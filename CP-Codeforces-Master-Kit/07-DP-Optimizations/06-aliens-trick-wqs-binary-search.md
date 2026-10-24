# Aliens Trick (WQS Binary Search, Lagrangian Relaxation)

> **Band:** 🟠 2200–2600 (combinations with other optimisations 🔴) · **Priority:** ⚡ · **FAANG:** low · **Prerequisites:** [DP state design](../06-Dynamic-Programming/01-dp-first-principles-and-state-design.md), [binary search on the answer](../02-Core-Techniques/02-binary-search-and-binary-search-on-answer.md), [convex hull trick / Li Chao](02-convex-hull-trick-and-li-chao-tree.md), [min-cost flow](../12-Flows-and-Matching/04-min-cost-flow.md) (for convexity arguments)
> **You can say you know this when:** given an "exactly $k$" / "at most $k$" DP whose $k$ dimension is the bottleneck, you can argue (or test) that the optimum is convex in $k$, replace the dimension by a per-use price $\lambda$, implement the tie-break correctly, and recover $f(k)$ even when no $\lambda$ makes the DP use exactly $k$.

## 1. First principles — why this works

### 1.1 The waste

Many DPs have the shape "choose things, **exactly $k$** (or at most $k$) of them, optimise cost": $k$ segments of a partition, $k$ transactions, $k$ chosen elements, $k$ facilities. The natural state is $(i, j)$ = (position, uses so far), costing $O(nk)$ states — often $O(n^2 k)$ with the transition. If $n, k \le 2\cdot10^5$ the $k$ dimension alone kills you, while the **same DP without the limit on $k$** is $O(n)$ or $O(n \log n)$.

So ask: can we drop the constraint and still recover the constrained optimum? Economists' answer: **put a price on each use**. With a price $\lambda$ per use, the unconstrained optimiser uses many items when they are cheap and few when they are expensive; tune $\lambda$ until it "wants" $k$.

### 1.2 Lagrangian relaxation, the picture

Let $f(k)$ = optimal cost using exactly $k$ items (minimisation). Define

$$g(\lambda) = \min_{k} \big( f(k) + \lambda k \big) = \min_{\text{all solutions } x} \big(\mathrm{cost}(x) + \lambda \cdot \mathrm{uses}(x)\big).$$

The right-hand side is a DP **without** the $k$ dimension: just add $\lambda$ whenever an item is used.

Geometrically, plot the points $(k, f(k))$. For a fixed $\lambda$, $f(k) + \lambda k$ is the intercept of the line of slope $-\lambda$ through $(k, f(k))$; minimising it means pushing a line of slope $-\lambda$ up from $-\infty$ until it first touches the point set. The touched points are the minimisers. Now:

- If $f$ is **convex** ($\Delta_k = f(k) - f(k-1)$ non-decreasing), every point lies on the lower convex hull, so **every $k$ is touched by some slope**: exactly the slopes with
  $$-\Delta_{k+1} \le \lambda \le -\Delta_k \qquad (\text{the "supporting lines" of } f \text{ at } k).$$
  Then $f(k) = g(\lambda) - \lambda k$ for any such $\lambda$.
- If $f$ is not convex, points above the hull are never touched, and $g(\lambda) - \lambda k$ only gives the hull value — a lower bound, not the answer. **Convexity is the whole validity condition.**

For maximisation the mirror holds: $f$ concave, $g(\lambda) = \max_k f(k) - \lambda k$, $k$ optimal iff $\Delta_{k+1} \le \lambda \le \Delta_k$, and $f(k) = g(\lambda) + \lambda k$.

### 1.3 Monotonicity — why binary search applies

**Claim.** If $\lambda < \lambda'$, $k_1$ minimises at $\lambda$ and $k_2$ minimises at $\lambda'$, then $k_2 \le k_1$.

*Proof.* $f(k_1) + \lambda k_1 \le f(k_2) + \lambda k_2$ and $f(k_2) + \lambda' k_2 \le f(k_1) + \lambda' k_1$. Add them: $\lambda k_1 + \lambda' k_2 \le \lambda k_2 + \lambda' k_1$, i.e. $(\lambda' - \lambda)(k_1 - k_2) \ge 0$. $\square$

(No convexity needed for this part.) So "how many items the penalised optimum uses" is non-increasing in the price, and we can binary search $\lambda$.

### 1.4 The tie problem, and the fix that always works

Take "choose exactly $k$ pairwise non-adjacent elements of $[1, 1, 1]$, maximise the sum". $f(0), f(1), f(2) = 0, 1, 2$: concave but **linear**. At $\lambda < 1$ the penalised optimum takes 2 elements, at $\lambda > 1$ it takes 0, at $\lambda = 1$ every count from 0 to 2 ties. No integer — no real — $\lambda$ makes the DP *report* exactly 1. A solution that binary-searches for "count $= k$" loops forever or returns garbage.

The fix: make ties deterministic, then search with an inequality.

1. Inside the DP, compare states lexicographically: **better value first, then fewer uses**. The DP then returns $c_{\min}(\lambda)$, the smallest optimal count.
2. Find the **smallest** integer $\lambda$ with $c_{\min}(\lambda) \le k$ (for minimisation with $+\lambda$ per use; with "$-\lambda$ per use" in a maximisation it is the same predicate).
3. Answer $f(k) = g(\lambda) - \lambda k$ (min) or $g(\lambda) + \lambda k$ (max) — **with $k$, not with the returned count**.

**Proof that $k$ is optimal at that $\lambda$.** The optimal counts at $\lambda$ form the integer interval $[c_{\min}(\lambda), c_{\max}(\lambda)]$ (convexity: the touched points of a supporting line are consecutive). We know $c_{\min}(\lambda) \le k$. Suppose $k > c_{\max}(\lambda)$. By §1.3, for every $\lambda' \ge \lambda$ all optima are $\le c_{\min}(\lambda) < k$, so $k$ is optimal only for prices $< \lambda$. But $k$ *is* optimal at the integer price $-\Delta_k$ (§1.2), hence $-\Delta_k \le \lambda - 1$ and $c_{\min}(-\Delta_k) \le k$ — contradicting the minimality of $\lambda$. So $k \in [c_{\min}(\lambda), c_{\max}(\lambda)]$ and $f(k) = g(\lambda) - \lambda k$. $\square$

The symmetric recipe (ties → more uses, largest $\lambda$ with $c_{\max}(\lambda) \ge k$) is equally correct. Mixing the two is the classic bug.

**Integer prices suffice** when all costs are integers: the $\Delta_k$ are integers, so each $k$'s interval $[-\Delta_{k+1}, -\Delta_k]$ has integer endpoints. With real costs, binary search on reals (fixed iteration count) and accept $\varepsilon$ error, or scale to integers.

### 1.5 How do you know $f$ is convex?

This is the part that needs thought; the code is routine.

1. **It is a min-cost flow in disguise.** If the problem can be modelled as sending $k$ units of flow at minimum cost, $f(k)$ is convex: successive shortest augmenting paths have non-decreasing costs (each augmentation is a shortest path in a residual graph whose potentials only grow). Stock trading with $k$ transactions, $k$ non-adjacent picks on a line, $k$ disjoint intervals — all are flows on a line.
2. **Partition into $k$ groups with a Monge cost.** If $\mathrm{cost}(a, d) + \mathrm{cost}(b, c) \ge \mathrm{cost}(a, c) + \mathrm{cost}(b, d)$ for $a \le b \le c \le d$ (the quadrangle inequality of [Knuth/D&C optimisation](04-knuth-optimization.md)), the optimum over partitions into exactly $k$ consecutive groups is convex in $k$. Squared segment sums, $k$-median on a line, "variance of each group" all qualify.
3. **Exchange argument.** Take optimal solutions for $k-1$ and $k+1$ and recombine them into two solutions with $k$ uses each and total cost $\le f(k-1) + f(k+1)$; then $2f(k) \le f(k-1) + f(k+1)$.
4. **Test it.** Before trusting a proof you are unsure of, compute $f(0..K)$ with the slow DP on a few hundred random small inputs and check $\Delta$ is monotone. It takes five minutes and catches most wrong guesses (the kit's stress tests for this file did exactly this).

### 1.6 Complexity

$O\big(T_{\text{inner}} \cdot \log(\lambda_{\max} - \lambda_{\min})\big)$, where $T_{\text{inner}}$ is the unconstrained DP. $\lambda$ must range over all slopes $\Delta_k$: for minimisation of non-negative costs with decreasing $f$, $[0, f(\text{fewest}) - f(\text{most})]$ is safe; in general $[-\max|\Delta|-1, \max|\Delta|+1]$. With values up to $10^{17}$ that is ~60 iterations.

## 2. Formulas, definitions and identities

| Name | Formula | Meaning |
|---|---|---|
| Penalised optimum (min) | $g(\lambda) = \min_k f(k) + \lambda k$ | DP that adds $\lambda$ per use, no $k$ dimension |
| Penalised optimum (max) | $g(\lambda) = \max_k f(k) - \lambda k$ | DP that subtracts $\lambda$ per use |
| Slopes | $\Delta_k = f(k) - f(k-1)$ | convex $\iff$ $\Delta$ non-decreasing |
| Optimality of $k$ (min) | $-\Delta_{k+1} \le \lambda \le -\Delta_k$ | supporting line of slope $-\lambda$ touches $(k, f(k))$ |
| Optimality of $k$ (max) | $\Delta_{k+1} \le \lambda \le \Delta_k$ | concave mirror |
| Monotonicity | $\lambda < \lambda' \Rightarrow \arg\min(\lambda') \le \arg\min(\lambda)$ | §1.3, needs no convexity |
| Recovery | $f(k) = g(\lambda^\ast) \mp \lambda^\ast k$ | use $k$, not the DP's count |
| Search predicate | smallest $\lambda$ with $c_{\min}(\lambda) \le k$ | ties broken toward fewer uses |
| Duality view | $f(k) = \max_\lambda \big(g(\lambda) - \lambda k\big)$ for convex $f$ | $g$ is concave piecewise linear (min of lines); strong duality |
| "At most $k$" (min, $f$ non-increasing) | search $\lambda \ge 0$ only | if $c_{\min}(0) \le k$ the answer is $g(0)$ |
| Cost | $O(T_{\text{inner}} \log R)$ | $R$ = range of $\lambda$ |

**"At most $k$" in one line.** If more uses never hurt (min-cost $f$ non-increasing, or max-profit $f$ non-decreasing), then $\min_{j \le k} f(j)$ is reached at $\min(k, c_{\min}(0))$, so searching only $\lambda \ge 0$ handles both cases with the same formula.

**Overflow.** $\lambda k$ can be huge during the search, but you only compute it once, at $\lambda^\ast$, where $\lambda^\ast k = g(\lambda^\ast) - f(k)$ is bounded by the values the DP already handles.

## 3. Implementation (C++ and Java)

The template is always the same three pieces: an inner DP returning `(value, count)` with the lexicographic tie-break, a binary search for the smallest $\lambda$ with `count <= k`, and the recovery formula. Below it is applied to "choose **exactly** $k$ pairwise non-adjacent elements ($|a_i| \le 10^6$, $n \le 2\cdot10^5$), maximise the sum" — concave in $k$ because it is a flow on a path. Stress-tested against the $O(nk)$ DP, including negative values where exactly $k$ forces bad picks.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

// Exactly k pairwise non-adjacent elements, maximise the sum.  f(k) is concave in k.
struct Res { ll val; int cnt; };
bool better(const Res& a, const Res& b) {             // larger value, then FEWER uses
    return a.val != b.val ? a.val > b.val : a.cnt < b.cnt;
}
int n;
vector<ll> a;

Res solve(ll lambda) {                                 // max over all selections of (sum - lambda * count)
    Res skip{0, 0}, take{LLONG_MIN / 4, 0};            // best with last element not taken / taken
    for (int i = 0; i < n; i++) {
        Res nskip = better(skip, take) ? skip : take;
        Res ntake{skip.val + a[i] - lambda, skip.cnt + 1};
        skip = nskip; take = ntake;
    }
    return better(skip, take) ? skip : take;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int k;
    cin >> n >> k;                                     // guaranteed 0 <= k <= ceil(n/2)
    a.resize(n);
    for (ll& x : a) cin >> x;
    ll lo = -300'000'000'000LL, hi = 300'000'000'000LL; // must contain every slope f(k)-f(k-1)
    while (lo < hi) {                                  // smallest lambda whose min-count optimum uses <= k
        ll mid = lo + (hi - lo) / 2;                   // floor even for negative bounds
        if (solve(mid).cnt <= k) hi = mid; else lo = mid + 1;
    }
    cout << solve(lo).val + lo * k << '\n';            // f(k) = g(lambda) + lambda * k
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n;
    static long[] a;
    static long resVal; static int resCnt;            // result of solve(), avoids allocating pairs

    // max over all selections of (sum - lambda * count); ties -> fewer elements
    static void solve(long lambda) {
        long sv = 0, tv = Long.MIN_VALUE / 4;
        int sc = 0, tc = 0;
        for (int i = 0; i < n; i++) {
            long nsv; int nsc;
            if (sv > tv || (sv == tv && sc <= tc)) { nsv = sv; nsc = sc; } else { nsv = tv; nsc = tc; }
            long ntv = sv + a[i] - lambda; int ntc = sc + 1;
            sv = nsv; sc = nsc; tv = ntv; tc = ntc;
        }
        if (sv > tv || (sv == tv && sc <= tc)) { resVal = sv; resCnt = sc; } else { resVal = tv; resCnt = tc; }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        n = in.nextInt();
        int k = in.nextInt();
        a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        long lo = -300_000_000_000L, hi = 300_000_000_000L;
        while (lo < hi) {
            long mid = lo + (hi - lo) / 2;
            solve(mid);
            if (resCnt <= k) hi = mid; else lo = mid + 1;
        }
        solve(lo);
        out.println(resVal + lo * k);
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

<!-- test
in:
3 1
1 1 1
out:
1
-->
<!-- test
in:
7 3
4 9 4 1 8 8 2
out:
19
-->
<!-- test
in:
6 3
-1 -1 -1 -1 -1 -1
out:
-3
-->
<!-- test
in:
1 1
-7
out:
-7
-->
<!-- test
in:
4 0
5 6 7 8
out:
0
-->

The first test is the tie example of §1.4: the search ends at $\lambda = 1$, where the DP reports 0 picks and $g = 0$, and $g + \lambda k = 1$ is still correct.

**Range of $\lambda$.** With $|a_i| \le 10^6$, $|f| \le 10^{11}$ and every $|\Delta_k| \le 2\cdot10^{11}$, so $\pm 3\cdot10^{11}$ covers all slopes and $\lambda \cdot \text{count} \le 3\cdot10^{16}$ never overflows.

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "exactly $k$" / "at most $k$" segments, groups, transactions, picks, with $n, k$ both large | DP with a $k$ dimension that you want to delete |
| the unconstrained version is a one-dimensional DP or a greedy | inner problem for $g(\lambda)$ |
| the problem is a min-cost flow on a line, or a partition with a Monge (quadrangle-inequality) cost | $f$ is convex — Aliens is valid |
| answers for successive $k$ look like "diminishing returns" in a brute force | likely convex; verify with second differences |
| the optimum for $k+1$ is not obtained by adding to the optimum for $k$ (greedy fails) | still fine — Aliens needs convexity, not nestedness |

**Confused with:**
- *Binary search on the answer* — there the predicate is feasibility of a threshold; here it is the count chosen by a priced optimiser.
- *D&C / Knuth optimisation* — those make each of the $k$ layers cheaper ($O(kn\log n)$); Aliens removes the layers ($O(n \log R)$). They combine: Aliens outside, CHT/D&C-free inner DP inside.
- *Greedy with a regret heap* ([03 greedy with heaps](../03-Greedy-Constructive-Interactive/02-greedy-with-heaps-and-regret.md)) — for flow-on-a-line problems the regret greedy computes *all* $f(k)$ incrementally; Aliens computes one $f(k)$ with any DP.

## 5. Worked examples (graded)

### Example 1 — Stock trading with at most k transactions  ·  ★ ≈2000 (est.)

- **Source:** [LC 188 · Best Time to Buy and Sell Stock IV](https://leetcode.com/problems/best-time-to-buy-and-sell-stock-iv/) — Hard, with the limits raised to $n, k \le 2\cdot10^5$, prices $\le 10^9$.
- **Difficulty:** ≈2000 (est.) at these limits.
- **Problem:** prices $p_1..p_n$; you may hold at most one share; at most $k$ buy–sell transactions; maximise profit.
- **Thinking from first principles:** the textbook DP has states (day, transactions used, holding?) — $O(nk) = 4\cdot10^{10}$. Without the limit, the problem is the $O(n)$ two-state DP (free/holding). The profit $F(k)$ for at most $k$ transactions is concave: the problem is a min-cost flow on the timeline (each transaction is a unit of flow from a buy day to a later sell day), so marginal gains shrink. Price each buy at $\lambda$; more fee → fewer trades. "At most" with non-decreasing $F$ → search $\lambda \ge 0$ only (§2).

<details><summary>Solution</summary>

Inner DP per $\lambda$: `free`/`hold` states with (profit, #buys), ties broken toward fewer buys. Binary search $\lambda \in [0, 2\cdot10^9]$ (a fee larger than every possible gain forces zero trades). Answer $g(\lambda^\ast) + \lambda^\ast k$. If $\lambda^\ast = 0$, the unconstrained optimum already uses $\le k$ trades and the formula returns $g(0)$. Time $O(n \log 2\cdot10^9) \approx 31n$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int n;
vector<ll> p;
// Every buy pays an extra fee lambda.  Returns {best profit - lambda * #transactions, fewest transactions among optima}.
pair<ll, int> solve(ll lambda) {
    ll freeV = 0, holdV = LLONG_MIN / 4;
    int freeC = 0, holdC = 0;
    auto better = [](ll v1, int c1, ll v2, int c2) { return v1 != v2 ? v1 > v2 : c1 < c2; };
    for (int i = 0; i < n; i++) {
        ll buyV = freeV - p[i] - lambda; int buyC = freeC + 1;      // open a transaction today
        ll sellV = holdV + p[i];         int sellC = holdC;          // close it today
        if (better(sellV, sellC, freeV, freeC)) { freeV = sellV; freeC = sellC; }
        if (better(buyV, buyC, holdV, holdC)) { holdV = buyV; holdC = buyC; }
    }
    return {freeV, freeC};
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int k;
    cin >> n >> k;
    p.resize(n);
    for (ll& x : p) cin >> x;
    ll lo = 0, hi = 2'000'000'001LL;                  // a fee above every possible gain forces 0 trades
    while (lo < hi) {
        ll mid = lo + (hi - lo) / 2;
        if (solve(mid).second <= k) hi = mid; else lo = mid + 1;
    }
    cout << solve(lo).first + lo * k << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n;
    static long[] p;
    static long resV; static int resC;

    static boolean better(long v1, int c1, long v2, int c2) { return v1 != v2 ? v1 > v2 : c1 < c2; }

    static void solve(long lambda) {
        long freeV = 0, holdV = Long.MIN_VALUE / 4;
        int freeC = 0, holdC = 0;
        for (int i = 0; i < n; i++) {
            long buyV = freeV - p[i] - lambda; int buyC = freeC + 1;
            long sellV = holdV + p[i];         int sellC = holdC;
            if (better(sellV, sellC, freeV, freeC)) { freeV = sellV; freeC = sellC; }
            if (better(buyV, buyC, holdV, holdC)) { holdV = buyV; holdC = buyC; }
        }
        resV = freeV; resC = freeC;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        n = in.nextInt();
        int k = in.nextInt();
        p = new long[n];
        for (int i = 0; i < n; i++) p[i] = in.nextLong();
        long lo = 0, hi = 2_000_000_001L;
        while (lo < hi) {
            long mid = lo + (hi - lo) / 2;
            solve(mid);
            if (resC <= k) hi = mid; else lo = mid + 1;
        }
        solve(lo);
        out.println(resV + lo * k);
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

<!-- test
in:
3 2
2 4 1
out:
2
-->
<!-- test
in:
6 2
3 2 6 5 0 3
out:
7
-->
<!-- test
in:
8 3
1 9 1 9 1 9 1 9
out:
24
-->
<!-- test
in:
8 0
1 9 1 9 1 9 1 9
out:
0
-->
<!-- test
in:
1 5
7
out:
0
-->

</details>

### Example 2 — Subarray Squares  ·  ★ ≈2300 (est.)

- **Source:** [CSES 2086 · Subarray Squares](https://cses.fi/problemset/task/2086)
- **Difficulty:** ≈2300 (est.)
- **Problem:** split an array of $n$ positive integers into exactly $k$ non-empty contiguous parts minimising the sum of squares of part sums.
- **Thinking from first principles:** $dp[j][i] = \min_{t < i} dp[j-1][t] + (S_i - S_t)^2$ is $O(kn^2)$; CHT makes each layer $O(n)$ — $O(kn)$ ([CHT file](02-convex-hull-trick-and-li-chao-tree.md)), and D&C makes it $O(kn\log n)$. To get rid of $k$: the cost $(S_i - S_t)^2$ satisfies the quadrangle inequality, so $f(k)$ is convex (§1.5 item 2). Price each part at $\lambda$:
  $$h[i] = \min_{t<i} h[t] + (S_i - S_t)^2 + \lambda = S_i^2 + \lambda + \min_t \big(-2S_t \cdot S_i + h[t] + S_t^2\big),$$
  a min over lines $y = m_t x + b_t$ evaluated at $x = S_i$ — a CHT query. Ties must prefer fewer parts *inside the hull too*.

<details><summary>Solution</summary>

**Why a Li Chao tree.** The lexicographic order (value, count) between two lines is still "better on a half-line" (their value difference is linear; equal slopes make it constant), so a Li Chao tree over the query points $S_1 < \dots < S_n$ handles the tie-break with no special cases, and it never multiplies two large numbers (a monotone deque would need $\sim 10^{26}$ cross products). Values stay $\le S_n^2 + \lambda \approx 2\cdot10^{17}$.

Binary search $\lambda \in [0, S_n^2 + 1]$ for the smallest $\lambda$ with $c_{\min}(\lambda) \le k$; answer $h[n] - \lambda k$. Time $O(n \log n \log S_n^2)$, about $60$ Li Chao passes.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

// dp[i] = min_j dp[j] + (S_i - S_j)^2 + lambda.  Line of j: slope -2 S_j, intercept dp[j] + S_j^2.
struct Line { ll m, b; int c; };                      // c = number of segments used by dp[j]
int n;
vector<ll> S;                                         // prefix sums; query points are S[1..n]
vector<Line> tr;
vector<char> has;

ll eval(const Line& L, ll x) { return L.m * x + L.b; }
bool lessAt(const Line& A, const Line& B, ll x) {     // A strictly better than B at x: value, then count
    ll va = eval(A, x), vb = eval(B, x);
    return va != vb ? va < vb : A.c < B.c;
}
void insert(int node, int l, int r, Line L) {         // Li Chao over query indices l..r (x = S[idx])
    if (!has[node]) { tr[node] = L; has[node] = 1; return; }
    int mid = (l + r) / 2;
    if (lessAt(L, tr[node], S[mid])) swap(L, tr[node]);
    if (l == r) return;
    if (lessAt(L, tr[node], S[l])) insert(2 * node, l, mid, L);
    else if (lessAt(L, tr[node], S[r])) insert(2 * node + 1, mid + 1, r, L);
}
pair<ll, int> query(int node, int l, int r, int idx) {
    pair<ll, int> best{LLONG_MAX, INT_MAX};
    while (true) {
        if (!has[node]) return best;
        pair<ll, int> cur{eval(tr[node], S[idx]), tr[node].c};
        best = min(best, cur);                        // lexicographic: value, then count
        if (l == r) return best;
        int mid = (l + r) / 2;
        if (idx <= mid) { node = 2 * node; r = mid; } else { node = 2 * node + 1; l = mid + 1; }
    }
}
pair<ll, int> solve(ll lambda) {
    fill(has.begin(), has.end(), 0);
    insert(1, 1, n, Line{0, 0, 0});                   // j = 0: dp[0] = 0, S_0 = 0
    pair<ll, int> cur{0, 0};
    for (int i = 1; i <= n; i++) {
        auto q = query(1, 1, n, i);
        cur = {q.first + S[i] * S[i] + lambda, q.second + 1};
        if (i < n) insert(1, 1, n, Line{-2 * S[i], cur.first + S[i] * S[i], cur.second});
    }
    return cur;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int k;
    cin >> n >> k;
    S.assign(n + 1, 0);
    for (int i = 1; i <= n; i++) { ll x; cin >> x; S[i] = S[i - 1] + x; }
    tr.resize(4 * n + 4); has.resize(4 * n + 4);
    ll lo = 0, hi = S[n] * S[n] + 1;                  // a segment never saves more than S_n^2
    while (lo < hi) {
        ll mid = lo + (hi - lo) / 2;
        if (solve(mid).second <= k) hi = mid; else lo = mid + 1;
    }
    cout << solve(lo).first - lo * k << '\n';         // f(k) = g(lambda) - lambda * k
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n;
    static long[] S, tm, tb;                          // Li Chao node line: slope, intercept
    static int[] tc;                                  // segment count carried by the line
    static boolean[] has;

    static boolean lessAt(long m1, long b1, int c1, long m2, long b2, int c2, long x) {
        long v1 = m1 * x + b1, v2 = m2 * x + b2;
        return v1 != v2 ? v1 < v2 : c1 < c2;
    }
    static void insert(int node, int l, int r, long m, long b, int c) {
        while (true) {
            if (!has[node]) { has[node] = true; tm[node] = m; tb[node] = b; tc[node] = c; return; }
            int mid = (l + r) / 2;
            if (lessAt(m, b, c, tm[node], tb[node], tc[node], S[mid])) {   // keep the winner at mid
                long t1 = tm[node], t2 = tb[node]; int t3 = tc[node];
                tm[node] = m; tb[node] = b; tc[node] = c; m = t1; b = t2; c = t3;
            }
            if (l == r) return;
            if (lessAt(m, b, c, tm[node], tb[node], tc[node], S[l])) { node = 2 * node; r = mid; }
            else if (lessAt(m, b, c, tm[node], tb[node], tc[node], S[r])) { node = 2 * node + 1; l = mid + 1; }
            else return;
        }
    }
    static long qv; static int qc;
    static void query(int idx) {
        int node = 1, l = 1, r = n;
        qv = Long.MAX_VALUE; qc = Integer.MAX_VALUE;
        while (has[node]) {
            long v = tm[node] * S[idx] + tb[node];
            if (v < qv || (v == qv && tc[node] < qc)) { qv = v; qc = tc[node]; }
            if (l == r) return;
            int mid = (l + r) / 2;
            if (idx <= mid) { node = 2 * node; r = mid; } else { node = 2 * node + 1; l = mid + 1; }
        }
    }
    static long resV; static int resC;
    static void solve(long lambda) {
        Arrays.fill(has, false);
        insert(1, 1, n, 0, 0, 0);
        for (int i = 1; i <= n; i++) {
            query(i);
            resV = qv + S[i] * S[i] + lambda; resC = qc + 1;
            if (i < n) insert(1, 1, n, -2 * S[i], resV + S[i] * S[i], resC);
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        n = in.nextInt();
        int k = in.nextInt();
        S = new long[n + 1];
        for (int i = 1; i <= n; i++) S[i] = S[i - 1] + in.nextLong();
        tm = new long[4 * n + 4]; tb = new long[4 * n + 4]; tc = new int[4 * n + 4]; has = new boolean[4 * n + 4];
        long lo = 0, hi = S[n] * S[n] + 1;
        while (lo < hi) {
            long mid = lo + (hi - lo) / 2;
            solve(mid);
            if (resC <= k) hi = mid; else lo = mid + 1;
        }
        solve(lo);
        out.println(resV - lo * k);
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

<!-- test
in:
5 2
2 3 1 2 2
out:
50
-->
<!-- test
in:
7 3
5 1 1 1 1 1 5
out:
75
-->
<!-- test
in:
6 6
1 2 3 4 5 6
out:
91
-->
<!-- test
in:
6 1
1 2 3 4 5 6
out:
441
-->
<!-- test
in:
1 1
100000
out:
10000000000
-->

</details>

### Example 3 — New Year and Handle Change  ·  ★ 2800

- **Source:** [CF 1279F · New Year and Handle Change](https://codeforces.com/problemset/problem/1279/F) — 2800
- **Difficulty:** 2800
- **Problem:** a string of $n \le 10^6$ Latin letters; at most $k$ operations, each turns a length-$l$ substring entirely lowercase or entirely uppercase. Minimise $\min(\#\text{lowercase}, \#\text{uppercase})$ at the end.
- **Thinking from first principles:**
  1. *Decouple the two directions.* To make the lowercase count small, an operation should never produce lowercase letters, so all operations go "to uppercase"; symmetrically for the other target. Answer $= \min$ over the two targets of (bad letters) $-$ (max bad letters covered by $\le k$ segments of length $l$). If $kl \ge n$ everything can be covered: answer 0.
  2. *The covering DP.* With overlaps never useful, $dp[i] = \max(dp[i-1],\ dp[\max(0, i-l)] + \text{bad}(i-l, i])$ — but with a count dimension that is $O(nk) = 10^{12}$.
  3. *Price the segments.* Coverage with $\le k$ fixed-length segments is concave in $k$ (this is the standard approach to the problem, and our stress test against an exhaustive search over segment placements agrees on hundreds of random cases). Subtract $\lambda$ per segment, tie-break toward fewer segments, $\lambda \in [0, l+1]$ (a segment never covers more than $l$).

<details><summary>Solution</summary>

A segment ending at $i < l$ is treated as covering the prefix $(0, i]$; it is dominated by the real segment $[1, l]$, so this relaxation does not change the optimum. Per target: $\lceil \log_2(l+2) \rceil \le 21$ passes of an $O(n)$ DP. Total $\approx 4\cdot10^7$ steps.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int n, k, l;
vector<int> pre;                                     // pre[i] = #letters in s[0..i) that we want to cover
vector<ll> dv;
vector<int> dc;

// max over placements of (covered - lambda * #segments); ties -> fewer segments
pair<ll, int> solve(ll lambda) {
    dv[0] = 0; dc[0] = 0;
    for (int i = 1; i <= n; i++) {
        dv[i] = dv[i - 1]; dc[i] = dc[i - 1];       // position i is not the right end of a segment
        int j = max(0, i - l);                       // a segment ending at i covers (j, i]
        ll v = dv[j] + (pre[i] - pre[j]) - lambda;
        int c = dc[j] + 1;
        if (v > dv[i] || (v == dv[i] && c < dc[i])) { dv[i] = v; dc[i] = c; }
    }
    return {dv[n], dc[n]};
}
ll maxCovered() {                                    // best coverage with at most k segments
    ll lo = 0, hi = l + 1;                           // a fee above l makes every segment unprofitable
    while (lo < hi) {
        ll mid = lo + (hi - lo) / 2;
        if (solve(mid).second <= k) hi = mid; else lo = mid + 1;
    }
    return solve(lo).first + lo * k;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s;
    cin >> n >> k >> l >> s;
    if ((ll)k * l >= n) { cout << 0 << '\n'; return 0; }
    pre.assign(n + 1, 0); dv.assign(n + 1, 0); dc.assign(n + 1, 0);
    ll best = LLONG_MAX;
    for (int target = 0; target < 2; target++) {     // 0: cover lowercase letters, 1: cover uppercase
        for (int i = 0; i < n; i++) pre[i + 1] = pre[i] + ((islower(s[i]) != 0) == (target == 0));
        best = min(best, pre[n] - maxCovered());
    }
    cout << best << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n, k, l;
    static int[] pre, dc;
    static long[] dv;
    static long resV; static int resC;

    static void solve(long lambda) {
        dv[0] = 0; dc[0] = 0;
        for (int i = 1; i <= n; i++) {
            dv[i] = dv[i - 1]; dc[i] = dc[i - 1];
            int j = Math.max(0, i - l);
            long v = dv[j] + (pre[i] - pre[j]) - lambda;
            int c = dc[j] + 1;
            if (v > dv[i] || (v == dv[i] && c < dc[i])) { dv[i] = v; dc[i] = c; }
        }
        resV = dv[n]; resC = dc[n];
    }
    static long maxCovered() {
        long lo = 0, hi = l + 1;
        while (lo < hi) {
            long mid = lo + (hi - lo) / 2;
            solve(mid);
            if (resC <= k) hi = mid; else lo = mid + 1;
        }
        solve(lo);
        return resV + lo * k;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        n = in.nextInt(); k = in.nextInt(); l = in.nextInt();
        String s = in.next();
        if ((long) k * l >= n) { out.println(0); out.flush(); return; }
        pre = new int[n + 1]; dc = new int[n + 1]; dv = new long[n + 1];
        long best = Long.MAX_VALUE;
        for (int target = 0; target < 2; target++) {
            for (int i = 0; i < n; i++)
                pre[i + 1] = pre[i] + ((Character.isLowerCase(s.charAt(i)) == (target == 0)) ? 1 : 0);
            best = Math.min(best, pre[n] - maxCovered());
        }
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
        String next() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            StringBuilder sb = new StringBuilder();
            for (; c > ' '; c = read()) sb.append((char) c);
            return sb.toString();
        }
    }
}
```

<!-- test
in:
7 1 4
PikMike
out:
0
-->
<!-- test
in:
15 2 2
AaAaAAaaAAAAaaA
out:
2
-->
<!-- test
in:
14 2 6
aBcdEFGHIJklMn
out:
0
-->
<!-- test
in:
9 2 2
aAaAAAaaA
out:
1
-->
<!-- test
in:
1 1 1
a
out:
0
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **One tie-break rule, used everywhere.** Every `max`/`min` inside the inner DP — including inside the CHT/Li Chao/deque — must compare (value, count) lexicographically in the same direction as the search predicate. One plain `max` breaks the proof of §1.4.
2. **Never search for "count $= k$".** Linear stretches of $f$ make it unreachable (the $[1,1,1]$ example). Search for the boundary with an inequality and recover with $k$.
3. **Recover with $k$, not with the returned count.** `g + lambda * cnt` is wrong whenever several counts tie.
4. **$\lambda$'s range must contain every slope.** Too narrow and the predicate is constant on the range — you silently get an endpoint. Bound $|\Delta_k|$ by the largest possible change of the objective from one more/less use; for "at most $k$" problems $[0, \max\text{gain of one use}+1]$.
5. **Floor midpoints with negative ranges:** `lo + (hi - lo) / 2`, never `(lo + hi) / 2` (truncates toward zero for negatives → infinite loop when `hi = lo + 1 < 0`).
6. **Overflow:** compute $\lambda k$ only once at the end (§2); inside the DP all values are bounded by the unconstrained solutions.
7. **Convexity is not optional.** If $f$ is not convex the method returns the convex hull of $f$ — plausible-looking and wrong. Test second differences with a brute force.
8. **"Exactly" vs "at most".** With "at most" and monotone $f$, clamp $\lambda \ge 0$. With "exactly" and $f$ not monotone (Example in §3 with negative values), $\lambda$ must also go negative.
9. **Real-valued costs.** Prefer scaling to integers. If you must use doubles, run a fixed number of iterations (≈100) and compute the answer as $g(\lambda) - \lambda k$ with the final $\lambda$; equality ties are then unreliable, so the answer is only $\varepsilon$-accurate.
10. **Reconstruction is harder than the value.** The DP at $\lambda^\ast$ may return a solution with $c_{\min} \ne k$ uses. Producing an actual $k$-use solution needs an extra argument (e.g. combining the $c_{\min}$ and $c_{\max}$ solutions, which works for some interval problems); most contest problems ask only for the value.
11. **Java:** return `(value, count)` through two static fields or two primitive arrays — allocating a pair object per DP step inside 60 binary-search passes is the usual TLE.
12. **Multiple constraints.** Two independent "exactly" constraints can be priced by two nested binary searches (both functions must be jointly convex); the inner tie-break then needs care in both counts.

## 7. Going further (toward 2400–2600+)

- **Aliens + something inside.** The inner DP is often itself optimised: CHT in [CF 643C · Levels and Regions](https://codeforces.com/problemset/problem/643/C) — 2400, a monotone-pointer DP in [CF 321E · Ciel and Gondolas](https://codeforces.com/problemset/problem/321/E) — 2600 (also solvable by [D&C optimisation](03-divide-and-conquer-optimization.md)), a priority-queue greedy in [CF 802M3 · April Fools' Problem (hard)](https://codeforces.com/problemset/problem/802/M3) — 2900.
- **Two constraints.** [CF 739E · Gosha is hunting](https://codeforces.com/problemset/problem/739/E) — 3000: two kinds of resources with counts $a$ and $b$; price one (or both) and solve the rest by DP.
- **Many independent convex pieces.** If the objective is a sum of independent convex functions $\sum_i c_i(x_i)$ with $\sum x_i = K$, the Lagrangian says: find the price $\lambda$ at which the marginal gains cross; binary search $\lambda$ and let each piece choose independently — [CF 1661F · Teleporters](https://codeforces.com/problemset/problem/1661/F) — 2600.
- **Why the name.** The trick became famous through the IOI 2016 task "Aliens"; in Chinese training material it is called WQS binary search, after the initials of the author who popularised it there. Mathematically it is Lagrangian relaxation plus an integrality argument.
- **Representing $f$ itself.** When you need $f$ as a function (to add, shift and minimise convex functions), see [slope trick](07-slope-trick.md).

## 8. Practice ladder

- [ ] [LC 188 · Best Time to Buy and Sell Stock IV](https://leetcode.com/problems/best-time-to-buy-and-sell-stock-iv/) — Hard
- [ ] [CSES 2086 · Subarray Squares](https://cses.fi/problemset/task/2086)
- [ ] [CSES 2087 · Houses and Schools](https://cses.fi/problemset/task/2087)
- [ ] [CF 958E2 · Guard Duty (medium)](https://codeforces.com/problemset/problem/958/E2) — 2200
- [ ] [CF 643C · Levels and Regions](https://codeforces.com/problemset/problem/643/C) — 2400
- [ ] [CF 321E · Ciel and Gondolas](https://codeforces.com/problemset/problem/321/E) — 2600
- [ ] [CF 1661F · Teleporters](https://codeforces.com/problemset/problem/1661/F) — 2600
- [ ] [AtCoder ABC218 H · Red and Blue Lamps](https://atcoder.jp/contests/abc218/tasks/abc218_h)
- [ ] [CF 1279F · New Year and Handle Change](https://codeforces.com/problemset/problem/1279/F) — 2800
- [ ] [CF 802M3 · April Fools' Problem (hard)](https://codeforces.com/problemset/problem/802/M3) — 2900
- [ ] [CF 739E · Gosha is hunting](https://codeforces.com/problemset/problem/739/E) — 3000

Hints: 2087 — $k$-median on a line, price each school; 958E2 — reduce to choosing $k$ non-adjacent gaps (the §3 template with minimisation); ABC218H — price each red lamp; 1661F — price an extra teleporter per gap.

## 9. LeetCode / FAANG cross-reference

- [LC 188 · Best Time to Buy and Sell Stock IV](https://leetcode.com/problems/best-time-to-buy-and-sell-stock-iv/) — Hard — the $O(nk)$ DP is the expected answer; "what if $k$ is up to $n$?" has two good answers: $k \ge n/2$ means unlimited trades, and in general Example 1.
- [LC 123 · Best Time to Buy and Sell Stock III](https://leetcode.com/problems/best-time-to-buy-and-sell-stock-iii/) — Hard — the $k = 2$ special case; write the four-state DP.
- [LC 1478 · Allocate Mailboxes](https://leetcode.com/problems/allocate-mailboxes/) — Hard — $k$-median on a line; $O(n^2k)$ is enough there, but the cost is Monge, so both Aliens and D&C apply.

Rare in interviews: the trick needs a convexity proof that interviewers do not expect. Mentioning "the answer is convex in $k$, so a per-transaction fee plus binary search removes $k$" as a follow-up is a strong signal.

## 10. Self-check

1. Draw the points $(k, f(k))$ and explain what $g(\lambda)$ is geometrically.
2. Prove that the optimal count is non-increasing in $\lambda$. Did you need convexity?
3. Give an instance where no $\lambda$ makes the DP return exactly $k$, and explain how the recipe still returns $f(k)$.
4. Why must the answer use $k$ rather than the count returned by the DP?
5. Why are integer $\lambda$ enough for integer costs?
6. Name two structural reasons for $f(k)$ to be convex.
7. Which $\lambda$ range is safe for an "at most $k$, maximise profit" problem, and why does that handle $k$ larger than the unconstrained optimum's count?
8. Why does a Li Chao tree tolerate the lexicographic tie-break without special cases?

<details><summary>Answers</summary>

1. The minimum intercept of a line of slope $-\lambda$ that touches the point set from below; the touched points are the optimal counts.
2. Add the two optimality inequalities: $(\lambda' - \lambda)(k_1 - k_2) \ge 0$. No convexity needed.
3. Non-adjacent picks on $[1,1,1]$ with $k = 1$: counts 0 and 2 only. With ties toward fewer picks, the smallest $\lambda$ with count $\le 1$ is $\lambda = 1$, where $k = 1$ is among the tied optima, so $g(1) + 1 \cdot 1 = 1$.
4. Several counts tie at $\lambda^\ast$; $g(\lambda^\ast) \mp \lambda^\ast k$ is correct for every tied count, in particular $k$, while the returned count may differ from $k$.
5. The slopes $\Delta_k$ are integers, and each $k$ is optimal on $[-\Delta_{k+1}, -\Delta_k]$, an interval with integer endpoints.
6. Min-cost flow structure (augmenting path costs grow); partition with a Monge cost; or an explicit exchange argument.
7. $[0, (\text{max gain of one use}) + 1]$. At $\lambda = 0$ the DP is unconstrained; if it already uses $\le k$, the search stops at 0 and returns $g(0)$, which is the "at most $k$" optimum.
8. Line A beats line B (value, then count) on a half-line, because the value difference is linear; that is the only property Li Chao uses.

</details>

Back to the [folder README](README.md) · [problems](problems.md) · [cheat sheet](../99-Cheat-Sheets/07-dp-optimizations-cheatsheet.md)
