# Divisibility, GCD/LCM and the Extended Euclidean Algorithm

> **Band:** 🟢 800 – 🟣 2100 · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [complexity](../01-Foundations/01-complexity-and-constraint-reading.md), [overflow](../01-Foundations/06-integer-overflow-precision-and-fast-io.md)
> **You can say you know this when:** you can prove $\gcd(a,b)=\gcd(b,a \bmod b)$ and Bézout from scratch, write extended Euclid iteratively without looking, and count the integer solutions of $ax+by=c$ inside a box with negative coefficients and no off-by-one.

---

## 1. First principles — why this works

### 1.1 Divisibility is about the set of integer combinations

Write $a \mid b$ ("$a$ divides $b$") when $b = ka$ for some integer $k$. Everything in this file follows from one object:

$$L(a,b) = \lbrace ax + by : x, y \in \mathbb{Z} \rbrace .$$

$L$ is closed under addition, subtraction and multiplication by integers. Let $g$ be the **smallest positive** element of $L$ (assume $a, b$ not both $0$). Then:

1. **Every element of $L$ is a multiple of $g$.** Take $v \in L$, divide: $v = qg + r$ with $0 \le r < g$. Then $r = v - qg \in L$, and $r < g$ forces $r = 0$ (otherwise $g$ was not the smallest).
2. **$g$ divides $a$ and $b$**, because $a = a\cdot 1 + b \cdot 0 \in L$ and $b \in L$.
3. **Every common divisor $d$ of $a$ and $b$ divides $g$**, because $d \mid ax + by$ for all $x, y$.

So $g$ is a common divisor that every other common divisor divides — it is *the* greatest common divisor, and it is an integer combination of $a$ and $b$. That is **Bézout's identity**, obtained without any algorithm. The algorithm (Euclid) is just a fast way to *find* $g$ and the coefficients.

### 1.2 Rediscovering Euclid

Naive: try every $d$ from $\min(a,b)$ down to $1$ — $O(\min(a,b))$, hopeless for $10^{18}$.
Key observation: for any integer $q$, the pairs $(a, b)$ and $(a - qb, b)$ have **exactly the same common divisors** ($d \mid a, d \mid b \Rightarrow d \mid a-qb$, and conversely $d \mid a-qb, d\mid b \Rightarrow d \mid a$). Choosing $q = \lfloor a/b \rfloor$ gives

$$\gcd(a,b) = \gcd(b,\ a \bmod b), \qquad \gcd(a, 0) = \lvert a \rvert .$$

The numbers shrink, so the process terminates. How fast? If $b \le a/2$ then $a \bmod b < b \le a/2$; if $b > a/2$ then $a \bmod b = a - b < a/2$. Either way **the larger number at least halves every two steps**, so Euclid takes $O(\log \min(a,b))$ iterations. Lamé's theorem (§2.4) sharpens this: the worst case is consecutive Fibonacci numbers, at most $\approx 1.44 \log_2 \min(a,b)$ divisions — about 90 for 64-bit inputs.

### 1.3 Rediscovering extended Euclid — carry the certificate along

Euclid replaces $(r_0, r_1) = (a, b)$ by $(r_1, r_2)$, $(r_2, r_3)$, … with $r_{k+1} = r_{k-1} - q_k r_k$. If we keep, for every remainder, *how it was made from $a$ and $b$*,

$$r_k = a\,x_k + b\,y_k ,$$

the same linear recurrence works on the coefficients: $x_{k+1} = x_{k-1} - q_k x_k$, $y_{k+1} = y_{k-1} - q_k y_k$, starting from $r_0 = a = a\cdot1 + b\cdot0$ and $r_1 = b = a\cdot 0 + b \cdot 1$. When the remainder hits $0$, the previous row holds $g = a x + b y$. That is the whole algorithm: **an invariant ($r = ax+by$) maintained under the Euclid step.**

The recursive form comes from unrolling one step: if $b x' + (a \bmod b) y' = g$ and $a \bmod b = a - \lfloor a/b \rfloor b$, then

$$a\,y' + b\,\bigl(x' - \lfloor a/b \rfloor y'\bigr) = g \;\Rightarrow\; (x, y) = \bigl(y',\ x' - \lfloor a/b\rfloor y'\bigr).$$

### 1.4 From one solution to all solutions

For $ax + by = c$: every left side lies in $L(a,b) = g\mathbb{Z}$, so a solution exists **iff $g \mid c$**. Scaling the Bézout pair by $c/g$ gives one solution $(x_0, y_0)$. If $(x, y)$ is another, subtracting gives $a(x-x_0) = -b(y-y_0)$; divide by $g$: $a'(x-x_0) = -b'(y-y_0)$ with $\gcd(a', b') = 1$, so $b' \mid x - x_0$ (Euclid's lemma, §2.2). Writing $x - x_0 = kb'$ forces $y - y_0 = -ka'$:

$$x = x_0 + k\frac{b}{g}, \qquad y = y_0 - k\frac{a}{g}, \qquad k \in \mathbb{Z}.$$

All solutions form an arithmetic progression **in one parameter $k$** — so "count solutions in a box", "minimise $\lvert x\rvert+\lvert y\rvert$", "smallest non-negative $x$" all become one-dimensional problems about $k$.

---

## 2. Formulas, definitions and identities

### 2.1 Basic divisibility

| Fact | Meaning / proof sketch |
|---|---|
| $a \mid b,\ b \mid c \Rightarrow a \mid c$ | $c = k_2 b = k_2 k_1 a$. |
| $a \mid b,\ a \mid c \Rightarrow a \mid bx + cy$ | Closure of multiples under combination. |
| Division algorithm: $a = qb + r$, $0 \le r < \lvert b \rvert$ | Unique. In C++/Java `%` gives $r$ with the sign of $a$ — see §6. |
| $\gcd(a,b) = \gcd(b, a-b) = \gcd(b, a \bmod b)$ | Same set of common divisors (§1.2). |
| $\gcd(ka, kb) = \lvert k\rvert\gcd(a,b)$ | $L(ka,kb) = k\,L(a,b)$. |
| $\gcd(a/g, b/g) = 1$ for $g = \gcd(a,b)$ | Divide Bézout $ax+by=g$ by $g$. |
| $\gcd(a, b) = 1,\ \gcd(a, c) = 1 \Rightarrow \gcd(a, bc) = 1$ | Multiply $(ax_1+by_1)(ax_2+cy_2)=1$: the result is $a(\dots) + bc\,y_1y_2 = 1$. |
| $\gcd(a, bc) = \gcd(a, c)$ if $\gcd(a,b)=1$ | Generalisation of the previous line. |
| $\gcd(a_1,\dots,a_n) = \gcd(\gcd(a_1,\dots,a_{n-1}), a_n)$ | Associativity; $\gcd(0, x) = x$ makes $0$ the identity. |

### 2.2 Euclid's lemma and unique factorisation

**Euclid's lemma.** If $\gcd(a, b) = 1$ and $a \mid bc$ then $a \mid c$.
*Proof.* $ax + by = 1 \Rightarrow c = acx + bcy$; $a$ divides both terms. ∎
For a prime $p$: $p \mid bc \Rightarrow p \mid b$ or $p \mid c$. Induction gives the **Fundamental Theorem of Arithmetic**: every $n \ge 2$ is $\prod p_i^{e_i}$ uniquely. With exponents $v_p$:

$$\gcd(a,b) = \prod_p p^{\min(v_p(a), v_p(b))}, \qquad \operatorname{lcm}(a,b) = \prod_p p^{\max(v_p(a), v_p(b))}.$$

### 2.3 GCD–LCM identities

| Identity | Proof sketch |
|---|---|
| $\gcd(a,b)\cdot\operatorname{lcm}(a,b) = ab$ ($a,b>0$) | $\min(x,y) + \max(x,y) = x + y$ for each prime exponent. |
| Compute $\operatorname{lcm}(a,b) = a / \gcd(a,b) \cdot b$ | Divide **first**: $a/g \cdot b$ overflows only if the lcm itself does. |
| $\operatorname{lcm}(a, \gcd(b,c)) = \gcd(\operatorname{lcm}(a,b), \operatorname{lcm}(a,c))$ | Per prime: $\max(x, \min(y,z)) = \min(\max(x,y), \max(x,z))$. Divisibility is a *distributive lattice*. |
| $\gcd(a, \operatorname{lcm}(b,c)) = \operatorname{lcm}(\gcd(a,b), \gcd(a,c))$ | Dual identity, same per-prime argument. |
| $\gcd(a^m - 1,\ a^n - 1) = a^{\gcd(m,n)} - 1$ ($a \ge 2$) | Below. |
| $\gcd(F_m, F_n) = F_{\gcd(m,n)}$ | Below. |
| $\gcd(n, n+1) = 1$; $\gcd(n, n+2) \in \lbrace 1,2 \rbrace$; $\gcd(a, b) \mid a-b$ | Special cases of $\gcd(a,b) = \gcd(a, b-a)$. |

**Proof of $\gcd(a^m-1, a^n-1) = a^{\gcd(m,n)}-1$.** For $m = qn + r$:
$a^m - 1 = a^r(a^{qn} - 1) + (a^r - 1)$, and $a^n - 1 \mid a^{qn}-1$ (because $x - 1 \mid x^q - 1$ with $x = a^n$). So
$a^m - 1 \equiv a^{r} - 1 \pmod{a^n - 1}$ with $0 \le a^r - 1 < a^n - 1$, i.e. "$(a^m-1) \bmod (a^n-1) = a^{m \bmod n} - 1$".
Euclid on the pair of numbers therefore runs Euclid on the exponents, ending at $a^{\gcd(m,n)} - 1$. ∎

**Proof of $\gcd(F_m, F_n) = F_{\gcd(m,n)}$** ($F_0 = 0, F_1 = 1$).
(i) $\gcd(F_n, F_{n+1}) = 1$: Euclid on $(F_{n+1}, F_n)$ gives $(F_n, F_{n-1})$, …, down to $(1, 0)$.
(ii) The addition formula $F_{m+n} = F_m F_{n+1} + F_{m-1} F_n$ (induction on $n$, or read it off the matrix identity $Q^{m+n} = Q^m Q^n$ with $Q = \begin{psmallmatrix}1&1\\1&0\end{psmallmatrix}$, $Q^k = \begin{psmallmatrix}F_{k+1}&F_k\\F_k&F_{k-1}\end{psmallmatrix}$).
(iii) Hence $\gcd(F_{m+n}, F_n) = \gcd(F_m F_{n+1}, F_n) = \gcd(F_m, F_n)$ by (i) and §2.1. So $\gcd(F_m, F_n) = \gcd(F_{m \bmod n}, F_n)$ — Euclid on indices again. ∎

### 2.4 Complexity of Euclid (Lamé)

**Theorem (Lamé).** If Euclid on $a > b \ge 1$ performs $k$ division steps, then $b \ge F_{k+1}$ and $a \ge F_{k+2}$.
*Proof by induction on $k$.* $k = 1$: $b \ge 1 = F_2$, $a > b$ gives $a \ge 2 = F_3$. Step: the first division maps $(a, b)$ to $(b, a \bmod b)$, which takes $k-1$ more steps, so $b \ge F_{k+1}$ and $a \bmod b \ge F_k$; then $a = qb + (a \bmod b) \ge b + (a \bmod b) \ge F_{k+1} + F_k = F_{k+2}$. ∎
Since $F_k \approx \varphi^k/\sqrt5$, $k \le \log_\varphi b + O(1) \approx 1.44\log_2 b$. Consecutive Fibonacci numbers attain it (every quotient is $1$). Each step is one 64-bit division, so `gcd` is effectively $O(\log)$ with a small constant.

**Amortised gcd chains.** Computing $g \leftarrow \gcd(g, a_i)$ for $i = 1..n$ costs $O(n + \log \max a)$ in total, not $O(n \log)$: whenever the gcd changes, it at least halves, so the total number of "non-trivial" Euclid steps telescopes.

**Distinct prefix gcds.** For a fixed right end $r$, the values $\gcd(a_l, \dots, a_r)$ over $l = r, r-1, \dots, 1$ form a divisor chain; each change divides by at least $2$, so there are **at most $\lfloor\log_2 \max a\rfloor + 1$ distinct values**. This is the basis of "all subarray gcds" techniques (Example 3).

### 2.5 Bézout and extended Euclid

| Statement | Note |
|---|---|
| $\exists x,y:\ ax + by = \gcd(a,b)$ | §1.1. The set of all $ax+by$ is exactly $\gcd(a,b)\,\mathbb{Z}$. |
| Recursive step: $(x,y) = (y',\ x' - \lfloor a/b\rfloor y')$ | §1.3. Base: $\gcd(a, 0) = a = a\cdot 1 + 0 \cdot 0$. |
| Size of coefficients: $\lvert x\rvert \le b/g$, $\lvert y\rvert \le a/g$ (for $a, b > 0$) | Standard extended Euclid output; so $a x$ never exceeds $ab/g = \operatorname{lcm}$ in magnitude — products fit in 64 bits whenever $a, b \le 10^{9}$, and need care (or `__int128`) beyond that. |
| $\gcd(a,m) = 1 \Rightarrow a^{-1} \bmod m = x \bmod m$ from $ax + my = 1$ | Inverse modulo a non-prime — see [modular arithmetic](02-modular-arithmetic-and-inverses.md). |

### 2.6 Linear Diophantine equation $ax + by = c$

| Question | Answer |
|---|---|
| Solvable? | iff $g = \gcd(a,b) \mid c$ (and if $a = b = 0$: iff $c = 0$). |
| One solution | $(x_0, y_0) = (x_g \cdot c/g,\ y_g \cdot c/g)$ where $a x_g + b y_g = g$. Signs: run extended Euclid on $\lvert a\rvert, \lvert b\rvert$ and flip $x_g$ if $a<0$, $y_g$ if $b<0$. |
| All solutions | $x = x_0 + k\,b/g$, $y = y_0 - k\,a/g$, $k \in \mathbb{Z}$ (§1.4). |
| Smallest $x \ge 0$ | $x_{\min} = x_0 \bmod (b/g)$ taken in $[0, \lvert b/g\rvert)$. |
| Count with $x \in [x_1, x_2]$, $y \in [y_1, y_2]$ | Each bound gives an interval of $k$: $x_1 \le x_0 + k s_x \le x_2$ with $s_x = b/g$. If $s_x>0$: $k \in [\lceil (x_1 - x_0)/s_x \rceil, \lfloor (x_2 - x_0)/s_x \rfloor]$; if $s_x < 0$ the bounds swap. Intersect with the $y$-interval ($s_y = -a/g$). Answer $\max(0, R - L + 1)$. |
| Non-negative solutions of $ax+by=c$ with $a,b>0$ | $x \ge 0 \Rightarrow k \ge \lceil -x_0 g/b\rceil$; $y \ge 0 \Rightarrow k \le \lfloor y_0 g / a\rfloor$. |
| Minimise $\lvert x \rvert + \lvert y\rvert$ | $f(k) = \lvert x_0 + k b' \rvert + \lvert y_0 - k a'\rvert$ is convex piecewise linear in $k$ (sum of convex functions); its minimum is at a breakpoint, i.e. at $\lfloor\cdot\rfloor/\lceil\cdot\rceil$ of $-x_0/b'$ or $y_0/a'$. Try those 4 values (±1 for safety). |
| Minimise $\lvert x\rvert + \lvert y \rvert$ subject to $a,b>0$, quick bound | Optimal $\lvert x \rvert \le \lvert c\rvert/a + b/g$, which is why brute forces in a small window work for testing. |
| Frobenius (two coins, $\gcd(a,b)=1$) | Largest $c$ **not** representable as $ax+by$ with $x,y \ge 0$ is $ab - a - b$; exactly $(a-1)(b-1)/2$ values are not representable (🧊 Sylvester). |

**Floor and ceiling division with negatives** (needed above): C++ and Java `/` truncate toward zero.

$$\left\lfloor \tfrac{p}{q} \right\rfloor = \texttt{p/q} - [\,p \bmod q \ne 0 \ \wedge\ (p<0) \ne (q<0)\,], \qquad \left\lceil \tfrac{p}{q} \right\rceil = -\left\lfloor \tfrac{-p}{q} \right\rfloor .$$

Java has `Math.floorDiv` / `Math.floorMod`; C++ has no built-in.

### 2.7 Binary GCD (Stein's algorithm)

Uses only shifts and subtraction, from three facts: $\gcd(2a, 2b) = 2\gcd(a,b)$; $\gcd(2a, b) = \gcd(a, b)$ for odd $b$; $\gcd(a, b) = \gcd(\lvert a - b \rvert, \min(a,b))$ and for two odd numbers $a-b$ is even. With `__builtin_ctzll` (count trailing zeros) all powers of two are stripped in one instruction. $O(\log a + \log b)$ subtractions, no divisions — roughly 2–3× faster than `%`-Euclid on 64-bit values, which matters only when gcd is the inner loop (e.g. $10^8$ gcd calls).

Library calls: C++17 `std::gcd`, `std::lcm` (`<numeric>`, accept signed types and return the absolute gcd; `lcm` can overflow silently); GCC's `__gcd` (older, works on negative inputs inconsistently — prefer `std::gcd`). Java: **there is no `Math.gcd`**; write the 3-line loop, or use `BigInteger.valueOf(a).gcd(BigInteger.valueOf(b))` for arbitrary precision.

---

## 3. Implementation (C++ and Java)

```cpp
// Iterative gcd, binary gcd, extended Euclid (iterative + recursive), safe lcm, floor/ceil division.
long long gcd_ll(long long a, long long b) {      // returns gcd(|a|, |b|); gcd(0,0) = 0
    a = llabs(a); b = llabs(b);
    while (b) { a %= b; swap(a, b); }
    return a;
}
unsigned long long binary_gcd(unsigned long long a, unsigned long long b) {
    if (!a || !b) return a | b;
    int shift = __builtin_ctzll(a | b);            // common power of two
    a >>= __builtin_ctzll(a);
    do {
        b >>= __builtin_ctzll(b);                  // b becomes odd
        if (a > b) swap(a, b);
        b -= a;                                    // odd - odd = even (or 0)
    } while (b);
    return a << shift;
}
// returns g = gcd(a, b) >= 0 and x, y with a*x + b*y = g  (a, b may be negative)
long long ext_gcd(long long a, long long b, long long &x, long long &y) {
    long long x0 = 1, y0 = 0, x1 = 0, y1 = 1;      // invariants: a0*x0 + b0*y0 = a, a0*x1 + b0*y1 = b
    while (b != 0) {
        long long q = a / b;
        tie(a, b) = make_pair(b, a - q * b);
        tie(x0, x1) = make_pair(x1, x0 - q * x1);
        tie(y0, y1) = make_pair(y1, y0 - q * y1);
    }
    if (a < 0) { a = -a; x0 = -x0; y0 = -y0; }
    x = x0; y = y0;
    return a;
}
long long ext_gcd_rec(long long a, long long b, long long &x, long long &y) {
    if (b == 0) { x = 1; y = 0; return a; }
    long long x1, y1;
    long long g = ext_gcd_rec(b, a % b, x1, y1);
    x = y1; y = x1 - (a / b) * y1;
    return g;
}
long long lcm_ll(long long a, long long b) { return a / gcd_ll(a, b) * b; }   // divide first
long long floor_div(long long p, long long q) { return p / q - ((p % q != 0) && ((p < 0) != (q < 0))); }
long long ceil_div(long long p, long long q) { return -floor_div(-p, q); }
```

```java
// Iterative gcd, binary gcd, extended Euclid (iterative + recursive), safe lcm, floor/ceil division.
static long gcd(long a, long b) {                  // gcd(|a|, |b|)
    a = Math.abs(a); b = Math.abs(b);
    while (b != 0) { long t = a % b; a = b; b = t; }
    return a;
}
static long binaryGcd(long a, long b) {            // a, b >= 0
    if (a == 0 || b == 0) return a | b;
    int shift = Long.numberOfTrailingZeros(a | b);
    a >>= Long.numberOfTrailingZeros(a);
    do {
        b >>= Long.numberOfTrailingZeros(b);
        if (a > b) { long t = a; a = b; b = t; }
        b -= a;
    } while (b != 0);
    return a << shift;
}
// returns {g, x, y} with a*x + b*y = g >= 0
static long[] extGcd(long a, long b) {
    long x0 = 1, y0 = 0, x1 = 0, y1 = 1;
    while (b != 0) {
        long q = a / b, t;
        t = a - q * b; a = b; b = t;
        t = x0 - q * x1; x0 = x1; x1 = t;
        t = y0 - q * y1; y0 = y1; y1 = t;
    }
    if (a < 0) { a = -a; x0 = -x0; y0 = -y0; }
    return new long[]{a, x0, y0};
}
static long[] extGcdRec(long a, long b) {
    if (b == 0) return new long[]{a, 1, 0};
    long[] r = extGcdRec(b, a % b);
    return new long[]{r[0], r[2], r[1] - (a / b) * r[2]};
}
static long lcm(long a, long b) { return a / gcd(a, b) * b; }
static long floorDiv(long p, long q) { return Math.floorDiv(p, q); }
static long ceilDiv(long p, long q) { return -Math.floorDiv(-p, q); }
```

---

## 4. Recognising the pattern

| Signal in the statement | Think |
|---|---|
| "gcd of the whole array after adding $x$ to every element" | $\gcd(a_1+x, a_2+x, \dots) = \gcd(a_1 + x, a_2 - a_1, a_3 - a_1, \dots)$ — differences are invariant under shifts (Example 1). |
| Operations "replace $a$ by $a-b$" or "$a \bmod b$", pouring jugs, stepping by $\pm a, \pm b$ | Reachable set is the multiples of the gcd (Bézout). LC "Water and Jug" is exactly this. |
| "Find integers $x, y$", "how many ways to pay $c$ with coins $a$ and $b$" | Linear Diophantine: one solution by extended Euclid, then the one-parameter family. |
| "gcd over all subarrays / count subarrays with gcd $= k$" | Distinct gcds per right end are $O(\log)$ — keep a compressed list (Example 3). |
| Huge indices with gcd: $\gcd(F_m, F_n)$, $\gcd(2^m-1, 2^n-1)$ | Euclid on the indices. |
| "lcm of many numbers mod $p$" | Never compute the lcm directly; take max prime exponents ([sieves](03-sieves-and-factorization.md)). |
| Periodicity "both events happen together" | Period is $\operatorname{lcm}$; first coincidence via [CRT](05-crt-and-linear-congruences.md). |

Confusions: Bézout gives *some* solution with possibly negative coefficients — if the statement requires $x, y \ge 0$ you still need the range analysis. And gcd of differences only works for **adding the same** value to every element, not multiplying.

---

## 5. Worked examples (graded)

### Example 1 — Row GCD  ·  ★ 1600

- **Source:** [CF 1458A · Row GCD](https://codeforces.com/problemset/problem/1458/A) — 1600
- **Difficulty:** 1600
- **Problem:** Arrays $a$ ($n \le 2\cdot10^5$) and $b$ ($m \le 2\cdot10^5$), values up to $10^{18}$. For every $j$ print $\gcd(a_1 + b_j, \dots, a_n + b_j)$.
- **Thinking from first principles:** Recomputing a gcd of $n$ numbers per query is $O(nm)$. The values change with $j$, but their *differences* $a_i - a_1$ do not. Since $\gcd(u, v) = \gcd(u, v - u)$, apply it to every element against the first: $\gcd(a_1 + b_j, a_2 + b_j, \dots) = \gcd(a_1 + b_j, a_2 - a_1, \dots, a_n - a_1)$. The tail is a constant $G$.

<details><summary>Solution</summary>

Precompute $G = \gcd_i \lvert a_i - a_1\rvert$, answer $\gcd(a_1 + b_j, G)$. $O(n + m)$ gcd calls plus $O(\log)$ amortised. $a_1 + b_j \le 2\cdot10^{18}$ fits in signed 64-bit. For $n=1$, $G = 0$ and $\gcd(x, 0) = x$ — no special case.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<long long> a(n);
    for (auto &x : a) cin >> x;
    long long G = 0;
    for (int i = 1; i < n; i++) G = gcd(G, llabs(a[i] - a[0]));
    for (int j = 0; j < m; j++) {
        long long b;
        cin >> b;
        cout << gcd(a[0] + b, G) << (j + 1 == m ? '\n' : ' ');
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long gcd(long a, long b) { while (b != 0) { long t = a % b; a = b; b = t; } return Math.abs(a); }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), m = in.nextInt();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        long G = 0;
        for (int i = 1; i < n; i++) G = gcd(G, Math.abs(a[i] - a[0]));
        StringBuilder sb = new StringBuilder();
        for (int j = 0; j < m; j++) {
            long b = in.nextLong();
            sb.append(gcd(a[0] + b, G)).append(j + 1 == m ? '\n' : ' ');
        }
        out.print(sb);
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
4 4
1 25 121 169
1 2 7 23
out:
2 3 8 24
-->
<!-- test
in:
1 3
1000000000000000000
1000000000000000000 1 7
out:
2000000000000000000 1000000000000000001 1000000000000000007
-->
<!-- test
in:
3 2
6 6 6
0 3
out:
6 9
-->

### Example 2 — GCD of two astronomically large Fibonacci numbers  ·  ★ ≈1800 (est.)

- **Source:** Original problem
- **Difficulty:** ≈1800 (est.)
- **Problem:** $t \le 10^5$ queries, each $1 \le m, n \le 10^{18}$. Print $\gcd(F_m, F_n) \bmod (10^9+7)$, where $F_1 = F_2 = 1$.
- **Thinking from first principles:** $F_{10^{18}}$ has $\approx 2\cdot10^{17}$ digits, so we cannot take a gcd of the numbers. Taking them mod $p$ first is wrong: $\gcd$ does not commute with reduction mod $p$. We need a structural fact: $\gcd(F_m, F_n) = F_{\gcd(m,n)}$ (§2.3). Now it is one gcd of indices plus one Fibonacci number mod $p$, computed by **fast doubling**: $F_{2k} = F_k(2F_{k+1} - F_k)$, $F_{2k+1} = F_k^2 + F_{k+1}^2$ (both from the addition formula with $m = k$ or $k+1$).

<details><summary>Solution</summary>

Walk the bits of $N = \gcd(m, n)$ from the top, keeping $(F_k, F_{k+1})$; each bit doubles $k$ (and adds $1$ if the bit is set). $O(\log N)$ per query. All products are of residues $< 2^{30}$, so they fit in 64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 1'000'000'007LL;
long long fib(unsigned long long n) {              // F_n mod MOD by fast doubling
    long long a = 0, b = 1;                        // (F_k, F_{k+1}), k = 0
    for (int bit = 63; bit >= 0; bit--) {
        long long c = a * ((2 * b - a + MOD) % MOD) % MOD;   // F_{2k}
        long long d = (a * a + b * b) % MOD;                 // F_{2k+1}
        if (n >> bit & 1) { a = d; b = (c + d) % MOD; }      // k -> 2k+1
        else { a = c; b = d; }                               // k -> 2k
    }
    return a;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        unsigned long long m, n; cin >> m >> n;
        cout << fib(gcd(m, n)) << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long fib(long n) {
        long a = 0, b = 1;
        for (int bit = 62; bit >= 0; bit--) {      // n <= 1e18 < 2^60
            long c = a * ((2 * b - a + MOD) % MOD) % MOD;
            long d = (a * a + b * b) % MOD;
            if ((n >> bit & 1) == 1) { a = d; b = (c + d) % MOD; } else { a = c; b = d; }
        }
        return a;
    }
    static long gcd(long a, long b) { while (b != 0) { long t = a % b; a = b; b = t; } return a; }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = in.nextInt();
        while (t-- > 0) out.println(fib(gcd(in.nextLong(), in.nextLong())));
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
6 9
12 18
1 1
100 150
7 11
out:
2
8
1
586268941
1
-->
<!-- test
in:
2
1000000000000000000 1000000000000000000
999999999999999989 2
out:
209783453
1
-->

### Example 3 — Sum of gcd over all subarrays  ·  ★ ≈1900 (est.)

- **Source:** Original problem (same technique as [CF 475D · CGCDSSQ](https://codeforces.com/problemset/problem/475/D) — 2000)
- **Difficulty:** ≈1900 (est.)
- **Problem:** $n \le 2\cdot10^5$, $1 \le a_i \le 10^6$. Print $\sum_{1 \le l \le r \le n} \gcd(a_l, \dots, a_r)$ (fits in 64-bit: at most $2\cdot10^{10}\cdot10^6$).
- **Thinking from first principles:** $O(n^2)$ subarrays is $2\cdot10^{10}$ — too slow even with $O(1)$ gcd updates. Fix the right end $r$. As $l$ moves left, $\gcd(a_l..a_r)$ only ever divides the previous value, and each strict change at least halves it (§2.4). So there are at most $\log_2 10^6 + 1 \approx 21$ distinct values, each attained on a contiguous range of $l$. Store the list of (value, how many $l$) for end $r$; moving to $r+1$ maps each value $v \mapsto \gcd(v, a_{r+1})$, appends $(a_{r+1}, 1)$, and merges equal neighbours.

<details><summary>Solution</summary>

Each step processes $O(\log A)$ pairs with one gcd each: $O(n \log A \cdot \log A)$ worst case, fast in practice (gcd of a number with its divisor-chain neighbours is cheap). Add $\sum v \cdot \text{cnt}$ for every $r$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<pair<int, long long>> cur, nxt;        // (gcd value, number of left ends)
    long long total = 0;
    for (int r = 0; r < n; r++) {
        int x; cin >> x;
        nxt.clear();
        for (auto [v, c] : cur) {
            int g = gcd(v, x);
            if (!nxt.empty() && nxt.back().first == g) nxt.back().second += c;
            else nxt.push_back({g, c});
        }
        if (!nxt.empty() && nxt.back().first == x) nxt.back().second += 1;
        else nxt.push_back({x, 1});
        swap(cur, nxt);
        for (auto [v, c] : cur) total += v * c;
    }
    cout << total << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int gcd(int a, int b) { while (b != 0) { int t = a % b; a = b; b = t; } return a; }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] val = new int[64], nval = new int[64];
        long[] cnt = new long[64], ncnt = new long[64];
        int sz = 0;
        long total = 0;
        for (int r = 0; r < n; r++) {
            int x = in.nextInt(), nsz = 0;
            for (int i = 0; i < sz; i++) {
                int g = gcd(val[i], x);
                if (nsz > 0 && nval[nsz - 1] == g) ncnt[nsz - 1] += cnt[i];
                else { nval[nsz] = g; ncnt[nsz] = cnt[i]; nsz++; }
            }
            if (nsz > 0 && nval[nsz - 1] == x) ncnt[nsz - 1]++;
            else { nval[nsz] = x; ncnt[nsz] = 1; nsz++; }
            int[] ti = val; val = nval; nval = ti;
            long[] tl = cnt; cnt = ncnt; ncnt = tl;
            sz = nsz;
            for (int i = 0; i < sz; i++) total += val[i] * cnt[i];
        }
        System.out.println(total);
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
2 4 6
out:
18
-->
<!-- test
in:
1
1000000
out:
1000000
-->
<!-- test
in:
6
12 18 7 14 28 5
out:
129
-->

### Example 4 — Count integer points of $ax + by = c$ in a box  ·  ★ ≈2000 (est.)

- **Source:** Original problem
- **Difficulty:** ≈2000 (est.)
- **Problem:** Given integers $a, b, c$ with $\lvert a\rvert, \lvert b\rvert, \lvert c\rvert \le 10^9$ and a box $x_1 \le x \le x_2$, $y_1 \le y \le y_2$ (coordinates in $[-10^9, 10^9]$), count integer pairs $(x, y)$ in the box with $ax + by = c$. $T \le 10^5$ test cases.
- **Thinking from first principles:** Iterating over $x$ is $2\cdot10^9$ per test. Every solution is $x_0 + k b/g$, $y_0 - k a/g$ (§1.4) — a single integer parameter. Each of the four box constraints is a half-line in $k$; intersect four half-lines. The traps: signs of $a, b$ (divide by a negative step flips the inequality), the degenerate cases $a = 0$ or $b = 0$, and floor division of negative numbers.

<details><summary>Solution</summary>

1. $a = b = 0$: every point works iff $c = 0$.
2. $a = 0$ (or $b = 0$): $y = c/b$ must be an integer in range; then any $x$ in $[x_1, x_2]$ works.
3. Otherwise extended Euclid on $\lvert a\rvert, \lvert b\rvert$; fail if $g \nmid c$; scale by $c/g$ (magnitude $\le 10^9 \cdot 10^9 = 10^{18}$, fits). Fix signs. For a constraint $lo \le v_0 + k s \le hi$ with $s \neq 0$, the $k$-interval is $[\lceil (lo - v_0)/s\rceil, \lfloor (hi - v_0)/s\rfloor]$ if $s > 0$ and $[\lceil (hi - v_0)/s \rceil, \lfloor (lo - v_0)/s\rfloor]$ if $s < 0$.

$O(\log)$ per test. Differences like $lo - v_0$ are at most $\approx 10^{18} + 10^9$ in magnitude — still within $9.2\cdot10^{18}$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
ll floor_div(ll p, ll q) { return p / q - ((p % q != 0) && ((p < 0) != (q < 0))); }
ll ceil_div(ll p, ll q) { return -floor_div(-p, q); }
ll ext_gcd(ll a, ll b, ll &x, ll &y) {
    if (b == 0) { x = 1; y = 0; return a; }
    ll x1, y1, g = ext_gcd(b, a % b, x1, y1);
    x = y1; y = x1 - (a / b) * y1;
    return g;
}
// k-range for lo <= v0 + k*s <= hi
pair<ll, ll> k_range(ll v0, ll s, ll lo, ll hi) {
    if (s > 0) return {ceil_div(lo - v0, s), floor_div(hi - v0, s)};
    return {ceil_div(hi - v0, s), floor_div(lo - v0, s)};
}
ll solve(ll a, ll b, ll c, ll x1, ll x2, ll y1, ll y2) {
    if (x1 > x2 || y1 > y2) return 0;
    if (a == 0 && b == 0) return c == 0 ? (x2 - x1 + 1) * (y2 - y1 + 1) : 0;
    if (a == 0) { if (c % b) return 0; ll y = c / b; return (y1 <= y && y <= y2) ? x2 - x1 + 1 : 0; }
    if (b == 0) { if (c % a) return 0; ll x = c / a; return (x1 <= x && x <= x2) ? y2 - y1 + 1 : 0; }
    ll x0, y0, g = ext_gcd(llabs(a), llabs(b), x0, y0);
    if (c % g) return 0;
    x0 *= c / g; y0 *= c / g;
    if (a < 0) x0 = -x0;
    if (b < 0) y0 = -y0;
    auto [l1, r1] = k_range(x0, b / g, x1, x2);
    auto [l2, r2] = k_range(y0, -a / g, y1, y2);
    ll L = max(l1, l2), R = min(r1, r2);
    return max(0LL, R - L + 1);
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int T; cin >> T;
    while (T--) {
        ll a, b, c, x1, x2, y1, y2;
        cin >> a >> b >> c >> x1 >> x2 >> y1 >> y2;
        cout << solve(a, b, c, x1, x2, y1, y2) << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long ceilDiv(long p, long q) { return -Math.floorDiv(-p, q); }
    static long[] extGcd(long a, long b) {
        if (b == 0) return new long[]{a, 1, 0};
        long[] r = extGcd(b, a % b);
        return new long[]{r[0], r[2], r[1] - (a / b) * r[2]};
    }
    static long[] kRange(long v0, long s, long lo, long hi) {
        if (s > 0) return new long[]{ceilDiv(lo - v0, s), Math.floorDiv(hi - v0, s)};
        return new long[]{ceilDiv(hi - v0, s), Math.floorDiv(lo - v0, s)};
    }
    static long solve(long a, long b, long c, long x1, long x2, long y1, long y2) {
        if (x1 > x2 || y1 > y2) return 0;
        if (a == 0 && b == 0) return c == 0 ? (x2 - x1 + 1) * (y2 - y1 + 1) : 0;
        if (a == 0) { if (c % b != 0) return 0; long y = c / b; return (y1 <= y && y <= y2) ? x2 - x1 + 1 : 0; }
        if (b == 0) { if (c % a != 0) return 0; long x = c / a; return (x1 <= x && x <= x2) ? y2 - y1 + 1 : 0; }
        long[] e = extGcd(Math.abs(a), Math.abs(b));
        long g = e[0];
        if (c % g != 0) return 0;
        long x0 = e[1] * (c / g), y0 = e[2] * (c / g);
        if (a < 0) x0 = -x0;
        if (b < 0) y0 = -y0;
        long[] r1 = kRange(x0, b / g, x1, x2), r2 = kRange(y0, -a / g, y1, y2);
        long L = Math.max(r1[0], r2[0]), R = Math.min(r1[1], r2[1]);
        return Math.max(0, R - L + 1);
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int T = in.nextInt();
        while (T-- > 0) {
            long a = in.nextLong(), b = in.nextLong(), c = in.nextLong();
            long x1 = in.nextLong(), x2 = in.nextLong(), y1 = in.nextLong(), y2 = in.nextLong();
            out.println(solve(a, b, c, x1, x2, y1, y2));
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
1 1 3 0 3 0 3
2 4 7 -10 10 -10 10
-3 5 1 -20 20 -20 20
0 0 0 1 3 -1 1
0 5 10 -2 2 1 2
4 -6 10 -100 100 -100 100
out:
4
0
8
9
5
67
-->
<!-- test
in:
3
1000000000 999999999 1 -1000000000 1000000000 -1000000000 1000000000
7 0 14 0 5 -3 3
3 3 1 -5 5 -5 5
out:
2
7
0
-->

### Example 5 — Minimum number of $\pm a$ / $\pm b$ jumps  ·  ★ ≈2000 (est.)

- **Source:** Original problem
- **Difficulty:** ≈2000 (est.)
- **Problem:** A token starts at $0$ on the integer line. One move shifts it by $+a$, $-a$, $+b$ or $-b$ ($1 \le a, b \le 10^9$). For $T \le 10^5$ targets $c$ ($\lvert c\rvert \le 10^9$) print the minimum number of moves to reach $c$, or $-1$.
- **Thinking from first principles:** Order of moves does not matter, so a plan is "net $x$ moves of $a$ and net $y$ moves of $b$" with $ax + by = c$ and cost $\lvert x\rvert + \lvert y\rvert$ (never use $+a$ and $-a$ together). BFS over positions is infinite in principle. The solutions form $x = x_0 + kb'$, $y = y_0 - ka'$; the cost $f(k)$ is a sum of two convex V-shapes, so its minimum is at one of the two kinks $k \approx -x_0/b'$ or $k \approx y_0/a'$ — evaluate the integers around them.

<details><summary>Solution</summary>

$g = \gcd(a, b)$; if $g \nmid c$ print $-1$. Otherwise compute $(x_0, y_0)$, the kinks, and evaluate $f$ at $\lfloor\cdot\rfloor$, $\lceil\cdot\rceil$ of each kink. A convex function of an integer variable attains its minimum next to a real kink, so these candidates suffice. Values $x_0 = x_g c/g$ reach $10^{18}$; after moving to the kink the terms are $O(a + b + \lvert c\rvert)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
ll floor_div(ll p, ll q) { return p / q - ((p % q != 0) && ((p < 0) != (q < 0))); }
ll ext_gcd(ll a, ll b, ll &x, ll &y) {
    if (b == 0) { x = 1; y = 0; return a; }
    ll x1, y1, g = ext_gcd(b, a % b, x1, y1);
    x = y1; y = x1 - (a / b) * y1;
    return g;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    ll a, b; int T;
    cin >> a >> b >> T;
    ll xg, yg, g = ext_gcd(a, b, xg, yg);
    ll ap = a / g, bp = b / g;
    while (T--) {
        ll c; cin >> c;
        if (c % g) { cout << -1 << '\n'; continue; }
        ll x0 = xg * (c / g), y0 = yg * (c / g);
        ll best = LLONG_MAX;
        ll kinks[2] = {floor_div(-x0, bp), floor_div(y0, ap)};
        for (ll k0 : kinks)
            for (ll k = k0 - 1; k <= k0 + 2; k++)
                best = min(best, llabs(x0 + k * bp) + llabs(y0 - k * ap));
        cout << best << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long[] extGcd(long a, long b) {
        if (b == 0) return new long[]{a, 1, 0};
        long[] r = extGcd(b, a % b);
        return new long[]{r[0], r[2], r[1] - (a / b) * r[2]};
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        long a = in.nextLong(), b = in.nextLong();
        int T = in.nextInt();
        long[] e = extGcd(a, b);
        long g = e[0], ap = a / g, bp = b / g;
        while (T-- > 0) {
            long c = in.nextLong();
            if (c % g != 0) { out.println(-1); continue; }
            long x0 = e[1] * (c / g), y0 = e[2] * (c / g);
            long best = Long.MAX_VALUE;
            long[] kinks = {Math.floorDiv(-x0, bp), Math.floorDiv(y0, ap)};
            for (long k0 : kinks)
                for (long k = k0 - 1; k <= k0 + 2; k++)
                    best = Math.min(best, Math.abs(x0 + k * bp) + Math.abs(y0 - k * ap));
            out.println(best);
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
3 5 6
1
2
0
7
-4
11
out:
3
2
0
3
4
3
-->
<!-- test
in:
4 6 4
2
3
-10
1000000000
out:
2
-1
2
166666667
-->

---

## 6. Tricks, pitfalls and things to remember

1. **`%` of a negative number is negative** in both C++ and Java (`-7 % 3 == -1`). Extended Euclid works with signed values, but any "smallest non-negative" answer needs `((x % m) + m) % m` or Java `Math.floorMod`.
2. **Integer division truncates toward zero**, so `(-7) / 2 == -3`, not $-4$. Every $k$-range computation needs a real `floor_div` (§2.6). This is the #1 WA in Diophantine counting.
3. **lcm overflow**: write `a / gcd(a,b) * b`, and if the lcm can exceed $10^{18}$ cap it (`if (a / g > LIMIT / b) lcm = LIMIT + 1`) or use `__int128`. `std::lcm` does not detect overflow.
4. **$\gcd(0, 0) = 0$** and $\gcd(x, 0) = \lvert x\rvert$ — so start accumulators at $0$, not at $a_1$, and singletons work automatically (Example 1 with $n=1$).
5. **Scaling the Bézout pair** by $c/g$ can overflow when $a, b, c$ are near $10^{18}$; reduce $x_0$ modulo $b/g$ *before* multiplying (using `__int128` for the product) when values are that large.
6. **Use `std::gcd` not `__gcd`** for signed inputs; in Java remember there is no `Math.gcd` — a missing helper costs minutes in contest.
7. **gcd of differences** only applies to a common *additive* shift. For multiplicative changes think about prime exponents instead.
8. **Recursion depth** of recursive extended Euclid is $O(\log)$ — safe in both languages; the iterative form avoids array allocation in Java (`long[]` per level).
9. **Lamé in practice:** gcd costs ~90 divisions worst case on 64-bit; a gcd inside an $O(n^2)$ loop with $n = 5000$ is $2.5\cdot10^7$ gcds — fine; inside $O(n^2)$ with $n = 2\cdot10^4$ use binary GCD or rethink.
10. **Counting solutions with $x, y \ge 0$** for $a, b > 0$: the count of non-negative solutions of $ax + by = c$ is $\lfloor c\,g/(ab)\rfloor$ or that plus one — compute it exactly with the $k$-range, never with the estimate.

---

## 7. Going further (toward 2400–2600+)

- **Lattice-point counting under a line** $\sum_{i<n} \lfloor (ai+b)/m \rfloor$ is Euclid in disguise — see `floor_sum` in [Möbius and floor sums](07-mobius-dirichlet-and-floor-sums.md).
- **Continued fractions and best rational approximations** (Stern–Brocot tree): the quotients $q_k$ of Euclid are the continued-fraction digits of $a/b$; the convergents are the best approximations. Used in "find the fraction with smallest denominator in an interval" (🧊).
- **gcd on a segment tree / sparse table**: $\gcd$ is idempotent and associative, so sparse tables answer range-gcd in $O(1)$ after $O(n \log n)$ — see [sparse table](../08-Data-Structures/05-sparse-table-and-rmq.md).
- **Polynomial gcd** and the "half-gcd" algorithm (🧊) — [polynomials](../15-Advanced-Math/04-polynomials-and-generating-functions.md).
- **Euclid-like algorithms on other structures**: "universal Euclid" for sums $\sum f(\lfloor (ai+b)/c \rfloor)$ with monoid values (🔴), Gaussian-integer gcd.

---

## 8. Practice ladder

**≤ 1400**
- [ ] [CF 1370A · Maximum GCD](https://codeforces.com/problemset/problem/1370/A) — 800
- [ ] [CF 1389A · LCM Problem](https://codeforces.com/problemset/problem/1389/A) — 800
- [ ] [CF 1325A · EhAb AnD gCd](https://codeforces.com/problemset/problem/1325/A) — 800
- [ ] [CF 1742D · Coprime](https://codeforces.com/problemset/problem/1742/D) — 1100
- [ ] [CF 1091C · New Year and the Sphere Transmission](https://codeforces.com/problemset/problem/1091/C) — 1400
- [ ] [CF 1285C · Fadi and LCM](https://codeforces.com/problemset/problem/1285/C) — 1400

**1400–1900**
- [ ] [CF 1458A · Row GCD](https://codeforces.com/problemset/problem/1458/A) — 1600
- [ ] [CF 1342C · Yet Another Counting Problem](https://codeforces.com/problemset/problem/1342/C) — 1600
- [ ] [CF 75C · Modified GCD](https://codeforces.com/problemset/problem/75/C) — 1600
- [ ] [CF 1260C · Infinite Fence](https://codeforces.com/problemset/problem/1260/C) — 1700
- [ ] [CF 7C · Line](https://codeforces.com/problemset/problem/7/C) — 1800
- [ ] [CF 1034A · Enlarge GCD](https://codeforces.com/problemset/problem/1034/A) — 1800
- [ ] [CF 1548B · Integers Have Friends](https://codeforces.com/problemset/problem/1548/B) — 1800

**1900–2400**
- [ ] [CF 1547F · Array Stabilization (GCD version)](https://codeforces.com/problemset/problem/1547/F) — 1900
- [ ] [CF 475D · CGCDSSQ](https://codeforces.com/problemset/problem/475/D) — 2000
- [ ] [CF 1244C · The Football Season](https://codeforces.com/problemset/problem/1244/C) — 2000
- [ ] [CF 1900D · Small GCD](https://codeforces.com/problemset/problem/1900/D) — 2000
- [ ] [CF 1366D · Two Divisors](https://codeforces.com/problemset/problem/1366/D) — 2000
- [ ] [CF 1665D · GCD Guess](https://codeforces.com/problemset/problem/1665/D) — 2000
- [ ] [CF 1513D · GCD and MST](https://codeforces.com/problemset/problem/1513/D) — 2000
- [ ] [CF 1762D · GCD Queries ](https://codeforces.com/problemset/problem/1762/D) — 2100

**AtCoder / CSES**
- [ ] [AtCoder ABC125 C · GCD on Blackboard](https://atcoder.jp/contests/abc125/tasks/abc125_c) — diff≈1197
- [ ] [AtCoder ARC159 B · GCD Subtraction](https://atcoder.jp/contests/arc159/tasks/arc159_b) — diff≈1438
- [ ] [AtCoder AGC022 B · GCD Sequence](https://atcoder.jp/contests/agc022/tasks/agc022_b) — diff≈1645
- [ ] [CSES 1081 · Common Divisors](https://cses.fi/problemset/task/1081)

---

## 9. LeetCode / FAANG cross-reference

- [LC 1979 · Find Greatest Common Divisor of Array](https://leetcode.com/problems/find-greatest-common-divisor-of-array/) — Easy — gcd of min and max.
- [LC 1071 · Greatest Common Divisor of Strings](https://leetcode.com/problems/greatest-common-divisor-of-strings/) — Easy — answer is the prefix of length $\gcd(\lvert s\rvert, \lvert t\rvert)$ iff $s+t = t+s$.
- [LC 914 · X of a Kind in a Deck of Cards](https://leetcode.com/problems/x-of-a-kind-in-a-deck-of-cards/) — Easy — gcd of all counts $\ge 2$.
- [LC 365 · Water and Jug Problem](https://leetcode.com/problems/water-and-jug-problem/) — Medium — Bézout: reachable iff $\gcd \mid$ target and target $\le x + y$.
- [LC 1250 · Check If It Is a Good Array](https://leetcode.com/problems/check-if-it-is-a-good-array/) — Hard — Bézout for $n$ numbers: gcd of all equals 1.
- [LC 2447 · Number of Subarrays With GCD Equal to K](https://leetcode.com/problems/number-of-subarrays-with-gcd-equal-to-k/) — Medium — the $O(\log)$-distinct-gcd list of Example 3.
- [LC 2654 · Minimum Number of Operations to Make All Array Elements Equal to 1](https://leetcode.com/problems/minimum-number-of-operations-to-make-all-array-elements-equal-to-1/) — Medium — shortest subarray with gcd 1.
- [LC 149 · Max Points on a Line](https://leetcode.com/problems/max-points-on-a-line/) — Hard — normalise slopes by dividing $(dx, dy)$ by their gcd.

Interviews use gcd mostly as a normalisation tool (fractions, slopes) and Bézout reasoning (jugs); extended Euclid itself is rare.

---

## 10. Self-check

1. Prove that the smallest positive value of $ax+by$ divides both $a$ and $b$.
2. Why does Euclid finish in $O(\log)$ steps? Give the "halves every two steps" argument and the worst-case input.
3. Derive the recursive extended-Euclid update $(x, y) = (y', x' - \lfloor a/b \rfloor y')$.
4. $ax + by = c$ has solution $(x_0, y_0)$. Write all solutions and prove there are no others.
5. Compute $\gcd(2^{48}-1, 2^{36}-1)$ without a calculator.
6. For a fixed right end, why are there only $O(\log A)$ distinct subarray gcds?
7. What does `(-7) / 2` evaluate to in C++ and Java, and what is $\lfloor -7/2 \rfloor$?
8. Why is `a / gcd(a,b) * b` safer than `a * b / gcd(a,b)`?

<details><summary>Answers</summary>

1. Let $g$ be the smallest positive element of $L(a,b)$. Divide $a = qg + r$; $r = a - qg \in L$ and $0 \le r < g$, so $r = 0$. Same for $b$.
2. If $b \le a/2$, $a \bmod b < b \le a/2$; otherwise $a \bmod b = a - b < a/2$. So the pair's larger element halves in two steps. Worst case: consecutive Fibonacci numbers (all quotients 1), $\approx 1.44 \log_2 b$ steps.
3. From $bx' + (a - \lfloor a/b\rfloor b) y' = g$, regroup: $a y' + b(x' - \lfloor a/b \rfloor y') = g$.
4. $x = x_0 + k b/g$, $y = y_0 - k a/g$. If $(x,y)$ is a solution, $a'(x-x_0) = -b'(y - y_0)$ with $\gcd(a', b') = 1$, so $b' \mid x - x_0$, and then $y$ is forced.
5. $2^{\gcd(48,36)} - 1 = 2^{12} - 1 = 4095$.
6. The gcds for $l = r, r-1, \dots$ form a chain where each divides the previous; a strict change divides by at least 2, so at most $\log_2 A + 1$ values.
7. Both give $-3$ (truncation); $\lfloor -3.5 \rfloor = -4$. Use `Math.floorDiv` or a `floor_div` helper.
8. The intermediate $a \cdot b$ can overflow even when the lcm fits; $a/g$ is exact, and $(a/g) \cdot b$ equals the lcm itself.

</details>
