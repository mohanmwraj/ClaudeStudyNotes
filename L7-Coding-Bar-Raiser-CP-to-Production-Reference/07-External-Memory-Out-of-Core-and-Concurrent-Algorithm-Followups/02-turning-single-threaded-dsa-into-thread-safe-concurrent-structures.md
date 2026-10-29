# Turning Single-Threaded DSA into Thread-Safe Concurrent Structures

> **Folder 07 · File 2 of 3** — the "now make it thread-safe" follow-up, done three ways and measured: an LRU cache behind one lock versus 64 lock stripes; a lock-free Treiber stack whose ABA bug is reproduced by a **scripted interleaving** rather than hoped for under stress, then fixed with a version stamp; and a single-producer single-consumer ring buffer with acquire/release counters against the textbook blocking queue.
> **Languages:** Java 21 (`--release 21 -Xlint:all -Werror`, JDK 25.0.4.1) and C++23 (GCC 16.2 and Clang 21.1, `-O2`, warnings as errors).

| Listing | File | What it proves |
|---|---|---|
| 7.3 | `ConcurrentDsa.java` | LRU with 8 threads × 1 M skewed gets: one lock 990 ms, 64 stripes 257 ms, same hit rate (18.6%), zero wrong values. Scripted ABA: a stale CAS on a plain `AtomicReference` succeeds and leaves a popped node on the stack; `AtomicStampedReference` rejects it. Stress: 8 threads × 200 k push+pop conserve every id. SPSC ring 354 ms vs `ArrayBlockingQueue<Long>` 2,323 ms for 20 M items |
| 7.4 | `concurrent_dsa.cpp` | The same with `std::mutex` stripes (`alignas(64)`), a node pool with 32-bit indices, a `(tag << 32) \| index` CAS, and a cache-line-padded SPSC ring vs a mutex + condition-variable queue. Stress recycles nodes on every operation |

**Verification.** Both listings were extracted from this file, compiled and run. The scripted ABA lines, the conservation checks, sizes, "wrong values" and checksums are **Output (verified)**: deterministic and identical in every run and build. Timings and hit rates depend on thread interleaving and are **one measured run**; across runs the hit rates stayed within 18.62–18.65%.

---

## 0. Orientation

"Make it thread-safe" is the most common Extension A prompt, and it has a trap built in: **the easy answer is correct and slow, and the fast answer is subtle.** An L5 answer wraps every method in a lock and stops. An L7 answer starts there too, then asks four questions: where is the contention, what invariant spans more than one memory word, what is the linearization point, and how would I test it.

| Single-threaded habit | What breaks with 64 threads | L7 replacement |
|---|---|---|
| `synchronized` on every method | One lock serializes all 64 threads | Lock striping: 64 independent shards; measured 3.6–4.5× faster at 8 threads |
| Compose two thread-safe structures (`ConcurrentHashMap` + `ConcurrentLinkedDeque`) | Each call is atomic; the pair isn't. Map and list drift apart | One lock around the multi-word invariant, or a design that tolerates approximate state |
| CAS loop on a pointer and call it lock-free | ABA when nodes are reused: a stale CAS succeeds | Version stamp / tag in the CAS word, hazard pointers, or epoch-based reclamation |
| `BlockingQueue` between two threads | Lock + condition variable + boxing per item | SPSC ring with acquire/release indices: measured 4.8–12× faster |
| `memory_order_relaxed` "for speed" | Consumer reads a slot before its value is visible | Release on publish, acquire on observe; relaxed only for single-owner indices |
| Test by running it a lot | Rare interleavings never show up | Script the interleaving (split the operation into steps), stress with a conservation invariant, use a linearizability checker |
| Counters for every thread in one array | False sharing: one cache line ping-pongs between cores | `alignas(64)` / padding between per-thread or per-stripe state |

---

## 1. First principles

### 1.1 Linearizability and the linearization point

A concurrent object is **linearizable** if every operation appears to take effect atomically at some instant between its call and its return: the **linearization point**. For a locked structure it's anywhere inside the critical section. For a Treiber stack it's the successful CAS on `top`. For an SPSC ring, `offer` linearizes at the release store of `tail` and `poll` at the release store of `head`. Naming the linearization point is the fastest way to show an interviewer you know why the code is correct, and to find out when it isn't: if no single instant makes the state change visible all at once, the object isn't linearizable.

**Composition is the trap.** Two linearizable objects don't make a linearizable pair. An LRU built from a `ConcurrentHashMap` and a `ConcurrentLinkedDeque` must update both on every `get` (move the key to the front) and on every `put` (insert, maybe evict). Between those two atomic calls another thread can run its own pair. The map and the recency list then disagree: a key evicted from the list but not the map, or present twice in the list. The invariant spans two objects, so one atomic step must cover both.

### 1.2 Lock striping

If the key space can be partitioned so that no operation needs two partitions, give each partition its own lock. Contention drops by the number of stripes, as long as keys spread evenly. For an LRU the cost is semantic: **recency becomes per-stripe**. The least recently used key overall may survive while a more recent key in a fuller stripe is evicted. With a uniform hash that rarely matters for hit rate, and the measurement confirms it: 18.64% with one lock against 18.62% with 64 stripes.

Two details from the listing:

* **Capacity division.** 10,000 / 64 = 156 per stripe, so total capacity is 9,984, not 10,000 (the printed size). Production code distributes the remainder or documents it.
* **False sharing.** The C++ `Stripe` is `alignas(64)`, so two stripes' mutexes never share a cache line. Without that, a thread locking stripe 3 invalidates the line holding stripe 4's mutex on every other core.

Java's `ConcurrentHashMap` used lock striping (segments) until Java 8 and now locks individual bins. Caffeine, the production Java cache, goes further: reads record their access in a lossy striped buffer and return immediately; a single thread drains the buffers into the recency policy under a lock, in batches. Reads never wait for the policy.

### 1.3 Treiber stack and ABA

A Treiber stack is a singly linked list with an atomic `top`. Push: read `top`, point the new node at it, CAS `top` from the old value to the new node, retry on failure. Pop: read `top` = A and `A.next` = B, CAS `top` from A to B.

The **ABA problem**: thread T1 reads top = A and next = B, then stalls. T2 pops A, pops B, and pushes A back (because A was recycled from a pool or free list). The stack is now A → C. T1 resumes; `top` is A again, so its CAS from A to B **succeeds**, and the stack becomes B → C, with B a node T2 already popped and may be using. The listing scripts exactly this interleaving by splitting `pop` into `readTop()` and `commitPop()`, so the bug reproduces every time, in both languages:

> *T2 popped 1 and 2, pushed 1 back; T1's stale CAS succeeded: true; stack now [2, 3] although node 2 was popped by T2.*

**Garbage collection doesn't make ABA impossible.** It prevents the specific case where A's *memory* is freed and reallocated while T1 still holds a reference, because A can't be collected while T1 references it. But if the program itself re-pushes the same node object (pools, free lists, intrusive containers), ABA is back, as the Java run shows.

Fixes:

* **Version stamp (tagged pointer).** Pair the pointer with a counter that every successful CAS increments, and CAS both together. Java has `AtomicStampedReference`; C++ packs `(tag << 32) | index` into one 64-bit atomic, which needs nodes addressed by 32-bit pool indices rather than 64-bit pointers. The stale CAS now fails ("stale CAS succeeded: false; stack [1, 3]"). A 32-bit tag can wrap after 2³² operations while one thread is stalled, which is unlikely but not impossible. 128-bit CAS (`cmpxchg16b`) allows a 64-bit pointer with a 64-bit tag.
* **Safe memory reclamation.** Hazard pointers (Michael) or epoch-based reclamation never reuse a node while any thread might still hold a reference to it, so the A that returns to `top` is always a different node. C++26 adds `std::hazard_pointer` and `std::rcu`.
* **Don't reuse nodes**, in a GC language: allocate a fresh node per push. That is what `ConcurrentLinkedDeque` does.

### 1.4 The SPSC ring buffer

With **one producer and one consumer**, each index has exactly one writer: the producer owns `tail`, the consumer owns `head`. No CAS is needed, only the right ordering.

* **Producer:** write the value into `buf[tail & mask]`, then **release-store** `tail + 1`. The release makes the value write visible to any thread that acquire-loads the new tail.
* **Consumer:** **acquire-load** `tail`; if it's ahead of `head`, read `buf[head & mask]`, then release-store `head + 1` to free the slot. The producer acquire-loads `head` to check for space.
* Each thread reads its *own* index with a plain or relaxed load, because nobody else writes it.

Put `head` and `tail` on separate cache lines (`alignas(64)` in C++), or every producer store invalidates the consumer's line and vice versa. Use a power-of-two capacity so `& mask` replaces `%`.

**What breaks with two producers:** both read the same `tail`, both write the same slot, both publish `tail + 1`, and one value is lost. Multi-producer queues need a CAS (or fetch-add) to claim a slot plus a per-slot sequence number to publish it (Vyukov's bounded MPMC queue). The LMAX Disruptor is the production version of the single-producer case.

### 1.5 Testing concurrent code

1. **Script the interleaving** you're worried about. Split the operation into its atomic steps and call them in the bad order from one thread, as `readTop` / `commitPop` do. Deterministic, runs in microseconds, and documents the bug.
2. **Stress with a conservation invariant.** Every pushed id must be popped or still present **exactly once** at the end. Sorting all observed ids and checking they are 0..N−1 catches loss, duplication and corruption. In the C++ stress each thread owns a single node from a tiny pool and re-pushes whatever it pops, so nodes are recycled on every operation. That is the worst case for ABA, and the tagged CAS still conserves all 1.6 M ids.
3. **Tools:** ThreadSanitizer (C++) for data races, `jcstress` (Java) for memory-model outcomes, and linearizability checkers (Lincheck for Java, Porcupine for Go-style histories) that search for a valid sequential order of a recorded history.

---

## 2. The listings

### 2.1 Listing 7.3 — Java

```java
// ConcurrentDsa.java - from single-threaded to concurrent: LRU (lock vs stripes), Treiber stack (ABA, scripted), SPSC ring.
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.AtomicStampedReference;
import java.util.function.LongUnaryOperator;

public final class ConcurrentDsa {

    static final class SplitMix64 {
        private long state;
        SplitMix64(long seed) { state = seed; }
        long next() {
            long z = (state += 0x9E3779B97F4A7C15L);
            z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
            z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
            return z ^ (z >>> 31);
        }
    }

    interface Body { void run(int thread) throws Exception; }

    static double parallel(int threads, Body body) throws InterruptedException {
        CountDownLatch gate = new CountDownLatch(1), done = new CountDownLatch(threads);
        List<Throwable> errors = new ArrayList<>();
        for (int t = 0; t < threads; t++) {
            int id = t;
            Thread.ofPlatform().start(() -> {
                try { gate.await(); body.run(id); }
                catch (Throwable e) { synchronized (errors) { errors.add(e); } }
                finally { done.countDown(); }
            });
        }
        long t0 = System.nanoTime();
        gate.countDown();
        done.await();
        if (!errors.isEmpty()) throw new IllegalStateException("worker failed", errors.get(0));
        return (System.nanoTime() - t0) / 1e6;
    }

    // ===================================================================== 1. LRU cache: one lock vs stripes
    /** Single-threaded LRU: LinkedHashMap in access order evicts the least recently used entry. */
    static final class Lru {
        private final LinkedHashMap<Long, Long> map;
        long hits, misses;
        Lru(int capacity) {
            map = new LinkedHashMap<>(capacity * 2, 0.75f, true) {
                @Override protected boolean removeEldestEntry(Map.Entry<Long, Long> e) { return size() > capacity; }
            };
        }
        long get(long key, LongUnaryOperator load) {
            Long v = map.get(key);
            if (v != null) { hits++; return v; }
            misses++;
            long fresh = load.applyAsLong(key);
            map.put(key, fresh);
            return fresh;
        }
        int size() { return map.size(); }
    }

    /** Striping: S independent LRUs chosen by key hash. Contention / S, but recency is only per stripe. */
    static final class StripedLru {
        private final Lru[] stripes;
        StripedLru(int capacity, int s) { stripes = new Lru[s]; for (int i = 0; i < s; i++) stripes[i] = new Lru(capacity / s); }
        long get(long key, LongUnaryOperator load) {
            Lru l = stripes[(int) Long.remainderUnsigned(key * 0x9E3779B97F4A7C15L >>> 32, stripes.length)];
            synchronized (l) { return l.get(key, load); }
        }
        long hits() { long h = 0; for (Lru l : stripes) h += l.hits; return h; }
        int size() { int n = 0; for (Lru l : stripes) n += l.size(); return n; }
    }

    // ===================================================================== 2. Treiber stack and ABA
    static final class Node {
        final long value;
        Node next;
        Node(long value) { this.value = value; }
    }

    /** A lock-free stack whose pop is split in two steps so a test can SCRIPT the interleaving that produces ABA. */
    static final class PlainStack {
        final AtomicReference<Node> top = new AtomicReference<>();
        void push(Node n) { Node t; do { t = top.get(); n.next = t; } while (!top.compareAndSet(t, n)); }
        Node[] readTop() { Node t = top.get(); return new Node[] {t, t == null ? null : t.next}; }   // step 1
        boolean commitPop(Node[] seen) { return top.compareAndSet(seen[0], seen[1]); }               // step 2
        Node pop() { while (true) { Node[] s = readTop(); if (s[0] == null) return null; if (commitPop(s)) return s[0]; } }
    }

    /** Same algorithm with a version stamp on top: a recycled node at the same address no longer looks unchanged. */
    static final class StampedStack {
        final AtomicStampedReference<Node> top = new AtomicStampedReference<>(null, 0);
        void push(Node n) {
            int[] st = new int[1];
            while (true) { Node t = top.get(st); n.next = t; if (top.compareAndSet(t, n, st[0], st[0] + 1)) return; }
        }
        Object[] readTop() { int[] st = new int[1]; Node t = top.get(st); return new Object[] {t, t == null ? null : t.next, st[0]}; }
        boolean commitPop(Object[] seen) {
            return top.compareAndSet((Node) seen[0], (Node) seen[1], (Integer) seen[2], (Integer) seen[2] + 1);
        }
        Node pop() { while (true) { Object[] s = readTop(); if (s[0] == null) return null; if (commitPop(s)) return (Node) s[0]; } }
    }

    static List<Long> contents(Node t) { List<Long> out = new ArrayList<>(); for (; t != null && out.size() < 10; t = t.next) out.add(t.value); return out; }

    // ===================================================================== 3. SPSC ring buffer
    /** One producer, one consumer: each index has a single writer, so plain release/acquire counters suffice. */
    static final class SpscRing {
        private final long[] buf;
        private final int mask;
        private final AtomicLong head = new AtomicLong(), tail = new AtomicLong();   // head: consumer, tail: producer
        SpscRing(int capacityPow2) { buf = new long[capacityPow2]; mask = capacityPow2 - 1; }
        boolean offer(long v) {
            long t = tail.getPlain();
            if (t - head.getAcquire() == buf.length) return false;      // full
            buf[(int) (t & mask)] = v;
            tail.setRelease(t + 1);                                      // publish the slot
            return true;
        }
        boolean poll(long[] out) {
            long h = head.getPlain();
            if (h == tail.getAcquire()) return false;                   // empty
            out[0] = buf[(int) (h & mask)];
            head.setRelease(h + 1);                                      // free the slot
            return true;
        }
    }

    public static void main(String[] args) throws Exception {
        int threads = 8, opsPerThread = 1_000_000, keys = 100_000, capacity = 10_000;
        SplitMix64 r = new SplitMix64(171);
        long[][] work = new long[threads][opsPerThread];
        for (long[] w : work) for (int i = 0; i < opsPerThread; i++) { double u = (r.next() >>> 11) * 0x1.0p-53; w[i] = (long) (keys * u * u); }
        LongUnaryOperator load = k -> k * 31 + 7;                           // the "expensive" computation, deterministic
        AtomicInteger wrong = new AtomicInteger();
        Lru global = new Lru(capacity);
        double msGlobal = parallel(threads, t -> { for (long k : work[t]) { long v; synchronized (global) { v = global.get(k, load); } if (v != load.applyAsLong(k)) wrong.incrementAndGet(); } });
        StripedLru striped = new StripedLru(capacity, 64);
        double msStriped = parallel(threads, t -> { for (long k : work[t]) if (striped.get(k, load) != load.applyAsLong(k)) wrong.incrementAndGet(); });
        long total = (long) threads * opsPerThread;
        System.out.printf("1. LRU, %d threads x %,d gets (skewed keys over %,d, capacity %,d), one measured run:%n", threads, opsPerThread, keys, capacity);
        System.out.printf("   one lock   : %4.0f ms, hit rate %.2f%%, size %,d%n", msGlobal, 100.0 * global.hits / total, global.size());
        System.out.printf("   64 stripes : %4.0f ms, hit rate %.2f%%, size %,d | wrong values seen by callers: %d%n", msStriped,
                100.0 * striped.hits() / total, striped.size(), wrong.get());

        // Scripted ABA: stack A -> B -> C. T1 reads (top=A, next=B), stalls. T2 pops A, pops B, pushes A back.
        Node a = new Node(1), b = new Node(2), c = new Node(3);
        PlainStack ps = new PlainStack();
        ps.push(c); ps.push(b); ps.push(a);
        Node[] t1 = ps.readTop();
        Node gotA = ps.pop(), gotB = ps.pop();
        ps.push(gotA);                                                       // node A recycled (a pool, a free list)
        boolean casOk = ps.commitPop(t1);
        System.out.printf("2. scripted ABA on a pooled Treiber stack: T2 popped %d and %d, pushed %d back; T1's stale CAS succeeded: %b;"
                + " stack now %s although node %d was popped by T2%n", gotA.value, gotB.value, gotA.value, casOk, contents(ps.top.get()), b.value);
        Node a2 = new Node(1), b2 = new Node(2), c2 = new Node(3);
        StampedStack ss = new StampedStack();
        ss.push(c2); ss.push(b2); ss.push(a2);
        Object[] s1 = ss.readTop();
        Node sa = ss.pop();
        ss.pop();
        ss.push(sa);
        boolean stampedOk = ss.commitPop(s1);
        System.out.printf("   same script, AtomicStampedReference: stale CAS succeeded: %b; stack %s%n", stampedOk, contents(ss.top.getReference()));

        StampedStack stress = new StampedStack();
        int perThread = 200_000;
        long[][] popped = new long[threads][];
        double msStack = parallel(threads, t -> {
            long[] mine = new long[perThread];
            int k = 0;
            for (int i = 0; i < perThread; i++) {
                stress.push(new Node((long) t * perThread + i));
                Node n = stress.pop();
                if (n != null) mine[k++] = n.value;
            }
            popped[t] = Arrays.copyOf(mine, k);
        });
        long[] seen = new long[threads * perThread];
        int cnt = 0;
        for (long[] p : popped) for (long v : p) seen[cnt++] = v;
        for (Node n = stress.top.getReference(); n != null; n = n.next) seen[cnt++] = n.value;
        long[] all = Arrays.copyOf(seen, cnt);
        Arrays.sort(all);
        boolean conserved = cnt == threads * perThread;
        for (int i = 0; i < all.length && conserved; i++) conserved = all[i] == i;
        System.out.printf("   stress, %d threads x %,d push+pop on the stamped stack: every pushed id popped or still present exactly once: %b (%.0f ms)%n",
                threads, perThread, conserved, msStack);

        int items = 20_000_000;
        SpscRing ring = new SpscRing(1 << 14);
        long[] result = new long[2];
        long q0 = System.nanoTime();
        Thread prod = Thread.ofPlatform().start(() -> { for (long i = 0; i < items; i++) while (!ring.offer(i)) Thread.onSpinWait(); });
        long[] got = new long[1];
        long sum = 0, prev = -1;
        boolean ordered = true;
        for (int i = 0; i < items; i++) { while (!ring.poll(got)) Thread.onSpinWait(); ordered &= got[0] == prev + 1; prev = got[0]; sum += got[0]; }
        prod.join();
        result[0] = (System.nanoTime() - q0) / 1_000_000;
        ArrayBlockingQueue<Long> abq = new ArrayBlockingQueue<>(1 << 14);
        long q1 = System.nanoTime();
        Thread prod2 = Thread.ofPlatform().start(() -> { try { for (long i = 0; i < items; i++) abq.put(i); } catch (InterruptedException e) { Thread.currentThread().interrupt(); } });
        long sum2 = 0;
        for (int i = 0; i < items; i++) sum2 += abq.take();
        prod2.join();
        result[1] = (System.nanoTime() - q1) / 1_000_000;
        System.out.printf("3. one producer -> one consumer, %,d items (one measured run): SPSC ring %d ms (in order %b) |"
                + " ArrayBlockingQueue<Long> %d ms | checksums equal %b%n", items, result[0], ordered, result[1], sum == sum2);
    }
}
```

**Output (verified, except the timings and hit rates, which are one measured run):**

```text
1. LRU, 8 threads x 1,000,000 gets (skewed keys over 100,000, capacity 10,000), one measured run:
   one lock   :  990 ms, hit rate 18.64%, size 10,000
   64 stripes :  257 ms, hit rate 18.62%, size 9,984 | wrong values seen by callers: 0
2. scripted ABA on a pooled Treiber stack: T2 popped 1 and 2, pushed 1 back; T1's stale CAS succeeded: true; stack now [2, 3] although node 2 was popped by T2
   same script, AtomicStampedReference: stale CAS succeeded: false; stack [1, 3]
   stress, 8 threads x 200,000 push+pop on the stamped stack: every pushed id popped or still present exactly once: true (678 ms)
3. one producer -> one consumer, 20,000,000 items (one measured run): SPSC ring 354 ms (in order true) | ArrayBlockingQueue<Long> 2323 ms | checksums equal true
```

### 2.2 Listing 7.4 — C++23

```cpp
// concurrent_dsa.cpp - from single-threaded to concurrent: LRU (lock vs stripes), Treiber stack (ABA, scripted), SPSC ring.
#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <list>
#include <mutex>
#include <new>
#include <print>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

using u32 = std::uint32_t;
using u64 = std::uint64_t;
using i64 = std::int64_t;

struct SplitMix64 {
    u64 state;
    u64 next() noexcept {
        u64 z = (state += 0x9E3779B97F4A7C15ULL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }
};

template <class Body>
double parallel(int threads, Body body) {
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    std::chrono::steady_clock::time_point t0;
    {
        std::vector<std::jthread> ts;
        for (int t = 0; t < threads; ++t)
            ts.emplace_back([&, t] {
                ready.fetch_add(1);
                while (!go.load(std::memory_order_acquire)) {}
                body(t);
            });
        while (ready.load() < threads) {}
        t0 = std::chrono::steady_clock::now();
        go.store(true, std::memory_order_release);
    }
    return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
}

// ======================================================================= 1. LRU cache: one lock vs stripes
class Lru {  // single-threaded: list in recency order + map from key to list node
public:
    explicit Lru(std::size_t capacity) : cap_(capacity) {}
    template <class Load>
    i64 get(i64 key, Load load) {
        if (auto it = index_.find(key); it != index_.end()) {
            ++hits;
            order_.splice(order_.begin(), order_, it->second);  // move to front: O(1), no reallocation
            return it->second->second;
        }
        ++misses;
        i64 v = load(key);
        order_.emplace_front(key, v);
        index_[key] = order_.begin();
        if (order_.size() > cap_) index_.erase(order_.back().first), order_.pop_back();
        return v;
    }
    std::size_t size() const { return order_.size(); }
    i64 hits = 0, misses = 0;

private:
    std::size_t cap_;
    std::list<std::pair<i64, i64>> order_;
    std::unordered_map<i64, std::list<std::pair<i64, i64>>::iterator> index_;
};

struct alignas(64) Stripe {
    std::mutex mu;
    Lru lru;
    explicit Stripe(std::size_t cap) : lru(cap) {}
};

// ======================================================================= 2. Treiber stack over a node pool
// Nodes are pool indices (1-based; 0 = null) and are REUSED: the setting in which ABA is real, GC or not.
struct Pool {
    std::vector<i64> value;
    std::vector<std::atomic<u32>> next;  // atomic: a stale reader may load it while its node is being recycled
    explicit Pool(std::size_t n) : value(n + 1), next(n + 1) {}
};

class PlainStack {  // top = index only
public:
    explicit PlainStack(Pool& p) : p_(p) {}
    void push(u32 n) {
        u32 t = top.load();
        do p_.next[n].store(t, std::memory_order_relaxed);
        while (!top.compare_exchange_weak(t, n));
    }
    std::pair<u32, u32> read_top() const {  // step 1 of pop
        u32 t = top.load();
        return {t, t ? p_.next[t].load(std::memory_order_relaxed) : 0};
    }
    bool commit_pop(std::pair<u32, u32> seen) { return top.compare_exchange_strong(seen.first, seen.second); }  // step 2
    u32 pop() {
        while (true) {
            auto s = read_top();
            if (!s.first) return 0;
            if (commit_pop(s)) return s.first;
        }
    }
    std::atomic<u32> top{0};

private:
    Pool& p_;
};

class TaggedStack {  // top = (tag << 32) | index: every successful CAS bumps the tag
public:
    explicit TaggedStack(Pool& p) : p_(p) {}
    void push(u32 n) {
        u64 t = top.load();
        while (true) {
            p_.next[n].store(static_cast<u32>(t), std::memory_order_relaxed);
            if (top.compare_exchange_weak(t, ((t >> 32) + 1) << 32 | n)) return;
        }
    }
    struct Seen {
        u64 top;
        u32 next;
    };
    Seen read_top() const {
        u64 t = top.load();
        auto idx = static_cast<u32>(t);
        return {t, idx ? p_.next[idx].load(std::memory_order_relaxed) : 0};
    }
    bool commit_pop(Seen s) { return top.compare_exchange_strong(s.top, ((s.top >> 32) + 1) << 32 | s.next); }
    u32 pop() {
        while (true) {
            Seen s = read_top();
            if (!static_cast<u32>(s.top)) return 0;
            if (commit_pop(s)) return static_cast<u32>(s.top);
        }
    }
    std::atomic<u64> top{0};

private:
    Pool& p_;
};

std::string contents(const Pool& p, u32 t) {
    std::string s = "[";
    for (int k = 0; t && k < 10; ++k, t = p.next[t].load()) s += (s.size() > 1 ? ", " : "") + std::to_string(p.value[t]);
    return s + "]";
}

// ======================================================================= 3. SPSC ring buffer
// One producer, one consumer: each index has a single writer, so release/acquire counters suffice.
class SpscRing {
public:
    explicit SpscRing(std::size_t cap_pow2) : buf_(cap_pow2), mask_(cap_pow2 - 1) {}
    bool offer(i64 v) {
        u64 t = tail_.load(std::memory_order_relaxed);
        if (t - head_.load(std::memory_order_acquire) == buf_.size()) return false;  // full
        buf_[t & mask_] = v;
        tail_.store(t + 1, std::memory_order_release);                                // publish the slot
        return true;
    }
    bool poll(i64& out) {
        u64 h = head_.load(std::memory_order_relaxed);
        if (h == tail_.load(std::memory_order_acquire)) return false;                // empty
        out = buf_[h & mask_];
        head_.store(h + 1, std::memory_order_release);                                // free the slot
        return true;
    }

private:
    std::vector<i64> buf_;
    u64 mask_;
    alignas(64) std::atomic<u64> head_{0};  // consumer-owned
    alignas(64) std::atomic<u64> tail_{0};  // producer-owned: separate lines, no false sharing
};

class LockedQueue {  // the textbook mutex + condition variable bounded queue
public:
    explicit LockedQueue(std::size_t cap) : cap_(cap) {}
    void put(i64 v) {
        std::unique_lock lock(mu_);
        not_full_.wait(lock, [&] { return q_.size() < cap_; });
        q_.push_back(v);
        not_empty_.notify_one();
    }
    i64 take() {
        std::unique_lock lock(mu_);
        not_empty_.wait(lock, [&] { return !q_.empty(); });
        i64 v = q_.front();
        q_.pop_front();
        not_full_.notify_one();
        return v;
    }

private:
    std::size_t cap_;
    std::mutex mu_;
    std::condition_variable not_full_, not_empty_;
    std::deque<i64> q_;
};

int main() {
    constexpr int threads = 8, ops = 1'000'000;
    constexpr i64 keys = 100'000;
    constexpr std::size_t capacity = 10'000;
    SplitMix64 r{171};
    std::vector<std::vector<i64>> work(threads, std::vector<i64>(ops));
    for (auto& w : work)
        for (auto& k : w) {
            double u = static_cast<double>(r.next() >> 11) * 0x1.0p-53;
            k = static_cast<i64>(static_cast<double>(keys) * u * u);
        }
    auto load = [](i64 k) { return k * 31 + 7; };  // the "expensive" computation, deterministic
    std::atomic<int> wrong{0};
    Lru global(capacity);
    std::mutex global_mu;
    double ms_global = parallel(threads, [&](int t) {
        for (i64 k : work[static_cast<std::size_t>(t)]) {
            i64 v;
            {
                std::scoped_lock lock(global_mu);
                v = global.get(k, load);
            }
            if (v != load(k)) wrong.fetch_add(1);
        }
    });
    std::vector<std::unique_ptr<Stripe>> stripes;
    for (int i = 0; i < 64; ++i) stripes.push_back(std::make_unique<Stripe>(capacity / 64));
    double ms_striped = parallel(threads, [&](int t) {
        for (i64 k : work[static_cast<std::size_t>(t)]) {
            auto& s = *stripes[static_cast<std::size_t>((static_cast<u64>(k) * 0x9E3779B97F4A7C15ULL >> 32) % 64)];
            i64 v;
            {
                std::scoped_lock lock(s.mu);
                v = s.lru.get(k, load);
            }
            if (v != load(k)) wrong.fetch_add(1);
        }
    });
    i64 striped_hits = 0;
    std::size_t striped_size = 0;
    for (auto& s : stripes) striped_hits += s->lru.hits, striped_size += s->lru.size();
    double total = static_cast<double>(threads) * ops;
    std::println("1. LRU, {} threads x {} gets (skewed keys over {}, capacity {}), one measured run:", threads, ops, keys, capacity);
    std::println("   one lock   : {:4.0f} ms, hit rate {:.2f}%, size {}", ms_global, 100.0 * static_cast<double>(global.hits) / total,
                 global.size());
    std::println("   64 stripes : {:4.0f} ms, hit rate {:.2f}%, size {} | wrong values seen by callers: {}", ms_striped,
                 100.0 * static_cast<double>(striped_hits) / total, striped_size, wrong.load());

    {  // scripted ABA: stack A -> B -> C. T1 reads (top=A, next=B) and stalls; T2 pops A, pops B, pushes A back.
        Pool p(3);
        p.value[1] = 1, p.value[2] = 2, p.value[3] = 3;
        PlainStack ps(p);
        ps.push(3), ps.push(2), ps.push(1);
        auto t1 = ps.read_top();
        u32 a = ps.pop(), b = ps.pop();
        ps.push(a);  // node A recycled from the pool
        bool cas_ok = ps.commit_pop(t1);
        std::println("2. scripted ABA on a pooled Treiber stack: T2 popped {} and {}, pushed {} back; T1's stale CAS succeeded: {};"
                     " stack now {} although node {} was popped by T2", p.value[a], p.value[b], p.value[a], cas_ok,
                     contents(p, ps.top.load()), p.value[b]);
        Pool q(3);
        q.value[1] = 1, q.value[2] = 2, q.value[3] = 3;
        TaggedStack ts(q);
        ts.push(3), ts.push(2), ts.push(1);
        auto s1 = ts.read_top();
        u32 sa = ts.pop();
        (void)ts.pop();
        ts.push(sa);
        bool tagged_ok = ts.commit_pop(s1);
        std::println("   same script, (tag, index) CAS: stale CAS succeeded: {}; stack {}", tagged_ok,
                     contents(q, static_cast<u32>(ts.top.load())));
    }

    constexpr int per_thread = 200'000;
    Pool pool(static_cast<std::size_t>(threads) * 2);  // only 2 nodes per thread: nodes are recycled constantly
    TaggedStack stress(pool);
    std::vector<std::vector<i64>> popped(threads);
    std::atomic<u32> next_node{1};
    double ms_stack = parallel(threads, [&](int t) {
        u32 mine = next_node.fetch_add(1), spare = next_node.fetch_add(1);
        auto& out = popped[static_cast<std::size_t>(t)];
        out.reserve(per_thread);
        for (int i = 0; i < per_thread; ++i) {
            pool.value[mine] = static_cast<i64>(t) * per_thread + i;  // safe: this node is private until pushed
            stress.push(mine);
            u32 got = stress.pop();
            out.push_back(pool.value[got]);
            mine = got;                                                // recycle whatever we popped
        }
        (void)spare;
    });
    std::vector<i64> all;
    for (auto& v : popped) all.insert(all.end(), v.begin(), v.end());
    for (u32 t = static_cast<u32>(stress.top.load()); t; t = pool.next[t].load()) all.push_back(pool.value[t]);
    std::ranges::sort(all);
    bool conserved = all.size() == static_cast<std::size_t>(threads) * per_thread;
    for (std::size_t i = 0; i < all.size() && conserved; ++i) conserved = all[i] == static_cast<i64>(i);
    std::println("   stress, {} threads x {} push+pop on the tagged stack, nodes recycled every op: every pushed id popped or still"
                 " present exactly once: {} ({:.0f} ms)", threads, per_thread, conserved, ms_stack);

    constexpr i64 items = 20'000'000;
    using clock = std::chrono::steady_clock;
    auto ms = [](clock::duration d) { return std::chrono::duration_cast<std::chrono::milliseconds>(d).count(); };
    SpscRing ring(std::size_t{1} << 14);
    i64 sum = 0, prev = -1;
    bool ordered = true;
    auto q0 = clock::now();
    {
        std::jthread prod([&] {
            for (i64 i = 0; i < items; ++i)
                while (!ring.offer(i)) {}
        });
        for (i64 i = 0, got = 0; i < items; ++i) {
            while (!ring.poll(got)) {}
            ordered = ordered && got == prev + 1;
            prev = got, sum += got;
        }
    }
    auto q1 = clock::now();
    LockedQueue lq(std::size_t{1} << 14);
    i64 sum2 = 0;
    {
        std::jthread prod([&] {
            for (i64 i = 0; i < items; ++i) lq.put(i);
        });
        for (i64 i = 0; i < items; ++i) sum2 += lq.take();
    }
    auto q2 = clock::now();
    std::println("3. one producer -> one consumer, {} items (one measured run): SPSC ring {} ms (in order {}) | mutex + condvar queue {} ms"
                 " | checksums equal {}", items, ms(q1 - q0), ordered, ms(q2 - q1), sum == sum2);
}
```

**Output, GCC 16.2 (verified, except the timings and hit rates, which are one measured run):**

```text
1. LRU, 8 threads x 1000000 gets (skewed keys over 100000, capacity 10000), one measured run:
   one lock   : 2817 ms, hit rate 18.65%, size 10000
   64 stripes :  785 ms, hit rate 18.64%, size 9984 | wrong values seen by callers: 0
2. scripted ABA on a pooled Treiber stack: T2 popped 1 and 2, pushed 1 back; T1's stale CAS succeeded: true; stack now [2, 3] although node 2 was popped by T2
   same script, (tag, index) CAS: stale CAS succeeded: false; stack [1, 3]
   stress, 8 threads x 200000 push+pop on the tagged stack, nodes recycled every op: every pushed id popped or still present exactly once: true (520 ms)
3. one producer -> one consumer, 20000000 items (one measured run): SPSC ring 207 ms (in order true) | mutex + condvar queue 2556 ms | checksums equal true
```

**Output, Clang 21.1 (verified, except the timings and hit rates, which are one measured run):**

```text
1. LRU, 8 threads x 1000000 gets (skewed keys over 100000, capacity 10000), one measured run:
   one lock   : 2688 ms, hit rate 18.64%, size 10000
   64 stripes :  598 ms, hit rate 18.63%, size 9984 | wrong values seen by callers: 0
2. scripted ABA on a pooled Treiber stack: T2 popped 1 and 2, pushed 1 back; T1's stale CAS succeeded: true; stack now [2, 3] although node 2 was popped by T2
   same script, (tag, index) CAS: stale CAS succeeded: false; stack [1, 3]
   stress, 8 threads x 200000 push+pop on the tagged stack, nodes recycled every op: every pushed id popped or still present exactly once: true (569 ms)
3. one producer -> one consumer, 20000000 items (one measured run): SPSC ring 213 ms (in order true) | mutex + condvar queue 1024 ms | checksums equal true
```

---

## 3. What the results show

* **Striping pays in proportion to contention.** With 8 threads, 64 stripes ran 3.9× faster than one lock in Java (990 → 257 ms), 3.6× with GCC (2,817 → 785 ms) and 4.5× with Clang (2,688 → 598 ms). Hit rates moved by at most 0.02 percentage points. No caller ever saw a wrong value.
* **The C++ locked LRU was slower than Java's.** One lock: GCC 2,817 ms and Clang 2,688 ms against Java's 990 ms. The cause wasn't isolated ⚠. Plausible contributors are the `std::mutex` implementations of the two Windows (MinGW-target) toolchains used here, compared with HotSpot's lightweight locking, and the node allocations in `std::list` + `std::unordered_map`. The relative gain from striping is the same in all three, and that is the result the listing is about.
* **ABA is real and the fix works.** The scripted interleaving reproduced the bug in both languages: the plain CAS succeeded and left node 2, which T2 had popped, on the stack. With a stamp or tag the same CAS failed and the stack stayed correct ([1, 3]).
* **The stamped and tagged stacks survive stress.** 8 threads × 200,000 push+pop conserved every id: Java 678 ms with a fresh node per push; C++ 520–569 ms with nodes recycled on every operation.
* **SPSC beats the blocking queue by a wide margin:** 20 M items in 354 ms against 2,323 ms in Java (6.6×; the ring also avoids boxing every `long`), 207 against 2,556 ms with GCC (12×) and 213 against 1,024 ms with Clang (4.8×). Every run delivered all items in order with matching checksums. The ring moves an item in about 10–18 ns.
---

## 4. The last 10 minutes: Extensions A, B and C

Here Extension A is the main topic, so the last ten minutes push it further (8 → 64 threads, skew) and then out (stream, fleet).

### 4.1 Extension A — "64 threads, and the keys are skewed"

* **More stripes than threads.** With S stripes and T threads hashing uniformly, the chance that two threads want the same stripe at once grows like T²/S. Use S ≥ 4T (and a power of two): 256 stripes for 64 threads.
* **Skew defeats striping.** If 10% of requests hit one key, its stripe serializes 10% of all traffic no matter how many stripes there are. Fixes: per-thread or per-core read replicas of the few hottest keys; Caffeine-style lock-free reads with buffered access recording; or for read-mostly data, an immutable snapshot swapped atomically (copy-on-write, RCU), so readers never lock.
* **Read-mostly with a reader-writer lock is often a trap.** Every `readLock()` increments a shared reader count, a single cache line written by all 64 cores. Java's `StampedLock` optimistic read (validate a version after reading, no write on the read path) or per-core reader counters avoid it.
* **Miss storms.** When 64 threads miss on the same key, each calls the loader. The listing computes the value under the stripe lock, which serializes them but also blocks every other key in the stripe for the load's duration. Production caches install a **future** per key (Java `computeIfAbsent` with a `CompletableFuture`, or "single-flight"): the first thread loads, the rest wait on that key only.
* **Queues at 64 threads:** a single MPMC queue's head and tail become the hot lines. Shard it (one SPSC or MPSC queue per producer or per consumer, with work stealing) the way Java's `ForkJoinPool` gives each worker its own deque.

### 4.2 Extension B — "an unbounded stream of keys, or a 100 TB backing store"

* **A cache is bounded memory over an unbounded key space by definition**, so the question becomes the policy. LRU is scan-vulnerable: one sequential pass over cold keys flushes the whole cache. Admission filters fix that: **TinyLFU** keeps a Count-Min-style frequency sketch (Folder 06 File 2) and admits a new key only if it is more frequent than the eviction victim. Caffeine's W-TinyLFU adds a small LRU window for recency bursts.
* **Bound by bytes, not entries.** "Capacity 10,000" means nothing if values range from 10 bytes to 10 MB. Track a weight per entry and evict until the total weight fits.
* **Queues need backpressure.** An unbounded queue between a fast producer and a slow consumer is a memory leak with a delay. A bounded ring makes the choice explicit: block the producer (`put`), fail fast (`offer` returns false, as in the listing), or drop the oldest. Each is a product decision, and the queue's API should force it.
* **Batching amortizes synchronization.** At tens of millions of items per second, publish the tail once per batch of items, not per item. The Disruptor's consumers read all available slots up to the published sequence in one go.

### 4.3 Extension C — "100 nodes"

* **Striping across machines is consistent hashing.** Each key maps to a node by hashing onto a ring of virtual nodes, so adding or removing a node moves only about 1/N of the keys. Each node runs a local (striped) LRU. Hot keys get replicated to several nodes, or cached in a near cache on the clients.
* **Coherence replaces the lock.** With copies on several nodes, a write must invalidate or update the others: TTLs (bounded staleness), invalidation messages (pub/sub), or leases (Facebook's memcache paper uses leases to stop both stale sets and thundering herds).
* **Distributed queues are partitioned logs.** Kafka keeps one ordered log per partition, which is the SPSC/MPSC idea scaled out: order holds within a partition, partitions are independent, and consumers track their own offset (the `head`). Producers choose the partition by key when per-key order matters.
* **No distributed lock-free stack.** A CAS needs one authority for the word being compared. Across machines that authority is a consensus group (Raft, ZooKeeper): a compare-and-set on a key in etcd is the distributed analogue of `compareAndSet`, with a version number playing exactly the role of the ABA stamp.

---

## 5. Failure modes

| # | Failure | Symptom | Prevention |
|---|---|---|---|
| F1 | One global lock | Throughput flat or falling as threads are added: 990 → 257 ms when striped (Java), 2,817 → 785 ms (GCC) | Lock striping; lock-free reads for read-heavy loads |
| F2 | Two thread-safe structures composed | Map and recency list disagree; leaked or duplicated entries | One lock over the multi-object invariant, or an approximate design that tolerates drift |
| F3 | Stripe locks packed in one array | False sharing: lines ping-pong between cores | `alignas(64)` stripes (C++), padded or `@Contended` fields (Java) |
| F4 | Capacity divided by the stripe count | Size 9,984 instead of 10,000 | Distribute the remainder; document per-stripe capacity |
| F5 | Hot key under striping | One stripe saturates | Replicate hot keys; lock-free reads; snapshots |
| F6 | Plain CAS on recycled nodes | ABA: a popped node returns to the stack (reproduced in both languages) | Stamp or tag in the CAS word; hazard pointers; epochs; or never reuse nodes |
| F7 | `delete` a popped node immediately (C++) | Use-after-free: a stalled popper dereferences `A->next` | Safe memory reclamation (hazard pointers, epochs, C++26 `std::hazard_pointer` / `std::rcu`) |
| F8 | 32-bit tag | Wraps after 2³² operations while one thread stalls (unlikely, not impossible) | 64-bit tag via 128-bit CAS, or SMR |
| F9 | SPSC ring with two producers | Lost or overwritten items | MPSC/MPMC design: claim slots by CAS/fetch-add, publish by per-slot sequence |
| F10 | Relaxed publication of `tail` | Consumer reads a slot before its value; invisible on x86, real on ARM and under compiler reordering | Release store of `tail`, acquire load by the consumer |
| F11 | Loader called under the stripe lock | A slow load blocks every key in the stripe | Per-key future / single-flight; load outside the lock |
| F12 | Tested only by running it many times | The bad interleaving never happens on the test machine | Scripted interleavings, conservation invariants, jcstress, TSan, Lincheck |

---

## 6. Bar-raiser chains

<details><summary><b>Q1 · "Make your LRU cache thread-safe."</b></summary>

**Initial Prompt.** The candidate has just written LC 146 with a hash map and a doubly linked list.

**L5 Answer.** "Add `synchronized` to `get` and `put`."

**Why L5 Stalls.** Correct, and a single point of serialization. Every `get` writes (it moves the node to the front), so even a read-only workload contends. The answer stops before asking what the bottleneck is.

**L7 Answer.** "One lock is the correct baseline, so I'd start there and measure. Because every get mutates the recency list, the lock is hot even for reads. Next step is lock striping: 64 independent LRUs chosen by key hash, each with its own lock, cache-line aligned. With 8 threads that ran 3.6–4.5× faster in my measurements, with the same hit rate to within 0.02 points. The trade-offs are per-stripe recency instead of global and capacity divided by 64. Beyond that, for read-heavy traffic, I'd look at Caffeine's design: reads record accesses into a lossy buffer and return without touching the policy, and one thread applies them in batches."
</details>

<details><summary><b>Q2 · "Why not a ConcurrentHashMap plus a ConcurrentLinkedDeque?"</b></summary>

**Initial Prompt.** The interviewer suggests the "obvious" lock-free composition.

**L5 Answer.** "That works: both are thread-safe."

**Why L5 Stalls.** Each operation is atomic on its own; the LRU invariant ("the map's keys are exactly the list's keys, ordered by recency") spans both. Two threads interleaving `get(k)` (remove from the deque, add at the head) can leave k in the deque twice, and `remove(Object)` on the deque is O(n) anyway.

**L7 Answer.** "Two linearizable objects don't compose into a linearizable pair. Between the map update and the list update another thread runs its own pair, and the structures drift: duplicates in the list, or entries evicted from the list but still in the map, a leak. I need one atomic step covering both, which means a lock (striped) or a design where the recency order is allowed to be approximate and is reconciled by a single maintenance thread. That's what Caffeine does, and its tests are about bounding that approximation."
</details>

<details><summary><b>Q3 · "What did striping cost you?"</b></summary>

**Initial Prompt.** Follow-up to Q1.

**L5 Answer.** "Nothing; it's strictly better."

**Why L5 Stalls.** It changes semantics and has edge cases.

**L7 Answer.** "Three things. First, eviction is per stripe: the globally least recently used key may survive while a newer key in a fuller stripe is evicted. With a uniform hash the hit rate barely moved, 18.64% against 18.62%, but on adversarial or skewed key sets it can. Second, capacity: 10,000 / 64 rounds to 156 per stripe, so the cache held 9,984 entries. I'd spread the remainder. Third, a hot key still serializes on its stripe, so striping fixes many-key contention, not one-key contention."
</details>

<details><summary><b>Q4 · "A popular key expires and 1,000 requests miss at the same moment."</b></summary>

**Initial Prompt.** Thundering herd.

**L5 Answer.** "Each request loads it from the database; they'll all succeed."

**Why L5 Stalls.** 1,000 identical database queries at once, possibly an outage. Loading under the cache lock instead serializes the 1,000 and blocks unrelated keys.

**L7 Answer.** "Single-flight: the first miss installs a future for the key and loads; the other 999 find the future and wait on it, so one database query serves all of them. In Java that's `ConcurrentHashMap.computeIfAbsent(key, k -> CompletableFuture.supplyAsync(...))`. The map holds the future, not the value, so the load runs outside any bin lock. I'd also refresh popular keys ahead of expiry (refresh-after-write), add jitter to TTLs so a batch of keys doesn't expire together, and handle loader failure by removing the future so the next request retries."
</details>

<details><summary><b>Q5 · "Implement a lock-free stack."</b></summary>

**Initial Prompt.** Direct.

**L5 Answer.** A correct Treiber stack: CAS loops on `top` for push and pop. Done.

**Why L5 Stalls.** No mention of ABA, memory reclamation or the linearization point, which are the actual content of the question.

**L7 Answer.** "Treiber's stack: push and pop are CAS loops on `top`, and each operation linearizes at its successful CAS. The hard parts are elsewhere. ABA: if nodes are reused, a pop that read top = A, next = B can stall while others pop A and B and push A back; its CAS then succeeds and installs B, which is no longer on the stack. I scripted exactly that interleaving and the plain CAS succeeded. The fix is a version stamp in the same CAS (Java `AtomicStampedReference`, or a tag packed with a 32-bit index in C++), and the stamped version rejected the stale CAS. In C++ there's also reclamation: I can't free a popped node while another thread may be about to read its `next`, so I need hazard pointers or epochs. And it's lock-free, not wait-free: under contention an individual thread can retry indefinitely, though some thread always makes progress."
</details>

<details><summary><b>Q6 · "Java has garbage collection, so ABA can't happen, right?"</b></summary>

**Initial Prompt.** A common belief.

**L5 Answer.** "Right. A node can't be reused while someone references it."

**Why L5 Stalls.** GC prevents reuse of *memory*, not reuse of *objects* by the program.

**L7 Answer.** "GC removes the case where A's memory is freed and reallocated under a stalled thread. It doesn't stop the program from pushing the same node object back, which is what object pools, free lists and intrusive structures do. My Java listing does exactly that: T2 pops node 1, pops node 2, pushes node 1 again, and the stalled thread's plain `compareAndSet` succeeds and puts node 2 back on the stack. With a fresh allocation per push, as `ConcurrentLinkedDeque` does, the reference identity really is unique and plain CAS is safe."
</details>

<details><summary><b>Q7 · "In C++, when do you free a popped node?"</b></summary>

**Initial Prompt.** Follow-up to Q5.

**L5 Answer.** "Right after pop returns it."

**Why L5 Stalls.** Another thread may have loaded `top == A` and be about to read `A->next`. Freeing A makes that a use-after-free, which a tag on `top` doesn't prevent because the read of `next` happens before the CAS.

**L7 Answer.** "Not until no thread can still hold a reference. Options: hazard pointers (each thread publishes the pointer it's about to dereference; a node is freed only when no hazard pointer names it), epoch-based reclamation (free a node two epochs after it was retired, once every thread has passed a quiescent point), or never freeing at all and recycling nodes through a pool with tagged indices. The last is what my listing does, with 32-bit indices so that the tag and the index fit in one 64-bit CAS. C++26 standardizes `std::hazard_pointer` and `std::rcu` for the first two."
</details>

<details><summary><b>Q8 · "Move 50 million events per second from the network thread to a parser thread."</b></summary>

**Initial Prompt.** A throughput question.

**L5 Answer.** "A `BlockingQueue` between them."

**Why L5 Stalls.** A lock and a condition variable per item, plus boxing in Java. Measured at 20 M items: 1,024–2,556 ms, so 50 M/s isn't reachable.

**L7 Answer.** "One producer and one consumer, so an SPSC ring: a power-of-two array, the producer owns `tail` and the consumer owns `head`, publication by a release store and observation by an acquire load, the two indices on separate cache lines. No CAS, no lock, no allocation. Mine moved 20 M items in 207–354 ms, 10–18 ns per item, 4.8–12× faster than the locked queue. To go further I'd batch: write several events, then publish `tail` once, which is what the LMAX Disruptor does. When the ring is full the producer must choose: spin, block, or drop. That's a product decision, so the API makes it explicit."
</details>

<details><summary><b>Q9 · "Now there are four network threads."</b></summary>

**Initial Prompt.** Follow-up to Q8.

**L5 Answer.** "Use the same ring; they all write to it."

**Why L5 Stalls.** Two producers read the same `tail`, write the same slot and publish the same index. Items are lost silently.

**L7 Answer.** "Two options. Simplest and usually fastest: four SPSC rings, one per producer, and the consumer polls them round-robin. Each ring keeps its own order, and if I need a global order I merge by sequence number. If it must be one queue: an MPSC design where producers claim a slot with `fetch_add` on `tail` and publish by writing a per-slot sequence number, which the consumer checks before reading. That's Vyukov's bounded queue. A claimed-but-unpublished slot blocks the consumer, so a producer must never be preempted for long between claim and publish. That's another reason to prefer per-producer rings."
</details>

<details><summary><b>Q10 · "Couldn't the ring's indices use memory_order_relaxed?"</b></summary>

**Initial Prompt.** Memory-model probe.

**L5 Answer.** "Yes; x86 doesn't reorder stores, so it's the same."

**Why L5 Stalls.** The C++ memory model, not the CPU, is the contract. The compiler may reorder the slot write after a relaxed `tail` store, and ARM and POWER CPUs reorder it themselves. The consumer would then read a slot before its value is written.

**L7 Answer.** "Each thread's load of its *own* index can be relaxed, because nobody else writes it. The cross-thread pair needs release and acquire: the producer's release store of `tail` happens-before the consumer's acquire load that sees it, which makes the slot write visible. Same for `head` in the other direction, so the producer doesn't overwrite a slot the consumer is still reading. On x86 release and acquire compile to plain moves anyway, so 'relaxed for speed' buys nothing there and breaks correctness on ARM. Java's `setRelease` and `getAcquire` are the same pair."
</details>

<details><summary><b>Q11 · "How do you test this?"</b></summary>

**Initial Prompt.** Applies to every structure in this file.

**L5 Answer.** "Run it with many threads in a loop and check nothing crashes."

**Why L5 Stalls.** The interesting interleavings are rare. ABA, for instance, needs a thread to stall at exactly one instruction while three operations complete elsewhere.

**L7 Answer.** "Three layers. One, script the interleavings I'm worried about: I split `pop` into `readTop` and `commitPop` and called them in the ABA order from one thread. It reproduces in microseconds, every time, and documents the bug. Two, stress with an invariant that detects any loss or duplication: every pushed id must be popped or still present exactly once, which I checked over 1.6 M ids with nodes recycled every operation. Three, tools: TSan for data races in C++, jcstress for memory-model outcomes in Java, and a linearizability checker such as Lincheck that records concurrent histories and searches for a valid sequential order."
</details>

---

## 7. Checklist

* [ ] Start from one lock; measure; then stripe (S ≥ 4 × threads, power of two, cache-line aligned).
* [ ] Name the invariant that spans more than one word or object; one atomic step must cover it.
* [ ] Name the linearization point of every operation.
* [ ] Striping trade-offs: per-stripe recency, capacity remainder, hot keys.
* [ ] Misses: single-flight futures, loads outside locks, jittered TTLs.
* [ ] Lock-free stack: ABA (stamp/tag), memory reclamation (hazard pointers, epochs), lock-free ≠ wait-free.
* [ ] SPSC: single writer per index, release/acquire, separate cache lines, power-of-two size, batching.
* [ ] Multiple producers: per-producer rings, or claim + per-slot sequence.
* [ ] Backpressure policy explicit: block, fail, or drop.
* [ ] Tests: scripted interleavings, conservation invariants, TSan / jcstress / Lincheck.
* [ ] Extension B: bound by bytes; admission (TinyLFU); bounded queues.
* [ ] Extension C: consistent hashing, replication of hot keys, invalidation or leases, partitioned logs.

---

## 8. References

* M. Herlihy, J. Wing, *Linearizability: A Correctness Condition for Concurrent Objects*, ACM TOPLAS 12(3), 1990 — DOI 10.1145/78969.78972
* M. Herlihy, N. Shavit, V. Luchangco, M. Spear, *The Art of Multiprocessor Programming*, 2nd ed., Morgan Kaufmann, 2020
* R. K. Treiber, *Systems Programming: Coping with Parallelism*, IBM Research Report RJ 5118, 1986
* M. M. Michael, *Hazard Pointers: Safe Memory Reclamation for Lock-Free Objects*, IEEE TPDS 15(6), 2004 — DOI 10.1109/TPDS.2004.8
* G. Einziger, R. Friedman, B. Manes, *TinyLFU: A Highly Efficient Cache Admission Policy*, ACM Transactions on Storage 13(4), 2017 — DOI 10.1145/3149371
* R. Nishtala et al., *Scaling Memcache at Facebook*, NSDI 2013 — <https://www.usenix.org/conference/nsdi13/technical-sessions/presentation/nishtala>
* D. Karger et al., *Consistent Hashing and Random Trees*, STOC 1997 — DOI 10.1145/258533.258660
* Caffeine design notes — <https://github.com/ben-manes/caffeine/wiki/Design>
* LMAX Disruptor — <https://lmax-exchange.github.io/disruptor/>
* D. Vyukov, bounded MPMC queue — <https://www.1024cores.net/home/lock-free-algorithms/queues/bounded-mpmc-queue>
* Java `AtomicStampedReference` — <https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/concurrent/atomic/AtomicStampedReference.html>
* C++ `std::memory_order` — <https://en.cppreference.com/w/cpp/atomic/memory_order>
* OpenJDK jcstress — <https://github.com/openjdk/jcstress>
* JetBrains Lincheck — <https://github.com/JetBrains/lincheck>
* Clang ThreadSanitizer — <https://clang.llvm.org/docs/ThreadSanitizer.html>

*Folder 07:* [01 — External merge sort, streaming top-K, sharded BFS](01-k-way-external-merge-sort-streaming-top-k-and-sharded-bfs-graph-traversal.md) · [03 — 30 hard problems with production Java 21 and C++23 code](03-30-faang-l7-hard-coding-problems-with-production-java21-and-cpp23-code.md)
