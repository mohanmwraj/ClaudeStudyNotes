# Binary search and binary search on the answer

> **Band:** 🟢–🟣 1000–2100 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [complexity and constraint reading](../01-Foundations/01-complexity-and-constraint-reading.md), [STL and Java collections](../01-Foundations/02-cpp-stl-and-java-collections.md), [prefix sums](01-prefix-sums-and-difference-arrays.md)
> **You can say you know this when:** you write a correct binary search of any flavour in under a minute by stating its invariant first; you turn "minimise the maximum", "k-th smallest" and "maximise a ratio" statements into a monotone predicate and can *prove* the monotonicity; and you never get bitten by `Arrays.binarySearch` on duplicates, by `std::lower_bound` on a `std::set`, or by an epsilon loop that never ends.

## 1. First principles — why this works

**Every binary search finds the boundary of a monotone predicate.** Let $p$ be a predicate on the integers $L..R$ that is
*monotone*: it is false up to some point and true from then on ($F\,F\,\dots F\,T\,T\dots T$). We want the first true
position. Asking $p$ at one point $x$ tells us which side of the boundary $x$ is on, and that is all a comparison can tell us —
so the best strategy is to ask in the middle of what is still unknown, which halves the unknown part each time.

**The invariant formulation.** Keep two positions with
$$p(lo)=\text{false},\qquad p(hi)=\text{true},$$
where $lo=L-1$ and $hi=R+1$ are *virtual* sentinels that are never evaluated (pretend $p(L-1)=F$, $p(R+1)=T$).
While $hi-lo>1$, take any $mid$ strictly between them, evaluate $p(mid)$, and replace $hi$ by $mid$ if it is true, $lo$ by
$mid$ if it is false. Three facts make this correct:

1. *The invariant is preserved* — by construction of the update.
2. *It terminates*: $mid$ is strictly inside $(lo,hi)$, so $hi-lo$ strictly decreases (and roughly halves); the loop stops
   when $hi=lo+1$, after $\lceil\log_2(R-L+2)\rceil$ evaluations.
3. *The answer is $hi$*: at the end $p(lo)=F$ and $p(lo+1)=p(hi)=T$, so by monotonicity everything $\le lo$ is false and $hi$
   is the first true position. If $hi=R+1$, no position is true; if $lo=L-1$, all are true. Sentinels make these edge cases free.

Because $mid$ is never a sentinel, the predicate is only ever evaluated inside $[L,R]$. Write this one form for everything and the
famous off-by-one bugs disappear: there is no `<=` versus `<`, no `mid+1`, no "return −1 if not found" special case.

**Sorted arrays are just one predicate.** In a sorted array, $p(i)=[a_i\ge x]$ is monotone; its first true index is
`lower_bound(x)`. With $p(i)=[a_i>x]$ it is `upper_bound(x)`. The number of copies of $x$ is `upper_bound − lower_bound`; the
last element $\le x$ sits at `upper_bound − 1`; the last element $<x$ at `lower_bound − 1`.

**Binary search on the answer.** Many optimisation problems ask for the smallest $T$ such that something is achievable:
"minimum time to finish", "minimise the largest group", "maximise the minimum gap" (largest $T$ that works). Define
$\text{feasible}(T)$. If you can prove
$$\text{feasible}(T)\Rightarrow\text{feasible}(T+1)$$
then the predicate is monotone and the answer is its first true point. The proof is almost always "a witness for $T$ is also a
witness for $T+1$": a schedule that finishes by time $T$ also finishes by $T+1$; groups of size $\le T$ are also of size $\le T+1$.
The payoff is that the *decision* question is usually much easier than the optimisation (often a greedy check in $O(n)$), and you
pay only a $\log(\text{range})$ factor. When the "witness" argument fails, the predicate may not be monotone — e.g. "split into
*exactly* $k$ groups each of sum $\le T$" is monotone only because a group can always be split further; check such details.

**k-th smallest via counting.** For a multiset $S$ that is too large to list (all $n\cdot m$ products $i\cdot j$, all
$\binom n2$ pairwise distances), let $c(x)=\#\{s\in S: s\le x\}$. It is non-decreasing in $x$, so the $k$-th smallest element is
$$\min\{x : c(x)\ge k\},$$
a first-true search over *values*. The result is always an element of $S$: if $x^*$ is the first value with $c(x^*)\ge k$ then
$c(x^*-1)<k\le c(x^*)$, so some element equals $x^*$. Total cost: $\log(\text{value range})$ times the cost of counting, and counting
is usually a linear sweep (§2).

**Real numbers.** The invariant is unchanged; only the stopping rule differs, because $hi-lo>1$ makes no sense. Run a **fixed
number of iterations**: each halves the interval, so 100 iterations shrink it by $2^{100}\approx10^{30}$ — more than any range
needs — and once the interval is a single floating-point step, $mid$ equals an endpoint and further iterations are harmless.
A `while (hi - lo > eps)` loop, by contrast, never ends if `eps` is smaller than the spacing of doubles near the answer
(about $1.2\cdot10^{-7}$ near $10^9$): $mid$ rounds to $lo$ or $hi$ and nothing changes.

**Fractional programming.** To maximise a ratio $R(S)=\frac{\sum_{i\in S}a_i}{\sum_{i\in S}b_i}$ ($b_i>0$) over feasible sets
$S$, do not attack the ratio directly. For a guess $\lambda$,
$$\max_S R(S)\ge\lambda\iff \exists S:\ \sum_{i\in S}(a_i-\lambda b_i)\ge0 \iff F(\lambda):=\max_S\sum_{i\in S}(a_i-\lambda b_i)\ge0,$$
by multiplying through by the positive $\sum b$. The right side is a *plain* maximum-sum problem with weights $a_i-\lambda b_i$
(top $k$ items, max-weight path, MST, ...). $F$ is decreasing in $\lambda$, so binary search on $\lambda$. Even better, $F$ is the
maximum of lines with negative slopes $-\sum_S b$, hence convex and piecewise linear, and Newton's method on it is
**Dinkelbach's algorithm**: $\lambda_{t+1}=R(S_t)$ where $S_t$ is the maximiser at $\lambda_t$. It converges in a handful of
iterations and, with integer data, gives the *exact* optimum.

## 2. Formulas, definitions and identities

**Iteration counts.** Integer search over $N$ candidates: $\lceil\log_2(N+1)\rceil$ evaluations ($\le 31$ for $N\le2\cdot10^9$,
$\le 61$ for $N\le2\cdot10^{18}$). Real search on $[L,R]$ to absolute error $\varepsilon$: $\lceil\log_2((R-L)/\varepsilon)\rceil$
iterations (range $10^9$, $\varepsilon=10^{-9}$: 60).

**Safe midpoint.** $mid=lo+\lfloor(hi-lo)/2\rfloor$ cannot overflow when $hi-lo$ fits, and it rounds toward $lo$ even for negative
numbers because $hi-lo\ge0$. By contrast $(lo+hi)/2$ overflows `int` near $2^{31}$ and, in both C++ and Java, `/` truncates toward zero,
so for negative sums it rounds *up*: $lo=-3,\ hi=-2$ gives $(lo+hi)/2=-2=hi$. `(lo+hi)>>1` floors (arithmetic shift; guaranteed in
C++20 and Java). Java's `(lo+hi)>>>1` is correct for non-negative `int`s even when the sum overflows (the JDK uses it), wrong for
negatives. C++20 also has `std::midpoint(lo, hi)`.

In the $hi-lo>1$ form *any* rounding is safe: with $d=hi-lo\ge2$, $\lfloor d/2\rfloor\ge1$ and $\lceil d/2\rceil\le d-1$, so $mid$ is
strictly inside. Rounding matters only in the closed-interval forms below.

**Off-by-one taxonomy.**

| Form | Invariant | Init | Loop | Update | Result | Trap |
|---|---|---|---|---|---|---|
| first true (recommended) | $p(lo)=F,\ p(hi)=T$ | $lo=L-1,\ hi=R+1$ | `hi - lo > 1` | `p(mid) ? hi = mid : lo = mid` | `hi` ($=R+1$: none) | none |
| last true | $p(lo)=T,\ p(hi)=F$ (pred $T..TF..F$) | $lo=L-1,\ hi=R+1$ | `hi - lo > 1` | `p(mid) ? lo = mid : hi = mid` | `lo` ($=L-1$: none) | none |
| closed, floor mid | answer in $[lo,hi]$ | $lo=L,\ hi=R+1$ | `lo < hi` | `p(mid) ? hi = mid : lo = mid + 1` | `lo` | mid must round **down** |
| closed, ceil mid | answer in $[lo,hi]$ (last true) | $lo=L-1,\ hi=R$ | `lo < hi` | `p(mid) ? lo = mid : hi = mid - 1` | `lo` | mid must round **up**: `lo + (hi - lo + 1) / 2` |
| "found it" search | $x$ in $a[lo..hi]$ if anywhere | $lo=0,\ hi=n-1$ | `lo <= hi` | `==` return; `<` / `>` move past mid | index or −1 | only finds *some* copy |
| reals | $p(lo)=F,\ p(hi)=T$ | bounds | 100 iterations | as first true | `hi` | never `while (hi - lo > eps)` with tiny eps |

**Library semantics (sorted range, value $x$).**

| Meaning | C++ | Java |
|---|---|---|
| first index with $a_i\ge x$ | `lower_bound(a.begin(), a.end(), x)` | own `lowerBound` (§3.1); `Arrays.binarySearch` is *not* this |
| first index with $a_i>x$ | `upper_bound(...)` | own `upperBound` |
| first index where a predicate stops holding | `partition_point(b, e, pred)` (pred true then false) | own loop |
| count of $x$ | `upper_bound − lower_bound`, or `equal_range` | `upperBound − lowerBound` |
| largest key $\le x$ / $<x$ in an ordered set | `prev(s.upper_bound(x))` / `prev(s.lower_bound(x))`, check `!= s.begin()` | `floorKey(x)` / `lowerKey(x)` (TreeMap), `floor` / `lower` (TreeSet) |
| smallest key $\ge x$ / $>x$ | `s.lower_bound(x)` / `s.upper_bound(x)`, check `!= s.end()` | `ceilingKey(x)` / `higherKey(x)`; `ceiling` / `higher` |

`Arrays.binarySearch(a, x)` and `Collections.binarySearch(list, x)` return *an* index of $x$ if present — with duplicates, **no
guarantee which one** — and otherwise $-(\text{ins})-1$ where $\text{ins}$ is the insertion point (the lower bound, possibly
$n$). Recover it as `ins = -r - 1` (equivalently `~r`). They require a sorted range; on unsorted data the result is undefined.
`Collections.binarySearch` on a `LinkedList` walks the list ($O(n)$ steps). TreeMap/TreeSet navigation methods return `null` when
no key qualifies — unboxing `null` into an `int` throws.

**Counting functions for k-th searches.**

- Multiplication table $n\times m$ (entries $i\cdot j$): $c(x)=\sum_{i=1}^{n}\min\!\big(m,\lfloor x/i\rfloor\big)$, $O(\min(n,m))$.
- Pairwise distances of sorted $a$: $c(d)=\#\{i<j: a_j-a_i\le d\}$. For each $j$ the smallest valid $i$ is non-decreasing in $j$,
  so two pointers give $O(n)$.
- Matrix with sorted rows and columns: $c(x)$ by walking a staircase from the bottom-left corner — move right while
  $A_{r,c}\le x$ (adding $r+1$ entries of that column), otherwise move up: $O(n+m)$. The same staircase from the top-right
  decides "is $x$ present?" in $O(n+m)$.
- Two sorted arrays, $k$-th of all sums $a_i+b_j$: $c(x)=\sum_i\#\{j: b_j\le x-a_i\}$, two pointers $O(n+m)$.

Overall cost: $O(\text{count}\cdot\log V)$ where $V$ is the value range.

**Fractional programming.** With $F(\lambda)=\max_S\sum_{i\in S}(a_i-\lambda b_i)$ and $R^*=\max_S R(S)$:

- $F$ is a maximum of lines $\lambda\mapsto A_S-\lambda B_S$ with $B_S>0$: convex, piecewise linear, strictly decreasing.
- $F(\lambda)>0\iff\lambda<R^*$, $\ F(R^*)=0$, $\ F(\lambda)<0\iff\lambda>R^*$.
- Dinkelbach: $S_t=\arg\max_S\sum(a-\lambda_t b)$, $\ \lambda_{t+1}=A_{S_t}/B_{S_t}$. This is Newton's step
  $\lambda_t-F(\lambda_t)/F'(\lambda_t)$ with $F'(\lambda_t)=-B_{S_t}$. If $F(\lambda_t)>0$ then $\lambda_{t+1}>\lambda_t$; if
  $F(\lambda_t)=0$ then $\lambda_t=R^*$. Starting from $\lambda_0=0$ (or any feasible ratio) the sequence strictly increases through
  ratios of distinct sets, so it terminates; in practice in fewer than ~10 iterations.

**Complexities.** `lower_bound` on a vector: $O(\log n)$. `std::lower_bound` on `set`/`map` iterators: $O(n)$ (iterators are not
random access) — always use the member `s.lower_bound(x)`. TreeMap navigation: $O(\log n)$. Binary search on answer: $O(C\log V)$
where $C$ is the check cost.

## 3. Implementation (C++ and Java)

### 3.1 Generic searches, real search and Java lower/upper bound (fragments)

```cpp
// pred is monotone F..F T..T on (lo, hi); pred(lo) treated as false and pred(hi) as true (never evaluated).
// Returns the first true position, or hi if none inside.
template <class F> ll firstTrue(ll lo, ll hi, F pred) {
    while (hi - lo > 1) {
        ll mid = lo + (hi - lo) / 2;
        (pred(mid) ? hi : lo) = mid;
    }
    return hi;
}
// pred is T..T F..F; returns the last true position, or lo if none inside.
template <class F> ll lastTrue(ll lo, ll hi, F pred) {
    while (hi - lo > 1) {
        ll mid = lo + (hi - lo) / 2;
        (pred(mid) ? lo : hi) = mid;
    }
    return lo;
}
// reals: fixed iteration count instead of an epsilon test
template <class F> double firstTrueReal(double lo, double hi, F pred, int iters = 100) {
    for (int it = 0; it < iters; it++) {
        double mid = (lo + hi) / 2;
        (pred(mid) ? hi : lo) = mid;
    }
    return hi;
}
// staircase in a matrix with sorted rows and columns: how many entries are <= x, O(n + m)
ll countLE(const vector<vector<ll>>& A, ll x) {
    int n = A.size(), m = A[0].size(), r = n - 1, c = 0;
    ll cnt = 0;
    while (r >= 0 && c < m) {
        if (A[r][c] <= x) { cnt += r + 1; c++; }     // whole column c above row r is <= x
        else r--;
    }
    return cnt;
}
```

```java
static long firstTrue(long lo, long hi, LongPredicate pred) {
    while (hi - lo > 1) {
        long mid = lo + (hi - lo) / 2;
        if (pred.test(mid)) hi = mid; else lo = mid;
    }
    return hi;
}
static long lastTrue(long lo, long hi, LongPredicate pred) {
    while (hi - lo > 1) {
        long mid = lo + (hi - lo) / 2;
        if (pred.test(mid)) lo = mid; else hi = mid;
    }
    return lo;
}
static double firstTrueReal(double lo, double hi, DoublePredicate pred) {
    for (int it = 0; it < 100; it++) {
        double mid = (lo + hi) / 2;
        if (pred.test(mid)) hi = mid; else lo = mid;
    }
    return hi;
}
// C++ lower_bound / upper_bound for a sorted int[]; Arrays.binarySearch cannot replace these with duplicates
static int lowerBound(int[] a, int x) {
    int lo = -1, hi = a.length;                     // a[lo] < x <= a[hi] (virtual sentinels)
    while (hi - lo > 1) { int mid = (lo + hi) >>> 1; if (a[mid] >= x) hi = mid; else lo = mid; }
    return hi;
}
static int upperBound(int[] a, int x) {
    int lo = -1, hi = a.length;
    while (hi - lo > 1) { int mid = (lo + hi) >>> 1; if (a[mid] > x) hi = mid; else lo = mid; }
    return hi;
}
static long countLE(long[][] A, long x) {
    int n = A.length, m = A[0].length, r = n - 1, c = 0;
    long cnt = 0;
    while (r >= 0 && c < m) {
        if (A[r][c] <= x) { cnt += r + 1; c++; } else r--;
    }
    return cnt;
}
```

(`(lo + hi) >>> 1` is safe in `lowerBound` because `lo >= -1` and `hi <= a.length`, so the sum is a small non-negative
number except when `lo = -1, hi = 0` — and that case never enters the loop.)

### 3.2 Library semantics in one program (tested)

Input: `n`, a non-decreasing array, `q`, then `q` values $x$. For each $x$ print `lower_bound`, `upper_bound`, the count of $x$, the
largest element $<x$ and the smallest element $>x$ (`-` if none). The C++ version uses `partition_point` (identical to
`lower_bound`) and a `std::set`; the Java version uses its own bounds and a `TreeSet`.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<int> a(n);
    for (auto& v : a) cin >> v;
    set<int> s(a.begin(), a.end());
    int q; cin >> q;
    while (q--) {
        int x; cin >> x;
        int lb = partition_point(a.begin(), a.end(), [&](int v) { return v < x; }) - a.begin();
        int ub = upper_bound(a.begin(), a.end(), x) - a.begin();
        auto it = s.lower_bound(x);                  // member function: O(log n)
        string lower = it == s.begin() ? "-" : to_string(*prev(it));
        auto jt = s.upper_bound(x);
        string higher = jt == s.end() ? "-" : to_string(*jt);
        cout << lb << ' ' << ub << ' ' << ub - lb << ' ' << lower << ' ' << higher << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int lowerBound(int[] a, int x) {
        int lo = -1, hi = a.length;
        while (hi - lo > 1) { int mid = (lo + hi) >>> 1; if (a[mid] >= x) hi = mid; else lo = mid; }
        return hi;
    }
    static int upperBound(int[] a, int x) {
        int lo = -1, hi = a.length;
        while (hi - lo > 1) { int mid = (lo + hi) >>> 1; if (a[mid] > x) hi = mid; else lo = mid; }
        return hi;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        int[] a = new int[n];
        TreeSet<Integer> s = new TreeSet<>();
        for (int i = 0; i < n; i++) { a[i] = in.nextInt(); s.add(a[i]); }
        int q = in.nextInt();
        while (q-- > 0) {
            int x = in.nextInt();
            int lb = lowerBound(a, x), ub = upperBound(a, x);
            int r = Arrays.binarySearch(a, x);
            if (r < 0 && -r - 1 != lb) throw new AssertionError();   // absent: insertion point == lower bound
            Integer lower = s.lower(x), higher = s.higher(x);        // null when none: never unbox blindly
            out.println(lb + " " + ub + " " + (ub - lb) + " " + (lower == null ? "-" : lower) + " " + (higher == null ? "-" : higher));
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
6
1 3 3 3 7 9
5
3
0
10
5
9
out:
1 4 3 1 7
0 0 0 - 1
6 6 0 9 -
4 4 0 3 7
5 6 1 7 -
-->
<!-- test
in:
1
5
2
5
4
out:
0 1 1 - -
0 0 0 - 5
-->

### 3.3 k-th smallest pairwise distance (tested)

Input `n k` and $n$ integers ($0\le a_i\le10^9$, $1\le k\le\binom n2$); output the $k$-th smallest $|a_i-a_j|$ over pairs $i<j$.
Sort, then search the smallest $d$ with $c(d)\ge k$, counting pairs with a two-pointer sweep. $O(n\log n+n\log V)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; ll k; cin >> n >> k;
    vector<ll> a(n);
    for (auto& v : a) cin >> v;
    sort(a.begin(), a.end());
    auto count = [&](ll d) {                         // pairs i < j with a[j] - a[i] <= d
        ll c = 0;
        for (int i = 0, j = 0; j < n; j++) {
            while (a[j] - a[i] > d) i++;
            c += j - i;
        }
        return c;
    };
    ll lo = -1, hi = a[n - 1] - a[0];                // count(-1) = 0 < k, count(max) = all pairs >= k
    while (hi - lo > 1) {
        ll mid = lo + (hi - lo) / 2;
        (count(mid) >= k ? hi : lo) = mid;
    }
    cout << hi << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(); long k = in.nextLong();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        Arrays.sort(a);                              // long[]: fine here; for int[] shuffle first or sort Integer[]
        long lo = -1, hi = a[n - 1] - a[0];
        while (hi - lo > 1) {
            long mid = lo + (hi - lo) / 2;
            long c = 0;
            for (int i = 0, j = 0; j < n; j++) {
                while (a[j] - a[i] > mid) i++;
                c += j - i;
            }
            if (c >= k) hi = mid; else lo = mid;
        }
        System.out.println(hi);
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
4 4
1 6 3 10
out:
5
-->
<!-- test
in:
2 1
7 7
out:
0
-->
<!-- test
in:
5 10
0 1000000000 5 5 1
out:
1000000000
-->

### 3.4 Fractional programming by binary search on λ (fragment)

Choose exactly $k$ items maximising $\sum a/\sum b$: the check "is the optimum $\ge\lambda$?" takes the $k$ largest $a_i-\lambda b_i$.
This floating version is the general pattern (swap the check for any max-sum problem); Example 5 does the same exactly with Dinkelbach.

```cpp
double maxRatioK(const vector<double>& a, const vector<double>& b, int k) {
    int n = a.size();
    vector<double> w(n);
    auto ok = [&](double lam) {                      // F(lam) >= 0 ?
        for (int i = 0; i < n; i++) w[i] = a[i] - lam * b[i];
        nth_element(w.begin(), w.begin() + (k - 1), w.end(), greater<double>());
        double s = 0;
        for (int i = 0; i < k; i++) s += w[i];
        return s >= 0;
    };
    double lo = 0, hi = *max_element(a.begin(), a.end()) / *min_element(b.begin(), b.end());
    for (int it = 0; it < 100; it++) {               // ok(lo) true, ok(hi) false-or-boundary
        double mid = (lo + hi) / 2;
        (ok(mid) ? lo : hi) = mid;
    }
    return lo;
}
```

```java
static double maxRatioK(double[] a, double[] b, int k) {
    int n = a.length;
    double lo = 0, hi = 0;
    for (int i = 0; i < n; i++) hi = Math.max(hi, a[i] / b[i]);
    double[] w = new double[n];
    for (int it = 0; it < 100; it++) {
        double mid = (lo + hi) / 2;
        for (int i = 0; i < n; i++) w[i] = a[i] - mid * b[i];
        Arrays.sort(w);                             // O(n log n) per step; fine for n <= 1e5
        double s = 0;
        for (int i = n - k; i < n; i++) s += w[i];
        if (s >= 0) lo = mid; else hi = mid;
    }
    return lo;
}
```

## 4. Recognising the pattern

- **"Minimise the maximum …" / "maximise the minimum …"** → binary search on that bound, check greedily.
- **"Minimum time / days / speed / capacity such that …"** with large limits ($10^9$, $10^{18}$) → answer search. The
  limits are the hint: an answer up to $10^{18}$ cannot be found by trying values.
- **"Find the $k$-th smallest" of an implicit set** (products, sums of pairs, distances, fractions, subarray sums) → binary search on
  the value with a counting check.
- **"Maximise an average / ratio / density"** → fractional programming: subtract $\lambda$, binary search or Dinkelbach.
  "Maximum average subarray of length $\ge k$" is the special case $b_i=1$: check with prefix sums and prefix minima.
- **A monotone function you can evaluate but not invert** (a square root, the first day something happens, the first prefix with a
  property) → binary search over the index or the argument.
- **Sorted data plus "how many are ≤ / ≥ / in a range"** → `lower_bound`/`upper_bound` (or a TreeMap in Java).
- **Interactive "guess the hidden number with $\lceil\log_2 n\rceil$ queries"** → see [interactive problems](../03-Greedy-Constructive-Interactive/05-interactive-problems.md).
- **Confused with:** ternary search (the function is unimodal, not monotone — [ternary search](06-ternary-search-and-meet-in-the-middle.md));
  two pointers (both pointers move monotonically, no logarithm — [two pointers](03-two-pointers-and-sliding-window.md));
  parallel binary search (many searches sharing one expensive check — [offline techniques](../16-IGM-Frontier/01-offline-techniques-cdq-parallel-binary-search.md));
  and the Aliens trick (binary search on a *penalty*, not on the answer — [WQS binary search](../07-DP-Optimizations/06-aliens-trick-wqs-binary-search.md)).

## 5. Worked examples (graded)

### Example 1 — Maximum Median  ·  ★ 1400

- **Source:** [CF 1201C · Maximum Median](https://codeforces.com/problemset/problem/1201/C) — 1400
- **Difficulty:** 1400
- **Problem:** An array of odd length $n$ ($n\le2\cdot10^5$, $1\le a_i\le10^9$) and up to $k\le10^9$ operations, each adding $1$
  to one element. Maximise the median.
- **Thinking from first principles:** Sort. Raising an element below the median never helps the median, and raising the median
  element past the next one just swaps roles. The real question is: can the median be at least $m$? That needs every element from the
  median position upwards to be $\ge m$ (exchange argument: raising a smaller element instead is never cheaper), which costs
  $\sum_{i\ge n/2}\max(0,m-a_i)$. This cost is non-decreasing in $m$, so "achievable" is monotone (true then false) — last-true search.
  Upper bound: $a_{n/2}+k$, so $hi=a_{n/2}+k+1$ is certainly false.

<details><summary>Solution</summary>

Sort; $lo=a_{\lfloor n/2\rfloor}$ (cost $0$, true), $hi=lo+k+1$ (false). Check $m$: accumulate the cost over the upper half and stop
early once it exceeds $k$. $O(n\log n+n\log k)$. Values reach $2\cdot10^9$: 64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; ll k; cin >> n >> k;
    vector<ll> a(n);
    for (auto& v : a) cin >> v;
    sort(a.begin(), a.end());
    auto ok = [&](ll m) {
        ll cost = 0;
        for (int i = n / 2; i < n && cost <= k; i++) cost += max(0LL, m - a[i]);
        return cost <= k;
    };
    ll lo = a[n / 2], hi = a[n / 2] + k + 1;         // ok(lo) true, ok(hi) false
    while (hi - lo > 1) {
        ll mid = lo + (hi - lo) / 2;
        (ok(mid) ? lo : hi) = mid;
    }
    cout << lo << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(); long k = in.nextLong();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        Arrays.sort(a);
        long lo = a[n / 2], hi = a[n / 2] + k + 1;
        while (hi - lo > 1) {
            long mid = lo + (hi - lo) / 2, cost = 0;
            for (int i = n / 2; i < n && cost <= k; i++) cost += Math.max(0, mid - a[i]);
            if (cost <= k) lo = mid; else hi = mid;
        }
        System.out.println(lo);
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
1 5
3
out:
8
-->
<!-- test
in:
5 3
5 4 3 2 1
out:
5
-->
<!-- test
in:
3 1000000000
1000000000 1000000000 1000000000
out:
1500000000
-->

</details>

### Example 2 — The Meeting Place Cannot Be Changed  ·  ★ 1600

- **Source:** [CF 780B · The Meeting Place Cannot Be Changed](https://codeforces.com/problemset/problem/780/B) — 1600
- **Difficulty:** 1600
- **Problem:** $n\le6\cdot10^4$ friends stand on a line at $x_i$ and move with maximum speed $v_i$ ($1\le x_i,v_i\le10^9$).
  Find the minimum time after which all of them can be at one common point (absolute or relative error $10^{-6}$).
- **Thinking from first principles:** Optimising over both the time and the meeting point at once is awkward. Fix the time $t$
  instead: friend $i$ can reach exactly the interval $[x_i-v_it,\ x_i+v_it]$, and a common point exists iff the intervals intersect,
  i.e. $\max_i(x_i-v_it)\le\min_i(x_i+v_it)$ — an $O(n)$ check. Intervals only grow with $t$, so feasibility is monotone. Search $t$
  over reals in $[0,10^9]$ with a fixed iteration count. (Bonus insight, used to verify: in 1D, pairwise intersecting intervals have
  a common point, so the answer is $\max_{i,j}|x_i-x_j|/(v_i+v_j)$ — an $O(n^2)$ brute force.)

<details><summary>Solution</summary>

100 iterations of the real first-true search with the interval-intersection check: $O(100n)$. Print with enough digits; doubles
suffice because only $10^{-6}$ relative precision is required.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<double> x(n), v(n);
    for (auto& t : x) cin >> t;
    for (auto& t : v) cin >> t;
    auto ok = [&](double t) {
        double L = -1e30, R = 1e30;
        for (int i = 0; i < n; i++) { L = max(L, x[i] - v[i] * t); R = min(R, x[i] + v[i] * t); }
        return L <= R;
    };
    double lo = 0, hi = 1e9;                         // ok(hi) is true: everyone can cover distance 1e9
    for (int it = 0; it < 100; it++) {
        double mid = (lo + hi) / 2;
        (ok(mid) ? hi : lo) = mid;
    }
    printf("%.9f\n", hi);
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        double[] x = new double[n], v = new double[n];
        for (int i = 0; i < n; i++) x[i] = in.nextLong();
        for (int i = 0; i < n; i++) v[i] = in.nextLong();
        double lo = 0, hi = 1e9;
        for (int it = 0; it < 100; it++) {
            double mid = (lo + hi) / 2, L = -1e30, R = 1e30;
            for (int i = 0; i < n; i++) { L = Math.max(L, x[i] - v[i] * mid); R = Math.min(R, x[i] + v[i] * mid); }
            if (L <= R) hi = mid; else lo = mid;
        }
        System.out.println(String.format(Locale.US, "%.9f", hi));   // Locale.US: never a decimal comma
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
1 11
1 4
out:
2.000000000
-->
<!-- test
in:
1
5
3
out:
0.000000000
-->
<!-- test
in:
3
1 5 9
2 1 2
out:
2.000000000
-->
<!-- test
in:
2
1 1000000000
1 2
out:
333333333.000000000
-->

</details>

### Example 3 — Multiplication Table  ·  ★ 1800

- **Source:** [CF 448D · Multiplication Table](https://codeforces.com/problemset/problem/448/D) — 1800
- **Difficulty:** 1800
- **Problem:** The $n\times m$ table has entry $i\cdot j$ in row $i$, column $j$ ($n,m\le5\cdot10^5$). Find the $k$-th smallest
  of its $nm$ entries (with repetitions).
- **Thinking from first principles:** Listing $2.5\cdot10^{11}$ entries is hopeless, and even a heap that pops $k$ times is
  too slow. But *counting* entries $\le x$ is easy: row $i$ is $i,2i,\dots,mi$, so it contributes $\min(m,\lfloor x/i\rfloor)$.
  The count is monotone in $x$, so the $k$-th smallest is the first $x$ with count $\ge k$. Iterate over the shorter side.

<details><summary>Solution</summary>

First-true search on $x\in(0,nm]$ with $c(x)=\sum_{i=1}^{n}\min(m,\lfloor x/i\rfloor)$, after swapping so that $n\le m$.
$O(\min(n,m)\log(nm))$; $nm\le2.5\cdot10^{11}$ needs 64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ll n, m, k; cin >> n >> m >> k;
    if (n > m) swap(n, m);
    auto cnt = [&](ll x) {
        ll c = 0;
        for (ll i = 1; i <= n; i++) c += min(m, x / i);
        return c;
    };
    ll lo = 0, hi = n * m;                           // cnt(0) = 0 < k, cnt(n*m) = n*m >= k
    while (hi - lo > 1) {
        ll mid = lo + (hi - lo) / 2;
        (cnt(mid) >= k ? hi : lo) = mid;
    }
    cout << hi << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        long n = in.nextLong(), m = in.nextLong(), k = in.nextLong();
        if (n > m) { long t = n; n = m; m = t; }
        long lo = 0, hi = n * m;
        while (hi - lo > 1) {
            long mid = lo + (hi - lo) / 2, c = 0;
            for (long i = 1; i <= n; i++) c += Math.min(m, mid / i);
            if (c >= k) hi = mid; else lo = mid;
        }
        System.out.println(hi);
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
3 4 7
out:
4
-->
<!-- test
in:
1 1 1
out:
1
-->
<!-- test
in:
500000 500000 250000000000
out:
250000000000
-->

</details>

### Example 4 — Max Median  ·  ★ 2100

- **Source:** [CF 1486D · Max Median](https://codeforces.com/problemset/problem/1486/D) — 2100
- **Difficulty:** 2100
- **Problem:** Given $a_1..a_n$ with $1\le a_i\le n\le2\cdot10^5$ and $k\le n$, find the largest median over all subarrays of length
  at least $k$, where the median of a length-$\ell$ array is its $\lfloor(\ell+1)/2\rfloor$-th smallest element.
- **Thinking from first principles:**
  1. Medians of all $O(n^2)$ subarrays cannot be computed, and the median of a sliding window changes erratically. Decision
     version instead: *is there a subarray of length $\ge k$ with median $\ge x$?* That is monotone in $x$ (a median $\ge x$ is also
     $\ge x-1$), so binary search $x\in[1,n]$.
  2. Median $\ge x$ only depends on how many elements are $\ge x$: the $\lfloor(\ell+1)/2\rfloor$-th smallest is $\ge x$ iff at most
     $\lfloor(\ell+1)/2\rfloor-1$ elements are $<x$, iff (count $\ge x$) $>$ (count $<x$). Map $a_i\mapsto+1$ if $a_i\ge x$, else $-1$:
     we need a subarray of length $\ge k$ with positive sum.
  3. "Positive-sum subarray of length $\ge k$" is a prefix-sum question: for each right end $r\ge k$, compare $P_r$ with the
     *prefix minimum* of $P_0..P_{r-k}$ ([prefix sums](01-prefix-sums-and-difference-arrays.md)). $O(n)$ per check.

<details><summary>Solution</summary>

Last-true search: $x=1$ is always feasible (every $b_i=+1$), $x=n+1$ never. Check: build $\pm1$ prefix sums on the fly, keep
$\min(P_0..P_{r-k})$, succeed if $P_r-\min>0$. $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, k; cin >> n >> k;
    vector<int> a(n + 1);
    for (int i = 1; i <= n; i++) cin >> a[i];
    vector<int> P(n + 1);
    auto ok = [&](int x) {
        P[0] = 0;
        for (int i = 1; i <= n; i++) P[i] = P[i - 1] + (a[i] >= x ? 1 : -1);
        int best = INT_MAX;
        for (int r = k; r <= n; r++) {
            best = min(best, P[r - k]);              // min over P[0..r-k]
            if (P[r] - best > 0) return true;
        }
        return false;
    };
    int lo = 1, hi = n + 1;                          // ok(1) true, ok(n+1) false
    while (hi - lo > 1) {
        int mid = lo + (hi - lo) / 2;
        (ok(mid) ? lo : hi) = mid;
    }
    cout << lo << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n, k;
    static int[] a, P;

    static boolean ok(int x) {
        for (int i = 1; i <= n; i++) P[i] = P[i - 1] + (a[i] >= x ? 1 : -1);
        int best = Integer.MAX_VALUE;
        for (int r = k; r <= n; r++) {
            best = Math.min(best, P[r - k]);
            if (P[r] - best > 0) return true;
        }
        return false;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        n = in.nextInt(); k = in.nextInt();
        a = new int[n + 1]; P = new int[n + 1];
        for (int i = 1; i <= n; i++) a[i] = in.nextInt();
        int lo = 1, hi = n + 1;
        while (hi - lo > 1) {
            int mid = lo + (hi - lo) / 2;
            if (ok(mid)) lo = mid; else hi = mid;
        }
        System.out.println(lo);
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
1 1
1
out:
1
-->
<!-- test
in:
6 2
6 1 6 1 1 1
out:
6
-->
<!-- test
in:
5 5
5 4 3 2 1
out:
3
-->
<!-- test
in:
4 4
1 2 3 4
out:
2
-->

</details>

### Example 5 — Best ratio of exactly k items (Dinkelbach)  ·  ★ ≈2000 (est.)

- **Source:** Original problem
- **Difficulty:** ≈2000 (est.)
- **Problem:** $n$ items have value $a_i$ and cost $b_i$ ($1\le a_i,b_i\le10^4$, $1\le k\le n\le10^5$). Choose exactly $k$ items
  maximising $\sum a/\sum b$; print the optimum as a reduced fraction `p/q`.
- **Thinking from first principles:**
  1. Sorting by individual ratio $a_i/b_i$ and taking the best $k$ is wrong: with $k=2$ and items $(2,1),(1,1),(1000,999)$, the two best
     ratios are $2$ and $1.001$ giving $1002/1000$, but $(2,1)+(1,1)$ gives $3/2$. A large item with a mediocre ratio dominates the sum.
  2. Linearise: the optimum is $\ge\lambda$ iff some $k$-set has $\sum(a_i-\lambda b_i)\ge0$, iff the $k$ largest values of
     $a_i-\lambda b_i$ sum to $\ge0$. That is monotone in $\lambda$ — binary search on reals works (§3.4), but prints a decimal.
  3. For an exact fraction, use Dinkelbach with $\lambda=p/q$ kept as integers: compare items by $c_i=a_iq-b_ip$ (that is
     $q\cdot(a_i-\lambda b_i)$, same order since $q>0$). Take the top $k$; if their $c$-sum is $0$, $\lambda$ is optimal; otherwise
     the chosen set has a strictly larger ratio — move to it. Each step strictly increases $\lambda$ through ratios of actual sets, so it
     terminates; in practice in very few steps. Bounds: $p,q\le10^9$, $|c_i|\le2\cdot10^{13}$, $k\cdot|c_i|\le2\cdot10^{18}$ — fits in 64 bits.

<details><summary>Solution</summary>

Start at $\lambda=0/1$. Repeat: $c_i=a_iq-b_ip$; select the $k$ largest (`nth_element` in C++; in Java pack $c_i$ and $i$ into one
`long` and sort); if $\sum c=0$ stop, else $p=\sum a$, $q=\sum b$ over the selection. Print $p/g$ and $q/g$ with $g=\gcd(p,q)$.
Each iteration $O(n)$ (C++) or $O(n\log n)$ (Java).

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, k; cin >> n >> k;
    vector<ll> a(n), b(n);
    for (int i = 0; i < n; i++) cin >> a[i] >> b[i];
    ll p = 0, q = 1;                                 // lambda = p / q
    vector<int> id(n);
    while (true) {
        iota(id.begin(), id.end(), 0);
        auto c = [&](int i) { return a[i] * q - b[i] * p; };
        nth_element(id.begin(), id.begin() + (k - 1), id.end(), [&](int i, int j) { return c(i) > c(j); });
        ll F = 0, A = 0, B = 0;
        for (int t = 0; t < k; t++) { F += c(id[t]); A += a[id[t]]; B += b[id[t]]; }
        if (F == 0) break;                           // F(lambda) = 0: lambda is the optimum
        p = A; q = B;                                // Dinkelbach step: lambda <- ratio of the maximiser
    }
    ll g = gcd(p, q);
    cout << p / g << '/' << q / g << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), k = in.nextInt();
        long[] a = new long[n], b = new long[n], key = new long[n];
        for (int i = 0; i < n; i++) { a[i] = in.nextLong(); b[i] = in.nextLong(); }
        long p = 0, q = 1;
        Random rnd = new Random(12345);
        while (true) {
            for (int i = 0; i < n; i++) key[i] = ((a[i] * q - b[i] * p) << 17) | i;   // |c| < 2^45, i < 2^17
            for (int i = n - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long t = key[i]; key[i] = key[j]; key[j] = t; }
            Arrays.sort(key);                        // shuffled first: no adversarial quicksort pattern
            long F = 0, A = 0, B = 0;
            for (int t = n - k; t < n; t++) {
                int i = (int) (key[t] & ((1 << 17) - 1));
                F += a[i] * q - b[i] * p; A += a[i]; B += b[i];
            }
            if (F == 0) break;
            p = A; q = B;
        }
        long g = gcd(p, q);
        System.out.println((p / g) + "/" + (q / g));
    }

    static long gcd(long x, long y) { while (y != 0) { long t = x % y; x = y; y = t; } return x; }

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
3 2
2 1
1 1
1000 999
out:
3/2
-->
<!-- test
in:
1 1
6 4
out:
3/2
-->
<!-- test
in:
3 2
1 1
2 3
3 1
out:
2/1
-->
<!-- test
in:
4 3
10000 10000
10000 10000
10000 10000
1 10000
out:
1/1
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **State the invariant before writing the loop.** "`lo` is always infeasible, `hi` always feasible." Then the update and the
   returned variable are forced; most binary-search bugs come from mixing two templates.
2. **Choose sentinels outside the range** ($L-1$, $R+1$) so "none" and "all" need no special code — and make sure $p$ is never
   evaluated at them (it isn't, in the $hi-lo>1$ form).
3. **Prove monotonicity, don't assume it.** Write the one-line witness argument. If the check has an "exactly" in it, or the cost is
   not monotone (e.g. depends on parity), the search silently returns garbage.
4. **Bound the answer correctly.** `hi` must be truly feasible: e.g. `hi = max(a) * k` may overflow, or `hi = 1e9` may be infeasible when
   the answer can be $2\cdot10^9$. Compute it from the constraints, and in the check guard against overflow (break early once a sum
   exceeds the budget, as in Example 1).
5. **Midpoint:** `lo + (hi - lo) / 2`. `(lo + hi) / 2` overflows `int` and rounds toward zero for negatives — fatal in the
   `lo = mid + 1 / hi = mid` template when the range is negative.
6. **Reals: iterate a fixed number of times** (60–100), never `while (hi - lo > 1e-12)` with large values. When the answer spans many
   orders of magnitude and relative precision is required, search on $\log$ or use $mid=\sqrt{lo\cdot hi}$.
7. **`Arrays.binarySearch` with duplicates returns an arbitrary match**, and returns $-(\text{ins})-1$ when absent. Use your own
   `lowerBound` for first/last occurrence or counting.
8. **`std::lower_bound(s.begin(), s.end(), x)` on a `set` is $O(n)$**; use `s.lower_bound(x)`. Same for `map`, `multiset`.
9. **Java TreeMap returns `null`** from `floorKey`/`ceilingKey` when nothing qualifies; `int v = map.floorKey(x)` throws on `null`.
   Also every key is boxed: for $10^6$ operations prefer a sorted primitive array if the set is static.
10. **Sort before searching** — and in Java, `Arrays.sort(int[])` has a quadratic worst case on adversarial input (anti-quicksort
    hacks are common on Codeforces): shuffle first, or sort `long[]`/`Integer[]`.
11. **The check dominates.** With 60 iterations and an $O(n\log n)$ check you are at $60\,n\log n$; precompute sorting outside the
    search and keep the check linear.
12. **k-th smallest: count $\le x$, not $<x$**, and search for the first $x$ with count $\ge k$. Mixing strict and non-strict counts shifts
    the answer by one element when there are duplicates.

## 7. Going further (toward 2400–2600+)

- **Parallel binary search:** answer many "first time something becomes true" queries at once by sweeping time once per round —
  [offline techniques](../16-IGM-Frontier/01-offline-techniques-cdq-parallel-binary-search.md).
- **Binary search on a penalty (Aliens / WQS):** when the constraint is "exactly $k$ items" and the cost is concave in $k$, binary search
  a per-item penalty $\lambda$ instead of the answer — [Aliens trick](../07-DP-Optimizations/06-aliens-trick-wqs-binary-search.md).
  Dinkelbach and WQS share the idea "linearise with a multiplier, then search the multiplier".
- **Fractional programming on graphs:** minimum mean cycle, optimal ratio spanning tree, maximum density subgraph (the last via
  [min cut](../12-Flows-and-Matching/02-min-cut-and-flow-modeling.md)) — each a max-sum problem after subtracting $\lambda b$.
- **Binary search on a segment tree / Fenwick tree:** find the first prefix whose sum reaches $k$ in $O(\log n)$ by descending the tree
  instead of an outer binary search ($O(\log^2n)$) — [segment tree descent](../08-Data-Structures/04-segment-tree-advanced-descent-merging-beats.md),
  [Fenwick tree](../08-Data-Structures/01-fenwick-tree.md).
- **Exponential (galloping) search** when the upper bound is unknown: double $hi$ until $p(hi)$ holds, then binary search — $O(\log\text{answer})$.
- **Binary search + hashing** for "longest substring that …" (length is monotone) — [string hashing](../11-Strings/01-string-hashing.md).

## 8. Practice ladder

**≤ 1400**
- [ ] [CF 706B · Interesting drink](https://codeforces.com/problemset/problem/706/B) — 1100
- [ ] [CF 474B · Worms](https://codeforces.com/problemset/problem/474/B) — 1200
- [ ] [CF 1613C · Poisoned Dagger](https://codeforces.com/problemset/problem/1613/C) — 1200
- [ ] [CF 1352C · K-th Not Divisible by n](https://codeforces.com/problemset/problem/1352/C) — 1200
- [ ] [CF 1538C · Number of Pairs](https://codeforces.com/problemset/problem/1538/C) — 1300
- [ ] [CF 1324D · Pair of Topics](https://codeforces.com/problemset/problem/1324/D) — 1400
- [ ] [CF 1840D · Wooden Toy Festival](https://codeforces.com/problemset/problem/1840/D) — 1400
- [ ] [CSES 1620 · Factory Machines](https://cses.fi/problemset/task/1620)

**1400–1700**
- [ ] [CF 760B · Frodo and pillows](https://codeforces.com/problemset/problem/760/B) — 1500
- [ ] [CF 702C · Cellular Network](https://codeforces.com/problemset/problem/702/C) — 1500
- [ ] [CF 670D2 · Magic Powder - 2](https://codeforces.com/problemset/problem/670/D2) — 1500
- [ ] [CF 1760F · Quests](https://codeforces.com/problemset/problem/1760/F) — 1500
- [ ] [CSES 1085 · Array Division](https://cses.fi/problemset/task/1085)
- [ ] [CF 371C · Hamburgers](https://codeforces.com/problemset/problem/371/C) — 1600
- [ ] [CF 1843E · Tracking Segments](https://codeforces.com/problemset/problem/1843/E) — 1600
- [ ] [CF 1730B · Meeting on the Line](https://codeforces.com/problemset/problem/1730/B) — 1600
- [ ] [CF 1610C · Keshi Is Throwing a Party](https://codeforces.com/problemset/problem/1610/C) — 1600
- [ ] [CF 778A · String Game](https://codeforces.com/problemset/problem/778/A) — 1700
- [ ] [CF 1359C · Mixing Water](https://codeforces.com/problemset/problem/1359/C) — 1700

**1700–2100**
- [ ] [CSES 2422 · Multiplication Table](https://cses.fi/problemset/task/2422)
- [ ] [CF 1117C · Magic Ship](https://codeforces.com/problemset/problem/1117/C) — 1900
- [ ] [CF 1251D · Salary Changing](https://codeforces.com/problemset/problem/1251/D) — 1900
- [ ] [CF 1260D · A Game with Traps](https://codeforces.com/problemset/problem/1260/D) — 1900
- [ ] [CF 1918D · Blocking Elements](https://codeforces.com/problemset/problem/1918/D) — 1900
- [ ] [AtCoder ABC236 E · Average and Median](https://atcoder.jp/contests/abc236/tasks/abc236_e) — average via $a_i-\lambda$, median via $\pm1$
- [ ] [CF 1288D · Minimax Problem](https://codeforces.com/problemset/problem/1288/D) — 2000
- [ ] [CF 1370D · Odd-Even Subsequence](https://codeforces.com/problemset/problem/1370/D) — 2000

**Stretch**
- [ ] [CF 1132D · Stressful Training](https://codeforces.com/problemset/problem/1132/D) — 2300

## 9. LeetCode / FAANG cross-reference

Binary search is a top-five interview topic; interviewers probe the boundary handling (first/last occurrence, rotated arrays) and
"binary search on the answer" disguised as a scheduling question.

- [LC 704 · Binary Search](https://leetcode.com/problems/binary-search/) — Easy — the plain search.
- [LC 35 · Search Insert Position](https://leetcode.com/problems/search-insert-position/) — Easy — exactly `lower_bound`.
- [LC 278 · First Bad Version](https://leetcode.com/problems/first-bad-version/) — Easy — first-true on an API predicate.
- [LC 69 · Sqrt(x)](https://leetcode.com/problems/sqrtx/) — Easy — last $m$ with $m^2\le x$; overflow in `m*m`.
- [LC 34 · Find First and Last Position of Element in Sorted Array](https://leetcode.com/problems/find-first-and-last-position-of-element-in-sorted-array/) — Medium — lower and upper bound.
- [LC 33 · Search in Rotated Sorted Array](https://leetcode.com/problems/search-in-rotated-sorted-array/) — Medium — predicate "is in the left run".
- [LC 153 · Find Minimum in Rotated Sorted Array](https://leetcode.com/problems/find-minimum-in-rotated-sorted-array/) — Medium — predicate $a_i\le a_{n-1}$.
- [LC 162 · Find Peak Element](https://leetcode.com/problems/find-peak-element/) — Medium — predicate $a_i>a_{i+1}$ is monotone enough to find *a* peak.
- [LC 74 · Search a 2D Matrix](https://leetcode.com/problems/search-a-2d-matrix/) — Medium — flatten the index.
- [LC 240 · Search a 2D Matrix II](https://leetcode.com/problems/search-a-2d-matrix-ii/) — Medium — staircase $O(n+m)$.
- [LC 378 · Kth Smallest Element in a Sorted Matrix](https://leetcode.com/problems/kth-smallest-element-in-a-sorted-matrix/) — Medium — value search + staircase count.
- [LC 668 · Kth Smallest Number in Multiplication Table](https://leetcode.com/problems/kth-smallest-number-in-multiplication-table/) — Hard — Example 3.
- [LC 719 · Find K-th Smallest Pair Distance](https://leetcode.com/problems/find-k-th-smallest-pair-distance/) — Hard — §3.3.
- [LC 786 · K-th Smallest Prime Fraction](https://leetcode.com/problems/k-th-smallest-prime-fraction/) — Medium — real-valued value search with a two-pointer count.
- [LC 875 · Koko Eating Bananas](https://leetcode.com/problems/koko-eating-bananas/) — Medium — minimum speed.
- [LC 1011 · Capacity To Ship Packages Within D Days](https://leetcode.com/problems/capacity-to-ship-packages-within-d-days/) — Medium — minimise the maximum load.
- [LC 410 · Split Array Largest Sum](https://leetcode.com/problems/split-array-largest-sum/) — Hard — the same with "at most $k$ parts".
- [LC 1482 · Minimum Number of Days to Make m Bouquets](https://leetcode.com/problems/minimum-number-of-days-to-make-m-bouquets/) — Medium — first day feasible.
- [LC 1552 · Magnetic Force Between Two Balls](https://leetcode.com/problems/magnetic-force-between-two-balls/) — Medium — maximise the minimum gap.
- [LC 2187 · Minimum Time to Complete Trips](https://leetcode.com/problems/minimum-time-to-complete-trips/) — Medium — CSES Factory Machines.
- [LC 2141 · Maximum Running Time of N Computers](https://leetcode.com/problems/maximum-running-time-of-n-computers/) — Hard — check $\sum\min(b_i,T)\ge nT$.
- [LC 4 · Median of Two Sorted Arrays](https://leetcode.com/problems/median-of-two-sorted-arrays/) — Hard — binary search on the split point.
- [LC 981 · Time Based Key-Value Store](https://leetcode.com/problems/time-based-key-value-store/) — Medium — TreeMap `floorKey` / upper bound on timestamps.
- [LC 644 · Maximum Average Subarray II](https://leetcode.com/problems/maximum-average-subarray-ii/) — Hard 🔒 — fractional programming with $b_i=1$, prefix minima.
- [LC 857 · Minimum Cost to Hire K Workers](https://leetcode.com/problems/minimum-cost-to-hire-k-workers/) — Hard — a ratio problem solved by sorting + heap (contrast with Example 5).

Interview framing: see [binary search for interviews](../17-FAANG-Interview-DSA/05-binary-search.md).

## 10. Self-check

1. State the loop invariant of the first-true search and prove the loop returns the first true position.
2. Why does `while (lo < hi) { mid = (lo + hi) / 2; if (p(mid)) hi = mid; else lo = mid + 1; }` loop forever on $lo=-3$, $hi=-2$? What fixes it?
3. `Arrays.binarySearch(a, 5)` returns `-4`. What does that tell you? And if it returns `2` on an array with many 5s?
4. What is the predicate, and why is it monotone, for "the $k$-th smallest of all pairwise sums $a_i+b_j$"? How do you count in $O(n+m)$?
5. Why is `while (hi - lo > 1e-9)` dangerous for answers around $10^9$, and how many fixed iterations do you need for range $10^9$, error $10^{-6}$?
6. Derive the check for "maximise $\sum a/\sum b$ over $k$-subsets" and explain why Dinkelbach's update strictly increases $\lambda$ until optimal.
7. In Example 4, why does "median $\ge x$" depend only on the counts of elements $\ge x$ and $<x$?
8. When is `std::lower_bound` on a `std::set` a TLE, and what do you write instead?

<details><summary>Answers</summary>

1. $p(lo)=F$, $p(hi)=T$ (sentinels virtual). Each step keeps it and strictly shrinks $hi-lo$; at $hi=lo+1$, monotonicity gives all
   positions $\le lo$ false and $hi$ true, so $hi$ is the first true.
2. $(lo+hi)/2=(-5)/2=-2=hi$ (truncation toward zero); if $p(-2)$ is true, `hi = mid` changes nothing. Use `mid = lo + (hi - lo) / 2`
   (rounds toward $lo$) or `>> 1`.
3. $-4=-(3)-1$: 5 is absent and would be inserted at index 3 (the lower bound). If it returns 2, *some* 5 is at index 2 — not
   necessarily the first or last.
4. $p(x)=[\#\{(i,j): a_i+b_j\le x\}\ge k]$; the count only grows with $x$. Sort both; as $i$ increases, the largest $j$ with
   $b_j\le x-a_i$ decreases, so one pointer sweeps $b$ backwards.
5. Doubles near $10^9$ are spaced $\approx1.2\cdot10^{-7}$ apart, so $hi-lo$ can never drop below $10^{-9}$; $mid$ rounds to an endpoint and the
   loop never ends. $\lceil\log_2(10^9/10^{-6})\rceil=50$ iterations (use 60–100 to be safe).
6. $\max R\ge\lambda\iff\max_S\sum(a-\lambda b)\ge0$ since $\sum b>0$; with $k$ items, take the $k$ largest $a_i-\lambda b_i$. If
   $F(\lambda_t)>0$, the maximiser $S_t$ has $\sum(a-\lambda_tb)>0$, i.e. $R(S_t)>\lambda_t$; if $F(\lambda_t)=0$ no set beats $\lambda_t$,
   which is itself a set's ratio, so it is optimal.
7. The $\lfloor(\ell+1)/2\rfloor$-th smallest is $\ge x$ iff fewer than $\lfloor(\ell+1)/2\rfloor$ elements are $<x$, which is
   equivalent to #($\ge x$) $>$ #($<x$); the actual values do not matter.
8. Set iterators are bidirectional, so the free function walks $O(n)$ steps per call. Use the member `s.lower_bound(x)`, $O(\log n)$.

</details>

See also the [cheat sheet](../99-Cheat-Sheets/02-core-techniques-cheatsheet.md) and the folder [problem list](problems.md).
