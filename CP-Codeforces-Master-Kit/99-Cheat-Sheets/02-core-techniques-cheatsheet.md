# Cheat sheet — Core Techniques

Revision sheet for [02-Core-Techniques](../02-Core-Techniques/README.md). Full derivations: [prefix sums](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md) ·
[binary search](../02-Core-Techniques/02-binary-search-and-binary-search-on-answer.md) · [two pointers](../02-Core-Techniques/03-two-pointers-and-sliding-window.md) ·
[monotonic stack and deque](../02-Core-Techniques/04-monotonic-stack-and-deque.md) · [compression and sweep](../02-Core-Techniques/05-coordinate-compression-and-sweep-line.md) ·
[ternary search and meet in the middle](../02-Core-Techniques/06-ternary-search-and-meet-in-the-middle.md) · [problem ladder](../02-Core-Techniques/problems.md).

## 1. Prefix sums and difference arrays (0-indexed, inclusive ranges)

| Formula | Meaning |
|---|---|
| $P_0 = 0,\ P_{i+1} = P_i + a_i$; $\sum_{i=l}^{r} a_i = P_{r+1} - P_l$ | range sum in $O(1)$ after $O(n)$ |
| $X_{r+1} \oplus X_l$ | range XOR (XOR is its own inverse) |
| $m_{i} = \min(m_{i-1}, a_i)$ | prefix min/max: prefixes only (min can't be undone) → [sparse table](../08-Data-Structures/05-sparse-table-and-rmq.md) for ranges |
| build $S_{i+1,j+1} = a_{ij} + S_{i,j+1} + S_{i+1,j} - S_{ij}$; query $S_{r_2+1,c_2+1} - S_{r_1,c_2+1} - S_{r_2+1,c_1} + S_{r_1,c_1}$ | 2D prefix, inclusion–exclusion |
| $d_l \mathrel{+}= v,\ d_{r+1} \mathrel{-}= v$, then $a = \text{prefix}(d)$ | $q$ range adds in $O(n + q)$, offline |
| $d_{r_1,c_1} \mathrel{+}= v,\ d_{r_1,c_2+1} \mathrel{-}= v,\ d_{r_2+1,c_1} \mathrel{-}= v,\ d_{r_2+1,c_2+1} \mathrel{+}= v$ | 2D range add, then 2D prefix |
| AP $s, s{+}k, \dots$ on $[l,r]$: $D_l \mathrel{+}= s$, $D_{l+1} \mathrel{+}= k - s$, $D_{r+1} \mathrel{-}= s + (r-l+1)k$, $D_{r+2} \mathrel{+}= s + (r-l)k$ | second-order differences; prefix **twice** |
| same AP as $C_i + K_i \cdot i$: add $s - kl$ to $C$ and $k$ to $K$ on $[l, r]$ | two first-order arrays, no index juggling |
| degree-$d$ polynomial on a range | $(d+1)$-th order differences |
| #subarrays with sum $= k$: $\sum_j \#\{i < j : P_i = P_j - k\}$ | hashmap seeded with $\text{cnt}[P_0 = 0] = 1$ |
| #subarrays with sum $\equiv 0 \pmod k$: $\sum_r \binom{c_r}{2}$ | $c_r$ = #prefixes (incl. $P_0$) with residue $r$ |
| equal numbers of 0s and 1s | map $0 \to -1$, count / longest with sum $0$ |
| updates interleaved with queries | [Fenwick](../08-Data-Structures/01-fenwick-tree.md) / [segment tree](../08-Data-Structures/02-segment-tree-basics.md) |

## 2. Binary search

**Invariant form (the only template you need):** `ok(lo) = false`, `ok(hi) = true`, `ok` monotone F…FT…T.
Loop `while (hi - lo > 1)`, `mid = lo + (hi - lo) / 2`, set `hi = mid` if `ok(mid)` else `lo = mid`. Never `±1`.
`mid` is strictly inside, so the sentinels `lo`, `hi` are never evaluated; the gap shrinks every step, so it terminates.

| Goal | `ok(i)` | Start `lo, hi` | Answer |
|---|---|---|---|
| first $i$ with $a_i \ge x$ (`lower_bound`) | $a_i \ge x$ | $-1,\ n$ | `hi` ($n$ = none) |
| first $i$ with $a_i > x$ (`upper_bound`) | $a_i > x$ | $-1,\ n$ | `hi` |
| last $i$ with $a_i \le x$ | $a_i > x$ | $-1,\ n$ | `lo` ($-1$ = none) |
| last $i$ with $a_i < x$ | $a_i \ge x$ | $-1,\ n$ | `lo` |
| count of $x$ | — | — | `upper − lower` |
| min feasible $X$ | feasible$(X)$ | known infeasible, known feasible | `hi` |
| max feasible $X$ | $\lnot$feasible$(X)$ | known feasible, known infeasible | `lo` |

| Want | C++ | Java |
|---|---|---|
| first $a_i \ge x$ / $> x$ | `lower_bound` / `upper_bound` − `begin` | write it (no array equivalent) |
| first `pred` false on partitioned range | `partition_point(b, e, pred)` | write it |
| is $x$ present | `binary_search` → `bool` | `Arrays.binarySearch(a, x)` → **any** matching index, or `-(insertionPoint) - 1` |
| sorted `List` | — | `Collections.binarySearch(list, x)`: same contract, $O(\log n)$ only for `RandomAccess` lists |
| greatest key $\le x$ | `prev(s.upper_bound(x))` unless `begin` | `floorKey(x)` / `floor(x)`, `null` if none |
| greatest key $< x$ | `prev(s.lower_bound(x))` unless `begin` | `lowerKey(x)` / `lower(x)` |
| least key $\ge x$ / $> x$ | `s.lower_bound(x)` / `s.upper_bound(x)` | `ceilingKey(x)` / `higherKey(x)` |

Traps: `std::lower_bound(s.begin(), s.end(), x)` on a `set` is $O(n)$ — use the member. `Arrays.binarySearch` on duplicates
returns an arbitrary one; its range form `(a, from, to, x)` has exclusive `to`; unboxing a `null` from `floorKey` throws.

| Topic | Formula / rule |
|---|---|
| overflow-safe mid | `lo + (hi - lo) / 2`; Java `(lo + hi) >>> 1` only for non-negative `int` |
| monotone predicate proof | show: if $X$ feasible then $X+1$ feasible (relax a constraint / reuse the same witness) |
| reals, iterations | $\lceil \log_2 (W/\varepsilon) \rceil$: $W = 2\cdot 10^9, \varepsilon = 10^{-9}$ → 61; use **100**, not `while (hi - lo > eps)`: `ulp(1e9)` $\approx 1.2 \cdot 10^{-7}$, so a smaller eps never terminates |
| k-th smallest by counting | answer $= \min\{x : \text{cnt}(\le x) \ge k\}$; it is always one of the values |
| multiplication table $n \times m$ | $\text{cnt}(x) = \sum_{i=1}^{n} \min(m, \lfloor x/i \rfloor)$, $O(n \log nm)$ |
| k-th pairwise distance | sort; $\text{cnt}(x)$ = pairs with $a_j - a_i \le x$ by two pointers, $O(n)$ per check |
| row- and column-sorted matrix | search: start top-right, go left if $> x$, down if $< x$, $O(n + m)$; k-th: BS on value + staircase count |
| fractional: max $\frac{\sum_S a}{\sum_S b}$, $b > 0$ | $F(\lambda) = \max_S \sum_S (a_i - \lambda b_i)$ is decreasing; $R^* \ge \lambda \iff F(\lambda) \ge 0$ |
| Dinkelbach | $\lambda_{t+1} = R(S_t)$ with $S_t = \arg\max F(\lambda_t)$; non-decreasing; stop when $F(\lambda_t) = 0$; usually < 10 rounds. On a penalty: [Aliens trick](../07-DP-Optimizations/06-aliens-trick-wqs-binary-search.md) |

## 3. Two pointers and sliding window

| Fact | Statement |
|---|---|
| validity | if every sub-window of a good window is good, $L(r) = \min\{l : [l, r] \text{ good}\}$ is non-decreasing ⇒ $\le 2n$ moves; #good subarrays $= \sum_r (r - L(r) + 1)$ |
| exactly $K$ | $\text{exact}(K) = \text{atMost}(K) - \text{atMost}(K-1)$ (distinct values, odd numbers, sum of 0/1 array) |
| negatives | "sum $\le S$" is not monotone under shrinking → prefix sums + deque / ordered set |
| fixed size $k$ | add $a_r$, remove $a_{r-k}$; answer for $r \ge k - 1$ |
| sorted two-sum | $i = 0, j = n - 1$: sum $< t$ ⇒ $i{+}{+}$ ($a_i$ is too small even with the largest remaining); $> t$ ⇒ $j{-}{-}$ |
| 3-sum | sort, fix the first, two-sum on the rest: $O(n^2)$; skip equal values for distinct triples |
| two sorted arrays | advance the pointer at the smaller value: merge, intersection, closest pair, $O(n + m)$ |
| Floyd | slow +1, fast +2 until equal; reset slow to $x_0$, both +1 ⇒ meet at cycle start $\mu$; walk once around ⇒ $\lambda$ |

## 4. Monotonic stack and deque

| Want for each $i$ (scan left → right; flip comparisons for "greater") | Pop while | Read off |
|---|---|---|
| previous strictly smaller | $a_{top} \ge a_i$ | top after popping |
| previous smaller-or-equal | $a_{top} > a_i$ | top after popping |
| next strictly smaller | $a_{top} > a_i$ | each popped top gets $i$ |
| next smaller-or-equal | $a_{top} \ge a_i$ | each popped top gets $i$ |

| Pattern | Formula |
|---|---|
| sum of subarray minima | $\sum_i a_i (i - L_i)(R_i - i)$, $L_i$ = prev **strictly** smaller ($-1$), $R_i$ = next smaller-**or-equal** ($n$); each subarray is counted once, at the rightmost position of its minimum. Both strict ⇒ double count on duplicates; both non-strict ⇒ subarrays missed |
| sum of ranges | $\sum \max - \sum \min$ |
| largest rectangle in histogram | $\max_i h_i (R_i - L_i - 1)$ with nearest strictly smaller on both sides |
| maximal rectangle in 0/1 matrix | heights per row, histogram per row: $O(nm)$ |
| stock span | $i - \text{prevGreater}(i)$ (previous strictly greater) |
| window max, length $k$ | pop back while $a_{back} \le a_i$; pop front while index $\le i - k$; front is the max |
| shortest subarray with sum $\ge K$ | deque of prefix indices with increasing $P$: pop front while $P_j - P_{front} \ge K$ (record); pop back while $P_{back} \ge P_j$ |
| $dp_i = \min_{j \in [i-k, i-1]} dp_j + c_i$ | deque over $dp$: [monotonic queue optimisation](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md) |
| min-Cartesian tree | parent($i$) = the larger of prev smaller and next smaller; subtree of $i$ = maximal range where $a_i$ is the min |

## 5. Coordinate compression and sweep line

| At equal coordinates | Use when |
|---|---|
| starts before ends | closed $[l, r]$: touching intervals overlap |
| ends before starts | half-open $[l, r)$: a room freed at 10 can host a meeting starting at 10 |
| integer closed $[l, r]$ → $[l, r + 1)$ | then the half-open rule; the diff-array form is $d_l{+}{+}, d_{r+1}{-}{-}$ |
| query point at $x$ (closed intervals) | after starts at $x$, before ends at $x$ |

| Pattern | Recipe |
|---|---|
| compression | sort, unique, `lower_bound` → rank in $[0, k)$; include **every** value you will look up (queries too) |
| max overlap = min rooms | events $\pm 1$, running max (lower bound and greedy match) |
| union length | sort by $l$, extend the current block, add its length when a gap appears |
| skyline | events (x, height), multiset of active heights, emit when the max changes |
| offline queries | sort queries by key, sweep objects with key $\le$ query into a Fenwick/set, write answers back by stored index |
| sweep + set | active objects in an ordered set; neighbours by `lower_bound` |
| nested segments | sort by $l$ asc, $r$ desc; Fenwick over compressed $r$ |
| rectangle union area | sweep $x$, segment tree over compressed $y$ with (cover count, covered length), $O(n \log n)$ |

## 6. Ternary search and meet in the middle

| Fact | Statement |
|---|---|
| requirement | **strictly** unimodal: strictly down then strictly up (for a min); a flat stretch away from the optimum makes $f(m_1) = f(m_2)$ uninformative |
| convexity closure | sums and maxima of convex functions are convex; $\lvert x - c\rvert$, $x^2$, linear are convex |
| integer version | min: first $m$ with $f(m) \le f(m+1)$ (strictly down, then non-decreasing); max: first $m$ with $f(m) \ge f(m+1)$ |
| real iterations | ternary: 2 evaluations per step, $\times \tfrac23$ ⇒ $\approx 3.42$ evaluations per halving, 100–200 steps; golden section reuses one point, $\times 0.618$ per evaluation ⇒ $\approx 1.44$ |
| MITM split | $2^{\lfloor n/2 \rfloor} + 2^{\lceil n/2 \rceil}$ sums; $n = 40$: $2 \cdot 2^{20}$ values, 16 MB as 64-bit |
| combine | sort both + two pointers / binary search: $O(2^{n/2} n)$; merge-generate sorted sums: $O(2^{n/2})$ |
| count sums $\le S$ | $A$ ascending, pointer into $B$ moves only down |
| 4-sum | $O(n^2)$ pair sums + hashmap or sort; watch index disjointness |
| bidirectional BFS | $b^{d/2}$ per side instead of $b^d$; expand the smaller frontier ([BFS](../09-Graphs/01-graph-representation-bfs-dfs.md)) |

## 7. Signals, techniques and costs

| Signal | Technique | Cost |
|---|---|---|
| static range sums, XORs, counts | prefix sums | $O(n)$ build (2D: $O(nm)$), $O(1)$ query |
| batch of range adds, read at the end | difference array | $O(n + q)$ |
| "count subarrays with sum $= k$ / divisible by $k$" | prefix + hashmap / residue counts | $O(n)$ expected |
| "minimise the maximum", "maximise the minimum", "smallest $X$ such that" | binary search on the answer | $O(\log V \cdot \text{check})$ |
| k-th among $n^2$ implicit values | binary search on value + counting | $O(\log V \cdot \text{count})$ |
| best ratio $\sum a / \sum b$ | fractional BS / Dinkelbach | $O(\text{iters} \cdot F)$ |
| longest/shortest window, property survives shrinking | two pointers | $O(n)$ + window structure |
| "exactly $K$" | atMost difference | $2 \times$ atMost |
| nearest greater/smaller, "how far does it extend", sum of mins | monotonic stack | $O(n)$ amortised |
| window max/min, DP over a sliding range | monotonic deque | $O(n)$ amortised |
| coordinates $\le 10^9$, $n \le 2 \cdot 10^5$ | compression | $O(n \log n)$ |
| intervals, "at some moment", union, offline queries | sweep | $O(n \log n)$ |
| one-parameter convex / unimodal cost | ternary search / BS on the slope | $O(\log V)$ evaluations |
| $n \le 40$ subsets, sums or XORs | meet in the middle | $O(2^{n/2})$–$O(2^{n/2} n)$, $O(2^{n/2})$ memory |

## 8. Templates (C++)

```cpp
vector<ll> prefix(const vector<ll>& a) {                     // sum(l..r) = P[r+1] - P[l]
    vector<ll> P(a.size() + 1, 0); for (size_t i = 0; i < a.size(); i++) P[i + 1] = P[i] + a[i]; return P;
}
struct Prefix2D {                                            // rectangle sums, inclusive corners
    vector<vector<ll>> S;
    Prefix2D(const vector<vector<ll>>& g) : S(g.size() + 1, vector<ll>(g.empty() ? 1 : g[0].size() + 1, 0)) {
        for (size_t i = 0; i < g.size(); i++)
            for (size_t j = 0; j < g[i].size(); j++) S[i + 1][j + 1] = g[i][j] + S[i][j + 1] + S[i + 1][j] - S[i][j];
    }
    ll query(int r1, int c1, int r2, int c2) const { return S[r2 + 1][c2 + 1] - S[r1][c2 + 1] - S[r2 + 1][c1] + S[r1][c1]; }
};
vector<ll> rangeAdds(int n, const vector<array<ll, 3>>& ops) {     // op = {l, r, v}
    vector<ll> d(n + 1, 0), a(n);
    for (auto& [l, r, v] : ops) { d[l] += v; d[r + 1] -= v; }
    for (ll i = 0, run = 0; i < n; i++) a[i] = run += d[i];
    return a;
}
template <class F> ll firstTrue(ll lo, ll hi, F ok) {        // ok(lo) false, ok(hi) true, monotone
    while (hi - lo > 1) { ll mid = lo + (hi - lo) / 2; (ok(mid) ? hi : lo) = mid; }
    return hi;
}
template <class F> double firstTrueReal(double lo, double hi, F ok, int iters = 100) {
    for (int it = 0; it < iters; it++) { double mid = (lo + hi) / 2; (ok(mid) ? hi : lo) = mid; }
    return hi;
}
template <class F> ll argminInt(ll lo, ll hi, F f) {         // strictly down, then non-decreasing on [lo, hi]
    while (lo < hi) { ll m = lo + (hi - lo) / 2; if (f(m) <= f(m + 1)) hi = m; else lo = m + 1; }
    return lo;
}
```

```cpp
int longestSumAtMost(const vector<ll>& a, ll S) {            // a[i] >= 0
    int best = 0; ll sum = 0;
    for (int l = 0, r = 0; r < (int)a.size(); r++) {
        for (sum += a[r]; sum > S;) sum -= a[l++];
        best = max(best, r - l + 1);
    }
    return best;
}
ll atMostK(const vector<int>& a, int K) {                    // subarrays with <= K distinct values
    if (K < 0) return 0;
    map<int, int> cnt; ll res = 0;
    for (int l = 0, r = 0; r < (int)a.size(); r++) {
        cnt[a[r]]++;
        while ((int)cnt.size() > K) { if (--cnt[a[l]] == 0) cnt.erase(a[l]); l++; }
        res += r - l + 1;
    }
    return res;
}
vector<int> nextSmaller(const vector<ll>& a) {               // next strictly smaller index, n if none
    int n = a.size(); vector<int> res(n, n), st;
    for (int i = 0; i < n; i++) {
        while (!st.empty() && a[st.back()] > a[i]) { res[st.back()] = i; st.pop_back(); }
        st.push_back(i);
    }
    return res;
}
ll sumSubarrayMins(const vector<ll>& a) {                    // L: prev strictly smaller, R: next smaller-or-equal
    int n = a.size(); vector<int> L(n), R(n, n), st;
    for (int i = 0; i < n; i++) {
        while (!st.empty() && a[st.back()] >= a[i]) { R[st.back()] = i; st.pop_back(); }
        L[i] = st.empty() ? -1 : st.back();
        st.push_back(i);
    }
    ll s = 0; for (int i = 0; i < n; i++) s += a[i] * (i - L[i]) * (R[i] - i); return s;
}
vector<ll> windowMax(const vector<ll>& a, int k) {           // n - k + 1 values
    deque<int> dq; vector<ll> res;
    for (int i = 0; i < (int)a.size(); i++) {
        while (!dq.empty() && a[dq.back()] <= a[i]) dq.pop_back();
        dq.push_back(i);
        if (dq.front() <= i - k) dq.pop_front();
        if (i >= k - 1) res.push_back(a[dq.front()]);
    }
    return res;
}
```

```cpp
vector<ll> compress(vector<ll> v) {                          // rank(x) = lower_bound(xs, x) - begin
    sort(v.begin(), v.end()); v.erase(unique(v.begin(), v.end()), v.end()); return v;
}
int maxOverlapClosed(const vector<pair<ll, ll>>& iv) {       // closed [l, r]: starts first at ties
    vector<pair<ll, int>> ev;
    for (auto& [l, r] : iv) { ev.push_back({l, -1}); ev.push_back({r, 1}); }
    sort(ev.begin(), ev.end());
    int cur = 0, best = 0;
    for (auto& [x, t] : ev) best = max(best, cur -= t);
    return best;
}
vector<ll> subsetSumsSorted(const vector<ll>& a) {           // all 2^k sums, sorted, O(2^k)
    vector<ll> s = {0};
    for (ll x : a) {
        vector<ll> t(s.size()), m(2 * s.size());
        for (size_t i = 0; i < s.size(); i++) t[i] = s[i] + x;
        merge(s.begin(), s.end(), t.begin(), t.end(), m.begin());
        s.swap(m);
    }
    return s;
}
ll countSubsetsAtMost(const vector<ll>& a, ll S) {           // n <= 40, includes the empty subset
    size_t h = a.size() / 2;
    vector<ll> A = subsetSumsSorted(vector<ll>(a.begin(), a.begin() + h));
    vector<ll> B = subsetSumsSorted(vector<ll>(a.begin() + h, a.end()));
    ll res = 0; int j = (int)B.size() - 1;
    for (ll x : A) { while (j >= 0 && x + B[j] > S) j--; res += j + 1; }
    return res;
}
```

## 9. Templates (Java)

```java
static long[] prefix(long[] a) {                             // sum(l..r) = P[r+1] - P[l]
    long[] P = new long[a.length + 1]; for (int i = 0; i < a.length; i++) P[i + 1] = P[i] + a[i]; return P;
}
static class Prefix2D {
    final long[][] S;
    Prefix2D(long[][] g) {
        S = new long[g.length + 1][g.length == 0 ? 1 : g[0].length + 1];
        for (int i = 0; i < g.length; i++)
            for (int j = 0; j < g[i].length; j++) S[i + 1][j + 1] = g[i][j] + S[i][j + 1] + S[i + 1][j] - S[i][j];
    }
    long query(int r1, int c1, int r2, int c2) { return S[r2 + 1][c2 + 1] - S[r1][c2 + 1] - S[r2 + 1][c1] + S[r1][c1]; }
}
static long[] rangeAdds(int n, long[][] ops) {               // op = {l, r, v}
    long[] d = new long[n + 1], a = new long[n];
    for (long[] o : ops) { d[(int) o[0]] += o[2]; d[(int) o[1] + 1] -= o[2]; }
    for (int i = 0; i < n; i++) a[i] = (i > 0 ? a[i - 1] : 0) + d[i];
    return a;
}
static long firstTrue(long lo, long hi, LongPredicate ok) { // ok(lo) false, ok(hi) true
    while (hi - lo > 1) { long mid = lo + (hi - lo) / 2; if (ok.test(mid)) hi = mid; else lo = mid; }
    return hi;
}
static double firstTrueReal(double lo, double hi, DoublePredicate ok, int iters) {
    for (int it = 0; it < iters; it++) { double mid = (lo + hi) / 2; if (ok.test(mid)) hi = mid; else lo = mid; }
    return hi;
}
static int lowerBound(long[] a, long x) {                    // first a[i] >= x; use a[mid] > x for upperBound
    int lo = -1, hi = a.length;
    while (hi - lo > 1) { int mid = lo + (hi - lo) / 2; if (a[mid] >= x) hi = mid; else lo = mid; }
    return hi;
}
static long argminInt(long lo, long hi, LongUnaryOperator f) {
    while (lo < hi) { long m = lo + (hi - lo) / 2; if (f.applyAsLong(m) <= f.applyAsLong(m + 1)) hi = m; else lo = m + 1; }
    return lo;
}
```

```java
static int longestSumAtMost(long[] a, long S) {              // a[i] >= 0
    int best = 0; long sum = 0;
    for (int l = 0, r = 0; r < a.length; r++) {
        for (sum += a[r]; sum > S;) sum -= a[l++];
        best = Math.max(best, r - l + 1);
    }
    return best;
}
static long atMostK(int[] a, int K) {                        // subarrays with <= K distinct values
    if (K < 0) return 0;
    HashMap<Integer, Integer> cnt = new HashMap<>(); long res = 0;
    for (int l = 0, r = 0; r < a.length; r++) {
        cnt.merge(a[r], 1, Integer::sum);
        while (cnt.size() > K) { if (cnt.merge(a[l], -1, Integer::sum) == 0) cnt.remove(a[l]); l++; }
        res += r - l + 1;
    }
    return res;
}
static int[] nextSmaller(long[] a) {                         // next strictly smaller index, n if none
    int n = a.length, top = 0; int[] res = new int[n], st = new int[n];
    Arrays.fill(res, n);
    for (int i = 0; i < n; i++) {
        while (top > 0 && a[st[top - 1]] > a[i]) res[st[--top]] = i;
        st[top++] = i;
    }
    return res;
}
static long sumSubarrayMins(long[] a) {
    int n = a.length, top = 0; int[] L = new int[n], R = new int[n], st = new int[n];
    Arrays.fill(R, n);
    for (int i = 0; i < n; i++) {
        while (top > 0 && a[st[top - 1]] >= a[i]) R[st[--top]] = i;
        L[i] = top == 0 ? -1 : st[top - 1];
        st[top++] = i;
    }
    long s = 0; for (int i = 0; i < n; i++) s += a[i] * (i - L[i]) * (R[i] - i); return s;
}
static long[] windowMax(long[] a, int k) {
    int n = a.length, head = 0, tail = 0; int[] dq = new int[n]; long[] res = new long[Math.max(0, n - k + 1)];
    for (int i = 0; i < n; i++) {
        while (tail > head && a[dq[tail - 1]] <= a[i]) tail--;
        dq[tail++] = i;
        if (dq[head] <= i - k) head++;
        if (i >= k - 1) res[i - k + 1] = a[dq[head]];
    }
    return res;
}
```

```java
static long[] compress(long[] v) {                           // rank(x) = Arrays.binarySearch(xs, x) for present x
    long[] s = v.clone(); Random rnd = new Random();
    for (int i = s.length - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long t = s[i]; s[i] = s[j]; s[j] = t; }
    Arrays.sort(s);                                          // shuffled first: no anti-quicksort worst case
    int k = 0;
    for (int i = 0; i < s.length; i++) if (k == 0 || s[i] != s[k - 1]) s[k++] = s[i];
    return Arrays.copyOf(s, k);
}
static int maxOverlapClosed(long[][] iv) {                   // start 2x sorts before end 2x+1
    long[] ev = new long[2 * iv.length];
    for (int i = 0; i < iv.length; i++) { ev[2 * i] = 2 * iv[i][0]; ev[2 * i + 1] = 2 * iv[i][1] + 1; }
    Arrays.sort(ev);
    int cur = 0, best = 0;
    for (long e : ev) best = Math.max(best, cur += (e & 1) == 0 ? 1 : -1);
    return best;
}
static long[] subsetSumsSorted(long[] a) {
    long[] s = {0};
    for (long x : a) {
        long[] m = new long[2 * s.length];
        for (int i = 0, j = 0, k = 0; k < m.length; k++)
            m[k] = (j == s.length || (i < s.length && s[i] <= s[j] + x)) ? s[i++] : s[j++] + x;
        s = m;
    }
    return s;
}
static long countSubsetsAtMost(long[] a, long S) {
    int h = a.length / 2;
    long[] A = subsetSumsSorted(Arrays.copyOfRange(a, 0, h)), B = subsetSumsSorted(Arrays.copyOfRange(a, h, a.length));
    long res = 0; int j = B.length - 1;
    for (long x : A) { while (j >= 0 && x + B[j] > S) j--; res += j + 1; }
    return res;
}
```

## 10. Top 10 mistakes

1. Prefix sums in `int` (Java and C++): $2 \cdot 10^5 \times 10^9$ overflows; use 64-bit everywhere a sum lives.
2. Mixing index conventions: $P_{r+1} - P_l$ (0-indexed) vs $P_r - P_{l-1}$ (1-indexed) in the same file.
3. Prefix hashmap not seeded with `cnt[0] = 1` — misses every subarray that starts at index 0.
4. `%` of a negative sum (C++ and Java both keep the sign): normalise `((p % k) + k) % k`.
5. Mixing binary-search templates (`lo <= hi` with `mid ± 1`, half-open elsewhere) → infinite loops; use `lo`-false / `hi`-true only.
6. Binary search on the answer with an upper bound below the true answer, or an overflowing check (sum of $10^5$ values
   of $10^{18}$ — cap the running sum or use `__int128`).
7. `while (hi - lo > 1e-9)` on large doubles; use a fixed iteration count.
8. Two pointers on a property that isn't monotone (negative numbers, "sum exactly $S$" with zeros counted wrongly).
9. Monotonic-stack contribution with the same strictness on both sides; deque storing values instead of indices (can't
   expire them).
10. Sweep tie order wrong; points compressed but query coordinates not; ternary search on a function with plateaus.

## 11. Last-minute before contest

- [ ] Binary search: `while (hi - lo > 1)`, `lo` false, `hi` true; write down what `lo` and `hi` mean before coding.
- [ ] Reals: 100 iterations (binary) / 200 (ternary); print with enough digits (`setprecision(10)` / `%.10f`).
- [ ] Prefix arrays sized $n + 1$; difference arrays sized $n + 2$ for second order; 2D arrays $(n+1) \times (m+1)$.
- [ ] Hashmap counting: seed `cnt[0] = 1`; C++ `unordered_map` needs a custom hash on Codeforces (or use `map` / sort).
- [ ] Stack/deque: decide strict vs non-strict on each side and write it in a comment.
- [ ] Sweep: decide closed or half-open, then the tie order; sort events with a total order.
- [ ] Java: `Arrays.sort` on a shuffled primitive array (or boxed / `long` encoding), `Arrays.binarySearch` returns any match or a negative code.
- [ ] $n \le 40$? Meet in the middle. $n \le 20$? Plain $2^n$ is fine.
