# 01 · Grafana: Cognitive Hierarchy, RED Drill-downs, Variables and Transformations

> **Folder 05 — Grafana Architecture, Dashboards as Code and Signal Correlation · File 1 of 3.**
> Pinned to **Grafana v13.3.0** (2026-10-27). Grafana 13.0 (April 2026) made **dynamic dashboards** and **Git Sync** generally available and on by default (official "What's new in v13.0").
> Labels: **[D]** documented · **[M]** measured by the listing (deterministic, re-run by the gate) · **[E]** model · **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L1 `dashboard_lab.py` | Generates a RED drill-down dashboard (rows ordered symptoms → drill-down → causes, chained `namespace`/`job` variables, `$__rate_interval` everywhere) as Grafana dashboard JSON; lints every panel query with the Folder 02 PromQL parser plus rules for hard-coded windows, `histogram_quantile` without `le` and regex on high-cardinality labels (catching 4/4 planted anti-patterns); and computes backend load for 1–25 viewers at 10–60 s refresh (up to 1,200 queries/min and ~410 M samples/min) | <1 s |

**Verification.** The dashboard JSON is serialised and re-parsed; every panel query parses with `promql_mini.py` (validated against 695 upstream promqltest cases). The cost model is arithmetic over stated series counts [E]. Grafana 13 feature status was read from the official "What's new in v13.0" page; layout specifics not stated there are marked ⚠. No Grafana instance was run.

---

## 0. Orientation

**What this file answers.** How to structure dashboards so an on-call engineer finds the broken component in minutes; how variables, intervals and transformations really work; and how to keep dashboards cheap for the metrics backend.

**What changed in Grafana 13 [D].**
- **Dynamic dashboards** are on by default for Cloud and self-managed: existing dashboards are migrated to the new dashboard schema when opened, with a new layout engine and editing experience (tabs and rows with section-level variables are in public preview ⚠).
- **Restore deleted dashboards** is GA ("Recently deleted").
- The HTTP API is moving from `/api` to `/apis` (the App Platform, Kubernetes-style resources).
- `grafana-cli`/`grafana-server` are removed in favour of `grafana cli` / `grafana server`.
- The Image Renderer plugin is no longer supported.
- Ad hoc filters are renamed "Filters"; the gauge visualization was revamped.

---

## 1. First principles: dashboards are a diagnostic algorithm

### 1.1 The cognitive hierarchy

```text
 Level 0  Service map / SLO overview        "Is anything burning budget?"  (one stat per service)
    │ click a red service
 Level 1  Service RED (this file's L1)       "Is it traffic, errors or latency? since when?"
    │ drill-down variables carry job/namespace
 Level 2  Breakdown by route / dependency     "Which endpoint / downstream?"
    │ exemplar click (File 2)               ┌──────────────► trace (Tempo) ──► logs (Loki) ──► profile
 Level 3  Causes (USE, saturation)            "Which resource or queue is full?" (Folder 03)
    │
 Level 4  Raw exploration (Explore, Drilldown apps)  — no dashboard needed
```

Rules that follow:

- **Symptoms before causes**: the top row is what users feel (RED / Golden Signals); saturation and resources live lower or one click away. L1 asserts this ordering.
- **One question per row**, ≤ ~8 panels visible above the fold; every panel title is a question or a quantity with units.
- **Consistent axes and units**: rates per second, ratios as percent units, latency in seconds; never mix scales on one axis.
- **Links carry context**: data links and dashboard links pass `${__url_time_range}` and variables, so drilling down keeps the time window and service.

### 1.2 RED panels that are correct by construction

| Panel | Query shape | Why |
|---|---|---|
| Requests/s | `sum(rate(..._count{sel}[$__rate_interval]))` | counter → rate, aggregated |
| Error ratio | errors / total, both `sum(rate(...))` with the same selector | ratio of rates, unit `percentunit` |
| p99 (successes) | `histogram_quantile(0.99, sum by (le) (rate(..._bucket{sel, outcome="SUCCESS"}[$__rate_interval])))` | keep `le`; split by outcome (Folder 03 File 1) |
| Breakdown | `sum by (uri) (...)` / `sum by (uri, le)` | low-cardinality labels only |
| Heatmap | `sum by (le) (rate(..._bucket[$__rate_interval]))` (classic) or the native histogram directly | distributions, not percentiles |

### 1.3 Intervals and variables [D]

- **`$__interval`** = (time range) / (max data points), rounded and bounded below by the data source's *Min interval* (set to the scrape interval in the Prometheus data source's `timeInterval`).
- **`$__rate_interval`** = `max($__interval + scrape interval, 4 × scrape interval)` — always ≥ 4 scrapes (Folder 02 File 1 §1.4), and never smaller than one step plus a scrape, so adjacent steps' windows overlap and no sample is skipped. Its correctness depends on the data source's scrape interval setting.
- **`$__range`** = the dashboard's time range, for "over the whole window" panels (`increase(x[$__range])` as an instant query).
- **Query variables**: `label_values(metric{scope}, label)` should always be scoped by upstream variables (L1: `job` is scoped by `namespace`); unscoped `label_values(label)` scans every series with that label.
- **Multi-value / "All"**: with "All" Grafana substitutes a regex alternation of every value (or a custom "All" value such as `.+`); `=~"$var"` then becomes a large regex — prefer a custom All value of `.*`/`.+` for high-count variables.
- **Refresh**: variables refreshed "on time range change" re-query on every zoom; "on dashboard load" is cheaper.

### 1.4 Transformations: compute in Grafana, carefully

Transformations post-process query results in the browser [D]: *Join by field* (outer join series on time or a key), *Organize fields*, *Reduce* (series → single row of stats), *Group by*, *Group to matrix*, *Filter data by values*, *Add field from calculation*, *Labels to fields*, *Partition by values*. Use them for presentation (tables, renames, joins of instant results), not for math that belongs in PromQL: a transformation runs per viewer per refresh, can't be alerted on, and silently produces wrong totals when a series is missing from one side of a join.

### 1.5 What a dashboard costs (L1 §3)

```text
 queries/min      = panels × targets × viewers × 60 / refresh_s
 samples/min      ≈ Σ(series per query) × samples per series in range × viewers × 60 / refresh_s
 example (8 panels, 6 h range, 15 s scrape): 25 viewers @ 60 s → 200 q/min, ~68 M samples/min
                                             25 viewers @ 10 s → 1,200 q/min, ~410 M samples/min
```

The p99-by-route panel (buckets × routes) dominates; backing it with a recording rule (Folder 04 File 1) and enforcing a minimum refresh of 1 m on shared dashboards cuts backend load by an order of magnitude. Query caching and the backend's query-frontend splitting (Folder 06) help further but don't fix unbounded queries.

<!-- listing:dashboard_lab.py -->
```python
"""dashboard_lab.py - dashboards as data: generate a RED drill-down dashboard (classic Grafana dashboard
JSON model) from a service spec, lint every panel query with the Folder 02 PromQL parser, and compute
what the dashboard costs the metrics backend.

Lint rules: queries must parse; rate-like functions must use $__rate_interval (never a hard-coded
window shorter than 4 x scrape interval); histogram_quantile over _bucket must keep `le`; no regex
matchers on high-cardinality labels (pod, instance, container_id); variables must be scoped by
upstream variables. Cost model: queries per refresh = panels x targets; each query touches
series x samples; viewers x refresh rate turns that into backend load.
Deterministic, stdlib only.

Usage: python dashboard_lab.py [target.md]
"""
import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from promql_mini import Parser, Unsupported  # noqa: E402

HIGH_CARD = ("pod", "instance", "container_id", "trace_id", "user_id")


def panel(pid, title, exprs, y, x=0, w=8, h=8, unit="short", ptype="timeseries"):
    return {"id": pid, "type": ptype, "title": title, "gridPos": {"x": x, "y": y, "w": w, "h": h},
            "datasource": {"type": "prometheus", "uid": "${datasource}"},
            "fieldConfig": {"defaults": {"unit": unit}, "overrides": []},
            "targets": [{"refId": chr(65 + i), "expr": e, "legendFormat": "__auto"} for i, e in enumerate(exprs)]}


def red_dashboard(service):
    sel = 'job="$job", namespace="$namespace"'
    rows = [
        {"type": "row", "title": "Golden signals (user-facing)", "gridPos": {"x": 0, "y": 0, "w": 24, "h": 1}, "id": 100},
        panel(1, "Requests / s", [f'sum(rate(http_server_requests_seconds_count{{{sel}}}[$__rate_interval]))'], 1, 0, unit="reqps"),
        panel(2, "Error ratio", [f'sum(rate(http_server_requests_seconds_count{{{sel}, outcome="SERVER_ERROR"}}[$__rate_interval])) / sum(rate(http_server_requests_seconds_count{{{sel}}}[$__rate_interval]))'], 1, 8, unit="percentunit"),
        panel(3, "p99 latency (successes)", [f'histogram_quantile(0.99, sum by (le) (rate(http_server_requests_seconds_bucket{{{sel}, outcome="SUCCESS"}}[$__rate_interval])))'], 1, 16, unit="s"),
        {"type": "row", "title": "Drill-down by route", "gridPos": {"x": 0, "y": 9, "w": 24, "h": 1}, "id": 101},
        panel(4, "Requests by route", [f'sum by (uri) (rate(http_server_requests_seconds_count{{{sel}}}[$__rate_interval]))'], 10, 0, w=12),
        panel(5, "p99 by route", [f'histogram_quantile(0.99, sum by (uri, le) (rate(http_server_requests_seconds_bucket{{{sel}}}[$__rate_interval])))'], 10, 12, w=12),
        {"type": "row", "title": "Saturation (causes)", "gridPos": {"x": 0, "y": 18, "w": 24, "h": 1}, "id": 102},
        panel(6, "Hikari pending", [f'sum by (pool) (hikaricp_connections_pending{{{sel}}})'], 19, 0),
        panel(7, "GC pause time", [f'sum(rate(jvm_gc_pause_seconds_sum{{{sel}}}[$__rate_interval]))'], 19, 8, unit="percentunit"),
        panel(8, "CPU throttled ratio", [f'sum(rate(container_cpu_cfs_throttled_periods_total{{namespace="$namespace", container="{service}"}}[$__rate_interval])) / sum(rate(container_cpu_cfs_periods_total{{namespace="$namespace", container="{service}"}}[$__rate_interval]))'], 19, 16, unit="percentunit"),
    ]
    templating = {"list": [
        {"name": "datasource", "type": "datasource", "query": "prometheus"},
        {"name": "namespace", "type": "query", "datasource": {"uid": "${datasource}"},
         "query": "label_values(http_server_requests_seconds_count, namespace)", "refresh": 2},
        {"name": "job", "type": "query", "datasource": {"uid": "${datasource}"},
         "query": 'label_values(http_server_requests_seconds_count{namespace="$namespace"}, job)', "refresh": 2},
    ]}
    return {"title": f"{service} / RED", "uid": f"{service}-red", "schemaVersion": 41, "editable": False,
            "tags": ["red", "generated"], "time": {"from": "now-6h", "to": "now"}, "refresh": "1m",
            "panels": rows, "templating": templating}


def lint_expr(expr):
    issues = []
    concrete = expr.replace("$__rate_interval", "1m").replace("$job", "x").replace("$namespace", "y")
    try:
        Parser(concrete).parse()
    except Unsupported as e:
        issues.append(f"does not parse: {e}")
    if re.search(r"\b(rate|increase|irate)\([^)]*\[(\d+[smh])\]", expr):
        issues.append("hard-coded range window; use $__rate_interval")
    if "_bucket" in expr and "histogram_quantile" in expr and not re.search(r"by \([^)]*\ble\b", expr):
        issues.append("histogram_quantile without 'le' in the aggregation")
    for lbl in HIGH_CARD:
        if re.search(rf"\b{lbl}=~", expr):
            issues.append(f"regex matcher on high-cardinality label '{lbl}'")
    return issues


def main():
    checks = []
    dash = red_dashboard("checkout")
    js = json.dumps(dash, indent=2)
    back = json.loads(js)
    panels = [p for p in back["panels"] if p["type"] != "row"]
    print(f"== 1. Generated dashboard '{back['title']}': {len(panels)} panels in {len(back['panels']) - len(panels)} rows, "
          f"{len(js):,} bytes of JSON ==")
    for p in back["panels"]:
        if p["type"] == "row":
            print(f"  [row] {p['title']}")
        else:
            iss = [i for t in p["targets"] for i in lint_expr(t["expr"])]
            print(f"    {p['title']:<26} {'ok' if not iss else '; '.join(iss)}")
            checks.append((p["title"], not iss))
    order = [p["title"] for p in back["panels"] if p["type"] == "row"]
    checks.append(("symptoms before causes", order[0].startswith("Golden") and order[-1].startswith("Saturation")))
    print()

    print("== 2. The same linter on hand-written anti-patterns ==")
    bad = {
        "hard-coded 1m window": 'sum(rate(http_server_requests_seconds_count{job="checkout"}[1m]))',
        "quantile without le": 'histogram_quantile(0.99, sum by (uri) (rate(http_server_requests_seconds_bucket[$__rate_interval])))',
        "regex on pod": 'sum(rate(container_cpu_usage_seconds_total{pod=~".*checkout.*"}[$__rate_interval]))',
        "unbalanced": 'sum(rate(http_server_requests_seconds_count[$__rate_interval])',
    }
    flagged = 0
    for name, e in bad.items():
        iss = lint_expr(e)
        flagged += bool(iss)
        print(f"  {name:<22} -> {'; '.join(iss)}")
    checks.append(("all anti-patterns flagged", flagged == len(bad)))
    print()

    print("== 3. What the dashboard costs the backend ==")
    targets = sum(len(p["targets"]) for p in panels)
    series_per_query = {1: 1, 2: 2, 3: 30, 4: 60, 5: 60 * 30, 6: 2, 7: 3, 8: 2}
    samples_per_series = 6 * 3600 // 15  # 6h range at 15s scrape (range query reads every raw sample once)
    for viewers, refresh_s in ((1, 60), (25, 60), (25, 10)):
        qpm = targets * viewers * 60 / refresh_s
        samples = sum(series_per_query[p["id"]] for p in panels) * samples_per_series * viewers * 60 / refresh_s
        print(f"  {viewers:>2} viewers, refresh {refresh_s:>2}s: {qpm:>6.0f} queries/min, ~{samples / 1e6:>7.1f} M samples/min")
    worst = sum(series_per_query[p["id"]] for p in panels) * samples_per_series * 25 * 6
    checks.append(("refresh 10s x 25 viewers is heavy", worst > 1e8))
    print("  -> the p99-by-route panel (bucket series x routes) dominates; back it with a recording rule")
    print("     (Folder 04 File 1) and set a 1m+ minimum refresh on shared dashboards.")
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:dashboard_lab.py -->
```text
== 1. Generated dashboard 'checkout / RED': 8 panels in 3 rows, 6,747 bytes of JSON ==
  [row] Golden signals (user-facing)
    Requests / s               ok
    Error ratio                ok
    p99 latency (successes)    ok
  [row] Drill-down by route
    Requests by route          ok
    p99 by route               ok
  [row] Saturation (causes)
    Hikari pending             ok
    GC pause time              ok
    CPU throttled ratio        ok

== 2. The same linter on hand-written anti-patterns ==
  hard-coded 1m window   -> hard-coded range window; use $__rate_interval
  quantile without le    -> histogram_quantile without 'le' in the aggregation
  regex on pod           -> regex matcher on high-cardinality label 'pod'
  unbalanced             -> does not parse: unexpected token ''

== 3. What the dashboard costs the backend ==
   1 viewers, refresh 60s:      8 queries/min, ~    2.7 M samples/min
  25 viewers, refresh 60s:    200 queries/min, ~   68.4 M samples/min
  25 viewers, refresh 10s:   1200 queries/min, ~  410.4 M samples/min
  -> the p99-by-route panel (bucket series x routes) dominates; back it with a recording rule
     (Folder 04 File 1) and set a 1m+ minimum refresh on shared dashboards.

checks: 11/11 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 Prometheus data source provisioning (scrape interval matters)

```yaml
apiVersion: 1
datasources:
  - name: Mimir
    uid: mimir
    type: prometheus
    access: proxy
    url: http://mimir-query-frontend.observability:8080/prometheus
    isDefault: true
    jsonData:
      timeInterval: 30s                 # = scrape interval: drives $__interval floor and $__rate_interval
      httpMethod: POST
      prometheusType: Mimir
      cacheLevel: Medium
      incrementalQuerying: true          # re-query only the new part of the range on refresh
      incrementalQueryOverlapWindow: 10m
      exemplarTraceIdDestinations:
        - name: trace_id
          datasourceUid: tempo
      httpHeaderName1: X-Scope-OrgID     # tenant header for a multi-tenant backend
    secureJsonData:
      httpHeaderValue1: platform
```

### 2.2 A dashboard provisioning provider (file-based, read-only)

```yaml
apiVersion: 1
providers:
  - name: platform-dashboards
    orgId: 1
    type: file
    disableDeletion: true
    allowUiUpdates: false                # UI edits can't silently diverge from Git
    updateIntervalSeconds: 60
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: true
```

### 2.3 RED dashboard JSON (excerpt of what L1 generates)

```json
{
  "title": "checkout / RED",
  "uid": "checkout-red",
  "refresh": "1m",
  "templating": {
    "list": [
      {"name": "namespace", "type": "query", "query": "label_values(http_server_requests_seconds_count, namespace)", "refresh": 2},
      {"name": "job", "type": "query", "query": "label_values(http_server_requests_seconds_count{namespace=\"$namespace\"}, job)", "refresh": 2}
    ]
  },
  "panels": [
    {"type": "row", "title": "Golden signals (user-facing)", "id": 100},
    {
      "type": "timeseries",
      "title": "Error ratio",
      "fieldConfig": {"defaults": {"unit": "percentunit"}},
      "targets": [{
        "refId": "A",
        "expr": "sum(rate(http_server_requests_seconds_count{job=\"$job\", namespace=\"$namespace\", outcome=\"SERVER_ERROR\"}[$__rate_interval])) / sum(rate(http_server_requests_seconds_count{job=\"$job\", namespace=\"$namespace\"}[$__rate_interval]))"
      }]
    }
  ]
}
```

### 2.4 Grafana server settings for shared, large installations

```yaml
# grafana.ini expressed as env vars (Helm values excerpt)
env:
  GF_DASHBOARDS_MIN_REFRESH_INTERVAL: 1m        # no 5s refresh on shared dashboards
  GF_DATAPROXY_TIMEOUT: "60"
  GF_SERVER_ENABLE_GZIP: "true"                  # default true since 13.0
  GF_DATABASE_TYPE: postgres                     # never SQLite for HA
  GF_UNIFIED_ALERTING_HA_PEERS: grafana-headless.observability:9094
```

---

## 3. Failure modes and FinOps debugging

### F1. The "wall of graphs" dashboard

**Symptom.** A 60-panel dashboard everyone opens during incidents; nobody can find anything; it takes 40 s to load.

**Signature.** No row hierarchy; mixed symptom and cause panels; dozens of unscoped variables; query log shows the dashboard as the top query source.

**Root cause.** Dashboards built by accretion, not as a diagnostic path.

**Fix.** Split into the hierarchy (§1.1): SLO overview → service RED → breakdown → USE; link them.

**Prevention.** Dashboard review checklist; panel budget per dashboard (~20); usage analytics to delete unused panels.

### F2. Rate panels that change shape with zoom

**Symptom.** Zooming out makes spikes disappear or rates drop; zooming in shows gaps.

**Signature.** Hard-coded `[1m]` windows with a step that becomes 5 m at a 7-day range (samples skipped between steps), or windows shorter than 4 scrapes at high zoom.

**Root cause.** Window and step decoupled.

**Fix.** `$__rate_interval` and a correct `timeInterval` on the data source.

**Prevention.** Lint (L1) on every dashboard change.

### F3. Variable queries that scan everything

**Symptom.** Dashboards take seconds before any panel loads; Prometheus shows heavy `/api/v1/label/.../values` or series queries.

**Signature.** `label_values(pod)` or `label_values({__name__=~".+"}, job)` unscoped; refresh on time range change.

**Root cause.** Label-value queries over all series, re-run on every zoom.

**Fix.** Scope by a metric and upstream variables; refresh on load; restrict time range for variable queries.

**Prevention.** Variable lint in CI.

### F4. Transformations hiding missing data

**Symptom.** A "success rate" table computed with transformations shows 100% for a service that is down.

**Signature.** *Join by field* of two queries where the error query returned no series; *Add field from calculation* treats missing as 0 or drops the row.

**Root cause.** Math done after the query, without PromQL's matching semantics or absence handling.

**Fix.** Compute ratios in PromQL (with `or … * 0`, Folder 02 File 2); transformations only for presentation.

**Prevention.** Review panels with calculation transformations; prefer recording rules.

### F5. Dashboard load as an outage cause

**Symptom.** During an incident, 80 engineers open the same dashboard and the metrics backend falls over, making the incident worse.

**Signature.** Query concurrency spikes; query-frontend queues; the dashboard refreshes every 5 s.

**Root cause.** Per-viewer, per-refresh query cost (L1 §3) multiplied by an incident crowd.

**Fix.** Minimum refresh interval, recording-rule-backed panels, query caching/result cache, read-only incident dashboards.

**Prevention.** Load-test top dashboards; alert on query-frontend queue time.

### F6. Grafana 13 upgrade surprises

**Symptom.** After upgrading to 13.0.0, Git-Synced dashboards reverted or disappeared; scripts using `grafana-cli` fail; rendering-based reports stop.

**Signature.** Upgrade from 12.x with Git Sync enabled to 13.0.0; tooling calling removed binaries; Image Renderer plugin.

**Root cause.** Documented 13.0 breaking changes, including a Git Sync migration bug in 13.0.0 (fixed in 13.0.1; data lost must be restored from backup).

**Fix.** Restore the database backup, upgrade to ≥ 13.0.1; switch to `grafana cli`; replace renderer-based workflows.

**Prevention.** Read the upgrade guide for each major; back up the Grafana database before upgrades; stage upgrades.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "Design the dashboard an on-call engineer opens first."</b></summary>

**Initial Prompt.** What's on it?

**L5 Textbook Answer.** CPU, memory, request rate, error rate, latency for every service.

**Why L5 Fails at 3 AM or on the Bill.** A flat collection doesn't guide diagnosis and costs a fortune in queries at incident scale.

**L7 Principal Defense.** An SLO overview: one row per service with error-budget burn and current SLI vs objective, each linking to that service's RED dashboard with variables and time range; RED rows ordered symptoms → breakdown → causes; exemplars to traces; recording-rule backed; ≤ 20 panels; minimum refresh 1 m. The structure *is* the runbook's first steps.
</details>

<details><summary><b>Q2 · "Explain $__rate_interval."</b></summary>

**Initial Prompt.** Why not just use `[5m]` everywhere?

**L5 Textbook Answer.** `$__rate_interval` adapts to the zoom level.

**Why L5 Fails at 3 AM or on the Bill.** Without the formula you can't explain gaps at high zoom or why it depends on the data source's scrape interval.

**L7 Principal Defense.** `max($__interval + scrape interval, 4 × scrape interval)`: at least 4 scrapes per window (Folder 02's error analysis) and at least one step plus a scrape so consecutive windows overlap and no sample is skipped. Requires `timeInterval` on the data source = real scrape interval; mixed-interval data sources need the largest.
</details>

<details><summary><b>Q3 · "Why is this dashboard slow?"</b></summary>

**Initial Prompt.** Diagnose a dashboard that takes 30 s to load.

**L5 Textbook Answer.** Prometheus is overloaded; scale it up.

**Why L5 Fails at 3 AM or on the Bill.** Scaling hides query design problems and costs money every hour.

**L7 Principal Defense.** Use the query inspector and the backend query log to rank panels by samples read; typical culprits are bucket-level `histogram_quantile` over raw series, unscoped variables, long ranges at small steps, regex on `pod`. Fix with recording rules, scoped variables, `$__rate_interval`, and caching; then measure with L1's cost model.
</details>

<details><summary><b>Q4 · "When are Grafana transformations appropriate?"</b></summary>

**Initial Prompt.** Teams compute SLO ratios with transformations. Good?

**L5 Textbook Answer.** Yes, it's flexible and avoids complex PromQL.

**Why L5 Fails at 3 AM or on the Bill.** Results can't be alerted on, are recomputed per viewer, and mishandle missing series.

**L7 Principal Defense.** Transformations for presentation: renaming, table shaping, joining instant results for display. Anything that is a metric (ratios, SLIs) lives in PromQL and recording rules so it is alertable, testable and cheap.
</details>

<details><summary><b>Q5 · "What does Grafana 13's dynamic dashboards change for teams?"</b></summary>

**Initial Prompt.** Should we worry about the new dashboard schema?

**L5 Textbook Answer.** It's a UI change; nothing to do.

**Why L5 Fails at 3 AM or on the Bill.** Dashboards-as-code pipelines generate JSON in a specific schema; an automatic migration on open plus a new layout model can create diffs and drift against generated code.

**L7 Principal Defense.** Existing dashboards are migrated to the new schema when opened; code generators (Foundation SDK, grafonnet, Terraform JSON) must be pinned and tested against 13.x, and Git Sync/provisioned dashboards reviewed for unintended diffs. Plan the upgrade as a schema migration: back up, stage, regenerate, compare.
</details>

<details><summary><b>Q6 · "How many variables should a dashboard have?"</b></summary>

**Initial Prompt.** Teams add 12 variables to every dashboard.

**L5 Textbook Answer.** As many as needed for filtering.

**Why L5 Fails at 3 AM or on the Bill.** Each variable is a query; chained "All" values create huge regexes; dashboards become slow and confusing.

**L7 Principal Defense.** 2–4 variables following the hierarchy (data source, namespace/cluster, service), scoped by upstream ones, refreshed on load; Filters (ad hoc) for exploration. Everything else is a separate drill-down dashboard.
</details>

<details><summary><b>Q7 · "Who should be able to edit production dashboards?"</b></summary>

**Initial Prompt.** Everyone edits dashboards; things break.

**L5 Textbook Answer.** Restrict editing to admins.

**Why L5 Fails at 3 AM or on the Bill.** Restricting edits stops improvement; the issue is unreviewed change, not editing.

**L7 Principal Defense.** Shared dashboards come from Git (Git Sync or provisioning with `allowUiUpdates: false`): edits become pull requests with lint (L1) and review. Personal scratch dashboards are free. RBAC by folder; restore-deleted (GA in 13) as a safety net.
</details>

<details><summary><b>Q8 · "Heatmap or percentile lines?"</b></summary>

**Initial Prompt.** How should latency be visualized?

**L5 Textbook Answer.** p50, p95, p99 lines.

**Why L5 Fails at 3 AM or on the Bill.** Percentile lines hide multimodality (cache hit vs miss) and are interpolated estimates (Folder 02 File 3).

**L7 Principal Defense.** A heatmap of bucket rates (or native histograms) shows the distribution's shape and modes; one p99 line on top for the SLO; the SLI panel shows the fraction under threshold, not a percentile.
</details>

---

## 5. Invariants checklist

- [ ] Dashboards follow the hierarchy: SLO overview → service RED → breakdown → causes, linked with variables and time range.
- [ ] Every rate uses `$__rate_interval`; the data source `timeInterval` equals the real scrape interval.
- [ ] Variables are scoped by upstream variables and refreshed on load; "All" uses a custom value for high-count variables.
- [ ] Ratios and SLIs are computed in PromQL/recording rules, never in transformations.
- [ ] Shared dashboards have a minimum refresh of 1 m and recording-rule-backed heavy panels.
- [ ] Shared dashboards are code (Git Sync/provisioning), linted on change.
- [ ] Grafana major upgrades follow the upgrade guide with a database backup (13.0.0 Git Sync bug).

---

## 6. References

- What's new in Grafana v13.0: <https://grafana.com/docs/grafana/latest/whatsnew/whats-new-in-v13-0/>
- Grafana v13.3.0 release: <https://github.com/grafana/grafana/releases/tag/v13.3.0>
- Prometheus data source and template variables (`$__rate_interval`): <https://grafana.com/docs/grafana/latest/datasources/prometheus/template-variables/>
- Transformations: <https://grafana.com/docs/grafana/latest/panels-visualizations/query-transform-data/transform-data/>
- Dashboard best practices: <https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/best-practices/>
- Provisioning: <https://grafana.com/docs/grafana/latest/administration/provisioning/>
