# 08 — Data Structures

Range queries, dynamic connectivity, ordered sets, offline tricks — the machinery that turns an $O(nq)$ idea into $O((n+q)\log n)$.
From Specialist to Master, data structures are the single most common "second half" of a problem: the observation tells you *what* to maintain, the
structure tells you *how fast* you can maintain it. Past 2100 the problems stop asking "do you know a segment tree?" and start asking "can you design the node,
the tag, or the offline order that makes it work?" — which is what this folder trains.

## First-principles overview: one question behind every structure

Every structure here answers the same question: **what can I precompute so that each operation touches only a few pieces?** The pieces and the rule for combining them decide everything.

1. **Decompose the index range into canonical blocks.** Prefix sums use one block per prefix; a Fenwick tree uses blocks whose lengths are the set bits of the index;
   a segment tree uses the dyadic intervals of a binary tree; a sparse table uses every power-of-two window; sqrt decomposition uses $\sqrt n$ equal blocks. Any range is a union of
   $O(\log n)$ (or $O(\sqrt n)$) blocks, and any position lies in $O(\log n)$ blocks — so both queries and updates are cheap.
2. **Check the algebra of the combine.** Blocks can be combined only if the operation is associative (a *monoid*). If it is also invertible (sum, xor) a range is a difference of prefixes —
   Fenwick tree. If it is idempotent (min, gcd) overlapping blocks are fine — sparse table, $O(1)$. Otherwise you need disjoint blocks — segment tree. For *range updates* the updates themselves must form
   a monoid acting on the summaries (lazy propagation); if they do not, a *potential argument* (each element can change only $O(\log V)$ times) or segment tree beats may still save you.
3. **Design the node.** When the answer for two halves does not determine the answer for the whole (max subarray, bracket matching, number of runs), add fields until the set of fields is closed under
   concatenation. This is the most important creative step at 1900–2400.
4. **Change the order of time.** Many "impossible" online problems become easy offline: sort queries by right end (distinct values), reverse time to turn deletions into insertions (DSU),
   reorder queries to minimise pointer movement (Mo), batch updates and rebuild (sqrt on queries), keep every version (persistence) or walk the version tree with undo.
5. **Exploit randomness and amortisation.** Random priorities keep treaps balanced in expectation; path compression and union by size make DSU near-constant; "each element is deleted once" bounds
   next-pointer DSU, lazy-deletion heaps and segment-tree merging.

The constant factor matters too: arrays of primitives instead of node objects (Java), bottom-up trees when recursion is unnecessary, inlined add/remove in Mo, preallocated pools for persistent and dynamic trees.

## Files

| File | Band | Priority | FAANG | One-line summary |
|---|---|---|---|---|
| [01 · Fenwick tree](01-fenwick-tree.md) | 🔵 1500–1900 | 🔥 | medium | lowbit blocks, two-BIT range add/sum, 2D BIT, k-th by descent, offline distinct counting |
| [02 · Segment tree basics](02-segment-tree-basics.md) | 🔵 1600–2000 | 🔥 | medium | monoids, recursive vs bottom-up, node design (max subarray, brackets, runs), 4n vs 2n |
| [03 · Lazy propagation](03-lazy-propagation.md) | 🟣 1900–2200 | 🔥 | low | monoid actions, assign+add, affine maps, arithmetic progressions, push-down discipline |
| [04 · Advanced segment trees](04-segment-tree-advanced-descent-merging-beats.md) | 🟣–🟠 1900–2500 | 🔥/⚡/🧊 | low | descent, dynamic trees, merging, range mod, beats, union-area sweep, wavelet/merge-sort trees |
| [05 · Sparse table and RMQ](05-sparse-table-and-rmq.md) | 🔵 1600–2100 | 🔥 | low | idempotence, $O(1)$ RMQ, gcd tables, disjoint sparse table, LCA via Euler tour |
| [06 · DSU and variants](06-dsu-and-variants.md) | 🔵 1400–2100 | 🔥 | high | union by size + compression, potentials, parity, reverse time, next pointers, rollback |
| [07 · Sqrt decomposition and Mo](07-sqrt-decomposition-and-mos-algorithm.md) | 🟣–🟠 1900–2600 | 🔥/⚡/🧊 | low | balancing, thresholds, Mo + odd–even, Mo with updates $O(n^{5/3})$, rebuild every $\sqrt q$ |
| [08 · Persistent structures](08-persistent-data-structures.md) | 🟠 2100–2500 | ⚡ | low | path copying, k-th in range online, distinct online, version trees with undo |
| [09 · Treaps](09-treaps-and-implicit-treaps.md) | 🟠 2000–2500 | ⚡ | low | random priorities, split/merge, order statistics, implicit treap: reverse, cut/paste, shifts |
| [10 · Ordered sets, PBDS, heaps](10-ordered-sets-pbds-and-heaps.md) | 🟢–🔵 1200–1900 | 🔥 | high | multiset/TreeMap idioms, PBDS, two heaps, lazy deletion, anti-hash, LRU |
| [problems.md](problems.md) | all | — | — | consolidated ladder, ≈95 problems by rating band + LeetCode list |
| [Cheat sheet](../99-Cheat-Sheets/08-data-structures-cheatsheet.md) | — | — | — | templates in C++ and Java, complexity tables, signal → structure, top mistakes |

## Choosing a structure in thirty seconds

Ask these in order; the first "yes" is usually the intended tool.

1. **Is the array static?** Invertible operation → prefix sums. Idempotent → sparse table. Otherwise → disjoint sparse table or segment tree.
2. **Are all queries known in advance?** Consider sorting them (by right end, by threshold), reversing time, Mo, or a version-tree DFS before any online structure.
3. **Point updates only?** Sum/xor → BIT. Anything else → bottom-up segment tree with a designed node.
4. **Range updates?** Derive `apply` and `compose`; if they exist → lazy segment tree; if not, is there a potential (values shrink fast) → recursion with pruning or beats.
5. **Do you need "first position where …" or "k-th"?** → descent on the tree you already have (BIT or segment tree), not a binary search around it.
6. **Is it about groups merging?** → DSU (with potentials/parity if relations carry values; reversed if items disappear; rollback if you must undo).
7. **Does the sequence itself change shape** (insert in the middle, cut/paste, reverse)? → implicit treap (or sqrt blocks rebuilt periodically).
8. **Do you need history** (copies, old versions, online range k-th)? → persistence by path copying.
9. **Is $n \le 10^5$ with a 3–5 s limit and nothing above fits?** → sqrt decomposition, thresholds or Mo.

## Prerequisites

- [Complexity and constraint reading](../01-Foundations/01-complexity-and-constraint-reading.md) — knowing that $2\cdot10^5$ means $O(n\log n)$ and $10^5$ with 5 s means $O(n\sqrt n)$ is possible.
- [C++ STL and Java collections](../01-Foundations/02-cpp-stl-and-java-collections.md), [bit manipulation](../01-Foundations/03-bit-manipulation.md), [fast I/O](../01-Foundations/06-integer-overflow-precision-and-fast-io.md).
- [Prefix sums and difference arrays](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md), [binary search](../02-Core-Techniques/02-binary-search-and-binary-search-on-answer.md), [coordinate compression and sweep line](../02-Core-Techniques/05-coordinate-compression-and-sweep-line.md).

## Recommended study order

1. **[10](10-ordered-sets-pbds-and-heaps.md) → [06](06-dsu-and-variants.md) → [01](01-fenwick-tree.md)** (Pupil/Specialist): library containers, DSU, BIT. These alone solve most data-structure Div2 C/D problems.
2. **[02](02-segment-tree-basics.md) → [05](05-sparse-table-and-rmq.md) → [03](03-lazy-propagation.md)** (Expert): segment trees and node design, static RMQ, lazy tags.
3. **[04](04-segment-tree-advanced-descent-merging-beats.md) (descent, dynamic, sweep) → [07](07-sqrt-decomposition-and-mos-algorithm.md) (blocks, Mo)** (Candidate Master): the toolkit for Div2 E / Div1 C.
4. **[08](08-persistent-data-structures.md) → [09](09-treaps-and-implicit-treaps.md) → the 🧊 parts of [04](04-segment-tree-advanced-descent-merging-beats.md) and [07](07-sqrt-decomposition-and-mos-algorithm.md)** (Master and beyond).
5. Continue with [trees](../10-Trees/README.md) (Euler tour, HLD, centroid) and [IGM frontier](../16-IGM-Frontier/README.md) (CDQ, segment tree on time, link–cut trees, advanced sqrt).

Practise each file's ladder until you can write its main structure without looking, then move on; come back to the hard end of each ladder later.

## How this domain shows up in rounds

- **Div2 B/C (≤ 1600):** `set`/`map`/heaps for simulation and greedy; DSU for "groups"; prefix sums disguised as data structures. Choosing the right library container is the skill.
- **Div2 D (1700–2000):** BIT counting (inversions, dominance), a segment tree with a non-trivial but small node, sparse table + binary search, DSU in reverse. Usually one structure, standard use.
- **Div2 E / Div1 B–C (2000–2400):** lazy tags with a twist (composition, bitwise splits), descent, offline reordering (sort by right end, Mo), merging on trees, potential arguments. The difficulty is in the modelling, not the code.
- **Div1 D+ (2400+):** persistence, beats, Mo with updates, sqrt on queries, segment tree on time, dynamic connectivity, combinations with HLD or centroid decomposition.
- **Educational rounds** (and AtCoder ABC F/G) contain the purest data-structure problems — the best place to drill this folder.

Many strong competitors keep a personal library of these structures; build yours from the tested code in these files (both languages), and re-derive each one on paper at least once so you can adapt it under pressure.

## Links

- Consolidated ladder: [problems.md](problems.md)
- Revision sheet: [08 · data structures cheat sheet](../99-Cheat-Sheets/08-data-structures-cheatsheet.md)
- Related folders: [core techniques](../02-Core-Techniques/README.md), [DP optimisations](../07-DP-Optimizations/README.md) (Li Chao tree, monotonic queues), [trees](../10-Trees/README.md), [FAANG DSA](../17-FAANG-Interview-DSA/README.md)
