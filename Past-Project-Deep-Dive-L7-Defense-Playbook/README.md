# Past-Project Deep-Dive L7 Defense Playbook

A knowledge base for the **60-minute Past Project Technical Deep-Dive / Architecture Retrospective** round at L6/L7: presenting a real production architecture on a whiteboard and defending it against two skeptical Principal Engineers. The companies used as lenses are Google, Amazon, NVIDIA, Uber, Apple and Netflix.

**Integrity rule.** This playbook teaches you to present work you really did, at its true scope, as clearly and defensibly as possible. It never helps you claim decisions you didn't make. That is an ethical line. It is also the winning tactic: the round is designed to find where your knowledge stops, so a claim you can't defend at depth costs more than a smaller claim you can.

## Status: complete (2026-10-31)

| Folder | Files | Words | Listings | Gate |
|---|---|---|---|---|
| [`01-Anatomy-of-the-60-Minute-Deep-Dive-Round/`](01-Anatomy-of-the-60-Minute-Deep-Dive-Round/) | 3 | ~42.2k | 3 (Python) | Passed |
| [`02-The-3-Viable-Options-Tradeoff-Defense-Framework/`](02-The-3-Viable-Options-Tradeoff-Defense-Framework/) | 3 | ~25.0k | 3 (Python) | Passed |
| [`03-Complete-L7-Whiteboard-Blueprints-for-4-Career-Archetypes/`](03-Complete-L7-Whiteboard-Blueprints-for-4-Career-Archetypes/) | 4 | ~36.7k | 4 (Java/Beam, Java/PostgreSQL, C++23, C11) | Passed |
| [`04-Surviving-the-25-Brutal-Bar-Raiser-Cross-Examination-Questions/`](04-Surviving-the-25-Brutal-Bar-Raiser-Cross-Examination-Questions/) | 3 | ~17.6k | 3 (Python) | Passed |
| [`05-Personal-Project-Dossier-Template-and-Stress-Test-Harness/`](05-Personal-Project-Dossier-Template-and-Stress-Test-Harness/) | 2 | ~13.5k | 2 (Python) | Passed |
| **Total** | **15** | **~135k** | **15** | **All passed** |

The KB has 141 bar-raiser chains and 70 paired L5/L7 tellings. Every file is checked: an L5 telling must be flagged by the lints, and an L7 telling must be clean.

**Folder names.** The brief's role line describes the KB as running from `01-Anatomy-of-the-Deep-Dive-Round/` to `05-Interactive-Adversarial-Grilling-Scripts/`. Its repository blueprint uses the longer names above. This KB follows the blueprint exactly.

## What's in each folder

### 01 · Anatomy of the 60-minute round
| File | Covers | Listing |
|---|---|---|
| [01.1 Pacing](01-Anatomy-of-the-60-Minute-Deep-Dive-Round/01-minute-by-minute-whiteboard-pacing-strategy-from-context-to-internals.md) | 7 signals, the depth floor, the 60-minute budget, the **P-0 Beacon** fact sheet, board zones, C4 zoom ladder, phase playbook, two scripted plans, interrupts, the cut order, depth wells, the numbers card, company lenses | `pace_check.py` |
| [01.2 Architect or passenger](01-Anatomy-of-the-60-Minute-Deep-Dive-Round/02-how-interviewers-test-if-you-were-the-architect-or-just-a-passenger.md) | 14 passenger tells, 12 authorship probes, the ownership map (enterprise band → ★ overlay), I/we attribution grammar, scope integrity, the consistency web | `ownership_lint.py` |
| [01.3 Constraints](01-Anatomy-of-the-60-Minute-Deep-Dive-Round/03-framing-constraints-legacy-tech-debt-client-politics-and-tight-deadlines.md) | The six properties of a constraint, the nine-column ledger, legacy and debt, stakeholder accountability, consulting client constraints, deadline math | `constraint_check.py` |

### 02 · The three-viable-options trade-off framework
| File | Covers | Listing |
|---|---|---|
| [02.1 Rejecting A and B](02-The-3-Viable-Options-Tradeoff-Defense-Framework/01-proving-first-principles-why-you-rejected-option-a-and-option-b.md) | Kill criteria vs weights; the five legitimate reasons for complexity (spikes, blast radius, SLA, regulatory scope, multi-team velocity), each with math; the honest concession; Option Zero; derivations; strawman detection | `options_matrix.py` |
| [02.2 Quantifying](02-The-3-Viable-Options-Tradeoff-Defense-Framework/02-quantifying-bottlenecks-before-and-after-latency-throughput-and-finops-math.md) | Little's law, the queueing knee, fan-out tails, percentiles that don't add, availability composition, batch windows, total-cost FinOps (people included), attribution | `capacity_math.py` |
| [02.3 Hindsight](02-The-3-Viable-Options-Tradeoff-Defense-Framework/03-answering-what-would-you-redesign-today-with-hindsight.md) | Decision vs outcome quality, time anchors, the regret taxonomy, reversibility, v2 delta plus migration path | `hindsight_check.py` |

### 03 · Four archetype blueprints
Each has a fact sheet, a whiteboard, three deep wells, a failure story, the trade-off defense, a constraint ledger, a numbers card, a rubric and 10 chains.

| File | Archetype | Listing (real code) |
|---|---|---|
| [03.1 A · Tidewater](03-Complete-L7-Whiteboard-Blueprints-for-4-Career-Archetypes/01-archetype-a-enterprise-data-migration-pipeline-beam-dataflow-gcp-defense.md) | Legacy-to-cloud CDC → Kafka → Dataflow → BigQuery/GCS | `TidewaterPipeline.java`: Beam 2.77 DirectRunner + TestStream (DLQ, stateful dedup, late panes, reconciliation catching a dropped event) |
| [03.2 B · Tillpoint](03-Complete-L7-Whiteboard-Blueprints-for-4-Career-Archetypes/02-archetype-b-banking-microservices-java-sql-idempotency-and-saga-defense.md) | Payments and checkout modernization | `TillpointLedger.java`: real PostgreSQL 18 (8 concurrent requests → 1 charge; double entry; outbox with `SKIP LOCKED`; idempotent saga compensation; `EXPLAIN ANALYZE` before and after) |
| [03.3 C · Quickset](03-Complete-L7-Whiteboard-Blueprints-for-4-Career-Archetypes/03-archetype-c-cpp-low-latency-application-and-memory-optimization-defense.md) | C++ in-process feature cache | `quickset.cpp`: probe lengths vs theory (and the 289-probe tail), 0 vs 100,000 allocations, LRU/FIFO/CLOCK/S3-FIFO hit ratios, cache-line layout |
| [03.4 D · Flightline](03-Complete-L7-Whiteboard-Blueprints-for-4-Career-Archetypes/04-archetype-d-embedded-systems-safety-critical-firmware-and-bus-protocol-defense.md) | Avionics data concentrator firmware | `flightline.c`: ARINC 429 encode/decode, MC/DC independence pairs (1/5 → 5/5), cyclic-executive frame budgets, an SPSC ring with an explicit overflow policy; cross-compiled for Cortex-M7 |

### 04 · The 25 cross-examination questions
| File | Questions | Listing |
|---|---|---|
| [04.1 Scale and overengineering](04-Surviving-the-25-Brutal-Bar-Raiser-Cross-Examination-Questions/01-attacks-on-scale-and-overengineering-why-not-a-simple-script.md) | Q1–Q9: one Postgres, a 15-min cron, the modular monolith, table-as-queue, unused headroom, autoscaling, build vs buy, cache vs query, people cost | `baseline_fit.py` |
| [04.2 Failure modes](04-Surviving-the-25-Brutal-Bar-Raiser-Cross-Examination-Questions/02-attacks-on-failure-modes-data-loss-duplication-and-split-brain.md) | Q10–Q17: every duplicate source, consumer crashes, producer retries, split brain and fencing, read-your-writes, backfill overlap, poison messages, cross-region ordering | `failure_sim.py` |
| [04.3 Security and day 2](04-Surviving-the-25-Brutal-Bar-Raiser-Cross-Examination-Questions/03-attacks-on-security-compliance-multi-tenancy-and-day2-operations.md) | Q18–Q25: noisy neighbors, cross-tenant leaks, rotation, erasure, audit, the 3 a.m. page, schema evolution, per-tenant cost | `tenant_sim.py` |

### 05 · Your dossier and the stress test
| File | Covers | Listing |
|---|---|---|
| [05.1 Dossier template](05-Personal-Project-Dossier-Template-and-Stress-Test-Harness/01-fill-in-the-blank-l7-project-rfc-and-whiteboard-script-template.md) | The blank 12-section template, field guidance, a fully filled Beacon dossier, dossier ↔ RFC mapping | `dossier_check.py` (the harness: 6 structural checks + 5 tool checks) |
| [05.2 Mock interviewer](05-Personal-Project-Dossier-Template-and-Stress-Test-Harness/02-adversarial-mock-interviewer-prompt-to-grill-my-filled-dossier.md) | The copy-paste XML prompt for two adversarial interviewers, the probe library, the protocol, the scoring sheet | `grill_plan.py` (a deterministic 60-minute probe plan from your dossier) |

## Exhibits (all composites, with internally consistent placeholder numbers)

| ID | System | Where |
|---|---|---|
| P-0 Beacon | Config and feature-flag distribution: 1,200 services, 48,000 instances; replaced ZooKeeper before a colo exit | 01.1 §3; used in every folder |
| A · Tidewater | An insurer's nightly batch → CDC/Kafka/Dataflow/BigQuery | 02.1 preview, 03.1 |
| B · Tillpoint | Commerce checkout and payments → services with idempotency, saga and outbox | 02.1 preview, 03.2 |
| C · Quickset | In-process C++ feature cache for a ranking service | 03.3 |
| D · Flightline | Remote data concentrator firmware (ARINC 429, MC/DC) | 03.4 |

## Conventions

- **Scope labels:** L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff.
- **⚠** marks mechanics that are not publicly documented. Company material is cited only from public pages: About Amazon on Bar Raisers, the Amazon Leadership Principles, Google re:Work, and the Netflix culture memo.
- **No leaked questions.** Every question is an original formulation. Companies are domain lenses.
- **Tellings** use `#### How an L5 tells it` / `#### How an L7 tells it` + `>` blockquotes. Dossier tellings use `#### My telling: <label>`.
- **Chains** use `<details><summary><b>Qn · …</b></summary>` with the four bold labels in order.
- **Marks:** ★ designed/led/wrote · ◆ reviewed/contributed · ○ consumed. **Number labels:** [M] measured · [E] estimated from inputs · [D] design target.
- **Tables the tools read, by marker:**
  - `ledger:start`: constraints;
  - `options:start`: option matrices;
  - `hindsight:start`: hindsight ledgers;
  - `workload:start`: baseline fit;
  - `cachekeys:start`: tenant-scoped cache keys;
  - `dossier:start`: dossiers.

  Names beginning `l5-` (or `blank`) are negative examples, and the tools expect them to fail.
- **Whiteboard scripts** go in ```` ```script ```` fences (01.1 §8). Spelling is American.

## Using the tools on your own project

1. **Copy the 7 Python listings into one folder:** `pace_check.py`, `ownership_lint.py`, `constraint_check.py`, `options_matrix.py`, `hindsight_check.py`, `dossier_check.py`, `grill_plan.py`. Each is standard-library only.
2. **Fill the 05.1 template** in `my-dossier.md`, then run `python -I dossier_check.py my-dossier.md` until it reports READY.
3. **Generate the probe plan:** `python -I grill_plan.py my-dossier.md`.
4. **Run the mocks** with the 05.2 prompt (paste the dossier and the plan) and with a human partner.
5. **Optional:** use `capacity_math.py`, `baseline_fit.py`, `failure_sim.py` and `tenant_sim.py` with your own parameters to rebuild every number you plan to say.

The Java, C++ and C listings in Folder 03 are exhibits. Their headers give the toolchain each one was built with (JDK 25 with `--release 21` and Beam 2.77.0 jars; PostgreSQL 18 embedded via zonky; Zig 0.16 / Clang 21).

## Gate results

Each folder is gated with `tools/gate.py <folder> --urls`, run on the final files. The final run covered all five folders.

| Check | Result |
|---|---|
| **Structure.** Every file has a header listing table and a Verification line; the spine `0. Orientation`, `1. First principles` … Failure modes, Bar-raiser chains, Checklist, References; ≥ 8 chains, each with its 4 labels; L5/L7 balance | 15/15 files pass: 141 chains, 70 pairs |
| **Listings.** Byte-identical to the source that was run | 15/15 |
| **Reruns.** Extracted listings, compiled and re-run on the final files, reproduce the embedded outputs | 15/15 identical. Every tool's own verdict line reads OK; `pace_check` shows the L5 plan with 6 flags and the L7 plan PASS. |
| **Compilers.** Java with `-Xlint:all -Werror` (Beam 2.77.0; PostgreSQL 18.6 embedded); C++23 and C11 with `-Wall -Wextra -Werror -pedantic` | All clean. `flightline.c` firmware core cross-compiled for `thumb-freestanding-eabihf -mcpu=cortex_m7`: 1,700-byte object. |
| **Lints.** Every L5 telling flagged by `ownership_lint` or `constraint_check`; every L7 telling clean in both | L5 70/70 flagged; L7 70/70 clean |
| **Ledgers and tables.** Constraint ledgers (`l5-*` must fail, the others pass); options, hindsight, workload, cache-key and dossier tables via their tools | All as expected: 6 constraint ledgers (plus 2 inside the dossiers, checked by the harness); 3 option matrices; 3 hindsight ledgers; 5 workloads; 2 key tables; 2 dossiers |
| **Links.** Relative links and anchors | 61/61 OK |
| **External URLs.** Every file + README | 63/63 reachable |

**Source notes.**
- **Google's careers pages** render without content for automated fetches, so Google's process is cited from re:Work.
- **CrowdStrike's RCA PDF** was verified by searching its decompressed content streams.
- **The Chesterton Society page** returns 403 to automated checks, so the fence parable is cited from the 1929 book.
- **ACM, APA and INFORMS papers** are cited by DOI and checked through Crossref (Little 1961; Dean & Barroso 2013; Fischhoff 1975; Garcia-Molina & Salem 1987; Liu & Layland 1973; Wilhelm et al. 2008; Lamport 1978; Yang et al. 2023).
- **Book ISBNs** were checked through Open Library where available (*Thinking in Bets*).
- **Vendor semantics** were confirmed against current documentation before writing: Dataflow exactly-once (processing vs side effects vs completeness), and the BigQuery Storage Write API (default stream at-least-once; committed type with offsets for exactly-once).
- **Embedded-PostgreSQL jars** were fetched from Maven Central with SHA-1 verification.

**Refinements made during the build.**
1. `pace_check.py` gained the CONTEXT-HEAVY and LATE-DEPTH rules: a plan can stay inside its own budgets and still be a context dump.
2. The tools call `sys.stdout.reconfigure(utf-8)`, because `-I` ignores `PYTHONIOENCODING`.
3. EXCUSE now matches "wasn't my call".
4. Some L7 tellings were rephrased where the unquantified-claim rule can't tell an invariant ("versions only increase") from an improvement claim.
5. The Tillpoint SQL demo showed the planner choosing a bitmap scan plus a sort for a small customer. That was kept as a teaching point, and a large-account query was added for the index-order plan.
6. The tenant simulation showed that a quota alone leaves a transient set by its burst allowance (171 ms). That was kept, and quota + DRR was added.
7. The MC/DC vector set was redesigned when a hand check showed the first draft would score 4/5, because of coupled SSM conditions.
8. The parity check was widened from one bit flip to all 32.
9. The gate extracts every listing in the KB before reruns, so the Folder 05 harness imports its sibling tools exactly as a reader would after copying them out.
