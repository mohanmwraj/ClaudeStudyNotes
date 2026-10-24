# 05 — Combinatorics and Probability Cheat Sheet

Revision only — derivations in [the combinatorics folder](../05-Combinatorics-and-Probability/README.md): [binomials](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) · [stars and bars](../05-Combinatorics-and-Probability/02-stars-and-bars-and-multisets.md) · [IE](../05-Combinatorics-and-Probability/03-inclusion-exclusion.md) · [Catalan / Stirling](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md) · [Burnside](../05-Combinatorics-and-Probability/05-burnside-and-polya.md) · [probability](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md) · [contribution](../05-Combinatorics-and-Probability/07-contribution-technique.md) · [problems](../05-Combinatorics-and-Probability/problems.md)

## 1. Binomial identities

| Identity | Formula |
|---|---|
| definition | $\binom nk = \frac{n!}{k!(n-k)!}$, $0$ outside $0 \le k \le n$ |
| Pascal / symmetry | $\binom nk = \binom{n-1}{k-1} + \binom{n-1}k$; $\binom nk = \binom n{n-k}$ |
| absorption | $k\binom nk = n\binom{n-1}{k-1}$ |
| trinomial revision | $\binom nm\binom mk = \binom nk\binom{n-k}{m-k}$ |
| row sums | $\sum_k\binom nk = 2^n$, $\sum(-1)^k\binom nk = [n=0]$, $\sum k\binom nk = n2^{n-1}$, $\sum k^2\binom nk = n(n+1)2^{n-2}$ |
| Vandermonde | $\sum_i\binom mi\binom n{k-i} = \binom{m+n}k$; $\sum\binom nk^2 = \binom{2n}n$ |
| hockey stick | $\sum_{i=r}^n\binom ir = \binom{n+1}{r+1}$; $\sum_{k\le m}\binom{n+k}k = \binom{n+m+1}m$ |
| upper negation | $\binom{-n}k = (-1)^k\binom{n+k-1}k$ |
| Fibonacci diagonal | $\sum_k\binom{n-k}k = F_{n+1}$ |
| multinomial | $\frac{n!}{\prod c_i!}$ |
| Lucas | $\binom nk \equiv \prod\binom{n_i}{k_i} \pmod p$ (base-$p$ digits); odd iff $k \mathbin\& n = k$ |
| Kummer | $v_p\binom{m+n}m$ = carries of $m + n$ in base $p$ |
| exact 64-bit | all $\binom nk$ with $n \le 66$ (signed), $n \le 67$ (unsigned) |
| big $n$, small $k$ | $\binom nk = \prod_{i<k}(n-i)/k!$ mod $p$ (needs $k < p$) |

## 2. Distributions (twelvefold way, $n$ balls, $k$ boxes)

| balls / boxes | any | ≤ 1 | ≥ 1 |
|---|---|---|---|
| distinct / distinct | $k^n$ | $k^{\underline n}$ | $k!S(n,k)$ |
| identical / distinct | $\binom{n+k-1}{k-1}$ | $\binom kn$ | $\binom{n-1}{k-1}$ |
| distinct / identical | $\sum_{j\le k}S(n,j)$ | $[n\le k]$ | $S(n,k)$ |
| identical / identical | $\sum_{j\le k}p(n,j)$ | $[n \le k]$ | $p(n,k)$ |

| Variant | Formula |
|---|---|
| $\sum x_i \le n$ | $\binom{n+k}k$ |
| $x_i \ge l_i$ | $\binom{n-\sum l_i+k-1}{k-1}$ |
| $0 \le x_i \le c$ | $\sum_j(-1)^j\binom kj\binom{n-j(c+1)+k-1}{k-1}$ |
| non-decreasing length $m$ over $[1,n]$ | $\binom{n+m-1}m$; strictly increasing $\binom nm$ |
| $m$ positions in $[1,n]$, gaps $\ge d$ | $\binom{n-(m-1)(d-1)}m$ |
| compositions of $n$ | $2^{n-1}$; into $k$ parts $\binom{n-1}{k-1}$ |
| lattice paths $(0,0)\to(a,b)$ | $\binom{a+b}a$ |

## 3. Inclusion–exclusion and friends

| Formula | |
|---|---|
| none of $A_i$ | $\sum_S(-1)^{\lvert S\rvert}\lvert\bigcap_SA_i\rvert$ |
| exactly $k$ | $E_k = \sum_{j\ge k}(-1)^{j-k}\binom jkS_j$ |
| binomial inversion | $g(k) = \sum_{t\ge k}\binom tkf(t) \iff f(k) = \sum_{t\ge k}(-1)^{t-k}\binom tkg(t)$ |
| subset Möbius | $f(S) = \sum_{T\subseteq S}(-1)^{\lvert S\setminus T\rvert}g(T)$ |
| derangements | $D_n = n!\sum\frac{(-1)^j}{j!} = (n-1)(D_{n-1}+D_{n-2}) = nD_{n-1}+(-1)^n$ |
| exactly $k$ fixed points | $\binom nkD_{n-k}$ |
| surjections | $\sum_j(-1)^j\binom kj(k-j)^n = k!S(n,k)$ |
| obstacle paths | $\text{dp}_i = \text{paths}(s,o_i) - \sum_{j\prec i}\text{dp}_j\,\text{paths}(o_j,o_i)$ |
| max exactly $M$ | $M^n - (M-1)^n$ |
| min–max IE | $E[\max] = \sum_{T\ne\emptyset}(-1)^{\lvert T\rvert+1}E[\min T]$ |

## 4. Special numbers

| Family | Formula / recurrence | First values |
|---|---|---|
| Catalan | $\frac1{n+1}\binom{2n}n = \binom{2n}n - \binom{2n}{n+1}$; $C_{n+1} = \sum C_iC_{n-i}$ | 1, 1, 2, 5, 14, 42, 132, 429, 1430 |
| prefix-balanced ($n$ open, $m$ close) | $\binom{n+m}m - \binom{n+m}{m-1}$ | |
| height $h \to 0$ in $r$ steps, $\ge 0$ | $\binom rd - \binom r{d+1}$, $d = \frac{r+h}2$ | |
| ballot ($a>b$, always ahead) | $\frac{a-b}{a+b}\binom{a+b}a$ | |
| Stirling 2nd $S(n,k)$ | $S(n-1,k-1) + kS(n-1,k)$; $x^n = \sum S(n,k)x^{\underline k}$ | $S(n,2) = 2^{n-1}-1$ |
| Stirling 1st $c(n,k)$ | $c(n-1,k-1) + (n-1)c(n-1,k)$; $x^{\overline n} = \sum c(n,k)x^k$ | $c(n,1) = (n-1)!$ |
| Bell | $B_{n+1} = \sum\binom nkB_k$ | 1, 1, 2, 5, 15, 52, 203, 877, 4140 |
| partitions | $p(n) = \sum_{k\ge1}(-1)^{k+1}[p(n-\frac{k(3k-1)}2) + p(n-\frac{k(3k+1)}2)]$ | 1, 1, 2, 3, 5, 7, 11, 15, 22, 30, 42 |
| derangements | — | 1, 0, 1, 2, 9, 44, 265 |
| Fibonacci | $F_{2n} = F_n(2F_{n+1}-F_n)$, $F_{2n+1} = F_n^2+F_{n+1}^2$; Cassini $F_{n-1}F_{n+1}-F_n^2 = (-1)^n$ | 0, 1, 1, 2, 3, 5, 8, 13 |
| Narayana / Lah (🧊) | $\frac1n\binom nk\binom n{k-1}$ / $\binom{n-1}{k-1}\frac{n!}{k!}$ | |

## 5. Burnside

| Formula | |
|---|---|
| Burnside | $\#\text{orbits} = \frac1{\lvert G\rvert}\sum_g\lvert\mathrm{Fix}(g)\rvert$; colourings: $\lvert\mathrm{Fix}\rvert = k^{\text{cycles}}$ |
| necklaces | $\frac1n\sum_{d\mid n}\varphi(d)k^{n/d}$ |
| bracelets | $\frac{N + R}2$, $R = k^{(n+1)/2}$ (odd), $\frac{k^{n/2+1}+k^{n/2}}2$ (even) |
| no equal neighbours | $\frac1n\sum_{d\mid n}\varphi(n/d)\bigl((k-1)^d + (-1)^d(k-1)\bigr)$ |
| Lyndon words | $\frac1n\sum_{d\mid n}\mu(d)k^{n/d}$ |
| grid up to rotation | $\frac14(k^{n^2} + 2k^{\lceil n^2/4\rceil} + k^{\lceil n^2/2\rceil})$ |
| cube faces | $\frac1{24}(k^6+3k^4+12k^3+8k^2)$ |

## 6. Probability

| Formula | |
|---|---|
| linearity | $E[\sum X_i] = \sum E[X_i]$ always; $E[I_A] = P(A)$ |
| tail sum | $E[X] = \sum_{k\ge1}P(X\ge k)$ |
| geometric | $E = 1/p$ (from $E = 1 + (1-p)E$) |
| coupon collector | $nH_n$; first $k$ distinct: $\sum_{i<k}\frac n{n-i}$ |
| max of $n$ rolls of $m$-die | $m - \sum_{k<m}(k/m)^n$ |
| uniforms | $E[\min] = \frac1{n+1}$, $E[k\text{-th}] = \frac k{n+1}$ |
| random permutation | fixed points 1, cycles $H_n$, inversions $\frac{n(n-1)}4$, records $H_n$ |
| binomial moments | $E[X^{\underline k}] = n^{\underline k}p^k$ |
| gambler's ruin (fair) | $P = i/N$, $E[T] = i(N-i)$ |
| biased | $P = \frac{1-r^i}{1-r^N}$, $r = q/p$ |
| birthday | first repeat after $\approx\sqrt{\pi n/2}$ |
| mod $p$ | $\frac ab \mapsto ab^{-1}$; never divide by a residue that may be $0$ |

## 7. Contribution

| Quantity | Formula |
|---|---|
| subarrays through $i$ | $i(n-i+1)$ (1-indexed) |
| $\sum$ subarray mins | $\sum a_i(i-L_i)(R_i-i)$; $L$: prev $\le$, $R$: next $<$ |
| $\sum$ subset max (sorted) | $\sum a_i2^i$; min $\sum a_i2^{n-1-i}$; size $k$: $\binom i{k-1}$ / $\binom{n-1-i}{k-1}$ |
| $\sum_{i<j}\lvert a_i-a_j\rvert$ (sorted) | $\sum a_i(2i-n+1)$ |
| $\sum_{i<j}a_ia_j$ | $\frac{S^2-\sum a^2}2$ |
| $\sum_{i<j}a_i\oplus a_j$ | $\sum_b2^bc_b(n-c_b)$ |
| tree pair distances | $\sum_e s_e(n-s_e)$ |

## 8. Signal → technique

| Signal | Technique |
|---|---|
| "number of ways", "mod $998244353$" | factorial tables; find the bijection first |
| identical items into distinct boxes | stars and bars (+ IE for caps) |
| "none / avoid all / every value appears" | inclusion–exclusion (derangements, surjections) |
| "exactly $k$" | binomial inversion from "at least" |
| grid paths with few obstacles | first-obstacle DP |
| brackets, "never below 0", BSTs, triangulations | Catalan / reflection |
| groups of labelled items, cycles, moments $E[X^k]$ | Stirling numbers |
| "up to rotation / reflection" | Burnside |
| "expected number of …" | indicators + linearity |
| "expected steps until …" | geometric / $E = a + bE$ / expectation DP |
| "sum over all subarrays / subsets / pairs" | contribution |
| modulus a small prime / composite | Lucas / prime powers + CRT / Pascal |

## 9. Templates (C++ then Java)

```cpp
const long long MOD = 998244353;
struct Comb {
    vector<long long> f, fi;
    static long long pw(long long a, long long e) { long long r = 1; a %= MOD; if (a < 0) a += MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
    explicit Comb(int n) : f(n + 1), fi(n + 1) {
        f[0] = 1; for (int i = 1; i <= n; i++) f[i] = f[i - 1] * i % MOD;
        fi[n] = pw(f[n], MOD - 2); for (int i = n; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
    }
    long long C(long long n, long long k) const { return (k < 0 || n < 0 || k > n) ? 0 : f[n] * fi[k] % MOD * fi[n - k] % MOD; }
    long long stars(long long n, long long k) const { return k == 0 ? (n == 0) : C(n + k - 1, k - 1); }    // x_i >= 0, sum n
    long long catalan(int n) const { return (C(2 * n, n) - C(2 * n, n + 1) + MOD) % MOD; }
};
long long lucas(long long n, long long k, long long p, const vector<long long> &f, const vector<long long> &fi) {
    long long r = 1;                                   // f, fi: factorials and inverse factorials mod p below p
    while (n || k) { long long a = n % p, b = k % p; if (b > a) return 0; r = r * f[a] % p * fi[b] % p * fi[a - b] % p; n /= p; k /= p; }
    return r;
}
vector<long long> stirling2_row(int n) {             // S(n, 0..n), O(n^2) time, O(n) memory
    vector<long long> S(n + 1, 0); S[0] = 1;
    for (int i = 1; i <= n; i++) { for (int j = i; j >= 1; j--) S[j] = (S[j - 1] + (long long)j * S[j]) % MOD; S[0] = 0; }
    return S;
}
long long sum_subarray_min(const vector<long long> &a) {
    int n = a.size(); vector<int> L(n), R(n), st;
    for (int i = 0; i < n; i++) { while (!st.empty() && a[st.back()] > a[i]) st.pop_back(); L[i] = st.empty() ? -1 : st.back(); st.push_back(i); }
    st.clear();
    for (int i = n - 1; i >= 0; i--) { while (!st.empty() && a[st.back()] >= a[i]) st.pop_back(); R[i] = st.empty() ? n : st.back(); st.push_back(i); }
    long long s = 0; for (int i = 0; i < n; i++) s += a[i] * (i - L[i]) * (long long)(R[i] - i);
    return s;
}
```

```java
static final long MOD = 998244353L;
static long[] f, fi;
static long pw(long a, long e) { long r = 1; a %= MOD; if (a < 0) a += MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
static void build(int n) {
    f = new long[n + 1]; fi = new long[n + 1]; f[0] = 1;
    for (int i = 1; i <= n; i++) f[i] = f[i - 1] * i % MOD;
    fi[n] = pw(f[n], MOD - 2); for (int i = n; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
}
static long C(long n, long k) { return (k < 0 || n < 0 || k > n) ? 0 : f[(int) n] * fi[(int) k] % MOD * fi[(int) (n - k)] % MOD; }
static long stars(long n, long k) { return k == 0 ? (n == 0 ? 1 : 0) : C(n + k - 1, k - 1); }
static long catalan(int n) { return (C(2L * n, n) - C(2L * n, n + 1) + MOD) % MOD; }
static long lucas(long n, long k, long p, long[] fp, long[] fip) {
    long r = 1;
    while (n > 0 || k > 0) { int a = (int) (n % p), b = (int) (k % p); if (b > a) return 0; r = r * fp[a] % p * fip[b] % p * fip[a - b] % p; n /= p; k /= p; }
    return r;
}
static long[] stirling2Row(int n) {
    long[] S = new long[n + 1]; S[0] = 1;
    for (int i = 1; i <= n; i++) { for (int j = i; j >= 1; j--) S[j] = (S[j - 1] + (long) j * S[j]) % MOD; S[0] = 0; }
    return S;
}
static long sumSubarrayMin(long[] a) {
    int n = a.length; int[] L = new int[n], R = new int[n], st = new int[n]; int top = 0;
    for (int i = 0; i < n; i++) { while (top > 0 && a[st[top - 1]] > a[i]) top--; L[i] = top == 0 ? -1 : st[top - 1]; st[top++] = i; }
    top = 0;
    for (int i = n - 1; i >= 0; i--) { while (top > 0 && a[st[top - 1]] >= a[i]) top--; R[i] = top == 0 ? n : st[top - 1]; st[top++] = i; }
    long s = 0; for (int i = 0; i < n; i++) s += a[i] * (i - L[i]) * (long) (R[i] - i);
    return s;
}
```

Necklaces for huge $n$ (divisors with $\varphi$) and the generic group-closure Burnside are in [the Burnside file §3](../05-Combinatorics-and-Probability/05-burnside-and-polya.md); $\binom nk \bmod p^e$ is in [the binomials file §3](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md).

## 10. Top 10 mistakes

1. Factorial table too small ($\binom{n+k-1}{k-1}$ needs $n + k - 1$).
2. `C(n, k)` not returning $0$ for $k < 0$ or $k > n$ — IE and Vandermonde sums break.
3. "$\ge 0$" vs "$\ge 1$" in stars and bars.
4. Dividing by an overcount that is not uniform (symmetric objects) — use Burnside.
5. Factorials mod $p$ with $n \ge p$ — use Lucas.
6. Same tie rule on both sides of a monotonic-stack contribution (double count or miss).
7. Negative values / subtractions mod $p$ without `+ MOD`.
8. $E[XY] = E[X]E[Y]$ or $P(A\cap B) = P(A)P(B)$ without independence.
9. Java: `String.format` without `Locale.US` prints commas; deep recursion on trees; `int` overflow in `i * j`.
10. Forgetting $D_0 = 1$, $C_0 = 1$, $S(0,0) = 1$, $p(0) = 1$ base cases.

## 11. Last minute before the contest

- Paste `Comb` with $N = 2\cdot10^6$ (or the problem's max $n + k$) and the modulus from the statement ($998244353$ vs $10^9+7$!).
- For every counting formula: brute force $n \le 7$ in 2 minutes and compare.
- Recognise small sequences: $1,2,5,14$ (Catalan), $1,2,5,15$ (Bell), $1,3,7,15$ ($2^n-1$), $0,1,2,9,44$ (derangements), $1,2,3,5,7,11$ (partitions).
- Expected value asked as $P\cdot Q^{-1}$: do everything in residues from the start; keep a double-precision brute to sanity-check.
- "Sum over all …" — ask "how many structures contain this element?" before anything else.
