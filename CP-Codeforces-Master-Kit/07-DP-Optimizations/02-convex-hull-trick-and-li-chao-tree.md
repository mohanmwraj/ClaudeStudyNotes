# Convex Hull Trick and Li Chao Tree

> **Band:** 🟣 1900–2400 (Li Chao on segments, merging, kinetic variants 🔴) · **Priority:** 🔥 · **FAANG:** low · **Prerequisites:** [prefix-sum and monotonic-queue optimisation](01-prefix-sum-and-monotonic-queue-optimization.md), [segment tree basics](../08-Data-Structures/02-segment-tree-basics.md), [vectors, dot and cross products](../14-Geometry/01-vectors-dot-cross-and-precision.md), [integer overflow and precision](../01-Foundations/06-integer-overflow-precision-and-fast-io.md)
> **You can say you know this when:** you can take a quadratic DP, expand its cost into "term in $j$ × term in $i$ + term in $j$ + term in $i$", name the right structure from the monotonicity of slopes and queries (deque, binary search on the hull, LineContainer, Li Chao, Li Chao on segments), and implement it with **exact** integer comparisons in both C++ and Java.

## 1. First principles — why this works

### 1.1 The shape that makes a DP "a set of lines"

Many 1D DPs read
$$dp[i] = \min_{j < i} \big(dp[j] + \mathrm{cost}(j, i)\big)$$
and are $O(n^2)$ because every $i$ scans every $j$. Expand the cost. If it splits as
$$\mathrm{cost}(j, i) = m_j \cdot x_i + c_j + d_i$$
(a product of something about $j$ and something about $i$, plus pure terms), then
$$dp[i] = d_i + \min_{j<i} \big(m_j x_i + b_j\big), \qquad b_j = dp[j] + c_j .$$
Each earlier state $j$ is a **line** $y = m_j x + b_j$, fixed once $dp[j]$ is known; computing $dp[i]$ is a **query**: the lowest line at $x = x_i$. Example (Frog 3): $(h_i - h_j)^2 + C = \underbrace{(-2h_j)}_{m_j} h_i + \underbrace{h_j^2}_{c_j} + \underbrace{h_i^2 + C}_{d_i}$.

So the DP becomes a data-structure problem: **insert lines, query the minimum at a point.** Everything in this file is a way to answer that faster than "evaluate all lines".

### 1.2 The lower envelope and why each line owns one interval

Let $E(x) = \min_j (m_j x + b_j)$, the lower envelope. Two facts drive everything:

1. **$E$ is concave and piecewise linear.** It is a minimum of linear (hence concave) functions.
2. **Each line is optimal on a single interval (possibly empty).** The set where line $\ell$ beats line $\ell'$ is a half-line (two distinct non-parallel lines cross exactly once), and the set where $\ell$ is the minimum is the intersection of those half-lines — an interval.

Walking left to right, the optimal lines appear in **decreasing slope order** (at $x \to -\infty$ the steepest line is lowest; at $x \to +\infty$ the flattest — most negative slope — is lowest). The envelope is therefore a *sorted list* of lines, each owning an interval, and the boundaries are pairwise intersections. That list is the **hull**.

### 1.3 Building the hull when slopes arrive sorted

Insert lines in decreasing slope order (for a minimum). The new line $\ell_3$ always owns the rightmost interval (it is the flattest). The current last line $\ell_2$, with predecessor $\ell_1$ ($m_1 > m_2 > m_3$), becomes useless exactly when $\ell_3$ takes over before $\ell_2$ ever beat $\ell_1$:
$$x_{13} \le x_{12}, \qquad x_{ab} = \frac{b_b - b_a}{m_a - m_b}.$$
Both denominators are positive, so cross-multiplying keeps the direction:
$$\boxed{(b_3 - b_1)(m_1 - m_2) \le (b_2 - b_1)(m_1 - m_3) \;\Longrightarrow\; \ell_2 \text{ is useless.}}$$
Pop $\ell_2$ and repeat with the new last two. Each line is pushed once and popped at most once: **amortised $O(1)$ per insert.** Equal slopes: keep only the lower intercept (the formula would divide by zero).

### 1.4 Queries

- **Monotone queries** ($x$ non-decreasing). The optimal line index along the hull is non-decreasing in $x$, so a pointer that only moves right (or popping the front of a deque) answers every query in amortised $O(1)$. Lines left of the pointer are dead forever: all future queries are to their right.
- **Arbitrary queries.** The hull is sorted, so binary search for the first line that is not beaten by its right neighbour at $x$ — $O(\log n)$. The predicate "$\ell_k(x) \le \ell_{k+1}(x)$" is monotone in $k$ because of the interval structure.
- **Arbitrary slope order** breaks the deque (a new line may land in the middle of the hull). Two standard answers follow.

### 1.5 Arbitrary insertion order, answer 1: the dynamic hull ("LineContainer")

Keep the hull in a balanced BST ordered by slope, and store with each line $p$ = the last integer $x$ at which it is still optimal against its right neighbour. Insertion of $\ell$: put it in slope order; while its right neighbour owns no integer any more ($p_\ell \ge p_{\text{right}}$), delete the neighbour; check whether $\ell$ itself is useless against its left neighbour; then delete left neighbours that $\ell$ buries. A query is a `lower_bound` on $p$. Every line is inserted and deleted once: amortised $O(\log n)$ per operation, exact with integer `floorDiv`. This is the structure people mean by "LineContainer" (the name comes from a well-known team notebook); the version in §3 is written for this kit.

### 1.6 Arbitrary insertion order, answer 2: the Li Chao tree

Fix the set of possible query points (an integer range $[lo, hi]$, or a sorted list of coordinates). Build a segment tree over it; every node stores **at most one line**. To insert line $\ell$ at a node with interval $[l, r]$, midpoint $mid$, holding line $s$:

1. Keep at the node whichever of $\ell, s$ is lower at $mid$; call the other one the *loser*.
2. Two lines cross at most once. If the loser is lower at $l$, the crossing is in $[l, mid]$, so the loser can only be optimal somewhere in the left half — recurse there. Otherwise it can only win in the right half — recurse right. (If it wins nowhere, it sinks to a leaf harmlessly.)

**Invariant.** For every query point $x$, the line optimal at $x$ among all inserted lines is stored at some node on the root-to-leaf path of $x$. *Proof by induction on insertions:* at each node the line that was discarded from $x$'s path is beaten at $x$ by the line kept at that node (the crossing argument above shows the loser is beaten on the whole half we did not recurse into, and on $mid$). So a **query** just evaluates the $O(\log C)$ lines on the path and takes the minimum.

Cost: $O(\log C)$ per insert and per query, $C$ = size of the coordinate range. No precision issues — it only *evaluates* lines, never intersects them. That is why many strong competitors use Li Chao as their default.

### 1.7 Li Chao on segments 🔴

If line $j$ is only valid for queries $x \in [L_j, R_j]$ (a line *segment*), decompose $[L_j, R_j]$ into the $O(\log C)$ canonical nodes of the segment tree and run the ordinary insertion inside each of those subtrees: $O(\log^2 C)$ per segment, query unchanged. The invariant holds per canonical subtree. Typical source: a state $j$ whose transitions are allowed only into a range of later states (Example 5).

### 1.8 Overflow and precision — the part that actually fails in contests

The bad-line test multiplies an intercept difference by a slope difference. With $|b| \le 10^{18}$ and $|m| \le 10^9$ the products reach $2\cdot10^{27}$: **64 bits overflow**, and the failure is silent (a wrong hull, wrong answers on large tests only). Options:

| Approach | C++ | Java | Exact? |
|---|---|---|---|
| 128-bit products | `(__int128)a * b` | `Math.multiplyHigh` + unsigned low word (§3) | yes |
| floor-division breakpoints (integer queries only) | `floorDiv(b2 - b1, m1 - m2)` | `Math.floorDiv` | yes, needs $|b_2 - b_1|$ to fit |
| `long double` cross-multiplication | 64-bit mantissa | — (Java `double` has 53 bits) | no; usually fine to $10^{18}$, not guaranteed |
| Li Chao (evaluate only) | $m x + b$ must fit in 64 bits | same | yes |

Also check the *evaluation* $m_j x + b_j$: with $|m|, |x| \le 10^9$ and $|b| \le 10^{18}$ it stays below $2\cdot10^{18} < 9.2\cdot10^{18}$, fine; with $|x| \le 10^{12}$ it is not.

**Maximum instead of minimum:** insert $(-m, -b)$ into a min-structure and negate the answer, or flip every comparison. Negating is less error-prone.

## 2. Formulas, definitions and identities

| Formula | Meaning |
|---|---|
| $dp[i] = d_i + \min_j (m_j x_i + b_j)$ | target form; $m_j, b_j$ depend only on $j$, $x_i, d_i$ only on $i$ |
| $(s_i - s_j)^2 = s_i^2 - 2 s_j s_i + s_j^2$ | the most common source: $m_j = -2s_j$, $b_j = dp_j + s_j^2$ |
| $x_{12} = \dfrac{b_2 - b_1}{m_1 - m_2}$ | intersection abscissa of $\ell_1, \ell_2$ |
| $(b_3 - b_1)(m_1 - m_2) \le (b_2 - b_1)(m_1 - m_3)$ | $\ell_2$ useless, given $m_1 > m_2 > m_3$ (min hull) |
| $p_1 = \lfloor (b_2 - b_1)/(m_1 - m_2) \rfloor$ | last integer where $\ell_1 \le \ell_2$ (LineContainer breakpoint) |
| $\lfloor a/b \rfloor$ = `a / b - ((a % b != 0) && ((a < 0) != (b < 0)))` | C++ floor division (`/` truncates toward zero) |
| $\operatorname{sign}(ab - cd)$ via $\mathrm{hi}(ab)$ vs $\mathrm{hi}(cd)$, then unsigned $\mathrm{lo}$ | exact 128-bit comparison in Java |
| $\max_j(m_j x + b_j) = -\min_j(-m_j x - b_j)$ | max hull from a min hull |

| Structure | Insert | Query | Requirements |
|---|---|---|---|
| deque hull + pointer | amortised $O(1)$ | amortised $O(1)$ | slopes sorted, queries sorted (same "direction") |
| deque hull + binary search | amortised $O(1)$ | $O(\log n)$ | slopes sorted |
| LineContainer | amortised $O(\log n)$ | $O(\log n)$ | integer queries (floor breakpoints) or careful reals |
| Li Chao (static points / range $C$) | $O(\log C)$ | $O(\log C)$ | query domain known |
| Li Chao, line segments | $O(\log^2 C)$ | $O(\log C)$ | query domain known |
| Li Chao, dynamic nodes | $O(\log C)$, $\le 1$ new node | $O(\log C)$ | range $[lo, hi]$, any order, online |

## 3. Implementation (C++ and Java)

All four structures compute a **minimum**; for a maximum, insert $(-m, -b)$ and negate. They were stress-tested against a brute force over random operation sequences (C++ and Java), including $|m|, |x| \le 10^9$ and $|b| \le 10^{18}$.

**3.1 Monotone hull (deque).** Slopes must be added in non-increasing order. Use `query` for non-decreasing $x$, or `queryAny` for arbitrary $x$.

```cpp
// Minimum of lines. add(): slopes in non-increasing order. query(): x non-decreasing between
// calls (amortised O(1)). queryAny(): any x, O(log n); use one or the other, not both.
// Maximum: add(-m, -b) and negate the answer.
struct MonoCHT {
    struct Line { ll m, b; ll at(ll x) const { return m * x + b; } };
    vector<Line> h;     // the hull; slopes strictly decreasing
    size_t head = 0;    // lines before head are dead for monotone queries
    // l2 is useless iff l1,l3 meet at or left of l1,l2 (m1 > m2 > m3); exact in 128 bits
    static bool useless(const Line& l1, const Line& l2, const Line& l3) {
        return (__int128)(l3.b - l1.b) * (l1.m - l2.m) <= (__int128)(l2.b - l1.b) * (l1.m - l3.m);
    }
    void add(ll m, ll b) {
        Line l{m, b};
        if (h.size() > head && h.back().m == m) {        // equal slopes: keep the lower line
            if (h.back().b <= b) return;
            h.pop_back();
        }
        while (h.size() >= head + 2 && useless(h[h.size() - 2], h.back(), l)) h.pop_back();
        h.push_back(l);
    }
    ll query(ll x) {
        while (head + 1 < h.size() && h[head + 1].at(x) <= h[head].at(x)) head++;
        return h[head].at(x);
    }
    ll queryAny(ll x) const {
        size_t lo = head, hi = h.size() - 1;              // first i with h[i](x) <= h[i+1](x)
        while (lo < hi) {
            size_t mid = (lo + hi) / 2;
            if (h[mid].at(x) <= h[mid + 1].at(x)) hi = mid; else lo = mid + 1;
        }
        return h[lo].at(x);
    }
};
```

```java
// Minimum of lines; same contract as the C++ version. cap = max number of add() calls.
static class MonoCHT {
    final long[] M, B;
    int head = 0, size = 0;
    MonoCHT(int cap) { M = new long[cap]; B = new long[cap]; }
    // sign(a*b - c*d) computed exactly in 128 bits (Java has no __int128)
    static int cmpMul(long a, long b, long c, long d) {
        long h1 = Math.multiplyHigh(a, b), h2 = Math.multiplyHigh(c, d);
        if (h1 != h2) return h1 < h2 ? -1 : 1;
        return Long.compareUnsigned(a * b, c * d);       // low words compare as unsigned
    }
    long at(int i, long x) { return M[i] * x + B[i]; }
    void add(long m, long b) {
        if (size > head && M[size - 1] == m) {
            if (B[size - 1] <= b) return;
            size--;
        }
        while (size >= head + 2) {
            int i = size - 2, j = size - 1;
            if (cmpMul(b - B[i], M[i] - M[j], B[j] - B[i], M[i] - m) > 0) break;
            size--;
        }
        M[size] = m; B[size] = b; size++;
    }
    long query(long x) {
        while (head + 1 < size && at(head + 1, x) <= at(head, x)) head++;
        return at(head, x);
    }
    long queryAny(long x) {
        int lo = head, hi = size - 1;
        while (lo < hi) {
            int mid = (lo + hi) >>> 1;
            if (at(mid, x) <= at(mid + 1, x)) hi = mid; else lo = mid + 1;
        }
        return at(lo, x);
    }
}
```

**3.2 LineContainer (any insertion order, integer queries).**

```cpp
// Dynamic lower hull: add any line in any order, query min at any integer x. Amortised O(log n).
// Lines are kept left-to-right along the envelope (slopes decreasing); each stores p = the last
// integer x at which it is still optimal against its right neighbour, so p increases along the set.
struct LineContainer {
    static constexpr ll INF = LLONG_MAX;
    struct Line {
        ll m, b;
        mutable ll p;                                    // not part of the ordering, safe to mutate
        bool operator<(const Line& o) const { return m > o.m; }
        bool operator<(ll x) const { return p < x; }     // used by lower_bound(x) in query
    };
    multiset<Line, less<>> s;                            // less<> enables lookup by ll
    using It = multiset<Line, less<>>::iterator;
    static ll floorDiv(ll a, ll b) { return a / b - ((a % b != 0) && ((a < 0) != (b < 0))); }
    // set x.p against its right neighbour y; true iff y now owns no integer (x.p >= y.p)
    bool fix(It x, It y) {
        if (y == s.end()) { x->p = INF; return false; }
        x->p = floorDiv(y->b - x->b, x->m - y->m);       // x <= y exactly for t <= this
        return x->p >= y->p;
    }
    void add(ll m, ll b) {
        auto same = s.find(Line{m, b, 0});
        if (same != s.end()) {                           // equal slope: keep the lower line
            if (same->b <= b) return;
            s.erase(same);
        }
        auto y = s.insert({m, b, 0});
        auto z = next(y);
        while (fix(y, z)) z = s.erase(z);                // right neighbours buried by the new line
        if (y == s.begin()) return;
        auto x = prev(y);
        if (fix(x, y)) { y = s.erase(y); fix(x, y); }    // the new line itself is useless
        while (x != s.begin()) {                         // left neighbours buried by the new line
            auto w = prev(x);
            if (w->p < x->p) break;
            x = s.erase(x);
            fix(w, x);
            x = w;
        }
    }
    ll query(ll x) const {                               // requires at least one line
        auto l = s.lower_bound(x);                       // first line with p >= x
        return l->m * x + l->b;
    }
};
```

```java
// Dynamic lower hull; same contract as the C++ version. A query is a probe Line with q = true
// whose p holds x: it sorts before every line with p >= x, so ceiling(probe) is the answer line.
static class LineContainer {
    static final long INF = Long.MAX_VALUE;
    static class Line {
        final long m, b; long p; final boolean q;
        Line(long m, long b, long p, boolean q) { this.m = m; this.b = b; this.p = p; this.q = q; }
    }
    final TreeSet<Line> s = new TreeSet<>((u, v) -> {
        if (u.q) return u.p <= v.p ? -1 : 1;             // never 0: probes are not stored
        if (v.q) return v.p <= u.p ? 1 : -1;
        return Long.compare(v.m, u.m);                   // real lines: slope descending
    });
    // set x.p against its right neighbour y (null = none); true iff y owns no integer now
    boolean fix(Line x, Line y) {
        if (y == null) { x.p = INF; return false; }
        x.p = Math.floorDiv(y.b - x.b, x.m - y.m);
        return x.p >= y.p;
    }
    void add(long m, long b) {
        Line y = new Line(m, b, 0, false);
        Line same = s.ceiling(y);                        // equal slope compares as equal
        if (same != null && same.m == m) {
            if (same.b <= b) return;
            s.remove(same);
        }
        s.add(y);
        Line z = s.higher(y);
        while (fix(y, z)) { s.remove(z); z = s.higher(y); }
        Line x = s.lower(y);
        if (x == null) return;
        if (fix(x, y)) { s.remove(y); fix(x, s.higher(x)); }
        Line w;
        while ((w = s.lower(x)) != null && w.p >= x.p) {
            s.remove(x);
            fix(w, s.higher(w));
            x = w;
        }
    }
    long query(long x) {                                 // requires at least one line
        Line l = s.ceiling(new Line(0, 0, x, true));
        return l.m * x + l.b;
    }
}
```

**3.3 Li Chao tree over fixed points, with segment insertion.** `xs` must be sorted and distinct; queries and segment bounds are *indices* into `xs`.

```cpp
// Minimum Li Chao tree over fixed, sorted, distinct points xs[0..n-1] (offline coordinates).
// addLine O(log n); addSegment(lq, rq): line active only on xs[lq..rq], O(log^2 n);
// query(i) = min over active lines at xs[i], O(log n); LLONG_MAX if no line covers xs[i].
struct LiChao {
    int n;
    vector<ll> xs, M, B;
    vector<char> has;                                    // empty-node flag, no INF lines
    explicit LiChao(const vector<ll>& pts)
        : n(pts.size()), xs(pts), M(4 * pts.size()), B(4 * pts.size()), has(4 * pts.size(), 0) {}
    void put(int node, int l, int r, ll m, ll b) {       // insert into the subtree of node
        while (true) {
            if (!has[node]) { has[node] = 1; M[node] = m; B[node] = b; return; }
            int mid = (l + r) / 2;
            bool lef = m * xs[l] + b < M[node] * xs[l] + B[node];
            bool mi = m * xs[mid] + b < M[node] * xs[mid] + B[node];
            if (mi) { swap(M[node], m); swap(B[node], b); }   // node keeps the winner at mid
            if (l == r) return;
            if (lef != mi) { node = 2 * node; r = mid; }     // loser can win only on the left
            else { node = 2 * node + 1; l = mid + 1; }       // ... or only on the right
        }
    }
    void seg(int node, int l, int r, int lq, int rq, ll m, ll b) {
        if (rq < l || r < lq) return;
        if (lq <= l && r <= rq) { put(node, l, r, m, b); return; }
        int mid = (l + r) / 2;
        seg(2 * node, l, mid, lq, rq, m, b);
        seg(2 * node + 1, mid + 1, r, lq, rq, m, b);
    }
    void addLine(ll m, ll b) { put(1, 0, n - 1, m, b); }
    void addSegment(int lq, int rq, ll m, ll b) { if (lq <= rq) seg(1, 0, n - 1, lq, rq, m, b); }
    ll query(int i) const {
        ll res = LLONG_MAX;
        int node = 1, l = 0, r = n - 1;
        while (true) {                                   // empty nodes are skipped, not cut
            if (has[node]) res = min(res, M[node] * xs[i] + B[node]);
            if (l == r) return res;
            int mid = (l + r) / 2;
            if (i <= mid) { node = 2 * node; r = mid; } else { node = 2 * node + 1; l = mid + 1; }
        }
    }
};
```

```java
// Minimum Li Chao tree over fixed sorted distinct points xs; same contract as the C++ version.
static class LiChao {
    final int n;
    final long[] xs, M, B;
    final boolean[] has;
    LiChao(long[] pts) {
        n = pts.length; xs = pts;
        M = new long[4 * n]; B = new long[4 * n]; has = new boolean[4 * n];
    }
    void put(int node, int l, int r, long m, long b) {
        while (true) {
            if (!has[node]) { has[node] = true; M[node] = m; B[node] = b; return; }
            int mid = (l + r) >>> 1;
            boolean lef = m * xs[l] + b < M[node] * xs[l] + B[node];
            boolean mi = m * xs[mid] + b < M[node] * xs[mid] + B[node];
            if (mi) { long t = M[node]; M[node] = m; m = t; t = B[node]; B[node] = b; b = t; }
            if (l == r) return;
            if (lef != mi) { node = 2 * node; r = mid; }
            else { node = 2 * node + 1; l = mid + 1; }
        }
    }
    void seg(int node, int l, int r, int lq, int rq, long m, long b) {
        if (rq < l || r < lq) return;
        if (lq <= l && r <= rq) { put(node, l, r, m, b); return; }
        int mid = (l + r) >>> 1;
        seg(2 * node, l, mid, lq, rq, m, b);
        seg(2 * node + 1, mid + 1, r, lq, rq, m, b);
    }
    void addLine(long m, long b) { put(1, 0, n - 1, m, b); }
    void addSegment(int lq, int rq, long m, long b) { if (lq <= rq) seg(1, 0, n - 1, lq, rq, m, b); }
    long query(int i) {
        long res = Long.MAX_VALUE;
        int node = 1, l = 0, r = n - 1;
        while (true) {
            if (has[node]) res = Math.min(res, M[node] * xs[i] + B[node]);
            if (l == r) return res;
            int mid = (l + r) >>> 1;
            if (i <= mid) { node = 2 * node; r = mid; } else { node = 2 * node + 1; l = mid + 1; }
        }
    }
}
```

**3.4 Dynamic Li Chao over an integer range.** Online, no coordinate list; memory $O(\#\text{lines})$.

```cpp
// Minimum Li Chao tree over all integers x in [lo, hi], nodes created on demand.
// Each add() creates at most one node, so memory is O(#lines). Online: no coordinates needed.
struct DynLiChao {
    ll lo, hi;
    vector<ll> M, B;
    vector<int> L, R;                                    // child indices, -1 = none
    DynLiChao(ll lo_, ll hi_) : lo(lo_), hi(hi_) {}
    int make(ll m, ll b) {
        M.push_back(m); B.push_back(b); L.push_back(-1); R.push_back(-1);
        return (int)M.size() - 1;
    }
    void add(ll m, ll b) {
        if (M.empty()) { make(m, b); return; }           // node 0 is the root
        int node = 0; ll l = lo, r = hi;
        while (true) {
            ll mid = l + (r - l) / 2;                    // floor, also for negative l
            bool lef = m * l + b < M[node] * l + B[node];
            bool mi = m * mid + b < M[node] * mid + B[node];
            if (mi) { swap(M[node], m); swap(B[node], b); }
            if (l == r) return;
            if (lef != mi) {
                if (L[node] < 0) { int c = make(m, b); L[node] = c; return; }
                node = L[node]; r = mid;
            } else {
                if (R[node] < 0) { int c = make(m, b); R[node] = c; return; }
                node = R[node]; l = mid + 1;
            }
        }
    }
    ll query(ll x) const {                               // LLONG_MAX if no line yet
        ll res = LLONG_MAX, l = lo, r = hi;
        int node = M.empty() ? -1 : 0;
        while (node >= 0) {
            res = min(res, M[node] * x + B[node]);
            ll mid = l + (r - l) / 2;
            if (x <= mid) { node = L[node]; r = mid; } else { node = R[node]; l = mid + 1; }
        }
        return res;
    }
};
```

```java
// Minimum Li Chao tree over integers in [lo, hi]; nodes live in a growing array pool.
static class DynLiChao {
    final long lo, hi;
    long[] M = new long[16], B = new long[16];
    int[] L = new int[16], R = new int[16];
    int cnt = 0;                                         // node 0 is the root once cnt > 0
    DynLiChao(long lo, long hi) { this.lo = lo; this.hi = hi; }
    int make(long m, long b) {
        if (cnt == M.length) {
            int c = 2 * cnt;
            M = Arrays.copyOf(M, c); B = Arrays.copyOf(B, c); L = Arrays.copyOf(L, c); R = Arrays.copyOf(R, c);
        }
        M[cnt] = m; B[cnt] = b; L[cnt] = -1; R[cnt] = -1;
        return cnt++;
    }
    void add(long m, long b) {
        if (cnt == 0) { make(m, b); return; }
        int node = 0; long l = lo, r = hi;
        while (true) {
            long mid = l + (r - l) / 2;
            boolean lef = m * l + b < M[node] * l + B[node];
            boolean mi = m * mid + b < M[node] * mid + B[node];
            if (mi) { long t = M[node]; M[node] = m; m = t; t = B[node]; B[node] = b; b = t; }
            if (l == r) return;
            if (lef != mi) {
                if (L[node] < 0) { int c = make(m, b); L[node] = c; return; }
                node = L[node]; r = mid;
            } else {
                if (R[node] < 0) { int c = make(m, b); R[node] = c; return; }
                node = R[node]; l = mid + 1;
            }
        }
    }
    long query(long x) {
        long res = Long.MAX_VALUE, l = lo, r = hi;
        int node = cnt == 0 ? -1 : 0;
        while (node >= 0) {
            res = Math.min(res, M[node] * x + B[node]);
            long mid = l + (r - l) / 2;
            if (x <= mid) { node = L[node]; r = mid; } else { node = R[node]; l = mid + 1; }
        }
        return res;
    }
}
```

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| $O(n^2)$ DP, $n \ge 10^5$, cost contains $(s_i - s_j)^2$, $s_i \cdot s_j$, $a_i b_j$, "time = strength × factor" | CHT |
| After expanding, the term coupling $i$ and $j$ is a **product of one $i$-quantity and one $j$-quantity** | lines $m_j x + b_j$ queried at $x_i$ |
| Slopes come from a sorted quantity (prefix sums of positives, sorted heights) | deque |
| Queries also sorted | pointer, amortised $O(1)$ |
| Slopes or queries in arbitrary order | Li Chao (simplest) or LineContainer |
| State $j$ may only transition into a range of later states | Li Chao on segments |
| Same DP with $k$ layers ("split into $k$ groups") | CHT per layer, $O(nk)$ — or [Aliens](06-aliens-trick-wqs-binary-search.md) to drop $k$ |
| Coupling term is $\sqrt{\cdot}$, $|\cdot|^3$, distinct counts … (not a product) | not CHT: try [D&C](03-divide-and-conquer-optimization.md) / [Knuth](04-knuth-optimization.md) via monotone optima |
| DP on a tree, lines inherited from ancestors | CHT with rollback, or Li Chao merging (§7) |

**Commonly confused with:** the [monotonic queue](01-prefix-sum-and-monotonic-queue-optimization.md) (that is CHT with all slopes equal); D&C optimisation (works for *any* cost with the quadrangle inequality, including squared costs — slower by a log but needs no algebra); geometric [convex hull](../14-Geometry/04-convex-hull-and-rotating-calipers.md) (the dual object: lines $\leftrightarrow$ points $(m, b)$; the lower envelope is a lower hull of the points, which is why the bad-line test is a cross product).

## 5. Worked examples (graded)

### Example 1 — Frog 3  ·  ★ ≈1900 (est.)

- **Source:** [AtCoder DP Z · Frog 3](https://atcoder.jp/contests/dp/tasks/dp_z)
- **Difficulty:** ≈1900 (est.; no rating in the tool for the Educational DP contest).
- **Problem:** $N \le 2\cdot10^5$ stones with strictly increasing heights $h_i \le 10^6$. From stone $i$ the frog may jump to any $j > i$, paying $(h_j - h_i)^2 + C$ ($C \le 10^{12}$). Minimum cost from stone $1$ to stone $N$.
- **Thinking from first principles:** $dp[i] = \min_{j<i} dp[j] + (h_i - h_j)^2 + C$ is $O(N^2) = 4\cdot10^{10}$. Expand: $dp[i] = h_i^2 + C + \min_j(-2h_j \cdot h_i + dp[j] + h_j^2)$. Lines with slope $-2h_j$ — **decreasing** because heights increase — queried at $h_i$ — **increasing**. Both monotone: the deque with a front pointer, $O(N)$.

<details><summary>Solution</summary>

Insert line $j$ after computing $dp[j]$; before computing $dp[i]$ advance the front while the next line is at least as good at $h_i$. Overflow check: intercept differences are $\le 3\cdot10^{12}$ (one jump from stone 1 bounds every $dp$), slope differences $\le 2\cdot10^6$, so products stay below $6\cdot10^{18}$ — plain 64-bit arithmetic is exact here (state such bounds explicitly in your own code; Example 2 is where they fail). $O(N)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    ll C;
    cin >> n >> C;
    vector<ll> h(n), M(n), B(n);                         // hull = lines [head, tail)
    for (auto& v : h) cin >> v;
    int head = 0, tail = 0;
    // |B diff| <= 3e12 and |M diff| <= 2e6, so the products stay below 6e18: 64 bits suffice
    auto add = [&](ll m, ll b) {
        while (tail - head >= 2 &&
               (b - B[tail - 2]) * (M[tail - 2] - M[tail - 1]) <= (B[tail - 1] - B[tail - 2]) * (M[tail - 2] - m))
            tail--;
        M[tail] = m; B[tail] = b; tail++;
    };
    ll dp = 0;                                           // dp of stone 1
    add(-2 * h[0], h[0] * h[0]);
    for (int i = 1; i < n; i++) {
        ll x = h[i];                                     // queries increase: pop dead lines in front
        while (tail - head >= 2 && M[head + 1] * x + B[head + 1] <= M[head] * x + B[head]) head++;
        dp = M[head] * x + B[head] + x * x + C;
        add(-2 * x, dp + x * x);
    }
    cout << dp << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long[] M, B;
    static int head = 0, tail = 0;

    static void add(long m, long b) {                    // products < 6e18 here: long is enough
        while (tail - head >= 2
               && (b - B[tail - 2]) * (M[tail - 2] - M[tail - 1]) <= (B[tail - 1] - B[tail - 2]) * (M[tail - 2] - m))
            tail--;
        M[tail] = m; B[tail] = b; tail++;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long C = in.nextLong();
        long[] h = new long[n];
        for (int i = 0; i < n; i++) h[i] = in.nextLong();
        M = new long[n]; B = new long[n];
        long dp = 0;
        add(-2 * h[0], h[0] * h[0]);
        for (int i = 1; i < n; i++) {
            long x = h[i];
            while (tail - head >= 2 && M[head + 1] * x + B[head + 1] <= M[head] * x + B[head]) head++;
            dp = M[head] * x + B[head] + x * x + C;
            add(-2 * x, dp + x * x);
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(dp);
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
5 6
1 2 3 4 5
out:
20
-->
<!-- test
in:
2 1000000000000
500000 1000000
out:
1250000000000
-->
<!-- test
in:
8 5
1 3 4 5 10 11 12 13
out:
62
-->

### Example 2 — Kalila and Dimna in the Logging Industry  ·  ★ 2100

- **Source:** [CF 319C · Kalila and Dimna in the Logging Industry](https://codeforces.com/problemset/problem/319/C) — 2100
- **Difficulty:** 2100
- **Problem:** $n \le 10^5$ trees with heights $a_1 = 1 < a_2 < \dots < a_n \le 10^9$ and costs $b_1 > b_2 > \dots > b_n = 0$. Each use of the chainsaw lowers one tree by $1$; after every use the saw must be recharged, costing $b_k$ where $k$ is the largest index of a tree already cut to height $0$ (the saw starts charged). Minimise the total cost of cutting all trees down.
- **Thinking from first principles:** once tree $n$ is down, recharges are free, so only the chain of trees we fully cut *before* tree $n$ matters. If the last fully cut tree is $j$ and we next fully cut tree $i > j$, each of the $a_i$ cuts on tree $i$ is preceded by a recharge at price $b_j$ (tree $i$ is not finished until its last cut). Tree $1$ has height $1$ and is cut with the initial charge. So $dp[1] = 0$, $dp[i] = \min_{j<i} dp[j] + b_j a_i$, answer $dp[n]$. Lines: slope $b_j$ (decreasing), intercept $dp[j]$, queries $a_i$ (increasing) — the monotone case again. (A brute-force simulation of the real recharge process over all cutting orders agrees with this DP on small inputs; we checked.)

<details><summary>Solution</summary>

Same deque as Example 1, but the numbers are now large: $dp \le b_1 a_n \le 10^{18}$, so the bad-line test multiplies values up to $10^{18}$ by slope differences up to $10^9$ — $10^{27}$, far beyond 64 bits. C++ uses `__int128`; Java compares the 128-bit products exactly with `Math.multiplyHigh` (high words signed, low words unsigned). Evaluations $b_j a_i + dp_j \le 2\cdot10^{18}$ fit. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<ll> a(n), b(n), M(n), B(n);
    for (auto& v : a) cin >> v;
    for (auto& v : b) cin >> v;
    int head = 0, tail = 0;
    auto add = [&](ll m, ll c) {                         // |B diff| ~1e18, |M diff| ~1e9: needs 128 bits
        while (tail - head >= 2 &&
               (__int128)(c - B[tail - 2]) * (M[tail - 2] - M[tail - 1]) <=
               (__int128)(B[tail - 1] - B[tail - 2]) * (M[tail - 2] - m))
            tail--;
        M[tail] = m; B[tail] = c; tail++;
    };
    ll dp = 0;                                           // tree 1 falls on the initial charge
    add(b[0], 0);
    for (int i = 1; i < n; i++) {
        ll x = a[i];                                     // heights increase: monotone queries
        while (tail - head >= 2 && M[head + 1] * x + B[head + 1] <= M[head] * x + B[head]) head++;
        dp = M[head] * x + B[head];
        add(b[i], dp);                                   // slopes b[i] decrease: monotone inserts
    }
    cout << dp << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long[] M, B;
    static int head = 0, tail = 0;

    // sign(a*b - c*d), exact: compare the signed high words, then the unsigned low words
    static int cmpMul(long a, long b, long c, long d) {
        long h1 = Math.multiplyHigh(a, b), h2 = Math.multiplyHigh(c, d);
        if (h1 != h2) return h1 < h2 ? -1 : 1;
        return Long.compareUnsigned(a * b, c * d);
    }

    static void add(long m, long c) {
        while (tail - head >= 2
               && cmpMul(c - B[tail - 2], M[tail - 2] - M[tail - 1], B[tail - 1] - B[tail - 2], M[tail - 2] - m) <= 0)
            tail--;
        M[tail] = m; B[tail] = c; tail++;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long[] a = new long[n], b = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        for (int i = 0; i < n; i++) b[i] = in.nextLong();
        M = new long[n]; B = new long[n];
        long dp = 0;
        add(b[0], 0);
        for (int i = 1; i < n; i++) {
            long x = a[i];
            while (tail - head >= 2 && M[head + 1] * x + B[head + 1] <= M[head] * x + B[head]) head++;
            dp = M[head] * x + B[head];
            add(b[i], dp);
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(dp);
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
5
1 2 3 4 5
5 4 3 2 0
out:
25
-->
<!-- test
in:
6
1 2 3 10 20 30
6 5 4 3 2 0
out:
138
-->
<!-- test
in:
1
1
0
out:
0
-->
<!-- test
in:
2
1 1000000000
1000000000 0
out:
1000000000000000000
-->

### Example 3 — Monster Game II  ·  ★ ≈2200 (est.)

- **Source:** [CSES 2085 · Monster Game II](https://cses.fi/problemset/task/2085)
- **Difficulty:** ≈2200 (est.)
- **Problem:** $n \le 2\cdot10^5$ levels; you start with skill factor $x$. Level $i$ has a monster of strength $s_i$; killing it takes $s_i \cdot f$ time where $f$ is your current factor, and afterwards your factor becomes $f_i$. You may skip any monster except the last. All values $\le 10^6$, **no ordering** among them. Minimise the total time.
- **Thinking from first principles:** $dp[i]$ = minimum time with monster $i$ killed last: $dp[i] = \min\big(x s_i, \min_{j<i} dp[j] + f_j s_i\big)$. Treat the start as line $j = 0$ with slope $x$ and intercept $0$. Lines with slope $f_j$, queries at $s_i$ — but now neither is sorted ([Monster Game I](https://cses.fi/problemset/task/2084) guarantees both, and the deque works there). The deque fails because a new line can land in the middle of the hull. Two fixes: a Li Chao tree over $x \in [1, 10^6]$, or the LineContainer.

<details><summary>Solution</summary>

**(a) Dynamic Li Chao** over $[1, 10^6]$: insert $(f_i, dp_i)$ after computing $dp_i = $ query$(s_i)$. $O(n \log 10^6)$, values $\le 2\cdot10^{17}$, no division anywhere.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

struct DynLiChao {
    ll lo, hi;
    vector<ll> M, B;
    vector<int> L, R;                                    // child indices, -1 = none
    DynLiChao(ll lo_, ll hi_) : lo(lo_), hi(hi_) {}
    int make(ll m, ll b) {
        M.push_back(m); B.push_back(b); L.push_back(-1); R.push_back(-1);
        return (int)M.size() - 1;
    }
    void add(ll m, ll b) {
        if (M.empty()) { make(m, b); return; }           // node 0 is the root
        int node = 0; ll l = lo, r = hi;
        while (true) {
            ll mid = l + (r - l) / 2;                    // floor, also for negative l
            bool lef = m * l + b < M[node] * l + B[node];
            bool mi = m * mid + b < M[node] * mid + B[node];
            if (mi) { swap(M[node], m); swap(B[node], b); }
            if (l == r) return;
            if (lef != mi) {
                if (L[node] < 0) { int c = make(m, b); L[node] = c; return; }
                node = L[node]; r = mid;
            } else {
                if (R[node] < 0) { int c = make(m, b); R[node] = c; return; }
                node = R[node]; l = mid + 1;
            }
        }
    }
    ll query(ll x) const {                               // LLONG_MAX if no line yet
        ll res = LLONG_MAX, l = lo, r = hi;
        int node = M.empty() ? -1 : 0;
        while (node >= 0) {
            res = min(res, M[node] * x + B[node]);
            ll mid = l + (r - l) / 2;
            if (x <= mid) { node = L[node]; r = mid; } else { node = R[node]; l = mid + 1; }
        }
        return res;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    ll x;
    cin >> n >> x;
    vector<ll> s(n), f(n);
    for (auto& v : s) cin >> v;
    for (auto& v : f) cin >> v;
    DynLiChao t(1, 1000000);                             // queries are strengths s_i in [1, 1e6]
    t.add(x, 0);                                         // "j = 0": factor x, cost so far 0
    ll dp = 0;
    for (int i = 0; i < n; i++) {
        dp = t.query(s[i]);                              // min_j dp_j + f_j * s_i
        t.add(f[i], dp);
    }
    cout << dp << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static class DynLiChao {
        final long lo, hi;
        long[] M = new long[16], B = new long[16];
        int[] L = new int[16], R = new int[16];
        int cnt = 0;                                         // node 0 is the root once cnt > 0
        DynLiChao(long lo, long hi) { this.lo = lo; this.hi = hi; }
        int make(long m, long b) {
            if (cnt == M.length) {
                int c = 2 * cnt;
                M = Arrays.copyOf(M, c); B = Arrays.copyOf(B, c); L = Arrays.copyOf(L, c); R = Arrays.copyOf(R, c);
            }
            M[cnt] = m; B[cnt] = b; L[cnt] = -1; R[cnt] = -1;
            return cnt++;
        }
        void add(long m, long b) {
            if (cnt == 0) { make(m, b); return; }
            int node = 0; long l = lo, r = hi;
            while (true) {
                long mid = l + (r - l) / 2;
                boolean lef = m * l + b < M[node] * l + B[node];
                boolean mi = m * mid + b < M[node] * mid + B[node];
                if (mi) { long t = M[node]; M[node] = m; m = t; t = B[node]; B[node] = b; b = t; }
                if (l == r) return;
                if (lef != mi) {
                    if (L[node] < 0) { int c = make(m, b); L[node] = c; return; }
                    node = L[node]; r = mid;
                } else {
                    if (R[node] < 0) { int c = make(m, b); R[node] = c; return; }
                    node = R[node]; l = mid + 1;
                }
            }
        }
        long query(long x) {
            long res = Long.MAX_VALUE, l = lo, r = hi;
            int node = cnt == 0 ? -1 : 0;
            while (node >= 0) {
                res = Math.min(res, M[node] * x + B[node]);
                long mid = l + (r - l) / 2;
                if (x <= mid) { node = L[node]; r = mid; } else { node = R[node]; l = mid + 1; }
            }
            return res;
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long x = in.nextLong();
        long[] s = new long[n], f = new long[n];
        for (int i = 0; i < n; i++) s[i] = in.nextLong();
        for (int i = 0; i < n; i++) f[i] = in.nextLong();
        DynLiChao t = new DynLiChao(1, 1000000);
        t.add(x, 0);
        long dp = 0;
        for (int i = 0; i < n; i++) {
            dp = t.query(s[i]);
            t.add(f[i], dp);
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(dp);
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

**(b) LineContainer**: same loop, $O(n \log n)$ amortised; breakpoints via exact floor division.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

struct LineContainer {
    static constexpr ll INF = LLONG_MAX;
    struct Line {
        ll m, b;
        mutable ll p;                                    // not part of the ordering, safe to mutate
        bool operator<(const Line& o) const { return m > o.m; }
        bool operator<(ll x) const { return p < x; }     // used by lower_bound(x) in query
    };
    multiset<Line, less<>> s;                            // less<> enables lookup by ll
    using It = multiset<Line, less<>>::iterator;
    static ll floorDiv(ll a, ll b) { return a / b - ((a % b != 0) && ((a < 0) != (b < 0))); }
    // set x.p against its right neighbour y; true iff y now owns no integer (x.p >= y.p)
    bool fix(It x, It y) {
        if (y == s.end()) { x->p = INF; return false; }
        x->p = floorDiv(y->b - x->b, x->m - y->m);       // x <= y exactly for t <= this
        return x->p >= y->p;
    }
    void add(ll m, ll b) {
        auto same = s.find(Line{m, b, 0});
        if (same != s.end()) {                           // equal slope: keep the lower line
            if (same->b <= b) return;
            s.erase(same);
        }
        auto y = s.insert({m, b, 0});
        auto z = next(y);
        while (fix(y, z)) z = s.erase(z);                // right neighbours buried by the new line
        if (y == s.begin()) return;
        auto x = prev(y);
        if (fix(x, y)) { y = s.erase(y); fix(x, y); }    // the new line itself is useless
        while (x != s.begin()) {                         // left neighbours buried by the new line
            auto w = prev(x);
            if (w->p < x->p) break;
            x = s.erase(x);
            fix(w, x);
            x = w;
        }
    }
    ll query(ll x) const {                               // requires at least one line
        auto l = s.lower_bound(x);                       // first line with p >= x
        return l->m * x + l->b;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    ll x;
    cin >> n >> x;
    vector<ll> s(n), f(n);
    for (auto& v : s) cin >> v;
    for (auto& v : f) cin >> v;
    LineContainer hull;
    hull.add(x, 0);
    ll dp = 0;
    for (int i = 0; i < n; i++) {
        dp = hull.query(s[i]);
        hull.add(f[i], dp);
    }
    cout << dp << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static class LineContainer {
        static final long INF = Long.MAX_VALUE;
        static class Line {
            final long m, b; long p; final boolean q;
            Line(long m, long b, long p, boolean q) { this.m = m; this.b = b; this.p = p; this.q = q; }
        }
        final TreeSet<Line> s = new TreeSet<>((u, v) -> {
            if (u.q) return u.p <= v.p ? -1 : 1;             // never 0: probes are not stored
            if (v.q) return v.p <= u.p ? 1 : -1;
            return Long.compare(v.m, u.m);                   // real lines: slope descending
        });
        // set x.p against its right neighbour y (null = none); true iff y owns no integer now
        boolean fix(Line x, Line y) {
            if (y == null) { x.p = INF; return false; }
            x.p = Math.floorDiv(y.b - x.b, x.m - y.m);
            return x.p >= y.p;
        }
        void add(long m, long b) {
            Line y = new Line(m, b, 0, false);
            Line same = s.ceiling(y);                        // equal slope compares as equal
            if (same != null && same.m == m) {
                if (same.b <= b) return;
                s.remove(same);
            }
            s.add(y);
            Line z = s.higher(y);
            while (fix(y, z)) { s.remove(z); z = s.higher(y); }
            Line x = s.lower(y);
            if (x == null) return;
            if (fix(x, y)) { s.remove(y); fix(x, s.higher(x)); }
            Line w;
            while ((w = s.lower(x)) != null && w.p >= x.p) {
                s.remove(x);
                fix(w, s.higher(w));
                x = w;
            }
        }
        long query(long x) {                                 // requires at least one line
            Line l = s.ceiling(new Line(0, 0, x, true));
            return l.m * x + l.b;
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long x = in.nextLong();
        long[] s = new long[n], f = new long[n];
        for (int i = 0; i < n; i++) s[i] = in.nextLong();
        for (int i = 0; i < n; i++) f[i] = in.nextLong();
        LineContainer hull = new LineContainer();
        hull.add(x, 0);
        long dp = 0;
        for (int i = 0; i < n; i++) {
            dp = hull.query(s[i]);
            hull.add(f[i], dp);
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(dp);
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

Both versions were stress-tested against an exhaustive search over all subsets of monsters to kill.

</details>

<!-- test
in:
5 100
20 70 40 10 50
40 60 100 30 10
out:
2500
-->
<!-- test
in:
1 7
5
3
out:
35
-->
<!-- test
in:
4 1000000
1000000 1 1000000 1000000
1 1000000 1 1
out:
1000000000000
-->
<!-- test
in:
3 2
5 6 7
3 1 1
out:
14
-->

### Example 4 — The Fair Nut and Rectangles  ·  ★ 2400

- **Source:** [CF 1083E · The Fair Nut and Rectangles](https://codeforces.com/problemset/problem/1083/E) — 2400
- **Difficulty:** 2400
- **Problem:** $n \le 10^6$ rectangles with corners $(0,0)$ and $(x_i, y_i)$, $x_i, y_i \le 10^9$, no rectangle nested in another; each has a price $a_i \le x_i y_i$. Choose a subset maximising (area of the union) $-$ (sum of prices).
- **Thinking from first principles:** no nesting means that sorting by $x$ increasing sorts $y$ decreasing. Take the chosen rectangles in that order. When rectangle $i$ is added after the previously chosen $j$, the union of all earlier chosen rectangles intersected with rectangle $i$ is exactly $[0, x_j] \times [0, y_i]$ (they are all at most as wide as $x_j$ and taller than $y_i$), so $i$ adds $x_i y_i - x_j y_i$. Hence $dp[i] = x_i y_i - a_i + \max\big(0, \max_{j<i} (dp[j] - x_j y_i)\big)$ — $O(n^2)$ for $n = 10^6$ is hopeless. Inside the max: lines of slope $-x_j$ and intercept $dp_j$ queried at $y_i$, a **maximum** with queries in decreasing order. Convert it to the standard case: $\max_j(dp_j - x_j y_i) = -\min_j\big((-x_j)\,q + (-dp_j)\big)$ with $q = -y_i$. Now slopes $-x_j$ decrease and queries $q$ increase: the monotone min-deque.

<details><summary>Solution</summary>

Sort by $x$; Java packs $(x, \text{index})$ into one `long` and shuffles before `Arrays.sort` (no adversarial quicksort input, no boxing). Start the hull with the line $(0, 0)$ = "nothing chosen yet", which also provides the $\max(0, \cdot)$. Products in the bad-line test reach $10^{18} \cdot 10^9$: 128-bit comparisons. $O(n \log n)$ for the sort, $O(n)$ for the DP.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<array<ll, 3>> r(n);
    for (auto& [x, y, a] : r) cin >> x >> y >> a;
    sort(r.begin(), r.end());                            // x increasing => y decreasing (no nesting)
    // max_j (dp_j - x_j*y) = -min_j ((-x_j)*(-y) + (-dp_j)): min hull, slopes -x_j decrease,
    // queries -y increase -- exactly the monotone deque case
    vector<ll> M(n + 1), B(n + 1);
    int head = 0, tail = 0;
    auto add = [&](ll m, ll b) {
        while (tail - head >= 2 &&
               (__int128)(b - B[tail - 2]) * (M[tail - 2] - M[tail - 1]) <=
               (__int128)(B[tail - 1] - B[tail - 2]) * (M[tail - 2] - m))
            tail--;
        M[tail] = m; B[tail] = b; tail++;
    };
    add(0, 0);                                           // "nothing chosen yet": x_0 = 0, dp_0 = 0
    ll ans = 0;
    for (auto& [x, y, a] : r) {
        ll q = -y;
        while (tail - head >= 2 && M[head + 1] * q + B[head + 1] <= M[head] * q + B[head]) head++;
        ll dp = x * y - a - (M[head] * q + B[head]);
        ans = max(ans, dp);
        add(-x, -dp);
    }
    cout << ans << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long[] M, B;
    static int head = 0, tail = 0;

    static int cmpMul(long a, long b, long c, long d) {  // sign(a*b - c*d), exact
        long h1 = Math.multiplyHigh(a, b), h2 = Math.multiplyHigh(c, d);
        if (h1 != h2) return h1 < h2 ? -1 : 1;
        return Long.compareUnsigned(a * b, c * d);
    }

    static void add(long m, long b) {
        while (tail - head >= 2
               && cmpMul(b - B[tail - 2], M[tail - 2] - M[tail - 1], B[tail - 1] - B[tail - 2], M[tail - 2] - m) <= 0)
            tail--;
        M[tail] = m; B[tail] = b; tail++;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long[] x = new long[n], y = new long[n], a = new long[n], key = new long[n];
        for (int i = 0; i < n; i++) {
            x[i] = in.nextLong(); y[i] = in.nextLong(); a[i] = in.nextLong();
            key[i] = x[i] << 20 | i;                     // x < 2^30, i < 2^20: sort one long[]
        }
        Random rnd = new Random(12345);                  // shuffle: no adversarial quicksort input
        for (int i = n - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long t = key[i]; key[i] = key[j]; key[j] = t; }
        Arrays.sort(key);
        M = new long[n + 1]; B = new long[n + 1];
        add(0, 0);
        long ans = 0;
        for (int k = 0; k < n; k++) {
            int i = (int) (key[k] & ((1 << 20) - 1));
            long q = -y[i];
            while (tail - head >= 2 && M[head + 1] * q + B[head + 1] <= M[head] * q + B[head]) head++;
            long dp = x[i] * y[i] - a[i] - (M[head] * q + B[head]);
            ans = Math.max(ans, dp);
            add(-x[i], -dp);
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(ans);
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
3
4 4 8
1 5 0
5 2 10
out:
9
-->
<!-- test
in:
4
6 2 4
1 6 2
2 4 3
5 3 8
out:
10
-->
<!-- test
in:
1
1000000000 1000000000 0
out:
1000000000000000000
-->
<!-- test
in:
2
1 5 5
5 1 4
out:
1
-->
<!-- test
in:
3
2 3 1
1 9 2
3 1 0
out:
10
-->

### Example 5 — Frog with limited jumps (Li Chao on segments)  ·  ★ ≈2300 (est.)

- **Source:** Original problem.
- **Difficulty:** ≈2300 (est.)
- **Problem:** $n \le 2\cdot10^5$ stones with strictly increasing heights $h_i \le 10^6$. From stone $i$ the frog may jump to any stone $j$ with $i < j \le i + r_i$ ($1 \le r_i \le n$), paying $(h_j - h_i)^2$. Print the minimum cost to reach stone $n$ from stone $1$, or $-1$.
- **Thinking from first principles:** the cost expands exactly as in Frog 3, so stone $i$ is the line $(-2h_i,\; dp_i + h_i^2)$. But this line may only answer queries of stones $i+1 .. i + r_i$ — a line **segment** over the index axis. A deque can't expire a line "from the middle"; a Li Chao tree over the stone indices (evaluated at $h$) can insert it into exactly the canonical nodes covering $[i+1, i+r_i]$.

<details><summary>Solution</summary>

Li Chao over the points $h_1 < \dots < h_n$. For $i = 1..n$: $dp_i = h_i^2 + $ query$(i)$ (or unreachable if no segment covers $i$; an unreachable stone inserts nothing), then add the segment of line $i$ on indices $[i+1, \min(n, i + r_i)]$. $O(n \log^2 n)$. Correctness: the Li Chao invariant holds inside each canonical subtree, and a query at index $t$ visits every canonical node whose interval contains $t$. Stress-tested against the $O(n^2)$ DP.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

struct LiChao {
    int n;
    vector<ll> xs, M, B;
    vector<char> has;                                    // empty-node flag, no INF lines
    explicit LiChao(const vector<ll>& pts)
        : n(pts.size()), xs(pts), M(4 * pts.size()), B(4 * pts.size()), has(4 * pts.size(), 0) {}
    void put(int node, int l, int r, ll m, ll b) {       // insert into the subtree of node
        while (true) {
            if (!has[node]) { has[node] = 1; M[node] = m; B[node] = b; return; }
            int mid = (l + r) / 2;
            bool lef = m * xs[l] + b < M[node] * xs[l] + B[node];
            bool mi = m * xs[mid] + b < M[node] * xs[mid] + B[node];
            if (mi) { swap(M[node], m); swap(B[node], b); }   // node keeps the winner at mid
            if (l == r) return;
            if (lef != mi) { node = 2 * node; r = mid; }     // loser can win only on the left
            else { node = 2 * node + 1; l = mid + 1; }       // ... or only on the right
        }
    }
    void seg(int node, int l, int r, int lq, int rq, ll m, ll b) {
        if (rq < l || r < lq) return;
        if (lq <= l && r <= rq) { put(node, l, r, m, b); return; }
        int mid = (l + r) / 2;
        seg(2 * node, l, mid, lq, rq, m, b);
        seg(2 * node + 1, mid + 1, r, lq, rq, m, b);
    }
    void addLine(ll m, ll b) { put(1, 0, n - 1, m, b); }
    void addSegment(int lq, int rq, ll m, ll b) { if (lq <= rq) seg(1, 0, n - 1, lq, rq, m, b); }
    ll query(int i) const {
        ll res = LLONG_MAX;
        int node = 1, l = 0, r = n - 1;
        while (true) {                                   // empty nodes are skipped, not cut
            if (has[node]) res = min(res, M[node] * xs[i] + B[node]);
            if (l == r) return res;
            int mid = (l + r) / 2;
            if (i <= mid) { node = 2 * node; r = mid; } else { node = 2 * node + 1; l = mid + 1; }
        }
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<ll> h(n);
    vector<int> r(n);
    for (auto& v : h) cin >> v;
    for (auto& v : r) cin >> v;
    LiChao t(h);                                         // domain: stone indices, evaluated at h
    ll dp = 0;                                           // dp of stone 1
    for (int i = 0; i < n; i++) {
        if (i > 0) {
            ll v = t.query(i);
            if (v == LLONG_MAX) continue;                // nobody can reach stone i
            dp = v + h[i] * h[i];
        }
        // line of stone i is valid only on the stones it can jump to
        t.addSegment(i + 1, (int)min<ll>(n - 1, (ll)i + r[i]), -2 * h[i], dp + h[i] * h[i]);
        if (i == n - 1) { cout << dp << "\n"; return 0; }
    }
    cout << -1 << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static class LiChao {
        final int n;
        final long[] xs, M, B;
        final boolean[] has;
        LiChao(long[] pts) {
            n = pts.length; xs = pts;
            M = new long[4 * n]; B = new long[4 * n]; has = new boolean[4 * n];
        }
        void put(int node, int l, int r, long m, long b) {
            while (true) {
                if (!has[node]) { has[node] = true; M[node] = m; B[node] = b; return; }
                int mid = (l + r) >>> 1;
                boolean lef = m * xs[l] + b < M[node] * xs[l] + B[node];
                boolean mi = m * xs[mid] + b < M[node] * xs[mid] + B[node];
                if (mi) { long t = M[node]; M[node] = m; m = t; t = B[node]; B[node] = b; b = t; }
                if (l == r) return;
                if (lef != mi) { node = 2 * node; r = mid; }
                else { node = 2 * node + 1; l = mid + 1; }
            }
        }
        void seg(int node, int l, int r, int lq, int rq, long m, long b) {
            if (rq < l || r < lq) return;
            if (lq <= l && r <= rq) { put(node, l, r, m, b); return; }
            int mid = (l + r) >>> 1;
            seg(2 * node, l, mid, lq, rq, m, b);
            seg(2 * node + 1, mid + 1, r, lq, rq, m, b);
        }
        void addLine(long m, long b) { put(1, 0, n - 1, m, b); }
        void addSegment(int lq, int rq, long m, long b) { if (lq <= rq) seg(1, 0, n - 1, lq, rq, m, b); }
        long query(int i) {
            long res = Long.MAX_VALUE;
            int node = 1, l = 0, r = n - 1;
            while (true) {
                if (has[node]) res = Math.min(res, M[node] * xs[i] + B[node]);
                if (l == r) return res;
                int mid = (l + r) >>> 1;
                if (i <= mid) { node = 2 * node; r = mid; } else { node = 2 * node + 1; l = mid + 1; }
            }
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long[] h = new long[n];
        int[] r = new int[n];
        for (int i = 0; i < n; i++) h[i] = in.nextLong();
        for (int i = 0; i < n; i++) r[i] = in.nextInt();
        LiChao t = new LiChao(h);
        long dp = 0;
        long ans = -1;
        for (int i = 0; i < n; i++) {
            if (i > 0) {
                long v = t.query(i);
                if (v == Long.MAX_VALUE) continue;
                dp = v + h[i] * h[i];
            }
            t.addSegment(i + 1, (int) Math.min(n - 1, (long) i + r[i]), -2 * h[i], dp + h[i] * h[i]);
            if (i == n - 1) ans = dp;
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(ans);
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
5
1 3 4 7 8
2 1 3 1 1
out:
15
-->
<!-- test
in:
4
1 2 3 4
1 1 1 1
out:
3
-->
<!-- test
in:
4
1 10 20 21
3 1 1 1
out:
182
-->
<!-- test
in:
1
5
1
out:
0
-->
<!-- test
in:
3
1 2 3
1 5 5
out:
2
-->

## 6. Tricks, pitfalls and things to remember

1. **Expand the cost on paper first.** Write it as (term in $j$)·(term in $i$) + (term in $j$) + (term in $i$). If you can't, it isn't CHT — don't force it.
2. **Check both monotonicities separately** (slopes on insertion, $x$ on query) and in which direction. Sorted slopes + unsorted queries = binary search on the hull; unsorted slopes = Li Chao / LineContainer.
3. **Overflow in the bad-line test is the #1 CHT bug.** Bound $|b_2 - b_1| \cdot |m_1 - m_3|$ explicitly. Over $9.2\cdot10^{18}$: `__int128` in C++, the `multiplyHigh` comparison in Java. `long double` usually works up to about $10^{19}$ products of exact integers but is not exact — and Java has no `long double`.
4. **Equal slopes** divide by zero in intersection formulas. Keep only the lower intercept before running the hull test (all four implementations above do this).
5. **`<=` vs `<` in the pop condition.** With `<=` you drop lines that tie at a single point; both are correct for the minimum value, `<=` keeps the hull smaller. For *argmin* reconstruction (or Aliens tie-breaking) decide deliberately.
6. **Query pointer + binary search don't mix** on the same hull object unless you understand that the pointer has discarded lines on the left.
7. **Max hull:** negate slopes and intercepts, run a min hull, negate the answer. Fewer sign bugs than rewriting comparisons.
8. **Li Chao domain:** queries must be inside $[lo, hi]$ (dynamic) or exactly at the given `xs` (static). With static points, `xs` must be **sorted and distinct**, or the crossing argument breaks.
9. **Li Chao evaluation overflow:** $m x + b$ must fit in 64 bits for *every* $x$ in the domain, not just the queries — the insertion evaluates at node endpoints and midpoints. Shrink the domain to the real query range.
10. **Li Chao "empty" nodes:** don't initialise nodes with a line $(0, \infty)$ and then evaluate $0 \cdot x + \infty$ plus something; use a has-line flag as in §3 or an $\infty$ that you never add to.
11. **C++ `/` truncates toward zero**, so the LineContainer needs a real floor division for negative numerators. Java has `Math.floorDiv`.
12. **Java `TreeSet` comparators must be consistent**; the LineContainer probe trick (§3.2) never returns 0 for probes so it is never stored or confused with a real line.
13. **Java recursion** in Li Chao segment insertion is only $O(\log n)$ deep — fine; but avoid `ArrayList<Long>` lines (boxing): parallel `long[]` arrays.
14. **Don't forget the "start" line** ($j = 0$: slope $x$ in Monster Game, $(0,0)$ in Fair Nut) — it's where the base case of the DP lives.

## 7. Going further (toward 2400–2600+)

- **CHT on a tree.** Lines come from ancestors on the root path. Keep one array hull; when entering a child, binary search where the new line goes, save the overwritten slot and old size, restore on exit — $O(\log n)$ per node with $O(1)$ rollback. Alternative: persistent Li Chao.
- **Li Chao merging (small-to-large).** For "dp[v] = min over descendants $u$ of $(dp_u + a_v b_u)$" merge children's Li Chao trees; with dynamic nodes, merging the smaller into the larger costs $O(n \log^2 n)$ in total, and a genuine node-by-node merge is $O(n \log n)$ amortised (CF 932F).
- **Layered CHT.** "Split into $k$ groups" with squared costs: one hull per layer, $O(nk)$. Usually you can then drop $k$ with the [Aliens trick](06-aliens-trick-wqs-binary-search.md) — CHT inside a binary search over $\lambda$.
- **CHT inside D&C / CDQ.** When lines are inserted in one order and queried in another with a validity window, divide and conquer on time: build a hull for the left half, query it from the right half ([CDQ](../16-IGM-Frontier/01-offline-techniques-cdq-parallel-binary-search.md)).
- **Kinetic segment tree** 🔴: maintain $\max_i (a_i t + b_i)$ under point updates while the global $t$ only increases — amortised analysis of "breakpoint events". Appears in IGM-level problems with "add $x$ to all, query max of $a_i \cdot x + b_i$".
- **Duality with geometry.** Line $y = mx + b$ ↔ point $(m, b)$; querying at $x$ = finding the point minimising the dot product with $(x, 1)$; the hull of lines is the lower convex hull of points ([convex hull](../14-Geometry/04-convex-hull-and-rotating-calipers.md)). Half-plane intersection ([sweep / half-plane](../14-Geometry/05-sweep-closest-pair-and-half-plane.md)) generalises the envelope.
- **Non-linear "lines".** Li Chao works for any family where two members cross at most once (e.g. $a_j + \sqrt{x - b_j}$ shapes, or functions of the form $f(x - c_j) + d_j$ for convex $f$ in some ranges). The single-crossing property is the only thing the proof used.

## 8. Practice ladder

**1900–2100**
- [ ] [AtCoder DP Z · Frog 3](https://atcoder.jp/contests/dp/tasks/dp_z) — monotone deque, ≈1900 (est.) (Example 1)
- [ ] [CSES 2084 · Monster Game I](https://cses.fi/problemset/task/2084) — both monotone, ≈2000 (est.)
- [ ] [CF 319C · Kalila and Dimna in the Logging Industry](https://codeforces.com/problemset/problem/319/C) — 2100 — overflow-safe deque (Example 2)

**2100–2400**
- [ ] [CSES 2085 · Monster Game II](https://cses.fi/problemset/task/2085) — arbitrary order, ≈2200 (est.) (Example 3)
- [ ] [CSES 2086 · Subarray Squares](https://cses.fi/problemset/task/2086) — one hull per layer, ≈2200 (est.)
- [ ] [CF 1083E · The Fair Nut and Rectangles](https://codeforces.com/problemset/problem/1083/E) — 2400 — sort, then max hull (Example 4)
- [ ] [CF 311B · Cats Transport](https://codeforces.com/problemset/problem/311/B) — 2400 — sort the waiting-time keys, layered hull
- [ ] [CF 643C · Levels and Regions](https://codeforces.com/problemset/problem/643/C) — 2400 — expected-time cost with prefix sums of ratios
- [ ] [CF 1715E · Long Way Home](https://codeforces.com/problemset/problem/1715/E) — 2400 — a flight step is a lower envelope over all cities

**2400+**
- [ ] [CF 660F · Bear and Bowling 4](https://codeforces.com/problemset/problem/660/F) — 2500 — fix the right end, lines indexed by the left end, arbitrary queries
- [ ] [CF 631E · Product Sum](https://codeforces.com/problemset/problem/631/E) — 2600 — two directions, queries not monotone
- [ ] [CF 932F · Escape Through Leaf](https://codeforces.com/problemset/problem/932/F) — 2700 — Li Chao merging on a tree
- [ ] [CF 1179D · Fedor Runs for President](https://codeforces.com/problemset/problem/1179/D) — 2700 — tree DP, then a hull over child subtree sizes
- [ ] [CF 1303G · Sum of Prefix Sums](https://codeforces.com/problemset/problem/1303/G) — 2700 — centroid decomposition + Li Chao
- [ ] [CF 1137E · Train Car Selection](https://codeforces.com/problemset/problem/1137/E) — 2700 — keep a hull of candidate points under global updates
- [ ] [CF 455E · Function](https://codeforces.com/problemset/problem/455/E) — 2900 — offline queries, hull over prefixes
- [ ] [CF 1175G · Yet Another Partiton Problem](https://codeforces.com/problemset/problem/1175/G) — 3000 — layered DP with a running maximum; lines kept over a monotonic stack

## 9. LeetCode / FAANG cross-reference

Rare in interviews. CHT needs a non-obvious algebraic rewrite plus a specialised structure, and interviewers prefer problems with several acceptable approaches; no mainstream LeetCode problem *requires* it. Two that are worth knowing for the underlying idea:

- [LC 1499 · Max Value of Equation](https://leetcode.com/problems/max-value-of-equation/) — Hard — the "all slopes equal" degenerate case: separating $y_i + y_j + x_i - x_j$ leaves a sliding-window max (monotonic queue).
- [LC 2944 · Minimum Number of Coins for Fruits](https://leetcode.com/problems/minimum-number-of-coins-for-fruits/) — Medium — same degenerate case, a window minimum.

If an interviewer does go there, explaining "each earlier state is a line, the DP query is the lower envelope at $x_i$" is the expected insight; the Li Chao tree is the easiest structure to code on a whiteboard.

## 10. Self-check

1. Given $dp[i] = \min_j dp[j] + (S_i - S_j)^2 + K$, what are $m_j$, $b_j$, $x_i$, $d_i$?
2. Why does every line own at most one interval of the lower envelope?
3. Derive the bad-line test for a min hull with decreasing slopes. Where is the overflow, and how do you avoid it in Java?
4. Slopes arrive sorted, queries arbitrary: which structure and what complexity? Slopes arbitrary: which two structures?
5. State the Li Chao invariant and prove that the loser line only needs to go to one child.
6. How do you insert a line valid only on $[L, R]$ into a Li Chao tree, and what does it cost?
7. How do you turn a max-hull problem into a min-hull one?
8. In Fair Nut, why is the overlap of rectangle $i$ with all previously chosen rectangles equal to $x_j y_i$ for the last chosen $j$?

<details><summary>Answers</summary>

1. $m_j = -2S_j$, $b_j = dp[j] + S_j^2$, $x_i = S_i$, $d_i = S_i^2 + K$.
2. Two non-parallel lines cross once, so "line $\ell$ is below line $\ell'$" holds on a half-line; the region where $\ell$ is the minimum is an intersection of half-lines, which is an interval.
3. With $m_1 > m_2 > m_3$: $\ell_2$ is useless iff $x_{13} \le x_{12}$, i.e. $\frac{b_3 - b_1}{m_1 - m_3} \le \frac{b_2 - b_1}{m_1 - m_2}$; multiply by the positive denominators: $(b_3-b_1)(m_1-m_2) \le (b_2-b_1)(m_1-m_3)$. The products of an intercept difference and a slope difference overflow; Java compares them exactly with `Math.multiplyHigh` for the high word and an unsigned comparison of the low word.
4. Sorted slopes: deque hull, $O(1)$ amortised insert, $O(\log n)$ binary-search query. Arbitrary slopes: Li Chao tree ($O(\log C)$) or LineContainer ($O(\log n)$ amortised).
5. For every query point $x$, the optimal line at $x$ is stored on the root-to-leaf path of $x$. At a node, the kept line wins at $mid$; since two lines cross at most once, the loser can beat the kept line only on the side of $mid$ where it was better at the endpoint — so only that child can need it.
6. Decompose $[L, R]$ into the $O(\log C)$ canonical segment-tree nodes and do a normal Li Chao insertion into each of their subtrees: $O(\log^2 C)$.
7. Insert $(-m, -b)$, query the minimum, negate it.
8. Chosen rectangles sorted by $x$ have decreasing $y$; the union of the earlier ones restricted to the strip $y \le y_i$ is exactly $[0, x_j] \times [0, y_i]$ because the last chosen $j$ is the widest and all of them are taller than $y_i$.

</details>

See also: [cheat sheet](../99-Cheat-Sheets/07-dp-optimizations-cheatsheet.md) · [folder problems](problems.md) · [folder README](README.md)
