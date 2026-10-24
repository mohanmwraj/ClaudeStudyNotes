# 03 — Greedy, Constructive, Interactive: problem ladder

Consolidated ladder for [01 greedy](01-greedy-and-exchange-arguments.md), [02 heaps and regret](02-greedy-with-heaps-and-regret.md),
[03 constructive](03-constructive-algorithms.md), [04 invariants](04-invariants-parity-and-ad-hoc-observations.md) and
[05 interactive](05-interactive-problems.md). Ratings are Codeforces ratings; CSES/AtCoder problems carry an estimate.
Hints name the technique family only. Work a band until you solve most problems without hints, then move up; for every
greedy or constructive problem, write the brute force and the checker even after AC — that habit is the real training.

Tags: **G** greedy/exchange · **H** heap/regret · **C** constructive · **I** invariant/ad hoc · **Q** interactive.

## ≤ 1400

- [ ] [CF 1343B · Balanced Array](https://codeforces.com/problemset/problem/1343/B) — 800 — C, parity of sums
- [ ] [CF 1454A · Special Permutation](https://codeforces.com/problemset/problem/1454/A) — 800 — C, shift
- [ ] [CF 1406A · Subset Mex](https://codeforces.com/problemset/problem/1406/A) — 900 — I, MEX counting
- [ ] [CF 1567B · MEXor Mixup](https://codeforces.com/problemset/problem/1567/B) — 1000 — I, XOR of a prefix of naturals
- [ ] [CF 1352B · Same Parity Summands](https://codeforces.com/problemset/problem/1352/B) — 1200 — C/I, parity
- [ ] [CF 545D · Queue](https://codeforces.com/problemset/problem/545/D) — 1300 — G, exchange
- [ ] [CF 1365B · Trouble Sort](https://codeforces.com/problemset/problem/1365/B) — 1300 — I, what can move
- [ ] [CF 1401C · Mere Array](https://codeforces.com/problemset/problem/1401/C) — 1300 — I, gcd and the minimum
- [ ] [CF 1335D · Anti-Sudoku](https://codeforces.com/problemset/problem/1335/D) — 1300 — C, one change per block
- [ ] [CF 1521B · Nastia and a Good Array](https://codeforces.com/problemset/problem/1521/B) — 1300 — C, coprime neighbours via the minimum
- [ ] [CF 1381A1 · Prefix Flip (Easy Version)](https://codeforces.com/problemset/problem/1381/A1) — 1300 — C, operation budget
- [ ] [CF 1988C · Increasing Sequence with Fixed OR](https://codeforces.com/problemset/problem/1988/C) — 1300 — C, bits
- [ ] [CF 1498B · Box Fitting](https://codeforces.com/problemset/problem/1498/B) — 1300 — H, largest first
- [ ] [CF 1807E · Interview](https://codeforces.com/problemset/problem/1807/E) — 1300 — Q, binary search
- [ ] [CF 479C · Exams](https://codeforces.com/problemset/problem/479/C) — 1400 — G, stays ahead
- [ ] [CF 1369C · RationalLee](https://codeforces.com/problemset/problem/1369/C) — 1400 — G, assignment by exchange
- [ ] [CF 1375C · Element Extermination](https://codeforces.com/problemset/problem/1375/C) — 1400 — I, monovariant
- [ ] [CF 520B · Two Buttons](https://codeforces.com/problemset/problem/520/B) — 1400 — I, think in reverse
- [ ] [CF 1515C · Phoenix and Towers](https://codeforces.com/problemset/problem/1515/C) — 1400 — H/C, smallest tower
- [ ] [CF 1463B · Find The Array](https://codeforces.com/problemset/problem/1463/B) — 1400 — C, powers of two
- [ ] [CF 679A · Bear and Prime 100](https://codeforces.com/problemset/problem/679/A) — 1400 — Q, choose the divisors
- [ ] [CF 1167B · Lost Numbers](https://codeforces.com/problemset/problem/1167/B) — 1400 — Q, products identify pairs
- [ ] [CSES 1629 · Movie Festival](https://cses.fi/problemset/task/1629) — ≈1200 (est.) — G, interval scheduling
- [ ] [CSES 1619 · Restaurant Customers](https://cses.fi/problemset/task/1619) — ≈1200 (est.) — G, sweep
- [ ] [CSES 1630 · Tasks and Deadlines](https://cses.fi/problemset/task/1630) — ≈1300 (est.) — G, exchange
- [ ] [CSES 2183 · Missing Coin Sum](https://cses.fi/problemset/task/2183) — ≈1400 (est.) — G/I, reachable prefix
- [ ] [CSES 1092 · Two Sets](https://cses.fi/problemset/task/1092) — ≈1200 (est.) — C, parity of the total
- [ ] [CSES 2205 · Gray Code](https://cses.fi/problemset/task/2205) — ≈1200 (est.) — C, induction
- [ ] [CSES 1754 · Coin Piles](https://cses.fi/problemset/task/1754) — ≈1300 (est.) — I, sum and ratio conditions

## 1400–1700

- [ ] [CF 545C · Woodcutters](https://codeforces.com/problemset/problem/545/C) — 1500 — G, left first
- [ ] [CF 1066B · Heaters](https://codeforces.com/problemset/problem/1066/B) — 1500 — G, covering
- [ ] [CF 1203E · Boxers](https://codeforces.com/problemset/problem/1203/E) — 1500 — G, sort and try smallest
- [ ] [CF 1526C1 · Potions (Easy Version)](https://codeforces.com/problemset/problem/1526/C1) — 1500 — H or DP
- [ ] [CF 1526C2 · Potions (Hard Version)](https://codeforces.com/problemset/problem/1526/C2) — 1600 — H, evict the worst
- [ ] [CF 1140C · Playlist](https://codeforces.com/problemset/problem/1140/C) — 1600 — H, sweep one key, heap the other
- [ ] [CF 1779C · Least Prefix Sum](https://codeforces.com/problemset/problem/1779/C) — 1600 — H, fix prefixes with a heap
- [ ] [CF 1336A · Linova and Kingdom](https://codeforces.com/problemset/problem/1336/A) — 1600 — G, contribution key
- [ ] [CF 1251C · Minimize The Integer](https://codeforces.com/problemset/problem/1251/C) — 1600 — G/I, what can pass what
- [ ] [CF 1352G · Special Permutation](https://codeforces.com/problemset/problem/1352/G) — 1600 — C, explorer
- [ ] [CF 1364C · Ehab and Prefix MEXs](https://codeforces.com/problemset/problem/1364/C) — 1600 — C, MEX
- [ ] [CF 1503A · Balance the Bits](https://codeforces.com/problemset/problem/1503/A) — 1600 — C, necessary counts first
- [ ] [CF 1396A · Multiples of Length](https://codeforces.com/problemset/problem/1396/A) — 1600 — C, three fixed operations
- [ ] [CF 1371D · Grid-00100](https://codeforces.com/problemset/problem/1371/D) — 1600 — C, diagonals
- [ ] [CF 1458A · Row GCD](https://codeforces.com/problemset/problem/1458/A) — 1600 — I, gcd of differences
- [ ] [CF 1294D · MEX maximizing](https://codeforces.com/problemset/problem/1294/D) — 1600 — I, residues
- [ ] [CF 1305C · Kuroni and Impossible Calculation](https://codeforces.com/problemset/problem/1305/C) — 1600 — I, pigeonhole
- [ ] [CF 1520F1 · Guess the K-th Zero (Easy version)](https://codeforces.com/problemset/problem/1520/F1) — 1600 — Q, binary search on counts
- [ ] [CF 1486C1 · Guessing the Greatest (easy version)](https://codeforces.com/problemset/problem/1486/C1) — 1600 — Q, halve around the second max
- [ ] [CF 1407C · Chocolate Bunny](https://codeforces.com/problemset/problem/1407/C) — 1600 — Q, compare by remainders
- [ ] [CF 1698D · Fixed Point Guessing](https://codeforces.com/problemset/problem/1698/D) — 1600 — Q, parity of a count
- [ ] [CSES 2214 · Inverse Inversions](https://cses.fi/problemset/task/2214) — ≈1500 (est.) — C, extremes first
- [ ] [CSES 1161 · Stick Divisions](https://cses.fi/problemset/task/1161) — ≈1500 (est.) — G, reverse the process
- [ ] [CSES 1164 · Room Allocation](https://cses.fi/problemset/task/1164) — ≈1500 (est.) — G/H, earliest free room
- [ ] [AtCoder ABC137 D · Summer Vacation](https://atcoder.jp/contests/abc137/tasks/abc137_d) — ≈1300 (est.) — H, deadlines

## 1700–1900

- [ ] [CF 632C · The Smallest String Concatenation](https://codeforces.com/problemset/problem/632/C) — 1700 — G, comparator
- [ ] [CF 1157C2 · Increasing Subsequence (hard version)](https://codeforces.com/problemset/problem/1157/C2) — 1700 — G, both ends
- [ ] [CF 1325D · Ehab the Xorcist](https://codeforces.com/problemset/problem/1325/D) — 1700 — C, sum vs XOR
- [ ] [CF 1381A2 · Prefix Flip (Hard Version)](https://codeforces.com/problemset/problem/1381/A2) — 1700 — C, operation budget
- [ ] [CF 1144F · Graph Without Long Directed Paths](https://codeforces.com/problemset/problem/1144/F) — 1700 — C, bipartite orientation
- [ ] [CF 1516C · Baby Ehab Partitions Again](https://codeforces.com/problemset/problem/1516/C) — 1700 — I, parity of powers of two
- [ ] [CF 1479A · Searching Local Minimum](https://codeforces.com/problemset/problem/1479/A) — 1700 — Q, border invariant
- [ ] [CF 1146C · Tree Diameter](https://codeforces.com/problemset/problem/1146/C) — 1700 — Q, split by bits
- [ ] [CF 1010B · Rocket](https://codeforces.com/problemset/problem/1010/B) — 1800 — Q, learn the lie pattern first
- [ ] [CSES 2215 · Monotone Subsequences](https://cses.fi/problemset/task/2215) — ≈1700 (est.) — C, Erdős–Szekeres blocks
- [ ] [CSES 2423 · Filling Trominos](https://cses.fi/problemset/task/2423) — ≈1900 (est.) — C, decompose into small tileable blocks
- [ ] [CSES 1632 · Movie Festival II](https://cses.fi/problemset/task/1632) — ≈1700 (est.) — G/H, multiset of end times

## 1900–2100

- [ ] [CF 1375D · Replace by MEX](https://codeforces.com/problemset/problem/1375/D) — 1900 — C, fix one position per MEX
- [ ] [CF 1486C2 · Guessing the Greatest (hard version)](https://codeforces.com/problemset/problem/1486/C2) — 1900 — Q, side then binary search
- [ ] [CF 1207E · XOR Guessing](https://codeforces.com/problemset/problem/1207/E) — 1900 — Q, bits by design
- [ ] [CF 1305D · Kuroni and the Celebration](https://codeforces.com/problemset/problem/1305/D) — 1900 — Q, remove leaves in pairs
- [ ] [CF 1385E · Directing Edges](https://codeforces.com/problemset/problem/1385/E) — 2000 — C, topological order
- [ ] [CF 1438C · Engineer Artem](https://codeforces.com/problemset/problem/1438/C) — 2000 — C, parity colouring
- [ ] [CF 1416B · Make Them Equal](https://codeforces.com/problemset/problem/1416/B) — 2000 — C, gather then distribute
- [ ] [CF 1349B · Orac and Medians](https://codeforces.com/problemset/problem/1349/B) — 2000 — I, local pattern decides
- [ ] [CF 730I · Olympiad in Programming and Sports](https://codeforces.com/problemset/problem/730/I) — 2000 — H, regret / flow
- [ ] [CF 843B · Interactive LowerBound](https://codeforces.com/problemset/problem/843/B) — 2000 — Q, random sampling

## 2100–2400

- [ ] [CF 1203F1 · Complete the Projects (easy version)](https://codeforces.com/problemset/problem/1203/F1) — 2100 — G, exchange key for negatives
- [ ] [CF 1271D · Portals](https://codeforces.com/problemset/problem/1271/D) — 2100 — H, defend as late as possible
- [ ] [CF 1003E · Tree Constructing](https://codeforces.com/problemset/problem/1003/E) — 2100 — C, diameter first
- [ ] [CF 1363D · Guess The Maximums](https://codeforces.com/problemset/problem/1363/D) — 2100 — Q, one binary search for the maximum
- [ ] [CF 1039B · Subway Pursuit](https://codeforces.com/problemset/problem/1039/B) — 2100 — Q, shrink then guess
- [ ] [CF 1428E · Carrots for Rabbits](https://codeforces.com/problemset/problem/1428/E) — 2200 — H, convex marginal gains
- [ ] [CF 958E2 · Guard Duty (medium)](https://codeforces.com/problemset/problem/958/E2) — 2200 — H, regret on a linked list
- [ ] [CF 1110E · Magic Stones](https://codeforces.com/problemset/problem/1110/E) — 2200 — I, differences
- [ ] [CF 1311E · Construct the Binary Tree](https://codeforces.com/problemset/problem/1311/E) — 2200 — C, adjust from extremes
- [ ] [CF 1305E · Kuroni and the Score Distribution](https://codeforces.com/problemset/problem/1305/E) — 2200 — C, count triples, then pad
- [ ] [CF 1520F2 · Guess the K-th Zero (Hard version)](https://codeforces.com/problemset/problem/1520/F2) — 2200 — Q, cache plus a Fenwick tree
- [ ] [CF 1114E · Arithmetic Progression](https://codeforces.com/problemset/problem/1114/E) — 2200 — Q, binary search the max, sample the rest
- [ ] [CF 1203F2 · Complete the Projects (hard version)](https://codeforces.com/problemset/problem/1203/F2) — 2300 — G + DP

## 2400+

- [ ] [CF 865D · Buy Low Sell High](https://codeforces.com/problemset/problem/865/D) — 2400 — H, regret token
- [ ] [CF 1251E2 · Voting (Hard Version)](https://codeforces.com/problemset/problem/1251/E2) — 2400 — H, process thresholds downward
- [ ] [CF 1174F · Ehab and the Big Finale](https://codeforces.com/problemset/problem/1174/F) — 2400 — Q, heavy path halving
- [ ] [CF 1375E · Inversion SwapSort](https://codeforces.com/problemset/problem/1375/E) — 2500 — C, ordering the swaps
- [ ] [CF 3D · Least Cost Bracket Sequence](https://codeforces.com/problemset/problem/3/D) — 2600 — H, cheapest flip
- [ ] [CF 436E · Cardboard Box](https://codeforces.com/problemset/problem/436/E) — 2600 — H, several regret options
- [ ] [CF 797F · Mice and Holes](https://codeforces.com/problemset/problem/797/F) — 2600 — H/DP, matching on a line
- [ ] [CF 1391E · Pairs of Pairs](https://codeforces.com/problemset/problem/1391/E) — 2600 — C, DFS tree dichotomy
- [ ] [CF 1270G · Subset with Zero Sum](https://codeforces.com/problemset/problem/1270/G) — 2700 — C/I, pigeonhole as a functional graph
- [ ] [CF 1365G · Secure Password](https://codeforces.com/problemset/problem/1365/G) — 2800 — Q, query design as codes

## LeetCode

**Greedy and intervals**
- [ ] [LC 455 · Assign Cookies](https://leetcode.com/problems/assign-cookies/) — Easy
- [ ] [LC 1710 · Maximum Units on a Truck](https://leetcode.com/problems/maximum-units-on-a-truck/) — Easy
- [ ] [LC 435 · Non-overlapping Intervals](https://leetcode.com/problems/non-overlapping-intervals/) — Medium
- [ ] [LC 452 · Minimum Number of Arrows to Burst Balloons](https://leetcode.com/problems/minimum-number-of-arrows-to-burst-balloons/) — Medium
- [ ] [LC 253 · Meeting Rooms II](https://leetcode.com/problems/meeting-rooms-ii/) — Medium 🔒
- [ ] [LC 45 · Jump Game II](https://leetcode.com/problems/jump-game-ii/) — Medium
- [ ] [LC 134 · Gas Station](https://leetcode.com/problems/gas-station/) — Medium
- [ ] [LC 179 · Largest Number](https://leetcode.com/problems/largest-number/) — Medium
- [ ] [LC 406 · Queue Reconstruction by Height](https://leetcode.com/problems/queue-reconstruction-by-height/) — Medium
- [ ] [LC 763 · Partition Labels](https://leetcode.com/problems/partition-labels/) — Medium
- [ ] [LC 135 · Candy](https://leetcode.com/problems/candy/) — Hard

**Heaps and regret**
- [ ] [LC 1642 · Furthest Building You Can Reach](https://leetcode.com/problems/furthest-building-you-can-reach/) — Medium
- [ ] [LC 1353 · Maximum Number of Events That Can Be Attended](https://leetcode.com/problems/maximum-number-of-events-that-can-be-attended/) — Medium
- [ ] [LC 621 · Task Scheduler](https://leetcode.com/problems/task-scheduler/) — Medium
- [ ] [LC 630 · Course Schedule III](https://leetcode.com/problems/course-schedule-iii/) — Hard
- [ ] [LC 871 · Minimum Number of Refueling Stops](https://leetcode.com/problems/minimum-number-of-refueling-stops/) — Hard
- [ ] [LC 502 · IPO](https://leetcode.com/problems/ipo/) — Hard
- [ ] [LC 857 · Minimum Cost to Hire K Workers](https://leetcode.com/problems/minimum-cost-to-hire-k-workers/) — Hard

**Constructive, invariants, interactive-style APIs**
- [ ] [LC 942 · DI String Match](https://leetcode.com/problems/di-string-match/) — Easy
- [ ] [LC 667 · Beautiful Arrangement II](https://leetcode.com/problems/beautiful-arrangement-ii/) — Medium
- [ ] [LC 932 · Beautiful Array](https://leetcode.com/problems/beautiful-array/) — Medium
- [ ] [LC 89 · Gray Code](https://leetcode.com/problems/gray-code/) — Medium
- [ ] [LC 991 · Broken Calculator](https://leetcode.com/problems/broken-calculator/) — Medium
- [ ] [LC 287 · Find the Duplicate Number](https://leetcode.com/problems/find-the-duplicate-number/) — Medium
- [ ] [LC 780 · Reaching Points](https://leetcode.com/problems/reaching-points/) — Hard
- [ ] [LC 278 · First Bad Version](https://leetcode.com/problems/first-bad-version/) — Easy
- [ ] [LC 162 · Find Peak Element](https://leetcode.com/problems/find-peak-element/) — Medium
- [ ] [LC 1095 · Find in Mountain Array](https://leetcode.com/problems/find-in-mountain-array/) — Hard
- [ ] [LC 843 · Guess the Word](https://leetcode.com/problems/guess-the-word/) — Hard
