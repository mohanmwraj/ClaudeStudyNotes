# 3.6 · Project Loom — Virtual Threads, Pinning, Structured Concurrency & Scoped Values

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut · 🎓 exam (1Z0-831: "platform and virtual threads, executors and scoped values")
> **Sources:** JEP 444 (Virtual Threads, JDK 21), JEP 491 (Synchronize Virtual Threads without Pinning, JDK 24), JEP 505 (Structured Concurrency, 5th preview, JDK 25), JEP 525 (6th preview, JDK 26), JEP 533 (7th preview, JDK 27), JEP 506 (Scoped Values, final in JDK 25), `java.lang.VirtualThread` source, Ron Pressler's Loom talks and design notes.
> **Everything below was run on Temurin 25.0.4.1.** Structured-concurrency code uses the **JDK 25 preview API** (`--enable-preview --release 25`), and §7.5 lists what changed in 26 and 27.

---

## 1. Why virtual threads exist 🔥

**Little's Law:** `concurrency = throughput × latency`. A service doing 5,000 req/s at 200 ms average latency has **1,000 requests in flight**. With thread-per-request on platform threads, that is 1,000 OS threads: ~1 GB of reserved stack, kernel scheduling overhead, and context switches. The industry's workaround was asynchronous code (callbacks, `CompletableFuture`, reactive streams). It scaled, but at the cost of unreadable stack traces, lost `ThreadLocal` context, viral `Mono<T>` types, and hard debugging.

**Virtual threads (VTs)** are `java.lang.Thread` instances **implemented by the JDK, not the OS**. They are cheap to create (a few hundred bytes to a few KB), cheap to block (blocking **unmounts** them from the OS thread), and so plentiful that you create one per task and never pool them.

Measured on this laptop: **10,000 tasks that each block for 100 ms**:

```
10k x 100ms sleeps: fixed pool(200) 5347 ms, virtual threads 153 ms
```

The 200-thread pool can run only 200 sleeps at a time (10,000 / 200 × 100 ms ≈ 5 s). Virtual threads run all 10,000 concurrently.

---

## 2. Architecture 🔥

```
                         Java code (blocking style)                     ← unchanged APIs: Thread, sockets, locks, queues
                                   │
                   VirtualThread  (java.lang.VirtualThread)
                   ├── Continuation  (jdk.internal.vm.Continuation)     ← one-shot delimited continuation
                   │       stack frames live in heap StackChunk objects while unmounted
                   └── scheduler: a dedicated ForkJoinPool in ASYNC (FIFO) mode
                           parallelism = availableProcessors()   (-Djdk.virtualThreadScheduler.parallelism)
                           maxPoolSize = max(parallelism, 256)    (-Djdk.virtualThreadScheduler.maxPoolSize)
                                   │
          ┌────────────── CARRIER threads (platform threads, group "CarrierThreads") ──────────────┐
          │  ForkJoinPool-1-worker-1   ForkJoinPool-1-worker-2   …                                │
          └──────────────────────────────────────────────────────────────────────────────────────┘

 MOUNT:   the scheduler picks a runnable VT → copies (lazily) its top frames onto the carrier's stack → runs it
 UNMOUNT: the VT calls a blocking operation (park, sleep, socket read, lock wait…) → Continuation.yield()
          → frames that changed are copied back to the heap StackChunk → the carrier is free for another VT
 RESUME:  when the blocking condition is satisfied (unpark, I/O readiness from the poller, timer),
          the VT is resubmitted to the scheduler — possibly onto a DIFFERENT carrier
```

**How blocking APIs were made to unmount:**

| Operation | Mechanism in JDK 21–25 |
|---|---|
| `LockSupport.park`, `ReentrantLock`, `BlockingQueue`, `CountDownLatch`, … | Park → `Continuation.yield` |
| `Thread.sleep` | Timer-based unpark → yield |
| Socket I/O (`java.net` and NIO channels in blocking mode) | Sockets are switched to non-blocking mode internally. On `EAGAIN` the VT registers with a **poller** (epoll/kqueue/wepoll) and parks, and the poller unparks it when the fd is ready (`NioSocketImpl`, JEP 353, made this possible) |
| `synchronized` enter and `Object.wait()` | **JDK 24+ (JEP 491): unmounts.** JDK 21–23: **pins** the carrier |
| File I/O, `InetAddress` DNS lookup, some native calls | **Capture the carrier** (the OS call blocks). The scheduler **compensates** by temporarily adding a carrier (up to `maxPoolSize`) |
| JNI/FFM native code that calls back into Java and blocks; blocking inside a class initializer; waiting for another thread to finish class initialization | **Still pins**, even in JDK 24+ (§4) |

### 2.1 Runnable: what a virtual thread looks like

<!-- run: -->
```java
import java.util.concurrent.*;

public class VtBasics {
    public static void main(String[] args) throws Exception {
        Thread vt = Thread.ofVirtual().name("order-", 1).unstarted(() -> {
            Thread me = Thread.currentThread();
            System.out.println("toString  : " + me.toString().replaceAll("worker-\\d+", "worker-N"));
            System.out.println("isVirtual=" + me.isVirtual() + " daemon=" + me.isDaemon() + " priority=" + me.getPriority()
                + " group=" + me.getThreadGroup().getName());
        });
        vt.start();
        vt.join();

        Thread.Builder.OfVirtual builder = Thread.ofVirtual().name("job-", 0);
        Thread a = builder.start(() -> { }), b = builder.start(() -> { });     // job-0, job-1
        a.join(); b.join();
        System.out.println("builder names: " + a.getName() + ", " + b.getName());

        try (ExecutorService ex = Executors.newVirtualThreadPerTaskExecutor()) {   // one NEW virtual thread per task
            Future<String> f = ex.submit(() -> Thread.currentThread().isVirtual() ? "ran on a virtual thread" : "platform?");
            System.out.println(f.get());
        }                                                                          // close() waits for all tasks
        Thread.startVirtualThread(() -> System.out.println("startVirtualThread: fire and forget")).join();
    }
}
```

Output (verified; thread IDs and carrier numbers vary):

```
toString  : VirtualThread[#28,order-1]/runnable@ForkJoinPool-1-worker-N
isVirtual=true daemon=true priority=5 group=VirtualThreads
builder names: job-0, job-1
ran on a virtual thread
startVirtualThread: fire and forget
```

Properties: always **daemon**; priority is fixed at `NORM_PRIORITY` (`setPriority` is ignored); thread group is a placeholder `VirtualThreads`; there is no `stop`/`suspend`/`resume`. `toString` shows the **current carrier** after the `@`.

---

## 3. What virtual threads are *not* 🔥

### 3.1 Not faster for CPU-bound work, and not preemptively time-sliced

The scheduler has **no time slicing**: a VT keeps its carrier until it blocks or finishes. CPU-bound VTs can starve every other VT on the same carriers.

<!-- run: jvm="-Djdk.virtualThreadScheduler.parallelism=2" -->
```java
public class NoTimeSlicing {
    static volatile long sink;
    public static void main(String[] args) throws Exception {
        long start = System.nanoTime();
        Thread sleeper = Thread.ofVirtual().start(() -> {
            try { Thread.sleep(10); } catch (InterruptedException e) { }
            System.out.printf("sleeper woke after %d ms (asked for 10 ms)%n", (System.nanoTime() - start) / 1_000_000);
        });
        Thread.sleep(2);
        Thread[] spinners = new Thread[2];                        // as many CPU hogs as carriers
        for (int i = 0; i < spinners.length; i++) spinners[i] = Thread.ofVirtual().start(() -> {
            long end = System.nanoTime() + 500_000_000L, x = 0;
            while (System.nanoTime() < end) x++;                  // never blocks → never yields its carrier
            sink += x;
        });
        sleeper.join();
        for (Thread t : spinners) t.join();
    }
}
```

Measured: with `-Djdk.virtualThreadScheduler.parallelism=2`, **`sleeper woke after 507 ms (asked for 10 ms)`**. With the default parallelism (12 on this machine): `sleeper woke after 15 ms`. In a server, a few CPU-heavy requests on virtual threads (JSON over megabyte payloads, image processing, crypto, big regexes) add latency to **every** request. Run CPU-heavy work on a bounded platform-thread pool sized to the cores, and keep VTs for blocking I/O orchestration.

### 3.2 Other things they are not

| Myth | Reality |
|---|---|
| "VTs make my service faster" | They raise **concurrency** for blocking workloads. Per-request latency is the same or slightly higher |
| "Pool them" | **Never.** Pooling defeats the design and keeps `ThreadLocal`s alive. Create one per task |
| "Limit them with the pool size" | Limit **resources** instead: `Semaphore`, bulkheads, connection pools |
| "ThreadLocals are free" | One copy **per VT**: 1M VTs × a 1 KB cached object = 1 GB. Avoid per-thread caches (`ThreadLocal<SimpleDateFormat>`, buffer recyclers), and use `ScopedValue` for context |
| "Everything unmounts" | File I/O and DNS block the carrier (compensated), and native and `<clinit>` cases pin (§4) |

---

## 4. Pinning 🔥

**Pinning** means the VT cannot unmount while blocked, so its **carrier is blocked too**. With enough pinned VTs, all carriers are stuck, and runnable VTs wait (latency spikes, or deadlock-like hangs).

### 4.1 Before and after JDK 24 (JEP 491)

| Situation | JDK 21–23 | JDK 24+ |
|---|---|---|
| Blocking while holding a `synchronized` monitor | **Pins** | Unmounts ✅ |
| Blocking to *enter* a contended `synchronized` | Pins | Unmounts ✅ |
| `Object.wait()` | Pins (compensated) | Unmounts ✅ |
| Native frame on the stack (JNI or FFM upcall) and the VT blocks | Pins | **Pins** |
| Blocking inside a class initializer (`<clinit>`) | Pins | **Pins** |
| Waiting for another thread to finish initializing a class | Pins | **Pins** |
| Diagnostic `-Djdk.tracePinnedThreads` | Prints stacks | **Removed** (no effect) |
| JFR `jdk.VirtualThreadPinned` | Emitted (mostly `synchronized`) | Emitted for the remaining cases, with **`pinnedReason`** and **carrier thread** fields |

### 4.2 Runnable: detecting pinning with JFR event streaming (JDK 25)

<!-- run: timeout=60 -->
```java
import java.time.Duration;
import java.util.*;
import jdk.jfr.consumer.RecordingStream;

public class PinningDetector {
    static final Object LOCK = new Object();
    static class SlowInit {                                   // blocking inside <clinit> still pins in JDK 24+
        static final String VALUE;
        static { sleep(60); VALUE = "ready"; }
    }

    public static void main(String[] args) throws Exception {
        Map<String, String> reasons = Collections.synchronizedMap(new LinkedHashMap<>());
        try (var rs = new RecordingStream()) {
            rs.enable("jdk.VirtualThreadPinned").withThreshold(Duration.ofMillis(1)).withStackTrace();
            rs.onEvent("jdk.VirtualThreadPinned", e -> reasons.put(e.getString("pinnedReason"), e.getString("blockingOperation")));
            rs.startAsync();

            Thread.ofVirtual().start(() -> { synchronized (LOCK) { sleep(60); } }).join();   // JDK 21-23: pinned; 24+: not
            Thread.ofVirtual().start(() -> { String v = SlowInit.VALUE; }).join();
            Thread.sleep(1500);                                                            // let the stream deliver events
        }
        System.out.println("synchronized + sleep pinned? " + reasons.keySet().stream().anyMatch(r -> !r.contains("<clinit>")));
        reasons.forEach((reason, op) -> System.out.println("pinned: reason=\"" + reason + "\" blockingOperation=" + op));
    }
    static void sleep(long ms) { try { Thread.sleep(ms); } catch (InterruptedException e) { Thread.currentThread().interrupt(); } }
}
```

Output (verified, JDK 25):

```
synchronized + sleep pinned? false
pinned: reason="VM call to PinningDetector$SlowInit.<clinit> on stack" blockingOperation=LockSupport.park
```

**In production:** keep JFR on (`jdk.VirtualThreadPinned` is enabled by default with a 20 ms threshold in the `default` profile), alert on the event's frequency, and read its stack trace. On **JDK 21 (LTS)**, still common in 2026, the guidance remains: replace `synchronized` around blocking I/O with `ReentrantLock`, and upgrade libraries (JDBC drivers, connection pools, HTTP clients) to versions that did so. Better: move to JDK 25.

### 4.3 The classic JDK 21 incident

A service enabled virtual threads on JDK 21. Under load it **hung**: all 12 carriers were pinned by VTs blocked inside a `synchronized` block in an old JDBC driver (waiting for a pool connection), while the VTs that *held* connections and needed a carrier to finish and release them couldn't be scheduled. That is a liveness deadlock with no Java-level lock cycle. Diagnosis: a JSON thread dump showed thousands of VTs waiting and every carrier's stack pinned inside the driver's `synchronized` method. Fixes: upgrade the driver, raise `maxPoolSize` temporarily, or move to JDK 24+ (JEP 491).

---

## 5. Limiting concurrency: the new capacity model 🔥

With platform threads, the pool size implicitly limited load on downstream systems. With VTs, **nothing does**: 10,000 concurrent requests become 10,000 concurrent DB queries unless you add limits.

```java
private final Semaphore dbPermits = new Semaphore(50);           // ≈ connection pool size (Pillar 5: Hikari)

Order load(long id) throws InterruptedException {
    if (!dbPermits.tryAcquire(200, TimeUnit.MILLISECONDS)) throw new OverloadedException("db busy");  // fail fast → 503
    try {
        return repository.findById(id);
    } finally {
        dbPermits.release();
    }
}
```

* Limit at **each scarce resource**: DB pools, per-partner HTTP concurrency, file handles, CPU-heavy sections (a small platform pool).
* Prefer **fail-fast with a timeout** over unbounded waiting: queued VTs are cheap, but queued *latency* isn't.
* Resilience4j's `Bulkhead` (semaphore type) and `RateLimiter` work with VTs (Pillar 6).

---

## 6. Observability for virtual threads ⚡

| Tool | Virtual-thread support |
|---|---|
| `jcmd <pid> Thread.dump_to_file -format=json <file>` | ✅ All VTs, grouped by **thread container** (executors, structured scopes) |
| `HotSpotDiagnosticMXBean.dumpThreads(file, JSON)` | ✅ The same, programmatically |
| `jstack` / `jcmd Thread.print` | Only platform threads, plus mounted VTs shown on their carriers. **Unmounted VTs are not listed** |
| JFR | `jdk.VirtualThreadPinned` (on), `jdk.VirtualThreadSubmitFailed` (on), `jdk.VirtualThreadStart`/`End` (off by default: high volume) |
| Debuggers (IntelliJ, jdb) | ✅ Step through VTs like normal threads |

Real JSON excerpt (JDK 25) showing a structured-concurrency scope named `order-lookup` with its forked VTs:

```json
{
  "container": "order-lookup\/jdk.internal.misc.ThreadFlock$ThreadContainerImpl@6d4e5011",
  "parent": "<root>",
  "owner": "3",
  "threads": [
    {
      "tid": "33",
      "time": "2026-10-24T07:32:40.850496400Z",
      "virtual": true,
      "name": "",
      "state": "TIMED_WAITING",
      "stack": [
        "java.base\/java.lang.VirtualThread.parkNanos(VirtualThread.java:787)",
        "java.base\/java.lang.VirtualThread.sleepNanos(VirtualThread.java:983)",
        …
```

The **container tree** (`parent`, `owner`) is the structured-concurrency payoff: you can see which request (owner thread) spawned which subtasks.

---

## 7. Structured concurrency (preview: JEP 505 in JDK 25) 🔥

### 7.1 The idea

Treat a group of concurrent subtasks as **one unit of work** with a lexical scope, like a code block:

* Subtasks are **forked** inside a scope and **joined** before the scope closes. No thread outlives its scope ("no orphan threads").
* **Failure and cancellation propagate:** a joiner policy decides when the scope is done, and the remaining subtasks are **interrupted**.
* The owner thread is the only one allowed to `fork`/`join`/`close`. Misuse throws `StructureViolationException` or `WrongThreadException`.
* Thread dumps show the parent–child relationship. `ScopedValue` bindings are **inherited** by forks.

### 7.2 API (JDK 25)

| Member | Meaning |
|---|---|
| `StructuredTaskScope.open()` | Default policy: **all subtasks must succeed**. `join()` returns `null` or throws `FailedException` (cause = the first failure), and cancels the others |
| `open(Joiner<T,R>)` | A custom policy. `join()` returns `R` |
| `open(Joiner, Function<Configuration, Configuration>)` | Configure `withName`, `withThreadFactory`, `withTimeout` (`join()` throws `TimeoutException`) |
| `scope.fork(Callable<U>)` → `Subtask<U>` | Starts a virtual thread (by default) |
| `scope.join()` | Waits per policy. Must be called before `get()` on subtasks |
| `Subtask.state()` | `UNAVAILABLE`, `SUCCESS`, `FAILED`; `get()`, `exception()` |
| `Joiner.allSuccessfulOrThrow()` | `R = Stream<Subtask<T>>`. Fails fast on the first failure |
| `Joiner.anySuccessfulResultOrThrow()` | `R = T` from the first success, then cancels the rest (a race) |
| `Joiner.awaitAllSuccessfulOrThrow()` | `R = Void`. Waits for all; throws on the first failure |
| `Joiner.awaitAll()` | `R = Void`. Waits for all, regardless of failures |
| `Joiner.allUntil(Predicate<Subtask>)` | Collects until the predicate cancels the scope |
| Custom `Joiner` | Implement `onFork`/`onComplete` (return `true` to cancel the scope) and `result()` |

### 7.3 Runnable: the policies in action

<!-- run: timeout=60 -->
```java
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.StructuredTaskScope.Joiner;
import java.util.concurrent.StructuredTaskScope.Subtask;
import java.util.concurrent.atomic.AtomicInteger;

public class StructuredDemo {
    static String call(String name, long ms, boolean fail) throws InterruptedException {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            System.out.println("    " + name + " was CANCELLED (interrupted)");
            throw e;
        }
        if (fail) throw new IllegalStateException(name + " failed");
        return name;
    }

    /** Custom joiner: succeed as soon as `quorum` subtasks have succeeded, then cancel the rest. */
    static <T> Joiner<T, List<T>> quorum(int quorum) {
        return new Joiner<>() {
            private final Queue<T> results = new ConcurrentLinkedQueue<>();
            private final AtomicInteger successes = new AtomicInteger();
            @Override public boolean onComplete(Subtask<? extends T> st) {
                if (st.state() == Subtask.State.SUCCESS) {
                    results.add(st.get());
                    return successes.incrementAndGet() >= quorum;     // true → cancel the scope
                }
                return false;
            }
            @Override public List<T> result() { return List.copyOf(results).subList(0, Math.min(quorum, results.size())); }
        };
    }

    public static void main(String[] args) throws Exception {
        System.out.println("1. default policy, one subtask fails:");
        try (var scope = StructuredTaskScope.open()) {
            scope.fork(() -> call("inventory", 50, true));
            scope.fork(() -> call("pricing", 2_000, false));         // still running → gets cancelled
            scope.join();
        } catch (StructuredTaskScope.FailedException e) {
            System.out.println("    join() → FailedException, cause: " + e.getCause().getMessage());
        }

        System.out.println("2. race (anySuccessfulResultOrThrow):");
        try (var scope = StructuredTaskScope.open(Joiner.<String>anySuccessfulResultOrThrow())) {
            scope.fork(() -> call("replica-eu", 300, false));
            scope.fork(() -> call("replica-us", 30, false));
            System.out.println("    winner: " + scope.join());
        }

        System.out.println("3. all results (allSuccessfulOrThrow):");
        try (var scope = StructuredTaskScope.open(Joiner.<String>allSuccessfulOrThrow())) {
            for (String svc : List.of("user", "orders", "prefs")) scope.fork(() -> call(svc, 20, false));
            System.out.println("    " + scope.join().map(Subtask::get).toList());
        }

        System.out.println("4. timeout:");
        try (var scope = StructuredTaskScope.open(Joiner.<String>awaitAll(), cf -> cf.withTimeout(Duration.ofMillis(100)))) {
            scope.fork(() -> call("slow-partner", 5_000, false));
            scope.join();
        } catch (StructuredTaskScope.TimeoutException e) {
            System.out.println("    join() → TimeoutException");
        }

        System.out.println("5. custom quorum joiner (2 of 3):");
        try (var scope = StructuredTaskScope.open(StructuredDemo.<String>quorum(2))) {
            scope.fork(() -> call("node-a", 20, false));
            scope.fork(() -> call("node-b", 40, false));
            scope.fork(() -> call("node-c", 2_000, false));
            System.out.println("    quorum reached: " + scope.join().stream().sorted().toList());
        }
    }
}
```

Output (verified):

```
1. default policy, one subtask fails:
    pricing was CANCELLED (interrupted)
    join() → FailedException, cause: inventory failed
2. race (anySuccessfulResultOrThrow):
    replica-eu was CANCELLED (interrupted)
    winner: replica-us
3. all results (allSuccessfulOrThrow):
    [user, orders, prefs]
4. timeout:
    slow-partner was CANCELLED (interrupted)
    join() → TimeoutException
5. custom quorum joiner (2 of 3):
    node-c was CANCELLED (interrupted)
    quorum reached: [node-a, node-b]
```

Every policy **cleans up after itself**: losing, failed or timed-out siblings are interrupted, and `close()` waits for them to finish. Compare that with `CompletableFuture.anyOf`, which leaves the losers running ([3.4 §5.2](04-Executors-ForkJoin-CompletableFuture.md#52-composition-and-error-handling)).

### 7.4 Structured concurrency vs `CompletableFuture` vs reactive

| | `StructuredTaskScope` | `CompletableFuture` | Reactor `Mono.zip`/`firstWithValue` |
|---|---|---|---|
| Cancellation of siblings | Automatic (interrupt) | Manual; `cancel` doesn't interrupt | Automatic (subscription cancel) |
| Lifetime guarantee | Forks can't outlive the scope | None (leaks possible) | Bound to the subscription |
| Exceptions | Normal try/catch | Wrapped `CompletionException` | Error signals |
| Context | `ScopedValue` inherited | Manual propagation | Reactor `Context` |
| Status | **Preview** (5th in 25, 6th in 26, 7th in 27) | Final | Library |

### 7.5 API churn: JDK 25 → 26 → 27 ⚠️

Preview APIs change. Pin your code to one JDK version until it's final:

| Change | JDK |
|---|---|
| `Joiner.onTimeout()` added (a joiner can return a result when the timeout expires) | 26 (JEP 525) |
| `allSuccessfulOrThrow()` returns a **`List` of results** instead of a `Stream<Subtask>` | 26 |
| `anySuccessfulResultOrThrow()` **renamed** `anySuccessfulOrThrow()` | 26 |
| `open(Joiner, …)` takes a `UnaryOperator<Configuration>` instead of a `Function` | 26 |
| Third type parameter `R_X extends Throwable`: the exception type `join()` throws | 27 (JEP 533) |
| Failing joiners make `join()` throw `ExecutionException` (overloads let you map it to another exception) | 27 |
| `Joiner.awaitAll()` **removed**; `onTimeout()` renamed **`timeout()`** (the exception has `CancelledByTimeoutException` as its cause) | 27 |
| New `open(UnaryOperator<Configuration>)` with the default joiner | 27 |

---

## 8. Scoped values (final in JDK 25, JEP 506) 🔥🎓

A `ScopedValue<T>` is an **immutable, inheritable, bounded-lifetime** per-thread binding: the modern replacement for `ThreadLocal` as a carrier of request context.

<!-- run: -->
```java
import java.util.concurrent.StructuredTaskScope;
import java.util.concurrent.StructuredTaskScope.Joiner;
import java.util.concurrent.StructuredTaskScope.Subtask;

public class ScopedValues {
    record Principal(String user, String tenant) {}
    static final ScopedValue<Principal> PRINCIPAL = ScopedValue.newInstance();
    static final ScopedValue<String> TRACE_ID = ScopedValue.newInstance();

    static String repositoryQuery(String what) {                 // deep in the call stack: no parameter threading
        Principal p = PRINCIPAL.get();                           // NoSuchElementException if unbound
        return what + "[tenant=" + p.tenant() + ", trace=" + TRACE_ID.orElse("none") + ", vt=" + Thread.currentThread().isVirtual() + "]";
    }

    static String handleRequest() throws Exception {
        try (var scope = StructuredTaskScope.open(Joiner.<String>allSuccessfulOrThrow())) {
            scope.fork(() -> repositoryQuery("orders"));          // forks INHERIT the caller's bindings
            scope.fork(() -> repositoryQuery("invoices"));
            return scope.join().map(Subtask::get).toList().toString();
        }
    }

    public static void main(String[] args) throws Exception {
        System.out.println("bound outside? " + PRINCIPAL.isBound());
        String result = ScopedValue.where(PRINCIPAL, new Principal("ann", "acme"))
            .where(TRACE_ID, "t-42")
            .call(ScopedValues::handleRequest);
        System.out.println(result);

        ScopedValue.where(PRINCIPAL, new Principal("ann", "acme")).run(() -> {
            System.out.println("outer: " + PRINCIPAL.get().user());
            ScopedValue.where(PRINCIPAL, new Principal("system", "acme")).run(() ->       // rebinding for a sub-scope
                System.out.println("  nested rebinding: " + PRINCIPAL.get().user()));
            System.out.println("outer again: " + PRINCIPAL.get().user());
        });
        try { PRINCIPAL.get(); } catch (java.util.NoSuchElementException e) { System.out.println("after scope: unbound → NoSuchElementException"); }
    }
}
```

Output (verified):

```
bound outside? false
[orders[tenant=acme, trace=t-42, vt=true], invoices[tenant=acme, trace=t-42, vt=true]]
outer: ann
  nested rebinding: system
outer again: ann
after scope: unbound → NoSuchElementException
```

| | `ThreadLocal` | `ScopedValue` |
|---|---|---|
| Write | `set()` anytime, anywhere (spooky action at a distance) | Bound once per scope (`where(...).run/call`); **immutable** |
| Lifetime | Until `remove()` or thread death (leaks, bleed) | Exactly the dynamic extent of `run`/`call` |
| Child threads | `InheritableThreadLocal` copies at thread creation | Inherited by `StructuredTaskScope` forks at **zero copy cost** |
| Cost with 1M VTs | A map plus entries per thread | Small and constant per binding; reads optimized by the JIT |
| Good for | Legacy libraries, mutable per-thread caches | Request context: principal, tenant, trace/span IDs, locale, deadline |

---

## 9. Migration playbook: adopting virtual threads (JDK 25) 🔥

1. **Upgrade to JDK 24+** (ideally 25 LTS) so `synchronized` no longer pins.
2. Spring Boot 3.2+: `spring.threads.virtual.enabled=true` puts Tomcat/Jetty request handling, `@Async`, scheduling and messaging listeners on VTs (Pillar 6). Plain Java: `Executors.newVirtualThreadPerTaskExecutor()` per request or task.
3. **Add concurrency limits** at every scarce resource (§5). Re-check DB pool sizing (Pillar 5); a bigger thread count doesn't mean a bigger DB pool.
4. **Audit `ThreadLocal`** usage: per-thread caches (Jackson buffer recyclers, formatters, `Random`s, Kryo instances) multiply by the VT count. Move request context to `ScopedValue` where libraries allow.
5. **Isolate CPU-heavy work** on a bounded platform pool.
6. Check native and `<clinit>` pinning in JFR (`jdk.VirtualThreadPinned`) under load tests.
7. Replace `CompletableFuture` fan-out with structured concurrency where preview features are acceptable, or with a VT executor plus `invokeAll`/futures where they aren't.
8. Update dashboards: thread-count metrics now mean little. Watch **in-flight requests**, semaphore wait times, pool waits, and carrier utilization (CPU).

---

## 10. Production failure modes & diagnostic checklist (Loom)

| Failure | Signature | Fix |
|---|---|---|
| Carrier exhaustion by pinning (JDK 21–23, or native/`<clinit>` on 24+) | Hang or latency cliff; JFR `jdk.VirtualThreadPinned` storm; JSON dump: carriers parked in `synchronized`/native frames | JDK 24+; `ReentrantLock` around blocking I/O; upgrade drivers; avoid blocking in `<clinit>` |
| Starvation by CPU-bound VTs | All carriers RUNNABLE in compute; sleeping VTs wake late (measured 507 ms vs 10 ms) | Bounded platform pool for CPU work; keep VTs for I/O |
| Downstream overload | DB or partner saturated after VT adoption; connection-pool timeouts | Semaphores and bulkheads sized to downstream capacity |
| Memory blow-up | Heap full of `ThreadLocalMap$Entry`, per-thread caches, deep `StackChunk`s | Remove per-thread caches; `ScopedValue`; avoid deep recursion in VTs |
| Pooled virtual threads | Odd ThreadLocal leakage; no benefit | Never pool VTs |
| Invisible threads in jstack | "Where are my request threads?" | `jcmd Thread.dump_to_file -format=json` |
| Lost cancellation | Fan-out subtasks keep running after the request fails | `StructuredTaskScope` (interrupts siblings); interrupt-aware code |
| File I/O-heavy VT workloads | Carrier count grows toward `maxPoolSize` (compensation), CPU contention | A dedicated platform pool for heavy file I/O, or async file APIs |

**Commands:**

```bash
jcmd <pid> Thread.dump_to_file -format=json /tmp/threads.json      # all VTs + containers
jcmd <pid> JFR.start name=loom settings=profile duration=120s filename=/tmp/loom.jfr
jfr print --events jdk.VirtualThreadPinned,jdk.VirtualThreadSubmitFailed /tmp/loom.jfr
java -Djdk.virtualThreadScheduler.parallelism=N -Djdk.virtualThreadScheduler.maxPoolSize=M …   # tune carriers (rarely needed)
```

---

## 11. Interview & certification Q&A

<details><summary><b>Q1. 🔥 How do virtual threads work under the hood?</b></summary>

A virtual thread is a `Thread` whose execution state is a heap-allocated continuation. A scheduler (a FIFO-mode `ForkJoinPool` with parallelism = cores) mounts it on a carrier platform thread to run. When it blocks on a JDK-aware operation (park, sleep, socket I/O via the poller, lock waits, and since JDK 24 monitors), the continuation yields: the changed stack frames are copied to heap stack chunks and the carrier is freed. When the operation completes, the VT is rescheduled, possibly on another carrier.
</details>

<details><summary><b>Q2. 🔥 What is pinning, and what changed in JDK 24?</b></summary>

Pinning means a blocked VT can't unmount, so its carrier blocks too. Before JDK 24 the main causes were blocking inside `synchronized` and `Object.wait()`. JEP 491 (JDK 24) made monitors VT-aware, so they no longer pin. Pinning remains for native frames on the stack (JNI/FFM upcalls that block), blocking inside class initializers, and waiting for class initialization. It's diagnosed with JFR `jdk.VirtualThreadPinned` (now with a `pinnedReason`); `jdk.tracePinnedThreads` was removed.
</details>

<details><summary><b>Q3. 🔥 Should you pool virtual threads? How do you limit concurrency then?</b></summary>

No. They're cheap to create, and pooling reintroduces ThreadLocal leakage and artificial limits. Create one per task (`newVirtualThreadPerTaskExecutor`), and limit access to scarce resources with semaphores, bulkheads, and properly sized connection pools.
</details>

<details><summary><b>Q4. ⚡ Why don't virtual threads help CPU-bound workloads?</b></summary>

Throughput for CPU work is bounded by cores, and VTs add no cores. Worse, the VT scheduler has no time slicing, so CPU-bound VTs monopolize carriers and starve other VTs (measured: a 10 ms sleep woke after 507 ms with 2 carriers busy). Use a bounded platform pool for CPU work.
</details>

<details><summary><b>Q5. 🎓 Name three ways to create a virtual thread.</b></summary>

`Thread.ofVirtual().start(runnable)` (or `.unstarted(...)`, and a builder with `name("prefix-", 0)`), `Thread.startVirtualThread(runnable)`, and `Executors.newVirtualThreadPerTaskExecutor()` (one new VT per submitted task). A `ThreadFactory` from `Thread.ofVirtual().factory()` also works with other executors.
</details>

<details><summary><b>Q6. 🔥 What problems does structured concurrency solve compared with `CompletableFuture`?</b></summary>

Guaranteed lifetimes (subtasks can't outlive the scope, so no leaked threads), automatic cancellation of siblings on failure, race completion or timeout (by interruption), straightforward exception handling (no `CompletionException` wrapping), observability (a thread-dump hierarchy), and inheritance of `ScopedValue` context. `CompletableFuture.cancel` doesn't even interrupt running tasks.
</details>

<details><summary><b>Q7. 🎓 What does `ScopedValue.get()` do when no binding exists, and how do you bind multiple values?</b></summary>

It throws `NoSuchElementException`. Check `isBound()` or use `orElse(default)`. Chain bindings with `ScopedValue.where(A, a).where(B, b).run(...)` or `.call(...)`. Bindings are visible during that dynamic extent, inherited by `StructuredTaskScope` forks, and can be rebound in nested scopes.
</details>

<details><summary><b>Q8. ⚡ Why might `jstack` not show your request threads after enabling virtual threads?</b></summary>

`jstack`/`Thread.print` list platform threads. Unmounted virtual threads aren't platform threads, so they don't appear (mounted ones show on their carriers). Use `jcmd <pid> Thread.dump_to_file -format=json` (or `HotSpotDiagnosticMXBean.dumpThreads`), which includes all VTs grouped by container.
</details>

<details><summary><b>Q9. 🧊 Which blocking operations capture the carrier instead of unmounting, and how does the JDK mitigate it?</b></summary>

Most file-system I/O and some native calls (for example DNS resolution via `InetAddress`) block the OS thread. The scheduler compensates by temporarily adding carrier threads (up to `jdk.virtualThreadScheduler.maxPoolSize`, default 256) so other VTs keep running.
</details>

<details><summary><b>Q10. ⚡ What changed in the structured concurrency API between JDK 25 and 27?</b></summary>

26: `anySuccessfulResultOrThrow` renamed to `anySuccessfulOrThrow`, `allSuccessfulOrThrow` returns a `List` of results, `Joiner.onTimeout` added, and the configuration function became a `UnaryOperator`. 27: a third type parameter for `join()`'s exception type, failing joiners throw `ExecutionException`, `awaitAll` removed, `onTimeout` renamed `timeout`, and a new `open(UnaryOperator)`. It is still a preview, so pin code to one JDK.
</details>

---

## 12. Further reading

* JEP 444: <https://openjdk.org/jeps/444> · JEP 491: <https://openjdk.org/jeps/491> · JEP 505/525/533 (structured concurrency) · JEP 506 (scoped values)
* Ron Pressler, "State of Loom" (parts 1–2) and "Virtual Threads: New Foundations for High-Scale Java Applications".
* Oracle, "Virtual Threads" guide (JDK 25 docs): <https://docs.oracle.com/en/java/javase/25/core/virtual-threads.html>
