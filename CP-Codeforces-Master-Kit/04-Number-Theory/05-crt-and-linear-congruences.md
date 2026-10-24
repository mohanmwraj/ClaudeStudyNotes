# Chinese Remainder Theorem and Linear Congruences

> **Band:** 🔵 1700 – 🟠 2500 · **Priority:** 🔥 (two-modulus merge) · ⚡ (Garner) · **FAANG:** low · **Prerequisites:** [extended Euclid](01-divisibility-gcd-and-extended-euclid.md), [modular inverses](02-modular-arithmetic-and-inverses.md)
> **You can say you know this when:** you can solve $ax \equiv b \pmod m$ for any $m$, merge two congruences with non-coprime moduli without overflow, count the integers in $[L, R]$ that satisfy a system, and reconstruct a number from its residues with Garner's algorithm.

---

## 1. First principles — why this works

### 1.1 One congruence: $ax \equiv b \pmod m$

This is the equation $ax - my = b$ in integers — a linear Diophantine equation ([§1.4 of the gcd file](01-divisibility-gcd-and-extended-euclid.md)). With $g = \gcd(a, m)$:

- if $g \nmid b$: no solution;
- otherwise divide everything by $g$: $a' x \equiv b' \pmod{m'}$ with $\gcd(a', m') = 1$, so $x \equiv b' \cdot (a')^{-1} \pmod{m'}$ — **one** residue class mod $m' = m/g$, which is $g$ distinct classes mod $m$.

The cancellation law ([modular arithmetic §2.1](02-modular-arithmetic-and-inverses.md)) is exactly why dividing the modulus by $g$ is forced, not optional.

### 1.2 Two congruences with coprime moduli — the constructive proof

Find $x$ with $x \equiv a_1 \pmod{m_1}$, $x \equiv a_2 \pmod{m_2}$, $\gcd(m_1, m_2) = 1$. Build "basis vectors": a number $e_1$ that is $1$ mod $m_1$ and $0$ mod $m_2$, and $e_2$ the other way round. Multiples of $m_2$ are $0$ mod $m_2$; we need one that is $1$ mod $m_1$: $e_1 = m_2\,(m_2^{-1} \bmod m_1)$ (the inverse exists because the moduli are coprime). Then $x = a_1 e_1 + a_2 e_2$ works. For $k$ pairwise coprime moduli with $M = \prod m_i$, $M_i = M/m_i$:

$$x \equiv \sum_{i=1}^{k} a_i\,M_i\,\bigl(M_i^{-1} \bmod m_i\bigr) \pmod M .$$

**Uniqueness.** If $x, x'$ both work, every $m_i$ divides $x - x'$; pairwise coprime ⇒ $M \mid x - x'$. So there is exactly one solution in $[0, M)$.

Counting gives the deeper statement: the map $x \bmod M \mapsto (x \bmod m_1, \dots, x \bmod m_k)$ is injective (uniqueness) between two sets of size $M$, hence a **bijection**, and it respects $+$ and $\times$ — a ring isomorphism $\mathbb{Z}/M \cong \prod \mathbb{Z}/m_i$. This is why multiplicative functions are multiplicative ($\varphi$, number of roots of polynomials mod $m$, …) and why "solve modulo each prime power, then glue" is a universal strategy.

### 1.3 Non-coprime moduli — merge by substitution

The sum formula breaks when moduli share factors (no inverses). Substitution always works: from the first congruence $x = a_1 + m_1 t$; plug into the second:

$$m_1 t \equiv a_2 - a_1 \pmod{m_2}.$$

That is a single linear congruence in $t$ (§1.1). With $g = \gcd(m_1, m_2)$: solvable iff $g \mid a_2 - a_1$, and then $t \equiv \frac{a_2 - a_1}{g}\cdot\left(\frac{m_1}{g}\right)^{-1} \pmod{\frac{m_2}{g}}$. Taking the smallest such $t \ge 0$,

$$x \equiv a_1 + m_1 t \pmod{\operatorname{lcm}(m_1, m_2)}.$$

The solution is unique modulo the lcm (both moduli divide $x - x'$ iff the lcm does). Merging a list one congruence at a time solves any system; inconsistency shows up as $g \nmid a_2 - a_1$ at some step. **Consistency condition** in one line: $a_i \equiv a_j \pmod{\gcd(m_i, m_j)}$ for all pairs (necessary for each pair, and sufficient overall — prime by prime the congruences are nested).

**Overflow.** $t < m_2/g$ and $x = a_1 + m_1 t < m_1 m_2 / g = \operatorname{lcm}$. If all moduli are $\le 10^9$ and the final lcm is $\le 10^{18}$, every product in the formula stays below $10^{18}$ — signed 64-bit suffices when the multiplications are ordered as above (reduce $\frac{a_2-a_1}{g}$ modulo $m_2/g$ *before* multiplying by the inverse). With moduli up to $10^{18}$ use `__int128`.

### 1.4 Garner: reconstruct without ever holding $M$

When $M = \prod m_i$ is astronomically large (e.g. three NTT primes, $M \approx 10^{27}$) but you want $x \bmod$ some other $Q$, write $x$ in **mixed radix**:

$$x = v_1 + v_2 m_1 + v_3 m_1 m_2 + \cdots + v_k m_1\cdots m_{k-1}, \qquad 0 \le v_i < m_i .$$

Reducing modulo $m_i$ kills every later term, so $v_i$ is determined by the earlier ones: $v_i \equiv \bigl(r_i - (v_1 + v_2 m_1 + \dots + v_{i-1}m_1\cdots m_{i-2})\bigr)\cdot (m_1\cdots m_{i-1})^{-1} \pmod{m_i}$. All arithmetic is modulo small numbers; finally evaluate the mixed-radix sum modulo $Q$. $O(k^2)$ operations.

---

## 2. Formulas, definitions and identities

| Statement | Meaning / proof sketch |
|---|---|
| $ax \equiv b \pmod m$ solvable $\iff \gcd(a, m) \mid b$ | Bézout (§1.1). |
| … then $x \equiv \frac{b}{g}\left(\frac{a}{g}\right)^{-1} \pmod{\frac{m}{g}}$; exactly $g$ solutions mod $m$ | Cancellation law. |
| CRT (pairwise coprime): unique $x \bmod M$, $x = \sum a_i M_i (M_i^{-1} \bmod m_i)$ | §1.2. |
| Two congruences solvable $\iff a_1 \equiv a_2 \pmod{\gcd(m_1, m_2)}$ | §1.3. |
| Merged: $x \equiv a_1 + m_1 t \pmod{\operatorname{lcm}(m_1,m_2)}$, $t = \frac{a_2 - a_1}{g}\bigl(\frac{m_1}{g}\bigr)^{-1} \bmod \frac{m_2}{g}$ | Substitution. |
| $\mathbb{Z}/M \cong \prod_i \mathbb{Z}/m_i$ (coprime $m_i$) | Bijection + respects $+, \times$. |
| #solutions of $f(x) \equiv 0 \pmod m$ $= \prod_{p^k \parallel m}$ #solutions mod $p^k$ | CRT bijection on solution sets. E.g. $x^2 \equiv 1 \pmod m$ has $2^{\omega(m)}$ solutions for odd $m$. |
| # of $x \in [L, R]$ with $x \equiv x_0 \pmod M$ | $\lfloor (R - x_0)/M\rfloor - \lfloor (L - 1 - x_0)/M \rfloor$ (floor division, works for negatives). |
| Garner mixed radix | §1.4; $O(k^2)$, intermediate values $< \max m_i$. |
| System $a_i x \equiv b_i \pmod{m_i}$ | Reduce each to $x \equiv c_i \pmod{m_i/g_i}$ (§1.1), then merge. |
| Coincidence of periodic events: event A at $t \equiv a_1 \pmod{p_1}$, B at $t \equiv a_2 \pmod{p_2}$ | First common time by merging; then every $\operatorname{lcm}(p_1,p_2)$. |
| Composite modulus strategy | $m = \prod p_i^{k_i}$: solve mod each $p_i^{k_i}$ (Lucas/Hensel/etc.), glue with CRT. |

---

## 3. Implementation (C++ and Java)

```cpp
// Linear congruence, general CRT merge (__int128-safe), Garner reconstruction.
using i128 = __int128;
long long ext_gcd(long long a, long long b, long long &x, long long &y) {
    if (b == 0) { x = 1; y = 0; return a; }
    long long x1, y1, g = ext_gcd(b, a % b, x1, y1);
    x = y1; y = x1 - (a / b) * y1;
    return g;
}
// all x with a*x == b (mod m): returns {x0, m/g} or {-1, -1}
pair<long long, long long> solve_linear(long long a, long long b, long long m) {
    a %= m; if (a < 0) a += m;
    b %= m; if (b < 0) b += m;
    long long x, y, g = ext_gcd(a, m, x, y);
    if (b % g) return {-1, -1};
    long long mm = m / g;
    long long x0 = (long long)((i128)(x % mm + mm) % mm * (b / g) % mm);
    return {x0, mm};
}
// merge x == a1 (mod m1) and x == a2 (mod m2); returns {a, lcm} with 0 <= a < lcm, or {-1, -1}
pair<long long, long long> crt_merge(long long a1, long long m1, long long a2, long long m2) {
    long long p, q, g = ext_gcd(m1, m2, p, q);      // m1*p + m2*q = g
    long long diff = a2 - a1;
    if (diff % g) return {-1, -1};
    long long m2g = m2 / g;
    long long t = (long long)((i128)(diff / g % m2g + m2g) % m2g * ((p % m2g + m2g) % m2g) % m2g);
    long long L = m1 / g * m2;                       // lcm; caller guarantees it fits
    long long x = (long long)(((i128)a1 + (i128)m1 * t) % L);
    if (x < 0) x += L;
    return {x, L};
}
pair<long long, long long> crt(const vector<long long> &a, const vector<long long> &m) {
    long long A = 0, M = 1;
    for (size_t i = 0; i < a.size(); i++) {
        auto [x, L] = crt_merge(A, M, ((a[i] % m[i]) + m[i]) % m[i], m[i]);
        if (L == -1) return {-1, -1};
        A = x; M = L;
    }
    return {A, M};
}
// Garner: pairwise coprime moduli m[i] (< 2^31), residues r[i]; returns x mod Q where x in [0, prod m)
long long garner(const vector<long long> &r, const vector<long long> &m, long long Q) {
    auto inv = [&](long long v, long long md) { long long x, y; ext_gcd(((v % md) + md) % md, md, x, y); return ((x % md) + md) % md; };
    int k = r.size();
    vector<long long> v(k);
    for (int i = 0; i < k; i++) {
        long long cur = 0, prod = 1;                 // value of v_0 + v_1 m_0 + ... mod m[i]
        for (int j = 0; j < i; j++) { cur = (cur + v[j] * prod) % m[i]; prod = prod * (m[j] % m[i]) % m[i]; }
        v[i] = ((r[i] - cur) % m[i] + m[i]) % m[i] * inv(prod, m[i]) % m[i];
    }
    long long x = 0, prod = 1 % Q;
    for (int i = 0; i < k; i++) { x = (x + v[i] % Q * prod) % Q; prod = prod * (m[i] % Q) % Q; }
    return x;
}
```

```java
// Linear congruence, general CRT merge (moduli <= ~1e9 or lcm-safe via BigInteger), Garner.
static long[] extGcd(long a, long b) {
    if (b == 0) return new long[]{a, 1, 0};
    long[] r = extGcd(b, a % b);
    return new long[]{r[0], r[2], r[1] - (a / b) * r[2]};
}
static long[] solveLinear(long a, long b, long m) {        // {x0, m/g} or null
    a = Math.floorMod(a, m); b = Math.floorMod(b, m);
    long[] e = extGcd(a, m);
    long g = e[0];
    if (b % g != 0) return null;
    long mm = m / g;
    long x0 = BigInteger.valueOf(Math.floorMod(e[1], mm)).multiply(BigInteger.valueOf(b / g)).mod(BigInteger.valueOf(mm)).longValue();
    return new long[]{x0, mm};
}
// merge; exact with BigInteger, so any 64-bit moduli whose lcm fits in long are fine
static long[] crtMerge(long a1, long m1, long a2, long m2) {
    long[] e = extGcd(m1, m2);
    long g = e[0], diff = a2 - a1;
    if (diff % g != 0) return null;
    long m2g = m2 / g;
    BigInteger t = BigInteger.valueOf(diff / g).mod(BigInteger.valueOf(m2g))
        .multiply(BigInteger.valueOf(Math.floorMod(e[1], m2g))).mod(BigInteger.valueOf(m2g));
    BigInteger L = BigInteger.valueOf(m1 / g).multiply(BigInteger.valueOf(m2));
    BigInteger x = BigInteger.valueOf(a1).add(BigInteger.valueOf(m1).multiply(t)).mod(L);
    return new long[]{x.longValue(), L.longValue()};
}
static long garner(long[] r, long[] m, long Q) {            // pairwise coprime m[i] < 2^31
    int k = r.length;
    long[] v = new long[k];
    for (int i = 0; i < k; i++) {
        long cur = 0, prod = 1;
        for (int j = 0; j < i; j++) { cur = (cur + v[j] * prod) % m[i]; prod = prod * (m[j] % m[i]) % m[i]; }
        long inv = Math.floorMod(extGcd(prod, m[i])[1], m[i]);
        v[i] = Math.floorMod(r[i] - cur, m[i]) * inv % m[i];
    }
    long x = 0, prod = 1 % Q;
    for (int i = 0; i < k; i++) { x = (x + v[i] % Q * prod) % Q; prod = prod * (m[i] % Q) % Q; }
    return x;
}
```

---

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "remainder $a_i$ when divided by $m_i$", "both clocks show …", "the bus and the train meet" | system of congruences → merge |
| a quantity that depends on $n \bmod A$ and on $n \bmod B$ separately | CRT pairs the two residues into one residue mod $\operatorname{lcm}(A, B)$ (Example 5) |
| answer needed modulo a composite like $10^9$ or $2^{32}\cdot$odd | solve modulo prime powers, glue |
| exact big integer needed, modular tools only | multi-modular + Garner |
| "is the unknown determined by these remainders?" | determined mod $\operatorname{lcm}$ — compare with the target modulus (Example 2) |
| $ax \equiv b$ with $\gcd(a, m) > 1$ | §1.1: $g$ solutions or none |

Do not confuse CRT with "the answer is periodic, so brute force one period": CRT tells you the *period* is the lcm, and often that period is too long to brute force — then you count residues instead.

---

## 5. Worked examples (graded)

### Example 1 — General CRT with non-coprime moduli  ·  ★ ≈1900 (est.)

- **Source:** Original problem
- **Difficulty:** ≈1900 (est.)
- **Problem:** $k \le 10^5$ congruences $x \equiv a_i \pmod{m_i}$, $1 \le m_i \le 10^9$, $0 \le a_i < m_i$. The lcm of all $m_i$ is guaranteed to be $\le 10^{18}$. Print the smallest $x \ge 0$ satisfying all of them, or $-1$.
- **Thinking from first principles:** Pairwise-coprime CRT does not apply (moduli may share factors). Merge left to right by substitution (§1.3). Keep the current solution as $(A, M)$ meaning "$x \equiv A \pmod M$"; merging with $(a, m)$ needs $g = \gcd(M, m) \mid a - A$. The bound on the lcm means every intermediate $M$ is $\le 10^{18}$, and with $m \le 10^9$ the products $t\cdot(\text{inverse}) < 10^{18}$ and $M t < \operatorname{lcm}$ never overflow.

<details><summary>Solution</summary>

$O(k \log)$. The C++ uses `__int128` defensively; the Java version shows that plain `long` suffices under these constraints when the operations are ordered carefully: reduce $(a - A)/g$ modulo $m/g$ first.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
ll ext_gcd(ll a, ll b, ll &x, ll &y) {
    if (b == 0) { x = 1; y = 0; return a; }
    ll x1, y1, g = ext_gcd(b, a % b, x1, y1);
    x = y1; y = x1 - (a / b) * y1;
    return g;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int k; cin >> k;
    ll A = 0, M = 1;
    bool ok = true;
    for (int i = 0; i < k; i++) {
        ll a, m; cin >> a >> m;
        if (!ok) continue;
        ll p, q, g = ext_gcd(M, m, p, q);          // M*p + m*q = g
        if ((a - A) % g != 0) { ok = false; continue; }
        ll mg = m / g;
        ll t = (ll)((__int128)(((a - A) / g) % mg + mg) % mg * ((p % mg + mg) % mg) % mg);
        ll L = M / g * m;
        A = (ll)(((__int128)A + (__int128)M * t) % L);
        M = L;
    }
    cout << (ok ? A : -1) << '\n';
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
        int k = in.nextInt();
        long A = 0, M = 1;
        boolean ok = true;
        for (int i = 0; i < k; i++) {
            long a = in.nextLong(), m = in.nextLong();
            if (!ok) continue;
            long[] e = extGcd(M, m);
            long g = e[0];
            if ((a - A) % g != 0) { ok = false; continue; }
            long mg = m / g;
            long t = Math.floorMod((a - A) / g, mg) * Math.floorMod(e[1], mg) % mg;  // both factors < 1e9
            long L = M / g * m;
            A = (A + M * t) % L;                    // M * t < lcm <= 1e18
            M = L;
        }
        System.out.println(ok ? A : -1);
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
2 3
3 5
2 7
out:
23
-->
<!-- test
in:
2
1 4
2 6
out:
-1
-->
<!-- test
in:
3
3 4
5 6
7 10
out:
47
-->
<!-- test
in:
3
123456789 999999937
987654321 999999929
123456789 999999937
out:
608024617817903461
-->

### Example 2 — Remainders Game  ·  ★ 1800

- **Source:** [CF 687B · Remainders Game](https://codeforces.com/problemset/problem/687/B) — 1800
- **Difficulty:** 1800
- **Problem:** You know $x \bmod c_i$ for $n \le 10^6$ values $c_i \le 10^6$ (but not $x$). Is $x \bmod k$ ($k \le 10^6$) determined for every possible $x$? Print `Yes` or `No`.
- **Thinking from first principles:** The residues mod all $c_i$ determine $x$ exactly modulo $L = \operatorname{lcm}(c_i)$ (CRT uniqueness) and no further: $x$ and $x + L$ are indistinguishable. So $x \bmod k$ is determined iff $k \mid L$. $L$ itself can be astronomically large; but only the part shared with $k$ matters: $k \mid L \iff k = \operatorname{lcm}_i \gcd(c_i, k)$ (per prime, $v_p(k) \le \max_i v_p(c_i) \iff v_p(k) = \max_i \min(v_p(c_i), v_p(k))$). That running lcm never exceeds $k$.

<details><summary>Solution</summary>

$G \leftarrow \operatorname{lcm}(G, \gcd(c_i, k))$, starting at $1$. Answer `Yes` iff $G = k$. $O(n\log k)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; long long k; cin >> n >> k;
    long long G = 1;
    for (int i = 0; i < n; i++) {
        long long c; cin >> c;
        long long d = gcd(c, k);
        G = G / gcd(G, d) * d;                 // divides k, so never exceeds k
    }
    cout << (G == k ? "Yes" : "No") << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long gcd(long a, long b) { while (b != 0) { long t = a % b; a = b; b = t; } return a; }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long k = in.nextLong(), G = 1;
        for (int i = 0; i < n; i++) {
            long d = gcd(in.nextLong(), k);
            G = G / gcd(G, d) * d;
        }
        System.out.println(G == k ? "Yes" : "No");
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
4 5
2 3 5 12
out:
Yes
-->
<!-- test
in:
2 7
2 3
out:
No
-->
<!-- test
in:
3 12
4 6 9
out:
Yes
-->
<!-- test
in:
2 8
4 12
out:
No
-->

### Example 3 — Two Arithmetic Progressions  ·  ★ 2500

- **Source:** [CF 710D · Two Arithmetic Progressions](https://codeforces.com/problemset/problem/710/D) — 2500
- **Difficulty:** 2500
- **Problem:** Given $0 < a_1, a_2 \le 2\cdot10^9$ and $-2\cdot10^9 \le b_1, b_2, L, R \le 2\cdot10^9$, $L \le R$: count integers $x \in [L, R]$ with $x = a_1 k + b_1 = a_2 l + b_2$ for some integers $k, l \ge 0$.
- **Thinking from first principles:** Drop $k, l \ge 0$ for a moment: $x$ is in both progressions iff $x \equiv b_1 \pmod{a_1}$ and $x \equiv b_2 \pmod{a_2}$ — a two-congruence system. Its solutions are one class $x_0 \bmod \operatorname{lcm}(a_1, a_2)$ (or none). The conditions $k, l \ge 0$ just say $x \ge b_1$ and $x \ge b_2$. So: merge, then count the class in $[\max(L, b_1, b_2), R]$. Values: $\operatorname{lcm} \le 4\cdot10^{18}$ still fits in signed 64-bit; the residues $b_i$ must be normalised to $[0, a_i)$ first (they can be negative).

<details><summary>Solution</summary>

Merge with `__int128` (C++) / `BigInteger` (Java) for safety, then count with floor divisions: $\#\lbrace x \in [lo, R] : x \equiv x_0 \pmod M\rbrace = \lfloor (R - x_0)/M\rfloor - \lfloor (lo - 1 - x_0)/M\rfloor$. $O(\log)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
using i128 = __int128;
ll ext_gcd(ll a, ll b, ll &x, ll &y) {
    if (b == 0) { x = 1; y = 0; return a; }
    ll x1, y1, g = ext_gcd(b, a % b, x1, y1);
    x = y1; y = x1 - (a / b) * y1;
    return g;
}
ll floor_div(ll p, ll q) { return p / q - ((p % q != 0) && ((p < 0) != (q < 0))); }
int main() {
    ll a1, b1, a2, b2, L, R;
    cin >> a1 >> b1 >> a2 >> b2 >> L >> R;
    ll r1 = ((b1 % a1) + a1) % a1, r2 = ((b2 % a2) + a2) % a2;
    ll p, q, g = ext_gcd(a1, a2, p, q);
    if ((r2 - r1) % g != 0) { cout << 0 << '\n'; return 0; }
    ll mg = a2 / g;
    ll t = (ll)((i128)((((r2 - r1) / g) % mg + mg) % mg) * ((p % mg + mg) % mg) % mg);
    ll M = a1 / g * a2;                          // <= 4e18
    ll x0 = (ll)(((i128)r1 + (i128)a1 * t) % M);
    ll lo = max({L, b1, b2});
    if (lo > R) { cout << 0 << '\n'; return 0; }
    cout << floor_div(R - x0, M) - floor_div(lo - 1 - x0, M) << '\n';
}
```

```java
import java.util.*;
import java.io.*;
import java.math.BigInteger;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        long a1 = Long.parseLong(st.nextToken()), b1 = Long.parseLong(st.nextToken());
        long a2 = Long.parseLong(st.nextToken()), b2 = Long.parseLong(st.nextToken());
        long L = Long.parseLong(st.nextToken()), R = Long.parseLong(st.nextToken());
        BigInteger A1 = BigInteger.valueOf(a1), A2 = BigInteger.valueOf(a2);
        BigInteger r1 = BigInteger.valueOf(b1).mod(A1), r2 = BigInteger.valueOf(b2).mod(A2);
        BigInteger g = A1.gcd(A2);
        BigInteger diff = r2.subtract(r1);
        if (diff.mod(g).signum() != 0) { System.out.println(0); return; }
        BigInteger mg = A2.divide(g);
        BigInteger t = mg.equals(BigInteger.ONE) ? BigInteger.ZERO
            : diff.divide(g).mod(mg).multiply(A1.divide(g).modInverse(mg)).mod(mg);
        BigInteger M = A1.divide(g).multiply(A2);
        long x0 = r1.add(A1.multiply(t)).mod(M).longValue();
        long m = M.longValue();
        long lo = Math.max(L, Math.max(b1, b2));
        if (lo > R) { System.out.println(0); return; }
        System.out.println(Math.floorDiv(R - x0, m) - Math.floorDiv(lo - 1 - x0, m));
    }
}
```

</details>

<!-- test
in:
2 0 3 3 5 21
out:
3
-->
<!-- test
in:
2 4 3 0 6 17
out:
2
-->
<!-- test
in:
2000000000 -2000000000 1999999999 -2000000000 -2000000000 2000000000
out:
1
-->
<!-- test
in:
4 1 6 2 -100 100
out:
0
-->

### Example 4 — Garner: rebuilding a huge number modulo $10^9+7$  ·  ★ ≈2100 (est.)

- **Source:** Original problem
- **Difficulty:** ≈2100 (est.)
- **Problem:** An unknown integer $0 \le x < \prod_{i=1}^{k} m_i$ is described by $k \le 50$ residues $r_i = x \bmod m_i$, where the $m_i \le 10^9$ are pairwise coprime. Print $x \bmod (10^9+7)$.
- **Thinking from first principles:** $\prod m_i$ has up to 450 digits, so the CRT sum cannot be formed in 64-bit arithmetic (it would need big integers and $O(k^2)$ big operations anyway). Garner's mixed radix (§1.4) only ever works modulo some $m_i$ or modulo the output prime, so all numbers stay below $10^9$.

<details><summary>Solution</summary>

Compute $v_i$ for $i = 1..k$ with the prefix product of earlier moduli taken mod $m_i$; then evaluate $\sum v_i \prod_{j<i} m_j$ modulo $10^9+7$. $O(k^2 + k\log)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
ll ext_gcd(ll a, ll b, ll &x, ll &y) {
    if (b == 0) { x = 1; y = 0; return a; }
    ll x1, y1, g = ext_gcd(b, a % b, x1, y1);
    x = y1; y = x1 - (a / b) * y1;
    return g;
}
ll inv_mod(ll a, ll m) { ll x, y; ext_gcd(a, m, x, y); return ((x % m) + m) % m; }
int main() {
    int k; cin >> k;
    vector<ll> r(k), m(k), v(k);
    for (int i = 0; i < k; i++) cin >> r[i] >> m[i];
    for (int i = 0; i < k; i++) {
        ll cur = 0, prod = 1 % m[i];
        for (int j = 0; j < i; j++) {
            cur = (cur + v[j] % m[i] * prod) % m[i];
            prod = prod * (m[j] % m[i]) % m[i];
        }
        v[i] = ((r[i] - cur) % m[i] + m[i]) % m[i] * inv_mod(prod, m[i]) % m[i];
    }
    const ll Q = 1'000'000'007LL;
    ll x = 0, prod = 1;
    for (int i = 0; i < k; i++) { x = (x + v[i] % Q * prod) % Q; prod = prod * (m[i] % Q) % Q; }
    cout << x << '\n';
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
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StreamTokenizer st = new StreamTokenizer(br);
        st.nextToken(); int k = (int) st.nval;
        long[] r = new long[k], m = new long[k], v = new long[k];
        for (int i = 0; i < k; i++) { st.nextToken(); r[i] = (long) st.nval; st.nextToken(); m[i] = (long) st.nval; }
        for (int i = 0; i < k; i++) {
            long cur = 0, prod = 1 % m[i];
            for (int j = 0; j < i; j++) {
                cur = (cur + v[j] % m[i] * prod) % m[i];
                prod = prod * (m[j] % m[i]) % m[i];
            }
            long inv = Math.floorMod(extGcd(prod, m[i])[1], m[i]);
            v[i] = Math.floorMod(r[i] - cur, m[i]) * inv % m[i];
        }
        final long Q = 1_000_000_007L;
        long x = 0, prod = 1;
        for (int i = 0; i < k; i++) { x = (x + v[i] % Q * prod) % Q; prod = prod * (m[i] % Q) % Q; }
        System.out.println(x);
    }
}
```

(`StreamTokenizer` is safe here because every number is $\le 10^9 < 2^{53}$.)

</details>

<!-- test
in:
3
2 3
3 5
2 7
out:
23
-->
<!-- test
in:
1
0 1
out:
0
-->
<!-- test
in:
4
123456788 999999937
5 999999929
77 1000000000
0 999999893
out:
391014407
-->

### Example 5 — Congruence Equation  ·  ★ 2100

- **Source:** [CF 919E · Congruence Equation](https://codeforces.com/problemset/problem/919/E) — 2100
- **Difficulty:** 2100
- **Problem:** Given a prime $p \le 10^6 + 3$, $1 \le a, b < p$ and $x \le 10^{12}$, count $n \in [1, x]$ with $n\,a^n \equiv b \pmod p$.
- **Thinking from first principles:** $n$ appears twice: as a factor (only $n \bmod p$ matters) and as an exponent (only $n \bmod (p-1)$ matters, by Fermat). These are coprime moduli, so by CRT the pair $(n \bmod p-1,\ n \bmod p)$ is equivalent to $n \bmod p(p-1)$. Fix $i = n \bmod (p-1)$: the equation becomes $n \equiv b\,a^{-i} =: j \pmod p$. So for each of the $p - 1$ choices of $i$ there is exactly one class mod $p(p-1)$ — count its members in $[1, x]$. The CRT here is explicit: $n = i + (p-1)t$ and $p - 1 \equiv -1$ gives $i - t \equiv j$, i.e. $t \equiv i - j \pmod p$.

<details><summary>Solution</summary>

Iterate $i = 0..p-2$, maintaining $a^{-i}$ incrementally. $n_0 = i + (p-1)\bigl((i - j) \bmod p\bigr) \in [0, p(p-1))$. If $n_0 = 0$ use $n_0 = p(p-1)$ (we need $n \ge 1$). The count is $\lfloor (x - n_0)/(p(p-1)) \rfloor + 1$ if $n_0 \le x$. $O(p)$.

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
    ll a, b, p, x;
    cin >> a >> b >> p >> x;
    ll M = p * (p - 1), ainv = power(a, p - 2, p), cur = 1;   // cur = a^{-i}
    ll total = 0;
    for (ll i = 0; i <= p - 2; i++) {
        ll j = b * cur % p;
        ll t = ((i - j) % p + p) % p;
        ll n0 = i + (p - 1) * t;
        if (n0 == 0) n0 = M;
        if (n0 <= x) total += (x - n0) / M + 1;
        cur = cur * ainv % p;
    }
    cout << total << '\n';
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
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        long a = Long.parseLong(st.nextToken()), b = Long.parseLong(st.nextToken());
        long p = Long.parseLong(st.nextToken()), x = Long.parseLong(st.nextToken());
        long M = p * (p - 1), ainv = power(a, p - 2, p), cur = 1, total = 0;
        for (long i = 0; i <= p - 2; i++) {
            long j = b * cur % p;
            long t = Math.floorMod(i - j, p);
            long n0 = i + (p - 1) * t;
            if (n0 == 0) n0 = M;
            if (n0 <= x) total += (x - n0) / M + 1;
            cur = cur * ainv % p;
        }
        System.out.println(total);
    }
}
```

</details>

<!-- test
in:
2 3 5 8
out:
2
-->
<!-- test
in:
4 6 7 13
out:
1
-->
<!-- test
in:
233 233 10007 1
out:
1
-->
<!-- test
in:
1 1 2 1000000000000
out:
500000000000
-->
<!-- test
in:
3 2 7 1000
out:
143
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Normalise residues first**: $b_i$ may be negative or $\ge m_i$ (Example 3). Merge on $((b \bmod m) + m) \bmod m$, but keep the original values for range constraints.
2. **Order the multiplications** in the merge: reduce $\frac{a_2 - a_1}{g}$ mod $\frac{m_2}{g}$ *before* multiplying by the inverse; then $t < m_2/g$ and $m_1 t < \operatorname{lcm}$.
3. **lcm can overflow before you notice**: if the statement does not bound the lcm, either cap it ("once the lcm exceeds the search range, at most one solution remains — check it directly") or use `__int128`/`BigInteger`.
4. **`modInverse` throws** in Java when the modulus is 1 or the number is not invertible — special-case $m_2/g = 1$ (Example 3).
5. **Counting with floor division**: `(R - x0) / M` truncates toward zero for negative numerators; use `floor_div` / `Math.floorDiv`.
6. **"$n \ge 1$" versus residue $0$**: when the class is $0 \bmod M$, the smallest positive member is $M$, not $0$ (Example 5).
7. **Garner needs pairwise coprime moduli.** For a general system, merge with §1.3 instead, or first split the moduli into prime powers.
8. **Inconsistent systems are common in tests** — always check $g \mid a_2 - a_1$ at every merge.

---

## 7. Going further (toward 2400–2600+)

- **Arbitrary-modulus NTT**: three primes $998244353$, $167772161$, $469762049$ and Garner reconstruct each coefficient modulo any $m$ — [FFT/NTT](../15-Advanced-Math/03-fft-and-ntt.md).
- **Binomials modulo composite $m$**: Lucas / prime-power factorial algorithm per prime power + CRT — [binomials](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md).
- **CRT inside data structures**: maintain a value modulo several small moduli in a segment tree to support "divisible by $k$" queries (🧊).
- **CRT + binary search on time** (two periodic sequences with mismatches): [CF 1500B · Two chandeliers](https://codeforces.com/problemset/problem/1500/B) — 2200.
- **Hensel lifting** (🧊): solve $f(x) \equiv 0 \pmod{p^k}$ from a root mod $p$, then glue prime powers with CRT.

---

## 8. Practice ladder

**≤ 1900**
- [ ] [CF 2034A · King Keykhosrow's Mystery](https://codeforces.com/problemset/problem/2034/A) — 800
- [ ] [CF 1266A · Competitive Programmer](https://codeforces.com/problemset/problem/1266/A) — 1000
- [ ] [CF 1342C · Yet Another Counting Problem](https://codeforces.com/problemset/problem/1342/C) — 1600
- [ ] [CF 1770C · Koxia and Number Theory](https://codeforces.com/problemset/problem/1770/C) — 1700
- [ ] [CF 687B · Remainders Game](https://codeforces.com/problemset/problem/687/B) — 1800

**1900–2400**
- [ ] [CF 1665D · GCD Guess](https://codeforces.com/problemset/problem/1665/D) — 2000
- [ ] [CF 1438C · Engineer Artem](https://codeforces.com/problemset/problem/1438/C) — 2000
- [ ] [CF 919E · Congruence Equation](https://codeforces.com/problemset/problem/919/E) — 2100
- [ ] [CF 1748D · ConstructOR ](https://codeforces.com/problemset/problem/1748/D) — 2100
- [ ] [CF 1500B · Two chandeliers](https://codeforces.com/problemset/problem/1500/B) — 2200
- [ ] [CF 1117E · Decypher the String](https://codeforces.com/problemset/problem/1117/E) — 2200

**2400+**
- [ ] [CF 710D · Two Arithmetic Progressions](https://codeforces.com/problemset/problem/710/D) — 2500
- [ ] [CF 906D · Power Tower](https://codeforces.com/problemset/problem/906/D) — 2700
- [ ] [CF 722F · Cyclic Cipher](https://codeforces.com/problemset/problem/722/F) — 2800

**AtCoder**
- [ ] [AtCoder ABC193 E · Oversleeping](https://atcoder.jp/contests/abc193/tasks/abc193_e) — diff≈1948

---

## 9. LeetCode / FAANG cross-reference

Rare in interviews: CRT is almost never asked directly. The closest ideas:

- [LC 878 · Nth Magical Number](https://leetcode.com/problems/nth-magical-number/) — Hard — periodicity with period $\operatorname{lcm}(a, b)$ plus binary search.
- [LC 1201 · Ugly Number III](https://leetcode.com/problems/ugly-number-iii/) — Medium — inclusion–exclusion over lcms of three numbers, binary search on the answer.
- [LC 365 · Water and Jug Problem](https://leetcode.com/problems/water-and-jug-problem/) — Medium — the single-congruence solvability test.

---

## 10. Self-check

1. Solve $6x \equiv 4 \pmod{10}$. How many solutions mod 10?
2. Prove that the CRT solution is unique modulo $M$ for pairwise coprime moduli.
3. When is $x \equiv a_1 \pmod{m_1}$, $x \equiv a_2 \pmod{m_2}$ solvable, and modulo what is the solution unique?
4. Write the merge formula and say why no product exceeds the lcm.
5. Why is $\mathbb{Z}/15 \cong \mathbb{Z}/3 \times \mathbb{Z}/5$ useful for counting solutions of polynomial congruences?
6. Explain Garner's mixed-radix representation and why it avoids big integers.
7. In "Remainders Game", why is checking $k \mid \operatorname{lcm}(c_i)$ equivalent to $\operatorname{lcm}_i\gcd(c_i, k) = k$?
8. How many $n \in [1, 100]$ satisfy $n \equiv 3 \pmod 4$ and $n \equiv 1 \pmod 6$?

<details><summary>Answers</summary>

1. $g = 2 \mid 4$: $3x \equiv 2 \pmod 5$, $x \equiv 4 \pmod 5$. Two solutions mod 10: $4, 9$.
2. Two solutions differ by a multiple of every $m_i$; pairwise coprime ⇒ multiple of $M$.
3. Iff $a_1 \equiv a_2 \pmod{\gcd(m_1, m_2)}$; unique mod $\operatorname{lcm}(m_1, m_2)$.
4. $t = \frac{a_2 - a_1}{g}\bigl(\frac{m_1}{g}\bigr)^{-1} \bmod \frac{m_2}{g}$, $x = a_1 + m_1 t$. Since $t < m_2/g$, $m_1 t < m_1 m_2/g = \operatorname{lcm}$.
5. Roots mod 15 correspond to pairs of roots mod 3 and mod 5, so counts multiply.
6. $x = v_1 + v_2 m_1 + v_3 m_1m_2 + \dots$; $v_i$ is found modulo $m_i$ using only earlier $v$'s, so everything is reduced mod small numbers; the final sum is evaluated mod the target.
7. Per prime $p$: $v_p(k) \le \max_i v_p(c_i)$ iff $v_p(k) = \max_i\min(v_p(c_i), v_p(k))$.
8. $n \equiv 7 \pmod{12}$ ($\gcd(4,6) = 2$ and $3 \equiv 1 \pmod 2$): $7, 19, \dots, 91$ — 8 numbers.

</details>
