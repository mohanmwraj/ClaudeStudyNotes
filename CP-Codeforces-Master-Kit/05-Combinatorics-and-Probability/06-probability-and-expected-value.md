# Probability and Expected Value

> **Band:** 🔵 1500 – 🟠 2400 · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [counting](01-counting-principles-and-binomials.md), [modular inverses](../04-Number-Theory/02-modular-arithmetic-and-inverses.md)
> **You can say you know this when:** you reach for linearity of expectation and indicator variables before anything else, can derive $E = 1/p$, $nH_n$, tail-sum and gambler's-ruin formulas, and can compute any rational probability modulo $998244353$ without ever using floating point.

---

## 1. First principles — why this works

### 1.1 Probability is counting with weights

A finite probability space is a set $\Omega$ of outcomes with weights $P(\omega) \ge 0$ summing to 1; an event is a subset, $P(A) = \sum_{\omega\in A}P(\omega)$. For uniform spaces this is counting: $P(A) = \lvert A\rvert/\lvert\Omega\rvert$. Everything else is definitions:

- **Conditional probability** $P(A \mid B) = \frac{P(A\cap B)}{P(B)}$ — restrict the space to $B$ and renormalise. Rearranged: $P(A\cap B) = P(B)P(A\mid B)$ (multiplication rule).
- **Total probability**: if $B_1, \dots, B_k$ partition $\Omega$, $P(A) = \sum_i P(B_i)P(A \mid B_i)$ — the sum rule, weighted. This is the equation behind every probability DP ("condition on the first step").
- **Bayes**: $P(B \mid A) = \frac{P(A\mid B)P(B)}{P(A)}$ — both sides equal $P(A\cap B)/P(A)$.
- **Independence**: $P(A \cap B) = P(A)P(B)$. For random variables: the joint distribution factorises.

### 1.2 Expectation and the most useful theorem in the topic

A **random variable** $X$ assigns a number to each outcome; $E[X] = \sum_\omega X(\omega)P(\omega)$. **Linearity**: $E[X + Y] = E[X] + E[Y]$ and $E[cX] = cE[X]$, **for any $X, Y$, dependent or not**:

$$E[X + Y] = \sum_\omega (X(\omega) + Y(\omega))P(\omega) = \sum_\omega X(\omega)P(\omega) + \sum_\omega Y(\omega)P(\omega).$$

Nothing about the joint distribution was used. Combine with **indicator variables** ($I_A = 1$ if $A$ happens, else $0$, so $E[I_A] = P(A)$): to find the expected number of "things" that happen, write the count as $\sum I_{A_i}$ and add up the individual probabilities — even when the events are wildly dependent.

*Examples.* Expected fixed points of a random permutation: $n\cdot\frac1n = 1$. Expected inversions: $\binom n2\cdot\frac12$. Expected number of distinct values among $k$ uniform draws from $[1, n]$: $n\bigl(1 - (1 - \frac1n)^k\bigr)$ (indicator per value).

### 1.3 Waiting times: geometric distribution, coupon collector, tail sums

Repeat a trial with success probability $p$ until the first success; let $T$ be the number of trials. Condition on the first trial (total expectation): with probability $p$ we are done after 1 trial; otherwise we used 1 trial and the future looks exactly like the start:

$$E[T] = 1 + (1 - p)E[T] \;\Longrightarrow\; E[T] = \frac1p .$$

This "the process restarts, so $E$ appears on both sides" trick solves many expected-value problems in one line (Example 5).

**Coupon collector.** Collecting all $n$ coupon types: while you already have $i$ types, each draw is new with probability $\frac{n-i}{n}$, so this phase lasts $\frac{n}{n-i}$ draws in expectation. By linearity over phases:

$$E[\text{draws for all } n] = \sum_{i=0}^{n-1}\frac{n}{n-i} = nH_n \approx n\ln n + 0.577n .$$

**Tail-sum formula.** For a non-negative integer variable, $X = \sum_{k\ge1}[X \ge k]$, so $E[X] = \sum_{k \ge 1}P(X \ge k)$. The maximum of $n$ independent rolls of an $m$-sided die satisfies $P(\max \le k) = (k/m)^n$ — maxima and minima turn into products of tails (Example 1).

### 1.4 Probabilities modulo a prime

"Print the answer as $P\cdot Q^{-1} \bmod 998244353$" works because the map $\frac ab \mapsto ab^{-1} \bmod p$ is consistent with $+$ and $\times$ ([modular arithmetic §2.5](../04-Number-Theory/02-modular-arithmetic-and-inverses.md)). So you may compute **directly in residues**: a probability "$\frac{1}{m}$" becomes `inv(m)`, sums and products are reduced as usual, and linear equations are solved with modular inverses. Two caveats: you cannot compare residues ("is the probability $> 0.5$?") and you must never divide by a residue that is $0$ — make sure denominators are non-zero *as rational numbers* and not divisible by $p$.

---

## 2. Formulas, definitions and identities

| Formula | Meaning / proof sketch |
|---|---|
| $P(A\cup B) = P(A) + P(B) - P(A\cap B)$; $P(\bar A) = 1 - P(A)$ | inclusion–exclusion |
| $P(A\cap B) = P(B)P(A\mid B)$; $P(A) = \sum_i P(B_i)P(A\mid B_i)$ | multiplication rule, total probability |
| $P(B\mid A) = P(A\mid B)P(B)/P(A)$ | Bayes |
| $E[X + Y] = E[X] + E[Y]$ always; $E[XY] = E[X]E[Y]$ if independent | §1.2 |
| $E[I_A] = P(A)$ | indicator |
| $E[X] = \sum_{k\ge1}P(X\ge k)$ ($X \in \mathbb Z_{\ge0}$); $E[X] = \int_0^\infty P(X > t)\,dt$ ($X \ge 0$) | tail sums |
| total expectation $E[X] = \sum_i P(B_i)E[X \mid B_i]$ | basis of expectation DP |
| geometric: $E = \frac1p$, $\operatorname{Var} = \frac{1-p}{p^2}$ | §1.3 |
| binomial $\operatorname{Bin}(n,p)$: $E = np$, $\operatorname{Var} = np(1-p)$, $E[X^{\underline k}] = n^{\underline k}p^k$ | indicators; [Stirling](04-catalan-stirling-bell-and-partitions.md) for moments |
| coupon collector: all $n$: $nH_n$; first $k$ distinct: $\sum_{i<k}\frac{n}{n-i}$ | §1.3 |
| unequal coupon probabilities $p_i$ (🧊) | $E = \sum_{\emptyset\ne S}(-1)^{\lvert S\rvert+1}\frac{1}{\sum_{i\in S}p_i}$ — min–max inclusion–exclusion |
| max of $n$ rolls of an $m$-die | $P(\max \le k) = (k/m)^n$; $E[\max] = m - \sum_{k=1}^{m-1}(k/m)^n$ |
| $n$ i.i.d. $U(0,1)$: $E[\min] = \frac{1}{n+1}$, $E[k\text{-th smallest}] = \frac{k}{n+1}$ | $n$ points split $[0,1]$ into $n+1$ exchangeable gaps |
| random permutation: $E[\text{fixed points}] = 1$, $E[\text{cycles}] = H_n$, $E[\text{inversions}] = \frac{n(n-1)}{4}$, $E[\text{left-to-right maxima}] = H_n$ | indicators: element $i$ is a record with probability $1/i$ |
| $\operatorname{Var}(X) = E[X^2] - E[X]^2$; $\operatorname{Var}(\sum X_i) = \sum\operatorname{Var}X_i + 2\sum_{i<j}\operatorname{Cov}(X_i, X_j)$ | expand the square |
| $E[(\sum I_i)^2] = \sum_i P(A_i) + 2\sum_{i<j}P(A_i\cap A_j)$ | squares of counts via pairs |
| gambler's ruin, fair walk from $i$ on $[0, N]$: $P(\text{hit } N \text{ first}) = \frac iN$, $E[\text{time}] = i(N - i)$ | $f(i) = \frac{f(i-1) + f(i+1)}2$ is linear; $g(i) = 1 + \frac{g(i-1)+g(i+1)}{2}$ is quadratic |
| biased walk ($p$ up, $q = 1-p$ down), $r = q/p \ne 1$ | $P(\text{hit } N \text{ first}) = \frac{1 - r^i}{1 - r^N}$ (solve $f(i) = pf(i+1) + qf(i-1)$) (🧊) |
| birthday paradox | $P(\text{no repeat in } k \text{ draws from } n) \approx e^{-k^2/(2n)}$; expected draws to first repeat $\approx\sqrt{\pi n/2}$ |
| Markov $P(X \ge a) \le E[X]/a$; Chebyshev $P(\lvert X - \mu\rvert \ge t) \le \operatorname{Var}/t^2$ | used to argue randomised algorithms ([randomised algorithms](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md)) |
| modular answer | $\frac ab \mapsto a\,b^{-1} \bmod p$ (§1.4) |

---

## 3. Implementation (C++ and Java)

```cpp
// Probability helpers: modular fractions, expected max of dice, coupon collector (mod p), gambler's ruin (double).
const long long P = 998244353LL;
long long power(long long a, long long e) { long long r = 1; a %= P; if (a < 0) a += P; for (; e; e >>= 1, a = a * a % P) if (e & 1) r = r * a % P; return r; }
long long frac(long long a, long long b) { return (a % P + P) % P * power(b, P - 2) % P; }     // a / b mod P
double expected_max_dice(int m, int n) {                    // E[max of n rolls of an m-sided die]
    double e = m;
    for (int k = 1; k < m; k++) e -= pow((double)k / m, n);   // pow of a number < 1: no overflow
    return e;
}
long long coupon_collector_mod(long long n, long long k) {  // expected draws to see k distinct of n types, mod P
    long long s = 0;
    for (long long i = 0; i < k; i++) s = (s + frac(n, n - i)) % P;
    return s;
}
double gamblers_ruin(int i, int N, double p) {              // P(reach N before 0) from i, up-probability p
    if (fabs(p - 0.5) < 1e-12) return (double)i / N;
    double r = (1 - p) / p;
    return (1 - pow(r, i)) / (1 - pow(r, N));
}
```

```java
// Probability helpers: modular fractions, expected max of dice, coupon collector (mod p), gambler's ruin (double).
static final long P = 998244353L;
static long power(long a, long e) { long r = 1; a %= P; if (a < 0) a += P; for (; e > 0; e >>= 1, a = a * a % P) if ((e & 1) == 1) r = r * a % P; return r; }
static long frac(long a, long b) { return Math.floorMod(a, P) * power(b, P - 2) % P; }
static double expectedMaxDice(int m, int n) {
    double e = m;
    for (int k = 1; k < m; k++) e -= Math.pow((double) k / m, n);
    return e;
}
static long couponCollectorMod(long n, long k) {
    long s = 0;
    for (long i = 0; i < k; i++) s = (s + frac(n, n - i)) % P;
    return s;
}
static double gamblersRuin(int i, int N, double p) {
    if (Math.abs(p - 0.5) < 1e-12) return (double) i / N;
    double r = (1 - p) / p;
    return (1 - Math.pow(r, i)) / (1 - Math.pow(r, N));
}
```

---

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "expected number of …" (pairs, inversions, components, distinct values) | sum of indicators; compute each probability separately |
| "expected maximum / minimum" | tail sums: $P(\max \le k)$ is a product |
| "expected number of steps until …" with a restart structure | $E = a + bE$ (solve for $E$) or expectation DP over states |
| random process on a tree/array, "each step removes …" | linearity over elements: when is element $v$ *directly* chosen? (Example 4) |
| "probability that A wins" with repeated rounds | total probability on the first round; geometric series |
| answer modulo $998244353$ "as $P\cdot Q^{-1}$" | work in residues from the start (Examples 3, 5) |
| "print with absolute/relative error $10^{-6}$" | doubles are fine; avoid catastrophic cancellation (sum small terms first, use $\log$ for huge powers) |
| $E[X^2]$, variance | pairs of indicators, or Stirling moments |

Confusion to avoid: linearity gives $E[\sum]$, **not** $E[\max]$, $E[\text{product}]$ or $P(\text{all})$ — those need independence or a different decomposition.

---

## 5. Worked examples (graded)

### Example 1 — Little Pony and Expected Maximum  ·  ★ 1600

- **Source:** [CF 453A · Little Pony and Expected Maximum](https://codeforces.com/problemset/problem/453/A) — 1600
- **Difficulty:** 1600
- **Problem:** A fair $m$-sided die is rolled $n$ times ($m, n \le 10^5$). Print the expected maximum (error $\le 10^{-4}$).
- **Thinking from first principles:** The distribution of the maximum is awkward directly, but its CDF is a product: $P(\max \le k) = (k/m)^n$. Tail sums: $E[\max] = \sum_{k=1}^{m}P(\max \ge k) = \sum_{k=1}^{m}\bigl(1 - (\frac{k-1}{m})^n\bigr) = m - \sum_{k=1}^{m-1}(k/m)^n$. Computing $k^n$ exactly overflows; $(k/m)^n$ is a number in $[0, 1]$ — no overflow, tiny underflow is harmless.

<details><summary>Solution</summary>

$O(m\log n)$ with `pow`.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    int m, n; cin >> m >> n;
    double e = m;
    for (int k = 1; k < m; k++) e -= pow((double)k / m, n);
    printf("%.12f\n", e);
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        int m = Integer.parseInt(st.nextToken()), n = Integer.parseInt(st.nextToken());
        double e = m;
        for (int k = 1; k < m; k++) e -= Math.pow((double) k / m, n);
        System.out.println(String.format(Locale.US, "%.12f", e));
    }
}
```

</details>

<!-- test
in:
6 1
out:
3.500000000000
-->
<!-- test
in:
6 3
out:
4.958333333333
-->
<!-- test
in:
2 2
out:
1.750000000000
-->
<!-- test
in:
100000 100000
out:
99999.418033254507
-->

### Example 2 — Inversion Probability  ·  ★ ≈1700 (est.)

- **Source:** [CSES 1728 · Inversion Probability](https://cses.fi/problemset/task/1728)
- **Difficulty:** ≈1700 (est.)
- **Problem:** $n \le 100$; $x_i$ is uniform on $\lbrace 1..r_i\rbrace$ independently ($r_i \le 100$). Print the expected number of inversions (pairs $i < j$ with $x_i > x_j$), rounded to 6 decimals.
- **Thinking from first principles:** The number of inversions is $\sum_{i<j}I[x_i > x_j]$. Linearity: add $P(x_i > x_j)$ over pairs. Each probability involves two independent uniforms: $P(x_i > x_j) = \frac{1}{r_ir_j}\sum_{a=1}^{r_i}\min(a - 1, r_j)$.

<details><summary>Solution</summary>

$O(n^2\max r)$ = $10^6$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    int n; cin >> n;
    vector<int> r(n);
    for (auto &x : r) cin >> x;
    double e = 0;
    for (int i = 0; i < n; i++)
        for (int j = i + 1; j < n; j++) {
            long long good = 0;
            for (int a = 1; a <= r[i]; a++) good += min(a - 1, r[j]);
            e += (double)good / ((double)r[i] * r[j]);
        }
    printf("%.6f\n", e);
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int n = Integer.parseInt(br.readLine().trim());
        StringTokenizer st = new StringTokenizer(br.readLine());
        int[] r = new int[n];
        for (int i = 0; i < n; i++) r[i] = Integer.parseInt(st.nextToken());
        double e = 0;
        for (int i = 0; i < n; i++)
            for (int j = i + 1; j < n; j++) {
                long good = 0;
                for (int a = 1; a <= r[i]; a++) good += Math.min(a - 1, r[j]);
                e += (double) good / ((double) r[i] * r[j]);
            }
        System.out.println(String.format(Locale.US, "%.6f", e));
    }
}
```

</details>

<!-- test
in:
3
5 2 7
out:
1.057143
-->
<!-- test
in:
1
100
out:
0.000000
-->
<!-- test
in:
4
1 1 1 1
out:
0.000000
-->
<!-- test
in:
5
100 90 80 70 60
out:
6.035952
-->

### Example 3 — Coupon collector modulo a prime  ·  ★ ≈1700 (est.)

- **Source:** Original problem
- **Difficulty:** ≈1700 (est.)
- **Problem:** Each draw yields one of $n$ coupon types uniformly at random ($n \le 10^6$). Print the expected number of draws until $k$ distinct types have been seen ($1 \le k \le n$), modulo $998244353$.
- **Thinking from first principles:** Split the process into phases: phase $i$ ($0 \le i < k$) starts when $i$ types are known and ends at the next new type. Each draw in phase $i$ is new with probability $\frac{n-i}{n}$, so the phase is geometric with mean $\frac{n}{n-i}$. Linearity over phases: $\sum_{i<k}\frac{n}{n-i}$. In residues each term is $n\cdot(n-i)^{-1}$.

<details><summary>Solution</summary>

Inverses $1..n$ by the linear table ([inverses §1.4](../04-Number-Theory/02-modular-arithmetic-and-inverses.md)); $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long P = 998244353LL;
int main() {
    long long n, k; cin >> n >> k;
    vector<long long> inv(n + 1, 1);
    for (long long i = 2; i <= n; i++) inv[i] = (P - (P / i) * inv[P % i] % P) % P;
    long long s = 0;
    for (long long i = 0; i < k; i++) s = (s + n % P * inv[n - i]) % P;
    cout << s << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        final long P = 998244353L;
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        int n = Integer.parseInt(st.nextToken()), k = Integer.parseInt(st.nextToken());
        long[] inv = new long[n + 1];
        inv[1] = 1;
        for (int i = 2; i <= n; i++) inv[i] = (P - (P / i) * inv[(int) (P % i)] % P) % P;
        long s = 0;
        for (int i = 0; i < k; i++) s = (s + n % P * inv[n - i]) % P;
        System.out.println(s);
    }
}
```

</details>

<!-- test
in:
1 1
out:
1
-->
<!-- test
in:
2 2
out:
3
-->
<!-- test
in:
3 3
out:
499122182
-->
<!-- test
in:
1000000 1000000
out:
697618461
-->

### Example 4 — Game on Tree  ·  ★ 2200

- **Source:** [CF 280C · Game on Tree](https://codeforces.com/problemset/problem/280/C) — 2200
- **Difficulty:** 2200
- **Problem:** A rooted tree ($n \le 10^5$, root 1). Each step picks a uniformly random remaining vertex and deletes its whole subtree. Print the expected number of steps until the tree is empty (error $\le 10^{-6}$).
- **Thinking from first principles:** Simulating the distribution is hopeless; count steps as $\sum_v I_v$ where $I_v$ = "vertex $v$ is *picked* (rather than deleted as a descendant)". $v$ is picked iff it is chosen before every one of its proper ancestors. Think of the process as a uniformly random order of all vertices in which deleted vertices are skipped: among $v$ and its $\text{depth}(v) - 1$ ancestors, each is equally likely to come first in that order, so $P(I_v) = 1/\text{depth}(v)$ (root has depth 1). Linearity: $E = \sum_v 1/\text{depth}(v)$.

<details><summary>Solution</summary>

BFS from the root for depths (iterative — recursion depth $10^5$ breaks Java's default stack). $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    int n; scanf("%d", &n);
    vector<vector<int>> g(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; scanf("%d %d", &a, &b); g[a].push_back(b); g[b].push_back(a); }
    vector<int> depth(n + 1, 0);
    queue<int> q; q.push(1); depth[1] = 1;
    double e = 0;
    while (!q.empty()) {
        int v = q.front(); q.pop();
        e += 1.0 / depth[v];
        for (int u : g[v]) if (!depth[u]) { depth[u] = depth[v] + 1; q.push(u); }
    }
    printf("%.10f\n", e);
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        int n = nextInt(in);
        int[] head = new int[n + 1], nxt = new int[2 * n], to = new int[2 * n];
        Arrays.fill(head, -1);
        int ec = 0;
        for (int i = 0; i < n - 1; i++) {
            int a = nextInt(in), b = nextInt(in);
            to[ec] = b; nxt[ec] = head[a]; head[a] = ec++;
            to[ec] = a; nxt[ec] = head[b]; head[b] = ec++;
        }
        int[] depth = new int[n + 1], queue = new int[n];
        int qh = 0, qt = 0;
        queue[qt++] = 1; depth[1] = 1;
        double e = 0;
        while (qh < qt) {
            int v = queue[qh++];
            e += 1.0 / depth[v];
            for (int id = head[v]; id != -1; id = nxt[id]) { int u = to[id]; if (depth[u] == 0) { depth[u] = depth[v] + 1; queue[qt++] = u; } }
        }
        System.out.println(String.format(Locale.US, "%.10f", e));
    }
    private static int nextInt(DataInputStream in) throws IOException {
        int r = 0, b = in.read();
        while (b < '0') b = in.read();
        while (b >= '0') { r = r * 10 + b - '0'; b = in.read(); }
        return r;
    }
}
```

</details>

<!-- test
in:
2
1 2
out:
1.5
-->
<!-- test
in:
3
1 2
1 3
out:
2.0
-->
<!-- test
in:
1
out:
1.0
-->
<!-- test
in:
5
1 2
2 3
3 4
4 5
out:
2.2833333333
-->

### Example 5 — Beautiful Mirrors  ·  ★ 2100

- **Source:** [CF 1265E · Beautiful Mirrors](https://codeforces.com/problemset/problem/1265/E) — 2100
- **Difficulty:** 2100
- **Problem:** $n \le 2\cdot10^5$ mirrors are asked in order, one per day; mirror $i$ says "beautiful" with probability $p_i/100$. On "yes" move to the next mirror (after mirror $n$, stop happily); on "no" restart from mirror 1 the next day. Print the expected number of days modulo $998244353$.
- **Thinking from first principles:** Let $E$ be the expected days from the start. A run from mirror 1 succeeds fully with probability $q_n = \prod p_i$; it fails at mirror $i$ with probability $q_{i-1}(1 - p_i)$ after using $i$ days, and then restarts — the future is again $E$. Total expectation:

$$E = \sum_{i=1}^{n}q_{i-1}(1 - p_i)(i + E) + q_n\cdot n.$$

Collecting $E$: $E(1 - (1 - q_n)) = \sum_i i\,q_{i-1}(1 - p_i) + nq_n$. The right side telescopes (since $q_{i-1}(1 - p_i) = q_{i-1} - q_i$) to $\sum_{i=0}^{n-1}q_i$. Hence

$$E = \frac{1 + q_1 + q_2 + \dots + q_{n-1}}{q_n}.$$

<details><summary>Solution</summary>

Work in residues: $p_i \mapsto p_i\cdot100^{-1}$, prefix products, one inverse. $O(n + \log P)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long P = 998244353LL;
long long power(long long a, long long e) { long long r = 1; a %= P; for (; e; e >>= 1, a = a * a % P) if (e & 1) r = r * a % P; return r; }
int main() {
    int n; scanf("%d", &n);
    long long inv100 = power(100, P - 2), q = 1, num = 0;
    for (int i = 0; i < n; i++) {
        long long p; scanf("%lld", &p);
        num = (num + q) % P;                  // adds q_0 .. q_{n-1}
        q = q * (p * inv100 % P) % P;          // q_{i+1}
    }
    printf("%lld\n", num * power(q, P - 2) % P);
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long P = 998244353L;
    static long power(long a, long e) { long r = 1; a %= P; for (; e > 0; e >>= 1, a = a * a % P) if ((e & 1) == 1) r = r * a % P; return r; }
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int n = Integer.parseInt(br.readLine().trim());
        StringTokenizer st = new StringTokenizer(br.readLine());
        long inv100 = power(100, P - 2), q = 1, num = 0;
        for (int i = 0; i < n; i++) {
            long p = Long.parseLong(st.nextToken());
            num = (num + q) % P;
            q = q * (p * inv100 % P) % P;
        }
        System.out.println(num * power(q, P - 2) % P);
    }
}
```

</details>

<!-- test
in:
1
50
out:
2
-->
<!-- test
in:
3
10 20 50
out:
112
-->
<!-- test
in:
2
100 100
out:
2
-->
<!-- test
in:
4
1 99 37 64
out:
27473958
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Linearity needs no independence** — but $E[XY] = E[X]E[Y]$ and $P(A\cap B) = P(A)P(B)$ do. Check before multiplying.
2. **Do not compute $k^n$ and then divide by $m^n$** — overflow/inf. Compute $(k/m)^n$, or work in $\log$ space.
3. **Printing doubles in Java**: `String.format` uses the default locale — on a machine with a comma decimal separator it prints `3,5`. Always pass `Locale.US` (or use `printf` with `Locale.US`).
4. **`%.6f` rounds**; the judge's checker usually tolerates $10^{-6}$, but "rounded to 6 decimals" problems (CSES) compare exactly — print exactly the requested precision.
5. **Modular expectations: never divide by a residue that might be $0$.** In Beautiful Mirrors, $q_n \ne 0$ as a rational because all $p_i \ge 1$; if some $p_i$ could be $0$, the expectation is infinite.
6. **Self-referential equations** ($E = a + bE$) are solvable only if $b \ne 1$; $b = 1$ means the process never ends with positive probability.
7. **Expectation DP direction**: define $E[s]$ = expected *remaining* cost from state $s$ and compute from terminal states backwards; forward DP of probabilities is the dual.
8. **Floating sums**: add many small terms in increasing order (or use `long double`) when the answer must be accurate to $10^{-9}$.
9. **Java recursion depth** on trees of $10^5$ — use iterative BFS/DFS (Example 4) or run in a thread with a big stack.

---

## 7. Going further (toward 2400–2600+)

- **Expectation DP and Markov chains**: cyclic state graphs need linear systems ([Gaussian elimination](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md)); structured ones (paths, trees) can be solved by expressing $E_v = a_vE_{\text{parent}} + b_v$ — [probability DP](../06-Dynamic-Programming/10-probability-and-expected-value-dp.md).
- **Min–max inclusion–exclusion** for "expected time until all events happen" with unequal probabilities (🧊).
- **Martingales / potential functions** (🧊): find $\Phi$ with $E[\Phi_{t+1} - \Phi_t] = -1$; then $E[T] = \Phi_0 - \Phi_{\text{end}}$ — the standard tool for "expected steps until all values equal" problems at 2500+.
- **Expected value of squares** via pairs, or via maintaining $E[X]$ and $E[X^2]$ together ([CF 235B · Let's Play Osu!](https://codeforces.com/problemset/problem/235/B) — 2000).
- **Randomised algorithms**: analysis of hashing, treaps, quickselect uses the same indicator technique — [randomised algorithms](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md).

---

## 8. Practice ladder

**≤ 1700**
- [ ] [CF 9A · Die Roll](https://codeforces.com/problemset/problem/9/A) — 800
- [ ] [CF 476B · Dreamoon and WiFi](https://codeforces.com/problemset/problem/476/B) — 1300
- [ ] [CF 839C · Journey](https://codeforces.com/problemset/problem/839/C) — 1500
- [ ] [CF 453A · Little Pony and Expected Maximum](https://codeforces.com/problemset/problem/453/A) — 1600
- [ ] [CF 1461C · Random Events](https://codeforces.com/problemset/problem/1461/C) — 1500
- [ ] [CSES 1725 · Dice Probability](https://cses.fi/problemset/task/1725)
- [ ] [CSES 1727 · Candy Lottery](https://cses.fi/problemset/task/1727)
- [ ] [CSES 1728 · Inversion Probability](https://cses.fi/problemset/task/1728)

**1700–2100**
- [ ] [CF 518D · Ilya and Escalator](https://codeforces.com/problemset/problem/518/D) — 1700
- [ ] [CF 148D · Bag of mice](https://codeforces.com/problemset/problem/148/D) — 1800
- [ ] [CF 1743D · Problem with Random Tests](https://codeforces.com/problemset/problem/1743/D) — 1700
- [ ] [CF 540D · Bad Luck Island](https://codeforces.com/problemset/problem/540/D) — 1900
- [ ] [CF 1753C · Wish I Knew How to Sort](https://codeforces.com/problemset/problem/1753/C) — 2000
- [ ] [CF 235B · Let's Play Osu!](https://codeforces.com/problemset/problem/235/B) — 2000
- [ ] [CF 1265E · Beautiful Mirrors](https://codeforces.com/problemset/problem/1265/E) — 2100
- [ ] [CSES 1726 · Moving Robots](https://cses.fi/problemset/task/1726)

**2100–2600**
- [ ] [CF 280C · Game on Tree](https://codeforces.com/problemset/problem/280/C) — 2200
- [ ] [CF 1097D · Makoto and a Blackboard](https://codeforces.com/problemset/problem/1097/D) — 2200
- [ ] [CF 1096F · Inversion Expectation](https://codeforces.com/problemset/problem/1096/F) — 2300
- [ ] [CF 1540B · Tree Array](https://codeforces.com/problemset/problem/1540/B) — 2300
- [ ] [CF 1139D · Steps to One](https://codeforces.com/problemset/problem/1139/D) — 2300
- [ ] [CF 1187F · Expected Square Beauty](https://codeforces.com/problemset/problem/1187/F) — 2500
- [ ] [CF 1278F · Cards](https://codeforces.com/problemset/problem/1278/F) — 2600

---

## 9. LeetCode / FAANG cross-reference

- [LC 1227 · Airplane Seat Assignment Probability](https://leetcode.com/problems/airplane-seat-assignment-probability/) — Medium — symmetry argument gives $\frac12$ for $n \ge 2$.
- [LC 837 · New 21 Game](https://leetcode.com/problems/new-21-game/) — Medium — probability DP with a sliding-window sum.
- [LC 688 · Knight Probability in Chessboard](https://leetcode.com/problems/knight-probability-in-chessboard/) — Medium — forward probability DP.
- [LC 808 · Soup Servings](https://leetcode.com/problems/soup-servings/) — Medium — memoised expectation; for large $n$ the answer tends to 1.
- [LC 470 · Implement Rand10() Using Rand7()](https://leetcode.com/problems/implement-rand10-using-rand7/) — Medium — rejection sampling; expected calls via the geometric distribution.
- [LC 384 · Shuffle an Array](https://leetcode.com/problems/shuffle-an-array/) — Medium — Fisher–Yates; prove every permutation has probability $1/n!$.
- [LC 382 · Linked List Random Node](https://leetcode.com/problems/linked-list-random-node/) — Medium — reservoir sampling: keep item $i$ with probability $1/i$.
- [LC 528 · Random Pick with Weight](https://leetcode.com/problems/random-pick-with-weight/) — Medium — prefix sums + binary search.

Interviewers love reservoir sampling, Fisher–Yates and rejection sampling; be ready to *prove* uniformity.

---

## 10. Self-check

1. Prove linearity of expectation without assuming independence.
2. Expected number of fixed points of a random permutation? Expected number of inversions?
3. Derive $E = 1/p$ for the geometric distribution in one line.
4. Derive the coupon-collector expectation.
5. Prove $E[X] = \sum_{k\ge1}P(X\ge k)$ for non-negative integer $X$.
6. Why is $P(\text{vertex } v \text{ is picked}) = 1/\text{depth}(v)$ in Game on Tree?
7. Fair random walk on $[0, 10]$ from $3$: probability of reaching $10$ first, and expected time?
8. How do you print $\frac{3}{4}$ modulo $998244353$?

<details><summary>Answers</summary>

1. $E[X+Y] = \sum_\omega(X(\omega) + Y(\omega))P(\omega)$ splits into two sums; no joint structure is used.
2. $\sum_i P(\pi(i) = i) = n\cdot\frac1n = 1$; each pair is inverted with probability $\frac12$: $\frac{n(n-1)}{4}$.
3. $E = 1 + (1-p)E$.
4. Phase $i$ (having $i$ types) lasts $\frac{n}{n-i}$ draws in expectation; sum over $i = 0..n-1$: $nH_n$.
5. $X = \sum_{k\ge1}[X \ge k]$; take expectations.
6. In the random order of all vertices, $v$ is picked iff it precedes all its ancestors; by symmetry each of the $\text{depth}(v)$ vertices on the root path is first with equal probability.
7. $3/10$; $3\cdot7 = 21$ steps.
8. $4^{-1} \equiv 748683265$ (check: $4\cdot748683265 = 3p + 1$), so $\frac34 \equiv 3\cdot748683265 - 2p = 249561089$.

</details>
