# Modular Arithmetic, Fast Exponentiation and Inverses

> **Band:** 🟢 1000 – 🔵 1900 · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [gcd and extended Euclid](01-divisibility-gcd-and-extended-euclid.md), [overflow](../01-Foundations/06-integer-overflow-precision-and-fast-io.md)
> **You can say you know this when:** you can explain why "divide by $b$" means "multiply by $b^{-1}$" and when $b^{-1}$ exists, derive the $O(n)$ inverse table, precompute factorials and inverse factorials in both languages, and compute $a\cdot b \bmod m$ for $m \approx 10^{18}$ without overflow.

---

## 1. First principles — why this works

### 1.1 Why "mod" commutes with $+$, $-$, $\times$

Statements say "print the answer modulo $10^9+7$" because the true answer has millions of digits. We want to reduce *during* the computation, not at the end. That is legal exactly when the final residue does not depend on which representative we carried. Write $a \equiv b \pmod m$ if $m \mid a - b$. If $a = a' + km$ and $b = b' + lm$, then

$$a + b = (a' + b') + (k + l)m, \qquad ab = a'b' + (a'l + b'k + klm)m,$$

so $a + b \equiv a' + b'$ and $ab \equiv a'b'$. Any expression built from $+, -, \times$ can be reduced at every step. This is the statement that the residues $\mathbb{Z}/m\mathbb{Z}$ form a **ring**.

What does *not* survive reduction:
- **Comparisons and floor/max/min** — $10 > 3$ but $10 \bmod 7 = 3$. Never compare reduced values; if a problem needs the true maximum, compare with exact numbers (or logarithms) and reduce only the winner.
- **Exponents** — $a^{e} \not\equiv a^{e \bmod m}$. Exponents live modulo the *order* of $a$, which divides $\varphi(m)$ — see [Euler's theorem](04-euler-phi-fermat-and-euler-theorem.md).
- **Division** — the next paragraph.

### 1.2 Division needs an inverse

"$x = c / b$" means "$x$ is the number with $b x = c$". Modulo $m$ we therefore want $x$ with $bx \equiv c$. If some $u$ satisfies $bu \equiv 1$ (an **inverse** $b^{-1}$), then $x = cu$ works and is unique: $bx \equiv bx' \Rightarrow u b x \equiv u b x' \Rightarrow x \equiv x'$.

When does $u$ exist? $bu \equiv 1 \pmod m$ means $bu + mv = 1$ for some integer $v$ — a Bézout equation. It is solvable **iff $\gcd(b, m) = 1$** ([§1.1 of the gcd file](01-divisibility-gcd-and-extended-euclid.md)). So:
- modulo a prime $p$, every $b \not\equiv 0$ is invertible ($\mathbb{Z}/p\mathbb{Z}$ is a **field**) — this is why contest moduli are prime;
- modulo a composite, only units (numbers coprime to $m$) are invertible; $2 \cdot 3 \equiv 0 \pmod 6$ shows non-units can multiply to $0$, so "cancel $2$" is invalid mod $6$.

Two ways to find $u$: extended Euclid (any $m$, $O(\log m)$), or Fermat's little theorem $b^{p-1} \equiv 1 \Rightarrow b^{-1} \equiv b^{p-2}$ (prime $p$, $O(\log p)$ multiplications).

### 1.3 Fast exponentiation — rediscovered

Computing $a^{e}$ by $e$ multiplications is $10^{18}$ operations. Write $e$ in binary, $e = \sum_i e_i 2^i$; then

$$a^{e} = \prod_{i:\ e_i = 1} a^{2^i}, \qquad a^{2^{i+1}} = \bigl(a^{2^i}\bigr)^2 .$$

Squaring generates $a, a^2, a^4, \dots$ in $\lfloor \log_2 e \rfloor$ steps; multiply in the ones whose bit is set. At most $2\lfloor \log_2 e\rfloor + 1$ multiplications. The same idea works for anything associative — matrices ([matrix exponentiation](../07-DP-Optimizations/08-matrix-exponentiation-for-dp.md)), permutations, polynomial multiplication, and "repeat this operation $e$ times" in general.

### 1.4 Inverses of $1..n$ in linear time — rediscovered

Fermat per element costs $O(n \log p)$. Can we reuse smaller inverses? Divide $p$ by $i$: $p = qi + r$ with $q = \lfloor p/i \rfloor$, $r = p \bmod i < i$. Read it modulo $p$:

$$0 \equiv qi + r \;\Rightarrow\; qi \equiv -r \;\Rightarrow\; i^{-1} \equiv -q\, r^{-1} \pmod p \quad (\text{multiply by } i^{-1} r^{-1}).$$

Since $r < i$, $r^{-1}$ was already computed: $\text{inv}[i] = -\lfloor p/i\rfloor \cdot \text{inv}[p \bmod i]$, $\text{inv}[1] = 1$. $O(n)$ total. ($r \neq 0$ because $p$ is prime and $i < p$.)

The same "reuse" idea gives **batch inversion** of arbitrary numbers $x_1..x_n$: prefix products $P_k = x_1\cdots x_k$, one inverse $P_n^{-1}$, then walk back: $x_k^{-1} = P_n^{-1}\cdot(\text{suffix product after }k)\cdot P_{k-1}$. Concretely: $\text{acc} \leftarrow P_n^{-1}$; for $k = n..1$: $x_k^{-1} = \text{acc}\cdot P_{k-1}$, $\text{acc} \leftarrow \text{acc}\cdot x_k$. One exponentiation plus $3n$ multiplications.

And **inverse factorials**: $(i-1)!^{-1} = i!^{-1}\cdot i$, so after one Fermat call for $n!^{-1}$, walk down. Then $i^{-1} = (i-1)!\cdot i!^{-1}$ comes for free.

---

## 2. Formulas, definitions and identities

### 2.1 Congruence rules

| Rule | Proof sketch / meaning |
|---|---|
| $a \equiv b \pmod m \iff m \mid a - b$ | Definition. Reflexive, symmetric, transitive. |
| $a \equiv a',\ b \equiv b' \Rightarrow a \pm b \equiv a' \pm b',\ ab \equiv a'b'$ | §1.1. |
| $a \equiv b \Rightarrow a^k \equiv b^k$ | Repeated multiplication. Base reduces; **exponent does not**. |
| $ac \equiv bc \pmod m \iff a \equiv b \pmod{m/\gcd(c,m)}$ | $m \mid c(a-b) \iff \frac{m}{g} \mid \frac{c}{g}(a-b) \iff \frac{m}{g} \mid a - b$ (coprime, Euclid's lemma). |
| $a \equiv b \pmod m,\ d \mid m \Rightarrow a \equiv b \pmod d$ | $d \mid m \mid a - b$. |
| $a \equiv b \pmod{m_1}$ and $\pmod{m_2}$ $\iff$ $a \equiv b \pmod{\operatorname{lcm}(m_1, m_2)}$ | Both divide $a-b$ iff the lcm does. Basis of [CRT](05-crt-and-linear-congruences.md). |
| $b^{-1} \bmod m$ exists $\iff \gcd(b, m) = 1$; it is unique mod $m$ | §1.2. |
| $(ab)^{-1} = a^{-1}b^{-1}$, $(a^{-1})^{-1} = a$ | Units form a group. |
| $(a / b) \bmod m$ with $b \mid a$ exactly but $\gcd(b, m) \ne 1$ | Compute $a \bmod (bm)$, then divide by $b$: if $a = bk$, $a \bmod bm = b\,(k \bmod m)$. Needs $bm$ to fit (or `__int128`). |

### 2.2 Inverses

| Method | Formula | Cost | Works when |
|---|---|---|---|
| Fermat | $b^{-1} \equiv b^{p-2} \pmod p$ | $O(\log p)$ | $p$ prime, $p \nmid b$ |
| Euler | $b^{-1} \equiv b^{\varphi(m) - 1} \pmod m$ | $O(\log m)$ + knowing $\varphi(m)$ | $\gcd(b, m) = 1$ |
| Extended Euclid | $bx + my = 1 \Rightarrow b^{-1} = x \bmod m$ | $O(\log m)$ | $\gcd(b,m)=1$, any $m$ |
| Linear table | $\text{inv}[i] = -\lfloor p/i\rfloor\,\text{inv}[p \bmod i]$ | $O(n)$ for $1..n$ | $p$ prime, $n < p$ |
| Batch | prefix products + one inverse | $O(n + \log p)$ | each $x_k$ invertible |
| Via factorials | $i^{-1} = (i-1)!\,(i!)^{-1}$ | $O(1)$ after tables | $i < p$ |

### 2.3 Factorial tables

$$\text{fact}[0] = 1,\quad \text{fact}[i] = i\cdot\text{fact}[i-1]; \qquad \text{ifact}[n] = \text{fact}[n]^{p-2},\quad \text{ifact}[i-1] = i\cdot\text{ifact}[i];$$
$$\binom{n}{k} \equiv \text{fact}[n]\,\text{ifact}[k]\,\text{ifact}[n-k] \pmod p \quad (0 \le k \le n < p).$$

Valid only for $n < p$: $p!$ contains the factor $p \equiv 0$. For $n \ge p$ use Lucas — see [binomials](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md).

### 2.4 Exponentiation facts

| Fact | Note |
|---|---|
| $a^{e}$ in $\le 2\lfloor\log_2 e\rfloor + 1$ multiplications | §1.3. $e = 10^{18}$: about 120 multiplications. |
| $0^0 = 1$ by convention | Binary exponentiation returns 1 for $e = 0$ automatically — check whether the statement agrees. |
| $a^{e} \equiv a^{e \bmod (p-1)} \pmod p$ if $p \nmid a$ | Fermat. If $p \mid a$, the answer is $0$ for $e \ge 1$ — the classic trap in "$a^{b^c}$" (Example 2). |
| $a^{-e} = (a^{-1})^{e}$ | Negative exponents need an inverse. |
| $\sum_{i=0}^{n-1} r^i = \frac{r^n - 1}{r - 1}$ | Needs $(r-1)^{-1}$; for arbitrary $m$ use doubling (Example 4) or compute $r^n \bmod (r-1)m$ and divide (§2.1 last row). |

### 2.5 Representing rationals modulo a prime

The map $\frac{a}{b} \mapsto a\,b^{-1} \bmod p$ (for $p \nmid b$) is well-defined ($\frac{a}{b} = \frac{c}{d} \Rightarrow ad = bc \Rightarrow ab^{-1} \equiv cd^{-1}$) and respects $+$ and $\times$. So **a rational answer can be computed entirely in residues**, even if every intermediate is a fraction — the basis of "print the probability as $P \cdot Q^{-1} \bmod 998244353$". It cannot be decoded back to a fraction in general, and comparisons are meaningless.

### 2.6 Choosing and handling moduli

| Item | Value / rule |
|---|---|
| $10^9 + 7$, $10^9 + 9$ | Primes; $(10^9+7)^2 \approx 1.0\cdot10^{18} < 2^{63} \approx 9.22\cdot10^{18}$, so one product of two reduced values fits in signed 64-bit. |
| $998244353 = 119\cdot 2^{23} + 1$ | Prime, primitive root 3, supports NTT up to length $2^{23}$ ([FFT/NTT](../15-Advanced-Math/03-fft-and-ntt.md)). |
| Sum of products | Reduce after **each** product: $9$ unreduced products already reach $9\cdot10^{18}$. |
| Negative residues | C++/Java `%` keeps the sign of the dividend: `(-7) % 3 == -1`. Normalise with `((x % m) + m) % m`, Java `Math.floorMod(x, m)`. After a subtraction of reduced values, `x - y + m` suffices. |
| 64-bit modulus ($m \le 10^{18}$) | $a\cdot b$ needs 128 bits. C++: `(unsigned __int128)a * b % m`. Java: no 128-bit type — use `Math.multiplyHigh` + reduction, double-and-add (below), or `BigInteger`. |

### 2.7 Faster reduction (🧊)

- **Barrett reduction:** precompute $\mu = \lfloor 2^{k}/m \rfloor$. For $0 \le x < m^2$, $q = \lfloor x\mu / 2^{k}\rfloor$ satisfies $q \le \lfloor x/m \rfloor \le q + 2$, so $x - qm \in [0, 3m)$ needs at most two subtractions. Replaces a hardware division by multiplications and shifts — what AtCoder Library's `barrett` does for runtime moduli.
- **Montgomery multiplication:** for odd $m$, $R = 2^{64}$, precompute $m' = -m^{-1} \bmod R$. Store numbers as $\bar a = aR \bmod m$. $\mathrm{REDC}(T) = (T + (T m' \bmod R)\,m)/R$ is exact division (the numerator is $\equiv 0 \bmod R$ by choice of $m'$), lies in $[0, 2m)$, and is $\equiv TR^{-1}$. Then $\overline{ab} = \mathrm{REDC}(\bar a \bar b)$. No division at all — the fastest 64-bit mulmod, used in serious Miller–Rabin / Pollard rho code.

---

## 3. Implementation (C++ and Java)

```cpp
// Modular toolkit for a fixed prime modulus, plus 64-bit-modulus helpers.
const long long MOD = 1'000'000'007LL;
long long power(long long a, long long e, long long m = MOD) {   // a^e mod m, e >= 0
    long long r = 1 % m;
    a %= m; if (a < 0) a += m;
    while (e > 0) {
        if (e & 1) r = r * a % m;
        a = a * a % m;
        e >>= 1;
    }
    return r;
}
long long inv_fermat(long long a) { return power(a, MOD - 2); }   // MOD prime, a % MOD != 0
long long inv_general(long long a, long long m) {                  // any m; returns -1 if gcd(a, m) != 1
    long long r0 = m, r1 = ((a % m) + m) % m, s0 = 0, s1 = 1;      // invariant: r_i == s_i * a (mod m)
    while (r1) {
        long long q = r0 / r1;
        tie(r0, r1) = make_pair(r1, r0 - q * r1);
        tie(s0, s1) = make_pair(s1, s0 - q * s1);
    }
    if (r0 != 1) return -1;                                         // r0 = gcd(a, m)
    return ((s0 % m) + m) % m;
}
struct Factorials {                       // fact, ifact, inv up to n (n < MOD)
    vector<long long> f, fi, iv;
    explicit Factorials(int n) : f(n + 1), fi(n + 1), iv(n + 1) {
        f[0] = 1;
        for (int i = 1; i <= n; i++) f[i] = f[i - 1] * i % MOD;
        fi[n] = power(f[n], MOD - 2);
        for (int i = n; i >= 1; i--) fi[i - 1] = fi[i] * i % MOD;
        iv[0] = 0;
        for (int i = 1; i <= n; i++) iv[i] = fi[i] * f[i - 1] % MOD;
    }
    long long C(int n, int k) const { return (k < 0 || k > n) ? 0 : f[n] * fi[k] % MOD * fi[n - k] % MOD; }
};
vector<long long> inverse_table(int n) {                          // inv[1..n] in O(n), MOD prime > n
    vector<long long> inv(n + 1, 0);
    if (n >= 1) inv[1] = 1;
    for (int i = 2; i <= n; i++) inv[i] = (MOD - (MOD / i) * inv[MOD % i] % MOD) % MOD;
    return inv;
}
// 64-bit modulus: m up to ~1.8e19 with unsigned __int128
unsigned long long mulmod(unsigned long long a, unsigned long long b, unsigned long long m) {
    return (unsigned __int128)a * b % m;
}
unsigned long long powmod64(unsigned long long a, unsigned long long e, unsigned long long m) {
    unsigned long long r = 1 % m; a %= m;
    for (; e; e >>= 1, a = mulmod(a, a, m)) if (e & 1) r = mulmod(r, a, m);
    return r;
}
```

```java
// Modular toolkit for a fixed prime modulus, plus 64-bit-modulus helpers.
static final long MOD = 1_000_000_007L;
static long power(long a, long e, long m) {          // a^e mod m, e >= 0, m < 2^31.5
    long r = 1 % m;
    a %= m; if (a < 0) a += m;
    while (e > 0) {
        if ((e & 1) == 1) r = r * a % m;
        a = a * a % m;
        e >>= 1;
    }
    return r;
}
static long invFermat(long a) { return power(a, MOD - 2, MOD); }
static long invGeneral(long a, long m) {             // -1 if not invertible
    long r0 = m, r1 = Math.floorMod(a, m), s0 = 0, s1 = 1;
    while (r1 != 0) {
        long q = r0 / r1, t;
        t = r0 - q * r1; r0 = r1; r1 = t;
        t = s0 - q * s1; s0 = s1; s1 = t;
    }
    return r0 == 1 ? Math.floorMod(s0, m) : -1;
}
static long[] fact, ifact, inv;
static void buildFactorials(int n) {
    fact = new long[n + 1]; ifact = new long[n + 1]; inv = new long[n + 1];
    fact[0] = 1;
    for (int i = 1; i <= n; i++) fact[i] = fact[i - 1] * i % MOD;
    ifact[n] = power(fact[n], MOD - 2, MOD);
    for (int i = n; i >= 1; i--) ifact[i - 1] = ifact[i] * i % MOD;
    for (int i = 1; i <= n; i++) inv[i] = ifact[i] * fact[i - 1] % MOD;
}
static long C(int n, int k) { return (k < 0 || k > n) ? 0 : fact[n] * ifact[k] % MOD * ifact[n - k] % MOD; }
static long[] inverseTable(int n) {
    long[] iv = new long[n + 1];
    if (n >= 1) iv[1] = 1;
    for (int i = 2; i <= n; i++) iv[i] = (MOD - (MOD / i) * iv[(int) (MOD % i)] % MOD) % MOD;
    return iv;
}
// 64-bit modulus without overflow: 0 <= a, b < m < 2^63 (double-and-add, ~60 steps)
static long mulmod(long a, long b, long m) {
    long r = 0;
    while (b > 0) {
        if ((b & 1) == 1) r = (r >= m - a) ? r - (m - a) : r + a;   // r + a without overflow
        a = (a >= m - a) ? a - (m - a) : a + a;                      // 2a without overflow
        b >>= 1;
    }
    return r;
}
static long mulmodBig(long a, long b, long m) {       // simplest correct alternative (slower)
    return BigInteger.valueOf(a).multiply(BigInteger.valueOf(b)).mod(BigInteger.valueOf(m)).longValue();
}
static long powmod64(long a, long e, long m) {
    long r = 1 % m; a %= m;
    for (; e > 0; e >>= 1, a = mulmod(a, a, m)) if ((e & 1) == 1) r = mulmod(r, a, m);
    return r;
}
```

C++ contestants often wrap residues in a `Mint` type so that `+ - * /` just work:

```cpp
template <int M> struct Mint {
    int v;
    Mint(long long x = 0) { x %= M; if (x < 0) x += M; v = (int)x; }
    Mint &operator+=(Mint o) { v += o.v; if (v >= M) v -= M; return *this; }
    Mint &operator-=(Mint o) { v -= o.v; if (v < 0) v += M; return *this; }
    Mint &operator*=(Mint o) { v = (int)(1LL * v * o.v % M); return *this; }
    Mint pow(long long e) const { Mint r = 1, a = *this; for (; e; e >>= 1, a *= a) if (e & 1) r *= a; return r; }
    Mint inv() const { return pow(M - 2); }          // M must be prime
    Mint &operator/=(Mint o) { return *this *= o.inv(); }
    friend Mint operator+(Mint a, Mint b) { return a += b; }
    friend Mint operator-(Mint a, Mint b) { return a -= b; }
    friend Mint operator*(Mint a, Mint b) { return a *= b; }
    friend Mint operator/(Mint a, Mint b) { return a /= b; }
    friend bool operator==(Mint a, Mint b) { return a.v == b.v; }
    friend ostream &operator<<(ostream &os, Mint a) { return os << a.v; }
};
using mint = Mint<998244353>;
```

```java
// Java has no operator overloading: keep residues as long and call helpers, e.g.
static final long P = 998244353L;
static long add(long a, long b) { long s = a + b; return s >= P ? s - P : s; }
static long sub(long a, long b) { long s = a - b; return s < 0 ? s + P : s; }
static long mul(long a, long b) { return a * b % P; }
static long div(long a, long b) {                       // a / b mod P
    long r = 1, e = P - 2; b %= P;
    for (; e > 0; e >>= 1, b = b * b % P) if ((e & 1) == 1) r = r * b % P;
    return a * r % P;
}
```

---

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "print modulo $10^9+7$ / $998244353$" | Reduce after every $+,\times$; precompute factorials up to the largest $n$; division → inverse. |
| "the answer is $P/Q$, print $P\cdot Q^{-1}$" | Rational in residues (§2.5); compute probabilities as residues from the start. |
| exponent itself huge ($a^{b^c}$, $a^{n!}$, string exponent) | Reduce the exponent mod $p-1$ (prime, $p \nmid a$) or use generalised Euler ([Euler's theorem](04-euler-phi-fermat-and-euler-theorem.md)). |
| modulus is not prime ($10^9$, $2^{32}$, input $m$) | No Fermat. Inverses only for units, via extended Euclid; consider CRT on prime powers; Pascal's triangle for binomials. |
| modulus up to $10^{18}$ | 128-bit multiplication. |
| $10^5$–$10^7$ inverses needed | Linear table or factorial trick, not $n$ Fermat calls. |
| "repeat operation $k$ times", $k \le 10^{18}$ | Binary exponentiation of the operation (matrix, permutation, function composition). |

Often confused: "mod $p$" in the *answer* (a residue) versus "mod $p$" as a *game rule* (take remainders of real values) — in the second case the true values matter and you may not reduce freely.

---

## 5. Worked examples (graded)

### Example 1 — Exponentiation  ·  ★ ≈1000 (est.)

- **Source:** [CSES 1095 · Exponentiation](https://cses.fi/problemset/task/1095)
- **Difficulty:** ≈1000 (est.)
- **Problem:** $n \le 2\cdot10^5$ queries $(a, b)$ with $0 \le a, b \le 10^9$; print $a^b \bmod 10^9+7$ ($0^0 = 1$).
- **Thinking from first principles:** $b$ multiplications per query is $2\cdot10^{14}$ in total. Binary exponentiation needs $\approx 60$ multiplications per query.

<details><summary>Solution</summary>

Square-and-multiply, $O(n \log b)$. The convention $0^0 = 1$ falls out of starting `r = 1`.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 1'000'000'007LL;
long long power(long long a, long long e) {
    long long r = 1; a %= MOD;
    for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD;
    return r;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    while (n--) { long long a, b; cin >> a >> b; cout << power(a, b) << '\n'; }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long power(long a, long e) {
        long r = 1; a %= MOD;
        for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD;
        return r;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        while (n-- > 0) out.println(power(in.nextLong(), in.nextLong()));
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
3 4
2 8
123 123
out:
81
256
921450052
-->
<!-- test
in:
4
0 0
0 5
1000000000 1000000000
1000000006 3
out:
1
0
312556845
1000000006
-->

### Example 2 — Exponentiation II: $a^{b^c}$  ·  ★ ≈1500 (est.)

- **Source:** [CSES 1712 · Exponentiation II](https://cses.fi/problemset/task/1712)
- **Difficulty:** ≈1500 (est.)
- **Problem:** $n \le 10^5$ queries $(a, b, c)$, $0 \le a, b, c \le 10^9$; print $a^{(b^c)} \bmod p$, $p = 10^9 + 7$.
- **Thinking from first principles:** $b^c$ has up to $9\cdot10^9$ digits — we can only know it modulo something. Reducing it mod $p$ is wrong (exponents are not residues mod $p$). Fermat says $a^{p-1} \equiv 1$ for $p \nmid a$, so the exponent matters only modulo $p - 1$: compute $e = b^c \bmod (p-1)$, then $a^{e} \bmod p$. The trap is $p \mid a$ (here only $a = 0$): then $a^{b^c} = 0$ unless the exponent $b^c$ is exactly $0$, which happens iff $b = 0$ and $c \ge 1$ — but $e = 0$ also arises for $b^c = p - 1$, which must give $0$, not $1$.

<details><summary>Solution</summary>

If $a \bmod p = 0$: answer is $1$ if $b^c = 0$ (i.e. $b = 0$, $c > 0$), else $0$. Otherwise answer $a^{\,b^c \bmod (p-1)} \bmod p$. $O(\log)$ per query.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long P = 1'000'000'007LL;
long long power(long long a, long long e, long long m) {
    long long r = 1 % m; a %= m;
    for (; e; e >>= 1, a = a * a % m) if (e & 1) r = r * a % m;
    return r;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    while (n--) {
        long long a, b, c; cin >> a >> b >> c;
        if (a % P == 0) { cout << ((b == 0 && c > 0) ? 1 : 0) << '\n'; continue; }
        cout << power(a, power(b, c, P - 1), P) << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long P = 1_000_000_007L;
    static long power(long a, long e, long m) {
        long r = 1 % m; a %= m;
        for (; e > 0; e >>= 1, a = a * a % m) if ((e & 1) == 1) r = r * a % m;
        return r;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        while (n-- > 0) {
            long a = in.nextLong(), b = in.nextLong(), c = in.nextLong();
            if (a % P == 0) { out.println((b == 0 && c > 0) ? 1 : 0); continue; }
            out.println(power(a, power(b, c, P - 1), P));
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
3
3 7 1
15 2 2
3 4 5
out:
2187
50625
763327764
-->
<!-- test
in:
6
0 0 5
0 5 0
0 0 0
2 0 0
7 1000000006 1
5 3 0
out:
1
0
0
2
1
5
-->

### Example 3 — Batch inverses with one exponentiation  ·  ★ ≈1500 (est.)

- **Source:** Original problem
- **Difficulty:** ≈1500 (est.)
- **Problem:** $n \le 10^6$ integers $1 \le x_i < p = 998244353$. Print $x_i^{-1} \bmod p$ for each.
- **Thinking from first principles:** $10^6$ Fermat calls are $3\cdot10^7$ multiplications — acceptable in C++, slow-ish in Java, and the idea matters when the inverse is the bottleneck inside a bigger loop. The linear table needs $x_i \le n$, which fails here. Use the prefix-product trick (§1.4): one inverse of the total product, then peel off one factor at a time.

<details><summary>Solution</summary>

$P_k = x_1\cdots x_k$; $\text{acc} = P_n^{-1}$; for $k = n$ down to $1$: $x_k^{-1} = \text{acc}\cdot P_{k-1}$, then $\text{acc} \leftarrow \text{acc}\cdot x_k$ (now $\text{acc} = P_{k-1}^{-1}$). $O(n + \log p)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long P = 998244353;
long long power(long long a, long long e) {
    long long r = 1; a %= P;
    for (; e; e >>= 1, a = a * a % P) if (e & 1) r = r * a % P;
    return r;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<long long> x(n), pre(n + 1, 1), inv(n);
    for (int i = 0; i < n; i++) { cin >> x[i]; pre[i + 1] = pre[i] * x[i] % P; }
    long long acc = power(pre[n], P - 2);                 // (x_1...x_n)^{-1}
    for (int k = n - 1; k >= 0; k--) {
        inv[k] = acc * pre[k] % P;                         // = x_k^{-1}
        acc = acc * x[k] % P;                              // = (x_1...x_{k-1})^{-1}
    }
    for (int i = 0; i < n; i++) cout << inv[i] << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long P = 998244353L;
    static long power(long a, long e) {
        long r = 1; a %= P;
        for (; e > 0; e >>= 1, a = a * a % P) if ((e & 1) == 1) r = r * a % P;
        return r;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long[] x = new long[n], pre = new long[n + 1], inv = new long[n];
        pre[0] = 1;
        for (int i = 0; i < n; i++) { x[i] = in.nextLong(); pre[i + 1] = pre[i] * x[i] % P; }
        long acc = power(pre[n], P - 2);
        for (int k = n - 1; k >= 0; k--) {
            inv[k] = acc * pre[k] % P;
            acc = acc * x[k] % P;
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < n; i++) sb.append(inv[i]).append('\n');
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.print(sb);
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
4
1 2 3 998244352
out:
1
499122177
332748118
998244352
-->
<!-- test
in:
1
123456789
out:
25170271
-->

### Example 4 — Geometric series modulo an arbitrary 64-bit modulus  ·  ★ ≈1900 (est.)

- **Source:** Original problem
- **Difficulty:** ≈1900 (est.)
- **Problem:** $T \le 10^4$ queries $(r, n, m)$ with $0 \le r, n \le 10^{18}$, $1 \le m \le 10^{18}$. Print $\sum_{i=0}^{n-1} r^i \bmod m$ (with $r^0 = 1$).
- **Thinking from first principles:** The closed form $\frac{r^n - 1}{r - 1}$ needs $(r-1)^{-1}$ mod $m$, which does not exist when $\gcd(r-1, m) > 1$ (and $m$ is arbitrary). Avoid division altogether: the pair $(S_k, P_k) = (\sum_{i<k} r^i,\ r^k)$ obeys $S_{2k} = S_k + P_k S_k$, $P_{2k} = P_k^2$, $S_{k+1} = S_k + P_k$, $P_{k+1} = P_k\, r$ — "binary exponentiation of a sum". Every product is of two residues below $10^{18}$, so it needs a 128-bit multiply.

<details><summary>Solution</summary>

Scan the bits of $n$ from the most significant: double, then increment if the bit is set. $O(\log n)$ mulmods per query. C++ uses `unsigned __int128`; Java uses the overflow-free double-and-add `mulmod` from §3 (≈60 additions each), which is fast enough here: $10^4 \cdot 60 \cdot 3 \cdot 60 \approx 10^8$ cheap operations.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ull = unsigned long long;
ull mulmod(ull a, ull b, ull m) { return (unsigned __int128)a * b % m; }
ull geo(ull r, ull n, ull m) {
    ull S = 0, Pk = 1 % m;               // k = 0: empty sum, r^0
    r %= m;
    for (int bit = 63; bit >= 0; bit--) {
        S = (S + mulmod(Pk, S, m)) % m;  // k -> 2k
        Pk = mulmod(Pk, Pk, m);
        if (n >> bit & 1) {              // k -> k + 1
            S = (S + Pk) % m;
            Pk = mulmod(Pk, r, m);
        }
    }
    return S;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int T; cin >> T;
    while (T--) { ull r, n, m; cin >> r >> n >> m; cout << geo(r, n, m) << '\n'; }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long mulmod(long a, long b, long m) {            // 0 <= a, b < m <= 1e18
        long r = 0;
        while (b > 0) {
            if ((b & 1) == 1) r = (r >= m - a) ? r - (m - a) : r + a;
            a = (a >= m - a) ? a - (m - a) : a + a;
            b >>= 1;
        }
        return r;
    }
    static long addmod(long a, long b, long m) { return (a >= m - b) ? a - (m - b) : a + b; }
    static long geo(long r, long n, long m) {
        long S = 0, Pk = 1 % m;
        r %= m;
        for (int bit = 62; bit >= 0; bit--) {
            S = addmod(S, mulmod(Pk, S, m), m);
            Pk = mulmod(Pk, Pk, m);
            if ((n >> bit & 1) == 1) {
                S = addmod(S, Pk, m);
                Pk = mulmod(Pk, r, m);
            }
        }
        return S;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int T = in.nextInt();
        while (T-- > 0) {
            long r = in.nextLong(), n = in.nextLong(), m = in.nextLong();
            out.println(geo(r, n, m));
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
6
2 10 1000
3 5 7
1 1000000000000000000 1000000000000000000
0 5 10
5 0 13
7 3 1
out:
23
2
0
1
0
0
-->
<!-- test
in:
2
999999999999999999 1000000000000000000 999999999999999989
123456789012345678 987654321098765432 1000000000000000000
out:
111111111111
325363800258806395
-->

---

## 6. Tricks, pitfalls and things to remember

1. **`a * b % MOD` with `int` operands overflows before the `%`.** In C++ write `1LL * a * b % MOD`; in Java declare residues as `long`.
2. **Subtraction:** `(a - b) % MOD` can be negative — use `(a - b + MOD) % MOD` for reduced $a, b$.
3. **Never reduce an exponent mod $p$.** Reduce it mod $p - 1$ (Fermat) and only when $p \nmid a$; handle $a \equiv 0$ separately (Example 2).
4. **Factorial tables only work for $n < p$.** With $p = 10^9+7$ that is never an issue for array sizes, but with small primes (e.g. $p = 13$ in a Lucas problem) it is.
5. **Inverse of $0$** silently returns $0$ with Fermat ($0^{p-2} = 0$). If a denominator can be $\equiv 0 \pmod p$, the formula needs restructuring, not an inverse.
6. **Precompute once.** Building factorials to $2\cdot10^6$ costs milliseconds; calling Fermat inside a loop of $10^6$ binomials costs $3\cdot10^7$ extra multiplications.
7. **Java `long` multiplication of two residues below $2^{31.5}$ is safe; below $10^{18}$ it is not.** Use `mulmod` (double-and-add), `Math.multiplyHigh` tricks, or `BigInteger`. C++ has `__int128` but **no `cin`/`cout` for it** — convert to `long long` before printing.
8. **Modulus 1:** `power` must return `1 % m`, not `1`, or answers mod 1 print `1`.
9. **Hashing with a fixed modulus** can be broken by anti-hash tests; choose a random base, or two moduli, or $2^{61}-1$ with 128-bit multiplication — see [string hashing](../11-Strings/01-string-hashing.md).
10. **Division by a small non-coprime number** (e.g. "divide by 2 mod $2^{32}$", "divide by 6 mod $10^9$"): compute modulo $m\cdot d$ and divide exactly at the end (§2.1).

---

## 7. Going further (toward 2400–2600+)

- **Montgomery / Barrett** (§2.7) give 2–4× speed-ups in 64-bit Miller–Rabin and Pollard rho ([next files](06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md)) and in NTT with runtime moduli.
- **Arbitrary-modulus convolution:** three NTT primes + [Garner](05-crt-and-linear-congruences.md) reconstruct exact products modulo any $m$.
- **Modular square roots, discrete logarithms** — [primitive roots file](06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md).
- **$p$-adic / prime-power arithmetic:** computing $n! \bmod p^k$ with $p$-parts removed — [binomials](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md).
- **Lazy reduction** with `unsigned long long` accumulators (add up to 18 products of 30-bit numbers before reducing) is a standard constant-factor trick in matrix multiplication mod $p$.

---

## 8. Practice ladder

**≤ 1400**
- [ ] [CSES 1095 · Exponentiation](https://cses.fi/problemset/task/1095)
- [ ] [CSES 1712 · Exponentiation II](https://cses.fi/problemset/task/1712)
- [ ] [CF 630A · Again Twenty Five!](https://codeforces.com/problemset/problem/630/A) — 800
- [ ] [CF 1514C · Product 1 Modulo N](https://codeforces.com/problemset/problem/1514/C) — 1600
- [ ] [AtCoder ABC156 D · Bouquet](https://atcoder.jp/contests/abc156/tasks/abc156_d) — diff≈1014

**1400–1900**
- [ ] [CF 1312D · Count the Arrays](https://codeforces.com/problemset/problem/1312/D) — 1700
- [ ] [CF 300C · Beautiful Numbers](https://codeforces.com/problemset/problem/300/C) — 1800
- [ ] [CF 1081C · Colorful Bricks](https://codeforces.com/problemset/problem/1081/C) — 1500
- [ ] [CF 327C · Magic Five](https://codeforces.com/problemset/problem/327/C) — 1700
- [ ] [CF 1753B · Factorial Divisibility](https://codeforces.com/problemset/problem/1753/B) — 1600

**1900–2400**
- [ ] [CF 1182E · Product Oriented Recurrence](https://codeforces.com/problemset/problem/1182/E) — 2300
- [ ] [CF 1265E · Beautiful Mirrors](https://codeforces.com/problemset/problem/1265/E) — 2100
- [ ] [CF 1097D · Makoto and a Blackboard](https://codeforces.com/problemset/problem/1097/D) — 2200
- [ ] [CF 1096F · Inversion Expectation](https://codeforces.com/problemset/problem/1096/F) — 2300

---

## 9. LeetCode / FAANG cross-reference

- [LC 50 · Pow(x, n)](https://leetcode.com/problems/powx-n/) — Medium — binary exponentiation with doubles; handle $n = -2^{31}$.
- [LC 372 · Super Pow](https://leetcode.com/problems/super-pow/) — Medium — exponent given as digits; $a^{10e + d} = (a^{e})^{10}\cdot a^{d}$, or reduce the exponent mod $\varphi(1337)$.
- [LC 1922 · Count Good Numbers](https://leetcode.com/problems/count-good-numbers/) — Medium — $5^{\lceil n/2\rceil}4^{\lfloor n/2\rfloor} \bmod (10^9+7)$ with $n \le 10^{15}$.
- [LC 1015 · Smallest Integer Divisible by K](https://leetcode.com/problems/smallest-integer-divisible-by-k/) — Medium — iterate $x \leftarrow (10x + 1) \bmod k$; pigeonhole bounds the loop at $k$.
- [LC 1735 · Count Ways to Make Array With Product](https://leetcode.com/problems/count-ways-to-make-array-with-product/) — Hard — factorials + inverse factorials for stars and bars per prime.
- [LC 1622 · Fancy Sequence](https://leetcode.com/problems/fancy-sequence/) — Hard — maintain a global affine map $x \mapsto ax + b$ and invert it with modular inverses.

---

## 10. Self-check

1. Why is $(a \bmod m)(b \bmod m) \bmod m = ab \bmod m$? Why is the analogous statement false for exponents?
2. When does $b^{-1} \bmod m$ exist? Give two ways to compute it and when each applies.
3. Derive $\text{inv}[i] = -\lfloor p/i\rfloor \cdot \text{inv}[p \bmod i]$.
4. How do you get $n$ inverses of arbitrary numbers with one exponentiation?
5. What is $3^{10^{18}} \bmod 7$? (Use Fermat.)
6. $m = 10^{18}$, $a, b < m$: how do you compute $ab \bmod m$ in C++? In Java?
7. In "$a^{b^c} \bmod p$", what goes wrong if you blindly reduce $b^c$ mod $p-1$ when $a = 0$?
8. How do you compute $\frac{x}{2} \bmod 2^{32}$ when you know $x$ is even?

<details><summary>Answers</summary>

1. $a = a' + km$, $b = b' + lm$ ⇒ $ab - a'b'$ is a multiple of $m$. Exponents: $2^{7} \bmod 5 = 3$ but $2^{7 \bmod 5} = 4$; exponents repeat with the order of the base, not with $m$.
2. Iff $\gcd(b, m) = 1$. Fermat $b^{p-2}$ for prime $p$; extended Euclid for any $m$.
3. $p = qi + r$ ⇒ $qi + r \equiv 0$ ⇒ multiply by $i^{-1}r^{-1}$: $q r^{-1} + i^{-1} \equiv 0$.
4. Prefix products, invert the total, then walk backwards multiplying by $x_k$ (§1.4).
5. $3^6 \equiv 1 \pmod 7$; $10^{18} \bmod 6 = 4$; $3^4 = 81 \equiv 4$.
6. C++: `(unsigned __int128)a * b % m`. Java: double-and-add `mulmod`, `BigInteger`, or `Math.multiplyHigh` with a 128-by-64 reduction.
7. $b^c$ could equal $p - 1$ (reduced to $0$), giving $0^0 = 1$ instead of the correct $0$. Handle $a \equiv 0$ by checking whether $b^c$ is literally $0$.
8. Compute $x \bmod 2^{33}$ and divide by 2 (exact division of the representative).

</details>
