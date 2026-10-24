# Counting Principles and Binomial Coefficients

> **Band:** 🟢 800 – 🟠 2300 · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [modular inverses and factorial tables](../04-Number-Theory/02-modular-arithmetic-and-inverses.md), [recursion and brute force](../01-Foundations/04-recursion-brute-force-and-backtracking.md)
> **You can say you know this when:** you can prove Pascal, Vandermonde and the hockey stick by counting (not algebra), choose the right way to compute $\binom nk$ for any $(n, k, \text{modulus})$ — Pascal, factorials, multiplicative formula, Lucas, prime powers + CRT — and spot a hidden Vandermonde convolution in a counting problem.

---

## 1. First principles — why this works

### 1.1 The three rules every count is built from

- **Sum rule.** If the objects split into disjoint classes, the total is the sum of the class sizes. *Every* "case analysis" is this rule; the art is choosing classes that are disjoint and easy to count.
- **Product rule.** If an object is built by a sequence of choices where the *number* of options at step $i$ is $c_i$ regardless of earlier choices, there are $\prod c_i$ objects. The options may change; only their count must not.
- **Bijection rule.** If you can pair objects of type A with objects of type B one-to-one, $\lvert A\rvert = \lvert B\rvert$. This is the strongest tool: most "clever" counting is finding a bijection to something already counted (stars and bars, Dyck paths, Prüfer codes).

A fourth, **double counting**, counts one set in two ways and equates the answers (e.g. $\sum_v \deg v = 2\lvert E\rvert$ counts (vertex, incident edge) pairs).

### 1.2 Permutations and combinations from the product rule

Ordered selections of $k$ distinct items from $n$: $n(n-1)\cdots(n-k+1) = n^{\underline k} = \frac{n!}{(n-k)!}$ (product rule). An unordered selection (a $k$-subset) corresponds to exactly $k!$ ordered ones (the orderings of its elements), so

$$\binom nk = \frac{n^{\underline k}}{k!} = \frac{n!}{k!\,(n-k)!}.$$

This "divide by the overcount" step is valid only because **every** subset is overcounted by the *same* factor $k!$. When the overcount varies (symmetric objects, repeated letters, necklaces) you need multinomials or [Burnside](05-burnside-and-polya.md) instead.

Repeated letters: arrangements of a multiset with counts $c_1, \dots, c_m$ ($\sum c_i = n$) — label the copies to make them distinct ($n!$ arrangements), and each unlabeled word is hit $\prod c_i!$ times: $\binom{n}{c_1, \dots, c_m} = \frac{n!}{c_1!\cdots c_m!}$.

### 1.3 Identities by counting, not algebra

Each identity below is a statement "these two procedures count the same set":

- **Pascal** $\binom nk = \binom{n-1}{k-1} + \binom{n-1}{k}$: split $k$-subsets of $\lbrace 1..n\rbrace$ by whether they contain $n$.
- **Symmetry** $\binom nk = \binom n{n-k}$: a subset ↔ its complement.
- **Absorption** $k\binom nk = n\binom{n-1}{k-1}$: choose a committee of $k$ with a chair — committee first then chair, or chair first then the other $k - 1$.
- **Binomial theorem** $(x + y)^n = \sum_k \binom nk x^k y^{n-k}$: expanding $n$ factors, a term picks $x$ from exactly $k$ factors — $\binom nk$ ways.
- **Vandermonde** $\sum_i \binom mi\binom n{k-i} = \binom{m+n}{k}$: choose $k$ people from $m$ men and $n$ women, split by the number of men.
- **Hockey stick** $\sum_{i=r}^{n}\binom ir = \binom{n+1}{r+1}$: choose $r + 1$ numbers from $\lbrace 0..n\rbrace$ and condition on the largest one $i$; the other $r$ come from $\lbrace 0..i-1\rbrace$.
- $\sum_k \binom nk = 2^n$ (subsets), $\sum_k k\binom nk = n2^{n-1}$ (subset with a marked element: mark first, then any subset of the rest).

### 1.4 Computing $\binom nk$: pick by the constraints

| Situation | Method | Why it is correct |
|---|---|---|
| $n \le 5000$, **any modulus** (even composite) or exact up to $n = 66$ | Pascal's triangle | Only additions — no division needed. |
| $n < p$, $p$ prime, many queries | factorials + inverse factorials | $k!(n-k)!$ is invertible because all factors are $< p$. |
| $n$ huge ($10^{18}$), $k$ small, $k < p$ | $\prod_{i<k}(n - i)\cdot (k!)^{-1}$ | $\binom nk k! = n^{\underline k}$ is an integer identity; $k!$ is invertible since $k < p$. |
| $n, k$ huge, $p$ small prime | **Lucas** | Below. |
| exact value, fits in 64-bit | multiplicative formula in order | $\binom{n}{i+1} = \binom ni\frac{n - i}{i + 1}$ and every prefix is an integer; use `__int128` for the intermediate product. |
| modulus $p^e$ or composite (🧊) | factorials with $p$ removed + CRT | Below. |

**Lucas's theorem.** Write $n = \sum n_i p^i$, $k = \sum k_i p^i$ in base $p$. Then $\binom nk \equiv \prod_i \binom{n_i}{k_i} \pmod p$.
*Proof idea.* $p \mid \binom pj$ for $0 < j < p$ (the numerator $p!$ has a factor $p$ the denominator lacks), so $(1 + x)^p \equiv 1 + x^p \pmod p$, and by induction $(1+x)^{p^i} \equiv 1 + x^{p^i}$. Hence
$(1 + x)^n = \prod_i (1 + x)^{n_i p^i} \equiv \prod_i (1 + x^{p^i})^{n_i}$. The coefficient of $x^k$ on the right: pick $x^{k_i p^i}$ from the $i$-th factor (in $\binom{n_i}{k_i}$ ways); base-$p$ digits are unique, so there is exactly one way to assemble $k$, giving $\prod\binom{n_i}{k_i}$. ∎ In particular $\binom nk \equiv 0$ iff some digit $k_i > n_i$ — Kummer's carry criterion again ([Möbius file §1.5](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md)).

**Prime powers (🧊).** Write $n! = p^{v_p(n!)}\cdot(n!)_p$ where $(n!)_p$ is the product with all factors $p$ removed. Then $\binom nk \equiv p^{v}\,(n!)_p\,((k!)_p)^{-1}((n-k)!_p)^{-1} \pmod{p^e}$ with $v = v_p(n!) - v_p(k!) - v_p((n-k)!)$ (zero if $v \ge e$); $(m!)_p$ is a unit, so the inverses exist. Grouping $1..m$ into blocks of length $p^e$ gives the recursion $(m!)_p \equiv Q^{\lfloor m/p^e\rfloor}\cdot\prod_{\substack{i \le m \bmod p^e\\ p\nmid i}} i\cdot(\lfloor m/p\rfloor!)_p$, where $Q$ is the product of units below $p^e$ ($\equiv -1$ except for $p = 2$, $e \ge 3$, where it is $1$ — Gauss's generalisation of Wilson). For composite $m$, solve modulo each $p^e \parallel m$ and glue with [CRT](../04-Number-Theory/05-crt-and-linear-congruences.md). This is the Granville-style generalisation of Lucas.

---

## 2. Formulas, definitions and identities

| Formula | Meaning / proof sketch |
|---|---|
| $n^k$ | sequences of length $k$ over $n$ symbols (product rule) |
| $n^{\underline k} = n!/(n-k)!$ | ordered $k$-selections without repetition |
| $\binom nk = n!/(k!(n-k)!)$; $\binom nk = 0$ for $k<0$ or $k>n$ | §1.2 |
| $\binom{n}{c_1,\dots,c_m} = \frac{n!}{\prod c_i!}$ | arrangements of a multiset; multinomial theorem $(x_1+\dots+x_m)^n = \sum\binom{n}{c}\prod x_i^{c_i}$ |
| $(n-1)!$ | circular arrangements of $n$ distinct items (fix one item's position) |
| $\binom nk = \binom{n-1}{k-1} + \binom{n-1}{k}$ | Pascal (§1.3) |
| $\binom nk = \binom n{n-k}$ | complement |
| $k\binom nk = n\binom{n-1}{k-1}$; $\binom nk = \frac nk\binom{n-1}{k-1}$ | absorption |
| $\binom nm\binom mk = \binom nk\binom{n-k}{m-k}$ | trinomial revision: choose $m$ then $k$ inside, or $k$ first then the rest |
| $\sum_k\binom nk = 2^n$; $\sum_k(-1)^k\binom nk = [n = 0]$ | $(1+1)^n$, $(1-1)^n$ |
| $\sum_k k\binom nk = n2^{n-1}$; $\sum_k k(k-1)\binom nk = n(n-1)2^{n-2}$ | absorption twice; derivative of $(1+x)^n$ |
| $\sum_k k^2\binom nk = n(n+1)2^{n-2}$ | $k^2 = k(k-1) + k$ |
| $\sum_{k \text{ even}}\binom nk = \sum_{k\text{ odd}}\binom nk = 2^{n-1}$ ($n\ge1$) | add/subtract the two sums above |
| $\sum_i\binom mi\binom n{k-i} = \binom{m+n}{k}$ | Vandermonde (§1.3); coefficient of $x^k$ in $(1+x)^m(1+x)^n$ |
| $\sum_k\binom nk^2 = \binom{2n}{n}$ | Vandermonde with $m = n$, symmetry |
| $\sum_{i=r}^{n}\binom ir = \binom{n+1}{r+1}$ | hockey stick (§1.3) |
| $\sum_{k=0}^{m}\binom{n+k}{k} = \binom{n+m+1}{m}$ | parallel summation (hockey stick on the other diagonal) |
| $\binom{-n}{k} = (-1)^k\binom{n+k-1}{k}$ | upper negation; $(1-x)^{-n} = \sum_k\binom{n+k-1}{k}x^k$ ([stars and bars](02-stars-and-bars-and-multisets.md)) |
| $\sum_{k}\binom{n-k}{k} = F_{n+1}$ | tilings of a $1\times n$ strip by $k$ dominoes and $n - 2k$ squares |
| $\binom{2n}{n} \sim \frac{4^n}{\sqrt{\pi n}}$; $\binom nk \le \left(\frac{en}{k}\right)^k$ | Stirling's approximation; size estimates |
| exact in signed 64-bit: all $\binom nk$ with $n \le 66$ | $\binom{66}{33} \approx 7.2\cdot10^{18}$, $\binom{67}{33} \approx 1.4\cdot10^{19}$ |
| Lucas: $\binom nk \equiv \prod\binom{n_i}{k_i} \pmod p$ | §1.4 |
| $\binom nk$ odd $\iff k \mathbin{\&} n = k$ | Lucas with $p = 2$ |

**Complexities.** Pascal table: $O(n^2)$ time, $O(n)$ memory per row. Factorial tables: $O(N + \log p)$ precompute, $O(1)$ per query. Multiplicative formula: $O(k)$. Lucas: $O(p)$ precompute, $O(\log_p n)$ per query. Prime-power method: $O(p^e)$ precompute, $O(\log_p n\cdot\log n)$ per query.

---

## 3. Implementation (C++ and Java)

```cpp
// Factorial-table binomials, Pascal mod any m, small-k big-n binomial, Lucas, and nCr mod p^e (prime power).
const long long MOD = 1'000'000'007LL;
long long power(long long a, long long e, long long m) { long long r = 1 % m; a %= m; for (; e; e >>= 1, a = a * a % m) if (e & 1) r = r * a % m; return r; }
struct Binom {
    vector<long long> f, fi;
    explicit Binom(int n) : f(n + 1), fi(n + 1) {
        f[0] = 1;
        for (int i = 1; i <= n; i++) f[i] = f[i - 1] * i % MOD;
        fi[n] = power(f[n], MOD - 2, MOD);
        for (int i = n; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
    }
    long long C(int n, int k) const { return (k < 0 || k > n) ? 0 : f[n] * fi[k] % MOD * fi[n - k] % MOD; }
    long long P(int n, int k) const { return (k < 0 || k > n) ? 0 : f[n] * fi[n - k] % MOD; }
};
vector<vector<long long>> pascal(int n, long long m) {        // C[i][j] mod m, any m >= 1
    vector<vector<long long>> C(n + 1, vector<long long>(n + 1, 0));
    for (int i = 0; i <= n; i++) {
        C[i][0] = 1 % m;
        for (int j = 1; j <= i; j++) C[i][j] = (C[i - 1][j - 1] + C[i - 1][j]) % m;
    }
    return C;
}
long long binom_big_n(long long n, long long k, long long p) { // k < p, p prime, n arbitrary (>= 0)
    if (k < 0 || k > n) return 0;
    long long num = 1, den = 1;
    for (long long i = 0; i < k; i++) { num = num * ((n - i) % p) % p; den = den * ((i + 1) % p) % p; }
    return num * power(den, p - 2, p) % p;
}
long long lucas(long long n, long long k, long long p, const vector<long long> &f, const vector<long long> &fi) {
    long long r = 1;                                            // f, fi: factorials mod p up to p - 1
    while (n > 0 || k > 0) {
        long long ni = n % p, ki = k % p;
        if (ki > ni) return 0;
        r = r * f[ni] % p * fi[ki] % p * fi[ni - ki] % p;
        n /= p; k /= p;
    }
    return r;
}
// C(n, k) mod p^e, n up to 1e18, p^e up to ~1e6 (table of size p^e)
struct BinomPrimePower {
    long long p, e, pe; vector<long long> unitProd;             // unitProd[i] = prod of j <= i, p does not divide j, mod pe
    BinomPrimePower(long long p_, long long e_) : p(p_), e(e_), pe(1) {
        for (int i = 0; i < e; i++) pe *= p;
        unitProd.assign(pe + 1, 1);
        for (long long i = 1; i <= pe; i++) unitProd[i] = (i % p == 0) ? unitProd[i - 1] : unitProd[i - 1] * (i % pe) % pe;
    }
    long long fact_p(long long n) const {                       // n! with all factors p removed, mod pe
        if (n == 0) return 1 % pe;
        return power(unitProd[pe], n / pe, pe) * unitProd[n % pe] % pe * fact_p(n / p) % pe;
    }
    static long long vp_fact(long long n, long long p) { long long v = 0; while (n) { n /= p; v += n; } return v; }
    long long inv(long long a) const {                          // a is a unit mod pe: extended Euclid
        long long r0 = pe, r1 = a % pe, s0 = 0, s1 = 1;
        while (r1) { long long q = r0 / r1; tie(r0, r1) = make_pair(r1, r0 - q * r1); tie(s0, s1) = make_pair(s1, s0 - q * s1); }
        return ((s0 % pe) + pe) % pe;
    }
    long long C(long long n, long long k) const {
        if (k < 0 || k > n) return 0;
        long long v = vp_fact(n, p) - vp_fact(k, p) - vp_fact(n - k, p);
        if (v >= e) return 0;
        long long r = fact_p(n) * inv(fact_p(k)) % pe * inv(fact_p(n - k)) % pe;
        for (int i = 0; i < v; i++) r = r * p % pe;
        return r;
    }
};
```

```java
// Factorial-table binomials, Pascal mod any m, small-k big-n binomial, Lucas, and nCr mod p^e (prime power).
static final long MOD = 1_000_000_007L;
static long power(long a, long e, long m) { long r = 1 % m; a %= m; for (; e > 0; e >>= 1, a = a * a % m) if ((e & 1) == 1) r = r * a % m; return r; }
static long[] fact, ifact;
static void buildBinom(int n) {
    fact = new long[n + 1]; ifact = new long[n + 1]; fact[0] = 1;
    for (int i = 1; i <= n; i++) fact[i] = fact[i - 1] * i % MOD;
    ifact[n] = power(fact[n], MOD - 2, MOD);
    for (int i = n; i > 0; i--) ifact[i - 1] = ifact[i] * i % MOD;
}
static long C(int n, int k) { return (k < 0 || k > n) ? 0 : fact[n] * ifact[k] % MOD * ifact[n - k] % MOD; }
static long[][] pascal(int n, long m) {
    long[][] c = new long[n + 1][n + 1];
    for (int i = 0; i <= n; i++) {
        c[i][0] = 1 % m;
        for (int j = 1; j <= i; j++) c[i][j] = (c[i - 1][j - 1] + c[i - 1][j]) % m;
    }
    return c;
}
static long binomBigN(long n, long k, long p) {
    if (k < 0 || k > n) return 0;
    long num = 1, den = 1;
    for (long i = 0; i < k; i++) { num = num * ((n - i) % p) % p; den = den * ((i + 1) % p) % p; }
    return num * power(den, p - 2, p) % p;
}
static long lucas(long n, long k, long p, long[] f, long[] fi) {
    long r = 1;
    while (n > 0 || k > 0) {
        int ni = (int) (n % p), ki = (int) (k % p);
        if (ki > ni) return 0;
        r = r * f[ni] % p * fi[ki] % p * fi[ni - ki] % p;
        n /= p; k /= p;
    }
    return r;
}
static final class BinomPrimePower {
    final long p, e; long pe = 1; final long[] unitProd;
    BinomPrimePower(long p, long e) {
        this.p = p; this.e = e;
        for (int i = 0; i < e; i++) pe *= p;
        unitProd = new long[(int) pe + 1]; unitProd[0] = 1;
        for (int i = 1; i <= pe; i++) unitProd[i] = (i % p == 0) ? unitProd[i - 1] : unitProd[i - 1] * (i % pe) % pe;
    }
    long factP(long n) { return n == 0 ? 1 % pe : power(unitProd[(int) pe], n / pe, pe) * unitProd[(int) (n % pe)] % pe * factP(n / p) % pe; }
    static long vpFact(long n, long p) { long v = 0; while (n > 0) { n /= p; v += n; } return v; }
    long inv(long a) {
        long r0 = pe, r1 = a % pe, s0 = 0, s1 = 1;
        while (r1 != 0) { long q = r0 / r1, t = r0 - q * r1; r0 = r1; r1 = t; t = s0 - q * s1; s0 = s1; s1 = t; }
        return Math.floorMod(s0, pe);
    }
    long C(long n, long k) {
        if (k < 0 || k > n) return 0;
        long v = vpFact(n, p) - vpFact(k, p) - vpFact(n - k, p);
        if (v >= e) return 0;
        long r = factP(n) * inv(factP(k)) % pe * inv(factP(n - k)) % pe;
        for (int i = 0; i < v; i++) r = r * p % pe;
        return r;
    }
}
```

---

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "choose", "select a subset", "number of ways to pick $k$" | $\binom nk$ — but check whether order matters and whether repetition is allowed (the [twelvefold way](02-stars-and-bars-and-multisets.md)) |
| grid paths with right/down moves | $\binom{a+b}{a}$; with obstacles → [inclusion–exclusion DP](03-inclusion-exclusion.md) |
| "distinct permutations of a string / multiset" | multinomial |
| a sum $\sum_i \binom{a}{i}\binom{b}{c-i}$ appears after a first derivation | collapse with Vandermonde (Example 5) |
| a sum $\sum_i \binom{i}{r}$ over a range | hockey stick |
| $n \le 10^9$ or $10^{18}$ but $k \le 10^6$ | multiplicative formula (Example 3) |
| modulus small prime (e.g. 13, 10007) | Lucas (Example 4) |
| modulus composite, given as input | Pascal (small $n$) or prime powers + CRT (🧊) |
| parity of $\binom nk$, "how many odd entries in row $n$" | $k \subseteq n$ bitwise; $2^{\text{popcount}(n)}$ |

---

## 5. Worked examples (graded)

### Example 1 — Binomial Coefficients  ·  ★ ≈1300 (est.)

- **Source:** [CSES 1079 · Binomial Coefficients](https://cses.fi/problemset/task/1079)
- **Difficulty:** ≈1300 (est.)
- **Problem:** $n \le 10^5$ queries $(a, b)$ with $0 \le b \le a \le 10^6$: print $\binom ab \bmod 10^9+7$.
- **Thinking from first principles:** Pascal's triangle up to $10^6$ is $10^{12}$ cells. The closed form needs division, which modulo a prime is multiplication by an inverse; all factors are $< p$, so factorials and inverse factorials up to $10^6$ (one exponentiation total) answer each query with three multiplications.

<details><summary>Solution</summary>

Precompute `fact` and `ifact` (§3), answer $f[a]\,fi[b]\,fi[a-b]$. $O(N + n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 1'000'000'007LL;
long long power(long long a, long long e) { long long r = 1; a %= MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    const int N = 1'000'000;
    vector<long long> f(N + 1), fi(N + 1);
    f[0] = 1;
    for (int i = 1; i <= N; i++) f[i] = f[i - 1] * i % MOD;
    fi[N] = power(f[N], MOD - 2);
    for (int i = N; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
    int n; cin >> n;
    while (n--) { int a, b; cin >> a >> b; cout << f[a] * fi[b] % MOD * fi[a - b] % MOD << '\n'; }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long power(long a, long e) { long r = 1; a %= MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
    public static void main(String[] args) throws IOException {
        final int N = 1_000_000;
        long[] f = new long[N + 1], fi = new long[N + 1];
        f[0] = 1;
        for (int i = 1; i <= N; i++) f[i] = f[i - 1] * i % MOD;
        fi[N] = power(f[N], MOD - 2);
        for (int i = N; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        while (n-- > 0) { int a = in.nextInt(), b = in.nextInt(); out.println(f[a] * fi[b] % MOD * fi[a - b] % MOD); }
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
3
5 3
8 1
9 5
out:
10
8
126
-->
<!-- test
in:
3
0 0
1000000 500000
1000000 1000000
out:
1
996692777
1
-->

### Example 2 — Creating Strings II (multinomial)  ·  ★ ≈1400 (est.)

- **Source:** [CSES 1715 · Creating Strings II](https://cses.fi/problemset/task/1715)
- **Difficulty:** ≈1400 (est.)
- **Problem:** A string of length $n \le 10^6$ over `a`–`z`. Count distinct strings obtainable by rearranging its letters, modulo $10^9+7$.
- **Thinking from first principles:** Make the equal letters distinguishable by labels: $n!$ arrangements. Erasing labels maps exactly $\prod c_i!$ labelled arrangements to each word (permute labels within each letter class), so the count is $n!/\prod c_i!$ — the multinomial coefficient.

<details><summary>Solution</summary>

Count letters, multiply $n!$ by the inverse factorials of the counts. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 1'000'000'007LL;
long long power(long long a, long long e) { long long r = 1; a %= MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
int main() {
    string s; cin >> s;
    int n = s.size();
    vector<long long> f(n + 1), fi(n + 1);
    f[0] = 1;
    for (int i = 1; i <= n; i++) f[i] = f[i - 1] * i % MOD;
    fi[n] = power(f[n], MOD - 2);
    for (int i = n; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
    array<int, 26> c{};
    for (char ch : s) c[ch - 'a']++;
    long long ans = f[n];
    for (int x : c) ans = ans * fi[x] % MOD;
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long power(long a, long e) { long r = 1; a %= MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        String s = br.readLine().trim();
        int n = s.length();
        long[] f = new long[n + 1], fi = new long[n + 1];
        f[0] = 1;
        for (int i = 1; i <= n; i++) f[i] = f[i - 1] * i % MOD;
        fi[n] = power(f[n], MOD - 2);
        for (int i = n; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
        int[] c = new int[26];
        for (int i = 0; i < n; i++) c[s.charAt(i) - 'a']++;
        long ans = f[n];
        for (int x : c) ans = ans * fi[x] % MOD;
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
aabac
out:
20
-->
<!-- test
in:
z
out:
1
-->
<!-- test
in:
abcdefghij
out:
3628800
-->

### Example 3 — Bouquet (huge $n$, small $k$)  ·  ★ ≈1100 (est.)

- **Source:** [AtCoder ABC156 D · Bouquet](https://atcoder.jp/contests/abc156/tasks/abc156_d)
- **Difficulty:** ≈1100 (est.; AtCoder Problems diff ≈1014)
- **Problem:** $n \le 10^9$ distinct flowers; count non-empty subsets whose size is neither $a$ nor $b$ ($1 \le a < b \le \min(n, 2\cdot10^5)$), modulo $10^9+7$.
- **Thinking from first principles:** All non-empty subsets: $2^n - 1$; subtract the forbidden sizes: $\binom na + \binom nb$. A factorial table to $10^9$ is too big, but $k \le 2\cdot10^5$: $\binom nk = n^{\underline k}/k!$ needs only $k$ factors (§1.4).

<details><summary>Solution</summary>

$2^n$ by fast power, each binomial by the multiplicative formula in $O(k)$. Watch the subtraction mod $p$.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 1'000'000'007LL;
long long power(long long a, long long e) { long long r = 1; a %= MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
long long binom_big_n(long long n, long long k) {
    long long num = 1, den = 1;
    for (long long i = 0; i < k; i++) { num = num * ((n - i) % MOD) % MOD; den = den * (i + 1) % MOD; }
    return num * power(den, MOD - 2) % MOD;
}
int main() {
    long long n, a, b; cin >> n >> a >> b;
    long long ans = (power(2, n) - 1 - binom_big_n(n, a) - binom_big_n(n, b)) % MOD;
    cout << (ans + 2 * MOD) % MOD << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long power(long a, long e) { long r = 1; a %= MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
    static long binomBigN(long n, long k) {
        long num = 1, den = 1;
        for (long i = 0; i < k; i++) { num = num * ((n - i) % MOD) % MOD; den = den * (i + 1) % MOD; }
        return num * power(den, MOD - 2) % MOD;
    }
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        long n = Long.parseLong(st.nextToken()), a = Long.parseLong(st.nextToken()), b = Long.parseLong(st.nextToken());
        long ans = (power(2, n) - 1 - binomBigN(n, a) - binomBigN(n, b)) % MOD;
        System.out.println((ans + 2 * MOD) % MOD);
    }
}
```

</details>

<!-- test
in:
4 1 3
out:
7
-->
<!-- test
in:
1000000000 141421 173205
out:
34076506
-->
<!-- test
in:
3 1 2
out:
1
-->

### Example 4 — Binomials modulo a small prime (Lucas)  ·  ★ ≈1900 (est.)

- **Source:** Original problem
- **Difficulty:** ≈1900 (est.)
- **Problem:** A prime $p \le 10^5$ and $T \le 10^5$ queries $0 \le k \le n \le 10^{18}$: print $\binom nk \bmod p$.
- **Thinking from first principles:** Factorial tables fail: $n! \equiv 0 \pmod p$ once $n \ge p$, and the "inverse" of $0$ does not exist — the $p$-factors in numerator and denominator must cancel *before* reducing. Lucas does this digit by digit: $\binom nk \equiv \prod\binom{n_i}{k_i}$ over base-$p$ digits, each digit binomial having arguments $< p$, where factorial tables are valid.

<details><summary>Solution</summary>

Tables of $i!$ and $(i!)^{-1}$ for $i < p$; per query at most $\log_p n + 1 \le 61$ digit binomials. $O(p + T\log_p n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
ll power(ll a, ll e, ll m) { ll r = 1 % m; a %= m; for (; e; e >>= 1, a = a * a % m) if (e & 1) r = r * a % m; return r; }
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    ll p; int T; cin >> p >> T;
    vector<ll> f(p), fi(p);
    f[0] = 1;
    for (ll i = 1; i < p; i++) f[i] = f[i - 1] * i % p;
    fi[p - 1] = power(f[p - 1], p - 2, p);
    for (ll i = p - 1; i > 0; i--) fi[i - 1] = fi[i] * i % p;
    while (T--) {
        ll n, k; cin >> n >> k;
        ll r = 1;
        while ((n > 0 || k > 0) && r) {
            ll ni = n % p, ki = k % p;
            r = (ki > ni) ? 0 : r * f[ni] % p * fi[ki] % p * fi[ni - ki] % p;
            n /= p; k /= p;
        }
        cout << r << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long power(long a, long e, long m) { long r = 1 % m; a %= m; for (; e > 0; e >>= 1, a = a * a % m) if ((e & 1) == 1) r = r * a % m; return r; }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        long p = in.nextLong(); int T = in.nextInt();
        long[] f = new long[(int) p], fi = new long[(int) p];
        f[0] = 1;
        for (int i = 1; i < p; i++) f[i] = f[i - 1] * i % p;
        fi[(int) p - 1] = power(f[(int) p - 1], p - 2, p);
        for (int i = (int) p - 1; i > 0; i--) fi[i - 1] = fi[i] * i % p;
        while (T-- > 0) {
            long n = in.nextLong(), k = in.nextLong(), r = 1;
            while ((n > 0 || k > 0) && r != 0) {
                int ni = (int) (n % p), ki = (int) (k % p);
                r = (ki > ni) ? 0 : r * f[ni] % p * fi[ki] % p * fi[ni - ki] % p;
                n /= p; k /= p;
            }
            out.println(r);
        }
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
7 5
10 3
7 1
6 3
49 7
100 50
out:
1
0
6
0
4
-->
<!-- test
in:
2 4
5 2
7 3
1000000000000000000 0
1000000000000000000 999999999999999999
out:
0
1
1
0
-->
<!-- test
in:
99991 3
1000000000000000000 500000000000000000
123456789123456789 987654321
99990 45000
out:
0
3299
1
-->

### Example 5 — Anton and School - 2 (hidden Vandermonde)  ·  ★ 2300

- **Source:** [CF 785D · Anton and School - 2](https://codeforces.com/problemset/problem/785/D) — 2300
- **Difficulty:** 2300
- **Problem:** A bracket string of length $\le 2\cdot10^5$. Count its subsequences (by positions) of the form $(^k)^k$ for $k \ge 1$, modulo $10^9+7$.
- **Thinking from first principles:** Classify each valid subsequence by **its last opening bracket** (sum rule; every such subsequence has exactly one). If that bracket is at position $i$, with $L$ opening brackets at or before $i$ and $R$ closing brackets after $i$, we choose $k - 1$ more openers from the $L - 1$ before $i$ and $k$ closers from the $R$ after: $\sum_{k\ge1}\binom{L-1}{k-1}\binom Rk$. Rewrite $\binom{L-1}{k-1} = \binom{L-1}{L-k}$; the sum is $\sum_k\binom{L-1}{L-k}\binom{R}{k}$, a Vandermonde convolution (indices add to $L$): it equals $\binom{L-1+R}{L}$. So each opener contributes one binomial.

<details><summary>Solution</summary>

Precompute prefix counts of `(` and suffix counts of `)`; sum $\binom{L + R - 1}{L}$ over openers. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 1'000'000'007LL;
long long power(long long a, long long e) { long long r = 1; a %= MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
int main() {
    string s; cin >> s;
    int n = s.size();
    vector<long long> f(n + 1), fi(n + 1);
    f[0] = 1;
    for (int i = 1; i <= n; i++) f[i] = f[i - 1] * i % MOD;
    fi[n] = power(f[n], MOD - 2);
    for (int i = n; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
    auto C = [&](int a, int b) -> long long { return (b < 0 || b > a) ? 0 : f[a] * fi[b] % MOD * fi[a - b] % MOD; };
    vector<int> closeAfter(n + 1, 0);
    for (int i = n - 1; i >= 0; i--) closeAfter[i] = closeAfter[i + 1] + (s[i] == ')');
    long long ans = 0; int L = 0;
    for (int i = 0; i < n; i++) {
        if (s[i] != '(') continue;
        L++;
        int R = closeAfter[i + 1];
        if (R > 0) ans = (ans + C(L + R - 1, L)) % MOD;
    }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long power(long a, long e) { long r = 1; a %= MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
    public static void main(String[] args) throws IOException {
        String s = new BufferedReader(new InputStreamReader(System.in)).readLine().trim();
        int n = s.length();
        long[] f = new long[n + 1], fi = new long[n + 1];
        f[0] = 1;
        for (int i = 1; i <= n; i++) f[i] = f[i - 1] * i % MOD;
        fi[n] = power(f[n], MOD - 2);
        for (int i = n; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
        int[] closeAfter = new int[n + 1];
        for (int i = n - 1; i >= 0; i--) closeAfter[i] = closeAfter[i + 1] + (s.charAt(i) == ')' ? 1 : 0);
        long ans = 0; int L = 0;
        for (int i = 0; i < n; i++) {
            if (s.charAt(i) != '(') continue;
            L++;
            int R = closeAfter[i + 1];
            if (R > 0) ans = (ans + f[L + R - 1] * fi[L] % MOD * fi[R - 1]) % MOD;
        }
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
)(()()
out:
6
-->
<!-- test
in:
()()()
out:
7
-->
<!-- test
in:
)))
out:
0
-->
<!-- test
in:
((()))(())
out:
66
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Size the factorial table for the largest argument actually used** — in Example 5 that is $L + R - 1 \le n$; in stars and bars it is $n + k - 1$. An off-by-one here is an out-of-bounds read, not a WA.
2. **Return 0 for $k < 0$ or $k > n$** in `C(n, k)`; many formulas (Vandermonde, IE) rely on it.
3. **Factorials mod $p$ are useless for $n \ge p$** — with small primes use Lucas; with composite moduli use Pascal or prime powers + CRT.
4. **"Exact" binomials overflow fast**: $\binom{67}{33}$ already exceeds `long long`. For exact values above that, use `__int128` (to $n \approx 130$) or big integers.
5. **The multiplicative formula must alternate multiply and divide** (`r = r * (n - i) / (i + 1)`) to stay integral; dividing at the end overflows.
6. **Dividing by the overcount** is only valid when every object is overcounted equally. Necklaces, symmetric shapes and "unordered pairs with possible equality" break it.
7. **Subtracting mod $p$**: `(a - b - c) % MOD` can be as low as $-2p$; add `2 * MOD` (Example 3).
8. **Java `long[]` of size $10^6$** is 8 MB per table — fine; `BigInteger` binomials are far too slow for loops.
9. **Recursion in `fact_p`** has depth $\log_p n$ — harmless.

---

## 7. Going further (toward 2400–2600+)

- **Prime-power binomials + CRT** (§1.4, code in §3) give $\binom nk \bmod m$ for any $m$ — rarely needed but decisive when it is.
- **Generating functions**: Vandermonde is coefficient extraction from $(1+x)^m(1+x)^n$; most identities become one-line GF manipulations — [polynomials and GFs](../15-Advanced-Math/04-polynomials-and-generating-functions.md).
- **Binomial sums with a moving parameter** ($\sum_{i\le m}\binom ni$ for many $(n, m)$) — maintain them with Pascal steps under Mo's algorithm ([Mo's algorithm](../08-Data-Structures/07-sqrt-decomposition-and-mos-algorithm.md)).
- **Lattice paths with constraints**: reflection principle ([Catalan](04-catalan-stirling-bell-and-partitions.md)), LGV lemma for non-intersecting paths ([LGV](../15-Advanced-Math/06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md)).
- **Kummer/Lucas structure**: counting $k$ with $\binom nk$ not divisible by $p$ is $\prod (n_i + 1)$ over base-$p$ digits.

---

## 8. Practice ladder

**≤ 1400**
- [ ] [CSES 1079 · Binomial Coefficients](https://cses.fi/problemset/task/1079)
- [ ] [CSES 1715 · Creating Strings II](https://cses.fi/problemset/task/1715)
- [ ] [CF 630C · Lucky Numbers](https://codeforces.com/problemset/problem/630/C) — 1100
- [ ] [CF 459B · Pashmak and Flowers](https://codeforces.com/problemset/problem/459/B) — 1300
- [ ] [CF 478B · Random Teams](https://codeforces.com/problemset/problem/478/B) — 1300
- [ ] [CF 1594E1 · Rubik's Cube Coloring (easy version)](https://codeforces.com/problemset/problem/1594/E1) — 1300
- [ ] [AtCoder ABC156 D · Bouquet](https://atcoder.jp/contests/abc156/tasks/abc156_d) — diff≈1014
- [ ] [AtCoder ABC145 D · Knight](https://atcoder.jp/contests/abc145/tasks/abc145_d) — diff≈1009

**1400–1900**
- [ ] [CF 1236B · Alice and the List of Presents](https://codeforces.com/problemset/problem/1236/B) — 1500
- [ ] [CF 1081C · Colorful Bricks](https://codeforces.com/problemset/problem/1081/C) — 1500
- [ ] [CF 1391C · Cyclic Permutations ](https://codeforces.com/problemset/problem/1391/C) — 1500
- [ ] [CF 131C · The World is a Theatre](https://codeforces.com/problemset/problem/131/C) — 1400
- [ ] [CF 1312D · Count the Arrays](https://codeforces.com/problemset/problem/1312/D) — 1700
- [ ] [CF 300C · Beautiful Numbers](https://codeforces.com/problemset/problem/300/C) — 1800
- [ ] [CF 869C · The Intriguing Obsession](https://codeforces.com/problemset/problem/869/C) — 1800

**1900–2400**
- [ ] [CF 1696E · Placing Jinas](https://codeforces.com/problemset/problem/1696/E) — 2000
- [ ] [CF 1761D · Carry Bit](https://codeforces.com/problemset/problem/1761/D) — 2100
- [ ] [CF 1606E · Arena](https://codeforces.com/problemset/problem/1606/E) — 2100
- [ ] [CF 785D · Anton and School - 2](https://codeforces.com/problemset/problem/785/D) — 2300
- [ ] [CF 1832E · Combinatorics Problem](https://codeforces.com/problemset/problem/1832/E) — 2200

---

## 9. LeetCode / FAANG cross-reference

- [LC 62 · Unique Paths](https://leetcode.com/problems/unique-paths/) — Medium — $\binom{m+n-2}{m-1}$; the DP is Pascal's rule.
- [LC 118 · Pascal's Triangle](https://leetcode.com/problems/pascals-triangle/) — Easy / [LC 119 · Pascal's Triangle II](https://leetcode.com/problems/pascals-triangle-ii/) — Easy — one row in $O(k)$ space by updating right to left.
- [LC 1641 · Count Sorted Vowel Strings](https://leetcode.com/problems/count-sorted-vowel-strings/) — Medium — $\binom{n+4}{4}$ (multisets).
- [LC 357 · Count Numbers with Unique Digits](https://leetcode.com/problems/count-numbers-with-unique-digits/) — Medium — falling factorials $9\cdot 9^{\underline{k-1}}$.
- [LC 1359 · Count All Valid Pickup and Delivery Options](https://leetcode.com/problems/count-all-valid-pickup-and-delivery-options/) — Hard — $(2n)!/2^n$ (each pair's order is forced).
- [LC 2221 · Find Triangular Sum of an Array](https://leetcode.com/problems/find-triangular-sum-of-an-array/) — Medium — answer is $\sum\binom{n-1}{i}a_i \bmod 10$ (Lucas mod 2 and 5 + CRT for large $n$).
- [LC 1569 · Number of Ways to Reorder Array to Get Same BST](https://leetcode.com/problems/number-of-ways-to-reorder-array-to-get-same-bst/) — Hard — interleavings of subtrees: $\binom{L+R}{L}$ recursively.

Interviewers like $\binom nk$ via Pascal (no modular inverses); mention the factorial method only when a modulus is given.

---

## 10. Self-check

1. Prove Pascal's rule and the hockey-stick identity by counting.
2. Why is dividing by $k!$ valid for subsets but not for necklaces?
3. Derive $\sum_k k\binom nk = n2^{n-1}$ two ways.
4. When must you use Lucas instead of factorial tables? Compute $\binom{10}{3} \bmod 7$ by Lucas.
5. How do you compute $\binom{10^{18}}{5} \bmod 10^9+7$?
6. What is the largest $n$ for which all $\binom nk$ fit in signed 64-bit?
7. Rewrite $\sum_{k}\binom{a}{k-1}\binom{b}{k}$ as a single binomial.
8. How many entries of row $n = 100$ of Pascal's triangle are odd?

<details><summary>Answers</summary>

1. Pascal: classify $k$-subsets by containing $n$ or not. Hockey stick: classify $(r+1)$-subsets of $\lbrace 0..n\rbrace$ by their maximum.
2. Every $k$-subset corresponds to exactly $k!$ ordered lists; a necklace with rotational symmetry corresponds to fewer than $n$ rotations, so the overcount is not uniform.
3. Absorption: $k\binom nk = n\binom{n-1}{k-1}$, sum to $n2^{n-1}$. Or differentiate $(1+x)^n$ and set $x = 1$.
4. When $n \ge p$. $10 = 13_7$, $3 = 03_7$: $\binom 10\binom 33 = 1$.
5. $\frac{n(n-1)(n-2)(n-3)(n-4)}{5!}$ with each factor reduced mod $p$ and $5!$ inverted.
6. $n = 66$.
7. $\sum_k\binom{a}{a-k+1}\binom bk = \binom{a+b}{a+1}$ (Vandermonde, indices add to $a+1$).
8. $100 = 1100100_2$ has 3 ones: $2^3 = 8$.

</details>
