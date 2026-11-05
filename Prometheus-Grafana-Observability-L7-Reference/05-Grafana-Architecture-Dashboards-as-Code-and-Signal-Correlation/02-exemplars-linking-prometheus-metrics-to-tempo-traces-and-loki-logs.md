# 02 · Exemplars: Linking Prometheus Metrics to Tempo Traces and Loki Logs

> **Folder 05 — Grafana Architecture, Dashboards as Code and Signal Correlation · File 2 of 3.**
> Pinned to **Prometheus v3.15.1** (`tsdb/exemplar.go`, `model/exemplar`), **Grafana v13.3.0**, **Tempo v3.1.1**, **Loki v3.7.9**.
> Labels: **[D]** documented / read in pinned source · **[M]** measured by the listing (deterministic, re-run by the gate) · **[E]** model · **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L2 `exemplar_lab.py` | Parses the OpenMetrics exemplar syntax; ports Prometheus's circular exemplar store (duplicate no-op, out-of-order rejection, 128-rune label cap, ring eviction with per-series unlinking); computes how long exemplars survive in the default 100,000-slot ring (2.5 min at 10k series, 7.5 s at 200k); and measures exemplar click-through success under head vs tail trace sampling (2.3% at 1% head sampling vs 100% with an aligned tail policy) | <1 s |

**Verification.** Store semantics follow `CircularExemplarStorage.validateExemplar`/`AddExemplar` at v3.15.1 (OOO window 0); `ExemplarMaxLabelSetLength = 128` is from `model/exemplar/exemplar.go`. The sampling experiment is a simulation [M] of 10,000 lognormal requests with exemplars taken from errors and the slowest 1%. Data-source provisioning keys are from Grafana's provisioning documentation (⚠ where newer). No live stack was run.

---

## 0. Orientation

**What this file answers.** How to jump from "p99 is high" to *the* slow request's trace, its logs and its profile in two clicks; what each link depends on; and why most exemplar setups silently fail (expired exemplars, sampled-away traces, label mismatches).

**The correlation graph.**

```text
          metrics (Prometheus/Mimir)                         traces (Tempo)
   http_server_requests_seconds_bucket ── exemplar ─────────► trace 4bf92f… ─ span ─┐
   {service="checkout", le="0.5"}         trace_id=4bf92f…     service.name=checkout  │ tracesToLogs
          ▲                                                    │ tracesToMetrics     ▼
          │ tracesToMetrics (span → RED query)                 │ tracesToProfiles    logs (Loki)
          └────────────────────────────────────────────────────┘                    {service_name="checkout"}
   span metrics (Tempo metrics-generator / OTel spanmetrics)   ▼                    | trace_id="4bf92f…"
                                                         profiles (Pyroscope)   ◄── derived field → trace
 the join keys: trace_id (exact) and service/k8s labels (scoped time-window queries)
```

---

## 1. First principles: what an exemplar is and where it lives

### 1.1 On the wire and in the TSDB [D]

An exemplar is a sample-level annotation: a small label set (typically `trace_id`, `span_id`), a value (the observation) and a timestamp, attached to a counter or histogram bucket:

```text
 http_server_requests_seconds_bucket{uri="/pay",le="0.5"} 1042 # {trace_id="4bf92f…",span_id="00f067…"} 0.43 1762300800.123
```

- Exposed by OpenMetrics text and protobuf (native histograms carry *several* exemplars per sample, with timestamps); the classic Prometheus text format cannot carry them.
- Ingested only with `--enable-feature=exemplar-storage` (still experimental in 3.15) into a **single global ring buffer** of `storage.exemplars.max_exemplars` entries (default 100,000), persisted via WAL records (type 4) and replayed on restart.
- Rules enforced on append (L2 §2): a repeat of the newest exemplar is a no-op; an older one is rejected (`prometheus_tsdb_exemplar_out_of_order_exemplars_total`); label names+values > 128 runes are rejected.
- Queried via `/api/v1/query_exemplars`; Grafana fetches them alongside range queries and draws diamonds on time-series and heatmap panels.
- Remote write sends them only with `send_exemplars: true`; Mimir stores them per tenant (`max_global_exemplars_per_user` limit ⚠).

### 1.2 The ring buffer is a short memory (L2 §3)

```text
 retention_seconds ≈ max_exemplars / (series emitting exemplars per scrape / scrape_interval)
   100,000 / (10,000 / 15 s)  = 150 s        100,000 / (200,000 / 15 s) = 7.5 s
```

With a large fleet, exemplars older than seconds-to-minutes are gone locally — fine for "what's slow right now", useless for yesterday's incident unless the long-term store keeps them (Mimir) and remote write ships them. Size `max_exemplars` from the series that actually emit exemplars (usually only latency histograms), not from total series.

### 1.3 Will the trace exist? (L2 §4)

Exemplars are picked from interesting requests (slow, failed). Whether the linked trace exists depends on the *trace* sampling policy [M]:

| Trace sampling | Traces kept | Exemplar click-through finds the trace |
|---|---|---|
| head 1% | 122 / 10,000 | 2.3% |
| head 10% | 960 / 10,000 | 6.5% |
| tail: errors + latency > p99 + 1% baseline | 329 / 10,000 | **100%** |

Head sampling decides at the root span before latency is known, so it keeps random requests; exemplar-worthy requests are exactly the ones it throws away. Two fixes:

1. **Tail sampling** in the OTel Collector/Alloy whose policy matches exemplar selection (Folder 06 File 1).
2. **Sampled-only exemplars**: SDKs (OpenTelemetry's `TraceBasedExemplarFilter`, Micrometer/OTel bridges) attach exemplars only for sampled spans, so every exemplar resolves — at the cost of fewer exemplars on non-sampled slow requests.

### 1.4 Logs ↔ traces ↔ profiles [D]

- **Logs → traces**: Loki *derived fields* extract `trace_id` from log lines (regex) or from structured metadata (label matcher), turning it into a link to Tempo.
- **Traces → logs**: Tempo's `tracesToLogsV2` builds a Loki query from span attributes (`service.name` → `service_name`), the span's time window (with shifts) and optionally `|= "<trace_id>"`.
- **Traces → metrics**: `tracesToMetrics` runs PromQL templates with span tags (`$__tags`) — RED for the span's service.
- **Traces → profiles**: `tracesToProfiles` opens the Pyroscope profile for the span's service and time, or the exact span profile when SDKs attach span IDs to profiling samples (span profiles).
- **Service graph and span metrics**: Tempo's metrics-generator (or the OTel `spanmetrics`/`servicegraph` connectors) emits `traces_spanmetrics_*` and `traces_service_graph_*` metrics with exemplars — RED for every traced service without code changes.

The join keys must agree everywhere: `service.name` in OTel resources, `service`/`job` in Prometheus, `service_name` in Loki. Pick one normalisation (OTel semantic conventions translated consistently) and enforce it in the collector.

<!-- listing:exemplar_lab.py -->
```python
"""exemplar_lab.py - exemplars end to end: the Prometheus circular exemplar store (tsdb/exemplar.go,
v3.15.1), the OpenMetrics exemplar wire syntax, how long an exemplar survives, and the probability
that clicking an exemplar in Grafana actually finds its trace in Tempo under different sampling.

Port: one global ring buffer of max_exemplars entries (default 100,000) with a per-series linked
list; an exemplar equal to the series' newest is a no-op duplicate; one older than the newest (no
OOO window) is rejected as out of order; label names+values are capped at 128 runes; when the ring
wraps, the overwritten entry is unlinked from its series.
Deterministic, stdlib only.

Usage: python exemplar_lab.py [target.md]
"""
import random
import re
import sys

MAX_LABEL_RUNES = 128


class ExemplarStore:
    def __init__(self, size):
        self.buf = [None] * size  # entries: [series, labels, value, ts, next]
        self.next = 0
        self.index = {}  # series -> [oldest, newest]
        self.stats = {"appended": 0, "duplicate": 0, "out_of_order": 0, "too_long": 0, "evicted": 0}

    def add(self, series, labels, value, ts):
        if sum(len(k) + len(v) for k, v in labels.items()) > MAX_LABEL_RUNES:
            self.stats["too_long"] += 1
            return "label set too long"
        idx = self.index.get(series)
        if idx is not None:
            newest = self.buf[idx[1]]
            if newest[1] == labels and newest[2] == value and newest[3] == ts:
                self.stats["duplicate"] += 1
                return "duplicate"
            if ts < newest[3] or (ts == newest[3] and value < newest[2]):
                self.stats["out_of_order"] += 1
                return "out of order"
        slot = self.next
        old = self.buf[slot]
        if old is not None:  # ring wrapped: unlink the overwritten entry from its series
            self.stats["evicted"] += 1
            oidx = self.index[old[0]]
            if oidx[0] == oidx[1]:
                del self.index[old[0]]
            else:
                oidx[0] = old[4]
        self.buf[slot] = [series, labels, value, ts, None]
        if series in self.index:
            self.buf[self.index[series][1]][4] = slot
            self.index[series][1] = slot
        else:
            self.index[series] = [slot, slot]
        self.next = (slot + 1) % len(self.buf)
        self.stats["appended"] += 1
        return "ok"

    def query(self, series, mint, maxt):
        idx, out = self.index.get(series), []
        i = idx[0] if idx else None
        while i is not None:
            e = self.buf[i]
            if mint <= e[3] <= maxt:
                out.append(e)
            i = e[4]
        return out


OM_EXEMPLAR = re.compile(r'^(?P<metric>\S+?)(?P<lbls>\{[^}]*\})?\s+(?P<val>\S+)(?:\s+(?P<ts>\S+))?\s+#\s+'
                         r'\{(?P<elbls>[^}]*)\}\s+(?P<ev>\S+)(?:\s+(?P<ets>\S+))?$')


def parse_om_line(line):
    m = OM_EXEMPLAR.match(line)
    if not m:
        return None
    lbls = dict(re.findall(r'(\w+)="([^"]*)"', m.group("elbls")))
    return {"series": m.group("metric") + (m.group("lbls") or ""), "labels": lbls,
            "value": float(m.group("ev")), "ts": float(m.group("ets")) if m.group("ets") else None}


def main():
    checks = []
    print("== 1. OpenMetrics exemplar syntax (what an instrumented app exposes) ==")
    line = ('http_server_requests_seconds_bucket{uri="/pay",le="0.5"} 1042 '
            '# {trace_id="4bf92f3577b34da6a3ce929d0e0e4736",span_id="00f067aa0ba902b7"} 0.43 1762300800.123')
    ex = parse_om_line(line)
    print(line)
    print(f"-> series {ex['series']} | exemplar labels {ex['labels']} | value {ex['value']} | ts {ex['ts']}")
    checks.append(("parsed trace_id", ex["labels"]["trace_id"].startswith("4bf9")))
    print()

    print("== 2. Store semantics (duplicates, out-of-order, label-length cap, ring eviction) ==")
    st = ExemplarStore(4)
    s = 'http_server_requests_seconds_bucket{uri="/pay",le="0.5"}'
    r = [st.add(s, {"trace_id": "a" * 32}, 0.4, 1000),
         st.add(s, {"trace_id": "a" * 32}, 0.4, 1000),
         st.add(s, {"trace_id": "b" * 32}, 0.3, 900),
         st.add(s, {"trace_id": "c" * 130}, 0.2, 1100)]
    for k in range(5):
        st.add(f"other{k}", {"trace_id": f"{k:032x}"}, 0.1, 2000 + k)
    print(f"append -> {r[0]}; same exemplar again -> {r[1]}; older timestamp -> {r[2]}; 130-rune trace_id -> {r[3]}")
    print(f"after 5 more series in a 4-slot ring: '/pay' exemplars left = {len(st.query(s, 0, 10**9))}; stats {st.stats}")
    checks.append(("semantics", r == ["ok", "duplicate", "out of order", "label set too long"] and not st.query(s, 0, 10**9)))
    print()

    print("== 3. How long does an exemplar live in the default 100,000-slot ring? ==")
    for series_with_ex, scrape_s in ((10_000, 15), (50_000, 15), (200_000, 15)):
        per_sec = series_with_ex / scrape_s  # one new exemplar per series per scrape, worst case
        retention = 100_000 / per_sec
        print(f"{series_with_ex:>7,} series emitting exemplars @{scrape_s}s -> ring turns over every {retention:>6.0f} s "
              f"({retention / 60:.1f} min)")
    checks.append(("200k series -> 7.5 s", abs(100_000 / (200_000 / 15) - 7.5) < 1e-9))
    print("-> exemplars are a short memory: size max_exemplars from (series with exemplars / scrape interval) x the")
    print("   lookback you want; long-term exemplars need a backend that stores them (Mimir) or remote write.")
    print()

    print("== 4. Will the trace behind an exemplar exist? (10,000 requests, exemplars picked from slow ones) ==")
    rng = random.Random(3)
    reqs = [(i, rng.lognormvariate(-2.3, 0.8), rng.random() < 0.01) for i in range(10_000)]  # (id, latency, error)
    slow_cut = sorted(r[1] for r in reqs)[int(0.99 * len(reqs))]
    exemplars = [r for r in reqs if r[1] >= slow_cut or r[2]]
    policies = {
        "head sampling 1%": lambda r: rng.random() < 0.01,
        "head sampling 10%": lambda r: rng.random() < 0.10,
        "tail: keep errors + latency > p99 + 1% rest": lambda r: r[2] or r[1] >= slow_cut or rng.random() < 0.01,
    }
    res = {}
    for name, keep in policies.items():
        kept = {r[0] for r in reqs if keep(r)}
        hit = sum(1 for r in exemplars if r[0] in kept) / len(exemplars)
        res[name] = hit
        print(f"{name:<44} traces kept {len(kept):>5}  exemplar click-through finds the trace {hit:>6.1%}")
    checks.append(("tail sampling aligns with exemplars", res["tail: keep errors + latency > p99 + 1% rest"] == 1.0
                   and res["head sampling 1%"] < 0.05))
    print("-> exemplars point at the interesting requests; head sampling throws most of them away. Exemplar")
    print("   selection and trace sampling must use the same policy (Folder 06 File 1).")
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:exemplar_lab.py -->
```text
== 1. OpenMetrics exemplar syntax (what an instrumented app exposes) ==
http_server_requests_seconds_bucket{uri="/pay",le="0.5"} 1042 # {trace_id="4bf92f3577b34da6a3ce929d0e0e4736",span_id="00f067aa0ba902b7"} 0.43 1762300800.123
-> series http_server_requests_seconds_bucket{uri="/pay",le="0.5"} | exemplar labels {'trace_id': '4bf92f3577b34da6a3ce929d0e0e4736', 'span_id': '00f067aa0ba902b7'} | value 0.43 | ts 1762300800.123

== 2. Store semantics (duplicates, out-of-order, label-length cap, ring eviction) ==
append -> ok; same exemplar again -> duplicate; older timestamp -> out of order; 130-rune trace_id -> label set too long
after 5 more series in a 4-slot ring: '/pay' exemplars left = 0; stats {'appended': 6, 'duplicate': 1, 'out_of_order': 1, 'too_long': 1, 'evicted': 2}

== 3. How long does an exemplar live in the default 100,000-slot ring? ==
 10,000 series emitting exemplars @15s -> ring turns over every    150 s (2.5 min)
 50,000 series emitting exemplars @15s -> ring turns over every     30 s (0.5 min)
200,000 series emitting exemplars @15s -> ring turns over every      8 s (0.1 min)
-> exemplars are a short memory: size max_exemplars from (series with exemplars / scrape interval) x the
   lookback you want; long-term exemplars need a backend that stores them (Mimir) or remote write.

== 4. Will the trace behind an exemplar exist? (10,000 requests, exemplars picked from slow ones) ==
head sampling 1%                             traces kept   122  exemplar click-through finds the trace   2.3%
head sampling 10%                            traces kept   960  exemplar click-through finds the trace   6.5%
tail: keep errors + latency > p99 + 1% rest  traces kept   329  exemplar click-through finds the trace 100.0%
-> exemplars point at the interesting requests; head sampling throws most of them away. Exemplar
   selection and trace sampling must use the same policy (Folder 06 File 1).

checks: 4/4 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 Prometheus: exemplar storage and shipping

```yaml
# prometheus flags: --enable-feature=exemplar-storage
storage:
  exemplars:
    max_exemplars: 500000      # size from (series with exemplars / scrape interval) x desired lookback
scrape_configs:
  - job_name: checkout
    scrape_protocols: [PrometheusProto, OpenMetricsText1.0.0]   # text 0.0.4 cannot carry exemplars
    static_configs: [{targets: ["checkout:8080"]}]
remote_write:
  - url: https://mimir.example.internal/api/v1/push
    send_exemplars: true
    send_native_histograms: true
```

### 2.2 Grafana data sources wired for correlation

```yaml
apiVersion: 1
datasources:
  - name: Mimir
    uid: mimir
    type: prometheus
    url: http://mimir-query-frontend.observability:8080/prometheus
    jsonData:
      timeInterval: 30s
      exemplarTraceIdDestinations:
        - name: trace_id                 # exemplar label holding the trace ID
          datasourceUid: tempo
  - name: Tempo
    uid: tempo
    type: tempo
    url: http://tempo-query-frontend.observability:3200
    jsonData:
      tracesToLogsV2:
        datasourceUid: loki
        spanStartTimeShift: -2m
        spanEndTimeShift: 2m
        filterByTraceID: true
        tags:
          - {key: service.name, value: service_name}
          - {key: k8s.namespace.name, value: namespace}
      tracesToMetrics:
        datasourceUid: mimir
        spanStartTimeShift: -5m
        spanEndTimeShift: 5m
        tags:
          - {key: service.name, value: service}
        queries:
          - name: Request rate
            query: sum(rate(traces_spanmetrics_calls_total{$$__tags}[5m]))
          - name: Error rate
            query: sum(rate(traces_spanmetrics_calls_total{$$__tags, status_code="STATUS_CODE_ERROR"}[5m]))
      tracesToProfiles:
        datasourceUid: pyroscope
        profileTypeId: process_cpu:cpu:nanoseconds:cpu:nanoseconds
        tags:
          - {key: service.name, value: service_name}
      serviceMap:
        datasourceUid: mimir
      nodeGraph:
        enabled: true
  - name: Loki
    uid: loki
    type: loki
    url: http://loki-gateway.observability
    jsonData:
      derivedFields:
        - name: TraceID
          matcherType: label             # structured metadata / label named trace_id
          matcherRegex: trace_id
          datasourceUid: tempo
          url: '$${__value.raw}'
        - name: TraceIDInLine
          matcherType: regex
          matcherRegex: 'trace_id=(\w+)'
          datasourceUid: tempo
          url: '$${__value.raw}'
  - name: Pyroscope
    uid: pyroscope
    type: grafana-pyroscope-datasource
    url: http://pyroscope.observability:4040
```

`$$` escapes `$` in provisioning files (Grafana interpolates environment variables with `$`).

### 2.3 Application side: exemplars only for sampled spans (OpenTelemetry Java SDK)

```java
// OpenTelemetry Java SDK: attach exemplars to measurements only when the active span is sampled,
// so every exemplar in Prometheus/Mimir resolves to a trace kept by the sampler.
SdkMeterProvider meterProvider = SdkMeterProvider.builder()
    .setResource(resource)
    .setExemplarFilter(ExemplarFilter.traceBased())
    .registerMetricReader(PeriodicMetricReader.builder(
        OtlpHttpMetricExporter.builder().setEndpoint("http://alloy:4318/v1/metrics").build())
        .setInterval(Duration.ofSeconds(15)).build())
    .build();
```

---

## 3. Failure modes and FinOps debugging

### F1. Exemplar diamonds that lead to "trace not found"

**Symptom.** Clicking exemplars mostly opens "trace not found" in Tempo.

**Signature.** Head sampling at a low rate; exemplars attached regardless of sampling; Tempo search confirms the trace IDs never arrived.

**Root cause.** Exemplar selection and trace sampling are independent (L2 §4: 2.3% success at 1% head sampling).

**Fix.** Trace-based exemplar filter (SDK) or tail sampling aligned with exemplar selection (errors, slow requests).

**Prevention.** Track exemplar resolution rate with a synthetic check that queries Tempo for a sample of exemplar trace IDs.

### F2. No exemplars at all

**Symptom.** Panels show no exemplars although the app emits them.

**Signature.** `prometheus_tsdb_exemplar_exemplars_appended_total` is 0; the scrape negotiated `PrometheusText0.0.4`; or the feature flag is missing; or remote write lacks `send_exemplars`.

**Root cause.** Every hop must support exemplars: exposition format, scrape protocol, storage flag, remote write, backend limits, Grafana's "Exemplars" toggle on the query.

**Fix.** Enable each hop (§2.1); verify with `/api/v1/query_exemplars`.

**Prevention.** End-to-end correlation test in staging per stack change.

### F3. Exemplars vanish within seconds

**Symptom.** Exemplars appear for "last 5 minutes" but not for an incident 30 minutes ago.

**Signature.** `prometheus_tsdb_exemplar_series_with_exemplars_in_storage` high; `max_exemplars` at default; ring turnover of seconds (L2 §3).

**Root cause.** Global ring buffer sized below the exemplar ingest rate × desired lookback.

**Fix.** Raise `max_exemplars` (memory ~100 bytes/exemplar ⚠) or rely on the long-term store's exemplar retention.

**Prevention.** Alert on `rate(prometheus_tsdb_exemplar_exemplars_appended_total[5m]) * lookback > max_exemplars`.

### F4. Traces-to-logs opens an empty Loki query

**Symptom.** "Logs for this span" returns nothing.

**Signature.** The Tempo data source maps `service.name` to a Loki label that doesn't exist (`service` vs `service_name`), or time shifts are too narrow for log shipping delay.

**Root cause.** Inconsistent attribute → label normalisation between the trace and log pipelines.

**Fix.** Align mappings (§2.2) and widen shifts; ensure logs carry `trace_id` in structured metadata.

**Prevention.** One attribute normalisation policy in the collector for all signals.

### F5. Exemplar label explosion

**Symptom.** Exemplar appends rejected; `prometheus_tsdb_exemplar_*` errors; apps attaching user IDs and URLs to exemplars.

**Signature.** Label set > 128 runes rejected; or exemplars carrying PII.

**Root cause.** Exemplars treated as a log channel.

**Fix.** Exemplars carry only `trace_id` (and optionally `span_id`); everything else belongs on the span.

**Prevention.** Instrumentation guidelines; SDK exemplar filters.

### F6. Correlation that only works in one direction

**Symptom.** Metrics → traces works, but traces → metrics shows empty panels.

**Signature.** `tracesToMetrics` queries reference `traces_spanmetrics_*` metrics that aren't generated (metrics-generator disabled), or tag mappings mismatch.

**Root cause.** Span metrics must be produced by Tempo's metrics-generator or the collector's spanmetrics connector.

**Fix.** Enable span metrics with bounded dimensions (Folder 06 File 1); align tag mappings.

**Prevention.** Correlation smoke test in CI against staging data sources.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "How do exemplars work, end to end?"</b></summary>

**Initial Prompt.** Explain the path from an app to a clickable diamond in Grafana.

**L5 Textbook Answer.** The app adds a trace ID to histogram observations; Prometheus stores it; Grafana shows it on graphs.

**Why L5 Fails at 3 AM or on the Bill.** Misses the six hops where it breaks: exposition format, scrape protocol negotiation, the experimental storage flag, a seconds-to-minutes ring buffer, remote-write flag and backend limits, and trace sampling.

**L7 Principal Defense.** SDK attaches `{trace_id}` to bucket observations (trace-based filter) → OpenMetrics/protobuf exposition → Prometheus with `exemplar-storage` into a global ring (size it, L2 §3) → `send_exemplars` to Mimir → Grafana fetches `/api/v1/query_exemplars` and maps `trace_id` to Tempo → the trace exists only if sampling kept it (L2 §4). I'd monitor the resolution rate as an SLI of the observability platform itself.
</details>

<details><summary><b>Q2 · "Head or tail sampling for a system that relies on exemplars?"</b></summary>

**Initial Prompt.** We sample 1% at the head. Problem?

**L5 Textbook Answer.** It's cheap; 1% gives enough traces.

**Why L5 Fails at 3 AM or on the Bill.** The slow and failing requests — the ones exemplars and on-call care about — are 99% likely to be dropped; L2 measures 2.3% exemplar resolution.

**L7 Principal Defense.** Tail sampling keeping all errors, latency above a threshold, and a small baseline; or head sampling with trace-based exemplar filtering so exemplars only point at kept traces. Cost is managed by the baseline percentage and by span-metric RED, which doesn't need traces at all.
</details>

<details><summary><b>Q3 · "How do you correlate logs and traces without exemplars?"</b></summary>

**Initial Prompt.** Our logs don't have trace IDs. Options?

**L5 Textbook Answer.** Search logs by timestamp around the trace.

**Why L5 Fails at 3 AM or on the Bill.** Time-window correlation is ambiguous at any real request rate.

**L7 Principal Defense.** Inject trace context into logs (OTel log bridge/MDC) and ship `trace_id` as structured metadata in Loki; configure derived fields (label matcher) and `tracesToLogsV2` with `filterByTraceID`. Until then, scope by service, pod and a narrow time window as a fallback, labelled as approximate.
</details>

<details><summary><b>Q4 · "What's the memory cost of exemplar storage?"</b></summary>

**Initial Prompt.** Can we set max_exemplars to 10 million?

**L5 Textbook Answer.** Yes, exemplars are small.

**Why L5 Fails at 3 AM or on the Bill.** 10 M entries × (labels + metadata, on the order of 100 bytes ⚠) is GiBs of heap on a server already sized for the head (Folder 01), and they're replayed from the WAL on restart.

**L7 Principal Defense.** Size from need: series emitting exemplars / scrape interval × lookback (L2 §3 formula); keep local lookback short and rely on the long-term store's exemplar retention for history; measure heap delta after changing it.
</details>

<details><summary><b>Q5 · "Span metrics vs application metrics for RED?"</b></summary>

**Initial Prompt.** Should we derive RED from traces instead of instrumenting metrics?

**L5 Textbook Answer.** Yes, span metrics are automatic.

**Why L5 Fails at 3 AM or on the Bill.** Span metrics are computed after sampling decisions in some setups (biased), add collector load, and explode cardinality with unbounded span names or attributes.

**L7 Principal Defense.** Span metrics computed *before* sampling (collector `spanmetrics` connector ahead of tail sampling) give unbiased RED for every traced service with exemplars attached; application metrics remain for business and SLO metrics with controlled labels. Bound span-metric dimensions explicitly.
</details>

<details><summary><b>Q6 · "Design the correlation keys across signals."</b></summary>

**Initial Prompt.** Metrics use `job`, logs use `app`, traces use `service.name`. Fix it.

**L5 Textbook Answer.** Add all three labels everywhere.

**Why L5 Fails at 3 AM or on the Bill.** Triples label cardinality and still leaves mapping ambiguity.

**L7 Principal Defense.** OTel resource attributes are the source of truth (`service.name`, `service.namespace`, `deployment.environment.name`, k8s attributes); the collector translates them once into each backend's label (`service_name` in Loki, `job`=`namespace/name` and promoted attributes in Mimir); Grafana data-source mappings encode that translation. One schema, one owner.
</details>

<details><summary><b>Q7 · "Exemplars on counters or histograms?"</b></summary>

**Initial Prompt.** Where should exemplars be attached?

**L5 Textbook Answer.** Histograms, because they measure latency.

**Why L5 Fails at 3 AM or on the Bill.** Partially right; counters of errors with exemplars are just as valuable (jump from an error-rate spike to a failing trace).

**L7 Principal Defense.** Latency histograms (exemplar per bucket shows *which* request was slow) and error counters (jump to a failing request). Native histograms carry multiple timestamped exemplars per sample, giving richer coverage at the same series cost.
</details>

<details><summary><b>Q8 · "How do you know correlation works in production?"</b></summary>

**Initial Prompt.** Prove it.

**L5 Textbook Answer.** Click around in Grafana.

**Why L5 Fails at 3 AM or on the Bill.** Manual checks don't catch regressions after collector or SDK upgrades.

**L7 Principal Defense.** A synthetic probe: periodically fetch recent exemplars from Mimir, look up their trace IDs in Tempo, look up logs by trace ID in Loki, and export the success ratios as metrics with alerts — the observability platform has its own SLOs.
</details>

---

## 5. Invariants checklist

- [ ] Exemplars carry only `trace_id`/`span_id`, attached by a trace-based filter or aligned with tail sampling.
- [ ] Scrape protocols negotiate OpenMetrics or protobuf for exemplar-emitting targets; `exemplar-storage` is enabled and `max_exemplars` sized from ingest rate × lookback.
- [ ] Remote write has `send_exemplars: true`; the long-term store retains exemplars.
- [ ] Grafana data sources map metrics → traces → logs → profiles with consistent attribute/label translations.
- [ ] Logs carry `trace_id` as structured metadata; Loki derived fields use the label matcher.
- [ ] An automated probe measures exemplar → trace → log resolution rates.

---

## 6. References

- Prometheus exemplar storage (feature flag): <https://prometheus.io/docs/prometheus/latest/feature_flags/#exemplars-storage>
- Exemplar store source: <https://github.com/prometheus/prometheus/blob/v3.15.1/tsdb/exemplar.go>
- OpenMetrics exemplars: <https://prometheus.io/docs/specs/om/open_metrics_spec/#exemplars>
- Grafana: introduction to exemplars: <https://grafana.com/docs/grafana/latest/fundamentals/exemplars/>
- Tempo data source (trace to logs/metrics/profiles): <https://grafana.com/docs/grafana/latest/datasources/tempo/configure-tempo-data-source/>
- Loki derived fields: <https://grafana.com/docs/grafana/latest/datasources/loki/configure/>
- OpenTelemetry metrics SDK, exemplar filters: <https://opentelemetry.io/docs/specs/otel/metrics/sdk/#exemplarfilter>
