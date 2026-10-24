# Gaussian elimination and the XOR (linear) basis

> **Band:** 🔵 1700 – 🔴 2600 · **Priority:** 🔥 (XOR basis, Gauss mod $p$) · ⚡ (GF(2) bitsets, determinant/inverse, cycle-space XOR paths) · 🧊 (prefix linear basis) · **FAANG:** low · **Prerequisites:** [modular inverses](../04-Number-Theory/02-modular-arithmetic-and-inverses.md), [bit manipulation](../01-Foundations/03-bit-manipulation.md), [binary trie](../11-Strings/05-trie-and-binary-trie.md)
> **You can say you know this when:** you can solve $Ax=b$ over $\mathbb{R}$, $\mathbb{Z}_p$ and GF(2), read off rank, determinant and the
> number of solutions ($p^{m-\text{rank}}$), and use an XOR basis for max-XOR, $k$-th smallest XOR, counting representable values,
> range queries (prefix basis), and XOR paths in graphs.

---

## 1. First principles — why this works

### 1.1 Elimination preserves the solution set

A linear system $Ax=b$ ($n$ equations, $m$ unknowns) is unchanged by three **row operations**: swapping two equations, multiplying an
equation by a non-zero scalar, and adding a multiple of one equation to another — each is invertible, so no solution is lost or
created. Use them to clear each column below (and, for Gauss–Jordan, above) a **pivot**:

1. For column $c$, find a row $r\ge$ current row with $a_{rc}\ne0$; if none, $x_c$ is a **free** variable.
2. Swap it up, scale the pivot to $1$, subtract multiples to zero the rest of the column.

At the end, each non-free column has exactly one pivot row that expresses its variable in terms of free ones. A row reading $0=\beta$ with
$\beta\ne0$ means **inconsistent**. Cost: $O(nm\min(n,m))$ field operations.

Consequences that are used constantly:

- **rank** $=$ number of pivots; **#solutions** over a field with $q$ elements is $q^{\,m-\text{rank}}$ if consistent, else $0$ (each free variable
  is chosen independently; pivots are then forced).
- **determinant** (square $A$): adding a multiple of a row keeps $\det$, swapping negates it, scaling a row by $\lambda$ scales it by $\lambda$. So
  after reducing to upper-triangular form, $\det A=(-1)^{\#\text{swaps}}\prod$ pivots.
- **inverse**: reduce $[A\mid I]$ to $[I\mid A^{-1}]$ — the same row operations applied to $I$ record the product of elementary matrices.

### 1.2 Which field?

- **Reals** (`double`): choose the pivot with the **largest absolute value** in the column (partial pivoting). Dividing by a tiny pivot
  multiplies existing rounding errors by a huge factor; the largest pivot keeps all multipliers $\le1$ in magnitude. Decide "zero" with an
  epsilon.
- **$\mathbb{Z}_p$, $p$ prime**: every non-zero element has an inverse $a^{p-2}$, so any non-zero pivot works and the arithmetic is exact.
- **GF(2)**: addition is XOR, multiplication is AND; a row is a bitset, and "subtract a multiple of a row" is `row ^= pivotRow`. With
  machine words that is $O(nm\cdot\min(n,m)/64)$.
- **Composite modulus** (no inverses): run a Euclid-like elimination on two rows at a time (see
  [matrix-tree file](06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md)).

### 1.3 The XOR basis: Gaussian elimination, one vector at a time

The set of XORs of subsets of a multiset $S$ of $B$-bit numbers is a **vector space** over GF(2) (closed under XOR, contains $0$). Keep a
basis in echelon form: slot $b_i$ holds a vector whose highest set bit is $i$, or is empty.

**Insert $x$:** for $i$ from high to low, if bit $i$ of $x$ is set: if $b_i$ is empty, store $x$ there and stop; otherwise $x\leftarrow x\oplus b_i$.
If $x$ becomes $0$ it was already representable. $O(B)$ per insertion. This *is* Gaussian elimination, processed online.

What the basis gives you (with $r=$ rank):

- **Count**: exactly $2^r$ distinct values are representable (distinct leading bits ⇒ different subsets of the basis give different XORs).
- **Multiplicity**: each representable value is the XOR of exactly $2^{\lvert S\rvert-r}$ subsets of $S$ (the kernel of the map
  "subset ↦ XOR" has dimension $\lvert S\rvert-r$).
- **Maximum XOR** (optionally starting from a given $v$): for $i$ from high to low, $v\leftarrow\max(v,v\oplus b_i)$. Proof: when slot $i$ is
  considered, bits above $i$ are final (all remaining vectors have leading bit $\le i$), and $v\oplus b_i$ flips bit $i$ while only touching
  lower bits, so taking it exactly when bit $i$ of $v$ is $0$ is optimal. **Minimum** of $v\oplus(\cdot)$: same with $\min$.
- **$k$-th smallest**: first **reduce** the basis (clear bit $i$ from every other vector that has it, for each pivot $i$). Then, with the
  non-empty vectors sorted by leading bit $v_0<v_1<\dots<v_{r-1}$, the map $k=\sum k_t2^t\mapsto\bigoplus_{t:k_t=1}v_t$ is **increasing** (the
  pivot bits of a reduced basis appear only in their own vector, so they act like the binary digits of $k$). So the $k$-th smallest
  ($0$-indexed, $0$ included) value is obtained by reading $k$'s bits.

### 1.4 Prefix linear basis (range queries, 🔴)

To answer "maximum XOR of a subset of $a_l..a_r$" offline, sweep $r$ and keep, for each bit slot, the vector **with the largest index**
that can occupy it. Inserting $a_r$ with position $p=r$: at slot $i$ (bit $i$ set), if the slot is empty, store; if the stored position is
smaller than $p$, **swap** (store the newer vector, keep inserting the older one); then XOR and continue.

Invariant: the vector in slot $i$ equals $a_{\text{pos}_i}$ XOR some elements with *larger* indices. (A swap installs the carried vector whose
smallest involved index is $p$; the displaced vector XORed with it has smallest index equal to the old position.) Hence for any $l$, the
vectors with $\text{pos}_i\ge l$ lie in $\operatorname{span}(a_l..a_r)$, are independent, and an exchange argument shows they span it. A query
$(l,r)$ runs the max-XOR greedy over slots with $\text{pos}_i\ge l$. $O(B)$ per insertion and per query.

### 1.5 XOR of paths = tree path ⊕ cycle space

In an undirected graph with edge weights, XOR along a walk: fix a DFS tree and $d_v=$ XOR from the root to $v$ along the tree. Every walk from
$u$ to $v$ has XOR $d_u\oplus d_v\oplus c$ where $c$ is in the **cycle space**, which is spanned by the fundamental cycles
$d_x\oplus d_y\oplus w$ for each non-tree edge $(x,y,w)$. Conversely every element of the cycle space is achievable: walk to the cycle,
around it, and back — the back-and-forth part cancels. So "minimum XOR path from $u$ to $v$" $=\min$ over the coset, which is the greedy
minimisation of $d_u\oplus d_v$ against a basis of the cycle values ([bipartite graphs and cycles](../09-Graphs/09-bipartite-graphs-and-cycles.md)).

---

## 2. Formulas, definitions and identities

| Fact | Formula | Cost |
|---|---|---|
| #solutions of $Ax=b$ over $\mathbb{F}_q$ | $q^{m-\operatorname{rank}A}$ if consistent, else $0$ | $O(nm\min(n,m))$ |
| consistency | $\operatorname{rank}A=\operatorname{rank}[A\mid b]$ (Rouché–Capelli) | |
| determinant | $(-1)^{\#\text{swaps}}\prod\text{pivots}$ | $O(n^3)$ |
| inverse | $[A\mid I]\to[I\mid A^{-1}]$; exists iff $\det A\ne0$ | $O(n^3)$ |
| GF(2) elimination | rows as bitsets, `row ^= pivot` | $O(nm\min(n,m)/64)$ |
| XOR basis size | $r\le B$ (bits) | insert $O(B)$ |
| representable values | $2^r$ | |
| subsets per value | $2^{\lvert S\rvert-r}$ | |
| non-empty subsets with XOR $0$ | $2^{\lvert S\rvert-r}-1$ | |
| max XOR | greedy $v\leftarrow\max(v,v\oplus b_i)$ from high bit | $O(B)$ |
| $k$-th smallest (0-indexed) | reduced basis, $\bigoplus_{t:\,k_t=1}v_t$; exists iff $k<2^r$ | $O(B^2)$ prep, $O(B)$ query |
| prefix basis | keep max position per slot; query uses slots with pos $\ge l$ | $O(B)$ |
| path XOR | $d_u\oplus d_v\oplus\text{cycle space}$ | $O((n+m)B)$ |
| real elimination error | partial pivoting keeps multipliers $\lvert\ell\rvert\le1$ | |

---

## 3. Implementation (C++ and Java)

### 3.1 Gauss over $\mathbb{Z}_p$ (solve, rank) and determinant

```cpp
const ll MOD = 1'000'000'007;
ll power(ll b, ll e) { ll r = 1; b %= MOD; if (b < 0) b += MOD; for (; e; e >>= 1, b = b * b % MOD) if (e & 1) r = r * b % MOD; return r; }
// a: n rows of m+1 entries (augmented). Returns rank, or -1 if inconsistent; x gets one solution (free vars = 0).
int gaussMod(vector<vector<ll>> a, int m, vector<ll>& x) {
    int n = a.size(), row = 0;
    vector<int> where(m, -1);
    for (int col = 0; col < m && row < n; col++) {
        int sel = -1;
        for (int i = row; i < n; i++) if (a[i][col]) { sel = i; break; }
        if (sel < 0) continue;
        swap(a[sel], a[row]);
        where[col] = row;
        ll inv = power(a[row][col], MOD - 2);
        for (int j = col; j <= m; j++) a[row][j] = a[row][j] * inv % MOD;
        for (int i = 0; i < n; i++) if (i != row && a[i][col]) {
            ll f = a[i][col];
            for (int j = col; j <= m; j++) a[i][j] = ((a[i][j] - f * a[row][j]) % MOD + MOD) % MOD;
        }
        row++;
    }
    for (int i = row; i < n; i++) if (a[i][m]) return -1;
    x.assign(m, 0);
    for (int c = 0; c < m; c++) if (where[c] >= 0) x[c] = a[where[c]][m];
    return row;
}
ll detMod(vector<vector<ll>> a) {
    int n = a.size();
    ll det = 1;
    for (int col = 0; col < n; col++) {
        int sel = -1;
        for (int i = col; i < n; i++) if (a[i][col] % MOD) { sel = i; break; }
        if (sel < 0) return 0;
        if (sel != col) { swap(a[sel], a[col]); det = MOD - det; }
        det = det * (a[col][col] % MOD) % MOD;
        ll inv = power(a[col][col], MOD - 2);
        for (int i = col + 1; i < n; i++) {
            ll f = a[i][col] % MOD * inv % MOD;
            if (f) for (int j = col; j < n; j++) a[i][j] = ((a[i][j] - f * a[col][j]) % MOD + MOD) % MOD;
        }
    }
    return det % MOD;
}
```

```java
static final long MOD = 1_000_000_007L;
static long power(long b, long e) { long r = 1; b %= MOD; if (b < 0) b += MOD; for (; e > 0; e >>= 1, b = b * b % MOD) if ((e & 1) == 1) r = r * b % MOD; return r; }
// a: n x (m+1). Returns rank or -1; x receives a solution.
static int gaussMod(long[][] a0, int m, long[] x) {
    int n = a0.length, row = 0;
    long[][] a = new long[n][];
    for (int i = 0; i < n; i++) a[i] = a0[i].clone();
    int[] where = new int[m];
    Arrays.fill(where, -1);
    for (int col = 0; col < m && row < n; col++) {
        int sel = -1;
        for (int i = row; i < n; i++) if (a[i][col] != 0) { sel = i; break; }
        if (sel < 0) continue;
        long[] t = a[sel]; a[sel] = a[row]; a[row] = t;
        where[col] = row;
        long inv = power(a[row][col], MOD - 2);
        for (int j = col; j <= m; j++) a[row][j] = a[row][j] * inv % MOD;
        for (int i = 0; i < n; i++) if (i != row && a[i][col] != 0) {
            long f = a[i][col];
            for (int j = col; j <= m; j++) { a[i][j] = (a[i][j] - f * a[row][j]) % MOD; if (a[i][j] < 0) a[i][j] += MOD; }
        }
        row++;
    }
    for (int i = row; i < n; i++) if (a[i][m] != 0) return -1;
    Arrays.fill(x, 0);
    for (int c = 0; c < m; c++) if (where[c] >= 0) x[c] = a[where[c]][m];
    return row;
}
static long detMod(long[][] a0) {
    int n = a0.length;
    long[][] a = new long[n][];
    for (int i = 0; i < n; i++) a[i] = a0[i].clone();
    long det = 1;
    for (int col = 0; col < n; col++) {
        int sel = -1;
        for (int i = col; i < n; i++) if (a[i][col] % MOD != 0) { sel = i; break; }
        if (sel < 0) return 0;
        if (sel != col) { long[] t = a[sel]; a[sel] = a[col]; a[col] = t; det = (MOD - det) % MOD; }
        det = det * (a[col][col] % MOD) % MOD;
        long inv = power(a[col][col], MOD - 2);
        for (int i = col + 1; i < n; i++) {
            long f = a[i][col] % MOD * inv % MOD;
            if (f != 0) for (int j = col; j < n; j++) { a[i][j] = (a[i][j] - f * a[col][j]) % MOD; if (a[i][j] < 0) a[i][j] += MOD; }
        }
    }
    return det;
}
```

### 3.2 Gauss over reals with partial pivoting

```cpp
// Returns 0: no solution, 1: unique (x filled), 2: infinitely many.
int gaussReal(vector<vector<ld>> a, vector<ld>& x) {
    const ld EPS = 1e-12;
    int n = a.size(), m = a[0].size() - 1, row = 0;
    vector<int> where(m, -1);
    for (int col = 0; col < m && row < n; col++) {
        int sel = row;
        for (int i = row; i < n; i++) if (fabsl(a[i][col]) > fabsl(a[sel][col])) sel = i;
        if (fabsl(a[sel][col]) < EPS) continue;
        swap(a[sel], a[row]);
        where[col] = row;
        for (int i = 0; i < n; i++) if (i != row) {
            ld f = a[i][col] / a[row][col];
            for (int j = col; j <= m; j++) a[i][j] -= f * a[row][j];
        }
        row++;
    }
    x.assign(m, 0);
    for (int c = 0; c < m; c++) if (where[c] >= 0) x[c] = a[where[c]][m] / a[where[c]][c];
    for (int i = 0; i < n; i++) {                       // verify every equation
        ld s = 0;
        for (int j = 0; j < m; j++) s += x[j] * a[i][j];
        if (fabsl(s - a[i][m]) > 1e-9) return 0;
    }
    for (int c = 0; c < m; c++) if (where[c] < 0) return 2;
    return 1;
}
```

```java
static int gaussReal(double[][] a0, double[] x) {
    final double EPS = 1e-12;
    int n = a0.length, m = a0[0].length - 1, row = 0;
    double[][] a = new double[n][];
    for (int i = 0; i < n; i++) a[i] = a0[i].clone();
    int[] where = new int[m];
    Arrays.fill(where, -1);
    for (int col = 0; col < m && row < n; col++) {
        int sel = row;
        for (int i = row; i < n; i++) if (Math.abs(a[i][col]) > Math.abs(a[sel][col])) sel = i;
        if (Math.abs(a[sel][col]) < EPS) continue;
        double[] t = a[sel]; a[sel] = a[row]; a[row] = t;
        where[col] = row;
        for (int i = 0; i < n; i++) if (i != row) {
            double f = a[i][col] / a[row][col];
            for (int j = col; j <= m; j++) a[i][j] -= f * a[row][j];
        }
        row++;
    }
    Arrays.fill(x, 0);
    for (int c = 0; c < m; c++) if (where[c] >= 0) x[c] = a[where[c]][m] / a[where[c]][c];
    for (int i = 0; i < n; i++) {
        double s = 0;
        for (int j = 0; j < m; j++) s += x[j] * a[i][j];
        if (Math.abs(s - a[i][m]) > 1e-9) return 0;
    }
    for (int c = 0; c < m; c++) if (where[c] < 0) return 2;
    return 1;
}
```

### 3.3 XOR basis and prefix basis

```cpp
struct XorBasis {
    static const int B = 60;
    ll b[B] = {};
    int rank = 0;
    bool insert(ll x) {
        for (int i = B - 1; i >= 0; i--) if (x >> i & 1) {
            if (!b[i]) { b[i] = x; rank++; return true; }
            x ^= b[i];
        }
        return false;                                     // already representable
    }
    bool contains(ll x) const { for (int i = B - 1; i >= 0; i--) if (x >> i & 1) { if (!b[i]) return false; x ^= b[i]; } return true; }
    ll maxXor(ll v = 0) const { for (int i = B - 1; i >= 0; i--) v = max(v, v ^ b[i]); return v; }
    ll minXor(ll v) const { for (int i = B - 1; i >= 0; i--) v = min(v, v ^ b[i]); return v; }
    // k-th smallest representable value, k 0-indexed (k = 0 -> 0); -1 if k >= 2^rank.
    ll kth(ll k) const {
        ll c[B]; copy(b, b + B, c);
        for (int i = 0; i < B; i++) if (c[i]) for (int j = i + 1; j < B; j++) if (c[j] >> i & 1) c[j] ^= c[i];
        vector<ll> v;
        for (int i = 0; i < B; i++) if (c[i]) v.push_back(c[i]);
        if ((int)v.size() < 62 && k >= (1LL << v.size())) return -1;
        ll res = 0;
        for (size_t t = 0; t < v.size(); t++) if (k >> t & 1) res ^= v[t];
        return res;
    }
};
// Prefix basis: insert a_1, a_2, ... in order; query(l) = max XOR of a subset of a_l..a_r (r = last inserted).
struct PrefixBasis {
    static const int B = 20;
    int b[B] = {}, pos[B] = {};
    void insert(int x, int p) {
        for (int i = B - 1; i >= 0 && x; i--) if (x >> i & 1) {
            if (!b[i]) { b[i] = x; pos[i] = p; return; }
            if (pos[i] < p) { swap(b[i], x); swap(pos[i], p); }  // keep the newest vector in the slot
            x ^= b[i];
        }
    }
    int query(int l) const { int r = 0; for (int i = B - 1; i >= 0; i--) if (b[i] && pos[i] >= l) r = max(r, r ^ b[i]); return r; }
};
```

```java
static final class XorBasis {
    static final int B = 60;
    final long[] b = new long[B];
    int rank = 0;
    boolean insert(long x) {
        for (int i = B - 1; i >= 0; i--) if ((x >> i & 1) == 1) {
            if (b[i] == 0) { b[i] = x; rank++; return true; }
            x ^= b[i];
        }
        return false;
    }
    long maxXor(long v) { for (int i = B - 1; i >= 0; i--) v = Math.max(v, v ^ b[i]); return v; }
    long minXor(long v) { for (int i = B - 1; i >= 0; i--) v = Math.min(v, v ^ b[i]); return v; }
    long kth(long k) {
        long[] c = b.clone();
        for (int i = 0; i < B; i++) if (c[i] != 0) for (int j = i + 1; j < B; j++) if ((c[j] >> i & 1) == 1) c[j] ^= c[i];
        long[] v = new long[B];
        int r = 0;
        for (int i = 0; i < B; i++) if (c[i] != 0) v[r++] = c[i];
        if (r < 62 && k >= (1L << r)) return -1;
        long res = 0;
        for (int t = 0; t < r; t++) if ((k >> t & 1) == 1) res ^= v[t];
        return res;
    }
}
static final class PrefixBasis {
    static final int B = 20;
    final int[] b = new int[B], pos = new int[B];
    void insert(int x, int p) {
        for (int i = B - 1; i >= 0 && x != 0; i--) if ((x >> i & 1) == 1) {
            if (b[i] == 0) { b[i] = x; pos[i] = p; return; }
            if (pos[i] < p) { int t = b[i]; b[i] = x; x = t; t = pos[i]; pos[i] = p; p = t; }
            x ^= b[i];
        }
    }
    int query(int l) { int r = 0; for (int i = B - 1; i >= 0; i--) if (b[i] != 0 && pos[i] >= l) r = Math.max(r, r ^ b[i]); return r; }
}
```

### 3.4 Tested demo: GF(2) system with bitsets (lights and switches)

$n$ lamps, $m$ switches; switch $j$ toggles a given set of lamps. All lamps start off. Count the subsets of switches that turn **every** lamp
on, modulo $10^9+7$. Variables $x_j\in\{0,1\}$; lamp $i$ gives the equation $\bigoplus_{j\ni i}x_j=1$. Answer $2^{m-\text{rank}}$ or $0$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007;
const int MAXM = 2048;                                   // m <= 2047 variables + 1 rhs column
int main() {
    int n, m; cin >> n >> m;
    vector<bitset<MAXM>> rows(n);
    for (int j = 0; j < m; j++) {
        int k; cin >> k;
        while (k--) { int lamp; cin >> lamp; rows[lamp - 1][j] = 1; }
    }
    for (int i = 0; i < n; i++) rows[i][m] = 1;              // right-hand side
    int rank = 0;
    for (int col = 0; col < m && rank < n; col++) {
        int sel = -1;
        for (int i = rank; i < n; i++) if (rows[i][col]) { sel = i; break; }
        if (sel < 0) continue;
        swap(rows[sel], rows[rank]);
        for (int i = 0; i < n; i++) if (i != rank && rows[i][col]) rows[i] ^= rows[rank];
        rank++;
    }
    for (int i = rank; i < n; i++) if (rows[i][m]) { cout << 0 << '\n'; return 0; }   // 0 = 1: inconsistent
    ll ans = 1;
    for (int i = 0; i < m - rank; i++) ans = ans * 2 % MOD;
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        st.nextToken(); int m = (int) st.nval;
        int W = (m + 1 + 63) / 64;                           // words per row, column m is the rhs
        long[][] rows = new long[n][W];
        for (int j = 0; j < m; j++) {
            st.nextToken(); int k = (int) st.nval;
            while (k-- > 0) { st.nextToken(); int lamp = (int) st.nval - 1; rows[lamp][j >> 6] |= 1L << (j & 63); }
        }
        for (int i = 0; i < n; i++) rows[i][m >> 6] |= 1L << (m & 63);
        int rank = 0;
        for (int col = 0; col < m && rank < n; col++) {
            int sel = -1;
            for (int i = rank; i < n; i++) if ((rows[i][col >> 6] >> (col & 63) & 1) == 1) { sel = i; break; }
            if (sel < 0) continue;
            long[] t = rows[sel]; rows[sel] = rows[rank]; rows[rank] = t;
            for (int i = 0; i < n; i++) if (i != rank && (rows[i][col >> 6] >> (col & 63) & 1) == 1)
                for (int w = 0; w < W; w++) rows[i][w] ^= rows[rank][w];
            rank++;
        }
        for (int i = rank; i < n; i++) if ((rows[i][m >> 6] >> (m & 63) & 1) == 1) { System.out.println(0); return; }
        long ans = 1, MOD = 1_000_000_007L;
        for (int i = 0; i < m - rank; i++) ans = ans * 2 % MOD;
        System.out.println(ans);
    }
}
```

<!-- test
in:
2 3
1 1
1 2
2 1 2
out:
2
-->
<!-- test
in:
2 2
1 1
1 1
out:
0
-->
<!-- test
in:
3 4
3 1 2 3
1 1
1 2
1 3
out:
2
-->

---

## 4. Recognising the pattern

| Statement says… | Think… |
|---|---|
| "system of equations modulo $p$", "find any assignment" | Gauss mod $p$ |
| "toggle", "parity", "lights out", "each element flips a set" | GF(2) system, bitsets, answer $2^{m-r}$ |
| "maximum XOR of a subset", "XOR of chosen elements" | XOR basis |
| "how many distinct XOR values", "how many subsets give XOR $x$" | $2^r$ and $2^{n-r}$ |
| "$k$-th smallest XOR" | reduced basis, read the bits of $k$ |
| "product is a perfect square" | exponent-parity vectors over GF(2) |
| "max XOR on a subarray range", many queries | prefix linear basis (offline by right end) |
| "XOR of a path in a graph", "walk may repeat edges" | DFS depths + cycle basis |
| "no non-empty subset has XOR 0" | linear independence ⇒ size $\le$ rank |
| "determinant", "is the matrix invertible", "count spanning trees" | elimination ([matrix-tree](06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md)) |
| "expected time with cyclic dependencies" | linear system over reals ([probability DP](../06-Dynamic-Programming/10-probability-and-expected-value-dp.md)) |

Confusions: **max XOR of a pair** (two elements) is a binary-trie problem, not a basis problem; **max XOR of a subset** is the basis.

---

## 5. Worked examples (graded)

### Example 1 — System of Linear Equations  ·  ★ ≈2000

- **Source:** [CSES 3154 · System of Linear Equations](https://cses.fi/problemset/task/3154)
- **Difficulty:** ≈2000 (est.)
- **Problem:** $n,m\le500$; $n$ equations in $m$ unknowns with coefficients modulo $10^9+7$. Print any solution, or $-1$.
- **Thinking from first principles:** The modulus is prime, so $\mathbb{Z}_p$ is a field and Gauss–Jordan works verbatim; free variables can be set
  to $0$. $500^3=1.25\cdot10^8$ modular multiply-subtracts — fine, but skip rows whose entry in the pivot column is already $0$.

<details><summary>Solution</summary>

`gaussMod` from §3.1. $O(nm\min(n,m))$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007;
ll power(ll b, ll e) { ll r = 1; for (; e; e >>= 1, b = b * b % MOD) if (e & 1) r = r * b % MOD; return r; }
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    vector<vector<ll>> a(n, vector<ll>(m + 1));
    for (auto& row : a) for (auto& v : row) cin >> v;
    vector<int> where(m, -1);
    int row = 0;
    for (int col = 0; col < m && row < n; col++) {
        int sel = -1;
        for (int i = row; i < n; i++) if (a[i][col]) { sel = i; break; }
        if (sel < 0) continue;
        swap(a[sel], a[row]);
        where[col] = row;
        ll inv = power(a[row][col], MOD - 2);
        for (int j = col; j <= m; j++) a[row][j] = a[row][j] * inv % MOD;
        for (int i = 0; i < n; i++) if (i != row && a[i][col]) {
            ll f = a[i][col];
            for (int j = col; j <= m; j++) { a[i][j] = (a[i][j] - f * a[row][j]) % MOD; if (a[i][j] < 0) a[i][j] += MOD; }
        }
        row++;
    }
    for (int i = row; i < n; i++) if (a[i][m]) { cout << -1 << '\n'; return 0; }
    for (int c = 0; c < m; c++) cout << (where[c] >= 0 ? a[where[c]][m] : 0) << (c + 1 < m ? ' ' : '\n');
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long power(long b, long e) { long r = 1; for (; e > 0; e >>= 1, b = b * b % MOD) if ((e & 1) == 1) r = r * b % MOD; return r; }
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        st.nextToken(); int m = (int) st.nval;
        long[][] a = new long[n][m + 1];
        for (int i = 0; i < n; i++) for (int j = 0; j <= m; j++) { st.nextToken(); a[i][j] = (long) st.nval; }
        int[] where = new int[m];
        Arrays.fill(where, -1);
        int row = 0;
        for (int col = 0; col < m && row < n; col++) {
            int sel = -1;
            for (int i = row; i < n; i++) if (a[i][col] != 0) { sel = i; break; }
            if (sel < 0) continue;
            long[] t = a[sel]; a[sel] = a[row]; a[row] = t;
            where[col] = row;
            long inv = power(a[row][col], MOD - 2);
            for (int j = col; j <= m; j++) a[row][j] = a[row][j] * inv % MOD;
            for (int i = 0; i < n; i++) if (i != row && a[i][col] != 0) {
                long f = a[i][col];
                long[] ai = a[i], ar = a[row];
                for (int j = col; j <= m; j++) { ai[j] = (ai[j] - f * ar[j]) % MOD; if (ai[j] < 0) ai[j] += MOD; }
            }
            row++;
        }
        for (int i = row; i < n; i++) if (a[i][m] != 0) { System.out.println(-1); return; }
        StringBuilder sb = new StringBuilder();
        for (int c = 0; c < m; c++) sb.append(where[c] >= 0 ? a[where[c]][m] : 0).append(c + 1 < m ? ' ' : '\n');
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
2 2
1 1 3
1 1000000006 1
out:
2 1
-->
<!-- test
in:
2 2
1 1 1
2 2 3
out:
-1
-->
<!-- test
in:
3 3
2 0 0 4
0 3 0 9
0 0 5 0
out:
2 3 0
-->

### Example 2 — Square Subsets  ·  ★ 2000

- **Source:** [CF 895C · Square Subsets](https://codeforces.com/problemset/problem/895/C) — 2000
- **Difficulty:** 2000
- **Problem:** $n\le10^5$ numbers $a_i\le70$. Count non-empty subsets (of indices) whose product is a perfect square, modulo $10^9+7$.
- **Thinking from first principles:** A product is a square iff every prime exponent is even. Only the **parities** matter, so map $a_i$ to a
  vector in GF(2)$^{19}$ (19 primes below 70). The product is a square iff the XOR of the chosen vectors is $0$. The number of subsets with XOR
  $0$ is $2^{n-r}$ ($r$ = rank), including the empty set. A bitmask DP over the 70 values also works, but the linear-algebra count is one line.

<details><summary>Solution</summary>

Insert every vector into a 19-bit XOR basis; answer $2^{n-r}-1$. $O(19n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    const ll MOD = 1'000'000'007;
    int primes[19] = {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67};
    int n; cin >> n;
    int basis[19] = {}, rank = 0;
    for (int i = 0; i < n; i++) {
        int a, mask = 0; cin >> a;
        for (int p = 0; p < 19; p++) while (a % primes[p] == 0) { a /= primes[p]; mask ^= 1 << p; }
        for (int b = 18; b >= 0 && mask; b--) if (mask >> b & 1) {
            if (!basis[b]) { basis[b] = mask; rank++; mask = 0; }
            else mask ^= basis[b];
        }
    }
    ll ans = 1;
    for (int i = 0; i < n - rank; i++) ans = ans * 2 % MOD;
    cout << (ans - 1 + MOD) % MOD << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        final long MOD = 1_000_000_007L;
        int[] primes = {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67};
        st.nextToken(); int n = (int) st.nval;
        int[] basis = new int[19];
        int rank = 0;
        for (int i = 0; i < n; i++) {
            st.nextToken(); int a = (int) st.nval, mask = 0;
            for (int p = 0; p < 19; p++) while (a % primes[p] == 0) { a /= primes[p]; mask ^= 1 << p; }
            for (int b = 18; b >= 0 && mask != 0; b--) if ((mask >> b & 1) == 1) {
                if (basis[b] == 0) { basis[b] = mask; rank++; mask = 0; }
                else mask ^= basis[b];
            }
        }
        long ans = 1;
        for (int i = 0; i < n - rank; i++) ans = ans * 2 % MOD;
        System.out.println((ans - 1 + MOD) % MOD);
    }
}
```

</details>

<!-- test
in:
3
2 8 3
out:
1
-->
<!-- test
in:
4
1 1 1 1
out:
15
-->
<!-- test
in:
1
6
out:
0
-->

### Example 3 — $k$-th smallest subset XOR  ·  ★ ≈2100

- **Source:** Original problem.
- **Difficulty:** ≈2100 (est.)
- **Problem:** $n\le10^5$ numbers below $2^{60}$ and $q\le10^5$ queries $k$ ($1\le k\le10^{18}$). Let $V$ be the set of distinct values
  obtainable as the XOR of a (possibly empty) subset. Print the $k$-th smallest element of $V$, or $-1$ if $\lvert V\rvert<k$.
- **Thinking from first principles:** $V$ is a vector space of size $2^r$; listing it is impossible for $r=60$. In a **reduced** basis each pivot
  bit lives in exactly one vector, so choosing a subset of basis vectors is like choosing the binary digits of an index, and the resulting
  values come out in increasing order. Hence the $k$-th smallest ($1$-indexed) is the XOR of the basis vectors selected by the bits of $k-1$.

<details><summary>Solution</summary>

Build, reduce once, answer each query by bits. $O(60n+60^2+60q)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    ll b[60] = {};
    for (int i = 0; i < n; i++) {
        ll x; cin >> x;
        for (int j = 59; j >= 0 && x; j--) if (x >> j & 1) { if (!b[j]) { b[j] = x; x = 0; } else x ^= b[j]; }
    }
    for (int i = 0; i < 60; i++) if (b[i]) for (int j = i + 1; j < 60; j++) if (b[j] >> i & 1) b[j] ^= b[i];   // reduce
    vector<ll> v;
    for (int i = 0; i < 60; i++) if (b[i]) v.push_back(b[i]);
    int r = v.size();
    while (q--) {
        ll k; cin >> k; k--;
        if (r < 62 && k >= (1LL << r)) { cout << -1 << '\n'; continue; }
        ll res = 0;
        for (int t = 0; t < r; t++) if (k >> t & 1) res ^= v[t];
        cout << res << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new String(System.in.readAllBytes()));
        int n = Integer.parseInt(st.nextToken()), q = Integer.parseInt(st.nextToken());
        long[] b = new long[60];
        for (int i = 0; i < n; i++) {
            long x = Long.parseLong(st.nextToken());
            for (int j = 59; j >= 0 && x != 0; j--) if ((x >> j & 1) == 1) { if (b[j] == 0) { b[j] = x; x = 0; } else x ^= b[j]; }
        }
        for (int i = 0; i < 60; i++) if (b[i] != 0) for (int j = i + 1; j < 60; j++) if ((b[j] >> i & 1) == 1) b[j] ^= b[i];
        long[] v = new long[60];
        int r = 0;
        for (int i = 0; i < 60; i++) if (b[i] != 0) v[r++] = b[i];
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            long k = Long.parseLong(st.nextToken()) - 1;
            if (r < 62 && k >= (1L << r)) { sb.append(-1).append('\n'); continue; }
            long res = 0;
            for (int t = 0; t < r; t++) if ((k >> t & 1) == 1) res ^= v[t];
            sb.append(res).append('\n');
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
3 6
5 6 3
1
2
3
4
5
1000000000000000000
out:
0
3
5
6
-1
-1
-->
<!-- test
in:
2 3
0 0
1
2
3
out:
0
-1
-1
-->

### Example 4 — (Zero XOR Subset)-less  ·  ★ 2300

- **Source:** [CF 1101G · (Zero XOR Subset)-less](https://codeforces.com/problemset/problem/1101/G) — 2300
- **Difficulty:** 2300
- **Problem:** Split $a_1..a_n$ ($n\le2\cdot10^5$, $a_i\le10^9$) into the maximum number of contiguous segments such that no non-empty set of
  segments has total XOR $0$. Print the maximum, or $-1$ if impossible.
- **Thinking from first principles:** Let $p_i$ be prefix XORs. Cutting after positions $r_1<\dots<r_k=n$ gives segment XORs
  $s_j=p_{r_j}\oplus p_{r_{j-1}}$ ($p_{r_0}=0$). The map from $(p_{r_1},\dots,p_{r_k})$ to $(s_1,\dots,s_k)$ is an invertible triangular change of
  variables over GF(2), so the $s_j$ are independent **iff** the chosen prefix values are independent. If $p_n=0$, the set of all segments
  already XORs to $0$: answer $-1$. Otherwise any basis of $\operatorname{span}(p_1..p_n)$ can be chosen to contain $p_n$ (exchange lemma),
  so the answer is the **rank** of the prefix XORs.

<details><summary>Solution</summary>

Rank of $\{p_1,\dots,p_n\}$ with a 30-bit basis, or $-1$ if $p_n=0$. $O(30n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    int b[30] = {}, rank = 0, p = 0;
    for (int i = 0; i < n; i++) {
        int a; cin >> a;
        p ^= a;
        int x = p;
        for (int j = 29; j >= 0 && x; j--) if (x >> j & 1) { if (!b[j]) { b[j] = x; rank++; x = 0; } else x ^= b[j]; }
    }
    cout << (p == 0 ? -1 : rank) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        int[] b = new int[30];
        int rank = 0, p = 0;
        for (int i = 0; i < n; i++) {
            st.nextToken(); p ^= (int) st.nval;
            int x = p;
            for (int j = 29; j >= 0 && x != 0; j--) if ((x >> j & 1) == 1) { if (b[j] == 0) { b[j] = x; rank++; x = 0; } else x ^= b[j]; }
        }
        System.out.println(p == 0 ? -1 : rank);
    }
}
```

</details>

<!-- test
in:
4
4 4 1 2
out:
3
-->
<!-- test
in:
2
7 7
out:
-1
-->
<!-- test
in:
3
6 3 5
out:
-1
-->
<!-- test
in:
4
1 2 4 8
out:
4
-->
<!-- test
in:
1
0
out:
-1
-->

### Example 5 — Shortest Path Problem? (XOR)  ·  ★ 2300

- **Source:** [CF 845G · Shortest Path Problem?](https://codeforces.com/problemset/problem/845/G) — 2300
- **Difficulty:** 2300
- **Problem:** A connected undirected graph ($n,m\le10^5$, weights $<2^{27}$, loops and multi-edges allowed). The length of a path is the XOR
  of its edge weights (edges may repeat). Find the minimum length of a path from $1$ to $n$.
- **Thinking from first principles:** Repeating edges makes "paths" into walks, and an edge used twice cancels. So any walk's XOR is the tree
  path XOR $d_1\oplus d_n$ plus some combination of fundamental cycles, and every combination is achievable (§1.5). The answer is the minimum of
  $d_n$ (with $d_1=0$) over that coset: greedy minimisation against the cycle basis.

<details><summary>Solution</summary>

Iterative DFS for $d$; for every edge insert $d_u\oplus d_v\oplus w$ (tree edges insert $0$, harmlessly); answer `minXor(d[n])`.
$O((n+m)\cdot27)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    vector<array<int, 3>> e(m);
    vector<vector<pair<int, int>>> g(n + 1);
    for (auto& [u, v, w] : e) { cin >> u >> v >> w; g[u].push_back({v, w}); g[v].push_back({u, w}); }
    vector<int> d(n + 1, -1);
    d[1] = 0;
    vector<int> st = {1};
    while (!st.empty()) {
        int u = st.back(); st.pop_back();
        for (auto [v, w] : g[u]) if (d[v] < 0) { d[v] = d[u] ^ w; st.push_back(v); }
    }
    int b[30] = {};
    for (auto& [u, v, w] : e) {
        int x = d[u] ^ d[v] ^ w;
        for (int j = 29; j >= 0 && x; j--) if (x >> j & 1) { if (!b[j]) { b[j] = x; x = 0; } else x ^= b[j]; }
    }
    int ans = d[n];
    for (int j = 29; j >= 0; j--) ans = min(ans, ans ^ b[j]);
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        st.nextToken(); int m = (int) st.nval;
        int[] eu = new int[m], ev = new int[m], ew = new int[m];
        int[] head = new int[n + 1], nxt = new int[2 * m], to = new int[2 * m], wt = new int[2 * m];
        Arrays.fill(head, -1);
        for (int i = 0; i < m; i++) {
            st.nextToken(); eu[i] = (int) st.nval; st.nextToken(); ev[i] = (int) st.nval; st.nextToken(); ew[i] = (int) st.nval;
            to[2 * i] = ev[i]; wt[2 * i] = ew[i]; nxt[2 * i] = head[eu[i]]; head[eu[i]] = 2 * i;
            to[2 * i + 1] = eu[i]; wt[2 * i + 1] = ew[i]; nxt[2 * i + 1] = head[ev[i]]; head[ev[i]] = 2 * i + 1;
        }
        int[] d = new int[n + 1];
        Arrays.fill(d, -1);
        d[1] = 0;
        int[] stack = new int[n + 1];
        int sp = 0;
        stack[sp++] = 1;
        while (sp > 0) {
            int u = stack[--sp];
            for (int k = head[u]; k >= 0; k = nxt[k]) if (d[to[k]] < 0) { d[to[k]] = d[u] ^ wt[k]; stack[sp++] = to[k]; }
        }
        int[] b = new int[30];
        for (int i = 0; i < m; i++) {
            int x = d[eu[i]] ^ d[ev[i]] ^ ew[i];
            for (int j = 29; j >= 0 && x != 0; j--) if ((x >> j & 1) == 1) { if (b[j] == 0) { b[j] = x; x = 0; } else x ^= b[j]; }
        }
        int ans = d[n];
        for (int j = 29; j >= 0; j--) ans = Math.min(ans, ans ^ b[j]);
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
3 3
1 2 5
2 3 6
1 3 1
out:
1
-->
<!-- test
in:
2 2
2 2 6
1 2 7
out:
1
-->
<!-- test
in:
1 1
1 1 5
out:
0
-->
<!-- test
in:
4 4
1 2 6
2 3 5
3 4 1
1 4 12
out:
2
-->

### Example 6 — Ivan and Burgers (range max XOR)  ·  ★ 2500

- **Source:** [CF 1100F · Ivan and Burgers](https://codeforces.com/problemset/problem/1100/F) — 2500
- **Difficulty:** 2500
- **Problem:** $n\le5\cdot10^5$ values $c_i<2^{20}$ and $q\le5\cdot10^5$ queries $(l,r)$: the maximum XOR of a subset of $c_l..c_r$.
- **Thinking from first principles:** A basis per query is $O(nq)$; a segment tree of bases merges in $O(B^2)$ per node — too slow at this size.
  The prefix linear basis answers a query for *any* $l$ once the sweep reaches $r$, provided each slot keeps the **newest** possible vector.
  Sort queries by $r$, sweep, and answer each with the slots whose position is $\ge l$.

<details><summary>Solution</summary>

Offline by $r$; `PrefixBasis` from §3.3. $O((n+q)\cdot20)$ plus sorting. Fast I/O matters at $10^6$ numbers.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<int> c(n + 1);
    for (int i = 1; i <= n; i++) cin >> c[i];
    int q; cin >> q;
    vector<int> L(q), ord(q), ans(q);
    vector<vector<int>> byR(n + 1);
    for (int i = 0; i < q; i++) { int l, r; cin >> l >> r; L[i] = l; byR[r].push_back(i); }
    int b[20] = {}, pos[20] = {};
    for (int r = 1; r <= n; r++) {
        int x = c[r], p = r;
        for (int i = 19; i >= 0 && x; i--) if (x >> i & 1) {
            if (!b[i]) { b[i] = x; pos[i] = p; break; }
            if (pos[i] < p) { swap(b[i], x); swap(pos[i], p); }
            x ^= b[i];
        }
        for (int id : byR[r]) {
            int res = 0;
            for (int i = 19; i >= 0; i--) if (b[i] && pos[i] >= L[id]) res = max(res, res ^ b[i]);
            ans[id] = res;
        }
    }
    string out;
    for (int i = 0; i < q; i++) out += to_string(ans[i]) + '\n';
    cout << out;
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        int n = nextInt(in);
        int[] c = new int[n + 1];
        for (int i = 1; i <= n; i++) c[i] = nextInt(in);
        int q = nextInt(in);
        int[] L = new int[q], head = new int[n + 1], nxt = new int[q], ans = new int[q];
        Arrays.fill(head, -1);
        for (int i = 0; i < q; i++) { L[i] = nextInt(in); int r = nextInt(in); nxt[i] = head[r]; head[r] = i; }
        int[] b = new int[20], pos = new int[20];
        for (int r = 1; r <= n; r++) {
            int x = c[r], p = r;
            for (int i = 19; i >= 0 && x != 0; i--) if ((x >> i & 1) == 1) {
                if (b[i] == 0) { b[i] = x; pos[i] = p; break; }
                if (pos[i] < p) { int t = b[i]; b[i] = x; x = t; t = pos[i]; pos[i] = p; p = t; }
                x ^= b[i];
            }
            for (int id = head[r]; id >= 0; id = nxt[id]) {
                int res = 0;
                for (int i = 19; i >= 0; i--) if (b[i] != 0 && pos[i] >= L[id]) res = Math.max(res, res ^ b[i]);
                ans[id] = res;
            }
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < q; i++) sb.append(ans[i]).append('\n');
        System.out.print(sb);
    }
    static int nextInt(DataInputStream in) throws IOException {
        int ret = 0, b = in.read();
        while (b < '0') b = in.read();
        while (b >= '0') { ret = ret * 10 + b - '0'; b = in.read(); }
        return ret;
    }
}
```

</details>

<!-- test
in:
6
9 5 6 12 3 10
5
1 6
2 3
4 4
3 5
1 2
out:
15
6
12
15
12
-->
<!-- test
in:
1
0
1
1 1
out:
0
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Normalise inputs modulo $p$** before elimination (negative or $\ge p$ coefficients); keep every intermediate in $[0,p)$.
2. **Inconsistency check** must look at rows *below* the last pivot after elimination: $0=\beta\ne0$.
3. **Determinant sign**: count swaps; a missing pivot means $\det=0$ immediately.
4. **Real Gauss**: partial pivoting is not optional; compare with an epsilon scaled to the data, and verify the solution afterwards.
5. **GF(2) with bitsets**: use `std::bitset` in C++; in Java pack into `long[]` words (there is `java.util.BitSet`, but manual words are faster for
   XOR-heavy loops).
6. **XOR basis width**: values up to $10^{18}$ need 60 bits; `1 << 40` in C++ is `int` overflow — write `1LL << i` (Java: `1L << i`).
7. **Max XOR starting value**: "maximise $v\oplus$ subset" starts the greedy from $v$, not from $0$.
8. **$k$-th smallest requires the reduced basis**; the plain echelon basis does not give sorted order. Clarify whether $0$ (empty subset)
   counts and whether $k$ is 0- or 1-indexed.
9. **Pair max XOR ≠ subset max XOR**: pairs use a binary trie ([tries](../11-Strings/05-trie-and-binary-trie.md)).
10. **Prefix basis swaps both value and position**; forgetting the position swap silently breaks queries.
11. **Graph XOR paths**: iterative DFS in Java for $n=10^5$; self-loops are cycles too (insert $w$).

---

## 7. Going further (toward 2400–2600+)

- **XOR basis on tree paths** (prefix basis along root paths, query with depth $\ge$ LCA): [CF 1902F · Trees and XOR Queries Again](https://codeforces.com/problemset/problem/1902/F) — 2400.
- **Constructing permutations with XOR structure (basis + Gray code)**: [CF 1163E · Magical Permutation](https://codeforces.com/problemset/problem/1163/E) — 2400.
- **Counting subsets by XOR with multiplicities**: [CF 959F · Mahmoud and Ehab and yet another xor task](https://codeforces.com/problemset/problem/959/F) — 2400
  (prefix bases offline; answer $2^{l-r}$ or $0$).
- **Sum over all pairs of XOR paths with cycle space**: [CF 724G · Xor-matic Number of the Graph](https://codeforces.com/problemset/problem/724/G) — 2600.
- **Linear algebra over GF(2) with optimisation**: [CF 251D · Two Sets](https://codeforces.com/problemset/problem/251/D) — 2700 (greedy bit order + Gauss).
- **Subspaces as DP states**: [CF 1299D · Around the World](https://codeforces.com/problemset/problem/1299/D) — 3000 (there are only 374 subspaces of GF(2)$^5$).
- **Basis of subtrees with rerooting**: [CF 1778E · The Tree Has Fallen!](https://codeforces.com/problemset/problem/1778/E) — 2500.
- **Weight-distribution of a code**: [CF 1336E1 · Chiori and Doll Picking (easy version)](https://codeforces.com/problemset/problem/1336/E1) — 2700.

---

## 8. Practice ladder

**1900–2300**
- [ ] [CSES 3154 · System of Linear Equations](https://cses.fi/problemset/task/3154)
- [ ] [CF 895C · Square Subsets](https://codeforces.com/problemset/problem/895/C) — 2000
- [ ] [CF 1101G · (Zero XOR Subset)-less](https://codeforces.com/problemset/problem/1101/G) — 2300
- [ ] [CF 845G · Shortest Path Problem?](https://codeforces.com/problemset/problem/845/G) — 2300

**2400+**
- [ ] [CF 959F · Mahmoud and Ehab and yet another xor task](https://codeforces.com/problemset/problem/959/F) — 2400
- [ ] [CF 1163E · Magical Permutation](https://codeforces.com/problemset/problem/1163/E) — 2400
- [ ] [CF 1902F · Trees and XOR Queries Again](https://codeforces.com/problemset/problem/1902/F) — 2400
- [ ] [CF 1100F · Ivan and Burgers](https://codeforces.com/problemset/problem/1100/F) — 2500
- [ ] [CF 1778E · The Tree Has Fallen!](https://codeforces.com/problemset/problem/1778/E) — 2500
- [ ] [CF 724G · Xor-matic Number of the Graph](https://codeforces.com/problemset/problem/724/G) — 2600
- [ ] [CF 251D · Two Sets](https://codeforces.com/problemset/problem/251/D) — 2700
- [ ] [CF 113D · Museum](https://codeforces.com/problemset/problem/113/D) — 2700
- [ ] [CF 1336E1 · Chiori and Doll Picking (easy version)](https://codeforces.com/problemset/problem/1336/E1) — 2700
- [ ] [CF 1299D · Around the World](https://codeforces.com/problemset/problem/1299/D) — 3000

---

## 9. LeetCode / FAANG cross-reference

- [LC 3681 · Maximum XOR of Subsequences](https://leetcode.com/problems/maximum-xor-of-subsequences/) — Hard — the XOR of two subsequences is the XOR of a subset: linear basis + greedy.
- [LC 421 · Maximum XOR of Two Numbers in an Array](https://leetcode.com/problems/maximum-xor-of-two-numbers-in-an-array/) — Medium — *pairs*: binary trie, not a basis (contrast).
- [LC 1707 · Maximum XOR With an Element From Array](https://leetcode.com/problems/maximum-xor-with-an-element-from-array/) — Hard — offline + trie (again pairs).
- [LC 1863 · Sum of All Subset XOR Totals](https://leetcode.com/problems/sum-of-all-subset-xor-totals/) — Easy — each bit present in the OR appears in exactly half the subsets: $\text{OR}\cdot2^{n-1}$ (a basis-style counting argument).
- [LC 399 · Evaluate Division](https://leetcode.com/problems/evaluate-division/) — Medium — a multiplicative linear system solved by weighted union–find, not elimination.

Gaussian elimination itself is rare in interviews; XOR-basis questions appear occasionally at the hardest level.

---

## 10. Self-check

1. Why do row operations preserve the solution set, and which one changes the determinant's sign?
2. Over $\mathbb{F}_p$, a consistent system has 7 unknowns and rank 4. How many solutions?
3. Prove that the greedy $v\leftarrow\max(v,v\oplus b_i)$ (high to low) gives the maximum XOR.
4. Why does the $k$-th smallest query need a *reduced* basis?
5. In (Zero XOR Subset)-less, why are segment XORs independent iff the chosen prefix XORs are?
6. Why is every element of the cycle space achievable by a walk from 1 to $n$?
7. What invariant makes the prefix linear basis correct?

<details><summary>Answers</summary>

1. Each operation is invertible (swap back, scale by the inverse, subtract the multiple back). Swapping two rows negates $\det$.
2. $p^{7-4}=p^3$.
3. Slots are processed by decreasing leading bit; after slot $i$, bits above $i$ can no longer change, and XORing $b_i$ toggles bit $i$ without
   affecting higher bits, so choosing it iff bit $i$ is $0$ maximises lexicographically from the top.
4. In a non-reduced basis a higher vector may contain lower pivot bits, so the selection by bits of $k$ is not monotone; reduction makes each
   pivot bit appear in exactly one vector.
5. $s_j=p_{r_j}\oplus p_{r_{j-1}}$ is a unitriangular (invertible) linear transformation of $(p_{r_1},\dots,p_{r_k})$, which preserves linear
   (in)dependence.
6. Walk to a vertex of the cycle, traverse it, walk back the same way: the access path is used twice and cancels, leaving the cycle's XOR.
7. The vector in slot $i$ equals $a_{\text{pos}_i}$ XOR elements with larger indices, and each slot holds the largest possible position; then
   the slots with $\text{pos}\ge l$ form a basis of $\operatorname{span}(a_l..a_r)$.

</details>
