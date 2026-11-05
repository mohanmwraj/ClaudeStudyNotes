# 02 · Observability FinOps: Adaptive Telemetry, Dropping Unused Metrics and TCO Math

> **Folder 08 — Market Comparison, FinOps and the FAANG L7 Bar-Raiser Playbook · File 2 of 3.**
> Builds on Prometheus v3.15.1 relabeling, Mimir 3.2.4 limits, OTel Collector v0.164.0 / Alloy v1.21.3 processors and the File 01 price points (2026-11-05).
> Labels: **[D]** documented / read in pinned source · **[M]** measured · **[E]** model · **⚠** version- or price-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L2 `finops_lab.py` | **Usage.** Parses 42 real queries (Folder 05 dashboard, Folder 07 rule catalog, an ad-hoc log) with `promql_mini` to find which labels each metric *needs*. **Inventory.** Applies them to a 6,000-container inventory: **4.58M → 535k series (88% fewer)**, worth $26k/month at Grafana Cloud Pro list or $202k at Datadog list. Dropping a label that is 1:1 with another (`instance` vs `pod`) saves nothing. **Aggregation proof.** Reset-aware counter aggregation reproduces the dashboard answer exactly (error 0), while naively summing raw counters is off by **1,333 req/s** around one pod restart. **Logs.** Drop and sample rules cut 3 TB/day by 55% | <1 s |

**Verification.**
- **Label usage.** Derived from the PromQL AST (`agg` grouping and `without`, `bin` `on()` labels, matchers, `le` for `histogram_quantile`, ALL for unaggregated selectors). Queries are parsed by the engine that passes upstream promqltest [M].
- **Correctness proof.** Runs the same query on raw and aggregated data in that engine [M].
- **Prices.** From File 01 (2026-11-05 list prices) ⚠.

---

## 0. Orientation

**What this file answers.** How to cut an observability bill by half or more without losing a single dashboard answer, alert or incident drill-down. It covers:
- usage analysis;
- dropping and aggregating at the right layer;
- reset-safe aggregation;
- log and trace volume control;
- the unit economics that keep it cut.

**The FinOps control loop.**

```text
            ┌─────────── usage (what is READ) ───────────┐
            │ Grafana query logs, rule files, API logs    │
            │ → per metric: labels needed (L2 §1)         │
            ▼                                             │
 inventory (what is STORED)            recommendations    │
 active series per metric/label  ──►  drop family | aggregate away labels | shorten retention
 log GB per app/level                  drop debug | sample access logs | index vs archive
            │                                             │
            ▼                                             │
 enforcement (WHERE)                                      │
   app (Micrometer MeterFilter) → agent/collector (Alloy, OTel filter/transform)
   → scrape (metric_relabel_configs) → backend (Mimir limits, Adaptive Metrics, Loki retention_stream)
            │                                             │
            └──────────── unit economics & budgets ───────┘
              $/series, $/GB, per team, alert at 80% of budget
```

---

## 1. First principles

### 1.1 What a query actually needs [M]

A label of metric M may be removed (aggregated away) only if **no** query needs it. L2 derives "needs" from the PromQL AST:

| Query shape | Labels needed from M |
|---|---|
| `M{a="x"}` returned raw (unaggregated) | **all** labels, because each series is shown |
| `sum by (a, b) (rate(M{c="y"}[5m]))` | `a`, `b`, `c` |
| `max without (pod) (M)` | all labels except `pod`, so effectively all |
| `histogram_quantile(0.99, sum by (le, uri) (…M_bucket…))` | `le`, `uri` (+ matchers) |
| `X / on(job) Y` | `job` (+ each side's grouping) |

Applied to Folder 05's RED dashboard, Folder 07's 27-rule catalog and seven ad-hoc incident queries (42 in total), the result for `http_server_requests_seconds_bucket` is that it needs `job, namespace, uri, method, outcome, pod, le`:
- `pod` and `method` are needed only by an incident drill-down query.
- `exception`, `instance` and `status` are never needed.
- That cuts 3,974,400 → 496,800 series.

**Without the incident queries in the corpus, the analysis would also strip `pod`.** That is cheaper but blinds on-call. The recommendation is exactly as good as the usage corpus: use 30–90 days of query logs from every reader.

### 1.2 Cardinality is a product of *independent* labels [M]

**Series = Π (cardinality of independent labels).**
- Labels that are functions of others (`instance` of `pod`; `container`, `id`, `image`, `name` of the cAdvisor pod/container) add **zero** series.
- Dropping them saves nothing. L2: `http_server_requests_seconds_count` stays at 57,600 without `instance`.

**The levers that matter**, from L2:

| Lever | Example | Effect |
|---|---|---|
| Unused families | `go_memstats_*`, `process_*`, cAdvisor's other 20 families, stale `kube_replicaset_*` | 346k series → 0 |
| Unused **independent** labels on big families | `status` and `exception` on 69-bucket histograms | 8× on the largest family |
| Histogram buckets | Folder 07 file 01: clamp 69 → 54, or SLO-only 4 | −20% to −90% per histogram |
| Unused derived metrics | `_sum`, `_max` of timers nobody reads | 115k → 0 |

### 1.3 Aggregation must be reset-aware [M]

```text
 pod b restarts at t=10m: its counter drops 9000 → 750 (a reset)
                    per-pod counters                         sum of raw counters
 a  ──────────────/────────────────/─────                 Σ ─────────/──────┐  ← sum DROPS by 8250
 b  ─────────/────┘(reset)/────────────                                     └──/─────────
 c  ──────────────/────────────────/─────                 rate(Σ) sees a "reset" → counts the whole
 sum(rate(per pod))  = 150 req/s (correct: each series      post-drop value as an increase
                       corrects its own reset)              → spike of +1,333 req/s for one window
 reset-aware aggregate = Σ (per-series reset-corrected increases)  = exact
```

**Counters reset when pods restart.** `rate()` handles resets *per series*.

**If you pre-aggregate by summing raw counters across pods**, one pod's reset becomes a drop in the *sum*.
- `rate()` then treats it as a reset of the whole sum and adds the entire post-drop value as an increase.
- L2 §3: truth is 150 req/s, and the naive sum spikes to an error of **1,333 req/s**.

**Correct options.**
- Aggregate **increases** (reset-corrected per series, then summed). L2's reset-aware variant is exact.
- Record `sum(rate(...))` as a recording rule (Folder 04), at the cost of losing raw-counter semantics downstream.
- Use a backend feature that does reset-aware aggregation. Grafana Cloud Adaptive Metrics aggregates at ingest and documents its counter handling ⚠, so check the semantics for each metric type before enabling it.

Folder 04's rule lint flags `rate()` over a recorded `…:sum` for the same reason.

### 1.4 Where to enforce, and what each layer can do [D]

| Layer | Mechanism | Can drop families | Can aggregate labels | Reset-safe | Owner |
|---|---|---|---|---|---|
| App | Micrometer `MeterFilter.deny`, closed tag sets, histogram policy (Folder 07 file 01) | yes | by not emitting | n/a | service team |
| Agent/collector | OTel `filter`, `transform`, `metricstransform`; Alloy `prometheus.relabel`, `otelcol.processor.*` | yes | yes (transform/aggregate) | depends ⚠ | platform |
| Scrape | `metric_relabel_configs` drop / labeldrop | yes | **labeldrop only if the result stays unique** | n/a | platform |
| Backend | Mimir per-tenant limits; Adaptive Metrics; Loki `retention_stream` | yes | yes (vendor) | vendor-defined | platform |

**`labeldrop` at scrape time is dangerous.** If the dropped label was needed for uniqueness (`pod`), multiple series collapse into duplicates. Prometheus rejects them as duplicate samples or out-of-order errors, and data is lost. Only drop labels that are functions of the remaining ones (§1.2), and aggregate everything else with a reset-aware aggregation.

### 1.5 Logs and traces: volume first, then indexing [M][D]

L2 §4 sets 3 TB/day with a typical level mix:
- drop debug at the agent;
- keep a 1% sample of health and readiness access logs;
- keep everything else.

The result is **3,000 → 1,356 GB/day (−55%)**, worth $27k/month at Grafana Cloud's $0.55/GB, or $140k/month in Datadog indexing at $1.70 per million 600-byte lines.

- **Traces.** Tail-sample by outcome (Folder 06 file 01). Keep 100% of errors and slow requests and a few percent baseline, and generate RED metrics *before* sampling.
- **Profiles.** Keep the default 19 Hz and aggregate across the fleet (Folder 06 file 03) instead of raising the rate.

<!-- listing:finops_lab.py -->
```python
"""finops_lab.py - find and remove telemetry nobody uses, safely.

  1. Usage extraction: every dashboard query (Folder 05 dashboard_lab.red_dashboard), every rule in the
     Folder 07 catalog (microservice-rules.yaml) and an ad-hoc query log are parsed with promql_mini.Parser
     (Folder 02); for each metric we collect the labels each query NEEDS (matchers, by/on labels, le for
     histogram_quantile; everything when a selector is not aggregated or aggregated with `without`).
  2. Inventory: a 6,000-container cluster's metric families with per-label cardinalities, including
     functionally dependent labels (instance ~ pod) that cost nothing to keep and save nothing to drop.
  3. Recommendations: drop unused families; aggregate away unused labels (what Grafana Adaptive Metrics or
     Mimir/Prometheus aggregation rules do) and compute the series removed.
  4. Proof on data: a dashboard query returns the same answer on aggregated series - IF the aggregation is
     reset-aware; naive summing of raw counters across pods turns one pod restart into a spike.
  5. Logs: drop/sample rules and their GB and $ effect.

Deterministic, stdlib only. Usage: python finops_lab.py [target.md]
"""
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from dashboard_lab import red_dashboard  # noqa: E402
from promql_mini import Engine, Parser  # noqa: E402
from rule_catalog_lab import load_yaml_subset  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
ALL = "*"


def needed_labels(ast):
    """metric name -> set of labels the query needs ('*' = all of them)."""
    out = {}

    def add(name, labels):
        out.setdefault(name, set()).update(labels)

    def walk(node, ctx):
        if not isinstance(node, tuple):
            return
        tag = node[0]
        if tag == "sel":
            _, name, ms, _ = node
            add(name, {m[0] for m in ms if m[0] != "__name__"} | (ctx if ctx != {ALL} else {ALL}))
            return
        if tag == "agg":
            _, op, param, expr, grouping, without = node
            inner = {ALL} if without or grouping is None and op in ("topk", "bottomk") else set(grouping or [])
            walk(expr, inner | ({l for l in ctx if l != ALL} if ctx != {ALL} else set()))
            if param is not None:
                walk(param, set())
            return
        if tag == "call":
            extra = {"le"} if node[1] == "histogram_quantile" else set()
            for a in node[2]:
                walk(a, ctx | extra if ctx != {ALL} else ctx)
            return
        if tag == "bin":
            opts = node[4] if len(node) > 4 and isinstance(node[4], dict) else {}
            on = set(opts.get("labels") or []) if opts.get("on") else set()
            for side in (node[2], node[3]):
                walk(side, ctx | on if ctx != {ALL} else ctx)
            return
        for child in node[1:]:
            if isinstance(child, tuple):
                walk(child, ctx)
            elif isinstance(child, list):
                for c in child:
                    walk(c, ctx)

    walk(ast, {ALL})
    return out


def queries():
    subst = {"$__rate_interval": "1m", "$job": "checkout", "$namespace": "shop"}
    qs = []
    for p in red_dashboard("checkout")["panels"]:
        for t in p.get("targets", []):
            e = t["expr"]
            for k, v in subst.items():
                e = e.replace(k, v)
            qs.append(("dashboard", e))
    doc = load_yaml_subset((HERE / "microservice-rules.yaml").read_text(encoding="utf-8"))
    for g in doc["groups"]:
        for r in g["rules"]:
            qs.append(("rule", r["expr"]))
    adhoc = ['topk(5, sum by (pod, status) (rate(http_server_requests_seconds_count{job="checkout", outcome="SERVER_ERROR"}[5m])))',
             'histogram_quantile(0.99, sum by (pod, method, uri, le) (rate(http_server_requests_seconds_bucket{job="checkout"}[5m])))',
             'sum by (pod) (rate(jvm_gc_pause_seconds_sum{job="checkout"}[5m]))',
             'topk(10, sum by (namespace, pod) (container_memory_working_set_bytes{container!=""}))',
             'sum by (namespace) (increase(kube_pod_container_status_restarts_total[1h])) > 3',
             'kube_deployment_status_replicas_available{namespace="shop"} / kube_deployment_spec_replicas{namespace="shop"}',
             'avg by (instance) (rate(node_cpu_seconds_total{mode!="idle"}[5m]))']
    qs += [("adhoc", q) for q in adhoc]
    return qs


# family -> {label: (cardinality, depends_on)}; depends_on means "1:1 with that label" (adds no series)
INVENTORY = {
    "http_server_requests_seconds_bucket": {"job": (30, None), "namespace": (1, "job"), "pod": (8, None),
                                            "instance": (1, "pod"), "uri": (15, None), "method": (2, None),
                                            "status": (4, None), "outcome": (1, "status"), "exception": (2, None),
                                            "le": (69, None)},
    "http_server_requests_seconds_count": {"job": (30, None), "namespace": (1, "job"), "pod": (8, None),
                                           "instance": (1, "pod"), "uri": (15, None), "method": (2, None),
                                           "status": (4, None), "outcome": (1, "status"), "exception": (2, None)},
    "http_server_requests_seconds_sum": {"job": (30, None), "pod": (8, None), "uri": (15, None), "method": (2, None),
                                         "status": (4, None), "exception": (2, None)},
    "http_server_requests_seconds_max": {"job": (30, None), "pod": (8, None), "uri": (15, None), "method": (2, None),
                                         "status": (4, None), "exception": (2, None)},
    "jvm_memory_used_bytes": {"job": (30, None), "pod": (8, None), "area": (2, None), "id": (4, None)},
    "jvm_memory_max_bytes": {"job": (30, None), "pod": (8, None), "area": (2, None), "id": (4, None)},
    "jvm_gc_pause_seconds_sum": {"job": (30, None), "namespace": (1, "job"), "pod": (8, None), "action": (2, None),
                                 "cause": (6, None), "gc": (2, None)},
    "hikaricp_connections_pending": {"job": (30, None), "namespace": (1, "job"), "pod": (8, None), "pool": (1, None)},
    "checkout_psp_latency_seconds_bucket": {"job": (1, None), "pod": (8, None), "psp": (4, None),
                                            "outcome": (2, None), "le": (54, None)},
    "container_cpu_cfs_throttled_periods_total": {"namespace": (40, None), "pod": (150, None), "container": (1, "pod"),
                                                  "id": (1, "pod"), "image": (1, "pod"), "name": (1, "pod")},
    "container_cpu_cfs_periods_total": {"namespace": (40, None), "pod": (150, None), "container": (1, "pod"),
                                        "id": (1, "pod"), "image": (1, "pod"), "name": (1, "pod")},
    "container_memory_working_set_bytes": {"namespace": (40, None), "pod": (150, None), "container": (1, "pod"),
                                           "id": (1, "pod"), "image": (1, "pod"), "name": (1, "pod")},
    "kube_pod_container_status_restarts_total": {"namespace": (40, None), "pod": (150, None), "container": (1, "pod"),
                                                 "uid": (1, "pod")},
    "kube_deployment_status_replicas_available": {"namespace": (40, None), "deployment": (12, None)},
    "kube_deployment_spec_replicas": {"namespace": (40, None), "deployment": (12, None)},
    "node_cpu_seconds_total": {"instance": (400, None), "cpu": (16, None), "mode": (8, None)},
    "up": {"job": (30, None), "pod": (8, None), "instance": (1, "pod")},
}
UNUSED_FAMILIES = {   # name: series (families no query touches)
    "go_memstats_* (25 families)": 25 * 240, "process_* (8 families)": 8 * 240, "jvm_buffer_* (3 families)": 3 * 240 * 3,
    "tomcat_sessions_* (6)": 6 * 240, "logback_events_total": 5 * 240, "executor_* (5)": 5 * 240 * 2,
    "container_* other cAdvisor (20)": 20 * 6000, "kube_replicaset_* stale (5)": 5 * 5000, "kube_pod_labels": 6000,
    "node_* other (150)": 150 * 400 * 3,
}


def series(fam, keep=None):
    n = 1
    for l, (card, dep) in INVENTORY[fam].items():
        if keep is not None and l not in keep:
            continue
        if dep is not None and (keep is None or dep in keep):
            continue
        n *= card
    return n


def main():
    checks = []
    print("== 1. Usage extracted from dashboards, rules and the query log (parsed by promql_mini) ==")
    qs = queries()
    usage = {}
    for src, q in qs:
        for name, labs in needed_labels(Parser(q).parse()).items():
            usage.setdefault(name, set()).update(labs)
    kinds = {k: sum(1 for s, _ in qs if s == k) for k in ("dashboard", "rule", "adhoc")}
    print(f"{len(qs)} queries ({kinds}); {len(usage)} metric names referenced")
    for name in sorted(usage):
        if name in INVENTORY:
            print(f"  {name:<44} needs {sorted(usage[name]) if ALL not in usage[name] else 'ALL labels'}")
    print()

    print("== 2. Recommendations: drop unused families, aggregate away unused labels ==")
    before = sum(series(f) for f in INVENTORY) + sum(UNUSED_FAMILIES.values())
    drop_fams = [f for f in INVENTORY if f not in usage]
    rows, after = [], 0
    for f in INVENTORY:
        if f in drop_fams:
            rows.append((f, series(f), 0, "drop: no query uses it"))
            continue
        need = usage[f]
        if ALL in need:
            after += series(f)
            rows.append((f, series(f), series(f), "keep all (a query needs every label)"))
            continue
        keep = set(need) | ({"le"} if f.endswith("_bucket") else set())
        dropped = sorted(set(INVENTORY[f]) - keep)
        s2 = series(f, keep)
        after += s2
        rows.append((f, series(f), s2, f"aggregate away {dropped}" if dropped else "keep"))
    for f, s1, s2, why in sorted(rows, key=lambda r: r[2] - r[1]):
        print(f"  {f:<44} {s1:>10,} -> {s2:>9,}  {why}")
    unused_total = sum(UNUSED_FAMILIES.values())
    print(f"  {'unused exporter families (' + str(len(UNUSED_FAMILIES)) + ' groups)':<44} {unused_total:>10,} -> {0:>9,}  drop")
    print(f"total active series {before:,} -> {after:,} ({1 - after / before:.0%} fewer)")
    saved = before - after
    print(f"at Grafana Cloud Pro list ($6.50 per 1k series): ${saved / 1000 * 6.5:,.0f}/month saved; at Datadog's "
          f"$5 per 100 custom metrics: ${saved / 100 * 5:,.0f}/month")
    inst_only = series("http_server_requests_seconds_count", set(INVENTORY["http_server_requests_seconds_count"]) - {"instance"})
    print(f"dropping only 'instance' (1:1 with pod) from http_server_requests_seconds_count: "
          f"{series('http_server_requests_seconds_count'):,} -> {inst_only:,} series (saves nothing)")
    print("-> the recommendation is only as good as the usage corpus: feed it 30-90 days of query logs from")
    print("   every Grafana, rule evaluator and API client, or an incident-time drill-down label disappears.")
    checks.append(("big reduction", after < 0.6 * before and inst_only == series("http_server_requests_seconds_count")))
    checks.append(("needs computed", "le" in usage["http_server_requests_seconds_bucket"]
                   and ALL in usage.get("kube_deployment_spec_replicas", set())))
    print()

    print("== 3. Is the aggregated data still correct? (3 pods, one restarts at t=10m) ==")
    eng_raw, eng_naive, eng_ra = Engine(), Engine(), Engine()
    pods, step = ["a", "b", "c"], 15000
    vals = {p: 0.0 for p in pods}
    offset = {p: 0.0 for p in pods}
    for k in range(80):
        T = k * step
        naive_sum, ra_sum = 0.0, 0.0
        for p in pods:
            if p == "b" and k == 40:
                offset[p] += vals[p]           # counter reset on restart
                vals[p] = 0.0
            vals[p] += 50.0 * 15
            eng_raw.add({"__name__": "reqs_total", "job": "checkout", "pod": p}, [(T, vals[p])])
            naive_sum += vals[p]
            ra_sum += vals[p] + offset[p]
        eng_naive.add({"__name__": "reqs_total", "job": "checkout"}, [(T, naive_sum)])
        eng_ra.add({"__name__": "reqs_total", "job": "checkout"}, [(T, ra_sum)])
    q = Parser("sum by (job) (rate(reqs_total[1m]))").parse()
    worst_ra = worst_naive = 0.0
    for k in range(8, 80):
        T = k * step
        r = eng_raw.eval(q, T)[0][1]
        worst_ra = max(worst_ra, abs(eng_ra.eval(q, T)[0][1] - r))
        worst_naive = max(worst_naive, abs(eng_naive.eval(q, T)[0][1] - r))
    print(f"truth: 150 req/s. reset-aware aggregated counter: max error {worst_ra:.2e} req/s; naive sum of raw counters: "
          f"max error {worst_naive:,.0f} req/s around the restart")
    checks.append(("reset-aware aggregation exact", worst_ra < 1e-9 and worst_naive > 100))
    print("-> aggregate counters on increases (reset-aware), or record sum(rate()) - never sum raw counters.")
    print()

    print("== 4. Logs: what dropping and sampling are worth (3 TB/day) ==")
    mix = {"debug": 0.35, "info: health/readiness access logs": 0.20, "info: business": 0.35, "warn": 0.07, "error": 0.03}
    keep = {"debug": 0.0, "info: health/readiness access logs": 0.01, "info: business": 1.0, "warn": 1.0, "error": 1.0}
    gb = 3000
    kept = sum(gb * s * keep[k] for k, s in mix.items())
    for k, s in mix.items():
        print(f"  {k:<36} {gb * s:>6,.0f} GB/day -> {gb * s * keep[k]:>6,.0f}")
    print(f"total {gb:,} -> {kept:,.0f} GB/day ({1 - kept / gb:.0%} less); Grafana Cloud at $0.55/GB: "
          f"${(gb - kept) * 30 * 0.55:,.0f}/month; Datadog indexing at $1.70/M (600 B lines): "
          f"${(gb - kept) * 30 * 1e9 / 600 / 1e6 * 1.70:,.0f}/month")
    checks.append(("logs halved", kept < 0.5 * gb))
    print("-> drop at the agent (Alloy loki.process stage.drop / OTel filter), keep errors 100%, and keep a")
    print("   1% sample of high-volume access logs for forensics instead of nothing.")
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:finops_lab.py -->
```text
== 1. Usage extracted from dashboards, rules and the query log (parsed by promql_mini) ==
42 queries ({'dashboard': 8, 'rule': 27, 'adhoc': 7}); 31 metric names referenced
  checkout_psp_latency_seconds_bucket          needs ['job', 'le', 'psp']
  container_cpu_cfs_periods_total              needs ['container', 'namespace', 'pod']
  container_cpu_cfs_throttled_periods_total    needs ['container', 'namespace', 'pod']
  container_memory_working_set_bytes           needs ['container', 'namespace', 'pod']
  hikaricp_connections_pending                 needs ['job', 'namespace', 'pod', 'pool']
  http_server_requests_seconds_bucket          needs ['job', 'le', 'method', 'namespace', 'outcome', 'pod', 'uri']
  http_server_requests_seconds_count           needs ['job', 'namespace', 'outcome', 'pod', 'status', 'uri']
  jvm_gc_pause_seconds_sum                     needs ['job', 'namespace', 'pod']
  jvm_memory_max_bytes                         needs ['area', 'job', 'pod']
  jvm_memory_used_bytes                        needs ['area', 'job', 'pod']
  kube_deployment_spec_replicas                needs ALL labels
  kube_deployment_status_replicas_available    needs ALL labels
  kube_pod_container_status_restarts_total     needs ['namespace']
  node_cpu_seconds_total                       needs ['instance', 'mode']
  up                                           needs ALL labels

== 2. Recommendations: drop unused families, aggregate away unused labels ==
  http_server_requests_seconds_bucket           3,974,400 ->   496,800  aggregate away ['exception', 'instance', 'status']
  http_server_requests_seconds_sum                 57,600 ->         0  drop: no query uses it
  http_server_requests_seconds_max                 57,600 ->         0  drop: no query uses it
  node_cpu_seconds_total                           51,200 ->     3,200  aggregate away ['cpu']
  http_server_requests_seconds_count               57,600 ->    14,400  aggregate away ['exception', 'instance', 'method']
  kube_pod_container_status_restarts_total          6,000 ->        40  aggregate away ['container', 'pod', 'uid']
  jvm_gc_pause_seconds_sum                          5,760 ->       240  aggregate away ['action', 'cause', 'gc']
  checkout_psp_latency_seconds_bucket               3,456 ->       216  aggregate away ['outcome', 'pod']
  jvm_memory_used_bytes                             1,920 ->       480  aggregate away ['id']
  jvm_memory_max_bytes                              1,920 ->       480  aggregate away ['id']
  hikaricp_connections_pending                        240 ->       240  keep
  container_cpu_cfs_throttled_periods_total         6,000 ->     6,000  aggregate away ['id', 'image', 'name']
  container_cpu_cfs_periods_total                   6,000 ->     6,000  aggregate away ['id', 'image', 'name']
  container_memory_working_set_bytes                6,000 ->     6,000  aggregate away ['id', 'image', 'name']
  kube_deployment_status_replicas_available           480 ->       480  keep all (a query needs every label)
  kube_deployment_spec_replicas                       480 ->       480  keep all (a query needs every label)
  up                                                  240 ->       240  keep all (a query needs every label)
  unused exporter families (10 groups)            346,120 ->         0  drop
total active series 4,583,016 -> 535,296 (88% fewer)
at Grafana Cloud Pro list ($6.50 per 1k series): $26,310/month saved; at Datadog's $5 per 100 custom metrics: $202,386/month
dropping only 'instance' (1:1 with pod) from http_server_requests_seconds_count: 57,600 -> 57,600 series (saves nothing)
-> the recommendation is only as good as the usage corpus: feed it 30-90 days of query logs from
   every Grafana, rule evaluator and API client, or an incident-time drill-down label disappears.

== 3. Is the aggregated data still correct? (3 pods, one restarts at t=10m) ==
truth: 150 req/s. reset-aware aggregated counter: max error 0.00e+00 req/s; naive sum of raw counters: max error 1,333 req/s around the restart
-> aggregate counters on increases (reset-aware), or record sum(rate()) - never sum raw counters.

== 4. Logs: what dropping and sampling are worth (3 TB/day) ==
  debug                                 1,050 GB/day ->      0
  info: health/readiness access logs      600 GB/day ->      6
  info: business                        1,050 GB/day ->  1,050
  warn                                    210 GB/day ->    210
  error                                    90 GB/day ->     90
total 3,000 -> 1,356 GB/day (55% less); Grafana Cloud at $0.55/GB: $27,126/month; Datadog indexing at $1.70/M (600 B lines): $139,740/month
-> drop at the agent (Alloy loki.process stage.drop / OTel filter), keep errors 100%, and keep a
   1% sample of high-volume access logs for forensics instead of nothing.

checks: 4/4 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 Usage capture: Grafana and Prometheus query logs

```yaml
# Prometheus: log every query (rotate the file; ship to Loki for the usage corpus)
global:
  query_log_file: /prometheus/query.log
```

```yaml
# Mimir: per-tenant query stats in the query-frontend logs (feed the same corpus)
frontend:
  query_stats_enabled: true
  log_queries_longer_than: -1s
```

**Mining the corpus.**
- Parse every logged query with a PromQL parser. L2's `needed_labels` walks the AST.
- Union "needed labels" per metric over 30–90 days.
- Treat rule files and dashboard JSON as permanent usage, even if they ran rarely: incident dashboards are opened once a quarter.

**Mimir semantics** [D], from the 3.2.4 config descriptor:
- `log_queries_longer_than` "Set to 0 to disable. Set to < 0 to enable on all queries", so `-1s` logs every query. Watch the log volume and sample if needed.
- `query_stats_enabled` defaults to true.

### 2.2 Drop and aggregate in the collector tier (Alloy)

```alloy
// Drop whole families nobody reads, before they cost anything downstream.
prometheus.relabel "drop_unused" {
  forward_to = [prometheus.remote_write.mimir.receiver]
  rule {
    source_labels = ["__name__"]
    regex         = "go_memstats_.*|process_.*|jvm_buffer_.*|tomcat_sessions_.*|http_server_requests_seconds_(sum|max)"
    action        = "drop"
  }
  // Labels that are pure functions of others (instance ~ pod; cAdvisor id/image/name ~ container) can be
  // dropped safely; uniqueness is preserved.
  rule {
    regex  = "id|image|name"
    action = "labeldrop"
  }
}

prometheus.remote_write "mimir" {
  endpoint {
    url     = "http://mimir-distributor.mimir.svc:8080/api/v1/push"
    headers = { "X-Scope-OrgID" = "prod" }
  }
}
```

⚠ **Scope the `labeldrop` to cAdvisor jobs.** The second rule removes `id`, `image` and `name` from *every* series passing this component. Scope it, for example by routing cAdvisor through its own `prometheus.relabel`, or a metric that legitimately uses `name` loses uniqueness.

### 2.3 Aggregate away unused independent labels with recording rules (reset-safe)

```yaml
groups:
  - name: finops-aggregations
    interval: 1m
    rules:
      # Replaces raw per-pod/status/exception buckets for long retention: rates are reset-safe per series.
      - record: job_namespace_uri_method_outcome:http_server_requests_seconds_bucket:rate1m
        expr: |
          sum by (job, namespace, uri, method, outcome, le) (
            rate(http_server_requests_seconds_bucket[1m])
          )
      - record: job:jvm_gc_pause_seconds_sum:rate1m
        expr: sum by (job) (rate(jvm_gc_pause_seconds_sum[1m]))
```

**Pairing with retention.**
- Keep raw series short in Mimir via `compactor_blocks_retention_period` per tenant, or in a separate short-retention tenant.
- Keep the aggregated recording-rule outputs for 13 months.
- Dashboards beyond the raw retention read the recorded series. The rules aggregate **rates**, so pod restarts are handled (§1.3).

### 2.4 Logs: drop and sample at the edge (Alloy)

```alloy
loki.process "finops" {
  stage.json {
    expressions = { level = "level", path = "path" }
  }
  stage.drop {
    source              = "level"
    value               = "debug"
    drop_counter_reason = "finops_debug"
  }
  stage.match {
    selector = "{app=~\".+\"} |~ \"/actuator/(health|readiness|liveness)\""
    stage.sampling {
      rate = 0.01
    }
  }
  forward_to = [loki.write.default.receiver]
}

loki.write "default" {
  endpoint {
    url       = "http://loki-gateway.loki.svc/loki/api/v1/push"
    tenant_id = "prod"
  }
}
```

### 2.5 Budgets and unit economics

```promql
# Active series per team (team label from ServiceMonitor targetLabels, Folder 07 file 02)
sort_desc(count by (team) ({__name__=~".+"}))

# Monthly $ per team at a chosen unit price (example: $6.50 per 1k series)
count by (team) ({__name__=~".+"}) / 1000 * 6.50

# Budget burn: alert when a team exceeds 80% of its series budget (budget stored as a recording rule/series)
count by (team) ({__name__=~".+"}) / on(team) team:series_budget:value > 0.8

# Top metric families by series (the first place to look)
topk(20, count by (__name__) ({__name__=~".+"}))
```

⚠ **`{__name__=~".+"}` touches every series.** Run it on a schedule as a recording rule in a low-traffic window, or use the TSDB status API / Mimir cardinality API instead of in dashboards.

---

## 3. Failure modes and FinOps debugging

### F1. A dashboard silently changes after "harmless" aggregation

**Symptom.** After an aggregation rollout, request rates show spikes at every deploy.

**Signature.** Raw counters were summed across pods at ingest (or via a naive recording rule), and `rate()` runs on the sum. Spikes align with pod restarts.

**Root cause.** The aggregation is not reset-aware (§1.3). L2 measures a 1,333 req/s error from one restart.

**Fix.** Aggregate rates or reset-corrected increases. Re-derive dashboards from those.

**Prevention.** A correctness test like L2 §3 for every aggregation rule before rollout. Folder 04's lint flags rate-over-sum.

### F2. Incident drill-down missing at 3 AM

**Symptom.** During an incident, on-call can't see which pod is failing, because `pod` was aggregated away.

**Signature.** The usage corpus held only dashboards and rules, not ad-hoc and incident queries.

**Root cause.** A corpus too small (L2 §2 shows `pod` kept only because the incident queries were included).

**Fix.** Restore `pod` on golden-signal metrics, or keep raw per-pod series with short retention alongside the aggregates.

**Prevention.**
- 30–90-day query-log corpus.
- A protected-label list (`pod`, `namespace`, `job`) for RED metrics.
- Short raw retention plus long aggregated retention.

### F3. Duplicate-sample errors after `labeldrop`

**Symptom.** After adding `labeldrop`, Prometheus logs duplicate sample timestamps and some series lose data.

**Signature.** The dropped label was needed for uniqueness (e.g. `pod` or `instance` where it is the only distinguishing label).

**Root cause.** `labeldrop` doesn't aggregate. It collapses distinct series into one identity.

**Fix.** Revert. Use aggregation (recording rules or collector transforms) for independent labels, and `labeldrop` only for derived ones (§1.2).

**Prevention.** A pre-rollout check: for each `labeldrop`, verify `count by (remaining labels)` equals `count` on a sample.

### F4. Savings that never materialise

**Symptom.** A FinOps project "removed" 2M series, but the bill didn't move.

**Signature.**
- The drop happened in dashboards, not at ingest.
- Or it was dropped at scrape in one Prometheus while another path still remote-writes it.
- Or the drop applies after the billed hop (SaaS bills on intake).

**Root cause.** Enforcement at the wrong layer (§1.4).

**Fix.** Drop at the first hop that is billed or stored: the app, agent or collector.

**Prevention.** Measure savings at the billing source (vendor usage API, `cortex_ingester_memory_series`), not in dashboards.

### F5. Cardinality grows back

**Symptom.** Three months after a cleanup, series are back to 90% of the old level.

**Signature.** New services, new tags and new histograms, with no budgets.

**Root cause.** A one-off cleanup without a control loop.

**Fix.** Re-run the usage analysis and the drop/aggregate rollout for the regrown families. Assign each regrowth to its owning team via the `team` label.

**Prevention.**
- Per-team budgets with 80% alerts (§2.5).
- Series-budget tests in CI (Folder 07 file 01).
- Backend limits per tenant (Mimir).
- A monthly top-20 families review.

### F6. Debug logs dropped, root cause lost

**Symptom.** A rare bug needs debug logs, and they were dropped at the edge.

**Signature.** An unconditional `stage.drop` on `level=debug` everywhere.

**Root cause.** A volume policy with no escape hatch.

**Fix.**
- Dynamic log levels per service (Spring Boot actuator `loggers` endpoint).
- A short-retention debug tenant or stream (`retention_stream` 24h).
- Time-boxed exemptions.

**Prevention.** Codify the escape hatch in the logging policy and test it during game days.

### F7. Sampling breaks per-customer SLAs

**Symptom.** An enterprise customer disputes an SLA breach. Sampled traces and logs can't prove what happened to their requests.

**Signature.** Probabilistic sampling without tenant-aware policies.

**Root cause.** Uniform sampling treats contractual tenants like anonymous traffic.

**Fix.**
- Tenant-aware tail-sampling policies (always keep regulated or contractual tenants; Folder 06 file 01).
- Per-tenant RED metrics from unsampled data.

**Prevention.** Map contractual obligations to telemetry retention and sampling in the FinOps policy itself.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "Cut observability spend 40% this quarter without losing visibility."</b></summary>

**Initial Prompt.** The CFO mandate is non-negotiable.

**L5 Textbook Answer.** Reduce retention and sample more traces.

**Why L5 Fails at 3 AM or on the Bill.** Retention cuts lose year-over-year analysis. Uniform sampling loses the error traces you need. Neither targets the biggest unit drivers, which are unused series and indexed logs.

**L7 Principal Defense.** Run the control loop.
1. **Measure usage.** Build the query-log corpus.
2. **Inventory.** Top families, labels and log streams.
3. **Remove what is never read.** In L2: 88% of series and 55% of log volume, with dashboards and rules unchanged.
4. **Enforce at the first billed hop** (collector or agent).
5. **Prove correctness.** Reset-aware aggregation tested as in L2 §3; incident queries kept.
6. **Keep it there.** Budgets per team with alerts.

Then negotiate SaaS prices or right-size self-hosted capacity on the reduced volume. 40% is conservative when most units are waste.
</details>

<details><summary><b>Q2 · "Which metrics can we safely drop?"</b></summary>

**Initial Prompt.** A team wants a list by Friday.

**L5 Textbook Answer.** Anything not on a dashboard.

**Why L5 Fails at 3 AM or on the Bill.** It misses alert and recording rules, API consumers, autoscalers (HPA and KEDA query metrics), SLO reports and incident-time ad-hoc queries. Dropping their inputs breaks automation silently.

**L7 Principal Defense.**
- **Corpus:** dashboards plus all rule files plus 90 days of query logs from Grafana, the ruler, HPA/KEDA adapters and API clients.
- **Analysis:** parse to "needed labels per metric" (L2 §1).
- **Decisions:**
  - drop unused families;
  - aggregate unused *independent* labels with reset-aware rules;
  - `labeldrop` only derived labels;
  - keep raw per-pod series at short retention for incidents.
- **Rollout:** canary on one tenant with a numeric diff of every dashboard query before and after.
</details>

<details><summary><b>Q3 · "Is Adaptive Metrics (ingest-time aggregation) safe?"</b></summary>

**Initial Prompt.** The vendor says it cuts 50–80%.

**L5 Textbook Answer.** Yes, it's automatic.

**Why L5 Fails at 3 AM or on the Bill.** Automatic recommendations are only as good as the usage window. A quarterly incident dashboard looks unused. Counter aggregation semantics determine whether `rate()` stays correct across restarts (L2 §3).

**L7 Principal Defense.**
- Treat recommendations as proposals.
- Pin protected labels for golden signals.
- Verify counter and histogram semantics per metric type in the vendor docs ⚠.
- Run an A/B: a shadow tenant with aggregation applied, with numeric diffs of dashboards and rules.
- Roll out by team with a rollback switch.
- Track savings at the billing meter.
</details>

<details><summary><b>Q4 · "Logs are our biggest line item. What do you do?"</b></summary>

**Initial Prompt.** 3 TB/day, all indexed.

**L5 Textbook Answer.** Shorten retention to 7 days.

**Why L5 Fails at 3 AM or on the Bill.** Retention isn't the driver on most SaaS: ingestion and indexing per GB or per event are. Shorter retention also hurts audits and slow-burning investigations.

**L7 Principal Defense.**
- **Volume first** (L2 §4: debug dropped, 1% health sampling, −55%).
- **Then index vs archive.** Index the ~15% that is searched, archive the rest cheaply (File 01: $335k → $119k on Datadog list).
- **On Loki**, labels decide object count (Folder 06 file 03), so fix label design.
- **Keep an escape hatch** for debug (F6).
- **Make every app's log bill visible** (`bytes_over_time` by app).
</details>

<details><summary><b>Q5 · "Why didn't removing 2M series reduce the bill?"</b></summary>

**Initial Prompt.** Finance is asking.

**L5 Textbook Answer.** Billing lags; wait a month.

**Why L5 Fails at 3 AM or on the Bill.** Usually the series were removed in the wrong place: dashboards, or one of two write paths. Or the SaaS bills at intake before the drop happened.

**L7 Principal Defense.**
- Trace each data path from source to billed hop (agents, collectors, remote-write fan-outs, federations).
- Confirm the drop at the first billed or stored hop with the vendor usage API or `cortex_ingester_memory_series`.
- Check for a second exporter: Datadog agent *and* OTel both shipping.
- Then set a measurement-based savings report, not a configuration-based one.
</details>

<details><summary><b>Q6 · "How do you make teams own their telemetry cost?"</b></summary>

**Initial Prompt.** The platform team is the bottleneck.

**L5 Textbook Answer.** Send a monthly report.

**Why L5 Fails at 3 AM or on the Bill.** Reports without budgets or levers don't change behaviour, and central teams can't judge which series matter to a service.

**L7 Principal Defense.**
- **Attribute cost to `team`.** It comes from Service labels, not developer memory (Folder 07 file 02).
- **Unit prices:** $/1k series, $/GB.
- **Budgets with 80% alerts** routed to the team (§2.5).
- **Self-serve levers:** MeterFilters and histogram policies in code (Folder 07 file 01), drop rules via PR to the collector config.
- **A CI series-budget test** per service.
- **Platform sets guardrails** (enforced limits) and teams decide trade-offs within them.
</details>

<details><summary><b>Q7 · "What's the cost of a histogram?"</b></summary>

**Initial Prompt.** A team enabled histograms on 40 timers.

**L5 Textbook Answer.** A few extra series.

**Why L5 Fails at 3 AM or on the Bill.** With Micrometer defaults, each timer × tag set exposes **69 bucket series** + count + sum + max (Folder 07 file 01, verified against the real registry). 40 timers × 400 tag sets × 72 × pods is millions of series.

**L7 Principal Defense.**
- Compute it before merging: buckets × tag sets × pods.
- Clamp min/max (69 → 54) and add SLO boundaries only at alert thresholds.
- Enable histograms only on SLO-bearing timers, or use SLO-only buckets (4).
- Consider native histograms end to end where the pipeline supports them ⚠.
- L2 shows aggregating unused independent labels on the bucket family is the largest single saving (3.97M → 497k).
</details>

<details><summary><b>Q8 · "Unit economics: what's our cost per request observed?"</b></summary>

**Initial Prompt.** The CTO wants one number.

**L5 Textbook Answer.** Total bill divided by requests.

**Why L5 Fails at 3 AM or on the Bill.** It hides which signal and team drive cost, and it rewards sending less of the *useful* telemetry.

**L7 Principal Defense.**
- Report $/1M requests per service, decomposed into metrics ($/series × series per service), logs ($/GB × GB per service) and traces (kept spans × $/GB).
- Pair it with value metrics: MTTD and MTTR, alert actionability.
- Set targets on waste (unused series %, indexed-but-never-searched logs %), not on total spend.
- The L2-style usage analysis turns waste into a measurable KPI.
</details>

---

## 5. Invariants checklist

- [ ] A usage corpus of 30–90 days of queries (dashboards, rules, ad-hoc, autoscalers, APIs) drives every drop decision.
- [ ] Only labels that are functions of others are `labeldrop`ped; independent labels are aggregated with reset-aware rules.
- [ ] Every aggregation is proven numerically equal on dashboards and rules before rollout (L2 §3 pattern).
- [ ] Protected labels (`job`, `namespace`, `pod`) stay on golden-signal metrics, at least with short raw retention.
- [ ] Drops happen at the first billed or stored hop; savings are measured at the billing meter.
- [ ] Per-team budgets in series and GB, with 80% alerts; a monthly top-families review.
- [ ] The logs policy has volume rules, index-vs-archive, and a debug escape hatch.

---

## 6. References

- Prometheus query log (`query_log_file`): <https://prometheus.io/docs/guides/query-log/>
- Prometheus relabeling (`labeldrop`, `drop`): <https://prometheus.io/docs/prometheus/latest/configuration/configuration/#relabel_config>
- Grafana Adaptive Metrics: <https://grafana.com/docs/grafana-cloud/cost-management-and-billing/reduce-costs/metrics-costs/control-metrics-usage-via-adaptive-metrics/>
- Grafana Cloud pricing: <https://grafana.com/pricing/>
- Datadog custom metrics billing: <https://docs.datadoghq.com/account_management/billing/custom_metrics/>
- OTel Collector filter processor: <https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/v0.164.0/processor/filterprocessor/README.md>
- Alloy `prometheus.relabel`: <https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.relabel/>
- Alloy `loki.process`: <https://grafana.com/docs/alloy/latest/reference/components/loki/loki.process/>
- FinOps Foundation framework: <https://www.finops.org/framework/>
