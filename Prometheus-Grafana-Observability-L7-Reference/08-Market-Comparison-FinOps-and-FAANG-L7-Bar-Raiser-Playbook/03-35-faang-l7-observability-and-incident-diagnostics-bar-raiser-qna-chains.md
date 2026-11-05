# 03 · 35 FAANG L7 Observability and Incident-Diagnostics Bar-Raiser Q&A Chains

> **Folder 08 — Market Comparison, FinOps and the FAANG L7 Bar-Raiser Playbook · File 3 of 3.**
> Every chain is grounded in a measured or documented result elsewhere in this KB. The L7 defense links to it, and the links are checked.
> Labels: **[D]** documented · **[M]** measured (by a listing in the linked file) · **[E]** model · **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L3 `chain_coverage_lab.py` | Audits this file: 35 chains numbered 1–35, each with the four labelled parts in order; all 9 domains covered at least 3 times; every L7 defense links to KB evidence and every link resolves; no duplicate prompts; at least 120 words per chain | <1 s |

**Verification.** L3 reads this document as built, ignoring its own output block, so the build-time and gate-time audits are identical [M]. The numbers inside the chains are quoted from the linked files' listings at their pinned versions.

---

## 0. Orientation

**How to use this file.** Each chain has four parts:
- a prompt as a bar-raiser would pose it;
- the answer a competent L5 gives;
- the specific way that answer fails in production or on the bill;
- the L7 defense, which quantifies, names mechanisms and trade-offs, and links to the evidence.

Rehearse them by covering the defense and answering out loud with numbers.

**The L5 → L7 delta, in one picture.**

```text
              L5 (correct)                               L7 (correct + accountable)
 mechanism    "rate() handles counter resets"        →   which samples, which extrapolation, which window, why it lies
 numbers      "it's expensive"                       →   69 buckets × 400 tag sets × 60 pods = 1.7M series ≈ $11k/mo
 failure      "monitor it"                           →   the exact 3 AM symptom, its signature, and the alert that catches it
 cost         (absent)                               →   $/series, $/GB, people, 3× volume, break-even
 org          (absent)                               →   ownership, budgets, CI checks, rollout and rollback, who gets paged
 evidence     "best practice"                        →   a reproducible measurement or the pinned source line
```

**Domain map.**

| Tag | Covers | Primary folders |
|---|---|---|
| TSDB | Head, WAL, chunks, index, native histograms | 01 |
| PromQL | rate math, matching, quantiles, query cost | 02 |
| Monitor | USE/RED, Kubernetes, JVM, Kafka/DB, LLM serving | 03 |
| Alerting | recording rules, burn rates, Alertmanager, absence | 04, 07 |
| Grafana | dashboards as code, correlation | 05 |
| OTel-LGTM | pipelines, Mimir/Thanos, Loki/Tempo/Pyroscope | 06 |
| K8s-Java | Boot/Micrometer, operator, rule catalogs | 07 |
| FinOps | TCO, governance, market | 08 |
| Incident | live diagnosis under pressure | all |

---

## 1. First principles: how interview probes work, and how incidents are diagnosed

### 1.1 What the probe is really testing

A bar-raiser follow-up almost always pushes on one of five axes:
1. **Mechanism.** *How* does it work (which code path, which data structure)?
2. **Magnitude.** *How much*: series, bytes, seconds, dollars?
3. **Failure.** What breaks first, how would you know, and how do you prevent it?
4. **Trade-off.** What do you give up, and when would you choose the other option?
5. **Organisation.** Who owns it, how is it enforced, how does it stay fixed?

An L7 answer volunteers 2–3 of these before being asked.

### 1.2 The incident diagnostic loop

```text
  DETECT ──► SCOPE ──────────────► LOCALISE ───────────────────► MITIGATE ─────► EXPLAIN
  burn-rate   who/what/since when    RED per service → dependency   rollback,       timeline, causal
  page, SLO   (tenant, region,       graph → exemplar trace →       failover,       chain, why it
  dashboard   version, endpoint)     span → logs by trace_id →      shed load,      wasn't caught,
              change log overlay     profile of the hot pod         feature flag    action items
       ▲                                                                                │
       └────────────────────── new alert / test / budget that would have caught it ─────┘
  Rules: mitigate before you fully explain · distrust a single signal · check that the telemetry itself is healthy
```

**Three properties make this loop fast. Each is a chain below.**
1. **Symptom alerts that page with context** (Q12, Q14).
2. **Signals joined by IDs:** exemplars, `trace_id` in logs, profiles by span (Q19, Q35).
3. **Telemetry you trust:** pipeline conservation, absence alerts, a Watchdog (Q16, Q31).

<!-- listing:chain_coverage_lab.py -->
```python
"""chain_coverage_lab.py - audits the 35-chain bar-raiser file it is embedded in: every chain has the four
labelled parts in order, every domain of the KB is covered at least three times, every L7 defense cites
evidence (a link into the KB that resolves to a real file), and no two chains share an opening prompt.
Embedded listing outputs are ignored, so the audit is identical at build time and at gate time.

Usage: python chain_coverage_lab.py <target.md>
"""
import collections
import pathlib
import re
import sys

PARTS = ["**Initial Prompt.**", "**L5 Textbook Answer.**", "**Why L5 Fails at 3 AM or on the Bill.**",
         "**L7 Principal Defense.**"]
DOMAINS = ["TSDB", "PromQL", "Monitor", "Alerting", "Grafana", "OTel-LGTM", "K8s-Java", "FinOps", "Incident"]


def main():
    target = pathlib.Path(sys.argv[1]).resolve()
    md = target.read_text(encoding="utf-8")
    md = re.sub(r"<!-- output:.*?```text\n.*?\n```", "", md, flags=re.S)
    chains = re.findall(r"<details><summary><b>Q(\d+) · \[([A-Za-z0-9-]+)\] (.*?)</b></summary>(.*?)</details>", md, re.S)
    checks = []
    print(f"== 1. Structure: {len(chains)} chains ==")
    bad_order, numbers = [], [int(n) for n, *_ in chains]
    for n, dom, title, body in chains:
        pos = [body.find(p) for p in PARTS]
        if min(pos) < 0 or pos != sorted(pos):
            bad_order.append(n)
    print(f"numbered 1..{max(numbers)} contiguous: {numbers == list(range(1, len(chains) + 1))}; chains missing or "
          f"misordering a part: {bad_order or 'none'}")
    checks.append(("35 well-formed chains", len(chains) == 35 and not bad_order and numbers == list(range(1, 36))))
    print()

    print("== 2. Domain coverage ==")
    cov = collections.Counter(d for _, d, _, _ in chains)
    for d in DOMAINS:
        print(f"  {d:<10} {cov.get(d, 0):>2} {'#' * cov.get(d, 0)}")
    unknown = set(cov) - set(DOMAINS)
    checks.append(("every domain >= 3", all(cov.get(d, 0) >= 3 for d in DOMAINS) and not unknown))
    print()

    print("== 3. Evidence: every L7 defense links into the KB, and every link resolves ==")
    no_evidence, broken, cited = [], [], collections.Counter()
    for n, _, _, body in chains:
        defense = body[body.find(PARTS[3]):]
        links = re.findall(r"\]\((\.\./[^)#]+\.md)(?:#[^)]*)?\)", defense)
        if not links:
            no_evidence.append(n)
        for l in links:
            p = (target.parent / l).resolve()
            if not p.exists():
                broken.append((n, l))
            cited[p.parent.name[:2]] += 1
    print(f"defenses without a KB link: {no_evidence or 'none'}; broken links: {broken or 'none'}")
    print("citations per folder: " + ", ".join(f"{k}:{v}" for k, v in sorted(cited.items())))
    checks.append(("evidence", not no_evidence and not broken and len(cited) >= 7))
    print()

    print("== 4. Distinctness ==")
    prompts = [re.sub(r"\W+", " ", body[body.find(PARTS[0]) + len(PARTS[0]):body.find(PARTS[1])]).strip().lower()
               for _, _, _, body in chains]
    dupes = [p for p, c in collections.Counter(prompts).items() if c > 1]
    words = [len(body.split()) for _, _, _, body in chains]
    print(f"duplicate prompts: {len(dupes)}; words per chain min {min(words)}, median {sorted(words)[len(words) // 2]}, "
          f"max {max(words)}")
    checks.append(("distinct and substantive", not dupes and min(words) >= 120))
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:chain_coverage_lab.py -->
```text
== 1. Structure: 35 chains ==
numbered 1..35 contiguous: True; chains missing or misordering a part: none

== 2. Domain coverage ==
  TSDB        4 ####
  PromQL      4 ####
  Monitor     4 ####
  Alerting    4 ####
  Grafana     3 ###
  OTel-LGTM   6 ######
  K8s-Java    4 ####
  FinOps      3 ###
  Incident    3 ###

== 3. Evidence: every L7 defense links into the KB, and every link resolves ==
defenses without a KB link: none; broken links: none
citations per folder: 01:5, 02:6, 03:7, 04:5, 05:5, 06:11, 07:15, 08:4

== 4. Distinctness ==
duplicate prompts: 0; words per chain min 124, median 147, max 191

checks: 4/4 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 First-15-minutes query pack (service `checkout`)

```promql
# 1. Is it real, how big, since when? (SLI vs budget)
job:http_server_requests_errors:rate5m{job="checkout"} / job:http_server_requests:rate5m{job="checkout"}
# 2. Which endpoints/pods? (needs uri and pod kept - see 02 FinOps F2)
topk(5, sum by (uri, pod) (rate(http_server_requests_seconds_count{job="checkout", outcome="SERVER_ERROR"}[5m])))
# 3. Dependency or self? (client-side latency per downstream)
histogram_quantile(0.99, sum by (le, client_name) (rate(http_client_requests_seconds_bucket{job="checkout"}[5m])))
# 4. Saturation: pool waiters, CPU throttling, GC
max by (pod) (hikaricp_connections_pending{job="checkout"})
sum by (pod) (rate(container_cpu_cfs_throttled_periods_total{container="checkout"}[5m])) / sum by (pod) (rate(container_cpu_cfs_periods_total{container="checkout"}[5m]))
# 5. Did something change? (deploys, config reloads)
changes(kube_deployment_status_observed_generation{deployment="checkout"}[1h])
# 6. Is the telemetry itself healthy?
up{job="checkout"} == 0
sum(rate(prometheus_rule_evaluation_failures_total[5m]))
```

```logql
# 7. Errors for the exemplar's trace, then the top error messages
{app="checkout"} | trace_id="4bf92f3577b34da6a3ce929d0e0e4736"
topk(10, sum by (msg) (count_over_time({app="checkout"} |= `"level":"error"` | json | __error__="" [10m])))
```

```traceql
// 8. Slow and erroring paths through checkout, and the descendant that dominates
{ resource.service.name = "checkout" && status = error } >> { duration > 500ms }
```

### 2.2 Incident triage runbook skeleton

```yaml
runbook: checkout-availability-burn
trigger: CheckoutAvailabilityBudgetBurnFast (severity=page)
first_5_minutes:
  - acknowledge; open incident channel; assign incident commander and scribe
  - query pack steps 1-2: confirm SLI breach and scope (uri, pod, region, version)
  - check change overlay (deploys/config in the last 2h); if correlated -> roll back first
mitigation_options:
  - rollback: kubectl rollout undo deploy/checkout (or GitOps revert)
  - shed: enable feature flag checkout.recommendations=off
  - failover: shift traffic to secondary region if regional
diagnosis:
  - exemplar from the p99 panel -> Tempo trace -> slowest/erroring span
  - logs by trace_id (structured metadata); profile of the hot pod (Pyroscope, merged >= 10 min)
telemetry_health:
  - up/absent for checkout; Watchdog heartbeat; collector dropped_too_early == 0
exit:
  - SLI back under 1x burn for 30 min; budget impact recorded
postmortem:
  - timeline from alerts/annotations; what would have caught it earlier; new test or alert added
```

### 2.3 Interview rubric

```yaml
rubric:
  mechanism:   {L5: names the component, L7: names the code path / data structure and its limit}
  magnitude:   {L5: qualitative, L7: computes series, bytes, seconds, dollars from first principles}
  failure:     {L5: "add monitoring", L7: symptom + signature + root cause + prevention}
  tradeoff:    {L5: one option, L7: when the other option wins, and the decision record}
  organisation: {L5: absent, L7: ownership, budgets, CI gates, rollout/rollback, paging policy}
pass_bar: L7 on at least 4 of 5 axes in at least 3 chains of different domains
```

---

## 3. Failure modes and FinOps debugging

### F1. Anchoring on the first dashboard

**Symptom.** Responders spend 40 minutes on CPU graphs while the cause is a downstream dependency.

**Signature.** No dependency or client-side latency panel was consulted. The first anomaly seen became the story.

**Root cause.** Anchoring bias, plus dashboards organised by resource rather than by request flow.

**Fix.** Follow the loop (§1.2): RED per service, then client latency per dependency, then saturation.

**Prevention.** Dashboards ordered by the cognitive hierarchy (Folder 05 file 01). The query pack (§2.1) in every runbook.

### F2. Trusting telemetry that is itself broken

**Symptom.** The dashboards look healthy during an outage.

**Signature.** Targets vanished (`absent`). Rule evaluation was failing. A collector was dropping traces too early. Recording rules diluted the SLI with health checks.

**Root cause.** No checks on the observability pipeline itself.

**Fix.** Step 6 of the query pack. Absence alerts, a Watchdog, and pipeline conservation counters.

**Prevention.** SLOs for the observability platform. Chaos tests that kill exporters and collectors.

### F3. Mitigation delayed by root-cause hunting

**Symptom.** A deploy-correlated regression runs for an hour while engineers debug.

**Signature.** The change overlay showed a deploy 4 minutes before the burn started, and rollback was not tried.

**Root cause.** Treating explanation as a prerequisite for mitigation.

**Fix.** Roll back first when a change correlates. Diagnose on the canary or a copy.

**Prevention.** Rollback as runbook step 1. Deploy annotations on every dashboard.

### F4. Averages hide the incident

**Symptom.** Average latency is flat, yet customers report timeouts.

**Signature.** p99 or SLI-ratio panels absent. Per-pod averages averaged again. Client-side percentiles merged.

**Root cause.** Wrong aggregation math (Folder 02 file 03; Folder 07 file 01 F4).

**Fix.** Use bucket-ratio SLIs and quantiles from summed bucket rates.

**Prevention.** Dashboard lint that rejects `avg` of quantile gauges.

### F5. Sampling erased the evidence

**Symptom.** No traces exist for the failing requests. Exemplars lead nowhere.

**Signature.** 1% head sampling and no tail policy for errors. Or a tail-sampler buffer cliff during the incident's traffic spike.

**Root cause.** Sampling decided without outcome awareness, or an undersized buffer (Folder 06 file 01).

**Fix.** Tail-sample errors and slow requests. Size `num_traces` for peak.

**Prevention.** Alert on `dropped_too_early > 0`. Track exemplar resolution as an SLI.

### F6. Postmortem without a control change

**Symptom.** The same class of incident recurs within a quarter.

**Signature.** Action items are "be more careful" or "add a dashboard". No test, alert or budget was added.

**Root cause.** No closed loop from incident to control.

**Fix.** Every postmortem adds a test (rule scenario, series budget, config lint) or an alert that would have caught it earlier.

**Prevention.** Track postmortem action items to closure as a reliability KPI.

---

## 4. L7 bar-raiser Q&A chains (35)

<details><summary><b>Q1 · [TSDB] "Prometheus memory doubled overnight. No new services shipped."</b></summary>

**Initial Prompt.** Diagnose and fix before it OOMs.

**L5 Textbook Answer.** Someone added a high-cardinality label. Find it and drop it.

**Why L5 Fails at 3 AM or on the Bill.** Often there is no new label, only **churn**. Rolling deploys, autoscaling or a cronjob create new series every hour, and the head keeps every series that saw a sample in the head window. Hunting for "the label" finds nothing while memory keeps climbing.

**L7 Principal Defense.**
- **Distinguish two causes.** Steady-state cardinality is `prometheus_tsdb_head_series`. Churn is `rate(prometheus_tsdb_head_series_created_total[1h])` and `…removed…`.
- **Cost per series.** Each head series is a `memSeries` (~176 B struct) plus postings and label strings (memory by label name ≈ (2 + len(name) + len(value)) × series), sharded across 16,384 stripes ([TSDB head](../01-Prometheus-3-TSDB-Internals-and-Cardinality-Physics/01-tsdb-head-block-wal-mmap-chunks-and-gorilla-xor-compression.md); [postings and OOM mechanics](../01-Prometheus-3-TSDB-Internals-and-Cardinality-Physics/02-inverted-index-postings-lists-and-high-cardinality-oom-mechanics.md)).
- **Find the source.** Use the TSDB status API (top label pairs by series and by memory). Look for pod-name or hash labels and new jobs.
- **Fix.** Drop or aggregate at scrape or the collector, and set `sample_limit`/`labelLimit` so the next one fails loudly.
- **Bound churn.** Avoid per-pod labels on long-lived aggregates.
</details>

<details><summary><b>Q2 · [TSDB] "Why does Prometheus take 20 minutes to restart, and how do you fix it?"</b></summary>

**Initial Prompt.** During incidents, restarts leave us blind.

**L5 Textbook Answer.** WAL replay is slow. Use faster disks.

**Why L5 Fails at 3 AM or on the Bill.** Disk speed is rarely the bound. Replay re-creates every head series and decodes every record since the last checkpoint, so it scales with series × samples in the WAL. Faster disks don't shrink that, and the blind window lands in the middle of an incident.

**L7 Principal Defense.**
- **What gets replayed.** The WAL is 32 KiB pages with CRC32C-framed records. A checkpoint compacts the first 2/3 of segments. The head is compacted to a block once its span exceeds 3h. So replay covers up to ~3h of samples plus series records ([WAL and head](../01-Prometheus-3-TSDB-Internals-and-Cardinality-Physics/01-tsdb-head-block-wal-mmap-chunks-and-gorilla-xor-compression.md)).
- **Levers:**
  - fewer head series (Q1);
  - m-mapped head chunks, which avoid re-encoding;
  - the memory-snapshot-on-shutdown feature for planned restarts ⚠;
  - HA pairs, so one replica restarts while the other serves;
  - a central TSDB (Mimir) for queries, so a single Prometheus restart doesn't blind dashboards or alerts.
- **Measure.** Track the replay duration metric per restart and alert if it exceeds the HA failover budget.
</details>

<details><summary><b>Q3 · [TSDB] "Explain Gorilla compression and when it stops working."</b></summary>

**Initial Prompt.** Our bytes/sample went from 1.3 to 4.

**L5 Textbook Answer.** Gorilla XOR compresses timestamps and values. Something increased the data.

**Why L5 Fails at 3 AM or on the Bill.** Without the encoding mechanics you can't tell *which* property of the data broke compression, so you can't fix the source. The bill is 3× on every downstream store.

**L7 Principal Defense.**
- **Timestamps** use delta-of-delta: a regular scrape costs 1 bit, while jitter spills into the 14/17/20-bit or 64-bit buckets.
- **Values** use XOR with the previous value: unchanged values cost 1 bit, while noisy floats (random gauges, high-precision timings) cost dozens.
- The `xor_chunk.py` port measures both ([chunks and XOR](../01-Prometheus-3-TSDB-Internals-and-Cardinality-Physics/01-tsdb-head-block-wal-mmap-chunks-and-gorilla-xor-compression.md)).
- **Typical causes of 4 B/sample:**
  - scrape jitter from overloaded targets or very short intervals;
  - gauges carrying nanosecond precision or random IDs;
  - many short-lived series (chunk headers amortised over few samples).
- **Note:** XOR2 (stable in 3.15) helps constant series (−29%), not noisy ones.
- **Fix the source:** round values, stabilise scrapes, reduce churn.
</details>

<details><summary><b>Q4 · [TSDB] "Should we migrate to native histograms?"</b></summary>

**Initial Prompt.** They're stable now; the team wants to switch everything.

**L5 Textbook Answer.** Yes. Fewer series and better precision.

**Why L5 Fails at 3 AM or on the Bill.** Defaults: Prometheus 3.x does not scrape native histograms unless `scrape_native_histograms` is set, and remote write doesn't send them unless `send_native_histograms` is set. Every hop (agent, Mimir, recording rules, dashboards) must support them. A partial rollout gives empty panels or double storage during dual-emission.

**L7 Principal Defense.**
- **Mechanics.** Exponential schemas make bucket boundaries 2^(2^−schema) apart. One series per histogram, sparse buckets, mergeable across instances. Bounds were verified bit-for-bit in [native histograms](../01-Prometheus-3-TSDB-Internals-and-Cardinality-Physics/03-metric-types-counters-gauges-summaries-and-prometheus3-native-histograms.md).
- **Precision.** `histogram_quantile` error is bounded by the schema, not by your bucket choice ([quantile math](../02-PromQL-Deep-Dive-and-Mathematical-Mechanics/03-histogram-quantile-math-classic-le-buckets-vs-native-exponential-schemas.md)).
- **Plan:**
  - enable end to end in one tenant;
  - dual-emit classic + native with NHCB conversion where needed;
  - port SLO rules to `histogram_fraction` and diff the results;
  - then drop classic buckets.
- The win is mostly series count (69 buckets → 1 series) and precision. The cost is migration risk on every consumer.
</details>

<details><summary><b>Q5 · [PromQL] "rate() shows a spike every deploy, but traffic is flat."</b></summary>

**Initial Prompt.** Explain the artefact.

**L5 Textbook Answer.** Counter resets on restart. `rate()` handles them, so it's real traffic.

**Why L5 Fails at 3 AM or on the Bill.** `rate()` does handle resets *per series*. Spikes appear when something summed counters before `rate()` (a recording rule or an ingest aggregation), or when a short range with few samples is extrapolated. False SLO burns follow every deploy.

**L7 Principal Defense.**
- **Prometheus `rate`:**
  - corrects resets per series;
  - extrapolates to the window edges unless the gap exceeds 1.1× the average spacing, in which case it extrapolates only half an interval;
  - clamps at zero for counters ([rate and extrapolation](../02-PromQL-Deep-Dive-and-Mathematical-Mechanics/01-instant-vs-range-vectors-rate-vs-irate-extrapolation-and-counter-resets.md)).
- **Spikes in flat traffic come from:**
  1. `rate()` over a pre-summed counter. One pod's reset becomes a reset of the sum: 1,333 req/s error in [FinOps L2](../08-Market-Comparison-FinOps-and-FAANG-L7-Bar-Raiser-Playbook/02-observability-finops-adaptive-telemetry-dropping-unused-metrics-and-tco-math.md).
  2. Ranges shorter than 4× the scrape interval. Use `$__rate_interval` = max(`$__interval` + scrape, 4 × scrape).
- **Fix** with `sum(rate())`, reset-aware aggregation and correct windows.
</details>

<details><summary><b>Q6 · [PromQL] "Our p99 panel disagrees with the SLO report."</b></summary>

**Initial Prompt.** The panel says 280 ms; the SLO says we breached 300 ms.

**L5 Textbook Answer.** One of them uses the wrong time range.

**Why L5 Fails at 3 AM or on the Bill.** Both may be "right". The panel interpolates linearly inside a bucket (0.268–0.358 s), while the SLO counts requests above an exact boundary. Or the panel averages per-pod quantiles, which is mathematically invalid.

**L7 Principal Defense.**
- **How `histogram_quantile` works.** It finds the bucket containing the rank and interpolates linearly, assuming a uniform distribution inside. It is exact only at bucket boundaries, and it caps at the highest finite bucket ([quantile math](../02-PromQL-Deep-Dive-and-Mathematical-Mechanics/03-histogram-quantile-math-classic-le-buckets-vs-native-exponential-schemas.md)).
- **Configure a boundary at every SLO threshold.** Micrometer's default ladder has no 0.3 s, so add it as an SLO boundary ([Boot code](../07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs/01-complete-java21-spring-boot-micrometer-otel-exemplar-and-custom-meter-code.md)).
- **Compute the SLI as a ratio** of `le="0.3"` to `_count`.
- **Show quantiles from summed bucket rates** for humans, and never average quantiles across pods.
- **Make the SLO report authoritative** and the panel explanatory.
</details>

<details><summary><b>Q7 · [PromQL] "'many-to-many matching not allowed' broke our recording rules."</b></summary>

**Initial Prompt.** It worked for a year.

**L5 Textbook Answer.** Add `group_left`.

**Why L5 Fails at 3 AM or on the Bill.** `group_left` without understanding the label sets can silently multiply series or pick arbitrary matches. The real cause is usually a new label (a second `instance` per `pod`, or a new `version` label) that broke one-to-one matching. The rules have been failing since then, so the alerts built on them are blind.

**L7 Principal Defense.**
- **Matching semantics.** Signatures are computed from `on()`/`ignoring()` labels. One-to-one requires unique signatures on both sides. `group_left` allows many on the left and copies `include` labels from the one side ([vector matching](../02-PromQL-Deep-Dive-and-Mathematical-Mechanics/02-aggregations-vector-matching-on-ignoring-group-left-and-subqueries.md)).
- **Diagnose** with `count by (signature labels) (rhs) > 1`.
- **Fix** with explicit `on(...)` or by aggregating away the new label on the "one" side.
- **Prevent** with `prometheus_rule_evaluation_failures_total > 0` alerts ([rule catalog §2.4](../07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs/03-production-ready-recording-and-slo-alerting-rules-catalog-for-microservices.md)) and scenario tests that include the new label.
</details>

<details><summary><b>Q8 · [PromQL] "A dashboard query OOMs the querier. Make it cheap."</b></summary>

**Initial Prompt.** `histogram_quantile(0.99, sum by (le, uri, pod) (rate(http_server_requests_seconds_bucket[5m])))` over 7 days.

**L5 Textbook Answer.** Add more querier memory.

**Why L5 Fails at 3 AM or on the Bill.** Cost scales with series selected × samples per series × steps. Here that is 4M bucket series (69 buckets) for 7 days. More memory just moves the cliff, and every refresh re-pays it.

**L7 Principal Defense.**
- **Estimate first.** Series selected (`count` of the selector), samples per range, steps.
- **Then cut each factor:**
  - aggregate away `pod` in a recording rule (`job_uri:…_bucket:rate5m`) for long ranges;
  - use `$__rate_interval` and a max-data-points that matches the panel width;
  - split by time in the query-frontend and use the results cache ([Mimir read path](../06-OpenTelemetry-Grafana-Alloy-and-The-LGTM-Scale-Stack/02-grafana-mimir-and-thanos-distributor-ingester-hash-rings-and-s3-compaction.md));
  - enforce `max_fetched_series_per_query` so the next one fails fast instead of OOMing.
- **Subqueries** over long ranges multiply the cost again ([subqueries](../02-PromQL-Deep-Dive-and-Mathematical-Mechanics/02-aggregations-vector-matching-on-ignoring-group-left-and-subqueries.md)).
</details>

<details><summary><b>Q9 · [Monitor] "CPU is at 40% but p99 latency tripled."</b></summary>

**Initial Prompt.** No CPU saturation, yet the service is slow.

**L5 Textbook Answer.** It must be the database or the network.

**Why L5 Fails at 3 AM or on the Bill.** Average CPU utilisation hides **CFS throttling**. A container with a CPU limit can exhaust its quota inside each 100 ms period and stall, even at 40% average. The team scales the database while the cause is the pod's own limit.

**L7 Principal Defense.**
- **Check** `container_cpu_cfs_throttled_periods_total / container_cpu_cfs_periods_total` and PSI CPU pressure.
- **Mechanism.** The CFS simulation shows bursty multithreaded work (GC, parallel request handling) hitting the quota early in the period, which adds up to ~100 ms stalls to tail latency ([CFS throttling](../03-What-to-Monitor-Complete-Enterprise-Taxonomy/02-kubernetes-monitoring-kube-state-metrics-cadvisor-cfs-throttling-and-ooms.md)).
- **Fix:**
  - remove CPU limits for latency-sensitive services (keep requests);
  - or raise the quota and align JVM GC and thread counts with the actual CPU entitlement ([JVM metrics](../03-What-to-Monitor-Complete-Enterprise-Taxonomy/03-java-jvm-micrometer-gc-pauses-virtual-threads-and-hikaricp-pool-metrics.md)).
- **Alert** on throttling ratio as a ticket ([rule catalog](../07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs/03-production-ready-recording-and-slo-alerting-rules-catalog-for-microservices.md)).
</details>

<details><summary><b>Q10 · [Monitor] "Size the DB connection pool from metrics, not folklore."</b></summary>

**Initial Prompt.** The team set `maximumPoolSize: 100` "to be safe".

**L5 Textbook Answer.** Connections = cores × 2 + spindles.

**Why L5 Fails at 3 AM or on the Bill.** The formula ignores the arrival rate and hold time. Oversized pools overload the database, so latency rises for every client. Undersized pools queue threads, and `hikaricp_connections_pending` grows.

**L7 Principal Defense.**
- **Model it as M/M/c.** Arrival rate λ comes from request rate × queries per request. Service time comes from `hikaricp_connections_usage_seconds`.
- **Pick c** so Erlang-C P(wait) and the expected wait meet the latency budget. The lab's Erlang C matches a discrete-event simulation ([pool math](../03-What-to-Monitor-Complete-Enterprise-Taxonomy/03-java-jvm-micrometer-gc-pauses-virtual-threads-and-hikaricp-pool-metrics.md)).
- **Watch at runtime:**
  - pending waiters;
  - acquire-time p99;
  - DB-side active sessions and wait events ([Postgres metrics](../03-What-to-Monitor-Complete-Enterprise-Taxonomy/04-kafka-postgres-redis-and-llm-inference-vllm-kv-cache-ttft-tpot-metrics.md)).
- **Virtual threads** move the bottleneck to exactly this pool.
- **Alert** on sustained pending waiters as a ticket. The burn alert pages if users feel it.
</details>

<details><summary><b>Q11 · [Monitor] "How do you monitor a Kafka consumer pipeline?"</b></summary>

**Initial Prompt.** Orders flow through 4 topics and 6 consumer groups.

**L5 Textbook Answer.** Alert on consumer lag above 10,000 messages.

**Why L5 Fails at 3 AM or on the Bill.** Message lag is meaningless across topics with different rates. 10k messages is 2 seconds on one topic and 3 hours on another. Users care about **time** lag: how old the data being processed is.

**L7 Principal Defense.**
- **Time-based lag** per group: estimate seconds behind from offset lag ÷ produce rate, or from record timestamps where exported ([Kafka metrics](../03-What-to-Monitor-Complete-Enterprise-Taxonomy/04-kafka-postgres-redis-and-llm-inference-vllm-kv-cache-ttft-tpot-metrics.md)).
- **SLO.** An end-to-end freshness SLO: P(order processed within 60 s), measured at the sink.
- **Consumer RED:** records/s, processing errors, rebalance count.
- **USE on brokers:** request queue time, under-replicated partitions.
- **Alerts:** freshness burn rate pages; a lag-growth derivative opens a ticket.
- **Traces** across topics with span links, so one slow handler is found by TraceQL instead of by guesswork.
</details>

<details><summary><b>Q12 · [Monitor] "What do you monitor for an LLM inference service?"</b></summary>

**Initial Prompt.** We self-host models with vLLM.

**L5 Textbook Answer.** GPU utilisation and request latency.

**Why L5 Fails at 3 AM or on the Bill.** GPU utilisation is near 100% whether it's useful or thrashing. Request latency mixes prompt length and output length. Users experience **time to first token** and **inter-token latency**, and cost depends on tokens/s per GPU at an acceptable latency (**goodput**).

**L7 Principal Defense.** Track TTFT and TPOT histograms, plus:
- queue time;
- KV-cache utilisation and preemptions (evictions force recomputation);
- running and waiting requests;
- prompt and generation tokens/s;
- goodput, meaning requests meeting TTFT and TPOT SLOs per GPU-hour ([LLM serving metrics](../03-What-to-Monitor-Complete-Enterprise-Taxonomy/04-kafka-postgres-redis-and-llm-inference-vllm-kv-cache-ttft-tpot-metrics.md)).

**Operation:**
- SLOs are defined on TTFT and TPOT per model.
- Autoscaling follows queue depth or KV-cache pressure, not GPU utilisation.
- Capacity planning uses goodput.
- Burn-rate alerts work exactly as for HTTP ([burn-rate math](../04-Recording-Rules-Alertmanager-and-SLO-Error-Budget-Math/02-google-sre-multi-window-multi-burn-rate-slo-alerts-and-error-budget-math.md)).
</details>

<details><summary><b>Q13 · [Alerting] "On-call gets 200 alerts a week. Fix the system."</b></summary>

**Initial Prompt.** People are ignoring pages.

**L5 Textbook Answer.** Tune thresholds and add `for:` durations.

**Why L5 Fails at 3 AM or on the Bill.** Threshold tuning on cause-based alerts trades noise for misses. The structural problem is paging on causes (CPU, heap, pool) instead of user-facing symptoms.

**L7 Principal Defense.**
- **Re-architect:**
  - page only on SLO burn rates and blindness (`absent`, Watchdog);
  - send causes to tickets;
  - inhibit causes during symptom pages;
  - group by service and SLO ([catalog §2.1](../07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs/03-production-ready-recording-and-slo-alerting-rules-catalog-for-microservices.md)).
- **Burn rates:** the 14.4×/6× page tiers consume 2% and 5% of the budget ([burn math](../04-Recording-Rules-Alertmanager-and-SLO-Error-Budget-Math/02-google-sre-multi-window-multi-burn-rate-slo-alerts-and-error-budget-math.md)).
- **Hysteresis and `keep_firing_for`** remove flapping ([flapping](../04-Recording-Rules-Alertmanager-and-SLO-Error-Budget-Math/04-dead-mans-switch-watchdog-absent-alerts-and-preventing-flapping-alert-fatigue.md)).
- **Measure** pages per week, actionable %, and alerts never acted on in 90 days (delete those).
- **Enforce** "page ⇒ symptom" in CI.
</details>

<details><summary><b>Q14 · [Alerting] "Alertmanager sent duplicate pages during a network partition."</b></summary>

**Initial Prompt.** Two Alertmanager replicas both paged.

**L5 Textbook Answer.** Gossip should deduplicate. It must be a bug.

**Why L5 Fails at 3 AM or on the Bill.** Alertmanager HA is **at-least-once by design**. Replicas gossip notification logs, and each waits position × peer timeout (15 s by default) before sending. Under a partition, gossip can't arrive, so each side sends.

**L7 Principal Defense.**
- **Mechanism.** The notification-log dedup (`needsUpdate`), the per-replica wait, and the partition behaviour are ported in [Alertmanager HA](../04-Recording-Rules-Alertmanager-and-SLO-Error-Budget-Math/03-alertmanager-architecture-gossip-ha-deduplication-grouping-inhibition-and-silences.md).
- **Design principle.** Duplicates are the safe failure mode; missed pages are not.
- **Mitigate downstream.** The paging provider dedups by incident key (group key), which makes duplicates one incident.
- **Ensure** both Prometheus replicas send to *all* Alertmanagers, and that the replica label is dropped from alerts so they deduplicate ([operator alert relabel](../07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs/02-kube-prometheus-stack-servicemonitor-podmonitor-and-relabeling-manifests.md)).
</details>

<details><summary><b>Q15 · [Alerting] "SLO burn alerts for a service with 2 requests per minute at night."</b></summary>

**Initial Prompt.** It either pages on one error or never pages.

**L5 Textbook Answer.** Use a longer window at night.

**Why L5 Fails at 3 AM or on the Bill.** Ratios on tiny denominators are noise (1 error of 2 = 50%). At zero traffic the ratio is 0/0 = NaN and alerts can't fire. A 100%-broken service with no traffic looks healthy until morning.

**L7 Principal Defense.**
- **Synthetic traffic.** Add probes that guarantee a request floor, so the SLI always has a denominator.
- **Low-traffic alerts.** Alert on absolute error counts or a minimum-event guard: `… and on() sum(rate(requests[1h])) > threshold`.
- **Coverage while idle.** Absence and `up` alerts cover idle periods.
- **Traffic tiers.** Generate rule templates per traffic tier ([catalog F2](../07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs/03-production-ready-recording-and-slo-alerting-rules-catalog-for-microservices.md)).
- **Report** SLO compliance only over windows with enough events.
- **Document the policy:** below N events per hour, the synthetic SLI governs.
</details>

<details><summary><b>Q16 · [Alerting] "An outage went unalerted. Find every way that can happen."</b></summary>

**Initial Prompt.** Postmortem item: "alerting failed".

**L5 Textbook Answer.** The threshold was too high.

**Why L5 Fails at 3 AM or on the Bill.** Most silent failures aren't thresholds. One alert class can never fire, and nobody notices until an outage tests it.

**L7 Principal Defense.** Enumerate and test each failure mode:
- **Targets vanished:** `up == 0` doesn't fire, `absent()` does ([absent](../04-Recording-Rules-Alertmanager-and-SLO-Error-Budget-Math/04-dead-mans-switch-watchdog-absent-alerts-and-preventing-flapping-alert-fatigue.md)).
- **Quantile saturation:** `histogram_quantile` saturates at the top finite bucket, so `> 1` never fires.
- **Rule failures:** rules failing with matching errors.
- **SLI dilution:** health checks dilute the SLI.
- **Sharding:** a sharded Prometheus evaluates on partial data.
- **Pipeline death:** Alertmanager or the receiver is broken, caught only by a Watchdog monitored externally.

Each has a scenario test in the [rule catalog lab](../07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs/03-production-ready-recording-and-slo-alerting-rules-catalog-for-microservices.md), which shows the never-firing PSP alert explicitly. CI runs them on every rule change.
</details>

<details><summary><b>Q17 · [Grafana] "Dashboards as code for 500 teams."</b></summary>

**Initial Prompt.** Dashboards drift and break after metric renames.

**L5 Textbook Answer.** Export JSON to Git.

**Why L5 Fails at 3 AM or on the Bill.** Exported JSON is unreviewable (IDs, positions, versions), drifts on the next UI edit, and doesn't follow metric renames. 500 teams × hand-edited JSON means thousands of broken panels after every platform change.

**L7 Principal Defense.**
- **Generate.** Dashboards and rules come from a service spec (mixins / Foundation SDK / Jsonnet).
- **Lint.** Run the generated queries through a PromQL linter: rate windows, `$__rate_interval`, no quantile averaging.
- **Sync.** Use Git Sync (GA in Grafana 13) so UI edits become PRs that run the same lint, or Terraform so applies revert drift ([as-code](../05-Grafana-Architecture-Dashboards-as-Code-and-Signal-Correlation/03-observability-as-code-grafana-git-sync-terraform-grizzly-and-monitoring-mixins.md)).
- **Structure.** Dashboards follow the cognitive hierarchy: SLO → RED → dependencies → saturation ([hierarchy](../05-Grafana-Architecture-Dashboards-as-Code-and-Signal-Correlation/01-grafana-cognitive-hierarchy-red-drilldowns-variables-and-transformations.md)).
- **Metric renames** go through a contract test on exposition names ([Boot naming](../07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs/01-complete-java21-spring-boot-micrometer-otel-exemplar-and-custom-meter-code.md)).
</details>

<details><summary><b>Q18 · [Grafana] "Grafana is slow and the Mimir bill for queries is high."</b></summary>

**Initial Prompt.** Dashboards take 20 s to load.

**L5 Textbook Answer.** Add more querier replicas.

**Why L5 Fails at 3 AM or on the Bill.** Query cost is set by the panels:
- 30 panels × 10 queries × 1 s refresh × raw high-cardinality selectors over 7 days;
- `rate[1m]` windows that bypass the cache's step alignment.

Adding replicas scales the waste.

**L7 Principal Defense.**
- **Audit the top queries** by cost (query-frontend stats).
- **Make dashboards cheap:**
  - recording rules for every panel over long ranges;
  - `$__rate_interval`;
  - max-data-points matched to panel width;
  - refresh at most 30 s to 1 m;
  - shared queries (dashboard datasource) instead of duplicates;
  - template variables that narrow selectors ([Grafana mechanics](../05-Grafana-Architecture-Dashboards-as-Code-and-Signal-Correlation/01-grafana-cognitive-hierarchy-red-drilldowns-variables-and-transformations.md)).
- **Make the backend cache well:** splitting, results cache, query sharding ([read path](../06-OpenTelemetry-Grafana-Alloy-and-The-LGTM-Scale-Stack/02-grafana-mimir-and-thanos-distributor-ingester-hash-rings-and-s3-compaction.md)).
- **Make cost visible:** per-dashboard query cost, so owners see it.
</details>

<details><summary><b>Q19 · [Grafana] "From a latency spike to the root cause in two clicks."</b></summary>

**Initial Prompt.** Design the correlation.

**L5 Textbook Answer.** Link dashboards to Tempo and Loki.

**Why L5 Fails at 3 AM or on the Bill.** Links without join keys and without retention alignment fail in practice:
- exemplars expire in seconds on large fleets;
- exemplars point at unsampled traces;
- logs lack `trace_id`;
- labels differ between signals.

**L7 Principal Defense.**
- **Exemplars on the latency histogram.** Prometheus's 100k-slot ring holds ~2.5 min at 10k series, so size it and ship exemplars to Mimir. Exemplars come only from sampled traces: Boot 4.1 defaults to `sampled-traces`, while 1% head sampling resolves only ~2.3% of clicks ([exemplars](../05-Grafana-Architecture-Dashboards-as-Code-and-Signal-Correlation/02-exemplars-linking-prometheus-metrics-to-tempo-traces-and-loki-logs.md)).
- **Tail policies** keep errors and slow requests.
- **`trace_id`** goes in log structured metadata.
- **Shared keys:** `service.name` and `k8s.*` across signals.
- **Profiles** are linked by span ([LGTM correlation](../06-OpenTelemetry-Grafana-Alloy-and-The-LGTM-Scale-Stack/03-grafana-loki-logql-tempo-traceql-and-pyroscope-continuous-ebpf-profiling.md)).
- **Measure exemplar resolution rate** as an SLI of the platform.
</details>

<details><summary><b>Q20 · [OTel-LGTM] "Tail sampling dropped all traces during Black Friday."</b></summary>

**Initial Prompt.** Tempo ingest went to zero at peak.

**L5 Textbook Answer.** The samplers were overloaded. Add pods.

**Why L5 Fails at 3 AM or on the Bill.** Adding pods mid-peak remaps ~1/N of in-flight traces and fragments them. The real cause is the buffer **cliff**: with FIFO eviction every trace lives `num_traces/rate` seconds, and below `decision_wait` *all* traces are evicted unevaluated. The defaults (50,000 / 30 s) fail at 1,667 new traces/s per pod.

**L7 Principal Defense.**
- **Pre-size** `num_traces ≥ 1.5 × peak per-pod rate × decision_wait`. The hottest pod runs ~1.08× the mean on the ring ([tail sampling](../06-OpenTelemetry-Grafana-Alloy-and-The-LGTM-Scale-Stack/01-opentelemetry-collector-vs-grafana-alloy-pipelines-tail-sampling-and-spanmetrics.md)).
- **Back-pressure.** Consider `block_on_overflow` with tier-1 queue headroom.
- **Alert** on `dropped_too_early > 0`.
- **Pre-scale on a calendar** with no HPA on samplers.
- **Generate RED before sampling,** so metrics stay correct even when the sampler fails.
</details>

<details><summary><b>Q21 · [OTel-LGTM] "Why move Mimir to ingest storage (Kafka)?"</b></summary>

**Initial Prompt.** Classic architecture works.

**L5 Textbook Answer.** Kafka scales better.

**Why L5 Fails at 3 AM or on the Bill.** It doesn't name the failure it removes or the one it adds. Classic ingesters serve reads and writes, so query storms fail pushes and rollouts need quorum. Kafka adds lag, partition planning and its own bill.

**L7 Principal Defense.**
- **What changes.** Ingest storage moves the commit point to Kafka ("the write path ends at Kafka"). Each partition is consumed by one ingester per zone. Reads are eventually consistent unless `X-Read-Consistency: strong` ([Mimir](../06-OpenTelemetry-Grafana-Alloy-and-The-LGTM-Scale-Stack/02-grafana-mimir-and-thanos-distributor-ingester-hash-rings-and-s3-compaction.md)).
- **Benefits:**
  - writes survive any ingester event;
  - queries can't hurt writes;
  - ingestion work becomes zones× rather than RF×.
- **Costs:**
  - Kafka;
  - receive-delay monitoring;
  - instance IDs ending in the partition number;
  - strong reads for the ruler.
- **Decide** on measured push-error minutes during query storms and rollouts versus Kafka TCO.
</details>

<details><summary><b>Q22 · [OTel-LGTM] "One Mimir ingester keeps OOMing. Others are at 60%."</b></summary>

**Initial Prompt.** It's always the same pod.

**L5 Textbook Answer.** Give it more memory, or add `num_tokens`.

**Why L5 Fails at 3 AM or on the Bill.** More random tokens converge slowly, and changing tokens reshuffles ownership. The ring analysis shows default random tokens at 1.12× max/mean. A zone-blind "even" layout is catastrophic at 7.01×, because with zone-aware replication each zone is its own ring.

**L7 Principal Defense.**
- **Measure skew** with `max/avg(cortex_ingester_memory_series)`.
- **Move to `spread-minimizing` tokens** computed per zone (1.02× in the port of dskit's lookup), rolling zone by zone ([rings](../06-OpenTelemetry-Grafana-Alloy-and-The-LGTM-Scale-Stack/02-grafana-mimir-and-thanos-distributor-ingester-hash-rings-and-s3-compaction.md)).
- **Check tenant hotspots** that tokens can't fix: a huge tenant with a small shuffle-shard size.
- **Size for the max, not the mean,** until skew is fixed.
- **Alert at skew > 1.15.**
- **Under ingest storage,** rebalance by partition count instead.
</details>

<details><summary><b>Q23 · [OTel-LGTM] "Design Loki labels; our bill doubled without more logs."</b></summary>

**Initial Prompt.** Bytes are flat; objects and costs doubled.

**L5 Textbook Answer.** S3 prices or retention changed.

**Why L5 Fails at 3 AM or on the Bill.** Loki costs scale with **streams**. A new low-volume label (e.g. `level`) splits streams thinly, chunks fill less before `max_chunk_age`, and object counts double at constant bytes. The model shows 131k → 278k chunks/day with 42% under 10% full ([Loki](../06-OpenTelemetry-Grafana-Alloy-and-The-LGTM-Scale-Stack/03-grafana-loki-logql-tempo-traceql-and-pyroscope-continuous-ebpf-profiling.md)).

**L7 Principal Defense.**
- **Index labels** are bounded, query-scoping dimensions only.
- **Per-request and per-instance values** go to structured metadata (on by default in 3.x).
- **OTLP** uses `ignore_defaults` with an explicit list, because the default indexes `k8s.pod.name` and `service.instance.id`.
- **Queries** narrow by labels before line filters, and filter before parse (53× fewer JSON parses).
- **Guardrail:** alert when average flushed-chunk fill drops below 25%.
- **Evidence:** the stream and chunk model and the mini LogQL engine are in [Loki and LogQL](../06-OpenTelemetry-Grafana-Alloy-and-The-LGTM-Scale-Stack/03-grafana-loki-logql-tempo-traceql-and-pyroscope-continuous-ebpf-profiling.md).
</details>

<details><summary><b>Q24 · [OTel-LGTM] "Find N+1 query patterns across 300 services."</b></summary>

**Initial Prompt.** DB CPU is high; no slow queries logged.

**L5 Textbook Answer.** Enable slow query logs.

**Why L5 Fails at 3 AM or on the Bill.** N+1 queries are individually fast. Slow-query logs never see them, and the database dies from volume, not latency.

**L7 Principal Defense.**
- **Detect.** TraceQL `{ span.db.system = "postgresql" } | count() > 5` finds traces with many DB spans. The evaluator found 156 of 156 seeded cases.
- **Rank** by `rootName` and confirm volume with a TraceQL metric over DB spans by service ([TraceQL](../06-OpenTelemetry-Grafana-Alloy-and-The-LGTM-Scale-Stack/03-grafana-loki-logql-tempo-traceql-and-pyroscope-continuous-ebpf-profiling.md)).
- **Make it fast.** Promote `db.system` to a Tempo dedicated column so the search is cheap.
- **Fix in code:** batching and joins.
- **Prevent** with a per-request query-count histogram and a CI test asserting query counts per endpoint.
</details>

<details><summary><b>Q25 · [OTel-LGTM] "Prove a 2% CPU regression with continuous profiling."</b></summary>

**Initial Prompt.** The flame graph from one pod shows `serialize()` grew.

**L5 Textbook Answer.** Ship the fix; the flame graph proves it.

**Why L5 Fails at 3 AM or on the Bill.** Profiles are samples. At `pyroscope.ebpf`'s default 19 Hz, one pod-core-15 s window is 285 samples. A 2.0%→2.5% change is z = 0.84, which is noise.

**L7 Principal Defense.**
- **Compute the samples needed:** about 13.8k per side for 95% confidence / 80% power, or ~12 core-minutes at 19 Hz.
- **Merge across the fleet:** 100 cores × 10 minutes gives z = 25.5 ([profiling statistics](../06-OpenTelemetry-Grafana-Alloy-and-The-LGTM-Scale-Stack/03-grafana-loki-logql-tempo-traceql-and-pyroscope-continuous-ebpf-profiling.md)).
- **Compare** with a diff flame graph between equal windows before and after the deploy.
- **Confirm in CI** with a benchmark.
- **Don't raise the sampling rate fleet-wide,** which costs 5× everywhere. Aggregate instead.
</details>

<details><summary><b>Q26 · [K8s-Java] "A team's ServiceMonitor produces no targets."</b></summary>

**Initial Prompt.** No errors anywhere.

**L5 Textbook Answer.** Check the targets page.

**Why L5 Fails at 3 AM or on the Bill.** If the Prometheus CR never selected the object (kube-prometheus-stack selects by the `release` label by default), the targets page shows nothing to debug.

**L7 Principal Defense.** Debug the three layers ([operator chain](../07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs/02-kube-prometheus-stack-servicemonitor-podmonitor-and-relabeling-manifests.md)):
1. **Object selection.** Labels and namespace vs the CR selectors. Check the job's presence in the generated Secret and in `prometheus_sd_discovered_targets`.
2. **Service selection.** A `keep` on service label value **and** presence.
3. **Port selection.** The Service port *name*.

The ported 18-rule chain shows a typo or selector mismatch yields 0 of 10 targets silently.

**Prevention:**
- An admission policy requires the selection label on every monitor.
- Services and ServiceMonitors are templated together, so port names cannot diverge.
- CI renders the operator configuration and simulates discovery against a real endpoint dump.
- Every critical job has an `absent(up{job=...})` alert, so the next silent miss pages within minutes.
</details>

<details><summary><b>Q27 · [K8s-Java] "Traces disappeared after the Spring Boot 4 upgrade."</b></summary>

**Initial Prompt.** Metrics are fine; Tempo is empty.

**L5 Textbook Answer.** The collector is down.

**Why L5 Fails at 3 AM or on the Bill.** Boot 4.0 removed `management.otlp.tracing.endpoint` (deprecation level `error`, replaced by `management.opentelemetry.tracing.export.otlp.endpoint`). Boot binds nothing to the stale key, so no exporter is configured. No error is logged unless the properties migrator is present.

**L7 Principal Defense.**
- **Rename the key.**
- **Lint every `application.yaml`** against the configuration metadata shipped in the Boot jars. The lint caught six Boot-3-era mistakes, including `exemplars.include: all`, which is unsupported with Prometheus ([Boot lint](../07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs/01-complete-java21-spring-boot-micrometer-otel-exemplar-and-custom-meter-code.md)).
- **Add `spring-boot-properties-migrator`** during upgrades.
- **Add a trace-completeness synthetic** per service so "traces stopped" pages within minutes, not at the next incident.
- **Generalise the lesson.** Framework upgrades are configuration-schema migrations. Every renamed key is a silent feature removal unless the configuration is validated against the new schema in CI.
</details>

<details><summary><b>Q28 · [K8s-Java] "SLO alerts became inconsistent after we sharded Prometheus."</b></summary>

**Initial Prompt.** `shards: 3` fixed memory but alerts disagree.

**L5 Textbook Answer.** Sharding bug; roll back.

**Why L5 Fails at 3 AM or on the Bill.** It's not a bug. Each shard owns a hash-partition of targets (hashmod on `__address__` with `$(SHARD)`) and evaluates the same rules on its partial data, so `sum by (job)` is a partial sum.

**L7 Principal Defense.**
- **Mechanism.** The operator's sharding tail places each of 300 targets on exactly one shard ([sharding](../07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs/02-kube-prometheus-stack-servicemonitor-podmonitor-and-relabeling-manifests.md)).
- **Global rules** (SLOs, ratios, absence) go to a central ruler over complete data: Mimir ruler, Thanos ruler.
- **Shard-local rules** (per-target `up`) can stay.
- **Alternatively,** shard by ownership: separate Prometheus CRs per domain.
- **Document rule placement** and test it in staging with a deliberately split job ([rule placement](../07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs/03-production-ready-recording-and-slo-alerting-rules-catalog-for-microservices.md)).
</details>

<details><summary><b>Q29 · [K8s-Java] "What does one Spring Boot service cost in series?"</b></summary>

**Initial Prompt.** Justify the observability budget for a new service.

**L5 Textbook Answer.** A few thousand series.

**Why L5 Fails at 3 AM or on the Bill.** With `percentiles-histogram` defaults, each timer × tag set exposes 69 buckets + count + sum + max. That was verified against the real Micrometer 1.17.2 registry. 400 tag sets is 28,800 series per pod, and 1.7M for 60 pods.

**L7 Principal Defense.** Compute the budget from first principles ([Boot code + oracle](../07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs/01-complete-java21-spring-boot-micrometer-otel-exemplar-and-custom-meter-code.md)):

| Policy | Series per pod |
|---|---|
| Defaults (69 buckets) | 28.8k |
| Clamped 5 ms–10 s + SLO boundaries (54) | 22.8k |
| SLO-only buckets (4) | 2.8k |

- **Enable full histograms only on SLO-bearing timers.**
- **Close every tag set.**
- **CI series-budget test** per service.
- **Price it** at $/series (File 01) so the team sees the trade-off.
</details>

<details><summary><b>Q30 · [FinOps] "Build vs buy at 12M series, 3 TB/day logs."</b></summary>

**Initial Prompt.** Give the CFO a recommendation.

**L5 Textbook Answer.** Open source is free; self-host.

**Why L5 Fails at 3 AM or on the Bill.** People are 74% of self-hosted TCO. Below a few million series, buying wins. Above that, SaaS scales linearly with volume while self-hosted scales with people.

**L7 Principal Defense.** Present the transparent model ([TCO](../08-Market-Comparison-FinOps-and-FAANG-L7-Bar-Raiser-Playbook/01-architectural-showdown-mimir-vs-victoriametrics-vs-clickhouse-signoz-vs-datadog.md)), with every assumption visible:

| | Monthly |
|---|---|
| Datadog curated | $335k (76% log indexing) |
| Grafana Cloud Pro | $132k |
| Self-hosted | $59k |

- **Break-even** is 5.3 FTE.
- **Doubling series** costs +$600k / +$78k / +$8k.
- **Recommendation:**
  - governance first (File 02's savings apply everywhere);
  - a vendor-neutral pipeline;
  - then self-host with ≥2 FTE and an on-call rotation, or negotiate SaaS from portability.
</details>

<details><summary><b>Q31 · [FinOps] "Cut 40% of observability spend in a quarter."</b></summary>

**Initial Prompt.** Without losing incident visibility.

**L5 Textbook Answer.** Reduce retention and sample traces harder.

**Why L5 Fails at 3 AM or on the Bill.** Those cut value, not waste. The largest units are unused series and indexed-but-never-searched logs. Uniform sampling deletes the error traces needed in incidents.

**L7 Principal Defense.** Run the control loop ([FinOps](../08-Market-Comparison-FinOps-and-FAANG-L7-Bar-Raiser-Playbook/02-observability-finops-adaptive-telemetry-dropping-unused-metrics-and-tco-math.md)):
1. Build a usage corpus from 30–90 days of query logs.
2. Derive needed labels from the PromQL AST.
3. Drop unused families and aggregate unused *independent* labels: 88% fewer series in L2, with dashboards and rules unchanged.
4. Prove correctness: reset-aware aggregation is exact, while naive summing spikes by 1,333 req/s on a restart.
5. Cut logs by 55% (debug dropped, health sampled) and index only what is searched.
6. Keep it there with per-team budgets.

40% is conservative.
</details>

<details><summary><b>Q32 · [FinOps] "Is ingest-time metric aggregation safe?"</b></summary>

**Initial Prompt.** A vendor feature promises 50–80% savings automatically.

**L5 Textbook Answer.** Yes, it's automatic and reversible.

**Why L5 Fails at 3 AM or on the Bill.**
- **Incomplete usage window.** Recommendations miss quarterly incident dashboards, and aggregating `pod` away blinds on-call.
- **Counters.** Counters aggregated without reset handling corrupt `rate()` at every deploy.

**L7 Principal Defense.**
- **Treat recommendations as proposals.**
- **Protect** `job`, `namespace` and `pod` on golden signals.
- **Verify semantics** per metric type, counters especially ⚠.
- **Shadow-tenant A/B** with numeric diffs of every dashboard and rule.
- **Roll out** by team with a rollback switch.
- **Measure savings at the billing meter.**

The L2 proof pattern (raw vs aggregated, with a pod restart) is the acceptance test ([FinOps proof](../08-Market-Comparison-FinOps-and-FAANG-L7-Bar-Raiser-Playbook/02-observability-finops-adaptive-telemetry-dropping-unused-metrics-and-tco-math.md)).
</details>

<details><summary><b>Q33 · [Incident] "Checkout p99 spiked 5 minutes ago. Walk me through the first 15 minutes."</b></summary>

**Initial Prompt.** You're the incident commander.

**L5 Textbook Answer.** Look at dashboards and logs to find the error.

**Why L5 Fails at 3 AM or on the Bill.** Unstructured exploration anchors on the first anomaly. Mitigation waits for explanation, and the telemetry's own health is never checked.

**L7 Principal Defense.**
- **0–2 minutes.** Confirm SLI and budget burn, then scope by uri, pod, region and version (query pack steps 1–2).
- **2–5 minutes.**
  - Check the change overlay. Roll back if a deploy correlates.
  - Check dependency client-latency panels.
- **5–10 minutes.** Click the exemplar on the p99 panel:
  - Tempo trace → slowest span;
  - logs by `trace_id`;
  - a merged profile of the hot pods.
- **10–15 minutes.**
  - Mitigate: rollback, shed load or fail over.
  - Communicate impact in budget terms.
  - Verify telemetry health (absence, Watchdog, collector drops).

Each step uses a tool from this KB: [rule catalog](../07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs/03-production-ready-recording-and-slo-alerting-rules-catalog-for-microservices.md) and [exemplars](../05-Grafana-Architecture-Dashboards-as-Code-and-Signal-Correlation/02-exemplars-linking-prometheus-metrics-to-tempo-traces-and-loki-logs.md).
</details>

<details><summary><b>Q34 · [Incident] "Errors spike only in one AZ. Is it us or the cloud?"</b></summary>

**Initial Prompt.** 20% errors from pods in us-east-1b.

**L5 Textbook Answer.** Cloud provider issue; wait for AWS.

**Why L5 Fails at 3 AM or on the Bill.** It may be ours:
- a zone-local dependency replica;
- a bad node pool;
- a stale configuration on one zone's rollout;
- in self-hosted Mimir, a degraded zone combined with a rollout in another, which loses quorum for series whose replicas span both.

**L7 Principal Defense.**
- **Scope by zone** with `topology_kubernetes_io_zone` from node labels on RED, the dependency client latency per zone, and the node and kubelet health in that zone (`kube_node_status_condition`) ([Kubernetes monitoring](../03-What-to-Monitor-Complete-Enterprise-Taxonomy/02-kubernetes-monitoring-kube-state-metrics-cadvisor-cfs-throttling-and-ooms.md)).
- **Mitigate first** by shifting traffic out of the zone (topology-aware routing, scaling the other zones).
- **For the observability stack itself:**
  - zone-aware replication makes a whole-zone loss cost 0% of writes;
  - a second zone degraded at the same time breaks quorum ([rings](../06-OpenTelemetry-Grafana-Alloy-and-The-LGTM-Scale-Stack/02-grafana-mimir-and-thanos-distributor-ingester-hash-rings-and-s3-compaction.md)).
- **Never run a rollout** in one zone while another is degraded.
</details>

<details><summary><b>Q35 · [Incident] "The dashboards were green during the outage. Why, and what changes?"</b></summary>

**Initial Prompt.** Customers saw failures for 40 minutes; every panel looked healthy.

**L5 Textbook Answer.** The dashboards need more panels.

**Why L5 Fails at 3 AM or on the Bill.** More panels on broken telemetry show more green. The candidates are:
- SLIs diluted by health-check traffic;
- vanished targets that `up == 0` can't see;
- recording rules failing silently;
- averages hiding tails;
- a collector dropping data.

**L7 Principal Defense.**
- **Audit the telemetry, not the panels:**
  - SLI definitions exclude `/actuator` and probes ([catalog F3](../07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs/03-production-ready-recording-and-slo-alerting-rules-catalog-for-microservices.md));
  - absence and Watchdog alerts exist and are tested;
  - rule-evaluation failures page;
  - dashboards use bucket ratios and quantiles from summed buckets, never averages of quantiles ([quantiles](../02-PromQL-Deep-Dive-and-Mathematical-Mechanics/03-histogram-quantile-math-classic-le-buckets-vs-native-exponential-schemas.md));
  - pipeline conservation counters exist ([pipelines](../06-OpenTelemetry-Grafana-Alloy-and-The-LGTM-Scale-Stack/01-opentelemetry-collector-vs-grafana-alloy-pipelines-tail-sampling-and-spanmetrics.md)).
- **Close the loop.** Add a synthetic user journey whose failure pages independently of the service's own metrics.
- **Track the SLO of the observability platform itself.**
</details>

---

## 5. Invariants checklist

- [ ] Every answer covers mechanism, magnitude, failure, trade-off and organisation, at least four of five.
- [ ] Every number quoted is reproducible from a listing or a pinned source in this KB.
- [ ] Incident response follows detect → scope → localise → mitigate → explain, with mitigation not blocked on explanation.
- [ ] The telemetry's own health (absence, Watchdog, rule failures, pipeline drops) is checked in every incident.
- [ ] Every postmortem adds a test, alert or budget that would have caught the incident earlier.

---

## 6. References

- Google SRE Book, managing incidents: <https://sre.google/sre-book/managing-incidents/>
- Google SRE Workbook, alerting on SLOs: <https://sre.google/workbook/alerting-on-slos/>
- Google SRE Workbook, postmortem culture: <https://sre.google/workbook/postmortem-culture/>
- Brendan Gregg, the USE method: <https://www.brendangregg.com/usemethod.html>
- Prometheus TSDB format documentation (v3.15.1): <https://github.com/prometheus/prometheus/tree/v3.15.1/tsdb/docs/format>
- Grafana Tempo TraceQL: <https://grafana.com/docs/tempo/latest/traceql/>
- OpenTelemetry semantic conventions: <https://opentelemetry.io/docs/specs/semconv/>
