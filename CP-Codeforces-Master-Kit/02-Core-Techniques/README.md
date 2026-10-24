# 02 — Core Techniques

This folder covers six techniques that take a brute force over subarrays, pairs, subsets or candidate answers from
$O(n^2)$, $O(n^3)$ or $O(2^n)$ down to $O(n)$, $O(n \log n)$ or $O(2^{n/2})$. They are prefix sums and difference arrays,
binary search (on indices and on the answer), two pointers and sliding windows, monotonic stacks and deques, coordinate
compression with sweep lines, and ternary search with meet in the middle. None of them is a data structure. They are
the small steps that sit **inside** almost every solution above 1400: the precomputation that makes a DP transition
$O(1)$, the outer loop around a greedy check, the sweep that feeds a Fenwick tree. Interviewers also ask about them more
than any other algorithm family.

## First-principles overview

Every technique here answers one question: **what work does the brute force repeat, and what structure lets you skip it?**
The answers fall into four kinds.

**1. Precomputed aggregates: prefix sums and difference arrays.** If the combining operation can be undone (sum by
subtraction, XOR by XOR, counts by subtraction), then any range aggregate is the difference of two prefix aggregates:
$\sum_{i=l}^{r} a_i = P_{r+1} - P_l$. Each range question becomes two point lookups. Run the same idea backwards and a
range update becomes two point updates on the difference array, and one prefix pass at the end applies all of them at
once. Counting subarrays whose sum has some property turns into counting **pairs of prefix values** with a matching
property, which a hashmap handles in one pass. Operations that can't be undone (min, max, gcd) work for prefixes only.
Arbitrary ranges of those need a [sparse table](../08-Data-Structures/05-sparse-table-and-rmq.md), and range queries
mixed with updates need a [Fenwick tree](../08-Data-Structures/01-fenwick-tree.md) or a
[segment tree](../08-Data-Structures/02-segment-tree-basics.md).

**2. Monotonicity: binary search, two pointers, monotonic stack and deque.** These four share one fact: **once a
candidate is dominated, it is never needed again**, so the algorithm can drop it for good.
- *Binary search.* The predicate is false … false, true … true over an ordered domain, so one probe rules out half of what
  remains. *On the answer:* "can we achieve $X$?" is monotone in $X$, and checking a single $X$ is usually far easier
  than optimising directly. The invariant `ok(lo) = false, ok(hi) = true` is the whole algorithm.
- *Two pointers.* For each right end $r$ let $L(r)$ be the smallest left end that still gives a good window. If every
  sub-window of a good window is good, $L(r)$ never decreases, so both pointers only move forward: $O(n)$ in total.
- *Monotonic stack.* When looking for the next smaller element, an element that has a smaller one after it can never
  be the answer for any position further right. Pop it and never look at it again. Each element is pushed once and
  popped once, so the cost is amortised $O(1)$.
- *Monotonic deque.* The same domination inside a sliding window: an older element that is also worse leaves the window
  before the newer, better one does, so it can never be the window's optimum.

**3. Order: coordinate compression and sweep lines.** Many questions depend only on the *relative order* of coordinates.
Compressing values to ranks $0..k-1$ lets arrays and Fenwick trees index them. A sweep turns a static 2D question
(intervals, rectangles, points with queries) into a 1D stream of events handled in sorted order while a structure
holds the currently active objects. Offline queries can be sorted into the same stream. Getting the order of events
at equal coordinates right is half of the technique.

**4. Shape of the search space: ternary search and meet in the middle.** For a strictly unimodal function, comparing two
interior points rules out a third of the range. For a search over $2^n$ subsets, splitting the items into two halves,
listing the $2^{n/2}$ sums of each half and combining them with sorting plus two pointers (or a hashmap) takes the square
root of the brute force. The same splitting idea underlies bidirectional BFS.

Three habits apply to the whole folder:
1. **Write the invariant before the loop.** Examples: `lo` is always false and `hi` always true; window $[l, r]$ is good;
   the stack is strictly increasing.
2. **Prove monotonicity before relying on it.** Negative numbers break "sum ≤ S" windows, and plateaus break ternary
   search.
3. **Brute-force small cases.** Off-by-one errors are the main way these techniques fail, and an $O(n^2)$ checker on
   random arrays of length 8 catches nearly all of them.

## Files

| File | Band | Priority | FAANG | One-line summary |
|---|---|---|---|---|
| [01 · Prefix sums and difference arrays](01-prefix-sums-and-difference-arrays.md) | 🟢–🔵 800–1900 | 🔥 | high | 1D/2D prefix and inclusion–exclusion, prefix XOR/min/max, count subarrays by hashmap and residues, 1D/2D and second-order differences |
| [02 · Binary search and binary search on the answer](02-binary-search-and-binary-search-on-answer.md) | 🟢–🟣 1000–2100 | 🔥 | high | invariant formulation, `lower_bound`/`partition_point` vs Java's `binarySearch`/`TreeMap`, monotone predicates, reals, k-th by counting, Dinkelbach |
| [03 · Two pointers and sliding window](03-two-pointers-and-sliding-window.md) | 🟢–🔵 1000–1800 | 🔥 | high | when monotonicity makes it valid, 2-sum/3-sum, merging, fixed and variable windows, exactly-K = atMost(K) − atMost(K−1), Floyd |
| [04 · Monotonic stack and deque](04-monotonic-stack-and-deque.md) | 🔵–🟣 1400–2100 | 🔥 | high | next/previous greater/smaller, histogram, maximal rectangle, contribution with tie-breaking, window max, shortest subarray ≥ K, Cartesian tree |
| [05 · Coordinate compression and sweep line](05-coordinate-compression-and-sweep-line.md) | 🔵–🟣 1400–2100 | 🔥 | medium | sort + unique + rank, event sweeps (union length, max overlap, rooms, skyline), offline query sorting, sweep + set, rectangle union |
| [06 · Ternary search and meet in the middle](06-ternary-search-and-meet-in-the-middle.md) | 🔵–🟠 1600–2300 | ⚡ | low | strict unimodality, integer and real versions, golden section, plateaus; subset sums over halves, counting sums ≤ S, 4-sum, bidirectional BFS |
| [problems.md](problems.md) | all | — | — | 100 problems by rating band + 39 LeetCode problems by topic |
| [Cheat sheet](../99-Cheat-Sheets/02-core-techniques-cheatsheet.md) | — | — | — | formulas, library semantics, tie rules, templates, mistakes |

## Prerequisites

- [Complexity and constraint reading](../01-Foundations/01-complexity-and-constraint-reading.md) — turning $n \le 2 \cdot 10^5$ into
  "needs $O(n \log n)$", and $n \le 40$ into "meet in the middle".
- [C++ STL and Java collections](../01-Foundations/02-cpp-stl-and-java-collections.md) — `lower_bound`, `deque`, `multiset`,
  `TreeMap`, `ArrayDeque`.
- [Sorting and comparators](../01-Foundations/05-sorting-and-comparators.md) — almost every two-pointer and sweep solution
  starts with a sort.
- [Integer overflow, precision and fast I/O](../01-Foundations/06-integer-overflow-precision-and-fast-io.md) — prefix sums
  overflow `int`, and binary search on reals needs a precision plan.
- [Bit manipulation](../01-Foundations/03-bit-manipulation.md) — prefix XOR and subset enumeration for meet in the middle.

## Recommended study order

1. **01 Prefix sums** §1–§3 and the first examples. Work the ≤ 1400 band of [problems.md](problems.md) alongside it.
2. **02 Binary search.** Learn the `lo`-false / `hi`-true template first and use only that one. Then binary search on the
   answer (the highest-yield skill in the folder for Div2 C/D), then reals and k-th by counting. Leave fractional
   programming until you are around 1800.
3. **03 Two pointers.** The validity proof, variable windows, and the exactly-K trick.
4. **04 Monotonic stack and deque.** Next smaller, histogram, the contribution technique with tie-breaking, the window
   maximum. Then follow the link to [deque DP optimisation](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md).
5. **05 Compression and sweep.** Events and tie order, then offline queries, then sweep + set. Continue with the
   [Fenwick tree](../08-Data-Structures/01-fenwick-tree.md) to unlock the 1800+ sweep problems.
6. **06 Ternary search and meet in the middle.** Short and less frequent, but it shows up exactly when $n \le 40$ or the
   objective is convex.
7. Second pass: the 1700–2100 bands of [problems.md](problems.md), mixed across topics so that you practise *choosing*
   the technique, not only applying it.
8. Before contests: the [cheat sheet](../99-Cheat-Sheets/02-core-techniques-cheatsheet.md).

## How this shows up in rounds

- **Div2 A–B (800–1300):** prefix sums, sorting + two pointers, `upper_bound` counting. These are expected to take
  minutes, and losing time on an off-by-one here costs more rating than missing a hard problem.
- **Div2 C (1300–1700):** binary search on the answer appears in a large share of rounds. So do prefix sums with a
  hashmap ("count subarrays such that …"), sliding windows with frequency counts, and difference arrays for batches of
  range additions.
- **Div2 D / Div1 B (1700–2100):** the contribution technique with monotonic stacks, binary search on the answer with a
  non-obvious check (the median ±1 transform, a greedy feasibility check), sweep + Fenwick, two pointers + sparse table,
  deque-optimised DP, and meet in the middle when $n \le 40$.
- **Div1 C and above (2100+):** these techniques rarely *are* the solution. They are sub-steps in parallel binary search,
  sweeps feeding a segment tree with lazy propagation, CDQ divide and conquer, Cartesian-tree DP, or hashing over
  meet-in-the-middle halves. You need them to be automatic so that all your thinking goes to the new idea.
- **FAANG interviews:** sliding window, binary search (including on the answer), monotonic stack and interval sweeps are
  among the most common interview categories. The [FAANG folder](../17-FAANG-Interview-DSA/README.md) covers the
  interview framing.

## Technique selection — signal → technique

| Signal in the statement or constraints | Think | File |
|---|---|---|
| many range-sum / range-XOR queries on a static array | prefix sums | [01](01-prefix-sums-and-difference-arrays.md) |
| many "add $v$ on $[l, r]$" operations, values read only at the end | difference array | [01](01-prefix-sums-and-difference-arrays.md) |
| "add $1, 2, 3, \dots$ on a range", arithmetic progressions | second-order differences | [01](01-prefix-sums-and-difference-arrays.md) |
| "count subarrays with sum $= k$ / divisible by $k$ / equal 0s and 1s" | prefix values + hashmap or residue counts | [01](01-prefix-sums-and-difference-arrays.md) |
| "minimise the maximum", "maximise the minimum", "smallest $X$ such that" | binary search on the answer | [02](02-binary-search-and-binary-search-on-answer.md) |
| "k-th smallest" among $\Theta(n^2)$ implicit values (pairs, products) | binary search on the value + counting | [02](02-binary-search-and-binary-search-on-answer.md) |
| maximise $\sum a / \sum b$ over a choice | fractional binary search / Dinkelbach | [02](02-binary-search-and-binary-search-on-answer.md) |
| answer is a real number, monotone feasibility | binary search on reals, fixed iterations | [02](02-binary-search-and-binary-search-on-answer.md) |
| longest/shortest subarray with a property that survives shrinking | two pointers | [03](03-two-pointers-and-sliding-window.md) |
| "exactly $K$ distinct / exactly $K$ odd numbers" | atMost(K) − atMost(K−1) | [03](03-two-pointers-and-sliding-window.md) |
| sorted array, pairs/triples with a target sum | two pointers from both ends | [03](03-two-pointers-and-sliding-window.md) |
| functional graph / linked list, find the cycle with $O(1)$ memory | Floyd's tortoise and hare | [03](03-two-pointers-and-sliding-window.md) |
| nearest greater/smaller, "how far can element $i$ extend" | monotonic stack | [04](04-monotonic-stack-and-deque.md) |
| sum over all subarrays of min / max / (max − min) | monotonic stack + contribution | [04](04-monotonic-stack-and-deque.md) |
| window max/min, or $dp_i = \min_{j \in [i-k, i-1]} (\dots)$ | monotonic deque | [04](04-monotonic-stack-and-deque.md) |
| values or coordinates up to $10^9$, but only $n \le 2 \cdot 10^5$ of them | coordinate compression | [05](05-coordinate-compression-and-sweep-line.md) |
| intervals: overlap, union, "at some moment", rooms | sweep over sorted events | [05](05-coordinate-compression-and-sweep-line.md) |
| all queries known in advance and answerable in sorted order | offline sweep | [05](05-coordinate-compression-and-sweep-line.md) |
| one real/integer parameter, cost convex or unimodal in it | ternary search (or binary search on the slope) | [06](06-ternary-search-and-meet-in-the-middle.md) |
| $n \le 40$ items, subsets, sums or XORs | meet in the middle | [06](06-ternary-search-and-meet-in-the-middle.md) |

Common confusions: a "minimise the maximum" problem can also be a greedy or DP problem, so check whether a direct greedy
exists before you binary search. A window problem with negative numbers is **not** two pointers; it needs prefix sums
with a deque or an ordered structure. A function that is merely "unimodal-looking" with flat stretches is **not**
safe for ternary search.

## Related folders

- [07 DP optimizations — prefix sums and monotonic queue](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md)
  and [Aliens trick](../07-DP-Optimizations/06-aliens-trick-wqs-binary-search.md) (binary search on a penalty).
- [08 Data structures](../08-Data-Structures/README.md): Fenwick and segment trees take over when prefix sums meet updates.
  [Sparse tables](../08-Data-Structures/05-sparse-table-and-rmq.md) cover static range min/max and gcd.
  [Ordered sets](../08-Data-Structures/10-ordered-sets-pbds-and-heaps.md) are what "sweep + set" maintains.
- [09 Graphs — functional graphs](../09-Graphs/10-functional-graphs-and-special-graphs.md) (Floyd's cycle detection at scale)
  and [BFS](../09-Graphs/01-graph-representation-bfs-dfs.md) (bidirectional BFS).
- [14 Geometry — sweep, closest pair, half-plane](../14-Geometry/05-sweep-closest-pair-and-half-plane.md).
- [16 IGM frontier — offline techniques, CDQ, parallel binary search](../16-IGM-Frontier/01-offline-techniques-cdq-parallel-binary-search.md).
- [03 Greedy, constructive, interactive](../03-Greedy-Constructive-Interactive/README.md): binary search drives most
  interactive strategies, and sweeps underpin interval greedy.
