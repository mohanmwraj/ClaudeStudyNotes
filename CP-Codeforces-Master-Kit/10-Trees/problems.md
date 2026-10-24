# 10 — Trees: consolidated problem ladder

Graded by rating band, easiest first within each band. Hints name the technique family only — no spoilers. Tree-DP-heavy problems are included where a structural technique from this folder is also needed; pure DP ladders live in [06-Dynamic-Programming/problems.md](../06-Dynamic-Programming/problems.md). CSES/estimated ratings are marked `(est.)`. Files: [01](01-tree-basics-diameter-center-euler-tour.md) · [02](02-lca-and-binary-lifting.md) · [03](03-small-to-large-and-dsu-on-tree.md) · [04](04-heavy-light-decomposition.md) · [05](05-centroid-decomposition.md) · [06](06-virtual-trees.md) · [cheat sheet](../99-Cheat-Sheets/10-trees-cheatsheet.md).

## ≤ 1400

- [ ] [CF 115A · Party](https://codeforces.com/problemset/problem/115/A) — 900 — depth of a forest
- [ ] [CF 1843D · Apple Tree](https://codeforces.com/problemset/problem/1843/D) — 1200 — leaf counts per subtree
- [ ] [CF 862B · Mahmoud and Ehab and the bipartiteness](https://codeforces.com/problemset/problem/862/B) — 1300 — 2-colouring a tree
- [ ] [CF 1676G · White-Black Balanced Subtrees](https://codeforces.com/problemset/problem/1676/G) — 1300 — bottom-up subtree counts
- [ ] [CF 1675D · Vertical Paths](https://codeforces.com/problemset/problem/1675/D) — 1300 — leaves and upward chains
- [ ] [CF 1900C · Anji's Binary Tree](https://codeforces.com/problemset/problem/1900/C) — 1300 — root-to-leaf costs
- [ ] [CF 429A · Xor-tree](https://codeforces.com/problemset/problem/429/A) — 1300 — top-down greedy with depth parity
- [ ] [CF 1143C · Queen](https://codeforces.com/problemset/problem/1143/C) — 1400 — local condition per vertex
- [ ] [CSES 1674 · Subordinates](https://cses.fi/problemset/task/1674) — ≈1200 (est.) — subtree sizes, iteratively
- [ ] [CSES 1131 · Tree Diameter](https://cses.fi/problemset/task/1131) — ≈1300 (est.) — two passes

## 1400 – 1700

- [ ] [CF 580C · Kefa and Park](https://codeforces.com/problemset/problem/580/C) — 1500 — top-down state on root paths
- [ ] [CF 1325C · Ehab and Path-etic MEXs](https://codeforces.com/problemset/problem/1325/C) — 1500 — constructive, look at degrees
- [ ] [CF 1139C · Edgy Trees](https://codeforces.com/problemset/problem/1139/C) — 1500 — components + complement counting
- [ ] [CF 1336A · Linova and Kingdom](https://codeforces.com/problemset/problem/1336/A) — 1600 — contribution of depth and size
- [ ] [CF 1593E · Gardener and Tree](https://codeforces.com/problemset/problem/1593/E) — 1600 — leaf peeling
- [ ] [CF 1437D · Minimal Height Tree](https://codeforces.com/problemset/problem/1437/D) — 1600 — BFS-order structure
- [ ] [CF 1006E · Military Problem](https://codeforces.com/problemset/problem/1006/E) — 1600 — preorder and subtree ranges
- [ ] [CF 1689C · Infected Tree](https://codeforces.com/problemset/problem/1689/C) — 1600 — small tree DP on a binary tree
- [ ] [CF 1406C · Link Cut Centroids](https://codeforces.com/problemset/problem/1406/C) — 1700 — two centroids
- [ ] [CF 1881F · Minimum Maximum Distance](https://codeforces.com/problemset/problem/1881/F) — 1700 — diameter of marked vertices
- [ ] [CF 1037D · Valid BFS?](https://codeforces.com/problemset/problem/1037/D) — 1700 — order checking
- [ ] [CSES 1132 · Tree Distances I](https://cses.fi/problemset/task/1132) — ≈1500 (est.) — eccentricity lemma
- [ ] [CSES 1137 · Subtree Queries](https://cses.fi/problemset/task/1137) — ≈1500 (est.) — Euler tour + Fenwick
- [ ] [CSES 1138 · Path Queries](https://cses.fi/problemset/task/1138) — ≈1600 (est.) — root paths as subtree range updates
- [ ] [CSES 1687 · Company Queries I](https://cses.fi/problemset/task/1687) — ≈1500 (est.) — $k$-th ancestor
- [ ] [CSES 1688 · Company Queries II](https://cses.fi/problemset/task/1688) — ≈1500 (est.) — LCA
- [ ] [CSES 1135 · Distance Queries](https://cses.fi/problemset/task/1135) — ≈1500 (est.) — distance via LCA
- [ ] [CSES 2079 · Finding a Centroid](https://cses.fi/problemset/task/2079) — ≈1600 (est.) — centroid walk

## 1700 – 1900

- [ ] [CF 219D · Choosing Capital for Treeland](https://codeforces.com/problemset/problem/219/D) — 1700 — rerooting warm-up
- [ ] [CF 1805D · A Wide, Wide Graph](https://codeforces.com/problemset/problem/1805/D) — 1800 — diameter endpoints and eccentricities
- [ ] [CF 161D · Distance in Tree](https://codeforces.com/problemset/problem/161/D) — 1800 — pairs at exact distance
- [ ] [CF 1843F1 · Omsk Metro (simple version)](https://codeforces.com/problemset/problem/1843/F1) — 1800 — root-path aggregates
- [ ] [CF 1324F · Maximum White Subtree](https://codeforces.com/problemset/problem/1324/F) — 1800 — rerooting
- [ ] [CF 1856E1 · PermuTree (easy version)](https://codeforces.com/problemset/problem/1856/E1) — 1800 — subtree sizes + subset sums
- [ ] [CF 1328E · Tree Queries](https://codeforces.com/problemset/problem/1328/E) — 1900 — ancestry tests with tin/tout
- [ ] [CF 1404B · Tree Tag](https://codeforces.com/problemset/problem/1404/B) — 1900 — distances and the diameter
- [ ] [CF 14D · Two Paths](https://codeforces.com/problemset/problem/14/D) — 1900 — diameter after cutting an edge
- [ ] [CF 1702G1 · Passable Paths (easy version)](https://codeforces.com/problemset/problem/1702/G1) — 1900 — is the set a path
- [ ] [CF 191C · Fools and Roads](https://codeforces.com/problemset/problem/191/C) — 1900 — difference array on a tree
- [ ] [CF 832D · Misha, Grisha and Underground](https://codeforces.com/problemset/problem/832/D) — 1900 — path intersections via LCA
- [ ] [CF 739B · Alyona and a tree](https://codeforces.com/problemset/problem/739/B) — 1900 — lifting as a binary search
- [ ] [CF 1092F · Tree with Maximum Cost](https://codeforces.com/problemset/problem/1092/F) — 1900 — rerooting
- [ ] [CSES 1136 · Counting Paths](https://cses.fi/problemset/task/1136) — ≈1700 (est.) — difference array on a tree
- [ ] [CSES 1139 · Distinct Colors](https://cses.fi/problemset/task/1139) — ≈1700 (est.) — small-to-large

## 1900 – 2100

- [ ] [CF 1294F · Three Paths on a Tree](https://codeforces.com/problemset/problem/1294/F) — 2000 — diameter plus farthest from a path
- [ ] [CF 383C · Propagating tree](https://codeforces.com/problemset/problem/383/C) — 2000 — Euler tour with depth parity
- [ ] [CF 877E · Danil and a Part-time Job](https://codeforces.com/problemset/problem/877/E) — 2000 — Euler tour + lazy segment tree
- [ ] [CF 1304E · 1-Trees and Queries](https://codeforces.com/problemset/problem/1304/E) — 2000 — LCA distances and parity
- [ ] [CF 1702G2 · Passable Paths (hard version)](https://codeforces.com/problemset/problem/1702/G2) — 2000 — on-path tests
- [ ] [CF 1923E · Count Paths](https://codeforces.com/problemset/problem/1923/E) — 2000 — per-colour virtual trees or small-to-large
- [ ] [CF 1060E · Sergey and Subway](https://codeforces.com/problemset/problem/1060/E) — 2000 — edge contributions with parity
- [ ] [CF 1101D · GCD Counting](https://codeforces.com/problemset/problem/1101/D) — 2000 — longest path per prime
- [ ] [CF 620E · New Year Tree](https://codeforces.com/problemset/problem/620/E) — 2100 — Euler tour + bitmask segment tree
- [ ] [CF 609E · Minimum spanning tree for each edge](https://codeforces.com/problemset/problem/609/E) — 2100 — MST + path max
- [ ] [CF 519E · A and B and Lecture Rooms](https://codeforces.com/problemset/problem/519/E) — 2100 — middle vertex of a path
- [ ] [CF 208E · Blood Cousins](https://codeforces.com/problemset/problem/208/E) — 2100 — $k$-th ancestor + depth lists
- [ ] [CF 165D · Beard Graph](https://codeforces.com/problemset/problem/165/D) — 2100 — edge-valued path sums
- [ ] [CF 343D · Water Tree](https://codeforces.com/problemset/problem/343/D) — 2100 — subtree and root-path assignments
- [ ] [CF 321C · Ciel the Commander](https://codeforces.com/problemset/problem/321/C) — 2100 — centroid levels
- [ ] [CF 1790F · Timofey and Black-White Tree](https://codeforces.com/problemset/problem/1790/F) — 2100 — nearest marked vertex
- [ ] [CSES 2134 · Path Queries II](https://cses.fi/problemset/task/2134) — ≈2100 (est.) — HLD + max segment tree
- [ ] [CSES 1700 · Tree Isomorphism I](https://cses.fi/problemset/task/1700) — ≈1900 (est.) — canonical ids
- [ ] [CSES 1701 · Tree Isomorphism II](https://cses.fi/problemset/task/1701) — ≈2100 (est.) — canonical ids from the centre
- [ ] [CSES 1134 · Prüfer Code](https://cses.fi/problemset/task/1134) — ≈1900 (est.) — linear decoding

## 2100 – 2400

- [ ] [CF 932D · Tree](https://codeforces.com/problemset/problem/932/D) — 2200 — lifting over a "next larger" chain
- [ ] [CF 587C · Duff in the Army](https://codeforces.com/problemset/problem/587/C) — 2200 — small mergeable summaries on jumps
- [ ] [CF 570D · Tree Requests](https://codeforces.com/problemset/problem/570/D) — 2200 — sack with depth masks
- [ ] [CF 1156D · 0-1-Tree](https://codeforces.com/problemset/problem/1156/D) — 2200 — components / centroid counting
- [ ] [CF 1062E · Company](https://codeforces.com/problemset/problem/1062/E) — 2300 — LCA of a set via preorder extremes
- [ ] [CF 1843F2 · Omsk Metro (hard version)](https://codeforces.com/problemset/problem/1843/F2) — 2300 — non-commutative path aggregate
- [ ] [CF 600E · Lomsat gelral](https://codeforces.com/problemset/problem/600/E) — 2300 — sack
- [ ] [CF 1009F · Dominant Indices](https://codeforces.com/problemset/problem/1009/F) — 2300 — depth arrays, long-path merging
- [ ] [CF 1805E · There Should Be a Lot of Maximums](https://codeforces.com/problemset/problem/1805/E) — 2300 — subtree vs complement statistics
- [ ] [CF 1681F · Unique Occurrences](https://codeforces.com/problemset/problem/1681/F) — 2300 — per-colour structure
- [ ] [CSES 2080 · Fixed-Length Paths I](https://cses.fi/problemset/task/2080) — ≈2100 (est.) — centroid + depth counts
- [ ] [CSES 2081 · Fixed-Length Paths II](https://cses.fi/problemset/task/2081) — ≈2200 (est.) — centroid, children sorted by depth
- [ ] [CF 375D · Tree and Queries](https://codeforces.com/problemset/problem/375/D) — 2400 — sack with frequency-of-frequency
- [ ] [CF 246E · Blood Cousins Return](https://codeforces.com/problemset/problem/246/E) — 2400 — distinct values per depth
- [ ] [CF 1709E · XOR Tree](https://codeforces.com/problemset/problem/1709/E) — 2400 — small-to-large sets + greedy
- [ ] [CF 342E · Xenia and Tree](https://codeforces.com/problemset/problem/342/E) — 2400 — centroid tree
- [ ] [CF 914E · Palindromes in a Tree](https://codeforces.com/problemset/problem/914/E) — 2400 — centroid + masks
- [ ] [CF 990G · GCD Counting](https://codeforces.com/problemset/problem/990/G) — 2400 — counting by divisors on paths
- [ ] [CF 1051F · The Shortest Statement](https://codeforces.com/problemset/problem/1051/F) — 2400 — tree distances + few extra edges
- [ ] [CF 1059E · Split the Tree](https://codeforces.com/problemset/problem/1059/E) — 2400 — lifting with budgets
- [ ] [CF 1174F · Ehab and the Big Finale](https://codeforces.com/problemset/problem/1174/F) — 2400 — interactive descent along heavy paths
- [ ] [CF 916E · Jamie and Tree](https://codeforces.com/problemset/problem/916/E) — 2400 — subtree queries with a moving root

## 2400+

- [ ] [CF 1824C · LuoTianyi and XOR-Tree](https://codeforces.com/problemset/problem/1824/C) — 2500 — small-to-large maps
- [ ] [CF 778C · Peterson Polyglot](https://codeforces.com/problemset/problem/778/C) — 2500 — merging tries
- [ ] [CF 1111E · Tree](https://codeforces.com/problemset/problem/1111/E) — 2500 — key vertices with a varying root
- [ ] [CF 1023F · Mobile Phone Network](https://codeforces.com/problemset/problem/1023/F) — 2600 — path minimum assignment
- [ ] [CF 1254D · Tree Queries](https://codeforces.com/problemset/problem/1254/D) — 2700 — light-child contributions
- [ ] [CF 1149C · Tree Generator™](https://codeforces.com/problemset/problem/1149/C) — 2700 — diameter in a bracket sequence
- [ ] [CF 293E · Close Vertices](https://codeforces.com/problemset/problem/293/E) — 2700 — centroid + two constraints
- [ ] [CF 715C · Digit Tree](https://codeforces.com/problemset/problem/715/C) — 2700 — centroid + modular arithmetic
- [ ] [CF 1856E2 · PermuTree (hard version)](https://codeforces.com/problemset/problem/1856/E2) — 2700 — heavy child shortcut + bitset subset sums
- [ ] [CF 613D · Kingdom and its Cities](https://codeforces.com/problemset/problem/613/D) — 2800 — virtual tree DP
- [ ] [CF 741D · Arpa’s letter-marked tree and Mehrdad’s Dokhtar-kosh paths](https://codeforces.com/problemset/problem/741/D) — 2900 — sack over path masks
- [ ] [CF 1455G · Forbidden Value](https://codeforces.com/problemset/problem/1455/G) — 2900 — merging DP maps
- [ ] [CF 150E · Freezing with Style](https://codeforces.com/problemset/problem/150/E) — 3000 — binary search + centroid
- [ ] [CF 1320E · Treeland and Viruses](https://codeforces.com/problemset/problem/1320/E) — 3000 — virtual tree + multi-source shortest paths
- [ ] [CF 536E · Tavas on the Path](https://codeforces.com/problemset/problem/536/E) — 3100 — HLD with segment summaries

## LeetCode (trees — interview side)

- [ ] [LC 104 · Maximum Depth of Binary Tree](https://leetcode.com/problems/maximum-depth-of-binary-tree/) — Easy — depth, recursion vs iteration
- [ ] [LC 543 · Diameter of Binary Tree](https://leetcode.com/problems/diameter-of-binary-tree/) — Easy — top-vertex DP
- [ ] [LC 236 · Lowest Common Ancestor of a Binary Tree](https://leetcode.com/problems/lowest-common-ancestor-of-a-binary-tree/) — Medium — single-query LCA
- [ ] [LC 235 · Lowest Common Ancestor of a Binary Search Tree](https://leetcode.com/problems/lowest-common-ancestor-of-a-binary-search-tree/) — Medium — LCA via BST order
- [ ] [LC 310 · Minimum Height Trees](https://leetcode.com/problems/minimum-height-trees/) — Medium — centres by leaf peeling
- [ ] [LC 652 · Find Duplicate Subtrees](https://leetcode.com/problems/find-duplicate-subtrees/) — Medium — canonical subtree ids
- [ ] [LC 1443 · Minimum Time to Collect All Apples in a Tree](https://leetcode.com/problems/minimum-time-to-collect-all-apples-in-a-tree/) — Medium — Steiner subtree size
- [ ] [LC 1519 · Number of Nodes in the Sub-Tree With the Same Label](https://leetcode.com/problems/number-of-nodes-in-the-sub-tree-with-the-same-label/) — Medium — subtree counting
- [ ] [LC 2477 · Minimum Fuel Cost to Report to the Capital](https://leetcode.com/problems/minimum-fuel-cost-to-report-to-the-capital/) — Medium — per-edge contribution
- [ ] [LC 1123 · Lowest Common Ancestor of Deepest Leaves](https://leetcode.com/problems/lowest-common-ancestor-of-deepest-leaves/) — Medium — LCA of a set
- [ ] [LC 124 · Binary Tree Maximum Path Sum](https://leetcode.com/problems/binary-tree-maximum-path-sum/) — Hard — diameter DP with negative weights
- [ ] [LC 834 · Sum of Distances in Tree](https://leetcode.com/problems/sum-of-distances-in-tree/) — Hard — edge contributions + rerooting
- [ ] [LC 1483 · Kth Ancestor of a Tree Node](https://leetcode.com/problems/kth-ancestor-of-a-tree-node/) — Hard — binary lifting
- [ ] [LC 2246 · Longest Path With Different Adjacent Characters](https://leetcode.com/problems/longest-path-with-different-adjacent-characters/) — Hard — top-two branches
- [ ] [LC 2846 · Minimum Edge Weight Equilibrium Queries in a Tree](https://leetcode.com/problems/minimum-edge-weight-equilibrium-queries-in-a-tree/) — Hard — root prefix counts + LCA
- [ ] [LC 2603 · Collect Coins in a Tree](https://leetcode.com/problems/collect-coins-in-a-tree/) — Hard — pruning leaves layer by layer
- [ ] [LC 2421 · Number of Good Paths](https://leetcode.com/problems/number-of-good-paths/) — Hard — DSU merging by value
