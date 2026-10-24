# 8.1 · JVM Profiling & Forensics — JFR (Custom Events, Streaming, `jfr view`), async-profiler, jcmd, Thread Dumps

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** JDK 25 `jdk.jfr` API docs; JEP 328 (Flight Recorder), JEP 349 (JFR Event Streaming), JEP 491 (synchronize virtual threads without pinning); `jfr` and `jcmd` tool documentation (JDK 25); async-profiler README; Brendan Gregg, *Flame Graphs*.
> **Verified stack:** Temurin JDK **25.0.4.1**, Windows x64. Everything below ran in-process or against the running JVM with the JDK's own `jfr` and `jcmd` binaries. async-profiler doesn't support Windows, so its section is commands only. This file builds on the triage runbook and always-on flags of [1.6](../01-JVM-Internals/06-Production-Failure-Modes-Diagnostics.md#3-first-five-minutes--runbook), and goes deeper into the tools.

---

## 1. Which tool answers which question 🔥

| Question | Tool | Overhead / safety |
|---|---|---|
| "What was the JVM doing during the incident?" | **JFR** always-on recording, dumped after the fact (`jcmd <pid> JFR.dump`) | ~1% with `default`, ~2% with `profile` settings; production-safe |
| "Where is CPU going?" | JFR `jdk.ExecutionSample` / `jfr view hot-methods`; **async-profiler** `-e cpu` (flame graph) | Low; sampling |
| "Where are we allocating?" | JFR `jdk.ObjectAllocationSample` (`allocation-by-site`); async-profiler `-e alloc` | Low; throttled sampling |
| "Why is latency high with idle CPU?" | Thread dumps; JFR `jdk.JavaMonitorEnter`, `jdk.ThreadPark`, socket/file I/O events; async-profiler `-e wall` | Thread dumps: a brief safepoint |
| "Is it a deadlock?" | `jcmd Thread.print` (detects it), `ThreadMXBean.findDeadlockedThreads` | Safe |
| "Is a virtual thread pinned?" | JFR `jdk.VirtualThreadPinned`; `jfr view pinned-threads` | Safe |
| "What's in the heap?" | `GC.class_histogram`, heap dump + Eclipse MAT | Full GC / long pause: last resort |
| "Native memory growth?" | NMT (`-XX:NativeMemoryTracking=summary` + `VM.native_memory`) | Small, enabled at startup |
| Business-level timings inside the JVM | **Custom JFR events** + `RecordingStream` | Near zero when disabled |

**JFR internals in one paragraph:** events are written to **thread-local buffers** (no locks on the hot path), which are promoted to global buffers and flushed to **chunks** in a disk **repository**. Event types are periodic (CPU load, GC configuration), threshold-based (I/O, locks: only events longer than the threshold are recorded), or sampling (execution, allocation). Settings files (`default.jfc`, `profile.jfc`) choose thresholds, periods and stack-trace capture. A custom event that is disabled costs a field check; `begin()/commit()` record start, duration, thread and stack.

---

## 2. JFR from code: custom events, a programmatic recording, streaming, and the `jfr` CLI 🔥

### 2.1 Runnable: what a 3-second recording tells you about this JVM

<!-- run: javac timeout=300 -->
```java
package demo.jfr;

import java.nio.file.*;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Collectors;
import jdk.jfr.*;
import jdk.jfr.consumer.*;

public class JfrDeepDive {
    @Name("demo.OrderProcessed") @Label("Order Processed") @Category({"Demo", "Orders"})
    @Description("One order through the pricing pipeline")
    static class OrderProcessed extends Event {
        @Label("Order id") String orderId;
        @Label("Amount") @DataAmount long amountCents;           // unit metadata shows up in JMC and `jfr print`
        @Label("Items") int items;
    }

    static final Object LOCK = new Object();
    static volatile Object sink;

    public static void main(String[] args) throws Exception {
        Path file = Files.createTempFile("demo", ".jfr");
        AtomicInteger slowAlerts = new AtomicInteger(), streamed = new AtomicInteger();

        try (Recording recording = new Recording(Configuration.getConfiguration("profile"));
             RecordingStream live = new RecordingStream()) {
            recording.enable("demo.OrderProcessed");
            recording.enable("jdk.JavaMonitorEnter").withThreshold(Duration.ofMillis(1));
            recording.enable("jdk.VirtualThreadPinned").withThreshold(Duration.ZERO);
            recording.start();

            live.enable("demo.OrderProcessed");                       // in-process, continuous monitoring
            live.onEvent("demo.OrderProcessed", e -> { streamed.incrementAndGet(); if (e.getDuration().toMillis() >= 5) slowAlerts.incrementAndGet(); });
            live.startAsync();

            for (int i = 0; i < 2_000; i++) processOrder(i);          // custom events (every 100th is slow)
            allocate();                                                // allocation pressure
            contend();                                                 // monitor contention between 4 threads
            pinCheck();                                                // virtual threads blocking inside synchronized

            long deadline = System.nanoTime() + 10_000_000_000L;        // the stream delivers in ~1 s flushes
            while (streamed.get() < 2_000 && System.nanoTime() < deadline) Thread.sleep(100);
            recording.stop();
            recording.dump(file);
        }

        List<RecordedEvent> events = RecordingFile.readAllEvents(file);
        Map<String, Long> counts = events.stream().collect(Collectors.groupingBy(e -> e.getEventType().getName(), TreeMap::new, Collectors.counting()));
        System.out.println("recording: " + Files.size(file) / 1024 + " KB, " + events.size() + " events, " + counts.size() + " event types");
        for (String type : List.of("demo.OrderProcessed", "jdk.ObjectAllocationSample", "jdk.JavaMonitorEnter", "jdk.VirtualThreadPinned", "jdk.ExecutionSample", "jdk.GarbageCollection"))
            System.out.printf("  %-28s %,6d%n", type, counts.getOrDefault(type, 0L));

        List<RecordedEvent> orders = events.stream().filter(e -> e.getEventType().getName().equals("demo.OrderProcessed")).toList();
        System.out.println("orders: slowest " + orders.stream().map(RecordedEvent::getDuration).max(Comparator.naturalOrder()).orElseThrow().toMillis()
            + " ms; >= 5 ms: " + orders.stream().filter(e -> e.getDuration().toMillis() >= 5).count() + "; RecordingStream saw " + streamed.get() + " events, alerts: " + slowAlerts.get());

        Map<String, Long> allocBySite = new TreeMap<>();               // "where is garbage coming from?"
        events.stream().filter(e -> e.getEventType().getName().equals("jdk.ObjectAllocationSample")).forEach(e ->
            allocBySite.merge(topFrame(e), e.getLong("weight"), Long::sum));
        System.out.println("top allocation site: " + allocBySite.entrySet().stream().max(Map.Entry.comparingByValue()).orElseThrow().getKey());

        List<RecordedEvent> waits = events.stream().filter(e -> e.getEventType().getName().equals("jdk.JavaMonitorEnter")
            && topFrame(e).startsWith("JfrDeepDive")).toList();                 // ignore JFR's own internal locks
        System.out.println("contention on LOCK at " + (waits.isEmpty() ? "-" : topFrame(waits.getFirst())) + ": " + waits.size()
            + " blocked acquisitions, waits (ms) " + waits.stream().map(e -> e.getDuration().toMillis()).sorted().toList());

        Path jfr = Path.of(System.getProperty("java.home"), "bin", "jfr");
        Process p = new ProcessBuilder(jfr.toString(), "view", "--width", "100", "allocation-by-site", file.toString()).redirectErrorStream(true).start();
        List<String> view = new String(p.getInputStream().readAllBytes()).lines().filter(l -> !l.isBlank()).limit(6).toList();
        p.waitFor();
        System.out.println("jfr view allocation-by-site (first lines):");
        view.forEach(l -> System.out.println("  " + l));
        Files.delete(file);
    }

    static void processOrder(int i) throws InterruptedException {
        OrderProcessed event = new OrderProcessed();
        event.begin();
        if (i % 100 == 0) Thread.sleep(6);                             // simulated slow path
        event.orderId = "A-" + i; event.amountCents = 1999L * (i % 7 + 1); event.items = i % 7 + 1;
        event.commit();                                                // records duration, thread and stack trace
    }

    static void allocate() {
        for (int i = 0; i < 200_000; i++) sink = new byte[1024];
    }

    static void contend() throws Exception {
        try (var pool = Executors.newFixedThreadPool(4)) {
            for (int t = 0; t < 4; t++) pool.submit(() -> {
                for (int i = 0; i < 20; i++) synchronized (LOCK) { sleepQuietly(3); }
            });
        }
    }

    static void pinCheck() throws Exception {
        try (var vts = Executors.newVirtualThreadPerTaskExecutor()) {
            for (int t = 0; t < 4; t++) vts.submit(() -> { synchronized (new Object()) { sleepQuietly(20); } });
        }
    }

    static String topFrame(RecordedEvent e) {
        RecordedStackTrace st = e.getStackTrace();
        if (st == null || st.getFrames().isEmpty()) return "?";
        RecordedFrame f = st.getFrames().stream().filter(fr -> fr.getMethod().getType().getName().startsWith("demo.")).findFirst().orElse(st.getFrames().getFirst());
        return f.getMethod().getType().getName().replace("demo.jfr.", "") + "." + f.getMethod().getName() + ":" + f.getLineNumber();
    }
    static void sleepQuietly(long ms) { try { Thread.sleep(ms); } catch (InterruptedException e) { Thread.currentThread().interrupt(); } }
}
```

One measured run (event counts other than the 2,000 custom events vary run to run):

```
recording: 543 KB, 7995 events, 83 event types
  demo.OrderProcessed           2,000
  jdk.ObjectAllocationSample       70
  jdk.JavaMonitorEnter              4
  jdk.VirtualThreadPinned           0
  jdk.ExecutionSample               8
  jdk.GarbageCollection             2
orders: slowest 8 ms; >= 5 ms: 20; RecordingStream saw 2000 events, alerts: 20
top allocation site: JfrDeepDive.allocate:88
contention on LOCK at JfrDeepDive.lambda$contend$0:94: 3 blocked acquisitions, waits (ms) [74, 147, 218]
jfr view allocation-by-site (first lines):
                                           Allocation by Site
  Method                                                                          Allocation Pressure
  ------------------------------------------------------------------------------- -------------------
  demo.jfr.JfrDeepDive.allocate()                                                              64.81%
  jdk.internal.classfile.impl.BufWriterImpl.<init>(...)                                        22.33%
  java.util.ArrayList.grow(int)                                                                 3.19%
```

What the recording reveals:

* **Custom events are first-class.** 2,000 `demo.OrderProcessed` events carried business fields (order ID, amount with `@DataAmount` unit metadata), a duration, the thread and a stack trace, with no logging framework involved. The slow path (≥ 5 ms) shows up as duration outliers you can query.
* **`RecordingStream` (JEP 349) turns JFR into an in-process metrics source.** The stream saw all 2,000 events and raised 20 "slow order" alerts. Typical uses: export GC pauses, lock waits or custom events to Micrometer, or trigger a dump on SLA breach. Events arrive in ~1 s flushes, so it's near-real-time, not synchronous.
* **Allocation by site** pointed straight at `allocate()` (also visible in `jfr view allocation-by-site`). JFR's own allocations (class-file generation for event classes) appear too, so filter by your packages.
* **Monitor contention showed `synchronized` barging:** 4 threads × 20 critical sections produced only **3 contended acquisitions**, with waits of ~70/145/215 ms. The releasing thread re-acquired the lock repeatedly while the others stayed blocked: monitors are **not fair**. Throughput looks fine while tail latency suffers. `jdk.JavaMonitorEnter` shows it; a profiler that samples only CPU does not.
* **`jdk.VirtualThreadPinned` = 0** while virtual threads blocked inside `synchronized`: since JDK 24 (JEP 491) monitors no longer pin carriers. Pinning still occurs for native frames and some class-initialization paths. Keep this event enabled.
* `jfr view <view> file.jfr` (JDK 21+) renders tables straight from a recording: `hot-methods`, `gc`, `gc-pauses`, `allocation-by-site`, `contention-by-site`, `pinned-threads`, `thread-allocation`, `latencies-by-type`, and on JDK 25 also `cpu-time-hot-methods` (CPU-time sampling, JEP 509, Linux) and `method-timing`/`method-calls` (method timing and tracing, JEP 520). `jfr help view` lists all of them (verified on 25.0.4.1). Also useful: `jfr summary`, `jfr print --events jdk.GarbageCollection`, and `jfr scrub` to remove sensitive events before sharing.

**Production JFR setup** (in addition to [1.6 §4](../01-JVM-Internals/06-Production-Failure-Modes-Diagnostics.md#4-always-on-configuration-that-makes-incidents-diagnosable)): ship custom events for business latencies; on SLA breach, dump the always-on recording (`jcmd <pid> JFR.dump name=1 filename=…`) or let `RecordingStream` trigger it; keep `maxage`/`maxsize` bounded; centralise `.jfr` files from canaries.

---

## 3. async-profiler (Linux/macOS) ⚡

A sampling profiler that combines `perf_events` (kernel stacks, hardware counters) with `AsyncGetCallTrace`. It has no safepoint bias and sees native and JIT frames. It is **not available on Windows**, so these commands come from its documentation and weren't run here:

```bash
asprof -d 30 -e cpu   -f cpu.html   <pid>      # CPU flame graph (on-CPU only)
asprof -d 30 -e wall  -t -f wall.html <pid>    # wall-clock per thread: finds I/O and lock waits
asprof -d 30 -e alloc -f alloc.html <pid>      # allocation flame graph (TLAB-driven sampling)
asprof -d 30 -e lock  -f lock.html  <pid>      # contended locks
asprof -d 30 -e cpu   -f profile.jfr <pid>     # JFR output: open in JMC or convert later
java -agentpath:/opt/async-profiler/lib/libasyncProfiler.so=start,event=cpu,file=startup.html …   # profile startup
```

* **Reading a flame graph:** x-axis = share of samples (not time order), y-axis = stack depth. Look for **wide plateaus** (functions on CPU themselves) and wide frames with narrow children (time spent calling into something), and compare before/after graphs.
* **Containers:** `perf_event_paranoid` and seccomp may block `perf_events`. Fall back to `-e itimer`, or run with the needed capabilities.
* **Safepoint bias:** JFR `ExecutionSample` and classic JVMTI profilers sample only at safepoints or on Java frames. async-profiler and JFR's newer CPU-time sampling (`jdk.CPUTimeSample`, Linux) avoid that.

---

## 4. Thread dumps: deadlocks, states, virtual threads 🔥

### 4.1 Runnable: a deadlock, a parked worker and an idle consumer, seen three ways

<!-- run: javac timeout=120 -->
```java
package demo.dumps;

import java.lang.management.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.locks.ReentrantLock;

public class ThreadDumpForensics {
    static final Object ACCOUNTS = new Object(), LEDGER = new Object();
    static final ReentrantLock POOL_LOCK = new ReentrantLock();

    public static void main(String[] args) throws Exception {
        CountDownLatch bothHoldFirst = new CountDownLatch(2);
        start("transfer-1", () -> { synchronized (ACCOUNTS) { await(bothHoldFirst); synchronized (LEDGER) { } } });
        start("transfer-2", () -> { synchronized (LEDGER) { await(bothHoldFirst); synchronized (ACCOUNTS) { } } });
        POOL_LOCK.lock();                                                     // main holds a j.u.c. lock …
        start("worker-waiting-for-lock", POOL_LOCK::lock);                   // … so this one parks
        start("idle-consumer", () -> { try { new LinkedBlockingQueue<>().take(); } catch (InterruptedException e) { } });
        Thread.ofVirtual().name("virtual-sleeper").start(() -> sleep(60_000));
        Thread.sleep(500);

        ThreadMXBean mx = ManagementFactory.getThreadMXBean();
        long[] deadlocked = mx.findDeadlockedThreads();                      // monitors AND ownable synchronizers
        System.out.println("findDeadlockedThreads: " + Arrays.stream(mx.getThreadInfo(deadlocked)).map(ThreadInfo::getThreadName).sorted().toList());
        for (ThreadInfo ti : mx.dumpAllThreads(true, true)) {
            if (!Set.of("transfer-1", "transfer-2", "worker-waiting-for-lock", "idle-consumer").contains(ti.getThreadName())) continue;
            System.out.printf("%-24s %-13s waiting on %-45s owned by %s%n", ti.getThreadName(), ti.getThreadState(),
                String.valueOf(ti.getLockName()).replaceAll("@[0-9a-f]+", "@…"), ti.getLockOwnerName());
        }
        System.out.println("virtual threads in ThreadMXBean.dumpAllThreads: "
            + Arrays.stream(mx.dumpAllThreads(false, false)).anyMatch(t -> t.getThreadName().equals("virtual-sleeper")));

        long pid = ProcessHandle.current().pid();                             // what an operator would run
        Path jcmd = Path.of(System.getProperty("java.home"), "bin", "jcmd");
        Process p = new ProcessBuilder(jcmd.toString(), String.valueOf(pid), "Thread.print").redirectErrorStream(true).start();
        List<String> lines = new String(p.getInputStream().readAllBytes()).lines().toList();
        p.waitFor();
        int start = lines.indexOf(lines.stream().filter(l -> l.startsWith("Found one Java-level deadlock")).findFirst().orElse(""));
        System.out.println("jcmd Thread.print → deadlock section:");
        lines.subList(start, start + 9).forEach(l -> System.out.println("  " + l.replaceAll("0x[0-9a-f]+", "0x…")));

        Path json = Files.createTempFile("threads", ".json");
        Files.delete(json);
        new ProcessBuilder(jcmd.toString(), String.valueOf(pid), "Thread.dump_to_file", "-format=json", json.toString()).start().waitFor();
        System.out.println("Thread.dump_to_file -format=json includes the virtual thread: " + Files.readString(json).contains("virtual-sleeper"));
        Files.delete(json);
        System.exit(0);                                                       // the deadlocked threads can never finish
    }

    static void start(String name, Runnable r) { Thread t = new Thread(r, name); t.setDaemon(true); t.start(); }
    static void await(CountDownLatch l) { l.countDown(); try { l.await(); } catch (InterruptedException e) { } }
    static void sleep(long ms) { try { Thread.sleep(ms); } catch (InterruptedException e) { } }
}
```

Output (verified):

```
findDeadlockedThreads: [transfer-1, transfer-2]
transfer-1               BLOCKED       waiting on java.lang.Object@…                            owned by transfer-2
transfer-2               BLOCKED       waiting on java.lang.Object@…                            owned by transfer-1
worker-waiting-for-lock  WAITING       waiting on java.util.concurrent.locks.ReentrantLock$NonfairSync@… owned by main
idle-consumer            WAITING       waiting on java.util.concurrent.locks.AbstractQueuedSynchronizer$ConditionObject@… owned by null
virtual threads in ThreadMXBean.dumpAllThreads: false
jcmd Thread.print → deadlock section:
  Found one Java-level deadlock:
  =============================
  "transfer-1":
    waiting to lock monitor 0x… (object 0x…, a java.lang.Object),
    which is held by "transfer-2"

  "transfer-2":
    waiting to lock monitor 0x… (object 0x…, a java.lang.Object),
    which is held by "transfer-1"
Thread.dump_to_file -format=json includes the virtual thread: true
```

* **Deadlock detection works for monitors and `java.util.concurrent` locks:** `findDeadlockedThreads()` returned the two transfer threads, and `jcmd Thread.print` printed the classic *"Found one Java-level deadlock"* section with who holds what. Fix such cycles by ordering lock acquisition ([5.4 §3.2](../05-Persistence-JPA-Hibernate/04-Transactions-Isolation-Locking-Spring-Transactional.md#32-runnable-lock-sql-nowait-skip-locked-a-deadlock-and-optimistic-locking) is the database equivalent).
* **States tell you the kind of wait:**

| State in the dump | Typically means | Example above |
|---|---|---|
| `BLOCKED` (waiting to lock a monitor) | `synchronized` contention | `transfer-1/2` |
| `WAITING` / `TIMED_WAITING` on an AQS object (parking) | `ReentrantLock`, semaphore, `CountDownLatch`, or a pool waiting for a connection | `worker-waiting-for-lock` (owner `main`), a Hikari wait ([5.5 §2.1](../05-Persistence-JPA-Hibernate/05-Production-Failure-Modes-Diagnostics.md#21-what-a-pool-starved-thread-looks-like-verified)) |
| `WAITING` on a `ConditionObject`, owner `null` | An idle consumer, `queue.take()` | `idle-consumer` (normal, not a problem) |
| `RUNNABLE` in `socketRead`/`NioSocketImpl.read` | **Waiting for the network**: RUNNABLE ≠ using CPU | JDBC or HTTP calls without timeouts |

* **Virtual threads are absent from `ThreadMXBean.dumpAllThreads` and `jstack`-style dumps.** Use `jcmd <pid> Thread.dump_to_file -format=json <file>` (verified to contain the virtual thread). With millions of virtual threads, group by stack in the JSON rather than reading it.
* **Method:** take 3 dumps 5–10 s apart. Threads stuck on the same frame across dumps are the bottleneck; many threads in the same frame point at a shared resource (a pool or a lock). Map hot OS threads to `nid` via `top -H` ([1.6 §3](../01-JVM-Internals/06-Production-Failure-Modes-Diagnostics.md#3-first-five-minutes--runbook)).

---

## 5. Production failure modes & diagnostics

| Symptom | Look at | Typical finding |
|---|---|---|
| p99 latency spikes, CPU fine | JFR `contention-by-site`, `jdk.ThreadPark`, thread dumps | One hot `synchronized` (barging), a pool wait, a `RUNNABLE` socket read without timeout |
| CPU high, no obvious cause | `hot-methods`, async-profiler CPU flame graph | Regex/JSON in a loop, logging at debug in a hot path, spin loops, GC (check the `gc` view first) |
| GC churn | `allocation-by-site`, `thread-allocation` | Per-request large buffers, boxing, `String` concatenation in logs |
| Virtual-thread app stalls | `pinned-threads`, JSON thread dump | Native frames pinning carriers, carrier pool exhausted by CPU work |
| "Hung" JVM | `jcmd Thread.print` (deadlock section), 3 dumps | Lock-order deadlock; all workers waiting on one downstream |
| Can't reproduce locally | The always-on JFR recording dumped at incident time | Evidence instead of guesses: the reason to keep JFR on in production |

---

## 6. Interview Q&A

<details><summary><b>Q1. 🔥 Why is JFR suitable for always-on production profiling?</b></summary>

Events are written to thread-local buffers without locks, many event types are thresholded or sampled, and the default settings target about 1% overhead. Recordings live in a bounded on-disk repository (`maxage`/`maxsize`) and can be dumped on demand with `jcmd`, so evidence of the incident already exists when you arrive.
</details>

<details><summary><b>Q2. ⚡ How do you add business-level timing to JFR, and consume it live?</b></summary>

Define a subclass of `jdk.jfr.Event` with `@Name`, `@Label` and typed fields, then call `begin()` and `commit()` around the operation (duration, thread and stack are captured). Consume it from a recording file (`RecordingFile`), with `jfr print`/`view`, or live in-process with `RecordingStream.onEvent(…)` (JEP 349), e.g. to alert or export to Micrometer. Verified: 2,000 events streamed and 20 slow-path alerts raised.
</details>

<details><summary><b>Q3. ⚡ A thread dump shows most threads `RUNNABLE` in `socketRead0`. Is the CPU busy?</b></summary>

No. `RUNNABLE` only means "not blocked on a Java monitor or park"; threads in a blocking socket read are waiting for the network. Correlate with CPU usage and look for missing read timeouts or a slow downstream. Use wall-clock profiling (`asprof -e wall`) or JFR socket-read events to quantify the waiting.
</details>

<details><summary><b>Q4. 🧊 Why did 4 threads competing for a `synchronized` lock produce only 3 contention events?</b></summary>

Monitors are unfair: the releasing thread can re-acquire immediately (barging) while waiters stay blocked. Each waiter blocked once, for a long time (measured ~70/145/215 ms), instead of many short waits. Throughput looks fine, but tail latency is terrible. Use `ReentrantLock(true)` if fairness matters, reduce the critical section, or redesign to avoid the shared lock.
</details>

<details><summary><b>Q5. ⚡ How do you get a thread dump that includes virtual threads?</b></summary>

`jcmd <pid> Thread.dump_to_file -format=json <file>` (or `-format=text`). `ThreadMXBean.dumpAllThreads` and classic `jstack` output list only platform threads (verified: the virtual thread was missing from the MXBean but present in the JSON).
</details>
