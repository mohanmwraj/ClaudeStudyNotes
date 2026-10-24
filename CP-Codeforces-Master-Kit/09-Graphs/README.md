# 09 — Graphs

Graphs are the most common "structure" in Codeforces problems after arrays: about one problem in four in a Div 2 round
involves a graph, explicitly or in disguise (a grid, a permutation, a set of rules "$a$ must precede $b$", a state machine).
This folder covers general graphs: traversal, shortest paths, spanning trees, orders and components, connectivity under
failures, 2-SAT, Euler tours, bipartiteness and cycles, and special graph families. Trees have their own folder
([10-Trees](../10-Trees/README.md)) and network flow its own ([12-Flows-and-Matching](../12-Flows-and-Matching/README.md)).

## First-principles overview of the domain

1. **Model first: vertices are states, edges are moves.** The hard step is almost never the algorithm; it is naming the
   state so that the question becomes "reachable?", "shortest?", "connected?", "ordered?". If the future depends on some
   history (walls broken, keys held, coupon used, time mod $k$), that history belongs in the vertex. If a move connects one
   vertex to a whole range or class of vertices, add auxiliary vertices instead of $n^2$ edges.
2. **Two traversals underlie everything.** BFS explores by distance (layers), so it answers unweighted shortest paths and,
   with a deque or heap, weighted ones. DFS explores by depth and leaves a *DFS tree* with entry/exit times; its structural
   facts — the parenthesis theorem, the white-path theorem, "undirected DFS trees have no cross edges", "a directed cycle
   exists iff there is a back edge" — prove topological sort, SCC, bridges, articulation points and 2-SAT.
3. **Shortest paths are schedules of relaxations.** BFS, 0-1 BFS, Dijkstra, Bellman–Ford and Floyd–Warshall all apply
   $d[v] \leftarrow \min(d[v], d[u]+w)$; they differ in *which order* guarantees correctness for which weights. Potentials
   ($w + h(u) - h(v)$) move between them and power difference constraints and min-cost flow.
4. **Greedy is provably optimal for spanning trees.** The cut and cycle properties (exchange arguments) make Kruskal and Prim
   correct and also answer "is this edge in some/every MST", bottleneck paths and MSTs of implicit complete graphs.
5. **Compress what is equivalent.** Mutual reachability (SCC), two-edge-connectivity (bridge tree), biconnectivity (block-cut
   tree), and cycles of a functional graph are equivalence classes or "blobs"; contracting them turns a general graph into a
   DAG or a tree where DP, LCA and counting become easy.
6. **Parity and degrees decide existence.** Bipartite ⇔ no odd cycle; Euler circuit ⇔ all degrees even (plus connectivity);
   2-SAT is satisfiable ⇔ no variable is equivalent to its negation. Many constructive problems are one of these conditions
   plus a linear-time construction.

## Files

| File | Band | Priority | FAANG | One-line summary |
|---|---|---|---|---|
| [01 Representation, BFS, DFS](01-graph-representation-bfs-dfs.md) | 🟢 800 → 🔵 1900 | 🔥 | high | CSR arrays, BFS layers proof, multi-source, 0-1 BFS, states, bidirectional, iterative DFS, edge classes, cycles |
| [02 Shortest paths](02-shortest-paths.md) | 🔵 1400 → 🟠 2400 | 🔥 | high | Dijkstra proof, Bellman–Ford + printing negative cycles, SPFA, Floyd, Johnson, layered graphs, counting, k-th, difference constraints |
| [03 Minimum spanning trees](03-minimum-spanning-trees.md) | 🔵 1500 → 🔴 2400+ | 🔥 / ⚡ / 🧊 | medium | cut/cycle properties, Kruskal, Prim, Borůvka, forced edges, bottleneck, Kruskal reconstruction tree, XOR-MST |
| [04 Topological sort and DAG DP](04-topological-sort-and-dag-dp.md) | 🟢 1200 → 🟠 2300 | 🔥 | high | Kahn, DFS order, lexicographic vs minimal labels, longest path, path counting, bitset reachability |
| [05 SCC and condensation](05-scc-and-condensation.md) | 🔵 1600 → 🟠 2400 | 🔥 | low | iterative Tarjan and Kosaraju, condensation DP, sources/sinks, $\max(s,t)$ augmentation |
| [06 Bridges, articulation points, BCC](06-bridges-articulation-points-and-bcc.md) | 🔵 1700 → 🟠 2300 | 🔥 / ⚡ | medium | low-link derivation, 2-edge-connected components, bridge tree, biconnected components, block-cut tree |
| [07 2-SAT](07-two-sat.md) | 🟣 1900 → 🟠 2400 | 🔥 | low | implication graph, SCC solution and assignment proof, clause encodings incl. at-most-one |
| [08 Euler paths and circuits](08-euler-paths-and-circuits.md) | 🔵 1700 → 🟠 2500 | 🔥 / ⚡ | medium | existence conditions, iterative Hierholzer, de Bruijn sequences, balancing degrees with extra edges |
| [09 Bipartite graphs and cycles](09-bipartite-graphs-and-cycles.md) | 🟢 1300 → 🟠 2300 | 🔥 / ⚡ | high | 2-coloring, odd cycles, girth via BFS, XOR cycle basis |
| [10 Functional and special graphs](10-functional-graphs-and-special-graphs.md) | 🟢 1200 → 🔴 2400 | 🔥 / ⚡ / 🧊 | medium | successor graphs, Floyd/Brent, binary lifting, cycle decomposition, complement BFS, virtual nodes, segment-tree graphs |
| [problems.md](problems.md) | all | — | — | ~90-problem ladder by rating band + LeetCode section |
| [Cheat sheet](../99-Cheat-Sheets/09-graphs-cheatsheet.md) | — | — | — | formulas, templates (C++/Java), signal → technique, mistakes |

## Prerequisites

- [Complexity and constraint reading](../01-Foundations/01-complexity-and-constraint-reading.md) — $n+m$ vs $n^2$ vs $nm$ budgets.
- [STL and Java collections](../01-Foundations/02-cpp-stl-and-java-collections.md), [fast I/O](../01-Foundations/06-integer-overflow-precision-and-fast-io.md) — graphs are I/O-heavy.
- [Recursion](../01-Foundations/04-recursion-brute-force-and-backtracking.md) — and why you will replace it with explicit stacks.
- [DSU](../08-Data-Structures/06-dsu-and-variants.md) and [heaps](../08-Data-Structures/10-ordered-sets-pbds-and-heaps.md) — Kruskal, offline connectivity, Dijkstra.
- [DP state design](../06-Dynamic-Programming/01-dp-first-principles-and-state-design.md) — BFS on states and DAG DP are DP.

## Recommended study order

1. **01** (BFS/DFS, iterative DFS, 0-1 BFS) → **04** (topological sort, DAG DP) → **09** (bipartite, cycles). This is the
   whole ≤1700 graph syllabus and most of the FAANG one.
2. **02** (Dijkstra first; Bellman–Ford and Floyd after) → **03** (Kruskal + DSU; Prim dense).
3. **10** (functional graphs, binary lifting) — appears constantly in Div 2 C/D.
4. **05** (SCC) → **07** (2-SAT) — the 1900–2200 pair.
5. **06** (bridges, articulation points; block-cut tree later) → **08** (Euler).
6. Revisit the 🧊/🔴 items (Johnson, Borůvka, Kruskal reconstruction tree, block-cut tree queries, segment-tree graphs) after
   [10-Trees](../10-Trees/README.md), and continue with [12-Flows-and-Matching](../12-Flows-and-Matching/README.md).

## How graphs show up in rounds

- **Div 2 A–B (≤1300):** grids and flood fill, components, "is it a tree", degrees and parity, simple BFS on numbers.
- **Div 2 C–D (1400–1900):** BFS with a twist (multi-source, 0-1, states), Dijkstra with a layer, DSU/Kruskal, topological
  order from comparisons, functional graphs (permutations, "next" pointers), bipartite coloring, cycle detection.
- **Div 2 E–F / Div 1 B–C (1900–2400):** SCC condensation + DP, 2-SAT modeling, bridges / bridge tree, MST with queries
  (forced edges, bottlenecks), shortest paths on constructed graphs (virtual vertices, segment trees), Euler tours with
  balancing, complement-graph BFS, DFS-tree constructive arguments.
- **Div 1 D+ (2400+):** block-cut trees, Kruskal reconstruction trees, dynamic connectivity offline, cycle spaces, graph
  constructions with very tight bounds; usually combined with data structures from
  [08](../08-Data-Structures/README.md) or [16](../16-IGM-Frontier/README.md).

Many strong competitors report that most graph WA/TLE at the 1600–2100 level come from implementation details rather than
ideas: recursion depth, forgetting the reverse edge, INF overflow, not resetting per test case, and visiting rules in BFS
vs Dijkstra. Every file here has a pitfalls section aimed at exactly these.

## Practice and revision

- Consolidated ladder: [problems.md](problems.md).
- Revision sheet: [09 graphs cheat sheet](../99-Cheat-Sheets/09-graphs-cheatsheet.md).
- Interview angle: [FAANG graphs](../17-FAANG-Interview-DSA/11-graphs.md) and [advanced graphs](../17-FAANG-Interview-DSA/12-advanced-graphs.md).
