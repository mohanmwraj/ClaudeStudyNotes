# Prefix-Sum and Monotonic-Queue Optimisation of DP Transitions

> **Band:** 🔵 1600–2100 · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [prefix sums and difference arrays](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md), [monotonic stack and deque](../02-Core-Techniques/04-monotonic-stack-and-deque.md), [knapsack family](../06-Dynamic-Programming/02-knapsack-family.md), [DP state design](../06-Dynamic-Programming/01-dp-first-principles-and-state-design.md)
> **You can say you know this when:** you look at a transition $dp[i] = h(i) \oplus \bigoplus_{j \in S(i)} g(j)$ and classify it in seconds as *prefix sums* ($\oplus$ invertible), *monotonic deque* ($\oplus$ = min/max, both window ends non-decreasing) or *running best* ($S(i)$ a growing prefix), and you can write the amortised-$O(1)$ version — including bounded knapsack in $O(nW)$ via residue classes — from memory.

## 1. First principles — why this works

### 1.1 Where the time goes

A DP costs (number of states) × (work per state). The DPs in this file are "too slow by a factor of $n$" because every state recomputes an aggregate over a set of predecessors from scratch:

$$dp[i] \;=\; h(i) \;+\; \bigoplus_{j \in S(i)} g(j),$$

where $g(j)$ depends only on $j$ (typically $dp[j]$, or $dp[j]$ plus a term in $j$), $h(i)$ only on $i$, and $\oplus$ is $+$, $\min$ or $\max$. If $S(i)$ and $S(i+1)$ overlap almost completely, recomputing $\bigoplus_{S(i+1)}$ repeats almost all of the work done for $S(i)$. Every technique below is a way to **reuse the previous aggregate**, and which one applies is decided by exactly two questions:

1. **Is $\oplus$ invertible?** $+$ (mod $p$ or not) and XOR are: you can "subtract" an element out of an aggregate. $\min$ and $\max$ are not.
2. **How does $S(i)$ move as $i$ grows?** An arbitrary interval $[L_i, R_i]$; a sliding window whose ends $L_i, R_i$ are both non-decreasing; or a prefix $[0, R_i]$.

| $\oplus$ | Shape of $S(i)$ | Tool | Cost per state |
|---|---|---|---|
| invertible ($+$, xor) | any interval $[L_i, R_i]$ | prefix sums | $O(1)$ |
| any associative | prefix $[0, R_i]$, $R_i$ non-decreasing | running aggregate ("keep best so far") | $O(1)$ |
| $\min$ / $\max$ | window, $L_i$ and $R_i$ non-decreasing | monotonic deque | amortised $O(1)$ |
| $\min$ / $\max$ | arbitrary intervals, static values | sparse table | $O(1)$ after $O(n\log n)$ |
| $\min$ / $\max$ | arbitrary intervals, values appear online | segment tree / Fenwick | $O(\log n)$ |
| $+$ | each $j$ *pushes* to an interval of targets | difference array | $O(1)$ |

The precondition hidden in the formula is **separability**: inside the aggregate, the term may not depend on $i$ except through something you can pull outside (the $h(i)$). If it depends on $i$ through a product $m_j \cdot x_i$, you need the [convex hull trick](02-convex-hull-trick-and-li-chao-tree.md); if it is a general cost $C(j, i)$, look at [divide & conquer](03-divide-and-conquer-optimization.md) or [Knuth](04-knuth-optimization.md) optimisation.

### 1.2 Prefix sums: invertible aggregates over arbitrary intervals

Let $P[t] = \sum_{j < t} g(j)$. Then $\sum_{j=L}^{R} g(j) = P[R+1] - P[L]$ — pure telescoping, valid for any $L \le R$, in $O(1)$. Two things decide how you build $P$:

- **Layered DP** ($dp_i$ reads only $dp_{i-1}$): build $P$ over the old layer in $O(K)$, then fill the new layer. This is the Candies pattern (Example 1): $dp_i[k] = \sum_{t=0}^{\min(a_i, k)} dp_{i-1}[k-t] = P[k+1] - P[\max(0, k - a_i)]$, turning $O(NK\cdot a)$ into $O(NK)$.
- **Same-layer DP** ($dp[i]$ reads $dp[j]$, $j < i$): extend $P$ after each state, $P[i+1] = P[i] + dp[i]$.

**Pull versus push.** Sometimes the statement describes where state $j$ *goes* ("from floor $y$ you may move to any floor $x$ with $|x-y| < |y-b|$"), i.e. $j$ sends $dp[j]$ to an interval $[lo_j, hi_j]$ of targets. The set of sources of a target is then *not* an interval of $j$, but the dual trick works: add $dp[j]$ at $D[lo_j]$, subtract it at $D[hi_j+1]$, and prefix-sum $D$. Same $O(1)$ per transition.

### 1.3 Monotonic deque: min/max over a sliding window

$\min$ has no inverse, so "prefix min of the right end minus prefix min of the left end" means nothing. The replacement is a **domination argument**.

**Claim.** Suppose the window ends $L_i$ and $R_i$ never decrease, and let $j < j'$ both be in the current window with $g(j) \ge g(j')$ (for a minimum). Then $j$ is never the unique optimum of any present or future window.

*Proof.* A future window contains $j$ only if its left end is $\le j < j'$; its right end is at least the current one, which is $\ge j'$. So every future window that contains $j$ also contains $j'$, and $j'$ is at least as good. $\square$

So we may delete $j$. After deleting all dominated candidates, the survivors, read in index order, have **strictly increasing values** — which is the deque invariant:

- the window minimum is the front;
- to add index $i$: pop from the back while the back's value is $\ge g(i)$, then push $i$ (the popped ones are dominated by $i$);
- to move the left end: pop from the front while the front's index is $< L$.

**Complexity.** Each index is pushed once and popped at most once, so $n$ operations cost $O(n)$ in total — amortised $O(1)$ each, regardless of window sizes.

**Exact validity conditions.**
1. Both $L_i$ and $R_i$ are non-decreasing in $i$. (If the left end can move back, a deleted candidate could be needed again — use a sparse table or a segment tree.)
2. The key $g(j)$ of a stored candidate never changes after insertion. A term like $(i-j)^2$ inside the min breaks this; a term $h(i)$ that is the same for every $j$ does not (pull it out). Often you *make* the key static by algebra — see bounded knapsack below.
3. You only ever ask for the extreme of the current window, not the $k$-th best (for that, use a multiset or two heaps).

### 1.4 Bounded knapsack through residue classes

Item: weight $w$, value $v$, at most $c$ copies. The transition
$$nd[x] = \max_{0 \le t \le c,\; tw \le x} \big(dp[x - tw] + t v\big)$$
costs $O(c)$ per capacity. Write $x = r + qw$ with $0 \le r < w$ and substitute $p = q - t$:
$$nd[r + qw] \;=\; qv + \max_{\max(0, q-c) \,\le\, p \,\le\, q} \big(dp[r + pw] - pv\big).$$
Inside one residue class $r$, the key $dp[r+pw] - pv$ depends only on $p$ (static), and the window $[q - c, q]$ slides right as $q$ grows. That is exactly §1.3, so each item costs $O(W)$ in total over all residues, and the whole knapsack costs $O(nW)$ — versus $O(W\sum c_i)$ naively and $O(W \sum \log c_i)$ with binary splitting. For **counting** (number of ways rather than max value) the aggregate is a sum, so use a running window sum per residue instead of a deque: $nd[x] = nd[x-w] + dp[x] - dp[x - (c+1)w]$.

### 1.5 "Keep best so far": prefixes need no structure at all

When $S(i)$ is a prefix that only grows, keep one running aggregate and extend it. The real skill is **making the inside separable**:

- $\max_{j<i} (a_j + a_i + j - i) = (a_i - i) + \max_{j<i}(a_j + j)$: keep the best $a_j + j$ (LC 1014).
- Absolute-value penalties split into two prefixes:
  $$\max_{y}\big(f(y) - |x - y|\big) = \max\Big(\max_{y \le x}\big(f(y) + y\big) - x,\;\; \max_{y \ge x}\big(f(y) - y\big) + x\Big),$$
  i.e. one left-to-right and one right-to-left running maximum (LC 1937). With a window limit $|x-y| \le w$ the two halves become sliding windows → deques (Fireworks, Example 4, uses the window without the split, because the penalty $|a - x|$ there depends on the target only).
- "Any predecessor except the same colour": keep the best and second-best with different arguments (LC 1289).
- If the condition is on *values* ($j < i$ and $a_j < a_i$), $S(i)$ is a prefix in value space, not in index space: use a [Fenwick tree](../08-Data-Structures/01-fenwick-tree.md) keyed by value.

### 1.6 Windows in disguise

Statements rarely say "window". Translate:

| Statement says | Window |
|---|---|
| "every block of $k$ consecutive items contains a chosen one" | consecutive chosen positions differ by $\le k$: $j \in [i-k, i-1]$ |
| "you move at most $d$ per unit of time" | $y \in [x - d\Delta t, x + d\Delta t]$, both ends increase with $x$ |
| "the gap between supports is at most $d$" | $j \in [i - d - 1, i - 1]$ |
| "the total weight of a group is at most $M$" (positive weights) | two pointers: left end non-decreasing because prefix sums increase |
| "at most $c$ copies of an item" | window of $c+1$ multiples inside a residue class |

## 2. Formulas, definitions and identities

| Formula | Meaning / proof |
|---|---|
| $P[t] = \sum_{j<t} g(j)$, $\;\sum_{j=L}^{R} g(j) = P[R+1] - P[L]$ | telescoping; $O(n)$ build, $O(1)$ query |
| $(P[R+1] - P[L] + p) \bmod p$ | modular window sum; the $+p$ keeps C++/Java `%` non-negative |
| $D[lo] \mathrel{+}= x,\; D[hi+1] \mathrel{-}= x,\; v[t] = \sum_{s \le t} D[s]$ | push $x$ to every target in $[lo, hi]$; $O(1)$ per push, $O(n)$ to read |
| $dp_i[k] = P_{i-1}[k+1] - P_{i-1}[\max(0, k-a_i)]$ | bounded "give $0..a_i$" counting (Candies) |
| $nd[r+qw] = qv + \max_{q-c \le p \le q}(dp[r+pw] - pv)$ | bounded knapsack, max value; deque per residue, $O(W)$ per item |
| $nd[x] = nd[x-w] + dp[x] - dp[x-(c+1)w]$ | bounded knapsack, number of ways; window sum per residue |
| $\max_y (f(y) - c\lvert x-y\rvert) = \max(\max_{y\le x}(f(y)+cy) - cx,\; \max_{y \ge x}(f(y) - cy) + cx)$ | linear distance penalty, $c \ge 0$: two sweeps, $O(n)$ |
| deque invariant (min): indices $\uparrow$, keys strictly $\uparrow$ | front = window min; $n$ pushes + $\le n$ pops |
| $\sum_{r=s}^{s+k-1} \mathrm{cost}_r$ | sliding sum of $k$ consecutive results: add the new one, subtract the one $k$ back |

**Complexities.**

| Problem shape | Naive | Optimised |
|---|---|---|
| $dp[i] = \sum_{j \in [L_i, R_i]} dp[j]$ | $O(n^2)$ | $O(n)$ |
| $dp[i] = h(i) + \min_{j \in [i-k, i-1]} dp[j]$ | $O(nk)$ | $O(n)$ |
| layered: $x$ layers $\times$ window of $k$ over $n$ | $O(xnk)$ | $O(xn)$ |
| bounded knapsack, $n$ items, capacity $W$ | $O(W \sum c_i)$ | $O(nW)$ |
| $|x - y|$ penalty, $m$ layers, $n$ positions | $O(mn^2)$ | $O(mn)$ |

## 3. Implementation (C++ and Java)

**3.1 Sliding-window minimum.** Indices must be pushed in increasing order; `expire(lo)` removes everything left of the window. For a maximum, push $-v$ and negate.

```cpp
// Sliding-window minimum over a stream of (index, value) pairs pushed with increasing index.
// push: amortised O(1). expire(lo): drop indices < lo. Window maximum: push -v, negate min().
struct MinQueue {
    deque<pair<int, ll>> q;                              // indices increasing, values strictly increasing
    void push(int i, ll v) {
        while (!q.empty() && q.back().second >= v) q.pop_back();   // older and not better: never optimal again
        q.emplace_back(i, v);
    }
    void expire(int lo) { while (!q.empty() && q.front().first < lo) q.pop_front(); }
    bool empty() const { return q.empty(); }
    ll min() const { return q.front().second; }
    int argmin() const { return q.front().first; }
};
```

```java
// Sliding-window minimum; same contract as the C++ version. cap = total number of push() calls.
static class MinQueue {
    final int[] idx;
    final long[] val;
    int head = 0, tail = 0;
    MinQueue(int cap) { idx = new int[cap]; val = new long[cap]; }
    void push(int i, long v) {
        while (tail > head && val[tail - 1] >= v) tail--;
        idx[tail] = i; val[tail] = v; tail++;
    }
    void expire(int lo) { while (head < tail && idx[head] < lo) head++; }
    boolean isEmpty() { return head == tail; }
    long min() { return val[head]; }
    int argmin() { return idx[head]; }
}
```

**3.2 Push-style range transitions (difference array).** Each state $j$ adds $dp[j]$ to every target $t \in [lo_j, hi_j]$.

```cpp
// Push-style range transition: state j sends dp[j] to every t in [lo[j], hi[j]] (mod MOD).
// O(n) with a difference array instead of O(n * range).
vector<ll> pushRanges(const vector<ll>& dp, const vector<int>& lo, const vector<int>& hi, ll MOD) {
    int n = dp.size();
    vector<ll> diff(n + 1, 0), res(n);
    for (int j = 0; j < n; j++) {
        if (lo[j] > hi[j]) continue;
        diff[lo[j]] = (diff[lo[j]] + dp[j]) % MOD;
        diff[hi[j] + 1] = (diff[hi[j] + 1] - dp[j] % MOD + MOD) % MOD;
    }
    ll run = 0;
    for (int t = 0; t < n; t++) { run = (run + diff[t]) % MOD; res[t] = run; }
    return res;
}
```

```java
// Push-style range transition with a difference array; same contract as the C++ version.
static long[] pushRanges(long[] dp, int[] lo, int[] hi, long MOD) {
    int n = dp.length;
    long[] diff = new long[n + 1], res = new long[n];
    for (int j = 0; j < n; j++) {
        if (lo[j] > hi[j]) continue;
        diff[lo[j]] = (diff[lo[j]] + dp[j]) % MOD;
        diff[hi[j] + 1] = (diff[hi[j] + 1] - dp[j] % MOD + MOD) % MOD;
    }
    long run = 0;
    for (int t = 0; t < n; t++) { run = (run + diff[t]) % MOD; res[t] = run; }
    return res;
}
```

**3.3 One bounded-knapsack item in $O(W)$.** Works for "capacity at most $c$" (initialise `dp` with zeros) and "exactly $c$" (initialise with `NEG` except `dp[0] = 0`); unreachable states stay `NEG`.

```cpp
// One bounded-knapsack item: up to cnt copies of (weight w >= 1, value v).
// dp[c] = best value using capacity exactly/at most c (NEG = unreachable). O(W) per item.
// Residue r, c = r + q*w:  nd[c] = q*v + max_{q-cnt <= p <= q} (dp[r+p*w] - p*v).
vector<ll> addBounded(const vector<ll>& dp, int w, ll v, int cnt) {
    const ll NEG = LLONG_MIN / 4;
    int W = (int)dp.size() - 1;
    vector<ll> nd(W + 1);
    vector<int> dq(W / w + 2);                           // q-indices of one residue class
    for (int r = 0; r < w && r <= W; r++) {
        int head = 0, tail = 0;
        auto key = [&](int p) { return dp[r + (ll)p * w] <= NEG / 2 ? NEG : dp[r + (ll)p * w] - p * v; };
        for (int q = 0; r + (ll)q * w <= W; q++) {
            ll kq = key(q);
            while (head < tail && key(dq[tail - 1]) <= kq) tail--;
            dq[tail++] = q;
            while (dq[head] < q - cnt) head++;
            ll best = key(dq[head]);
            nd[r + q * w] = best <= NEG / 2 ? NEG : best + q * v;
        }
    }
    return nd;
}
```

```java
// One bounded-knapsack item; same contract as the C++ version.
static final long NEG = Long.MIN_VALUE / 4;
static long[] addBounded(long[] dp, int w, long v, int cnt) {
    int W = dp.length - 1;
    long[] nd = new long[W + 1];
    int[] dq = new int[W / w + 2];
    long[] key = new long[W / w + 2];                    // key[q] = dp[r+q*w] - q*v of the current residue
    for (int r = 0; r < w && r <= W; r++) {
        int head = 0, tail = 0;
        for (int q = 0; r + (long) q * w <= W; q++) {
            long d = dp[r + q * w];
            key[q] = d <= NEG / 2 ? NEG : d - q * v;
            while (head < tail && key[dq[tail - 1]] <= key[q]) tail--;
            dq[tail++] = q;
            while (dq[head] < q - cnt) head++;
            long best = key[dq[head]];
            nd[r + q * w] = best <= NEG / 2 ? NEG : best + q * v;
        }
    }
    return nd;
}
```

All three were checked against direct $O(n \cdot \text{range})$ loops on random inputs (C++ and Java).

## 4. Recognising the pattern

| Signal in the statement / your first DP | Think |
|---|---|
| Your transition is a **sum** over a contiguous range of the previous layer | prefix sums of the previous layer |
| Each state **sends** its value to a contiguous range of next states | difference array |
| Transition is $\min/\max$ over $j \in [i-k, i-1]$ or "within distance $d$" | monotonic deque |
| "At most $c$ copies", $c$ large, $W \cdot \sum c$ too big | residue classes + deque (max) or window sums (count) |
| The window is defined by a sum constraint on positive numbers | two pointers + deque |
| Predecessors are *all* $j < i$ and the term separates | running best — no data structure at all |
| $-c|x - y|$ or $+c|x - y|$ between consecutive layers | split into $y \le x$ and $y \ge x$, two sweeps |
| Inside the min you have $g(j) + m_j x_i$ | not this file: [CHT](02-convex-hull-trick-and-li-chao-tree.md) |
| The window's left end can move left | sparse table / segment tree, not a deque |

**Commonly confused with:** two pointers (the window itself) versus the deque (the *aggregate* over the window); sliding-window problems that need the median or $k$-th element (use two multisets / heaps, see [ordered sets and heaps](../08-Data-Structures/10-ordered-sets-pbds-and-heaps.md)); slope trick, which handles $|x - y|$ penalties on *convex* functions without enumerating positions ([slope trick](07-slope-trick.md)).

## 5. Worked examples (graded)

### Example 1 — Candies  ·  ★ ≈1800 (est.)

- **Source:** [AtCoder DP M · Candies](https://atcoder.jp/contests/dp/tasks/dp_m)
- **Difficulty:** ≈1800 (est.; the tool lists no rating for the Educational DP contest).
- **Problem:** $N \le 100$ children, child $i$ may receive between $0$ and $a_i \le K$ candies; count the ways to hand out exactly $K \le 10^5$ candies, modulo $10^9 + 7$.
- **Thinking from first principles:** the state is (children processed, candies used). The direct transition $dp_i[k] = \sum_{t=0}^{\min(a_i,k)} dp_{i-1}[k-t]$ costs $O(K)$ per state, $O(NK^2) = 10^{12}$ in total. The sum is over a *contiguous* range $[k - a_i, k]$ of the previous layer and $+$ is invertible, so the inner loop collapses to a prefix-sum difference. Dead end worth noting: generating functions $\prod (1 + x + \dots + x^{a_i})$ are the same computation; polynomial multiplication by $(1 - x^{a_i+1})/(1-x)$ *is* "prefix sum, then subtract a shifted copy".

<details><summary>Solution</summary>

Build $P[k+1] = P[k] + dp[k]$ over the old layer, then $dp[k] = P[k+1] - P[\max(0, k - a_i)]$. $O(NK)$ time, $O(K)$ memory. Correctness is the telescoping identity; the only trap is the modular subtraction.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    const long long MOD = 1'000'000'007;
    int n, K;
    cin >> n >> K;
    vector<long long> dp(K + 1, 0), pre(K + 2, 0);
    dp[0] = 1;                                           // zero children, zero candies: one way
    for (int i = 0; i < n; i++) {
        int a;
        cin >> a;
        for (int k = 0; k <= K; k++) pre[k + 1] = (pre[k] + dp[k]) % MOD;   // pre[k] = sum dp[0..k-1]
        for (int k = 0; k <= K; k++) {
            int lo = max(0, k - a);                      // child i takes t = k - j in [0, a]
            dp[k] = (pre[k + 1] - pre[lo] + MOD) % MOD;
        }
    }
    cout << dp[K] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        final long MOD = 1_000_000_007L;
        int n = in.nextInt(), K = in.nextInt();
        long[] dp = new long[K + 1], pre = new long[K + 2];
        dp[0] = 1;
        for (int i = 0; i < n; i++) {
            int a = in.nextInt();
            for (int k = 0; k <= K; k++) pre[k + 1] = (pre[k] + dp[k]) % MOD;
            for (int k = 0; k <= K; k++) {
                int lo = Math.max(0, k - a);
                dp[k] = (pre[k + 1] - pre[lo] + MOD) % MOD;   // Java % keeps the sign: add MOD first
            }
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(dp[K]);
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
3 4
1 2 3
out:
5
-->
<!-- test
in:
1 7
0
out:
0
-->
<!-- test
in:
2 0
0 0
out:
1
-->
<!-- test
in:
4 12
3 3 3 3
out:
1
-->

### Example 2 — Rudolf and k Bridges  ·  ★ 1600

- **Source:** [CF 1941E · Rudolf and k Bridges](https://codeforces.com/problemset/problem/1941/E) — 1600
- **Difficulty:** 1600
- **Problem:** $t$ test cases. A grid of $n \le 100$ rows and $m \le 2\cdot 10^5$ columns ($nm \le 2\cdot10^5$ per test) holds depths $a_{r,j}$, with the first and last column of every row equal to $0$. A bridge along a row needs supports in the first and last column, and between two consecutive supports in columns $j_1 < j_2$ we need $j_2 - j_1 - 1 \le d$. A support in cell $(r, j)$ costs $a_{r,j} + 1$. Build bridges on $k$ **consecutive** rows, minimising the total cost.
- **Thinking from first principles:** rows are independent, so first compute the cheapest bridge for each row, then take the minimum sum of $k$ consecutive row costs (a sliding sum). For one row, let $dp[j]$ be the cheapest valid prefix with a support at column $j$: $dp[j] = a_j + 1 + \min_{j-d-1 \le p \le j-1} dp[p]$. That's $O(md)$, up to $4\cdot10^{10}$. The window $[j-d-1, j-1]$ slides right, the keys $dp[p]$ are fixed once computed, and we want a minimum — the monotonic deque applies verbatim.

<details><summary>Solution</summary>

Per row: process $j = 0, 1, \dots$; expire indices $< j - d - 1$, read the front, compute $dp[j]$, push $j$. Then a sliding sum over rows. $O(nm)$ per test. Proof: §1.3 (windows non-decreasing, static keys).

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int t;
    cin >> t;
    while (t--) {
        int n, m, k, d;
        cin >> n >> m >> k >> d;
        vector<ll> rowCost(n), dp(m);
        vector<int> dq(m);                               // deque of column indices, dp increasing
        for (int r = 0; r < n; r++) {
            int head = 0, tail = 0;
            for (int j = 0; j < m; j++) {
                ll a;
                cin >> a;
                // previous support p must satisfy j - p - 1 <= d, i.e. p >= j - d - 1
                while (head < tail && dq[head] < j - d - 1) head++;
                dp[j] = a + 1 + (j == 0 ? 0 : dp[dq[head]]);
                while (head < tail && dp[dq[tail - 1]] >= dp[j]) tail--;
                dq[tail++] = j;
            }
            rowCost[r] = dp[m - 1];
        }
        ll window = 0, best = LLONG_MAX;
        for (int r = 0; r < n; r++) {
            window += rowCost[r];
            if (r >= k) window -= rowCost[r - k];
            if (r >= k - 1) best = min(best, window);
        }
        cout << best << "\n";
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = in.nextInt();
        while (t-- > 0) {
            int n = in.nextInt(), m = in.nextInt(), k = in.nextInt(), d = in.nextInt();
            long[] rowCost = new long[n], dp = new long[m];
            int[] dq = new int[m];
            for (int r = 0; r < n; r++) {
                int head = 0, tail = 0;
                for (int j = 0; j < m; j++) {
                    long a = in.nextLong();
                    while (head < tail && dq[head] < j - d - 1) head++;
                    dp[j] = a + 1 + (j == 0 ? 0 : dp[dq[head]]);
                    while (head < tail && dp[dq[tail - 1]] >= dp[j]) tail--;
                    dq[tail++] = j;
                }
                rowCost[r] = dp[m - 1];
            }
            long window = 0, best = Long.MAX_VALUE;
            for (int r = 0; r < n; r++) {
                window += rowCost[r];
                if (r >= k) window -= rowCost[r - k];
                if (r >= k - 1) best = Math.min(best, window);
            }
            out.println(best);
        }
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
2
3 11 1 4
0 1 2 3 4 5 4 3 2 1 0
0 1 1 1 1 1 1 1 1 1 0
0 9 9 9 9 9 9 9 9 9 0
1 3 1 1
0 7 0
out:
4
2
-->
<!-- test
in:
1
3 4 2 1
0 5 1 0
0 1 5 0
0 2 2 0
out:
8
-->

### Example 3 — Pictures with Kittens (hard version)  ·  ★ 2100

- **Source:** [CF 1077F2 · Pictures with Kittens (hard version)](https://codeforces.com/problemset/problem/1077/F2) — 2100
- **Difficulty:** 2100
- **Problem:** $n \le 5000$ pictures with beauties $a_i \le 10^9$. Repost **exactly** $x$ of them so that every block of $k$ consecutive pictures contains at least one repost; maximise the total beauty of the reposted pictures, or print $-1$.
- **Thinking from first principles:** "every block of $k$ contains a repost" is equivalent to: the first repost is at position $\le k$, the last at position $\ge n-k+1$, and consecutive reposts differ by at most $k$. Put a virtual repost at position $0$ and all three conditions become "consecutive reposts differ by $\le k$" plus the end condition. State $dp[j][i]$ = best sum with $j$ reposts, the last at $i$: $dp[j][i] = a_i + \max_{i-k \le p \le i-1} dp[j-1][p]$. Naively $O(xnk) = 1.25\cdot10^{11}$. The easy version ($n \le 200$) allows that; the hard one needs the window max. Per layer $j$ the window $[i-k, i-1]$ slides right and keys are the fixed previous layer — a deque per layer, $O(xn) = 2.5\cdot10^7$.

<details><summary>Solution</summary>

Two rolling rows of length $n+1$. In layer $j$, before computing position $i$ push candidate $p = i-1$ (key `prev[p]`), expire indices $< i-k$, read the front. Unreachable states carry `NEG`; never add $a_i$ to `NEG` blindly (it is far from overflow, but you must not let `NEG + a` look reachable — hence the explicit check). Answer: $\max_{i \ge n-k+1} dp[x][i]$. Time $O(xn)$, memory $O(n)$.

The window always contains at least $p = i-1$, so the deque is never empty when read.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, k, x;
    cin >> n >> k >> x;
    vector<ll> a(n + 1);
    for (int i = 1; i <= n; i++) cin >> a[i];
    const ll NEG = LLONG_MIN / 4;                        // "impossible"; safe to add a[i] to
    vector<ll> prev(n + 1, NEG), cur(n + 1);
    prev[0] = 0;                                         // 0 reposts, virtual repost at position 0
    vector<int> dq(n + 1);
    for (int j = 1; j <= x; j++) {
        int head = 0, tail = 0;
        cur[0] = NEG;
        for (int i = 1; i <= n; i++) {
            int p = i - 1;                               // candidate p enters the window [i-k, i-1]
            while (head < tail && prev[dq[tail - 1]] <= prev[p]) tail--;
            dq[tail++] = p;
            while (dq[head] < i - k) head++;             // the gap after a repost is at most k-1
            ll best = prev[dq[head]];
            cur[i] = best == NEG ? NEG : best + a[i];
        }
        swap(prev, cur);
    }
    ll ans = NEG;
    for (int i = max(1, n - k + 1); i <= n; i++) ans = max(ans, prev[i]);
    cout << (ans == NEG ? -1 : ans) << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), k = in.nextInt(), x = in.nextInt();
        long[] a = new long[n + 1];
        for (int i = 1; i <= n; i++) a[i] = in.nextLong();
        final long NEG = Long.MIN_VALUE / 4;
        long[] prev = new long[n + 1], cur = new long[n + 1];
        Arrays.fill(prev, NEG);
        prev[0] = 0;
        int[] dq = new int[n + 1];
        for (int j = 1; j <= x; j++) {
            int head = 0, tail = 0;
            cur[0] = NEG;
            for (int i = 1; i <= n; i++) {
                int p = i - 1;
                while (head < tail && prev[dq[tail - 1]] <= prev[p]) tail--;
                dq[tail++] = p;
                while (dq[head] < i - k) head++;
                long best = prev[dq[head]];
                cur[i] = best == NEG ? NEG : best + a[i];
            }
            long[] tmp = prev; prev = cur; cur = tmp;
        }
        long ans = NEG;
        for (int i = Math.max(1, n - k + 1); i <= n; i++) ans = Math.max(ans, prev[i]);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(ans == NEG ? -1 : ans);
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
5 2 3
5 1 3 10 1
out:
18
-->
<!-- test
in:
6 1 5
10 30 30 70 10 10
out:
-1
-->
<!-- test
in:
4 3 1
1 100 1 1
out:
100
-->
<!-- test
in:
1 1 1
1000000000
out:
1000000000
-->

### Example 4 — Watching Fireworks is Fun  ·  ★ 2100

- **Source:** [CF 372C · Watching Fireworks is Fun](https://codeforces.com/problemset/problem/372/C) — 2100
- **Difficulty:** 2100
- **Problem:** a street of $n \le 1.5\cdot10^5$ sections. $m \le 300$ fireworks; firework $i$ is launched at time $t_i$ (non-decreasing) in section $a_i$ and gives $b_i - |a_i - x|$ happiness if you stand at $x$ (can be negative). You may move at most $d$ sections per unit of time and start anywhere at time $1$. Maximise total happiness.
- **Thinking from first principles:** $dp_i[x]$ = best total after firework $i$ standing at $x$: $dp_i[x] = b_i - |a_i - x| + \max_{|y - x| \le w_i} dp_{i-1}[y]$ with $w_i = d(t_i - t_{i-1})$. Naively $O(mn^2)$. The penalty depends only on the target $x$, so it sits outside the max — the inside is a pure window maximum over $y \in [x - w, x + w]$, and both ends increase with $x$. A deque per firework gives $O(mn) = 4.5\cdot10^7$. Note $w$ can be astronomically large ($d \cdot 10^9$): clamp it to $n$, and compute it in 64 bits.

<details><summary>Solution</summary>

For each firework sweep $x = 1..n$, pushing positions up to $x + w$ into a max-deque and expiring positions $< x - w$. The window is never empty because it contains $x$ itself. The first firework uses $w = n$ (start anywhere). Time $O(mn)$, memory $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    ll d;
    cin >> n >> m >> d;
    vector<ll> prev(n + 1, 0), cur(n + 1);              // positions 1..n
    vector<int> dq(n + 1);
    ll lastT = 0;
    for (int f = 0; f < m; f++) {
        ll a, b, t;
        cin >> a >> b >> t;
        ll w = (f == 0) ? n : min<ll>(n, (t - lastT) * d);   // reach radius; first: anywhere
        lastT = t;
        int head = 0, tail = 0, nxt = 1;                 // nxt = next position to push
        for (int x = 1; x <= n; x++) {
            while (nxt <= n && nxt <= x + w) {           // window [x-w, x+w] grows on the right
                while (head < tail && prev[dq[tail - 1]] <= prev[nxt]) tail--;
                dq[tail++] = nxt++;
            }
            while (dq[head] < x - w) head++;             // ... and shrinks on the left
            cur[x] = prev[dq[head]] + b - llabs(a - x);
        }
        swap(prev, cur);
    }
    cout << *max_element(prev.begin() + 1, prev.end()) << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt();
        long d = in.nextLong();
        long[] prev = new long[n + 1], cur = new long[n + 1];
        int[] dq = new int[n + 1];
        long lastT = 0;
        for (int f = 0; f < m; f++) {
            long a = in.nextLong(), b = in.nextLong(), t = in.nextLong();
            long w = (f == 0) ? n : Math.min(n, (t - lastT) * d);   // long: (t - lastT) * d can reach 1e14
            lastT = t;
            int head = 0, tail = 0, nxt = 1;
            for (int x = 1; x <= n; x++) {
                while (nxt <= n && nxt <= x + w) {
                    while (head < tail && prev[dq[tail - 1]] <= prev[nxt]) tail--;
                    dq[tail++] = nxt++;
                }
                while (dq[head] < x - w) head++;
                cur[x] = prev[dq[head]] + b - Math.abs(a - x);
            }
            long[] tmp = prev; prev = cur; cur = tmp;
        }
        long best = Long.MIN_VALUE;
        for (int x = 1; x <= n; x++) best = Math.max(best, prev[x]);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(best);
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
50 3 1
49 1 1
26 1 4
6 1 10
out:
-31
-->
<!-- test
in:
10 2 1
1 1000 4
9 1000 4
out:
1992
-->
<!-- test
in:
1 1 1
1 5 3
out:
5
-->

### Example 5 — Book Shop II (bounded knapsack)  ·  ★ ≈2000 (est.)

- **Source:** [CSES 1159 · Book Shop II](https://cses.fi/problemset/task/1159)
- **Difficulty:** ≈2000 (est.)
- **Problem:** $n \le 100$ book types; type $i$ costs $h_i$, has $s_i$ pages and there are $k_i \le 1000$ copies. With budget $x \le 10^5$, maximise the total number of pages.
- **Thinking from first principles:** plain 0/1 knapsack over all copies is $x \cdot \sum k_i = 10^{10}$. Binary splitting (copies $1, 2, 4, \dots$) gives $x \sum \log k_i \approx 10^8$ — it passes, but it is not the idea worth learning. The residue-class rewrite of §1.4 turns each type into one sliding-window maximum per residue mod $h_i$, $O(x)$ per type, $10^7$ in total.

<details><summary>Solution</summary>

For each type and each residue $r < h$, walk $q = 0, 1, \dots$ over capacities $r + qh$, keeping a deque of $q$-indices whose keys $dp[r+ph] - ps$ decrease; expire $p < q - k$. Then $nd[r + qh] = \text{key}(\text{front}) + qs$. `dp` starts at all zeros because the budget is "at most $x$". Proof: §1.4; complexity $O(nx)$ time, $O(x)$ memory.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, X;
    cin >> n >> X;
    vector<int> h(n), s(n), k(n);
    for (auto& v : h) cin >> v;
    for (auto& v : s) cin >> v;
    for (auto& v : k) cin >> v;
    vector<ll> dp(X + 1, 0), nd(X + 1);                  // dp[c] = max pages with price <= c
    vector<int> dq(X + 1);                               // holds q-indices inside one residue class
    for (int i = 0; i < n; i++) {
        int w = h[i];
        for (int r = 0; r < w && r <= X; r++) {
            int head = 0, tail = 0;
            for (int q = 0; r + q * w <= X; q++) {       // c = r + q*w
                // candidate p contributes dp[r+p*w] - p*s; keep a decreasing deque of those values
                ll val = dp[r + q * w] - (ll)q * s[i];
                while (head < tail && dp[r + dq[tail - 1] * w] - (ll)dq[tail - 1] * s[i] <= val) tail--;
                dq[tail++] = q;
                while (dq[head] < q - k[i]) head++;      // at most k copies: p >= q - k
                int p = dq[head];
                nd[r + q * w] = dp[r + p * w] - (ll)p * s[i] + (ll)q * s[i];
            }
        }
        swap(dp, nd);
    }
    cout << dp[X] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), X = in.nextInt();
        int[] h = new int[n], s = new int[n], k = new int[n];
        for (int i = 0; i < n; i++) h[i] = in.nextInt();
        for (int i = 0; i < n; i++) s[i] = in.nextInt();
        for (int i = 0; i < n; i++) k[i] = in.nextInt();
        long[] dp = new long[X + 1], nd = new long[X + 1];
        int[] dq = new int[X + 1];
        for (int i = 0; i < n; i++) {
            int w = h[i];
            long si = s[i];
            for (int r = 0; r < w && r <= X; r++) {
                int head = 0, tail = 0;
                for (int q = 0; r + (long) q * w <= X; q++) {
                    long val = dp[r + q * w] - q * si;
                    while (head < tail && dp[r + dq[tail - 1] * w] - dq[tail - 1] * si <= val) tail--;
                    dq[tail++] = q;
                    while (dq[head] < q - k[i]) head++;
                    int p = dq[head];
                    nd[r + q * w] = dp[r + p * w] - p * si + q * si;
                }
            }
            long[] tmp = dp; dp = nd; nd = tmp;
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(dp[X]);
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
3 10
2 6 3
8 5 4
3 5 2
out:
28
-->
<!-- test
in:
1 5
6
100
3
out:
0
-->
<!-- test
in:
2 12
3 4
5 7
4 1
out:
20
-->

## 6. Tricks, pitfalls and things to remember

1. **Store indices in the deque, not values.** You need the index to expire old candidates; read the value through the index.
2. **Push before you read** when the window includes the newest candidate ($[i-k, i-1]$ needs $i-1$ pushed before computing $i$). An off-by-one here silently allows gaps of $k+1$.
3. **Empty window = unreachable state.** Check `head < tail` (or carry a `NEG` sentinel) before reading the front. Kittens shows the sentinel route; Rudolf never has an empty window because $j-1$ is always in it.
4. **Pop with `>=` (min) or `<=` (max)** keeps the deque strictly monotone and the newest of equal keys. Both `>` and `>=` give the right *value*; they differ only in which argmin you get — matters for reconstruction and for tie-breaking rules such as the [Aliens trick](06-aliens-trick-wqs-binary-search.md).
5. **The key must be static.** If you find yourself wanting to "update" values already in the deque, your key still depends on $i$ — rewrite it (residue trick) or switch technique (CHT).
6. **Modular window sums:** `(P[r+1] - P[l] + MOD) % MOD`. In Java and C++ `%` of a negative number is negative.
7. **Overflow in the window radius:** $d \cdot \Delta t$ in Fireworks reaches $1.5\cdot 10^{14}$; compute it in `long long`/`long` and clamp to $n$ before using it as an index.
8. **Sentinels:** use `LLONG_MIN / 4` (`Long.MIN_VALUE / 4`), never `LLONG_MIN`: one addition of a negative value overflows the latter. And test reachability explicitly — `NEG + a_i` must not become "reachable".
9. **Bounded knapsack needs a second array** (or a careful in-place order): `nd[r+qh]` reads `dp` at smaller $q$ in the same residue, which an in-place update would already have overwritten.
10. **Java:** do not use `ArrayDeque<Integer>` in a hot loop — boxing and pointer chasing cost 3–5×. An `int[]` with `head`/`tail` (reset per layer) is the contest form. Reuse arrays across layers instead of reallocating; swap references.
11. **Layered memory:** rolling two rows turns $O(xn)$ memory into $O(n)$ — Kittens needs that ($5000^2$ longs = 200 MB).
12. **When the window's left end is not monotone** (e.g. $L_i$ depends on $a_i$), the deque is wrong — not slow, *wrong*. Use a sparse table (static) or a segment tree (online).
13. **A multiset "works" for sliding windows but costs $O(\log n)$ with a big constant.** Use it only when you need more than the extreme (median, $k$-th).

## 7. Going further (toward 2400–2600+)

- **Binary search + deque DP.** Many "minimise the maximum" problems become "is the answer $\le M$?" with a deque DP inside whose window is defined by two pointers on $M$ (CF 1918D Blocking Elements).
- **Monotone stack DP.** When transitions go to "the next greater element" or "everything visible", the predecessor set is maintained by a monotonic *stack*, and the DP aggregates over stack segments (CF 1407D; CF 1585F combines it with alternating-sign prefix sums).
- **Two-stack queue for any associative aggregate.** If the window ends are monotone but $\oplus$ is neither invertible nor $\min/\max$ (gcd, matrix product, "knapsack merge"), keep the window as two stacks with prefix aggregates; amortised $O(1)$ merges per step. This is how sliding-window knapsack queries are answered offline.
- **2D sliding windows.** Apply the deque to every row, then to every column of the row results: $O(nm)$ for all $a \times b$ window minima.
- **Distance penalties on convex functions.** If every layer's function is convex piecewise linear, $\max_{|y-x| \le w}$ and $+|a - x|$ can be done on breakpoints without enumerating positions — [slope trick](07-slope-trick.md) solves Fireworks-like problems with huge $n$.
- **Prefix sums over subsets** are the [SOS DP](05-sos-dp-and-subset-convolution.md) zeta transform — the same "reuse the aggregate" idea on the subset lattice.
- **Products of $j$ and $i$ inside the min** → [CHT / Li Chao](02-convex-hull-trick-and-li-chao-tree.md). **General costs with monotone optima** → [D&C](03-divide-and-conquer-optimization.md) and [Knuth](04-knuth-optimization.md).

## 8. Practice ladder

**1400–1700**
- [ ] [CF 1941E · Rudolf and k Bridges](https://codeforces.com/problemset/problem/1941/E) — 1600 — window min per row (Example 2)
- [ ] [CF 1994C · Hungry Games](https://codeforces.com/problemset/problem/1994/C) — 1600 — suffix DP with prefix sums and a pointer
- [ ] [CF 474D · Flowers](https://codeforces.com/problemset/problem/474/D) — 1700 — linear DP, then prefix sums for range queries

**1700–1900**
- [ ] [CF 1525D · Armchairs](https://codeforces.com/problemset/problem/1525/D) — 1800 — fold "best so far" into the recurrence
- [ ] [CF 2025D · Attribute Checks](https://codeforces.com/problemset/problem/2025/D) — 1800 — push range additions lazily with a difference array
- [ ] [CSES 1159 · Book Shop II](https://cses.fi/problemset/task/1159) — bounded knapsack, ≈2000 (est.) (Example 5)
- [ ] [AtCoder DP M · Candies](https://atcoder.jp/contests/dp/tasks/dp_m) — window sums, ≈1800 (est.) (Example 1)

**1900–2100**
- [ ] [CF 479E · Riding in a Lift](https://codeforces.com/problemset/problem/479/E) — 1900 — push to ranges
- [ ] [CF 1077F1 · Pictures with Kittens (easy version)](https://codeforces.com/problemset/problem/1077/F1) — 1900 — write the $O(xnk)$ DP first
- [ ] [CF 1918D · Blocking Elements](https://codeforces.com/problemset/problem/1918/D) — 1900 — binary search outside, deque inside
- [ ] [CF 1932F · Feed Cats](https://codeforces.com/problemset/problem/1932/F) — 1900 — "keep best so far" with a precomputed left limit
- [ ] [CF 940E · Cashback](https://codeforces.com/problemset/problem/940/E) — 2000 — only two segment lengths matter; window minimum
- [ ] [CF 1716D · Chip Move](https://codeforces.com/problemset/problem/1716/D) — 2000 — running sums inside residue classes
- [ ] [CF 1077F2 · Pictures with Kittens (hard version)](https://codeforces.com/problemset/problem/1077/F2) — 2100 — layered window max (Example 3)
- [ ] [CF 372C · Watching Fireworks is Fun](https://codeforces.com/problemset/problem/372/C) — 2100 — two-sided window (Example 4)

**2100+**
- [ ] [CF 1407D · Discrete Centrifugal Jumps](https://codeforces.com/problemset/problem/1407/D) — 2200 — monotonic stacks as predecessor sets
- [ ] [CF 1585F · Non-equal Neighbours](https://codeforces.com/problemset/problem/1585/F) — 2400 — inclusion–exclusion DP with a monotonic stack of minima

## 9. LeetCode / FAANG cross-reference

- [LC 239 · Sliding Window Maximum](https://leetcode.com/problems/sliding-window-maximum/) — Hard — the deque primitive itself; know it cold.
- [LC 1696 · Jump Game VI](https://leetcode.com/problems/jump-game-vi/) — Medium — $dp[i] = a_i + \max_{[i-k, i-1]} dp$: Example 2 in interview form.
- [LC 1425 · Constrained Subsequence Sum](https://leetcode.com/problems/constrained-subsequence-sum/) — Hard — same window, with $\max(0, \cdot)$ to allow starting fresh.
- [LC 2944 · Minimum Number of Coins for Fruits](https://leetcode.com/problems/minimum-number-of-coins-for-fruits/) — Medium — window $[i+1, 2i+1]$, both ends monotone.
- [LC 1499 · Max Value of Equation](https://leetcode.com/problems/max-value-of-equation/) — Hard — separate $y_i + y_j + x_i - x_j$, window on $x_i - x_j \le k$.
- [LC 1871 · Jump Game VII](https://leetcode.com/problems/jump-game-vii/) — Medium — prefix sums of reachable positions.
- [LC 1155 · Number of Dice Rolls With Target Sum](https://leetcode.com/problems/number-of-dice-rolls-with-target-sum/) — Medium — Candies with equal bounds.
- [LC 629 · K Inverse Pairs Array](https://leetcode.com/problems/k-inverse-pairs-array/) — Hard — window sum over the previous layer.
- [LC 837 · New 21 Game](https://leetcode.com/problems/new-21-game/) — Medium — probability DP with a sliding window sum.
- [LC 2902 · Count of Sub-Multisets With Bounded Sum](https://leetcode.com/problems/count-of-sub-multisets-with-bounded-sum/) — Hard — bounded knapsack *counting* via residue window sums.
- [LC 2585 · Number of Ways to Earn Points](https://leetcode.com/problems/number-of-ways-to-earn-points/) — Hard — bounded counting knapsack; small limits, but the window sum is the clean solution.
- [LC 121 · Best Time to Buy and Sell Stock](https://leetcode.com/problems/best-time-to-buy-and-sell-stock/) — Easy — "keep the minimum so far" is the whole problem.
- [LC 1014 · Best Sightseeing Pair](https://leetcode.com/problems/best-sightseeing-pair/) — Medium — separate into $(a_j + j) + (a_i - i)$.
- [LC 1937 · Maximum Number of Points with Cost](https://leetcode.com/problems/maximum-number-of-points-with-cost/) — Medium — the two-sweep split of $-|c - c'|$.
- [LC 1289 · Minimum Falling Path Sum II](https://leetcode.com/problems/minimum-falling-path-sum-ii/) — Hard — keep best and second best.

In interviews this is the most common "DP optimisation" by far: LC 1696/1425/1937 appear regularly, and the expected follow-up to an $O(nk)$ answer is exactly the deque.

## 10. Self-check

1. Why can't you get a window minimum from two prefix minima, when you can get a window sum from two prefix sums?
2. State the two conditions under which the monotonic deque is correct, and give a transition that violates each.
3. Derive the bounded-knapsack recurrence per residue class. What is the key stored in the deque, and why is it static?
4. In Kittens, why does adding a virtual repost at position $0$ handle the "first block of $k$" condition?
5. How do you turn $\max_y (f(y) - |x-y|)$ over all $y$ into $O(n)$ total work?
6. A transition sends $dp[j]$ to all targets in $[lo_j, hi_j]$. Which structure, and why isn't it a prefix sum over $j$?
7. When does a deque DP need a `NEG` sentinel, and what is the overflow-safe choice?

<details><summary>Answers</summary>

1. Sums are invertible: $\sum_{[L,R]} = P[R+1] - P[L]$. $\min$ has no inverse — knowing $\min(A \cup B)$ and $\min(A)$ tells you nothing about $\min(B)$.
2. (a) Window ends non-decreasing — violated by $j \in [i - a_i, i - 1]$ with arbitrary $a_i$ (left end jumps back). (b) Keys independent of $i$ — violated by $\min_j (dp[j] + (i-j)^2)$; that one is CHT.
3. $x = r + qw$, $p = q - t$: $nd[r+qw] = qv + \max_{q-c \le p \le q}(dp[r+pw] - pv)$. The key $dp[r+pw] - pv$ involves only $p$; the $qv$ term is common to all candidates and sits outside.
4. With a repost at $0$, "consecutive reposts differ by at most $k$" includes the pair $(0, \text{first})$, i.e. the first repost is at position $\le k$, which is exactly "the first block contains a repost".
5. Split by sign: $\max_{y \le x}(f(y) + y) - x$ (prefix running max, left to right) and $\max_{y \ge x}(f(y) - y) + x$ (suffix running max, right to left); take the larger.
6. A difference array: add at $lo_j$, subtract at $hi_j + 1$, prefix-sum over targets. The *sources* of a target $t$ are $\{j : lo_j \le t \le hi_j\}$, which need not be contiguous in $j$, so pulling via prefix sums over $j$ doesn't apply.
7. Whenever some state is unreachable (exact counts, forced positions). Use `LLONG_MIN / 4`, and check reachability before adding a value so `NEG + a` is never treated as a real answer.

</details>

See also: [cheat sheet](../99-Cheat-Sheets/07-dp-optimizations-cheatsheet.md) · [folder problems](problems.md) · [folder README](README.md)
