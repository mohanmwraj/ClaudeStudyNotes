# Dynamic Programming — Cheat Sheet

Revision only. Full derivations: [06-Dynamic-Programming](../06-Dynamic-Programming/README.md) · ladder: [problems.md](../06-Dynamic-Programming/problems.md) · speed-ups: [DP optimisations cheat sheet](07-dp-optimizations-cheatsheet.md).

## 1. State design in 9 lines ([01](../06-Dynamic-Programming/01-dp-first-principles-and-state-design.md))

1. Write the brute-force recursion over decisions; its parameters are draft state.
2. Drop every parameter the future does not need (exact sum → sum mod $k$, set → size, sequence → last element).
3. Add what constraints check (last choice, run length, phase, tight flag, automaton state).
4. Find the progress measure (index ↑, mask ↑, interval length ↓, subtree size ↓) → evaluation order.
5. Count states × transitions vs ~$10^8$; memory vs 256 MB ($6.4\cdot10^7$ ints).
6. Base cases from the definition (empty prefix counts once).
7. Counting? Each object ↔ exactly one path (canonical decomposition).
8. Then roll arrays / optimise transitions.
9. Stress-test against the brute force.

Heuristics: **fix the last element / operation**; **add a dimension for what breaks the greedy**; **swap value and index** when one range is small.

## 2. Semirings

| Kind | ⊕ | ⊗ | init unreachable | note |
|---|---|---|---|---|
| min cost | min | + | $+\infty$ (`LLONG_MAX/4`) | idempotent: duplicates harmless |
| max value | max | + | $-\infty$ | never 0 for unreachable |
| count | + | × | 0 | mod $p$; no comparisons |
| feasibility | or | and | false | bitsets: 64× |
| probability | + | × | 0 | doubles or mod $p$ |

## 3. Signal → technique

| Signal | Technique / file |
|---|---|
| "number of ways mod $p$" | counting DP, canonical decomposition |
| choose subset, sum ≤ limit | knapsack; index the small-range quantity ([02](../06-Dynamic-Programming/02-knapsack-family.md)) |
| subsequence, increasing | LIS tails / Fenwick ([03](../06-Dynamic-Programming/03-sequence-dp-lis-lcs-edit-distance.md)) |
| two strings | $(i, j)$ table ([03](../06-Dynamic-Programming/03-sequence-dp-lis-lcs-edit-distance.md)) |
| right/down moves | grid DP; huge grid + few blocks → binomials ([04](../06-Dynamic-Programming/04-grid-and-path-counting-dp.md)) |
| merge/remove on a line, $n \le 500$ | interval DP ([05](../06-Dynamic-Programming/05-interval-dp.md)) |
| $n \le 20$ | bitmask ([06](../06-Dynamic-Programming/06-bitmask-dp.md)) |
| count $x \le 10^{18}$ with digit property | digit DP ([07](../06-Dynamic-Programming/07-digit-dp.md)) |
| tree, local rule / every root | tree DP / rerooting ([08](../06-Dynamic-Programming/08-tree-dp-and-rerooting.md)) |
| DAG, shortest-path counts, cycles | topo DP / SP-DAG / SCC ([09](../06-Dynamic-Programming/09-dp-on-dags-and-graphs.md)) |
| state + resource, revisits allowed | Dijkstra on (vertex, resource) |
| expected steps / probability | backward E / forward P ([10](../06-Dynamic-Programming/10-probability-and-expected-value-dp.md)) |
| grid side ≤ 10, tilings | broken profile ([11](../06-Dynamic-Programming/11-broken-profile-dp.md)) |

## 4. Recurrences and costs

| Problem | Recurrence | Time |
|---|---|---|
| 0/1 knapsack | $f(w) \gets \max(f(w), f(w-w_i)+v_i)$, $w$ ↓ | $O(nW)$ |
| unbounded | same, $w$ ↑ | $O(nW)$ |
| bounded | bundles $1,2,4,\dots,r$ then 0/1 | $O(W\sum\log c)$ |
| group | $w$ ↓ outer, items of group inner | $O(W\cdot\#)$ |
| value-indexed | $g(v) \gets \min(g(v), g(v-v_i)+w_i)$ | $O(n\sum v)$ |
| coin multisets | coins outer, $s$ ↑ | $O(nx)$ |
| coin sequences | $s$ outer, coins inner | $O(nx)$ |
| subset sum | $R \mid= R \ll w$ | $O(nS/64)$ |
| LIS | `lower_bound` in tails (`upper_bound`: non-decreasing) | $O(n\log n)$ |
| LCS | $=$diag$+1$ or $\max$(up, left) | $O(nm)$ |
| edit distance | $\min(\uparrow+1, \leftarrow+1, \nwarrow+[a\ne b])$ | $O(nm)$ |
| distinct subsequences | $D_i = 2D_{i-1} - D_{p-1}$ | $O(n)$ |
| grid paths | $f = f_{\uparrow} + f_{\leftarrow}$ | $O(nm)$ |
| few obstacles | $g_i = P(s\to o_i) - \sum_{o_j \le o_i} g_jP(o_j\to o_i)$ | $O(k^2)$ |
| two walkers | $(d, r_1, r_2)$, add cell once if $r_1=r_2$ | $O(n^3)$ |
| interval merge | $f(l,r) = S(l,r) + \min_k f(l,k)+f(k+1,r)$ | $O(n^3)$ |
| burst balloons | last $k$ in $(l,r)$: $f(l,k)+f(k,r)+v_lv_kv_r$ | $O(n^3)$ |
| removal game | $g(l,r) = \max(a_l - g(l+1,r), a_r - g(l,r-1))$ | $O(n^2)$ |
| TSP | $f(\text{mask}, v) = \min_u f(\text{mask}\setminus v, u)+d_{uv}$ | $O(2^nn^2)$ |
| partition into blocks | over submasks containing lowest bit | $O(3^n)$ |
| digit DP | (pos, tight, started, extra) | $O(\text{len}\cdot|\text{extra}|\cdot10)$ |
| tree indep. set | $f_1 = w + \sum f_0(c)$, $f_0 = \sum\max$ | $O(n)$ |
| tree knapsack | merge with size bounds | $O(n^2)$ |
| reroot sum of distances | $\text{cost}(c) = \text{cost}(v) + A - 2A_c$ | $O(n)$ |
| self-loop | $E = \frac{c + \sum_{t\ne s}p_tE_t}{1-q}$ | |
| cyclic via start | $E_i = a_i + b_iE_0$, $E_0 = \frac{a_0}{1-b_0}$ | |
| broken profile | at $(i,j)$: covered → clear bit; else H: set bit $i$, V: set bit $i+1$ | $O(nm2^n)$ |

**Counts:** intervals $n^3/6$ triples; subsets $2^n$; (set, submask) $3^n$; $3^{16} = 4.3\cdot10^7$; $2^{20}\cdot20 = 2.1\cdot10^7$.

## 5. Evaluation orders

| Shape | Order |
|---|---|
| prefix | $i$ ↑ |
| interval | len ↑, or $l$ ↓ with $r$ ↑ |
| subsets | mask ↑ |
| tree | reverse BFS order (children first) |
| DAG | Kahn order |
| shortest-path DAG | Dijkstra pop order |
| digit DP memo | key by **remaining length**, memo only non-tight |

## 6. Templates — C++

```cpp
// 0/1 and unbounded knapsack (best value with weight <= W)
long long knap01(const vector<int>& w, const vector<long long>& v, int W) {
    vector<long long> f(W + 1, 0);
    for (size_t i = 0; i < w.size(); i++)
        for (int c = W; c >= w[i]; c--) f[c] = max(f[c], f[c - w[i]] + v[i]);
    return f[W];
}

// LIS length (strict); use upper_bound for non-decreasing
int lis(const vector<long long>& a) {
    vector<long long> T;
    for (long long x : a) {
        auto it = lower_bound(T.begin(), T.end(), x);
        if (it == T.end()) T.push_back(x); else *it = x;
    }
    return T.size();
}

// LCS length with two rows
int lcs(const string& a, const string& b) {
    vector<int> prv(b.size() + 1, 0), cur(b.size() + 1, 0);
    for (size_t i = 1; i <= a.size(); i++) {
        for (size_t j = 1; j <= b.size(); j++)
            cur[j] = a[i - 1] == b[j - 1] ? prv[j - 1] + 1 : max(prv[j], cur[j - 1]);
        swap(prv, cur);
    }
    return prv[b.size()];
}

// Interval DP skeleton: merge adjacent piles
long long mergePiles(const vector<long long>& a) {
    int n = a.size();
    vector<long long> P(n + 1, 0);
    for (int i = 0; i < n; i++) P[i + 1] = P[i] + a[i];
    vector<vector<long long>> f(n, vector<long long>(n, 0));
    for (int len = 2; len <= n; len++)
        for (int l = 0; l + len - 1 < n; l++) {
            int r = l + len - 1;
            f[l][r] = LLONG_MAX;
            for (int k = l; k < r; k++) f[l][r] = min(f[l][r], f[l][k] + f[k + 1][r]);
            f[l][r] += P[r + 1] - P[l];
        }
    return n ? f[0][n - 1] : 0;
}
```

```cpp
// Bitmask: Held-Karp shortest Hamiltonian path from 0 (any end), and submask iteration
long long tspPath(const vector<vector<long long>>& d) {
    int n = d.size(), full = 1 << n;
    const long long INF = LLONG_MAX / 4;
    vector<long long> f((size_t)full * n, INF);
    f[1 * n + 0] = 0;
    for (int mask = 1; mask < full; mask++)
        for (int v = 0; v < n; v++) {
            long long cur = f[(size_t)mask * n + v];
            if (cur >= INF) continue;
            for (int u = 0; u < n; u++)
                if (!(mask >> u & 1)) {
                    long long& t = f[(size_t)(mask | 1 << u) * n + u];
                    t = min(t, cur + d[v][u]);
                }
        }
    long long best = INF;
    for (int v = 0; v < n; v++) best = min(best, f[(size_t)(full - 1) * n + v]);
    return best;
}

int countSubmasks(int m) {                            // visits every non-empty submask
    int c = 0;
    for (int s = m; s > 0; s = (s - 1) & m) c++;
    return c;
}

// Digit DP: count x in [0, N] with digit sum % D == 0 (memo by remaining length)
long long digitSumCount(long long N, int D) {
    if (N < 0) return 0;
    vector<vector<long long>> g(20, vector<long long>(D, 0));   // g[r][s]: r-digit strings with digit sum = s (mod D)
    g[0][0] = 1;
    for (int r = 1; r < 20; r++)
        for (int s = 0; s < D; s++)
            for (int d = 0; d <= 9; d++) g[r][s] += g[r - 1][((s - d) % D + D) % D];
    string t = to_string(N);
    long long total = 0;
    int sum = 0, len = t.size();
    for (int i = 0; i < len; i++) {
        for (int d = 0; d < t[i] - '0'; d++) total += g[len - 1 - i][((-(sum + d)) % D + D) % D];
        sum = (sum + t[i] - '0') % D;
    }
    return total + (sum == 0);
}

// Tree: iterative BFS order + subtree sizes (bottom-up in reverse order)
vector<int> subtreeSizes(const vector<vector<int>>& adj) {
    int n = adj.size();
    vector<int> order{0}, par(n, -1), sz(n, 1);
    for (int i = 0; i < (int)order.size(); i++)
        for (int u : adj[order[i]]) if (u != par[order[i]]) { par[u] = order[i]; order.push_back(u); }
    for (int i = n - 1; i > 0; i--) sz[par[order[i]]] += sz[order[i]];
    return sz;
}
```

## 7. Templates — Java

```java
static long knap01(int[] w, long[] v, int W) {
    long[] f = new long[W + 1];
    for (int i = 0; i < w.length; i++)
        for (int c = W; c >= w[i]; c--) f[c] = Math.max(f[c], f[c - w[i]] + v[i]);
    return f[W];
}

static int lis(long[] a) {                              // strict; use T[mid] > x for non-decreasing
    long[] T = new long[a.length];
    int len = 0;
    for (long x : a) {
        int lo = 0, hi = len;
        while (lo < hi) { int mid = (lo + hi) >>> 1; if (T[mid] >= x) hi = mid; else lo = mid + 1; }
        T[lo] = x;
        if (lo == len) len++;
    }
    return len;
}

static int lcs(String a, String b) {
    int[] prv = new int[b.length() + 1], cur = new int[b.length() + 1];
    for (int i = 1; i <= a.length(); i++) {
        for (int j = 1; j <= b.length(); j++)
            cur[j] = a.charAt(i - 1) == b.charAt(j - 1) ? prv[j - 1] + 1 : Math.max(prv[j], cur[j - 1]);
        int[] t = prv; prv = cur; cur = t;
    }
    return prv[b.length()];
}

static long tspPath(long[][] d) {
    int n = d.length, full = 1 << n;
    final long INF = Long.MAX_VALUE / 4;
    long[] f = new long[full * n];
    Arrays.fill(f, INF);
    f[n] = 0;                                            // mask 1, vertex 0
    for (int mask = 1; mask < full; mask++)
        for (int v = 0; v < n; v++) {
            long cur = f[mask * n + v];
            if (cur >= INF) continue;
            for (int u = 0; u < n; u++)
                if ((mask >> u & 1) == 0) {
                    int idx = (mask | 1 << u) * n + u;
                    f[idx] = Math.min(f[idx], cur + d[v][u]);
                }
        }
    long best = INF;
    for (int v = 0; v < n; v++) best = Math.min(best, f[(full - 1) * n + v]);
    return best;
}

// Tree: BFS order with CSR adjacency (start/adj), parents; process order backwards for bottom-up DPs
static int[] bfsOrder(int n, int[] start, int[] adj, int[] par) {
    int[] order = new int[n];
    Arrays.fill(par, -1);
    int tail = 1;
    for (int i = 0; i < tail; i++) {
        int v = order[i];
        for (int k = start[v]; k < start[v + 1]; k++) if (adj[k] != par[v]) { par[adj[k]] = v; order[tail++] = adj[k]; }
    }
    return order;
}

// Broken profile: domino tilings of n x m (n = rows, small)
static long tilings(int n, int m) {
    final long MOD = 1_000_000_007L;
    long[] f = new long[1 << n], h = new long[1 << n];
    f[0] = 1;
    for (int j = 0; j < m; j++)
        for (int i = 0; i < n; i++) {
            Arrays.fill(h, 0);
            for (int s = 0; s < (1 << n); s++) {
                if (f[s] == 0) continue;
                if ((s >> i & 1) != 0) { h[s ^ (1 << i)] = (h[s ^ (1 << i)] + f[s]) % MOD; continue; }
                if (j + 1 < m) h[s | 1 << i] = (h[s | 1 << i] + f[s]) % MOD;
                if (i + 1 < n && (s >> (i + 1) & 1) == 0) h[s | 1 << (i + 1)] = (h[s | 1 << (i + 1)] + f[s]) % MOD;
            }
            long[] t = f; f = h; h = t;
        }
    return f[0];
}
```

## 8. Edge cases and constants

- Empty object: $f(0)=1$ for counting; $x=0$ in digit DP (decide whether it counts).
- $n = 1$ (no edges in a tree, one balloon, one-digit numbers).
- Blocked start/target cell → 0.
- All values equal (strict vs non-strict LIS).
- Answers up to $10^{18}$: `long long`; mod constants `1'000'000'007`, `998244353`.
- Doubles: print `%.10f`; avoid computing $1-q$ for $q \approx 1$.
- $\binom{2n}{n}$-sized counts overflow 64-bit at $n \approx 33$ — cap or use mod.

## 9. Top 10 mistakes

1. Unreachable states initialised to 0 in a max-DP (should be $-\infty$).
2. Wrong knapsack loop direction (0/1 needs capacity ↓).
3. Coin loops in the wrong nesting (multisets vs sequences).
4. Interval DP looping $l$ ↑ with $r$ inner (reads unfinished $f(l+1,r)$).
5. Counting the same object twice (no canonical decomposition: lowest bit, first obstacle, smallest start).
6. Comparing or zero-testing values reduced mod $p$.
7. Forgetting to clear the rolling target array between layers.
8. Digit DP memo keyed by position (invalid across different $N$) or memoising tight states.
9. Deep recursion on trees/paths (Java StackOverflow; Windows 1 MB stack) — use BFS order or a big-stack thread.
10. `int` overflow in products ($w\cdot s$, $p_lp_kp_r$, `take * w[i]`), and `1 << 31`.

## 10. Last minute before the contest

- [ ] Fast I/O ready in both languages; Java reader is DataInputStream-based, output through `StringBuilder`/`PrintWriter`.
- [ ] Remember: state = what the future needs; say it as a sentence before coding.
- [ ] Multiply states × transitions *before* writing loops.
- [ ] For counting, write the canonical form of an object.
- [ ] Big stack: `new Thread(null, r, "", 1 << 28)` (Java), or iterative order.
- [ ] Brute force + random tests script ready for anything with a non-obvious transition.
- [ ] If a DP is too slow, look up the transition shape in the [optimisations cheat sheet](07-dp-optimizations-cheatsheet.md).
