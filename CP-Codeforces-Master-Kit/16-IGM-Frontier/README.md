# 16 — IGM Frontier: from Master (2100) towards Grandmaster and International Grandmaster (2400–2600+)

This folder is the bridge from "I know the standard techniques" to "I can solve the problems that decide Div 1 rounds". It covers the techniques that appear at 2300–3000 and are not in the classic syllabus — offline divide and conquer, segment tree on time, link-cut trees, randomisation, bitsets, advanced square-root splits — and, just as important, the *way of thinking* that strong competitors use to find the key observation.

**Read this first if your goal is Master by December 2027:** most of this folder is *after*-Master material. Only a few items are worth learning before the target (table in §3). Everything else is here so that the path continues past 2100 without changing books.

## 1. What the domain is about

Problems at 2400+ rarely ask for a brand-new algorithm. They take a standard structure and remove the property it needs: the DSU now has deletions, the tree now changes shape, the hash can be attacked, the $O(n^2)$ DP is just too slow, the queries do not come in a convenient order. Each file in this folder is a way to **buy that property back**:

| The structure lacks… | Buy it back with… | File |
|---|---|---|
| the right processing order | reorder queries, split time or values in halves (CDQ, parallel / overall binary search) | [01](01-offline-techniques-cdq-parallel-binary-search.md) |
| deletions | undo instead of delete: segment tree on time + rollback DSU | [02](02-segment-tree-on-time-and-dsu-rollback.md) |
| a fixed shape | paths chosen by recent use, kept in splay trees: link-cut trees | [03](03-link-cut-trees.md) |
| protection against adversarial inputs | random choices made after the input is fixed; hashing of sets and multisets | [04](04-randomized-algorithms-and-hashing.md) |
| speed by a constant factor of 64 | word-level parallelism: bitsets | [05](05-bitset-optimization.md) |
| one algorithm good for all sizes | two algorithms and a threshold: heavy/light, periodic rebuild | [06](06-advanced-sqrt-techniques.md) |
| the observation itself | heuristics, editorial reading, deliberate practice | [07](07-how-grandmasters-think.md) |

## 2. First-principles overview

Four ideas run through the whole folder.

1. **Freedom from order.** Offline algorithms may reorder anything. Sorting queries by a threshold makes a structure monotone (DSU only grows); splitting time in halves turns a dynamic problem into static ones (CDQ); sharing one sweep among many binary searches turns $q$ sweeps into $\log$ sweeps (parallel binary search); the DFS of a segment tree over time turns deletions into LIFO undos.
2. **Amortisation and potential.** Link-cut trees, rollback structures and periodic rebuilds are fast on average over a sequence, not per operation. Knowing *which* potential argument applies tells you which operations are allowed (rollback forbids path compression; splaying must follow every descent).
3. **Probability as a tool, not luck.** Random labels make multisets comparable in $O(1)$ with error $2^{-64}$; random samples find heavy elements; random choices defeat hacks. Every randomised step comes with a computed failure probability.
4. **Balancing.** Whenever two methods are each fast in one regime, the threshold $B = \sqrt{b/a}$ minimises $aB + b/B$. Bitsets are the degenerate case where one side is "the same algorithm, 64 at a time".

Underneath all four sits file [07](07-how-grandmasters-think.md): the techniques matter only after the statement has been reduced to something they apply to, and that reduction is the real skill at 2400+.

## 3. Files, bands and what to learn before December 2027

| File | Band | Priority | FAANG | One-line summary |
|---|---|---|---|---|
| [01 Offline techniques: CDQ, parallel binary search](01-offline-techniques-cdq-parallel-binary-search.md) | 🟠 2100–2600 | ⚡ (offline sort + DSU: 🔥) | low/medium | sort queries + DSU, reverse time, CDQ for 3D dominance and dynamic 2D, parallel and overall binary search |
| [02 Segment tree on time and DSU rollback](02-segment-tree-on-time-and-dsu-rollback.md) | 🔴 2400–2800 | 🧊 (rollback DSU: ⚡) | none | offline dynamic connectivity, bipartiteness over time, leave-one-out D&C |
| [03 Link-cut trees](03-link-cut-trees.md) | 🔴 2500–3400 | 🧊 | none | access/makeRoot/link/cut, path aggregates, dynamic LCA, incremental MST; when HLD suffices |
| [04 Randomised algorithms and hashing](04-randomized-algorithms-and-hashing.md) | 🟣→🟠 1900–2600 | 🔥 (hashing, seeding, sampling) | medium | XOR/sum hashing, anti-hack seeding, random sampling, Freivalds, Schwartz–Zippel, colour coding |
| [05 Bitset optimisation](05-bitset-optimization.md) | 🟠 2000–2600 | ⚡ | low | shift-or knapsack, bounded-total subset sums, closure, triangles, corner rectangles |
| [06 Advanced sqrt techniques](06-advanced-sqrt-techniques.md) | 🟠 2100–2700 | ⚡ | low | split by step/degree/size/length, periodic rebuild, heavy/light sets |
| [07 How grandmasters think](07-how-grandmasters-think.md) | all bands | 🔥 | medium | 12 heuristics, reading editorials, idea journal, +300–500 practice, upsolving |

**Worth learning before the Dec-2027 Master target (few, on purpose):**

1. [07 — heuristics, editorial reading, upsolving](07-how-grandmasters-think.md): from day one, and reread monthly.
2. [04 — XOR/sum hashing, anti-hack seeding, random sampling](04-randomized-algorithms-and-hashing.md) (§1.1–1.3, 1.8; Examples 1, 2, 4): these appear in Div 2 D/E at 1900–2300.
3. [01 §1.2 — offline sorting + DSU and reverse time](01-offline-techniques-cdq-parallel-binary-search.md): an 1800–2100 skill that shows up constantly.
4. [06 §1.2–1.3 — split by step and heavy/light by degree or size](06-advanced-sqrt-techniques.md): the most common 2100–2300 square-root idea.
5. [05 §1.2–1.3 — `b |= b << w` and bounded-total subset sums](05-bitset-optimization.md): cheap to learn, saves a TLE a few times a year.
6. Late 2027, if the above are solid: parallel binary search and CDQ from [01](01-offline-techniques-cdq-parallel-binary-search.md).

**After the Master target (on the way to GM/IGM):** segment tree on time and rollback DSU ([02](02-segment-tree-on-time-and-dsu-rollback.md)), link-cut trees ([03](03-link-cut-trees.md)), Freivalds / Schwartz–Zippel / colour coding (04 §1.4, 1.7), bit-parallel LCS and Four Russians (05 §7), periodic rebuild and few-distinct-answers arguments (06 §1.4–1.5), sqrt tree and Mo with updates.

The reasoning (an opinion based on how these techniques are distributed in recent rounds): a 2100 rating is decided mostly by solving Div 2 A–D fast and D/E reliably; the 🧊 techniques here are Div 1 D+ material, and the time is better spent on volume at 1900–2300 with the 🔥 items above.

## 4. Prerequisites

- [Fenwick tree](../08-Data-Structures/01-fenwick-tree.md), [segment tree basics](../08-Data-Structures/02-segment-tree-basics.md), [DSU and variants](../08-Data-Structures/06-dsu-and-variants.md), [sqrt decomposition and Mo](../08-Data-Structures/07-sqrt-decomposition-and-mos-algorithm.md), [treaps](../08-Data-Structures/09-treaps-and-implicit-treaps.md)
- [LCA and binary lifting](../10-Trees/02-lca-and-binary-lifting.md), [heavy-light decomposition](../10-Trees/04-heavy-light-decomposition.md)
- [Binary search on the answer](../02-Core-Techniques/02-binary-search-and-binary-search-on-answer.md), [knapsack family](../06-Dynamic-Programming/02-knapsack-family.md)
- [Probability and expected value](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md), [string hashing](../11-Strings/01-string-hashing.md)

## 5. Recommended study order

1. **07** — read once now; it changes how you practise everything else.
2. **04** §1–3 and Examples 1–2, 4 — hashing and seeding.
3. **01** §1.2 and Example 1 — offline sorting + DSU.
4. **06** Examples 1, 2, 5 — the split-by-size pattern.
5. **05** Examples 1, 5 — bitset knapsack.
6. **01** rest — parallel binary search, overall binary search, CDQ.
7. **02** — rollback DSU, then segment tree on time.
8. **03** — link-cut trees last; practise on [CF 13E · Holes](https://codeforces.com/problemset/problem/13/E) — 2700 with both an LCT and the sqrt solution.

## 6. How this shows up in rounds

- **Div 2 D/E (1900–2400):** XOR/sum hashing ("is this subarray a permutation / balanced"), random sampling for frequent elements, offline query sorting with DSU or Fenwick, square-root split by step or degree, bitset subset sum. The heuristics of 07 decide most Div 2 D's.
- **Div 1 C/D (2300–2700):** parallel binary search, CDQ, segment tree on time, heavy/light sets, periodic rebuild, randomised "pick a random element" arguments, bitsets with dynamic sizes.
- **Div 1 E/F (2800+):** link-cut trees, lifetimes decided on the fly, nested D&C, colour coding, combinations of several of the above.
- **Educational rounds** tend to use classic techniques in fairly pure form, which makes them good practice for this folder; **rounds with hacks** punish fixed seeds and default hashes — see 04 §1.8.

## 7. Where to practise and revise

- [problems.md](problems.md) — 96 problems by rating band, plus a LeetCode section.
- [Cheat sheet](../99-Cheat-Sheets/16-igm-frontier-cheatsheet.md) — templates in C++ and Java, complexities, signal → technique, top mistakes.
