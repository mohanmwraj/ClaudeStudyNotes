# Burnside's Lemma and Pólya Enumeration

> **Band:** 🟣 1900 – 🟠 2400 · **Priority:** ⚡ · **FAANG:** none · **Prerequisites:** [Euler's totient](../04-Number-Theory/04-euler-phi-fermat-and-euler-theorem.md), [binomials](01-counting-principles-and-binomials.md), [Möbius](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md)
> **You can say you know this when:** you can prove Burnside's lemma from orbit–stabiliser, derive the necklace formula $\frac1n\sum_{d\mid n}\varphi(d)k^{n/d}$, add reflections for bracelets, and count objects up to an arbitrary small symmetry group by listing its permutations and their cycles.

---

## 1. First principles — why this works

### 1.1 Why "divide by the number of symmetries" fails

Colour the 4 beads of a necklace with 2 colours: $2^4 = 16$ colourings, 4 rotations. If every necklace had exactly 4 distinct rotations the answer would be $16/4 = 4$ — but the true answer is 6 (`0000, 0001, 0011, 0101, 0111, 1111`). The colouring `0101` has only 2 distinct rotations and `0000` has 1: symmetric objects are **under-counted** by the naive division. We need to count orbits, weighting each colouring by how symmetric it is.

### 1.2 Group actions, orbits and stabilisers

A group $G$ of symmetries (rotations, reflections, …) **acts** on a set $X$ of configurations: each $g \in G$ maps $x \mapsto gx$, compatibly with composition. Two configurations are "the same" iff one is mapped to the other by some $g$ — the classes are **orbits**, and we want to count orbits. For a configuration $x$:

- its **orbit** $Gx = \lbrace gx : g \in G\rbrace$;
- its **stabiliser** $G_x = \lbrace g : gx = x\rbrace$ (the symmetries that fix it — a subgroup).

**Orbit–stabiliser theorem:** $\lvert Gx\rvert\cdot\lvert G_x\rvert = \lvert G\rvert$. *Proof.* $gx = hx \iff h^{-1}g \in G_x \iff g \in hG_x$: the elements of $G$ sending $x$ to the same place form exactly one coset of $G_x$. Cosets all have size $\lvert G_x\rvert$, and there is one per orbit point. ∎

### 1.3 Burnside's lemma by double counting

Count the pairs $(g, x)$ with $gx = x$ in two ways. By $g$: $\sum_{g}\lvert\mathrm{Fix}(g)\rvert$. By $x$: $\sum_x\lvert G_x\rvert = \sum_x\frac{\lvert G\rvert}{\lvert Gx\rvert}$. Group the last sum by orbits: each orbit $O$ contributes $\lvert O\rvert\cdot\frac{\lvert G\rvert}{\lvert O\rvert} = \lvert G\rvert$. Hence

$$\#\text{orbits} = \frac{1}{\lvert G\rvert}\sum_{g\in G}\lvert\mathrm{Fix}(g)\rvert .$$

"The number of distinct objects is the **average number of configurations fixed by a symmetry**." For the 4-bead example: identity fixes 16, rotation by 2 fixes 4 (`abab`), rotations by 1 and 3 fix 2 each: $(16 + 2 + 4 + 2)/4 = 6$. ✓

### 1.4 Pólya: fixed colourings are counted by cycles

When $X$ is "colourings of positions with $k$ colours" and $g$ permutes positions, a colouring is fixed by $g$ iff it is constant on every **cycle** of $g$ (the colour must travel around the cycle and come back). So $\lvert\mathrm{Fix}(g)\rvert = k^{c(g)}$ with $c(g)$ the number of cycles:

$$\#\text{distinct colourings} = \frac{1}{\lvert G\rvert}\sum_{g} k^{c(g)} .$$

**Rotations of a necklace.** Rotation by $r$ moves position $i$ to $i + r \bmod n$. The cycle through $0$ is $\lbrace 0, r, 2r, \dots\rbrace$, which has $n/\gcd(r, n)$ elements (the additive order of $r$), and all cycles have that length, so there are $\gcd(r, n)$ cycles. The number of $r \in [0, n)$ with $\gcd(r, n) = d$ is $\varphi(n/d)$ ([totient §1.4](../04-Number-Theory/04-euler-phi-fermat-and-euler-theorem.md)). Therefore

$$N(n, k) = \frac1n\sum_{r=0}^{n-1}k^{\gcd(r,n)} = \frac{1}{n}\sum_{d \mid n}\varphi\!\left(\frac nd\right)k^{d} = \frac1n\sum_{d\mid n}\varphi(d)\,k^{n/d}.$$

**Constraints that are themselves symmetric** (e.g. "adjacent beads differ", "exactly $c_i$ beads of colour $i$") still work: count configurations fixed by $g$ *that satisfy the constraint*. A colouring fixed by rotation with $d$ cycles is periodic with period $d$, so adjacency constraints become constraints on a cycle of length $d$ (Example 4).

---

## 2. Formulas, definitions and identities

| Formula | Meaning / proof sketch |
|---|---|
| $\lvert Gx\rvert\,\lvert G_x\rvert = \lvert G\rvert$ | orbit–stabiliser (§1.2) |
| $\#\text{orbits} = \frac1{\lvert G\rvert}\sum_g\lvert\mathrm{Fix}(g)\rvert$ | Burnside (§1.3) |
| $\lvert\mathrm{Fix}(g)\rvert = k^{c(g)}$ for $k$-colourings | Pólya (§1.4) |
| cycle index $Z_G = \frac1{\lvert G\rvert}\sum_g\prod_i x_i^{c_i(g)}$ ($c_i$ = number of $i$-cycles) | substituting $x_i = k$ gives the count; substituting $x_i = \sum_{\text{colours}} w_c^i$ gives the colour-weighted count (Pólya's theorem) |
| rotation by $r$ on $\mathbb Z_n$: $\gcd(r,n)$ cycles of length $n/\gcd(r,n)$ | §1.4 |
| necklaces $N(n,k) = \frac1n\sum_{d\mid n}\varphi(d)k^{n/d}$ | §1.4 |
| bracelets (rotations + reflections, dihedral group of order $2n$) | $B(n,k) = \frac{N(n,k) + R(n,k)}{2}$, $R = k^{(n+1)/2}$ ($n$ odd), $R = \frac{k^{n/2+1} + k^{n/2}}{2}$ ($n$ even) |
| reflections of an $n$-gon | $n$ odd: every axis passes a vertex and an edge midpoint — $1 + \frac{n-1}2$ cycles; $n$ even: $\frac n2$ axes through two vertices ($\frac n2 + 1$ cycles), $\frac n2$ through two edge midpoints ($\frac n2$ cycles) |
| aperiodic necklaces (Lyndon words) $L(n,k) = \frac1n\sum_{d\mid n}\mu(d)k^{n/d}$ | $k^n = \sum_{d\mid n} d\,L(d,k)$ (every word is a power of a unique primitive word, rotated); Möbius inversion |
| necklaces with exactly $c_1, \dots, c_m$ beads of each colour | $\frac1n\sum_{d \mid \gcd(n, c_1, \dots, c_m)}\varphi(d)\binom{n/d}{c_1/d, \dots, c_m/d}$ |
| proper colourings of a cycle $C_d$ with $k$ colours | $(k-1)^d + (-1)^d(k-1)$ (chromatic polynomial; $d = 1$ gives $0$) |
| necklaces with no two adjacent beads equal | $\frac1n\sum_{d\mid n}\varphi(n/d)\bigl((k-1)^d + (-1)^d(k-1)\bigr)$ |
| $n\times n$ grid up to rotation, $k$ colours | $\frac14\bigl(k^{n^2} + 2k^{\lceil n^2/4\rceil} + k^{\lceil n^2/2\rceil}\bigr)$ |
| square grid up to rotations and reflections ($D_4$, order 8) | add 4 reflections: two diagonal ($k^{(n^2+n)/2}$ each), two axis-parallel ($k^{n\lceil n/2\rceil}$ each); divide by 8 |
| cube faces up to rotation (order 24) | $\frac{1}{24}(k^6 + 3k^4 + 12k^3 + 8k^2)$ |
| complexity | $O(\lvert G\rvert\cdot\text{cost of Fix})$; for necklaces $O(d(n)\log)$ after factoring $n$ |

**Division by $\lvert G\rvert$ modulo $p$** needs $\gcd(\lvert G\rvert, p) = 1$. For $n < p$ this always holds; if $n$ can be a multiple of $p$, compute the sum modulo $p\cdot n$ and divide exactly ([modular arithmetic §2.1](../04-Number-Theory/02-modular-arithmetic-and-inverses.md)).

---

## 3. Implementation (C++ and Java)

```cpp
// Necklaces and bracelets for big n (divisors + phi), and generic Burnside over an explicit permutation group.
const long long MOD = 1'000'000'007LL;
long long power(long long a, long long e) { long long r = 1; a %= MOD; if (a < 0) a += MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
vector<pair<long long, int>> factorize(long long n) {
    vector<pair<long long, int>> f;
    for (long long p = 2; p * p <= n; p++) if (n % p == 0) { int e = 0; while (n % p == 0) { n /= p; e++; } f.push_back({p, e}); }
    if (n > 1) f.push_back({n, 1});
    return f;
}
// all divisors d of n together with phi(d)
vector<pair<long long, long long>> divisors_with_phi(long long n) {
    vector<pair<long long, long long>> ds = {{1, 1}};
    for (auto [p, e] : factorize(n)) {
        int sz = ds.size();
        long long pk = 1;
        for (int k = 1; k <= e; k++) {
            long long phipk = pk * (p - 1);      // phi(p^k) = p^{k-1}(p-1)
            pk *= p;
            for (int i = 0; i < sz; i++) ds.push_back({ds[i].first * pk, ds[i].second * phipk});
        }
    }
    return ds;
}
long long necklaces(long long n, long long k) {        // rotations only, n < MOD
    long long s = 0;
    for (auto [d, ph] : divisors_with_phi(n)) s = (s + ph % MOD * power(k, n / d)) % MOD;
    return s * power(n, MOD - 2) % MOD;
}
long long bracelets(long long n, long long k) {        // rotations + reflections
    long long refl = (n % 2) ? power(k, (n + 1) / 2) : (power(k, n / 2 + 1) + power(k, n / 2)) % MOD * power(2, MOD - 2) % MOD;
    return (necklaces(n, k) + refl) % MOD * power(2, MOD - 2) % MOD;
}
// Burnside over the group generated by `gens` (permutations of 0..m-1); returns (1/|G|) * sum k^{cycles}
long long burnside(const vector<vector<int>> &gens, long long k) {
    int m = gens[0].size();
    vector<int> id(m); iota(id.begin(), id.end(), 0);
    set<vector<int>> G = {id};
    vector<vector<int>> todo = {id};
    while (!todo.empty()) {                              // closure under composition (BFS)
        auto g = todo.back(); todo.pop_back();
        for (auto &h : gens) {
            vector<int> gh(m);
            for (int i = 0; i < m; i++) gh[i] = h[g[i]];
            if (G.insert(gh).second) todo.push_back(gh);
        }
    }
    long long s = 0;
    for (auto &g : G) {
        vector<bool> seen(m, false); int cyc = 0;
        for (int i = 0; i < m; i++) if (!seen[i]) { cyc++; for (int j = i; !seen[j]; j = g[j]) seen[j] = true; }
        s = (s + power(k, cyc)) % MOD;
    }
    return s * power((long long)G.size(), MOD - 2) % MOD;
}
```

```java
// Necklaces and bracelets for big n (divisors + phi), and generic Burnside over an explicit permutation group.
static final long MOD = 1_000_000_007L;
static long power(long a, long e) { long r = 1; a %= MOD; if (a < 0) a += MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
static List<long[]> divisorsWithPhi(long n) {           // {d, phi(d)}
    List<long[]> ds = new ArrayList<>(); ds.add(new long[]{1, 1});
    long m = n;
    for (long p = 2; p * p <= m; p++) {
        if (m % p != 0) continue;
        int e = 0; while (m % p == 0) { m /= p; e++; }
        addPrime(ds, p, e);
    }
    if (m > 1) addPrime(ds, m, 1);
    return ds;
}
static void addPrime(List<long[]> ds, long p, int e) {
    int sz = ds.size(); long pk = 1;
    for (int k = 1; k <= e; k++) {
        long phipk = pk * (p - 1); pk *= p;
        for (int i = 0; i < sz; i++) ds.add(new long[]{ds.get(i)[0] * pk, ds.get(i)[1] * phipk});
    }
}
static long necklaces(long n, long k) {
    long s = 0;
    for (long[] d : divisorsWithPhi(n)) s = (s + d[1] % MOD * power(k, n / d[0])) % MOD;
    return s * power(n, MOD - 2) % MOD;
}
static long bracelets(long n, long k) {
    long refl = (n % 2 == 1) ? power(k, (n + 1) / 2) : (power(k, n / 2 + 1) + power(k, n / 2)) % MOD * power(2, MOD - 2) % MOD;
    return (necklaces(n, k) + refl) % MOD * power(2, MOD - 2) % MOD;
}
static long burnside(int[][] gens, long k) {
    int m = gens[0].length;
    int[] id = new int[m]; for (int i = 0; i < m; i++) id[i] = i;
    Set<String> seenKeys = new HashSet<>(); List<int[]> G = new ArrayList<>();
    Deque<int[]> todo = new ArrayDeque<>();
    seenKeys.add(Arrays.toString(id)); G.add(id); todo.add(id);
    while (!todo.isEmpty()) {
        int[] g = todo.poll();
        for (int[] h : gens) {
            int[] gh = new int[m];
            for (int i = 0; i < m; i++) gh[i] = h[g[i]];
            if (seenKeys.add(Arrays.toString(gh))) { G.add(gh); todo.add(gh); }
        }
    }
    long s = 0;
    for (int[] g : G) {
        boolean[] seen = new boolean[m]; int cyc = 0;
        for (int i = 0; i < m; i++) if (!seen[i]) { cyc++; for (int j = i; !seen[j]; j = g[j]) seen[j] = true; }
        s = (s + power(k, cyc)) % MOD;
    }
    return s * power(G.size(), MOD - 2) % MOD;
}
```

---

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "up to rotation", "necklace", "circular arrangement of colours", "considered the same if one can be rotated into the other" | Burnside with the cyclic group |
| "… or flipped", "bracelet", "turned over" | dihedral group |
| colourings of a grid/cube/polyhedron "up to symmetry" | list the symmetry group's permutations, count cycles |
| "distinct strings up to cyclic shift" with a constraint | Burnside; restrict the fixed-point count to valid configurations (Example 4) |
| "primitive"/"aperiodic" words, Lyndon words | Möbius over divisors |
| answer is a sum over $d \mid n$ of $\varphi(\cdot)k^{\cdot}$ | the necklace formula is hiding inside |

Do not apply Burnside when the objects are **labelled** (people at a round table are distinct: just $(n-1)!$) — the overcount is uniform there.

---

## 5. Worked examples (graded)

### Example 1 — Counting Necklaces  ·  ★ ≈1900 (est.)

- **Source:** [CSES 2209 · Counting Necklaces](https://cses.fi/problemset/task/2209)
- **Difficulty:** ≈1900 (est.)
- **Problem:** Count necklaces of $n$ pearls with $m$ colours up to rotation ($n, m \le 10^6$), modulo $10^9+7$.
- **Thinking from first principles:** Group = the $n$ rotations. Rotation by $r$ fixes $m^{\gcd(r,n)}$ colourings (§1.4). Average them: $\frac1n\sum_{r=0}^{n-1}m^{\gcd(r,n)}$. With $n \le 10^6$ the direct sum (one gcd and one power per $r$) is fine; for $n \le 10^{18}$ use the divisor form.

<details><summary>Solution</summary>

Precompute $m^0..m^n$ to avoid $n$ fast powers. $O(n\log n)$ for the gcds.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 1'000'000'007LL;
long long power(long long a, long long e) { long long r = 1; a %= MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
int main() {
    long long n, m; cin >> n >> m;
    vector<long long> pw(n + 1); pw[0] = 1;
    for (int i = 1; i <= n; i++) pw[i] = pw[i - 1] * (m % MOD) % MOD;
    long long s = 0;
    for (long long r = 0; r < n; r++) s = (s + pw[gcd(r, n)]) % MOD;
    cout << s * power(n, MOD - 2) % MOD << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long power(long a, long e) { long r = 1; a %= MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
    static long gcd(long a, long b) { while (b != 0) { long t = a % b; a = b; b = t; } return a; }
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        int n = Integer.parseInt(st.nextToken()); long m = Long.parseLong(st.nextToken());
        long[] pw = new long[n + 1]; pw[0] = 1;
        for (int i = 1; i <= n; i++) pw[i] = pw[i - 1] * (m % MOD) % MOD;
        long s = 0;
        for (int r = 0; r < n; r++) s = (s + pw[(int) gcd(r, n)]) % MOD;
        System.out.println(s * power(n, MOD - 2) % MOD);
    }
}
```

</details>

<!-- test
in:
4 3
out:
24
-->
<!-- test
in:
4 2
out:
6
-->
<!-- test
in:
1 1000000
out:
1000000
-->
<!-- test
in:
1000000 1000000
out:
905621449
-->

### Example 2 — Counting Grids  ·  ★ ≈1900 (est.)

- **Source:** [CSES 2210 · Counting Grids](https://cses.fi/problemset/task/2210)
- **Difficulty:** ≈1900 (est.)
- **Problem:** Count $n\times n$ black/white grids up to rotation ($n \le 10^9$), modulo $10^9+7$.
- **Thinking from first principles:** Four rotations. Identity: $2^{n^2}$. Rotation by $180°$ pairs each cell with its opposite (the centre is alone if $n$ is odd): $\lceil n^2/2\rceil$ cycles. Rotations by $90°$/$270°$ group cells in 4-cycles (centre alone for odd $n$): $\lceil n^2/4\rceil$ cycles. Burnside: $\frac14\bigl(2^{n^2} + 2\cdot2^{\lceil n^2/4\rceil} + 2^{\lceil n^2/2\rceil}\bigr)$.

<details><summary>Solution</summary>

$n^2 \le 10^{18}$ fits in 64-bit; fast power handles the exponents directly. $O(\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 1'000'000'007LL;
long long power(long long a, unsigned long long e) { long long r = 1; a %= MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
int main() {
    unsigned long long n; cin >> n;
    unsigned long long sq = n * n;
    long long s = (power(2, sq) + 2 * power(2, (sq + 3) / 4) + power(2, (sq + 1) / 2)) % MOD;
    cout << s * power(4, MOD - 2) % MOD << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long power(long a, long e) { long r = 1; a %= MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
    public static void main(String[] args) throws IOException {
        long n = Long.parseLong(new BufferedReader(new InputStreamReader(System.in)).readLine().trim());
        long sq = n * n;                                 // <= 1e18
        long s = (power(2, sq) + 2 * power(2, (sq + 3) / 4) + power(2, (sq + 1) / 2)) % MOD;
        System.out.println(s * power(4, MOD - 2) % MOD);
    }
}
```

</details>

<!-- test
in:
4
out:
16456
-->
<!-- test
in:
1
out:
2
-->
<!-- test
in:
3
out:
140
-->
<!-- test
in:
1000000000
out:
179934857
-->

### Example 3 — Bracelets (rotations and reflections)  ·  ★ ≈2100 (est.)

- **Source:** Original problem
- **Difficulty:** ≈2100 (est.)
- **Problem:** Count bracelets of $n$ beads with $k$ colours up to rotation **and** reflection ($1 \le n, k \le 10^9$), modulo $10^9+7$.
- **Thinking from first principles:** The group has $2n$ elements: $n$ rotations (sum $= nN(n,k)$ via divisors, since $n$ is too large to loop over $r$) and $n$ reflections whose cycle counts depend on the parity of $n$ (§2). Average: $\frac{1}{2n}\bigl(nN(n,k) + \sum_{\text{refl}}k^{c}\bigr) = \frac{N + R}{2}$.

<details><summary>Solution</summary>

Factor $n$ by trial division, enumerate divisors with $\varphi$, then the formulas. $O(\sqrt n + d(n)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007LL;
ll power(ll a, ll e) { ll r = 1; a %= MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
int main() {
    ll n, k; cin >> n >> k;
    vector<pair<ll, ll>> ds = {{1, 1}};                 // (d, phi(d))
    ll m = n;
    auto addPrime = [&](ll p, int e) {
        int sz = ds.size(); ll pk = 1;
        for (int t = 1; t <= e; t++) { ll ph = pk * (p - 1); pk *= p; for (int i = 0; i < sz; i++) ds.push_back({ds[i].first * pk, ds[i].second * ph}); }
    };
    for (ll p = 2; p * p <= m; p++) if (m % p == 0) { int e = 0; while (m % p == 0) { m /= p; e++; } addPrime(p, e); }
    if (m > 1) addPrime(m, 1);
    ll rot = 0;
    for (auto [d, ph] : ds) rot = (rot + ph % MOD * power(k, n / d)) % MOD;
    ll neck = rot * power(n, MOD - 2) % MOD, inv2 = power(2, MOD - 2);
    ll refl = (n % 2) ? power(k, (n + 1) / 2) : (power(k, n / 2 + 1) + power(k, n / 2)) % MOD * inv2 % MOD;
    cout << (neck + refl) % MOD * inv2 % MOD << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long power(long a, long e) { long r = 1; a %= MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
    static List<long[]> ds = new ArrayList<>();
    static void addPrime(long p, int e) {
        int sz = ds.size(); long pk = 1;
        for (int t = 1; t <= e; t++) { long ph = pk * (p - 1); pk *= p; for (int i = 0; i < sz; i++) ds.add(new long[]{ds.get(i)[0] * pk, ds.get(i)[1] * ph}); }
    }
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        long n = Long.parseLong(st.nextToken()), k = Long.parseLong(st.nextToken());
        ds.add(new long[]{1, 1});
        long m = n;
        for (long p = 2; p * p <= m; p++) if (m % p == 0) { int e = 0; while (m % p == 0) { m /= p; e++; } addPrime(p, e); }
        if (m > 1) addPrime(m, 1);
        long rot = 0;
        for (long[] d : ds) rot = (rot + d[1] % MOD * power(k, n / d[0])) % MOD;
        long neck = rot * power(n, MOD - 2) % MOD, inv2 = power(2, MOD - 2);
        long refl = (n % 2 == 1) ? power(k, (n + 1) / 2) : (power(k, n / 2 + 1) + power(k, n / 2)) % MOD * inv2 % MOD;
        System.out.println((neck + refl) % MOD * inv2 % MOD);
    }
}
```

</details>

<!-- test
in:
4 2
out:
6
-->
<!-- test
in:
6 2
out:
13
-->
<!-- test
in:
5 3
out:
39
-->
<!-- test
in:
1 7
out:
7
-->
<!-- test
in:
1000000000 1000000000
out:
638747898
-->

### Example 4 — Necklaces with no two equal neighbours  ·  ★ ≈2200 (est.)

- **Source:** Original problem
- **Difficulty:** ≈2200 (est.)
- **Problem:** Count necklaces of $n$ beads ($n \le 10^9$) with $k \le 10^9$ colours, up to rotation, such that adjacent beads (including bead $n$ and bead $1$) have different colours. Modulo $10^9+7$.
- **Thinking from first principles:** The constraint is rotation-invariant, so Burnside applies to the set of *valid* colourings. A colouring fixed by a rotation with $d = \gcd(r, n)$ cycles is periodic with period $d$; it is valid iff its first $d$ beads form a proper colouring of a **cycle of length $d$** (bead $d$ is adjacent to bead $d + 1$, which equals bead $1$). Proper colourings of $C_d$: $(k-1)^d + (-1)^d(k-1)$ (choose colours around the cycle; this is the chromatic polynomial of a cycle, and it correctly gives $0$ for $d = 1$). So the answer is $\frac1n\sum_{d\mid n}\varphi(n/d)\bigl((k-1)^d + (-1)^d(k-1)\bigr)$.

<details><summary>Solution</summary>

Same divisor enumeration as Example 3, indexing $\varphi$ by $n/d$. $O(\sqrt n + d(n)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007LL;
ll power(ll a, ll e) { ll r = 1; a %= MOD; if (a < 0) a += MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
int main() {
    ll n, k; cin >> n >> k;
    vector<pair<ll, ll>> ds = {{1, 1}};
    ll m = n;
    auto addPrime = [&](ll p, int e) {
        int sz = ds.size(); ll pk = 1;
        for (int t = 1; t <= e; t++) { ll ph = pk * (p - 1); pk *= p; for (int i = 0; i < sz; i++) ds.push_back({ds[i].first * pk, ds[i].second * ph}); }
    };
    for (ll p = 2; p * p <= m; p++) if (m % p == 0) { int e = 0; while (m % p == 0) { m /= p; e++; } addPrime(p, e); }
    if (m > 1) addPrime(m, 1);
    ll s = 0;
    for (auto [e, ph] : ds) {                         // e runs over divisors; cycle length d = n / e, phi(n/d) = phi(e)
        ll d = n / e;
        ll proper = (power(k - 1, d) + (d % 2 ? MOD - (k - 1) % MOD : (k - 1) % MOD)) % MOD;
        s = (s + ph % MOD * proper) % MOD;
    }
    cout << s * power(n, MOD - 2) % MOD << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long power(long a, long e) { long r = 1; a %= MOD; if (a < 0) a += MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
    static List<long[]> ds = new ArrayList<>();
    static void addPrime(long p, int e) {
        int sz = ds.size(); long pk = 1;
        for (int t = 1; t <= e; t++) { long ph = pk * (p - 1); pk *= p; for (int i = 0; i < sz; i++) ds.add(new long[]{ds.get(i)[0] * pk, ds.get(i)[1] * ph}); }
    }
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        long n = Long.parseLong(st.nextToken()), k = Long.parseLong(st.nextToken());
        ds.add(new long[]{1, 1});
        long m = n;
        for (long p = 2; p * p <= m; p++) if (m % p == 0) { int e = 0; while (m % p == 0) { m /= p; e++; } addPrime(p, e); }
        if (m > 1) addPrime(m, 1);
        long s = 0;
        for (long[] q : ds) {
            long d = n / q[0];
            long km1 = (k - 1) % MOD;
            long proper = (power(k - 1, d) + (d % 2 == 1 ? MOD - km1 : km1)) % MOD;
            s = (s + q[1] % MOD * proper) % MOD;
        }
        System.out.println(s * power(n, MOD - 2) % MOD);
    }
}
```

</details>

<!-- test
in:
3 3
out:
2
-->
<!-- test
in:
4 2
out:
1
-->
<!-- test
in:
1 5
out:
0
-->
<!-- test
in:
6 3
out:
14
-->
<!-- test
in:
999999999 1000000000
out:
10607013
-->

### Example 5 — Colouring the faces of a cube (explicit group)  ·  ★ ≈2000 (est.)

- **Source:** Original problem
- **Difficulty:** ≈2000 (est.)
- **Problem:** Given $k \le 10^9$, count colourings of the 6 faces of a cube with $k$ colours up to rotation of the cube, modulo $10^9+7$.
- **Thinking from first principles:** Instead of classifying the 24 rotations by hand (identity; $6$ quarter-turns about face axes with 3 cycles; $3$ half-turns about face axes with 4 cycles; $8$ turns about vertex axes with 2 cycles; $6$ half-turns about edge axes with 3 cycles), let the computer do it: write two generating rotations as permutations of the faces, close under composition (the group has 24 elements), and count the cycles of each element. This works for any small symmetry group — polyhedra, grids with reflections, graph automorphisms.

<details><summary>Solution</summary>

Faces: 0 = up, 1 = down, 2 = front, 3 = back, 4 = left, 5 = right. A quarter turn about the vertical axis cycles front → right → back → left; a quarter turn about the left–right axis cycles up → front → down → back. Closure gives 24 permutations; Burnside $\frac1{24}\sum k^{c(g)}$, which equals $\frac1{24}(k^6 + 3k^4 + 12k^3 + 8k^2)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 1'000'000'007LL;
long long power(long long a, long long e) { long long r = 1; a %= MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
int main() {
    long long k; cin >> k;
    vector<int> rz = {0, 1, 5, 4, 2, 3};               // face i moves to rz[i]: front->right->back->left->front
    vector<int> rx = {2, 3, 1, 0, 4, 5};               // up->front->down->back->up
    vector<int> id = {0, 1, 2, 3, 4, 5};
    set<vector<int>> G = {id};
    vector<vector<int>> todo = {id};
    while (!todo.empty()) {
        auto g = todo.back(); todo.pop_back();
        for (auto &h : {rz, rx}) {
            vector<int> gh(6);
            for (int i = 0; i < 6; i++) gh[i] = h[g[i]];
            if (G.insert(gh).second) todo.push_back(gh);
        }
    }
    long long s = 0;
    for (auto &g : G) {
        vector<bool> seen(6, false); int c = 0;
        for (int i = 0; i < 6; i++) if (!seen[i]) { c++; for (int j = i; !seen[j]; j = g[j]) seen[j] = true; }
        s = (s + power(k, c)) % MOD;
    }
    cout << G.size() << ' ' << s * power((long long)G.size(), MOD - 2) % MOD << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long power(long a, long e) { long r = 1; a %= MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
    public static void main(String[] args) throws IOException {
        long k = Long.parseLong(new BufferedReader(new InputStreamReader(System.in)).readLine().trim());
        int[][] gens = {{0, 1, 5, 4, 2, 3}, {2, 3, 1, 0, 4, 5}};
        int[] id = {0, 1, 2, 3, 4, 5};
        Set<String> keys = new HashSet<>(); List<int[]> G = new ArrayList<>(); Deque<int[]> todo = new ArrayDeque<>();
        keys.add(Arrays.toString(id)); G.add(id); todo.add(id);
        while (!todo.isEmpty()) {
            int[] g = todo.poll();
            for (int[] h : gens) {
                int[] gh = new int[6];
                for (int i = 0; i < 6; i++) gh[i] = h[g[i]];
                if (keys.add(Arrays.toString(gh))) { G.add(gh); todo.add(gh); }
            }
        }
        long s = 0;
        for (int[] g : G) {
            boolean[] seen = new boolean[6]; int c = 0;
            for (int i = 0; i < 6; i++) if (!seen[i]) { c++; for (int j = i; !seen[j]; j = g[j]) seen[j] = true; }
            s = (s + power(k, c)) % MOD;
        }
        System.out.println(G.size() + " " + s * power(G.size(), MOD - 2) % MOD);
    }
}
```

</details>

<!-- test
in:
1
out:
24 1
-->
<!-- test
in:
2
out:
24 10
-->
<!-- test
in:
3
out:
24 57
-->
<!-- test
in:
1000000000
out:
24 5047
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Average, don't divide the total**: the answer is $\frac{1}{\lvert G\rvert}\sum_g\lvert\mathrm{Fix}(g)\rvert$, and the sum is always a multiple of $\lvert G\rvert$ — a good self-check when computing exactly.
2. **Identify the group exactly**: rotations only ($n$ elements) versus rotations + reflections ($2n$). Re-read "can be flipped".
3. **Reflections for even $n$** come in two types (through vertices / through edges) with different cycle counts — the most common bracelet bug.
4. **Large $n$**: never loop over $r = 0..n-1$; sum over divisors with $\varphi$.
5. **Modular division by $\lvert G\rvert$** requires $\gcd(\lvert G\rvert, p) = 1$; with $n$ possibly divisible by $p$, compute modulo $pn$.
6. **$k^{c}$ with $k \ge p$**: reduce $k$ mod $p$ first (`power` does); exponents are actual cycle counts, never reduce them mod $p$ (mod $p - 1$ is fine if $p \nmid k$).
7. **Constraints must be invariant under the group**; e.g. "bead 1 is red" breaks rotational symmetry — then there is nothing to divide.
8. **Composition order** when generating a group from permutations does not matter for the final set (a group is closed both ways), but be consistent when applying a permutation to positions vs colours.

---

## 7. Going further (toward 2400–2600+)

- **Pólya with weights**: necklaces with prescribed colour counts, or generating functions by number of beads of each colour — substitute power sums into the cycle index ([GFs](../15-Advanced-Math/04-polynomials-and-generating-functions.md)).
- **Burnside on graphs**: counting unlabelled graphs or trees up to isomorphism (cycle index of $S_n$ acting on pairs) — exponential, but small $n$ appears in hard problems.
- **Burnside + DP**: when $\lvert\mathrm{Fix}(g)\rvert$ itself needs a DP (e.g. colourings with forbidden adjacent pairs given by a matrix: $\operatorname{tr}(A^d)$ via [matrix power](../07-DP-Optimizations/08-matrix-exponentiation-for-dp.md)).
- **Lyndon words and de Bruijn sequences**: the Duval algorithm generates Lyndon factorisations in linear time — [strings](../11-Strings/README.md).

---

## 8. Practice ladder

- [ ] [CSES 2209 · Counting Necklaces](https://cses.fi/problemset/task/2209)
- [ ] [CSES 2210 · Counting Grids](https://cses.fi/problemset/task/2210)
- [ ] [CF 1367E · Necklace Assembly](https://codeforces.com/problemset/problem/1367/E) — 1900
- [ ] [CF 1327D · Infinite Path](https://codeforces.com/problemset/problem/1327/D) — 2200
- [ ] [AtCoder ABC428 G · Necklace](https://atcoder.jp/contests/abc428/tasks/abc428_g) — diff≈2472
- [ ] [AtCoder ABC252 Ex · K-th beautiful Necklace](https://atcoder.jp/contests/abc252/tasks/abc252_h) — diff≈3015

(Pure Burnside problems are rarer on Codeforces than on other judges; the cycle-structure reasoning of §1.4 appears far more often — permutation cycles, rotations of arrays, periodic strings.)

---

## 9. LeetCode / FAANG cross-reference

Rare in interviews — symmetry-reduced counting does not appear in standard FAANG question banks. The underlying "rotation by $r$ splits into $\gcd(r, n)$ cycles" fact does: [LC 189 · Rotate Array](https://leetcode.com/problems/rotate-array/) — Medium — the in-place cyclic-replacement solution walks exactly $\gcd(k, n)$ cycles.

---

## 10. Self-check

1. Prove orbit–stabiliser and use it to prove Burnside's lemma.
2. Why does rotation by $r$ on $n$ beads have $\gcd(r, n)$ cycles?
3. Compute the number of 6-bead necklaces with 2 colours.
4. Add reflections: how many 6-bead bracelets with 2 colours?
5. Count the cycles of the four rotations of a $3\times3$ grid.
6. Why is the number of proper colourings of $C_1$ equal to $0$, and why does that matter in Example 4?
7. Derive the Lyndon-word formula from $k^n = \sum_{d \mid n} dL(d,k)$.
8. What goes wrong if you count "round-table seatings of $n$ distinct people" with Burnside?

<details><summary>Answers</summary>

1. Elements sending $x$ to a given orbit point form a coset of $G_x$, so $\lvert G\rvert = \lvert Gx\rvert\lvert G_x\rvert$. Double count fixed pairs: $\sum_g\lvert\mathrm{Fix}(g)\rvert = \sum_x\lvert G_x\rvert = \sum_x\lvert G\rvert/\lvert Gx\rvert = \lvert G\rvert\cdot\#\text{orbits}$.
2. The cycle of position $0$ is the subgroup generated by $r$ in $\mathbb Z_n$, of size $n/\gcd(r, n)$; all cycles are cosets of it.
3. $\frac16(2^6 + 2^1 + 2^2 + 2^3 + 2^2 + 2^1) = \frac{84}{6} = 14$.
4. $R = \frac{2^4 + 2^3}{2} = 12$; $\frac{14 + 12}{2} = 13$.
5. Identity 9; $90°$ and $270°$: 3 each (two 4-cycles + centre); $180°$: 5 (four 2-cycles + centre).
6. A single bead is adjacent to itself; a fixed colouring under a rotation with one cycle is constant, which violates the constraint. The chromatic formula gives $0$ automatically.
7. Every word of length $n$ is a rotation of a primitive word of length $d \mid n$ repeated; a primitive necklace of length $d$ has $d$ distinct rotations. Möbius inversion gives $nL(n,k) = \sum_{d\mid n}\mu(d)k^{n/d}$.
8. Nothing is symmetric — every seating has $n$ distinct rotations — so Burnside gives $n!/n = (n-1)!$, the same as plain division; the machinery is unnecessary but not wrong.

</details>
