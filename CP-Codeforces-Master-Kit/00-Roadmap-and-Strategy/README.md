# 00 · Roadmap and Strategy

This folder is the operating manual of the kit: what the target means in measurable terms, how to get there between November 2026 and
December 2027 while working full time, how to practise and compete, how to think about a problem you have never seen, how to set up
C++ and Java on Windows 11, which external resources to use, and the evidence behind all of it.

## The domain from first principles

Getting to Master-level capability is an optimisation problem with three variables:

1. **What you can solve** — the syllabus. The kit's Codeforces API analysis shows which topics grow between 1900 and 2600 (dp, data structures,
   graphs, trees, combinatorics, divide and conquer, probabilities) and which stay important at every level (math, constructive algorithms,
   greedy — ad-hoc thinking never stops mattering). → [01](01-rating-tiers-and-what-each-level-solves.md)
2. **How you turn time into ability** — practice at the right difficulty, honest struggle, upsolving, journaling, spaced repetition. Most of this
   is opinion rather than settled fact, and the files say so. → [03](03-practice-methodology.md), [05](05-first-principles-problem-solving.md)
3. **How ability shows up as performance** — speed, problem selection, penalties, nerves, and an environment that never fails you.
   → [04](04-contest-strategy-and-mindset.md), [06](06-environment-templates-cpp-java.md)

The [roadmap](02-roadmap-nov-2026-to-dec-2027.md) schedules all three over 14 months with quarterly, measurable checkpoints, and is explicit that its
timelines are a plan, not a verified prediction.

## Files

| File | Band | Priority | FAANG | One-line summary |
|---|---|---|---|---|
| [01 · Rating tiers & what each level solves](01-rating-tiers-and-what-each-level-solves.md) | all | 🔥 | none | verified title bands and division rules; letter-by-letter rating table and topic mix by band computed from the Codeforces API |
| [02 · Roadmap Nov 2026 → Dec 2027](02-roadmap-nov-2026-to-dec-2027.md) | all | 🔥 | parallel track | placement test, phases A–E, month-by-month plan over folders 01–16, weekly templates (10/15/20 h), checkpoints, what to do when behind |
| [03 · Practice methodology](03-practice-methodology.md) | all | 🔥 | medium | problem selection, time boxes (opinions), editorial protocol, idea journal, spaced repetition, untagged practice, API progress scripts, burnout |
| [04 · Contest strategy & mindset](04-contest-strategy-and-mindset.md) | all | 🔥 | low | scoring and penalty maths (verified rules), first 30 minutes, skip rules, multi-test bugs, hacks, Div. 1 strategy, post-contest routine, tilt |
| [05 · First-principles problem solving](05-first-principles-problem-solving.md) | all | 🔥 | high | a 10-step framework, the simplification toolbox, six worked examples (1200–2100) in C++ and Java, a checklist of questions |
| [06 · Environment & templates](06-environment-templates-cpp-java.md) | all | 🔥 | low | what Codeforces runs, C++/Java templates, debug macros, local debug builds on Windows, tested stress scripts (Git Bash and PowerShell), generators, VS Code |
| [07 · Resources & problem sets](07-resources-and-problem-sets.md) | all | ⚡ | high (§5) | CSES (400 problems, 18 sections), CP-Algorithms and its gaps, USACO Guide Platinum/Advanced, Grind 75/169, standard resources, which one when |
| [08 · Research findings & sources](08-research-findings-and-sources.md) | all | ⚡ | low | every verified claim, caveats, refuted claims, open questions, the cf-stats method and full tables, extra checks, full source list |

## Prerequisites

None. Read this folder first, then start [01-Foundations](../01-Foundations/README.md) (or wherever the placement test in
[02 §1](02-roadmap-nov-2026-to-dec-2027.md) puts you).

## Recommended order

1. **Day 1:** [06](06-environment-templates-cpp-java.md) — install, compile both templates, run the stress script once.
2. **Day 2:** [01](01-rating-tiers-and-what-each-level-solves.md) and [02](02-roadmap-nov-2026-to-dec-2027.md) — understand the target, do the
   placement virtual contest, pick a weekly template.
3. **Week 1:** [05](05-first-principles-problem-solving.md) — work through the six examples *before* reading their solutions.
4. **Week 1–2:** [03](03-practice-methodology.md) and [04](04-contest-strategy-and-mindset.md) — set up the journal and your contest rules.
5. **As needed:** [07](07-resources-and-problem-sets.md), [08](08-research-findings-and-sources.md).
6. **Every quarter:** re-read 01 §5–8 and the checkpoints in 02 §5.

## Ten numbers to remember from this folder

| Number | Meaning | Source |
|---|---|---|
| 2100 | Master floor (since May 2018); Div. 2 and Educational rounds are rated only below it | verified ([01](01-rating-tiers-and-what-each-level-solves.md)) |
| 1900 | Div. 1 / Div. 2 split in parallel rounds; Candidate Master floor | verified |
| 2400 / 2600 | Grandmaster / International Grandmaster floors | verified |
| 1900 / 2400 | median rating of Div. 2 D / Div. 2 E (2023–2026) | computed from the Codeforces API |
| 1300 / 1900 / 2300 | median rating of Div. 1 A / B / C (2023–2026) | computed from the Codeforces API |
| 16–22% | share of problems tagged constructive in *every* rating band | computed from the Codeforces API |
| 30.9% → 36.4% | dp share from 1900–2099 to 2400–2599 (data structures 24.3% → 30.7%) | computed from the Codeforces API |
| $X/250$ per minute, 50 per WA | standard-round scoring decay and penalty | verified (contest rules) |
| 256 MB | C++ stack on Codeforces (`--stack=268435456`) | verified (command-lines post) |
| 400 / 18 | CSES problems / sections | verified |

## How this folder shows up in Div. 2 / Div. 1 rounds

Directly, it does not — no problem is tagged "strategy". Indirectly it decides most of your rating at 1600–2100: performance comes from rank, and
rank among people who solve the same problems is decided by speed and penalties ([04 §1–2](04-contest-strategy-and-mindset.md)); and the problems
that separate ratings are ad-hoc ones that the framework of [05](05-first-principles-problem-solving.md) targets. After you cross 2100 you are rated only
in Div. 1, Div. 1 + 2 and Global rounds, where Div. 1 B (median rating 1900) and C (median 2300) decide most results
([01 §4–5](01-rating-tiers-and-what-each-level-solves.md)).

## Problems and cheat sheets

This folder has no `problems.md` of its own: the practice problems for its worked examples are in
[05 · First-principles problem solving](05-first-principles-problem-solving.md), and the problem sets are organised by topic in folders 01–17
(start with [01-Foundations problems](../01-Foundations/problems.md)). Revision material lives in the cheat-sheet folder, starting with the
[foundations cheat sheet](../99-Cheat-Sheets/01-foundations-cheatsheet.md), whose "last-minute before contest" list complements
[04](04-contest-strategy-and-mindset.md).
