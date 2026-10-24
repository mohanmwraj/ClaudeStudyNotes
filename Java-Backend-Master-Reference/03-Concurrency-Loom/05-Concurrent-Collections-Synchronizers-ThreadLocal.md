# 3.5 · Concurrent Collections, Synchronizers & `ThreadLocal` Internals

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut · 🎓 exam ("concurrent collections", `CyclicBarrier`, `CountDownLatch`, `Semaphore`, `ConcurrentHashMap`)
> **Sources:** `java.util.concurrent` Javadoc and source (JDK 25): `ArrayBlockingQueue`, `LinkedBlockingQueue`, `SynchronousQueue`, `LinkedTransferQueue`, `DelayQueue`, `CopyOnWriteArrayList`, `ConcurrentSkipListMap`, `Phaser`, `ThreadLocal`.
> `ConcurrentHashMap` internals are in [2.1 §9](../02-Core-Java/01-Collections-Internals.md#9-concurrenthashmap-internals-jdk-8-). This file covers the rest of the toolbox.

---

## 1. `BlockingQueue` — the producer/consumer workhorse 🔥🎓

### 1.1 The four method families (an exam staple)

| Operation | Throws exception | Returns special value | Blocks | Times out |
|---|---|---|---|---|
| Insert | `add(e)` → `IllegalStateException` if full | `offer(e)` → `false` | `put(e)` | `offer(e, time, unit)` |
| Remove | `remove()` → `NoSuchElementException` if empty | `poll()` → `null` | `take()` | `poll(time, unit)` |
| Examine | `element()` → `NoSuchElementException` | `peek()` → `null` | — | — |

`null` elements are **always rejected** (NPE), because `null` is the "empty" signal of `poll`.

<!-- run: -->
```java
import java.util.concurrent.*;

public class QueueApi {
    static String attempt(Callable<Object> c) {
        try { return String.valueOf(c.call()); } catch (Exception e) { return e.getClass().getSimpleName(); }
    }
    public static void main(String[] args) {
        BlockingQueue<String> q = new ArrayBlockingQueue<>(1);
        System.out.println("offer(a)=" + attempt(() -> q.offer("a")) + " offer(b)=" + attempt(() -> q.offer("b"))
            + " add(b)=" + attempt(() -> q.add("b")) + " offer(b,50ms)=" + attempt(() -> q.offer("b", 50, TimeUnit.MILLISECONDS)));
        System.out.println("peek=" + attempt(q::peek) + " poll=" + attempt(q::poll) + " poll=" + attempt(q::poll)
            + " remove=" + attempt(q::remove) + " element=" + attempt(q::element) + " poll(50ms)=" + attempt(() -> q.poll(50, TimeUnit.MILLISECONDS)));
        System.out.println("offer(null)=" + attempt(() -> q.offer(null)) + " remainingCapacity=" + q.remainingCapacity());
    }
}
```

Output (verified):

```
offer(a)=true offer(b)=false add(b)=IllegalStateException offer(b,50ms)=false
peek=a poll=a poll=null remove=NoSuchElementException element=NoSuchElementException poll(50ms)=null
offer(null)=NullPointerException remainingCapacity=1
```

### 1.2 Implementations and their internals

| Queue | Bound | Locking | Internals and notes |
|---|---|---|---|
| `ArrayBlockingQueue` | Bounded (fixed array) | **One** `ReentrantLock` + `notEmpty`/`notFull` conditions; optional fairness | No per-element allocation; producers and consumers contend on one lock |
| `LinkedBlockingQueue` | Optional bound (default `Integer.MAX_VALUE`!) | **Two locks** (`putLock`, `takeLock`) + `AtomicInteger count` | Producers and consumers don't block each other, so throughput is higher. One `Node` per element (GC churn) |
| `LinkedBlockingDeque` | Optional bound | One lock | Work-stealing-style use (both ends) |
| `PriorityBlockingQueue` | **Unbounded** | One lock, binary heap | `put` never blocks, so it can grow to OOM. Iteration is not ordered |
| `DelayQueue` | Unbounded | One lock + leader/follower waiting | Elements implement `Delayed`; `take` returns only expired ones (retry and timeout schedulers) |
| `SynchronousQueue` | **Zero capacity** | Lock-free dual stack (non-fair) or dual queue (fair) | Each `put` waits for a `take`: pure hand-off (`newCachedThreadPool`) |
| `LinkedTransferQueue` | Unbounded | Lock-free dual queue | `transfer(e)` blocks until a consumer receives it; `tryTransfer` |
| `ConcurrentLinkedQueue` / `Deque` | Unbounded, **non-blocking** | Lock-free (Michael–Scott) | **`size()` is O(n)** and only an estimate; use `isEmpty()` |

**Backpressure rule:** a bounded `BlockingQueue` between stages *is* backpressure: producers block (or get `false`) when consumers fall behind. An unbounded queue converts overload into memory growth and unbounded latency.

---

## 2. Other concurrent collections ⚡🎓

### 2.1 `CopyOnWriteArrayList` / `CopyOnWriteArraySet`

* Every mutation **copies the entire array** under a lock, then publishes the new array via a volatile write. Reads and iteration are lock-free on an immutable **snapshot**.
* **Good for:** listener lists, configuration snapshots, routing tables: read-mostly, small, rarely changed.
* **Bad for:** anything written frequently. Each `add` is O(n) and allocates a new array (measured below). The iterator's `remove()` is unsupported.

<!-- run: timeout=120 -->
```java
import java.util.*;
import java.util.concurrent.CopyOnWriteArrayList;

public class CowCost {
    static long timeAdds(List<Integer> list, int n) {
        long t = System.nanoTime();
        for (int i = 0; i < n; i++) list.add(i);
        return (System.nanoTime() - t) / 1_000_000;
    }
    public static void main(String[] args) {
        for (int round = 0; round < 2; round++) {
            long arr = timeAdds(Collections.synchronizedList(new ArrayList<>()), 50_000);
            long cow = timeAdds(new CopyOnWriteArrayList<>(), 50_000);
            if (round == 1) System.out.println("50,000 adds: synchronizedList " + arr + " ms vs CopyOnWriteArrayList " + cow + " ms");
        }
        List<String> listeners = new CopyOnWriteArrayList<>(List.of("audit", "metrics"));
        Iterator<String> snapshot = listeners.iterator();
        listeners.add("alerts");
        List<String> seen = new ArrayList<>(); snapshot.forEachRemaining(seen::add);
        System.out.println("iterator created before add sees " + seen + "; list now " + listeners);
    }
}
```

One measured run:

```
50,000 adds: synchronizedList 1 ms vs CopyOnWriteArrayList 336 ms
iterator created before add sees [audit, metrics]; list now [audit, metrics, alerts]
```

### 2.2 `ConcurrentSkipListMap` / `ConcurrentSkipListSet`

A lock-free **skip list**: sorted, O(log n) expected, with `NavigableMap` operations (`ceilingKey`, `headMap`, `pollFirstEntry`), and weakly consistent iterators. Use it when you need **ordering plus concurrency**: time-ordered event buffers, leaderboards, rate-limiter windows, order books. It uses more memory per entry than `ConcurrentHashMap` (index nodes).

### 2.3 `Collections.synchronizedX` and `Vector`/`Hashtable`

Every method is synchronized on one mutex, but **compound actions are not atomic**:

<!-- run: -->
```java
import java.util.*;
import java.util.concurrent.*;

public class CompoundActions {
    public static void main(String[] args) throws Exception {
        List<Integer> list = Collections.synchronizedList(new ArrayList<>());
        Set<Integer> chmSet = ConcurrentHashMap.newKeySet();
        ExecutorService pool = Executors.newFixedThreadPool(8);
        List<Callable<Void>> tasks = new ArrayList<>();
        for (int t = 0; t < 8; t++) tasks.add(() -> {
            for (int i = 0; i < 2_000; i++) {
                if (!list.contains(i)) list.add(i);           // check-then-act: NOT atomic even on a synchronized list
                chmSet.add(i);                                // atomic put-if-absent
            }
            return null;
        });
        pool.invokeAll(tasks);
        pool.shutdown();
        System.out.println("synchronizedList size=" + list.size() + " (expected 2000; extra = duplicates from races)");
        System.out.println("ConcurrentHashMap.newKeySet size=" + chmSet.size());

        List<Integer> safe = Collections.synchronizedList(new ArrayList<>());
        synchronized (safe) {                                 // correct: hold the list's own lock for compound actions
            if (!safe.contains(1)) safe.add(1);
            for (Integer i : safe) { }                        // iteration must also hold the lock (or risk CME)
        }
        System.out.println("guarded compound action ok: " + safe);
    }
}
```

Output (one verified run; the duplicate count varies, and is occasionally 0):

```
synchronizedList size=2449 (expected 2000; extra = duplicates from races)
ConcurrentHashMap.newKeySet size=2000
guarded compound action ok: [1]
```

---

## 3. Synchronizers 🔥🎓

| Synchronizer | Purpose | Reusable? | Key methods | Typical use |
|---|---|---|---|---|
| `CountDownLatch` | Wait until N events happen | ❌ one-shot | `countDown()`, `await()`, `await(t, u)` | Wait for N services to initialize; test start gates |
| `CyclicBarrier` | N threads wait for **each other**, then optionally run a barrier action | ✅ | `await()` → arrival index; `BrokenBarrierException` if any party fails, times out or is interrupted | Iterative parallel algorithms (simulation steps) |
| `Phaser` | Dynamic-party barrier with numbered phases | ✅ | `register`, `arriveAndAwaitAdvance`, `arriveAndDeregister`, `onAdvance` | Phased workflows where parties join and leave |
| `Semaphore` | Limit concurrent access to N permits | ✅ | `acquire`, `tryAcquire(t, u)`, `release`; fair option | **Concurrency limits** (bulkheads), especially with virtual threads |
| `Exchanger` | Two threads swap objects at a rendezvous | ✅ | `exchange(v)` | Double-buffering pipelines |

<!-- run: -->
```java
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

public class SynchronizersTour {
    public static void main(String[] args) throws Exception {
        // CountDownLatch: main waits until 3 "services" are ready
        CountDownLatch ready = new CountDownLatch(3);
        for (String svc : List.of("db", "cache", "broker")) Thread.ofPlatform().start(() -> { sleep(20); ready.countDown(); });
        System.out.println("latch released: " + ready.await(1, TimeUnit.SECONDS) + ", count=" + ready.getCount());

        // CyclicBarrier: 3 workers do 2 steps in lock-step; the barrier action runs once per step
        List<String> log = Collections.synchronizedList(new ArrayList<>());
        CyclicBarrier barrier = new CyclicBarrier(3, () -> log.add("--step done--"));
        List<Thread> ws = new ArrayList<>();
        for (int w = 0; w < 3; w++) {
            int id = w;
            ws.add(Thread.ofPlatform().start(() -> {
                try { for (int step = 1; step <= 2; step++) { log.add("w" + id + "s" + step); barrier.await(); } }
                catch (Exception e) { throw new RuntimeException(e); }
            }));
        }
        for (Thread t : ws) t.join();
        long stepMarkers = log.stream().filter(s -> s.startsWith("--")).count();
        System.out.println("barrier: " + (log.size() - stepMarkers) + " work items, " + stepMarkers + " barrier actions, last entry=" + log.getLast());

        // Semaphore: at most 2 concurrent "DB calls" out of 10 tasks
        Semaphore permits = new Semaphore(2);
        AtomicInteger inFlight = new AtomicInteger(), maxSeen = new AtomicInteger();
        try (var ex = Executors.newVirtualThreadPerTaskExecutor()) {
            for (int i = 0; i < 10; i++) ex.submit(() -> {
                permits.acquire();
                try { maxSeen.accumulateAndGet(inFlight.incrementAndGet(), Math::max); sleep(30); inFlight.decrementAndGet(); }
                finally { permits.release(); }
                return null;
            });
        }
        System.out.println("semaphore: max concurrent = " + maxSeen.get());

        // Phaser: parties register dynamically; onAdvance can terminate
        Phaser phaser = new Phaser(1) { @Override protected boolean onAdvance(int phase, int parties) { return phase >= 2 || parties == 0; } };
        for (int p = 0; p < 2; p++) {
            phaser.register();
            Thread.ofPlatform().start(() -> { while (!phaser.isTerminated()) phaser.arriveAndAwaitAdvance(); });
        }
        while (!phaser.isTerminated()) phaser.arriveAndAwaitAdvance();
        System.out.println("phaser terminated after phase " + (phaser.getPhase() + Integer.MIN_VALUE) + " (phases 0,1,2 completed)");

        // Exchanger: two threads swap buffers
        Exchanger<String> exch = new Exchanger<>();
        Thread filler = Thread.ofPlatform().start(() -> { try { System.out.println("filler got back: " + exch.exchange("FULL buffer")); } catch (InterruptedException e) { } });
        System.out.println("drainer got: " + exch.exchange("EMPTY buffer"));
        filler.join();
    }
    static void sleep(long ms) { try { Thread.sleep(ms); } catch (InterruptedException e) { Thread.currentThread().interrupt(); } }
}
```

Output (verified; the two Exchanger lines may appear in either order):

```
latch released: true, count=0
barrier: 6 work items, 2 barrier actions, last entry=--step done--
semaphore: max concurrent = 2
phaser terminated after phase 3 (phases 0,1,2 completed)
drainer got: FULL buffer
filler got back: EMPTY buffer
```

(After termination, `getPhase()` returns a negative number. Adding `Integer.MIN_VALUE` recovers the phase that was reached.)

---

## 4. `ThreadLocal` internals and its pitfalls 🔥

### 4.1 Structure

```
Thread
 └── ThreadLocal.ThreadLocalMap threadLocals          (lazily created per thread)
       Entry[] table        open addressing with LINEAR PROBING; power-of-two size; resize at 2/3 load
       Entry extends WeakReference<ThreadLocal<?>> { Object value; }   ← KEY weak, VALUE strong
 ThreadLocal.threadLocalHashCode = nextHashCode += 0x61c88647   (Fibonacci hashing: spreads keys evenly)
```

* `get()` hashes the `ThreadLocal` into the **current thread's** map, so there is no contention. That's why it's fast.
* **Weak keys, strong values:** if a `ThreadLocal` object becomes unreachable, its entry's key is cleared, but the **value stays strongly referenced** until a later `get`/`set`/`remove` happens to probe that slot and expunge it ("stale entries"). On long-lived pooled threads this is a leak, and if the value's class came from a webapp loader, it's a ClassLoader leak ([1.1 §7.1](../01-JVM-Internals/01-ClassLoading-Linking-JPMS.md#71-runnable-unloading-works--until-a-threadlocal-pins-the-loader)).
* `InheritableThreadLocal` copies values **when a thread is created**, so it doesn't help with pools (threads are created once and reused) and is copied for every new virtual thread.

### 4.2 Runnable: context bleeding between pooled tasks (the MDC bug)

<!-- run: -->
```java
import java.util.concurrent.*;

public class ThreadLocalBleed {
    static final ThreadLocal<String> USER = new ThreadLocal<>();     // e.g. MDC, security context, tenant id

    static String handle(String user, boolean cleanUp) {
        if (user != null) USER.set(user);                            // request 2 is unauthenticated: nothing set
        try { return "request sees user=" + USER.get(); }
        finally { if (cleanUp) USER.remove(); }
    }

    public static void main(String[] args) throws Exception {
        ExecutorService pool = Executors.newSingleThreadExecutor();   // 1 thread → reuse guaranteed
        System.out.println("no cleanup:   " + pool.submit(() -> handle("alice", false)).get()
            + " | " + pool.submit(() -> handle(null, false)).get() + "  ← leaked into the next request!");
        pool.submit(() -> USER.remove()).get();
        System.out.println("with remove:  " + pool.submit(() -> handle("alice", true)).get()
            + " | " + pool.submit(() -> handle(null, true)).get());
        pool.shutdown();
    }
}
```

Output (verified):

```
no cleanup:   request sees user=alice | request sees user=alice  ← leaked into the next request!
with remove:  request sees user=alice | request sees user=null
```

A security bug in one picture: an anonymous request executed as `alice` because the pooled thread still carried her context. **Rule:** `set` → `try` → `finally remove()`. Frameworks (Spring's `RequestContextHolder`, `SecurityContextHolder`, logging MDC filters) do this at request boundaries. Custom `ThreadLocal` usage must too.

### 4.3 `ThreadLocal` vs virtual threads vs `ScopedValue`

| | `ThreadLocal` | `ScopedValue` (final in JDK 25) |
|---|---|---|
| Mutability | Mutable (`set` anywhere) | Immutable binding for a dynamic scope |
| Lifetime | Until `remove()` or thread death, so leaks are possible | Bounded by `where(...).run/call`, so no leaks |
| Inheritance to child threads | Copy on thread creation (Inheritable) | Inherited automatically by `StructuredTaskScope` forks, without copying |
| Cost per thread | A map plus entries per thread: **millions of VTs × each ThreadLocal** | A cheap lookup, no per-thread map |
| Use | Legacy libraries, per-thread caches (avoid with VTs) | Request context, tenant, user, trace IDs |

Details and examples in [3.6](06-Virtual-Threads-Structured-Concurrency-Scoped-Values.md).

---

## 5. Production failure modes & diagnostics

| Failure | Signature | Fix |
|---|---|---|
| `LinkedBlockingQueue()` without a bound | Heap growth with `LinkedBlockingQueue$Node` dominating; rising latency | Set capacity; reject or shed load |
| `PriorityBlockingQueue`/`DelayQueue` growth | Same; `put` never blocks | Admission control upstream |
| `CopyOnWriteArrayList` written frequently | CPU and allocation in `Arrays.copyOf`; GC pressure | Concurrent queue/map, or batch updates into one new snapshot |
| `ConcurrentLinkedQueue.size()` in hot paths | O(n) CPU | Track a separate `LongAdder`/`AtomicInteger` count; use `isEmpty()` |
| Check-then-act on synchronized collections | Duplicates or lost updates (measured: 449 duplicates in one run) | Concurrent collections' atomic methods (`putIfAbsent`, `computeIfAbsent`, `newKeySet().add`) or explicit locking |
| `CyclicBarrier` broken | `BrokenBarrierException` cascades after one party's timeout or interrupt | Handle it, reset, or design for party failure (`Phaser` with deregistration) |
| `CountDownLatch` never reaches zero | Threads `WAITING` in `await()` forever | Always `countDown` in `finally`; await with a timeout |
| ThreadLocal leaks or bleed | Wrong user/tenant/trace in logs; ClassLoader leaks on redeploy | `remove()` in `finally`; prefer `ScopedValue` |
| Semaphore permit leaks | Throughput slowly drops to zero | `release()` in `finally`; `tryAcquire` with a timeout; monitor `availablePermits()` |

---

## 6. Interview & certification Q&A

<details><summary><b>Q1. 🎓 Which `BlockingQueue` method blocks when the queue is full, which returns `false`, and which throws?</b></summary>

`put` blocks, `offer` returns `false` (or waits up to a timeout with `offer(e, t, unit)`), and `add` throws `IllegalStateException`. For removal: `take` blocks, `poll` returns `null` (or waits with a timeout), and `remove()` throws `NoSuchElementException`.
</details>

<details><summary><b>Q2. 🔥 `ArrayBlockingQueue` vs `LinkedBlockingQueue`: when do you pick each?</b></summary>

`ArrayBlockingQueue`: fixed preallocated array, one lock, no per-element allocation, optional fairness. Predictable memory, but producers and consumers contend on one lock. `LinkedBlockingQueue`: separate put and take locks, so higher throughput under concurrent producers and consumers, but it allocates a node per element and is **unbounded by default**. Always give it a capacity.
</details>

<details><summary><b>Q3. 🎓 `CountDownLatch` vs `CyclicBarrier`?</b></summary>

A latch is one-shot: any threads count down, and waiters proceed when the count hits zero; the counters and the waiters can be different threads. A barrier is reusable: a fixed number of parties wait for each other at the barrier, then all proceed together (optionally after a barrier action). If one party fails, the others get `BrokenBarrierException`.
</details>

<details><summary><b>Q4. 🔥 Why can `ThreadLocal` leak memory even though its map uses weak references?</b></summary>

Only the **key** (the `ThreadLocal` object) is weak. The **value** is strongly referenced from the thread's map entry, and stale entries are only expunged opportunistically during later map operations. On long-lived pool threads the values (and their classes' loaders) stay reachable. Call `remove()` when done.
</details>

<details><summary><b>Q5. ⚡ When is `CopyOnWriteArrayList` the right choice?</b></summary>

Read-mostly, small collections iterated far more often than modified, such as listener lists or routing snapshots. Iteration needs no locking and never throws CME. Every write copies the array (measured: 336 ms for 50k adds vs 1 ms for a synchronized list), so it's wrong for frequent writes.
</details>

<details><summary><b>Q6. ⚡ Is `if (!syncList.contains(x)) syncList.add(x)` thread-safe on `Collections.synchronizedList`?</b></summary>

No. Each call is synchronized individually, but another thread can add `x` between them (measured: 449 duplicates in one run). Hold the list's lock across the compound action (`synchronized (syncList) { … }`) or use an atomic API (`ConcurrentHashMap.newKeySet().add(x)`).
</details>

<details><summary><b>Q7. 🔥 How would you limit concurrent calls to a downstream service from virtual threads?</b></summary>

A `Semaphore` with N permits (or a bulkhead such as Resilience4j's): `acquire` (or `tryAcquire` with a timeout) before the call, and `release` in `finally`. Don't use a fixed thread pool for this: with virtual threads, threads are cheap and the limit must be on the resource, not the thread count.
</details>

---

## 7. Further reading

* `java.util.concurrent` package summary (queue method table, memory consistency effects).
* *Java Concurrency in Practice*, ch. 5 (building blocks) and ch. 14 (custom synchronizers).
* `ThreadLocal` source (the `ThreadLocalMap` implementation comments).
