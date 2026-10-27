# 07.1 · Read-Write Locks: Reader vs Writer Preference, a Custom AQS Synchronizer, and Optimistic Reads

> **Folder 07 · File 1 of 3.** "Implement a read-write lock" is a bar-raiser favourite. The first version usually works, and **starves writers**. This file covers:
> - **measuring** starvation under a read flood;
> - two ways to give writers preference;
> - how `AbstractQueuedSynchronizer` really works, by writing a synchronizer on it;
> - the AQS trap that makes the "obvious" strict writer preference **lose wakeups**;
> - why optimistic reads (`StampedLock`, seqlock) beat every lock when reads dominate.
>
> **Listing pair 07.1:** `RwLocks.java` / `rw_locks.cpp`. One measured run per build. Torn reads were 0 for every lock in every build.

---

## 1. First principles

**The contract:**
- many readers **or** one writer;
- no reader observes a half-applied write.

**The policy is the hard part:**

| Policy | Who enters when a writer is waiting? | Failure mode |
|---|---|---|
| **Reader preference** | New readers keep entering while any reader is inside | Writers starve under a continuous read stream |
| **Writer preference** | New readers wait once a writer waits | Readers wait behind bursts of writers; throughput drops with frequent writes |
| **Fair (FIFO)** | Strict arrival order | Batching lost: readers alternate with writers |
| **Optimistic reads** | Readers don't lock at all; they validate a version afterwards | Writers never wait for readers; readers retry when a write intervened |

**Choose by workload:**
- configuration and routing tables, with mostly reads and rare writes that must land promptly: writer preference or optimistic reads;
- balanced mixes: often just a mutex. A RW lock's bookkeeping costs more than it saves for short critical sections (measured in [01.3](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md)).

## 2. AQS from the inside

`AbstractQueuedSynchronizer` is the engine under `ReentrantLock`, `Semaphore`, `CountDownLatch` and `ReentrantReadWriteLock`. You supply the **state transitions**; AQS supplies the **waiting**.

**What you write:**
- **State:** one `int` (`getState`, `setState`, `compareAndSetState`). In `AqsRwLock`, `state = readers`, or `-1` while a writer holds it.
- **Exclusive mode:** `tryAcquire` / `tryRelease`. The writer is `compareAndSetState(0, -1)`, and release is `setState(0)`.
- **Shared mode:** `tryAcquireShared` returns ≥ 0 on success, < 0 to queue. `tryReleaseShared` returns `true` when waiters should be woken: here, when the **last** reader leaves.

**What AQS does around them:**
1. **The queue:** a variant of the CLH lock queue. A thread whose `try*` fails is enqueued as a node, spins briefly, then **parks**.
2. **Release:** `release` / `releaseShared` unpark the head's successor.
3. **Shared propagation:** a woken shared node that succeeds wakes the next shared node. That's how a batch of readers enters together after a writer leaves.
4. **Extras:** cancellation (timeouts, interrupts) unlinks nodes, and `ConditionObject` gives exclusive-mode condition queues.

**The trap: strict writer preference loses wakeups on AQS.** The obvious rule is "a reader fails `tryAcquireShared` whenever *any* writer is waiting". Here is how it breaks:
1. A reader R queues while writer W1 holds the lock.
2. Writer W2 queues behind R.
3. W1 releases, and AQS wakes R, the head's successor.
4. R retries, sees "a writer is waiting", fails, and **parks again**.
5. Nobody wakes W2, because the release already happened. The lock is idle, with everyone asleep.

`AqsRwLock` uses the JDK's own rule instead: readers queue if a writer holds the lock **or the first queued thread is a writer**. Because that writer is at the head, it is the node that gets woken. The **strict** variant belongs on a monitor or mutex + condition variables, where `notifyAll` re-evaluates every waiter; that is `WriterPreferenceMonitor` / `WriterPreference`.

## 3. Measured: 8 readers in a tight loop, 1 writer that wants in every few microseconds, 1 second

| Lock | Java (writes · writer p99 · reads) | GCC 16.2 | Clang 21.1 |
|---|---|---|---|
| **Reader preference** | **16 writes · p99 1.0 s** · 3.46 M | 466 · p99 8.5 ms (max 11 ms) · 2.11 M | 69 · p99 81.5 ms · 3.22 M |
| Writer preference (monitor / mutex + 2 cvs) | 8,902 · 87 µs · 1.87 M | 9,760 · 42 µs · 1.54 M | 9,965 · 74 µs · 2.18 M |
| Custom AQS, writer-first-in-queue (Java) / `std::shared_mutex` (C++) | 11,208 · 51 µs · 4.63 M | 11,215 · 37 µs · 1.46 M (libstdc++/MinGW) | 10,230 · 74 µs · 2.52 M (libc++) |
| `ReentrantReadWriteLock` nonfair (Java) / state-word spinlock (C++) | 10,553 · 50 µs · 3.17 M | 13,072 · 7 µs · 9.07 M | 13,753 · 8 µs · 9.42 M |
| **`StampedLock` optimistic reads (Java) / seqlock (C++)** | 10,700 · 3 µs · **328 M** | 11,672 · 0 µs · **624 M** | 10,652 · 2 µs · **1,721 M** |

**Reading the numbers:**
- **Reader preference starves the writer.** In Java the writer got in 16 times in a second, and its worst wait was the whole run.
- **Writer preference makes writes land within tens of µs** and pays with fewer reads (1.5–2.2 M vs 2.1–3.5 M).
- **AQS beats the monitor for reads** (4.63 M vs 1.87 M) with the same writer latency. Readers that succeed in `tryAcquireShared` never touch a monitor, and waiting threads park instead of contending on one lock word.
- **`std::shared_mutex`'s policy is implementation-defined.** Both standard libraries let writers through here. On other platforms (a glibc `pthread_rwlock` defaults to reader preference) the same code can starve writers. Measure on your target, or wrap with an explicit policy.
- **The state-word spinlock is fastest** on this 8-reader, 1-writer box, but it *spins*. With more threads than cores it burns CPU that AQS would have parked. That's the trade AQS exists to make.
- **Optimistic reads win by two orders of magnitude.** Readers write nothing shared (no reader count), so there's no cache-line ping-pong. Writers never wait for readers, so the writer p99 is ~0–3 µs.
  - **The cost:** readers must tolerate a retry and copy small data.
  - **The C++ seqlock** needs atomics (relaxed) for the racy copy, plus an acquire fence before re-checking the sequence. A plain array would be a data race, which is undefined behaviour.

## 4. Java 21 implementation

```java
// RwLocks.java - 07.1: reader- vs writer-preference RW locks, a custom AQS synchronizer, RRWL and StampedLock under a read flood
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.LongAdder;
import java.util.concurrent.locks.AbstractQueuedSynchronizer;
import java.util.concurrent.locks.ReentrantReadWriteLock;
import java.util.concurrent.locks.StampedLock;

public final class RwLocks {

    interface RwLock {
        void readLock();

        void readUnlock();

        void writeLock();

        void writeUnlock();
    }

    /** Waits on a monitor without letting an interrupt break the lock protocol (the flag is restored for the caller). */
    static void await(Object monitor) {
        try {
            monitor.wait();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    /** Reader preference: a reader enters whenever no writer is ACTIVE. A steady stream of readers starves writers. */
    static final class ReaderPreference implements RwLock {
        int readers;                                                   // guarded by this
        boolean writer;

        @Override
        public synchronized void readLock() {
            while (writer) await(this);
            readers++;
        }

        @Override
        public synchronized void readUnlock() {
            if (--readers == 0) notifyAll();
        }

        @Override
        public synchronized void writeLock() {
            while (writer || readers > 0) await(this);
            writer = true;
        }

        @Override
        public synchronized void writeUnlock() {
            writer = false;
            notifyAll();
        }
    }

    /** Strict writer preference on a monitor: once a writer WAITS, new readers wait too. Correct, simple, not queue-fair. */
    static final class WriterPreferenceMonitor implements RwLock {
        int readers, waitingWriters;                                   // guarded by this
        boolean writer;

        @Override
        public synchronized void readLock() {
            while (writer || waitingWriters > 0) await(this);
            readers++;
        }

        @Override
        public synchronized void readUnlock() {
            if (--readers == 0) notifyAll();
        }

        @Override
        public synchronized void writeLock() {
            waitingWriters++;
            while (writer || readers > 0) await(this);
            waitingWriters--;
            writer = true;
        }

        @Override
        public synchronized void writeUnlock() {
            writer = false;
            notifyAll();
        }
    }

    /**
     * A custom AQS synchronizer. state = number of readers, or -1 while a writer holds it. Writer preference the way
     * the JDK's RRWL does it: a reader blocks if a writer holds the lock OR the FIRST queued thread is a writer. (Strict
     * "block if any writer waits" loses wakeups on AQS: a reader woken at the head fails, re-parks, and the writer queued
     * behind it is never signalled.)
     */
    static final class AqsRwLock implements RwLock {
        static final class Sync extends AbstractQueuedSynchronizer {
            private static final long serialVersionUID = 1L;
            final transient Set<Thread> queuedWriters = ConcurrentHashMap.newKeySet();

            int state() {                                              // getState() is protected to AQS's own package
                return getState();
            }

            boolean firstQueuedIsWriter() {
                Thread first = getFirstQueuedThread();
                return first != null && queuedWriters.contains(first);
            }

            @Override
            protected int tryAcquireShared(int unused) {
                for (;;) {
                    int s = getState();
                    if (s < 0 || firstQueuedIsWriter()) return -1;     // a writer holds it, or is next in line: queue
                    if (compareAndSetState(s, s + 1)) return 1;
                }
            }

            @Override
            protected boolean tryReleaseShared(int unused) {
                for (;;) {
                    int s = getState();
                    if (compareAndSetState(s, s - 1)) return s == 1;   // the last reader out wakes the queue
                }
            }

            @Override
            protected boolean tryAcquire(int unused) {
                return compareAndSetState(0, -1);
            }

            @Override
            protected boolean tryRelease(int unused) {
                setState(0);
                return true;
            }

            @Override
            protected boolean isHeldExclusively() {
                return getState() < 0;
            }
        }

        final Sync sync = new Sync();

        @Override
        public void readLock() {
            sync.acquireShared(1);
        }

        @Override
        public void readUnlock() {
            sync.releaseShared(1);
        }

        @Override
        public void writeLock() {
            sync.queuedWriters.add(Thread.currentThread());
            try {
                sync.acquire(1);
            } finally {
                sync.queuedWriters.remove(Thread.currentThread());
            }
        }

        @Override
        public void writeUnlock() {
            sync.release(1);
        }
    }

    static final class Rrwl implements RwLock {
        final ReentrantReadWriteLock l = new ReentrantReadWriteLock();

        @Override
        public void readLock() {
            l.readLock().lock();
        }

        @Override
        public void readUnlock() {
            l.readLock().unlock();
        }

        @Override
        public void writeLock() {
            l.writeLock().lock();
        }

        @Override
        public void writeUnlock() {
            l.writeLock().unlock();
        }
    }

    // ---- the shared data: 8 longs that a writer always sets to one value; a reader that sees two values saw a torn write

    static final long[] DATA = new long[8];

    static boolean consistent(long[] snap) {
        for (long v : snap)
            if (v != snap[0]) return false;
        return true;
    }

    record Result(String name, long reads, long writes, long maxWaitUs, long p99WaitUs, long torn) {}

    static Result flood(String name, RwLock lock, StampedLock stamped) throws Exception {
        Arrays.fill(DATA, 0);
        LongAdder reads = new LongAdder(), torn = new LongAdder();
        AtomicBoolean running = new AtomicBoolean(true);
        CyclicBarrier start = new CyclicBarrier(10);
        CountDownLatch done = new CountDownLatch(9);
        AtomicReference<Exception> failure = new AtomicReference<>();
        List<Long> waits = new ArrayList<>();
        for (int r = 0; r < 8; r++)
            Thread.ofPlatform().start(() -> {
                long[] snap = new long[8];
                try {
                    start.await();
                    while (running.get()) {
                        if (stamped != null) {                         // optimistic read: no lock, validate afterwards
                            long st = stamped.tryOptimisticRead();
                            for (int i = 0; i < 8; i++) snap[i] = DATA[i];
                            if (!stamped.validate(st)) {
                                st = stamped.readLock();
                                try {
                                    for (int i = 0; i < 8; i++) snap[i] = DATA[i];
                                } finally {
                                    stamped.unlockRead(st);
                                }
                            }
                        } else {
                            lock.readLock();
                            try {
                                for (int i = 0; i < 8; i++) snap[i] = DATA[i];
                                for (int k = 0; k < 20; k++) Thread.onSpinWait();   // a short read-side critical section
                            } finally {
                                lock.readUnlock();
                            }
                        }
                        if (!consistent(snap)) torn.increment();
                        reads.increment();
                    }
                } catch (Exception e) {
                    failure.compareAndSet(null, e);
                } finally {
                    done.countDown();
                }
            });
        Thread.ofPlatform().start(() -> {
            try {
                start.await();
                for (long v = 1; running.get(); v++) {
                    long t0 = System.nanoTime();
                    long st = 0;
                    if (stamped != null) st = stamped.writeLock();
                    else lock.writeLock();
                    long waited = System.nanoTime() - t0;
                    try {
                        for (int i = 0; i < 8; i++) DATA[i] = v;
                    } finally {
                        if (stamped != null) stamped.unlockWrite(st);
                        else lock.writeUnlock();
                    }
                    synchronized (waits) {
                        waits.add(waited);
                    }
                    for (int k = 0; k < 2_000; k++) Thread.onSpinWait();      // the writer wants in every few microseconds
                }
            } catch (Exception e) {
                failure.compareAndSet(null, e);
            } finally {
                done.countDown();
            }
        });
        start.await();
        Thread.sleep(1_000);
        running.set(false);
        done.await();
        if (failure.get() != null) throw new IllegalStateException(failure.get());
        long[] w = waits.stream().mapToLong(Long::longValue).sorted().toArray();
        return new Result(name, reads.sum(), w.length, w.length == 0 ? 0 : w[w.length - 1] / 1_000, w.length == 0 ? 0 : w[w.length * 99 / 100] / 1_000,
                torn.sum());
    }

    public static void main(String[] args) throws Exception {
        System.out.println("== 8 readers in a tight loop + 1 writer that wants in every few microseconds, 1 second each ==");
        List<Result> results = new ArrayList<>();
        results.add(flood("reader preference (monitor)", new ReaderPreference(), null));
        results.add(flood("writer preference (monitor)", new WriterPreferenceMonitor(), null));
        results.add(flood("custom AQS (writer-first-in-queue)", new AqsRwLock(), null));
        results.add(flood("ReentrantReadWriteLock (nonfair)", new Rrwl(), null));
        results.add(flood("StampedLock optimistic reads", null, new StampedLock()));
        for (Result r : results)
            System.out.printf("  %-36s reads %6.2f M | writes %7d | writer wait p99 %8d us, max %8d us | torn reads %d%n", r.name(), r.reads() / 1e6,
                    r.writes(), r.p99WaitUs(), r.maxWaitUs(), r.torn());

        System.out.println("== AQS semantics: shared acquisition, exclusive acquisition, and the queue ==");
        AqsRwLock l = new AqsRwLock();
        l.readLock();
        l.readLock();
        int twoReaders = l.sync.state();
        boolean writerBlockedByReaders = !l.sync.tryAcquire(1);
        l.readUnlock();
        l.readUnlock();
        l.writeLock();
        int writerHeld = l.sync.state();
        boolean readerBlockedByWriter = l.sync.tryAcquireShared(1) < 0;
        l.writeUnlock();
        System.out.printf("  two readers -> state %d | writer tryAcquire while readers hold: %s | writer holds -> state %d | reader tryAcquireShared: %s%n",
                twoReaders, writerBlockedByReaders ? "refused" : "granted", writerHeld, readerBlockedByWriter ? "refused" : "granted");

        boolean ok = results.stream().allMatch(r -> r.torn() == 0) && twoReaders == 2 && writerBlockedByReaders && writerHeld == -1 && readerBlockedByWriter
                && results.get(1).writes() > results.get(0).writes() && results.get(2).writes() > results.get(0).writes();
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (one measured run):**

```text
== 8 readers in a tight loop + 1 writer that wants in every few microseconds, 1 second each ==
  reader preference (monitor)          reads   3.46 M | writes      16 | writer wait p99  1001452 us, max  1001452 us | torn reads 0
  writer preference (monitor)          reads   1.87 M | writes    8902 | writer wait p99       87 us, max      633 us | torn reads 0
  custom AQS (writer-first-in-queue)   reads   4.63 M | writes   11208 | writer wait p99       51 us, max     3036 us | torn reads 0
  ReentrantReadWriteLock (nonfair)     reads   3.17 M | writes   10553 | writer wait p99       50 us, max      343 us | torn reads 0
  StampedLock optimistic reads         reads 328.56 M | writes   10700 | writer wait p99        3 us, max      198 us | torn reads 0
== AQS semantics: shared acquisition, exclusive acquisition, and the queue ==
  two readers -> state 2 | writer tryAcquire while readers hold: refused | writer holds -> state -1 | reader tryAcquireShared: refused
SELF-TEST OK
```

## 5. C++23 implementation

```cpp
// rw_locks.cpp - 07.1: reader- vs writer-preference RW locks, std::shared_mutex per library, a state-word spinlock, a seqlock
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <memory>
#include <mutex>
#include <print>
#include <shared_mutex>
#include <string>
#include <thread>
#include <vector>

using i64 = std::int64_t;
using u32 = std::uint32_t;
using sz = std::size_t;

void pause_spin(int n) {
    for (int k = 0; k < n; ++k) {
#if defined(__x86_64__) || defined(__i386__)
        __builtin_ia32_pause();
#endif
    }
}

struct RwLock {
    virtual ~RwLock() = default;
    virtual void read_lock() = 0;
    virtual void read_unlock() = 0;
    virtual void write_lock() = 0;
    virtual void write_unlock() = 0;
};

/** Reader preference: a reader enters whenever no writer is ACTIVE. A steady stream of readers starves writers. */
class ReaderPreference final : public RwLock {
    std::mutex m_;
    std::condition_variable cv_;
    int readers_ = 0;
    bool writer_ = false;

public:
    ReaderPreference() { std::scoped_lock warm(m_); }
    void read_lock() override {
        std::unique_lock l(m_);
        cv_.wait(l, [&] { return !writer_; });
        ++readers_;
    }
    void read_unlock() override {
        std::scoped_lock l(m_);
        if (--readers_ == 0) cv_.notify_all();
    }
    void write_lock() override {
        std::unique_lock l(m_);
        cv_.wait(l, [&] { return !writer_ && readers_ == 0; });
        writer_ = true;
    }
    void write_unlock() override {
        {
            std::scoped_lock l(m_);
            writer_ = false;
        }
        cv_.notify_all();
    }
};

/** Strict writer preference: once a writer WAITS, new readers wait too. */
class WriterPreference final : public RwLock {
    std::mutex m_;
    std::condition_variable readers_cv_, writers_cv_;
    int readers_ = 0, waiting_writers_ = 0;
    bool writer_ = false;

public:
    WriterPreference() { std::scoped_lock warm(m_); }
    void read_lock() override {
        std::unique_lock l(m_);
        readers_cv_.wait(l, [&] { return !writer_ && waiting_writers_ == 0; });
        ++readers_;
    }
    void read_unlock() override {
        std::scoped_lock l(m_);
        if (--readers_ == 0) writers_cv_.notify_one();
    }
    void write_lock() override {
        std::unique_lock l(m_);
        ++waiting_writers_;
        writers_cv_.wait(l, [&] { return !writer_ && readers_ == 0; });
        --waiting_writers_;
        writer_ = true;
    }
    void write_unlock() override {
        std::scoped_lock l(m_);
        writer_ = false;
        if (waiting_writers_ > 0) writers_cv_.notify_one();
        else readers_cv_.notify_all();
    }
};

/** std::shared_mutex: the reader/writer policy is implementation-defined. Measured per standard library below. */
class StdShared final : public RwLock {
    std::shared_mutex m_;

public:
    StdShared() { std::unique_lock warm(m_); }  // MinGW: warm a fresh shared_mutex (P10)
    void read_lock() override { m_.lock_shared(); }
    void read_unlock() override { m_.unlock_shared(); }
    void write_lock() override { m_.lock(); }
    void write_unlock() override { m_.unlock(); }
};

/**
 * AQS's idea without AQS's queue: one atomic state word. bits 0-15 = readers, bits 16-30 = waiting writers,
 * bit 31 = writer holds. Readers back off while any writer waits (writer preference); everyone spins, nobody parks.
 */
class StateWordSpin final : public RwLock {
    std::atomic<u32> s_{0};
    static constexpr u32 kWriter = 1u << 31, kWaiter = 1u << 16, kReaders = 0xFFFFu;

public:
    void read_lock() override {
        for (u32 cur = s_.load(std::memory_order_relaxed);;) {
            if ((cur & ~kReaders) == 0) {  // no writer holding, none waiting
                if (s_.compare_exchange_weak(cur, cur + 1, std::memory_order_acquire)) return;
                continue;
            }
            pause_spin(4);
            cur = s_.load(std::memory_order_relaxed);
        }
    }
    void read_unlock() override { s_.fetch_sub(1, std::memory_order_release); }
    void write_lock() override {
        s_.fetch_add(kWaiter, std::memory_order_relaxed);  // announce: new readers now back off
        for (u32 cur = s_.load(std::memory_order_relaxed);;) {
            if ((cur & (kWriter | kReaders)) == 0) {
                if (s_.compare_exchange_weak(cur, (cur - kWaiter) | kWriter, std::memory_order_acquire)) return;
                continue;
            }
            pause_spin(4);
            cur = s_.load(std::memory_order_relaxed);
        }
    }
    void write_unlock() override { s_.fetch_and(~kWriter, std::memory_order_release); }
};

// ---- the shared data: 8 values a writer always sets equal; a reader that sees two values saw a torn write

std::array<std::atomic<i64>, 8> data{};  // atomics (relaxed) so the seqlock's racy copy is not UB

/** A seqlock: the C++ analog of StampedLock's optimistic read. Writers bump an even/odd sequence around the write. */
struct SeqLock {
    std::atomic<u32> seq{0};
    std::mutex writer;
    SeqLock() { std::scoped_lock warm(writer); }
};

struct Result { std::string name; i64 reads, writes, max_wait_us, p99_wait_us, torn; };

i64 now_ns() { return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count(); }

Result flood(const std::string& name, RwLock* lock, SeqLock* seq) {
    for (auto& d : data) d.store(0);
    std::atomic<i64> reads{0}, torn{0};
    std::atomic<bool> running{true};
    std::atomic<int> ready{0};
    std::vector<i64> waits;
    {
        std::vector<std::jthread> ts;
        for (int r = 0; r < 8; ++r)
            ts.emplace_back([&] {
                ready.fetch_add(1);
                while (ready.load() < 10) {}
                std::array<i64, 8> snap{};
                i64 my_reads = 0, my_torn = 0;
                while (running.load(std::memory_order_relaxed)) {
                    if (seq) {  // optimistic: copy, then check that no writer ran meanwhile
                        for (;;) {
                            const u32 s0 = seq->seq.load(std::memory_order_acquire);
                            if (s0 & 1) continue;  // a write is in progress
                            for (sz i = 0; i < 8; ++i) snap[i] = data[i].load(std::memory_order_relaxed);
                            std::atomic_thread_fence(std::memory_order_acquire);
                            if (seq->seq.load(std::memory_order_relaxed) == s0) break;
                        }
                    } else {
                        lock->read_lock();
                        for (sz i = 0; i < 8; ++i) snap[i] = data[i].load(std::memory_order_relaxed);
                        pause_spin(20);  // a short read-side critical section
                        lock->read_unlock();
                    }
                    my_torn += !std::ranges::all_of(snap, [&](i64 v) { return v == snap[0]; });
                    ++my_reads;
                }
                reads += my_reads;
                torn += my_torn;
            });
        ts.emplace_back([&] {
            ready.fetch_add(1);
            while (ready.load() < 10) {}
            for (i64 v = 1; running.load(std::memory_order_relaxed); ++v) {
                const i64 t0 = now_ns();
                if (seq) {
                    seq->writer.lock();
                    const i64 waited = now_ns() - t0;
                    seq->seq.fetch_add(1, std::memory_order_relaxed);  // odd: readers will retry
                    std::atomic_thread_fence(std::memory_order_release);
                    for (auto& d : data) d.store(v, std::memory_order_relaxed);
                    seq->seq.fetch_add(1, std::memory_order_release);  // even again
                    seq->writer.unlock();
                    waits.push_back(waited);
                } else {
                    lock->write_lock();
                    const i64 waited = now_ns() - t0;
                    for (auto& d : data) d.store(v, std::memory_order_relaxed);
                    lock->write_unlock();
                    waits.push_back(waited);
                }
                pause_spin(2'000);  // the writer wants in every few microseconds
            }
        });
        ready.fetch_add(1);
        while (ready.load() < 10) {}
        std::this_thread::sleep_for(std::chrono::seconds(1));
        running.store(false);
    }
    std::ranges::sort(waits);
    const auto n = waits.size();
    return {name, reads.load(), static_cast<i64>(n), n ? waits.back() / 1'000 : 0, n ? waits[n * 99 / 100] / 1'000 : 0, torn.load()};
}

int main() {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::println("== 8 readers in a tight loop + 1 writer that wants in every few microseconds, 1 second each ==");
    std::vector<Result> results;
    {
        ReaderPreference a;
        results.push_back(flood("reader preference (mutex + cv)", &a, nullptr));
    }
    {
        WriterPreference b;
        results.push_back(flood("writer preference (mutex + 2 cvs)", &b, nullptr));
    }
    {
        StdShared c;
#if defined(_LIBCPP_VERSION)
        results.push_back(flood("std::shared_mutex (libc++)", &c, nullptr));
#else
        results.push_back(flood("std::shared_mutex (libstdc++/MinGW)", &c, nullptr));
#endif
    }
    {
        StateWordSpin d;
        results.push_back(flood("state-word spinlock (writer-first)", &d, nullptr));
    }
    {
        SeqLock s;
        results.push_back(flood("seqlock optimistic reads", nullptr, &s));
    }
    for (const auto& r : results)
        std::println("  {:<36} reads {:6.2f} M | writes {:7} | writer wait p99 {:8} us, max {:8} us | torn reads {}", r.name,
                     static_cast<double>(r.reads) / 1e6, r.writes, r.p99_wait_us, r.max_wait_us, r.torn);

    const bool ok = std::ranges::all_of(results, [](const Result& r) { return r.torn == 0; }) && results[1].writes > results[0].writes &&
                    results[3].writes > results[0].writes;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 8 readers in a tight loop + 1 writer that wants in every few microseconds, 1 second each ==
  reader preference (mutex + cv)       reads   2.11 M | writes     466 | writer wait p99     8465 us, max    11300 us | torn reads 0
  writer preference (mutex + 2 cvs)    reads   1.54 M | writes    9760 | writer wait p99       42 us, max      583 us | torn reads 0
  std::shared_mutex (libstdc++/MinGW)  reads   1.46 M | writes   11215 | writer wait p99       37 us, max      400 us | torn reads 0
  state-word spinlock (writer-first)   reads   9.07 M | writes   13072 | writer wait p99        7 us, max      701 us | torn reads 0
  seqlock optimistic reads             reads 624.04 M | writes   11672 | writer wait p99        0 us, max       11 us | torn reads 0
SELF-TEST OK
```

**Output, Clang 21.1:**

```text
== 8 readers in a tight loop + 1 writer that wants in every few microseconds, 1 second each ==
  reader preference (mutex + cv)       reads   3.22 M | writes      69 | writer wait p99    81501 us, max    81501 us | torn reads 0
  writer preference (mutex + 2 cvs)    reads   2.18 M | writes    9965 | writer wait p99       74 us, max     1015 us | torn reads 0
  std::shared_mutex (libc++)           reads   2.52 M | writes   10230 | writer wait p99       74 us, max      679 us | torn reads 0
  state-word spinlock (writer-first)   reads   9.42 M | writes   13753 | writer wait p99        8 us, max      831 us | torn reads 0
  seqlock optimistic reads             reads 1721.09 M | writes   10652 | writer wait p99        2 us, max     1736 us | torn reads 0
SELF-TEST OK
```

## 6. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Design | Reader count + `synchronized`, readers always enter | Writer-waiting flag | Policy chosen by workload; starvation measured; writer preference on a monitor, or AQS with first-queued-writer semantics |
| AQS | "It's the base class of locks" | Overrides `tryAcquire` / `tryRelease` | State encoding, shared propagation, why strict preference loses wakeups on AQS, park vs spin trade-off |
| Reads | Always lock | `ReadWriteLock` | Optimistic reads (`StampedLock` / seqlock) for small, hot, read-mostly data, with validation and fallback |
| C++ | `std::shared_mutex` assumed fair | Knows it's implementation-defined | Measures each library; seqlock with atomics + fences, no data races |

## 7. Curveballs and 5-minute refactors

| Curveball | Response |
|---|---|
| "Make it reentrant" | Per-thread hold counts (a `ThreadLocal` counter for readers; owner + count for the writer). Read → write upgrade must be refused (deadlock when two readers both upgrade) or done as `StampedLock.tryConvertToWriteLock` |
| "Add `tryLock(timeout)`" | AQS gives `tryAcquireNanos` / `tryAcquireSharedNanos` with cancellation built in; on a monitor you'd hand-roll deadline loops |
| "Downgrade write → read" | Acquire the read lock while holding the write lock, then release the write lock. Safe in RRWL; never the reverse |
| "Readers are on virtual threads" | AQS-based locks park virtual threads cheaply. Since JDK 24 `synchronized` no longer pins carriers (JEP 491), but long critical sections still serialize |
| "100 readers, 1 writer, data is 4 KB" | Optimistic copy of 4 KB per read is costly; prefer copy-on-write (an immutable snapshot behind a volatile reference) so reads are a single load |

## 8. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "Write a read-write lock."</b></summary>

**L5:** "A counter of readers; writers wait until it's zero."

**Why it fails:** a steady read stream never lets the count reach zero. Measured: 16 writes in a second, worst wait 1.0 s.

**L7 defence:** "Choose a policy. For read-mostly data with prompt writes, writer preference: once a writer waits, new readers wait. On a monitor that's a waiting-writers count plus `notifyAll`. On AQS, readers queue behind a *first-queued* writer. Or skip the lock for readers entirely with optimistic reads."
</details>

<details>
<summary><b>Q2 🔥 "On AQS, just fail `tryAcquireShared` whenever a writer is waiting."</b></summary>

**L5:** "That gives strict writer preference."

**Why it fails:** a reader woken at the head fails and re-parks, and the writer queued behind it is never signalled. That's a lost wakeup: the lock is free, and every thread waits.

**L7 defence:** "AQS wakes the head's successor, so the blocking rule must guarantee that successor can proceed. The JDK blocks readers only when the first queued thread is a writer. Strict preference belongs where `notifyAll` re-evaluates everyone."
</details>

<details>
<summary><b>Q3 ⚡ "Reads are 99.9%. Can we do better than any RW lock?"</b></summary>

**L5:** "Use `ReentrantReadWriteLock`."

**Why it fails:** every read still writes the shared reader count, so cores ping-pong one cache line: about 3 M reads/s here.

**L7 defence:** "Optimistic reads. `StampedLock.tryOptimisticRead` + `validate` (328 M reads/s here), or a seqlock in C++ with atomic loads and an acquire fence (0.6–1.7 billion/s). For larger data, copy-on-write snapshots behind a volatile reference."
</details>

## 9. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| Writes delayed for seconds | Reader preference under load | Writer preference / optimistic reads |
| Idle lock, all threads parked | Strict preference on AQS (lost wakeup) | First-queued-writer rule, or a monitor |
| Throughput collapses with many threads | Spinning RW lock with oversubscription | Park (AQS) after a short spin |
| Torn data with a seqlock in C++ | Non-atomic racy copy / missing fence | Relaxed atomics + acquire fence |
| Different behaviour per platform | `std::shared_mutex` policy is implementation-defined | Measure; wrap with an explicit policy |

- [ ] State the policy; measure writer wait under a read flood.
- [ ] AQS: state encoding, `try*` contracts, the head-successor wakeup rule.
- [ ] Optimistic reads for small, read-mostly data; copy-on-write for large.
- [ ] Torn-read checks in every test.

## 10. References

- Doug Lea, *The java.util.concurrent Synchronizer Framework* (AQS). <https://gee.cs.oswego.edu/dl/papers/aqs.pdf>
- Java `AbstractQueuedSynchronizer`. <https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/concurrent/locks/AbstractQueuedSynchronizer.html>
- Java `StampedLock`. <https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/concurrent/locks/StampedLock.html>
- Hans Boehm, *Can Seqlocks Get Along with Programming Language Memory Models?* (MSPC 2012). <https://doi.org/10.1145/2247684.2247688>
- In this KB: [01.3 CAS, StampedLock and seqlocks](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md) · [P10 The shared_mutex lazy-init bug](../04-Tier2-Resource-Allocation-and-Lock-Contention-P6-to-P10/05-problem-10-meeting-room-scheduler-interval-tree-and-conflict-locking.md)
