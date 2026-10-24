# Orders, Primitive Roots, Discrete Log, Miller–Rabin and Pollard's Rho

> **Band:** 🟣 1900 – 🔴 2700 · **Priority:** ⚡ (Miller–Rabin, BSGS, primitive roots) · 🧊 (Tonelli–Shanks, non-coprime discrete log) · **FAANG:** none · **Prerequisites:** [Euler's theorem](04-euler-phi-fermat-and-euler-theorem.md), [64-bit mulmod](02-modular-arithmetic-and-inverses.md), [sieves](03-sieves-and-factorization.md)
> **You can say you know this when:** you can test primality of any 64-bit number deterministically, factor $10^{18}$-sized numbers with Pollard–Brent, find a primitive root, solve $a^x \equiv b \pmod m$ (including $\gcd(a,m) > 1$), and take square roots modulo a prime.

---

## 1. First principles — why this works

### 1.1 Order: the period of powers

For a unit $a$ mod $n$, the sequence $a^0, a^1, a^2, \dots$ lives in a finite set, so it repeats; since multiplication by $a$ is invertible it is *purely* periodic. The period is the **order** $\operatorname{ord}_n(a)$ = smallest $k \ge 1$ with $a^k \equiv 1$. Two facts follow from the division algorithm:

- $a^{e} \equiv 1 \iff \operatorname{ord}(a) \mid e$ (write $e = q\cdot\operatorname{ord} + r$; then $a^{r} \equiv 1$ with $r < \operatorname{ord}$ forces $r = 0$);
- hence $\operatorname{ord}(a) \mid \varphi(n)$ (Euler).

**Computing the order** without trying all exponents: start from $k = \varphi(n)$ and, for each prime $q \mid \varphi(n)$, divide $k$ by $q$ while $a^{k/q} \equiv 1$. What remains is the order. Cost: $O(\omega(\varphi)\cdot\log\varphi\cdot\log n)$, given the factorisation of $\varphi(n)$.

### 1.2 Primitive roots: when the group is cyclic

A **primitive root** $g$ has order exactly $\varphi(n)$; then $g^0, \dots, g^{\varphi(n)-1}$ are all the units, and every unit has a unique **index** (discrete logarithm) $\operatorname{ind}_g(a) \in [0, \varphi(n))$. Multiplication becomes addition of indices modulo $\varphi(n)$ — the reason primitive roots unlock $k$-th roots, NTT, and "multiplicative to additive" reductions.

**Existence modulo a prime $p$ (proof).** Let $\psi(d)$ be the number of units of order $d$; it is non-zero only for $d \mid p - 1$.
1. Over the field $\mathbb{Z}/p$, a polynomial of degree $d$ has at most $d$ roots (factor theorem: each root $r$ splits off a factor $x - r$, and a field has no zero divisors).
2. If some $a$ has order $d$, then $1, a, \dots, a^{d-1}$ are $d$ distinct roots of $x^d - 1$ — therefore *all* of them. The elements of order exactly $d$ among them are $a^j$ with $\gcd(j, d) = 1$: so $\psi(d) \in \lbrace 0, \varphi(d)\rbrace$, in particular $\psi(d) \le \varphi(d)$.
3. Every unit has some order: $\sum_{d \mid p-1}\psi(d) = p - 1 = \sum_{d \mid p-1}\varphi(d)$ ([§1.4 of the totient file](04-euler-phi-fermat-and-euler-theorem.md)). With termwise $\psi \le \varphi$, equality holds everywhere: $\psi(p - 1) = \varphi(p-1) \ge 1$. ∎

More generally a primitive root mod $n$ exists **iff $n \in \lbrace 1, 2, 4, p^k, 2p^k\rbrace$** ($p$ odd prime). Why not others: if $n = ab$ with coprime $a, b > 2$, both $\varphi(a), \varphi(b)$ are even, and every unit satisfies $x^{\operatorname{lcm}(\varphi(a), \varphi(b))} \equiv 1$ with $\operatorname{lcm} < \varphi(a)\varphi(b)$; and mod $2^k$ ($k \ge 3$) every odd square is $1 \bmod 8$, so orders are at most $2^{k-2}$.

**Finding one.** $g$ is a primitive root iff $g^{\varphi/q} \not\equiv 1$ for every prime $q \mid \varphi$ (if the order were a proper divisor, it would divide some $\varphi/q$). There are $\varphi(\varphi(n))$ primitive roots — a constant fraction up to $\log\log$ factors — so testing $g = 2, 3, 4, \dots$ succeeds quickly (3 for 998244353, 5 for $10^9+7$).

### 1.3 Discrete logarithm by baby-step giant-step

Solve $a^x \equiv b \pmod m$, $\gcd(a, m) = 1$. Brute force tries $x = 0..\operatorname{ord}(a) - 1$, up to $m$ steps. **Meet in the middle**: with $n = \lceil\sqrt m\,\rceil$ write $x = in - j$, $1 \le i \le n$, $0 \le j < n$. Then

$$a^{x} \equiv b \iff (a^{n})^{i} \equiv b\,a^{j}.$$

Store all $b\,a^j$ ("baby steps") in a hash map, then walk the "giant steps" $(a^n)^i$ and look each up. $O(\sqrt m)$ time and memory. To get the **smallest** $x$, take the first $i$ that hits and, for that value, the largest $j$.

**Non-coprime case (🧊).** If $g = \gcd(a, m) > 1$: either $b$ equals the current prefix product (answer found at a small $x$), or $g \mid b$ is required; divide the congruence $a\cdot a^{x-1} \equiv b$ by $g$: $\frac{a}{g}a^{x-1} \equiv \frac{b}{g} \pmod{\frac{m}{g}}$, increasing a counter. After at most $\log_2 m$ such steps $\gcd(a, m') = 1$ and we solve $C\cdot a^{y} \equiv b' \pmod{m'}$ with BSGS (start the giant steps from $C$). The answer is $y$ + counter.

### 1.4 Square roots and Euler's criterion

With a primitive root $g$, $a = g^t$ is a square iff $t$ is even, so exactly half the units are **quadratic residues**. Since $g^{(p-1)/2}$ is a square root of $1$ other than $1$, it equals $-1$, and

$$a^{(p-1)/2} = g^{t(p-1)/2} = (-1)^{t} \quad\Longrightarrow\quad a^{(p-1)/2} \equiv \left(\frac{a}{p}\right) \in \lbrace 1, -1\rbrace \pmod p \qquad\text{(Euler's criterion).}$$

If $p \equiv 3 \pmod 4$, $r = a^{(p+1)/4}$ works directly: $r^2 = a^{(p+1)/2} = a \cdot a^{(p-1)/2} = a$. In general **Tonelli–Shanks** (🧊): write $p - 1 = q 2^s$ with $q$ odd, pick a non-residue $z$, and keep the invariant $R^2 \equiv a\,t$ where $t$ has order $2^{i}$ dividing $2^{M}$, and $c$ has order exactly $2^{M}$. Start $R = a^{(q+1)/2}$, $t = a^q$, $c = z^q$, $M = s$. While $t \ne 1$: find the least $i$ with $t^{2^i} = 1$; set $b = c^{2^{M-i-1}}$, then $R \leftarrow Rb$, $t \leftarrow tb^2$, $c \leftarrow b^2$, $M \leftarrow i$. Multiplying $t$ by $b^2$ (order $2^{i}$) cancels its top bit of order, so the order of $t$ strictly drops; at most $s$ rounds, $O(\log^2 p)$.

### 1.5 Primality: from Fermat to Miller–Rabin

Fermat's test ("$a^{n-1} \equiv 1$?") is fooled by **Carmichael numbers** such as $561 = 3\cdot11\cdot17$, for which $a^{560} \equiv 1$ for every coprime $a$. The fix uses one more fact true only for primes: **modulo a prime, $x^2 \equiv 1$ has only the roots $\pm 1$** (§1.2, degree-2 polynomial). Write $n - 1 = 2^s d$ with $d$ odd and look at the chain $a^d, a^{2d}, a^{4d}, \dots, a^{2^s d} = a^{n-1}$: each term is the square of the previous. For prime $n$ the chain ends in $1$, and the first $1$ must be preceded by $-1$ (or the chain starts at $1$). So $n$ is a **strong probable prime to base $a$** iff

$$a^{d} \equiv 1 \quad\text{or}\quad a^{2^r d} \equiv -1 \ \text{ for some } 0 \le r < s.$$

A composite passes for at most $1/4$ of bases (Rabin). For $n < 2^{64}$ the bases $\lbrace 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37\rbrace$ are **deterministic** (no composite below $3.3\cdot10^{24}$ passes all of them); for $n < 4\,759\,123\,141$ (covers 32-bit) $\lbrace 2, 7, 61\rbrace$ suffices. Cost: 12 modular exponentiations ≈ 1500 64-bit mulmods.

### 1.6 Factoring: Pollard's rho

Let $p$ be an unknown prime factor of $n$. Iterate a pseudo-random map $x \mapsto f(x) = x^2 + c \bmod n$. Reduced mod $p$, the sequence lives in a set of size $p$, so by the **birthday paradox** two terms collide mod $p$ after about $\sqrt{\pi p/2}$ steps, after which the sequence mod $p$ is periodic (its picture is the letter ρ). We cannot see residues mod $p$, but a collision $x_i \equiv x_j \pmod p$ makes $p \mid x_i - x_j$, so $\gcd(\lvert x_i - x_j\rvert, n) > 1$ reveals it — usually a proper factor, because a collision mod $n$ itself is far less likely.

- **Cycle detection.** Floyd compares $x_i$ with $x_{2i}$. **Brent** compares with $x_{2^k}$ (saved at powers of two) — fewer evaluations of $f$.
- **Batching.** Multiply up to ~128 differences modulo $n$ and take one gcd; if the batch gcd is $n$, back up and redo that batch one step at a time.
- **Cost.** With $p \le \sqrt n$ the expected work is $O(n^{1/4})$ mulmods: $\approx 3\cdot10^4$ steps for $n = 10^{18}$.

Full factorisation: if $n$ is prime (Miller–Rabin) stop; otherwise split $n = d\cdot(n/d)$ by rho and recurse.

---

## 2. Formulas, definitions and identities

| Statement | Proof sketch / meaning |
|---|---|
| $a^{e} \equiv 1 \iff \operatorname{ord}(a) \mid e$; $\operatorname{ord}(a) \mid \varphi(n)$ | Division algorithm (§1.1). |
| $\operatorname{ord}(a^k) = \operatorname{ord}(a)/\gcd(k, \operatorname{ord}(a))$ | $(a^k)^e = 1 \iff \operatorname{ord}(a) \mid ke \iff \frac{\operatorname{ord}}{\gcd} \mid e$. |
| In a cyclic group of order $N$, exactly $\varphi(d)$ elements have order $d$, for each $d \mid N$ | Powers $g^{jN/d}$, $\gcd(j, d) = 1$. |
| Primitive root exists mod $n$ $\iff n \in \lbrace 1,2,4,p^k,2p^k\rbrace$; count $\varphi(\varphi(n))$ | §1.2. |
| $g$ primitive $\iff g^{\varphi(n)/q} \ne 1$ for every prime $q \mid \varphi(n)$ | §1.2. |
| A primitive root mod $p$ that is also primitive mod $p^2$ is primitive mod all $p^k$; if $g$ fails mod $p^2$, $g + p$ works | Standard lifting lemma (🧊). |
| $x^k \equiv a \pmod p$ solvable $\iff a^{(p-1)/\gcd(k, p-1)} \equiv 1$; then $\gcd(k, p-1)$ solutions | Indices: $k\cdot\operatorname{ind}(x) \equiv \operatorname{ind}(a) \pmod{p-1}$ is a linear congruence. |
| Euler's criterion $a^{(p-1)/2} \equiv \left(\frac{a}{p}\right)$ | §1.4. |
| $\left(\frac{-1}{p}\right) = (-1)^{(p-1)/2}$, $\left(\frac{2}{p}\right) = (-1)^{(p^2-1)/8}$ | Criterion for $-1$; Gauss's lemma for $2$ (🧊). |
| Quadratic reciprocity $\left(\frac{p}{q}\right)\left(\frac{q}{p}\right) = (-1)^{\frac{p-1}{2}\frac{q-1}{2}}$ (🧊) | Lets you compute Legendre/Jacobi symbols in $O(\log)$ like gcd. |
| $p \equiv 3 \pmod 4$: $\sqrt a = a^{(p+1)/4}$ | §1.4. |
| Wilson / Fermat / Carmichael: 561, 1105, 1729 are Carmichael | Fermat test is unsafe. |
| Strong pseudoprime test; deterministic 64-bit bases = first 12 primes | §1.5. |
| BSGS: $x = in - j$, $n = \lceil\sqrt m\rceil$; $O(\sqrt m)$ | §1.3. |
| Pollard rho: expected $O(\sqrt p) = O(n^{1/4})$ steps | Birthday paradox (§1.6). |

---

## 3. Implementation (C++ and Java)

The C++ version uses `unsigned __int128` for products. Java has no 128-bit integer, so the Java version uses **Montgomery multiplication** (built on `Math.unsignedMultiplyHigh`, Java 18+) — about as fast as the C++ code. Montgomery needs an odd modulus; Miller–Rabin and rho only call it on odd $n$.

```cpp
// 64-bit Miller–Rabin, Pollard–Brent rho, factorisation, primitive root, BSGS (general), Tonelli–Shanks.
using u64 = unsigned long long;
using u128 = unsigned __int128;
u64 mulmod(u64 a, u64 b, u64 m) { return (u128)a * b % m; }
u64 powmod(u64 a, u64 e, u64 m) {
    u64 r = 1 % m; a %= m;
    for (; e; e >>= 1, a = mulmod(a, a, m)) if (e & 1) r = mulmod(r, a, m);
    return r;
}
bool is_prime(u64 n) {
    if (n < 2) return false;
    for (u64 p : {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37}) if (n % p == 0) return n == p;
    u64 d = n - 1; int s = 0;
    while (d % 2 == 0) { d /= 2; s++; }
    for (u64 a : {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37}) {
        u64 x = powmod(a, d, n);
        if (x == 1 || x == n - 1) continue;
        bool comp = true;
        for (int r = 1; r < s && comp; r++) { x = mulmod(x, x, n); if (x == n - 1) comp = false; }
        if (comp) return false;
    }
    return true;
}
u64 pollard_brent(u64 n) {                       // n composite; returns a non-trivial factor
    if (n % 2 == 0) return 2;
    static mt19937_64 rng(0x5eed);
    while (true) {
        u64 c = rng() % (n - 1) + 1, y = rng() % n, x = y, ys = y, q = 1, g = 1;
        auto f = [&](u64 v) { return (mulmod(v, v, n) + c) % n; };
        const int BATCH = 128;
        for (u64 r = 1; g == 1; r <<= 1) {
            x = y;                                // x = value at the last power of two
            for (u64 i = 0; i < r; i++) y = f(y);
            for (u64 k = 0; k < r && g == 1; k += BATCH) {
                ys = y;
                for (u64 i = 0; i < BATCH && i < r - k; i++) { y = f(y); q = mulmod(q, x > y ? x - y : y - x, n); }
                g = std::gcd(q, n);
            }
        }
        if (g == n) {                             // batch overshot: redo it step by step
            g = 1;
            while (g == 1) { ys = f(ys); g = std::gcd(x > ys ? x - ys : ys - x, n); }
        }
        if (g != n) return g;                     // otherwise retry with a new c
    }
}
void factor_rec(u64 n, vector<u64> &out) {
    if (n == 1) return;
    if (is_prime(n)) { out.push_back(n); return; }
    for (u64 p : {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37})
        if (n % p == 0) { out.push_back(p); factor_rec(n / p, out); return; }
    u64 d = pollard_brent(n);
    factor_rec(d, out); factor_rec(n / d, out);
}
vector<u64> factorize(u64 n) { vector<u64> f; factor_rec(n, f); sort(f.begin(), f.end()); return f; }
u64 primitive_root(u64 p) {                      // p prime
    if (p == 2) return 1;
    vector<u64> f = factorize(p - 1);
    f.erase(unique(f.begin(), f.end()), f.end());
    for (u64 g = 2;; g++) {
        bool ok = true;
        for (u64 q : f) if (powmod(g, (p - 1) / q, p) == 1) { ok = false; break; }
        if (ok) return g;
    }
}
long long discrete_log(long long a, long long b, long long m) {   // smallest x >= 0 with a^x == b (mod m), or -1
    a %= m; b %= m;
    if (m == 1) return 0;
    long long k = 1 % m, add = 0, g;
    while ((g = std::gcd(a, m)) > 1) {
        if (b == k) return add;
        if (b % g) return -1;
        b /= g; m /= g; add++;
        k = (__int128)k * (a / g) % m;
    }
    long long n = (long long)sqrtl((long double)m) + 1, an = 1;
    for (long long i = 0; i < n; i++) an = (__int128)an * a % m;
    unordered_map<long long, long long> baby;
    baby.reserve(2 * n);
    for (long long j = 0, cur = b; j <= n; j++) { baby[cur] = j; cur = (__int128)cur * a % m; }  // keeps largest j
    for (long long i = 1, cur = k; i <= n; i++) {
        cur = (__int128)cur * an % m;
        auto it = baby.find(cur);
        if (it != baby.end()) return n * i - it->second + add;
    }
    return -1;
}
long long sqrt_mod(long long a, long long p) {   // p prime; a root r (r*r == a), or -1
    a %= p; if (a < 0) a += p;
    if (a == 0 || p == 2) return a;
    if (powmod(a, (p - 1) / 2, p) != 1) return -1;
    if (p % 4 == 3) return powmod(a, (p + 1) / 4, p);
    long long q = p - 1; int s = 0;
    while (q % 2 == 0) { q /= 2; s++; }
    long long z = 2;
    while (powmod(z, (p - 1) / 2, p) != (u64)(p - 1)) z++;
    long long M = s, c = powmod(z, q, p), t = powmod(a, q, p), R = powmod(a, (q + 1) / 2, p);
    while (t != 1) {
        long long i = 0, tt = t;
        while (tt != 1) { tt = mulmod(tt, tt, p); i++; }
        long long b = c;
        for (long long j = 0; j < M - i - 1; j++) b = mulmod(b, b, p);
        M = i; c = mulmod(b, b, p); t = mulmod(t, c, p); R = mulmod(R, b, p);
    }
    return R;
}
```

```java
// 64-bit Miller–Rabin and Pollard–Brent with Montgomery multiplication, primitive root, BSGS, Tonelli–Shanks.
static final class Mont {                       // odd modulus n < 2^63
    final long n, nInv, r2;                     // nInv = -n^{-1} mod 2^64, r2 = 2^128 mod n
    Mont(long n) {
        this.n = n;
        long inv = n;                           // correct to 3 bits for odd n
        for (int i = 0; i < 5; i++) inv *= 2 - n * inv;   // Newton: 3 -> 6 -> ... -> 96 bits
        nInv = -inv;
        r2 = BigInteger.ONE.shiftLeft(128).mod(BigInteger.valueOf(n)).longValue();
    }
    long reduce(long hi, long lo) {             // (hi*2^64 + lo) / 2^64 mod n, needs hi < n
        long m = lo * nInv;
        long t = hi + Math.unsignedMultiplyHigh(m, n) + (lo != 0 ? 1 : 0);
        return Long.compareUnsigned(t, n) >= 0 ? t - n : t;
    }
    long mul(long a, long b) { return reduce(Math.unsignedMultiplyHigh(a, b), a * b); }
    long to(long a) { return mul(Long.remainderUnsigned(a, n), r2); }
    long from(long a) { return reduce(0, a); }
    long pow(long aM, long e) {                 // aM in Montgomery form, e >= 0
        long r = to(1);
        for (; e > 0; e >>= 1, aM = mul(aM, aM)) if ((e & 1) == 1) r = mul(r, aM);
        return r;
    }
}
static final long[] BASES = {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37};
static boolean isPrime(long n) {                // 0 <= n < 2^63
    if (n < 2) return false;
    for (long p : BASES) if (n % p == 0) return n == p;
    Mont M = new Mont(n);
    long d = n - 1; int s = Long.numberOfTrailingZeros(d); d >>= s;
    long one = M.to(1), minusOne = M.to(n - 1);
    for (long a : BASES) {
        long x = M.pow(M.to(a), d);
        if (x == one || x == minusOne) continue;
        boolean comp = true;
        for (int r = 1; r < s && comp; r++) { x = M.mul(x, x); if (x == minusOne) comp = false; }
        if (comp) return false;
    }
    return true;
}
static long gcd(long a, long b) { while (b != 0) { long t = a % b; a = b; b = t; } return a; }
static final SplittableRandom RNG = new SplittableRandom(0x5eed);
static long pollardBrent(long n) {             // n odd composite
    Mont M = new Mont(n);
    while (true) {
        long c = M.to(1 + RNG.nextLong(n - 1)), y = M.to(RNG.nextLong(n)), x = y, ys = y, q = M.to(1), g = 1;
        for (long r = 1; g == 1; r <<= 1) {
            x = y;
            for (long i = 0; i < r; i++) { y = M.mul(y, y) + c; if (y >= n) y -= n; }
            for (long k = 0; k < r && g == 1; k += 128) {
                ys = y;
                for (long i = 0; i < 128 && i < r - k; i++) {
                    y = M.mul(y, y) + c; if (y >= n) y -= n;
                    q = M.mul(q, x > y ? x - y : y - x);
                }
                g = gcd(q, n);                  // gcd(vR mod n, n) = gcd(v, n): Montgomery form is fine
            }
        }
        if (g == n) {
            g = 1;
            while (g == 1) { ys = M.mul(ys, ys) + c; if (ys >= n) ys -= n; g = gcd(x > ys ? x - ys : ys - x, n); }
        }
        if (g != n) return g;
    }
}
static void factorRec(long n, List<Long> out) {
    if (n == 1) return;
    if (isPrime(n)) { out.add(n); return; }
    for (long p : BASES) if (n % p == 0) { out.add(p); factorRec(n / p, out); return; }
    long d = pollardBrent(n);
    factorRec(d, out); factorRec(n / d, out);
}
static List<Long> factorize(long n) { List<Long> f = new ArrayList<>(); factorRec(n, f); Collections.sort(f); return f; }
static long powmod(long a, long e, long m) {   // m < 2^31 version for small moduli
    long r = 1 % m; a %= m;
    for (; e > 0; e >>= 1, a = a * a % m) if ((e & 1) == 1) r = r * a % m;
    return r;
}
static long discreteLog(long a, long b, long m) {   // m <= ~2e9
    a %= m; b %= m;
    if (m == 1) return 0;
    long k = 1 % m, add = 0, g;
    while ((g = gcd(a, m)) > 1) {
        if (b == k) return add;
        if (b % g != 0) return -1;
        b /= g; m /= g; add++;
        k = k * (a / g) % m;
    }
    long n = (long) Math.sqrt((double) m) + 1, an = 1;
    for (long i = 0; i < n; i++) an = an * a % m;
    HashMap<Long, Long> baby = new HashMap<>();
    for (long j = 0, cur = b; j <= n; j++) { baby.put(cur, j); cur = cur * a % m; }
    for (long i = 1, cur = k; i <= n; i++) {
        cur = cur * an % m;
        Long j = baby.get(cur);
        if (j != null) return n * i - j + add;
    }
    return -1;
}
static long sqrtMod(long a, long p) {           // p prime < 2^31
    a = Math.floorMod(a, p);
    if (a == 0 || p == 2) return a;
    if (powmod(a, (p - 1) / 2, p) != 1) return -1;
    if (p % 4 == 3) return powmod(a, (p + 1) / 4, p);
    long q = p - 1; int s = 0;
    while (q % 2 == 0) { q /= 2; s++; }
    long z = 2;
    while (powmod(z, (p - 1) / 2, p) != p - 1) z++;
    long M = s, c = powmod(z, q, p), t = powmod(a, q, p), R = powmod(a, (q + 1) / 2, p);
    while (t != 1) {
        long i = 0, tt = t;
        while (tt != 1) { tt = tt * tt % p; i++; }
        long b = c;
        for (long j = 0; j < M - i - 1; j++) b = b * b % p;
        M = i; c = b * b % p; t = t * c % p; R = R * b % p;
    }
    return R;
}
```

---

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "is $n$ prime", $n \le 10^{18}$ | Miller–Rabin with the 12 fixed bases |
| factor numbers up to $10^{18}$; "number of divisors of $n \le 10^{18}$" | Pollard–Brent (or the cube-root trick from [sieves](03-sieves-and-factorization.md)) |
| $a^x \equiv b$, unknown exponent | BSGS; if the modulus is prime and many queries share the base, precompute baby steps once |
| $x^k \equiv a \pmod p$ | primitive root + discrete log + linear congruence on the index |
| "$\sqrt{a} \bmod p$", "is $a$ a square mod $p$" | Euler's criterion; Tonelli–Shanks |
| multiplicative structure mod a prime ("product of a subset ≡ $x$") | take indices w.r.t. a primitive root: products become sums mod $p-1$ (knapsack / convolution) |
| period of $a^k$, "smallest $k$ with $a^k \equiv 1$" | order via factorisation of $\varphi$ |
| NTT with a new prime | need a primitive root of that prime |

---

## 5. Worked examples (graded)

### Example 1 — Next prime after a 64-bit number  ·  ★ ≈1900 (est.)

- **Source:** Original problem (a larger-range version of [CSES 3396 · Next Prime](https://cses.fi/problemset/task/3396))
- **Difficulty:** ≈1900 (est.)
- **Problem:** $T \le 1000$ queries $1 \le n \le 10^{18}$: print the smallest prime $> n$.
- **Thinking from first principles:** Prime gaps below $10^{18}$ are at most 1442 and about $\ln 10^{18} \approx 41$ on average ([sieves §2.2](03-sieves-and-factorization.md)), so scanning $n+1, n+2, \dots$ needs a fast exact primality test — trial division is $10^9$ per candidate. Miller–Rabin with the deterministic base set costs ~1500 mulmods per prime candidate, and most composites die at the first base (or at the small-prime check).

<details><summary>Solution</summary>

Scan upward with `is_prime`. Expected $O(T\cdot\ln n\cdot\log n)$ mulmods.

```cpp
#include <bits/stdc++.h>
using namespace std;
using u64 = unsigned long long;
u64 mulmod(u64 a, u64 b, u64 m) { return (unsigned __int128)a * b % m; }
u64 powmod(u64 a, u64 e, u64 m) {
    u64 r = 1 % m; a %= m;
    for (; e; e >>= 1, a = mulmod(a, a, m)) if (e & 1) r = mulmod(r, a, m);
    return r;
}
bool is_prime(u64 n) {
    if (n < 2) return false;
    for (u64 p : {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37}) if (n % p == 0) return n == p;
    u64 d = n - 1; int s = 0;
    while (d % 2 == 0) { d /= 2; s++; }
    for (u64 a : {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37}) {
        u64 x = powmod(a, d, n);
        if (x == 1 || x == n - 1) continue;
        bool comp = true;
        for (int r = 1; r < s && comp; r++) { x = mulmod(x, x, n); if (x == n - 1) comp = false; }
        if (comp) return false;
    }
    return true;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int T; cin >> T;
    while (T--) {
        u64 n; cin >> n;
        u64 x = n + 1;
        while (!is_prime(x)) x++;
        cout << x << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;
import java.math.BigInteger;

public class Main {
    static final class Mont {
        final long n, nInv, r2;
        Mont(long n) {
            this.n = n;
            long inv = n;
            for (int i = 0; i < 5; i++) inv *= 2 - n * inv;
            nInv = -inv;
            r2 = BigInteger.ONE.shiftLeft(128).mod(BigInteger.valueOf(n)).longValue();
        }
        long reduce(long hi, long lo) {
            long m = lo * nInv;
            long t = hi + Math.unsignedMultiplyHigh(m, n) + (lo != 0 ? 1 : 0);
            return Long.compareUnsigned(t, n) >= 0 ? t - n : t;
        }
        long mul(long a, long b) { return reduce(Math.unsignedMultiplyHigh(a, b), a * b); }
        long to(long a) { return mul(Long.remainderUnsigned(a, n), r2); }
        long pow(long aM, long e) {
            long r = to(1);
            for (; e > 0; e >>= 1, aM = mul(aM, aM)) if ((e & 1) == 1) r = mul(r, aM);
            return r;
        }
    }
    static final long[] BASES = {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37};
    static boolean isPrime(long n) {
        if (n < 2) return false;
        for (long p : BASES) if (n % p == 0) return n == p;
        Mont M = new Mont(n);
        long d = n - 1; int s = Long.numberOfTrailingZeros(d); d >>= s;
        long one = M.to(1), minusOne = M.to(n - 1);
        for (long a : BASES) {
            long x = M.pow(M.to(a), d);
            if (x == one || x == minusOne) continue;
            boolean comp = true;
            for (int r = 1; r < s && comp; r++) { x = M.mul(x, x); if (x == minusOne) comp = false; }
            if (comp) return false;
        }
        return true;
    }
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int T = Integer.parseInt(br.readLine().trim());
        StringBuilder sb = new StringBuilder();
        while (T-- > 0) {
            long x = Long.parseLong(br.readLine().trim()) + 1;
            while (!isPrime(x)) x++;
            sb.append(x).append('\n');
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
5
1
2
10
560
1000000000
out:
2
3
11
563
1000000007
-->
<!-- test
in:
3
1000000000000000000
999999999999999989
436273009
out:
1000000000000000003
1000000000000000003
436273291
-->

### Example 2 — Factor numbers up to $10^{18}$  ·  ★ ≈2300 (est.)

- **Source:** Original problem
- **Difficulty:** ≈2300 (est.)
- **Problem:** $T \le 100$ numbers $2 \le n \le 10^{18}$. Print the prime factorisation of each (primes in non-decreasing order, with repetition).
- **Thinking from first principles:** Trial division needs $10^9$ divisions for a semiprime of two 9-digit primes. Pollard–Brent finds a factor $p$ in about $\sqrt p \le 3\cdot10^4$ iterations; recursion with a primality check handles the rest. The hard inputs are exactly those trial division hates — semiprimes $p\cdot q$ with $p \approx q \approx 10^9$ and prime squares.

<details><summary>Solution</summary>

`factorize` from §3. Worst case per number $\approx 10^5$ mulmods. Output sorted.

```cpp
#include <bits/stdc++.h>
using namespace std;
using u64 = unsigned long long;
u64 mulmod(u64 a, u64 b, u64 m) { return (unsigned __int128)a * b % m; }
u64 powmod(u64 a, u64 e, u64 m) {
    u64 r = 1 % m; a %= m;
    for (; e; e >>= 1, a = mulmod(a, a, m)) if (e & 1) r = mulmod(r, a, m);
    return r;
}
bool is_prime(u64 n) {
    if (n < 2) return false;
    for (u64 p : {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37}) if (n % p == 0) return n == p;
    u64 d = n - 1; int s = 0;
    while (d % 2 == 0) { d /= 2; s++; }
    for (u64 a : {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37}) {
        u64 x = powmod(a, d, n);
        if (x == 1 || x == n - 1) continue;
        bool comp = true;
        for (int r = 1; r < s && comp; r++) { x = mulmod(x, x, n); if (x == n - 1) comp = false; }
        if (comp) return false;
    }
    return true;
}
u64 pollard_brent(u64 n) {
    if (n % 2 == 0) return 2;
    static mt19937_64 rng(0x5eed);
    while (true) {
        u64 c = rng() % (n - 1) + 1, y = rng() % n, x = y, ys = y, q = 1, g = 1;
        auto f = [&](u64 v) { return (mulmod(v, v, n) + c) % n; };
        for (u64 r = 1; g == 1; r <<= 1) {
            x = y;
            for (u64 i = 0; i < r; i++) y = f(y);
            for (u64 k = 0; k < r && g == 1; k += 128) {
                ys = y;
                for (u64 i = 0; i < 128 && i < r - k; i++) { y = f(y); q = mulmod(q, x > y ? x - y : y - x, n); }
                g = gcd(q, n);
            }
        }
        if (g == n) { g = 1; while (g == 1) { ys = f(ys); g = gcd(x > ys ? x - ys : ys - x, n); } }
        if (g != n) return g;
    }
}
void factor_rec(u64 n, vector<u64> &out) {
    if (n == 1) return;
    if (is_prime(n)) { out.push_back(n); return; }
    for (u64 p : {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37})
        if (n % p == 0) { out.push_back(p); factor_rec(n / p, out); return; }
    u64 d = pollard_brent(n);
    factor_rec(d, out); factor_rec(n / d, out);
}
int main() {
    int T; cin >> T;
    while (T--) {
        u64 n; cin >> n;
        vector<u64> f; factor_rec(n, f);
        sort(f.begin(), f.end());
        for (size_t i = 0; i < f.size(); i++) cout << f[i] << (i + 1 == f.size() ? '\n' : ' ');
    }
}
```

```java
import java.util.*;
import java.io.*;
import java.math.BigInteger;

public class Main {
    static final class Mont {
        final long n, nInv, r2;
        Mont(long n) {
            this.n = n;
            long inv = n;
            for (int i = 0; i < 5; i++) inv *= 2 - n * inv;
            nInv = -inv;
            r2 = BigInteger.ONE.shiftLeft(128).mod(BigInteger.valueOf(n)).longValue();
        }
        long reduce(long hi, long lo) {
            long m = lo * nInv;
            long t = hi + Math.unsignedMultiplyHigh(m, n) + (lo != 0 ? 1 : 0);
            return Long.compareUnsigned(t, n) >= 0 ? t - n : t;
        }
        long mul(long a, long b) { return reduce(Math.unsignedMultiplyHigh(a, b), a * b); }
        long to(long a) { return mul(Long.remainderUnsigned(a, n), r2); }
        long pow(long aM, long e) {
            long r = to(1);
            for (; e > 0; e >>= 1, aM = mul(aM, aM)) if ((e & 1) == 1) r = mul(r, aM);
            return r;
        }
    }
    static final long[] BASES = {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37};
    static boolean isPrime(long n) {
        if (n < 2) return false;
        for (long p : BASES) if (n % p == 0) return n == p;
        Mont M = new Mont(n);
        long d = n - 1; int s = Long.numberOfTrailingZeros(d); d >>= s;
        long one = M.to(1), minusOne = M.to(n - 1);
        for (long a : BASES) {
            long x = M.pow(M.to(a), d);
            if (x == one || x == minusOne) continue;
            boolean comp = true;
            for (int r = 1; r < s && comp; r++) { x = M.mul(x, x); if (x == minusOne) comp = false; }
            if (comp) return false;
        }
        return true;
    }
    static long gcd(long a, long b) { while (b != 0) { long t = a % b; a = b; b = t; } return a; }
    static final SplittableRandom RNG = new SplittableRandom(0x5eed);
    static long pollardBrent(long n) {
        Mont M = new Mont(n);
        while (true) {
            long c = M.to(1 + RNG.nextLong(n - 1)), y = M.to(RNG.nextLong(n)), x = y, ys = y, q = M.to(1), g = 1;
            for (long r = 1; g == 1; r <<= 1) {
                x = y;
                for (long i = 0; i < r; i++) { y = M.mul(y, y) + c; if (y >= n) y -= n; }
                for (long k = 0; k < r && g == 1; k += 128) {
                    ys = y;
                    for (long i = 0; i < 128 && i < r - k; i++) {
                        y = M.mul(y, y) + c; if (y >= n) y -= n;
                        q = M.mul(q, x > y ? x - y : y - x);
                    }
                    g = gcd(q, n);
                }
            }
            if (g == n) { g = 1; while (g == 1) { ys = M.mul(ys, ys) + c; if (ys >= n) ys -= n; g = gcd(x > ys ? x - ys : ys - x, n); } }
            if (g != n) return g;
        }
    }
    static void factorRec(long n, List<Long> out) {
        if (n == 1) return;
        if (isPrime(n)) { out.add(n); return; }
        for (long p : BASES) if (n % p == 0) { out.add(p); factorRec(n / p, out); return; }
        long d = pollardBrent(n);
        factorRec(d, out); factorRec(n / d, out);
    }
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int T = Integer.parseInt(br.readLine().trim());
        StringBuilder sb = new StringBuilder();
        while (T-- > 0) {
            List<Long> f = new ArrayList<>();
            factorRec(Long.parseLong(br.readLine().trim()), f);
            Collections.sort(f);
            for (int i = 0; i < f.size(); i++) sb.append(f.get(i)).append(i + 1 == f.size() ? '\n' : ' ');
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
5
2
561
1000000000000000000
999999999999999989
897612484786617600
out:
2
3 11 17
2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5
999999999999999989
2 2 2 2 2 2 2 2 3 3 3 3 5 5 7 7 11 13 17 19 23 29 31 37
-->
<!-- test
in:
3
999999866000004473
999999999999999877
999999874000003969
out:
999999929 999999937
999999999999999877
999999937 999999937
-->

### Example 3 — Smallest primitive root of a large prime  ·  ★ ≈2100 (est.)

- **Source:** Original problem
- **Difficulty:** ≈2100 (est.)
- **Problem:** $T \le 100$ primes $p \le 10^{18}$. Print the smallest primitive root of each.
- **Thinking from first principles:** Testing whether $g$ has order $p - 1$ by computing all powers is $O(p)$. The order divides $p-1$, so it suffices to rule out the maximal proper divisors $(p-1)/q$ for each prime $q \mid p - 1$ (§1.2). That needs the factorisation of $p - 1$ — Pollard rho. Then try $g = 2, 3, \dots$; primitive roots are plentiful.

<details><summary>Solution</summary>

Factor $p - 1$, deduplicate primes, and test candidates. $O(\text{factor} + k\cdot\omega\cdot\log p)$ where $k$ is the answer.

```cpp
#include <bits/stdc++.h>
using namespace std;
using u64 = unsigned long long;
u64 mulmod(u64 a, u64 b, u64 m) { return (unsigned __int128)a * b % m; }
u64 powmod(u64 a, u64 e, u64 m) {
    u64 r = 1 % m; a %= m;
    for (; e; e >>= 1, a = mulmod(a, a, m)) if (e & 1) r = mulmod(r, a, m);
    return r;
}
bool is_prime(u64 n) {
    if (n < 2) return false;
    for (u64 p : {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37}) if (n % p == 0) return n == p;
    u64 d = n - 1; int s = 0;
    while (d % 2 == 0) { d /= 2; s++; }
    for (u64 a : {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37}) {
        u64 x = powmod(a, d, n);
        if (x == 1 || x == n - 1) continue;
        bool comp = true;
        for (int r = 1; r < s && comp; r++) { x = mulmod(x, x, n); if (x == n - 1) comp = false; }
        if (comp) return false;
    }
    return true;
}
u64 pollard_brent(u64 n) {
    if (n % 2 == 0) return 2;
    static mt19937_64 rng(0x5eed);
    while (true) {
        u64 c = rng() % (n - 1) + 1, y = rng() % n, x = y, ys = y, q = 1, g = 1;
        auto f = [&](u64 v) { return (mulmod(v, v, n) + c) % n; };
        for (u64 r = 1; g == 1; r <<= 1) {
            x = y;
            for (u64 i = 0; i < r; i++) y = f(y);
            for (u64 k = 0; k < r && g == 1; k += 128) {
                ys = y;
                for (u64 i = 0; i < 128 && i < r - k; i++) { y = f(y); q = mulmod(q, x > y ? x - y : y - x, n); }
                g = gcd(q, n);
            }
        }
        if (g == n) { g = 1; while (g == 1) { ys = f(ys); g = gcd(x > ys ? x - ys : ys - x, n); } }
        if (g != n) return g;
    }
}
void factor_rec(u64 n, vector<u64> &out) {
    if (n == 1) return;
    if (is_prime(n)) { out.push_back(n); return; }
    for (u64 p : {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37})
        if (n % p == 0) { out.push_back(p); factor_rec(n / p, out); return; }
    u64 d = pollard_brent(n);
    factor_rec(d, out); factor_rec(n / d, out);
}
int main() {
    int T; cin >> T;
    while (T--) {
        u64 p; cin >> p;
        if (p == 2) { cout << 1 << '\n'; continue; }
        vector<u64> f; factor_rec(p - 1, f);
        sort(f.begin(), f.end()); f.erase(unique(f.begin(), f.end()), f.end());
        for (u64 g = 2;; g++) {
            bool ok = true;
            for (u64 q : f) if (powmod(g, (p - 1) / q, p) == 1) { ok = false; break; }
            if (ok) { cout << g << '\n'; break; }
        }
    }
}
```

```java
import java.util.*;
import java.io.*;
import java.math.BigInteger;

public class Main {
    static final class Mont {
        final long n, nInv, r2;
        Mont(long n) {
            this.n = n;
            long inv = n;
            for (int i = 0; i < 5; i++) inv *= 2 - n * inv;
            nInv = -inv;
            r2 = BigInteger.ONE.shiftLeft(128).mod(BigInteger.valueOf(n)).longValue();
        }
        long reduce(long hi, long lo) {
            long m = lo * nInv;
            long t = hi + Math.unsignedMultiplyHigh(m, n) + (lo != 0 ? 1 : 0);
            return Long.compareUnsigned(t, n) >= 0 ? t - n : t;
        }
        long mul(long a, long b) { return reduce(Math.unsignedMultiplyHigh(a, b), a * b); }
        long to(long a) { return mul(Long.remainderUnsigned(a, n), r2); }
        long pow(long aM, long e) {
            long r = to(1);
            for (; e > 0; e >>= 1, aM = mul(aM, aM)) if ((e & 1) == 1) r = mul(r, aM);
            return r;
        }
    }
    static final long[] BASES = {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37};
    static boolean isPrime(long n) {
        if (n < 2) return false;
        for (long p : BASES) if (n % p == 0) return n == p;
        Mont M = new Mont(n);
        long d = n - 1; int s = Long.numberOfTrailingZeros(d); d >>= s;
        long one = M.to(1), minusOne = M.to(n - 1);
        for (long a : BASES) {
            long x = M.pow(M.to(a), d);
            if (x == one || x == minusOne) continue;
            boolean comp = true;
            for (int r = 1; r < s && comp; r++) { x = M.mul(x, x); if (x == minusOne) comp = false; }
            if (comp) return false;
        }
        return true;
    }
    static long gcd(long a, long b) { while (b != 0) { long t = a % b; a = b; b = t; } return a; }
    static final SplittableRandom RNG = new SplittableRandom(0x5eed);
    static long pollardBrent(long n) {
        Mont M = new Mont(n);
        while (true) {
            long c = M.to(1 + RNG.nextLong(n - 1)), y = M.to(RNG.nextLong(n)), x = y, ys = y, q = M.to(1), g = 1;
            for (long r = 1; g == 1; r <<= 1) {
                x = y;
                for (long i = 0; i < r; i++) { y = M.mul(y, y) + c; if (y >= n) y -= n; }
                for (long k = 0; k < r && g == 1; k += 128) {
                    ys = y;
                    for (long i = 0; i < 128 && i < r - k; i++) {
                        y = M.mul(y, y) + c; if (y >= n) y -= n;
                        q = M.mul(q, x > y ? x - y : y - x);
                    }
                    g = gcd(q, n);
                }
            }
            if (g == n) { g = 1; while (g == 1) { ys = M.mul(ys, ys) + c; if (ys >= n) ys -= n; g = gcd(x > ys ? x - ys : ys - x, n); } }
            if (g != n) return g;
        }
    }
    static void factorRec(long n, List<Long> out) {
        if (n == 1) return;
        if (isPrime(n)) { out.add(n); return; }
        for (long p : BASES) if (n % p == 0) { out.add(p); factorRec(n / p, out); return; }
        long d = pollardBrent(n);
        factorRec(d, out); factorRec(n / d, out);
    }
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int T = Integer.parseInt(br.readLine().trim());
        StringBuilder sb = new StringBuilder();
        while (T-- > 0) {
            long p = Long.parseLong(br.readLine().trim());
            if (p == 2) { sb.append(1).append('\n'); continue; }
            List<Long> f = new ArrayList<>();
            factorRec(p - 1, f);
            TreeSet<Long> qs = new TreeSet<>(f);
            Mont M = new Mont(p);
            long one = M.to(1);
            for (long g = 2;; g++) {
                boolean ok = true;
                long gM = M.to(g);
                for (long q : qs) if (M.pow(gM, (p - 1) / q) == one) { ok = false; break; }
                if (ok) { sb.append(g).append('\n'); break; }
            }
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
6
2
3
7
998244353
1000000007
1000000000000000003
out:
1
2
3
3
5
2
-->
<!-- test
in:
3
40961
2147483647
999999999999999989
out:
3
7
2
-->

### Example 4 — Discrete logarithm, including $\gcd(a, m) > 1$  ·  ★ ≈2300 (est.)

- **Source:** Original problem
- **Difficulty:** ≈2300 (est.)
- **Problem:** $T \le 100$ queries $(a, b, m)$ with $0 \le a, b < m \le 10^9$. Print the smallest $x \ge 0$ with $a^x \equiv b \pmod m$ (with $a^0 = 1$), or $-1$.
- **Thinking from first principles:** The powers of $a$ are eventually periodic, with pre-period $\le \log_2 m$ (each common factor with $m$ can be "absorbed" at most $\log_2 m$ times) and period dividing $\varphi(m)$. BSGS handles the periodic part in $O(\sqrt m)$; the gcd-stripping loop of §1.3 handles the pre-period exactly.

<details><summary>Solution</summary>

`discrete_log` from §3; $O(\sqrt m)$ per query with hashing. Use `reserve` (C++) to avoid rehash cost; in Java `HashMap<Long,Long>` with $3\cdot10^4$ entries per query is fine.

```cpp
#include <bits/stdc++.h>
using namespace std;
long long discrete_log(long long a, long long b, long long m) {
    a %= m; b %= m;
    if (m == 1) return 0;
    long long k = 1 % m, add = 0, g;
    while ((g = gcd(a, m)) > 1) {
        if (b == k) return add;
        if (b % g) return -1;
        b /= g; m /= g; add++;
        k = k * (a / g) % m;
    }
    long long n = (long long)sqrtl((long double)m) + 1, an = 1;
    for (long long i = 0; i < n; i++) an = an * a % m;
    unordered_map<long long, long long> baby;
    baby.reserve(2 * n);
    for (long long j = 0, cur = b; j <= n; j++) { baby[cur] = j; cur = cur * a % m; }
    for (long long i = 1, cur = k; i <= n; i++) {
        cur = cur * an % m;
        auto it = baby.find(cur);
        if (it != baby.end()) return n * i - it->second + add;
    }
    return -1;
}
int main() {
    int T; cin >> T;
    while (T--) { long long a, b, m; cin >> a >> b >> m; cout << discrete_log(a, b, m) << '\n'; }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long gcd(long a, long b) { while (b != 0) { long t = a % b; a = b; b = t; } return a; }
    static long discreteLog(long a, long b, long m) {
        a %= m; b %= m;
        if (m == 1) return 0;
        long k = 1 % m, add = 0, g;
        while ((g = gcd(a, m)) > 1) {
            if (b == k) return add;
            if (b % g != 0) return -1;
            b /= g; m /= g; add++;
            k = k * (a / g) % m;
        }
        long n = (long) Math.sqrt((double) m) + 1, an = 1;
        for (long i = 0; i < n; i++) an = an * a % m;
        HashMap<Long, Long> baby = new HashMap<>();
        for (long j = 0, cur = b; j <= n; j++) { baby.put(cur, j); cur = cur * a % m; }
        for (long i = 1, cur = k; i <= n; i++) {
            cur = cur * an % m;
            Long j = baby.get(cur);
            if (j != null) return n * i - j + add;
        }
        return -1;
    }
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int T = Integer.parseInt(br.readLine().trim());
        StringBuilder sb = new StringBuilder();
        while (T-- > 0) {
            StringTokenizer st = new StringTokenizer(br.readLine());
            long a = Long.parseLong(st.nextToken()), b = Long.parseLong(st.nextToken()), m = Long.parseLong(st.nextToken());
            sb.append(discreteLog(a, b, m)).append('\n');
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
7
2 8 11
3 1 7
2 3 4
0 0 5
2 0 8
6 4 10
5 0 1
out:
3
0
-1
1
3
-1
0
-->
<!-- test
in:
3
3 13 998244353
2 999999999 1000000000
12345 6789 1000000007
out:
834170439
-1
-1
-->

### Example 5 — Square roots modulo a prime (Tonelli–Shanks)  ·  ★ ≈2200 (est.)

- **Source:** Original problem
- **Difficulty:** ≈2200 (est.)
- **Problem:** $T \le 10^5$ queries $(a, p)$, $p \le 10^9$ prime, $0 \le a < p$. Print the smaller of the (at most two) $r \in [0, p)$ with $r^2 \equiv a$, or $-1$.
- **Thinking from first principles:** Enumerating $r$ is $O(p)$. Euler's criterion decides existence in one exponentiation. If $p \equiv 3 \pmod 4$ the root is a single power; otherwise peel off the power-of-two part of $p - 1$ with Tonelli–Shanks (§1.4). The two roots are $r$ and $p - r$, so print $\min(r, p - r)$.

<details><summary>Solution</summary>

`sqrt_mod` from §3, $O(\log^2 p)$ per query. Products of residues below $10^9$ fit in 64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
ll powmod(ll a, ll e, ll m) {
    ll r = 1 % m; a %= m;
    for (; e; e >>= 1, a = a * a % m) if (e & 1) r = r * a % m;
    return r;
}
ll sqrt_mod(ll a, ll p) {
    a %= p;
    if (a == 0 || p == 2) return a;
    if (powmod(a, (p - 1) / 2, p) != 1) return -1;
    if (p % 4 == 3) return powmod(a, (p + 1) / 4, p);
    ll q = p - 1; int s = 0;
    while (q % 2 == 0) { q /= 2; s++; }
    ll z = 2;
    while (powmod(z, (p - 1) / 2, p) != p - 1) z++;
    ll M = s, c = powmod(z, q, p), t = powmod(a, q, p), R = powmod(a, (q + 1) / 2, p);
    while (t != 1) {
        ll i = 0, tt = t;
        while (tt != 1) { tt = tt * tt % p; i++; }
        ll b = c;
        for (ll j = 0; j < M - i - 1; j++) b = b * b % p;
        M = i; c = b * b % p; t = t * c % p; R = R * b % p;
    }
    return R;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int T; cin >> T;
    while (T--) {
        ll a, p; cin >> a >> p;
        ll r = sqrt_mod(a, p);
        cout << (r < 0 ? -1 : min(r, (p - r) % p)) << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long powmod(long a, long e, long m) {
        long r = 1 % m; a %= m;
        for (; e > 0; e >>= 1, a = a * a % m) if ((e & 1) == 1) r = r * a % m;
        return r;
    }
    static long sqrtMod(long a, long p) {
        a %= p;
        if (a == 0 || p == 2) return a;
        if (powmod(a, (p - 1) / 2, p) != 1) return -1;
        if (p % 4 == 3) return powmod(a, (p + 1) / 4, p);
        long q = p - 1; int s = 0;
        while (q % 2 == 0) { q /= 2; s++; }
        long z = 2;
        while (powmod(z, (p - 1) / 2, p) != p - 1) z++;
        long M = s, c = powmod(z, q, p), t = powmod(a, q, p), R = powmod(a, (q + 1) / 2, p);
        while (t != 1) {
            long i = 0, tt = t;
            while (tt != 1) { tt = tt * tt % p; i++; }
            long b = c;
            for (long j = 0; j < M - i - 1; j++) b = b * b % p;
            M = i; c = b * b % p; t = t * c % p; R = R * b % p;
        }
        return R;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int T = in.nextInt();
        while (T-- > 0) {
            long a = in.nextLong(), p = in.nextLong();
            long r = sqrtMod(a, p);
            out.println(r < 0 ? -1 : Math.min(r, (p - r) % p));
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
2 7
3 7
0 13
10 13
1 2
4 17
out:
3
-1
0
6
1
2
-->
<!-- test
in:
4
642754969 998244353
3 998244353
25 1000000007
10821600 1000000009
out:
123456789
-1
5
12345688
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Never use a Fermat test or random bases in contests** when a deterministic set exists: 12 primes for 64-bit, $\lbrace 2, 7, 61\rbrace$ for 32-bit.
2. **`(a * b) % m` with 64-bit $m$ overflows**; MR on $10^{18}$ silently gives garbage without 128-bit products (C++) or Montgomery/`BigInteger` (Java).
3. **Pollard rho on a prime loops forever** — always test primality first; also strip factors 2 (Montgomery needs odd $n$) and small primes.
4. **Pollard rho on a perfect power** like $p^2$ works (the gcd returns $p$), but on $4$ the map $x^2 + c$ mod 4 can cycle badly — small-prime stripping avoids it.
5. **Seed your RNG** (fixed seed is fine for correctness; random seed avoids adversarial cases on hackable judges).
6. **BSGS minimality**: store the *largest* $j$ per value and stop at the first giant step that hits. Using `emplace` (keeps the first $j$) returns a non-minimal $x$.
7. **BSGS memory**: $\sqrt{10^{18}} = 10^9$ entries is impossible — discrete log mod a 64-bit prime needs Pohlig–Hellman (factor $p - 1$, solve in each prime-power subgroup).
8. **`unordered_map` with adversarial input** can be hacked; for BSGS the keys are powers of $a$, rarely adversarial, but `reserve` helps speed.
9. **Primitive roots exist only mod $1, 2, 4, p^k, 2p^k$.** Mod $2^k$ ($k \ge 3$) the units are $\pm 5^j$ — not cyclic.
10. **Square roots come in pairs** $\pm r$ (except $a = 0$ or $p = 2$); state which one you output.

---

## 7. Going further (toward 2400–2600+)

- **Pohlig–Hellman**: discrete log in a group of order $N = \prod q_i^{e_i}$ reduces to logs in subgroups of order $q_i$; with smooth $p - 1$ (e.g. $998244353 - 1 = 2^{23}\cdot 7 \cdot 17$) it is fast even for 64-bit $p$.
- **Discrete roots** $x^k \equiv a$: index calculus via a primitive root — used in [CF 1106F · Lunar New Year and a Recursive Sequence](https://codeforces.com/problemset/problem/1106/F) — 2400.
- **Cipolla's algorithm** (🧊): square roots via arithmetic in $\mathbb{F}_{p^2}$, simpler to prove than Tonelli–Shanks.
- **Square roots modulo composites**: solve mod each prime power (Hensel lifting), combine with [CRT](05-crt-and-linear-congruences.md).
- **Montgomery everywhere**: the same `Mont` structure speeds up NTT with runtime moduli and Miller–Rabin batches ([randomized algorithms](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md)).

---

## 8. Practice ladder

- [ ] [CSES 3396 · Next Prime](https://cses.fi/problemset/task/3396)
- [ ] [CF 1514C · Product 1 Modulo N](https://codeforces.com/problemset/problem/1514/C) — 1600
- [ ] [CF 1366D · Two Divisors](https://codeforces.com/problemset/problem/1366/D) — 2000
- [ ] [CF 1325E · Ehab's REAL Number Theory Problem](https://codeforces.com/problemset/problem/1325/E) — 2600
- [ ] [CF 1106F · Lunar New Year and a Recursive Sequence](https://codeforces.com/problemset/problem/1106/F) — 2400
- [ ] [CF 1305F · Kuroni and the Punishment](https://codeforces.com/problemset/problem/1305/F) — 2500
- [ ] [CF 487C · Prefix Product Sequence](https://codeforces.com/problemset/problem/487/C) — 2300
- [ ] [CF 1182E · Product Oriented Recurrence](https://codeforces.com/problemset/problem/1182/E) — 2300
- [ ] [AtCoder ABC270 G · Sequence in mod P](https://atcoder.jp/contests/abc270/tasks/abc270_g) — diff≈2220
- [ ] [AtCoder AGC047 C · Product Modulo](https://atcoder.jp/contests/agc047/tasks/agc047_c) — diff≈2496
- [ ] [AtCoder ABC245 Ex · Product Modulo 2](https://atcoder.jp/contests/abc245/tasks/abc245_h) — diff≈3057

---

## 9. LeetCode / FAANG cross-reference

Rare in interviews — none of these algorithms is expected in FAANG rounds. The nearest relatives:
- [LC 204 · Count Primes](https://leetcode.com/problems/count-primes/) — Medium — primality en masse uses a sieve, not Miller–Rabin.
- [LC 1015 · Smallest Integer Divisible by K](https://leetcode.com/problems/smallest-integer-divisible-by-k/) — Medium — the answer is the order of $10$ modulo $9k$ (for $\gcd(k, 10) = 1$); the loop bound $k$ comes from pigeonhole.

---

## 10. Self-check

1. Why does $\operatorname{ord}(a)$ divide every $e$ with $a^e \equiv 1$?
2. Prove that a primitive root exists modulo every prime (outline the counting argument).
3. How do you test whether $g$ is a primitive root mod $p$ in $O(\omega(p-1)\log p)$?
4. Why can a Carmichael number fool Fermat but not Miller–Rabin with all bases?
5. Derive BSGS: what are the baby and giant steps and why is the complexity $O(\sqrt m)$?
6. Prove Euler's criterion using a primitive root.
7. Why does Pollard's rho take about $\sqrt p$ steps, where $p$ is the smallest prime factor?
8. For which $n$ does a primitive root exist? Why not mod 8?

<details><summary>Answers</summary>

1. Write $e = q\cdot\operatorname{ord} + r$; $a^r \equiv 1$ with $0 \le r < \operatorname{ord}$ forces $r = 0$.
2. #elements of order $d$ is $0$ or $\varphi(d)$ (roots of $x^d - 1$); these counts sum to $p - 1 = \sum_{d \mid p-1}\varphi(d)$, so all are $\varphi(d)$, including $d = p - 1$.
3. Factor $p - 1$; check $g^{(p-1)/q} \ne 1$ for each distinct prime $q$.
4. Miller–Rabin also requires that the last square root of $1$ in the chain be $-1$. For a composite $n$ with two distinct prime factors, $x^2 \equiv 1$ has extra roots that expose it for most bases.
5. $x = in - j$; baby steps store $b a^j$ ($n$ values), giant steps compute $(a^n)^i$ ($n$ values); a match gives $a^{in} = ba^j$. Both loops are $\sqrt m$ long.
6. $a = g^t$; $a^{(p-1)/2} = (g^{(p-1)/2})^t = (-1)^t$, and $a$ is a square iff $t$ is even.
7. The iterates mod $p$ behave like random values in a set of size $p$; the birthday paradox gives a repeat after $\Theta(\sqrt p)$ steps, which becomes visible as $\gcd(x_i - x_j, n) \ge p$.
8. $n = 1, 2, 4, p^k, 2p^k$. Mod 8, the units $1, 3, 5, 7$ all square to $1$, so no element has order 4.

</details>
