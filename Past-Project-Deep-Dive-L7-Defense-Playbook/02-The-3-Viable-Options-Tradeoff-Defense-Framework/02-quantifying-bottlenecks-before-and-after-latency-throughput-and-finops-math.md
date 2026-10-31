# 02.2 · Quantifying Bottlenecks: Before-and-After Latency, Throughput and FinOps Math

> **Folder:** `02-The-3-Viable-Options-Tradeoff-Defense-Framework` · file 2 of 3
> **Question this file answers:** how do I turn "it was slow, so we rebuilt it, and now it's fast and cheaper" into numbers that survive two Principal Engineers checking the derivation, the measurement and the causality? Which formulas should I be able to apply on a whiteboard in under a minute?
> **Running exhibits:** P-0 Beacon, Tidewater (Archetype A preview) and Tillpoint (Archetype B preview); see [02.1](01-proving-first-principles-why-you-rejected-option-a-and-option-b.md).
> **Scope labels:** L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff.

| Listing | Language | What it does | Where it runs |
|---|---|---|---|
| L5 `capacity_math.py` | Python 3, standard library | Computes every quantity quoted in this file and in 02.1 §4: Little's law, M/M/1 and M/M/c (Erlang C) response times, fan-out tail probability, availability composition and error budgets, batch-window overflow, single-database fit, deploy-queue utilization, a seeded simulation showing percentiles don't add, total-cost FinOps comparisons, and Beacon's egress | [§13](#13-the-capacity-math-tool) |

**Verification.** The gate extracts the listing from this file and checks it byte for byte against the source that was run. It then re-runs the listing and compares the result with the output block in §13. The simulation is seeded, so its output is deterministic. Tellings are linted by the Folder 01 lints. Results are in the [README](../README.md#gate-results).

---

## 0. Orientation

Every deep dive eventually reaches numbers. The interviewers will check them in three ways. **Derivation:** can you produce the number from first principles? **Measurement:** where did it come from, and is that the right place to measure? **Attribution:** did *your change* cause the before/after difference, or did something else? This file gives you the formulas for the first check, the measurement discipline for the second, and the causal reasoning for the third. Every worked number is computed by `capacity_math.py` (§13), so you can see the arithmetic and replace the placeholder inputs with your own.

---

## 1. First principles: a number is a claim with three parts

### 1.1 Derived, measured, attributed

| Part | Question | Weak | Strong |
|---|---|---|---|
| **Derived** | Could you have predicted it? | "It handles 4,800 QPS" | "48,000 instances ÷ 10 s poll = 4,800 QPS; I estimated it before the load test" |
| **Measured** | Where, how, over what window? | "From the dashboard" | "Server-side histogram at the replica, peak hour, 7 days; client-side p99 agrees within 2 ms" |
| **Attributed** | Why did it change? | "After the migration, latency dropped 40%" | "The canary cell with the new path had p99 141 ms vs 238 ms in the control cell, same hour, same traffic mix" |

Interviewers probe the weakest of the three. A measured but underived number suggests you didn't understand the system. A derived but unmeasured number suggests you never checked. An unattributed before/after delta suggests the improvement may have come from somewhere else.

### 1.2 Normalize before you compare

A before/after comparison is valid only if the conditions match. Normalize for:
- **Load:** compare at the same request rate, or report per-unit numbers (cost per million events, CPU-ms per request).
- **Mix:** a latency drop after "the migration" may just be a shift in the request mix (more cache-friendly reads).
- **Season:** comparing November with February in commerce means nothing.
- **Version and hardware:** a hardware refresh in the same quarter is the most common hidden confounder.

### 1.3 Distributions, not averages

- **Report percentiles from histograms,** not averages: tail behavior is what users and SLOs see.
- **Never average percentiles across hosts or time windows.** The average of 10 hosts' p99s is not the fleet p99. Merge the histograms, then take the percentile.
- **Percentiles don't add** across serial calls (§3.4).
- **State the window and the percentile together:** "p99 over 1-minute windows, then the median of those across the peak hour" is a definition; "p99" alone isn't.

---

## 2. Finding the bottleneck before you fix it

**Name the bottleneck before the solution.** A deep dive that says "it was slow, so we rewrote it in a streaming framework" without saying *what resource was saturated* is a solution looking for a problem.

**Method 1: USE (Utilization, Saturation, Errors), per resource.** Brendan Gregg's USE method ([brendangregg.com](https://www.brendangregg.com/usemethod.html)) asks three questions of every resource (CPU, memory, disk, network, locks, connection pools, thread pools):
- How busy is it? (utilization)
- How much work is queued? (saturation)
- Is it failing? (errors)

The first saturated resource on the request path is the bottleneck.

**Method 2: the request-level golden signals** of latency, traffic, errors and saturation, from Google's SRE book ([Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/)). These tell you *that* there's a problem; USE tells you *where*.

**Method 3: Amdahl's law for "we parallelized it".** If a fraction *p* of the work parallelizes over *n* workers, the speedup is 1 / ((1 − p) + p/n). With p = 0.9, the speedup can never exceed 10×, however many workers you add. Interviewers use this against "we scaled out the workers 20×, so it got 20× faster".

| Archetype | The bottleneck to name | How it was found |
|---|---|---|
| Beacon | Not throughput: the coupling of propagation speed to blast radius | Incident analysis (A1–A3), not profiling |
| Tidewater | The single-threaded merge step in the nightly job, plus the 24 h cadence | Job-stage timing: 71% of the 5.56 h was in the merge stage |
| Tillpoint | Checkout's synchronous fan-out (40 calls), and lock contention on the inventory row for hot SKUs | Distributed traces; `pg_stat_activity` wait events showed lock waits on 0.3% of SKUs |

---

## 3. Latency math

### 3.1 Little's law: L = λW

The average number of items in a system equals the arrival rate times the average time each spends there. It holds for any stable system regardless of distribution (Little, *Operations Research* 9(3), 1961, DOI 10.1287/opre.9.3.383). Uses on a whiteboard:
- **Sizing pools.** Tillpoint's checkout at peak: 2,400 requests/s × 180 ms = **432 concurrent requests**. A 200-connection pool is undersized by construction, whatever the timeouts are.
- **Sanity-checking claims.** Beacon's polling alternative: 4,800 QPS × 2 ms = **9.6 requests in flight**. That is trivial for one replica, which is why throughput isn't the argument against it.
- **Deriving latency from concurrency.** If a service holds 50 concurrent requests at 1,000 RPS, its average latency is 50 ms, whatever the dashboard claims.

### 3.2 The queueing knee: why 70–80% utilization is a ceiling

For a single server with random arrivals and service times (M/M/1), the mean response time is *service time ÷ (1 − ρ)*, where ρ is utilization. With the service time fixed at 2 ms:

| Utilization ρ | M/M/1 response | M/M/8 response (8 servers, same per-server ρ) | M/M/8 P(wait) |
|---|---|---|---|
| 0.50 | 4.0 ms | 2.03 ms | 5.9% |
| 0.70 | 6.7 ms | 2.23 ms | 27.1% |
| 0.80 | 10.0 ms | 2.57 ms | 45.8% |
| 0.90 | 20.0 ms | 3.75 ms | 70.2% |
| 0.95 | 40.0 ms | 6.22 ms | 84.4% |

Two lessons that interviewers expect you to know:
1. **The knee.** Response time explodes as ρ → 1. That is why a "fits at 90% utilization" claim is a failure, not a fit. Plan peak utilization at 70–80% for latency-sensitive resources.
2. **Pooling.** Eight servers sharing one queue behave far better at the same utilization than eight separate queues (M/M/8 vs 8 × M/M/1). That is the math behind "one shared pool beats per-partition pools" and behind work stealing. It's also why *hot keys* hurt: they turn a pooled system into one saturated single server.

These are model numbers. Real service-time distributions have heavier tails, which make the knee worse, so treat the table as a lower bound on the damage.

### 3.3 Fan-out tail amplification

If a request fans out to *N* backends and waits for all of them, and each backend is slow (above its own p99) with probability 1%, then the probability that the request sees at least one slow backend is 1 − 0.99ᴺ:

| Fan-out N | P(request sees ≥ 1 backend p99) |
|---|---|
| 1 | 1.0% |
| 10 | 9.6% |
| 40 | 33.1% |
| 100 | 63.4% |

Dean and Barroso's "The Tail at Scale" (*Communications of the ACM* 56(2), 2013, DOI 10.1145/2408776.2408794) made this the standard argument for tail-tolerant techniques: hedged requests, tied requests, and reducing fan-out.

**Tillpoint worked example.** Checkout fanned out to 40 calls, so a third of checkouts touched at least one backend's p99. Caching the 28 read-mostly lookups (catalog, pricing tiers, feature flags) cut the fan-out to 12, and the tail exposure from 33.1% to **11.4%**. That one number is the defense of the cache. Caching didn't make individual calls faster; it removed calls from the tail lottery.

#### How an L5 tells it

> The checkout page was really slow because it called a lot of services. We added caching and it got way faster, around 40% better latency overall, which was a huge improvement for customers.

#### How an L7 tells it

> Checkout's p99 was dominated by fan-out, not by any single slow service. It made 40 calls, so at a 1% chance of any one call being in its own tail, about 33% of checkouts hit at least one tail. I cached the 28 read-mostly lookups with event-driven invalidation, which took the fan-out to 12 and the tail exposure to about 11%. In a 2-week canary against a control cell at the same traffic mix, checkout p99 went from 238 to 141 milliseconds, while p50 moved only from 62 to 55. That pattern is what you'd expect if the change removed tail exposure rather than speeding up calls.

### 3.4 Percentiles don't add

Interviewers sometimes ask: "Your three calls have p99s of 64, 141 and 38 ms. What's the end-to-end p99?" The wrong answer is 243 ms. In a seeded simulation of three independent lognormal calls with those p99s, the p99 of the sum is **185 ms** (p50 75 ms). The tails rarely coincide. The sum of p99s is a pessimistic upper bound for independent calls. It's not even a bound when the calls are *correlated*, for example during a GC pause or a shared database brownout, which is when tails coincide.

**How to answer.** "Somewhere between the largest single p99 and the sum, depending on correlation. For independent calls it's well below the sum; our traces showed 185 ms. If they share a dependency that stalls, they're correlated, and the tail approaches the sum or worse."

### 3.5 Latency budgets

A latency SLO is a budget to allocate, hop by hop. Allocate at the **percentile the SLO uses**, leave a **reserve** for queueing (§3.2), and remember that §3.4 means you can't simply subtract per-hop p99s from the total. A workable whiteboard method:
- Budget the *mean* or *p50* additively.
- Budget the tail with the fan-out and correlation reasoning above.
- Confirm with traces.

### 3.6 Measurement pitfalls interviewers know about

| Pitfall | What goes wrong | Defense |
|---|---|---|
| **Coordinated omission** | A load generator that waits for each response before sending the next one under-samples exactly the slow periods. Gil Tene's HdrHistogram project documents the problem ([hdrhistogram.org](http://hdrhistogram.org/)). | Open-loop load at a fixed arrival rate; record intended start times |
| **Client vs server time** | Server-side latency excludes queueing in the client's pool and the network | Measure where the user's clock runs, and say which you quoted |
| **Averaged percentiles** | Mean of per-host p99s ≠ fleet p99 | Merge histograms |
| **Survivorship** | Timeouts and errors excluded from latency stats make p99 look better | Count timeouts at the timeout value, or report them separately |
| **Warm vs cold** | Benchmarks after warm-up hide cold-start behavior (JIT, caches) | Report both if restarts are frequent (Beacon's INC-B7 was a cold-start problem) |

---

## 4. Throughput math

### 4.1 Peak-to-mean and headroom

- **Measure the ratio; don't assume it.** Tillpoint's Black Friday peak was 8× the November mean: 2,400 orders/s against 300.
- **Headroom = capacity ÷ peak demand.** For latency-sensitive resources, plan for peak utilization ≤ 70–80% (§3.2).
- **Ask what the peak is made of.** A peak from many users behaves differently from a peak from a few hot keys (§4.4).

### 4.2 Batch-window arithmetic

Processing time = records ÷ rate. Overflow time under compound growth *g*: *t* = ln(window ÷ current time) ÷ ln(1 + g).

**Tidewater:**
- 180M records ÷ 9,000 records/s = **5.56 h** of a 6 h window.
- At 35% annual growth, overflow comes in **3.1 months**.
- Worst-case freshness of a daily batch is about 24 h + 5.56 h = **29.6 h**.

The first two numbers justify *some* change. Only the third justifies leaving batch, and even then only past a micro-batch (02.1 §8.3).

### 4.3 Single-database fit (the concession calculator)

Peak rows/s = peak transactions/s × rows per transaction. Compare with *measured* capacity on your hardware, for your schema and indexes, at your durability settings (`synchronous_commit`, replication mode).

**Tillpoint:** 2,400 orders/s × 6 rows = **14,400 rows/s**, against 40,000 rows/s measured, so **36%** at peak. It fits. The split needed other reasons (02.1 §4.4, §4.5), and the L7 answer says so first.

### 4.4 Partitioning math and hot keys

For a partitioned log or table:
- **Partitions needed** ≥ peak throughput ÷ the per-partition throughput a single consumer sustains, plus headroom.
- **Skew.** Throughput is limited by the *hottest* partition, not the average. With a Zipf-like key distribution, the hottest key can carry several percent of all traffic by itself.
- **Hot-key mitigations:** key salting (spread one key over k sub-keys, then merge), combiner lifting (pre-aggregate before the shuffle), and per-key rate limits.

#### How an L5 tells it

> We had some hot partitions in Kafka, so we added more partitions and that basically fixed the throughput problem. We also scaled up the consumers to handle the load better.

#### How an L7 tells it

> The topic had 48 partitions and the consumers sustained about 3,000 events a second each, so the nominal capacity was about 144,000 a second against a 60,000 peak. It still lagged, because 1 partition carried 9% of all events: a single large broker account generating claims in bulk. Adding partitions would not have moved that key, since a key maps to 1 partition. I salted that account's key across 8 sub-keys and merged the per-sub-key aggregates downstream, which took the hottest partition from 9% of traffic to under 2% and the peak consumer lag from 14 minutes to under 30 seconds.

### 4.5 Amdahl, revisited for pipelines

A pipeline is as fast as its slowest *serial* stage. Tidewater's merge stage was 71% of the job and single-threaded. Parallelizing everything else 10× would have taken the job from 5.56 h to about 4.1 h: 5.56 × (0.71 + 0.29/10) ≈ 4.11 h. That is still inside one window, but it buys only months of growth and does nothing for freshness.

---

## 5. Availability math

| Composition | Formula | Example |
|---|---|---|
| **Serial** (all must work) | ∏ aᵢ | 5 dependencies at 99.95% → **99.7502%** |
| **Parallel, independent** (any one suffices) | 1 − ∏(1 − aᵢ) | 2 replicas at 99.9% → **99.9999%**, *only if failures are independent* |
| **Error budget** | (1 − SLO) × period | 30 days: 99.9% → **43.2 min**, 99.95% → **21.6 min**, 99.99% → **4.3 min** |

**The independence caveat is the interviewer's favorite attack on redundancy math.** Two replicas behind the same config system, deployed by the same pipeline, in the same region, are *not* independent. Beacon's A1 would have taken down every replica of every service at once. The SRE book's chapter on risk and error budgets ([Embracing Risk](https://sre.google/sre-book/embracing-risk/)) is the standard reference for budget-based reasoning.

**The 4.3-minute lesson.** At 99.99%, a 30-day error budget is about 4 minutes. A human-in-the-loop rollback that takes 10 minutes spends 2.5 months of budget in one incident. That arithmetic is the defense of *automated* halts (Beacon's rollout controller) at high SLOs.

---

## 6. FinOps math: unit economics and the total-cost trap

### 6.1 Unit economics

Report cost per unit of business work (per million events, per thousand orders, per tenant-month), not total monthly spend, so comparisons survive growth. The FinOps Foundation's framework ([finops.org](https://www.finops.org/framework/)) organizes the practice around making cost visible, then optimizing it, then operating it continuously. In an interview, the "visible" part is what matters: can you state your system's unit cost, and what drives it?

### 6.2 The total-cost comparison (people included)

**Tidewater (placeholder prices; use your bill).**

| | Now: 5,400M events/month | In 12 months: 7,290M events/month |
|---|---|---|
| On-prem infrastructure | $61,000 ($11.30/M) | $99,000 ($13.58/M). The capacity step needed when the window overflows. |
| Cloud infrastructure | $57,260 ($10.60/M) | $75,026 ($10.29/M) |
| On-prem total (+1.5 FTE operations) | $92,250 | $130,250 |
| Cloud total (+2 FTE pipeline engineering) | $98,927 | $116,693 |
| **Cloud vs on-prem, total** | **costs $6,677/month more** | **saves $13,557/month** |

What this table teaches:
1. **Infrastructure-only comparisons mislead.** Cloud was cheaper on infrastructure from day one, but more expensive in total once people were counted.
2. **On-prem "fixed" costs are step functions.** The $38k/month capacity step is what flips the total-cost result. Know when your next step comes.
3. **The migration's FinOps case is real but secondary.** It turns positive only after growth forces the step. The primary case was freshness (a kill criterion), and claiming the move was "for cost" would fail the first total-cost probe.

#### How an L5 tells it

> Moving to the cloud saved a lot of money, because we no longer had to pay for the expensive on-prem appliance. Dataflow is also really cost efficient since it autoscales.

#### How an L7 tells it

> On infrastructure alone, cloud was about $3,700 a month cheaper at launch, $57,260 against $61,000. Counting people, it was about $6,700 a month more expensive, because the new pipeline needed 2 engineers against 1.5 for the appliance. The total-cost case turned positive about 3 months in, when growth would have forced a $38,000-a-month capacity step on-prem; after that, cloud saves about $13,500 a month. So I never sold the migration on cost. I sold it on the 30-minute freshness requirement, and I reported cost per million events monthly, $10.60 at launch, so the cost story stayed honest.

### 6.3 The cost of complexity

Every component you add has a people cost: on-call, upgrades, security patching, expertise. A rough rule worth stating in interviews: **each independently operated stateful system costs a meaningful fraction of an engineer to run well**, and that fraction must be counted on the "complex" side of the ledger. Beacon's relay tier is ~0.5 engineer (01.3 K5). If you can't state your design's people cost, the interviewer will assume you never counted it.

### 6.4 Commitments and the shape of demand

- **Committed-use or reserved discounts** reward predictable baselines. Spiky peaks stay on demand.
- **State the shape of demand in your FinOps argument:** "the baseline 60% is on a 1-year commitment; the Black Friday peak runs on demand" shows you priced the shape, not just the average.
- **Prices change, so cite the method, not a price list.** Every price in this file is a placeholder.

---

## 7. Velocity math (cross-reference)

The deploy-queue model is in 02.1 §4.5:
- **Demand:** 14 teams × 3 deploys/day = 42.
- **Capacity:** a 45-minute train fits 13.3 a day, so ρ = **3.15**.
- **After the pipeline fix:** 12 minutes per deploy gives ρ = 0.84 and a mean wait of **63 minutes**.
- **Coordination:** 14 teams have **91** pairwise paths.

`capacity_math.py` computes it as scenario S7. The general lesson for this file: *velocity claims are queueing claims*, and should be presented with demand, capacity and wait, like any other throughput argument.

---

## 8. Presenting before/after: the delta table

Every outcome you claim should fit in one row of this table:

| Metric | Before | After | Normalization | Measured at | Attribution evidence | Known confounders |
|---|---|---|---|---|---|---|
| Beacon flag propagation | 55 min (YAML) / ~2 s uncontrolled (ZK) | p99 24 s within the target ring | Per change, in-ring | SDK applied-version reports | Design property, not a speedup claim | None material |
| Beacon config-caused Sev-1s | 2 per 12 months | 0 per 12 months | Same 12-month windows | Incident tracker | 3 bad changes auto-halted in ring0 (each would have gone global before) | Small numbers: 2 → 0 is suggestive, not statistically strong. Say so. |
| Tidewater freshness | ~29.6 h worst case | ~3 min p95 | Heartbeat rows, 30 days | Warehouse query on heartbeat table | Direct: the pipeline is the only path | — |
| Tillpoint checkout p99 | 238 ms | 141 ms | Same traffic mix, same hours | Canary vs control cell, 2 weeks | Control cell unchanged; p50 barely moved (tail effect) | A CDN change in week 2 (excluded by comparing cells) |
| Tidewater cost per million events | $11.30 (infra) | $10.60 (infra) | Per million events | Monthly bills | Direct | People cost excluded here; reported separately (§6.2) |

**Say "small numbers" when the numbers are small.** "2 Sev-1s to 0" over a year is not statistical proof. An L7 says so and points to the mechanism evidence, here the three auto-halts, as the stronger argument. Interviewers notice candidates who overclaim from small samples.

---

## 9. Attribution: proving your change caused the delta

Hierarchy of evidence, strongest first:
1. **Controlled comparison.** A canary or A/B against a control at the same time, on the same traffic.
2. **Dose-response.** The effect scales with how much of the change was applied: a ring at 1% shows 1% of the effect, the next ring more.
3. **Time alignment with ruled-out confounders.** The metric moved at the deploy time, and nothing else changed then (deploy log, config log, traffic mix, hardware).
4. **Mechanism plus partial evidence.** The design predicts the effect, and partial measurements agree (the p50 vs p99 shape in §3.3).
5. **Before/after alone.** Weakest. Present it with its confounders named.

#### How an L5 tells it

> After we launched the new service, the error rate dropped a lot, so the migration clearly worked. The dashboards showed a big improvement right after we went live.

#### How an L7 tells it

> The error rate fell from 0.42% to 0.09% across the cutover month, but the month-over-month comparison alone would not convince me, because a CDN change shipped in the same month. The evidence I trust is the ring data: as each ring cut over, its error rate dropped to about 0.09% while the rings still on the old path stayed near 0.4%, at the same hours and traffic. That's a controlled comparison twice over, at the 1% and 33% rings, and the final ring landed at the same 0.09%. The CDN change touched static assets only, and the API error rate in the control rings didn't move when it shipped.

---

## 10. When the math kills a worry: Beacon's egress

An interviewer may ask: "48,000 instances fetching snapshots on every change: isn't that a lot of egress?" Derive it:
- **Average change:** 270 changes/day × ~60 instances × 18 KB ≈ **285 MB/day**.
- **Widest namespace:** 4 changes/day to `platform/global` × 48,000 × 18 KB ≈ **3,375 MB/day**.
- **Total:** about **3.6 GB/day**, which isn't a design driver.

**Answering with the derivation in 20 seconds is stronger than "it was fine".** It also shows that you checked the worry rather than dismissing it.

---

## 11. Numbers on the whiteboard: derivation on demand

- **Keep the inputs on the board, not just the results.** In the numbers column (01.1 §5), write "48,000 inst", "10 s poll", "18 KB median". Any derived number can then be re-derived in front of the interviewers in seconds.
- **Derive aloud, and round deliberately.** "48,000 over 27 is about 1,800" is better than reciting "1,778", which sounds memorized.
- **When challenged on a number, re-derive it; don't defend it.** A derivation either survives or reveals your error. Both are better than insisting.

#### How an L5 tells it

> I think it was around 5,000 queries per second at peak, which our database basically handled without any trouble. I'd have to check the exact number on the dashboard, but it was a lot of traffic.

#### How an L7 tells it

> Let me derive it rather than recall it. 48,000 instances polling every 10 seconds is 4,800 queries a second, and each query is a point read on an indexed key, so by Little's law with about 2 milliseconds per query, roughly 10 are in flight at any moment. The load test agreed: one replica sustained 12,000 a second at that query shape, so the polling load would have run that replica at about 40%.

---

## 12. Hiring-committee scoring rubric: quantification

Bands follow the poor / borderline / solid / outstanding vocabulary of Google's public structured-interviewing guidance ([re:Work](https://rework.withgoogle.com/intl/en/guides/a-guide-to-structured-interviewing-for-better-hiring-practices)). The anchors are a composite (⚠).

| Dimension | Poor | Borderline | Solid (L6) | Outstanding (L7) |
|---|---|---|---|---|
| **Derivation** | Numbers recited | Some numbers derivable | Key numbers derived from inputs on the board | Derives under challenge; knows which model applies and its limits (M/M/1 as a lower bound) |
| **Measurement** | "The dashboard" | Names the metric | Names where, the window and the percentile | Also names the pitfalls avoided (coordinated omission, averaged percentiles) |
| **Attribution** | Before/after only | Mentions a confounder | Controlled comparison | Dose-response across rings; confounders ruled out explicitly |
| **Bottleneck** | Solution before problem | Names a slow component | Names the saturated resource (USE) | Names it, and shows why the alternative fixes (more partitions, more workers) wouldn't move it |
| **FinOps** | "It was cheaper" | Infra cost only | Unit cost, before and after | Total cost including people, capacity steps and the demand shape; states when the case turns positive |

---

## 13. The capacity math tool

### 13.1 Listing L5: `capacity_math.py`

<!-- listing:capacity_math.py -->
```python
#!/usr/bin/env python3
"""capacity_math.py - the back-of-envelope math behind "why not simpler?".

Every number quoted in 02.2 is printed by one of the scenarios below, so the
prose and the arithmetic cannot drift apart. Inputs marked [placeholder] are
composite values: replace them with your own measurements.

  S1  Little's law              L = lambda * W
  S2  Queueing knee             M/M/1 and M/M/c (Erlang C) response time vs utilization
  S3  Fan-out tail              P(a request touches >= 1 slow backend) = 1 - p^N
  S4  Availability              serial product, parallel redundancy, error budget
  S5  Batch window              when does the nightly cron stop fitting?
  S6  Single-database fit       peak rows/s vs measured capacity (the honest concession)
  S7  Multi-team deploy queue   a shared release train as an M/M/1 queue
  S8  Percentiles don't add     sum of p99s vs p99 of the sum (seeded simulation)
  S9  FinOps unit economics     cost per million events and the people-cost break-even
  S10 Beacon egress             what the fan-out actually costs per day

Usage: python -I capacity_math.py [<file.md>]   (the argument is ignored)
Standard library only; deterministic (fixed seed).
"""
import math
import random
import sys


def erlang_c(c, a):
    """Probability that an arrival waits, M/M/c with offered load a = lambda/mu."""
    s = sum(a ** k / math.factorial(k) for k in range(c))
    top = a ** c / math.factorial(c) * (c / (c - a))
    return top / (s + top)


def mmc_response(c, rho, service_ms):
    mu = 1.0 / service_ms
    lam = rho * c * mu
    a = lam / mu
    pw = erlang_c(c, a)
    wq = pw / (c * mu - lam)
    return wq + service_ms, pw


def pct(xs, q):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(q * len(xs)))]


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    checks = 0
    print("S1 Little's law")
    lam, w = 4800.0, 0.002
    print(f"  Beacon polling alternative: {lam:,.0f} req/s x {w * 1000:.0f} ms = {lam * w:.1f} requests in flight")
    lam2, w2 = 2400.0, 0.180
    print(f"  checkout at peak: {lam2:,.0f} req/s x {w2 * 1000:.0f} ms = {lam2 * w2:,.0f} concurrent requests -> pool sizing floor")
    checks += 2

    print("S2 Queueing knee (service time 2 ms)")
    print("  rho    M/M/1 resp   M/M/8 resp   M/M/8 P(wait)")
    for rho in (0.5, 0.7, 0.8, 0.9, 0.95):
        r1 = 2.0 / (1 - rho)
        r8, pw = mmc_response(8, rho, 2.0)
        print(f"  {rho:.2f}   {r1:7.1f} ms   {r8:7.2f} ms     {pw:6.1%}")
    checks += 5

    print("S3 Fan-out tail (each backend slow with probability 1%)")
    for n in (1, 10, 40, 100):
        print(f"  N={n:<3}  P(request sees >= 1 backend p99) = {1 - 0.99 ** n:6.1%}")
    print(f"  checkout fan-out 40 -> 12 after caching: {1 - 0.99 ** 40:.1%} -> {1 - 0.99 ** 12:.1%}")
    checks += 5

    print("S4 Availability")
    serial = 0.9995 ** 5
    par = 1 - (1 - 0.999) ** 2
    print(f"  5 serial dependencies at 99.95%: {serial:.4%}")
    print(f"  2 independent replicas at 99.9% (parallel): {par:.4%}  (only if failures are independent)")
    for slo in (0.999, 0.9995, 0.9999):
        print(f"  SLO {slo:.2%} over 30 days -> error budget {(1 - slo) * 30 * 24 * 60:5.1f} min")
    checks += 5

    print("S5 Batch window (Archetype A preview)")
    recs, rate, window, growth = 180e6, 9000.0, 6.0, 0.35
    hours = recs / rate / 3600
    months = 12 * math.log(window / hours) / math.log(1 + growth)
    print(f"  {recs / 1e6:.0f}M records at {rate:,.0f} rec/s = {hours:.2f} h of a {window:.0f} h window")
    print(f"  at {growth:.0%}/yr growth the window overflows in {months:.1f} months")
    print(f"  freshness of a nightly batch: worst case ~{24 + hours:.1f} h vs a 30 min requirement")
    checks += 3

    print("S6 Single-database fit (Archetype B preview) [placeholder capacity]")
    mean_orders, peak_x, rows_per_order, cap_rows = 300.0, 8, 6, 40000.0
    peak_rows = mean_orders * peak_x * rows_per_order
    print(f"  peak {mean_orders * peak_x:,.0f} orders/s x {rows_per_order} rows = {peak_rows:,.0f} rows/s "
          f"vs {cap_rows:,.0f} measured -> utilization {peak_rows / cap_rows:.0%}")
    print("  verdict: a single primary fits the peak; throughput is NOT the reason to split")
    checks += 1

    print("S7 Multi-team deploy queue (shared release train)")
    teams, per_day, day_min = 14, 3, 600.0
    for deploy_min in (45.0, 12.0):
        cap = day_min / deploy_min
        demand = teams * per_day
        rho = demand / cap
        if rho >= 1:
            batch = demand / cap
            print(f"  {deploy_min:.0f} min/deploy: capacity {cap:.1f}/day vs demand {demand}/day (rho {rho:.2f}) "
                  f"-> queue grows without bound; forced batching ~{batch:.1f} changes/deploy")
        else:
            wait = rho / (1 - rho) * deploy_min
            print(f"  {deploy_min:.0f} min/deploy: capacity {cap:.1f}/day vs demand {demand}/day (rho {rho:.2f}) "
                  f"-> mean wait {wait:.0f} min (M/M/1)")
    print(f"  coordination paths among {teams} teams: {teams * (teams - 1) // 2}")
    checks += 3

    print("S8 Percentiles don't add (3 serial calls, lognormal, seed 7, 200,000 samples)")
    rng = random.Random(7)
    a = [rng.lognormvariate(math.log(20), 0.5) for _ in range(200000)]
    b = [rng.lognormvariate(math.log(35), 0.6) for _ in range(200000)]
    c = [rng.lognormvariate(math.log(15), 0.4) for _ in range(200000)]
    s = [x + y + z for x, y, z in zip(a, b, c)]
    sum_p99 = pct(a, 0.99) + pct(b, 0.99) + pct(c, 0.99)
    print(f"  p99s: {pct(a, .99):.0f} + {pct(b, .99):.0f} + {pct(c, .99):.0f} = {sum_p99:.0f} ms (sum of p99s)")
    print(f"  p99 of the end-to-end sum = {pct(s, .99):.0f} ms; p50 = {pct(s, .50):.0f} ms")
    checks += 2

    print("S9 FinOps unit economics [placeholder prices]")
    fte = 250000.0 / 12
    cloud_fixed, cloud_var = 6500.0, 9.40
    for label, events_m, onprem_infra in (("now", 5400.0, 61000.0), ("in 12 months", 5400.0 * 1.35, 99000.0)):
        cloud_infra = cloud_fixed + cloud_var * events_m
        onprem_total = onprem_infra + 1.5 * fte
        cloud_total = cloud_infra + 2.0 * fte
        print(f"  {label}: {events_m:,.0f}M events/month")
        print(f"    infra only : on-prem ${onprem_infra:,.0f} (${onprem_infra / events_m:.2f}/M) vs "
              f"cloud ${cloud_infra:,.0f} (${cloud_infra / events_m:.2f}/M)")
        print(f"    with people: on-prem ${onprem_total:,.0f} (1.5 FTE) vs cloud ${cloud_total:,.0f} (2 FTE) "
              f"-> cloud {'saves' if cloud_total < onprem_total else 'costs'} ${abs(onprem_total - cloud_total):,.0f}/month")
    breakeven = (61000.0 - cloud_fixed) / cloud_var
    print(f"  infra-only break-even before the on-prem capacity step: {breakeven:,.0f}M events/month")
    checks += 5

    print("S10 Beacon egress per day")
    avg = 270 * 60 * 18 / 1024
    wide = 4 * 48000 * 18 / 1024
    print(f"  270 changes x ~60 instances x 18 KB = {avg:,.0f} MB; 4 platform/global changes x 48,000 x 18 KB = {wide:,.0f} MB")
    print(f"  total ~{(avg + wide) / 1024:.1f} GB/day -> egress is not a design driver")
    checks += 1

    print()
    print(f"verdict: OK ({checks} quantities computed)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

### 13.2 Output

<!-- output:capacity_math.py -->
```text
S1 Little's law
  Beacon polling alternative: 4,800 req/s x 2 ms = 9.6 requests in flight
  checkout at peak: 2,400 req/s x 180 ms = 432 concurrent requests -> pool sizing floor
S2 Queueing knee (service time 2 ms)
  rho    M/M/1 resp   M/M/8 resp   M/M/8 P(wait)
  0.50       4.0 ms      2.03 ms       5.9%
  0.70       6.7 ms      2.23 ms      27.1%
  0.80      10.0 ms      2.57 ms      45.8%
  0.90      20.0 ms      3.75 ms      70.2%
  0.95      40.0 ms      6.22 ms      84.4%
S3 Fan-out tail (each backend slow with probability 1%)
  N=1    P(request sees >= 1 backend p99) =   1.0%
  N=10   P(request sees >= 1 backend p99) =   9.6%
  N=40   P(request sees >= 1 backend p99) =  33.1%
  N=100  P(request sees >= 1 backend p99) =  63.4%
  checkout fan-out 40 -> 12 after caching: 33.1% -> 11.4%
S4 Availability
  5 serial dependencies at 99.95%: 99.7502%
  2 independent replicas at 99.9% (parallel): 99.9999%  (only if failures are independent)
  SLO 99.90% over 30 days -> error budget  43.2 min
  SLO 99.95% over 30 days -> error budget  21.6 min
  SLO 99.99% over 30 days -> error budget   4.3 min
S5 Batch window (Archetype A preview)
  180M records at 9,000 rec/s = 5.56 h of a 6 h window
  at 35%/yr growth the window overflows in 3.1 months
  freshness of a nightly batch: worst case ~29.6 h vs a 30 min requirement
S6 Single-database fit (Archetype B preview) [placeholder capacity]
  peak 2,400 orders/s x 6 rows = 14,400 rows/s vs 40,000 measured -> utilization 36%
  verdict: a single primary fits the peak; throughput is NOT the reason to split
S7 Multi-team deploy queue (shared release train)
  45 min/deploy: capacity 13.3/day vs demand 42/day (rho 3.15) -> queue grows without bound; forced batching ~3.1 changes/deploy
  12 min/deploy: capacity 50.0/day vs demand 42/day (rho 0.84) -> mean wait 63 min (M/M/1)
  coordination paths among 14 teams: 91
S8 Percentiles don't add (3 serial calls, lognormal, seed 7, 200,000 samples)
  p99s: 64 + 141 + 38 = 243 ms (sum of p99s)
  p99 of the end-to-end sum = 185 ms; p50 = 75 ms
S9 FinOps unit economics [placeholder prices]
  now: 5,400M events/month
    infra only : on-prem $61,000 ($11.30/M) vs cloud $57,260 ($10.60/M)
    with people: on-prem $92,250 (1.5 FTE) vs cloud $98,927 (2 FTE) -> cloud costs $6,677/month
  in 12 months: 7,290M events/month
    infra only : on-prem $99,000 ($13.58/M) vs cloud $75,026 ($10.29/M)
    with people: on-prem $130,250 (1.5 FTE) vs cloud $116,693 (2 FTE) -> cloud saves $13,557/month
  infra-only break-even before the on-prem capacity step: 5,798M events/month
S10 Beacon egress per day
  270 changes x ~60 instances x 18 KB = 285 MB; 4 platform/global changes x 48,000 x 18 KB = 3,375 MB
  total ~3.6 GB/day -> egress is not a design driver

verdict: OK (32 quantities computed)
```

**Reading the output.** Every number quoted in §3–§10, and in 02.1 §4, appears in this output. Replace the placeholder inputs (capacities, prices, team counts) with your own measured values, re-run, and keep the output next to your dossier (Folder 05). The derivation you practice is the one you'll do on the whiteboard.

---

## 14. Failure modes

| # | Failure mode | Symptom | Fix |
|---|---|---|---|
| F1 | **Recited numbers** | Can't re-derive under challenge | Keep the inputs on the board; derive aloud (§11) |
| F2 | **Utilization denial** | "It fits at 90%" | The queueing knee (§3.2) |
| F3 | **Adding p99s** | 64 + 141 + 38 = 243 ms "end to end" | Percentiles don't add; correlation matters (§3.4) |
| F4 | **Averaged percentiles** | Mean of host p99s reported as fleet p99 | Merge histograms (§1.3) |
| F5 | **Unattributed delta** | "After launch it got better" | Controlled comparison; dose-response (§9) |
| F6 | **Independence assumed** | 2 replicas = 99.9999% | Shared config, deploys and region break independence (§5) |
| F7 | **More partitions for a hot key** | Lag persists after scaling out | A key maps to one partition; salt or pre-aggregate (§4.4) |
| F8 | **Infra-only FinOps** | "Cloud saved money" | Total cost with people and capacity steps (§6.2) |
| F9 | **Small-number overclaim** | "2 → 0 incidents proves it" | Say "small numbers"; lead with mechanism evidence (§8) |
| F10 | **Solution before bottleneck** | "We rewrote it in streaming" | Name the saturated resource first (§2) |

---

## 15. Bar-raiser chains

<details><summary><b>Q1 · "Your p99 dropped 40%. Prove the migration caused it."</b></summary>

**Initial Prompt.** "You said checkout p99 went from 238 to 141 ms after your change. Plenty of other things changed that quarter. Prove it was you."

**L5 Answer.** "The timing lines up exactly with our launch, and we didn't see any other big changes, so it has to be our change."

**Why L5 Stalls.** Time alignment is the weakest evidence (§9), and "we didn't see any other changes" invites the interviewer to name one. In this case, a CDN change shipped in the same window.

**L7 Answer.** "Timing alone wouldn't convince me either; a CDN change shipped in week 2. The evidence is the canary: for 2 weeks, one cell ran the cached path and a control cell didn't, at the same hours and traffic mix. The canary's p99 was 141 against 238 in the control. The CDN change hit both cells equally and touched static assets, not API calls. The shape is a second check: p50 moved only from 62 to 55. If calls had simply got faster, p50 would have dropped too. A p99-only drop is the signature of reduced fan-out exposure, which is what the design predicted: 33% to 11% of checkouts touching at least one tail."

</details>

<details><summary><b>Q2 · "Three calls with p99s of 64, 141 and 38 ms. What's the end-to-end p99?"</b></summary>

**Initial Prompt.** The interviewer writes three numbers on the board and asks for the composed p99.

**L5 Answer.** "243 milliseconds. You add them up since the calls are sequential."

**Why L5 Stalls.** Percentiles don't add. The answer reveals a gap in the statistics that latency budgets rely on, and the interviewer will now distrust every latency budget the candidate presents.

**L7 Answer.** "Not 243. That's the sum of p99s, which overstates the tail when the calls are independent, because their slow moments rarely coincide. In a simulation with those three p99s and independent lognormal latencies, the end-to-end p99 comes out around 185 milliseconds. The real answer depends on correlation. If all three share a dependency that stalls (a GC pause in a shared sidecar, a database brownout), the tails coincide and you approach 243 or worse. So I'd measure it from end-to-end traces rather than compose it, and I'd use the sum only as a pessimistic budget for independent calls."

</details>

<details><summary><b>Q3 · "You run the database at 85% CPU at peak. Is that fine?"</b></summary>

**Initial Prompt.** "Your load test shows the primary at 85% CPU at peak. You said it fits. Does it?"

**L5 Answer.** "Yes, there's still 15% headroom, so it can absorb a bit more traffic."

**Why L5 Stalls.** At 85% utilization, queueing delay is already several times the service time (§3.2), and "15% headroom" ignores that response time is nonlinear in utilization. The candidate treats capacity as linear.

**L7 Answer.** "At 85%, it fits on throughput and fails on latency. In a simple M/M/1 model, response time at 85% is about 6.7 times the service time, and real service-time tails make it worse. For a latency-sensitive primary I plan peak utilization at 70% or lower. So 85% at peak tells me I need about 20% more capacity or 20% less work at peak. In Tillpoint's case the work reduction was cheaper: moving 3 synchronous writes to the outbox took peak CPU from 85% to about 61%, and p99 commit latency from 31 to 9 milliseconds."

</details>

<details><summary><b>Q4 · "You added 4× the partitions and lag didn't improve. Why?"</b></summary>

**Initial Prompt.** A scenario: "Your consumer group lags at peak. You go from 48 to 192 partitions and the lag barely changes. What's happening?"

**L5 Answer.** "Maybe the consumers didn't scale up, or there was a rebalance issue. I'd check the consumer configuration."

**Why L5 Stalls.** Those are plausible checks, but the classic cause, a hot key, isn't mentioned, and it's the one that partition count can't fix.

**L7 Answer.** "My first hypothesis is skew: a hot key. A key hashes to one partition whatever the partition count, so if one key carries 9% of traffic, its partition's consumer is saturated at 48 or 192 partitions. I'd confirm with per-partition lag and bytes-in: one partition lagging while the rest are idle is the signature. The fixes act on the key, not the partition count. Salt the key across k sub-keys, if the downstream can merge, or pre-aggregate before the shuffle if the operation is a combinable aggregate. In Tidewater it was one broker account submitting bulk claims. Salting across 8 sub-keys took that partition from 9% to under 2% of traffic, and peak lag from 14 minutes to under 30 seconds."

</details>

<details><summary><b>Q5 · "Two replicas at 99.9% each gives you six nines. Agree?"</b></summary>

**Initial Prompt.** "You run two replicas, each 99.9% available. So the pair is 99.9999%?"

**L5 Answer.** "Yes, because both would have to fail at the same time, and that's very unlikely."

**Why L5 Stalls.** The formula assumes independent failures, and real replicas share config, deploys, regions, dependencies and bugs. The candidate has fallen for the most common redundancy fallacy.

**L7 Answer.** "Only if their failures are independent, and in practice they usually aren't. Two replicas that share a config system, a deploy pipeline, a region or a code bug fail together. Our A1 incident would have taken down both replicas of every service at once. The correlated failure modes set the real number, so I'd estimate it from them: how often does a bad deploy or config push hit both? That's why Beacon's rings and Tillpoint's cell-by-cell deploys exist. They make replicas *more* independent by never changing all of them at once. Six nines from two replicas is a ceiling you approach only by removing shared failure causes."

</details>

<details><summary><b>Q6 · "The cloud migration saved money. Show me the total-cost math."</b></summary>

**Initial Prompt.** "You claim the migration reduced cost. Include everything."

**L5 Answer.** "The on-prem appliance cost $61,000 a month and Dataflow costs around $57,000, so we saved about $4,000 a month, plus it autoscales."

**Why L5 Stalls.** Infrastructure only. The interviewer's next question, "and the people?", turns the saving negative, and the candidate didn't see it coming.

**L7 Answer.** "Infrastructure alone was about $3,700 a month cheaper at launch. With people it was about $6,700 a month *more* expensive: 2 FTE for the pipeline against 1.5 for the appliance. It turns positive only because on-prem cost is a step function. Growth would have forced a $38,000-a-month capacity step about 3 months in, and after that cloud saves about $13,500 a month in total. So the honest summary is that the migration wasn't justified by cost; it was justified by freshness, and the cost case became positive as a side effect of growth. I reported cost per million events monthly, $10.60 at launch and $10.29 a year later, so nobody had to take the cost claim on trust."

</details>

<details><summary><b>Q7 · "Your consumers scaled out 20×. Why did the job only get 1.4× faster?"</b></summary>

**Initial Prompt.** On Tidewater's batch history: "Someone scaled the workers from 4 to 80, and the nightly job went from 5.6 hours to about 4. Explain."

**L5 Answer.** "Probably there was some overhead from coordination, or the workers were waiting on I/O."

**Why L5 Stalls.** It's a guess without the model. Amdahl's law predicts exactly this, and an L7 should reach for it immediately.

**L7 Answer.** "Amdahl's law. 71% of the job's time was a single-threaded merge stage, so only 29% parallelized. With the parallel part split many ways, the job approaches 5.56 × 0.71 ≈ 3.95 hours, and you never get below that, however many workers you add. That matches what they saw. The serial merge was the bottleneck, and it was serial because it reconciled updates to the same policy across 6 source extracts in arrival order. The streaming design dissolved that bottleneck instead of parallelizing around it: each policy's updates are keyed and ordered by event time, so the merge happens per key, in parallel across keys."

</details>

<details><summary><b>Q8 · "What's your system's unit cost, and what drives it?"</b></summary>

**Initial Prompt.** "If I double your traffic tomorrow, what happens to your bill, line by line?"

**L5 Answer.** "It would probably roughly double, since everything autoscales."

**Why L5 Stalls.** "Probably roughly" means the candidate doesn't know the cost structure. And "everything autoscales" is rarely true: fixed costs, step functions and commitments exist in every bill.

**L7 Answer.** "Tidewater's bill has 4 lines that scale differently. Streaming compute is about 60% of the variable cost and scales roughly linearly with events, except for the hot-key work, which scales with the largest accounts. Warehouse storage grows with retained history, not with traffic, so doubling traffic doubles its *growth rate*. Streaming inserts are linear in rows. The fixed part, about $6,500 a month, covers monitoring, the schema registry and the dead-letter tooling, and doesn't move. So doubling traffic takes us from about $57,000 to about $108,000 a month: $6,500 fixed plus $9.40 per million events on 10,800 million. The unit cost falls slightly, from $10.60 to about $10, because the fixed part is spread thinner."

</details>

<details><summary><b>Q9 · "2 Sev-1s to 0. Is that statistically meaningful?"</b></summary>

**Initial Prompt.** "You keep citing 2 config incidents before and 0 after. Is that evidence?"

**L5 Answer.** "Yes, it went from 2 to zero, which is a 100% improvement."

**Why L5 Stalls.** "100% improvement" from 2 events is overclaiming from small numbers. Two events a year is consistent with chance variation, and an interviewer with any statistics will press on it.

**L7 Answer.** "On its own, no. 2 versus 0 in a year is well within chance for a rare event. I'd never rest the case on it. The stronger evidence is mechanistic and observed: 3 bad changes in the first year were auto-halted in the 1% canary ring, worst case 528 instances for 4 minutes. Each of those, under the old system, would have gone to all 48,000 instances in about 2 seconds, like A1 did. So the claim I'd defend is 'the exposure per bad change fell by about 860 times', which is measured per event. The incident count is consistent with that, but too small to prove it."

</details>

<details><summary><b>Q10 · "Size the connection pool for checkout. Right now, on the board."</b></summary>

**Initial Prompt.** "Peak 2,400 checkouts a second. Each holds a database connection for part of its life. How big is the pool?"

**L5 Answer.** "I'd probably start with something like 100 connections and tune it based on monitoring."

**Why L5 Stalls.** "Start with 100 and tune" isn't sizing. Little's law gives a floor in one line, and the interviewer wanted to see it applied.

**L7 Answer.** "Little's law on the database-holding portion, not the whole request. If a checkout holds a connection for about 12 milliseconds of its 180, then at 2,400 a second that's 2,400 × 0.012, about 29 connections busy on average. I'd size for the peak-of-peak and for variance: at 70% target utilization, about 41, and I'd split them across instances, say 12 instances at 4 each. The more important point is the other direction. If code holds the connection across the whole 180-millisecond request, for example a transaction opened before a remote call, the requirement jumps to 432, and no pool size fixes that. In Tillpoint, moving the payment call outside the transaction was worth more than any pool tuning."

</details>

---

## 16. Checklist

- [ ] For every number you'll say aloud: the derivation, the measurement (where, window, percentile), and the attribution evidence (§1.1).
- [ ] The bottleneck of your "before" system named as a saturated resource (§2).
- [ ] Little's law, the queueing knee, fan-out tail and Amdahl's law applied to your own system at least once each (§3–§4).
- [ ] Your peak-to-mean ratio, measured, and your peak utilization against the 70–80% guideline (§4.1).
- [ ] The single-database-fit calculation for your system, and the concession if it fits (§4.3).
- [ ] Availability composition for your critical path, with the shared failure causes that break independence (§5).
- [ ] The total-cost comparison including people and capacity steps; your unit cost and what drives it (§6).
- [ ] A delta table with normalization, measurement and confounders for every outcome you claim (§8).
- [ ] The strongest attribution evidence you have for each outcome (§9).
- [ ] `capacity_math.py` re-run with your own inputs, and the output kept with your dossier (§13).

---

## 17. References

- John D. C. Little, "A Proof for the Queuing Formula: L = λW", *Operations Research* 9(3):383–387, 1961. DOI 10.1287/opre.9.3.383 (verified via Crossref).
- Jeffrey Dean and Luiz André Barroso, "The Tail at Scale", *Communications of the ACM* 56(2):74–80, 2013. DOI 10.1145/2408776.2408794 (verified via Crossref).
- Brendan Gregg, "The USE Method". <https://www.brendangregg.com/usemethod.html>
- Google SRE Book, "Monitoring Distributed Systems" (the four golden signals). <https://sre.google/sre-book/monitoring-distributed-systems/>
- Google SRE Book, "Embracing Risk" (error budgets). <https://sre.google/sre-book/embracing-risk/>
- HdrHistogram (Gil Tene; coordinated omission). <http://hdrhistogram.org/>
- FinOps Foundation, FinOps Framework. <https://www.finops.org/framework/>
- Gene Amdahl, "Validity of the single processor approach to achieving large scale computing capabilities", AFIPS Spring Joint Computer Conference, 1967 (Amdahl's law).
