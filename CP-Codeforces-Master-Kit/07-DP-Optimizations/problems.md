# 07 — DP Optimisations: Problem Ladder

Consolidated ladder for [01](01-prefix-sum-and-monotonic-queue-optimization.md)–[08](08-matrix-exponentiation-for-dp.md). Hints name the technique only (in this folder that is the point) — not the reduction. Codeforces ratings are the official ones; CSES and Educational-DP problems have estimates; AtCoder contest problems show the AtCoder difficulty estimate. Tags: `[PS]` prefix sums, `[MQ]` monotonic queue / running best, `[CHT]` hull / Li Chao, `[DC]` divide & conquer, `[KN]` Knuth, `[SOS]` subset transforms, `[AL]` Aliens, `[ST]` slope trick, `[MX]` matrix power.

Rule for all of them: write the naive DP first, then optimise and compare on random small inputs.

## ≤ 1400

- [ ] [CF 185A · Plant](https://codeforces.com/problemset/problem/185/A) — 1300 — `[MX]` 2-state linear recurrence, huge $n$

## 1400–1700

- [ ] [CF 166E · Tetrahedron](https://codeforces.com/problemset/problem/166/E) — 1500 — `[MX]` walks of length $n$ (also has an $O(n)$ answer — do both)
- [ ] [CF 1941E · Rudolf and k Bridges](https://codeforces.com/problemset/problem/1941/E) — 1600 — `[MQ]` window minimum per row
- [ ] [CF 1994C · Hungry Games](https://codeforces.com/problemset/problem/1994/C) — 1600 — `[PS]` suffix DP with a pointer

## 1700–1900

- [ ] [CF 474D · Flowers](https://codeforces.com/problemset/problem/474/D) — 1700 — `[PS]` linear DP + prefix sums for queries
- [ ] [CF 1829H · Don't Blame Me](https://codeforces.com/problemset/problem/1829/H) — 1700 — `[SOS]` DP over the 64 AND values
- [ ] [CF 678D · Iterated Linear Function](https://codeforces.com/problemset/problem/678/D) — 1700 — `[MX]` affine map as a 2×2 matrix
- [ ] [CF 1525D · Armchairs](https://codeforces.com/problemset/problem/1525/D) — 1800 — `[MQ]` fold the running best into the recurrence
- [ ] [CF 2025D · Attribute Checks](https://codeforces.com/problemset/problem/2025/D) — 1800 — `[PS]` lazy range additions with a difference array
- [ ] [CSES 1722 · Fibonacci Numbers](https://cses.fi/problemset/task/1722) — ≈1700 (est.) — `[MX]` the template
- [ ] [CSES 1096 · Throwing Dice](https://cses.fi/problemset/task/1096) — ≈1800 (est.) — `[MX]` 6×6 companion matrix
- [ ] [AtCoder DP N · Slimes](https://atcoder.jp/contests/dp/tasks/dp_n) — ≈1700 (est.) — `[KN]` naive passes; use it to test your Knuth
- [ ] [AtCoder DP M · Candies](https://atcoder.jp/contests/dp/tasks/dp_m) — ≈1800 (est.) — `[PS]` window sums of the previous layer

## 1900–2100

- [ ] [CF 479E · Riding in a Lift](https://codeforces.com/problemset/problem/479/E) — 1900 — `[PS]` push transitions to ranges
- [ ] [CF 1077F1 · Pictures with Kittens (easy version)](https://codeforces.com/problemset/problem/1077/F1) — 1900 — write the $O(xnk)$ DP
- [ ] [CF 1918D · Blocking Elements](https://codeforces.com/problemset/problem/1918/D) — 1900 — `[MQ]` binary search outside, deque inside
- [ ] [CF 1932F · Feed Cats](https://codeforces.com/problemset/problem/1932/F) — 1900 — `[MQ]` running best with a left limit
- [ ] [CF 222E · Decoding Genome](https://codeforces.com/problemset/problem/222/E) — 1900 — `[MX]` transition matrix over letters
- [ ] [CF 691E · Xor-sequences](https://codeforces.com/problemset/problem/691/E) — 1900 — `[MX]` adjacency by popcount
- [ ] [CF 940E · Cashback](https://codeforces.com/problemset/problem/940/E) — 2000 — `[MQ]` window minimum after a key observation
- [ ] [CF 1716D · Chip Move](https://codeforces.com/problemset/problem/1716/D) — 2000 — `[PS]` running sums inside residue classes
- [ ] [CF 621E · Wet Shark and Blocks](https://codeforces.com/problemset/problem/621/E) — 2000 — `[MX]` states = remainders
- [ ] [AtCoder DP Z · Frog 3](https://atcoder.jp/contests/dp/tasks/dp_z) — ≈1900 (est.) — `[CHT]` monotone deque
- [ ] [AtCoder DP R · Walk](https://atcoder.jp/contests/dp/tasks/dp_r) — ≈1900 (est.) — `[MX]` walks of length $K$
- [ ] [CSES 1723 · Graph Paths I](https://cses.fi/problemset/task/1723) — ≈1900 (est.) — `[MX]` counting walks
- [ ] [CSES 1724 · Graph Paths II](https://cses.fi/problemset/task/1724) — ≈2000 (est.) — `[MX]` $(\min,+)$ power
- [ ] [CSES 1159 · Book Shop II](https://cses.fi/problemset/task/1159) — ≈2000 (est.) — `[MQ]` bounded knapsack
- [ ] [CSES 2084 · Monster Game I](https://cses.fi/problemset/task/2084) — ≈2000 (est.) — `[CHT]` both sides monotone
- [ ] [CSES 1654 · SOS Bit Problem](https://cses.fi/problemset/task/1654) — ≈2000 (est.) — `[SOS]` subsets and supersets
- [ ] [AtCoder ABC127 F · Absolute Minima](https://atcoder.jp/contests/abc127/tasks/abc127_f) — AtCoder ≈2003 — `[ST]` the median form

## 2100–2400

- [ ] [CF 1077F2 · Pictures with Kittens (hard version)](https://codeforces.com/problemset/problem/1077/F2) — 2100 — `[MQ]` layered window max
- [ ] [CF 372C · Watching Fireworks is Fun](https://codeforces.com/problemset/problem/372/C) — 2100 — `[MQ]` two-sided window
- [ ] [CF 319C · Kalila and Dimna in the Logging Industry](https://codeforces.com/problemset/problem/319/C) — 2100 — `[CHT]` mind the overflow
- [ ] [CF 1117D · Magic Gems](https://codeforces.com/problemset/problem/1117/D) — 2100 — `[MX]` $M \times M$ companion matrix
- [ ] [CF 954F · Runner's Problem](https://codeforces.com/problemset/problem/954/F) — 2100 — `[MX]` piecewise-constant transitions
- [ ] [CF 821E · Okabe and El Psy Kongroo](https://codeforces.com/problemset/problem/821/E) — 2100 — `[MX]` one matrix per segment
- [ ] [CF 1407D · Discrete Centrifugal Jumps](https://codeforces.com/problemset/problem/1407/D) — 2200 — `[MQ]` monotonic stacks as predecessor sets
- [ ] [CF 833B · The Bakery](https://codeforces.com/problemset/problem/833/B) — 2200 — `[DC]` maximisation, moving window
- [ ] [CF 165E · Compatible Numbers](https://codeforces.com/problemset/problem/165/E) — 2200 — `[SOS]` witness over submasks
- [ ] [CF 1234F · Yet Another Substring Reverse](https://codeforces.com/problemset/problem/1234/F) — 2200 — `[SOS]` max over submasks
- [ ] [CF 958E2 · Guard Duty (medium)](https://codeforces.com/problemset/problem/958/E2) — 2200 — `[AL]` or a greedy with heaps
- [ ] [CF 13C · Sequence](https://codeforces.com/problemset/problem/13/C) — 2200 — `[ST]` non-decreasing with minimum change
- [ ] [CF 713C · Sonya and Problem Wihtout a Legend](https://codeforces.com/problemset/problem/713/C) — 2300 — `[ST]` strictly increasing version
- [ ] [CF 718C · Sasha and Array](https://codeforces.com/problemset/problem/718/C) — 2300 — `[MX]` segment tree of matrices
- [ ] [CF 1182E · Product Oriented Recurrence](https://codeforces.com/problemset/problem/1182/E) — 2300 — `[MX]` exponents mod $p-1$
- [ ] [CSES 2085 · Monster Game II](https://cses.fi/problemset/task/2085) — ≈2200 (est.) — `[CHT]` Li Chao
- [ ] [CSES 2086 · Subarray Squares](https://cses.fi/problemset/task/2086) — ≈2200 (est.) — `[DC]` `[CHT]` `[KN]` `[AL]` — solve it four ways
- [ ] [CSES 2088 · Knuth Division](https://cses.fi/problemset/task/2088) — ≈2200 (est.) — `[KN]`
- [ ] [CSES 2087 · Houses and Schools](https://cses.fi/problemset/task/2087) — ≈2300 (est.) — `[DC]` / `[KN]` with median costs
- [ ] [AtCoder ARC100 E · Or Plus Max](https://atcoder.jp/contests/arc100/tasks/arc100_c) — AtCoder ≈2111 — `[SOS]` top-two over submasks

## 2400+

- [ ] [CF 1083E · The Fair Nut and Rectangles](https://codeforces.com/problemset/problem/1083/E) — 2400 — `[CHT]` sort first
- [ ] [CF 311B · Cats Transport](https://codeforces.com/problemset/problem/311/B) — 2400 — `[CHT]` / `[DC]` layered
- [ ] [CF 643C · Levels and Regions](https://codeforces.com/problemset/problem/643/C) — 2400 — `[CHT]` / `[DC]` / `[AL]`
- [ ] [CF 1715E · Long Way Home](https://codeforces.com/problemset/problem/1715/E) — 2400 — `[CHT]` / `[DC]` inside Dijkstra rounds
- [ ] [CF 1585F · Non-equal Neighbours](https://codeforces.com/problemset/problem/1585/F) — 2400 — `[MQ]` stack of minima, alternating signs
- [ ] [CF 449D · Jzzhu and Numbers](https://codeforces.com/problemset/problem/449/D) — 2400 — `[SOS]` + inclusion–exclusion
- [ ] [CF 1620G · Subsequences Galore](https://codeforces.com/problemset/problem/1620/G) — 2400 — `[SOS]` superset sums
- [ ] [CF 865D · Buy Low Sell High](https://codeforces.com/problemset/problem/865/D) — 2400 — `[ST]` heap form
- [ ] [CF 1609E · William The Oblivious](https://codeforces.com/problemset/problem/1609/E) — 2400 — `[MX]` $(\min,+)$ matrices in a segment tree
- [ ] [CF 1106F · Lunar New Year and a Recursive Sequence](https://codeforces.com/problemset/problem/1106/F) — 2400 — `[MX]` exponent recurrence + discrete log
- [ ] [CF 868F · Yet Another Minimization Problem](https://codeforces.com/problemset/problem/868/F) — 2500 — `[DC]` canonical moving-window cost
- [ ] [CF 1527E · Partition Game](https://codeforces.com/problemset/problem/1527/E) — 2500 — `[DC]` or segment tree
- [ ] [CF 660F · Bear and Bowling 4](https://codeforces.com/problemset/problem/660/F) — 2500 — `[CHT]` arbitrary queries
- [ ] [CF 1043F · Make It One](https://codeforces.com/problemset/problem/1043/F) — 2500 — `[SOS]`-style counting on divisors
- [ ] [CF 147B · Smile House](https://codeforces.com/problemset/problem/147/B) — 2500 — `[MX]` $(\max,+)$ powers + binary search
- [ ] [CF 321E · Ciel and Gondolas](https://codeforces.com/problemset/problem/321/E) — 2600 — `[DC]` / `[KN]` / `[AL]`, heavy input
- [ ] [CF 631E · Product Sum](https://codeforces.com/problemset/problem/631/E) — 2600 — `[CHT]` two directions
- [ ] [CF 1661F · Teleporters](https://codeforces.com/problemset/problem/1661/F) — 2600 — `[AL]` binary search on a marginal gain
- [ ] [CF 1208F · Bits And Pieces](https://codeforces.com/problemset/problem/1208/F) — 2600 — `[SOS]` keep two witnesses
- [ ] [CF 662C · Binary Table](https://codeforces.com/problemset/problem/662/C) — 2600 — `[SOS]` XOR convolution
- [ ] [CF 914G · Sum the Fibonacci](https://codeforces.com/problemset/problem/914/G) — 2600 — `[SOS]` all three convolutions
- [ ] [CF 1530F · Bingo](https://codeforces.com/problemset/problem/1530/F) — 2600 — `[SOS]` inclusion–exclusion over lines
- [ ] [CF 932F · Escape Through Leaf](https://codeforces.com/problemset/problem/932/F) — 2700 — `[CHT]` Li Chao merging
- [ ] [CF 1179D · Fedor Runs for President](https://codeforces.com/problemset/problem/1179/D) — 2700 — `[CHT]` on a tree
- [ ] [CF 1303G · Sum of Prefix Sums](https://codeforces.com/problemset/problem/1303/G) — 2700 — `[CHT]` + centroid decomposition
- [ ] [CF 383E · Vowels](https://codeforces.com/problemset/problem/383/E) — 2700 — `[SOS]` complement counting
- [ ] [CF 772D · Varying Kibibits](https://codeforces.com/problemset/problem/772/D) — 2700 — `[SOS]` digit-wise zeta
- [ ] [CF 576D · Flights for Regular Customers](https://codeforces.com/problemset/problem/576/D) — 2700 — `[MX]` boolean matrix powers
- [ ] [CF 1279F · New Year and Handle Change](https://codeforces.com/problemset/problem/1279/F) — 2800 — `[AL]`
- [ ] [AtCoder ABC218 H · Red and Blue Lamps](https://atcoder.jp/contests/abc218/tasks/abc218_h) — AtCoder ≈2805 — `[AL]`
- [ ] [CF 455E · Function](https://codeforces.com/problemset/problem/455/E) — 2900 — `[CHT]` offline
- [ ] [CF 802M3 · April Fools' Problem (hard)](https://codeforces.com/problemset/problem/802/M3) — 2900 — `[AL]` + flow intuition
- [ ] [CF 1603D · Artistic Partition](https://codeforces.com/problemset/problem/1603/D) — 3000 — `[DC]` number-theoretic cost
- [ ] [CF 739E · Gosha is hunting](https://codeforces.com/problemset/problem/739/E) — 3000 — `[AL]` (twice)
- [ ] [CF 280E · Sequence Transformation](https://codeforces.com/problemset/problem/280/E) — 3000 — `[ST]` with reconstruction
- [ ] [AtCoder ABC217 H · Snuketoon](https://atcoder.jp/contests/abc217/tasks/abc217_h) — AtCoder ≈3112 — `[ST]` window minimum on breakpoints
- [ ] [AtCoder ARC070 E · NarrowRectangles](https://atcoder.jp/contests/arc070/tasks/arc070_c) — AtCoder ≈3365 — `[ST]`
- [ ] [CF 1326F2 · Wise Men (Hard Version)](https://codeforces.com/problemset/problem/1326/F2) — 3200 — `[SOS]` partitions of $n$ + OR transforms
- [ ] [CF 1534G · A New Beginning](https://codeforces.com/problemset/problem/1534/G) — 3300 — `[ST]` after a coordinate rotation

## LeetCode

- [ ] [LC 121 · Best Time to Buy and Sell Stock](https://leetcode.com/problems/best-time-to-buy-and-sell-stock/) — Easy — `[MQ]` running minimum
- [ ] [LC 509 · Fibonacci Number](https://leetcode.com/problems/fibonacci-number/) — Easy — `[MX]` the $O(\log n)$ follow-up
- [ ] [LC 1014 · Best Sightseeing Pair](https://leetcode.com/problems/best-sightseeing-pair/) — Medium — `[MQ]` separate the terms
- [ ] [LC 1696 · Jump Game VI](https://leetcode.com/problems/jump-game-vi/) — Medium — `[MQ]` window max
- [ ] [LC 1937 · Maximum Number of Points with Cost](https://leetcode.com/problems/maximum-number-of-points-with-cost/) — Medium — `[MQ]` two sweeps for $|c - c'|$
- [ ] [LC 1155 · Number of Dice Rolls With Target Sum](https://leetcode.com/problems/number-of-dice-rolls-with-target-sum/) — Medium — `[PS]`
- [ ] [LC 837 · New 21 Game](https://leetcode.com/problems/new-21-game/) — Medium — `[PS]` sliding probability sum
- [ ] [LC 462 · Minimum Moves to Equal Array Elements II](https://leetcode.com/problems/minimum-moves-to-equal-array-elements-ii/) — Medium — `[ST]` the median fact behind slope trick
- [ ] [LC 1425 · Constrained Subsequence Sum](https://leetcode.com/problems/constrained-subsequence-sum/) — Hard — `[MQ]`
- [ ] [LC 239 · Sliding Window Maximum](https://leetcode.com/problems/sliding-window-maximum/) — Hard — `[MQ]` the primitive
- [ ] [LC 629 · K Inverse Pairs Array](https://leetcode.com/problems/k-inverse-pairs-array/) — Hard — `[PS]`
- [ ] [LC 2902 · Count of Sub-Multisets With Bounded Sum](https://leetcode.com/problems/count-of-sub-multisets-with-bounded-sum/) — Hard — `[PS]` bounded knapsack counting
- [ ] [LC 1547 · Minimum Cost to Cut a Stick](https://leetcode.com/problems/minimum-cost-to-cut-a-stick/) — Hard — `[KN]`
- [ ] [LC 1478 · Allocate Mailboxes](https://leetcode.com/problems/allocate-mailboxes/) — Hard — `[DC]` / `[KN]` $k$-median
- [ ] [LC 188 · Best Time to Buy and Sell Stock IV](https://leetcode.com/problems/best-time-to-buy-and-sell-stock-iv/) — Hard — `[AL]` at large $k$
- [ ] [LC 1220 · Count Vowels Permutation](https://leetcode.com/problems/count-vowels-permutation/) — Hard — `[MX]` 5×5 transition matrix
- [ ] [LC 552 · Student Attendance Record II](https://leetcode.com/problems/student-attendance-record-ii/) — Hard — `[MX]` small automaton
- [ ] [LC 1335 · Minimum Difficulty of a Job Schedule](https://leetcode.com/problems/minimum-difficulty-of-a-job-schedule/) — Hard — trap: `[DC]` is **not** valid here (see 03 §6)
