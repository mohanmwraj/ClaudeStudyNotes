# Two pointers and sliding window

> **Band:** 🟢–🔵 1000–1800 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [sorting and comparators](../01-Foundations/05-sorting-and-comparators.md), [prefix sums](01-prefix-sums-and-difference-arrays.md), [complexity and constraints](../01-Foundations/01-complexity-and-constraint-reading.md)
> **You can say you know this when:** you can name the monotonicity property that makes a window legal *before* coding it, write the "extend right, shrink left while bad" loop with no off-by-one, turn "exactly $K$" into two "at most" counts, and see within seconds when negative numbers or a non-monotone condition make two pointers wrong.

## 1. First principles — why this works

**The waste in the naive scan.** "Longest / shortest / number of subarrays such that …" ranges over all
$\binom{n+1}{2}$ intervals $[l, r]$. Even with $O(1)$ incremental updates (fix $l$, extend $r$), that is $\Theta(n^2)$,
too slow for $n = 2 \cdot 10^5$. The waste: for every new $l$ we rebuild windows we already know about.

**The property that removes it.** Call a predicate $\text{good}(l, r)$ on intervals *hereditary* (downward closed) if
every sub-interval of a good interval is good:

$$\text{good}(l, r) \;\Rightarrow\; \text{good}(l', r') \quad \text{for all } l \le l' \le r' \le r .$$

Examples: "sum $\le S$" when all $a_i \ge 0$; "at most $K$ distinct values"; "$\max - \min \le d$"; "all elements
distinct". Define $L(r) = \min\{\, l : \text{good}(l, r) \,\}$, allowing the empty window $l = r + 1$ (always good).

**Lemma (the pointer never moves back).** $L(r) \le L(r+1)$.
*Proof.* $[L(r+1), r+1]$ is good, so its sub-interval $[L(r+1), r]$ is good, hence $L(r) \le L(r+1)$ by minimality. $\square$

So when $r$ advances, the correct left end is at or to the right of the old one, and we find it by moving $l$ forward
until the window becomes good. Both pointers only move forward and each moves at most $n$ times, so the whole scan does
at most $2n$ window updates — **amortised $O(1)$ per step**, even though one iteration of the inner loop may move $l$ far.
(Potential argument: $\Phi = n - l$ starts at $n$, never increases, and pays for every inner step.)

The complementary shape is *upward closed*: if $[l, r]$ is good then every super-interval is (e.g. "sum $\ge S$" with
$a_i \ge 0$, "contains all $K$ colours"). Then for fixed $r$ the good left ends form a prefix $\{0, \dots, M(r)\}$, and by the
same argument $M(r)$ is non-decreasing. The same loop finds $M(r)$; the *shortest* good window ending at $r$ has length
$r - M(r) + 1$ and the *number* of good windows ending at $r$ is $M(r) + 1$.

**What the window needs.** A structure supporting `push_back` (r moves), `pop_front` (l moves) and "is it good?":

| Window statistic | Structure | Cost per move |
|---|---|---|
| sum, xor, count of a property | running total (invertible) | $O(1)$ |
| number of distinct values | frequency array after compression | $O(1)$ |
| max / min | monotonic deque ([04](04-monotonic-stack-and-deque.md)) | amortised $O(1)$ |
| gcd, OR, AND (not invertible) | queue built from two stacks (§3.3) | amortised $O(1)$ ops |
| median, $k$-th | two multisets / order-statistics tree ([08](../08-Data-Structures/10-ordered-sets-pbds-and-heaps.md)) | $O(\log n)$ |

**Opposite-direction pointers are a staircase search.** Sorted $a$, find $i < j$ with $a_i + a_j = X$. Picture the matrix
$M_{ij} = a_i + a_j$: rows and columns are non-decreasing. Stand at $(i, j) = (0, n-1)$, the top-right corner of the
upper triangle. If $M_{ij} < X$, every entry left of it in row $i$ is $\le M_{ij} < X$, so row $i$ holds no answer —
discard it ($i{+}{+}$). If $M_{ij} > X$, every entry below it in column $j$ is $\ge M_{ij}$ — discard the column
($j{-}{-}$). Each step deletes a row or a column, so at most $n$ steps, and no deleted cell could have been a solution: that
*is* the correctness proof. The same walk counts pairs with $a_i + a_j \le X$ (the cells left of the staircase).
3-sum fixes the smallest element and runs 2-sum on the rest: $O(n^2)$. That is believed optimal up to $n^{o(1)}$ factors
(the 3SUM conjecture), so do not hunt for an $O(n \log n)$ 3-sum.

**Two pointers on two arrays.** Merging two sorted arrays keeps the invariant "the output is the sorted union of the two
consumed prefixes, and every unconsumed element is $\ge$ the last output". For "closest pair across $A$ and $B$": if
$a_i < b_j$, then $a_i$'s best partner among $b_j, b_{j+1}, \dots$ is $b_j$ (later ones are farther), which we just
examined — so $a_i$ is finished and we advance $i$. Advancing the smaller head is the only move that can help.

**Fast and slow pointers.** Iterating $x_{t+1} = f(x_t)$ on a finite set eventually repeats, giving a "rho" shape: a tail of
length $\mu$ followed by a cycle of length $\lambda$. Floyd's algorithm finds both with $O(1)$ memory (proof in §2). It is
the same object as a functional graph, see [functional graphs](../09-Graphs/10-functional-graphs-and-special-graphs.md);
linked-list cycle detection and "find the duplicate in $1..n$" are special cases.

**Where two pointers is wrong.** The lemma needs heredity. These break it:

- "sum $= S$" or "sum $\ge S$" with negative numbers — a longer window can be *smaller*. Use prefix sums + hash map for
  counting ([01](01-prefix-sums-and-difference-arrays.md)) and prefix sums + monotonic deque for "shortest with sum
  $\ge K$" ([04](04-monotonic-stack-and-deque.md)).
- "exactly $K$ distinct" — a sub-window may have fewer. Not hereditary, but it is the *difference* of two hereditary counts:
  $\#\{= K\} = \#\{\le K\} - \#\{\le K-1\}$.
- "sum divisible by $k$" — no monotonicity at all; prefix residues + counting.

## 2. Formulas, definitions and identities

**(F1) Monotone left end.** For a hereditary predicate, $L(r) \le L(r+1)$ (proof in §1). For an upward-closed predicate,
$M(r) \le M(r+1)$ where $M(r) = \max\{l : \text{good}(l,r)\}$ ($-1$ if none).

**(F2) Work bound.** Total pointer moves $\le 2n$; with per-move cost $c$ the scan is $O(nc)$. With a hash map, $c$ is
expected $O(1)$; with a balanced tree, $O(\log n)$.

**(F3) Counting good windows.**
$$\#\{\text{good } [l,r]\} = \sum_{r=0}^{n-1} \bigl(r - L(r) + 1\bigr) \ \ \text{(hereditary)}, \qquad
\sum_{r=0}^{n-1} \bigl(M(r) + 1\bigr) \ \ \text{(upward closed)}.$$

**(F4) Exactly / at least.** If $f$ is integer-valued and monotone under inclusion (distinct count, number of odd
elements, sum of non-negative integers) and $A(K) = \#\{[l,r] : f \le K\}$, then
$$E(K) = \#\{f = K\} = A(K) - A(K-1), \qquad \#\{f \ge K\} = \tfrac{n(n+1)}{2} - A(K-1).$$
*Proof.* $\{f \le K\}$ is the disjoint union of $\{f \le K-1\}$ and $\{f = K\}$. Use $A(-1) = 0$.

**(F5) Pairs with sum in a range.** For $C(X) = \#\{i<j : a_i + a_j \le X\}$,
$$\#\{i<j : lo \le a_i + a_j \le hi\} = C(hi) - C(lo - 1).$$
Order does not matter for pair counts, so sort first; $C$ is one staircase walk, $O(n)$ after an $O(n \log n)$ sort.

**(F6) Sizes.** Subarrays: $n(n+1)/2$ (about $2 \cdot 10^{10}$ for $n = 2 \cdot 10^5$ — needs 64-bit). Unordered pairs:
$n(n-1)/2$. Fixed-length windows of length $k$: $n - k + 1$.

**(F7) Fixed window update.** $W_{i+1} = W_i + a_{i+k} - a_i$ for sums; for counts, add the entering element and remove the
leaving one. $O(n)$ total.

**(F8) $k$-sum.** Fix $k-2$ indices and run 2-sum: $O(n^{k-1})$. Meet in the middle does $k$-sum in
$O(n^{\lceil k/2 \rceil} \log n)$ — see [meet in the middle](06-ternary-search-and-meet-in-the-middle.md).

**(F9) Floyd's cycle detection.** Let $x_0, x_1 = f(x_0), \dots$ have tail length $\mu$ and cycle length $\lambda$
(so $x_i = x_j$ for $i < j$ iff $i \ge \mu$ and $\lambda \mid j - i$).

1. *Meeting.* Slow is at $x_t$, fast at $x_{2t}$. They coincide iff $t \ge \mu$ and $\lambda \mid t$. The first such $t \ge 1$ is
   $t^{\ast} = \lambda \cdot \max(1, \lceil \mu / \lambda \rceil) \le \mu + \lambda$.
2. *Finding $\mu$.* Put one pointer at $x_0$, keep the other at $x_{t^{\ast}}$, and step both once per round. After $i$ rounds they
   are at $x_i$ and $x_{t^{\ast}+i}$. For $i = \mu$ these are equal ($t^{\ast}$ is a multiple of $\lambda$ and both indices are
   $\ge \mu$). For $i < \mu$, $x_i$ lies on the tail and $x_{t^{\ast}+i}$ on the cycle, so they differ. The first meeting is at
   $i = \mu$, at the cycle entrance.
3. *Finding $\lambda$.* Walk from $x_\mu$ until you return: $\lambda$ steps.

Total: $3t^{\ast} + 2\mu + \lambda = O(\mu + \lambda)$ evaluations of $f$, $O(1)$ memory. Brent's variant (teleport the slow
pointer at powers of two) uses fewer evaluations and gives $\lambda$ directly.

**(F10) Two-stack queue.** Keep an "in" stack and an "out" stack, each storing prefix aggregates of an associative operation
$\oplus$ from its bottom. Push goes to "in"; pop takes from "out", first moving everything from "in" to "out" if "out" is empty;
the whole-queue aggregate is $\text{agg(in)} \oplus \text{agg(out)}$ (for a non-commutative $\oplus$, out's aggregate comes
first). Each element is moved once, so every operation is amortised $O(1)$ applications of $\oplus$. This makes any
associative statistic (gcd, OR, AND, min, matrix product) usable in a sliding window.

| Operation | Time | Memory |
|---|---|---|
| variable window (longest / shortest / count) | $O(n \cdot c)$ | $O(\text{window structure})$ |
| fixed window | $O(n)$ | $O(1)$ extra |
| 2-sum on sorted array | $O(n)$ (+ $O(n\log n)$ sort) | $O(1)$ |
| 3-sum, all value-distinct triples | $O(n^2)$ | $O(1)$ extra |
| merge two sorted arrays | $O(n + m)$ | $O(n+m)$ output |
| Floyd $(\mu, \lambda)$ | $O(\mu + \lambda)$ | $O(1)$ |

## 3. Implementation (C++ and Java)

### 3.1 Same-direction windows

The loop shape never changes: **add `a[r]`; while the window is bad, remove `a[l++]`; now `[l, r]` is the best window
ending at `r`.**

```cpp
// Longest window with sum <= S; requires a[i] >= 0. Returns 0 if no element fits.
int longestSumAtMost(const vector<ll>& a, ll S) {
    int best = 0; ll sum = 0;
    for (int l = 0, r = 0; r < (int)a.size(); r++) {
        sum += a[r];
        while (l <= r && sum > S) sum -= a[l++];   // l may reach r+1: the empty window
        best = max(best, r - l + 1);
    }
    return best;
}
// Number of subarrays with at most K distinct values; values must be in [0, V) (compress first).
ll countAtMostDistinct(const vector<int>& a, int K, int V) {
    if (K <= 0) return 0;
    vector<int> cnt(V, 0); int distinct = 0; ll total = 0;
    for (int l = 0, r = 0; r < (int)a.size(); r++) {
        if (cnt[a[r]]++ == 0) distinct++;
        while (distinct > K) if (--cnt[a[l++]] == 0) distinct--;
        total += r - l + 1;                        // every start in [l, r] is good for this r
    }
    return total;
}
ll countExactlyDistinct(const vector<int>& a, int K, int V) {
    return countAtMostDistinct(a, K, V) - countAtMostDistinct(a, K - 1, V);
}
// Maximum sum over all windows of fixed length k (1 <= k <= n).
ll maxFixedWindow(const vector<ll>& a, int k) {
    ll s = 0;
    for (int i = 0; i < k; i++) s += a[i];
    ll best = s;
    for (int i = k; i < (int)a.size(); i++) { s += a[i] - a[i - k]; best = max(best, s); }
    return best;
}
```

```java
static int longestSumAtMost(long[] a, long S) {         // requires a[i] >= 0
    int best = 0; long sum = 0;
    for (int l = 0, r = 0; r < a.length; r++) {
        sum += a[r];
        while (l <= r && sum > S) sum -= a[l++];
        best = Math.max(best, r - l + 1);
    }
    return best;
}
static long countAtMostDistinct(int[] a, int K, int V) { // values in [0, V)
    if (K <= 0) return 0;
    int[] cnt = new int[V]; int distinct = 0; long total = 0;
    for (int l = 0, r = 0; r < a.length; r++) {
        if (cnt[a[r]]++ == 0) distinct++;
        while (distinct > K) if (--cnt[a[l++]] == 0) distinct--;
        total += r - l + 1;
    }
    return total;
}
static long countExactlyDistinct(int[] a, int K, int V) {
    return countAtMostDistinct(a, K, V) - countAtMostDistinct(a, K - 1, V);
}
static long maxFixedWindow(long[] a, int k) {
    long s = 0;
    for (int i = 0; i < k; i++) s += a[i];
    long best = s;
    for (int i = k; i < a.length; i++) { s += a[i] - a[i - k]; best = Math.max(best, s); }
    return best;
}
```

### 3.2 Opposite-direction pointers and two arrays

```cpp
// Sorted a: some i < j with a[i] + a[j] == X, or {-1, -1}.
pair<int,int> twoSumSorted(const vector<ll>& a, ll X) {
    int i = 0, j = (int)a.size() - 1;
    while (i < j) {
        ll s = a[i] + a[j];
        if (s == X) return {i, j};
        if (s < X) i++; else j--;                  // s < X: row i has nothing left, drop it
    }
    return {-1, -1};
}
// Sorted a: number of pairs i < j with a[i] + a[j] <= X.
ll countPairsAtMost(const vector<ll>& a, ll X) {
    ll cnt = 0;
    for (int i = 0, j = (int)a.size() - 1; i < j; i++) {
        while (i < j && a[i] + a[j] > X) j--;
        cnt += j - i;                              // partners i+1..j all work
    }
    return cnt;
}
// Sorted a: all value-distinct triples with sum X. O(n^2).
vector<array<ll,3>> threeSum(const vector<ll>& a, ll X) {
    vector<array<ll,3>> res; int n = a.size();
    for (int i = 0; i < n; i++) {
        if (i > 0 && a[i] == a[i - 1]) continue;   // same first value gives the same triples
        int j = i + 1, k = n - 1;
        while (j < k) {
            ll s = a[i] + a[j] + a[k];
            if (s < X) j++;
            else if (s > X) k--;
            else {
                res.push_back({a[i], a[j], a[k]});
                ll vj = a[j], vk = a[k];
                while (j < k && a[j] == vj) j++;   // skip duplicates on both sides
                while (j < k && a[k] == vk) k--;
            }
        }
    }
    return res;
}
vector<ll> mergeSorted(const vector<ll>& a, const vector<ll>& b) {
    vector<ll> c; c.reserve(a.size() + b.size());
    size_t i = 0, j = 0;
    while (i < a.size() && j < b.size()) c.push_back(a[i] <= b[j] ? a[i++] : b[j++]);  // <= keeps it stable
    while (i < a.size()) c.push_back(a[i++]);
    while (j < b.size()) c.push_back(b[j++]);
    return c;
}
// Sorted a, b: number of (i, j) with a[i] + b[j] <= X.
ll countCrossPairsAtMost(const vector<ll>& a, const vector<ll>& b, ll X) {
    ll cnt = 0; int j = (int)b.size() - 1;
    for (size_t i = 0; i < a.size(); i++) {
        while (j >= 0 && a[i] + b[j] > X) j--;
        cnt += j + 1;
    }
    return cnt;
}
// Sorted, non-empty a, b: min |a[i] - b[j]|.
ll closestCross(const vector<ll>& a, const vector<ll>& b) {
    ll best = LLONG_MAX; size_t i = 0, j = 0;
    while (i < a.size() && j < b.size()) {
        best = min(best, llabs(a[i] - b[j]));
        if (a[i] < b[j]) i++; else j++;            // the smaller head has seen its best partner
    }
    return best;
}
```

```java
static int[] twoSumSorted(long[] a, long X) {
    int i = 0, j = a.length - 1;
    while (i < j) {
        long s = a[i] + a[j];
        if (s == X) return new int[]{i, j};
        if (s < X) i++; else j--;
    }
    return new int[]{-1, -1};
}
static long countPairsAtMost(long[] a, long X) {
    long cnt = 0;
    for (int i = 0, j = a.length - 1; i < j; i++) {
        while (i < j && a[i] + a[j] > X) j--;
        cnt += j - i;
    }
    return cnt;
}
static List<long[]> threeSum(long[] a, long X) {
    List<long[]> res = new ArrayList<>(); int n = a.length;
    for (int i = 0; i < n; i++) {
        if (i > 0 && a[i] == a[i - 1]) continue;
        int j = i + 1, k = n - 1;
        while (j < k) {
            long s = a[i] + a[j] + a[k];
            if (s < X) j++;
            else if (s > X) k--;
            else {
                res.add(new long[]{a[i], a[j], a[k]});
                long vj = a[j], vk = a[k];
                while (j < k && a[j] == vj) j++;
                while (j < k && a[k] == vk) k--;
            }
        }
    }
    return res;
}
static long[] mergeSorted(long[] a, long[] b) {
    long[] c = new long[a.length + b.length]; int i = 0, j = 0, t = 0;
    while (i < a.length && j < b.length) c[t++] = a[i] <= b[j] ? a[i++] : b[j++];
    while (i < a.length) c[t++] = a[i++];
    while (j < b.length) c[t++] = b[j++];
    return c;
}
static long countCrossPairsAtMost(long[] a, long[] b, long X) {
    long cnt = 0; int j = b.length - 1;
    for (int i = 0; i < a.length; i++) {
        while (j >= 0 && a[i] + b[j] > X) j--;
        cnt += j + 1;
    }
    return cnt;
}
static long closestCross(long[] a, long[] b) {
    long best = Long.MAX_VALUE; int i = 0, j = 0;
    while (i < a.length && j < b.length) {
        best = Math.min(best, Math.abs(a[i] - b[j]));
        if (a[i] < b[j]) i++; else j++;
    }
    return best;
}
```

### 3.3 Floyd's cycle detection and the two-stack queue

```cpp
// Rho shape of x0, f(x0), f(f(x0)), ...: returns {mu, lambda} = (tail length, cycle length).
pair<ll,ll> floydRho(const function<ll(ll)>& f, ll x0) {
    ll slow = f(x0), fast = f(f(x0));
    while (slow != fast) { slow = f(slow); fast = f(f(fast)); }
    ll mu = 0; slow = x0;
    while (slow != fast) { slow = f(slow); fast = f(fast); mu++; }   // meet at the cycle entrance
    ll lam = 1; fast = f(slow);
    while (slow != fast) { fast = f(fast); lam++; }
    return {mu, lam};
}
// Queue with push_back, pop_front and gcd of its contents, amortised O(1) gcd calls per operation.
struct GcdQueue {
    vector<pair<ll,ll>> in, out;                   // (value, gcd of this stack from its bottom up to here)
    static ll top(const vector<pair<ll,ll>>& s) { return s.empty() ? 0 : s.back().second; }
    void push(ll x) { in.push_back({x, gcd(top(in), x)}); }
    void pop() {                                   // precondition: size() > 0
        if (out.empty())
            while (!in.empty()) { ll x = in.back().first; in.pop_back(); out.push_back({x, gcd(top(out), x)}); }
        out.pop_back();
    }
    ll query() const { return gcd(top(in), top(out)); }   // gcd(0, x) = x, so an empty queue gives 0
    size_t size() const { return in.size() + out.size(); }
};
```

```java
static long[] floydRho(LongUnaryOperator f, long x0) {
    long slow = f.applyAsLong(x0), fast = f.applyAsLong(f.applyAsLong(x0));
    while (slow != fast) { slow = f.applyAsLong(slow); fast = f.applyAsLong(f.applyAsLong(fast)); }
    long mu = 0; slow = x0;
    while (slow != fast) { slow = f.applyAsLong(slow); fast = f.applyAsLong(fast); mu++; }
    long lam = 1; fast = f.applyAsLong(slow);
    while (slow != fast) { fast = f.applyAsLong(fast); lam++; }
    return new long[]{mu, lam};
}
static class GcdQueue {                            // cap = max number of elements alive at once
    final long[] inV, inG, outV, outG; int inN = 0, outN = 0;
    GcdQueue(int cap) { inV = new long[cap]; inG = new long[cap]; outV = new long[cap]; outG = new long[cap]; }
    static long gcd(long a, long b) { while (b != 0) { long t = a % b; a = b; b = t; } return Math.abs(a); }
    void push(long x) { inV[inN] = x; inG[inN] = gcd(inN == 0 ? 0 : inG[inN - 1], x); inN++; }
    void pop() {
        if (outN == 0)
            while (inN > 0) { long x = inV[--inN]; outV[outN] = x; outG[outN] = gcd(outN == 0 ? 0 : outG[outN - 1], x); outN++; }
        outN--;
    }
    long query() { return gcd(inN == 0 ? 0 : inG[inN - 1], outN == 0 ? 0 : outG[outN - 1]); }
    int size() { return inN + outN; }
}
```

## 4. Recognising the pattern

| Signal in the statement | Think |
|---|---|
| "longest / shortest / count subarrays (substrings) such that …", $n \ge 10^5$, values $\ge 0$ | same-direction window; check heredity first |
| "at most $K$ distinct / changes / zeros" | window with a counter; "exactly $K$" = two "at most" calls |
| "contains all …", "covers every type" | upward-closed window: shrink while still covering, record, then shrink once more |
| "every window of length $k$" | fixed window, update by one element in and one out |
| pairs/triples with a sum condition, order of elements irrelevant | sort, then opposite-direction pointers |
| "after sorting, max − min $\le d$" (teams, tuples, groups) | sort, then window over the sorted values |
| two sorted lists, nearest/closest, merge | two pointers on two arrays |
| linked list cycle, "repeat $f$ until a value repeats" with tight memory, duplicate in $1..n$ | Floyd fast/slow |
| negative numbers with a sum target | **not** two pointers: prefix sums + hash map / deque / sorting |
| subsequence (not contiguous) | usually not a window; greedy matching with one pointer per string, or DP |

Often confused with: binary search on the answer (two pointers is the $O(n)$ replacement when the feasibility test of
"length $w$" is itself a window scan — see [binary search](02-binary-search-and-binary-search-on-answer.md)), and
with Mo's algorithm (two pointers over *offline queries* rather than over one array — see
[sqrt decomposition and Mo](../08-Data-Structures/07-sqrt-decomposition-and-mos-algorithm.md)).

## 5. Worked examples (graded)

### Example 1 — Number of Pairs  ·  ★ 1300

- **Source:** [CF 1538C · Number of Pairs](https://codeforces.com/problemset/problem/1538/C) — 1300
- **Difficulty:** 1300
- **Problem:** $t$ test cases, total $n \le 2 \cdot 10^5$. Given $a_1..a_n$ ($1 \le a_i \le 10^9$) and $l \le r$, count pairs
  $i < j$ with $l \le a_i + a_j \le r$.
- **Thinking from first principles:** the answer depends only on the multiset, so sort. A two-sided condition is awkward;
  a one-sided one ("$\le X$") is a staircase walk. Two-sided = difference of two one-sided counts (F5). Dead end: binary
  search for each $i$ also works ($O(n \log n)$) but the walk is simpler and linear after sorting.

<details><summary>Solution</summary>

Sort; answer $= C(r) - C(l-1)$ with $C(X) = \#\{i<j : a_i + a_j \le X\}$ computed by `countPairsAtMost` (§3.2). The pointer
$j$ is the largest index with $a_i + a_j \le X$; as $i$ grows, $a_i$ grows, so $j$ only decreases. $O(n \log n)$ per test
for the sort, $O(n)$ for the walks. The answer can reach $\approx 2 \cdot 10^{10}$: 64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;
long long countAtMost(const vector<long long>& a, long long X) {
    long long cnt = 0;
    for (int i = 0, j = (int)a.size() - 1; i < j; i++) {
        while (i < j && a[i] + a[j] > X) j--;
        cnt += j - i;
    }
    return cnt;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        int n; long long l, r; cin >> n >> l >> r;
        vector<long long> a(n);
        for (auto& x : a) cin >> x;
        sort(a.begin(), a.end());
        cout << countAtMost(a, r) - countAtMost(a, l - 1) << '\n';
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static long countAtMost(long[] a, long X) {
        long cnt = 0;
        for (int i = 0, j = a.length - 1; i < j; i++) {
            while (i < j && a[i] + a[j] > X) j--;
            cnt += j - i;
        }
        return cnt;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = in.nextInt();
        Random rnd = new Random(2024);
        while (t-- > 0) {
            int n = in.nextInt(); long l = in.nextLong(), r = in.nextLong();
            long[] a = new long[n];
            for (int i = 0; i < n; i++) a[i] = in.nextLong();
            for (int i = n - 1; i > 0; i--) { int k = rnd.nextInt(i + 1); long tmp = a[i]; a[i] = a[k]; a[k] = tmp; }
            Arrays.sort(a);                            // shuffled first: defeats anti-quicksort tests
            out.println(countAtMost(a, r) - countAtMost(a, l - 1));
        }
        out.flush();
    }
    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
3
4 3 7
1 2 3 4
1 1 1
5
5 5 6
5 1 3 3 2
out:
6
0
4
-->
<!-- test
in:
2
3 2 2
1 1 1
4 1000000000 2000000000
1000000000 1000000000 1 999999999
out:
3
6
-->

</details>

### Example 2 — Cellular Network  ·  ★ 1500

- **Source:** [CF 702C · Cellular Network](https://codeforces.com/problemset/problem/702/C) — 1500
- **Difficulty:** 1500
- **Problem:** $n$ cities and $m$ towers on a line ($n, m \le 10^5$, coordinates $|x| \le 10^9$), both lists given in
  non-decreasing order. Find the smallest $r$ such that every city is within distance $r$ of some tower.
- **Thinking from first principles:** $r$ is the maximum over cities of the distance to the *nearest* tower, and the
  nearest tower is either the last tower $\le$ the city or the first tower $\ge$ it. Binary searching each city is
  $O(n \log m)$; but the cities are sorted, so "first tower $\ge$ city" only moves right — two pointers on two arrays.

<details><summary>Solution</summary>

Keep $j$ = first tower with $b_j \ge a_i$. For the next city ($a_{i+1} \ge a_i$) that index can only grow. Distance is
$\min(b_j - a_i, a_i - b_{j-1})$ with missing sides ignored. Answer $= \max_i$. $O(n + m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    vector<long long> a(n), b(m);
    for (auto& x : a) cin >> x;
    for (auto& x : b) cin >> x;
    long long r = 0; int j = 0;
    for (int i = 0; i < n; i++) {
        while (j < m && b[j] < a[i]) j++;              // b[j] is the first tower >= a[i]
        long long d = LLONG_MAX;
        if (j < m) d = b[j] - a[i];
        if (j > 0) d = min(d, a[i] - b[j - 1]);
        r = max(r, d);
    }
    cout << r << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt();
        long[] a = new long[n], b = new long[m];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        for (int i = 0; i < m; i++) b[i] = in.nextLong();
        long r = 0; int j = 0;
        for (int i = 0; i < n; i++) {
            while (j < m && b[j] < a[i]) j++;
            long d = Long.MAX_VALUE;
            if (j < m) d = b[j] - a[i];
            if (j > 0) d = Math.min(d, a[i] - b[j - 1]);
            r = Math.max(r, d);
        }
        System.out.println(r);
    }
    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
4 2
-5 0 3 10
1 4
out:
6
-->
<!-- test
in:
1 1
7
7
out:
0
-->
<!-- test
in:
3 3
-1000000000 0 1000000000
-1000000000 -1000000000 -999999999
out:
1999999999
-->

</details>

### Example 3 — Rho of a pseudo-random generator  ·  ★ ≈1500 (est.)

- **Source:** Original problem.
- **Difficulty:** ≈1500 (est.)
- **Problem:** $x_0 = s$, $x_{t+1} = (x_t^2 + c) \bmod m$ with $1 \le m \le 10^9$, $0 \le s, c < m$. It is guaranteed that
  $\mu + \lambda \le 10^7$, where $\mu$ is the index of the first value that ever repeats and $\lambda$ the cycle length.
  Memory limit 4 MB. Print $\mu$ and $\lambda$.
- **Thinking from first principles:** a hash set of visited values finds both in one pass but needs up to $10^7$ entries —
  far over 4 MB. The sequence is a walk in a functional graph, so it is a rho; Floyd needs two numbers of state.
  $x_t < 10^9$ so $x_t^2 < 10^{18}$ fits in 64 bits.

<details><summary>Solution</summary>

Floyd exactly as in (F9): find a meeting point, restart one pointer from $x_0$ to get $\mu$, walk the cycle for $\lambda$.
$O(\mu + \lambda)$ time, $O(1)$ memory.

```cpp
#include <bits/stdc++.h>
using namespace std;
long long s, c, m;
long long f(long long x) { return (x * x + c) % m; }
int main() {
    cin >> s >> c >> m;
    long long slow = f(s), fast = f(f(s));
    while (slow != fast) { slow = f(slow); fast = f(f(fast)); }
    long long mu = 0; slow = s;
    while (slow != fast) { slow = f(slow); fast = f(fast); mu++; }
    long long lam = 1; fast = f(slow);
    while (slow != fast) { fast = f(fast); lam++; }
    cout << mu << ' ' << lam << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static long c, m;
    static long f(long x) { return (x * x + c) % m; }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        long s = in.nextLong(); c = in.nextLong(); m = in.nextLong();
        long slow = f(s), fast = f(f(s));
        while (slow != fast) { slow = f(slow); fast = f(f(fast)); }
        long mu = 0; slow = s;
        while (slow != fast) { slow = f(slow); fast = f(fast); mu++; }
        long lam = 1; fast = f(slow);
        while (slow != fast) { fast = f(fast); lam++; }
        System.out.println(mu + " " + lam);
    }
    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
0 1 10
out:
0 6
-->
<!-- test
in:
2 0 10
out:
2 1
-->
<!-- test
in:
0 0 1
out:
0 1
-->
<!-- test
in:
3 7 1000
out:
1 8
-->

</details>

### Example 4 — Subarrays with exactly K distinct values  ·  ★ ≈1600 (est.)

- **Source:** Original problem (the same idea as [LC 992 · Subarrays with K Different Integers](https://leetcode.com/problems/subarrays-with-k-different-integers/) — Hard).
- **Difficulty:** ≈1600 (est.)
- **Problem:** $n \le 2 \cdot 10^5$, $1 \le K \le n$, $1 \le a_i \le 10^9$. Count subarrays containing exactly $K$ distinct values.
- **Thinking from first principles:** try a window directly: for fixed $r$, the left ends that give exactly $K$ distinct form
  an *interval* $[L_K(r), L_{K-1}(r))$ — not a prefix — so one pointer is not enough (you would need two). "At most $K$" is
  hereditary, so count it with one pointer and subtract (F4). Values up to $10^9$: compress to $0..n-1$ so a plain array
  can count frequencies (a hash map works but is slower and, in C++, hackable).

<details><summary>Solution</summary>

Compress, then answer $= A(K) - A(K-1)$ with $A$ = `countAtMostDistinct` (§3.1). $O(n \log n)$ for compression,
$O(n)$ for the two scans. The answer can be $\approx n^2/2$: 64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;
long long atMost(const vector<int>& a, int K, int V) {
    if (K <= 0) return 0;
    vector<int> cnt(V, 0); int distinct = 0; long long total = 0;
    for (int l = 0, r = 0; r < (int)a.size(); r++) {
        if (cnt[a[r]]++ == 0) distinct++;
        while (distinct > K) if (--cnt[a[l++]] == 0) distinct--;
        total += r - l + 1;
    }
    return total;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, K; cin >> n >> K;
    vector<int> a(n);
    for (auto& x : a) cin >> x;
    vector<int> vals(a);
    sort(vals.begin(), vals.end());
    vals.erase(unique(vals.begin(), vals.end()), vals.end());
    for (auto& x : a) x = lower_bound(vals.begin(), vals.end(), x) - vals.begin();
    int V = vals.size();
    cout << atMost(a, K, V) - atMost(a, K - 1, V) << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static long atMost(int[] a, int K, int V) {
        if (K <= 0) return 0;
        int[] cnt = new int[V]; int distinct = 0; long total = 0;
        for (int l = 0, r = 0; r < a.length; r++) {
            if (cnt[a[r]]++ == 0) distinct++;
            while (distinct > K) if (--cnt[a[l++]] == 0) distinct--;
            total += r - l + 1;
        }
        return total;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), K = in.nextInt();
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        Integer[] boxed = new Integer[n];                  // object sort: merge sort, no anti-quicksort risk
        for (int i = 0; i < n; i++) boxed[i] = a[i];
        Arrays.sort(boxed);
        int[] vals = new int[n]; int V = 0;
        for (int i = 0; i < n; i++) if (V == 0 || vals[V - 1] != boxed[i]) vals[V++] = boxed[i];
        for (int i = 0; i < n; i++) a[i] = Arrays.binarySearch(vals, 0, V, a[i]);   // present, so index >= 0
        System.out.println(atMost(a, K, V) - atMost(a, K - 1, V));
    }
    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
6 2
5 5 7 5 9 9
out:
7
-->
<!-- test
in:
1 1
1000000000
out:
1
-->
<!-- test
in:
4 3
2 2 2 2
out:
0
-->
<!-- test
in:
7 3
1 2 3 1 2 3 4
out:
11
-->

</details>

### Example 5 — Quiz Master  ·  ★ 1700

- **Source:** [CF 1777C · Quiz Master](https://codeforces.com/problemset/problem/1777/C) — 1700
- **Difficulty:** 1700
- **Problem:** $t$ tests; $n$ students with smartness $a_i$ and topics $1..m$ ($\sum n, \sum m \le 10^5$, $a_i \le 10^5$).
  Student $i$ knows topic $T$ iff $T \mid a_i$. Choose a team that collectively knows every topic and minimises
  $\max a - \min a$ over the team; print it, or $-1$ if impossible.
- **Thinking from first principles:** only the min and max of the team matter, and adding students between them never
  hurts — so after sorting, an optimal team is a contiguous range of the sorted array. "Covers all topics" is upward
  closed, so a window works: for each right end, shrink the left end while the window still covers everything. The
  window statistic is "how many topics have count $> 0$", updated through the divisors of the entering/leaving value
  (each $a \le 10^5$ has at most 128 divisors).

<details><summary>Solution</summary>

Precompute divisor lists up to $10^5$ by a harmonic sieve ($\sum_{d} 10^5/d \approx 1.2 \cdot 10^6$ entries). Sort $a$. Keep
`cnt[T]` for $T \le m$ and `covered`. Add $a_r$'s divisors $\le m$; while `covered == m`, record $a_r - a_l$ and remove
$a_l$. Proof: for each $r$ we try every $l$ for which $[l, r]$ covers (the largest such $l$ is reached, and smaller $l$ give
larger differences); $l$ never needs to move back because covering is upward closed (F1). Time
$O(\sum (n \log n + n \cdot d_{\max}))$.

```cpp
#include <bits/stdc++.h>
using namespace std;
const int MX = 100000;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    vector<vector<int>> divs(MX + 1);
    for (int d = 1; d <= MX; d++)
        for (int x = d; x <= MX; x += d) divs[x].push_back(d);   // each list ends up sorted ascending
    int t; cin >> t;
    while (t--) {
        int n, m; cin >> n >> m;
        vector<int> a(n);
        for (auto& x : a) cin >> x;
        sort(a.begin(), a.end());
        vector<int> cnt(m + 1, 0);
        int covered = 0, best = INT_MAX;
        for (int l = 0, r = 0; r < n; r++) {
            for (int d : divs[a[r]]) { if (d > m) break; if (cnt[d]++ == 0) covered++; }
            while (covered == m) {
                best = min(best, a[r] - a[l]);
                for (int d : divs[a[l]]) { if (d > m) break; if (--cnt[d] == 0) covered--; }
                l++;
            }
        }
        cout << (best == INT_MAX ? -1 : best) << '\n';
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        final int MX = 100000;
        int[] deg = new int[MX + 1];
        for (int d = 1; d <= MX; d++) for (int x = d; x <= MX; x += d) deg[x]++;
        int[][] divs = new int[MX + 1][];
        for (int x = 1; x <= MX; x++) divs[x] = new int[deg[x]];
        int[] fill = new int[MX + 1];
        for (int d = 1; d <= MX; d++) for (int x = d; x <= MX; x += d) divs[x][fill[x]++] = d;
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = in.nextInt();
        Random rnd = new Random(12345);
        while (t-- > 0) {
            int n = in.nextInt(), m = in.nextInt();
            int[] a = new int[n];
            for (int i = 0; i < n; i++) a[i] = in.nextInt();
            for (int i = n - 1; i > 0; i--) { int k = rnd.nextInt(i + 1); int tmp = a[i]; a[i] = a[k]; a[k] = tmp; }
            Arrays.sort(a);                                      // shuffled first: no anti-quicksort input
            int[] cnt = new int[m + 1];
            int covered = 0, best = Integer.MAX_VALUE;
            for (int l = 0, r = 0; r < n; r++) {
                for (int d : divs[a[r]]) { if (d > m) break; if (cnt[d]++ == 0) covered++; }
                while (covered == m) {
                    best = Math.min(best, a[r] - a[l]);
                    for (int d : divs[a[l]]) { if (d > m) break; if (--cnt[d] == 0) covered--; }
                    l++;
                }
            }
            out.println(best == Integer.MAX_VALUE ? -1 : best);
        }
        out.flush();
    }
    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
3
2 4
3 7
4 2
3 7 2 9
5 7
6 4 3 5 7
out:
-1
0
3
-->
<!-- test
in:
2
1 1
100000
6 6
12 18 5 30 7 2
out:
0
7
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **State the heredity (or upward closure) in one sentence before coding.** If you cannot, the window is probably
   wrong; the classic failure is "sum $\ge S$" with negative numbers, where a longer window can be worse.
2. **The empty window.** In "longest with sum $\le S$", a single element larger than $S$ forces $l = r + 1$. Guard the
   shrink loop with `l <= r` so you never remove from an empty window, and make sure `r - l + 1 = 0` is handled.
3. **Count with `r - l + 1` per right end**, not by enumerating windows; use 64-bit — $n(n+1)/2$ overflows `int` at
   $n \approx 65\,536$.
4. **"Exactly $K$" = $A(K) - A(K-1)$**, and $A(0) = 0$ for distinct counts (guard `K <= 0`). For "at least $K$", use
   total $- A(K-1)$ or the upward-closed loop directly.
5. **Compress before counting frequencies.** A `vector<int>`/`int[]` of size $V$ is several times faster than a hash map;
   `unordered_map` with default hash can be hacked (anti-hash tests), and Java `HashMap<Integer,Integer>` boxes every
   value. Reset counts per test in $O(\text{touched})$ or allocate size $m+1$, never $10^9$.
6. **Sorting destroys positions.** Opposite-direction pointers need sorted data; if the answer needs original indices,
   sort `(value, index)` pairs.
7. **Duplicates in 2-sum / 3-sum.** For value-distinct triples, skip equal values for the fixed element *and* after each
   match on both inner pointers. For *index* pairs with equal values (counting), do not skip anything.
8. **Two-sided conditions** ($lo \le \text{sum} \le hi$) are two one-sided counts. Trying to maintain both bounds with
   one pointer pair is a frequent WA.
9. **Floyd initialisation.** Start with `slow = f(x0), fast = f(f(x0))` (or both at `x0` and use a do-while); starting
   both at `x0` with a `while (slow != fast)` loop never enters the loop.
10. **Java sorting traps.** `Arrays.sort(int[])` / `long[]` is a dual-pivot quicksort with adversarial $O(n^2)$ inputs that
    hackers use on Codeforces: shuffle first, or sort `Integer[]`/objects (merge sort). `Arrays.binarySearch` returns
    $-(\text{insertion point}) - 1$ for missing keys — only use it on values known to be present, as in Example 4.
11. **Upward-closed loop order.** For "shortest window covering everything", the record step goes *inside* the shrink
    loop (record, then remove $a_l$), as in Example 5; for "longest good window" it goes after the loop.
12. **Fixed windows with $n < k$** have no window at all — decide the output for that case explicitly.

## 7. Going further (toward 2400–2600+)

- **Non-invertible window statistics.** gcd, OR, AND, min over a sliding window via the two-stack queue (F10) or a sparse
  table ([05 sparse table](../08-Data-Structures/05-sparse-table-and-rmq.md)). Model problem: longest subarray whose
  differences share a common divisor $\ge 2$ — [CF 1548B · Integers Have Friends](https://codeforces.com/problemset/problem/1548/B) — 1800.
- **Two pointers + a heavier structure.** Window max − min via two monotonic deques ([04](04-monotonic-stack-and-deque.md));
  window median via two heaps or an order-statistics tree; "next position after a valid segment" + binary lifting
  ([CF 1516D · Cut](https://codeforces.com/problemset/problem/1516/D) — 2100, see [binary lifting](../10-Trees/02-lca-and-binary-lifting.md)).
- **Two pointers over queries:** Mo's algorithm reorders offline range queries so that both endpoints move
  $O(n\sqrt{q})$ in total ([08/07](../08-Data-Structures/07-sqrt-decomposition-and-mos-algorithm.md)).
- **Monotone optimal split points.** When the best split $opt(i)$ is non-decreasing in $i$, a pointer replaces a search —
  the root idea of divide-and-conquer and Knuth optimisation ([07/03](../07-DP-Optimizations/03-divide-and-conquer-optimization.md),
  [07/04](../07-DP-Optimizations/04-knuth-optimization.md)).
- **Rotating calipers** is two pointers on a convex polygon's boundary ([14/04](../14-Geometry/04-convex-hull-and-rotating-calipers.md)).
- **Cycle detection at scale:** Pollard's rho factorisation runs Floyd/Brent on $x \mapsto x^2 + c \bmod n$
  ([04/06](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md)); functional-graph problems
  with $10^{18}$ steps use binary lifting or cycle + tail decomposition ([09/10](../09-Graphs/10-functional-graphs-and-special-graphs.md)).

## 8. Practice ladder

**≤ 1400**
- [ ] [CF 1690D · Black and White Stripe](https://codeforces.com/problemset/problem/1690/D) — 1000
- [ ] [CF 1354B · Ternary String](https://codeforces.com/problemset/problem/1354/B) — 1200
- [ ] [CF 1692E · Binary Deque](https://codeforces.com/problemset/problem/1692/E) — 1200
- [ ] [CF 489B · BerSU Ball](https://codeforces.com/problemset/problem/489/B) — 1200
- [ ] [CF 1873F · Money Trees](https://codeforces.com/problemset/problem/1873/F) — 1300
- [ ] [CF 279B · Books](https://codeforces.com/problemset/problem/279/B) — 1400
- [ ] [CF 1324D · Pair of Topics](https://codeforces.com/problemset/problem/1324/D) — 1400
- [ ] [CF 1955D · Inaccurate Subsequence Search](https://codeforces.com/problemset/problem/1955/D) — 1400
- [ ] [CSES 1640 · Sum of Two Values](https://cses.fi/problemset/task/1640)
- [ ] [CSES 1090 · Ferris Wheel](https://cses.fi/problemset/task/1090)
- [ ] [CSES 1141 · Playlist](https://cses.fi/problemset/task/1141)
- [ ] [CSES 1660 · Subarray Sums I](https://cses.fi/problemset/task/1660)

**1400–1700**
- [ ] [CF 580B · Kefa and Company](https://codeforces.com/problemset/problem/580/B) — 1500
- [ ] [CF 676C · Vasya and String](https://codeforces.com/problemset/problem/676/C) — 1500
- [ ] [CF 701C · They Are Everywhere](https://codeforces.com/problemset/problem/701/C) — 1500
- [ ] [CF 1462E1 · Close Tuples (easy version)](https://codeforces.com/problemset/problem/1462/E1) — 1500
- [ ] [CSES 1641 · Sum of Three Values](https://cses.fi/problemset/task/1641)
- [ ] [CSES 2428 · Distinct Values Subarrays II](https://cses.fi/problemset/task/2428)
- [ ] [CSES 3220 · Sliding Window Sum](https://cses.fi/problemset/task/3220)
- [ ] [AtCoder ABC098 D · Xor Sum 2](https://atcoder.jp/contests/abc098/tasks/arc098_b)
- [ ] [CF 1041D · Glider](https://codeforces.com/problemset/problem/1041/D) — 1700

**1700–2100**
- [ ] [CF 1548B · Integers Have Friends](https://codeforces.com/problemset/problem/1548/B) — 1800
- [ ] [CF 1611F · ATM and Students](https://codeforces.com/problemset/problem/1611/F) — 1800
- [ ] [CF 6E · Exposition](https://codeforces.com/problemset/problem/6/E) — 1900
- [ ] [CF 514D · R2D2 and Droid Army](https://codeforces.com/problemset/problem/514/D) — 2000
- [ ] [CF 1632D · New Year Concert](https://codeforces.com/problemset/problem/1632/D) — 2000
- [ ] [CF 1516D · Cut](https://codeforces.com/problemset/problem/1516/D) — 2100

## 9. LeetCode / FAANG cross-reference

- [LC 167 · Two Sum II - Input Array Is Sorted](https://leetcode.com/problems/two-sum-ii-input-array-is-sorted/) — Medium — the staircase walk.
- [LC 15 · 3Sum](https://leetcode.com/problems/3sum/) — Medium — fix one, 2-sum the rest, skip duplicates (§3.2).
- [LC 16 · 3Sum Closest](https://leetcode.com/problems/3sum-closest/) — Medium — same walk, track $|s - X|$.
- [LC 18 · 4Sum](https://leetcode.com/problems/4sum/) — Medium — two fixed indices + 2-sum, $O(n^3)$; watch overflow.
- [LC 11 · Container With Most Water](https://leetcode.com/problems/container-with-most-water/) — Medium — move the shorter wall: it is the only move that can improve.
- [LC 42 · Trapping Rain Water](https://leetcode.com/problems/trapping-rain-water/) — Hard — opposite pointers with running maxima (or a monotonic stack, [04](04-monotonic-stack-and-deque.md)).
- [LC 88 · Merge Sorted Array](https://leetcode.com/problems/merge-sorted-array/) — Easy — merge from the back to work in place.
- [LC 977 · Squares of a Sorted Array](https://leetcode.com/problems/squares-of-a-sorted-array/) — Easy — merge the two monotone halves from the ends.
- [LC 3 · Longest Substring Without Repeating Characters](https://leetcode.com/problems/longest-substring-without-repeating-characters/) — Medium — hereditary "all distinct".
- [LC 209 · Minimum Size Subarray Sum](https://leetcode.com/problems/minimum-size-subarray-sum/) — Medium — upward-closed window, positives only.
- [LC 76 · Minimum Window Substring](https://leetcode.com/problems/minimum-window-substring/) — Hard — "covers all" window, the Example 5 shape.
- [LC 424 · Longest Repeating Character Replacement](https://leetcode.com/problems/longest-repeating-character-replacement/) — Medium — window length − max frequency $\le k$.
- [LC 438 · Find All Anagrams in a String](https://leetcode.com/problems/find-all-anagrams-in-a-string/) — Medium — fixed window with a 26-letter count difference.
- [LC 567 · Permutation in String](https://leetcode.com/problems/permutation-in-string/) — Medium — same fixed window.
- [LC 904 · Fruit Into Baskets](https://leetcode.com/problems/fruit-into-baskets/) — Medium — longest window with $\le 2$ distinct.
- [LC 340 · Longest Substring with At Most K Distinct Characters](https://leetcode.com/problems/longest-substring-with-at-most-k-distinct-characters/) — Medium 🔒 — §3.1 with "longest" instead of "count".
- [LC 992 · Subarrays with K Different Integers](https://leetcode.com/problems/subarrays-with-k-different-integers/) — Hard — Example 4.
- [LC 930 · Binary Subarrays With Sum](https://leetcode.com/problems/binary-subarrays-with-sum/) — Medium — exactly = atMost − atMost (or prefix sums + counts).
- [LC 1248 · Count Number of Nice Subarrays](https://leetcode.com/problems/count-number-of-nice-subarrays/) — Medium — same trick on "number of odd elements".
- [LC 713 · Subarray Product Less Than K](https://leetcode.com/problems/subarray-product-less-than-k/) — Medium — hereditary because all values are $\ge 1$.
- [LC 1004 · Max Consecutive Ones III](https://leetcode.com/problems/max-consecutive-ones-iii/) — Medium — at most $k$ zeros.
- [LC 1658 · Minimum Operations to Reduce X to Zero](https://leetcode.com/problems/minimum-operations-to-reduce-x-to-zero/) — Medium — complement: longest middle window with sum $= \text{total} - x$ (positives).
- [LC 1838 · Frequency of the Most Frequent Element](https://leetcode.com/problems/frequency-of-the-most-frequent-element/) — Medium — sort, window cost $= a_r \cdot len - \text{sum} \le k$.
- [LC 2563 · Count the Number of Fair Pairs](https://leetcode.com/problems/count-the-number-of-fair-pairs/) — Medium — exactly Example 1.
- [LC 141 · Linked List Cycle](https://leetcode.com/problems/linked-list-cycle/) — Easy — Floyd meeting phase.
- [LC 142 · Linked List Cycle II](https://leetcode.com/problems/linked-list-cycle-ii/) — Medium — Floyd's $\mu$ phase (F9).
- [LC 287 · Find the Duplicate Number](https://leetcode.com/problems/find-the-duplicate-number/) — Medium — functional graph $i \to a_i$; the duplicate is the cycle entrance.
- [LC 876 · Middle of the Linked List](https://leetcode.com/problems/middle-of-the-linked-list/) — Easy — fast moves 2, slow moves 1.
- [LC 202 · Happy Number](https://leetcode.com/problems/happy-number/) — Easy — Floyd on the digit-square map.

Sliding window and two pointers are among the most frequent interview patterns. Interviewers look for the invariant ("the
window is always the longest valid one ending at `r`") and for the $O(n)$ amortised argument, stated out loud. See also
[FAANG two pointers](../17-FAANG-Interview-DSA/03-two-pointers-and-sliding-window.md) and
[linked lists](../17-FAANG-Interview-DSA/06-linked-lists.md).

## 10. Self-check

1. Define a hereditary interval predicate and prove that the minimal left end is non-decreasing in $r$.
2. Why is the sliding window $O(n)$ even though the inner `while` loop can run $n$ times in one iteration?
3. Why does "shortest subarray with sum $\ge S$" fail with two pointers when negative numbers are allowed? What replaces it?
4. Express "number of subarrays with exactly $K$ odd numbers" with one helper function.
5. In 2-sum on a sorted array, prove that moving `i` forward when $a_i + a_j < X$ never skips a solution.
6. In Floyd's algorithm, why does restarting one pointer at $x_0$ and stepping both by one meet exactly at $x_\mu$?
7. Which window statistics need a deque or a two-stack queue instead of a running total, and why?
8. When does sorting first make a "subarray" problem into a window problem, and when is sorting forbidden?

<details><summary>Answers</summary>

1. Every sub-interval of a good interval is good. $[L(r+1), r+1]$ good $\Rightarrow$ $[L(r+1), r]$ good $\Rightarrow$
   $L(r) \le L(r+1)$.
2. `l` only increases and is bounded by $n$, so the total number of inner iterations over the whole run is $\le n$
   (amortisation / potential $n - l$).
3. With negatives, extending a window can lower its sum, so the good set for fixed $r$ is not a prefix of left ends.
   Use prefix sums $P$: want the largest $i < j$ with $P_i \le P_j - S$ — a monotonic deque of candidate starts ([04](04-monotonic-stack-and-deque.md)).
4. $A(K) - A(K-1)$ where $A(k)$ counts subarrays with at most $k$ odd numbers (window), $A(-1) = 0$.
5. If $a_i + a_j < X$ then $a_i + a_k \le a_i + a_j < X$ for every remaining $k \le j$, so $a_i$ has no partner left —
   only row $i$ is discarded.
6. After meeting at time $t^{\ast}$, a multiple of $\lambda$ with $t^{\ast} \ge \mu$, the pointers sit at $x_i$ and $x_{t^{\ast}+i}$. They are
   equal for $i = \mu$ and differ for $i < \mu$ (tail vs cycle).
7. max/min (deque — removing an element can change the max to something older), gcd/OR/AND (not invertible, so you
   cannot "subtract" the leaving element; the two-stack queue avoids subtraction).
8. When only the *multiset* of chosen elements matters (pairs, teams, "max − min $\le d$ after choosing") you may sort and
   the chosen set becomes a contiguous range. When the problem is about contiguous subarrays of the given order, sorting
   destroys the structure being asked about.

</details>
