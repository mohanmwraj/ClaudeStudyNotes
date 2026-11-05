# 02 · Google SRE Multi-Window, Multi-Burn-Rate SLO Alerts and Error-Budget Math

> **Folder 04 — Recording Rules, Alertmanager and SLO Error-Budget Math · File 2 of 4.**
> Method from the *Site Reliability Workbook* (O'Reilly, 2018), chapter 5 "Alerting on SLOs"; rules target Prometheus v3.15.1.
> Labels: **[D]** documented (Workbook / docs) · **[M]** measured by the listing (deterministic, re-run by the gate) · **[E]** model · **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L2 `burn_rate_lab.py` | Error-budget arithmetic for a 30-day 99.9% SLO; the Workbook's page/page/ticket burn-rate tiers (14.4 over 1h, 6 over 6h, 1 over 3d, each AND-ed with a 1/12 short window) **reproduce the Workbook's 2%/5%/10% budget figures and 0.86-minute detection of a total outage**; detection times for error ratios from 100% to 0.2%; and 90 days of minute-level traffic with 300 harmless blips and six incidents scored against static-threshold, single-window and multi-window strategies | <1 s |

**Verification.** The Workbook's published numbers are the oracle and are asserted exactly. The 90-day comparison is a simulation [M] with a stated workload (baseline 0.02% errors, blips of 3–8% lasting 2–4 minutes, six incidents from 15-minute total outages to a 2-day 0.18% slow burn); its outcome — static thresholds page hundreds of times, multi-window pages only for budget-threatening incidents — is asserted.

---

## 0. Orientation

**What this file answers.** How to turn an SLO into alerts that page *only* when the error budget is genuinely threatened, quickly for fast burns and eventually for slow ones; the exact math behind the famous 14.4×; and how to express it as Prometheus rules that are correct for low-traffic services, absent series and multiple SLOs.

**Vocabulary [D].**

| Term | Definition |
|---|---|
| SLI | good events / valid events, measured over a window (e.g. requests with status < 500 and latency ≤ 300 ms) |
| SLO | target for the SLI over a compliance period (99.9% over 30 days) |
| Error budget | 1 − SLO = 0.1% of valid events in the period (≈ 43 minutes of total outage in 30 days) |
| Burn rate | observed error ratio / (1 − SLO); burn rate 1 spends exactly the budget over the period |
| Budget consumed by an alert window | burn rate × window / period |

---

## 1. First principles: error budgets and burn rates

### 1.1 Why burn rates, not thresholds

A static threshold (`error ratio > 1% for 5m`) answers "is it bad right now?", not "will we miss the SLO?". The budget view converts every error into a fraction of a monthly allowance, so alert severity can scale with how fast the allowance is being spent:

```text
 burn rate  b = error_ratio / (1 − SLO)                    SLO 99.9% → (1 − SLO) = 0.001
 fraction of 30-day budget consumed in window W at rate b  = b · W / 30d
 time to exhaust the whole budget at rate b                 = 30d / b
       b = 14.4 →  2% of budget per hour,  exhausted in 2.1 days        → page
       b = 6    →  5% of budget per 6h,    exhausted in 5 days          → page
       b = 1    → 10% of budget per 3d,    exhausted exactly at period  → ticket
```

L2 §1 reproduces the Workbook's figures exactly [M].

### 1.2 Detection time and the short window

For a sustained error ratio *e* that starts at t = 0, a window of length W reaches the threshold `b·(1−SLO)` after `t = b·(1−SLO)·W / e`. The Workbook pairs each long window with a short one (1/12 of it) and requires **both**:

| Error ratio | 1h & 5m @ 14.4 | 6h & 30m @ 6 | 3d & 6h @ 1 |
|---|---|---|---|
| 100% | **52 s** (Workbook: 0.86 min) | 2.2 min | 4.3 min |
| 10% | 8.6 min | 21.6 min | 43 min |
| 2% | 43 min | 108 min | 3.6 h |
| 1% | never | 3.6 h | 7.2 h |
| 0.5% | never | never | 14.4 h |
| 0.2% | never | never | 36 h |

```text
 error ratio  ███████████████ (15-min outage at 100%)
 time         |----- outage -----|------------------- recovery -------------------|
 1h window    avg rises ──► crosses 14.4×0.1% after ~52 s ... stays above threshold until the
              bad minutes roll out of the window (≈ +45 min)          ← long window alone: late reset
 5m window    crosses after ~4 s ............ drops below threshold ≈ 5 min after recovery
 AND of both  FIRES at ~52 s ................. RESOLVES ≈ 5 min after recovery  ← the design goal
```

- **Detection scales with severity**: total outages page within a minute; a 1% error rate (10× burn) pages in 3.6 h; a 0.2% rate (2× burn) becomes a ticket after ~1.5 days — exactly the urgency each deserves.
- **The short window is for *reset*, not detection.** Without it, a 15-minute outage keeps the 1-hour average above threshold for up to an hour after recovery — paging people about an incident that has ended. The 5-minute short window drops below threshold within minutes of recovery, so the AND-ed alert resolves.

### 1.3 What the policy buys (L2 §3)

90 days, one-minute resolution, 300 blips plus six incidents [M]:

| Strategy | Pages | False pages | Budget-threatening incidents caught | Mean detection |
|---|---|---|---|---|
| static: error ratio > 1% over 5m | 297 | **285** | 6/6 | 68 min |
| single window: 1h burn > 14.4 | 3 | 0 | 3/6 | 7 min |
| multi-window multi-burn (page tiers) | 5 | **0** | 5/6 | 89 min |

The static rule's "catches" are largely blips that happened to coincide with incidents; on-call would have been paged 285 times for nothing. The 1-hour/14.4 tier alone misses slow burns. The two page tiers catch every fast and medium incident without a single false page; the one remaining incident (a 2-day 0.18% slow burn — 1.8× burn rate) is caught by the 3-day **ticket** tier, as designed.

### 1.4 Low-traffic services and SLI construction

- **Low traffic breaks ratios.** At 10 requests per hour, one error is a 10% ratio — a 100× burn. Options: aggregate SLIs across similar services, require a minimum request count (`and sum(rate(requests[1h])) > N`), use longer windows, or use synthetic probes to generate a baseline.
- **Count, don't average.** SLIs are recorded as numerator and denominator rates per window (File 1 §1.3); burn rates are their ratio.
- **Absent numerators** (no errors ever) must evaluate to 0, not "no data" (Folder 02 File 2 §1.4) — the rules below use `or … * 0`.
- **Latency SLIs** use bucket counts at a threshold that is a bucket boundary or native histograms (Folder 02 File 3): good = `rate(bucket{le="0.3"})`, valid = `rate(count)`.

<!-- listing:burn_rate_lab.py -->
```python
"""burn_rate_lab.py - SLO error-budget mathematics and the Google SRE Workbook's multi-window,
multi-burn-rate alerts, verified against the Workbook's own numbers and stress-tested on 90 days of
synthetic traffic.

Oracle (SRE Workbook, "Alerting on SLOs", 30-day 99.9% SLO): burn rate 14.4 over 1h consumes 2% of
the budget, 6 over 6h consumes 5%, 1 over 3d consumes 10%; a 100% outage is detected by the
1h/14.4 condition in 0.86 minutes.
Sections: (1) budget arithmetic; (2) detection and reset times per error rate; (3) strategy
comparison (static threshold, single-window burn, multi-window multi-burn) on a 90-day minute-level
trace with blips and real incidents. Deterministic, stdlib only.

Usage: python burn_rate_lab.py [target.md]
"""
import random
import sys

SLO = 0.999
BUDGET = 1 - SLO
PERIOD_MIN = 30 * 24 * 60
POLICY = [  # (name, long window min, short window min, burn rate, severity)
    ("page-fast", 60, 5, 14.4, "page"),
    ("page-slow", 360, 30, 6.0, "page"),
    ("ticket", 4320, 360, 1.0, "ticket"),
]


def detection_minutes(e, long_w, short_w, burn):
    thr = burn * BUDGET
    if e <= thr:
        return None
    return max(thr * long_w / e, thr * short_w / e)


def main():
    checks = []
    print(f"== 1. Budget arithmetic: SLO {SLO:.1%} over 30 days -> budget {BUDGET:.2%} of requests "
          f"= {BUDGET * PERIOD_MIN:.0f} min of total outage ==")
    for name, lw, sw, b, sev in POLICY:
        consumed = b * lw / PERIOD_MIN
        print(f"{name:<10} burn {b:>5} over {lw / 60:>4.0f}h (AND {sw}m): fires after {consumed:.0%} of the budget is "
              f"spent; budget exhausted in {PERIOD_MIN / b / 60 / 24:.1f} days at this rate -> {sev}")
    checks.append(("workbook 2/5/10%", [round(b * lw / PERIOD_MIN, 4) for _, lw, _, b, _ in POLICY] == [0.02, 0.05, 0.1]))
    print()

    print("== 2. Detection time (constant error ratio starting at t=0) and reset time ==")
    print(f"{'error ratio':>11} | " + " | ".join(f"{n:>11}" for n, *_ in POLICY))
    for e in (1.0, 0.1, 0.02, 0.01, 0.005, 0.002):
        row = []
        for _, lw, sw, b, _ in POLICY:
            d = detection_minutes(e, lw, sw, b)
            row.append("never" if d is None else (f"{d * 60:.0f} s" if d < 2 else f"{d:.1f} min" if d < 120 else f"{d / 60:.1f} h"))
        print(f"{e:>11.1%} | " + " | ".join(f"{r:>11}" for r in row))
    d100 = detection_minutes(1.0, 60, 5, 14.4)
    print(f"oracle: 100% errors detected by 1h/14.4 in {d100:.2f} min (Workbook: 0.86 min)")
    checks.append(("0.86 min", abs(d100 - 0.864) < 1e-9))
    print("reset: once the incident ends, the 5m short window drops below 14.4x within <= 5 min, so the AND-ed alert")
    print("resolves in minutes; a long window alone would keep firing for up to 1h (the reason short windows exist)")
    print()

    print("== 3. 90 days at 1-minute resolution: blips, slow burns and outages vs three strategies ==")
    rng = random.Random(2026)
    n = 90 * 24 * 60
    err = [max(0.0, rng.gauss(0.0002, 0.0001)) for _ in range(n)]
    for _ in range(300):  # harmless blips: 2-4 minutes at 3-8% errors
        s = rng.randrange(n - 10)
        for k in range(rng.randint(2, 4)):
            err[s + k] = rng.uniform(0.03, 0.08)
    incidents = [(10_000, 15, 1.0), (40_000, 45, 0.05), (70_000, 8 * 60, 0.008), (100_000, 2 * 24 * 60, 0.0018),
                 (90_000, 30, 0.2), (115_000, 6 * 60, 0.01)]
    for s, dur, e in incidents:
        for k in range(dur):
            err[s + k] = max(err[s + k], e)
    pre = [0.0]
    for x in err:
        pre.append(pre[-1] + x)

    def avg(t, w):
        a = max(0, t - w + 1)
        return (pre[t + 1] - pre[a]) / (t + 1 - a)

    def run(strategy):
        firing, alerts = False, []
        for t in range(n):
            if strategy == "static 1% over 5m":
                f = avg(t, 5) > 0.01
            elif strategy == "single 1h burn 14.4":
                f = avg(t, 60) > 14.4 * BUDGET
            else:
                f = any(avg(t, lw) > b * BUDGET and avg(t, sw) > b * BUDGET for _, lw, sw, b, sev in POLICY if sev == "page")
            if f and not firing:
                alerts.append(t)
            firing = f
        return alerts

    def budget_threatening(s, dur, e):
        return dur * e / (BUDGET * PERIOD_MIN) >= 0.02  # >= 2% of the monthly budget

    print(f"{'strategy':<22} {'pages':>5} {'false pages':>11} {'incidents caught':>16} {'mean detect':>11}")
    results = {}
    for strat in ("static 1% over 5m", "single 1h burn 14.4", "multi-window multi-burn"):
        al = run(strat)
        caught, delays, true_alerts = 0, [], set()
        for s, dur, e in incidents:
            if not budget_threatening(s, dur, e):
                continue
            hit = [a for a in al if s <= a <= s + dur + 60]
            if hit:
                caught += 1
                delays.append(hit[0] - s)
                true_alerts.update(hit)
        false = len([a for a in al if a not in true_alerts and not any(s <= a <= s + dur + 60 for s, dur, _ in incidents)])
        n_threat = sum(budget_threatening(*i) for i in incidents)
        results[strat] = (len(al), false, caught, n_threat)
        md = f"{sum(delays) / len(delays):.0f} min" if delays else "-"
        print(f"{strat:<22} {len(al):>5} {false:>11} {caught:>9}/{n_threat:<6} {md:>11}")
    ok_multi = results["multi-window multi-burn"]
    checks.append(("multi: no false pages", ok_multi[1] == 0))
    checks.append(("static: many false pages", results["static 1% over 5m"][1] > 50))
    checks.append(("multi catches more than single", ok_multi[2] >= results["single 1h burn 14.4"][2]))
    print("-> blips page the static rule hundreds of times; the 1h/14.4 window alone misses slow burns; the")
    print("   multi-window policy pages only for budget-threatening incidents. The 3-day ticket tier covers the rest.")
    print()

    failed = [n_ for n_, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:burn_rate_lab.py -->
```text
== 1. Budget arithmetic: SLO 99.9% over 30 days -> budget 0.10% of requests = 43 min of total outage ==
page-fast  burn  14.4 over    1h (AND 5m): fires after 2% of the budget is spent; budget exhausted in 2.1 days at this rate -> page
page-slow  burn   6.0 over    6h (AND 30m): fires after 5% of the budget is spent; budget exhausted in 5.0 days at this rate -> page
ticket     burn   1.0 over   72h (AND 360m): fires after 10% of the budget is spent; budget exhausted in 30.0 days at this rate -> ticket

== 2. Detection time (constant error ratio starting at t=0) and reset time ==
error ratio |   page-fast |   page-slow |      ticket
     100.0% |        52 s |     2.2 min |     4.3 min
      10.0% |     8.6 min |    21.6 min |    43.2 min
       2.0% |    43.2 min |   108.0 min |       3.6 h
       1.0% |       never |       3.6 h |       7.2 h
       0.5% |       never |       never |      14.4 h
       0.2% |       never |       never |      36.0 h
oracle: 100% errors detected by 1h/14.4 in 0.86 min (Workbook: 0.86 min)
reset: once the incident ends, the 5m short window drops below 14.4x within <= 5 min, so the AND-ed alert
resolves in minutes; a long window alone would keep firing for up to 1h (the reason short windows exist)

== 3. 90 days at 1-minute resolution: blips, slow burns and outages vs three strategies ==
strategy               pages false pages incidents caught mean detect
static 1% over 5m        297         285         6/6           68 min
single 1h burn 14.4        3           0         3/6            7 min
multi-window multi-burn     5           0         5/6           89 min
-> blips page the static rule hundreds of times; the 1h/14.4 window alone misses slow burns; the
   multi-window policy pages only for budget-threatening incidents. The 3-day ticket tier covers the rest.

checks: 5/5 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 SLI recording rules (availability, one service)

```yaml
groups:
  - name: slo:checkout-availability:rules
    interval: 30s
    rules:
      # error ratio per window = errors / requests; `or ... * 0` turns "no errors" into 0
      - record: slo:sli_error:ratio_rate5m
        labels: {slo: checkout-availability}
        expr: |
          (sum(rate(http_server_requests_seconds_count{job="checkout", code=~"5.."}[5m]))
            or sum(rate(http_server_requests_seconds_count{job="checkout"}[5m])) * 0)
          / sum(rate(http_server_requests_seconds_count{job="checkout"}[5m]))
      - record: slo:sli_error:ratio_rate30m
        labels: {slo: checkout-availability}
        expr: |
          (sum(rate(http_server_requests_seconds_count{job="checkout", code=~"5.."}[30m]))
            or sum(rate(http_server_requests_seconds_count{job="checkout"}[30m])) * 0)
          / sum(rate(http_server_requests_seconds_count{job="checkout"}[30m]))
      - record: slo:sli_error:ratio_rate1h
        labels: {slo: checkout-availability}
        expr: |
          (sum(rate(http_server_requests_seconds_count{job="checkout", code=~"5.."}[1h]))
            or sum(rate(http_server_requests_seconds_count{job="checkout"}[1h])) * 0)
          / sum(rate(http_server_requests_seconds_count{job="checkout"}[1h]))
      - record: slo:sli_error:ratio_rate6h
        labels: {slo: checkout-availability}
        expr: |
          (sum(rate(http_server_requests_seconds_count{job="checkout", code=~"5.."}[6h]))
            or sum(rate(http_server_requests_seconds_count{job="checkout"}[6h])) * 0)
          / sum(rate(http_server_requests_seconds_count{job="checkout"}[6h]))
      - record: slo:sli_error:ratio_rate3d
        labels: {slo: checkout-availability}
        expr: |
          (sum(rate(http_server_requests_seconds_count{job="checkout", code=~"5.."}[3d]))
            or sum(rate(http_server_requests_seconds_count{job="checkout"}[3d])) * 0)
          / sum(rate(http_server_requests_seconds_count{job="checkout"}[3d]))
      - record: slo:objective:ratio
        labels: {slo: checkout-availability}
        expr: vector(0.999)
```

Evaluating `rate(...[3d])` every 30 s over raw series is expensive; at scale, compute the 3-day ratio from a recorded 5-minute numerator/denominator with `sum_over_time` (or let Sloth/Pyrra generate this optimisation).

### 2.2 Multi-window, multi-burn-rate alerts

```yaml
groups:
  - name: slo:checkout-availability:alerts
    rules:
      - alert: CheckoutErrorBudgetBurn
        expr: |
          (
              slo:sli_error:ratio_rate1h{slo="checkout-availability"} > (14.4 * (1 - 0.999))
            and
              slo:sli_error:ratio_rate5m{slo="checkout-availability"} > (14.4 * (1 - 0.999))
          )
          or
          (
              slo:sli_error:ratio_rate6h{slo="checkout-availability"} > (6 * (1 - 0.999))
            and
              slo:sli_error:ratio_rate30m{slo="checkout-availability"} > (6 * (1 - 0.999))
          )
        for: 2m
        labels:
          severity: page
          slo: checkout-availability
        annotations:
          summary: "checkout is burning its 30-day error budget fast"
          description: "Error ratio {{ $value | humanizePercentage }}; at this rate the budget is gone in days."
          runbook_url: https://runbooks.example.internal/slo/checkout-availability
      - alert: CheckoutErrorBudgetBurnSlow
        expr: |
          slo:sli_error:ratio_rate3d{slo="checkout-availability"} > (1 * (1 - 0.999))
            and
          slo:sli_error:ratio_rate6h{slo="checkout-availability"} > (1 * (1 - 0.999))
        for: 1h
        labels:
          severity: ticket
          slo: checkout-availability
        annotations:
          summary: "checkout will exhaust its error budget within the period at the current rate"
```

### 2.3 Generating SLO rules: Sloth / Pyrra spec (shape)

```yaml
# Sloth (prometheus/v1) spec - generates the recording rules and burn-rate alerts above
version: prometheus/v1
service: checkout
labels:
  owner: payments
slos:
  - name: requests-availability
    objective: 99.9
    description: "Checkout HTTP requests return non-5xx"
    sli:
      events:
        error_query: sum(rate(http_server_requests_seconds_count{job="checkout",code=~"5.."}[{{.window}}]))
        total_query: sum(rate(http_server_requests_seconds_count{job="checkout"}[{{.window}}]))
    alerting:
      name: CheckoutHighErrorRate
      page_alert:
        labels: {severity: page}
      ticket_alert:
        labels: {severity: ticket}
```

### 2.4 Error-budget reporting and policy

```promql
# Remaining budget over the 30-day period (1 = untouched, 0 = exhausted, <0 = SLO violated)
1 - (
  (sum(increase(http_server_requests_seconds_count{job="checkout", code=~"5.."}[30d]))
    or sum(increase(http_server_requests_seconds_count{job="checkout"}[30d])) * 0)
  / sum(increase(http_server_requests_seconds_count{job="checkout"}[30d]))
) / (1 - 0.999)
```

---

## 3. Failure modes and FinOps debugging

### F1. Pages that resolve themselves before anyone looks

**Symptom.** SLO pages fire for 2–4 minutes and resolve; on-call learns to ignore them.

**Signature.** Single short-window burn alerts (e.g. `ratio_rate5m > 14.4 × budget`) without the long window; blips of 3–8% errors trigger them.

**Root cause.** Short windows measure blips, not budget threat (L2 §3: 285 false pages in 90 days with a 5-minute static rule).

**Fix.** Long window AND short window per tier (§2.2).

**Prevention.** Generate SLO alerts from specs (Sloth/Pyrra); forbid hand-written single-window SLO alerts.

### F2. Alerts that keep firing an hour after recovery

**Symptom.** After a 10-minute outage is fixed, the page stays active for ~50 minutes; responders keep investigating a recovered system.

**Signature.** Long-window-only burn alerts.

**Root cause.** The 1-hour average stays above threshold until the bad minutes roll out of the window.

**Fix.** Add the short window (1/12 of the long one) to each tier.

**Prevention.** Policy as code; review alert duration distributions (Folder 04 File 4).

### F3. Low-traffic services page on a single error

**Symptom.** A rarely used admin API pages at night for one 500.

**Signature.** Denominator ≈ 1–10 requests per window; burn rate computed as 100–1000.

**Root cause.** Ratios over tiny counts are noise.

**Fix.** Minimum-traffic guard (`and sum(rate(requests[1h])) > 0.1`), aggregate SLOs for small services, synthetic traffic.

**Prevention.** SLO onboarding checks expected traffic; services below a threshold get grouped SLOs.

### F4. SLO dashboard says compliant; customers disagree

**Symptom.** The availability SLO is green while support tickets spike.

**Signature.** The SLI counts only 5xx from the service itself; client-side timeouts, load-balancer 502s and fast 503s from a circuit breaker happen elsewhere.

**Root cause.** The SLI is measured at the wrong point or excludes failure classes.

**Fix.** Measure as close to the user as possible (load balancer / edge / client RUM), count timeouts as errors, include latency SLIs.

**Prevention.** SLI review against real incidents: every incident should have burned budget; if not, the SLI is wrong.

### F5. 3-day windows that melt the rule evaluator

**Symptom.** SLO rule groups miss iterations; Prometheus CPU climbs after adding 40 SLOs.

**Signature.** `rate(raw_counter[3d])` per SLO per 30 s evaluation over raw high-cardinality series.

**Root cause.** Each evaluation reads 3 days of raw samples.

**Fix.** Compute long windows from recorded 5-minute num/den via `sum_over_time`, evaluate long tiers every 1–5 minutes, or use Pyrra/Sloth's optimised rules.

**Prevention.** Load-test SLO rule sets; budget rule evaluation CPU.

### F6. Error budget "resets" mid-month

**Symptom.** The remaining-budget panel jumps up after a Prometheus migration or a retention change.

**Signature.** `increase(...[30d])` over a range with missing history; counters reset by the migration.

**Root cause.** Rolling 30-day windows need 30 days of data; history gaps undercount errors.

**Fix.** Compute budgets from long-term storage (Mimir/Thanos), and record daily num/den to long-term storage so budgets survive migrations.

**Prevention.** SLO data is a retention requirement: ≥ period + margin in the long-term store.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "Derive 14.4."</b></summary>

**Initial Prompt.** Where does the 14.4 burn-rate threshold come from?

**L5 Textbook Answer.** It's Google's recommended value for a 1-hour window.

**Why L5 Fails at 3 AM or on the Bill.** A memorised constant can't be adapted to a 28-day period, a 99.99% SLO or a different paging budget.

**L7 Principal Defense.** Choose how much budget you're willing to spend before paging — 2% — and over what window — 1 hour. Then b × 1h / 720h = 0.02 → b = 14.4. For a 28-day period, b = 0.02 × 672 = 13.44; for 6 h at 5%, b = 0.05 × 720/6 = 6. Detection time for a total outage = b × (1 − SLO) × window = 14.4 × 0.001 × 60 min = 0.86 min (L2 asserts it).
</details>

<details><summary><b>Q2 · "Why two windows per alert?"</b></summary>

**Initial Prompt.** Isn't the long window enough?

**L5 Textbook Answer.** The short window makes alerts faster.

**Why L5 Fails at 3 AM or on the Bill.** Detection is governed by the long window (it must accumulate budget); the short window's job is to stop the alert once the problem ends.

**L7 Principal Defense.** Long window: significance (enough budget spent). Short window (1/12): currency (is it still happening). AND-ing them gives fast reset after recovery while keeping the long window's precision. Without it, a 10-minute outage pages for ~50 minutes after it's over.
</details>

<details><summary><b>Q3 · "Design alerting for a 99.99% SLO."</b></summary>

**Initial Prompt.** Our payments API targets four nines. Same rules?

**L5 Textbook Answer.** Same burn rates, just change the objective.

**Why L5 Fails at 3 AM or on the Bill.** The budget is 4.3 minutes a month; a 14.4× tier consumes 2% (~5 seconds of outage) before paging, but traffic noise and scrape intervals dominate at that resolution; low-traffic paths make ratios meaningless.

**L7 Principal Defense.** Keep the budget-fraction design but check feasibility: measurement resolution (scrape 15 s, rate windows ≥ 1 m), traffic volume per window, and whether the system can even be repaired within budget (MTTR ≪ 4 min implies automated failover). Often the honest answer is per-request-type SLOs, synthetic probing for coverage, and 99.95% for the human-paged tier with automation guarding four nines.
</details>

<details><summary><b>Q4 · "How do you know your SLO alerts are good?"</b></summary>

**Initial Prompt.** Prove the alerting policy works.

**L5 Textbook Answer.** We haven't missed any incidents.

**Why L5 Fails at 3 AM or on the Bill.** Absence of evidence; no measure of false pages or detection delay.

**L7 Principal Defense.** Backtest: replay 90 days of recorded SLI num/den through the rules (L2 does this on synthetic data) and compare with the incident log — precision (pages that were real), recall (incidents that paged), detection and reset times. Track the same live per quarter. Tune windows, not thresholds, and only with data.
</details>

<details><summary><b>Q5 · "What do you do when the budget is exhausted?"</b></summary>

**Initial Prompt.** The error budget hit zero on day 18. Now what?

**L5 Textbook Answer.** Freeze deployments until next month.

**Why L5 Fails at 3 AM or on the Bill.** A blanket freeze without analysis halts unrelated work and may block the fix itself.

**L7 Principal Defense.** An agreed error-budget policy: releases that affect the SLO's service pause except reliability fixes; postmortems for the top budget consumers; the next sprint prioritises their action items; product leadership signs off on exceptions. The policy is written before the incident, owned jointly by SRE and product.
</details>

<details><summary><b>Q6 · "Availability SLI from logs, metrics or probes?"</b></summary>

**Initial Prompt.** Where should the SLI be measured?

**L5 Textbook Answer.** From the service's own request metrics.

**Why L5 Fails at 3 AM or on the Bill.** Server-side metrics miss requests that never reached the service (LB, DNS, TLS, client timeouts).

**L7 Principal Defense.** As close to the user as feasible: edge/load balancer metrics or RUM for the user-facing SLO; server metrics for team-level SLOs; probes for low-traffic coverage and dependency checks. Different layers, different SLOs, with explicit relationships.
</details>

<details><summary><b>Q7 · "Latency SLO alerting — same method?"</b></summary>

**Initial Prompt.** Apply burn rates to a latency SLO.

**L5 Textbook Answer.** Alert when p99 latency exceeds the target.

**Why L5 Fails at 3 AM or on the Bill.** Quantile thresholds don't map to a budget and can't be summed over time.

**L7 Principal Defense.** Define the latency SLI as a count ratio: bad = requests slower than the threshold (bucket counts at a boundary or native histogram fraction), valid = all. Then identical burn-rate tiers apply. One SLO per (latency threshold, percentile target) pair, e.g. 99% under 300 ms.
</details>

<details><summary><b>Q8 · "How many SLOs per service?"</b></summary>

**Initial Prompt.** Teams want 15 SLOs each.

**L5 Textbook Answer.** As many as needed to cover all features.

**Why L5 Fails at 3 AM or on the Bill.** Each SLO has 4–6 recording rules, 2 alerts and an error-budget policy; dozens per service create alert overlap and rule-evaluation cost nobody reviews.

**L7 Principal Defense.** 2–4 per user journey: availability and latency for the critical paths, maybe freshness for data pipelines. Everything else is a dashboard. Fewer SLOs, rigorously owned, beat many unowned ones.
</details>

---

## 5. Invariants checklist

- [ ] SLIs are count ratios (good/valid), recorded as numerator and denominator rates; absent numerators evaluate to 0.
- [ ] Page tiers: 14.4× over 1h AND 5m, 6× over 6h AND 30m; ticket tier: 1× over 3d AND 6h (or derived from your period and budget fractions).
- [ ] Low-traffic guards or aggregated SLOs exist for services with < ~1 request/s.
- [ ] SLO rules are generated from specs (Sloth/Pyrra/own generator) and unit-tested.
- [ ] Alerting policy is backtested (precision, recall, detection, reset) at least quarterly.
- [ ] Budget reporting uses `increase()` of counts over the period from long-term storage.
- [ ] An error-budget policy is agreed with product owners before it's needed.

---

## 6. References

- *The Site Reliability Workbook*, ch. 5 "Alerting on SLOs": <https://sre.google/workbook/alerting-on-slos/>
- *Site Reliability Engineering*, ch. 4 "Service Level Objectives": <https://sre.google/sre-book/service-level-objectives/>
- Sloth (SLO generator for Prometheus): <https://github.com/slok/sloth>
- Pyrra (SLOs with Prometheus): <https://github.com/pyrra-dev/pyrra>
- OpenSLO specification: <https://github.com/OpenSLO/OpenSLO>
- Grafana SLO documentation: <https://grafana.com/docs/grafana-cloud/alerting-and-irm/slo/>
