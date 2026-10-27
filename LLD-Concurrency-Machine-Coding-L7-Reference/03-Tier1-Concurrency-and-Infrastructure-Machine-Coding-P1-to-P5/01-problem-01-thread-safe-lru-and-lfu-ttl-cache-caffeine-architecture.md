# P1 · Thread-Safe LRU / LFU / TTL Cache: the Caffeine Architecture

> **Folder 03 · Problem 1 of 20.** The most-asked concurrency machine-coding problem. At L5, it's `LinkedHashMap` + `synchronized`. At L7, it's the answer to two questions:
> 1. **Why** does an LRU `get()` need a write lock?
> 2. **How** does Caffeine avoid taking one?
>
> Admission (TinyLFU) and expiry follow from those answers.
>
> **Listing pair P1:** `CaffeineStyleCache.java` / `caffeine_style_cache.cpp`. Hit rates and TTL behaviour are deterministic and **identical in Java and C++**. Throughput is one measured run (4 threads, i5-11260H).

---

## 1. Problem and scope

**Functional:** `get(k)`, `put(k, v)`, bounded size with eviction (LRU, or LFU), optional expire-after-write TTL.

**Non-functional:** thread-safe; reads dominate (typically 90–99%); `get` latency must not degrade with core count; no value of one key may ever be returned for another; the size bound holds after quiescence.

**Assumptions to state:** values are immutable (or copied); a slightly imprecise LRU order is acceptable, while an imprecise *size bound* is not; time is injected.

**Out of scope, with the reason:**
- refresh-after-write and async loading (mentioned in §8);
- weak/soft references;
- distribution across nodes, which is a different problem: consistent hashing and invalidation.

## 2. Domain model and invariants

| Type | Java | C++ | Notes |
|---|---|---|---|
| Cache contract | `interface Cache<K,V>` | `struct Cache<K,V>` (virtual) | `get` returns `null` / `std::nullopt` on a miss *or* on expiry |
| LRU baseline | `AccessOrderMap extends LinkedHashMap(accessOrder=true)` + one `ReentrantLock` | `std::list` + `unordered_map<K, list::iterator>` + `std::mutex` | O(1) get/put; `get` relinks/splices |
| LFU | `HashMap<K, Entry>` + `HashMap<freq, LinkedHashSet<K>>` + `minFreq` | `unordered_map<K, Entry>` + `unordered_map<int, list<K>>` | O(1); ties broken by least-recent within the minimum frequency |
| Admission | `CountMinSketch` (4 × 4096 saturating counters, halved every 10 × capacity samples) | same, bit-identical | Rejects newcomers less popular than the victim |
| Concurrent LRU | `ConcurrentHashMap<K, Node>` + lossy striped read buffers + eviction lock + write-order deque | 16-shard map + try-lock stripes of *keys* + eviction lock + write-order deque | The Caffeine split: **data plane** vs **policy plane** |

**Invariants:**
- **I1 (correctness):** `get(k)` returns the value of some `put(k, ·)`, never another key's. The stress test checks `v % 10_000 == k` on every hit.
- **I2 (bound):** after quiescence, `size() ≤ capacity`. A transient overshoot of at most one entry per in-flight writer is allowed, and Caffeine behaves the same way.
- **I3 (expiry):** an entry is invisible from `writeTime + ttl` (inclusive), whether or not maintenance has run yet.
- **I4 (no resurrection):** eviction and expiry remove an entry only if it is still the *same* entry. The checks are `data.remove(k, node)` and remove-if-version. Otherwise a racing `put` of a new value could be deleted by the eviction of the old one.

## 3. Concurrency and contention analysis

### 3.1 Why an LRU `get()` is a write 🔥

An access-ordered `LinkedHashMap` moves the accessed entry to the tail on every `get`. That means rewriting four `prev`/`next` pointers and incrementing `modCount`. Listing part 1 proves it single-threaded: iterating the keys while calling `get()` throws `ConcurrentModificationException`. So:
- a `ReentrantReadWriteLock` with `get` under the *read* lock lets two readers relink the same list concurrently, which corrupts it (lost nodes, cycles, infinite loops);
- in C++, a `shared_lock` around `list::splice` is a data race, which is undefined behaviour.

**An LRU cache under one lock serializes every read.** That's the real problem the round is testing.

### 3.2 How Caffeine removes the lock from reads ⚡

1. **Data plane:** lookups go to a `ConcurrentHashMap`, which takes no lock for `get`.
2. **Record, don't reorder:** a hit appends the node to a small **striped, lossy ring buffer** with one CAS. Each thread uses a *stable* stripe; Caffeine uses the thread's probe. When a ring is full, the hint is **dropped**: LRU order is a heuristic, and losing a few hints changes hit rates negligibly.
3. **Policy plane:** one thread at a time (`evictionLock.tryLock()`, never blocking a reader) **drains** the buffers and replays the accesses onto the LRU list. Writes and maintenance then do eviction and expiry under the same lock.
4. **Amortization:** draining happens once per full ring (16 hints), so the lock is taken about 1/16 as often as reads happen.

Real Caffeine adds what this listing simplifies:
- a **write buffer**, so `put` doesn't take the eviction lock synchronously, with maintenance running asynchronously on a `ForkJoinPool`;
- a **W-TinyLFU** policy: a small window LRU plus a segmented main LRU, with TinyLFU admission between them;
- a **hierarchical timer wheel** for variable expiry (P3 builds one).

The measurements below show exactly why the write buffer matters.

### 3.3 Where threads collide, and the rules that prevent damage

| Collision | Hazard | Rule in the listing |
|---|---|---|
| Two `put(k)` race | Both link a node; the list holds a stale one | **Link only if still current** (`data.get(k) == n` / version check) under the eviction lock |
| Evict `old(k)` races `put(k, new)` | Eviction deletes the *new* value | Conditional removal: `data.remove(k, victim)` / remove-if-version |
| A reader records a node that is then evicted | Java: harmless (GC keeps it; `linked == false` makes the drain skip it). C++: use-after-free | C++ records **keys**, not pointers; the policy owns its own `key → list iterator` index |
| A ring slot claimed (CAS) but not yet published (`lazySet`) | The drain reads `null` | Stop at the first unpublished slot and resume next drain |
| Expiry vs `get` | A reader sees an expired value before maintenance purges it | `get` checks the deadline itself (I3); maintenance only reclaims memory |

**Expire-after-write ordering:** with a fixed TTL, write order *is* expiry order. A FIFO deque of nodes, appended on `put`, lets maintenance pop expired heads in O(1) per expired entry with no scanning. Variable per-entry TTLs break that property, which is why Caffeine uses a timer wheel for them.

## 4. Java 21 implementation

```java
// CaffeineStyleCache.java - P1: LRU/LFU/TTL caches; why LRU get() is a write; Caffeine-style read buffers; TinyLFU
import java.io.Serial;
import java.time.Duration;
import java.util.ArrayDeque;
import java.util.ConcurrentModificationException;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReferenceArray;
import java.util.concurrent.atomic.LongAdder;
import java.util.concurrent.locks.ReentrantLock;
import java.util.function.ToLongFunction;

public final class CaffeineStyleCache {

    interface Cache<K, V> {
        V get(K key);
        void put(K key, V value);
        int size();
    }

    @FunctionalInterface
    interface Ticker {
        long read();
    }

    static final class FakeTicker implements Ticker {
        private final AtomicLong nanos = new AtomicLong();
        void advance(Duration d) { nanos.addAndGet(d.toNanos()); }
        @Override public long read() { return nanos.get(); }
    }

    static long mix64(long z) {                                // SplitMix64: same streams in Java and C++
        z += 0x9E3779B97F4A7C15L;
        z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
        z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
        return z ^ (z >>> 31);
    }

    // ===== 1. Global-lock LRU: get() must take the WRITE side, because it relinks a node ============

    static final class AccessOrderMap<K, V> extends LinkedHashMap<K, V> {
        @Serial private static final long serialVersionUID = 1L;
        private final int capacity;

        AccessOrderMap(int capacity) {
            super(16, 0.75f, true);                            // accessOrder = true: get() moves the entry to the tail
            this.capacity = capacity;
        }

        @Override protected boolean removeEldestEntry(Map.Entry<K, V> eldest) {
            return capacity > 0 && size() > capacity;
        }
    }

    static final class LockedLru<K, V> implements Cache<K, V> {
        private final AccessOrderMap<K, V> map;
        private final ReentrantLock lock = new ReentrantLock(); // one exclusive lock: a read lock would corrupt the list

        LockedLru(int capacity) {
            map = new AccessOrderMap<>(capacity);
        }

        @Override public V get(K k) {
            lock.lock();
            try { return map.get(k); } finally { lock.unlock(); }
        }

        @Override public void put(K k, V v) {
            lock.lock();
            try { map.put(k, v); } finally { lock.unlock(); }
        }

        @Override public int size() {
            lock.lock();
            try { return map.size(); } finally { lock.unlock(); }
        }
    }

    // ===== 2. O(1) LFU: frequency buckets, least-recent within the minimum frequency =================

    static final class LfuCache<K, V> implements Cache<K, V> {
        private static final class Entry<V> { V value; int freq = 1; Entry(V v) { value = v; } }
        private final HashMap<K, Entry<V>> entries = new HashMap<>();
        private final HashMap<Integer, LinkedHashSet<K>> buckets = new HashMap<>();
        private final int capacity;
        private int minFreq;

        LfuCache(int capacity) {
            this.capacity = capacity;
        }

        private void touch(K k, Entry<V> e) {
            LinkedHashSet<K> b = buckets.get(e.freq);
            b.remove(k);
            if (b.isEmpty()) {
                buckets.remove(e.freq);
                if (minFreq == e.freq) minFreq++;
            }
            e.freq++;
            buckets.computeIfAbsent(e.freq, f -> new LinkedHashSet<>()).add(k);
        }

        @Override public synchronized V get(K k) {
            Entry<V> e = entries.get(k);
            if (e == null) return null;
            touch(k, e);
            return e.value;
        }

        @Override public synchronized void put(K k, V v) {
            Entry<V> e = entries.get(k);
            if (e != null) {
                e.value = v;
                touch(k, e);
                return;
            }
            if (entries.size() >= capacity) {
                LinkedHashSet<K> b = buckets.get(minFreq);
                K victim = b.iterator().next();                 // least recently used among the least frequent
                b.remove(victim);
                if (b.isEmpty()) buckets.remove(minFreq);
                entries.remove(victim);
            }
            entries.put(k, new Entry<>(v));
            buckets.computeIfAbsent(1, f -> new LinkedHashSet<>()).add(k);
            minFreq = 1;
        }

        @Override public synchronized int size() {
            return entries.size();
        }
    }

    // ===== 3. TinyLFU admission: a count-min sketch decides whether a newcomer may evict the victim ====

    static final class CountMinSketch {
        private final byte[][] rows = new byte[4][4096];        // 4-bit-style saturating counters (max 15)
        private final int resetAfter;
        private int samples;

        CountMinSketch(int resetAfter) {
            this.resetAfter = resetAfter;
        }

        private static int index(long h, int row) {
            return (int) (mix64(h + row * 0x632BE59BD9B4E019L) & 4095);
        }

        void increment(long h) {
            for (int r = 0; r < 4; r++) {
                int i = index(h, r);
                if (rows[r][i] < 15) rows[r][i]++;
            }
            if (++samples >= resetAfter) {                      // aging: halve everything so old popularity decays
                for (byte[] row : rows) for (int i = 0; i < row.length; i++) row[i] >>= 1;
                samples = 0;
            }
        }

        int frequency(long h) {
            int f = 15;
            for (int r = 0; r < 4; r++) f = Math.min(f, rows[r][index(h, r)]);
            return f;
        }
    }

    static final class TinyLfuLru<K, V> implements Cache<K, V> {
        private final AccessOrderMap<K, V> map = new AccessOrderMap<>(0);   // 0: we evict ourselves
        private final CountMinSketch sketch;
        private final ToLongFunction<K> hasher;
        private final int capacity;
        long rejected;

        TinyLfuLru(int capacity, ToLongFunction<K> hasher) {
            this.capacity = capacity;
            this.hasher = hasher;
            this.sketch = new CountMinSketch(10 * capacity);
        }

        @Override public synchronized V get(K k) {
            sketch.increment(hasher.applyAsLong(k));
            return map.get(k);
        }

        @Override public synchronized void put(K k, V v) {
            if (map.containsKey(k) || map.size() < capacity) {
                map.put(k, v);
                return;
            }
            K victim = map.keySet().iterator().next();          // LRU victim
            if (sketch.frequency(hasher.applyAsLong(k)) <= sketch.frequency(hasher.applyAsLong(victim))) {
                rejected++;                                     // a one-hit wonder may not evict a popular key
                return;
            }
            map.remove(victim);
            map.put(k, v);
        }

        @Override public synchronized int size() {
            return map.size();
        }
    }

    // ===== 4. Caffeine-style concurrent LRU + expire-after-write ====================================

    static final class BufferedLru<K, V> implements Cache<K, V> {
        static final class Node<K, V> {
            final K key;
            final V value;
            final long deadline;
            Node<K, V> prev, next;                              // guarded by evictionLock
            boolean linked;                                     // guarded by evictionLock

            Node(K key, V value, long deadline) {
                this.key = key;
                this.value = value;
                this.deadline = deadline;
            }
        }

        /** One lossy MPSC ring per stripe: readers CAS a slot index; a full ring drops the access hint. */
        static final class ReadBuffer<K, V> {
            static final int SIZE = 16, MASK = SIZE - 1;
            final AtomicReferenceArray<Node<K, V>> slots = new AtomicReferenceArray<>(SIZE);
            final AtomicLong writes = new AtomicLong(), reads = new AtomicLong();
        }

        private static final int STRIPES = 8;
        private static final AtomicLong NEXT_STRIPE = new AtomicLong();
        private static final ThreadLocal<Integer> STRIPE =
                ThreadLocal.withInitial(() -> (int) (NEXT_STRIPE.getAndIncrement() & (STRIPES - 1)));
        private final ConcurrentHashMap<K, Node<K, V>> data = new ConcurrentHashMap<>();
        private final ReentrantLock evictionLock = new ReentrantLock();
        private final Node<K, V> head = new Node<>(null, null, 0);    // head.next = least recently used
        private final ArrayDeque<Node<K, V>> writeOrder = new ArrayDeque<>();   // for expire-after-write
        @SuppressWarnings({"unchecked", "rawtypes"})            // generic array creation
        private final ReadBuffer<K, V>[] buffers = new ReadBuffer[STRIPES];
        private final int capacity;
        private final long ttlNanos;
        private final Ticker ticker;
        final LongAdder droppedReads = new LongAdder();

        /** ttl == null: no expiry, and then no ticker read on the hot path (Caffeine does the same). */
        BufferedLru(int capacity, Duration ttl, Ticker ticker) {
            this.capacity = capacity;
            this.ttlNanos = ttl == null ? Long.MAX_VALUE : ttl.toNanos();
            this.ticker = ticker;
            head.prev = head.next = head;
            for (int i = 0; i < STRIPES; i++) buffers[i] = new ReadBuffer<>();
        }

        @Override public V get(K k) {
            Node<K, V> n = data.get(k);                         // lock-free hash lookup
            if (n == null) return null;
            if (ttlNanos != Long.MAX_VALUE && ticker.read() - n.deadline >= 0) return null;   // expired: miss now, purge later
            record(n);
            return n.value;
        }

        private void record(Node<K, V> n) {
            ReadBuffer<K, V> b = buffers[STRIPE.get()];        // stable per-thread stripe: no CAS fights
            long w = b.writes.get();
            if (w - b.reads.get() >= ReadBuffer.SIZE || !b.writes.compareAndSet(w, w + 1)) {
                droppedReads.increment();                       // lossy by design: LRU order is a hint
                tryDrain();
                return;
            }
            b.slots.lazySet((int) (w & ReadBuffer.MASK), n);
            if ((w & ReadBuffer.MASK) == ReadBuffer.MASK) tryDrain();   // amortize: drain once per ring-full
        }

        private void tryDrain() {
            if (evictionLock.tryLock()) {                       // never block a reader on maintenance
                try { drainReadBuffers(); } finally { evictionLock.unlock(); }
            }
        }

        private void drainReadBuffers() {                       // caller holds evictionLock
            for (ReadBuffer<K, V> b : buffers) {
                long r = b.reads.get(), w = b.writes.get();
                for (; r < w; r++) {
                    int i = (int) (r & ReadBuffer.MASK);
                    Node<K, V> n = b.slots.get(i);
                    if (n == null) break;                       // claimed but not yet published: retry next drain
                    b.slots.lazySet(i, null);
                    if (n.linked) { unlink(n); linkLast(n); }
                }
                b.reads.set(r);
            }
        }

        @Override public void put(K k, V v) {
            Node<K, V> n = new Node<>(k, v, ttlNanos == Long.MAX_VALUE ? Long.MAX_VALUE : ticker.read() + ttlNanos);
            Node<K, V> prev = data.put(k, n);
            evictionLock.lock();
            try {
                drainReadBuffers();
                if (prev != null && prev.linked) unlink(prev);
                if (data.get(k) == n) {                         // link only if still current: a racing put may have won
                    linkLast(n);
                    if (ttlNanos != Long.MAX_VALUE) writeOrder.addLast(n);
                }
                expireAndEvict();
            } finally {
                evictionLock.unlock();
            }
        }

        private void expireAndEvict() {                         // caller holds evictionLock
            long now = ticker.read();
            while (ttlNanos != Long.MAX_VALUE && !writeOrder.isEmpty()) {   // write order == expiry order for a fixed TTL
                Node<K, V> n = writeOrder.peekFirst();
                boolean superseded = data.get(n.key) != n;
                if (!superseded && now - n.deadline < 0) break;
                writeOrder.pollFirst();
                if (!superseded) data.remove(n.key, n);
                if (n.linked) unlink(n);
            }
            while (data.size() > capacity && head.next != head) {
                Node<K, V> victim = head.next;                  // least recently used
                unlink(victim);
                data.remove(victim.key, victim);                // conditional: never remove a newer value
            }
        }

        void cleanUp() {
            evictionLock.lock();
            try {
                drainReadBuffers();
                expireAndEvict();
            } finally {
                evictionLock.unlock();
            }
        }

        private void unlink(Node<K, V> n) {
            n.prev.next = n.next;
            n.next.prev = n.prev;
            n.linked = false;
        }

        private void linkLast(Node<K, V> n) {
            n.prev = head.prev;
            n.next = head;
            head.prev.next = n;
            head.prev = n;
            n.linked = true;
        }

        @Override public int size() {
            return data.size();
        }
    }

    // ===== Harness ===================================================================================

    /** Same deterministic request stream in both languages: hot set + warm set + periodic one-shot scans. */
    static long requestKey(int i, long[] scanCounter) {
        if (i % 10_000 < 1_000) return 1_000_000L + scanCounter[0]++;
        long r = mix64(i);
        return Long.remainderUnsigned(r, 10) < 8 ? Long.remainderUnsigned(r >>> 8, 200) : 1_000 + Long.remainderUnsigned(r >>> 8, 5_000);
    }

    static long hits(Cache<Long, Long> cache, int requests) {
        long[] scan = {0};
        long hits = 0;
        for (int i = 0; i < requests; i++) {
            long k = requestKey(i, scan);
            if (cache.get(k) != null) hits++;
            else cache.put(k, k);
        }
        return hits;
    }

    record Stress(double mopsPerSec, long wrongValues, int sizeAfter) {}

    static Stress stress(Cache<Long, Long> cache, Runnable cleanUp, int threads, int opsPerThread, int putPerMille) throws Exception {
        CyclicBarrier start = new CyclicBarrier(threads + 1), end = new CyclicBarrier(threads + 1);
        LongAdder wrong = new LongAdder();
        for (int t = 0; t < threads; t++) {
            final long seed = t;
            Thread.ofPlatform().start(() -> {
                try {
                    start.await();
                    for (int i = 0; i < opsPerThread; i++) {
                        long r = mix64(seed * 1_000_003L + i);
                        long k = Long.remainderUnsigned(r, 10_000);
                        if (Long.remainderUnsigned(r >>> 40, 1_000) < putPerMille) cache.put(k, k + 10_000L * (i % 97));
                        else {
                            Long v = cache.get(k);
                            if (v != null && v % 10_000 != k) wrong.increment();   // a value from another key
                        }
                    }
                    end.await();
                } catch (Exception e) {
                    throw new IllegalStateException(e);
                }
            });
        }
        start.await();
        long t0 = System.nanoTime();
        end.await();
        double secs = (System.nanoTime() - t0) / 1e9;
        cleanUp.run();
        return new Stress(threads * (double) opsPerThread / secs / 1e6, wrong.sum(), cache.size());
    }

    public static void main(String[] args) throws Exception {
        System.out.println("== 1. LinkedHashMap(accessOrder=true): get() is a STRUCTURAL modification ==");
        AccessOrderMap<String, Integer> m = new AccessOrderMap<>(0);
        m.put("a", 1);
        m.put("b", 2);
        m.put("c", 3);
        m.get("a");
        System.out.println("  insert a,b,c then get(a) -> iteration order " + m.keySet());
        try {
            for (String k : m.keySet()) m.get(k);              // single-threaded, and still...
        } catch (ConcurrentModificationException e) {
            System.out.println("  calling get() while iterating -> ConcurrentModificationException (modCount changed)");
        }
        System.out.println("  => a ReadWriteLock read lock around get() would let two readers relink the list at once");

        System.out.println("== 2. Hit rates on one deterministic stream (300,000 requests, capacity 500) ==");
        int requests = 300_000;
        TinyLfuLru<Long, Long> tiny = new TinyLfuLru<>(500, CaffeineStyleCache::mix64);
        long lru = hits(new LockedLru<>(500), requests), lfu = hits(new LfuCache<>(500), requests), tlfu = hits(tiny, requests);
        System.out.printf("  LRU          hit rate %6.2f%%%n", 100.0 * lru / requests);
        System.out.printf("  LFU          hit rate %6.2f%%%n", 100.0 * lfu / requests);
        System.out.printf("  TinyLFU+LRU  hit rate %6.2f%%   (admission rejected %,d one-hit wonders)%n", 100.0 * tlfu / requests, tiny.rejected);

        System.out.println("== 3. TTL (expire-after-write) with an injected ticker ==");
        FakeTicker ticker = new FakeTicker();
        BufferedLru<String, String> ttl = new BufferedLru<>(10, Duration.ofMinutes(5), ticker);
        ttl.put("seat-7", "alice");
        ticker.advance(Duration.ofMinutes(5).minusNanos(1));
        String before = ttl.get("seat-7");
        ticker.advance(Duration.ofNanos(1));
        String at = ttl.get("seat-7");
        int sizeBeforeCleanup = ttl.size();
        ttl.cleanUp();
        System.out.println("  get at TTL-1ns = " + before + ", get at TTL = " + at + ", size before cleanUp = "
                + sizeBeforeCleanup + ", after = " + ttl.size());

        System.out.println("== 4. Concurrency: 4 threads x 2,000,000 ops, 10,000 keys, capacity 1,000, no expiry ==");
        Stress[] results = new Stress[4];
        long dropped = 0;
        int idx = 0;
        for (int putPerMille : new int[] {100, 10}) {
            LockedLru<Long, Long> locked = new LockedLru<>(1_000);
            BufferedLru<Long, Long> buffered = new BufferedLru<>(1_000, null, System::nanoTime);
            stress(locked, () -> {}, 4, 200_000, putPerMille);            // warm-up
            stress(buffered, buffered::cleanUp, 4, 200_000, putPerMille);
            Stress a = stress(locked, () -> {}, 4, 2_000_000, putPerMille);
            Stress b = stress(buffered, buffered::cleanUp, 4, 2_000_000, putPerMille);
            results[idx++] = a;
            results[idx++] = b;
            dropped += buffered.droppedReads.sum();
            System.out.printf("  %4.1f%% puts  LockedLru   (one exclusive lock)       %6.1f M ops/s  wrong values %d  size %,d%n",
                    putPerMille / 10.0, a.mopsPerSec(), a.wrongValues(), a.sizeAfter());
            System.out.printf("  %4.1f%% puts  BufferedLru (CHM + lossy read buffers) %6.1f M ops/s  wrong values %d  size %,d  dropped hints %,d%n",
                    putPerMille / 10.0, b.mopsPerSec(), b.wrongValues(), b.sizeAfter(), buffered.droppedReads.sum());
        }

        boolean ok = tlfu > lru && "alice".equals(before) && at == null && ttl.size() == 0
                && java.util.Arrays.stream(results).allMatch(r -> r.wrongValues() == 0 && r.sizeAfter() <= 1_000) && dropped >= 0;
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (parts 1–3 verified; part 4 throughput one measured run):**

```text
== 1. LinkedHashMap(accessOrder=true): get() is a STRUCTURAL modification ==
  insert a,b,c then get(a) -> iteration order [b, c, a]
  calling get() while iterating -> ConcurrentModificationException (modCount changed)
  => a ReadWriteLock read lock around get() would let two readers relink the list at once
== 2. Hit rates on one deterministic stream (300,000 requests, capacity 500) ==
  LRU          hit rate  70.90%
  LFU          hit rate  73.03%
  TinyLFU+LRU  hit rate  72.84%   (admission rejected 67,811 one-hit wonders)
== 3. TTL (expire-after-write) with an injected ticker ==
  get at TTL-1ns = alice, get at TTL = null, size before cleanUp = 1, after = 0
== 4. Concurrency: 4 threads x 2,000,000 ops, 10,000 keys, capacity 1,000, no expiry ==
  10.0% puts  LockedLru   (one exclusive lock)         13.9 M ops/s  wrong values 0  size 1,000
  10.0% puts  BufferedLru (CHM + lossy read buffers)   13.9 M ops/s  wrong values 0  size 1,000  dropped hints 0
   1.0% puts  LockedLru   (one exclusive lock)         16.7 M ops/s  wrong values 0  size 1,000
   1.0% puts  BufferedLru (CHM + lossy read buffers)   47.9 M ops/s  wrong values 0  size 1,000  dropped hints 2,409
SELF-TEST OK
```

## 5. C++23 implementation

C++ has no `ConcurrentHashMap` and no GC:
- **The data plane is 16 `alignas(64)` shards**, each a `std::mutex` + `unordered_map`, padded so neighbouring shard locks don't false-share (file 01.3 §7).
- **Read hints are keys pushed into per-thread `try_lock` stripes.** A busy stripe drops the hint: lossy, like Caffeine's ring.
- **Versions replace node identity** for "link only if current" and conditional removal.

```cpp
// caffeine_style_cache.cpp - P1: LRU/LFU/TTL caches; LRU get() is a write; Caffeine-style buffered LRU; TinyLFU
#include <algorithm>
#include <array>
#include <atomic>
#include <barrier>
#include <chrono>
#include <cstdint>
#include <deque>
#include <functional>
#include <list>
#include <memory>
#include <mutex>
#include <optional>
#include <print>
#include <string>
#include <thread>
#include <unordered_map>
#include <utility>
#include <vector>

using u64 = std::uint64_t;
using i64 = std::int64_t;

constexpr u64 mix64(u64 z) {  // SplitMix64: the same stream as the Java listing
    z += 0x9E3779B97F4A7C15ULL;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

template <class K, class V>
struct Cache {
    virtual ~Cache() = default;
    virtual std::optional<V> get(const K& k) = 0;
    virtual void put(const K& k, V v) = 0;
    virtual std::size_t size() = 0;
};

// ===== 1. Global-lock LRU: get() SPLICES the list, so it is a write ============================

template <class K, class V>
class LockedLru final : public Cache<K, V> {
    std::mutex m_;  // exclusive: two "readers" splicing one std::list concurrently is a data race (UB)
    std::list<std::pair<K, V>> order_;  // front = least recently used
    std::unordered_map<K, typename std::list<std::pair<K, V>>::iterator> pos_;
    std::size_t cap_;
public:
    explicit LockedLru(std::size_t cap) : cap_(cap) {}
    std::optional<V> get(const K& k) override {
        std::scoped_lock l(m_);
        auto it = pos_.find(k);
        if (it == pos_.end()) return std::nullopt;
        order_.splice(order_.end(), order_, it->second);  // the "read" mutates the list
        return it->second->second;
    }
    void put(const K& k, V v) override {
        std::scoped_lock l(m_);
        if (auto it = pos_.find(k); it != pos_.end()) {
            it->second->second = std::move(v);
            order_.splice(order_.end(), order_, it->second);
            return;
        }
        order_.emplace_back(k, std::move(v));
        pos_.emplace(k, std::prev(order_.end()));
        if (order_.size() > cap_) {
            pos_.erase(order_.front().first);
            order_.pop_front();
        }
    }
    std::size_t size() override {
        std::scoped_lock l(m_);
        return order_.size();
    }
    std::vector<K> keys() {
        std::scoped_lock l(m_);
        std::vector<K> ks;
        for (const auto& [k, v] : order_) ks.push_back(k);
        return ks;
    }
};

// ===== 2. O(1) LFU: frequency buckets, least-recent within the minimum frequency ================

template <class K, class V>
class LfuCache final : public Cache<K, V> {
    struct Entry { V value; int freq; typename std::list<K>::iterator it; };
    std::mutex m_;
    std::unordered_map<K, Entry> entries_;
    std::unordered_map<int, std::list<K>> buckets_;  // freq -> keys, front = least recently touched
    std::size_t cap_;
    int min_freq_ = 0;
    void touch(const K& k, Entry& e) {
        auto& b = buckets_[e.freq];
        b.erase(e.it);
        if (b.empty()) {
            buckets_.erase(e.freq);
            if (min_freq_ == e.freq) ++min_freq_;
        }
        ++e.freq;
        auto& nb = buckets_[e.freq];
        e.it = nb.insert(nb.end(), k);
    }
public:
    explicit LfuCache(std::size_t cap) : cap_(cap) {}
    std::optional<V> get(const K& k) override {
        std::scoped_lock l(m_);
        auto it = entries_.find(k);
        if (it == entries_.end()) return std::nullopt;
        touch(k, it->second);
        return it->second.value;
    }
    void put(const K& k, V v) override {
        std::scoped_lock l(m_);
        if (auto it = entries_.find(k); it != entries_.end()) {
            it->second.value = std::move(v);
            touch(k, it->second);
            return;
        }
        if (entries_.size() >= cap_) {
            auto& b = buckets_[min_freq_];
            entries_.erase(b.front());
            b.pop_front();
            if (b.empty()) buckets_.erase(min_freq_);
        }
        auto& b1 = buckets_[1];
        entries_.emplace(k, Entry{std::move(v), 1, b1.insert(b1.end(), k)});
        min_freq_ = 1;
    }
    std::size_t size() override {
        std::scoped_lock l(m_);
        return entries_.size();
    }
};

// ===== 3. TinyLFU admission on top of LRU =========================================================

class CountMinSketch {
    std::array<std::array<std::uint8_t, 4096>, 4> rows_{};  // saturating counters, max 15
    int reset_after_, samples_ = 0;
    static std::size_t index(u64 h, u64 row) { return static_cast<std::size_t>(mix64(h + row * 0x632BE59BD9B4E019ULL) & 4095); }
public:
    explicit CountMinSketch(int reset_after) : reset_after_(reset_after) {}
    void increment(u64 h) {
        for (u64 r = 0; r < 4; ++r) {
            auto& c = rows_[r][index(h, r)];
            if (c < 15) ++c;
        }
        if (++samples_ >= reset_after_) {  // aging: old popularity decays
            for (auto& row : rows_)
                for (auto& c : row) c = static_cast<std::uint8_t>(c >> 1);
            samples_ = 0;
        }
    }
    int frequency(u64 h) const {
        int f = 15;
        for (u64 r = 0; r < 4; ++r) f = std::min(f, static_cast<int>(rows_[r][index(h, r)]));
        return f;
    }
};

class TinyLfuLru final : public Cache<u64, u64> {
    std::mutex m_;
    std::list<std::pair<u64, u64>> order_;
    std::unordered_map<u64, std::list<std::pair<u64, u64>>::iterator> pos_;
    CountMinSketch sketch_;
    std::size_t cap_;
public:
    u64 rejected = 0;
    explicit TinyLfuLru(std::size_t cap) : sketch_(static_cast<int>(10 * cap)), cap_(cap) {}
    std::optional<u64> get(const u64& k) override {
        std::scoped_lock l(m_);
        sketch_.increment(mix64(k));
        auto it = pos_.find(k);
        if (it == pos_.end()) return std::nullopt;
        order_.splice(order_.end(), order_, it->second);
        return it->second->second;
    }
    void put(const u64& k, u64 v) override {
        std::scoped_lock l(m_);
        if (auto it = pos_.find(k); it != pos_.end()) {
            it->second->second = v;
            order_.splice(order_.end(), order_, it->second);
            return;
        }
        if (order_.size() >= cap_) {
            const u64 victim = order_.front().first;
            if (sketch_.frequency(mix64(k)) <= sketch_.frequency(mix64(victim))) {
                ++rejected;  // a one-hit wonder may not evict a popular key
                return;
            }
            pos_.erase(victim);
            order_.pop_front();
        }
        order_.emplace_back(k, v);
        pos_.emplace(k, std::prev(order_.end()));
    }
    std::size_t size() override {
        std::scoped_lock l(m_);
        return order_.size();
    }
};

// ===== 4. Caffeine-style buffered LRU + expire-after-write =======================================

/**
 * Data plane: sharded hash map (C++ has no ConcurrentHashMap). Policy plane: one lock, batched.
 * No GC, so the read buffers record KEYS, not node pointers, and the policy owns its own index:
 * a pointer recorded by a reader could otherwise be freed by eviction before the drain replays it.
 */
template <class K, class V>
class BufferedLru final : public Cache<K, V> {
    struct Entry { V value; i64 deadline; u64 version; };
    struct alignas(64) Shard { std::mutex m; std::unordered_map<K, Entry> map; };
    struct alignas(64) Stripe { std::mutex m; std::vector<K> keys; };
    static constexpr std::size_t kShards = 16, kStripes = 8, kStripeCap = 16;
    std::array<Shard, kShards> shards_;
    std::array<Stripe, kStripes> stripes_;
    std::mutex eviction_;
    std::list<std::pair<K, u64>> lru_;  // (key, version); front = least recently used
    std::unordered_map<K, typename std::list<std::pair<K, u64>>::iterator> pos_;
    std::deque<std::tuple<K, u64, i64>> write_order_;  // (key, version, deadline)
    std::atomic<i64> size_{0};
    std::atomic<u64> versions_{0};
    std::size_t cap_;
    i64 ttl_;  // INT64_MAX = no expiry, and then no clock reads on the hot path
    std::function<i64()> now_;
    static inline std::atomic<std::size_t> next_stripe_{0};

    Shard& shard(const K& k) { return shards_[std::hash<K>{}(k) % kShards]; }
    static std::size_t my_stripe() {
        thread_local const std::size_t s = next_stripe_.fetch_add(1) % kStripes;  // stable per thread
        return s;
    }
    void record(const K& k) {
        Stripe& s = stripes_[my_stripe()];
        bool full = false;
        if (s.m.try_lock()) {  // lossy: a busy stripe drops the access hint instead of blocking
            s.keys.push_back(k);
            full = s.keys.size() >= kStripeCap;
            s.m.unlock();
        } else {
            dropped.fetch_add(1, std::memory_order_relaxed);
        }
        if (full && eviction_.try_lock()) {
            drain();
            eviction_.unlock();
        }
    }
    void drain() {  // caller holds eviction_
        std::vector<K> batch;
        for (auto& s : stripes_) {
            {
                std::scoped_lock l(s.m);
                batch.swap(s.keys);
            }
            for (const auto& k : batch)
                if (auto it = pos_.find(k); it != pos_.end()) lru_.splice(lru_.end(), lru_, it->second);
            batch.clear();
        }
    }
    bool remove_if_version(const K& k, u64 version) {
        Shard& sh = shard(k);
        std::scoped_lock l(sh.m);
        auto it = sh.map.find(k);
        if (it == sh.map.end() || it->second.version != version) return false;  // never remove a newer value
        sh.map.erase(it);
        size_.fetch_sub(1);
        return true;
    }
    u64 current_version(const K& k) {
        Shard& sh = shard(k);
        std::scoped_lock l(sh.m);
        auto it = sh.map.find(k);
        return it == sh.map.end() ? 0 : it->second.version;
    }
    void expire_and_evict() {  // caller holds eviction_
        const i64 now = ttl_ == INT64_MAX ? 0 : now_();
        while (ttl_ != INT64_MAX && !write_order_.empty()) {
            const auto& [k, ver, deadline] = write_order_.front();
            const bool superseded = current_version(k) != ver;
            if (!superseded && now < deadline) break;
            if (!superseded && remove_if_version(k, ver)) {
                if (auto it = pos_.find(k); it != pos_.end()) {
                    lru_.erase(it->second);
                    pos_.erase(it);
                }
            }
            write_order_.pop_front();
        }
        while (size_.load() > static_cast<i64>(cap_) && !lru_.empty()) {
            auto [k, ver] = lru_.front();
            lru_.pop_front();
            pos_.erase(k);
            remove_if_version(k, ver);
        }
    }
public:
    std::atomic<u64> dropped{0};
    BufferedLru(std::size_t cap, std::optional<std::chrono::nanoseconds> ttl, std::function<i64()> now)
        : cap_(cap), ttl_(ttl ? ttl->count() : INT64_MAX), now_(std::move(now)) {}
    std::optional<V> get(const K& k) override {
        std::optional<V> v;
        {
            Shard& sh = shard(k);
            std::scoped_lock l(sh.m);
            auto it = sh.map.find(k);
            if (it == sh.map.end()) return std::nullopt;
            if (ttl_ != INT64_MAX && now_() >= it->second.deadline) return std::nullopt;  // expired: purge later
            v = it->second.value;
        }
        record(k);
        return v;
    }
    void put(const K& k, V v) override {
        const u64 ver = versions_.fetch_add(1) + 1;
        const i64 deadline = ttl_ == INT64_MAX ? INT64_MAX : now_() + ttl_;
        {
            Shard& sh = shard(k);
            std::scoped_lock l(sh.m);
            auto [it, fresh] = sh.map.insert_or_assign(k, Entry{std::move(v), deadline, ver});
            if (fresh) size_.fetch_add(1);
        }
        std::scoped_lock l(eviction_);
        drain();
        if (current_version(k) == ver) {  // link only if still current: a racing put may have won
            if (auto it = pos_.find(k); it != pos_.end()) {
                lru_.erase(it->second);
                pos_.erase(it);
            }
            lru_.emplace_back(k, ver);
            pos_.emplace(k, std::prev(lru_.end()));
            if (ttl_ != INT64_MAX) write_order_.emplace_back(k, ver, deadline);
        }
        expire_and_evict();
    }
    void clean_up() {
        std::scoped_lock l(eviction_);
        drain();
        expire_and_evict();
    }
    std::size_t size() override { return static_cast<std::size_t>(size_.load()); }
};

// ===== Harness ===================================================================================

u64 request_key(int i, u64& scan) {  // hot set + warm set + one-shot scans: same stream as Java
    if (i % 10'000 < 1'000) return 1'000'000 + scan++;
    const u64 r = mix64(static_cast<u64>(i));
    return r % 10 < 8 ? (r >> 8) % 200 : 1'000 + (r >> 8) % 5'000;
}

double hit_rate(Cache<u64, u64>& c, int requests) {
    u64 scan = 0, hits = 0;
    for (int i = 0; i < requests; ++i) {
        const u64 k = request_key(i, scan);
        if (c.get(k)) ++hits;
        else c.put(k, k);
    }
    return 100.0 * static_cast<double>(hits) / requests;
}

struct Stress { double mops; u64 wrong; std::size_t size_after; };

Stress stress(Cache<u64, u64>& cache, const std::function<void()>& clean_up, int threads, int ops, u64 put_per_mille) {
    std::barrier sync(threads + 1);
    std::atomic<u64> wrong{0};
    std::vector<std::jthread> ts;
    for (int t = 0; t < threads; ++t)
        ts.emplace_back([&, t] {
            sync.arrive_and_wait();
            u64 bad = 0;
            for (int i = 0; i < ops; ++i) {
                const u64 r = mix64(static_cast<u64>(t) * 1'000'003ULL + static_cast<u64>(i));
                const u64 k = r % 10'000;
                if ((r >> 40) % 1'000 < put_per_mille) cache.put(k, k + 10'000ULL * static_cast<u64>(i % 97));
                else if (auto v = cache.get(k); v && *v % 10'000 != k) ++bad;  // a value from another key
            }
            wrong.fetch_add(bad);
            sync.arrive_and_wait();
        });
    sync.arrive_and_wait();
    const auto t0 = std::chrono::steady_clock::now();
    sync.arrive_and_wait();
    const double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    ts.clear();
    clean_up();
    return {threads * static_cast<double>(ops) / secs / 1e6, wrong.load(), cache.size()};
}

int main() {
    std::println("== 1. LRU get() splices the list: it is a WRITE ==");
    LockedLru<std::string, int> demo(0 + 10);
    demo.put("a", 1);
    demo.put("b", 2);
    demo.put("c", 3);
    (void)demo.get("a");
    std::string order;
    for (const auto& k : demo.keys()) order += k;
    std::println("  insert a,b,c then get(a) -> order {} : a shared_lock around get() would race on the splice (UB)", order);

    std::println("== 2. Hit rates on one deterministic stream (300,000 requests, capacity 500) ==");
    constexpr int kRequests = 300'000;
    LockedLru<u64, u64> lru(500);
    LfuCache<u64, u64> lfu(500);
    TinyLfuLru tiny(500);
    const double h_lru = hit_rate(lru, kRequests), h_lfu = hit_rate(lfu, kRequests), h_tiny = hit_rate(tiny, kRequests);
    std::println("  LRU          hit rate {:6.2f}%", h_lru);
    std::println("  LFU          hit rate {:6.2f}%", h_lfu);
    std::println("  TinyLFU+LRU  hit rate {:6.2f}%   (admission rejected {} one-hit wonders)", h_tiny, tiny.rejected);

    std::println("== 3. TTL (expire-after-write) with an injected clock ==");
    std::atomic<i64> fake_now{0};
    BufferedLru<std::string, std::string> ttl(10, std::chrono::minutes(5), [&] { return fake_now.load(); });
    ttl.put("seat-7", "alice");
    fake_now += std::chrono::nanoseconds(std::chrono::minutes(5)).count() - 1;
    const auto before = ttl.get("seat-7");
    fake_now += 1;
    const auto at = ttl.get("seat-7");
    const auto size_before = ttl.size();
    ttl.clean_up();
    std::println("  get at TTL-1ns = {}, get at TTL = {}, size before clean_up = {}, after = {}", before.value_or("null"),
                 at.value_or("null"), size_before, ttl.size());

    std::println("== 4. Concurrency: 4 threads x 2,000,000 ops, 10,000 keys, capacity 1,000, no expiry ==");
    bool all_ok = true;
    for (u64 put_per_mille : {100ULL, 10ULL}) {
        LockedLru<u64, u64> locked(1'000);
        BufferedLru<u64, u64> buffered(1'000, std::nullopt, [] { return i64{0}; });
        stress(locked, [] {}, 4, 200'000, put_per_mille);
        stress(buffered, [&] { buffered.clean_up(); }, 4, 200'000, put_per_mille);
        const auto a = stress(locked, [] {}, 4, 2'000'000, put_per_mille);
        const auto b = stress(buffered, [&] { buffered.clean_up(); }, 4, 2'000'000, put_per_mille);
        std::println("  {:4.1f}% puts  LockedLru   (one exclusive lock)          {:6.1f} M ops/s  wrong values {}  size {}",
                     static_cast<double>(put_per_mille) / 10.0, a.mops, a.wrong, a.size_after);
        std::println("  {:4.1f}% puts  BufferedLru (sharded map + read buffers)  {:6.1f} M ops/s  wrong values {}  size {}  dropped hints {}",
                     static_cast<double>(put_per_mille) / 10.0, b.mops, b.wrong, b.size_after, buffered.dropped.load());
        all_ok &= a.wrong == 0 && b.wrong == 0 && a.size_after <= 1'000 && b.size_after <= 1'000;
    }
    const bool ok = h_tiny > h_lru && before == "alice" && !at && ttl.size() == 0 && all_ok;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2 (one measured run for part 4):**

```text
== 1. LRU get() splices the list: it is a WRITE ==
  insert a,b,c then get(a) -> order bca : a shared_lock around get() would race on the splice (UB)
== 2. Hit rates on one deterministic stream (300,000 requests, capacity 500) ==
  LRU          hit rate  70.90%
  LFU          hit rate  73.03%
  TinyLFU+LRU  hit rate  72.84%   (admission rejected 67811 one-hit wonders)
== 3. TTL (expire-after-write) with an injected clock ==
  get at TTL-1ns = alice, get at TTL = null, size before clean_up = 1, after = 0
== 4. Concurrency: 4 threads x 2,000,000 ops, 10,000 keys, capacity 1,000, no expiry ==
  10.0% puts  LockedLru   (one exclusive lock)             8.7 M ops/s  wrong values 0  size 1000
  10.0% puts  BufferedLru (sharded map + read buffers)     4.7 M ops/s  wrong values 0  size 1000  dropped hints 6762
   1.0% puts  LockedLru   (one exclusive lock)             9.6 M ops/s  wrong values 0  size 1000
   1.0% puts  BufferedLru (sharded map + read buffers)    17.4 M ops/s  wrong values 0  size 1000  dropped hints 4877
SELF-TEST OK
```

**Output, Clang 21.1 (one measured run for part 4):**

```text
== 1. LRU get() splices the list: it is a WRITE ==
  insert a,b,c then get(a) -> order bca : a shared_lock around get() would race on the splice (UB)
== 2. Hit rates on one deterministic stream (300,000 requests, capacity 500) ==
  LRU          hit rate  70.90%
  LFU          hit rate  73.03%
  TinyLFU+LRU  hit rate  72.84%   (admission rejected 67811 one-hit wonders)
== 3. TTL (expire-after-write) with an injected clock ==
  get at TTL-1ns = alice, get at TTL = null, size before clean_up = 1, after = 0
== 4. Concurrency: 4 threads x 2,000,000 ops, 10,000 keys, capacity 1,000, no expiry ==
  10.0% puts  LockedLru   (one exclusive lock)            16.6 M ops/s  wrong values 0  size 1000
  10.0% puts  BufferedLru (sharded map + read buffers)     7.3 M ops/s  wrong values 0  size 1000  dropped hints 5012
   1.0% puts  LockedLru   (one exclusive lock)            22.9 M ops/s  wrong values 0  size 1000
   1.0% puts  BufferedLru (sharded map + read buffers)    30.9 M ops/s  wrong values 0  size 1000  dropped hints 3827
SELF-TEST OK
```

## 6. Reading the results

**Admission beats recency on polluted streams.**

| Policy | Hit rate (Java = C++) | Why |
|---|---|---|
| LRU | 70.90% | Every 1,000-key scan flushes the hot set out of a 500-entry cache |
| LFU | 73.03% | Hot keys accumulate frequency, so scan keys evict only each other |
| TinyLFU + LRU | 72.84% | 67,811 one-hit wonders were refused admission. Nearly LFU's hit rate, with LRU's O(1) simplicity, and with *aging*, which plain LFU lacks (an old popular key never leaves an LFU cache) |

Java and C++ produce bit-identical counts, which validates both policy implementations against each other.

**Lock-free reads win when reads dominate, and only then.**

| Mix (4 threads) | Java LockedLru | Java BufferedLru | C++ (GCC) Locked → Buffered | C++ (Clang) Locked → Buffered |
|---|---|---|---|---|
| 99% get / 1% put | 16.7 M ops/s | **47.9 M ops/s (2.9×)** | 9.6 → **17.4** | 22.9 → **30.9** |
| 90% get / 10% put | 13.9 | 13.9 (tie) | 8.7 → 4.7 (slower) | 16.6 → 7.3 (slower) |

At 10% writes, every `put` takes the eviction lock and drains all stripes synchronously. The policy lock becomes the same bottleneck as the single lock, and the C++ version pays three shard-lock acquisitions per put on top. That is **the measured reason Caffeine buffers writes and runs maintenance asynchronously**. In an interview, the L7 sentence is: "My read path is lock-free. My write path still serializes on the policy lock, so the next step is a write buffer drained by the same maintenance task."

The first Java run was also slower than the single lock (12.4 vs 14.2 M ops/s), for two avoidable reasons:
- every `get` read `System.nanoTime()` even with expiry effectively off;
- each `get` picked a *random* stripe, so threads fought over each other's CAS.

Skipping the clock when there's no TTL and using stable per-thread stripes, as Caffeine does, produced the table above. Profile before claiming a design is faster.

## 7. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Structure | `LinkedHashMap(accessOrder)` + `synchronized` | HashMap + hand-rolled doubly linked list, O(1) | Data plane (concurrent map) separated from policy plane (single-writer, batched) |
| Reads | Take the lock | "Use a read lock", which is **wrong** for LRU | Lock-free lookup + lossy access recording + amortized drain under `tryLock` |
| Eviction policy | LRU | LRU or LFU on request | Admission (TinyLFU) + aging; W-TinyLFU explained; policy chosen by workload (scan resistance) |
| Expiry | A background thread scanning everything | Lazy check on `get` | Lazy visibility check + O(1) purge from a write-order queue; timer wheel for variable TTL; injected ticker |
| Races | Not considered | One lock | Link-if-current, conditional removal, unpublished-slot handling; C++ reclamation addressed by recording keys |
| Evidence | Demo | Unit tests | Hit-rate simulation on a scan-polluted stream + multi-threaded stress with invariant checks + throughput by read/write mix |

## 8. Curveballs and 5-minute refactors

| Curveball | Response |
|---|---|
| "Make it a loading cache: `get(k, loader)` with no stampede" | `computeIfAbsent(k, k -> new CompletableFuture<>())` installs a placeholder atomically. The loader runs **outside** the bin lock (01.3 §6). Concurrent callers join the same future; failures remove the placeholder |
| "Refresh entries asynchronously after 1 minute but keep serving stale" | Refresh-after-write: on access past the refresh time, serve the old value and trigger one async reload (a CAS on a `refreshing` flag) |
| "Per-entry TTL" | The FIFO write-order deque no longer equals expiry order. Use a hierarchical timer wheel (P3), with each node holding its wheel slot |
| "Size by weight (bytes), not count" | Track a weight sum in the policy plane; evict while `weight > max`; the weigher runs at `put` |
| "Hit rate dropped after a batch job" | Exactly the scan pattern in §6: add TinyLFU admission, or segment protected/probationary LRU |
| "Writes are 30% of traffic" | Add a write buffer (an MPSC queue of `AddTask`/`UpdateTask`) drained by maintenance. `put` then updates the map and enqueues: no lock |
| "Expose stats" | `LongAdder` hits/misses/evictions in the hot path (01.3 §3); never a shared `AtomicLong` |

## 9. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "Reads are 99% of traffic. Use a ReadWriteLock so gets run in parallel?"</b></summary>

**L5:** "Yes, `get` takes the read lock, `put` the write lock."

**Why it fails:** an LRU `get` *reorders the list*. Two read-locked readers relink the same nodes concurrently and corrupt it. Java even throws `ConcurrentModificationException` single-threaded when you iterate during `get`. In C++ it's a data race, which is UB.

**L7 defence:** "Separate lookup from ordering. Lookups go to a concurrent map with no lock. Accesses are recorded into a lossy striped buffer and replayed by one maintenance thread under `tryLock`. Order becomes eventually consistent, which LRU tolerates. That's Caffeine's design, and it measured 2.9× the single lock at 99% reads."
</details>

<details>
<summary><b>Q2 ⚡ "Your buffered cache isn't faster at 10% writes. Why?"</b></summary>

**L5:** "Concurrency overhead."

**Why it fails:** that's a description, not a diagnosis.

**L7 defence:** "Every `put` takes the policy lock and drains synchronously, so writes serialize exactly as before, and at 10% writes the lock is saturated. Caffeine queues writes into a buffer, updates the map immediately, and lets an async maintenance task apply policy changes. I'd also check the hot path for hidden costs: a `nanoTime` per get, random stripes. Removing those moved my 10%-write result from 12.4 to 13.9 M ops/s."
</details>

<details>
<summary><b>Q3 ⚡ "Eviction removes key k while another thread puts a new value for k. What happens?"</b></summary>

**L5:** "The lock prevents it."

**Why it fails:** the map update happens *outside* the policy lock in a lock-free design. An unconditional `remove(k)` during eviction deletes the newer value.

**L7 defence:** "Removal is conditional on identity: `remove(k, victimNode)` in Java, remove-if-version in C++. Linking is conditional too, only if the node is still the current mapping. I1 and I4 hold under every interleaving, and the stress test checks I1 on every hit."
</details>

<details>
<summary><b>Q4 🧊 "Why does LFU need aging, and why is TinyLFU an admission policy rather than an eviction policy?"</b></summary>

**L5:** "LFU evicts the least frequent; that's it."

**Why it fails:** pure LFU never forgets. Yesterday's viral key keeps its count and squats in the cache forever. Exact LFU also needs a counter per key, including keys that were evicted.

**L7 defence:** "TinyLFU keeps approximate frequencies for *all* recent keys in a few kilobytes (count-min sketch, 4-bit counters) and halves them periodically, so popularity decays. It doesn't pick victims: LRU or SLRU does. It only decides whether a newcomer is worth evicting that victim for, which is what makes it scan-resistant at O(1) cost."
</details>

## 10. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| Corrupted list / hang under load | Read lock around an access-ordered `get` | Exclusive lock, or the buffered design |
| Throughput flat as cores grow | Every read takes the cache lock | Lock-free data plane + read buffers |
| Fresh value disappears right after `put` | Unconditional eviction of the key | Conditional removal by identity/version |
| Hit rate collapses during batch scans | Pure LRU | TinyLFU admission / segmented LRU |
| Stale entries served past their TTL | Expiry only by a background sweeper | Deadline check on `get` (I3) |
| C++ crash in the drain | Raw node pointers recorded and then freed by eviction | Record keys / versions; policy-owned index |
| Thundering herd on a miss | `get` → load → `put` race | Future placeholder via `computeIfAbsent` |

- [ ] `get` never takes a lock that would serialize readers (or the single lock is a justified baseline).
- [ ] Eviction and expiry remove only the same entry they chose.
- [ ] The size bound holds after quiescence; the overshoot is bounded and documented.
- [ ] Expiry is visible immediately (checked on read) and reclaimed lazily.
- [ ] Time is injected; there are no clock reads on the hot path when expiry is off.
- [ ] Hit-rate behaviour is tested on a stream with scans, not just uniform keys.

## 11. References

- Ben Manes, Caffeine design wiki. <https://github.com/ben-manes/caffeine/wiki/Design>
- Gil Einziger, Roy Friedman, Ben Manes, "TinyLFU: A Highly Efficient Cache Admission Policy", *ACM ToS* 2017. <https://arxiv.org/abs/1512.00727>
- Caffeine source: `BoundedLocalCache`, `BoundedBuffer`, `FrequencySketch`, `TimerWheel`. <https://github.com/ben-manes/caffeine/tree/master/caffeine/src/main/java/com/github/benmanes/caffeine/cache>
- JDK `LinkedHashMap` (access order, `removeEldestEntry`). <https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/LinkedHashMap.html>
- Graham Cormode and S. Muthukrishnan, "An Improved Data Stream Summary: The Count-Min Sketch", 2005. <https://doi.org/10.1016/j.jalgor.2003.12.001>
- In this KB: [01.3 CAS, false sharing, CHM bins](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md) · [P3 timing wheel](03-problem-03-delayed-job-scheduler-and-hierarchical-timing-wheel.md) · P18 multi-level cache (Folder 06)
