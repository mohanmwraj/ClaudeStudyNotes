# 3.8 · Pillar 3 — Interview & Certification Question Bank (Concurrency & Loom)

> **Use:** A = flashcards, B = senior and architect scenarios, C = 1Z0-830/831-style code questions (original practice items). **Every program in C was run on JDK 25**, and each answer shows the real output. Questions whose output depends on scheduling are phrased as "which outputs are *possible*".

---

## A. Rapid-fire

<details><summary><b>A1–A15</b></summary>

1. **What creates happens-before between a volatile write and a read?** A read that sees the write is ordered after it (synchronizes-with).
2. **Is `count++` on a volatile atomic?** No: it's read-modify-write.
3. **What reordering does x86 permit?** StoreLoad only.
4. **How does HotSpot implement a volatile store on x86?** `mov` + `lock addl $0,(rsp)` (a full fence).
5. **Default locking mode for `synchronized` since JDK 23?** Lightweight locking (lock-stack); inflation to `ObjectMonitor` on contention.
6. **Thread state while waiting to enter `synchronized`?** `BLOCKED`.
7. **Thread state while waiting on a `ReentrantLock`?** `WAITING` (parking), or `TIMED_WAITING` with a timeout.
8. **Can a `ReentrantReadWriteLock` read lock be upgraded?** No (self-deadlock). Downgrading is OK.
9. **What does `StampedLock.tryOptimisticRead` cost?** No writes to shared memory: just reading the state, plus `validate`.
10. **What is AQS's `state`?** A volatile int whose meaning the subclass defines (hold count, permits, latch count).
11. **`AtomicLong` vs `LongAdder` under contention?** `LongAdder` scales via striped `@Contended` cells.
12. **What is ABA?** The value changes A→B→A, so a stale CAS succeeds. Fix with version stamps.
13. **`newFixedThreadPool`'s queue?** Unbounded `LinkedBlockingQueue`.
14. **`newCachedThreadPool`'s risk?** Unbounded thread creation (`SynchronousQueue`, max = `Integer.MAX_VALUE`).
15. **When does a `ThreadPoolExecutor` grow past core?** Only when the queue rejects an offer (is full).
</details>

<details><summary><b>A16–A30</b></summary>

16. **What happens to an exception in a task passed to `submit`?** It is stored in the `Future`, and is lost unless `get()` is called.
17. **What happens to a periodic scheduled task after it throws?** All future runs are suppressed.
18. **`CompletableFuture.cancel(true)` interrupts the task?** No.
19. **Default executor for `supplyAsync`?** `ForkJoinPool.commonPool()` (or a new thread per task if parallelism < 2).
20. **What does `join()` throw vs `get()`?** `CompletionException` (unchecked) vs `ExecutionException` (checked).
21. **What is the virtual-thread scheduler?** A dedicated FIFO-mode `ForkJoinPool`, parallelism = cores.
22. **Does `synchronized` pin virtual threads in JDK 25?** No (JEP 491, JDK 24). Native frames and `<clinit>` still do.
23. **Which JFR event reports pinning?** `jdk.VirtualThreadPinned` (fields include `pinnedReason`, `carrierThread`).
24. **Are virtual threads daemon?** Always.
25. **Can virtual threads time-slice CPU-bound work?** No: a VT runs until it blocks or ends.
26. **How do you list all virtual threads?** `jcmd <pid> Thread.dump_to_file -format=json`.
27. **Status of structured concurrency in JDK 25/26/27?** Preview (5th/6th/7th).
28. **Status of scoped values in JDK 25?** Final (JEP 506).
29. **Are scoped values inherited by `Thread.ofVirtual().start()`?** No: only by `StructuredTaskScope` forks.
30. **What does a `ThreadLocalMap` entry reference weakly?** The `ThreadLocal` key, not the value.
</details>

---

## B. Senior & architect scenarios

<details><summary><b>B1. 🔥 You're migrating a Spring MVC service (JDK 25) from a 200-thread Tomcat pool to virtual threads. List what you check and change.</b></summary>

(1) Downstream capacity: add bulkheads or semaphores sized to the DB pool and partner limits, since the thread pool used to be the implicit limit. (2) `ThreadLocal` usage: per-thread caches and context, so move request context to `ScopedValue` where possible and remove expensive per-thread caches. (3) CPU-heavy endpoints: offload them to a bounded platform pool. (4) Pinning: run load tests with JFR (`jdk.VirtualThreadPinned`) for native and `<clinit>` cases. (5) Observability: JSON thread dumps, plus metrics on in-flight requests and semaphore waits instead of pool utilization. (6) Timeouts everywhere (VTs make waiting cheap, but latency still matters). (7) Library versions (JDBC drivers, HTTP clients) and connection-pool sizing (Pillar 5).
</details>

<details><summary><b>B2. 🔥 A p99 latency spike appears every few minutes. Thread dumps during spikes show 150 threads BLOCKED on one monitor in a logging appender. Explain and fix.</b></summary>

A lock convoy: a synchronous appender holds a monitor while doing I/O (disk or network). Under load threads queue behind it, and every holder's I/O latency adds to everyone's. Fixes: an async appender with a bounded queue and a drop policy (log4j2 `AsyncLogger` with the LMAX Disruptor), reduce log volume on hot paths, and make sure appenders don't do network I/O synchronously. Verify with JFR `jdk.JavaMonitorEnter`.
</details>

<details><summary><b>B3. ⚡ Design a per-tenant rate limiter usable from virtual threads with ~10k tenants.</b></summary>

A `ConcurrentHashMap<TenantId, Bucket>` with a token bucket per tenant (lazy-refilled from `System.nanoTime()` deltas, updated with CAS on a packed `AtomicLong` or a small lock per bucket), with eviction of idle tenants (Caffeine with `expireAfterAccess`). Avoid one global lock, `LongAdder` for limits (it isn't exact), and blocking waits in the limiter (return "retry-after" instead). For cluster-wide limits, use Redis with Lua or a gateway (Pillar 6).
</details>

<details><summary><b>B4. ⚡ When would you still choose WebFlux/reactive over virtual threads in 2026?</b></summary>

When the workload is inherently streaming with backpressure (server push to many long-lived connections, event-stream processing, fan-in of reactive sources), when you need operator-level flow control (`limitRate`, windowing) end to end, or when the stack is already reactive and healthy (R2DBC, reactive Kafka). For classic request/response fan-out, VTs give the same scalability with simpler code.
</details>

<details><summary><b>B5. 🧊 How do you test that a lock-free class is correct?</b></summary>

jcstress tests that enumerate allowed and forbidden outcomes for small concurrent scenarios (run on x86 and ARM, with JIT variations); linearizability checking with model-based stress tests (Lincheck); invariants checked under heavy randomized stress (checksums like the Treiber stack test); and code review for ABA and memory ordering (publication via release/acquire). Unit tests alone can't prove it.
</details>

---

## C. Certification-style code questions (verified on JDK 25)

### C1 — Thread states

<!-- run: -->
```java
public class T01 {
    public static void main(String[] args) throws Exception {
        Thread t = new Thread(() -> { synchronized (T01.class) { } });
        System.out.print(t.getState() + " ");
        synchronized (T01.class) {
            t.start();
            Thread.sleep(100);
            System.out.print(t.getState() + " ");
        }
        t.join();
        System.out.println(t.getState());
    }
}
```

<details><summary>Answer</summary>

`NEW BLOCKED TERMINATED`. Before `start()` the thread is NEW. While `main` holds `T01.class`, `t` waits to enter the monitor (BLOCKED). After `join()` it has finished.
</details>

### C2 — `run()` vs `start()`, and starting twice

<!-- run: -->
```java
public class T02 {
    public static void main(String[] args) throws Exception {
        Thread t = new Thread(() -> System.out.print(Thread.currentThread().getName() + " "), "worker");
        t.run();
        t.start();
        t.join();
        try { t.start(); } catch (IllegalThreadStateException e) { System.out.println("ITSE"); }
    }
}
```

<details><summary>Answer</summary>

`main worker ITSE`. `run()` is a plain method call on the current thread. `start()` creates the new thread. A thread can be started only once.
</details>

### C3 — `invokeAll` and executor lifecycle

<!-- run: -->
```java
import java.util.List;
import java.util.concurrent.*;

public class T03 {
    public static void main(String[] args) throws Exception {
        ExecutorService ex = Executors.newFixedThreadPool(2);
        try (ex) {
            List<Callable<Integer>> tasks = List.of(() -> 1, () -> 2, () -> 3);
            int sum = 0;
            for (Future<Integer> f : ex.invokeAll(tasks)) sum += f.get();
            System.out.print(sum + " " + ex.isShutdown() + " ");
        }
        System.out.println(ex.isShutdown() + " " + ex.isTerminated());
    }
}
```

<details><summary>Answer</summary>

`6 false true true`. `invokeAll` waits for all tasks. Inside the try block the executor is still running. `close()` (JDK 19+) shuts it down and waits, so afterwards it is shut down and terminated.
</details>

### C4 — Exceptions through `Future`

<!-- run: -->
```java
import java.util.concurrent.*;

public class T04 {
    public static void main(String[] args) throws Exception {
        try (var ex = Executors.newSingleThreadExecutor()) {
            Future<Integer> f = ex.submit(() -> 10 / 0);
            Future<?> r = ex.submit(() -> System.out.print("runnable "));
            System.out.print(r.get() + " ");
            try { f.get(); } catch (ExecutionException e) { System.out.println(e.getCause().getClass().getSimpleName()); }
        }
    }
}
```

<details><summary>Answer</summary>

`runnable null ArithmeticException`. A `Runnable` submitted with `submit` yields a `Future<?>` whose `get()` returns `null`. The `Callable`'s exception is wrapped in `ExecutionException`.
</details>

### C5 — Atomic operations

<!-- run: -->
```java
import java.util.concurrent.atomic.AtomicInteger;

public class T05 {
    public static void main(String[] args) {
        AtomicInteger a = new AtomicInteger(5);
        System.out.println(a.getAndIncrement() + " " + a.incrementAndGet() + " " + a.compareAndSet(7, 10) + " "
            + a.updateAndGet(x -> x * 2) + " " + a.accumulateAndGet(3, Math::max));
    }
}
```

<details><summary>Answer</summary>

`5 7 true 20 20`. 5 (then 6) → 7 → CAS 7→10 succeeds → 20 → max(20, 3) = 20.
</details>

### C6 — `ConcurrentHashMap` compute family

<!-- run: -->
```java
import java.util.TreeMap;
import java.util.concurrent.ConcurrentHashMap;

public class T06 {
    public static void main(String[] args) {
        var m = new ConcurrentHashMap<String, Integer>();
        for (String w : "a b a c a b".split(" ")) m.merge(w, 1, Integer::sum);
        m.computeIfPresent("c", (k, v) -> null);               // returning null REMOVES the mapping
        m.computeIfAbsent("d", k -> 4);
        System.out.print(new TreeMap<>(m) + " ");
        try { m.put("e", null); } catch (NullPointerException e) { System.out.println("NPE"); }
    }
}
```

<details><summary>Answer</summary>

`{a=3, b=2, d=4} NPE`. `merge` counts words. A remapping function returning `null` removes the key. `ConcurrentHashMap` rejects null values.
</details>

### C7 — `CopyOnWriteArrayList` iteration

<!-- run: -->
```java
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

public class T07 {
    public static void main(String[] args) {
        var list = new CopyOnWriteArrayList<>(List.of(1, 2, 3));
        for (int x : list) if (x == 2) list.add(99);
        System.out.println(list);
    }
}
```

<details><summary>Answer</summary>

`[1, 2, 3, 99]`. The iterator walks a snapshot, so there is no `ConcurrentModificationException`, and the loop doesn't see 99 (no infinite loop).
</details>

### C8 — `CountDownLatch` and `Semaphore` arithmetic

<!-- run: -->
```java
import java.util.concurrent.*;

public class T08 {
    public static void main(String[] args) throws Exception {
        CountDownLatch l = new CountDownLatch(2);
        l.countDown(); l.countDown(); l.countDown();
        System.out.print(l.getCount() + " " + l.await(10, TimeUnit.MILLISECONDS) + " | ");
        Semaphore s = new Semaphore(2);
        System.out.print(s.tryAcquire() + " " + s.tryAcquire(2) + " " + s.availablePermits() + " ");
        s.release(3);
        System.out.println(s.availablePermits());
    }
}
```

<details><summary>Answer</summary>

`0 true | true false 1 4`. A latch count never goes below zero, and a latch at zero returns from `await` immediately. A semaphore's `tryAcquire(2)` fails with only 1 permit left. Releases aren't capped by the initial count (1 + 3 = 4).
</details>

### C9 — `ReentrantLock` from two threads

<!-- run: -->
```java
import java.util.concurrent.locks.ReentrantLock;

public class T09 {
    public static void main(String[] args) throws Exception {
        ReentrantLock lock = new ReentrantLock();
        lock.lock(); lock.lock();
        System.out.print(lock.getHoldCount() + " " + lock.isHeldByCurrentThread() + " ");
        lock.unlock();
        Thread t = new Thread(() -> System.out.print(lock.tryLock() + " "));
        t.start(); t.join();
        lock.unlock();
        System.out.println(lock.isLocked());
    }
}
```

<details><summary>Answer</summary>

`2 true false false`. Reentrant hold count is 2. After one `unlock`, `main` still holds it (count 1), so the other thread's `tryLock` fails. After the second `unlock`, the lock is free.
</details>

### C10 — Interrupt status semantics

<!-- run: -->
```java
public class T10 {
    public static void main(String[] args) {
        Thread.currentThread().interrupt();
        System.out.print(Thread.interrupted() + " " + Thread.interrupted() + " ");
        Thread.currentThread().interrupt();
        try { Thread.sleep(10); } catch (InterruptedException e) { System.out.println("IE " + Thread.currentThread().isInterrupted()); }
    }
}
```

<details><summary>Answer</summary>

`true false IE false`. The static `Thread.interrupted()` returns **and clears** the flag. `sleep` on an interrupted thread throws immediately and clears the flag, so code that catches it should usually call `interrupt()` again.
</details>

### C11 — Parallel stream ordering

<!-- run: -->
```java
import java.util.List;

public class T11 {
    public static void main(String[] args) {
        List<Integer> l = List.of(1, 2, 3, 4, 5);
        l.parallelStream().map(x -> x * 2).forEachOrdered(System.out::print);
        System.out.println(" " + l.parallelStream().reduce(0, Integer::sum) + " " + l.parallelStream().findFirst().get()
            + " " + l.parallelStream().map(x -> x * 10).toList());
    }
}
```

<details><summary>Answer</summary>

`246810 15 1 [10, 20, 30, 40, 50]`. `forEachOrdered`, `findFirst` and `toList` respect encounter order even in parallel. A parallel `reduce` with an associative function and a true identity equals the sequential result. (`forEach` or `findAny` would have no defined order.)
</details>

### C12 — Virtual thread properties

<!-- run: -->
```java
public class T12 {
    public static void main(String[] args) {
        Thread v = Thread.ofVirtual().unstarted(() -> { });
        System.out.print(v.isVirtual() + " " + v.isDaemon() + " " + v.getState() + " ");
        try { v.setDaemon(false); } catch (IllegalArgumentException e) { System.out.print("IAE "); }
        v.setPriority(Thread.MAX_PRIORITY);
        System.out.println(v.getPriority());
    }
}
```

<details><summary>Answer</summary>

`true true NEW IAE 5`. Virtual threads are always daemon (`setDaemon(false)` throws `IllegalArgumentException`), and priority changes are ignored (always `NORM_PRIORITY` = 5).
</details>

### C13 — Scoped values are not inherited by plain threads

<!-- run: -->
```java
public class T13 {
    static final ScopedValue<String> SV = ScopedValue.newInstance();
    public static void main(String[] args) {
        ScopedValue.where(SV, "x").run(() -> {
            Thread t = Thread.ofVirtual().start(() -> System.out.print(SV.isBound() + " "));
            try { t.join(); } catch (InterruptedException e) { }
            System.out.println(SV.get());
        });
    }
}
```

<details><summary>Answer</summary>

`false x`. Bindings are visible only in the dynamic scope of the binding thread and in `StructuredTaskScope` forks, not in arbitrary threads started inside it.
</details>

### C14 — `CompletableFuture` pipeline

<!-- run: -->
```java
import java.util.concurrent.CompletableFuture;

public class T14 {
    public static void main(String[] args) {
        CompletableFuture<Integer> cf = CompletableFuture.supplyAsync(() -> 2)
            .thenApply(x -> x * 3)
            .thenCombine(CompletableFuture.completedFuture(4), Integer::sum)
            .thenCompose(x -> CompletableFuture.supplyAsync(() -> x / 0))
            .exceptionally(e -> -1)
            .thenApply(x -> x + 100);
        System.out.println(cf.join());
    }
}
```

<details><summary>Answer</summary>

`99`. 2×3 = 6, +4 = 10, then `10/0` throws, `exceptionally` recovers with −1, and −1 + 100 = 99.
</details>

### C15 — Executor after shutdown

<!-- run: -->
```java
import java.util.concurrent.*;

public class T15 {
    public static void main(String[] args) throws Exception {
        ExecutorService ex = Executors.newSingleThreadExecutor();
        ex.submit(() -> { try { Thread.sleep(100); } catch (InterruptedException e) { System.out.print("interrupted "); } });
        Thread.sleep(20);
        var neverRun = ex.shutdownNow();
        try { ex.submit(() -> { }); } catch (RejectedExecutionException e) { System.out.print("rejected "); }
        System.out.println(ex.awaitTermination(1, TimeUnit.SECONDS) + " " + neverRun.size());
    }
}
```

<details><summary>Answer</summary>

`interrupted rejected true 0`. `shutdownNow` interrupts the running task (its sleep throws) and returns the queued-but-never-started tasks (none here). Submissions after shutdown are rejected.
</details>

### C16 — Which outputs are *possible*? (no run: reasoning question)

```java
class Counter { int n; synchronized void inc() { n++; } int get() { return n; } }
// Two threads each call inc() 1000 times; main joins both, then prints c.get().
```

A. Always 2000  B. Any value 1000–2000  C. Always 2000, but only because of `join()`  D. Can exceed 2000

<details><summary>Answer</summary>

**A**, with the reasoning from C. `inc()` is synchronized, so increments don't interleave. The value is **visible** to `main` because each thread's actions happen-before `join()` returns, even though `get()` isn't synchronized. Without `join()` (reading concurrently) `get()` could see stale values, because it is unsynchronized. Option B describes an unsynchronized `n++`.
</details>

### C17 — `ReadWriteLock` rules (no run: reasoning question)

Which statement is true for `ReentrantReadWriteLock`?
A. Multiple threads can hold the write lock simultaneously.
B. A thread holding the write lock can acquire the read lock.
C. A thread holding the read lock can acquire the write lock if no other readers exist.
D. The read lock supports `newCondition()`.

<details><summary>Answer</summary>

**B** (downgrading). A: write is exclusive. C: upgrading deadlocks even with no other readers, because the thread's own read hold blocks the write. D: the read lock's `newCondition()` throws `UnsupportedOperationException`.
</details>

---

## D. Study map

| 1Z0-831 objective | Files | Practise |
|---|---|---|
| Platform and virtual threads, executors, scoped values | [3.4](04-Executors-ForkJoin-CompletableFuture.md), [3.6](06-Virtual-Threads-Structured-Concurrency-Scoped-Values.md) | C1–C4, C12–C15 |
| Thread-safe code with locks and the concurrent API | [3.1](01-Java-Memory-Model.md), [3.2](02-Synchronization-Locks-AQS.md), [3.3](03-Lock-Free-CAS-Atomics.md) | C5, C9, C10, C16, C17 |
| Concurrent collections and parallel streams | [3.5](05-Concurrent-Collections-Synchronizers-ThreadLocal.md), [2.3 §3](../02-Core-Java/03-Lambdas-Streams-Collectors-Gatherers.md#3-parallel-streams-when-they-help-and-when-they-hurt-) | C6–C8, C11 |
