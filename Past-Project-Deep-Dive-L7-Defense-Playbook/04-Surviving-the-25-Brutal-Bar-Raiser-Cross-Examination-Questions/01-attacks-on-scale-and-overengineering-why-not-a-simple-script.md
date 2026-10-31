# 04.1 · Attacks on Scale and Overengineering: "Why Not a Simple Script?" (Questions 1–9)

> **Folder:** `04-Surviving-the-25-Brutal-Bar-Raiser-Cross-Examination-Questions` · file 1 of 3
> **Question this file answers:** the overengineering attack ("one Postgres would do", "a cron job would do", "why microservices") is the most common way strong candidates lose the deep dive. What are the 9 variants a bar-raiser uses, what does each one really test, and what does a survivable answer contain?
> **Exhibits:** P-0 Beacon (01.1), A·Tidewater, B·Tillpoint, C·Quickset, D·Flightline (Folder 03).
> **Scope labels:** L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff.

| Listing | Language | What it does | Where it runs |
|---|---|---|---|
| L11 `baseline_fit.py` | Python 3, standard library | Checks the boring baselines against a workload table and names the binding resource:<br>1. a single database (writes, reads, storage);<br>2. a scheduled batch (worst-case staleness vs requirement);<br>3. a database table used as a queue;<br>4. a shared deploy train. | [§6](#6-the-baseline-fit-tool), on 5 workloads |

**Verification.** The gate extracts the listing, checks it byte for byte against the source, re-runs it on this file, and compares the result with §6. The tool's verdict confirms that each workload's result matches its stated expectation. Tellings are checked by the Folder 01 lints. Results are in the [README](../README.md#gate-results).

---

## 0. Orientation

Folder 04 contains the **25 cross-examination questions**, grouped into three families:
- **Scale and overengineering:** Q1–Q9, this file.
- **Failure modes** (data loss, duplication, split-brain): Q10–Q17, [04.2](02-attacks-on-failure-modes-data-loss-duplication-and-split-brain.md).
- **Security, compliance, multi-tenancy and day-2 operations:** Q18–Q25, [04.3](03-attacks-on-security-compliance-multi-tenancy-and-day2-operations.md).

Every question is an original formulation of a probe class, not a leaked question.

**How each question is presented.**
- **A defense card** (§3): the attack, what it really tests, the trap, the skeleton of a survivable answer, the numbers you need, the archetype variants, and two follow-ups the interviewer will use next.
- **A full chain** (§8), in the Folder 01 format: Initial Prompt → L5 Answer → Why L5 Stalls → L7 Answer.

**How to drill them.** Pick your project, then answer each card's skeleton aloud with *your* numbers in under 90 seconds. Then have a partner read the follow-ups. Folder 05's mock-interviewer prompt uses these 25 as its probe library.

---

## 1. First principles: why the overengineering attack works, and the five-move answer

### 1.1 What the attack is really about

The interviewer isn't asking whether your system *works*. They're asking whether you can tell **necessary complexity from accidental complexity**, and whether you were honest with yourself about which was which. Every distributed component costs:
- people to operate it (02.2 §6.3);
- failure modes (Folder 04.2);
- a security surface (Folder 04.3);
- organizational coordination.

The bar-raiser's prior, shaped by public writing such as McKinley's "Choose Boring Technology" and Fowler's "MonolithFirst" (02.1 §1.1), is that most systems have more of it than they need.

### 1.2 The five-move answer

| Move | What you say | Why it works |
|---|---|---|
| **1. Concede what's true** | "On throughput alone, one primary would have handled it: 36% at peak." | It takes away the interviewer's strongest point before they make it, and signals that you ran the numbers on your own design |
| **2. Name the binding requirement** | "The PCI boundary: 140 hosts in scope." | It moves the debate from taste to a requirement with a source |
| **3. Show the math** | "Deploy train utilization 3.15, so forced batching of 3 changes." | Numbers are checkable; adjectives aren't |
| **4. State what you kept simple** | "Inventory stayed a module with its own schema, not a service." | It shows complexity was spent deliberately, not by default |
| **5. Name the trigger to simplify** | "If the mesh reaches 95% coverage, the relay tier goes." | It shows the decision is held provisionally, revisited on evidence |

### 1.3 Necessary vs accidental complexity: a quick test

For each component you added, answer: **"What requirement fails, with what number, if I delete this?"**
- If there's an answer, the component is necessary. Say the answer.
- If the answer is "it would be less scalable" or "it's best practice", the component is accidental, or you haven't done the analysis.

Either way, the interviewer will find out.

---

## 2. The baseline-fit method

Before the interview, run every "why not the simple thing?" through an explicit capacity check. `baseline_fit.py` (§6) does it from a small table per workload. **Fitting on capacity doesn't settle the argument**, because the simple option may still fail on semantics, blast radius or regulation. **Exceeding on capacity names exactly which resource the complex design buys.**

### 2.1 Five workloads

<!-- workload:start name=beacon-polling expect=fits -->
| Parameter | Value |
|---|---|
| peak_read_qps | 4800 |
| db_read_capacity_qps | 12000 |
| replicas | 1 |
| peak_write_rows_per_s | 1 |
| db_write_capacity_rows_per_s | 40000 |
<!-- workload:end -->

<!-- workload:start name=tidewater-nightly-cron expect=exceeds -->
| Parameter | Value |
|---|---|
| freshness_required_s | 1800 |
| batch_interval_s | 86400 |
| batch_runtime_s | 20016 |
<!-- workload:end -->

<!-- workload:start name=tidewater-15min-microbatch expect=tight -->
| Parameter | Value |
|---|---|
| freshness_required_s | 1800 |
| batch_interval_s | 900 |
| batch_runtime_s | 420 |
<!-- workload:end -->

<!-- workload:start name=resume-driven-kafka expect=fits -->
| Parameter | Value |
|---|---|
| queue_msgs_per_s | 0.67 |
| table_queue_capacity_msgs_per_s | 5000 |
<!-- workload:end -->

<!-- workload:start name=tillpoint-monolith expect=exceeds -->
| Parameter | Value |
|---|---|
| peak_write_rows_per_s | 14400 |
| db_write_capacity_rows_per_s | 40000 |
| teams | 14 |
| deploys_per_team_per_day | 3 |
| deploy_minutes | 45 |
| work_minutes_per_day | 600 |
<!-- workload:end -->

**What the five show.**
- **Beacon's polling baseline fits** on capacity (40% of one replica). The complex design is justified by staging semantics, not by load.
- **Tidewater's nightly cron exceeds** on freshness by about 59×.
- **Tidewater's micro-batch is tight** (73% of the freshness budget), so it was a real option (02.1 §8.3).
- **The "Kafka for 40 messages a minute" workload fits a table queue** at 0.01% utilization.
- **Tillpoint's monolith fits on writes** (36%) but **exceeds on the deploy queue** (ρ 3.15). The binding constraint is organizational, not the database.

---

## 3. Defense cards: Questions 1–9

### Q1 · "This volume fits in one Postgres instance. Why a distributed pipeline?"

| | |
|---|---|
| **Tests** | Whether you invented scale; whether you know the real reason |
| **Trap** | Claiming the database couldn't handle it, when it could |
| **Skeleton** | Concede the fit with the number → name the non-capacity requirement (atomic snapshot, freshness, PCI) → show what Postgres still does in your design → the trigger |
| **Numbers** | Peak rows/s vs measured capacity; utilization; the requirement's threshold |
| **Variants** | Beacon: 40% of a replica, rejected on G1 staging. Tillpoint: 36%, the split rests on PCI and deploys. Tidewater: capacity *did* bind (batch window), but freshness was the kill criterion. |
| **Follow-ups** | "So you agree Postgres was enough?" → "For throughput, yes; here's the requirement it failed." · "What does Postgres still do?" → "It's the source of truth." |

### Q2 · "A cron job every 15 minutes would meet your freshness target. Why streaming?"

| | |
|---|---|
| **Tests** | Whether you compared against the *good* batch, not the strawman nightly one |
| **Trap** | Arguing against the nightly batch when the question is about micro-batch |
| **Skeleton** | Agree micro-batch meets the requirement (tight: 73% of budget) → name the tie-breaker (a committed or roadmap requirement) → show that the code transfers (same Beam pipeline, batch mode) → "I'd accept micro-batch if the tie-breaker went away" |
| **Numbers** | Interval + runtime = worst staleness; the requirement; the tie-breaker's threshold |
| **Variants** | Tidewater: the fraud team's 5-min requirement. Beacon: not applicable (push semantics required). Quickset: a refresh cron would violate K4's 30 s freshness. |
| **Follow-ups** | "Was the tie-breaker committed?" → "Confirmed in writing by the fraud director before I committed." · "What does streaming cost extra?" → people and state (02.2 §6). |

### Q3 · "Why microservices? A modular monolith gives you modules without the network."

| | |
|---|---|
| **Tests** | Whether you can separate the reasons for *modules* from the reasons for *processes* |
| **Trap** | "Teams can deploy independently", which a modular monolith with independent build units also achieves |
| **Skeleton** | Grant that velocity alone → modular monolith → name the process-boundary requirement (a regulatory scope, independent scaling with numbers, failure isolation with a blast-radius number, a language or runtime boundary) → admit which split was weakest |
| **Numbers** | Deploy-queue ρ; PCI hosts in scope; the critical-path availability |
| **Variants** | Tillpoint: PCI 140 → 12 hosts; inventory as a service was the weakest split. Quickset: the language boundary *forced* in-process (C++). |
| **Follow-ups** | "Which service would you merge back?" → name one. · "What did the network cost you?" → latency per hop, partial failure, the outbox. |

### Q4 · "Kafka for this? A table with `SKIP LOCKED` is a fine queue at your rate."

| | |
|---|---|
| **Tests** | Whether you know the table-queue pattern and its limits |
| **Trap** | Claiming a database can't be a queue |
| **Skeleton** | Agree that at low rates it is (Tillpoint's outbox *is* a table queue drained with `SKIP LOCKED`) → name what the log gave you: replay and retention, multiple independent consumers, ordered partitions, decoupled retention from the producer's database → or concede that it was résumé-driven if it was |
| **Numbers** | Messages/s; consumers; replay window; table-queue capacity on your database |
| **Variants** | Tidewater: 7-day replay sets the dedup horizon; 38 topics; multiple consumers. Tillpoint: the outbox table feeds Kafka; both patterns coexist. |
| **Follow-ups** | "What breaks first on a table queue?" → vacuum and bloat on high churn; index contention; polling cost. · "Would you rip Kafka out today?" → only if consumers ≤ 1 and replay isn't needed. |

### Q5 · "You built for 10× growth. Did it come, and what did the headroom cost while you waited?"

| | |
|---|---|
| **Tests** | Whether you design for the next order of magnitude or for fantasy, and whether you track the cost of headroom |
| **Trap** | Defending capacity that was never used, or claiming the growth came when it didn't |
| **Skeleton** | State what was built for which growth, and the evidence for that growth at the time → what actually happened (numbers) → the cost of unused headroom (infra and complexity) → the design property that made it cheap to be wrong (elastic vs pre-provisioned; two-way doors) |
| **Numbers** | Planned vs actual growth; idle capacity cost per month; time to scale if you'd under-built |
| **Variants** | Tidewater: 35%/yr growth materialized, and capacity is elastic. Quickset: memory headroom pre-provisioned at 12 GB on fixed host shapes. |
| **Follow-ups** | "What would under-building have cost?" → time to add capacity under incident. · "Who decided the growth target?" → name the source. |

### Q6 · "Your peak is 8× your mean. Why not provision for the mean and autoscale?"

| | |
|---|---|
| **Tests** | Whether you know autoscaling's reaction time and which tiers can't autoscale |
| **Trap** | "We autoscale everything", which ignores warm-up, stateful tiers and the database |
| **Skeleton** | Separate the tiers: stateless compute autoscales (with a reaction time); stateful tiers (databases, caches with warm-up, partitions) don't scale in minutes → for known peaks, schedule capacity ahead → for unknown spikes, shed load (quotas, 04.3 Q18) rather than fall over → show the cost of each |
| **Numbers** | Autoscaling reaction time vs spike rise time; cache warm-up time; peak-to-mean ratio |
| **Variants** | Tillpoint: Black Friday is known, so capacity is scheduled; the database was sized for peak at 61% CPU. Quickset: a new host needs ~90 s to warm, so autoscaling on spikes adds cold hosts. Tidewater: mainframe-night peaks (29×) are predictable, and workers are pre-scaled. |
| **Follow-ups** | "How long does a new instance take to be useful?" → state it. · "What sheds first?" → name the lowest-priority traffic. |

### Q7 · "Why did you build this instead of buying it?"

| | |
|---|---|
| **Tests** | Not-invented-here vs evidence |
| **Trap** | "Nothing fit our use case" |
| **Skeleton** | Name the product or library you evaluated, *how* (a prototype for N weeks), the requirement it failed (with the number), the cost comparison (build + own vs adapt/fork + own), and the condition under which you'd buy |
| **Numbers** | Prototype results; maintenance estimate in engineer-years; licensing cost |
| **Variants** | Quickset: the library met latency but failed the byte-exact memory cap. Beacon: built on Postgres and object storage (bought) plus a thin relay tier (built). Tidewater: bought CDC, bought Dataflow, built dedup and reconciliation. |
| **Follow-ups** | "What did you buy?" → list it. Most designs are mostly bought. · "Who maintains it when you leave?" → the ownership plan. |

### Q8 · "You added a cache. Why not just fix the query?"

| | |
|---|---|
| **Tests** | Whether the cache hides a fixable problem, and whether you understand cache costs (invalidation, staleness, cold start) |
| **Trap** | Defending the cache without showing the underlying query was already as good as it gets |
| **Skeleton** | Show the query was fixed first (the plan, before and after) → the remaining reason for the cache (fan-out tail, network hop, rate) with a number → the cache's consistency model and invalidation → its failure mode (cold start, stampede) |
| **Numbers** | Query latency after tuning; the fan-out tail before and after; hit ratio; staleness bound |
| **Variants** | Tillpoint: the index fixed the orders query (§7.2 of 03.2); the cache addressed fan-out (40 → 12 calls). Quickset: no query to fix; the cost was 32-shard fan-out. |
| **Follow-ups** | "What happens when the cache is cold?" → warm-up and admission. · "How stale can it be?" → the bound. |

### Q9 · "How many engineers does it take to run this, compared with the simple version?"

| | |
|---|---|
| **Tests** | Whether you count the people cost of complexity |
| **Trap** | Not knowing, or claiming "it runs itself" |
| **Skeleton** | Name the FTE for each operated component (on-call, upgrades, tuning) → compare with the simple version's FTE → put it in the total-cost comparison (02.2 §6.2) → what you did to reduce it (managed services, automation) |
| **Numbers** | FTE per component; total-cost delta per month |
| **Variants** | Beacon: relays ~0.5 FTE. Tidewater: 2 FTE vs 1.5 for the appliance, so the total cost was negative until the capacity step. Quickset: ~0.5 FTE. |
| **Follow-ups** | "Was it worth it?" → the requirement it bought, priced. · "What would you automate next?" → name it. |

---

## 4. Tellings: the hardest concessions

### 4.1 When the honest answer is "it was résumé-driven"

Sometimes the complex component *wasn't* justified. The L7 move is to say so, show that you know it, and say what you'd do.

#### How an L5 tells it

> We used Kafka because it's the industry standard for event streaming and it gave us a highly scalable foundation for the future. It's basically the best practice for this kind of architecture.

#### How an L7 tells it

> Honestly, the notification queue didn't need Kafka. It carries about 40 messages a minute to 1 consumer, and a table in the service's own Postgres drained with SKIP LOCKED would have run at a tiny fraction of its capacity. It was there because the team had just stood up Kafka for the order events, which did need replay and 6 consumers, and I let the second use ride on the first without running the numbers. Today I'd move it to the outbox table it's already written from and remove 1 topic, 1 consumer group and the on-call for both.

### 4.2 When the growth never came

#### How an L5 tells it

> We designed the system to be highly scalable so it could handle future growth. It's ready for 10x the traffic whenever we need it.

#### How an L7 tells it

> I sized the relay tier for 3 times the fleet, about 150,000 instances, because the platform roadmap in month 0 projected that within 2 years. It reached about 61,000 by month 24. The overbuild costs little, because the relays are stateless and the tier scales by instance count, so we ran 27 relays sized for the actual fleet rather than the projected one. Where headroom was built in and paid for up front, in the snapshot cap and the 64-bit version field, it was cheap by design. The 1 thing I'd change is the 3 relays per availability zone: 2 would have met the load, and the third mostly adds upgrade time.

### 4.3 Counting people

#### How an L5 tells it

> It doesn't take many people to run since it's mostly automated. The team handles it as part of normal on-call and it's pretty much low maintenance.

#### How an L7 tells it

> The pipeline costs about 2 engineers to run, and I count them in the business case: on-call, Dataflow and Kafka upgrades, schema reviews, and the reconciliation repairs. The appliance it replaced needed about 1.5. Counting people, the migration was about $6,700 a month more expensive until the appliance's next capacity step would have hit, and about $13,500 a month cheaper after. I reduced the load in 2 ways: managed Dataflow instead of self-run workers, and an automated repair path for reconciliation mismatches, which took repairs from about 6 engineer-hours a week to 1.

---

## 5. Hiring-committee scoring rubric: overengineering attacks

| Dimension | Poor | Borderline | Solid (L6) | Outstanding (L7) |
|---|---|---|---|---|
| **Concession** | Never concedes | Concedes under pressure | Concedes the capacity fit unprompted | Concedes where the design was *not* justified (résumé-driven parts) |
| **Binding requirement** | "Scalability" | A named requirement, no number | Requirement + threshold + source | Plus the math showing the baseline fails it |
| **Simplicity elsewhere** | Everything complex | — | Names what was kept simple | Shows complexity spent deliberately, with a trigger to simplify |
| **People cost** | "Runs itself" | Mentions on-call | FTE per component | FTE in the total-cost comparison; automation that reduced it |
| **Build vs buy** | NIH | "Didn't fit" | The failed requirement | Prototype evidence, maintenance estimate, buy condition |

---

## 6. The baseline-fit tool

### 6.1 Listing L11: `baseline_fit.py`

<!-- listing:baseline_fit.py -->
```python
#!/usr/bin/env python3
"""baseline_fit.py - would the boring baseline have worked?

Reads every workload table between
    <!-- workload:start name=<label> expect=<fits|tight|exceeds> -->  ...  <!-- workload:end -->
(two columns: Parameter | Value) and checks each simple baseline whose
parameters are present:

  db-writes      peak_write_rows_per_s      vs db_write_capacity_rows_per_s
  db-reads       peak_read_qps              vs db_read_capacity_qps x replicas
  db-storage     rows_per_day x retention_days x row_bytes vs db_storage_limit_gb
  batch-fresh    batch_interval_s + batch_runtime_s (worst staleness) vs freshness_required_s
  table-queue    queue_msgs_per_s           vs table_queue_capacity_msgs_per_s
  deploy-queue   teams x deploys_per_team_per_day vs work_minutes_per_day / deploy_minutes

Utilization <= 0.70 fits, <= 0.90 is tight, above that exceeds. The workload's
verdict is its worst check, and the binding check is named. "Fits on capacity"
does not end the argument (semantics, blast radius, regulation may still kill
the baseline); "exceeds" names exactly which resource the complex design buys.
Usage: python -I baseline_fit.py <file.md>
"""
import re
import sys

CHECKS = [
    ("db-writes", "peak_write_rows_per_s", lambda p: p["db_write_capacity_rows_per_s"]),
    ("db-reads", "peak_read_qps", lambda p: p["db_read_capacity_qps"] * p.get("replicas", 1)),
    ("db-storage", None, lambda p: p["db_storage_limit_gb"]),
    ("batch-fresh", None, lambda p: p["freshness_required_s"]),
    ("table-queue", "queue_msgs_per_s", lambda p: p["table_queue_capacity_msgs_per_s"]),
    ("deploy-queue", None, lambda p: p["work_minutes_per_day"] / p["deploy_minutes"]),
]
NEEDS = {
    "db-writes": ["peak_write_rows_per_s", "db_write_capacity_rows_per_s"],
    "db-reads": ["peak_read_qps", "db_read_capacity_qps"],
    "db-storage": ["rows_per_day", "retention_days", "row_bytes", "db_storage_limit_gb"],
    "batch-fresh": ["batch_interval_s", "batch_runtime_s", "freshness_required_s"],
    "table-queue": ["queue_msgs_per_s", "table_queue_capacity_msgs_per_s"],
    "deploy-queue": ["teams", "deploys_per_team_per_day", "deploy_minutes", "work_minutes_per_day"],
}
RANK = {"fits": 0, "tight": 1, "exceeds": 2}


def demand(name, p):
    if name == "db-storage":
        return p["rows_per_day"] * p["retention_days"] * p["row_bytes"] / 1e9
    if name == "batch-fresh":
        return p["batch_interval_s"] + p["batch_runtime_s"]
    if name == "deploy-queue":
        return p["teams"] * p["deploys_per_team_per_day"]
    return p[dict((c[0], c[1]) for c in CHECKS)[name]]


def verdict(u):
    return "fits" if u <= 0.70 else ("tight" if u <= 0.90 else "exceeds")


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    md = open(sys.argv[1], encoding="utf-8").read().replace("\r\n", "\n")
    blocks = re.findall(r"<!-- workload:start name=(\S+) expect=(\w+) -->\n(.*?)<!-- workload:end -->", md, re.S)
    ok = True
    print(f"baseline_fit: {len(blocks)} workload(s); fits <= 0.70 < tight <= 0.90 < exceeds")
    for name, expect, body in blocks:
        p = {}
        for row in body.splitlines():
            cells = [c.strip() for c in row.strip().strip("|").split("|")]
            if len(cells) == 2 and re.fullmatch(r"[a-z_]+", cells[0]):
                p[cells[0]] = float(cells[1].replace(",", ""))
        print()
        print(f"workload {name} (expect {expect})")
        worst, binding = "fits", "-"
        for check, _, cap in CHECKS:
            if not all(k in p for k in NEEDS[check]):
                continue
            d, c = demand(check, p), cap(p)
            u = d / c
            v = verdict(u)
            print(f"  {check:<13} demand {d:>14,.1f}  limit {c:>14,.1f}  utilization {u:7.2f}  {v}")
            if RANK[v] > RANK[worst] or (RANK[v] == RANK[worst] and binding == "-" and v != "fits"):
                worst, binding = v, check
        msg = {"fits": "the simple baseline fits on capacity; reject it only on a named non-capacity requirement",
               "tight": f"tight on {binding}: the baseline works with little headroom; say so",
               "exceeds": f"exceeds on {binding}: that resource is what the complex design buys"}[worst]
        print(f"  => {worst.upper()}: {msg}")
        ok &= worst == expect
    print()
    print("verdict:", "OK (every workload's verdict matches its stated expectation)" if ok else "CHECK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

### 6.2 Output on the five workloads in §2.1

<!-- output:baseline_fit.py -->
```text
baseline_fit: 5 workload(s); fits <= 0.70 < tight <= 0.90 < exceeds

workload beacon-polling (expect fits)
  db-writes     demand            1.0  limit       40,000.0  utilization    0.00  fits
  db-reads      demand        4,800.0  limit       12,000.0  utilization    0.40  fits
  => FITS: the simple baseline fits on capacity; reject it only on a named non-capacity requirement

workload tidewater-nightly-cron (expect exceeds)
  batch-fresh   demand      106,416.0  limit        1,800.0  utilization   59.12  exceeds
  => EXCEEDS: exceeds on batch-fresh: that resource is what the complex design buys

workload tidewater-15min-microbatch (expect tight)
  batch-fresh   demand        1,320.0  limit        1,800.0  utilization    0.73  tight
  => TIGHT: tight on batch-fresh: the baseline works with little headroom; say so

workload resume-driven-kafka (expect fits)
  table-queue   demand            0.7  limit        5,000.0  utilization    0.00  fits
  => FITS: the simple baseline fits on capacity; reject it only on a named non-capacity requirement

workload tillpoint-monolith (expect exceeds)
  db-writes     demand       14,400.0  limit       40,000.0  utilization    0.36  fits
  deploy-queue  demand           42.0  limit           13.3  utilization    3.15  exceeds
  => EXCEEDS: exceeds on deploy-queue: that resource is what the complex design buys

verdict: OK (every workload's verdict matches its stated expectation)
```

**Reading the output.** Two workloads fit, one is tight, two exceed, and the binding check is named each time. Note `tillpoint-monolith`: the database fits at 36%, and the deploy queue is what exceeds (3.15). If your own workload "fits", the overengineering attack has to be answered with a non-capacity requirement, or by conceding.

---

## 7. Failure modes

| # | Failure mode | Symptom | Fix |
|---|---|---|---|
| F1 | Invented scale | "It wouldn't scale" with no number | Run `baseline_fit.py`; concede if it fits |
| F2 | Strawman baseline | Arguing against nightly batch when asked about micro-batch | Compare against the *best* simple option (Q2) |
| F3 | Modules ≠ processes | Velocity used to justify services | Name the process-boundary requirement (Q3) |
| F4 | "Databases can't queue" | Contradicted by your own outbox | Know the table-queue limits (Q4) |
| F5 | Defending unused headroom | 10× capacity idle for 2 years | Cheap-to-be-wrong designs; admit overbuild (§4.2) |
| F6 | "We autoscale everything" | Ignores stateful tiers and warm-up | Tier-by-tier scaling story (Q6) |
| F7 | NIH | "Nothing fit" | Prototype + failed requirement + buy condition (Q7) |
| F8 | Cache hiding a bad query | No before/after plan | Fix the query first (Q8) |
| F9 | People cost ignored | Total cost unknown | FTE per component (Q9, §4.3) |
| F10 | Never conceding | Every component "necessary" | The five-move answer, move 1 (§1.2) |

---

## 8. Bar-raiser chains

<details><summary><b>Q1 · "This volume fits in one Postgres instance. Why did you build a distributed pipeline?"</b></summary>

**Initial Prompt.** On Beacon: "4,800 reads a second of tiny rows. One Postgres replica eats that for breakfast. Why the relay tier, the snapshots, the controller?"

**L5 Answer.** "Because at our scale, with 48,000 instances, a single database would be a bottleneck and a single point of failure."

**Why L5 Stalls.** The candidate's own load test (12,000 QPS on one replica) contradicts "bottleneck", and replicas address "single point of failure". Both claims collapse in one follow-up.

**L7 Answer.** "You're right on capacity: 4,800 reads a second is about 40% of what one replica sustained in our load test, and I say that in the RFC. Throughput isn't what the complex parts buy. They buy staging. A bad flag change must reach at most 1% of instances for at most 5 minutes, because A1 went global in 2 seconds. Postgres polling gives every client every row as soon as it commits, with no atomic multi-key snapshot and no ring pointer, so staging would have to be rebuilt in 4 client libraries. Postgres is still the source of truth in my design; the publisher reads its change log. If the 1% blast-radius requirement didn't exist, I'd have built the polling design."

</details>

<details><summary><b>Q2 · "A cron job every 15 minutes would meet your freshness target. Why streaming?"</b></summary>

**Initial Prompt.** On Tidewater: "Your requirement is 30 minutes. Run the batch every 15. Done. Why Dataflow streaming?"

**L5 Answer.** "Batch has too much latency, and streaming gives us real-time data, which is better for the business."

**Why L5 Stalls.** "Real-time is better" isn't a requirement, and the interviewer has just proposed a batch cadence that meets the stated requirement. The candidate is arguing against something nobody proposed.

**L7 Answer.** "It would meet it, and I evaluated exactly that. A 15-minute schedule plus about 7 minutes of runtime gives a worst-case staleness of about 22 minutes, 73% of the 30-minute budget. That's tight but valid, and on my matrix it tied with streaming. The tie-breaker was the fraud team's 5-minute requirement 2 quarters out, which I had their director confirm before committing; micro-batch can't reach 5 minutes. Without it, I'd have built the micro-batch, and the code would have been the same Beam pipeline in batch mode, which is in fact how our backfill runs today."

</details>

<details><summary><b>Q3 · "Why microservices? A modular monolith gives you independent modules without the network."</b></summary>

**Initial Prompt.** On Tillpoint: "Modules with enforced boundaries, separate build units, one deployable. That solves team independence. Why pay for the network?"

**L5 Answer.** "Microservices let teams deploy and scale independently, which a monolith can't do."

**Why L5 Stalls.** A modular monolith with per-module build and deploy units does give independent deploys, and the candidate hasn't named anything that *requires* a process boundary.

**L7 Answer.** "For team independence alone, I agree, a modular monolith was enough, and my velocity math pointed there. The process boundaries came from 2 requirements a module can't satisfy. First, PCI scope: as long as card data passes through a process, that process's hosts are in scope, so tokenization had to be its own process at the edge, which took 140 hosts to 12. Second, the critical path: checkout needed only 2 synchronous dependencies for 99.9%, which meant loyalty, notifications and analytics moved behind an outbox and became independent consumers. The weakest split was inventory; a module with its own schema would have been close, and I'd defend it only on independent scaling for the doorbuster week."

</details>

<details><summary><b>Q4 · "Kafka for this? A table with SELECT … FOR UPDATE SKIP LOCKED is a perfectly good queue at your rate."</b></summary>

**Initial Prompt.** "Your notification events: 40 a minute. Why is there a Kafka topic?"

**L5 Answer.** "Kafka is more reliable and scalable than using the database as a queue, which is an anti-pattern."

**Why L5 Stalls.** The candidate's own outbox is a database queue drained with SKIP LOCKED, so "anti-pattern" contradicts their design. And "reliable and scalable" isn't a requirement at 40 messages a minute.

**L7 Answer.** "For that topic you're right, and I'd remove it. 40 messages a minute to 1 consumer is a tiny fraction of what a SKIP LOCKED table queue handles; it rode on Kafka because the order events were already there. For the order events, the log earns its place: 6 independent consumers each reading at their own pace, 7 days of replay that we use for re-processing after consumer bugs, and ordered partitions per order. A table queue gives you none of those without building them. The test I'd apply is whether a topic has more than 1 consumer or needs replay. If not, it belongs in the producer's database."

</details>

<details><summary><b>Q5 · "You built for 10× growth. Did it come? What did the headroom cost while you waited?"</b></summary>

**Initial Prompt.** "Your RFC sized for 150,000 instances. How many do you have?"

**L5 Answer.** "We're not there yet, but we're ready when the growth comes, so it was a good investment."

**Why L5 Stalls.** "Ready when growth comes" doesn't say what the unused headroom costs, or whether the growth estimate was ever sound.

**L7 Answer.** "About 61,000 at month 24, against the 150,000 the roadmap projected in month 0. The cost of being wrong was small by design: the relays are stateless and scale by instance count, so we only ever ran the 27 the actual fleet needed. The headroom we paid for up front, the 4-megabyte snapshot cap and 64-bit versions, costs almost nothing. Where I overbuilt was 3 relays per availability zone; 2 meet the load with margin, and the third mostly lengthens rolling upgrades. That's about 9 instances I'd remove. The general rule I'd defend: build the expensive-to-change parts, like formats and identifiers, for 10 times, and build the cheap-to-change parts, like instance counts, for what you have."

</details>

<details><summary><b>Q6 · "Your peak is 8× your mean. Why not provision for the mean and autoscale?"</b></summary>

**Initial Prompt.** On Tillpoint: "You run for Black Friday all year? Autoscale."

**L5 Answer.** "We do use autoscaling for the services, so we scale up for peaks automatically."

**Why L5 Stalls.** Autoscaling works for stateless tiers but not for the database or warm caches, and the candidate doesn't mention reaction time. The answer suggests they haven't thought about which tiers can scale in minutes.

**L7 Answer.** "Tier by tier. The stateless services autoscale on request rate, with a reaction time of about 3 minutes from signal to a serving instance, which is fine for gradual ramps. Black Friday isn't gradual and isn't a surprise, so we schedule that capacity a day ahead rather than react to it. The primary database can't autoscale in minutes at all: it's sized for peak at about 61% CPU, and the rest of the year it runs far below that, which I accept as the price of not resharding under load. For unplanned spikes, the answer isn't more capacity, it's shedding: per-merchant quotas reject the excess with 429s before it reaches the database. The quiet merchants are protected, at the cost of the noisy one."

</details>

<details><summary><b>Q7 · "Why did you build this instead of buying it?"</b></summary>

**Initial Prompt.** On Quickset: "There are good in-process cache libraries. Why write your own?"

**L5 Answer.** "The existing libraries didn't fit our use case, and building our own gave us more control and better performance."

**Why L5 Stalls.** "Didn't fit" and "more control" are unfalsifiable. The interviewer wants the library, the test and the failed requirement.

**L7 Answer.** "I prototyped the strongest library for 2 weeks before writing anything. It met latency: about 1.1 milliseconds p99 per request in our load test, against our 3. It failed the memory requirement: entries were individually allocated and eviction counted entries, not bytes, so the 12-gigabyte hard cap couldn't be enforced with values ranging from 200 bytes to 6 kilobytes. Making it byte-exact meant forking it. I estimated owning a fork at about 1.5 engineer-years over 3 years against about 3 to build and own Quickset, and chose to build. Most of the system is still bought: Redis on the miss path, the change stream and the histogram library. If the library added custom allocators with byte accounting, I'd move to it."

</details>

<details><summary><b>Q8 · "You added a cache. Why not just fix the query?"</b></summary>

**Initial Prompt.** On Tillpoint: "Caches hide bad queries. Did you fix the query first?"

**L5 Answer.** "The query was already optimized, so caching was the next step to get the latency down."

**Why L5 Stalls.** "Already optimized" without a plan is unverifiable, and it doesn't say what the cache fixed that the query couldn't.

**L7 Answer.** "Yes, and they fixed different things. The slow query, open orders by customer, was a sequential scan of 200,000 rows plus a sort; a partial composite index turned it into an index scan reading 20 rows, and that was the query fix. The cache addressed something no query fix could: checkout made 40 calls, so about 33% of checkouts touched at least 1 call's tail. Caching 28 read-mostly lookups took it to 12 calls and the tail exposure to about 11%, which is the p99 move from 238 to 141 milliseconds. The cache's staleness is bounded by event-driven invalidation plus a 60-second TTL. Its failure mode is a cold start after a deploy, handled by warming from the previous instance's key list before taking traffic."

</details>

<details><summary><b>Q9 · "How many engineers does it take to run this, compared with the simple version?"</b></summary>

**Initial Prompt.** On Tidewater: "Your old system was an appliance and a cron job. What does the new one cost in people?"

**L5 Answer.** "It's mostly managed services, so it doesn't need much maintenance. The team handles it in normal on-call."

**Why L5 Stalls.** "Doesn't need much" isn't a number, and the interviewer suspects the people cost was never counted. In Tidewater's case, counting it changes the business case.

**L7 Answer.** "About 2 FTE against about 1.5 for the appliance, and I put both in the business case, because they flip it. Infrastructure alone, cloud was cheaper from day 1: $57,260 against $61,000 a month. With people, it was about $6,700 a month more expensive until growth would have forced a $38,000-a-month capacity step on the appliance, and about $13,500 a month cheaper after that. The 2 FTE go to on-call, Dataflow and Kafka upgrades, schema reviews, and reconciliation repairs. I automated the repair path, which took repairs from about 6 engineer-hours a week to 1, and the migration was justified by freshness, not cost. That's the version I told the director."

</details>

---

## 9. Checklist

- [ ] For each complex component: "what fails, by what number, if I delete it?" (§1.3).
- [ ] A workload table for your system, run through `baseline_fit.py` (§2, §6).
- [ ] Q1–Q9 skeletons answered aloud with your numbers in under 90 s each (§3).
- [ ] One honest concession where a component wasn't justified (§4.1).
- [ ] Your growth assumptions, what actually happened, and the cost of headroom (Q5).
- [ ] The tier-by-tier scaling story, with reaction times (Q6).
- [ ] Build-vs-buy evidence for everything you built (Q7).
- [ ] The query fix before the cache (Q8).
- [ ] FTE per operated component, in the total-cost comparison (Q9).

---

## 10. References

- Dan McKinley, "Choose Boring Technology". <https://mcfunley.com/choose-boring-technology>
- Martin Fowler, "MonolithFirst". <https://martinfowler.com/bliki/MonolithFirst.html>
- PostgreSQL documentation: `SELECT`, the locking clause (`SKIP LOCKED`). <https://www.postgresql.org/docs/current/sql-select.html>
- Apache Kafka documentation (consumer groups, retention, partitions). <https://kafka.apache.org/documentation/>
- FinOps Foundation, FinOps Framework. <https://www.finops.org/framework/>
- Amazon Leadership Principles (Frugality; Invent and Simplify). <https://www.amazon.jobs/content/en/our-workplace/leadership-principles>
