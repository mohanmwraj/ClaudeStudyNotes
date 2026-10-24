# 1.6 · Pillar 1 — Production Failure Modes & Diagnostic Checklist (JVM Internals)

> This file pulls together the failure-mode tables from [1.1](01-ClassLoading-Linking-JPMS.md)–[1.5](05-JIT-Compilation-AOT-Native-Image.md) into **incident playbooks**, a **first-five-minutes runbook**, a **data-collection script**, and **alerting thresholds**.
> The war stories are composites of common real-world incident patterns, anonymized and simplified. The log lines are real JDK 25 output from the experiments in this pillar.

---

## 1. The JVM triage mental model

```
            Is it the JVM at all?  (compare app latency vs. downstream latency vs. host/container metrics)
                                     │
        ┌──────────────┬─────────────┼──────────────┬───────────────┬─────────────────┐
        ▼              ▼             ▼              ▼               ▼                 ▼
   MEMORY (heap)   MEMORY (native)  GC/SAFEPOINT    JIT/CPU         THREADS/LOCKS      CLASSLOADING
   OOM heap,       OOMKilled 137,   pauses, TTSP,   warm-up, deopt, (Pillar 3)         Metaspace, NCDFE,
   leak            direct, threads  stalls          code cache                         NoSuchMethodError
   ─────────       ─────────        ─────────       ─────────                          ─────────
   heap dump,      NMT, pmap,       GC + safepoint  JFR Compilation/ thread dumps,     -Xlog:class+load,
   histograms,     BufferPool MX,   logs, JFR       Deoptimization,  JFR locks         classloader_stats,
   JFR OldObject   cgroup stats     GC events       Compiler.queue                     VM.metaspace
```

**Rule 1:** collect evidence *before* restarting. A restart destroys the heap, the native memory map and the thread state. **Rule 2:** change one variable at a time. **Rule 3:** suspect the most recent change first: deployment, traffic shape, dependency upgrade, JDK upgrade, container limits.

---

## 2. Incident playbooks (war stories)

### 🔥 Story 1 — "Exit code 137 with a perfectly healthy heap"

* **Symptom:** pods restart every few hours with `OOMKilled` (exit 137). Heap dashboards show 1.2 of 2 GB used, and there is no Java `OutOfMemoryError` in the logs.
* **Investigation:**
  ```bash
  kubectl describe pod … | grep -A3 "Last State"         # Reason: OOMKilled
  jcmd <pid> VM.native_memory summary scale=MB           # needs -XX:NativeMemoryTracking=summary
  cat /sys/fs/cgroup/memory.current /sys/fs/cgroup/memory.max
  pmap -x <pid> | sort -k3 -n | tail -20                # many ~64 MB anon regions → glibc malloc arenas
  ```
  NMT showed `Other` (direct buffers) at 600 MB, from a Netty-based HTTP client allocating unpooled direct buffers under bursty load, plus 300 threads × ~1 MB committed stacks. `-Xmx2g` in a 3 GiB pod left too little for native memory.
* **Root cause:** RSS = heap + native. `MaxDirectMemorySize` defaulted to `-Xmx` (2 GB!), and the thread count was unbounded.
* **Fix:** `-XX:MaxRAMPercentage=65`, `-XX:MaxDirectMemorySize=256m`, a pooled allocator, a bounded executor, and `MALLOC_ARENA_MAX=2`.
* **Prevention:** alert on `container_memory_working_set_bytes / limit > 0.9`, export `jvm.buffer.memory.used{id=direct}`, and run NMT summaries in canaries.

### 🔥 Story 2 — "400 ms pauses on a 'small' service"

* **Symptom:** p99 latency of 450 ms on a 1-vCPU, 1 GiB pod. GC pauses of ~400 ms appear in metrics.
* **Investigation:** the first line of `-Xlog:gc` was `Using Serial`.
* **Root cause:** JVM ergonomics pick **Serial GC** below 2 CPUs or ~1.8 GB of memory (JDK ≤ 26), and full GCs are single-threaded.
* **Fix:** `-XX:+UseG1GC` explicitly, plus 2 vCPU requests for latency-sensitive pods. JDK 27 (JEP 523) changes the default.
* **Prevention:** a startup log assertion, or `jcmd <pid> VM.flags | grep -E 'Use.*GC'` in a smoke test.

### 🔥 Story 3 — "Monday-morning Full GC"

* **Symptom:** weekly batch import days show `Pause Full (G1 Compaction Pause)` lasting 4–8 s.
* **Investigation:** GC log causes `(G1 Humongous Allocation)`, `Humongous regions: 2400->2380`, then `Evacuation Failure: Allocation` → `Pause Full`.
* **Root cause:** each import message was read fully into a `byte[]` of 4–12 MB. With 8 MB regions, every buffer was **humongous**: allocated in old gen, fragmenting it, triggering concurrent cycles constantly, and eventually exhausting contiguous free regions.
* **Fix:** stream-parse the payloads (Jackson `JsonParser` over `InputStream`), and set `-XX:G1HeapRegionSize=32m` as a stopgap.
* **Prevention:** a dashboard panel for humongous allocations (`-Xlog:gc+humongous=debug` or the JFR `jdk.G1HeapRegionTypeChange`/allocation events).

### 🔥 Story 4 — "Metaspace ratchet"

* **Symptom:** `OutOfMemoryError: Metaspace` every ~3 days. Metaspace usage climbs in steps.
* **Investigation:** `jcmd <pid> VM.classloader_stats` listed 9,000 `GroovyClassLoader$InnerLoader` instances. The heap dump's path to GC roots showed a static `ConcurrentHashMap` in a rules engine caching compiled scripts **by script text including a timestamp**.
* **Root cause:** a cache key that never repeated, so every evaluation compiled a new class in a new loader.
* **Fix:** a stable cache key, `-XX:MaxMetaspaceSize=512m` so it fails loudly, and a bounded Caffeine cache with eviction.
* **Prevention:** alert on `jvm.classes.loaded` growth with no matching unloads, and on Metaspace used > 80% of the max.

### ⚡ Story 5 — "We gave it more memory and it got worse"

* **Symptom:** after raising `-Xmx` from 30g to 34g, GC frequency went *up*.
* **Investigation:** `-Xlog:gc+init` showed `Compressed Oops: Disabled`.
* **Root cause:** crossing the 32 GB compressed-oops boundary made every reference 8 bytes, and the reference-heavy cache grew ~35%.
* **Fix:** back to `-Xmx31g` (or go to ≥ 48 GB). Shrink the cache footprint with primitive maps.

### 🔥 Story 6 — "GC logs say 5 ms, users say 900 ms"

* **Symptom:** periodic ~1 s request stalls. GC pauses are all < 10 ms.
* **Investigation:** `-Xlog:safepoint` showed `Reaching safepoint: 870000000 ns, At safepoint: 4100000 ns`, so TTSP was ~870 ms. `perf` showed a thread page-faulting on a large memory-mapped file whose pages had been evicted (the host was under memory pressure, with swap enabled). A second case had the same signature from a JVM writing `hsperfdata` to a `/tmp` on slow storage.
* **Root cause:** a thread couldn't reach a safepoint poll while blocked on page faults, so every other thread waited at the safepoint.
* **Fix:** disable swap for latency nodes, add `-XX:+AlwaysPreTouch`, keep mmap'd hot files resident (or use page-cache-friendly access), and set `-XX:+PerfDisableSharedMem`.
* **Prevention:** always log `safepoint` alongside `gc`, and alert when TTSP exceeds 100 ms.

### ⚡ Story 7 — "Day-9 slowdown"

* **Symptom:** after ~9 days of uptime, throughput drops 70% and never recovers until restart.
* **Investigation:** the stdout log contained `CodeCache is full. Compiler has been disabled.`. `jcmd Compiler.codecache` showed the non-profiled segment full. JFR showed thousands of deoptimizations per hour from a plugin system loading new subclasses (CHA invalidation), which led to recompilation churn and fragmentation.
* **Fix:** `-XX:ReservedCodeCacheSize=512m` short-term, then load plugin classes at startup, which stopped the CHA invalidation churn.
* **Prevention:** export the `CodeHeap` memory pools as metrics and alert above 90%.

### ⚡ Story 8 — "Stack-trace-less NPE flood"

* **Symptom:** millions of `java.lang.NullPointerException` log lines with no message and no stack trace.
* **Root cause:** `OmitStackTraceInFastThrow`. The first few thousand occurrences (with traces) had rotated out of the logs.
* **Fix:** search the archived logs for the first occurrence, or restart a canary with `-XX:-OmitStackTraceInFastThrow`.

### ⚡ Story 9 — "ZGC migration, now with stalls"

* **Symptom:** after switching G1 → ZGC with the same `-Xmx8g`, p99 improved but p99.9 got worse.
* **Investigation:** GC log lines `Allocation Stall (http-nio-…) 12.4ms`.
* **Root cause:** ZGC has no compressed oops, so the live set grew from 3.5 to ~4.6 GB, and ZGC needs headroom to run concurrently. At an 8 GB heap the GC couldn't keep up with allocation bursts.
* **Fix:** `-Xmx14g` with `-XX:SoftMaxHeapSize=11g`, plus reduced allocation in the JSON layer.
* **Prevention:** size ZGC from the measured live set (×2–3), and make **allocation stalls = 0** an SLO.

### ⚡ Story 10 — "The heap dump that took down the node"

* **Symptom:** a 28 GB heap OOM'd; `HeapDumpOnOutOfMemoryError` started writing 28 GB to the root disk, the node ran out of disk, and other pods were evicted.
* **Fix:** write dumps to a dedicated volume, use `-XX:+ExitOnOutOfMemoryError`, and set liveness probes with enough tolerance. Prefer `jcmd GC.heap_dump -gz=1` for manual dumps. Consider JFR `OldObjectSample` as the first-line leak evidence (small files).

### ⚡ Story 11 — "Startup hang on a 64-core box"

* **Symptom:** the service occasionally hangs during startup only on big machines. Threads show as `RUNNABLE`, and jstack reports no deadlock.
* **Root cause:** a **class-initialization deadlock** between two singletons whose static initializers referenced each other, triggered concurrently by parallel bean initialization (see [1.1 §5.4](01-ClassLoading-Linking-JPMS.md#54-class-initialization-deadlock-)).
* **Fix:** break the static-init cycle and make initialization explicit and ordered.

### ⚡ Story 12 — "`NoSuchMethodError` only when a customer exports a report"

* **Root cause:** two versions of Apache POI on the class path. The exporter was compiled against 5.x while 4.x won class loading, and lazy resolution meant the failure appeared only on that code path.
* **Diagnose:** `-Xlog:class+load=info | grep poi` showed which JAR supplied the class.
* **Fix:** dependency convergence (Maven Enforcer `dependencyConvergence`, Gradle `failOnVersionConflict()`).

---

## 3. First five minutes — runbook

```bash
# 0. Identify the JVM (inside the container: the PID is usually 1, or use jcmd with no args)
jcmd                                   # list JVMs
PID=<pid>

# 1. What is this JVM? (flags, version, uptime, GC in use)
jcmd $PID VM.version
jcmd $PID VM.command_line
jcmd $PID VM.flags | tr ' ' '\n' | grep -E 'Use.*GC|Xmx|MaxRAM|MaxHeapSize|MaxDirect|Metaspace|ActiveProcessor'
jcmd $PID VM.uptime

# 2. Memory picture
jcmd $PID GC.heap_info
jcmd $PID VM.native_memory summary scale=MB    # only if NMT was enabled at startup
jcmd $PID VM.metaspace | head -20

# 3. Threads (take 3 dumps 5-10 s apart; diffs reveal stuck vs. busy threads)
for i in 1 2 3; do jcmd $PID Thread.print -l > /tmp/td.$i.txt; sleep 5; done
jcmd $PID Thread.dump_to_file -format=json /tmp/td.json     # includes virtual threads (JDK 21+)

# 4. Flight recording (low overhead, the single most valuable artifact)
jcmd $PID JFR.start name=triage duration=120s settings=profile filename=/tmp/triage.jfr
# … or dump the always-on recording:
jcmd $PID JFR.dump name=1 filename=/tmp/now.jfr

# 5. CPU by thread (Linux): map hot native thread IDs (hex) to Java thread "nid=0x…"
top -H -b -n 1 -p $PID | head -30
printf '%x\n' <tid>

# 6. Only if memory is the issue and you can afford a pause:
jcmd $PID GC.class_histogram | head -40          # triggers full GC
jcmd $PID GC.heap_dump -gz=1 /dumps/heap.hprof.gz # pauses for seconds on big heaps
```

### 3.1 A reusable collection script

```bash
#!/usr/bin/env bash
# jvm-triage.sh <pid> [outdir] — collect JVM evidence non-destructively (no heap dump, no histogram)
set -euo pipefail
PID=$1; OUT=${2:-/tmp/jvm-triage-$(date +%Y%m%dT%H%M%S)}; mkdir -p "$OUT"
run() { echo "## $*" ; "$@" 2>&1 || true; }
{
  run jcmd "$PID" VM.version
  run jcmd "$PID" VM.uptime
  run jcmd "$PID" VM.command_line
  run jcmd "$PID" VM.flags -all
  run jcmd "$PID" VM.system_properties
  run jcmd "$PID" GC.heap_info
  run jcmd "$PID" VM.metaspace
  run jcmd "$PID" VM.native_memory summary scale=MB
  run jcmd "$PID" Compiler.codecache
  run jcmd "$PID" VM.classloader_stats
} > "$OUT/vm.txt"
for i in 1 2 3; do jcmd "$PID" Thread.print -l > "$OUT/threads.$i.txt" 2>&1 || true; sleep 5; done
jcmd "$PID" Thread.dump_to_file -format=json "$OUT/threads.json" >/dev/null 2>&1 || true
jcmd "$PID" JFR.start name=triage duration=60s settings=profile filename="$OUT/triage.jfr" >/dev/null 2>&1 || true
[ -r /sys/fs/cgroup/memory.stat ] && cp /sys/fs/cgroup/memory.stat /sys/fs/cgroup/cpu.stat "$OUT/" 2>/dev/null || true
top -H -b -n 1 -p "$PID" > "$OUT/top-threads.txt" 2>/dev/null || true
echo "Evidence in $OUT (JFR completes in 60 s)"
```

---

## 4. Always-on configuration that makes incidents diagnosable

```bash
-Xlog:gc*,safepoint:file=/logs/gc.log:time,uptime,level,tags:filecount=5,filesize=20m
-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/dumps -XX:+ExitOnOutOfMemoryError
-XX:StartFlightRecording=disk=true,maxage=6h,maxsize=512m,settings=default,dumponexit=true,filename=/dumps/
-XX:NativeMemoryTracking=summary            # small overhead; at least on canaries
-XX:+PerfDisableSharedMem                    # avoids hsperfdata stalls (disables jstat/jps discovery)
-XX:ErrorFile=/logs/hs_err_pid%p.log         # crash logs to persistent storage
```

---

## 5. Metrics & alert thresholds (Micrometer names)

| Metric | Alert when | Points to |
|---|---|---|
| `jvm.gc.pause` (max, p99) | > SLO budget (e.g. p99 > 200 ms G1, > 5 ms ZGC) | GC tuning or a leak |
| `jvm.gc.overhead` (Micrometer `JvmHeapPressureMetrics`) | > 10% over 5 min | Undersized heap or allocation hotspot |
| `jvm.gc.live.data.size` (post-GC old gen) | Rising floor over 24 h | **Leak** |
| `jvm.gc.memory.promoted` rate | Rising over days | Premature promotion |
| `jvm.memory.used{area=nonheap,id=Metaspace}` | > 80% of `MaxMetaspaceSize`, or steady growth | Loader leak |
| `jvm.memory.used{id=CodeHeap 'non-profiled nmethods'}` | > 90% | Code cache exhaustion |
| `jvm.buffer.memory.used{id=direct}` | Growing without bound | Direct buffer leak |
| `jvm.threads.live` / `jvm.threads.peak` | Growing without bound | Thread leak |
| `container_memory_working_set_bytes / limit` | > 90% | Native growth → OOMKill risk |
| `process.cpu.usage` with `container_cpu_cfs_throttled_periods_total` | Throttling > 5% | CPU limits starving GC/JIT |
| GC log: `Allocation Stall`, `Pause Degenerated`, `Evacuation Failure`, `Pause Full` | Any occurrence | Collector can't keep up |
| Safepoint TTSP (from logs/JFR) | > 100 ms | Page faults, swap, long non-polling loops |

---

## 6. Master diagnostic checklist (print this)

**Memory — heap**
- [ ] Live set after GC: stable, or a rising floor?
- [ ] Allocation rate and promotion rate known?
- [ ] Heap dump on OOM configured to a volume with space?
- [ ] `-Xmx` < 32 GB (compressed oops), or deliberately ≥ 48 GB?
- [ ] Collector chosen deliberately (not Serial by accident)?

**Memory — native**
- [ ] Container limit ≥ heap + Metaspace + code cache + threads × stack + direct + GC overhead + 10%?
- [ ] `MaxDirectMemorySize` set explicitly for Netty/NIO-heavy apps?
- [ ] `MaxMetaspaceSize` set so leaks fail fast?
- [ ] Thread pools bounded (no `newCachedThreadPool` on request paths)?
- [ ] `MALLOC_ARENA_MAX` considered for glibc + many threads?

**GC / safepoints**
- [ ] GC **and safepoint** logging on, with rotation?
- [ ] Zero full GCs / allocation stalls / degenerated GCs in steady state?
- [ ] TTSP < 1 ms typical?
- [ ] Swap disabled on latency-critical nodes; THP set to `madvise`?

**JIT**
- [ ] Warm-up strategy (readiness after warm-up, AOT cache, CRaC)?
- [ ] Code cache usage monitored?
- [ ] `-XX:-OmitStackTraceInFastThrow` considered for debugging environments?

**Class loading**
- [ ] Dependency convergence enforced at build time?
- [ ] No per-request class generation (scripts, proxies) without a bounded cache?
- [ ] `--add-opens` flags documented with owners and removal plans?

---

## 7. Further reading

* JDK Troubleshooting Guide (JDK 25): <https://docs.oracle.com/en/java/javase/25/troubleshoot/>
* `jcmd` reference: <https://docs.oracle.com/en/java/javase/25/docs/specs/man/jcmd.html>
* JDK Mission Control: <https://jdk.java.net/jmc/>
* Brendan Gregg, "Systems Performance" (2nd ed.), for the OS side of every JVM incident.
