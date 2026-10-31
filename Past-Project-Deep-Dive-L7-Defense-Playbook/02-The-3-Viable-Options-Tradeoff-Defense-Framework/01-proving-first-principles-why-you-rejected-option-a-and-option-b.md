# 02.1 · Proving From First Principles Why You Rejected Option A and Option B

> **Folder:** `02-The-3-Viable-Options-Tradeoff-Defense-Framework` · file 1 of 3
> **Question this file answers:** when a Principal Engineer asks "why did you build a distributed pipeline when a single PostgreSQL instance or a cron job could handle this volume?", how do I prove, from requirements and arithmetic rather than taste, that the simpler options failed a real requirement? And how do I concede honestly where they didn't?
> **Running exhibits:** P-0 Beacon ([01.1 §3](../01-Anatomy-of-the-60-Minute-Deep-Dive-Round/01-minute-by-minute-whiteboard-pacing-strategy-from-context-to-internals.md#3-the-running-exhibit-p-0-beacon-fact-sheet)), plus previews of two Folder 03 composites:
> - **"Tidewater"** (Archetype A): an insurer's nightly batch replaced by a streaming pipeline.
> - **"Tillpoint"** (Archetype B): a commerce checkout and payments modernization.
> **Scope labels:** L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff.

| Listing | Language | What it does | Where it runs |
|---|---|---|---|
| L4 `options_matrix.py` | Python 3, standard library | Audits option tables. Applies kill criteria, computes weighted totals, and flags strawmen (dominated options), unchampioned options, matrices with no kill criteria or no concession, and a chosen option that isn't the top survivor. It also reports close calls: survivors within 10%, or a winner that flips under a ±2 weight change. | [§12](#12-the-options-matrix-tool), on the three matrices in this file |

**Verification.** The gate extracts the listing from this file and checks it byte for byte against the source that was run. It then re-runs the listing on this file and compares the result with the output block in §12; the tool's own verdict line must read OK. Every L5 telling must be flagged, and every L7 telling clean, by the Folder 01 lints ([`ownership_lint.py`](../01-Anatomy-of-the-60-Minute-Deep-Dive-Round/02-how-interviewers-test-if-you-were-the-architect-or-just-a-passenger.md#13-the-ownership-lint), [`constraint_check.py`](../01-Anatomy-of-the-60-Minute-Deep-Dive-Round/03-framing-constraints-legacy-tech-debt-client-politics-and-tight-deadlines.md#12-the-constraint-checker)). Results are in the [README](../README.md#gate-results).

---

## 0. Orientation

Folder 01 covered the clock, authorship and constraints. Folder 02 covers the core of an architecture defense: **the trade-off**. This file is about the *decision* (why the chosen option and not the other two). [02.2](02-quantifying-bottlenecks-before-and-after-latency-throughput-and-finops-math.md) is about the *numbers* that make the decision provable. [02.3](03-answering-what-would-you-redesign-today-with-hindsight.md) is about the *hindsight* question: whether the decision still holds.

The organizing idea is the **three viable options**:
- **The baseline:** the simplest thing that could work.
- **The default:** what your organization or the industry would reach for without thinking.
- **The chosen option:** what you built.

Behind all three sits **Option Zero**: do nothing, or fix what exists. A defense that names fewer than three real options, or whose rejected options were never real, fails at L6 and above, regardless of how good the chosen design is.

---

## 1. First principles: why three options, and why "why not simpler?" kills

### 1.1 Complexity has to pay rent

Experienced interviewers start from a prior that complexity is guilty until proven necessary. They have seen résumé-driven architecture (Kafka for 40 messages a minute, microservices for a 3-person team), and they have operated the results. Two widely cited essays capture the prior:
- Dan McKinley's "[Choose Boring Technology](https://mcfunley.com/choose-boring-technology)": every organization has a small budget of "innovation tokens", so spend them only where the problem demands it.
- Martin Fowler's "[MonolithFirst](https://martinfowler.com/bliki/MonolithFirst.html)": many successful microservice systems started as monoliths that were split once the boundaries were understood.

Amazon's Leadership Principles say the same in two words each: "Invent and Simplify", and "Frugality": "Constraints breed resourcefulness, self-sufficiency, and invention" ([LPs](https://www.amazon.jobs/content/en/our-workplace/leadership-principles)).

So when the interviewer asks "why not a single Postgres instance?", it isn't a trick question. It's the *default hypothesis*, and your design has to beat it with evidence. The evidence has three acceptable forms:
1. **A requirement the simple option fails, with a number.** "Freshness ≤ 30 minutes; a nightly batch is ~29.6 hours stale in the worst case."
2. **A failure the simple option causes, with history.** "A1: per-key writes with no staging reached every instance in 2 seconds."
3. **A cost the simple option hides, with math.** "14 teams sharing a 45-minute deploy train is a queue with utilization 3.15; it can't be stable."

### 1.2 Why exactly three options

| Number of options | What it signals | Interviewer's inference |
|---|---|---|
| 1 | No decision was made | "Passenger, or followed a default" |
| 2 | A false dichotomy ("microservices or the old monolith") | "Didn't explore the space; the second option is often a strawman" |
| **3** | **A real spectrum: baseline, default, chosen** | "Searched the space, including the boring end" |
| 5+ | A survey | "Can't prioritize; or padded the list to look thorough" |

Three works because each option tests something different:
- **The baseline** tests whether you were willing to be boring.
- **The default** tests whether you thought past what everyone else would do.
- **The chosen option** has to beat both on stated requirements.

**Option Zero** (keep the existing system, or fix it) goes in front of all three and is dismissed in a sentence when it truly fails. Otherwise it is a fourth real option (§5).

### 1.3 Requirements decide; preferences rank

Two kinds of criteria appear in every trade-off, and confusing them is the most common error in architecture defenses:

| | Kill criteria (requirements) | Scored criteria (preferences) |
|---|---|---|
| Nature | Pass/fail against a threshold | Better/worse on a scale |
| Source | An SLO, a regulation, a contract, an incident, a hard date | Cost, effort, familiarity, elegance |
| Example | "p95 freshness ≤ 30 min, from source commit to queryable" | "Operational cost" (weight 3) |
| Role in the decision | **Eliminates options** | **Ranks the survivors** |
| How interviewers attack it | "Was the threshold real? Who set it?" | "Why that weight? What if it were 2?" |

**A decision that rests only on scored criteria can be reversed by changing a weight,** and interviewers know that weights are usually chosen after the decision. A decision that rests on kill criteria can be reversed only by showing the requirement was wrong. That is a much harder attack, and one you can prepare for.

### 1.4 What the interviewers are testing

1. **The alternatives were real:** each had a champion, was described in as much detail as the chosen option, and was evaluated (ideally prototyped or load-tested).
2. **The kill criteria were real:** each traces to a source and has a number.
3. **You concede where the simple option wins:** on cost, on effort, sometimes even on throughput.
4. **You can re-derive the decision:** if a requirement changed, you know which option would win.

---

## 2. Anatomy of a viable option

Prepare every option, including the rejected ones, at the same level of detail:

| Field | What it holds | Beacon O1 (Postgres polling, rejected) |
|---|---|---|
| **Mechanism** | How it would work, concretely | 48,000 instances poll a replica every 10 s for their namespaces' current rows |
| **What it is best at** | The requirement it satisfies better than the chosen option | Lowest operational cost; no new tier; familiar to every team |
| **Kill criterion it fails** | The requirement, the threshold, the evidence | No atomic multi-key snapshot and no ring pointer, so G1 (≤ 1% blast radius) can't be met without rebuilding snapshots in every client |
| **Cost** | Build, run, people | ~2 engineer-months to build; ~0.1 engineer to run |
| **Champion** | Who argued for it, by role | The platform architect |
| **Evidence** | What you measured | Load test: one replica served 12,000 QPS of the point read |
| **What you kept** | The part of it that survived into the chosen design | Postgres stays the source of truth |
| **Revisit trigger** | When it would become the right answer | If staged rollout weren't required (for example, a single-region, single-team deployment) |

**The "what it is best at" field is the steelman.** If you can't say what a rejected option is best at, you didn't really consider it, and the interviewer will notice.

---

## 3. Kill criteria versus weighted scoring

### 3.1 Why weighted matrices draw fire

A weighted decision matrix looks rigorous, but most are reverse-engineered: the author knows the answer, then chooses criteria and weights that produce it. Interviewers test this by changing a weight ("what if operational cost mattered more?") or adding a criterion ("you didn't include on-call burden"). If the winner flips, the matrix was decoration.

### 3.2 Writing a kill criterion

A kill criterion has four parts:

| Part | Weak | Strong |
|---|---|---|
| **Property** | "Fast enough" | "Freshness: source commit to queryable in the warehouse" |
| **Threshold** | — | "p95 ≤ 30 min" |
| **Measurement** | — | "Measured by a heartbeat row written to the source every minute and read from the warehouse" |
| **Source** | "The business wanted real-time" | "The claims-triage team's SLA to the regulator for first-notice-of-loss acknowledgement; signed off by their director" |

### 3.3 Trace every kill criterion to a source

| Source type | Example | Strength |
|---|---|---|
| Regulation or contract | PCI change control; a data-residency clause | Strongest: someone else's hard constraint |
| SLO with error budget | 99.9% availability for checkout | Strong if the SLO is enforced |
| Incident history | A1: global propagation in 2 s caused a Sev-1 | Strong: a demonstrated failure |
| Hard date | The colo lease ends at M9 | Strong if priced (01.3 §5.1) |
| Stakeholder request | "The fraud team wants real-time" | **Weak until quantified:** what latency, for what decision, at what cost? |
| Your own preference | "Streaming is the modern approach" | Not a kill criterion |

### 3.4 Use scores only for the survivors, and report sensitivity

Once the kill criteria eliminate options, score the survivors on preferences. Then report **how robust the ranking is**. If a ±2 change in any one weight flips the winner, say so: "this was a close call, and the tie-breaker was X". Admitting a close call is a strength. It shows you know which parts of your decision rest on judgment, and it pre-empts the weight attack.

---

## 4. The "why not simpler?" defense: five legitimate reasons for complexity

There are only a handful of legitimate reasons to choose a more complex architecture over a simpler one. Each comes with the math an interviewer expects. 02.2 holds the formulas, and `capacity_math.py` there computes every number quoted below.

### 4.1 Throughput spikes and batch windows

**The claim:** "The simple option fits the mean but not the peak, or not next year's volume."

**The math the interviewer expects:**
- **Peak-to-mean ratio, measured:** not "traffic is spiky", but "Black Friday peak was 8× the November mean".
- **Headroom at peak:** utilization = peak demand ÷ measured capacity. Above ~70–80%, queueing delay grows sharply (02.2 §3.2).
- **For batch:** processing time = records ÷ rate, compared with the window, with growth projected.

**Tidewater (Archetype A) worked example.** The nightly job processes 180M records at 9,000 records/s, which takes 5.56 h of a 6 h window. At 35% annual growth, the window overflows in about **3.1 months**. Separately, a nightly batch's worst-case freshness is about **29.6 h**, against a 30-minute requirement from claims triage.

**The honest test.** Would a *better* batch pass? A 15-minute micro-batch using the same code passes the freshness requirement and fits the window comfortably. It's a real option, and §8.3 shows it nearly tied with streaming. The cron job doesn't lose because cron is bad. It loses because a 24-hour cadence can't meet a 30-minute requirement.

#### How an L5 tells it

> A cron job just wouldn't scale for us. The data volumes were huge and growing really fast, so we needed a streaming architecture to handle it. Batch is kind of outdated for this sort of thing anyway.

#### How an L7 tells it

> The cron job failed 2 requirements with numbers. The window: 180 million records a night at 9,000 records per second is 5.6 hours of a 6-hour window, and at 35% annual growth it would overflow in about 3 months. Freshness: claims triage needed new claims queryable within 30 minutes at p95, and a nightly batch is up to 29.6 hours stale. Neither requirement needs streaming, though. A 15-minute micro-batch running the same Beam code met both, and on my matrix it tied with streaming. I chose streaming on a tie-breaker I can defend separately, and I'd have accepted the micro-batch.

### 4.2 Blast-radius isolation

**The claim:** "The simple option puts too much of the system in one failure domain."

**The math.** Expected impact = P(bad event) × fraction exposed × (time to detect + time to mitigate). A useful single number is **exposure in instance-minutes** (or user-minutes): fraction exposed × fleet size × duration.

**Beacon worked example.**
- **Before**, INC-A1: 100% of 48,000 instances × 38 min = **1,824,000 instance-minutes**.
- **After**, worst ring0 halt: 1.1% × 48,000 = 528 instances × 4 min = **2,112 instance-minutes**.
- That is an exposure reduction of about **860×** for the same class of bad change.

That ratio is the defense of the rollout controller, the relay tier and the snapshot protocol. None of them exists for throughput. They exist to shrink the second and third terms of that product.

**The honest test.** Could the simple option be staged? Yes, partially: Postgres polling could support staging if every client implemented ring membership and snapshot assembly. That's the point O1 loses on. The staging logic would be reimplemented in 4 languages instead of once in a controller. Public writing on isolation techniques is a useful reference for this argument, for example AWS's Builders' Library on shuffle sharding ([Workload isolation using shuffle-sharding](https://aws.amazon.com/builders-library/workload-isolation-using-shuffle-sharding/)).

#### How an L5 tells it

> With the old system any change could take down everything, so we needed better isolation. The new architecture is much more robust because changes go out gradually and we can roll back quickly.

#### How an L7 tells it

> I measured blast radius as exposure: fraction of the fleet affected times duration. A1 exposed all 48,000 instances for 38 minutes, about 1.8 million instance-minutes. The worst bad change after launch exposed 528 instances in the canary ring for 4 minutes, about 2,100 instance-minutes, roughly 860 times less. Every complex part of the design is there to shrink one factor of that product: the ring pointer shrinks the fraction, and the health gates shrink the duration. None of it is there for throughput, and I say that up front, because a single replica handled our read load.

### 4.3 SLA and availability guarantees

**The claim:** "The simple option can't meet the SLO."

**Watch the trap.** Adding services usually *lowers* availability, because serial dependencies multiply. Five serial dependencies at 99.95% each give 0.9995⁵ = **99.75%**, below a 99.9% target before your own code fails once. The legitimate availability argument for a more distributed design is almost always **shortening the critical path**: moving dependencies off the synchronous path (asynchronous queues, caches, fail-static reads) or adding *independent* redundancy. It is never "we have more services, so it's more available".

**The math.**
- Serial availability = ∏ aᵢ.
- Parallel redundancy = 1 − ∏(1 − aᵢ), valid *only* if the failures are independent.
- Error budget = (1 − SLO) × period: 99.9% over 30 days is **43.2 minutes**; 99.95% is **21.6 minutes**.

**Tillpoint (Archetype B) preview.** Checkout's synchronous path had 5 dependencies. The modernization moved 3 of them (notification, loyalty, analytics) behind an outbox, leaving 2 synchronous ones (payment authorization, inventory reservation). Two serial dependencies at 99.95% compose to about 99.90% before checkout's own failures, compared with 99.75% for five. That is the availability argument, and it comes from *removing* synchronous calls, not from adding services.

### 4.4 Regulatory boundaries

**The claim:** "The simple option puts too much of the system inside a regulated scope."

**The math is scope cost.** Every system inside a compliance scope carries recurring cost: audits, evidence collection, change control, access reviews, hardening. Segmentation that shrinks the scope is one of the most common legitimate reasons for a service boundary. The PCI Security Standards Council publishes scoping and segmentation guidance in its document library ([PCI SSC](https://www.pcisecuritystandards.org/document_library/)).

**Tillpoint example (composite numbers).** In the monolith, card data passed through the order service, so all 140 hosts in the order cluster were in PCI scope. A tokenization service took the card at the edge and returned a token, which reduced the in-scope footprint to 12 hosts. At a placeholder cost of ~$1,800 per in-scope host per year in audit and evidence work, that is about $230k a year. More important, it took 13 teams' change processes out of PCI change control. The service boundary is justified by a regulatory boundary, and the throughput of the tokenization service is irrelevant to the argument.

**Data residency is the other common case.** If a contract or regulation requires that certain data stay in a region, the architecture needs a regional boundary that a single global database can't provide. Name the clause and the data class, not "GDPR" in general.

### 4.5 Multi-team velocity

**The claim:** "The simple option makes teams wait on each other."

**This is the most abused justification,** so it needs the most rigorous math. Model a shared release train as a queue:
- Demand = teams × deploys per team per day.
- Capacity = working minutes ÷ minutes per deploy.
- Utilization ρ = demand ÷ capacity. If ρ ≥ 1, the queue grows without bound and teams are forced to batch changes. If ρ < 1, the mean wait is ρ/(1 − ρ) × deploy time (M/M/1).

**Tillpoint worked example.**
- **Today:** 14 teams × 3 deploys a day = 42 requested deploys, against a 45-minute serialized train in a 600-minute day = 13.3 deploys of capacity. ρ = **3.15**, so changes are forced into batches of about 3. Each batch makes rollback attribution harder and failures larger.
- **Fixing the pipeline first** (45 → 12 minutes): capacity becomes 50/day, ρ = 0.84, and the mean wait is still **~63 minutes**. Better, and an honest Option Zero, but it doesn't remove the coupling.
- **Coordination:** 14 teams have 14 × 13 / 2 = **91** pairwise coordination paths. Conway's observation that systems mirror their organizations' communication structures ([Conway's Law](https://www.melconway.com/Home/Conways_Law.html)) is the reason independent deployability matters at this team count.

**The honest test.** Does the velocity argument require *microservices*, or only *independent deployment units*? A modular monolith with per-module deploy pipelines, or a monorepo with independent artifacts, may solve it with less operational cost. If you chose services, you need a second reason (§4.2–§4.4) that a modular monolith doesn't satisfy.

#### How an L5 tells it

> The monolith was slowing everyone down, so we decided to break it into microservices. With microservices each team can move independently, which is basically best practice for an organization of our size.

#### How an L7 tells it

> I modeled the release train as a queue. 14 teams wanted about 42 deploys a day, and a 45-minute serialized train fits 13 in a working day, so utilization was 3.15: teams were batching 3 changes per deploy and bisecting every rollback. My first proposal was the cheap fix, cutting the pipeline to 12 minutes, and at 0.84 utilization the mean wait was still about 63 minutes. That showed the problem was coupling, not pipeline speed. Even so, independent deployment alone pointed to a modular monolith, not services. What pushed checkout and payments into separate services was the PCI boundary: tokenization at the edge took 128 of 140 hosts out of scope.

### 4.6 The honest concession: when the simple option fits

Sometimes the math says the simple option *would* have worked on the dimension the interviewer is attacking. **Say so immediately.** Tillpoint's order writes peak at 2,400 orders/s × 6 rows = 14,400 rows/s, against a measured single-primary capacity of 40,000 rows/s: **36% utilization at peak**. Throughput isn't the reason to split, and claiming it is would collapse under one derivation probe.

#### How an L5 tells it

> A single Postgres would never have handled our peak traffic. On Black Friday we had a massive spike, so we needed to shard the data across services to scale.

#### How an L7 tells it

> On throughput alone, a single Postgres primary would have been fine, and I want to be clear about that. Peak was 2,400 orders a second at 6 rows each, about 14,400 rows a second, and the primary we load-tested sustained 40,000, so peak utilization was about 36%. The split came from 2 other requirements: the PCI boundary took 128 of 140 hosts out of scope, and the deploy-train math showed 14 teams queued behind 1 release. If neither had existed, I'd have kept the single primary and partitioned the 2 hot tables.

**Why the concession is strong.** It takes away the interviewer's best attack before they make it. It shows you ran the numbers against your own design. And it moves the debate to ground you have prepared (§4.4, §4.5).

---

## 5. Option Zero: do nothing, or fix what exists

Every option list starts with the status quo, for two reasons. It's often a real option, and dismissing it without analysis is the clearest sign of a solution looking for a problem.

**The cost of doing nothing:**
- Incident cost per year.
- Toil.
- Growth that breaks the current system.
- Opportunity cost: what the current system prevents.

**Beacon's Option Zero:** fix the 4 ZooKeeper client libraries and put a staging publisher in front of the ensemble. 01.3 Q3 concedes that this would have addressed A1, and that the colo exit was what removed it. **Tidewater's Option Zero:** buy more warehouse-appliance capacity. That fixes the window (about $38k/month more, 02.2 §6) but not freshness, which is a kill criterion.

| Option Zero question | Beacon answer |
|---|---|
| What does doing nothing cost per year? | 2 Sev-1s (~90 min of customer impact), ~11 pages/month, and a colo lease that must be extended at ~$190k/month |
| Could the existing system be fixed? | Partly: client fixes + a staging layer would address A1 and A2 |
| What would still fail after the fix? | The colo exit (a hard date) and the single-region ensemble |
| So is Option Zero dead? | Dead because of the date, not because of the design. Say exactly that. |

---

## 6. Deriving the choice from first principles

The strongest form of trade-off defense is a **derivation**: requirements → invariants → mechanisms → the option that provides the mechanisms most cheaply. A derivation is hard to attack, because every step can be checked.

**Tidewater: deriving the sink design.**

| Step | Statement | Why it follows |
|---|---|---|
| R1 | Claims counts in the warehouse must equal source counts (regulatory reporting) | Requirement, from the reporting team's audit |
| I1 | Each source event must have exactly one effect in the warehouse | From R1: duplicates or losses break the counts |
| F1 | The transport (CDC → Kafka) is at-least-once | Fact: retries and redelivery produce duplicates |
| M1 | Therefore the pipeline needs idempotency: a stable event key and either transactional sink writes or deduplication | From I1 + F1: at-least-once delivery + idempotent effect = exactly-once effect |
| M2 | Dedup state needs a bounded horizon, or it grows forever | Resource bound: state must expire |
| M3 | The horizon must exceed the maximum redelivery delay | From M2 + F1: a duplicate arriving after expiry would be counted twice |
| C1 | Reconciliation (control totals per partition per day) proves I1 independently | Defense in depth: measure the invariant, don't assume it |

Every row can be challenged, and every challenge has an answer that is part of the design. Folder 03's Archetype A blueprint develops this derivation and runs it as real Beam code.

**The derivation pattern generalizes.**
- **For a cache:** requirement (p99 ≤ 1 ms) → invariant (no network on the hot path) → mechanism (in-process cache plus invalidation) → option.
- **For a saga:** requirement (no double charge) → invariant (an idempotent charge per order) → mechanism (idempotency key + outbox) → option.

---

## 7. Strawmen and steelmen

### 7.1 How interviewers detect a strawman

| Sign | Example | Detection probe |
|---|---|---|
| **Dominated** | The rejected option loses on every criterion | "Was there anything it was better at?" |
| **Unchampioned** | Nobody argued for it | "Who wanted this one?" |
| **Thin** | Described in one line while the chosen option gets ten | "Walk me through how option A would have worked" |
| **Never tested** | No prototype, load test or spike | "What did you measure?" |
| **Anachronistic** | An option nobody would consider today (FTP drops, XML-RPC) | "What would a reasonable team have done instead?" |

### 7.2 Steelmanning: present each rejected option at its strongest

A steelman states the rejected option the way its champion would, including the situations in which it would be *right*.

#### How an L5 tells it

> We looked at using the service mesh, but that would have been way too complex and it wasn't really designed for config. Our approach was a lot cleaner, so the team went with relays.

#### How an L7 tells it

> The strongest alternative was the SRE lead's: deliver config over the service mesh's xDS control plane. At its best it adds 0 new tiers, reuses streams that already reach every sidecar, and gets push semantics for free; for a fleet at 100% sidecar coverage I think it beats my design. It failed 2 of 3 exit criteria in a 1-week prototype: coverage was 82%, so 18% of instances would need a second path, and config pushes would have shipped on the mesh's release train. At 97% coverage today, I would re-run that prototype.

---

## 8. Worked matrices

Each matrix below uses the notation `options_matrix.py` reads (§12): a `KILL` weight for requirements, 1–5 weights for preferences, and `Champion` and `Chosen` metadata rows.

### 8.1 A matrix that fails (typical L5 preparation)

<!-- options:start name=l5-matrix -->
| Criterion | Weight | Kafka + microservices | Monolith | Cron job |
|---|---|---|---|---|
| Scalability | 5 | 5 | 2 | 1 |
| Reliability | 4 | 5 | 2 | 2 |
| Modern stack | 3 | 5 | 1 | 1 |
| Team excitement | 2 | 5 | 1 | 1 |
| Champion | - | me | - | - |
| Chosen | - | yes | - | - |
<!-- options:end -->

Every defect in it maps to an interviewer probe:
- **No kill criteria:** "which requirement did the monolith fail?"
- **Both alternatives dominated:** "was the cron job better at *anything*?"
- **Neither alternative has a champion:** "who proposed the monolith?"
- **The chosen option wins every row:** "what did Kafka cost you?"
- **The criteria themselves are unfalsifiable** ("scalability", "modern stack", "team excitement").

### 8.2 Beacon: distribution mechanism

<!-- options:start name=beacon-distribution -->
| Criterion | Weight | O1 Postgres polling | O2 Mesh xDS | O3 Relay tier + snapshots |
|---|---|---|---|---|
| Atomic multi-key snapshot + ring pointer (G1) | KILL | fail: per-row reads, no ring pointer | pass | pass |
| Reaches at least 95% of instances at launch | KILL | pass | fail: 82% sidecar coverage | pass |
| Reads survive a control-plane outage (G3) | KILL | pass: clients keep LKG | pass | pass |
| Operational cost | 3 | 5 | 4 | 2 |
| Implementation effort | 3 | 4 | 3 | 2 |
| Propagation latency | 2 | 3 | 5 | 4 |
| Blast-radius control | 4 | 2 | 3 | 5 |
| Independence from other release trains | 3 | 3 | 1 | 5 |
| Champion | - | platform architect | SRE lead | me (tech lead) |
| Chosen | - | - | - | yes |
<!-- options:end -->

**Reading it.** Two kill criteria decide this matrix, and each eliminates one alternative. The scored rows then *concede* what the chosen option costs: O3 is the most expensive to build and operate (scores 2 and 2). That concession is what makes the matrix credible.

### 8.3 Tidewater: freshness pipeline (a close call)

<!-- options:start name=tidewater-freshness -->
| Criterion | Weight | B1 Nightly batch (status quo) | B2 15-minute micro-batch | B3 Streaming (Dataflow) |
|---|---|---|---|---|
| p95 freshness at most 30 min (claims triage) | KILL | fail: up to 29.6 h stale | pass: ~22 min p95 | pass: ~3 min p95 |
| Fits the processing window at 2x volume | KILL | fail: overflows in ~3 months | pass | pass |
| Monthly cost | 3 | 5 | 4 | 2 |
| Operational complexity | 3 | 4 | 4 | 2 |
| Freshness margin | 3 | 1 | 3 | 5 |
| Late and out-of-order data handling | 2 | 3 | 2 | 5 |
| Same code for backfill | 2 | 2 | 4 | 4 |
| Champion | - | warehouse team | data platform lead | me (tech lead) |
| Chosen | - | - | - | yes |
<!-- options:end -->

**Reading it.** The micro-batch and streaming options both survive, and they tie on score. The tool reports it as a close call, and the honest defense names the tie-breaker:

#### How an L5 tells it

> We evaluated micro-batch but streaming was obviously the better architecture, since it's real-time and more scalable. Micro-batching is sort of a halfway solution.

#### How an L7 tells it

> On my matrix, the 15-minute micro-batch and streaming tied at 45 points, and a 1-point change in the cost weight flips it to micro-batch, so I treat it as a close call, not a clear win. The tie-breaker was a requirement that wasn't yet committed: the fraud team's roadmap needed claim events within 5 minutes 2 quarters later, which micro-batch can't reach with 15-minute scheduling plus about 6 minutes of run time. I chose streaming, and I wrote down that if the fraud requirement were dropped, micro-batch would be the right call and the Beam code would move across with a runner flag. The fraud team shipped on it in month 8, so the bet paid, but it was a bet.

**Why "it was a bet" is the right closing.** It separates decision quality from outcome quality. 02.3 builds on that distinction.

---

## 9. Presenting the options on the whiteboard

**Layout.** Three columns, one per option, with the rows in this order:
1. **Kill criteria at the top,** each cell ✓ or ✗ with its number.
2. **Preferences,** with the scores.
3. **The champion,** by role.
4. **"Kept" at the bottom:** the part of each rejected option that survived.

```text
              | O1 Postgres poll  | O2 Mesh xDS        | O3 Relays+snapshots *
 -------------+-------------------+--------------------+----------------------
 K: atomic    |  X  per-row reads |  ok                |  ok
 K: 95% reach |  ok               |  X  82% sidecars   |  ok
 K: fail-     |  ok (LKG)         |  ok                |  ok
    static    |                   |                    |
 cost / effort|  5 / 4  (best)    |  4 / 3             |  2 / 2  (worst)
 blast radius |  2                |  3                 |  5
 champion     |  platform arch    |  SRE lead          |  me
 KEPT         |  PG = source of   |  mesh identities   |  -
              |  truth            |  for relay auth    |
```

**The 90-second verbal pattern:**
1. "Three options, plus doing nothing."
2. One sentence per option: the mechanism and its champion.
3. "Two hard requirements decided it." Name each, with its number and which option it eliminated.
4. "On preferences the winner is the *worst* on cost and effort, and here's why I paid that."
5. "From each loser I kept X."
6. "It would flip if Y."

---

## 10. Company lenses (⚠ inference from public material)

- **Amazon.** "Invent and Simplify" and "Frugality" are public principles, so expect the "why not simpler?" attack early. The concession (§4.6) reads as Frugality, and the derivation (§6) as "Are Right, A Lot", which includes working "to disconfirm their beliefs".
- **Google.** Written feedback for reviewers who weren't in the room rewards matrices with numbers: "rejected Postgres polling despite a 12k QPS load test, on atomicity and staging" is a quotable sentence.
- **Netflix.** "Farming for dissent" ([culture](https://jobs.netflix.com/culture)): expect "who argued for option A?" and credit for having sought out the champion.
- **NVIDIA, Uber, Apple.** Expect the trade-off attack to go to the domain's hard constraint: performance-per-watt or memory bandwidth (NVIDIA), peak-event behavior across regions (Uber), device and hardware schedule (Apple). Prepare kill criteria in those units.

---

## 11. Hiring-committee scoring rubric: trade-off defense

Bands follow the poor / borderline / solid / outstanding vocabulary of Google's public structured-interviewing guidance ([re:Work](https://rework.withgoogle.com/intl/en/guides/a-guide-to-structured-interviewing-for-better-hiring-practices)). The anchors are a composite (⚠).

| Dimension | Poor | Borderline | Solid (L6) | Outstanding (L7) |
|---|---|---|---|---|
| **Alternatives** | One option, or strawmen | Two options, one weak | Three real options with champions | Three plus Option Zero; each steelmanned, with what was kept from it |
| **Decision basis** | Taste ("modern", "scalable") | Weighted scores only | Kill criteria with numbers and sources | Kill criteria plus sensitivity; close calls named with their tie-breaker |
| **"Why not simpler?"** | Claims a scale that isn't there | Generic ("it wouldn't scale") | Names the failing requirement with a number | Concedes where simple wins, then defends on the real requirement |
| **Derivation** | None | Partial | Requirements → mechanisms | Requirements → invariants → mechanisms → option, every step checkable |
| **Re-derivation** | Can't say what would change the decision | Vague | Names the trigger | Names the trigger and which option would win, and why |

---

## 12. The options matrix tool

### 12.1 Listing L4: `options_matrix.py`

<!-- listing:options_matrix.py -->
```python
#!/usr/bin/env python3
"""options_matrix.py - audit a "three viable options" decision matrix.

Reads every table between
    <!-- options:start name=<label> -->  ...  <!-- options:end -->
Columns: Criterion | Weight | <option 1> | <option 2> | ...
Row kinds, by the Weight cell:
    1..5     scored criterion; option cells are integers 1..5 (5 = best)
    KILL     hard requirement; option cells start with "pass" or "fail"
    -        metadata row: "Champion" (who argued for it) or "Chosen" ("yes")

Flags (structural defects an interviewer will find):
    NO-KILL-CRITERIA   the decision rests only on adjustable weights
    CHOSEN-FAILS-KILL  the chosen option violates a hard requirement
    CHOSEN-NOT-TOP     a surviving option strictly outscores the chosen one
    STRAWMAN?          an option is dominated on every scored criterion
    NO-CONCESSION      the chosen option is never worse on any criterion
    UNCHAMPIONED       a rejected option that nobody argued for
Notes (not defects, but say them out loud):
    CLOSE-CALL         survivors within 10%, or a +/-1..2 change to one weight
                       flips the winner: name your tie-breaker

Matrices named l5-* are negative examples and are expected to raise flags.
Usage: python -I options_matrix.py <file.md>
"""
import re
import sys

START = re.compile(r"<!-- options:start name=(\S+) -->\n(.*?)<!-- options:end -->", re.S)


def parse(block):
    rows = [r for r in block.splitlines() if r.strip().startswith("|")]
    cells = [[c.strip() for c in r.strip().strip("|").split("|")] for r in rows]
    header, body = cells[0], cells[2:]
    opts = header[2:]
    scored, kills, meta = [], [], {}
    for row in body:
        crit, weight, vals = re.sub(r"[*_`]", "", row[0]), row[1], row[2:]
        if weight.upper() == "KILL":
            kills.append((crit, [v.lower().startswith("pass") for v in vals], vals))
        elif re.fullmatch(r"\d+", weight):
            scored.append((crit, int(weight), [int(re.match(r"\d+", v).group(0)) for v in vals]))
        else:
            meta[crit.lower()] = vals
    return opts, scored, kills, meta


def totals(opts, scored, weights=None):
    w = weights or [s[1] for s in scored]
    return [sum(wi * s[2][i] for wi, s in zip(w, scored)) for i in range(len(opts))]


def audit(name, opts, scored, kills, meta):
    flags, notes = [], []
    n = len(opts)
    chosen = [i for i, v in enumerate(meta.get("chosen", [""] * n)) if v.lower().startswith("yes")]
    ci = chosen[0] if chosen else None
    survive = [all(k[1][i] for k in kills) for i in range(n)]
    tot = totals(opts, scored)
    if not kills:
        flags.append("NO-KILL-CRITERIA: no hard requirement separates the options; weights alone decide")
    if ci is not None and not survive[ci]:
        flags.append(f"CHOSEN-FAILS-KILL: '{opts[ci]}' fails a hard requirement")
    surv_idx = [i for i in range(n) if survive[i]]
    if ci is not None and surv_idx and max(tot[i] for i in surv_idx) > tot[ci] and survive[ci]:
        top = max(surv_idx, key=lambda i: tot[i])
        flags.append(f"CHOSEN-NOT-TOP: survivor '{opts[top]}' scores {tot[top]} vs chosen {tot[ci]}")
    for a in range(n):
        for b in range(n):
            if a == b:
                continue
            ge = all(s[2][b] >= s[2][a] for s in scored)
            gt = any(s[2][b] > s[2][a] for s in scored)
            kill_ok = all(k[1][b] or not k[1][a] for k in kills)
            if scored and ge and gt and kill_ok:
                flags.append(f"STRAWMAN?: '{opts[a]}' is dominated by '{opts[b]}' on every criterion")
                break
    if ci is not None and scored and all(s[2][ci] >= max(s[2]) for s in scored):
        flags.append(f"NO-CONCESSION: '{opts[ci]}' is never worse on any criterion; real alternatives cost something")
    champs = meta.get("champion", [""] * n)
    for i in range(n):
        if i != ci and re.sub(r"[-—\s]", "", champs[i] if i < len(champs) else "") == "":
            flags.append(f"UNCHAMPIONED: nobody argued for '{opts[i]}'")
    if len(surv_idx) >= 2:
        ranked = sorted(surv_idx, key=lambda i: -tot[i])
        best, second = ranked[0], ranked[1]
        if tot[best] and (tot[best] - tot[second]) <= 0.10 * tot[best]:
            notes.append(f"CLOSE-CALL: survivors '{opts[best]}' {tot[best]} and '{opts[second]}' {tot[second]} are within 10%")
        base = [s[1] for s in scored]
        for j, s in enumerate(scored):
            for d in (-2, -1, 1, 2):
                w = list(base)
                w[j] = max(0, w[j] + d)
                t = totals(opts, scored, w)
                win = max(surv_idx, key=lambda i: (t[i], i == ci))
                if win != (ci if ci in surv_idx else best):
                    notes.append(f"CLOSE-CALL: weight of '{s[0]}' {base[j]}->{w[j]} makes '{opts[win]}' the winner")
                    break
    return tot, survive, ci, flags, notes


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    md = open(sys.argv[1], encoding="utf-8").read().replace("\r\n", "\n")
    ok = True
    blocks = START.findall(md)
    print(f"options_matrix: {len(blocks)} matrix(es)")
    for name, block in blocks:
        opts, scored, kills, meta = parse(block)
        tot, survive, ci, flags, notes = audit(name, opts, scored, kills, meta)
        print()
        print(f"matrix {name}: {len(opts)} options, {len(kills)} kill criteria, {len(scored)} scored criteria")
        for i, o in enumerate(opts):
            mark = " (chosen)" if i == ci else ""
            print(f"  {o[:34]:<34} total {tot[i]:>3}  {'survives' if survive[i] else 'killed  '}{mark}")
        for k in kills:
            failed = [opts[i][:20] for i, p in enumerate(k[1]) if not p]
            print(f"  kill '{k[0][:48]}': fails -> {', '.join(failed) if failed else 'none'}")
        for f in flags:
            print(f"  FLAG {f}")
        for x in notes:
            print(f"  note {x}")
        if not flags:
            print("  no structural flags")
        expect_flags = name.startswith("l5")
        ok &= bool(flags) == expect_flags
    print()
    print("verdict:", "OK (l5-* matrices flagged, all others clean)" if ok else "CHECK (unexpected flags or a clean l5-* matrix)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

### 12.2 Output on this file's three matrices

<!-- output:options_matrix.py -->
```text
options_matrix: 3 matrix(es)

matrix l5-matrix: 3 options, 0 kill criteria, 4 scored criteria
  Kafka + microservices              total  70  survives (chosen)
  Monolith                           total  23  survives
  Cron job                           total  18  survives
  FLAG NO-KILL-CRITERIA: no hard requirement separates the options; weights alone decide
  FLAG STRAWMAN?: 'Monolith' is dominated by 'Kafka + microservices' on every criterion
  FLAG STRAWMAN?: 'Cron job' is dominated by 'Kafka + microservices' on every criterion
  FLAG NO-CONCESSION: 'Kafka + microservices' is never worse on any criterion; real alternatives cost something
  FLAG UNCHAMPIONED: nobody argued for 'Monolith'
  FLAG UNCHAMPIONED: nobody argued for 'Cron job'

matrix beacon-distribution: 3 options, 3 kill criteria, 5 scored criteria
  O1 Postgres polling                total  50  killed  
  O2 Mesh xDS                        total  46  killed  
  O3 Relay tier + snapshots          total  55  survives (chosen)
  kill 'Atomic multi-key snapshot + ring pointer (G1)': fails -> O1 Postgres polling
  kill 'Reaches at least 95% of instances at launch': fails -> O2 Mesh xDS
  kill 'Reads survive a control-plane outage (G3)': fails -> none
  no structural flags

matrix tidewater-freshness: 3 options, 2 kill criteria, 5 scored criteria
  B1 Nightly batch (status quo)      total  40  killed  
  B2 15-minute micro-batch           total  45  survives
  B3 Streaming (Dataflow)            total  45  survives (chosen)
  kill 'p95 freshness at most 30 min (claims triage)': fails -> B1 Nightly batch (st
  kill 'Fits the processing window at 2x volume': fails -> B1 Nightly batch (st
  note CLOSE-CALL: survivors 'B2 15-minute micro-batch' 45 and 'B3 Streaming (Dataflow)' 45 are within 10%
  note CLOSE-CALL: weight of 'Monthly cost' 3->4 makes 'B2 15-minute micro-batch' the winner
  note CLOSE-CALL: weight of 'Operational complexity' 3->4 makes 'B2 15-minute micro-batch' the winner
  note CLOSE-CALL: weight of 'Freshness margin' 3->1 makes 'B2 15-minute micro-batch' the winner
  note CLOSE-CALL: weight of 'Late and out-of-order data handling' 2->0 makes 'B2 15-minute micro-batch' the winner
  no structural flags

verdict: OK (l5-* matrices flagged, all others clean)
```

**Reading the output.**
- **`l5-matrix` raises every structural flag:** no kill criteria, two strawmen, two unchampioned options, and no concession.
- **`beacon-distribution` is clean.** Each kill criterion eliminates exactly one alternative, and the chosen option concedes cost and effort.
- **`tidewater-freshness` is clean but reports close calls.** The tool says what §8.3's L7 telling says: the decision rests on a tie-breaker, and you should name it before the interviewer finds it.

---

## 13. Failure modes

| # | Failure mode | Symptom | Fix |
|---|---|---|---|
| F1 | **Invented scale** | "It wouldn't scale" with no number | Run the S6-style fit; concede if it fits (§4.6) |
| F2 | **Strawman alternatives** | Rejected options lose on everything | Steelman; the "best at" field (§2) |
| F3 | **No Option Zero** | Never asked whether to fix the existing system | §5 table |
| F4 | **Weights as justification** | "It scored 87 vs 62" | Kill criteria decide; scores only rank (§1.3) |
| F5 | **Unsourced kill criteria** | "The business wanted real-time" | Threshold, measurement, source (§3.2) |
| F6 | **The availability fallacy** | "More services, more resilient" | Serial dependencies multiply; argue the shorter critical path (§4.3) |
| F7 | **The velocity fallacy** | "Microservices let teams move independently" | Deploy-queue math; consider the modular monolith (§4.5) |
| F8 | **Hiding the close call** | Presents a tie as a clear win | Name the tie-breaker (§8.3) |
| F9 | **Outcome as proof** | "It worked, so it was right" | Separate the decision from the outcome (02.3) |
| F10 | **Unchampioned options** | "We considered X" (nobody proposed it) | Name the champion by role |
| F11 | **Nothing kept** | Losers fully discarded | Name what survived from each |

---

## 14. Bar-raiser chains

<details><summary><b>Q1 · "A cron job and a single Postgres instance could handle this. Why didn't you use them?"</b></summary>

**Initial Prompt.** The classic opener, on Tidewater: "180 million records a night. A cron job and a well-tuned Postgres could do that. Why a streaming pipeline?"

**L5 Answer.** "Because batch doesn't scale, and the business needed real-time data. Streaming is the modern way to build data pipelines."

**Why L5 Stalls.** Both claims are refutable: 180M records a night is well within batch capability, and "real-time" is undefined. The interviewer will now probe every scale claim the candidate makes, and the candidate has no numbers to stand on.

**L7 Answer.** "Two parts. On volume you're right: 180 million a night is 5.6 hours at our measured 9,000 records a second, and a better-provisioned batch would handle it. Volume alone would have meant buying capacity or optimizing the job. The kill criterion was freshness. Claims triage committed to their regulator to acknowledge first notice of loss within a window that required new claims to be queryable within 30 minutes at p95, and a nightly batch is up to about 29.6 hours stale. That killed the cron job, not the volume. It didn't kill batch, though: a 15-minute micro-batch met it, and it tied with streaming on my matrix. Streaming won on a tie-breaker, the fraud team's 5-minute requirement 2 quarters out. I'd defend the choice as a judgment call, not as an inevitability."

</details>

<details><summary><b>Q2 · "Your matrix has your design winning on everything. Convince me it isn't rigged."</b></summary>

**Initial Prompt.** The interviewer looks at a matrix the candidate drew: "Your option wins every row. Why should I believe this wasn't reverse-engineered?"

**L5 Answer.** "Because we evaluated everything carefully, and our design really was the best on all the criteria."

**Why L5 Stalls.** A real alternative is better at *something*, almost by definition; otherwise nobody would have proposed it. "Best on all criteria" is the signature of a matrix built after the decision.

**L7 Answer.** "If mine said that, you'd be right to distrust it. Beacon's doesn't: my option is the worst on operational cost and implementation effort. Postgres polling beats it on both. Two hard requirements decided it, not the weights. The polling design has no atomic multi-key snapshot or ring pointer, so it can't meet the 1% blast-radius goal without rebuilding snapshots in 4 client libraries. The mesh option reached only 82% of instances. Change any weight you like and those two eliminations don't move. Where the decision *is* weight-sensitive, as in Tidewater's micro-batch versus streaming, I say it's a close call and name the tie-breaker."

</details>

<details><summary><b>Q3 · "Microservices lower availability. You added five. Defend that."</b></summary>

**Initial Prompt.** On Tillpoint: "Every service you add is another thing that can fail. You went from 1 deployable to 6. How is checkout more available?"

**L5 Answer.** "Because if one service fails, the others keep working, so the system is more resilient overall."

**Why L5 Stalls.** That's true only for failures *off* the critical path. If checkout synchronously calls all 6 services, their availabilities multiply and checkout gets worse. The interviewer is testing whether the candidate knows the composition math.

**L7 Answer.** "You're right that services in series multiply. Five synchronous dependencies at 99.95% each give about 99.75% before checkout's own failures, which is below our 99.9% target. The availability gain came from the opposite of adding services: I moved notification, loyalty and analytics off checkout's synchronous path behind a transactional outbox. Checkout now depends synchronously on 2 things, payment authorization and inventory reservation, which compose to about 99.90%. The other 3 can be down for hours without failing a checkout; their events wait in the outbox. The service count went up, but the critical path got shorter, and the critical path is what the SLO measures."

</details>

<details><summary><b>Q4 · "Who proposed the option you rejected, and what was it best at?"</b></summary>

**Initial Prompt.** "Pick your strongest rejected option. Who championed it, and what was it better at than yours?"

**L5 Answer.** "I think it came up in a brainstorm. It was simpler, but it didn't meet our needs."

**Why L5 Stalls.** "Came up in a brainstorm" means no champion. "Simpler" is the only stated strength, and "didn't meet our needs" names no need. That is a strawman, by every test in §7.1.

**L7 Answer.** "The SRE lead's xDS proposal. It was better than mine in 3 ways: no new tier to operate, push semantics on streams that already existed, and propagation latency in the low seconds, slightly better than my relays. If our fleet had been at full sidecar coverage I think it would have won. It lost on 2 measurable criteria in a prototype the SRE lead and I scoped together: 82% coverage, and coupling config pushes to the mesh's release train. From it I kept the mesh's workload identities for relay authentication."

</details>

<details><summary><b>Q5 · "What would have to change for Option A to win?"</b></summary>

**Initial Prompt.** "Give me the world in which your rejected Postgres-polling option is the right answer."

**L5 Answer.** "Probably if we were a lot smaller. At small scale Postgres would be fine."

**Why L5 Stalls.** Scale wasn't the reason Postgres polling lost, so "if we were smaller" shows the candidate doesn't remember (or never knew) the real kill criterion.

**L7 Answer.** "Scale doesn't matter, because it handled our load. It wins in a world where staged rollout isn't a requirement. That means one region, a small fleet where every change can be watched by a human, or config that is never safety-relevant. Concretely: if the per-change blast-radius goal were 'all instances, quickly revertible' instead of '1% for 5 minutes', the atomic-snapshot and ring-pointer kill criterion disappears. The scored rows are already close, 55 to 50 in my favor, and with blast-radius control weighted 2 instead of 4, polling wins them 46 to 45. A second world: if Postgres had a built-in, widely supported publish mechanism with snapshot semantics that all 4 client languages could consume, I'd revisit it too."

</details>

<details><summary><b>Q6 · "You keep saying 'regulatory'. How many hosts left PCI scope, and what did it save?"</b></summary>

**Initial Prompt.** On Tillpoint's tokenization boundary: "Quantify the PCI argument. What actually changed?"

**L5 Answer.** "It reduced our PCI scope significantly, which made audits a lot easier."

**Why L5 Stalls.** "Significantly" and "a lot easier" are unquantified. A regulatory justification for a service boundary has to be priced like any other, or it reads as a convenient label.

**L7 Answer.** "In-scope hosts went from 140 to 12, because card data now stops at the tokenization service at the edge and the order cluster only ever sees tokens. The direct saving was about $230k a year in audit and evidence work, at the roughly $1,800 per in-scope host per year our compliance team uses. The larger saving is in process: 13 teams' services left PCI change control, so their deploys no longer need the ticketed approval that payments uses, which also takes those teams off the deploy-queue math. The tokenization service is small, about 400 requests a second at peak, and its throughput was never part of the argument."

</details>

<details><summary><b>Q7 · "Your velocity argument just says 'we have many teams'. Do the math."</b></summary>

**Initial Prompt.** "Everyone says microservices help team velocity. Show me, with numbers, that your teams were actually blocked."

**L5 Answer.** "Teams were constantly waiting on each other's releases, and merge conflicts were a big problem, so velocity was really low."

**Why L5 Stalls.** "Constantly", "big problem" and "really low" are anecdote. The interviewer wants the queue: demand, capacity, utilization and wait. It also wants to know whether the cheaper fix was tried.

**L7 Answer.** "Demand was 14 teams at about 3 deploys a day, so 42. Capacity was a serialized 45-minute train in a 600-minute day, about 13. Utilization was 3.15, so it wasn't really a queue: changes were batched about 3 to a deploy, and a failed deploy meant bisecting 3 teams' changes. I tried the cheap fix first and took the pipeline from 45 to 12 minutes. Capacity became 50 a day, utilization 0.84, and the M/M/1 mean wait is still about 63 minutes. That measured result is what moved the decision from 'faster pipeline' to 'independent deploy units'. Even then, I'd say velocity justified a modular monolith. The service split came from the PCI boundary."

</details>

<details><summary><b>Q8 · "Isn't 'streaming' just résumé-driven development here?"</b></summary>

**Initial Prompt.** The skeptic's version: "Be honest: wasn't streaming at least partly because it was more interesting to build?"

**L5 Answer.** "No, it was purely a business decision. Streaming was needed for the requirements."

**Why L5 Stalls.** "Purely" is implausible, and it leaves the interviewer's real question unexamined: how did the candidate guard against their own bias? An L7 knows their biases and can name the mechanism that checked them.

**L7 Answer.** "I'm sure the interest was there; it's a more interesting system to build. That's exactly why I put the micro-batch option on the matrix with its own champion, the data platform lead, and scored it honestly. It tied. I didn't let the tie go to the interesting option by default. I documented the tie-breaker, the fraud team's 5-minute roadmap requirement, and asked the fraud team's director to confirm it in writing before I committed. If they'd said 'nice to have', I'd have built the micro-batch. The guard against résumé-driven design isn't claiming I have no bias. It's making the boring option compete fairly, with someone arguing for it."

</details>

<details><summary><b>Q9 · "What did you do about Option Zero?"</b></summary>

**Initial Prompt.** "Before any of these three options, did you consider fixing what you already had?"

**L5 Answer.** "The old system was beyond fixing, so there wasn't much point."

**Why L5 Stalls.** "Beyond fixing" is an unexamined claim (01.3 §3.1), and it suggests the candidate skipped the cheapest option.

**L7 Answer.** "Yes, and it was closer than you'd think. For Beacon, fixing the 4 ZooKeeper clients and adding a staging publisher in front of the ensemble would have addressed A1 and A2. I estimated it at about 4 engineer-months, against roughly 54 for Beacon. It died on the colo exit: the ensemble had to move regardless, and moving a single-region ensemble whose clients span 3 regions would have been its own project. For Tidewater, Option Zero was buying more appliance capacity, about $38k a month more, which fixes the batch window but leaves freshness at up to 29.6 hours, a kill criterion. In both cases I can say exactly which requirement Option Zero failed."

</details>

<details><summary><b>Q10 · "Derive your sink design from the requirement, step by step."</b></summary>

**Initial Prompt.** On Tidewater: "Don't describe the sink. Derive it. Start from the requirement."

**L5 Answer.** "We needed exactly-once, so we used Dataflow's exactly-once processing, and BigQuery handles the rest."

**Why L5 Stalls.** "Exactly-once processing" inside the pipeline doesn't guarantee exactly-once *effects* in an external sink. The answer delegates the hardest part to a product name. The interviewer asked for a derivation and got a citation.

**L7 Answer.** "Requirement: warehouse claim counts must equal source counts, because they feed regulatory reports. Invariant: each source event has exactly one effect in the warehouse. Fact: CDC into Kafka is at-least-once; producer retries and consumer restarts redeliver. So I need idempotency: a stable event key, the source's log sequence number plus the table key, and either a sink write that is transactional against that key or a dedup step before it. Dedup state can't be unbounded, so it needs a horizon, and the horizon has to exceed the longest redelivery delay we'd ever see, which I set at 7 days from the Kafka retention policy plus a margin. Duplicates older than that are impossible by construction, because the source data would be gone. Finally, I don't trust the derivation: a reconciliation job compares control totals per partition per day between source and warehouse, which turns the invariant into a measurement. Folder 03 runs exactly this as code."

</details>

---

## 15. Checklist

- [ ] Three real options plus Option Zero, each with mechanism, best-at, kill criterion, cost, champion, evidence, what was kept, and a revisit trigger (§2).
- [ ] Every kill criterion has a property, a threshold, a measurement and a source (§3.2).
- [ ] Your matrix passes `options_matrix.py`: kill criteria present, no strawmen, champions named, and a concession visible (§12).
- [ ] For every "why not simpler?" argument, the math for your project is prepared: peak/mean and headroom; exposure; availability composition; scope cost; deploy-queue utilization (§4).
- [ ] At least one honest concession prepared: the dimension where the simple option would have worked (§4.6).
- [ ] Close calls named, each with its tie-breaker (§8.3).
- [ ] One derivation chain from requirement to mechanism for your core component (§6).
- [ ] A steelman for your strongest rejected option, including when it would win (§7.2, Q5).
- [ ] The whiteboard layout and the 90-second verbal pattern rehearsed (§9).

---

## 16. References

- Dan McKinley, "Choose Boring Technology". <https://mcfunley.com/choose-boring-technology>
- Martin Fowler, "MonolithFirst". <https://martinfowler.com/bliki/MonolithFirst.html>
- Mel Conway, "Conway's Law". <https://www.melconway.com/Home/Conways_Law.html>
- Amazon Leadership Principles (Invent and Simplify; Frugality; Are Right, A Lot). <https://www.amazon.jobs/content/en/our-workplace/leadership-principles>
- Amazon Builders' Library, "Workload isolation using shuffle-sharding". <https://aws.amazon.com/builders-library/workload-isolation-using-shuffle-sharding/>
- PCI Security Standards Council, Document Library (scoping and segmentation guidance). <https://www.pcisecuritystandards.org/document_library/>
- Google SRE Book, "Embracing Risk" (error budgets). <https://sre.google/sre-book/embracing-risk/>
- Netflix culture memo (farming for dissent). <https://jobs.netflix.com/culture>
- Google re:Work, "A guide to structured interviewing for better hiring practices". <https://rework.withgoogle.com/intl/en/guides/a-guide-to-structured-interviewing-for-better-hiring-practices>
