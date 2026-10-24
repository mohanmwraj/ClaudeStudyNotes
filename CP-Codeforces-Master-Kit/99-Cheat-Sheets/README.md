# 99 · Cheat Sheets — revise and remember

One sheet per topic folder, plus a master formula sheet. The sheets are for **revision, not learning**: each one compresses a folder into
formulas, "signal → technique" tables, short templates in **C++ and Java**, the ten mistakes that cost the most verdicts, and a last-minute list.
Every line links back to the topic file that derives it — when something on a sheet doesn't feel obvious, that is the file to re-read.

All template code on these sheets compiles as written (checked with g++ 16.2 `-std=c++20` and JDK 21 when the kit was built).

## The sheets

| Sheet | Folder | What's on it | Re-read when |
|---|---|---|---|
| [00 · Master formula sheet](00-master-formula-sheet.md) | all | every formula, identity, theorem and constant in the kit, by area | before **every** contest (10 min) |
| [01 · Foundations](01-foundations-cheatsheet.md) | [01](../01-Foundations/README.md) | constraint → complexity table, sums and recurrences, memory, overflow, exact division, bits, C++ ↔ Java containers, sorting | first month; then whenever you TLE/WA on "easy" bugs |
| [02 · Core techniques](02-core-techniques-cheatsheet.md) | [02](../02-Core-Techniques/README.md) | prefix sums & differences, binary search invariants, two pointers, monotonic stack/deque, sweep, ternary search, meet in the middle | before Div. 2 / Div. 3 rounds |
| [03 · Greedy, constructive, interactive](03-greedy-constructive-interactive-cheatsheet.md) | [03](../03-Greedy-Constructive-Interactive/README.md) | proof toolkit, exchange-argument comparators, interval and regret patterns, constructive toolkit, invariant checklist, XOR/MEX, interactive protocol | before every round — ad-hoc thinking matters at every rating |
| [04 · Number theory](04-number-theory-cheatsheet.md) | [04](../04-Number-Theory/README.md) | gcd/Bezout, modular rules and inverses, sieves, φ/μ, CRT, Miller–Rabin, floor blocks, constants (divisor bounds, prime counts) | when a statement says "modulo" or "divisible" |
| [05 · Combinatorics & probability](05-combinatorics-and-probability-cheatsheet.md) | [05](../05-Combinatorics-and-Probability/README.md) | binomial identities, twelvefold way, inclusion–exclusion, Catalan/Stirling/Bell, Burnside, expectation, contribution technique | before Div. 1 + 2 and Educational rounds |
| [06 · Dynamic programming](06-dynamic-programming-cheatsheet.md) | [06](../06-Dynamic-Programming/README.md) | state design in 9 lines, semirings, signal → DP type, recurrences with costs, evaluation orders, templates | weekly from Feb 2027 |
| [07 · DP optimisations](07-dp-optimizations-cheatsheet.md) | [07](../07-DP-Optimizations/README.md) | validity conditions for monotone-queue, CHT/Li Chao, divide & conquer, Knuth, SOS, Aliens, slope trick, matrix power | when a DP is one factor of $n$ too slow |
| [08 · Data structures](08-data-structures-cheatsheet.md) | [08](../08-Data-Structures/README.md) | structures at a glance, signal → structure, Fenwick/segment tree/lazy/DSU/sparse table/Mo/treap templates | before every round from Mar 2027 |
| [09 · Graphs](09-graphs-cheatsheet.md) | [09](../09-Graphs/README.md) | BFS/DFS variants, shortest paths, MST, topo sort, SCC, bridges, 2-SAT, Euler paths, functional graphs | when the input is "n vertices, m edges" |
| [10 · Trees](10-trees-cheatsheet.md) | [10](../10-Trees/README.md) | Euler tour, LCA/binary lifting, small-to-large, HLD, centroid decomposition, virtual trees | when the input is "a tree on n vertices" |
| [11 · Strings](11-strings-cheatsheet.md) | [11](../11-Strings/README.md) | hashing, prefix function, Z, Manacher, tries, Aho–Corasick, suffix array, suffix automaton, eertree | string-heavy rounds; before ICPC-style sets |
| [12 · Flows & matching](12-flows-and-matching-cheatsheet.md) | [12](../12-Flows-and-Matching/README.md) | complexities, max-flow/min-cut and matching theorems, signal → model, gadgets, Dinic/Hopcroft–Karp/MCMF/Hungarian | when $n \le 500$ and the problem smells like assignment |
| [13 · Game theory](13-game-theory-cheatsheet.md) | [13](../13-Game-Theory/README.md) | P/N positions, Nim, Sprague–Grundy, misère, staircase, Wythoff, game DP | when a statement says "Alice and Bob play optimally" |
| [14 · Geometry](14-geometry-cheatsheet.md) | [14](../14-Geometry/README.md) | cross/dot, orientation, segments, shoelace & Pick, hull, closest pair, circles, integer-type bounds | before geometry-tagged practice |
| [15 · Advanced math](15-advanced-math-cheatsheet.md) | [15](../15-Advanced-Math/README.md) | matrices & recurrences, Gaussian elimination & XOR basis, FFT/NTT, generating functions, interpolation, matrix-tree | from Sep 2027 |
| [16 · IGM frontier](16-igm-frontier-cheatsheet.md) | [16](../16-IGM-Frontier/README.md) | offline techniques (CDQ, parallel binary search), segment tree on time, link-cut trees, randomisation, bitsets, sqrt tricks | from Oct 2027 |
| [17 · FAANG interviews](17-faang-interview-cheatsheet.md) | [17](../17-FAANG-Interview-DSA/README.md) | the 45-minute timeline, constraints → technique, signal → pattern, operation costs, templates, key facts | the day before a mock or an interview |

## How to use them (a revision routine)

The routine below is the kit's suggestion, not a researched rule; adjust it to your schedule in the
[roadmap](../00-Roadmap-and-Strategy/02-roadmap-nov-2026-to-dec-2027.md).

1. **After finishing a folder**, read its sheet once and mark every line you couldn't have written yourself. Re-read the source section for each
   marked line the same week.
2. **Before every rated contest** (10–15 minutes): the [master formula sheet](00-master-formula-sheet.md), the sheet for the folder you are
   currently studying, and the "Top 10 mistakes" + "Last-minute" sections of [01](01-foundations-cheatsheet.md) and [03](03-greedy-constructive-interactive-cheatsheet.md).
3. **Weekly**: one older sheet in rotation (spaced repetition: a sheet you struggled with comes back after 2 days, 7 days, then 30 days).
4. **Monthly**: re-type two templates from memory, in both languages, and compare with the sheet. The templates are short on purpose — typing them
   under time pressure is the skill.
5. **After a contest**: if a verdict was lost to something already on a sheet, bold that line; if it wasn't on any sheet, add it to your own notes
   (the [practice methodology](../00-Roadmap-and-Strategy/03-practice-methodology.md) describes an idea journal for this).

## Layout of every sheet

`Formulas / results` → `Signal → technique` → `Templates (C++ then Java)` → `Edge cases and constants` → `Top 10 mistakes` → `Last-minute list`.
Section names vary slightly between sheets, but the order is the same, so you always know where to look.
