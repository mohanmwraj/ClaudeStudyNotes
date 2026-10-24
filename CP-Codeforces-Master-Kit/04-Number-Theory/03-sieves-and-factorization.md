# Sieves, Smallest Prime Factors and Factorisation

> **Band:** 🟢 1000 – 🟣 2100 · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [gcd](01-divisibility-gcd-and-extended-euclid.md), [modular arithmetic](02-modular-arithmetic-and-inverses.md), [complexity](../01-Foundations/01-complexity-and-constraint-reading.md)
> **You can say you know this when:** you can write a linear sieve that also produces $\varphi$, $\mu$, $d$ and $\sigma$, factor $10^6$ numbers in $O(\log)$ each, sieve primes in $[10^{12}, 10^{12}+10^6]$, and quote the divisor-count bounds that decide whether "iterate over all divisors" is fast enough.

---

## 1. First principles — why this works

### 1.1 Trial division and the $\sqrt n$ barrier

If $n = ab$ with $1 < a \le b$, then $a^2 \le ab = n$, so **every composite $n$ has a prime factor $\le \sqrt n$**. Testing primality or factoring by dividing by $2, 3, \dots, \lfloor\sqrt n\rfloor$ is therefore correct, and costs $O(\sqrt n)$: $10^6$ divisions for $n = 10^{12}$, $10^9$ for $10^{18}$ (too slow — that needs [Pollard rho](06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md)). Dividing out each factor as found keeps the loop correct: when $i$ divides the current $n$, every smaller prime has already been removed, so $i$ is prime.

### 1.2 The sieve of Eratosthenes: reuse work across numbers

Testing each of $1..N$ separately costs $O(N\sqrt N)$. Turn it around: instead of asking "who divides $x$?", let each prime **announce** its multiples. Walk $p = 2, 3, \dots$; if $p$ is still unmarked it is prime (no smaller prime divides it), and we mark $p^2, p^2 + p, \dots$. Starting at $p^2$ is enough: a smaller multiple $kp$ with $k < p$ has a prime factor $< p$ and was already marked. The outer loop can stop at $\sqrt N$.

**Cost.** Prime $p$ marks $\le N/p$ numbers, so the total is $N \sum_{p \le N} 1/p$. Mertens' theorem says $\sum_{p \le x} 1/p = \ln \ln x + M + o(1)$ ($M \approx 0.2615$). Sketch: $\prod_{p \le x} (1 - 1/p)^{-1} = \prod_p (1 + 1/p + 1/p^2 + \cdots) \ge \sum_{n \le x} 1/n \approx \ln x$ (every $n \le x$ appears in the expanded product); take logs and use $-\ln(1 - t) = t + O(t^2)$ to get $\sum 1/p \ge \ln\ln x - O(1)$; the matching upper bound needs Chebyshev-type estimates. So Eratosthenes is $O(N \log\log N)$ — practically linear ($\ln\ln 10^7 \approx 2.8$).

### 1.3 The linear sieve: every composite crossed out exactly once

Eratosthenes marks $30 = 2\cdot15 = 3\cdot10 = 5\cdot6$ three times. Can we make each composite be produced once, by a canonical factorisation? Write $c = \operatorname{spf}(c)\cdot\frac{c}{\operatorname{spf}(c)}$ where $\operatorname{spf}$ is the smallest prime factor. Generate $c$ **only** as $i \cdot p$ with $i = c/\operatorname{spf}(c)$ and $p = \operatorname{spf}(c)$. For a fixed $i$, which primes $p$ give $\operatorname{spf}(ip) = p$? Exactly those with $p \le \operatorname{spf}(i)$. So:

> for $i = 2..N$: if $i$ unmarked, it is prime. Then for primes $p = 2, 3, \dots$ while $p \le \operatorname{spf}(i)$ and $ip \le N$: set $\operatorname{spf}(ip) = p$.

Each composite is set exactly once, so the sieve is $O(N)$, and as a by-product we get $\operatorname{spf}$ for every number — which gives $O(\log n)$ factorisation by repeated division (each step at least halves $n$).

The case split "$p < \operatorname{spf}(i)$" versus "$p = \operatorname{spf}(i)$" is exactly "$p \nmid i$" versus "$p \mid i$". That is what makes **multiplicative functions** computable inside the same loop: if $p \nmid i$ then $f(ip) = f(i) f(p)$; if $p \mid i$ we need to know how many times $p$ already divides $i$ (§2.4).

### 1.4 Segmented sieve: primes in a far-away window

For $[L, R]$ with $R \le 10^{12}$ but $R - L \le 10^6$, an array of size $R$ is impossible, but a composite $x \le R$ always has a prime factor $\le \sqrt R \le 10^6$. Sieve primes up to $\sqrt R$ normally, then for each such $p$ cross out its multiples inside the window, starting from $\max(p^2, \lceil L/p\rceil p)$. Cost $O\bigl((R - L)\log\log R + \sqrt R\bigr)$.

### 1.5 Harmonic sums: "iterate over multiples" is cheap

Looping, for every $d = 1..N$, over its multiples $d, 2d, 3d, \dots \le N$ costs $\sum_{d=1}^{N} \lfloor N/d \rfloor \approx N \ln N$. This one fact powers "divisor DP", counting multiples of every $d$, and the $O(N\log N)$ divisor-list construction (append $d$ to the list of each multiple). Whenever a statement has values up to $10^6$ and a relation "$x$ divides $y$", think harmonic loop.

---

## 2. Formulas, definitions and identities

### 2.1 Divisor functions (for $n = \prod_i p_i^{e_i}$)

| Function | Formula | Derivation |
|---|---|---|
| number of divisors $d(n)$ | $\prod_i (e_i + 1)$ | A divisor picks an exponent $0..e_i$ for each prime independently. |
| sum of divisors $\sigma(n)$ | $\prod_i \dfrac{p_i^{e_i + 1} - 1}{p_i - 1}$ | Expand $\prod_i (1 + p_i + \dots + p_i^{e_i})$: each divisor appears once; each factor is a geometric series. |
| $\sigma_k(n) = \sum_{d \mid n} d^k$ | $\prod_i \dfrac{p_i^{k(e_i+1)} - 1}{p_i^k - 1}$ | Same expansion with $p^k$. |
| product of divisors | $n^{d(n)/2}$ | Pair $d$ with $n/d$; if $n$ is a square, $\sqrt n$ pairs with itself, still giving $n^{d/2}$. Modulo $p$, compute exponents mod $p-1$ (Example 2). |
| number of square divisors, odd divisors, … | $\prod_i (\lfloor e_i/2\rfloor + 1)$, $\prod_{p_i \ne 2} (e_i + 1)$ | Same "independent exponent" argument. |

### 2.2 Bounds and constants worth memorising

| Quantity | Value | Source |
|---|---|---|
| $\pi(10^6), \pi(10^7), \pi(10^8), \pi(10^9)$ | 78 498; 664 579; 5 761 455; 50 847 534 | counted by sieve |
| density of primes near $n$ | $\approx 1/\ln n$ (prime number theorem, $\pi(x) \sim x/\ln x$) | ~1 in 28 near $10^{12}$, 1 in 41 near $10^{18}$ |
| max $d(n)$, $n \le 10^3$ / $10^4$ / $10^5$ / $10^6$ | 32 / 64 / 128 / 240 (at 840, 7560, 83160, 720720) | search over non-increasing exponents |
| max $d(n)$, $n \le 10^7$ / $10^8$ / $10^9$ | 448 / 768 / **1344** (at 735 134 400) | same |
| max $d(n)$, $n \le 10^{12}$ / $10^{15}$ / $10^{18}$ | 6720 / 26 880 / **103 680** (at 897 612 484 786 617 600) | same |
| rough rule | $\max_{n\le N} d(n)$ is a small multiple of $\sqrt[3]{N}$ in contest ranges — about $3.2\times$ at $N=10^3$ falling to $1.3\times$ at $N=10^9$ (32, 64, 128, 240, 448, 768, 1344 for $N=10^3,\dots,10^9$), so $n^{1/3}$ is an estimate, **not** an upper bound; $d(n) \le 2\sqrt n$ always | divisors pair up as $(d, n/d)$ |
| max number of distinct primes $\omega(n)$ | 9 for $n \le 10^9$ ($2\cdot3\cdots23 = 223\,092\,870$); 15 for $n \le 10^{18}$ (first 15 primes: $\approx 6.1\cdot10^{17}$) | primorials |
| max prime gap below $10^9$ / $10^{18}$ | 282 (after 436 273 009) / 1442 | sieve / published record |
| $\sum_{i \le n} d(i)$ | $= \sum_{k \le n}\lfloor n/k\rfloor = n\ln n + (2\gamma - 1)n + O(\sqrt n)$ | count pairs $(k, m)$ with $km \le n$ |
| $\sum_{i \le n} \sigma(i)$ | $= \sum_{k \le n} k\lfloor n/k\rfloor \approx \frac{\pi^2}{12}n^2$ | swap the sum: $k$ divides $\lfloor n/k\rfloor$ numbers |
| harmonic number $H_n = \sum_{i \le n} 1/i$ | $\ln n + \gamma + O(1/n)$, $\gamma \approx 0.5772$ | integral comparison |

Consequences: "for each query enumerate all divisors of $x \le 10^9$" is at most 1344 per query; "for each $x \le 10^6$ enumerate divisors" totals $\approx 1.4\cdot10^7$; the "next prime after $n$" is at most a few hundred steps away for 64-bit $n$, so trying consecutive numbers with a fast primality test is fine.

### 2.3 Algorithms and their cost

| Task | Method | Cost |
|---|---|---|
| is $n$ prime / factor $n$ | trial division to $\sqrt n$ | $O(\sqrt n)$; by primes only: $O(\sqrt n / \ln n)$ |
| all primes $\le N$ | Eratosthenes from $p^2$ | $O(N \log\log N)$ time, $N$ bits (`vector<bool>`/`bitset`) |
| $\operatorname{spf}$ of all $n \le N$ | linear sieve | $O(N)$, $4N$ bytes |
| factor any $n \le N$ after the sieve | divide by $\operatorname{spf}$ repeatedly | $O(\log n)$ |
| primes in $[L, R]$ | segmented sieve | $O((R-L)\log\log R + \sqrt R)$ |
| divisors of all $n \le N$ | harmonic loop | $O(N \log N)$ time and memory |
| divisors of one $n$ given its factorisation | product over primes | $O(d(n))$ |
| $n \le 10^{18}$ | Miller–Rabin + Pollard rho | $\approx O(n^{1/4})$ — [file 06](06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md) |

**Cube-root trick (🧊).** To compute $d(n)$ for $n \le 10^{18}$ without Pollard: trial-divide by primes $\le n^{1/3} = 10^6$. The leftover cofactor $r$ has no prime factor $\le n^{1/3}$, so it has at most two prime factors: $r = 1$, a prime $q$ (contributes $\times 2$), a square $q^2$ ($\times 3$), or $q_1 q_2$ with $q_1 \ne q_2$ ($\times 4$). Distinguish with one primality test and one integer square root.

### 2.4 Multiplicative functions in the linear sieve

A function is **multiplicative** if $f(ab) = f(a)f(b)$ whenever $\gcd(a, b) = 1$ (and $f(1) = 1$). Then $f$ is determined by its values on prime powers. In the linear sieve step $(i, p)$ with $p \le \operatorname{spf}(i)$:

- $p \nmid i$ ($p < \operatorname{spf}(i)$): $\gcd(i, p) = 1$, so $f(ip) = f(i)f(p)$.
- $p \mid i$ ($p = \operatorname{spf}(i)$): write $i = p^{e} m$ with $p \nmid m$. Then $f(ip) = f(m)\,f(p^{e+1})$. Track $\text{pk}[i] = p^e$ (the full power of the smallest prime) so that $m = i / \text{pk}[i]$.

For the standard functions the $p \mid i$ case simplifies:

| $f$ | $f(p)$ | $p \mid i$ case | why |
|---|---|---|---|
| $\varphi$ | $p - 1$ | $\varphi(ip) = p\,\varphi(i)$ | $\varphi(p^{e+1}) = p\cdot\varphi(p^e)$ for $e \ge 1$ |
| $\mu$ | $-1$ | $\mu(ip) = 0$ | $p^2 \mid ip$ |
| $d$ | $2$ | $d(ip) = d(i)\,\frac{e+2}{e+1}$ with $e = \text{cnt}[i]$ | $(e+1) \to (e+2)$ in the product |
| $\sigma$ | $p + 1$ | $\sigma(ip) = \sigma(m)\,\bigl(\sigma(p^e) + p^{e+1}\bigr)$ | geometric series gains one term |

$\varphi$ and $\mu$ are derived in [Euler's theorem](04-euler-phi-fermat-and-euler-theorem.md) and [Möbius](07-mobius-dirichlet-and-floor-sums.md).

---

## 3. Implementation (C++ and Java)

```cpp
// Eratosthenes (bit-packed), linear sieve with spf + phi + mu + d + sigma, segmented sieve, factorisation.
vector<int> eratosthenes(int n) {                       // all primes <= n
    vector<bool> comp(n + 1, false);
    vector<int> primes;
    for (int i = 2; i <= n; i++) {
        if (comp[i]) continue;
        primes.push_back(i);
        for (long long j = 1LL * i * i; j <= n; j += i) comp[j] = true;
    }
    return primes;
}
struct LinearSieve {
    vector<int> spf, primes, phi, mu, d, cnt;          // cnt[i] = exponent of spf(i) in i
    vector<long long> sigma, pk;                        // pk[i] = spf(i)^cnt[i]
    explicit LinearSieve(int n) : spf(n + 1), phi(n + 1), mu(n + 1), d(n + 1), cnt(n + 1), sigma(n + 1), pk(n + 1) {
        phi[1] = mu[1] = d[1] = 1; sigma[1] = 1; pk[1] = 1;
        for (int i = 2; i <= n; i++) {
            if (spf[i] == 0) {                          // i is prime
                spf[i] = i; primes.push_back(i);
                phi[i] = i - 1; mu[i] = -1; d[i] = 2; cnt[i] = 1; sigma[i] = i + 1; pk[i] = i;
            }
            for (int p : primes) {
                long long ip = 1LL * i * p;
                if (p > spf[i] || ip > n) break;
                spf[ip] = p;
                if (p == spf[i]) {                      // p divides i
                    phi[ip] = phi[i] * p;
                    mu[ip] = 0;
                    cnt[ip] = cnt[i] + 1;
                    d[ip] = d[i] / (cnt[i] + 1) * (cnt[i] + 2);
                    pk[ip] = pk[i] * p;
                    long long m = i / pk[i];            // part of i coprime to p
                    sigma[ip] = sigma[m] * (sigma[pk[i]] + pk[ip]);
                } else {                                // gcd(i, p) = 1
                    phi[ip] = phi[i] * (p - 1);
                    mu[ip] = -mu[i];
                    cnt[ip] = 1;
                    d[ip] = d[i] * 2;
                    pk[ip] = p;
                    sigma[ip] = sigma[i] * (p + 1);
                }
            }
        }
    }
    vector<pair<int, int>> factor(int x) const {       // (prime, exponent), O(log x)
        vector<pair<int, int>> f;
        while (x > 1) {
            int p = spf[x], e = 0;
            while (x % p == 0) { x /= p; e++; }
            f.push_back({p, e});
        }
        return f;
    }
};
vector<pair<long long, int>> trial_factor(long long n) {   // O(sqrt n)
    vector<pair<long long, int>> f;
    for (long long p = 2; p * p <= n; p += (p == 2 ? 1 : 2)) {
        if (n % p) continue;
        int e = 0;
        while (n % p == 0) { n /= p; e++; }
        f.push_back({p, e});
    }
    if (n > 1) f.push_back({n, 1});
    return f;
}
vector<long long> divisors_from(const vector<pair<long long, int>> &f) {
    vector<long long> ds = {1};
    for (auto [p, e] : f) {
        int sz = ds.size();
        long long pw = 1;
        for (int k = 1; k <= e; k++) {
            pw *= p;
            for (int j = 0; j < sz; j++) ds.push_back(ds[j] * pw);
        }
    }
    return ds;                                          // unsorted
}
vector<char> segmented_sieve(long long L, long long R) {    // is_prime[x - L] for x in [L, R]
    long long lim = sqrtl((long double)R) + 1;
    while (lim * lim > R) lim--;
    vector<int> small = eratosthenes((int)lim);
    vector<char> is(R - L + 1, 1);
    for (long long p : small) {
        long long start = max(p * p, (L + p - 1) / p * p);
        for (long long x = start; x <= R; x += p) is[x - L] = 0;
    }
    if (L <= 1) for (long long x = L; x <= min(R, 1LL); x++) is[x - L] = 0;   // 0 and 1 are not prime
    return is;
}
```

```java
// Eratosthenes, linear sieve with spf + phi + mu + d + sigma, segmented sieve, factorisation.
static int[] eratosthenes(int n) {
    boolean[] comp = new boolean[n + 1];
    int[] tmp = new int[n + 1]; int cnt = 0;
    for (int i = 2; i <= n; i++) {
        if (comp[i]) continue;
        tmp[cnt++] = i;
        for (long j = (long) i * i; j <= n; j += i) comp[(int) j] = true;
    }
    return Arrays.copyOf(tmp, cnt);
}
static int[] spf, phi, mu, dcnt, expo, primes;
static long[] sigma, pk;
static void linearSieve(int n) {
    spf = new int[n + 1]; phi = new int[n + 1]; mu = new int[n + 1]; dcnt = new int[n + 1]; expo = new int[n + 1];
    sigma = new long[n + 1]; pk = new long[n + 1];
    int[] pr = new int[n + 1]; int pc = 0;
    phi[1] = mu[1] = dcnt[1] = 1; sigma[1] = 1; pk[1] = 1;
    for (int i = 2; i <= n; i++) {
        if (spf[i] == 0) { spf[i] = i; pr[pc++] = i; phi[i] = i - 1; mu[i] = -1; dcnt[i] = 2; expo[i] = 1; sigma[i] = i + 1; pk[i] = i; }
        for (int j = 0; j < pc; j++) {
            int p = pr[j];
            long ipL = (long) i * p;
            if (p > spf[i] || ipL > n) break;
            int ip = (int) ipL;
            spf[ip] = p;
            if (p == spf[i]) {
                phi[ip] = phi[i] * p; mu[ip] = 0; expo[ip] = expo[i] + 1;
                dcnt[ip] = dcnt[i] / (expo[i] + 1) * (expo[i] + 2);
                pk[ip] = pk[i] * p;
                int m = (int) (i / pk[i]);
                sigma[ip] = sigma[m] * (sigma[(int) pk[i]] + pk[ip]);
            } else {
                phi[ip] = phi[i] * (p - 1); mu[ip] = -mu[i]; expo[ip] = 1; dcnt[ip] = dcnt[i] * 2;
                pk[ip] = p; sigma[ip] = sigma[i] * (p + 1);
            }
        }
    }
    primes = Arrays.copyOf(pr, pc);
}
static List<long[]> factorSpf(int x) {             // requires linearSieve(n >= x)
    List<long[]> f = new ArrayList<>();
    while (x > 1) { int p = spf[x], e = 0; while (x % p == 0) { x /= p; e++; } f.add(new long[]{p, e}); }
    return f;
}
static List<long[]> trialFactor(long n) {
    List<long[]> f = new ArrayList<>();
    for (long p = 2; p * p <= n; p += (p == 2 ? 1 : 2)) {
        if (n % p != 0) continue;
        int e = 0;
        while (n % p == 0) { n /= p; e++; }
        f.add(new long[]{p, e});
    }
    if (n > 1) f.add(new long[]{n, 1});
    return f;
}
static boolean[] segmentedSieve(long L, long R) {  // isPrime[x - L]
    long lim = (long) Math.sqrt((double) R) + 1;
    while (lim * lim > R) lim--;
    int[] small = eratosthenes((int) lim);
    boolean[] is = new boolean[(int) (R - L + 1)];
    Arrays.fill(is, true);
    for (int p : small) {
        long start = Math.max((long) p * p, (L + p - 1) / p * p);
        for (long x = start; x <= R; x += p) is[(int) (x - L)] = false;
    }
    for (long x = L; x <= Math.min(R, 1L); x++) is[(int) (x - L)] = false;
    return is;
}
```

---

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| many queries "factor $x$", $x \le 10^7$ | linear sieve with $\operatorname{spf}$, $O(\log x)$ per query |
| one or few numbers up to $10^{12}$ | trial division to $10^6$ |
| numbers up to $10^{18}$ | Miller–Rabin + Pollard rho (or the cube-root trick if only $d(n)$ is needed) |
| "count / sum over all $i \le N$ of $f(i)$" with multiplicative $f$, $N \le 10^7$ | compute $f$ in the linear sieve |
| primes in a window $[L, R]$, $R$ huge, $R - L$ small | segmented sieve |
| "$a_i$ divides $a_j$", chains, values $\le 10^6$ | harmonic loop over multiples (Example 5) |
| lcm/gcd of many numbers, "per prime exponent" | factor everything; per prime, take min/max/second-min of exponents (Example 4) |
| "product / sum of divisors modulo $p$" | multiplicativity + exponents modulo $p - 1$ (Example 2) |
| "make $x$ a perfect square / cube" | reduce exponents mod 2 or 3 (squarefree kernel) via $\operatorname{spf}$ |

Common confusion: the linear sieve is not faster than a bit-packed Eratosthenes for *just primes* (Eratosthenes touches memory more cache-friendly with bits); use the linear sieve when you need $\operatorname{spf}$ or multiplicative functions.

---

## 5. Worked examples (graded)

### Example 1 — Counting Divisors  ·  ★ ≈1300 (est.)

- **Source:** [CSES 1713 · Counting Divisors](https://cses.fi/problemset/task/1713)
- **Difficulty:** ≈1300 (est.)
- **Problem:** $n \le 10^5$ queries, each $x \le 10^6$: print $d(x)$.
- **Thinking from first principles:** Trial division per query is $10^3$ steps × $10^5$ = $10^8$ — borderline. Precomputation is better: either the harmonic loop ("every $k$ adds 1 to each multiple", $\approx 1.4\cdot10^7$ increments) or $d$ from the linear sieve ($O(N)$).

<details><summary>Solution</summary>

Harmonic loop: `for k in 1..N: for m = k, 2k, ...: d[m]++`. Simple, $O(N \ln N)$, no multiplicativity needed.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    const int N = 1'000'000;
    vector<int> d(N + 1, 0);
    for (int k = 1; k <= N; k++)
        for (int m = k; m <= N; m += k) d[m]++;
    int n; cin >> n;
    while (n--) { int x; cin >> x; cout << d[x] << '\n'; }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        final int N = 1_000_000;
        int[] d = new int[N + 1];
        for (int k = 1; k <= N; k++)
            for (int m = k; m <= N; m += k) d[m]++;
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        while (n-- > 0) out.println(d[in.nextInt()]);
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
16
17
18
out:
5
2
6
-->
<!-- test
in:
4
1
720720
1000000
999983
out:
1
240
49
2
-->

### Example 2 — Divisor Analysis  ·  ★ ≈1800 (est.)

- **Source:** [CSES 2182 · Divisor Analysis](https://cses.fi/problemset/task/2182)
- **Difficulty:** ≈1800 (est.)
- **Problem:** A number $N = \prod_{i=1}^{n} x_i^{k_i}$ is given by $n \le 10^5$ distinct primes $x_i \le 10^6$ and exponents $k_i \le 10^9$. Print the number, sum and product of its divisors, each modulo $p = 10^9+7$.
- **Thinking from first principles:** Number and sum are the product formulas of §2.1 (the sum needs $(x_i - 1)^{-1}$, fine since $x_i - 1 < p$). The product $N^{d(N)/2}$ is the trap: $d(N)$ is a huge number known only modulo something, and $d/2$ may not be an integer. Build the product prime by prime instead: if $N'$ has divisor product $P'$ and divisor count $D'$, then multiplying by $x^{k}$ (new prime) gives divisors $\delta x^{j}$, $0 \le j \le k$, whose product is

$$P = \prod_{\delta \mid N'} \prod_{j=0}^{k} \delta\,x^{j} = (P')^{k+1}\cdot x^{D'\cdot k(k+1)/2}.$$

Exponents of a base coprime to $p$ live modulo $p - 1$ (Fermat), so $D'$ must be tracked **modulo $p - 1$**, not modulo $p$.

<details><summary>Solution</summary>

Keep $D \bmod p$ (for printing), $D \bmod (p-1)$ (for exponents), $S$, $P$. Per prime: $S \mathrel{*}= \frac{x^{k+1}-1}{x-1}$; $P \leftarrow P^{k+1} \cdot x^{(D_{p-1}\cdot \frac{k(k+1)}{2}) \bmod (p-1)}$; then $D \mathrel{*}= k+1$ in both moduli. $\frac{k(k+1)}{2} \le 5\cdot10^{17}$: reduce it mod $p-1$ before multiplying. $O(n \log p)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll P = 1'000'000'007LL, PH = P - 1;
ll power(ll a, ll e, ll m) {
    ll r = 1 % m; a %= m;
    for (; e; e >>= 1, a = a * a % m) if (e & 1) r = r * a % m;
    return r;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    ll cnt = 1, cntPhi = 1, sum = 1, prod = 1;
    for (int i = 0; i < n; i++) {
        ll x, k; cin >> x >> k;
        sum = sum * ((power(x, k + 1, P) - 1 + P) % P) % P * power(x - 1, P - 2, P) % P;
        ll tri = (k % (2 * PH)) * ((k + 1) % (2 * PH)) / 2 % PH;   // k(k+1)/2 mod (p-1)
        prod = power(prod, k + 1, P) * power(x, cntPhi * tri % PH, P) % P;
        cnt = cnt * ((k + 1) % P) % P;
        cntPhi = cntPhi * ((k + 1) % PH) % PH;
    }
    cout << cnt << ' ' << sum << ' ' << prod << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long P = 1_000_000_007L, PH = P - 1;
    static long power(long a, long e, long m) {
        long r = 1 % m; a %= m;
        for (; e > 0; e >>= 1, a = a * a % m) if ((e & 1) == 1) r = r * a % m;
        return r;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long cnt = 1, cntPhi = 1, sum = 1, prod = 1;
        for (int i = 0; i < n; i++) {
            long x = in.nextLong(), k = in.nextLong();
            sum = sum * ((power(x, k + 1, P) - 1 + P) % P) % P * power(x - 1, P - 2, P) % P;
            long a = k, b = k + 1;                     // k(k+1)/2 mod (p-1): halve the even factor first
            if (a % 2 == 0) a /= 2; else b /= 2;
            long tri = (a % PH) * (b % PH) % PH;
            prod = power(prod, k + 1, P) * power(x, cntPhi * tri % PH, P) % P;
            cnt = cnt * ((k + 1) % P) % P;
            cntPhi = cntPhi * ((k + 1) % PH) % PH;
        }
        System.out.println(cnt + " " + sum + " " + prod);
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

The C++ line computing `tri` relies on $k(k+1)$ being even: with $k < 2(p-1)$ after reduction the product is below $4\cdot10^{18}$, and reducing both factors mod $2(p-1)$ preserves $k(k+1)/2 \bmod (p-1)$. The Java version shows the other standard way: halve the even factor before reducing.

</details>

<!-- test
in:
2
2 2
3 1
out:
6 28 1728
-->
<!-- test
in:
1
2 2
out:
3 7 8
-->
<!-- test
in:
3
2 1000000000
999983 7
5 1
out:
999999911 682211251 181116156
-->

### Example 3 — Primes in a far window (segmented sieve)  ·  ★ ≈1600 (est.)

- **Source:** Original problem
- **Difficulty:** ≈1600 (est.)
- **Problem:** $T \le 10$ queries $1 \le L \le R \le 10^{12}$ with $R - L \le 10^6$. Print the number of primes in $[L, R]$.
- **Thinking from first principles:** A sieve up to $10^{12}$ is impossible; trial division of $10^6$ numbers by up to $78\,498$ primes is $8\cdot10^{10}$. But every composite in the window has a prime factor $\le 10^6$, and each such prime hits the window $\approx (R-L)/p$ times: $\sum_p (R - L)/p \approx 3\cdot10^6$. Sieve the small primes once, then mark multiples inside each window.

<details><summary>Solution</summary>

Precompute primes $\le 10^6$. For each query and each prime $p$ with $p^2 \le R$, mark from $\max(p^2, \lceil L/p\rceil p)$ in steps of $p$. Unmark $1$ if $L = 1$. $O(T\cdot((R-L)\log\log R + \pi(\sqrt R)))$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    const int LIM = 1'000'000;
    vector<bool> comp(LIM + 1, false);
    vector<int> primes;
    for (int i = 2; i <= LIM; i++) {
        if (comp[i]) continue;
        primes.push_back(i);
        for (long long j = 1LL * i * i; j <= LIM; j += i) comp[j] = true;
    }
    int T; cin >> T;
    while (T--) {
        long long L, R; cin >> L >> R;
        vector<char> is(R - L + 1, 1);
        for (long long p : primes) {
            if (p * p > R) break;
            for (long long x = max(p * p, (L + p - 1) / p * p); x <= R; x += p) is[x - L] = 0;
        }
        if (L == 1) is[0] = 0;
        cout << count(is.begin(), is.end(), 1) << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        final int LIM = 1_000_000;
        boolean[] comp = new boolean[LIM + 1];
        int[] primes = new int[80_000]; int pc = 0;
        for (int i = 2; i <= LIM; i++) {
            if (comp[i]) continue;
            primes[pc++] = i;
            for (long j = (long) i * i; j <= LIM; j += i) comp[(int) j] = true;
        }
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int T = in.nextInt();
        while (T-- > 0) {
            long L = in.nextLong(), R = in.nextLong();
            boolean[] notPrime = new boolean[(int) (R - L + 1)];
            for (int j = 0; j < pc; j++) {
                long p = primes[j];
                if (p * p > R) break;
                for (long x = Math.max(p * p, (L + p - 1) / p * p); x <= R; x += p) notPrime[(int) (x - L)] = true;
            }
            if (L == 1) notPrime[0] = true;
            int c = 0;
            for (boolean b : notPrime) if (!b) c++;
            out.println(c);
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
4
1 10
1 1
2 2
1 1000000
out:
4
0
1
78498
-->
<!-- test
in:
2
999999000000 1000000000000
999999999989 999999999989
out:
36400
1
-->

### Example 4 — Orac and LCM  ·  ★ 1600

- **Source:** [CF 1349A · Orac and LCM](https://codeforces.com/problemset/problem/1349/A) — 1600
- **Difficulty:** 1600
- **Problem:** $n \le 10^5$ numbers $a_i \le 2\cdot10^5$. Print $\gcd\lbrace \operatorname{lcm}(a_i, a_j) : i < j\rbrace$.
- **Thinking from first principles:** $n^2/2$ lcms are too many. Work **per prime**: the exponent of $p$ in $\operatorname{lcm}(a_i, a_j)$ is $\max(e_i, e_j)$, and the gcd takes the minimum over pairs. The minimum over pairs of a max is the **second smallest** exponent among all $a_i$ (pair the two smallest; no pair can do better, since a pair's max is at least the second smallest value). Exponent $0$ counts — if two or more $a_i$ are not divisible by $p$, $p$ does not appear.

<details><summary>Solution</summary>

Factor each $a_i$ with $\operatorname{spf}$. For each prime $p$ record the list of positive exponents; the number of elements with exponent $0$ is $n - (\text{list size})$. If at least two have exponent 0 skip $p$; otherwise sort the list and take the second smallest exponent overall (with zeros counted). $O(n\log A + A)$.
(Alternative using §2.3 of the gcd file: $\gcd_{j>i}\operatorname{lcm}(a_i, a_j) = \operatorname{lcm}(a_i, \gcd_{j>i} a_j)$, so the answer is $\gcd_i \operatorname{lcm}(a_i, \text{suffix gcd}_{i+1})$ — $O(n\log A)$ with no factorisation.)

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    const int A = 200000;
    vector<int> spf(A + 1, 0);
    for (int i = 2; i <= A; i++)
        if (!spf[i]) for (int j = i; j <= A; j += i) if (!spf[j]) spf[j] = i;
    int n; cin >> n;
    vector<vector<int>> ex(A + 1);                   // positive exponents per prime
    for (int i = 0; i < n; i++) {
        int x; cin >> x;
        while (x > 1) {
            int p = spf[x], e = 0;
            while (x % p == 0) { x /= p; e++; }
            ex[p].push_back(e);
        }
    }
    long long ans = 1;
    for (int p = 2; p <= A; p++) {
        int zeros = n - (int)ex[p].size();
        if (zeros >= 2) continue;
        sort(ex[p].begin(), ex[p].end());
        int second = (zeros == 1) ? ex[p][0] : ex[p][1];   // second smallest including zeros
        for (int k = 0; k < second; k++) ans *= p;
    }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        final int A = 200000;
        int[] spf = new int[A + 1];
        for (int i = 2; i <= A; i++)
            if (spf[i] == 0) for (int j = i; j <= A; j += i) if (spf[j] == 0) spf[j] = i;
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] min1 = new int[A + 1], min2 = new int[A + 1], cnt = new int[A + 1];   // two smallest positive exponents
        Arrays.fill(min1, Integer.MAX_VALUE); Arrays.fill(min2, Integer.MAX_VALUE);
        for (int i = 0; i < n; i++) {
            int x = in.nextInt();
            while (x > 1) {
                int p = spf[x], e = 0;
                while (x % p == 0) { x /= p; e++; }
                cnt[p]++;
                if (e < min1[p]) { min2[p] = min1[p]; min1[p] = e; } else if (e < min2[p]) min2[p] = e;
            }
        }
        long ans = 1;
        for (int p = 2; p <= A; p++) {
            int zeros = n - cnt[p];
            if (zeros >= 2 || cnt[p] == 0) continue;
            int second = (zeros == 1) ? min1[p] : min2[p];
            for (int k = 0; k < second; k++) ans *= p;
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
2
1 1
out:
1
-->
<!-- test
in:
4
10 24 40 80
out:
40
-->
<!-- test
in:
10
540 648 810 648 720 540 594 864 972 648
out:
54
-->

### Example 5 — Strange Beauty  ·  ★ 1900

- **Source:** [CF 1475G · Strange Beauty](https://codeforces.com/problemset/problem/1475/G) — 1900
- **Difficulty:** 1900
- **Problem:** $t \le 10$ tests; each has $n \le 2\cdot10^5$ numbers $a_i \le 2\cdot10^5$. Remove the minimum number of elements so that for every remaining pair one divides the other.
- **Thinking from first principles:** "Every pair comparable under divisibility" means the remaining *distinct* values form a chain $v_1 \mid v_2 \mid \cdots$, and equal values are free to keep. Maximise $\sum \text{cnt}[v]$ over chains — a longest-path DP on the divisibility DAG: $\text{dp}[x] = \text{cnt}[x] + \max_{d \mid x,\ d < x} \text{dp}[d]$. Enumerating divisors of each $x$ costs $\sum d(x)$; pushing $\text{dp}[x]$ forward to every multiple costs the harmonic sum $A\ln A \approx 2.4\cdot10^6$.

<details><summary>Solution</summary>

Process $x = 1..A$ in increasing order; when $x$ is reached all its divisors are final. `best[y]` holds the max dp over proper divisors of $y$ seen so far. Answer $n - \max_x \text{dp}[x]$. $O(A \log A)$ per test.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    const int A = 200000;
    int t; cin >> t;
    vector<int> cnt(A + 1), dp(A + 1);
    while (t--) {
        int n; cin >> n;
        fill(cnt.begin(), cnt.end(), 0);
        fill(dp.begin(), dp.end(), 0);                // dp[y] first collects max over divisors
        for (int i = 0; i < n; i++) { int x; cin >> x; cnt[x]++; }
        int best = 0;
        for (int x = 1; x <= A; x++) {
            dp[x] += cnt[x];
            best = max(best, dp[x]);
            for (int y = 2 * x; y <= A; y += x) dp[y] = max(dp[y], dp[x]);
        }
        cout << n - best << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        final int A = 200000;
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = in.nextInt();
        int[] cnt = new int[A + 1], dp = new int[A + 1];
        while (t-- > 0) {
            int n = in.nextInt();
            Arrays.fill(cnt, 0); Arrays.fill(dp, 0);
            for (int i = 0; i < n; i++) cnt[in.nextInt()]++;
            int best = 0;
            for (int x = 1; x <= A; x++) {
                dp[x] += cnt[x];
                best = Math.max(best, dp[x]);
                for (int y = 2 * x; y <= A; y += x) if (dp[x] > dp[y]) dp[y] = dp[x];
            }
            out.println(n - best);
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
4
5
7 9 3 14 63
3
2 14 42
4
45 9 3 18
3
2 2 8
out:
2
0
1
0
-->
<!-- test
in:
2
1
200000
6
6 10 15 30 7 7
out:
0
4
-->

---

## 6. Tricks, pitfalls and things to remember

1. **`i * i` overflows `int`** for $i > 46340$ — write `1LL * i * i` (C++) or `(long) i * i` (Java) in the inner-loop start, or loop the outer index only to $\sqrt N$.
2. **Memory:** `int spf[10^7]` is 40 MB; plus $\varphi$, $\mu$ … quickly exceeds 256 MB. Keep only what you need; `vector<bool>`/`BitSet` for primality is $N/8$ bytes.
3. **Java `boolean[]` uses one byte per entry** — `new boolean[10^8]` is 100 MB. Use `long[]` bit-packing or `BitSet` for $N \ge 5\cdot10^7$.
4. **Trial division loop condition** `p * p <= n` with `long long`; and after the loop, a leftover `n > 1` is a prime factor — forgetting it loses the largest prime.
5. **Divisor product / exponents mod $p$**: exponents reduce modulo $p - 1$, and $d(n)/2$ is not an integer for squares (Example 2).
6. **Segmented sieve start** must be $\max(p^2, \lceil L/p \rceil p)$ — starting at $\lceil L/p\rceil p$ alone wrongly marks $p$ itself when $p \in [L, R]$.
7. **$1$ is not prime and $0$ is not prime** — special-case $L \le 1$.
8. **Harmonic loops must start at the right place**: "push to proper multiples" starts at $2x$; "count multiples including itself" starts at $x$.
9. **Per-test resets** of arrays sized by the value range cost $O(A)$ per test; fine for $t \le 10$, fatal for $t = 10^4$ — then reset only touched entries.
10. **Factorising $10^{18}$ by trial division** is $10^9$ steps — use the cube-root trick or Pollard rho.

---

## 7. Going further (toward 2400–2600+)

- **Prime counting $\pi(n)$ for $n \le 10^{11}$–$10^{13}$** — Meissel–Lehmer / Lucy_Hedgehog DP in $O(n^{3/4}/\log n)$ (🔴); Min_25 sieve generalises it to prefix sums of multiplicative functions ([Möbius file](07-mobius-dirichlet-and-floor-sums.md)).
- **Bitset / wheel sieves** reach $10^9$ in about a second (store odd numbers only, segment to L1 cache).
- **Sieving other functions**: smallest/largest prime factor, "sum of prime factors", squarefree kernel; the sieve of *values* (e.g. $\operatorname{spf}$ of $n^2 + 1$ via quadratic residues) is IGM-level.
- **Smooth numbers and the cube-root trick** for $d(n)$, $\omega(n)$ with $n \le 10^{18}$.
- Factorisation for $n \le 10^{18}$: [Miller–Rabin + Pollard rho](06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md).

---

## 8. Practice ladder

**≤ 1400**
- [ ] [CF 230B · T-primes](https://codeforces.com/problemset/problem/230/B) — 1300
- [ ] [CF 26A · Almost Prime](https://codeforces.com/problemset/problem/26/A) — 900
- [ ] [CF 1294C · Product of Three Numbers](https://codeforces.com/problemset/problem/1294/C) — 1300
- [ ] [CF 1360D · Buying Shovels](https://codeforces.com/problemset/problem/1360/D) — 1300
- [ ] [CF 762A · k-th divisor](https://codeforces.com/problemset/problem/762/A) — 1400
- [ ] [CSES 1713 · Counting Divisors](https://cses.fi/problemset/task/1713)

**1400–1900**
- [ ] [CF 1349A · Orac and LCM](https://codeforces.com/problemset/problem/1349/A) — 1600
- [ ] [CF 1165D · Almost All Divisors](https://codeforces.com/problemset/problem/1165/D) — 1600
- [ ] [CF 1225D · Power Products](https://codeforces.com/problemset/problem/1225/D) — 1800
- [ ] [CF 546D · Soldier and Number Game](https://codeforces.com/problemset/problem/546/D) — 1700
- [ ] [CF 385C · Bear and Prime Numbers](https://codeforces.com/problemset/problem/385/C) — 1700
- [ ] [CF 1538D · Another Problem About Dividing Numbers](https://codeforces.com/problemset/problem/1538/D) — 1700
- [ ] [CF 1497E1 · Square-Free Division (easy version)](https://codeforces.com/problemset/problem/1497/E1) — 1700
- [ ] [CSES 2182 · Divisor Analysis](https://cses.fi/problemset/task/2182)

**1900–2400**
- [ ] [CF 1475G · Strange Beauty](https://codeforces.com/problemset/problem/1475/G) — 1900
- [ ] [CF 1366D · Two Divisors](https://codeforces.com/problemset/problem/1366/D) — 2000
- [ ] [CF 27E · Number With The Given Amount Of Divisors](https://codeforces.com/problemset/problem/27/E) — 2000
- [ ] [CF 920F · SUM and REPLACE](https://codeforces.com/problemset/problem/920/F) — 2000
- [ ] [CF 1627D · Not Adding](https://codeforces.com/problemset/problem/1627/D) — 1900
- [ ] [CF 1493D · GCD of an Array](https://codeforces.com/problemset/problem/1493/D) — 2100
- [ ] [CF 1114F · Please, another Queries on Array?](https://codeforces.com/problemset/problem/1114/F) — 2400
- [ ] [CF 1497E2 · Square-Free Division (hard version)](https://codeforces.com/problemset/problem/1497/E2) — 2500

**AtCoder**
- [ ] [AtCoder ABC172 D · Sum of Divisors](https://atcoder.jp/contests/abc172/tasks/abc172_d) — diff≈963
- [ ] [AtCoder ABC177 E · Coprime](https://atcoder.jp/contests/abc177/tasks/abc177_e) — diff≈1057

---

## 9. LeetCode / FAANG cross-reference

- [LC 204 · Count Primes](https://leetcode.com/problems/count-primes/) — Medium — the canonical interview sieve; start crossing at $p^2$.
- [LC 2523 · Closest Prime Numbers in Range](https://leetcode.com/problems/closest-prime-numbers-in-range/) — Medium — sieve then scan adjacent primes.
- [LC 1492 · The kth Factor of n](https://leetcode.com/problems/the-kth-factor-of-n/) — Medium — divisors in $O(\sqrt n)$ by pairing $d$ with $n/d$.
- [LC 1390 · Four Divisors](https://leetcode.com/problems/four-divisors/) — Medium — $d(n) = 4$ iff $n = p^3$ or $n = pq$.
- [LC 2521 · Distinct Prime Factors of Product of Array](https://leetcode.com/problems/distinct-prime-factors-of-product-of-array/) — Medium — factor each element, union of primes.
- [LC 952 · Largest Component Size by Common Factor](https://leetcode.com/problems/largest-component-size-by-common-factor/) — Hard — DSU over prime factors from an $\operatorname{spf}$ sieve.
- [LC 2709 · Greatest Common Divisor Traversal](https://leetcode.com/problems/greatest-common-divisor-traversal/) — Hard — same DSU-on-primes idea.
- [LC 263 · Ugly Number](https://leetcode.com/problems/ugly-number/) — Easy / [LC 264 · Ugly Number II](https://leetcode.com/problems/ugly-number-ii/) — Medium — numbers whose prime factors are in a fixed set.

---

## 10. Self-check

1. Why may Eratosthenes start crossing out at $p^2$, and why can the outer loop stop at $\sqrt N$?
2. State the linear-sieve invariant that makes each composite be marked exactly once.
3. Give $\varphi(ip)$ and $\mu(ip)$ in the two linear-sieve cases.
4. What is $d(720720)$, and what is the largest $d(n)$ for $n \le 10^9$?
5. How many primes does a number $\le 10^{18}$ have at most (distinct)?
6. Product of divisors of $36$? Why can't you compute $36^{d/2}$ with $d/2$ as an integer?
7. In a segmented sieve for $[L, R]$, where does marking for prime $p$ start and why?
8. Why is "for each $x \le 10^6$, loop over its multiples" only $\approx 1.4\cdot10^7$ steps?

<details><summary>Answers</summary>

1. Smaller multiples $kp$ ($k < p$) have a smaller prime factor and are already marked. A composite $\le N$ has a prime factor $\le\sqrt N$, so primes above $\sqrt N$ mark nothing new.
2. Composite $c$ is marked only at the pair $(i, p) = (c/\operatorname{spf}(c), \operatorname{spf}(c))$, which is the unique pair with $p \le \operatorname{spf}(i)$ and $ip = c$.
3. $p \nmid i$: $\varphi(ip) = \varphi(i)(p-1)$, $\mu(ip) = -\mu(i)$. $p \mid i$: $\varphi(ip) = p\varphi(i)$, $\mu(ip) = 0$.
4. $720720 = 2^4\cdot3^2\cdot5\cdot7\cdot11\cdot13$: $5\cdot3\cdot2^4 = 240$. For $n \le 10^9$ the maximum is 1344.
5. 15 (the product of the first 16 primes exceeds $10^{18}$).
6. $d(36) = 9$; product $= 36^{4.5} = 6^9 = 10\,077\,696$. Write it as $\prod p^{e\cdot d/2}$ with integer exponents $e\cdot d/2$ per prime, or build it prime by prime.
7. At $\max(p^2, \lceil L/p\rceil p)$: multiples below $p^2$ have smaller prime factors, and $p$ itself must not be marked.
8. $\sum_{x \le N} N/x = N H_N \approx N\ln N \approx 1.4\cdot10^7$ for $N = 10^6$.

</details>
