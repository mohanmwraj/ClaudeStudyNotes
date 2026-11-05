# 03 · Production-Ready Recording and SLO Alerting Rules Catalog for Microservices

> **Folder 07 — Production Blueprints: Spring Boot, Kubernetes and Rule Catalogs · File 3 of 3.**
> Pinned to **Prometheus v3.15.1** rule semantics, **Alertmanager v0.34.2**, metric names from **Micrometer 1.17.2** (File 01), kube-state-metrics and cAdvisor (Folder 03).
> Labels: **[D]** documented / read in pinned source · **[M]** measured · **[E]** model · **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L7 `microservice-rules.yaml` | The catalog: 4 groups, 17 recording rules and 10 alerts. It covers availability and latency SLO burn rates, target down, absence, PSP latency, DB pool, heap, CPU throttling and Watchdog | parsed by L8 and gate |
| L8 `rule_catalog_lab.py` | **Static checks.** Every expression parses; every recording rule passes the Folder 04 naming lint; every alert carries severity/team/summary/runbook; page alerts are burn or absence alerts only; burn thresholds equal factor × budget. **Dynamic checks.** 5 h scrape timelines across 7 scenarios each fire exactly the expected alerts. Fast burn fires 6 min after a 20% outage, latency burn 36 min after 25% of requests go slow, target-down 6 min after onset and absent 10 min after onset. A PSP p99 alert fires in 10 min, and **never fires when no bucket exists above the threshold** | ~7 s |

**Verification.**
- **Engine.** Dynamic tests run the rules with `promql_mini` (Folder 02, which passes 695/695 attempted upstream `promqltest` cases).
- **Rule manager.** A minimal one evaluates recording rules every 2 min and writes their outputs back as series, as Prometheus's rule manager does. Alerts follow pending→firing with `for`.
- **Scope.** This is a stand-in for `promtool test rules`, which was not run because executing downloaded binaries is blocked here. A `promtool` test file for the same catalog is in §2.3.

---

## 0. Orientation

**What this file answers.**
- Which rules a Java microservice actually needs.
- How they are named, layered and routed.
- How to prove they fire when they should and stay silent when they shouldn't, before an incident tests them for you.

**Layered rule architecture.**

```text
 raw series (File 01 meters, KSM, cAdvisor)                     ← scraped, high cardinality
   │ recording group "checkout-sli-recording" (30s)
   ▼
 job:http_server_requests[_errors|_slow]:rate{5m,30m,1h,2h,6h,1d,3d}   ← tiny, per job, every SLO window
   │ alert group "checkout-slo-alerts"   → severity page | ticket   (symptoms: users hurt)
   │ alert group "checkout-runtime-alerts" → ticket (causes) + page only for "blind" (absent)
   ▼
 Alertmanager route: severity=page → PagerDuty; severity=ticket → Jira/Slack; Watchdog → dead-man's switch
```

**Design rules.**
1. **Page on symptoms only.** Burn rates and blindness (absence) page. Causes (heap, throttling, pool) open tickets.
2. **Every alert names an owner and a runbook.** `team` is inherited from the Service via `targetLabels` (File 02).
3. **Every threshold is backed by a bucket or a recorded ratio** that makes it exact (File 01 §1.2).
4. **Rules are code.** They are unit-tested against synthetic timelines in CI (L8).

---

## 1. First principles

### 1.1 SLO arithmetic behind the catalog [D]

| SLO | Budget (30 d) | Fast page | Slow ticket |
|---|---|---|---|
| Availability 99.9% (5xx = bad) | 0.1% of requests ≈ 43.2 min of full outage | 14.4× over 1h & 5m, or 6× over 6h & 30m | 3× over 1d & 2h, or 1× over 3d & 6h |
| Latency 99% < 300 ms | 1% of requests | 14.4× over 1h & 5m | — (add tiers as for availability) |

**Where the multipliers come from** (SRE Workbook, reproduced in Folder 04 `burn_rate_lab.py`):
- **14.4×** for 1h consumes 2% of the 30-day budget.
- **6×** for 6h consumes 5%.
- **3×** for 1d consumes 10%.
- The short window (1/12 of the long one) makes the alert reset quickly after recovery.
- L8 checks that the catalog's thresholds are exactly `{14.4, 6, 3, 1} × 0.001` and `14.4 × 0.01`.

### 1.2 Why recording rules, and how they are named [D]

- **The burn alerts need 7 windows × 2 numerators.** Computing `rate(…[3d])` across all raw series on every 30 s evaluation is expensive and slow. Recording each window once per group interval makes the alerts cheap and consistent.
- **Naming follows `level:metric:operations`.**
  - Level: the labels kept (`job`).
  - Metric: the source metric, extended (`http_server_requests_errors`).
  - Operations: `rate5m`.
- Folder 04's `rules_lab.lint` enforces this, and L8 runs it on all 17 recording rules: 0 issues.
- **Exclude actuator traffic in the recording layer.** Excluding it once (`uri!~"/actuator.*"`) keeps scrape and probe requests from diluting the error ratio. The synthetic timelines include 2 actuator requests per minute per pod to exercise this.
- **The latency SLI is "requests minus requests ≤ 0.3 s".** It uses the `le="0.3"` bucket, which exists only because File 01 configured 300 ms as an SLO boundary.

### 1.3 How an alert fires: evaluation, `for`, and detection time [D][M]

**Evaluation.**
- Each group evaluates every `interval`, and an alert is *pending* from the first true evaluation.
- It fires once true for `for` (state machine ported in Folder 04 `alert_state_lab.py`).
- Recording-rule outputs are written at evaluation time, so a rule reading a recorded series sees the value from the latest group evaluation within the 5-minute lookback.

**How the two windows of the fast-burn tier move during L8's 20% outage** (threshold 14.4 × 0.1% = 1.44%) [E]:

```text
 ratio
 20%  ┤        5m window ▕▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▏ (crosses 1.44% within ~1 min of onset)
      │                  ▕                             ▏╲
 1h   │  1h window       ▕      ╱▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▏ ╲___ slowly decays for an hour
      │                  ▕    ╱  (1.44% after 0.0144/0.20 × 60 ≈ 4.3 min)
 1.44%┤┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄▕┄┄╱┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄▏┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
 0.02%┤▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▕▁╱                            ▏
      └──────────────────┬──┬──┬───────────────────────┬──┬──────────────────── time
                       3h00 │  └ fires at 3h06 (both windows > 1.44% for `for: 2m`, 2-min eval grid)
                            └ pending ≈ 3h04             3h30 └ 5m window drops below → alert resolves
                                                               within minutes, while the 1h window alone
                                                               would have kept it firing for ~40 more minutes
```

**Detection time** measured by L8 at 2-min evaluation steps:

| Scenario | Fired | After onset |
|---|---|---|
| 20% errors for 30 min | Availability fast burn (page), then slow burn (ticket) | +6 min (page), +16 min (ticket) |
| 0.5% errors constantly (5× budget) | Slow burn only: 5× < 6× page threshold, > 3× ticket threshold | at 18 min of data |
| 25% slow requests | Latency fast burn | **+36 min**: the 1h window needs ~35 min to average above 14.4% |
| One pod's scrape fails | TargetDown | +6 min (`for: 5m`) |
| All pods gone (staleness) | Absent | +10 min (`for: 10m`) |
| 5% of PSP calls ~2 s | PSP p99 > 1 s | +10 min |
| Same, but buckets end at 1 s | **nothing** | never: `histogram_quantile` caps at the highest finite bucket |

- **The latency row is a real design trade-off.** At 25× burn the budget is still safe for hours, so +36 min is acceptable. A sharper page would need a 5-minute-only tier with its false-positive cost.
- **The last row is the most common silent failure in alerting.** The alert *looks* right, passes review and can never fire.

### 1.4 Alert metadata is an API [D]

L8 enforces these on every alert except Watchdog:

| Field | Required | Used by |
|---|---|---|
| `labels.severity` ∈ {page, ticket, none} | yes | Alertmanager routing (Folder 04: `Route.Match` port) |
| `labels.team` | yes | Routing to the owning team's receiver |
| `labels.slo` | on burn alerts | Grouping and SLO dashboards |
| `annotations.summary` | yes | Notification title |
| `annotations.runbook_url` | yes | The first click of the on-call |
| `annotations.description`, `dashboard_url` | recommended | Context; `{{ $value \| humanizePercentage }}` |

**No cause-based paging.** `severity: page` is allowed only on burn-rate and `absent()` alerts. Heap, CPU throttling and pool saturation are *causes*. They open tickets, and if they hurt users the burn alert pages anyway.

<!-- listing:microservice-rules.yaml -->
```yaml
# Rule catalog for one Spring Boot microservice (job="checkout"), built on the meters of File 01.
# SLOs: availability 99.9% (5xx = bad) and latency 99% of requests under 300 ms (needs the le="0.3"
# SLO boundary configured in application.yaml). Burn-rate tiers follow the SRE Workbook:
# page = 14.4x over 1h&5m or 6x over 6h&30m; ticket = 3x over 1d&2h or 1x over 3d&6h.
groups:
  - name: checkout-sli-recording
    interval: 30s
    rules:
      - record: job:http_server_requests:rate5m
        expr: sum by (job) (rate(http_server_requests_seconds_count{job="checkout", uri!~"/actuator.*"}[5m]))
      - record: job:http_server_requests_errors:rate5m
        expr: sum by (job) (rate(http_server_requests_seconds_count{job="checkout", uri!~"/actuator.*", outcome="SERVER_ERROR"}[5m]))
      - record: job:http_server_requests:rate30m
        expr: sum by (job) (rate(http_server_requests_seconds_count{job="checkout", uri!~"/actuator.*"}[30m]))
      - record: job:http_server_requests_errors:rate30m
        expr: sum by (job) (rate(http_server_requests_seconds_count{job="checkout", uri!~"/actuator.*", outcome="SERVER_ERROR"}[30m]))
      - record: job:http_server_requests:rate1h
        expr: sum by (job) (rate(http_server_requests_seconds_count{job="checkout", uri!~"/actuator.*"}[1h]))
      - record: job:http_server_requests_errors:rate1h
        expr: sum by (job) (rate(http_server_requests_seconds_count{job="checkout", uri!~"/actuator.*", outcome="SERVER_ERROR"}[1h]))
      - record: job:http_server_requests:rate2h
        expr: sum by (job) (rate(http_server_requests_seconds_count{job="checkout", uri!~"/actuator.*"}[2h]))
      - record: job:http_server_requests_errors:rate2h
        expr: sum by (job) (rate(http_server_requests_seconds_count{job="checkout", uri!~"/actuator.*", outcome="SERVER_ERROR"}[2h]))
      - record: job:http_server_requests:rate6h
        expr: sum by (job) (rate(http_server_requests_seconds_count{job="checkout", uri!~"/actuator.*"}[6h]))
      - record: job:http_server_requests_errors:rate6h
        expr: sum by (job) (rate(http_server_requests_seconds_count{job="checkout", uri!~"/actuator.*", outcome="SERVER_ERROR"}[6h]))
      - record: job:http_server_requests:rate1d
        expr: sum by (job) (rate(http_server_requests_seconds_count{job="checkout", uri!~"/actuator.*"}[1d]))
      - record: job:http_server_requests_errors:rate1d
        expr: sum by (job) (rate(http_server_requests_seconds_count{job="checkout", uri!~"/actuator.*", outcome="SERVER_ERROR"}[1d]))
      - record: job:http_server_requests:rate3d
        expr: sum by (job) (rate(http_server_requests_seconds_count{job="checkout", uri!~"/actuator.*"}[3d]))
      - record: job:http_server_requests_errors:rate3d
        expr: sum by (job) (rate(http_server_requests_seconds_count{job="checkout", uri!~"/actuator.*", outcome="SERVER_ERROR"}[3d]))
      - record: job:http_server_requests_seconds_bucket:rate5m
        expr: sum by (job, le) (rate(http_server_requests_seconds_bucket{job="checkout", uri!~"/actuator.*"}[5m]))
      - record: job:http_server_requests_slow:rate5m
        expr: |
          sum by (job) (rate(http_server_requests_seconds_count{job="checkout", uri!~"/actuator.*"}[5m]))
          - sum by (job) (rate(http_server_requests_seconds_bucket{job="checkout", uri!~"/actuator.*", le="0.3"}[5m]))
      - record: job:http_server_requests_slow:rate1h
        expr: |
          sum by (job) (rate(http_server_requests_seconds_count{job="checkout", uri!~"/actuator.*"}[1h]))
          - sum by (job) (rate(http_server_requests_seconds_bucket{job="checkout", uri!~"/actuator.*", le="0.3"}[1h]))

  - name: checkout-slo-alerts
    interval: 30s
    rules:
      - alert: CheckoutAvailabilityBudgetBurnFast
        expr: |
          (
            job:http_server_requests_errors:rate1h / job:http_server_requests:rate1h > (14.4 * 0.001)
            and
            job:http_server_requests_errors:rate5m / job:http_server_requests:rate5m > (14.4 * 0.001)
          )
          or
          (
            job:http_server_requests_errors:rate6h / job:http_server_requests:rate6h > (6 * 0.001)
            and
            job:http_server_requests_errors:rate30m / job:http_server_requests:rate30m > (6 * 0.001)
          )
        for: 2m
        labels:
          severity: page
          team: payments
          slo: checkout-availability
        annotations:
          summary: Checkout is burning its 99.9% availability budget fast
          description: Error ratio {{ $value | humanizePercentage }} over the burn window; at this rate the 30-day budget is gone in under 3 days.
          runbook_url: https://runbooks.acme.internal/checkout/availability-burn
          dashboard_url: https://grafana.acme.internal/d/checkout-red
      - alert: CheckoutAvailabilityBudgetBurnSlow
        expr: |
          (
            job:http_server_requests_errors:rate1d / job:http_server_requests:rate1d > (3 * 0.001)
            and
            job:http_server_requests_errors:rate2h / job:http_server_requests:rate2h > (3 * 0.001)
          )
          or
          (
            job:http_server_requests_errors:rate3d / job:http_server_requests:rate3d > (1 * 0.001)
            and
            job:http_server_requests_errors:rate6h / job:http_server_requests:rate6h > (1 * 0.001)
          )
        for: 15m
        labels:
          severity: ticket
          team: payments
          slo: checkout-availability
        annotations:
          summary: Checkout is consuming its availability budget faster than it accrues
          description: Sustained error ratio above the budget rate; investigate within business hours.
          runbook_url: https://runbooks.acme.internal/checkout/availability-burn
      - alert: CheckoutLatencyBudgetBurnFast
        expr: |
          job:http_server_requests_slow:rate1h / job:http_server_requests:rate1h > (14.4 * 0.01)
          and
          job:http_server_requests_slow:rate5m / job:http_server_requests:rate5m > (14.4 * 0.01)
        for: 2m
        labels:
          severity: page
          team: payments
          slo: checkout-latency
        annotations:
          summary: More than 14.4% of checkout requests are slower than 300 ms
          description: Slow-request ratio {{ $value | humanizePercentage }}; the 99%-under-300ms budget burns 14.4x too fast.
          runbook_url: https://runbooks.acme.internal/checkout/latency-burn

  - name: checkout-runtime-alerts
    interval: 30s
    rules:
      - alert: CheckoutTargetDown
        expr: up{job="checkout"} == 0
        for: 5m
        labels:
          severity: ticket
          team: payments
        annotations:
          summary: Prometheus cannot scrape {{ $labels.pod }}
          description: The target is discovered but failing; pods that vanished from discovery are covered by CheckoutAbsent.
          runbook_url: https://runbooks.acme.internal/checkout/target-down
      - alert: CheckoutAbsent
        expr: absent(up{job="checkout"})
        for: 10m
        labels:
          severity: page
          team: payments
        annotations:
          summary: No checkout targets are being scraped at all
          description: Either every pod is gone or service discovery/ServiceMonitor selection broke; RED and SLO alerts are blind.
          runbook_url: https://runbooks.acme.internal/checkout/absent
      - alert: CheckoutPspLatencyHigh
        expr: histogram_quantile(0.99, sum by (le, psp) (rate(checkout_psp_latency_seconds_bucket{job="checkout"}[5m]))) > 1
        for: 10m
        labels:
          severity: ticket
          team: payments
        annotations:
          summary: p99 latency to {{ $labels.psp }} is above 1 s
          description: p99 is {{ $value | humanizeDuration }}; check PSP status and the circuit breaker.
          runbook_url: https://runbooks.acme.internal/checkout/psp-latency
      - alert: CheckoutDbPoolSaturated
        expr: max by (pod) (hikaricp_connections_pending{job="checkout"}) > 5
        for: 5m
        labels:
          severity: ticket
          team: payments
        annotations:
          summary: '{{ $labels.pod }} has threads waiting for a database connection'
          description: Pending connection requests above 5 for 5 minutes; see Folder 03 for pool sizing with Erlang C.
          runbook_url: https://runbooks.acme.internal/checkout/db-pool
      - alert: CheckoutHeapPressure
        expr: |
          sum by (pod) (jvm_memory_used_bytes{job="checkout", area="heap"})
          / sum by (pod) (jvm_memory_max_bytes{job="checkout", area="heap"} > 0) > 0.9
        for: 15m
        labels:
          severity: ticket
          team: payments
        annotations:
          summary: '{{ $labels.pod }} heap above 90% for 15 minutes'
          description: Heap {{ $value | humanizePercentage }} of max; expect GC thrash or OOMKilled.
          runbook_url: https://runbooks.acme.internal/checkout/heap
      - alert: CheckoutCpuThrottled
        expr: |
          sum by (namespace, pod) (rate(container_cpu_cfs_throttled_periods_total{namespace="shop", container="checkout"}[5m]))
          / sum by (namespace, pod) (rate(container_cpu_cfs_periods_total{namespace="shop", container="checkout"}[5m])) > 0.25
        for: 15m
        labels:
          severity: ticket
          team: payments
        annotations:
          summary: '{{ $labels.pod }} is CPU-throttled in {{ $value | humanizePercentage }} of CFS periods'
          description: Throttling inflates tail latency long before average CPU looks high; see Folder 03 CFS simulation.
          runbook_url: https://runbooks.acme.internal/checkout/cpu-throttling

  - name: meta
    rules:
      - alert: Watchdog
        expr: vector(1)
        labels:
          severity: none
        annotations:
          summary: Always-firing heartbeat that proves the alerting pipeline works end to end
          description: Routed to an external dead man's switch; silence of this alert is the page.
```

<!-- listing:rule_catalog_lab.py -->
```python
"""rule_catalog_lab.py - unit tests for a production rule catalog, the way `promtool test rules` would
run them, using this KB's PromQL engine instead of a Prometheus binary:

  * loads microservice-rules.yaml (this folder) with a small YAML-subset reader;
  * static checks: every expression parses (promql_mini.Parser, Folder 02), every recording rule passes
    rules_lab.lint (Folder 04), every alert has severity/team/summary/runbook_url, page alerts are
    burn-rate or absence alerts, and burn thresholds equal factor x error budget;
  * dynamic checks: synthetic scrape timelines (60 s scrapes, 5 h) for healthy traffic and six failure
    scenarios; recording rules are evaluated every 2 m and written back as series (as the rule manager
    does), alerts run a pending/firing state machine honouring `for`; each scenario asserts exactly which
    alerts fire and how fast.

promql_mini passes 695/695 attempted upstream promqltest cases (Folder 02). Deterministic, stdlib only.
Usage: python rule_catalog_lab.py [target.md]
"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from promql_mini import STALE, Engine, Parser  # noqa: E402
from rules_lab import lint  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent


def load_yaml_subset(text):
    """Maps, lists of maps ('- key: v'), block scalars ('|'), quoted scalars, comments."""
    lines = []
    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            lines.append(None)
            continue
        lines.append((len(raw) - len(raw.lstrip()), raw.strip(), raw))

    def scalar(v):
        v = v.strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
            return v[1:-1]
        return v

    def block(i, indent):
        while i < len(lines) and lines[i] is None:
            i += 1
        if i >= len(lines):
            return None, i
        if lines[i][1].startswith("- "):
            out = []
            while i < len(lines) and (lines[i] is None or (lines[i][0] == indent and lines[i][1].startswith("- "))):
                if lines[i] is None:
                    i += 1
                    continue
                ind, txt, raw = lines[i]
                lines[i] = (ind + 2, txt[2:], raw)
                item, i = block(i, ind + 2)
                out.append(item)
            return out, i
        out = {}
        while i < len(lines):
            if lines[i] is None:
                i += 1
                continue
            ind, txt, _ = lines[i]
            if ind != indent or txt.startswith("- "):
                break
            key, _, rest = txt.partition(":")
            rest = rest.strip()
            i += 1
            if rest in ("|", "|-", ">", ">-"):
                body = []
                while i < len(lines) and (lines[i] is None or lines[i][0] > indent):
                    body.append("" if lines[i] is None else lines[i][2])
                    i += 1
                pad = min(len(b) - len(b.lstrip()) for b in body if b.strip())
                out[key] = "\n".join(b[pad:] for b in body).strip("\n") + "\n"
            elif rest == "":
                j = i
                while j < len(lines) and lines[j] is None:
                    j += 1
                out[key], i = block(j, lines[j][0]) if j < len(lines) else (None, j)
            else:
                out[key] = scalar(rest)
        return out, i
    return block(0, 0)[0]


def dur_ms(s):
    return int(s[:-1]) * {"s": 1000, "m": 60000, "h": 3600000}[s[-1]] if s else 0


class RuleManager:
    def __init__(self, groups):
        self.rules = [(r, Parser(r["expr"]).parse()) for g in groups for r in g["rules"]]
        self.active = {}            # (alert, labels) -> since
        self.fired = {}             # alert -> first firing time

    def step(self, eng, T):
        for rule, ast in self.rules:
            vec = eng.eval(ast, T)
            if "record" in rule:
                for lbls, v, _ in vec:
                    eng.add({**{k: x for k, x in lbls.items() if k != "__name__"}, "__name__": rule["record"]}, [(T, v)])
                continue
            seen = set()
            for lbls, v, _ in vec:
                key = (rule["alert"], tuple(sorted((k, x) for k, x in lbls.items() if k != "__name__")))
                seen.add(key)
                since = self.active.setdefault(key, T)
                if T - since >= dur_ms(rule.get("for", "")):
                    self.fired.setdefault(rule["alert"], T)
            for key in [k for k in self.active if k[0] == rule["alert"] and k not in seen]:
                del self.active[key]


def timeline(hours=5, err=lambda t: 0.0002, slow=lambda t: 0.005, psp_slow=lambda t: 0.0,
             down=lambda t, pod: False, gone=lambda t: False, psp_buckets=(0.1, 0.3, 1.0, 2.5, 5.0)):
    eng = Engine()
    pods = ["checkout-a", "checkout-b", "checkout-c"]
    rps, step = 20.0, 60000
    state = {}
    for k in range(hours * 60 + 1):
        T = k * step
        h = T / 3600000
        for pod in pods:
            base = {"job": "checkout", "pod": pod}
            if gone(h):
                if not state.get(("gone", pod)):
                    for key in [s for s in state if isinstance(s, tuple) and s[0] == "series" and s[1] == pod]:
                        eng.add(state[key], [(T, STALE)])
                    eng.add({"__name__": "up", **base}, [(T, STALE)])
                    state[("gone", pod)] = True
                continue
            if down(h, pod):
                eng.add({"__name__": "up", **base}, [(T, 0.0)])
                continue
            eng.add({"__name__": "up", **base}, [(T, 1.0)])
            n = rps * 60
            e, s = err(h), slow(h)
            incs = {
                ("count", "/api/checkout", "SUCCESS"): n * (1 - e),
                ("count", "/api/checkout", "SERVER_ERROR"): n * e,
                ("count", "/actuator/prometheus", "SUCCESS"): 2.0,
            }
            for (_, uri, outcome), inc in incs.items():
                lbl = {"__name__": "http_server_requests_seconds_count", **base, "uri": uri, "outcome": outcome}
                key = ("series", pod, "c", uri, outcome)
                state[key] = lbl
                state[("v",) + key[1:]] = state.get(("v",) + key[1:], 0.0) + inc
                eng.add(lbl, [(T, state[("v",) + key[1:]])])
            for le, frac in (("0.1", (1 - s) * 0.7), ("0.3", 1 - s), ("1.0", 1 - s * 0.2), ("+Inf", 1.0)):
                lbl = {"__name__": "http_server_requests_seconds_bucket", **base, "uri": "/api/checkout", "le": le}
                key = ("series", pod, "b", le)
                state[key] = lbl
                state[("v",) + key[1:]] = state.get(("v",) + key[1:], 0.0) + n * frac
                eng.add(lbl, [(T, state[("v",) + key[1:]])])
            p = psp_slow(h)
            calls = 300.0
            cum = {0.1: 0.6 * (1 - p), 0.3: 0.95 * (1 - p), 1.0: 1 - p, 2.5: 1.0 - p * 0.1, 5.0: 1.0}
            for le in list(psp_buckets) + ["+Inf"]:
                frac = 1.0 if le == "+Inf" else cum[le]
                lbl = {"__name__": "checkout_psp_latency_seconds_bucket", **base, "psp": "stripe",
                       "le": le if le == "+Inf" else repr(le)}
                key = ("series", pod, "p", str(le))
                state[key] = lbl
                state[("v",) + key[1:]] = state.get(("v",) + key[1:], 0.0) + calls * frac
                eng.add(lbl, [(T, state[("v",) + key[1:]])])
    return eng


def run(groups, eng, hours=5, every=120000):
    rm = RuleManager(groups)
    for T in range(0, hours * 3600000 + 1, every):
        rm.step(eng, T)
    return {a: t / 60000 for a, t in rm.fired.items()}


def main():
    checks = []
    doc = load_yaml_subset((HERE / "microservice-rules.yaml").read_text(encoding="utf-8"))
    groups = doc["groups"]
    rules = [r for g in groups for r in g["rules"]]
    records = [r for r in rules if "record" in r]
    alerts = [r for r in rules if "alert" in r]
    print(f"== 1. Static checks on {len(groups)} groups, {len(records)} recording rules, {len(alerts)} alerts ==")
    parse_fail = []
    for r in rules:
        try:
            Parser(r["expr"]).parse()
        except Exception as ex:  # noqa: BLE001
            parse_fail.append((r.get("record") or r.get("alert"), str(ex)[:60]))
    lint_issues = [(r["record"], i) for r in records for i in lint(r)]
    meta_issues = []
    for a in alerts:
        lab, ann = a.get("labels", {}), a.get("annotations", {})
        if lab.get("severity") not in ("page", "ticket", "none"):
            meta_issues.append((a["alert"], "severity"))
        if a["alert"] != "Watchdog":
            for need in ("team",):
                if need not in lab:
                    meta_issues.append((a["alert"], need))
            for need in ("summary", "runbook_url"):
                if need not in ann:
                    meta_issues.append((a["alert"], need))
        if lab.get("severity") == "page" and not ("Burn" in a["alert"] or "absent(" in a["expr"]):
            meta_issues.append((a["alert"], "page alerts must be SLO burn or absence alerts"))
    burn = []
    for a in alerts:
        for factor, budget in re.findall(r"\(\s*([0-9.]+)\s*\*\s*(0\.0+1)\s*\)", a["expr"]):
            burn.append((a["alert"], float(factor), float(budget)))
    expected = {(14.4, 0.001), (6.0, 0.001), (3.0, 0.001), (1.0, 0.001), (14.4, 0.01)}
    print(f"parse failures {len(parse_fail)}, recording-rule lint issues {len(lint_issues)}, alert metadata issues "
          f"{len(meta_issues)}")
    print(f"burn tiers found: {sorted({(f, b) for _, f, b in burn})}")
    checks.append(("static", not parse_fail and not lint_issues and not meta_issues and
                   {(f, b) for _, f, b in burn} == expected))
    print()

    print("== 2. Scenario tests (60 s scrapes, rules every 2 m, 5 h) ==")
    scen = [
        ("healthy: 0.02% errors, 0.5% slow", timeline(), {"Watchdog"}),
        ("outage: 20% errors from 3h00 to 3h30", timeline(err=lambda t: 0.2 if 3 <= t < 3.5 else 0.0002),
         {"Watchdog", "CheckoutAvailabilityBudgetBurnFast", "CheckoutAvailabilityBudgetBurnSlow"}),
        ("slow burn: 0.5% errors all day", timeline(err=lambda t: 0.005),
         {"Watchdog", "CheckoutAvailabilityBudgetBurnSlow"}),
        ("latency: 25% of requests > 300ms from 2h", timeline(slow=lambda t: 0.25 if t >= 2 else 0.005),
         {"Watchdog", "CheckoutLatencyBudgetBurnFast"}),
        ("pod b scrape fails from 2h; every pod gone at 4h",
         timeline(down=lambda t, pod: pod == "checkout-b" and 2 <= t < 4, gone=lambda t: t >= 4),
         {"Watchdog", "CheckoutTargetDown", "CheckoutAbsent"}),
        ("PSP: 5% of calls take ~2 s from 3h", timeline(psp_slow=lambda t: 0.05 if t >= 3 else 0.0),
         {"Watchdog", "CheckoutPspLatencyHigh"}),
        ("same PSP incident, but no bucket above 1 s", timeline(psp_slow=lambda t: 0.05 if t >= 3 else 0.0,
                                                               psp_buckets=(0.1, 0.3, 1.0)), {"Watchdog"}),
    ]
    starts = {"CheckoutAvailabilityBudgetBurnFast": 180, "CheckoutLatencyBudgetBurnFast": 120,
              "CheckoutTargetDown": 120, "CheckoutAbsent": 240, "CheckoutPspLatencyHigh": 180}
    for name, eng, want in scen:
        fired = run(groups, eng)
        ok = set(fired) == want
        checks.append((name, ok))
        detail = ", ".join(f"{a} @ {m:.0f}m" + (f" (+{m - starts[a]:.0f}m after onset)" if a in starts and not
                                                 name.startswith("slow burn") else "")
                           for a, m in sorted(fired.items(), key=lambda x: x[1]) if a != "Watchdog")
        print(f"{'ok ' if ok else 'BAD'} {name:<52} -> {detail or 'only Watchdog'}")
    print("-> the last row is the classic trap: histogram_quantile caps at the highest finite bucket (1 s),")
    print("   so `> 1` can never be true. Buckets must extend past every alert threshold.")
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:rule_catalog_lab.py -->
```text
== 1. Static checks on 4 groups, 17 recording rules, 10 alerts ==
parse failures 0, recording-rule lint issues 0, alert metadata issues 0
burn tiers found: [(1.0, 0.001), (3.0, 0.001), (6.0, 0.001), (14.4, 0.001), (14.4, 0.01)]

== 2. Scenario tests (60 s scrapes, rules every 2 m, 5 h) ==
ok  healthy: 0.02% errors, 0.5% slow                     -> only Watchdog
ok  outage: 20% errors from 3h00 to 3h30                 -> CheckoutAvailabilityBudgetBurnFast @ 186m (+6m after onset), CheckoutAvailabilityBudgetBurnSlow @ 196m
ok  slow burn: 0.5% errors all day                       -> CheckoutAvailabilityBudgetBurnSlow @ 18m
ok  latency: 25% of requests > 300ms from 2h             -> CheckoutLatencyBudgetBurnFast @ 156m (+36m after onset)
ok  pod b scrape fails from 2h; every pod gone at 4h     -> CheckoutTargetDown @ 126m (+6m after onset), CheckoutAbsent @ 250m (+10m after onset)
ok  PSP: 5% of calls take ~2 s from 3h                   -> CheckoutPspLatencyHigh @ 190m (+10m after onset)
ok  same PSP incident, but no bucket above 1 s           -> only Watchdog
-> the last row is the classic trap: histogram_quantile caps at the highest finite bucket (1 s),
   so `> 1` can never be true. Buckets must extend past every alert threshold.

checks: 8/8 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 Alertmanager routing for the catalog (v0.34)

```yaml
route:
  receiver: default-slack
  group_by: [alertname, team, slo]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    - matchers: [alertname = "Watchdog"]
      receiver: deadmansswitch
      repeat_interval: 1m
      group_wait: 0s
    - matchers: [severity = "page"]
      receiver: pagerduty-payments
      continue: true
      routes:
        - matchers: [team = "payments"]
          receiver: pagerduty-payments
    - matchers: [severity = "ticket"]
      receiver: jira-payments
      repeat_interval: 24h
inhibit_rules:
  - source_matchers: [alertname = "CheckoutAbsent"]
    target_matchers: [team = "payments", alertname =~ "Checkout.*", alertname != "CheckoutAbsent"]
    equal: [team]
  - source_matchers: [severity = "page", slo = "checkout-availability"]
    target_matchers: [severity = "ticket", slo = "checkout-availability"]
    equal: [slo]
receivers:
  - name: default-slack
  - name: deadmansswitch
  - name: pagerduty-payments
  - name: jira-payments
```

**Why.**
- **`CheckoutAbsent` inhibits the rest.** When the service is blind, every other checkout alert is noise.
- **A page inhibits its own ticket tier.** It does so for the same SLO.
- **Watchdog repeats every minute** to an external heartbeat (Folder 04 `alert_state_lab.py` §3).
- **Receivers are stubs here.** Fill them with real integrations.

### 2.2 Generalising the catalog: one template, many services

```yaml
# rules-template.yaml rendered per service by Helm/Jsonnet/CUE: only these inputs vary.
service: checkout
team: payments
availability_slo: 0.999
latency_slo:
  threshold_seconds: 0.3
  target: 0.99
burn_tiers:
  page:
    - {long: 1h, short: 5m, factor: 14.4}
    - {long: 6h, short: 30m, factor: 6}
  ticket:
    - {long: 1d, short: 2h, factor: 3}
    - {long: 3d, short: 6h, factor: 1}
runbook_base: https://runbooks.acme.internal/checkout
```

Folder 05 `mixin_lab.py` shows the generator pattern: a spec produces rules plus dashboards, and the Folder 04 linters run on the output. The rendered output for `checkout` is exactly L7. CI renders every service and runs the L8 static checks on each.

### 2.3 `promtool test rules` file for the same catalog

```yaml
# checkout-rules.test.yaml: run with `promtool test rules checkout-rules.test.yaml` in CI
rule_files:
  - microservice-rules.yaml
evaluation_interval: 30s
tests:
  - interval: 1m
    input_series:
      - series: 'http_server_requests_seconds_count{job="checkout", pod="checkout-a", uri="/api/checkout", outcome="SUCCESS"}'
        values: '0+1200x120 144960+960x39'
      - series: 'http_server_requests_seconds_count{job="checkout", pod="checkout-a", uri="/api/checkout", outcome="SERVER_ERROR"}'
        values: '0+0x120 240+240x39'
      - series: 'up{job="checkout", pod="checkout-a"}'
        values: '1x160'
    alert_rule_test:
      - eval_time: 115m
        alertname: CheckoutAvailabilityBudgetBurnFast
        exp_alerts: []
      - eval_time: 130m
        alertname: CheckoutAvailabilityBudgetBurnFast
        exp_alerts:
          - exp_labels:
              severity: page
              team: payments
              slo: checkout-availability
              job: checkout
  - interval: 1m
    input_series:
      - series: 'up{job="checkout", pod="checkout-a"}'
        values: '1x10 stale'
    alert_rule_test:
      - eval_time: 25m
        alertname: CheckoutAbsent
        exp_alerts:
          - exp_labels:
              severity: page
              team: payments
              job: checkout
```

**Caveats** ⚠.
- This file was not executed here; L8's scenarios are the executed equivalent.
- `exp_labels` must list every label the alert carries, including those produced by `absent()` (`job` from the equality matcher), or the test fails.
- In the first test the outage starts at minute 120 (20% errors). The 130 m expectation allows the 5 m and 1 h windows plus `for: 2m`.

### 2.4 Operating the catalog

```promql
# Rule evaluation health (a failing rule is a silent monitoring outage)
sum by (rule_group) (rate(prometheus_rule_evaluation_failures_total[5m])) > 0
max by (rule_group) (prometheus_rule_group_last_duration_seconds / prometheus_rule_group_interval_seconds) > 0.8
sum by (rule_group) (increase(prometheus_rule_group_iterations_missed_total[1h])) > 0

# Error-budget remaining over 30 days (for the SLO dashboard)
1 - (
  sum_over_time(job:http_server_requests_errors:rate5m{job="checkout"}[30d])
  / sum_over_time(job:http_server_requests:rate5m{job="checkout"}[30d])
) / 0.001

# Alert noise review: firing alerts per team per week
sum by (team, alertname) (changes(ALERTS{alertstate="firing"}[7d]))
```

The budget expression averages 5-minute rates sampled at the rule interval. That is accurate when the interval is regular. Use `increase()` over raw counters for audit-grade numbers.

---

## 3. Failure modes and FinOps debugging

### F1. The alert that can never fire

**Symptom.** A real PSP slowdown, with no alert. The rule review had passed.

**Signature.** `histogram_quantile(0.99, …) > 1` while the largest finite bucket is `le="1.0"`. L8's last scenario shows zero alerts.

**Root cause.** `histogram_quantile` returns the highest finite bucket boundary when the rank falls into `+Inf`, so the value saturates at 1 [D].

**Fix.** Add buckets above every threshold (File 01: SLO boundaries plus a clamped max), or alert on bucket ratios (`le="1"` fraction) instead of quantiles.

**Prevention.** A CI check that every quantile alert threshold is strictly below the metric's largest finite bucket. A scenario test per quantile alert (L8).

### F2. No traffic, no alert, no budget

**Symptom.** A low-traffic service had 100% errors overnight, and no burn alert fired.

**Signature.** The 5 m request rate is 0 or near 0. The ratio `errors/requests` is `NaN` (0/0) or computed from 2 requests.

**Root cause.** Ratios are undefined without traffic, and burn rates on tiny denominators are noisy.

**Fix.**
- Add a synthetic probe to guarantee a request floor.
- Alert on absolute error counts for low-traffic services.
- Use longer windows (or `absent`/`up` alerts) for idle hours.

**Prevention.** Classify services by traffic tier and generate the right template (§2.2).

### F3. Recording rules diluted by health checks

**Symptom.** The availability SLO looks perfect during an outage: the error ratio is 0.4% while customers see 30% errors.

**Signature.** Recording rules lack `uri!~"/actuator.*"`. Actuator and probe requests (always 200) are 90% of the traffic.

**Root cause.** The SLI counts non-user traffic as good events.

**Fix.** Exclude actuator in the recording layer (L7) **and** in the app (File 01's `ObservationPredicate`).

**Prevention.** SLI definitions are reviewed with "what counts as an event?" as the first question. Synthetic timelines include actuator traffic (L8).

### F4. Burn alerts on a sharded Prometheus

**Symptom.** Burn alerts fire on one Prometheus shard and not others. The values differ by shard.

**Signature.** `shards > 1` (File 02 F4). Each shard's recording rule sums a subset of pods.

**Root cause.** SLO rules need complete data.

**Fix.** Evaluate this catalog in the Mimir ruler, or in a single unsharded Prometheus per domain.

**Prevention.** A rule-placement policy: SLO groups carry a label routing them to the central ruler.

### F5. Alert storm during a dependency outage

**Symptom.** The PSP is down. 40 alerts fire across checkout, cart and orders, and the on-call ignores the one that matters.

**Signature.** Cause-based alerts (pool saturation, latency, heap) at page severity. No inhibition.

**Root cause.** Paging on causes multiplies alerts per incident.

**Fix.**
- Page only on symptoms (burn and absence).
- Inhibit causes when the symptom alert is firing for the same team.
- Group by `slo`.

**Prevention.** A weekly noise review (§2.4). An L8 static check that `page` is burn or absence only.

### F6. Rule group lagging or failing silently

**Symptom.** Recorded series have gaps. Alerts flap on missing data.

**Signature.** `prometheus_rule_group_last_duration_seconds` is near the interval, `iterations_missed_total` is increasing, or `rule_evaluation_failures_total` is greater than 0 (for example a `many-to-many matching` error after a label change).

**Root cause.**
- Long-window rates (`[3d]`) over raw high-cardinality series exceed the interval.
- A label change made a join ambiguous.

**Fix.**
- Build long windows from recorded short windows (`avg_over_time(job:…:rate5m[3d])` is cheaper, as an approximation).
- Split groups.
- Add `on()`/`ignoring()` to joins.

**Prevention.** Alert on rule-evaluation health (§2.4). Load-test rules against production-sized data in staging.

### F7. Absent alert never fires because of label mismatch

**Symptom.** All pods were deleted, and `CheckoutAbsent` stayed silent.

**Signature.** The rule is `absent(up{job="checkout-svc"})`, but the real job is `checkout`. Or a regex matcher was used: `absent()` returns labels only from equality matchers.

**Root cause.** `absent()` is true only when *no* series match. A typo matches nothing, ever, so the alert is "absent" from day one and was silenced as noise, or the mismatch makes it always fire.

**Fix.** Pin `absent()` to the exact `job` produced by the ServiceMonitor (File 02). Test it with a staleness scenario (L8 `pod b… every pod gone`).

**Prevention.** A static check that every `absent()` selector matches at least one live series in staging.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "Write the alerting for a new payment service."</b></summary>

**Initial Prompt.** It has a 99.9% availability SLO and a 300 ms p99 goal.

**L5 Textbook Answer.** Alert when the error rate exceeds 1% for 5 minutes, and when p99 is above 300 ms.

**Why L5 Fails at 3 AM or on the Bill.**
- A static 1% threshold pages on blips at low traffic and misses slow burns.
- A "p99 > 300 ms" quantile alert is noisy and saturates if the buckets don't extend past the threshold (F1).
- There are no owners, runbooks or inhibition.

**L7 Principal Defense.** Use the L7 structure.
- **Recording.** Recorded SLIs per window with actuator excluded.
- **Paging.** Multiwindow multi-burn-rate alerts (page 14.4×/6×, ticket 3×/1×).
- **Latency SLI.** A request ratio with an exact bucket at 0.3 s, not a quantile.
- **Absence.** An absence alert that pages because the service is blind.
- **Causes as tickets.** Heap, throttling and pool alerts go to the ticket queue.
- **Metadata.** Every alert has team, runbook and SLO labels.
- **Routing.** Alertmanager routes and inhibition as in §2.1.
- **Proof.** Before merge, CI runs the static checks and scenario tests (L8) proving each alert fires in its scenario and stays silent on healthy traffic.
</details>

<details><summary><b>Q2 · "Why multiwindow? A single 1h window is simpler."</b></summary>

**Initial Prompt.** Justify the complexity to a skeptical team.

**L5 Textbook Answer.** Google recommends it.

**Why L5 Fails at 3 AM or on the Bill.** "Google says" doesn't survive a design review. Without the numbers you can't tune.

**L7 Principal Defense.**
- **One window forces a trade-off** between detection time and reset time. A 1h window keeps firing for up to an hour after recovery.
- **The short window (1/12)** gates the alert off quickly once the burn stops.
- **The tiers separate severity by budget consumed:** 2% of budget in 1h pages, 10% in a day opens a ticket.
- **L8 shows the behaviour:**
  - the 20% outage pages at +6 min;
  - the constant 5× burn only tickets;
  - healthy traffic stays silent.
- I'd show the precision/recall/detection-time numbers from Folder 04's lab for our traffic.
</details>

<details><summary><b>Q3 · "How do you test alert rules?"</b></summary>

**Initial Prompt.** Our last incident went unalerted because a rule had a typo.

**L5 Textbook Answer.** Review rules carefully in PRs.

**Why L5 Fails at 3 AM or on the Bill.** Reviews don't catch semantic errors:
- a quantile capped by buckets (F1);
- a 0/0 ratio (F2);
- `absent()` with the wrong job (F7).

Those need execution.

**L7 Principal Defense.**
- **Static checks** on every rule: parse, naming lint, metadata contract, page-only-on-symptoms, thresholds equal factor × budget.
- **Scenario tests:** `promtool test rules` or the L8 equivalent with synthetic series per failure mode (outage, slow burn, latency, target down, absence, dependency slow). Each test asserts which alerts fire and when.
- **In production:** rule-evaluation health alerts, and a weekly firing-alerts review.

Rules become code with tests, versioned with the service.
</details>

<details><summary><b>Q4 · "Latency SLO: quantile alert or ratio alert?"</b></summary>

**Initial Prompt.** The team wants `histogram_quantile(0.99, …) > 0.3`.

**L5 Textbook Answer.** The p99 alert is intuitive; use it.

**Why L5 Fails at 3 AM or on the Bill.**
- Quantiles from buckets are interpolations, exact only at boundaries. They can't be averaged across windows.
- Above the largest bucket they saturate (F1).
- They don't map to an error budget.

**L7 Principal Defense.**
- Define the SLI as the fraction of requests slower than 0.3 s, computed from `_count − bucket{le="0.3"}`. It is exact because 0.3 is an SLO boundary (File 01).
- Burn-rate alert on that ratio (L7 `CheckoutLatencyBudgetBurnFast`).
- Keep p99 panels for humans.
- L8 measured the detection: +36 min at 25% slow, a deliberate trade-off. Add a short-window tier if the business needs faster paging on latency.
</details>

<details><summary><b>Q5 · "What should page, and what shouldn't?"</b></summary>

**Initial Prompt.** On-call gets 30 pages a week.

**L5 Textbook Answer.** Raise the thresholds.

**Why L5 Fails at 3 AM or on the Bill.** Higher thresholds miss real incidents. The noise comes from paging on causes, not from the threshold values.

**L7 Principal Defense.**
- **Page:**
  - user-facing symptom burn rates;
  - total blindness (`absent`, a Watchdog failure detected externally).
- **Ticket:** causes (heap, throttling, pool, disk) and slow burns.
- **Dashboard only:** everything else.
- **Inhibition** suppresses causes during symptom pages.
- **Measurement:** pages per week per team, actionable rate, MTTA. Delete alerts that were never actionable in 90 days.
- **Enforcement:** the L8 metadata check makes "page ⇒ symptom" a CI rule, not a convention.
</details>

<details><summary><b>Q6 · "Where do these rules run in a multi-cluster setup?"</b></summary>

**Initial Prompt.** checkout runs in 3 clusters.

**L5 Textbook Answer.** Deploy the PrometheusRule to each cluster.

**Why L5 Fails at 3 AM or on the Bill.** Per-cluster SLOs don't match the user's global experience. A failover that moves traffic between clusters makes per-cluster ratios meaningless, and three copies page three times.

**L7 Principal Defense.**
- **Global SLO rules** run once, in the Mimir ruler over all clusters' data (a `cluster` external label per source). They use `sum without (cluster)` in the recording layer.
- **Per-cluster rules** (absence, target down, saturation) stay local, so they keep working when the central path is down.
- **Alertmanager:** an HA cluster with dedup.
- **Watchdog** from each Prometheus *and* from the central ruler, each monitored externally.
</details>

<details><summary><b>Q7 · "How do you know your SLO rules are cheap enough?"</b></summary>

**Initial Prompt.** Rule evaluation takes 20 s of a 30 s interval.

**L5 Textbook Answer.** Increase the evaluation interval.

**Why L5 Fails at 3 AM or on the Bill.** A longer interval slows detection, and it doesn't fix the cost driver: long-window rates over raw high-cardinality series.

**L7 Principal Defense.**
- Measure per group (`last_duration / interval`, §2.4).
- Make the recording layer aggregate first, with only `job` kept.
- Long windows can derive from recorded 5m rates via `avg_over_time` (approximation documented) or run in a separate group with a longer interval.
- Split SLO groups from runtime groups.
- Kill unused recording rules: query-log analysis (Folder 08).
- Target under 50% of the interval for every group, with an alert at 80%.
</details>

<details><summary><b>Q8 · "A dependency (PSP) is slow. Who gets paged?"</b></summary>

**Initial Prompt.** checkout's latency SLO burns because the PSP is slow.

**L5 Textbook Answer.** The checkout team; they own the SLO.

**Why L5 Fails at 3 AM or on the Bill.** Partly right. Without dependency context, checkout's on-call wastes the first 20 minutes investigating its own service.

**L7 Principal Defense.**
- **Checkout is paged** on its own SLO burn, because users are hurt.
- **The page carries context:**
  - the PSP p99 ticket alert (L7 `CheckoutPspLatencyHigh`) is grouped and linked;
  - the runbook's first step is the dependency panel;
  - exemplars open the slow traces (File 01).
- **The PSP's owner** (or vendor management) gets a ticket.
- **If the PSP is external:** a circuit breaker and fallback reduce the burn, and their state is a metric on the dashboard.
- **Post-incident:** add a dependency SLO and an error-budget policy for the integration.
</details>

---

## 5. Invariants checklist

- [ ] Every SLO has recorded SLIs for each burn window, excluding non-user traffic.
- [ ] Burn thresholds are factor × budget with the Workbook tiers; page only on symptom burn and absence.
- [ ] Every quantile alert threshold is strictly below the metric's largest finite bucket; latency SLOs use exact-boundary ratios.
- [ ] Every alert has severity, team, summary and runbook_url; SLO alerts carry `slo`.
- [ ] `absent()` selectors match the ServiceMonitor-generated `job` exactly and are tested with a staleness scenario.
- [ ] Rules are unit-tested (`promtool test rules` or equivalent scenarios) in CI; evaluation health is alerted in production.
- [ ] SLO rules run where data is complete (unsharded or central ruler); per-cluster blindness alerts stay local.
- [ ] Alertmanager inhibits causes during symptom pages and routes Watchdog to an external heartbeat.

---

## 6. References

- Google SRE Workbook, alerting on SLOs: <https://sre.google/workbook/alerting-on-slos/>
- Prometheus recording rules (naming best practices): <https://prometheus.io/docs/practices/rules/>
- Prometheus alerting rules: <https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/>
- Unit testing rules with promtool: <https://prometheus.io/docs/prometheus/latest/configuration/unit_testing_rules/>
- Alertmanager configuration (routes, inhibition): <https://prometheus.io/docs/alerting/latest/configuration/>
- `histogram_quantile` semantics: <https://prometheus.io/docs/prometheus/latest/querying/functions/#histogram_quantile>
- Prometheus alerting best practices: <https://prometheus.io/docs/practices/alerting/>
