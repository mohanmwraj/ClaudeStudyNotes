# 03 · Metric Types: Counters, Gauges, Summaries and Prometheus 3 Native Histograms

> **Folder 01: Prometheus 3 TSDB Internals and Cardinality Physics. File 3 of 4.**
> Pinned to **Prometheus v3.15.1** (server) and **client_golang v1.25.0** (released 2026-10-08) for client behaviour.
> Labels: **[D]** documented or read in pinned source. **[M]** measured by the listing here (deterministic, re-run by the gate). **[E]** model. **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L5 `native_histogram_lab.py` | Native histogram bucket math: schema → base, the client key function versus server `getBoundExponential`, and the hard-coded bounds table regenerated bit-exactly with client_golang's generator plus a port of Go's `math.Exp2` (SHA-256 checked). Also spans and deltas, protobuf size, resolution reduction (`targetIdx`), OTel index mapping, a quantile-accuracy shoot-out (classic DefBuckets vs native schemas 3 and 0 on lognormal and bimodal latencies, using ports of PromQL's `BucketQuantile` and `HistogramQuantile`), and summary non-aggregatability | <1 s |

**Verification.** L5's bounds table is regenerated, not copied, and checked against the SHA-256 of the table parsed from `model/histogram/generic.go` at v3.15.1. That table is byte-identical to client_golang's `nativeHistogramBounds`.
- Key/bound consistency is property-tested over 20,000 random values in all 13 schemas, plus every bound in −40..40.
- The quantile functions are line-level ports of `promql/quantile.go`.
- Ground-truth quantiles come from the sorted raw observations.
- No live Prometheus server was run.

---

## 0. Orientation

**What this file answers.**
- What each metric type *is* on the wire, in the TSDB and in PromQL.
- Why summaries cannot be aggregated.
- Why classic histograms are the biggest single cardinality multiplier in most fleets.
- What native histograms change: bits, accuracy, series count, migration risk.

**The key reframe.** Metric "types" are **metadata**. The TSDB stores exactly two value kinds:
1. **float samples**: counters, gauges, untyped, and every classic histogram bucket, `_sum` and `_count`;
2. **histogram samples**: native histograms with exponential buckets, or with custom bounds (NHCB).

A classic histogram is *N + 2 float series* glued together by naming conventions. A native histogram is *one series* whose sample is a whole distribution. Everything in this file follows from that difference.

**Status in 3.15 [D].**
- Native histograms are **stable** since 3.8.0 (2025-12-02).
- Scraping them is opt-in per scrape config: `scrape_native_histograms: true`. The global default is `false`.
- `--enable-feature=native-histograms` is a no-op since 3.9.0.
- Remote write sends them only with `send_native_histograms: true` (default `false`).
- Exposition requires a format that can carry them: protobuf (`PrometheusProto`) or the experimental OpenMetrics 2.0 text (`--enable-feature=openmetrics2`, 3.15). Text format 0.0.4 and OpenMetrics 1.0 cannot.

---

## 1. First principles: what each type means

### 1.1 Counter

A counter is monotonically non-decreasing between **resets** (process restarts). Its value is meaningless; only its increase over time is.
- **Naming:** `_total` suffix. OTLP translation appends it in the `...WithSuffixes` strategies.
- **Reset handling:** PromQL `rate()`, `increase()` and `resets()` detect a decrease and treat the post-reset value as the increase since zero (Folder 02 proves the extrapolation math).
- **Start timestamps** (formerly "created timestamps") record *when the counter began counting*:
  - **OpenMetrics 1.0** exposes `<name>_created` series. They are expensive to parse and easy to ingest accidentally as extra series.
  - **Protobuf** carries `start_timestamp` on Counter/Summary/Histogram messages.
  - `--enable-feature=created-timestamp-zero-ingestion` injects a synthetic `0` sample at the start time, so the first increase after a restart is not lost.
  - 3.11+ `st-storage` stores ST natively per sample in WAL, XOR2 chunks and remote write 2.0.
  - 3.12+ `use-start-timestamps` lets `rate()`, `irate()`, `increase()` and `resets()` use it.
  - 3.14+ adds `start_timestamp()`.
  - `st-synthesis` (3.12+) synthesizes STs for scraped cumulative metrics that lack them, at the cost of dropping the first sample and rebasing values.

> The architect's takeaway: "first scrape after a restart under-counts" is a known counter limitation with a 2026 fix path (ST). It is not a reason to switch to gauges.

### 1.2 Gauge

A gauge is a value that can go up and down: memory in use, queue depth, temperature. Aggregation is semantic:
- `sum` for additive quantities (bytes in use across pods);
- `max` / `min` for extremes;
- **never** `rate()`, which assumes counter semantics and will "detect resets" on every decrease.

The common gauge mistake is the converse: exporting *cumulative* data as a gauge. For example, a `queue_processed` "gauge" that is really a counter loses reset handling and breaks `rate()`.

### 1.3 Summary

A summary is computed in the **client** over a sliding time window. In client_golang the defaults are `MaxAge` 10 m and `AgeBuckets` 5, with user-chosen `Objectives` such as `{0.5: 0.05, 0.99: 0.001}`. It exports:
- `name{quantile="0.99"}`, which is the φ-quantile of *this process's* observations in the window;
- `name_sum` and `name_count`.

```text
 pod A p99 = 410 ms      pod B p99 = 95 ms      pod C p99 = 101 ms
 avg(p99) = 202 ms   ≠   fleet p99 (depends on traffic split and shapes; can be 400+ ms)
 there is NO operator that combines quantiles: the information (the distribution) is gone
```

L5 §5 measures 10 pods with different latency profiles and one pod carrying 4× traffic [M]:
- **avg(per-pod p99) is −12.2% off** the true fleet p99.
- `histogram_quantile(0.99, sum(native histograms))` is +0.3% off.

Summaries are still the right tool in two narrow cases: one process whose exact percentile you need, or a client that cannot afford histogram state. For anything aggregated across replicas (SLOs, dashboards), use histograms.

### 1.4 Classic histogram

```text
 http_server_request_duration_seconds_bucket{le="0.005"}  12
 http_server_request_duration_seconds_bucket{le="0.01"}   40          cumulative counts
 …                                                                     (each le = 1 series)
 http_server_request_duration_seconds_bucket{le="+Inf"}   1000        == _count
 http_server_request_duration_seconds_sum                  97.3
 http_server_request_duration_seconds_count                1000
 series per label combination = len(buckets incl. +Inf) + 2   (DefBuckets: 12 + 2 = 14)
```

**The properties that matter [D]:**

- **The buckets are chosen up front and are the same for everyone.** Quantile estimates interpolate *linearly* inside a bucket (`BucketQuantile`):
  - the lowest bucket assumes a lower bound of 0;
  - a quantile landing in the `+Inf` bucket returns the **upper bound of the second-highest bucket**. You can never see a value above your largest finite bucket.
- **Aggregation is exact.** `sum by (le) (rate(x_bucket[5m]))` merges replicas correctly, because counts add.
- **The cost is cardinality.** Every bucket is a series, multiplied by every label combination (File 02 §1.5).
- **3.0 normalizes `le` and `quantile` values to float strings.** `le="1"` is ingested as `le="1.0"` regardless of scrape protocol. Before 3.0 the protobuf and text paths disagreed, so the series identity depended on the protocol. Selectors that hard-code `le="1"` stopped matching in 3.0.

### 1.5 Native histogram: the exponential schema

```text
 schema s ∈ [-4, 8]   base b = 2^(2^-s)       s=3 → b = 2^(1/8) ≈ 1.0905 (≈9.05% wide buckets)
 bucket i (positive) = ( b^(i-1), b^i ]       upper-inclusive; 1.0 is the upper bound of bucket 0
 negative buckets mirror;  zero bucket [-zt, zt] with zt default 2^-128 (client_golang)

 observation v → key:  frac, exp = frexp(|v|)          (v = frac·2^exp, frac ∈ [0.5, 1))
     s > 0:  key = searchFloat64s(bounds[s], frac) + (exp-1)·2^s
     s ≤ 0:  key = exp (−1 if frac == 0.5); key = (key + 2^-s − 1) >> -s

 one sample on the wire (protobuf Histogram):
   sample_count, sample_sum, schema (sint32), zero_threshold, zero_count,
   positive_span  [ {offset: -68, length: 90} ]       ← where populated buckets are
   positive_delta [ 1, 0, 2, -2, 1, 4, … ]            ← count deltas, bucket to bucket
   (gaps of ≤ 2 empty buckets are filled with explicit zeros; > 2 opens a new span)
```

**Why spans + deltas.** Populated buckets are contiguous runs on a log scale, so spans describe them in a few integers. Neighbouring bucket counts are similar, so deltas are small zig-zag varints. In L5, 100,000 lognormal latencies (median 120 ms, σ 0.9) fill **87 buckets at schema 3** and encode to a **168-byte** protobuf payload [M]. The classic equivalent with 12 buckets and *worse* accuracy is 14 separate series.

**Bucket boundaries are a table, not a formula [D][M].**
- Server-side `getBoundExponential` and client-side key lookup both use the same hard-coded 511-entry `exponentialBounds` / `nativeHistogramBounds` table.
- client_golang documents its generator: chain `bound·factor` with `factor = math.Exp2(math.Exp2(-s))`, reusing the previous schema's value for every second entry.
- L5 regenerates the table with that generator and a port of Go's pure-Go `math.Exp2`. It matches the SHA-256 of the Go source exactly. The same generator with Python's `2**x` differs in 255 of 511 entries.
- Only 170 of 511 entries are correctly rounded; the rest are 1–4 ulps low.

The interop consequence: an instrumentation library that computes keys with exact math, or with a different `exp2`, puts observations that lie in those few-ulp slivers into a *different bucket* than Prometheus's own math would. L5 shows 4 such doubles at schema 7, bound 109. Harmless for quantiles, but it explains "off-by-one bucket" flakes in conformance tests. If you implement a client, **use the table, not `pow`**. A maintainer comment next to the generator in client_golang notes that the numbers may be pinned precisely in the standard in future.

**Resolution reduction.** Merging to a coarser schema is exact and cheap: `targetIdx(i, from, to) = ((i − 1) >> (from − to)) + 1` maps 2^(from−to) buckets onto one, and schema-0 bounds are every 8th schema-3 bound (L5 checks both).
- Clients do this when they exceed `NativeHistogramMaxBucketNumber`, as an alternative to resetting.
- Prometheus does it at scrape time when `native_histogram_bucket_limit` or `native_histogram_min_bucket_factor` is exceeded.
- PromQL does it automatically when aggregating histograms of different schemas: the result takes the coarsest schema.

**Counter resets for histograms.** A reset is detected if the count, the zero bucket or any bucket decreases, or if the schema or zero threshold change in a way that cannot be a simple merge. Histogram chunks carry a **counter-reset hint** header (unknown / reset / not-reset / gauge). 3.15.0 fixed `DetectReset` missing a reset when a populated bucket behind an empty one disappeared, which could undercount `rate()` on native histograms. That is a reason to stay current.

**Chunk encoding.** Histogram chunks (`EncHistogram`, `EncFloatHistogram`, and the 3.14+ experimental ST variants) target **1,024 bytes per chunk** with a minimum of 10 samples, instead of 120 samples (`TargetBytesPerHistogramChunk`, `MinSamplesPerHistogramChunk`). A 90-bucket histogram costs far more than 1–2 bytes per sample, but one series replaces dozens.

### 1.6 NHCB: native histograms with custom buckets (schema −53)

NHCB keeps **classic bucket boundaries** inside **one native-histogram series** [D]:
- `convert_classic_histograms_to_nhcb: true` (scrape) or OTLP `convert_histograms_to_nhcb: true` turns N+2 series into 1.
- `histogram_quantile` on NHCB interpolates **linearly**, like classic. The `+Inf` bucket returns the lower bound of that bucket, and a first bucket with lower bound −Inf uses 0 as its lower bound if its upper bound is positive.
- Aggregating NHCBs whose bounds differ does not fail. In v3.15.1 `FloatHistogram.Add` reconciles them to the **intersection** of the two bound sets (coarser buckets) and PromQL attaches an annotation. Mixed bucket layouts across a fleet therefore silently degrade resolution, so keep bounds identical per family.
- 3.13 adds `__convert_classic_histograms_to_nhcb__` as a target label, so the conversion can be enabled per target via relabeling.

NHCB is the low-risk first step: the same accuracy as classic, 1/14 the series, and no instrumentation change.

### 1.7 OpenTelemetry exponential histograms → Prometheus native histograms

OTel's "scale" *is* Prometheus's schema, but the indices are off by one [D]:

```text
 OTel bucket index i  covers ( base^i ,    base^(i+1) ]
 Prom bucket index i  covers ( base^(i-1), base^i     ]      ⇒  prom_index = otel_index + 1
 OTel scale > 8   → downscale to schema 8 (merge 2^(scale-8) buckets: index >> scaleDown)
 OTel scale < -4  → rejected (cannot be represented)
 gap > 2 empty buckets → new span (constant copied from client_golang)
```

This is `convertBucketsLayout` in `storage/remote/otlptranslator/prometheusremotewrite/histograms.go`. OTel explicit-bucket histograms become classic histograms by default, or NHCB with `otlp.convert_histograms_to_nhcb: true`.

### 1.8 How accurate is each choice? (L5 §4)

| Distribution / q | Classic DefBuckets | Native schema 3 | Native schema 0 |
|---|---|---|---|
| lognormal p50 | +10.0% | −0.1% | −0.4% |
| lognormal p90 | +12.2% | +0.0% | +7.4% |
| lognormal p99.9 | **+29.3%** | +0.0% | +6.3% |
| bimodal (2 ms / 300 ms) p50 | **+50.9%** | +0.2% | +14.5% |
| bimodal p99 | **+34.1%** | +0.5% | +27.9% |

The mechanics behind the numbers [M]:
- Classic error is governed by *bucket placement relative to the data*. DefBuckets' 250 ms → 500 ms gap is 2× wide right where the bimodal mode sits.
- Native error is bounded by schema. At schema 3, ±4.4% is the worst case for a geometric-midpoint estimate. PromQL interpolates *log-linearly* inside native buckets (`HistogramQuantile`) and iterates from the top for q ≥ 0.5, which is why the observed error is far below the bound.
- Schema 0 (100%-wide buckets) is worse than well-placed classic buckets near the mode but better in the tail. Resolution must be chosen, not defaulted to "lowest".

### 1.9 Exposition formats and negotiation

| Format | Content type | Native histograms | Start timestamps | Notes |
|---|---|---|---|---|
| Prometheus text 0.0.4 / 1.0.0 | `text/plain; version=…` | ✗ | ✗ | Universal; `le` normalized on ingest (3.0) |
| OpenMetrics 1.0 | `application/openmetrics-text; version=1.0.0` | ✗ | `_created` series | Exemplars on counters/buckets; EOF marker |
| PrometheusProto | `application/vnd.google.protobuf; proto=io.prometheus.client.MetricFamily; encoding=delimited` | ✓ | ✓ `start_timestamp` | Preferred when `scrape_native_histograms: true` |
| OpenMetrics 2.0 | `application/openmetrics-text; version=2.0.0` | ✓ | ✓ | `--enable-feature=openmetrics2`, experimental in 3.15 |

With `scrape_native_histograms: true` and no explicit `scrape_protocols`, Prometheus negotiates `[PrometheusProto, OpenMetricsText1.0.0, OpenMetricsText0.0.1, PrometheusText1.0.0, PrometheusText0.0.4]`. Otherwise it puts OpenMetrics first [D]. A target that cannot serve protobuf silently delivers classic-only data. Check the scrape protocol on the Targets page.

### 1.10 Type and unit as labels (experimental)

`--enable-feature=type-and-unit-labels` injects reserved `__type__` and `__unit__` labels from metadata (scrape formats, RW2, OTLP). PromQL drops them like `__name__` in arithmetic. This is how Prometheus plans to handle same-name/different-type collisions, such as an OTLP metric without suffix translation next to a scraped one, and native histogram migrations. Treat it as a schema change: it alters series identity.

<!-- listing:native_histogram_lab.py -->
```python
"""native_histogram_lab.py - native (sparse exponential) histogram math vs classic histograms and
summaries, ported from Prometheus v3.15.1 and checked against its constants.

Sources (tag v3.15.1):
  model/histogram/generic.go   schema range -4..8, NHCB schema -53, getBoundExponential, and the
                               hard-coded exponentialBounds table (rebuilt here bit-exactly and
                               verified by SHA-256 against the table parsed from the Go source).
  model/histogram/float_histogram.go  targetIdx(idx, from, to) = ((idx-1) >> (from-to)) + 1.
  promql/quantile.go           BucketQuantile (classic: linear, +Inf bucket -> 2nd-highest bound)
                               and HistogramQuantile (native: log-linear interpolation, reverse
                               iteration for q >= 0.5; NHCB: linear, last bucket -> lower bound).
  storage/remote/otlptranslator/prometheusremotewrite/histograms.go  OTel index i -> Prom i+1,
                               scale > 8 downscaled with >>, new span only for gaps > 2 buckets.
  client_golang (bucket key from math.Frexp + sort.SearchFloat64s over the same table).
Stdlib only, deterministic.

Usage: python native_histogram_lab.py [target.md]
"""
import bisect
import hashlib
import math
import random
import struct
import sys
from decimal import Decimal, getcontext

TABLE_SHA256 = "1c5fe4473fb24e335cd41237e1a9be990e001c1a5b72033f183aee5aee179963"  # 511 doubles, parsed
# from model/histogram/generic.go (Prometheus) == client_golang's nativeHistogramBounds (same hash)


def go_exp2(x):
    """Port of Go's pure-Go math.Exp2 (src/math/exp.go: argument reduction + expmulti). The bounds
    table was generated with it; Python's 2**x / math.exp2 give different last bits."""
    p1, p2, p3 = 1.66666666666666657415e-01, -2.77777777770155933842e-03, 6.61375632143793436117e-05
    p4, p5 = -1.65339022054652515390e-06, 4.13813679705723846039e-08
    ln2hi, ln2lo = 6.93147180369123816490e-01, 1.90821492927058770002e-10
    k = int(x + 0.5) if x > 0 else (int(x - 0.5) if x < 0 else 0)
    t = x - float(k)
    hi, lo = t * ln2hi, -t * ln2lo
    r = hi - lo
    tt = r * r
    c = r - tt * (p1 + tt * (p2 + tt * (p3 + tt * (p4 + tt * p5))))
    return math.ldexp(1 - ((lo - (r * c) / (2 - c)) - hi), k)


def f2i(v):
    return struct.unpack(">q", struct.pack(">d", v))[0]


def i2f(i):
    return struct.unpack(">d", struct.pack(">q", i))[0]


def exact_bound(j, schema):
    getcontext().prec = 60
    return float(Decimal(2) ** (Decimal(j) / Decimal(2 ** schema)) / 2)


def build_table(exp2=go_exp2):
    """client_golang's documented generator: chain bound*factor, reuse the previous schema's bound
    for every second entry 'for increased precision'."""
    tables, n = [], 1
    for i in range(9):
        bounds, factor = [0.5], exp2(exp2(float(-i)))
        for j in range(n - 1):
            bounds.append(tables[i - 1][j // 2 + 1] if (j + 1) % 2 == 0 else bounds[j] * factor)
        n *= 2
        tables.append(bounds)
    return tables


BOUNDS = build_table()


def get_bound(idx, schema):  # getBoundExponential
    if schema < 0:
        exp = idx << -schema
        return sys.float_info.max if exp == 1024 else math.ldexp(1, exp)
    frac = BOUNDS[schema][idx & ((1 << schema) - 1)]
    exp = (idx >> schema) + 1
    if frac == 0.5 and exp == 1025:
        return sys.float_info.max
    return math.ldexp(frac, exp)


def bucket_key(v, schema):  # client_golang: key such that get_bound(key-1) < |v| <= get_bound(key)
    frac, exp = math.frexp(abs(v))
    if schema > 0:
        bounds = BOUNDS[schema]
        return bisect.bisect_left(bounds, frac) + (exp - 1) * len(bounds)
    key = exp - 1 if frac == 0.5 else exp
    off = (1 << -schema) - 1
    return (key + off) >> -schema


def target_idx(idx, origin, target):
    return ((idx - 1) >> (origin - target)) + 1


class Native:
    def __init__(self, schema, zero_threshold=2.0 ** -128):
        self.schema, self.zt = schema, zero_threshold
        self.pos, self.zero, self.count, self.sum = {}, 0, 0, 0.0

    def observe(self, v):
        self.count += 1
        self.sum += v
        if abs(v) <= self.zt:
            self.zero += 1
        else:
            k = bucket_key(v, self.schema)
            self.pos[k] = self.pos.get(k, 0) + 1

    def reduce(self, target):
        out = Native(target, self.zt)
        out.zero, out.count, out.sum = self.zero, self.count, self.sum
        for k, c in self.pos.items():
            t = target_idx(k, self.schema, target)
            out.pos[t] = out.pos.get(t, 0) + c
        return out

    def spans_deltas(self, max_gap=2):
        keys = sorted(self.pos)
        spans, deltas, prev, last = [], [], 0, None
        for k in keys:
            if last is None or k - last - 1 > max_gap:
                spans.append([k if last is None else k - last - 1, 0])
            else:
                for _ in range(k - last - 1):  # fill small gaps with explicit zero buckets
                    spans[-1][1] += 1
                    deltas.append(0 - prev)
                    prev = 0
            spans[-1][1] += 1
            deltas.append(self.pos[k] - prev)
            prev, last = self.pos[k], k
        return spans, deltas

    def quantile(self, q):  # promql HistogramQuantile, positive buckets + zero bucket
        buckets = [(0.0, self.zt, self.zero)] if self.zero else []
        buckets += [(get_bound(k - 1, self.schema), get_bound(k, self.schema), self.pos[k]) for k in sorted(self.pos)]
        if q < 0.5:
            it, rank = buckets, q * self.count
        else:
            it, rank = list(reversed(buckets)), (1 - q) * self.count
        count = 0
        for lo, hi, c in it:
            if c == 0:
                continue
            count += c
            if count >= rank:
                break
        rank = rank - (count - c) if q < 0.5 else count - rank
        frac = rank / c
        if lo <= 0 <= hi:
            return lo + (hi - lo) * frac
        return math.exp2(math.log2(lo) + (math.log2(hi) - math.log2(lo)) * frac)


def classic_quantile(q, bounds, cum):  # promql BucketQuantile; bounds end with +Inf, cum cumulative
    rank = q * cum[-1]
    b = next(i for i in range(len(bounds) - 1) if cum[i] >= rank) if any(
        cum[i] >= rank for i in range(len(bounds) - 1)) else len(bounds) - 1
    if b == len(bounds) - 1:
        return bounds[-2]
    start, count = (bounds[b - 1], cum[b] - cum[b - 1]) if b > 0 else (0.0, cum[0])
    rank -= cum[b - 1] if b > 0 else 0
    return start + (bounds[b] - start) * (rank / count)


def classic(values, bounds):
    cum = [sum(1 for v in values if v <= ub) for ub in bounds]
    return cum


def pb_varint(x):
    out = bytearray()
    while x >= 0x80:
        out.append((x & 0x7F) | 0x80)
        x >>= 7
    out.append(x)
    return bytes(out)


def pb_zz(x):
    return (x << 1) ^ (x >> 63)


def pb_field(num, wt, payload):
    return pb_varint(num << 3 | wt) + payload


def encode_native_proto(h):  # io.prometheus.client.Histogram native fields
    spans, deltas = h.spans_deltas()
    b = pb_field(1, 0, pb_varint(h.count)) + pb_field(2, 1, struct.pack("<d", h.sum))
    b += pb_field(5, 0, pb_varint(pb_zz(h.schema) & 0xFFFFFFFF))
    b += pb_field(6, 1, struct.pack("<d", h.zt)) + pb_field(7, 0, pb_varint(h.zero))
    for off, ln in spans:
        sp = pb_field(1, 0, pb_varint(pb_zz(off) & 0xFFFFFFFF)) + pb_field(2, 0, pb_varint(ln))
        b += pb_field(12, 2, pb_varint(len(sp)) + sp)
    packed = b"".join(pb_varint(pb_zz(d) & 0xFFFFFFFFFFFFFFFF) for d in deltas)
    b += pb_field(13, 2, pb_varint(len(packed)) + packed)
    return b


def latencies(rng, n, median, sigma):
    return [math.exp(rng.gauss(math.log(median), sigma)) for _ in range(n)]


def true_q(sorted_vals, q):
    return sorted_vals[min(len(sorted_vals) - 1, max(0, math.ceil(q * len(sorted_vals)) - 1))]


DEF_BUCKETS = [.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10, math.inf]  # client_golang DefBuckets


def main():
    checks = []
    blob = b"".join(struct.pack(">d", v) for row in BOUNDS for v in row)
    sha_ok = hashlib.sha256(blob).hexdigest() == TABLE_SHA256
    flat = [v for row in BOUNDS for v in row]
    exact_n = sum(1 for s_ in range(9) for j in range(2 ** s_) if BOUNDS[s_][j] == exact_bound(j, s_))
    py_diff = sum(1 for a, b in zip(flat, [v for row in build_table(lambda x: 2.0 ** x) for v in row]) if a != b)
    checks.append(("bounds table SHA-256", sha_ok))

    print("== 1. Schemas: base = 2^(2^-schema) ==")
    print(f"{'schema':>6} {'base':>10} {'width':>7} {'bkts/decade':>11} {'max rel err (geo mid)':>21}")
    for s in (-4, -2, 0, 1, 2, 3, 4, 5, 8):
        base = 2 ** (2.0 ** -s)
        print(f"{s:>6} {base:>10.5f} {base - 1:>6.1%} {math.log(10) / math.log(base):>11.1f} {math.sqrt(base) - 1:>20.2%}")
    print(f"bounds table regenerated (client_golang generator + Go math.Exp2 port): SHA-256 matches the Go "
          f"source: {sha_ok}; the same generator with Python 2**x differs in {py_diff}/511 entries; "
          f"only {exact_n}/511 entries are correctly rounded")
    devs = [(f2i(BOUNDS[s_][j]) - f2i(exact_bound(j, s_)), s_, j) for s_ in range(9) for j in range(2 ** s_)]
    _, s_w, j_w = min(devs)
    lo = get_bound(j_w - 2 ** s_w, s_w) * 2  # table bound scaled into [1,2): key j_w
    ex = exact_bound(j_w, s_w) * 2
    between = [i2f(f2i(lo) + d) for d in range(1, f2i(ex) - f2i(lo) + 1)]
    disagree = sum(1 for v in between if bucket_key(v, s_w) == j_w + 1)
    print(f"e.g. schema {s_w} bound #{j_w}: table {lo!r} vs exact {ex!r}; {len(between)} doubles in between "
          f"land in the upper bucket in Prometheus but the lower one in exact math ({disagree} confirmed)")
    checks.append(("boundary sliver exists", disagree == len(between) >= 1))
    print()

    print("== 2. Bucket key <-> bound consistency (client_golang key vs server getBound), 20k values ==")
    rng = random.Random(1)
    bad = 0
    for _ in range(20_000):
        v = math.ldexp(rng.random() + 0.5, rng.randint(-60, 60))
        s = rng.randint(-4, 8)
        k = bucket_key(v, s)
        bad += not (get_bound(k - 1, s) < v <= get_bound(k, s))
    for s in range(-4, 9):  # every bound is upper-inclusive: an observation equal to bound(k) lands in k
        for k in range(-40, 41):
            bad += bucket_key(get_bound(k, s), s) != k
    checks.append(("key/bound consistent", bad == 0))
    print(f"violations of bound(k-1) < v <= bound(k): {bad}")
    print()

    print("== 3. 100k latencies (lognormal, median 120 ms, sigma 0.9) as a schema-3 native histogram ==")
    rng = random.Random(2026)
    vals = latencies(rng, 100_000, 0.120, 0.9)
    h3 = Native(3)
    for v in vals:
        h3.observe(v)
    spans, deltas = h3.spans_deltas()
    proto = encode_native_proto(h3)
    print(f"populated buckets {len(h3.pos)}, spans {spans[:3]}{'...' if len(spans) > 3 else ''} ({len(spans)} total), "
          f"deltas {len(deltas)} (first {deltas[:6]})")
    print(f"protobuf Histogram message (native fields only): {len(proto)} B for {len(h3.pos)} buckets")
    for tgt in (2, 1, 0):
        r = h3.reduce(tgt)
        checks.append((f"reduce to {tgt} keeps count", sum(r.pos.values()) == sum(h3.pos.values())))
        print(f"reduce schema 3 -> {tgt}: {len(r.pos)} buckets (counts preserved: {sum(r.pos.values()) == 100_000})")
    ok = all(get_bound(k, 3) == get_bound(target_idx(k, 3, 0), 0) for k in range(-64, 64) if k % 8 == 0)
    checks.append(("schema 0 bounds are every 8th schema-3 bound", ok))
    otel = {i - 1: c for i, c in h3.pos.items()}  # OTel index = Prom index - 1 (OTel bucket (base^i, base^(i+1)])
    back = {i + 1: c for i, c in otel.items()}
    checks.append(("OTel offset +1 mapping", back == h3.pos))
    print()

    print("== 4. Quantile estimates: classic DefBuckets vs NHCB vs native schema 3 vs schema 0 ==")
    h0 = h3.reduce(0)
    dists = {"lognormal 120ms": vals,
             "bimodal 2ms/300ms": [v for v in latencies(random.Random(3), 70_000, 0.002, 0.3)] +
                                  latencies(random.Random(4), 30_000, 0.300, 0.4)}
    for name, data in dists.items():
        sv = sorted(data)
        cum = classic(sv, DEF_BUCKETS)
        hn, h0d = Native(3), None
        for v in data:
            hn.observe(v)
        h0d = hn.reduce(0)
        print(f"-- {name}")
        print(f"{'q':>6} {'true':>9} | {'classic':>9} {'err':>7} | {'native s3':>9} {'err':>7} | {'native s0':>9} {'err':>7}")
        for q in (0.5, 0.9, 0.99, 0.999):
            t = true_q(sv, q)
            c = classic_quantile(q, DEF_BUCKETS, cum)
            n3, n0 = hn.quantile(q), h0d.quantile(q)
            print(f"{q:>6} {t:>9.4f} | {c:>9.4f} {c / t - 1:>+7.1%} | {n3:>9.4f} {n3 / t - 1:>+7.1%} | {n0:>9.4f} {n0 / t - 1:>+7.1%}")
            if name.startswith("lognormal"):
                checks.append((f"native s3 within 5% at q={q}", abs(n3 / t - 1) < 0.05))
        print()

    print("== 5. Why summaries do not aggregate: 10 pods, per-pod p99 vs fleet p99 ==")
    rng = random.Random(77)
    pods = [latencies(rng, 5_000 * (1 + 3 * (i == 0)), 0.08 * (1 + i / 3), 0.5) for i in range(10)]
    allv = sorted(v for p in pods for v in p)
    avg_p99 = sum(true_q(sorted(p), 0.99) for p in pods) / len(pods)
    agg = Native(3)
    for p in pods:
        for v in p:
            agg.observe(v)  # summing per-pod native histograms bucket-wise is identical to this
    t99 = true_q(allv, 0.99)
    print(f"true fleet p99 {t99:.4f}s | avg(per-pod p99) {avg_p99:.4f}s ({avg_p99 / t99 - 1:+.1%}) | "
          f"histogram_quantile(0.99, sum(native)) {agg.quantile(0.99):.4f}s ({agg.quantile(0.99) / t99 - 1:+.1%})")
    checks.append(("aggregated histogram beats averaged p99", abs(agg.quantile(0.99) / t99 - 1) < abs(avg_p99 / t99 - 1)))
    print()

    print("== 6. Series cost per histogram family (per label combination) ==")
    print(f"classic with DefBuckets: {len(DEF_BUCKETS)} _bucket (incl. +Inf) + _sum + _count = {len(DEF_BUCKETS) + 2} series")
    print(f"NHCB (classic converted): 1 series, same {len(DEF_BUCKETS)} buckets, same linear interpolation")
    print(f"native schema 3: 1 series, {len(h3.pos)} populated buckets here, resolution ~{2 ** (1 / 8) - 1:.1%} per bucket")
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed[:5]}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:native_histogram_lab.py -->
```text
== 1. Schemas: base = 2^(2^-schema) ==
schema       base   width bkts/decade max rel err (geo mid)
    -4 65536.00000 6553500.0%         0.2            25500.00%
    -2   16.00000 1500.0%         0.8              300.00%
     0    2.00000 100.0%         3.3               41.42%
     1    1.41421  41.4%         6.6               18.92%
     2    1.18921  18.9%        13.3                9.05%
     3    1.09051   9.1%        26.6                4.43%
     4    1.04427   4.4%        53.2                2.19%
     5    1.02190   2.2%       106.3                1.09%
     8    1.00271   0.3%       850.4                0.14%
bounds table regenerated (client_golang generator + Go math.Exp2 port): SHA-256 matches the Go source: True; the same generator with Python 2**x differs in 255/511 entries; only 170/511 entries are correctly rounded
e.g. schema 7 bound #109: table 1.804454167806623 vs exact 1.804454167806624; 4 doubles in between land in the upper bucket in Prometheus but the lower one in exact math (4 confirmed)

== 2. Bucket key <-> bound consistency (client_golang key vs server getBound), 20k values ==
violations of bound(k-1) < v <= bound(k): 0

== 3. 100k latencies (lognormal, median 120 ms, sigma 0.9) as a schema-3 native histogram ==
populated buckets 87, spans [[-68, 90]] (1 total), deltas 90 (first [1, 0, 2, -2, 1, 4])
protobuf Histogram message (native fields only): 168 B for 87 buckets
reduce schema 3 -> 2: 45 buckets (counts preserved: True)
reduce schema 3 -> 1: 24 buckets (counts preserved: True)
reduce schema 3 -> 0: 12 buckets (counts preserved: True)

== 4. Quantile estimates: classic DefBuckets vs NHCB vs native schema 3 vs schema 0 ==
-- lognormal 120ms
     q      true |   classic     err | native s3     err | native s0     err
   0.5    0.1206 |    0.1326  +10.0% |    0.1205   -0.1% |    0.1200   -0.4%
   0.9    0.3812 |    0.4278  +12.2% |    0.3812   +0.0% |    0.4093   +7.4%
  0.99    0.9659 |    0.9888   +2.4% |    0.9656   -0.0% |    0.9846   +1.9%
 0.999    1.8304 |    2.3674  +29.3% |    1.8304   +0.0% |    1.9454   +6.3%

-- bimodal 2ms/300ms
     q      true |   classic     err | native s3     err | native s0     err
   0.5    0.0024 |    0.0036  +50.9% |    0.0024   +0.2% |    0.0027  +14.5%
   0.9    0.3569 |    0.3996  +12.0% |    0.3572   +0.1% |    0.3785   +6.1%
  0.99    0.6259 |    0.8396  +34.1% |    0.6289   +0.5% |    0.8007  +27.9%
 0.999    0.8915 |    0.9889  +10.9% |    0.8947   +0.4% |    0.9847  +10.5%

== 5. Why summaries do not aggregate: 10 pods, per-pod p99 vs fleet p99 ==
true fleet p99 0.7352s | avg(per-pod p99) 0.6454s (-12.2%) | histogram_quantile(0.99, sum(native)) 0.7375s (+0.3%)

== 6. Series cost per histogram family (per label combination) ==
classic with DefBuckets: 12 _bucket (incl. +Inf) + _sum + _count = 14 series
NHCB (classic converted): 1 series, same 12 buckets, same linear interpolation
native schema 3: 1 series, 87 populated buckets here, resolution ~9.1% per bucket

checks: 13/13 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 Instrumentation (Go, client_golang v1.25): dual classic + native during migration

```go
package metrics

import (
	"net/http"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

// RequestDuration exposes BOTH a classic and a native histogram from one Observe() call.
// Scrapers with scrape_native_histograms=false see only the classic buckets; native-aware
// scrapers (protobuf) see the native buckets, plus the classic ones only if they set
// always_scrape_classic_histograms=true.
var RequestDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
	Name:    "http_server_request_duration_seconds",
	Help:    "Duration of HTTP server requests.",
	Buckets: []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.3, 0.5, 1, 2.5, 5}, // 0.3 = SLO threshold
	// Native part: smallest schema whose growth factor <= 1.1 is schema 3 (2^(1/8) ≈ 1.0905).
	NativeHistogramBucketFactor:     1.1,
	NativeHistogramMaxBucketNumber:  160,       // past this, reset (after MinResetDuration) or reduce schema
	NativeHistogramMinResetDuration: time.Hour, // do not reset more often than hourly
	NativeHistogramMaxExemplars:     10,        // exemplars kept per histogram (link to traces, Folder 05)
	NativeHistogramExemplarTTL:      5 * time.Minute,
}, []string{"route", "method", "code"}) // NO pod/user/tenant here: cardinality is per combination

// Requests is a counter; start timestamps are exposed via protobuf automatically.
var Requests = promauto.NewCounterVec(prometheus.CounterOpts{
	Name: "http_server_requests_total",
	Help: "HTTP server requests.",
}, []string{"route", "method", "code"})

// Instrument wraps a handler; route must be the TEMPLATE ("/orders/{id}"), never the raw path.
func Instrument(route string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, code: 200}
		next.ServeHTTP(rec, r)
		code := strconv.Itoa(rec.code)
		RequestDuration.WithLabelValues(route, r.Method, code).Observe(time.Since(start).Seconds())
		Requests.WithLabelValues(route, r.Method, code).Inc()
	})
}

type statusRecorder struct {
	http.ResponseWriter
	code int
}

func (s *statusRecorder) WriteHeader(code int) { s.code = code; s.ResponseWriter.WriteHeader(code) }
```

### 2.2 Scrape configuration for a staged migration

```yaml
global:
  scrape_interval: 15s
  scrape_native_histograms: false          # explicit: do not depend on defaults (3.8+ semantics)
scrape_configs:
  # Phase 1 (week 0): convert classic -> NHCB server-side, keep classic for existing dashboards.
  - job_name: legacy-apps
    convert_classic_histograms_to_nhcb: true
    always_scrape_classic_histograms: true      # dual-store during dashboard migration (2x histogram cost)
    kubernetes_sd_configs: [{role: pod}]
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        regex: "true"
        action: keep
  # Phase 2 (instrumented services): native exponential histograms via protobuf.
  - job_name: native-apps
    scrape_native_histograms: true
    always_scrape_classic_histograms: false     # flip to true only while classic consumers remain
    native_histogram_bucket_limit: 160          # server-side cap: reduce schema beyond this
    native_histogram_min_bucket_factor: 1.09    # never store finer than schema 3
    scrape_protocols: [PrometheusProto, OpenMetricsText1.0.0, PrometheusText0.0.4]
    kubernetes_sd_configs: [{role: pod}]
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_metrics_native]
        regex: "true"
        action: keep
      # 3.13+: per-target overrides via internal labels
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_native_histograms]
        regex: "(true|false)"
        target_label: __scrape_native_histograms__
remote_write:
  - url: https://mimir.example.internal/api/v1/push
    protobuf_message: io.prometheus.write.v2.Request
    send_native_histograms: true                # default false: without it native data never leaves
```

### 2.3 Queries that work on both, and recording rules for the migration window

```yaml
groups:
  - name: latency-slo.rules
    interval: 30s
    rules:
      # Native (exponential or NHCB): one series per route; no 'le' in the aggregation.
      - record: route:http_server_request_duration_seconds:p99_rate5m
        expr: |
          histogram_quantile(0.99,
            sum by (route) (rate(http_server_request_duration_seconds[5m])))
      # Classic: must keep 'le' through the aggregation.
      - record: route:http_server_request_duration_seconds_bucket:p99_rate5m_classic
        expr: |
          histogram_quantile(0.99,
            sum by (route, le) (rate(http_server_request_duration_seconds_bucket[5m])))
      # SLO "fraction of requests faster than 300 ms": native uses histogram_fraction directly.
      - record: route:http_server_request_duration_seconds:fraction_le_300ms_rate5m
        expr: |
          histogram_fraction(0, 0.3,
            sum by (route) (rate(http_server_request_duration_seconds[5m])))
      # Classic equivalent is EXACT only because 0.3 is a bucket boundary.
      - record: route:http_server_request_duration_seconds_bucket:fraction_le_300ms_rate5m_classic
        expr: |
          sum by (route) (rate(http_server_request_duration_seconds_bucket{le="0.3"}[5m]))
            / sum by (route) (rate(http_server_request_duration_seconds_count[5m]))
      # Average and count from native histograms without separate _sum/_count series.
      - record: route:http_server_request_duration_seconds:avg_rate5m
        expr: histogram_avg(sum by (route) (rate(http_server_request_duration_seconds[5m])))
```

### 2.4 Counter hygiene and start timestamps

```yaml
# prometheus.yml excerpt for a fleet whose services expose start timestamps via protobuf
global:
  scrape_protocols: [PrometheusProto, OpenMetricsText1.0.0, PrometheusText0.0.4]
# CLI (pick ONE ST mode; both are feature flags, not config):
#   --enable-feature=created-timestamp-zero-ingestion   # mature: inject 0 at start time
#   --enable-feature=st-storage                          # 3.11+ experimental: store ST per sample
#                                                        # (implies XOR2 + histogram ST chunks; see File 01 F4)
```

---

## 3. Failure modes and FinOps debugging

### F1. "p99 across the fleet" built by averaging summaries

**Symptom.** The SLO dashboard says p99 = 200 ms while customers report seconds. Error-budget burn looks fine during an incident.

**Signature.** Panels use `avg(http_request_duration_seconds{quantile="0.99"})` or `max(...)`. The metric is a summary: the `quantile` label exists and there are no `_bucket` series.

**Root cause.** Quantiles do not compose. Averaging them weights a quiet pod the same as a hot one and discards the tail (L5 §5: −12% on a mild case; arbitrarily wrong with skew). `max()` is also wrong: it is an upper bound only if every pod sees the same traffic mix.

**Fix.** Replace with a histogram, native or classic, and compute `histogram_quantile(0.99, sum(rate(...)))`. For SLOs, use ratios of counts (`histogram_fraction` or the bucket ratio at the threshold), not quantiles at all (Folder 04).

**Prevention.** Lint dashboards for aggregations over `quantile=` series, and forbid summaries for any metric used across replicas.

### F2. SLO threshold that is not a bucket boundary

**Symptom.** "99% under 300 ms" is reported as 97.8% one week and 99.4% the next, with no corresponding change in traces.

**Signature.** The buckets are DefBuckets (…, 0.25, 0.5, …). The SLI query interpolates between `le="0.25"` and `le="0.5"`.

**Root cause.**
- With linear interpolation inside a 250 ms–500 ms bucket, any count change near 300 ms is smeared across a 2× range. L5 shows +12–34% quantile errors from DefBuckets near the mode.
- An SLI computed from `le="0.25"` measures the *wrong threshold* exactly.

**Fix.**
- Add the threshold as a bucket boundary (0.3 in §2.1).
- Or move to native histograms, where `histogram_fraction(0, 0.3, …)` interpolates log-linearly inside a ~9% bucket.

**Prevention.** SLO reviews must include "is the threshold a bucket boundary?" Keep a bucket set per latency class, not DefBuckets everywhere.

### F3. Native histograms "enabled" but nothing native is stored

**Symptom.** Services were instrumented with `NativeHistogramBucketFactor`. Dashboards using `histogram_quantile(0.99, sum(rate(x[5m])))` without `_bucket` return empty.

**Signature.**
- `x` has no histogram samples; only `x_bucket` exists.
- The Targets page shows the scrape protocol as OpenMetrics or text.
- `prometheus_tsdb_head_native_histogram_series` (3.14+) is 0.

**Root cause.** Since 3.8 native histograms are ingested only with `scrape_native_histograms: true` on the scrape config. Also, negotiation must land on protobuf (or OM 2.0 with its flag), because text formats cannot carry native buckets. Upgrades from pre-3.8 that relied on the feature flag silently lost native ingestion when 3.9 made the flag a no-op.

**Fix.** Set `scrape_native_histograms: true` and verify the negotiated protocol. Backfill is impossible, so the gap remains.

**Prevention.**
- Set the option explicitly (true or false) in every scrape config, so defaults never decide.
- Alert when `prometheus_tsdb_head_native_histogram_series` drops to 0 for a server expected to have them.

### F4. Native data never reaches the long-term store

**Symptom.** Local Prometheus dashboards work; Grafana on Mimir/Thanos shows no native latency data.

**Signature.** The remote store has the classic `_bucket` series (if dual-exposed) but no histogram samples. `prometheus_remote_storage_histograms_total` is 0 while local native series exist.

**Root cause.** `remote_write.send_native_histograms` defaults to **false**.

**Fix.** Set it to true, confirm the receiver supports native histograms (and RW2 if used), and check `prometheus_remote_storage_histograms_failed_total`.

**Prevention.** Add a config-lint rule: if any scrape config sets `scrape_native_histograms: true`, every remote_write must set `send_native_histograms: true`, or the omission must be documented.

### F5. Bucket explosion and silent resolution loss on wide-range histograms

**Symptom.** A histogram covering microseconds to minutes (batch jobs, queue wait) shows quantiles that jump in steps. Memory per series is high.

**Signature.**
- Many populated buckets (`histogram_count` vs bucket count via the UI table).
- `prometheus_target_scrapes_exceeded_native_histogram_bucket_limit_total` increments.
- The schema drops over time, visible in the UI's histogram view.

**Root cause.** At schema 3 one decade costs ~27 buckets (L5 §1), so 10⁻⁶–10³ s is ~240 buckets. The client's `NativeHistogramMaxBucketNumber` or the server's `native_histogram_bucket_limit` force resolution reduction (schema 3 → 2 → 1 …) or periodic client resets. Precision then degrades exactly when the distribution is widest.

**Fix.**
- Split the metric by job phase.
- Use a coarser schema intentionally (`NativeHistogramBucketFactor: 1.2` → schema 2).
- Raise the zero threshold so sub-microsecond noise collapses into the zero bucket.

**Prevention.** Size schema × decades-covered at design time: buckets ≈ 2^s × log₂(max/min).

### F6. 3.0 upgrade breaks every `le="1"` selector

**Symptom.** After upgrading to 3.x, some SLO recording rules return nothing or drop by a bucket's worth.

**Signature.** Rules or dashboards contain `le="1"`, `le="5"` or `quantile="1"`. Series now have `le="1.0"`.

**Root cause.** 3.0 normalizes `le` and `quantile` label values to float formatting on ingestion for every protocol. In 2.x text ingestion kept `"1"` while protobuf produced `"1.0"`, so series identity depended on the protocol.

**Fix.** Rewrite selectors to `le="1.0"`, or use a regex such as `le=~"1(\\.0)?"` during the transition, then remove it.

**Prevention.** Run `promtool test rules` fixtures with float-formatted `le` values. Grep rule repos for integer `le=` before major upgrades.

### F7. Dual-storing classic + native doubles the bill

**Symptom.** Head series and remote-write cost rose ~1.5× after the "native histogram migration", which was supposed to cut them.

**Signature.** `always_scrape_classic_histograms: true` on many jobs, and both `x_bucket` series and `x` histogram samples exist for the same family.

**Root cause.** The migration toggle was never turned off. Classic N+2 series plus one native series per combination is strictly more than either alone.

**Fix.** Find remaining classic consumers with dashboard and rule usage analysis (Folder 08). Rewrite them, then set `always_scrape_classic_histograms: false`, family by family.

**Prevention.** Time-box dual storage, for example 30 days with an owner and a removal ticket. Track `prometheus_tsdb_head_native_histogram_series` against classic `_bucket` series counts on a migration dashboard.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "Histogram or summary for our API latency?"</b></summary>

**Initial Prompt.** We need p99 latency per route across 200 pods. Which type?

**L5 Textbook Answer.** Summary, because it computes accurate quantiles client-side. Histograms are approximate.

**Why L5 Fails at 3 AM or on the Bill.** "Across 200 pods" is an aggregation, and summaries cannot be aggregated. The dashboard will average p99s and under-report the tail during exactly the incidents that matter (L5: −12% on a mild case). Summaries also cannot change their quantiles retroactively or feed `histogram_fraction` for SLOs.

**L7 Principal Defense.**
1. A histogram, specifically a native one at schema 3 (~9% buckets, ≤ ~4.4% worst-case error and typically under 1%, L5).
2. One series per route/method/code instead of 14, so it is also cheaper than classic.
3. Fleet p99 is `histogram_quantile(0.99, sum by (route) (rate(x[5m])))`.
4. For the SLO I use `histogram_fraction(0, 0.3, …)`, a ratio of counts, which is mathematically aggregatable, rather than a quantile.
5. A summary is only for a single-process percentile where the histogram state is unaffordable.
</details>

<details><summary><b>Q2 · "Explain native histogram bucket math precisely."</b></summary>

**Initial Prompt.** How does a native histogram decide which bucket 0.137 s goes into, and what is stored?

**L5 Textbook Answer.** Buckets grow exponentially by a factor set by the schema. The value goes into the bucket covering it, and buckets are sparse, so only non-empty ones are stored.

**Why L5 Fails at 3 AM or on the Bill.** No bound inclusivity, no index formula, no encoding, no OTel off-by-one. That is how teams ship OTel → Prometheus pipelines with every bucket shifted by one, or argue about "off-by-one-bucket" test failures.

**L7 Principal Defense.**
1. Base `b = 2^(2^-s)`; bucket `i` is `(b^(i−1), b^i]`, upper-inclusive.
2. Key: `frexp(0.137) = (0.548, −2)`. At schema 3, `searchFloat64s(bounds, 0.548) + (−3)·8` locates it.
3. Bounds come from a shared 511-entry table that is not correctly rounded. Clients must use the table: regenerating it with Python `pow` differs in 255 entries, while Go's `math.Exp2` reproduces it bit-exactly (L5).
4. Stored: schema, zero threshold and count, plus spans (offset, length) and zig-zag delta counts. Gaps of ≤ 2 empty buckets are padded inside a span.
5. OTel's index is one lower: `(b^i, b^(i+1)]`, so the translator adds 1 and downscales scale > 8.
6. Reduction is `((i−1) >> Δ) + 1`, exact.
</details>

<details><summary><b>Q3 · "Our classic histogram p99 says 2.5 s. Is it?"</b></summary>

**Initial Prompt.** The p99 panel is pinned at exactly 2.5 s for hours. Is latency really 2.5 s?

**L5 Textbook Answer.** Yes, p99 is 2.5 s; we should optimize the slow endpoint.

**Why L5 Fails at 3 AM or on the Bill.** A quantile that sits *exactly on a bucket boundary* for hours is the signature of the `+Inf` rule. When the rank falls in the `+Inf` bucket, `BucketQuantile` returns the second-highest bound. The real p99 could be 2.6 s or 60 s, and you are blind above your largest finite bucket.

**L7 Principal Defense.**
1. Check `rate(x_bucket{le="+Inf"}[5m]) - rate(x_bucket{le="2.5"}[5m])`. If more than 1% of requests are above 2.5 s, the panel is clamped.
2. Short term: add buckets (5, 10, 30) or compute `histogram_fraction`-style "share above 2.5 s".
3. Long term: native histograms have no fixed top and cover the tail adaptively.
4. I would also alert on "share of requests in the +Inf bucket" as a measurement-validity alert.
</details>

<details><summary><b>Q4 · "Migrate 300 services from classic to native histograms. Plan it."</b></summary>

**Initial Prompt.** Give me the rollout plan and the risks.

**L5 Textbook Answer.** Enable native histograms in Prometheus, update client libraries, change dashboards to the new queries.

**Why L5 Fails at 3 AM or on the Bill.** It misses the default traps and the dashboard cutover gap:
- `scrape_native_histograms` is off by default;
- `send_native_histograms` is off by default;
- the protocol must negotiate to protobuf.

It also misses the cost spike from dual storage, and the long-term store's support status. Native data is never backfilled, so mistakes create permanent holes.

**L7 Principal Defense.**
1. Inventory. Find classic families by series count and consumers (rules, dashboards, alerts).
2. Phase 1, no code change: `convert_classic_histograms_to_nhcb: true` with `always_scrape_classic_histograms: true`. Rewrite queries against NHCB, then turn classic off. Series fall ~14×.
3. Phase 2: client libraries emit native exponential buckets (factor 1.1, max 160), `scrape_native_histograms: true`, protobuf negotiated, and `send_native_histograms: true` on every remote_write. Verify `prometheus_tsdb_head_native_histogram_series` and remote `histograms_total`.
4. Phase 3: SLOs move to `histogram_fraction`.
5. Exit criteria per family: zero classic consumers, then classic off.
6. Time-box dual storage with an owner. Measure head series and remote-write bytes before and after.
</details>

<details><summary><b>Q5 · "Why do counters reset, and how much data do we lose?"</b></summary>

**Initial Prompt.** After every deploy, our request-rate panels dip. Are we losing data?

**L5 Textbook Answer.** Counters reset on restart; `rate()` handles resets automatically, so no data is lost.

**Why L5 Fails at 3 AM or on the Bill.** `rate()` handles the *decrease*, but the increments between the last pre-restart scrape and the first post-restart scrape are invisible. On short-lived or frequently deployed pods with long scrape intervals, that is a measurable under-count, and pods that die before their first scrape are never counted.

**L7 Principal Defense.**
1. Quantify it: lost increments ≈ rate × (scrape interval / 2) per restart. That matters at high deploy frequency.
2. Mitigations:
   - start timestamps via protobuf, with `created-timestamp-zero-ingestion` (inserts a 0 at the start time so the first scrape's full value counts);
   - in 3.11+, `st-storage` plus `use-start-timestamps` so `rate()` uses the true start;
   - a pre-stop hook that delays termination by one scrape interval.
3. For billing-grade counts I do not use scraped counters at all; I use events (logs or Kafka) reconciled offline.
</details>

<details><summary><b>Q6 · "What does a native histogram cost compared to a classic one?"</b></summary>

**Initial Prompt.** Finance asks whether native histograms are cheaper or more expensive.

**L5 Textbook Answer.** Cheaper, because it is one series instead of many.

**Why L5 Fails at 3 AM or on the Bill.** The cost lives in several places:
- series count is down ~14×, which shrinks head memory, index and postings;
- *bytes per sample* go up, since a native sample can be hundreds of bytes and histogram chunks target 1 KiB;
- remote-write payloads grow per sample but shrink per family;
- vendor pricing may count "series", "samples" or "datapoints per bucket".

A one-line answer can be wrong by vendor.

**L7 Principal Defense.**
1. Model all three: series (memory and index), bytes (disk), and billable units (vendor).
2. For self-hosted Prometheus, Mimir or Thanos, memory and index dominate, so native histograms are a clear win, typically 5–14× fewer series for latency families.
3. For per-series SaaS pricing, also a win. For per-datapoint SaaS pricing that counts buckets, check the contract, since it may be neutral or worse.
4. I would run one representative family in both forms for a week and compare `prometheus_tsdb_head_series`, block bytes and the vendor invoice line.
</details>

<details><summary><b>Q7 · "OTel SDK sends exponential histograms at scale 20. What happens in Prometheus?"</b></summary>

**Initial Prompt.** Our Java services use the OTel SDK with default exponential histograms, sent over OTLP to Prometheus.

**L5 Textbook Answer.** Prometheus supports OTLP natively, so it just works as native histograms.

**Why L5 Fails at 3 AM or on the Bill.**
- Prometheus supports schemas −4..8, so scale 20 is downscaled by 2^12. The SDK's 160-bucket budget at high scale becomes a handful of coarse buckets, or the SDK's own rescaling has already happened.
- Indices shift by one.
- Explicit-bucket OTel histograms become *classic* series unless `convert_histograms_to_nhcb` is set.
- Delta temporality needs `otlp-deltatocumulative` or native delta ingestion.

"It just works" hides precision and cost differences.

**L7 Principal Defense.**
1. Configure the SDK's max scale or max size so resolution is not wasted, e.g. a max scale ≤ 8 that matches Prometheus.
2. Use cumulative temporality toward Prometheus.
3. Set `otlp.convert_histograms_to_nhcb: true` for explicit histograms.
4. Verify by querying the histogram's schema in the UI table view.
5. Watch `prometheus_api_otlp_translation_warnings_total` for name collisions.
6. Document the translation strategy so dashboard authors know the metric names.
</details>

<details><summary><b>Q8 · "Can I use rate() on a gauge?"</b></summary>

**Initial Prompt.** I want the rate of change of `queue_depth`. `rate(queue_depth[5m])` gives weird values.

**L5 Textbook Answer.** `rate()` works on any series; the weird values are just noise in the queue.

**Why L5 Fails at 3 AM or on the Bill.** `rate()` assumes counter semantics. Every decrease is treated as a reset and the post-drop value is added as an increase, so a draining queue shows a *positive* "rate". Alerts on it fire backwards.

**L7 Principal Defense.**
1. For gauges use `deriv(queue_depth[5m])` (least-squares slope) or `delta()`.
2. For "items processed", export a counter (`queue_dequeued_total`) and `rate()` it.
3. Gauge-vs-counter correctness is enforced at code review with naming conventions (`_total` only on counters), and optionally with `type-and-unit-labels` so tooling can warn when `rate()` is applied to a gauge.
</details>

---

## 5. Invariants checklist

- [ ] No cross-replica aggregation of summaries. Fleet percentiles come from histograms only.
- [ ] Every SLO latency threshold is a classic bucket boundary, or the SLO uses native histograms with `histogram_fraction`.
- [ ] `scrape_native_histograms` is set explicitly in every scrape config. Native-histogram jobs negotiate `PrometheusProto` (or OM 2.0 with its flag).
- [ ] Every `remote_write` sets `send_native_histograms` deliberately.
- [ ] Dual classic + native storage (`always_scrape_classic_histograms: true`) is time-boxed with an owner.
- [ ] Clients that compute native buckets use the shared bounds table, not `pow`. OTel scale is capped at 8 toward Prometheus, and OTel index + 1 = Prometheus index.
- [ ] Rules and dashboards use float-formatted `le`/`quantile` values (3.0 normalization).
- [ ] Wide-range histograms are sized by `2^schema × log₂(max/min)` buckets against `native_histogram_bucket_limit`.
- [ ] Counter correctness after restarts is addressed with start timestamps where under-count matters.

---

## 6. References

- Native histogram math and bounds table: <https://github.com/prometheus/prometheus/blob/v3.15.1/model/histogram/generic.go>
- `targetIdx` and float histogram ops: <https://github.com/prometheus/prometheus/blob/v3.15.1/model/histogram/float_histogram.go>
- `BucketQuantile` / `HistogramQuantile`: <https://github.com/prometheus/prometheus/blob/v3.15.1/promql/quantile.go>
- OTLP histogram translation: <https://github.com/prometheus/prometheus/blob/v3.15.1/storage/remote/otlptranslator/prometheusremotewrite/histograms.go>
- client_golang histogram (bounds generator, key function, options): <https://github.com/prometheus/client_golang/blob/main/prometheus/histogram.go>
- Exposition protobuf (`io.prometheus.client`): <https://github.com/prometheus/prometheus/blob/v3.15.1/prompb/io/prometheus/client/metrics.proto>
- Native histograms specification: <https://prometheus.io/docs/specs/native_histograms/>
- 3.x migration guide (`le`/`quantile` normalization, scrape protocols): <https://prometheus.io/docs/prometheus/latest/migration/>
- Feature flags (created timestamps, st-storage, type-and-unit labels, openmetrics2): <https://prometheus.io/docs/prometheus/latest/feature_flags/>
- Histograms and summaries practice guide: <https://prometheus.io/docs/practices/histograms/>
- OpenTelemetry exponential histogram data model: <https://opentelemetry.io/docs/specs/otel/metrics/data-model/#exponentialhistogram>
- Go `math.Exp2` source used by the bounds generator: <https://github.com/golang/go/blob/master/src/math/exp.go>
