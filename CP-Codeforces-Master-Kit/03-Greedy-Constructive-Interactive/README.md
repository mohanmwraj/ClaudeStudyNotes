# 03 — Greedy, Constructive and Interactive

This folder covers the problems that are *not* solved by a named data structure or a textbook algorithm: choose
locally and prove it (greedy), build an object with a property (constructive), discover what an operation preserves
(invariants / ad hoc), and extract hidden information under a query budget (interactive). On Codeforces these make up
most of Div2 A–C and a large share of D, and they are the problems where rating gaps between Expert and Master are most
visible: the algorithmic content is small, the reasoning is everything.

## First-principles overview

All four topics share one discipline: **separate what must be true from what you can make true**.

- **Greedy** — an optimisation problem where a local choice can be proven safe. The proof is the technique:
  *exchange argument* (any optimal solution can be transformed into the greedy one without getting worse; for orderings
  this reduces to a two-element inequality that also *gives* you the sort key), *greedy stays ahead* (an induction on a
  progress measure), or *lower bound + matching construction*. When a decision can only be judged later, keep the chosen
  items in a heap and evict or undo with **regret tokens** — which is a hand-simulated min-cost flow.
- **Constructive** — print any object with property P or −1. First the *necessary* conditions (parity, counting,
  invariants) give the impossible cases; then a construction (pattern from brute-forced small cases, induction,
  extremes first, a global parity/order/colouring that makes the property automatic) covers the rest; then a checker
  verifies it on all small inputs.
- **Invariants and ad hoc** — for "apply the operation any number of times", look at functions of the state: what never
  changes (invariant → necessity), what moves one way (monovariant → termination, bounds), and a normal form that every
  state with the same invariants reaches (sufficiency). Parity, colouring, pigeonhole, extremal elements, reverse
  thinking, XOR and MEX facts are the standard tools.
- **Interactive** — the input is a conversation. Information theory gives the lower bound ($\lceil \log_k N \rceil$ queries for
  $k$-ary answers), the budget hints at the strategy, an invariant keeps the search honest against an adaptive judge, and
  protocol hygiene (flush, −1, multiple tests) decides whether a correct idea is accepted.

The common habit across the folder: **brute force tiny cases before thinking hard** — to kill a wrong greedy, to see
the shape of a construction, to discover an invariant by BFS, to stress-test an interactive strategy against a local judge.

## Files

| File | Band | Priority | FAANG | One-line summary |
|---|---|---|---|---|
| [01 · Greedy and exchange arguments](01-greedy-and-exchange-arguments.md) | 🟢–🟣 800–2100 | 🔥 | high | exchange / stays-ahead proofs, interval scheduling, Smith's rule, EDF, Huffman, fractional knapsack, comparator correctness |
| [02 · Greedy with heaps and regret](02-greedy-with-heaps-and-regret.md) | 🔵–🔴 1400–2600 | 🔥 | high | evict-the-worst heaps, deadlines & profits, Moore–Hodgson, regret tokens (Buy Low Sell High), convex marginal gains, lazy deletion |
| [03 · Constructive algorithms](03-constructive-algorithms.md) | 🟢–🟠 800–2400 | 🔥 | medium | necessity then sufficiency, small-case explorer, induction, extremes, XOR/bit constructions, parity colourings, DAG orientation |
| [04 · Invariants, parity and ad hoc](04-invariants-parity-and-ad-hoc-observations.md) | 🟢–🟠 800–2400 | 🔥 | medium | invariant vs monovariant, normal forms, colouring, pigeonhole, extremal principle, reverse thinking, MEX and XOR facts |
| [05 · Interactive problems](05-interactive-problems.md) | 🔵–🟠 1300–2400 | 🔥 | low | protocol and flushing, query budgets and lower bounds, binary search on hidden data, local extrema, adaptive judges, local interactors |
| [problems.md](problems.md) | all | — | — | 99 problems by rating band + a LeetCode list |
| [Cheat sheet](../99-Cheat-Sheets/03-greedy-constructive-interactive-cheatsheet.md) | — | — | — | formulas, keys, patterns, templates, mistakes |

## Prerequisites

- [Sorting and comparators](../01-Foundations/05-sorting-and-comparators.md) — strict weak orderings, custom keys.
- [Recursion, brute force and backtracking](../01-Foundations/04-recursion-brute-force-and-backtracking.md) — you will
  write a brute force for almost every problem here.
- [Bit manipulation](../01-Foundations/03-bit-manipulation.md) — XOR constructions and invariants.
- [Binary search](../02-Core-Techniques/02-binary-search-and-binary-search-on-answer.md) — the backbone of interactive strategies.
- [C++ STL and Java collections](../01-Foundations/02-cpp-stl-and-java-collections.md) — `priority_queue`, `multiset`,
  `PriorityQueue`, `TreeMap`.

## Recommended study order

1. **01 Greedy** §1–§2 (the proof techniques) and Examples 1–4. Do the ≤ 1400 ladder in parallel.
2. **04 Invariants** §1 checklist and Examples 1–4 — the cheapest rating gain in the folder.
3. **03 Constructive** with the explorer habit; Examples 1–3, then the 1400–1700 ladder.
4. **05 Interactive** protocol (§1, §3) before your next contest — one forgotten flush costs a problem.
5. **02 Heaps and regret** Examples 1–3, then return for Examples 4–6 (regret tokens) when you are around 1900.
6. Finish the remaining examples of 01, 03, 04 (the 2000–2200 ones) and work the 1900–2100 band of [problems.md](problems.md).
7. Before contests: the [cheat sheet](../99-Cheat-Sheets/03-greedy-constructive-interactive-cheatsheet.md).

## How this shows up in rounds

- **Div2 A–B (800–1400):** almost entirely greedy-with-sorting, parity/invariant observations and small constructions.
  Speed matters: recognising "only the multiset matters" or "the first element can only grow" in a minute is the skill.
- **Div2 C (1400–1800):** constructive problems with an impossibility case, greedy with a heap or a two-element
  exchange key, MEX/XOR ad hoc, and roughly every second or third round an interactive binary search.
- **Div2 D / Div1 B (1800–2200):** regret greedy and exchange + DP combinations, constructions with operation budgets
  ("at most $n$ operations"), invariants that need a normal-form proof, interactive problems with tight budgets
  ($\log_2 n + c$) or adaptive judges.
- **Div1 C+ (2300+):** the same ideas layered on other domains — greedy that simulates a flow, constructions on graphs and
  trees (DFS-tree dichotomies), invariants in linear algebra over GF(2), interactive problems on trees.

Many strong competitors say that the fastest way from Expert to Master is not learning new algorithms but getting
reliable at exactly these "observation" problems; the files emphasise the habits (brute force, invariant checklist,
checker, local judge) that make them reliable.

## Related folders

- [02 Core techniques](../02-Core-Techniques/README.md) — two pointers, sweep line and binary search underpin many greedy proofs.
- [07 DP optimizations — slope trick](../07-DP-Optimizations/07-slope-trick.md) and
  [Aliens trick](../07-DP-Optimizations/06-aliens-trick-wqs-binary-search.md) — the convexity behind regret greedy.
- [12 Flows — min-cost flow](../12-Flows-and-Matching/04-min-cost-flow.md) — what regret greedy simulates.
- [13 Game theory](../13-Game-Theory/README.md) — invariants of optimal play.
- [17 FAANG — greedy and intervals](../17-FAANG-Interview-DSA/15-greedy-and-intervals.md) — interview framing of file 01.
