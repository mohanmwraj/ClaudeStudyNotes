# Euler's Totient, Fermat, Euler and Wilson

> **Band:** 🔵 1500 – 🔴 2700 · **Priority:** 🔥 (φ, Fermat) · ⚡ (generalised Euler, power towers) · **FAANG:** low · **Prerequisites:** [modular arithmetic](02-modular-arithmetic-and-inverses.md), [sieves](03-sieves-and-factorization.md)
> **You can say you know this when:** you can prove $\sum_{d\mid n}\varphi(d) = n$ and Euler's theorem from scratch, compute $\varphi$ for one number and for all numbers up to $10^7$, and evaluate a power tower $a_1^{a_2^{\cdot^{\cdot^{a_k}}}} \bmod m$ for arbitrary $m$.

---

## 1. First principles — why this works

### 1.1 What $\varphi$ counts and why it matters

$\varphi(n) = \#\lbrace 1 \le k \le n : \gcd(k, n) = 1\rbrace$ — the number of residues mod $n$ that have an inverse ([§1.2 of modular arithmetic](02-modular-arithmetic-and-inverses.md)). These **units** form a group $U_n$ under multiplication: the product of two units is a unit and each has an inverse. So $\varphi(n) = \lvert U_n\rvert$, and everything about exponents mod $n$ is really about this group.

**Computing it from first principles.** For a prime power $p^k$, the non-units in $1..p^k$ are the multiples of $p$, and there are $p^{k-1}$ of them: $\varphi(p^k) = p^k - p^{k-1} = p^{k-1}(p-1)$.
For coprime $m, n$, the Chinese Remainder Theorem says $x \bmod mn \leftrightarrow (x \bmod m, x \bmod n)$ is a bijection ([CRT](05-crt-and-linear-congruences.md)), and $x$ is coprime to $mn$ iff it is coprime to both $m$ and $n$. So units of $mn$ correspond to pairs of units: $\varphi(mn) = \varphi(m)\varphi(n)$ — **multiplicative**. Together:

$$\varphi(n) = \prod_{p^k \parallel n} p^{k-1}(p-1) = n\prod_{p \mid n}\Bigl(1 - \frac1p\Bigr).$$

The second form is also inclusion–exclusion over the prime divisors: remove multiples of each $p$, add back multiples of each $pq$, … ([inclusion–exclusion](../05-Combinatorics-and-Probability/03-inclusion-exclusion.md)); the alternating sum factors into the product.

### 1.2 Euler's theorem by the "permutation" argument

Let $r_1, \dots, r_{\varphi(n)}$ be the units mod $n$ and $a$ a unit. Multiplication by $a$ is injective ($ar_i \equiv ar_j \Rightarrow r_i \equiv r_j$, multiply by $a^{-1}$) and maps units to units, so $ar_1, \dots, ar_{\varphi(n)}$ is the same list in a different order. Multiply everything:

$$\prod_i (a r_i) \equiv \prod_i r_i \;\Rightarrow\; a^{\varphi(n)} \prod r_i \equiv \prod r_i \;\Rightarrow\; a^{\varphi(n)} \equiv 1 \pmod n,$$

cancelling the unit $\prod r_i$. For prime $n = p$ this is **Fermat's little theorem**: $a^{p-1} \equiv 1$ for $p \nmid a$, equivalently $a^p \equiv a$ for all $a$.

(A second proof of Fermat: $(a+1)^p = \sum \binom{p}{k}a^k \equiv a^p + 1 \pmod p$ because $p \mid \binom pk$ for $0<k<p$; induct on $a$.)

Consequence: **exponents of a unit can be reduced modulo $\varphi(n)$** — $a^{e} \equiv a^{e \bmod \varphi(n)}$. Group theory sharpens it: the exponents repeat with period $\operatorname{ord}_n(a)$, which divides $\varphi(n)$ ([orders and primitive roots](06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md)).

### 1.3 What if $a$ is not a unit? The generalised Euler theorem

For $\gcd(a, m) > 1$, $a^e \bmod m$ is not periodic from $e = 0$, but it becomes periodic *eventually*. Claim: for $e \ge \log_2 m$,

$$a^{e} \equiv a^{(e \bmod \varphi(m)) + \varphi(m)} \pmod m .$$

*Proof sketch.* It suffices to check modulo each prime power $p^k \parallel m$ (CRT). If $p \nmid a$: $\varphi(p^k) \mid \varphi(m)$, so both exponents agree modulo $\varphi(p^k)$ and Euler applies. If $p \mid a$: $a^{t} \equiv 0 \pmod{p^k}$ as soon as $t \ge k$; both exponents are $\ge k$ because $e \ge \log_2 m \ge k$ and $(e \bmod \varphi) + \varphi \ge \varphi(m) \ge \varphi(p^k) = p^{k-1}(p - 1) \ge k$. ∎
So the rule is: **if the true exponent is large, replace it by its residue mod $\varphi(m)$ plus $\varphi(m)$; if it is small, use it exactly.** Power towers need to know "is the exponent $\ge \varphi(m)$?" without computing it — Example 4 carries that one bit along.

### 1.4 Why $\varphi$ shows up in counting

Partition $1..n$ by the value $d = \gcd(k, n)$. Writing $k = d k'$, the condition $\gcd(k, n) = d$ is $\gcd(k', n/d) = 1$ with $1 \le k' \le n/d$: there are $\varphi(n/d)$ such $k$. Since every $k$ has exactly one gcd,

$$\sum_{d \mid n} \varphi(n/d) = \sum_{d\mid n}\varphi(d) = n.$$

The same partition gives **gcd sums**: $\sum_{k=1}^{n} \gcd(k, n) = \sum_{d \mid n} d\,\varphi(n/d)$, and "how many $x$ with $\gcd(x, m) = g$" questions are always $\varphi$ of a quotient (Example 1).

---

## 2. Formulas, definitions and identities

| Identity | Meaning / proof sketch |
|---|---|
| $\varphi(1) = 1$, $\varphi(p) = p - 1$, $\varphi(p^k) = p^{k-1}(p-1)$ | §1.1. |
| $\varphi(mn) = \varphi(m)\varphi(n)$ for $\gcd(m,n)=1$ | CRT bijection on units. |
| $\varphi(n) = n\prod_{p\mid n}(1 - 1/p)$ | Product of prime-power values, or inclusion–exclusion. |
| $\varphi(mn) = \varphi(m)\varphi(n)\dfrac{g}{\varphi(g)}$, $g = \gcd(m,n)$ | Apply the product formula: primes of $g$ are counted twice in $\varphi(m)\varphi(n)/(mn)$. |
| $\varphi(n)$ is even for $n \ge 3$ | $k \leftrightarrow n - k$ pairs units, and $k = n - k$ would need $\gcd(n/2, n) = n/2 = 1$. |
| $\varphi(n) \le n/2$ for even $n$ | Half of $1..n$ is even. Hence the chain $n, \varphi(n), \varphi(\varphi(n)), \dots$ reaches 1 in $\le 2\log_2 n + O(1)$ steps. |
| $\sum_{d\mid n}\varphi(d) = n$ | §1.4. In Dirichlet language $\varphi * 1 = \mathrm{id}$ ([Möbius](07-mobius-dirichlet-and-floor-sums.md)). |
| $\sum_{\substack{1\le k\le n\\ \gcd(k,n)=1}} k = \dfrac{n\,\varphi(n)}{2}$ ($n \ge 2$) | Pair $k$ with $n - k$; each pair sums to $n$. |
| $\sum_{k=1}^{n}\gcd(k, n) = \sum_{d \mid n} d\,\varphi(n/d)$ | Group $k$ by $\gcd(k,n) = d$ (§1.4). Multiplicative in $n$. |
| $\#\lbrace (x, y) \in [1,n]^2 : \gcd(x,y) = 1\rbrace = 2\sum_{k=1}^n\varphi(k) - 1$ | For $x < y$ count $\varphi(y)$; symmetric; $(1,1)$ once. |
| Farey sequence length $\lvert F_n\rvert = 1 + \sum_{k=1}^{n}\varphi(k)$ | Reduced fractions in $[0, 1]$ with denominator $\le n$. |
| $\sum_{k \le n} \varphi(k) \approx \frac{3}{\pi^2}n^2$ | Probability two random integers are coprime is $6/\pi^2$. |
| **Fermat:** $a^{p-1} \equiv 1 \pmod p$ for $p \nmid a$; $a^p \equiv a$ always | §1.2. |
| **Euler:** $a^{\varphi(n)} \equiv 1 \pmod n$ for $\gcd(a,n) = 1$ | §1.2. |
| **Generalised Euler:** $a^{e} \equiv a^{(e \bmod \varphi(m)) + \varphi(m)} \pmod m$ for $e \ge \log_2 m$ | §1.3. Holds for every $a$. |
| **Wilson:** $(p-1)! \equiv -1 \pmod p$ for prime $p$; and $(n-1)! \equiv 0 \pmod n$ for composite $n > 4$ | Below. |
| $\operatorname{ord}_n(a) \mid \varphi(n)$ | Divide $\varphi(n)$ by the order; the remainder exponent would be a smaller one. |
| Carmichael $\lambda(n)$ (🧊) | Smallest $e$ with $a^{e} \equiv 1$ for all units; $\lambda(n) \mid \varphi(n)$, e.g. $\lambda(8) = 2$ while $\varphi(8) = 4$. |

**Proof of Wilson.** In the field $\mathbb{Z}/p$, the product $1\cdot 2\cdots (p-1)$ pairs each element with its inverse. The self-inverse elements solve $x^2 \equiv 1 \iff p \mid (x-1)(x+1) \iff x \equiv \pm 1$. All other factors cancel in pairs, leaving $1\cdot(p-1) \equiv -1$. ∎ For composite $n = ab$ with $1 < a < b < n$, both factors appear in $(n-1)!$; for $n = q^2$ with $q > 2$, both $q$ and $2q$ appear; only $n = 4$ escapes ($3! = 6 \equiv 2$).

**Useful corollary (factorials near $p$).** $n! \equiv -\bigl((n+1)(n+2)\cdots(p-1)\bigr)^{-1} \pmod p$ — compute $n!$ in $O(p - n)$ when $n$ is close to $p$ (Example 3).

**Complexities.** $\varphi(n)$ for one $n$: $O(\sqrt n)$ by trial division. All $\varphi(1..N)$: $O(N\log\log N)$ with the Eratosthenes-style update, or $O(N)$ in the [linear sieve](03-sieves-and-factorization.md). Prefix sums of $\varphi$ up to $10^{10}$: Du's sieve, $O(N^{2/3})$ ([file 07](07-mobius-dirichlet-and-floor-sums.md)).

---

## 3. Implementation (C++ and Java)

```cpp
// phi of one number, phi table by sieve, gcd-sum, generalised-Euler power with the ">= m" flag.
long long phi_single(long long n) {             // O(sqrt n)
    long long r = n;
    for (long long p = 2; p * p <= n; p++) {
        if (n % p) continue;
        while (n % p == 0) n /= p;
        r -= r / p;                              // r *= (1 - 1/p), exact
    }
    if (n > 1) r -= r / n;
    return r;
}
vector<int> phi_table(int N) {                   // O(N log log N)
    vector<int> phi(N + 1);
    iota(phi.begin(), phi.end(), 0);
    for (int p = 2; p <= N; p++)
        if (phi[p] == p)                         // untouched => prime
            for (int j = p; j <= N; j += p) phi[j] -= phi[j] / p;
    return phi;
}
long long gcd_sum(long long n) {                 // sum_{k=1..n} gcd(k, n) = sum_{d|n} d * phi(n/d)
    long long s = 0;
    for (long long d = 1; d * d <= n; d++) {
        if (n % d) continue;
        s += d * phi_single(n / d);
        if (d != n / d) s += (n / d) * phi_single(d);
    }
    return s;
}
// "x mod' m": keeps x if x < m, else maps into [m, 2m). Products of such values stay correct
// for deciding whether the true value is >= m (valid for positive integers).
long long modp(long long x, long long m) { return x < m ? x : x % m + m; }
long long pow_flag(long long a, long long e, long long m) {   // returns a^e mod' m, a >= 1
    long long r = 1; a = modp(a, m);
    for (; e; e >>= 1) {
        if (e & 1) r = modp(r * a, m);           // r, a < 2m <= 2e9: product < 4e18
        a = modp(a * a, m);
    }
    return modp(r, m);
}
```

```java
// phi of one number, phi table by sieve, gcd-sum, generalised-Euler power with the ">= m" flag.
static long phiSingle(long n) {
    long r = n;
    for (long p = 2; p * p <= n; p++) {
        if (n % p != 0) continue;
        while (n % p == 0) n /= p;
        r -= r / p;
    }
    if (n > 1) r -= r / n;
    return r;
}
static int[] phiTable(int N) {
    int[] phi = new int[N + 1];
    for (int i = 0; i <= N; i++) phi[i] = i;
    for (int p = 2; p <= N; p++)
        if (phi[p] == p)
            for (int j = p; j <= N; j += p) phi[j] -= phi[j] / p;
    return phi;
}
static long gcdSum(long n) {
    long s = 0;
    for (long d = 1; d * d <= n; d++) {
        if (n % d != 0) continue;
        s += d * phiSingle(n / d);
        if (d != n / d) s += (n / d) * phiSingle(d);
    }
    return s;
}
static long modp(long x, long m) { return x < m ? x : x % m + m; }
static long powFlag(long a, long e, long m) {    // a >= 1, m <= 1e9
    long r = 1; a = modp(a, m);
    for (; e > 0; e >>= 1) {
        if ((e & 1) == 1) r = modp(r * a, m);
        a = modp(a * a, m);
    }
    return modp(r, m);
}
```

Why `modp` works: if $x, y \ge 1$ are true values and $\bar x, \bar y$ their `modp` images, then $\bar x \equiv x$, and $\bar x \ge m \iff x \ge m$. For the product, $xy \ge m$ iff $\bar x\bar y \ge m$: if both are small the images are exact; if one is $\ge m$ its image is $\ge m$ and the other is $\ge 1$. So `modp(x̄ȳ, m)` is the image of $xy$.

---

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "count $x \le m$ with $\gcd(x, m) = g$" or "$\gcd$ unchanged after a shift" | $\varphi(m/g)$ (Example 1). |
| sum of gcds / lcms over a range, pairs with fixed gcd | group by the gcd value $d$; $\varphi$ of the quotient. |
| reduced fractions, visible lattice points, coprime pairs up to $n$ | prefix sums of $\varphi$ (Example 2). |
| exponent is astronomically large | Fermat/Euler: exponent mod $p-1$ or $\varphi(m)$; if $\gcd(a, m) > 1$, generalised Euler with the $\ge$ flag (Example 4). |
| factorial of a number close to a prime | Wilson (Example 3). |
| "order", "period of $a^k$", "cycle length of $x \mapsto ax$" | divisors of $\varphi(n)$ — [primitive roots](06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md). |
| sum over $a+b+c = n$ involving $\gcd(a, b)$ | fix the gcd $d$, the pairs with $a + b = s$, $\gcd = d$ number $\varphi(s/d)$ (Example 5). |

Confusion to avoid: $\varphi$ counts units *up to $n$*, not up to an arbitrary bound $N$. Coprime counts in $[1, N]$ for $N \ne n$ need inclusion–exclusion over the primes of $n$.

---

## 5. Worked examples (graded)

### Example 1 — Same GCDs  ·  ★ 1800

- **Source:** [CF 1295D · Same GCDs](https://codeforces.com/problemset/problem/1295/D) — 1800
- **Difficulty:** 1800
- **Problem:** $T \le 50$ queries $1 \le a < m \le 10^{10}$. Count $x \in [0, m)$ with $\gcd(a, m) = \gcd(a + x, m)$.
- **Thinking from first principles:** Let $g = \gcd(a, m)$ and $y = a + x$, which runs over $m$ consecutive integers — a complete residue system mod $m$, and $\gcd(y, m)$ depends only on $y \bmod m$. So we are counting $y \in [1, m]$ with $\gcd(y, m) = g$, which is $\varphi(m/g)$ by the partition in §1.4.

<details><summary>Solution</summary>

Answer $\varphi(m/g)$, computed by trial division in $O(\sqrt{m})$ per query ($10^5$ steps).

```cpp
#include <bits/stdc++.h>
using namespace std;
long long phi_single(long long n) {
    long long r = n;
    for (long long p = 2; p * p <= n; p++) {
        if (n % p) continue;
        while (n % p == 0) n /= p;
        r -= r / p;
    }
    if (n > 1) r -= r / n;
    return r;
}
int main() {
    int T; cin >> T;
    while (T--) {
        long long a, m; cin >> a >> m;
        cout << phi_single(m / gcd(a, m)) << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long phiSingle(long n) {
        long r = n;
        for (long p = 2; p * p <= n; p++) {
            if (n % p != 0) continue;
            while (n % p == 0) n /= p;
            r -= r / p;
        }
        if (n > 1) r -= r / n;
        return r;
    }
    static long gcd(long a, long b) { while (b != 0) { long t = a % b; a = b; b = t; } return a; }
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StreamTokenizer st = new StreamTokenizer(br);
        st.resetSyntax(); st.wordChars('0', '9'); st.whitespaceChars(0, ' ');
        st.nextToken(); int T = Integer.parseInt(st.sval);
        StringBuilder sb = new StringBuilder();
        while (T-- > 0) {
            st.nextToken(); long a = Long.parseLong(st.sval);
            st.nextToken(); long m = Long.parseLong(st.sval);
            sb.append(phiSingle(m / gcd(a, m))).append('\n');
        }
        System.out.print(sb);
    }
}
```

(`StreamTokenizer` parses numbers as `double` by default, which loses precision above $2^{53}$; resetting the syntax to read words and parsing with `Long.parseLong` avoids that.)

</details>

<!-- test
in:
3
4 9
5 10
42 9999999967
out:
6
1
9999999966
-->
<!-- test
in:
2
1 2
6 10000000000
out:
1
2000000000
-->

### Example 2 — Counting reduced fractions  ·  ★ ≈1500 (est.)

- **Source:** Original problem (the counting part of [LC 1447 · Simplified Fractions](https://leetcode.com/problems/simplified-fractions/) — Medium)
- **Difficulty:** ≈1500 (est.)
- **Problem:** $Q \le 10^5$ queries $n \le 10^6$. Print the number of fractions $p/q$ with $1 \le p < q \le n$ and $\gcd(p, q) = 1$.
- **Thinking from first principles:** For a fixed denominator $q$ the valid numerators are exactly the units below $q$: $\varphi(q)$ of them ($q \ge 2$). Sum over $q$; precompute prefix sums once. The answer reaches $\approx 3\cdot10^{11}$ — 64-bit.

<details><summary>Solution</summary>

$\varphi$-table by sieve, prefix sums, answer $\sum_{q=2}^{n}\varphi(q)$. $O(N\log\log N + Q)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    const int N = 1'000'000;
    vector<int> phi(N + 1);
    iota(phi.begin(), phi.end(), 0);
    for (int p = 2; p <= N; p++)
        if (phi[p] == p)
            for (int j = p; j <= N; j += p) phi[j] -= phi[j] / p;
    vector<long long> pre(N + 1, 0);
    for (int q = 2; q <= N; q++) pre[q] = pre[q - 1] + phi[q];
    int Q; cin >> Q;
    while (Q--) { int n; cin >> n; cout << pre[n] << '\n'; }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        final int N = 1_000_000;
        int[] phi = new int[N + 1];
        for (int i = 0; i <= N; i++) phi[i] = i;
        for (int p = 2; p <= N; p++)
            if (phi[p] == p)
                for (int j = p; j <= N; j += p) phi[j] -= phi[j] / p;
        long[] pre = new long[N + 1];
        for (int q = 2; q <= N; q++) pre[q] = pre[q - 1] + phi[q];
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int Q = in.nextInt();
        while (Q-- > 0) out.println(pre[in.nextInt()]);
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
5
1
2
3
4
10
out:
0
1
3
5
31
-->
<!-- test
in:
1
1000000
out:
303963552391
-->

### Example 3 — Factorial just below a prime (Wilson)  ·  ★ ≈1900 (est.)

- **Source:** Original problem
- **Difficulty:** ≈1900 (est.)
- **Problem:** $T \le 100$ queries: a prime $p \le 2\cdot10^9$ and $n \le 2\cdot10^9$ with $p - n \le 10^6$ when $n < p$. Print $n! \bmod p$.
- **Thinking from first principles:** Multiplying $1\cdots n$ is $2\cdot10^9$ steps. If $n \ge p$ the product contains $p$: answer $0$. Otherwise Wilson gives the *full* product $(p-1)! \equiv -1$; divide out the short tail: $n! = (p-1)!/\bigl((n+1)\cdots(p-1)\bigr)$. The tail has $p - 1 - n \le 10^6$ factors.

<details><summary>Solution</summary>

$t = \prod_{k=n+1}^{p-1} k \bmod p$; answer $-t^{-1} \bmod p = p - t^{p-2} \bmod p$. Products of residues below $2\cdot10^9$ need up to $4\cdot10^{18}$ — still below $2^{63}$. $O(p - n + \log p)$ per query.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
ll power(ll a, ll e, ll m) {
    ll r = 1 % m; a %= m;
    for (; e; e >>= 1, a = a * a % m) if (e & 1) r = r * a % m;
    return r;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int T; cin >> T;
    while (T--) {
        ll p, n; cin >> p >> n;
        if (n >= p) { cout << 0 << '\n'; continue; }
        ll t = 1;
        for (ll k = n + 1; k <= p - 1; k++) t = t * k % p;
        cout << (p - power(t, p - 2, p)) % p << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long power(long a, long e, long m) {
        long r = 1 % m; a %= m;
        for (; e > 0; e >>= 1, a = a * a % m) if ((e & 1) == 1) r = r * a % m;
        return r;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int T = in.nextInt();
        while (T-- > 0) {
            long p = in.nextLong(), n = in.nextLong();
            if (n >= p) { out.println(0); continue; }
            long t = 1;
            for (long k = n + 1; k <= p - 1; k++) t = t * k % p;
            out.println((p - power(t, p - 2, p)) % p);
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
5
7 3
7 6
7 7
13 10
1000000007 1000000005
out:
6
6
0
6
1
-->
<!-- test
in:
3
2 1
1000000007 999000000
1999999973 1999999000
out:
1
869544707
1847711786
-->

### Example 4 — Power Tower  ·  ★ 2700

- **Source:** [CF 906D · Power Tower](https://codeforces.com/problemset/problem/906/D) — 2700
- **Difficulty:** 2700
- **Problem:** $n \le 10^5$ values $1 \le w_i \le 10^9$, a modulus $2 \le m \le 10^9$, and $q \le 10^5$ queries $(l, r)$: print $w_l^{\,w_{l+1}^{\,\cdot^{\cdot^{w_r}}}} \bmod m$ (exponentiation is right-associative).
- **Thinking from first principles:** The exponent of $w_l$ is itself a tower — astronomically large, so we need it modulo $\varphi(m)$, whose exponent we need modulo $\varphi(\varphi(m))$, and so on. Two things make this finite and correct:
  1. The chain $m, \varphi(m), \varphi^{(2)}(m), \dots$ hits $1$ within about $2\log_2 m \approx 60$ steps (§2); modulo $1$ everything is $0$, so the recursion depth is bounded no matter how long the query range is.
  2. $w_l$ need not be coprime to $m$, so use the **generalised** Euler theorem: we must know whether the true exponent is $\ge \varphi(m)$. Carry values in the form "`x mod' M`" (keep $x$ if $x < M$, else $x \bmod M + M$), which is closed under multiplication of positive integers (§3). Then the image itself *is* a valid exponent: it is congruent to the true exponent mod $\varphi$ and it is $\ge \varphi$ exactly when the true one is.

<details><summary>Solution</summary>

Precompute the chain $c_0 = m, c_{k+1} = \varphi(c_k)$ until $c_k = 1$. Define $\mathrm{eval}(l, k)$ = image of the tower $w_l \uparrow \cdots \uparrow w_r$ under `mod'` $c_k$:
- if $c_k = 1$: return $1$ (the true value is $\ge 1$, so its image mod' 1 is $0 + 1$);
- if $l = r$: return `modp(w_l, c_k)`;
- else return `pow_flag(w_l, eval(l+1, k+1), c_k)`.

The answer is $\mathrm{eval}(l, 0) \bmod m$. Depth $\le \min(r - l + 1, \text{chain length})$, each level $O(\log)$ — $O(q \log^2 m)$ total.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
ll phi_single(ll n) {
    ll r = n;
    for (ll p = 2; p * p <= n; p++) {
        if (n % p) continue;
        while (n % p == 0) n /= p;
        r -= r / p;
    }
    if (n > 1) r -= r / n;
    return r;
}
ll modp(ll x, ll m) { return x < m ? x : x % m + m; }
ll pow_flag(ll a, ll e, ll m) {
    ll r = 1; a = modp(a, m);
    for (; e; e >>= 1) {
        if (e & 1) r = modp(r * a, m);
        a = modp(a * a, m);
    }
    return r;
}
int n, R;
vector<ll> w, chain;
ll eval(int l, int k) {
    if (chain[k] == 1) return 1;
    if (l == R) return modp(w[l], chain[k]);
    return pow_flag(w[l], eval(l + 1, k + 1), chain[k]);
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    ll m; cin >> n >> m;
    w.resize(n + 1);
    for (int i = 1; i <= n; i++) cin >> w[i];
    chain.push_back(m);
    while (chain.back() != 1) chain.push_back(phi_single(chain.back()));
    int q; cin >> q;
    while (q--) {
        int l; cin >> l >> R;
        cout << eval(l, 0) % m << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long phiSingle(long n) {
        long r = n;
        for (long p = 2; p * p <= n; p++) {
            if (n % p != 0) continue;
            while (n % p == 0) n /= p;
            r -= r / p;
        }
        if (n > 1) r -= r / n;
        return r;
    }
    static long modp(long x, long m) { return x < m ? x : x % m + m; }
    static long powFlag(long a, long e, long m) {
        long r = 1; a = modp(a, m);
        for (; e > 0; e >>= 1) {
            if ((e & 1) == 1) r = modp(r * a, m);
            a = modp(a * a, m);
        }
        return r;
    }
    static long[] w, chain;
    static int R;
    static long eval(int l, int k) {
        if (chain[k] == 1) return 1;
        if (l == R) return modp(w[l], chain[k]);
        return powFlag(w[l], eval(l + 1, k + 1), chain[k]);
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        long m = in.nextLong();
        w = new long[n + 1];
        for (int i = 1; i <= n; i++) w[i] = in.nextLong();
        List<Long> ch = new ArrayList<>();
        ch.add(m);
        while (ch.get(ch.size() - 1) != 1) ch.add(phiSingle(ch.get(ch.size() - 1)));
        chain = new long[ch.size()];
        for (int i = 0; i < chain.length; i++) chain[i] = ch.get(i);
        int q = in.nextInt();
        while (q-- > 0) {
            int l = in.nextInt(); R = in.nextInt();
            out.println(eval(l, 0) % m);
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
6 1000000000
1 2 2 3 3 3
8
1 1
1 6
2 2
2 3
2 4
4 4
4 5
4 6
out:
1
1
2
4
256
3
27
597484987
-->
<!-- test
in:
5 12
2 3 2 4 6
6
1 2
1 3
2 5
3 5
1 5
5 5
out:
8
8
9
4
8
6
-->

### Example 5 — Madoka and The Best University  ·  ★ 2200

- **Source:** [CF 1717E · Madoka and The Best University](https://codeforces.com/problemset/problem/1717/E) — 2200
- **Difficulty:** 2200
- **Problem:** Given $n \le 10^5$, compute $\sum \operatorname{lcm}(c, \gcd(a, b))$ over all triples of positive integers with $a + b + c = n$, modulo $10^9+7$.
- **Thinking from first principles:** $O(n^2)$ triples is too many. Fix $c$; then $s = a + b = n - c$, and the summand depends only on $d = \gcd(a, b)$, which must divide $s$ (since $d \mid a + b$). How many pairs $(a, b)$ with $a + b = s$, $\gcd(a, b) = d$? Write $a = dx$, $b = dy$: $x + y = s/d$, $\gcd(x, y) = 1 \iff \gcd(x, s/d) = 1$, $1 \le x < s/d$. That is $\varphi(s/d)$ pairs when $s/d \ge 2$ — and zero when $s/d = 1$ (then $x$ would be $0$; note $\varphi(1) = 1$ would be wrong here).

<details><summary>Solution</summary>

$$\text{answer} = \sum_{s=2}^{n-1}\ \sum_{\substack{d \mid s\\ d < s}} \varphi(s/d)\cdot\operatorname{lcm}(n - s, d).$$

Enumerate $d$ and its multiples $s = 2d, 3d, \dots \le n - 1$ (harmonic loop, $O(n\log n)$ pairs), each with one gcd. $\varphi$ from a sieve.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    long long n; cin >> n;
    const long long MOD = 1'000'000'007LL;
    vector<int> phi(n + 1);
    iota(phi.begin(), phi.end(), 0);
    for (int p = 2; p <= n; p++)
        if (phi[p] == p)
            for (int j = p; j <= n; j += p) phi[j] -= phi[j] / p;
    long long ans = 0;
    for (long long d = 1; d <= n; d++)
        for (long long s = 2 * d; s <= n - 1; s += d) {
            long long c = n - s;
            long long l = c / gcd(c, d) * d % MOD;
            ans = (ans + l * phi[s / d]) % MOD;
        }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long gcd(long a, long b) { while (b != 0) { long t = a % b; a = b; b = t; } return a; }
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int n = Integer.parseInt(br.readLine().trim());
        final long MOD = 1_000_000_007L;
        int[] phi = new int[n + 1];
        for (int i = 0; i <= n; i++) phi[i] = i;
        for (int p = 2; p <= n; p++)
            if (phi[p] == p)
                for (int j = p; j <= n; j += p) phi[j] -= phi[j] / p;
        long ans = 0;
        for (long d = 1; d <= n; d++)
            for (long s = 2 * d; s <= n - 1; s += d) {
                long c = n - s;
                long l = c / gcd(c, d) * d % MOD;
                ans = (ans + l * phi[(int) (s / d)]) % MOD;
            }
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
3
out:
1
-->
<!-- test
in:
5
out:
11
-->
<!-- test
in:
69228
out:
778304278
-->
<!-- test
in:
50
out:
29492
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Fermat needs $p \nmid a$; Euler needs $\gcd(a, n) = 1$.** For a non-unit base use the generalised theorem, and only for exponents $\ge \log_2 m$ — small exponents must be used exactly.
2. **Reducing an exponent mod $\varphi(m)$ when it is $0$ after reduction** is the classic bug: $a^{\varphi(m)}$ is $1$ for units but $a^0$ "looks" the same; for non-units it is not. The "$+\varphi(m)$" in the generalised theorem fixes exactly this.
3. **`r -= r / p`** in $\varphi$ is exact because $p \mid r$ at that moment; writing `r = r * (p - 1) / p` can overflow.
4. **Trial-division $\varphi$ is $O(\sqrt n)$ per call** — inside a loop over all divisors of $10^{12}$ that is $6720 \cdot 10^6$. Factor $n$ once and derive $\varphi$ of each divisor from its exponent vector.
5. **The $\varphi$ chain is short** ($\le 2\log_2 m$), so recursive tower evaluation needs no memo and never recurses deeply.
6. **Wilson's theorem is a primality test in theory only** — $O(p)$ multiplications. Use [Miller–Rabin](06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md).
7. **Java `StreamTokenizer` parses numbers as `double`** — values above $2^{53}$ (e.g. $10^{18}$) silently lose digits. Read them as words or use a byte-level reader.
8. **$\varphi(1) = 1$** but "pairs $(a, b)$ of positive integers with $a + b = s$ and $\gcd = 1$" is $\varphi(s)$ only for $s \ge 2$ — check boundary meanings when converting a count to $\varphi$ (Example 5).

---

## 7. Going further (toward 2400–2600+)

- **Prefix sums of $\varphi$ up to $10^{10}$** with Du's sieve: $\Phi(n) = \frac{n(n+1)}{2} - \sum_{d=2}^{n}\Phi(\lfloor n/d\rfloor)$ — [file 07](07-mobius-dirichlet-and-floor-sums.md).
- **Order and primitive roots**: replacing $\varphi(n)$ by $\operatorname{ord}_n(a)$ or the Carmichael function gives the exact period — [file 06](06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md).
- **Lifting the exponent**, $v_p(a^n - b^n)$ — [file 07](07-mobius-dirichlet-and-floor-sums.md).
- **Euler's theorem in $\mathbb{Z}[x]/(f)$ and matrix groups**: the period of a linear recurrence mod $p$ divides $p^k - 1$ for some $k$ (Pisano periods) — [linear recurrences](../15-Advanced-Math/01-matrices-and-linear-recurrences.md).

---

## 8. Practice ladder

**1400–1900**
- [ ] [CF 1295D · Same GCDs](https://codeforces.com/problemset/problem/1295/D) — 1800
- [ ] [CF 1514C · Product 1 Modulo N](https://codeforces.com/problemset/problem/1514/C) — 1600
- [ ] [CF 1753B · Factorial Divisibility](https://codeforces.com/problemset/problem/1753/B) — 1600
- [ ] [CF 1225D · Power Products](https://codeforces.com/problemset/problem/1225/D) — 1800
- [ ] [AtCoder ABC162 E · Sum of gcd of Tuples (Hard)](https://atcoder.jp/contests/abc162/tasks/abc162_e) — diff≈1662
- [ ] [CSES 1712 · Exponentiation II](https://cses.fi/problemset/task/1712)

**1900–2400**
- [ ] [CF 1717E · Madoka and The Best University](https://codeforces.com/problemset/problem/1717/E) — 2200
- [ ] [CF 1182E · Product Oriented Recurrence](https://codeforces.com/problemset/problem/1182/E) — 2300
- [ ] [CF 1366D · Two Divisors](https://codeforces.com/problemset/problem/1366/D) — 2000
- [ ] [CF 919E · Congruence Equation](https://codeforces.com/problemset/problem/919/E) — 2100
- [ ] [CF 1499D · The Number of Pairs](https://codeforces.com/problemset/problem/1499/D) — 2100

**2400+**
- [ ] [CF 906D · Power Tower](https://codeforces.com/problemset/problem/906/D) — 2700
- [ ] [CF 1106F · Lunar New Year and a Recursive Sequence](https://codeforces.com/problemset/problem/1106/F) — 2400
- [ ] [CF 1114F · Please, another Queries on Array?](https://codeforces.com/problemset/problem/1114/F) — 2400

---

## 9. LeetCode / FAANG cross-reference

- [LC 1447 · Simplified Fractions](https://leetcode.com/problems/simplified-fractions/) — Medium — the count is $\sum_{q\le n}\varphi(q)$; the listing is a gcd filter.
- [LC 372 · Super Pow](https://leetcode.com/problems/super-pow/) — Medium — $1337 = 7\cdot191$, $\varphi(1337) = 1140$: reduce the exponent with generalised Euler (or digit-by-digit powering).
- [LC 1922 · Count Good Numbers](https://leetcode.com/problems/count-good-numbers/) — Medium — Fermat would also let you reduce $n$ mod $p-1$.

Rare in interviews beyond "use fast exponentiation"; totients themselves almost never appear.

---

## 10. Self-check

1. Derive $\varphi(p^k)$ and explain why $\varphi$ is multiplicative.
2. Prove Euler's theorem with the permutation argument.
3. Prove $\sum_{d \mid n}\varphi(d) = n$.
4. Why is $\varphi(n)$ even for $n \ge 3$, and why does $n \to \varphi(n)$ reach 1 in $O(\log n)$ steps?
5. Compute $2^{100} \bmod 12$ with the generalised theorem.
6. Prove Wilson's theorem. What is $(n-1)! \bmod n$ for composite $n$?
7. In the power tower, why do we return $1$ (not $0$) when the modulus in the chain is $1$?
8. How many $x \in [1, 10^{6}]$ have $\gcd(x, 10^6) = 10^3$?

<details><summary>Answers</summary>

1. Non-units in $1..p^k$ are the $p^{k-1}$ multiples of $p$. CRT pairs residues mod $mn$ with pairs of residues, and units with pairs of units.
2. §1.2: $x \mapsto ax$ permutes the units; compare the products and cancel.
3. Partition $1..n$ by $d = \gcd(k, n)$; class $d$ has $\varphi(n/d)$ members.
4. $k \leftrightarrow n - k$ pairs units without fixed points. Once $n$ is even (after one step), $\varphi(n) \le n/2$.
5. $\varphi(12) = 4$; $100 \ge \log_2 12$, so $2^{100} \equiv 2^{(100 \bmod 4) + 4} = 2^4 = 16 \equiv 4 \pmod{12}$.
6. Pair each element of $\lbrace 2..p-2 \rbrace$ with its inverse; only $\pm1$ are self-inverse. Composite $n$: $0$, except $n = 4$ ($3! \equiv 2$).
7. We return the `mod'` image: the true tower is $\ge 1 = c_k$, so its image is $(\text{value} \bmod 1) + 1 = 1$, which tells the level above "the exponent is large".
8. $x = 1000y$ with $\gcd(y, 1000) = 1$, $y \le 1000$: $\varphi(1000) = 400$.

</details>
