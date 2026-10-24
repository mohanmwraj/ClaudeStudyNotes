# 3.4 · Executors, Thread Pools, ForkJoinPool & `CompletableFuture`

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut · 🎓 exam ("executors", `Future`, `Callable`, `invokeAll`)
> **Sources:** `ThreadPoolExecutor`/`ScheduledThreadPoolExecutor`/`ForkJoinPool`/`CompletableFuture` source and Javadoc (JDK 25), *Java Concurrency in Practice* ch. 6–8, Doug Lea, "A Java Fork/Join Framework" (2000), Little's Law.
> Every program below was run on JDK 25. The printed facts (pool sizes, thread names, exception types) are deterministic. Timings are labelled.

---

## 1. `ThreadPoolExecutor` internals 🔥

### 1.1 State and the `execute()` algorithm

```
ctl (AtomicInteger) = [ runState : 3 bits | workerCount : 29 bits ]
runState: RUNNING → SHUTDOWN (no new tasks, drain queue) → STOP (shutdownNow: interrupt, drop queue) → TIDYING → TERMINATED

execute(task):
  1. if workerCount < corePoolSize      → start a NEW worker with this task (even if other workers are idle!)
  2. else if workQueue.offer(task)      → queued (re-check: pool may have shut down / have 0 workers)
  3. else if workerCount < maximumPool  → start a NEW worker (only when the queue REFUSED the task)
  4. else                               → RejectedExecutionHandler
```

**Step 3 is the trap:** the pool grows beyond `corePoolSize` **only when the queue is full**. With an unbounded `LinkedBlockingQueue`, the queue is never full, so `maximumPoolSize` is **never used** and the queue grows without limit, which ends in an OOM.

* **Worker** = a `Thread` plus a first task, extending AQS as a **non-reentrant lock** held while running a task. `shutdown()` interrupts only *idle* workers (those whose lock it can acquire).
* Idle workers beyond core die after `keepAliveTime`; core workers die too with `allowCoreThreadTimeOut(true)`. `prestartAllCoreThreads()` warms the pool up.
* Hooks: `beforeExecute`, `afterExecute(Runnable, Throwable)`, `terminated()`.

### 1.2 Runnable: queue choice decides the pool's behaviour

<!-- run: -->
```java
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

public class QueueChoice {
    static String run(String name, BlockingQueue<Runnable> queue) throws Exception {
        AtomicInteger rejected = new AtomicInteger();
        var pool = new ThreadPoolExecutor(2, 6, 30, TimeUnit.SECONDS, queue, (r, ex) -> rejected.incrementAndGet());
        for (int i = 0; i < 20; i++) pool.execute(() -> sleep(200));
        String result = String.format("%-24s poolSize=%d queued=%d rejected=%d", name, pool.getPoolSize(), pool.getQueue().size(), rejected.get());
        pool.shutdownNow();
        pool.awaitTermination(5, TimeUnit.SECONDS);
        return result;
    }
    static void sleep(long ms) { try { Thread.sleep(ms); } catch (InterruptedException e) { Thread.currentThread().interrupt(); } }

    public static void main(String[] args) throws Exception {
        System.out.println("core=2 max=6, 20 tasks submitted instantly:");
        System.out.println(run("LinkedBlockingQueue()", new LinkedBlockingQueue<>()));
        System.out.println(run("ArrayBlockingQueue(5)", new ArrayBlockingQueue<>(5)));
        System.out.println(run("SynchronousQueue", new SynchronousQueue<>()));
    }
}
```

Output (verified):

```
core=2 max=6, 20 tasks submitted instantly:
LinkedBlockingQueue()    poolSize=2 queued=18 rejected=0
ArrayBlockingQueue(5)    poolSize=6 queued=5 rejected=9
SynchronousQueue         poolSize=6 queued=0 rejected=14
```

| Queue | Behaviour | `Executors` factory that uses it | Risk |
|---|---|---|---|
| Unbounded `LinkedBlockingQueue` | Never grows past core; infinite queueing | `newFixedThreadPool`, `newSingleThreadExecutor` | **Unbounded memory and latency**: OOM under overload |
| Bounded `ArrayBlockingQueue(n)` / `LinkedBlockingQueue(n)` | Grows to max when the queue is full, then rejects | — (construct `ThreadPoolExecutor` yourself) | Must choose a rejection policy |
| `SynchronousQueue` (direct hand-off) | A new thread whenever none is idle | `newCachedThreadPool` (max = `Integer.MAX_VALUE`!) | **Unbounded threads** → `OutOfMemoryError: unable to create native thread` |
| `PriorityBlockingQueue` | Priority order, unbounded | — | Starvation of low-priority tasks; unbounded |
| `DelayedWorkQueue` | Ordered by delay | `ScheduledThreadPoolExecutor` (core-sized, effectively unbounded) | — |

> **Rule:** in production code, construct `ThreadPoolExecutor` explicitly, with a **bounded queue**, a **named `ThreadFactory`**, an **explicit rejection policy**, and **metrics**. The `Executors.newFixedThreadPool`/`newCachedThreadPool` shortcuts hide two different unbounded resources.

### 1.3 Rejection policies

<!-- run: -->
```java
import java.util.*;
import java.util.concurrent.*;

public class RejectionPolicies {
    static void sleep(long ms) { try { Thread.sleep(ms); } catch (InterruptedException e) { Thread.currentThread().interrupt(); } }

    static void demo(String name, RejectedExecutionHandler handler) throws Exception {
        List<String> ranOn = Collections.synchronizedList(new ArrayList<>());
        var pool = new ThreadPoolExecutor(1, 1, 0, TimeUnit.SECONDS, new ArrayBlockingQueue<>(1),
            Thread.ofPlatform().name("worker-", 0).factory(), handler);
        StringBuilder sb = new StringBuilder(String.format("%-20s", name));
        for (int i = 1; i <= 3; i++) {                      // 1 runs, 1 queues, the 3rd overflows
            int id = i;
            try { pool.execute(() -> { sleep(150); ranOn.add("t" + id + "@" + Thread.currentThread().getName()); }); }
            catch (RejectedExecutionException e) { sb.append(" t").append(id).append(":REJECTED"); }
        }
        pool.shutdown(); pool.awaitTermination(5, TimeUnit.SECONDS);
        ranOn.sort(Comparator.naturalOrder());
        System.out.println(sb + " ran=" + ranOn);
    }

    public static void main(String[] args) throws Exception {
        demo("AbortPolicy", new ThreadPoolExecutor.AbortPolicy());
        demo("CallerRunsPolicy", new ThreadPoolExecutor.CallerRunsPolicy());
        demo("DiscardPolicy", new ThreadPoolExecutor.DiscardPolicy());
        demo("DiscardOldestPolicy", new ThreadPoolExecutor.DiscardOldestPolicy());
    }
}
```

Output (verified; 1 worker + queue of 1, 3 tasks submitted at once):

```
AbortPolicy          t3:REJECTED ran=[t1@worker-0, t2@worker-0]
CallerRunsPolicy     ran=[t1@worker-0, t2@worker-0, t3@main]
DiscardPolicy        ran=[t1@worker-0, t2@worker-0]
DiscardOldestPolicy  ran=[t1@worker-0, t3@worker-0]
```

* **Abort** (default): throws `RejectedExecutionException`, so callers must handle it (for example by returning HTTP 503).
* **CallerRuns**: the submitting thread runs the task (`t3@main`), which naturally **throttles the producer**, a crude form of backpressure. Never use it when the caller is an event loop or a request thread with a tight SLO.
* **Discard / DiscardOldest**: **silent data loss**. Acceptable only for droppable work (metrics samples), and always count the drops.

---

## 2. Sizing thread pools 🔥

### 2.1 The formulas

```
CPU-bound:  N_threads ≈ N_cpu (+1 to cover occasional page faults/pauses)

I/O-bound (Goetz, JCiP §8.2):  N_threads = N_cpu × U_target × (1 + W/C)
      W/C = wait time / compute time per task,  U_target = desired CPU utilization (0..1)
      e.g. 8 cores, U=0.8, each request waits 90 ms on the DB and computes 10 ms → 8 × 0.8 × (1 + 9) = 64 threads

Little's Law (queueing theory):  L = λ × W
      concurrency needed = arrival rate × time in system
      e.g. 2,000 req/s × 0.050 s = 100 concurrent requests in flight → you need ≥ 100 "slots" (threads or VTs)
```

### 2.2 What the formulas don't tell you

* **Downstream limits dominate.** A pool of 200 threads calling a DB with 20 connections means 180 threads waiting on the connection pool. Size thread pools to the **narrowest downstream resource** (Pillar 5: Hikari sizing) and use **bulkheads**: one pool per dependency, so one slow dependency can't exhaust everything (Pillar 6).
* **Containers:** `availableProcessors()` honours CPU *limits* (cgroups). Fractional limits (e.g. 1.5 CPUs) round **up**, so set `-XX:ActiveProcessorCount` deliberately.
* **Virtual threads change the question** for I/O-bound work: instead of sizing a pool, you **limit concurrency** per resource with semaphores or bulkheads, and let threads be "free" ([3.6](06-Virtual-Threads-Structured-Concurrency-Scoped-Values.md)).
* Measure: queue wait time (enqueue → start), execution time, active count, queue depth, rejection rate.

---

## 3. Exceptions and lifecycle traps 🔥

### 3.1 Runnable: where do exceptions go?

<!-- run: -->
```java
import java.util.concurrent.*;

public class LostExceptions {
    public static void main(String[] args) throws Exception {
        var pool = new ThreadPoolExecutor(1, 1, 0, TimeUnit.SECONDS, new LinkedBlockingQueue<>(),
                Thread.ofPlatform().name("pool-worker-", 0).uncaughtExceptionHandler(
                    (t, e) -> System.out.println("  [UEH] " + t.getName() + " died: " + e.getMessage())).factory()) {
            @Override protected void afterExecute(Runnable r, Throwable t) {
                if (t == null && r instanceof Future<?> f && f.isDone()) {          // submit() wraps tasks in FutureTask
                    try { f.get(); } catch (ExecutionException e) { t = e.getCause(); } catch (InterruptedException | CancellationException ignored) { }
                }
                if (t != null) System.out.println("  [afterExecute] saw: " + t.getMessage());
            }
        };

        System.out.println("execute():");
        pool.execute(() -> { throw new IllegalStateException("boom-1"); });   // propagates → UEH, worker thread dies
        Thread.sleep(100);

        System.out.println("submit() without get():");
        Future<?> f = pool.submit(() -> { throw new IllegalStateException("boom-2"); });  // captured in the Future
        Thread.sleep(100);

        System.out.println("submit() then get():");
        try { f.get(); } catch (ExecutionException e) { System.out.println("  get() → ExecutionException caused by " + e.getCause().getMessage()); }

        System.out.println("worker threads created so far: " + pool.getCompletedTaskCount() + " tasks completed, largestPoolSize=" + pool.getLargestPoolSize());
        pool.close();                                                           // JDK 19+: ExecutorService is AutoCloseable
    }
}
```

Output (verified):

```
execute():
  [afterExecute] saw: boom-1
  [UEH] pool-worker-0 died: boom-1
submit() without get():
  [afterExecute] saw: boom-2
submit() then get():
  get() → ExecutionException caused by boom-2
worker threads created so far: 2 tasks completed, largestPoolSize=1
```

* `execute(Runnable)`: the exception propagates out of the task, `afterExecute` sees it, then the **worker thread dies** (the UEH prints it) and the pool replaces the worker.
* `submit(...)`: the exception is **captured in the `FutureTask`**. If nobody calls `get()`, **it vanishes**: no log, no metric. This is the most common "silently failing background job" bug. Always consume futures, or log in `afterExecute` as above.

### 3.2 Scheduled tasks die silently

<!-- run: -->
```java
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

public class ScheduledSilentDeath {
    public static void main(String[] args) throws Exception {
        var ses = Executors.newSingleThreadScheduledExecutor();
        AtomicInteger runs = new AtomicInteger();
        ScheduledFuture<?> f = ses.scheduleAtFixedRate(() -> {
            int n = runs.incrementAndGet();
            if (n == 3) throw new IllegalStateException("transient failure on run 3");
        }, 0, 50, TimeUnit.MILLISECONDS);
        Thread.sleep(500);
        System.out.println("runs=" + runs.get() + " isDone=" + f.isDone() + " (no more executions, nothing logged)");
        try { f.get(); } catch (ExecutionException e) { System.out.println("only get() reveals: " + e.getCause().getMessage()); }
        ses.shutdown();
    }
}
```

Output (verified):

```
runs=3 isDone=true (no more executions, nothing logged)
only get() reveals: transient failure on run 3
```

**Any exception from a periodic task cancels all future runs, silently.** Wrap periodic bodies in `try { … } catch (Throwable t) { log; }`, or use a scheduler library that does (Spring `@Scheduled` logs and continues).

### 3.3 Shutdown, interruption and cancellation 🎓

| API | Effect |
|---|---|
| `shutdown()` | No new tasks; queued and running tasks complete |
| `shutdownNow()` | Interrupts running tasks; returns queued tasks **not** run |
| `awaitTermination(t, unit)` | Blocks until terminated or timeout |
| `close()` (JDK 19+) | `shutdown()` + wait (retrying, interrupt-aware), so `try (var ex = …) { }` is idiomatic |
| `Future.cancel(true)` | Interrupts the thread running the task (if started). The task must **respond** to interruption |
| `invokeAll(tasks)` | Runs all, returns futures when **all** are done |
| `invokeAny(tasks)` | Returns the first **successful** result and cancels the rest |

**Interruption etiquette:** blocking methods throw `InterruptedException` and **clear** the interrupt flag. Either propagate the exception, or restore the flag with `Thread.currentThread().interrupt()` so the code above you can see it. Swallowing it makes tasks un-cancellable and shutdown hang.

### 3.4 Thread-starvation deadlock 🔥

<!-- run: -->
```java
import java.util.concurrent.*;

public class StarvationDeadlock {
    public static void main(String[] args) throws Exception {
        ExecutorService pool = Executors.newFixedThreadPool(2);
        Callable<String> parent = () -> {
            Future<String> child = pool.submit(() -> "child result");   // child queued to the SAME pool…
            return "parent got " + child.get();                         // …and the parent blocks waiting for it
        };
        Future<String> p1 = pool.submit(parent), p2 = pool.submit(parent);   // both workers now block in get()
        try { System.out.println(p1.get(1, TimeUnit.SECONDS)); }
        catch (TimeoutException e) { System.out.println("deadlocked: both workers wait for children stuck in the queue (queue=" + ((ThreadPoolExecutor) pool).getQueue().size() + ")"); }
        pool.shutdownNow();
    }
}
```

Output (verified):

```
deadlocked: both workers wait for children stuck in the queue (queue=2)
```

No lock is involved, so `findDeadlockedThreads` finds nothing. Fixes: never block on tasks submitted to the same bounded pool; use separate pools per stage; use `ForkJoinPool` (whose `join` **helps** run queued tasks); or compose asynchronously (`thenCompose`). Virtual threads remove the pool-size cap entirely.

---

## 4. `ForkJoinPool` and work stealing ⚡

### 4.1 Mechanics

```
ForkJoinPool (parallelism P)
  worker 1: [ deque ] ← push/pop at the TOP (LIFO: cache-hot, depth-first)
  worker 2: [ deque ]
  …            ▲
               └── idle workers STEAL from the BOTTOM of a random victim's deque (FIFO: oldest = largest subtasks)
  external submissions → shared submission queues (or the caller helps, for commonPool)

fork()  = push the subtask to my own deque
join()  = if the subtask hasn't started, run it myself; otherwise "help" (run other tasks) instead of blocking
```

* **Divide and conquer:** split until the work is below a threshold, compute directly, and combine. Stealing from the bottom takes the *largest* remaining chunk, which minimizes steal frequency.
* **`ForkJoinPool.commonPool()`** (parallelism = cores − 1) backs parallel streams and `CompletableFuture` async methods without an executor. **Don't block in it.** If you must, wrap blocking in `ForkJoinPool.managedBlock(ManagedBlocker)`, which lets the pool add a compensating thread.
* **Async mode** (`asyncMode=true`): FIFO local queues, for event-style tasks that are never joined. The **virtual-thread scheduler** is a dedicated `ForkJoinPool` in async mode ([3.6](06-Virtual-Threads-Structured-Concurrency-Scoped-Values.md)).

### 4.2 Runnable: `RecursiveTask` and the threshold trade-off

<!-- run: timeout=120 -->
```java
import java.util.concurrent.ForkJoinPool;
import java.util.concurrent.RecursiveTask;

public class ForkJoinSum extends RecursiveTask<Long> {
    private final long[] data; private final int lo, hi, threshold;
    ForkJoinSum(long[] data, int lo, int hi, int threshold) { this.data = data; this.lo = lo; this.hi = hi; this.threshold = threshold; }

    @Override protected Long compute() {
        if (hi - lo <= threshold) {
            long s = 0;
            for (int i = lo; i < hi; i++) s += data[i] * data[i] % 7;
            return s;
        }
        int mid = (lo + hi) >>> 1;
        ForkJoinSum left = new ForkJoinSum(data, lo, mid, threshold);
        left.fork();                                                   // push left half onto my deque
        long right = new ForkJoinSum(data, mid, hi, threshold).compute(); // compute right half myself
        return right + left.join();                                    // join left (may have been stolen)
    }

    public static void main(String[] args) {
        long[] data = new long[20_000_000];
        for (int i = 0; i < data.length; i++) data[i] = i;
        ForkJoinPool pool = new ForkJoinPool(4);
        long expected = 0; for (long v : data) expected += v * v % 7;
        for (int threshold : new int[] {1_000, 100_000, 5_000_000}) {
            long best = Long.MAX_VALUE, result = 0;
            for (int r = 0; r < 5; r++) {
                long t = System.nanoTime();
                result = pool.invoke(new ForkJoinSum(data, 0, data.length, threshold));
                best = Math.min(best, System.nanoTime() - t);
            }
            System.out.printf("threshold %,10d: %6.1f ms correct=%b%n", threshold, best / 1e6, result == expected);
        }
        System.out.println("steals so far: " + (pool.getStealCount() > 0 ? "> 0 (work stealing happened)" : "0"));
        pool.close();
    }
}
```

One measured run (4-worker pool, otherwise idle laptop):

```
threshold      1,000:    7.9 ms correct=true
threshold    100,000:    5.4 ms correct=true
threshold  5,000,000:    5.5 ms correct=true
steals so far: > 0 (work stealing happened)
```

A too-small threshold (1,000 elements → 20,000 leaf tasks) pays visibly for task creation and scheduling (+46%). The coarse threshold (4 leaves for 4 workers) was as fast as the middle one **here**, because equal-sized leaves on idle cores need no balancing. It loses when leaves are uneven (data-dependent cost) or cores are busy with other work, since a slow leaf can't be split or stolen. A threshold yielding **≈ 4–16× more leaves than workers** is a robust default.

---

## 5. `CompletableFuture` 🔥🎓

### 5.1 Mental model

* A `CompletableFuture<T>` is a **write-once box** plus a **stack of dependent actions** (a Treiber stack of `Completion` objects). Completing it (`complete`, `completeExceptionally`, or the async task finishing) pops and runs the dependents.
* **Which thread runs a non-async stage (`thenApply`, `thenAccept`, …)?** The thread that **completes** the previous stage, or, if it's **already complete** when you attach the stage, **the calling thread right away**.
* **`…Async` stages** run on the given executor, or by default on `ForkJoinPool.commonPool()`. If the common pool's parallelism is < 2 (1-CPU containers), a new thread is created per task.

<!-- run: -->
```java
import java.util.concurrent.*;

public class WhoRunsMyCallback {
    static String t() { String n = Thread.currentThread().getName(); return n.startsWith("ForkJoinPool.commonPool") ? "commonPool" : n; }

    public static void main(String[] args) throws Exception {
        ExecutorService io = Executors.newFixedThreadPool(1, Thread.ofPlatform().name("io-", 0).factory());

        CompletableFuture<String> done = CompletableFuture.completedFuture("x");
        done.thenApply(v -> { System.out.println("1. thenApply on an already-completed future runs on: " + t()); return v; });

        CompletableFuture<String> later = new CompletableFuture<>();
        later.thenApply(v -> { System.out.println("2. thenApply attached before completion runs on: " + t()); return v; });
        Thread.ofPlatform().name("completer").start(() -> later.complete("y")).join();

        CompletableFuture.supplyAsync(() -> { sleep(50); return t(); }, io)    // still running when thenApply is attached
            .thenApply(v -> { System.out.println("3. supplyAsync ran on " + v + ", thenApply on: " + t()); return v; })
            .thenApplyAsync(v -> { System.out.println("4. thenApplyAsync (no executor) runs on: " + t()); return v; })
            .thenApplyAsync(v -> { System.out.println("5. thenApplyAsync(io) runs on: " + t()); return v; }, io)
            .join();
        io.shutdown();
    }
    static void sleep(long ms) { try { Thread.sleep(ms); } catch (InterruptedException e) { Thread.currentThread().interrupt(); } }
}
```

Output (verified):

```
1. thenApply on an already-completed future runs on: main
2. thenApply attached before completion runs on: completer
3. supplyAsync ran on io-0, thenApply on: io-0
4. thenApplyAsync (no executor) runs on: commonPool
5. thenApplyAsync(io) runs on: io-0
```

Without the 50 ms sleep, step 3 sometimes printed `thenApply on: main`: the async task had already finished when `thenApply` was attached, so the caller ran it. Same code, different thread, depending on timing.

**Implication:** a "non-blocking" chain can execute your callback on an I/O pool thread, an event-loop thread (Netty/reactive clients completing futures), or the caller. Heavy work in a non-async stage can stall whichever thread completed the future. Be explicit: pass executors to `…Async` methods.

### 5.2 Composition and error handling

<!-- run: -->
```java
import java.util.List;
import java.util.concurrent.*;

public class CfComposition {
    static CompletableFuture<Integer> price(String sku) {
        return CompletableFuture.supplyAsync(() -> {
            if (sku.equals("bad")) throw new IllegalArgumentException("unknown sku " + sku);
            return sku.length() * 100;
        });
    }

    public static void main(String[] args) {
        // thenCompose flattens CF<CF<T>>; thenCombine joins two independent futures
        CompletableFuture<Integer> total = price("apple").thenCombine(price("kiwi"), Integer::sum);
        System.out.println("combine: " + total.join());

        CompletableFuture<CompletableFuture<Integer>> nested = CompletableFuture.completedFuture("pear").thenApply(CfComposition::price);
        CompletableFuture<Integer> flat = CompletableFuture.completedFuture("pear").thenCompose(CfComposition::price);
        System.out.println("thenApply → nested " + nested.join().join() + " | thenCompose → " + flat.join());

        // exceptionally / handle / whenComplete
        CompletableFuture<Integer> failing = price("bad");
        System.out.println("exceptionally: " + failing.exceptionally(ex -> { System.out.println("  ex type in callback = " + ex.getClass().getSimpleName()); return -1; }).join());
        System.out.println("handle: " + failing.handle((v, ex) -> ex == null ? v : 0).join());
        try { failing.join(); } catch (CompletionException e) { System.out.println("join() throws CompletionException(cause=" + e.getCause().getClass().getSimpleName() + ")"); }
        try { failing.get(); } catch (ExecutionException | InterruptedException e) { System.out.println("get() throws " + e.getClass().getSimpleName()); }

        // allOf: wait for all, then collect; failures propagate
        List<CompletableFuture<Integer>> all = List.of(price("a"), price("bb"), price("ccc"));
        int sum = CompletableFuture.allOf(all.toArray(CompletableFuture[]::new))
            .thenApply(v -> all.stream().mapToInt(CompletableFuture::join).sum()).join();
        System.out.println("allOf sum=" + sum);

        // timeouts (JDK 9+)
        CompletableFuture<String> slow = CompletableFuture.supplyAsync(() -> { sleep(500); return "slow"; });
        System.out.println("completeOnTimeout → " + slow.completeOnTimeout("fallback", 50, TimeUnit.MILLISECONDS).join());
        CompletableFuture<String> slow2 = CompletableFuture.supplyAsync(() -> { sleep(500); return "slow"; });
        try { slow2.orTimeout(50, TimeUnit.MILLISECONDS).join(); }
        catch (CompletionException e) { System.out.println("orTimeout → " + e.getCause().getClass().getSimpleName()); }

        // cancel() does NOT interrupt the running task
        CompletableFuture<String> running = CompletableFuture.supplyAsync(() -> { sleep(300); System.out.println("  task finished anyway (not interrupted)"); return "done"; });
        sleep(50);
        System.out.println("cancel(true) → " + running.cancel(true) + ", isCancelled=" + running.isCancelled());
        sleep(400);
    }
    static void sleep(long ms) { try { Thread.sleep(ms); } catch (InterruptedException e) { Thread.currentThread().interrupt(); } }
}
```

Output (verified):

```
combine: 900
thenApply → nested 400 | thenCompose → 400
  ex type in callback = CompletionException
exceptionally: -1
handle: 0
join() throws CompletionException(cause=IllegalArgumentException)
get() throws ExecutionException
allOf sum=600
completeOnTimeout → fallback
orTimeout → TimeoutException
cancel(true) → true, isCancelled=true
  task finished anyway (not interrupted)
```

**The rules the output demonstrates:**

* Exceptions inside stages arrive in callbacks **wrapped in `CompletionException`**. Unwrap with `getCause()`. `join()` throws `CompletionException` (unchecked); `get()` throws the checked `ExecutionException`.
* `exceptionally` recovers, `handle` sees both outcomes and transforms them, and `whenComplete` observes without changing the result (but propagates its own exceptions). `exceptionallyCompose` (JDK 12) recovers asynchronously.
* **`cancel(true)` does not interrupt** a `supplyAsync` task: it only completes the future with `CancellationException`, and the work keeps running. For real cancellation, use `Future`s from an `ExecutorService`, structured concurrency, or check a flag or the interrupt status yourself.
* `allOf` returns `CompletableFuture<Void>`; collect results from the individual futures afterwards. `anyOf` completes with the first result **or the first exception**.
* **Always attach a terminal handler** (`whenComplete`/`exceptionally` + logging) to fire-and-forget futures, otherwise failures disappear (as with `submit`).

### 5.3 `CompletableFuture` vs virtual threads (2026 perspective)

| Concern | `CompletableFuture` chains | Virtual threads (+ structured concurrency) |
|---|---|---|
| Code shape | Callback pipeline | Sequential, blocking-style |
| Stack traces | Fragmented across threads | Normal |
| `ThreadLocal`/MDC/security context | Lost between stages unless propagated | Preserved (or use `ScopedValue`) |
| Cancellation | Doesn't interrupt (see above) | Interrupt-based, automatic in `StructuredTaskScope` |
| Timeouts | `orTimeout`/`completeOnTimeout` | Scope timeout / `Future.get(timeout)` |
| Composition | Rich operators | Plain code: loops, try/catch |
| When it still fits | Integrating callback-based APIs, event-driven pipelines, reactive interop | The default for request/response fan-out in new code |

---

## 6. Production failure modes & diagnostics (executors)

| Failure | Signature | Fix |
|---|---|---|
| Unbounded queue OOM | Heap full of `FutureTask`/lambda objects; latency grows for minutes before the OOM | Bounded queue plus rejection; load shedding; metrics on queue depth |
| Thread explosion | `newCachedThreadPool` under a burst → thousands of threads, `unable to create native thread` | Bounded max threads, or virtual threads with a semaphore |
| Silent task failure | Background jobs "just stop"; nothing in logs | Consume futures; `afterExecute` logging; try/catch in periodic tasks |
| Pool starvation deadlock | All workers `WAITING` in `FutureTask.get`; queue non-empty | No same-pool blocking; separate pools; async composition |
| commonPool starvation | Unrelated async work slow; commonPool workers blocked in I/O | Dedicated executors for blocking work |
| CallerRuns on a request thread | Latency spikes under load as request threads execute background work | Explicit rejection plus 503, or a separate overflow path |
| Shutdown hangs | `awaitTermination` times out; tasks ignore interrupts | Interrupt-aware tasks; restore the interrupt flag |
| Lost MDC / tracing context in async tasks | Logs without trace IDs | Wrap executors (context-propagation libraries, OpenTelemetry instrumentation); `ScopedValue` with structured concurrency |

**Metrics to export for every pool:** `pool.size`, `active`, `queue.size`, `queue.remaining_capacity`, `completed`, `rejected` (counted in the handler), and task wait and execution histograms. Micrometer's `ExecutorServiceMetrics` binds most of these. Name threads (`order-db-1`, …): thread names are your first clue in every thread dump.

---

## 7. Interview & certification Q&A

<details><summary><b>Q1. 🔥 Describe `ThreadPoolExecutor.execute()`'s algorithm. Why might `maximumPoolSize` never take effect?</b></summary>

Below the core size, start a new worker. Otherwise try to enqueue. If the queue rejects, start a non-core worker up to the max. Otherwise reject. With an unbounded queue the offer never fails, so the pool never grows past core and tasks queue without bound (`newFixedThreadPool` behaves this way).
</details>

<details><summary><b>Q2. 🎓 `submit()` vs `execute()`: what happens to an exception thrown by the task?</b></summary>

`execute`: the exception propagates out of the worker's run loop (`afterExecute` sees it), the thread's `UncaughtExceptionHandler` reports it, and the worker is replaced. `submit`: the exception is captured in the returned `Future` and only surfaces as `ExecutionException` from `get()`. If nobody calls `get`, it is silently lost.
</details>

<details><summary><b>Q3. 🔥 How do you size a thread pool for an I/O-bound service?</b></summary>

Start with Little's Law (concurrency = throughput × latency) and Goetz's formula `Ncpu × U × (1 + W/C)`. Then cap it by downstream capacity (DB pool size, remote rate limits), use separate bounded pools per dependency (bulkheads), measure queue wait and utilization, and adjust. On JDK 21+, consider virtual threads plus per-resource semaphores instead of large pools.
</details>

<details><summary><b>Q4. ⚡ Which thread executes `thenApply`'s function?</b></summary>

The thread that completes the previous stage. If the stage is already complete when `thenApply` is called, the calling thread executes it immediately. `thenApplyAsync` uses the given executor, or `ForkJoinPool.commonPool()` by default.
</details>

<details><summary><b>Q5. 🎓 What do `join()` and `get()` throw for a failed `CompletableFuture`?</b></summary>

`join()` throws the unchecked `CompletionException` (cause = the original exception). `get()` throws the checked `ExecutionException` (and `InterruptedException`). Both throw `CancellationException` if the future was cancelled.
</details>

<details><summary><b>Q6. 🔥 How does work stealing work, and why do thieves steal from the opposite end?</b></summary>

Each worker pushes and pops its own tasks LIFO at the top of its deque (cache locality, depth-first). Idle workers steal FIFO from the bottom of another worker's deque. The bottom holds the oldest, largest (least split) tasks, so one steal yields a lot of work and there is less contention with the owner, who works at the other end.
</details>

<details><summary><b>Q7. ⚡ Does `CompletableFuture.cancel(true)` interrupt the running computation?</b></summary>

No. It completes the future exceptionally with `CancellationException` and dependent stages see that, but the underlying `supplyAsync` task keeps running (it isn't linked to a thread interrupt). Use `ExecutorService` futures, structured concurrency, or cooperative cancellation flags.
</details>

<details><summary><b>Q8. ⚡ What happens to a periodic task scheduled with `scheduleAtFixedRate` if one execution throws?</b></summary>

All subsequent executions are suppressed and the `ScheduledFuture` completes exceptionally. Nothing is logged unless someone calls `get()`. Catch everything inside periodic tasks.
</details>

<details><summary><b>Q9. 🎓 What is the difference between `shutdown()` and `shutdownNow()`? What does `close()` do?</b></summary>

`shutdown()` stops accepting new tasks but lets queued and running ones finish. `shutdownNow()` also interrupts running tasks and returns the never-started queued tasks. `close()` (JDK 19+) calls `shutdown` and waits for termination (interrupt-aware), enabling try-with-resources.
</details>

---

## 8. Further reading

* `java.util.concurrent.ThreadPoolExecutor` Javadoc ("Queuing", "Rejected tasks", "Hook methods").
* *Java Concurrency in Practice*, ch. 6–8; Doug Lea, "A Java Fork/Join Framework".
* `CompletableFuture` Javadoc ("Actions supplied for dependent completions of non-async methods may be performed by the thread that completes the current CompletableFuture, or by any other caller of a completion method").
