# Inclusion–Exclusion, Derangements and Binomial Inversion

> **Band:** 🔵 1500 – 🟠 2400 · **Priority:** 🔥 · **FAANG:** low · **Prerequisites:** [binomials](01-counting-principles-and-binomials.md), [bitmasks](../01-Foundations/03-bit-manipulation.md)
> **You can say you know this when:** you can prove inclusion–exclusion with indicator functions, derive the derangement formula and recurrence, count surjections, convert "at least" counts into "exactly" counts by binomial inversion, and apply IE over subsets with overflow-safe pruning.

---

## 1. First principles — why this works

### 1.1 The problem IE solves

We want the number of objects with **none** of several "bad" properties $A_1, \dots, A_m$, but the only thing we can count easily is objects that have **all** properties in a given set $S$ (e.g. "divisible by every prime in $S$", "these $j$ variables exceed their caps", "these cells are on the path"). Subtracting $\sum\lvert A_i\rvert$ removes objects with two properties twice; adding back $\sum\lvert A_i \cap A_j\rvert$ re-adds objects with three properties too often, and so on. The alternating pattern is forced, and it is exact:

$$\Bigl\lvert \overline{A_1}\cap\cdots\cap\overline{A_m}\Bigr\rvert = \sum_{S \subseteq [m]} (-1)^{\lvert S\rvert}\,\Bigl\lvert \bigcap_{i\in S} A_i\Bigr\rvert \qquad (\textstyle\bigcap_{\emptyset} = \text{everything}).$$

### 1.2 Proof with indicators (the version worth remembering)

For an object $x$, let $[x \in A_i]$ be $1$ or $0$. Then $[x \text{ has no property}] = \prod_i (1 - [x \in A_i])$. Expanding the product over choices of "$1$" or "$-[x \in A_i]$" from each factor:

$$\prod_{i=1}^{m}(1 - [x\in A_i]) = \sum_{S\subseteq[m]}(-1)^{\lvert S\rvert}\prod_{i\in S}[x \in A_i] = \sum_S (-1)^{\lvert S\rvert}\Bigl[x \in \bigcap_{i\in S}A_i\Bigr].$$

Sum over all objects $x$ and swap the sums: that is the formula. Equivalently, an object with exactly $t \ge 1$ properties is counted $\sum_{j=0}^{t}(-1)^j\binom tj = (1-1)^t = 0$ times, and an object with none is counted once.

The same proof works with **weights** (sum of $w(x)$ instead of counts) and with **probabilities**, and it explains the Möbius function: $\mu$ is IE over the set of primes dividing a number ([Möbius §1.1](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md)).

### 1.3 Derangements — the model application

A **derangement** is a permutation with no fixed point. Let $A_i$ = "position $i$ is fixed". Fixing a set $S$ of $j$ positions leaves $(n-j)!$ permutations, and there are $\binom nj$ such sets:

$$D_n = \sum_{j=0}^{n}(-1)^j\binom nj(n-j)! = n!\sum_{j=0}^{n}\frac{(-1)^j}{j!} \;\approx\; \frac{n!}{e}.$$

**Recurrence (direct proof).** In a derangement of $1..n$, element $n$ goes to some position $i \ne n$ ($n - 1$ choices). Either element $i$ goes to position $n$ (a swap; the other $n - 2$ elements form a derangement: $D_{n-2}$), or it does not — then "element $i$ must avoid position $n$" plays the role of "avoid its own position", and the $n - 1$ elements other than $n$ form a derangement: $D_{n-1}$. Hence

$$D_n = (n-1)(D_{n-1} + D_{n-2}), \qquad D_0 = 1,\ D_1 = 0, \qquad\text{and also}\quad D_n = nD_{n-1} + (-1)^n .$$

### 1.4 "At least" versus "exactly": binomial inversion

Often we can count $g(k)$ = "objects together with a chosen set of $k$ properties they satisfy" (an object with exactly $t$ properties is counted $\binom tk$ times), but we want $f(k)$ = "objects with *exactly* $k$ properties". The relation is $g(k) = \sum_{t \ge k}\binom tk f(t)$, and it inverts as

$$f(k) = \sum_{t\ge k}(-1)^{t-k}\binom tk\,g(t).$$

*Proof.* Substitute $g$: $\sum_t(-1)^{t-k}\binom tk\sum_{s}\binom st f(s) = \sum_s f(s)\binom sk\sum_{t}(-1)^{t-k}\binom{s-k}{t-k} = \sum_s f(s)\binom sk[s = k]$, using $\binom tk\binom st = \binom sk\binom{s-k}{t-k}$ and $(1-1)^{s-k}$. ∎ Plain IE is the case $k = 0$.

The subset version (**Möbius inversion on the Boolean lattice**): if $g(S) = \sum_{T \subseteq S} f(T)$ then $f(S) = \sum_{T\subseteq S}(-1)^{\lvert S \setminus T\rvert}g(T)$, because $\sum_{U \subseteq T \subseteq S}(-1)^{\lvert S\setminus T\rvert} = [U = S]$. Computing it for all $S$ at once is the inverse SOS transform, $O(m 2^m)$ ([SOS DP](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md)).

---

## 2. Formulas, definitions and identities

| Formula | Meaning / proof sketch |
|---|---|
| $\lvert A\cup B\rvert = \lvert A\rvert + \lvert B\rvert - \lvert A\cap B\rvert$ | two sets |
| $\lvert\bigcup A_i\rvert = \sum_{\emptyset\ne S}(-1)^{\lvert S\rvert+1}\lvert\bigcap_S A_i\rvert$ | complement of §1.1 |
| $E_k = \sum_{j\ge k}(-1)^{j-k}\binom jk S_j$, $S_j = \sum_{\lvert S\rvert=j}\lvert\bigcap_S A_i\rvert$ | exactly $k$ properties (Jordan); §1.4 |
| Bonferroni: truncating the IE sum after an odd (even) number of terms gives an upper (lower) bound for the union | alternating partial sums of $(1-1)^t$ (🧊) |
| $D_n = n!\sum_{j=0}^n\frac{(-1)^j}{j!}$; $D_n = \operatorname{round}(n!/e)$ for $n \ge 1$ | §1.3 |
| $D_n = (n-1)(D_{n-1}+D_{n-2})$; $D_n = nD_{n-1} + (-1)^n$ | §1.3 |
| permutations with exactly $k$ fixed points | $\binom nk D_{n-k}$ |
| surjections $[n] \to [k]$ | $\operatorname{surj}(n,k) = \sum_{j=0}^{k}(-1)^j\binom kj(k-j)^n = k!\,S(n,k)$ — $A_i$ = "value $i$ unused" |
| arrays of length $n$ over $m$ symbols using exactly $k$ distinct | $\binom mk\operatorname{surj}(n,k)$ |
| $\#\lbrace x \le N : \gcd(x, n) = 1\rbrace$ | $\sum_{S \subseteq \text{primes}(n)}(-1)^{\lvert S\rvert}\lfloor N/\prod_S p\rfloor$ |
| $\varphi(n) = n\prod_{p\mid n}(1 - 1/p)$ | the previous line with $N = n$; the alternating sum factors |
| bounded stars and bars | $\sum_j(-1)^j\binom kj\binom{n - j(c+1)+k-1}{k-1}$ ([stars and bars](02-stars-and-bars-and-multisets.md)) |
| grid paths avoiding obstacles (sorted) | $\text{dp}_i = \text{paths}(s \to o_i) - \sum_{j \prec i}\text{dp}_j\cdot\text{paths}(o_j \to o_i)$ — "first obstacle hit" is $o_i$ |
| binomial inversion | $g(k) = \sum_{t\ge k}\binom tk f(t) \iff f(k) = \sum_{t \ge k}(-1)^{t-k}\binom tk g(t)$ |
| subset Möbius | $g(S) = \sum_{T\subseteq S}f(T) \iff f(S) = \sum_{T\subseteq S}(-1)^{\lvert S\setminus T\rvert}g(T)$ |
| min–max IE (🧊) | $\max(S) = \sum_{\emptyset\ne T\subseteq S}(-1)^{\lvert T\rvert+1}\min(T)$; by linearity $E[\max] = \sum(-1)^{\lvert T\rvert+1}E[\min T]$ |
| "max of the array is exactly $M$" | $M^n - (M-1)^n$ (all $\le M$ minus all $\le M - 1$) — the simplest IE |

**Complexity.** Plain IE over $m$ properties is $O(2^m)$ times the cost of one intersection; DFS over sets with pruning (stop when the intersection is empty, e.g. product $> N$) is usually far faster. Symmetric properties collapse the sum to $O(m)$ terms.

---

## 3. Implementation (C++ and Java)

```cpp
// IE over primes with pruning, derangements, surjections, binomial inversion, subset Mobius transform.
// count x in [1, N] divisible by at least one of the given primes (N <= 1e18)
long long count_divisible_any(long long N, const vector<long long> &pr) {
    long long res = 0;
    function<void(int, long long, int)> dfs = [&](int i, long long prod, int cnt) {
        if (i == (int)pr.size()) { if (cnt) res += (cnt & 1 ? 1 : -1) * (N / prod); return; }
        dfs(i + 1, prod, cnt);                                   // skip prime i
        if (prod <= N / pr[i]) dfs(i + 1, prod * pr[i], cnt + 1); // take it (prune: product > N contributes 0)
    };
    dfs(0, 1, 0);
    return res;
}
const long long MOD = 1'000'000'007LL;
vector<long long> derangements(int n) {               // D[0..n] mod MOD
    vector<long long> D(n + 1, 0);
    D[0] = 1;
    for (int i = 2; i <= n; i++) D[i] = (long long)(i - 1) * ((D[i - 1] + D[i - 2]) % MOD) % MOD;
    return D;
}
long long power(long long a, long long e) { long long r = 1; a %= MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
long long surjections(long long n, int k, const vector<long long> &C_k) {   // C_k[j] = C(k, j) mod MOD
    long long res = 0;
    for (int j = 0; j <= k; j++) {
        long long term = C_k[j] * power(k - j, n) % MOD;
        res = (j & 1) ? (res - term + MOD) % MOD : (res + term) % MOD;
    }
    return res;
}
// exactly-k from at-least-k: f[k] = sum_{t >= k} (-1)^{t-k} C(t, k) g[t]; C is a Pascal table mod MOD
vector<long long> binomial_inversion(const vector<long long> &g, const vector<vector<long long>> &C) {
    int m = g.size();
    vector<long long> f(m, 0);
    for (int k = 0; k < m; k++)
        for (int t = k; t < m; t++) {
            long long term = C[t][k] * g[t] % MOD;
            f[k] = ((t - k) & 1) ? (f[k] - term + MOD) % MOD : (f[k] + term) % MOD;
        }
    return f;
}
// in place: g[S] = sum_{T subset S} f[T]  ->  f[S]  (inverse zeta / Mobius on subsets), O(m 2^m)
void subset_mobius(vector<long long> &a, int m) {
    for (int b = 0; b < m; b++)
        for (int S = 0; S < (1 << m); S++)
            if (S >> b & 1) a[S] = (a[S] - a[S ^ (1 << b)] + MOD) % MOD;
}
```

```java
// IE over primes with pruning, derangements, surjections, binomial inversion, subset Mobius transform.
static long N0; static long[] PR; static long resIE;
static void dfsIE(int i, long prod, int cnt) {
    if (i == PR.length) { if (cnt > 0) resIE += ((cnt & 1) == 1 ? 1 : -1) * (N0 / prod); return; }
    dfsIE(i + 1, prod, cnt);
    if (prod <= N0 / PR[i]) dfsIE(i + 1, prod * PR[i], cnt + 1);
}
static long countDivisibleAny(long N, long[] primes) { N0 = N; PR = primes; resIE = 0; dfsIE(0, 1, 0); return resIE; }
static final long MOD = 1_000_000_007L;
static long[] derangements(int n) {
    long[] D = new long[n + 1];
    D[0] = 1;
    for (int i = 2; i <= n; i++) D[i] = (long) (i - 1) * ((D[i - 1] + D[i - 2]) % MOD) % MOD;
    return D;
}
static long power(long a, long e) { long r = 1; a %= MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
static long surjections(long n, int k, long[] Ck) {
    long res = 0;
    for (int j = 0; j <= k; j++) {
        long term = Ck[j] * power(k - j, n) % MOD;
        res = (j & 1) == 1 ? (res - term + MOD) % MOD : (res + term) % MOD;
    }
    return res;
}
static long[] binomialInversion(long[] g, long[][] C) {
    int m = g.length; long[] f = new long[m];
    for (int k = 0; k < m; k++)
        for (int t = k; t < m; t++) {
            long term = C[t][k] * g[t] % MOD;
            f[k] = ((t - k) & 1) == 1 ? (f[k] - term + MOD) % MOD : (f[k] + term) % MOD;
        }
    return f;
}
static void subsetMobius(long[] a, int m) {
    for (int b = 0; b < m; b++)
        for (int S = 0; S < (1 << m); S++)
            if ((S >> b & 1) == 1) a[S] = (a[S] - a[S ^ (1 << b)] + MOD) % MOD;
}
```

---

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "none of", "avoid all", "no element in its original place" | complement + IE over the bad events |
| "every value appears at least once", "every row/column has a …" | IE over the values/rows that are **missing** (surjections, Example 5) |
| constraints are easy when *forced* but hard when *forbidden* | IE: forcing is a lower bound or a fixed choice |
| $k \le 20$ conditions (primes, caps, special cells) | IE over subsets of $2^k$ |
| "exactly $k$" with a natural "at least these $k$" count | binomial inversion |
| a grid / DAG with few forbidden points | sort them; DP on "first forbidden point hit" (Example 4) |
| counting coprime numbers to a fixed $n$ up to $N$ | IE over primes of $n$ (or $\mu$) |
| symmetric bad events (all intersections of size $j$ equal) | collapse to $\sum_j(-1)^j\binom mj c_j$ |

Confusion: IE gives *exact* answers — if your intersection counts are approximations (e.g. probabilities assumed independent), the alternating sum can blow up.

---

## 5. Worked examples (graded)

### Example 1 — Prime Multiples  ·  ★ ≈1600 (est.)

- **Source:** [CSES 2185 · Prime Multiples](https://cses.fi/problemset/task/2185)
- **Difficulty:** ≈1600 (est.)
- **Problem:** Given $n \le 10^{18}$ and $k \le 20$ distinct primes $a_i \le n$, count integers in $[1, n]$ divisible by at least one $a_i$.
- **Thinking from first principles:** "Divisible by all primes in $S$" means divisible by their product (distinct primes), which has $\lfloor n/\prod_S a_i\rfloor$ multiples. Union by IE: $\sum_{S \ne\emptyset}(-1)^{\lvert S\rvert+1}\lfloor n/\prod_S a_i\rfloor$. Products overflow 64-bit quickly — but once a product exceeds $n$ the term is $0$ and so is every superset's, so prune (check `prod > n / a` before multiplying).

<details><summary>Solution</summary>

DFS over subsets with pruning. Worst case $2^{20}$ subsets, each $O(1)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
ll n, res = 0; int k; vector<ll> a;
void dfs(int i, ll prod, int cnt) {
    if (i == k) { if (cnt) res += (cnt & 1 ? 1 : -1) * (n / prod); return; }
    dfs(i + 1, prod, cnt);
    if (prod <= n / a[i]) dfs(i + 1, prod * a[i], cnt + 1);
}
int main() {
    cin >> n >> k;
    a.resize(k);
    for (auto &x : a) cin >> x;
    dfs(0, 1, 0);
    cout << res << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long n, res = 0; static int k; static long[] a;
    static void dfs(int i, long prod, int cnt) {
        if (i == k) { if (cnt > 0) res += ((cnt & 1) == 1 ? 1 : -1) * (n / prod); return; }
        dfs(i + 1, prod, cnt);
        if (prod <= n / a[i]) dfs(i + 1, prod * a[i], cnt + 1);
    }
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        n = Long.parseLong(st.nextToken()); k = Integer.parseInt(st.nextToken());
        a = new long[k];
        st = new StringTokenizer(br.readLine());
        for (int i = 0; i < k; i++) a[i] = Long.parseLong(st.nextToken());
        dfs(0, 1, 0);
        System.out.println(res);
    }
}
```

</details>

<!-- test
in:
20 2
2 5
out:
12
-->
<!-- test
in:
1 1
2
out:
0
-->
<!-- test
in:
1000000000000000000 3
2 3 5
out:
733333333333333334
-->
<!-- test
in:
1000000000000000000 20
2 3 5 7 11 13 17 19 23 29 31 37 41 43 47 53 59 61 67 71
out:
872202319624080142
-->

### Example 2 — Christmas Party (derangements)  ·  ★ ≈1500 (est.)

- **Source:** [CSES 1717 · Christmas Party](https://cses.fi/problemset/task/1717)
- **Difficulty:** ≈1500 (est.)
- **Problem:** $n \le 10^6$ children each bring a gift; count assignments where every child receives one gift and nobody gets their own, modulo $10^9+7$.
- **Thinking from first principles:** A gift assignment is a permutation; "nobody gets their own" is "no fixed point". IE over the set of fixed points gives $\sum_j(-1)^j\binom nj(n-j)!$; the recurrence $D_n = (n-1)(D_{n-1} + D_{n-2})$ (§1.3) computes it in $O(n)$ without inverses.

<details><summary>Solution</summary>

$O(n)$ with the recurrence.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    const long long MOD = 1'000'000'007LL;
    int n; cin >> n;
    long long a = 1, b = 0;                     // D_0, D_1
    if (n == 0) { cout << 1 << '\n'; return 0; }
    for (int i = 2; i <= n; i++) { long long c = (long long)(i - 1) * ((a + b) % MOD) % MOD; a = b; b = c; }
    cout << b << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        final long MOD = 1_000_000_007L;
        int n = Integer.parseInt(new BufferedReader(new InputStreamReader(System.in)).readLine().trim());
        long a = 1, b = 0;
        if (n == 0) { System.out.println(1); return; }
        for (int i = 2; i <= n; i++) { long c = (long) (i - 1) * ((a + b) % MOD) % MOD; a = b; b = c; }
        System.out.println(b);
    }
}
```

</details>

<!-- test
in:
4
out:
9
-->
<!-- test
in:
1
out:
0
-->
<!-- test
in:
2
out:
1
-->
<!-- test
in:
1000000
out:
102701088
-->

### Example 3 — Exactly $k$ distinct values (surjections)  ·  ★ ≈1800 (est.)

- **Source:** Original problem
- **Difficulty:** ≈1800 (est.)
- **Problem:** Count arrays of length $n$ with values in $[1, m]$ that use **exactly** $k$ distinct values ($1 \le n, m \le 10^9$, $1 \le k \le \min(m, 10^5)$), modulo $10^9+7$.
- **Thinking from first principles:** Choose the set of values used: $\binom mk$ (big $m$, small $k$ → multiplicative formula). Then count arrays over exactly those $k$ values that use each at least once — surjections. Bad event $A_i$ = "value $i$ is missing"; forcing $j$ values to be missing leaves $(k - j)^n$ arrays: $\operatorname{surj}(n, k) = \sum_j(-1)^j\binom kj(k-j)^n$. If $n < k$ the formula correctly gives $0$.

<details><summary>Solution</summary>

$\binom kj$ from factorials up to $k$; $\binom mk$ by the multiplicative formula; $k + 1$ fast powers. $O(k\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007LL;
ll power(ll a, ll e) { ll r = 1; a %= MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
int main() {
    ll n, m; int k; cin >> n >> m >> k;
    vector<ll> f(k + 1), fi(k + 1);
    f[0] = 1;
    for (int i = 1; i <= k; i++) f[i] = f[i - 1] * i % MOD;
    fi[k] = power(f[k], MOD - 2);
    for (int i = k; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
    ll surj = 0;
    for (int j = 0; j <= k; j++) {
        ll term = f[k] * fi[j] % MOD * fi[k - j] % MOD * power(k - j, n) % MOD;
        surj = (j & 1) ? (surj - term + MOD) % MOD : (surj + term) % MOD;
    }
    ll cmk = fi[k];                                 // C(m, k) = m(m-1)...(m-k+1) / k!
    for (int i = 0; i < k; i++) cmk = cmk * ((m - i) % MOD) % MOD;
    cout << cmk * surj % MOD << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long power(long a, long e) { long r = 1; a %= MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        long n = Long.parseLong(st.nextToken()), m = Long.parseLong(st.nextToken());
        int k = Integer.parseInt(st.nextToken());
        long[] f = new long[k + 1], fi = new long[k + 1];
        f[0] = 1;
        for (int i = 1; i <= k; i++) f[i] = f[i - 1] * i % MOD;
        fi[k] = power(f[k], MOD - 2);
        for (int i = k; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
        long surj = 0;
        for (int j = 0; j <= k; j++) {
            long term = f[k] * fi[j] % MOD * fi[k - j] % MOD * power(k - j, n) % MOD;
            surj = (j & 1) == 1 ? (surj - term + MOD) % MOD : (surj + term) % MOD;
        }
        long cmk = fi[k];
        for (int i = 0; i < k; i++) cmk = cmk * ((m - i) % MOD) % MOD;
        System.out.println(cmk * surj % MOD);
    }
}
```

</details>

<!-- test
in:
3 3 2
out:
18
-->
<!-- test
in:
2 5 3
out:
0
-->
<!-- test
in:
4 2 2
out:
14
-->
<!-- test
in:
1000000000 1000000000 100000
out:
391923733
-->

### Example 4 — Gerald and Giant Chess  ·  ★ 2200

- **Source:** [CF 559C · Gerald and Giant Chess](https://codeforces.com/problemset/problem/559/C) — 2200
- **Difficulty:** 2200
- **Problem:** An $h \times w$ grid ($h, w \le 10^5$) with $n \le 2000$ black cells. Count monotone (right/down) paths from the top-left to the bottom-right corner that avoid all black cells, modulo $10^9+7$. The corners are white.
- **Thinking from first principles:** Grid DP is $10^{10}$ cells. Paths between two cells are a binomial. IE over subsets of black cells is $2^{2000}$ — but classify each bad path by **the first black cell it hits** (sum rule; disjoint classes). Let $\text{dp}_i$ = paths from the start to black cell $i$ that avoid all other black cells. Then $\text{dp}_i = \text{paths}(\text{start}\to i) - \sum_{j}\text{dp}_j\,\text{paths}(j \to i)$ over black cells $j$ that can precede $i$. Treat the target as the last "black cell"; its dp is the answer. This is IE organised as a DP over a sorted order.

<details><summary>Solution</summary>

Sort black cells by $(r, c)$ (any order compatible with reachability), append the target, $O(n^2)$ transitions with $O(1)$ binomials from factorials up to $h + w$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007LL;
ll power(ll a, ll e) { ll r = 1; a %= MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
int main() {
    int h, w, n; cin >> h >> w >> n;
    vector<pair<int, int>> p(n);
    for (auto &[r, c] : p) cin >> r >> c;
    sort(p.begin(), p.end());
    p.push_back({h, w});
    int N = h + w;
    vector<ll> f(N + 1), fi(N + 1);
    f[0] = 1;
    for (int i = 1; i <= N; i++) f[i] = f[i - 1] * i % MOD;
    fi[N] = power(f[N], MOD - 2);
    for (int i = N; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
    auto paths = [&](int dr, int dc) -> ll { return (dr < 0 || dc < 0) ? 0 : f[dr + dc] * fi[dr] % MOD * fi[dc] % MOD; };
    vector<ll> dp(n + 1);
    for (int i = 0; i <= n; i++) {
        dp[i] = paths(p[i].first - 1, p[i].second - 1);
        for (int j = 0; j < i; j++)
            dp[i] = (dp[i] - dp[j] * paths(p[i].first - p[j].first, p[i].second - p[j].second) % MOD + MOD) % MOD;
    }
    cout << dp[n] << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long[] f, fi;
    static long power(long a, long e) { long r = 1; a %= MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
    static long paths(int dr, int dc) { return (dr < 0 || dc < 0) ? 0 : f[dr + dc] * fi[dr] % MOD * fi[dc] % MOD; }
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        int h = Integer.parseInt(st.nextToken()), w = Integer.parseInt(st.nextToken()), n = Integer.parseInt(st.nextToken());
        int[][] p = new int[n + 1][2];
        for (int i = 0; i < n; i++) {
            st = new StringTokenizer(br.readLine());
            p[i][0] = Integer.parseInt(st.nextToken()); p[i][1] = Integer.parseInt(st.nextToken());
        }
        p[n][0] = h; p[n][1] = w;
        Arrays.sort(p, 0, n, (x, y) -> x[0] != y[0] ? Integer.compare(x[0], y[0]) : Integer.compare(x[1], y[1]));
        int N = h + w;
        f = new long[N + 1]; fi = new long[N + 1]; f[0] = 1;
        for (int i = 1; i <= N; i++) f[i] = f[i - 1] * i % MOD;
        fi[N] = power(f[N], MOD - 2);
        for (int i = N; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
        long[] dp = new long[n + 1];
        for (int i = 0; i <= n; i++) {
            dp[i] = paths(p[i][0] - 1, p[i][1] - 1);
            for (int j = 0; j < i; j++)
                dp[i] = (dp[i] - dp[j] * paths(p[i][0] - p[j][0], p[i][1] - p[j][1]) % MOD + MOD) % MOD;
        }
        System.out.println(dp[n]);
    }
}
```

</details>

<!-- test
in:
3 4 2
2 2
2 3
out:
2
-->
<!-- test
in:
100 100 3
15 16
16 15
99 88
out:
545732279
-->
<!-- test
in:
1 1 0
out:
1
-->
<!-- test
in:
3 3 1
2 2
out:
2
-->

### Example 5 — Another Filling the Grid  ·  ★ 2300

- **Source:** [CF 1228E · Another Filling the Grid](https://codeforces.com/problemset/problem/1228/E) — 2300
- **Difficulty:** 2300
- **Problem:** Fill an $n \times n$ grid ($n \le 250$) with integers in $[1, k]$ ($k \le 10^9$) so that every row and every column has minimum $1$ (contains a $1$). Count fillings modulo $10^9+7$.
- **Thinking from first principles:** Two families of conditions — rows and columns — so a double IE over $2^{2n}$ sets is out. Do IE over **rows only** and count the column condition exactly. Fix a set of $i$ rows that are forced to contain no $1$. Columns are then independent: a column has its $i$ cells in $[2, k]$ and $n - i$ cells in $[1, k]$, and must still contain a $1$ (which can only sit in the other $n - i$ rows): $k^{n-i}(k-1)^i - (k-1)^n$ ways (all minus those with no $1$ at all). So

$$\text{ans} = \sum_{i=0}^{n}(-1)^i\binom ni\bigl(k^{n-i}(k-1)^i - (k-1)^n\bigr)^n .$$

<details><summary>Solution</summary>

Precompute powers of $k$ and $k - 1$; $n + 1$ terms each with one fast power. $O(n\log n)$. Note $k = 1$ works ($(k-1)^0 = 1$).

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007LL;
ll power(ll a, ll e) { ll r = 1; a %= MOD; if (a < 0) a += MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
int main() {
    ll n, k; cin >> n >> k;
    vector<vector<ll>> C(n + 1, vector<ll>(n + 1, 0));
    for (int i = 0; i <= n; i++) { C[i][0] = 1; for (int j = 1; j <= i; j++) C[i][j] = (C[i - 1][j - 1] + C[i - 1][j]) % MOD; }
    ll ans = 0, allNoOne = power(k - 1, n);
    for (int i = 0; i <= n; i++) {
        ll col = (power(k, n - i) * power(k - 1, i) % MOD - allNoOne + MOD) % MOD;
        ll term = C[n][i] * power(col, n) % MOD;
        ans = (i & 1) ? (ans - term + MOD) % MOD : (ans + term) % MOD;
    }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long power(long a, long e) { long r = 1; a %= MOD; if (a < 0) a += MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        int n = Integer.parseInt(st.nextToken()); long k = Long.parseLong(st.nextToken());
        long[][] C = new long[n + 1][n + 1];
        for (int i = 0; i <= n; i++) { C[i][0] = 1; for (int j = 1; j <= i; j++) C[i][j] = (C[i - 1][j - 1] + C[i - 1][j]) % MOD; }
        long ans = 0, allNoOne = power(k - 1, n);
        for (int i = 0; i <= n; i++) {
            long col = (power(k, n - i) * power(k - 1, i) % MOD - allNoOne + MOD) % MOD;
            long term = C[n][i] * power(col, n) % MOD;
            ans = (i & 1) == 1 ? (ans - term + MOD) % MOD : (ans + term) % MOD;
        }
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
2 2
out:
7
-->
<!-- test
in:
123 456789
out:
689974806
-->
<!-- test
in:
1 1
out:
1
-->
<!-- test
in:
3 1
out:
1
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Prune products** before they overflow: `if (prod > N / a) skip` — a product above $N$ contributes $0$ and so do all supersets (Example 1).
2. **Signs mod $p$**: keep the running sum in $[0, p)$ with `(res - term + MOD) % MOD`.
3. **Duplicate primes / non-coprime moduli**: "divisible by all of $S$" is divisible by the **lcm**, not the product. Deduplicate or use lcms.
4. **Collapse symmetric sums.** If all $j$-intersections have the same size, the sum is over $j$, not over subsets.
5. **Order matters for "first obstacle" DP** (Example 4): the sort must put every cell that can precede $i$ before $i$; sorting by $(r, c)$ does that for right/down paths.
6. **Derangement base cases**: $D_0 = 1$, $D_1 = 0$ — $D_0 = 0$ breaks every formula that uses $\binom nk D_{n-k}$ with $k = n$.
7. **IE over rows *and* columns**: do IE over one family and count the other exactly (Example 5); a full double sum is $O(n^2)$ terms with powers — also fine if needed, but think first.
8. **$0^0 = 1$** in surjection-like sums: the $j = k$ term is $(-1)^k\binom kk 0^n$, which is $0$ for $n \ge 1$ and $(-1)^k$ for $n = 0$. Fast power returns $1$ for exponent $0$, which is what you want.

---

## 7. Going further (toward 2400–2600+)

- **IE with "generalised" properties**: Möbius functions of other posets (divisors → $\mu$, subsets → $(-1)^{\lvert S\rvert}$, partitions → $(-1)^{k-1}(k-1)!$ ).
- **Subset convolution / SOS**: compute all $g(S)$ and invert in $O(m2^m)$ — [SOS DP](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md); e.g. "count subsets with AND $= 0$" is IE over set bits.
- **IE + DP on the number of violated constraints**: when the bad events form a structure (adjacent equal elements, forbidden positions on a board), count "at least these $j$ violations" with a DP over $j$ and finish with binomial inversion — rook polynomials (🧊).
- **Min–max inclusion–exclusion** for expected time until *all* events occur (coupon collector with unequal probabilities) — [probability file](06-probability-and-expected-value.md).
- **Sky Full of Stars**–type problems: closed-form double IE simplified by the binomial theorem — [CF 997C · Sky Full of Stars](https://codeforces.com/problemset/problem/997/C) — 2500.

---

## 8. Practice ladder

**1400–1900**
- [ ] [CSES 1717 · Christmas Party](https://cses.fi/problemset/task/1717)
- [ ] [CSES 2185 · Prime Multiples](https://cses.fi/problemset/task/2185)
- [ ] [CF 888D · Almost Identity Permutations](https://codeforces.com/problemset/problem/888/D) — 1600
- [ ] [CF 1207D · Number Of Permutations](https://codeforces.com/problemset/problem/1207/D) — 1800
- [ ] [CF 1750D · Count GCD](https://codeforces.com/problemset/problem/1750/D) — 1800
- [ ] [AtCoder ABC172 E · NEQ](https://atcoder.jp/contests/abc172/tasks/abc172_e) — diff≈1880

**1900–2400**
- [ ] [CF 803F · Coprime Subsequences](https://codeforces.com/problemset/problem/803/F) — 2000
- [ ] [CF 559C · Gerald and Giant Chess](https://codeforces.com/problemset/problem/559/C) — 2200
- [ ] [CF 1228E · Another Filling the Grid](https://codeforces.com/problemset/problem/1228/E) — 2300
- [ ] [CF 451E · Devu and Flowers](https://codeforces.com/problemset/problem/451/E) — 2300
- [ ] [CF 1342E · Placing Rooks](https://codeforces.com/problemset/problem/1342/E) — 2300
- [ ] [CF 340E · Iahub and Permutations](https://codeforces.com/problemset/problem/340/E) — 2000

**2400+**
- [ ] [CF 997C · Sky Full of Stars](https://codeforces.com/problemset/problem/997/C) — 2500
- [ ] [CF 449D · Jzzhu and Numbers](https://codeforces.com/problemset/problem/449/D) — 2400
- [ ] [CF 1036F · Relatively Prime Powers](https://codeforces.com/problemset/problem/1036/F) — 2400

---

## 9. LeetCode / FAANG cross-reference

- [LC 634 · Find the Derangement of An Array](https://leetcode.com/problems/find-the-derangement-of-an-array/) — Medium 🔒 — the derangement recurrence.
- [LC 1201 · Ugly Number III](https://leetcode.com/problems/ugly-number-iii/) — Medium — IE over three divisors with lcms, inside a binary search.
- [LC 878 · Nth Magical Number](https://leetcode.com/problems/nth-magical-number/) — Hard — two-set IE $\lfloor x/a\rfloor + \lfloor x/b\rfloor - \lfloor x/\operatorname{lcm}\rfloor$.
- [LC 920 · Number of Music Playlists](https://leetcode.com/problems/number-of-music-playlists/) — Hard — DP, or IE over songs never played (surjection-like).

IE is rare in interviews beyond two- or three-set unions.

---

## 10. Self-check

1. Prove inclusion–exclusion using $\prod(1 - [x\in A_i])$.
2. Derive $D_n = (n-1)(D_{n-1} + D_{n-2})$ combinatorially. What is $D_5$?
3. How many surjections from a 5-set onto a 3-set?
4. State binomial inversion and the "exactly $k$ properties" formula.
5. How many integers in $[1, 100]$ are divisible by none of $2, 3, 5$?
6. In Gerald and Giant Chess, why is "first black cell hit" a valid partition of the bad paths?
7. Why does Example 5 only need IE over rows?
8. How many permutations of 6 elements have exactly 2 fixed points?

<details><summary>Answers</summary>

1. Expand the product over subsets; sum over all objects; each object with $t \ge 1$ properties contributes $(1-1)^t = 0$.
2. Element $n$ goes to $i \ne n$; either $i$ goes to $n$ ($D_{n-2}$) or not ($D_{n-1}$). $D_5 = 4(D_4 + D_3) = 4(9 + 2) = 44$.
3. $3^5 - 3\cdot2^5 + 3\cdot1^5 = 243 - 96 + 3 = 150$.
4. $g(k) = \sum_{t\ge k}\binom tk f(t) \iff f(k) = \sum_{t\ge k}(-1)^{t-k}\binom tk g(t)$; $E_k = \sum_j(-1)^{j-k}\binom jkS_j$.
5. $100 - (50 + 33 + 20) + (16 + 10 + 6) - 3 = 26$.
6. Every bad path hits at least one black cell, and it has exactly one *first* one, so the classes are disjoint and cover all bad paths.
7. Once the forced-bad rows are fixed, the column condition factorises over columns and can be counted exactly.
8. $\binom 62 D_4 = 15\cdot9 = 135$.

</details>
