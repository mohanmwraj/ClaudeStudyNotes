# Divide and Conquer Optimisation (and Monotone Decisions)

> **Band:** 🟠 2100–2600 · **Priority:** 🔥 · **FAANG:** low · **Prerequisites:** [DP state design](../06-Dynamic-Programming/01-dp-first-principles-and-state-design.md), [interval DP](../06-Dynamic-Programming/05-interval-dp.md), [prefix sums](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md), [Mo's algorithm](../08-Data-Structures/07-sqrt-decomposition-and-mos-algorithm.md) (for the moving-window cost)
> **You can say you know this when:** for a "split the array into $k$ groups" DP you can prove (or refute, with a counterexample) the quadrangle inequality of the group cost, write the $O(kn\log n)$ divide-and-conquer layer with an $O(1)$ or moving-pointer cost, and switch to the deque-with-binary-search method when the DP depends on its own layer.

## 1. First principles — why this works

### 1.1 The DP and its waste

The archetype: split $a_1..a_n$ into $k$ consecutive groups, the cost of a group $(j, i]$ (elements $j+1..i$) being $C(j, i)$; minimise the total.
$$dp_t[i] = \min_{j < i} \big(dp_{t-1}[j] + C(j, i)\big), \qquad dp_1[i] = C(0, i), \qquad \text{answer } dp_k[n].$$
That is $k$ layers × $n$ states × $n$ candidates $= O(kn^2)$. Within one layer, let $\mathrm{opt}(i)$ be the (smallest) $j$ achieving the minimum. The waste: for every $i$ we scan all $j$, although in most natural problems **the optimal split point moves right as $i$ moves right** — if we knew $\mathrm{opt}(i) \le \mathrm{opt}(i') $ for $i < i'$, the candidate ranges of different $i$ would barely overlap.

### 1.2 Exploiting a monotone optimum: divide and conquer

Assume $\mathrm{opt}(i) \le \mathrm{opt}(i+1)$ for all $i$. Compute the middle state first:

```text
compute(l, r, optl, optr):            # fill cur[l..r]; we know opt(i) ∈ [optl, optr] for i ∈ [l, r]
    if l > r: return
    mid = (l + r) / 2
    scan j ∈ [optl, min(mid-1, optr)], take the best -> cur[mid], best
    compute(l, mid-1, optl, best)      # everything left of mid has opt ≤ best
    compute(mid+1, r, best, optr)      # everything right of mid has opt ≥ best
```

**Complexity.** The recursion has $\lceil \log_2 n \rceil$ levels. On one level the nodes' state ranges $[l, r]$ partition $[1, n]$, and their candidate ranges $[optl, optr]$ are consecutive with **only endpoints shared** (each child range starts where its left sibling's ended). So one level scans at most $n + (\text{number of nodes}) = O(n)$ candidates, and one layer costs $O(n \log n)$ evaluations of $C$. With $k$ layers: $O(kn \log n)$.

Each layer only reads the *previous* layer, so all $dp_{t-1}$ values exist when we need them — this is why D&C needs the layered form (§1.6 handles the self-referential form).

### 1.3 Why the optimum moves right: the quadrangle inequality

$C$ satisfies the **quadrangle inequality (QI)** if for all $a \le b \le c \le d$
$$C(a, c) + C(b, d) \;\le\; C(a, d) + C(b, c)$$
("two crossing intervals are no more expensive than the nested pair").

**Theorem.** If $C$ satisfies QI, then for **any** function $f$ (in particular $f = dp_{t-1}$), the largest minimiser $\mathrm{opt}(i)$ of $f(j) + C(j, i)$ is non-decreasing in $i$. (The same holds for the smallest minimiser.)

*Proof.* Suppose $b = \mathrm{opt}(i+1) < a = \mathrm{opt}(i)$. Since $a$ is optimal for $i$: $f(a) + C(a, i) \le f(b) + C(b, i)$. QI with $b < a \le i < i+1$: $C(b, i) + C(a, i+1) \le C(b, i+1) + C(a, i)$. Adding the two and cancelling gives $f(a) + C(a, i+1) \le f(b) + C(b, i+1)$: $a$ is at least as good as $b$ at $i+1$, and $a > b$, contradicting that $b$ is the *largest* minimiser for $i+1$. $\square$

Two remarks a strong solver internalises:
- The theorem says nothing about $f$. So it holds for every layer independently, and $dp$ itself needs no special property.
- QI is **sufficient, not necessary**. Sometimes $\mathrm{opt}$ is monotone for a problem-specific reason; but if you can't prove it, stress-test before trusting D&C (§6 shows costs where it silently fails).

### 1.4 Checking QI in practice

**Local QI suffices.** If $C(a, c) + C(a+1, c+1) \le C(a, c+1) + C(a+1, c)$ for all $a < c$, then QI holds for all $a \le b \le c \le d$: the inequality for $(a, b, c, d)$ is the sum of the local inequalities over the grid $[a, b) \times [c, d)$ (the intermediate terms telescope). So you only need to check "one step" — easy by hand or by a brute-force checker.

**Families that satisfy QI** (each one-line proof is worth knowing):

1. **$C(j, i) = h(P_i - P_j)$ with $h$ convex and $P$ non-decreasing** (squared sums, $|\text{length} - L|^p$, variance-like costs). With $x_1 = P_c - P_b \le x_2, x_3 \le x_4 = P_d - P_a$, $x_2 = P_c - P_a$, $x_3 = P_d - P_b$ and $x_1 + x_4 = x_2 + x_3$, convexity gives $h(x_2) + h(x_3) \le h(x_1) + h(x_4)$ — exactly QI.
2. **Number of equal pairs inside the group** (CF 868F). $C(a, d) + C(b, c) - C(a, c) - C(b, d)$ counts equal pairs with one element in $(a, b]$ and the other in $(c, d]$: non-negative.
3. **Sum of pairwise weights inside the group** with $w \ge 0$ (CF 321E): same counting argument, $\sum_{p \in (a,b], q \in (c,d]} w_{pq} \ge 0$.
4. **$k$-median on a line** (sum of distances to the group's best centre): QI holds (classic; our brute force on random instances found no violation).
5. **Distinct values in the group** satisfies the *reverse* inequality, $C(a, c) + C(b, d) \ge C(a, d) + C(b, c)$: with $S(\cdot)$ the value sets, $S(a,c) \cup S(b,d) = S(a,d)$ and $S(a,c) \cap S(b,d) \supseteq S(b,c)$, so $|S(a,c)| + |S(b,d)| \ge |S(a,d)| + |S(b,c)|$. Reverse QI is what a **maximisation** needs (negate the cost and it becomes QI), which is why D&C works for The Bakery (Example 2) — and why "minimise the number of distinct values" is *not* safe.

### 1.5 Costs that are not $O(1)$: the moving window

For costs like "equal pairs" or "distinct values" there is no prefix-sum formula, but $C(j, i)$ can be maintained for a window $[L, R]$ that moves by one element at a time (add/remove an element in $O(1)$), exactly as in Mo's algorithm. Keep one global window; each `cost(L, R)` moves it there.

**Why the total movement is $O(n \log n)$ per layer.** Inside one call, the scanned $j$ range is contiguous, so the left end sweeps $[optl, optr]$ once, and the right end sits at $mid$. Between calls, the window jumps from the parent's position to the child's: the child's $mid$ is within the parent's $[l, r]$ and its $optl$ within the parent's $[optl, optr]$. Charging each jump to the parent's ranges, every level of the recursion pays $O(n)$ in total, so $O(n \log n)$ per layer and $O(kn\log n)$ overall — the same bound as with $O(1)$ costs.

### 1.6 The self-referential form: monotone decisions with a deque

For $dp[i] = \min_{j < i} dp[j] + C(j, i)$ (one layer, $dp$ depends on itself) D&C cannot run "middle first": $dp[j]$ for the middle's candidates may not be known yet. The QI gives a stronger, *online* statement:

**Lemma.** If $j_1 < j_2$ and $j_2$ is at least as good as $j_1$ at some $i$, then $j_2$ is at least as good as $j_1$ at every $i' > i$.

*Proof.* QI with $j_1 < j_2 \le i < i'$: $C(j_1, i) + C(j_2, i') \le C(j_1, i') + C(j_2, i)$. Add $dp[j_2] + C(j_2, i) \le dp[j_1] + C(j_1, i)$ and cancel. $\square$

So, among the future positions $i+1..n$, each candidate "owns" a contiguous block, and blocks appear in candidate order. Keep a deque of (candidate, first owned position). When $dp[i]$ is final, candidate $i$ takes over a suffix: pop back blocks it wins at their first position, then binary-search the first position where it beats the last remaining candidate. Each candidate is pushed and popped once, plus one binary search: $O(n \log n)$. This also works for the layered form, but D&C is simpler there.

### 1.7 Where this sits among the other optimisations

| Situation | Method | Cost |
|---|---|---|
| layered, QI cost, $O(1)$ or moving-window cost | D&C (this file) | $O(kn\log n)$ |
| layered, QI cost, $O(1)$ cost, $k$ large | [Knuth's bound](04-knuth-optimization.md) $\mathrm{opt}_{t-1}(i) \le \mathrm{opt}_t(i) \le \mathrm{opt}_t(i+1)$ | $O(n^2)$ total |
| layered, convex in $k$ | [Aliens](06-aliens-trick-wqs-binary-search.md) + one of the 1D methods | $O(n \log n \log V)$ |
| cost = product of $i$- and $j$-terms | [CHT](02-convex-hull-trick-and-li-chao-tree.md) | $O(kn)$ or $O(kn\log)$ |
| self-referential, QI cost | deque + binary search (§1.6) | $O(n\log n)$ |

## 2. Formulas, definitions and identities

| Statement | Meaning |
|---|---|
| $C(a,c) + C(b,d) \le C(a,d) + C(b,c)$, $a \le b \le c \le d$ | quadrangle inequality (QI); "crossing $\le$ nested" |
| $C(a,c) + C(a{+}1,c{+}1) \le C(a,c{+}1) + C(a{+}1,c)$ | local QI; implies QI by summing over a grid |
| QI $\Rightarrow$ $\mathrm{opt}(i) \le \mathrm{opt}(i+1)$ for any $f$ | the D&C theorem (§1.3) |
| QI $\Rightarrow$ "later candidate, once better, stays better" | the deque lemma (§1.6) |
| $h$ convex, $P$ non-decreasing $\Rightarrow$ $h(P_i - P_j)$ satisfies QI | squared sums, $|x - L|^p$ |
| $\sum_{j<p<q\le i} [a_p = a_q]$, $\sum_{j<p<q \le i} w_{pq}$ ($w \ge 0$) | QI by counting crossing pairs |
| $|\{a_{j+1..i}\}|$ satisfies reverse QI | fine for maximisation only |
| $\max(a_{j+1..i})$, $\max \cdot \text{len} - \text{sum}$ | **reverse** QI-type: D&C is wrong for *minimising* these (§6) |
| per level: $\sum (\text{candidates}) \le n + \#\text{nodes}$ | gives $O(n\log n)$ per layer |
| moving window: $O(n\log n)$ pointer moves per layer | Mo-like cost (§1.5) |

| Variant | Time | Memory |
|---|---|---|
| naive layered | $O(kn^2)$ | $O(n)$ rolling |
| D&C, $O(1)$ cost | $O(kn\log n)$ | $O(n)$ |
| D&C, moving-window cost | $O(kn \log n)$ window moves | $O(n + V)$ |
| 1D/1D deque + binary search | $O(n \log n)$ | $O(n)$ |

## 3. Implementation (C++ and Java)

**3.1 One D&C layer with a cost callback.** Requires $\mathrm{prv}[j]$ finite for every $j \ge optl$ — start the candidate range at the first reachable state (for "$t$ groups", $j \ge t-1$). Tested against the $O(kn^2)$ DP with squared, cubic and equal-pair costs.

```cpp
// One layer of divide & conquer optimisation, for i in [l, r]:
//   cur[i] = min over j in [optl, min(i - 1, optr)] of prv[j] + C(j, i)
// Call as dncLayer(prv, cur, l, r, optl, r - 1, C). Requires opt(i) non-decreasing in i
// (guaranteed by the quadrangle inequality) and prv[j] finite for every j >= optl.
// Each recursion level scans O(r - l + optr - optl) candidates: O(n log n) cost evaluations.
template <class Cost>
void dncLayer(const vector<ll>& prv, vector<ll>& cur, int l, int r, int optl, int optr, Cost& C) {
    if (l > r) return;
    int mid = (l + r) / 2, best = optl;
    ll bestv = LLONG_MAX;
    for (int j = optl, hi = min(mid - 1, optr); j <= hi; j++) {
        ll v = prv[j] + C(j, mid);
        if (v < bestv) { bestv = v; best = j; }      // strict: the smallest optimal j
    }
    cur[mid] = bestv;
    dncLayer(prv, cur, l, mid - 1, optl, best, C);   // left half: opt <= best
    dncLayer(prv, cur, mid + 1, r, best, optr, C);   // right half: opt >= best
}
```

```java
// One layer of D&C optimisation; same contract as the C++ version.
interface Cost { long get(int j, int i); }
static void dncLayer(long[] prv, long[] cur, int l, int r, int optl, int optr, Cost C) {
    if (l > r) return;
    int mid = (l + r) >>> 1, best = optl;
    long bestv = Long.MAX_VALUE;
    for (int j = optl, hi = Math.min(mid - 1, optr); j <= hi; j++) {
        long v = prv[j] + C.get(j, mid);
        if (v < bestv) { bestv = v; best = j; }
    }
    cur[mid] = bestv;
    dncLayer(prv, cur, l, mid - 1, optl, best, C);
    dncLayer(prv, cur, mid + 1, r, best, optr, C);
}
```

**3.2 Self-referential DP with monotone decisions** (§1.6).

```cpp
// dp[0] = base; dp[i] = min over 0 <= j < i of dp[j] + C(j, i), for i = 1..n.
// Valid when C satisfies the quadrangle inequality: then a later candidate that is at least as
// good as an earlier one at some i stays at least as good for every larger i.
// Deque of (candidate, first i it owns); binary search for each new boundary: O(n log n).
template <class Cost>
vector<ll> monotoneDecisionDP(int n, ll base, Cost& C) {
    vector<ll> dp(n + 1);
    dp[0] = base;
    auto val = [&](int j, int i) { return dp[j] + C(j, i); };
    vector<int> qj(n + 1), qf(n + 1);
    int head = 0, tail = 0;
    qj[tail] = 0; qf[tail] = 1; tail++;
    for (int i = 1; i <= n; i++) {
        while (tail - head >= 2 && qf[head + 1] <= i) head++;
        dp[i] = val(qj[head], i);
        if (i == n) break;
        while (tail > head) {                        // i owns the last segment from its start on
            int p = max(qf[tail - 1], i + 1);
            if (val(i, p) <= val(qj[tail - 1], p)) tail--; else break;
        }
        if (tail == head) { qj[tail] = i; qf[tail] = i + 1; tail++; continue; }
        int lo = max(qf[tail - 1], i + 1), hi = n + 1;
        while (lo < hi) {
            int mid = (lo + hi) / 2;
            if (val(i, mid) <= val(qj[tail - 1], mid)) hi = mid; else lo = mid + 1;
        }
        if (lo <= n) { qj[tail] = i; qf[tail] = lo; tail++; }
    }
    return dp;
}
```

```java
// 1D/1D DP with monotone decisions; same contract as the C++ version (own interface so it compiles alone).
interface Cost1D { long get(int j, int i); }
static long[] monotoneDecisionDP(int n, long base, Cost1D C) {
    long[] dp = new long[n + 1];
    dp[0] = base;
    int[] qj = new int[n + 1], qf = new int[n + 1];
    int head = 0, tail = 0;
    qj[tail] = 0; qf[tail] = 1; tail++;
    for (int i = 1; i <= n; i++) {
        while (tail - head >= 2 && qf[head + 1] <= i) head++;
        dp[i] = dp[qj[head]] + C.get(qj[head], i);
        if (i == n) break;
        while (tail > head) {
            int p = Math.max(qf[tail - 1], i + 1), b = qj[tail - 1];
            if (dp[i] + C.get(i, p) <= dp[b] + C.get(b, p)) tail--; else break;
        }
        if (tail == head) { qj[tail] = i; qf[tail] = i + 1; tail++; continue; }
        int b = qj[tail - 1], lo = Math.max(qf[tail - 1], i + 1), hi = n + 1;
        while (lo < hi) {
            int mid = (lo + hi) >>> 1;
            if (dp[i] + C.get(i, mid) <= dp[b] + C.get(b, mid)) hi = mid; else lo = mid + 1;
        }
        if (lo <= n) { qj[tail] = i; qf[tail] = lo; tail++; }
    }
    return dp;
}
```

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "Split into $k$ consecutive groups / $k$ segments / $k$ gondolas / $k$ boxes", cost per group | layered partition DP |
| $n \cdot k \le$ a few $10^6$ but $n^2 k$ is too big ($n \le 10^4..10^5$, $k \le 20..800$) | D&C, $O(kn \log n)$ |
| Group cost = convex function of a sum or length | QI via §1.4 (1) |
| Group cost counts pairs inside the group | QI via §1.4 (2)/(3); moving window if no formula |
| Group cost is a max, a distinct count, a "waste" | check the *direction*: often reverse QI — fine for max-objective, wrong for min-objective |
| Cost involves a product $s_i s_j$ only | CHT is usually simpler and faster |
| $k$ up to $n$ and $O(1)$ cost | Knuth, $O(n^2)$ |
| No layers, $dp[i]$ from $dp[j]$ of the same array | deque + binary search |

**Commonly confused with:** [Knuth](04-knuth-optimization.md) (needs the extra monotonicity in the *layer* index or interval length; gives $O(n^2)$); [CHT](02-convex-hull-trick-and-li-chao-tree.md) (needs a product structure, not QI); binary search on the answer (for "minimise the maximum group" objectives like LC 410, which are not sums of group costs).

## 5. Worked examples (graded)

### Example 1 — Subarray Squares  ·  ★ ≈2200 (est.)

- **Source:** [CSES 2086 · Subarray Squares](https://cses.fi/problemset/task/2086)
- **Difficulty:** ≈2200 (est.)
- **Problem:** split $n \le 3000$ positive integers ($\le 10^5$) into exactly $k \le n$ contiguous parts, minimising the sum of the squares of the part sums.
- **Thinking from first principles:** the layered DP is $O(kn^2) = 2.7\cdot10^{10}$. The cost $C(j, i) = (S_i - S_j)^2$ is a convex function of a difference of prefix sums, so QI holds (§1.4 (1)) and $\mathrm{opt}$ is monotone: D&C gives $O(kn\log n) \approx 10^8$ cheap operations. (This cost is also a product form, so CHT per layer works too, $O(kn)$; and $f(k)$ is convex in $k$, so [Aliens](06-aliens-trick-wqs-binary-search.md) works as well. Same problem, three optimisations.)

<details><summary>Solution</summary>

Layer 1: $dp_1[i] = S_i^2$. Layer $t$: `compute(t, n, t-1, n-1)` — with $t$ groups the last split is at $j \ge t-1$. Values: $(3\cdot10^8)^2 = 9\cdot10^{16}$ fits in 64 bits. $O(kn\log n)$ time, $O(n)$ memory.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int n, k;
vector<ll> S, prv, cur;

ll cost(int j, int i) { ll s = S[i] - S[j]; return s * s; }  // group a[j+1..i]

// cur[i] = min over j in [optl, min(i-1, optr)] of prv[j] + cost(j, i), for i in [l, r]
void compute(int l, int r, int optl, int optr) {
    if (l > r) return;
    int mid = (l + r) / 2, best = optl;
    ll bestv = LLONG_MAX;
    for (int j = optl; j <= min(mid - 1, optr); j++) {
        ll v = prv[j] + cost(j, mid);
        if (v < bestv) { bestv = v; best = j; }  // strict <: smallest argmin
    }
    cur[mid] = bestv;
    compute(l, mid - 1, optl, best);
    compute(mid + 1, r, best, optr);
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    cin >> n >> k;
    S.assign(n + 1, 0);
    for (int i = 1; i <= n; i++) { ll x; cin >> x; S[i] = S[i - 1] + x; }
    prv.assign(n + 1, LLONG_MAX);
    cur.assign(n + 1, LLONG_MAX);
    for (int i = 1; i <= n; i++) prv[i] = cost(0, i);  // layer 1
    for (int t = 2; t <= k; t++) {
        fill(cur.begin(), cur.end(), LLONG_MAX);
        compute(t, n, t - 1, n - 1);  // i >= t groups need j >= t-1
        swap(prv, cur);
    }
    cout << prv[n] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n, k;
    static long[] S, prv, cur;

    static long cost(int j, int i) { long s = S[i] - S[j]; return s * s; }

    static void compute(int l, int r, int optl, int optr) {
        if (l > r) return;
        int mid = (l + r) >>> 1, best = optl;
        long bestv = Long.MAX_VALUE;
        int hi = Math.min(mid - 1, optr);
        for (int j = optl; j <= hi; j++) {
            long v = prv[j] + cost(j, mid);
            if (v < bestv) { bestv = v; best = j; }
        }
        cur[mid] = bestv;
        compute(l, mid - 1, optl, best);
        compute(mid + 1, r, best, optr);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        n = in.nextInt(); k = in.nextInt();
        S = new long[n + 1];
        for (int i = 1; i <= n; i++) S[i] = S[i - 1] + in.nextLong();
        prv = new long[n + 1]; cur = new long[n + 1];
        Arrays.fill(prv, Long.MAX_VALUE);
        for (int i = 1; i <= n; i++) prv[i] = cost(0, i);
        for (int t = 2; t <= k; t++) {
            Arrays.fill(cur, Long.MAX_VALUE);
            compute(t, n, t - 1, n - 1);
            long[] tmp = prv; prv = cur; cur = tmp;
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
8 3
2 3 1 2 2 3 4 1
out:
110
-->
<!-- test
in:
1 1
5
out:
25
-->
<!-- test
in:
5 5
1 1 1 1 1
out:
5
-->
<!-- test
in:
4 2
100000 1 1 100000
out:
20000400002
-->

### Example 2 — The Bakery  ·  ★ 2200

- **Source:** [CF 833B · The Bakery](https://codeforces.com/problemset/problem/833/B) — 2200
- **Difficulty:** 2200
- **Problem:** $n \le 35000$ cakes in a row with types $a_i \le n$; pack them into exactly $k \le \min(n, 50)$ boxes, each a non-empty contiguous segment. The value of a box is its number of distinct types; maximise the total value.
- **Thinking from first principles:** layered DP with $C(j, i) =$ distinct types in $(j, i]$, a **maximisation**. Distinct count satisfies the reverse QI (§1.4 (5)), which is exactly what monotone optima of a maximisation need (apply §1.3 to $-C$). No formula for $C$, but a window can add/remove one cake in $O(1)$ with a counter array, so use the moving-window cost. $O(kn\log n) \approx 2.8\cdot10^7$ window moves. (The intended solution uses a lazy segment tree; D&C is the shorter alternative.)

<details><summary>Solution</summary>

`cost(L, R)` moves a global window to $[L, R]$, **extending before shrinking** so counters never go negative. `compute` scans $j$ in increasing order, so the left end sweeps forward within a call. Strict `>` keeps the smallest argmax, consistently with the recursion bounds. $O(kn\log n)$ time, $O(n)$ memory.

```cpp
#include <bits/stdc++.h>
using namespace std;

int n, k;
vector<int> a, cnt, prv, cur;
int curL = 1, curR = 0, curCost = 0;                 // window a[curL..curR] and its distinct count

void add(int x) { if (cnt[x]++ == 0) curCost++; }
void rem(int x) { if (--cnt[x] == 0) curCost--; }
int cost(int L, int R) {                             // distinct values in a[L..R]
    while (curR < R) add(a[++curR]);
    while (curL > L) add(a[--curL]);
    while (curR > R) rem(a[curR--]);
    while (curL < L) rem(a[curL++]);
    return curCost;
}

// cur[i] = max over j in [optl, min(i-1, optr)] of prv[j] + distinct(j+1..i), for i in [l, r]
void compute(int l, int r, int optl, int optr) {
    if (l > r) return;
    int mid = (l + r) / 2, best = optl, bestv = INT_MIN;
    for (int j = optl, hi = min(mid - 1, optr); j <= hi; j++) {
        int v = prv[j] + cost(j + 1, mid);
        if (v > bestv) { bestv = v; best = j; }
    }
    cur[mid] = bestv;
    compute(l, mid - 1, optl, best);
    compute(mid + 1, r, best, optr);
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    cin >> n >> k;
    a.assign(n + 1, 0);
    cnt.assign(n + 1, 0);
    for (int i = 1; i <= n; i++) cin >> a[i];
    prv.assign(n + 1, 0);
    cur.assign(n + 1, 0);
    for (int i = 1; i <= n; i++) prv[i] = cost(1, i);  // one box
    for (int t = 2; t <= k; t++) {
        compute(t, n, t - 1, n - 1);                 // t boxes need at least t cakes
        swap(prv, cur);
    }
    cout << prv[n] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n, k, curL = 1, curR = 0, curCost = 0;
    static int[] a, cnt, prv, cur;

    static void add(int x) { if (cnt[x]++ == 0) curCost++; }
    static void rem(int x) { if (--cnt[x] == 0) curCost--; }
    static int cost(int L, int R) {
        while (curR < R) add(a[++curR]);
        while (curL > L) add(a[--curL]);
        while (curR > R) rem(a[curR--]);
        while (curL < L) rem(a[curL++]);
        return curCost;
    }

    static void compute(int l, int r, int optl, int optr) {
        if (l > r) return;
        int mid = (l + r) >>> 1, best = optl, bestv = Integer.MIN_VALUE;
        for (int j = optl, hi = Math.min(mid - 1, optr); j <= hi; j++) {
            int v = prv[j] + cost(j + 1, mid);
            if (v > bestv) { bestv = v; best = j; }
        }
        cur[mid] = bestv;
        compute(l, mid - 1, optl, best);
        compute(mid + 1, r, best, optr);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        n = in.nextInt(); k = in.nextInt();
        a = new int[n + 1]; cnt = new int[n + 1];
        for (int i = 1; i <= n; i++) a[i] = in.nextInt();
        prv = new int[n + 1]; cur = new int[n + 1];
        for (int i = 1; i <= n; i++) prv[i] = cost(1, i);
        for (int t = 2; t <= k; t++) {
            compute(t, n, t - 1, n - 1);
            int[] tmp = prv; prv = cur; cur = tmp;
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
4 1
1 2 2 1
out:
2
-->
<!-- test
in:
7 2
1 3 3 1 4 4 4
out:
5
-->
<!-- test
in:
8 3
7 7 8 7 7 8 1 7
out:
6
-->
<!-- test
in:
1 1
1
out:
1
-->

### Example 3 — Yet Another Minimization Problem  ·  ★ 2500

- **Source:** [CF 868F · Yet Another Minimization Problem](https://codeforces.com/problemset/problem/868/F) — 2500
- **Difficulty:** 2500
- **Problem:** $n \le 10^5$, values $a_i \le n$, $2 \le k \le \min(n, 20)$. Split into $k$ non-empty contiguous segments; the cost of a segment is the number of unordered pairs of equal elements inside it. Minimise the total.
- **Thinking from first principles:** the cost has no $O(1)$ formula, $kn^2$ is $2\cdot10^{11}$, and there is no product structure for CHT. But pair-counting costs satisfy QI (§1.4 (2)), so $\mathrm{opt}$ is monotone; and the cost of a window changes by `cnt[x]` when $x$ enters — the moving window again. This is *the* canonical D&C-with-Mo-cost problem.

<details><summary>Solution</summary>

Adding $x$ to the window adds `cnt[x]` new pairs (then increments); removing decrements first and subtracts. Total pairs fit in 64 bits ($\binom{10^5}{2} \approx 5\cdot10^9$, already beyond 32 bits). $O(kn\log n)$ window moves.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int n, k;
vector<int> a, cnt;
vector<ll> prv, cur;
int curL = 1, curR = 0;  // window a[curL..curR], initially empty
ll curCost = 0;          // number of equal pairs inside the window

inline void add(int x) { curCost += cnt[x]++; }
inline void rem(int x) { curCost -= --cnt[x]; }
ll cost(int L, int R) {  // move the window to a[L..R]; extend first, shrink second
    while (curR < R) add(a[++curR]);
    while (curL > L) add(a[--curL]);
    while (curR > R) rem(a[curR--]);
    while (curL < L) rem(a[curL++]);
    return curCost;
}

void compute(int l, int r, int optl, int optr) {
    if (l > r) return;
    int mid = (l + r) / 2, best = optl;
    ll bestv = LLONG_MAX;
    for (int j = optl, hi = min(mid - 1, optr); j <= hi; j++) {
        ll v = prv[j] + cost(j + 1, mid);
        if (v < bestv) { bestv = v; best = j; }
    }
    cur[mid] = bestv;
    compute(l, mid - 1, optl, best);
    compute(mid + 1, r, best, optr);
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    cin >> n >> k;
    a.assign(n + 1, 0);
    cnt.assign(n + 1, 0);
    for (int i = 1; i <= n; i++) cin >> a[i];
    prv.assign(n + 1, LLONG_MAX);
    cur.assign(n + 1, LLONG_MAX);
    for (int i = 1; i <= n; i++) prv[i] = cost(1, i);
    for (int t = 2; t <= k; t++) {
        compute(t, n, t - 1, n - 1);
        swap(prv, cur);
    }
    cout << prv[n] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n, k;
    static int[] a, cnt;
    static long[] prv, cur;
    static int curL = 1, curR = 0;
    static long curCost = 0;

    static void add(int x) { curCost += cnt[x]++; }
    static void rem(int x) { curCost -= --cnt[x]; }
    static long cost(int L, int R) {
        while (curR < R) add(a[++curR]);
        while (curL > L) add(a[--curL]);
        while (curR > R) rem(a[curR--]);
        while (curL < L) rem(a[curL++]);
        return curCost;
    }

    static void compute(int l, int r, int optl, int optr) {
        if (l > r) return;
        int mid = (l + r) >>> 1, best = optl;
        long bestv = Long.MAX_VALUE;
        int hi = Math.min(mid - 1, optr);
        for (int j = optl; j <= hi; j++) {
            long v = prv[j] + cost(j + 1, mid);
            if (v < bestv) { bestv = v; best = j; }
        }
        cur[mid] = bestv;
        compute(l, mid - 1, optl, best);
        compute(mid + 1, r, best, optr);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        n = in.nextInt(); k = in.nextInt();
        a = new int[n + 1]; cnt = new int[n + 1];
        for (int i = 1; i <= n; i++) a[i] = in.nextInt();
        prv = new long[n + 1]; cur = new long[n + 1];
        Arrays.fill(prv, Long.MAX_VALUE);
        for (int i = 1; i <= n; i++) prv[i] = cost(1, i);
        for (int t = 2; t <= k; t++) {
            compute(t, n, t - 1, n - 1);
            long[] tmp = prv; prv = cur; cur = tmp;
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
7 3
1 1 3 3 3 2 1
out:
1
-->
<!-- test
in:
10 2
1 2 1 2 1 2 1 2 1 2
out:
8
-->
<!-- test
in:
13 3
1 2 2 2 1 2 1 1 1 2 2 1 1
out:
9
-->
<!-- test
in:
2 2
1 1
out:
0
-->

### Example 4 — Ciel and Gondolas  ·  ★ 2600

- **Source:** [CF 321E · Ciel and Gondolas](https://codeforces.com/problemset/problem/321/E) — 2600
- **Difficulty:** 2600
- **Problem:** $n \le 4000$ people in a queue, a symmetric matrix $u_{ij} \in [0, 9]$ ($u_{ii} = 0$), $k \le \min(n, 800)$ gondolas. Split the queue into $k$ consecutive groups; a group costs the sum of $u_{pq}$ over its unordered pairs. Minimise the total.
- **Thinking from first principles:** $C(j, i) = \sum_{j < p < q \le i} u_{pq}$ is an $O(1)$ query on 2D prefix sums of $u$ (the square block, halved). Non-negative pairwise weights ⇒ QI (§1.4 (3)). D&C: $O(kn\log n) \approx 4\cdot10^7$. The input itself is $1.6\cdot10^7$ numbers — fast input is half the problem.

<details><summary>Solution</summary>

$P[i][j] = \sum_{a \le i, b \le j} u_{ab}$ in a flat `int` array (max $9 \cdot 4000^2 = 1.44\cdot10^8$ fits in `int`). $C(j, i) = (P[i][i] - P[j][i] - P[i][j] + P[j][j]) / 2$. C++ reads with one big `fread` buffer; Java uses the `DataInputStream` reader (never `Scanner` here — it would take tens of seconds). Memory $\approx 64$ MB for $P$. (Knuth's layered bound gives an $O(n^2)$ alternative — see [Knuth](04-knuth-optimization.md); Aliens + monotone queue gives $O(n \log n \log V)$.)

```cpp
#include <bits/stdc++.h>
using namespace std;

static char buf[1 << 25];
int bufLen = 0, bufPos = 0;
inline int readChar() {
    if (bufPos == bufLen) { bufLen = (int)fread(buf, 1, sizeof(buf), stdin); bufPos = 0; if (bufLen <= 0) return -1; }
    return buf[bufPos++];
}
inline int readInt() {
    int c = readChar();
    while (c != -1 && (c < '0' || c > '9')) c = readChar();
    int x = 0;
    while (c >= '0' && c <= '9') { x = x * 10 + (c - '0'); c = readChar(); }
    return x;
}

int n, k, W;               // W = n + 1, row width of the prefix table
vector<int> P, prv, cur;   // P[i*W+j] = sum of u[a][b] for a <= i, b <= j

inline int cost(int j, int i) {  // unfamiliarity of group (j, i]: pairs inside, each counted once
    return (P[i * W + i] - P[j * W + i] - P[i * W + j] + P[j * W + j]) / 2;
}

void compute(int l, int r, int optl, int optr) {
    if (l > r) return;
    int mid = (l + r) / 2, best = optl, bestv = INT_MAX;
    for (int j = optl, hi = min(mid - 1, optr); j <= hi; j++) {
        int v = prv[j] + cost(j, mid);
        if (v < bestv) { bestv = v; best = j; }
    }
    cur[mid] = bestv;
    compute(l, mid - 1, optl, best);
    compute(mid + 1, r, best, optr);
}

int main() {
    n = readInt(); k = readInt();
    W = n + 1;
    P.assign((size_t)W * W, 0);
    for (int i = 1; i <= n; i++)
        for (int j = 1; j <= n; j++)
            P[i * W + j] = readInt() + P[(i - 1) * W + j] + P[i * W + j - 1] - P[(i - 1) * W + j - 1];
    prv.assign(n + 1, INT_MAX);
    cur.assign(n + 1, INT_MAX);
    for (int i = 1; i <= n; i++) prv[i] = cost(0, i);
    for (int t = 2; t <= k; t++) {
        compute(t, n, t - 1, n - 1);
        swap(prv, cur);
    }
    printf("%d\n", prv[n]);
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n, k, W;
    static int[] P, prv, cur;

    static int cost(int j, int i) {
        return (P[i * W + i] - P[j * W + i] - P[i * W + j] + P[j * W + j]) / 2;
    }

    static void compute(int l, int r, int optl, int optr) {
        if (l > r) return;
        int mid = (l + r) >>> 1, best = optl, bestv = Integer.MAX_VALUE;
        int hi = Math.min(mid - 1, optr);
        for (int j = optl; j <= hi; j++) {
            int v = prv[j] + cost(j, mid);
            if (v < bestv) { bestv = v; best = j; }
        }
        cur[mid] = bestv;
        compute(l, mid - 1, optl, best);
        compute(mid + 1, r, best, optr);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        n = in.nextInt(); k = in.nextInt();
        W = n + 1;
        P = new int[W * W];  // one flat array: 16M ints = 64 MB, no per-row object overhead
        for (int i = 1; i <= n; i++)
            for (int j = 1; j <= n; j++)
                P[i * W + j] = in.nextInt() + P[(i - 1) * W + j] + P[i * W + j - 1] - P[(i - 1) * W + j - 1];
        prv = new int[n + 1]; cur = new int[n + 1];
        Arrays.fill(prv, Integer.MAX_VALUE);
        for (int i = 1; i <= n; i++) prv[i] = cost(0, i);
        for (int t = 2; t <= k; t++) {
            compute(t, n, t - 1, n - 1);
            int[] tmp = prv; prv = cur; cur = tmp;
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
0 0 1 1 1
0 0 1 1 1
1 1 0 0 0
1 1 0 0 0
1 1 0 0 0
out:
0
-->
<!-- test
in:
8 3
0 1 1 1 1 1 1 1
1 0 1 1 1 1 1 1
1 1 0 1 1 1 1 1
1 1 1 0 1 1 1 1
1 1 1 1 0 1 1 1
1 1 1 1 1 0 1 1
1 1 1 1 1 1 0 1
1 1 1 1 1 1 1 0
out:
7
-->
<!-- test
in:
3 2
0 2 0
2 0 3
0 3 0
out:
2
-->
<!-- test
in:
1 1
0
out:
0
-->

### Example 5 — Typesetting with a cubic penalty (monotone decisions, one layer)  ·  ★ ≈2400 (est.)

- **Source:** Original problem.
- **Difficulty:** ≈2400 (est.)
- **Problem:** $n \le 10^5$ words with lengths $1 \le w_i \le 10$ must be printed in order. A line holding words $j+1..i$ has length $T = (w_{j+1} + \dots + w_i) + (i - j - 1)$ (single spaces) and penalty $|T - L|^3$ for a target width $1 \le L \le 1000$ (lines may be longer than $L$). Minimise the total penalty.
- **Thinking from first principles:** $dp[i] = \min_{j<i} dp[j] + |Q_i - Q_j - 1 - L|^3$ with $Q_i = \sum_{t \le i}(w_t + 1)$. No layers, so D&C's "middle first" is impossible; no product form, so no CHT (the absolute value and the cube break it). But $h(x) = |x - 1 - L|^3$ is convex and $Q$ increasing, so QI holds (§1.4 (1)), and the deque lemma (§1.6) applies: $O(n \log n)$. Overflow check: $T \le 1.1\cdot10^6$, $T^3 \le 1.4\cdot10^{18}$, plus $dp \le n \cdot 1000^3 = 10^{14}$: fits in signed 64 bits.

<details><summary>Solution</summary>

Deque entries $(j, f)$: candidate $j$ is the best known for positions $f, f+1, \dots$ up to the next entry's $f$. For each $i$: drop front entries that no longer own $i$, read $dp[i]$, then insert $i$ as described in §1.6. Correctness: the lemma guarantees each candidate owns one contiguous block, so popping a block that $i$ wins at its first position is safe, and the binary-search predicate is monotone. $O(n\log n)$; stress-tested against the $O(n^2)$ DP.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int n;
ll L;
vector<ll> Q, dp;                                    // Q[i] = (w_1 + ... + w_i) + i

ll val(int j, int i) {                               // dp[j] + penalty of the line holding words j+1..i
    ll d = Q[i] - Q[j] - 1 - L;                      // line length minus the target width
    if (d < 0) d = -d;
    return dp[j] + d * d * d;
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    cin >> n >> L;
    Q.assign(n + 1, 0);
    dp.assign(n + 1, 0);
    for (int i = 1; i <= n; i++) { ll w; cin >> w; Q[i] = Q[i - 1] + w + 1; }
    // deque of (candidate j, first position where j is the best known candidate)
    vector<int> qj(n + 1), qf(n + 1);
    int head = 0, tail = 0;
    qj[tail] = 0; qf[tail] = 1; tail++;
    for (int i = 1; i <= n; i++) {
        while (tail - head >= 2 && qf[head + 1] <= i) head++;
        dp[i] = val(qj[head], i);
        if (i == n) break;
        // candidate i, once at least as good as an older one, stays so (quadrangle inequality)
        while (tail > head) {
            int p = max(qf[tail - 1], i + 1);
            if (val(i, p) <= val(qj[tail - 1], p)) tail--;   // i takes over the whole segment
            else break;
        }
        if (tail == head) { qj[tail] = i; qf[tail] = i + 1; tail++; continue; }
        int lo = max(qf[tail - 1], i + 1), hi = n + 1;  // first p where i beats the last candidate
        while (lo < hi) {
            int mid = (lo + hi) / 2;
            if (val(i, mid) <= val(qj[tail - 1], mid)) hi = mid; else lo = mid + 1;
        }
        if (lo <= n) { qj[tail] = i; qf[tail] = lo; tail++; }
    }
    cout << dp[n] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long L;
    static long[] Q, dp;

    static long val(int j, int i) {
        long d = Math.abs(Q[i] - Q[j] - 1 - L);
        return dp[j] + d * d * d;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        L = in.nextLong();
        Q = new long[n + 1]; dp = new long[n + 1];
        for (int i = 1; i <= n; i++) Q[i] = Q[i - 1] + in.nextLong() + 1;
        int[] qj = new int[n + 1], qf = new int[n + 1];
        int head = 0, tail = 0;
        qj[tail] = 0; qf[tail] = 1; tail++;
        for (int i = 1; i <= n; i++) {
            while (tail - head >= 2 && qf[head + 1] <= i) head++;
            dp[i] = val(qj[head], i);
            if (i == n) break;
            while (tail > head) {
                int p = Math.max(qf[tail - 1], i + 1);
                if (val(i, p) <= val(qj[tail - 1], p)) tail--;
                else break;
            }
            if (tail == head) { qj[tail] = i; qf[tail] = i + 1; tail++; continue; }
            int lo = Math.max(qf[tail - 1], i + 1), hi = n + 1;
            while (lo < hi) {
                int mid = (lo + hi) >>> 1;
                if (val(i, mid) <= val(qj[tail - 1], mid)) hi = mid; else lo = mid + 1;
            }
            if (lo <= n) { qj[tail] = i; qf[tail] = lo; tail++; }
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(dp[n]);
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
5 10
3 3 3 3 3
out:
28
-->
<!-- test
in:
1 1000
10
out:
970299000
-->
<!-- test
in:
6 7
1 2 3 4 5 6
out:
29
-->
<!-- test
in:
10 1
10 10 10 10 10 10 10 10 10 10
out:
7290
-->

## 6. Tricks, pitfalls and things to remember

1. **Prove (or test) QI before using D&C — the failure is silent.** Brute-force counterexamples we found with a 30-line checker (exact DP vs D&C on random tiny arrays):
   - *Maximise* the sum of squared group sums: $a = [2, 2, 1, 3]$, $k = 2$ — exact $40$, D&C $34$. Squares are QI for minimisation, reverse for maximisation.
   - *Minimise* the sum of group maxima (the cost of LC 1335): $a = [6, 7, 2, 7]$, $k = 2$ — exact $13$, D&C $14$. A max is reverse-QI.
   - *Minimise* "max × length − sum" (LC 1959's waste): $a = [3, 6, 2, 6]$, $k = 2$ — exact $4$, D&C $7$.
   - *Minimise* the number of distinct values: $a = [1, 1, 2, 1, 3, 1]$, $k = 5$ — exact $5$, D&C $6$.
2. **Keep a brute-force QI checker in your template**: evaluate $C(a,c) + C(a+1,c+1) - C(a,c+1) - C(a+1,c)$ on random small inputs. Ten seconds of work, and it catches every case above.
3. **Consistent tie-breaking.** Use the smallest (strict `<`) or the largest (`<=`) argmin throughout; both are monotone under QI, mixing them per call is not guaranteed.
4. **Candidate range $j \le mid - 1$** (non-empty groups) and $j \ge t - 1$ in layer $t$. An empty scan leaves `best` at `optl` and the state at $\infty$ — make sure that can't happen, or handle unreachable states explicitly.
5. **Moving window: extend first, then shrink** (`R` up, `L` down, then `R` down, `L` up). Shrinking first can make the window empty with $L > R + 1$ and drive counters negative.
6. **Don't reset the moving window between layers or calls** — the amortisation argument relies on continuing from where it is.
7. **Overflow:** pair counts exceed $2^{31}$ at $n = 10^5$; squared sums of $3\cdot10^8$ need 64 bits; for cubic penalties bound $T^3$ explicitly.
8. **321E-style input sizes:** $1.6\cdot10^7$ integers. C++: one `fread` into a buffer; Java: the `DataInputStream` reader (no `Scanner`, no `BufferedReader.readLine().split`).
9. **Java recursion depth is only $O(\log n)$** for D&C, so no thread trick is needed; but avoid lambdas/interfaces in the innermost loop if the time limit is tight — inline the cost as in the examples.
10. **Memory:** rolling two layers ($O(n)$) is enough unless you need reconstruction; then store $\mathrm{opt}$ per layer ($O(kn)$ ints).
11. **The self-referential form needs the deque method**, not D&C; trying "D&C on one layer" reads $dp$ values that aren't computed yet.

## 7. Going further (toward 2400–2600+)

- **Knuth's layered bound** $\mathrm{opt}_{t-1}(i) \le \mathrm{opt}_t(i) \le \mathrm{opt}_t(i+1)$ turns the whole table into $O(n^2)$ — better than $O(kn\log n)$ when $k$ is large ([Knuth](04-knuth-optimization.md)).
- **Aliens + D&C/deque.** When $f(k)$ is convex (true for QI partition costs), drop the layer index and solve one 1D DP per penalty $\lambda$ — $O(n \log n \log V)$ ([Aliens](06-aliens-trick-wqs-binary-search.md)). CF 321E and CF 1603D are standard showcases.
- **SMAWK and LARSCH.** A QI cost makes the matrix $M[i][j] = f(j) + C(j, i)$ *totally monotone*; SMAWK finds all row minima in $O(n)$, and LARSCH does the self-referential version in $O(n)$. Rarely needed in contests (the log factor is usually fine), but it's the "real" theory behind §1.
- **D&C with a data-structure cost.** If $C(j, i)$ needs a persistent segment tree or a wavelet query, D&C still bounds the *number* of queries by $O(n\log n)$ per layer.
- **CDQ divide and conquer** solves online-looking 1D recurrences offline when decisions are monotone *and* each candidate's contribution needs a structure ([CDQ](../16-IGM-Frontier/01-offline-techniques-cdq-parallel-binary-search.md)).
- **Reverse direction.** If you process $i$ decreasing, the same theory gives monotone "next split" points; useful for suffix-based DPs.

## 8. Practice ladder

**2100–2400**
- [ ] [CSES 2086 · Subarray Squares](https://cses.fi/problemset/task/2086) — prefix-sum cost, ≈2200 (est.) (Example 1)
- [ ] [CSES 2087 · Houses and Schools](https://cses.fi/problemset/task/2087) — $k$-median cost, ≈2300 (est.)
- [ ] [CF 833B · The Bakery](https://codeforces.com/problemset/problem/833/B) — 2200 — maximisation, moving window (Example 2)
- [ ] [CF 1715E · Long Way Home](https://codeforces.com/problemset/problem/1715/E) — 2400 — each flight step is a (min,+) product with a Monge matrix
- [ ] [CF 311B · Cats Transport](https://codeforces.com/problemset/problem/311/B) — 2400 — sort, then layered partition (CHT also works)
- [ ] [CF 643C · Levels and Regions](https://codeforces.com/problemset/problem/643/C) — 2400 — prefix sums of ratios give an $O(1)$ cost

**2400+**
- [ ] [CF 868F · Yet Another Minimization Problem](https://codeforces.com/problemset/problem/868/F) — 2500 — the canonical moving-window cost (Example 3)
- [ ] [CF 1527E · Partition Game](https://codeforces.com/problemset/problem/1527/E) — 2500 — span cost per value; moving window or segment tree
- [ ] [CF 321E · Ciel and Gondolas](https://codeforces.com/problemset/problem/321/E) — 2600 — 2D prefix sums, heavy input (Example 4)
- [ ] [CF 1603D · Artistic Partition](https://codeforces.com/problemset/problem/1603/D) — 3000 — number-theoretic cost; only $\log n$ layers matter
- [ ] [CF 1175G · Yet Another Partiton Problem](https://codeforces.com/problemset/problem/1175/G) — 3000 — D&C over the array combined with hull structures

## 9. LeetCode / FAANG cross-reference

Rare in interviews: the expected solutions use $O(kn^2)$ DP at $n \le 500$ or binary search on the answer. Where it applies, it's a strong "follow-up" answer:

- [LC 1478 · Allocate Mailboxes](https://leetcode.com/problems/allocate-mailboxes/) — Hard — $k$-median on a line: QI holds, so D&C (or Knuth) speeds up the layered DP.
- [LC 410 · Split Array Largest Sum](https://leetcode.com/problems/split-array-largest-sum/) — Hard — objective is a *max* of group sums: binary search on the answer is the intended solution; the partition-DP framing is still the right first model.
- [LC 1335 · Minimum Difficulty of a Job Schedule](https://leetcode.com/problems/minimum-difficulty-of-a-job-schedule/) — Hard — a trap: the group cost (maximum) violates QI for minimisation, so D&C is **wrong** here (counterexample in §6). Use the plain DP or a monotonic stack.
- [LC 1959 · Minimum Total Space Wasted With K Resizing Operations](https://leetcode.com/problems/minimum-total-space-wasted-with-k-resizing-operations/) — Medium — another trap (counterexample in §6); $O(kn^2)$ with $n \le 200$ is intended.

## 10. Self-check

1. State the quadrangle inequality and prove that it makes $\mathrm{opt}(i)$ non-decreasing for any $f$.
2. Why is one D&C layer $O(n \log n)$? What exactly bounds the work on one recursion level?
3. Why does the local QI imply the full QI?
4. Prove that $C(j,i) = (S_i - S_j)^2$ satisfies QI for positive $a_i$. Does it still for arbitrary-sign $a_i$?
5. Why does D&C work for maximising distinct counts but not for minimising them?
6. How is the moving-window cost amortised, and why must you extend before shrinking?
7. Why can't D&C handle $dp[i] = \min_{j<i} dp[j] + C(j, i)$ directly, and what replaces it?
8. Give a natural group cost for which D&C gives a wrong answer.

<details><summary>Answers</summary>

1. $C(a,c) + C(b,d) \le C(a,d) + C(b,c)$ for $a \le b \le c \le d$. If $b = \mathrm{opt}(i+1) < a = \mathrm{opt}(i)$ (largest minimisers), add $f(a) + C(a,i) \le f(b) + C(b,i)$ to QI on $(b, a, i, i+1)$ to get $f(a) + C(a, i+1) \le f(b) + C(b, i+1)$, contradicting maximality of $b$.
2. On one level the nodes' candidate ranges are consecutive and overlap only in endpoints, so the total scanned is $\le n + \#\text{nodes} = O(n)$; there are $O(\log n)$ levels.
3. Summing the local inequality over all $(a', c')$ with $a \le a' < b$, $c \le c' < d$ telescopes to the inequality for $(a, b, c, d)$.
4. It is $h(S_i - S_j)$ with $h(x) = x^2$ convex and $S$ increasing; §1.4 (1). With negative $a_i$, $S$ is not monotone and the argument breaks — and so can monotonicity of $\mathrm{opt}$.
5. Distinct counts satisfy the *reverse* QI, which is the condition for a maximisation (QI of $-C$). For minimisation you'd need QI itself, which fails (counterexample $[1,1,2,1,3,1]$, $k = 5$).
6. Within a call the left end sweeps once over the candidate range; jumps between calls are bounded by the parent's ranges, so each level costs $O(n)$ moves. Extending first keeps $L \le R + 1$ and every counter non-negative.
7. "Middle first" needs $dp[j]$ for candidates that are to the right of the already computed prefix. Use the deque of candidate blocks with binary search (§1.6), justified by "later candidate once better stays better".
8. The group maximum (LC 1335), "max × length − sum", maximising squared sums, minimising distinct counts — all have small counterexamples in §6.

</details>

See also: [cheat sheet](../99-Cheat-Sheets/07-dp-optimizations-cheatsheet.md) · [folder problems](problems.md) · [folder README](README.md)
