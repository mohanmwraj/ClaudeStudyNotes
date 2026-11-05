# 01 · USE, RED, the Four Golden Signals, and Linux / eBPF / node_exporter Metrics

> **Folder 03 — What to Monitor: Complete Enterprise Taxonomy · File 1 of 4.**
> Pinned to **node_exporter v1.12.1** (2026-07-14; collector source read at that tag) and Prometheus v3.15.1 for query semantics.
> Labels: **[D]** documented / read in pinned source · **[M]** measured by the listing (deterministic, re-run by the gate) · **[E]** model · **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L1 `use_red_lab.py` | M/M/c (Erlang C) response time vs utilization for 1–64 servers; Little's law on simulated disk counters (`io_time` = utilization, `io_time_weighted` = queue depth); a synthetic 8-core node incident with real node_exporter metric names, where this file's recording/alert expressions are **evaluated by the Folder 02 PromQL engine**; RED computed from HTTP counters and why duration must be split by outcome | <1 s |

**Verification.** Queueing results are analytic (Erlang C) and cross-checked by simulation (Little's law holds to floating-point precision; M/M/1 mean latency within 3% of theory). Alert expressions are executed with `promql_mini.py` (Folder 02, validated against 695 upstream promqltest cases). Metric names were checked against node_exporter v1.12.1 collector source (e.g. `collector/pressure_linux.go`). No live host was scraped.

---

## 0. Orientation

**What this file answers.** Which signals to collect for *any* system, why each framework exists, how they map to concrete Linux and node_exporter metrics, and how to turn them into alerts that page on user pain rather than on resource trivia.

**The three frameworks, one sentence each.**

| Framework | Origin | Applies to | Question it answers |
|---|---|---|---|
| **USE** — Utilization, Saturation, Errors | Brendan Gregg | every *resource* (CPU, memory, disk, NIC, locks, pools) | "Is this resource the bottleneck?" |
| **RED** — Rate, Errors, Duration | Tom Wilkie | every *request-driven service* | "Are users being served well?" |
| **Four Golden Signals** — Latency, Traffic, Errors, Saturation | Google SRE book | every *user-facing system* | "What should page a human?" |

They are complementary: Golden Signals and RED define **symptoms** (what pages), USE defines **causes** (what you look at once paged). An L7 monitoring design pages on symptoms and dashboards causes.

---

## 1. First principles: why utilization alone lies

### 1.1 Queueing theory in one table (L1 §1)

Response time / service time for an M/M/c queue [M]:

| Utilization | c = 1 (one disk, one lock) | c = 4 | c = 16 | c = 64 (cores) |
|---|---|---|---|---|
| 50% | 2.00 | 1.09 | 1.00 | 1.00 |
| 80% | **5.00** | 1.75 | 1.10 | 1.00 |
| 90% | **10.00** | 2.97 | 1.37 | 1.05 |
| 99% | 100.00 | 25.45 | 6.96 | 2.42 |

- A single-server resource (one disk queue, one mutex, one single-threaded event loop) is already **5× slower at 80% utilization**. A 64-wide pool barely notices 90%.
- Therefore "alert when CPU > 80%" is wrong in both directions: too late for a single-threaded component, too early for a wide one. **Saturation** — work that is *waiting* — is the signal that generalises.
- Little's law (`L = λ·W`) connects the three: queue length = arrival rate × time in system. L1 §2 verifies it on simulated disk counters to machine precision, which is exactly how node_exporter's disk metrics should be read.

### 1.2 USE on Linux, resource by resource

```text
 resource   utilization                              saturation                                  errors
 ────────   ──────────────────────────────────────   ─────────────────────────────────────────   ──────────────────────────────
 CPU        1 - rate(node_cpu_seconds_total          rate(node_pressure_cpu_waiting_seconds_     (machine-check, rare)
            {mode="idle"}[5m])  (per CPU, avg)       total[5m])  PSI "some"; node_load1/cores
 memory     1 - MemAvailable/MemTotal                rate(node_pressure_memory_{waiting,stalled}  node_vmstat_oom_kill (rate)
            (node_memory_MemAvailable_bytes)          _seconds_total[5m]); rate(node_vmstat_pgmajfault)
 disk       rate(node_disk_io_time_seconds_total)   rate(node_disk_io_time_weighted_seconds_     node_disk_* errors via SMART /
            (busy fraction of one queue)             total[5m]) = avg in-flight (Little)          dmesg exporters; fs errors
 network    rate(node_network_{receive,transmit}_    rate(node_network_*_drop_total[5m]);         rate(node_network_*_errs_total)
            bytes_total)*8 / link speed               TcpExt listen overflows/drops (netstat)
 filesystem 1 - avail/size                           inode use (node_filesystem_files_free)       read-only remounts (node_filesystem_readonly)
 file desc  node_filefd_allocated / maximum          —                                            EMFILE in app logs
```

Notes that separate experts from checklists [D]:

- **PSI (Pressure Stall Information)** is the kernel's direct saturation signal (Linux ≥ 4.20, cgroup v2). node_exporter exposes cumulative seconds: `node_pressure_cpu_waiting_seconds_total` ("some" — at least one task waiting for CPU), `node_pressure_memory_waiting_seconds_total` (some) and `node_pressure_memory_stalled_seconds_total` (full — *all* non-idle tasks stalled), the same pair for `io`, and `node_pressure_irq_stalled_seconds_total`. `rate(...)` of these is the fraction of wall time spent stalled — 0.2 means 20% of the time some task could not run. cAdvisor exposes the same per container (`container_pressure_*_seconds_total`, File 2).
- **Load average** counts runnable *and* uninterruptible (D-state) tasks on Linux, so it mixes CPU and I/O saturation; divide by cores and confirm with PSI.
- **`iowait` is not a disk metric.** It is idle CPU time while some I/O is outstanding; on a busy CPU it shrinks even if the disk is saturated. Use disk saturation (`io_time_weighted`) and PSI io instead.
- **`node_disk_io_time_seconds_total`** (busy time) saturates at 1.0 *per queue*; on NVMe/SSD with deep parallel queues, 100% busy is not saturation. Latency (`rate(read_time)/rate(reads_completed)`) and queue depth (`io_time_weighted`) are the truth.
- **Memory "used"** is meaningless (page cache); `MemAvailable` is the kernel's estimate of memory available without swapping. Saturation shows up as PSI memory and major faults long before OOM.
- **Steal** (`mode="steal"`) is CPU taken by the hypervisor — sustained steal on cloud VMs is a noisy-neighbour or credit-exhaustion (burstable instance) signal.

### 1.3 RED and the Four Golden Signals for services

```text
 Golden Signal   RED        Prometheus (HTTP server, Micrometer/OTel naming)
 ─────────────   ───────    ───────────────────────────────────────────────────────────────────────────
 Traffic         Rate       sum by (service) (rate(http_server_requests_seconds_count[5m]))
 Errors          Errors     ratio of 5xx (and explicit failures: timeouts, gRPC codes) over all requests
 Latency         Duration   histogram_quantile on SUCCESSFUL requests; separate latency of failures
 Saturation      —          the service's own queue/pool: in-flight requests, thread/connection pool
                            pending, CPU throttling, GC, event-loop lag (Files 2–4)
```

Two subtleties L1 §4 makes concrete [M]: fast failures make latency look *better* (a 5 ms 503 lowers the mean), and slow failures (timeouts) make it look *worse* — blended mean 214 ms vs 120 ms for successes when 5% of requests time out at 2 s. **Always split latency by outcome**, and count timeouts as errors.

### 1.4 What eBPF adds

eBPF programs attached to kernel hooks give USE/RED data without instrumenting applications [D, ⚠ fast-moving]:

- **Kernel-level latency distributions**: run-queue latency (CPU saturation per process), block I/O latency histograms, TCP retransmits and RTT — via Cloudflare's `ebpf_exporter` or BCC/bpftrace tooling.
- **Zero-code RED**: Grafana Beyla — donated to OpenTelemetry in 2025 as *OpenTelemetry eBPF Instrumentation (OBI)* — derives HTTP/gRPC/SQL request rate, errors and duration from socket and TLS-library probes, emitting OTel/Prometheus metrics with service names from Kubernetes metadata.
- **Continuous profiling** (Folder 06 File 3) uses the same machinery to sample stacks.

Trade-offs: kernel version and BTF requirements, privileged DaemonSets, CPU overhead under high event rates, and *cardinality* — per-connection or per-endpoint labels explode unless aggregated in-kernel.

<!-- listing:use_red_lab.py -->
```python
"""use_red_lab.py - the queueing mathematics behind USE/RED/Golden Signals, and the node_exporter
alert expressions of this file evaluated on a synthetic incident with promql_mini.py (Folder 02).

Sections: (1) M/M/1 and M/M/c (Erlang C) response time vs utilization - why "utilization 80%" is
already saturation for single queues but not for wide ones; (2) Little's law checks on disk
counters (avg queue depth = rate(io_time_weighted)); (3) a synthetic 8-core node going into CPU
saturation: utilization, load/cores and PSI 'some' computed with real node_exporter metric names,
and the recording/alert rules evaluated by the engine; (4) RED from an HTTP histogram's counters.
Deterministic, stdlib only.

Usage: python use_red_lab.py [target.md]
"""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from promql_mini import Engine, Parser  # noqa: E402

S, M = 1000, 60000


def erlang_c(c, a):
    """Probability that an arrival waits in M/M/c with offered load a = lambda/mu (a < c)."""
    s = sum(a ** k / math.factorial(k) for k in range(c))
    top = a ** c / math.factorial(c) * c / (c - a)
    return top / (s + top)


def mmc_response(c, rho, service=1.0):
    a = rho * c
    pw = erlang_c(c, a)
    return service + pw * service / (c * (1 - rho))


def main():
    checks = []
    print("== 1. Response time / service time vs utilization (M/M/c) ==")
    print(f"{'util':>5} | {'c=1':>7} {'c=4':>7} {'c=16':>7} {'c=64':>7} | P(wait) c=16")
    for rho in (0.5, 0.7, 0.8, 0.9, 0.95, 0.99):
        row = [mmc_response(c, rho) for c in (1, 4, 16, 64)]
        print(f"{rho:>5.0%} | " + " ".join(f"{r:>7.2f}" for r in row) + f" | {erlang_c(16, rho * 16):>6.1%}")
    checks.append(("M/M/1 at 90% is 10x", abs(mmc_response(1, 0.9) - 10.0) < 1e-9))
    checks.append(("wide pools tolerate 90%", mmc_response(64, 0.9) < 1.2))
    print("-> a single disk/lock/thread is saturated long before 100%; a 64-core pool is not. USE thresholds must")
    print("   be per-resource-shape, and SATURATION (queueing) is the signal, not utilization alone.")
    print()

    print("== 2. Little's law on disk counters (L = lambda x W) ==")
    rng = random.Random(4)
    lam, svc_ms = 400.0, 2.0  # 400 IOPS, 2 ms service: utilization 80% on one queue
    t, busy_until, io_time, weighted, completed, waits = 0.0, 0.0, 0.0, 0.0, 0, []
    horizon = 600.0
    while t < horizon:
        t += rng.expovariate(lam)
        start = max(t, busy_until)
        svc = rng.expovariate(1000.0 / svc_ms)
        busy_until = start + svc
        io_time += svc
        waits.append(busy_until - t)
        completed += 1
    weighted = sum(waits)  # node_disk_io_time_weighted_seconds_total: sum of in-flight time
    util = io_time / horizon
    qdepth = weighted / horizon
    lat = weighted / completed
    print(f"rate(node_disk_io_time_seconds_total)          = {util:.3f}  (utilization)")
    print(f"rate(node_disk_io_time_weighted_seconds_total) = {qdepth:.3f}  (average in-flight = saturation)")
    print(f"Little: in-flight / IOPS = {qdepth / (completed / horizon) * 1000:.2f} ms = mean latency {lat * 1000:.2f} ms "
          f"(M/M/1 predicts {svc_ms / (1 - lam * svc_ms / 1000):.1f} ms)")
    checks.append(("little holds", abs(qdepth / (completed / horizon) - lat) < 1e-9))
    checks.append(("mm1 close", abs(lat * 1000 - svc_ms / (1 - 0.8)) < 1.5))
    print()

    print("== 3. Synthetic 8-core node: normal, then a CPU-bound batch job (t=10m..20m) ==")
    eng = Engine()
    cores = 8
    modes = {"user": 0.25, "system": 0.05, "iowait": 0.02, "steal": 0.0}
    acc = {(c, m): 0.0 for c in range(cores) for m in list(modes) + ["idle"]}
    psi, load = 0.0, []
    pts = {k: [] for k in acc}
    psi_pts, load_pts = [], []
    for step in range(0, 30 * 4 + 1):  # 15 s scrapes for 30 min
        tt = step * 15
        hot = 600 <= tt < 1200
        runnable = 14.0 if hot else 2.5
        for c in range(cores):
            used = 0.0
            for m, share in modes.items():
                s = 0.97 * 15 if (hot and m == "user") else share * 15
                acc[(c, m)] += s
                used += s
            acc[(c, "idle")] += max(0.0, 15 - used)
            for k in [(c, m) for m in list(modes) + ["idle"]]:
                pts[k].append((tt * S, acc[k]))
        psi += 15 * (min(1.0, max(0.0, (runnable - cores) / runnable)) if hot else 0.01)
        psi_pts.append((tt * S, psi))
        load_pts.append((tt * S, runnable))
    for (c, m), p in pts.items():
        eng.add({"__name__": "node_cpu_seconds_total", "instance": "n1", "cpu": str(c), "mode": m}, p)
    eng.add({"__name__": "node_pressure_cpu_waiting_seconds_total", "instance": "n1"}, psi_pts)
    eng.add({"__name__": "node_load1", "instance": "n1"}, load_pts)
    exprs = {
        "utilization": '1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))',
        "load per core": 'node_load1 / on(instance) count by (instance) (node_cpu_seconds_total{mode="idle"})',
        "PSI cpu some": 'rate(node_pressure_cpu_waiting_seconds_total[5m])',
        "ALERT CPUSaturated": '(rate(node_pressure_cpu_waiting_seconds_total[5m]) > 0.2) '
                              'and on(instance) (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) > 0.9)',
    }
    print(f"{'t':>5} | " + " | ".join(f"{k:>18}" for k in exprs))
    fired = []
    for tm in (5, 9, 12, 15, 19, 22, 26):
        row = []
        for k, e in exprs.items():
            v = eng.eval(Parser(e).parse(), tm * M)
            val = v[0][1] if v else None
            row.append("firing" if (k.startswith("ALERT") and v) else ("-" if val is None else f"{val:.3f}"))
            if k.startswith("ALERT") and v:
                fired.append(tm)
        print(f"{tm:>4}m | " + " | ".join(f"{r:>18}" for r in row))
    checks.append(("alert fires only in the incident", fired and min(fired) >= 12 and max(fired) <= 22))
    print()

    print("== 4. RED from counters: rate, errors, duration (synthetic checkout service) ==")
    eng2 = Engine()
    reqs = {("200",): 95.0, ("500",): 5.0}
    for (code,), r in reqs.items():
        eng2.add({"__name__": "http_server_requests_seconds_count", "job": "checkout", "status": code},
                 [(i * 15 * S, r * 15 * i) for i in range(41)])
        eng2.add({"__name__": "http_server_requests_seconds_sum", "job": "checkout", "status": code},
                 [(i * 15 * S, r * 15 * i * (0.120 if code == "200" else 2.0)) for i in range(41)])
    q = {
        "Rate (req/s)": 'sum by (job) (rate(http_server_requests_seconds_count[5m]))',
        "Errors (ratio)": 'sum by (job) (rate(http_server_requests_seconds_count{status=~"5.."}[5m])) / sum by (job) (rate(http_server_requests_seconds_count[5m]))',
        "Duration (mean s)": 'sum by (job) (rate(http_server_requests_seconds_sum[5m])) / sum by (job) (rate(http_server_requests_seconds_count[5m]))',
        "Duration of successes": 'sum by (job) (rate(http_server_requests_seconds_sum{status!~"5.."}[5m])) / sum by (job) (rate(http_server_requests_seconds_count{status!~"5.."}[5m]))',
    }
    for k, e in q.items():
        v = eng2.eval(Parser(e).parse(), 10 * M)[0][1]
        print(f"{k:<24} {v:.4f}")
    mean_all = eng2.eval(Parser(q["Duration (mean s)"]).parse(), 10 * M)[0][1]
    checks.append(("errors inflate mean latency", mean_all > 0.2))
    print("-> slow failures (timeouts) inflate the blended mean 1.8x; RED 'Duration' must be split by outcome")
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:use_red_lab.py -->
```text
== 1. Response time / service time vs utilization (M/M/c) ==
 util |     c=1     c=4    c=16    c=64 | P(wait) c=16
  50% |    2.00    1.09    1.00    1.00 |   0.9%
  70% |    3.33    1.36    1.03    1.00 |  13.0%
  80% |    5.00    1.75    1.10    1.00 |  30.5%
  90% |   10.00    2.97    1.37    1.05 |  59.1%
  95% |   20.00    5.46    1.98    1.18 |  78.0%
  99% |  100.00   25.45    6.96    2.42 |  95.4%
-> a single disk/lock/thread is saturated long before 100%; a 64-core pool is not. USE thresholds must
   be per-resource-shape, and SATURATION (queueing) is the signal, not utilization alone.

== 2. Little's law on disk counters (L = lambda x W) ==
rate(node_disk_io_time_seconds_total)          = 0.798  (utilization)
rate(node_disk_io_time_weighted_seconds_total) = 3.891  (average in-flight = saturation)
Little: in-flight / IOPS = 9.74 ms = mean latency 9.74 ms (M/M/1 predicts 10.0 ms)

== 3. Synthetic 8-core node: normal, then a CPU-bound batch job (t=10m..20m) ==
    t |        utilization |      load per core |       PSI cpu some | ALERT CPUSaturated
   5m |              0.320 |              0.312 |              0.010 |                  -
   9m |              0.320 |              0.312 |              0.010 |                  -
  12m |              0.642 |              1.750 |              0.208 |                  -
  15m |              1.000 |              1.750 |              0.429 |             firing
  19m |              1.000 |              1.750 |              0.429 |             firing
  22m |              0.678 |              0.312 |              0.230 |                  -
  26m |              0.320 |              0.312 |              0.010 |                  -

== 4. RED from counters: rate, errors, duration (synthetic checkout service) ==
Rate (req/s)             100.0000
Errors (ratio)           0.0500
Duration (mean s)        0.2140
Duration of successes    0.1200
-> slow failures (timeouts) inflate the blended mean 1.8x; RED 'Duration' must be split by outcome

checks: 6/6 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 node_exporter DaemonSet flags (v1.12)

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata: {name: node-exporter, namespace: monitoring}
spec:
  selector: {matchLabels: {app: node-exporter}}
  template:
    metadata: {labels: {app: node-exporter}}
    spec:
      hostNetwork: true
      hostPID: true
      tolerations: [{operator: Exists}]
      containers:
        - name: node-exporter
          image: quay.io/prometheus/node-exporter:v1.12.1
          args:
            - --path.procfs=/host/proc
            - --path.sysfs=/host/sys
            - --path.rootfs=/host/root
            - --collector.filesystem.mount-points-exclude=^/(dev|proc|sys|run/k3s|var/lib/(docker|containerd|kubelet)/.+)($|/)
            - --collector.netclass.ignored-devices=^(veth.*|cali.*|cilium.*|lxc.*|flannel.*)$
            - --collector.netdev.device-exclude=^(veth.*|cali.*|cilium.*|lxc.*)$
            - --no-collector.wifi
            - --no-collector.hwmon            # enable only on bare metal where you use it
          ports: [{name: metrics, containerPort: 9100}]
          resources:
            requests: {cpu: 50m, memory: 64Mi}
            limits: {memory: 128Mi}
          volumeMounts:
            - {name: proc, mountPath: /host/proc, readOnly: true}
            - {name: sys, mountPath: /host/sys, readOnly: true}
            - {name: root, mountPath: /host/root, readOnly: true, mountPropagation: HostToContainer}
      volumes:
        - {name: proc, hostPath: {path: /proc}}
        - {name: sys, hostPath: {path: /sys}}
        - {name: root, hostPath: {path: /}}
```

Excluding container veth interfaces and overlay mounts is the single biggest node_exporter cardinality fix on Kubernetes nodes.

### 2.2 USE recording rules and saturation-first alerts

```yaml
groups:
  - name: node-use.rules
    interval: 30s
    rules:
      - record: instance:node_cpu_utilisation:rate5m
        expr: 1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))
      - record: instance:node_pressure_cpu_waiting:rate5m
        expr: rate(node_pressure_cpu_waiting_seconds_total[5m])
      - record: instance:node_pressure_memory_stalled:rate5m
        expr: rate(node_pressure_memory_stalled_seconds_total[5m])
      - record: instance:node_memory_available:ratio
        expr: node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes
      - record: instance_device:node_disk_io_time_seconds:rate5m
        expr: rate(node_disk_io_time_seconds_total{device!~"dm-.*|loop.*"}[5m])
      - record: instance_device:node_disk_queue_depth:rate5m
        expr: rate(node_disk_io_time_weighted_seconds_total{device!~"dm-.*|loop.*"}[5m])
      - record: instance_device:node_disk_read_latency_seconds:rate5m
        expr: |
          rate(node_disk_read_time_seconds_total[5m])
            / clamp_min(rate(node_disk_reads_completed_total[5m]), 1e-9)
  - name: node-use.alerts
    rules:
      - alert: NodeCPUSaturated
        expr: |
          instance:node_pressure_cpu_waiting:rate5m > 0.2
            and on(instance) instance:node_cpu_utilisation:rate5m > 0.9
        for: 15m
        labels: {severity: warning}
        annotations:
          summary: "{{ $labels.instance }}: tasks waited for CPU {{ $value | humanizePercentage }} of the time"
      - alert: NodeMemoryPressure
        expr: instance:node_pressure_memory_stalled:rate5m > 0.05
        for: 10m
        labels: {severity: warning}
        annotations:
          summary: "{{ $labels.instance }}: all tasks stalled on memory >5% of the time (reclaim/swap thrash)"
      - alert: NodeOOMKills
        expr: increase(node_vmstat_oom_kill[15m]) > 0
        labels: {severity: warning}
      - alert: NodeDiskSaturated
        expr: instance_device:node_disk_queue_depth:rate5m > 8 and instance_device:node_disk_read_latency_seconds:rate5m > 0.05
        for: 15m
        labels: {severity: warning}
      - alert: NodeFilesystemFillingUp
        expr: |
          predict_linear(node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs"}[6h], 24 * 3600) < 0
            and node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs"}
              / node_filesystem_size_bytes{fstype!~"tmpfs|overlay|squashfs"} < 0.2
        for: 1h
        labels: {severity: warning}
      - alert: NodeNetworkDrops
        expr: rate(node_network_receive_drop_total{device!~"lo|veth.*"}[5m]) > 100
        for: 15m
        labels: {severity: warning}
```

### 2.3 RED rules for every HTTP service (outcome-split latency)

```yaml
groups:
  - name: red.rules
    interval: 30s
    rules:
      - record: service:http_requests:rate5m
        expr: sum by (service) (rate(http_server_requests_seconds_count[5m]))
      - record: service:http_errors:ratio_rate5m
        expr: |
          (sum by (service) (rate(http_server_requests_seconds_count{outcome=~"SERVER_ERROR"}[5m]))
            or sum by (service) (rate(http_server_requests_seconds_count[5m])) * 0)
          / sum by (service) (rate(http_server_requests_seconds_count[5m]))
      - record: service:http_success_latency_seconds:p99_5m
        expr: |
          histogram_quantile(0.99,
            sum by (service, le) (rate(http_server_requests_seconds_bucket{outcome="SUCCESS"}[5m])))
      - record: service:http_success_latency_seconds:mean_5m
        expr: |
          sum by (service) (rate(http_server_requests_seconds_sum{outcome="SUCCESS"}[5m]))
            / sum by (service) (rate(http_server_requests_seconds_count{outcome="SUCCESS"}[5m]))
```

`outcome` (`SUCCESS`, `CLIENT_ERROR`, `SERVER_ERROR`, …) is a Micrometer/Spring tag; for OTel semantic conventions use `http_response_status_code` and an explicit error flag.

---

## 3. Failure modes and FinOps debugging

### F1. "CPU at 85%" pages nobody needed, while a single-threaded bottleneck goes unseen

**Symptom.** High-CPU alerts fire on busy but healthy batch nodes; meanwhile an API is slow and no resource alert fires.

**Signature.** Node CPU 85% with PSI cpu ≈ 0; the slow API's process has one hot thread at 100% (`rate(process_cpu_seconds_total) ≈ 1.0`) on a 32-core box (node utilization 4%).

**Root cause.** Utilization thresholds ignore resource *shape* (L1 §1): a 32-core pool at 85% has little queueing; a single thread at 100% is saturated.

**Fix.** Replace utilization alerts with saturation (PSI, run-queue latency, pool pending) and with RED symptom alerts on the service.

**Prevention.** Monitoring standard: page on symptoms; resource utilization is a dashboard, not an alert.

### F2. Disk "100% busy" on NVMe with healthy latency

**Symptom.** Disk utilization alerts fire constantly on new NVMe nodes; nobody can find a problem.

**Signature.** `rate(node_disk_io_time_seconds_total) ≈ 1.0`, but read latency < 1 ms and queue depth modest relative to device capability.

**Root cause.** Busy time counts wall time with ≥1 I/O in flight; parallel devices serve many I/Os concurrently, so "100% busy" ≠ saturated.

**Fix.** Alert on latency + queue depth (§2.2), per device class.

**Prevention.** Separate thresholds for rotational, SSD and NVMe (`node_disk_info`), validated with fio baselines.

### F3. Memory alerts on page cache

**Symptom.** "Memory used > 90%" fires on database nodes permanently.

**Signature.** `MemTotal − MemFree` high; `MemAvailable` healthy; PSI memory ≈ 0.

**Root cause.** Free memory is used as page cache by design; "used" includes reclaimable cache.

**Fix.** Use `MemAvailable` and PSI memory; alert on stall, major faults and OOM kills.

**Prevention.** Remove `MemFree`-based alerts from the catalog.

### F4. node_exporter cardinality explosion on Kubernetes nodes

**Symptom.** node_exporter is the top job by series; the TSDB status page shows `device` with thousands of values.

**Signature.** `count by (device) (node_network_receive_bytes_total)` lists `veth*`/`cali*` interfaces that churn with every pod; filesystem series for each overlay mount.

**Root cause.** Default collectors enumerate every interface and mount; on Kubernetes those are per-pod and ephemeral (churn — Folder 01 File 2).

**Fix.** Device/mount exclusion flags (§2.1); drop residual series with `metric_relabel_configs`.

**Prevention.** Budget series per node exporter (≤ ~1–2k) and alert on growth.

### F5. Latency SLO "improves" during an outage

**Symptom.** During a dependency outage, mean and p50 latency *drop* and the latency SLO looks great.

**Signature.** 5xx ratio spikes while latency of all requests falls; failures are fast (circuit breaker open).

**Root cause.** Blended latency mixes fast failures with successes (§1.3).

**Fix.** Latency SLIs over successful requests only; errors handled by the availability SLI.

**Prevention.** Recording rules split by outcome (§2.3); dashboards never show blended latency without the error rate next to it.

### F6. Burstable instances run out of CPU credits

**Symptom.** Periodic multi-hour slowdowns on t-class/burstable VMs; CPU utilization caps at a strange plateau.

**Signature.** `mode="steal"` rises sharply; utilization flat-lines near the baseline percentage; PSI cpu rises.

**Root cause.** Exhausted CPU credits throttle the VM at the hypervisor, visible as steal.

**Fix.** Move latency-sensitive tiers (including Prometheus itself — Folder 01 F3) to non-burstable instances or unlimited mode.

**Prevention.** Alert on `rate(node_cpu_seconds_total{mode="steal"}[10m]) > 0.1` per CPU.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "USE vs RED vs Golden Signals — which do we use?"</b></summary>

**Initial Prompt.** Our teams argue about monitoring frameworks. Pick one.

**L5 Textbook Answer.** RED for microservices, USE for infrastructure, Golden Signals is Google's version of RED plus saturation.

**Why L5 Fails at 3 AM or on the Bill.** "Pick one per layer" without an alerting policy produces resource alerts that page for healthy systems and services with no saturation signal at all.

**L7 Principal Defense.** All three, with roles: Golden Signals/RED define *paging* (symptoms users feel — availability and latency SLIs), USE defines *diagnosis* (dashboards per resource), and saturation is the bridge — every service exports its own queue (in-flight, pool pending, event-loop lag). Policy: page only on SLO burn (Folder 04), ticket on saturation trends, never page on utilization.
</details>

<details><summary><b>Q2 · "Why not alert at 80% CPU?"</b></summary>

**Initial Prompt.** It's simple and everyone understands it.

**L5 Textbook Answer.** Because 80% might be normal for some workloads; tune thresholds per service.

**Why L5 Fails at 3 AM or on the Bill.** Tuning thresholds treats a modelling error as a calibration problem; the same 80% means 5× latency on a single queue and nothing on 64 cores (L1 §1).

**L7 Principal Defense.** Utilization predicts latency only through queueing, which depends on parallelism. Measure queueing directly — PSI `cpu waiting`, run-queue latency (eBPF), service pool pending — and alert on user-facing latency SLOs. Utilization stays as a capacity-planning input with per-shape headroom targets.
</details>

<details><summary><b>Q3 · "Explain PSI and how you'd use it."</b></summary>

**Initial Prompt.** What is Pressure Stall Information?

**L5 Textbook Answer.** It's a newer kernel metric that shows resource pressure as percentages.

**Why L5 Fails at 3 AM or on the Bill.** Without "some" vs "full" semantics, teams alert on the wrong one (memory *some* fires constantly) or miss thrash (memory *full*).

**L7 Principal Defense.** PSI accumulates time during which at least one task (*some*) or all non-idle tasks (*full*) were stalled on CPU, memory or IO; node_exporter exposes the totals as `node_pressure_*_{waiting,stalled}_seconds_total`, and `rate()` is the stalled fraction. CPU *some* > 20% means run-queue saturation; memory *full* > 5% means reclaim thrash; io *full* means everything waits on disk. Per-cgroup PSI from cAdvisor attributes pressure to containers — the best "noisy neighbour" signal Kubernetes has.
</details>

<details><summary><b>Q4 · "How do you read node_disk_io_time_weighted_seconds_total?"</b></summary>

**Initial Prompt.** What does that metric mean?

**L5 Textbook Answer.** It's the weighted time spent doing I/O.

**Why L5 Fails at 3 AM or on the Bill.** Without Little's law it is unreadable, so teams ignore the one disk metric that measures saturation.

**L7 Principal Defense.** It integrates the number of in-flight I/Os over time, so its rate is the average queue depth L. With IOPS λ from completions, mean latency W = L/λ (L1 §2 checks this to machine precision). Queue depth relative to the device's parallelism is saturation; W is the user-visible effect.
</details>

<details><summary><b>Q5 · "What does eBPF give us that exporters don't?"</b></summary>

**Initial Prompt.** Should we invest in eBPF observability?

**L5 Textbook Answer.** Yes, eBPF gives deep kernel visibility with low overhead.

**Why L5 Fails at 3 AM or on the Bill.** "Deep visibility" is not a requirement; eBPF has real costs (privileged agents, kernel compatibility, event-rate CPU, label cardinality) and overlaps with existing instrumentation.

**L7 Principal Defense.** Three concrete wins: per-process run-queue and block-I/O latency histograms (saturation where exporters only have counters), zero-code RED for services we can't instrument (OBI/Beyla), and continuous profiling. I'd deploy it as a DaemonSet with in-kernel aggregation, cap label sets to service/endpoint-template, and measure its overhead against an SLO before broad rollout.
</details>

<details><summary><b>Q6 · "Latency got better during the outage. Explain."</b></summary>

**Initial Prompt.** The p50 dropped from 120 ms to 15 ms while errors spiked.

**L5 Textbook Answer.** Fewer requests reached the slow path, so latency improved.

**Why L5 Fails at 3 AM or on the Bill.** "Improved" latency during an outage is a measurement artefact that will mislead the next incident review and any latency-based autoscaler.

**L7 Principal Defense.** Fast failures (circuit breaker, 503 from a sidecar) dominate the distribution; latency must be measured on successes, errors counted separately, and timeouts classified as errors. Rules split by outcome (§2.3) and the SLO uses separate availability and latency SLIs.
</details>

<details><summary><b>Q7 · "Design the minimal host dashboard."</b></summary>

**Initial Prompt.** What goes on the first row of a node dashboard?

**L5 Textbook Answer.** CPU, memory, disk, network usage graphs.

**Why L5 Fails at 3 AM or on the Bill.** Four utilization graphs answer "how busy" and never "is anything waiting" — the question on-call actually has.

**L7 Principal Defense.** Row 1: PSI cpu/memory/io (saturation), OOM kills and disk/NIC errors (errors). Row 2: utilization per resource with shape-appropriate scales. Row 3: latency per device and per NIC drops. Every panel links to the per-container view (cAdvisor PSI) for attribution. That is USE, ordered by diagnostic value.
</details>

<details><summary><b>Q8 · "What's the error signal for a CPU?"</b></summary>

**Initial Prompt.** USE says Errors for every resource. What are CPU errors?

**L5 Textbook Answer.** CPUs don't really have errors.

**Why L5 Fails at 3 AM or on the Bill.** Hardware faults are rare but catastrophic and silent at the application layer (silent data corruption, MCEs, thermal throttling).

**L7 Principal Defense.** Machine-check exceptions and EDAC memory errors (`node_edac_*` collector on bare metal), thermal throttling (`node_cpu_core_throttles_total`), and on cloud the provider's instance-health events. I'd collect them on bare metal and in long-lived fleets, alert on any correctable-error growth (a leading indicator), and route to hardware lifecycle, not to service on-call.
</details>

---

## 5. Invariants checklist

- [ ] Pages are on symptoms (SLO burn of availability and success latency); resource utilization is never a paging condition.
- [ ] Every resource on the critical path has a saturation metric: PSI for CPU, memory and IO, queue depth for disks, pending for pools, drops for NICs.
- [ ] Latency SLIs use successful requests only; timeouts count as errors.
- [ ] Memory alerts use `MemAvailable` and PSI memory, never `MemFree`.
- [ ] Disk alerts combine latency and queue depth, with per-device-class thresholds.
- [ ] node_exporter excludes container veths and overlay mounts; the series budget per node is enforced.
- [ ] Steal time and CPU credits are monitored on virtualised and burstable fleets.
- [ ] eBPF agents run with in-kernel aggregation, a bounded label set, and a measured overhead budget.

---

## 6. References

- Brendan Gregg, "The USE Method": <https://www.brendangregg.com/usemethod.html>
- Tom Wilkie, "The RED Method" (Grafana blog): <https://grafana.com/blog/2018/08/02/the-red-method-how-to-instrument-your-services/>
- Google SRE book, "Monitoring Distributed Systems" (Four Golden Signals): <https://sre.google/sre-book/monitoring-distributed-systems/>
- node_exporter v1.12.1: <https://github.com/prometheus/node_exporter/releases/tag/v1.12.1>
- PSI collector source: <https://github.com/prometheus/node_exporter/blob/v1.12.1/collector/pressure_linux.go>
- Linux PSI documentation: <https://docs.kernel.org/accounting/psi.html>
- `/proc/diskstats` field semantics: <https://docs.kernel.org/admin-guide/iostats.html>
- Cloudflare ebpf_exporter: <https://github.com/cloudflare/ebpf_exporter>
- OpenTelemetry eBPF Instrumentation (from Grafana Beyla): <https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation>
