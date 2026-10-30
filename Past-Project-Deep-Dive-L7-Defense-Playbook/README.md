# Past-Project Deep-Dive L7 Defense Playbook

A knowledge base for the **60-minute Past Project Technical Deep-Dive / Architecture Retrospective** round at L6/L7: presenting a real production architecture on a whiteboard and defending it against two skeptical Principal Engineers. The companies used as lenses are Google, Amazon, NVIDIA, Uber, Apple and Netflix.

**Integrity rule.** This playbook teaches you to present work you really did, at its true scope, as clearly and defensibly as possible. It never helps you claim decisions you didn't make. That is an ethical line. It is also the winning tactic: the round is designed to find where your knowledge stops, so a claim you can't defend at depth costs more than a smaller claim you can.

## Status

| Folder | Files | Status |
|---|---|---|
| `01-Anatomy-of-the-60-Minute-Deep-Dive-Round/` | 3 | **Done 2026-10-31.** Gate passed (below). |
| `02-The-3-Viable-Options-Tradeoff-Defense-Framework/` | 3 | Pending (next turn) |
| `03-Complete-L7-Whiteboard-Blueprints-for-4-Career-Archetypes/` | 4 | Pending |
| `04-Surviving-the-25-Brutal-Bar-Raiser-Cross-Examination-Questions/` | 3 | Pending |
| `05-Personal-Project-Dossier-Template-and-Stress-Test-Harness/` | 2 | Pending |

**Folder names.** The brief's role line describes the KB as running from `01-Anatomy-of-the-Deep-Dive-Round/` to `05-Interactive-Adversarial-Grilling-Scripts/`. Its repository blueprint uses the longer names above. This KB follows the blueprint names exactly.

## Folder 01: Anatomy of the 60-Minute Deep-Dive Round

| File | What it covers | Words | Listing |
|---|---|---|---|
| [01.1 Minute-by-minute whiteboard pacing](01-Anatomy-of-the-60-Minute-Deep-Dive-Round/01-minute-by-minute-whiteboard-pacing-strategy-from-context-to-internals.md) | What the round measures (7 signals, depth floor, two-interviewer dynamics); the 60-minute budget and checkpoints; the **P-0 Beacon** fact sheet; project selection matrix; board zones and notation; the C4 zoom ladder; phase-by-phase playbook; two scripted plans; interrupt handling; the cut order; depth wells; the numbers card; company lenses; rubric | ~19.5k | `pace_check.py` |
| [01.2 Architect or passenger?](01-Anatomy-of-the-60-Minute-Deep-Dive-Round/02-how-interviewers-test-if-you-were-the-architect-or-just-a-passenger.md) | Decision vs description knowledge; 14 passenger tells; 12 authorship probes; the ownership map (★/◆/○, ownership ledger, enterprise band, surgical highlight); I/we attribution grammar; scope integrity; evidence artifacts; the five-level self-test; the consistency web; rubric | ~11.7k | `ownership_lint.py` |
| [01.3 Framing constraints](01-Anatomy-of-the-60-Minute-Deep-Dive-Round/03-framing-constraints-legacy-tech-debt-client-politics-and-tight-deadlines.md) | Constraints as design inputs (six properties); the nine-column constraint ledger; legacy and debt (Chesterton, Hyrum, Fowler quadrant, migration patterns); stakeholder accountability maps and the demand-to-requirement conversion; consulting client constraints; deadline taxonomy, critical-path math, bounded shortcuts; red-flag language; rubric | ~11.1k | `constraint_check.py` |

Each file has 10 bar-raiser chains (Initial Prompt → L5 Answer → Why L5 Stalls → L7 Answer) and 6 paired L5/L7 tellings.

## The running exhibit: P-0 "Beacon"

Beacon is a **composite** configuration and feature-flag distribution platform:
- **Scale:** ~1,200 services, ~48,000 instances, 3 regions.
- **Migration:** it replaces a ZooKeeper ensemble and baked-in YAML before a hard colo-exit date.
- **Design:** signed, versioned, immutable snapshots; stateless relays; a fail-static SDK; ring-based rollout with automatic halt.

It was chosen because config propagation is one of the best-documented outage classes in public postmortems (Cloudflare 2025-11-18, Google Cloud 2025-06-12, CrowdStrike Channel File 291), and because it is distinct from the four archetypes in Folder 03. All of its numbers are placeholders, made internally consistent so the worked examples close arithmetically (01.2 §9). The full fact sheet is in [01.1 §3](01-Anatomy-of-the-60-Minute-Deep-Dive-Round/01-minute-by-minute-whiteboard-pacing-strategy-from-context-to-internals.md#3-the-running-exhibit-p-0-beacon-fact-sheet).

## Conventions

- **Scope labels:** L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff. Amazon's L7 is Principal; Google's and Meta's L7 is Senior Staff.
- **⚠** marks mechanics that are not publicly documented (reported patterns, composites, inferences). Company material is cited only from public primary pages: About Amazon on Bar Raisers, the Amazon Leadership Principles, Google re:Work on structured interviewing, and the Netflix culture memo.
- **Companies are domain lenses.** There are no leaked questions; every question is an original formulation.
- **Tellings** use `#### How an L5 tells it` / `#### How an L7 tells it` headings followed by `>` blockquotes. The lints extract them by that exact heading.
- **Chains** use `<details><summary><b>Qn · …</b></summary>` with the four bold labels in order.
- **Ownership marks:** ★ designed/led/wrote · ◆ reviewed/contributed/operated · ○ team or other, consumed.
- **Provenance labels for numbers:** [M] measured · [E] estimated from measured inputs · [D] design target.
- **Constraint ledgers** sit between `<!-- ledger:start name=… -->` and `<!-- ledger:end -->`, with nine columns (01.3 §2).
- **Whiteboard scripts** go in ```` ```script ```` fences, using `== mm:ss-mm:ss | Title`, `SAY:`, `DRAW:`, `ASK:` and `RESERVE:` lines (01.1 §8).
- Spelling is American.

## Tools (all Python 3, standard library only)

| Tool | Embedded in | Use on your own material |
|---|---|---|
| `pace_check.py` | 01.1 §8.3 | Write your plan in `script` notation, then run `python -I pace_check.py plan.md --wpm <your measured rate>` |
| `ownership_lint.py` | 01.2 §13.1 | Write your tellings under `#### How an L7 tells it` headings, then run `python -I ownership_lint.py dossier.md` |
| `constraint_check.py` | 01.3 §12.1 | Put your ledger between ledger markers, then run `python -I constraint_check.py dossier.md` |

Folder 05 will combine these tools into the dossier stress-test harness.

## Gate results

Folder 01 gate (`tools/gate.py --urls`, run on the final files):

| Check | Result |
|---|---|
| Structure: header listing table + Verification line; spine order; ≥ 8 chains with 4 labels; L5/L7 balance | 3/3 files pass: 10 chains each (30 in total), 6 pairs each (18 in total) |
| Listings byte-identical to the source that was run | 3/3 |
| Listing re-run on the final file reproduces the embedded output | 3/3 identical |
| `pace_check.py` verdicts | Plan A (L5) 6 flags; Plan B (L7) PASS |
| Lints across Folder 01: every L5 telling flagged by at least one lint; every L7 telling clean in both | L5 flagged 18/18; L7 clean 18/18 |
| Constraint ledgers | `l5-ledger` fails as intended (10 problems in 3 rows); `p0-beacon` passes (7 rows) |
| Relative links and anchors (3 files + README) | 20/20 OK |
| External URLs | 22/22 reachable |

**Source notes.**
- **Google's careers pages** ("how we hire", "interview tips") render without content for automated fetches, so Google's process is cited from its re:Work structured-interviewing guide instead.
- **CrowdStrike's RCA PDF** has no extractable text through the fetch tool. The 21-field / 20-input mismatch and the staged-deployment finding were verified by searching the PDF's decompressed content streams.
- **The Chesterton Society page** returns 403 to automated checks, so the fence parable is cited from the 1929 book.

**Refinements made during the build.**
1. `pace_check.py` gained two rules, CONTEXT-HEAVY (more than 7 min of context) and LATE-DEPTH (first deep dive after 20:00). Without them, a plan can be internally on-budget and still be a context dump.
2. The tools call `sys.stdout.reconfigure(encoding="utf-8")`, because `-I` ignores `PYTHONIOENCODING` and Windows pipes otherwise garble the en-dashes in headings.
3. EXCUSE now matches "wasn't my call" as well as "not my call".
4. One L7 telling was rephrased ("versions only increase" → "strictly monotonic"), because the lint's unquantified-claim rule can't tell the verb "increase" in an invariant from an improvement claim.
5. Exhibit consistency: the SDK ports are attributed to the language-platform teams in every file, so the team-capacity check in 01.2 §9 closes. The lease-extension price (~$190k/month, 6-month minimum) was added to the fact sheet because 01.3 relies on it.

## How to use this KB

1. Read Folder 01 in order: the clock, then authorship, then constraints.
2. Pick your project with the 01.1 §4 matrix and build your ownership ledger (01.2 §4.2) and constraint ledger (01.3 §2) as you read.
3. Write your plan in `script` notation and run `pace_check.py` until it passes at your measured speaking rate.
4. Rehearse with a partner who interrupts on purpose (01.1 §9), using the bar-raiser chains as their question bank.
5. Folders 02–05 add the trade-off framework, four archetype blueprints, the 25 hardest cross-examination questions, and your dossier and stress-test harness.
