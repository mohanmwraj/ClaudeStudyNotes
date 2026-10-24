# Probability and Expected-Value DP

> **Band:** 🔵→🟠 1500–2400 · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [DP first principles](01-dp-first-principles-and-state-design.md), [probability and expectation](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md), [modular inverses](../04-Number-Theory/02-modular-arithmetic-and-inverses.md)
> **You can say you know this when:** you choose between pushing probability mass forward and computing expectations backward without thinking; you solve self-loops by moving the term to the left side; you express a cyclic dependency on one unknown as $E_i = a_i + b_iE_0$ and solve for it; you compute expected values modulo a prime; you reach for linearity of expectation before writing any DP; and you know when the equations really are a linear system (Gaussian elimination, or a tridiagonal sweep).

Randomness does not change what a DP is — it changes the semiring. Probabilities flow along transitions with $(+, \times)$; expectations satisfy the same Bellman equation as a min-cost DP with $\min$ replaced by a weighted average. The new phenomena are self-loops ("nothing happens this step"), cycles that are not self-loops (random walks), and exact answers modulo a prime.

---

## 1. First principles — why this works

### 1.1 Markov states: what the future's *distribution* depends on

A random process moves between states; the transition probabilities from the current state must not depend on how we got there — the **Markov property**. That is the probabilistic version of "the state captures everything the future needs" ([first principles](01-dp-first-principles-and-state-design.md) §1.2). Once the state is Markov:

- the **probability** of being in state $t$ after $k$ steps satisfies $P_{k+1}(t) = \sum_s P_k(s)\, p(s \to t)$ (law of total probability);
- the **expected remaining cost** from state $s$ satisfies $E(s) = c(s) + \sum_t p(s\to t)\, E(t)$ (law of total expectation), with $E = 0$ on absorbing states.

Identical histories in distribution give identical futures, so one number per state suffices.

### 1.2 Forward probability vs backward expectation

| | Forward (push probability) | Backward (pull expectation) |
|---|---|---|
| quantity per state | $P(\text{reach } s)$ | $E[\text{cost from } s \text{ to the end}]$ |
| starts at | the initial state, $P=1$ | absorbing states, $E=0$ |
| natural for | "probability that …", distributions after $k$ steps, expected value of a *final* quantity ($\sum_s P(s)\cdot\text{val}(s)$) | "expected number of steps until …", optimal stopping, games |
| order | topological from the start | topological from the end |

Both are correct; pick the one whose base case is trivial. Expected steps until absorption is backward, because the starting distribution is a point mass and the end is fixed — the backward recurrence never needs to know how likely a state is.

A forward alternative for expectations exists — accumulate $\sum_s P(s)\cdot c(s)$ over all visited states — but it requires the process to visit each state at most once per run (a DAG), and is awkward with self-loops.

### 1.3 Self-loops — move the term to the left

If with probability $q$ "nothing happens" (the process stays in $s$), the backward equation contains $E(s)$ on both sides:
$$E(s) = 1 + q\,E(s) + \sum_{t \ne s} p_t E(t) \;\Longrightarrow\; E(s) = \frac{1 + \sum_{t\ne s} p_t E(t)}{1 - q}.$$
This is just algebra on one equation, valid when $q < 1$. Intuition: the number of attempts until something happens is geometric with mean $\frac{1}{1-q}$. **Sushi** (AtCoder DP J, Example 3) is exactly this: choosing an empty plate is a self-loop.

### 1.4 Cycles through one special state — express everything in terms of it

When every cycle passes through one state (typically "start over"), write each $E_i$ as an **affine function of that unknown**, $E_i = a_i + b_i E_0$, computed backward from the end; then the equation for $E_0$ itself is linear in one variable:
$$E_0 = a_0 + b_0 E_0 \;\Longrightarrow\; E_0 = \frac{a_0}{1 - b_0}.$$
**Beautiful Mirrors** (CF 1265E, Example 4) is the archetype — failure sends you back to mirror 1. The same trick handles "restart with probability $p$", "lose everything and go back" and tree walks that return to the root.

### 1.5 Genuine linear systems

A random walk on a general graph produces $n$ coupled equations $E_v = 1 + \sum_u p(v\to u)E_u$. That is a linear system: Gaussian elimination in $O(n^3)$ ([Gaussian elimination](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md)). Structure often helps:

- **tridiagonal** (a walk on a line, or within a row): solve in $O(n)$ with the Thomas algorithm (Example 5);
- **block structure** (moves only within a row or downward): solve row by row from the bottom, each row a small system;
- **trees**: express a child's value as an affine function of its parent's and propagate (the §1.4 trick, vertex by vertex).

Iterating $E \leftarrow 1 + PE$ ("value iteration") converges geometrically for absorbing chains and is a quick way to *check* an answer with doubles, but rarely precise or fast enough as the main method.

### 1.6 Expected values modulo a prime

"Print the answer as $P \cdot Q^{-1} \bmod 998244353$" means: the answer is a rational number and every formula uses only $+,-,\times,\div$, so carry out the same computation in the field $\mathbb F_p$. Probabilities become residues ($\frac{x}{100} \to x \cdot 100^{-1}$), division becomes multiplication by a modular inverse (Fermat: $a^{-1} = a^{p-2}$). It is valid as long as no denominator is $\equiv 0 \pmod p$ — which problem setters guarantee. You cannot compare residues ("is this probability $> 1/2$?") — keep such decisions in exact or floating arithmetic.

### 1.7 Linearity of expectation — the shortcut that kills DPs

$E[X_1 + \dots + X_k] = \sum E[X_i]$ **even when the $X_i$ are dependent**. Write the quantity as a sum of indicators and compute each probability separately:

- Expected number of operations in "repeatedly pick a random remaining vertex and delete its subtree" (CF 280C): vertex $v$ is picked itself iff it is chosen before all its ancestors — probability $1/\text{depth}(v)$; the answer is $\sum_v 1/\text{depth}(v)$, no DP at all.
- Expected number of inversions of a random permutation: each pair is inverted with probability $\frac12$ — $\binom n2/2$.
- $E[X] = \sum_{k \ge 1} P(X \ge k)$ for non-negative integer $X$ (expected maximum of dice, CF 453A).

Before designing an expected-value DP, ask "is this a sum of indicators?" ([contribution technique](../05-Combinatorics-and-Probability/07-contribution-technique.md)).

**Non-linear quantities** (expected square, expected product) are not handled by linearity directly, but often by carrying several moments in the state: $E[(L+1)^2] = E[L^2] + 2E[L] + 1$ (CF 235B *Let's Play Osu!*).

### 1.8 Precision

Doubles have ~15–16 significant digits. Probability DPs that only add non-negative terms are numerically benign. Dangers: subtracting nearly equal numbers ($1 - q$ when $q \approx 1$ — rewrite as the sum of the other probabilities), very long products (underflow to 0 — use logs or rescale), and printing too few digits (`printf("%.10f")`; in Java `String.format("%.10f", x)` or `PrintWriter.printf`).

---

## 2. Formulas, definitions and identities

| Identity | Formula | Use |
|---|---|---|
| total probability | $P(t) = \sum_s P(s)\,p(s\to t)$ | forward DP |
| total expectation | $E(s) = c(s) + \sum_t p(s\to t)E(t)$ | backward DP |
| self-loop | $E(s) = \frac{c(s) + \sum_{t\ne s} p_tE(t)}{1-q}$ | Sushi |
| one cyclic unknown | $E_i = a_i + b_iE_0 \Rightarrow E_0 = \frac{a_0}{1-b_0}$ | Mirrors |
| geometric distribution | $E[\text{trials until success}] = 1/p$ | |
| coupon collector | $E = n H_n = n\sum_{k=1}^n \frac1k$ | |
| tail sum | $E[X] = \sum_{k\ge1} P(X \ge k)$, $X \in \mathbb Z_{\ge 0}$ | expected max |
| linearity | $E[\sum X_i] = \sum E[X_i]$ | indicators |
| Wald | $E[\sum_{i=1}^N Y_i] = E[N]\,E[Y]$ for i.i.d. $Y_i$, stopping time $N$ | repeated attempts |
| mod $p$ | $\frac ab \equiv a\cdot b^{p-2} \pmod p$ | exact answers |

**Repeated independent attempts** (each costs $C$ in expectation and succeeds with probability $\pi$): expected total $= C/\pi$. Beautiful Mirrors: $C = \sum_{i=1}^{n}\prod_{j<i}p_j$, $\pi = \prod_j p_j$.

**Thomas algorithm** for $a_jx_{j-1} + b_jx_j + c_jx_{j+1} = d_j$: forward $c'_j = \frac{c_j}{b_j - a_jc'_{j-1}}$, $d'_j = \frac{d_j - a_jd'_{j-1}}{b_j - a_jc'_{j-1}}$; backward $x_j = d'_j - c'_jx_{j+1}$. Stable when the matrix is diagonally dominant ($|b_j| \ge |a_j|+|c_j|$, strictly somewhere) — true for absorbing random walks.

---

## 3. Implementation (C++ and Java)

### 3.1 Modular arithmetic for expected values

```cpp
const long long MODP = 998244353;
long long mpow(long long b, long long e) {
    long long r = 1;
    b %= MODP;
    if (b < 0) b += MODP;
    for (; e > 0; e >>= 1, b = b * b % MODP)
        if (e & 1) r = r * b % MODP;
    return r;
}
long long minv(long long a) { return mpow(a, MODP - 2); }        // MODP prime, a not divisible by it
long long frac(long long num, long long den) { return (num % MODP + MODP) % MODP * minv(den) % MODP; }
```

```java
static final long MODP = 998244353L;

static long mpow(long b, long e) {
    long r = 1;
    b %= MODP;
    if (b < 0) b += MODP;
    for (; e > 0; e >>= 1, b = b * b % MODP)
        if ((e & 1) == 1) r = r * b % MODP;
    return r;
}

static long minv(long a) { return mpow(a, MODP - 2); }

static long frac(long num, long den) { return (num % MODP + MODP) % MODP * minv(den) % MODP; }
```

### 3.2 Tridiagonal solver (Thomas algorithm)

```cpp
// Solves a[j]*x[j-1] + b[j]*x[j] + c[j]*x[j+1] = d[j] for j = 0..n-1 (a[0], c[n-1] ignored).
vector<double> thomas(vector<double> a, vector<double> b, vector<double> c, vector<double> d) {
    int n = b.size();
    for (int j = 1; j < n; j++) {                      // eliminate the sub-diagonal
        double m = a[j] / b[j - 1];
        b[j] -= m * c[j - 1];
        d[j] -= m * d[j - 1];
    }
    vector<double> x(n);
    x[n - 1] = d[n - 1] / b[n - 1];
    for (int j = n - 2; j >= 0; j--) x[j] = (d[j] - c[j] * x[j + 1]) / b[j];
    return x;
}
```

```java
static double[] thomas(double[] a, double[] b, double[] c, double[] d) {
    int n = b.length;
    b = b.clone();
    d = d.clone();
    for (int j = 1; j < n; j++) {
        double m = a[j] / b[j - 1];
        b[j] -= m * c[j - 1];
        d[j] -= m * d[j - 1];
    }
    double[] x = new double[n];
    x[n - 1] = d[n - 1] / b[n - 1];
    for (int j = n - 2; j >= 0; j--) x[j] = (d[j] - c[j] * x[j + 1]) / b[j];
    return x;
}
```

---

## 4. Recognising the pattern

| Signal | Technique |
|---|---|
| "probability that after $k$ steps …", independent events with given probabilities | forward probability DP |
| "expected number of steps/days/operations until …" | backward expectation from the absorbing states |
| "with probability $q$ nothing happens" / choose a useless option | self-loop: divide by $1-q$ |
| failure sends you back to the start | $E_i = a_i + b_iE_0$ |
| random walk on a line or within rows | tridiagonal / row-by-row systems |
| random walk on a general small graph ($n \le 500$) | Gaussian elimination |
| "expected number of …" that is a count of events | linearity of expectation — no DP |
| "expected value of a square / product" | carry several moments in the state |
| "print $P\cdot Q^{-1} \bmod p$" | same DP in $\mathbb F_p$ |
| optimal strategy with restarts ("you may reset at any time") | binary search on the expected value (CF 865C) |

---

## 5. Worked examples (graded)

### Example 1 — Coins (forward probability)  ·  ★ ≈1300 (est.)

- **Source:** [AtCoder DP I · Coins](https://atcoder.jp/contests/dp/tasks/dp_i)
- **Difficulty:** ≈1300 (est.)
- **Problem:** $n \le 2999$ (odd) coins; coin $i$ shows heads with probability $p_i$. Probability that there are more heads than tails.
- **Thinking from first principles:** Enumerating $2^n$ outcomes is hopeless, but the question only cares about the **number** of heads. After tossing coins $1..i$, the future's distribution depends only on how many heads so far — push probability mass: $P_i(h) = P_{i-1}(h-1)p_i + P_{i-1}(h)(1-p_i)$. $n^2/2 = 4.5\cdot10^6$ updates.

<details><summary>Solution</summary>

One array, $h$ downward (like 0/1 knapsack). Answer $\sum_{h > n/2} P_n(h)$. $O(n^2)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    int n;
    scanf("%d", &n);
    vector<double> P(n + 1, 0.0);
    P[0] = 1.0;
    for (int i = 1; i <= n; i++) {
        double p;
        scanf("%lf", &p);
        for (int h = i; h >= 0; h--)                  // downward: P[h-1] is still the old layer
            P[h] = P[h] * (1 - p) + (h > 0 ? P[h - 1] * p : 0.0);
    }
    double ans = 0;
    for (int h = n / 2 + 1; h <= n; h++) ans += P[h];
    printf("%.10f\n", ans);
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken();
        int n = (int) st.nval;
        double[] P = new double[n + 1];
        P[0] = 1.0;
        for (int i = 1; i <= n; i++) {
            st.nextToken();
            double p = st.nval;
            for (int h = i; h >= 0; h--) P[h] = P[h] * (1 - p) + (h > 0 ? P[h - 1] * p : 0.0);
        }
        double ans = 0;
        for (int h = n / 2 + 1; h <= n; h++) ans += P[h];
        System.out.printf("%.10f%n", ans);
    }
}
```

</details>

<!-- test
in:
3
0.10 0.50 0.90
out:
0.5000000000
-->
<!-- test
in:
1
0.50
out:
0.5000000000
-->
<!-- test
in:
5
0.42 0.01 0.42 0.99 0.42
out:
0.3821815872
-->

### Example 2 — Ilya and Escalator (expected final value)  ·  ★ 1700

- **Source:** [CF 518D · Ilya and Escalator](https://codeforces.com/problemset/problem/518/D) — 1700
- **Difficulty:** 1700
- **Problem:** $n \le 2000$ people queue for an escalator. Each second, with probability $p$ the first person in the queue steps on (and stays on); otherwise nobody moves. After $t \le 2000$ seconds, what is the expected number of people on the escalator?
- **Thinking from first principles:** The quantity is a function of the **final** state, so compute the final distribution forward: state $(\text{seconds}, \text{people on})$. When everybody is already on, the state is absorbing. Expected value $= \sum_j j\cdot P_t(j)$. (A closed form exists — $\sum_k \binom tk p^k(1-p)^{t-k}\min(n,k)$ — but the DP generalises to rules a formula can't capture.)

<details><summary>Solution</summary>

Rolling array over $j$; $O(nt)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    int n, t;
    double p;
    scanf("%d %lf %d", &n, &p, &t);
    vector<double> P(n + 1, 0.0), Q(n + 1);
    P[0] = 1.0;
    for (int s = 0; s < t; s++) {
        fill(Q.begin(), Q.end(), 0.0);
        for (int j = 0; j <= n; j++) {
            if (j == n) { Q[n] += P[n]; continue; }   // queue empty: absorbing
            Q[j + 1] += P[j] * p;
            Q[j] += P[j] * (1 - p);
        }
        swap(P, Q);
    }
    double ans = 0;
    for (int j = 0; j <= n; j++) ans += j * P[j];
    printf("%.10f\n", ans);
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        int n = Integer.parseInt(st.nextToken());
        double p = Double.parseDouble(st.nextToken());
        int t = Integer.parseInt(st.nextToken());
        double[] P = new double[n + 1], Q = new double[n + 1];
        P[0] = 1.0;
        for (int s = 0; s < t; s++) {
            Arrays.fill(Q, 0.0);
            for (int j = 0; j <= n; j++) {
                if (j == n) { Q[n] += P[n]; continue; }
                Q[j + 1] += P[j] * p;
                Q[j] += P[j] * (1 - p);
            }
            double[] tmp = P; P = Q; Q = tmp;
        }
        double ans = 0;
        for (int j = 0; j <= n; j++) ans += j * P[j];
        System.out.printf("%.10f%n", ans);
    }
}
```

</details>

<!-- test
in:
3 0.50 2
out:
1.0000000000
-->
<!-- test
in:
5 0.30 4
out:
1.2000000000
-->
<!-- test
in:
2 1.00 10
out:
2.0000000000
-->

### Example 3 — Sushi (self-loops)  ·  ★ ≈1900 (est.)

- **Source:** [AtCoder DP J · Sushi](https://atcoder.jp/contests/dp/tasks/dp_j)
- **Difficulty:** ≈1900 (est.)
- **Problem:** $N \le 300$ plates, plate $i$ has $a_i \in \{1,2,3\}$ pieces. Repeatedly roll a fair $N$-sided die; if the chosen plate has a piece, eat one. Expected number of rolls until everything is eaten.
- **Thinking from first principles:** The plates are interchangeable except for how many pieces they hold, so the Markov state is $(c_1, c_2, c_3)$ = number of plates with 1, 2, 3 pieces — $O(N^3/6)$ states instead of $4^N$. From that state, a roll hits a plate with $k$ pieces with probability $c_k/N$, and an empty plate with probability $c_0/N$ — a **self-loop**. Writing the equation and moving the self-loop term left gives $E = \frac{N + c_1E_1 + c_2E_2 + c_3E_3}{c_1+c_2+c_3}$ where $E_k$ is the state after eating from a $k$-plate. Evaluation order: every successor has fewer total pieces; looping $c_3, c_2, c_1$ upward suffices (check each successor index is smaller in the loop order).

<details><summary>Solution</summary>

$E(c_1,c_2,c_3)$ with transitions $(c_1-1,c_2,c_3)$, $(c_1+1,c_2-1,c_3)$, $(c_1,c_2+1,c_3-1)$. Jagged storage with $c_1 \le N - c_2 - c_3$ keeps memory at $\approx N^3/6$ doubles. $O(N^3)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    int N;
    scanf("%d", &N);
    int cnt[4] = {0, 0, 0, 0};
    for (int i = 0; i < N; i++) { int a; scanf("%d", &a); cnt[a]++; }
    // E[c3][c2][c1] with c1 + c2 + c3 <= N
    vector<vector<vector<double>>> E(N + 1);
    for (int c3 = 0; c3 <= N; c3++) {
        E[c3].resize(N - c3 + 1);
        for (int c2 = 0; c2 + c3 <= N; c2++) {
            E[c3][c2].assign(N - c3 - c2 + 1, 0.0);
            for (int c1 = 0; c1 + c2 + c3 <= N; c1++) {
                int s = c1 + c2 + c3;
                if (s == 0) continue;
                double e = N;                          // N / s is the expected rolls until a non-empty plate
                if (c1) e += c1 * E[c3][c2][c1 - 1];
                if (c2) e += c2 * E[c3][c2 - 1][c1 + 1];
                if (c3) e += c3 * E[c3 - 1][c2 + 1][c1];
                E[c3][c2][c1] = e / s;
            }
        }
    }
    printf("%.10f\n", E[cnt[3]][cnt[2]][cnt[1]]);
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken();
        int N = (int) st.nval;
        int[] cnt = new int[4];
        for (int i = 0; i < N; i++) { st.nextToken(); cnt[(int) st.nval]++; }
        double[][][] E = new double[N + 1][][];
        for (int c3 = 0; c3 <= N; c3++) {
            E[c3] = new double[N - c3 + 1][];
            for (int c2 = 0; c2 + c3 <= N; c2++) {
                E[c3][c2] = new double[N - c3 - c2 + 1];
                for (int c1 = 0; c1 + c2 + c3 <= N; c1++) {
                    int s = c1 + c2 + c3;
                    if (s == 0) continue;
                    double e = N;
                    if (c1 > 0) e += c1 * E[c3][c2][c1 - 1];
                    if (c2 > 0) e += c2 * E[c3][c2 - 1][c1 + 1];
                    if (c3 > 0) e += c3 * E[c3 - 1][c2 + 1][c1];
                    E[c3][c2][c1] = e / s;
                }
            }
        }
        System.out.printf("%.10f%n", E[cnt[3]][cnt[2]][cnt[1]]);
    }
}
```

</details>

<!-- test
in:
3
1 2 3
out:
10.5486111111
-->
<!-- test
in:
1
3
out:
3.0000000000
-->
<!-- test
in:
4
3 3 3 3
out:
19.5659054101
-->

### Example 4 — Beautiful Mirrors (cycle through the start, mod $p$)  ·  ★ 2100

- **Source:** [CF 1265E · Beautiful Mirrors](https://codeforces.com/problemset/problem/1265/E) — 2100
- **Difficulty:** 2100
- **Problem:** $n \le 2\cdot10^5$ mirrors; mirror $i$ says "beautiful" with probability $p_i/100$. Each day you ask the current mirror (starting with mirror 1): on "beautiful" you move to the next mirror tomorrow (and stop after mirror $n$); otherwise you start again from mirror 1 tomorrow. Expected number of days, mod $998244353$.
- **Thinking from first principles:** $E_i$ = expected days starting at mirror $i$; $E_i = 1 + p_iE_{i+1} + (1-p_i)E_1$, $E_{n+1}=0$. Every equation mentions $E_1$ — a cycle through the start — so a backward pass cannot finish. Treat $E_1$ as an unknown: write $E_i = a_i + b_iE_1$, compute $(a_i, b_i)$ from $i = n$ down to $1$, then solve $E_1 = a_1 + b_1E_1$. All in $\mathbb F_p$ since probabilities are $p_i\cdot 100^{-1}$.

<details><summary>Solution</summary>

$a_{n+1}=b_{n+1}=0$; $a_i = 1 + p_ia_{i+1}$, $b_i = p_ib_{i+1} + (1-p_i)$; $E_1 = a_1/(1-b_1)$. (Equivalently $E_1 = \frac{\sum_{i}\prod_{j<i}p_j}{\prod_j p_j}$ — expected cost per attempt divided by the success probability.) $O(n + \log p)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

const long long MOD = 998244353;
long long power(long long b, long long e) {
    long long r = 1;
    for (b %= MOD; e > 0; e >>= 1, b = b * b % MOD)
        if (e & 1) r = r * b % MOD;
    return r;
}

int main() {
    int n;
    scanf("%d", &n);
    vector<long long> p(n);
    long long inv100 = power(100, MOD - 2);
    for (auto& x : p) { scanf("%lld", &x); x = x * inv100 % MOD; }
    long long a = 0, b = 0;                           // E_{i} = a + b * E_1, starting from E_{n+1} = 0
    for (int i = n - 1; i >= 0; i--) {
        long long na = (1 + p[i] * a) % MOD;
        long long nb = (p[i] * b + (1 - p[i] + MOD)) % MOD;
        a = na, b = nb;
    }
    long long E1 = a * power((1 - b + MOD) % MOD, MOD - 2) % MOD;
    printf("%lld\n", E1);
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 998244353L;

    static long power(long b, long e) {
        long r = 1;
        b %= MOD;
        for (; e > 0; e >>= 1, b = b * b % MOD) if ((e & 1) == 1) r = r * b % MOD;
        return r;
    }

    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken();
        int n = (int) st.nval;
        long inv100 = power(100, MOD - 2);
        long[] p = new long[n];
        for (int i = 0; i < n; i++) { st.nextToken(); p[i] = (long) st.nval * inv100 % MOD; }
        long a = 0, b = 0;
        for (int i = n - 1; i >= 0; i--) {
            long na = (1 + p[i] * a) % MOD;
            long nb = (p[i] * b + (1 - p[i] + MOD)) % MOD;
            a = na; b = nb;
        }
        System.out.println(a * power((1 - b + MOD) % MOD, MOD - 2) % MOD);
    }
}
```

</details>

<!-- test
in:
1
25
out:
4
-->
<!-- test
in:
3
50 50 50
out:
14
-->
<!-- test
in:
2
100 100
out:
2
-->

### Example 5 — Broken robot (tridiagonal systems)  ·  ★ 2400

- **Source:** [CF 24D · Broken robot](https://codeforces.com/problemset/problem/24/D) — 2400
- **Difficulty:** 2400
- **Problem:** An $N\times M$ board ($N, M \le 1000$); a robot starts at row $i$, column $j$. Each step it stays, moves left, moves right, or moves down — uniformly among the moves that keep it on the board. Expected number of steps to reach the bottom row $N$.
- **Thinking from first principles:** Moves never go up, so rows can be solved from the bottom: when solving row $r$, the values $D_c = E(r+1, c)$ are known. Within a row, though, left/right moves create cycles: $E(r,c)$ depends on $E(r, c\pm1)$ — a linear system, not a DP order. But each equation involves only neighbours: it is **tridiagonal**, solvable in $O(M)$ (Thomas). For an interior column: $E_c = 1 + \frac{E_c + E_{c-1} + E_{c+1} + D_c}{4}$, i.e. $-E_{c-1} + 3E_c - E_{c+1} = 4 + D_c$; at the walls $2E_c - E_{c\pm1} = 3 + D_c$; for $M = 1$ only "stay" and "down" exist, so $E = D + 2$. Diagonal dominance keeps elimination stable. Gaussian elimination on all $NM$ unknowns would be $10^{18}$.

<details><summary>Solution</summary>

Rows $N-1, \dots, i$ bottom-up, one Thomas sweep each. $O(NM)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    int N, M, si, sj;
    scanf("%d %d %d %d", &N, &M, &si, &sj);
    vector<double> E(M, 0.0);                          // row N: already at the bottom
    vector<double> a(M), b(M), c(M), d(M);
    for (int r = N - 1; r >= si; r--) {
        if (M == 1) { E[0] += 2; continue; }
        for (int col = 0; col < M; col++) {
            if (col == 0) { a[col] = 0; b[col] = 2; c[col] = -1; d[col] = 3 + E[col]; }
            else if (col == M - 1) { a[col] = -1; b[col] = 2; c[col] = 0; d[col] = 3 + E[col]; }
            else { a[col] = -1; b[col] = 3; c[col] = -1; d[col] = 4 + E[col]; }
        }
        for (int col = 1; col < M; col++) {            // Thomas: forward elimination
            double m = a[col] / b[col - 1];
            b[col] -= m * c[col - 1];
            d[col] -= m * d[col - 1];
        }
        E[M - 1] = d[M - 1] / b[M - 1];
        for (int col = M - 2; col >= 0; col--) E[col] = (d[col] - c[col] * E[col + 1]) / b[col];
    }
    printf("%.10f\n", E[sj - 1]);
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        int[] v = new int[4];
        for (int k = 0; k < 4; k++) { st.nextToken(); v[k] = (int) st.nval; }
        int N = v[0], M = v[1], si = v[2], sj = v[3];
        double[] E = new double[M], a = new double[M], b = new double[M], c = new double[M], d = new double[M];
        for (int r = N - 1; r >= si; r--) {
            if (M == 1) { E[0] += 2; continue; }
            for (int col = 0; col < M; col++) {
                if (col == 0) { a[col] = 0; b[col] = 2; c[col] = -1; d[col] = 3 + E[col]; }
                else if (col == M - 1) { a[col] = -1; b[col] = 2; c[col] = 0; d[col] = 3 + E[col]; }
                else { a[col] = -1; b[col] = 3; c[col] = -1; d[col] = 4 + E[col]; }
            }
            for (int col = 1; col < M; col++) {
                double m = a[col] / b[col - 1];
                b[col] -= m * c[col - 1];
                d[col] -= m * d[col - 1];
            }
            E[M - 1] = d[M - 1] / b[M - 1];
            for (int col = M - 2; col >= 0; col--) E[col] = (d[col] - c[col] * E[col + 1]) / b[col];
        }
        System.out.printf("%.10f%n", E[sj - 1]);
    }
}
```

</details>

<!-- test
in:
6 5
2 3
out:
14.7856020764
-->
<!-- test
in:
1 1
1 1
out:
0.0000000000
-->
<!-- test
in:
5 2
1 2
out:
12.0000000000
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Is it a sum of indicators?** Check linearity of expectation before writing a DP (§1.7) — many 2000+ "expected value" problems have a one-line answer.
2. **Self-loops:** never iterate "until convergence"; solve the one-variable equation (§1.3).
3. **A cycle through one state:** carry $E = a + bE_0$ and solve at the end (§1.4); the same trick works on trees with "return to root".
4. **Mod-$p$ expectations:** convert probabilities once ($x \cdot 100^{-1}$), keep everything reduced, and remember $1 - p$ must be written `(1 - p + MOD) % MOD`.
5. **Don't compare modular values** — decisions ("which option is better?") need real numbers or exact fractions.
6. **Precision:** print at least 9–10 decimals; avoid $1 - q$ with $q$ close to 1 (sum the complementary probabilities instead); long products may underflow.
7. **State symmetry:** interchangeable objects (plates, identical dice) collapse into counts — Sushi's $(c_1,c_2,c_3)$ instead of $4^N$.
8. **Evaluation order with self-loops removed:** verify every successor is strictly "smaller" in your loop order (Example 3's index check).
9. **Expected value of a function of the final state** — forward distribution; **expected cost of the process** — backward expectation.
10. **Java `double` printing:** `System.out.println(x)` may print `1.0E-5`; use `printf("%.10f%n", x)`.
11. **Reading decimals in Java:** `StreamTokenizer` parses `0.42` correctly as a double; for exact decimal inputs (like `0.50` meaning 50/100) parse the string if exactness matters.
12. **Memory of 3-D probability tables:** use jagged arrays bounded by $c_1+c_2+c_3 \le N$ (6× smaller than a cube).

---

## 7. Going further (toward 2400–2600+)

- **Optimal stopping with restarts** (CF 865C *Gotta Go Fast*): the optimal decision "reset or continue" depends on $E_0$ itself; binary search on $E_0$, run the DP with "reset costs $E_0$", and compare the computed start value with the guess — the map is monotone.
- **Expected value via Möbius / divisor DP** (CF 1139D *Steps to One*): $E[\text{length}] = \sum_k P(\text{length} \ge k)$, and $P(\gcd \text{ of the first } k \ne 1)$ by inclusion–exclusion over divisors ([Möbius](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md)).
- **Truncating infinite state spaces** (CF 908D): once a quantity exceeds a threshold the remaining expectation has a closed form; DP over the bounded part only.
- **Expectations on trees by linearity** (CF 280C, CF 1540B *Tree Array*): probabilities of pairwise orderings computed with a small DP on path lengths.
- **Markov chains and the fundamental matrix** $N = (I - Q)^{-1}$: expected visits to each transient state; absorption probabilities $B = NR$ — Gaussian elimination for $n \le 500$.
- **Probability generating functions** for sums of independent variables: multiply polynomials (FFT) instead of DP when $n$ is large ([FFT](../15-Advanced-Math/03-fft-and-ntt.md)).
- **Stirling numbers for $E[X^k]$** (CF 1278F *Cards*): $X^k = \sum_j S(k,j)\,j!\binom Xj$ turns powers into falling factorials whose expectations are easy ([Stirling numbers](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md)).

---

## 8. Practice ladder

**≤ 1700**
- [ ] [AtCoder DP I · Coins](https://atcoder.jp/contests/dp/tasks/dp_i)
- [ ] [CF 839C · Journey](https://codeforces.com/problemset/problem/839/C) — 1500
- [ ] [CF 1461C · Random Events](https://codeforces.com/problemset/problem/1461/C) — 1500
- [ ] [CF 453A · Little Pony and Expected Maximum](https://codeforces.com/problemset/problem/453/A) — 1600
- [ ] [CF 518D · Ilya and Escalator](https://codeforces.com/problemset/problem/518/D) — 1700

**1700–2100**
- [ ] [CF 148D · Bag of mice](https://codeforces.com/problemset/problem/148/D) — 1800
- [ ] [CF 16E · Fish](https://codeforces.com/problemset/problem/16/E) — 1900
- [ ] [CF 540D · Bad Luck Island](https://codeforces.com/problemset/problem/540/D) — 1900
- [ ] [AtCoder DP J · Sushi](https://atcoder.jp/contests/dp/tasks/dp_j)
- [ ] [CF 1753C · Wish I Knew How to Sort](https://codeforces.com/problemset/problem/1753/C) — 2000
- [ ] [CF 235B · Let's Play Osu!](https://codeforces.com/problemset/problem/235/B) — 2000
- [ ] [CF 1265E · Beautiful Mirrors](https://codeforces.com/problemset/problem/1265/E) — 2100
- [ ] [CF 1778D · Flexible String Revisit](https://codeforces.com/problemset/problem/1778/D) — 2100

**2100–2400**
- [ ] [CF 280C · Game on Tree](https://codeforces.com/problemset/problem/280/C) — 2200
- [ ] [CF 768D · Jon and Orbs](https://codeforces.com/problemset/problem/768/D) — 2200
- [ ] [CF 908D · New Year and Arbitrary Arrangement](https://codeforces.com/problemset/problem/908/D) — 2200
- [ ] [CF 1097D · Makoto and a Blackboard](https://codeforces.com/problemset/problem/1097/D) — 2200
- [ ] [CF 1139D · Steps to One](https://codeforces.com/problemset/problem/1139/D) — 2300
- [ ] [CF 1540B · Tree Array](https://codeforces.com/problemset/problem/1540/B) — 2300
- [ ] [CF 24D · Broken robot](https://codeforces.com/problemset/problem/24/D) — 2400
- [ ] [CF 865C · Gotta Go Fast](https://codeforces.com/problemset/problem/865/C) — 2400

**2500+**
- [ ] [CF 1278F · Cards](https://codeforces.com/problemset/problem/1278/F) — 2600
- [ ] [CF 1523E · Crypto Lights](https://codeforces.com/problemset/problem/1523/E) — 2600

---

## 9. LeetCode / FAANG cross-reference

- [LC 688 · Knight Probability in Chessboard](https://leetcode.com/problems/knight-probability-in-chessboard/) — Medium — forward probability by steps.
- [LC 837 · New 21 Game](https://leetcode.com/problems/new-21-game/) — Medium — probability DP with a sliding-window sum of the last $W$ states.
- [LC 808 · Soup Servings](https://leetcode.com/problems/soup-servings/) — Medium — memoised probability with a cut-off for large $n$ (answer → 1).
- [LC 1227 · Airplane Seat Assignment Probability](https://leetcode.com/problems/airplane-seat-assignment-probability/) — Medium — the DP collapses to $1/2$; prove it by symmetry.
- [LC 1230 · Toss Strange Coins](https://leetcode.com/problems/toss-strange-coins/) — Medium 🔒 — Example 1 with "exactly $k$ heads".
- [LC 576 · Out of Boundary Paths](https://leetcode.com/problems/out-of-boundary-paths/) — Medium — counting version of a bounded random walk.
- [LC 1514 · Path with Maximum Probability](https://leetcode.com/problems/path-with-maximum-probability/) — Medium — Dijkstra in the $(\max, \times)$ semiring.

Interviews rarely go beyond forward probability DPs; the most common follow-up is LC 837's sliding window (a prefix-sum optimisation of a probability DP).

---

## 10. Self-check

1. When do you compute probabilities forward and expectations backward? Give one problem of each kind.
2. Derive the Sushi recurrence including the self-loop.
3. Explain the $E_i = a_i + b_iE_1$ trick and why it is needed in Beautiful Mirrors.
4. Why is it legitimate to compute an expected value modulo $998244353$?
5. Compute the expected number of fair-die rolls until a 6 appears, and the expected number of distinct faces seen in 6 rolls (by linearity).
6. Why does Broken robot need a linear solve per row, and why is it $O(M)$?
7. What goes wrong if you subtract $1 - q$ in doubles with $q = 1 - 10^{-12}$?

<details><summary>Answers</summary>

1. Forward when the base case is the start and you want a distribution or a function of the final state (Coins, Escalator); backward when you want expected remaining cost until absorption and the end states are known (Sushi, Broken robot).
2. $E = 1 + \frac{c_0}{N}E + \sum_k \frac{c_k}{N}E_k$ with $c_0 = N - c_1 - c_2 - c_3$; moving $\frac{c_0}{N}E$ to the left gives $E\cdot\frac{c_1+c_2+c_3}{N} = 1 + \sum_k\frac{c_k}{N}E_k$.
3. Every state can fall back to mirror 1, so $E_1$ appears in every equation and no state is "finished" first. Writing each $E_i$ as an affine function of the unknown $E_1$ lets the backward pass complete, and the last equation is linear in $E_1$.
4. The answer is a rational number obtained from the inputs by $+,-,\times,\div$; the same operations in the field $\mathbb F_p$ give $P\cdot Q^{-1}$ as long as no denominator is divisible by $p$.
5. Geometric with $p = 1/6$: 6 rolls. Distinct faces: $6\cdot\big(1 - (5/6)^6\big) \approx 3.99$.
6. Left/right moves make the values in a row depend on each other (cycles), so a DP order does not exist; but each equation involves only adjacent columns, giving a tridiagonal system solvable by one forward and one backward sweep.
7. $1-q$ is computed with large relative error (only a few correct digits remain), and dividing by it amplifies the error; compute the complementary probability directly as a sum of the other transition probabilities.

</details>
