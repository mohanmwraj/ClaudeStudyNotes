# 12 — Flows and Matching

Network flow is the most reusable "big hammer" in competitive programming: one solver (Dinic, plus min-cost flow) answers a whole family of questions — assignment,
disjoint paths, separation, selection with dependencies, covering — once you can translate the statement into a network. At Codeforces Div 2 it appears rarely (and mostly in disguise);
at Div 1 and at 2100–2600 it is a standard tool, and the difficulty is almost entirely in the **modeling** and in recognising the **min-max theorems** (König, Hall, Dilworth) that turn a
"find the minimum cover / check every subset" statement into a matching size.

## First-principles overview of the domain

1. **Flow = routed units.** By flow decomposition, an integral flow of value $k$ is $k$ unit paths. If every object in the statement has a "life story" that is a path through resources with limits,
   the maximum number of objects is a max flow. Integer capacities ⇒ integer optimal flow, so "each student gets one project" never splits a student.
2. **Cut = binary labeling.** A cut labels every vertex $S$ or $T$ and pays for edges from $S$ to $T$. Every edge is a penalty rule ("pay $c$ if $u$ is chosen and $v$ is not"; $\infty$ = implication).
   Max-flow min-cut says the cheapest labeling costs exactly the max flow — so min cut solves selection problems (project selection, image segmentation) that look nothing like flows.
3. **Augmenting paths are the universal improvement step.** Residual graphs let an algorithm undo earlier choices. Kuhn (matching), Ford–Fulkerson, Edmonds–Karp, Dinic, Hopcroft–Karp and successive
   shortest paths are all "find an augmenting path, flip it", differing only in which path and how many at once.
4. **Duality certifies optimality.** Every max-flow has a min cut; every maximum matching in a bipartite graph has a vertex cover of the same size (König); every min-cost flow has potentials
   proving no cheaper rerouting exists; the Hungarian algorithm's $u_i+v_j\le c_{ij}$ labels are LP dual variables. When the problem asks for the *certificate* (a cover, an antichain, a cut),
   you read it off the residual graph.
5. **Costs = shortest paths in the residual graph.** Min-cost flow is "augment along the cheapest path", made fast by Johnson potentials so Dijkstra works despite negative residual costs.
   The cost as a function of the flow value is convex, which justifies early stopping, convex per-unit costs, and Lagrangian tricks.

## The reductions to know cold

| You need | Build | Answer |
|---|---|---|
| max assignment with capacities | $s\to A\to B\to t$ | max flow |
| min edges / vertices separating $x$ and $y$ | unit capacities / split vertices | min cut, read from residual reachability |
| max disjoint routes | same networks | flow decomposition into paths |
| best subset with "needs" rules | closure network ($\infty$ implications) | $\sum$ positive profits $-$ min cut |
| min rows/columns covering marks | bipartite marks graph | König: max matching |
| max conflict-free set (bipartite conflicts) | conflict graph | $n-\nu$ |
| min chains covering an order | split graph on the transitive closure | $n-\nu$ = max antichain (Dilworth) |
| cheapest way to ship $k$ units | costs on edges | min-cost $k$-flow (SSP + potentials) |
| best perfect assignment, dense | cost matrix | Hungarian $O(n^3)$ |
| feasibility with forced minimums | lower bounds + $S^*,T^*$ | saturating flow |

## Files

| File | Band | Priority | FAANG | Summary |
|---|---|---|---|---|
| [01 — Max flow, Dinic](01-max-flow-dinic.md) | 🟣 1900–2400 | 🔥 | low | residual graphs, max-flow min-cut proof, Edmonds–Karp, Dinic with current arcs, unit-network bounds |
| [02 — Min cut & modeling](02-min-cut-and-flow-modeling.md) | 🟣 2000–2600 | 🔥 | low | canonical cut extraction, vertex splitting, Menger, project selection, segmentation, lower bounds 🟠 |
| [03 — Bipartite matching](03-bipartite-matching-kuhn-hopcroft-karp.md) | 🔵→🟣 1700–2400 | 🔥 | low | Berge, Kuhn, Hopcroft–Karp, matching via Dinic, vertex cover / independent set reconstruction |
| [04 — Min-cost flow](04-min-cost-flow.md) | 🟠 2100–2600 | 🔥 | none | successive shortest paths with potentials, negative costs, convex costs, $k$-flow vs any-flow |
| [05 — Hungarian algorithm](05-hungarian-algorithm.md) | 🟠 2000–2500 | ⚡ | low | $O(n^3)$ assignment from LP duality; maximize, rectangular, forbidden pairs |
| [06 — Matching theorems](06-matching-theorems-konig-hall-dilworth.md) | 🟣→🔴 1900–2700 | 🔥 | low | König, Hall (typed, deficiency), Dilworth, Mirsky, Gallai, path covers, Tutte 🔴, Birkhoff 🧊 |
| [problems.md](problems.md) | all | — | — | ~90 problems by rating band + LeetCode list |
| [Cheat sheet](../99-Cheat-Sheets/12-flows-and-matching-cheatsheet.md) | — | — | — | templates (C++/Java), formulas, signal → model, mistakes |

## Prerequisites

- BFS/DFS, residual-style thinking: [graph representation, BFS, DFS](../09-Graphs/01-graph-representation-bfs-dfs.md).
- Dijkstra and Bellman–Ford (for min-cost flow and potentials): [shortest paths](../09-Graphs/02-shortest-paths.md).
- Bipartiteness and 2-coloring: [bipartite graphs](../09-Graphs/09-bipartite-graphs-and-cycles.md); DAGs and topological order: [topological sort](../09-Graphs/04-topological-sort-and-dag-dp.md).
- Comfort with proofs by exchange and by contradiction: [first-principles problem solving](../00-Roadmap-and-Strategy/05-first-principles-problem-solving.md).

## Recommended study order

1. **[03](03-bipartite-matching-kuhn-hopcroft-karp.md) Kuhn first** — the smallest augmenting-path algorithm; you can use it at 1700–1900 immediately.
2. **[01](01-max-flow-dinic.md) Dinic** — memorize the template in both languages; prove max-flow min-cut once yourself.
3. **[02](02-min-cut-and-flow-modeling.md) modeling** — this is where rating comes from; do the project-selection and vertex-splitting problems.
4. **[06](06-matching-theorems-konig-hall-dilworth.md) König, Hall, Dilworth** — learn to see covers, antichains and "every subset has enough" conditions.
5. **[04](04-min-cost-flow.md) min-cost flow**, then **[05](05-hungarian-algorithm.md) Hungarian** — after you are comfortable with Dijkstra + potentials.
6. Lower bounds/circulations (02 §1), Tutte/blossom (06), push–relabel (01) only after Master-level comfort.

A reasonable plan for the Dec-2027 Master target: Kuhn + Dinic + basic modeling by 1900; König/Hall/Dilworth and min-cost flow by 2100; the 🟠/🔴 material as depth toward IGM.

## How this domain shows up in rounds

- **Div 2 A–C (≤1600):** almost never an explicit flow. You see *greedy matchings on a line* (sort + two pointers) and small cut arguments ("the answer is at most 2/4 because…").
  Recognising that the greedy is a matching helps you prove it.
- **Div 2 D–E / Div 1 B–C (1900–2400):** bipartite matching with $n\le 2000$, binary search + matching, small min-cut models, "minimum number of rows/columns" (König), Hall-type greedy checks.
  Flow problems at this level are usually solvable by Dinic within limits; the trick is the network.
- **Div 1 D+ (2400+):** min-cost flow with clever compression, lower bounds, closures with extra structure, and "the network is too big — compute its min cut by DP/segment tree".
  Educational rounds and ICPC-style sets use flows more often than regular CF rounds; AtCoder ABC G/Ex problems use them regularly (see the ABC entries in [problems.md](problems.md)).
- **Interviews:** flows are essentially absent; matching appears as small bitmask-DP assignment problems. See the LeetCode section of [problems.md](problems.md) and
  [FAANG advanced graphs](../17-FAANG-Interview-DSA/12-advanced-graphs.md).

## Links

- Consolidated ladder: [problems.md](problems.md)
- Revision: [12 — flows and matching cheat sheet](../99-Cheat-Sheets/12-flows-and-matching-cheatsheet.md)
- Related: [shortest paths](../09-Graphs/02-shortest-paths.md) (potentials), [bipartite graphs](../09-Graphs/09-bipartite-graphs-and-cycles.md), [DSU](../08-Data-Structures/06-dsu-and-variants.md) (for the "matching on a pseudoforest" tricks),
  [greedy with regret](../03-Greedy-Constructive-Interactive/02-greedy-with-heaps-and-regret.md) (simulated min-cost flow), [linear algebra tricks](../15-Advanced-Math/06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md) (Tutte matrix).
