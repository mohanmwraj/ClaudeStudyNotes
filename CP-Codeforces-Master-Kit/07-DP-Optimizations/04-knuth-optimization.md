# Knuth Optimisation (Knuth–Yao Speed-up)

> **Band:** 🟠 2100–2500 · **Priority:** ⚡ · **FAANG:** low · **Prerequisites:** [interval DP](../06-Dynamic-Programming/05-interval-dp.md), [divide & conquer optimisation](03-divide-and-conquer-optimization.md) (the quadrangle inequality), [prefix sums](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md)
> **You can say you know this when:** you can state the two conditions on the cost (quadrangle inequality + monotonicity on inclusion), prove why they give $\mathrm{opt}[i][j-1] \le \mathrm{opt}[i][j] \le \mathrm{opt}[i+1][j]$ and why the restricted loops total $O(n^2)$, recognise when the conditions fail (matrix chain, burst balloons), and use the same bound on the $k$-partition DP to get $O(n^2)$ regardless of $k$.

## 1. First principles — why this works

### 1.1 The DP and its waste

The archetype is "merge adjacent piles" (equivalently: split an array into singletons, each split of a block costing its sum):
$$dp[i][j] = C(i, j) + \min_{i \le k < j}\big(dp[i][k] + dp[k+1][j]\big), \qquad dp[i][i] = 0 .$$
$O(n^2)$ intervals × $O(n)$ split points $= O(n^3)$; at $n = 5000$ that is $10^{11}$. Let $\mathrm{opt}[i][j]$ be the best split. Intuition: if you extend the interval to the right, the best split can't jump left; if you shrink it from the left, it can't jump right. Formally, **Knuth's bound**
$$\mathrm{opt}[i][j-1] \;\le\; \mathrm{opt}[i][j] \;\le\; \mathrm{opt}[i+1][j].$$

### 1.2 Why the bound gives $O(n^2)$: telescoping

Process intervals by length $d = j - i$. With the bound, interval $(i, j)$ scans $\mathrm{opt}[i+1][j] - \mathrm{opt}[i][j-1] + 1$ candidates. For a fixed $d$, summing over $i$:
$$\sum_{i} \big(\mathrm{opt}[i+1][i+d] - \mathrm{opt}[i][i+d-1] + 1\big) = \mathrm{opt}[n-d+1][n] - \mathrm{opt}[1][d] + (n - d) \le 2n,$$
because consecutive terms cancel ($\mathrm{opt}[i+1][i+d]$ appears with $+$ for $i$ and with $-$ for $i+1$). So each length costs $O(n)$ and the whole table $O(n^2)$. The bound only uses values from length $d-1$, which are already computed.

### 1.3 When the bound holds: the two conditions on $C$

For all $a \le b \le c \le d$:
1. **Quadrangle inequality (QI):** $C(a, c) + C(b, d) \le C(a, d) + C(b, c)$.
2. **Monotone on inclusion:** $C(b, c) \le C(a, d)$ (a sub-interval never costs more).

The classic cost "sum of the block" satisfies QI with equality and is monotone for non-negative values. **Theorem (Yao 1980, generalising Knuth 1971):** under 1 and 2, $dp$ itself satisfies QI, and QI of $dp$ implies Knuth's bound.

**Step A — QI of $dp$ implies the bound.** Fix $(i, j)$, let $k = \mathrm{opt}[i][j-1]$ (largest optimum) and take any $k' < k$. Optimality of $k$ for $(i, j-1)$: $dp[i][k] + dp[k+1][j-1] \le dp[i][k'] + dp[k'+1][j-1]$. QI of $dp$ on $k'+1 \le k+1 \le j-1 \le j$: $dp[k'+1][j-1] + dp[k+1][j] \le dp[k'+1][j] + dp[k+1][j-1]$. Adding and cancelling: $dp[i][k] + dp[k+1][j] \le dp[i][k'] + dp[k'+1][j]$, so $k$ is at least as good as every $k' < k$ for $(i, j)$, hence the largest optimum of $(i, j)$ is $\ge k$. The upper bound is symmetric. $\square$

**Step B — QI and monotonicity of $C$ imply QI of $dp$** (induction on the length of the outer interval $[a, d]$; sketch). For $a < b \le c < d$ let $z = \mathrm{opt}[a][d]$ and $y = \mathrm{opt}[b][c]$.
- *If $z \le y$:* split $[a, c]$ at $z$ and $[b, d]$ at $y$ (both legal), so $dp[a][c] + dp[b][d] \le C(a,c) + C(b,d) + dp[a][z] + dp[b][y] + dp[z+1][c] + dp[y+1][d]$. Apply QI of $C$ to the $C$ terms and the induction hypothesis to $dp[z+1][c] + dp[y+1][d] \le dp[z+1][d] + dp[y+1][c]$ (indices $z+1 \le y+1 \le c \le d$, shorter outer interval). The right side regroups into $dp[a][d] + dp[b][c]$.
- *If $z > y$:* symmetric — split $[a, c]$ at $y$ and $[b, d]$ at $z$, and use the hypothesis on $a \le b \le y \le z$.
- *Degenerate case $b = c$* (single element, $dp[b][b] = 0$, no $y$): here monotonicity of $C$ is needed, $C(c, d) \le C(a, d)$, together with the hypothesis on $(a, c, c, z)$.

You don't need to reproduce Step B in a contest; you need to know **both** conditions are required and to check them.

### 1.4 Other shapes with the same theory

- **Shared boundaries ("cut the stick").** Points $0 = c_0 < \dots < c_{m+1} = L$; $dp[i][j] = (c_j - c_i) + \min_{i<k<j}(dp[i][k] + dp[k][j])$, $dp[i][i+1] = 0$. Re-index the *gaps* between points as elements and it is the form of §1.1 with cost "sum of gap lengths". Same bound.
- **Optimal binary search tree** (Knuth's original problem). Keys $1..n$ with access weights $f_i$; $e[i][j] = W(i, j) + \min_{i \le r \le j}(e[i][r-1] + e[r+1][j])$, $e[i][i-1] = 0$, $W$ = sum of weights. Root bound $\mathrm{root}[i][j-1] \le \mathrm{root}[i][j] \le \mathrm{root}[i+1][j]$.
- **The $k$-partition DP** $dp_t[i] = \min_j dp_{t-1}[j] + C(j, i)$ with $C$ QI (no monotonicity condition needed here):
  $$\mathrm{opt}_{t-1}[i] \;\le\; \mathrm{opt}_t[i] \;\le\; \mathrm{opt}_t[i+1].$$
  The right inequality is the [D&C theorem](03-divide-and-conquer-optimization.md). The left one says "with one more group, the last group starts no earlier"; it follows from the exchange inequality $dp_{t-1}[b] + dp_{t-2}[a] \le dp_{t-1}[a] + dp_{t-2}[b]$ for $a < b$, proved by crossing two optimal partitions and swapping their tails (QI on the two crossing groups). Fill $t$ increasing and $i$ decreasing; the same telescoping gives $O(n(n+k))$ — **$O(n^2)$ total, independent of $k$**, versus $O(kn\log n)$ for D&C.

### 1.5 When it does not apply

The cost must not depend on the split point $k$. Matrix-chain multiplication, $dp[i][j] = \min_k dp[i][k] + dp[k+1][j] + p_{i-1} p_k p_j$, violates the premise; a brute force finds $4$ matrices with dimensions $5\times8, 8\times5, 5\times6, 6\times3$ where the Knuth-restricted DP returns $365$ but the true optimum is $330$. Burst balloons and polygon triangulation have the same issue. (Matrix chain has a separate $O(n\log n)$ algorithm by Hu and Shing — far beyond contest needs.)

## 2. Formulas, definitions and identities

| Statement | Meaning |
|---|---|
| $dp[i][j] = C(i,j) + \min_{i\le k<j}(dp[i][k] + dp[k+1][j])$ | interval-split form |
| $C(a,c) + C(b,d) \le C(a,d) + C(b,c)$ | QI of the cost |
| $C(b,c) \le C(a,d)$ for $[b,c] \subseteq [a,d]$ | monotone on inclusion |
| QI + monotone $\Rightarrow$ $dp$ satisfies QI | Yao's lemma (§1.3 B) |
| $dp$ QI $\Rightarrow$ $\mathrm{opt}[i][j-1] \le \mathrm{opt}[i][j] \le \mathrm{opt}[i+1][j]$ | Knuth's bound (§1.3 A) |
| $\sum_i (\mathrm{opt}[i+1][i+d] - \mathrm{opt}[i][i+d-1] + 1) \le 2n$ | telescoping, $O(n)$ per length |
| $\mathrm{opt}_{t-1}[i] \le \mathrm{opt}_t[i] \le \mathrm{opt}_t[i+1]$ | layered (partition) form; $O(n(n+k))$ |
| $dp_{t-1}[b] + dp_{t-2}[a] \le dp_{t-1}[a] + dp_{t-2}[b]$, $a < b$ | exchange inequality behind the layered bound |
| $W(i,j) = \sum_{t=i}^{j} f_t$ | optimal BST weight; QI with equality, monotone |
| $\sum_{t} c_t\,|t - m|$, $m$ = weighted median | $k$-median group cost (QI) |

| Variant | Naive | Knuth |
|---|---|---|
| interval split ($n$ elements) | $O(n^3)$ | $O(n^2)$ time, $O(n^2)$ memory |
| optimal BST | $O(n^3)$ | $O(n^2)$ |
| $k$-partition | $O(kn^2)$ | $O(n(n+k))$, $O(n)$ memory with rolling rows |

## 3. Implementation (C++ and Java)

**3.1 Interval form.** Jagged rows (row $i$ stores intervals $[i, i..n-1]$) halve the memory: at $n = 5000$, $1.25\cdot10^7$ `long`s ($100$ MB) instead of $200$ MB. Both fragments were stress-tested against the $O(n^3)$ DP with "sum" and "sum + length²" costs.

```cpp
// Knuth optimisation for  dp[i][j] = C(i, j) + min_{i <= k < j} (dp[i][k] + dp[k+1][j]),  dp[i][i] = 0
// (0-indexed elements i..j). Valid when C satisfies the quadrangle inequality and is monotone on
// inclusion (C(b, c) <= C(a, d) for a <= b <= c <= d). Then opt[i][j-1] <= opt[i][j] <= opt[i+1][j].
// O(n^2) time; jagged storage row i = intervals [i, i..n-1], so memory is n(n+1)/2 entries.
template <class Cost>
ll knuthInterval(int n, Cost& C) {
    vector<vector<ll>> dp(n);
    vector<vector<int>> opt(n);
    for (int i = 0; i < n; i++) { dp[i].assign(n - i, 0); opt[i].assign(n - i, i); }
    for (int d = 1; d < n; d++) {
        for (int i = 0; i + d < n; i++) {
            int j = i + d;
            int lo = opt[i][d - 1], hi = min(opt[i + 1][d - 1], j - 1);   // opt[i][j-1], opt[i+1][j]
            ll best = LLONG_MAX;
            int arg = lo;
            for (int k = lo; k <= hi; k++) {
                ll v = dp[i][k - i] + dp[k + 1][j - k - 1];
                if (v <= best) { best = v; arg = k; }   // largest optimal split
            }
            dp[i][d] = best + C(i, j);
            opt[i][d] = arg;
        }
    }
    return dp[0][n - 1];
}
```

```java
// Knuth optimisation, interval form; same contract as the C++ version.
interface IntervalCost { long get(int i, int j); }
static long knuthInterval(int n, IntervalCost C) {
    long[][] dp = new long[n][];
    int[][] opt = new int[n][];
    for (int i = 0; i < n; i++) { dp[i] = new long[n - i]; opt[i] = new int[n - i]; opt[i][0] = i; }
    for (int d = 1; d < n; d++) {
        for (int i = 0; i + d < n; i++) {
            int j = i + d;
            int lo = opt[i][d - 1], hi = Math.min(opt[i + 1][d - 1], j - 1);
            long best = Long.MAX_VALUE;
            int arg = lo;
            for (int k = lo; k <= hi; k++) {
                long v = dp[i][k - i] + dp[k + 1][j - k - 1];
                if (v <= best) { best = v; arg = k; }
            }
            dp[i][d] = best + C.get(i, j);
            opt[i][d] = arg;
        }
    }
    return dp[0][n - 1];
}
```

**3.2 Layered (partition) form.** Two rolling rows of values and of optima; $i$ runs downwards because $\mathrm{opt}_t[i]$ needs $\mathrm{opt}_t[i+1]$. Stress-tested against the $O(kn^2)$ DP with squared, cubic-penalty and equal-pair costs.

```cpp
// Knuth's bound for the k-partition DP  dp[t][i] = min_{t-1 <= j < i} dp[t-1][j] + C(j, i),
// dp[1][i] = C(0, i): with C satisfying the quadrangle inequality,
//   opt[t-1][i] <= opt[t][i] <= opt[t][i+1]   (largest optimal j in every cell).
// Fill t increasing, i decreasing. Total work O(n (n + K)); two rolling rows of dp and opt.
template <class Cost>
ll knuthLayered(int n, int K, Cost& C) {
    vector<ll> prv(n + 1), cur(n + 1);
    vector<int> po(n + 2, 0), co(n + 2);
    for (int i = 1; i <= n; i++) prv[i] = C(0, i);        // layer 1, opt = 0
    for (int t = 2; t <= K; t++) {
        co[n + 1] = n;                                     // sentinel upper bound for i = n
        for (int i = n; i >= t; i--) {
            int lo = max(po[i], t - 1), hi = min(co[i + 1], i - 1);
            ll best = LLONG_MAX;
            int arg = lo;
            for (int j = lo; j <= hi; j++) {
                ll v = prv[j] + C(j, i);
                if (v <= best) { best = v; arg = j; }
            }
            cur[i] = best;
            co[i] = arg;
        }
        swap(prv, cur);
        swap(po, co);
    }
    return prv[n];
}
```

```java
// Knuth's bound for the k-partition DP; same contract as the C++ version.
interface PartCost { long get(int j, int i); }
static long knuthLayered(int n, int K, PartCost C) {
    long[] prv = new long[n + 1], cur = new long[n + 1];
    int[] po = new int[n + 2], co = new int[n + 2];
    for (int i = 1; i <= n; i++) prv[i] = C.get(0, i);
    for (int t = 2; t <= K; t++) {
        co[n + 1] = n;
        for (int i = n; i >= t; i--) {
            int lo = Math.max(po[i], t - 1), hi = Math.min(co[i + 1], i - 1);
            long best = Long.MAX_VALUE;
            int arg = lo;
            for (int j = lo; j <= hi; j++) {
                long v = prv[j] + C.get(j, i);
                if (v <= best) { best = v; arg = j; }
            }
            cur[i] = best;
            co[i] = arg;
        }
        long[] t1 = prv; prv = cur; cur = t1;
        int[] t2 = po; po = co; co = t2;
    }
    return prv[n];
}
```

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| Interval DP "merge/split adjacent", $n$ up to $5000$, cost = sum / length of the block | Knuth, $O(n^2)$ |
| Optimal BST, optimal alphabetic code, "build a search structure minimising weighted depth" | Knuth's root bound |
| Cutting a stick / a string at given points, each cut costs the current length | Knuth (shared-boundary form) |
| $k$-partition DP with QI cost and **large $k$** (up to $n$) | layered Knuth, $O(n^2)$ |
| Cost depends on the split point $k$ ($p_{i-1}p_kp_j$, $a_{i-1}a_ka_{j+1}$) | **not** Knuth — keep $O(n^3)$ or find another structure |
| Cost has QI but is not monotone on inclusion (e.g. it can decrease when you grow the interval) | check with a brute force before trusting the bound |

**Commonly confused with:** [D&C optimisation](03-divide-and-conquer-optimization.md) (one-dimensional monotonicity $\mathrm{opt}(i) \le \mathrm{opt}(i+1)$, needs QI only, gives $O(kn\log n)$); generic [interval DP](../06-Dynamic-Programming/05-interval-dp.md) problems whose cost involves the split point.

## 5. Worked examples (graded)

### Example 1 — Minimum Cost to Cut a Stick (large limits)  ·  ★ ≈2000 (est.)

- **Source:** [LC 1547 · Minimum Cost to Cut a Stick](https://leetcode.com/problems/minimum-cost-to-cut-a-stick/) — Hard, with $m$ raised from $100$ to $5000$ cuts.
- **Difficulty:** ≈2000 (est.) at these limits.
- **Problem:** a stick of length $L \le 10^9$ must be cut at $m$ given distinct positions, in an order you choose; each cut costs the length of the piece being cut. Minimise the total cost. Input: `L m`, then the $m$ positions.
- **Thinking from first principles:** after sorting, the pieces that ever exist are $(c_i, c_j)$ between two cut points; the first cut inside $(c_i, c_j)$ at $c_k$ splits it into two independent subproblems: $dp[i][j] = (c_j - c_i) + \min_{i<k<j}(dp[i][k] + dp[k][j])$. $O(m^3)$ is fine for LC's $m \le 100$ but $10^{11}$ at $m = 5000$. The cost $c_j - c_i$ doesn't depend on $k$, satisfies QI with equality and is monotone on inclusion: Knuth applies, $O(m^2)$.

<details><summary>Solution</summary>

Shared-boundary form (§1.4) with $\mathrm{opt}[i][i+1] = i+1$ as the base bound; clamp the scan to $(i, j)$. $O(m^2)$ time and memory (two $(m+2)^2$ tables, $\approx 300$ MB at $m = 5000$ — use jagged rows as in §3.1 if memory is tight). Stress-tested against the exhaustive recursion over cut orders.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    ll len;
    int m;
    cin >> len >> m;
    vector<ll> c(m + 2);
    c[0] = 0;
    for (int i = 1; i <= m; i++) cin >> c[i];
    c[m + 1] = len;
    sort(c.begin(), c.end());
    int P = m + 2;                                       // points 0..m+1; a piece is (i, j), i < j
    vector<vector<ll>> dp(P, vector<ll>(P, 0));
    vector<vector<int>> opt(P, vector<int>(P, 0));
    for (int i = 0; i + 1 < P; i++) opt[i][i + 1] = i + 1;   // no cut inside; bound for length 2
    for (int d = 2; d < P; d++) {
        for (int i = 0; i + d < P; i++) {
            int j = i + d;
            int lo = max(opt[i][j - 1], i + 1), hi = min(opt[i + 1][j], j - 1);
            ll best = LLONG_MAX;
            int arg = lo;
            for (int k = lo; k <= hi; k++) {             // first cut at point k
                ll v = dp[i][k] + dp[k][j];
                if (v <= best) { best = v; arg = k; }
            }
            dp[i][j] = best + (c[j] - c[i]);             // cutting piece (i, j) costs its length
            opt[i][j] = arg;
        }
    }
    cout << dp[0][P - 1] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        long len = in.nextLong();
        int m = in.nextInt();
        long[] c = new long[m + 2];
        for (int i = 1; i <= m; i++) c[i] = in.nextLong();
        c[m + 1] = len;
        Arrays.sort(c);                                  // long[]: no quicksort anti-test issue
        int P = m + 2;
        long[][] dp = new long[P][P];
        int[][] opt = new int[P][P];
        for (int i = 0; i + 1 < P; i++) opt[i][i + 1] = i + 1;
        for (int d = 2; d < P; d++) {
            for (int i = 0; i + d < P; i++) {
                int j = i + d;
                int lo = Math.max(opt[i][j - 1], i + 1), hi = Math.min(opt[i + 1][j], j - 1);
                long best = Long.MAX_VALUE;
                int arg = lo;
                for (int k = lo; k <= hi; k++) {
                    long v = dp[i][k] + dp[k][j];
                    if (v <= best) { best = v; arg = k; }
                }
                dp[i][j] = best + (c[j] - c[i]);
                opt[i][j] = arg;
            }
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(dp[0][P - 1]);
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
7 4
1 3 4 5
out:
16
-->
<!-- test
in:
9 5
5 6 1 4 2
out:
22
-->
<!-- test
in:
2 1
1
out:
2
-->
<!-- test
in:
1000000000 1
1
out:
1000000000
-->

### Example 2 — Knuth Division  ·  ★ ≈2200 (est.)

- **Source:** [CSES 2088 · Knuth Division](https://cses.fi/problemset/task/2088)
- **Difficulty:** ≈2200 (est.)
- **Problem:** an array of $n \le 5000$ positive integers ($\le 10^9$) must be divided into $n$ single-element pieces; splitting a piece into two contiguous parts costs the sum of that piece. Minimise the total cost.
- **Thinking from first principles:** read backwards it is "merge adjacent piles, paying the merged sum" (AtCoder's Slimes with larger $n$). $dp[i][j] = S(i..j) + \min_k (dp[i][k] + dp[k+1][j])$: the block sum is QI with equality and monotone for positive values, so Knuth gives $O(n^2) = 2.5\cdot10^7$ instead of $2\cdot10^{10}$. Values: each element is paid at most $n-1$ times, $\le 5000 \cdot 5000 \cdot 10^9 = 2.5\cdot10^{16}$.

<details><summary>Solution</summary>

Exactly §3.1 with $C(i,j) = S_{j+1} - S_i$. Jagged rows keep memory at about $150$ MB in total for $n = 5000$ (dp + opt).

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<ll> S(n + 1, 0);
    for (int i = 0; i < n; i++) { ll x; cin >> x; S[i + 1] = S[i] + x; }
    // dp[i][d] = cost to split a[i..i+d] into singletons; jagged rows halve the memory
    vector<vector<ll>> dp(n);
    vector<vector<int>> opt(n);
    for (int i = 0; i < n; i++) { dp[i].assign(n - i, 0); opt[i].assign(n - i, i); }
    for (int d = 1; d < n; d++) {
        for (int i = 0; i + d < n; i++) {
            int j = i + d;
            int lo = opt[i][d - 1], hi = min(opt[i + 1][d - 1], j - 1);   // Knuth: opt[i][j-1] .. opt[i+1][j]
            ll best = LLONG_MAX;
            int arg = lo;
            for (int k = lo; k <= hi; k++) {
                ll v = dp[i][k - i] + dp[k + 1][j - k - 1];
                if (v <= best) { best = v; arg = k; }
            }
            dp[i][d] = best + S[j + 1] - S[i];           // splitting a[i..j] costs its sum
            opt[i][d] = arg;
        }
    }
    cout << dp[0][n - 1] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long[] S = new long[n + 1];
        for (int i = 0; i < n; i++) S[i + 1] = S[i] + in.nextLong();
        long[][] dp = new long[n][];
        int[][] opt = new int[n][];
        for (int i = 0; i < n; i++) { dp[i] = new long[n - i]; opt[i] = new int[n - i]; opt[i][0] = i; }
        for (int d = 1; d < n; d++) {
            for (int i = 0; i + d < n; i++) {
                int j = i + d;
                int lo = opt[i][d - 1], hi = Math.min(opt[i + 1][d - 1], j - 1);
                long best = Long.MAX_VALUE;
                int arg = lo;
                for (int k = lo; k <= hi; k++) {
                    long v = dp[i][k - i] + dp[k + 1][j - k - 1];
                    if (v <= best) { best = v; arg = k; }
                }
                dp[i][d] = best + S[j + 1] - S[i];
                opt[i][d] = arg;
            }
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(dp[0][n - 1]);
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
5
2 7 3 2 5
out:
43
-->
<!-- test
in:
1
7
out:
0
-->
<!-- test
in:
2
1000000000 1000000000
out:
2000000000
-->
<!-- test
in:
4
1 1 1 1
out:
8
-->

### Example 3 — Optimal binary search tree  ·  ★ ≈2200 (est.)

- **Source:** Original problem (Knuth's 1971 setting, without "dummy" miss weights).
- **Difficulty:** ≈2200 (est.)
- **Problem:** keys $1..n$ ($n \le 5000$) are searched with frequencies $f_i \le 10^6$ (possibly $0$). Build a BST on them minimising $\sum_i f_i \cdot \mathrm{depth}(i)$, the root having depth $1$.
- **Thinking from first principles:** choosing root $r$ for keys $i..j$ splits into independent subtrees $i..r-1$ and $r+1..j$, and pushes every key of $i..j$ one level deeper — that's where the weight $W(i, j)$ comes from (it accounts for depth without tracking it): $e[i][j] = W(i,j) + \min_r (e[i][r-1] + e[r+1][j])$. $W$ is QI with equality and monotone, so $\mathrm{root}[i][j-1] \le \mathrm{root}[i][j] \le \mathrm{root}[i+1][j]$. Zero frequencies create many ties — a good test of consistent tie-breaking.

<details><summary>Solution</summary>

Fill by length; the root of $(i, j)$ is searched in $[\mathrm{root}[i][j-1], \mathrm{root}[i+1][j]]$, with $\mathrm{root}[i][i] = i$. Strict `<` = smallest optimal root, used consistently. $O(n^2)$. Stress-tested against a brute force that tracks depths explicitly (no weight trick), so it checks the recurrence itself as well as the optimisation.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<ll> W(n + 2, 0);                              // W[i] = f_1 + ... + f_i
    for (int i = 1; i <= n; i++) { ll f; cin >> f; W[i] = W[i - 1] + f; }
    // e[i][j], 1 <= i <= j+1 <= n+1: best cost of a tree on keys i..j; e[i][i-1] = 0 (empty)
    vector<vector<ll>> e(n + 2, vector<ll>(n + 1, 0));
    vector<vector<int>> root(n + 2, vector<int>(n + 1, 0));
    for (int i = 1; i <= n; i++) { e[i][i] = W[i] - W[i - 1]; root[i][i] = i; }
    for (int d = 1; d < n; d++) {
        for (int i = 1; i + d <= n; i++) {
            int j = i + d;
            ll best = LLONG_MAX;
            int arg = root[i][j - 1];
            for (int r = root[i][j - 1]; r <= root[i + 1][j]; r++) {   // Knuth's 1971 bound
                ll v = e[i][r - 1] + (r + 1 <= j ? e[r + 1][j] : 0);
                if (v < best) { best = v; arg = r; }
            }
            e[i][j] = best + W[j] - W[i - 1];            // every key in i..j moves one level down
            root[i][j] = arg;
        }
    }
    cout << e[1][n] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long[] W = new long[n + 2];
        for (int i = 1; i <= n; i++) W[i] = W[i - 1] + in.nextLong();
        long[][] e = new long[n + 2][n + 1];
        int[][] root = new int[n + 2][n + 1];
        for (int i = 1; i <= n; i++) { e[i][i] = W[i] - W[i - 1]; root[i][i] = i; }
        for (int d = 1; d < n; d++) {
            for (int i = 1; i + d <= n; i++) {
                int j = i + d;
                long best = Long.MAX_VALUE;
                int arg = root[i][j - 1];
                for (int r = root[i][j - 1]; r <= root[i + 1][j]; r++) {
                    long v = e[i][r - 1] + (r + 1 <= j ? e[r + 1][j] : 0);
                    if (v < best) { best = v; arg = r; }
                }
                e[i][j] = best + W[j] - W[i - 1];
                root[i][j] = arg;
            }
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(e[1][n]);
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
3
1 2 3
out:
10
-->
<!-- test
in:
1
5
out:
5
-->
<!-- test
in:
4
0 0 0 0
out:
0
-->
<!-- test
in:
5
15 10 5 10 20
out:
130
-->
<!-- test
in:
7
1 1 1 1 1 1 1
out:
17
-->

### Example 4 — Houses and Schools (layered Knuth)  ·  ★ ≈2300 (est.)

- **Source:** [CSES 2087 · Houses and Schools](https://cses.fi/problemset/task/2087)
- **Difficulty:** ≈2300 (est.)
- **Problem:** $n \le 3000$ houses on a line at unit distance, house $i$ with $c_i \le 10^9$ children. Build $k \le n$ schools in houses; every child walks to the nearest school. Minimise the total walking distance.
- **Thinking from first principles:** in an optimal solution each school serves a contiguous block of houses, and inside a block the best location is a weighted median. So it's a $k$-partition DP with the $k$-median cost, which satisfies QI. D&C gives $O(kn\log n)$ — up to $10^8$ with $k = n$. Knuth's layered bound gives $O(n(n+k)) \approx 1.8\cdot10^7$ independent of $k$. For an $O(1)$ cost we need the median of every block: for a fixed left end it only moves right as the block grows, so all medians come from a two-pointer sweep in $O(n^2)$.

<details><summary>Solution</summary>

With $C_x = \sum_{t \le x} c_t$, $D_x = \sum_{t \le x} t\,c_t$ and median $m$ of block $(j, i]$:
$$\mathrm{cost}(j, i) = m(C_m - C_j) - (D_m - D_j) + (D_i - D_m) - m(C_i - C_m).$$
Medians in a jagged `int` table ($\approx 18$ MB). Then §3.2: layers $t = 2..k$, $i$ from $n$ down to $t$, scanning $j \in [\max(\mathrm{opt}_{t-1}[i], t-1), \min(\mathrm{opt}_t[i+1], i-1)]$ with the largest optimum kept. Stress-tested against a brute force over all school placements with nearest-school assignment (which also validates the "contiguous blocks + median" model).

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int n, K;
vector<ll> C, D;                                     // C[x] = sum c, D[x] = sum t*c_t over t <= x
vector<vector<int>> med;                             // med[j][i-j] = weighted median of houses j+1..i

ll cost(int j, int i) {                              // one school serving houses j+1..i
    ll m = med[j][i - j];
    return m * (C[m] - C[j]) - (D[m] - D[j]) + (D[i] - D[m]) - m * (C[i] - C[m]);
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    cin >> n >> K;
    C.assign(n + 1, 0);
    D.assign(n + 1, 0);
    for (int t = 1; t <= n; t++) { ll c; cin >> c; C[t] = C[t - 1] + c; D[t] = D[t - 1] + c * t; }
    med.assign(n + 1, {});
    for (int j = 0; j < n; j++) {                    // the median only moves right as i grows
        med[j].assign(n - j + 1, 0);
        int m = j + 1;
        for (int i = j + 1; i <= n; i++) {
            while (2 * (C[m] - C[j]) < C[i] - C[j]) m++;
            med[j][i - j] = m;
        }
    }
    // Knuth for the partition DP: opt[t-1][i] <= opt[t][i] <= opt[t][i+1]
    vector<ll> prv(n + 1), cur(n + 1);
    vector<int> po(n + 2, 0), co(n + 2);
    for (int i = 1; i <= n; i++) prv[i] = cost(0, i);
    for (int t = 2; t <= K; t++) {
        co[n + 1] = n;
        for (int i = n; i >= t; i--) {
            int lo = max(po[i], t - 1), hi = min(co[i + 1], i - 1);
            ll best = LLONG_MAX;
            int arg = lo;
            for (int j = lo; j <= hi; j++) {
                ll v = prv[j] + cost(j, i);
                if (v <= best) { best = v; arg = j; }
            }
            cur[i] = best;
            co[i] = arg;
        }
        swap(prv, cur);
        swap(po, co);
    }
    cout << prv[n] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long[] C, D;
    static int[][] med;

    static long cost(int j, int i) {
        long m = med[j][i - j];
        return m * (C[(int) m] - C[j]) - (D[(int) m] - D[j]) + (D[i] - D[(int) m]) - m * (C[i] - C[(int) m]);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), K = in.nextInt();
        C = new long[n + 1]; D = new long[n + 1];
        for (int t = 1; t <= n; t++) { long c = in.nextLong(); C[t] = C[t - 1] + c; D[t] = D[t - 1] + c * t; }
        med = new int[n + 1][];
        for (int j = 0; j < n; j++) {
            med[j] = new int[n - j + 1];
            int m = j + 1;
            for (int i = j + 1; i <= n; i++) {
                while (2 * (C[m] - C[j]) < C[i] - C[j]) m++;
                med[j][i - j] = m;
            }
        }
        long[] prv = new long[n + 1], cur = new long[n + 1];
        int[] po = new int[n + 2], co = new int[n + 2];
        for (int i = 1; i <= n; i++) prv[i] = cost(0, i);
        for (int t = 2; t <= K; t++) {
            co[n + 1] = n;
            for (int i = n; i >= t; i--) {
                int lo = Math.max(po[i], t - 1), hi = Math.min(co[i + 1], i - 1);
                long best = Long.MAX_VALUE;
                int arg = lo;
                for (int j = lo; j <= hi; j++) {
                    long v = prv[j] + cost(j, i);
                    if (v <= best) { best = v; arg = j; }
                }
                cur[i] = best;
                co[i] = arg;
            }
            long[] t1 = prv; prv = cur; cur = t1;
            int[] t2 = po; po = co; co = t2;
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(prv[n]);
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
5 2
2 7 1 4 6
out:
7
-->
<!-- test
in:
1 1
5
out:
0
-->
<!-- test
in:
4 4
1 2 3 4
out:
0
-->
<!-- test
in:
6 2
1 1 1 1 1 1
out:
4
-->
<!-- test
in:
3 1
1000000000 1000000000 1000000000
out:
2000000000
-->

## 6. Tricks, pitfalls and things to remember

1. **Check that the cost doesn't depend on the split point.** If $k$ appears in the cost (matrix chain, burst balloons, triangulation), Knuth is wrong — the matrix-chain counterexample in §1.5 ($365$ vs $330$) came from a 20-line brute-force comparison; the same check on polygon triangulation (LC 1039) with vertex values $2, 6, 7, 9, 4$ gives $392$ with the bound versus the true $282$.
2. **Check both conditions**, not just QI. A cost that satisfies QI but can *decrease* when the interval grows breaks Yao's lemma (the degenerate case of Step B).
3. **Consistent tie-breaking.** Take the smallest or the largest optimum everywhere. Zero weights (Example 3) produce plateaus of equal values; mixing rules there is how "Knuth almost works" bugs are born.
4. **Base cases of `opt`.** Interval form: $\mathrm{opt}[i][i] = i$. Shared-boundary form: $\mathrm{opt}[i][i+1] = i+1$, and clamp the scan to $i < k < j$. Layered form: $\mathrm{opt}_1[\cdot] = 0$ and a sentinel $\mathrm{opt}_t[n+1] = n$.
5. **Loop order.** Interval form: by increasing length. Layered form: $t$ increasing, $i$ **decreasing** (the upper bound is $\mathrm{opt}_t[i+1]$).
6. **Memory is the real limit.** $n = 5000$ means $2.5\cdot10^7$ cells per table. Use jagged/triangular storage, `int` for `opt`, and roll rows in the layered form. In Java, `long[5001][5001]` alone is 200 MB.
7. **Overflow:** sums paid up to $n$ times — $n^2 \max a$ can reach $10^{16}$–$10^{17}$: 64-bit.
8. **Java:** allocate the jagged arrays once; avoid `ArrayList<long[]>`. Inner loops on `dp[i][k - i]` and `dp[k + 1][j - k - 1]` are cache-unfriendly across rows — still fine at $2.5\cdot10^7$ steps.
9. **Don't confuse with "merge $K$ consecutive piles"** (LC 1000): the state needs the number of piles, and the standard solution is $O(n^3/K)$ interval DP; Knuth's bound isn't the tool there.
10. **AtCoder Slimes ($n \le 400$) passes in $O(n^3)$** — use it to *test* your Knuth implementation against the naive DP before relying on it.

## 7. Going further (toward 2400–2600+)

- **Garsia–Wachs** solves the merge-adjacent-piles problem (optimal alphabetic tree) in $O(n \log n)$; it's what you need when $n = 10^5$ and Knuth's $O(n^2)$ is too slow. 🧊
- **Hu–Tucker** is the classical alternative for optimal alphabetic trees; **Hu–Shing** solves matrix chain in $O(n\log n)$ — both are research-level, rarely seen in contests.
- **Knuth for the partition DP** is often the cleanest way to get $O(n^2)$ on problems usually taught with D&C (CF 321E, CSES 2086/2087); combined with **Aliens** it shrinks further ([Aliens trick](06-aliens-trick-wqs-binary-search.md)).
- **Total monotonicity** (SMAWK) is the common root of Knuth, D&C and the monotone-queue methods; see [D&C optimisation §7](03-divide-and-conquer-optimization.md).
- **Optimal BST with miss probabilities** (CLRS's version with dummy keys $q_i$): same bound, weights include the $q$'s.

## 8. Practice ladder

Knuth's bound is rare on Codeforces (most interval DPs there have costs that depend on the split point); practise on these:

- [ ] [AtCoder DP N · Slimes](https://atcoder.jp/contests/dp/tasks/dp_n) — $O(n^3)$ passes; re-solve with the bound and compare, ≈1700 (est.)
- [ ] [LC 1547 · Minimum Cost to Cut a Stick](https://leetcode.com/problems/minimum-cost-to-cut-a-stick/) — Hard — shared-boundary form (Example 1)
- [ ] [CSES 2088 · Knuth Division](https://cses.fi/problemset/task/2088) — the textbook case, ≈2200 (est.) (Example 2)
- [ ] [CSES 2086 · Subarray Squares](https://cses.fi/problemset/task/2086) — layered Knuth, $O(n^2)$ for every $k$, ≈2200 (est.)
- [ ] [CSES 2087 · Houses and Schools](https://cses.fi/problemset/task/2087) — layered Knuth with median costs, ≈2300 (est.) (Example 4)
- [ ] [CF 321E · Ciel and Gondolas](https://codeforces.com/problemset/problem/321/E) — 2600 — layered Knuth instead of D&C
- [ ] [LC 1039 · Minimum Score Triangulation of Polygon](https://leetcode.com/problems/minimum-score-triangulation-of-polygon/) — Medium — a cost that *depends on the split*: confirm by brute force that the bound fails
- [ ] [LC 312 · Burst Balloons](https://leetcode.com/problems/burst-balloons/) — Hard — same exercise; keep the $O(n^3)$ DP

## 9. LeetCode / FAANG cross-reference

Rare in interviews as an optimisation (LeetCode limits make $O(n^3)$ interval DP pass), but the underlying interval DPs are interview staples:

- [LC 1547 · Minimum Cost to Cut a Stick](https://leetcode.com/problems/minimum-cost-to-cut-a-stick/) — Hard — the cleanest interview problem where mentioning Knuth's bound is a genuine improvement.
- [LC 1000 · Minimum Cost to Merge Stones](https://leetcode.com/problems/minimum-cost-to-merge-stones/) — Hard — the $K = 2$ case is Example 2; general $K$ needs a pile-count dimension.
- [LC 1039 · Minimum Score Triangulation of Polygon](https://leetcode.com/problems/minimum-score-triangulation-of-polygon/) — Medium — split-dependent cost; Knuth does **not** apply.
- [LC 312 · Burst Balloons](https://leetcode.com/problems/burst-balloons/) — Hard — split-dependent cost; Knuth does **not** apply.
- [LC 1130 · Minimum Cost Tree From Leaf Values](https://leetcode.com/problems/minimum-cost-tree-from-leaf-values/) — Medium — interval DP whose cost uses maxima of both sides; the intended fast solution is a monotonic stack, not Knuth.
- [LC 96 · Unique Binary Search Trees](https://leetcode.com/problems/unique-binary-search-trees/) — Medium — counts BSTs (Catalan numbers); the optimal-BST DP of Example 3 is its optimisation cousin.

## 10. Self-check

1. Write Knuth's bound for the interval form and explain the telescoping that makes the total $O(n^2)$.
2. Which two conditions on $C$ make the bound valid? Why isn't QI alone enough?
3. Prove that QI of $dp$ implies $\mathrm{opt}[i][j-1] \le \mathrm{opt}[i][j]$.
4. Why does matrix-chain multiplication fall outside the theorem?
5. For the $k$-partition DP, state the layered bound, the loop order, and the total complexity.
6. Where does the weight $W(i, j)$ in the optimal BST recurrence come from?
7. What memory does an $n = 5000$ interval DP need, and how do you reduce it?

<details><summary>Answers</summary>

1. $\mathrm{opt}[i][j-1] \le \mathrm{opt}[i][j] \le \mathrm{opt}[i+1][j]$. For a fixed length the scan sizes $\mathrm{opt}[i+1][j] - \mathrm{opt}[i][j-1] + 1$ telescope over $i$ to $O(n)$; $n$ lengths give $O(n^2)$.
2. QI ($C(a,c) + C(b,d) \le C(a,d) + C(b,c)$) and monotonicity on inclusion ($C(b,c) \le C(a,d)$). Yao's proof that $dp$ inherits QI needs monotonicity in the degenerate case where the inner interval is a single element.
3. Let $k = \mathrm{opt}[i][j-1]$, $k' < k$. Add the optimality of $k$ for $(i, j-1)$ to QI of $dp$ on $(k'+1, k+1, j-1, j)$; cancelling gives $dp[i][k] + dp[k+1][j] \le dp[i][k'] + dp[k'+1][j]$, so some optimum of $(i,j)$ is $\ge k$.
4. Its cost $p_{i-1}p_kp_j$ depends on the split $k$, so the recurrence isn't of the form $C(i,j) + \min_k(\dots)$ at all; a 4-matrix counterexample exists.
5. $\mathrm{opt}_{t-1}[i] \le \mathrm{opt}_t[i] \le \mathrm{opt}_t[i+1]$; $t$ increasing, $i$ decreasing; $O(n(n+k))$.
6. Making $r$ the root pushes every key of $i..j$ one level down, adding $\sum_{t=i}^{j} f_t$ to the cost; the root itself pays its depth $1$ through the same term.
7. Two $n \times n$ tables ($2.5\cdot10^7$ cells each): $200$ MB for `long` values plus $100$ MB for `int` optima. Use triangular/jagged rows (halves it) and `int` for optima.

</details>

See also: [cheat sheet](../99-Cheat-Sheets/07-dp-optimizations-cheatsheet.md) · [folder problems](problems.md) · [folder README](README.md)
