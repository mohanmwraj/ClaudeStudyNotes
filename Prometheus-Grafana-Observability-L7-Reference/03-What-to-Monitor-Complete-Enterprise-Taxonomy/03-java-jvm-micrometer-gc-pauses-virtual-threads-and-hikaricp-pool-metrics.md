# 03 · Java: JVM, Micrometer, GC Pauses, Virtual Threads and HikariCP Pool Metrics

> **Folder 03 — What to Monitor: Complete Enterprise Taxonomy · File 3 of 4.**
> Pinned to **Micrometer v1.17.2** (2026-10-23), **Spring Boot v4.1.2** (2026-10-22), **HikariCP 7.1.0**, JDK 21/25 LTS. Meter names were read from `JvmGcMetrics`, `JvmThreadMetrics`, `VirtualThreadMetrics` (micrometer-java21) and HikariCP's `MicrometerMetricsTracker`.
> Labels: **[D]** documented / read in pinned source · **[M]** measured by the listing (deterministic, re-run by the gate) · **[E]** model · **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L3 `hikari_pool_lab.py` | An Erlang-C (M/M/c) model of `hikaricp_connections_pending` and acquire time, **validated by a discrete-event simulation** (within 10% for pools of 10–16); a 300 ms stop-the-world GC pause every 10 s turning acquire p99 from 12.5 ms into 254 ms with an idle database; and why "switch to virtual threads" at 2× traffic produces 16k pending acquisitions and 12k timeouts on an unchanged pool | ~6 s |

**Verification.** The analytic model and the simulator are independent implementations of the same queue; their agreement is asserted. GC and virtual-thread scenarios are model results [E/M] for the stated workload (400 req/s, 20 ms connection hold time). Meter names are from the pinned sources; Prometheus names follow Micrometer's Prometheus naming convention (dots → underscores, base unit and `_total` suffixes), with ⚠ where a gauge's unit suffix is version-dependent. No JVM was run.

---

## 0. Orientation

**What this file answers.** Which JVM and library signals predict user-visible latency in a Spring Boot service, how to read them (GC, heap, threads, virtual threads, connection pools, executors), and how container limits interact with JVM ergonomics.

**The Java service saturation stack.** Requests wait in up to five queues, each with its own metric — and the one that is full is the one that matters:

```text
 client → [Tomcat/Netty accept + worker threads]  tomcat_threads_busy_threads / config_max_threads
        → [application executor / virtual-thread scheduler]  executor_queued_tasks, jvm_threads_virtual_*
        → [HikariCP connection pool]  hikaricp_connections_pending, hikaricp_connections_acquire_seconds
        → [database]  (File 4)
 overlaid on every stage: GC pauses (jvm_gc_pause_seconds), CPU throttling (File 2), safepoints
```

---

## 1. First principles: what each JVM signal means

### 1.1 Heap and GC (Micrometer `JvmMemoryMetrics`, `JvmGcMetrics`, `JvmHeapPressureMetrics`) [D]

| Micrometer meter | Prometheus series | Read it as |
|---|---|---|
| `jvm.memory.used` / `committed` / `max` (`area`, `id` tags) | `jvm_memory_used_bytes{area="heap",id="G1 Old Gen"}` … | Per pool; old-gen "used" after GC is the live set |
| `jvm.gc.pause` (Timer; `action`, `cause`, `gc` tags) | `jvm_gc_pause_seconds_count/_sum/_max` (+ `_bucket` if histograms enabled) | Stop-the-world pause time; `rate(_sum)` = fraction of time paused |
| `jvm.gc.concurrent.phase.time` | `jvm_gc_concurrent_phase_time_seconds_*` | Concurrent work (ZGC/Shenandoah/G1 marking) — CPU, not pauses |
| `jvm.gc.memory.allocated` / `promoted` | `jvm_gc_memory_allocated_bytes_total`, `jvm_gc_memory_promoted_bytes_total` | Allocation and promotion *rates* — the GC workload |
| `jvm.gc.live.data.size` / `max.data.size` | `jvm_gc_live_data_size_bytes`, `jvm_gc_max_data_size_bytes` | Old-gen live set vs capacity — leak and sizing signal |
| `jvm.gc.overhead` (heap-pressure binder) | `jvm_gc_overhead` | Share of CPU time spent in GC over a lookback window |
| `jvm.gc.cpu.time` (recent Micrometer; present in 1.17.2) | `jvm_gc_cpu_time_seconds_total` | GC CPU, including concurrent threads |

Collector-specific reading for JDK 21/25:

- **G1 (default)**: young pauses scale with live objects in the young gen and remembered-set work; mixed collections reclaim old regions. Watch `rate(jvm_gc_pause_seconds_sum[5m])` (> 0.05 = 5% of wall time paused is severe) and pause *max* per scrape.
- **Generational ZGC** (opt-in in JDK 21, the default ZGC mode from JDK 23, the only mode from JDK 24): pauses are sub-millisecond; the risk shifts to **allocation stalls** (application threads blocked waiting for memory) and concurrent GC CPU. Pause metrics look perfect while latency suffers — watch allocation rate vs the GC's reclaim rate and GC logs (`-Xlog:gc*`).
- **Live-set growth** across full cycles (`jvm_gc_live_data_size_bytes` after collection trending up) is the leak signal; heap *used* oscillating is normal.

### 1.2 Threads, executors and virtual threads [D]

- `jvm_threads_live_threads`, `jvm_threads_daemon_threads`, `jvm_threads_peak_threads`, `jvm_threads_started_threads_total`, `jvm_threads_states_threads{state="blocked|waiting|timed-waiting|runnable"}` — a rising `blocked` share is lock contention.
- Executors bound by Micrometer: `executor_active_threads`, `executor_queued_tasks`, `executor_pool_size_threads`, `executor_completed_tasks_total`. **Queued tasks is saturation.**
- Tomcat: `tomcat_threads_busy_threads` vs `tomcat_threads_config_max_threads` — the classic request-thread saturation ratio (not needed with virtual threads, where there is no worker cap).
- **Virtual threads** (`micrometer-java21` `VirtualThreadMetrics`, JFR-based): `jvm.threads.virtual.pinned` (Timer from `jdk.VirtualThreadPinned` events), `jvm.threads.virtual.submit.failed` (Counter), and gauges `jvm.threads.virtual.parallelism`, `.pool.size`, `.live` (tagged mounted/queued). Prometheus: `jvm_threads_virtual_pinned_seconds_*`, `jvm_threads_virtual_submit_failed_total`, and the gauges (⚠ unit suffix depends on the gauge's base unit).
- **Pinning**: on JDK 21–23 a virtual thread blocking inside `synchronized` pins its carrier; JDK 24 (JEP 491) removed that case, leaving native frames and a few JDK internals. Pinned-time on JDK 21 is a top saturation signal for virtual-thread services that use JDBC drivers or libraries with `synchronized` I/O.

### 1.3 HikariCP: the pool as a queue (L3)

HikariCP 7.1 publishes (via Micrometer) `hikaricp_connections_active`, `_idle`, `_pending`, `_max`, `_min`, `hikaricp_connections` (total), `hikaricp_connections_timeout_total`, and timers `hikaricp_connections_acquire_seconds` (wait), `hikaricp_connections_usage_seconds` (hold time) and `hikaricp_connections_creation_seconds` [D], each tagged `pool`.

That is an M/M/c queue whose parameters are directly observable [M]:

```text
 λ = rate(hikaricp_connections_usage_seconds_count[5m])        (acquisitions per second)
 S = rate(hikaricp_connections_usage_seconds_sum[5m]) / λ      (mean hold time)
 offered load a = λ·S   (connections busy on average)   utilisation ρ = a / maximumPoolSize
 Erlang C: P(wait), mean wait W_q = P(wait)·S/(c−a),  pending = λ·W_q  (Little)
```

L3 §1 at λ = 400/s, S = 20 ms (a = 8):

| Pool c | ρ | P(wait) | Model wait | Simulated wait | Simulated p99 | Pending |
|---|---|---|---|---|---|---|
| 9 | 89% | 65% | 13.1 ms | 12.7 ms | 82 ms | 5.1 |
| 10 (default) | 80% | **41%** | 4.1 ms | 4.4 ms | 39 ms | 1.8 |
| 12 | 67% | 14% | 0.7 ms | 0.7 ms | 12.5 ms | 0.3 |
| 16 | 50% | 0.9% | 0.02 ms | 0.02 ms | ~0 | 0.0 |

Consequences:

- **Size pools from Little's law, not folklore**: `c ≥ λ·S / target_ρ` with target ρ ≈ 0.6–0.7 for latency-sensitive services — and remember the *database* must serve c × replicas concurrent queries (the real constraint, File 4).
- **GC pauses masquerade as database slowness.** A 300 ms pause every 10 s queues ~120 requests that then hit a pool of 12 at once: acquire p99 12.5 → **254 ms** with an idle database (L3 §2). Correlate `hikaricp_connections_acquire_seconds` with `jvm_gc_pause_seconds_max` before escalating to the DBA.
- **Virtual threads move the bottleneck, they don't remove it.** With platform threads, Tomcat's 200-thread cap bounded concurrency; with virtual threads every request reaches the pool. At 2× traffic (a = 16 > c = 10) the pool is unstable: mean wait 20 s, 12k timeouts in 2 minutes (L3 §3). Pair virtual threads with an explicit concurrency limiter (semaphore/bulkhead) sized to the pool.

### 1.4 The JVM inside a container

- **CPU**: `Runtime.availableProcessors()` is derived from the cgroup CPU *quota* (limits). With no CPU limit it is the host's core count → oversized GC thread counts, ForkJoin common pool and Netty event loops on a 2-core-request pod. Set `-XX:ActiveProcessorCount` to the request when running without limits.
- **Memory**: heap is sized with `-XX:MaxRAMPercentage` of the cgroup limit (default 25% — far too low for most services; 60–75% is typical), but RSS = heap + metaspace + code cache + thread stacks + direct/NIO buffers + GC structures. OOMKills (File 2) with a "small" heap are off-heap; NMT (`-XX:NativeMemoryTracking=summary`) attributes them.
- **Safepoints and TTSP**: long time-to-safepoint (counted loops, large array copies) stretches every pause; JDK unified logging `-Xlog:safepoint` exposes it.

<!-- listing:hikari_pool_lab.py -->
```python
"""hikari_pool_lab.py - connection-pool physics for HikariCP dashboards: an Erlang-C (M/M/c) model
of hikaricp_connections_pending / hikaricp_connections_acquire_seconds, validated by a discrete-
event simulation, then three production effects: undersized pools, a stop-the-world GC pause,
and 'just add virtual threads'.

Model: requests arrive Poisson(lambda); each holds a connection for an exponential time with mean
S (query + transaction); the pool has c connections (HikariCP maximumPoolSize, default 10);
waiters queue FIFO and give up after connectionTimeout (default 30 s).
Deterministic (fixed seeds), stdlib only.

Usage: python hikari_pool_lab.py [target.md]
"""
import heapq
import math
import random
import sys


def erlang_c(c, a):
    s = sum(a ** k / math.factorial(k) for k in range(c))
    top = a ** c / math.factorial(c) * c / (c - a)
    return top / (s + top)


def model(lam, s, c):
    a = lam * s
    if a >= c:
        return {"util": 1.0, "p_wait": 1.0, "wait": math.inf, "pending": math.inf}
    pw = erlang_c(c, a)
    wq = pw * s / (c - a)
    return {"util": a / c, "p_wait": pw, "wait": wq, "pending": lam * wq}


def simulate(lam, s, c, seconds=600, seed=7, gc_pause=None, timeout=30.0):
    """Event simulation. gc_pause=(every_s, length_s): no connection is released and no request
    acquires during a stop-the-world pause (the JVM is frozen), arrivals keep queueing upstream."""
    rng = random.Random(seed)
    t, free, waiting, events = 0.0, c, [], []
    waits, timeouts, pend_area, last = [], 0, 0.0, 0.0
    heapq.heappush(events, (rng.expovariate(lam), "arr"))

    def frozen(x):
        if not gc_pause:
            return 0.0
        every, length = gc_pause
        k = math.floor(x / every)
        start = k * every + every - length
        return max(0.0, start + length - x) if x >= start else 0.0

    while events:
        t, kind = heapq.heappop(events)
        if t > seconds:
            break
        pend_area += len(waiting) * (t - last)
        last = t
        hold = frozen(t)
        if hold > 0:  # JVM frozen: requests keep arriving (they queue), nothing is acquired or released
            if kind == "arr":
                heapq.heappush(events, (t + rng.expovariate(lam), "arr"))
                waiting.append(t)
                if not any(k == "thaw" and abs(x - (t + hold)) < 1e-9 for x, k in events):
                    heapq.heappush(events, (t + hold, "thaw"))
            elif kind == "rel":
                heapq.heappush(events, (t + hold, kind))
            continue
        if kind == "thaw":
            while free and waiting:
                free -= 1
                waits.append(t - waiting.pop(0))
                heapq.heappush(events, (t + rng.expovariate(1 / s), "rel"))
            continue
        if kind == "arr":
            heapq.heappush(events, (t + rng.expovariate(lam), "arr"))
            if free:
                free -= 1
                waits.append(0.0)
                heapq.heappush(events, (t + rng.expovariate(1 / s), "rel"))
            else:
                waiting.append(t)
        else:
            while waiting and t - waiting[0] > timeout:
                waiting.pop(0)
                timeouts += 1
            if waiting:
                arrived = waiting.pop(0)
                waits.append(t - arrived)
                heapq.heappush(events, (t + rng.expovariate(1 / s), "rel"))
            else:
                free += 1
    waits.sort()
    return {"wait": sum(waits) / len(waits), "p99": waits[int(0.99 * (len(waits) - 1))],
            "pending": pend_area / last, "timeouts": timeouts, "n": len(waits)}


def main():
    checks = []
    lam, s = 400.0, 0.020  # 400 req/s each holding a connection 20 ms -> offered load 8 connections
    print(f"== 1. Erlang-C model vs simulation: lambda={lam:.0f}/s, hold S={s * 1000:.0f} ms, offered load "
          f"a = lambda*S = {lam * s:.1f} connections ==")
    print(f"{'pool c':>6} {'util':>6} {'P(wait)':>8} {'model wait ms':>13} {'sim wait ms':>11} {'sim p99 ms':>10} "
          f"{'model pending':>13} {'sim pending':>11}")
    for c in (9, 10, 12, 16, 32):
        m = model(lam, s, c)
        r = simulate(lam, s, c)
        print(f"{c:>6} {m['util']:>6.0%} {m['p_wait']:>8.1%} {m['wait'] * 1000:>13.2f} {r['wait'] * 1000:>11.2f} "
              f"{r['p99'] * 1000:>10.1f} {m['pending']:>13.2f} {r['pending']:>11.2f}")
        if c in (10, 12, 16):
            checks.append((f"sim~model c={c}", abs(r["wait"] - m["wait"]) <= 0.25 * m["wait"] + 0.0005))
    print("-> the default maximumPoolSize=10 at 80% utilization already makes ~40% of requests wait;")
    print("   12-16 connections make waiting rare. Size from Little's law: c >= lambda*S / target_util.")
    print()

    print("== 2. A 300 ms stop-the-world GC pause every 10 s (c=12) ==")
    base = simulate(lam, s, 12)
    gc = simulate(lam, s, 12, gc_pause=(10.0, 0.3))
    print(f"no GC:   mean wait {base['wait'] * 1000:.2f} ms, p99 {base['p99'] * 1000:.1f} ms, avg pending {base['pending']:.2f}")
    print(f"with GC: mean wait {gc['wait'] * 1000:.2f} ms, p99 {gc['p99'] * 1000:.1f} ms, avg pending {gc['pending']:.2f}")
    print("-> after every pause ~120 queued requests hit a pool of 12 at once; acquire p99 jumps although the DB was idle.")
    print("   Correlate hikaricp_connections_acquire_seconds with jvm_gc_pause_seconds before blaming the database.")
    checks.append(("gc inflates p99", gc["p99"] > 3 * base["p99"]))
    print()

    print("== 3. 'Switch to virtual threads' with the same pool (c=10) and 2x traffic ==")
    vt = simulate(800.0, s, 10, seconds=120)
    m2 = model(800.0, s, 10)
    print(f"offered load {800 * s:.0f} connections > pool 10: model says unstable ({m2['util']:.0%});")
    print(f"simulation: mean wait {vt['wait']:.2f} s, p99 {vt['p99']:.1f} s, pending ~{vt['pending']:.0f}, "
          f"timeouts {vt['timeouts']:,} in 120 s")
    print("-> virtual threads remove the thread-pool cap, so ALL requests reach the connection pool: the bottleneck")
    print("   (and hikaricp_connections_pending) moves to the pool and the database. Throughput is still c / S.")
    checks.append(("vt overload", vt["timeouts"] > 0 and vt["pending"] > 100))
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:hikari_pool_lab.py -->
```text
== 1. Erlang-C model vs simulation: lambda=400/s, hold S=20 ms, offered load a = lambda*S = 8.0 connections ==
pool c   util  P(wait) model wait ms sim wait ms sim p99 ms model pending sim pending
     9    89%    65.3%         13.07       12.74       82.4          5.23        5.09
    10    80%    40.9%          4.09        4.42       39.4          1.64        1.77
    12    67%    14.0%          0.70        0.67       12.5          0.28        0.27
    16    50%     0.9%          0.02        0.02        0.0          0.01        0.01
    32    25%     0.0%          0.00        0.00        0.0          0.00        0.00
-> the default maximumPoolSize=10 at 80% utilization already makes ~40% of requests wait;
   12-16 connections make waiting rare. Size from Little's law: c >= lambda*S / target_util.

== 2. A 300 ms stop-the-world GC pause every 10 s (c=12) ==
no GC:   mean wait 0.67 ms, p99 12.5 ms, avg pending 0.27
with GC: mean wait 13.26 ms, p99 253.9 ms, avg pending 5.34
-> after every pause ~120 queued requests hit a pool of 12 at once; acquire p99 jumps although the DB was idle.
   Correlate hikaricp_connections_acquire_seconds with jvm_gc_pause_seconds before blaming the database.

== 3. 'Switch to virtual threads' with the same pool (c=10) and 2x traffic ==
offered load 16 connections > pool 10: model says unstable (100%);
simulation: mean wait 19.94 s, p99 30.0 s, pending ~16032, timeouts 12,231 in 120 s
-> virtual threads remove the thread-pool cap, so ALL requests reach the connection pool: the bottleneck
   (and hikaricp_connections_pending) moves to the pool and the database. Throughput is still c / S.

checks: 5/5 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 Spring Boot 4.1 `application.yaml` for metrics

```yaml
spring:
  application:
    name: checkout
  threads:
    virtual:
      enabled: true                       # virtual threads for request handling (JDK 21+)
  datasource:
    hikari:
      pool-name: main
      maximum-pool-size: 16               # from Little's law: lambda*S/0.6 per replica, DB-capped
      minimum-idle: 16                    # fixed-size pool: no connection churn under load
      connection-timeout: 2000            # ms; fail fast instead of 30 s default queueing
      max-lifetime: 1500000               # 25 min, below DB/proxy idle cutoffs
      leak-detection-threshold: 20000     # ms; logs stack of connections held > 20 s
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
  metrics:
    tags:
      application: ${spring.application.name}
    distribution:
      percentiles-histogram:
        http.server.requests: true        # classic buckets for histogram_quantile
        hikaricp.connections.acquire: true
        jvm.gc.pause: true
      slo:
        http.server.requests: 100ms,300ms,1s   # SLO thresholds become exact bucket boundaries
      minimum-expected-value:
        http.server.requests: 5ms
      maximum-expected-value:
        http.server.requests: 10s
  prometheus:
    metrics:
      export:
        enabled: true
```

### 2.2 JVM flags for containers

```yaml
# Deployment container env (excerpt)
env:
  - name: JAVA_TOOL_OPTIONS
    value: >-
      -XX:MaxRAMPercentage=70
      -XX:ActiveProcessorCount=2
      -XX:+UseZGC
      -Xlog:gc*,safepoint:file=/tmp/gc.log:time,uptime,level,tags:filecount=5,filesize=20m
      -XX:NativeMemoryTracking=summary
      -XX:+ExitOnOutOfMemoryError
resources:
  requests: {cpu: "2", memory: 4Gi}
  limits: {memory: 4Gi}                   # no CPU limit; ActiveProcessorCount pins ergonomics to the request
```

### 2.3 JVM and pool alert rules

```yaml
groups:
  - name: jvm.rules
    interval: 30s
    rules:
      - record: application:jvm_gc_pause_seconds:ratio_rate5m
        expr: sum by (application, pod) (rate(jvm_gc_pause_seconds_sum[5m]))
      - record: application_pool:hikaricp_utilisation:ratio
        expr: |
          sum by (application, pod, pool) (rate(hikaricp_connections_usage_seconds_sum[5m]))
            / max by (application, pod, pool) (hikaricp_connections_max)
  - name: jvm.alerts
    rules:
      - alert: JvmGcPauseTimeHigh
        expr: application:jvm_gc_pause_seconds:ratio_rate5m > 0.05
        for: 15m
        labels: {severity: ticket}
        annotations:
          summary: "{{ $labels.application }}/{{ $labels.pod }} spends {{ $value | humanizePercentage }} of wall time in GC pauses"
      - alert: JvmLiveSetGrowing
        expr: |
          deriv(min_over_time(jvm_gc_live_data_size_bytes[30m])[6h:30m]) > 0
            and jvm_gc_live_data_size_bytes / jvm_gc_max_data_size_bytes > 0.7
        for: 1h
        labels: {severity: ticket}
      - alert: HikariPoolSaturated
        expr: |
          application_pool:hikaricp_utilisation:ratio > 0.8
            and on (application, pod, pool) max by (application, pod, pool) (hikaricp_connections_pending) > 0
        for: 10m
        labels: {severity: ticket}
      - alert: HikariAcquireTimeouts
        expr: sum by (application, pool) (increase(hikaricp_connections_timeout_total[5m])) > 0
        labels: {severity: warning}
      - alert: VirtualThreadPinning
        expr: sum by (application) (rate(jvm_threads_virtual_pinned_seconds_sum[5m])) > 0.1
        for: 15m
        labels: {severity: ticket}
        annotations:
          summary: "{{ $labels.application }}: virtual threads pinned {{ $value }}s per second (JDK 21-23 synchronized I/O?)"
```

---

## 3. Failure modes and FinOps debugging

### F1. "The database is slow" — actually GC

**Symptom.** p99 latency and `hikaricp_connections_acquire_seconds` spike periodically; the DBA sees idle databases.

**Signature.** Acquire-time spikes align with `jvm_gc_pause_seconds_max` spikes; `hikaricp_connections_pending` jumps right after each pause.

**Root cause.** A stop-the-world pause freezes request processing; arrivals queue and then hit the pool simultaneously (L3 §2: p99 12.5 → 254 ms).

**Fix.** Reduce pause times (heap sizing, ZGC/G1 tuning, allocation reduction); size the pool for post-pause bursts.

**Prevention.** Dashboards overlay GC pauses on pool and latency panels; runbooks check GC first.

### F2. Pool exhaustion after enabling virtual threads

**Symptom.** After `spring.threads.virtual.enabled=true`, load tests show timeouts and database CPU at 100% at traffic the old version handled.

**Signature.** `hikaricp_connections_pending` in the thousands; `hikaricp_connections_timeout_total` rising; concurrent DB sessions at the pool max across all replicas.

**Root cause.** Platform threads used to cap in-flight requests (Tomcat's thread limit); virtual threads remove the cap, so the pool and the database absorb unbounded concurrency (L3 §3).

**Fix.** A semaphore/bulkhead limiting concurrent DB work to ≈ the pool size; fail-fast `connection-timeout`; load-shed at the edge.

**Prevention.** Capacity tests that compare platform- and virtual-thread modes; an alert on pending > c.

### F3. OOMKilled JVM with a "small" heap

**Symptom.** Pods OOMKilled with `-Xmx` at 50% of the limit.

**Signature.** `jvm_memory_used_bytes{area="heap"}` well below max; container RSS (File 2) at the limit; NMT shows large `Thread`, `Internal` (direct buffers) or `Code` sections.

**Root cause.** Off-heap memory: thread stacks (thousands of platform threads), Netty direct buffers, metaspace from class generation.

**Fix.** Cap `MaxDirectMemorySize`, reduce platform threads (or move to virtual threads), set `MaxRAMPercentage` with an off-heap budget.

**Prevention.** Export NMT summaries or use `jvm_buffer_memory_used_bytes` and the `nonheap` area; alert on RSS vs limit.

### F4. Oversized thread pools on huge hosts

**Symptom.** A service with a 2-core request runs 128 GC threads and 127 ForkJoin workers on a 128-core node; latency suffers under contention.

**Signature.** `system_cpu_count` (from Micrometer's `ProcessorMetrics`) = 128 in a 2-core pod; high `jvm_threads_live_threads`; throttling if limits exist.

**Root cause.** Without a CPU limit, the JVM sizes ergonomics to host cores.

**Fix.** `-XX:ActiveProcessorCount=<request>`; size application pools explicitly.

**Prevention.** Platform base images set `ActiveProcessorCount` from the downward API.

### F5. Pool sized by folklore

**Symptom.** "Max pool size 100 for safety" on 40 replicas; the database hits `max_connections` during deploys.

**Signature.** `sum(hikaricp_connections)` across replicas > DB `max_connections`; DB errors "too many connections" during rollouts (old + new pods).

**Root cause.** Pools sized without Little's law or a global DB budget; rollouts temporarily double replicas.

**Fix.** Per-replica pool = λ·S/ρ (L3), global budget = pool × max replicas during surge ≤ DB limit; use a proxy (PgBouncer) if needed.

**Prevention.** Capacity review per service: the DB connection budget is a shared resource with an owner.

### F6. Zero pause, high latency on ZGC

**Symptom.** After moving to ZGC, pause metrics are near zero but latency still has spikes.

**Signature.** Allocation rate near the collector's throughput; GC logs show "Allocation Stall"; concurrent GC CPU high; CPU throttling.

**Root cause.** Concurrent collectors trade pauses for allocation stalls and CPU when allocation outpaces collection.

**Fix.** More heap headroom or CPU for GC threads; reduce allocation rate.

**Prevention.** Alert on allocation rate vs heap and on GC CPU (`jvm_gc_overhead`), not only pauses.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "Size the HikariCP pool for this service."</b></summary>

**Initial Prompt.** 400 req/s per replica, each holding a connection ~20 ms. Pool size?

**L5 Textbook Answer.** The HikariCP wiki says `cores × 2 + spindles`, so about 10.

**Why L5 Fails at 3 AM or on the Bill.** That formula sizes the *database's* useful concurrency, not a pool's queueing behaviour at a given λ and S; at 80% utilization 41% of requests wait (L3).

**L7 Principal Defense.** Offered load a = λS = 8 connections; Erlang C gives P(wait) and W_q per c; I'd pick c = 12–16 (P(wait) 14% → 1%), then check the global constraint: c × max replicas (including rollout surge) ≤ the DB's effective concurrency, which is where the wiki's formula applies. If the global budget can't fit, reduce S (query tuning) or add a pooling proxy. Validate with `hikaricp_connections_pending` and acquire p99 after rollout.
</details>

<details><summary><b>Q2 · "Our GC pause metrics are fine but latency spikes. What else?"</b></summary>

**Initial Prompt.** ZGC pauses are under 1 ms; p99 still spikes to 300 ms.

**L5 Textbook Answer.** Then it's not GC; look at the database.

**Why L5 Fails at 3 AM or on the Bill.** Concurrent collectors move cost from pauses to allocation stalls and CPU; pause metrics are blind to both.

**L7 Principal Defense.** Check allocation stalls in GC logs, GC CPU (`jvm_gc_overhead`, `jvm_gc_cpu_time_seconds_total`), CPU throttling (GC threads compete with app threads under quota — File 2), and time-to-safepoint. Then the pool and executors. The order: CPU quota → GC CPU/stalls → pool pending → DB.
</details>

<details><summary><b>Q3 · "Virtual threads: what changes in monitoring?"</b></summary>

**Initial Prompt.** We're moving to virtual threads. Update the dashboards.

**L5 Textbook Answer.** Thread-pool metrics go away since virtual threads are cheap; nothing else changes.

**Why L5 Fails at 3 AM or on the Bill.** The thread cap that used to bound concurrency disappears; saturation moves to pools and downstreams (L3 §3), and pinning becomes a new failure mode on JDK 21–23.

**L7 Principal Defense.** Remove Tomcat busy-thread saturation; add `jvm_threads_virtual_pinned_seconds`, submit failures, carrier pool size/parallelism; promote `hikaricp_connections_pending` and an explicit concurrency-limiter metric to saturation signals; load-test platform vs virtual threads at 2× peak. On JDK 24+ pinning on `synchronized` is gone (JEP 491), so pinning alerts mostly flag native frames.
</details>

<details><summary><b>Q4 · "Heap usage is at 90%. Page someone?"</b></summary>

**Initial Prompt.** An alert fires at 90% heap used.

**L5 Textbook Answer.** Yes, the JVM might run out of memory soon.

**Why L5 Fails at 3 AM or on the Bill.** Heap used oscillates by design (collectors let it fill before collecting); 90% before a collection is normal and the alert is pure noise.

**L7 Principal Defense.** The signals are live set after GC relative to max (leak/sizing), GC time fraction (thrash) and allocation stalls. I alert on live-set growth over hours and GC overhead > 5–10%, and never on instantaneous heap used.
</details>

<details><summary><b>Q5 · "Why do our JVMs get OOMKilled with 50% heap?"</b></summary>

**Initial Prompt.** -Xmx is 2 GiB, limit 4 GiB, still OOMKilled.

**L5 Textbook Answer.** Increase the limit to give more headroom.

**Why L5 Fails at 3 AM or on the Bill.** Without finding the off-heap consumer, the limit increase just delays the kill and raises cost.

**L7 Principal Defense.** RSS = heap + metaspace + code cache + threads × stack + direct buffers + GC overhead. Enable NMT, compare categories, check thread counts (`jvm_threads_live_threads` × 1 MiB stacks) and Netty/NIO direct memory (`jvm_buffer_memory_used_bytes`). Fix the consumer (bounded direct memory, fewer platform threads), then set `MaxRAMPercentage` leaving an explicit off-heap budget.
</details>

<details><summary><b>Q6 · "What's the single best saturation signal for a Spring Boot service?"</b></summary>

**Initial Prompt.** One metric to tell me the service is at capacity.

**L5 Textbook Answer.** CPU usage.

**Why L5 Fails at 3 AM or on the Bill.** CPU is one of five queues; most Java services saturate on the connection pool or executor long before CPU.

**L7 Principal Defense.** There isn't one; there is "the first full queue". I expose each stage's waiting count (Tomcat busy/max or a concurrency limiter, executor queued tasks, Hikari pending) plus CPU throttling and GC time, and compute a single derived "saturation" panel as the max of normalised ratios — but alerts stay on SLO burn.
</details>

<details><summary><b>Q7 · "Should we enable percentiles-histogram for every timer?"</b></summary>

**Initial Prompt.** Histograms everywhere for better p99s?

**L5 Textbook Answer.** Yes, histograms give accurate percentiles.

**Why L5 Fails at 3 AM or on the Bill.** Micrometer's default histogram has dozens of buckets; enabled on every timer × every tag combination (uri × method × status × outcome × exception), it multiplies series — a cardinality incident (Folder 01 File 2).

**L7 Principal Defense.** Histograms only on SLO-relevant timers (http.server.requests, key client calls, pool acquire), with `minimum/maximum-expected-value` to trim buckets and `slo` boundaries at thresholds; strict tag hygiene (`uri` templates, no exception messages); or native histograms via OTel/Prometheus where supported, which collapse buckets into one series.
</details>

<details><summary><b>Q8 · "How do you prove pool sizing changes worked?"</b></summary>

**Initial Prompt.** We raised the pool from 10 to 16. Did it help?

**L5 Textbook Answer.** Check whether latency went down.

**Why L5 Fails at 3 AM or on the Bill.** Latency moves with traffic, GC and deploys; without the queue's own metrics the change can't be attributed, and it may have just shifted load to the DB.

**L7 Principal Defense.** Compare before/after at matched λ: utilisation ratio (usage_sum/max), P(wait) ≈ fraction of acquisitions with non-zero wait (from the acquire histogram's first bucket), acquire p99 and pending — against the Erlang-C prediction (L3). Then check the DB side (active sessions, CPU, lock waits) to confirm the bottleneck didn't just move.
</details>

---

## 5. Invariants checklist

- [ ] Pools are sized with Little's law/Erlang C per replica and a global DB connection budget that includes rollout surge.
- [ ] `connection-timeout` is seconds, not the 30 s default, for user-facing paths; timeouts are counted and alerted.
- [ ] GC pauses are overlaid on pool, executor and latency panels; GC time fraction and live-set growth are alerted, heap-used is not.
- [ ] Containers set `MaxRAMPercentage` with an explicit off-heap budget and `ActiveProcessorCount` when CPU limits are absent.
- [ ] Virtual-thread services have a concurrency limiter sized to downstream capacity and monitor pinning (JDK 21–23).
- [ ] Histograms are enabled only on SLO-relevant timers with trimmed bucket ranges and SLO boundaries.
- [ ] `uri` tags are templates; exception tags are class names, never messages.

---

## 6. References

- Micrometer JVM binders (v1.17.2): <https://github.com/micrometer-metrics/micrometer/tree/v1.17.2/micrometer-core/src/main/java/io/micrometer/core/instrument/binder/jvm>
- Micrometer `VirtualThreadMetrics`: <https://github.com/micrometer-metrics/micrometer/blob/v1.17.2/micrometer-java21/src/main/java/io/micrometer/java21/instrument/binder/jdk/VirtualThreadMetrics.java>
- HikariCP Micrometer tracker (7.1.0): <https://github.com/brettwooldridge/HikariCP/blob/HikariCP-7.1.0/src/main/java/com/zaxxer/hikari/metrics/micrometer/MicrometerMetricsTracker.java>
- HikariCP "About Pool Sizing": <https://github.com/brettwooldridge/HikariCP/wiki/About-Pool-Sizing>
- Spring Boot actuator metrics reference: <https://docs.spring.io/spring-boot/reference/actuator/metrics.html>
- JEP 444 Virtual Threads: <https://openjdk.org/jeps/444>; JEP 491 Synchronize Virtual Threads without Pinning: <https://openjdk.org/jeps/491>
- JEP 439 Generational ZGC: <https://openjdk.org/jeps/439>
