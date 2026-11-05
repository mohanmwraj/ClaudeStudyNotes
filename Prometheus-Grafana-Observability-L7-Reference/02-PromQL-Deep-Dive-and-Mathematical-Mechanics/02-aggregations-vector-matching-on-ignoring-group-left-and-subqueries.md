# 02 · Aggregations, Vector Matching (on / ignoring / group_left) and Subqueries

> **Folder 02 — PromQL Deep Dive and Mathematical Mechanics · File 2 of 3.**
> Pinned to **Prometheus v3.15.1** (`promql/engine.go` `resultMetric`, `VectorBinop`, aggregation and subquery code read at tag `v3.15.1`).
> Labels: **[D]** documented / read in pinned source · **[M]** measured by a listing (deterministic, re-run by the gate) · **[E]** model · **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L3 `vector_matching_lab.py` | On the L1 engine (File 1, validated against promqltest): `sum(rate())` vs `rate(sum())` across a pod restart; an info-metric join with `on(pod) group_left(team)` and the many-to-many failure when kube-state-metrics briefly duplicates a pod; why an error-ratio alert is *absent* when no error series exists and the `or … * 0` fix; the absolute subquery grid and its cost; `topk` returning more than k series in range queries; staleness markers vs the 5-minute lookback | <1 s |

**Verification.** L3 evaluates every expression with L1 (`promql_mini.py`, File 1), whose aggregation, matching, set-operator and subquery code passes all attempted cases of upstream `aggregators.test` (122), `operators.test` (136) and `subquery.test` (32). Each section asserts the numeric outcome it prints. No live server was run.

---

## 0. Orientation

**What this file answers.** How PromQL combines series: which labels survive an aggregation or a binary operation, how two vectors are paired, what "many-to-many" means and why it appears only during incidents, how `and`/`or`/`unless` decide membership, and what a subquery actually evaluates (and costs).

**The core rule.** Every binary operation between two instant vectors is a **join on a label signature**. By default the signature is *all labels except `__name__`*; `on(l…)` restricts it to `l…`; `ignoring(l…)` removes `l…`. One-to-one is the default; `group_left`/`group_right` declare which side may have many matches. Most PromQL bugs are signature bugs.

---

## 1. First principles: aggregation and matching semantics

### 1.1 Aggregation operators [D]

```text
 <aggr>([param,] expr) [by (l…) | without (l…)]      by/without may also precede the parens
 by (l…)       → output labels = exactly l… (absent ones omitted)
 without (l…)  → output labels = input labels − l… − __name__
 none          → one group, no labels
 operators: sum avg min max count group stddev stdvar   → value per group, labels per rule above
            topk(k) bottomk(k) limitk(k) limit_ratio(r) → ORIGINAL samples (labels incl. __name__)
            quantile(φ)                                  → φ-quantile, linear interpolation, rank φ(n−1)
            count_values("lbl")                          → one series per distinct value, lbl=value
```

Numerics in 3.x [D] (all ported in L1 and checked by `aggregators.test`):

- `sum` uses **Kahan–Neumaier** compensated summation (`kahansum.Inc`); `+Inf` resets the compensation.
- `avg` sums with compensation while the sum stays finite, then switches to an **incremental mean** (`mean ← q·mean + x/n`, `q = (n−1)/n`) to survive overflow — so `avg(1e308, 1e308)` is `1e308`, not `+Inf`.
- `stddev`/`stdvar` are population statistics via Welford's update; a first value of NaN or ±Inf poisons the group to NaN.
- `min`/`max` treat NaN as "replace me": `max(NaN, 3) = 3`.
- `count_values` formats values like Go's `strconv.FormatFloat(f, 'f', -1, 64)` — `1e21` becomes `"1000000000000000000000"`.

### 1.2 Binary operators: arithmetic, comparison, set

```text
 precedence (high → low):  ^   (right-assoc)
                           unary −   (−2^2 = −4)
                           * / % atan2
                           + −
                           == != <= < >= >
                           and unless
                           or
 scalar ⊕ scalar        → scalar (comparisons need `bool`)
 vector ⊕ scalar        → per sample; arithmetic DROPS __name__; comparison FILTERS (keeps sample,
                          keeps __name__, value = the VECTOR's value even when the scalar is on the left)
 vector ⊕ vector        → join on signature; arithmetic or `bool` drops __name__
 comparison + bool      → 0/1 for every matched pair, __name__ dropped
```

### 1.3 Vector matching and `resultMetric` [D]

```text
 sig(s) = on(l…)      ? labels(s) ∩ l…
        : ignoring(l…)? labels(s) − l… − __name__
        :               labels(s) − __name__

 one-to-one (default): every sig must be unique on BOTH sides
       → duplicate on the right: "found duplicate series for the match group"
       → two left samples hit one right sample: "many-to-one matching must be explicit"
 group_left(extra…):  left = "many", right = "one" (must be unique per sig)
 group_right(extra…): mirror image

 result labels (resultMetric):
   start from the "many" side (or the left side for one-to-one)
   drop __name__ if arithmetic or bool
   one-to-one + on(l…)      → KEEP ONLY l…            (yes: `a > on(job) b` returns {job=…})
   one-to-one + ignoring(l…)→ DELETE l…
   group_x(extra…)          → copy each extra label FROM the "one" side (delete if empty there)
 any duplicate result labelset → "vector cannot contain metrics with the same labelset"
```

**The info-metric join** is the canonical use. L3 §2 [M]:

```promql
sum by (team) (
  rate(http_requests_total[5m])
  * on(pod) group_left(team)
  kube_pod_info
)
```

`kube_pod_info` (value 1) is the "one" side keyed by `pod`; `team` is copied onto each request series; the multiplication by 1 preserves the rate. Result: `payments 12/s, storefront 3/s`. Then L3 adds a second `kube_pod_info{pod="api-1"}` with a different `node` — exactly what happens for a few scrapes when kube-state-metrics restarts or a pod is rescheduled — and the query **errors**: *duplicate series for the match group*. The robust form collapses the "one" side first: `… * on(pod) group_left(team) max by (pod, team) (kube_pod_info)`.

### 1.4 Set operators and the "absent series" problem

- `a and b` — samples of `a` whose signature exists in `b` (values and labels from `a`).
- `a unless b` — samples of `a` whose signature does **not** exist in `b`.
- `a or b` — all of `a`, plus samples of `b` whose signature is not in `a`.
- Signatures for set operators also ignore `__name__` and honour `on`/`ignoring`; `group_*` is not allowed.

The alerting consequence (L3 §3 [M]): an error-ratio `sum(rate(x{code=~"5.."}[5m])) / sum(rate(x[5m]))` returns **nothing** when no 5xx series has ever been created — the alert can neither fire nor resolve, and a dashboard shows "No data" rather than 0%. Fix per group with `or`:

```promql
(
    sum by (job) (rate(http_requests_total{code=~"5.."}[5m]))
  or
    sum by (job) (rate(http_requests_total[5m])) * 0
)
/ sum by (job) (rate(http_requests_total[5m]))
```

The 3.10+ experimental `fill(0)` binop modifier (`--enable-feature=promql-binop-fill-modifiers`) expresses the same intent (`a / fill_left(0) b`), but the `or … * 0` idiom works everywhere and in every Prometheus-compatible backend.

### 1.5 Aggregation order: `sum(rate())`, never `rate(sum())`

`rate()` must see each counter individually so it can correct each counter's resets. Summing first turns one pod's restart into a "reset" of the sum. L3 §1 [M]: three pods at 2/s combined, pod b restarts → `sum(rate(x[5m])) = 2.0000/s` (exact), `rate(sum(x)[5m:15s]) = 11.05/s` — a **5.5× phantom spike**, from one restart. The same rule applies to recording rules: record `sum by (…) (rate(...))`; never record `sum(x)` and rate it later.

### 1.6 Subqueries: what is actually evaluated

`f(expr[R:S])` at time T evaluates `expr` at every multiple of `S` in `(T − offset − R, T − offset]` and feeds the resulting series to `f` as a range vector [D]:

```text
 start = S · trunc((T − o − R)/S);  if start ≤ T − o − R: start += S      (absolute grid, not T-aligned)
 inner evaluations at start, start+S, …, ≤ T − o          default S = global evaluation_interval
 example: R=10m, S=1m, T=10m30s → inner at 1m,2m,…,10m  (10 evaluations; the half-minute is ignored)
```

Costs and traps (L3 §4 [M]):

- A 24 h range query at 1 m step over `max_over_time(rate(x[1m])[10m:1m])` performs 1,440 × 10 = **14,400 inner `rate` evaluations per series**. A recording rule for the inner expression turns that into 1,440 reads of a stored series — the standard remedy for slow SLO dashboards.
- The grid is absolute, so the result does **not** move smoothly as T moves within a step; panel values "stair-step".
- `rate()` over a subquery of a counter works but sees only grid-aligned samples (resets between grid points are invisible); prefer `rate()` on the raw series inside, aggregate outside.

### 1.7 `topk` in range queries, `absent`, and label manipulation

- **`topk(k, …)` is per step.** A range query returns every series that was in the top k at *any* step — L3 §5: `topk(1, cpu)` over 30 steps returns **2** series. For "top 5 over the last hour" use `topk(5, avg_over_time(x[1h]))` evaluated as an instant query (Grafana: "Instant" toggle), or `topk(5, …) and on() …` patterns.
- **`absent(v)`** returns `{labels from equality matchers} 1` when `v` is empty; labels repeated or matched by non-equality matchers are dropped (ported and checked in L1). `absent_over_time(v[r])` does the same over a range.
- **`label_replace(v, dst, repl, src, regex)`** — regex fully anchored; Go template semantics (`${1}`); an empty replacement deletes `dst`. **`label_join`** concatenates. Both keep `__name__`.

### 1.8 Experimental operators to know (⚠ feature-flagged in 3.15)

`info(v [, selector])` joins `target_info`-style metadata without hand-written `group_left` (experimental functions flag); `fill()/fill_left()/fill_right()` binop modifiers (3.10); native-histogram trimming operators `</` and `>/` (3.11); duration expressions such as `rate(x[step()*4])` (on by default since 3.14); `limitk`/`limit_ratio` aggregations; `sort_by_label`. Use them in exploration; keep them out of SLO rules until stable, and record which flags a rule depends on.

<!-- listing:vector_matching_lab.py -->
```python
"""vector_matching_lab.py - aggregation order, vector matching, set operators, subqueries and
staleness, evaluated with promql_mini.py (the engine validated against promqltest in L1).

Sections: (1) sum(rate()) vs rate(sum()) across a counter reset; (2) joining an info metric with
on()/group_left() and the many-to-many failure during a kube-state-metrics duplicate; (3) why an
error-ratio alert disappears when the error series does not exist, and the `or` fixes; (4) the
subquery evaluation grid and its cost; (5) topk() in a range query returns more than k series;
(6) staleness markers vs the 5-minute lookback. Deterministic, stdlib only.

Usage: python vector_matching_lab.py [target.md]
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from promql_mini import STALE, Engine, EvalError, Parser  # noqa: E402

S, M = 1000, 60000


def q(eng, expr, T):
    return eng.eval(Parser(expr).parse(), T)


def fmt(vec):
    if isinstance(vec, float):
        return f"{vec:g}"
    return "; ".join(f"{dict(sorted(l.items()))} {v:.4g}" for l, v, _ in sorted(vec, key=lambda s: sorted(s[0].items()))) or "<empty>"


def main():
    checks = []
    print("== 1. sum(rate()) vs rate(sum()) when one of three pods restarts ==")
    eng = Engine()
    for pod in ("a", "b", "c"):
        pts = []
        for i in range(0, 41):
            v = 1000.0 + 10 * i
            if pod == "b" and i >= 30:
                v = 10.0 * (i - 29)  # pod b restarted just before 7m30s: counts again from 0
            pts.append((i * 15 * S, v))
        eng.add({"__name__": "http_requests_total", "pod": pod}, pts)
    T = 10 * M
    good = q(eng, "sum(rate(http_requests_total[5m]))", T)[0][1]
    bad = q(eng, "rate(sum(http_requests_total)[5m:15s])", T)[0][1]
    print(f"sum(rate(x[5m]))           = {good:.4f}/s  (true: 3 pods x 10 per 15 s = 2.0/s)")
    print(f"rate(sum(x)[5m:15s])       = {bad:.4f}/s  (the drop of pod b's counter looks like a reset of the SUM)")
    checks.append(("sum-of-rates correct", abs(good - 2.0) < 1e-9))
    checks.append(("rate-of-sum wrong", abs(bad - 2.0) > 0.5))
    print()

    print("== 2. Info-metric join: on(pod) group_left(team) and the many-to-many trap ==")
    eng2 = Engine()
    for pod, rate in (("api-1", 5), ("api-2", 7), ("web-1", 3)):
        eng2.add({"__name__": "http_requests_total", "pod": pod}, [(i * 15 * S, float(rate * 15 * i)) for i in range(0, 41)])
    for pod, team in (("api-1", "payments"), ("api-2", "payments"), ("web-1", "storefront")):
        eng2.add({"__name__": "kube_pod_info", "pod": pod, "team": team, "node": "n1"}, [(i * 15 * S, 1.0) for i in range(0, 41)])
    expr = 'sum by (team) (rate(http_requests_total[5m]) * on(pod) group_left(team) kube_pod_info)'
    res = q(eng2, expr, T)
    print(f"{expr}\n  -> {fmt(res)}")
    checks.append(("join", sorted((l['team'], round(v, 6)) for l, v, _ in res) == [("payments", 12.0), ("storefront", 3.0)]))
    # kube-state-metrics restarts and briefly exposes the pod twice (different 'uid'/'node' label)
    eng2.add({"__name__": "kube_pod_info", "pod": "api-1", "team": "payments", "node": "n2"}, [(i * 15 * S, 1.0) for i in range(36, 41)])
    try:
        q(eng2, expr, T)
        failed_join = False
        print("  duplicate kube_pod_info: no error (unexpected)")
    except EvalError as e:
        failed_join = True
        print(f"  with a duplicate kube_pod_info{{pod=\"api-1\"}} series: ERROR {e}")
    fixed = 'sum by (team) (rate(http_requests_total[5m]) * on(pod) group_left(team) max by (pod, team) (kube_pod_info))'
    res2 = q(eng2, fixed, T)
    print(f"  fix: collapse the 'one' side first -> {fmt(res2)}")
    checks.append(("many-to-many detected", failed_join))
    checks.append(("fixed join", sorted(round(v, 6) for _, v, _ in res2) == [3.0, 12.0]))
    print()

    print("== 3. Error-ratio alerts and missing series ==")
    eng3 = Engine()
    eng3.add({"__name__": "http_requests_total", "job": "checkout", "code": "200"}, [(i * 15 * S, 100.0 * i) for i in range(0, 41)])
    naive = 'sum by (job) (rate(http_requests_total{code=~"5.."}[5m])) / sum by (job) (rate(http_requests_total[5m]))'
    r = q(eng3, naive, T)
    print(f"no 5xx series has ever existed -> naive ratio: {fmt(r)}  (an alert on it can never fire OR resolve)")
    fix = ('(sum by (job) (rate(http_requests_total{code=~"5.."}[5m])) or sum by (job) (rate(http_requests_total[5m])) * 0)'
           ' / sum by (job) (rate(http_requests_total[5m]))')
    r2 = q(eng3, fix, T)
    print(f"`or ... * 0` fills the gap per job -> {fmt(r2)}")
    absent_expr = 'absent(up{job="checkout"})'
    r3 = q(eng3, absent_expr, T)
    print(f"{absent_expr} with no up series -> {fmt(r3)} (labels come from the selector's equality matchers)")
    checks.append(("naive empty", len(r) == 0))
    checks.append(("fixed zero", len(r2) == 1 and r2[0][1] == 0.0 and r2[0][0] == {"job": "checkout"}))
    unless = q(eng3, 'http_requests_total unless on(job) http_requests_total{code="500"}', T)
    print(f"`unless on(job)` keeps lhs series whose job has no 500s -> {len(unless)} series")
    print()

    print("== 4. Subquery grid: max_over_time(rate(x[1m])[10m:1m]) evaluated at T = 10m30s ==")
    T4 = 10 * M + 30 * S
    rng, step = 10 * M, 1 * M
    base = T4 - rng
    start = step * int(base / step)
    if start <= base:
        start += step
    grid = list(range(start, T4 + 1, step))
    print(f"inner evaluations at {[t // S for t in grid]} s ({len(grid)} steps, aligned to absolute multiples of 1m, "
          f"NOT to T)")
    v = q(eng, 'max_over_time(rate(http_requests_total{pod="a"}[1m])[10m:1m])', T4)
    print(f"result {fmt(v)}; cost = {len(grid)} inner rate() evaluations x series per outer step")
    checks.append(("grid aligned", all(t % step == 0 for t in grid) and len(grid) == 10))
    print("a range query over 24h at step 1m therefore runs 1440 x 10 = 14,400 inner evaluations per series; "
          "a recording rule for rate(x[1m]) turns that into 1440 reads")
    print()

    print("== 5. topk(1, ...) in a range query returns more than one series ==")
    eng5 = Engine()
    for pod, shift in (("p1", 0), ("p2", 5)):
        eng5.add({"__name__": "cpu", "pod": pod}, [(i * M, float((i + shift) % 10)) for i in range(0, 31)])
    winners = set()
    for t in range(0, 31 * M, M):
        res = q(eng5, "topk(1, cpu)", t)
        winners.update(l["pod"] for l, _, _ in res)
    print(f"distinct series returned by topk(1, cpu) over 30 one-minute steps: {sorted(winners)}")
    checks.append(("topk flips", len(winners) == 2))
    print()

    print("== 6. Staleness marker vs 5-minute lookback ==")
    eng6 = Engine()
    eng6.add({"__name__": "up", "instance": "with-marker"}, [(i * 15 * S, 1.0) for i in range(0, 21)] + [(21 * 15 * S, STALE)])
    eng6.add({"__name__": "up", "instance": "no-marker"}, [(i * 15 * S, 1.0) for i in range(0, 21)])
    for t_s in (300, 330, 400, 600, 610):
        res = q(eng6, "up", t_s * S)
        print(f"t={t_s:>3}s up -> {sorted(l['instance'] for l, _, _ in res)}")
    gone = q(eng6, "up", 330 * S)
    checks.append(("marker hides immediately", [l["instance"] for l, _, _ in gone] == ["no-marker"]))
    checks.append(("lookback expires", len(q(eng6, "up", 610 * S)) == 0))
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:vector_matching_lab.py -->
```text
== 1. sum(rate()) vs rate(sum()) when one of three pods restarts ==
sum(rate(x[5m]))           = 2.0000/s  (true: 3 pods x 10 per 15 s = 2.0/s)
rate(sum(x)[5m:15s])       = 11.0526/s  (the drop of pod b's counter looks like a reset of the SUM)

== 2. Info-metric join: on(pod) group_left(team) and the many-to-many trap ==
sum by (team) (rate(http_requests_total[5m]) * on(pod) group_left(team) kube_pod_info)
  -> {'team': 'payments'} 12; {'team': 'storefront'} 3
  with a duplicate kube_pod_info{pod="api-1"} series: ERROR found duplicate series for the match group on the 'one' side
  fix: collapse the 'one' side first -> {'team': 'payments'} 12; {'team': 'storefront'} 3

== 3. Error-ratio alerts and missing series ==
no 5xx series has ever existed -> naive ratio: <empty>  (an alert on it can never fire OR resolve)
`or ... * 0` fills the gap per job -> {'job': 'checkout'} 0
absent(up{job="checkout"}) with no up series -> {'job': 'checkout'} 1 (labels come from the selector's equality matchers)
`unless on(job)` keeps lhs series whose job has no 500s -> 1 series

== 4. Subquery grid: max_over_time(rate(x[1m])[10m:1m]) evaluated at T = 10m30s ==
inner evaluations at [60, 120, 180, 240, 300, 360, 420, 480, 540, 600] s (10 steps, aligned to absolute multiples of 1m, NOT to T)
result {'pod': 'a'} 0.6667; cost = 10 inner rate() evaluations x series per outer step
a range query over 24h at step 1m therefore runs 1440 x 10 = 14,400 inner evaluations per series; a recording rule for rate(x[1m]) turns that into 1440 reads

== 5. topk(1, ...) in a range query returns more than one series ==
distinct series returned by topk(1, cpu) over 30 one-minute steps: ['p1', 'p2']

== 6. Staleness marker vs 5-minute lookback ==
t=300s up -> ['no-marker', 'with-marker']
t=330s up -> ['no-marker']
t=400s up -> ['no-marker']
t=600s up -> []
t=610s up -> []

checks: 11/11 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 Joins and enrichment as recording rules

```yaml
groups:
  - name: enrichment
    interval: 30s
    rules:
      # De-duplicated "one" side: survives kube-state-metrics restarts and pod reschedules
      - record: pod_team:kube_pod_info:max
        expr: max by (namespace, pod, team) (kube_pod_info{team!=""})
      # Cost/ownership attribution: requests per team
      - record: team:http_server_requests:rate5m
        expr: |
          sum by (team) (
            sum by (namespace, pod) (rate(http_server_requests_seconds_count[5m]))
            * on (namespace, pod) group_left (team)
            pod_team:kube_pod_info:max
          )
      # Container CPU per workload (cAdvisor x kube-state-metrics owner join)
      - record: namespace_workload:container_cpu_usage_seconds:rate5m
        expr: |
          sum by (namespace, workload) (
            rate(container_cpu_usage_seconds_total{container!=""}[5m])
            * on (namespace, pod) group_left (workload)
            max by (namespace, pod, workload) (
              label_replace(kube_pod_owner{owner_kind="ReplicaSet"}, "workload", "$1", "owner_name", "(.*)-[a-z0-9]+")
            )
          )
```

### 2.2 Alert expressions that survive missing series

```yaml
groups:
  - name: robust-alerts
    rules:
      - alert: HighErrorRatio
        expr: |
          (
              sum by (job) (rate(http_server_requests_seconds_count{code=~"5.."}[5m]))
            or
              sum by (job) (rate(http_server_requests_seconds_count[5m])) * 0
          )
          / sum by (job) (rate(http_server_requests_seconds_count[5m]))
          > 0.05
        for: 10m
        labels: {severity: page}
        annotations:
          summary: "{{ $labels.job }}: {{ $value | humanizePercentage }} 5xx"
      - alert: JobMissing
        expr: absent(up{job="checkout"})
        for: 10m
        labels: {severity: page}
        annotations:
          summary: "No up series for job=checkout: discovery or relabeling dropped every target"
      - alert: SomeTargetsDown
        expr: |
          sum by (job) (up == 0) / count by (job) (up) > 0.2
        for: 5m
        labels: {severity: warning}
```

### 2.3 Range-query hygiene for dashboards

```promql
# Top 5 routes over the dashboard window, as an INSTANT query (no per-step churn)
topk(5, sum by (route) (increase(http_server_requests_seconds_count{job="checkout"}[$__range])))

# Ratio panels: same window and the SAME `by` labels on both sides, so signatures match 1:1
sum by (route) (rate(http_server_requests_seconds_count{job="checkout", code=~"5.."}[$__rate_interval]))
  /
sum by (route) (rate(http_server_requests_seconds_count{job="checkout"}[$__rate_interval]))
```

---

## 3. Failure modes and FinOps debugging

### F1. "many-to-many matching not allowed" — only during incidents

**Symptom.** A team-attribution dashboard and an alert using `group_left` fail with match-group errors for a few minutes during node drains or kube-state-metrics restarts — exactly when they are needed.

**Signature.** Query error mentioning duplicate series for the match group; `count by (pod) (kube_pod_info) > 1` returns pods; ksm restarted (`changes(process_start_time_seconds{job="kube-state-metrics"}[10m]) > 0`).

**Root cause.** The "one" side is unique *most* of the time. Pod rescheduling, ksm sharding changes or HA ksm replicas briefly expose two series per pod (different `node`, `uid` or `instance`).

**Fix.** Collapse the one side to exactly the join key + copied labels (`max by (namespace, pod, team) (...)`), ideally as a recording rule (§2.1).

**Prevention.** Never join directly against raw info metrics in alerts; lint for `group_left` whose right side is not an aggregation.

### F2. Phantom traffic from `rate(sum())`

**Symptom.** A recording rule `job:requests:sum` followed by `rate(job:requests:sum[5m])` shows huge spikes on every deploy.

**Signature.** Spikes coincide with pod restarts; `resets(job:requests:sum[1h])` > 0.

**Root cause.** Summing counters before `rate` turns any individual reset into a reset of the sum, and the full pre-reset sum is added (L3 §1: 5.5× from one restart).

**Fix.** Record `sum by (job) (rate(x[5m]))`; delete rules that sum raw counters.

**Prevention.** Rule review checklist: `rate`/`increase` must be the innermost operation on counters.

### F3. Ratio alerts that never fire

**Symptom.** A service had a 30-minute 100%-error outage of a new endpoint; the error-ratio alert stayed green.

**Signature.** The numerator has no series for that job/route until the first error; `count(x{code=~"5.."})` was 0 before the incident; the alert expression returns empty, not 0.

**Root cause.** Arithmetic on an absent series yields no result; `> 0.05` on nothing is nothing (L3 §3).

**Fix.** `or … * 0` per group (§1.4), or initialise counters at startup with zero for known label values (client libraries' `WithLabelValues(...)` at init).

**Prevention.** Unit-test alerts with promtool fixtures that include the "no error series yet" case.

### F4. `on()` comparison returns fewer labels than expected

**Symptom.** `node_load1 > on(instance) node_cpu_count * 2` returns series with only `instance`; downstream routing by `job` breaks.

**Signature.** Result series lack labels present in the left operand.

**Root cause.** For one-to-one matching with `on(l…)`, `resultMetric` keeps **only** `l…` — even for filtering comparisons [D].

**Fix.** Use `ignoring(…)` with the differing labels, or `group_left` (which keeps the left side's labels).

**Prevention.** Know `resultMetric`'s rules (§1.3); add label assertions to rule unit tests.

### F5. Subquery dashboards that time out

**Symptom.** An SLO dashboard with `max_over_time(rate(x[5m])[30d:5m])` takes minutes and trips `--query.max-samples`.

**Signature.** Query log shows huge `samples` counts; `prometheus_engine_query_samples_total` spikes; the panel is the top entry in the query log.

**Root cause.** Each outer step re-evaluates the inner expression at every grid point over 30 days; cost = steps × (R/S) × series × samples per inner window.

**Fix.** Record the inner expression (`…:rate5m`) and query `max_over_time(recorded[30d])`; or compute long windows from recorded hourly aggregates.

**Prevention.** Lint dashboards for subqueries with R/S > 100; prefer recording rules for anything on a shared dashboard.

### F6. `topk` panels with 30 legend entries

**Symptom.** A "Top 5 pods by CPU" time-series panel shows dozens of pods; users think the query is broken.

**Signature.** Range query; `topk` inside; series churn across steps.

**Root cause.** Range queries evaluate `topk` independently per step (L3 §5).

**Fix.** Make it an instant query over the window (`topk(5, avg_over_time(x[$__range]))`) or a bar gauge; for time series, select the top-k set once and join: `x and on(pod) topk(5, avg_over_time(x[$__range] @ end()))` (with `@` support).

**Prevention.** Dashboard guidelines: `topk` belongs in instant/table panels.

### F7. `label_replace` silently does nothing

**Symptom.** A `workload` label derived with `label_replace` is missing for some pods.

**Signature.** Pod names that do not match the regex exactly; regex written as if unanchored.

**Root cause.** The regex is fully anchored (`^(?:…)$`): `-[a-z0-9]+` must match to the end of the string; non-matching input leaves the series unchanged (no `workload`).

**Fix.** Write the full pattern (`(.*)-[a-z0-9]{8,10}-[a-z0-9]{5}` for ReplicaSet pods), or join on `kube_pod_owner` instead of parsing names.

**Prevention.** Unit tests with real pod-name fixtures (Deployment, StatefulSet, Job, CronJob patterns).

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "Explain group_left with an example where it is required."</b></summary>

**Initial Prompt.** When do you need `group_left`, and what labels does the result have?

**L5 Textbook Answer.** When joining a metric with many series to one with fewer, like adding team labels; the result has the left side's labels plus the ones in group_left.

**Why L5 Fails at 3 AM or on the Bill.** It misses uniqueness on the "one" side — the failure that only appears during reschedules — and the label-copy semantics (copied *from the one side*, deleted if empty there), so it cannot debug missing `team` labels or match errors.

**L7 Principal Defense.** Signature = `on(...)` labels; the right side must be unique per signature; result labels start from the left (many) sample, `__name__` dropped for arithmetic, and each `group_left(l)` label is copied from the matched right sample. I always collapse the right side with `max by (key, copied) (...)` because ksm restarts duplicate info series (L3 §2), and I record the enrichment so alerts don't depend on it at query time.
</details>

<details><summary><b>Q2 · "Why is rate(sum(x)) wrong if sum(rate(x)) is right?"</b></summary>

**Initial Prompt.** Mathematically, isn't the rate of a sum the sum of rates?

**L5 Textbook Answer.** For continuous functions yes, but Prometheus handles resets per series, so the order matters a little.

**Why L5 Fails at 3 AM or on the Bill.** "A little" is a 5.5× phantom spike per restart (L3 §1) — the kind that pages people and triggers autoscalers.

**L7 Principal Defense.** Linearity holds for derivatives of smooth functions; counters are piecewise with resets, and reset correction is non-linear (it adds the pre-reset value). Correction needs to see each counter's own decrease, so `rate` must be innermost. In recording rules: `sum by (..) (rate(x[5m]))`, never `rate()` of a recorded sum. Same for `increase` and `irate`.
</details>

<details><summary><b>Q3 · "An error-ratio alert missed a total outage. Why?"</b></summary>

**Initial Prompt.** A new endpoint returned 100% 5xx for 30 minutes; `errors/total > 0.05` never fired.

**L5 Textbook Answer.** Maybe the `for:` clause was too long or the scrape failed.

**Why L5 Fails at 3 AM or on the Bill.** The expression was *empty*, not low: no 5xx series existed for that route until the first error was counted, and if the route's counters were only created on first use, even the denominator was missing. Tuning `for:` changes nothing.

**L7 Principal Defense.** Absent operands produce empty results; comparisons on empty vectors are empty. I fix with `or (… * 0)` per group, pre-initialise counters for known label values at startup, add an `absent()`/`absent_over_time()` alert for the job, and unit-test the "no errors yet" path with promtool. Then SLO burn-rate alerts (Folder 04) inherit the same construction.
</details>

<details><summary><b>Q4 · "What does a subquery cost?"</b></summary>

**Initial Prompt.** Our SLO dashboard uses `max_over_time(rate(x[5m])[7d:1m])` and is slow. Why, and how do you fix it?

**L5 Textbook Answer.** Subqueries are expensive because they look at a lot of data; use a shorter range.

**Why L5 Fails at 3 AM or on the Bill.** Shortening the range changes the SLO semantics; the cost driver is the *product* steps × (R/S) × series, and a recording rule removes it without changing semantics.

**L7 Principal Defense.** Inner evaluations = R/S per outer step on an absolute grid (L3 §4): 7 d at 1 m = 10,080 inner `rate`s per series per step. I record `rate(x[5m])` (it's already needed for alerts), then query `max_over_time(recorded[7d])`, which reads 10,080 stored samples once. Cost falls by orders of magnitude and the value is identical up to grid alignment.
</details>

<details><summary><b>Q5 · "Write a query for CPU per Kubernetes workload."</b></summary>

**Initial Prompt.** Give me CPU usage per Deployment from cAdvisor.

**L5 Textbook Answer.** `sum by (pod) (rate(container_cpu_usage_seconds_total[5m]))` and then group pods by name prefix.

**Why L5 Fails at 3 AM or on the Bill.** Name-prefix parsing breaks on StatefulSets/Jobs and on hashes of different lengths; cAdvisor also exposes pod-level cgroup series (`container=""`) that double-count; and the result is per pod, not per workload.

**L7 Principal Defense.** Exclude aggregate cgroups (`container!=""`), rate per container, join on `(namespace, pod)` with an owner mapping derived from `kube_pod_owner` (ReplicaSet → Deployment via `kube_replicaset_owner`), collapse the mapping with `max by`, and record it (§2.1). kube-prometheus's `namespace_workload_pod:kube_pod_owner:relabel` mixin rule exists for exactly this.
</details>

<details><summary><b>Q6 · "Why does `topk(5, …)` return 30 series on my graph?"</b></summary>

**Initial Prompt.** Explain and fix.

**L5 Textbook Answer.** Probably a Grafana bug, or the series changed names.

**Why L5 Fails at 3 AM or on the Bill.** Range queries are independent instant evaluations; topk picks per step (L3 §5). Blaming Grafana wastes the incident.

**L7 Principal Defense.** Per-step evaluation is the PromQL model. For a stable top-k set: compute the set once over the window (`topk(5, avg_over_time(x[$__range]))`, instant) and either show it as a table/bar or filter the time series with `and on(pod)` against that set evaluated at the range end (`@ end()`).
</details>

<details><summary><b>Q7 · "When would you use `unless` in an alert?"</b></summary>

**Initial Prompt.** Give a real example of `unless`.

**L5 Textbook Answer.** To exclude some series, like `up == 0 unless on(job) maintenance`.

**Why L5 Fails at 3 AM or on the Bill.** Correct shape, but without explaining signatures it will silently match nothing (label mismatch) — maintenance suppression that never suppresses, or suppresses everything.

**L7 Principal Defense.** `unless` keeps left samples whose signature is absent on the right. Real uses: "targets down unless the node is cordoned" (`up == 0 unless on(node) kube_node_spec_unschedulable == 1` after mapping instance→node), "deprecated API in use unless allow-listed". I make the `on(...)` keys explicit, verify both sides carry them, and unit-test both branches. For time-based suppression, Alertmanager silences/inhibitions or `time_intervals` are cleaner (Folder 04).
</details>

<details><summary><b>Q8 · "How do Prometheus aggregations stay numerically accurate?"</b></summary>

**Initial Prompt.** We sum 50,000 series of large byte counters; can floating-point error matter?

**L5 Textbook Answer.** float64 has ~15 digits of precision, so it's fine.

**Why L5 Fails at 3 AM or on the Bill.** Naive summation of many values of mixed magnitude loses small terms; averages of huge values overflow to Inf; these show up as SLO ratios off by more than the budget at five nines.

**L7 Principal Defense.** 3.x uses Kahan–Neumaier compensation in `sum`, `avg`, `sum_over_time`, `avg_over_time` and regression; `avg` switches to an incremental mean on overflow; stddev uses Welford. L1 ports these and passes the upstream precision tests. For SLO math at 99.999%, I still compute ratios from counts (not averages of ratios) and keep the numerator/denominator in the same aggregation.
</details>

---

## 5. Invariants checklist

- [ ] `rate`/`increase` innermost on counters; recording rules never `rate()` a recorded sum.
- [ ] Every `group_left`/`group_right` "one" side is collapsed to its join key + copied labels (`max by (...)`), preferably recorded.
- [ ] Ratio alerts handle absent numerators (`or … * 0`) and have a companion `absent()` alert for the job.
- [ ] `on(...)` vs `ignoring(...)` chosen consciously: one-to-one `on()` keeps only the `on` labels.
- [ ] No subquery with R/S > 100 on shared dashboards; inner expressions are recorded.
- [ ] `topk`/`bottomk` appear in instant/table panels or with an explicitly fixed set.
- [ ] `label_replace` regexes are written as full matches and unit-tested with real label values.
- [ ] Experimental operators (`fill`, `info`, trimming, `limitk`) are absent from SLO and paging rules.

---

## 6. References

- Operators (vector matching, `group_left`, set operators, precedence): <https://prometheus.io/docs/prometheus/latest/querying/operators/>
- Aggregation operators and functions: <https://prometheus.io/docs/prometheus/latest/querying/operators/#aggregation-operators>
- Subqueries: <https://prometheus.io/docs/prometheus/latest/querying/basics/#subquery>
- Engine source (`resultMetric`, `VectorBinop`, aggregation, subquery grid): <https://github.com/prometheus/prometheus/blob/v3.15.1/promql/engine.go>
- Upstream tests used as oracle: <https://github.com/prometheus/prometheus/blob/v3.15.1/promql/promqltest/testdata/operators.test>, <https://github.com/prometheus/prometheus/blob/v3.15.1/promql/promqltest/testdata/aggregators.test>, <https://github.com/prometheus/prometheus/blob/v3.15.1/promql/promqltest/testdata/subquery.test>
- kube-prometheus mixin recording rules (workload attribution): <https://github.com/prometheus-operator/kube-prometheus>
- Julien Pivotto and Brian Brazil, *Prometheus: Up & Running*, 2nd ed. (O'Reilly, 2023), chapters on PromQL aggregation and operators.
