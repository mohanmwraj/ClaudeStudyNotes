# Stars and Bars, Multisets and the Twelvefold Way

> **Band:** 🟢 1200 – 🟠 2300 · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [binomials](01-counting-principles-and-binomials.md), [inclusion–exclusion](03-inclusion-exclusion.md) (for upper bounds)
> **You can say you know this when:** you can turn "non-decreasing arrays", "distribute identical items", "multisets", "compositions" and "positions with gaps" into one binomial by an explicit bijection, handle lower and upper bounds, and fill in the twelvefold-way table from memory.

---

## 1. First principles — why this works

### 1.1 The bijection

How many solutions does $x_1 + x_2 + \dots + x_k = n$ have in non-negative integers? Listing them is hopeless, but each solution can be **drawn**: write $x_1$ stars, a bar, $x_2$ stars, a bar, …, $x_k$ stars. For $n = 7$, $k = 3$, the solution $(2, 0, 5)$ is `**||*****`. The drawing has $n$ stars and $k - 1$ bars in some order; conversely every arrangement of $n$ stars and $k - 1$ bars decodes to exactly one solution (read the star counts between bars). This is a bijection, so

$$\#\lbrace x_i \ge 0,\ \textstyle\sum x_i = n\rbrace = \binom{n + k - 1}{k - 1}.$$

### 1.2 Everything else is a change of variables

- **Lower bounds** $x_i \ge l_i$: substitute $y_i = x_i - l_i \ge 0$, so $\sum y_i = n - \sum l_i$. In particular $x_i \ge 1$ gives $\binom{n-1}{k-1}$ (equivalently: place $k - 1$ bars into the $n - 1$ gaps between stars, at most one per gap).
- **"$\le n$" instead of "$= n$"**: add a slack variable $x_{k+1} \ge 0$: $\binom{n + k}{k}$.
- **Non-decreasing sequences** $1 \le a_1 \le a_2 \le \dots \le a_m \le n$: let $x_1 = a_1 - 1$, $x_i = a_i - a_{i-1}$, $x_{m+1} = n - a_m$ — non-negative, summing to $n - 1$ over $m + 1$ variables: $\binom{n - 1 + m}{m}$. Equivalently, a non-decreasing sequence *is* a multiset of size $m$ from $n$ types.
- **Strictly increasing sequences** $1 \le a_1 < \dots < a_m \le n$ are just $m$-subsets: $\binom nm$. The shift $b_i = a_i - (i - 1)$ turns "strictly increasing in $[1, n]$" into "non-decreasing in $[1, n - m + 1]$", and both formulas agree — a good sanity check.
- **Gaps of at least $d$** between chosen positions: $b_i = a_i - (i-1)(d - 1)$ maps them to strictly increasing values in $[1, n - (m-1)(d-1)]$: $\binom{n - (m-1)(d-1)}{m}$.
- **Upper bounds** $x_i \le c_i$ break the bijection. Count the complement with inclusion–exclusion: force a chosen set $S$ of variables to violate ($x_i \ge c_i + 1$, a lower bound!), count with stars and bars, alternate signs ([inclusion–exclusion](03-inclusion-exclusion.md)):

$$\sum_{S \subseteq [k]} (-1)^{\lvert S\rvert}\binom{n - \sum_{i\in S}(c_i + 1) + k - 1}{k - 1}.$$

With a common bound $c$ the subsets collapse by size: $\sum_{j \ge 0}(-1)^j\binom kj\binom{n - j(c+1) + k - 1}{k - 1}$.

### 1.3 The twelvefold way: which formula for which "balls into boxes"

Put $n$ balls into $k$ boxes. Three yes/no questions decide the formula: are the balls distinguishable, are the boxes distinguishable, and is there a restriction (at most one per box = injective; at least one per box = surjective)?

| balls / boxes | any | ≤ 1 per box | ≥ 1 per box |
|---|---|---|---|
| distinct / distinct | $k^n$ | $k^{\underline n}$ | $k!\,S(n,k)$ |
| identical / distinct | $\binom{n+k-1}{k-1}$ | $\binom kn$ | $\binom{n-1}{k-1}$ |
| distinct / identical | $\sum_{j\le k} S(n, j)$ | $[n \le k]$ | $S(n,k)$ |
| identical / identical | $\sum_{j \le k} p(n, j)$ | $[n \le k]$ | $p(n, k)$ |

$S(n,k)$ = Stirling numbers of the second kind (partitions of a labelled set into $k$ blocks), $p(n,k)$ = partitions of the integer $n$ into exactly $k$ positive parts — both in [Catalan, Stirling, Bell and partitions](04-catalan-stirling-bell-and-partitions.md). Derivations: row 1 is the product rule and surjection counting ([inclusion–exclusion](03-inclusion-exclusion.md)); row 2 is this file; rows 3–4 are what remains after dividing out box labels — which is only legal for *surjective* assignments into distinct boxes (every box non-empty ⇒ the $k!$ relabelings give distinct assignments), hence $S(n,k) = \text{surj}(n,k)/k!$, and the "any" columns sum over the number of used boxes.

---

## 2. Formulas, definitions and identities

| Count | Formula | Note |
|---|---|---|
| $x_1 + \dots + x_k = n$, $x_i \ge 0$ | $\binom{n+k-1}{k-1}$ | stars and bars |
| … $x_i \ge 1$ | $\binom{n-1}{k-1}$ | compositions of $n$ into $k$ parts |
| … $x_i \ge l_i$ | $\binom{n - \sum l_i + k - 1}{k-1}$ | shift |
| $x_1 + \dots + x_k \le n$, $x_i \ge 0$ | $\binom{n+k}{k}$ | slack variable |
| … $0 \le x_i \le c$ | $\sum_{j}(-1)^j\binom kj\binom{n - j(c+1) + k - 1}{k-1}$ | IE; terms vanish once $n - j(c+1) < 0$ |
| … $0 \le x_i \le c_i$ | $\sum_{S}(-1)^{\lvert S\rvert}\binom{n - \sum_S(c_i + 1) + k - 1}{k-1}$ | $2^k$ terms |
| compositions of $n$ (any number of parts) | $2^{n-1}$ | each of $n - 1$ gaps: bar or not |
| multisets of size $m$ from $n$ types | $\binom{n+m-1}{m} = \left(\!\binom nm\!\right)$ | |
| non-decreasing length-$m$ sequences over $[1, n]$ | $\binom{n+m-1}{m}$ | = multisets |
| strictly increasing | $\binom nm$ | |
| $m$ positions in $[1, n]$ with pairwise gaps $\ge d$ | $\binom{n - (m-1)(d-1)}{m}$ | shift $b_i = a_i - (i-1)(d-1)$; $d = 2$: no two adjacent |
| monotone lattice paths $(0,0) \to (a, b)$ | $\binom{a+b}{a}$ | a path = a sequence of $a$ R's and $b$ U's |
| GF identity | $\sum_{n\ge0}\binom{n+k-1}{k-1}x^n = (1 - x)^{-k}$ | product of $k$ geometric series; bounded version: $\left(\frac{1 - x^{c+1}}{1-x}\right)^k$ expands into the IE formula |
| distinct objects into labelled groups of sizes $c_1..c_k$ | $\frac{n!}{\prod c_i!}$ | multinomial |
| $\sum_{i=0}^{m}\binom{i + k - 1}{k-1} = \binom{m + k}{k}$ | hockey stick = "sum $\le m$" | |

---

## 3. Implementation (C++ and Java)

```cpp
// Stars and bars with factorial tables: exact-sum, at-least-one, common upper bound, individual upper bounds.
const long long MOD = 1'000'000'007LL;
struct Comb {
    vector<long long> f, fi;
    static long long power(long long a, long long e) { long long r = 1; a %= MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
    explicit Comb(int n) : f(n + 1), fi(n + 1) {
        f[0] = 1;
        for (int i = 1; i <= n; i++) f[i] = f[i - 1] * i % MOD;
        fi[n] = power(f[n], MOD - 2);
        for (int i = n; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
    }
    long long C(long long n, long long k) const { return (k < 0 || n < 0 || k > n) ? 0 : f[n] * fi[k] % MOD * fi[n - k] % MOD; }
    long long nonneg(long long n, long long k) const { return k == 0 ? (n == 0) : C(n + k - 1, k - 1); }   // x_i >= 0
    long long positive(long long n, long long k) const { return k == 0 ? (n == 0) : C(n - 1, k - 1); }    // x_i >= 1
    long long bounded(long long n, long long k, long long c) const {                                     // 0 <= x_i <= c
        long long res = 0;
        for (long long j = 0; j <= k && j * (c + 1) <= n; j++) {
            long long term = C(k, j) * nonneg(n - j * (c + 1), k) % MOD;
            res = (j & 1) ? (res - term + MOD) % MOD : (res + term) % MOD;
        }
        return res;
    }
};
// individual upper bounds c[i] (k <= 20), n up to ~1e6: subset inclusion-exclusion
long long bounded_each(const Comb &cb, long long n, const vector<long long> &c) {
    int k = c.size(); long long res = 0;
    for (int mask = 0; mask < (1 << k); mask++) {
        long long rem = n; int bits = 0;
        for (int i = 0; i < k; i++) if (mask >> i & 1) { rem -= c[i] + 1; bits++; }
        if (rem < 0) continue;
        long long term = cb.nonneg(rem, k);
        res = (bits & 1) ? (res - term + MOD) % MOD : (res + term) % MOD;
    }
    return res;
}
```

```java
// Stars and bars with factorial tables: exact-sum, at-least-one, common upper bound, individual upper bounds.
static final long MOD = 1_000_000_007L;
static long[] f, fi;
static long power(long a, long e) { long r = 1; a %= MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
static void build(int n) {
    f = new long[n + 1]; fi = new long[n + 1]; f[0] = 1;
    for (int i = 1; i <= n; i++) f[i] = f[i - 1] * i % MOD;
    fi[n] = power(f[n], MOD - 2);
    for (int i = n; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
}
static long C(long n, long k) { return (k < 0 || n < 0 || k > n) ? 0 : f[(int) n] * fi[(int) k] % MOD * fi[(int) (n - k)] % MOD; }
static long nonneg(long n, long k) { return k == 0 ? (n == 0 ? 1 : 0) : C(n + k - 1, k - 1); }
static long positive(long n, long k) { return k == 0 ? (n == 0 ? 1 : 0) : C(n - 1, k - 1); }
static long bounded(long n, long k, long c) {
    long res = 0;
    for (long j = 0; j <= k && j * (c + 1) <= n; j++) {
        long term = C(k, j) * nonneg(n - j * (c + 1), k) % MOD;
        res = (j & 1) == 1 ? (res - term + MOD) % MOD : (res + term) % MOD;
    }
    return res;
}
static long boundedEach(long n, long[] c) {
    int k = c.length; long res = 0;
    for (int mask = 0; mask < (1 << k); mask++) {
        long rem = n; int bits = 0;
        for (int i = 0; i < k; i++) if ((mask >> i & 1) == 1) { rem -= c[i] + 1; bits++; }
        if (rem < 0) continue;
        long term = nonneg(rem, k);
        res = (bits & 1) == 1 ? (res - term + MOD) % MOD : (res + term) % MOD;
    }
    return res;
}
```

---

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "distribute $n$ identical items among $k$ people" | stars and bars (check: may someone get nothing?) |
| "number of non-decreasing arrays of length $m$ with values in $[1, n]$" | multisets: $\binom{n+m-1}{m}$ |
| two arrays with $a$ non-decreasing, $b$ non-increasing, $a_i \le b_i$ | glue them into one non-decreasing sequence of length $2m$ (Example 2) |
| "choose positions, no two adjacent / at distance $\ge d$" | gap shift |
| "split into $k$ non-empty consecutive groups" | compositions $\binom{n-1}{k-1}$ (bars in gaps) — Example 3 |
| each part at most $c$ / at most $c_i$ | inclusion–exclusion over violated parts (Examples 4, 5) |
| "number of multisets / combinations with repetition" | $\binom{n+m-1}{m}$ |
| distinct objects, some boxes may be empty, boxes unlabelled | not stars and bars — Stirling/Bell (twelvefold way) |

Watch out: stars and bars counts **identical** items into **distinct** boxes. If the items are distinct, it is $k^n$ or a surjection count; if boxes are identical, it is a partition count.

---

## 5. Worked examples (graded)

### Example 1 — Distributing Apples  ·  ★ ≈1300 (est.)

- **Source:** [CSES 1716 · Distributing Apples](https://cses.fi/problemset/task/1716)
- **Difficulty:** ≈1300 (est.)
- **Problem:** $n$ children and $m$ identical apples ($n, m \le 10^6$); count distributions (a child may get none), modulo $10^9+7$.
- **Thinking from first principles:** Identical items, distinct recipients, no restriction → stars and bars with $m$ stars and $n - 1$ bars: $\binom{n + m - 1}{n - 1}$.

<details><summary>Solution</summary>

Factorials up to $n + m - 1 \le 2\cdot10^6$. $O(n + m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 1'000'000'007LL;
long long power(long long a, long long e) { long long r = 1; a %= MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
int main() {
    long long n, m; cin >> n >> m;
    int N = n + m;
    vector<long long> f(N + 1), fi(N + 1);
    f[0] = 1;
    for (int i = 1; i <= N; i++) f[i] = f[i - 1] * i % MOD;
    fi[N] = power(f[N], MOD - 2);
    for (int i = N; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
    cout << f[n + m - 1] * fi[n - 1] % MOD * fi[m] % MOD << '\n';
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
        int n = Integer.parseInt(st.nextToken()), m = Integer.parseInt(st.nextToken());
        int N = n + m;
        long[] f = new long[N + 1], fi = new long[N + 1];
        f[0] = 1;
        for (int i = 1; i <= N; i++) f[i] = f[i - 1] * i % MOD;
        fi[N] = power(f[N], MOD - 2);
        for (int i = N; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
        System.out.println(f[n + m - 1] * fi[n - 1] % MOD * fi[m] % MOD);
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
1000000 1000000
out:
96075800
-->

### Example 2 — Two Arrays  ·  ★ 1600

- **Source:** [CF 1288C · Two Arrays](https://codeforces.com/problemset/problem/1288/C) — 1600
- **Difficulty:** 1600
- **Problem:** Given $n \le 1000$, $m \le 10$: count pairs of arrays $a, b$ of length $m$ with values in $[1, n]$, $a$ non-decreasing, $b$ non-increasing, and $a_i \le b_i$ for all $i$. Modulo $10^9+7$.
- **Thinking from first principles:** A DP over $(i, a_i, b_i)$ works but there is a bijection. Since $a$ rises, $b$ falls and $a_i \le b_i$, the binding constraint is only $a_m \le b_m$: the sequence $a_1 \le \dots \le a_m \le b_m \le b_{m-1} \le \dots \le b_1$ is non-decreasing of length $2m$, and every such sequence splits back into a valid pair. Multisets of size $2m$ from $n$ values: $\binom{n + 2m - 1}{2m}$.

<details><summary>Solution</summary>

One binomial with $n + 2m - 1 \le 1019$. $O(n + m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 1'000'000'007LL;
long long power(long long a, long long e) { long long r = 1; a %= MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
int main() {
    int n, m; cin >> n >> m;
    long long num = 1, den = 1;
    for (int i = 0; i < 2 * m; i++) { num = num * (n + 2 * m - 1 - i) % MOD; den = den * (i + 1) % MOD; }
    cout << num * power(den, MOD - 2) % MOD << '\n';
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
        int n = Integer.parseInt(st.nextToken()), m = Integer.parseInt(st.nextToken());
        long num = 1, den = 1;
        for (int i = 0; i < 2 * m; i++) { num = num * (n + 2 * m - 1 - i) % MOD; den = den * (i + 1) % MOD; }
        System.out.println(num * power(den, MOD - 2) % MOD);
    }
}
```

</details>

<!-- test
in:
2 2
out:
5
-->
<!-- test
in:
10 1
out:
55
-->
<!-- test
in:
723 9
out:
157557417
-->
<!-- test
in:
1 10
out:
1
-->

### Example 3 — Blue and Red Balls  ·  ★ ≈1200 (est.)

- **Source:** [AtCoder ABC132 D · Blue and Red Balls](https://atcoder.jp/contests/abc132/tasks/abc132_d)
- **Difficulty:** ≈1200 (est.; AtCoder Problems diff ≈1167)
- **Problem:** $N$ balls in a row, $K$ of them blue ($1 \le K \le N \le 2000$). For each $i = 1..K$, count arrangements in which the blue balls form exactly $i$ maximal blocks, modulo $10^9+7$.
- **Thinking from first principles:** Two independent choices (product rule). (1) Split the $K$ blue balls into $i$ non-empty consecutive blocks: compositions, $\binom{K-1}{i-1}$. (2) Place the $i$ blocks among the $N - K$ red balls so that no two touch: the reds create $N - K + 1$ slots, choose $i$ distinct slots: $\binom{N-K+1}{i}$.

<details><summary>Solution</summary>

Pascal's triangle to 2001 (no modular inverse needed). $O(N^2)$ precompute, $O(K)$ answers.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 1'000'000'007LL;
int main() {
    int N, K; cin >> N >> K;
    vector<vector<long long>> C(N + 2, vector<long long>(N + 2, 0));
    for (int i = 0; i <= N + 1; i++) {
        C[i][0] = 1;
        for (int j = 1; j <= i; j++) C[i][j] = (C[i - 1][j - 1] + C[i - 1][j]) % MOD;
    }
    for (int i = 1; i <= K; i++) cout << C[K - 1][i - 1] * C[N - K + 1][i] % MOD << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        final long MOD = 1_000_000_007L;
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        int N = Integer.parseInt(st.nextToken()), K = Integer.parseInt(st.nextToken());
        long[][] C = new long[N + 2][N + 2];
        for (int i = 0; i <= N + 1; i++) {
            C[i][0] = 1;
            for (int j = 1; j <= i; j++) C[i][j] = (C[i - 1][j - 1] + C[i - 1][j]) % MOD;
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 1; i <= K; i++) sb.append(C[K - 1][i - 1] * C[N - K + 1][i] % MOD).append('\n');
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
5 3
out:
3
6
1
-->
<!-- test
in:
2000 3
out:
1998
3990006
327341989
-->
<!-- test
in:
3 3
out:
1
0
0
-->

### Example 4 — Bounded parts by inclusion–exclusion  ·  ★ ≈1800 (est.)

- **Source:** Original problem
- **Difficulty:** ≈1800 (est.)
- **Problem:** Given $n, k, c$ ($0 \le n \le 10^6$, $1 \le k \le 10^6$, $0 \le c \le 10^6$), count $(x_1, \dots, x_k)$ with $0 \le x_i \le c$ and $\sum x_i = n$, modulo $10^9+7$.
- **Thinking from first principles:** Without the cap it is $\binom{n + k - 1}{k-1}$. Let $A_i$ be the bad set "$x_i \ge c + 1$". Forcing a set of $j$ variables to be bad is a lower bound — stars and bars on $n - j(c+1)$. All $\binom kj$ choices of $j$ variables give the same count, so IE collapses to $\sum_j (-1)^j\binom kj\binom{n - j(c+1) + k - 1}{k-1}$ with $j \le \min(k, n/(c+1))$.

<details><summary>Solution</summary>

Factorials up to $n + k$. At most $\min(k, n/(c+1)) + 1$ terms. $O(n + k)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 1'000'000'007LL;
long long power(long long a, long long e) { long long r = 1; a %= MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
int main() {
    long long n, k, c; cin >> n >> k >> c;
    int N = n + k + 1;
    vector<long long> f(N + 1), fi(N + 1);
    f[0] = 1;
    for (int i = 1; i <= N; i++) f[i] = f[i - 1] * i % MOD;
    fi[N] = power(f[N], MOD - 2);
    for (int i = N; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
    auto C = [&](long long a, long long b) -> long long { return (b < 0 || a < 0 || b > a) ? 0 : f[a] * fi[b] % MOD * fi[a - b] % MOD; };
    long long ans = 0;
    for (long long j = 0; j <= k && j * (c + 1) <= n; j++) {
        long long term = C(k, j) * C(n - j * (c + 1) + k - 1, k - 1) % MOD;
        ans = (j % 2 ? ans - term + MOD : ans + term) % MOD;
    }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long[] f, fi;
    static long power(long a, long e) { long r = 1; a %= MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
    static long C(long a, long b) { return (b < 0 || a < 0 || b > a) ? 0 : f[(int) a] * fi[(int) b] % MOD * fi[(int) (a - b)] % MOD; }
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        long n = Long.parseLong(st.nextToken()), k = Long.parseLong(st.nextToken()), c = Long.parseLong(st.nextToken());
        int N = (int) (n + k + 1);
        f = new long[N + 1]; fi = new long[N + 1]; f[0] = 1;
        for (int i = 1; i <= N; i++) f[i] = f[i - 1] * i % MOD;
        fi[N] = power(f[N], MOD - 2);
        for (int i = N; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
        long ans = 0;
        for (long j = 0; j <= k && j * (c + 1) <= n; j++) {
            long term = C(k, j) * C(n - j * (c + 1) + k - 1, k - 1) % MOD;
            ans = (j % 2 == 1 ? ans - term + MOD : ans + term) % MOD;
        }
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
5 3 2
out:
3
-->
<!-- test
in:
7 3 7
out:
36
-->
<!-- test
in:
0 5 0
out:
1
-->
<!-- test
in:
1000000 1000000 1
out:
1
-->
<!-- test
in:
12345 678 30
out:
811017977
-->

### Example 5 — Devu and Flowers  ·  ★ 2300

- **Source:** [CF 451E · Devu and Flowers](https://codeforces.com/problemset/problem/451/E) — 2300
- **Difficulty:** 2300
- **Problem:** $n \le 20$ boxes; box $i$ holds $f_i \le 10^{12}$ identical flowers of colour $i$. Count ways to pick exactly $s \le 10^{14}$ flowers (distinguished only by colour counts), modulo $10^9+7$.
- **Thinking from first principles:** Count $x_1 + \dots + x_n = s$ with $0 \le x_i \le f_i$ — individual caps, so subset IE with $2^{20} \approx 10^6$ terms, each $\binom{s - \sum_{S}(f_i + 1) + n - 1}{n - 1}$. The top argument is up to $10^{14}$, far beyond factorial tables, but the bottom is $n - 1 \le 19$: use the multiplicative formula with each factor reduced mod $p$ (valid because $(n-1)! $ is invertible, §1.4 of [binomials](01-counting-principles-and-binomials.md)).

<details><summary>Solution</summary>

Precompute $((n-1)!)^{-1}$. For each mask compute the remaining sum $r$; if $r \ge 0$ add $(-1)^{\lvert S\rvert}\prod_{i=1}^{n-1}(r + i) \cdot ((n-1)!)^{-1}$ (note $\binom{r + n - 1}{n-1} = \frac{(r+1)\cdots(r+n-1)}{(n-1)!}$). $O(2^n\cdot n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007LL;
ll power(ll a, ll e) { ll r = 1; a %= MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
int main() {
    int n; ll s; cin >> n >> s;
    vector<ll> f(n);
    for (auto &x : f) cin >> x;
    ll fact = 1;
    for (int i = 1; i < n; i++) fact = fact * i % MOD;
    ll invFact = power(fact, MOD - 2), ans = 0;
    for (int mask = 0; mask < (1 << n); mask++) {
        ll r = s; int bits = 0;
        for (int i = 0; i < n; i++) if (mask >> i & 1) { r -= f[i] + 1; bits++; }
        if (r < 0) continue;
        ll term = invFact;
        for (int i = 1; i < n; i++) term = term * ((r + i) % MOD) % MOD;   // C(r + n - 1, n - 1)
        ans = (bits & 1) ? (ans - term + MOD) % MOD : (ans + term) % MOD;
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
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        int n = Integer.parseInt(st.nextToken()); long s = Long.parseLong(st.nextToken());
        st = new StringTokenizer(br.readLine());
        long[] f = new long[n];
        for (int i = 0; i < n; i++) f[i] = Long.parseLong(st.nextToken());
        long fact = 1;
        for (int i = 1; i < n; i++) fact = fact * i % MOD;
        long invFact = power(fact, MOD - 2), ans = 0;
        for (int mask = 0; mask < (1 << n); mask++) {
            long r = s; int bits = 0;
            for (int i = 0; i < n; i++) if ((mask >> i & 1) == 1) { r -= f[i] + 1; bits++; }
            if (r < 0) continue;
            long term = invFact;
            for (int i = 1; i < n; i++) term = term * ((r + i) % MOD) % MOD;
            ans = (bits & 1) == 1 ? (ans - term + MOD) % MOD : (ans + term) % MOD;
        }
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
2 3
1 3
out:
2
-->
<!-- test
in:
2 4
2 2
out:
1
-->
<!-- test
in:
3 5
1 3 2
out:
3
-->
<!-- test
in:
1 100000000000000
1000000000000
out:
0
-->
<!-- test
in:
3 1000000000000
1000000000000 1000000000000 1000000000000
out:
24489501
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Decide "$\ge 0$" versus "$\ge 1$" first** — the two formulas differ by $n \to n - k$; reading the statement wrong here is the most common WA.
2. **$k = 0$ boxes**: $\binom{n - 1}{-1}$ is $0$ by the convention, but the true count is $[n = 0]$ — special-case it.
3. **Factorial table size**: $\binom{n + k - 1}{k - 1}$ needs factorials up to $n + k - 1$, not $\max(n, k)$.
4. **Huge $n$, small $k$**: never build factorials to $10^{14}$; use the multiplicative formula with reduced factors (Example 5).
5. **Negative arguments in IE terms**: stop the loop when the remaining sum becomes negative, or make `C` return $0$ for negative $n$.
6. **Identical vs distinct**: if the items are distinguishable (people, labelled balls) stars and bars is wrong — use $k^n$/surjections.
7. **Signs modulo $p$**: `ans - term + MOD` before `% MOD`.
8. **Exact counts**: $\binom{n+k-1}{k-1}$ grows fast; without a modulus, check whether the true answer fits in 64-bit before using a table of `long long`.

---

## 7. Going further (toward 2400–2600+)

- **Generating functions** turn every capped / weighted distribution into coefficient extraction of $\prod_i (1 + x + \dots + x^{c_i})$, computed by polynomial multiplication or NTT when the caps vary — [polynomials and GFs](../15-Advanced-Math/04-polynomials-and-generating-functions.md).
- **Prefix-sum DP** for "$x_i \le c_i$" with many different caps and $n \le 10^5$: $\text{dp}_i[s] = \sum_{t = s - c_i}^{s}\text{dp}_{i-1}[t]$ in $O(nk)$ — [knapsack family](../06-Dynamic-Programming/02-knapsack-family.md).
- **Stars and bars over primes**: distributing prime exponents of a product among $k$ factors ([LC 1735](https://leetcode.com/problems/count-ways-to-make-array-with-product/) — Hard) multiplies $\binom{e_p + k - 1}{k - 1}$ over primes.
- **Lattice paths under a barrier** (ballot / reflection) — [Catalan file](04-catalan-stirling-bell-and-partitions.md).

---

## 8. Practice ladder

**≤ 1400**
- [ ] [CSES 1716 · Distributing Apples](https://cses.fi/problemset/task/1716)
- [ ] [AtCoder ABC132 D · Blue and Red Balls](https://atcoder.jp/contests/abc132/tasks/abc132_d) — diff≈1167
- [ ] [AtCoder ABC178 D · Redistribution](https://atcoder.jp/contests/abc178/tasks/abc178_d) — diff≈875

**1400–1900**
- [ ] [CF 1462E1 · Close Tuples (easy version)](https://codeforces.com/problemset/problem/1462/E1) — 1500
- [ ] [CF 1288C · Two Arrays](https://codeforces.com/problemset/problem/1288/C) — 1600
- [ ] [CF 1462E2 · Close Tuples (hard version)](https://codeforces.com/problemset/problem/1462/E2) — 1700
- [ ] [CF 1327E · Count The Blocks](https://codeforces.com/problemset/problem/1327/E) — 1800

**1900–2400**
- [ ] [CF 893E · Counting Arrays](https://codeforces.com/problemset/problem/893/E) — 2000
- [ ] [CF 1931G · One-Dimensional Puzzle](https://codeforces.com/problemset/problem/1931/G) — 2000
- [ ] [CF 1696E · Placing Jinas](https://codeforces.com/problemset/problem/1696/E) — 2000
- [ ] [CF 571A · Lengthening Sticks](https://codeforces.com/problemset/problem/571/A) — 2100
- [ ] [CF 451E · Devu and Flowers](https://codeforces.com/problemset/problem/451/E) — 2300
- [ ] [CF 1342E · Placing Rooks](https://codeforces.com/problemset/problem/1342/E) — 2300

---

## 9. LeetCode / FAANG cross-reference

- [LC 1641 · Count Sorted Vowel Strings](https://leetcode.com/problems/count-sorted-vowel-strings/) — Medium — non-decreasing strings = multisets of size $n$ from 5: $\binom{n+4}{4}$.
- [LC 62 · Unique Paths](https://leetcode.com/problems/unique-paths/) — Medium — lattice paths.
- [LC 1155 · Number of Dice Rolls With Target Sum](https://leetcode.com/problems/number-of-dice-rolls-with-target-sum/) — Medium — bounded stars and bars (IE formula or prefix-sum DP).
- [LC 1735 · Count Ways to Make Array With Product](https://leetcode.com/problems/count-ways-to-make-array-with-product/) — Hard — stars and bars per prime exponent.
- [LC 2147 · Number of Ways to Divide a Long Corridor](https://leetcode.com/problems/number-of-ways-to-divide-a-long-corridor/) — Hard — product of independent "bar position" choices between seat pairs.

---

## 10. Self-check

1. Prove $\binom{n+k-1}{k-1}$ by an explicit bijection.
2. How many non-decreasing sequences of length 3 with values in $[1, 5]$?
3. How many ways to choose 4 numbers from $[1, 20]$ with no two consecutive?
4. Write the inclusion–exclusion formula for $x_1 + x_2 + x_3 = 10$, $0 \le x_i \le 4$, and evaluate it.
5. Fill the twelvefold-way row "identical balls, distinct boxes".
6. Why is "distinct balls, identical boxes, surjective" equal to surjections divided by $k!$, but "any" is not $k^n/k!$?
7. How do you count solutions of $x_1 + \dots + x_k \le n$?
8. Why can Devu and Flowers use the multiplicative formula even though $s \approx 10^{14}$?

<details><summary>Answers</summary>

1. Write each solution as $n$ stars separated into $k$ groups by $k - 1$ bars; arrangements of the $n + k - 1$ symbols ↔ solutions.
2. Multisets of size 3 from 5: $\binom{7}{3} = 35$.
3. Gap shift: $\binom{20 - 3}{4} = \binom{17}{4} = 2380$.
4. $\binom{12}{2} - 3\binom{7}{2} + 3\binom{2}{2} = 66 - 63 + 3 = 6$.
5. $\binom{n+k-1}{k-1}$, $\binom kn$, $\binom{n-1}{k-1}$.
6. In a surjection every box is non-empty, so all $k!$ relabelings of the boxes give different assignments — the overcount is uniform. With empty boxes allowed, relabeling two empty boxes gives the same assignment.
7. Add a slack variable: $\binom{n+k}{k}$.
8. The bottom index is $n - 1 \le 19 < p$, so $\binom{N}{n-1} = \frac{N(N-1)\cdots}{(n-1)!}$ holds with every factor reduced mod $p$ and $(n-1)!$ invertible.

</details>
