# Ternary search and meet in the middle

> **Band:** 🔵–🟠 1600–2300 · **Priority:** ⚡ · **FAANG:** low · **Prerequisites:** [binary search](02-binary-search-and-binary-search-on-answer.md), [two pointers](03-two-pointers-and-sliding-window.md), [recursion and brute force](../01-Foundations/04-recursion-brute-force-and-backtracking.md), [bit manipulation](../01-Foundations/03-bit-manipulation.md)
> **You can say you know this when:** you can prove a function is unimodal or convex before ternary-searching it, explain with a concrete example why plateaus break ternary search, write the integer version as a binary search on $f(m) \le f(m+1)$ — and you split a $2^{40}$ search into two $2^{20}$ halves combined with sorting and two pointers, without reaching for a hash map.

## 1. First principles — why this works

Both techniques make an exponential or continuous search tractable by exploiting **structure the brute force
ignores**: ternary search uses the *shape* of a function (one peak, no false peaks), meet in the middle uses the
*decomposability* of an objective (a sum over two independent halves).

### 1.1 Ternary search: discarding a third safely

**Setting.** $f$ is defined on $[l, r]$ and we want its minimum (the maximum is symmetric). Call $f$ **strictly
unimodal** (for minimisation) if there is a point $x^*$ with $f$ strictly decreasing on $[l, x^*]$ and strictly
increasing on $[x^*, r]$.

Without structure, finding the minimum of a black-box $f$ needs every value. With unimodality, two probes
$m_1 < m_2$ already tell us where $x^*$ is *not*:

> **Lemma.** If $f(m_1) < f(m_2)$ then $x^* < m_2$, so $(m_2, r]$ can be discarded. If $f(m_1) > f(m_2)$ then
> $x^* > m_1$, so $[l, m_1)$ can be discarded. If they are equal, $m_1 < x^* < m_2$ and either side can go.
>
> *Proof.* Suppose $f(m_1) < f(m_2)$ but $x^* \ge m_2$. Then $m_1 < m_2 \le x^*$ both lie on the strictly decreasing part,
> so $f(m_1) > f(m_2)$ — contradiction. The second case is the mirror image. For equality: $x^* \le m_1$ would give
> $f(m_1) < f(m_2)$ and $x^* \ge m_2$ would give $f(m_1) > f(m_2)$.

With $m_1, m_2$ at the thirds, every iteration keeps $\frac{2}{3}$ of the interval, so after $t$ iterations the width is
$(2/3)^t W$. For $W = 2\cdot10^9$ and target width $10^{-9}$ that is $t \approx 104$; contestants simply run 100–200
iterations of a fixed loop rather than testing `hi - lo > eps` (which can loop forever when `eps` is below the floating
spacing of the numbers involved).

**The integer version is a binary search.** On integers, define the predicate $P(m) = [\,f(m) \le f(m+1)\,]$
("the slope at $m$ is non-negative"). For a strictly unimodal $f$, $P$ is false on $[l, x^*-1]$ and true on
$[x^*, r-1]$ — monotone — so the first $m$ with $P(m)$ true is $x^*$. This is plain
[binary search on a monotone predicate](02-binary-search-and-binary-search-on-answer.md): $\lceil \log_2 W \rceil$
iterations, two evaluations each, no off-by-one fiddling with "stop when $r - l < 3$ and scan".

### 1.2 Why plateaus break it — and why convexity does not

Unimodality must be **strict** away from the optimum. Consider *maximising*

$$f = (0,\ 0,\ 0,\ 0,\ 0,\ 0,\ 0,\ 5,\ 0) \quad\text{on indices } 0..8.$$

It is "unimodal" in the weak sense (non-decreasing then non-increasing). Ternary search probes $m_1 = 2$, $m_2 = 5$,
sees $f(2) = f(5) = 0$, and whichever third it drops, it learns nothing; dropping the right third loses the peak at 7. The
slope predicate $f(m) \ge f(m+1)$ is already true at $m = 0$. No clever probing fixes this: an adversary can hide the
bump at any unprobed index, so a function that may be flat everywhere except one point needs $\Theta(n)$ probes.
**Plateaus that are not at the optimum make the problem information-theoretically hard.**

Convex functions are the main *source* of unimodality in contest problems, and they are safe even when they have a
flat bottom. $f$ is **convex** if $f(\lambda a + (1-\lambda) b) \le \lambda f(a) + (1-\lambda) f(b)$ for $\lambda \in [0,1]$.

> **Lemma (convex functions are flat only at the minimum).** Let $f$ be convex and $m_1 < m_2$. If $f(m_1) \le f(m_2)$, then
> $f(x) \ge f(m_2)$ for every $x > m_2$; if $f(m_1) \ge f(m_2)$, then $f(x) \ge f(m_1)$ for every $x < m_1$.
>
> *Proof* (first claim). $m_2$ lies between $m_1$ and $x$: $m_2 = \lambda m_1 + (1-\lambda) x$ with $\lambda \in (0,1)$. Convexity
> gives $f(m_2) \le \lambda f(m_1) + (1-\lambda) f(x) \le \lambda f(m_2) + (1-\lambda) f(x)$, so $f(m_2) \le f(x)$.

So for a convex $f$, the rule "if $f(m_1) < f(m_2)$ drop the right third, else drop the left third" never discards every
minimiser, even on ties. The same holds for the integer slope search with $f(m) \le f(m+1)$: for convex $f$ the forward
difference $\Delta f(x) = f(x+1) - f(x)$ is non-decreasing (**discrete convexity**), so $P(m) = [\Delta f(m) \ge 0]$ is monotone
and its first true point is a minimiser.

**Recognising convexity** is therefore the real skill. Closure rules: $|x - a|$, $(x-a)^2$, $e^x$, $1/\sqrt{x+1}$ (for $x > -1$)
and every affine function are convex; **non-negative weighted sums** of convex functions are convex; the **pointwise maximum**
of convex functions is convex; composing a convex function with an affine map keeps convexity. Hence $\sum w_i |x - a_i|$,
$\max_i (t_i + |x - x_i|)$, and "max over all segments of $|\text{sum} - x \cdot \text{len}|$" are convex. The **minimum** of convex
functions and the **product** of convex functions are generally *not* convex — that is where hidden plateaus and false
minima come from.

A useful consequence for two dimensions: if $f(x, y)$ is jointly convex then $g(x) = \min_y f(x, y)$ is convex, so a
**nested ternary search** (outer over $x$, inner over $y$) is correct, at $O(\text{iters}^2)$ evaluations.

### 1.3 Golden-section search: one evaluation per step

Ternary search throws away one of its two probes every iteration. Choose the probes in the golden ratio instead:
$m_1 = r - (r-l)/\varphi$, $m_2 = l + (r-l)/\varphi$ with $\varphi = \frac{1+\sqrt5}{2}$. After discarding $(m_2, r]$, the new
interval is $[l, m_2]$ of length $L/\varphi$, and its new right probe $l + (m_2 - l)/\varphi = l + L/\varphi^2$ equals the old
$m_1$ because $1/\varphi^2 = 1 - 1/\varphi$. So one of the two probes is **reused**, and each iteration costs one new
evaluation and shrinks the interval by $1/\varphi \approx 0.618$. Ternary search shrinks by $2/3$ per **two** evaluations,
i.e. $\sqrt{2/3} \approx 0.816$ per evaluation. Golden-section matters when $f$ is expensive (each evaluation is $O(n)$ or
itself a search); otherwise plain ternary search with 100 iterations is simpler and safe.

### 1.4 Meet in the middle: split, enumerate, combine

**Setting.** We search a product space $A \times B$ for pairs $(a, b)$ whose combined value $g(a) \oplus h(b)$ satisfies a
condition — typically "subset of $n \le 40$ items with sum $= x$, $\le S$, maximal modulo $m$, or closest to $T$". Brute
force over all $2^{40} \approx 1.1\cdot10^{12}$ subsets is hopeless.

**Key observation.** A subset of all items is a pair (subset of the first half, subset of the second half), and the
sum *decomposes*: $\text{sum} = s_A + s_B$. Enumerate the $2^{n/2} \approx 10^6$ sums of each half. The condition on a pair
is now a **one-dimensional query**: for a fixed $s_A$ we need $s_B = x - s_A$, or $s_B \le S - s_A$, or the largest $s_B$
below a bound. Sorting one list answers each query by binary search, and sorting both lets a single **two-pointer**
pass answer all of them: as $s_A$ increases, the threshold $S - s_A$ decreases, so the pointer into $B$ only moves left.
This is exactly two-sum ([two pointers](03-two-pointers-and-sliding-window.md)) on lists of size $2^{n/2}$.

**Generating sorted subset sums in $O(2^k)$.** Start with $L_0 = [0]$. Adding item $x$ turns a sorted list $L$ into
$\operatorname{merge}(L, L + x)$, which is sorted and twice as long; the total work is $\sum_{i \le k} 2^i = O(2^k)$ — no
$\log$ factor from sorting.

**Memory.** $2^{20}$ `long long` values are 8 MiB, so $n = 40$ is comfortable. $n = 46$ means $2^{23}$ values (64 MiB)
per half — tight. Then use an **unbalanced split**: store the sorted sums of $k$ items ($2^k$ memory) and enumerate the other
$n - k$ items by DFS, querying the stored list by binary search: time $O(2^k + 2^{n-k}\, k)$, memory $O(2^k)$.

**Why not a hash map?** Counting "pairs with $s_A + s_B = x$" through `unordered_map<long long,int>` with $10^6$ keys
means a heap-allocated node per key, random memory access (cache misses on every lookup), rehashing, and on
Codeforces a hackable hash. A sorted `vector` plus two pointers touches memory sequentially and is typically several
times faster. In Java it is worse: `HashMap<Long,Integer>` boxes every key and value and allocates a node per entry (on
the order of 50+ bytes per entry), so $10^6$ entries cost tens of MiB and heavy GC. Sorted primitive arrays are the default.

**4-sum.** "Count $(i, j, k, l)$ with $A_i + B_j + C_k + D_l = 0$" over four lists of size $n$: the $n^4$ brute force
becomes two lists of $n^2$ pair sums, $P = \{A_i + B_j\}$ and $Q = \{C_k + D_l\}$, and the count of $p + q = 0$ via sorting and
two pointers: $O(n^2 \log n)$ time, $O(n^2)$ memory. The same split solves "sum of four values" and many
"choose two pairs" problems.

**Other shapes of the same idea.** Meet in the middle works whenever a path or a choice sequence of length $d$ can
be cut at its midpoint and the two halves only interact through a small "interface": grid paths meeting on the
anti-diagonal ([CF 1006F](https://codeforces.com/problemset/problem/1006/F) — 2100), baby-step giant-step for discrete
logarithms ([number theory](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md)), maximum
independent set or clique on $n \le 40$ vertices, and bidirectional search.

### 1.5 Bidirectional BFS

In an implicit graph with branching factor $b$ and source–target distance $d$, BFS explores about $b^d$ states. Searching
from both ends and stopping when the frontiers meet explores about $2 b^{d/2}$ — the square root. Requirements: a single
known target, and the ability to generate **predecessors** (edges are reversible or the reverse moves are known). Rules
that keep it correct: expand **whole layers**, always the side with the smaller frontier; when a newly generated state
is already labelled by the other side, the answer is $\text{dist}_s + 1 + \text{dist}_t$ minimised over all meetings found
while finishing that layer (stopping at the first meeting can be off by one when layers are uneven). See
[BFS and DFS](../09-Graphs/01-graph-representation-bfs-dfs.md) for the plain version.

```text
fs = {s}, ft = {t}, ds[s] = 0, dt[t] = 0
while fs and ft are non-empty:
    if |fs| > |ft|: swap the roles of (fs, ds) and (ft, dt)
    next = {}, best = INF
    for u in fs: for v in neighbours(u):            # predecessors when expanding the target side
        if v in dt: best = min(best, ds[u] + 1 + dt[v])
        if v not in ds: ds[v] = ds[u] + 1, next.add(v)
    if best < INF: return best                      # only after the whole layer
    fs = next
return unreachable
```

## 2. Formulas, definitions and identities

| Item | Formula | Meaning / proof sketch |
|---|---|---|
| Ternary iterations | $t \ge \log(W/\varepsilon)/\log(3/2)$ | width shrinks by $2/3$ per iteration; $W = 2\cdot10^9,\ \varepsilon = 10^{-9}$ gives $t \approx 104$ |
| Golden-section evaluations | $t \ge \log(W/\varepsilon)/\log\varphi$, $\varphi = \frac{1+\sqrt5}{2}$ | one evaluation per step, factor $1/\varphi \approx 0.618$; same example: $\approx 88$ evaluations vs $\approx 208$ |
| Golden identities | $1/\varphi = \varphi - 1$, $\ 1/\varphi^2 = 1 - 1/\varphi$ | the reused probe lands exactly on the new golden point |
| Integer slope search | first $m$ with $f(m) \le f(m+1)$ | monotone for strictly unimodal or convex $f$; $\lceil\log_2 W\rceil$ steps, 2 evaluations each |
| Convexity | $f(\lambda a + (1-\lambda)b) \le \lambda f(a) + (1-\lambda) f(b)$ | closed under non-negative sums, max, affine substitution |
| Discrete convexity | $\Delta f(x) = f(x+1) - f(x)$ non-decreasing | a convex function restricted to integers is discretely convex |
| $\arg\min \sum_i \lvert x - a_i\rvert$ | any median of the $a_i$ | slope $= \#\{a_i < x\} - \#\{a_i > x\}$ changes sign at the median — no search needed |
| $\arg\min \sum_i w_i \lvert x - a_i\rvert$ | weighted median | same slope argument with weights |
| $\arg\min \sum_i (x - a_i)^2$ | mean $\bar a$ | derivative $2\sum (x - a_i) = 0$ |
| $\arg\min \max_i (t_i + \lvert x - x_i\rvert)$ | $\frac{1}{2}\bigl(\max_i (x_i + t_i) + \min_i (x_i - t_i)\bigr)$ | $f(x) = \max(P - x,\ Q + x)$ with $P = \max(x_i + t_i)$, $Q = \max(t_i - x_i)$; minimised where both are equal |
| MITM time | $O(2^{n/2})$ generation by merging + $O(2^{n/2})$ two-pointer combine | versus $O(2^n)$; with sorting instead of merging, $O(2^{n/2}\, n)$ |
| MITM memory | $2^{n/2}$ values per half | $n = 40$: $2^{20} \cdot 8$ B $= 8$ MiB per list |
| Unbalanced split | time $O(2^k + 2^{n-k} k)$, memory $O(2^k)$ | store the smaller half, DFS the larger one with binary search |
| Subsets with sum $\le S$ | $\sum_{a \in A} \lvert\{b \in B : b \le S - a\}\rvert$ | two pointers: $S - a$ decreases as $a$ increases |
| Subsets with sum $= x$ | $\sum_{v} \text{cnt}_A(v)\cdot \text{cnt}_B(x - v)$ | count equal runs on both sides |
| 4-sum | $O(n^2 \log n)$ time, $O(n^2)$ memory | pair sums $A + B$ and $C + D$, then two-sum |
| Bidirectional BFS | $\approx 2 b^{d/2}$ states instead of $b^d$ | two balls of radius $d/2$ |

## 3. Implementation (C++ and Java)

### 3.1 Ternary, golden-section and integer slope search (fragments)

```cpp
// Minimum of a strictly unimodal (or convex) function on reals: fixed iteration count, no eps loop.
template <class F> double ternaryMin(F f, double lo, double hi, int iters = 100) {
    for (int it = 0; it < iters; it++) {
        double m1 = lo + (hi - lo) / 3, m2 = hi - (hi - lo) / 3;
        if (f(m1) < f(m2)) hi = m2; else lo = m1;      // the dropped third never contains the only minimiser
    }
    return (lo + hi) / 2;
}
// Golden-section: one new evaluation per iteration.
template <class F> double goldenMin(F f, double lo, double hi, int iters = 100) {
    const double r = (sqrt(5.0) - 1) / 2;               // 1/phi
    double m1 = hi - r * (hi - lo), m2 = lo + r * (hi - lo), f1 = f(m1), f2 = f(m2);
    for (int it = 0; it < iters; it++) {
        if (f1 < f2) { hi = m2; m2 = m1; f2 = f1; m1 = hi - r * (hi - lo); f1 = f(m1); }
        else         { lo = m1; m1 = m2; f1 = f2; m2 = lo + r * (hi - lo); f2 = f(m2); }
    }
    return (lo + hi) / 2;
}
// Integer argmin of a strictly unimodal or convex f on [lo, hi]: first m with f(m) <= f(m+1).
template <class F> long long argminInt(F f, long long lo, long long hi) {
    while (lo < hi) {                                   // invariant: some minimiser lies in [lo, hi]
        long long m = lo + (hi - lo) / 2;               // overflow-safe midpoint
        if (f(m) <= f(m + 1)) hi = m; else lo = m + 1;
    }
    return lo;
}
```

```java
// Minimum of a strictly unimodal (or convex) function on reals.
static double ternaryMin(DoubleUnaryOperator f, double lo, double hi, int iters) {
    for (int it = 0; it < iters; it++) {
        double m1 = lo + (hi - lo) / 3, m2 = hi - (hi - lo) / 3;
        if (f.applyAsDouble(m1) < f.applyAsDouble(m2)) hi = m2; else lo = m1;
    }
    return (lo + hi) / 2;
}
static double goldenMin(DoubleUnaryOperator f, double lo, double hi, int iters) {
    final double r = (Math.sqrt(5.0) - 1) / 2;
    double m1 = hi - r * (hi - lo), m2 = lo + r * (hi - lo), f1 = f.applyAsDouble(m1), f2 = f.applyAsDouble(m2);
    for (int it = 0; it < iters; it++) {
        if (f1 < f2) { hi = m2; m2 = m1; f2 = f1; m1 = hi - r * (hi - lo); f1 = f.applyAsDouble(m1); }
        else         { lo = m1; m1 = m2; f1 = f2; m2 = lo + r * (hi - lo); f2 = f.applyAsDouble(m2); }
    }
    return (lo + hi) / 2;
}
// Integer argmin: first m in [lo, hi] with f(m) <= f(m+1).
static long argminInt(LongToDoubleFunction f, long lo, long hi) {
    while (lo < hi) {
        long m = lo + (hi - lo) / 2;
        if (f.applyAsDouble(m) <= f.applyAsDouble(m + 1)) hi = m; else lo = m + 1;
    }
    return lo;
}
```

For a **maximum**, flip the comparisons (or minimise $-f$). If $f$ is expensive, cache $f(m)$ and $f(m+1)$ — the
integer search evaluates both at every step. When $f$ is integer-valued, compare exactly; never compare doubles with
an `eps` inside the search unless you have a reason.

### 3.2 Meet in the middle: count subsets with sum at most $S$

Input: $n \le 40$ and $S$, then $n$ integers (any sign, $|a_i| \le 10^9$). Output: the number of subsets (including the
empty one) with sum $\le S$.

```cpp
#include <bits/stdc++.h>
using namespace std;
// All 2^k subset sums of v, sorted, in O(2^k): merge L with L + x for every item x.
vector<long long> sortedSums(const vector<long long>& v) {
    vector<long long> s = {0}, t;
    for (long long x : v) {
        size_t k = s.size(), i = 0, j = 0, o = 0;
        t.assign(2 * k, 0);
        while (i < k || j < k)
            t[o++] = (j == k || (i < k && s[i] <= s[j] + x)) ? s[i++] : s[j++] + x;
        swap(s, t);
    }
    return s;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; long long S; cin >> n >> S;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    vector<long long> A = sortedSums(vector<long long>(a.begin(), a.begin() + n / 2));
    vector<long long> B = sortedSums(vector<long long>(a.begin() + n / 2, a.end()));
    long long cnt = 0;
    int j = (int)B.size() - 1;
    for (long long x : A) {                             // x increases, so S - x decreases: j only moves left
        while (j >= 0 && x + B[j] > S) j--;
        cnt += j + 1;
    }
    cout << cnt << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long[] sortedSums(long[] v, int from, int to) {
        long[] s = {0};
        for (int p = from; p < to; p++) {
            long x = v[p]; int k = s.length, i = 0, j = 0, o = 0;
            long[] t = new long[2 * k];
            while (i < k || j < k) t[o++] = (j == k || (i < k && s[i] <= s[j] + x)) ? s[i++] : s[j++] + x;
            s = t;
        }
        return s;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(); long S = in.nextLong();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        long[] A = sortedSums(a, 0, n / 2), B = sortedSums(a, n / 2, n);
        long cnt = 0; int j = B.length - 1;
        for (long x : A) {
            while (j >= 0 && x + B[j] > S) j--;
            cnt += j + 1;
        }
        out.println(cnt);
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
4 5
1 2 3 4
out:
9
-->
<!-- test
in:
1 -1
-3
out:
1
-->
<!-- test
in:
3 0
-2 1 1
out:
5
-->
<!-- test
in:
40 1000000000000
1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000 1000000000
out:
1099511627776
-->

### 3.3 4-sum by pair sums: count $A_i + B_j + C_k + D_l = 0$

Input: $n$, then the four arrays (one per line). Output: the number of index quadruples. Pair sums are sorted
and combined by two pointers with equal-run counting.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<vector<long long>> v(4, vector<long long>(n));
    for (auto& row : v) for (auto& x : row) cin >> x;
    vector<long long> P, Q;
    P.reserve(1LL * n * n); Q.reserve(1LL * n * n);
    for (long long x : v[0]) for (long long y : v[1]) P.push_back(x + y);
    for (long long x : v[2]) for (long long y : v[3]) Q.push_back(x + y);
    sort(P.begin(), P.end()); sort(Q.begin(), Q.end());
    long long cnt = 0;
    long long i = 0, j = (long long)Q.size() - 1;
    while (i < (long long)P.size() && j >= 0) {
        long long s = P[i] + Q[j];
        if (s < 0) i++;
        else if (s > 0) j--;
        else {                                          // count both equal runs, multiply
            long long a = P[i], b = Q[j], ca = 0, cb = 0;
            while (i < (long long)P.size() && P[i] == a) i++, ca++;
            while (j >= 0 && Q[j] == b) j--, cb++;
            cnt += ca * cb;
        }
    }
    cout << cnt << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        long[][] v = new long[4][n];
        for (int r = 0; r < 4; r++) for (int i = 0; i < n; i++) v[r][i] = in.nextLong();
        long[] P = new long[n * n], Q = new long[n * n];
        for (int i = 0, t = 0; i < n; i++) for (int j = 0; j < n; j++, t++) { P[t] = v[0][i] + v[1][j]; Q[t] = v[2][i] + v[3][j]; }
        shuffle(P); shuffle(Q); Arrays.sort(P); Arrays.sort(Q);
        long cnt = 0; int i = 0, j = Q.length - 1;
        while (i < P.length && j >= 0) {
            long s = P[i] + Q[j];
            if (s < 0) i++;
            else if (s > 0) j--;
            else {
                long a = P[i], b = Q[j], ca = 0, cb = 0;
                while (i < P.length && P[i] == a) { i++; ca++; }
                while (j >= 0 && Q[j] == b) { j--; cb++; }
                cnt += ca * cb;
            }
        }
        out.println(cnt);
        out.flush();
    }
    static void shuffle(long[] a) {
        Random rnd = new Random();
        for (int i = a.length - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long t = a[i]; a[i] = a[j]; a[j] = t; }
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
2
1 -1
0 2
-1 1
3 0
out:
3
-->
<!-- test
in:
1
5
-2
-3
1
out:
0
-->
<!-- test
in:
3
0 0 0
0 0 0
0 0 0
0 0 0
out:
81
-->

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "choose a real $x$ (a position, a time, a shift) to minimise a cost", cost is a max/sum of distances or absolute values | prove convexity, then ternary search (or find the closed form: median, mean, midpoint) |
| integer parameter $k$, cost "first decreases then increases" and $f(k)$ is cheap | integer slope search on $f(k) \le f(k+1)$ |
| the cost needs an $O(n)$ evaluation and the answer is real | ternary with ~100 iterations: $O(100 \cdot n)$ |
| $n \le 40$ (or 35, 46) items, subset sums / products, target or modulus | meet in the middle: $2^{n/2}$ per half, sort, two pointers |
| $n \le 20$ | plain $2^n$ or [bitmask DP](../06-Dynamic-Programming/06-bitmask-dp.md) — no split needed |
| "four numbers / two pairs summing to $X$" with $n \le 1000$–$5000$ | pair sums, two-sum over them |
| grid paths of length $n + m$ with an XOR / sum condition, $n, m \le 20$ | split paths at the middle anti-diagonal |
| shortest sequence of reversible moves between two known states, huge state space | bidirectional BFS |

Often confused: **binary search on the answer** needs a monotone *feasibility* predicate, ternary search needs a
unimodal *cost*. If you can phrase the question as "is cost $\le c$ achievable?", binary search on $c$ is usually more robust.
Meet in the middle is not **DP**: it works when values are huge (sums up to $10^{18}$) and a DP over sums is impossible;
when the target is small ($\le 10^5$) a knapsack DP is simpler.

## 5. Worked examples (graded)

### Example 1 — Freefall  ·  ★ ≈1100 (est.)

- **Source:** [AtCoder ABC279 D · Freefall](https://atcoder.jp/contests/abc279/tasks/abc279_d)
- **Difficulty:** ≈1100 (est.)
- **Problem:** Given integers $1 \le A, B \le 10^{18}$, minimise $f(g) = B \cdot g + \dfrac{A}{\sqrt{g + 1}}$ over integers $g \ge 0$
  (in the story, $g$ operations of cost $B$ each make the fall take $A/\sqrt{g+1}$). Print the minimum (relative or absolute error $10^{-6}$).
- **Thinking from first principles:** Trying all $g$ fails: the optimum is near $(A/2B)^{2/3}$, up to $\sim 6\cdot10^{11}$.
  Calculus gives a real minimiser, but rounding it correctly is fiddly. Structure: $B g$ is linear and $A/\sqrt{g+1}$ is
  convex (second derivative $\frac{3}{4}A(g+1)^{-5/2} > 0$), so $f$ is convex and, restricted to integers, discretely convex.
  Search range: for $g > A/B$, $f(g) > Bg > A = f(0)$, so $g \in [0, \lfloor A/B \rfloor]$.

<details><summary>Solution</summary>

Integer slope search: the first $g$ with $f(g) \le f(g+1)$ is a minimiser (§1.2). About 60 iterations. Use `long double`
in C++; in Java `double` suffices because near the optimum $f$ is flat, so mis-ordering two nearly equal values costs
only rounding error. $O(\log(A/B))$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    long long A, B; cin >> A >> B;
    auto f = [&](long long g) { return (long double)B * g + (long double)A / sqrtl((long double)g + 1); };
    long long lo = 0, hi = A / B;                       // beyond A/B the linear term alone exceeds f(0) = A
    while (lo < hi) {
        long long m = lo + (hi - lo) / 2;
        if (f(m) <= f(m + 1)) hi = m; else lo = m + 1;  // discrete convexity: first non-negative slope
    }
    cout << fixed << setprecision(10) << (double)f(lo) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        long A = in.nextLong(), B = in.nextLong();
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        long lo = 0, hi = A / B;
        while (lo < hi) {
            long m = lo + (hi - lo) / 2;
            if (f(A, B, m) <= f(A, B, m + 1)) hi = m; else lo = m + 1;
        }
        out.printf("%.10f%n", f(A, B, lo));
        out.flush();
    }
    static double f(long A, long B, long g) { return (double) B * g + (double) A / Math.sqrt(g + 1.0); }
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
10 1
out:
7.7735026919
-->
<!-- test
in:
1 1000000000000000000
out:
1.0000000000
-->
<!-- test
in:
1000000000000000000 1
out:
1889881574841.3097
-->
<!-- test
in:
100 3
out:
55.7964473009
-->

</details>

### Example 2 — Meeting on the Line  ·  ★ 1600

- **Source:** [CF 1730B · Meeting on the Line](https://codeforces.com/problemset/problem/1730/B) — 1600
- **Difficulty:** 1600
- **Problem:** $t$ test cases. $n$ people stand at $x_i$ on a line ($0 \le x_i, t_i \le 10^8$, $\sum n \le 2\cdot10^5$). Person $i$
  needs $t_i$ to get ready and then walks at speed 1. Choose a meeting point $x_0$ minimising the time until everyone
  has arrived, $\max_i (t_i + |x_i - x_0|)$; print $x_0$ (it is unique; error $10^{-6}$ allowed).
- **Thinking from first principles:** Each term $t_i + |x_i - x_0|$ is a V-shape in $x_0$, and the maximum of convex functions
  is convex — so ternary search over $[0, 10^8]$ with 100 iterations of an $O(n)$ evaluation is correct: $2\cdot10^7$
  operations per $10^5$ people. Better still, write the maximum as $\max(P - x_0,\ Q + x_0)$ with $P = \max(x_i + t_i)$ and
  $Q = \max(t_i - x_i)$: one decreasing and one increasing line, minimised where they cross, $x_0 = (P - Q)/2$. Seeing the
  closed form *after* convexity is the usual pattern: convexity tells you a search works, the structure of the
  maximum tells you the search is unnecessary.

<details><summary>Solution</summary>

The programs below use the ternary search (the general tool); the hidden tests were computed from the closed form
$x_0 = \frac12(\max(x_i + t_i) + \min(x_i - t_i))$, which is the faster contest solution. The optimum lies in
$[\min x_i, \max x_i] \subseteq [0, 10^8]$ because moving outside the hull increases every distance. $f$ is strictly unimodal
(slopes $\pm 1$), so ties never occur at exact arithmetic. $O(100 \cdot n)$ per test.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int T; cin >> T;
    while (T--) {
        int n; cin >> n;
        vector<double> x(n), t(n);
        for (auto& v : x) { long long z; cin >> z; v = z; }   // integer input: cin >> double is slow on MinGW
        for (auto& v : t) { long long z; cin >> z; v = z; }
        auto f = [&](double p) { double m = 0; for (int i = 0; i < n; i++) m = max(m, t[i] + fabs(x[i] - p)); return m; };
        double lo = 0, hi = 1e8;
        for (int it = 0; it < 100; it++) {
            double m1 = lo + (hi - lo) / 3, m2 = hi - (hi - lo) / 3;
            if (f(m1) < f(m2)) hi = m2; else lo = m1;
        }
        cout << fixed << setprecision(7) << (lo + hi) / 2 << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int T = in.nextInt();
        while (T-- > 0) {
            int n = in.nextInt();
            double[] x = new double[n], t = new double[n];
            for (int i = 0; i < n; i++) x[i] = in.nextInt();
            for (int i = 0; i < n; i++) t[i] = in.nextInt();
            double lo = 0, hi = 1e8;
            for (int it = 0; it < 100; it++) {
                double m1 = lo + (hi - lo) / 3, m2 = hi - (hi - lo) / 3;
                if (f(x, t, m1) < f(x, t, m2)) hi = m2; else lo = m1;
            }
            out.printf("%.7f%n", (lo + hi) / 2);
        }
        out.flush();
    }
    static double f(double[] x, double[] t, double p) {
        double m = 0;
        for (int i = 0; i < x.length; i++) m = Math.max(m, t[i] + Math.abs(x[i] - p));
        return m;
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
2
0 10
0 0
3
1 4 9
5 0 1
1
100000000
7
out:
5.0000000
3.0000000
100000000.0000000
-->
<!-- test
in:
2
2
0 5
10 0
4
3 3 3 3
1 2 3 4
out:
0.0000000
3.0000000
-->

</details>

### Example 3 — Maximum Subsequence  ·  ★ 1800

- **Source:** [CF 888E · Maximum Subsequence](https://codeforces.com/problemset/problem/888/E) — 1800
- **Difficulty:** 1800
- **Problem:** $n \le 35$ integers $1 \le a_i \le 10^9$ and a modulus $1 \le m \le 10^9$. Choose a subset (possibly empty)
  maximising $(\sum a_i) \bmod m$.
- **Thinking from first principles:** $2^{35} \approx 3.4\cdot10^{10}$ subsets is too many; a DP over residues has $m$ up to
  $10^9$ states. The objective decomposes: a subset is a pair of half-subsets with residues $u, v \in [0, m)$, and the
  value is $(u + v) \bmod m$, which is $u + v$ if $u + v < m$ and $u + v - m$ otherwise. The "wrap-around" case is never
  better than taking $v = 0$ (the empty half-subset): $u + v - m < u$. So we want, for each $u$, the largest $v \le m - 1 - u$ —
  a sorted-list query, and since the bound decreases as $u$ grows, one two-pointer pass.

<details><summary>Solution</summary>

Enumerate residues of all subsets of each half ($2^{17}$ and $2^{18}$), sort both. Walk $u$ upward through the first list
while a pointer $j$ walks downward through the second until $B_j \le m - 1 - u$; candidate $u + B_j$. $B$ contains 0, so $j$
never falls off. $O(2^{n/2} \log 2^{n/2})$.

```cpp
#include <bits/stdc++.h>
using namespace std;
vector<long long> residues(const vector<long long>& v, long long m) {
    vector<long long> s = {0};
    for (long long x : v) { size_t k = s.size(); for (size_t i = 0; i < k; i++) s.push_back((s[i] + x) % m); }
    sort(s.begin(), s.end());
    return s;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; long long m; cin >> n >> m;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    auto A = residues(vector<long long>(a.begin(), a.begin() + n / 2), m);
    auto B = residues(vector<long long>(a.begin() + n / 2, a.end()), m);
    long long best = 0; int j = (int)B.size() - 1;
    for (long long u : A) {                             // bound m-1-u decreases as u increases
        while (B[j] > m - 1 - u) j--;                   // B[0] = 0 always satisfies the bound
        best = max(best, u + B[j]);
    }
    cout << best << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long[] residues(long[] a, int from, int to, long m) {
        long[] s = new long[1 << (to - from)];
        int k = 1;
        for (int p = from; p < to; p++) { for (int i = 0; i < k; i++) s[k + i] = (s[i] + a[p]) % m; k *= 2; }
        shuffle(s); Arrays.sort(s);
        return s;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(); long m = in.nextLong();
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        long[] A = residues(a, 0, n / 2, m), B = residues(a, n / 2, n, m);
        long best = 0; int j = B.length - 1;
        for (long u : A) {
            while (B[j] > m - 1 - u) j--;
            best = Math.max(best, u + B[j]);
        }
        out.println(best);
        out.flush();
    }
    static void shuffle(long[] a) {
        Random rnd = new Random();
        for (int i = a.length - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long t = a[i]; a[i] = a[j]; a[j] = t; }
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
3 10
4 5 8
out:
9
-->
<!-- test
in:
1 1
1000000000
out:
0
-->
<!-- test
in:
4 1000000000
999999999 999999999 999999999 2
out:
999999999
-->
<!-- test
in:
5 7
3 3 3 3 3
out:
6
-->

</details>

### Example 4 — Meet in the Middle (count subsets with a given sum)  ·  ★ ≈1900 (est.)

- **Source:** [CSES 1628 · Meet in the Middle](https://cses.fi/problemset/task/1628)
- **Difficulty:** ≈1900 (est.)
- **Problem:** $n \le 40$ weights $1 \le t_i \le 10^9$ and a target $1 \le x \le 10^9$. Count the subsets with sum exactly $x$.
- **Thinking from first principles:** The count can be as large as $\binom{40}{20} \approx 1.4\cdot10^{11}$, so even
  enumerating *solutions* is impossible — we must count pairs. Split into halves; a pair $(s_A, s_B)$ works iff
  $s_B = x - s_A$. With both lists sorted, walk $s_A$ up and $s_B$ down; when the sum matches, count the run of equal
  values on each side and add the product. Generating the lists by merging keeps the whole thing $O(2^{n/2})$: about
  $2\cdot10^6$ operations instead of $10^{12}$.

<details><summary>Solution</summary>

`sortedSums` from §3.2 for both halves; two pointers with equal-run counting (as in §3.3). Answer up to $2^{40}$: `long long`.
Memory $2 \cdot 2^{20}$ values plus a merge buffer, about 32 MiB in C++.

```cpp
#include <bits/stdc++.h>
using namespace std;
vector<long long> sortedSums(const vector<long long>& v) {
    vector<long long> s = {0}, t;
    for (long long x : v) {
        size_t k = s.size(), i = 0, j = 0, o = 0;
        t.assign(2 * k, 0);
        while (i < k || j < k) t[o++] = (j == k || (i < k && s[i] <= s[j] + x)) ? s[i++] : s[j++] + x;
        swap(s, t);
    }
    return s;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; long long x; cin >> n >> x;
    vector<long long> a(n);
    for (auto& v : a) cin >> v;
    auto A = sortedSums(vector<long long>(a.begin(), a.begin() + n / 2));
    auto B = sortedSums(vector<long long>(a.begin() + n / 2, a.end()));
    long long cnt = 0;
    long long i = 0, j = (long long)B.size() - 1;
    while (i < (long long)A.size() && j >= 0) {
        long long s = A[i] + B[j];
        if (s < x) i++;
        else if (s > x) j--;
        else {
            long long va = A[i], vb = B[j], ca = 0, cb = 0;
            while (i < (long long)A.size() && A[i] == va) i++, ca++;
            while (j >= 0 && B[j] == vb) j--, cb++;
            cnt += ca * cb;
        }
    }
    cout << cnt << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long[] sortedSums(long[] v, int from, int to) {
        long[] s = {0};
        for (int p = from; p < to; p++) {
            long x = v[p]; int k = s.length, i = 0, j = 0, o = 0;
            long[] t = new long[2 * k];
            while (i < k || j < k) t[o++] = (j == k || (i < k && s[i] <= s[j] + x)) ? s[i++] : s[j++] + x;
            s = t;
        }
        return s;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(); long x = in.nextLong();
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        long[] A = sortedSums(a, 0, n / 2), B = sortedSums(a, n / 2, n);
        long cnt = 0; int i = 0, j = B.length - 1;
        while (i < A.length && j >= 0) {
            long s = A[i] + B[j];
            if (s < x) i++;
            else if (s > x) j--;
            else {
                long va = A[i], vb = B[j], ca = 0, cb = 0;
                while (i < A.length && A[i] == va) { i++; ca++; }
                while (j >= 0 && B[j] == vb) { j--; cb++; }
                cnt += ca * cb;
            }
        }
        out.println(cnt);
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
5 6
1 2 3 4 5
out:
3
-->
<!-- test
in:
1 7
7
out:
1
-->
<!-- test
in:
6 3
1 1 1 1 1 1
out:
20
-->
<!-- test
in:
40 20
1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
out:
137846528820
-->

</details>

### Example 5 — Weakness and Poorness  ·  ★ 2000

- **Source:** [CF 578C · Weakness and Poorness](https://codeforces.com/problemset/problem/578/C) — 2000
- **Difficulty:** 2000
- **Problem:** An array of $n \le 2\cdot10^5$ integers with $|a_i| \le 10^4$. For a real $x$, the *weakness* of $a - x$
  (subtract $x$ from every element) is the maximum over all non-empty segments of the absolute value of the segment sum.
  Find the minimum possible weakness over all real $x$ (error $10^{-6}$).
- **Thinking from first principles:** For a fixed $x$ the weakness is easy: with prefix sums $S_0 = 0$,
  $S_j = \sum_{i \le j}(a_i - x)$, every segment sum is $S_j - S_i$, so the weakness is $\max_j S_j - \min_j S_j$ — $O(n)$.
  As a function of $x$, each segment contributes $|\text{sum} - x\cdot\text{len}|$: the absolute value of an affine
  function, which is convex. The maximum of convex functions is convex, so weakness$(x)$ is convex and ternary search
  applies. Range: for $x \le \min a$ every element is $\ge 0$ and the weakness is the total sum, which decreases as $x$
  rises; symmetrically above $\max a$; so the optimum is in $[-10^4, 10^4]$. Precision budget: the slope of the weakness
  is at most $n$, so an $x$-error of $10^{-12}$ costs at most $2\cdot10^{-7}$; 100 iterations shrink $2\cdot10^4$ to
  about $5\cdot10^{-14}$.

<details><summary>Solution</summary>

Ternary search over $x$ with 100 iterations; each evaluation is one prefix-sum pass, so the total is 200 passes,
about $4\cdot10^7$ operations. C++ uses `long double`; Java `double` is enough because partial sums are bounded by the answer itself
($|S_j - S_0| \le$ weakness), so rounding error is relative to the answer.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<long double> a(n);
    for (auto& v : a) { long long z; cin >> z; v = z; }       // read integers, convert: much faster than cin >> long double
    auto weakness = [&](long double x) {
        long double s = 0, mx = 0, mn = 0;              // prefix sums of a_i - x, including S_0 = 0
        for (int i = 0; i < n; i++) { s += a[i] - x; mx = max(mx, s); mn = min(mn, s); }
        return mx - mn;
    };
    long double lo = -1e4, hi = 1e4;
    for (int it = 0; it < 100; it++) {
        long double m1 = lo + (hi - lo) / 3, m2 = hi - (hi - lo) / 3;
        if (weakness(m1) < weakness(m2)) hi = m2; else lo = m1;
    }
    cout << fixed << setprecision(9) << (double)weakness((lo + hi) / 2) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        double[] a = new double[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        double lo = -1e4, hi = 1e4;
        for (int it = 0; it < 100; it++) {
            double m1 = lo + (hi - lo) / 3, m2 = hi - (hi - lo) / 3;
            if (weakness(a, m1) < weakness(a, m2)) hi = m2; else lo = m1;
        }
        out.printf("%.9f%n", weakness(a, (lo + hi) / 2));
        out.flush();
    }
    static double weakness(double[] a, double x) {
        double s = 0, mx = 0, mn = 0;
        for (double v : a) { s += v - x; if (s > mx) mx = s; if (s < mn) mn = s; }
        return mx - mn;
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
1
-7
out:
0.000000000
-->
<!-- test
in:
2
0 10
out:
5.000000000
-->
<!-- test
in:
4
3 -1 4 -1
out:
2.500000000
-->
<!-- test
in:
3
10000 10000 10000
out:
0.000000000
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Prove unimodality before you search.** "It looks like a valley in the samples" is how ternary search WAs happen.
   Convexity via closure rules (sum, max, $|{\cdot}|$, affine substitution) is the usual proof; a product or a minimum
   of convex functions is a red flag.
2. **Plateaus away from the optimum are fatal; at the optimum they are harmless** (for convex $f$). Integer-valued
   functions built with `ceil`/`floor` (e.g. $x + \lceil d/x \rceil$) often have staircase plateaus — check them by brute
   force on small values, or iterate over a neighbourhood of the real optimum instead.
3. **Fixed iteration counts, not `while (hi - lo > eps)`.** With large coordinates, `eps` below the floating spacing never
   terminates; 100 iterations cover any double range.
4. **Integer ternary = binary search on $f(m) \le f(m+1)$.** It avoids the "shrink until 3 elements remain, then scan" code
   and its off-by-ones; use `lo + (hi - lo) / 2` for overflow safety on 64-bit ranges.
5. **Don't ternary-search when a closed form exists:** median for $\sum|x - a_i|$, mean for $\sum (x-a_i)^2$, midpoint
   $\frac12(\max(x_i+t_i) + \min(x_i - t_i))$ for $\max(t_i + |x - x_i|)$. Search is the fallback.
6. **Ternary on reals costs $\sim 200$ evaluations.** If one evaluation is $O(n \log n)$ with $n = 2\cdot10^5$, that is
   $\sim 7\cdot10^8$ — consider golden-section (half the evaluations) or binary search on the derivative sign if the
   derivative is cheap.
7. **Meet in the middle: sort, don't hash.** Sorted arrays and two pointers beat `unordered_map` by a large constant and
   cannot be anti-hash hacked; in Java avoid `HashMap<Long,…>` boxing for $10^6$ keys.
8. **Count, don't enumerate, solutions.** The number of matching pairs can exceed $10^{11}$; multiply the sizes of equal runs.
9. **Odd $n$:** put $\lfloor n/2 \rfloor$ items in one half and the rest in the other; a list of $2^{0} = 1$ element (the empty
   sum) is a valid half, so $n = 1$ works without special cases.
10. **Merge-generation needs a second buffer** of the same size; allocate once and swap (C++ `swap`) instead of reallocating
    in a loop when memory is tight.
11. **Java `Arrays.sort(long[])` on $2^{20}$ adversarial values** can degrade; shuffle first, or generate sorted lists by
    merging so no sort is needed.
12. **Reading floating-point input with `cin` is slow on MinGW** (the Windows toolchain Codeforces uses): $4\cdot10^5$
    `cin >> double` took about 1.2 s in our tests versus 0.2 s for the same numbers read as integers. When the input is
    integral, read `long long` and convert; otherwise read tokens and use `strtod`. Java's `Double.parseDouble` on tokens is fine.
13. **Bidirectional BFS:** finish the layer before answering, and expand the smaller frontier; generating predecessors
    must be exact (for non-reversible moves, write the inverse moves explicitly).

## 7. Going further (toward 2400–2600+)

- **Ternary search inside other searches:** binary search on the answer with a ternary search in the check, or nested
  ternary search for jointly convex 2D costs ([LC 1515](https://leetcode.com/problems/best-position-for-a-service-centre/) is the
  interview version; geometric minimax problems such as [CF 1059D](https://codeforces.com/problemset/problem/1059/D) — 2200 —
  where the needed radius as a function of the centre's $x$ is a maximum of parabolas).
- **Convexity as structure, not just search:** convex cost functions are what make
  [slope trick](../07-DP-Optimizations/07-slope-trick.md) and the [Aliens trick](../07-DP-Optimizations/06-aliens-trick-wqs-binary-search.md)
  work; the "concave in $k$" proof for WQS binary search is the same kind of argument as §1.2.
- **Meet in the middle on graphs:** maximum independent set / clique for $n \le 40$ (split vertices, SOS DP over one half —
  see [SOS DP](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md)), $3^{n/2}$ splits where each item has three
  options ([CF 585D](https://codeforces.com/problemset/problem/585/D) — 2300), and products instead of sums with a binary
  search on the answer ([CF 912E](https://codeforces.com/problemset/problem/912/E) — 2400).
- **Randomised meet in the middle:** birthday-paradox collisions (two random walks of $\sqrt{N}$ steps meet with
  constant probability) — [CF 995E](https://codeforces.com/problemset/problem/995/E) — 2700; see
  [randomized algorithms](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md).
- **Baby-step giant-step** is meet in the middle on exponents: $a^{im} = b \cdot a^{-j}$ ([discrete log](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md)).
- **Bitset speed-ups** for the combine step when the condition is a set intersection ([bitset optimisation](../16-IGM-Frontier/05-bitset-optimization.md)).

## 8. Practice ladder

**≤ 1400**
- [ ] [CF 1978B · New Bakery](https://codeforces.com/problemset/problem/1978/B) — 800
- [ ] [CF 2009E · Klee's SUPER DUPER LARGE Array!!!](https://codeforces.com/problemset/problem/2009/E) — 1400
- [ ] [CF 289B · Polo the Penguin and Matrix](https://codeforces.com/problemset/problem/289/B) — 1400

**1400–1700**
- [ ] [CF 1301B · Motarack's Birthday](https://codeforces.com/problemset/problem/1301/B) — 1500
- [ ] [CF 1933E · Turtle vs. Rabbit Race: Optimal Trainings](https://codeforces.com/problemset/problem/1933/E) — 1500
- [ ] [AtCoder ABC184 F · Programming Contest](https://atcoder.jp/contests/abc184/tasks/abc184_f) — subset sums of 40 items, best $\le T$
- [ ] [AtCoder ABC271 F · XOR on Grid Path](https://atcoder.jp/contests/abc271/tasks/abc271_f) — meet on the anti-diagonal
- [ ] [CF 439D · Devu and his Brother](https://codeforces.com/problemset/problem/439/D) — 1700
- [ ] [CF 1479A · Searching Local Minimum](https://codeforces.com/problemset/problem/1479/A) — 1700

**1700–1900**
- [ ] [CF 939E · Maximize!](https://codeforces.com/problemset/problem/939/E) — 1800
- [ ] [CSES 1642 · Sum of Four Values](https://cses.fi/problemset/task/1642) — pair sums, keep indices distinct
- [ ] [CF 613A · Peter and Snow Blower](https://codeforces.com/problemset/problem/613/A) — 1900

**1900–2100**
- [ ] [CF 1006F · Xor-Paths](https://codeforces.com/problemset/problem/1006/F) — 2100
- [ ] [CF 525E · Anya and Cubes](https://codeforces.com/problemset/problem/525/E) — 2100
- [ ] [CF 1355E · Restorer Distance](https://codeforces.com/problemset/problem/1355/E) — 2100

**2100–2400**
- [ ] [CF 1105E · Helping Hiasat ](https://codeforces.com/problemset/problem/1105/E) — 2200
- [ ] [CF 1059D · Nature Reserve](https://codeforces.com/problemset/problem/1059/D) — 2200
- [ ] [CF 585D · Lizard Era: Beginning](https://codeforces.com/problemset/problem/585/D) — 2300
- [ ] [CF 912E · Prime Gift](https://codeforces.com/problemset/problem/912/E) — 2400
- [ ] [CF 1257F · Make Them Similar](https://codeforces.com/problemset/problem/1257/F) — 2400

**2400+**
- [ ] [CF 1767E · Algebra Flash](https://codeforces.com/problemset/problem/1767/E) — 2500
- [ ] [CF 839E · Mother of Dragons](https://codeforces.com/problemset/problem/839/E) — 2700
- [ ] [CF 995E · Number Clicker](https://codeforces.com/problemset/problem/995/E) — 2700

## 9. LeetCode / FAANG cross-reference

Ternary search itself is rare in interviews; its integer form appears as "find the peak" binary search. Meet in the
middle shows up in a handful of Hard problems with $n \le 40$; bidirectional BFS is a common follow-up to word-ladder
style questions.

- [LC 852 · Peak Index in a Mountain Array](https://leetcode.com/problems/peak-index-in-a-mountain-array/) — Medium — slope binary search: first $i$ with $a_i > a_{i+1}$.
- [LC 162 · Find Peak Element](https://leetcode.com/problems/find-peak-element/) — Medium — same predicate; works because a local peak always exists on the rising side.
- [LC 1095 · Find in Mountain Array](https://leetcode.com/problems/find-in-mountain-array/) — Hard — slope search for the peak, then two monotone binary searches.
- [LC 2448 · Minimum Cost to Make Array Equal](https://leetcode.com/problems/minimum-cost-to-make-array-equal/) — Hard — convex $\sum c_i|x - a_i|$: ternary search or weighted median.
- [LC 1515 · Best Position for a Service Centre](https://leetcode.com/problems/best-position-for-a-service-centre/) — Hard — jointly convex sum of distances: nested ternary search.
- [LC 454 · 4Sum II](https://leetcode.com/problems/4sum-ii/) — Medium — §3.3 exactly.
- [LC 18 · 4Sum](https://leetcode.com/problems/4sum/) — Medium — sort + two pointers inside two loops (pair-sum idea with dedupe).
- [LC 1755 · Closest Subsequence Sum](https://leetcode.com/problems/closest-subsequence-sum/) — Hard — MITM, closest pair sum by two pointers.
- [LC 2035 · Partition Array Into Two Arrays to Minimize Sum Difference](https://leetcode.com/problems/partition-array-into-two-arrays-to-minimize-sum-difference/) — Hard — MITM grouped by how many items each half takes.
- [LC 805 · Split Array With Same Average](https://leetcode.com/problems/split-array-with-same-average/) — Hard — shift values by the mean, then MITM for a zero-sum proper subset.
- [LC 127 · Word Ladder](https://leetcode.com/problems/word-ladder/) — Hard — bidirectional BFS.
- [LC 752 · Open the Lock](https://leetcode.com/problems/open-the-lock/) — Medium — bidirectional BFS on $10^4$ states.

## 10. Self-check

1. State strict unimodality and prove that ternary search never discards the minimiser.
2. Give a weakly unimodal array on which ternary search returns the wrong maximum, and explain why no algorithm can
   fix it with few probes.
3. Why does ternary search remain correct for a convex function with a flat bottom?
4. Write the integer version as a binary search. Which predicate, and why is it monotone?
5. Why does golden-section search need only one new evaluation per iteration? What is its shrink factor per
   evaluation compared with ternary search?
6. For $n = 40$ items, describe how to count subsets with sum $\le S$ in $O(2^{20})$ after generation, and how to generate
   the sorted sums without sorting.
7. In CF 888E, why is it enough to pair each residue $u$ with the largest $v \le m - 1 - u$, ignoring pairs that wrap past $m$?
8. When should you prefer an unbalanced split, and what are its time and memory costs?

<details><summary>Answers</summary>

1. There is $x^*$ with $f$ strictly decreasing on $[l, x^*]$ and strictly increasing on $[x^*, r]$. If $f(m_1) < f(m_2)$ and
   $x^* \ge m_2$, both probes are on the decreasing side, so $f(m_1) > f(m_2)$, contradiction; hence $x^* < m_2$ and
   $(m_2, r]$ is safe to drop. Symmetric for $>$; equality forces $m_1 < x^* < m_2$.
2. $(0,0,0,0,0,0,0,5,0)$ with probes 2 and 5: equal values, and dropping the right third loses index 7. An adversary
   answering 0 to every probe can place the 5 at any unprobed index, so $\Theta(n)$ probes are necessary.
3. For convex $f$, $f(m_1) \le f(m_2)$ implies $f(x) \ge f(m_2)$ for all $x > m_2$, so the dropped part contains no value
   below one we keep; flatness can only occur at the minimum level.
4. Find the first $m$ with $f(m) \le f(m+1)$. For strictly unimodal or discretely convex $f$, the forward difference is
   negative before the minimiser and non-negative from it on, so the predicate is false…false, true…true.
5. With probes at the golden ratio, after discarding one side the surviving probe sits exactly at the new golden point
   ($1/\varphi^2 = 1 - 1/\varphi$). Factor $1/\varphi \approx 0.618$ per evaluation versus $\sqrt{2/3} \approx 0.816$.
6. Generate each half's sums sorted by repeatedly merging $L$ with $L + x$ ($O(2^{20})$ total). Then for $a$ in $A$
   ascending, move a pointer down $B$ while $a + B_j > S$ and add $j + 1$.
7. For residues $u, v < m$, a wrapping pair gives $u + v - m < u$, while pairing $u$ with $v = 0$ (the empty subset of
   the other half) gives $u$. So wrapping pairs never win.
8. When $2^{n/2}$ values per list do not fit in memory (e.g. $n \ge 46$). Store sorted sums of $k$ items and DFS the other
   $n - k$ with a binary search each: time $O(2^k + 2^{n-k} k)$, memory $O(2^k)$.

</details>
