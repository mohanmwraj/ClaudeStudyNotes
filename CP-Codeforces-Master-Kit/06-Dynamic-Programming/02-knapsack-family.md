# The Knapsack Family

> **Band:** 🟢→🟠 1200–2400 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [DP first principles](01-dp-first-principles-and-state-design.md), [bit manipulation](../01-Foundations/03-bit-manipulation.md)
> **You can say you know this when:** you can explain from the in-place update why 0/1 knapsack loops capacity downward and unbounded upward; you pick between weight-indexed and value-indexed tables from the constraints; you can count combinations vs ordered sequences without mixing them up; you can do bounded knapsack by binary splitting and subset sum with a bitset in both C++ and Java; and you can reconstruct a (lexicographically smallest) optimal set.

"Knapsack" is shorthand for a whole class: *process items one by one; the state is (how many items processed, how much of some resource is used)*. Once you see it as that, dozens of problems that never mention a bag — splitting an array into two equal halves, reaching a score, choosing bottles, picking projects — collapse into the same three loops.

---

## 1. First principles — why this works

### 1.1 The state, derived

Items $1..n$ with weight $w_i$ and value $v_i$; choose a subset with $\sum w \le W$ maximising $\sum v$. Brute force: $2^n$ subsets.

Decide items in index order. What does the future (items $i+1..n$) need to know about the decisions made so far? Not *which* items were taken — only **how much capacity is used**. Two histories with the same used weight are equivalent; the one with larger value dominates. State $(i, w)$:

$$f_i(w) = \max\big(f_{i-1}(w),\; f_{i-1}(w - w_i) + v_i\big), \qquad f_0(0) = 0,\; f_0(w>0) = -\infty .$$

$(n+1)(W+1)$ states, 2 transitions each: $O(nW)$. This is **pseudo-polynomial** — polynomial in the *value* $W$, exponential in its bit length. Knapsack is NP-hard, so nothing polynomial in $\log W$ is expected; whenever a knapsack problem has $W \approx 10^9$, the constraints are telling you to index by something else (§1.6) or to split the items in half ([meet in the middle](../02-Core-Techniques/06-ternary-search-and-meet-in-the-middle.md)).

**"Exactly $w$" vs "at most $w$".** With $f_0(w>0) = -\infty$, $f_n(w)$ is the best value of total weight *exactly* $w$, and the answer is $\max_{w \le W} f_n(w)$. Initialising every $f_0(w) = 0$ instead makes $f_n(w)$ the best with weight *at most* $w$ (an unused slack is free), and the answer is $f_n(W)$. Both are right; mixing them is the bug. Feasibility and counting versions must use the "exactly" form.

### 1.2 Rolling to one array — why 0/1 iterates capacity downward

Layer $i$ reads only layer $i-1$, so keep one array and overwrite it in place. When we compute the new $f(w)$ we need the **old** $f(w - w_i)$.

- Loop $w$ **downward** ($W \to w_i$): position $w - w_i < w$ has not been touched yet in this round, so it still holds the layer-$(i-1)$ value. Each item is used at most once. ✔ 0/1 knapsack.
- Loop $w$ **upward**: $f(w - w_i)$ has already been updated *in this round* — it may already contain item $i$. Using it adds item $i$ again. So the upward loop computes
  $$f_i(w) = \max\big(f_{i-1}(w),\; f_i(w - w_i) + v_i\big),$$
  which is exactly the recurrence for **unbounded** knapsack (classify by "is there at least one more copy of item $i$?").

The loop direction *is* the difference between the two problems. Memorise the reason, not the direction.

### 1.3 Bounded knapsack — binary splitting

Item $i$ may be taken up to $c_i$ times. Naively, treat it as $c_i$ separate items: $O(W \sum c_i)$.

**Binary splitting.** Replace the $c$ copies by bundles of sizes $1, 2, 4, \dots, 2^{k-1}$ and a remainder $r = c - (2^k - 1)$, where $k$ is the largest integer with $2^k - 1 \le c$ (so $0 \le r < 2^k$). Each bundle is one 0/1 item with weight and value multiplied by its size.

*Claim:* the subset sums of $\{1, 2, \dots, 2^{k-1}, r\}$ are exactly $\{0, 1, \dots, c\}$.
*Proof:* any $t \le 2^k - 1$ is a sum of powers (binary). For $2^k \le t \le c$, $t - r \in [2^k - r,\, 2^k-1] \subseteq [0, 2^k-1]$, so $t = r + (\text{powers})$. And the total is $c$, so nothing exceeds $c$. ∎

Each item becomes $O(\log c_i)$ bundles: $O(W \sum \log c_i)$. An $O(nW)$ method exists using a **monotonic deque** per residue class $w \bmod w_i$ ([monotonic-queue optimisation](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md)); for counting/feasibility versions a sliding-window *sum* per residue class gives $O(nW)$ too.

### 1.4 Group (multiple-choice) knapsack

Items are partitioned into groups; take **at most one** item per group. Process groups as layers. Inside a group, every item must read the value *before this group*:

```text
for each group G:
    for w = W down to 0:              // outer: capacity, downward
        for each item (wt, val) in G: // inner: items of the group
            if wt <= w: f[w] = max(f[w], f[w - wt] + val)
```

Because $w$ is the outer loop and goes downward, $f[w - wt]$ is still the pre-group value for every item in the group, so at most one item of the group is added. Swapping the two loops (items outer) would allow one item per group *per item*, i.e. several items of the same group. Cost $O(W \cdot \text{total items})$. "Exactly one per group" = initialise the new layer to $-\infty$ and copy nothing from the old one.

### 1.5 Counting ways — combinations vs ordered sequences

Coins $c_1..c_n$ (unlimited); count ways to make sum $x$.

- **Ordered sequences** ("1+2" and "2+1" differ): fix the **last coin** of the sequence — any coin. $g(s) = \sum_j g(s - c_j)$, $g(0) = 1$. Loop *sum outer, coins inner.*
- **Multisets** ("1+2" = "2+1"): a multiset has no "last" coin, so make it canonical — list coins **in type order**. Then process coin types one at a time; for type $j$, either use no more of it or use one more: $h_j(s) = h_{j-1}(s) + h_j(s - c_j)$. Loop *coins outer, sums inner (upward)*.

Each loop order counts each object exactly once *under its own canonical form*; using the wrong order silently counts the other object. This is the cleanest illustration of the rule "counting needs an unambiguous decomposition" ([first principles](01-dp-first-principles-and-state-design.md) §1.9).

The generating-function view makes it mechanical: multisets of coins have generating function $\prod_j \frac{1}{1 - x^{c_j}}$, ordered sequences $\frac{1}{1 - \sum_j x^{c_j}}$, and 0/1 subsets $\prod_i (1 + x^{w_i})$. Each DP loop is "multiply by one factor" ([generating functions](../15-Advanced-Math/04-polynomials-and-generating-functions.md)).

### 1.6 Value-indexed knapsack — swap the roles

If $W$ is huge ($10^9$) but values are small ($\sum v \le 10^5$), the weight dimension is unusable. The state only needs *one* of the two quantities as an index — the other can be the optimised value:

$$g_i(v) = \min\big(g_{i-1}(v),\; g_{i-1}(v - v_i) + w_i\big), \qquad g_0(0) = 0,\ g_0(v>0)=+\infty,$$

$g(v)$ = minimum weight achieving value exactly $v$. Answer: the largest $v$ with $g(v) \le W$. $O(n \sum v)$. The general lesson: **put the small-range quantity in the index and optimise the other one.** With three quantities (weight, value, count), the index is whichever two are small.

### 1.7 Subset sum with bitsets

Feasibility: which sums are reachable? The set $R$ of reachable sums updates as $R \leftarrow R \cup (R + w_i)$. Store $R$ as a bit array; then "$R + w_i$" is a left shift:

$$R \leftarrow R \;\lor\; (R \ll w_i).$$

Each update costs $S/64$ word operations: $O(nS/64)$. In C++ `std::bitset<N>` does it in one line (N must be a compile-time constant — take the maximum). Java has no shift on `BitSet`, so keep a `long[]` and shift by hand (§3.6). Typical gain: a 64× speed-up that turns $10^{10}$ into $1.6\cdot10^8$.

Two classic accelerations for subset sum with total $S$: there are at most $O(\sqrt S)$ *distinct* item sizes (since $1+2+\dots+k \le S$), and equal sizes can be merged by binary splitting; together $O(S\sqrt S/64)$ ([bitset optimisation](../16-IGM-Frontier/05-bitset-optimization.md)).

### 1.8 Reconstruction

The rolled 1D array forgets which items were taken. Options:

- Keep the full $(n+1)\times(W+1)$ table (fine when it fits) and walk back: item $i$ was taken iff $f_i(w) \ne f_{i-1}(w)$.
- Keep one **decision bit** per $(i, w)$: $nW$ bits = $nW/8$ bytes.
- For the **lexicographically smallest** optimal set: compute the DP over *suffixes* ($g_i(c)$ = best from items $i..n$ with capacity $c$), then walk forward, taking item $i$ whenever $g_i(c) = v_i + g_{i+1}(c - w_i)$. Requires every $v_i \ge 1$ so that no optimal set is a prefix of another (Example 6).

### 1.9 Variations you will meet

- **Minimum number of items** (coin change): min-plus semiring, $f(s) = \min_j f(s - c_j) + 1$, $f(0)=0$.
- **Negative weights / offsets**: shift the index by $\sum |\text{negative}|$ ($\sum(a_i - k b_i) = 0$ in CF 366C).
- **Two capacities** ($w$ and $u$): state $(i, w, u)$, loops both downward ([LC 474](https://leetcode.com/problems/ones-and-zeroes/)).
- **Partition into two parts with equal/closest sums**: subset sum to $\lfloor S/2 \rfloor$.
- **Order matters + knapsack**: sort by an exchange-argument key first (deadlines in CF 864E, project ratings in CF 1203F2), then knapsack in that order.
- **Knapsack on a tree** (take a vertex only with its parent): merge children's tables; the $O(n^2)$ bound comes from "sum of size products" ([tree DP](08-tree-dp-and-rerooting.md) §1.4).
- **Fractional knapsack**: greedy by $v/w$ is optimal — the only member of the family where greedy works.

---

## 2. Formulas, definitions and identities

| Variant | Recurrence (1-D, in place) | Loop order | Time |
|---|---|---|---|
| 0/1 | $f(w) \gets \max(f(w), f(w-w_i)+v_i)$ | $w$ downward | $O(nW)$ |
| unbounded | same | $w$ upward | $O(nW)$ |
| bounded ($c_i$ copies) | 0/1 on bundles $1,2,4,\dots,r$ | downward | $O(W\sum \log c_i)$ |
| bounded, deque | per residue class, sliding max of $f(w - kw_i) - kv_i$ | — | $O(nW)$ |
| group | $f(w) \gets \max_{i\in G}(f(w-w_i)+v_i)$ | $w$ downward outer, items inner | $O(W \cdot \#\text{items})$ |
| value-indexed | $g(v) \gets \min(g(v), g(v-v_i)+w_i)$ | $v$ downward | $O(n\sum v)$ |
| count multisets | $h(s) \mathrel{+}= h(s-c_j)$ | coins outer, $s$ upward | $O(nx)$ |
| count sequences | $g(s) = \sum_j g(s-c_j)$ | $s$ outer, coins inner | $O(nx)$ |
| count 0/1 subsets | $h(s) \mathrel{+}= h(s-w_i)$ | items outer, $s$ downward | $O(nS)$ |
| subset sum | $R \gets R \lor (R \ll w_i)$ | — | $O(nS/64)$ |
| min #items | $f(s) \gets \min(f(s), f(s-c)+1)$ | upward (unbounded) | $O(nx)$ |

**Generating functions:**
$$\text{0/1 subsets: } \prod_i (1 + x^{w_i}), \qquad \text{multisets: } \prod_j \frac{1}{1-x^{c_j}}, \qquad \text{sequences: } \frac{1}{1-\sum_j x^{c_j}}.$$
The coefficient of $x^s$ is the count. Proof: expand each factor; choosing a term from each factor is choosing a multiplicity.

**Binary splitting identity:** for $c = (2^k - 1) + r$ with $0 \le r < 2^k$,
$$\{ \textstyle\sum_{j\in J} b_j : J \subseteq \{1..k+1\} \} = \{0, 1, \dots, c\},\quad b = (1, 2, \dots, 2^{k-1}, r).$$

**Pigeonhole for subset sums mod $m$:** among the $m+1$ prefix sums $P_0 = 0, P_1, \dots, P_m$ of any $m$ numbers, two are congruent mod $m$, so some non-empty *contiguous* block (hence subset) has sum $\equiv 0$. So "is there a non-empty subset with sum divisible by $m$" is always YES when $n \ge m$ (CF 577B), and an $O(m^2)$ DP handles $n < m$.

**Number of distinct sizes:** if $\sum_i w_i = S$ with positive integers, the number of distinct $w_i$ is at most $\sqrt{2S}$.

---

## 3. Implementation (C++ and Java)

Reusable kernels. All take 0-indexed vectors/arrays. Values use 64-bit.

### 3.1 0/1 and unbounded (weight-indexed, "at most W")

```cpp
long long knap01(const vector<int>& w, const vector<long long>& v, int W) {
    vector<long long> f(W + 1, 0);                    // f[c]: best value with weight <= c
    for (size_t i = 0; i < w.size(); i++)
        for (int c = W; c >= w[i]; c--)                // downward: each item once
            f[c] = max(f[c], f[c - w[i]] + v[i]);
    return f[W];
}

long long knapUnbounded(const vector<int>& w, const vector<long long>& v, int W) {
    vector<long long> f(W + 1, 0);
    for (size_t i = 0; i < w.size(); i++)
        for (int c = w[i]; c <= W; c++)                // upward: item reusable
            f[c] = max(f[c], f[c - w[i]] + v[i]);
    return f[W];
}
```

```java
static long knap01(int[] w, long[] v, int W) {
    long[] f = new long[W + 1];
    for (int i = 0; i < w.length; i++)
        for (int c = W; c >= w[i]; c--)
            f[c] = Math.max(f[c], f[c - w[i]] + v[i]);
    return f[W];
}

static long knapUnbounded(int[] w, long[] v, int W) {
    long[] f = new long[W + 1];
    for (int i = 0; i < w.length; i++)
        for (int c = w[i]; c <= W; c++)
            f[c] = Math.max(f[c], f[c - w[i]] + v[i]);
    return f[W];
}
```

### 3.2 Bounded knapsack by binary splitting

```cpp
// Item i has weight w[i], value v[i], and at most cnt[i] copies.
long long knapBounded(const vector<int>& w, const vector<long long>& v, const vector<int>& cnt, int W) {
    vector<long long> f(W + 1, 0);
    for (size_t i = 0; i < w.size(); i++) {
        int c = cnt[i];
        for (int b = 1; c > 0; b <<= 1) {
            int take = min(b, c);                      // bundle sizes 1, 2, 4, ..., remainder
            c -= take;
            long long bw = 1LL * take * w[i], bv = take * v[i];
            for (long long cap = W; cap >= bw; cap--) f[cap] = max(f[cap], f[cap - bw] + bv);
        }
    }
    return f[W];
}
```

```java
static long knapBounded(int[] w, long[] v, int[] cnt, int W) {
    long[] f = new long[W + 1];
    for (int i = 0; i < w.length; i++) {
        int c = cnt[i];
        for (int b = 1; c > 0; b <<= 1) {
            int take = Math.min(b, c);
            c -= take;
            long bw = (long) take * w[i], bv = take * v[i];
            for (long cap = W; cap >= bw; cap--)
                f[(int) cap] = Math.max(f[(int) cap], f[(int) (cap - bw)] + bv);
        }
    }
    return f[W];
}
```

The loop `take = min(b, c)` produces $1, 2, 4, \dots$ and then the leftover; its subset sums are $\{0..c\}$ by the same argument as §1.3 (the leftover is at most the next power).

### 3.3 Group knapsack (at most one item per group)

```cpp
// groups[g] = list of (weight, value). Returns best value with weight <= W.
long long knapGroups(const vector<vector<pair<int, long long>>>& groups, int W) {
    vector<long long> f(W + 1, 0);
    for (const auto& G : groups)
        for (int c = W; c >= 0; c--)                   // capacity outer and downward
            for (auto [wt, val] : G)                   // every item reads the pre-group f
                if (wt <= c) f[c] = max(f[c], f[c - wt] + val);
    return f[W];
}
```

```java
// groupW[g][k], groupV[g][k]: the k-th item of group g.
static long knapGroups(int[][] groupW, long[][] groupV, int W) {
    long[] f = new long[W + 1];
    for (int g = 0; g < groupW.length; g++)
        for (int c = W; c >= 0; c--)
            for (int k = 0; k < groupW[g].length; k++)
                if (groupW[g][k] <= c) f[c] = Math.max(f[c], f[c - groupW[g][k]] + groupV[g][k]);
    return f[W];
}
```

### 3.4 Counting: multisets, sequences, 0/1 subsets, and minimum coins

```cpp
const long long MOD = 1'000'000'007;

long long countMultisets(const vector<int>& coins, int x) {      // order does not matter
    vector<long long> h(x + 1, 0);
    h[0] = 1;
    for (int c : coins)
        for (int s = c; s <= x; s++) h[s] = (h[s] + h[s - c]) % MOD;
    return h[x];
}

long long countSequences(const vector<int>& coins, int x) {      // order matters
    vector<long long> g(x + 1, 0);
    g[0] = 1;
    for (int s = 1; s <= x; s++)
        for (int c : coins)
            if (c <= s) g[s] = (g[s] + g[s - c]) % MOD;
    return g[x];
}

long long countSubsets(const vector<int>& w, int S) {            // each item at most once
    vector<long long> h(S + 1, 0);
    h[0] = 1;
    for (int wi : w)
        for (int s = S; s >= wi; s--) h[s] = (h[s] + h[s - wi]) % MOD;
    return h[S];
}

int minCoins(const vector<int>& coins, int x) {                  // -1 if impossible
    const int INF = INT_MAX / 2;
    vector<int> f(x + 1, INF);
    f[0] = 0;
    for (int c : coins)
        for (int s = c; s <= x; s++) f[s] = min(f[s], f[s - c] + 1);
    return f[x] >= INF ? -1 : f[x];
}
```

```java
static final long MOD = 1_000_000_007L;

static long countMultisets(int[] coins, int x) {
    long[] h = new long[x + 1];
    h[0] = 1;
    for (int c : coins)
        for (int s = c; s <= x; s++) h[s] = (h[s] + h[s - c]) % MOD;
    return h[x];
}

static long countSequences(int[] coins, int x) {
    long[] g = new long[x + 1];
    g[0] = 1;
    for (int s = 1; s <= x; s++)
        for (int c : coins)
            if (c <= s) g[s] = (g[s] + g[s - c]) % MOD;
    return g[x];
}

static long countSubsets(int[] w, int S) {
    long[] h = new long[S + 1];
    h[0] = 1;
    for (int wi : w)
        for (int s = S; s >= wi; s--) h[s] = (h[s] + h[s - wi]) % MOD;
    return h[S];
}

static int minCoins(int[] coins, int x) {
    final int INF = Integer.MAX_VALUE / 2;
    int[] f = new int[x + 1];
    Arrays.fill(f, INF);
    f[0] = 0;
    for (int c : coins)
        for (int s = c; s <= x; s++) f[s] = Math.min(f[s], f[s - c] + 1);
    return f[x] >= INF ? -1 : f[x];
}
```

### 3.5 Value-indexed knapsack

```cpp
// Max total value with total weight <= W, when sum of values is small.
long long knapByValue(const vector<long long>& w, const vector<int>& v, long long W) {
    int V = accumulate(v.begin(), v.end(), 0);
    const long long INF = LLONG_MAX / 4;
    vector<long long> g(V + 1, INF);                   // g[val]: min weight for value exactly val
    g[0] = 0;
    for (size_t i = 0; i < w.size(); i++)
        for (int val = V; val >= v[i]; val--) g[val] = min(g[val], g[val - v[i]] + w[i]);
    for (int val = V; val >= 0; val--)
        if (g[val] <= W) return val;
    return 0;
}
```

```java
static long knapByValue(long[] w, int[] v, long W) {
    int V = 0;
    for (int x : v) V += x;
    final long INF = Long.MAX_VALUE / 4;
    long[] g = new long[V + 1];
    Arrays.fill(g, INF);
    g[0] = 0;
    for (int i = 0; i < w.length; i++)
        for (int val = V; val >= v[i]; val--) g[val] = Math.min(g[val], g[val - v[i]] + w[i]);
    for (int val = V; val >= 0; val--)
        if (g[val] <= W) return val;
    return 0;
}
```

### 3.6 Subset sum with a bitset

```cpp
const int MAXS = 100001;
// Returns the set of reachable sums (bit s set iff some subset sums to s).
bitset<MAXS> subsetSums(const vector<int>& a) {
    bitset<MAXS> R;
    R[0] = 1;
    for (int x : a) R |= R << x;                       // O(MAXS / 64) per item
    return R;
}
```

```java
// b |= b << s on a bit array stored in long words (bit k lives in b[k >> 6]).
static void shiftOr(long[] b, int s) {
    int ws = s >>> 6, bs = s & 63;
    for (int i = b.length - 1; i >= ws; i--) {         // high to low: sources are still old
        long v = b[i - ws] << bs;
        if (bs != 0 && i - ws - 1 >= 0) v |= b[i - ws - 1] >>> (64 - bs);
        b[i] |= v;
    }
}

static long[] subsetSums(int[] a, int maxS) {
    long[] b = new long[(maxS >> 6) + 1];
    b[0] = 1L;
    for (int x : a) shiftOr(b, x);
    return b;                                          // test bit s: (b[s >> 6] >>> (s & 63) & 1) != 0
}
```

Use `>>>` (unsigned shift) in Java when moving bits down; `>>` would smear the sign bit into the word.

---

## 4. Recognising the pattern

| Signal | Variant |
|---|---|
| "choose a subset", total of something ≤ limit, maximise another total | 0/1 knapsack; index by the small-range quantity |
| capacity up to $10^9$ but values (or counts) small | value-indexed (§1.6) |
| "unlimited supply", "any number of times" | unbounded (upward loop) |
| "at most $c_i$ copies" | bounded: binary splitting or deque |
| "split into two groups with equal / closest sums", "can we reach exactly $S$?" | subset sum, bitset |
| "choose one option from each category" | group knapsack |
| "number of ways to pay", "in how many orders" | counting: decide multiset vs sequence *first* |
| two resources (e.g. zeros and ones) | 2-D capacity |
| $n \le 40$, weights huge | meet in the middle, not knapsack |
| "the sum must be divisible by $m$" | knapsack over residues mod $m$ (and pigeonhole when $n \ge m$) |
| items with deadlines / prerequisites ordering | sort by exchange argument, then knapsack |
| choose a vertex only if its parent is chosen | tree knapsack ([tree DP](08-tree-dp-and-rerooting.md)) |

Often confused with: **greedy by ratio** (correct only for fractional knapsack or special coin systems — "canonical" coin systems like 1,2,5,10 happen to be greedy-optimal, arbitrary ones are not: coins $\{1,3,4\}$, sum 6: greedy $4+1+1$, optimal $3+3$).

---

## 5. Worked examples (graded)

### Example 1 — Knapsack 1  ·  ★ ≈1100 (est.)

- **Source:** [AtCoder DP D · Knapsack 1](https://atcoder.jp/contests/dp/tasks/dp_d)
- **Difficulty:** ≈1100 (est.)
- **Problem:** $n \le 100$ items, capacity $W \le 10^5$, weights $w_i \le W$, values $v_i \le 10^9$. Maximise total value with total weight $\le W$.
- **Thinking from first principles:** $nW = 10^7$ states — fine. The value sum reaches $10^{11}$, so values need 64-bit; that is the only trap. Use the "at most" initialisation so the answer is $f(W)$ directly.

<details><summary>Solution</summary>

One array, capacity downward. $O(nW)$ time, $O(W)$ memory.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, W;
    cin >> n >> W;
    vector<long long> f(W + 1, 0);
    for (int i = 0; i < n; i++) {
        int w;
        long long v;
        cin >> w >> v;
        for (int c = W; c >= w; c--) f[c] = max(f[c], f[c - w] + v);
    }
    cout << f[W] << "\n";
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
        int n = (int) nl(), W = (int) nl();
        long[] f = new long[W + 1];
        for (int i = 0; i < n; i++) {
            int w = (int) nl();
            long v = nl();
            for (int c = W; c >= w; c--) f[c] = Math.max(f[c], f[c - w] + v);
        }
        System.out.println(f[W]);
    }
}
```

</details>

<!-- test
in:
4 10
5 10
4 40
6 30
3 50
out:
90
-->
<!-- test
in:
1 5
6 100
out:
0
-->
<!-- test
in:
2 2
1 1000000000
1 1000000000
out:
2000000000
-->

### Example 2 — Knapsack 2  ·  ★ ≈1300 (est.)

- **Source:** [AtCoder DP E · Knapsack 2](https://atcoder.jp/contests/dp/tasks/dp_e)
- **Difficulty:** ≈1300 (est.)
- **Problem:** Same as Example 1 but $W \le 10^9$, $w_i \le W$ and $v_i \le 10^3$ ($n \le 100$).
- **Thinking from first principles:** The weight index is dead ($10^{11}$ states). But the total value is at most $10^5$. The state needs only one of (weight, value) as an index; the other can be optimised. Index by value, minimise weight.

<details><summary>Solution</summary>

$g(v)$ = min weight of a subset with value exactly $v$. Answer = max $v$ with $g(v) \le W$. $O(n \sum v) = 10^7$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    long long W;
    cin >> n >> W;
    vector<long long> w(n);
    vector<int> v(n);
    for (int i = 0; i < n; i++) cin >> w[i] >> v[i];
    int V = accumulate(v.begin(), v.end(), 0);
    const long long INF = LLONG_MAX / 4;
    vector<long long> g(V + 1, INF);
    g[0] = 0;
    for (int i = 0; i < n; i++)
        for (int val = V; val >= v[i]; val--) g[val] = min(g[val], g[val - v[i]] + w[i]);
    int ans = 0;
    for (int val = 0; val <= V; val++)
        if (g[val] <= W) ans = val;
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
        long W = nl();
        long[] w = new long[n];
        int[] v = new int[n];
        int V = 0;
        for (int i = 0; i < n; i++) { w[i] = nl(); v[i] = (int) nl(); V += v[i]; }
        final long INF = Long.MAX_VALUE / 4;
        long[] g = new long[V + 1];
        Arrays.fill(g, INF);
        g[0] = 0;
        for (int i = 0; i < n; i++)
            for (int val = V; val >= v[i]; val--) g[val] = Math.min(g[val], g[val - v[i]] + w[i]);
        int ans = 0;
        for (int val = 0; val <= V; val++) if (g[val] <= W) ans = val;
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
3 1000000000
1000000000 7
1 3
999999999 5
out:
8
-->
<!-- test
in:
1 1
2 10
out:
0
-->
<!-- test
in:
2 10
5 1000
5 1000
out:
2000
-->

### Example 3 — Ordered vs unordered coin sums  ·  ★ ≈1300 (est.)

- **Source:** Original problem (it combines [CSES 1635 · Coin Combinations I](https://cses.fi/problemset/task/1635) and [CSES 1636 · Coin Combinations II](https://cses.fi/problemset/task/1636)).
- **Difficulty:** ≈1300 (est.)
- **Problem:** $n \le 100$ distinct coin values $c_i \le 10^5$, unlimited supply, target $x \le 10^5$. Print (1) the number of *ordered* sequences of coins summing to $x$ and (2) the number of *multisets*, both mod $10^9+7$.
- **Thinking from first principles:** For sequences, the last coin is well defined; classify by it. For multisets there is no "last" coin until we impose an order — sort the multiset by coin type, and then "the type of the largest coin used" or equivalently "process types one by one" is canonical. The two loop nests differ only in which loop is outside; the semantics differ completely. Writing both in one program is the best way to never confuse them again.

<details><summary>Solution</summary>

Sequences: $g(s) = \sum_j g(s - c_j)$, sums outer. Multisets: for each coin type, $h(s) \mathrel{+}= h(s - c)$ for $s$ upward. Both $O(nx)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    const int MOD = 1'000'000'007;
    int n, x;
    cin >> n >> x;
    vector<int> c(n);
    for (auto& v : c) cin >> v;
    vector<int> g(x + 1, 0), h(x + 1, 0);
    g[0] = h[0] = 1;
    for (int s = 1; s <= x; s++)                       // ordered: last coin is any coin
        for (int v : c)
            if (v <= s) { g[s] += g[s - v]; if (g[s] >= MOD) g[s] -= MOD; }
    for (int v : c)                                    // unordered: coin types in a fixed order
        for (int s = v; s <= x; s++) { h[s] += h[s - v]; if (h[s] >= MOD) h[s] -= MOD; }
    cout << g[x] << " " << h[x] << "\n";
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
        int n = (int) nl(), x = (int) nl();
        int[] c = new int[n];
        for (int i = 0; i < n; i++) c[i] = (int) nl();
        int[] g = new int[x + 1], h = new int[x + 1];
        g[0] = h[0] = 1;
        for (int s = 1; s <= x; s++)
            for (int v : c)
                if (v <= s) { g[s] += g[s - v]; if (g[s] >= MOD) g[s] -= MOD; }
        for (int v : c)
            for (int s = v; s <= x; s++) { h[s] += h[s - v]; if (h[s] >= MOD) h[s] -= MOD; }
        System.out.println(g[x] + " " + h[x]);
    }
}
```

</details>

<!-- test
in:
3 9
2 3 5
out:
8 3
-->
<!-- test
in:
1 7
2
out:
0 0
-->
<!-- test
in:
2 4
1 2
out:
5 3
-->

### Example 4 — Money Sums (bitset subset sum)  ·  ★ ≈1300 (est.)

- **Source:** [CSES 1745 · Money Sums](https://cses.fi/problemset/task/1745)
- **Difficulty:** ≈1300 (est.)
- **Problem:** $n \le 100$ coins with values $x_i \le 1000$. Print the number of distinct non-zero sums obtainable from subsets, then the sums in increasing order.
- **Thinking from first principles:** The question is pure feasibility over sums $\le 10^5$: boolean 0/1 knapsack, $10^7$ bit updates. With a bitset it is $10^7/64 \approx 1.6\cdot 10^5$ word operations. Even the plain boolean array passes, but this is the cleanest place to practise the bitset idiom in both languages.

<details><summary>Solution</summary>

$R \leftarrow R \lor (R \ll x_i)$ starting from $R = \{0\}$; print every set bit except 0.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    const int MAXS = 100001;
    int n;
    cin >> n;
    bitset<MAXS> R;
    R[0] = 1;
    for (int i = 0; i < n; i++) {
        int x;
        cin >> x;
        R |= R << x;
    }
    vector<int> sums;
    for (int s = 1; s < MAXS; s++)
        if (R[s]) sums.push_back(s);
    cout << sums.size() << "\n";
    for (size_t i = 0; i < sums.size(); i++) cout << sums[i] << " \n"[i + 1 == sums.size()];
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

    static void shiftOr(long[] b, int s) {               // b |= b << s
        int ws = s >>> 6, bs = s & 63;
        for (int i = b.length - 1; i >= ws; i--) {
            long v = b[i - ws] << bs;
            if (bs != 0 && i - ws - 1 >= 0) v |= b[i - ws - 1] >>> (64 - bs);
            b[i] |= v;
        }
    }

    public static void main(String[] args) throws IOException {
        final int MAXS = 100001;
        int n = (int) nl();
        long[] b = new long[(MAXS >> 6) + 1];
        b[0] = 1L;
        for (int i = 0; i < n; i++) shiftOr(b, (int) nl());
        StringBuilder sb = new StringBuilder();
        int cnt = 0;
        for (int s = 1; s < MAXS; s++)
            if ((b[s >> 6] >>> (s & 63) & 1L) != 0) {
                if (cnt++ > 0) sb.append(' ');
                sb.append(s);
            }
        System.out.println(cnt);
        System.out.println(sb);
    }
}
```

</details>

<!-- test
in:
4
4 2 5 2
out:
9
2 4 5 6 7 8 9 11 13
-->
<!-- test
in:
1
1000
out:
1
1000
-->
<!-- test
in:
3
3 3 3
out:
3
3 6 9
-->

### Example 5 — Book Shop II (bounded knapsack)  ·  ★ ≈1800 (est.)

- **Source:** [CSES 1159 · Book Shop II](https://cses.fi/problemset/task/1159)
- **Difficulty:** ≈1800 (est.)
- **Problem:** $n \le 100$ book types; type $i$ costs $h_i \le 1000$, has $s_i \le 1000$ pages and there are $k_i \le 1000$ copies. Budget $x \le 10^5$. Maximise the total number of pages.
- **Thinking from first principles:** Expanding copies gives up to $10^5$ items × $10^5$ capacity $= 10^{10}$ — too slow. But we never need to know *which* copies we took, only how many, and the binary bundles $1,2,4,\dots,r$ realise every count $0..k_i$ (§1.3). Items become $100 \cdot 10 = 1000$ bundles: $10^8$ simple updates, fine in both languages.

<details><summary>Solution</summary>

Split each type into bundles, then run 0/1 knapsack (capacity downward) over the bundles. $O(x \sum \log k_i)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, x;
    cin >> n >> x;
    vector<int> h(n), s(n), k(n);
    for (auto& v : h) cin >> v;
    for (auto& v : s) cin >> v;
    for (auto& v : k) cin >> v;
    vector<int> f(x + 1, 0);
    for (int i = 0; i < n; i++) {
        int left = k[i];
        for (int b = 1; left > 0; b <<= 1) {
            int take = min(b, left);
            left -= take;
            long long cost = 1LL * take * h[i];
            int pages = take * s[i];
            for (long long c = x; c >= cost; c--) f[c] = max(f[c], f[c - cost] + pages);
        }
    }
    cout << f[x] << "\n";
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
        int n = (int) nl(), x = (int) nl();
        int[] h = new int[n], s = new int[n], k = new int[n];
        for (int i = 0; i < n; i++) h[i] = (int) nl();
        for (int i = 0; i < n; i++) s[i] = (int) nl();
        for (int i = 0; i < n; i++) k[i] = (int) nl();
        int[] f = new int[x + 1];
        for (int i = 0; i < n; i++) {
            int left = k[i];
            for (int b = 1; left > 0; b <<= 1) {
                int take = Math.min(b, left);
                left -= take;
                long cost = (long) take * h[i];
                if (cost > x) continue;
                int pages = take * s[i], cst = (int) cost;
                for (int c = x; c >= cst; c--) f[c] = Math.max(f[c], f[c - cst] + pages);
            }
        }
        System.out.println(f[x]);
    }
}
```

</details>

<!-- test
in:
3 10
4 8 5
5 12 8
3 2 1
out:
13
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

### Example 6 — Lexicographically smallest optimal set  ·  ★ ≈1700 (est.)

- **Source:** Original problem.
- **Difficulty:** ≈1700 (est.)
- **Problem:** $n \le 100$ items with weight $1 \le w_i \le 10^4$ and value $1 \le v_i \le 10^9$; capacity $W \le 10^4$. Print the maximum value, the number of items in an optimal set, and the indices of the **lexicographically smallest** optimal set (indices in increasing order).
- **Thinking from first principles:** Any optimal set is easy to recover by walking the table backward from $(n, W)$, but backward walking decides item $n$ first, which optimises the *last* index, not the first. To make the *first* chosen index as small as possible we need to know, while standing at item $i$ with remaining capacity $c$, "can I still finish optimally if I take $i$?" That is a question about the **suffix** $i..n$ — so run the DP over suffixes and walk forward. Because all values are $\ge 1$, no optimal set is a proper subset of another, so greedily minimising each next index yields the lexicographic minimum.

<details><summary>Solution</summary>

$g_i(c)$ = best value from items $i..n-1$ with capacity $c$; $g_n \equiv 0$, $g_i(c) = \max(g_{i+1}(c), v_i + g_{i+1}(c - w_i))$. Walk $i = 0..n-1$ with $c = W$: take $i$ iff $w_i \le c$ and $g_i(c) = v_i + g_{i+1}(c - w_i)$. Time and memory $O(nW) = 10^6$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, W;
    cin >> n >> W;
    vector<int> w(n);
    vector<long long> v(n);
    for (int i = 0; i < n; i++) cin >> w[i] >> v[i];
    vector<vector<long long>> g(n + 1, vector<long long>(W + 1, 0));   // suffix DP
    for (int i = n - 1; i >= 0; i--)
        for (int c = 0; c <= W; c++) {
            g[i][c] = g[i + 1][c];
            if (w[i] <= c) g[i][c] = max(g[i][c], v[i] + g[i + 1][c - w[i]]);
        }
    vector<int> pick;
    for (int i = 0, c = W; i < n; i++)
        if (w[i] <= c && g[i][c] == v[i] + g[i + 1][c - w[i]]) {     // taking i keeps optimality
            pick.push_back(i + 1);
            c -= w[i];
        }
    cout << g[0][W] << "\n" << pick.size() << "\n";
    for (size_t k = 0; k < pick.size(); k++) cout << pick[k] << (k + 1 == pick.size() ? "" : " ");
    cout << "\n";
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
        int n = (int) nl(), W = (int) nl();
        int[] w = new int[n];
        long[] v = new long[n];
        for (int i = 0; i < n; i++) { w[i] = (int) nl(); v[i] = nl(); }
        long[][] g = new long[n + 1][W + 1];
        for (int i = n - 1; i >= 0; i--)
            for (int c = 0; c <= W; c++) {
                g[i][c] = g[i + 1][c];
                if (w[i] <= c) g[i][c] = Math.max(g[i][c], v[i] + g[i + 1][c - w[i]]);
            }
        StringJoiner sj = new StringJoiner(" ");
        int cnt = 0;
        for (int i = 0, c = W; i < n; i++)
            if (w[i] <= c && g[i][c] == v[i] + g[i + 1][c - w[i]]) {
                sj.add(Integer.toString(i + 1));
                cnt++;
                c -= w[i];
            }
        System.out.println(g[0][W] + "\n" + cnt + "\n" + sj);
    }
}
```

</details>

<!-- test
in:
5 7
3 5
4 6
2 3
5 8
3 5
out:
11
2
1 2
-->
<!-- test
in:
3 4
2 1
2 1
2 1
out:
2
2
1 2
-->
<!-- test
in:
2 3
5 9
4 9
out:
0
0
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Loop direction encodes the problem.** Downward = each item once; upward = unlimited. Re-derive it from "does $f(w - w_i)$ still hold the old layer?" whenever in doubt.
2. **"Exactly" vs "at most"** initialisation (§1.1). Counting and feasibility must use "exactly" ($f(0)=1$, others 0).
3. **Pick the index by range.** If $W$ is huge, index by value or by count (Example 2). If both are huge but $n \le 40$, meet in the middle.
4. **Overflow.** Values up to $10^9$ × 100 items exceed `int`. In bounded knapsack, `take * w[i]` can exceed `int` before the comparison — compute in 64-bit (Example 5).
5. **Group knapsack loop order:** capacity outer (downward), items of the group inner. Items outer lets two items of the same group combine.
6. **Counting multisets vs sequences:** coins outer = multisets; sum outer = sequences. Say which one the statement wants before writing a loop.
7. **Mod in tight loops:** `if (x >= MOD) x -= MOD;` instead of `%` doubles the speed of counting knapsacks; Java `int` with this trick is safe since $2 \cdot MOD < 2^{31}$.
8. **`std::bitset` size is a compile-time constant.** Use the maximum over all tests; for many test cases with small sums, a dynamic bitset or a plain `vector<char>` may be faster than shifting a huge bitset.
9. **Java bitsets:** `java.util.BitSet` has no shift; write `shiftOr` on `long[]` and use `>>>` for the carry. Iterate the target words from high to low so sources are not yet modified.
10. **Unreachable states in min-weight tables:** `INF + w` must not overflow; use `LLONG_MAX/4` or skip INF entries.
11. **Reconstruction needs the table.** Rolling to 1D loses it; keep $(n+1)\times(W+1)$ or decision bits. For lexicographic minimality, use suffix DP + forward walk (Example 6).
12. **Zero-weight items** in an "at most" knapsack are harmless in 0/1 (downward loop still reads old values) but make unbounded knapsack ill-defined (infinite value) — handle them separately.
13. **Dominated items:** for each weight keep only the best value (unbounded) — the $O(\sqrt S)$ distinct-sizes fact then bounds the work.
14. **Java `long[][]` of size $10^2 \times 10^5$** is fine ($8\cdot10^7$ bytes = 80 MB — check the memory limit!). Prefer a 1-D array whenever no reconstruction is needed.

---

## 7. Going further (toward 2400–2600+)

- **Bounded knapsack in $O(nW)$** with a monotonic deque per residue class; and the counting version with sliding window sums ([monotonic queue](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md)).
- **Subset sum in $O(S\sqrt S / 64)$**: merge equal sizes by binary splitting, then bitset (CF 755F).
- **Knapsack with huge $W$ and few distinct weights**: work modulo the smallest weight (shortest paths over residues — "coin problem"/Frobenius, a Dijkstra in disguise).
- **Counting subset sums of all prefixes/segments**: ABC159 F — add a fresh "start" mass at each index.
- **Max-plus convolution** of concave sequences is linear (merging knapsacks of identical items); general max-plus convolution has no known truly subquadratic algorithm, which is why "merge two knapsack tables" is $O(W^2)$ unless the structure helps.
- **Polynomial methods**: counting subsets with sum $s$ for all $s$ = $\prod (1+x^{w_i})$; with many items use $\log$/$\exp$ of power series ([FFT/NTT](../15-Advanced-Math/03-fft-and-ntt.md), [generating functions](../15-Advanced-Math/04-polynomials-and-generating-functions.md)) — $O(S \log S)$.
- **Lagrangian relaxation** of a knapsack constraint ("exactly $k$ items") is the Aliens trick ([WQS binary search](../07-DP-Optimizations/06-aliens-trick-wqs-binary-search.md)).

---

## 8. Practice ladder

**≤ 1400**
- [ ] [CSES 1634 · Minimizing Coins](https://cses.fi/problemset/task/1634) — min-plus unbounded
- [ ] [CSES 1635 · Coin Combinations I](https://cses.fi/problemset/task/1635) — sequences
- [ ] [CSES 1636 · Coin Combinations II](https://cses.fi/problemset/task/1636) — multisets
- [ ] [CSES 1158 · Book Shop](https://cses.fi/problemset/task/1158) — 0/1
- [ ] [CF 189A · Cut Ribbon](https://codeforces.com/problemset/problem/189/A) — 1300

**1400–1900**
- [ ] [CSES 1093 · Two Sets II](https://cses.fi/problemset/task/1093) — count subsets, halve with a modular inverse (or skip the last item)
- [ ] [CF 1516C · Baby Ehab Partitions Again](https://codeforces.com/problemset/problem/1516/C) — 1700
- [ ] [CF 1974E · Money Buys Happiness](https://codeforces.com/problemset/problem/1974/E) — 1800
- [ ] [CF 687C · The Values You Can Make](https://codeforces.com/problemset/problem/687/C) — 1900
- [ ] [CF 366C · Dima and Salad](https://codeforces.com/problemset/problem/366/C) — 1900
- [ ] [CF 19B · Checkout Assistant](https://codeforces.com/problemset/problem/19/B) — 1900
- [ ] [CF 577B · Modulo Sum](https://codeforces.com/problemset/problem/577/B) — 1900
- [ ] [CF 730J · Bottles](https://codeforces.com/problemset/problem/730/J) — 1900
- [ ] [AtCoder ABC169 F · Knapsack for All Subsets](https://atcoder.jp/contests/abc169/tasks/abc169_f) — ≈1700 (AtCoder est.)

**1900–2400**
- [ ] [CF 864E · Fire](https://codeforces.com/problemset/problem/864/E) — 2000
- [ ] [AtCoder ABC159 F · Knapsack for All Segments](https://atcoder.jp/contests/abc159/tasks/abc159_f) — ≈1900 (AtCoder est.)
- [ ] [CF 837D · Round Subset](https://codeforces.com/problemset/problem/837/D) — 2100
- [ ] [CF 1203F2 · Complete the Projects (hard version)](https://codeforces.com/problemset/problem/1203/F2) — 2300

**2400+**
- [ ] [CF 95E · Lucky Country](https://codeforces.com/problemset/problem/95/E) — 2500
- [ ] [CF 755F · PolandBall and Gifts](https://codeforces.com/problemset/problem/755/F) — 2600

---

## 9. LeetCode / FAANG cross-reference

- [LC 416 · Partition Equal Subset Sum](https://leetcode.com/problems/partition-equal-subset-sum/) — Medium — subset sum to $S/2$; a bitset makes it one line in C++.
- [LC 494 · Target Sum](https://leetcode.com/problems/target-sum/) — Medium — signs ⇒ subset with sum $(S+T)/2$; count subsets.
- [LC 474 · Ones and Zeroes](https://leetcode.com/problems/ones-and-zeroes/) — Medium — 0/1 knapsack with two capacities.
- [LC 1049 · Last Stone Weight II](https://leetcode.com/problems/last-stone-weight-ii/) — Medium — closest subset sum to $S/2$.
- [LC 322 · Coin Change](https://leetcode.com/problems/coin-change/) — Medium — min coins (min-plus, unbounded).
- [LC 518 · Coin Change II](https://leetcode.com/problems/coin-change-ii/) — Medium — count multisets (coins outer).
- [LC 377 · Combination Sum IV](https://leetcode.com/problems/combination-sum-iv/) — Medium — despite the name, counts *sequences* (sum outer).
- [LC 279 · Perfect Squares](https://leetcode.com/problems/perfect-squares/) — Medium — min coins with square denominations.
- [LC 879 · Profitable Schemes](https://leetcode.com/problems/profitable-schemes/) — Hard — counting knapsack, profit capped at the target ("at least $P$" ⇒ clamp).
- [LC 956 · Tallest Billboard](https://leetcode.com/problems/tallest-billboard/) — Hard — state = height difference, value = taller side.
- [LC 2585 · Number of Ways to Earn Points](https://leetcode.com/problems/number-of-ways-to-earn-points/) — Hard — bounded counting knapsack.
- [LC 1155 · Number of Dice Rolls With Target Sum](https://leetcode.com/problems/number-of-dice-rolls-with-target-sum/) — Medium — group knapsack, exactly one per group.

Interviewers love LC 416/494/322/518; the follow-ups are "reduce memory to 1-D" (§1.2) and "why does the loop go backwards?" — answer with the in-place argument.

---

## 10. Self-check

1. Prove that the upward 1-D loop solves the unbounded knapsack, not the 0/1 one.
2. When is the answer $f(W)$ and when is it $\max_{w\le W} f(w)$?
3. Show that bundles $1, 2, 4, 8, 5$ represent every count from 0 to 20.
4. You must count ways to pay 100 with coins {1, 5, 10} where "5+1" and "1+5" are the same. Which loop is outside?
5. $n = 200$, $W = 10^9$, $v_i \le 500$. Which table, and how big?
6. Why must group knapsack loop capacity outside the items of a group?
7. What breaks in Example 6 if some values are 0?
8. Name two ways to make subset sum over $S = 10^6$ with $n = 10^4$ items fast enough.

<details><summary>Answers</summary>

1. Ascending $w$ means $f(w - w_i)$ already belongs to layer $i$, so the recurrence is $f_i(w) = \max(f_{i-1}(w), f_i(w-w_i)+v_i)$: "either no copy of $i$, or one copy plus an optimal solution that may contain more copies". That is the unbounded recurrence.
2. If $f_0 \equiv 0$ (at-most semantics) the answer is $f(W)$; if $f_0(0)=0$ and $f_0(w>0) = -\infty$ (exact semantics), take $\max_{w\le W}$.
3. Powers 1,2,4,8 give 0..15; adding 5 gives 5..20. Together 0..20, and the total is 20.
4. Coins outside (multisets), sums inside ascending.
5. Value-indexed: $\sum v \le 10^5$ entries of min-weight, $200 \times 10^5 = 2\cdot10^7$ updates.
6. With capacity outside and downward, every item of the group reads $f(w - w_i)$ from before the group, so at most one is added. With items outside, the second item reads a value that may already include the first.
7. Two optimal sets could be nested ($\{1\}$ and $\{1,2\}$ with $v_2 = 0$); the forward greedy would add item 2 although the shorter list is lexicographically smaller (a prefix). With values $\ge 1$, nested optimal sets cannot exist.
8. A bitset ($10^{10}/64 \approx 1.6\cdot10^8$), and merging equal sizes with binary splitting (at most $\sqrt{2S} \approx 1400$ distinct sizes), which together give about $1400 \cdot \log \cdot 10^6/64$.

</details>
