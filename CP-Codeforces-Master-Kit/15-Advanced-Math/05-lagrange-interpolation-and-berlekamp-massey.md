# Lagrange interpolation and Berlekamp–Massey

> **Band:** 🟣 2000 – 🔴 2700 · **Priority:** ⚡ (Lagrange on consecutive points, $\sum i^k$) · 🔴 (Berlekamp–Massey + Kitamasa, polynomial-in-a-parameter DP) · **FAANG:** none · **Prerequisites:** [modular inverses](../04-Number-Theory/02-modular-arithmetic-and-inverses.md), [matrices and linear recurrences](01-matrices-and-linear-recurrences.md), [Fermat's little theorem](../04-Number-Theory/04-euler-phi-fermat-and-euler-theorem.md)
> **You can say you know this when:** you can prove that $\sum_{i\le m}i^k$ is a polynomial of degree $k+1$ in $m$ and evaluate it at
> $m=10^9$ in $O(k)$, recognise a DP whose answer is a polynomial in a huge parameter, and use Berlekamp–Massey to find the recurrence of
> a sequence from its first terms and jump to the $10^{18}$-th term.

---

## 1. First principles — why this works

### 1.1 A polynomial is determined by $n+1$ values

If two polynomials of degree $\le n$ agree at $n+1$ distinct points, their difference has degree $\le n$ and $n+1$ roots, so it is zero
(this needs a field — e.g. $\mathbb{Z}_p$). Existence is constructive: the **Lagrange basis**

$$L_i(x)=\prod_{j\ne i}\frac{x-x_j}{x_i-x_j}\qquad(L_i(x_j)=[i=j])$$

gives $P(x)=\sum_iy_iL_i(x)$. Evaluating at one point costs $O(n^2)$ (or $O(n\log n)$ with tricks); recovering all coefficients costs $O(n^2)$.

### 1.2 Consecutive points: $O(n)$

With $x_i=i$ for $i=0..n$, the denominators are $\prod_{j\ne i}(i-j)=i!\,(n-i)!\,(-1)^{n-i}$, and the numerators are prefix/suffix products of
$(X-j)$:

$$P(X)=\sum_{i=0}^{n}y_i\cdot\frac{\prod_{j<i}(X-j)\cdot\prod_{j>i}(X-j)}{i!\,(n-i)!\,(-1)^{n-i}} .$$

$O(n)$ after precomputing factorials. If $X\bmod p\in[0,n]$ some factor vanishes — then simply return $y_{X\bmod p}$ (a polynomial with
coefficients mod $p$ satisfies $P(X)\equiv P(X\bmod p)$).

### 1.3 Why $\sum_{i=1}^{m}i^k$ is a polynomial of degree $k+1$

Let $S(m)=\sum_{i=1}^{m}i^k$. Its **forward difference** $\Delta S(m)=S(m+1)-S(m)=(m+1)^k$ is a polynomial of degree $k$. A function whose
difference is a polynomial of degree $k$ is itself a polynomial of degree $k+1$: the falling powers $m^{\underline{d}}=m(m-1)\cdots(m-d+1)$ satisfy
$\Delta m^{\underline{d}}=d\,m^{\underline{d-1}}$, so write $(m+1)^k$ in the falling-power basis and "integrate" term by term. Therefore $S$ is determined
by $k+2$ values $S(0),\dots,S(k+1)$, computed directly in $O(k\log k)$ (or $O(k)$ with a linear sieve, since $i\mapsto i^k$ is completely
multiplicative), and $S(n)$ for $n=10^9$ follows by §1.2.

The same reasoning powers a large class of problems: **any DP whose transitions are "sum of polynomials over a range" produces polynomials**, with
the degree rising by one per summation. Identify the degree, compute that many $+1$ values with the small DP, interpolate (Example 4).

### 1.4 Berlekamp–Massey: find the recurrence

Many sequences obey an unknown linear recurrence $s_n=\sum_{i=1}^{L}c_is_{n-i}$ — every sequence of the form $u^{T}M^nv$ for a fixed $k\times k$
matrix $M$ does, with $L\le k$ (Cayley–Hamilton, [file 01](01-matrices-and-linear-recurrences.md)). That includes the answer of *every* DP
with a fixed linear transition on $k$ states, sums of such sequences, $n^d\lambda^n$, and their products by constants.

**Berlekamp–Massey** finds the *shortest* such recurrence from the first terms in $O(N^2)$. Keep the current connection polynomial
$C(x)=1+C_1x+\dots+C_Lx^L$ (meaning $\sum_{i=0}^{L}C_is_{n-i}=0$), and a copy $B$ of the polynomial before the last length change, with its
discrepancy $b$ and the shift $m$ since then. For each new term $s_n$:

1. Compute the **discrepancy** $d=\sum_{i=0}^{L}C_is_{n-i}$. If $d=0$, $C$ still works: $m\leftarrow m+1$.
2. Otherwise correct: $C\leftarrow C-\frac{d}{b}x^mB$. The shifted $B$ produces discrepancy exactly $b$ at position $n$ (it failed there by $b$, $m$ steps
   ago) and $0$ at all earlier positions where $C$ was tested, so the correction cancels $d$ without breaking anything that held before.
3. If $2L\le n$ the length must grow: $L\leftarrow n+1-L$, and the old $C$ becomes the new $B$ (with $b\leftarrow d$, $m\leftarrow1$). Else $m\leftarrow m+1$.

**Massey's theorem** guarantees the result is the minimum-length recurrence, and that $2L$ terms suffice to determine a recurrence of
length $L$. Then compute $s_n$ for huge $n$ by Kitamasa ($O(L^2\log n)$).

### 1.5 When BM is the right tool

- The answer is clearly "a fixed linear DP repeated $n$ times" but deriving the matrix is tedious (profile DPs, automata products, multiple
  interacting counters): compute $2K+10$ terms with any brute DP (where $K$ bounds the number of states), run BM, Kitamasa.
- The modulus must be **prime** (BM divides by discrepancies).
- Always generate a few more terms than $2K$ and check the recurrence on them — if the sequence is not actually linear-recurrent (e.g. it
  involves $\binom{2n}{n}$), BM returns a recurrence of length $\approx N/2$ that fails on fresh terms.
- Many red coders keep BM in their library precisely as a "proof-free" shortcut. The risk is a wrong upper bound on $K$: be generous.

---

## 2. Formulas, definitions and identities

| Formula | Meaning | Cost |
|---|---|---|
| $L_i(x)=\prod_{j\ne i}\frac{x-x_j}{x_i-x_j}$, $P=\sum y_iL_i$ | Lagrange interpolation | $O(n^2)$ per point |
| consecutive: $\prod_{j\ne i}(i-j)=i!(n-i)!(-1)^{n-i}$ | denominators for $x_i=i$ | $O(n)$ per point |
| $\Delta S(m)=S(m+1)-S(m)$; $\deg\Delta S=\deg S-1$ | finite differences | |
| $\Delta m^{\underline d}=d\,m^{\underline{d-1}}$ | falling powers | |
| $\sum_{i=1}^{m}i^k$ has degree $k+1$ | needs $k+2$ samples | $O(k)$ |
| $\sum i=\frac{m(m+1)}2$, $\sum i^2=\frac{m(m+1)(2m+1)}6$, $\sum i^3=\big(\frac{m(m+1)}2\big)^2$ | Faulhaber, small $k$ | |
| $\binom{p-1}{k}\equiv(-1)^k\pmod p$ | binomial mod $p$ | |
| $x^{p-1}\equiv[x\not\equiv0]\pmod p$ | Fermat indicator | |
| $\sum_{i=0}^{L}C_is_{n-i}=0$, discrepancy $d$ | BM invariant | $O(N^2)$ |
| $C\leftarrow C-\frac db x^mB$; $L\leftarrow n+1-L$ if $2L\le n$ | BM update | |
| $2L$ terms determine a length-$L$ recurrence | Massey | |
| $u^TM^nv$ ($k\times k$) is linear-recurrent of order $\le k$ | Cayley–Hamilton | |

**The Fermat-indicator trick (Example 2).** For prime $p$, $1-(x-i)^{p-1}\equiv[x\equiv i]\pmod p$ as a function on $\mathbb{Z}_p$. So
$f(x)=\sum_ia_i\big(1-(x-i)^{p-1}\big)$ is a polynomial of degree $\le p-1$ taking prescribed values $a_i$ — an explicit interpolation
formula, with coefficients from $\binom{p-1}{k}\equiv(-1)^k$.

---

## 3. Implementation (C++ and Java)

```cpp
const ll MOD = 1'000'000'007;
ll pw(ll b, ll e) { ll r = 1; b %= MOD; if (b < 0) b += MOD; for (; e; e >>= 1, b = b * b % MOD) if (e & 1) r = r * b % MOD; return r; }
// P(i) = y[i] for i = 0..n; returns P(X) mod MOD. O(n) after O(n) factorials.
ll lagrangeConsecutive(const vector<ll>& y, ll X) {
    int n = (int)y.size() - 1;
    X %= MOD; if (X < 0) X += MOD;
    if (X <= n) return y[X];
    vector<ll> pre(n + 2, 1), suf(n + 2, 1), fact(n + 1, 1);
    for (int i = 0; i <= n; i++) pre[i + 1] = pre[i] * ((X - i) % MOD) % MOD;
    for (int i = n; i >= 0; i--) suf[i] = suf[i + 1] * ((X - i) % MOD) % MOD;
    for (int i = 1; i <= n; i++) fact[i] = fact[i - 1] * i % MOD;
    ll res = 0;
    for (int i = 0; i <= n; i++) {
        ll num = pre[i] * suf[i + 1] % MOD;
        ll den = fact[i] * fact[n - i] % MOD;
        ll term = y[i] % MOD * num % MOD * pw(den, MOD - 2) % MOD;
        res = ((n - i) & 1) ? (res - term + MOD) % MOD : (res + term) % MOD;
    }
    return res;
}
// General points (distinct x mod MOD). O(n^2).
ll lagrange(const vector<ll>& x, const vector<ll>& y, ll X) {
    ll res = 0; int n = x.size();
    for (int i = 0; i < n; i++) {
        ll num = 1, den = 1;
        for (int j = 0; j < n; j++) if (j != i) { num = num * (((X - x[j]) % MOD + MOD) % MOD) % MOD; den = den * (((x[i] - x[j]) % MOD + MOD) % MOD) % MOD; }
        res = (res + y[i] % MOD * num % MOD * pw(den, MOD - 2)) % MOD;
    }
    return res;
}
// Shortest recurrence s_n = sum_{i=1..L} c[i-1] * s_{n-i}  (prime modulus).
vector<ll> berlekampMassey(const vector<ll>& s) {
    vector<ll> C = {1}, B = {1};
    int L = 0, m = 1;
    ll b = 1;
    for (size_t n = 0; n < s.size(); n++) {
        ll d = 0;
        for (int i = 0; i <= L && i < (int)C.size(); i++) d = (d + C[i] * s[n - i]) % MOD;
        if (d == 0) { m++; continue; }
        vector<ll> T = C;
        ll coef = d * pw(b, MOD - 2) % MOD;
        if (C.size() < B.size() + m) C.resize(B.size() + m, 0);
        for (size_t i = 0; i < B.size(); i++) C[i + m] = (C[i + m] - coef * B[i] % MOD + MOD) % MOD;
        if (2 * L <= (int)n) { L = n + 1 - L; B = T; b = d; m = 1; }
        else m++;
    }
    vector<ll> c(L);
    for (int i = 1; i <= L; i++) c[i - 1] = (MOD - (i < (int)C.size() ? C[i] : 0)) % MOD;
    return c;
}
// n-th term given recurrence c and initial terms a[0..L-1] (Kitamasa, see file 01).
ll nthTerm(const vector<ll>& a, const vector<ll>& c, ull n) {
    int k = c.size();
    if (k == 0) return 0;
    if (n < (ull)k) return a[n];
    auto mm = [&](const vector<ll>& p, const vector<ll>& q) {
        vector<ll> r(2 * k - 1, 0);
        for (int i = 0; i < k; i++) if (p[i]) for (int j = 0; j < k; j++) r[i + j] = (r[i + j] + p[i] * q[j]) % MOD;
        for (int d = 2 * k - 2; d >= k; d--) if (r[d]) for (int i = 0; i < k; i++) r[d - 1 - i] = (r[d - 1 - i] + r[d] * c[i]) % MOD;
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
```

```java
static final long MOD = 1_000_000_007L;
static long pw(long b, long e) { long r = 1; b %= MOD; if (b < 0) b += MOD; for (; e > 0; e >>= 1, b = b * b % MOD) if ((e & 1) == 1) r = r * b % MOD; return r; }
static long lagrangeConsecutive(long[] y, long X) {
    int n = y.length - 1;
    X %= MOD; if (X < 0) X += MOD;
    if (X <= n) return y[(int) X];
    long[] pre = new long[n + 2], suf = new long[n + 2], fact = new long[n + 1];
    pre[0] = 1; suf[n + 1] = 1; fact[0] = 1;
    for (int i = 0; i <= n; i++) pre[i + 1] = pre[i] * ((X - i) % MOD) % MOD;
    for (int i = n; i >= 0; i--) suf[i] = suf[i + 1] * ((X - i) % MOD) % MOD;
    for (int i = 1; i <= n; i++) fact[i] = fact[i - 1] * i % MOD;
    long res = 0;
    for (int i = 0; i <= n; i++) {
        long term = y[i] % MOD * (pre[i] * suf[i + 1] % MOD) % MOD * pw(fact[i] * fact[n - i] % MOD, MOD - 2) % MOD;
        res = ((n - i) & 1) == 1 ? (res - term + MOD) % MOD : (res + term) % MOD;
    }
    return res;
}
static long[] berlekampMassey(long[] s) {
    long[] C = {1}, B = {1};
    int L = 0, m = 1;
    long b = 1;
    for (int n = 0; n < s.length; n++) {
        long d = 0;
        for (int i = 0; i <= L && i < C.length; i++) d = (d + C[i] * s[n - i]) % MOD;
        if (d == 0) { m++; continue; }
        long[] T = C.clone();
        long coef = d * pw(b, MOD - 2) % MOD;
        if (C.length < B.length + m) C = Arrays.copyOf(C, B.length + m);
        for (int i = 0; i < B.length; i++) C[i + m] = (C[i + m] - coef * B[i] % MOD + MOD) % MOD;
        if (2 * L <= n) { L = n + 1 - L; B = T; b = d; m = 1; }
        else m++;
    }
    long[] c = new long[L];
    for (int i = 1; i <= L; i++) c[i - 1] = (MOD - (i < C.length ? C[i] : 0)) % MOD;
    return c;
}
static long nthTerm(long[] a, long[] c, long n) {
    int k = c.length;
    if (k == 0) return 0;
    if (n < k) return a[(int) n];
    long[] res = new long[k], base = new long[k];
    res[0] = 1;
    if (k == 1) base[0] = c[0]; else base[1] = 1;
    for (; n > 0; n >>= 1, base = polyMulMod(base, base, c)) if ((n & 1) == 1) res = polyMulMod(res, base, c);
    long ans = 0;
    for (int i = 0; i < k; i++) ans = (ans + res[i] * a[i]) % MOD;
    return ans;
}
static long[] polyMulMod(long[] p, long[] q, long[] c) {
    int k = c.length;
    long[] r = new long[2 * k - 1];
    for (int i = 0; i < k; i++) if (p[i] != 0) for (int j = 0; j < k; j++) r[i + j] = (r[i + j] + p[i] * q[j]) % MOD;
    for (int d = 2 * k - 2; d >= k; d--) if (r[d] != 0) for (int i = 0; i < k; i++) r[d - 1 - i] = (r[d - 1 - i] + r[d] * c[i]) % MOD;
    return Arrays.copyOf(r, k);
}
```

---

## 4. Recognising the pattern

| Statement says… | Think… |
|---|---|
| "$\sum_{i=1}^{n}i^k$", "$\sum$ of a polynomial", $n\le10^9$ | degree $k+1$ polynomial: Lagrange on consecutive points |
| a DP with a huge numeric parameter $D$ (salary bound, value range) and small $n$ | the answer is a polynomial in $D$; DP for $D=0..\deg$, interpolate |
| "find a polynomial with given values mod $p$" | Lagrange / Fermat indicator |
| $n\le10^{18}$, small state DP, messy transitions | Berlekamp–Massey on $2K+10$ terms + Kitamasa |
| "count tilings of a $k\times n$ board", "strings avoiding patterns" for huge $n$ | linear recurrence — BM |
| "$\sum_{i\le n}f(i)$" where $f$ satisfies a recurrence | the prefix sum also satisfies one (order $+1$) — BM handles it |
| sequence grows like $\binom{2n}{n}$, Catalan, factorial | **not** linear-recurrent with constant coefficients — BM will fail |

---

## 5. Worked examples (graded)

### Example 1 — Polynomial Construction  ·  ★ ≈2400

- **Source:** [AtCoder ABC137 F · Polynomial Construction](https://atcoder.jp/contests/abc137/tasks/abc137_f) — diff≈2402
- **Difficulty:** ≈2400 (AtCoder model estimate)
- **Problem:** A prime $p\le2999$ and $a_0..a_{p-1}\in\{0,1\}$. Output coefficients $b_0..b_{p-1}\in[0,p)$ of a polynomial with $f(i)\equiv a_i\pmod p$ for all $i$.
- **Thinking from first principles:** General Lagrange would work in $O(p^2)$, but Fermat gives a cleaner formula: $1-(x-i)^{p-1}$ is $1$ at $x=i$ and $0$
  elsewhere. Sum it over the $i$ with $a_i=1$. Expanding $(x-i)^{p-1}=\sum_k\binom{p-1}{k}x^k(-i)^{p-1-k}$ and using $\binom{p-1}{k}\equiv(-1)^k$ gives
  $b_k=[k=0]\cdot\#\{i:a_i=1\}-(-1)^k\sum_{i:a_i=1}(-i)^{p-1-k}$.

<details><summary>Solution</summary>

For each $i$ with $a_i=1$, walk the powers of $(-i)$ from exponent $0$ to $p-1$. $O(p^2)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    int p; cin >> p;
    vector<int> a(p);
    for (auto& v : a) cin >> v;
    vector<long long> b(p, 0);
    for (int i = 0; i < p; i++) if (a[i]) {
        b[0] = (b[0] + 1) % p;
        long long base = (p - i) % p, cur = 1;            // (-i)^e for e = 0, 1, ...
        for (int e = 0; e <= p - 1; e++) {
            int k = p - 1 - e;                              // coefficient of x^k uses (-i)^{p-1-k}
            long long sign = (k % 2 == 0) ? 1 : p - 1;      // (-1)^k = C(p-1, k) mod p
            b[k] = (b[k] - sign * cur % p + p) % p;
            cur = cur * base % p;
        }
    }
    for (int k = 0; k < p; k++) cout << b[k] << (k + 1 < p ? ' ' : '\n');
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int p = (int) st.nval;
        int[] a = new int[p];
        for (int i = 0; i < p; i++) { st.nextToken(); a[i] = (int) st.nval; }
        long[] b = new long[p];
        for (int i = 0; i < p; i++) if (a[i] == 1) {
            b[0] = (b[0] + 1) % p;
            long base = (p - i) % p, cur = 1;
            for (int e = 0; e <= p - 1; e++) {
                int k = p - 1 - e;
                long sign = (k % 2 == 0) ? 1 : p - 1;
                b[k] = (b[k] - sign * cur % p + p) % p;
                cur = cur * base % p;
            }
        }
        StringBuilder sb = new StringBuilder();
        for (int k = 0; k < p; k++) sb.append(b[k]).append(k + 1 < p ? ' ' : '\n');
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
3
1 1 0
out:
1 2 1
-->
<!-- test
in:
3
0 0 0
out:
0 0 0
-->
<!-- test
in:
5
0 1 0 1 1
out:
0 3 4 2 2
-->

### Example 2 — The Sum of the k-th Powers  ·  ★ 2600

- **Source:** [CF 622F · The Sum of the k-th Powers](https://codeforces.com/problemset/problem/622/F) — 2600
- **Difficulty:** 2600
- **Problem:** Print $\sum_{i=1}^{n}i^k\bmod(10^9+7)$ for $n\le10^9$, $0\le k\le10^6$.
- **Thinking from first principles:** Faulhaber's closed forms need Bernoulli numbers ($O(k^2)$ naively). The structural fact is enough: the sum is a
  polynomial in $n$ of degree $k+1$ (§1.3). Compute it at $n=0,1,\dots,k+1$ by direct summation, then evaluate at the real $n$ with the
  consecutive-points Lagrange formula — $O(k\log k)$ for the powers, $O(k)$ for the interpolation.

<details><summary>Solution</summary>

$y_x=\sum_{i\le x}i^k$ for $x\le k+1$; `lagrangeConsecutive(y, n)`. Note $0^0=1$ is never needed since the sum starts at $i=1$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007;
ll pw(ll b, ll e) { ll r = 1; b %= MOD; for (; e; e >>= 1, b = b * b % MOD) if (e & 1) r = r * b % MOD; return r; }
int main() {
    ll n; int k; cin >> n >> k;
    int N = k + 1;                                             // points 0..N
    vector<ll> y(N + 1, 0);
    for (int x = 1; x <= N; x++) y[x] = (y[x - 1] + pw(x, k)) % MOD;
    if (n <= N) { cout << y[n] << '\n'; return 0; }
    vector<ll> pre(N + 2, 1), suf(N + 2, 1), fact(N + 1, 1);
    for (int i = 0; i <= N; i++) pre[i + 1] = pre[i] * ((n - i) % MOD) % MOD;
    for (int i = N; i >= 0; i--) suf[i] = suf[i + 1] * ((n - i) % MOD) % MOD;
    for (int i = 1; i <= N; i++) fact[i] = fact[i - 1] * i % MOD;
    vector<ll> invFact(N + 1);
    invFact[N] = pw(fact[N], MOD - 2);
    for (int i = N; i > 0; i--) invFact[i - 1] = invFact[i] * i % MOD;
    ll res = 0;
    for (int i = 0; i <= N; i++) {
        ll term = y[i] * pre[i] % MOD * suf[i + 1] % MOD * invFact[i] % MOD * invFact[N - i] % MOD;
        res = ((N - i) & 1) ? (res - term + MOD) % MOD : (res + term) % MOD;
    }
    cout << res << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long pw(long b, long e) { long r = 1; b %= MOD; for (; e > 0; e >>= 1, b = b * b % MOD) if ((e & 1) == 1) r = r * b % MOD; return r; }
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        long n = Long.parseLong(st.nextToken());
        int k = Integer.parseInt(st.nextToken()), N = k + 1;
        long[] y = new long[N + 1];
        for (int x = 1; x <= N; x++) y[x] = (y[x - 1] + pw(x, k)) % MOD;
        if (n <= N) { System.out.println(y[(int) n]); return; }
        long[] pre = new long[N + 2], suf = new long[N + 2], fact = new long[N + 1], invFact = new long[N + 1];
        pre[0] = 1; suf[N + 1] = 1; fact[0] = 1;
        for (int i = 0; i <= N; i++) pre[i + 1] = pre[i] * ((n - i) % MOD) % MOD;
        for (int i = N; i >= 0; i--) suf[i] = suf[i + 1] * ((n - i) % MOD) % MOD;
        for (int i = 1; i <= N; i++) fact[i] = fact[i - 1] * i % MOD;
        invFact[N] = pw(fact[N], MOD - 2);
        for (int i = N; i > 0; i--) invFact[i - 1] = invFact[i] * i % MOD;
        long res = 0;
        for (int i = 0; i <= N; i++) {
            long term = y[i] * pre[i] % MOD * suf[i + 1] % MOD * invFact[i] % MOD * invFact[N - i] % MOD;
            res = ((N - i) & 1) == 1 ? (res - term + MOD) % MOD : (res + term) % MOD;
        }
        System.out.println(res);
    }
}
```

</details>

<!-- test
in:
10 2
out:
385
-->
<!-- test
in:
1000000000 0
out:
1000000000
-->
<!-- test
in:
1000000000 1
out:
21
-->
<!-- test
in:
123456789 7
out:
470286437
-->

### Example 3 — Domino tilings of a $4\times n$ board via Berlekamp–Massey  ·  ★ ≈2300

- **Source:** Original problem.
- **Difficulty:** ≈2300 (est.)
- **Problem:** Count tilings of a $4\times n$ board by $1\times2$ dominoes, $n\le10^{18}$, modulo $10^9+7$.
- **Thinking from first principles:** Column-by-column profile DP has $2^4=16$ states with a fixed transfer matrix, so the counts form a linear recurrence
  of order $\le16$ (Cayley–Hamilton). Instead of building and powering the $16\times16$ matrix ($16^3\cdot60$), compute the first $2\cdot16+10$ terms
  with the profile DP, let Berlekamp–Massey find the recurrence (it turns out to have order 4:
  $T_n=T_{n-1}+5T_{n-2}+T_{n-3}-T_{n-4}$), and jump with Kitamasa. The same three steps work for any board height or tile set — only the brute DP
  changes.

<details><summary>Solution</summary>

Profile DP: state = set of rows of the current column already covered by horizontal dominoes from the left; fill the column with vertical
dominoes or horizontal ones protruding to the right. $O(42\cdot16\cdot2^4)$ for the terms, $O(L^2)$ BM, $O(L^2\log n)$ Kitamasa.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
using ull = unsigned long long;
const ll MOD = 1'000'000'007;
const int H = 4;
ll pw(ll b, ll e) { ll r = 1; b %= MOD; for (; e; e >>= 1, b = b * b % MOD) if (e & 1) r = r * b % MOD; return r; }
// all next-column masks reachable when the current column starts with 'cur' filled
void fill(int row, int cur, int nxt, vector<int>& out) {
    if (row == H) { out.push_back(nxt); return; }
    if (cur >> row & 1) { fill(row + 1, cur, nxt, out); return; }
    fill(row + 1, cur, nxt | 1 << row, out);                                  // horizontal domino into the next column
    if (row + 1 < H && !(cur >> (row + 1) & 1)) fill(row + 2, cur, nxt, out); // vertical domino
}
vector<ll> bm(const vector<ll>& s) {
    vector<ll> C = {1}, B = {1};
    int L = 0, m = 1; ll b = 1;
    for (size_t n = 0; n < s.size(); n++) {
        ll d = 0;
        for (int i = 0; i <= L && i < (int)C.size(); i++) d = (d + C[i] * s[n - i]) % MOD;
        if (d == 0) { m++; continue; }
        vector<ll> T = C;
        ll coef = d * pw(b, MOD - 2) % MOD;
        if (C.size() < B.size() + m) C.resize(B.size() + m, 0);
        for (size_t i = 0; i < B.size(); i++) C[i + m] = (C[i + m] - coef * B[i] % MOD + MOD) % MOD;
        if (2 * L <= (int)n) { L = n + 1 - L; B = T; b = d; m = 1; } else m++;
    }
    vector<ll> c(L);
    for (int i = 1; i <= L; i++) c[i - 1] = (MOD - (i < (int)C.size() ? C[i] : 0)) % MOD;
    return c;
}
ll nth(const vector<ll>& a, const vector<ll>& c, ull n) {
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
    ull n; cin >> n;
    vector<vector<int>> tr(1 << H);
    for (int mask = 0; mask < (1 << H); mask++) fill(0, mask, 0, tr[mask]);
    const int TERMS = 2 * (1 << H) + 10;
    vector<ll> dp(1 << H, 0), seq;
    dp[0] = 1;
    for (int col = 0; col < TERMS; col++) {
        seq.push_back(dp[0]);                                  // T(col): all columns before col filled, nothing protruding
        vector<ll> nd(1 << H, 0);
        for (int mask = 0; mask < (1 << H); mask++) if (dp[mask]) for (int nx : tr[mask]) nd[nx] = (nd[nx] + dp[mask]) % MOD;
        dp = nd;
    }
    vector<ll> c = bm(seq);
    cout << nth(seq, c, n) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static final int H = 4;
    static long pw(long b, long e) { long r = 1; b %= MOD; for (; e > 0; e >>= 1, b = b * b % MOD) if ((e & 1) == 1) r = r * b % MOD; return r; }
    static void fill(int row, int cur, int nxt, List<Integer> out) {
        if (row == H) { out.add(nxt); return; }
        if ((cur >> row & 1) == 1) { fill(row + 1, cur, nxt, out); return; }
        fill(row + 1, cur, nxt | 1 << row, out);
        if (row + 1 < H && (cur >> (row + 1) & 1) == 0) fill(row + 2, cur, nxt, out);
    }
    static long[] bm(long[] s) {
        long[] C = {1}, B = {1};
        int L = 0, m = 1; long b = 1;
        for (int n = 0; n < s.length; n++) {
            long d = 0;
            for (int i = 0; i <= L && i < C.length; i++) d = (d + C[i] * s[n - i]) % MOD;
            if (d == 0) { m++; continue; }
            long[] T = C.clone();
            long coef = d * pw(b, MOD - 2) % MOD;
            if (C.length < B.length + m) C = Arrays.copyOf(C, B.length + m);
            for (int i = 0; i < B.length; i++) C[i + m] = (C[i + m] - coef * B[i] % MOD + MOD) % MOD;
            if (2 * L <= n) { L = n + 1 - L; B = T; b = d; m = 1; } else m++;
        }
        long[] c = new long[L];
        for (int i = 1; i <= L; i++) c[i - 1] = (MOD - (i < C.length ? C[i] : 0)) % MOD;
        return c;
    }
    static long[] mm(long[] p, long[] q, long[] c) {
        int k = c.length;
        long[] r = new long[2 * k - 1];
        for (int i = 0; i < k; i++) for (int j = 0; j < k; j++) r[i + j] = (r[i + j] + p[i] * q[j]) % MOD;
        for (int d = 2 * k - 2; d >= k; d--) for (int i = 0; i < k; i++) r[d - 1 - i] = (r[d - 1 - i] + r[d] * c[i]) % MOD;
        return Arrays.copyOf(r, k);
    }
    static long nth(long[] a, long[] c, long n) {
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
        long n = Long.parseLong(new BufferedReader(new InputStreamReader(System.in)).readLine().trim());
        List<List<Integer>> tr = new ArrayList<>();
        for (int mask = 0; mask < (1 << H); mask++) { List<Integer> l = new ArrayList<>(); fill(0, mask, 0, l); tr.add(l); }
        int TERMS = 2 * (1 << H) + 10;
        long[] dp = new long[1 << H], seq = new long[TERMS];
        dp[0] = 1;
        for (int col = 0; col < TERMS; col++) {
            seq[col] = dp[0];
            long[] nd = new long[1 << H];
            for (int mask = 0; mask < (1 << H); mask++) if (dp[mask] != 0) for (int nx : tr.get(mask)) nd[nx] = (nd[nx] + dp[mask]) % MOD;
            dp = nd;
        }
        System.out.println(nth(seq, bm(seq), n));
    }
}
```

</details>

<!-- test
in:
2
out:
5
-->
<!-- test
in:
0
out:
1
-->
<!-- test
in:
10
out:
18061
-->
<!-- test
in:
1000000000000000000
out:
328515267
-->

### Example 4 — Cowmpany Cowmpensation  ·  ★ 2700

- **Source:** [CF 995F · Cowmpany Cowmpensation](https://codeforces.com/problemset/problem/995/F) — 2700
- **Difficulty:** 2700
- **Problem:** A rooted tree of $n\le3000$ employees (boss of $i+1$ is $p_i\le i$). Assign integer salaries in $[1,D]$ ($D\le10^9$) so that nobody earns more
  than their boss. Count assignments modulo $10^9+7$.
- **Thinking from first principles:** The obvious DP $f_v(x)$ = ways for the subtree of $v$ with $v$'s salary $\le x$ satisfies
  $f_v(x)=\sum_{s=1}^{x}\prod_{c}f_c(s)$ — but $x$ ranges up to $10^9$. Look at the *shape* of $f_v$: for a leaf $f(x)=x$; a product of polynomials is a
  polynomial whose degree is the sum; a prefix sum raises the degree by one. By induction $f_v$ is a polynomial of degree $\lvert\text{subtree}(v)\rvert\le n$.
  So compute $f_{\text{root}}(x)$ for $x=0..n$ with the DP ($O(n^2)$) and interpolate at $D$.

<details><summary>Solution</summary>

Children have larger indices than parents, so process $v=n..1$: finish $f_v$ from the product accumulated in $\text{prod}_v$, multiply it into
$\text{prod}_{p_v}$. Then `lagrangeConsecutive` on $f_1(0..n)$. $O(n^2)$ time, $O(n^2)$ memory (`int`).

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007;
ll pw(ll b, ll e) { ll r = 1; b %= MOD; for (; e; e >>= 1, b = b * b % MOD) if (e & 1) r = r * b % MOD; return r; }
int main() {
    int n; ll D; cin >> n >> D;
    vector<int> par(n + 1, 0);
    for (int i = 2; i <= n; i++) cin >> par[i];
    int N = n;                                                 // points x = 0..N
    vector<vector<int>> prod(n + 1, vector<int>(N + 1, 1));
    vector<ll> f(N + 1);
    for (int v = n; v >= 1; v--) {
        f[0] = 0;
        for (int x = 1; x <= N; x++) f[x] = (f[x - 1] + prod[v][x]) % MOD;   // f_v(x) = sum_{s<=x} prod_v(s)
        if (v > 1) for (int x = 0; x <= N; x++) prod[par[v]][x] = (ll)prod[par[v]][x] * f[x] % MOD;
        vector<int>().swap(prod[v]);                           // free memory
    }
    // f now holds f_1(0..N); interpolate at D
    ll X = D % MOD;
    if (X <= N) { cout << f[X] << '\n'; return 0; }
    vector<ll> pre(N + 2, 1), suf(N + 2, 1), fact(N + 1, 1);
    for (int i = 0; i <= N; i++) pre[i + 1] = pre[i] * ((X - i) % MOD) % MOD;
    for (int i = N; i >= 0; i--) suf[i] = suf[i + 1] * ((X - i) % MOD) % MOD;
    for (int i = 1; i <= N; i++) fact[i] = fact[i - 1] * i % MOD;
    ll res = 0;
    for (int i = 0; i <= N; i++) {
        ll term = f[i] * pre[i] % MOD * suf[i + 1] % MOD * pw(fact[i] * fact[N - i] % MOD, MOD - 2) % MOD;
        res = ((N - i) & 1) ? (res - term + MOD) % MOD : (res + term) % MOD;
    }
    cout << res << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long pw(long b, long e) { long r = 1; b %= MOD; for (; e > 0; e >>= 1, b = b * b % MOD) if ((e & 1) == 1) r = r * b % MOD; return r; }
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        st.nextToken(); long D = (long) st.nval;
        int[] par = new int[n + 1];
        for (int i = 2; i <= n; i++) { st.nextToken(); par[i] = (int) st.nval; }
        int N = n;
        int[][] prod = new int[n + 1][];
        long[] f = new long[N + 1];
        for (int v = n; v >= 1; v--) {
            if (prod[v] == null) { prod[v] = new int[N + 1]; Arrays.fill(prod[v], 1); }
            f[0] = 0;
            for (int x = 1; x <= N; x++) f[x] = (f[x - 1] + prod[v][x]) % MOD;
            if (v > 1) {
                int p = par[v];
                if (prod[p] == null) { prod[p] = new int[N + 1]; Arrays.fill(prod[p], 1); }
                for (int x = 0; x <= N; x++) prod[p][x] = (int) ((long) prod[p][x] * f[x] % MOD);
            }
            prod[v] = null;
        }
        long X = D % MOD;
        if (X <= N) { System.out.println(f[(int) X]); return; }
        long[] pre = new long[N + 2], suf = new long[N + 2], fact = new long[N + 1];
        pre[0] = 1; suf[N + 1] = 1; fact[0] = 1;
        for (int i = 0; i <= N; i++) pre[i + 1] = pre[i] * ((X - i) % MOD) % MOD;
        for (int i = N; i >= 0; i--) suf[i] = suf[i + 1] * ((X - i) % MOD) % MOD;
        for (int i = 1; i <= N; i++) fact[i] = fact[i - 1] * i % MOD;
        long res = 0;
        for (int i = 0; i <= N; i++) {
            long term = f[i] * pre[i] % MOD * suf[i + 1] % MOD * pw(fact[i] * fact[N - i] % MOD, MOD - 2) % MOD;
            res = ((N - i) & 1) == 1 ? (res - term + MOD) % MOD : (res + term) % MOD;
        }
        System.out.println(res);
    }
}
```

</details>

<!-- test
in:
3 2
1
1
out:
5
-->
<!-- test
in:
1 1000000000
out:
1000000000
-->
<!-- test
in:
2 5
1
out:
15
-->
<!-- test
in:
4 1000000000
1
2
2
out:
105
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Count the degree correctly**: you need $\deg+1$ samples. Off by one ⇒ silently wrong. When unsure, take one or two extra points — an extra point
   never hurts interpolation.
2. **$X\bmod p\le n$**: return the sample directly; otherwise the prefix products contain a zero factor and the formula divides by nothing useful.
3. **Signs**: the consecutive-point denominator carries $(-1)^{n-i}$.
4. **Precompute inverse factorials** once ($O(n)$) instead of calling `pow` per term when $n$ is $10^6$.
5. **BM needs a prime modulus** and enough terms: $2\times$(upper bound on order) $+$ a safety margin; verify the found recurrence on extra terms.
6. **BM output convention**: return $c_i$ with $s_n=\sum c_is_{n-i}$; Kitamasa expects exactly that, with initial terms $s_0..s_{L-1}$.
7. **If $L=0$** (all-zero sequence), the answer is 0 — guard Kitamasa.
8. **Polynomiality proofs**: check every DP transition is a sum/product of polynomials in the parameter; a `min`, a comparison with the parameter,
   or a division breaks it (then split the parameter range into pieces where it holds).
9. **Memory** in tree DPs over sample points: $n\times(n+1)$ `int`s for $n=3000$ is 36 MB — free child arrays as soon as they are merged.
10. **Java**: `StreamTokenizer` parses numbers as `double` — exact for $\le2^{53}$; read $n\le10^{18}$ as a string.

---

## 7. Going further (toward 2400–2600+)

- **Cumulative sums of powers through several layers** (degree grows by one per layer): [AtCoder ABC208 F · Cumulative Sum](https://atcoder.jp/contests/abc208/tasks/abc208_f) — diff≈2772.
- **Matrix-tree + interpolation** (determinant as a polynomial in an edge weight): [CF 917D · Stranger Trees](https://codeforces.com/problemset/problem/917/D) — 2600
  (see [matrix-tree file](06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md)).
- **Recurrences hidden in palindromic automata / string DPs**: [CF 506E · Mr. Kitayuta's Gift](https://codeforces.com/problemset/problem/506/E) — 3000 (matrix
  power or BM on the counts).
- **Multipoint evaluation / fast interpolation** in $O(n\log^2n)$ with product trees — Library Checker has template problems.

---

## 8. Practice ladder

**1900–2300**
- [ ] [AtCoder ABC137 F · Polynomial Construction](https://atcoder.jp/contests/abc137/tasks/abc137_f) — diff≈2402

**2400+**
- [ ] [CF 622F · The Sum of the k-th Powers](https://codeforces.com/problemset/problem/622/F) — 2600
- [ ] [CF 917D · Stranger Trees](https://codeforces.com/problemset/problem/917/D) — 2600
- [ ] [CF 995F · Cowmpany Cowmpensation](https://codeforces.com/problemset/problem/995/F) — 2700
- [ ] [AtCoder ABC208 F · Cumulative Sum](https://atcoder.jp/contests/abc208/tasks/abc208_f) — diff≈2772
- [ ] [CF 506E · Mr. Kitayuta's Gift](https://codeforces.com/problemset/problem/506/E) — 3000

**Re-solve with BM + Kitamasa (no matrix derivation)**
- [ ] [CSES 1096 · Throwing Dice](https://cses.fi/problemset/task/1096)
- [ ] [CF 1117D · Magic Gems](https://codeforces.com/problemset/problem/1117/D) — 2100
- [ ] [CF 222E · Decoding Genome](https://codeforces.com/problemset/problem/222/E) — 1900

---

## 9. LeetCode / FAANG cross-reference

Rare in interviews: interpolation and Berlekamp–Massey are contest tools. The interview-adjacent idea is "sum of a polynomial has a closed form"
(e.g. $\sum i^2$) — for instance [LC 1137 · N-th Tribonacci Number](https://leetcode.com/problems/n-th-tribonacci-number/) — Easy — is the kind of
sequence BM would discover from five terms.

---

## 10. Self-check

1. Why do $n+1$ values determine a polynomial of degree $\le n$ modulo a prime?
2. Write the denominator of $L_i$ for the points $0..n$.
3. Prove that $\sum_{i\le m}i^k$ has degree $k+1$ in $m$.
4. In Cowmpany Cowmpensation, what is the degree of $f_v$ and why?
5. What does the BM discrepancy measure, and why does subtracting $\frac db x^mB$ fix it without breaking earlier terms?
6. How many terms does BM need for a recurrence of order $L$? What happens if you give it too few?
7. Why is the $4\times n$ tiling count linearly recurrent, and of what maximum order?

<details><summary>Answers</summary>

1. Uniqueness: the difference of two such polynomials has $n+1$ roots in a field, so it is zero. Existence: Lagrange basis.
2. $\prod_{j\ne i}(i-j)=i!\,(n-i)!\,(-1)^{n-i}$.
3. $\Delta S(m)=(m+1)^k$ has degree $k$; since $\Delta$ lowers degree by exactly one on polynomials (via falling powers), $S$ has degree $k+1$.
4. $\lvert\text{subtree}(v)\rvert$: leaves give $x$; the product over children adds degrees; the prefix sum adds one.
5. $d$ is the failure of the current recurrence at the newest term. $x^mB$ evaluated against the sequence is $0$ at all earlier tested positions and
   equals $b$ at the current one (it is the old recurrence that failed $m$ steps ago, shifted), so $\frac db x^mB$ cancels exactly $d$.
6. $2L$. With fewer, BM may return a shorter recurrence that fits the given prefix but is wrong later.
7. The counts are $e_0^TM^ne_0$ for the $16\times16$ profile transfer matrix $M$; by Cayley–Hamilton they satisfy a recurrence of order $\le16$ (BM finds 4).

</details>
