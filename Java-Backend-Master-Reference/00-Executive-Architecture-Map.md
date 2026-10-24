# 00 · Executive Architecture Map — How JDK 21 → 25 (→ 27) Changed Backend Engineering

> **Scope of this run:** Pillars 1–4 (JVM internals, Core Java, Concurrency/Loom, I/O–NIO–Serialization). Pillars 5–8 (persistence, Spring/microservices, AI engineering, observability/security/testing) arrive in run 2, and this map already shows where they plug in.
>
> **Baseline:** Java 21 LTS and **Java 25 LTS** (GA 2025-09-16). Where a later release changed something you will run into, it is called out: **JDK 26** (GA 2026-03-17) and **JDK 27** (GA 2026-09-15). Every runnable sample was executed on Temurin `25.0.4.1+1-LTS`.

---

## 0. The one-paragraph synthesis

From roughly 2014 to 2021 the JVM backend's defining constraint was **expensive threads**. A platform thread is a 1:1 OS thread with roughly 1 MB of reserved stack, kernel scheduling and context-switch cost, which in practice caps a service at a few thousand in-flight blocking operations. The industry worked around that cap with **asynchronous, callback- or reactive-style code** (CompletableFuture chains, Reactor/RxJava, Netty pipelines). The workarounds paid off in throughput, but at a steep cost in debuggability, stack traces, `ThreadLocal`-based context (MDC, security, transactions) and developer cognition. **JDK 21 removed the constraint** with virtual threads. JDK 24 removed their biggest sharp edge, `synchronized` pinning (JEP 491). Structured concurrency (still in preview in JDK 27) and scoped values (final in JDK 25) give the model correct lifetimes and context propagation. In parallel, the memory side moved from "tune G1 pause targets" to "**pauses are a solved problem if you can afford the CPU and memory headroom**": Generational ZGC (JEP 439) has been ZGC's only mode since JDK 24, with sub-millisecond pauses that do not grow with heap size. Compact object headers (JEP 519, product in 25, **default in 27** via JEP 534) cut every object header from 12 to 8 bytes. **Project Leyden** (JEPs 483/514/515/516) gives startup and warm-up wins without leaving the JIT world, which narrows the gap that GraalVM Native Image used to own. The language itself moved toward **data-oriented programming** (records + sealed types + exhaustive pattern matching). The platform moved toward **integrity by default**: strong encapsulation, the `Unsafe` memory-access deprecation, JNI restrictions, "final means final", and the FFM API as the sanctioned way off-heap and into native code.

---

## 1. The six paradigm shifts (with the architect's "so what")

| # | Shift | Key JEPs (release) | What it obsoletes | Architect's consequence |
|---|---|---|---|---|
| 1 | **Cheap blocking**: thread-per-request is viable again | 444 (21), 491 (24), 505/525/533 (preview 25/26/27), 506 (25) | Reactive *purely for scalability*; hand-tuned I/O thread pools; most `CompletableFuture` plumbing | Bottleneck moves **downstream** (DB pools, rate limits). Concurrency limits move from *thread pools* to *semaphores/bulkheads*. |
| 2 | **Pause-less GC as a commodity** | 439 (21), 474 (23), 490 (24), 404/521 (24/25), 522 (26), 523 (27) | Heap-size-driven pause anxiety, CMS-era tuning folklore | GC choice is now a **CPU/memory-headroom vs tail-latency** trade, not a pause-tuning exercise. |
| 3 | **Denser objects** | 450 (24 exp), 519 (25), 534 (27 default) | "Every object costs ≥16 B" | 10–20% smaller live sets on object-heavy heaps, and better cache density. Verify per workload. |
| 4 | **Startup without leaving the JIT** | 483 (24), 514/515 (25), 516 (26) | Some Native Image adoption that was purely for startup | AOT cache = training run + cached loaded/linked classes + profiles (+ objects in 26). Keep full JIT peak performance. |
| 5 | **Data-oriented programming** | 395 (16), 409 (17), 440/441 (21), 456 (22), 507→532 (preview) | Visitor pattern, `instanceof` ladders, Lombok-for-DTOs | Model domains as **closed sums of immutable products**. The compiler enforces exhaustiveness. |
| 6 | **Integrity by default + sanctioned native access** | 403 (17), 451 (21), 454 (22), 471/498 (23/24), 472 (24), 486 (24), 500 (26) | `sun.misc.Unsafe`, deep reflection hacks, JNI glue, Security Manager | Upgrades now break **libraries** that cheat. Budget for `--add-opens`/`--enable-native-access` audits, and prefer libraries that use FFM and VarHandles. |

---

## 2. Release timeline of what matters to a backend architect

```
JDK 8  (2014) lambdas/streams, Metaspace replaces PermGen, CompletableFuture, java.time
JDK 9  (2017) JPMS, G1 default, compact strings, indy string concat, VarHandles, unified logging
JDK 11 (2018) LTS · HttpClient, ZGC (exp), Epsilon, JFR open-sourced, TLS 1.3
JDK 14–16     records, pattern-matching instanceof, helpful NPEs, ZGC/Shenandoah production (15), elastic Metaspace
JDK 17 (2021) LTS · sealed classes, strong encapsulation (no --illegal-access), Graal AOT/JIT removed from OpenJDK
JDK 18        biased locking removed, core reflection on method handles, finalization deprecated
JDK 21 (2023) LTS · virtual threads, generational ZGC, record patterns, switch patterns, sequenced collections
JDK 22        FFM API final, unnamed variables `_`, G1 region pinning, multi-file source launcher
JDK 23        ZGC generational by default, Unsafe memory methods deprecated, lightweight locking default
JDK 24        synchronized no longer pins VTs, stream gatherers, Class-File API, AOT class loading/linking,
              Security Manager permanently disabled, non-generational ZGC removed, compact headers (exp)
JDK 25 (2025) LTS · scoped values final, compact object headers (product, opt-in), generational Shenandoah,
              AOT ergonomics + method profiling, JFR CPU-time profiling (exp), module imports,
              compact source files, flexible constructor bodies; structured concurrency 5th preview
JDK 26 (2026) HTTP/3 client, AOT object caching with any GC, G1 throughput (fewer barriers syncs),
              "final means final" warnings, Applet API removed; SC 6th preview, lazy constants 2nd preview
JDK 27 (2026) G1 default in *all* environments, compact object headers BY DEFAULT, PQ hybrid TLS 1.3
              key exchange, JFR in-process redaction; SC 7th preview, primitive patterns 5th preview
```

> **Practical upgrade guidance (Oct 2026):** Production estates should be on **25 LTS**. Treat 26/27 as preview lanes for G1/ZGC/Leyden improvements. Two 27 changes are worth testing *now*, because they change defaults rather than adding APIs: **JEP 534** (compact headers on by default) and **JEP 523** (G1 even on 1-CPU or small-memory containers, where earlier JDKs silently picked Serial GC).

---

## 3. Paradigm 1 — Virtual threads vs reactive: the decision, quantified

### 3.1 The math that drives everything: Little's Law

```
in-flight requests (L) = arrival rate (λ) × time in system (W)

Example: 5,000 req/s × 200 ms average latency (mostly waiting on DB/HTTP) = 1,000 concurrent requests
```

| Model | What holds a request while it waits | Cost per waiting request | Practical ceiling per JVM |
|---|---|---|---|
| Platform thread-per-request | 1 OS thread (stack reserved ~1 MB; kernel task struct) | ~1 MB virtual / tens–hundreds of KB committed, plus context switches | ~1–5k threads before scheduler and memory overhead dominate |
| Reactive (Netty event loop + Reactor) | A heap object graph of callbacks/operators | ~hundreds of bytes – few KB | 100k+ |
| **Virtual thread-per-request** | A heap-allocated continuation (stack chunk) while parked | ~hundreds of bytes – few KB (grows with stack depth) | 100k–1M+ |

Virtual threads give **reactive-class concurrency with blocking-style code**. They do **not** make CPU-bound code faster. They have **no time-slicing preemption**, so a virtual thread holding a carrier in a hot loop starves others. They also do **not** make downstream resources infinite: 10,000 virtual threads hitting a 20-connection Hikari pool means 9,980 threads queued on the pool.

### 3.2 Decision table

| Criterion | Platform threads + pools | **Virtual threads (MVC + JDBC)** | Reactive (WebFlux + R2DBC/Netty) |
|---|---|---|---|
| Programming model | Imperative | Imperative | Functional/declarative operators |
| Debuggability / stack traces | Excellent | Excellent (VT stacks in JFR and JSON thread dumps) | Poor without Reactor debug agent / checkpoints |
| `ThreadLocal`/MDC/Tx context | Works | Works, but costly at 1M threads; prefer `ScopedValue` | Needs Reactor `Context` + context-propagation bridges |
| Throughput for I/O-bound | Limited by pool size | High | High |
| Tail latency under overload | Queueing in pool | Queueing on semaphores/pools; needs explicit limits | Backpressure-aware |
| **Backpressure / streaming** | Manual | Manual (bounded queues, semaphores) | **First-class (Reactive Streams `request(n)`)** |
| CPU-bound work | Fine | No benefit; use bounded platform pools | No benefit |
| Ecosystem maturity (2026) | Universal | Universal for blocking libraries; JDBC drivers moved off `synchronized` | Narrower (R2DBC, reactive drivers) |
| Failure mode to watch | Pool exhaustion | Pinning (native/`<clinit>`), unbounded fan-out into downstream | Blocking call on event loop, lost context, operator-chain complexity |

**Rule of thumb (2026):** default to **Spring MVC on virtual threads**. Choose reactive when the problem *is a stream* (backpressured fan-in/fan-out, server push to many long-lived connections with protocol-level flow control), or when the codebase is already reactive and healthy. Never pick reactive only "for scalability" for request/response workloads. See [03-Concurrency-Loom/06](03-Concurrency-Loom/06-Virtual-Threads-Structured-Concurrency-Scoped-Values.md).

### 3.3 The same fan-out three ways (runnable)

The service calls two "remote" dependencies, each taking about 300 ms. With platform-thread blocking the calls would run serially (~600 ms). With `CompletableFuture` you get parallelism but callback plumbing. With virtual threads plus structured concurrency you get parallelism with sequential-looking code and well-defined cancellation.

<!-- run: jvm="-Xmx128m" -->
```java
import java.time.Duration;
import java.time.Instant;
import java.util.concurrent.*;

public class FanOutThreeWays {
    record Profile(String user, String tier) {}

    static String fetchUser(int id) throws InterruptedException { Thread.sleep(300); return "user-" + id; }
    static String fetchTier(int id) throws InterruptedException { Thread.sleep(300); return id % 2 == 0 ? "GOLD" : "SILVER"; }

    // 1) Sequential blocking — simple but latency = sum of calls
    static Profile sequential(int id) throws InterruptedException {
        return new Profile(fetchUser(id), fetchTier(id));
    }

    // 2) CompletableFuture — parallel, but exceptions/cancellation/context are manual
    static Profile completableFuture(int id, ExecutorService ioPool) {
        var u = CompletableFuture.supplyAsync(() -> uncheck(() -> fetchUser(id)), ioPool);
        var t = CompletableFuture.supplyAsync(() -> uncheck(() -> fetchTier(id)), ioPool);
        return u.thenCombine(t, Profile::new).orTimeout(2, TimeUnit.SECONDS).join();
    }

    // 3) Virtual threads + StructuredTaskScope (JDK 25 preview API, JEP 505):
    //    parallel, sequential-looking, failure of one cancels the other, no leaked threads
    static Profile structured(int id) throws InterruptedException {
        try (var scope = StructuredTaskScope.open()) {          // default joiner: all must succeed
            var u = scope.fork(() -> fetchUser(id));
            var t = scope.fork(() -> fetchTier(id));
            scope.join();                                       // throws FailedException if any failed
            return new Profile(u.get(), t.get());
        }
    }

    public static void main(String[] args) throws Exception {
        time("sequential", () -> sequential(1));
        try (var ioPool = Executors.newVirtualThreadPerTaskExecutor()) {
            time("completableFuture", () -> completableFuture(2, ioPool));
        }
        time("structured", () -> structured(3));
    }

    interface Call<T> { T call() throws Exception; }
    static <T> T uncheck(Call<T> c) { try { return c.call(); } catch (Exception e) { throw new CompletionException(e); } }
    static void time(String label, Call<Profile> c) throws Exception {
        var start = Instant.now();
        var p = c.call();
        long ms = Duration.between(start, Instant.now()).toMillis();
        System.out.printf("%-18s %s  %s%n", label, p, ms < 500 ? "≈300 ms (parallel)" : "≈600 ms (serial)");
    }
}
```

Output (verified):

```
sequential         Profile[user=user-1, tier=SILVER]  ≈600 ms (serial)
completableFuture  Profile[user=user-2, tier=GOLD]  ≈300 ms (parallel)
structured         Profile[user=user-3, tier=SILVER]  ≈300 ms (parallel)
```

> The `StructuredTaskScope` API above is the **JDK 25** shape. JDK 26 renamed `Joiner.anySuccessfulResultOrThrow()` → `anySuccessfulOrThrow()`, made `allSuccessfulOrThrow()` return a `List`, and switched the config parameter to `UnaryOperator`. JDK 27 adds a third type parameter for the exception thrown by `join()` and makes the failing joiners throw `ExecutionException`. Pin your preview code to one JDK. Details are in Pillar 3, file 06.

---

## 4. Paradigm 2 — Memory management: choosing a collector in 2026

### 4.1 One-table decision

| Collector | Pauses | CPU overhead | Memory headroom needed | Compressed oops | Best for | Avoid when |
|---|---|---|---|---|---|---|
| **Serial** | Long STW (single-threaded) | Lowest | Low | Yes | Tiny containers, CLI tools, build steps | Any latency SLO with heaps > ~200 MB |
| **Parallel** | STW, multi-threaded | Low | Low | Yes | Batch/throughput (ETL, Spark executors, nightly jobs) | Interactive latency SLOs |
| **G1** (default) | Mostly 10–200 ms young/mixed evacuation pauses; target `MaxGCPauseMillis=200` | Moderate (SATB + card-marking barriers) | ~20–30% | Yes | General-purpose services, 2–64 GB heaps | p99.9 < 10 ms requirements |
| **Generational ZGC** | **< 1 ms**, independent of heap size | Higher (load + store barriers, concurrent relocation) | Headroom needed, or allocation stalls | **No** (64-bit colored pointers) | Latency-critical APIs, large heaps (tens of GB–TB) | Small, CPU-starved containers; ≤ 1–2 vCPU |
| **Shenandoah** (generational in 25) | < ~10 ms, concurrent compaction | Higher (LRB + SATB) | Moderate | Yes | Low latency with compressed oops; Red Hat / Corretto / Temurin users | Vendors that don't ship it (historically Oracle JDK builds) |
| **Epsilon** | None, never collects | None | Everything | Yes | Perf testing, ultra-short jobs | Anything long-running |

### 4.2 Why "ZGC everywhere" is wrong and "G1 everywhere" is also wrong

* ZGC trades **CPU and memory** for **pause time**. Its concurrent phases steal cycles from application threads (load/store barriers on every reference access, plus GC worker threads). It has **no compressed oops**, so every reference field and every `Object[]` slot is 8 bytes instead of 4. If the allocation rate outruns the concurrent cycle, threads hit **allocation stalls**, which are pauses in everything but name.
* G1 gives excellent throughput and footprint with compressed oops and card-marking barriers. Its weakness is that **evacuation pauses scale with live data in the collection set and with remembered-set work**. That makes a 1 ms p99.9 impossible on big heaps.
* **Decision procedure:** (1) find your *pause* budget from the SLO; (2) measure the allocation rate and the live set under production-like load; (3) if G1 meets the SLO with `MaxGCPauseMillis` at or above the observed p99.9 pause, stay on G1; (4) otherwise try ZGC with `-Xmx` ≥ 2–3× live set and verify zero `Allocation Stall` events in the JFR `jdk.ZAllocationStall` event or GC logs.

Real G1 and ZGC logs, along with how to read them, are in [01-JVM-Internals/04](01-JVM-Internals/04-Garbage-Collection-G1-ZGC-Shenandoah.md).

### 4.3 Compact object headers — the "free" 10–20%

Measured with JOL on JDK 25.0.4 (`HashMap<Integer,Integer>` with 100k entries, keys outside the Integer cache):

| Structure | Legacy headers (12 B) | `-XX:+UseCompactObjectHeaders` (8 B) | Saving |
|---|---|---|---|
| `new Object()` | 16 B | **8 B** | 50% |
| `java.lang.Long` | 24 B | **16 B** | 33% |
| `HashMap.Node` | 32 B | **24 B** | 25% |
| `HashMap<Integer,Integer>` (100k) | 5.85 MB (58.5 B/entry) | **5.05 MB (50.5 B/entry)** | 14% |
| `TreeMap<Integer,Integer>` (100k) | 5.60 MB | **4.80 MB** | 14% |
| `java.lang.Integer` | 16 B | 16 B | 0% (8 B header + 4 B value + 4 B padding) |

JDK 27 turns this on by default (JEP 534). Test JDK 25 workloads with the flag now: it touches locking (monitors move to a side table), GC forwarding and anything that cares about array base offsets (for example `Unsafe` users).

---

## 5. Paradigm 3 — Startup and footprint: JIT, Leyden AOT cache, CRaC, Native Image

| Approach | How it works | Startup | Peak throughput | Memory (RSS) | Dynamism (reflection, proxies, class loading) | Operational cost |
|---|---|---|---|---|---|---|
| Plain JIT (HotSpot) | Interpret → C1 → C2 with profiling | Slowest (seconds for Spring) | **Best** (profile-guided C2) | Highest | Full | None |
| CDS / AppCDS | Pre-parsed class metadata archive | ~10–30% faster | Best | Slightly lower (shared mapping) | Full | Low |
| **Leyden AOT cache** (24+) | Training run records loaded+linked classes (24), method profiles (25), heap objects with any GC (26) | **~40%+ faster** (JEP 483 reports up to 42% on Spring PetClinic) | Best, and warm-up is faster thanks to profiles | Similar | **Full** (falls back gracefully) | Training run in CI; cache must match JDK/classpath |
| CRaC (Coordinated Restore at Checkpoint) | Snapshot a warmed process, restore later | ~tens of ms | Best (already warm) | Similar | Full, but needs checkpoint-safe resources (sockets, secrets) | Vendor JDK support (Azul, Liberica), Linux CRIU, security of the snapshot |
| GraalVM Native Image | Closed-world static analysis, AOT compile, image heap | **~10–100 ms** | Lower without PGO (Oracle GraalVM PGO narrows the gap) | **Lowest** | Must be declared (reachability metadata) | Long builds, separate test matrix, different GC options |

```bash
# JDK 25 Leyden one-step training (JEP 514), then production run:
java -XX:AOTCacheOutput=app.aot -jar app.jar --spring.context.exit=onRefresh   # training run
java -XX:AOTCache=app.aot -jar app.jar                                          # production
```

---

## 6. Paradigm 4 — Data-oriented programming (records + sealed + patterns)

<!-- run: wrap -->
```java
sealed interface PaymentResult permits Approved, Declined, Pending {}
record Approved(String authCode, long amountMinor) implements PaymentResult {}
record Declined(String reason, boolean retryable) implements PaymentResult {}
record Pending(java.time.Instant until) implements PaymentResult {}

static String render(PaymentResult r) {
    return switch (r) {                                   // exhaustive: no default needed
        case Approved(var code, var amt) when amt > 1_000_00 -> "BIG approval " + code;
        case Approved(var code, _)                          -> "approved " + code;
        case Declined(var why, var retry) when retry        -> "retry later: " + why;
        case Declined(var why, _)                           -> "hard decline: " + why;
        case Pending(var until)                             -> "pending until " + until;
    };
}
```

> Record patterns cannot contain **constant** sub-patterns such as `Declined(var why, true)`; the compiler rejects them. Use a `when` guard. Constant patterns are not part of the language as of JDK 27. Only *primitive type* patterns are in preview (JEPs 507 → 530 → 532).

**Architectural consequence:** adding `record Refunded(...) implements PaymentResult` turns every non-exhaustive `switch` into a **compile error**. That is what you want for domain invariants. A *separately compiled* stale client gets a runtime `MatchException` instead (Pillar 2, file 02).

---

## 7. Paradigm 5 — Integrity by default and native interop

| Old practice | Status | Replacement |
|---|---|---|
| `sun.misc.Unsafe` memory access (`getLong(address)`, `allocateMemory`) | Deprecated for removal (JEP 471, 23); runtime warnings (JEP 498, 24) | `MemorySegment`/`Arena` (FFM), `VarHandle` |
| `Unsafe.compareAndSwap*` | Same | `VarHandle.compareAndSet`, `Atomic*` |
| Deep reflection into JDK internals | Blocked since 17 (JEP 403) | Public APIs; `--add-opens` as last resort (documented debt) |
| Mutating `final` fields via reflection | Warns in 26 (JEP 500), headed for denial | Constructors, builders, `with`-style copies |
| JNI | Warnings on first use unless enabled (JEP 472, 24) | FFM API (`Linker`, `SymbolLookup`), jextract |
| Dynamic agent attach | Warns (JEP 451, 21) | `-javaagent` at startup or `-XX:+EnableDynamicAgentLoading` |
| Security Manager | Permanently disabled (JEP 486, 24) | Process/container isolation, OS sandboxing |
| `finalize()` | Deprecated for removal (JEP 421, 18) | `Cleaner`, try-with-resources |

---

## 8. Paradigm 6 — Observability is built in

* **JFR** (open-sourced in 11, streaming API in 14) costs about 1% in the default profile, so it can run *always-on* in production.
* JDK 25 adds **CPU-time profiling** (JEP 509, experimental, Linux), **cooperative sampling** (JEP 518, safer stack walking) and **method timing and tracing** (JEP 520, no bytecode agent needed).
* JDK 27 adds **in-process data redaction** (JEP 536) for safely sharing recordings.
* Virtual threads appear in `jcmd <pid> Thread.dump_to_file -format=json`. Classic `jstack` won't list unmounted virtual threads.

---

## 9. A request's life in a JDK 25 service — where every pillar shows up

```
 Client ──TCP SYN──► NIC ─► kernel (TCP stack, accept queue: backlog)            [P4: sockets, epoll]
                                   │
           Tomcat/Jetty acceptor (platform thread) accept()                       [P4: NIO ServerSocketChannel]
                                   │
           request handed to a NEW virtual thread (spring.threads.virtual.enabled)[P3: Loom scheduler = FJP]
                                   │
   ┌──────── HTTP parsing: bytes → String (compact strings, Latin-1 coder)         [P2: String internals]
   │         Jackson: bytes → record DTO (allocation; escape analysis may scalar-   [P4: serialization]
   │         replace temporaries once C2 has compiled the hot path)                 [P1: JIT/EA]
   │                                   │
   │         Business logic: sealed/records/pattern switch                          [P2]
   │         Fan-out to 2 services: StructuredTaskScope forks 2 VTs                 [P3]
   │                │        VT blocks on socket read → unmounts; carrier freed      [P3/P4: poller]
   │                │        JDBC call → Hikari ConcurrentBag (Pillar 5)             [P5 next run]
   │                ▼
   │         Response objects die young → TLAB bump allocation → eden               [P1: heap/TLAB]
   │         Young GC (G1 evacuation) or ZGC minor cycle reclaims them              [P1: GC]
   └──────── Response bytes → socket write (maybe zero-copy for static files)        [P4: transferTo]
             Trace/metrics/logs: OpenTelemetry context in ScopedValue/ThreadLocal    [P8 next run]
```

**Where latency hides on this path:** accept-queue overflow (P4), carrier starvation from CPU-bound VTs or pinning (P3), GC pauses or allocation stalls (P1), JIT warm-up and deoptimization (P1), lock convoys (P3), DB pool waits (P5), serialization allocation (P4).

---

## 10. Production JVM baseline for containers (JDK 25, Kubernetes)

```bash
JAVA_TOOL_OPTIONS="\
  -XX:MaxRAMPercentage=75.0 -XX:InitialRAMPercentage=75.0 \
  -XX:+UseG1GC \
  -XX:+UseCompactObjectHeaders \
  -XX:+ExitOnOutOfMemoryError -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/dumps \
  -Xlog:gc*,safepoint:file=/logs/gc.log:time,uptime,level,tags:filecount=5,filesize=20m \
  -XX:NativeMemoryTracking=summary \
  -XX:StartFlightRecording=disk=true,maxsize=256m,maxage=6h,settings=default,dumponexit=true,filename=/dumps/ \
  -XX:+PerfDisableSharedMem"
```

| Flag | Why | Pitfall it prevents |
|---|---|---|
| `MaxRAMPercentage=75` | Heap sized from the cgroup memory limit; leaves ~25% for Metaspace, code cache, thread stacks, direct buffers, GC structures, malloc | Default is **25%**, which wastes 75% of the pod, or with `-Xmx` hard-coded, gets OOMKilled |
| `InitialRAMPercentage=75` | Commit up-front, so there's no heap growth under load (or use `-Xms` = `-Xmx`) | Resize churn and late OOMKill surprises |
| `UseG1GC` explicit | On JDK ≤ 26, JVM ergonomics pick **Serial GC** when it sees < 2 CPUs or < ~1792 MB of memory | Silent Serial GC in small pods → long STW pauses (fixed by JEP 523 in 27) |
| `UseCompactObjectHeaders` | 8-byte headers (product flag in 25) | — (test first; default in 27) |
| `ExitOnOutOfMemoryError` | Fail fast and let the orchestrator restart | Zombie JVM limping after OOM in a random thread |
| `HeapDumpOnOutOfMemoryError` | Forensics | Ensure the volume has space ≥ heap and the liveness probe tolerates dump time |
| `-Xlog:gc*,safepoint` | GC and time-to-safepoint visibility with rotation | Unbounded GC logs filling disk |
| `NativeMemoryTracking=summary` | Explains RSS > heap (`jcmd <pid> VM.native_memory summary`) | Guessing at OOMKilled root causes. Small overhead, so some teams enable it only in canaries |
| `StartFlightRecording` | Always-on low-overhead flight recorder | No data after an incident |
| `PerfDisableSharedMem` | Stops the JVM mmap'ing `/tmp/hsperfdata_*` | Multi-hundred-ms stalls when the hsperfdata page write blocks on I/O (classic latency-spike war story); note it disables `jps`/`jstat` discovery |

Add `-XX:ActiveProcessorCount=N` when CPU *limits* are fractional or when you deliberately run without CPU limits. The JVM derives thread-pool sizes (GC workers, `ForkJoinPool.commonPool`, the virtual-thread scheduler) from this count.

---

## 11. Architecture Decision Records (ADR) — default answers

| Decision | Default (2026) | Switch when |
|---|---|---|
| Java version | 25 LTS | 27 for compact-headers-by-default or G1 improvements, after soak testing |
| Web stack | Spring MVC + virtual threads | Streaming/backpressure-native workloads → WebFlux |
| GC | G1 with `MaxRAMPercentage` | p99.9 pause SLO < ~10 ms → Generational ZGC; batch → Parallel |
| Async composition | Virtual threads + `StructuredTaskScope` (preview) or `CompletableFuture` on a VT executor | Need final APIs only → `CompletableFuture` + `newVirtualThreadPerTaskExecutor()` |
| Request context | `ScopedValue` (final in 25) | Libraries require `ThreadLocal`/MDC → keep `ThreadLocal`, but never pool VTs |
| Off-heap / native | FFM API | Legacy JNI libs → wrap them, and plan the migration |
| Serialization (internal RPC) | Protobuf/gRPC | Kafka analytics with schema registry → Avro; public APIs → JSON (Jackson) |
| Never | Java native serialization over trust boundaries | — |
| Startup-sensitive (scale-to-zero, CLI) | Leyden AOT cache first | Need < 100 ms cold start and tiny RSS → Native Image |

---

## 12. Reading map

| Pillar | Folder | Start with |
|---|---|---|
| 1 · JVM internals | [01-JVM-Internals](01-JVM-Internals/) | 02 (memory areas) → 04 (GC) → 05 (JIT) |
| 2 · Core Java | [02-Core-Java](02-Core-Java/) | 01 (collections) → 02 (strings/records/patterns) → 03 (streams) |
| 3 · Concurrency & Loom | [03-Concurrency-Loom](03-Concurrency-Loom/) | 01 (JMM) → 06 (virtual threads) |
| 4 · I/O, NIO, serialization | [04-IO-NIO-Serialization](04-IO-NIO-Serialization/) | 01 (I/O models) → 02 (zero-copy and Netty) |
| Cheat sheets | [99-Cheat-Sheets](99-Cheat-Sheets/) | JVM flags + `jcmd` |

### Primary sources

* JEPs: <https://openjdk.org/jeps/0> (index). Release pages: <https://openjdk.org/projects/jdk/25/>, `/26/`, `/27/`.
* JVM Specification SE 25: <https://docs.oracle.com/javase/specs/jvms/se25/html/>. JLS SE 25: <https://docs.oracle.com/javase/specs/jls/se25/html/>.
* HotSpot GC tuning guide: <https://docs.oracle.com/en/java/javase/25/gctuning/>.
* Aleksey Shipilëv's "JVM Anatomy Quarks": <https://shipilev.net/jvm/anatomy-quarks/>.
* Martin Thompson, "Mechanical Sympathy": <https://mechanical-sympathy.blogspot.com/>.
