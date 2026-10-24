# 08 — Data Structures: Consolidated Problem Ladder

Work top to bottom; inside a band, the order is roughly easiest first. Hints name the *structure or idea*, not the solution.
Codeforces ratings are the official ones; CSES and AtCoder Library Practice problems carry an estimate. Topic files: [README](README.md) · cheat sheet: [08 cheat sheet](../99-Cheat-Sheets/08-data-structures-cheatsheet.md).

## ≤ 1400

- [ ] [CSES 1647 · Static Range Minimum Queries](https://cses.fi/problemset/task/1647) — ≈1200 (est.) — sparse table
- [ ] [CSES 1091 · Concert Tickets](https://cses.fi/problemset/task/1091) — ≈1200 (est.) — multiset, largest ≤ x, erase one
- [ ] [CF 1520D · Same Differences](https://codeforces.com/problemset/problem/1520/D) — 1200 — hash a key derived from (value, index)
- [ ] [CF 4C · Registration System](https://codeforces.com/problemset/problem/4/C) — 1300 — hash map of counts
- [ ] [CSES 1648 · Dynamic Range Sum Queries](https://cses.fi/problemset/task/1648) — ≈1300 (est.) — BIT, assign as add-delta
- [ ] [CSES 1649 · Dynamic Range Minimum Queries](https://cses.fi/problemset/task/1649) — ≈1300 (est.) — bottom-up segment tree
- [ ] [CSES 1651 · Range Update Queries](https://cses.fi/problemset/task/1651) — ≈1300 (est.) — BIT over differences
- [ ] [AtCoder PRACTICE2 A · Disjoint Set Union](https://atcoder.jp/contests/practice2/tasks/practice2_a) — ≈1200 (est.) — DSU template
- [ ] [AtCoder PRACTICE2 B · Fenwick Tree](https://atcoder.jp/contests/practice2/tasks/practice2_b) — ≈1200 (est.) — BIT template
- [ ] [CSES 1676 · Road Construction](https://cses.fi/problemset/task/1676) — ≈1400 (est.) — DSU with sizes and a running max
- [ ] [CSES 1661 · Subarray Sums II](https://cses.fi/problemset/task/1661) — ≈1400 (est.) — prefix sums + safe hashing
- [ ] [CF 1167C · News Distribution](https://codeforces.com/problemset/problem/1167/C) — 1400 — DSU component sizes
- [ ] [CF 277A · Learning Languages](https://codeforces.com/problemset/problem/277/A) — 1400 — DSU with virtual nodes
- [ ] [CF 1559D1 · Mocha and Diana (Easy Version)](https://codeforces.com/problemset/problem/1559/D1) — 1400 — two DSUs

## 1400–1700

- [ ] [CF 1915F · Greetings](https://codeforces.com/problemset/problem/1915/F) — 1500 — count nested pairs
- [ ] [CF 1676H2 · Maximum Crossings (Hard Version)](https://codeforces.com/problemset/problem/1676/H2) — 1500 — inversion count with ties
- [ ] [CF 356A · Knight Tournament](https://codeforces.com/problemset/problem/356/A) — 1500 — skip processed indices
- [ ] [CF 1263D · Secret Passwords](https://codeforces.com/problemset/problem/1263/D) — 1500 — DSU through shared letters
- [ ] [CF 977E · Cyclic Components](https://codeforces.com/problemset/problem/977/E) — 1500 — components + degree check
- [ ] [CF 1791F · Range Update Point Query](https://codeforces.com/problemset/problem/1791/F) — 1500 — each element changes few times
- [ ] [CSES 1143 · Hotel Queries](https://cses.fi/problemset/task/1143) — ≈1500 (est.) — max tree descent
- [ ] [CF 1234D · Distinct Characters Queries](https://codeforces.com/problemset/problem/1234/D) — 1600 — 26 sets or bitmask segment tree
- [ ] [CF 722C · Destroying Array](https://codeforces.com/problemset/problem/722/C) — 1600 — reverse time
- [ ] [CF 731C · Socks](https://codeforces.com/problemset/problem/731/C) — 1600 — DSU + majority colour per component
- [ ] [CF 1029C · Maximal Intersection](https://codeforces.com/problemset/problem/1029/C) — 1600 — multisets of endpoints
- [ ] [CF 1526C2 · Potions (Hard Version)](https://codeforces.com/problemset/problem/1526/C2) — 1600 — heap with regret
- [ ] [CF 1353D · Constructing the Array](https://codeforces.com/problemset/problem/1353/D) — 1600 — heap of segments with a tie-break
- [ ] [CSES 1739 · Forest Queries II](https://cses.fi/problemset/task/1739) — ≈1600 (est.) — 2D BIT
- [ ] [CF 339D · Xenia and Bit Operations](https://codeforces.com/problemset/problem/339/D) — 1700 — level-dependent combine
- [ ] [CF 1594D · The Number of Imposters](https://codeforces.com/problemset/problem/1594/D) — 1700 — parity DSU
- [ ] [CSES 1749 · List Removals](https://cses.fi/problemset/task/1749) — ≈1700 (est.) — k-th alive by descent
- [ ] [CSES 2163 · Josephus Problem II](https://cses.fi/problemset/task/2163) — ≈1700 (est.) — order statistics
- [ ] [CSES 1076 · Sliding Window Median](https://cses.fi/problemset/task/1076) — ≈1700 (est.) — two multisets / lazy heaps
- [ ] [CSES 1135 · Distance Queries](https://cses.fi/problemset/task/1135) — ≈1700 (est.) — LCA by Euler tour + RMQ

## 1700–1900

- [ ] [CF 220B · Little Elephant and Array](https://codeforces.com/problemset/problem/220/B) — 1800 — few candidate values, offline
- [ ] [CF 459D · Pashmak and Parmida's problem](https://codeforces.com/problemset/problem/459/D) — 1800 — prefix/suffix counts + BIT
- [ ] [CF 1042D · Petya and Array](https://codeforces.com/problemset/problem/1042/D) — 1800 — BIT over compressed prefix sums
- [ ] [CF 652D · Nested Segments](https://codeforces.com/problemset/problem/652/D) — 1800 — sweep + BIT
- [ ] [CF 1227D2 · Optimal Subsequences (Hard Version)](https://codeforces.com/problemset/problem/1227/D2) — 1800 — offline by k, k-th
- [ ] [CF 1548B · Integers Have Friends](https://codeforces.com/problemset/problem/1548/B) — 1800 — gcd of differences
- [ ] [CF 1691D · Max GEQ Sum](https://codeforces.com/problemset/problem/1691/D) — 1800 — nearest greater + range max of prefix sums
- [ ] [CF 863D · Yet Another Array Queries Problem](https://codeforces.com/problemset/problem/863/D) — 1800 — trace positions (or implicit treap)
- [ ] [CF 482B · Interesting Array](https://codeforces.com/problemset/problem/482/B) — 1800 — per-bit difference arrays + range AND check
- [ ] [CF 1213G · Path Queries](https://codeforces.com/problemset/problem/1213/G) — 1800 — offline DSU by weight
- [ ] [CSES 1190 · Subarray Sum Queries](https://cses.fi/problemset/task/1190) — ≈1800 (est.) — 4-field node
- [ ] [CSES 1144 · Salary Queries](https://cses.fi/problemset/task/1144) — ≈1800 (est.) — compression or dynamic tree
- [ ] [CF 61E · Enemy is weak](https://codeforces.com/problemset/problem/61/E) — 1900 — middle element decomposition
- [ ] [CF 1311F · Moving Points](https://codeforces.com/problemset/problem/1311/F) — 1900 — BIT of counts and sums
- [ ] [CF 1354D · Multiset](https://codeforces.com/problemset/problem/1354/D) — 1900 — BIT k-th in tight memory
- [ ] [CF 914D · Bash and a Tough Math Puzzle](https://codeforces.com/problemset/problem/914/D) — 1900 — gcd tree, count failing leaves early
- [ ] [CF 1547F · Array Stabilization (GCD version)](https://codeforces.com/problemset/problem/1547/F) — 1900 — doubled array + gcd table
- [ ] [CF 566D · Restructuring Company](https://codeforces.com/problemset/problem/566/D) — 1900 — two DSUs
- [ ] [CF 25D · Roads not only in Berland](https://codeforces.com/problemset/problem/25/D) — 1900 — redundant edges vs components
- [ ] [CF 1620E · Replace the Numbers](https://codeforces.com/problemset/problem/1620/E) — 1900 — process in reverse with a value map
- [ ] [CSES 1734 · Distinct Values Queries](https://cses.fi/problemset/task/1734) — ≈1900 (est.) — sort by right end
- [ ] [CSES 2166 · Prefix Sum Queries](https://cses.fi/problemset/task/2166) — ≈1900 (est.) — (sum, best prefix) node
- [ ] [CSES 1735 · Range Updates and Sums](https://cses.fi/problemset/task/1735) — ≈1900 (est.) — assign + add tags
- [ ] [CSES 1737 · Range Queries and Copies](https://cses.fi/problemset/task/1737) — ≈1900 (est.) — path copying
- [ ] [CSES 2072 · Cut and Paste](https://cses.fi/problemset/task/2072) — ≈1900 (est.) — implicit treap

## 1900–2100

- [ ] [CF 380C · Sereja and Brackets](https://codeforces.com/problemset/problem/380/C) — 2000 — (matched, open, close) node
- [ ] [CF 242E · XOR on Segment](https://codeforces.com/problemset/problem/242/E) — 2000 — per-bit counts + xor tag
- [ ] [CF 877E · Danil and a Part-time Job](https://codeforces.com/problemset/problem/877/E) — 2000 — Euler tour + flip tag
- [ ] [CF 383C · Propagating tree](https://codeforces.com/problemset/problem/383/C) — 2000 — Euler tour + signed adds by depth parity
- [ ] [CF 1288E · Messenger Simulator](https://codeforces.com/problemset/problem/1288/E) — 2000 — BIT over a padded position array
- [ ] [CF 359D · Pair of Numbers](https://codeforces.com/problemset/problem/359/D) — 2000 — gcd = min, monotone in length
- [ ] [CF 514D · R2D2 and Droid Army](https://codeforces.com/problemset/problem/514/D) — 2000 — two pointers + per-type max
- [ ] [CF 475D · CGCDSSQ](https://codeforces.com/problemset/problem/475/D) — 2000 — few distinct gcds per endpoint
- [ ] [CF 797E · Array Queries](https://codeforces.com/problemset/problem/797/E) — 2000 — threshold on k
- [ ] [CF 1514D · Cut and Stick](https://codeforces.com/problemset/problem/1514/D) — 2000 — range majority frequency
- [ ] [CF 776D · The Door Problem](https://codeforces.com/problemset/problem/776/D) — 2000 — parity constraints
- [ ] [CF 659F · Polycarp and Hay](https://codeforces.com/problemset/problem/659/F) — 2000 — cells in decreasing order + DSU
- [ ] [CF 920F · SUM and REPLACE](https://codeforces.com/problemset/problem/920/F) — 2000 — values stabilise quickly (potential)
- [ ] [CSES 1736 · Polynomial Queries](https://cses.fi/problemset/task/1736) — ≈2000 (est.) — arithmetic-progression tags
- [ ] [AtCoder PRACTICE2 K · Range Affine Range Sum](https://atcoder.jp/contests/practice2/tasks/practice2_k) — ≈2000 (est.) — affine monoid action
- [ ] [CF 474F · Ant colony](https://codeforces.com/problemset/problem/474/F) — 2100 — gcd and count of minimum
- [ ] [CF 689D · Friends and Subsequences](https://codeforces.com/problemset/problem/689/D) — 2100 — monotone difference, two binary searches
- [ ] [CF 703D · Mishka and Interesting sum](https://codeforces.com/problemset/problem/703/D) — 2100 — xor of distinct, offline by right end
- [ ] [CF 343D · Water Tree](https://codeforces.com/problemset/problem/343/D) — 2100 — Euler tour + assign
- [ ] [CF 620E · New Year Tree](https://codeforces.com/problemset/problem/620/E) — 2100 — colour bitmask + assign tag
- [ ] [CF 1207F · Remainder Problem](https://codeforces.com/problemset/problem/1207/F) — 2100 — small/large modulus
- [ ] [CF 103D · Time to Raid Cowavans](https://codeforces.com/problemset/problem/103/D) — 2100 — offline by step + threshold
- [ ] [CF 1555E · Boring Segments](https://codeforces.com/problemset/problem/1555/E) — 2100 — two pointers + coverage min tree
- [ ] [CF 920E · Connected Components?](https://codeforces.com/problemset/problem/920/E) — 2100 — complement graph BFS with a set of unvisited
- [ ] [CF 609E · Minimum spanning tree for each edge](https://codeforces.com/problemset/problem/609/E) — 2100 — Kruskal + path max
- [ ] [CSES 2074 · Reversals and Sums](https://cses.fi/problemset/task/2074) — ≈2100 (est.) — implicit treap with sums

## 2100–2400

- [ ] [CF 52C · Circular RMQ](https://codeforces.com/problemset/problem/52/C) — 2200 — add/min lazy, line-based input
- [ ] [CF 86D · Powerful array](https://codeforces.com/problemset/problem/86/D) — 2200 — Mo
- [ ] [CF 617E · XOR and Favorite Number](https://codeforces.com/problemset/problem/617/E) — 2200 — Mo on prefix xors
- [ ] [CF 813E · Army Creation](https://codeforces.com/problemset/problem/813/E) — 2200 — online, k-th previous occurrence
- [ ] [CF 707D · Persistent Bookcase](https://codeforces.com/problemset/problem/707/D) — 2200 — version tree + undo
- [ ] [CF 1179C · Serge and Dining Room](https://codeforces.com/problemset/problem/1179/C) — 2200 — balance tree + descent
- [ ] [CF 1557D · Ezzat and Grid](https://codeforces.com/problemset/problem/1557/D) — 2200 — DP with max tree over compressed columns
- [ ] [CF 1567E · Non-Decreasing Dilemma](https://codeforces.com/problemset/problem/1567/E) — 2200 — runs node
- [ ] [CF 438D · The Child and Sequence](https://codeforces.com/problemset/problem/438/D) — 2300 — range mod by potential
- [ ] [CF 558E · A Simple Task](https://codeforces.com/problemset/problem/558/E) — 2300 — 26 counting trees with assign
- [ ] [CF 915E · Physical Education Lessons](https://codeforces.com/problemset/problem/915/E) — 2300 — dynamic tree or interval map
- [ ] [CF 600E · Lomsat gelral](https://codeforces.com/problemset/problem/600/E) — 2300 — merging or small-to-large
- [ ] [CF 1009F · Dominant Indices](https://codeforces.com/problemset/problem/1009/F) — 2300 — merging depth trees
- [ ] [CF 718C · Sasha and Array](https://codeforces.com/problemset/problem/718/C) — 2300 — matrix tags
- [ ] [CF 817F · MEX Queries](https://codeforces.com/problemset/problem/817/F) — 2300 — assign/flip + first zero
- [ ] [CF 85D · Sum of Medians](https://codeforces.com/problemset/problem/85/D) — 2300 — sums by index mod 5 in a tree
- [ ] [CF 610D · Vika and Segments](https://codeforces.com/problemset/problem/610/D) — 2300 — union of segments by sweep

## 2400+

- [ ] [CF 342E · Xenia and Tree](https://codeforces.com/problemset/problem/342/E) — 2400 — rebuild every √q (or centroid)
- [ ] [CF 375D · Tree and Queries](https://codeforces.com/problemset/problem/375/D) — 2400 — subtree counts of counts
- [ ] [CF 1000F · One Occurrence](https://codeforces.com/problemset/problem/1000/F) — 2400 — prev/next occurrence + offline min
- [ ] [CF 145E · Lucky Queries](https://codeforces.com/problemset/problem/145/E) — 2400 — node for both flip states
- [ ] [CF 446C · DZY Loves Fibonacci Numbers](https://codeforces.com/problemset/problem/446/C) — 2400 — Fibonacci-progression tags
- [ ] [CF 1114F · Please, another Queries on Array?](https://codeforces.com/problemset/problem/1114/F) — 2400 — product tags + prime masks
- [ ] [CF 1093E · Intersection of Permutations](https://codeforces.com/problemset/problem/1093/E) — 2400 — 2D counting with updates
- [ ] [CF 1044D · Deduction Queries](https://codeforces.com/problemset/problem/1044/D) — 2400 — xor potentials on compressed prefixes
- [ ] [CF 865D · Buy Low Sell High](https://codeforces.com/problemset/problem/865/D) — 2400 — heap with regret
- [ ] [CF 911G · Mass Change Queries](https://codeforces.com/problemset/problem/911/G) — 2500 — split/merge value trees
- [ ] [CF 840D · Destiny](https://codeforces.com/problemset/problem/840/D) — 2500 — persistent descent by frequency
- [ ] [CF 484E · Sign on Fence](https://codeforces.com/problemset/problem/484/E) — 2500 — persistent runs node + binary search
- [ ] [CF 341D · Iahub and Xors](https://codeforces.com/problemset/problem/341/D) — 2500 — 2D BIT with parity classes
- [ ] [CF 687D · Dividing Kingdom II](https://codeforces.com/problemset/problem/687/D) — 2500 — parity DSU over sorted edges
- [ ] [CF 940F · Machine Learning](https://codeforces.com/problemset/problem/940/F) — 2600 — Mo with updates
- [ ] [CF 896C · Willem, Chtholly and Seniorious](https://codeforces.com/problemset/problem/896/C) — 2600 — interval map on random data
- [ ] [CF 13E · Holes](https://codeforces.com/problemset/problem/13/E) — 2700 — block jump pointers
- [ ] [CF 455D · Serega and Fun](https://codeforces.com/problemset/problem/455/D) — 2700 — blocks with deques and counts
- [ ] [CF 702F · T-Shirts](https://codeforces.com/problemset/problem/702/F) — 2800 — treap with amortised re-insertion
- [ ] [CF 1290E · Cartesian Tree](https://codeforces.com/problemset/problem/1290/E) — 3300 — segment tree beats with adds

## LeetCode (folder topics)

- [ ] [LC 307 · Range Sum Query - Mutable](https://leetcode.com/problems/range-sum-query-mutable/) — Medium — BIT / segment tree
- [ ] [LC 547 · Number of Provinces](https://leetcode.com/problems/number-of-provinces/) — Medium — DSU
- [ ] [LC 684 · Redundant Connection](https://leetcode.com/problems/redundant-connection/) — Medium — DSU cycle edge
- [ ] [LC 721 · Accounts Merge](https://leetcode.com/problems/accounts-merge/) — Medium — DSU with virtual nodes
- [ ] [LC 399 · Evaluate Division](https://leetcode.com/problems/evaluate-division/) — Medium — weighted DSU
- [ ] [LC 146 · LRU Cache](https://leetcode.com/problems/lru-cache/) — Medium — hash map + linked list
- [ ] [LC 215 · Kth Largest Element in an Array](https://leetcode.com/problems/kth-largest-element-in-an-array/) — Medium — heap / quickselect
- [ ] [LC 347 · Top K Frequent Elements](https://leetcode.com/problems/top-k-frequent-elements/) — Medium — counts + heap
- [ ] [LC 1146 · Snapshot Array](https://leetcode.com/problems/snapshot-array/) — Medium — fat-node versioning
- [ ] [LC 295 · Find Median from Data Stream](https://leetcode.com/problems/find-median-from-data-stream/) — Hard — two heaps
- [ ] [LC 480 · Sliding Window Median](https://leetcode.com/problems/sliding-window-median/) — Hard — lazy deletion / multisets
- [ ] [LC 315 · Count of Smaller Numbers After Self](https://leetcode.com/problems/count-of-smaller-numbers-after-self/) — Hard — BIT over values
- [ ] [LC 493 · Reverse Pairs](https://leetcode.com/problems/reverse-pairs/) — Hard — BIT / merge sort
- [ ] [LC 327 · Count of Range Sum](https://leetcode.com/problems/count-of-range-sum/) — Hard — BIT over prefix sums
- [ ] [LC 2179 · Count Good Triplets in an Array](https://leetcode.com/problems/count-good-triplets-in-an-array/) — Hard — left × right counts
- [ ] [LC 850 · Rectangle Area II](https://leetcode.com/problems/rectangle-area-ii/) — Hard — cover-count sweep
- [ ] [LC 732 · My Calendar III](https://leetcode.com/problems/my-calendar-iii/) — Hard — dynamic add/max tree
- [ ] [LC 2407 · Longest Increasing Subsequence II](https://leetcode.com/problems/longest-increasing-subsequence-ii/) — Hard — max tree over values
- [ ] [LC 2286 · Booking Concert Tickets in Groups](https://leetcode.com/problems/booking-concert-tickets-in-groups/) — Hard — descent
- [ ] [LC 2382 · Maximum Segment Sum After Removals](https://leetcode.com/problems/maximum-segment-sum-after-removals/) — Hard — reverse DSU
- [ ] [LC 1697 · Checking Existence of Edge Length Limited Paths](https://leetcode.com/problems/checking-existence-of-edge-length-limited-paths/) — Hard — offline DSU by threshold
- [ ] [LC 460 · LFU Cache](https://leetcode.com/problems/lfu-cache/) — Hard — frequency buckets
- [ ] [LC 1157 · Online Majority Element In Subarray](https://leetcode.com/problems/online-majority-element-in-subarray/) — Hard — threshold / random sampling
