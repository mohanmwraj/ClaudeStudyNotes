# Matrices and linear recurrences

> **Band:** 🔵 1500 – 🔴 2600 · **Priority:** 🔥 (matrix power, companion matrix, fast doubling) · ⚡ (geometric series of matrices, exponents mod $p-1$) · 🧊 (Kitamasa, Cayley–Hamilton) · **FAANG:** low · **Prerequisites:** [modular arithmetic](../04-Number-Theory/02-modular-arithmetic-and-inverses.md), [Fermat/Euler](../04-Number-Theory/04-euler-phi-fermat-and-euler-theorem.md), [matrix exponentiation for DP](../07-DP-Optimizations/08-matrix-exponentiation-for-dp.md)
> **You can say you know this when:** you can turn any fixed-transition DP into a matrix and compute its $n$-th state for
> $n=10^{18}$, derive the Fibonacci doubling formulas from $Q^n$, sum $I+A+\dots+A^{n-1}$ with one block matrix, and explain
> why $x^n \bmod P(x)$ gives the $n$-th term of a linear recurrence in $O(k^2\log n)$.

---

## 1. First principles — why this works

### 1.1 A linear recurrence is a linear map on a window

Take $a_n=c_1a_{n-1}+c_2a_{n-2}+\dots+c_ka_{n-k}$. The naive loop is $O(nk)$ — hopeless for $n=10^{18}$. The observation: the next
**window** $(a_{n+1},a_n,\dots,a_{n-k+2})$ depends *linearly* on the current window $(a_n,\dots,a_{n-k+1})$. Linear maps are matrices:

$$\begin{pmatrix}a_{n+1}\\a_n\\\vdots\\a_{n-k+2}\end{pmatrix}=\underbrace{\begin{pmatrix}c_1&c_2&\cdots&c_{k-1}&c_k\\1&0&\cdots&0&0\\0&1&\cdots&0&0\\\vdots&&\ddots&&\vdots\\0&0&\cdots&1&0\end{pmatrix}}_{M\ (\text{companion matrix})}\begin{pmatrix}a_n\\a_{n-1}\\\vdots\\a_{n-k+1}\end{pmatrix}.$$

So $s_n=M^{\,n-k+1}s_{k-1}$. Matrix multiplication is **associative**, so $M^n$ can be built by repeated squaring:
$M^{2t}=(M^t)^2$, $M^{2t+1}=M\cdot M^{2t}$ — $O(\log n)$ multiplications of $k\times k$ matrices, $O(k^3\log n)$ total.

### 1.2 Any fixed-transition DP is a matrix power

If a DP over "time steps" has a fixed set of states and the transition from step $t$ to $t+1$ is the same linear rule every step
($\text{dp}_{t+1}[j]=\sum_i T_{ij}\,\text{dp}_t[i]$), then $\text{dp}_n=\text{dp}_0T^n$. The cleanest instance: **$(A^k)_{ij}$ counts walks of length
$k$ from $i$ to $j$** in a graph with adjacency matrix $A$ — by induction, $(A^{k+1})_{ij}=\sum_l(A^k)_{il}A_{lj}$ splits a walk by its last edge.

Two state-augmentation tricks make almost any "linear-ish" recurrence fit:

- **Constants:** $a_n=2a_{n-1}+3$ → keep a constant $1$ in the state: $(a_n,1)\mapsto(2a_n+3\cdot1,\ 1)$.
- **Prefix sums:** to also get $S_n=\sum_{i\le n}a_i$, add $S$ to the state: $S_{n+1}=S_n+a_{n+1}$ is linear in the state.

The same squaring works in any **semiring** where multiplication distributes over addition and is associative — e.g. $(\min,+)$ gives
shortest walks with exactly $k$ edges ([CSES 1724 · Graph Paths II](https://cses.fi/problemset/task/1724)).

### 1.3 Fibonacci, done properly

$Q=\begin{pmatrix}1&1\\1&0\end{pmatrix}$ satisfies $Q^n=\begin{pmatrix}F_{n+1}&F_n\\F_n&F_{n-1}\end{pmatrix}$ (induction: multiply by $Q$ and use $F_{n+2}=F_{n+1}+F_n$).
Every Fibonacci identity is a matrix identity in disguise:

- $Q^{m+n}=Q^mQ^n$ ⇒ **addition formula** $F_{m+n}=F_mF_{n+1}+F_{m-1}F_n$.
- $Q^{2n}=(Q^n)^2$ ⇒ **doubling**: $F_{2n}=F_n(F_{n+1}+F_{n-1})=F_n(2F_{n+1}-F_n)$ and $F_{2n+1}=F_{n+1}^2+F_n^2$.
  So $(F_n,F_{n+1})\mapsto(F_{2n},F_{2n+1})$ costs 3 multiplications; recursing on the bits of $n$ gives $O(\log n)$ with tiny constants.
- $\det Q^n=(\det Q)^n$ ⇒ **Cassini** $F_{n+1}F_{n-1}-F_n^2=(-1)^n$.
- $\gcd(F_m,F_n)=F_{\gcd(m,n)}$ (from the addition formula and $\gcd(F_n,F_{n+1})=1$, Euclid on indices).
- Eigenvalues of $Q$ are $\varphi,\psi=\frac{1\pm\sqrt5}{2}$ ⇒ **Binet** $F_n=\frac{\varphi^n-\psi^n}{\sqrt5}$ (useless for exact work, useful for growth:
  $F_n\approx\varphi^n/\sqrt5$).
- Modulo $m$ the sequence is periodic (Pisano period $\pi(m)\le6m$) because the pair $(F_n,F_{n+1})$ takes at most $m^2$ values and the
  map is invertible.

### 1.4 Faster than $k^3$: Kitamasa via Cayley–Hamilton (🧊)

For order $k\approx1000$, $k^3\log n$ is too slow. The **characteristic polynomial** of the recurrence is
$P(x)=x^k-c_1x^{k-1}-\dots-c_k$. Define the linear functional $\Lambda(x^j)=a_j$ on polynomials. The recurrence says exactly that
$\Lambda\big(x^jP(x)\big)=a_{j+k}-c_1a_{j+k-1}-\dots-c_ka_j=0$ for every $j\ge0$, so $\Lambda$ vanishes on all multiples of $P$. Therefore

$$a_n=\Lambda(x^n)=\Lambda\big(x^n\bmod P(x)\big)=\sum_{i<k}r_ia_i\quad\text{where } x^n\equiv\sum_{i<k}r_ix^i\pmod{P}.$$

Compute $x^n\bmod P$ by repeated squaring of polynomials modulo $P$: each step is a product of two degree-$<k$ polynomials ($O(k^2)$
schoolbook, or $O(k\log k)$ with [NTT](03-fft-and-ntt.md)) followed by reduction. Total $O(k^2\log n)$ (or $O(k\log k\log n)$).
(This is the Cayley–Hamilton theorem $P(M)=0$ applied to the companion matrix, without ever forming $M$.)

### 1.5 Geometric series of matrices

To compute $S_n=I+A+A^2+\dots+A^{n-1}$ (e.g. walks of length $<n$), note

$$\begin{pmatrix}A&I\\0&I\end{pmatrix}^{\!n}=\begin{pmatrix}A^n&S_n\\0&I\end{pmatrix}$$

by induction: multiplying by the block matrix once more gives top-right $A^n+S_n=S_{n+1}$. One $2k\times2k$ power, $8\times$ the cost of a
$k\times k$ power. (Alternative without doubling the size: $S_{2t}=S_t(I+A^t)$, $S_{t+1}=I+AS_t$, recursing on the bits of $n$.) Note that
$(A-I)^{-1}(A^n-I)$ is **not** usable modulo $p$ in general — $A-I$ may be singular.

### 1.6 Exponents live modulo $p-1$

When a recurrence is *multiplicative* ($f_n=f_{n-1}f_{n-2}\cdots$), take logarithms: the **exponents** satisfy a linear recurrence.
By Fermat, $g^e\equiv g^{e\bmod(p-1)}\pmod p$ for $g\not\equiv0$, so the exponent matrix power is done **modulo $p-1$**, not $p$
(Example 6). $p-1$ is composite — fine, because matrix power only multiplies and adds.

---

## 2. Formulas, definitions and identities

| Formula | Meaning | Cost |
|---|---|---|
| $s_n=M^{n-k+1}s_{k-1}$ | companion matrix of $a_n=\sum c_ia_{n-i}$ | $O(k^3\log n)$ |
| $(A^k)_{ij}=\#$walks of length $k$ $i\to j$ | adjacency powers | |
| $Q^n=\begin{pmatrix}F_{n+1}&F_n\\F_n&F_{n-1}\end{pmatrix}$ | Fibonacci matrix | |
| $F_{2n}=F_n(2F_{n+1}-F_n)$, $F_{2n+1}=F_n^2+F_{n+1}^2$ | fast doubling | $O(\log n)$ |
| $F_{m+n}=F_mF_{n+1}+F_{m-1}F_n$ | addition | |
| $F_{n+1}F_{n-1}-F_n^2=(-1)^n$ | Cassini | |
| $\gcd(F_m,F_n)=F_{\gcd(m,n)}$ | | |
| $\sum_{i=0}^{n}F_i=F_{n+2}-1$, $\sum F_i^2=F_nF_{n+1}$ | telescoping | |
| $F_n=\frac{\varphi^n-\psi^n}{\sqrt5}$ | Binet | |
| $a_n=\sum r_ia_i$, $x^n\equiv\sum r_ix^i \pmod{P}$ | Kitamasa | $O(k^2\log n)$ |
| $\begin{pmatrix}A&I\\0&I\end{pmatrix}^n=\begin{pmatrix}A^n&\sum_{i<n}A^i\\0&I\end{pmatrix}$ | geometric series | $O((2k)^3\log n)$ |
| $g^e\equiv g^{e\bmod(p-1)}$ | exponent reduction ($p\nmid g$) | |
| $\pi(m)\le6m$ | Pisano period | |

**Telescoping derivations.** $\sum_{i\le n}F_i$: since $F_i=F_{i+2}-F_{i+1}$, the sum telescopes to $F_{n+2}-F_1=F_{n+2}-1$.
$\sum F_i^2$: $F_i^2=F_i(F_{i+1}-F_{i-1})=F_iF_{i+1}-F_{i-1}F_i$, which telescopes to $F_nF_{n+1}$.

**Cost model for matrix multiplication mod $p$.** With entries $<p\approx10^9$, a product is $<10^{18}$; an unsigned 64-bit accumulator holds 16
such terms ($1.6\cdot10^{19}<1.84\cdot10^{19}$), a signed Java `long` holds 8. Reducing only every 16 (8) terms removes most `%` operations; the
$i$-$k$-$j$ loop order makes the inner loop stream through rows (cache-friendly).

---

## 3. Implementation (C++ and Java)

### 3.1 Matrix power, Fibonacci doubling, Kitamasa

```cpp
const ll MOD = 1'000'000'007;
using Mat = vector<vector<ll>>;
Mat mul(const Mat& A, const Mat& B, ll mod = MOD) {
    int n = A.size(), m = B[0].size(), K = B.size();
    Mat C(n, vector<ll>(m, 0));
    vector<ull> acc(m);
    for (int i = 0; i < n; i++) {
        fill(acc.begin(), acc.end(), 0);
        for (int k = 0; k < K; k++) {
            ull a = A[i][k];
            if (a == 0) continue;
            for (int j = 0; j < m; j++) acc[j] += a * (ull)B[k][j];
            if ((k & 15) == 15) for (int j = 0; j < m; j++) acc[j] %= mod;   // <= 16 products of < 2^60 each fit
        }
        for (int j = 0; j < m; j++) C[i][j] = acc[j] % mod;
    }
    return C;
}
Mat eye(int n) { Mat I(n, vector<ll>(n, 0)); for (int i = 0; i < n; i++) I[i][i] = 1; return I; }   // not "identity": clashes with std::identity (C++20)
Mat mpow(Mat A, ull e, ll mod = MOD) {
    Mat R = eye(A.size());
    for (; e; e >>= 1, A = mul(A, A, mod)) if (e & 1) R = mul(R, A, mod);
    return R;
}
// (F_n, F_{n+1}) mod MOD by fast doubling.
pair<ll, ll> fib(ull n) {
    if (n == 0) return {0, 1};
    auto [a, b] = fib(n >> 1);                          // a = F_k, b = F_{k+1}, k = n/2
    ll c = a * ((2 * b - a + MOD) % MOD) % MOD;         // F_{2k}
    ll d = (a * a + b * b) % MOD;                       // F_{2k+1}
    return (n & 1) ? make_pair(d, (c + d) % MOD) : make_pair(c, d);
}
// a_n for a_n = sum_{i=1..k} c[i-1] * a_{n-i}, given a[0..k-1]. O(k^2 log n).
ll kitamasa(const vector<ll>& a, const vector<ll>& c, ull n) {
    int k = c.size();
    if (n < (ull)k) return a[n];
    auto mulmod = [&](const vector<ll>& p, const vector<ll>& q) {
        vector<ll> r(2 * k - 1, 0);
        for (int i = 0; i < k; i++) if (p[i]) for (int j = 0; j < k; j++) r[i + j] = (r[i + j] + p[i] * q[j]) % MOD;
        for (int d = 2 * k - 2; d >= k; d--) if (r[d])           // x^d = x^{d-k} * x^k = sum_i c[i] x^{d-1-i}
            for (int i = 0; i < k; i++) r[d - 1 - i] = (r[d - 1 - i] + r[d] * c[i]) % MOD;
        r.resize(k);
        return r;
    };
    vector<ll> res(k, 0), base(k, 0);
    res[0] = 1;
    if (k == 1) base[0] = c[0] % MOD; else base[1] = 1;          // x mod P
    for (; n; n >>= 1, base = mulmod(base, base)) if (n & 1) res = mulmod(res, base);
    ll ans = 0;
    for (int i = 0; i < k; i++) ans = (ans + res[i] * a[i]) % MOD;
    return ans;
}
```

```java
static final long MOD = 1_000_000_007L;
static long[][] mul(long[][] A, long[][] B, long mod) {
    int n = A.length, K = B.length, m = B[0].length;
    long[][] C = new long[n][m];
    long[] acc = new long[m];
    for (int i = 0; i < n; i++) {
        Arrays.fill(acc, 0);
        for (int k = 0; k < K; k++) {
            long a = A[i][k];
            if (a == 0) continue;
            long[] Bk = B[k];
            for (int j = 0; j < m; j++) acc[j] += a * Bk[j];
            if ((k & 7) == 7) for (int j = 0; j < m; j++) acc[j] %= mod;   // signed long: <= 8 products of ~1e18
        }
        for (int j = 0; j < m; j++) C[i][j] = acc[j] % mod;
    }
    return C;
}
static long[][] mpow(long[][] A, long e, long mod) {
    int n = A.length;
    long[][] R = new long[n][n];
    for (int i = 0; i < n; i++) R[i][i] = 1;
    for (; e > 0; e >>= 1, A = mul(A, A, mod)) if ((e & 1) == 1) R = mul(R, A, mod);
    return R;
}
// returns {F_n, F_{n+1}} mod MOD; n may be up to 1e18 (treated as unsigned bits).
static long[] fib(long n) {
    if (n == 0) return new long[]{0, 1};
    long[] p = fib(n >>> 1);
    long a = p[0], b = p[1];
    long c = a * ((2 * b - a + MOD) % MOD) % MOD, d = (a * a + b * b) % MOD;
    return (n & 1) == 1 ? new long[]{d, (c + d) % MOD} : new long[]{c, d};
}
static long kitamasa(long[] a, long[] c, long n) {
    int k = c.length;
    if (n < k) return a[(int) n];
    long[] res = new long[k], base = new long[k];
    res[0] = 1;
    if (k == 1) base[0] = c[0] % MOD; else base[1] = 1;
    for (; n > 0; n >>= 1, base = polyMulMod(base, base, c)) if ((n & 1) == 1) res = polyMulMod(res, base, c);
    long ans = 0;
    for (int i = 0; i < k; i++) ans = (ans + res[i] * a[i]) % MOD;
    return ans;
}
static long[] polyMulMod(long[] p, long[] q, long[] c) {
    int k = c.length;
    long[] r = new long[2 * k - 1];
    for (int i = 0; i < k; i++) if (p[i] != 0) for (int j = 0; j < k; j++) r[i + j] = (r[i + j] + p[i] * q[j]) % MOD;
    for (int d = 2 * k - 2; d >= k; d--) if (r[d] != 0)
        for (int i = 0; i < k; i++) r[d - 1 - i] = (r[d - 1 - i] + r[d] * c[i]) % MOD;
    return Arrays.copyOf(r, k);
}
```

### 3.2 Tested demo: one recurrence, three methods

Input: $k$, coefficients $c_1..c_k$, initial $a_0..a_{k-1}$, then $n$. Output $a_n \bmod 10^9+7$ computed by the companion matrix, by
Kitamasa, and (for $n\le10^5$) by the naive loop — all three must agree.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
using ull = unsigned long long;
const ll MOD = 1'000'000'007;
using Mat = vector<vector<ll>>;
Mat mul(const Mat& A, const Mat& B) {
    int n = A.size(), K = B.size(), m = B[0].size();
    Mat C(n, vector<ll>(m, 0));
    vector<ull> acc(m);
    for (int i = 0; i < n; i++) {
        fill(acc.begin(), acc.end(), 0);
        for (int k = 0; k < K; k++) {
            ull a = A[i][k];
            for (int j = 0; j < m; j++) acc[j] += a * (ull)B[k][j];
            if ((k & 15) == 15) for (int j = 0; j < m; j++) acc[j] %= MOD;
        }
        for (int j = 0; j < m; j++) C[i][j] = acc[j] % MOD;
    }
    return C;
}
ll kitamasa(const vector<ll>& a, const vector<ll>& c, ull n) {
    int k = c.size();
    if (n < (ull)k) return a[n];
    auto mm = [&](const vector<ll>& p, const vector<ll>& q) {
        vector<ll> r(2 * k - 1, 0);
        for (int i = 0; i < k; i++) for (int j = 0; j < k; j++) r[i + j] = (r[i + j] + p[i] * q[j]) % MOD;
        for (int d = 2 * k - 2; d >= k; d--) for (int i = 0; i < k; i++) r[d - 1 - i] = (r[d - 1 - i] + r[d] * c[i]) % MOD;
        r.resize(k);
        return r;
    };
    vector<ll> res(k, 0), base(k, 0);
    res[0] = 1;
    if (k == 1) base[0] = c[0]; else base[1] = 1;
    for (; n; n >>= 1, base = mm(base, base)) if (n & 1) res = mm(res, base);
    ll ans = 0;
    for (int i = 0; i < k; i++) ans = (ans + res[i] * a[i]) % MOD;
    return ans;
}
int main() {
    int k; cin >> k;
    vector<ll> c(k), a(k);
    for (auto& v : c) cin >> v;
    for (auto& v : a) cin >> v;
    ull n; cin >> n;
    // companion matrix acting on (a_{t}, a_{t-1}, ..., a_{t-k+1})
    ll viaMatrix;
    if (n < (ull)k) viaMatrix = a[n];
    else {
        Mat M(k, vector<ll>(k, 0)), R(k, vector<ll>(k, 0));
        for (int j = 0; j < k; j++) M[0][j] = c[j];
        for (int i = 1; i < k; i++) M[i][i - 1] = 1;
        for (int i = 0; i < k; i++) R[i][i] = 1;
        for (ull e = n - k + 1; e; e >>= 1, M = mul(M, M)) if (e & 1) R = mul(R, M);
        viaMatrix = 0;
        for (int j = 0; j < k; j++) viaMatrix = (viaMatrix + R[0][j] * a[k - 1 - j]) % MOD;
    }
    cout << viaMatrix << ' ' << kitamasa(a, c, n);
    if (n <= 100000) {
        vector<ll> s(a);
        for (ull t = k; t <= n; t++) { ll v = 0; for (int i = 1; i <= k; i++) v = (v + c[i - 1] * s[t - i]) % MOD; s.push_back(v); }
        cout << ' ' << s[n];
    }
    cout << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long[][] mul(long[][] A, long[][] B) {
        int n = A.length, K = B.length, m = B[0].length;
        long[][] C = new long[n][m];
        long[] acc = new long[m];
        for (int i = 0; i < n; i++) {
            Arrays.fill(acc, 0);
            for (int k = 0; k < K; k++) {
                long a = A[i][k];
                for (int j = 0; j < m; j++) acc[j] += a * B[k][j];
                if ((k & 7) == 7) for (int j = 0; j < m; j++) acc[j] %= MOD;
            }
            for (int j = 0; j < m; j++) C[i][j] = acc[j] % MOD;
        }
        return C;
    }
    static long[] mm(long[] p, long[] q, long[] c) {
        int k = c.length;
        long[] r = new long[2 * k - 1];
        for (int i = 0; i < k; i++) for (int j = 0; j < k; j++) r[i + j] = (r[i + j] + p[i] * q[j]) % MOD;
        for (int d = 2 * k - 2; d >= k; d--) for (int i = 0; i < k; i++) r[d - 1 - i] = (r[d - 1 - i] + r[d] * c[i]) % MOD;
        return Arrays.copyOf(r, k);
    }
    static long kitamasa(long[] a, long[] c, long n) {
        int k = c.length;
        if (n < k) return a[(int) n];
        long[] res = new long[k], base = new long[k];
        res[0] = 1;
        if (k == 1) base[0] = c[0]; else base[1] = 1;
        for (; n > 0; n >>= 1, base = mm(base, base, c)) if ((n & 1) == 1) res = mm(res, base, c);
        long ans = 0;
        for (int i = 0; i < k; i++) ans = (ans + res[i] * a[i]) % MOD;
        return ans;
    }
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new String(System.in.readAllBytes()));
        int k = Integer.parseInt(st.nextToken());
        long[] c = new long[k], a = new long[k];
        for (int i = 0; i < k; i++) c[i] = Long.parseLong(st.nextToken());
        for (int i = 0; i < k; i++) a[i] = Long.parseLong(st.nextToken());
        long n = Long.parseLong(st.nextToken());
        long viaMatrix;
        if (n < k) viaMatrix = a[(int) n];
        else {
            long[][] M = new long[k][k], R = new long[k][k];
            for (int j = 0; j < k; j++) M[0][j] = c[j];
            for (int i = 1; i < k; i++) M[i][i - 1] = 1;
            for (int i = 0; i < k; i++) R[i][i] = 1;
            for (long e = n - k + 1; e > 0; e >>= 1, M = mul(M, M)) if ((e & 1) == 1) R = mul(R, M);
            viaMatrix = 0;
            for (int j = 0; j < k; j++) viaMatrix = (viaMatrix + R[0][j] * a[k - 1 - j]) % MOD;
        }
        StringBuilder sb = new StringBuilder();
        sb.append(viaMatrix).append(' ').append(kitamasa(a, c, n));
        if (n <= 100000) {
            long[] s = Arrays.copyOf(a, (int) Math.max(n + 1, k));
            for (int t = k; t <= n; t++) { long v = 0; for (int i = 1; i <= k; i++) v = (v + c[i - 1] * s[t - i]) % MOD; s[t] = v; }
            sb.append(' ').append(s[(int) n]);
        }
        System.out.println(sb);
    }
}
```

<!-- test
in:
2
1 1
0 1
10
out:
55 55 55
-->
<!-- test
in:
3
2 0 5
1 2 3
1000
out:
98956472 98956472 98956472
-->
<!-- test
in:
1
3
7
0
out:
7 7 7
-->
<!-- test
in:
2
1 1
0 1
1000000000000000000
out:
209783453 209783453
-->

---

## 4. Recognising the pattern

| Statement says… | Think… |
|---|---|
| $n\le10^{18}$ and a DP with $\le\sim100$ states and the same transition each step | matrix power |
| "number of walks/paths of exactly $k$ steps" | $A^k$ |
| "at most $k$ steps", "sum over all lengths $\le k$" | block matrix $\begin{pmatrix}A&I\\0&I\end{pmatrix}$ or a sum state |
| "shortest/longest walk with exactly $k$ edges" | $(\min,+)$ / $(\max,+)$ matrix power |
| Fibonacci-like, huge $n$, one or two values | fast doubling |
| order $k$ up to $\sim2000$, one term needed | Kitamasa $O(k^2\log n)$ |
| "$f_n=f_{n-1}^af_{n-2}^b\cdots$" | exponents mod $p-1$ |
| sequence looks linear-recurrent but you can't derive the matrix | [Berlekamp–Massey](05-lagrange-interpolation-and-berlekamp-massey.md) on the first terms |
| range updates of "Fibonacci-type" values in a segment tree | store $2\times2$ matrices in nodes |

Confusion: matrix power needs a **fixed** transition; if the transition depends on the step (e.g. obstacles at certain columns), split
into segments with different matrices and multiply them in order.

---

## 5. Worked examples (graded)

### Example 1 — Fibonacci Numbers  ·  ★ ≈1500

- **Source:** [CSES 1722 · Fibonacci Numbers](https://cses.fi/problemset/task/1722)
- **Difficulty:** ≈1500 (est.)
- **Problem:** Print $F_n\bmod(10^9+7)$ for $0\le n\le10^{18}$ ($F_0=0$, $F_1=1$).
- **Thinking from first principles:** A loop is $10^{18}$ steps. The pair $(F_n,F_{n+1})$ evolves by a fixed linear map, so its $n$-th iterate is a
  matrix power; squaring that matrix symbolically gives the doubling identities, which skip the matrix entirely.

<details><summary>Solution</summary>

`fib(n)` by fast doubling, recursion depth $\le60$. $O(\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007;
pair<ll, ll> fib(unsigned long long n) {
    if (n == 0) return {0, 1};
    auto [a, b] = fib(n >> 1);
    ll c = a * ((2 * b - a + MOD) % MOD) % MOD, d = (a * a + b * b) % MOD;
    return (n & 1) ? make_pair(d, (c + d) % MOD) : make_pair(c, d);
}
int main() {
    unsigned long long n; cin >> n;
    cout << fib(n).first << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long[] fib(long n) {
        if (n == 0) return new long[]{0, 1};
        long[] p = fib(n >>> 1);
        long a = p[0], b = p[1], c = a * ((2 * b - a + MOD) % MOD) % MOD, d = (a * a + b * b) % MOD;
        return (n & 1) == 1 ? new long[]{d, (c + d) % MOD} : new long[]{c, d};
    }
    public static void main(String[] args) throws IOException {
        long n = Long.parseLong(new BufferedReader(new InputStreamReader(System.in)).readLine().trim());
        System.out.println(fib(n)[0]);
    }
}
```

</details>

<!-- test
in:
10
out:
55
-->
<!-- test
in:
0
out:
0
-->
<!-- test
in:
1000000000000000000
out:
209783453
-->

### Example 2 — Throwing Dice  ·  ★ ≈1600

- **Source:** [CSES 1096 · Throwing Dice](https://cses.fi/problemset/task/1096)
- **Difficulty:** ≈1600 (est.)
- **Problem:** Count ordered sequences of die throws (values $1..6$) summing to $n\le10^{18}$, modulo $10^9+7$.
- **Thinking from first principles:** Condition on the last throw: $a_n=a_{n-1}+\dots+a_{n-6}$ with $a_0=1$ and $a_{<0}=0$. Order 6, constant
  coefficients — a $6\times6$ companion matrix, or Kitamasa with $k=6$. Initial window: $a_0..a_5=1,1,2,4,8,16$.

<details><summary>Solution</summary>

Companion matrix power: $O(6^3\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007;
using Mat = array<array<ll, 6>, 6>;
Mat mul(const Mat& A, const Mat& B) {
    Mat C{};
    for (int i = 0; i < 6; i++) for (int k = 0; k < 6; k++) for (int j = 0; j < 6; j++) C[i][j] = (C[i][j] + A[i][k] * B[k][j]) % MOD;
    return C;
}
int main() {
    unsigned long long n; cin >> n;
    ll init[6] = {1, 1, 2, 4, 8, 16};                     // a_0..a_5
    if (n < 6) { cout << init[n] << '\n'; return 0; }
    Mat M{}, R{};
    for (int j = 0; j < 6; j++) M[0][j] = 1;
    for (int i = 1; i < 6; i++) M[i][i - 1] = 1;
    for (int i = 0; i < 6; i++) R[i][i] = 1;
    for (unsigned long long e = n - 5; e; e >>= 1, M = mul(M, M)) if (e & 1) R = mul(R, M);
    ll ans = 0;
    for (int j = 0; j < 6; j++) ans = (ans + R[0][j] * init[5 - j]) % MOD;  // state = (a_5, a_4, ..., a_0)
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long[][] mul(long[][] A, long[][] B) {
        long[][] C = new long[6][6];
        for (int i = 0; i < 6; i++) for (int k = 0; k < 6; k++) for (int j = 0; j < 6; j++) C[i][j] = (C[i][j] + A[i][k] * B[k][j]) % MOD;
        return C;
    }
    public static void main(String[] args) throws IOException {
        long n = Long.parseLong(new BufferedReader(new InputStreamReader(System.in)).readLine().trim());
        long[] init = {1, 1, 2, 4, 8, 16};
        if (n < 6) { System.out.println(init[(int) n]); return; }
        long[][] M = new long[6][6], R = new long[6][6];
        for (int j = 0; j < 6; j++) M[0][j] = 1;
        for (int i = 1; i < 6; i++) M[i][i - 1] = 1;
        for (int i = 0; i < 6; i++) R[i][i] = 1;
        for (long e = n - 5; e > 0; e >>= 1, M = mul(M, M)) if ((e & 1) == 1) R = mul(R, M);
        long ans = 0;
        for (int j = 0; j < 6; j++) ans = (ans + R[0][j] * init[5 - j]) % MOD;
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
3
out:
4
-->
<!-- test
in:
8
out:
125
-->
<!-- test
in:
1
out:
1
-->

### Example 3 — Graph Paths I  ·  ★ ≈1700

- **Source:** [CSES 1723 · Graph Paths I](https://cses.fi/problemset/task/1723)
- **Difficulty:** ≈1700 (est.)
- **Problem:** A directed multigraph with $n\le100$ vertices and $m$ edges. Count routes from 1 to $n$ using exactly $k\le10^9$ edges, modulo $10^9+7$.
- **Thinking from first principles:** "Routes" may revisit vertices — they are walks — so the count is $(A^k)_{1,n}$ with $A_{ab}$ the number of
  edges $a\to b$. $100^3\cdot30=3\cdot10^7$ multiply-adds.

<details><summary>Solution</summary>

`mpow(A, k)` with the lazy-reduction multiplication of §3.1. $O(n^3\log k)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
using ull = unsigned long long;
const ll MOD = 1'000'000'007;
using Mat = vector<vector<ll>>;
Mat mul(const Mat& A, const Mat& B) {
    int n = A.size();
    Mat C(n, vector<ll>(n, 0));
    vector<ull> acc(n);
    for (int i = 0; i < n; i++) {
        fill(acc.begin(), acc.end(), 0);
        for (int k = 0; k < n; k++) {
            ull a = A[i][k];
            if (!a) continue;
            for (int j = 0; j < n; j++) acc[j] += a * (ull)B[k][j];
            if ((k & 15) == 15) for (int j = 0; j < n; j++) acc[j] %= MOD;
        }
        for (int j = 0; j < n; j++) C[i][j] = acc[j] % MOD;
    }
    return C;
}
int main() {
    int n, m; long long k; cin >> n >> m >> k;
    Mat A(n, vector<ll>(n, 0)), R(n, vector<ll>(n, 0));
    for (int i = 0; i < m; i++) { int a, b; cin >> a >> b; A[a - 1][b - 1]++; }
    for (int i = 0; i < n; i++) R[i][i] = 1;
    for (; k; k >>= 1, A = mul(A, A)) if (k & 1) R = mul(R, A);
    cout << R[0][n - 1] << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long[][] mul(long[][] A, long[][] B) {
        int n = A.length;
        long[][] C = new long[n][n];
        long[] acc = new long[n];
        for (int i = 0; i < n; i++) {
            Arrays.fill(acc, 0);
            for (int k = 0; k < n; k++) {
                long a = A[i][k];
                if (a == 0) continue;
                long[] Bk = B[k];
                for (int j = 0; j < n; j++) acc[j] += a * Bk[j];
                if ((k & 7) == 7) for (int j = 0; j < n; j++) acc[j] %= MOD;
            }
            for (int j = 0; j < n; j++) C[i][j] = acc[j] % MOD;
        }
        return C;
    }
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        st.nextToken(); int m = (int) st.nval;
        st.nextToken(); long k = (long) st.nval;
        long[][] A = new long[n][n], R = new long[n][n];
        for (int i = 0; i < m; i++) { st.nextToken(); int a = (int) st.nval; st.nextToken(); int b = (int) st.nval; A[a - 1][b - 1]++; }
        for (int i = 0; i < n; i++) R[i][i] = 1;
        for (; k > 0; k >>= 1, A = mul(A, A)) if ((k & 1) == 1) R = mul(R, A);
        System.out.println(R[0][n - 1]);
    }
}
```

</details>

<!-- test
in:
3 4 2
1 2
2 3
1 3
3 3
out:
2
-->
<!-- test
in:
2 2 1000000000
1 2
2 1
out:
0
-->
<!-- test
in:
2 3 3
1 1
1 2
2 2
out:
3
-->

### Example 4 — Magic Gems  ·  ★ 2100

- **Source:** [CF 1117D · Magic Gems](https://codeforces.com/problemset/problem/1117/D) — 2100
- **Difficulty:** 2100
- **Problem:** A magic gem occupies 1 unit, or can be split into $m$ normal gems occupying $m$ units ($2\le m\le100$). Count configurations of
  total size $n\le10^{18}$ (which gems are split matters), modulo $10^9+7$.
- **Thinking from first principles:** Look at the last unit of space: it is either an unsplit gem ($f(n-1)$ ways for the rest) or the last of
  $m$ units of a split gem ($f(n-m)$). So $f(n)=f(n-1)+f(n-m)$ with $f(n)=1$ for $0\le n<m$. Order $m\le100$: a $100\times100$ companion
  matrix costs $10^6\cdot60$ operations — fine. Kitamasa would do it in $10^4\cdot60$.

<details><summary>Solution</summary>

Companion matrix with $c_1=1$, $c_m=1$; state $(f(t),\dots,f(t-m+1))$ starting at $t=m-1$ (all ones). $O(m^3\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
using ull = unsigned long long;
const ll MOD = 1'000'000'007;
using Mat = vector<vector<ll>>;
Mat mul(const Mat& A, const Mat& B) {
    int n = A.size();
    Mat C(n, vector<ll>(n, 0));
    vector<ull> acc(n);
    for (int i = 0; i < n; i++) {
        fill(acc.begin(), acc.end(), 0);
        for (int k = 0; k < n; k++) {
            ull a = A[i][k];
            if (!a) continue;
            for (int j = 0; j < n; j++) acc[j] += a * (ull)B[k][j];
            if ((k & 15) == 15) for (int j = 0; j < n; j++) acc[j] %= MOD;
        }
        for (int j = 0; j < n; j++) C[i][j] = acc[j] % MOD;
    }
    return C;
}
int main() {
    ull n; int m; cin >> n >> m;
    if (n < (ull)m) { cout << 1 << '\n'; return 0; }
    Mat M(m, vector<ll>(m, 0)), R(m, vector<ll>(m, 0));
    M[0][0] = 1; M[0][m - 1] = (m == 1) ? 2 : 1;
    for (int i = 1; i < m; i++) M[i][i - 1] = 1;
    for (int i = 0; i < m; i++) R[i][i] = 1;
    for (ull e = n - (m - 1); e; e >>= 1, M = mul(M, M)) if (e & 1) R = mul(R, M);
    ll ans = 0;
    for (int j = 0; j < m; j++) ans = (ans + R[0][j]) % MOD;   // initial state is all ones
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long[][] mul(long[][] A, long[][] B) {
        int n = A.length;
        long[][] C = new long[n][n];
        long[] acc = new long[n];
        for (int i = 0; i < n; i++) {
            Arrays.fill(acc, 0);
            for (int k = 0; k < n; k++) {
                long a = A[i][k];
                if (a == 0) continue;
                long[] Bk = B[k];
                for (int j = 0; j < n; j++) acc[j] += a * Bk[j];
                if ((k & 7) == 7) for (int j = 0; j < n; j++) acc[j] %= MOD;
            }
            for (int j = 0; j < n; j++) C[i][j] = acc[j] % MOD;
        }
        return C;
    }
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        long n = Long.parseLong(st.nextToken());
        int m = Integer.parseInt(st.nextToken());
        if (n < m) { System.out.println(1); return; }
        long[][] M = new long[m][m], R = new long[m][m];
        M[0][0] = 1; M[0][m - 1] = 1;
        for (int i = 1; i < m; i++) M[i][i - 1] = 1;
        for (int i = 0; i < m; i++) R[i][i] = 1;
        for (long e = n - (m - 1); e > 0; e >>= 1, M = mul(M, M)) if ((e & 1) == 1) R = mul(R, M);
        long ans = 0;
        for (int j = 0; j < m; j++) ans = (ans + R[0][j]) % MOD;
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
5 3
out:
4
-->
<!-- test
in:
6 2
out:
13
-->
<!-- test
in:
1 3
out:
1
-->
<!-- test
in:
1000000000000000000 100
out:
161502719
-->

### Example 5 — Walks of length at most $k$  ·  ★ ≈1900

- **Source:** Original problem.
- **Difficulty:** ≈1900 (est.)
- **Problem:** A directed multigraph with $n\le50$ vertices, vertices $s,t$, and $k\le10^{18}$. Count walks from $s$ to $t$ of length
  between $1$ and $k$, modulo $10^9+7$.
- **Thinking from first principles:** The answer is $\big(\sum_{\ell=1}^{k}A^\ell\big)_{st}$. Summing $k$ powers is too slow, and
  $(A-I)^{-1}$ need not exist modulo $p$. The block matrix $B=\begin{pmatrix}A&I\\0&I\end{pmatrix}$ has $B^{k+1}$ with top-right block
  $\sum_{\ell=0}^{k}A^\ell$; subtract the $\ell=0$ term $I_{st}$.

<details><summary>Solution</summary>

One power of a $2n\times2n$ matrix. $O((2n)^3\log k)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
using ull = unsigned long long;
const ll MOD = 1'000'000'007;
using Mat = vector<vector<ll>>;
Mat mul(const Mat& A, const Mat& B) {
    int n = A.size();
    Mat C(n, vector<ll>(n, 0));
    vector<ull> acc(n);
    for (int i = 0; i < n; i++) {
        fill(acc.begin(), acc.end(), 0);
        for (int k = 0; k < n; k++) {
            ull a = A[i][k];
            if (!a) continue;
            for (int j = 0; j < n; j++) acc[j] += a * (ull)B[k][j];
            if ((k & 15) == 15) for (int j = 0; j < n; j++) acc[j] %= MOD;
        }
        for (int j = 0; j < n; j++) C[i][j] = acc[j] % MOD;
    }
    return C;
}
int main() {
    int n, m, s, t; ull k; cin >> n >> m >> s >> t >> k;
    s--; t--;
    Mat B(2 * n, vector<ll>(2 * n, 0)), R(2 * n, vector<ll>(2 * n, 0));
    for (int i = 0; i < m; i++) { int a, b; cin >> a >> b; B[a - 1][b - 1]++; }
    for (int i = 0; i < n; i++) { B[i][n + i] = 1; B[n + i][n + i] = 1; }
    for (int i = 0; i < 2 * n; i++) R[i][i] = 1;
    for (ull e = k + 1; e; e >>= 1, B = mul(B, B)) if (e & 1) R = mul(R, B);
    ll ans = (R[s][n + t] - (s == t ? 1 : 0) + MOD) % MOD;
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long[][] mul(long[][] A, long[][] B) {
        int n = A.length;
        long[][] C = new long[n][n];
        long[] acc = new long[n];
        for (int i = 0; i < n; i++) {
            Arrays.fill(acc, 0);
            for (int k = 0; k < n; k++) {
                long a = A[i][k];
                if (a == 0) continue;
                long[] Bk = B[k];
                for (int j = 0; j < n; j++) acc[j] += a * Bk[j];
                if ((k & 7) == 7) for (int j = 0; j < n; j++) acc[j] %= MOD;
            }
            for (int j = 0; j < n; j++) C[i][j] = acc[j] % MOD;
        }
        return C;
    }
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new String(System.in.readAllBytes()));
        int n = Integer.parseInt(st.nextToken()), m = Integer.parseInt(st.nextToken());
        int s = Integer.parseInt(st.nextToken()) - 1, t = Integer.parseInt(st.nextToken()) - 1;
        long k = Long.parseLong(st.nextToken());
        long[][] B = new long[2 * n][2 * n], R = new long[2 * n][2 * n];
        for (int i = 0; i < m; i++) { int a = Integer.parseInt(st.nextToken()) - 1, b = Integer.parseInt(st.nextToken()) - 1; B[a][b]++; }
        for (int i = 0; i < n; i++) { B[i][n + i] = 1; B[n + i][n + i] = 1; }
        for (int i = 0; i < 2 * n; i++) R[i][i] = 1;
        for (long e = k + 1; e > 0; e >>= 1, B = mul(B, B)) if ((e & 1) == 1) R = mul(R, B);
        System.out.println((R[s][n + t] - (s == t ? 1 : 0) + MOD) % MOD);
    }
}
```

</details>

<!-- test
in:
2 2 1 2 3
1 2
2 1
out:
2
-->
<!-- test
in:
1 1 1 1 1000000000000000000
1 1
out:
49
-->
<!-- test
in:
3 3 1 1 6
1 2
2 3
3 1
out:
2
-->

### Example 6 — Product Oriented Recurrence  ·  ★ 2300

- **Source:** [CF 1182E · Product Oriented Recurrence](https://codeforces.com/problemset/problem/1182/E) — 2300
- **Difficulty:** 2300
- **Problem:** $f_x=c^{2x-6}f_{x-1}f_{x-2}f_{x-3}$ for $x\ge4$. Given $n\le10^{18}$ ($n\ge4$) and $f_1,f_2,f_3,c\le10^9$, print $f_n\bmod(10^9+7)$.
- **Thinking from first principles:** Products become sums under logarithms, but the $c^{2x-6}$ factor depends on $x$. Absorb it: with
  $g_x=c^xf_x$, $g_x=c^{3x-6}f_{x-1}f_{x-2}f_{x-3}=g_{x-1}g_{x-2}g_{x-3}$ because $(x-1)+(x-2)+(x-3)=3x-6$. Now $g_n=g_1^{\alpha}g_2^{\beta}g_3^{\gamma}$ where
  the exponents follow the tribonacci recurrence. Exponents can be reduced modulo $p-1$ (Fermat; every $g_i\not\equiv0$ since all inputs are
  in $[1,10^9]$, below $p$). Finally $f_n=g_n\cdot c^{-n}$.

<details><summary>Solution</summary>

$T=\begin{pmatrix}1&1&1\\1&0&0\\0&1&0\end{pmatrix}^{n-3}$ modulo $p-1$ maps $(e_3,e_2,e_1)$ to $(e_n,e_{n-1},e_{n-2})$, so the exponent of $g_3$ is $T_{00}$,
of $g_2$ is $T_{01}$, of $g_1$ is $T_{02}$. $O(27\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll P = 1'000'000'007, E = P - 1;
using Mat = array<array<ll, 3>, 3>;
Mat mul(const Mat& A, const Mat& B) {
    Mat C{};
    for (int i = 0; i < 3; i++) for (int k = 0; k < 3; k++) for (int j = 0; j < 3; j++) C[i][j] = (C[i][j] + A[i][k] * B[k][j]) % E;
    return C;
}
ll pw(ll b, ll e) { ll r = 1; b %= P; for (; e; e >>= 1, b = b * b % P) if (e & 1) r = r * b % P; return r; }
int main() {
    ll n, f1, f2, f3, c; cin >> n >> f1 >> f2 >> f3 >> c;
    Mat T = {{{1, 1, 1}, {1, 0, 0}, {0, 1, 0}}}, R{};
    for (int i = 0; i < 3; i++) R[i][i] = 1;
    for (ll e = n - 3; e; e >>= 1, T = mul(T, T)) if (e & 1) R = mul(R, T);
    ll g1 = c % P * f1 % P, g2 = pw(c, 2) * f2 % P, g3 = pw(c, 3) * f3 % P;
    ll gn = pw(g3, R[0][0]) * pw(g2, R[0][1]) % P * pw(g1, R[0][2]) % P;
    ll cinv = pw(c, E - n % E);                             // c^{-n} = c^{(p-1) - n mod (p-1)}
    cout << gn * cinv % P << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long P = 1_000_000_007L, E = P - 1;
    static long[][] mul(long[][] A, long[][] B) {
        long[][] C = new long[3][3];
        for (int i = 0; i < 3; i++) for (int k = 0; k < 3; k++) for (int j = 0; j < 3; j++) C[i][j] = (C[i][j] + A[i][k] * B[k][j]) % E;
        return C;
    }
    static long pw(long b, long e) { long r = 1; b %= P; for (; e > 0; e >>= 1, b = b * b % P) if ((e & 1) == 1) r = r * b % P; return r; }
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        long n = Long.parseLong(st.nextToken()), f1 = Long.parseLong(st.nextToken()), f2 = Long.parseLong(st.nextToken());
        long f3 = Long.parseLong(st.nextToken()), c = Long.parseLong(st.nextToken());
        long[][] T = {{1, 1, 1}, {1, 0, 0}, {0, 1, 0}}, R = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}};
        for (long e = n - 3; e > 0; e >>= 1, T = mul(T, T)) if ((e & 1) == 1) R = mul(R, T);
        long g1 = c % P * f1 % P, g2 = pw(c, 2) * f2 % P, g3 = pw(c, 3) * f3 % P;
        long gn = pw(g3, R[0][0]) * pw(g2, R[0][1]) % P * pw(g1, R[0][2]) % P;
        System.out.println(gn * pw(c, E - n % E) % P);
    }
}
```

</details>

<!-- test
in:
4 1 2 3 1
out:
6
-->
<!-- test
in:
5 2 3 5 2
out:
28800
-->
<!-- test
in:
6 1 1 1 3
out:
4782969
-->
<!-- test
in:
7 3 1 4 5
out:
124633366
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Off-by-one in the exponent**: with state $s_t=(a_t,\dots,a_{t-k+1})$ starting at $t=k-1$, you need $M^{n-k+1}$. Test $n=k-1$ and $n=k$.
2. **Handle $n<k$ separately** — `n - k + 1` underflows for unsigned types.
3. **Lazy reduction**: unsigned 64-bit holds 16 products of values $<2^{30}$; Java's signed `long` holds 8. Reduce before overflow, not after.
4. **Loop order $i$-$k$-$j$** is 3–5× faster than $i$-$j$-$k$ (row-major streaming); skip zero $A_{ik}$ for sparse matrices.
5. **Exponents mod $p-1$**, not $p$ — and check the base is non-zero mod $p$ (if it can be $0$, handle $0^0$ and $0^e$ separately).
6. **Do not divide by $A-I$** for geometric series modulo $p$; use the block matrix or the doubling recursion.
7. **Memory/time with many queries**: precompute $M^{2^i}$ once; then each query multiplies a **vector** by $\log n$ matrices: $O(k^2\log n)$
   per query instead of $O(k^3\log n)$.
8. **Java recursion in `fib`** is only 60 deep — fine; but avoid allocating `long[][]` in hot loops (reuse buffers for big $k$).
9. **`long n` in Java** for $n\le10^{18}$ fits; use `>>>` if you ever treat it as unsigned.
10. **Min-plus matrices**: identity has $0$ on the diagonal and $+\infty$ elsewhere; beware $\infty+\infty$ overflow.
11. **C++20 name clash**: with `using namespace std;`, a function named `identity` collides with `std::identity` — call it `eye`.

---

## 7. Going further (toward 2400–2600+)

- **Matrices in segment tree nodes** (range "apply Fibonacci shift"): [CF 718C · Sasha and Array](https://codeforces.com/problemset/problem/718/C) — 2300;
  with Fibonacci identities instead of matrices: [CF 446C · DZY Loves Fibonacci Numbers](https://codeforces.com/problemset/problem/446/C) — 2400.
- **Piecewise-constant transitions**: [CF 821E · Okabe and El Psy Kongroo](https://codeforces.com/problemset/problem/821/E) — 2100.
- **Tree-shaped recurrences with a sum state**: [CF 514E · Darth Vader and Tree](https://codeforces.com/problemset/problem/514/E) — 2200.
- **Min-plus / max-plus matrices in segment trees** (dynamic DP): [CF 750E · New Year and Old Subsequence](https://codeforces.com/problemset/problem/750/E) — 2600.
- **Kitamasa with NTT** ($O(k\log k\log n)$) and the Bostan–Mori algorithm for $[x^n]\frac{P(x)}{Q(x)}$ — see
  [polynomials](04-polynomials-and-generating-functions.md).
- **Finding the recurrence automatically**: [Berlekamp–Massey](05-lagrange-interpolation-and-berlekamp-massey.md).

---

## 8. Practice ladder

**≤1400**
- [ ] [AtCoder MATH-AND-ALGORITHM 049 · Fibonacci Easy (mod 1000000007)](https://atcoder.jp/contests/math-and-algorithm/tasks/math_and_algorithm_ap)
- [ ] [CF 185A · Plant](https://codeforces.com/problemset/problem/185/A) — 1300

**1400–1900**
- [ ] [CSES 1722 · Fibonacci Numbers](https://cses.fi/problemset/task/1722)
- [ ] [CF 166E · Tetrahedron](https://codeforces.com/problemset/problem/166/E) — 1500
- [ ] [CSES 1096 · Throwing Dice](https://cses.fi/problemset/task/1096)
- [ ] [AtCoder MATH-AND-ALGORITHM 055 · Recurrence Formula 1](https://atcoder.jp/contests/math-and-algorithm/tasks/math_and_algorithm_au)
- [ ] [AtCoder MATH-AND-ALGORITHM 056 · Recurrence Formula 2](https://atcoder.jp/contests/math-and-algorithm/tasks/math_and_algorithm_av)
- [ ] [CSES 1723 · Graph Paths I](https://cses.fi/problemset/task/1723)
- [ ] [CSES 1724 · Graph Paths II](https://cses.fi/problemset/task/1724)
- [ ] [CF 691E · Xor-sequences](https://codeforces.com/problemset/problem/691/E) — 1900
- [ ] [CF 222E · Decoding Genome](https://codeforces.com/problemset/problem/222/E) — 1900

**1900–2300**
- [ ] [CF 621E · Wet Shark and Blocks](https://codeforces.com/problemset/problem/621/E) — 2000
- [ ] [CF 852B · Neural Network country](https://codeforces.com/problemset/problem/852/B) — 2000
- [ ] [CF 1117D · Magic Gems](https://codeforces.com/problemset/problem/1117/D) — 2100
- [ ] [CF 821E · Okabe and El Psy Kongroo](https://codeforces.com/problemset/problem/821/E) — 2100
- [ ] [CF 514E · Darth Vader and Tree](https://codeforces.com/problemset/problem/514/E) — 2200
- [ ] [CF 1182E · Product Oriented Recurrence](https://codeforces.com/problemset/problem/1182/E) — 2300
- [ ] [CF 718C · Sasha and Array](https://codeforces.com/problemset/problem/718/C) — 2300

**2400+**
- [ ] [CF 446C · DZY Loves Fibonacci Numbers](https://codeforces.com/problemset/problem/446/C) — 2400
- [ ] [CF 750E · New Year and Old Subsequence](https://codeforces.com/problemset/problem/750/E) — 2600
- [ ] [AtCoder ABC300 Ex · Fibonacci: Revisited](https://atcoder.jp/contests/abc300/tasks/abc300_h) — diff≈3209

---

## 9. LeetCode / FAANG cross-reference

- [LC 509 · Fibonacci Number](https://leetcode.com/problems/fibonacci-number/) — Easy — the base case; mention $O(\log n)$ doubling as a follow-up.
- [LC 70 · Climbing Stairs](https://leetcode.com/problems/climbing-stairs/) — Easy — Fibonacci in disguise.
- [LC 1137 · N-th Tribonacci Number](https://leetcode.com/problems/n-th-tribonacci-number/) — Easy — order-3 companion matrix.
- [LC 935 · Knight Dialer](https://leetcode.com/problems/knight-dialer/) — Medium — $10\times10$ adjacency power for huge $n$.
- [LC 790 · Domino and Tromino Tiling](https://leetcode.com/problems/domino-and-tromino-tiling/) — Medium — linear recurrence $a_n=2a_{n-1}+a_{n-3}$.
- [LC 1220 · Count Vowels Permutation](https://leetcode.com/problems/count-vowels-permutation/) — Hard — $5\times5$ transition matrix.
- [LC 552 · Student Attendance Record II](https://leetcode.com/problems/student-attendance-record-ii/) — Hard — 6-state DP, matrix power if $n$ were huge.
- [LC 3337 · Total Characters in String After Transformations II](https://leetcode.com/problems/total-characters-in-string-after-transformations-ii/) — Hard — $26\times26$ matrix power.
- [LC 3700 · Number of ZigZag Arrays II](https://leetcode.com/problems/number-of-zigzag-arrays-ii/) — Hard — state-machine DP raised to a huge length.

Interviewers rarely require matrix power, but "can you do better than $O(n)$?" on Fibonacci-like DPs is a common follow-up.

---

## 10. Self-check

1. Write the companion matrix of $a_n=3a_{n-1}-a_{n-3}$ and the exponent needed to reach $a_n$ from $(a_2,a_1,a_0)$.
2. Derive $F_{2n}$ and $F_{2n+1}$ from $Q^{2n}=(Q^n)^2$.
3. Why is $(A^k)_{ij}$ the number of walks of length $k$?
4. Show that the top-right block of $\begin{pmatrix}A&I\\0&I\end{pmatrix}^n$ is $\sum_{i<n}A^i$.
5. Explain Kitamasa in one sentence. What is its complexity?
6. In Example 6, why modulo $p-1$, and what goes wrong if some $f_i$ is a multiple of $p$?
7. How many products can you accumulate in an unsigned 64-bit integer before reducing, for entries below $10^9+7$?

<details><summary>Answers</summary>

1. $M=\begin{pmatrix}3&0&-1\\1&0&0\\0&1&0\end{pmatrix}$ (entries mod $p$); $(a_n,a_{n-1},a_{n-2})^T=M^{n-2}(a_2,a_1,a_0)^T$.
2. $(Q^n)^2$ has top-right entry $F_{n+1}F_n+F_nF_{n-1}=F_n(F_{n+1}+F_{n-1})=F_n(2F_{n+1}-F_n)$ and top-left $F_{n+1}^2+F_n^2=F_{2n+1}$.
3. Induction: a walk of length $k+1$ from $i$ to $j$ is a walk of length $k$ to some $l$ followed by an edge $l\to j$.
4. Induction: $\begin{pmatrix}A^n&S_n\\0&I\end{pmatrix}\begin{pmatrix}A&I\\0&I\end{pmatrix}=\begin{pmatrix}A^{n+1}&A^n+S_n\\0&I\end{pmatrix}$.
5. The term-extraction functional kills multiples of the characteristic polynomial, so $a_n$ is read off from $x^n\bmod P(x)$, computed by
   repeated squaring: $O(k^2\log n)$.
6. Fermat's little theorem $g^{p-1}\equiv1$ needs $p\nmid g$; then exponents only matter mod $p-1$. A base divisible by $p$ makes the answer $0$
   (for positive exponent) and the reduction invalid — but inputs $\le10^9<p$ rule it out.
7. $\lfloor(2^{64}-1)/(10^9+6)^2\rfloor=18$; 16 is the convenient power of two.

</details>
