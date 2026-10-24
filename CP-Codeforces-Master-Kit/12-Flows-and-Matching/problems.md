# Flows and Matching — Problem Ladder

Consolidated practice for [12 — Flows and Matching](README.md), easiest first inside each band. Ratings are Codeforces ratings; CSES/AtCoder/original entries show an estimate
(AtCoder numbers are AtCoder's own difficulty estimates). Hints name the *model*, not the solution. Tick `[x]` as you go.

How to use it: up to 1900, solve each problem twice — once with the general tool (Kuhn/Dinic), once with the intended greedy if there is one. From 2100 on, before coding,
write the network on paper and say in one sentence what a cut / a unit of flow means in the original problem.

## ≤ 1400

- [ ] [CF 1549B · Gregor and the Pawn Game](https://codeforces.com/problemset/problem/1549/B) — 800 — pawns to columns: greedy matching
- [ ] [CF 1797A · Li Hua and Maze](https://codeforces.com/problemset/problem/1797/A) — 800 — smallest vertex cut around a cell
- [ ] [CF 1360C · Similar Pairs](https://codeforces.com/problemset/problem/1360/C) — 1100 — pairing by parity, think of a perfect matching
- [ ] [CF 1624C · Division by Two and Permutation](https://codeforces.com/problemset/problem/1624/C) — 1100 — numbers to targets 1..n, greedy assignment (or Kuhn)
- [ ] [CF 489B · BerSU Ball](https://codeforces.com/problemset/problem/489/B) — 1200 — bipartite matching or sorted two pointers
- [ ] [AtCoder ARC092 A · 2D Plane 2N Points](https://atcoder.jp/contests/arc092/tasks/arc092_a) — ≈1268 (est.) — dominance pairs: matching with a greedy order

## 1400 – 1700

- [ ] [CSES 1694 · Download Speed](https://cses.fi/problemset/task/1694) — ≈1700 (est.) — plain maximum flow
- [ ] [CSES 1696 · School Dance](https://cses.fi/problemset/task/1696) — ≈1700 (est.) — bipartite matching, print the pairs
- [ ] [CF 1530D · Secret Santa](https://codeforces.com/problemset/problem/1530/D) — 1600 — assignment that respects as many wishes as possible
- [ ] [AtCoder PRACTICE2 D · Maxflow](https://atcoder.jp/contests/practice2/tasks/practice2_d) — ≈1700 (est.) — dominoes as a bipartite flow, rebuild the grid from the residual

## 1700 – 1900

- [ ] [CSES 1695 · Police Chase](https://cses.fi/problemset/task/1695) — ≈1800 (est.) — minimum edge cut, print it
- [ ] [CSES 1711 · Distinct Routes](https://cses.fi/problemset/task/1711) — ≈1800 (est.) — edge-disjoint paths, decompose the flow
- [ ] [CF 1437C · Chef Monocarp](https://codeforces.com/problemset/problem/1437/C) — 1800 — dishes to minutes, cost matrix
- [ ] [CF 1525D · Armchairs](https://codeforces.com/problemset/problem/1525/D) — 1800 — min-cost matching on a line
- [ ] [CF 1426E · Rock, Paper, Scissors](https://codeforces.com/problemset/problem/1426/E) — 1800 — best and worst case of a pairing game
- [ ] [CF 727D · T-shirts Distribution](https://codeforces.com/problemset/problem/727/D) — 1800 — requests with one or two options, capacities

## 1900 – 2100

- [ ] [CF 1214D · Treasure Island](https://codeforces.com/problemset/problem/1214/D) — 1900 — vertex cut of size at most 2
- [ ] [CF 965D · Single-use Stones](https://codeforces.com/problemset/problem/965/D) — 1900 — the min cut is a window
- [ ] [CF 1423B · Valuable Paper](https://codeforces.com/problemset/problem/1423/B) — 1900 — binary search + Hopcroft–Karp
- [ ] [CF 321B · Ciel and Duel](https://codeforces.com/problemset/problem/321/B) — 1900 — assignment with two kinds of targets
- [ ] [CF 237E · Build String](https://codeforces.com/problemset/problem/237/E) — 2000 — min-cost flow through letter nodes
- [ ] [CF 730I · Olympiad in Programming and Sports](https://codeforces.com/problemset/problem/730/I) — 2000 — two teams, choose students: min-cost flow or DP
- [ ] [CSES 2121 · Parcel Delivery](https://cses.fi/problemset/task/2121) — ≈2000 (est.) — min-cost k-flow
- [ ] [AtCoder PRACTICE2 E · MinCostFlow](https://atcoder.jp/contests/practice2/tasks/practice2_e) — ≈2000 (est.) — profits as negative costs with row/column limits
- [ ] [AtCoder ABC205 F · Grid and Tokens](https://atcoder.jp/contests/abc205/tasks/abc205_f) — ≈2088 (est.) — rows → split tokens → columns
- [ ] [CSES 2130 · Distinct Routes II](https://cses.fi/problemset/task/2130) — ≈2100 (est.) — k edge-disjoint paths with minimum total length

## 2100 – 2400

- [ ] [CF 546E · Soldier and Traveling](https://codeforces.com/problemset/problem/546/E) — 2100 — supplies and demands through neighbors
- [ ] [CF 498C · Array and Operations](https://codeforces.com/problemset/problem/498/C) — 2100 — per prime, b-matching odd vs even indices
- [ ] [CF 852D · Exploration plan](https://codeforces.com/problemset/problem/852/D) — 2100 — binary search on time + matching
- [ ] [CF 269C · Flawed Flow](https://codeforces.com/problemset/problem/269/C) — 2100 — conservation orients the edges
- [ ] [CF 653D · Delivery Bears](https://codeforces.com/problemset/problem/653/D) — 2200 — binary search on per-unit weight + flow
- [ ] [CF 863F · Almost Permutation](https://codeforces.com/problemset/problem/863/F) — 2200 — convex costs as unit edges
- [ ] [CF 387D · George and Interesting Graph](https://codeforces.com/problemset/problem/387/D) — 2200 — fix the center, match the rest
- [ ] [CF 1179C · Serge and Dining Room](https://codeforces.com/problemset/problem/1179/C) — 2200 — Hall-type counting with a segment tree
- [ ] [CF 1034B · Little C Loves 3 II](https://codeforces.com/problemset/problem/1034/B) — 2200 — pairs at distance 3: think matching on a grid graph
- [ ] [CSES 2129 · Task Assignment](https://cses.fi/problemset/task/2129) — ≈2200 (est.) — assignment problem
- [ ] [AtCoder ABC239 G · Builder Takahashi](https://atcoder.jp/contests/abc239/tasks/abc239_g) — ≈2215 (est.) — vertex splitting, print the removed vertices
- [ ] [AtCoder ABC247 G · Dream Team](https://atcoder.jp/contests/abc247/tasks/abc247_g) — ≈2159 (est.) — answers for every k from successive augmentations
- [ ] [AtCoder ABC318 G · Typical Path Problem](https://atcoder.jp/contests/abc318/tasks/abc318_g) — ≈2260 (est.) — two vertex-disjoint paths through a middle vertex
- [ ] [AtCoder ABC263 G · Erasing Prime Pairs](https://atcoder.jp/contests/abc263/tasks/abc263_g) — ≈2261 (est.) — odd/even split, special handling of the value 1
- [ ] [CF 311E · Biologist](https://codeforces.com/problemset/problem/311/E) — 2300 — project selection with flip costs
- [ ] [CF 510E · Fox And Dinner](https://codeforces.com/problemset/problem/510/E) — 2300 — degree-2 capacities on a parity split
- [ ] [CF 1955H · The Most Reckless Defense](https://codeforces.com/problemset/problem/1955/H) — 2300 — towers × radii assignment
- [ ] [AtCoder ABC274 G · Security Camera 3](https://atcoder.jp/contests/abc274/tasks/abc274_g) — ≈2340 (est.) — segments as vertices, cells as edges, König

## 2400+

- [ ] [CF 1082G · Petya and Graph](https://codeforces.com/problemset/problem/1082/G) — 2400 — closure: edges force their endpoints
- [ ] [CF 1139E · Maximize Mex](https://codeforces.com/problemset/problem/1139/E) — 2400 — reverse time, incremental augmenting paths
- [ ] [CF 277E · Binary Tree on Plane](https://codeforces.com/problemset/problem/277/E) — 2400 — parents with capacity 2, real costs
- [ ] [CF 1009G · Allowed Letters](https://codeforces.com/problemset/problem/1009/G) — 2400 — greedy + Hall over letter masks
- [ ] [CF 808F · Card Game](https://codeforces.com/problemset/problem/808/F) — 2400 — binary search + max independent set via min cut
- [ ] [CF 802M2 · April Fools' Problem (medium)](https://codeforces.com/problemset/problem/802/M2) — 2400 — days as a min-cost flow chain
- [ ] [CF 1913E · Matrix Problem](https://codeforces.com/problemset/problem/1913/E) — 2400 — row/column sums with change costs
- [ ] [CF 21D · Traveling Graph](https://codeforces.com/problemset/problem/21/D) — 2400 — general matching on odd vertices (bitmask DP)
- [ ] [CF 1027F · Session in BSU](https://codeforces.com/problemset/problem/1027/F) — 2400 — Hall per component on a pseudoforest
- [ ] [AtCoder ABC241 G · Round Robin](https://atcoder.jp/contests/abc241/tasks/abc241_g) — ≈2422 (est.) — remaining games as flow, per candidate
- [ ] [AtCoder ABC259 G · Grid Card Game](https://atcoder.jp/contests/abc259/tasks/abc259_g) — ≈2428 (est.) — rows and columns as items, pair penalties
- [ ] [AtCoder ABC326 G · Unlock Achievement](https://atcoder.jp/contests/abc326/tasks/abc326_g) — ≈2470 (est.) — levels as chains, achievements as closures
- [ ] [AtCoder ABC193 F · Zebraness](https://atcoder.jp/contests/abc193/tasks/abc193_f) — ≈2475 (est.) — flip a color class, then min cut
- [ ] [CF 2026E · Best Subsequence](https://codeforces.com/problemset/problem/2026/E) — 2500 — max independent set: elements vs bits
- [ ] [CF 976F · Minimal k-covering](https://codeforces.com/problemset/problem/976/F) — 2500 — lower bounds that grow with k
- [ ] [CF 1717F · Madoka and The First Session](https://codeforces.com/problemset/problem/1717/F) — 2500 — choose which edges count, flow with forced parts
- [ ] [CF 1198E · Rectangle Painting 2](https://codeforces.com/problemset/problem/1198/E) — 2500 — weighted vertex cover with compressed rows/columns
- [ ] [CF 1783F · Double Sort II](https://codeforces.com/problemset/problem/1783/F) — 2500 — cycles as vertices, indices as edges
- [ ] [CF 981F · Round Marriage](https://codeforces.com/problemset/problem/981/F) — 2500 — binary search + cyclic Hall condition
- [ ] [CF 1354F · Summoning Minions](https://codeforces.com/problemset/problem/1354/F) — 2500 — order positions × minions as an assignment
- [ ] [AtCoder ABC285 G · Tatami](https://atcoder.jp/contests/abc285/tasks/abc285_g) — ≈2566 (est.) — forced cells as lower bounds
- [ ] [AtCoder ABC317 G · Rearranging](https://atcoder.jp/contests/abc317/tasks/abc317_g) — ≈2649 (est.) — regular bipartite multigraph, peel perfect matchings
- [ ] [AtCoder ABC354 G · Select Strings](https://atcoder.jp/contests/abc354/tasks/abc354_g) — ≈2665 (est.) — maximum-weight antichain via min cut
- [ ] [AtCoder ABC237 H · Hakata](https://atcoder.jp/contests/abc237/tasks/abc237_h) — ≈2807 (est.) — maximum antichain (Dilworth)
- [ ] [CF 1061E · Politics](https://codeforces.com/problemset/problem/1061/E) — 2600 — two trees of constraints, min-cost flow
- [ ] [CF 818G · Four Melodies](https://codeforces.com/problemset/problem/818/G) — 2600 — k disjoint subsequences, compressed network
- [ ] [CF 1107F · Vasya and Endless Credits](https://codeforces.com/problemset/problem/1107/F) — 2600 — offers × months, maximize
- [ ] [CF 1510B · Button Lock](https://codeforces.com/problemset/problem/1510/B) — 2600 — chain cover with costs
- [ ] [CF 1146G · Zoning Restrictions](https://codeforces.com/problemset/problem/1146/G) — 2700 — chain per item min cut
- [ ] [CF 1264E · Beautiful League](https://codeforces.com/problemset/problem/1264/E) — 2700 — convex costs on tournament results
- [ ] [CF 1404E · Bricks](https://codeforces.com/problemset/problem/1404/E) — 2800 — König on joints
- [ ] [CF 1572D · Bridge Club](https://codeforces.com/problemset/problem/1572/D) — 2800 — keep only the heaviest edges, then matching
- [ ] [CF 280D · k-Maximum Subsequence Sum](https://codeforces.com/problemset/problem/280/D) — 2800 — min-cost flow simulated with a segment tree
- [ ] [CF 1919F2 · Wine Factory (Hard Version)](https://codeforces.com/problemset/problem/1919/F2) — 2800 — min cut maintained by a segment tree
- [ ] [CF 1592F2 · Alice and Recoloring 2](https://codeforces.com/problemset/problem/1592/F2) — 2800 — matching on special cells
- [ ] [CF 1288F · Red-Blue Graph](https://codeforces.com/problemset/problem/1288/F) — 2900 — lower bounds + costs
- [ ] [CF 708D · Incorrect Flow](https://codeforces.com/problemset/problem/708/D) — 2900 — min-cost repair of a flow
- [ ] [CF 103E · Buying Sets](https://codeforces.com/problemset/problem/103/E) — 2900 — closure made well-posed by a perfect matching
- [ ] [CF 724E · Goods transportation](https://codeforces.com/problemset/problem/724/E) — 2900 — min cut by DP, the network is too big
- [ ] [CF 1307G · Cow and Exercise](https://codeforces.com/problemset/problem/1307/G) — 3100 — parametric min-cost flow
- [ ] [AtCoder ABC214 H · Collecting](https://atcoder.jp/contests/abc214/tasks/abc214_h) — ≈3138 (est.) — condensation + profits with k paths
- [ ] [CF 1630F · Making It Bipartite](https://codeforces.com/problemset/problem/1630/F) — 3400 — split vertices, Dilworth on a DAG

## LeetCode (interview-sized versions of these ideas)

- [ ] [LC 455 · Assign Cookies](https://leetcode.com/problems/assign-cookies/) — Easy — matching on a line: sort + two pointers
- [ ] [LC 2410 · Maximum Matching of Players With Trainers](https://leetcode.com/problems/maximum-matching-of-players-with-trainers/) — Medium — matching on a line: sort + two pointers
- [ ] [LC 826 · Most Profit Assigning Work](https://leetcode.com/problems/most-profit-assigning-work/) — Medium — assign each worker the best job it can do
- [ ] [LC 2071 · Maximum Number of Tasks You Can Assign](https://leetcode.com/problems/maximum-number-of-tasks-you-can-assign/) — Hard — binary search + greedy matching
- [ ] [LC 1820 · Maximum Number of Accepted Invitations](https://leetcode.com/problems/maximum-number-of-accepted-invitations/) — Medium 🔒 — plain bipartite matching (Kuhn)
- [ ] [LC 1349 · Maximum Students Taking Exam](https://leetcode.com/problems/maximum-students-taking-exam/) — Hard — max independent set in a bipartite graph = seats − matching
- [ ] [LC 2123 · Minimum Operations to Remove Adjacent Ones in Matrix](https://leetcode.com/problems/minimum-operations-to-remove-adjacent-ones-in-matrix/) — Hard 🔒 — min vertex cover = matching (König)
- [ ] [LC 1947 · Maximum Compatibility Score Sum](https://leetcode.com/problems/maximum-compatibility-score-sum/) — Medium — assignment, maximize (bitmask DP or Hungarian)
- [ ] [LC 1066 · Campus Bikes II](https://leetcode.com/problems/campus-bikes-ii/) — Medium 🔒 — rectangular min-cost assignment
- [ ] [LC 1879 · Minimum XOR Sum of Two Arrays](https://leetcode.com/problems/minimum-xor-sum-of-two-arrays/) — Hard — assignment with XOR costs
- [ ] [LC 2172 · Maximum AND Sum of Array](https://leetcode.com/problems/maximum-and-sum-of-array/) — Hard — numbers × slots (each slot twice), maximize
- [ ] [LC 2850 · Minimum Moves to Spread Stones Over Grid](https://leetcode.com/problems/minimum-moves-to-spread-stones-over-grid/) — Medium — surplus stones × empty cells, Manhattan costs
- [ ] [LC 1595 · Minimum Cost to Connect Two Groups of Points](https://leetcode.com/problems/minimum-cost-to-connect-two-groups-of-points/) — Hard — minimum-cost edge cover of a bipartite graph
- [ ] [LC 300 · Longest Increasing Subsequence](https://leetcode.com/problems/longest-increasing-subsequence/) — Medium — Mirsky: LIS = minimum number of non-increasing piles
- [ ] [LC 354 · Russian Doll Envelopes](https://leetcode.com/problems/russian-doll-envelopes/) — Hard — longest chain in a 2D dominance order

## Checklist before you call a problem "done"

- [ ] I can explain the network and what each unit of flow (or each side of the cut) means.
- [ ] I proved both directions of the correspondence (solution → flow and flow → solution).
- [ ] I know the size of the network and why Dinic / Hopcroft–Karp / SSP fits the time limit.
- [ ] If the problem prints a certificate (cut, cover, antichain, assignment), I read it from the residual graph and checked it independently on small cases.
