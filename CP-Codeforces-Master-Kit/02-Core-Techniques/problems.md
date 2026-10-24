# 02 — Core Techniques: problem ladder

Consolidated ladder for [01 prefix sums](01-prefix-sums-and-difference-arrays.md),
[02 binary search](02-binary-search-and-binary-search-on-answer.md), [03 two pointers](03-two-pointers-and-sliding-window.md),
[04 monotonic stack and deque](04-monotonic-stack-and-deque.md), [05 compression and sweep](05-coordinate-compression-and-sweep-line.md)
and [06 ternary search and meet in the middle](06-ternary-search-and-meet-in-the-middle.md).
Ratings are Codeforces ratings. CSES problems carry my estimate. AtCoder problems carry the AtCoder Problems difficulty
estimate, which runs somewhat below a Codeforces rating at the same level, so treat them as a little harder than their band.
Hints name the technique family only.

How to use it: clear a band until most problems fall without hints, then move up. For every binary-search or
two-pointer problem, write down the invariant (`lo` false / `hi` true, "window $[l, r]$ is good") **before** coding;
for every counting problem, check the answer against an $O(n^2)$ brute force on small random arrays.

Tags: **P** prefix sums / difference arrays · **B** binary search (on index, on answer, k-th by counting, fractional) ·
**W** two pointers / sliding window · **M** monotonic stack / deque · **S** coordinate compression / sweep line ·
**X** ternary search / meet in the middle.

## ≤ 1400

- [ ] [CF 1709B · Also Try Minecraft](https://codeforces.com/problemset/problem/1709/B) — 900 — P, one prefix array per direction
- [ ] [CF 1873E · Building an Aquarium](https://codeforces.com/problemset/problem/1873/E) — 1100 — B on the answer
- [ ] [CF 706B · Interesting drink](https://codeforces.com/problemset/problem/706/B) — 1100 — B, count values ≤ x
- [ ] [CF 433B · Kuriyama Mirai's Stones](https://codeforces.com/problemset/problem/433/B) — 1200 — P, two prefix arrays
- [ ] [CF 474B · Worms](https://codeforces.com/problemset/problem/474/B) — 1200 — P + B
- [ ] [CF 1354B · Ternary String](https://codeforces.com/problemset/problem/1354/B) — 1200 — W, shortest window
- [ ] [CF 1201C · Maximum Median](https://codeforces.com/problemset/problem/1201/C) — 1400 — B on the answer
- [ ] [CF 279B · Books](https://codeforces.com/problemset/problem/279/B) — 1400 — W, variable window
- [ ] [CF 1324D · Pair of Topics](https://codeforces.com/problemset/problem/1324/D) — 1400 — B or W after a transform
- [ ] [CF 816B · Karen and Coffee](https://codeforces.com/problemset/problem/816/B) — 1400 — P, difference array then prefix counts
- [ ] [CF 295A · Greg and Array](https://codeforces.com/problemset/problem/295/A) — 1400 — P, difference arrays on two levels
- [ ] [CSES 1646 · Static Range Sum Queries](https://cses.fi/problemset/task/1646) — ≈1000 (est.) — P
- [ ] [CSES 1652 · Forest Queries](https://cses.fi/problemset/task/1652) — ≈1200 (est.) — P, 2D
- [ ] [CSES 1640 · Sum of Two Values](https://cses.fi/problemset/task/1640) — ≈1100 (est.) — W from both ends
- [ ] [CSES 1660 · Subarray Sums I](https://cses.fi/problemset/task/1660) — ≈1200 (est.) — W, positive values
- [ ] [CSES 1645 · Nearest Smaller Values](https://cses.fi/problemset/task/1645) — ≈1300 (est.) — M
- [ ] [CSES 3221 · Sliding Window Minimum](https://cses.fi/problemset/task/3221) — ≈1300 (est.) — M, deque
- [ ] [AtCoder ABC183 D · Water Heater](https://atcoder.jp/contests/abc183/tasks/abc183_d) — ≈650 (est.) — P, difference array over time

## 1400–1700

- [ ] [CF 1426D · Non-zero Segments](https://codeforces.com/problemset/problem/1426/D) — 1500 — P, repeated prefix values
- [ ] [CF 276C · Little Girl and Maximum Sum](https://codeforces.com/problemset/problem/276/C) — 1500 — P, how often each index is used
- [ ] [CF 676C · Vasya and String](https://codeforces.com/problemset/problem/676/C) — 1500 — W, budget of changes
- [ ] [CF 701C · They Are Everywhere](https://codeforces.com/problemset/problem/701/C) — 1500 — W, cover every type
- [ ] [CF 1301B · Motarack's Birthday](https://codeforces.com/problemset/problem/1301/B) — 1500 — X, convex in one variable (or a direct formula)
- [ ] [CF 1398C · Good Subarrays](https://codeforces.com/problemset/problem/1398/C) — 1600 — P + hashmap after shifting values
- [ ] [CF 1722E · Counting Rectangles](https://codeforces.com/problemset/problem/1722/E) — 1600 — P, 2D over the value grid
- [ ] [CF 1029C · Maximal Intersection](https://codeforces.com/problemset/problem/1029/C) — 1600 — P, prefix and suffix max/min
- [ ] [CF 1610C · Keshi Is Throwing a Party](https://codeforces.com/problemset/problem/1610/C) — 1600 — B on the answer, greedy check
- [ ] [CF 1843E · Tracking Segments](https://codeforces.com/problemset/problem/1843/E) — 1600 — B on the answer + P
- [ ] [CF 780B · The Meeting Place Cannot Be Changed](https://codeforces.com/problemset/problem/780/B) — 1600 — B on reals
- [ ] [CF 616D · Longest k-Good Segment](https://codeforces.com/problemset/problem/616/D) — 1600 — W, distinct counts
- [ ] [CSES 1661 · Subarray Sums II](https://cses.fi/problemset/task/1661) — ≈1400 (est.) — P + hashmap
- [ ] [CSES 1662 · Subarray Divisibility](https://cses.fi/problemset/task/1662) — ≈1500 (est.) — P, residues
- [ ] [CSES 1085 · Array Division](https://cses.fi/problemset/task/1085) — ≈1500 (est.) — B on the answer
- [ ] [CSES 2428 · Distinct Values Subarrays II](https://cses.fi/problemset/task/2428) — ≈1600 (est.) — W, at most k distinct
- [ ] [CSES 1142 · Advertisement](https://cses.fi/problemset/task/1142) — ≈1600 (est.) — M, histogram
- [ ] [AtCoder ABC105 D · Candy Distribution](https://atcoder.jp/contests/abc105/tasks/abc105_d) — ≈1450 (est.) — P, residues
- [ ] [AtCoder ABC184 F · Programming Contest](https://atcoder.jp/contests/abc184/tasks/abc184_f) — ≈1400 (est.) — X, meet in the middle
- [ ] [AtCoder ABC034 D · 食塩水 (salt water)](https://atcoder.jp/contests/abc034/tasks/abc034_d) — ≈1550 (est.) — B, maximise a ratio
- [ ] [AtCoder ABC271 F · XOR on Grid Path](https://atcoder.jp/contests/abc271/tasks/abc271_f) — ≈1650 (est.) — X, meet on a diagonal

## 1700–1900

- [ ] [CF 466C · Number of Ways](https://codeforces.com/problemset/problem/466/C) — 1700 — P, count split points
- [ ] [CF 1343D · Constant Palindrome Sum](https://codeforces.com/problemset/problem/1343/D) — 1700 — P, difference array over the target
- [ ] [CF 1333C · Eugene and an array](https://codeforces.com/problemset/problem/1333/C) — 1700 — P + W
- [ ] [CF 1661C · Water the Trees](https://codeforces.com/problemset/problem/1661/C) — 1700 — B on the answer, count both kinds of days
- [ ] [CF 439D · Devu and his Brother](https://codeforces.com/problemset/problem/439/D) — 1700 — X, convex in the threshold
- [ ] [CF 1000C · Covered Points Count](https://codeforces.com/problemset/problem/1000/C) — 1700 — S, events
- [ ] [CF 448D · Multiplication Table](https://codeforces.com/problemset/problem/448/D) — 1800 — B, k-th by counting
- [ ] [CF 1475D · Cleaning the Phone](https://codeforces.com/problemset/problem/1475/D) — 1800 — W on two sorted arrays
- [ ] [CF 1548B · Integers Have Friends](https://codeforces.com/problemset/problem/1548/B) — 1800 — W + range gcd
- [ ] [CF 1691D · Max GEQ Sum](https://codeforces.com/problemset/problem/1691/D) — 1800 — M + range queries on prefix sums
- [ ] [CF 1355C · Count Triangles](https://codeforces.com/problemset/problem/1355/C) — 1800 — P, count by sums
- [ ] [CF 1968F · Equal XOR Segments](https://codeforces.com/problemset/problem/1968/F) — 1800 — P (XOR) + B on positions
- [ ] [CF 652D · Nested Segments](https://codeforces.com/problemset/problem/652/D) — 1800 — S + Fenwick
- [ ] [CF 1420D · Rescue Nibel!](https://codeforces.com/problemset/problem/1420/D) — 1800 — S + counting
- [ ] [CF 1249D2 · Too Many Segments (hard version)](https://codeforces.com/problemset/problem/1249/D2) — 1800 — S + ordered set
- [ ] [CF 69E · Subsegments](https://codeforces.com/problemset/problem/69/E) — 1800 — W + ordered set
- [ ] [CF 888E · Maximum Subsequence](https://codeforces.com/problemset/problem/888/E) — 1800 — X, meet in the middle
- [ ] [CSES 1628 · Meet in the Middle](https://cses.fi/problemset/task/1628) — ≈1800 (est.) — X
- [ ] [CSES 1147 · Maximum Building I](https://cses.fi/problemset/task/1147) — ≈1800 (est.) — M, one histogram per row
- [ ] [AtCoder ABC236 E · Average and Median](https://atcoder.jp/contests/abc236/tasks/abc236_e) — ≈1900 (est.) — B, two different predicates

## 1900–2100

- [ ] [CF 1661D · Progressions Covering](https://codeforces.com/problemset/problem/1661/D) — 1900 — P, arithmetic progressions on ranges
- [ ] [CF 1197D · Yet Another Subarray Problem](https://codeforces.com/problemset/problem/1197/D) — 1900 — P, best start per residue (or a small DP)
- [ ] [CF 1400D · Zigzags](https://codeforces.com/problemset/problem/1400/D) — 1900 — P, prefix counts
- [ ] [CF 1260D · A Game with Traps](https://codeforces.com/problemset/problem/1260/D) — 1900 — B on the answer + difference array
- [ ] [CF 1251D · Salary Changing](https://codeforces.com/problemset/problem/1251/D) — 1900 — B on the median
- [ ] [CF 1358D · The Best Vacation](https://codeforces.com/problemset/problem/1358/D) — 1900 — W on a doubled array + P
- [ ] [CF 6E · Exposition](https://codeforces.com/problemset/problem/6/E) — 1900 — W + window max/min
- [ ] [CF 547B · Mike and Feet](https://codeforces.com/problemset/problem/547/B) — 1900 — M, reach of each minimum
- [ ] [CF 1313C2 · Skyscrapers (hard version)](https://codeforces.com/problemset/problem/1313/C2) — 1900 — M, prefix costs
- [ ] [CF 817D · Imbalanced Array](https://codeforces.com/problemset/problem/817/D) — 1900 — M, contribution with tie-breaking
- [ ] [CF 1311F · Moving Points](https://codeforces.com/problemset/problem/1311/F) — 1900 — S, compression + Fenwick
- [ ] [CF 1370D · Odd-Even Subsequence](https://codeforces.com/problemset/problem/1370/D) — 2000 — B on the answer
- [ ] [CF 578C · Weakness and Poorness](https://codeforces.com/problemset/problem/578/C) — 2000 — X, ternary search on reals
- [ ] [CF 1359D · Yet Another Yet Another Task](https://codeforces.com/problemset/problem/1359/D) — 2000 — P, fix one more parameter
- [ ] [CF 940E · Cashback](https://codeforces.com/problemset/problem/940/E) — 2000 — M, window minimum inside a DP
- [ ] [CSES 2169 · Nested Ranges Count](https://cses.fi/problemset/task/2169) — ≈1900 (est.) — S + Fenwick

## 2100–2400

- [ ] [CF 1486D · Max Median](https://codeforces.com/problemset/problem/1486/D) — 2100 — B on the answer + P
- [ ] [CF 1299C · Water Balance](https://codeforces.com/problemset/problem/1299/C) — 2100 — M, merge blocks on a stack
- [ ] [CF 1913D · Array Collapse](https://codeforces.com/problemset/problem/1913/D) — 2100 — M + DP
- [ ] [CF 1355E · Restorer Distance](https://codeforces.com/problemset/problem/1355/E) — 2100 — X, convex in the target
- [ ] [CF 525E · Anya and Cubes](https://codeforces.com/problemset/problem/525/E) — 2100 — X, meet in the middle
- [ ] [CF 1006F · Xor-Paths](https://codeforces.com/problemset/problem/1006/F) — 2100 — X, meet in the middle on a grid
- [ ] [CF 1077F2 · Pictures with Kittens (hard version)](https://codeforces.com/problemset/problem/1077/F2) — 2100 — M, deque DP
- [ ] [CF 372C · Watching Fireworks is Fun](https://codeforces.com/problemset/problem/372/C) — 2100 — M, deque DP
- [ ] [CF 484B · Maximum Value](https://codeforces.com/problemset/problem/484/B) — 2100 — B over multiples
- [ ] [CF 985E · Pencils and Boxes](https://codeforces.com/problemset/problem/985/E) — 2100 — W + prefix sums over a DP
- [ ] [CF 551C · GukiZ hates Boxes](https://codeforces.com/problemset/problem/551/C) — 2200 — B on the answer, greedy check
- [ ] [CF 1407D · Discrete Centrifugal Jumps](https://codeforces.com/problemset/problem/1407/D) — 2200 — M + DP
- [ ] [CF 610D · Vika and Segments](https://codeforces.com/problemset/problem/610/D) — 2300 — S + Fenwick, merge then count overlaps
- [ ] [CF 1849E · Max to the Right of Min](https://codeforces.com/problemset/problem/1849/E) — 2300 — M, iterate the shorter side
- [ ] [CF 1748E · Yet Another Array Counting Problem](https://codeforces.com/problemset/problem/1748/E) — 2300 — M, Cartesian tree
- [ ] [CSES 1741 · Area of Rectangles](https://cses.fi/problemset/task/1741) — ≈2200 (est.) — S + segment tree
- [ ] [AtCoder ABC229 G · Longest Y](https://atcoder.jp/contests/abc229/tasks/abc229_g) — ≈2100 (est.) — B + W

## 2400+

- [ ] [CF 5E · Bindian Signalizing](https://codeforces.com/problemset/problem/5/E) — 2400 — M on a circle
- [ ] [CF 912E · Prime Gift](https://codeforces.com/problemset/problem/912/E) — 2400 — X + B on the answer
- [ ] [CF 1257F · Make Them Similar](https://codeforces.com/problemset/problem/1257/F) — 2400 — X + hashing
- [ ] [CF 1736C2 · Good Subarrays (Hard Version)](https://codeforces.com/problemset/problem/1736/C2) — 2400 — W + P, then point changes
- [ ] [CF 1436E · Complicated Computations](https://codeforces.com/problemset/problem/1436/E) — 2400 — S, offline sweep over right ends
- [ ] [CF 484E · Sign on Fence](https://codeforces.com/problemset/problem/484/E) — 2500 — B on the answer + persistence (or parallel BS)
- [ ] [CF 660F · Bear and Bowling 4](https://codeforces.com/problemset/problem/660/F) — 2500 — P + convex hull
- [ ] [CF 1730E · Maximums and Minimums](https://codeforces.com/problemset/problem/1730/E) — 2700 — M + divisors

For the 2100+ problems the core technique is usually one step inside a larger solution; the other step lives in
[07 DP optimizations](../07-DP-Optimizations/README.md), [08 data structures](../08-Data-Structures/README.md) or
[16 IGM frontier](../16-IGM-Frontier/README.md).

## LeetCode

**Prefix sums and difference arrays**
- [ ] [LC 303 · Range Sum Query - Immutable](https://leetcode.com/problems/range-sum-query-immutable/) — Easy — 1D prefix
- [ ] [LC 304 · Range Sum Query 2D - Immutable](https://leetcode.com/problems/range-sum-query-2d-immutable/) — Medium — inclusion–exclusion
- [ ] [LC 560 · Subarray Sum Equals K](https://leetcode.com/problems/subarray-sum-equals-k/) — Medium — prefix + hashmap
- [ ] [LC 974 · Subarray Sums Divisible by K](https://leetcode.com/problems/subarray-sums-divisible-by-k/) — Medium — residues, negative mod
- [ ] [LC 525 · Contiguous Array](https://leetcode.com/problems/contiguous-array/) — Medium — ±1 transform, first occurrence
- [ ] [LC 1109 · Corporate Flight Bookings](https://leetcode.com/problems/corporate-flight-bookings/) — Medium — difference array
- [ ] [LC 1074 · Number of Submatrices That Sum to Target](https://leetcode.com/problems/number-of-submatrices-that-sum-to-target/) — Hard — fix two rows, 1D hashmap

**Binary search**
- [ ] [LC 34 · Find First and Last Position of Element in Sorted Array](https://leetcode.com/problems/find-first-and-last-position-of-element-in-sorted-array/) — Medium — lower and upper bound
- [ ] [LC 33 · Search in Rotated Sorted Array](https://leetcode.com/problems/search-in-rotated-sorted-array/) — Medium — find the sorted half
- [ ] [LC 875 · Koko Eating Bananas](https://leetcode.com/problems/koko-eating-bananas/) — Medium — on the answer
- [ ] [LC 410 · Split Array Largest Sum](https://leetcode.com/problems/split-array-largest-sum/) — Hard — minimise the maximum
- [ ] [LC 4 · Median of Two Sorted Arrays](https://leetcode.com/problems/median-of-two-sorted-arrays/) — Hard — partition point
- [ ] [LC 378 · Kth Smallest Element in a Sorted Matrix](https://leetcode.com/problems/kth-smallest-element-in-a-sorted-matrix/) — Medium — value + staircase count
- [ ] [LC 668 · Kth Smallest Number in Multiplication Table](https://leetcode.com/problems/kth-smallest-number-in-multiplication-table/) — Hard — k-th by counting
- [ ] [LC 719 · Find K-th Smallest Pair Distance](https://leetcode.com/problems/find-k-th-smallest-pair-distance/) — Hard — count with two pointers

**Two pointers and sliding window**
- [ ] [LC 167 · Two Sum II - Input Array Is Sorted](https://leetcode.com/problems/two-sum-ii-input-array-is-sorted/) — Medium — both ends
- [ ] [LC 15 · 3Sum](https://leetcode.com/problems/3sum/) — Medium — fix one, two pointers, skip duplicates
- [ ] [LC 11 · Container With Most Water](https://leetcode.com/problems/container-with-most-water/) — Medium — both ends; prove which pointer may move
- [ ] [LC 3 · Longest Substring Without Repeating Characters](https://leetcode.com/problems/longest-substring-without-repeating-characters/) — Medium — variable window
- [ ] [LC 76 · Minimum Window Substring](https://leetcode.com/problems/minimum-window-substring/) — Hard — shortest covering window
- [ ] [LC 992 · Subarrays with K Different Integers](https://leetcode.com/problems/subarrays-with-k-different-integers/) — Hard — atMost(K) − atMost(K−1)
- [ ] [LC 142 · Linked List Cycle II](https://leetcode.com/problems/linked-list-cycle-ii/) — Medium — Floyd, cycle entry

**Monotonic stack and deque**
- [ ] [LC 739 · Daily Temperatures](https://leetcode.com/problems/daily-temperatures/) — Medium — next greater
- [ ] [LC 503 · Next Greater Element II](https://leetcode.com/problems/next-greater-element-ii/) — Medium — circular, two passes
- [ ] [LC 84 · Largest Rectangle in Histogram](https://leetcode.com/problems/largest-rectangle-in-histogram/) — Hard — span of each bar
- [ ] [LC 85 · Maximal Rectangle](https://leetcode.com/problems/maximal-rectangle/) — Hard — one histogram per row
- [ ] [LC 907 · Sum of Subarray Minimums](https://leetcode.com/problems/sum-of-subarray-minimums/) — Medium — contribution, strict on one side
- [ ] [LC 901 · Online Stock Span](https://leetcode.com/problems/online-stock-span/) — Medium — online previous greater
- [ ] [LC 239 · Sliding Window Maximum](https://leetcode.com/problems/sliding-window-maximum/) — Hard — monotonic deque
- [ ] [LC 862 · Shortest Subarray with Sum at Least K](https://leetcode.com/problems/shortest-subarray-with-sum-at-least-k/) — Hard — deque of prefix sums

**Compression and sweep line**
- [ ] [LC 56 · Merge Intervals](https://leetcode.com/problems/merge-intervals/) — Medium — sort by start
- [ ] [LC 253 · Meeting Rooms II](https://leetcode.com/problems/meeting-rooms-ii/) — Medium 🔒 — max overlap, tie order
- [ ] [LC 218 · The Skyline Problem](https://leetcode.com/problems/the-skyline-problem/) — Hard — events + multiset of heights
- [ ] [LC 850 · Rectangle Area II](https://leetcode.com/problems/rectangle-area-ii/) — Hard — compression + sweep
- [ ] [LC 2251 · Number of Flowers in Full Bloom](https://leetcode.com/problems/number-of-flowers-in-full-bloom/) — Hard — offline queries or two sorted arrays

**Ternary search and meet in the middle**
- [ ] [LC 852 · Peak Index in a Mountain Array](https://leetcode.com/problems/peak-index-in-a-mountain-array/) — Medium — search on the slope
- [ ] [LC 454 · 4Sum II](https://leetcode.com/problems/4sum-ii/) — Medium — pair sums
- [ ] [LC 1755 · Closest Subsequence Sum](https://leetcode.com/problems/closest-subsequence-sum/) — Hard — halves + two pointers
- [ ] [LC 2035 · Partition Array Into Two Arrays to Minimize Sum Difference](https://leetcode.com/problems/partition-array-into-two-arrays-to-minimize-sum-difference/) — Hard — halves grouped by size
