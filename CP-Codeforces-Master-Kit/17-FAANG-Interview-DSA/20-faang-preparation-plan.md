# FAANG Preparation Plan (alongside the CP Roadmap)

> **Band:** all · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [README](README.md), [master list](18-leetcode-master-list.md), [CP roadmap](../00-Roadmap-and-Strategy/02-roadmap-nov-2026-to-dec-2027.md)
> **You can say you know this when:** you follow a weekly schedule that keeps CP progress on track and adds interview practice, you can switch to the 8–12 week sprint the moment an interview is booked, and your mock-interview scores show all four signals at "hire" level.

Two plans are given. The **long plan** runs from November 2026 to December 2027 next to the CP roadmap, spending a small, fixed slice of each week on interview-specific work. The **sprint** is a focused 8–12 week block for when an interview loop is scheduled. Both use the same tools: the pattern files of this folder, the [master list](18-leetcode-master-list.md) with its checkboxes, timed mock interviews, and spaced review with the [cheat sheet](../99-Cheat-Sheets/17-faang-interview-cheatsheet.md).

Time budgets below are this kit's suggestions for a working engineer, not measured data. Scale them to your week.

## 1. First principles — why the plan looks like this

1. **CP training covers most of the algorithmic load.** The interview pool is narrow (335 problems across five lists) and sits mostly in the 🟢/🔵 bands ([file 19](19-cp-to-interview-mapping.md)). The interview-specific work is therefore *coverage of the classic problems*, *presentation*, and *design-style classes*, not new algorithms.
2. **Presentation is a separate skill** and only improves with practice under observation. Hence the weekly mock interviews, which are the part people most often skip.
3. **Spacing beats cramming.** Re-solving a problem after a gap of days or weeks is more effective than solving it twice on the same day; the spacing effect is a well-replicated finding in learning research. Hence the review schedule in §6.
4. **Interleaving patterns** (mixing problem types in a session) trains recognition, the skill that the first two minutes of an interview depend on. The long plan learns patterns in blocks first, then switches to mixed sets.

## 2. Weekly template for the long plan (about 3–5 interview hours per week)

| Day | CP (main track) | Interview track |
|---|---|---|
| Mon | CP topic study (roadmap) | — |
| Tue | CP practice ladder | **45 min:** 1–2 problems of the current pattern file, solved with the full [framework](01-interview-framework-and-communication.md), spoken aloud |
| Wed | CP topic study | — |
| Thu | CP practice ladder | **45 min:** 1–2 problems, or one design class from [file 17](17-design-problems.md) |
| Sat | Codeforces round + upsolving | — |
| Sun | CP review | **60–90 min:** spaced re-solves (§6) + one mock interview every other week (§5) |

Rule: one interview problem per session is written as clean class code with a complexity statement, even when the CP version is already in your head.

## 3. The long plan: November 2026 → December 2027

The CP column mirrors the month table of the [CP roadmap §3](../00-Roadmap-and-Strategy/02-roadmap-nov-2026-to-dec-2027.md) (folder numbers, with file numbers after the slash); if you shift the roadmap, shift this column with it. The interview column deliberately keeps Grind 75's own order instead of chasing the CP topic of the month; [file 19](19-cp-to-interview-mapping.md) shows which interview files pair with which CP folders. "G75 weeks" refers to the 8-week Grind 75 schedule in [18 §4](18-leetcode-master-list.md).

| Month | CP focus (kit folder) | Interview files | Problems (from [18](18-leetcode-master-list.md)) | Mocks |
|---|---|---|---|---|
| Nov 2026 | Setup + [01](../01-Foundations/README.md) review, [first principles](../00-Roadmap-and-Strategy/05-first-principles-problem-solving.md) | [01](01-interview-framework-and-communication.md), [02](02-arrays-hashing-and-prefix-sums.md), [03](03-two-pointers-and-sliding-window.md) | G75 weeks 1–2 | 1 (baseline, recorded) |
| Dec 2026 | [02](../02-Core-Techniques/README.md) core techniques (all) | [04](04-stacks-and-monotonic-stacks.md), [05](05-binary-search.md) | G75 weeks 3–4 | 2 |
| Jan 2027 | [03/01–04](../03-Greedy-Constructive-Interactive/README.md) greedy/constructive, [04/01–03](../04-Number-Theory/README.md) | [06](06-linked-lists.md), [07](07-trees-and-bst.md), [15](15-greedy-and-intervals.md) | G75 weeks 5–6 | 2 |
| Feb 2027 | [06/01–05](../06-Dynamic-Programming/README.md) DP basics, [05/01–03](../05-Combinatorics-and-Probability/README.md) | [13](13-dynamic-programming-1d.md), [14](14-dynamic-programming-2d.md) | G75 weeks 7–8 (**Grind 75 complete**) | 2 |
| Mar 2027 | [08/01,02,05,06](../08-Data-Structures/README.md) Fenwick/segtree/DSU, [09/01–04](../09-Graphs/README.md) | [11](11-graphs.md), [12](12-advanced-graphs.md) | `NC150` graph and tree problems not yet solved | 2 |
| Apr 2027 | [10/01–02](../10-Trees/README.md) Euler tour/LCA, [09/05,06,09,10](../09-Graphs/README.md), [04/04–05](../04-Number-Theory/README.md) | [09](09-heaps-and-top-k.md), [08](08-tries.md), [17](17-design-problems.md) | `NC150` heaps/tries/design + all design examples | 2 |
| May 2027 | [06/06–10](../06-Dynamic-Programming/README.md) advanced DP, [05/04,06,07](../05-Combinatorics-and-Probability/README.md) | [10](10-backtracking.md), [16](16-math-geometry-and-bit-manipulation.md) | rest of `NC150` (**NeetCode 150 complete**) | 2 |
| Jun 2027 | [08/03,04,07,10](../08-Data-Structures/README.md) lazy/descent/Mo, [11/01–05](../11-Strings/README.md) | mixed review | `G169` problems, first half (mixed order) | 3 |
| Jul 2027 | [07/01–04,08](../07-DP-Optimizations/README.md) DP optimisations, [10/03–04](../10-Trees/README.md), [09/07–08](../09-Graphs/README.md) | [17](17-design-problems.md) follow-ups | `G169`, second half (**Grind 169 complete**) | 3 |
| Aug 2027 | [12/01–03](../12-Flows-and-Matching/README.md) flows, [11/06–07](../11-Strings/README.md), [13/01–02](../13-Game-Theory/README.md) | [19](19-cp-to-interview-mapping.md) rewrite drill | `TI150`-only problems (implementation-heavy array/string work) | 3 |
| Sep 2027 | [15/01–03](../15-Advanced-Math/README.md), [10/05–06](../10-Trees/README.md), [14/01–04](../14-Geometry/README.md), [07/05–07](../07-DP-Optimizations/README.md) | weakest two patterns | `NC250`-only problems in the weakest patterns | 4 |
| Oct 2027 | [16/01,02,04,05,07](../16-IGM-Frontier/README.md), [08/08–09](../08-Data-Structures/README.md), [11/08–09](../11-Strings/README.md), [12/04–06](../12-Flows-and-Matching/README.md) | all cheat-sheet sections | timed mixed sets: 2 Mediums in 45 minutes | 4 |
| Nov 2027 | weak-topic sprints, [15/04–06](../15-Advanced-Math/README.md), [16/03,06](../16-IGM-Frontier/README.md) | maintenance | 3 mixed problems per week + re-solves | 2–4 |
| Dec 2027 | Master push (contests), cheat-sheet review | maintenance | re-solve all `G75` once | 2 |

By the end of May 2027 this covers Grind 75 and NeetCode 150 (167 distinct problems in the fetched lists), which is the core most candidates aim for. June–October extend it to all 335 problems at a low weekly cost.

## 4. The sprint: 8–12 weeks before an interview loop

Switch to this when interviews are booked. CP drops to one contest per week to keep the rating, and the interview track gets **10–15 hours per week**. The 12-week version is below. For 8 weeks, merge weeks 1–2, 5–6, 9–10 and 11–12.

| Week | Patterns (read §1 and §5 of each file again) | Problems | Mocks | Other |
|---|---|---|---|---|
| 1 | [02](02-arrays-hashing-and-prefix-sums.md), [03](03-two-pointers-and-sliding-window.md) | G75 week 1 + `NC150` of these patterns | 1 (baseline) | re-read [01](01-interview-framework-and-communication.md) |
| 2 | [04](04-stacks-and-monotonic-stacks.md), [05](05-binary-search.md) | G75 week 2 + `NC150` of these | 1 | |
| 3 | [06](06-linked-lists.md), [07](07-trees-and-bst.md) | G75 week 3 + `NC150` trees | 1 | |
| 4 | [07](07-trees-and-bst.md), [08](08-tries.md) | G75 week 4 + rest of trees | 2 | |
| 5 | [09](09-heaps-and-top-k.md), [15](15-greedy-and-intervals.md) | G75 week 5 + `NC150` of these | 2 | |
| 6 | [10](10-backtracking.md), [11](11-graphs.md) | G75 week 6 + `NC150` of these | 2 | |
| 7 | [12](12-advanced-graphs.md), [13](13-dynamic-programming-1d.md) | G75 week 7 + `NC150` 1D DP | 2 | |
| 8 | [14](14-dynamic-programming-2d.md), [16](16-math-geometry-and-bit-manipulation.md) | G75 week 8 + `NC150` 2D DP | 2 | Grind 75 done |
| 9 | [17](17-design-problems.md) | all 10 design examples, then `G169` design problems | 2 | company-tagged practice if you have access |
| 10 | weakest 3 patterns (from mock scores) | `G169` / `NC150` of those patterns | 3 | |
| 11 | mixed | timed sets: 2 problems in 45 minutes, unseen problems only | 3 | |
| 12 | review | re-solve every `G75` problem you ticked late or with hints | 2 | light week; sleep before the loop |

Daily rhythm during the sprint (opinion, adjust freely): one new problem, one re-solve from the review queue, ten minutes on the cheat sheet. Time-box new problems to 25 minutes (Easy) or 40 minutes (Medium). If stuck, read the solution, close it, and re-implement it from scratch the same day, then queue it for review.

## 5. Mock interviews

A mock is 45 minutes with a partner (a friend, a colleague, or a mock-interview service) acting as the interviewer, or, as a fallback, a recorded solo session where you speak as if someone were listening.

**Format:** 5 min intro → 30–35 min for one Medium (or a Medium plus a follow-up) → 5 min of your questions → 5 min feedback. The interviewer picks an **unseen** problem from a pattern you have studied.

**Scoring rubric** (score 1–4 per signal after each mock, and track the trend):

| Signal | 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| Problem solving | no working approach | brute force only | optimal with hints | optimal independently, with trade-offs |
| Coding | does not run | major bugs | minor bugs, clean structure | clean, idiomatic, correct |
| Verification | no testing | tests only when asked | traces one example | traces examples and edge cases, finds own bugs |
| Communication | silent | narrates code only | explains plan and complexity | collaborative, responds well to hints |

Aim for 3+ on every signal in three consecutive mocks before the real loop. Write one sentence per signal after each mock ("Verification: forgot the empty input again") and turn the most frequent miss into the focus of the next week.

## 6. Spaced review

Use the checkboxes of [18](18-leetcode-master-list.md) as the record of first solves, and keep a small review log (a spreadsheet is enough) with: problem, pattern, date solved, *needed hints?*, next review date, result.

| After a solve that was… | Review again after |
|---|---|
| independent and clean | 7 days, then 30 days |
| with hints or bugs | 2 days, 7 days, then 30 days |
| failed (read the solution) | next day, then 3, 7 and 30 days |

A review is a **re-solve from a blank editor** in at most 15 minutes, not a re-read. If it fails, the problem restarts the "failed" row. Before each mock and before the real loop, read the relevant cheat-sheet sections: the "signal → pattern" table and the templates.

## 7. Readiness checklist (before an interview loop)

- [ ] every `G75` problem solved independently at least once, and re-solved after a gap
- [ ] every pattern file's worked examples re-implemented from memory in your interview language
- [ ] all ten design classes from [file 17](17-design-problems.md) written from scratch in under 25 minutes each
- [ ] three consecutive mocks at 3+ on all four signals
- [ ] the [cheat sheet](../99-Cheat-Sheets/17-faang-interview-cheatsheet.md) "top 10 mistakes" list read the day before
- [ ] behavioural preparation done separately (out of scope for this kit)

## 8. Pitfalls and things to remember

1. **Do not let interview prep displace CP entirely during the long plan.** 3–5 hours per week is enough there; the sprint is the time to invert the ratio.
2. **Counting solved problems is a vanity metric.** Re-solves and mock scores predict interview performance better than a total.
3. **Skipping mocks is the most common failure** of strong competitive programmers. The framework only becomes automatic under observation.
4. **Unseen problems only** in mocks and timed sets. Re-solving a known problem measures memory, not skill.
5. **Pick one interview language and stay with it.** Switching between C++ and Java in the last month costs fluency. (This kit gives both so either choice is covered.)

## 9. CP counterpart

- [CP roadmap Nov 2026 → Dec 2027](../00-Roadmap-and-Strategy/02-roadmap-nov-2026-to-dec-2027.md) and [practice methodology](../00-Roadmap-and-Strategy/03-practice-methodology.md): the main track this plan runs beside.
- [CP → interview mapping](19-cp-to-interview-mapping.md): which CP month feeds which interview pattern.

## 10. Self-check

1. How many interview hours per week does the long plan use, and what are they spent on?
2. What changes in the sprint, and how do you compress it to 8 weeks?
3. What are the four mock-interview signals, and what score pattern means "ready"?
4. What counts as a review, and when is a problem reviewed after a failed attempt?

<details><summary>Answers</summary>

1. About 3–5 hours: two 45-minute pattern sessions and one longer weekend session of re-solves plus a mock every other week.
2. The interview track grows to 10–15 hours per week while CP drops to one contest per week. The 8-week version merges weeks 1–2, 5–6, 9–10 and 11–12.
3. Problem solving, coding, verification, communication. Ready means 3 or more on every signal in three consecutive mocks.
4. A timed re-solve from a blank editor (at most 15 minutes), not re-reading. After a failure: the next day, then after 3, 7 and 30 days.

</details>
