# 01 · Recording Rules: Naming Conventions, level:metric:operations and Pre-Aggregation

> **Folder 04 — Recording Rules, Alertmanager and SLO Error-Budget Math · File 1 of 4.**
> Pinned to **Prometheus v3.15.1** (`docs/configuration/recording_rules.md`, `rules/` package read at tag `v3.15.1`).
> Labels: **[D]** documented / read in pinned source · **[M]** measured by the listing (deterministic, re-run by the gate) · **[E]** model · **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L1 `rules_lab.py` | A linter for the `level:metric:operations` convention (level must equal the `by` labels, operations must name the window, metric must name the source, no `rate()` over recorded sums, no `irate` in rules) run on a sample catalog; the series and query-cost arithmetic of pre-aggregation with the recorded expression evaluated by the Folder 02 engine (192,000 raw bucket series → 240; a 30-day p99 panel from 33 G samples to 2 M); and rule-group ordering (same-group freshness vs cross-group lag up to one interval) | <1 s |

**Verification.** The linter's verdicts on the 7-rule catalog are asserted (3 conforming, 4 violations, each for a documented reason). The recorded expression's output shape is checked by evaluating it with `promql_mini.py` on a slice of the fleet. Cost numbers are arithmetic over stated inputs [E]. No live server was run.

---

## 0. Orientation

**What this file answers.** Why recording rules exist, how to name them so a 10,000-rule estate stays navigable, which expressions to record (and which never to), how rule groups evaluate, and how recorded series change the economics of dashboards, alerts and remote storage.

**Three jobs of a recording rule.**

1. **Speed** — precompute expensive aggregations once per interval instead of per dashboard refresh per viewer.
2. **Correctness by construction** — encode the right order of operations (`sum(rate())`, `sum by (le)`) once, so every consumer inherits it.
3. **Cost and portability** — ship low-cardinality aggregates to long-term storage and drop the raw series (Folder 01 File 4 `write_relabel_configs`), and give alerts a stable, testable input.

---

## 1. First principles: what a recording rule is and costs

### 1.1 Evaluation model [D]

```text
 rule group "http.rules" interval 30s  (offset from a hash of the group, so groups spread over time)
   t0: rule 1  record job:http_requests:rate5m  = sum by (job) (rate(http_requests_total[5m]))
       rule 2  record job:http_errors:ratio_rate5m = … job:http_requests:rate5m …   ◄─ sees rule 1's
                                                                                     value from t0
   results are written to the TSDB (WAL + head) as ordinary samples with timestamp t0 − query_offset
 other groups: independent schedules; a rule reading another group's output sees its LAST evaluation
```

- Rules in a group run **sequentially** at the same timestamp; later rules see earlier rules' fresh output. Across groups there is no ordering — a consumer in another group lags by up to one interval (L1 §3: 5–30 s at 30 s). 3.x's `--enable-feature=concurrent-rule-eval` runs *independent* rules concurrently (dependency analysis keeps dependents ordered), bounded by `--rules.max-concurrent-evals`.
- `query_offset` (per group) / `global.rule_query_offset` evaluates "in the past" — essential when inputs arrive late (remote write, OTLP, federation) or when using `smoothed` selectors.
- `limit` caps output series per rule (protects against a rule that suddenly fans out).
- Group-level `labels` are added to every rule's output.
- A recorded series is a normal series: it costs head memory, WAL, index and disk like any other (Folder 01) — record what is *used*, not everything.

### 1.2 The `level:metric:operations` convention [D]

```text
 job_route:http_request_duration_seconds_bucket:rate5m
 └──┬────┘ └───────────────┬────────────────────┘ └─┬──┘
  level:   the labels the output is aggregated BY     operations: newest first
           (job, route)                                (rate5m; ratio_rate5m; p99_5m; sum)
           metric: the source metric, unchanged except `_total` dropped once rate()d
```

Rules of thumb from the Prometheus docs, enforced by L1's linter [M]:

| Rule | Example violation | Why it matters |
|---|---|---|
| Name has exactly three colon-separated parts | `http_requests_per_second` | Recorded vs raw series must be distinguishable at a glance; colons are reserved for rules |
| `level` = the `by` labels | `job:http_requests:rate1m` built `by (job, code)` | Consumers trust the name to know what they can `sum by` next |
| `operations` names the window | `…:rate1m` computed over `[5m]` | Mismatched windows silently change alert sensitivity |
| `metric` names the source | `job:errors:…` from `http_errors_total` | Grep-ability from raw metric to every derived series |
| Never `rate()` a recorded sum | `rate(job:http_requests:sum[5m])` | Member resets become resets of the sum (Folder 02 File 2: 5.5× phantom spikes) |
| No `irate` in rules | `job:errors:irate1m` | Records two-sample noise as if it were a trend |

### 1.3 What to record (and what not to)

```text
 RECORD                                              DO NOT RECORD
 rates of counters, aggregated to service level      raw counters "for convenience" (doubles storage)
 sum by (…, le) of bucket rates (keep le!)           histogram_quantile outputs ONLY (can't re-aggregate)
 SLI numerators and denominators separately          ratios ONLY (can't re-aggregate across services/time)
 ratios for direct alerting (in addition)            anything nobody queries (Folder 08 usage analysis)
 joins with info metrics (de-duplicated one side)    per-pod series that are aggregated anyway
```

The single most important design rule: **record numerators and denominators, not just ratios and quantiles.** `avg_over_time(ratio[30d])` is not the 30-day ratio (it weights every interval equally regardless of traffic); `sum_over_time(numerator[30d]) / sum_over_time(denominator[30d])` is. SLO math (File 2) depends on this.

### 1.4 The cost model of pre-aggregation (L1 §2)

A latency histogram over 200 pods × 20 routes × 4 codes × 12 buckets is **192,000 series**. The p99-per-route dashboard needs only `sum by (job, route, le)`: **240 series** (800× fewer). A 30-day panel at a 5-minute step:

| Source | Samples touched | vs `--query.max-samples` (50 M) |
|---|---|---|
| raw buckets, 5m rate per step | ~33,200,000,000 | fails |
| recorded `job_route:…:rate5m` | ~2,070,000 | fine (16,000× less) |

The same ratio applies to remote-write egress and long-term storage if the recorded series are shipped and the raw ones are not.

<!-- listing:rules_lab.py -->
```python
"""rules_lab.py - recording rules as an engineering artefact: a linter for the level:metric:operations
naming convention, the query-cost arithmetic of pre-aggregation (evaluated with promql_mini.py from
Folder 02), and rule-group evaluation ordering.

Convention (Prometheus docs "Recording rules" best practices): level:metric:operations where
level = the labels the output is aggregated BY (e.g. job, instance_path), metric = the source
metric name without _total when rate()d, operations = newest first (rate5m, ratio_rate5m, sum, max).
Deterministic, stdlib only.

Usage: python rules_lab.py [target.md]
"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from promql_mini import Engine, Parser  # noqa: E402

S, M = 1000, 60000


def lint(rule):
    name, expr = rule["record"], " ".join(rule["expr"].split())
    parts = name.split(":")
    if len(parts) != 3:
        return [f"name '{name}' is not level:metric:operations"]
    level, metric, ops = parts
    issues = []
    by = re.search(r"\b(?:sum|avg|max|min|count|quantile|stddev|stdvar)\s+by\s*\(([^)]*)\)", expr)
    if by:
        labels = [l.strip() for l in by.group(1).split(",") if l.strip() and l.strip() != "le"]
        if level != "_".join(labels) and set(level.split("_")) != set(labels):
            issues.append(f"level '{level}' != aggregation labels {labels}")
    win = re.search(r"\[(\d+[smhd])\]", expr)
    if re.search(r"\brate\(", expr) and win and f"rate{win.group(1)}" not in ops:
        issues.append(f"operations '{ops}' does not mention rate{win.group(1)}")
    src = re.search(r"\(\s*([a-zA-Z_][a-zA-Z0-9_:]*)\s*(?:\{|\[)", expr)
    if src and ":" not in src.group(1):
        s_ = src.group(1)
        stem = "_".join(s_.split("_")[:2])
        if metric not in (s_, re.sub(r"_total$", "", s_)) and not metric.startswith(stem):
            issues.append(f"metric '{metric}' does not name the source '{s_}'")
    if re.search(r"\brate\(\s*[a-z_]+:[a-z_0-9]+:[a-z_0-9]*\b", expr) and re.search(r":[a-z_0-9]*sum\b", expr):
        issues.append("rate() over a recorded SUM: resets of members become resets of the sum")
    if "irate(" in expr:
        issues.append("irate() in a recording rule: records last-two-samples noise")
    return issues


CATALOG = [
    {"record": "job:http_requests:rate5m", "expr": "sum by (job) (rate(http_requests_total[5m]))"},
    {"record": "job_route:http_request_duration_seconds_bucket:rate5m",
     "expr": "sum by (job, route, le) (rate(http_request_duration_seconds_bucket[5m]))"},
    {"record": "instance:node_cpu_utilisation:rate5m",
     "expr": 'avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))'},
    {"record": "http_requests_per_second", "expr": "sum(rate(http_requests_total[5m]))"},
    {"record": "job:http_requests:rate1m", "expr": "sum by (job, code) (rate(http_requests_total[5m]))"},
    {"record": "job:http_requests_total:rate5m", "expr": "rate(job:http_requests:sum[5m])"},
    {"record": "job:errors:irate1m", "expr": "sum by (job) (irate(http_errors_total[1m]))"},
]


def main():
    checks = []
    print("== 1. Naming-convention lint on a sample rule catalog ==")
    flagged = 0
    for r in CATALOG:
        iss = lint(r)
        flagged += bool(iss)
        print(f"{'OK  ' if not iss else 'FAIL'} {r['record']:<52} {'; '.join(iss)}")
    checks.append(("3 good, 4 bad", flagged == 4))
    print()

    print("== 2. Pre-aggregation: what a recording rule saves a dashboard ==")
    eng = Engine()
    pods, routes, codes, les = 200, 20, 4, 12
    raw_series = pods * routes * codes * les
    for p in range(10):  # small slice actually loaded; costs scale linearly
        for r in range(routes):
            for le in range(les):
                eng.add({"__name__": "http_request_duration_seconds_bucket", "job": "api", "pod": f"p{p}",
                         "route": f"/r{r}", "code": "200", "le": str(le)}, [(i * 15 * S, float(i * (le + 1))) for i in range(41)])
    q = "sum by (job, route, le) (rate(http_request_duration_seconds_bucket[5m]))"
    out = eng.eval(Parser(q).parse(), 10 * M)
    print(f"raw bucket series: {pods} pods x {routes} routes x {codes} codes x {les} le = {raw_series:,}")
    rec_series = routes * les
    print(f"recorded job_route:...:rate5m series: {routes} routes x {les} le = {rec_series} "
          f"({raw_series // rec_series}x fewer); engine check on a 10-pod slice -> {len(out)} output series")
    checks.append(("record shape", len(out) == routes * les))
    steps, samples_per_window = 30 * 24 * 60 // 5, 20  # 30d dashboard at 5m step, 5m window @15s
    raw_cost = raw_series * steps * samples_per_window
    rec_cost = rec_series * steps * 1
    print(f"30-day p99 panel at 5m step: raw = {raw_cost:,.0f} samples touched; recorded = {rec_cost:,.0f} "
          f"({raw_cost / rec_cost:,.0f}x less) -- and --query.max-samples is 50,000,000")
    checks.append(("raw exceeds max-samples", raw_cost > 50_000_000 > rec_cost))
    print()

    print("== 3. Rule-group ordering: same group vs separate groups ==")
    print("Rules in ONE group run sequentially at the same timestamp; a later rule sees the earlier rule's")
    print("fresh output. Across groups there is no ordering: a dependent group reads the previous evaluation.")
    interval = 30
    lag_same, lag_cross = 0, []
    for phase in range(0, interval, 5):  # group B's evaluation phase relative to group A
        lag_cross.append((interval - phase) % interval or interval)
    print(f"interval {interval}s: dependent rule staleness, same group = {lag_same}s; separate groups = "
          f"{min(lag_cross)}..{max(lag_cross)}s depending on phase (hash-based group offsets)")
    checks.append(("cross-group lag up to interval", max(lag_cross) == interval))
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:rules_lab.py -->
```text
== 1. Naming-convention lint on a sample rule catalog ==
OK   job:http_requests:rate5m                             
OK   job_route:http_request_duration_seconds_bucket:rate5m 
OK   instance:node_cpu_utilisation:rate5m                 
FAIL http_requests_per_second                             name 'http_requests_per_second' is not level:metric:operations
FAIL job:http_requests:rate1m                             level 'job' != aggregation labels ['job', 'code']; operations 'rate1m' does not mention rate5m
FAIL job:http_requests_total:rate5m                       rate() over a recorded SUM: resets of members become resets of the sum
FAIL job:errors:irate1m                                   metric 'errors' does not name the source 'http_errors_total'; irate() in a recording rule: records last-two-samples noise

== 2. Pre-aggregation: what a recording rule saves a dashboard ==
raw bucket series: 200 pods x 20 routes x 4 codes x 12 le = 192,000
recorded job_route:...:rate5m series: 20 routes x 12 le = 240 (800x fewer); engine check on a 10-pod slice -> 240 output series
30-day p99 panel at 5m step: raw = 33,177,600,000 samples touched; recorded = 2,073,600 (16,000x less) -- and --query.max-samples is 50,000,000

== 3. Rule-group ordering: same group vs separate groups ==
Rules in ONE group run sequentially at the same timestamp; a later rule sees the earlier rule's
fresh output. Across groups there is no ordering: a dependent group reads the previous evaluation.
interval 30s: dependent rule staleness, same group = 0s; separate groups = 5..30s depending on phase (hash-based group offsets)

checks: 4/4 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 A rule file layout that scales

```yaml
# rules/http-service.rules.yaml  (one file per domain; one group per evaluation cadence)
groups:
  - name: http-service.rules
    interval: 30s
    query_offset: 0s                  # set >0 for remote-write/OTLP-fed inputs
    limit: 5000                       # guard against accidental fan-out
    labels:
      rule_origin: platform-http      # provenance on every recorded series
    rules:
      # level 1: per job/route/code rates (the base everything else reads)
      - record: job_route_code:http_server_requests:rate5m
        expr: |
          sum by (job, route, code) (rate(http_server_requests_seconds_count[5m]))
      - record: job_route_le:http_server_request_duration_seconds_bucket:rate5m
        expr: |
          sum by (job, route, le) (rate(http_server_request_duration_seconds_bucket[5m]))
      # level 2: derived from level 1 in the SAME group (fresh values, same timestamp)
      - record: job:http_server_requests:rate5m
        expr: sum by (job) (job_route_code:http_server_requests:rate5m)
      - record: job:http_server_errors:rate5m
        expr: sum by (job) (job_route_code:http_server_requests:rate5m{code=~"5.."})
      - record: job:http_server_errors:ratio_rate5m
        expr: |
          job:http_server_errors:rate5m / job:http_server_requests:rate5m
      - record: job_route:http_server_request_duration_seconds:p99_5m
        expr: histogram_quantile(0.99, job_route_le:http_server_request_duration_seconds_bucket:rate5m)
  - name: http-service.rules.1h
    interval: 5m                      # long windows don't need 30s evaluation
    rules:
      - record: job:http_server_requests:rate1h
        expr: sum by (job) (rate(http_server_requests_seconds_count[1h]))
      - record: job:http_server_errors:rate1h
        expr: sum by (job) (rate(http_server_requests_seconds_count{code=~"5.."}[1h]))
```

### 2.2 Unit tests for rules (`promtool test rules`)

```yaml
# tests/http-service.rules.test.yaml
rule_files:
  - ../rules/http-service.rules.yaml
evaluation_interval: 30s
tests:
  - interval: 30s
    input_series:
      - series: 'http_server_requests_seconds_count{job="checkout",route="/pay",code="200"}'
        values: '0+600x20'             # 20 req/s
      - series: 'http_server_requests_seconds_count{job="checkout",route="/pay",code="500"}'
        values: '0+30x20'              # 1 req/s
    promql_expr_test:
      - expr: job:http_server_errors:ratio_rate5m
        eval_time: 10m
        exp_samples:
          - labels: 'job:http_server_errors:ratio_rate5m{job="checkout",rule_origin="platform-http"}'
            value: 0.047619047619047616   # 1 / 21
  - interval: 30s
    input_series:                     # the "no error series yet" case (Folder 02 File 2 F3)
      - series: 'http_server_requests_seconds_count{job="checkout",route="/pay",code="200"}'
        values: '0+600x20'
    promql_expr_test:
      - expr: job:http_server_errors:ratio_rate5m
        eval_time: 10m
        exp_samples: []               # documents that the ratio is ABSENT, not 0
```

Run in CI with `promtool check rules rules/*.yaml && promtool test rules tests/*.yaml`.

### 2.3 Shipping aggregates, not raw series

```yaml
remote_write:
  - url: https://mimir.example.internal/api/v1/push
    protobuf_message: io.prometheus.write.v2.Request
    write_relabel_configs:
      - source_labels: [__name__]
        regex: '[a-z0-9_]+:[a-z0-9_]+:[a-z0-9_]+|up|ALERTS|ALERTS_FOR_STATE'
        action: keep                  # recorded series + target health + alert state only
```

---

## 3. Failure modes and FinOps debugging

### F1. Recorded ratios that cannot be aggregated

**Symptom.** A 30-day availability report computed as `avg_over_time(job:errors:ratio_rate5m[30d])` disagrees with the request logs by tenths of a percent — enough to change an SLO verdict.

**Signature.** Only ratio series are recorded; traffic varies 10× between night and day.

**Root cause.** The average of ratios weights a quiet night interval like a peak interval; the true ratio is Σ errors / Σ requests.

**Fix.** Record numerator and denominator rates; compute long-window ratios as `sum_over_time(num[30d]) / sum_over_time(den[30d])` (or with `increase`).

**Prevention.** Lint: every `:ratio_` rule must have its `num` and `den` recorded in the same group.

### F2. A rule's `by` changes and dashboards silently break

**Symptom.** After someone adds `code` to a recording rule's `by`, dashboard sums double and alerts misfire.

**Signature.** The rule name's level (`job:`) no longer matches its labels; series count per name jumps.

**Root cause.** Consumers trusted the name; the convention was not enforced.

**Fix.** Rename the rule (`job_code:…`) and keep the old one until consumers migrate.

**Prevention.** L1-style lint in CI; recorded series are an API with versioning.

### F3. Rule evaluation falls behind

**Symptom.** Recorded series have gaps; `prometheus_rule_group_last_duration_seconds` exceeds the group interval; `prometheus_rule_group_iterations_missed_total` increases.

**Signature.** One expensive rule (e.g. a join over raw cAdvisor series or a long subquery) dominates group duration.

**Root cause.** Groups run their rules sequentially; a group whose total duration exceeds its interval skips iterations.

**Fix.** Split heavy rules into their own groups with longer intervals; pre-aggregate inputs; enable concurrent rule evaluation for independent rules.

**Prevention.** Alert on `prometheus_rule_group_last_duration_seconds / prometheus_rule_group_interval_seconds > 0.8`.

### F4. Recording rules that explode cardinality

**Symptom.** A new rule adds 2 M series overnight.

**Signature.** `without (pod)` used where `by (job, route)` was intended — every other label survives, including high-cardinality ones; or a join that multiplies series.

**Root cause.** `without` keeps everything not listed; inputs gained labels since the rule was written.

**Fix.** Prefer `by (…)` in recording rules; set group `limit`.

**Prevention.** Rule output series budget per group, alerting on `count by (__name__)` growth of recorded series via TSDB status.

### F5. Cross-group dependency lag in alerts

**Symptom.** An alert based on a recorded series fires 30–60 s later than expected and flaps at boundaries.

**Signature.** The recorded input lives in another group with the same interval but a different hash offset.

**Root cause.** No ordering between groups (§1.1); the alert reads the previous evaluation's value.

**Fix.** Put the alert in the same group as its inputs, or accept and document the lag.

**Prevention.** Rule design guideline: alerts live next to the rules they read.

### F6. Stale recorded series after renames

**Symptom.** Dashboards show flat lines at old values for 5 minutes after a rule rename, then gaps.

**Signature.** The old rule was removed; its series get staleness markers (rule manager writes them) and then disappear; new name has no history.

**Root cause.** Renaming creates a new series; history is not migrated.

**Fix.** Run old and new names in parallel for the retention period consumers need; query `old or new` during migration.

**Prevention.** Rename policy: dual-write until dashboards and alerts are migrated, then remove.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "When should something be a recording rule?"</b></summary>

**Initial Prompt.** A team wants to record everything "for performance". Your policy?

**L5 Textbook Answer.** Record expensive queries used in dashboards and alerts.

**Why L5 Fails at 3 AM or on the Bill.** "Expensive" without a cost model leads to recording raw-equivalent series (doubling storage) or recording only quantiles and ratios that can't be re-aggregated.

**L7 Principal Defense.** Record when (a) the query is evaluated repeatedly (dashboards × viewers × refresh, alerts every interval) and its input cardinality is ≫ output cardinality — L1: 192k → 240 series, 16,000× less work; (b) the order of operations must be enforced (rate-then-sum, keep `le`); (c) the output is the unit we ship to long-term storage. Record numerators/denominators and bucket rates; quantiles/ratios additionally, never instead. And delete recorded series nobody reads (usage analytics, Folder 08).
</details>

<details><summary><b>Q2 · "Explain level:metric:operations with an example."</b></summary>

**Initial Prompt.** Name the rule for p99 latency per job and route over 5 minutes.

**L5 Textbook Answer.** `job_route:latency_p99:5m`.

**Why L5 Fails at 3 AM or on the Bill.** Loses the source metric name (not greppable) and the operation order; consumers can't tell whether it's a quantile of rates or a rate of quantiles.

**L7 Principal Defense.** First `job_route_le:http_server_request_duration_seconds_bucket:rate5m` (the reusable base), then `job_route:http_server_request_duration_seconds:p99_5m` derived from it in the same group. Level = `by` labels, metric = source (`_bucket` kept for the bucket rate, dropped for the quantile output), operations newest-first. The linter in L1 enforces it in CI.
</details>

<details><summary><b>Q3 · "Why can't I average recorded ratios over 30 days?"</b></summary>

**Initial Prompt.** Our SLO report averages the 5-minute error ratio over the month.

**L5 Textbook Answer.** That's fine as long as the ratio is recorded frequently.

**Why L5 Fails at 3 AM or on the Bill.** Equal weighting of unequal traffic: a 50%-error minute at 3 AM counts like a peak minute; reports diverge from user experience and can flip SLO compliance.

**L7 Principal Defense.** Ratios don't compose; counts do. Record error and request rates, and compute `sum_over_time(err[30d]) / sum_over_time(req[30d])` (or `increase` of raw counters over the window). Ratios stay for alerting where the window is fixed.
</details>

<details><summary><b>Q4 · "Our rule groups miss iterations. Diagnose."</b></summary>

**Initial Prompt.** `prometheus_rule_group_iterations_missed_total` is climbing.

**L5 Textbook Answer.** Increase the evaluation interval.

**Why L5 Fails at 3 AM or on the Bill.** Slower evaluation degrades every alert in the group and hides the one bad rule.

**L7 Principal Defense.** Find the slow rule (`prometheus_rule_evaluation_duration_seconds` per rule, query log), then fix its input: pre-aggregate raw series in an earlier group, replace subqueries with recorded inner expressions, move it to its own group with a longer interval if its consumers tolerate it. Enable concurrent evaluation for independent rules. Alert on duration/interval > 0.8.
</details>

<details><summary><b>Q5 · "How do you test recording rules?"</b></summary>

**Initial Prompt.** What does CI do for rule changes?

**L5 Textbook Answer.** Run `promtool check rules` for syntax.

**Why L5 Fails at 3 AM or on the Bill.** Syntax-valid rules can be semantically wrong (wrong `by`, wrong window, absent-series behaviour) and break every consumer.

**L7 Principal Defense.** Four layers: `promtool check rules` (syntax), naming lint (L1), `promtool test rules` with fixtures including resets, absent series and label variety (§2.2), and a cardinality dry-run (evaluate the expression against production via the API and count output series before merge). Plus code owners for shared rule files.
</details>

<details><summary><b>Q6 · "Should alerts read recorded series or raw expressions?"</b></summary>

**Initial Prompt.** Pick a policy.

**L5 Textbook Answer.** Raw expressions, so alerts don't depend on rules.

**Why L5 Fails at 3 AM or on the Bill.** Raw expressions duplicate logic and cost in every alert, drift from dashboards, and are harder to test.

**L7 Principal Defense.** Alerts read recorded series from the *same group* (no cross-group lag), with the recorded expression unit-tested. The exception is the meta-monitoring path (dead man's switch, `up`, rule-evaluation health), which must not depend on the rules it guards.
</details>

<details><summary><b>Q7 · "How do recording rules cut the observability bill?"</b></summary>

**Initial Prompt.** Finance asks for a 50% cut in metrics storage.

**L5 Textbook Answer.** Reduce retention or scrape less often.

**Why L5 Fails at 3 AM or on the Bill.** Retention cuts lose history everybody uses; scrape intervals hurt alert accuracy (Folder 02 File 1) for modest savings.

**L7 Principal Defense.** Keep raw high-resolution data short-term locally; ship only recorded aggregates (plus `up`, `ALERTS`) to long-term storage via `write_relabel_configs` (§2.3); measure which raw series long-term queries actually touch (Folder 08 File 2) and drop the rest. Pre-aggregation ratios of 100–1000× (L1) are where the savings are.
</details>

<details><summary><b>Q8 · "What's `query_offset` for?"</b></summary>

**Initial Prompt.** When would you set a rule group's query_offset?

**L5 Textbook Answer.** To delay evaluation if data is late.

**Why L5 Fails at 3 AM or on the Bill.** Without knowing which inputs are late and by how much, it's either unset (rules see incomplete data and under-count) or too large (alerts slow).

**L7 Principal Defense.** Rules evaluate "now"; push-ingested inputs (remote write, OTLP, agents with batching) may arrive seconds late, so `rate()` over the latest window sees missing samples and under-estimates. Set `query_offset` ≈ p99 ingestion delay (measured from `prometheus_tsdb_sample_ooo_delta` or receiver lag) for those groups only, and always for rules using `smoothed` selectors. Scrape-fed rules keep 0.
</details>

---

## 5. Invariants checklist

- [ ] Every recorded series follows `level:metric:operations`; CI lints names against `by` labels and windows.
- [ ] Numerators and denominators are recorded wherever a ratio is recorded; bucket rates keep `le`.
- [ ] No `rate()`/`increase()` over recorded sums; no `irate` in rules.
- [ ] Rules and the alerts that read them share a group; heavy rules get their own group and interval.
- [ ] `promtool test rules` covers resets, absent series and label variety for every shared rule file.
- [ ] Rule group duration/interval and missed iterations are alerted.
- [ ] Long-term storage receives recorded aggregates; raw series stay local and short-lived.
- [ ] Rule renames dual-write until consumers migrate.

---

## 6. References

- Recording rules configuration: <https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/>
- Recording rules naming best practice: <https://prometheus.io/docs/practices/rules/>
- Unit testing rules with promtool: <https://prometheus.io/docs/prometheus/latest/configuration/unit_testing_rules/>
- Rule manager source: <https://github.com/prometheus/prometheus/tree/v3.15.1/rules>
- Feature flags (concurrent rule evaluation): <https://prometheus.io/docs/prometheus/latest/feature_flags/>
- kubernetes-mixin rules (convention in practice): <https://github.com/kubernetes-monitoring/kubernetes-mixin>
