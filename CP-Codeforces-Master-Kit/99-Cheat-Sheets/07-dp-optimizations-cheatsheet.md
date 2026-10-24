# DP Optimisations — Cheat Sheet

Revision only. Full derivations and proofs: [07-DP-Optimizations](../07-DP-Optimizations/README.md) · ladder: [problems.md](../07-DP-Optimizations/problems.md) · base DP: [DP cheat sheet](06-dynamic-programming-cheatsheet.md).

**Always:** write the naive DP first, keep it as the oracle, stress-test the optimised one on random small inputs.

## 1. Signal → technique

| Recurrence / signal | Technique | Cost | File |
|---|---|---|---|
| $\sum_{j \in [L_i, R_i]} dp[j]$ | prefix sums of the previous layer | $O(1)$/state | [01](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md) |
| state $j$ pushes to targets $[lo_j, hi_j]$ | difference array | $O(1)$/push | [01](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md) |
| $\min/\max_{j \in [L_i, R_i]}$, both ends non-decreasing | monotonic deque | amortised $O(1)$ | [01](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md) |
| bounded knapsack, $c$ copies | residues mod $w$ + deque (max) / window sum (count) | $O(W)$/item | [01](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md) |
| $\pm c\lvert x - y\rvert$ between layers | split $y \le x$ / $y \ge x$: two running sweeps | $O(n)$/layer | [01](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md) |
| $\min_j (dp_j + m_j x_i + b_j)$ — cost has an $i\cdot j$ product | CHT: deque / binary search / Li Chao / LineContainer | $O(1)$–$O(\log)$ | [02](../07-DP-Optimizations/02-convex-hull-trick-and-li-chao-tree.md) |
| line valid only for a range of later states | Li Chao on segments | $O(\log^2 C)$ | [02](../07-DP-Optimizations/02-convex-hull-trick-and-li-chao-tree.md) |
| $k$ groups, $\min_j dp_{t-1}[j] + C(j,i)$, $C$ QI | D&C layer / layered Knuth | $O(kn\log n)$ / $O(n^2)$ | [03](../07-DP-Optimizations/03-divide-and-conquer-optimization.md), [04](../07-DP-Optimizations/04-knuth-optimization.md) |
| one layer, $dp[i] = \min_{j<i} dp[j] + C(j,i)$, $C$ QI | deque of candidate blocks + binary search | $O(n\log n)$ | [03](../07-DP-Optimizations/03-divide-and-conquer-optimization.md) |
| $C(i,j) + \min_k dp[i][k] + dp[k+1][j]$, $C$ QI + monotone, no $k$ in $C$ | Knuth | $O(n^2)$ | [04](../07-DP-Optimizations/04-knuth-optimization.md) |
| $\sum_{T \subseteq S}$, $\bigoplus_{A \cup B = S}$, $A \oplus B$, disjoint unions | zeta/Möbius, OR/AND conv., WHT, ranked zeta | $n2^n$, $n^2 2^n$ | [05](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md) |
| "exactly/at most $k$" dimension, $f(k)$ convex | Aliens / WQS / Lagrangian | $\times \log V$ | [06](../07-DP-Optimizations/06-aliens-trick-wqs-binary-search.md) |
| $dp_i(x) = \min_{y \sim x} dp_{i-1}(y) + |x - a_i|$ | slope trick (two heaps) | $O(n\log n)$ | [07](../07-DP-Optimizations/07-slope-trick.md) |
| fixed linear step, $n$ up to $10^{18}$, state $m \le 100$ | matrix power; $(\min,+)$ semiring | $O(m^3\log n)$ | [08](../07-DP-Optimizations/08-matrix-exponentiation-for-dp.md) |

## 2. Validity conditions (the part that silently fails)

| Technique | Exact condition | Quick check |
|---|---|---|
| deque | window ends non-decreasing **and** key of a stored candidate independent of $i$ | write $dp[i] = h(i) + \min g(j)$ explicitly |
| CHT deque | slopes inserted sorted; pointer query needs sorted $x$ | otherwise Li Chao |
| QI | $C(a,c) + C(b,d) \le C(a,d) + C(b,c)$, $a \le b \le c \le d$ | local: $C(a,c)+C(a{+}1,c{+}1) \le C(a,c{+}1)+C(a{+}1,c)$, brute-force it |
| D&C | QI (min) / reverse QI (max) $\Rightarrow$ $\mathrm{opt}(i) \le \mathrm{opt}(i+1)$ for **any** previous layer | |
| Knuth (interval) | QI **and** $C(b,c) \le C(a,d)$ for $[b,c] \subseteq [a,d]$; $C$ must not depend on $k$ | matrix chain, triangulation, burst balloons **fail** |
| Knuth (layered) | QI: $\mathrm{opt}_{t-1}[i] \le \mathrm{opt}_t[i] \le \mathrm{opt}_t[i+1]$ | fill $t\uparrow$, $i\downarrow$ |
| Aliens | $f(k)$ convex (min) / concave (max) | min-cost-flow structure, Monge partition, or brute-force second differences |
| slope trick | every function convex piecewise linear, integer breakpoints | operations preserve convexity |
| matrix power | transition independent of the step (or periodic / piecewise) | segment tree of matrices otherwise |

**QI families:** $h(P_i - P_j)$ with $h$ convex, $P$ non-decreasing; pairs/weights $\ge 0$ inside a group; $k$-median on a line. **Reverse QI (max only):** distinct count, group maximum. Counterexamples for *minimising* with D&C: group max $[6,7,2,7]$, $k=2$ ($13$ vs $14$); "max·len − sum" $[3,6,2,6]$ ($4$ vs $7$).

## 3. Formulas

| Formula | Note |
|---|---|
| $P[R+1] - P[L]$, $(\ldots + p) \bmod p$ | window sum; non-negative mod |
| $nd[r+qw] = qv + \max_{q-c \le p \le q}(dp[r+pw] - pv)$ | bounded knapsack (max) |
| $nd[x] = nd[x-w] + dp[x] - dp[x-(c+1)w]$ | bounded knapsack (count) |
| $(s_i - s_j)^2 = -2s_j \cdot s_i + s_j^2 + s_i^2$ | line $m_j = -2s_j$, $b_j = dp_j + s_j^2$ |
| $\ell_2$ useless $\iff (b_3-b_1)(m_1-m_2) \le (b_2-b_1)(m_1-m_3)$, $m_1>m_2>m_3$ | min hull; 128-bit products |
| $p = \lfloor (b_2 - b_1)/(m_1 - m_2) \rfloor$ | last integer where $\ell_1 \le \ell_2$ |
| $\max_j(m_jx+b_j) = -\min_j(-m_jx - b_j)$ | max hull |
| $\sum_i(\mathrm{opt}[i+1][i+d] - \mathrm{opt}[i][i+d-1] + 1) \le 2n$ | Knuth telescoping |
| per D&C level: candidates $\le n + \#\text{nodes}$ | $O(n\log n)$ per layer |
| $\hat f(S) = \sum_{T\subseteq S} f(T)$; $f(S) = \sum_{T \subseteq S}(-1)^{|S\setminus T|}\hat f(T)$ | zeta / Möbius |
| $\widehat{f \mathbin{\lvert} g} = \hat f\,\hat g$ (subset zeta); $\widehat{f \mathbin{\&} g}$ via superset zeta | OR / AND convolution |
| WHT: $(u,v) \to (u+v, u-v)$, inverse $\div 2^n$ | XOR convolution |
| $g(\lambda) = \min_k f(k) + \lambda k$; $k$ optimal iff $-\Delta_{k+1} \le \lambda \le -\Delta_k$ | Aliens; answer $g(\lambda) - \lambda k$ |
| $f = \min f + \sum_{l \in L}(l - x)^+ + \sum_{r \in R}(x - r)^+$, $\max L \le \min R$ | slope trick |
| $\begin{pmatrix}F_{n+1}&F_n\\F_n&F_{n-1}\end{pmatrix} = \begin{pmatrix}1&1\\1&0\end{pmatrix}^n$ | Fibonacci; doubling $F_{2k} = F_k(2F_{k+1} - F_k)$ |
| $\begin{pmatrix}A & I\\ 0 & I\end{pmatrix}^k$ carries $\sum_{i<k} A^i$ | prefix sums of powers |

## 4. Templates (C++ then Java)

All fragments below were checked against brute force on random inputs.

**Sliding-window DP**

```cpp
// dp[i] = cost[i] + min(dp[i-k..i-1]); dp[0] = cost[0]. Deque of indices with increasing dp.
vector<ll> windowMinDP(const vector<ll>& cost, int k) {
    int n = cost.size();
    vector<ll> dp(n);
    deque<int> q;
    for (int i = 0; i < n; i++) {
        while (!q.empty() && q.front() < i - k) q.pop_front();          // expire
        dp[i] = cost[i] + (i == 0 ? 0 : dp[q.front()]);
        while (!q.empty() && dp[q.back()] >= dp[i]) q.pop_back();       // dominated
        q.push_back(i);
    }
    return dp;
}
```

```java
// dp[i] = cost[i] + min(dp[i-k..i-1]); dp[0] = cost[0]. int[] deque, no boxing.
static long[] windowMinDP(long[] cost, int k) {
    int n = cost.length, head = 0, tail = 0;
    long[] dp = new long[n];
    int[] q = new int[n];
    for (int i = 0; i < n; i++) {
        while (head < tail && q[head] < i - k) head++;
        dp[i] = cost[i] + (i == 0 ? 0 : dp[q[head]]);
        while (head < tail && dp[q[tail - 1]] >= dp[i]) tail--;
        q[tail++] = i;
    }
    return dp;
}
```

**Monotone CHT (min), exact**

```cpp
// Min hull; add() with non-increasing slopes, query() with non-decreasing x. Exact via __int128.
struct CHT {
    vector<ll> M, B; size_t h = 0;
    bool bad(int a, int b, ll m, ll c) {                // line b useless after adding (m, c)?
        return (__int128)(c - B[a]) * (M[a] - M[b]) <= (__int128)(B[b] - B[a]) * (M[a] - m);
    }
    void add(ll m, ll c) {
        if (M.size() > h && M.back() == m) { if (B.back() <= c) return; M.pop_back(); B.pop_back(); }
        while (M.size() >= h + 2 && bad(M.size() - 2, M.size() - 1, m, c)) { M.pop_back(); B.pop_back(); }
        M.push_back(m); B.push_back(c);
    }
    ll query(ll x) {
        while (h + 1 < M.size() && M[h + 1] * x + B[h + 1] <= M[h] * x + B[h]) h++;
        return M[h] * x + B[h];
    }
};
```

```java
// Min hull, sorted slopes (non-increasing) and queries (non-decreasing); exact 128-bit test.
static class CHT {
    long[] M, B; int h = 0, sz = 0;
    CHT(int cap) { M = new long[cap]; B = new long[cap]; }
    static int cmp(long a, long b, long c, long d) {      // sign(a*b - c*d)
        long h1 = Math.multiplyHigh(a, b), h2 = Math.multiplyHigh(c, d);
        return h1 != h2 ? Long.compare(h1, h2) : Long.compareUnsigned(a * b, c * d);
    }
    void add(long m, long c) {
        if (sz > h && M[sz - 1] == m) { if (B[sz - 1] <= c) return; sz--; }
        while (sz >= h + 2 && cmp(c - B[sz - 2], M[sz - 2] - M[sz - 1], B[sz - 1] - B[sz - 2], M[sz - 2] - m) <= 0) sz--;
        M[sz] = m; B[sz] = c; sz++;
    }
    long query(long x) {
        while (h + 1 < sz && M[h + 1] * x + B[h + 1] <= M[h] * x + B[h]) h++;
        return M[h] * x + B[h];
    }
}
```

**Li Chao (min), dynamic nodes**

```cpp
// Li Chao (min) over integers [lo, hi], nodes on demand; any insertion/query order.
struct LiChao {
    struct Node { ll m, b; int l = -1, r = -1; };
    vector<Node> t; ll lo, hi;
    LiChao(ll lo, ll hi) : lo(lo), hi(hi) {}
    void add(ll m, ll b) {
        if (t.empty()) { t.push_back({m, b}); return; }
        int v = 0; ll l = lo, r = hi;
        while (true) {
            ll mid = l + (r - l) / 2;
            bool L = m * l + b < t[v].m * l + t[v].b, Mi = m * mid + b < t[v].m * mid + t[v].b;
            if (Mi) { swap(t[v].m, m); swap(t[v].b, b); }  // node keeps the winner at mid
            if (l == r) return;
            int& c = (L != Mi) ? t[v].l : t[v].r;          // loser can only win on one side
            if (L != Mi) r = mid; else l = mid + 1;
            if (c < 0) { c = t.size(); t.push_back({m, b}); return; }
            v = c;
        }
    }
    ll query(ll x) {                                     // LLONG_MAX if empty
        ll res = LLONG_MAX, l = lo, r = hi;
        for (int v = t.empty() ? -1 : 0; v >= 0;) {
            res = min(res, t[v].m * x + t[v].b);
            ll mid = l + (r - l) / 2;
            if (x <= mid) { v = t[v].l; r = mid; } else { v = t[v].r; l = mid + 1; }
        }
        return res;
    }
};
```

```java
// Li Chao (min) over integers [lo, hi], nodes on demand in parallel arrays.
static class LiChao {
    long lo, hi; int cnt = 0;
    long[] M = new long[16], B = new long[16]; int[] Lc = new int[16], Rc = new int[16];
    LiChao(long lo, long hi) { this.lo = lo; this.hi = hi; }
    int node(long m, long b) {
        if (cnt == M.length) { M = Arrays.copyOf(M, 2 * cnt); B = Arrays.copyOf(B, 2 * cnt); Lc = Arrays.copyOf(Lc, 2 * cnt); Rc = Arrays.copyOf(Rc, 2 * cnt); }
        M[cnt] = m; B[cnt] = b; Lc[cnt] = Rc[cnt] = -1;
        return cnt++;
    }
    void add(long m, long b) {
        if (cnt == 0) { node(m, b); return; }
        int v = 0; long l = lo, r = hi;
        while (true) {
            long mid = l + (r - l) / 2;
            boolean L = m * l + b < M[v] * l + B[v], Mi = m * mid + b < M[v] * mid + B[v];
            if (Mi) { long t = M[v]; M[v] = m; m = t; t = B[v]; B[v] = b; b = t; }
            if (l == r) return;
            if (L != Mi) { r = mid; if (Lc[v] < 0) { int c = node(m, b); Lc[v] = c; return; } v = Lc[v]; }
            else { l = mid + 1; if (Rc[v] < 0) { int c = node(m, b); Rc[v] = c; return; } v = Rc[v]; }
        }
    }
    long query(long x) {
        long res = Long.MAX_VALUE, l = lo, r = hi;
        for (int v = cnt == 0 ? -1 : 0; v >= 0; ) {
            res = Math.min(res, M[v] * x + B[v]);
            long mid = l + (r - l) / 2;
            if (x <= mid) { v = Lc[v]; r = mid; } else { v = Rc[v]; l = mid + 1; }
        }
        return res;
    }
}
```

**D&C layer** — call `dnc(prv, cur, t, n, t - 1, n - 1, C)` for layer $t$.

```cpp
// D&C layer: cur[i] = min_{optl <= j <= min(i-1, optr)} prv[j] + C(j, i), i in [l, r]. Needs QI.
template <class F>
void dnc(const vector<ll>& prv, vector<ll>& cur, int l, int r, int optl, int optr, F& C) {
    if (l > r) return;
    int mid = (l + r) / 2, best = optl;
    ll bv = LLONG_MAX;
    for (int j = optl; j <= min(mid - 1, optr); j++) {
        ll v = prv[j] + C(j, mid);
        if (v < bv) { bv = v; best = j; }
    }
    cur[mid] = bv;
    dnc(prv, cur, l, mid - 1, optl, best, C);
    dnc(prv, cur, mid + 1, r, best, optr, C);
}
```

```java
// D&C layer; same contract as the C++ version.
interface Cost { long get(int j, int i); }
static void dnc(long[] prv, long[] cur, int l, int r, int optl, int optr, Cost C) {
    if (l > r) return;
    int mid = (l + r) >>> 1, best = optl;
    long bv = Long.MAX_VALUE;
    for (int j = optl; j <= Math.min(mid - 1, optr); j++) {
        long v = prv[j] + C.get(j, mid);
        if (v < bv) { bv = v; best = j; }
    }
    cur[mid] = bv;
    dnc(prv, cur, l, mid - 1, optl, best, C);
    dnc(prv, cur, mid + 1, r, best, optr, C);
}
```

**Knuth (interval form)**

```cpp
// Knuth: dp[i][j] = C(i,j) + min_{i<=k<j} dp[i][k] + dp[k+1][j]; needs QI + monotone C. O(n^2).
template <class F>
ll knuth(int n, F& C) {
    vector<vector<ll>> dp(n, vector<ll>(n, 0));
    vector<vector<int>> opt(n, vector<int>(n));
    for (int i = 0; i < n; i++) opt[i][i] = i;
    for (int d = 1; d < n; d++)
        for (int i = 0, j = d; j < n; i++, j++) {
            dp[i][j] = LLONG_MAX;
            for (int k = opt[i][j - 1]; k <= min(opt[i + 1][j], j - 1); k++) {
                ll v = dp[i][k] + dp[k + 1][j];
                if (v <= dp[i][j]) { dp[i][j] = v; opt[i][j] = k; }
            }
            dp[i][j] += C(i, j);
        }
    return dp[0][n - 1];
}
```

```java
// Knuth, interval form; same contract as the C++ version.
interface ICost { long get(int i, int j); }
static long knuth(int n, ICost C) {
    long[][] dp = new long[n][n];
    int[][] opt = new int[n][n];
    for (int i = 0; i < n; i++) opt[i][i] = i;
    for (int d = 1; d < n; d++)
        for (int i = 0, j = d; j < n; i++, j++) {
            dp[i][j] = Long.MAX_VALUE;
            for (int k = opt[i][j - 1]; k <= Math.min(opt[i + 1][j], j - 1); k++) {
                long v = dp[i][k] + dp[k + 1][j];
                if (v <= dp[i][j]) { dp[i][j] = v; opt[i][j] = k; }
            }
            dp[i][j] += C.get(i, j);
        }
    return dp[0][n - 1];
}
```

**SOS transforms and Walsh–Hadamard**

```cpp
// Subset sums (zeta), its inverse (Mobius), superset sums, and Walsh-Hadamard (exact integers).
void zetaSub(vector<ll>& f, int n) {
    for (int i = 0; i < n; i++) for (int m = 0; m < (1 << n); m++) if (m >> i & 1) f[m] += f[m ^ (1 << i)];
}
void mobiusSub(vector<ll>& f, int n) {
    for (int i = 0; i < n; i++) for (int m = 0; m < (1 << n); m++) if (m >> i & 1) f[m] -= f[m ^ (1 << i)];
}
void zetaSup(vector<ll>& f, int n) {
    for (int i = 0; i < n; i++) for (int m = 0; m < (1 << n); m++) if (!(m >> i & 1)) f[m] += f[m | (1 << i)];
}
void wht(vector<ll>& f, bool inverse) {                  // size must be a power of two
    int N = f.size();
    for (int len = 1; len < N; len <<= 1)
        for (int i = 0; i < N; i += 2 * len)
            for (int j = i; j < i + len; j++) { ll u = f[j], v = f[j + len]; f[j] = u + v; f[j + len] = u - v; }
    if (inverse) for (ll& x : f) x /= N;
}
```

```java
// Zeta / Mobius on subsets, superset zeta, Walsh-Hadamard (exact integers).
static void zetaSub(long[] f, int n) {
    for (int i = 0; i < n; i++) for (int m = 0; m < (1 << n); m++) if ((m >> i & 1) == 1) f[m] += f[m ^ (1 << i)];
}
static void mobiusSub(long[] f, int n) {
    for (int i = 0; i < n; i++) for (int m = 0; m < (1 << n); m++) if ((m >> i & 1) == 1) f[m] -= f[m ^ (1 << i)];
}
static void zetaSup(long[] f, int n) {
    for (int i = 0; i < n; i++) for (int m = 0; m < (1 << n); m++) if ((m >> i & 1) == 0) f[m] += f[m | (1 << i)];
}
static void wht(long[] f, boolean inverse) {
    int N = f.length;
    for (int len = 1; len < N; len <<= 1)
        for (int i = 0; i < N; i += 2 * len)
            for (int j = i; j < i + len; j++) { long u = f[j], v = f[j + len]; f[j] = u + v; f[j + len] = u - v; }
    if (inverse) for (int i = 0; i < N; i++) f[i] /= N;
}
```

**Aliens skeleton (maximisation)** — inside `solve`, compare states by (value desc, count asc).

```cpp
// Aliens, maximisation, concave F(k). solve(lam) = {max of gain - lam*uses, SMALLEST optimal uses}.
// Smallest lam with uses(lam) <= k, then F(k) = value + lam*k (use k, not the returned count).
ll aliensMax(int k, ll lo, ll hi, const function<pair<ll, int>(ll)>& solve) {
    while (lo < hi) {
        ll mid = lo + (hi - lo) / 2;                     // floor division, also for negative lo
        if (solve(mid).second <= k) hi = mid; else lo = mid + 1;
    }
    return solve(lo).first + lo * k;
}
```

```java
// Aliens, maximisation; solve(lam) returns {value, smallest optimal count}.
interface Penalised { long[] solve(long lam); }
static long aliensMax(int k, long lo, long hi, Penalised P) {
    while (lo < hi) {
        long mid = lo + (hi - lo) / 2;                   // floor, also for negative lo
        if (P.solve(mid)[1] <= k) hi = mid; else lo = mid + 1;
    }
    return P.solve(lo)[0] + lo * k;
}
```

**Slope trick: non-decreasing with minimum total change**

```cpp
// Slope trick: min total |a_i - b_i| over non-decreasing b. Max-heap of breakpoints.
ll makeNonDecreasing(const vector<ll>& a) {
    priority_queue<ll> L;
    ll ans = 0;
    for (ll x : a) {
        L.push(x);
        if (L.top() > x) { ans += L.top() - x; L.pop(); L.push(x); }
    }
    return ans;                                          // strictly increasing: run on a_i - i
}
```

```java
// Slope trick: min total |a_i - b_i| over non-decreasing b (max-heap of breakpoints).
static long makeNonDecreasing(long[] a) {
    PriorityQueue<Long> L = new PriorityQueue<>(Collections.reverseOrder());
    long ans = 0;
    for (long x : a) {
        L.add(x);
        if (L.peek() > x) { ans += L.poll() - x; L.add(x); }
    }
    return ans;
}
```

**Matrix power mod $p$**

```cpp
// Matrix power mod p (p < 2^31 so products fit): O(m^3 log e). Loops i-k-j, skip zeros.
using Mat = vector<vector<ll>>;
Mat mul(const Mat& A, const Mat& B, ll p) {
    int n = A.size(), K = B.size(), m = B[0].size();
    Mat C(n, vector<ll>(m, 0));
    for (int i = 0; i < n; i++) for (int k = 0; k < K; k++) if (A[i][k])
        for (int j = 0; j < m; j++) C[i][j] = (C[i][j] + A[i][k] * B[k][j]) % p;
    return C;
}
Mat mpow(Mat A, ll e, ll p) {
    int n = A.size();
    Mat R(n, vector<ll>(n, 0));
    for (int i = 0; i < n; i++) R[i][i] = 1 % p;
    for (; e > 0; e >>= 1, A = mul(A, A, p)) if (e & 1) R = mul(R, A, p);
    return R;
}
```

```java
// Matrix power mod p (p < 2^31): O(m^3 log e).
static long[][] mul(long[][] A, long[][] B, long p) {
    int n = A.length, K = B.length, m = B[0].length;
    long[][] C = new long[n][m];
    for (int i = 0; i < n; i++) for (int k = 0; k < K; k++) if (A[i][k] != 0)
        for (int j = 0; j < m; j++) C[i][j] = (C[i][j] + A[i][k] * B[k][j]) % p;
    return C;
}
static long[][] mpow(long[][] A, long e, long p) {
    int n = A.length;
    long[][] R = new long[n][n];
    for (int i = 0; i < n; i++) R[i][i] = 1 % p;
    for (; e > 0; e >>= 1, A = mul(A, A, p)) if ((e & 1) == 1) R = mul(R, A, p);
    return R;
}
```

## 5. Edge cases and constants

| Item | Value / rule |
|---|---|
| sentinel | `LLONG_MIN / 4`, `LLONG_MAX / 4` — survive one addition |
| CHT products | $|\Delta b| \cdot |\Delta m|$: $10^{18}\cdot10^9$ needs 128 bits |
| Li Chao evaluation | $|m|\cdot|x| + |b|$ must fit at every node endpoint, not only at queries |
| Java 128-bit compare | `Math.multiplyHigh` for high words, `Long.compareUnsigned` for low words |
| C++ floor division | `a / b - ((a % b != 0) && ((a < 0) != (b < 0)))` |
| SOS sizes | $2^{20}$ longs = 8 MB; $2^{23}$ ints = 32 MB; ranked zeta $n^2 2^n$: $n \le 20$ |
| Knuth memory | $n = 5000$: $2.5\cdot10^7$ cells per table — jagged rows, `int` for opt |
| matrix mod | $p < 2^{31}$ keeps `a * b` in 63 bits; $p \approx 10^{18}$ needs `__int128` / `multiplyHigh` |
| Aliens range | $\lambda$ must cover every marginal gain; integer $\lambda$ suffices for integer costs |
| Fireworks-style radius | $d \cdot \Delta t$ up to $10^{14}$+: compute in 64 bits, clamp to $n$ |

## 6. Top 10 mistakes

1. Using D&C/Knuth without checking QI — wrong answers, no crash (group max, distinct-count minimisation, matrix chain).
2. CHT bad-line test in 64 bits when $|b|\sim10^{18}$ — passes samples, fails on large tests.
3. Deque storing values instead of indices — can't expire; or reading the front of an empty window.
4. Pointer queries on a hull when $x$ is not sorted (or sorted the "wrong way") — use binary search / Li Chao.
5. Equal slopes in the hull → division by zero or keeping the worse line.
6. Aliens: returning $g(\lambda) - \lambda \cdot \text{count}$ instead of $g(\lambda) - \lambda k$, or inconsistent tie-breaking between DP and search.
7. SOS: swapping the loop order (masks outer, bits inner) — counts submasks multiple times.
8. Knuth: forgetting $\mathrm{opt}[i][i] = i$ / the shared-boundary base $\mathrm{opt}[i][i+1] = i+1$, or filling the layered form with $i$ increasing.
9. Matrix power: `identity` as a function name clashes with `std::identity` in C++20; `int` overflow in products; forgetting `1 % p` when $p = 1$.
10. Java: `ArrayDeque<Integer>`/`PriorityQueue<Long>` in hot loops (boxing), `Scanner` on $10^7$ inputs, `long[5001][5001]` memory.

## 7. Last-minute before the contest

- [ ] Template file has: MinQueue, monotone CHT with `__int128`, Li Chao (dynamic), D&C layer, Knuth loop, zeta/Möbius/WHT, matrix power — in the language you'll use.
- [ ] A 20-line QI checker (local inequality on random small inputs) ready to paste.
- [ ] A naive-vs-fast stress script (generator + two binaries + diff loop).
- [ ] Remember the recognition rule: expand the cost; a product $i \cdot j$ → CHT; a group cost → check QI; a count dimension → check convexity; a huge $n$ with tiny state → matrix.
- [ ] For maximisation, negate and reuse the min template rather than rewriting comparisons.
- [ ] Re-read the overflow table above.
