# Möbius Inversion, Dirichlet Convolution and Floor Sums

> **Band:** 🟣 1900 – 🔴 2700 · **Priority:** 🔥 (floor blocks, μ over gcd) · ⚡ (Dirichlet algebra, floor_sum) · 🧊 (Du's sieve, LTE, Min_25) · **FAANG:** none · **Prerequisites:** [sieves and multiplicative functions](03-sieves-and-factorization.md), [Euler's totient](04-euler-phi-fermat-and-euler-theorem.md), [inclusion–exclusion](../05-Combinatorics-and-Probability/03-inclusion-exclusion.md)
> **You can say you know this when:** you can turn any "sum over pairs with $\gcd = 1$" into $\sum_d \mu(d)(\dots)$, enumerate the $O(\sqrt n)$ blocks of $\lfloor n/i \rfloor$ without off-by-one, derive `floor_sum` from a lattice-point count, and compute $\sum_{i \le 10^{10}}\varphi(i)$ with Du's sieve.

---

## 1. First principles — why this works

### 1.1 Where μ comes from: inclusion–exclusion over primes

Count pairs $1 \le i, j \le n$ with $\gcd(i, j) = 1$. Directly, the condition couples $i$ and $j$. Complement-wise: a pair is "bad for $p$" if $p$ divides both. Inclusion–exclusion over the set of primes dividing both:

$$\#\text{coprime} = \sum_{S \text{ set of primes}} (-1)^{\lvert S\rvert}\,\#\lbrace (i,j) : \textstyle\prod_{p\in S} p \text{ divides both}\rbrace = \sum_{d \text{ squarefree}} (-1)^{\omega(d)} \Bigl\lfloor \frac nd\Bigr\rfloor^2 .$$

The coefficient attached to $d$ is exactly the **Möbius function**:

$$\mu(d) = \begin{cases} 1 & d = 1\\ (-1)^k & d = p_1\cdots p_k \text{ (distinct primes)}\\ 0 & p^2 \mid d\end{cases}$$

The structural fact behind it: **$\sum_{d \mid n}\mu(d) = [n = 1]$**. Proof: for $n > 1$ with $k \ge 1$ distinct primes, only squarefree divisors count, and there are $\binom{k}{j}$ of them with $j$ primes: $\sum_j \binom kj(-1)^j = (1-1)^k = 0$. So $\mu$ is an *indicator generator*:

$$[\gcd(i, j) = 1] = \sum_{d \mid \gcd(i,j)} \mu(d) = \sum_{d \mid i,\ d \mid j} \mu(d).$$

Swapping the order of summation ("for each $d$, how many pairs are divisible by $d$?") is what turns a coupled condition into independent factors $\lfloor n/d\rfloor\cdot\lfloor m/d\rfloor$. That swap is the single most important move in this file.

### 1.2 Dirichlet convolution: the algebra behind every identity

For arithmetic functions define $(f * g)(n) = \sum_{d \mid n} f(d)\,g(n/d)$. It is commutative, associative, has identity $\varepsilon(n) = [n = 1]$, and **the convolution of multiplicative functions is multiplicative** (a divisor of $ab$ with $\gcd(a,b)=1$ splits uniquely as a product of divisors of $a$ and $b$). Let $\mathbf 1(n) = 1$, $\mathrm{id}(n) = n$. Then:

| Identity | Read as |
|---|---|
| $\mu * \mathbf 1 = \varepsilon$ | §1.1 |
| $\varphi * \mathbf 1 = \mathrm{id}$ | $\sum_{d\mid n}\varphi(d) = n$ ([totient §1.4](04-euler-phi-fermat-and-euler-theorem.md)) |
| $\mu * \mathrm{id} = \varphi$ | convolve the previous line with $\mu$ |
| $\mathbf 1 * \mathbf 1 = d$ (divisor count), $\mathrm{id} * \mathbf 1 = \sigma$ | definitions |
| $\mathrm{id} * \varphi = $ gcd-sum $\sum_{k \le n}\gcd(k, n)$ | group $k$ by $\gcd(k, n)$ |

**Möbius inversion.** $g = f * \mathbf 1 \iff f = g * \mu$.
*Proof.* Convolve both sides of $g = f * \mathbf 1$ with $\mu$: $g * \mu = f * (\mathbf 1 * \mu) = f * \varepsilon = f$. The converse is the same computation backwards. ∎
In words: if $g(n) = \sum_{d\mid n} f(d)$ is easy (e.g. "count objects whose gcd is a multiple of $n$"), then $f(n) = \sum_{d \mid n}\mu(n/d)\,g(d)$ ("objects whose gcd is exactly $n$"). The **multiple form** — $G(d) = \sum_{d \mid k} F(k) \iff F(d) = \sum_{d\mid k}\mu(k/d)G(k)$ — is the one used most in contests: $G(d)$ = "number of subsets/pairs all divisible by $d$" is a product of counts, and $F(1)$ is the coprime answer (Example 3).

### 1.3 Floor blocks: $\lfloor n/i\rfloor$ has only $O(\sqrt n)$ values

For $i \le \sqrt n$ there are at most $\sqrt n$ indices; for $i > \sqrt n$, $\lfloor n/i \rfloor < \sqrt n$, so at most $\sqrt n$ values. Total $\le 2\sqrt n$. The indices sharing the value $q = \lfloor n/l\rfloor$ form a contiguous block ending at

$$r = \Bigl\lfloor \frac{n}{q} \Bigr\rfloor = \Bigl\lfloor \frac{n}{\lfloor n/l\rfloor}\Bigr\rfloor ,$$

because $\lfloor n/i\rfloor \ge q \iff i \le n/q$. So any sum $\sum_{i=1}^{n} f(i)\,g(\lfloor n/i\rfloor)$ with a fast prefix sum of $f$ costs $O(\sqrt n)$:

```text
for (l = 1; l <= n; l = r + 1) { q = n / l; r = n / q; ans += (F(r) - F(l-1)) * g(q); }
```

For two numerators $n, m$ use $r = \min(\lfloor n/\lfloor n/l\rfloor\rfloor, \lfloor m/\lfloor m/l\rfloor\rfloor)$ — still $O(\sqrt n + \sqrt m)$ blocks. Nested floors collapse: $\lfloor \lfloor n/a\rfloor / b\rfloor = \lfloor n/(ab)\rfloor$ (write $n = qa + r$; $\lfloor q/b\rfloor = \lfloor (qa + r)/(ab)\rfloor$ since $r < a$), so the set $\lbrace \lfloor n/i\rfloor\rbrace$ is closed under taking floors again — the foundation of Du's sieve and Min_25.

### 1.4 floor_sum: lattice points under a line, solved like Euclid

$S(n, m, a, b) = \sum_{i=0}^{n-1}\lfloor (ai + b)/m\rfloor$ for $0 \le a, b$ and huge $n$ cannot be blocked (the floor values are all different). Two moves reduce it:

1. **Reduce coefficients.** $\lfloor (ai+b)/m\rfloor = \lfloor a/m\rfloor i + \lfloor b/m \rfloor + \lfloor ((a \bmod m) i + (b \bmod m))/m\rfloor$, so
$S = \lfloor a/m\rfloor\frac{n(n-1)}{2} + \lfloor b/m\rfloor n + S(n, m, a \bmod m, b \bmod m)$.
2. **Swap axes** (now $a, b < m$). $S$ counts lattice points $(i, y)$ with $0 \le i < n$ and $1 \le y \le (ai+b)/m$. Count by rows instead: for a fixed $y$, the valid $i$ satisfy $ai \ge my - b$ and $i \le n - 1$, so there are $n - \lceil (my-b)/a\rceil = \lfloor (an + b - my)/a\rfloor$ of them (when non-negative). Rows exist for $y = 1, \dots, Y$ with $Y = \lfloor (an + b)/m\rfloor$. Substituting $y = Y - j$:
$$S = \sum_{j=0}^{Y-1}\Bigl\lfloor \frac{m j + \bigl((an + b) - mY\bigr)}{a}\Bigr\rfloor = S\bigl(Y,\ a,\ m,\ (an+b) \bmod m\bigr).$$

The new modulus is the old $a < m$, so step 1 shrinks the slope from $a/m$ to $(m \bmod a)/a$ — the pair $(m, a)$ evolves exactly like Euclid's algorithm, giving $O(\log m)$ rounds. This is the AtCoder Library `floor_sum`; it counts lattice points in triangles and is the engine behind "$\sum (ai+b) \bmod m$" problems via $x \bmod m = x - m\lfloor x/m\rfloor$.

### 1.5 Prime exponents in factorials and binomials

**Legendre.** $v_p(n!) = \sum_{k \ge 1}\lfloor n/p^k\rfloor$: each multiple of $p^k$ contributes one extra factor $p$ at level $k$. Writing $n$ in base $p$ with digit sum $s_p(n)$, the sum telescopes to

$$v_p(n!) = \frac{n - s_p(n)}{p - 1}.$$

(Each digit $d_i$ at position $i$ contributes $d_i(p^{i-1} + \cdots + 1) = d_i\frac{p^i - 1}{p-1}$.)

**Kummer.** $v_p\binom{m+n}{m}$ equals the **number of carries** when adding $m$ and $n$ in base $p$. Proof: by Legendre it is $\frac{s_p(m) + s_p(n) - s_p(m+n)}{p - 1}$, and each carry lowers the digit sum of the result by exactly $p - 1$ (a column overflowing by $p$ becomes $p$ smaller and adds $1$ to the next column). Corollary: $\binom{n}{k}$ is odd iff $k \mathbin{\&} n = k$ (no carries in base 2 when adding $k$ and $n - k$) — Lucas's theorem in disguise.

---

## 2. Formulas, definitions and identities

| Formula | Meaning / proof sketch |
|---|---|
| $\sum_{d \mid n}\mu(d) = [n=1]$ | §1.1 binomial argument. |
| $\sum_{d\mid n}\frac{\mu(d)}{d} = \frac{\varphi(n)}{n}$ | $\varphi = \mu * \mathrm{id}$. |
| Möbius inversion $g = f*\mathbf 1 \iff f = g*\mu$; multiple form $G(d) = \sum_{d\mid k}F(k) \iff F(d) = \sum_{d\mid k}\mu(k/d)G(k)$ | §1.2. |
| $\#\lbrace i \le n, j \le m : \gcd(i,j) = 1\rbrace = \sum_{d}\mu(d)\lfloor n/d\rfloor\lfloor m/d\rfloor$ | Insert $[\gcd = 1] = \sum_{d\mid\gcd}\mu(d)$, swap sums. $O(\sqrt n)$ with prefix sums of $\mu$. |
| $\#\lbrace \gcd(i,j) = k\rbrace$ | Same formula with $n/k, m/k$. |
| $\sum_{i \le n}\gcd(i, n) = \sum_{d \mid n} d\,\varphi(n/d)$ | $\mathrm{id}*\varphi$. |
| $\sum_{i \le n}\sum_{j\le n}\gcd(i,j) = \sum_{d \le n}\varphi(d)\lfloor n/d\rfloor^2$ | $\gcd(i,j) = \sum_{d \mid \gcd}\varphi(d)$ (from $\varphi * \mathbf 1 = \mathrm{id}$), swap sums. |
| $\sum_{i\le n}\sum_{j \le m}\gcd(i,j) = \sum_d \varphi(d)\lfloor n/d\rfloor\lfloor m/d\rfloor$ | Same. |
| $\sum_{i,j \le n}\operatorname{lcm}(i,j) = \sum_{d\le n} d\sum_{k \le n/d}\mu(k)k^2\,T(\lfloor n/(dk)\rfloor)^2$, $T(x) = \frac{x(x+1)}{2}$ (🧊) | $\operatorname{lcm} = ij/\gcd$; group by $\gcd = d$, remove coprimality with $\mu$. |
| #distinct $\lfloor n/i\rfloor$ $\le 2\sqrt n$; block end $r = \lfloor n/\lfloor n/l\rfloor\rfloor$ | §1.3. |
| $\lfloor\lfloor n/a\rfloor/b\rfloor = \lfloor n/(ab)\rfloor$ | §1.3. |
| $\sum_{i=1}^{n}(k \bmod i) = nk - \sum_{i=1}^{n} i\lfloor k/i\rfloor$ | $x \bmod i = x - i\lfloor x/i\rfloor$; blocks. |
| $\sum_{i=1}^n \sigma(i) = \sum_{d=1}^{n} d\lfloor n/d\rfloor$; $\sum d(i) = \sum\lfloor n/d\rfloor$ | Count pairs $(d, i)$, $d \mid i$, by $d$. |
| `floor_sum`$(n,m,a,b) = \sum_{i<n}\lfloor (ai+b)/m\rfloor$ in $O(\log m)$ | §1.4. |
| $\sum_{i < n}((ai + b) \bmod m) = \sum(ai+b) - m\cdot\text{floor\_sum}$ | Definition of mod. |
| Legendre $v_p(n!) = \sum_k\lfloor n/p^k\rfloor = \frac{n - s_p(n)}{p-1}$ | §1.5. Trailing zeros of $n!$: $v_5(n!)$. |
| Kummer $v_p\binom{m+n}{m}$ = #carries of $m + n$ in base $p$ | §1.5. |
| LTE (🧊): $p$ odd, $p \mid x - y$, $p \nmid x, y$: $v_p(x^n - y^n) = v_p(x - y) + v_p(n)$ | Factor $x^n - y^n = (x - y)\sum x^{n-1-i}y^i$; the sum is $\equiv n x^{n-1} \pmod p$, and the case $n = p$ adds exactly one factor $p$. |
| LTE, $p = 2$, $x, y$ odd, $n$ even: $v_2(x^n - y^n) = v_2(x-y) + v_2(x+y) + v_2(n) - 1$ | Repeated $x^{2k} - y^{2k} = (x^k - y^k)(x^k + y^k)$. |
| Dirichlet hyperbola: $\sum_{k \le N}(f*g)(k) = \sum_{d\le a}f(d)G(N/d) + \sum_{d\le b}g(d)F(N/d) - F(a)G(b)$, $ab = N$ | Count lattice points $de \le N$ split along $d \le a$ or $e \le b$. |
| Du's sieve: $g(1)S(n) = \sum_{i\le n}(f*g)(i) - \sum_{d=2}^{n}g(d)\,S(\lfloor n/d\rfloor)$ | Expand $\sum_{i \le n}(f*g)(i) = \sum_d g(d)S(\lfloor n/d\rfloor)$; isolate $d = 1$. |
| $\Phi(n) = \sum_{i\le n}\varphi(i) = \frac{n(n+1)}{2} - \sum_{d=2}^{n}\Phi(\lfloor n/d\rfloor)$ | Du with $g = \mathbf 1$, $f*g = \mathrm{id}$. |
| Mertens $M(n) = \sum_{i \le n}\mu(i) = 1 - \sum_{d=2}^{n}M(\lfloor n/d\rfloor)$ | Du with $g = \mathbf 1$, $f * g = \varepsilon$. |
| Du's sieve cost: $O(n^{3/4})$ plain, $O(n^{2/3})$ with a linear sieve to $n^{2/3}$ | Sum of $\sqrt{n/i}$ over block values. |

---

## 3. Implementation (C++ and Java)

```cpp
// Mobius sieve, coprime-pair count with 2-D floor blocks, floor_sum, Legendre and Kummer.
vector<int> mobius_sieve(int n) {                   // linear sieve for mu
    vector<int> mu(n + 1, 0), primes; vector<bool> comp(n + 1, false);
    mu[1] = 1;
    for (int i = 2; i <= n; i++) {
        if (!comp[i]) { primes.push_back(i); mu[i] = -1; }
        for (int p : primes) {
            if (1LL * i * p > n) break;
            comp[i * p] = true;
            if (i % p == 0) { mu[i * p] = 0; break; }
            mu[i * p] = -mu[i];
        }
    }
    return mu;
}
// #{(i, j) : 1 <= i <= n, 1 <= j <= m, gcd(i, j) = 1}; needs prefix sums of mu up to min(n, m)
long long coprime_pairs(long long n, long long m, const vector<long long> &muPrefix) {
    long long res = 0, lim = min(n, m);
    for (long long l = 1, r; l <= lim; l = r + 1) {
        r = min(n / (n / l), m / (m / l));         // largest index with the same pair of quotients
        res += (muPrefix[r] - muPrefix[l - 1]) * (n / l) * (m / l);
    }
    return res;
}
// sum_{i=0}^{n-1} floor((a*i + b) / m); n < 2^32, 1 <= m < 2^32, a, b >= 0 (any size, reduced inside)
unsigned long long floor_sum(unsigned long long n, unsigned long long m, unsigned long long a, unsigned long long b) {
    unsigned long long ans = 0;
    while (true) {
        if (a >= m) { ans += n * (n - 1) / 2 * (a / m); a %= m; }
        if (b >= m) { ans += n * (b / m); b %= m; }
        unsigned long long y_max = a * n + b;
        if (y_max < m) break;
        n = y_max / m;                               // number of rows Y
        b = y_max % m;
        swap(m, a);                                  // S(Y, a, m, (an+b) mod m)
    }
    return ans;
}
long long vp_factorial(long long n, long long p) {  // v_p(n!) (Legendre); NOT named legendre: std::legendre exists
    long long e = 0;
    while (n) { n /= p; e += n; }
    return e;
}
int kummer_carries(long long m, long long n, long long p) {   // = v_p(C(m+n, m))
    int carries = 0, c = 0;
    while (m || n || c) {
        long long s = m % p + n % p + c;
        c = s >= p; carries += c;
        m /= p; n /= p;
    }
    return carries;
}
```

```java
// Mobius sieve, coprime-pair count with 2-D floor blocks, floor_sum, Legendre and Kummer.
static int[] mobiusSieve(int n) {
    int[] mu = new int[n + 1], primes = new int[n + 1]; boolean[] comp = new boolean[n + 1];
    int pc = 0; mu[1] = 1;
    for (int i = 2; i <= n; i++) {
        if (!comp[i]) { primes[pc++] = i; mu[i] = -1; }
        for (int j = 0; j < pc; j++) {
            int p = primes[j];
            if ((long) i * p > n) break;
            comp[i * p] = true;
            if (i % p == 0) { mu[i * p] = 0; break; }
            mu[i * p] = -mu[i];
        }
    }
    return mu;
}
static long coprimePairs(long n, long m, long[] muPrefix) {
    long res = 0, lim = Math.min(n, m);
    for (long l = 1, r; l <= lim; l = r + 1) {
        r = Math.min(n / (n / l), m / (m / l));
        res += (muPrefix[(int) r] - muPrefix[(int) (l - 1)]) * (n / l) * (m / l);
    }
    return res;
}
// same contract as the C++ version; values stay below 2^63 for n, m <= 1e9
static long floorSum(long n, long m, long a, long b) {
    long ans = 0;
    while (true) {
        if (a >= m) { ans += n * (n - 1) / 2 * (a / m); a %= m; }
        if (b >= m) { ans += n * (b / m); b %= m; }
        long yMax = a * n + b;
        if (yMax < m) break;
        n = yMax / m;
        b = yMax % m;
        long t = m; m = a; a = t;
    }
    return ans;
}
static long vpFactorial(long n, long p) { long e = 0; while (n > 0) { n /= p; e += n; } return e; }
static int kummerCarries(long m, long n, long p) {
    int carries = 0; long c = 0;
    while (m > 0 || n > 0 || c > 0) {
        long s = m % p + n % p + c;
        c = s >= p ? 1 : 0; carries += c;
        m /= p; n /= p;
    }
    return carries;
}
```

---

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| $\sum\sum [\gcd(i, j) = 1]$, $\sum\sum \gcd$, "pairs with gcd $k$" | insert $\mu$ (or $\varphi$) over divisors of the gcd, swap sums, floor blocks |
| "number of subsets / subsequences with gcd 1" | $\sum_d \mu(d)(2^{c_d} - 1)$ with $c_d$ = #multiples of $d$ (harmonic loop) |
| "exactly gcd $= g$" from "all divisible by $g$" | Möbius inversion in the multiple form, or the subtract-multiples DP: $F(d) = G(d) - \sum_{k \ge 2} F(kd)$ |
| sums of $\lfloor n/i\rfloor$, $n \bmod i$, $\sigma(i)$, $d(i)$ with $n \le 10^{12}$ | floor blocks, $O(\sqrt n)$ |
| $\sum \lfloor (ai+b)/m\rfloor$, $\sum (ai + b)\bmod m$, lattice points under a line | `floor_sum` |
| trailing zeros, "largest $k$ with $p^k \mid n!$", divisibility of $\binom nk$ | Legendre, Kummer, Lucas |
| prefix sums of $\varphi$ or $\mu$ up to $10^{10}$–$10^{11}$ | Du's sieve (🔴) |
| prefix sums of a multiplicative $f$ with $f(p)$ a polynomial in $p$, $n \le 10^{11}$ | Min_25 sieve (🔴, mention) |

---

## 5. Worked examples (graded)

### Example 1 — Floor and Mod  ·  ★ 1700

- **Source:** [CF 1485C · Floor and Mod](https://codeforces.com/problemset/problem/1485/C) — 1700
- **Difficulty:** 1700
- **Problem:** $t \le 100$ tests with $1 \le x, y \le 10^9$: count pairs $1 \le a \le x$, $1 \le b \le y$ with $\lfloor a/b\rfloor = a \bmod b$.
- **Thinking from first principles:** Name the common value $k$. Then $a = kb + k = k(b+1)$, with $k < b$ (it is a remainder) and $k \ge 1$ ($a \ge 1$). For a fixed $b$: $1 \le k \le \min(b - 1, \lfloor x/(b+1)\rfloor)$. So the answer is $\sum_{b=1}^{y}\min(b - 1, \lfloor x/(b+1)\rfloor)$ — $10^9$ terms. The minimum switches once: $b - 1 \le x/(b+1) \iff b^2 \le x + 1$. Below $B = \lfloor\sqrt{x+1}\rfloor$ sum $b - 1$ in closed form; above, sum $\lfloor x/d\rfloor$ over $d = b + 1 \in [B + 2, y + 1]$ with floor blocks.

<details><summary>Solution</summary>

$O(\sqrt x)$ per test. Clamp the second range at $d \le x$ (beyond it the floor is $0$).

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
int main() {
    int t; cin >> t;
    while (t--) {
        ll x, y; cin >> x >> y;
        ll B = sqrtl((long double)x + 1);
        while (B * B > x + 1) B--;
        while ((B + 1) * (B + 1) <= x + 1) B++;
        ll lim = min(B, y), ans = lim * (lim - 1) / 2;           // sum of (b-1) for b <= lim
        ll lo = B + 2, hi = min(y + 1, x);                         // d = b + 1
        for (ll l = lo, r; l <= hi; l = r + 1) {
            r = min(hi, x / (x / l));
            ans += (r - l + 1) * (x / l);
        }
        cout << ans << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int t = Integer.parseInt(br.readLine().trim());
        StringBuilder sb = new StringBuilder();
        while (t-- > 0) {
            StringTokenizer st = new StringTokenizer(br.readLine());
            long x = Long.parseLong(st.nextToken()), y = Long.parseLong(st.nextToken());
            long B = (long) Math.sqrt((double) (x + 1));
            while (B * B > x + 1) B--;
            while ((B + 1) * (B + 1) <= x + 1) B++;
            long lim = Math.min(B, y), ans = lim * (lim - 1) / 2;
            long lo = B + 2, hi = Math.min(y + 1, x);
            for (long l = lo, r; l <= hi; l = r + 1) {
                r = Math.min(hi, x / (x / l));
                ans += (r - l + 1) * (x / l);
            }
            sb.append(ans).append('\n');
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
9
3 4
2 100
4 3
50 3
12 4
69 420
12345 6789
123456 789
12345678 9
out:
1
0
2
3
5
141
53384
160909
36
-->
<!-- test
in:
2
1 1
1000000000 1000000000
out:
0
10438801384
-->

### Example 2 — Sum of Divisors up to $10^{12}$  ·  ★ ≈1800 (est.)

- **Source:** [CSES 1082 · Sum of Divisors](https://cses.fi/problemset/task/1082)
- **Difficulty:** ≈1800 (est.)
- **Problem:** Given $n \le 10^{12}$, print $\sum_{i=1}^{n}\sigma(i) \bmod (10^9+7)$.
- **Thinking from first principles:** Summing $\sigma(i)$ one by one is $10^{12}$ terms. Swap the double sum: $\sum_{i\le n}\sum_{d \mid i} d = \sum_{d \le n} d\cdot\#\lbrace i \le n : d \mid i\rbrace = \sum_{d\le n} d\lfloor n/d\rfloor$. In a floor block $[l, r]$ the factor $\lfloor n/d \rfloor = q$ is constant, so the block contributes $q\cdot\frac{(l + r)(r - l + 1)}{2}$. About $2\cdot10^6$ blocks.

<details><summary>Solution</summary>

The only trap is the arithmetic: $(l + r)(r - l + 1)$ reaches $2\cdot10^{24}$. Halve the even factor *before* reducing modulo $p$. $O(\sqrt n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007LL;
int main() {
    ll n; cin >> n;
    ll ans = 0;
    for (ll l = 1, r; l <= n; l = r + 1) {
        ll q = n / l; r = n / q;
        ll s = l + r, c = r - l + 1;                  // block sum = s * c / 2
        if (s % 2 == 0) s /= 2; else c /= 2;
        ll blockSum = (s % MOD) * (c % MOD) % MOD;
        ans = (ans + q % MOD * blockSum) % MOD;
    }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        long n = Long.parseLong(br.readLine().trim());
        final long MOD = 1_000_000_007L;
        long ans = 0;
        for (long l = 1, r; l <= n; l = r + 1) {
            long q = n / l; r = n / q;
            long s = l + r, c = r - l + 1;
            if (s % 2 == 0) s /= 2; else c /= 2;
            long blockSum = (s % MOD) * (c % MOD) % MOD;
            ans = (ans + q % MOD * blockSum) % MOD;
        }
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
5
out:
21
-->
<!-- test
in:
1
out:
1
-->
<!-- test
in:
1000000000000
out:
146462362
-->

### Example 3 — Counting Coprime Pairs  ·  ★ ≈1900 (est.)

- **Source:** [CSES 2417 · Counting Coprime Pairs](https://cses.fi/problemset/task/2417)
- **Difficulty:** ≈1900 (est.)
- **Problem:** $n \le 10^5$ numbers $x_i \le 10^6$. Count pairs $i < j$ with $\gcd(x_i, x_j) = 1$.
- **Thinking from first principles:** $n^2/2 = 5\cdot10^9$ gcds is too slow. Let $c_d$ = number of elements divisible by $d$ (harmonic loop over the value range, $\approx 1.4\cdot10^7$). Pairs with both elements divisible by $d$: $\binom{c_d}{2}$ — that is $G(d) = \sum_{d \mid k}F(k)$ where $F(k)$ = pairs with gcd exactly $k$. Möbius inversion at $d = 1$: $F(1) = \sum_d \mu(d)\binom{c_d}{2}$.

<details><summary>Solution</summary>

Count occurrences, compute $c_d$ by summing over multiples, sieve $\mu$, sum. $O(A \log A)$ with $A = 10^6$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    const int A = 1'000'000;
    int n; cin >> n;
    vector<int> occ(A + 1, 0);
    for (int i = 0; i < n; i++) { int x; cin >> x; occ[x]++; }
    vector<int> mu(A + 1, 0), primes; vector<bool> comp(A + 1, false);
    mu[1] = 1;
    for (int i = 2; i <= A; i++) {
        if (!comp[i]) { primes.push_back(i); mu[i] = -1; }
        for (int p : primes) {
            if (1LL * i * p > A) break;
            comp[i * p] = true;
            if (i % p == 0) { mu[i * p] = 0; break; }
            mu[i * p] = -mu[i];
        }
    }
    long long ans = 0;
    for (int d = 1; d <= A; d++) {
        if (mu[d] == 0) continue;
        long long c = 0;
        for (int k = d; k <= A; k += d) c += occ[k];
        ans += mu[d] * (c * (c - 1) / 2);
    }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        final int A = 1_000_000;
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] occ = new int[A + 1];
        for (int i = 0; i < n; i++) occ[in.nextInt()]++;
        int[] mu = new int[A + 1], primes = new int[A + 1]; boolean[] comp = new boolean[A + 1];
        int pc = 0; mu[1] = 1;
        for (int i = 2; i <= A; i++) {
            if (!comp[i]) { primes[pc++] = i; mu[i] = -1; }
            for (int j = 0; j < pc; j++) {
                int p = primes[j];
                if ((long) i * p > A) break;
                comp[i * p] = true;
                if (i % p == 0) { mu[i * p] = 0; break; }
                mu[i * p] = -mu[i];
            }
        }
        long ans = 0;
        for (int d = 1; d <= A; d++) {
            if (mu[d] == 0) continue;
            long c = 0;
            for (int k = d; k <= A; k += d) c += occ[k];
            ans += mu[d] * (c * (c - 1) / 2);
        }
        System.out.println(ans);
    }
    static class FastReader {
        private final DataInputStream st; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException { if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } } return buf[ptr++]; }
        long nextLong() throws IOException { int c = read(); while (c != -1 && c <= ' ') c = read(); boolean neg = c == '-'; if (neg) c = read(); long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); } return neg ? -r : r; }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
8
5 4 20 1 16 17 5 15
out:
19
-->
<!-- test
in:
3
6 6 6
out:
0
-->
<!-- test
in:
5
1 1 1 2 3
out:
10
-->

### Example 4 — $\sum_{i,j \le n}\gcd(i, j)$ for $n = 5\cdot10^6$  ·  ★ ≈2000 (est.)

- **Source:** Original problem
- **Difficulty:** ≈2000 (est.)
- **Problem:** Given $n \le 5\cdot10^6$, print $\sum_{i=1}^{n}\sum_{j=1}^{n}\gcd(i, j)$ (exact; it fits in 64-bit).
- **Thinking from first principles:** $n^2 = 2.5\cdot10^{13}$ pairs. Use $\varphi * \mathbf 1 = \mathrm{id}$ to *expand the gcd into a sum over its divisors*: $\gcd(i,j) = \sum_{d \mid \gcd(i,j)}\varphi(d)$. Swap: $\sum_d\varphi(d)\cdot\#\lbrace (i,j) : d \mid i, d\mid j\rbrace = \sum_{d\le n}\varphi(d)\lfloor n/d\rfloor^2$. One $\varphi$ sieve, one linear pass (with $q$ queries one would block with prefix sums of $\varphi$).

<details><summary>Solution</summary>

$\varphi$ by the Eratosthenes-style sieve into an `int` array (20 MB), then $\sum\varphi(d)\lfloor n/d\rfloor^2$. The result is $< n^2 \cdot H_n \approx 4\cdot10^{14}$. $O(n\log\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    int n; cin >> n;
    vector<int> phi(n + 1);
    iota(phi.begin(), phi.end(), 0);
    for (int p = 2; p <= n; p++)
        if (phi[p] == p)
            for (int j = p; j <= n; j += p) phi[j] -= phi[j] / p;
    long long ans = 0;
    for (int d = 1; d <= n; d++) { long long q = n / d; ans += phi[d] * q * q; }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int n = Integer.parseInt(br.readLine().trim());
        int[] phi = new int[n + 1];
        for (int i = 0; i <= n; i++) phi[i] = i;
        for (int p = 2; p <= n; p++)
            if (phi[p] == p)
                for (int j = p; j <= n; j += p) phi[j] -= phi[j] / p;
        long ans = 0;
        for (int d = 1; d <= n; d++) { long q = n / d; ans += phi[d] * q * q; }
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
1
out:
1
-->
<!-- test
in:
4
out:
24
-->
<!-- test
in:
5000000
out:
240539697026056
-->

### Example 5 — Floor Sum  ·  ★ ≈2200 (est.)

- **Source:** [AtCoder PRACTICE2 C · Floor Sum](https://atcoder.jp/contests/practice2/tasks/practice2_c)
- **Difficulty:** ≈2200 (est.)
- **Problem:** $T \le 10^5$ queries $(n, m, a, b)$ with $1 \le n, m \le 10^9$, $0 \le a, b < m$: print $\sum_{i=0}^{n-1}\lfloor (ai+b)/m\rfloor$.
- **Thinking from first principles:** The terms change at almost every $i$, so blocks do not help. Interpret the sum as lattice points under the line $y = (ax + b)/m$ and count them by rows instead of columns (§1.4): that swaps the roles of $a$ and $m$, and reducing $m \bmod a$ continues the Euclidean algorithm. $O(\log m)$ per query.

<details><summary>Solution</summary>

`floor_sum` from §3. Under these bounds $a n + b < 10^{18} + 10^9$ and the answer $< 5\cdot10^{17}$ — 64-bit is enough.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ull = unsigned long long;
ull floor_sum(ull n, ull m, ull a, ull b) {
    ull ans = 0;
    while (true) {
        if (a >= m) { ans += n * (n - 1) / 2 * (a / m); a %= m; }
        if (b >= m) { ans += n * (b / m); b %= m; }
        ull y_max = a * n + b;
        if (y_max < m) break;
        n = y_max / m; b = y_max % m;
        swap(m, a);
    }
    return ans;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int T; cin >> T;
    while (T--) { ull n, m, a, b; cin >> n >> m >> a >> b; cout << floor_sum(n, m, a, b) << '\n'; }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long floorSum(long n, long m, long a, long b) {
        long ans = 0;
        while (true) {
            if (a >= m) { ans += n * (n - 1) / 2 * (a / m); a %= m; }
            if (b >= m) { ans += n * (b / m); b %= m; }
            long yMax = a * n + b;
            if (yMax < m) break;
            n = yMax / m; b = yMax % m;
            long t = m; m = a; a = t;
        }
        return ans;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int T = in.nextInt();
        while (T-- > 0) out.println(floorSum(in.nextLong(), in.nextLong(), in.nextLong(), in.nextLong()));
        out.flush();
    }
    static class FastReader {
        private final DataInputStream st; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException { if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } } return buf[ptr++]; }
        long nextLong() throws IOException { int c = read(); while (c != -1 && c <= ' ') c = read(); boolean neg = c == '-'; if (neg) c = read(); long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); } return neg ? -r : r; }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
5
4 10 6 3
6 5 4 3
1 1 0 0
31415 92653 58979 32384
1000000000 1000000000 999999999 999999999
out:
3
13
0
314095480
499999999500000000
-->
<!-- test
in:
2
1000000000 1 0 0
7 3 2 1
out:
0
14
-->

### Example 6 — Du's sieve: $\sum_{i \le n}\varphi(i)$ and $\sum_{i\le n}\mu(i)$ for $n = 10^{10}$  ·  ★ ≈2500 (est.) 🔴

- **Source:** Original problem
- **Difficulty:** ≈2500 (est.)
- **Problem:** Given $n \le 10^{10}$, print $\Phi(n) = \sum_{i\le n}\varphi(i) \bmod (10^9+7)$ and the Mertens value $M(n) = \sum_{i \le n}\mu(i)$ (exact).
- **Thinking from first principles:** A sieve to $10^{10}$ is impossible. But we know prefix sums of convolutions with $\mathbf 1$ in closed form: $\sum_{i\le v}(\varphi * \mathbf 1)(i) = \sum_{i\le v} i$ and $\sum_{i \le v}(\mu * \mathbf 1)(i) = 1$. Expanding the left side by the outer divisor gives $\sum_{d \le v}\Phi(\lfloor v/d\rfloor)$ — the unknown at smaller arguments, all of the form $\lfloor n/k\rfloor$ (§1.3). Isolate $d = 1$, recurse with floor blocks and memoise. Sieving directly up to $L \approx n^{2/3}$ cuts the recursion off: total cost $O(n^{2/3})$.

<details><summary>Solution</summary>

$L = 5\cdot10^6$ (above $n^{2/3} \approx 4.6\cdot10^6$). For $v > L$ the value $v = \lfloor n/k\rfloor$ has $k = n/v < n/L$, so memoise in an array indexed by $k$. Reduce $v(v+1)/2$ by halving the even factor first. Recursion depth is tiny (each level divides by at least 2).

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007LL;
const int L = 5'000'000;
ll n;
vector<ll> sphi;            // prefix sums of phi mod MOD, up to L
vector<int> smu;            // prefix sums of mu, up to L
vector<ll> memoPhi, memoMu; vector<char> done;
ll tri(ll v) { ll a = v, b = v + 1; if (a % 2 == 0) a /= 2; else b /= 2; return (a % MOD) * (b % MOD) % MOD; }
void calc(ll v) {           // fills memo for v > L (both functions at once)
    int k = n / v;
    if (done[k]) return;
    ll rp = tri(v), rm = 1;
    for (ll l = 2, r; l <= v; l = r + 1) {
        ll q = v / l; r = v / q;
        ll cp, cm;
        if (q <= L) { cp = sphi[q]; cm = smu[q]; } else { calc(q); cp = memoPhi[n / q]; cm = memoMu[n / q]; }
        rp = (rp - (r - l + 1) % MOD * cp % MOD + MOD) % MOD;
        rm -= (r - l + 1) * cm;
    }
    memoPhi[k] = rp; memoMu[k] = rm; done[k] = 1;
}
int main() {
    cin >> n;
    vector<int> phi(L + 1), mu(L + 1, 0), primes; vector<bool> comp(L + 1, false);
    phi[1] = 1; mu[1] = 1;
    for (int i = 2; i <= L; i++) {
        if (!comp[i]) { primes.push_back(i); phi[i] = i - 1; mu[i] = -1; }
        for (int p : primes) {
            if (1LL * i * p > L) break;
            comp[i * p] = true;
            if (i % p == 0) { phi[i * p] = phi[i] * p; mu[i * p] = 0; break; }
            phi[i * p] = phi[i] * (p - 1); mu[i * p] = -mu[i];
        }
    }
    sphi.assign(L + 1, 0); smu.assign(L + 1, 0);
    for (int i = 1; i <= L; i++) { sphi[i] = (sphi[i - 1] + phi[i]) % MOD; smu[i] = smu[i - 1] + mu[i]; }
    if (n <= L) { cout << sphi[n] << ' ' << smu[n] << '\n'; return 0; }
    int K = n / L + 2;
    memoPhi.assign(K, 0); memoMu.assign(K, 0); done.assign(K, 0);
    calc(n);
    cout << memoPhi[1] << ' ' << memoMu[1] << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static final int L = 5_000_000;
    static long n;
    static long[] sphi, memoPhi, memoMu;
    static int[] smu;
    static boolean[] done;
    static long tri(long v) { long a = v, b = v + 1; if (a % 2 == 0) a /= 2; else b /= 2; return (a % MOD) * (b % MOD) % MOD; }
    static void calc(long v) {
        int k = (int) (n / v);
        if (done[k]) return;
        long rp = tri(v), rm = 1;
        for (long l = 2, r; l <= v; l = r + 1) {
            long q = v / l; r = v / q;
            long cp, cm;
            if (q <= L) { cp = sphi[(int) q]; cm = smu[(int) q]; }
            else { calc(q); cp = memoPhi[(int) (n / q)]; cm = memoMu[(int) (n / q)]; }
            rp = (rp - (r - l + 1) % MOD * cp % MOD + MOD) % MOD;
            rm -= (r - l + 1) * cm;
        }
        memoPhi[k] = rp; memoMu[k] = rm; done[k] = true;
    }
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        n = Long.parseLong(br.readLine().trim());
        int[] phi = new int[L + 1], mu = new int[L + 1], primes = new int[L / 2 + 10];
        boolean[] comp = new boolean[L + 1];
        int pc = 0; phi[1] = 1; mu[1] = 1;
        for (int i = 2; i <= L; i++) {
            if (!comp[i]) { primes[pc++] = i; phi[i] = i - 1; mu[i] = -1; }
            for (int j = 0; j < pc; j++) {
                int p = primes[j];
                if ((long) i * p > L) break;
                comp[i * p] = true;
                if (i % p == 0) { phi[i * p] = phi[i] * p; mu[i * p] = 0; break; }
                phi[i * p] = phi[i] * (p - 1); mu[i * p] = -mu[i];
            }
        }
        sphi = new long[L + 1]; smu = new int[L + 1];
        for (int i = 1; i <= L; i++) { sphi[i] = (sphi[i - 1] + phi[i]) % MOD; smu[i] = smu[i - 1] + mu[i]; }
        if (n <= L) { System.out.println(sphi[(int) n] + " " + smu[(int) n]); return; }
        int K = (int) (n / L) + 2;
        memoPhi = new long[K]; memoMu = new long[K]; done = new boolean[K];
        calc(n);
        System.out.println(memoPhi[1] + " " + memoMu[1]);
    }
}
```

</details>

<!-- test
in:
10
out:
32 -1
-->
<!-- test
in:
10000000
out:
356214470 1037
-->
<!-- test
in:
10000000000
out:
111732206 -33722
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Block end with two numerators**: $r = \min(n/(n/l), m/(m/l))$, and stop at $\min(n, m)$ — iterating to $\max$ divides by zero once $m/l = 0$.
2. **Sums of arithmetic progressions overflow** quickly with $n \sim 10^{12}$: halve the even factor of $(l+r)(r-l+1)$ before multiplying (Example 2).
3. **Prefix sums of $\mu$ can be negative** — keep them as signed integers; when reducing mod $p$, add $p$ before `%`.
4. **Skip $d$ with $\mu(d) = 0$** in harmonic loops: about 39% of numbers are not squarefree, a free speed-up.
5. **The $\sum_d\mu(d)\lfloor n/d\rfloor^2$ trick counts ordered pairs** including $(1, 1)$; unordered pairs $i<j$ need $(\text{total} - 1)/2$ (Example 3 uses $\binom{c_d}{2}$ directly instead).
6. **`floor_sum` contract**: $a, b \ge 0$. For negative $a$ or $b$, shift: replace $b$ by $b \bmod m$ and subtract the correction $\lfloor b/m\rfloor n$ yourself (floor division!), similarly for $a$.
7. **`sqrt` with doubles** at $10^{18}$ is off by one regularly; correct with `while (B*B > x) B--; while ((B+1)*(B+1) <= x) B++;`.
8. **Du's sieve memo index**: memoise by $n/v$ (unique for $v > \sqrt n$), not by $v$ — a hash map works but is several times slower.
9. **Java recursion in Du's sieve** is shallow (depth $O(\log n)$), but the presieve of $5\cdot10^6$ `int`s ×3 plus a `boolean[]` is ~65 MB; fine for 256 MB.
10. **Legendre in a loop** `while (n) { n /= p; e += n; }` avoids computing $p^k$ (which overflows for $p^k > 10^{18}$).
11. **Do not name a C++ function `legendre`** (or `beta`, `expint`, `laguerre`, `hermite`, …): C++17 `<cmath>` declares `std::legendre(unsigned, T)` (Legendre *polynomials*), and with `using namespace std;` a call like `legendre(n, 3)` on `int` arguments silently binds to the template — it compiles and returns nonsense.

---

## 7. Going further (toward 2400–2600+)

- **Min_25 sieve** (🔴): prefix sums of multiplicative $f$ with $f(p)$ a low-degree polynomial in $p$, for $n \le 10^{11}$, in roughly $O(n^{3/4}/\log n)$. Two phases: a Lucy-style DP over the $O(\sqrt n)$ values $\lfloor n/k\rfloor$ for sums over primes, then a recursive sum over smallest prime factors.
- **Lucy_Hedgehog prime counting**: $\pi(10^{11})$ in about a second with the same value set.
- **Dirichlet series viewpoint**: $\sum f(n)n^{-s}$; convolution is multiplication, $\zeta(s)^{-1} = \sum\mu(n)n^{-s}$ — the reason every identity above holds.
- **Universal Euclidean algorithm** (🔴): generalises `floor_sum` to $\sum f(\lfloor (ai+b)/m\rfloor)$ with monoid-valued $f$ (sums of $i\cdot\lfloor\cdot\rfloor$, $\lfloor\cdot\rfloor^2$, matrix products).
- **Möbius on other posets**: subsets (inclusion–exclusion), partitions, divisibility — all the same inversion theorem ([inclusion–exclusion §2](../05-Combinatorics-and-Probability/03-inclusion-exclusion.md)); SOS DP computes the subset version fast ([SOS DP](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md)).

---

## 8. Practice ladder

**1400–1900**
- [ ] [AtCoder ABC172 D · Sum of Divisors](https://atcoder.jp/contests/abc172/tasks/abc172_d) — diff≈963
- [ ] [AtCoder ADT_ALL_20260914_1 H · Fraction Floor Sum](https://atcoder.jp/contests/adt_all_20260914_1/tasks/abc230_e) — diff≈969
- [ ] [CF 1485C · Floor and Mod](https://codeforces.com/problemset/problem/1485/C) — 1700
- [ ] [CF 1114C · Trailing Loves (or L'oeufs?)](https://codeforces.com/problemset/problem/1114/C) — 1700
- [ ] [AtCoder ABC162 E · Sum of gcd of Tuples (Hard)](https://atcoder.jp/contests/abc162/tasks/abc162_e) — diff≈1662
- [ ] [AtCoder ABC206 E · Divide Both](https://atcoder.jp/contests/abc206/tasks/abc206_e) — diff≈1745
- [ ] [CSES 1082 · Sum of Divisors](https://cses.fi/problemset/task/1082)
- [ ] [CSES 2417 · Counting Coprime Pairs](https://cses.fi/problemset/task/2417)

**1900–2400**
- [ ] [CF 803F · Coprime Subsequences](https://codeforces.com/problemset/problem/803/F) — 2000
- [ ] [CF 1750D · Count GCD](https://codeforces.com/problemset/problem/1750/D) — 1800
- [ ] [CF 1101D · GCD Counting](https://codeforces.com/problemset/problem/1101/D) — 2000
- [ ] [CF 616E · Sum of Remainders](https://codeforces.com/problemset/problem/616/E) — 2200
- [ ] [CF 839D · Winter is here](https://codeforces.com/problemset/problem/839/D) — 2200
- [ ] [CF 1559E · Mocha and Stars](https://codeforces.com/problemset/problem/1559/E) — 2200
- [ ] [CF 1139D · Steps to One](https://codeforces.com/problemset/problem/1139/D) — 2300
- [ ] [AtCoder PRACTICE2 C · Floor Sum](https://atcoder.jp/contests/practice2/tasks/practice2_c)

**2400+**
- [ ] [CF 1036F · Relatively Prime Powers](https://codeforces.com/problemset/problem/1036/F) — 2400
- [ ] [CF 990G · GCD Counting](https://codeforces.com/problemset/problem/990/G) — 2400
- [ ] [CF 1043F · Make It One](https://codeforces.com/problemset/problem/1043/F) — 2500
- [ ] [CF 1097F · Alex and a TV Show](https://codeforces.com/problemset/problem/1097/F) — 2500
- [ ] [AtCoder ABC230 G · GCD Permutation](https://atcoder.jp/contests/abc230/tasks/abc230_g) — diff≈2516

---

## 9. LeetCode / FAANG cross-reference

Rare in interviews — Möbius inversion and floor blocks are contest-only tools. Related LeetCode problems:
- [LC 172 · Factorial Trailing Zeroes](https://leetcode.com/problems/factorial-trailing-zeroes/) — Medium — Legendre's formula with $p = 5$.
- [LC 1819 · Number of Different Subsequences GCDs](https://leetcode.com/problems/number-of-different-subsequences-gcds/) — Hard — for each $g$, the gcd of all multiples of $g$ present equals $g$? (harmonic loop).
- [LC 2183 · Count Array Pairs Divisible by K](https://leetcode.com/problems/count-array-pairs-divisible-by-k/) — Hard — reduce each number to $\gcd(x, k)$; pairs over divisors of $k$.

---

## 10. Self-check

1. Prove $\sum_{d\mid n}\mu(d) = [n = 1]$.
2. State and prove Möbius inversion using Dirichlet convolution.
3. Derive $\sum_{i,j \le n}[\gcd(i,j)=1] = \sum_d\mu(d)\lfloor n/d\rfloor^2$.
4. Why does $\lfloor n/i\rfloor$ take $O(\sqrt n)$ values, and why is the block end $\lfloor n/\lfloor n/l\rfloor\rfloor$?
5. Derive the axis-swap step of `floor_sum`.
6. How many trailing zeros does $100!$ have? What is $v_2(100!)$ via digit sums?
7. When is $\binom{n}{k}$ odd?
8. Write Du's recurrence for $\Phi(n)$ and explain where $\frac{n(n+1)}{2}$ comes from.

<details><summary>Answers</summary>

1. For $n > 1$ with $k$ distinct primes: $\sum_j\binom kj(-1)^j = 0$; non-squarefree divisors contribute $0$.
2. $g = f * \mathbf 1 \Rightarrow g * \mu = f * (\mathbf 1 * \mu) = f$; converse symmetric.
3. $[\gcd = 1] = \sum_{d\mid i, d\mid j}\mu(d)$; swap: each $d$ is paired with $\lfloor n/d\rfloor^2$ pairs.
4. Indices $\le\sqrt n$ give $\le\sqrt n$ values; larger indices give values $<\sqrt n$. $\lfloor n/i\rfloor \ge q \iff i \le n/q$, so the last index with value $q$ is $\lfloor n/q\rfloor$.
5. Count points by rows $y = 1..Y$: row $y$ has $\lfloor (an + b - my)/a\rfloor$ points; substitute $y = Y - j$ to get $\sum_{j<Y}\lfloor (mj + (an+b-mY))/a\rfloor$.
6. $\lfloor 100/5\rfloor + \lfloor 100/25\rfloor = 24$. $100 = 1100100_2$, $s_2 = 3$: $v_2 = 100 - 3 = 97$.
7. Iff $k$'s binary 1-bits are a subset of $n$'s ($k \mathbin{\&} n = k$): no carries when adding $k$ and $n - k$ (Kummer).
8. $\Phi(n) = \frac{n(n+1)}{2} - \sum_{d=2}^{n}\Phi(\lfloor n/d\rfloor)$; it is $\sum_{i \le n}(\varphi * \mathbf 1)(i) = \sum_{i\le n} i$.

</details>
