# 02 · Kubernetes Monitoring: kube-state-metrics, cAdvisor, CFS Throttling and OOMs

> **Folder 03 — What to Monitor: Complete Enterprise Taxonomy · File 2 of 4.**
> Pinned to **kube-state-metrics v2.20.0** (2026-08-18), **cAdvisor v0.60.6** (2026-09-18; metric names read from `lib/metrics/prometheus.go`), Prometheus v3.15.1.
> Labels: **[D]** documented / read in pinned source · **[M]** measured by the listing (deterministic, re-run by the gate) · **[E]** model · **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L2 `cfs_throttling_sim.py` | Linux CFS bandwidth control (100 ms period, quota = limit × period, optional `cpu.max.burst`) at 1 ms resolution for a fan-out service averaging 0.8 cores: throttled-period ratio and p50/p99 latency under limits of none/4/2/1.5/1 cores and 2 cores + burst; what cAdvisor's counters show over 5 minutes; kubelet allocatable and memory overcommit arithmetic | <1 s |

**Verification.** The simulator implements the CFS bandwidth rules as documented in the kernel's `sched-bwc` documentation (quota per period, whole-cgroup throttling until the next period, burst carry-over bounded by the burst size). Results are a model [E/M]: they reproduce the well-known "throttled at low average utilization" effect quantitatively for a stated workload; they are not measurements of a real kernel. Metric names are from the pinned sources.

---

## 0. Orientation

**What this file answers.** Which Kubernetes signals come from where, how to detect the four classic Kubernetes failure modes — CPU throttling, OOM kills, scheduling failure, crash loops — and which "obvious" metrics are misleading.

**Three sources, three questions [D].**

| Source | What it exposes | Answers |
|---|---|---|
| **kube-state-metrics** (KSM) | Object *desired/declared state* from the API server: `kube_pod_status_phase`, `kube_pod_container_status_restarts_total`, `kube_pod_container_status_last_terminated_reason`, `kube_pod_container_resource_requests/limits`, `kube_deployment_status_replicas_available`, `kube_node_status_condition`, `kube_pod_owner`, `kube_pod_info`… | "Is Kubernetes doing what we asked?" |
| **cAdvisor** (in the kubelet, `/metrics/cadvisor`) | Container *actual usage* from cgroups: `container_cpu_usage_seconds_total`, `container_cpu_cfs_periods_total`, `container_cpu_cfs_throttled_periods_total`, `container_cpu_cfs_throttled_seconds_total`, `container_cpu_cfs_burst_periods_total`, `container_memory_working_set_bytes`, `container_memory_rss`, `container_oom_events_total`, `container_pressure_{cpu,memory,io}_{waiting,stalled}_seconds_total` | "What are containers consuming, and are they starved?" |
| **kubelet / control plane** (`/metrics`, apiserver, scheduler, etcd) | Node agent and control-plane health: request latencies, admission, scheduling attempts, etcd fsync | "Is the platform itself healthy?" |

The joins between them (pod → node → owner → team) are done with `group_left` against KSM info metrics (Folder 02 File 2 §2.1).

---

## 1. First principles: how limits actually bite

### 1.1 CPU requests vs limits under CFS

- **Requests** set `cpu.weight` (cgroup v2): a *proportional share* under contention, never a cap. They also drive scheduling.
- **Limits** set `cpu.max` = `quota period`, with the default period **100 ms**. A container limited to 2 cores may use 200 ms of CPU per 100 ms period *across all its threads*; once spent, **every thread waits** for the next period.

```text
 limit 2 cores → quota 200 ms per 100 ms period;  8 worker threads; burst of fan-out work at t=0
 t=0ms    8 threads run in parallel → consume 8 ms of quota per ms
 t=25ms   quota exhausted (200 ms used)  ──► THROTTLED: all threads parked
 t=100ms  new period: quota refilled ──► next 8 tasks run … throttled again at t=125ms
 average over a minute: 0.8 cores used = 40% of the limit, yet ~35% of periods throttled
```

L2 §1 for a service averaging 0.8 cores (16 tasks of 20–30 ms every 500 ms, 8-thread pool) [M]:

| Limit | Use / limit | Throttled periods | p50 | p99 |
|---|---|---|---|---|
| none | — | 0% | 30 ms | 59 ms |
| 4 cores | 20% | **15.3%** | 30 ms | 107 ms |
| 2 cores | 41% | **35.3%** | 105 ms | **207 ms** |
| 2 cores + 200 ms burst | 41% | 15.3% | 30 ms | 107 ms |
| 1 core | 82% | 74.9% | 205 ms | 407 ms |

- **Throttling happens at low average utilization** whenever parallelism × burst duration exceeds the quota; a 4-core limit throttles a service using 20% of it because 8 threads can run.
- **The latency cost is in 100 ms quanta**: a throttled request waits for the next period.
- **`cpu.max.burst`** (cgroup v2; Kubernetes support is ⚠ version/feature-gate dependent) lets unused quota carry over and recovers most of the latency; cAdvisor reports its use as `container_cpu_cfs_burst_periods_total`/`_seconds_total`.
- **The fix space**: remove CPU limits for latency-sensitive services (keep requests accurate, rely on `cpu.weight`); size limits for peak parallelism; cap thread pools to the limit (the JVM sees `availableProcessors()` from the quota — File 3); use burst.

### 1.2 Memory: working set, RSS and the OOM killer

```text
 container_memory_usage_bytes        = RSS + page cache (+ kernel memory)      ← includes reclaimable cache
 container_memory_working_set_bytes  = usage − inactive_file                   ← what the kubelet uses for eviction
 container_memory_rss                = anonymous memory                         ← what the OOM killer must reclaim
 limit (memory.max) exceeded by non-reclaimable memory  →  kernel OOM kill  →  container_oom_events_total +1,
                                                         kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}
 node memory.available < evictionHard  →  kubelet EVICTION (pod status Failed, reason Evicted), BestEffort first
```

- **Working set** is the right "usage" for limits and eviction; **RSS** growing towards the limit is the OOM predictor. Page cache counted in usage is reclaimable and not a leak.
- **OOM kill vs eviction** are different events with different signals: OOM is a kernel decision *inside* the container's cgroup (restart, same pod); eviction is a kubelet decision under *node* pressure (pod replaced, maybe elsewhere).
- **Allocatable arithmetic** (L2 §3): capacity − kube-reserved − system-reserved − eviction threshold. Scheduling packs by requests, so limits can overcommit the node (185% in the example) — safe only if peaks don't coincide.

### 1.3 Workload-level health from KSM

| Question | Expression (KSM v2.20 names) |
|---|---|
| Crash looping? | `increase(kube_pod_container_status_restarts_total[15m]) > 3` plus `kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} == 1` |
| OOM killed? | `kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}` changing, or `increase(container_oom_events_total[15m]) > 0` |
| Rollout stuck? | `kube_deployment_spec_replicas != kube_deployment_status_replicas_available` for > 15 m, with `kube_deployment_status_observed_generation` behind `metadata_generation` |
| Pods unschedulable? | `kube_pod_status_unschedulable == 1` or `kube_pod_status_phase{phase="Pending"}` for > 15 m |
| Node unhealthy? | `kube_node_status_condition{condition="Ready",status="true"} == 0`, `{condition=~"MemoryPressure|DiskPressure|PIDPressure",status="true"} == 1` |
| Requests vs usage (rightsizing) | `sum by (namespace, pod) (rate(container_cpu_usage_seconds_total{container!=""}[30m]))` vs `sum by (namespace, pod) (kube_pod_container_resource_requests{resource="cpu"})` |

### 1.4 cAdvisor label hygiene

cAdvisor emits series at several cgroup levels; `container=""` (and `container="POD"` on older runtimes) are **pod-level aggregates** and the pause container. Summing without `container!=""` double-counts. `image`, `id` and `name` labels are high-cardinality and should be dropped at scrape time (Folder 01 File 4 §2.1 keeps only the needed families).

<!-- listing:cfs_throttling_sim.py -->
```python
"""cfs_throttling_sim.py - Linux CFS bandwidth control (cpu.max quota/period) simulated at 1 ms
resolution for a bursty multi-threaded service, reproducing what cAdvisor reports as
container_cpu_cfs_periods_total / container_cpu_cfs_throttled_periods_total, plus the latency
damage, and the kubelet allocatable/eviction arithmetic for memory.

Model: period 100 ms; quota = limit_cores x 100 ms of CPU per period shared by all threads; when
the quota is spent the whole cgroup waits for the next period. cpu.max.burst (cfs_burst) lets
unused quota carry over up to `burst` ms. Work arrives in batches (a fan-out request every 500 ms
spawning 16 tasks of 25 ms on an 8-thread pool): average demand 0.8 cores.
Deterministic, stdlib only.

Usage: python cfs_throttling_sim.py [target.md]
"""
import random
import sys

PERIOD = 100  # ms


def simulate(limit_cores, threads=8, burst_ms=0, seconds=120, seed=1):
    rng = random.Random(seed)
    queue, running, lat, used_total = [], [], [], 0.0
    periods = throttled = 0
    quota = limit_cores * PERIOD if limit_cores else None
    budget = quota
    carry = 0.0
    for t in range(seconds * 1000):
        if t % PERIOD == 0:
            periods += 1
            if quota is not None:
                carry = min(burst_ms, carry + budget) if burst_ms else 0.0
                budget = quota + carry
                carry = 0.0
            period_throttled = False
        if t % 500 == 0:
            for _ in range(16):
                queue.append([t, rng.uniform(20, 30)])
        while queue and len(running) < threads:
            running.append(queue.pop(0))
        if not running:
            continue
        if quota is not None and budget <= 0:
            if not period_throttled:
                throttled += 1
                period_throttled = True
            continue
        n = len(running)
        share = 1.0 if quota is None else min(1.0, budget / n)
        for task in running:
            task[1] -= share
        used = share * n
        used_total += used
        if quota is not None:
            budget -= used
            if (t + 1) % PERIOD == 0 and budget > 0 and burst_ms:
                carry = budget  # unused quota may carry over (bounded by burst)
        done = [x for x in running if x[1] <= 1e-9]
        for x in done:
            lat.append(t + 1 - x[0])
        running = [x for x in running if x[1] > 1e-9]
    lat.sort()
    p = lambda q: lat[int(q * (len(lat) - 1))]  # noqa: E731
    return {"avg_cores": used_total / (seconds * 1000), "throttle_ratio": throttled / periods,
            "p50": p(0.5), "p99": p(0.99), "n": len(lat)}


def main():
    checks = []
    print("== 1. Same workload (avg 0.8 cores), different CPU limits ==")
    print(f"{'limit':>16} {'avg cores':>9} {'util of limit':>13} {'throttled periods':>17} {'p50 ms':>7} {'p99 ms':>7}")
    res = {}
    for name, lim, burst in (("none", 0, 0), ("4 cores", 4, 0), ("2 cores", 2, 0), ("1.5 cores", 1.5, 0),
                             ("2 cores + burst", 2, 200), ("1 core", 1, 0)):
        r = simulate(lim, burst_ms=burst)
        res[name] = r
        util = f"{r['avg_cores'] / lim:.0%}" if lim else "-"
        print(f"{name:>16} {r['avg_cores']:>9.2f} {util:>13} {r['throttle_ratio']:>17.1%} {r['p50']:>7.0f} {r['p99']:>7.0f}")
    checks.append(("throttled at 40% of limit", res["2 cores"]["throttle_ratio"] > 0.1 and res["2 cores"]["avg_cores"] / 2 < 0.45))
    checks.append(("p99 penalty", res["2 cores"]["p99"] > 1.5 * res["none"]["p99"]))
    checks.append(("burst helps", res["2 cores + burst"]["p99"] < res["2 cores"]["p99"]))
    print("-> 'CPU usage 40% of limit' and '20%+ of periods throttled' are both true: the average hides")
    print("   100 ms-scale bursts. Alert on the throttled-periods RATIO and on latency, not on usage/limit.")
    print()

    print("== 2. What the PromQL sees (cAdvisor counters over 5m) ==")
    r = res["2 cores"]
    periods_5m = 300_000 / PERIOD
    print(f"increase(container_cpu_cfs_periods_total[5m])           ~= {periods_5m:.0f}")
    print(f"increase(container_cpu_cfs_throttled_periods_total[5m]) ~= {periods_5m * r['throttle_ratio']:.0f}")
    print(f"ratio = {r['throttle_ratio']:.1%}   rate(container_cpu_usage_seconds_total[5m]) ~= {r['avg_cores']:.2f}")
    print()

    print("== 3. Node allocatable and eviction arithmetic (kubelet) ==")
    cap_gib, kube_res, sys_res, evict_hard = 64.0, 2.0, 1.0, 0.5
    alloc = cap_gib - kube_res - sys_res - evict_hard
    print(f"capacity {cap_gib} GiB - kube-reserved {kube_res} - system-reserved {sys_res} - evictionHard "
          f"memory.available<{evict_hard}Gi = allocatable {alloc} GiB")
    requests = [4.0] * 14
    limits = [8.0] * 14
    print(f"14 pods x request 4 GiB = {sum(requests)} GiB scheduled (fits); limits sum {sum(limits)} GiB = "
          f"{sum(limits) / alloc:.0%} of allocatable -> overcommit: under pressure the kubelet evicts BestEffort, then "
          f"Burstable pods exceeding requests; the kernel OOM-kills a container that exceeds its own limit")
    checks.append(("overcommit", sum(limits) > alloc >= sum(requests)))
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:cfs_throttling_sim.py -->
```text
== 1. Same workload (avg 0.8 cores), different CPU limits ==
           limit avg cores util of limit throttled periods  p50 ms  p99 ms
            none      0.82             -              0.0%      30      59
         4 cores      0.82           20%             15.3%      30     107
         2 cores      0.82           41%             35.3%     105     207
       1.5 cores      0.82           54%             40.0%     112     222
 2 cores + burst      0.82           41%             15.3%      30     107
          1 core      0.82           82%             74.9%     205     407
-> 'CPU usage 40% of limit' and '20%+ of periods throttled' are both true: the average hides
   100 ms-scale bursts. Alert on the throttled-periods RATIO and on latency, not on usage/limit.

== 2. What the PromQL sees (cAdvisor counters over 5m) ==
increase(container_cpu_cfs_periods_total[5m])           ~= 3000
increase(container_cpu_cfs_throttled_periods_total[5m]) ~= 1060
ratio = 35.3%   rate(container_cpu_usage_seconds_total[5m]) ~= 0.82

== 3. Node allocatable and eviction arithmetic (kubelet) ==
capacity 64.0 GiB - kube-reserved 2.0 - system-reserved 1.0 - evictionHard memory.available<0.5Gi = allocatable 60.5 GiB
14 pods x request 4 GiB = 56.0 GiB scheduled (fits); limits sum 112.0 GiB = 185% of allocatable -> overcommit: under pressure the kubelet evicts BestEffort, then Burstable pods exceeding requests; the kernel OOM-kills a container that exceeds its own limit

checks: 4/4 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 Recording rules (kubernetes-mixin style)

```yaml
groups:
  - name: k8s-container.rules
    interval: 30s
    rules:
      - record: namespace_pod_container:container_cpu_usage_seconds_total:sum_rate5m
        expr: |
          sum by (cluster, namespace, pod, container) (
            rate(container_cpu_usage_seconds_total{job="kubelet", metrics_path="/metrics/cadvisor", container!=""}[5m])
          )
      - record: namespace_pod_container:container_cpu_cfs_throttled:ratio_rate5m
        expr: |
          sum by (cluster, namespace, pod, container) (rate(container_cpu_cfs_throttled_periods_total{container!=""}[5m]))
            / sum by (cluster, namespace, pod, container) (rate(container_cpu_cfs_periods_total{container!=""}[5m]))
      - record: namespace_pod_container:container_memory_working_set_bytes:max
        expr: max by (cluster, namespace, pod, container) (container_memory_working_set_bytes{container!=""})
      - record: namespace_pod_container:container_memory_limit_utilisation:ratio
        expr: |
          namespace_pod_container:container_memory_working_set_bytes:max
            / on (cluster, namespace, pod, container)
          max by (cluster, namespace, pod, container) (kube_pod_container_resource_limits{resource="memory"} > 0)
      - record: namespace_pod_container:container_pressure_cpu_waiting:rate5m
        expr: |
          sum by (cluster, namespace, pod, container) (
            rate(container_pressure_cpu_waiting_seconds_total{container!=""}[5m])
          )
```

### 2.2 Kubernetes alerts that page on impact

```yaml
groups:
  - name: k8s.alerts
    rules:
      - alert: ContainerCPUThrottledHighWithLatencyImpact
        expr: |
          namespace_pod_container:container_cpu_cfs_throttled:ratio_rate5m > 0.25
            and on (namespace, pod)
          max by (namespace, pod) (namespace_pod_container:container_pressure_cpu_waiting:rate5m) > 0.1
        for: 15m
        labels: {severity: ticket}
        annotations:
          summary: "{{ $labels.namespace }}/{{ $labels.pod }}/{{ $labels.container }} throttled {{ $value | humanizePercentage }} of CFS periods"
          runbook: "Raise/remove the CPU limit, cap thread pools to the limit, or enable CFS burst"
      - alert: ContainerOOMKilled
        expr: |
          increase(container_oom_events_total{container!=""}[15m]) > 0
            or (kube_pod_container_status_last_terminated_reason{reason="OOMKilled"} == 1
                and on (namespace, pod, container) increase(kube_pod_container_status_restarts_total[15m]) > 0)
        labels: {severity: warning}
        annotations:
          summary: "{{ $labels.namespace }}/{{ $labels.pod }}/{{ $labels.container }} OOM-killed"
      - alert: ContainerMemoryNearLimit
        expr: namespace_pod_container:container_memory_limit_utilisation:ratio > 0.9
        for: 30m
        labels: {severity: ticket}
      - alert: PodCrashLooping
        expr: |
          max_over_time(kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"}[5m]) >= 1
        for: 15m
        labels: {severity: warning}
      - alert: DeploymentReplicasMismatch
        expr: |
          kube_deployment_spec_replicas != kube_deployment_status_replicas_available
            and changes(kube_deployment_status_replicas_updated[10m]) == 0
        for: 15m
        labels: {severity: warning}
      - alert: PodsPendingTooLong
        expr: |
          sum by (namespace) (kube_pod_status_phase{phase="Pending"}) > 0
            and on (namespace) sum by (namespace) (kube_pod_status_unschedulable) > 0
        for: 15m
        labels: {severity: warning}
      - alert: NodeNotReady
        expr: kube_node_status_condition{condition="Ready", status="true"} == 0
        for: 10m
        labels: {severity: page}
```

### 2.3 kube-state-metrics deployment knobs (v2.20)

```yaml
# kube-state-metrics container args (excerpt)
args:
  - --resources=pods,deployments,statefulsets,daemonsets,replicasets,jobs,cronjobs,nodes,namespaces,persistentvolumeclaims,horizontalpodautoscalers
  - --metric-allowlist=kube_pod_.*,kube_deployment_.*,kube_statefulset_.*,kube_daemonset_.*,kube_node_.*,kube_job_.*,kube_horizontalpodautoscaler_.*,kube_persistentvolumeclaim_.*,kube_replicaset_owner,kube_namespace_labels
  - --metric-labels-allowlist=pods=[app.kubernetes.io/name,app.kubernetes.io/component,team],namespaces=[team,cost-center]
  - --metric-annotations-allowlist=namespaces=[owner]
  # very large clusters: run N shards
  # - --shard=0
  # - --total-shards=3
```

`--metric-labels-allowlist` controls which Kubernetes labels become `kube_pod_labels`/`kube_namespace_labels` labels; allowing `*` imports every label key, including churny ones (`pod-template-hash`), and is a classic cardinality incident.

---

## 3. Failure modes and FinOps debugging

### F1. Latency spikes at 40% CPU usage

**Symptom.** p99 latency doubles at modest load; CPU usage graphs show 30–40% of the limit; adding replicas helps only proportionally.

**Signature.** `namespace_pod_container:container_cpu_cfs_throttled:ratio_rate5m` > 0.2; `container_pressure_cpu_waiting` elevated; latency quantised around 100 ms steps.

**Root cause.** CFS quota exhausted within periods by parallel bursts (L2: 35% of periods throttled at 41% average use).

**Fix.** Remove the CPU limit (keep requests) for latency-sensitive services, or raise it to peak parallelism, or enable burst; cap worker pools to the limit.

**Prevention.** Alert on throttle ratio *with* PSI or latency impact (§2.2); platform policy on CPU limits documented per tier.

### F2. "Memory leak" that is page cache

**Symptom.** A service's memory graph climbs to the limit and plateaus; no OOM kills; teams chase a leak.

**Signature.** `container_memory_usage_bytes` near limit, `container_memory_working_set_bytes` well below, `container_memory_rss` flat.

**Root cause.** File-backed page cache is counted in usage and reclaimed on demand.

**Fix.** Dashboard working set and RSS; never usage.

**Prevention.** Remove `container_memory_usage_bytes` from standard dashboards and alerts.

### F3. OOM kills invisible to the application team

**Symptom.** Pods restart every few hours; application logs show nothing (the process was SIGKILLed).

**Signature.** `kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}`; `container_oom_events_total` increments; RSS rises steadily between restarts.

**Root cause.** RSS exceeded `memory.max`; for JVMs often heap + metaspace + direct buffers + thread stacks > limit (File 3).

**Fix.** Raise the limit, or bound off-heap (JVM `-XX:MaxRAMPercentage`, `MaxDirectMemorySize`); find the leak with heap profiles.

**Prevention.** `ContainerOOMKilled` routed to the owning team with the terminated-reason label; RSS slope alerts.

### F4. Double-counted CPU from cAdvisor's pod-level series

**Symptom.** Namespace CPU usage is ~2× what billing says.

**Signature.** Queries without `container!=""`; both container and pod-level cgroup series summed.

**Root cause.** cAdvisor exposes per-container and aggregate cgroups; summing all levels counts usage twice.

**Fix.** Always filter `container!=""` (and `container!="POD"` on older runtimes); use mixin recording rules.

**Prevention.** Recording rules are the only source for namespace/workload CPU in dashboards and chargeback.

### F5. KSM label explosion

**Symptom.** kube-state-metrics becomes the top cardinality job after an upgrade.

**Signature.** `kube_pod_labels` with hundreds of label keys; `--metric-labels-allowlist=pods=[*]`.

**Root cause.** Every Kubernetes label key and value becomes a Prometheus label, including per-rollout hashes.

**Fix.** Explicit allowlists (§2.3); drop residual series.

**Prevention.** Review KSM flags as part of the platform's cardinality budget.

### F6. Evictions mistaken for crashes

**Symptom.** Pods disappear and reappear on other nodes during busy periods; teams look for crashes.

**Signature.** `kube_pod_status_reason{reason="Evicted"}`; node `MemoryPressure` condition true; working set of BestEffort/Burstable pods above requests.

**Root cause.** Node-level memory pressure crossed `evictionHard`; the kubelet evicted pods exceeding their requests.

**Fix.** Set memory requests ≈ steady-state working set; reserve system memory; spread memory-heavy pods.

**Prevention.** Alert on node pressure conditions and on eviction counts per namespace; rightsizing reviews from the requests-vs-usage panel.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "Why is my service throttled at 30% CPU?"</b></summary>

**Initial Prompt.** The dashboard shows 30% of the CPU limit, yet throttling is high. Bug?

**L5 Textbook Answer.** Averages hide spikes; the service probably bursts above the limit sometimes.

**Why L5 Fails at 3 AM or on the Bill.** Without the CFS mechanics, the fix is "double the limit" — more cost, and still throttled if thread parallelism exceeds it.

**L7 Principal Defense.** CFS enforces quota per 100 ms period across all threads; N runnable threads burn quota N times faster, so a fan-out burst exhausts a 2-core quota in 25 ms and every thread waits ~75 ms (L2: 35% of periods throttled at 41% average use, p99 3.5×). Options by preference: no CPU limit for latency tiers, pool sizes ≤ limit, burst, then a higher limit. Measure success with the throttle ratio and p99, not average CPU.
</details>

<details><summary><b>Q2 · "Should we set CPU limits at all?"</b></summary>

**Initial Prompt.** Platform policy debate: limits everywhere or nowhere?

**L5 Textbook Answer.** Limits prevent noisy neighbours, so set them everywhere.

**Why L5 Fails at 3 AM or on the Bill.** Limits don't protect neighbours — requests do (`cpu.weight`); limits throttle the limited workload even on idle nodes, buying latency loss for no fairness gain.

**L7 Principal Defense.** Requests for every container (scheduling + fair share). No CPU limits for latency-sensitive services, with namespace quotas on requests and alerting on node CPU PSI. CPU limits only where cost isolation or tenant fairness is contractual (batch, multi-tenant). Memory limits always — memory isn't compressible.
</details>

<details><summary><b>Q3 · "OOMKilled vs Evicted — explain the difference and the signals."</b></summary>

**Initial Prompt.** Two pods died; one OOMKilled, one Evicted. Same thing?

**L5 Textbook Answer.** Both are memory problems, one by the kernel and one by Kubernetes.

**Why L5 Fails at 3 AM or on the Bill.** Treating them alike leads to raising limits for evictions (useless — eviction is node pressure) or adding nodes for OOMs (useless — the limit is per container).

**L7 Principal Defense.** OOMKilled: the container exceeded its own `memory.max`; signals `container_oom_events_total` and the terminated reason; fix the limit or the leak. Evicted: the *node* crossed `memory.available < evictionHard`; the kubelet removes pods exceeding requests, BestEffort first; signals `kube_pod_status_reason{reason="Evicted"}` and node `MemoryPressure`; fix requests and node reservations.
</details>

<details><summary><b>Q4 · "Which memory metric goes on the dashboard?"</b></summary>

**Initial Prompt.** usage, working set, RSS — which one?

**L5 Textbook Answer.** `container_memory_usage_bytes`, it's the total.

**Why L5 Fails at 3 AM or on the Bill.** Usage includes page cache and causes false leak investigations and over-provisioning.

**L7 Principal Defense.** Working set against the limit (what the kubelet and eviction use) and RSS trend (what the OOM killer must reclaim). Usage only for cache-heavy workloads where cache hit rate matters, explicitly labelled.
</details>

<details><summary><b>Q5 · "How do you right-size requests across 2,000 deployments?"</b></summary>

**Initial Prompt.** Finance wants requests aligned with usage.

**L5 Textbook Answer.** Set requests to average usage plus 20%.

**Why L5 Fails at 3 AM or on the Bill.** Averages undersize bursty services (throttling or eviction) and ignore memory's non-compressibility.

**L7 Principal Defense.** CPU requests at a high percentile of 5-minute usage (p90–p95 over 14 days); memory requests at the p99+ of working set plus margin; recommendations from recording rules (§2.1) or the VPA recommender; rollout guarded by throttle ratio, OOM and eviction alerts. Report savings as (requests − recommended) × node price, and track realised node reduction, not theoretical.
</details>

<details><summary><b>Q6 · "What does CFS burst change?"</b></summary>

**Initial Prompt.** Is `cpu.max.burst` worth enabling?

**L5 Textbook Answer.** It lets containers use more CPU temporarily.

**Why L5 Fails at 3 AM or on the Bill.** Without the accounting, teams expect higher average usage (wrong) or ignore it (missing an easy latency win).

**L7 Principal Defense.** Burst lets *unused* quota from previous periods carry over up to the burst size, so short spikes run unthrottled while the long-run average stays capped. L2: 2 cores + 200 ms burst behaves like a 4-core limit for this workload (p99 207 → 107 ms) at the same average. I'd enable it for latency tiers that must keep limits, verify kernel and Kubernetes support, and watch `container_cpu_cfs_burst_periods_total`.
</details>

<details><summary><b>Q7 · "Kubernetes monitoring is noisy. What would you page on?"</b></summary>

**Initial Prompt.** We have 150 Kubernetes alerts and ignore most of them.

**L5 Textbook Answer.** Tune thresholds and add `for:` durations.

**Why L5 Fails at 3 AM or on the Bill.** The problem is *what* pages, not the thresholds: pod restarts, throttling and replica mismatches are causes, not user impact.

**L7 Principal Defense.** Page on service SLO burn and on platform-wide failures (nodes NotReady at scale, control plane unavailable, DNS, CNI). Route workload-level signals (crash loops, OOMs, throttling, pending pods) as tickets to the owning team with label-derived routing (`team` from KSM labels). Delete alerts nobody acts on; measure alert precision quarterly (Folder 04 File 4).
</details>

<details><summary><b>Q8 · "How do you attribute container cost to teams?"</b></summary>

**Initial Prompt.** Build chargeback from Prometheus.

**L5 Textbook Answer.** Sum CPU and memory usage by namespace and multiply by node prices.

**Why L5 Fails at 3 AM or on the Bill.** Usage-based charging ignores that capacity is reserved by *requests*; double counting from cAdvisor aggregates and idle node capacity break the totals.

**L7 Principal Defense.** Charge `max(requests, usage)` per container (requests reserve capacity; usage above request consumes slack), joined to team via KSM namespace/pod labels; filter `container!=""`; allocate idle node capacity proportionally or to the platform; reconcile the total to the cloud bill monthly. OpenCost implements this model; the PromQL is in the mixin recording rules.
</details>

---

## 5. Invariants checklist

- [ ] Every container has CPU and memory requests; memory limits everywhere; CPU limits only where policy demands, sized to peak parallelism or with burst.
- [ ] Throttling alerts use the throttled-periods ratio *and* an impact signal (PSI or latency).
- [ ] Memory dashboards use working set and RSS; OOMKilled and Evicted are distinct alerts with distinct runbooks.
- [ ] All cAdvisor aggregations filter `container!=""`; high-cardinality cAdvisor labels are dropped at scrape time.
- [ ] KSM runs with resource, metric and label allowlists; label import is explicit.
- [ ] Workload-level Kubernetes alerts route as tickets to owning teams; pages are reserved for SLO burn and platform-wide failures.
- [ ] Chargeback uses max(requests, usage), reconciled to the bill.

---

## 6. References

- kube-state-metrics v2.20.0 metrics docs: <https://github.com/kubernetes/kube-state-metrics/tree/v2.20.0/docs/metrics>
- cAdvisor Prometheus metrics source: <https://github.com/google/cadvisor/blob/v0.60.6/lib/metrics/prometheus.go>
- Linux CFS bandwidth control: <https://docs.kernel.org/scheduler/sched-bwc.html>
- Kubernetes: resource management for pods and containers: <https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/>
- Kubernetes: node-pressure eviction: <https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/>
- Kubernetes: reserve compute resources for system daemons: <https://kubernetes.io/docs/tasks/administer-cluster/reserve-compute-resources/>
- kubernetes-mixin (recording rules and alerts): <https://github.com/kubernetes-monitoring/kubernetes-mixin>
- OpenCost specification: <https://www.opencost.io/docs/specification>
