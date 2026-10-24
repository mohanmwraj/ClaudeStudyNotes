# 04 — Number Theory Cheat Sheet

Revision only — derivations live in [the number theory folder](../04-Number-Theory/README.md): [gcd](../04-Number-Theory/01-divisibility-gcd-and-extended-euclid.md) · [modular](../04-Number-Theory/02-modular-arithmetic-and-inverses.md) · [sieves](../04-Number-Theory/03-sieves-and-factorization.md) · [totient](../04-Number-Theory/04-euler-phi-fermat-and-euler-theorem.md) · [CRT](../04-Number-Theory/05-crt-and-linear-congruences.md) · [MR / rho / roots](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md) · [Möbius / floor sums](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md) · [problems](../04-Number-Theory/problems.md)

## 1. Core formulas

| Topic | Formula |
|---|---|
| Euclid | $\gcd(a,b) = \gcd(b, a \bmod b)$, $\gcd(a,0) = \lvert a\rvert$; $\le 1.44\log_2\min(a,b)$ steps |
| gcd·lcm | $\gcd(a,b)\operatorname{lcm}(a,b) = ab$; compute $\operatorname{lcm} = a/\gcd\cdot b$ |
| shifts | $\gcd(a_1+x, \dots, a_n+x) = \gcd(a_1+x, a_2-a_1, \dots, a_n - a_1)$ |
| huge indices | $\gcd(F_m,F_n) = F_{\gcd(m,n)}$, $\gcd(a^m-1, a^n-1) = a^{\gcd(m,n)}-1$ |
| subarray gcds | per right end $\le \log_2 A + 1$ distinct values |
| Bézout | $\lbrace ax+by\rbrace = \gcd(a,b)\mathbb Z$; ext. Euclid $(x,y) \leftarrow (y', x' - \lfloor a/b\rfloor y')$ |
| Diophantine | $ax+by=c$ iff $g \mid c$; $x = x_0 + k\frac bg$, $y = y_0 - k\frac ag$ |
| Inverse | exists iff $\gcd(a,m)=1$; Fermat $a^{p-2}$; table $\text{inv}[i] = -\lfloor p/i\rfloor\,\text{inv}[p \bmod i]$ |
| Factorials | $\text{ifact}[i-1] = i\cdot\text{ifact}[i]$; $\binom nk = n!\,k!^{-1}(n-k)!^{-1}$ for $n < p$ |
| Exact division mod $m$ | $(a/b) \bmod m = (a \bmod bm)/b$ when $b \mid a$ |
| Divisor functions | $d = \prod(e_i+1)$, $\sigma = \prod\frac{p^{e+1}-1}{p-1}$, $\prod_{d\mid n} d = n^{d(n)/2}$ |
| Totient | $\varphi(n) = n\prod_{p\mid n}(1 - 1/p)$; $\sum_{d\mid n}\varphi(d) = n$; $\#\lbrace x \le m : \gcd(x,m) = g\rbrace = \varphi(m/g)$ |
| Fermat / Euler | $a^{p-1} \equiv 1$; $a^{\varphi(n)} \equiv 1$ ($\gcd = 1$) |
| Generalised Euler | $a^e \equiv a^{(e \bmod \varphi(m)) + \varphi(m)} \pmod m$ for $e \ge \log_2 m$ |
| Wilson | $(p-1)! \equiv -1 \pmod p$ |
| CRT merge | $g = \gcd(m_1,m_2) \mid a_2 - a_1$; $t = \frac{a_2-a_1}{g}(\frac{m_1}{g})^{-1} \bmod \frac{m_2}{g}$; $x = a_1 + m_1t \bmod \operatorname{lcm}$ |
| Linear congruence | $ax \equiv b \pmod m$: iff $g \mid b$, $x \equiv \frac bg(\frac ag)^{-1} \pmod{\frac mg}$ |
| Order | $\operatorname{ord}(a) \mid \varphi(n)$; $\operatorname{ord}(a^k) = \operatorname{ord}(a)/\gcd(k, \operatorname{ord}(a))$ |
| Primitive root | exists iff $n \in \lbrace 1,2,4,p^k,2p^k\rbrace$; $g$ works iff $g^{\varphi/q} \ne 1$ for all primes $q \mid \varphi$ |
| Euler's criterion | $a^{(p-1)/2} \equiv \left(\frac ap\right)$; $p \equiv 3 \ (4)$: $\sqrt a = a^{(p+1)/4}$ |
| μ | $\sum_{d\mid n}\mu(d) = [n=1]$; $[\gcd(i,j)=1] = \sum_{d\mid i, d\mid j}\mu(d)$ |
| Dirichlet | $\mu*1=\varepsilon$, $\varphi*1=\mathrm{id}$, $\mu*\mathrm{id}=\varphi$, $1*1=d$, $\mathrm{id}*1=\sigma$ |
| Inversion | $g = f*1 \iff f = g*\mu$; multiples: $F(d) = \sum_{d\mid k}\mu(k/d)G(k)$ |
| Coprime pairs | $\sum_d \mu(d)\lfloor n/d\rfloor\lfloor m/d\rfloor$ |
| gcd sums | $\sum_{i\le n}\gcd(i,n) = \sum_{d\mid n}d\varphi(n/d)$; $\sum_{i,j\le n}\gcd = \sum_d\varphi(d)\lfloor n/d\rfloor^2$ |
| Floor blocks | $\le 2\sqrt n$ values; block $[l, r]$, $r = \lfloor n/\lfloor n/l\rfloor\rfloor$; two numerators: min of both |
| Floor identities | $\lfloor\lfloor n/a\rfloor/b\rfloor = \lfloor n/(ab)\rfloor$; $\sum_{i\le n}\sigma(i) = \sum_d d\lfloor n/d\rfloor$ |
| floor_sum | $\sum_{i<n}\lfloor\frac{ai+b}{m}\rfloor$: reduce $a,b$ mod $m$, then $(n,m,a,b) \to (\lfloor\frac{an+b}{m}\rfloor, a, m, (an+b) \bmod m)$ |
| Legendre | $v_p(n!) = \sum_k\lfloor n/p^k\rfloor = \frac{n - s_p(n)}{p-1}$ |
| Kummer | $v_p\binom{m+n}{m}$ = #carries of $m+n$ in base $p$; $\binom nk$ odd iff $k \mathbin\& n = k$ |
| LTE | odd $p \mid x-y$, $p \nmid xy$: $v_p(x^n-y^n) = v_p(x-y)+v_p(n)$ |
| Du's sieve | $\Phi(n) = \frac{n(n+1)}2 - \sum_{d\ge2}\Phi(\lfloor n/d\rfloor)$; $M(n) = 1 - \sum_{d \ge 2}M(\lfloor n/d\rfloor)$; $O(n^{2/3})$ |

## 2. Constants

| Constant | Value |
|---|---|
| $\pi(10^6), \pi(10^7), \pi(10^8), \pi(10^9)$ | 78 498 · 664 579 · 5 761 455 · 50 847 534 |
| max $d(n)$ for $n \le 10^5 / 10^6 / 10^9 / 10^{12} / 10^{18}$ | 128 / 240 / 1344 / 6720 / 103 680 |
| max $\omega(n)$ for $n \le 10^9$ / $10^{18}$ | 9 / 15 |
| max prime gap below $10^9$ / $10^{18}$ | 282 / 1442 |
| $\sum_{i\le n}d(i)$, $\sum_{i\le n}\varphi(i)$ | $\approx n\ln n$, $\approx 3n^2/\pi^2$ |
| NTT prime | $998244353 = 119\cdot2^{23}+1$, root 3 |
| other primes | $10^9+7$ (root 5), $10^9+9$, $2^{61}-1$, $10^{18}+3$, $999999999999999989$ |
| Carmichael | 561, 1105, 1729 |
| MR bases | 64-bit: $\lbrace 2,3,5,7,11,13,17,19,23,29,31,37\rbrace$; 32-bit: $\lbrace 2,7,61\rbrace$ |
| $(10^9+7)^2$ | $\approx 1.0\cdot10^{18} < 2^{63}\approx 9.22\cdot10^{18}$ |

## 3. Signal → technique

| Signal | Technique |
|---|---|
| "modulo $p$", divisions in a formula | inverses, factorial tables |
| exponent astronomically large | reduce mod $p-1$ / $\varphi(m)$ (+$\varphi$ if not coprime) |
| values $\le 10^7$, many factorisations | linear sieve + spf |
| one $n \le 10^{12}$ | trial division to $10^6$ |
| $n \le 10^{18}$ prime / factor | Miller–Rabin + Pollard–Brent |
| primes in $[L, R]$, $R - L \le 10^6$ | segmented sieve |
| "$a_i \mid a_j$", chains, values $\le 10^6$ | harmonic loop over multiples |
| gcd of array after a common shift | gcd of differences |
| count pairs/subsets with $\gcd = 1$ | Möbius over multiples |
| $\sum f(\lfloor n/i\rfloor)$, $n \le 10^{12}$ | floor blocks |
| $\sum\lfloor (ai+b)/m\rfloor$ | floor_sum |
| remainders given, recover $x$ | CRT (merge, check consistency) |
| $a^x \equiv b$ | BSGS (non-coprime: strip gcd first) |
| $x^2 \equiv a$, $x^k \equiv a$ | Euler's criterion, Tonelli–Shanks, primitive root |
| trailing zeros, $v_p(n!)$, parity of $\binom nk$ | Legendre, Kummer, Lucas |

## 4. Templates (C++ then Java)

```cpp
using ll = long long;
ll power(ll a, ll e, ll m) { ll r = 1 % m; a %= m; if (a < 0) a += m; for (; e; e >>= 1, a = a * a % m) if (e & 1) r = r * a % m; return r; }
ll ext_gcd(ll a, ll b, ll &x, ll &y) { if (!b) { x = 1; y = 0; return a; } ll x1, y1, g = ext_gcd(b, a % b, x1, y1); x = y1; y = x1 - a / b * y1; return g; }
ll inv_mod(ll a, ll m) { ll x, y; return ext_gcd(((a % m) + m) % m, m, x, y) == 1 ? ((x % m) + m) % m : -1; }
ll floor_div(ll p, ll q) { return p / q - ((p % q != 0) && ((p < 0) != (q < 0))); }
unsigned long long mulmod(unsigned long long a, unsigned long long b, unsigned long long m) { return (unsigned __int128)a * b % m; }
// CRT merge: returns {x, lcm} or {-1, -1}
pair<ll, ll> crt_merge(ll a1, ll m1, ll a2, ll m2) {
    ll p, q, g = ext_gcd(m1, m2, p, q);
    if ((a2 - a1) % g) return {-1, -1};
    ll mg = m2 / g, t = (ll)((__int128)(((a2 - a1) / g) % mg + mg) % mg * ((p % mg + mg) % mg) % mg);
    ll L = m1 / g * m2;
    return {(ll)(((__int128)a1 + (__int128)m1 * t) % L + L) % L, L};
}
// linear sieve: spf + phi + mu
struct Sieve {
    vector<int> spf, primes, phi, mu;
    Sieve(int n) : spf(n + 1), phi(n + 1), mu(n + 1) {
        phi[1] = mu[1] = 1;
        for (int i = 2; i <= n; i++) {
            if (!spf[i]) { spf[i] = i; primes.push_back(i); phi[i] = i - 1; mu[i] = -1; }
            for (int p : primes) {
                if (p > spf[i] || 1LL * i * p > n) break;
                spf[i * p] = p;
                if (p == spf[i]) { phi[i * p] = phi[i] * p; mu[i * p] = 0; }
                else { phi[i * p] = phi[i] * (p - 1); mu[i * p] = -mu[i]; }
            }
        }
    }
};
unsigned long long floor_sum(unsigned long long n, unsigned long long m, unsigned long long a, unsigned long long b) {
    unsigned long long ans = 0;
    while (true) {
        if (a >= m) { ans += n * (n - 1) / 2 * (a / m); a %= m; }
        if (b >= m) { ans += n * (b / m); b %= m; }
        unsigned long long y = a * n + b;
        if (y < m) break;
        n = y / m; b = y % m; swap(m, a);
    }
    return ans;
}
bool is_prime64(unsigned long long n) {
    if (n < 2) return false;
    for (unsigned long long p : {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37}) if (n % p == 0) return n == p;
    unsigned long long d = n - 1; int s = __builtin_ctzll(d); d >>= s;
    for (unsigned long long a : {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37}) {
        unsigned long long x = 1, b = a, e = d;
        for (; e; e >>= 1, b = mulmod(b, b, n)) if (e & 1) x = mulmod(x, b, n);
        if (x == 1 || x == n - 1) continue;
        bool comp = true;
        for (int r = 1; r < s && comp; r++) { x = mulmod(x, x, n); comp = x != n - 1; }
        if (comp) return false;
    }
    return true;
}
```

```java
static long power(long a, long e, long m) { long r = 1 % m; a %= m; if (a < 0) a += m; for (; e > 0; e >>= 1, a = a * a % m) if ((e & 1) == 1) r = r * a % m; return r; }
static long[] extGcd(long a, long b) { if (b == 0) return new long[]{a, 1, 0}; long[] r = extGcd(b, a % b); return new long[]{r[0], r[2], r[1] - a / b * r[2]}; }
static long invMod(long a, long m) { long[] e = extGcd(Math.floorMod(a, m), m); return e[0] == 1 ? Math.floorMod(e[1], m) : -1; }
static long gcd(long a, long b) { while (b != 0) { long t = a % b; a = b; b = t; } return Math.abs(a); }
// overflow-free a*b mod m for 0 <= a, b < m < 2^63
static long mulmod(long a, long b, long m) {
    long r = 0;
    for (; b > 0; b >>= 1) { if ((b & 1) == 1) r = r >= m - a ? r - (m - a) : r + a; a = a >= m - a ? a - (m - a) : a + a; }
    return r;
}
static long[] crtMerge(long a1, long m1, long a2, long m2) {        // moduli <= ~1e9, lcm fits in long
    long[] e = extGcd(m1, m2); long g = e[0];
    if ((a2 - a1) % g != 0) return null;
    long mg = m2 / g, t = Math.floorMod((a2 - a1) / g, mg) * Math.floorMod(e[1], mg) % mg;
    long L = m1 / g * m2;
    return new long[]{Math.floorMod(a1 + m1 * t, L), L};
}
static int[] spf, phi, mu;
static void sieve(int n) {
    spf = new int[n + 1]; phi = new int[n + 1]; mu = new int[n + 1];
    int[] pr = new int[n + 1]; int pc = 0; phi[1] = mu[1] = 1;
    for (int i = 2; i <= n; i++) {
        if (spf[i] == 0) { spf[i] = i; pr[pc++] = i; phi[i] = i - 1; mu[i] = -1; }
        for (int j = 0; j < pc; j++) {
            int p = pr[j];
            if (p > spf[i] || (long) i * p > n) break;
            spf[i * p] = p;
            if (p == spf[i]) { phi[i * p] = phi[i] * p; mu[i * p] = 0; }
            else { phi[i * p] = phi[i] * (p - 1); mu[i * p] = -mu[i]; }
        }
    }
}
static long floorSum(long n, long m, long a, long b) {
    long ans = 0;
    while (true) {
        if (a >= m) { ans += n * (n - 1) / 2 * (a / m); a %= m; }
        if (b >= m) { ans += n * (b / m); b %= m; }
        long y = a * n + b;
        if (y < m) break;
        n = y / m; b = y % m; long t = m; m = a; a = t;
    }
    return ans;
}
static boolean isPrime64(long n) {                                // uses mulmod above (slow but simple)
    if (n < 2) return false;
    long[] bases = {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37};
    for (long p : bases) if (n % p == 0) return n == p;
    long d = n - 1; int s = Long.numberOfTrailingZeros(d); d >>= s;
    for (long a : bases) {
        long x = 1, b = a, e = d;
        for (; e > 0; e >>= 1, b = mulmod(b, b, n)) if ((e & 1) == 1) x = mulmod(x, b, n);
        if (x == 1 || x == n - 1) continue;
        boolean comp = true;
        for (int r = 1; r < s && comp; r++) { x = mulmod(x, x, n); comp = x != n - 1; }
        if (comp) return false;
    }
    return true;
}
```

Floor-block loop (both languages, same shape):

```cpp
long long sum_floor(long long n) {            // sum_{i=1..n} floor(n / i)
    long long s = 0;
    for (long long l = 1, r; l <= n; l = r + 1) { long long q = n / l; r = n / q; s += (r - l + 1) * q; }
    return s;
}
```

```java
static long sumFloor(long n) {
    long s = 0;
    for (long l = 1, r; l <= n; l = r + 1) { long q = n / l; r = n / q; s += (r - l + 1) * q; }
    return s;
}
```

For fast 64-bit Miller–Rabin / Pollard–Brent in Java use the Montgomery class from [file 06](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md).

## 5. Complexities

| Operation | Cost |
|---|---|
| gcd, ext. gcd, inverse, CRT merge | $O(\log)$ |
| $a^e \bmod m$ | $O(\log e)$ multiplications |
| Eratosthenes / linear sieve to $N$ | $O(N\log\log N)$ / $O(N)$ |
| factor via spf | $O(\log n)$ |
| trial division | $O(\sqrt n)$ |
| Miller–Rabin 64-bit | 12 exponentiations |
| Pollard–Brent | expected $O(n^{1/4})$ per split |
| BSGS | $O(\sqrt m)$ time and memory |
| Tonelli–Shanks | $O(\log^2 p)$ |
| floor blocks | $O(\sqrt n)$ |
| floor_sum | $O(\log m)$ |
| Du's sieve | $O(n^{2/3})$ |

## 6. Top 10 mistakes

1. `a * b % m` with `int` operands — overflow before `%`. Use `1LL *` / `long`.
2. `%` of a negative number is negative in C++ and Java — normalise with `((x % m) + m) % m` / `Math.floorMod`.
3. `/` truncates toward zero — use `floor_div` / `Math.floorDiv` in Diophantine and CRT counting.
4. Reducing an exponent mod $p$ instead of mod $p - 1$; forgetting the $a \equiv 0$ case.
5. lcm computed as `a * b / g` — overflow; and lcm of many numbers exploding past $10^{18}$.
6. Factorial tables used with $n \ge p$ (small primes) — need Lucas.
7. Forgetting the leftover prime `if (n > 1)` after trial division.
8. Segmented sieve starting at $\lceil L/p\rceil p$ instead of $\max(p^2, \cdot)$ — marks $p$ itself.
9. 64-bit modulus without `__int128` / Montgomery — silent garbage in Miller–Rabin.
10. Naming a C++ helper `legendre` (or `beta`) under `using namespace std;` — `std::legendre` hijacks `int` calls.

## 7. Last minute before the contest

- Paste-ready: `power`, `inv`, factorial tables (size $\ge$ max $n$ + a few), `Sieve`, `crt_merge`, `floor_sum`, MR + rho.
- Decide the modulus type once (`const long long MOD`); never mix `int` residues with products.
- For "answer modulo $p$" problems, write a brute force for $n \le 8$ and compare residues — it catches missing inverses and off-by-one factorial bounds.
- If the statement has $10^{12}$ and a sum of floors: floor blocks. If $10^{18}$ and primes: MR + rho.
- Java: no `Math.gcd`, `StreamTokenizer` loses precision above $2^{53}$, `HashMap<Long,Long>` is slow beyond $10^6$ entries.
