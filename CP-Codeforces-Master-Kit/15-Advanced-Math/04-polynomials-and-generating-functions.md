# Polynomials and generating functions

> **Band:** 🔵 1600 – 🔴 2800 · **Priority:** ⚡ (OGF/EGF modelling, closed forms, D&C products) · 🔴 (Newton: inverse, log, exp) · **FAANG:** none · **Prerequisites:** [FFT and NTT](03-fft-and-ntt.md), [stars and bars](../05-Combinatorics-and-Probability/02-stars-and-bars-and-multisets.md), [Catalan and partitions](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md)
> **You can say you know this when:** you can translate a counting statement into a product of generating functions (ordinary or
> exponential), read coefficients from closed forms like $\frac1{(1-x)^k}$, derive the Catalan formula from $C=1+xC^2$, multiply many
> small polynomials in $O(N\log^2N)$, and derive the Newton iterations for $1/A$, $\ln A$ and $e^A$.

---

## 1. First principles — why this works

### 1.1 A generating function is a bookkeeping device

Attach the sequence $a_0,a_1,\dots$ to the **formal power series** $A(x)=\sum_na_nx^n$. "Formal" means $x$ is never evaluated: we only ever
read coefficients, so convergence is irrelevant and all manipulations are algebraic identities on coefficient sequences. Operations
on series correspond to operations on combinatorial objects:

| Series operation | Coefficients | Combinatorial meaning (ordinary GF) |
|---|---|---|
| $A+B$ | $a_n+b_n$ | disjoint union of two classes |
| $A\cdot B$ | $\sum_{k}a_kb_{n-k}$ | ordered pair of independent choices, sizes add |
| $\frac{1}{1-A}$ ($a_0=0$) | $\sum_kA^k$ | sequences of objects from $A$ |
| $xA'$ | $na_n$ | mark one unit of size |
| $A(x^2)$ | $a_{n/2}$ | "doubled" objects |

The multiplication rule is the heart of it: choosing an object of size $k$ from one class and one of size $n-k$ from another, independently,
is counted by the convolution — the product of the series.

### 1.2 Closed forms you must be able to expand

- **Geometric series.** $(1-x)\sum_{n\ge0}x^n=1$, so $\frac1{1-x}=\sum x^n$, and $\frac1{1-cx}=\sum c^nx^n$, $\frac{1}{1-x^c}=\sum x^{cn}$ (coins of value $c$).
- **Stars and bars.** $\frac1{(1-x)^k}=\big(\sum x^n\big)^k$: the coefficient of $x^n$ counts solutions of $e_1+\dots+e_k=n$ with $e_i\ge0$, i.e.
  $\binom{n+k-1}{k-1}$. So $\frac{1}{(1-x)^k}=\sum_n\binom{n+k-1}{k-1}x^n$. (Also from the generalised binomial theorem:
  $(1-x)^{-k}=\sum_n\binom{-k}{n}(-x)^n$ and $(-1)^n\binom{-k}{n}=\binom{n+k-1}{n}$.)
- **Bounded multiplicity.** At most $c$ copies of one kind: $1+x+\dots+x^c=\frac{1-x^{c+1}}{1-x}$.
- **Unordered coin combinations.** $\prod_i\frac{1}{1-x^{c_i}}$; ordered sequences of coins: $\frac{1}{1-\sum_ix^{c_i}}$.

### 1.3 Solving a linear recurrence with a GF

For Fibonacci, multiply $F_n=F_{n-1}+F_{n-2}$ ($n\ge2$) by $x^n$ and sum:
$F(x)-x=x F(x)+x^2F(x)$, so $F(x)=\frac{x}{1-x-x^2}$. Factor $1-x-x^2=(1-\varphi x)(1-\psi x)$ and use partial fractions:
$F(x)=\frac{1}{\sqrt5}\big(\frac{1}{1-\varphi x}-\frac{1}{1-\psi x}\big)$, so $F_n=\frac{\varphi^n-\psi^n}{\sqrt5}$ (Binet).

General principle: **a sequence satisfies a linear recurrence of order $k$ iff its GF is $\frac{P(x)}{Q(x)}$ with $\deg Q\le k$, $\deg P<k$**, where
$Q(x)=1-c_1x-\dots-c_kx^k$ is the reversed characteristic polynomial. That is the bridge to
[matrix power / Kitamasa](01-matrices-and-linear-recurrences.md) and [Berlekamp–Massey](05-lagrange-interpolation-and-berlekamp-massey.md).

### 1.4 Catalan numbers from a functional equation

A binary tree is either empty, or a root with a left and a right subtree. Translating with sizes counted by nodes:
$C(x)=1+x\,C(x)^2$. Solve the quadratic: $C(x)=\frac{1\pm\sqrt{1-4x}}{2x}$; the "$+$" root blows up at $x=0$, so
$C(x)=\frac{1-\sqrt{1-4x}}{2x}$. Expand $\sqrt{1-4x}=\sum_n\binom{1/2}{n}(-4x)^n$ with $\binom{1/2}{n}(-4)^n=-\frac{2}{n}\binom{2n-2}{n-1}$ for $n\ge1$.
Hence $[x^n]C=\frac{1}{2}\cdot\frac{2}{n+1}\binom{2n}{n}=\frac{1}{n+1}\binom{2n}{n}$. Every "recursive structure" problem (trees, bracketings,
triangulations) follows this route: write the functional equation, then extract coefficients — by formula when possible, by Newton's method
on power series otherwise.

### 1.5 Exponential GFs: labelled objects

$\hat A(x)=\sum_na_n\frac{x^n}{n!}$. The product $\hat A\hat B$ has coefficient $\sum_k\binom nk a_kb_{n-k}$: split the $n$ **labels** into the $k$ that go to the
first structure and the rest. So EGFs count **labelled** constructions. Two key consequences:

- **Sets of structures.** If $\hat C$ counts connected labelled structures, then sets of them (all structures) are counted by $\hat G=e^{\hat C}$
  (a set of $k$ components contributes $\frac{\hat C^k}{k!}$ — divide by $k!$ because components are unordered). So $\hat C=\ln\hat G$.
- **Example:** labelled graphs: $g_n=2^{\binom n2}$, so connected labelled graphs are $c_n=n![x^n]\ln\big(\sum_n2^{\binom n2}\frac{x^n}{n!}\big)$ (Example 5).

### 1.6 Newton's method on power series (🔴)

To solve $\Phi(B)=0$ modulo $x^{2k}$ given a solution $B_k$ modulo $x^k$: write $B=B_k+E$ with $E\equiv0\pmod{x^k}$. Taylor:
$\Phi(B_k+E)=\Phi(B_k)+\Phi'(B_k)E+O(E^2)$ and $E^2\equiv0\pmod{x^{2k}}$. So

$$B_{2k}=B_k-\frac{\Phi(B_k)}{\Phi'(B_k)}\pmod{x^{2k}}$$

doubles the number of correct coefficients per step. Each step costs a constant number of multiplications of size $O(k)$, so the total is
$T(n)=T(n/2)+O(n\log n)=O(n\log n)$.

- **Inverse** ($\Phi(B)=B^{-1}-A$): $B_{2k}=B_k(2-AB_k)$. Requires $a_0\ne0$.
- **Logarithm** ($a_0=1$): $\ln A=\int\frac{A'}{A}$ — one inverse and one product.
- **Exponential** ($a_0=0$; $\Phi(B)=\ln B-A$): $B_{2k}=B_k\big(1-\ln B_k+A\big)$.
- **Power** $A^m$ ($a_0=1$): $\exp(m\ln A)$; or, when only a full product of known degree is needed, raise the NTT values to the $m$-th power
  pointwise (Example 2).
- **Square root** ($\Phi(B)=B^2-A$): $B_{2k}=\frac12\big(B_k+\frac{A}{B_k}\big)$.

### 1.7 Multiplying many small polynomials

$\prod_{i=1}^{m}P_i(x)$ with total degree $N$: multiplying left to right costs up to $O(N^2)$ (the running product grows). Instead multiply in a
**balanced binary tree**: each level of the tree handles total degree $\le N+m$, there are $\lceil\log_2m\rceil$ levels, each level costs
$O(N\log N)$ with FFT: $O(N\log N\log m)$. Typical uses: $\prod(1+a_ix)$ (elementary symmetric polynomials), $\prod(1+x+\dots+x^{c_i})$
(multisets with bounded multiplicities, Example 3), Stirling numbers of the first kind $\prod_{i<n}(x+i)$.

---

## 2. Formulas, definitions and identities

| Identity | Meaning |
|---|---|
| $\frac{1}{1-x}=\sum x^n$, $\frac{1}{1-cx}=\sum c^nx^n$ | geometric |
| $\frac{1}{(1-x)^k}=\sum\binom{n+k-1}{k-1}x^n$ | stars and bars |
| $(1+x)^m=\sum\binom mnx^n$; $(1-x)^{-m}$ via $\binom{-m}{n}=(-1)^n\binom{n+m-1}{n}$ | binomial theorem |
| $\frac{1-x^{c+1}}{1-x}$ | at most $c$ copies |
| $\prod_i\frac{1}{1-x^{c_i}}$ / $\frac{1}{1-\sum x^{c_i}}$ | unordered / ordered coin sums |
| $F(x)=\frac{x}{1-x-x^2}$ | Fibonacci |
| $C(x)=\frac{1-\sqrt{1-4x}}{2x}$, $C_n=\frac{1}{n+1}\binom{2n}{n}$ | Catalan |
| $\prod_{k\ge1}\frac1{1-x^k}=\sum p(n)x^n$ | partitions |
| $\prod_{k\ge1}(1-x^k)=\sum_{j\in\mathbb Z}(-1)^jx^{j(3j-1)/2}$ | Euler's pentagonal theorem |
| $\prod_{k\ge1}(1+x^k)=\prod_{k\ge1}\frac{1}{1-x^{2k-1}}$ | distinct parts = odd parts |
| $e^x=\sum\frac{x^n}{n!}$; $\hat A\hat B\leftrightarrow\sum\binom nka_kb_{n-k}$ | EGF product |
| $\hat G=e^{\hat C}$ | sets of connected labelled structures |
| $e^{e^x-1}$ (Bell), $\frac{(e^x-1)^k}{k!}$ (Stirling 2nd kind), $\frac{1}{1-x}$ (permutations) | classic EGFs |
| $B_{2k}=B_k(2-AB_k)$ | power-series inverse, $O(n\log n)$ |
| $\ln A=\int A'A^{-1}$; $B_{2k}=B_k(1-\ln B_k+A)$ | log / exp, $O(n\log n)$ |
| $T(n)=T(n/2)+O(n\log n)$ | Newton cost |
| D&C product of $m$ polys, total degree $N$ | $O(N\log N\log m)$ |

**Pentagonal theorem, why it helps.** $\sum p(n)x^n=\big(\prod(1-x^k)\big)^{-1}$ and the product has only $O(\sqrt n)$ non-zero terms up to
$x^n$, so $p(0..n)$ follows from one power-series inverse in $O(n\log n)$, or from the recurrence
$p(n)=\sum_{j\ne0}(-1)^{j+1}p\big(n-\frac{j(3j-1)}2\big)$ in $O(n\sqrt n)$. (Franklin's involution proves the theorem: pair partitions into distinct
parts with an even and odd number of parts by moving the smallest part / the last diagonal; only pentagonal sizes are left unpaired.)

---

## 3. Implementation (C++ and Java)

All arithmetic modulo $998244353$. `mul` is the NTT convolution from [file 03](03-fft-and-ntt.md).

```cpp
const ll MOD = 998244353;
ll pw(ll b, ll e) { ll r = 1; b %= MOD; if (b < 0) b += MOD; for (; e; e >>= 1, b = b * b % MOD) if (e & 1) r = r * b % MOD; return r; }
void ntt(vector<ll>& a, bool inv) {
    int n = a.size();
    for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; j & bit; bit >>= 1) j ^= bit; j ^= bit; if (i < j) swap(a[i], a[j]); }
    vector<ll> w(n / 2 + 1);
    for (int len = 2; len <= n; len <<= 1) {
        ll wl = pw(3, (MOD - 1) / len);
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
using poly = vector<ll>;
poly mul(poly a, poly b) {
    if (a.empty() || b.empty()) return {};
    int need = a.size() + b.size() - 1, n = 1;
    while (n < need) n <<= 1;
    a.resize(n); b.resize(n);
    ntt(a, false); ntt(b, false);
    for (int i = 0; i < n; i++) a[i] = a[i] * b[i] % MOD;
    ntt(a, true);
    a.resize(need);
    return a;
}
poly inverse(const poly& a, int n) {                       // a[0] != 0; first n coefficients of 1/a
    poly b = {pw(a[0], MOD - 2)};
    for (int k = 1; k < n; k <<= 1) {
        poly ac(a.begin(), a.begin() + min((int)a.size(), 2 * k));
        poly t = mul(ac, b);
        t.resize(2 * k);
        for (auto& x : t) x = (MOD - x) % MOD;
        t[0] = (t[0] + 2) % MOD;                            // 2 - a*b
        b = mul(b, t);
        b.resize(2 * k);
    }
    b.resize(n);
    return b;
}
poly logarithm(const poly& a, int n) {                     // a[0] == 1
    poly da(max(1, (int)a.size() - 1));
    for (size_t i = 1; i < a.size(); i++) da[i - 1] = a[i] * i % MOD;
    poly q = mul(da, inverse(a, n));
    poly res(n, 0);
    for (int i = 1; i < n && i - 1 < (int)q.size(); i++) res[i] = q[i - 1] * pw(i, MOD - 2) % MOD;
    return res;
}
poly exponent(const poly& a, int n) {                      // a[0] == 0
    poly b = {1};
    for (int k = 1; k < n; k <<= 1) {
        poly l = logarithm(b, 2 * k);
        for (int i = 0; i < 2 * k; i++) l[i] = ((i < (int)a.size() ? a[i] : 0) - l[i] + MOD) % MOD;
        l[0] = (l[0] + 1) % MOD;                            // 1 - ln b + a
        b = mul(b, l);
        b.resize(2 * k);
    }
    b.resize(n);
    return b;
}
// Balanced product of many polynomials.
poly productAll(const vector<poly>& ps, int l, int r) {
    if (r - l == 1) return ps[l];
    int mid = (l + r) / 2;
    return mul(productAll(ps, l, mid), productAll(ps, mid, r));
}
```

```java
static final long MOD = 998244353L;
static long pw(long b, long e) { long r = 1; b %= MOD; if (b < 0) b += MOD; for (; e > 0; e >>= 1, b = b * b % MOD) if ((e & 1) == 1) r = r * b % MOD; return r; }
static void ntt(long[] a, boolean inv) {
    int n = a.length;
    for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; (j & bit) != 0; bit >>= 1) j ^= bit; j ^= bit; if (i < j) { long t = a[i]; a[i] = a[j]; a[j] = t; } }
    long[] w = new long[Math.max(1, n / 2)];
    for (int len = 2; len <= n; len <<= 1) {
        long wl = pw(3, (MOD - 1) / len);
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
static long[] mul(long[] a, long[] b) {
    if (a.length == 0 || b.length == 0) return new long[0];
    int need = a.length + b.length - 1, n = 1;
    while (n < need) n <<= 1;
    long[] fa = Arrays.copyOf(a, n), fb = Arrays.copyOf(b, n);
    ntt(fa, false); ntt(fb, false);
    for (int i = 0; i < n; i++) fa[i] = fa[i] * fb[i] % MOD;
    ntt(fa, true);
    return Arrays.copyOf(fa, need);
}
static long[] inverse(long[] a, int n) {
    long[] b = {pw(a[0], MOD - 2)};
    for (int k = 1; k < n; k <<= 1) {
        long[] t = Arrays.copyOf(mul(Arrays.copyOf(a, Math.min(a.length, 2 * k)), b), 2 * k);
        for (int i = 0; i < 2 * k; i++) t[i] = (MOD - t[i]) % MOD;
        t[0] = (t[0] + 2) % MOD;
        b = Arrays.copyOf(mul(b, t), 2 * k);
    }
    return Arrays.copyOf(b, n);
}
static long[] logarithm(long[] a, int n) {
    long[] da = new long[Math.max(1, a.length - 1)];
    for (int i = 1; i < a.length; i++) da[i - 1] = a[i] * i % MOD;
    long[] q = mul(da, inverse(a, n));
    long[] res = new long[n];
    for (int i = 1; i < n && i - 1 < q.length; i++) res[i] = q[i - 1] * pw(i, MOD - 2) % MOD;
    return res;
}
static long[] exponent(long[] a, int n) {
    long[] b = {1};
    for (int k = 1; k < n; k <<= 1) {
        long[] l = logarithm(b, 2 * k);
        for (int i = 0; i < 2 * k; i++) l[i] = ((i < a.length ? a[i] : 0) - l[i] + MOD) % MOD;
        l[0] = (l[0] + 1) % MOD;
        b = Arrays.copyOf(mul(b, l), 2 * k);
    }
    return Arrays.copyOf(b, n);
}
static long[] productAll(List<long[]> ps, int l, int r) {
    if (r - l == 1) return ps.get(l);
    int mid = (l + r) >>> 1;
    return mul(productAll(ps, l, mid), productAll(ps, mid, r));
}
```

---

## 4. Recognising the pattern

| Statement says… | Think… |
|---|---|
| "distribute $n$ identical items into $k$ boxes", "non-negative solutions" | $\frac{1}{(1-x)^k}$, stars and bars |
| "each type can be used at most $c_i$ times", "count multisets of size $k$" | $\prod(1+x+\dots+x^{c_i})$, D&C + FFT |
| "number of ways to pay $n$ with coins", unordered | $\prod\frac1{1-x^{c}}$ (knapsack DP or one inverse) |
| "sum of $n$ digits from a set", "$k$ dice", "tickets with equal halves" | $P(x)^n$ (pointwise power in the NTT domain) |
| "labelled", "permutations with cycle constraints", "connected graphs" | EGF; $\exp$/$\ln$ for set/connected |
| "count trees/bracketings with a recursive definition" | functional equation $\Rightarrow$ closed form or Newton |
| "answer for every $n\le10^5$" of a recursive counting problem | power-series inverse / exp in $O(n\log n)$ |
| "$p(n)$ partitions for all $n\le2\cdot10^5$" | pentagonal theorem + inverse |
| linear recurrence, but you need coefficient $10^{18}$ | rational GF $\to$ Kitamasa / Bostan–Mori |

---

## 5. Worked examples (graded)

### Example 1 — Distributing Apples  ·  ★ ≈1600

- **Source:** [CSES 1716 · Distributing Apples](https://cses.fi/problemset/task/1716)
- **Difficulty:** ≈1600 (est.)
- **Problem:** Count ways to give $m$ identical apples to $n$ children ($n,m\le10^6$), modulo $10^9+7$.
- **Thinking from first principles:** Each child contributes a factor $\sum_{e\ge0}x^e=\frac1{1-x}$, so the answer is $[x^m]\frac{1}{(1-x)^n}=\binom{m+n-1}{n-1}$.
  Factorials up to $2\cdot10^6$ and Fermat inverses finish it.

<details><summary>Solution</summary>

$\binom{n+m-1}{m}$ via factorials. $O(n+m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007;
ll pw(ll b, ll e) { ll r = 1; for (; e; e >>= 1, b = b * b % MOD) if (e & 1) r = r * b % MOD; return r; }
int main() {
    int n, m; cin >> n >> m;
    int N = n + m;
    vector<ll> f(N + 1, 1);
    for (int i = 1; i <= N; i++) f[i] = f[i - 1] * i % MOD;
    cout << f[n + m - 1] * pw(f[m], MOD - 2) % MOD * pw(f[n - 1], MOD - 2) % MOD << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long pw(long b, long e) { long r = 1; for (; e > 0; e >>= 1, b = b * b % MOD) if ((e & 1) == 1) r = r * b % MOD; return r; }
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        int n = Integer.parseInt(st.nextToken()), m = Integer.parseInt(st.nextToken());
        long[] f = new long[n + m + 1];
        f[0] = 1;
        for (int i = 1; i <= n + m; i++) f[i] = f[i - 1] * i % MOD;
        System.out.println(f[n + m - 1] * pw(f[m], MOD - 2) % MOD * pw(f[n - 1], MOD - 2) % MOD);
    }
}
```

</details>

<!-- test
in:
3 2
out:
6
-->
<!-- test
in:
1 1000000
out:
1
-->
<!-- test
in:
4 4
out:
35
-->

### Example 2 — Lucky Tickets  ·  ★ 2400

- **Source:** [CF 1096G · Lucky Tickets](https://codeforces.com/problemset/problem/1096/G) — 2400
- **Difficulty:** 2400
- **Problem:** A ticket is $n$ digits ($n\le2\cdot10^5$, even) using only $k$ allowed digits. It is lucky if the digit sums of both halves are equal.
  Count lucky tickets modulo $998244353$.
- **Thinking from first principles:** One half is a sequence of $n/2$ independent digits, so the number of halves with sum $s$ is
  $q_s=[x^s]P(x)^{n/2}$ with $P(x)=\sum_{d\text{ allowed}}x^d$. Both halves are independent: answer $\sum_sq_s^2$. The power has degree
  $\le9\cdot\frac n2$, so choose an NTT length $N>9\cdot\frac n2$; then $P^{n/2}$ has no wrap-around and can be computed by raising each NTT
  **value** to the power $n/2$ — evaluation commutes with multiplication. One forward and one inverse transform.

<details><summary>Solution</summary>

$N=2^{20}$ suffices ($9\cdot10^5<2^{20}$). $O(N\log N+N\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 998244353;
ll pw(ll b, ll e) { ll r = 1; b %= MOD; for (; e; e >>= 1, b = b * b % MOD) if (e & 1) r = r * b % MOD; return r; }
void ntt(vector<ll>& a, bool inv) {
    int n = a.size();
    for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; j & bit; bit >>= 1) j ^= bit; j ^= bit; if (i < j) swap(a[i], a[j]); }
    vector<ll> w(n / 2 + 1);
    for (int len = 2; len <= n; len <<= 1) {
        ll wl = pw(3, (MOD - 1) / len);
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
    int n, k; cin >> n >> k;
    int half = n / 2, N = 1;
    while (N <= 9 * half) N <<= 1;
    vector<ll> a(N, 0);
    for (int i = 0; i < k; i++) { int d; cin >> d; a[d] = 1; }
    ntt(a, false);
    for (auto& x : a) x = pw(x, half);                         // pointwise power = coefficient-wise P^(n/2)
    ntt(a, true);
    ll ans = 0;
    for (auto x : a) ans = (ans + x * x) % MOD;
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 998244353L;
    static long pw(long b, long e) { long r = 1; b %= MOD; for (; e > 0; e >>= 1, b = b * b % MOD) if ((e & 1) == 1) r = r * b % MOD; return r; }
    static void ntt(long[] a, boolean inv) {
        int n = a.length;
        for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; (j & bit) != 0; bit >>= 1) j ^= bit; j ^= bit; if (i < j) { long t = a[i]; a[i] = a[j]; a[j] = t; } }
        long[] w = new long[Math.max(1, n / 2)];
        for (int len = 2; len <= n; len <<= 1) {
            long wl = pw(3, (MOD - 1) / len);
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
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        st.nextToken(); int k = (int) st.nval;
        int half = n / 2, N = 1;
        while (N <= 9 * half) N <<= 1;
        long[] a = new long[N];
        for (int i = 0; i < k; i++) { st.nextToken(); a[(int) st.nval] = 1; }
        ntt(a, false);
        for (int i = 0; i < N; i++) a[i] = pw(a[i], half);
        ntt(a, true);
        long ans = 0;
        for (long x : a) ans = (ans + x * x) % MOD;
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
2 3
0 1 9
out:
3
-->
<!-- test
in:
4 2
3 5
out:
6
-->
<!-- test
in:
6 1
7
out:
1
-->

### Example 3 — Lightsabers (hard)  ·  ★ 2600

- **Source:** [CF 958F3 · Lightsabers (hard)](https://codeforces.com/problemset/problem/958/F3) — 2600
- **Difficulty:** 2600
- **Problem:** $n\le2\cdot10^5$ items, each with a colour in $1..m$; items of the same colour are indistinguishable. Count the different
  collections of exactly $k$ items (as multisets of colours), modulo $1009$.
- **Thinking from first principles:** Colour $c$ with $\text{cnt}_c$ copies contributes $1+x+\dots+x^{\text{cnt}_c}$ (choose how many). The answer is
  $[x^k]\prod_c(1+\dots+x^{\text{cnt}_c})$, a product of up to $m$ polynomials with total degree $n$. Left-to-right multiplication is $O(nm)$ in the
  worst case; a balanced D&C product is $O(n\log n\log m)$. The modulus $1009$ is not NTT-friendly, but coefficients are $<1009$ and lengths
  $\le2\cdot10^5$, so true products are $<2\cdot10^5\cdot1009^2\approx2\cdot10^{11}$ — `double` FFT is exact after rounding.

<details><summary>Solution</summary>

Build one polynomial per present colour, multiply in a balanced tree with complex FFT, reduce modulo 1009 after each product.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
using cd = complex<double>;
const int MOD = 1009;
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
vector<int> mul(const vector<int>& a, const vector<int>& b) {
    int need = a.size() + b.size() - 1, n = 1;
    if ((ll)a.size() * b.size() <= 4096) {                       // small: schoolbook is faster
        vector<int> c(need, 0);
        for (size_t i = 0; i < a.size(); i++) for (size_t j = 0; j < b.size(); j++) c[i + j] = (c[i + j] + a[i] * b[j]) % MOD;
        return c;
    }
    while (n < need) n <<= 1;
    vector<cd> fa(n), fb(n);
    for (size_t i = 0; i < a.size(); i++) fa[i] = a[i];
    for (size_t i = 0; i < b.size(); i++) fb[i] = b[i];
    fft(fa, false); fft(fb, false);
    for (int i = 0; i < n; i++) fa[i] *= fb[i];
    fft(fa, true);
    vector<int> c(need);
    for (int i = 0; i < need; i++) c[i] = llround(fa[i].real()) % MOD;
    return c;
}
vector<int> prod(vector<vector<int>>& ps, int l, int r) {
    if (r - l == 1) return ps[l];
    int mid = (l + r) / 2;
    return mul(prod(ps, l, mid), prod(ps, mid, r));
}
int main() {
    int n, m, k; cin >> n >> m >> k;
    vector<int> cnt(m + 1, 0);
    for (int i = 0; i < n; i++) { int c; cin >> c; cnt[c]++; }
    vector<vector<int>> ps;
    for (int c = 1; c <= m; c++) if (cnt[c]) ps.push_back(vector<int>(cnt[c] + 1, 1));
    vector<int> res = prod(ps, 0, ps.size());
    cout << (k < (int)res.size() ? res[k] : 0) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final int MOD = 1009;
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
    static int[] mul(int[] a, int[] b) {
        int need = a.length + b.length - 1, n = 1;
        if ((long) a.length * b.length <= 4096) {
            int[] c = new int[need];
            for (int i = 0; i < a.length; i++) for (int j = 0; j < b.length; j++) c[i + j] = (c[i + j] + a[i] * b[j]) % MOD;
            return c;
        }
        while (n < need) n <<= 1;
        double[] ar = new double[n], ai = new double[n], br = new double[n], bi = new double[n];
        for (int i = 0; i < a.length; i++) ar[i] = a[i];
        for (int i = 0; i < b.length; i++) br[i] = b[i];
        fft(ar, ai, false); fft(br, bi, false);
        for (int i = 0; i < n; i++) { double r = ar[i] * br[i] - ai[i] * bi[i]; ai[i] = ar[i] * bi[i] + ai[i] * br[i]; ar[i] = r; }
        fft(ar, ai, true);
        int[] c = new int[need];
        for (int i = 0; i < need; i++) c[i] = (int) (Math.round(ar[i]) % MOD);
        return c;
    }
    static int[] prod(List<int[]> ps, int l, int r) {
        if (r - l == 1) return ps.get(l);
        int mid = (l + r) >>> 1;
        return mul(prod(ps, l, mid), prod(ps, mid, r));
    }
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        st.nextToken(); int m = (int) st.nval;
        st.nextToken(); int k = (int) st.nval;
        int[] cnt = new int[m + 1];
        for (int i = 0; i < n; i++) { st.nextToken(); cnt[(int) st.nval]++; }
        List<int[]> ps = new ArrayList<>();
        for (int c = 1; c <= m; c++) if (cnt[c] > 0) { int[] p = new int[cnt[c] + 1]; Arrays.fill(p, 1); ps.add(p); }
        int[] res = prod(ps, 0, ps.size());
        System.out.println(k < res.length ? res[k] : 0);
    }
}
```

</details>

<!-- test
in:
5 3 3
1 1 2 3 3
out:
5
-->
<!-- test
in:
5 2 5
1 1 1 2 2
out:
1
-->
<!-- test
in:
3 3 3
1 2 3
out:
1
-->
<!-- test
in:
6 1 3
1 1 1 1 1 1
out:
1
-->

### Example 4 — Partition numbers via the pentagonal theorem  ·  ★ ≈2300

- **Source:** Original problem.
- **Difficulty:** ≈2300 (est.)
- **Problem:** Given $n\le2\cdot10^5$, print $p(n)\bmod998244353$, the number of partitions of $n$ (and, as a checksum, $\sum_{i\le n}p(i)$).
- **Thinking from first principles:** $\sum p(n)x^n=\prod_{k\ge1}\frac{1}{1-x^k}$. Multiplying $n$ factors is wasteful; Euler's pentagonal theorem says the
  denominator $\prod(1-x^k)$ has only the terms $(-1)^jx^{j(3j-1)/2}$, about $2\sqrt{2n/3}$ of them below $x^n$. Build that sparse series and take
  one power-series inverse: $O(n\log n)$. (The $O(n\sqrt n)$ recurrence from the same theorem is a good cross-check.)

<details><summary>Solution</summary>

`inverse` from §3 applied to the pentagonal series truncated at $x^{n+1}$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 998244353;
ll pw(ll b, ll e) { ll r = 1; b %= MOD; for (; e; e >>= 1, b = b * b % MOD) if (e & 1) r = r * b % MOD; return r; }
void ntt(vector<ll>& a, bool inv) {
    int n = a.size();
    for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; j & bit; bit >>= 1) j ^= bit; j ^= bit; if (i < j) swap(a[i], a[j]); }
    vector<ll> w(n / 2 + 1);
    for (int len = 2; len <= n; len <<= 1) {
        ll wl = pw(3, (MOD - 1) / len);
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
vector<ll> mul(vector<ll> a, vector<ll> b) {
    int need = a.size() + b.size() - 1, n = 1;
    while (n < need) n <<= 1;
    a.resize(n); b.resize(n);
    ntt(a, false); ntt(b, false);
    for (int i = 0; i < n; i++) a[i] = a[i] * b[i] % MOD;
    ntt(a, true);
    a.resize(need);
    return a;
}
vector<ll> inverse(const vector<ll>& a, int n) {
    vector<ll> b = {pw(a[0], MOD - 2)};
    for (int k = 1; k < n; k <<= 1) {
        vector<ll> ac(a.begin(), a.begin() + min((int)a.size(), 2 * k));
        vector<ll> t = mul(ac, b);
        t.resize(2 * k);
        for (auto& x : t) x = (MOD - x) % MOD;
        t[0] = (t[0] + 2) % MOD;
        b = mul(b, t);
        b.resize(2 * k);
    }
    b.resize(n);
    return b;
}
int main() {
    int n; cin >> n;
    vector<ll> e(n + 1, 0);
    for (ll j = 0;; j++) {                                      // generalized pentagonal numbers j(3j-1)/2 and j(3j+1)/2
        ll g1 = j * (3 * j - 1) / 2, g2 = j * (3 * j + 1) / 2;
        if (g1 > n) break;
        ll s = (j % 2 == 0) ? 1 : MOD - 1;
        e[g1] = s;
        if (j > 0 && g2 <= n) e[g2] = s;
    }
    vector<ll> p = inverse(e, n + 1);
    ll sum = 0;
    for (int i = 0; i <= n; i++) sum = (sum + p[i]) % MOD;
    cout << p[n] << ' ' << sum << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 998244353L;
    static long pw(long b, long e) { long r = 1; b %= MOD; for (; e > 0; e >>= 1, b = b * b % MOD) if ((e & 1) == 1) r = r * b % MOD; return r; }
    static void ntt(long[] a, boolean inv) {
        int n = a.length;
        for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; (j & bit) != 0; bit >>= 1) j ^= bit; j ^= bit; if (i < j) { long t = a[i]; a[i] = a[j]; a[j] = t; } }
        long[] w = new long[Math.max(1, n / 2)];
        for (int len = 2; len <= n; len <<= 1) {
            long wl = pw(3, (MOD - 1) / len);
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
    static long[] mul(long[] a, long[] b) {
        int need = a.length + b.length - 1, n = 1;
        while (n < need) n <<= 1;
        long[] fa = Arrays.copyOf(a, n), fb = Arrays.copyOf(b, n);
        ntt(fa, false); ntt(fb, false);
        for (int i = 0; i < n; i++) fa[i] = fa[i] * fb[i] % MOD;
        ntt(fa, true);
        return Arrays.copyOf(fa, need);
    }
    static long[] inverse(long[] a, int n) {
        long[] b = {pw(a[0], MOD - 2)};
        for (int k = 1; k < n; k <<= 1) {
            long[] t = Arrays.copyOf(mul(Arrays.copyOf(a, Math.min(a.length, 2 * k)), b), 2 * k);
            for (int i = 0; i < 2 * k; i++) t[i] = (MOD - t[i]) % MOD;
            t[0] = (t[0] + 2) % MOD;
            b = Arrays.copyOf(mul(b, t), 2 * k);
        }
        return Arrays.copyOf(b, n);
    }
    public static void main(String[] args) throws IOException {
        int n = Integer.parseInt(new BufferedReader(new InputStreamReader(System.in)).readLine().trim());
        long[] e = new long[n + 1];
        for (long j = 0; ; j++) {
            long g1 = j * (3 * j - 1) / 2, g2 = j * (3 * j + 1) / 2;
            if (g1 > n) break;
            long s = (j % 2 == 0) ? 1 : MOD - 1;
            e[(int) g1] = s;
            if (j > 0 && g2 <= n) e[(int) g2] = s;
        }
        long[] p = inverse(e, n + 1);
        long sum = 0;
        for (int i = 0; i <= n; i++) sum = (sum + p[i]) % MOD;
        System.out.println(p[n] + " " + sum);
    }
}
```

</details>

<!-- test
in:
5
out:
7 19
-->
<!-- test
in:
0
out:
1 1
-->
<!-- test
in:
100
out:
190569292 644748215
-->

### Example 5 — Connected labelled graphs via $\ln$  ·  ★ ≈2600

- **Source:** Original problem.
- **Difficulty:** ≈2600 (est.)
- **Problem:** Given $n\le10^5$, print the number of connected labelled simple graphs on $n$ vertices, modulo $998244353$.
- **Thinking from first principles:** All labelled graphs: $g_n=2^{\binom n2}$. A graph is a **set** of connected components on disjoint label sets, so
  with EGFs $\hat G=e^{\hat C}$ (§1.5), i.e. $\hat C=\ln\hat G$. The $O(n^2)$ alternative — subtract graphs where vertex 1's component has size
  $k<n$: $c_n=g_n-\sum_{k<n}\binom{n-1}{k-1}c_kg_{n-k}$ — is the same identity read coefficient by coefficient, and serves as a brute force.
  Note $\binom n2$ is huge: reduce the exponent modulo $p-1$.

<details><summary>Solution</summary>

$\hat G_i=2^{\binom i2}/i!$, `logarithm`, multiply by $n!$. $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 998244353;
ll pw(ll b, ll e) { ll r = 1; b %= MOD; for (; e; e >>= 1, b = b * b % MOD) if (e & 1) r = r * b % MOD; return r; }
void ntt(vector<ll>& a, bool inv) {
    int n = a.size();
    for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; j & bit; bit >>= 1) j ^= bit; j ^= bit; if (i < j) swap(a[i], a[j]); }
    vector<ll> w(n / 2 + 1);
    for (int len = 2; len <= n; len <<= 1) {
        ll wl = pw(3, (MOD - 1) / len);
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
vector<ll> mul(vector<ll> a, vector<ll> b) {
    int need = a.size() + b.size() - 1, n = 1;
    while (n < need) n <<= 1;
    a.resize(n); b.resize(n);
    ntt(a, false); ntt(b, false);
    for (int i = 0; i < n; i++) a[i] = a[i] * b[i] % MOD;
    ntt(a, true);
    a.resize(need);
    return a;
}
vector<ll> inverse(const vector<ll>& a, int n) {
    vector<ll> b = {pw(a[0], MOD - 2)};
    for (int k = 1; k < n; k <<= 1) {
        vector<ll> ac(a.begin(), a.begin() + min((int)a.size(), 2 * k));
        vector<ll> t = mul(ac, b);
        t.resize(2 * k);
        for (auto& x : t) x = (MOD - x) % MOD;
        t[0] = (t[0] + 2) % MOD;
        b = mul(b, t);
        b.resize(2 * k);
    }
    b.resize(n);
    return b;
}
vector<ll> logarithm(const vector<ll>& a, int n) {
    vector<ll> da(max(1, (int)a.size() - 1));
    for (size_t i = 1; i < a.size(); i++) da[i - 1] = a[i] * i % MOD;
    vector<ll> q = mul(da, inverse(a, n));
    vector<ll> res(n, 0);
    for (int i = 1; i < n && i - 1 < (int)q.size(); i++) res[i] = q[i - 1] * pw(i, MOD - 2) % MOD;
    return res;
}
int main() {
    int n; cin >> n;
    vector<ll> fact(n + 1, 1), g(n + 1);
    for (int i = 1; i <= n; i++) fact[i] = fact[i - 1] * i % MOD;
    for (ll i = 0; i <= n; i++) g[i] = pw(2, (i * (i - 1) / 2) % (MOD - 1)) * pw(fact[i], MOD - 2) % MOD;
    vector<ll> c = logarithm(g, n + 1);
    cout << c[n] * fact[n] % MOD << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 998244353L;
    static long pw(long b, long e) { long r = 1; b %= MOD; for (; e > 0; e >>= 1, b = b * b % MOD) if ((e & 1) == 1) r = r * b % MOD; return r; }
    static void ntt(long[] a, boolean inv) {
        int n = a.length;
        for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; (j & bit) != 0; bit >>= 1) j ^= bit; j ^= bit; if (i < j) { long t = a[i]; a[i] = a[j]; a[j] = t; } }
        long[] w = new long[Math.max(1, n / 2)];
        for (int len = 2; len <= n; len <<= 1) {
            long wl = pw(3, (MOD - 1) / len);
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
    static long[] mul(long[] a, long[] b) {
        int need = a.length + b.length - 1, n = 1;
        while (n < need) n <<= 1;
        long[] fa = Arrays.copyOf(a, n), fb = Arrays.copyOf(b, n);
        ntt(fa, false); ntt(fb, false);
        for (int i = 0; i < n; i++) fa[i] = fa[i] * fb[i] % MOD;
        ntt(fa, true);
        return Arrays.copyOf(fa, need);
    }
    static long[] inverse(long[] a, int n) {
        long[] b = {pw(a[0], MOD - 2)};
        for (int k = 1; k < n; k <<= 1) {
            long[] t = Arrays.copyOf(mul(Arrays.copyOf(a, Math.min(a.length, 2 * k)), b), 2 * k);
            for (int i = 0; i < 2 * k; i++) t[i] = (MOD - t[i]) % MOD;
            t[0] = (t[0] + 2) % MOD;
            b = Arrays.copyOf(mul(b, t), 2 * k);
        }
        return Arrays.copyOf(b, n);
    }
    static long[] logarithm(long[] a, int n) {
        long[] da = new long[Math.max(1, a.length - 1)];
        for (int i = 1; i < a.length; i++) da[i - 1] = a[i] * i % MOD;
        long[] q = mul(da, inverse(a, n));
        long[] res = new long[n];
        for (int i = 1; i < n && i - 1 < q.length; i++) res[i] = q[i - 1] * pw(i, MOD - 2) % MOD;
        return res;
    }
    public static void main(String[] args) throws IOException {
        int n = Integer.parseInt(new BufferedReader(new InputStreamReader(System.in)).readLine().trim());
        long[] fact = new long[n + 1], g = new long[n + 1];
        fact[0] = 1;
        for (int i = 1; i <= n; i++) fact[i] = fact[i - 1] * i % MOD;
        for (long i = 0; i <= n; i++) g[(int) i] = pw(2, (i * (i - 1) / 2) % (MOD - 1)) * pw(fact[(int) i], MOD - 2) % MOD;
        long[] c = logarithm(g, n + 1);
        System.out.println(c[n] * fact[n] % MOD);
    }
}
```

</details>

<!-- test
in:
4
out:
38
-->
<!-- test
in:
1
out:
1
-->
<!-- test
in:
6
out:
26704
-->
<!-- test
in:
50
out:
807799776
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Truncate early**: every Newton step works modulo $x^{2k}$; resize after each multiplication or the arrays (and time) double.
2. **Preconditions**: inverse needs $a_0\ne0$; log needs $a_0=1$ (scale first); exp needs $a_0=0$.
3. **Pointwise powers** in the NTT domain are only valid when the final degree is below the transform length.
4. **Exponents like $\binom n2$** must be reduced modulo $p-1$ before `pow`.
5. **Small modulus that isn't NTT-friendly** (1009, $10^9+7$): `double` FFT if products stay $<10^{14}$, else three-prime CRT.
6. **D&C order matters**: balanced recursion on the list (or a min-heap by length) — never left-to-right.
7. **Switch to schoolbook** for tiny products (e.g. $\text{len}_a\cdot\text{len}_b\le4096$): FFT overhead dominates there.
8. **EGF vs OGF**: labelled structures ⇒ EGF (divide by $n!$, multiply back at the end); unlabelled ⇒ OGF. Mixing them is the classic modelling bug.
9. **Java recursion** in D&C products is only $\log m$ deep — fine; but allocate arrays per level, not per element.
10. **Check with brute force**: every GF identity has an $O(n^2)$ DP equivalent (Example 5's recurrence) — use it on small $n$.

---

## 7. Going further (toward 2400–2600+)

- **Square root and inverse of a power series**: [CF 438E · The Child and Binary Tree](https://codeforces.com/problemset/problem/438/E) — 3100
  ($C=1+xWC^2$ with weight polynomial $W$; solve with sqrt + inverse).
- **Polynomial powers**: [CF 632E · Thief in a Shop](https://codeforces.com/problemset/problem/632/E) — 2400.
- **D&C products in counting**: [CF 1251F · Red-White Fence](https://codeforces.com/problemset/problem/1251/F) — 2500,
  [CF 1613F · Tree Coloring](https://codeforces.com/problemset/problem/1613/F) — 2600,
  [CF 960G · Bandit Blues](https://codeforces.com/problemset/problem/960/G) — 2900 (Stirling numbers of the first kind).
- **Polynomial division in counting**: [CF 1548C · The Three Little Pigs](https://codeforces.com/problemset/problem/1548/C) — 2500.
- **Exp/log of EGFs**: [CF 891E · Lust](https://codeforces.com/problemset/problem/891/E) — 3000,
  [CF 755G · PolandBall and Many Other Balls](https://codeforces.com/problemset/problem/755/G) — 3200.
- **Bostan–Mori**: $[x^n]\frac{P(x)}{Q(x)}$ via $\frac{P(x)Q(-x)}{Q(x)Q(-x)}$ — the denominator becomes even, so halve $n$ each step: $O(k\log k\log n)$.
- **Online convolution** for "$f$ defined by its own convolution" ($f_n=\sum f_ig_{n-i}$): CDQ + FFT, [AtCoder ABC213 Ex · Stroll](https://atcoder.jp/contests/abc213/tasks/abc213_h) — diff≈2806.

---

## 8. Practice ladder

**1400–1900**
- [ ] [CSES 1716 · Distributing Apples](https://cses.fi/problemset/task/1716)
- [ ] [CSES 2064 · Bracket Sequences I](https://cses.fi/problemset/task/2064)
- [ ] [CSES 2187 · Bracket Sequences II](https://cses.fi/problemset/task/2187)

**1900–2300**
- [ ] [CF 1342E · Placing Rooks](https://codeforces.com/problemset/problem/1342/E) — 2300

**2400+**
- [ ] [CF 1096G · Lucky Tickets](https://codeforces.com/problemset/problem/1096/G) — 2400
- [ ] [CF 632E · Thief in a Shop](https://codeforces.com/problemset/problem/632/E) — 2400
- [ ] [CF 1251F · Red-White Fence](https://codeforces.com/problemset/problem/1251/F) — 2500
- [ ] [CF 1548C · The Three Little Pigs](https://codeforces.com/problemset/problem/1548/C) — 2500
- [ ] [CF 958F3 · Lightsabers (hard)](https://codeforces.com/problemset/problem/958/F3) — 2600
- [ ] [CF 1613F · Tree Coloring](https://codeforces.com/problemset/problem/1613/F) — 2600
- [ ] [CF 960G · Bandit Blues](https://codeforces.com/problemset/problem/960/G) — 2900
- [ ] [CF 891E · Lust](https://codeforces.com/problemset/problem/891/E) — 3000
- [ ] [CF 438E · The Child and Binary Tree](https://codeforces.com/problemset/problem/438/E) — 3100
- [ ] [CF 923E · Perpetual Subtraction](https://codeforces.com/problemset/problem/923/E) — 3100
- [ ] [CF 755G · PolandBall and Many Other Balls](https://codeforces.com/problemset/problem/755/G) — 3200

---

## 9. LeetCode / FAANG cross-reference

- [LC 1735 · Count Ways to Make Array With Product](https://leetcode.com/problems/count-ways-to-make-array-with-product/) — Hard — per prime exponent, stars and bars $\binom{e+k-1}{k-1}$ (the $\frac{1}{(1-x)^k}$ coefficient).
- [LC 3405 · Count the Number of Arrays with K Matching Adjacent Elements](https://leetcode.com/problems/count-the-number-of-arrays-with-k-matching-adjacent-elements/) — Hard — choose matching positions, closed form $\binom{n-1}{k}m(m-1)^{n-1-k}$.
- [LC 1634 · Add Two Polynomials Represented as Linked Lists](https://leetcode.com/problems/add-two-polynomials-represented-as-linked-lists/) — Medium 🔒 — polynomial representation only.

Generating functions are not asked in interviews as such, but deriving a closed-form count (stars and bars, Catalan) is.

---

## 10. Self-check

1. Expand $[x^n]\frac{1}{(1-x)^k}$ and explain the combinatorial meaning.
2. Derive $F(x)=\frac{x}{1-x-x^2}$ from the Fibonacci recurrence.
3. Derive the Catalan formula from $C=1+xC^2$. Why the minus sign?
4. Why does the EGF of "sets of connected structures" equal $e^{\hat C}$?
5. Derive the Newton step for the power-series inverse and its complexity.
6. Why is the D&C product $O(N\log N\log m)$, while left-to-right can be $O(N^2)$?
7. In Lucky Tickets, why is raising NTT values to the power $n/2$ correct?

<details><summary>Answers</summary>

1. $\binom{n+k-1}{k-1}$: the number of ways to write $n$ as an ordered sum of $k$ non-negative integers (stars and bars).
2. $\sum_{n\ge2}F_nx^n=\sum_{n\ge2}(F_{n-1}+F_{n-2})x^n$ gives $F-x=xF+x^2F$.
3. $xC^2-C+1=0\Rightarrow C=\frac{1\pm\sqrt{1-4x}}{2x}$; $C(0)=1$ must be finite, which forces the minus sign. Expanding $\sqrt{1-4x}$ gives $\frac{1}{n+1}\binom{2n}{n}$.
4. A set of $k$ components on disjoint label sets is counted by $\frac{\hat C^k}{k!}$ (ordered $k$-tuples overcount by $k!$); summing over $k$ gives $e^{\hat C}$.
5. $\Phi(B)=B^{-1}-A$, $\Phi'(B)=-B^{-2}$: $B-\frac{\Phi}{\Phi'}=B+B^2(B^{-1}-A)=B(2-AB)$. Doubling precision per step: $T(n)=T(n/2)+O(n\log n)=O(n\log n)$.
6. Each tree level multiplies polynomials of total degree $\le N+m$ in $O(N\log N)$, over $\log m$ levels; left-to-right repeatedly multiplies a
   large running product by small factors.
7. The NTT is evaluation at roots of unity, and evaluation is a ring homomorphism: $\widehat{P^m}=\hat P^m$ as long as the degree of $P^m$ is below the
   length (no wrap-around).

</details>
