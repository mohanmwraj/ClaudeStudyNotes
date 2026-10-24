# 3.7 · Pillar 3 — Production Failure Modes & Diagnostic Checklist (Concurrency & Loom)

> Concurrency incidents are the hardest to reproduce, so you need the **evidence-collection habits** in place *before* the incident. This file has the incident playbooks (composite war stories, each mechanism demonstrated by a verified program in [3.1](01-Java-Memory-Model.md)–[3.6](06-Virtual-Threads-Structured-Concurrency-Scoped-Values.md)), a **thread-dump reading guide** using real JDK 25 output, and the metrics and alerts that catch problems early.

---

## 1. Incident playbooks

### 🔥 Story 1 — "Enabled virtual threads, service froze" (JDK 21)

* **Symptom:** after `spring.threads.virtual.enabled=true` on JDK 21, the service stops responding under moderate load. CPU is near 0%, and no errors are logged.
* **Evidence:** a JSON thread dump (`jcmd <pid> Thread.dump_to_file -format=json`) shows thousands of VTs waiting for a DB connection, and every `ForkJoinPool-1-worker-*` carrier pinned inside an old JDBC driver's `synchronized` method, blocked on socket I/O. JFR shows a storm of `jdk.VirtualThreadPinned` events.
* **Root cause:** pinning ([3.6 §4](06-Virtual-Threads-Structured-Concurrency-Scoped-Values.md#4-pinning-)). The VTs holding connections couldn't get a carrier to finish and release them.
* **Fix:** upgrade the driver (vendors replaced `synchronized` with `ReentrantLock`), move to JDK 24+/25 (JEP 491), and add a semaphore in front of the DB.

### 🔥 Story 2 — "Virtual threads melted the database"

* **Symptom:** after migrating to VTs, p99 rose and the DB CPU hit 100%. Hikari logs `Connection is not available, request timed out after 30000ms`.
* **Root cause:** the old 200-thread Tomcat pool had been an **implicit concurrency limit**. With VTs, 5,000 concurrent requests all queued on the 50-connection pool, and a slow query pattern got hammered at full concurrency.
* **Fix:** an explicit bulkhead (`Semaphore`/Resilience4j) sized to the pool, `tryAcquire` with a timeout returning 503, and query fixes. See [3.6 §5](06-Virtual-Threads-Structured-Concurrency-Scoped-Values.md#5-limiting-concurrency-the-new-capacity-model-).

### 🔥 Story 3 — "The consumer never stops" (visibility)

* **Symptom:** graceful shutdown hangs; a worker keeps consuming after `running = false`.
* **Root cause:** a non-volatile `boolean running` read in a tight loop. C2 hoisted the read ([3.1 Demo 1](01-Java-Memory-Model.md#3-demo-1--visibility-the-loop-that-never-ends-)).
* **Fix:** `volatile`/`AtomicBoolean`, or better, interrupt-based cancellation (`while (!Thread.currentThread().isInterrupted())`, or a `BlockingQueue` poison pill).

### 🔥 Story 4 — "Money transfers froze at month-end"

* **Symptom:** during month-end batch runs, transfer throughput drops to zero.
* **Evidence (real `jcmd Thread.print` output from the reproduction):**

```
Found one Java-level deadlock:
=============================
"transfer-A-to-B":
  waiting to lock monitor 0x00000208a7c52230 (object 0x000000071441e5f0, a Bank$Account),
  which is held by "transfer-B-to-A"

"transfer-B-to-A":
  waiting to lock monitor 0x00000208a7c31470 (object 0x000000071441e5b0, a Bank$Account),
  which is held by "transfer-A-to-B"

Java stack information for the threads listed above:
===================================================
"transfer-A-to-B":
	at Bank.transfer(Bank.java:6)
	- waiting to lock <0x000000071441e5f0> (a Bank$Account)
	- locked <0x000000071441e5b0> (a Bank$Account)
	…
Found 1 deadlock.
```

* **Root cause:** `transfer(from, to)` locked `from` then `to`, and opposite-direction transfers locked in opposite orders.
* **Fix:** lock in a global order (by account ID), or use DB transactions with ordered row locks.

### ⚡ Story 5 — "The nightly reconciliation stopped running in March"

* **Root cause:** `scheduleAtFixedRate` task threw once (a transient network error). All future executions were silently cancelled ([3.4 §3.2](04-Executors-ForkJoin-CompletableFuture.md#32-scheduled-tasks-die-silently)).
* **Fix:** catch `Throwable` inside periodic tasks, add a "last successful run" metric with an alert on staleness, and use a scheduler with error handling.

### ⚡ Story 6 — "Heap full of `FutureTask`"

* **Root cause:** `Executors.newFixedThreadPool(16)` (an unbounded `LinkedBlockingQueue`) behind a Kafka consumer. During a downstream slowdown, millions of tasks queued, ending in OOM ([3.4 §1.2](04-Executors-ForkJoin-CompletableFuture.md#12-runnable-queue-choice-decides-the-pools-behaviour)).
* **Fix:** a bounded queue, pausing consumption (backpressure) when full, and a queue-depth metric with an alert.

### ⚡ Story 7 — "Event loop blocked by CallerRunsPolicy"

* **Root cause:** an executor with `CallerRunsPolicy` received tasks from a Netty event-loop thread. Under overload, the event loop itself ran blocking tasks, which stalled all connections on that loop (Pillar 4).
* **Fix:** never let an event loop be the "caller" of `CallerRuns`; reject with an explicit overload response instead.

### ⚡ Story 8 — "Requests executed as another tenant"

* **Root cause:** a `ThreadLocal` tenant context set in a filter and never removed on an error path. The next request on that pooled thread inherited it ([3.5 §4.2](05-Concurrent-Collections-Synchronizers-ThreadLocal.md#42-runnable-context-bleeding-between-pooled-tasks-the-mdc-bug)).
* **Fix:** `try/finally remove()`, a request-scoped `ScopedValue` (JDK 25), and tests asserting no context leaks between requests.

### ⚡ Story 9 — "Fair lock made it 200× slower"

* **Root cause:** a well-meaning `new ReentrantLock(true)` on a hot cache path ([3.2 §2.1](02-Synchronization-Locks-AQS.md#21-fairness-costs-throughput-measured)).
* **Fix:** a non-fair lock, a shorter critical section, or a concurrent map instead.

### ⚡ Story 10 — "Only fails on ARM" (Graviton migration)

* **Root cause:** a config object was published through a plain (non-volatile) field after its fields were written. x86 TSO happened to preserve the order; ARMv8 didn't, so readers saw default values ([3.1 §1](01-Java-Memory-Model.md#1-why-java-needs-a-memory-model-)).
* **Fix:** safe publication (volatile/`AtomicReference`/final fields), jcstress in ARM CI.

### ⚡ Story 11 — "Image thumbnails made every API slow"

* **Root cause:** CPU-heavy thumbnail generation ran on virtual threads. With no time slicing, I/O-bound VTs waited for carriers ([3.6 §3.1](06-Virtual-Threads-Structured-Concurrency-Scoped-Values.md#31-not-faster-for-cpu-bound-work-and-not-preemptively-time-sliced), measured: 507 ms delay for a 10 ms sleep).
* **Fix:** a dedicated bounded platform pool for CPU work.

### ⚡ Story 12 — "Pods killed on every deploy"

* **Root cause:** worker tasks swallowed `InterruptedException` (`catch (InterruptedException e) {}`), so `shutdownNow` couldn't stop them. Kubernetes' `terminationGracePeriodSeconds` expired and the pod got SIGKILLed mid-transaction.
* **Fix:** restore the interrupt flag or propagate, make long loops check interruption, and bound shutdown with `awaitTermination` plus logging.

### 🧊 Story 13 — "Trace IDs vanish in async code"

* **Root cause:** OpenTelemetry context and MDC are `ThreadLocal`-based. `CompletableFuture.supplyAsync` on the common pool lost them.
* **Fix:** context-propagating executors (OTel's `Context.taskWrapping(executor)`, Micrometer context-propagation), or structured concurrency with `ScopedValue` (forks inherit). [8.2](../08-Observability-Security-Testing/02-Observability-OpenTelemetry-Micrometer-Logging.md) covers OTel in depth.

---

## 2. Reading thread dumps like a pro

### 2.1 Anatomy of a thread entry (real JDK 25 output)

```
"transfer-A-to-B" #26 [26240] prio=5 os_prio=0 cpu=0.00ms elapsed=2.60s tid=0x00000208a7c2e880 nid=26240 waiting for monitor entry  [0x00000031f67ff000]
   java.lang.Thread.State: BLOCKED (on object monitor)
	at Bank.transfer(Bank.java:6)
	- waiting to lock <0x000000071441e5f0> (a Bank$Account)
	- locked <0x000000071441e5b0> (a Bank$Account)
```

| Field | Meaning |
|---|---|
| `"transfer-A-to-B"` | Thread name. **Name your threads** (thread factories, `Thread.ofVirtual().name("order-", 0)`) |
| `#26` | Java thread ID |
| `[26240]` / `nid=26240` | Native (OS) thread ID. Match it against `top -H` (Linux shows it in decimal; older dumps print hex) to find hot threads |
| `cpu=0.00ms elapsed=2.60s` | CPU time vs wall time. **High CPU means busy; low CPU with a long elapsed time means waiting** |
| State line | `BLOCKED (on object monitor)`, `WAITING (parking)`, `TIMED_WAITING (sleeping)`, `RUNNABLE` |
| `- waiting to lock <addr>` | Wants a monitor (BLOCKED) |
| `- locked <addr>` | Holds a monitor |
| `- parking to wait for <addr> (a …ReentrantLock$NonfairSync)` | Waiting on a `j.u.c` lock or condition |
| `Locked ownable synchronizers:` (with `-l`) | `j.u.c` locks this thread holds |

### 2.2 The method

1. **Take 3 dumps 5–10 s apart** (`jcmd <pid> Thread.print -l > td.$i`). A single dump can't distinguish "stuck" from "busy".
2. **Group threads by stack.** Many threads with identical top frames reveal the bottleneck. Tools: fastThread.io, IntelliJ's thread dump analyzer, `jstack.review`, or just `grep -A3 'State:' | sort | uniq -c`.
3. **Follow lock addresses.** For a lock that many threads are `waiting to lock`, find the thread with `- locked <same addr>`. Its stack is the bottleneck (often I/O under a lock).
4. **Check pool threads.** `pool-*`/`ForkJoinPool.commonPool-worker-*`/`http-nio-*` all `WAITING` in `FutureTask.get` means pool starvation. All `RUNNABLE` in compute means CPU saturation.
5. **For virtual threads,** use `Thread.dump_to_file -format=json`: see the containers (executors and scopes), the VT stacks, and whether the carriers are pinned.
6. **Correlate with JFR** (`jdk.JavaMonitorEnter`, `jdk.ThreadPark`, `jdk.VirtualThreadPinned`) for *how long* threads wait, not just *that* they wait.

### 2.3 Quick triage table

| Dump pattern | Diagnosis |
|---|---|
| "Found one Java-level deadlock" | Lock-order deadlock |
| Many `BLOCKED` on one monitor; its owner `RUNNABLE` in socket I/O or a DB call | I/O under a lock (convoy) |
| All workers `WAITING` in `FutureTask.get`, queue non-empty | Thread-starvation deadlock |
| Threads `RUNNABLE` in `<clinit>` of mutually dependent classes | Class-init deadlock (not reported as a deadlock) |
| commonPool workers in I/O frames | Blocking in the common pool |
| Thousands of threads named `pool-N-thread-M` | Executor created per request (thread leak) |
| Carriers in `synchronized` or native frames, VTs waiting | VT pinning |
| One thread `RUNNABLE` at high CPU in a loop over a plain field | Visibility bug or busy-spin |

---

## 3. Always-on signals: metrics and alerts

| Signal | Source | Alert / meaning |
|---|---|---|
| Executor active, queue depth, rejections | Micrometer `ExecutorServiceMetrics` (`executor.active`, `executor.queued`, `executor.completed`, `executor.pool.size`) plus your own rejection counter | Queue depth trending up; any rejections |
| Task wait time (enqueue → start) | Timer around task wrappers | p99 > SLO budget |
| Live and peak thread counts | `jvm.threads.live`, `jvm.threads.peak`, `jvm.threads.states{state=blocked}` | Growth means a thread leak; sustained BLOCKED means contention |
| Lock contention | JFR `jdk.JavaMonitorEnter` (> 20 ms), `jdk.ThreadPark`; async-profiler `-e lock` | Top contended monitors |
| VT pinning | JFR `jdk.VirtualThreadPinned` count and rate | Any sustained rate |
| VT submit failures | JFR `jdk.VirtualThreadSubmitFailed` | Any occurrence (scheduler saturation or OOM) |
| Deadlock check | A health check calling `ThreadMXBean.findDeadlockedThreads()` every minute | Non-null result: page and restart |
| Semaphore and bulkhead saturation | `availablePermits`, wait-time histograms | Near zero permits for a long time |
| Interrupt-driven shutdown duration | Logs at `awaitTermination` | Longer than the grace period |

---

## 4. Concurrency code-review checklist

- [ ] Every field shared between threads has an HB story (final, volatile, lock, atomic, concurrent collection).
- [ ] No check-then-act on shared state outside a lock or atomic API.
- [ ] Locks: acquired in a global order; `unlock()` in `finally`; no I/O or alien calls while held; non-fair unless proven otherwise.
- [ ] `wait()` in `while` loops; `notifyAll` (or separate `Condition`s).
- [ ] Executors: explicitly constructed, bounded queues, named threads, a rejection policy, metrics, shutdown on application stop.
- [ ] No blocking on futures of the same bounded pool; no blocking in `commonPool`/parallel streams.
- [ ] Periodic tasks catch `Throwable`; `submit()` futures are consumed or logged.
- [ ] `InterruptedException` is propagated or the flag restored; long loops check interruption.
- [ ] `ThreadLocal`s removed in `finally`; context propagated explicitly across async boundaries (or `ScopedValue`).
- [ ] Virtual threads: JDK 24+; concurrency limits per resource; CPU work isolated; no pooling; no per-thread caches.
- [ ] `CompletableFuture` stages have executors chosen deliberately and error handlers attached.
- [ ] Counters under contention use `LongAdder`; exact decisions use `AtomicLong`/`Semaphore`.
- [ ] Concurrency tests exist (stress tests; jcstress for low-level code; run on ARM if you deploy on ARM).
