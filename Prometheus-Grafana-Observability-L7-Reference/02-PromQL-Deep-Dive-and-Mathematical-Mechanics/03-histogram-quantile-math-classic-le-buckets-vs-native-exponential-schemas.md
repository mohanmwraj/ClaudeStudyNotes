# 03 · histogram_quantile() Math: Classic `le` Buckets vs Native Exponential Schemas

> **Folder 02 — PromQL Deep Dive and Mathematical Mechanics · File 3 of 3.**
> Pinned to **Prometheus v3.15.1** (`promql/quantile.go` `BucketQuantile`, `HistogramQuantile`, `BucketFraction`, read at tag `v3.15.1`). Bucket representation is in Folder 01 File 3; this file is about the *query-time* math.
> Labels: **[D]** documented / read in pinned source · **[M]** measured by a listing (deterministic, re-run by the gate) · **[E]** model · **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L4 `histogram_quantile_lab.py` | 5 pods × 20 req/s × 10 min of lognormal latencies (one degraded pod), scraped into classic `_bucket` counters and queried through the L1 engine. Shows: averaging per-pod p99s is wrong *even with perfect per-pod quantiles* (−43%); bucket-width error of the correct query (+40% at p99 with DefBuckets) vs native schema 3 (+0.8%); the missing-`le` bug; SLO fraction with/without the threshold as a bucket boundary; worst-case error bounds; and the `+Inf` clamp | ~2 s |

**Verification.** Classic queries run through L1 (File 1), whose `histogram_quantile`/`histogram_fraction` ports pass all attempted upstream `histograms.test` cases (82). Native interpolation follows `HistogramQuantile` (log-linear within a bucket, reverse iteration for q ≥ 0.5). Ground truth is the empirical quantile of raw observations in the same `(T−5m, T]` window. No live server was run.

---

## 0. Orientation

**What this file answers.** How `histogram_quantile(φ, …)` turns bucket counts into a latency number — exactly; how large its error can be and why; which aggregation orders are mathematically valid; how `histogram_fraction` gives exact SLO ratios when buckets are placed well; and how native histograms change every one of these answers.

**The one-line model.** A histogram never stores observations, only counts per interval. Every quantile is therefore an **interpolation** inside the bucket that contains rank φ·N — linear for classic and NHCB buckets, logarithmic for native exponential buckets — and its error is bounded by that bucket's width.

---

## 1. First principles: from bucket counts to a number

### 1.1 Classic: `BucketQuantile` [D]

```text
 input: one group = buckets {(le_i, cumulative count c_i)} incl. le=+Inf (else → NaN)
 1. sort by le; coalesce equal le (sum counts); force monotonicity:
      if c_i ≈ c_{i-1} (rel. 1e-12) or c_i < c_{i-1}:  c_i := c_{i-1}   (annotation emitted)
 2. N = c_{+Inf};  N == 0 → NaN;  φ<0 → −Inf;  φ>1 → +Inf;  φ NaN → NaN
 3. rank = φ·N;  b = first bucket with c_b ≥ rank  (searching all but the +Inf bucket)
 4. if b is the +Inf bucket:          return le of the second-highest bucket      ← the clamp
    if b == 0 and le_0 ≤ 0:          return le_0
    lower = (b == 0) ? 0 : le_{b-1};  count = c_b − c_{b-1};  rank −= c_{b-1}
    return lower + (le_b − lower) · rank / count                                  ← linear
```

Two properties follow immediately:

- **Error bound.** The true quantile lies in `(le_{b−1}, le_b]`; the estimate lies in the same interval; so |error| < bucket width. With DefBuckets `(1, 2.5]` that is up to 1.5 s at p99 (L4 §4: actual +0.49 s).
- **Blind tail.** If more than (1−φ) of observations exceed the largest finite `le`, the answer is pinned at the second-highest bound forever (L4 §6: 22% of requests above 0.5 s, true p99 3.25 s, reported 0.50 s).

### 1.2 Native: `HistogramQuantile` [D]

```text
 φ < 0.5 (or Sum is NaN): iterate buckets from the lowest; rank = φ·N
 φ ≥ 0.5:                 iterate from the HIGHEST bucket;  rank = (1−φ)·N   (less float error in tails)
 stop at the bucket where the running count ≥ rank; fraction f = position inside that bucket
 zero bucket or custom buckets (NHCB):   lower + (upper−lower)·f                    (linear)
 positive exponential bucket (lo, hi]:   2^( log2(lo) + (log2(hi) − log2(lo))·f )   (log-linear)
 negative bucket: mirrored;  NHCB first bucket (−Inf, x]: lower := 0 if x > 0;  last (x, +Inf]: return x
```

Because exponential buckets are equal-width on a log scale, log-linear interpolation is the natural "uniform within bucket" assumption, and the error bound is *relative*: at schema 3 a bucket spans 9.05%, so the estimate is within ~±4.4% of the bucket's geometric centre in the worst case and usually far closer (L4 §5).

### 1.3 Aggregation order: buckets first, quantile last

```text
 correct:   histogram_quantile(0.99, sum by (le) (rate(x_bucket[5m])))          classic
            histogram_quantile(0.99, sum(rate(x[5m])))                           native / NHCB
 wrong:     avg(histogram_quantile(0.99, sum by (pod, le) (rate(x_bucket[5m]))))
            avg(x{quantile="0.99"})                                              (summaries)
 also wrong: histogram_quantile(0.99, rate(sum(x_bucket)[5m:]))                 (rate after sum, File 2)
```

L4 §1 makes the distinction quantitative [M]:

| Method | p99 | Error vs true 1.241 s | Error source |
|---|---|---|---|
| avg of **exact** per-pod p99s (perfect summaries) | 0.706 s | **−43.1%** | inherent: quantiles don't average |
| avg of per-pod classic `histogram_quantile` | 0.854 s | −31.2% | inherent + bucket width |
| classic `sum by (le)` then quantile | 1.733 s | +39.6% | bucket width only (`(1, 2.5]`) |
| native schema 3, summed then quantile | 1.251 s | **+0.8%** | bucket width (9%) only |

The averaged numbers can *look* closer than the correct classic query on a given day — that is a coincidence of coarse buckets, not a property. Averaging error is unbounded and depends on traffic mix (the slow pod's tail is diluted 5×); bucket error is bounded and is removed by better buckets or native histograms.

### 1.4 `histogram_fraction`: the SLO primitive

`histogram_fraction(a, b, h)` estimates the share of observations in `[a, b]`. Classic/NHCB use `BucketFraction` (linear interpolation inside the boundary buckets; buckets with infinite bounds contribute nothing beyond their cumulative count) [D]. For SLOs:

- **If the threshold is a bucket boundary the ratio is exact:** `rate(x_bucket{le="0.3"}[5m]) / rate(x_count[5m])` — L4 §3: **−0.05 pp** vs truth (the residue is the counter window's sampling noise).
- **If it is not, the fraction interpolates:** DefBuckets have no 0.3, so `(0.25, 0.5]` is split linearly — **−1.55 pp**. At a 99% SLO that is *more than the entire error budget* (1 pp).
- **Native histograms** interpolate inside a ~9% bucket around 0.3 s, so the error is a small fraction of the bucket's count — good enough for most SLOs without placing a boundary.

### 1.5 The rest of the histogram toolbox (native and NHCB) [D]

| Function | Returns | Classic equivalent |
|---|---|---|
| `histogram_count(h)` | observations count | `x_count` |
| `histogram_sum(h)` | sum of observations | `x_sum` |
| `histogram_avg(h)` | sum/count | `x_sum / x_count` |
| `histogram_stddev(h)` / `histogram_stdvar(h)` | estimated from bucket midpoints (geometric for exponential) | — |
| `histogram_fraction(a, b, h)` | share in [a, b] | ratio of `le` buckets |
| `histogram_quantiles(h, "q", 0.5, 0.99)` | several quantiles at once (experimental, 3.11) | several queries |
| `h </ 0.1`, `h >/ 2` | histogram trimmed below/above a value (3.11) | — |

`rate()`/`increase()`/`sum()` work directly on native histograms (bucket-wise, with schema reconciliation to the coarsest schema and NHCB bound intersection — Folder 01 File 3 §1.6).

### 1.6 Bucket design for classic histograms

```text
 rule 1  every SLO threshold is a boundary                  (exact SLI)
 rule 2  boundaries ~geometric near the operating range     (relative error roughly constant)
 rule 3  largest finite boundary > worst plausible p99.9    (avoid the +Inf clamp)
 rule 4  count × labels budgeted: series = (buckets+2) × label combinations
 example for a 300 ms SLO API:  .005 .01 .025 .05 .1 .2 .3 .5 1 2 5 10   (12 buckets + sum + count)
```

If following all four rules makes the series budget explode, that is the argument for native histograms.

<!-- listing:histogram_quantile_lab.py -->
```python
"""histogram_quantile_lab.py - histogram_quantile() and histogram_fraction() mathematics on classic
buckets (through promql_mini.py, validated against promqltest) and on native exponential buckets
(log-linear interpolation as in promql/quantile.go HistogramQuantile).

Five pods serve 20 req/s each for 10 minutes; latencies are lognormal (median 80 ms, sigma 0.7) with
pod 'p4' degraded (median 400 ms). Cumulative _bucket counters are scraped every 15 s. Ground truth
is computed from the raw observations inside the same (T-5m, T] window.

Sections: (1) the correct aggregation order vs averaging per-pod quantiles; (2) the missing-'le'
bug; (3) SLO fraction with and without the threshold as a bucket boundary; (4) worst-case error
bounds; (5) classic vs native schema 3; (6) the +Inf clamp.

Usage: python histogram_quantile_lab.py [target.md]
"""
import bisect
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from promql_mini import Engine, Parser  # noqa: E402

S, M = 1000, 60000
DEF = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
SLO = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.3, 0.5, 1, 2.5, 5, 10]


def le_str(b):
    return "+Inf" if math.isinf(b) else repr(float(b))  # 3.x normalizes le to float formatting


def build(bounds, seed=11):
    rng = random.Random(seed)
    eng, obs = Engine(), []
    for p in range(5):
        med = 0.4 if p == 4 else 0.08
        events = []
        for s in range(600):
            for _ in range(20):
                events.append((s + rng.random(), math.exp(rng.gauss(math.log(med), 0.7))))
        events.sort()
        obs += events
        ts = [e[0] for e in events]
        for b in bounds + [math.inf]:
            pts = []
            for k in range(0, 41):
                t = k * 15.0
                n = bisect.bisect_right(ts, t)
                pts.append((int(t * 1000), float(sum(1 for e in events[:n] if e[1] <= b))))
            eng.add({"__name__": "lat_bucket", "pod": f"p{p}", "job": "api", "le": le_str(b)}, pts)
    return eng, sorted(obs)


def build_pod_truth(p, seed=11):
    """Re-generate pod p's raw events exactly as build() does (same RNG sequence)."""
    rng = random.Random(seed)
    for pp in range(5):
        med = 0.4 if pp == 4 else 0.08
        events = []
        for s in range(600):
            for _ in range(20):
                events.append((s + rng.random(), math.exp(rng.gauss(math.log(med), 0.7))))
        if pp == p:
            return sorted(events), None
    raise ValueError(p)


def truth(obs, T, q):
    vals = sorted(v for t, v in obs if (T - 300 * S) / 1000 < t <= T / 1000)
    return vals[min(len(vals) - 1, math.ceil(q * len(vals)) - 1)], vals


def native_quantile(vals, q, schema=3):
    base = 2 ** (2.0 ** -schema)
    counts = {}
    for v in vals:
        k = math.ceil(math.log(v, base) - 1e-12)
        counts[k] = counts.get(k, 0) + 1
    keys = sorted(counts, reverse=True)  # q >= 0.5: iterate from the top (HistogramQuantile)
    rank, cum = (1 - q) * len(vals), 0
    for k in keys:
        cum += counts[k]
        if cum >= rank:
            break
    frac = (cum - rank) / counts[k]
    lo, hi = base ** (k - 1), base ** k
    return 2 ** (math.log2(lo) + (math.log2(hi) - math.log2(lo)) * frac), len(counts)


def main():
    checks = []
    T = 10 * M
    eng, obs = build(DEF)

    def q(expr):
        return eng.eval(Parser(expr).parse(), T)

    print("== 1. Aggregation order (DefBuckets, 4 healthy pods + 1 slow pod) ==")
    t99, vals = truth(obs, T, 0.99)
    good = q("histogram_quantile(0.99, sum by (le) (rate(lat_bucket[5m])))")[0][1]
    per_pod = q("histogram_quantile(0.99, sum by (pod, le) (rate(lat_bucket[5m])))")
    avg_pp = sum(v for _, v, _ in per_pod) / len(per_pod)
    # exact per-pod p99s (what perfect summaries would export), from the same raw data
    rng_pods = []
    for p_ in range(5):
        ev, _ = build_pod_truth(p_)
        rng_pods.append(ev)
    avg_true_pp = sum(truth(ev, T, 0.99)[0] for ev in rng_pods) / 5
    nat, _ = native_quantile(vals, 0.99)
    print(f"true fleet p99 from {len(vals):,} raw observations: {t99:.3f}s")
    print(f"avg of EXACT per-pod p99s (perfect summaries)         = {avg_true_pp:.3f}s ({avg_true_pp / t99 - 1:+.1%})  <- inherent")
    print(f"avg over pods of classic histogram_quantile by pod     = {avg_pp:.3f}s ({avg_pp / t99 - 1:+.1%})")
    print(f"classic histogram_quantile(0.99, sum by (le) (rate))   = {good:.3f}s ({good / t99 - 1:+.1%})  <- bucket width")
    print(f"native schema 3, buckets summed across pods            = {nat:.3f}s ({nat / t99 - 1:+.1%})")
    checks.append(("averaging error is inherent", abs(avg_true_pp / t99 - 1) > 0.2))
    checks.append(("native aggregate exact-ish", abs(nat / t99 - 1) < 0.02))
    print()

    print("== 2. The missing-'le' bug ==")
    bad = q("histogram_quantile(0.99, sum by (job) (rate(lat_bucket[5m])))")
    print(f"sum by (job) drops 'le' -> histogram_quantile returns {len(bad)} series (silently empty panel)")
    checks.append(("no le -> empty", len(bad) == 0))
    print()

    print("== 3. SLO 'requests under 300 ms': threshold as a bucket boundary or not ==")
    true_frac = sum(1 for v in vals if v <= 0.3) / len(vals)
    interp = q("histogram_fraction(0, 0.3, sum by (le) (rate(lat_bucket[5m])))")[0][1]
    eng_slo, _ = build(SLO)
    exact = eng_slo.eval(Parser('sum(rate(lat_bucket{le="0.3"}[5m])) / sum(rate(lat_bucket{le="+Inf"}[5m]))').parse(), T)[0][1]
    print(f"true fraction <= 300 ms: {true_frac:.4%}")
    print(f"DefBuckets (no 0.3 bound), histogram_fraction interpolates in (0.25, 0.5]: {interp:.4%} "
          f"(error {100 * (interp - true_frac):+.2f} pp)")
    print(f"buckets with 0.3 as a bound, ratio of rates:                           {exact:.4%} "
          f"(error {100 * (exact - true_frac):+.2f} pp)")
    checks.append(("boundary exact", abs(exact - true_frac) < 2e-3))
    checks.append(("interpolation off", abs(interp - true_frac) > abs(exact - true_frac)))
    print()

    print("== 4. Worst-case error of linear interpolation in the containing bucket ==")
    for qq in (0.5, 0.9, 0.99):
        est = q(f"histogram_quantile({qq}, sum by (le) (rate(lat_bucket[5m])))")[0][1]
        tv, _ = truth(obs, T, qq)
        i = bisect.bisect_left(DEF, est)
        lo, hi = (DEF[i - 1] if i > 0 else 0.0), DEF[i]
        print(f"q={qq}: estimate {est:.3f}s in bucket ({lo}, {hi}] -> worst case +/-{hi - lo:.3f}s; "
              f"actual error {est - tv:+.3f}s")
        checks.append((f"within bucket q={qq}", lo - 1e-9 <= tv <= hi + 1e-9 or abs(est - tv) <= hi - lo))
    print()

    print("== 5. Classic DefBuckets vs native schema 3 (log-linear interpolation) on the same window ==")
    print(f"{'q':>6} {'true':>7} {'classic':>8} {'err':>7} {'native':>8} {'err':>7}")
    for qq in (0.5, 0.9, 0.99, 0.999):
        tv, _ = truth(obs, T, qq)
        c = q(f"histogram_quantile({qq}, sum by (le) (rate(lat_bucket[5m])))")[0][1]
        n, nb = native_quantile(vals, qq)
        print(f"{qq:>6} {tv:>7.3f} {c:>8.3f} {c / tv - 1:>+7.1%} {n:>8.3f} {n / tv - 1:>+7.1%}")
        if qq >= 0.9:
            checks.append((f"native better q={qq}", abs(n / tv - 1) < abs(c / tv - 1)))
    print(f"native populated buckets: {nb} (one series) vs classic {len(DEF) + 1} bucket series per label set")
    print()

    print("== 6. The +Inf clamp: when the tail outruns the largest finite bucket ==")
    eng_t = Engine()
    small = [0.05, 0.1, 0.25, 0.5]
    rng = random.Random(3)
    ev = sorted((rng.random() * 600, math.exp(rng.gauss(math.log(0.2), 1.2))) for _ in range(30000))
    ts = [e[0] for e in ev]
    for b in small + [math.inf]:
        pts = [(k * 15 * S, float(sum(1 for e in ev[:bisect.bisect_right(ts, k * 15.0)] if e[1] <= b))) for k in range(41)]
        eng_t.add({"__name__": "lat_bucket", "le": le_str(b)}, pts)
    est = eng_t.eval(Parser("histogram_quantile(0.99, sum by (le) (rate(lat_bucket[5m])))").parse(), T)[0][1]
    tail = sorted(v for t, v in ev if 300 < t <= 600)
    tv = tail[math.ceil(0.99 * len(tail)) - 1]
    above = sum(1 for v in tail if v > 0.5) / len(tail)
    print(f"{above:.1%} of requests exceed the largest finite bucket (0.5 s); true p99 {tv:.2f}s; "
          f"histogram_quantile returns {est:.2f}s = the second-highest bound, forever")
    checks.append(("clamped to 0.5", est == 0.5 and tv > 1.0))
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:histogram_quantile_lab.py -->
```text
== 1. Aggregation order (DefBuckets, 4 healthy pods + 1 slow pod) ==
true fleet p99 from 30,000 raw observations: 1.241s
avg of EXACT per-pod p99s (perfect summaries)         = 0.706s (-43.1%)  <- inherent
avg over pods of classic histogram_quantile by pod     = 0.854s (-31.2%)
classic histogram_quantile(0.99, sum by (le) (rate))   = 1.733s (+39.6%)  <- bucket width
native schema 3, buckets summed across pods            = 1.251s (+0.8%)

== 2. The missing-'le' bug ==
sum by (job) drops 'le' -> histogram_quantile returns 0 series (silently empty panel)

== 3. SLO 'requests under 300 ms': threshold as a bucket boundary or not ==
true fraction <= 300 ms: 84.5933%
DefBuckets (no 0.3 bound), histogram_fraction interpolates in (0.25, 0.5]: 83.0435% (error -1.55 pp)
buckets with 0.3 as a bound, ratio of rates:                           84.5439% (error -0.05 pp)

== 4. Worst-case error of linear interpolation in the containing bucket ==
q=0.5: estimate 0.099s in bucket (0.05, 0.1] -> worst case +/-0.050s; actual error +0.001s
q=0.9: estimate 0.454s in bucket (0.25, 0.5] -> worst case +/-0.250s; actual error +0.033s
q=0.99: estimate 1.733s in bucket (1, 2.5] -> worst case +/-1.500s; actual error +0.491s

== 5. Classic DefBuckets vs native schema 3 (log-linear interpolation) on the same window ==
     q    true  classic     err   native     err
   0.5   0.098    0.099   +0.7%    0.098   +0.2%
   0.9   0.420    0.454   +7.9%    0.420   +0.0%
  0.99   1.241    1.733  +39.6%    1.251   +0.8%
 0.999   2.303    2.475   +7.5%    2.320   +0.7%
native populated buckets: 78 (one series) vs classic 12 bucket series per label set

== 6. The +Inf clamp: when the tail outruns the largest finite bucket ==
22.4% of requests exceed the largest finite bucket (0.5 s); true p99 3.25s; histogram_quantile returns 0.50s = the second-highest bound, forever

checks: 12/12 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 Latency recording rules (classic and native side by side)

```yaml
groups:
  - name: latency.rules
    interval: 30s
    rules:
      # Classic: aggregate rates of buckets, keep 'le', quantile last
      - record: job_route_le:http_server_request_duration_seconds_bucket:rate5m
        expr: |
          sum by (job, route, le) (rate(http_server_request_duration_seconds_bucket[5m]))
      - record: job_route:http_server_request_duration_seconds:p99_5m
        expr: |
          histogram_quantile(0.99, job_route_le:http_server_request_duration_seconds_bucket:rate5m)
      - record: job:http_server_request_duration_seconds:p99_5m
        expr: |
          histogram_quantile(0.99,
            sum by (job, le) (job_route_le:http_server_request_duration_seconds_bucket:rate5m))
      # Native: record the aggregated histogram itself; every quantile/fraction derives from it
      - record: job_route:http_server_request_duration_seconds:rate5m
        expr: sum by (job, route) (rate(http_server_request_duration_seconds[5m]))
      - record: job_route:http_server_request_duration_seconds:p99_5m_native
        expr: histogram_quantile(0.99, job_route:http_server_request_duration_seconds:rate5m)
      # SLI: fraction of requests <= 300 ms (exact on classic because 0.3 is a boundary)
      - record: job:http_server_request_duration_seconds:good_ratio_5m
        expr: |
          sum by (job) (job_route_le:http_server_request_duration_seconds_bucket:rate5m{le="0.3"})
            / sum by (job) (job_route_le:http_server_request_duration_seconds_bucket:rate5m{le="+Inf"})
```

### 2.2 Measurement-validity alerts

```yaml
groups:
  - name: histogram-validity
    rules:
      - alert: LatencyBeyondLargestBucket
        expr: |
          (
            sum by (job) (job_route_le:http_server_request_duration_seconds_bucket:rate5m{le="+Inf"})
            - sum by (job) (job_route_le:http_server_request_duration_seconds_bucket:rate5m{le="10.0"})
          )
          / sum by (job) (job_route_le:http_server_request_duration_seconds_bucket:rate5m{le="+Inf"})
          > 0.01
        for: 15m
        labels: {severity: warning}
        annotations:
          summary: "{{ $labels.job }}: >1% of requests exceed the largest bucket; p99 panels are clamped and lie"
      - alert: NativeHistogramIngestionMissing
        expr: |
          absent_over_time(http_server_request_duration_seconds{job="checkout"}[15m])
            and on() (count(http_server_request_duration_seconds_bucket{job="checkout"}) > 0)
        labels: {severity: warning}
        annotations:
          summary: "Classic buckets present but no native samples: check scrape_native_histograms / protobuf negotiation"
```

Note `le="10.0"`: since 3.0, `le` values are normalised to float formatting on ingestion (Folder 01 File 3 F6).

### 2.3 Grafana heatmap and quantile panels

```promql
# Heatmap (classic): rate of buckets per le; Grafana "Heatmap" format, calculate=false
sum by (le) (rate(http_server_request_duration_seconds_bucket{job="checkout"}[$__rate_interval]))

# Heatmap (native): the histogram series itself; Grafana renders native buckets directly
sum(rate(http_server_request_duration_seconds{job="checkout"}[$__rate_interval]))

# p50/p90/p99 overlay (native)
histogram_quantile(0.99, sum(rate(http_server_request_duration_seconds{job="checkout"}[$__rate_interval])))
```

---

## 3. Failure modes and FinOps debugging

### F1. Empty latency panels after a "small" query refactor

**Symptom.** p99 panels go blank after someone "simplified" the query.

**Signature.** The aggregation inside `histogram_quantile` is `sum by (job)` or `sum without (pod, le)`; `le` is gone; the result is empty (L4 §2).

**Root cause.** `histogram_quantile` groups classic buckets by all labels except `le`; with no `le`, nothing is a bucket.

**Fix.** Always include `le` in `by (...)` (or exclude it from `without`); or use native histograms where there is no `le`.

**Prevention.** Lint rule: inside `histogram_quantile`, `by` must contain `le` for `_bucket` inputs.

### F2. p99 pinned to a round number for hours

**Symptom.** p99 sits flat at exactly 2.5 or 10 during an incident.

**Signature.** The pinned value equals the largest finite bucket below `+Inf`; the `+Inf` minus largest-bucket rate is > 1% of total (alert in §2.2).

**Root cause.** The rank falls into the `+Inf` bucket and `BucketQuantile` returns the second-highest bound (L4 §6).

**Fix.** Add buckets above the plausible tail; meanwhile report "share above X".

**Prevention.** Measurement-validity alert; bucket design rule 3.

### F3. SLO compliance that swings with no behaviour change

**Symptom.** "% of requests under 300 ms" moves ±1–2 pp week to week; error budget burns inconsistently.

**Signature.** 0.3 is not a bucket boundary; the SLI uses `histogram_quantile` or `histogram_fraction` interpolation.

**Root cause.** Linear interpolation inside a 2×-wide bucket around the threshold (L4 §3: −1.55 pp), sensitive to how the distribution shifts inside that bucket.

**Fix.** Add the threshold as a boundary and use the exact bucket ratio; or use native histograms.

**Prevention.** SLO review checklist: threshold is a boundary or native.

### F4. Averaging quantiles across pods or regions

**Symptom.** Global p99 looks healthy while one region is on fire; region-level p99s average to a calm number.

**Signature.** `avg(...quantile...)` or `avg(histogram_quantile(... by (region, le)))` on global dashboards.

**Root cause.** Quantiles are not linear; averaging dilutes tails and ignores traffic weights (L4 §1: −43% even with perfect per-pod quantiles).

**Fix.** Sum buckets across regions, then quantile; show per-region panels for localisation.

**Prevention.** Dashboard lint: aggregations over quantile outputs are disallowed.

### F5. Non-monotonic buckets and "forced monotonicity" annotations

**Symptom.** Query annotations warn "input to histogram_quantile needed to be fixed for monotonicity"; quantiles jump.

**Signature.** Bucket series from different scrapes/targets merged (e.g. federated partial data, two exporters with the same labels), or buckets with mixed `le` formatting from pre-3.0 data (`"1"` and `"1.0"` as separate series).

**Root cause.** Cumulative counts must be non-decreasing in `le`; partial or duplicated bucket sets break that, and PromQL silently clamps (§1.1 step 1).

**Fix.** Ensure each bucket set comes from one target per timestamp; after 3.0 upgrades, normalise old `le` values in rules (`le=~"1(\\.0)?"`) until old data ages out.

**Prevention.** Alert on the annotation via the query log, and check for duplicate bucket series with `count by (le, job, instance) (...) > 1`.

### F6. Mixing classic and native histograms of the same name

**Symptom.** During migration, some panels double-count or show both shapes; `histogram_quantile` returns odd values for a few series.

**Signature.** Both `x` (native) and `x_bucket` (classic) exist; queries select `{__name__=~"x.*"}` or use `sum(rate(x[5m]))` while some targets still expose classic only.

**Root cause.** Classic and native are different series with different math; mixed fleets give partial native aggregates.

**Fix.** Query each explicitly; during migration compute both and compare (L4 §5 style) before switching dashboards.

**Prevention.** Migration plan with per-family cutover (Folder 01 File 3 Q4).

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "Derive what histogram_quantile(0.99, …) returns."</b></summary>

**Initial Prompt.** Walk me through the computation for classic buckets.

**L5 Textbook Answer.** It finds the bucket containing the 99th percentile and interpolates linearly.

**Why L5 Fails at 3 AM or on the Bill.** It omits the `+Inf` clamp, the zero lower bound, monotonicity fixing and the error bound — so it cannot recognise a clamped panel, a lying SLO or a merge bug.

**L7 Principal Defense.** Sort and coalesce buckets, force monotonicity, rank = 0.99·N, first bucket with cumulative ≥ rank, linear interpolation from the previous bound (0 for the first), and if the rank lands in `+Inf`, return the second-highest bound. Error < width of the containing bucket; tail blindness above the top finite bucket. I size buckets from those two facts and alert when >1% of traffic exceeds the top bucket.
</details>

<details><summary><b>Q2 · "Why can't I average p99s across pods?"</b></summary>

**Initial Prompt.** Each pod reports its own p99. Why not average them for the fleet?

**L5 Textbook Answer.** Because traffic isn't evenly distributed; a weighted average would be better.

**Why L5 Fails at 3 AM or on the Bill.** Even traffic-weighted averages of quantiles are wrong: the fleet tail depends on the *shape* of each pod's distribution, not just its p99. L4 shows −43% with perfect per-pod quantiles.

**L7 Principal Defense.** Quantiles are order statistics of the union, which can only be computed from the merged distribution. Histograms are mergeable sketches: bucket counts add. So: sum buckets (classic, keep `le`) or sum native histograms, then quantile. Weighted averages of p99 are a cheaper wrong answer, not an approximation with known error.
</details>

<details><summary><b>Q3 · "Our SLO is 99% under 300 ms. Is histogram_quantile the right SLI?"</b></summary>

**Initial Prompt.** We alert when `histogram_quantile(0.99, …) > 0.3`. Good?

**L5 Textbook Answer.** Yes, if p99 is above 300 ms we're violating the SLO.

**Why L5 Fails at 3 AM or on the Bill.** Quantile thresholds can't be summed over time into an error budget; interpolation error near the threshold can exceed the budget; and "p99 > 0.3" doesn't say *how many* requests were bad.

**L7 Principal Defense.** The SLI is a ratio of counts: good = requests ≤ 0.3 s (bucket `le="0.3"` — make it a boundary — or `histogram_fraction(0, 0.3, …)` on native), valid = all. Ratios aggregate over time and services, map to error budgets, and drive multi-window burn-rate alerts (Folder 04). The quantile stays a diagnostic panel.
</details>

<details><summary><b>Q4 · "How accurate are native histograms, really?"</b></summary>

**Initial Prompt.** Sell me native histograms with numbers.

**L5 Textbook Answer.** They have more buckets so they're more accurate.

**Why L5 Fails at 3 AM or on the Bill.** "More buckets" ignores that resolution is relative and that accuracy also depends on interpolation; it also ignores the cost model change (one series, bigger samples).

**L7 Principal Defense.** Schema s gives bucket width 2^(2^−s)−1 (9.05% at s=3), interpolated log-linearly; worst-case relative error ±4.4%, observed <1% at p90–p99.9 on L4's data versus +8% to +40% for DefBuckets. Series per label set drop from 14 to 1 (bytes per sample rise; histogram chunks target 1 KiB). For latency SLOs that is strictly better on accuracy and usually on cost — with the migration caveats in Folder 01 File 3.
</details>

<details><summary><b>Q5 · "The p99 graph is flat at 2.5 s during an outage. What's happening?"</b></summary>

**Initial Prompt.** Diagnose.

**L5 Textbook Answer.** Latency is consistently 2.5 s, maybe a timeout setting.

**Why L5 Fails at 3 AM or on the Bill.** A flat line exactly on a bucket boundary is the clamp; the real p99 may be 30 s. Tuning a "2.5 s timeout" chases a measurement artifact.

**L7 Principal Defense.** Check `+Inf − le="2.5"` share; if >1%, the panel is clamped (L4 §6 reproduces it). Report "% of requests > 2.5 s" during the incident, add higher buckets or move to native histograms, and keep a measurement-validity alert so it never surprises us again.
</details>

<details><summary><b>Q6 · "Explain histogram_fraction and when it is exact."</b></summary>

**Initial Prompt.** How does histogram_fraction compute its result?

**L5 Textbook Answer.** It returns the fraction of observations between two values using the buckets.

**Why L5 Fails at 3 AM or on the Bill.** Exactness is the whole point for SLOs; without knowing when it interpolates, teams publish SLO numbers with ±1–2 pp of silent error.

**L7 Principal Defense.** It accumulates cumulative counts up to each bound; if a bound coincides with a bucket boundary the count is exact; otherwise it interpolates linearly inside that bucket (classic/NHCB) or within the exponential bucket (native). L4 §3: boundary −0.05 pp, interpolated −1.55 pp. For a 99% SLO, interpolation error must be ≪ 1 pp, so thresholds become boundaries or the histogram becomes native.
</details>

<details><summary><b>Q7 · "Design the buckets for a new service."</b></summary>

**Initial Prompt.** A gRPC service with a 200 ms p99 target and occasional 5 s outliers. Buckets?

**L5 Textbook Answer.** Use the default buckets; they cover 5 ms to 10 s.

**Why L5 Fails at 3 AM or on the Bill.** DefBuckets have no 0.2 boundary (exact SLI impossible) and a 2× gap from 0.25 to 0.5 right where the tail lives; per-route × method × code labels multiply 14 series per combination.

**L7 Principal Defense.** Native histogram (factor 1.1, max 160 buckets) — accurate everywhere, 1 series per label set. If classic is mandatory: `.005 .01 .025 .05 .1 .15 .2 .3 .5 1 2 5 10` (0.2 is a boundary, geometric-ish around it, top above the 5 s outliers), and cardinality budgeted with (13+2) × routes × methods × codes; drop `code` from the histogram and keep it on the counter if the budget breaks.
</details>

<details><summary><b>Q8 · "Can you merge histograms from services with different bucket layouts?"</b></summary>

**Initial Prompt.** Two teams use different classic buckets for the same metric name. Can a global p99 combine them?

**L5 Textbook Answer.** Yes, `sum by (le)` merges them; Prometheus handles the different `le` values.

**Why L5 Fails at 3 AM or on the Bill.** Summing cumulative counts across *different* boundary sets produces a staircase that is not a valid cumulative distribution for either layout; `BucketQuantile` then forces monotonicity and interpolates across mismatched intervals. The number is meaningless, and no error is raised.

**L7 Principal Defense.** Classic histograms are mergeable only with identical boundaries; I enforce one bucket set per metric name (lint in CI, client-library wrappers). Native exponential histograms merge across schemas exactly (resolution reduces to the coarsest schema), and NHCBs with different bounds are reconciled to the bound intersection in 3.15. So cross-team latency aggregation is an argument for native histograms; until then, I aggregate per layout and compare quantiles side by side rather than merging.
</details>

---

## 5. Invariants checklist

- [ ] Quantiles are computed after aggregation: `sum by (…, le)` (classic) or `sum` of native histograms; never averages of quantiles.
- [ ] SLIs are count ratios; every SLO threshold is a bucket boundary (classic) or the histogram is native.
- [ ] A measurement-validity alert fires when >1% of traffic exceeds the largest finite bucket.
- [ ] `le` selectors use float formatting (`"1.0"`, `"10.0"`) after 3.0.
- [ ] Recording rules store aggregated bucket rates (classic) or aggregated native histograms; quantiles are derived from them.
- [ ] Dashboards show heatmaps for distributions and at most p50/p90/p99 lines; quantile lines are never averaged across panels.
- [ ] Mixed classic/native periods have explicit per-family queries and a cutover plan.

---

## 6. References

- `BucketQuantile`, `HistogramQuantile`, `BucketFraction`: <https://github.com/prometheus/prometheus/blob/v3.15.1/promql/quantile.go>
- Upstream histogram tests (oracle for L1): <https://github.com/prometheus/prometheus/blob/v3.15.1/promql/promqltest/testdata/histograms.test>
- Histograms and summaries practice guide: <https://prometheus.io/docs/practices/histograms/>
- Native histograms specification: <https://prometheus.io/docs/specs/native_histograms/>
- Function reference (`histogram_*`): <https://prometheus.io/docs/prometheus/latest/querying/functions/>
