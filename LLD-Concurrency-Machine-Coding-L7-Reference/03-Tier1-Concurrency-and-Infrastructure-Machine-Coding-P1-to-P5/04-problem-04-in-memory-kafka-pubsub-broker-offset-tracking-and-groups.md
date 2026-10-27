# P4 · In-Memory Kafka: Pub/Sub Broker with Partitions, Offsets, and Consumer Groups

> **Folder 03 · Problem 4 of 20.** Topic → partitions (an append-only segmented log) → consumer groups (partition ownership, offset commits, rebalancing). The L7 content is in three places:
> - **readers that never block writers;**
> - **generation-fenced commits**, so a zombie consumer can't move offsets;
> - **segment reclamation**, which the JVM's GC does for free and C++ must do explicitly (epoch-based reclamation).
>
> **Listing pair P4:** `MiniKafkaBroker.java` / `mini_kafka_broker.cpp`. Fencing is deterministic. Loss, order and torn-read checks are guaranteed invariants. Redelivery and contention counts are one measured run.

---

## 1. Problem and scope

**Functional:**
- `send(topic, key, value) → offset`;
- `read(partition, fromOffset, max)`;
- consumer groups: `join`/`leave`, partition assignment, `commit(partition, offset)`;
- retention: delete old segments.

**Guarantees to state up front:**
- **per-key ordering** (same key → same partition → append order);
- **at-least-once** delivery to a group (process, then commit);
- **no loss** of committed data;
- readers see only fully written records.

**Out of scope:** replication and ISR (Distributed Systems KB), exactly-once transactions (§8), disk persistence.

## 2. Domain model and invariants

| Element | Java | C++ |
|---|---|---|
| Partition log | `Record[][]` over absolute segment numbers; `volatile end` (high watermark); `volatile logStart` | `std::atomic<Segment*>` table; `atomic<i64>` end / log_start |
| Append | `ReentrantLock appendLock`: one writer section per partition | `std::mutex` |
| Read | Lock-free against appends; `StampedLock` optimistic read **against retention only** | Epoch-protected read; re-check of `log_start` after the copy |
| Reclamation | GC | Minimal epoch-based reclamation (EBR) |
| Group | `Assignment(generation, member → partitions)` published atomically; `commit` fenced by generation | same with `shared_ptr<const Assignment>` |

**Invariants:**
- **I1 (publication):** a reader that observes `end = e` sees every record with offset `< e` fully constructed. Records are written before the volatile/release store of `end`.
- **I2 (per-key order):** within a partition, records of one key from one producer appear in send order. Verified: 0 violations.
- **I3 (no loss):** every appended offset is processed at least once by the group. Verified: lost 0.
- **I4 (fencing):** a commit is accepted only from the partition's owner in the **current generation**.
- **I5 (no torn batches):** a read returns a contiguous run of offsets, or `OutOfRange`. Verified: 0 torn.

## 3. Concurrency and contention analysis

**Writers.** Appends to one partition serialize on its append lock. That's inherent: offset assignment is a sequence. Throughput scales with *partitions*, which is why Kafka's unit of parallelism is the partition. Each append writes the record, then publishes `end = off + 1` with a volatile (Java) or release (C++) store.

**Readers vs appends: no lock needed.** Records below `end` are immutable, so a reader that reads `end` (an acquire) and copies below it can't see a partially written record, and appends can't invalidate it. **The brief's StampedLock is therefore aimed at the wrong conflict if it guards appends.** Every append would take the write stamp and fail every optimistic read. Here the `StampedLock` versions only **retention**. Measured in Java: **542,719 optimistic reads validated against 808 failures** (0.15%) that retried under the read lock, while 2 M appends ran.

**Readers vs retention: the reclamation problem.**
- **Java:** retention nulls segment slots. A reader that raced with it may copy from a segment the GC still keeps alive. `validate()` (or the `logStart` re-check) rejects that copy, and the reader re-reads or gets `OutOfRange`. 1,452 out-of-range resets happened when readers fell behind the retention horizon.
- **C++:** freeing a segment while a reader is copying from it is use-after-free, *even if validation would reject the copy later*. The listing implements **epoch-based reclamation**:
  1. A reader announces the global epoch before touching segments, and goes idle after.
  2. Retention retires segments tagged with the current epoch and advances it.
  3. It frees a segment only when every active reader has announced a later epoch.

  1,946 segments were freed safely.
- **Why `seq_cst`?** The reader's "announce, then load the pointer" and retention's "advance, then scan the announcements" form a store→load (Dekker) pattern. Release/acquire would allow both sides to miss each other, which is exactly the outcome the litmus test in 01.3 §2.4 showed.

**Consumer groups.**
- The coordinator publishes one immutable `Assignment` per rebalance, with a monotonically increasing **generation**.
- Consumers notice a new generation, drop their positions, and restart from the committed offsets.
- `commit(member, generation, partition, offset)` succeeds only if the generation is current and the member owns the partition. In the deterministic test, consumer `a` tries to commit partition 1 with generation 1 after it moved to `b` in generation 2: **FENCED**. This is Kafka's generation/epoch fencing, and file 01's fencing token in another guise.
- **At-least-once** shows up as **redelivery**. A consumer that processed records but whose commit was fenced (it lost the partition in between) leaves them uncommitted, so the new owner processes them again. Java measured 192 redeliveries and 3 fenced commits when c2 was stopped mid-flight. In C++, c2 was joined before leaving, so all its processed records were committed: 0 redeliveries. Both satisfy I3. Duplicates must be absorbed by idempotent processing, or by transactions (§8).

## 4. Java 21 implementation

```java
// MiniKafkaBroker.java - P4: topic -> partitions (segmented log) -> consumer groups with fenced offset commits
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicIntegerArray;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.LongAdder;
import java.util.concurrent.locks.ReentrantLock;
import java.util.concurrent.locks.StampedLock;

public final class MiniKafkaBroker {

    record Record(String key, String value, long offset) {}

    sealed interface ReadResult permits Records, OutOfRange {}
    record Records(List<Record> records, long nextOffset) implements ReadResult {}
    record OutOfRange(long logStartOffset) implements ReadResult {}

    /**
     * Append-only log over absolutely numbered segments: segment k holds offsets [k*SEG, (k+1)*SEG).
     * Appends serialize on appendLock and publish a volatile end offset (the high watermark): a record
     * below `end` is immutable, so readers need no lock against appends. Only RETENTION (deleting whole
     * segments) can invalidate a reader, so the StampedLock versions retention alone.
     */
    static final class PartitionLog {
        static final int SEG = 1_024, MAX_SEGMENTS = 4_096;
        private final Record[][] table = new Record[MAX_SEGMENTS][];
        private final ReentrantLock appendLock = new ReentrantLock();
        private final StampedLock retention = new StampedLock();
        private volatile long end;                             // next offset; written under appendLock
        private volatile long logStart;                        // first readable offset; written under retention
        final LongAdder optimisticOk = new LongAdder(), optimisticFailed = new LongAdder();

        long append(String key, String value) {
            appendLock.lock();
            try {
                long off = end;
                int seg = (int) ((off / SEG) % MAX_SEGMENTS);
                if (off % SEG == 0) table[seg] = new Record[SEG];   // roll a new segment
                table[seg][(int) (off % SEG)] = new Record(key, value, off);
                end = off + 1;                                 // volatile write publishes the record
                return off;
            } finally {
                appendLock.unlock();
            }
        }

        ReadResult read(long from, int max) {
            long stamp = retention.tryOptimisticRead();
            ReadResult r = copy(from, max);
            if (retention.validate(stamp)) {
                optimisticOk.increment();
                return r;
            }
            optimisticFailed.increment();                      // retention ran meanwhile: re-read under the lock
            stamp = retention.readLock();
            try {
                return copy(from, max);
            } finally {
                retention.unlockRead(stamp);
            }
        }

        private ReadResult copy(long from, int max) {
            long start = logStart, hw = end;                   // volatile reads
            if (from < start) return new OutOfRange(start);
            List<Record> out = new ArrayList<>();
            for (long off = from; off < hw && out.size() < max; off++) {
                Record[] seg = table[(int) ((off / SEG) % MAX_SEGMENTS)];
                Record rec = seg == null ? null : seg[(int) (off % SEG)];
                if (rec == null || rec.offset() != off) break; // a torn optimistic read: validate() rejects it
                out.add(rec);
            }
            return new Records(out, from + out.size());
        }

        /** Delete whole segments strictly below `offset` (rounded down to a segment boundary). */
        void truncateBefore(long offset) {
            long stamp = retention.writeLock();
            try {
                long newStart = Math.min(offset, end) / SEG * SEG;
                for (long s = logStart / SEG; s < newStart / SEG; s++) table[(int) (s % MAX_SEGMENTS)] = null;
                if (newStart > logStart) logStart = newStart;
            } finally {
                retention.unlockWrite(stamp);
            }
        }

        long endOffset() {
            return end;
        }
    }

    static final class Topic {
        final PartitionLog[] partitions;

        Topic(int n) {
            partitions = new PartitionLog[n];
            for (int i = 0; i < n; i++) partitions[i] = new PartitionLog();
        }

        int partitionFor(String key) {                         // same key -> same partition -> per-key order
            return Math.floorMod(key.hashCode() * 0x9E3779B9, partitions.length);
        }

        long send(String key, String value) {
            return partitions[partitionFor(key)].append(key, value);
        }
    }

    /** Group coordinator: generation-numbered assignments; commits from stale generations are fenced. */
    static final class Group {
        record Assignment(int generation, Map<String, List<Integer>> byMember) {
            String owner(int partition) {
                for (var e : byMember.entrySet()) if (e.getValue().contains(partition)) return e.getKey();
                return null;
            }
        }

        private final int partitions;
        private final TreeSet<String> members = new TreeSet<>();
        final AtomicReference<Assignment> current = new AtomicReference<>(new Assignment(0, Map.of()));
        final ConcurrentHashMap<Integer, Long> committed = new ConcurrentHashMap<>();
        final LongAdder fencedCommits = new LongAdder();

        Group(int partitions) {
            this.partitions = partitions;
        }

        synchronized void join(String member) {
            members.add(member);
            rebalance();
        }

        synchronized void leave(String member) {
            members.remove(member);
            rebalance();
        }

        private void rebalance() {                             // round-robin over sorted members
            Map<String, List<Integer>> plan = new TreeMap<>();
            List<String> ms = new ArrayList<>(members);
            for (String m : ms) plan.put(m, new ArrayList<>());
            for (int p = 0; p < partitions && !ms.isEmpty(); p++) plan.get(ms.get(p % ms.size())).add(p);
            current.set(new Assignment(current.get().generation() + 1, plan));   // one atomic publication
        }

        /** Accepted only from the partition's owner in the CURRENT generation (Kafka's generation fencing). */
        synchronized boolean commit(String member, int generation, int partition, long offset) {
            Assignment a = current.get();
            if (a.generation() != generation || !member.equals(a.owner(partition))) {
                fencedCommits.increment();
                return false;
            }
            committed.merge(partition, offset, Math::max);
            return true;
        }
    }

    static final class Consumer implements Runnable {
        final String id;
        final Group group;
        final Topic topic;
        final AtomicIntegerArray[] seen;                       // [partition][offset] -> times processed
        final AtomicBoolean running = new AtomicBoolean(true);
        final AtomicBoolean producersDone;

        Consumer(String id, Group g, Topic t, AtomicIntegerArray[] seen, AtomicBoolean producersDone) {
            this.id = id;
            this.group = g;
            this.topic = t;
            this.seen = seen;
            this.producersDone = producersDone;
        }

        @Override public void run() {
            Map<Integer, Long> position = new TreeMap<>();
            int generation = -1;
            while (running.get()) {
                Group.Assignment a = group.current.get();
                if (a.generation() != generation) {            // rebalance: reset positions to the committed offsets
                    generation = a.generation();
                    position.clear();
                    for (int p : a.byMember().getOrDefault(id, List.of())) position.put(p, group.committed.getOrDefault(p, 0L));
                }
                boolean idle = true;
                for (var e : position.entrySet()) {
                    int p = e.getKey();
                    if (topic.partitions[p].read(e.getValue(), 64) instanceof Records(List<Record> recs, long next) && !recs.isEmpty()) {
                        idle = false;
                        for (Record r : recs) seen[p].incrementAndGet((int) r.offset());   // "process"
                        if (group.commit(id, generation, p, next)) e.setValue(next);       // at-least-once
                        else break;                            // fenced: a rebalance happened; re-read assignment
                    }
                }
                if (idle && producersDone.get()) Thread.onSpinWait();
            }
        }
    }

    public static void main(String[] args) throws Exception {
        int partitions = 6, producers = 4, perProducer = 30_000;
        Topic topic = new Topic(partitions);
        AtomicIntegerArray[] seen = new AtomicIntegerArray[partitions];
        for (int p = 0; p < partitions; p++) seen[p] = new AtomicIntegerArray(producers * perProducer);
        Group group = new Group(partitions);
        AtomicBoolean producersDone = new AtomicBoolean();
        List<Consumer> consumers = new ArrayList<>();
        List<Thread> consumerThreads = new ArrayList<>();
        for (String id : List.of("c1", "c2", "c3")) {
            Consumer c = new Consumer(id, group, topic, seen, producersDone);
            consumers.add(c);
            group.join(id);
            consumerThreads.add(Thread.ofPlatform().name(id).start(c));
        }

        System.out.println("== 1. 4 producers x 30,000 keyed messages into 6 partitions; 3-member group consuming ==");
        CountDownLatch produced = new CountDownLatch(producers);
        for (int pr = 0; pr < producers; pr++) {
            final int me = pr;
            Thread.ofPlatform().start(() -> {
                for (int i = 0; i < perProducer; i++) topic.send("k" + (i % 100), me + ":" + i);
                produced.countDown();
            });
        }
        Thread.sleep(30);
        Consumer c2 = consumers.get(1);
        c2.running.set(false);                                 // c2 crashes without committing its in-flight work
        group.leave("c2");
        Consumer c4 = new Consumer("c4", group, topic, seen, producersDone);
        consumers.add(c4);
        group.join("c4");
        consumerThreads.add(Thread.ofPlatform().name("c4").start(c4));
        produced.await();
        producersDone.set(true);
        long total = 0;
        for (PartitionLog log : topic.partitions) total += log.endOffset();
        while (true) {                                         // wait until every partition is fully committed
            long done = 0;
            for (int p = 0; p < partitions; p++) done += group.committed.getOrDefault(p, 0L);
            if (done == total) break;
            Thread.sleep(5);
        }
        for (Consumer c : consumers) c.running.set(false);
        for (Thread t : consumerThreads) t.join();

        long lost = 0, duplicates = 0, orderViolations = 0;
        for (int p = 0; p < partitions; p++) {
            long end = topic.partitions[p].endOffset();
            Map<String, Integer> lastSeqPerProducerKey = new java.util.HashMap<>();
            Records all = (Records) topic.partitions[p].read(0, (int) end);
            for (Record r : all.records()) {
                int times = seen[p].get((int) r.offset());
                if (times == 0) lost++;
                if (times > 1) duplicates += times - 1;
                String[] pv = r.value().split(":");
                String k = pv[0] + "/" + r.key();
                int seq = Integer.parseInt(pv[1]);
                Integer prev = lastSeqPerProducerKey.put(k, seq);
                if (prev != null && seq <= prev) orderViolations++;   // per-key order inside the log
            }
        }
        System.out.printf("  appended %,d | lost %d | redelivered (at-least-once) %,d | per-key order violations %d | fenced commits %,d | generation %d%n",
                total, lost, duplicates, orderViolations, group.fencedCommits.sum(), group.current.get().generation());

        System.out.println("== 2. Zombie fencing, deterministic ==");
        Group g = new Group(2);
        g.join("a");
        int genA = g.current.get().generation();
        g.join("b");                                           // rebalance: generation +1, p1 moves to b
        boolean zombie = g.commit("a", genA, 1, 500);
        int gen = g.current.get().generation();
        boolean owner = g.commit("b", gen, 1, 500);
        System.out.println("  a commits p1 with generation " + genA + " after rebalance -> " + (zombie ? "ACCEPTED" : "FENCED")
                + "; b commits p1 with generation " + gen + " -> " + (owner ? "ACCEPTED" : "FENCED"));

        System.out.println("== 3. Retention racing readers: 2 readers chase 2,000,000 appends, truncation every 2,048 ==");
        PartitionLog log = new PartitionLog();
        AtomicBoolean stop = new AtomicBoolean();
        LongAdder delivered = new LongAdder(), outOfRange = new LongAdder(), torn = new LongAdder();
        List<Thread> readers = new ArrayList<>();
        for (int r = 0; r < 2; r++) {
            readers.add(Thread.ofPlatform().start(() -> {
                long pos = 0;
                while (!stop.get()) {
                    switch (log.read(pos, 256)) {
                        case Records(List<Record> recs, long next) -> {
                            for (int i = 0; i < recs.size(); i++) if (recs.get(i).offset() != pos + i) torn.increment();
                            delivered.add(recs.size());
                            pos = next;
                        }
                        case OutOfRange(long start) -> {
                            outOfRange.increment();
                            pos = start;                       // the consumer reset policy: earliest available
                        }
                    }
                }
            }));
        }
        Thread writer = Thread.ofPlatform().start(() -> {
            for (int i = 1; i <= 2_000_000; i++) {
                log.append("k", "v");
                if (i % 2_048 == 0) log.truncateBefore(i - 4_096);   // keep only the newest ~4 segments
                if (i % 64 == 0) Thread.onSpinWait();
            }
        });
        writer.join();
        stop.set(true);
        for (Thread t : readers) t.join();
        System.out.printf("  delivered %,d | out-of-range resets %,d | torn batches returned %d | optimistic ok %,d, failed->locked %,d%n",
                delivered.sum(), outOfRange.sum(), torn.sum(), log.optimisticOk.sum(), log.optimisticFailed.sum());

        boolean ok = lost == 0 && orderViolations == 0 && !zombie && owner && torn.sum() == 0;
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (fencing deterministic; counts one measured run; I2/I3/I5 guaranteed):**

```text
== 1. 4 producers x 30,000 keyed messages into 6 partitions; 3-member group consuming ==
  appended 120,000 | lost 0 | redelivered (at-least-once) 192 | per-key order violations 0 | fenced commits 3 | generation 5
== 2. Zombie fencing, deterministic ==
  a commits p1 with generation 1 after rebalance -> FENCED; b commits p1 with generation 2 -> ACCEPTED
== 3. Retention racing readers: 2 readers chase 2,000,000 appends, truncation every 2,048 ==
  delivered 1,711,872 | out-of-range resets 1,452 | torn batches returned 0 | optimistic ok 542,719, failed->locked 808
SELF-TEST OK
```

## 5. C++23 implementation

```cpp
// mini_kafka_broker.cpp - P4: segmented partition log + epoch-based reclamation + consumer groups with fencing
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <latch>
#include <limits>
#include <map>
#include <memory>
#include <mutex>
#include <print>
#include <set>
#include <stop_token>
#include <string>
#include <thread>
#include <unordered_map>
#include <variant>
#include <vector>

using u64 = std::uint64_t;
using i64 = std::int64_t;

struct Record { std::string key, value; i64 offset = -1; };
struct Records { std::vector<Record> records; i64 next; };
struct OutOfRange { i64 log_start; };
using ReadResult = std::variant<Records, OutOfRange>;

/**
 * Epoch-based reclamation, minimal: the C++ answer to "the GC keeps it alive". Readers announce the
 * epoch they entered; retention retires segments tagged with the current epoch and frees them only
 * when every active reader announced a later epoch. Announce (store) then read the pointer, and on the
 * other side bump-epoch then scan the announcements: a store->load (Dekker) pattern, so both are seq_cst.
 */
class Epochs {
    static constexpr u64 kIdle = std::numeric_limits<u64>::max();
    std::atomic<u64> global_{1};
    std::array<std::atomic<u64>, 8> slots_;  // one per registered reader
public:
    Epochs() {
        for (auto& s : slots_) s.store(kIdle);
    }
    void enter(std::size_t r) { slots_[r].store(global_.load(std::memory_order_seq_cst), std::memory_order_seq_cst); }
    void exit(std::size_t r) { slots_[r].store(kIdle, std::memory_order_release); }
    u64 advance() { return global_.fetch_add(1, std::memory_order_seq_cst); }  // returns the retiring epoch
    u64 min_active() const {
        u64 m = kIdle;
        for (const auto& s : slots_) m = std::min(m, s.load(std::memory_order_seq_cst));
        return m;
    }
};

class PartitionLog {
    static constexpr i64 kSeg = 1'024, kMaxSegments = 4'096;
    struct Segment { std::array<Record, kSeg> recs; };
    std::array<std::atomic<Segment*>, kMaxSegments> table_{};
    std::mutex append_m_, retire_m_;
    std::atomic<i64> end_{0}, log_start_{0};
    std::vector<std::pair<u64, Segment*>> retired_;  // (epoch, segment), guarded by retire_m_
public:
    Epochs epochs;
    std::atomic<u64> stable_reads{0}, retention_moved{0}, freed{0};

    ~PartitionLog() {
        for (auto& s : table_) delete s.load();
        for (auto& [e, seg] : retired_) delete seg;
    }
    i64 append(std::string key, std::string value) {
        std::scoped_lock l(append_m_);
        const i64 off = end_.load(std::memory_order_relaxed);
        auto& slot = table_[static_cast<std::size_t>((off / kSeg) % kMaxSegments)];
        if (off % kSeg == 0) slot.store(new Segment(), std::memory_order_release);  // roll a segment
        slot.load(std::memory_order_relaxed)->recs[static_cast<std::size_t>(off % kSeg)] = Record{std::move(key), std::move(value), off};
        end_.store(off + 1, std::memory_order_release);  // publishes the record
        return off;
    }
    ReadResult read(std::size_t reader, i64 from, int max) {
        epochs.enter(reader);
        const i64 start = log_start_.load(std::memory_order_acquire), hw = end_.load(std::memory_order_acquire);
        ReadResult result = OutOfRange{start};
        if (from >= start) {
            Records out{{}, from};
            for (i64 off = from; off < hw && static_cast<int>(out.records.size()) < max; ++off) {
                const Segment* seg = table_[static_cast<std::size_t>((off / kSeg) % kMaxSegments)].load(std::memory_order_acquire);
                if (!seg) break;
                out.records.push_back(seg->recs[static_cast<std::size_t>(off % kSeg)]);  // memory stays valid: epoch held
            }
            out.next = from + static_cast<i64>(out.records.size());
            if (log_start_.load(std::memory_order_acquire) > from) {  // retention passed us during the copy
                retention_moved.fetch_add(1, std::memory_order_relaxed);
                result = OutOfRange{log_start_.load()};
            } else {
                stable_reads.fetch_add(1, std::memory_order_relaxed);
                result = std::move(out);
            }
        }
        epochs.exit(reader);
        return result;
    }
    void truncate_before(i64 offset) {
        std::scoped_lock l(retire_m_);
        const i64 new_start = std::min(offset, end_.load()) / kSeg * kSeg;
        const i64 old_start = log_start_.load();
        if (new_start <= old_start) return;
        log_start_.store(new_start, std::memory_order_seq_cst);
        const u64 tag = epochs.advance();
        for (i64 s = old_start / kSeg; s < new_start / kSeg; ++s)
            if (Segment* seg = table_[static_cast<std::size_t>(s % kMaxSegments)].exchange(nullptr)) retired_.emplace_back(tag, seg);
        const u64 safe = epochs.min_active();  // free only what no active reader can still see
        std::erase_if(retired_, [&](const std::pair<u64, Segment*>& r) {
            if (r.first >= safe) return false;
            delete r.second;
            freed.fetch_add(1, std::memory_order_relaxed);
            return true;
        });
    }
    i64 end_offset() const { return end_.load(); }
};

class Topic {
public:
    std::vector<std::unique_ptr<PartitionLog>> partitions;
    explicit Topic(int n) {
        for (int i = 0; i < n; ++i) partitions.push_back(std::make_unique<PartitionLog>());
    }
    std::size_t partition_for(const std::string& key) const { return std::hash<std::string>{}(key) % partitions.size(); }
    i64 send(const std::string& key, const std::string& value) { return partitions[partition_for(key)]->append(key, value); }
};

class Group {
public:
    struct Assignment {
        int generation;
        std::map<std::string, std::vector<int>> by_member;
        std::string owner(int p) const {
            for (const auto& [m, ps] : by_member)
                if (std::ranges::find(ps, p) != ps.end()) return m;
            return {};
        }
    };
private:
    int partitions_;
    std::mutex m_;
    std::set<std::string> members_;
    std::shared_ptr<const Assignment> current_ = std::make_shared<const Assignment>(Assignment{0, {}});
    std::unordered_map<int, i64> committed_;
    void rebalance() {
        Assignment next{current_->generation + 1, {}};
        std::vector<std::string> ms(members_.begin(), members_.end());
        for (const auto& m : ms) next.by_member[m];
        for (int p = 0; p < partitions_ && !ms.empty(); ++p) next.by_member[ms[static_cast<std::size_t>(p) % ms.size()]].push_back(p);
        current_ = std::make_shared<const Assignment>(std::move(next));
    }
public:
    std::atomic<u64> fenced{0};
    explicit Group(int partitions) : partitions_(partitions) {}
    void join(const std::string& m) {
        std::scoped_lock l(m_);
        members_.insert(m);
        rebalance();
    }
    void leave(const std::string& m) {
        std::scoped_lock l(m_);
        members_.erase(m);
        rebalance();
    }
    std::shared_ptr<const Assignment> assignment() {
        std::scoped_lock l(m_);
        return current_;
    }
    bool commit(const std::string& member, int generation, int p, i64 offset) {  // generation fencing
        std::scoped_lock l(m_);
        if (current_->generation != generation || current_->owner(p) != member) {
            fenced.fetch_add(1);
            return false;
        }
        auto& c = committed_[p];
        c = std::max(c, offset);
        return true;
    }
    i64 committed(int p) {
        std::scoped_lock l(m_);
        auto it = committed_.find(p);
        return it == committed_.end() ? 0 : it->second;
    }
};

using Seen = std::vector<std::unique_ptr<std::atomic<int>[]>>;

void consume(std::stop_token st, const std::string& id, std::size_t reader, Group& group, Topic& topic, Seen& seen) {
    std::map<int, i64> position;
    int generation = -1;
    while (!st.stop_requested()) {
        const auto a = group.assignment();
        if (a->generation != generation) {  // rebalance: restart from committed offsets
            generation = a->generation;
            position.clear();
            if (auto it = a->by_member.find(id); it != a->by_member.end())
                for (int p : it->second) position[p] = group.committed(p);
        }
        for (auto& [p, pos] : position) {
            auto r = topic.partitions[static_cast<std::size_t>(p)]->read(reader, pos, 64);
            if (auto* recs = std::get_if<Records>(&r); recs && !recs->records.empty()) {
                for (const auto& rec : recs->records) seen[static_cast<std::size_t>(p)][static_cast<std::size_t>(rec.offset)].fetch_add(1);
                if (group.commit(id, generation, p, recs->next)) pos = recs->next;
                else break;  // fenced: rebalance in progress
            }
        }
    }
}

int main() {
    constexpr int kPartitions = 6, kProducers = 4, kPerProducer = 30'000;
    Topic topic(kPartitions);
    Seen seen;
    for (int p = 0; p < kPartitions; ++p) seen.push_back(std::make_unique<std::atomic<int>[]>(kProducers * kPerProducer));
    Group group(kPartitions);
    std::println("== 1. 4 producers x 30,000 keyed messages into 6 partitions; 3-member group consuming ==");
    std::map<std::string, std::jthread> consumers;
    std::size_t reader_slot = 0;
    for (const char* id : {"c1", "c2", "c3"}) {
        group.join(id);
        const std::size_t slot = reader_slot++;
        consumers.emplace(id, std::jthread([&, id = std::string(id), slot](std::stop_token st) { consume(st, id, slot, group, topic, seen); }));
    }
    {
        std::vector<std::jthread> producers;
        for (int pr = 0; pr < kProducers; ++pr)
            producers.emplace_back([&, pr] {
                for (int i = 0; i < kPerProducer; ++i) topic.send("k" + std::to_string(i % 100), std::to_string(pr) + ":" + std::to_string(i));
            });
        std::this_thread::sleep_for(std::chrono::milliseconds(30));
        consumers.erase("c2");  // c2 stops (joined) without committing in-flight work
        group.leave("c2");
        group.join("c4");
        const std::size_t slot = reader_slot++;
        consumers.emplace("c4", std::jthread([&, slot](std::stop_token st) { consume(st, "c4", slot, group, topic, seen); }));
    }
    i64 total = 0;
    for (const auto& log : topic.partitions) total += log->end_offset();
    while (true) {
        i64 done = 0;
        for (int p = 0; p < kPartitions; ++p) done += group.committed(p);
        if (done == total) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    consumers.clear();
    i64 lost = 0, dup = 0, order_violations = 0;
    for (int p = 0; p < kPartitions; ++p) {
        auto& log = *topic.partitions[static_cast<std::size_t>(p)];
        const auto all = std::get<Records>(log.read(7, 0, static_cast<int>(log.end_offset())));
        std::unordered_map<std::string, int> last;
        for (const auto& r : all.records) {
            const int times = seen[static_cast<std::size_t>(p)][static_cast<std::size_t>(r.offset)].load();
            lost += times == 0;
            dup += times > 1 ? times - 1 : 0;
            const auto colon = r.value.find(':');
            const std::string k = r.value.substr(0, colon) + "/" + r.key;
            const int seq = std::stoi(r.value.substr(colon + 1));
            auto [it, fresh] = last.try_emplace(k, seq);
            if (!fresh) {
                if (seq <= it->second) ++order_violations;
                it->second = seq;
            }
        }
    }
    std::println("  appended {} | lost {} | redelivered (at-least-once) {} | per-key order violations {} | fenced commits {} | generation {}",
                 total, lost, dup, order_violations, group.fenced.load(), group.assignment()->generation);

    std::println("== 2. Zombie fencing, deterministic ==");
    Group g(2);
    g.join("a");
    const int gen_a = g.assignment()->generation;
    g.join("b");
    const bool zombie = g.commit("a", gen_a, 1, 500);
    const int gen = g.assignment()->generation;
    const bool owner = g.commit("b", gen, 1, 500);
    std::println("  a commits p1 with generation {} after rebalance -> {}; b commits p1 with generation {} -> {}", gen_a,
                 zombie ? "ACCEPTED" : "FENCED", gen, owner ? "ACCEPTED" : "FENCED");

    std::println("== 3. Retention racing readers: 2 readers chase 2,000,000 appends, truncation every 2,048 (EBR frees segments) ==");
    PartitionLog log;
    std::atomic<bool> stop{false};
    std::atomic<i64> delivered{0}, oor{0}, torn{0};
    {
        std::vector<std::jthread> readers;
        for (std::size_t r = 0; r < 2; ++r)
            readers.emplace_back([&, r] {
                i64 pos = 0;
                while (!stop.load()) {
                    auto res = log.read(r, pos, 256);
                    if (auto* recs = std::get_if<Records>(&res)) {
                        for (std::size_t i = 0; i < recs->records.size(); ++i) torn += recs->records[i].offset != pos + static_cast<i64>(i);
                        delivered += static_cast<i64>(recs->records.size());
                        pos = recs->next;
                    } else {
                        ++oor;
                        pos = std::get<OutOfRange>(res).log_start;
                    }
                }
            });
        std::jthread writer([&] {
            for (i64 i = 1; i <= 2'000'000; ++i) {
                log.append("k", "v");
                if (i % 2'048 == 0) log.truncate_before(i - 4'096);
            }
        });
        writer.join();
        stop.store(true);
    }
    std::println("  delivered {} | out-of-range resets {} | torn batches returned {} | stable reads {}, retention moved mid-read {} | segments freed by EBR {}",
                 delivered.load(), oor.load(), torn.load(), log.stable_reads.load(), log.retention_moved.load(), log.freed.load());
    const bool ok = lost == 0 && order_violations == 0 && !zombie && owner && torn.load() == 0 && log.freed.load() > 0;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 1. 4 producers x 30,000 keyed messages into 6 partitions; 3-member group consuming ==
  appended 120000 | lost 0 | redelivered (at-least-once) 0 | per-key order violations 0 | fenced commits 0 | generation 5
== 2. Zombie fencing, deterministic ==
  a commits p1 with generation 1 after rebalance -> FENCED; b commits p1 with generation 2 -> ACCEPTED
== 3. Retention racing readers: 2 readers chase 2,000,000 appends, truncation every 2,048 (EBR frees segments) ==
  delivered 4000000 | out-of-range resets 0 | torn batches returned 0 | stable reads 1206620, retention moved mid-read 0 | segments freed by EBR 1946
SELF-TEST OK
```

**Output, Clang 21.1:**

```text
== 1. 4 producers x 30,000 keyed messages into 6 partitions; 3-member group consuming ==
  appended 120000 | lost 0 | redelivered (at-least-once) 0 | per-key order violations 0 | fenced commits 0 | generation 5
== 2. Zombie fencing, deterministic ==
  a commits p1 with generation 1 after rebalance -> FENCED; b commits p1 with generation 2 -> ACCEPTED
== 3. Retention racing readers: 2 readers chase 2,000,000 appends, truncation every 2,048 (EBR frees segments) ==
  delivered 4000000 | out-of-range resets 0 | torn batches returned 0 | stable reads 672696, retention moved mid-read 0 | segments freed by EBR 1946
SELF-TEST OK
```

## 6. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Log | `List<Message>` + `synchronized` | Per-partition lock; offsets | Segmented append-only log; volatile high-watermark publication; readers lock-free against appends; StampedLock or EBR only for retention |
| Ordering | "FIFO queue" | Per-partition order | Per-key order via key → partition; explains why there's no global order, and its cost |
| Groups | Every consumer reads everything | Assign partitions to consumers | Generation-numbered assignments; commits fenced by generation; rebalance resets to the committed offsets; at-least-once with measured redelivery |
| Retention | Never deletes | Delete old messages under a lock | Whole-segment deletion; reader `OutOfRange` + reset policy; safe reclamation (GC vs EBR) |
| Testing | A demo prints messages | Single-threaded tests | Concurrent producers + a rebalancing group + a retention race, with invariants for loss, order, torn reads and fencing |

## 7. Curveballs and 5-minute refactors

| Curveball | Response |
|---|---|
| "Exactly-once processing" | Idempotent producer (producer id + sequence per partition, broker de-dup) plus transactional commit of the output *and* the input offsets together. Or make consumers idempotent by `(partition, offset)` |
| "Consumers must not stop the world during rebalance" | Incremental cooperative rebalancing: only moved partitions are revoked; generations still fence |
| "Slow consumer, fast producer" | The log *is* the buffer: lag = `end − committed`; alert on lag; retention bounds memory, so a consumer that falls behind retention resets to earliest/latest by policy |
| "Key compaction (keep the last value per key)" | A compactor rewrites old segments keeping the newest offset per key; readers see segments swapped atomically (the same retention/EBR machinery) |
| "Replicate partitions" | A leader appends, followers fetch, the high watermark advances when the ISR acknowledges. Readers read only below the HW, which is exactly I1, now across nodes |

## 8. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "Readers and writers on the same partition. Which lock?"</b></summary>

**L5:** "A ReadWriteLock: readers share, writers exclusive."

**Why it fails:** every append takes the write lock and stalls all readers. An optimistic StampedLock fails every read for the same reason.

**L7 defence:** "Appends don't modify existing records. I publish the high watermark with a volatile store after writing the record, and readers copy below it with no lock. Only retention deletes data, so only retention needs versioning: a StampedLock in Java (0.15% optimistic failures measured during 2 M appends) and epoch-based reclamation in C++ to make freeing safe."
</details>

<details>
<summary><b>Q2 ⚡ "A consumer paused for 30 s (GC), lost its partitions, then woke up and committed. What happens?"</b></summary>

**L5:** "Its offsets are committed."

**Why it fails:** the new owner may already be ahead. The zombie's commit moves the offset backward (re-processing) or forward past unprocessed records (loss).

**L7 defence:** "Commits carry the generation. The coordinator accepts them only from the current owner in the current generation, so the zombie is fenced (shown deterministically). That's the same idea as a fencing token for leases."
</details>

<details>
<summary><b>Q3 🧊 "Your C++ reader validated the copy. Why isn't that enough when retention frees the segment?"</b></summary>

**L5:** "Validation rejects stale data."

**Why it fails:** validation happens *after* the copy. If the segment was freed during the copy, the reader already dereferenced freed memory, which is undefined behaviour before any check runs.

**L7 defence:** "Separate logical deletion from reclamation. Readers announce an epoch; retention retires segments and frees them only once no active reader is in an older epoch. Announce/scan is a store→load pattern, so those operations are `seq_cst`. Alternatives: hazard pointers or reference counting. Java gets this from the GC."
</details>

## 9. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| Readers stall during heavy writes | RW lock / optimistic read invalidated by appends | High-watermark publication; version only retention |
| Consumers see half-written messages | `end` published before the record write | Write the record, then the release store of `end` |
| Offsets jump backward after a rebalance | Zombie commits | Generation fencing |
| Duplicate processing after a rebalance | At-least-once semantics | Idempotent handlers / transactions; measure redelivery |
| C++ crash or garbage under retention | Segments freed while readers copy | EBR / hazard pointers / refcounting |
| Unbounded memory | No retention | Segment-based retention + lag alerts |

- [ ] Per-key order guaranteed by key → partition; no global-order promise.
- [ ] Records are published by the high-watermark release store; readers are lock-free against appends.
- [ ] Retention conflicts are handled by versioning (Java) and safe reclamation (C++).
- [ ] Commits are fenced by generation; a rebalance resets positions to committed offsets.
- [ ] Tests assert no loss, per-key order, no torn reads, and fencing.

## 10. References

- Jay Kreps, Neha Narkhede, Jun Rao, "Kafka: a Distributed Messaging System for Log Processing", NetDB 2011. <https://www.microsoft.com/en-us/research/wp-content/uploads/2017/09/Kafka.pdf>
- Apache Kafka design documentation (log, consumer groups, offsets). <https://kafka.apache.org/documentation/#design>
- KIP-848, The Next Generation of the Consumer Rebalance Protocol. <https://cwiki.apache.org/confluence/display/KAFKA/KIP-848%3A+The+Next+Generation+of+the+Consumer+Rebalance+Protocol>
- Keir Fraser, *Practical lock-freedom* (epoch-based reclamation), Cambridge TR-579, 2004. <https://www.cl.cam.ac.uk/techreports/UCAM-CL-TR-579.pdf>
- In this KB: [01.3 StampedLock and the store-buffer litmus](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md) · [02.3 Event-bus ordering](../02-Design-Patterns-Reimagined-for-High-Throughput-Java/03-observer-event-bus-command-undo-redo-and-double-dispatch-visitor.md) · P17 MPSC logger (Folder 06)
