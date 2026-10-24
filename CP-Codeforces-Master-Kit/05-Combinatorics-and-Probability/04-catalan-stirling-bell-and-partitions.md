# Catalan, Stirling, Bell, Partitions and Fibonacci

> **Band:** 🔵 1500 – 🔴 2600 · **Priority:** 🔥 (Catalan, Fibonacci) · ⚡ (Stirling, partitions) · 🧊 (Narayana, Lah, pentagonal theorem) · **FAANG:** medium (Catalan via LC 96 / 22) · **Prerequisites:** [binomials](01-counting-principles-and-binomials.md), [inclusion–exclusion](03-inclusion-exclusion.md)
> **You can say you know this when:** you can prove the Catalan formula by reflection, count bracket completions from an arbitrary prefix, derive both Stirling recurrences from "where does the last element go", use $x^n = \sum_k S(n,k)\,x^{\underline k}$ to compute moments, and compute $p(n)$ with the pentagonal recurrence.

---

## 1. First principles — why this works

### 1.1 Catalan numbers by the reflection principle

A **Dyck path** of length $2n$ uses steps $+1$ (`(`) and $-1$ (`)`), starts and ends at height $0$, and never goes below $0$ — exactly a balanced bracket sequence. Without the "never below 0" condition there are $\binom{2n}{n}$ paths. Count the **bad** ones (which touch $-1$): take the first time a bad path touches $-1$ and **reflect** the part before it across the line $y = -1$. The reflected path starts at $-2$ and ends at $0$, so it has $n + 1$ up-steps and $n - 1$ down-steps. Conversely, any path from $-2$ to $0$ must cross $-1$; reflecting its part before the first touch gives a bad path. This bijection gives $\binom{2n}{n+1}$ bad paths:

$$C_n = \binom{2n}{n} - \binom{2n}{n+1} = \frac{1}{n+1}\binom{2n}{n}.$$

The same argument handles any start height $h \ge 0$, any length and any end height: paths from $h$ to $0$ in $r$ steps that stay $\ge 0$ number $\binom{r}{d} - \binom{r}{d+1}$ where $d = (r + h)/2$ is the number of down-steps (reflect the start to $-h-2$). This is exactly "complete a bracket prefix" (Example 2).

**Recurrence (first-return decomposition).** A non-empty Dyck path is `(` $A$ `)` $B$ where the `)` is the first return to height $0$; $A$ and $B$ are arbitrary Dyck paths of total length $2n - 2$. So $C_{n+1} = \sum_{i=0}^{n} C_i C_{n-i}$, $C_0 = 1$ — and every structure with the same "root splits into two independent smaller parts" decomposition is counted by Catalan: binary trees with $n$ nodes (root, left subtree, right subtree), BSTs on $n$ keys, triangulations of an $(n+2)$-gon (the triangle on a fixed edge splits the polygon in two), full binary trees with $n + 1$ leaves, non-crossing matchings of $2n$ points, stack-sortable permutations, monotone lattice paths that stay below the diagonal.

### 1.2 Stirling and Bell numbers: "where does the last element go?"

**Stirling numbers of the second kind** $S(n, k)$ count partitions of $\lbrace 1..n\rbrace$ into $k$ non-empty unlabelled blocks. Look at element $n$: either it is alone (the rest form $k - 1$ blocks) or it joins one of the $k$ blocks of a partition of the rest:

$$S(n,k) = S(n-1, k-1) + k\,S(n-1,k), \qquad S(0,0) = 1.$$

Labelling the blocks turns partitions into surjections, so $k!S(n,k) = \operatorname{surj}(n,k) = \sum_j(-1)^j\binom kj(k-j)^n$ ([inclusion–exclusion](03-inclusion-exclusion.md)). Counting all functions $[n] \to [x]$ by the size $k$ of their image gives the identity that makes Stirling numbers a computational tool:

$$x^n = \sum_{k=0}^{n} S(n,k)\,x^{\underline k}, \qquad x^{\underline k} = x(x-1)\cdots(x-k+1).$$

(Choose the image: $\binom xk$ ways; map onto it: $k!S(n,k)$ ways; $\binom xk k! = x^{\underline k}$.) Powers are awkward for expectations and sums, falling factorials are easy: $E[\binom Xk]$ is "the expected number of $k$-subsets of successes" — that is how [CF 1278F · Cards](https://codeforces.com/problemset/problem/1278/F) — 2600 is solved (Example 5).

**Stirling numbers of the first kind** $c(n,k)$ (unsigned) count permutations of $n$ elements with exactly $k$ cycles. Element $n$ either forms its own cycle, or is inserted right after one of the $n - 1$ other elements inside its cycle:

$$c(n,k) = c(n-1,k-1) + (n-1)\,c(n-1,k), \qquad x^{\overline n} = x(x+1)\cdots(x+n-1) = \sum_k c(n,k)\,x^k .$$

**Bell numbers** $B_n = \sum_k S(n,k)$ count all set partitions. Classify by the block containing element $n + 1$: choose which $j$ of the other $n$ elements join it, then partition the remaining $n - j$: $B_{n+1} = \sum_j\binom nj B_{n-j} = \sum_j\binom nj B_j$.

### 1.3 Integer partitions and the pentagonal theorem

$p(n)$ counts ways to write $n$ as an unordered sum of positive integers. Its generating function is $\prod_{i\ge1}\frac{1}{1 - x^i}$ (choose how many parts of each size). The coin-change DP over part sizes computes $p(1..N)$ in $O(N^2)$. Euler's **pentagonal number theorem** says

$$\prod_{i\ge 1}(1 - x^i) = \sum_{k=-\infty}^{\infty}(-1)^k x^{k(3k-1)/2} = 1 - x - x^2 + x^5 + x^7 - x^{12} - x^{15} + \cdots$$

Multiplying by $\sum p(n)x^n$ gives $1$, so comparing coefficients:

$$p(n) = \sum_{k \ge 1}(-1)^{k+1}\Bigl[p\bigl(n - \tfrac{k(3k-1)}{2}\bigr) + p\bigl(n - \tfrac{k(3k+1)}{2}\bigr)\Bigr],$$

with only $O(\sqrt n)$ non-zero terms — $O(N\sqrt N)$ for all $p(n)$, $n \le N$ (🧊 Franklin's involution proves the theorem bijectively). Two more classics: partitions into **distinct** parts equal partitions into **odd** parts ($\prod(1 + x^i) = \prod\frac{1 - x^{2i}}{1 - x^i} = \prod\frac{1}{1 - x^{2i-1}}$), and partitions into at most $k$ parts equal partitions with all parts $\le k$ (transpose the Young diagram).

### 1.4 Fibonacci identities from one matrix

With $Q = \begin{psmallmatrix}1&1\\1&0\end{psmallmatrix}$, $Q^n = \begin{psmallmatrix}F_{n+1}&F_n\\F_n&F_{n-1}\end{psmallmatrix}$. From $Q^{m+n} = Q^mQ^n$: $F_{m+n} = F_mF_{n+1} + F_{m-1}F_n$; with $m = n$ and $m = n+1$ the **fast-doubling** formulas $F_{2n} = F_n(2F_{n+1} - F_n)$, $F_{2n+1} = F_n^2 + F_{n+1}^2$; from $\det Q^n = (-1)^n$ **Cassini** $F_{n-1}F_{n+1} - F_n^2 = (-1)^n$. Combinatorially, $F_{n+1}$ counts tilings of a $1\times n$ strip by $1\times1$ and $1\times2$ tiles (last tile is a square or a domino), which explains $\sum_k\binom{n-k}{k} = F_{n+1}$.

---

## 2. Formulas, definitions and identities

| Formula | Note / proof sketch |
|---|---|
| $C_n = \frac{1}{n+1}\binom{2n}n = \binom{2n}n - \binom{2n}{n+1}$ | reflection (§1.1) |
| $C_{n+1} = \sum_{i=0}^{n}C_iC_{n-i}$; $C_{n+1} = \frac{2(2n+1)}{n+2}C_n$ | first return; ratio of closed forms |
| $1, 1, 2, 5, 14, 42, 132, 429, 1430, 4862, 16796$ | $C_0..C_{10}$ |
| $\sum_n C_n x^n = \frac{1 - \sqrt{1-4x}}{2x}$; $C_n \sim \frac{4^n}{n^{3/2}\sqrt\pi}$ | GF from $C(x) = 1 + xC(x)^2$ |
| sequences of $n$ `(` and $m \le n$ `)` with every prefix balanced | $\binom{n+m}{m} - \binom{n+m}{m-1}$ |
| paths from height $h$ to $0$ in $r$ steps staying $\ge 0$ | $\binom rd - \binom r{d+1}$, $d = \frac{r+h}{2}$ |
| ballot: $a > b$ votes, $A$ strictly ahead throughout | probability $\frac{a-b}{a+b}$, count $\frac{a-b}{a+b}\binom{a+b}{a}$ |
| Fuss–Catalan ($k$-ary trees with $n$ internal nodes) | $\frac{1}{(k-1)n+1}\binom{kn}{n}$ |
| Narayana $N(n,k) = \frac1n\binom nk\binom n{k-1}$ (🧊) | Dyck paths with $k$ peaks; $\sum_k N(n,k) = C_n$ |
| $S(n,k) = S(n-1,k-1) + kS(n-1,k)$ | §1.2 |
| $S(n,k) = \frac1{k!}\sum_{j=0}^{k}(-1)^j\binom kj(k-j)^n$ | surjections / $k!$ |
| $x^n = \sum_k S(n,k)x^{\underline k}$ | count maps $[n]\to[x]$ by image size |
| $S(n,1) = S(n,n) = 1$, $S(n,2) = 2^{n-1} - 1$, $S(n, n-1) = \binom n2$ | small cases |
| $c(n,k) = c(n-1,k-1) + (n-1)c(n-1,k)$; $\sum_k c(n,k) = n!$; $c(n,1) = (n-1)!$ | §1.2 |
| $x^{\overline n} = \sum_k c(n,k)x^k$; $x^{\underline n} = \sum_k (-1)^{n-k}c(n,k)x^k$ | rising/falling factorials |
| $B_{n+1} = \sum_k\binom nkB_k$; $B_n = \sum_k S(n,k)$; $1,1,2,5,15,52,203,877,4140$ | §1.2 |
| Bell triangle: $a_{0,0} = 1$, $a_{i,0} = a_{i-1,i-1}$, $a_{i,j} = a_{i,j-1} + a_{i-1,j-1}$; $B_i = a_{i,0}$ | $O(n^2)$ without binomials |
| Lah $L(n,k) = \binom{n-1}{k-1}\frac{n!}{k!}$ (🧊) | partitions into $k$ ordered lists |
| $p(n)$: $1, 1, 2, 3, 5, 7, 11, 15, 22, 30, 42$; $p(100) = 190\,569\,292$ | |
| $p(n,k) = p(n-1,k-1) + p(n-k,k)$ (exactly $k$ parts) | smallest part is 1, or subtract 1 from every part |
| pentagonal recurrence (§1.3); $p(n) \sim \frac{1}{4n\sqrt3}e^{\pi\sqrt{2n/3}}$ | $O(N\sqrt N)$ table |
| distinct parts = odd parts; $\le k$ parts = parts $\le k$ | GF / conjugation |
| $F_{m+n} = F_mF_{n+1} + F_{m-1}F_n$; $F_{2n} = F_n(2F_{n+1}-F_n)$; $F_{2n+1} = F_n^2+F_{n+1}^2$ | §1.4 |
| $F_{n-1}F_{n+1} - F_n^2 = (-1)^n$; $\sum_{i=1}^{n}F_i = F_{n+2} - 1$; $\sum F_i^2 = F_nF_{n+1}$ | Cassini; telescoping; area of a Fibonacci rectangle |
| $\gcd(F_m,F_n) = F_{\gcd(m,n)}$; $F_n = \frac{\varphi^n - \psi^n}{\sqrt5}$ | [gcd file](../04-Number-Theory/01-divisibility-gcd-and-extended-euclid.md); Binet |
| Zeckendorf: every $n$ is uniquely a sum of non-consecutive Fibonacci numbers | greedy |

---

## 3. Implementation (C++ and Java)

```cpp
// Catalan, Stirling tables (both kinds), Bell triangle, partitions (DP and pentagonal), Fibonacci fast doubling.
const long long MOD = 1'000'000'007LL;
long long power(long long a, long long e) { long long r = 1; a %= MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
vector<long long> catalan(int n) {                    // C_0..C_n via C_{i+1} = C_i * 2(2i+1) / (i+2)
    vector<long long> c(n + 1); c[0] = 1;
    for (int i = 0; i < n; i++) c[i + 1] = c[i] * (2 * (2 * i + 1)) % MOD * power(i + 2, MOD - 2) % MOD;
    return c;
}
vector<vector<long long>> stirling2(int n) {          // S[i][k]
    vector<vector<long long>> S(n + 1, vector<long long>(n + 1, 0)); S[0][0] = 1;
    for (int i = 1; i <= n; i++) for (int k = 1; k <= i; k++) S[i][k] = (S[i - 1][k - 1] + (long long)k * S[i - 1][k]) % MOD;
    return S;
}
vector<vector<long long>> stirling1(int n) {          // unsigned c[i][k]: permutations with k cycles
    vector<vector<long long>> c(n + 1, vector<long long>(n + 1, 0)); c[0][0] = 1;
    for (int i = 1; i <= n; i++) for (int k = 1; k <= i; k++) c[i][k] = (c[i - 1][k - 1] + (long long)(i - 1) * c[i - 1][k]) % MOD;
    return c;
}
vector<long long> bell(int n) {                       // Bell triangle, O(n^2)
    vector<long long> B(n + 1), row = {1}; B[0] = 1;
    for (int i = 1; i <= n; i++) {
        vector<long long> nr(i + 1); nr[0] = row.back();
        for (int j = 1; j <= i; j++) nr[j] = (nr[j - 1] + row[j - 1]) % MOD;
        B[i] = nr[0]; row = nr;
    }
    return B;
}
vector<long long> partitions_pentagonal(int n) {      // p(0..n), O(n sqrt n)
    vector<long long> p(n + 1, 0); p[0] = 1;
    for (int i = 1; i <= n; i++) {
        long long s = 0;
        for (int k = 1;; k++) {
            int g1 = k * (3 * k - 1) / 2, g2 = k * (3 * k + 1) / 2;
            if (g1 > i) break;
            long long t = p[i - g1] + (g2 <= i ? p[i - g2] : 0);
            s = (k & 1) ? (s + t) % MOD : (s - t % MOD + 2 * MOD) % MOD;
        }
        p[i] = s;
    }
    return p;
}
pair<long long, long long> fib_pair(unsigned long long n) {   // (F_n, F_{n+1}) mod MOD
    long long a = 0, b = 1;
    for (int bit = 63; bit >= 0; bit--) {
        long long c = a * ((2 * b - a + MOD) % MOD) % MOD, d = (a * a + b * b) % MOD;
        if (n >> bit & 1) { a = d; b = (c + d) % MOD; } else { a = c; b = d; }
    }
    return {a, b};
}
```

```java
// Catalan, Stirling tables (both kinds), Bell triangle, partitions (DP and pentagonal), Fibonacci fast doubling.
static final long MOD = 1_000_000_007L;
static long power(long a, long e) { long r = 1; a %= MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
static long[] catalan(int n) {
    long[] c = new long[n + 1]; c[0] = 1;
    for (int i = 0; i < n; i++) c[i + 1] = c[i] * (2L * (2 * i + 1)) % MOD * power(i + 2, MOD - 2) % MOD;
    return c;
}
static long[][] stirling2(int n) {
    long[][] S = new long[n + 1][n + 1]; S[0][0] = 1;
    for (int i = 1; i <= n; i++) for (int k = 1; k <= i; k++) S[i][k] = (S[i - 1][k - 1] + (long) k * S[i - 1][k]) % MOD;
    return S;
}
static long[][] stirling1(int n) {
    long[][] c = new long[n + 1][n + 1]; c[0][0] = 1;
    for (int i = 1; i <= n; i++) for (int k = 1; k <= i; k++) c[i][k] = (c[i - 1][k - 1] + (long) (i - 1) * c[i - 1][k]) % MOD;
    return c;
}
static long[] bell(int n) {
    long[] B = new long[n + 1]; long[] row = {1}; B[0] = 1;
    for (int i = 1; i <= n; i++) {
        long[] nr = new long[i + 1]; nr[0] = row[row.length - 1];
        for (int j = 1; j <= i; j++) nr[j] = (nr[j - 1] + row[j - 1]) % MOD;
        B[i] = nr[0]; row = nr;
    }
    return B;
}
static long[] partitionsPentagonal(int n) {
    long[] p = new long[n + 1]; p[0] = 1;
    for (int i = 1; i <= n; i++) {
        long s = 0;
        for (int k = 1;; k++) {
            int g1 = k * (3 * k - 1) / 2, g2 = k * (3 * k + 1) / 2;
            if (g1 > i) break;
            long t = p[i - g1] + (g2 <= i ? p[i - g2] : 0);
            s = (k & 1) == 1 ? (s + t) % MOD : (s - t % MOD + 2 * MOD) % MOD;
        }
        p[i] = s;
    }
    return p;
}
static long[] fibPair(long n) {                         // {F_n, F_{n+1}} mod MOD, n >= 0
    long a = 0, b = 1;
    for (int bit = 62; bit >= 0; bit--) {
        long c = a * ((2 * b - a + MOD) % MOD) % MOD, d = (a * a + b * b) % MOD;
        if ((n >> bit & 1) == 1) { a = d; b = (c + d) % MOD; } else { a = c; b = d; }
    }
    return new long[]{a, b};
}
```

---

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| balanced brackets, "never below zero", stack push/pop orders, mountain profiles | Catalan / reflection |
| binary trees or BSTs with $n$ nodes, triangulations, non-crossing chords | Catalan via first-return decomposition |
| "prefix given, count completions", "start at height $h$" | generalised reflection (Example 2) |
| "split $n$ labelled items into $k$ groups" (groups unlabelled, non-empty) | $S(n,k)$; labelled groups → $k!S(n,k)$ |
| permutations by number of cycles, "records", "visible from the left" | Stirling first kind (left-to-right maxima ↔ cycles by Foata's bijection) |
| all set partitions | Bell |
| $E[X^k]$, $\sum_i i^k\binom ni$, moments of a binomial | $x^k = \sum S(k,j)x^{\underline j}$ (Example 5) |
| write $n$ as an unordered sum | partitions: coin-change DP or pentagonal |
| tilings of a strip, "no two adjacent", $n \le 10^{18}$ | Fibonacci + fast doubling (Example 3) |

Small values to memorise (they identify sequences instantly in brute-force output): Catalan $1,2,5,14,42$; Bell $1,2,5,15,52$; partitions $1,2,3,5,7,11$; derangements $0,1,2,9,44$; Fibonacci $1,1,2,3,5,8$.

---

## 5. Worked examples (graded)

### Example 1 — Bracket Sequences I  ·  ★ ≈1500 (est.)

- **Source:** [CSES 2064 · Bracket Sequences I](https://cses.fi/problemset/task/2064)
- **Difficulty:** ≈1500 (est.)
- **Problem:** Count balanced bracket sequences of length $n \le 10^6$, modulo $10^9+7$.
- **Thinking from first principles:** Odd length: $0$. Otherwise it is the number of Dyck paths with $n/2$ up-steps: $C_{n/2} = \binom{n}{n/2} - \binom{n}{n/2+1}$ (§1.1).

<details><summary>Solution</summary>

Factorials up to $n$. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 1'000'000'007LL;
long long power(long long a, long long e) { long long r = 1; a %= MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
int main() {
    int n; cin >> n;
    if (n % 2) { cout << 0 << '\n'; return 0; }
    vector<long long> f(n + 1), fi(n + 1);
    f[0] = 1;
    for (int i = 1; i <= n; i++) f[i] = f[i - 1] * i % MOD;
    fi[n] = power(f[n], MOD - 2);
    for (int i = n; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
    auto C = [&](int a, int b) -> long long { return (b < 0 || b > a) ? 0 : f[a] * fi[b] % MOD * fi[a - b] % MOD; };
    int h = n / 2;
    cout << (C(n, h) - C(n, h + 1) + MOD) % MOD << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long[] f, fi;
    static long power(long a, long e) { long r = 1; a %= MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
    static long C(int a, int b) { return (b < 0 || b > a) ? 0 : f[a] * fi[b] % MOD * fi[a - b] % MOD; }
    public static void main(String[] args) throws IOException {
        int n = Integer.parseInt(new BufferedReader(new InputStreamReader(System.in)).readLine().trim());
        if (n % 2 == 1) { System.out.println(0); return; }
        f = new long[n + 1]; fi = new long[n + 1]; f[0] = 1;
        for (int i = 1; i <= n; i++) f[i] = f[i - 1] * i % MOD;
        fi[n] = power(f[n], MOD - 2);
        for (int i = n; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
        int h = n / 2;
        System.out.println((C(n, h) - C(n, h + 1) + MOD) % MOD);
    }
}
```

</details>

<!-- test
in:
6
out:
5
-->
<!-- test
in:
1
out:
0
-->
<!-- test
in:
20
out:
16796
-->
<!-- test
in:
1000000
out:
213941567
-->

### Example 2 — Bracket Sequences II (completing a prefix)  ·  ★ ≈1900 (est.)

- **Source:** [CSES 2187 · Bracket Sequences II](https://cses.fi/problemset/task/2187)
- **Difficulty:** ≈1900 (est.)
- **Problem:** Given $n \le 10^6$ and a prefix of length $\le n$, count balanced sequences of length $n$ that start with it, modulo $10^9+7$.
- **Thinking from first principles:** If the prefix ever dips below zero, the answer is $0$. Otherwise it ends at height $h$, and we need paths of $r = n - \lvert\text{prefix}\rvert$ steps from $h$ to $0$ staying $\ge 0$. Such a path has $d = (r + h)/2$ down-steps (parity must match, and $h \le r$), so there are $\binom rd$ paths ignoring the floor. Reflect each bad path (one touching $-1$) before its first touch: it becomes a path from $-h-2$ to $0$, which has $d + 1$ up-steps — $\binom r{d+1}$ of them, and the reflection is a bijection. Answer: $\binom rd - \binom r{d+1}$.

<details><summary>Solution</summary>

Validate the prefix, compute $h$, $r$, check parity, apply the formula. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 1'000'000'007LL;
long long power(long long a, long long e) { long long r = 1; a %= MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
int main() {
    int n; string s; cin >> n >> s;
    long long h = 0;
    for (char c : s) { h += (c == '(') ? 1 : -1; if (h < 0) { cout << 0 << '\n'; return 0; } }
    long long r = n - (long long)s.size();
    if (h > r || (r + h) % 2) { cout << 0 << '\n'; return 0; }
    vector<long long> f(n + 1), fi(n + 1);
    f[0] = 1;
    for (int i = 1; i <= n; i++) f[i] = f[i - 1] * i % MOD;
    fi[n] = power(f[n], MOD - 2);
    for (int i = n; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
    auto C = [&](long long a, long long b) -> long long { return (b < 0 || b > a) ? 0 : f[a] * fi[b] % MOD * fi[a - b] % MOD; };
    long long d = (r + h) / 2;
    cout << (C(r, d) - C(r, d + 1) + MOD) % MOD << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long[] f, fi;
    static long power(long a, long e) { long r = 1; a %= MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
    static long C(long a, long b) { return (b < 0 || b > a) ? 0 : f[(int) a] * fi[(int) b] % MOD * fi[(int) (a - b)] % MOD; }
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int n = Integer.parseInt(br.readLine().trim());
        String s = br.readLine().trim();
        long h = 0;
        for (int i = 0; i < s.length(); i++) { h += s.charAt(i) == '(' ? 1 : -1; if (h < 0) { System.out.println(0); return; } }
        long r = n - s.length();
        if (h > r || (r + h) % 2 != 0) { System.out.println(0); return; }
        f = new long[n + 1]; fi = new long[n + 1]; f[0] = 1;
        for (int i = 1; i <= n; i++) f[i] = f[i - 1] * i % MOD;
        fi[n] = power(f[n], MOD - 2);
        for (int i = n; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
        long d = (r + h) / 2;
        System.out.println((C(r, d) - C(r, d + 1) + MOD) % MOD);
    }
}
```

</details>

<!-- test
in:
6
(()
out:
2
-->
<!-- test
in:
4
())
out:
0
-->
<!-- test
in:
4
(())
out:
1
-->
<!-- test
in:
1000000
((((((((((
out:
336213977
-->

### Example 3 — Fibonacci Numbers (fast doubling)  ·  ★ ≈1500 (est.)

- **Source:** [CSES 1722 · Fibonacci Numbers](https://cses.fi/problemset/task/1722)
- **Difficulty:** ≈1500 (est.)
- **Problem:** Print $F_n \bmod 10^9+7$ for $0 \le n \le 10^{18}$ ($F_0 = 0$, $F_1 = 1$).
- **Thinking from first principles:** Iterating is $10^{18}$ steps. The doubling identities (§1.4) move from $(F_k, F_{k+1})$ to $(F_{2k}, F_{2k+1})$ in $O(1)$; walking the bits of $n$ costs $O(\log n)$ — the same as $2\times2$ matrix power, with fewer multiplications.

<details><summary>Solution</summary>

`fib_pair` from §3.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 1'000'000'007LL;
int main() {
    unsigned long long n; cin >> n;
    long long a = 0, b = 1;
    for (int bit = 63; bit >= 0; bit--) {
        long long c = a * ((2 * b - a + MOD) % MOD) % MOD, d = (a * a + b * b) % MOD;
        if (n >> bit & 1) { a = d; b = (c + d) % MOD; } else { a = c; b = d; }
    }
    cout << a << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        final long MOD = 1_000_000_007L;
        long n = Long.parseLong(new BufferedReader(new InputStreamReader(System.in)).readLine().trim());
        long a = 0, b = 1;
        for (int bit = 62; bit >= 0; bit--) {
            long c = a * ((2 * b - a + MOD) % MOD) % MOD, d = (a * a + b * b) % MOD;
            if ((n >> bit & 1) == 1) { a = d; b = (c + d) % MOD; } else { a = c; b = d; }
        }
        System.out.println(a);
    }
}
```

</details>

<!-- test
in:
10
out:
55
-->
<!-- test
in:
0
out:
0
-->
<!-- test
in:
1000000000000000000
out:
209783453
-->

### Example 4 — Partition numbers via the pentagonal theorem  ·  ★ ≈2100 (est.)

- **Source:** Original problem
- **Difficulty:** ≈2100 (est.)
- **Problem:** $T \le 10^5$ queries $n \le 10^5$: print $p(n) \bmod 10^9+7$.
- **Thinking from first principles:** The coin-change DP over part sizes is $O(N^2) = 10^{10}$. The generating function $\prod(1-x^i)^{-1}$ has an inverse with only $O(\sqrt N)$ non-zero coefficients up to $x^N$ (pentagonal numbers), so $p(n)$ is a signed sum of $O(\sqrt n)$ earlier values: $O(N\sqrt N) \approx 5\cdot10^7$.

<details><summary>Solution</summary>

Precompute $p(0..10^5)$ once with the recurrence, answer queries by lookup.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 1'000'000'007LL;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    const int N = 100000;
    vector<long long> p(N + 1, 0); p[0] = 1;
    for (int i = 1; i <= N; i++) {
        long long s = 0;
        for (int k = 1;; k++) {
            int g1 = k * (3 * k - 1) / 2, g2 = k * (3 * k + 1) / 2;
            if (g1 > i) break;
            long long t = p[i - g1] + (g2 <= i ? p[i - g2] : 0);
            s = (k & 1) ? (s + t) % MOD : (s - t % MOD + 2 * MOD) % MOD;
        }
        p[i] = s;
    }
    int T; cin >> T;
    while (T--) { int n; cin >> n; cout << p[n] << '\n'; }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        final long MOD = 1_000_000_007L;
        final int N = 100000;
        long[] p = new long[N + 1]; p[0] = 1;
        for (int i = 1; i <= N; i++) {
            long s = 0;
            for (int k = 1;; k++) {
                int g1 = k * (3 * k - 1) / 2, g2 = k * (3 * k + 1) / 2;
                if (g1 > i) break;
                long t = p[i - g1] + (g2 <= i ? p[i - g2] : 0);
                s = (k & 1) == 1 ? (s + t) % MOD : (s - t % MOD + 2 * MOD) % MOD;
            }
            p[i] = s;
        }
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int T = Integer.parseInt(br.readLine().trim());
        StringBuilder sb = new StringBuilder();
        StringTokenizer st = new StringTokenizer("");
        while (T-- > 0) {
            while (!st.hasMoreTokens()) st = new StringTokenizer(br.readLine());
            sb.append(p[Integer.parseInt(st.nextToken())]).append('\n');
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
5
0
1
5
10
100
out:
1
1
7
42
190569292
-->
<!-- test
in:
2
1000
100000
out:
709496666
49037875
-->

### Example 5 — Cards (moments via Stirling numbers)  ·  ★ 2600

- **Source:** [CF 1278F · Cards](https://codeforces.com/problemset/problem/1278/F) — 2600
- **Difficulty:** 2600
- **Problem:** A deck of $m$ cards has one joker. $n$ times, shuffle uniformly and look at the top card. Let $x$ be the number of times the joker was on top. Print $E[x^k] \bmod 998244353$ for $n, m < 998244353$, $k \le 5000$.
- **Thinking from first principles:** $x \sim \operatorname{Bin}(n, p)$ with $p = 1/m$. Expanding $E[x^k] = \sum_i\binom ni p^i(1-p)^{n-i}i^k$ is $O(n)$ terms — too many. Change basis: $x^k = \sum_j S(k,j)\,x^{\underline j}$ (§1.2), and $x^{\underline j} = j!\binom xj$, where $\binom xj$ counts $j$-subsets of the $x$ successful rounds. By linearity, $E[\binom xj] = \sum_{\lvert J\rvert = j}P(\text{all rounds in } J \text{ succeed}) = \binom nj p^j$. Hence

$$E[x^k] = \sum_{j=0}^{\min(k, n)} S(k, j)\; n^{\underline j}\; m^{-j}.$$

<details><summary>Solution</summary>

$S(k, j)$ by the $O(k^2)$ recurrence ($2.5\cdot10^7$ operations), falling factorials and powers of $m^{-1}$ incrementally. $O(k^2)$ time; keep one row of $S$ in memory.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 998244353LL;
ll power(ll a, ll e) { ll r = 1; a %= MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
int main() {
    ll n, m; int k; cin >> n >> m >> k;
    vector<ll> S(k + 1, 0); S[0] = 1;                      // row i of Stirling-2, updated in place
    for (int i = 1; i <= k; i++) {
        for (int j = i; j >= 1; j--) S[j] = (S[j - 1] + (ll)j * S[j]) % MOD;
        S[0] = 0;
    }
    ll invm = power(m, MOD - 2), ff = 1, pw = 1, ans = 0;     // ff = n^{falling j}, pw = m^{-j}
    for (int j = 0; j <= k && j <= n; j++) {
        ans = (ans + S[j] * ff % MOD * pw) % MOD;
        ff = ff * ((n - j) % MOD) % MOD;
        pw = pw * invm % MOD;
    }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 998244353L;
    static long power(long a, long e) { long r = 1; a %= MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        long n = Long.parseLong(st.nextToken()), m = Long.parseLong(st.nextToken());
        int k = Integer.parseInt(st.nextToken());
        long[] S = new long[k + 1]; S[0] = 1;
        for (int i = 1; i <= k; i++) {
            for (int j = i; j >= 1; j--) S[j] = (S[j - 1] + (long) j * S[j]) % MOD;
            S[0] = 0;
        }
        long invm = power(m, MOD - 2), ff = 1, pw = 1, ans = 0;
        for (int j = 0; j <= k && j <= n; j++) {
            ans = (ans + S[j] * ff % MOD * pw) % MOD;
            ff = ff * ((n - j) % MOD) % MOD;
            pw = pw * invm % MOD;
        }
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
1 1 1
out:
1
-->
<!-- test
in:
1 1 5000
out:
1
-->
<!-- test
in:
2 2 2
out:
499122178
-->
<!-- test
in:
998244352 1337 5000
out:
326459680
-->
<!-- test
in:
5 3 4
out:
480636202
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Odd length / wrong parity** gives $0$ bracket sequences — check before indexing factorials with half-integers (Example 2: $(r + h)$ must be even).
2. **Catalan via $\binom{2n}{n}/(n+1)$ modulo $p$** needs the inverse of $n + 1$; the difference form $\binom{2n}{n} - \binom{2n}{n+1}$ avoids it.
3. **$S(n, k)$ tables are $O(nk)$ memory** — for $k = 5000$ keep a single row updated right to left (Example 5).
4. **Stirling first vs second kind**: cycles (permutations) vs blocks (set partitions). The recurrence multiplier is $n - 1$ for cycles, $k$ for blocks.
5. **Pentagonal signs** go $+, +, -, -, +, +, \dots$ in pairs: the $k$-th pair has sign $(-1)^{k+1}$.
6. **$p(n)$ grows like $e^{\pi\sqrt{2n/3}}$** — exact values overflow 64-bit near $n = 416$; use a modulus or big integers.
7. **Fibonacci index conventions** ($F_0 = 0$ or $F_1 = F_2 = 1$) shift answers by one — read the statement.
8. **Expected values with falling factorials**: $E[x^{\underline j}] = n^{\underline j}p^j$ only for the binomial distribution; for other distributions compute $E[\binom xj]$ from the problem's structure.

---

## 7. Going further (toward 2400–2600+)

- **Stirling rows/columns in $O(n\log n)$** with NTT (rising factorial by divide and conquer; $S(n, \cdot)$ by convolving $\frac{(-1)^j}{j!}$ with $\frac{i^n}{i!}$) — [FFT/NTT](../15-Advanced-Math/03-fft-and-ntt.md).
- **Exponential generating functions**: $\sum_n B_n\frac{x^n}{n!} = e^{e^x - 1}$, $\sum_n S(n,k)\frac{x^n}{n!} = \frac{(e^x-1)^k}{k!}$ — set partitions are "exp" of non-empty sets ([GFs](../15-Advanced-Math/04-polynomials-and-generating-functions.md)).
- **Catalan-like decompositions** in tree DP and interval DP: "the root/first-return splits the structure" is the same idea as [interval DP](../06-Dynamic-Programming/05-interval-dp.md).
- **Partitions with restrictions** (distinct parts, bounded parts, at most $k$ parts) via $\sqrt n$ decomposition: parts $< \sqrt n$ by knapsack, parts $\ge\sqrt n$ by the "number of large parts" DP (🧊).
- **Lindström–Gessel–Viennot** counts non-intersecting lattice paths as a determinant of binomials — [LGV](../15-Advanced-Math/06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md).

---

## 8. Practice ladder

**≤ 1900**
- [ ] [CSES 2064 · Bracket Sequences I](https://cses.fi/problemset/task/2064)
- [ ] [CSES 2187 · Bracket Sequences II](https://cses.fi/problemset/task/2187)
- [ ] [CSES 1722 · Fibonacci Numbers](https://cses.fi/problemset/task/1722)
- [ ] [CF 1391C · Cyclic Permutations ](https://codeforces.com/problemset/problem/1391/C) — 1500
- [ ] [CF 1433E · Two Round Dances](https://codeforces.com/problemset/problem/1433/E) — 1300
- [ ] [CF 1081C · Colorful Bricks](https://codeforces.com/problemset/problem/1081/C) — 1500

**1900–2400**
- [ ] [CF 9D · How many trees?](https://codeforces.com/problemset/problem/9/D) — 1900
- [ ] [CF 1976D · Invertible Bracket Sequences](https://codeforces.com/problemset/problem/1976/D) — 2000
- [ ] [CF 1342E · Placing Rooks](https://codeforces.com/problemset/problem/1342/E) — 2300
- [ ] [CF 1716F · Bags with Balls](https://codeforces.com/problemset/problem/1716/F) — 2500

**2400+**
- [ ] [CF 932E · Team Work](https://codeforces.com/problemset/problem/932/E) — 2400
- [ ] [CF 1830C · Hyperregular Bracket Strings](https://codeforces.com/problemset/problem/1830/C) — 2400
- [ ] [CF 1278F · Cards](https://codeforces.com/problemset/problem/1278/F) — 2600
- [ ] [CF 1264D1 · Beautiful Bracket Sequence (easy version)](https://codeforces.com/problemset/problem/1264/D1) — 2600

---

## 9. LeetCode / FAANG cross-reference

- [LC 96 · Unique Binary Search Trees](https://leetcode.com/problems/unique-binary-search-trees/) — Medium — Catalan by the root-split recurrence.
- [LC 95 · Unique Binary Search Trees II](https://leetcode.com/problems/unique-binary-search-trees-ii/) — Medium — enumerate the same decomposition.
- [LC 22 · Generate Parentheses](https://leetcode.com/problems/generate-parentheses/) — Medium — backtracking over Dyck paths; the output size is $C_n$.
- [LC 1866 · Number of Ways to Rearrange Sticks With K Sticks Visible](https://leetcode.com/problems/number-of-ways-to-rearrange-sticks-with-k-sticks-visible/) — Hard — exactly $c(n, k)$ (Stirling first kind): left-to-right maxima ↔ cycles.
- [LC 279 · Perfect Squares](https://leetcode.com/problems/perfect-squares/) — Medium — a partition-style DP (min instead of count).
- [LC 935 · Knight Dialer](https://leetcode.com/problems/knight-dialer/) — Medium — linear recurrence, like Fibonacci (matrix power for huge $n$).

---

## 10. Self-check

1. Prove $C_n = \binom{2n}{n} - \binom{2n}{n+1}$ by reflection.
2. Why do BSTs on $n$ keys satisfy the Catalan recurrence?
3. How many balanced completions of length 8 does the prefix `((` have?
4. Derive $S(n,k) = S(n-1,k-1) + kS(n-1,k)$ and $c(n,k) = c(n-1,k-1) + (n-1)c(n-1,k)$.
5. Prove $x^n = \sum_k S(n,k)x^{\underline k}$.
6. State the pentagonal recurrence and compute $p(7)$ from $p(0..6) = 1,1,2,3,5,7,11$.
7. Why are partitions into distinct parts equinumerous with partitions into odd parts?
8. Compute $E[X^2]$ for $X \sim \operatorname{Bin}(n, p)$ using Stirling numbers.

<details><summary>Answers</summary>

1. Bad paths (touching $-1$) ↔ paths from $-2$ to $0$ by reflecting before the first touch; the latter have $n+1$ ups: $\binom{2n}{n+1}$.
2. The root key $i$ splits the keys into $i - 1$ smaller (left subtree) and $n - i$ larger (right subtree), independently.
3. $h = 2$, $r = 6$, $d = 4$: $\binom64 - \binom65 = 15 - 6 = 9$.
4. Element $n$ alone or joining one of $k$ blocks; element $n$ a fixed point or inserted after one of $n - 1$ elements in a cycle.
5. Count maps $[n] \to [x]$ by image size $k$: choose image $\binom xk$, surject onto it $k!S(n,k)$.
6. $p(7) = p(6) + p(5) - p(2) - p(0) = 11 + 7 - 2 - 1 = 15$.
7. $\prod(1 + x^i) = \prod\frac{1-x^{2i}}{1-x^i}$; cancelling even factors leaves $\prod_{i \text{ odd}}\frac{1}{1 - x^i}$.
8. $x^2 = x^{\underline2} + x^{\underline1}$: $E = n(n-1)p^2 + np$.

</details>
