# 03 · Grafana Loki + LogQL, Tempo + TraceQL, and Pyroscope Continuous eBPF Profiling

> **Folder 06 — OpenTelemetry, Grafana Alloy and the LGTM Scale Stack · File 3 of 3.**
> Pinned to **Loki v3.7.9** (stable; **v4.0.0-rc.2** prerelease noted ⚠), **Tempo v3.1.1**, **Pyroscope v2.4.3**, **Grafana Alloy v1.21.3**.
> Labels: **[D]** documented / read in pinned source · **[M]** measured by the listing (deterministic, re-run by the gate) · **[E]** model · **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L3 `lgtm_query_lab.py` | **Loki storage.** Turns label designs into streams, chunks and objects using the v3.7.9 chunk defaults: a level label doubles chunk count and leaves 42% of chunks under 10% full; `trace_id` as a label produces 69M streams/day. **Mini LogQL engine.** Shows filter-before-parse gives the same answer with **53× fewer** JSON parses. Reproduces Loki's metric-query **pipeline error** and the `__error__=""` fix. Shows extracted labels explode a raw `count_over_time` into 8,927 series (limit 500), and `unwrap` quantiles match exact p99 bit-for-bit. **Mini TraceQL evaluator.** `>>` structural queries, an N+1 detector and `rate() by` all match generator ground truth. **Profiling.** At `pyroscope.ebpf`'s default 19 Hz a 2.0%→2.5% CPU regression has z = 0.84 per pod-window and z = 25.5 fleet-wide | ~2 s |

**Verification.**
- **Loki.** Defaults are read from the v3.7.9 configuration reference. The pipeline-error text comes from `pkg/logqlmodel/error.go`, and label-filter semantics from the LogQL docs [D].
- **Tempo.** Defaults come from the v3.1.1 generated manifest [D].
- **Pyroscope.** The v2 architecture comes from the v2.4.3 docs [D].
- **`pyroscope.ebpf`.** Arguments come from the Alloy v1.21.3 reference [D].
- **Engines.** The LogQL and TraceQL engines are small re-implementations of the documented semantics, not ports. Their outputs are checked against independent ground truth [M].
- **Not run.** No Loki, Tempo or Pyroscope binary was run.

---

## 0. Orientation

**The common pattern.** All three stores index the *small* thing, keep the *big* thing in object storage, and pay for every query in bytes scanned.

| | Indexed | Stored | Query cost driver |
|---|---|---|---|
| Loki | Stream labels (TSDB index, 24h periods) | Compressed chunks of log lines per stream | Bytes of chunks in the selected streams × time range |
| Tempo | Block metadata + bloom filters on trace IDs; columns (vParquet5) | Parquet blocks of spans | Columns touched × row groups × time range |
| Pyroscope | Series labels + segment/block metadata (metastore) | Profile segments/blocks (symbols, stacktraces, samples) | Profiles merged × time range |

**The 2026 architectures** [D]:

```text
 Loki 3.7 (stable)
   Alloy/OTel ─push─► distributor ─(ring, RF3)─► ingesters: per-stream head chunk → cut at 1.5 MiB / 2h / 30m idle
                                                  └─ flush chunks + TSDB index (24h) ─► S3
   query-frontend (split 1h, shard by bytes 600 MB) ─► queriers ─► ingesters (recent) + index-gateway + S3 chunks
 Loki 4.0 (rc.2, prerelease ⚠): Kafka in the write path (RF1 storage), columnar "DataObjects", new query planner/engine

 Tempo 3.1
   OTLP ─► distributor ─► Kafka ─┬─► block-builders: cut vParquet5 blocks ─► S3        (RF1: one copy, Kafka is the log)
                                 ├─► live-stores: last traces for queries (max_trace_idle 5s, live 30s, complete_block 20m)
                                 └─► metrics-generator (ring_mode: partition): span metrics, service graphs ─► remote_write
   backend-scheduler + backend-workers: compaction and retention (block_retention 336h)   [replace the old compactors]
   query-frontend ─► queriers ─► live-stores + S3 blocks (TraceQL search and TraceQL metrics)

 Pyroscope 2.4
   SDK / Alloy pyroscope.ebpf / OTLP profiles ─► distributor ─► segment-writers (diskless; 500 ms segments; one object per shard)
        ─► S3 + metastore (Raft, the only stateful component) ─► compaction-workers
   query-frontend ─► query-backend (stateless, reads object storage directly)
```

---

## 1. First principles

### 1.1 Loki: streams are the unit of everything [D][M]

**A stream is a unique label set.**
- Each stream has its own in-memory head chunk in an ingester (×RF).
- Chunks are cut at `chunk_target_size` (**1,572,864 B uncompressed**), at `max_chunk_age` (**2h**), or after `chunk_idle_period` (**30m**) with no lines.
- Each flushed chunk is an object (plus index entries).
- **Object count, index size, ingester memory and query fan-out all scale with streams, not bytes.**

L3 §1 models 2,000 pods × 2 containers with skewed per-container volume (lognormal, median 1 line/s):

| Label design | Streams | Chunks/day | Avg chunk (compressed) | Chunks < 10% full |
|---|---|---|---|---|
| namespace, app, container | 120 | 131,650 | 191.9 KiB | 0% |
| + `k8s.pod.name` | 4,000 | 142,403 | 177.4 KiB | 1% |
| + `level` (4 values) | 16,000 | 278,207 | 90.8 KiB | 42% |
| + `trace_id` | 68,991,831 | 68,991,831 | 0.4 KiB | 100% |

**Lessons.**
- **The pod label is affordable here.** Most containers still fill chunks before 2h.
- **Low-volume dimensions that split streams thinly double the cost.** `level`, where `error` is 2.5% of lines, is the example.
- **Per-request values as labels are fatal.**

**Two defaults make this real in 2026** [D]:
1. **OTLP ingestion.** `distributor.otlp_config.default_resource_attributes_as_index_labels` includes `service.instance.id`, `k8s.pod.name` and 16 other attributes. OTLP logs are therefore indexed per pod and per instance unless you override `limits_config.otlp_config.resource_attributes`.
2. **Structured metadata.** `allow_structured_metadata` defaults to **true** (limits: 64 KB, 128 entries per line). That is where `trace_id`, `user_id` and `pod_uid` belong. They are queryable as `| trace_id="…"` without creating streams.

### 1.2 LogQL execution: what actually costs [D][M]

```text
 {selector}               → index lookup: which streams, which chunks (time range)   ← the ONLY index use
 |= "x"  |~ "re"  != ...  → line filters: substring/regex over raw bytes            ← cheapest per line
 | json | logfmt | regexp | pattern  → parsers: extract labels                       ← expensive per line
 | label filters          → on extracted labels (numeric/duration/bytes/string)
 | line_format | label_format | drop | keep
 range agg [5m]           → count_over_time, rate, bytes_over_time, *_over_time | unwrap
 vector agg               → sum by (…)
```

What L3 §2 reproduced:

| Behaviour | Measured |
|---|---|
| **Filter before parse.** A line filter for the error marker before `| json` gives the identical per-path result. | **170 vs 9,000** JSON parses (53×) |
| **Pipeline errors in metric queries.** One pod's plain-text lines under `| json` raise "pipeline error: 'JSONParserErr' … Use a label filter to intentionally skip this error." This is Loki's real behaviour [D]. | `| __error__=""` fixes it (8,927 lines) |
| **Extracted labels are series labels.** `count_over_time({app="checkout"} | json …)` without aggregation makes every JSON field, including `trace_id` and `latency_ms`, part of the series identity. | **8,927 series**; Loki's `max_query_series` is **500**. `sum by (status)` gives 2 |
| **`unwrap` quantiles.** `quantile_over_time(0.99, … | unwrap latency_ms [5m]) by (path)` is computed over every value. | Matches exact p99 with zero error |

**Label-filter semantics worth memorising** [D]:
- If a numeric, duration or bytes conversion fails, "the log line is not filtered and an `__error__` label is added".
- Only string matchers can filter out `__error__` lines.

**Query-planning defaults** [D]:
- `split_queries_by_interval: 1h`;
- `tsdb_max_query_parallelism: 128`;
- `tsdb_max_bytes_per_shard: 600MB`;
- `query_timeout: 1m`;
- `max_query_length: 30d1h`;
- `max_entries_limit_per_query: 5000`;
- `max_query_bytes_read: 0B` (unlimited — **set it**).

### 1.3 Tempo 3: Kafka, RF1, and columns [D]

**Write path.**
- In microservices mode the distributor writes to Kafka (`ingest.kafka`).
- **Block-builders** consume partitions and cut vParquet5 blocks (max 20 MiB per block-builder block by default) to object storage: **one copy** (RF1). Durability before the block exists is Kafka's job.
- **Live-stores** consume the same partitions to serve recent traces. A trace is "live" until idle 5 s or 30 s old, and blocks complete within 20 minutes.
- **Backend scheduler/worker** replace compactors (retention 336h by default).
- **Metrics-generator** consumes partitions too (`ring_mode: partition`).

**Columns decide TraceQL speed.**
- vParquet5 is the default block version.
- **Dedicated columns** store chosen attributes as real Parquet columns instead of entries in a generic attribute map. The defaults are:
  - `k8s.cluster.name`, `k8s.namespace.name`, `k8s.pod.name` and `k8s.container.name` (resource scope);
  - `http.request.method` and `http.response.status_code` (span scope);
  - the list continues in the manifest.
- A predicate on a dedicated column reads one column. A predicate on a generic attribute reads the key and value columns of the map for every row group in range.
- Add your own hot attributes (`tenant.id`, `http.route`, `db.system`) per tenant via overrides.

**Default limits** (overrides.defaults) [D]:
- `ingestion.rate_limit_bytes` and `burst_size_bytes`: 30 MB;
- `max_traces_per_user`: 10,000 live traces;
- `global.max_bytes_per_trace`: **5 MB**, so traces above it are truncated or rejected — raise it for batch jobs or cut those traces at the source.

### 1.4 TraceQL semantics [D][M]

```text
 { resource.service.name = "checkout" && status = error }              spanset filter (spans that match)
 A >> B   B spans with an ancestor in A        A > B   B spans whose parent is in A
 A ~ B    siblings                             A && B  traces having both spansets (… and more operators)
 | count() > 5     | avg(duration) > 200ms     | select(span.http.route)          pipelines over spansets
 | rate() by (resource.service.name)   | quantile_over_time(duration, .99) by (…)   TraceQL metrics
 intrinsics: duration, name, status, kind, statusMessage, rootName, rootServiceName, traceDuration
 scopes:     span.  resource.  event.  link.  instrumentation.   (and unscoped .attr matching any scope)
```

What L3 §3 checked against ground truth on 5,000 traces:

| Query | Result |
|---|---|
| `{ resource.service.name = "checkout" && status = error } >> { span.db.system = "postgresql" && duration > 100ms }` | 30 traces, ground truth 30 |
| `{ span.db.system = "postgresql" } | count() > 5`, an **N+1 query detector** | 156 traces, ground truth 156 |
| `{ status = error } | rate() by (resource.service.name)` | Equals error spans ÷ window exactly |

**TraceQL metrics compute over the spans Tempo has.**
- If tier 2 tail-samples (file 01), TraceQL `rate()` counts what was kept.
- For RED, use span metrics generated before sampling, or re-weight with the metrics-generator span-multiplier/tracestate options ⚠.

### 1.5 Pyroscope 2: diskless writes and the statistics of profiles [D][M]

**Write path** [D]:
- Distributors route profiles so one application's profiles co-locate on a **segment-writer**.
- Segment-writers accumulate **500 ms** segments (`-segment-writer.segment-duration`) and write **one object per shard** containing all tenants' services for that shard. This minimises PUTs.
- Ingestion is synchronous: clients block until the object is durable and indexed in the metastore, with median latency "less than 500ms".
- The **metastore** (Raft) is the only stateful component.
- **Compaction-workers** merge segments into blocks.
- **Query-backends** read object storage directly and scale with the query load.
- Raising the segment duration cuts PUT cost but must stay well under client timeouts. Otherwise clients see `context deadline exceeded` and `422` [D].

**Profiles are samples.**
- `pyroscope.ebpf` (Alloy, embedding Grafana's fork of the OpenTelemetry eBPF profiler) samples at **19 Hz** by default and collects every 15 s [D].
- L3 §4 sets a function's CPU share regressing from 2.0% to 2.5%:

| Aggregation | Samples per side | z-score |
|---|---|---|
| One pod, one core, one 15 s window | 285 | 0.84 (noise) |
| 100 cores × 10 min | 1,140,000 | 25.5 |
| Needed for 95% confidence / 80% power | 13,806 | = 12 core-minutes |

- **Never conclude anything from one pod's 15-second flame graph.** Merge across pods and time.
- Compare equal time ranges with diff flame graphs.
- Choose time windows long enough for the effect size you care about.

<!-- listing:lgtm_query_lab.py -->
```python
"""lgtm_query_lab.py - the query-side physics of Loki 3.7, Tempo 3.1 and Pyroscope 2.4, with small
working engines instead of prose:

  1. Loki storage: how label choices turn into streams, chunks and objects (chunk_target_size 1,572,864,
     chunk_idle_period 30m, max_chunk_age 2h - the v3.7.9 defaults), including the OTLP default that makes
     k8s.pod.name an index label.
  2. A mini LogQL engine (stream selector, line filters, json/logfmt, label filters, unwrap, range and
     vector aggregations) that reproduces three production behaviours: filter-before-parse cost,
     the metric-query pipeline error ("Use a label filter to intentionally skip this error"), and the
     extracted-label series explosion that trips max_query_series (default 500).
  3. A mini TraceQL evaluator (spanset filters, >> and > structural operators, count()/avg() pipelines,
     rate() by) answering three real questions: erroring checkout spans with a slow Postgres descendant,
     N+1 query traces, and error rate per service - each checked against generator ground truth.
  4. Continuous profiling statistics: pyroscope.ebpf samples at 19 Hz by default (Alloy v1.21.3), so a
     2.0% -> 2.5% CPU regression in one function is invisible per pod-window and obvious fleet-wide.

Deterministic, stdlib only. Usage: python lgtm_query_lab.py [target.md]
"""
import collections
import json
import math
import random
import re
import sys

# ----------------------------------------------------------------------------------------------- LogQL


class PipelineError(Exception):
    pass


def parse_logfmt(line):
    out = {}
    for m in re.finditer(r'(\w+)=("([^"]*)"|\S+)', line):
        out[m.group(1)] = m.group(3) if m.group(3) is not None else m.group(2)
    return out


TOK = re.compile(r'\s*(\|=|\|~|!=|!~|=~|>=|<=|==|\||\{|\}|\(|\)|\[|\]|,|=|>|<|"(?:[^"\\]|\\.)*"|`[^`]*`|'
                 r'[0-9.]+[a-z]+|[0-9.]+|[A-Za-z_][A-Za-z0-9_.]*)')


def tokenize(s):
    pos, out = 0, []
    while pos < len(s):
        m = TOK.match(s, pos)
        if not m or m.end() == pos:
            if s[pos:].strip() == "":
                break
            raise SyntaxError(f"bad token at {s[pos:pos + 20]!r}")
        out.append(m.group(1))
        pos = m.end()
    return out


def unquote(t):
    if t.startswith("`"):
        return t[1:-1]
    return json.loads(t)


def dur_s(t):
    m = re.fullmatch(r"([0-9.]+)(ms|s|m|h)", t)
    return float(m.group(1)) * {"ms": 0.001, "s": 1, "m": 60, "h": 3600}[m.group(2)]


class LogQL:
    RANGE_FNS = {"count_over_time", "rate", "bytes_over_time", "sum_over_time", "quantile_over_time",
                 "avg_over_time", "max_over_time"}
    VEC_FNS = {"sum", "count", "max", "min", "avg"}

    def __init__(self, entries):
        self.entries = entries          # list of (ts, stream_labels dict, line)
        self.parses = 0

    # ---- parsing
    def parse(self, q):
        self.t, self.i = tokenize(q), 0
        node = self.metric()
        if self.i != len(self.t):
            raise SyntaxError(f"trailing tokens {self.t[self.i:]}")
        return node

    def peek(self, k=0):
        return self.t[self.i + k] if self.i + k < len(self.t) else None

    def take(self, want=None):
        tok = self.t[self.i]
        if want is not None and tok != want:
            raise SyntaxError(f"expected {want} got {tok}")
        self.i += 1
        return tok

    def labels_list(self):
        self.take("(")
        out = []
        while self.peek() != ")":
            out.append(self.take())
            if self.peek() == ",":
                self.take()
        self.take(")")
        return out

    def metric(self):
        fn = self.peek()
        if fn in self.VEC_FNS:
            self.take()
            by = None
            if self.peek() == "by":
                self.take()
                by = self.labels_list()
            self.take("(")
            inner = self.metric()
            self.take(")")
            if by is None and self.peek() == "by":
                self.take()
                by = self.labels_list()
            return ("vec", fn, by, inner)
        if fn in self.RANGE_FNS:
            self.take()
            self.take("(")
            param = None
            if fn == "quantile_over_time":
                param = float(self.take())
                self.take(",")
            sel, stages = self.log_expr()
            self.take("[")
            rng = dur_s(self.take())
            self.take("]")
            self.take(")")
            by = None
            if self.peek() == "by":
                self.take()
                by = self.labels_list()
            return ("range", fn, param, sel, stages, rng, by)
        sel, stages = self.log_expr()
        return ("log", sel, stages)

    def log_expr(self):
        self.take("{")
        sel = []
        while self.peek() != "}":
            name, op, val = self.take(), self.take(), unquote(self.take())
            sel.append((name, op, val))
            if self.peek() == ",":
                self.take()
        self.take("}")
        stages = []
        while self.peek() in ("|=", "|~", "!=", "!~", "|"):
            op = self.take()
            if op != "|":
                stages.append(("line", op, unquote(self.take())))
                continue
            word = self.take()
            if word in ("json", "logfmt"):
                stages.append(("parse", word))
            elif word == "unwrap":
                stages.append(("unwrap", self.take()))
            else:
                cmp_op, raw = self.take(), self.take()
                val = unquote(raw) if raw[0] in "\"`" else float(raw)
                stages.append(("label", word, cmp_op, val))
        return sel, stages

    # ---- evaluation
    @staticmethod
    def match(op, have, want):
        if op == "=":
            return have == want
        if op == "!=":
            return have != want
        if op == "=~":
            return re.fullmatch(want, have) is not None
        return re.fullmatch(want, have) is None

    def run_pipeline(self, labels, line, stages):
        labels = dict(labels)
        value = None
        for st in stages:
            if st[0] == "line":
                _, op, s = st
                hit = (s in line) if op in ("|=", "!=") else (re.search(s, line) is not None)
                if hit != (op in ("|=", "|~")):
                    return None
            elif st[0] == "parse":
                self.parses += 1
                try:
                    fields = json.loads(line) if st[1] == "json" else parse_logfmt(line)
                    if not isinstance(fields, dict) or (st[1] == "logfmt" and not fields):
                        raise ValueError
                except ValueError:
                    labels["__error__"] = "JSONParserErr" if st[1] == "json" else "LogfmtParserErr"
                    continue
                for k, v in fields.items():
                    labels[k + "_extracted" if k in labels else k] = str(v)
            elif st[0] == "label":
                _, name, op, want = st
                have = labels.get(name, "")
                if isinstance(want, str):
                    if not self.match(op, have, want):
                        return None
                else:
                    try:
                        x = float(have)
                    except ValueError:
                        labels["__error__"] = labels.get("__error__") or "LabelFilterErr"
                        continue          # Loki keeps the line and tags it
                    ok = {"==": x == want, "=": x == want, "!=": x != want, ">": x > want, ">=": x >= want,
                          "<": x < want, "<=": x <= want}[op]
                    if not ok:
                        return None
            elif st[0] == "unwrap":
                try:
                    value = float(labels.pop(st[1]))
                except (KeyError, ValueError):
                    labels["__error__"] = "SampleExtractionErr"
        return labels, line, value

    def select(self, sel, stages, t0, t1):
        for ts, labels, line in self.entries:
            if t0 < ts <= t1 and all(self.match(op, labels.get(n, ""), v) for n, op, v in sel):
                r = self.run_pipeline(labels, line, stages)
                if r is not None:
                    yield ts, r

    def eval(self, node, t):
        if node[0] == "vec":
            _, fn, by, inner = node
            groups = collections.defaultdict(list)
            for lab, v in self.eval(inner, t).items():
                d = dict(lab)
                groups[tuple(sorted((k, d.get(k, "")) for k in (by or [])))].append(v)
            agg = {"sum": sum, "count": len, "max": max, "min": min, "avg": lambda xs: sum(xs) / len(xs)}[fn]
            return {k: agg(v) for k, v in groups.items()}
        _, fn, param, sel, stages, rng, by = node
        series = collections.defaultdict(list)
        for ts, (labels, line, value) in self.select(sel, stages, t - rng, t):
            if labels.get("__error__"):
                key = ",".join(f'{k}="{v}"' for k, v in sorted(labels.items()) if k != "__error__")
                raise PipelineError(f"pipeline error: '{labels['__error__']}' for series: '{{{key[:60]}...}}'. "
                                    f"Use a label filter to intentionally skip this error.")
            key = tuple(sorted(labels.items())) if by is None else tuple(sorted((k, labels.get(k, "")) for k in by))
            series[key].append((line, value))
        out = {}
        for key, items in series.items():
            vals = [v for _, v in items]
            if fn == "count_over_time":
                out[key] = len(items)
            elif fn == "rate":
                out[key] = len(items) / rng
            elif fn == "bytes_over_time":
                out[key] = sum(len(line) for line, _ in items)
            elif fn == "sum_over_time":
                out[key] = sum(vals)
            elif fn == "avg_over_time":
                out[key] = sum(vals) / len(vals)
            elif fn == "max_over_time":
                out[key] = max(vals)
            else:
                out[key] = quantile(param, vals)
        return out

    def query(self, q, t):
        return self.eval(self.parse(q), t)


def quantile(q, xs):
    """Prometheus/Loki quantile_over_time: linear interpolation between closest ranks."""
    xs = sorted(xs)
    rank = q * (len(xs) - 1)
    lo, hi = math.floor(rank), math.ceil(rank)
    return xs[lo] + (xs[hi] - xs[lo]) * (rank - lo)


def gen_logs(seed=11):
    rng = random.Random(seed)
    paths = ["/api/cart", "/api/checkout", "/api/pay", "/api/search", "/api/item"]
    entries, truth = [], collections.defaultdict(list)
    for sec in range(600):
        for pod in range(6):
            for _ in range(5):
                ts = sec + rng.random()
                path = rng.choice(paths)
                err = rng.random() < 0.02
                lat = round(rng.lognormvariate(3.5, 0.6) * (4 if err else 1), 1)
                labels = {"app": "checkout", "namespace": "shop", "pod": f"checkout-{pod}"}
                if pod == 5 and rng.random() < 0.05:   # a legacy library on one pod prints plain text
                    entries.append((ts, labels, f"WARN pool exhausted after {lat}ms"))
                    continue
                rec = {"level": "error" if err else "info", "path": path, "status": 500 if err else 200,
                       "latency_ms": lat, "trace_id": f"{rng.getrandbits(64):016x}"}
                entries.append((ts, labels, json.dumps(rec, separators=(",", ":"))))
                if ts > 300:
                    truth[path].append(lat)
            ts = sec + rng.random()
            entries.append((ts, {"app": "payments", "namespace": "shop", "pod": f"payments-{pod}"},
                            f'level=info msg="charge ok" amount={rng.randint(5, 500)} psp=stripe'))
    entries.sort(key=lambda e: e[0])
    return entries, truth


# --------------------------------------------------------------------------------------------- TraceQL


def gen_traces(n, seed=5):
    rng = random.Random(seed)
    spans, truth = [], {"slow_db_under_err": set(), "n_plus_one": set()}
    sid = 0

    def add(tid, parent, svc, name, dur, status="ok", **attrs):
        nonlocal sid
        sid += 1
        spans.append({"trace": tid, "id": sid, "parent": parent, "resource.service.name": svc, "name": name,
                      "duration": dur, "status": status, **{f"span.{k}": v for k, v in attrs.items()}})
        return sid

    for t in range(n):
        tid = f"t{t:05d}"
        fe = add(tid, None, "frontend", "GET /checkout", 0.0, **{"http.status_code": 200})
        err = rng.random() < 0.04
        co = add(tid, fe, "checkout", "PlaceOrder", 0.0, "error" if err else "ok")
        n_db = 20 if rng.random() < 0.03 else rng.randint(1, 3)
        slow = False
        for _ in range(n_db):
            d = rng.lognormvariate(-4.0, 0.8) * (8 if rng.random() < 0.05 else 1)
            slow |= d > 0.1
            add(tid, co, "checkout", "SELECT orders", d, **{"db.system": "postgresql"})
        pay = add(tid, co, "payments", "Charge", rng.lognormvariate(-3, 0.5),
                  "error" if (err and rng.random() < 0.5) else "ok")
        add(tid, pay, "payments", "POST psp", rng.lognormvariate(-3.2, 0.5), **{"http.status_code": 200})
        if err and slow:
            truth["slow_db_under_err"].add(tid)
        if n_db > 5:
            truth["n_plus_one"].add(tid)
    return spans, truth


class TraceQL:
    TOK = re.compile(r'\s*(>>|&&|\|\||!=|>=|<=|=~|[{}()|><=,]|"[^"]*"|[0-9.]+(?:ms|s)?|[A-Za-z_][A-Za-z0-9_.]*)')

    def __init__(self, spans, window_s):
        self.by_trace = collections.defaultdict(list)
        for s in spans:
            self.by_trace[s["trace"]].append(s)
        self.window = window_s

    def tokenize(self, q):
        out, pos = [], 0
        while pos < len(q):
            m = self.TOK.match(q, pos)
            if not m or m.end() == pos:
                if not q[pos:].strip():
                    break
                raise SyntaxError(q[pos:])
            out.append(m.group(1))
            pos = m.end()
        return out

    @staticmethod
    def value(tok):
        if tok.startswith('"'):
            return tok[1:-1]
        if tok in ("error", "ok", "unset"):
            return tok
        if tok.endswith("ms"):
            return float(tok[:-2]) / 1000
        if tok.endswith("s"):
            return float(tok[:-1])
        return float(tok)

    def cond(self, toks):
        """{ a op v && b op v || ... } -> predicate (&& binds tighter than ||)."""
        ors, cur = [], []
        i = 0
        while i < len(toks):
            if toks[i] == "||":
                ors.append(cur)
                cur = []
                i += 1
                continue
            if toks[i] == "&&":
                i += 1
                continue
            attr, op, val = toks[i], toks[i + 1], self.value(toks[i + 2])
            cur.append((attr, op, val))
            i += 3
        ors.append(cur)

        def ok(span, attr, op, val):
            have = span.get(attr)
            if have is None:
                return False
            if op == "=":
                return have == val
            if op == "!=":
                return have != val
            if op == "=~":
                return re.fullmatch(val, str(have)) is not None
            return {">": have > val, ">=": have >= val, "<": have < val, "<=": have <= val}[op]
        return lambda s: any(all(ok(s, *c) for c in conj) for conj in ors)

    def query(self, q):
        toks = self.tokenize(q)
        parts, i = [], 0
        stage = []
        while i < len(toks):          # split on top-level structural ops and pipes
            stage.append(toks[i])
            i += 1
        # spanset expression: { } [>>|>] { } ; then optional | pipeline
        pipe_at = toks.index("|") if "|" in toks else len(toks)
        expr, pipe = toks[:pipe_at], toks[pipe_at + 1:]
        sets, ops, j = [], [], 0
        while j < len(expr):
            k = expr.index("}", j)
            sets.append(self.cond(expr[j + 1:k]))
            j = k + 1
            if j < len(expr):
                ops.append(expr[j])
                j += 1
        results = {}
        for tid, spans in self.by_trace.items():
            matched = [s for s in spans if sets[0](s)]
            for op, pred in zip(ops, sets[1:]):
                ids = {s["id"] for s in matched}
                parent = {s["id"]: s["parent"] for s in spans}
                nxt = []
                for s in spans:
                    if not pred(s):
                        continue
                    if op == ">":
                        hit = s["parent"] in ids
                    else:                       # >> descendant: walk up the ancestors
                        p, hit = s["parent"], False
                        while p is not None and not hit:
                            hit = p in ids
                            p = parent.get(p)
                    if hit:
                        nxt.append(s)
                matched = nxt
            if matched:
                results[tid] = matched
        if not pipe:
            return results
        if pipe[0] == "rate":            # { } | rate() by (attr)
            attr = pipe[pipe.index("by") + 2]
            c = collections.Counter(s[attr] for ms in results.values() for s in ms)
            return {k: v / self.window for k, v in c.items()}
        fn = pipe[0]
        arg = pipe[2] if pipe[2] != ")" else None
        op, thr = pipe[-2], self.value(pipe[-1])
        out = {}
        for tid, ms in results.items():
            x = len(ms) if fn == "count" else sum(s[arg] for s in ms) / len(ms)
            if {">": x > thr, ">=": x >= thr, "<": x < thr, "=": x == thr}[op]:
                out[tid] = ms
        return out


# ------------------------------------------------------------------------------------------- profiling


def main():
    checks = []
    print("== 1. Loki: labels -> streams -> chunks -> objects (v3.7.9 chunk defaults) ==")
    target, idle_s, max_age_s, ratio, line_b = 1_572_864, 1800, 7200, 8.0, 300
    pods, containers = 2000, 2
    vr = random.Random(3)
    rates = [vr.lognormvariate(0, 1.2) for _ in range(pods * containers)]     # lines/s, median 1, skewed
    level_share = {"info": 0.90, "warn": 0.07, "error": 0.025, "debug": 0.005}

    def stream_chunks(r):
        """chunks/day for one stream of r lines/s: cut at chunk_target_size, at max_chunk_age, or, when
        lines are further apart than chunk_idle_period, one chunk per line."""
        if r <= 0:
            return 0, 0.0
        if 1 / r > idle_s:
            return r * 86400, line_b
        b = r * line_b * 86400
        n = max(math.ceil(b / target), math.ceil(86400 / max_age_s))
        return n, b / n

    def design(stream_rates):
        n_chunks = tot_b = small = 0
        for r in stream_rates:
            n, size = stream_chunks(r)
            n_chunks += n
            tot_b += n * size
            small += n if size < target / 10 else 0
        return len(stream_rates), n_chunks, tot_b / ratio / n_chunks, small / n_chunks
    groups = collections.defaultdict(float)
    for i, r in enumerate(rates):
        groups[i % 120] += r
    total_lines_day = sum(rates) * 86400
    rows = [("namespace, app, container (static labels)", design(list(groups.values()))),
            ("+ k8s.pod.name (Loki OTLP default index label)", design(rates)),
            ("+ level as an index label (4 values)", design([r * s for r in rates for s in level_share.values()]))]
    req = int(total_lines_day / 10)
    rows.append(("+ trace_id as a label (1 request -> 1 stream)", (req, req, 10 * line_b / ratio, 1.0)))
    print(f"{pods:,} pods x {containers} containers, lognormal lines/s per container (median 1), {line_b} B/line, "
          f"compression ~{ratio:.0f}x [E]")
    print(f"{'label design':<48} {'streams':>12} {'chunks/day':>12} {'avg chunk':>10} {'<10% full':>9}")
    for name, (s, n, avg, small) in rows:
        print(f"{name:<48} {s:>12,} {n:>12,.0f} {avg / 1024:>8.1f}KiB {small:>9.0%}")
    sizes = [r[1][2] for r in rows]
    checks.append(("label cardinality shrinks chunks", rows[3][1][1] > 100 * rows[0][1][1] and
                   sizes[0] > sizes[1] > sizes[2] > sizes[3]))
    print("-> object count, index size and ingester memory scale with STREAMS, not bytes. A per-pod label is")
    print("   affordable here (+8% chunks) because most containers still fill chunks before max_chunk_age; a")
    print("   4-value level label doubles the chunk count and leaves 42% of chunks under 10% full; trace_id")
    print("   as a label is fatal. Keep index labels bounded and query-scoping; put trace_id, user_id and")
    print("   pod UID in structured metadata (allow_structured_metadata defaults to true).")
    print()

    print("== 2. A mini LogQL engine on 10 minutes of checkout + payments logs ==")
    entries, truth = gen_logs()
    eng = LogQL(entries)
    T = 600
    q_fast = 'sum by (path) (count_over_time({app="checkout"} |= `"level":"error"` | json | level="error" [5m]))'
    q_slow = 'sum by (path) (count_over_time({app="checkout"} | json | __error__="" | level="error" [5m]))'
    eng.parses = 0
    a = eng.query(q_fast, T)
    p_fast = eng.parses
    eng.parses = 0
    b = eng.query(q_slow, T)
    p_slow = eng.parses
    print(f"errors by path, line filter first : {dict(sorted((k[0][1], v) for k, v in a.items()))}  json parses {p_fast:,}")
    print(f"errors by path, parse everything  : {dict(sorted((k[0][1], v) for k, v in b.items()))}  json parses {p_slow:,}")
    checks.append(("filter-first same answer, fewer parses", a == b and p_slow > 20 * p_fast))
    try:
        eng.query('sum(count_over_time({app="checkout"} | json [5m]))', T)
        perr = None
    except PipelineError as e:
        perr = str(e)
    print(f"metric query over a stream with plain-text lines: {perr[:110] if perr else 'no error'}...")
    fixed = eng.query('sum(count_over_time({app="checkout"} | json | __error__="" [5m]))', T)
    print(f"with | __error__=\"\": {list(fixed.values())[0]:,.0f} lines counted")
    checks.append(("pipeline error raised then fixed", perr is not None and "intentionally skip" in perr))
    raw = eng.query('count_over_time({app="checkout"} | json | __error__="" [5m])', T)
    grouped = eng.query('sum by (status) (count_over_time({app="checkout"} | json | __error__="" [5m]))', T)
    print(f"count_over_time after | json without aggregation returns {len(raw):,} series (every extracted field,")
    print(f"incl. trace_id and latency_ms, became a label) vs {len(grouped)} with sum by (status); Loki's default")
    print(f"max_query_series is 500")
    checks.append(("extracted labels explode series", len(raw) > 500 and len(grouped) <= 3))
    p99 = eng.query('quantile_over_time(0.99, {app="checkout"} | json | __error__="" | unwrap latency_ms [5m]) by (path)', T)
    exact = {p: quantile(0.99, v) for p, v in truth.items()}
    worst = max(abs(p99[(("path", p),)] - exact[p]) for p in exact)
    print(f"quantile_over_time(0.99, ... | unwrap latency_ms [5m]) by (path) vs exact p99 from the generator: "
          f"max abs diff {worst:.3g} ms")
    checks.append(("unwrap quantile exact", worst < 1e-9))
    print()

    print("== 3. A mini TraceQL evaluator on 5,000 traces ==")
    spans, ttruth = gen_traces(5000)
    tq = TraceQL(spans, window_s=300)
    q1 = '{ resource.service.name = "checkout" && status = error } >> { span.db.system = "postgresql" && duration > 100ms }'
    r1 = tq.query(q1)
    print(f"{q1}\n  -> {len(r1)} traces; ground truth {len(ttruth['slow_db_under_err'])}")
    q2 = '{ span.db.system = "postgresql" } | count() > 5'
    r2 = tq.query(q2)
    print(f"{q2}   (N+1 query detector)\n  -> {len(r2)} traces; ground truth {len(ttruth['n_plus_one'])}")
    q3 = '{ status = error } | rate() by (resource.service.name)'
    r3 = tq.query(q3)
    err_truth = collections.Counter(s["resource.service.name"] for s in spans if s["status"] == "error")
    print(f"{q3}\n  -> " + ", ".join(f"{k} {v:.3f}/s" for k, v in sorted(r3.items())))
    checks.append(("TraceQL matches ground truth", set(r1) == ttruth["slow_db_under_err"] and set(r2) == ttruth["n_plus_one"]
                   and all(abs(r3[k] - err_truth[k] / 300) < 1e-12 for k in err_truth)))
    q4 = '{ resource.service.name = "checkout" } > { span.db.system = "postgresql" } | avg(duration) > 50ms'
    print(f"{q4}\n  -> {len(tq.query(q4))} traces whose checkout->postgres child spans average > 50 ms")
    print("-> TraceQL metrics run over ALL ingested spans in the window; if the pipeline tail-samples, rate()")
    print("   counts only what was kept (Tempo's span multiplier / tracestate options exist to re-weight).")
    print()

    print("== 4. Continuous profiling: what 19 Hz sampling can and cannot see ==")
    hz, window = 19, 15
    base, regressed = 0.020, 0.025
    rng = random.Random(21)

    def sample(p, n):
        return sum(rng.random() < p for _ in range(n))

    def z(n):
        a, b = sample(base, n), sample(regressed, n)
        p = (a + b) / (2 * n)
        se = math.sqrt(2 * p * (1 - p) / n) if p else 1
        return (b - a) / n / se
    per_window = hz * window
    fleet = hz * 600 * 100           # 100 cores for 10 minutes
    z_small, z_big = z(per_window), z(fleet)
    need = (1.96 + 0.8416) ** 2 * (base * (1 - base) + regressed * (1 - regressed)) / (regressed - base) ** 2
    print(f"one pod, one core, one {window}s collect window: {per_window} samples -> expected {base * per_window:.1f} vs "
          f"{regressed * per_window:.1f} hits; z = {z_small:.2f}")
    print(f"100 cores x 10 minutes: {fleet:,} samples per side -> z = {z_big:.1f}")
    print(f"samples per side for 95%/80% power on 2.0% -> 2.5%: {need:,.0f} = {need / hz / 60:.0f} core-minutes at {hz} Hz")
    checks.append(("regression invisible per window, visible fleet-wide", abs(z_small) < 2 and z_big > 5))
    stacks = collections.Counter()
    frames = {"main;http;checkout;serialize": 0.025, "main;http;checkout;db.query": 0.30,
              "main;http;checkout;pricing": 0.12, "main;gc": 0.18, "main;http;cart": 0.375}
    keys, weights = list(frames), list(frames.values())
    for k in rng.choices(keys, weights, k=fleet):
        stacks[k] += 1
    total = collections.Counter()
    for k, v in stacks.items():
        parts = k.split(";")
        for d in range(1, len(parts) + 1):
            total[";".join(parts[:d])] += v
    print("flame graph (total %): " + ", ".join(f"{k.split(';')[-1]} {total[k] / fleet:.1%}" for k in
                                               ("main;http", "main;http;checkout", "main;gc")))
    checks.append(("flame totals add up", total["main"] == fleet and
                   abs(total["main;http;checkout"] / fleet - 0.445) < 0.01))
    print("-> profiles are statistics: query them merged over many pods and minutes (Pyroscope/Grafana")
    print("   'Explore Profiles' does), compare like-for-like time ranges, and use diff flame graphs.")
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:lgtm_query_lab.py -->
```text
== 1. Loki: labels -> streams -> chunks -> objects (v3.7.9 chunk defaults) ==
2,000 pods x 2 containers, lognormal lines/s per container (median 1), 300 B/line, compression ~8x [E]
label design                                          streams   chunks/day  avg chunk <10% full
namespace, app, container (static labels)                 120      131,650    191.9KiB        0%
+ k8s.pod.name (Loki OTLP default index label)          4,000      142,403    177.4KiB        1%
+ level as an index label (4 values)                   16,000      278,207     90.8KiB       42%
+ trace_id as a label (1 request -> 1 stream)      68,991,831   68,991,831      0.4KiB      100%
-> object count, index size and ingester memory scale with STREAMS, not bytes. A per-pod label is
   affordable here (+8% chunks) because most containers still fill chunks before max_chunk_age; a
   4-value level label doubles the chunk count and leaves 42% of chunks under 10% full; trace_id
   as a label is fatal. Keep index labels bounded and query-scoping; put trace_id, user_id and
   pod UID in structured metadata (allow_structured_metadata defaults to true).

== 2. A mini LogQL engine on 10 minutes of checkout + payments logs ==
errors by path, line filter first : {'/api/cart': 34, '/api/checkout': 26, '/api/item': 33, '/api/pay': 39, '/api/search': 38}  json parses 170
errors by path, parse everything  : {'/api/cart': 34, '/api/checkout': 26, '/api/item': 33, '/api/pay': 39, '/api/search': 38}  json parses 9,000
metric query over a stream with plain-text lines: pipeline error: 'JSONParserErr' for series: '{app="checkout",namespace="shop",pod="checkout-5"...}'. Use a lab...
with | __error__="": 8,927 lines counted
count_over_time after | json without aggregation returns 8,927 series (every extracted field,
incl. trace_id and latency_ms, became a label) vs 2 with sum by (status); Loki's default
max_query_series is 500
quantile_over_time(0.99, ... | unwrap latency_ms [5m]) by (path) vs exact p99 from the generator: max abs diff 0 ms

== 3. A mini TraceQL evaluator on 5,000 traces ==
{ resource.service.name = "checkout" && status = error } >> { span.db.system = "postgresql" && duration > 100ms }
  -> 30 traces; ground truth 30
{ span.db.system = "postgresql" } | count() > 5   (N+1 query detector)
  -> 156 traces; ground truth 156
{ status = error } | rate() by (resource.service.name)
  -> checkout 0.663/s, payments 0.343/s
{ resource.service.name = "checkout" } > { span.db.system = "postgresql" } | avg(duration) > 50ms
  -> 688 traces whose checkout->postgres child spans average > 50 ms
-> TraceQL metrics run over ALL ingested spans in the window; if the pipeline tail-samples, rate()
   counts only what was kept (Tempo's span multiplier / tracestate options exist to re-weight).

== 4. Continuous profiling: what 19 Hz sampling can and cannot see ==
one pod, one core, one 15s collect window: 285 samples -> expected 5.7 vs 7.1 hits; z = 0.84
100 cores x 10 minutes: 1,140,000 samples per side -> z = 25.5
samples per side for 95%/80% power on 2.0% -> 2.5%: 13,806 = 12 core-minutes at 19 Hz
flame graph (total %): http 82.0%, checkout 44.6%, gc 18.0%
-> profiles are statistics: query them merged over many pods and minutes (Pyroscope/Grafana
   'Explore Profiles' does), compare like-for-like time ranges, and use diff flame graphs.

checks: 8/8 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 Loki 3.7 (simple scalable or microservices; TSDB index, schema v13, S3)

```yaml
# loki.yaml — keys verified against docs/sources/shared/configuration.md @ v3.7.9
auth_enabled: true
server:
  http_listen_port: 3100
  grpc_listen_port: 9095
common:
  path_prefix: /var/loki
  replication_factor: 3
  storage:
    s3:
      bucketnames: acme-loki-chunks
      region: us-east-1
schema_config:
  configs:
    - from: "2026-01-01"
      store: tsdb
      object_store: s3
      schema: v13
      index:
        prefix: loki_index_
        period: 24h
storage_config:
  tsdb_shipper:
    active_index_directory: /var/loki/tsdb-index
    cache_location: /var/loki/tsdb-cache
ingester:
  chunk_encoding: snappy
  chunk_target_size: 1572864
  chunk_idle_period: 30m
  max_chunk_age: 2h
compactor:
  working_directory: /var/loki/compactor
  retention_enabled: true
  retention_delete_delay: 2h
  delete_request_store: s3
limits_config:
  ingestion_rate_mb: 20
  ingestion_burst_size_mb: 40
  per_stream_rate_limit: 5MB
  per_stream_rate_limit_burst: 20MB
  max_global_streams_per_user: 20000
  max_label_names_per_series: 15
  allow_structured_metadata: true
  max_structured_metadata_size: 64KB
  max_line_size: 256KB
  max_query_series: 500
  max_query_length: 30d1h
  max_query_bytes_read: 200GB
  query_timeout: 2m
  split_queries_by_interval: 1h
  tsdb_max_bytes_per_shard: 600MB
  retention_period: 744h
  retention_stream:
    - selector: '{namespace="debug"}'
      priority: 1
      period: 72h
  otlp_config:
    resource_attributes:
      ignore_defaults: true
      attributes_config:
        - action: index_label
          attributes:
            - service.name
            - service.namespace
            - deployment.environment.name
            - k8s.cluster.name
            - k8s.namespace.name
        - action: structured_metadata
          attributes:
            - k8s.pod.name
            - service.instance.id
            - k8s.container.name
```

**Why.**
- **Chunk encoding.** `chunk_encoding: snappy` trades some storage for much cheaper decompression; the default is gzip ⚠. Measure both on your logs.
- **OTLP index labels.** `ignore_defaults: true` turns the 18-attribute OTLP default into an explicit, bounded index-label list. Per-pod and per-instance identity moves to structured metadata (§1.1).
- **Query cap.** `max_query_bytes_read` puts a hard cap on what one query can scan; the default is unlimited.
- **Retention.** `retention_stream` gives short retention to debug namespaces. The compactor needs `delete_request_store` when retention is on.

### 2.2 Alloy log pipeline (Kubernetes pods → Loki) with labels vs structured metadata

```alloy
discovery.kubernetes "pods" {
  role = "pod"
}

discovery.relabel "pods" {
  targets = discovery.kubernetes.pods.targets
  rule {
    source_labels = ["__meta_kubernetes_namespace"]
    target_label  = "namespace"
  }
  rule {
    source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name"]
    target_label  = "app"
  }
  rule {
    source_labels = ["__meta_kubernetes_pod_container_name"]
    target_label  = "container"
  }
  rule {
    source_labels = ["__meta_kubernetes_pod_name"]
    target_label  = "pod"
  }
}

loki.source.kubernetes "pods" {
  targets    = discovery.relabel.pods.output
  forward_to = [loki.process.apps.receiver]
}

loki.process "apps" {
  stage.json {
    expressions = { level = "level", trace_id = "trace_id", route = "path" }
  }
  stage.drop {
    source              = "level"
    value               = "debug"
    drop_counter_reason = "debug_level"
  }
  stage.drop {
    older_than          = "1h"
    drop_counter_reason = "too_old"
  }
  // The extracted map starts with the entry's labels, so "pod" is available here; moving a label
  // to structured metadata removes it from the label set (and therefore from the stream identity).
  stage.structured_metadata {
    values = { trace_id = "", level = "", pod = "" }
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

**Labels kept vs moved.**
- Index labels are `namespace`, `app` and `container`.
- `trace_id`, `level` and `pod` go to structured metadata. Grafana's trace-to-logs link then queries `{app="checkout"} | trace_id="…"` (Folder 05 file 02).
- Debug lines and lines older than an hour are dropped at the edge, with a reason counter.

### 2.3 Tempo 3.1 (microservices with Kafka; keys from the v3.1.1 manifest)

```yaml
# tempo.yaml — shared config; each workload sets -target (distributor, block-builder, live-store,
# metrics-generator, query-frontend, querier, backend-scheduler, backend-worker).
stream_over_http_enabled: true
server:
  http_listen_port: 3200
distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318
ingest:
  kafka:
    address: kafka-bootstrap.kafka.svc:9092
    topic: tempo-ingest
    auto_create_topic_enabled: false
block_builder:
  consume_cycle_duration: 5m
live_store:
  max_trace_idle: 5s
  max_trace_live: 30s
  complete_block_timeout: 20m
metrics_generator:
  ring_mode: partition
  processor:
    service_graphs:
      dimensions: [k8s.cluster.name]
      peer_attributes: [peer.service, db.name, db.system]
    span_metrics:
      dimensions: [http.route]
  storage:
    path: /var/tempo/generator/wal
    remote_write:
      - url: http://mimir-distributor.mimir.svc:8080/api/v1/push
        headers:
          X-Scope-OrgID: prod
storage:
  trace:
    backend: s3
    s3:
      bucket: acme-tempo-traces
      endpoint: s3.us-east-1.amazonaws.com
      region: us-east-1
    block:
      version: vParquet5
      parquet_dedicated_columns:
        - scope: resource
          name: service.namespace
          type: string
        - scope: span
          name: http.route
          type: string
        - scope: span
          name: db.system
          type: string
overrides:
  defaults:
    ingestion:
      rate_limit_bytes: 60000000
      burst_size_bytes: 90000000
      max_traces_per_user: 50000
    global:
      max_bytes_per_trace: 10000000
    metrics_generator:
      processors: [service-graphs, span-metrics]
```

⚠ **Caveats.**
- Setting `parquet_dedicated_columns` *replaces* the default list rather than appending to it. Copy the defaults you still want from the manifest before adding new ones.
- The metrics-generator only sees what reaches Tempo. If tail sampling happens before Tempo, its RED is biased (file 01, F4).

### 2.4 Pyroscope via Alloy eBPF (DaemonSet) and a Java service

```alloy
discovery.kubernetes "local_pods" {
  role = "pod"
  selectors {
    role  = "pod"
    field = "spec.nodeName=" + sys.env("NODE_NAME")   // NODE_NAME from the Downward API (fieldRef spec.nodeName)
  }
}

discovery.relabel "profiling" {
  targets = discovery.kubernetes.local_pods.targets
  rule {
    source_labels = ["__meta_kubernetes_pod_annotation_profiles_grafana_com_cpu_ebpf_enabled"]
    regex         = "true"
    action        = "keep"
  }
  rule {
    source_labels = ["__meta_kubernetes_namespace", "__meta_kubernetes_pod_label_app_kubernetes_io_name"]
    separator     = "/"
    target_label  = "service_name"
  }
}

pyroscope.ebpf "cpu" {
  targets          = discovery.relabel.profiling.output
  forward_to       = [pyroscope.write.default.receiver]
  sample_rate      = 19
  collect_interval = "15s"
  demangle         = "simplified"
  off_cpu_threshold = 0
}

pyroscope.write "default" {
  endpoint {
    url = "http://pyroscope-distributor.pyroscope.svc:4040"
  }
}
```

**eBPF agent requirements** [D]:
- **Privileges.** Capabilities (`BPF`, `PERFMON`, `SYS_PTRACE`, `CHECKPOINT_RESTORE`, `SYS_RESOURCE`, `DAC_READ_SEARCH`, `SYSLOG`) or `privileged: true`, plus `hostPID: true`. That is a security review item.
- **Runtimes.** HotSpot, Go, Python, Ruby, PHP, Perl, .NET and V8 unwinders are enabled by default.
- **Java detail.** For JVM allocation and lock profiles beyond CPU, add `pyroscope.java` (async-profiler) or the Pyroscope Java agent. eBPF sees CPU only, plus off-CPU with `off_cpu_threshold > 0`.

### 2.5 Query catalogue (copy-paste, each one explained above)

```logql
# Errors by route in the last 5m, filter before parse (L3 §2)
sum by (path) (count_over_time({app="checkout"} |= `"level":"error"` | json | __error__="" | level="error" [5m]))

# p99 latency from logs, per route, with parse errors excluded before unwrap
quantile_over_time(0.99, {app="checkout"} | json | __error__="" | unwrap latency_ms | __error__="" [5m]) by (path)

# Logs of one trace via structured metadata (no stream explosion)
{app="checkout"} | trace_id="4bf92f3577b34da6a3ce929d0e0e4736"

# Bytes per app, for the FinOps table (Folder 08)
sum by (app) (bytes_over_time({namespace="shop"}[1h]))
```

```traceql
// Erroring checkout spans with a slow Postgres descendant (L3 §3)
{ resource.service.name = "checkout" && status = error } >> { span.db.system = "postgresql" && duration > 100ms }

// N+1 query detector
{ span.db.system = "postgresql" } | count() > 5

// Error rate per service, TraceQL metrics
{ status = error } | rate() by (resource.service.name)

// p99 duration of checkout server spans by route
{ resource.service.name = "checkout" && kind = server } | quantile_over_time(duration, .99) by (span.http.route)
```

---

## 3. Failure modes and FinOps debugging

### F1. Loki ingestion rejected: "too many streams"

**Symptom.** 429s from Loki. Collectors back off and log pipelines lag.

**Signature.** Per-tenant stream count is near `max_global_streams_per_user` (default 5,000 per tenant). A new label appeared: an OTLP resource attribute, a `level` label, a request ID.

**Root cause.** Stream cardinality (L3 §1). With OTLP the default index-label list includes `k8s.pod.name` and `service.instance.id`.

**Fix.**
- Move per-instance and per-request attributes to structured metadata.
- Set `otlp_config.resource_attributes.ignore_defaults: true` with an explicit list.
- Raise the stream limit only after the label review.

**Prevention.**
- Track stream counts per label with `logcli series --analyze-labels` or the volume API.
- Review label-set changes in CI for the Alloy/OTel configs.

### F2. "maximum number of series (500) reached for a single query"

**Symptom.** Dashboard panels on log metrics fail intermittently, more often with longer ranges.

**Signature.** A metric query uses `| json` or `| logfmt` without `sum by (...)`, or with a `by` that includes a high-cardinality extracted field.

**Root cause.** Extracted labels join the series identity (L3 §2: 8,927 series against the limit of 500).

**Fix.**
- Wrap the query in `sum by (bounded labels)`.
- Use `| keep` or `| drop` on extracted labels.
- Parse only the fields you need with `| json level="level", path="path"`.

**Prevention.** A dashboard lint that rejects LogQL metric queries without an outer aggregation.

### F3. Log metric alerts fail with "pipeline error"

**Symptom.** Loki ruler alerts error out. The alert never fires during an outage.

**Signature.** The ruler logs `pipeline error: 'JSONParserErr' … Use a label filter to intentionally skip this error`. One container writes non-JSON lines (a stack trace, a third-party library).

**Root cause.** Metric queries fail when any selected line has `__error__` set [D].

**Fix.**
- Add `| __error__=""` after parsers and after `unwrap`.
- Or narrow the selector to JSON-only containers.

**Prevention.** Alert on ruler evaluation failures. Unit-test rules against sample lines that include malformed ones.

### F4. Loki queries time out on "simple" searches

**Symptom.** `{namespace="prod"} |= "OrderNotFound"` over 7 days times out.

**Signature.** Query stats show hundreds of GB scanned. The selector matches thousands of streams. `max_query_bytes_read` is unlimited.

**Root cause.** Line filters scan every chunk of every selected stream. The index narrows only by labels.

**Fix.**
- Narrow by labels first (`app`, `container`).
- Shorten the range.
- Use structured-metadata filters where available.
- Set `max_query_bytes_read` and a `query_timeout` that reflects reality.
- Consider bloom gateways for needle-in-haystack queries (experimental in 3.7 ⚠).

**Prevention.** Publish query-cost guidance. Show the query-stats panel in Explore. Use per-tenant bytes-read limits.

### F5. Tempo traces truncated or "trace too large"

**Symptom.** Batch-job traces show partial span trees. The distributor logs trace-too-large discards.

**Signature.** Traces exceed `global.max_bytes_per_trace` (default 5 MB) or tenants exceed `max_traces_per_user` live traces (default 10,000).

**Root cause.** Unbounded traces: loops that create spans per item, long-running consumers that reuse one trace.

**Fix.**
- At the source, break batch work into per-item traces linked with span links.
- Raise the per-tenant limit for known batch tenants only.
- Cap at the collector with `maximum_trace_size_bytes`.

**Prevention.** Alert on discarded spans by reason. Track a trace-size p99 histogram in the collector.

### F6. TraceQL searches on custom attributes are slow

**Symptom.** `{ span.tenant.id = "acme" }` over 24h takes tens of seconds. The same query on `k8s.namespace.name` is fast.

**Signature.** The attribute is not a dedicated column, so every row group's generic attribute map is scanned.

**Root cause.** The columnar layout: only dedicated columns are cheap predicates (§1.3).

**Fix.**
- Add the attribute to `parquet_dedicated_columns`, keeping the defaults, via overrides.
- New blocks benefit after compaction or rollover.

**Prevention.** Review the top TraceQL predicates monthly from query-frontend logs and promote the top 5–10 to dedicated columns.

### F7. Pyroscope ingestion returns 422 / deadline exceeded after a cost tweak

**Symptom.** Profile clients log `context deadline exceeded`. `/ingest` returns 422.

**Signature.** Someone raised `-segment-writer.segment-duration` to cut PUT costs.

**Root cause.** Ingestion is synchronous: clients wait for the segment flush. A longer segment duration approaches the client timeout [D].

**Fix.** Lower the segment duration, or raise client timeouts with headroom. Increase it in small steps while watching latency.

**Prevention.** Run a cost/latency SLO on profile ingestion, and record the PUT-cost rationale next to the setting.

### F8. Flame-graph "regressions" that are noise

**Symptom.** An engineer files a perf regression from a 15-second flame graph of one pod. It does not reproduce.

**Signature.** The difference is within sampling error. At 19 Hz × 15 s = 285 samples, a 2%→2.5% change has z = 0.84 (L3 §4).

**Root cause.** Profiles are statistical samples, and the default eBPF sampling rate is low.

**Fix.**
- Compare merged profiles across pods and ≥10 minutes.
- Use diff views, and compute the needed core-minutes for the effect size: 12 core-minutes at 19 Hz for 2.0→2.5%.

**Prevention.** Profiling runbook with minimum aggregation windows. CI performance tests use their own longer captures.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "Design Loki labels for 3,000 microservices."</b></summary>

**Initial Prompt.** Teams want to filter by pod, level, user and trace.

**L5 Textbook Answer.** Add those as labels so queries are fast.

**Why L5 Fails at 3 AM or on the Bill.** Labels define streams.
- `user` and `trace` as labels produce millions of streams and 0.4 KiB chunks (L3 §1).
- `level` doubles chunk count.
- Ingestion is rejected at the stream limit (F1).

**L7 Principal Defense.**
- **Index labels** are bounded, query-scoping dimensions: cluster, namespace, app/service, container, maybe environment.
- **Structured metadata** holds pod, instance, trace_id, user_id and level, which filter cheaply after stream selection.
- **OTLP** gets an explicit index-label list (`ignore_defaults`), because the default indexes per pod and instance.
- **Fast "needle" search** comes from narrow selectors plus bytes-read limits (bloom gateways where justified ⚠).
- **Verification.** Model streams × chunk fill before rollout and monitor stream count per label.
</details>

<details><summary><b>Q2 · "Why is this LogQL alert silently not firing?"</b></summary>

**Initial Prompt.** `sum(rate({app="pay"} | json | status >= 500 [5m])) > 1` never fired during an outage.

**L5 Textbook Answer.** The threshold is too high.

**Why L5 Fails at 3 AM or on the Bill.** Two traps.
- **Parse errors.** Any non-JSON line makes the metric query fail with a pipeline error. The ruler logs an error and the alert doesn't evaluate (F3).
- **Failed numeric filters.** If `status` is missing on some lines, the conversion error keeps those lines with `__error__`. They are not filtered out [D].

**L7 Principal Defense.**
- Rewrite as `sum(rate({app="pay"} |= "status" | json | __error__="" | status >= 500 [5m]))`.
- Alert on ruler evaluation failures.
- Test rules against fixtures including malformed lines.
- Prefer application metrics for the SLO (Micrometer) and use log alerts as a backup signal only.
</details>

<details><summary><b>Q3 · "Tempo 3 removed ingesters. What does that change operationally?"</b></summary>

**Initial Prompt.** We're upgrading from Tempo 2.x.

**L5 Textbook Answer.** It's faster and uses Kafka.

**Why L5 Fails at 3 AM or on the Bill.** It misses the new dependency and its failure modes:
- Kafka lag means stale recent traces;
- partition planning;
- RF1 storage, where Kafka retention is the safety net until block-builders flush;
- a migration path that needs dual-running.

**L7 Principal Defense.**
- **Write durability is Kafka's.** Set its replication and retention to cover block-builder outages (consume cycle 5 m by default, plus a recovery margin).
- **Recent-trace queries come from live-stores.** Watch their lag.
- **Blocks are RF1,** so object-storage durability is the only copy afterward. That is fine for S3/GCS.
- **Compaction and retention move to backend-scheduler/workers.**
- **Metrics-generator moves to partition ring mode.**
- **Migration.** I'd run the Kafka path in parallel, validate trace completeness with synthetic traces, then cut over.
</details>

<details><summary><b>Q4 · "TraceQL vs span metrics for RED?"</b></summary>

**Initial Prompt.** TraceQL metrics can do `rate()` now; drop span metrics?

**L5 Textbook Answer.** Yes, one less thing to run.

**Why L5 Fails at 3 AM or on the Bill.**
- TraceQL metrics run at query time over stored spans. With tail sampling they are biased (file 01, F4).
- They are expensive to evaluate for 30-day SLO windows.
- They are not a stable recording-rule substrate.

**L7 Principal Defense.**
- **SLOs and RED** come from metrics generated from all spans or from the app (cheap, stable, long retention).
- **TraceQL metrics** are for exploratory questions you didn't pre-aggregate: "p99 of `/checkout` for tenant X where `db.system=postgresql`". They are also for validating hypotheses before adding a recording rule.
- When a TraceQL metric is needed daily, promote it to a span-metrics dimension or a recording rule, after checking cardinality.
</details>

<details><summary><b>Q5 · "Find N+1 queries across the fleet."</b></summary>

**Initial Prompt.** Database CPU is high and nobody knows why.

**L5 Textbook Answer.** Enable slow query logging on Postgres.

**Why L5 Fails at 3 AM or on the Bill.** N+1 queries are fast individually. Slow-query logs miss them, while the database dies from volume.

**L7 Principal Defense.**
- Run `{ span.db.system = "postgresql" } | count() > 5` (L3 §3 found 156 of 156 seeded cases). Group by `rootName` to rank endpoints.
- Confirm with a TraceQL metric `| rate() by (resource.service.name)` on DB spans.
- Correlate with profiles (ORM hot paths) and fix in code with batching or joins.
- Prevent regressions with a span-count-per-request histogram from span metrics, plus a CI test asserting query counts per endpoint.
</details>

<details><summary><b>Q6 · "Continuous profiling: what sampling rate and what overhead?"</b></summary>

**Initial Prompt.** Security approved eBPF; product wants 100 Hz for precision.

**L5 Textbook Answer.** Higher rate means more precision; use 100 Hz.

**Why L5 Fails at 3 AM or on the Bill.** Precision comes from **samples aggregated**, not rate alone.
- 5× the rate costs 5× the agent CPU, ingest and storage everywhere.
- The same precision is reachable by merging more pods or minutes.
- Most questions are fleet-level.

**L7 Principal Defense.**
- Keep the default **19 Hz**.
- Compute required samples from the effect size: 13.8k per side for 2.0→2.5%, about 12 core-minutes (L3 §4).
- On a 100-core service that is 7 seconds of fleet time, so the default suffices.
- For single-pod or short-lived jobs, raise the rate temporarily via a per-target override, or use language agents with allocation and lock profiles.
- Budget overhead under 1% CPU and verify with the agent's own metrics.
</details>

<details><summary><b>Q7 · "Why did our Loki bill double without more logs?"</b></summary>

**Initial Prompt.** Bytes ingested are flat; S3 requests and costs doubled.

**L5 Textbook Answer.** S3 prices changed.

**Why L5 Fails at 3 AM or on the Bill.** Request costs scale with **objects**, and objects scale with streams and chunk fill. A label change can double chunks at constant bytes (L3 §1: adding `level` 131k → 278k chunks/day, 42% under-filled).

**L7 Principal Defense.**
- Diff the label sets and stream counts before and after.
- Check average chunk fill (`chunk_target_size` utilisation) and flush reasons (idle vs age vs full).
- Revert the label to structured metadata.
- Watch the PUT/GET rates in bucket metrics.
- Add a FinOps guardrail: alert when average flushed-chunk size drops below 25% of target for a tenant.
</details>

<details><summary><b>Q8 · "Pyroscope v2 claims no local disks. What's the catch?"</b></summary>

**Initial Prompt.** We want stateless everything.

**L5 Textbook Answer.** No catch; it writes straight to S3.

**Why L5 Fails at 3 AM or on the Bill.**
- Synchronous ingestion couples client latency to object-storage latency and segment duration (F7).
- The metastore (Raft) *is* stateful and must be run like a consensus system.
- Small segments mean many PUTs; compaction is essential.

**L7 Principal Defense.**
- **Segments vs latency.** Segment duration balances PUT cost against client latency and memory. Keep it well below client timeouts.
- **Metastore.** Run 3 replicas across zones, back it up, alert on leader elections and on Raft log growth.
- **Compaction.** Watch compaction-worker lag, because queries read many small segments until compaction catches up.
- **Costs.** One object per shard per flush is the design's PUT minimisation: count shards × flushes/s to estimate requests.
- **Upside.** The heaviest queries can't hurt ingestion, and query-backends scale out instantly.
</details>

<details><summary><b>Q9 · "Loki 4 is in RC. Do we wait?"</b></summary>

**Initial Prompt.** Our Loki 3 cluster struggles with query cost.

**L5 Textbook Answer.** Upgrade to 4 as soon as it's out; it's columnar.

**Why L5 Fails at 3 AM or on the Bill.**
- Release candidates are not production.
- Loki 4 changes the write path (Kafka), storage format (DataObjects) and query engine, which is a migration, not an upgrade.
- Most query-cost problems are label and query design, which a new engine won't fix.

**L7 Principal Defense.**
- Fix the fundamentals on 3.7 now: labels, structured metadata, bytes-read limits, query hygiene. Those carry over.
- Stand up Loki 4 in a shadow environment with mirrored traffic once it is GA.
- Measure bytes scanned and p99 latency on our top 20 queries.
- Plan Kafka capacity.
- Migrate tenant by tenant with dual-write.
- Pin versions and re-verify the configuration keys at the GA tag ⚠.
</details>

---

## 5. Invariants checklist

- [ ] Loki index labels are a bounded, reviewed list; OTLP `ignore_defaults` is used with an explicit list; per-request and per-instance IDs live in structured metadata.
- [ ] Every LogQL metric query has an outer aggregation and `| __error__=""` after parsers and `unwrap`; ruler evaluation failures page.
- [ ] `max_query_bytes_read` and query timeouts are set per tenant; selectors narrow by labels before line filters.
- [ ] Average flushed-chunk fill is monitored; stream count per tenant is alerted below `max_global_streams_per_user`.
- [ ] Tempo: Kafka retention covers block-builder recovery; live-store lag is alerted; dedicated columns include the top TraceQL predicates and keep the defaults; trace-size limits are set deliberately.
- [ ] RED/SLO metrics never come from post-sampling data; TraceQL metrics are exploratory.
- [ ] Pyroscope: the metastore runs as a 3-replica Raft group with alerts; segment duration stays well below client timeouts; profiles are compared merged and diffed, never single-pod snapshots.
- [ ] The eBPF agent's privileges are reviewed and documented; language agents cover allocation and lock profiles where needed.

---

## 6. References

- Loki configuration reference (v3.7.9 source): <https://github.com/grafana/loki/blob/v3.7.9/docs/sources/shared/configuration.md>
- LogQL log queries (label filters, parsers, `__error__`): <https://grafana.com/docs/loki/latest/query/log_queries/>
- LogQL metric queries: <https://grafana.com/docs/loki/latest/query/metric_queries/>
- Loki pipeline error source: <https://github.com/grafana/loki/blob/v3.7.9/pkg/logqlmodel/error.go>
- Loki structured metadata: <https://grafana.com/docs/loki/latest/get-started/labels/structured-metadata/>
- Loki releases (v4.0.0-rc.2 prerelease): <https://github.com/grafana/loki/releases>
- Tempo configuration manifest (v3.1.1): <https://github.com/grafana/tempo/blob/v3.1.1/docs/sources/tempo/configuration/manifest.md>
- TraceQL: <https://grafana.com/docs/tempo/latest/traceql/>
- Pyroscope v2 architecture (v2.4.3 source): <https://github.com/grafana/pyroscope/blob/v2.4.3/docs/sources/reference-pyroscope-v2-architecture/about-pyroscope-v2-architecture/index.md>
- Pyroscope segment-writer: <https://github.com/grafana/pyroscope/blob/v2.4.3/docs/sources/reference-pyroscope-v2-architecture/components/segment-writer.md>
- Alloy `pyroscope.ebpf`: <https://grafana.com/docs/alloy/latest/reference/components/pyroscope/pyroscope.ebpf/>
- Alloy `loki.process`: <https://grafana.com/docs/alloy/latest/reference/components/loki/loki.process/>
- OpenTelemetry eBPF profiler: <https://github.com/open-telemetry/opentelemetry-ebpf-profiler>
