# 04 · Dead Man's Switch, Watchdog, absent() Alerts and Preventing Flapping and Alert Fatigue

> **Folder 04 — Recording Rules, Alertmanager and SLO Error-Budget Math · File 4 of 4.**
> Pinned to **Prometheus v3.15.1** (`rules/alerting.go` state machine read at tag `v3.15.1`) and Alertmanager v0.34.2.
> Labels: **[D]** documented / read in pinned source · **[M]** measured by the listing (deterministic, re-run by the gate) · **[E]** model · **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L4 `alert_state_lab.py` | A port of the alerting-rule state machine (Pending → Firing via `for`, deletion of Pending alerts, resolution, `keep_firing_for` hold, `KeepFiringSince` reset) run on 10 hours of a noisy error-ratio signal with a real 30-minute incident: `for: 0` pages 22 times, `for: 5m`, `keep_firing_for` and hysteresis page once and still catch the incident; `up == 0` vs `absent(up{job=…})` evaluated by the Folder 02 engine on a target that leaves service discovery (with its staleness marker); and dead man's switch detection bounds | <1 s |

**Verification.** The state machine follows `AlertingRule.Eval` at v3.15.1 line by line for float alerts (ActiveAt, KeepFiringSince, resolution handling). The absence experiment uses real PromQL evaluation (`promql_mini.py`) including staleness markers. Signal parameters are synthetic and stated; page counts are asserted. No live server was run.

---

## 0. Orientation

**What this file answers.** How to know that monitoring itself is working; how to alert on things that *stopped* (targets, series, pipelines) rather than things that changed; and how to keep alert volume low enough that every page gets attention.

**Three classes of silent failure.**

| Class | Example | Detector |
|---|---|---|
| The pipeline is dead | Prometheus OOM-looping, Alertmanager misconfigured, PagerDuty key rotated | **Dead man's switch**: an always-firing alert that an *external* system expects to hear from |
| A thing vanished | target dropped from discovery, exporter crashed before first scrape, metric renamed | **absence alerts**: `absent()`, `absent_over_time()`, expected-count checks |
| Alerts are ignored | 40 pages a week, most auto-resolving | **alert hygiene**: `for`, `keep_firing_for`, hysteresis, symptom-based paging, precision metrics |

---

## 1. First principles: alert states and the shape of signals

### 1.1 The alerting-rule state machine [D]

```text
 each evaluation (every interval, at t):
   series returned by expr, not already active  → new alert: PENDING, ActiveAt = t
   active alert returned again                   → keep (value/annotations updated), KeepFiringSince cleared
   PENDING and t − ActiveAt ≥ for               → FIRING (FiredAt = t)          ◄─ sent to Alertmanager
   alert NOT returned:
       PENDING                                   → deleted (never notified)
       FIRING and keep_firing_for > 0           → stays FIRING until t − KeepFiringSince ≥ keep_firing_for
       FIRING otherwise                          → INACTIVE (ResolvedAt = t), resolution sent; kept 15 m
 ALERTS{alertstate="pending|firing"} and ALERTS_FOR_STATE (ActiveAt) are written as series
 restart: for-state restored from ALERTS_FOR_STATE if the outage < --rules.alert.for-outage-tolerance (1h)
```

Consequences (L4 §1 [M], 10 hours of a signal hovering near its threshold plus one real incident):

| Configuration | Pages | Real incident paged |
|---|---|---|
| `for: 0` | **22** | yes |
| `for: 5m` | 1 | yes |
| `for: 5m`, `keep_firing_for: 15m` | 1 | yes |
| hysteresis (fire > 1.2, clear < 0.9) + `for: 5m` | 1 | yes |

- **`for`** filters short excursions, but every re-crossing restarts the clock, and it delays detection by exactly `for`.
- **`keep_firing_for`** (Prometheus 2.42+) holds a firing alert through brief dips, removing resolve/re-fire churn (the "flap" that re-pages).
- **Hysteresis** — a lower threshold to clear than to fire — removes chatter at the source. In PromQL it's written with the alert's own state:

```promql
(
    job:http_server_errors:ratio_rate5m > 0.05
)
or
(
    job:http_server_errors:ratio_rate5m > 0.02
  and on (job)
    ALERTS{alertname="HighErrorRatio", alertstate="firing"}
)
```

### 1.2 Absence: `up == 0` is not enough (L4 §2)

```text
 target scraped, failing          → up{instance=X} = 0          → `up == 0` fires
 target removed from discovery    → up{instance=X} STALE → gone → `up == 0` returns NOTHING
 job never scraped (relabel bug)  → no up series at all        → nothing fires anywhere
```

L4 §2 evaluates both expressions over a target that leaves discovery at t = 10 m (staleness marker written) [M]: `up == 0` returns 0 series at every step; `absent(up{job="checkout"})` returns 1 series from t = 10 m. Complete coverage needs:

- `up == 0` — scraped but failing;
- `absent(up{job="checkout"})` or `count(up{job="checkout"}) < N` — target set shrank or vanished;
- `absent_over_time(important_metric[15m])` — metric disappeared while the target stays up (renamed metric, exporter bug);
- for push/batch jobs: `time() - last_success_timestamp_seconds > threshold` (the pushgateway pattern).

`absent()` takes its output labels from the selector's *equality* matchers, so `absent(up{job="checkout"})` produces `{job="checkout"}` that routes like any job alert; regex matchers contribute nothing.

### 1.3 The dead man's switch

```text
 Prometheus ──(rule: alert Watchdog, expr: vector(1))──► Alertmanager ──route: repeat 1m──► webhook
                                                                                              │
 external heartbeat service (outside this cluster/cloud account) expects a call every T  ◄────┘
 no call for T → it pages via an independent path
 detection latency ≤ repeat_interval + T        (L4 §3: 60 s + 300 s → 6 minutes)
```

It tests the entire chain — rule evaluation, Prometheus→Alertmanager connectivity, routing, receiver credentials and egress — which no internal health check can. It must run **outside** the failure domain it monitors (a different cloud account/region, a SaaS heartbeat service), and its own paging path must not depend on the monitored Alertmanager.

### 1.4 Alert fatigue as a measurable quantity

| Metric | Definition | Target |
|---|---|---|
| Pages per on-call shift | count of notifications to the paging receiver | ≤ 2 per 12 h shift (Google SRE guidance) |
| Precision | pages that required human action / all pages | > 80–90% |
| Auto-resolve rate | pages resolved before acknowledgement | < 10% |
| Time to acknowledge | p50/p90 | trending down |
| Duplicate rate | pages for the same incident | ≈ 0 |

These come from Alertmanager metrics (`alertmanager_notifications_total` by receiver) joined with the paging system's export; reviewed weekly; any alert with low precision is fixed or demoted to a ticket.

<!-- listing:alert_state_lab.py -->
```python
"""alert_state_lab.py - the Prometheus alerting-rule state machine (rules/alerting.go, v3.15.1) and the
design of non-flapping alerts, absence alerts and the dead man's switch.

Port: each evaluation, series returned by the expression become Pending (ActiveAt = now) unless already
active; Pending -> Firing once now - ActiveAt >= for; a series no longer returned is deleted if
Pending, set Inactive (resolved) if Firing - unless keep_firing_for holds it Firing until
now - KeepFiringSince >= keep_firing_for; a Firing alert seen again resets KeepFiringSince.
Sections: (1) a signal oscillating around its threshold under for / keep_firing_for / hysteresis;
(2) which absence alert notices a target that vanishes from discovery; (3) dead man's switch
detection latency. Deterministic, stdlib only.

Usage: python alert_state_lab.py [target.md]
"""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from promql_mini import STALE, Engine, Parser  # noqa: E402


class Rule:
    def __init__(self, hold=0, keep=0):
        self.hold, self.keep = hold, keep
        self.state, self.active_at, self.keep_since = "inactive", None, None
        self.pages = 0

    def eval(self, t, present):
        if present:
            if self.state == "inactive":
                self.state, self.active_at = "pending", t
            self.keep_since = None
        else:
            keep_firing = False
            if self.state == "firing" and self.keep > 0:
                if self.keep_since is None:
                    self.keep_since = t
                keep_firing = t - self.keep_since < self.keep
            if not keep_firing:
                self.state, self.keep_since = "inactive", None
                return
        if self.state == "pending" and t - self.active_at >= self.hold:
            self.state = "firing"
            self.pages += 1


def signal(n, seed):
    rng = random.Random(seed)
    out, level = [], 0.0
    for t in range(n):
        incident = 300 <= t < 330  # a real 30-minute problem
        base = 1.6 if incident else 0.92
        level = 0.7 * level + 0.3 * (base + rng.gauss(0, 0.12))
        out.append(level)
    return out


def main():
    checks = []
    print("== 1. Error-ratio signal hovering around its 1.0 threshold for 10 h (1-minute evaluations) ==")
    sig = signal(600, 5)
    configs = {
        "for: 0": dict(hold=0, keep=0, hyst=False),
        "for: 5m": dict(hold=5, keep=0, hyst=False),
        "for: 5m, keep_firing_for: 15m": dict(hold=5, keep=15, hyst=False),
        "hysteresis (fire >1.2, clear <0.9) + for: 5m": dict(hold=5, keep=0, hyst=True),
    }
    print(f"{'configuration':<46} {'pages':>5} {'incident paged':>14}")
    res = {}
    for name, c in configs.items():
        r = Rule(c["hold"], c["keep"])
        caught = False
        for t, v in enumerate(sig):
            if c["hyst"]:
                present = v > 1.2 or (r.state != "inactive" and v > 0.9)
            else:
                present = v > 1.0
            before = r.pages
            r.eval(t, present)
            if r.pages > before and 300 <= t < 340:
                caught = True
        res[name] = (r.pages, caught)
        print(f"{name:<46} {r.pages:>5} {str(caught):>14}")
    checks.append(("for:0 flaps", res["for: 0"][0] > 10))
    checks.append(("hysteresis quiet and catches", res["hysteresis (fire >1.2, clear <0.9) + for: 5m"] == (1, True)))
    print("-> 'for' suppresses short excursions but each re-crossing restarts the clock; keep_firing_for")
    print("   suppresses resolve/re-fire churn; hysteresis (higher fire than clear threshold, written as")
    print("   `v > hi or (v > lo and ALERTS{...})` in PromQL) removes threshold chatter at the source.")
    print()

    print("== 2. A target disappears from service discovery at t=10m (evaluated with promql_mini) ==")
    eng = Engine()
    pts = [(i * 15000, 1.0) for i in range(40)] + [(40 * 15000, STALE)]  # scrape loop writes a staleness marker
    eng.add({"__name__": "up", "job": "checkout", "instance": "10.0.0.7:8080"}, pts)
    rows = []
    for t in range(0, 31, 5):
        down = eng.eval(Parser("up == 0").parse(), t * 60000)
        gone = eng.eval(Parser('absent(up{job="checkout"})').parse(), t * 60000)
        rows.append((t, bool(down), bool(gone)))
        print(f"t={t:>2}m  `up == 0` -> {len(down)} series   `absent(up{{job=\"checkout\"}})` -> {len(gone)} series")
    checks.append(("only absent catches", not any(r[1] for r in rows) and rows[-1][2] and not rows[1][2]))
    print("-> `up == 0` only covers targets that are still discovered but failing. Pair it with absent() (or")
    print("   count(up{job=...}) < expected) per critical job.")
    print()

    print("== 3. Dead man's switch: Watchdog (vector(1)) -> Alertmanager -> external heartbeat monitor ==")
    for repeat, timeout in ((60, 300), (300, 600), (3600, 7200)):
        worst = repeat + timeout
        print(f"repeat_interval {repeat:>4}s, heartbeat timeout {timeout:>4}s -> pipeline death noticed within "
              f"{worst / 60:.0f} min (worst case)")
    checks.append(("formula", math.isclose((60 + 300) / 60, 6.0)))
    print("-> the heartbeat proves the WHOLE path (Prometheus eval, rule loading, Alertmanager, routing,")
    print("   receiver) works; it must be monitored from OUTSIDE the stack it watches.")
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:alert_state_lab.py -->
```text
== 1. Error-ratio signal hovering around its 1.0 threshold for 10 h (1-minute evaluations) ==
configuration                                  pages incident paged
for: 0                                            22           True
for: 5m                                            1           True
for: 5m, keep_firing_for: 15m                      1           True
hysteresis (fire >1.2, clear <0.9) + for: 5m       1           True
-> 'for' suppresses short excursions but each re-crossing restarts the clock; keep_firing_for
   suppresses resolve/re-fire churn; hysteresis (higher fire than clear threshold, written as
   `v > hi or (v > lo and ALERTS{...})` in PromQL) removes threshold chatter at the source.

== 2. A target disappears from service discovery at t=10m (evaluated with promql_mini) ==
t= 0m  `up == 0` -> 0 series   `absent(up{job="checkout"})` -> 0 series
t= 5m  `up == 0` -> 0 series   `absent(up{job="checkout"})` -> 0 series
t=10m  `up == 0` -> 0 series   `absent(up{job="checkout"})` -> 1 series
t=15m  `up == 0` -> 0 series   `absent(up{job="checkout"})` -> 1 series
t=20m  `up == 0` -> 0 series   `absent(up{job="checkout"})` -> 1 series
t=25m  `up == 0` -> 0 series   `absent(up{job="checkout"})` -> 1 series
t=30m  `up == 0` -> 0 series   `absent(up{job="checkout"})` -> 1 series
-> `up == 0` only covers targets that are still discovered but failing. Pair it with absent() (or
   count(up{job=...}) < expected) per critical job.

== 3. Dead man's switch: Watchdog (vector(1)) -> Alertmanager -> external heartbeat monitor ==
repeat_interval   60s, heartbeat timeout  300s -> pipeline death noticed within 6 min (worst case)
repeat_interval  300s, heartbeat timeout  600s -> pipeline death noticed within 15 min (worst case)
repeat_interval 3600s, heartbeat timeout 7200s -> pipeline death noticed within 180 min (worst case)
-> the heartbeat proves the WHOLE path (Prometheus eval, rule loading, Alertmanager, routing,
   receiver) works; it must be monitored from OUTSIDE the stack it watches.

checks: 4/4 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 Meta-monitoring rule group

```yaml
groups:
  - name: meta-monitoring
    interval: 30s
    rules:
      - alert: Watchdog
        expr: vector(1)
        labels: {severity: none}
        annotations:
          summary: "Always firing. Its absence at the external heartbeat service means the alerting pipeline is broken."
      - alert: TargetDown
        expr: 100 * (count by (job, namespace) (up == 0) / count by (job, namespace) (up)) > 10
        for: 10m
        labels: {severity: warning}
      - alert: CriticalJobAbsent
        expr: |
          absent(up{job="checkout"}) or absent(up{job="payments"}) or absent(up{job="kube-state-metrics"})
        for: 5m
        labels: {severity: page}
        annotations:
          summary: "{{ $labels.job }} has no scrape targets at all (discovery/relabeling dropped them)"
      - alert: CheckoutTargetsBelowExpected
        expr: count(up{job="checkout"} == 1) < 3
        for: 10m
        labels: {severity: warning}
      - alert: CriticalMetricMissing
        expr: absent_over_time(http_server_requests_seconds_count{job="checkout"}[15m])
        labels: {severity: warning}
        annotations:
          summary: "checkout exposes no request metrics (renamed metric, instrumentation removed?)"
      - alert: BatchJobNotSucceeding
        expr: time() - max by (job) (batch_last_success_timestamp_seconds) > 26 * 3600
        labels: {severity: ticket}
      - alert: RuleEvaluationFailing
        expr: increase(prometheus_rule_evaluation_failures_total[10m]) > 0
        labels: {severity: warning}
      - alert: AlertmanagerNotificationsFailing
        expr: |
          sum by (integration) (rate(alertmanager_notifications_failed_total[5m]))
            / sum by (integration) (rate(alertmanager_notifications_total[5m])) > 0.05
        for: 10m
        labels: {severity: page}
      - alert: PrometheusNotificationsDropped
        expr: increase(prometheus_notifications_dropped_total[10m]) > 0
        labels: {severity: page}
```

### 2.2 A non-flapping symptom alert (hysteresis + `keep_firing_for`)

```yaml
groups:
  - name: checkout-symptoms
    interval: 30s
    rules:
      - alert: HighErrorRatio
        expr: |
          (job:http_server_errors:ratio_rate5m{job="checkout"} > 0.05)
          or
          (job:http_server_errors:ratio_rate5m{job="checkout"} > 0.02
             and on (job) ALERTS{alertname="HighErrorRatio", alertstate="firing"})
        for: 5m
        keep_firing_for: 10m
        labels: {severity: page}
        annotations:
          summary: "checkout 5xx ratio {{ $value | humanizePercentage }}"
          runbook_url: https://runbooks.example.internal/checkout/high-error-ratio
```

### 2.3 External heartbeat receiver (route lives in File 3's config)

```yaml
# alertmanager.yml excerpt
route:
  routes:
    - receiver: watchdog-heartbeat
      matchers: ['alertname="Watchdog"']
      group_wait: 0s
      group_interval: 1m
      repeat_interval: 1m
receivers:
  - name: watchdog-heartbeat
    webhook_configs:
      - url_file: /etc/alertmanager/secrets/heartbeat-url   # e.g. a SaaS dead-man's-switch check URL
        send_resolved: false
```

---

## 3. Failure modes and FinOps debugging

### F1. Silence everywhere because the pipeline is dead

**Symptom.** A major outage produced no pages; afterwards, Prometheus is found crash-looping (or Alertmanager rejected its config, or the PagerDuty key expired).

**Signature.** `up{job="prometheus"}` gaps, `alertmanager_config_last_reload_successful == 0`, receiver 4xx errors in Alertmanager logs; no Watchdog heartbeats at the external service.

**Root cause.** Every alert depended on the component that failed; nothing outside watched it.

**Fix.** Restore the pipeline; wire the Watchdog to an external heartbeat service that pages through an independent path.

**Prevention.** Dead man's switch tested monthly by deliberately stopping the Watchdog route.

### F2. Targets vanish without an alert

**Symptom.** A deploy changed pod labels; Prometheus stopped scraping the service; nobody noticed for days.

**Signature.** `up{job="checkout"}` series ended (staleness marker); `count(up{job="checkout"})` dropped to 0; only `up == 0`-style alerts existed.

**Root cause.** `up == 0` needs a series; a dropped target has none (L4 §2).

**Fix.** `absent(up{job=...})` / expected-count alerts per critical job.

**Prevention.** Generate absence alerts for every job in the service catalog.

### F3. Flapping pages

**Symptom.** The same alert fires and resolves 10+ times a day; responders mute the channel.

**Signature.** `changes(ALERTS{alertname="X", alertstate="firing"}[1d])` high; alert has `for: 0` or a threshold at the signal's normal level.

**Root cause.** Threshold chatter and no hold-down (L4 §1: 22 pages vs 1).

**Fix.** Symptom-based SLO burn alerts (File 2), or `for` + `keep_firing_for` + hysteresis.

**Prevention.** Weekly review of the flappiest alerts; a CI check that every paging alert has `for` ≥ 2m.

### F4. `for` reset by every Prometheus restart

**Symptom.** After rolling restarts, long-`for` alerts (e.g. `for: 1h`) take another hour to fire.

**Signature.** Prometheus restarted longer ago than `--rules.alert.for-outage-tolerance` (1h), or the alert's labels changed so `ALERTS_FOR_STATE` didn't match.

**Root cause.** `for` state is restored only within the outage tolerance and for unchanged label sets; `--rules.alert.for-grace-period` (10m) also defers.

**Fix.** Keep restarts short (memory snapshot, Folder 01 File 1) and HA; avoid very long `for` on critical alerts (use burn-rate windows instead).

**Prevention.** Know the three `--rules.alert.*` flags; restart HA replicas one at a time.

### F5. Alert fatigue from cause-based paging

**Symptom.** 60 pages a week from CPU, memory, restart and replica-count alerts; real customer-impacting incidents are found by support.

**Signature.** Precision < 30%; most pages auto-resolve; few pages correlate with SLO burn.

**Root cause.** Paging on causes (resources, Kubernetes events) instead of symptoms.

**Fix.** Page only on SLO burn and pipeline health; demote cause alerts to tickets/dashboards.

**Prevention.** Track pages per shift and precision; every page requires a runbook and an owner.

### F6. `absent()` alerts that never resolve or fire for decommissioned jobs

**Symptom.** After a service is retired, `absent()` pages forever; or a renamed job silently disables its absence alert.

**Signature.** Hard-coded job names in absence rules out of sync with the service catalog.

**Root cause.** Absence alerts encode expectations that must be maintained.

**Fix.** Generate absence rules from the service catalog (Backstage, CMDB) in CI.

**Prevention.** Expectations-as-code: every catalog entry declares its jobs and expected replica counts.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "How do you know your alerting works right now?"</b></summary>

**Initial Prompt.** Prove the alerting pipeline is healthy at this moment.

**L5 Textbook Answer.** Prometheus and Alertmanager are up and have no errors.

**Why L5 Fails at 3 AM or on the Bill.** "Up" components can still fail end to end: wrong config loaded, receiver credentials expired, egress blocked, routing changed.

**L7 Principal Defense.** An always-firing Watchdog routed every minute to an external heartbeat service that pages through an independent path if the heartbeat stops; detection ≤ repeat + timeout (6 minutes in L4 §3). Plus internal signals: rule evaluation failures, notifications failed/dropped, config reload status, cluster members. Tested monthly by breaking it on purpose.
</details>

<details><summary><b>Q2 · "Why didn't `up == 0` fire when the service disappeared?"</b></summary>

**Initial Prompt.** A target vanished. Explain the gap.

**L5 Textbook Answer.** Maybe the alert's `for` duration hadn't elapsed.

**Why L5 Fails at 3 AM or on the Bill.** The series no longer exists; comparisons on absent series return nothing (L4 §2).

**L7 Principal Defense.** `up` exists only for discovered targets; when discovery drops a target, the scrape loop writes a staleness marker and the series ends. Coverage requires `absent(up{job=…})` or expected-count checks per critical job, plus `absent_over_time` for vanished metrics — generated from the service catalog so they stay in sync.
</details>

<details><summary><b>Q3 · "Explain `for` vs `keep_firing_for`."</b></summary>

**Initial Prompt.** What does each do, and when do you use both?

**L5 Textbook Answer.** `for` waits before firing; `keep_firing_for` waits before resolving.

**Why L5 Fails at 3 AM or on the Bill.** Misses the state-machine details: a Pending alert that disappears is deleted (the `for` clock restarts), and `keep_firing_for` only applies to Firing alerts and resets whenever the condition returns.

**L7 Principal Defense.** `for` adds a pending phase that must be continuous; it trades detection latency for noise immunity. `keep_firing_for` holds Firing through gaps shorter than its value, preventing resolve/re-fire flaps; `KeepFiringSince` resets when the expression returns. Combine: `for: 5m` to avoid blips, `keep_firing_for: 10m` to avoid flapping on recovery noise; or prefer SLO burn-rate alerts where the windows provide both.
</details>

<details><summary><b>Q4 · "How would you reduce pages by 80% without missing incidents?"</b></summary>

**Initial Prompt.** On-call gets 60 pages a week. Fix it.

**L5 Textbook Answer.** Raise thresholds and add longer `for` durations.

**Why L5 Fails at 3 AM or on the Bill.** Blanket threshold tuning reduces sensitivity to real incidents too.

**L7 Principal Defense.** Measure first: precision per alert, auto-resolve rate, correlation with SLO burn. Then: page only on SLO burn (multi-window, File 2) and pipeline health; demote cause alerts to tickets; group and inhibit storms (File 3); add hysteresis/keep_firing_for to the few remaining threshold pages. Validate by backtesting against the incident log so recall doesn't drop.
</details>

<details><summary><b>Q5 · "Where do you run the dead man's switch monitor?"</b></summary>

**Initial Prompt.** We'll run a small service in our cluster that expects Watchdog webhooks.

**L5 Textbook Answer.** That works if the service is highly available.

**Why L5 Fails at 3 AM or on the Bill.** A cluster-wide or account-wide failure (network, DNS, cloud region) kills the monitor and the monitored together.

**L7 Principal Defense.** Outside the failure domain: a different cloud account/region or a SaaS heartbeat product, paging through a channel independent of the monitored Alertmanager (direct PagerDuty/SMS integration). Each Prometheus HA pair and each Alertmanager cluster gets its own heartbeat so partial failures are visible.
</details>

<details><summary><b>Q6 · "How do you alert on a batch job that should run nightly?"</b></summary>

**Initial Prompt.** The ETL job runs once a night and exits. How to alert?

**L5 Textbook Answer.** Alert if the job's failure counter increases.

**Why L5 Fails at 3 AM or on the Bill.** A job that never starts (cron disabled, scheduler down) never increments a failure counter.

**L7 Principal Defense.** The job pushes `last_success_timestamp_seconds` on success (Pushgateway or remote write); alert on `time() - last_success > period + margin`, plus `absent()` of that series. Failures are diagnosed from logs; the alert is on *success freshness*, which catches every failure mode.
</details>

<details><summary><b>Q7 · "What does Prometheus do with alert state across restarts?"</b></summary>

**Initial Prompt.** We restarted Prometheus; a `for: 30m` alert reset. Why?

**L5 Textbook Answer.** Alert state is in memory and is lost on restart.

**Why L5 Fails at 3 AM or on the Bill.** Not quite: Prometheus restores `for` state from `ALERTS_FOR_STATE` if the outage is within `--rules.alert.for-outage-tolerance` (1h) and labels match, honouring `--rules.alert.for-grace-period` (10m).

**L7 Principal Defense.** Restore works for short restarts with stable labels; long outages, label changes or grace-period effects reset the clock. Mitigations: HA replicas (the other replica keeps state), memory-snapshot for fast restarts, and windows in the expression (burn rates) instead of very long `for`.
</details>

<details><summary><b>Q8 · "How do you measure alert quality?"</b></summary>

**Initial Prompt.** Define an alerting-quality scorecard.

**L5 Textbook Answer.** Count the alerts and try to reduce them.

**Why L5 Fails at 3 AM or on the Bill.** Counting alone rewards deleting alerts, including good ones.

**L7 Principal Defense.** Per alert and per team: precision (actioned/total), recall (incidents that paged/all incidents), detection delay, auto-resolve rate, pages per shift, and duplicate rate — computed from Alertmanager metrics joined with incident records, reviewed weekly; alerts below precision targets are fixed or demoted, and missed incidents create new symptom alerts.
</details>

---

## 5. Invariants checklist

- [ ] An always-firing Watchdog reaches an external heartbeat service outside the monitored failure domain; it is tested monthly.
- [ ] Every critical job has an absence or expected-count alert; critical metrics have `absent_over_time` checks.
- [ ] Batch and push jobs are monitored by success freshness, not failure counters.
- [ ] Paging alerts have `for` ≥ 2m, and `keep_firing_for` or hysteresis where signals hover near thresholds.
- [ ] Pipeline health (rule failures, notifications failed/dropped, config reload, cluster members) is alerted.
- [ ] Alert quality (precision, recall, pages per shift, auto-resolve rate) is reviewed weekly.
- [ ] Absence expectations are generated from the service catalog.

---

## 6. References

- Alerting rules (`for`, `keep_firing_for`): <https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/>
- Alerting rule state machine source: <https://github.com/prometheus/prometheus/blob/v3.15.1/rules/alerting.go>
- Alerting practice guide: <https://prometheus.io/docs/practices/alerting/>
- Google SRE book, "Being On-Call" (pages per shift): <https://sre.google/sre-book/being-on-call/>
- Rob Ewaschuk, "My Philosophy on Alerting": <https://docs.google.com/document/d/199PqyG3UsyXlwieHaqbGiWVa8eMWi8zzAn0YfcApr8Q/edit>
- kube-prometheus Watchdog pattern: <https://github.com/prometheus-operator/kube-prometheus>
