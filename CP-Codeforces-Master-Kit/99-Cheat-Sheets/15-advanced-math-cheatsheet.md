# Advanced math cheat sheet

Revision only — derivations in [15-Advanced-Math](../15-Advanced-Math/README.md): [matrices](../15-Advanced-Math/01-matrices-and-linear-recurrences.md) ·
[Gauss/XOR basis](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md) · [FFT/NTT](../15-Advanced-Math/03-fft-and-ntt.md) ·
[polynomials/GFs](../15-Advanced-Math/04-polynomials-and-generating-functions.md) · [Lagrange/BM](../15-Advanced-Math/05-lagrange-interpolation-and-berlekamp-massey.md) ·
[matrix-tree/LGV](../15-Advanced-Math/06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md).

## 1. Formulas

| Topic | Formula | Note |
|---|---|---|
| companion matrix | $s_{n}=M^{n-k+1}s_{k-1}$, row 0 $=(c_1..c_k)$, sub-diagonal 1s | $O(k^3\log n)$ |
| walks | $(A^k)_{ij}$ = walks of length $k$ | $(\min,+)$ for shortest |
| geometric series | $\begin{pmatrix}A&I\\0&I\end{pmatrix}^n=\begin{pmatrix}A^n&\sum_{i<n}A^i\\0&I\end{pmatrix}$ | never divide by $A-I$ |
| Fibonacci | $Q^n=\begin{pmatrix}F_{n+1}&F_n\\F_n&F_{n-1}\end{pmatrix}$ | |
| doubling | $F_{2n}=F_n(2F_{n+1}-F_n)$, $F_{2n+1}=F_n^2+F_{n+1}^2$ | |
| identities | $F_{m+n}=F_mF_{n+1}+F_{m-1}F_n$; Cassini $F_{n+1}F_{n-1}-F_n^2=(-1)^n$; $\gcd(F_m,F_n)=F_{\gcd}$ | |
| Kitamasa | $a_n=\sum r_ia_i$, $x^n\equiv\sum r_ix^i \pmod{x^k-\sum c_ix^{k-i}}$ | $O(k^2\log n)$ |
| exponents | $g^e\equiv g^{e\bmod(p-1)}$ ($p\nmid g$) | multiplicative recurrences |
| #solutions | $q^{m-\operatorname{rank}}$ if consistent | over $\mathbb F_q$ |
| determinant | $(-1)^{\#\text{swaps}}\prod$ pivots | composite $M$: Euclid rows |
| XOR basis | $2^r$ values; each by $2^{n-r}$ subsets; max: $v=\max(v,v\oplus b_i)$ high→low | $k$-th: reduce, read bits |
| DFT | $\hat a_k=\sum a_j\omega^{jk}$; $F^{-1}=\frac1N\bar F$ | $\sum_k\omega^{tk}=N[N\mid t]$ |
| butterfly | $A(\omega^k)=E+\omega^kO$, $A(\omega^{k+N/2})=E-\omega^kO$ | |
| Walsh–Hadamard | $(u,v)\to(u+v,u-v)$; inverse $/2^n$ | OR: $v\mathrel{+}=u$; AND: $u\mathrel{+}=v$ |
| wildcard match | $\sum P_jT_{i+j}(P_j-T_{i+j})^2=0$ | random letter values mod $p$ |
| geometric GF | $\frac1{1-x}=\sum x^n$, $\frac1{(1-x)^k}=\sum\binom{n+k-1}{k-1}x^n$ | stars and bars |
| Catalan | $C=1+xC^2$, $C=\frac{1-\sqrt{1-4x}}{2x}$, $C_n=\frac{1}{n+1}\binom{2n}n$ | |
| EGF | $\hat A\hat B\leftrightarrow\sum\binom nka_kb_{n-k}$; sets of connected: $e^{\hat C}$ | |
| pentagonal | $\prod(1-x^k)=\sum_j(-1)^jx^{j(3j-1)/2}$ | $p(n)$ via one inverse |
| Newton | inverse $B(2-AB)$; $\ln A=\int A'/A$; exp $B(1-\ln B+A)$; sqrt $\frac12(B+A/B)$ | $O(n\log n)$ |
| Lagrange (0..n) | $P(X)=\sum y_i\frac{\prod_{j\ne i}(X-j)}{i!(n-i)!(-1)^{n-i}}$ | $O(n)$ |
| power sums | $\sum_{i\le m}i^k$ has degree $k+1$ | $k+2$ samples |
| Fermat indicator | $1-(x-i)^{p-1}\equiv[x\equiv i]$; $\binom{p-1}{k}\equiv(-1)^k$ | |
| BM | $2L$ terms determine order $L$; prime modulus | $O(N^2)$ |
| Kirchhoff | $\tau=\det(D-A)_{\hat r\hat r}$; weighted: $\sum_T\prod w_e$ | $\tau(K_n)=n^{n-2}$ |
| Tutte | in-degree Laplacian minor = out-arborescences at $r$ | |
| BEST | $ec=t_w\prod_v(\deg^+v-1)!$ | |
| LGV | $\det[e(a_i,b_j)]=$ signed disjoint systems | 2 paths: $e_{11}e_{22}-e_{12}e_{21}$ |
| Thomas | $c'_j=\frac{c_j}{b_j-a_jc'_{j-1}}$, $d'_j=\frac{d_j-a_jd'_{j-1}}{b_j-a_jc'_{j-1}}$ | tridiagonal $O(n)$ |

## 2. Constants

| Constant | Value |
|---|---|
| NTT prime | $998244353=119\cdot2^{23}+1$, root $3$, max length $2^{23}$ |
| CRT primes (root 3) | $167772161=5\cdot2^{25}+1$, $469762049=7\cdot2^{26}+1$ |
| other | $754974721=45\cdot2^{24}+1$ (root 11) |
| `double` FFT exact | true results $\lesssim10^{14}$ |
| lazy reduction | unsigned 64-bit: 16 products $<2^{60}$; Java `long`: 8 |
| subspaces of GF(2)$^5$ | 374 (DP over subspaces) |
| primes $\le70$ | 19 (square-product parity vectors) |

## 3. Signal → technique

| Signal | Technique |
|---|---|
| $n\le10^{18}$, fixed small-state DP | matrix power (or BM + Kitamasa) |
| "$f_n=f_{n-1}^a\cdots$" | exponents mod $p-1$ |
| "count subsets with XOR / square product" | GF(2) rank, $2^{n-r}$ |
| "max XOR on range" | prefix linear basis, offline by $r$ |
| "XOR path in graph" | DFS depths + cycle basis |
| "for every $k$: pairs with sum $k$" | convolution |
| modulus $998244353$ | NTT |
| "match with wildcards", "mismatches per shift" | convolution with reversed pattern |
| "$\bigoplus$/OR/AND over pairs of masks" | Walsh–Hadamard / zeta |
| "multisets with bounded copies", "product of many small polys" | D&C NTT/FFT |
| "labelled", "connected" counting for all $n$ | EGF + $\ln$/$\exp$ |
| huge parameter, polynomial DP | sample + Lagrange |
| "spanning trees", "with exactly $k$ special edges" | Kirchhoff (weighted + interpolation) |
| "two non-crossing paths" | LGV |
| expectation with back-edges | linear system (tridiagonal if neighbours only) |

## 4. Templates

### 4.1 Matrix multiply (lazy reduction) and power

```cpp
const ll MOD = 1'000'000'007;
using Mat = vector<vector<ll>>;
Mat mul(const Mat& A, const Mat& B) {
    int n = A.size(), K = B.size(), m = B[0].size();
    Mat C(n, vector<ll>(m));
    vector<ull> acc(m);
    for (int i = 0; i < n; i++) {
        fill(acc.begin(), acc.end(), 0);
        for (int k = 0; k < K; k++) {
            ull a = A[i][k];
            if (!a) continue;
            for (int j = 0; j < m; j++) acc[j] += a * (ull)B[k][j];
            if ((k & 15) == 15) for (int j = 0; j < m; j++) acc[j] %= MOD;
        }
        for (int j = 0; j < m; j++) C[i][j] = acc[j] % MOD;
    }
    return C;
}
Mat mpow(Mat A, ull e) {
    Mat R(A.size(), vector<ll>(A.size(), 0));
    for (size_t i = 0; i < A.size(); i++) R[i][i] = 1;
    for (; e; e >>= 1, A = mul(A, A)) if (e & 1) R = mul(R, A);
    return R;
}
```

```java
static final long MOD = 1_000_000_007L;
static long[][] mul(long[][] A, long[][] B) {
    int n = A.length, K = B.length, m = B[0].length;
    long[][] C = new long[n][m];
    long[] acc = new long[m];
    for (int i = 0; i < n; i++) {
        Arrays.fill(acc, 0);
        for (int k = 0; k < K; k++) {
            long a = A[i][k];
            if (a == 0) continue;
            for (int j = 0; j < m; j++) acc[j] += a * B[k][j];
            if ((k & 7) == 7) for (int j = 0; j < m; j++) acc[j] %= MOD;
        }
        for (int j = 0; j < m; j++) C[i][j] = acc[j] % MOD;
    }
    return C;
}
static long[][] mpow(long[][] A, long e) {
    long[][] R = new long[A.length][A.length];
    for (int i = 0; i < A.length; i++) R[i][i] = 1;
    for (; e > 0; e >>= 1, A = mul(A, A)) if ((e & 1) == 1) R = mul(R, A);
    return R;
}
```

### 4.2 XOR basis

```cpp
struct XorBasis {
    ll b[60] = {};
    int rank = 0;
    bool insert(ll x) {
        for (int i = 59; i >= 0; i--) if (x >> i & 1) {
            if (!b[i]) { b[i] = x; rank++; return true; }
            x ^= b[i];
        }
        return false;
    }
    ll maxXor(ll v = 0) const { for (int i = 59; i >= 0; i--) v = max(v, v ^ b[i]); return v; }
    ll minXor(ll v) const { for (int i = 59; i >= 0; i--) v = min(v, v ^ b[i]); return v; }
};
```

```java
static final class XorBasis {
    final long[] b = new long[60];
    int rank = 0;
    boolean insert(long x) {
        for (int i = 59; i >= 0; i--) if ((x >> i & 1) == 1) {
            if (b[i] == 0) { b[i] = x; rank++; return true; }
            x ^= b[i];
        }
        return false;
    }
    long maxXor(long v) { for (int i = 59; i >= 0; i--) v = Math.max(v, v ^ b[i]); return v; }
    long minXor(long v) { for (int i = 59; i >= 0; i--) v = Math.min(v, v ^ b[i]); return v; }
}
```

### 4.3 NTT convolution (mod 998244353)

```cpp
const ll P = 998244353;
ll pw(ll b, ll e) { ll r = 1; b %= P; for (; e; e >>= 1, b = b * b % P) if (e & 1) r = r * b % P; return r; }
void ntt(vector<ll>& a, bool inv) {
    int n = a.size();
    for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; j & bit; bit >>= 1) j ^= bit; j ^= bit; if (i < j) swap(a[i], a[j]); }
    for (int len = 2; len <= n; len <<= 1) {
        ll wl = pw(3, (P - 1) / len);
        if (inv) wl = pw(wl, P - 2);
        for (int i = 0; i < n; i += len) {
            ll w = 1;
            for (int j = 0; j < len / 2; j++, w = w * wl % P) {
                ll u = a[i + j], v = a[i + j + len / 2] * w % P;
                a[i + j] = (u + v) % P; a[i + j + len / 2] = (u - v + P) % P;
            }
        }
    }
    if (inv) { ll ni = pw(n, P - 2); for (auto& x : a) x = x * ni % P; }
}
vector<ll> conv(vector<ll> a, vector<ll> b) {
    int need = a.size() + b.size() - 1, n = 1;
    while (n < need) n <<= 1;
    a.resize(n); b.resize(n);
    ntt(a, false); ntt(b, false);
    for (int i = 0; i < n; i++) a[i] = a[i] * b[i] % P;
    ntt(a, true);
    a.resize(need);
    return a;
}
```

```java
static final long P = 998244353L;
static long pw(long b, long e) { long r = 1; b %= P; for (; e > 0; e >>= 1, b = b * b % P) if ((e & 1) == 1) r = r * b % P; return r; }
static void ntt(long[] a, boolean inv) {
    int n = a.length;
    for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; (j & bit) != 0; bit >>= 1) j ^= bit; j ^= bit; if (i < j) { long t = a[i]; a[i] = a[j]; a[j] = t; } }
    for (int len = 2; len <= n; len <<= 1) {
        long wl = pw(3, (P - 1) / len);
        if (inv) wl = pw(wl, P - 2);
        for (int i = 0; i < n; i += len) {
            long w = 1;
            for (int j = 0; j < len / 2; j++, w = w * wl % P) {
                long u = a[i + j], v = a[i + j + len / 2] * w % P;
                a[i + j] = (u + v) % P; a[i + j + len / 2] = (u - v + P) % P;
            }
        }
    }
    if (inv) { long ni = pw(n, P - 2); for (int i = 0; i < n; i++) a[i] = a[i] * ni % P; }
}
static long[] conv(long[] a, long[] b) {
    int need = a.length + b.length - 1, n = 1;
    while (n < need) n <<= 1;
    long[] fa = Arrays.copyOf(a, n), fb = Arrays.copyOf(b, n);
    ntt(fa, false); ntt(fb, false);
    for (int i = 0; i < n; i++) fa[i] = fa[i] * fb[i] % P;
    ntt(fa, true);
    return Arrays.copyOf(fa, need);
}
```

### 4.4 Walsh–Hadamard (XOR), Lagrange on $0..n$, Berlekamp–Massey

```cpp
void fwhtXor(vector<ll>& a, bool inv) {
    int n = a.size();
    for (int len = 1; 2 * len <= n; len <<= 1)
        for (int i = 0; i < n; i += 2 * len)
            for (int j = i; j < i + len; j++) { ll u = a[j], v = a[j + len]; a[j] = u + v; a[j + len] = u - v; }
    if (inv) for (auto& x : a) x /= n;
}
const ll M7 = 1'000'000'007;
ll pw7(ll b, ll e) { ll r = 1; b %= M7; if (b < 0) b += M7; for (; e; e >>= 1, b = b * b % M7) if (e & 1) r = r * b % M7; return r; }
ll lagrange0n(const vector<ll>& y, ll X) {                // P(i) = y[i], i = 0..n
    int n = (int)y.size() - 1;
    X %= M7;
    if (X <= n) return y[X];
    vector<ll> pre(n + 2, 1), suf(n + 2, 1), f(n + 1, 1);
    for (int i = 0; i <= n; i++) pre[i + 1] = pre[i] * ((X - i) % M7) % M7;
    for (int i = n; i >= 0; i--) suf[i] = suf[i + 1] * ((X - i) % M7) % M7;
    for (int i = 1; i <= n; i++) f[i] = f[i - 1] * i % M7;
    ll res = 0;
    for (int i = 0; i <= n; i++) {
        ll t = y[i] * pre[i] % M7 * suf[i + 1] % M7 * pw7(f[i] * f[n - i] % M7, M7 - 2) % M7;
        res = ((n - i) & 1) ? (res - t + M7) % M7 : (res + t) % M7;
    }
    return res;
}
vector<ll> berlekampMassey(const vector<ll>& s) {         // s_n = sum c[i-1] s_{n-i}
    vector<ll> C = {1}, B = {1};
    int L = 0, m = 1; ll b = 1;
    for (size_t n = 0; n < s.size(); n++) {
        ll d = 0;
        for (int i = 0; i <= L && i < (int)C.size(); i++) d = (d + C[i] * s[n - i]) % M7;
        if (!d) { m++; continue; }
        vector<ll> T = C;
        ll coef = d * pw7(b, M7 - 2) % M7;
        if (C.size() < B.size() + m) C.resize(B.size() + m, 0);
        for (size_t i = 0; i < B.size(); i++) C[i + m] = (C[i + m] - coef * B[i] % M7 + M7) % M7;
        if (2 * L <= (int)n) { L = n + 1 - L; B = T; b = d; m = 1; } else m++;
    }
    vector<ll> c(L);
    for (int i = 1; i <= L; i++) c[i - 1] = (M7 - (i < (int)C.size() ? C[i] : 0)) % M7;
    return c;
}
```

```java
static void fwhtXor(long[] a, boolean inv) {
    int n = a.length;
    for (int len = 1; 2 * len <= n; len <<= 1)
        for (int i = 0; i < n; i += 2 * len)
            for (int j = i; j < i + len; j++) { long u = a[j], v = a[j + len]; a[j] = u + v; a[j + len] = u - v; }
    if (inv) for (int i = 0; i < n; i++) a[i] /= n;
}
static final long M7 = 1_000_000_007L;
static long pw7(long b, long e) { long r = 1; b %= M7; if (b < 0) b += M7; for (; e > 0; e >>= 1, b = b * b % M7) if ((e & 1) == 1) r = r * b % M7; return r; }
static long lagrange0n(long[] y, long X) {
    int n = y.length - 1;
    X %= M7;
    if (X <= n) return y[(int) X];
    long[] pre = new long[n + 2], suf = new long[n + 2], f = new long[n + 1];
    pre[0] = 1; suf[n + 1] = 1; f[0] = 1;
    for (int i = 0; i <= n; i++) pre[i + 1] = pre[i] * ((X - i) % M7) % M7;
    for (int i = n; i >= 0; i--) suf[i] = suf[i + 1] * ((X - i) % M7) % M7;
    for (int i = 1; i <= n; i++) f[i] = f[i - 1] * i % M7;
    long res = 0;
    for (int i = 0; i <= n; i++) {
        long t = y[i] * pre[i] % M7 * suf[i + 1] % M7 * pw7(f[i] * f[n - i] % M7, M7 - 2) % M7;
        res = ((n - i) & 1) == 1 ? (res - t + M7) % M7 : (res + t) % M7;
    }
    return res;
}
static long[] berlekampMassey(long[] s) {
    long[] C = {1}, B = {1};
    int L = 0, m = 1; long b = 1;
    for (int n = 0; n < s.length; n++) {
        long d = 0;
        for (int i = 0; i <= L && i < C.length; i++) d = (d + C[i] * s[n - i]) % M7;
        if (d == 0) { m++; continue; }
        long[] T = C.clone();
        long coef = d * pw7(b, M7 - 2) % M7;
        if (C.length < B.length + m) C = Arrays.copyOf(C, B.length + m);
        for (int i = 0; i < B.length; i++) C[i + m] = (C[i + m] - coef * B[i] % M7 + M7) % M7;
        if (2 * L <= n) { L = n + 1 - L; B = T; b = d; m = 1; } else m++;
    }
    long[] c = new long[L];
    for (int i = 1; i <= L; i++) c[i - 1] = (M7 - (i < C.length ? C[i] : 0)) % M7;
    return c;
}
```

Kitamasa for the $n$-th term after BM: [file 01 §3.1](../15-Advanced-Math/01-matrices-and-linear-recurrences.md). Determinant mod $p$ / mod composite and
Kirchhoff builders: [file 06 §3](../15-Advanced-Math/06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md).

## 5. Top 10 mistakes

1. Matrix power off by one ($M^{n-k+1}$ vs $M^n$); not handling $n<k$.
2. Overflowing the lazy accumulator (more than 16 / 8 products before `%`).
3. Exponents reduced mod $p$ instead of $p-1$.
4. NTT length $<\deg A+\deg B+1$ (cyclic wrap-around); length beyond $2^{23}$.
5. Exact counts that exceed the NTT prime (use `double` FFT or CRT).
6. `double` FFT with results above $10^{14}$; roots built by repeated multiplication.
7. XOR basis: `1 << i` instead of `1LL << i`; confusing pair max-XOR (trie) with subset max-XOR (basis); unreduced basis for $k$-th.
8. Newton iterations without truncation to $x^{2k}$; $\ln$ with $a_0\ne1$, $\exp$ with $a_0\ne0$.
9. Interpolation with too few points (degree miscounted); forgetting the $(-1)^{n-i}$ sign.
10. Laplacian built with self-loops, or the directed version with out-degrees when counting out-trees.

## 6. Last-minute before contest

- [ ] NTT + `conv` pasted and tested on a $2\times2$ example; know $998244353$, root $3$.
- [ ] Matrix `mul`/`mpow` with lazy reduction; Fibonacci doubling.
- [ ] XOR basis struct; remember $2^{n-r}$.
- [ ] Lagrange on $0..n$ and BM + Kitamasa ready for "huge $n$" counting.
- [ ] Determinant mod $p$ (and Euclid version for composite moduli).
- [ ] Java: `long` everywhere, `(a * b) % MOD` only when both $<2^{31.5}$; `Arrays.sort` on primitives only after shuffling.
