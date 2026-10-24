# Roadmap: November 2026 → December 2027

> **Band:** all · **Priority:** 🔥 · **FAANG:** parallel track (§7) · **Prerequisites:** [rating tiers](01-rating-tiers-and-what-each-level-solves.md), [practice methodology](03-practice-methodology.md)
> **You can say you know this when:** you know your entry phase from a placement test, have a weekly schedule that fits your working week, and check measurable targets every quarter instead of watching your rating daily.

**Honesty first.** No source verified in this research says how long it takes to go from Specialist/Expert to Master, how many problems it needs,
or whether any particular schedule works better than another (see the open questions in [08](08-research-findings-and-sources.md)). The phase
lengths, month plan and checkpoints below are **this kit's plan** — a structured guess built from the syllabus data in
[rating tiers](01-rating-tiers-and-what-each-level-solves.md) and from the kind of practice structure strong competitors commonly describe. Treat
them as a default to adapt, not as a prediction. The goal is **Master-level capability** (§8 of rating tiers), not a number on a given date.

## 1. Self-placement (week 1)

Your current rating is unknown to this kit, and a rating from years ago is not informative. Measure instead:

1. **Virtual contest.** Pick a recent Codeforces **Div. 2** round you have not seen and run it as a *virtual participation* (full 2 hours, no
   editorial, no internet search for the problems). Record which letters you solve and when.
2. **Second data point.** One week later, do a recent **Educational** round or a second Div. 2 virtually. Use the better of the two only if they agree.
3. **Untagged band test (optional, 3–5 h).** From the Codeforces problemset, take 8 random unseen problems at rating $R$ (hide tags). If you solve
   at least 6 within about 45 minutes each, repeat at $R+200$. Your working level is the highest $R$ you pass.

| Virtual Div. 2 result | Working level (rough) | Start at |
|---|---|---|
| A only, or A–B slowly | below ~1200 | Phase A, from the beginning (all of 01) |
| A–B within an hour | ~1200–1400 | Phase A; skim 01, do 02 fully |
| A–C | ~1400–1700 | **Phase B** (default track below assumes this) |
| A–C fast, D sometimes | ~1700–1900 | Phase C |
| A–D, sometimes E | ~1900–2100 | Phase D |

The mapping uses the letter medians of the cf-stats table (Div. 2 B ≈ 1100, C ≈ 1400, D ≈ 1900, E ≈ 2400); it is a heuristic for choosing a starting
point, not a rating estimate.

## 2. Phases

| Phase | Performance target to leave the phase | Main folders | Typical length (plan, not prediction) |
|---|---|---|---|
| **0 · Setup** | environment works, placement done | [00/06](06-environment-templates-cpp-java.md), [00/05](05-first-principles-problem-solving.md) | 1–2 weeks |
| **A · Foundations** | Div. 2 A–B reliably; ~1400 | [01](../01-Foundations/README.md), [02](../02-Core-Techniques/README.md) | 1–2 months |
| **B · Expert core** | Div. 2 A–C reliably, D sometimes; ~1700–1900 | [03](../03-Greedy-Constructive-Interactive/README.md), [04](../04-Number-Theory/README.md) 01–05, [05](../05-Combinatorics-and-Probability/README.md) 01–03, [06](../06-Dynamic-Programming/README.md) 01–05, [08](../08-Data-Structures/README.md) 01–02/05–06, [09](../09-Graphs/README.md) 01–04, [10](../10-Trees/README.md) 01–02 | 3–4 months |
| **C · CM → Master core** | Div. 2 A–D reliably, Div. 1 A–B; ~2000–2100 | [06](../06-Dynamic-Programming/README.md) 06–10, [07](../07-DP-Optimizations/README.md) 01–04, [08](../08-Data-Structures/README.md) 03–04/07/10, [09](../09-Graphs/README.md) 05–10, [10](../10-Trees/README.md) 03–04, [11](../11-Strings/README.md) 01–05, [05](../05-Combinatorics-and-Probability/README.md) 04–07 | 3–4 months |
| **D · Master consolidation** | ~2100+ performance in half of rated rounds | [07](../07-DP-Optimizations/README.md) 05–08, [12](../12-Flows-and-Matching/README.md), [13](../13-Game-Theory/README.md), [14](../14-Geometry/README.md), [15](../15-Advanced-Math/README.md), [10](../10-Trees/README.md) 05–06, [11](../11-Strings/README.md) 06–09 | 3 months |
| **E · Peak + IGM depth** | sustain; Div. 1 C sometimes | [16](../16-IGM-Frontier/README.md), weak-topic sprints | remaining time |

Why this order: the tag shares in [rating tiers §6](01-rating-tiers-and-what-each-level-solves.md) grow for dp, data structures, graphs, trees and
combinatorics between 1900 and 2600, while greedy/math/constructive problems are present at every band. So phases B–C build the growing
topics in depth, and every phase keeps mixed ad-hoc practice. Specialist topics with small shares (flows, FFT, suffix structures) come last.

## 3. Default month-by-month plan (entry at Phase B, ~1400–1700)

Each month: **topic study** (read the kit file, re-derive the first-principles section, type the reference implementation from memory in both
languages), **topic ladder** (the file's practice ladder), **mixed untagged practice** at your level +0…+300, **contests + upsolving** every week.

| Month | Topic focus (kit files) | Problem-set backbone | Contest focus |
|---|---|---|---|
| **Nov 2026** | Phase 0; [01](../01-Foundations/README.md) review (complexity, STL, bits, overflow); [05 first principles](05-first-principles-problem-solving.md) | CSES Introductory, CSES Sorting and Searching (first half) | placement virtuals; first rated rounds |
| **Dec 2026** | [02 Core techniques](../02-Core-Techniques/README.md) (all six files) | CSES Sorting and Searching (rest) | Div. 2 / Educational weekly, ABC weekly |
| **Jan 2027** | [03](../03-Greedy-Constructive-Interactive/README.md) 01–04 (greedy, regret, constructive, invariants); [04](../04-Number-Theory/README.md) 01–03 | CF greedy/constructive 1400–1800 untagged | **Q1 checkpoint** (31 Jan) |
| **Feb 2027** | [06](../06-Dynamic-Programming/README.md) 01–05 (state design, knapsack, sequences, grids, intervals); [05](../05-Combinatorics-and-Probability/README.md) 01–03 | CSES Dynamic Programming; AtCoder DP contest A–N | |
| **Mar 2027** | [08](../08-Data-Structures/README.md) 01, 02, 05, 06 (Fenwick, segment tree, sparse table, DSU); [09](../09-Graphs/README.md) 01–04 | CSES Range Queries (first half), CSES Graph Algorithms (first half) | attempt Div. 2 D in every round |
| **Apr 2027** | [10](../10-Trees/README.md) 01–02 (Euler tour, LCA); [09](../09-Graphs/README.md) 05, 06, 09, 10; [04](../04-Number-Theory/README.md) 04–05 | CSES Tree Algorithms; CSES Graph Algorithms (rest) | **Q2 checkpoint** (end of Apr) |
| **May 2027** | [06](../06-Dynamic-Programming/README.md) 06–10 (bitmask, digit, tree DP, DAG DP, expected value); [05](../05-Combinatorics-and-Probability/README.md) 04, 06, 07 | AtCoder DP contest O–Z; CSES Counting | Div. 1 + 2 rounds whenever available |
| **Jun 2027** | [08](../08-Data-Structures/README.md) 03, 04, 07, 10 (lazy, segment-tree descent, sqrt/Mo, ordered sets); [11](../11-Strings/README.md) 01–05 | CSES Range Queries (rest), CSES String Algorithms (first half) | |
| **Jul 2027** | [07](../07-DP-Optimizations/README.md) 01–04, 08; [10](../10-Trees/README.md) 03–04 (small-to-large, HLD); [09](../09-Graphs/README.md) 07–08 | CF dp/data structures 1900–2200 untagged | **Q3 checkpoint** (end of Jul) |
| **Aug 2027** | [12](../12-Flows-and-Matching/README.md) 01–03; [11](../11-Strings/README.md) 06–07; [03](../03-Greedy-Constructive-Interactive/05-interactive-problems.md) interactive; [13](../13-Game-Theory/README.md) 01–02 | CSES Advanced Graph (selected), CSES Interactive | virtual Div. 1 rounds weekly |
| **Sep 2027** | [15](../15-Advanced-Math/README.md) 01–03 (matrices, Gauss/XOR basis, FFT/NTT); [10](../10-Trees/README.md) 05–06; [14](../14-Geometry/README.md) 01–04; [07](../07-DP-Optimizations/README.md) 05–07 | CSES Mathematics (selected), CSES Geometry (first half) | |
| **Oct 2027** | [16](../16-IGM-Frontier/README.md) 01, 02, 04, 05, 07; [08](../08-Data-Structures/README.md) 08–09; [11](../11-Strings/README.md) 08–09; [12](../12-Flows-and-Matching/README.md) 04–06 | CSES Advanced Techniques; USACO Guide Platinum modules | **Q4 checkpoint** (end of Oct) |
| **Nov 2027** | weak-topic sprints from your journal; [15](../15-Advanced-Math/README.md) 04–06; [16](../16-IGM-Frontier/README.md) 03, 06 | mixed 2000–2400 untagged | maximum contest volume; virtual Div. 1 + 2 |
| **Dec 2027** | maintenance: cheat-sheet review ([99](../99-Cheat-Sheets/01-foundations-cheatsheet.md) …), upsolving | mixed | final assessment (§5) |

**Other entry points.** Entering at Phase A: add one month at the start (Nov: 01; Dec: 02 + CSES Introductory) and shift everything by a month,
merging the Sep/Oct topic blocks if needed (the 🧊 items in 15/16 are the first to drop). Entering at Phase C or D: start the table at Mar or Jun
2027 respectively and use the freed months for more contests and the IGM-frontier folder.

## 4. Weekly schedule templates (working engineer)

The split below follows one principle (an opinion, consistent with the practice advice summarised in [practice methodology](03-practice-methodology.md)):
**most of the time goes to solving and upsolving problems slightly above your level; topic reading is a minority of the week.**

| Activity | 10 h / week | 15 h / week | 20 h / week |
|---|---|---|---|
| Rated contests (CF and/or AtCoder) | 1 × 2 h = 2 h | 2 contests ≈ 3.5 h | 2–3 contests ≈ 5 h |
| Upsolving those contests | 2 h | 3 h | 4 h |
| Topic study (kit file + implementing it in both languages) | 2 h | 3 h | 3.5 h |
| Topic ladder problems | 2.5 h | 3 h | 4 h |
| Mixed untagged practice / virtual contest | 1 h | 2 h | 2.5 h |
| Cheat-sheet review, idea journal | 0.5 h | 0.5 h | 1 h |
| **Total** | **10 h** | **15 h** | **20 h** |

Example 10-hour week: Mon 1 h topic reading · Tue 1 h ladder · Wed 1 h ladder · Thu 1 h topic implementation · Sat 2 h rated contest + 1 h upsolve ·
Sun 1 h upsolve + 1 h ladder + 1 h mixed/journal. Keep one weekday fully off.

With 15–20 hours, add the second contest (an AtCoder ABC is a good second contest until ~1900; ARC afterwards) and a weekly virtual round. If a
contest falls at an impossible time, do it as a virtual participation within a few days — the value is in the timed attempt plus upsolving, not
in the rating change.

## 5. Contest calendar habits and quarterly checkpoints

**Calendar habits** (round times are standard knowledge, not verified in this research — check the sites):

- **Codeforces**: several rounds per week of mixed types. Register early; pick by division (below 1900: Div. 2 / Div. 3 / Educational /
  Div. 1 + 2; from 2100: Div. 1, Div. 1 + 2, Global). Codeforces rounds commonly start at 17:35 Moscow time (14:35 UTC); times vary.
- **AtCoder**: Beginner Contest (ABC) roughly weekly, usually Saturday or Sunday at 21:00 JST (12:00 UTC); Regular Contest (ARC) some weeks;
  Grand Contest (AGC) occasionally. ABC trains speed and clean implementation; ARC trains the ad-hoc/constructive thinking that Codeforces
  Div. 1 B–C demands.
- **Fixed slots beat motivation**: decide your two contest slots per week at the start of each month.
- **Never skip upsolving**: a contest without upsolving is mostly a rating lottery.

**Quarterly checkpoints** (this kit's targets; measure with the Codeforces API as in [practice methodology §8](03-practice-methodology.md)).
"Solved" means solved by you (accepted), including upsolving with at most a hint.

| Checkpoint | Volume | At level | Contest performance |
|---|---|---|---|
| **Q1 — 31 Jan 2027** | ≥ 150 problems since 1 Nov 2026 | ≥ 50 rated 1400–1700; CSES Introductory + Sorting and Searching ≥ 80% | Div. 2 A–C within 75 min in 3 of the last 4 Div. 2 (virtual counts); performance ≥ 1600 in half of rated rounds |
| **Q2 — 30 Apr 2027** | ≥ 350 total | ≥ 80 rated 1700–1900; CSES DP ≥ 15/23, Graph ≥ 20/36 | Div. 2 D solved in ≥ 40% of Div. 2 rounds; performance ≥ 1800 in half of rated rounds |
| **Q3 — 31 Jul 2027** | ≥ 550 total | ≥ 100 rated 1900–2100 | Div. 2 A–D in ≥ 60% of Div. 2 rounds; performance ≥ 2000 in half of rated rounds |
| **Q4 — 31 Oct 2027** | ≥ 750 total | ≥ 80 rated 2100–2400 | Div. 1 A–B in most Div. 1 rounds (virtual counts); performance ≥ 2100 in at least 3 of the last 8 rated rounds |
| **Final — Dec 2027** | — | — | performance ≥ 2100 in at least half of the last 8–10 rated rounds (Master capability per [rating tiers §8](01-rating-tiers-and-what-each-level-solves.md)) |

Why performance and not rating: rating is a lagging average and moves slowly at first; performance in individual rounds shows capability earlier.
Problem counts are inputs, not goals — 100 problems with honest struggle and upsolving beat 300 easy ones.

## 6. What to do when you are behind

Diagnose before changing the plan. Look at the last 6–8 contests and the last month of practice:

| Symptom | Diagnosis | Change |
|---|---|---|
| You solve $R+200$ problems in practice but perform at $R-200$ in contests | speed, nerves, contest strategy | more timed virtuals; [contest strategy](04-contest-strategy-and-mindset.md); set a per-problem time box |
| You cannot solve $R+200$ problems even with 2 hours | idea generation | more problems at $R$…$R+200$ with the [framework](05-first-principles-problem-solving.md); stricter upsolving protocol; hide tags |
| You know the idea but implementation takes too long / has bugs | implementation fluency | re-type reference implementations from memory; template snippets; stress testing habit |
| You fail on one topic repeatedly (e.g. DP) | knowledge gap | a 2-week sprint on that folder's ladder; postpone the next new topic |
| Practice hours keep falling below plan | schedule does not fit life | drop to the 10-hour template; protect the contest + upsolve slots first |
| Everything feels flat for 2+ months | plateau (common, not failure) | change problem source (AtCoder ARC, CSES sections), review the idea journal, rest a week |

Rules: **cut breadth, not depth** — drop 🧊 items and the later folders first, never the upsolving; **extend phases rather than skipping
them**; and if the December 2027 target becomes unrealistic, move the date rather than lowering the standard of practice.

## 7. Parallel FAANG track

The algorithmic core of FAANG interviews is a subset of phases A–C (arrays, hashing, two pointers, binary search, trees, graphs, DP, heaps,
backtracking). What CP does **not** train: talking through a solution, clean production-style code under observation, and interview-specific
patterns (linked lists, design problems). The kit's plan for that is in [FAANG preparation plan](../17-FAANG-Interview-DSA/20-faang-preparation-plan.md),
built around Grind 75 / Grind 169 (verified as Yangshun Tay's list, see [resources](07-resources-and-problem-sets.md)).

Suggested integration (opinion): 1 hour per week from the start (one Grind 75 problem solved out loud, with complexity analysis), rising to
4–6 hours per week for the 6–8 weeks before real interviews, taken from the "mixed practice" and "topic ladder" rows of §4. The CP-to-interview mapping
is in [CP → interview mapping](../17-FAANG-Interview-DSA/19-cp-to-interview-mapping.md).

## 8. Self-check

1. Which two contest types do you use for placement, and why a virtual participation rather than a rated round?
2. In the 10-hour template, which two activities together take 40% of the time?
3. What is the Q3 checkpoint in terms of contest performance?
4. You perform 300 points below your practice level. Which file do you study, and what do you change in your week?
5. Why does the plan put flows, FFT and suffix structures in the last phases?

<details><summary>Answers</summary>

1. A recent Div. 2 and an Educational (or a second Div. 2); a virtual gives a full timed attempt now, on unseen problems, without waiting for a schedule and without rating pressure.
2. Rated contests (2 h) and their upsolving (2 h).
3. Div. 2 A–D in at least 60% of Div. 2 rounds and performance ≥ 2000 in half of the rated rounds.
4. [Contest strategy](04-contest-strategy-and-mindset.md); add timed virtual contests and per-problem time boxes.
5. Their tag shares are small below 2400 (flows 1.1% at 1900–2099, fft 0.4%) and grow mainly beyond 2400, while dp/data structures/graphs/trees dominate the 1900–2400 growth.

</details>
