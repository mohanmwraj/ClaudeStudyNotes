# Bitmask DP

> **Band:** 🔵→🟠 1600–2400 · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [DP first principles](01-dp-first-principles-and-state-design.md), [bit manipulation](../01-Foundations/03-bit-manipulation.md)
> **You can say you know this when:** you can explain why "the set of used items plus the current item" collapses $n!$ orders into $n 2^n$ states; you write Held–Karp, assignment-by-popcount and submask DP from memory; you can prove the $3^n$ bound; you use a canonical element (lowest bit) to avoid double counting; and you know when the mask should encode something other than "items used" (parities of prime exponents, a window of recent choices, a frontier).

When the future depends on *which* items have been used — not just how many — and $n \le 20$, the state contains a subset, stored as the bits of an integer. The win over brute force is that the **order** of past choices is forgotten: $n!$ permutations collapse to $2^n$ subsets.

---

## 1. First principles — why this works

### 1.1 From permutations to subsets

Brute force over orders of $n$ items is $n!$ ($20! \approx 2.4\cdot10^{18}$). Ask the usual question: after placing some items, what does the future need? For the travelling salesman problem (visit every city once, minimise total distance), the cost of the rest of the tour depends on **which cities remain** and **where we stand** — not on the order in which the visited ones were visited. Two partial tours with the same visited set and the same last city are equivalent; keep the cheaper. That gives the Held–Karp state $(\text{mask}, v)$:

$$f(\text{mask}, v) = \min_{u \in \text{mask}\setminus\{v\}} f(\text{mask}\setminus\{v\}, u) + d(u, v), \qquad f(\{s\}, s) = 0.$$

$2^n n$ states, $n$ transitions each: $O(2^n n^2)$ — $4\cdot10^8$ for $n=20$, about $1.7\cdot 10^7$ for $n = 16$. Exponential still, but $20!$ vs $2^{20}\cdot 400$ is the difference between impossible and one second.

**Evaluation order:** removing a bit makes the integer smaller, so iterating masks in increasing numeric order processes every submask first.

### 1.2 Implicit dimensions — the popcount trick

In assignment problems ("match $n$ men to $n$ women", "assign $n$ jobs to $n$ workers") we decide men in order $0, 1, \dots$. After deciding $k$ men, the set of used women has exactly $k$ elements — so **the man index is $\text{popcount}(\text{mask})$** and need not be stored:

$$g(\text{mask}) = \sum_{w \in \text{mask},\ \text{compatible}(|\text{mask}|-1,\, w)} g(\text{mask} \setminus \{w\}),\qquad g(\emptyset) = 1.$$

$O(2^n n)$ instead of $O(2^n n^2)$ (AtCoder DP O). Always ask whether a dimension is determined by the others ([first principles](01-dp-first-principles-and-state-design.md) §1.7).

### 1.3 Submask enumeration and the $3^n$ bound

Partition-type problems ("split the set into groups", "cover the set with blocks") need transitions from a mask to its **submasks**:

$$f(\text{mask}) = \operatorname{opt}_{\emptyset \ne s \subseteq \text{mask}} \big(\text{cost}(s) \oplus f(\text{mask} \setminus s)\big).$$

The loop `for (s = mask; s; s = (s - 1) & mask)` visits every non-empty submask of `mask` in decreasing order: subtracting 1 clears the lowest set bit and sets all lower bits; `& mask` keeps only bits of `mask` — it is "decrement in the number system whose digits are the bits of mask".

**Total work over all masks is $3^n$.** Each element is, for a pair $(s \subseteq \text{mask})$, in exactly one of three situations: outside mask, in mask but not in $s$, in $s$. So the number of pairs is $3^n$; equivalently $\sum_k \binom{n}{k} 2^k = (1+2)^n$. For $n = 16$: $4.3\cdot10^7$; $n=18$: $3.9\cdot10^8$ (tight).

**Counting partitions needs a canonical block.** In an optimisation it doesn't matter that the partition $\{A, B\}$ is generated twice (first $A$ then $B$, or first $B$ then $A$). For *counting*, force the chosen block $s$ to contain the **lowest set bit** of mask: then each unordered partition is produced exactly once. (It also halves the work in optimisation problems.)

### 1.4 Compound DP values

Sometimes the right DP value is not a number but a pair compared lexicographically. **Elevator rides** (CSES 1653): people with weights $w_i$, an elevator with capacity $x$; minimise the number of rides. Process people in some order; the state after placing a set of people is (rides used, weight in the current ride). For a fixed mask, fewer rides is always at least as good (we can always start a new ride), and with equal rides, a lighter current ride dominates. So $f(\text{mask}) = $ lexicographically smallest pair, and

$$f(\text{mask}) = \min_{i\in\text{mask}} \text{add}\big(f(\text{mask}\setminus\{i\}), w_i\big), \quad \text{add}((r, \ell), w) = \begin{cases}(r, \ell+w) & \ell + w \le x\\ (r+1, w) & \text{otherwise.}\end{cases}$$

$O(2^n n)$ instead of $O(3^n)$ for the "partition into feasible blocks" formulation. A dominance argument ("this pair is never worse than that one") is what licenses keeping a single pair per mask.

### 1.5 Canonical starting points — counting cycles

To count simple cycles of a graph ($n \le 19$, CF 11D), count paths that **start at the lowest-numbered vertex of their vertex set**, visit exactly the set, and end at a neighbour of the start. $h(\text{mask}, v)$ = number of such paths from $\text{low}(\text{mask})$ to $v$. Every cycle of length $\ge 3$ is counted exactly twice (two directions) — divide by 2. Without the canonical start, each cycle would be counted $2\ell$ times for length $\ell$, which can be fixed too, but the canonical start also prunes work (only extend to vertices larger than the start).

### 1.6 The mask does not have to be "items used"

The mask is just a compact encoding of whatever finite information the future needs:

- **Parities**: "the product of a chosen subset is a perfect square" (CF 895C) — the mask stores the parity of the exponent of each of the 19 primes below 70; the DP over values multiplies by 2 for each extra copy.
- **A window of recent decisions**: "no two chosen positions within distance $k$" — the mask holds the last $k$ decisions (a sliding window of bits).
- **A frontier**: in tilings, the mask is the set of cells of the next column already covered ([broken profile DP](11-broken-profile-dp.md)).
- **Which constraints are satisfied**: "the team must cover all $m \le 16$ skills" (LC 1125) — mask over skills, not over people.
- **Digits used** in [digit DP](07-digit-dp.md) (numbers with distinct digits): a 10-bit mask.

### 1.7 Bit manipulation you need

| Operation | C++ | Java |
|---|---|---|
| is bit $i$ set | `m >> i & 1` | `(m >> i & 1) != 0` |
| set / clear bit | `m \| 1 << i`, `m & ~(1 << i)` | same |
| lowest set bit | `m & -m` | `m & -m` (or `Integer.lowestOneBit`) |
| index of lowest bit | `__builtin_ctz(m)` | `Integer.numberOfTrailingZeros(m)` |
| popcount | `__builtin_popcount(m)` (`ll`: `__builtin_popcountll`) | `Integer.bitCount(m)` / `Long.bitCount` |
| all submasks of `m` | `for (s = m; s; s = (s-1) & m)` | same |
| all supersets of `m` within $n$ bits | `for (s = m; s < 1<<n; s = (s+1) \| m)` | same |
| next mask with the same popcount (Gosper) | `c = m & -m; r = m + c; m = (((r ^ m) >> 2) / c) \| r;` | same |

Gosper's hack enumerates all $k$-subsets in increasing order — useful when only masks of a given size matter.

### 1.8 Related techniques

- **Sum over subsets** (SOS DP): $F(\text{mask}) = \sum_{s\subseteq\text{mask}} f(s)$ for *all* masks in $O(n 2^n)$, not $3^n$ ([SOS DP](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md)).
- **Meet in the middle** for $n \le 40$ when the state would be $2^{40}$ ([meet in the middle](../02-Core-Techniques/06-ternary-search-and-meet-in-the-middle.md)).
- **Subset convolution** $\sum_{s \subseteq m} f(s)g(m\setminus s)$ for all $m$ in $O(n^2 2^n)$ via ranked zeta transforms (🔴).

---

## 2. Formulas, definitions and identities

| Pattern | State | Time | Typical $n$ |
|---|---|---|---|
| assignment / permutation by position | $g(\text{mask})$, position $= \text{popcount}$ | $O(n2^n)$ | $\le 21$ |
| TSP / Hamiltonian path | $f(\text{mask}, v)$ | $O(n^2 2^n)$ | $\le 18$–$20$ |
| set partition / cover by blocks | $f(\text{mask})$ over submasks | $O(3^n)$ | $\le 16$–$17$ |
| bin packing with dominance | $f(\text{mask}) = (\text{bins}, \text{last load})$ | $O(n2^n)$ | $\le 20$ |
| counting simple cycles | $h(\text{mask}, v)$, start $=\text{low}(\text{mask})$ | $O(n^2 2^n)$ | $\le 19$ |
| SOS | $F(\text{mask}) = \sum_{s\subseteq \text{mask}} f(s)$ | $O(n 2^n)$ | $\le 22$ |

$$\sum_{\text{mask}} 2^{|\text{mask}|} = \sum_{k=0}^{n}\binom{n}{k}2^k = 3^n, \qquad \sum_{\text{mask}}|\text{mask}| = n 2^{n-1}.$$

**Precomputing block values in $O(2^n)$ or $O(n 2^n)$:** for an additive per-element value, $\text{val}(m) = \text{val}(m \setminus \text{low}(m)) + v_{\text{ctz}(m)}$; for pairwise sums (Grouping), $\text{score}(m) = \text{score}(m') + \sum_{j \in m'} a_{\ell j}$ with $\ell = \text{low}(m)$, $m' = m \setminus \{\ell\}$.

**Memory:** $2^{20} \cdot 20$ `int` $= 80$ MB; `long long` doubles it. Prefer `int` or `float` when values fit, flatten 2-D tables in Java (`new long[(1<<n)*n]`) to avoid $2^n$ small arrays.

**Speed reference ($\approx 10^8$–$3\cdot10^8$ simple ops/s):** $2^{20}\cdot 20 = 2\cdot10^7$ ✓, $2^{20}\cdot 400 = 4\cdot10^8$ ⚠, $3^{16} = 4.3\cdot10^7$ ✓, $3^{18} = 3.9\cdot 10^8$ ⚠.

---

## 3. Implementation (C++ and Java)

### 3.1 Bit-iteration kernels

```cpp
// Calls f(s) for every non-empty submask s of m, in decreasing order.
template <class F> void forSubmasks(int m, F f) {
    for (int s = m; s > 0; s = (s - 1) & m) f(s);
}

// Calls f(s) for every superset s of m among n-bit masks.
template <class F> void forSupersets(int m, int n, F f) {
    for (int s = m; s < (1 << n); s = (s + 1) | m) f(s);
}

// Calls f(s) for every n-bit mask with exactly k bits set (k >= 1), in increasing order (Gosper's hack).
template <class F> void forKSubsets(int n, int k, F f) {
    for (long long s = (1LL << k) - 1; s < (1LL << n);) {
        f((int)s);
        long long c = s & -s, r = s + c;
        s = (((r ^ s) >> 2) / c) | r;
    }
}
```

```java
static void forSubmasks(int m, java.util.function.IntConsumer f) {
    for (int s = m; s > 0; s = (s - 1) & m) f.accept(s);
}

static void forSupersets(int m, int n, java.util.function.IntConsumer f) {
    for (int s = m; s < (1 << n); s = (s + 1) | m) f.accept(s);
}

static void forKSubsets(int n, int k, java.util.function.IntConsumer f) {
    for (long s = (1L << k) - 1; s < (1L << n);) {
        f.accept((int) s);
        long c = s & -s, r = s + c;
        s = (((r ^ s) >> 2) / c) | r;
    }
}
```

In hot loops, inline these instead of passing lambdas (Java lambdas through `IntConsumer` are fast after JIT, but plain loops are simpler to optimise).

### 3.2 Held–Karp TSP (minimum Hamiltonian cycle)

Input: $n \le 16$ and an $n\times n$ distance matrix. Output: the length of the shortest tour that starts and ends at city 0 and visits every city once ($0$ for $n=1$).

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<vector<long long>> d(n, vector<long long>(n));
    for (auto& row : d) for (auto& x : row) cin >> x;
    const long long INF = LLONG_MAX / 4;
    int full = 1 << n;
    vector<vector<long long>> f(full, vector<long long>(n, INF));   // f[mask][v]: path 0 -> v visiting mask
    f[1][0] = 0;
    for (int mask = 1; mask < full; mask++) {
        if (!(mask & 1)) continue;                                   // every path starts at city 0
        for (int v = 0; v < n; v++) {
            if (!(mask >> v & 1) || f[mask][v] >= INF) continue;
            for (int u = 0; u < n; u++) {
                if (mask >> u & 1) continue;
                int nm = mask | 1 << u;
                f[nm][u] = min(f[nm][u], f[mask][v] + d[v][u]);    // push to an unvisited city
            }
        }
    }
    long long ans = n == 1 ? 0 : INF;
    for (int v = 1; v < n; v++) ans = min(ans, f[full - 1][v] + d[v][0]);
    cout << ans << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c != '-' && (c < '0' || c > '9')) c = IN.read();
        boolean neg = c == '-';
        if (neg) c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nl();
        long[][] d = new long[n][n];
        for (int i = 0; i < n; i++) for (int j = 0; j < n; j++) d[i][j] = nl();
        final long INF = Long.MAX_VALUE / 4;
        int full = 1 << n;
        long[] f = new long[full * n];                 // flattened: f[mask * n + v]
        Arrays.fill(f, INF);
        f[1 * n + 0] = 0;
        for (int mask = 1; mask < full; mask += 2)     // odd masks contain city 0
            for (int v = 0; v < n; v++) {
                long cur = f[mask * n + v];
                if ((mask >> v & 1) == 0 || cur >= INF) continue;
                for (int u = 0; u < n; u++) {
                    if ((mask >> u & 1) != 0) continue;
                    int idx = (mask | 1 << u) * n + u;
                    f[idx] = Math.min(f[idx], cur + d[v][u]);
                }
            }
        long ans = n == 1 ? 0 : INF;
        for (int v = 1; v < n; v++) ans = Math.min(ans, f[(full - 1) * n + v] + d[v][0]);
        System.out.println(ans);
    }
}
```

<!-- test
in:
4
0 2 9 10
1 0 6 4
15 7 0 8
6 3 12 0
out:
21
-->
<!-- test
in:
1
0
out:
0
-->
<!-- test
in:
2
0 3
5 0
out:
8
-->

---

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| $n \le 20$ (sometimes 16–23) and the answer depends on *which* elements are used | bitmask state |
| "visit all", "order of visiting", "shortest route through every …" | $(\text{mask}, \text{last})$ |
| "assign each of $n$ … to a distinct …" | mask of the second side, position = popcount |
| "split into groups", "cover with sets", "schedule into days/bins" | submask DP $O(3^n)$, or a compound value $O(n 2^n)$ |
| $m \le 16$ requirements (skills, colours, primes) | mask over requirements |
| constraint about the last $k \le 10$ choices | sliding-window mask |
| grid with one small side (width $\le 10$) | profile mask ([broken profile](11-broken-profile-dp.md)) |
| "for every mask, aggregate over its submasks/supersets" | SOS DP, not $3^n$ |
| $n \le 40$ | meet in the middle |

Often confused with: **greedy by sorting** — if an exchange argument shows the order is forced (e.g. by deadline), the mask is unnecessary; **graph shortest paths** — Held–Karp *is* Dijkstra/DP on the state graph $(\text{mask}, v)$; when edge costs make the state graph cyclic (revisiting allowed), run Dijkstra/BFS over the same states (LC 847).

---

## 5. Worked examples (graded)

### Example 1 — Matching  ·  ★ ≈1700 (est.)

- **Source:** [AtCoder DP O · Matching](https://atcoder.jp/contests/dp/tasks/dp_o)
- **Difficulty:** ≈1700 (est.)
- **Problem:** $n \le 21$ men and $n$ women, a 0/1 compatibility matrix. Count perfect matchings into compatible pairs, mod $10^9+7$.
- **Thinking from first principles:** Brute force is $n! \approx 5\cdot10^{19}$. Match men in order. After matching men $0..k-1$, the future needs only the set of used women — and $k$ is the size of that set. So $g(\text{mask})$ with the man index implicit. $2^{21}\cdot 21 = 4.4\cdot10^7$ transitions.

<details><summary>Solution</summary>

Push form: from `mask` (men $0..|mask|-1$ matched), man $k = |mask|$ takes any compatible free woman. $O(n 2^n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    const int MOD = 1'000'000'007;
    int n;
    cin >> n;
    vector<int> ok(n, 0);                              // ok[man]: bitmask of compatible women
    for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++) {
            int x;
            cin >> x;
            if (x) ok[i] |= 1 << j;
        }
    vector<int> g(1 << n, 0);
    g[0] = 1;
    for (int mask = 0; mask < (1 << n) - 1; mask++) {
        if (!g[mask]) continue;
        int k = __builtin_popcount(mask);             // the next man to match
        for (int free = ok[k] & ~mask; free; free &= free - 1) {
            int w = __builtin_ctz(free);
            int& t = g[mask | 1 << w];
            t += g[mask];
            if (t >= MOD) t -= MOD;
        }
    }
    cout << g[(1 << n) - 1] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c != '-' && (c < '0' || c > '9')) c = IN.read();
        boolean neg = c == '-';
        if (neg) c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        final int MOD = 1_000_000_007;
        int n = (int) nl();
        int[] ok = new int[n];
        for (int i = 0; i < n; i++)
            for (int j = 0; j < n; j++)
                if (nl() == 1) ok[i] |= 1 << j;
        int[] g = new int[1 << n];
        g[0] = 1;
        for (int mask = 0; mask < (1 << n) - 1; mask++) {
            if (g[mask] == 0) continue;
            int k = Integer.bitCount(mask);
            for (int free = ok[k] & ~mask; free != 0; free &= free - 1) {
                int w = Integer.numberOfTrailingZeros(free);
                int t = g[mask | 1 << w] + g[mask];
                g[mask | 1 << w] = t >= MOD ? t - MOD : t;
            }
        }
        System.out.println(g[(1 << n) - 1]);
    }
}
```

</details>

<!-- test
in:
3
1 1 0
0 1 1
1 0 1
out:
2
-->
<!-- test
in:
1
0
out:
0
-->
<!-- test
in:
4
1 1 1 1
1 1 1 1
1 1 1 1
1 1 1 1
out:
24
-->

### Example 2 — Kefa and Dishes  ·  ★ 1800

- **Source:** [CF 580D · Kefa and Dishes](https://codeforces.com/problemset/problem/580/D) — 1800
- **Difficulty:** 1800
- **Problem:** $n \le 18$ dishes with satisfaction $a_i \le 10^9$; eat exactly $m \le n$ distinct dishes in some order. $k \le n(n-1)$ rules: eating $x$ *immediately* before $y$ adds $c \le 10^9$. Maximise total satisfaction.
- **Thinking from first principles:** The bonus of the next dish depends on the previous dish only; the remaining choices depend on which dishes are used. State $(\text{mask}, \text{last})$, exactly the TSP shape, stopping at $|\text{mask}| = m$. $2^{18}\cdot 18^2 = 8.5\cdot10^7$ transitions. Totals reach $3.6\cdot10^{10}$: 64-bit.

<details><summary>Solution</summary>

$f(\{i\}, i) = a_i$; push $f(\text{mask}\cup\{j\}, j) \leftarrow f(\text{mask}, i) + a_j + c(i,j)$ while $|\text{mask}| < m$. Answer: max over masks with $|\text{mask}| = m$. Unreachable states are $-1$ (all values are non-negative). $O(2^n n^2)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m, k;
    cin >> n >> m >> k;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    vector<vector<long long>> bonus(n, vector<long long>(n, 0));
    for (int i = 0; i < k; i++) {
        int x, y;
        long long c;
        cin >> x >> y >> c;
        bonus[x - 1][y - 1] = c;
    }
    vector<long long> f((1 << n) * n, -1);            // f[mask * n + last]
    for (int i = 0; i < n; i++) f[(1 << i) * n + i] = a[i];
    long long ans = 0;
    for (int mask = 1; mask < (1 << n); mask++) {
        int cnt = __builtin_popcount(mask);
        for (int i = 0; i < n; i++) {
            long long cur = f[mask * n + i];
            if (cur < 0) continue;
            if (cnt == m) { ans = max(ans, cur); continue; }
            for (int j = 0; j < n; j++) {
                if (mask >> j & 1) continue;
                long long& t = f[(mask | 1 << j) * n + j];
                t = max(t, cur + a[j] + bonus[i][j]);
            }
        }
    }
    cout << ans << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c != '-' && (c < '0' || c > '9')) c = IN.read();
        boolean neg = c == '-';
        if (neg) c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nl(), m = (int) nl(), k = (int) nl();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = nl();
        long[][] bonus = new long[n][n];
        for (int i = 0; i < k; i++) {
            int x = (int) nl() - 1, y = (int) nl() - 1;
            bonus[x][y] = nl();
        }
        long[] f = new long[(1 << n) * n];
        Arrays.fill(f, -1);
        for (int i = 0; i < n; i++) f[(1 << i) * n + i] = a[i];
        long ans = 0;
        for (int mask = 1; mask < (1 << n); mask++) {
            int cnt = Integer.bitCount(mask);
            for (int i = 0; i < n; i++) {
                long cur = f[mask * n + i];
                if (cur < 0) continue;
                if (cnt == m) { ans = Math.max(ans, cur); continue; }
                for (int j = 0; j < n; j++) {
                    if ((mask >> j & 1) != 0) continue;
                    int idx = (mask | 1 << j) * n + j;
                    f[idx] = Math.max(f[idx], cur + a[j] + bonus[i][j]);
                }
            }
        }
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
3 2 1
1 1 1
2 1 5
out:
7
-->
<!-- test
in:
4 3 2
5 1 2 4
1 3 10
3 4 7
out:
28
-->
<!-- test
in:
1 1 0
1000000000
out:
1000000000
-->

### Example 3 — Grouping (submask DP)  ·  ★ ≈2000 (est.)

- **Source:** [AtCoder DP U · Grouping](https://atcoder.jp/contests/dp/tasks/dp_u)
- **Difficulty:** ≈2000 (est.)
- **Problem:** $n \le 16$ rabbits, compatibility $a_{ij}$ ($|a_{ij}| \le 10^9$, symmetric, $a_{ii}=0$). Partition the rabbits into groups; the score is the sum of $a_{ij}$ over pairs in the same group. Maximise.
- **Thinking from first principles:** Fix the group containing the lowest-numbered remaining rabbit (canonical, §1.3): $f(\text{mask}) = \max_{s \subseteq \text{mask},\ \text{low}(\text{mask}) \in s} \text{score}(s) + f(\text{mask}\setminus s)$. The $3^{16}/2 \approx 2\cdot10^7$ pairs are fine; precompute $\text{score}$ for all $2^{16}$ subsets incrementally in $O(n 2^n)$, not $O(n^2 2^n)$ — though either passes.

<details><summary>Solution</summary>

$\text{score}(m) = \text{score}(m \setminus \{\ell\}) + \sum_{j \in m\setminus\{\ell\}} a_{\ell j}$, $\ell = \text{low}(m)$. Then the submask DP. $O(3^n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<vector<long long>> a(n, vector<long long>(n));
    for (auto& row : a) for (auto& x : row) cin >> x;
    int full = 1 << n;
    vector<long long> score(full, 0), f(full, 0);
    for (int m = 1; m < full; m++) {
        int l = __builtin_ctz(m);
        int rest = m & (m - 1);
        score[m] = score[rest];
        for (int r = rest; r; r &= r - 1) score[m] += a[l][__builtin_ctz(r)];
    }
    for (int mask = 1; mask < full; mask++) {
        int low = mask & -mask, rest = mask ^ low;
        long long best = LLONG_MIN;
        for (int s = rest;; s = (s - 1) & rest) {     // groups containing the lowest rabbit: low | s
            best = max(best, score[low | s] + f[rest ^ s]);
            if (s == 0) break;
        }
        f[mask] = best;
    }
    cout << f[full - 1] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c != '-' && (c < '0' || c > '9')) c = IN.read();
        boolean neg = c == '-';
        if (neg) c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nl();
        long[][] a = new long[n][n];
        for (int i = 0; i < n; i++) for (int j = 0; j < n; j++) a[i][j] = nl();
        int full = 1 << n;
        long[] score = new long[full], f = new long[full];
        for (int m = 1; m < full; m++) {
            int l = Integer.numberOfTrailingZeros(m);
            int rest = m & (m - 1);
            long s = score[rest];
            for (int r = rest; r != 0; r &= r - 1) s += a[l][Integer.numberOfTrailingZeros(r)];
            score[m] = s;
        }
        for (int mask = 1; mask < full; mask++) {
            int low = mask & -mask, rest = mask ^ low;
            long best = Long.MIN_VALUE;
            for (int s = rest;; s = (s - 1) & rest) {
                best = Math.max(best, score[low | s] + f[rest ^ s]);
                if (s == 0) break;
            }
            f[mask] = best;
        }
        System.out.println(f[full - 1]);
    }
}
```

</details>

<!-- test
in:
3
0 10 20
10 0 -100
20 -100 0
out:
20
-->
<!-- test
in:
1
0
out:
0
-->
<!-- test
in:
4
0 -1 -1 -1
-1 0 -1 -1
-1 -1 0 -1
-1 -1 -1 0
out:
0
-->

### Example 4 — Elevator Rides  ·  ★ ≈2000 (est.)

- **Source:** [CSES 1653 · Elevator Rides](https://cses.fi/problemset/task/1653)
- **Difficulty:** ≈2000 (est.)
- **Problem:** $n \le 20$ people with weights $w_i \le x \le 10^9$. Minimum number of elevator rides (each ride carries total weight $\le x$).
- **Thinking from first principles:** The partition formulation ($f(\text{mask}) = 1 + \min_{\text{feasible } s} f(\text{mask}\setminus s)$) costs $3^{20} \approx 3.5\cdot10^9$ — too slow. Instead let people enter one at a time: the state of the elevator process after a set of people has entered is (rides so far, load of the current ride), and for a fixed set the lexicographically smallest pair dominates all others (§1.4). So one pair per mask suffices: $O(2^n n) = 2\cdot10^7$.

<details><summary>Solution</summary>

$f(\emptyset) = (1, 0)$; $f(\text{mask}) = \min_{i \in \text{mask}} \text{add}(f(\text{mask}\setminus\{i\}), w_i)$; answer the first component of $f(\text{full})$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    long long x;
    cin >> n >> x;
    vector<long long> w(n);
    for (auto& v : w) cin >> v;
    vector<pair<int, long long>> f(1 << n, {INT_MAX, 0});  // (rides, load of the current ride)
    f[0] = {1, 0};
    for (int mask = 1; mask < (1 << n); mask++)
        for (int i = 0; i < n; i++) {
            if (!(mask >> i & 1)) continue;
            auto [r, load] = f[mask ^ (1 << i)];
            pair<int, long long> cand = load + w[i] <= x ? make_pair(r, load + w[i]) : make_pair(r + 1, w[i]);
            f[mask] = min(f[mask], cand);
        }
    cout << f[(1 << n) - 1].first << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c != '-' && (c < '0' || c > '9')) c = IN.read();
        boolean neg = c == '-';
        if (neg) c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nl();
        long x = nl();
        long[] w = new long[n];
        for (int i = 0; i < n; i++) w[i] = nl();
        int full = 1 << n;
        int[] rides = new int[full];
        long[] load = new long[full];
        Arrays.fill(rides, Integer.MAX_VALUE);
        rides[0] = 1;
        for (int mask = 1; mask < full; mask++)
            for (int i = 0; i < n; i++) {
                if ((mask >> i & 1) == 0) continue;
                int p = mask ^ (1 << i);
                int r;
                long l;
                if (load[p] + w[i] <= x) { r = rides[p]; l = load[p] + w[i]; }
                else { r = rides[p] + 1; l = w[i]; }
                if (r < rides[mask] || (r == rides[mask] && l < load[mask])) { rides[mask] = r; load[mask] = l; }
            }
        System.out.println(rides[full - 1]);
    }
}
```

</details>

<!-- test
in:
5 10
6 4 5 5 3
out:
3
-->
<!-- test
in:
1 7
7
out:
1
-->
<!-- test
in:
4 100
100 100 100 100
out:
4
-->

### Example 5 — A Simple Task (counting cycles)  ·  ★ 2200

- **Source:** [CF 11D · A Simple Task](https://codeforces.com/problemset/problem/11/D) — 2200
- **Difficulty:** 2200
- **Problem:** A simple undirected graph with $n \le 19$ vertices and $m$ edges. Count its simple cycles (length $\ge 3$).
- **Thinking from first principles:** A cycle has no natural start or direction — counting needs a canonical representative. Start at the **smallest** vertex of the cycle and walk; each cycle is then a path from its minimum vertex $s$ through vertices $> s$ back to a neighbour of $s$, counted once per direction. State $(\text{mask}, v)$ with $s = \text{low}(\text{mask})$ implicit. Close the cycle when $v$ is adjacent to $s$ and $|\text{mask}| \ge 3$; divide the total by 2. The answer can reach $\sim 10^{15}$ (complete graph): 64-bit.

<details><summary>Solution</summary>

$h(\{s\}, s) = 1$; push $h(\text{mask} \cup \{u\}, u) \mathrel{+}= h(\text{mask}, v)$ for neighbours $u > s$ of $v$ not in mask. $O(2^n n^2)$, about $1.9\cdot 10^8$ cheap operations at $n=19$ (only $u>s$ are tried).

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<int> adj(n, 0);
    for (int i = 0; i < m; i++) {
        int a, b;
        cin >> a >> b;
        a--, b--;
        adj[a] |= 1 << b;
        adj[b] |= 1 << a;
    }
    vector<long long> h((size_t)(1 << n) * n, 0);
    for (int s = 0; s < n; s++) h[(size_t)(1 << s) * n + s] = 1;
    long long twice = 0;
    for (int mask = 1; mask < (1 << n); mask++) {
        int s = __builtin_ctz(mask);                   // canonical start: smallest vertex
        int cnt = __builtin_popcount(mask);
        for (int v = s; v < n; v++) {
            long long cur = h[(size_t)mask * n + v];
            if (!cur) continue;
            if (cnt >= 3 && (adj[v] >> s & 1)) twice += cur;    // close the cycle back to s
            int ext = adj[v] & ~mask & ~((1 << (s + 1)) - 1);    // unvisited neighbours larger than s
            for (; ext; ext &= ext - 1) {
                int u = __builtin_ctz(ext);
                h[(size_t)(mask | 1 << u) * n + u] += cur;
            }
        }
    }
    cout << twice / 2 << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c != '-' && (c < '0' || c > '9')) c = IN.read();
        boolean neg = c == '-';
        if (neg) c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nl(), m = (int) nl();
        int[] adj = new int[n];
        for (int i = 0; i < m; i++) {
            int a = (int) nl() - 1, b = (int) nl() - 1;
            adj[a] |= 1 << b;
            adj[b] |= 1 << a;
        }
        long[] h = new long[(1 << n) * n];
        for (int s = 0; s < n; s++) h[(1 << s) * n + s] = 1;
        long twice = 0;
        for (int mask = 1; mask < (1 << n); mask++) {
            int s = Integer.numberOfTrailingZeros(mask);
            int cnt = Integer.bitCount(mask);
            for (int v = s; v < n; v++) {
                long cur = h[mask * n + v];
                if (cur == 0) continue;
                if (cnt >= 3 && (adj[v] >> s & 1) != 0) twice += cur;
                int ext = adj[v] & ~mask & ~((1 << (s + 1)) - 1);
                for (; ext != 0; ext &= ext - 1) {
                    int u = Integer.numberOfTrailingZeros(ext);
                    h[(mask | 1 << u) * n + u] += cur;
                }
            }
        }
        System.out.println(twice / 2);
    }
}
```

</details>

<!-- test
in:
4 5
1 2
1 3
1 4
2 3
3 4
out:
3
-->
<!-- test
in:
3 2
1 2
2 3
out:
0
-->
<!-- test
in:
5 5
1 2
2 3
3 4
4 5
5 1
out:
1
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Operator precedence:** shifts bind tighter than `&` (so `mask & 1 << i` is fine), but `==`/`!=` bind tighter than `&`: `mask & 1 << i == 0` means `mask & ((1 << i) == 0)`. C++ compiles it silently; Java rejects `int & boolean`. Always write `(mask >> i & 1) == 1` or `(mask & (1 << i)) != 0`.
2. **`1 << 31` and beyond:** for $n \ge 31$ use `1LL <<` / `1L <<`. Masks of 32+ elements are a sign the approach is wrong anyway.
3. **Submask loop termination:** `for (s = m; s; s = (s-1) & m)` skips $s = 0$; if the empty submask is needed, use the `for (;;) { …; if (s == 0) break; s = (s-1)&m; }` form (Example 3).
4. **Canonical choices for counting:** fix the block containing the lowest element (partitions), the smallest vertex as the start (cycles); otherwise you count each object several times.
5. **Unreachable states:** initialise to $\pm\infty$ (or $-1$ for non-negative maxima) and skip them; in counting DPs, skip zeros for speed.
6. **Memory layout:** `dp[mask][v]` with $v$ inner and contiguous is cache-friendly for "for each $v$ in mask"; in Java flatten to `long[(1<<n)*n]` — $2^{20}$ separate `long[20]` objects cost ~40 MB of headers alone.
7. **Use `int` where possible:** counts mod $p$ fit in `int`; $2^{21}$ ints = 8 MB vs 16 MB for `long`.
8. **Iterate set bits, not all bits:** `for (r = mask; r; r &= r - 1) i = ctz(r)` — halves the constant when masks are sparse.
9. **`__builtin_popcount` is for `unsigned int`;** use `__builtin_popcountll` for 64-bit masks. Java: `Integer.bitCount`, `Long.bitCount`.
10. **Prune by popcount:** if only masks of size $\le m$ matter (Example 2), skip extensions once $|\text{mask}| = m$.
11. **Dominance licenses compressing values:** in Example 4, keeping one pair per mask is correct only because (rides, load) is totally ordered by "never worse"; check that argument before reusing the trick.
12. **Push vs pull:** push from `mask` to `mask | bit` is natural for "add one element"; pull over submasks is natural for partitions. Both process masks in increasing order.

---

## 7. Going further (toward 2400–2600+)

- **SOS DP / zeta and Möbius transforms over subsets** — aggregate over all submasks in $O(n2^n)$ (CF 165E, CF 449D, CF 1208F; [SOS DP](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md)).
- **Subset convolution** in $O(n^2 2^n)$ (🔴) for "partition into two parts with independent costs, for every mask".
- **Bitmask over values, not items** (CF 895C, CF 453B): the mask stores prime-exponent parities or which primes are used; group items by value first.
- **Profile DP** — masks of a frontier in grids ([broken profile](11-broken-profile-dp.md)), and its 🔴 extension "plug DP" with connectivity encodings.
- **Rotate-columns style problems** (CF 1209E2): only the $n$ best columns matter, then $O(3^n \cdot n)$ submask DP.
- **Steiner tree in graphs** with $k \le 10$ terminals: $f(\text{mask}, v)$ with submask merges at $v$ plus Dijkstra relaxation per mask — $O(3^k n + 2^k m \log m)$ (🔴).
- **Inclusion–exclusion over masks** for counting Hamiltonian paths in $O(2^n n^3)$ with polynomial memory (🧊).

---

## 8. Practice ladder

**1600–1900**
- [ ] [AtCoder DP O · Matching](https://atcoder.jp/contests/dp/tasks/dp_o)
- [ ] [CF 1051D · Bicolorings](https://codeforces.com/problemset/problem/1051/D) — 1700
- [ ] [CF 580D · Kefa and Dishes](https://codeforces.com/problemset/problem/580/D) — 1800
- [ ] [CSES 1690 · Hamiltonian Flights](https://cses.fi/problemset/task/1690) — count Hamiltonian paths, $(\text{mask}, v)$
- [ ] [CF 16E · Fish](https://codeforces.com/problemset/problem/16/E) — 1900

**1900–2200**
- [ ] [AtCoder DP U · Grouping](https://atcoder.jp/contests/dp/tasks/dp_u)
- [ ] [CSES 1653 · Elevator Rides](https://cses.fi/problemset/task/1653)
- [ ] [CF 8C · Looking for Order](https://codeforces.com/problemset/problem/8/C) — 2000
- [ ] [CF 453B · Little Pony and Harmony Chest](https://codeforces.com/problemset/problem/453/B) — 2000
- [ ] [CF 895C · Square Subsets](https://codeforces.com/problemset/problem/895/C) — 2000
- [ ] [CF 1102F · Elongated Matrix](https://codeforces.com/problemset/problem/1102/F) — 2000
- [ ] [CF 11D · A Simple Task](https://codeforces.com/problemset/problem/11/D) — 2200
- [ ] [CF 1215E · Marbles](https://codeforces.com/problemset/problem/1215/E) — 2200
- [ ] [CF 1238E · Keyboard Purchase](https://codeforces.com/problemset/problem/1238/E) — 2200
- [ ] [CF 165E · Compatible Numbers](https://codeforces.com/problemset/problem/165/E) — 2200
- [ ] [CF 678E · Another Sith Tournament](https://codeforces.com/problemset/problem/678/E) — 2200

**2300+**
- [ ] [CF 1316E · Team Building](https://codeforces.com/problemset/problem/1316/E) — 2300
- [ ] [CF 744C · Hongcow Buys a Deck of Cards](https://codeforces.com/problemset/problem/744/C) — 2400
- [ ] [CF 1209E2 · Rotate Columns (hard version)](https://codeforces.com/problemset/problem/1209/E2) — 2500

---

## 9. LeetCode / FAANG cross-reference

- [LC 847 · Shortest Path Visiting All Nodes](https://leetcode.com/problems/shortest-path-visiting-all-nodes/) — Hard — BFS over $(\text{mask}, v)$ (revisits allowed ⇒ BFS, not a single DP pass).
- [LC 943 · Find the Shortest Superstring](https://leetcode.com/problems/find-the-shortest-superstring/) — Hard — TSP on overlaps, with reconstruction.
- [LC 1125 · Smallest Sufficient Team](https://leetcode.com/problems/smallest-sufficient-team/) — Hard — mask over skills.
- [LC 698 · Partition to K Equal Sum Subsets](https://leetcode.com/problems/partition-to-k-equal-sum-subsets/) — Medium — Elevator-rides pair trick (load mod target).
- [LC 1879 · Minimum XOR Sum of Two Arrays](https://leetcode.com/problems/minimum-xor-sum-of-two-arrays/) — Hard — assignment, index = popcount.
- [LC 526 · Beautiful Arrangement](https://leetcode.com/problems/beautiful-arrangement/) — Medium — count permutations by popcount position.
- [LC 2305 · Fair Distribution of Cookies](https://leetcode.com/problems/fair-distribution-of-cookies/) — Medium — submask DP over children.
- [LC 1494 · Parallel Courses II](https://leetcode.com/problems/parallel-courses-ii/) — Hard — submasks of available courses of size $\le k$.
- [LC 1434 · Number of Ways to Wear Different Hats to Each Other](https://leetcode.com/problems/number-of-ways-to-wear-different-hats-to-each-other/) — Hard — iterate hats, mask over the 10 people (mask the *small* side).
- [LC 2172 · Maximum AND Sum of Array](https://leetcode.com/problems/maximum-and-sum-of-array/) — Hard — base-3 mask (each slot holds ≤ 2).
- [LC 1655 · Distribute Repeating Integers](https://leetcode.com/problems/distribute-repeating-integers/) — Hard — submask DP over customers.
- [LC 1349 · Maximum Students Taking Exam](https://leetcode.com/problems/maximum-students-taking-exam/) — Hard — row masks with compatibility between consecutive rows.

In interviews, bitmask DP appears mostly at Google/Meta "hard" rounds; state the $n \le 20$ observation explicitly — it shows you read constraints as hints.

---

## 10. Self-check

1. Why does Held–Karp not need to remember the order in which cities were visited?
2. Prove that the total number of (mask, submask) pairs is $3^n$.
3. In assignment DP, why is the man index equal to `popcount(mask)`?
4. Why must a counting partition DP force the block to contain the lowest set bit?
5. What makes keeping a single (rides, load) pair per mask correct in Elevator Rides?
6. How many times is each cycle counted by the canonical-start DP, and why?
7. Write the submask loop that also visits the empty submask.
8. Estimate time and memory for $f(\text{mask}, v)$ with `long long`, $n = 20$.

<details><summary>Answers</summary>

1. The cost of finishing the tour depends only on the set of unvisited cities and the current city; any two partial tours with the same (set, city) have identical futures, so only the cheaper one matters.
2. Each element is outside the mask, inside the mask but outside the submask, or inside the submask — 3 choices per element, independently.
3. Men are processed in order $0,1,\dots$ and each matched man uses exactly one woman, so after $k$ men the mask of used women has $k$ bits.
4. Without it each partition into $j$ blocks is generated $j!$ times (once per order of choosing the blocks); fixing the block of the lowest element makes the order canonical.
5. For a fixed set of people, (fewer rides) or (same rides and lighter current load) is never worse for any continuation, so the lexicographically smallest pair dominates every other reachable pair.
6. Exactly twice — once in each direction around the cycle — because the start is forced to be the smallest vertex.
7. `for (int s = m;; s = (s - 1) & m) { use(s); if (s == 0) break; }`
8. $2^{20}\cdot 20 \approx 2.1\cdot10^7$ states × 8 bytes $\approx 168$ MB (too much for 256 MB with anything else; use `int` if possible), and $2^{20}\cdot 400 \approx 4.2\cdot10^8$ transitions — borderline, needs pruning.

</details>
