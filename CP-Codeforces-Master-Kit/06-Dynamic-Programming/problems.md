# Dynamic Programming — Consolidated Problem Ladder

How to use this list:

1. **Do the AtCoder Educational DP Contest (A–Z) first**, in order. It is the cleanest tour of the standard state shapes; each problem isolates one idea. Ratings are estimates on the Codeforces scale.
2. **Then the CSES Dynamic Programming section** (23 tasks) — classic formulations with tight limits that punish slow constant factors (good Java practice).
3. **Then Codeforces by rating band.** Aim to solve each problem within ~45 minutes before reading the editorial; if you needed the editorial, re-solve it a week later from scratch. Hints are tags, not solutions.

Topic files: [01 first principles](01-dp-first-principles-and-state-design.md) · [02 knapsack](02-knapsack-family.md) · [03 sequences](03-sequence-dp-lis-lcs-edit-distance.md) · [04 grids](04-grid-and-path-counting-dp.md) · [05 intervals](05-interval-dp.md) · [06 bitmasks](06-bitmask-dp.md) · [07 digits](07-digit-dp.md) · [08 trees](08-tree-dp-and-rerooting.md) · [09 DAGs/graphs](09-dp-on-dags-and-graphs.md) · [10 probability](10-probability-and-expected-value-dp.md) · [11 broken profile](11-broken-profile-dp.md) · [cheat sheet](../99-Cheat-Sheets/06-dynamic-programming-cheatsheet.md)

---

## AtCoder Educational DP Contest (A–Z)

- [ ] [AtCoder DP A · Frog 1](https://atcoder.jp/contests/dp/tasks/dp_a) — ≈800 (est.) — prefix DP, two predecessors
- [ ] [AtCoder DP B · Frog 2](https://atcoder.jp/contests/dp/tasks/dp_b) — ≈900 (est.) — $k$ predecessors
- [ ] [AtCoder DP C · Vacation](https://atcoder.jp/contests/dp/tasks/dp_c) — ≈1000 (est.) — remember the last choice
- [ ] [AtCoder DP D · Knapsack 1](https://atcoder.jp/contests/dp/tasks/dp_d) — ≈1100 (est.) — 0/1 knapsack
- [ ] [AtCoder DP E · Knapsack 2](https://atcoder.jp/contests/dp/tasks/dp_e) — ≈1300 (est.) — swap value and index
- [ ] [AtCoder DP F · LCS](https://atcoder.jp/contests/dp/tasks/dp_f) — ≈1400 (est.) — two prefixes, reconstruction
- [ ] [AtCoder DP G · Longest Path](https://atcoder.jp/contests/dp/tasks/dp_g) — ≈1300 (est.) — topological order
- [ ] [AtCoder DP H · Grid 1](https://atcoder.jp/contests/dp/tasks/dp_h) — ≈1100 (est.) — grid paths with walls
- [ ] [AtCoder DP I · Coins](https://atcoder.jp/contests/dp/tasks/dp_i) — ≈1300 (est.) — forward probability
- [ ] [AtCoder DP J · Sushi](https://atcoder.jp/contests/dp/tasks/dp_j) — ≈1900 (est.) — expectation with self-loops
- [ ] [AtCoder DP K · Stones](https://atcoder.jp/contests/dp/tasks/dp_k) — ≈1300 (est.) — win/lose game states
- [ ] [AtCoder DP L · Deque](https://atcoder.jp/contests/dp/tasks/dp_l) — ≈1500 (est.) — interval game, score difference
- [ ] [AtCoder DP M · Candies](https://atcoder.jp/contests/dp/tasks/dp_m) — ≈1700 (est.) — counting knapsack + prefix sums
- [ ] [AtCoder DP N · Slimes](https://atcoder.jp/contests/dp/tasks/dp_n) — ≈1600 (est.) — interval merge
- [ ] [AtCoder DP O · Matching](https://atcoder.jp/contests/dp/tasks/dp_o) — ≈1700 (est.) — bitmask, implicit index
- [ ] [AtCoder DP P · Independent Set](https://atcoder.jp/contests/dp/tasks/dp_p) — ≈1500 (est.) — tree DP, counting
- [ ] [AtCoder DP Q · Flowers](https://atcoder.jp/contests/dp/tasks/dp_q) — ≈1900 (est.) — weighted LIS with a range-max structure
- [ ] [AtCoder DP R · Walk](https://atcoder.jp/contests/dp/tasks/dp_r) — ≈1900 (est.) — paths of length $K$, matrix power
- [ ] [AtCoder DP S · Digit Sum](https://atcoder.jp/contests/dp/tasks/dp_s) — ≈1800 (est.) — digit DP on a huge string
- [ ] [AtCoder DP T · Permutation](https://atcoder.jp/contests/dp/tasks/dp_t) — ≈2100 (est.) — relative-rank state + prefix sums
- [ ] [AtCoder DP U · Grouping](https://atcoder.jp/contests/dp/tasks/dp_u) — ≈2000 (est.) — submask DP, $3^n$
- [ ] [AtCoder DP V · Subtree](https://atcoder.jp/contests/dp/tasks/dp_v) — ≈2200 (est.) — rerooting, non-invertible combine
- [ ] [AtCoder DP W · Intervals](https://atcoder.jp/contests/dp/tasks/dp_w) — ≈2400 (est.) — DP over "last chosen position" with lazy segment tree
- [ ] [AtCoder DP X · Tower](https://atcoder.jp/contests/dp/tasks/dp_x) — ≈2100 (est.) — exchange-argument order, then knapsack
- [ ] [AtCoder DP Y · Grid 2](https://atcoder.jp/contests/dp/tasks/dp_y) — ≈2000 (est.) — few walls on a huge grid
- [ ] [AtCoder DP Z · Frog 3](https://atcoder.jp/contests/dp/tasks/dp_z) — ≈2200 (est.) — quadratic transition cost, convex hull trick

## CSES — Dynamic Programming section

- [ ] [CSES 1633 · Dice Combinations](https://cses.fi/problemset/task/1633) — ≈1000 (est.) — fix the last die
- [ ] [CSES 1634 · Minimizing Coins](https://cses.fi/problemset/task/1634) — ≈1100 (est.) — min-plus unbounded knapsack
- [ ] [CSES 1635 · Coin Combinations I](https://cses.fi/problemset/task/1635) — ≈1200 (est.) — ordered counting
- [ ] [CSES 1636 · Coin Combinations II](https://cses.fi/problemset/task/1636) — ≈1300 (est.) — unordered counting
- [ ] [CSES 1637 · Removing Digits](https://cses.fi/problemset/task/1637) — ≈1100 (est.) — DP over the value
- [ ] [CSES 1638 · Grid Paths I](https://cses.fi/problemset/task/1638) — ≈1100 (est.) — grid counting
- [ ] [CSES 1158 · Book Shop](https://cses.fi/problemset/task/1158) — ≈1300 (est.) — 0/1 knapsack, tight limits
- [ ] [CSES 1746 · Array Description](https://cses.fi/problemset/task/1746) — ≈1500 (est.) — (position, value) state
- [ ] [CSES 2413 · Counting Towers](https://cses.fi/problemset/task/2413) — ≈1800 (est.) — two-state profile per level
- [ ] [CSES 1639 · Edit Distance](https://cses.fi/problemset/task/1639) — ≈1400 (est.) — three last operations
- [ ] [CSES 3403 · Longest Common Subsequence](https://cses.fi/problemset/task/3403) — ≈1400 (est.) — LCS with reconstruction
- [ ] [CSES 1744 · Rectangle Cutting](https://cses.fi/problemset/task/1744) — ≈1500 (est.) — 2-D state, cut positions
- [ ] [CSES 3359 · Minimal Grid Path](https://cses.fi/problemset/task/3359) — ≈1700 (est.) — anti-diagonal frontier
- [ ] [CSES 1745 · Money Sums](https://cses.fi/problemset/task/1745) — ≈1300 (est.) — subset sums (bitset)
- [ ] [CSES 1097 · Removal Game](https://cses.fi/problemset/task/1097) — ≈1500 (est.) — interval game
- [ ] [CSES 1093 · Two Sets II](https://cses.fi/problemset/task/1093) — ≈1500 (est.) — count subsets, avoid double counting
- [ ] [CSES 3314 · Mountain Range](https://cses.fi/problemset/task/3314) — ≈1800 (est.) — DP in height order with nearest taller neighbours
- [ ] [CSES 1145 · Increasing Subsequence](https://cses.fi/problemset/task/1145) — ≈1300 (est.) — tails array
- [ ] [CSES 1140 · Projects](https://cses.fi/problemset/task/1140) — ≈1700 (est.) — sort by end, binary search the predecessor
- [ ] [CSES 1653 · Elevator Rides](https://cses.fi/problemset/task/1653) — ≈2000 (est.) — bitmask with a pair value
- [ ] [CSES 2181 · Counting Tilings](https://cses.fi/problemset/task/2181) — ≈2000 (est.) — broken profile
- [ ] [CSES 2220 · Counting Numbers](https://cses.fi/problemset/task/2220) — ≈1800 (est.) — digit DP with leading zeros
- [ ] [CSES 1748 · Increasing Subsequence II](https://cses.fi/problemset/task/1748) — ≈1800 (est.) — counting with a Fenwick tree

---

## Codeforces by rating

### ≤ 1400
- [ ] [CF 189A · Cut Ribbon](https://codeforces.com/problemset/problem/189/A) — 1300 — unbounded knapsack
- [ ] [CF 1178B · WOW Factor](https://codeforces.com/problemset/problem/1178/B) — 1300 — counting subsequences
- [ ] [CF 1676G · White-Black Balanced Subtrees](https://codeforces.com/problemset/problem/1676/G) — 1300 — subtree aggregates
- [ ] [CF 1937B · Binary Path](https://codeforces.com/problemset/problem/1937/B) — 1300 — 2-row grid paths
- [ ] [CF 1195C · Basketball Exercise](https://codeforces.com/problemset/problem/1195/C) — 1400 — state = last row
- [ ] [CF 698A · Vacations](https://codeforces.com/problemset/problem/698/A) — 1400 — state = last activity

### 1400–1700
- [ ] [CF 455A · Boredom](https://codeforces.com/problemset/problem/455/A) — 1500 — DP over values
- [ ] [CF 545C · Woodcutters](https://codeforces.com/problemset/problem/545/C) — 1500 — direction of the last fall
- [ ] [CF 1881E · Block Sequence](https://codeforces.com/problemset/problem/1881/E) — 1500 — suffix DP
- [ ] [CF 1272D · Remove One Element](https://codeforces.com/problemset/problem/1272/D) — 1500 — add a "used deletion" flag
- [ ] [CF 1842C · Tenzing and Balls](https://codeforces.com/problemset/problem/1842/C) — 1500 — best value per colour
- [ ] [CF 340D · Bubble Sort Graph](https://codeforces.com/problemset/problem/340/D) — 1500 — LIS in disguise
- [ ] [CF 839C · Journey](https://codeforces.com/problemset/problem/839/C) — 1500 — expectation on a tree
- [ ] [CF 1741E · Sending a Sequence Over the Network](https://codeforces.com/problemset/problem/1741/E) — 1600 — segments marked at either end
- [ ] [CF 1389B · Array Walk](https://codeforces.com/problemset/problem/1389/B) — 1600 — bounded left moves
- [ ] [CF 429B · Working out](https://codeforces.com/problemset/problem/429/B) — 1600 — four corner DPs
- [ ] [CF 1528A · Parsa's Humongous Tree](https://codeforces.com/problemset/problem/1528/A) — 1600 — tree DP on endpoint choices
- [ ] [CF 1689C · Infected Tree](https://codeforces.com/problemset/problem/1689/C) — 1600 — subtree DP

### 1700–1900
- [ ] [CF 474D · Flowers](https://codeforces.com/problemset/problem/474/D) — 1700 — counting + prefix sums
- [ ] [CF 1324E · Sleeping Schedule](https://codeforces.com/problemset/problem/1324/E) — 1700 — time of day as state
- [ ] [CF 977F · Consecutive Subsequence](https://codeforces.com/problemset/problem/977/F) — 1700 — map-indexed DP, reconstruction
- [ ] [CF 118D · Caesar's Legions](https://codeforces.com/problemset/problem/118/D) — 1700 — run-length state
- [ ] [CF 4D · Mysterious Present](https://codeforces.com/problemset/problem/4/D) — 1700 — 2-D chains
- [ ] [CF 219D · Choosing Capital for Treeland](https://codeforces.com/problemset/problem/219/D) — 1700 — rerooting
- [ ] [CF 1051D · Bicolorings](https://codeforces.com/problemset/problem/1051/D) — 1700 — column states + counter
- [ ] [CF 518D · Ilya and Escalator](https://codeforces.com/problemset/problem/518/D) — 1700 — forward probability
- [ ] [CF 1516C · Baby Ehab Partitions Again](https://codeforces.com/problemset/problem/1516/C) — 1700 — subset sum
- [ ] [CF 1695C · Zero Path](https://codeforces.com/problemset/problem/1695/C) — 1700 — min/max path sums
- [ ] [CF 919D · Substring](https://codeforces.com/problemset/problem/919/D) — 1700 — DAG DP per letter
- [ ] [CF 1625C · Road Optimization](https://codeforces.com/problemset/problem/1625/C) — 1700 — (sign, removed) state
- [ ] [CF 580D · Kefa and Dishes](https://codeforces.com/problemset/problem/580/D) — 1800 — (mask, last)
- [ ] [CF 161D · Distance in Tree](https://codeforces.com/problemset/problem/161/D) — 1800 — depth counts per subtree
- [ ] [CF 1324F · Maximum White Subtree](https://codeforces.com/problemset/problem/1324/F) — 1800 — rerooting
- [ ] [CF 1446B · Catching Cheaters](https://codeforces.com/problemset/problem/1446/B) — 1800 — LCS-shaped table
- [ ] [CF 245H · Queries for Number of Palindromes](https://codeforces.com/problemset/problem/245/H) — 1800 — interval table
- [ ] [CF 1509C · The Sports Festival](https://codeforces.com/problemset/problem/1509/C) — 1800 — interval DP after sorting
- [ ] [CF 1398D · Colored Rectangles](https://codeforces.com/problemset/problem/1398/D) — 1800 — three pointers as state
- [ ] [CF 1525D · Armchairs](https://codeforces.com/problemset/problem/1525/D) — 1800 — matching in order
- [ ] [CF 1974E · Money Buys Happiness](https://codeforces.com/problemset/problem/1974/E) — 1800 — value-indexed knapsack
- [ ] [CF 914C · Travelling Salesman and Special Numbers](https://codeforces.com/problemset/problem/914/C) — 1800 — binary digit counting
- [ ] [CF 148D · Bag of mice](https://codeforces.com/problemset/problem/148/D) — 1800 — probability game
- [ ] [CF 1915G · Bicycles](https://codeforces.com/problemset/problem/1915/G) — 1800 — Dijkstra on (city, resource)

### 1900–2100
- [ ] [CF 1155D · Beautiful Array](https://codeforces.com/problemset/problem/1155/D) — 1900 — phase automaton
- [ ] [CF 1036C · Classy Numbers](https://codeforces.com/problemset/problem/1036/C) — 1900 — digit DP, many queries
- [ ] [CF 607B · Zuma](https://codeforces.com/problemset/problem/607/B) — 1900 — interval DP
- [ ] [CF 1114D · Flood Fill](https://codeforces.com/problemset/problem/1114/D) — 1900 — interval DP on compressed runs
- [ ] [CF 149D · Coloring Brackets](https://codeforces.com/problemset/problem/149/D) — 1900 — interval + end colours
- [ ] [CF 1183H · Subsequences (hard version)](https://codeforces.com/problemset/problem/1183/H) — 1900 — distinct subsequences by length
- [ ] [CF 597C · Subsequences](https://codeforces.com/problemset/problem/597/C) — 1900 — Fenwick per length
- [ ] [CF 463D · Gargari and Permutations](https://codeforces.com/problemset/problem/463/D) — 1900 — DAG from orderings
- [ ] [CF 687C · The Values You Can Make](https://codeforces.com/problemset/problem/687/C) — 1900 — two-level subset sums
- [ ] [CF 366C · Dima and Salad](https://codeforces.com/problemset/problem/366/C) — 1900 — knapsack with offset
- [ ] [CF 19B · Checkout Assistant](https://codeforces.com/problemset/problem/19/B) — 1900 — capped knapsack
- [ ] [CF 577B · Modulo Sum](https://codeforces.com/problemset/problem/577/B) — 1900 — pigeonhole + residues
- [ ] [CF 1092F · Tree with Maximum Cost](https://codeforces.com/problemset/problem/1092/F) — 1900 — rerooting by subtraction
- [ ] [CF 16E · Fish](https://codeforces.com/problemset/problem/16/E) — 1900 — probability over masks
- [ ] [CF 1353E · K-periodic Garland](https://codeforces.com/problemset/problem/1353/E) — 1900 — per residue class phases
- [ ] [CF 2B · The least round way](https://codeforces.com/problemset/problem/2/B) — 2000 — two additive grid DPs
- [ ] [CF 213C · Relay Race](https://codeforces.com/problemset/problem/213/C) — 2000 — two walkers in lock-step
- [ ] [CF 1132F · Clear the String](https://codeforces.com/problemset/problem/1132/F) — 2000 — first element rides along
- [ ] [CF 1426F · Number of Subsequences](https://codeforces.com/problemset/problem/1426/F) — 2000 — counting with wildcards
- [ ] [CF 346B · Lucky Common Subsequence](https://codeforces.com/problemset/problem/346/B) — 2000 — LCS + automaton state
- [ ] [CF 864E · Fire](https://codeforces.com/problemset/problem/864/E) — 2000 — sort, knapsack, reconstruct
- [ ] [CF 461B · Appleman and Tree](https://codeforces.com/problemset/problem/461/B) — 2000 — tree DP, "component has a black vertex"
- [ ] [CF 895C · Square Subsets](https://codeforces.com/problemset/problem/895/C) — 2000 — mask of prime parities
- [ ] [CF 8C · Looking for Order](https://codeforces.com/problemset/problem/8/C) — 2000 — bitmask, canonical first element
- [ ] [CF 1753C · Wish I Knew How to Sort](https://codeforces.com/problemset/problem/1753/C) — 2000 — expectation, geometric waits

### 2100–2400
- [ ] [CF 1312E · Array Shrinking](https://codeforces.com/problemset/problem/1312/E) — 2100 — interval value + prefix DP
- [ ] [CF 1025D · Recovering BST](https://codeforces.com/problemset/problem/1025/D) — 2100 — interval DP with parent side
- [ ] [CF 1187E · Tree Painting](https://codeforces.com/problemset/problem/1187/E) — 2100 — rerooting
- [ ] [CF 837D · Round Subset](https://codeforces.com/problemset/problem/837/D) — 2100 — knapsack over fives
- [ ] [CF 1265E · Beautiful Mirrors](https://codeforces.com/problemset/problem/1265/E) — 2100 — cyclic expectation mod $p$
- [ ] [CF 1006F · Xor-Paths](https://codeforces.com/problemset/problem/1006/F) — 2100 — meet in the middle on a grid
- [ ] [CF 1409F · Subsequences of Length Two](https://codeforces.com/problemset/problem/1409/F) — 2100 — (position, changes, count) state
- [ ] [CF 1472G · Moving to the Capital](https://codeforces.com/problemset/problem/1472/G) — 2100 — DP over BFS layers
- [ ] [CF 1667B · Optimal Partition](https://codeforces.com/problemset/problem/1667/B) — 2100 — segment DP + data structure
- [ ] [CF 559C · Gerald and Giant Chess](https://codeforces.com/problemset/problem/559/C) — 2200 — first-obstacle counting
- [ ] [CF 11D · A Simple Task](https://codeforces.com/problemset/problem/11/D) — 2200 — counting cycles over masks
- [ ] [CF 1238E · Keyboard Purchase](https://codeforces.com/problemset/problem/1238/E) — 2200 — mask over letters, cost by contribution
- [ ] [CF 165E · Compatible Numbers](https://codeforces.com/problemset/problem/165/E) — 2200 — subset aggregation
- [ ] [CF 628D · Magic Numbers](https://codeforces.com/problemset/problem/628/D) — 2200 — digit DP, both bounds
- [ ] [CF 486E · LIS of Sequence](https://codeforces.com/problemset/problem/486/E) — 2200 — LIS from both sides
- [ ] [CF 13C · Sequence](https://codeforces.com/problemset/problem/13/C) — 2200 — DP over sorted values
- [ ] [CF 1336C · Kaavi and Magic Spell](https://codeforces.com/problemset/problem/1336/C) — 2200 — build by both ends
- [ ] [CF 280C · Game on Tree](https://codeforces.com/problemset/problem/280/C) — 2200 — linearity of expectation
- [ ] [CF 1407D · Discrete Centrifugal Jumps](https://codeforces.com/problemset/problem/1407/D) — 2200 — DAG DP + monotonic stacks
- [ ] [CF 1073E · Segment Sum](https://codeforces.com/problemset/problem/1073/E) — 2300 — digit DP with sums
- [ ] [CF 713C · Sonya and Problem Wihtout a Legend](https://codeforces.com/problemset/problem/713/C) — 2300 — shift to non-decreasing
- [ ] [CF 1203F2 · Complete the Projects (hard version)](https://codeforces.com/problemset/problem/1203/F2) — 2300 — exchange order + knapsack
- [ ] [CF 543D · Road Improvement](https://codeforces.com/problemset/problem/543/D) — 2300 — rerooting without division
- [ ] [CF 1139D · Steps to One](https://codeforces.com/problemset/problem/1139/D) — 2300 — expectation over divisors
- [ ] [CF 1540B · Tree Array](https://codeforces.com/problemset/problem/1540/B) — 2300 — pairwise probabilities on paths
- [ ] [CF 1316E · Team Building](https://codeforces.com/problemset/problem/1316/E) — 2300 — sort + mask of positions

### 2400+
- [ ] [CF 1107E · Vasya and Binary String](https://codeforces.com/problemset/problem/1107/E) — 2400 — interval DP with glued counter
- [ ] [CF 815C · Karen and Supermarket](https://codeforces.com/problemset/problem/815/C) — 2400 — tree knapsack
- [ ] [CF 24D · Broken robot](https://codeforces.com/problemset/problem/24/D) — 2400 — tridiagonal expectations
- [ ] [CF 865C · Gotta Go Fast](https://codeforces.com/problemset/problem/865/C) — 2400 — binary search on the expectation
- [ ] [CF 1473E · Minimum Path](https://codeforces.com/problemset/problem/1473/E) — 2400 — Dijkstra with two flags
- [ ] [CF 1499F · Diameter Cuts](https://codeforces.com/problemset/problem/1499/F) — 2400 — depth-bounded tree knapsack
- [ ] [CF 744C · Hongcow Buys a Deck of Cards](https://codeforces.com/problemset/problem/744/C) — 2400 — mask + saved resources
- [ ] [CF 95E · Lucky Country](https://codeforces.com/problemset/problem/95/E) — 2500 — bounded knapsack, binary splitting
- [ ] [CF 55D · Beautiful numbers](https://codeforces.com/problemset/problem/55/D) — 2500 — digit DP mod 2520
- [ ] [CF 1209E2 · Rotate Columns (hard version)](https://codeforces.com/problemset/problem/1209/E2) — 2500 — keep few columns, submask DP
- [ ] [CF 1137C · Museums Tour](https://codeforces.com/problemset/problem/1137/C) — 2500 — time-expanded SCC DP
- [ ] [CF 348D · Turtles](https://codeforces.com/problemset/problem/348/D) — 2500 — non-intersecting paths
- [ ] [CF 1188C · Array Beauty](https://codeforces.com/problemset/problem/1188/C) — 2500 — counting by threshold, pointer DP
- [ ] [CF 755F · PolandBall and Gifts](https://codeforces.com/problemset/problem/755/F) — 2600 — bitset subset sum
- [ ] [CF 650D · Zip-line](https://codeforces.com/problemset/problem/650/D) — 2600 — LIS with point changes, offline
- [ ] [CF 1278F · Cards](https://codeforces.com/problemset/problem/1278/F) — 2600 — moments via Stirling numbers
- [ ] [CF 1572C · Paint](https://codeforces.com/problemset/problem/1572/C) — 2700 — interval DP with sparse splits

---

## LeetCode (FAANG) — DP across the folder

- [ ] [LC 70 · Climbing Stairs](https://leetcode.com/problems/climbing-stairs/) — Easy — fix the last step
- [ ] [LC 198 · House Robber](https://leetcode.com/problems/house-robber/) — Medium — took previous?
- [ ] [LC 322 · Coin Change](https://leetcode.com/problems/coin-change/) — Medium — min coins
- [ ] [LC 518 · Coin Change II](https://leetcode.com/problems/coin-change-ii/) — Medium — multisets
- [ ] [LC 416 · Partition Equal Subset Sum](https://leetcode.com/problems/partition-equal-subset-sum/) — Medium — subset sum
- [ ] [LC 494 · Target Sum](https://leetcode.com/problems/target-sum/) — Medium — signed subset counting
- [ ] [LC 300 · Longest Increasing Subsequence](https://leetcode.com/problems/longest-increasing-subsequence/) — Medium — tails
- [ ] [LC 354 · Russian Doll Envelopes](https://leetcode.com/problems/russian-doll-envelopes/) — Hard — 2-D LIS tie-break
- [ ] [LC 1143 · Longest Common Subsequence](https://leetcode.com/problems/longest-common-subsequence/) — Medium — two prefixes
- [ ] [LC 72 · Edit Distance](https://leetcode.com/problems/edit-distance/) — Medium — last operation
- [ ] [LC 115 · Distinct Subsequences](https://leetcode.com/problems/distinct-subsequences/) — Hard — occurrence counting
- [ ] [LC 64 · Minimum Path Sum](https://leetcode.com/problems/minimum-path-sum/) — Medium — grid min-plus
- [ ] [LC 741 · Cherry Pickup](https://leetcode.com/problems/cherry-pickup/) — Hard — two walkers
- [ ] [LC 312 · Burst Balloons](https://leetcode.com/problems/burst-balloons/) — Hard — last balloon
- [ ] [LC 1000 · Minimum Cost to Merge Stones](https://leetcode.com/problems/minimum-cost-to-merge-stones/) — Hard — $K$-way interval merge
- [ ] [LC 664 · Strange Printer](https://leetcode.com/problems/strange-printer/) — Hard — first element rides along
- [ ] [LC 847 · Shortest Path Visiting All Nodes](https://leetcode.com/problems/shortest-path-visiting-all-nodes/) — Hard — BFS over (mask, vertex)
- [ ] [LC 1125 · Smallest Sufficient Team](https://leetcode.com/problems/smallest-sufficient-team/) — Hard — mask over skills
- [ ] [LC 902 · Numbers At Most N Given Digit Set](https://leetcode.com/problems/numbers-at-most-n-given-digit-set/) — Hard — tight flag
- [ ] [LC 233 · Number of Digit One](https://leetcode.com/problems/number-of-digit-one/) — Hard — counts with sums
- [ ] [LC 337 · House Robber III](https://leetcode.com/problems/house-robber-iii/) — Medium — tree independent set
- [ ] [LC 968 · Binary Tree Cameras](https://leetcode.com/problems/binary-tree-cameras/) — Hard — three statuses
- [ ] [LC 834 · Sum of Distances in Tree](https://leetcode.com/problems/sum-of-distances-in-tree/) — Hard — rerooting
- [ ] [LC 787 · Cheapest Flights Within K Stops](https://leetcode.com/problems/cheapest-flights-within-k-stops/) — Medium — layered Bellman–Ford
- [ ] [LC 1976 · Number of Ways to Arrive at Destination](https://leetcode.com/problems/number-of-ways-to-arrive-at-destination/) — Medium — counting shortest paths
- [ ] [LC 837 · New 21 Game](https://leetcode.com/problems/new-21-game/) — Medium — probability + sliding window
- [ ] [LC 688 · Knight Probability in Chessboard](https://leetcode.com/problems/knight-probability-in-chessboard/) — Medium — forward probability
- [ ] [LC 790 · Domino and Tromino Tiling](https://leetcode.com/problems/domino-and-tromino-tiling/) — Medium — tiny profile
- [ ] [LC 1411 · Number of Ways to Paint N × 3 Grid](https://leetcode.com/problems/number-of-ways-to-paint-n-3-grid/) — Hard — row states
