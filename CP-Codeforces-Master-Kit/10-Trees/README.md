# 10 — Trees

Trees are the most common non-trivial structure on Codeforces: roughly every second Div. 2 round has a tree problem from C onwards, and the 1900–2400 range is full of "a tree plus one technique" problems. This folder covers the *structural* techniques — how to root, linearise, decompose and compress a tree so that path and subtree questions become array questions. **Tree DP and rerooting** live in [06-Dynamic-Programming/08](../06-Dynamic-Programming/08-tree-dp-and-rerooting.md); graph traversal basics in [09-Graphs/01](../09-Graphs/01-graph-representation-bfs-dfs.md).

## First-principles overview

A tree is the graph where **every pair of vertices has exactly one path**. Everything in this folder exploits that uniqueness in one of four ways.

1. **Root it and order it.** Rooting gives parents, depths and subtrees. Any order in which parents precede children (BFS, stack preorder) lets you compute top-down values forwards and bottom-up values backwards — *no recursion needed*, which matters in Java. The preorder makes every subtree a contiguous block, so subtree queries become range queries ([file 01](01-tree-basics-diameter-center-euler-tour.md)).
2. **Answer path questions through the LCA.** The path $u$–$v$ is $u \to \mathrm{lca} \to v$, so distances, path sums, "is $x$ on the path", the $k$-th vertex of a path and path difference-arrays all reduce to LCA. Binary lifting gives LCA, $k$-th ancestors and static path aggregates in $O(\log n)$; a sparse table over the preorder gives $O(1)$ LCA ([file 02](02-lca-and-binary-lifting.md)).
3. **Decompose so that every path or subtree touches few pieces.** The *light-edge lemma* — at most $\log_2 n$ light edges on any root path — is the engine of three techniques:
   - **small-to-large / sack**: subtree statistics that are not sums, $O(n\log n)$ ([file 03](03-small-to-large-and-dsu-on-tree.md));
   - **heavy–light decomposition**: arbitrary paths with updates become $O(\log n)$ array ranges ([file 04](04-heavy-light-decomposition.md));
   - **centroid decomposition** uses a different halving (removing the centroid halves components) to handle *all paths* at once, and its centroid tree answers "nearest marked vertex" queries ([file 05](05-centroid-decomposition.md)).
4. **Compress.** When each query touches only $k$ key vertices and $\sum k$ is bounded, keep just the keys and their pairwise LCAs — the virtual tree has $\le 2k - 1$ vertices and is built with two sorts ([file 06](06-virtual-trees.md)).

The question to ask on reading any tree problem: *is the quantity about a subtree, a root path, an arbitrary path, all paths, or a small set of vertices — and are there updates?* The table in "Choosing a technique" below answers the rest.

## Files

| File | Band | Priority | FAANG | One-line summary |
|---|---|---|---|---|
| [01 · Tree basics, diameter, centre, Euler tour](01-tree-basics-diameter-center-euler-tour.md) | 🟢–🔵 (isomorphism, Prüfer 🟠) | 🔥 | high | Iterative rooting, diameter (two BFS + DP), centre vs centroid, subtree = range, root-path sums, isomorphism, Prüfer/Cayley |
| [02 · LCA and binary lifting](02-lca-and-binary-lifting.md) | 🔵–🟣 | 🔥 | medium | Doubling table, $k$-th ancestor, path max/min, $O(1)$ LCA via preorder RMQ, Tarjan offline, on-path tests |
| [03 · Small-to-large and DSU on tree](03-small-to-large-and-dsu-on-tree.md) | 🟣–🟠 | 🔥 | low | Merge smaller into larger, heavy-child "sack" with no recursion, offline subtree queries |
| [04 · Heavy–light decomposition](04-heavy-light-decomposition.md) | 🟠 | ⚡ | none | Chains via heavy children, path + subtree ops on one segment tree, edge values, non-commutative paths |
| [05 · Centroid decomposition](05-centroid-decomposition.md) | 🟠 | ⚡ | none | Count/optimise over all paths, centroid tree for nearest-marked queries |
| [06 · Virtual trees](06-virtual-trees.md) | 🟠–🔴 | ⚡ | none | Compress to $\le 2k-1$ vertices with two sorts, DP on the compressed tree |
| [problems.md](problems.md) | all | — | — | ~85 graded problems for the whole folder + LeetCode list |
| [Cheat sheet](../99-Cheat-Sheets/10-trees-cheatsheet.md) | — | — | — | formulas, templates (C++ and Java), signals, pitfalls |

## Prerequisites

- [BFS/DFS and graph representation](../09-Graphs/01-graph-representation-bfs-dfs.md) — adjacency lists, iterative traversal.
- [Fenwick tree](../08-Data-Structures/01-fenwick-tree.md), [segment tree](../08-Data-Structures/02-segment-tree-basics.md), [lazy propagation](../08-Data-Structures/03-lazy-propagation.md), [sparse table](../08-Data-Structures/05-sparse-table-and-rmq.md) — the array structures that trees are reduced to.
- [DSU](../08-Data-Structures/06-dsu-and-variants.md) — union by size is the same argument as small-to-large; Tarjan's LCA uses it.
- [Tree DP](../06-Dynamic-Programming/08-tree-dp-and-rerooting.md) — most tree problems combine one technique from here with a DP.

## Recommended study order

1. **01** fully (two days). Write the iterative rooting template in both languages until it is muscle memory; do CSES 1674, 1131, 1132, 1137, 1138.
2. **02** binary lifting, then the $O(1)$ version (three days). CSES 1687, 1688, 1135, 1136; CF 191C, 1702G2, 609E.
3. [Tree DP and rerooting](../06-Dynamic-Programming/08-tree-dp-and-rerooting.md) — interleave here; it is the most frequent tree topic in Div. 2.
4. **03** small-to-large and the sack (two days). CSES 1139, CF 600E, 570D.
5. **04** HLD (two days) — needs a solid segment tree. CSES 2134, CF 343D.
6. **05** centroid decomposition (two days). CSES 2079–2081, CF 342E.
7. **06** virtual trees (one or two days) once 02 is fluent. CF 1923E, 613D.

For the Master target, 01–03 are must-know and appear constantly; 04–05 appear a few times per year in Div. 2 E/F and Div. 1 C/D; 06 is rarer but is the standard tool when you see "$\sum k \le$" in a constraint.

## Choosing a technique

| The question is about… | No updates | With updates |
|---|---|---|
| a subtree (sum/min) | Euler tour + prefix sums | Euler tour + Fenwick / segment tree |
| a subtree (distinct, mode, $\ge k$ occurrences) | sack / small-to-large (offline) | Euler tour + Mo / persistent structures |
| a root path (invertible aggregate) | prefix from root | range add on subtree + point query |
| an arbitrary path (max/min/gcd) | binary lifting | HLD + segment tree |
| an arbitrary path with path updates | — | HLD + lazy segment tree |
| all paths (count with a length/weight condition) | centroid decomposition | — |
| distance to a dynamic set of marked vertices | — | centroid tree |
| many queries on small vertex sets ($\sum k$ bounded) | virtual tree + DP | — |
| links and cuts of edges online | — | [link-cut tree](../16-IGM-Frontier/03-link-cut-trees.md) |

## How trees show up in rounds

- **Div. 2 A–C (≤ 1600):** degrees, leaves, subtree sizes, BFS layers, diameter, bipartite colouring, "greedy from the leaves".
- **Div. 2 D–E (1700–2200):** tree DP and rerooting, Euler tour + Fenwick, LCA with path difference arrays, small-to-large, $k$-th ancestor tricks, "deepest vertex is an endpoint" arguments.
- **Div. 2 F / Div. 1 C–D (2200–2600):** HLD with a non-trivial segment tree, centroid decomposition with bitmasks or XOR, virtual trees with a DP, merging structures bottom-up, interactive search on trees.
- **Educational rounds** like classic named techniques (sack, HLD, virtual tree) more than ad-hoc rounds do.

A recurring meta-skill: **reduce to an array**. Many 2000+ tree problems become a known array problem after choosing the right linearisation (preorder for subtrees, HLD order for paths, preorder-sorted key lists for virtual trees).

## Where next

- [problems.md](problems.md) — the consolidated ladder.
- [Cheat sheet](../99-Cheat-Sheets/10-trees-cheatsheet.md) — revision before contests.
- Further: [link-cut trees](../16-IGM-Frontier/03-link-cut-trees.md), [segment tree on time / DSU rollback](../16-IGM-Frontier/02-segment-tree-on-time-and-dsu-rollback.md), [persistent structures](../08-Data-Structures/08-persistent-data-structures.md), [FAANG trees and BST](../17-FAANG-Interview-DSA/07-trees-and-bst.md).
