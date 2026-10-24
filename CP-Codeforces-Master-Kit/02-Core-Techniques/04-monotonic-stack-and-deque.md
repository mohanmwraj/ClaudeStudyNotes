# Monotonic stack and monotonic deque

> **Band:** 🔵–🟣 1400–2100 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [two pointers and sliding window](03-two-pointers-and-sliding-window.md), [prefix sums](01-prefix-sums-and-difference-arrays.md), [STL and Java collections](../01-Foundations/02-cpp-stl-and-java-collections.md)
> **You can say you know this when:** you can produce any of the four nearest greater/smaller arrays with the right strictness in one pass, prove that a popped element is never needed again, sum the minimum of every subarray with each subarray counted exactly once despite ties, and turn "sliding-window maximum" or "dp over the last $k$ states" into an $O(n)$ deque.

## 1. First principles — why this works

**The question.** For every $i$, find the nearest $j < i$ with $a_j > a_i$ (the *previous greater element*). Scanning left
from each $i$ is $\Theta(n^2)$ on an increasing array: every scan walks to the start.

**Dominance removes the waste.** Suppose $j < k$ and $a_j \le a_k$. For every *future* query $i > k$: if $a_j > a_i$ then
$a_k \ge a_j > a_i$ too, and $k$ is nearer. So $j$ can never again be an answer — $k$ dominates it **forever**, because
$k$ stays between $j$ and every later $i$. Delete every dominated index. The survivors, read left to right, have strictly
decreasing values (any non-decrease would be a domination). That sorted list of candidates is the **monotonic stack**:

- A new element $i$ dominates exactly the survivors with value $\le a_i$. Since values decrease from bottom to top, those are
  on top: pop them.
- The new top (if any) is the answer for $i$. *Proof.* Let $j^{\ast}$ be the true nearest greater. If $j^{\ast}$ had been deleted, its
  dominator $k$ ($j^{\ast} < k < i$, $a_k \ge a_{j^{\ast}} > a_i$) would be a nearer greater element — contradiction. So $j^{\ast}$ is a survivor;
  among survivors, those $> a_i$ are exactly the ones left after popping, and the nearest of them is the top.
- Push $i$ (it dominates nothing older that is still there, and is itself a candidate for the future).

**Amortised $O(n)$.** Every index is pushed once and popped at most once, so the total work is $\le 2n$ stack operations,
even though one step can pop many. (Potential $\Phi$ = stack size: a push raises it by 1, each pop lowers it by 1.)

**Free information at pop time.** When $i$ pops $j$ (because $a_j \le a_i$), $i$ is the *next greater-or-equal* element of $j$:
anything between them that was $\ge a_j$ would have popped $j$ earlier. So a single left-to-right pass yields a "previous"
array (read at push time) and a "next" array (written at pop time), and **the pop condition fixes the strictness of both**:

| Pop while | Survivor below $i$ is its | The element that pops $j$ is its |
|---|---|---|
| $a_{top} \le a_i$ | previous strictly greater | next greater-or-equal |
| $a_{top} < a_i$ | previous greater-or-equal | next strictly greater |
| $a_{top} \ge a_i$ | previous strictly smaller | next smaller-or-equal |
| $a_{top} > a_i$ | previous smaller-or-equal | next strictly smaller |

**Ranges where an element is the minimum.** With $L_i$ = previous smaller and $R_i$ = next smaller, $a_i$ is a minimum of
$[l, r] \ni i$ exactly when $L_i < l$ and $r < R_i$. That single fact drives three classics:

- *Largest rectangle in a histogram.* An optimal rectangle's height equals the lowest bar it covers (otherwise raise it).
  So try every bar $i$ as that lowest bar and stretch it as far as it stays lowest: width $R_i - L_i - 1$ with strictly
  smaller neighbours. In the one-pass version (pop on $\ge$) a bar's right end is its next *smaller-or-equal*, which can
  undercount for tied bars — but for the optimal rectangle the **rightmost** bar of minimum height inside it gets the full
  width (nothing $\le h$ to its right inside the rectangle, nothing $< h$ to the left), so the maximum is still found.
- *Maximal all-ones rectangle in a matrix.* Fix the bottom row; the column heights of consecutive ones above it form a
  histogram. Heights update in $O(m)$ per row: $O(nm)$ total.
- *Sum of subarray minimums (contribution).* $\sum_{[l,r]} \min = \sum_i a_i \cdot \#\{[l,r] : i \text{ is the designated minimum}\}$.
  With ties a subarray has several minimum positions, so designate one — the **leftmost**. Then $i$ owns $[l, r]$ iff every
  element in $[l, i)$ is $> a_i$ and every element in $(i, r]$ is $\ge a_i$: left boundary = previous **smaller-or-equal**,
  right boundary = next **strictly smaller**. Every subarray has exactly one leftmost minimum, so it is counted exactly once.
  Using strict on both sides overcounts tied subarrays; non-strict on both sides misses them.

**Monotonic deque: dominance with expiry.** Sliding-window maximum over windows $[i-k+1, i]$. If $j < k'$ and $a_j \le a_{k'}$,
then every window that contains $j$ and has already reached $k'$ also contains $k'$ (it is $[l, r]$ with $l \le j < k' \le r$),
so $j$ is useless once $k'$ has arrived. Survivors again have decreasing values, so the window maximum is the **oldest**
survivor — but old survivors *expire* when the window's left end passes them. Removal at both ends = deque: pop dominated
elements at the back, pop expired elements at the front. Each index enters and leaves once: $O(n)$.

**Shortest subarray with sum $\ge K$ when values can be negative.** Two pointers fails (a longer window can have a smaller
sum). With prefix sums $P$, we want $\min\{ j - i : i < j,\ P_j - P_i \ge K \}$. Keep a deque of candidate starts:

- *Back pop (dominance).* If $i_1 < i_2$ and $P_{i_1} \ge P_{i_2}$, then $i_2$ is better than $i_1$ for every future $j$: it is
  later (shorter subarray) and has a smaller prefix (larger sum). Pop $i_1$ when $i_2$ arrives. Hence prefixes in the deque increase.
- *Front pop (finished).* If the oldest start $i$ satisfies $P_j - P_i \ge K$, record $j - i$ and pop $i$: any later $j' > j$
  would give a longer subarray with the same start, so $i$ has nothing better to offer.

**Deque DP.** $dp_i = c_i + \max_{i-k \le j < i} dp_j$ is a sliding-window maximum over the $dp$ array itself; the deque
makes it $O(n)$ instead of $O(nk)$. This is the gateway to the monotone-queue optimisation in
[07/01](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md).

**The Cartesian tree is the stack's memory.** The min-Cartesian tree of $a$ has the minimum at the root, the left part as
its left subtree and the right part as its right subtree, recursively. The monotonic (increasing) stack after processing a
prefix is exactly the **right spine** of that prefix's Cartesian tree: a new element pops the larger spine nodes, adopts
the last popped one as its left child, and hangs itself as the right child of the new top. So the tree is built in $O(n)$,
and the subtree of $i$ is exactly the range $(L_i, R_i)$ from the contribution argument. $\operatorname{RMQ}(l, r)$ is the LCA of
$l$ and $r$ ([sparse table and RMQ](../08-Data-Structures/05-sparse-table-and-rmq.md)); a treap is a Cartesian tree on
(key, random priority) ([treaps](../08-Data-Structures/09-treaps-and-implicit-treaps.md)).

## 2. Formulas, definitions and identities

**Nearest-element arrays** ($-1$ / $n$ when none). All computed in $O(n)$ by one pass with the pop rule from the §1 table;
"next" arrays can also be computed by the same loop run from right to left.

| Array | Definition | Left-to-right pop rule |
|---|---|---|
| $PG_i$ | $\max\{j < i : a_j > a_i\}$ | pop while $a_{top} \le a_i$ |
| $PGE_i$ | $\max\{j < i : a_j \ge a_i\}$ | pop while $a_{top} < a_i$ |
| $PS_i$ | $\max\{j < i : a_j < a_i\}$ | pop while $a_{top} \ge a_i$ |
| $PSE_i$ | $\max\{j < i : a_j \le a_i\}$ | pop while $a_{top} > a_i$ |

**Subarrays owned by $i$ as leftmost minimum.** With $L_i = PSE_i$ and $R_i = NS_i$ (next strictly smaller):
$$\#\text{owned}(i) = (i - L_i)(R_i - i), \qquad \sum_{0 \le l \le r < n} \min a[l..r] = \sum_i a_i (i - L_i)(R_i - i).$$
Check: $\sum_i (i - L_i)(R_i - i) = n(n+1)/2$ (each subarray owned once). Maxima: same with greater; or negate:
$\sum \max(a) = -\sum \min(-a)$. **Sum of ranges** $= \sum \max - \sum \min$. Magnitude: at most $\max|a| \cdot n(n+1)/2$
— $10^6 \cdot 5 \cdot 10^{11} = 5 \cdot 10^{17}$ for $n = 10^6$, inside signed 64-bit ($\approx 9.2 \cdot 10^{18}$); take it mod $p$ when asked.

**Largest rectangle.** $\displaystyle \max_i \; h_i \,(NS_i - PS_i - 1)$. Maximal rectangle in an $n \times m$ 0/1 matrix:
$H_r[c] = (H_{r-1}[c] + 1)\cdot[\text{cell}_{r,c} = 1]$, answer $\max_r \text{hist}(H_r)$, $O(nm)$.

**Window length where $a_i$ is the minimum.** $w_i = NS_i - PS_i - 1$; the best minimum over windows of length $x$ is
$\max\{a_i : w_i \ge x\}$, a suffix maximum over $x$.

**Stock span.** $\text{span}_i = i - PG_i$ (days back, including today, with price $\le$ today's).

**Sliding window.** $\max a[i-k+1..i] = a[\text{front}]$ after popping back elements $\le a_i$ and the front if it is $\le i-k$.
Each step pops at most one expired element. $O(n)$ total, $O(k)$ memory.

**Shortest subarray with sum $\ge K$.** $\min\{ j - i : 0 \le i < j \le n,\ P_j - P_i \ge K \}$, $O(n)$ with the two pops of §1.

**Deque DP.** $dp_i = c_i + \max_{i-k \le j < i} dp_j$ in $O(n)$; works for any window whose both ends are non-decreasing in $i$.

**Cartesian tree.** For distinct values, $\operatorname{parent}(i)$ is whichever of $PS_i, NS_i$ has the **larger** value (the lower
of the two in the tree); the subtree of $i$ spans $(PS_i, NS_i)$; in-order traversal = index order; depth is $O(n)$ worst case,
$O(\log n)$ expected for a random permutation (the treap fact).

| Operation | Time | Extra memory |
|---|---|---|
| one nearest-element array | $O(n)$ amortised | $O(n)$ stack |
| histogram / maximal rectangle | $O(n)$ / $O(nm)$ | $O(m)$ |
| sum of subarray min / max / range | $O(n)$ | $O(n)$ |
| sliding-window max/min, deque DP | $O(n)$ | $O(k)$ |
| shortest subarray sum $\ge K$ | $O(n)$ | $O(n)$ |
| Cartesian tree | $O(n)$ | $O(n)$ |

## 3. Implementation (C++ and Java)

### 3.1 Nearest greater / smaller (all four, one generic routine)

```cpp
// res[i] = nearest j < i that survives the pop rule (-1 if none). pop(x, y): does stack value x get removed by new value y?
//   previous strictly greater: x <= y    previous greater-or-equal: x < y
//   previous strictly smaller: x >= y    previous smaller-or-equal: x > y
template <class Pop> vector<int> prevBy(const vector<ll>& a, Pop pop) {
    int n = a.size(); vector<int> res(n), st;
    for (int i = 0; i < n; i++) {
        while (!st.empty() && pop(a[st.back()], a[i])) st.pop_back();
        res[i] = st.empty() ? -1 : st.back();
        st.push_back(i);
    }
    return res;
}
// Same rules, nearest j > i (n if none): scan from the right.
template <class Pop> vector<int> nextBy(const vector<ll>& a, Pop pop) {
    int n = a.size(); vector<int> res(n), st;
    for (int i = n - 1; i >= 0; i--) {
        while (!st.empty() && pop(a[st.back()], a[i])) st.pop_back();
        res[i] = st.empty() ? n : st.back();
        st.push_back(i);
    }
    return res;
}
// Example: auto PG = prevBy(a, [](ll x, ll y) { return x <= y; });   auto NS = nextBy(a, [](ll x, ll y) { return x >= y; });
```

```java
interface Pop { boolean test(long top, long cur); }
static int[] prevBy(long[] a, Pop pop) {
    int n = a.length; int[] res = new int[n], st = new int[n]; int sp = 0;
    for (int i = 0; i < n; i++) {
        while (sp > 0 && pop.test(a[st[sp - 1]], a[i])) sp--;
        res[i] = sp == 0 ? -1 : st[sp - 1];
        st[sp++] = i;
    }
    return res;
}
static int[] nextBy(long[] a, Pop pop) {
    int n = a.length; int[] res = new int[n], st = new int[n]; int sp = 0;
    for (int i = n - 1; i >= 0; i--) {
        while (sp > 0 && pop.test(a[st[sp - 1]], a[i])) sp--;
        res[i] = sp == 0 ? n : st[sp - 1];
        st[sp++] = i;
    }
    return res;
}
// Example: int[] pg = prevBy(a, (x, y) -> x <= y);
```

### 3.2 Histogram, maximal rectangle, sum of subarray minimums, stock span

```cpp
// Largest rectangle under a histogram (h[i] >= 0). Index n acts as a height-0 sentinel that flushes the stack.
ll largestRectangle(const vector<ll>& h) {
    int n = h.size(); vector<int> st; ll best = 0;
    for (int i = 0; i <= n; i++) {
        ll cur = i < n ? h[i] : 0;
        while (!st.empty() && h[st.back()] >= cur) {
            ll height = h[st.back()]; st.pop_back();
            int left = st.empty() ? -1 : st.back();     // previous strictly smaller
            best = max(best, height * (i - left - 1));  // i = next smaller-or-equal
        }
        st.push_back(i);
    }
    return best;
}
ll maximalRectangle(const vector<string>& g) {          // cells '0' / '1'
    if (g.empty()) return 0;
    int m = g[0].size(); vector<ll> h(m, 0); ll best = 0;
    for (auto& row : g) {
        for (int c = 0; c < m; c++) h[c] = row[c] == '1' ? h[c] + 1 : 0;
        best = max(best, largestRectangle(h));
    }
    return best;
}
// Sum over all subarrays of the minimum; the leftmost minimum owns each subarray.
ll sumSubarrayMins(const vector<ll>& a) {
    int n = a.size(); vector<int> L(n), R(n, n), st;
    for (int i = 0; i < n; i++) {
        while (!st.empty() && a[st.back()] > a[i]) { R[st.back()] = i; st.pop_back(); }  // next strictly smaller
        L[i] = st.empty() ? -1 : st.back();                                              // previous smaller-or-equal
        st.push_back(i);
    }
    ll s = 0;
    for (int i = 0; i < n; i++) s += a[i] * (i - L[i]) * (R[i] - i);
    return s;
}
ll sumSubarrayRanges(vector<ll> a) {                      // sum of (max - min)
    ll mn = sumSubarrayMins(a);
    for (auto& x : a) x = -x;
    return -sumSubarrayMins(a) - mn;                      // sum max(a) = -sum min(-a)
}
struct StockSpanner {                                     // online: span = days back (inclusive) with price <= today's
    vector<pair<ll,int>> st; int day = 0;                 // (price, day), prices strictly decreasing upward
    int next(ll price) {
        while (!st.empty() && st.back().first <= price) st.pop_back();
        int span = st.empty() ? day + 1 : day - st.back().second;
        st.push_back({price, day++});
        return span;
    }
};
```

```java
static long largestRectangle(long[] h) {
    int n = h.length; int[] st = new int[n + 1]; int sp = 0; long best = 0;
    for (int i = 0; i <= n; i++) {
        long cur = i < n ? h[i] : 0;
        while (sp > 0 && h[st[sp - 1]] >= cur) {
            long height = h[st[--sp]];
            int left = sp == 0 ? -1 : st[sp - 1];
            best = Math.max(best, height * (i - left - 1));
        }
        st[sp++] = i;
    }
    return best;
}
static long maximalRectangle(String[] g) {
    if (g.length == 0) return 0;
    int m = g[0].length(); long[] h = new long[m]; long best = 0;
    for (String row : g) {
        for (int c = 0; c < m; c++) h[c] = row.charAt(c) == '1' ? h[c] + 1 : 0;
        best = Math.max(best, largestRectangle(h));
    }
    return best;
}
static long sumSubarrayMins(long[] a) {
    int n = a.length; int[] L = new int[n], R = new int[n], st = new int[n]; int sp = 0;
    Arrays.fill(R, n);
    for (int i = 0; i < n; i++) {
        while (sp > 0 && a[st[sp - 1]] > a[i]) R[st[--sp]] = i;
        L[i] = sp == 0 ? -1 : st[sp - 1];
        st[sp++] = i;
    }
    long s = 0;
    for (int i = 0; i < n; i++) s += a[i] * (i - L[i]) * (R[i] - i);
    return s;
}
static long sumSubarrayRanges(long[] a) {
    long[] neg = new long[a.length];
    for (int i = 0; i < a.length; i++) neg[i] = -a[i];
    return -sumSubarrayMins(neg) - sumSubarrayMins(a);
}
static class StockSpanner {
    long[] price = new long[16]; int[] day = new int[16]; int sp = 0, today = 0;
    int next(long p) {
        while (sp > 0 && price[sp - 1] <= p) sp--;
        int span = sp == 0 ? today + 1 : today - day[sp - 1];
        if (sp == price.length) { price = Arrays.copyOf(price, 2 * sp); day = Arrays.copyOf(day, 2 * sp); }
        price[sp] = p; day[sp++] = today++;
        return span;
    }
}
```

### 3.3 Monotonic deque: window max, shortest subarray with sum ≥ K, deque DP, Cartesian tree

```cpp
// res[i - k + 1] = max of a[i-k+1..i] for every full window.
vector<ll> slidingMax(const vector<ll>& a, int k) {
    deque<int> dq; vector<ll> res;
    for (int i = 0; i < (int)a.size(); i++) {
        while (!dq.empty() && a[dq.back()] <= a[i]) dq.pop_back();   // dominated: older and not larger
        dq.push_back(i);
        if (dq.front() <= i - k) dq.pop_front();                      // expired (at most one per step)
        if (i >= k - 1) res.push_back(a[dq.front()]);
    }
    return res;
}
// Shortest non-empty subarray with sum >= K, values may be negative; -1 if none.
int shortestSumAtLeast(const vector<ll>& a, ll K) {
    int n = a.size(); vector<ll> P(n + 1, 0);
    for (int i = 0; i < n; i++) P[i + 1] = P[i] + a[i];
    deque<int> dq; int best = INT_MAX;
    for (int j = 0; j <= n; j++) {
        while (!dq.empty() && P[j] - P[dq.front()] >= K) { best = min(best, j - dq.front()); dq.pop_front(); }
        while (!dq.empty() && P[dq.back()] >= P[j]) dq.pop_back();    // j is later with a prefix no larger
        dq.push_back(j);
    }
    return best == INT_MAX ? -1 : best;
}
// dp[i] = a[i] + max(dp[j] : i-k <= j < i), dp[0] = a[0]; returns dp[n-1].
ll windowDP(const vector<ll>& a, int k) {
    int n = a.size(); vector<ll> dp(n); deque<int> dq;
    for (int i = 0; i < n; i++) {
        while (!dq.empty() && dq.front() < i - k) dq.pop_front();
        dp[i] = a[i] + (dq.empty() ? 0 : dp[dq.front()]);
        while (!dq.empty() && dp[dq.back()] <= dp[i]) dq.pop_back();
        dq.push_back(i);
    }
    return dp[n - 1];
}
// Min-Cartesian tree, parent array (-1 = root). Equal values: the earlier index is the ancestor.
vector<int> cartesianParent(const vector<ll>& a) {
    int n = a.size(); vector<int> par(n, -1), st;         // st = right spine, values increasing upward
    for (int i = 0; i < n; i++) {
        int last = -1;
        while (!st.empty() && a[st.back()] > a[i]) { last = st.back(); st.pop_back(); }
        if (last != -1) par[last] = i;                     // popped chain becomes i's left subtree
        if (!st.empty()) par[i] = st.back();               // i is the right child of the new top
        st.push_back(i);
    }
    return par;
}
```

```java
static long[] slidingMax(long[] a, int k) {
    int n = a.length; int[] dq = new int[n]; int head = 0, tail = 0, t = 0;
    long[] res = new long[Math.max(0, n - k + 1)];
    for (int i = 0; i < n; i++) {
        while (tail > head && a[dq[tail - 1]] <= a[i]) tail--;
        dq[tail++] = i;
        if (dq[head] <= i - k) head++;
        if (i >= k - 1) res[t++] = a[dq[head]];
    }
    return res;
}
static int shortestSumAtLeast(long[] a, long K) {
    int n = a.length; long[] P = new long[n + 1];
    for (int i = 0; i < n; i++) P[i + 1] = P[i] + a[i];
    int[] dq = new int[n + 1]; int head = 0, tail = 0, best = Integer.MAX_VALUE;
    for (int j = 0; j <= n; j++) {
        while (tail > head && P[j] - P[dq[head]] >= K) { best = Math.min(best, j - dq[head]); head++; }
        while (tail > head && P[dq[tail - 1]] >= P[j]) tail--;
        dq[tail++] = j;
    }
    return best == Integer.MAX_VALUE ? -1 : best;
}
static long windowDP(long[] a, int k) {
    int n = a.length; long[] dp = new long[n]; int[] dq = new int[n]; int head = 0, tail = 0;
    for (int i = 0; i < n; i++) {
        while (tail > head && dq[head] < i - k) head++;
        dp[i] = a[i] + (tail == head ? 0 : dp[dq[head]]);
        while (tail > head && dp[dq[tail - 1]] <= dp[i]) tail--;
        dq[tail++] = i;
    }
    return dp[n - 1];
}
static int[] cartesianParent(long[] a) {
    int n = a.length; int[] par = new int[n], st = new int[n]; int sp = 0;
    Arrays.fill(par, -1);
    for (int i = 0; i < n; i++) {
        int last = -1;
        while (sp > 0 && a[st[sp - 1]] > a[i]) last = st[--sp];
        if (last != -1) par[last] = i;
        if (sp > 0) par[i] = st[sp - 1];
        st[sp++] = i;
    }
    return par;
}
```

Java note: `ArrayDeque<Integer>` works but boxes every index; the `int[]` with `head`/`tail` above is several times faster
and is safe because each index is pushed once (so `tail <= n`).

## 4. Recognising the pattern

| Signal in the statement | Think |
|---|---|
| "next / previous greater (smaller)", "first day warmer", "how far can it see", "span" | §3.1 with the right pop rule |
| "for each element, the longest segment where it is the minimum (maximum)" | $PS/NS$ (or $PG/NG$) widths |
| "sum over all subarrays of min / max / max − min" | contribution with leftmost-owner tie-breaking |
| "largest rectangle", "largest empty area in a grid", "max of (min × length)" | histogram stack, row by row for grids |
| "max of min over windows of every length" | widths $w_i$ + suffix maximum |
| "sliding window maximum/minimum", "max − min $\le d$ over a window" | deque (two deques + two pointers for max − min) |
| $dp_i$ uses $\max/\min$ of $dp_j$ over a moving range $[i-k, i-1]$ | deque DP |
| "shortest subarray with sum $\ge K$" with negatives | prefix sums + increasing deque |
| "remove $k$ digits to make the number smallest", "smallest subsequence with each letter once" | greedy monotonic stack (pop while it helps and is still allowed) |
| matching brackets, collapsing adjacent pairs | a plain stack — not monotone; don't overthink it |

Often confused with: arbitrary range-min queries (use a [sparse table](../08-Data-Structures/05-sparse-table-and-rmq.md)
or [segment tree](../08-Data-Structures/02-segment-tree-basics.md) — a deque only works when both window ends move
forward), and sliding median (two heaps or an order-statistics tree, not a deque).

## 5. Worked examples (graded)

### Example 1 — Maximum Building I  ·  ★ ≈1700 (est.)

- **Source:** [CSES 1147 · Maximum Building I](https://cses.fi/problemset/task/1147)
- **Difficulty:** ≈1700 (est.)
- **Problem:** an $n \times m$ grid ($n, m \le 1000$) of empty cells `.` and trees `*`. Find the largest area of an
  axis-aligned rectangle consisting only of empty cells.
- **Thinking from first principles:** brute force over all rectangles is $O(n^2m^2)$. Fix the bottom row of the rectangle:
  each column then offers a "height" — the number of consecutive empty cells ending at that row — and a rectangle with that
  bottom row is a rectangle under this histogram. So the grid problem is $n$ histogram problems, each $O(m)$ with the stack.

<details><summary>Solution</summary>

Maintain `h[c]` row by row (reset to 0 at a tree). For each row run the one-pass histogram (§3.2) with a sentinel 0 at
index $m$. Correctness: the best rectangle has some bottom row $r$, and at row $r$ it is a rectangle under $H_r$, which the
histogram routine maximises (proof in §1). $O(nm)$ time, $O(m)$ memory.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    vector<int> h(m + 1, 0), st;                        // h[m] stays 0: the sentinel bar
    long long best = 0; string row;
    for (int r = 0; r < n; r++) {
        cin >> row;
        for (int c = 0; c < m; c++) h[c] = row[c] == '.' ? h[c] + 1 : 0;
        st.clear();
        for (int i = 0; i <= m; i++) {
            while (!st.empty() && h[st.back()] >= h[i]) {
                long long height = h[st.back()]; st.pop_back();
                int left = st.empty() ? -1 : st.back();
                best = max(best, height * (i - left - 1));
            }
            st.push_back(i);
        }
    }
    cout << best << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt();
        int[] h = new int[m + 1], st = new int[m + 1];
        long best = 0;
        for (int r = 0; r < n; r++) {
            String row = in.next();
            for (int c = 0; c < m; c++) h[c] = row.charAt(c) == '.' ? h[c] + 1 : 0;
            int sp = 0;
            for (int i = 0; i <= m; i++) {
                while (sp > 0 && h[st[sp - 1]] >= h[i]) {
                    long height = h[st[--sp]];
                    int left = sp == 0 ? -1 : st[sp - 1];
                    best = Math.max(best, height * (i - left - 1));
                }
                st[sp++] = i;
            }
        }
        System.out.println(best);
    }
    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
        String next() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

<!-- test
in:
4 7
...*...
..*....
.......
*....*.
out:
9
-->
<!-- test
in:
1 1
*
out:
0
-->
<!-- test
in:
2 3
...
...
out:
6
-->
<!-- test
in:
3 5
*.*.*
.....
**.**
out:
5
-->

</details>

### Example 2 — Mike and Feet  ·  ★ 1900

- **Source:** [CF 547B · Mike and Feet](https://codeforces.com/problemset/problem/547/B) — 1900
- **Difficulty:** 1900
- **Problem:** $n \le 2 \cdot 10^5$ heights $a_i \le 10^9$. For every $x = 1..n$, print the maximum over all windows of length
  $x$ of the window minimum.
- **Thinking from first principles:** $n$ sliding-window minima would be $O(n^2)$. Turn the question around: instead of
  asking each length which element wins, ask each element for which lengths it *can* be the minimum. $a_i$ is the minimum of
  some window of length $x$ iff $x \le w_i$, where $w_i$ is the length of the maximal range around $i$ with no smaller
  element. So $\text{ans}[x] = \max\{a_i : w_i \ge x\}$.

<details><summary>Solution</summary>

$w_i = NS_i - PS_i - 1$ (strictly smaller neighbours, so equal values may share a window). Put $\text{best}[w_i] \gets \max(\text{best}[w_i], a_i)$,
then take suffix maxima: $\text{ans}[x] = \max_{y \ge x} \text{best}[y]$. Proof: "$a_i$ is a window-of-length-$x$ minimum
$\iff x \le w_i$" — any window of length $\le w_i$ containing $i$ inside $(PS_i, NS_i)$ has minimum $a_i$, and any window of
length $> w_i$ containing $i$ includes a smaller element. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    vector<int> L(n), R(n, n), st;
    for (int i = 0; i < n; i++) {
        while (!st.empty() && a[st.back()] >= a[i]) st.pop_back();
        L[i] = st.empty() ? -1 : st.back();              // previous strictly smaller
        st.push_back(i);
    }
    st.clear();
    for (int i = n - 1; i >= 0; i--) {
        while (!st.empty() && a[st.back()] >= a[i]) st.pop_back();
        R[i] = st.empty() ? n : st.back();               // next strictly smaller
        st.push_back(i);
    }
    vector<long long> best(n + 2, 0);
    for (int i = 0; i < n; i++) { int w = R[i] - L[i] - 1; best[w] = max(best[w], a[i]); }
    for (int x = n - 1; x >= 1; x--) best[x] = max(best[x], best[x + 1]);
    for (int x = 1; x <= n; x++) cout << best[x] << (x == n ? '\n' : ' ');
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        int[] L = new int[n], R = new int[n], st = new int[n]; int sp = 0;
        for (int i = 0; i < n; i++) {
            while (sp > 0 && a[st[sp - 1]] >= a[i]) sp--;
            L[i] = sp == 0 ? -1 : st[sp - 1];
            st[sp++] = i;
        }
        sp = 0;
        for (int i = n - 1; i >= 0; i--) {
            while (sp > 0 && a[st[sp - 1]] >= a[i]) sp--;
            R[i] = sp == 0 ? n : st[sp - 1];
            st[sp++] = i;
        }
        long[] best = new long[n + 2];
        for (int i = 0; i < n; i++) { int w = R[i] - L[i] - 1; best[w] = Math.max(best[w], a[i]); }
        for (int x = n - 1; x >= 1; x--) best[x] = Math.max(best[x], best[x + 1]);
        StringBuilder sb = new StringBuilder();
        for (int x = 1; x <= n; x++) sb.append(best[x]).append(x == n ? '\n' : ' ');
        System.out.print(sb);
    }
    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
5
3 1 4 1 5
out:
5 1 1 1 1
-->
<!-- test
in:
1
7
out:
7
-->
<!-- test
in:
4
2 2 2 2
out:
2 2 2 2
-->
<!-- test
in:
6
1000000000 999999999 5 999999998 1000000000 6
out:
1000000000 999999999 6 5 5 5
-->

</details>

### Example 3 — Imbalanced Array  ·  ★ 1900

- **Source:** [CF 817D · Imbalanced Array](https://codeforces.com/problemset/problem/817/D) — 1900
- **Difficulty:** 1900
- **Problem:** $n \le 10^6$, $1 \le a_i \le 10^6$. The imbalance of a subarray is its maximum minus its minimum. Print the sum
  of imbalances over all $n(n+1)/2$ subarrays.
- **Thinking from first principles:** linearity: $\sum (\max - \min) = \sum \max - \sum \min$, and each sum is a contribution
  sum over elements (§1). The only danger is ties: $[2, 2]$ has two minimum positions. Designate the leftmost minimum (and
  the leftmost maximum), which fixes one strict and one non-strict comparison per side. A quick check that catches the
  wrong tie rule: for an all-equal array the answer must be 0 and $\sum_i (i - L_i)(R_i - i)$ must equal $n(n+1)/2$.

<details><summary>Solution</summary>

For the minimum: $L_i$ = previous smaller-or-equal, $R_i$ = next strictly smaller — both from one pass popping on
$a_{top} > a_i$. For the maximum: the mirror (pop on $a_{top} < a_i$). Answer $= \sum_i a_i \bigl[(i-L^{\max}_i)(R^{\max}_i-i) - (i-L^{\min}_i)(R^{\min}_i-i)\bigr]$.
Bound: each of the two sums is $\le 10^6 \cdot n(n+1)/2 \approx 5 \cdot 10^{17}$, inside 64-bit (a random
array with $n = 10^6$ really does give $\approx 5 \cdot 10^{17}$). $O(n)$ time; with $n = 10^6$, fast input matters.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    vector<int> L(n), R(n), st; st.reserve(n);
    long long ans = 0;
    for (int sign = 1; sign >= -1; sign -= 2) {          // +1: maxima, -1: minima (compare sign*a)
        fill(R.begin(), R.end(), n); st.clear();
        for (int i = 0; i < n; i++) {
            while (!st.empty() && sign * a[st.back()] < sign * a[i]) { R[st.back()] = i; st.pop_back(); }
            L[i] = st.empty() ? -1 : st.back();
            st.push_back(i);
        }
        for (int i = 0; i < n; i++) ans += sign * a[i] * (long long)(i - L[i]) * (R[i] - i);
    }
    cout << ans << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        int[] L = new int[n], R = new int[n], st = new int[n];
        long ans = 0;
        for (int sign = 1; sign >= -1; sign -= 2) {
            Arrays.fill(R, n); int sp = 0;
            for (int i = 0; i < n; i++) {
                while (sp > 0 && sign * a[st[sp - 1]] < sign * a[i]) R[st[--sp]] = i;
                L[i] = sp == 0 ? -1 : st[sp - 1];
                st[sp++] = i;
            }
            for (int i = 0; i < n; i++) ans += sign * a[i] * (long) (i - L[i]) * (R[i] - i);
        }
        System.out.println(ans);
    }
    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

Comparing `sign * a` turns one loop into both passes: with `sign = 1` it pops while $a_{top} < a_i$ (leftmost maximum owns
the subarray), with `sign = -1` while $a_{top} > a_i$ (leftmost minimum).

<!-- test
in:
4
1 3 2 4
out:
12
-->
<!-- test
in:
1
5
out:
0
-->
<!-- test
in:
3
2 2 2
out:
0
-->
<!-- test
in:
6
5 1 5 1 5 1
out:
60
-->

</details>

### Example 4 — Exposition  ·  ★ 1900

- **Source:** [CF 6E · Exposition](https://codeforces.com/problemset/problem/6/E) — 1900
- **Difficulty:** 1900
- **Problem:** heights $h_1..h_n$ ($n \le 10^5$, $h_i \le 10^6$) and $k \le 10^6$. Find the maximum length $a$ of a contiguous
  segment with $\max - \min \le k$, the number $b$ of segments of that length satisfying it, and print those segments
  (1-indexed, in order).
- **Thinking from first principles:** "$\max - \min \le k$" is hereditary (a sub-window has a smaller max and a larger min), so
  a two-pointer window is legal ([03](03-two-pointers-and-sliding-window.md)). The window statistic is max and min under
  push-right / pop-left: one decreasing deque for the max, one increasing deque for the min. Every optimal segment is the
  longest good window ending at its right end, so the windows found by the scan are exactly the candidates.

<details><summary>Solution</summary>

For each $r$: push $r$ into both deques; while $h[\text{maxFront}] - h[\text{minFront}] > k$, advance $l$ and drop fronts
that fell out. Then $[l, r]$ is the longest good window ending at $r$. A good segment of maximum length $a$ ending at $r$
must equal $[l, r]$ (if $l$ were smaller, the window would be longer than $a$; if larger, $[l,r]$ would be longer than the
segment, still good, contradiction). So record $(l, r)$ whenever $r - l + 1$ ties the best, and reset the list when it
improves. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; long long k; cin >> n >> k;
    vector<long long> h(n);
    for (auto& x : h) cin >> x;
    deque<int> mx, mn;                                   // mx: decreasing values, mn: increasing values
    int best = 0; vector<pair<int,int>> segs;
    for (int l = 0, r = 0; r < n; r++) {
        while (!mx.empty() && h[mx.back()] <= h[r]) mx.pop_back();
        while (!mn.empty() && h[mn.back()] >= h[r]) mn.pop_back();
        mx.push_back(r); mn.push_back(r);
        while (h[mx.front()] - h[mn.front()] > k) {
            l++;
            if (mx.front() < l) mx.pop_front();
            if (mn.front() < l) mn.pop_front();
        }
        int len = r - l + 1;
        if (len > best) { best = len; segs.clear(); }
        if (len == best) segs.push_back({l + 1, r + 1});
    }
    cout << best << ' ' << segs.size() << '\n';
    for (auto [s, e] : segs) cout << s << ' ' << e << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(); long k = in.nextLong();
        long[] h = new long[n];
        for (int i = 0; i < n; i++) h[i] = in.nextLong();
        int[] mx = new int[n], mn = new int[n];
        int mxH = 0, mxT = 0, mnH = 0, mnT = 0, best = 0, cnt = 0;
        int[] segL = new int[n];
        for (int l = 0, r = 0; r < n; r++) {
            while (mxT > mxH && h[mx[mxT - 1]] <= h[r]) mxT--;
            while (mnT > mnH && h[mn[mnT - 1]] >= h[r]) mnT--;
            mx[mxT++] = r; mn[mnT++] = r;
            while (h[mx[mxH]] - h[mn[mnH]] > k) {
                l++;
                if (mx[mxH] < l) mxH++;
                if (mn[mnH] < l) mnH++;
            }
            int len = r - l + 1;
            if (len > best) { best = len; cnt = 0; }
            if (len == best) segL[cnt++] = l;
        }
        StringBuilder sb = new StringBuilder();
        sb.append(best).append(' ').append(cnt).append('\n');
        for (int i = 0; i < cnt; i++) sb.append(segL[i] + 1).append(' ').append(segL[i] + best).append('\n');
        System.out.print(sb);
    }
    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

The inner `while` always terminates with $l \le r$: the single-element window has $\max - \min = 0 \le k$, and when $l = r$
both deques' fronts are $r$.

<!-- test
in:
6 2
1 3 2 4 6 5
out:
3 3
1 3
2 4
4 6
-->
<!-- test
in:
1 0
5
out:
1 1
1 1
-->
<!-- test
in:
5 0
7 7 3 3 3
out:
3 1
3 5
-->
<!-- test
in:
7 3
10 1 4 2 8 5 9
out:
3 1
2 4
-->

</details>

### Example 5 — Shortest subarray with sum at least K (negatives allowed)  ·  ★ ≈2000 (est.)

- **Source:** Original problem (same task as [LC 862 · Shortest Subarray with Sum at Least K](https://leetcode.com/problems/shortest-subarray-with-sum-at-least-k/) — Hard).
- **Difficulty:** ≈2000 (est.)
- **Problem:** $n \le 2 \cdot 10^5$, $|a_i| \le 10^9$, $1 \le K \le 10^{15}$. Print the length of the shortest non-empty
  subarray with sum $\ge K$, or $-1$.
- **Thinking from first principles:** with positives this is the upward-closed window of
  [03](03-two-pointers-and-sliding-window.md); negatives destroy the monotonicity (in $[5, -10, 6]$ with $K = 6$ the window
  $[5,-10,6]$ fails while its suffix $[6]$ succeeds). Binary search on the length is possible ("some subarray of length
  $\le w$ has sum $\ge K$" is monotone in $w$), but its check is itself a sliding minimum of prefix sums, so go straight to
  prefix sums: for each end $j$ we want the **latest** start $i$ with
  $P_i \le P_j - K$. Dominance among starts (later and smaller prefix wins) gives an increasing deque; "a start that has
  already succeeded can only produce longer answers later" gives the front pop. Both pops are proved in §1.

<details><summary>Solution</summary>

Exactly `shortestSumAtLeast` from §3.3. Each prefix index enters and leaves the deque once: $O(n)$. Prefix sums reach
$2 \cdot 10^{14}$: 64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; long long K; cin >> n >> K;
    vector<long long> P(n + 1, 0);
    for (int i = 0; i < n; i++) { long long x; cin >> x; P[i + 1] = P[i] + x; }
    deque<int> dq; int best = INT_MAX;
    for (int j = 0; j <= n; j++) {
        while (!dq.empty() && P[j] - P[dq.front()] >= K) { best = min(best, j - dq.front()); dq.pop_front(); }
        while (!dq.empty() && P[dq.back()] >= P[j]) dq.pop_back();
        dq.push_back(j);
    }
    cout << (best == INT_MAX ? -1 : best) << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(); long K = in.nextLong();
        long[] P = new long[n + 1];
        for (int i = 0; i < n; i++) P[i + 1] = P[i] + in.nextLong();
        int[] dq = new int[n + 1]; int head = 0, tail = 0, best = Integer.MAX_VALUE;
        for (int j = 0; j <= n; j++) {
            while (tail > head && P[j] - P[dq[head]] >= K) { best = Math.min(best, j - dq[head]); head++; }
            while (tail > head && P[dq[tail - 1]] >= P[j]) tail--;
            dq[tail++] = j;
        }
        System.out.println(best == Integer.MAX_VALUE ? -1 : best);
    }
    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
3 6
5 -10 6
out:
1
-->
<!-- test
in:
2 5
2 2
out:
-1
-->
<!-- test
in:
7 7
3 -1 4 -1 -1 5 -9
out:
4
-->
<!-- test
in:
4 2000000000
1000000000 -1000000000 1000000000 1000000000
out:
2
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Decide strictness from the definition, not from habit.** Write down "previous *strictly* greater" or "greater-or-equal"
   and read the pop rule off the §1 table. Off-by-strictness passes random tests with distinct values and fails on ties.
2. **Ties in contribution sums:** one side strict, the other non-strict. Self-test: all-equal array, check
   $\sum (i-L_i)(R_i-i) = n(n+1)/2$.
3. **Store indices, not values,** on the stack/deque: you need positions for widths and expiry, and values are one lookup away.
4. **Sentinels** simplify flushing: a height-0 bar at index $n$ in the histogram, $-1$/$n$ defaults in $L/R$. Make sure the
   sentinel does not leak into answers (e.g. a negative height breaks "pop everything with $\ge 0$").
5. **Overflow:** `height * width` and `a[i] * (i-L) * (R-i)` exceed 32 bits immediately; cast before multiplying
   (`1LL *`, `(long)`). For LC 907 take it mod $10^9+7$ term by term.
6. **Deque expiry check is "front $\le i - k$"** for windows $[i-k+1, i]$; one pop per step is enough because the front was
   valid at step $i-1$. For DP windows $[i-k, i-1]$ the test is "front $< i-k$" — derive it each time.
7. **Deque DP: query before you push.** $dp_i$ must read the window $[i-k, i-1]$ before $i$ itself is inserted.
8. **Shortest-subarray deque: front pops before back pops** at each $j$ — it is the old starts that get tested against $P_j$,
   then $j$ is inserted as a new start.
9. **Java:** avoid `Stack<Integer>` (synchronised, boxed) and prefer `int[]` + pointer; `ArrayDeque<Integer>` is acceptable
   but boxes. With $n = 10^6$ (Example 3) boxing alone can cost the time limit. Use the DataInputStream reader.
10. **C++:** `std::stack` / `std::deque` are fine but `vector` as a stack is faster and cache-friendlier; `deque` has a large
    constant per element — a `vector<int>` with a moving head index works because each index is pushed once.
11. **Recursion on the Cartesian tree** can be $O(n)$ deep (sorted input): iterate, or run DFS with an explicit stack.
12. **"Remove $k$ digits" greedy stacks** need a budget check in the pop condition (`k > 0`) and a final trim if budget remains.

## 7. Going further (toward 2400–2600+)

- **DP with stacks:** [CF 1313C2 · Skyscrapers (hard version)](https://codeforces.com/problemset/problem/1313/C2) — 1900
  (maximum total of a unimodal profile under caps $m_i$: $\text{left}_i = \text{left}_{PS_i} + m_i (i - PS_i)$), and
  [CF 1407D · Discrete Centrifugal Jumps](https://codeforces.com/problemset/problem/1407/D) — 2200 (transitions exactly to the
  elements popped by both a min- and a max-stack; total transitions $O(n)$).
- **Simulations by stack:** [CF 319B · Psychos in a Line](https://codeforces.com/problemset/problem/319/B) — 1900 — the
  death time of each element is computed from the elements it pops (the same as LC 2289).
- **Contribution with a divide step:** sums over subarrays of $f(\max, \min)$ where both matter at once
  ([CF 1730E · Maximums and Minimums](https://codeforces.com/problemset/problem/1730/E) — 2700) combine both stacks with
  divisor enumeration; [CF 1849E · Max to the Right of Min](https://codeforces.com/problemset/problem/1849/E) — 2300 uses
  "iterate over the smaller side" of the Cartesian-tree split ($O(n \log n)$ by the small-to-large argument).
- **Monotone-queue DP and beyond:** multiple-choice knapsack by residues, and the bridge to convex hull trick when the
  transition is linear in $i$ ([07/01](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md),
  [07/02](../07-DP-Optimizations/02-convex-hull-trick-and-li-chao-tree.md)).
- **Cartesian tree as a tool:** offline RMQ by LCA, "count subarrays where $a_i$ is max and some condition on lengths"
  by recursing on the tree, treaps for sequences ([08/09](../08-Data-Structures/09-treaps-and-implicit-treaps.md)).
- **Monotonic stack on trees / in 2D:** stacks along DFS paths (with rollback) and the "all nearest smaller values"
  in parallel are IGM-depth curiosities; the 2D grid version you need in contests is Example 1 and
  [CSES 1148 · Maximum Building II](https://cses.fi/problemset/task/1148) (count all rectangle sizes with difference arrays).

## 8. Practice ladder

**≤ 1400**
- [ ] [CSES 1645 · Nearest Smaller Values](https://cses.fi/problemset/task/1645)
- [ ] [CSES 3221 · Sliding Window Minimum](https://cses.fi/problemset/task/3221)
- [ ] [AtCoder ABC189 C · Mandarin Orange](https://atcoder.jp/contests/abc189/tasks/abc189_c)

**1400–1700**
- [ ] [CF 1313C1 · Skyscrapers (easy version)](https://codeforces.com/problemset/problem/1313/C1) — 1500
- [ ] [CF 343B · Alternating Current](https://codeforces.com/problemset/problem/343/B) — 1600
- [ ] [CF 1941E · Rudolf and k Bridges](https://codeforces.com/problemset/problem/1941/E) — 1600
- [ ] [CSES 1142 · Advertisement](https://cses.fi/problemset/task/1142)
- [ ] [CSES 1147 · Maximum Building I](https://cses.fi/problemset/task/1147)

**1700–1900**
- [ ] [CF 280B · Maximum Xor Secondary](https://codeforces.com/problemset/problem/280/B) — 1800
- [ ] [CF 1691D · Max GEQ Sum](https://codeforces.com/problemset/problem/1691/D) — 1800
- [ ] [CF 547B · Mike and Feet](https://codeforces.com/problemset/problem/547/B) — 1900
- [ ] [CF 817D · Imbalanced Array](https://codeforces.com/problemset/problem/817/D) — 1900
- [ ] [CF 6E · Exposition](https://codeforces.com/problemset/problem/6/E) — 1900
- [ ] [CF 1313C2 · Skyscrapers (hard version)](https://codeforces.com/problemset/problem/1313/C2) — 1900
- [ ] [CF 5C · Longest Regular Bracket Sequence](https://codeforces.com/problemset/problem/5/C) — 1900
- [ ] [AtCoder ABC407 F · Sums of Sliding Window Maximum](https://atcoder.jp/contests/abc407/tasks/abc407_f)

**1900–2100**
- [ ] [CF 319B · Psychos in a Line](https://codeforces.com/problemset/problem/319/B) — 1900
- [ ] [CF 940E · Cashback](https://codeforces.com/problemset/problem/940/E) — 2000
- [ ] [CF 514D · R2D2 and Droid Army](https://codeforces.com/problemset/problem/514/D) — 2000
- [ ] [CF 372C · Watching Fireworks is Fun](https://codeforces.com/problemset/problem/372/C) — 2100
- [ ] [CF 601B · Lipshitz Sequence](https://codeforces.com/problemset/problem/601/B) — 2100
- [ ] [CSES 1148 · Maximum Building II](https://cses.fi/problemset/task/1148)

**2100+**
- [ ] [CF 1407D · Discrete Centrifugal Jumps](https://codeforces.com/problemset/problem/1407/D) — 2200
- [ ] [CF 1849E · Max to the Right of Min](https://codeforces.com/problemset/problem/1849/E) — 2300
- [ ] [CF 5E · Bindian Signalizing](https://codeforces.com/problemset/problem/5/E) — 2400
- [ ] [CF 1730E · Maximums and Minimums](https://codeforces.com/problemset/problem/1730/E) — 2700

## 9. LeetCode / FAANG cross-reference

- [LC 496 · Next Greater Element I](https://leetcode.com/problems/next-greater-element-i/) — Easy — next greater + a value→index map.
- [LC 503 · Next Greater Element II](https://leetcode.com/problems/next-greater-element-ii/) — Medium — circular: run the pass over $2n$ indices mod $n$.
- [LC 739 · Daily Temperatures](https://leetcode.com/problems/daily-temperatures/) — Medium — next strictly greater, answer = distance.
- [LC 901 · Online Stock Span](https://leetcode.com/problems/online-stock-span/) — Medium — `StockSpanner` in §3.2.
- [LC 1475 · Final Prices With a Special Discount in a Shop](https://leetcode.com/problems/final-prices-with-a-special-discount-in-a-shop/) — Easy — next smaller-or-equal.
- [LC 84 · Largest Rectangle in Histogram](https://leetcode.com/problems/largest-rectangle-in-histogram/) — Hard — §3.2.
- [LC 85 · Maximal Rectangle](https://leetcode.com/problems/maximal-rectangle/) — Hard — row-by-row histograms (Example 1).
- [LC 907 · Sum of Subarray Minimums](https://leetcode.com/problems/sum-of-subarray-minimums/) — Medium — contribution with tie-breaking, mod $10^9+7$.
- [LC 2104 · Sum of Subarray Ranges](https://leetcode.com/problems/sum-of-subarray-ranges/) — Medium — Example 3.
- [LC 1856 · Maximum Subarray Min-Product](https://leetcode.com/problems/maximum-subarray-min-product/) — Medium — widths + prefix sums.
- [LC 1793 · Maximum Score of a Good Subarray](https://leetcode.com/problems/maximum-score-of-a-good-subarray/) — Hard — histogram restricted to windows containing $k$.
- [LC 42 · Trapping Rain Water](https://leetcode.com/problems/trapping-rain-water/) — Hard — stack fills "basins" layer by layer.
- [LC 1944 · Number of Visible People in a Queue](https://leetcode.com/problems/number-of-visible-people-in-a-queue/) — Hard — answer = number of people you pop, plus one if someone taller remains on the stack.
- [LC 2289 · Steps to Make Array Non-decreasing](https://leetcode.com/problems/steps-to-make-array-non-decreasing/) — Medium — Psychos in a Line.
- [LC 402 · Remove K Digits](https://leetcode.com/problems/remove-k-digits/) — Medium — greedy increasing stack with a budget.
- [LC 316 · Remove Duplicate Letters](https://leetcode.com/problems/remove-duplicate-letters/) — Medium — greedy stack, pop only if the letter appears later.
- [LC 456 · 132 Pattern](https://leetcode.com/problems/132-pattern/) — Medium — decreasing stack from the right, track the best "2".
- [LC 654 · Maximum Binary Tree](https://leetcode.com/problems/maximum-binary-tree/) — Medium — a max-Cartesian tree, $O(n)$ by §3.3.
- [LC 239 · Sliding Window Maximum](https://leetcode.com/problems/sliding-window-maximum/) — Hard — §3.3.
- [LC 1438 · Longest Continuous Subarray With Absolute Diff Less Than or Equal to Limit](https://leetcode.com/problems/longest-continuous-subarray-with-absolute-diff-less-than-or-equal-to-limit/) — Medium — Example 4.
- [LC 862 · Shortest Subarray with Sum at Least K](https://leetcode.com/problems/shortest-subarray-with-sum-at-least-k/) — Hard — Example 5.
- [LC 1696 · Jump Game VI](https://leetcode.com/problems/jump-game-vi/) — Medium — deque DP (`windowDP`).
- [LC 1425 · Constrained Subsequence Sum](https://leetcode.com/problems/constrained-subsequence-sum/) — Hard — deque DP with $\max(0, \cdot)$.
- [LC 1499 · Max Value of Equation](https://leetcode.com/problems/max-value-of-equation/) — Hard — deque over $y_j - x_j$ with a distance window.
- [LC 2398 · Maximum Number of Robots Within Budget](https://leetcode.com/problems/maximum-number-of-robots-within-budget/) — Hard — two pointers + max deque.

Monotonic stacks are an interview staple (daily temperatures, histogram, sum of subarray minimums); interviewers usually
probe the amortised $O(n)$ argument and tie handling. See [FAANG stacks](../17-FAANG-Interview-DSA/04-stacks-and-monotonic-stacks.md)
and the [contribution technique](../05-Combinatorics-and-Probability/07-contribution-technique.md).

## 10. Self-check

1. Why can an index popped from the "previous greater" stack never be the answer for a later query?
2. Prove that the whole pass is $O(n)$.
3. You pop while $a_{top} < a_i$. What are the survivor-below-$i$ and the popper-of-$j$ relations, exactly?
4. In the sum of subarray minimums, which side is strict and why does using strict on both sides fail? Give a 2-element counterexample.
5. In the one-pass histogram (pop on $\ge$), some bars get too-small widths. Why is the answer still correct?
6. Why does sliding-window maximum need a deque rather than a stack?
7. In the shortest subarray with sum $\ge K$, justify both kinds of pops.
8. How does the monotonic stack build the Cartesian tree, and what does the subtree of $i$ correspond to?

<details><summary>Answers</summary>

1. It was popped by some $k$ with $a_k \ge a_j$ and $j < k$; for any later $i$, if $a_j > a_i$ then $a_k > a_i$ and $k$ is nearer.
2. Each index is pushed once and popped at most once: $\le 2n$ operations in total (potential = stack size).
3. Survivor below $i$ is the previous greater-or-equal; the element that pops $j$ is $j$'s next strictly greater.
4. Left non-strict (previous smaller-or-equal) and right strict (next strictly smaller), or the mirror. For $[2, 2]$ with
   strict on both sides each element claims $[0,1]$: $\min$ counted twice, sum $= 2+2+2\cdot 2 = 8$ instead of 6.
5. For the optimal rectangle with height $h$, its rightmost bar of height $h$ has no bar $\le h$ to its right inside the
   rectangle and no bar $< h$ to its left inside it, so its computed rectangle contains the optimal one.
6. The maximum is the oldest surviving candidate, and candidates also leave from the old end when they expire — removals at
   both ends.
7. Back: a later start with a prefix that is not larger is better for every future end. Front: once start $i$ works for $j$,
   later ends only give longer subarrays with $i$, so record and discard it.
8. The stack is the right spine; a new element pops larger spine nodes, takes the last popped as its left child, and becomes
   the right child of the new top. The subtree of $i$ is the index range $(PS_i, NS_i)$ — the maximal range where $a_i$ is the minimum.

</details>
