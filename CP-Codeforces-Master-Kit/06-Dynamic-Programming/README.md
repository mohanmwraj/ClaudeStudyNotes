# 06 — Dynamic Programming

Dynamic programming is the single most important rating topic between 1600 and 2400. Most Div2 C–E and Div1 A–C problems either *are* a DP or contain one after an observation. This folder teaches DP as one idea applied to different shapes of history, not as a collection of recurrences.

## The whole domain from first principles

1. **Start from brute force.** A solution is a sequence of decisions; brute force explores the tree of all decision sequences (histories).
2. **Merge equivalent histories.** Two histories are equivalent if no future can tell them apart (same valid completions, same added cost). A **state** is a compact label of an equivalence class. The design question is always: *what must I remember about the past to decide the future — and nothing more?*
3. **The states form a DAG.** Decisions make progress (index grows, set grows, interval shrinks, subtree is smaller), so the state graph is acyclic and optimal values are best paths in it: compute them in topological order. Time $=$ #states $\times$ #transitions.
4. **The semiring sets the kind of DP:** (min, +) optimisation, (+, ×) counting, (or, and) feasibility, (+, ×) with probabilities. Counting needs every object to correspond to exactly one path — the decomposition must be canonical.
5. **Two heuristics find transitions:** *fix the last element / last operation* (so the rest is settled and the parts are independent) and *add a dimension for whatever breaks the greedy* (the state becomes position × automaton state).
6. **When the graph has cycles,** it is no longer a single-pass DP: shortest paths (Dijkstra on a product graph), SCC condensation, or a system of equations (expectations).
7. **When it is too slow,** reduce states (an observation removes a dimension; swap value and index) or reduce transitions ([DP optimisations](../07-DP-Optimizations/README.md)).

Every file below is one family of state shapes: prefixes, (prefix, capacity), pairs of prefixes, grid cells, intervals, subsets, digit positions with a tight flag, subtrees, DAG vertices, Markov states, and grid frontiers.

## State shapes at a glance

| Family | Typical state | "The future only needs…" | Typical limits | Cost |
|---|---|---|---|---|
| prefix | $i$ (+ last choice / phase) | where I am, what the last step forbids | $n \le 10^6$ | $O(n)$ |
| knapsack | $(i, w)$ or $(i, v)$ | how much capacity is used | $nW \le 10^8$ | $O(nW)$ |
| two sequences | $(i, j)$ | how much of each string is consumed | $n, m \le 5000$ | $O(nm)$ |
| LIS-type | best tail per length | the smallest possible last value | $n \le 2\cdot10^5$ | $O(n\log n)$ |
| grid | $(r, c)$ (+ residue) | the current cell | $nm \le 10^7$ | $O(nm)$ |
| interval | $(l, r)$ (+ glued count) | which segment remains | $n \le 500$ | $O(n^3)$ |
| subset | $(\text{mask}, v)$ | which items are used, where I am | $n \le 20$ | $O(2^nn^2)$ |
| digits | (pos, tight, started, extra) | prefix still equal to $N$? + property summary | $N \le 10^{18}$ or a string | $O(\text{len}\cdot S\cdot 10)$ |
| tree | $(v, \text{status})$ | the status of $v$ | $n \le 2\cdot10^5$ | $O(n)$ |
| DAG / graph | vertex (× resource) | the vertex (and resource) | $n, m \le 2\cdot10^5$ | $O(n+m)$ / Dijkstra |
| Markov | state of the random process | the current state (Markov property) | problem-specific | states × transitions |
| frontier | (cell, profile mask) | coverage of the frontier cells | short side $\le 10$ | $O(nm2^n)$ |

## If you only have a week

Day 1: [01](01-dp-first-principles-and-state-design.md) §1 + AtCoder DP A–C · Day 2: [02](02-knapsack-family.md) + DP D, E, CSES coin problems · Day 3: [03](03-sequence-dp-lis-lcs-edit-distance.md) + DP F, CSES 1145, 1639 · Day 4: [05](05-interval-dp.md) + DP L, N · Day 5: [06](06-bitmask-dp.md) + DP O, U · Day 6: [08](08-tree-dp-and-rerooting.md) + DP P, V · Day 7: [07](07-digit-dp.md) and [10](10-probability-and-expected-value-dp.md) + DP I, J, S. Everything else follows the full study order below.

## Files

| File | Band | Priority | FAANG | One line |
|---|---|---|---|---|
| [01 · First principles and state design](01-dp-first-principles-and-state-design.md) | 🟢→🟣 1200–2100 | 🔥 | high | States as equivalence classes, DAG view, push/pull, memo vs table, reconstruction, the checklist |
| [02 · Knapsack family](02-knapsack-family.md) | 🟢→🟠 1200–2400 | 🔥 | high | 0/1, unbounded, bounded (binary splitting), group, value-indexed, counting orders, bitset subset sum |
| [03 · Sequence DP](03-sequence-dp-lis-lcs-edit-distance.md) | 🟢→🟣 1300–2200 | 🔥 | high | LIS ($n\log n$, reconstruction, counting), LCS, edit distance, distinct subsequences |
| [04 · Grid and path counting](04-grid-and-path-counting-dp.md) | 🟢→🟠 1100–2300 | 🔥 | high | Obstacles, binomials + first obstacle, two walkers, anti-diagonals, running sums |
| [05 · Interval DP](05-interval-dp.md) | 🔵→🟠 1500–2400 | 🔥 | medium | Split points, last operation, "first element rides along", glued counters, games |
| [06 · Bitmask DP](06-bitmask-dp.md) | 🔵→🟠 1600–2400 | 🔥 | medium | Held–Karp, popcount index, submasks in $3^n$, compound values, canonical starts |
| [07 · Digit DP](07-digit-dp.md) | 🔵→🟠 1700–2500 | 🔥 | low | Tight/started flags, memo by remaining length, sums, huge strings, both bounds |
| [08 · Tree DP and rerooting](08-tree-dp-and-rerooting.md) | 🔵→🟠 1500–2400 | 🔥 | high | Subtree states, iterative order, $O(n^2)$ tree knapsack, rerooting with prefix/suffix |
| [09 · DP on DAGs and graphs](09-dp-on-dags-and-graphs.md) | 🔵→🟠 1300–2400 | 🔥 | high | Topological DP, shortest-path DAG, SCC condensation, functional graphs, Dijkstra on states |
| [10 · Probability and expected value](10-probability-and-expected-value-dp.md) | 🔵→🟠 1500–2400 | 🔥 | medium | Forward probability, backward expectation, self-loops, cyclic unknowns, mod $p$, linear systems |
| [11 · Broken profile DP](11-broken-profile-dp.md) | 🟠 2000–2400 (🔴 plug DP) | ⚡ | low | Frontier masks, cell-at-a-time tilings with obstacles, adjacency windows |
| [problems.md](problems.md) | all | — | — | AtCoder DP A–Z, CSES DP section, Codeforces 1300–2700, LeetCode |
| [Cheat sheet](../99-Cheat-Sheets/06-dynamic-programming-cheatsheet.md) | all | — | — | Recurrences, loop orders, templates in C++ and Java, mistakes |

## Prerequisites

- [Recursion and backtracking](../01-Foundations/04-recursion-brute-force-and-backtracking.md) — the brute force every DP starts from.
- [Complexity and constraint reading](../01-Foundations/01-complexity-and-constraint-reading.md) — to estimate states × transitions.
- [Bit manipulation](../01-Foundations/03-bit-manipulation.md) (for 06, 11), [modular arithmetic](../04-Number-Theory/02-modular-arithmetic-and-inverses.md) (counting), [BFS/DFS](../09-Graphs/01-graph-representation-bfs-dfs.md) (08, 09), [probability](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md) (10).

## Recommended study order

1. **01** — read §1 twice; do Examples 1–3 and the AtCoder DP A–C.
2. **02 → 03 → 04** — the bread-and-butter shapes; AtCoder DP D–H, CSES DP section up to Edit Distance.
3. **05 → 06** — intervals and subsets; AtCoder DP L, N, O, U.
4. **08 → 09** — trees and graphs; AtCoder DP G, P, V.
5. **07 → 10** — digit and probability DP; AtCoder DP I, J, S.
6. **11** — after you are comfortable with bitmasks; CSES Counting Tilings.
7. Then [07-DP-Optimizations](../07-DP-Optimizations/README.md) for the 2100+ transition speed-ups.

A reasonable pace for the Dec-2027 target: 01–04 in the first month of DP work, 05–09 in the second, 07/10/11 and the optimisation folder in the third, with the [problems.md](problems.md) ladder running throughout.

## How DP shows up in rounds

- **Div2 B–C (1100–1600):** prefix DPs with one extra flag (last choice, a deletion used), simple knapsacks, grid paths. Often disguised as greedy — if your greedy fails a hand-made test, ask what it forgot and put that in a state.
- **Div2 D (1700–2000):** the state needs an observation — a bounded quantity (sum ≤ $10^5$, time of day, residue), an exchange-argument order before a knapsack, a tree DP with two or three statuses, a rerooting, or a bitmask over $\le 20$ items.
- **Div2 E / Div1 B–C (2000–2400):** interval DP with a decomposition trick, digit DP with sums, expected values mod $p$ with cyclic dependencies, tree knapsack with the $O(n^2)$ argument, and DPs whose transition needs a data structure or one of the [optimisations](../07-DP-Optimizations/README.md) (prefix sums, monotonic queue, CHT, D&C, Knuth).
- **Div1 D+ (2400+):** DP of DP, connected-component DP, plug DP, slope trick, Aliens trick, DP over generating functions — see [07-DP-Optimizations](../07-DP-Optimizations/README.md) and [16-IGM-Frontier](../16-IGM-Frontier/README.md).

Many strong competitors describe their process as "find the state first; the recurrence writes itself". The checklist in [01 §1.13](01-dp-first-principles-and-state-design.md) is that process made explicit.

## Interview relevance

DP is the most-asked "hard" topic in FAANG interviews: 1-D DPs (House Robber, Decode Ways, Word Break), knapsack variants (Coin Change, Partition Equal Subset Sum), two-sequence DPs (LCS, Edit Distance), grid DPs (Unique Paths, Minimal Path Sum), and tree DPs on binary trees. Interval, bitmask and digit DP appear occasionally at the hardest level. See [interview DP 1-D](../17-FAANG-Interview-DSA/13-dynamic-programming-1d.md) and [interview DP 2-D](../17-FAANG-Interview-DSA/14-dynamic-programming-2d.md).
