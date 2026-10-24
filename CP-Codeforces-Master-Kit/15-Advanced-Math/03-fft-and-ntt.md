# FFT, NTT and Walsh–Hadamard transforms

> **Band:** 🟣 1900 – 🔴 2600 · **Priority:** 🔥 (NTT convolution, counting pair sums) · ⚡ (complex FFT and its precision, FWHT, wildcard matching) · 🔴 (arbitrary-modulus convolution) · **FAANG:** none · **Prerequisites:** [modular arithmetic](../04-Number-Theory/02-modular-arithmetic-and-inverses.md), [primitive roots](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md), [SOS DP and subset convolution](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md)
> **You can say you know this when:** you can derive the DFT recursion and the inverse transform from the orthogonality of roots of
> unity, write an iterative NTT modulo $998244353$ from memory, know when `double` FFT is exact enough and what to do when it is not,
> and turn "count pairs with sum/difference/XOR $=k$" or "match with wildcards" into convolutions.

---

## 1. First principles — why this works

### 1.1 The problem: convolution

The product of $A(x)=\sum a_ix^i$ and $B(x)=\sum b_jx^j$ has coefficients $c_k=\sum_{i+j=k}a_ib_j$ — a **convolution**. It appears whenever
two independent choices *add*: "count pairs $(i,j)$ with $a$-value $i$ and $b$-value $j$ summing to $k$", "sum of dice", "align a pattern at
every shift". Naively $O(nm)$. We want $O(N\log N)$ with $N\ge n+m-1$.

### 1.2 Evaluate, multiply, interpolate

A polynomial of degree $<N$ is determined by its values at $N$ distinct points (Lagrange/Vandermonde). In value form, multiplication is
pointwise: $C(x_t)=A(x_t)B(x_t)$, $O(N)$. So: **evaluate** $A$, $B$ at $N$ points, multiply, **interpolate** back. Naive evaluation is $O(N^2)$;
the whole trick is to choose points where evaluation splits recursively.

### 1.3 Roots of unity make evaluation recursive

Let $N$ be a power of two and $\omega=e^{2\pi i/N}$. The $N$-th roots of unity $\omega^0,\dots,\omega^{N-1}$ have two properties:

- $\omega^{N/2}=-1$, so $\omega^{k+N/2}=-\omega^k$ (the points come in $\pm$ pairs);
- **halving lemma:** $(\omega^k)^2=\omega_{N/2}^{\,k}$ — the squares of the $N$-th roots are the $N/2$-th roots, each twice.

Split $A$ into even and odd coefficients: $A(x)=E(x^2)+x\,O(x^2)$ with $E,O$ of degree $<N/2$. Then for $k<N/2$:

$$A(\omega^k)=E(\omega_{N/2}^k)+\omega^kO(\omega_{N/2}^k),\qquad A(\omega^{k+N/2})=E(\omega_{N/2}^k)-\omega^kO(\omega_{N/2}^k).$$

Two half-size evaluations plus $O(N)$ "butterflies": $T(N)=2T(N/2)+O(N)=O(N\log N)$. This evaluation map is the **DFT**:
$\hat a_k=\sum_ja_j\omega^{jk}$.

### 1.4 The inverse is the same transform

The DFT matrix is $F_{kj}=\omega^{kj}$. **Orthogonality:** for an integer $t$,
$\sum_{k=0}^{N-1}\omega^{tk}=N$ if $N\mid t$, and $=\frac{\omega^{tN}-1}{\omega^t-1}=0$ otherwise (geometric series; $\omega^{tN}=1$).
Hence $(\bar F F)_{lj}=\sum_k\omega^{-lk}\omega^{kj}=N[l=j]$, i.e. $F^{-1}=\frac1N\bar F$: **the inverse DFT is the DFT with $\omega^{-1}$, divided by $N$.**
No separate interpolation algorithm is needed.

### 1.5 Iterative version and bit reversal

Unrolling the recursion, the leaves (single coefficients) appear in **bit-reversed** order of their indices (index $j$ goes to the leaf whose
path is the bits of $j$ read from least significant). So: permute the array by bit reversal, then for $\text{len}=2,4,\dots,N$ combine adjacent
blocks with butterflies $(u,v)\mapsto(u+wv,\ u-wv)$. In-place, no recursion, cache-friendly.

### 1.6 NTT: the same algebra in $\mathbb{Z}_p$

The derivation used only: $\omega^N=1$, $\omega^{N/2}=-1$, $\omega^t\ne1$ for $0<t<N$, and that $N$ is invertible. In $\mathbb{Z}_p$ ($p$ prime) the
multiplicative group is cyclic of order $p-1$ with a generator $g$ (primitive root). If $N\mid p-1$, then $\omega=g^{(p-1)/N}$ has order exactly $N$
— all properties hold, and arithmetic is **exact**.

$p=998244353=119\cdot2^{23}+1$ with primitive root $3$ supports $N$ up to $2^{23}\approx8.4\cdot10^6$. That is why so many problems use this
modulus. Other NTT-friendly primes: $167772161=5\cdot2^{25}+1$ and $469762049=7\cdot2^{26}+1$ (both with primitive root 3), and
$754974721=45\cdot2^{24}+1$ (primitive root 11).

### 1.7 Precision of complex FFT, and what to do about it

With `double`, each output coefficient has absolute error roughly $\varepsilon\cdot\log N\cdot\lVert a\rVert\lVert b\rVert$ (norms of the inputs). In
practice: if the **true results are below $\sim10^{14}$–$10^{15}$**, rounding to the nearest integer is safe; beyond that it silently fails.
Coefficients below $10^9$ with $N=10^6$ give results up to $10^{24}$ — impossible directly. Options:

1. **NTT** when the problem's modulus is NTT-friendly, or when the true results are $<p$ (exact counts).
2. **Three NTT primes + CRT** (Garner): any modulus, results up to $p_1p_2p_3\approx7.8\cdot10^{25}$ are reconstructed exactly. 9 transforms.
3. **Split FFT** (🔴): write $a=a_1\cdot2^{15}+a_0$, so pieces are $<2^{15}$; four products of small pieces (computed with 2–4 complex FFTs using
   the real/imaginary packing trick) stay below $10^{14}$; recombine modulo $M$.

### 1.8 What else is a convolution

- **Pair counts:** $\#\{(i,j):a_i+b_j=k\}$ = convolution of the value histograms. Differences: reverse one histogram.
- **Pattern matching:** align pattern $P$ at shift $i$ of text $T$: $\sum_jf(P_j,T_{i+j})$ is a convolution of $T$ with the **reversed** pattern
  when $f$ is a product of a function of $P_j$ and a function of $T_{i+j}$. With wildcards (value $0$), the score
  $\sum_jP_jT_{i+j}(P_j-T_{i+j})^2=\sum P_j^3T_{i+j}-2P_j^2T_{i+j}^2+P_jT_{i+j}^3$ is zero exactly at matches: three convolutions.
- **Mismatch counting per letter:** for each letter $c$, convolve "$T=c$" with reversed "$P=c$" and sum over letters.
- **XOR/AND/OR convolution:** the **Walsh–Hadamard transform**. For XOR: $\hat a_S=\sum_i(-1)^{\lvert i\wedge S\rvert}a_i$. Since
  $(-1)^{\lvert(i\oplus j)\wedge S\rvert}=(-1)^{\lvert i\wedge S\rvert}(-1)^{\lvert j\wedge S\rvert}$, the transform turns XOR-convolution into a pointwise
  product; applying it twice multiplies by $2^n$, so the inverse is the same transform divided by $2^n$. Butterfly: $(u,v)\mapsto(u+v,u-v)$.
  OR-convolution uses the subset-sum (zeta) transform $\hat a_S=\sum_{i\subseteq S}a_i$ (butterfly $v\leftarrow v+u$), AND uses superset sums
  ([SOS DP](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md)).

---

## 2. Formulas, definitions and identities

| Formula | Meaning |
|---|---|
| $c_k=\sum_{i+j=k}a_ib_j$ | convolution, $\deg C=\deg A+\deg B$ |
| $\omega_N=e^{2\pi i/N}$, $\omega^{N/2}=-1$, $\omega_N^2=\omega_{N/2}$ | roots of unity, halving lemma |
| $A(x)=E(x^2)+xO(x^2)$; $A(\omega^{k+N/2})=E-\omega^kO$ | butterfly |
| $\sum_{k<N}\omega^{tk}=N[N\mid t]$ | orthogonality |
| $F^{-1}=\frac1N\bar F$ | inverse DFT |
| $T(N)=2T(N/2)+O(N)=O(N\log N)$ | cost |
| $998244353=119\cdot2^{23}+1$, $g=3$ | NTT prime, $N\le2^{23}$ |
| $\omega_N=g^{(p-1)/N}$, $\omega_N^{-1}=\omega_N^{p-2}$, $N^{-1}=N^{p-2}$ | NTT constants |
| $167772161=5\cdot2^{25}+1$, $469762049=7\cdot2^{26}+1$ ($g=3$) | CRT primes |
| `double` FFT safe when results $\lesssim10^{14}$ | precision rule of thumb |
| $\hat a_S=\sum_i(-1)^{\lvert i\wedge S\rvert}a_i$, $H^2=2^nI$ | Walsh–Hadamard (XOR) |
| OR: $\hat a_S=\sum_{i\subseteq S}a_i$; AND: $\hat a_S=\sum_{i\supseteq S}a_i$ | zeta transforms |
| $\sum_jP_jT_{i+j}(P_j-T_{i+j})^2=0$ | wildcard match at shift $i$ |
| Garner: $x=r_1+p_1\big((r_2-r_1)p_1^{-1}\bmod p_2\big)+\dots$ | CRT reconstruction |

**Garner's formula derivation.** Want $x\bmod p_1p_2$ with $x\equiv r_1\pmod{p_1}$, $x\equiv r_2\pmod{p_2}$. Write $x=r_1+p_1k$; then
$r_1+p_1k\equiv r_2\pmod{p_2}$ gives $k\equiv(r_2-r_1)p_1^{-1}\pmod{p_2}$. Repeat with the third prime on $x_{12}=r_1+p_1k$. All intermediate
values stay below $p_1p_2<2^{63}$; the final combination is done modulo the target $M$.

---

## 3. Implementation (C++ and Java)

### 3.1 NTT modulo $998244353$ and complex FFT

```cpp
const int NTT_MOD = 998244353, NTT_G = 3;
ll pw(ll b, ll e, ll m = NTT_MOD) { ll r = 1; b %= m; for (; e; e >>= 1, b = b * b % m) if (e & 1) r = r * b % m; return r; }
void ntt(vector<ll>& a, bool invert, ll mod = NTT_MOD, ll g = NTT_G) {
    int n = a.size();
    for (int i = 1, j = 0; i < n; i++) {                       // bit-reversal permutation
        int bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) swap(a[i], a[j]);
    }
    vector<ll> w(n / 2 + 1);
    for (int len = 2; len <= n; len <<= 1) {
        ll wl = pw(g, (mod - 1) / len, mod);
        if (invert) wl = pw(wl, mod - 2, mod);
        w[0] = 1;
        for (int j = 1; j < len / 2; j++) w[j] = w[j - 1] * wl % mod;   // powers of the len-th root
        for (int i = 0; i < n; i += len)
            for (int j = 0; j < len / 2; j++) {
                ll u = a[i + j], v = a[i + j + len / 2] * w[j] % mod;
                a[i + j] = u + v < mod ? u + v : u + v - mod;
                a[i + j + len / 2] = u - v >= 0 ? u - v : u - v + mod;
            }
    }
    if (invert) { ll inv = pw(n, mod - 2, mod); for (auto& x : a) x = x * inv % mod; }
}
vector<ll> convolution(vector<ll> a, vector<ll> b, ll mod = NTT_MOD, ll g = NTT_G) {
    if (a.empty() || b.empty()) return {};
    int need = a.size() + b.size() - 1, n = 1;
    while (n < need) n <<= 1;
    a.resize(n); b.resize(n);
    ntt(a, false, mod, g); ntt(b, false, mod, g);
    for (int i = 0; i < n; i++) a[i] = a[i] * b[i] % mod;
    ntt(a, true, mod, g);
    a.resize(need);
    return a;
}
using cd = complex<double>;
void fft(vector<cd>& a, bool invert) {
    int n = a.size();
    for (int i = 1, j = 0; i < n; i++) {
        int bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) swap(a[i], a[j]);
    }
    const double PI = acos(-1.0);
    vector<cd> root(n / 2);                                    // exact cos/sin per root: no drift from repeated products
    for (int j = 0; j < n / 2; j++) root[j] = cd(cos(2 * PI * j / n), (invert ? -1 : 1) * sin(2 * PI * j / n));
    for (int len = 2; len <= n; len <<= 1)
        for (int i = 0, step = n / len; i < n; i += len)
            for (int j = 0; j < len / 2; j++) {
                cd u = a[i + j], v = a[i + j + len / 2] * root[j * step];
                a[i + j] = u + v; a[i + j + len / 2] = u - v;
            }
    if (invert) for (auto& x : a) x /= n;
}
// Exact integer product when every true result is below ~1e14.
vector<ll> multiplyFFT(const vector<ll>& a, const vector<ll>& b) {
    int need = a.size() + b.size() - 1, n = 1;
    while (n < need) n <<= 1;
    vector<cd> fa(n), fb(n);
    for (size_t i = 0; i < a.size(); i++) fa[i] = (double)a[i];
    for (size_t i = 0; i < b.size(); i++) fb[i] = (double)b[i];
    fft(fa, false); fft(fb, false);
    for (int i = 0; i < n; i++) fa[i] *= fb[i];
    fft(fa, true);
    vector<ll> c(need);
    for (int i = 0; i < need; i++) c[i] = llround(fa[i].real());
    return c;
}
```

```java
static final long NTT_MOD = 998244353L, NTT_G = 3;
static long pw(long b, long e, long m) { long r = 1; b %= m; if (b < 0) b += m; for (; e > 0; e >>= 1, b = b * b % m) if ((e & 1) == 1) r = r * b % m; return r; }
static void ntt(long[] a, boolean invert, long mod, long g) {
    int n = a.length;
    for (int i = 1, j = 0; i < n; i++) {
        int bit = n >> 1;
        for (; (j & bit) != 0; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) { long t = a[i]; a[i] = a[j]; a[j] = t; }
    }
    long[] w = new long[Math.max(1, n / 2)];
    for (int len = 2; len <= n; len <<= 1) {
        long wl = pw(g, (mod - 1) / len, mod);
        if (invert) wl = pw(wl, mod - 2, mod);
        w[0] = 1;
        for (int j = 1; j < len / 2; j++) w[j] = w[j - 1] * wl % mod;
        int half = len >> 1;
        for (int i = 0; i < n; i += len)
            for (int j = 0; j < half; j++) {
                long u = a[i + j], v = a[i + j + half] * w[j] % mod;
                a[i + j] = u + v < mod ? u + v : u + v - mod;
                a[i + j + half] = u - v >= 0 ? u - v : u - v + mod;
            }
    }
    if (invert) { long inv = pw(n, mod - 2, mod); for (int i = 0; i < n; i++) a[i] = a[i] * inv % mod; }
}
static long[] convolution(long[] a, long[] b, long mod, long g) {
    if (a.length == 0 || b.length == 0) return new long[0];
    int need = a.length + b.length - 1, n = 1;
    while (n < need) n <<= 1;
    long[] fa = Arrays.copyOf(a, n), fb = Arrays.copyOf(b, n);
    ntt(fa, false, mod, g); ntt(fb, false, mod, g);
    for (int i = 0; i < n; i++) fa[i] = fa[i] * fb[i] % mod;
    ntt(fa, true, mod, g);
    return Arrays.copyOf(fa, need);
}
// Complex FFT on parallel arrays (re, im).
static void fft(double[] re, double[] im, boolean invert) {
    int n = re.length;
    for (int i = 1, j = 0; i < n; i++) {
        int bit = n >> 1;
        for (; (j & bit) != 0; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) { double t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t; }
    }
    double[] cr = new double[Math.max(1, n / 2)], ci = new double[Math.max(1, n / 2)];
    for (int j = 0; j < n / 2; j++) { cr[j] = Math.cos(2 * Math.PI * j / n); ci[j] = (invert ? -1 : 1) * Math.sin(2 * Math.PI * j / n); }
    for (int len = 2; len <= n; len <<= 1) {
        int half = len >> 1, step = n / len;
        for (int i = 0; i < n; i += len)
            for (int j = 0; j < half; j++) {
                double wr = cr[j * step], wi = ci[j * step];
                double xr = re[i + j + half] * wr - im[i + j + half] * wi, xi = re[i + j + half] * wi + im[i + j + half] * wr;
                re[i + j + half] = re[i + j] - xr; im[i + j + half] = im[i + j] - xi;
                re[i + j] += xr; im[i + j] += xi;
            }
    }
    if (invert) for (int i = 0; i < n; i++) { re[i] /= n; im[i] /= n; }
}
static long[] multiplyFFT(long[] a, long[] b) {
    int need = a.length + b.length - 1, n = 1;
    while (n < need) n <<= 1;
    double[] ar = new double[n], ai = new double[n], br = new double[n], bi = new double[n];
    for (int i = 0; i < a.length; i++) ar[i] = a[i];
    for (int i = 0; i < b.length; i++) br[i] = b[i];
    fft(ar, ai, false); fft(br, bi, false);
    for (int i = 0; i < n; i++) { double r = ar[i] * br[i] - ai[i] * bi[i]; ai[i] = ar[i] * bi[i] + ai[i] * br[i]; ar[i] = r; }
    fft(ar, ai, true);
    long[] c = new long[need];
    for (int i = 0; i < need; i++) c[i] = Math.round(ar[i]);
    return c;
}
```

### 3.2 Arbitrary modulus: three NTT primes + Garner (🔴), tested

Input: $n$, $m$, modulus $M$, then $a$ and $b$. Output $a*b \bmod M$; for small sizes the program also checks against the naive product
and prints `OK`.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
ll pw(ll b, ll e, ll m) { ll r = 1; b %= m; for (; e; e >>= 1, b = b * b % m) if (e & 1) r = r * b % m; return r; }
void ntt(vector<ll>& a, bool inv, ll mod, ll g) {
    int n = a.size();
    for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; j & bit; bit >>= 1) j ^= bit; j ^= bit; if (i < j) swap(a[i], a[j]); }
    vector<ll> w(n / 2 + 1);
    for (int len = 2; len <= n; len <<= 1) {
        ll wl = pw(g, (mod - 1) / len, mod);
        if (inv) wl = pw(wl, mod - 2, mod);
        w[0] = 1;
        for (int j = 1; j < len / 2; j++) w[j] = w[j - 1] * wl % mod;
        for (int i = 0; i < n; i += len) for (int j = 0; j < len / 2; j++) {
            ll u = a[i + j], v = a[i + j + len / 2] * w[j] % mod;
            a[i + j] = (u + v) % mod; a[i + j + len / 2] = (u - v + mod) % mod;
        }
    }
    if (inv) { ll ni = pw(n, mod - 2, mod); for (auto& x : a) x = x * ni % mod; }
}
vector<ll> conv(vector<ll> a, vector<ll> b, ll mod, ll g) {
    int need = a.size() + b.size() - 1, n = 1;
    while (n < need) n <<= 1;
    for (auto& x : a) x %= mod;
    for (auto& x : b) x %= mod;
    a.resize(n); b.resize(n);
    ntt(a, false, mod, g); ntt(b, false, mod, g);
    for (int i = 0; i < n; i++) a[i] = a[i] * b[i] % mod;
    ntt(a, true, mod, g);
    a.resize(need);
    return a;
}
vector<ll> convAnyMod(const vector<ll>& a, const vector<ll>& b, ll M) {
    const ll p1 = 998244353, p2 = 167772161, p3 = 469762049;
    auto c1 = conv(a, b, p1, 3), c2 = conv(a, b, p2, 3), c3 = conv(a, b, p3, 3);
    const ll inv_p1_mod_p2 = pw(p1, p2 - 2, p2), inv_p12_mod_p3 = pw(p1 % p3 * (p2 % p3) % p3, p3 - 2, p3);
    vector<ll> res(c1.size());
    for (size_t i = 0; i < c1.size(); i++) {
        ll k1 = (c2[i] - c1[i] % p2 + p2) % p2 * inv_p1_mod_p2 % p2;
        ll x12 = c1[i] + p1 * k1;                              // exact value mod p1*p2 (< 2^58)
        ll k2 = ((c3[i] - x12 % p3) % p3 + p3) % p3 * inv_p12_mod_p3 % p3;
        res[i] = (ll)((x12 % M + (__int128)(p1 * p2 % M) * k2) % M);   // x = x12 + p1*p2*k2 (128-bit: M may exceed 2^31)
    }
    return res;
}
int main() {
    int n, m; ll M; cin >> n >> m >> M;
    vector<ll> a(n), b(m);
    for (auto& x : a) cin >> x;
    for (auto& x : b) cin >> x;
    auto c = convAnyMod(a, b, M);
    for (size_t i = 0; i < c.size(); i++) cout << c[i] << (i + 1 < c.size() ? ' ' : '\n');
    if ((ll)n * m <= 1000000) {
        vector<ll> d(n + m - 1, 0);
        for (int i = 0; i < n; i++) for (int j = 0; j < m; j++) d[i + j] = (d[i + j] + (__int128)a[i] * b[j] % M) % M;
        cout << (c == d ? "OK" : "MISMATCH") << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long pw(long b, long e, long m) { long r = 1; b %= m; for (; e > 0; e >>= 1, b = b * b % m) if ((e & 1) == 1) r = r * b % m; return r; }
    static void ntt(long[] a, boolean inv, long mod, long g) {
        int n = a.length;
        for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; (j & bit) != 0; bit >>= 1) j ^= bit; j ^= bit; if (i < j) { long t = a[i]; a[i] = a[j]; a[j] = t; } }
        long[] w = new long[Math.max(1, n / 2)];
        for (int len = 2; len <= n; len <<= 1) {
            long wl = pw(g, (mod - 1) / len, mod);
            if (inv) wl = pw(wl, mod - 2, mod);
            w[0] = 1;
            for (int j = 1; j < len / 2; j++) w[j] = w[j - 1] * wl % mod;
            for (int i = 0; i < n; i += len) for (int j = 0; j < len / 2; j++) {
                long u = a[i + j], v = a[i + j + len / 2] * w[j] % mod;
                a[i + j] = (u + v) % mod; a[i + j + len / 2] = (u - v + mod) % mod;
            }
        }
        if (inv) { long ni = pw(n, mod - 2, mod); for (int i = 0; i < n; i++) a[i] = a[i] * ni % mod; }
    }
    static long[] conv(long[] a0, long[] b0, long mod, long g) {
        int need = a0.length + b0.length - 1, n = 1;
        while (n < need) n <<= 1;
        long[] a = new long[n], b = new long[n];
        for (int i = 0; i < a0.length; i++) a[i] = a0[i] % mod;
        for (int i = 0; i < b0.length; i++) b[i] = b0[i] % mod;
        ntt(a, false, mod, g); ntt(b, false, mod, g);
        for (int i = 0; i < n; i++) a[i] = a[i] * b[i] % mod;
        ntt(a, true, mod, g);
        return Arrays.copyOf(a, need);
    }
    static long[] convAnyMod(long[] a, long[] b, long M) {
        final long p1 = 998244353L, p2 = 167772161L, p3 = 469762049L;
        long[] c1 = conv(a, b, p1, 3), c2 = conv(a, b, p2, 3), c3 = conv(a, b, p3, 3);
        long i12 = pw(p1, p2 - 2, p2), i123 = pw(p1 % p3 * (p2 % p3) % p3, p3 - 2, p3);
        long[] res = new long[c1.length];
        for (int i = 0; i < c1.length; i++) {
            long k1 = (c2[i] - c1[i] % p2 + p2) % p2 * i12 % p2;
            long x12 = c1[i] + p1 * k1;
            long k2 = ((c3[i] - x12 % p3) % p3 + p3) % p3 * i123 % p3;
            res[i] = (x12 % M + mulmod(p1 * p2 % M, k2, M)) % M;
        }
        return res;
    }
    static long mulmod(long a, long b, long m) {               // a, b in [0, m)
        if (m <= 3_037_000_499L) return a * b % m;              // product < 2^63
        return java.math.BigInteger.valueOf(a).multiply(java.math.BigInteger.valueOf(b)).mod(java.math.BigInteger.valueOf(m)).longValue();
    }
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new String(System.in.readAllBytes()));
        int n = Integer.parseInt(st.nextToken()), m = Integer.parseInt(st.nextToken());
        long M = Long.parseLong(st.nextToken());
        long[] a = new long[n], b = new long[m];
        for (int i = 0; i < n; i++) a[i] = Long.parseLong(st.nextToken());
        for (int i = 0; i < m; i++) b[i] = Long.parseLong(st.nextToken());
        long[] c = convAnyMod(a, b, M);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < c.length; i++) sb.append(c[i]).append(i + 1 < c.length ? ' ' : '\n');
        if ((long) n * m <= 1000000) {
            long[] d = new long[n + m - 1];
            for (int i = 0; i < n; i++) for (int j = 0; j < m; j++) d[i + j] = (d[i + j] + mulmod(a[i] % M, b[j] % M, M)) % M;
            sb.append(Arrays.equals(c, d) ? "OK" : "MISMATCH").append('\n');
        }
        System.out.print(sb);
    }
}
```

<!-- test
in:
3 2 1000000007
1 2 3
4 5
out:
4 13 22 15
OK
-->
<!-- test
in:
3 3 1000000007
1000000006 1000000006 1000000006
1000000006 1000000006 1000000006
out:
1 2 3 2 1
OK
-->
<!-- test
in:
1 1 1000000000000
999999999999 999999999999
out:
1
OK
-->

### 3.3 Walsh–Hadamard (XOR / OR / AND convolution)

```cpp
// type: 0 = XOR, 1 = OR, 2 = AND. Size must be a power of two. Exact over integers (inverse divides by n for XOR).
void fwht(vector<ll>& a, int type, bool invert) {
    int n = a.size();
    for (int len = 1; 2 * len <= n; len <<= 1)
        for (int i = 0; i < n; i += 2 * len)
            for (int j = i; j < i + len; j++) {
                ll u = a[j], v = a[j + len];
                if (type == 0) { a[j] = u + v; a[j + len] = u - v; }
                else if (type == 1) a[j + len] = invert ? v - u : v + u;
                else a[j] = invert ? u - v : u + v;
            }
    if (invert && type == 0) for (auto& x : a) x /= n;
}
vector<ll> xorConvolution(vector<ll> a, vector<ll> b) {
    fwht(a, 0, false); fwht(b, 0, false);
    for (size_t i = 0; i < a.size(); i++) a[i] *= b[i];
    fwht(a, 0, true);
    return a;
}
```

```java
static void fwht(long[] a, int type, boolean invert) {
    int n = a.length;
    for (int len = 1; 2 * len <= n; len <<= 1)
        for (int i = 0; i < n; i += 2 * len)
            for (int j = i; j < i + len; j++) {
                long u = a[j], v = a[j + len];
                if (type == 0) { a[j] = u + v; a[j + len] = u - v; }
                else if (type == 1) a[j + len] = invert ? v - u : v + u;
                else a[j] = invert ? u - v : u + v;
            }
    if (invert && type == 0) for (int i = 0; i < n; i++) a[i] /= n;
}
static long[] xorConvolution(long[] a0, long[] b0) {
    long[] a = a0.clone(), b = b0.clone();
    fwht(a, 0, false); fwht(b, 0, false);
    for (int i = 0; i < a.length; i++) a[i] *= b[i];
    fwht(a, 0, true);
    return a;
}
```

---

## 4. Recognising the pattern

| Statement says… | Think… |
|---|---|
| "for every $k$, count pairs with $a_i+b_j=k$" | histogram convolution |
| "for every shift, how many positions match / mismatch" | convolution with the reversed pattern, per letter |
| "match with wildcards / don't-care symbols" | $\sum PT(P-T)^2$ with three convolutions (randomise letter values mod $p$) |
| "sum of $k$ dice / $k$-fold sum of a distribution" | polynomial power (pointwise power in the NTT domain) |
| "multiply many small polynomials" | divide-and-conquer + NTT ([polynomials](04-polynomials-and-generating-functions.md)) |
| modulus $998244353$ in the statement | almost certainly NTT |
| "for every mask, $\sum_{i\oplus j=\text{mask}}$" | Walsh–Hadamard |
| "$\sum_{i\mid j=\text{mask}}$" / "$\sum_{i\&j=\text{mask}}$" | zeta/Möbius (OR/AND) transform |
| $n\le2\cdot10^5$ and an $O(n^2)$ "sum over pairs by difference" | think convolution before data structures |

---

## 5. Worked examples (graded)

### Example 1 — Convolution (mod 998244353)  ·  ★ ≈1900

- **Source:** [AtCoder PRACTICE2 F · Convolution](https://atcoder.jp/contests/practice2/tasks/practice2_f)
- **Difficulty:** ≈1900 (est.; the template problem)
- **Problem:** Given $a_0..a_{N-1}$ and $b_0..b_{M-1}$ ($N,M\le524288$, values $<998244353$), print $c_k=\sum_{i+j=k}a_ib_j\bmod998244353$.
- **Thinking from first principles:** The modulus is $119\cdot2^{23}+1$ and $N+M-1\le2^{20}$, so the NTT applies directly and is exact.

<details><summary>Solution</summary>

`convolution` from §3.1. $O((N+M)\log(N+M))$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 998244353, G = 3;
ll pw(ll b, ll e) { ll r = 1; b %= MOD; for (; e; e >>= 1, b = b * b % MOD) if (e & 1) r = r * b % MOD; return r; }
void ntt(vector<ll>& a, bool inv) {
    int n = a.size();
    for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; j & bit; bit >>= 1) j ^= bit; j ^= bit; if (i < j) swap(a[i], a[j]); }
    vector<ll> w(n / 2 + 1);
    for (int len = 2; len <= n; len <<= 1) {
        ll wl = pw(G, (MOD - 1) / len);
        if (inv) wl = pw(wl, MOD - 2);
        w[0] = 1;
        for (int j = 1; j < len / 2; j++) w[j] = w[j - 1] * wl % MOD;
        for (int i = 0; i < n; i += len) for (int j = 0; j < len / 2; j++) {
            ll u = a[i + j], v = a[i + j + len / 2] * w[j] % MOD;
            a[i + j] = u + v < MOD ? u + v : u + v - MOD;
            a[i + j + len / 2] = u - v >= 0 ? u - v : u - v + MOD;
        }
    }
    if (inv) { ll ni = pw(n, MOD - 2); for (auto& x : a) x = x * ni % MOD; }
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    vector<ll> a(n), b(m);
    for (auto& x : a) cin >> x;
    for (auto& x : b) cin >> x;
    int need = n + m - 1, sz = 1;
    while (sz < need) sz <<= 1;
    a.resize(sz); b.resize(sz);
    ntt(a, false); ntt(b, false);
    for (int i = 0; i < sz; i++) a[i] = a[i] * b[i] % MOD;
    ntt(a, true);
    string out;
    for (int i = 0; i < need; i++) { out += to_string(a[i]); out += (i + 1 < need ? ' ' : '\n'); }
    cout << out;
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 998244353L, G = 3;
    static long pw(long b, long e) { long r = 1; b %= MOD; for (; e > 0; e >>= 1, b = b * b % MOD) if ((e & 1) == 1) r = r * b % MOD; return r; }
    static void ntt(long[] a, boolean inv) {
        int n = a.length;
        for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; (j & bit) != 0; bit >>= 1) j ^= bit; j ^= bit; if (i < j) { long t = a[i]; a[i] = a[j]; a[j] = t; } }
        long[] w = new long[Math.max(1, n / 2)];
        for (int len = 2; len <= n; len <<= 1) {
            long wl = pw(G, (MOD - 1) / len);
            if (inv) wl = pw(wl, MOD - 2);
            w[0] = 1;
            for (int j = 1; j < len / 2; j++) w[j] = w[j - 1] * wl % MOD;
            int half = len >> 1;
            for (int i = 0; i < n; i += len) for (int j = 0; j < half; j++) {
                long u = a[i + j], v = a[i + j + half] * w[j] % MOD;
                a[i + j] = u + v < MOD ? u + v : u + v - MOD;
                a[i + j + half] = u - v >= 0 ? u - v : u - v + MOD;
            }
        }
        if (inv) { long ni = pw(n, MOD - 2); for (int i = 0; i < n; i++) a[i] = a[i] * ni % MOD; }
    }
    public static void main(String[] args) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        int n = nextInt(in), m = nextInt(in), need = n + m - 1, sz = 1;
        while (sz < need) sz <<= 1;
        long[] a = new long[sz], b = new long[sz];
        for (int i = 0; i < n; i++) a[i] = nextInt(in);
        for (int i = 0; i < m; i++) b[i] = nextInt(in);
        ntt(a, false); ntt(b, false);
        for (int i = 0; i < sz; i++) a[i] = a[i] * b[i] % MOD;
        ntt(a, true);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < need; i++) sb.append(a[i]).append(i + 1 < need ? ' ' : '\n');
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
3 4
2 0 7
1 1 3 5
out:
2 2 13 17 21 35
-->
<!-- test
in:
1 1
998244352
998244352
out:
1
-->
<!-- test
in:
2 2
5 6
0 0
out:
0 0 0
-->

### Example 2 — Apples and Bananas  ·  ★ ≈1900

- **Source:** [CSES 2111 · Apples and Bananas](https://cses.fi/problemset/task/2111)
- **Difficulty:** ≈1900 (est.)
- **Problem:** $n$ apple weights and $m$ banana weights, all in $[1,k]$ ($k,n,m\le2\cdot10^5$). For every $w=2..2k$ print the number of
  (apple, banana) pairs of total weight $w$.
- **Thinking from first principles:** Counting pairs by sum is exactly the convolution of the two weight histograms. The counts are exact integers
  up to $nm=4\cdot10^{10}$ — **larger than $998244353$**, so NTT modulo that prime would wrap. Complex FFT is exact here: results $\le4\cdot10^{10}$ are
  far below the $\sim10^{14}$ safety limit.

<details><summary>Solution</summary>

Histograms $A[w]$, $B[w]$; `multiplyFFT(A, B)`; print indices $2..2k$. $O(k\log k)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
using cd = complex<double>;
void fft(vector<cd>& a, bool invert) {
    int n = a.size();
    for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; j & bit; bit >>= 1) j ^= bit; j ^= bit; if (i < j) swap(a[i], a[j]); }
    const double PI = acos(-1.0);
    vector<cd> root(n / 2);
    for (int j = 0; j < n / 2; j++) root[j] = cd(cos(2 * PI * j / n), (invert ? -1 : 1) * sin(2 * PI * j / n));
    for (int len = 2; len <= n; len <<= 1)
        for (int i = 0, step = n / len; i < n; i += len)
            for (int j = 0; j < len / 2; j++) {
                cd u = a[i + j], v = a[i + j + len / 2] * root[j * step];
                a[i + j] = u + v; a[i + j + len / 2] = u - v;
            }
    if (invert) for (auto& x : a) x /= n;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int k, n, m; cin >> k >> n >> m;
    int sz = 1;
    while (sz < 2 * k + 1) sz <<= 1;
    vector<cd> A(sz), B(sz);
    for (int i = 0; i < n; i++) { int w; cin >> w; A[w] += 1; }
    for (int i = 0; i < m; i++) { int w; cin >> w; B[w] += 1; }
    fft(A, false); fft(B, false);
    for (int i = 0; i < sz; i++) A[i] *= B[i];
    fft(A, true);
    string out;
    for (int w = 2; w <= 2 * k; w++) { out += to_string(llround(A[w].real())); out += (w < 2 * k ? ' ' : '\n'); }
    cout << out;
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static void fft(double[] re, double[] im, boolean invert) {
        int n = re.length;
        for (int i = 1, j = 0; i < n; i++) {
            int bit = n >> 1;
            for (; (j & bit) != 0; bit >>= 1) j ^= bit;
            j ^= bit;
            if (i < j) { double t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t; }
        }
        double[] cr = new double[Math.max(1, n / 2)], ci = new double[Math.max(1, n / 2)];
        for (int j = 0; j < n / 2; j++) { cr[j] = Math.cos(2 * Math.PI * j / n); ci[j] = (invert ? -1 : 1) * Math.sin(2 * Math.PI * j / n); }
        for (int len = 2; len <= n; len <<= 1) {
            int half = len >> 1, step = n / len;
            for (int i = 0; i < n; i += len) for (int j = 0; j < half; j++) {
                double wr = cr[j * step], wi = ci[j * step];
                double xr = re[i + j + half] * wr - im[i + j + half] * wi, xi = re[i + j + half] * wi + im[i + j + half] * wr;
                re[i + j + half] = re[i + j] - xr; im[i + j + half] = im[i + j] - xi;
                re[i + j] += xr; im[i + j] += xi;
            }
        }
        if (invert) for (int i = 0; i < n; i++) { re[i] /= n; im[i] /= n; }
    }
    public static void main(String[] args) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        int k = nextInt(in), n = nextInt(in), m = nextInt(in), sz = 1;
        while (sz < 2 * k + 1) sz <<= 1;
        double[] ar = new double[sz], ai = new double[sz], br = new double[sz], bi = new double[sz];
        for (int i = 0; i < n; i++) ar[nextInt(in)] += 1;
        for (int i = 0; i < m; i++) br[nextInt(in)] += 1;
        fft(ar, ai, false); fft(br, bi, false);
        for (int i = 0; i < sz; i++) { double r = ar[i] * br[i] - ai[i] * bi[i]; ai[i] = ar[i] * bi[i] + ai[i] * br[i]; ar[i] = r; }
        fft(ar, ai, true);
        StringBuilder sb = new StringBuilder();
        for (int w = 2; w <= 2 * k; w++) sb.append(Math.round(ar[w])).append(w < 2 * k ? ' ' : '\n');
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
3 2 3
1 3
2 2 3
out:
0 2 1 2 1
-->
<!-- test
in:
1 1 1
1
1
out:
1
-->

### Example 3 — Matching with wildcards  ·  ★ ≈2200

- **Source:** Original problem.
- **Difficulty:** ≈2200 (est.)
- **Problem:** Text $T$ ($\lvert T\rvert\le2\cdot10^5$) and pattern $P$ ($\lvert P\rvert\le\lvert T\rvert$) over lowercase letters and `?` (matches anything, in both
  strings). Print the number of positions where $P$ matches, then those positions (1-indexed).
- **Thinking from first principles:** For a fixed shift $i$ we want $\sum_j[\text{mismatch}(P_j,T_{i+j})]=0$, and mismatch with wildcards is not a
  product of a $P$-term and a $T$-term. Assign each letter a value $v>0$ and `?` the value $0$: the expression $P_jT_{i+j}(P_j-T_{i+j})^2$ is $0$
  iff they match (a wildcard kills it, equal letters kill it), and positive otherwise — so the sum over $j$ is $0$ iff the whole window matches.
  Expanded, it is $P^3T-2P^2T^2+PT^3$: three convolutions with the reversed pattern. Modulo $998244353$ a genuine mismatch could sum to a
  multiple of $p$, so pick the letter values **at random** modulo $p$: the sum is then a non-zero polynomial of degree 4 in the random values,
  and by Schwartz–Zippel it vanishes with probability $\le4/p$ per position.

<details><summary>Solution</summary>

Reverse $P$; compute $\sum$ of the three convolutions at index $i+\lvert P\rvert-1$. Fixed seed for reproducibility. $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 998244353, G = 3;
ll pw(ll b, ll e) { ll r = 1; b %= MOD; for (; e; e >>= 1, b = b * b % MOD) if (e & 1) r = r * b % MOD; return r; }
void ntt(vector<ll>& a, bool inv) {
    int n = a.size();
    for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; j & bit; bit >>= 1) j ^= bit; j ^= bit; if (i < j) swap(a[i], a[j]); }
    vector<ll> w(n / 2 + 1);
    for (int len = 2; len <= n; len <<= 1) {
        ll wl = pw(G, (MOD - 1) / len);
        if (inv) wl = pw(wl, MOD - 2);
        w[0] = 1;
        for (int j = 1; j < len / 2; j++) w[j] = w[j - 1] * wl % MOD;
        for (int i = 0; i < n; i += len) for (int j = 0; j < len / 2; j++) {
            ll u = a[i + j], v = a[i + j + len / 2] * w[j] % MOD;
            a[i + j] = (u + v) % MOD; a[i + j + len / 2] = (u - v + MOD) % MOD;
        }
    }
    if (inv) { ll ni = pw(n, MOD - 2); for (auto& x : a) x = x * ni % MOD; }
}
int main() {
    string T, P; cin >> T >> P;
    int n = T.size(), m = P.size(), sz = 1;
    while (sz < n + m - 1) sz <<= 1;
    mt19937_64 rng(2026);
    ll val[26];
    for (auto& v : val) v = rng() % (MOD - 1) + 1;
    vector<ll> t[3], p[3];                                     // powers 1..3
    for (int e = 0; e < 3; e++) { t[e].assign(sz, 0); p[e].assign(sz, 0); }
    for (int i = 0; i < n; i++) if (T[i] != '?') { ll v = val[T[i] - 'a']; t[0][i] = v; t[1][i] = v * v % MOD; t[2][i] = t[1][i] * v % MOD; }
    for (int j = 0; j < m; j++) if (P[j] != '?') { ll v = val[P[j] - 'a']; int r = m - 1 - j; p[0][r] = v; p[1][r] = v * v % MOD; p[2][r] = p[1][r] * v % MOD; }
    for (int e = 0; e < 3; e++) { ntt(t[e], false); ntt(p[e], false); }
    vector<ll> s(sz);
    for (int i = 0; i < sz; i++)                               // P^3 T - 2 P^2 T^2 + P T^3
        s[i] = ((p[2][i] * t[0][i] - 2 * p[1][i] % MOD * t[1][i] % MOD + p[0][i] * t[2][i]) % MOD + 2 * MOD) % MOD;
    ntt(s, true);
    vector<int> pos;
    for (int i = 0; i + m <= n; i++) if (s[i + m - 1] == 0) pos.push_back(i + 1);
    cout << pos.size() << '\n';
    for (size_t i = 0; i < pos.size(); i++) cout << pos[i] << (i + 1 < pos.size() ? ' ' : '\n');
    if (pos.empty()) cout << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 998244353L, G = 3;
    static long pw(long b, long e) { long r = 1; b %= MOD; for (; e > 0; e >>= 1, b = b * b % MOD) if ((e & 1) == 1) r = r * b % MOD; return r; }
    static void ntt(long[] a, boolean inv) {
        int n = a.length;
        for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; (j & bit) != 0; bit >>= 1) j ^= bit; j ^= bit; if (i < j) { long t = a[i]; a[i] = a[j]; a[j] = t; } }
        long[] w = new long[Math.max(1, n / 2)];
        for (int len = 2; len <= n; len <<= 1) {
            long wl = pw(G, (MOD - 1) / len);
            if (inv) wl = pw(wl, MOD - 2);
            w[0] = 1;
            for (int j = 1; j < len / 2; j++) w[j] = w[j - 1] * wl % MOD;
            for (int i = 0; i < n; i += len) for (int j = 0; j < len / 2; j++) {
                long u = a[i + j], v = a[i + j + len / 2] * w[j] % MOD;
                a[i + j] = (u + v) % MOD; a[i + j + len / 2] = (u - v + MOD) % MOD;
            }
        }
        if (inv) { long ni = pw(n, MOD - 2); for (int i = 0; i < n; i++) a[i] = a[i] * ni % MOD; }
    }
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        String T = br.readLine().trim(), P = br.readLine().trim();
        int n = T.length(), m = P.length(), sz = 1;
        while (sz < n + m - 1) sz <<= 1;
        Random rng = new Random(2026);
        long[] val = new long[26];
        for (int c = 0; c < 26; c++) val[c] = Math.floorMod(rng.nextLong(), MOD - 1) + 1;
        long[][] t = new long[3][sz], p = new long[3][sz];
        for (int i = 0; i < n; i++) if (T.charAt(i) != '?') { long v = val[T.charAt(i) - 'a']; t[0][i] = v; t[1][i] = v * v % MOD; t[2][i] = t[1][i] * v % MOD; }
        for (int j = 0; j < m; j++) if (P.charAt(j) != '?') { long v = val[P.charAt(j) - 'a']; int r = m - 1 - j; p[0][r] = v; p[1][r] = v * v % MOD; p[2][r] = p[1][r] * v % MOD; }
        for (int e = 0; e < 3; e++) { ntt(t[e], false); ntt(p[e], false); }
        long[] s = new long[sz];
        for (int i = 0; i < sz; i++) s[i] = ((p[2][i] * t[0][i] - 2 * p[1][i] % MOD * t[1][i] % MOD + p[0][i] * t[2][i]) % MOD + 2 * MOD) % MOD;
        ntt(s, true);
        StringBuilder pos = new StringBuilder();
        int cnt = 0;
        for (int i = 0; i + m <= n; i++) if (s[i + m - 1] == 0) { pos.append(cnt++ > 0 ? " " : "").append(i + 1); }
        System.out.println(cnt);
        System.out.println(pos);
    }
}
```

</details>

<!-- test
in:
abacaba
a?a
out:
3
1 3 5
-->
<!-- test
in:
ab?ba
?a
out:
2
2 4
-->
<!-- test
in:
xyz
abc
out:
0

-->

### Example 4 — Fuzzy Search  ·  ★ 2500

- **Source:** [CF 528D · Fuzzy Search](https://codeforces.com/problemset/problem/528/D) — 2500
- **Difficulty:** 2500
- **Problem:** Strings $S$ ($\lvert S\rvert\le2\cdot10^5$) and $T$ ($\lvert T\rvert\le\lvert S\rvert$) over `ACGT`, and $k\le2\cdot10^5$. $T$ occurs at position $i$ if for every
  $j$ there is a position $p$ in $S$ with $\lvert(i+j)-p\rvert\le k$ and $S_p=T_j$. Count such positions.
- **Thinking from first principles:** Decouple the letters. For letter $c$, let $A_c[x]=1$ if some occurrence of $c$ in $S$ is within distance $k$ of $x$
  (a difference array over the intervals $[p-k,p+k]$). Then position $i$ works iff for every $j$, $A_{T_j}[i+j]=1$, i.e.
  $\sum_c\sum_jA_c[i+j]\,[T_j=c]=\lvert T\rvert$. Each inner sum is a convolution of $A_c$ with the reversed indicator of $c$ in $T$. Counts are $\le2\cdot10^5<p$,
  so NTT is exact.

<details><summary>Solution</summary>

Four NTT convolutions (one per letter), sum, count indices equal to $\lvert T\rvert$. $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 998244353, G = 3;
ll pw(ll b, ll e) { ll r = 1; b %= MOD; for (; e; e >>= 1, b = b * b % MOD) if (e & 1) r = r * b % MOD; return r; }
void ntt(vector<ll>& a, bool inv) {
    int n = a.size();
    for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; j & bit; bit >>= 1) j ^= bit; j ^= bit; if (i < j) swap(a[i], a[j]); }
    vector<ll> w(n / 2 + 1);
    for (int len = 2; len <= n; len <<= 1) {
        ll wl = pw(G, (MOD - 1) / len);
        if (inv) wl = pw(wl, MOD - 2);
        w[0] = 1;
        for (int j = 1; j < len / 2; j++) w[j] = w[j - 1] * wl % MOD;
        for (int i = 0; i < n; i += len) for (int j = 0; j < len / 2; j++) {
            ll u = a[i + j], v = a[i + j + len / 2] * w[j] % MOD;
            a[i + j] = (u + v) % MOD; a[i + j + len / 2] = (u - v + MOD) % MOD;
        }
    }
    if (inv) { ll ni = pw(n, MOD - 2); for (auto& x : a) x = x * ni % MOD; }
}
int main() {
    int n, m, k; string S, T; cin >> n >> m >> k >> S >> T;
    int sz = 1;
    while (sz < n + m - 1) sz <<= 1;
    const string L = "ACGT";
    vector<ll> total(sz, 0);
    for (char c : L) {
        vector<int> diff(n + 1, 0);
        for (int p = 0; p < n; p++) if (S[p] == c) { diff[max(0, p - k)]++; diff[min(n, p + k + 1)]--; }
        vector<ll> A(sz, 0), B(sz, 0);
        for (int x = 0, run = 0; x < n; x++) { run += diff[x]; A[x] = run > 0; }
        for (int j = 0; j < m; j++) B[m - 1 - j] = (T[j] == c);
        ntt(A, false); ntt(B, false);
        for (int i = 0; i < sz; i++) total[i] = (total[i] + A[i] * B[i]) % MOD;
    }
    ntt(total, true);
    int cnt = 0;
    for (int i = 0; i + m <= n; i++) if (total[i + m - 1] == m) cnt++;
    cout << cnt << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 998244353L, G = 3;
    static long pw(long b, long e) { long r = 1; b %= MOD; for (; e > 0; e >>= 1, b = b * b % MOD) if ((e & 1) == 1) r = r * b % MOD; return r; }
    static void ntt(long[] a, boolean inv) {
        int n = a.length;
        for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; (j & bit) != 0; bit >>= 1) j ^= bit; j ^= bit; if (i < j) { long t = a[i]; a[i] = a[j]; a[j] = t; } }
        long[] w = new long[Math.max(1, n / 2)];
        for (int len = 2; len <= n; len <<= 1) {
            long wl = pw(G, (MOD - 1) / len);
            if (inv) wl = pw(wl, MOD - 2);
            w[0] = 1;
            for (int j = 1; j < len / 2; j++) w[j] = w[j - 1] * wl % MOD;
            for (int i = 0; i < n; i += len) for (int j = 0; j < len / 2; j++) {
                long u = a[i + j], v = a[i + j + len / 2] * w[j] % MOD;
                a[i + j] = (u + v) % MOD; a[i + j + len / 2] = (u - v + MOD) % MOD;
            }
        }
        if (inv) { long ni = pw(n, MOD - 2); for (int i = 0; i < n; i++) a[i] = a[i] * ni % MOD; }
    }
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        int n = Integer.parseInt(st.nextToken()), m = Integer.parseInt(st.nextToken()), k = Integer.parseInt(st.nextToken());
        String S = br.readLine().trim(), T = br.readLine().trim();
        int sz = 1;
        while (sz < n + m - 1) sz <<= 1;
        long[] total = new long[sz];
        for (char c : "ACGT".toCharArray()) {
            int[] diff = new int[n + 1];
            for (int p = 0; p < n; p++) if (S.charAt(p) == c) { diff[Math.max(0, p - k)]++; diff[Math.min(n, p + k + 1)]--; }
            long[] A = new long[sz], B = new long[sz];
            for (int x = 0, run = 0; x < n; x++) { run += diff[x]; A[x] = run > 0 ? 1 : 0; }
            for (int j = 0; j < m; j++) B[m - 1 - j] = T.charAt(j) == c ? 1 : 0;
            ntt(A, false); ntt(B, false);
            for (int i = 0; i < sz; i++) total[i] = (total[i] + A[i] * B[i]) % MOD;
        }
        ntt(total, true);
        int cnt = 0;
        for (int i = 0; i + m <= n; i++) if (total[i + m - 1] == m) cnt++;
        System.out.println(cnt);
    }
}
```

</details>

<!-- test
in:
8 3 1
ACGTACGT
CTA
out:
2
-->
<!-- test
in:
5 2 0
AAAAA
AA
out:
4
-->
<!-- test
in:
4 4 2
ACGT
TGCA
out:
0
-->

### Example 5 — Binary Table (XOR convolution)  ·  ★ 2600

- **Source:** [CF 662C · Binary Table](https://codeforces.com/problemset/problem/662/C) — 2600
- **Difficulty:** 2600
- **Problem:** An $n\times m$ 0/1 table ($n\le20$, $m\le10^5$). You may invert any rows and any columns. Minimise the number of ones.
- **Thinking from first principles:** Fix the set $R$ of inverted rows (a mask). Column $j$ with bit pattern $c_j$ then reads $c_j\oplus R$, and inverting
  the column is optimal iff it has more ones than zeros: its contribution is $f(c_j\oplus R)$ with $f(x)=\min(\operatorname{pc}(x),n-\operatorname{pc}(x))$.
  So the answer is $\min_R\sum_xcnt[x]\,f(x\oplus R)$, and $\sum_xcnt[x]f(x\oplus R)=(cnt\circledast f)[R]$ — an XOR convolution. Brute force over $R$ is
  $2^{20}\cdot10^5$; the Walsh–Hadamard transform does all $R$ in $O(n2^n)$.

<details><summary>Solution</summary>

$cnt$ = histogram of column masks, $f$ as above, XOR-convolve with FWHT (exact in 64-bit integers: transformed values $\le2^{20}\cdot10^5$
and products $\le\sim10^{17}$), take the minimum. $O(n2^n+nm)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
void fwht(vector<ll>& a, bool inv) {
    int n = a.size();
    for (int len = 1; 2 * len <= n; len <<= 1)
        for (int i = 0; i < n; i += 2 * len)
            for (int j = i; j < i + len; j++) { ll u = a[j], v = a[j + len]; a[j] = u + v; a[j + len] = u - v; }
    if (inv) for (auto& x : a) x /= n;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    vector<string> row(n);
    for (auto& s : row) cin >> s;
    int N = 1 << n;
    vector<ll> cnt(N, 0), f(N);
    for (int j = 0; j < m; j++) {
        int mask = 0;
        for (int i = 0; i < n; i++) if (row[i][j] == '1') mask |= 1 << i;
        cnt[mask]++;
    }
    for (int x = 0; x < N; x++) { int pc = __builtin_popcount(x); f[x] = min(pc, n - pc); }
    fwht(cnt, false); fwht(f, false);
    for (int i = 0; i < N; i++) cnt[i] *= f[i];
    fwht(cnt, true);
    cout << *min_element(cnt.begin(), cnt.end()) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static void fwht(long[] a, boolean inv) {
        int n = a.length;
        for (int len = 1; 2 * len <= n; len <<= 1)
            for (int i = 0; i < n; i += 2 * len)
                for (int j = i; j < i + len; j++) { long u = a[j], v = a[j + len]; a[j] = u + v; a[j + len] = u - v; }
        if (inv) for (int i = 0; i < n; i++) a[i] /= n;
    }
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        int n = Integer.parseInt(st.nextToken()), m = Integer.parseInt(st.nextToken());
        int[] mask = new int[m];
        for (int i = 0; i < n; i++) {
            String s = br.readLine().trim();
            for (int j = 0; j < m; j++) if (s.charAt(j) == '1') mask[j] |= 1 << i;
        }
        int N = 1 << n;
        long[] cnt = new long[N], f = new long[N];
        for (int j = 0; j < m; j++) cnt[mask[j]]++;
        for (int x = 0; x < N; x++) { int pc = Integer.bitCount(x); f[x] = Math.min(pc, n - pc); }
        fwht(cnt, false); fwht(f, false);
        for (int i = 0; i < N; i++) cnt[i] *= f[i];
        fwht(cnt, true);
        long best = Long.MAX_VALUE;
        for (long v : cnt) best = Math.min(best, v);
        System.out.println(best);
    }
}
```

</details>

<!-- test
in:
2 3
110
011
out:
1
-->
<!-- test
in:
1 4
1010
out:
0
-->
<!-- test
in:
3 4
1100
1010
0110
out:
3
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Size**: the transform length must be a power of two $\ge\deg A+\deg B+1$, not $\ge\max(\deg)$ — otherwise the product wraps around (cyclic
   convolution).
2. **NTT modulus**: $N$ must divide $p-1$ ($2^{23}$ for $998244353$). Exceeding it gives silently wrong results.
3. **Counts beyond $p$**: if exact counts can exceed the modulus (Example 2), use `double` FFT (results $\lesssim10^{14}$) or two primes + CRT.
4. **`double` FFT accuracy**: compute roots by `cos/sin` of the exact angle (or a long-double table), not by repeated multiplication of one root;
   round with `llround`, never truncate.
5. **Reverse the pattern** for matching problems; the result for shift $i$ sits at index $i+\lvert P\rvert-1$.
6. **Randomise** letter values when a modular sum must certify "exactly zero".
7. **Java speed**: `long[]` NTT of size $2^{20}$ takes ~60–100 ms; avoid `Long` objects, precompute roots per level, and read input with a
   byte buffer. Three transforms per product — reuse transformed arrays when one operand is fixed.
8. **FWHT overflow**: values grow by a factor of $2^n$ through the forward transform; check the bound or work modulo a prime (then divide by
   $2^n$ via the modular inverse).
9. **Negative numbers**: Java `%` keeps the sign — normalise `(u - v + MOD) % MOD`.
10. **Convolution of length-0 arrays** is empty — guard, or `n + m - 1` becomes $-1$.

---

## 7. Going further (toward 2400–2600+)

- **Per-letter-pair convolutions + DSU**: [CF 954I · Yet Another String Matching Problem](https://codeforces.com/problemset/problem/954/I) — 2200.
- **Wildcards in both strings with periods**: [CF 827E · Rusty String](https://codeforces.com/problemset/problem/827/E) — 2700.
- **Polynomial powers in the NTT domain**: [CF 632E · Thief in a Shop](https://codeforces.com/problemset/problem/632/E) — 2400,
  [CF 1096G · Lucky Tickets](https://codeforces.com/problemset/problem/1096/G) — 2400 (see [polynomials](04-polynomials-and-generating-functions.md)).
- **Counting order statistics with prefix-sum convolutions**: [CF 993E · Nikita and Order Statistics](https://codeforces.com/problemset/problem/993/E) — 2300.
- **Self-convolution to detect sums**: [CF 286E · Ladies' Shop](https://codeforces.com/problemset/problem/286/E) — 2800.
- **Subset convolution / FWHT combinations**: [CF 914G · Sum the Fibonacci](https://codeforces.com/problemset/problem/914/G) — 2600,
  [CF 1119H · Triple](https://codeforces.com/problemset/problem/1119/H) — 3200.
- **Online (relaxed) convolution / CDQ + FFT**: [CF 553E · Kyoya and Train](https://codeforces.com/problemset/problem/553/E) — 3200,
  [AtCoder ABC213 Ex · Stroll](https://atcoder.jp/contests/abc213/tasks/abc213_h) — diff≈2806; see
  [CDQ](../16-IGM-Frontier/01-offline-techniques-cdq-parallel-binary-search.md).
- Library Checker ([judge.yosupo.jp](https://judge.yosupo.jp)) has template problems for every transform here — useful for timing your code.

---

## 8. Practice ladder

**1900–2300**
- [ ] [AtCoder PRACTICE2 F · Convolution](https://atcoder.jp/contests/practice2/tasks/practice2_f)
- [ ] [CSES 2111 · Apples and Bananas](https://cses.fi/problemset/task/2111)
- [ ] [CSES 2112 · One Bit Positions](https://cses.fi/problemset/task/2112)
- [ ] [CSES 2113 · Signal Processing](https://cses.fi/problemset/task/2113)
- [ ] [CF 954I · Yet Another String Matching Problem](https://codeforces.com/problemset/problem/954/I) — 2200
- [ ] [CF 993E · Nikita and Order Statistics](https://codeforces.com/problemset/problem/993/E) — 2300
- [ ] [CF 300D · Painting Square](https://codeforces.com/problemset/problem/300/D) — 2300

**2400+**
- [ ] [CF 632E · Thief in a Shop](https://codeforces.com/problemset/problem/632/E) — 2400
- [ ] [CF 1096G · Lucky Tickets](https://codeforces.com/problemset/problem/1096/G) — 2400
- [ ] [CF 528D · Fuzzy Search](https://codeforces.com/problemset/problem/528/D) — 2500
- [ ] [CF 662C · Binary Table](https://codeforces.com/problemset/problem/662/C) — 2600
- [ ] [CF 914G · Sum the Fibonacci](https://codeforces.com/problemset/problem/914/G) — 2600
- [ ] [CF 1398G · Running Competition](https://codeforces.com/problemset/problem/1398/G) — 2600
- [ ] [CF 827E · Rusty String](https://codeforces.com/problemset/problem/827/E) — 2700
- [ ] [CF 286E · Ladies' Shop](https://codeforces.com/problemset/problem/286/E) — 2800
- [ ] [AtCoder ABC213 Ex · Stroll](https://atcoder.jp/contests/abc213/tasks/abc213_h) — diff≈2806
- [ ] [CF 1119H · Triple](https://codeforces.com/problemset/problem/1119/H) — 3200

---

## 9. LeetCode / FAANG cross-reference

- [LC 43 · Multiply Strings](https://leetcode.com/problems/multiply-strings/) — Medium — schoolbook convolution of digits; FFT is the asymptotic answer for huge numbers.
- [LC 3549 · Multiply Two Polynomials](https://leetcode.com/problems/multiply-two-polynomials/) — Hard 🔒 — direct FFT/NTT.

Rare in interviews: FFT is outside the usual FAANG syllabus. Knowing that convolution exists (and when it applies) is enough there.

---

## 10. Self-check

1. Derive $A(\omega^{k+N/2})=E(\omega^{2k})-\omega^kO(\omega^{2k})$.
2. Prove $\sum_{k<N}\omega^{tk}=0$ for $N\nmid t$ and conclude $F^{-1}=\frac1N\bar F$.
3. Why does $998244353$ support NTT up to $2^{23}$, and how do you get a primitive $2^{20}$-th root of unity?
4. When can you use `double` FFT safely? What do you do when results exceed $10^{15}$?
5. Write the wildcard-matching score and explain why randomising letter values is needed modulo $p$.
6. Why does the Walsh–Hadamard transform turn XOR-convolution into pointwise multiplication?
7. What goes wrong if the transform length is only $\max(n,m)$?

<details><summary>Answers</summary>

1. $A(x)=E(x^2)+xO(x^2)$ and $(\omega^{k+N/2})^2=\omega^{2k}$ while $\omega^{k+N/2}=-\omega^k$.
2. Geometric series: $\frac{\omega^{tN}-1}{\omega^t-1}=0$ since $\omega^{tN}=1$ and $\omega^t\ne1$. So $\bar FF=NI$.
3. $p-1=119\cdot2^{23}$, so $2^k\mid p-1$ for $k\le23$; $\omega=3^{(p-1)/2^{20}}$ has order exactly $2^{20}$ because $3$ is a primitive root.
4. When all true results are below about $10^{14}$. Otherwise NTT (if the modulus allows or results $<p$), three primes + CRT, or split FFT.
5. $\sum_jP_jT_{i+j}(P_j-T_{i+j})^2$ with wildcard $=0$; it is a positive integer for a mismatch, but modulo $p$ it could be a multiple of $p$ — random
   values make that happen with probability $\le4/p$ (Schwartz–Zippel).
6. The character $(-1)^{\lvert x\wedge S\rvert}$ is multiplicative over XOR: $\chi_S(i\oplus j)=\chi_S(i)\chi_S(j)$, so the transform of the convolution
   factors.
7. The DFT computes a **cyclic** convolution; coefficients of degree $\ge N$ wrap around onto low indices.

</details>
