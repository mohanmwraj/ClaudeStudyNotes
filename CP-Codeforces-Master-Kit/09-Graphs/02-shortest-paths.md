# Shortest Paths: Dijkstra, Bellman–Ford, SPFA, Floyd–Warshall and Friends

> **Band:** 🔵 1400 → 🟠 2400 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [BFS/DFS and 0-1 BFS](01-graph-representation-bfs-dfs.md), [heaps](../08-Data-Structures/10-ordered-sets-pbds-and-heaps.md), [DP state design](../06-Dynamic-Programming/01-dp-first-principles-and-state-design.md)
> **You can say you know this when:** you can prove why Dijkstra is correct and exactly where negative edges break it; choose between BFS / 0-1 BFS / Dijkstra / Bellman–Ford / Floyd–Warshall from the constraints in seconds; build layered and state graphs (k free edges, coupons, parity); count shortest paths; detect *and print* a negative cycle; and turn a system of difference constraints into a shortest-path problem.

## 1. First principles — why this works

**The problem.** Edges carry weights; the length of a walk is the sum of its weights; we want
$\operatorname{dist}(s, v) = \min$ over walks $s \leadsto v$. Enumerating walks is exponential. Two structural facts make it
polynomial:

1. **Optimal substructure.** If there is no negative cycle, some shortest walk is a simple path, and every prefix of a
   shortest path is a shortest path (otherwise swap in the shorter prefix).
2. **Relaxation.** Keep upper bounds $d[v] \ge \operatorname{dist}(v)$ (initially $d[s]=0$, $d[v]=\infty$). Relaxing an edge
   $u\to v$ of weight $w$ sets $d[v] \leftarrow \min(d[v], d[u] + w)$. Every $d[v]$ is always the length of a real walk, so it
   never drops below $\operatorname{dist}(v)$. **Path-relaxation property:** if the edges of a shortest path
   $s = v_0 \to v_1 \to \dots \to v_k$ are relaxed in this order (other relaxations may be interleaved), then afterwards
   $d[v_k] = \operatorname{dist}(v_k)$ (induction on $i$).

Every shortest-path algorithm is just a **schedule of relaxations** that guarantees the path-relaxation property for all
vertices cheaply. BFS ([file 01](01-graph-representation-bfs-dfs.md)) is the schedule for unit weights; the others:

**Dijkstra (non-negative weights).** Schedule: repeatedly take the unsettled vertex with the smallest $d$, declare it
settled, relax its outgoing edges.
*Claim: when $u$ is taken, $d[u] = \operatorname{dist}(u)$.* Suppose not, and look at a shortest path to $u$. Let $y$ be its
first unsettled vertex and $x$ the settled vertex before it. When $x$ was settled (correctly, by induction) the edge $x\to y$
was relaxed, so $d[y] = \operatorname{dist}(y)$. Weights are $\ge 0$, so $\operatorname{dist}(y) \le \operatorname{dist}(u)$.
Hence $d[y] \le \operatorname{dist}(u) < d[u]$, contradicting the choice of $u$. ∎
The single place where non-negativity is used is $\operatorname{dist}(y) \le \operatorname{dist}(u)$: "a prefix is never
longer than the whole path". With a negative edge that fails — e.g. $s\to a$ (2), $s \to b$ (3), $b \to a$ ($-2$): Dijkstra settles
$a$ with $2$ although $\operatorname{dist}(a) = 1$. Adding a constant to every edge does **not** fix it (paths with more edges
are penalized more); potentials do (below).

*Implementation with a binary heap and lazy deletion:* push $(d[v], v)$ on every improvement and, when popping, skip entries
whose key is no longer $d[v]$ ("stale"). At most $m+1$ pushes, each $O(\log m) = O(\log n)$: total
$O((n + m)\log n)$. For dense graphs ($m \approx n^2$) the array version — scan all $n$ vertices for the minimum — is
$O(n^2)$ and faster.

**Dijkstra beyond sums.** The proof only needs (i) extending a path never makes it better and (ii) the order of two path
values is preserved when both are extended by the same edge. So the same algorithm minimizes the maximum edge on a path
(bottleneck/minimax: LC 1631, LC 778), maximizes a product of probabilities $\le 1$ (LC 1514), or handles time-dependent edges
whose arrival time is non-decreasing in departure time (trains leaving every $K$ minutes: AtCoder ABC192 E).

**Bellman–Ford (any weights).** Schedule: relax *every* edge, $n-1$ times. After round $k$, $d[v] \le$ the length of the
shortest walk with at most $k$ edges (induction: the last edge of such a walk is relaxed in round $k$). Without negative
cycles shortest paths are simple, so $n-1$ edges suffice and $n-1$ rounds give exact distances: $O(nm)$.
*Negative cycle test:* if some edge still relaxes in round $n$, a negative cycle is reachable. Conversely, if a negative cycle
is reachable, $d$ can never stabilize (summing $d[v] \le d[u] + w$ around the cycle would give $0 \le w(\text{cycle}) < 0$).

*Printing the cycle.* Keep parent pointers `par[v]` = the vertex that last improved $v$. Two facts:
(a) the invariant $d[v] \ge d[\text{par}[v]] + w(\text{par}[v], v)$ holds forever (equality when set; $d[\text{par}[v]]$ only
decreases later);
(b) every cycle of the parent graph is negative (sum the invariant around it, using that the last edge set on the cycle was a
strict improvement — CLRS Lemma 24.16).
Start all $d$ at 0 (a virtual source joined to every vertex, so *every* negative cycle counts). Suppose $x$ is relaxed in
round $n$. If the parent chain from $x$ were acyclic it would be a simple path $P$ ending at $x$, and (a) would give
$d[x] \ge w(P)$; but after $n-1$ rounds $d[x]$ is already $\le$ the weight of every simple path ending at $x$, and round $n$
lowered it further — contradiction. So the chain from $x$ runs into a cycle within $n$ steps: walk `par` $n$ times from
$x$, then follow `par` until you return. By (b) that cycle is negative.

**SPFA ("queue Bellman–Ford").** Only vertices whose $d$ just changed can cause new relaxations, so keep them in a FIFO queue.
Often much faster on random graphs, but the worst case is still $\Theta(nm)$ and Codeforces problem setters build tests (grids
with small weight perturbations, chains with decoys) that make it time out. Use it only when negative edges are forced and
$nm$ is affordable anyway, or for the first potential in min-cost flow. Negative-cycle detection: count edges on the current
path to each vertex; if a count reaches $n$, there is a negative cycle.

**Floyd–Warshall (all pairs, $n \le 500$).** DP over the set of allowed intermediate vertices: let $d_k[i][j]$ be the
shortest $i \leadsto j$ path whose interior uses only vertices $1..k$. Either the optimal path avoids $k$, or it passes $k$
once (no negative cycles), splitting into two paths with interior in $1..k-1$:
$$d_k[i][j] = \min\big(d_{k-1}[i][j],\; d_{k-1}[i][k] + d_{k-1}[k][j]\big).$$
A single 2-D array suffices: in round $k$ the entries $d[i][k]$ and $d[k][j]$ do not change (they would change only via
$d[k][k] < 0$). $O(n^3)$ time, $O(n^2)$ memory, three nested loops with **$k$ outermost** (putting $k$ inside is the classic
wrong-answer bug). Negative cycle through $i$ $\iff$ $d[i][i] < 0$ at the end.
Variants of the same DP: **transitive closure** (`reach[i] |= reach[k]` whenever `reach[i][k]`, $O(n^3/64)$ with bitsets);
**minimum weight cycle** in an undirected graph — before round $k$, $\min_{i<j<k} d[i][j] + w(j,k) + w(k,i)$ is the lightest
cycle whose largest vertex is $k$ ($i \ne j$ keeps it simple, $d$ over vertices $< k$ keeps $k$ off the path); **adding
vertices in reverse deletion order** (CF 295B); updating all pairs after one new edge in $O(n^2)$ (CF 25C).

**Potentials and Johnson's algorithm (🧊 for contests, essential for min-cost flow).** For any function $h$ on vertices,
reweight $w'(u,v) = w(u,v) + h(u) - h(v)$. Every $s \leadsto t$ path changes by the same constant $h(s) - h(t)$, so
shortest paths are preserved, and $\operatorname{dist}(s,t) = \operatorname{dist}'(s,t) - h(s) + h(t)$. If $h$ is a
**feasible potential** ($w' \ge 0$ on every edge) Dijkstra runs on $w'$. Taking $h = $ Bellman–Ford distances from a virtual
source works because of the triangle inequality $h(v) \le h(u) + w(u,v)$. A feasible potential exists iff there is no negative
cycle. Johnson = one Bellman–Ford + $n$ Dijkstras = $O(nm\log n)$ all-pairs for sparse graphs with negative edges. The same
idea keeps edge costs non-negative in [min-cost flow](../12-Flows-and-Matching/04-min-cost-flow.md), and A* search is Dijkstra
with potential $h = -\text{heuristic}$ (consistency of the heuristic is exactly $w' \ge 0$).

**State graphs (layered graphs).** When the cost of the future depends on a bounded amount of history, make it part of the
vertex. "At most $k$ edges may be used for free / at half price" → vertices $(v, j)$ for $j = 0..k$ coupons used, edges
$(u,j)\to(v,j)$ with weight $w$ and $(u,j)\to(v,j+1)$ with the discounted weight. Run Dijkstra on $n(k+1)$ vertices and
$m(2k+1)$ edges. The same pattern handles "parity of the number of edges", "last edge color", "whether the special edge was used",
"max and min edge already subtracted" (CF 1473E).

**Counting and comparing shortest paths.** With positive weights, Dijkstra settles vertices in an order that is a topological
order of the **shortest-path DAG** (edges with $d[v] = d[u] + w$). So DP along the settling order counts shortest paths,
or finds the fewest/most edges among them: on improvement copy, on a tie combine. Zero-weight edges break the "strictly
earlier" argument: with them, first compute $d$, then do the DP in a topological order of the DAG.

**K shortest walks.** Let every vertex be popped from the heap up to $k$ times; the $i$-th pop of $v$ carries the $i$-th
smallest walk length to $v$ (same exchange argument as Dijkstra, applied to walks). $O(km\log(km))$. (Simple paths instead of
walks need Yen's algorithm; huge $k$ needs Eppstein's — both 🧊.)

**Difference constraints.** A system $x_v - x_u \le w$ is the triangle inequality $d[v] \le d[u] + w$ in disguise: make an edge
$u\to v$ of weight $w$ and a virtual source with 0-edges to all vertices. The system is feasible iff there is no negative
cycle, and $x = d$ is a solution; it is the componentwise **largest** solution with all $x_i \le 0$, because any such solution
satisfies $x_v \le x_u + w$ along every path from the virtual source. Rewrites: $x_v - x_u \ge w \iff x_u - x_v \le -w$;
$x_v = x_u + w$ gives two edges; over integers $x_v - x_u < w \iff x_v - x_u \le w - 1$.

## 2. Formulas, definitions and identities

| Quantity / algorithm | Formula or statement | Cost |
|---|---|---|
| relaxation | $d[v] \leftarrow \min(d[v], d[u]+w(u,v))$ | $O(1)$ |
| triangle inequality (at optimum) | $\operatorname{dist}(v) \le \operatorname{dist}(u) + w(u,v)$ for every edge | — |
| edge on some shortest $s$-path | $\operatorname{dist}(u) + w(u,v) = \operatorname{dist}(v)$ | — |
| edge on some shortest $s$–$t$ path | $\operatorname{dist}_s(u) + w + \operatorname{dist}_t(v) = \operatorname{dist}_s(t)$ ($\operatorname{dist}_t$ on the reversed graph) | 2 runs |
| Dijkstra, binary heap, lazy deletion | needs $w \ge 0$ | $O((n+m)\log n)$ |
| Dijkstra, array (dense) | needs $w \ge 0$ | $O(n^2 + m)$ |
| Dial / bucket queue, $w \in \{0..C\}$ | buckets by distance | $O(m + nC)$ |
| 0-1 BFS | $w \in \{0,1\}$ | $O(n+m)$ |
| Bellman–Ford | round $k$: $d[v] \le$ best walk with $\le k$ edges | $O(nm)$ |
| negative cycle (reachable) | some edge relaxes in round $n$ | $O(nm)$ |
| SPFA | worst case $\Theta(nm)$; neg. cycle iff path edge-count $\ge n$ | $O(nm)$ |
| Floyd–Warshall | $d[i][j] = \min(d[i][j], d[i][k]+d[k][j])$, $k$ outermost | $O(n^3)$ |
| negative cycle (Floyd) | $\exists i: d[i][i] < 0$ | — |
| transitive closure | `reach[i] |= reach[k]` if `reach[i][k]` | $O(n^3/64)$ |
| min cycle, undirected | $\min_{i<j<k} d_{k-1}[i][j] + w(j,k)+w(k,i)$ | $O(n^3)$ |
| reweighting | $w'(u,v) = w + h(u) - h(v)$, $\operatorname{dist} = \operatorname{dist}' - h(s) + h(t)$ | — |
| Johnson | BF from virtual source, then $n$ Dijkstras | $O(nm \log n)$ |
| layered graph, $k$ coupons | $n(k+1)$ vertices, $m(2k+1)$ edges | $O(mk\log(nk))$ |
| k shortest walks | pop each vertex $\le k$ times | $O(km\log(km))$ |
| difference constraints | $x_v - x_u \le w \Rightarrow$ edge $u\to v$ of weight $w$ | BF $O(nm)$ |

**Magnitudes.** $n \cdot \max w$ must fit: $10^5 \cdot 10^9 = 10^{14}$ → `long long`. Use $\text{INF} = 4\cdot10^{18}$ or
`LLONG_MAX/4` so that `INF + w` cannot overflow; in Floyd, skip `d[i][k] == INF` instead of adding two INFs.

**Counting recurrences** (positive weights, $u$ settled, edge $u\to v$, $nd = d[u]+w$):
if $nd < d[v]$: $d[v]=nd$, $\text{cnt}[v]=\text{cnt}[u]$, $\text{mn}[v] = \text{mn}[u]+1$, $\text{mx}[v] = \text{mx}[u]+1$;
if $nd = d[v]$: $\text{cnt}[v] \mathrel{+}= \text{cnt}[u]$, $\text{mn}[v] = \min(\text{mn}[v], \text{mn}[u]+1)$,
$\text{mx}[v] = \max(\text{mx}[v], \text{mx}[u]+1)$.

## 3. Implementation (C++ and Java)

### 3.1 Dijkstra (lazy deletion, with parents)

```cpp
// g[u] = {(v, w)}, w >= 0.  Returns dist (LLONG_MAX = unreachable) and parent for path restoration.
pair<vector<ll>, vector<int>> dijkstra(const vector<vector<pair<int, ll>>>& g, int s) {
    int n = g.size();
    vector<ll> d(n, LLONG_MAX);
    vector<int> par(n, -1);
    priority_queue<pair<ll, int>, vector<pair<ll, int>>, greater<>> pq;
    d[s] = 0;
    pq.push({0, s});
    while (!pq.empty()) {
        auto [du, u] = pq.top(); pq.pop();
        if (du != d[u]) continue;                    // stale entry
        for (auto [v, w] : g[u])
            if (du + w < d[v]) { d[v] = du + w; par[v] = u; pq.push({d[v], v}); }
    }
    return {d, par};
}
```

```java
// Primitive min-heap of (long key, int value): no boxing, no Comparator objects.
static final class LongHeap {
    long[] key; int[] val; int size;
    long topKey; int topVal;
    LongHeap(int cap) { key = new long[Math.max(cap, 1)]; val = new int[Math.max(cap, 1)]; }
    void push(long k, int v) {
        if (size == key.length) { key = Arrays.copyOf(key, 2 * size); val = Arrays.copyOf(val, 2 * size); }
        int i = size++;
        while (i > 0) {
            int p = (i - 1) >> 1;
            if (key[p] <= k) break;
            key[i] = key[p]; val[i] = val[p]; i = p;
        }
        key[i] = k; val[i] = v;
    }
    void pop() {                       // moves the minimum into (topKey, topVal)
        topKey = key[0]; topVal = val[0];
        long k = key[--size]; int v = val[size];
        int i = 0;
        while (true) {
            int c = 2 * i + 1;
            if (c >= size) break;
            if (c + 1 < size && key[c + 1] < key[c]) c++;
            if (key[c] >= k) break;
            key[i] = key[c]; val[i] = val[c]; i = c;
        }
        key[i] = k; val[i] = v;
    }
}

// CSR graph: edges of u are e in [start[u], start[u+1]) with head to[e] and weight wt[e] >= 0.
static long[] dijkstra(int n, int[] start, int[] to, long[] wt, int s, int[] par) {
    long[] d = new long[n];
    Arrays.fill(d, Long.MAX_VALUE);
    Arrays.fill(par, -1);
    LongHeap pq = new LongHeap(to.length + 1);
    d[s] = 0;
    pq.push(0, s);
    while (pq.size > 0) {
        pq.pop();
        long du = pq.topKey; int u = pq.topVal;
        if (du != d[u]) continue;
        for (int e = start[u]; e < start[u + 1]; e++) {
            long nd = du + wt[e];
            if (nd < d[to[e]]) { d[to[e]] = nd; par[to[e]] = u; pq.push(nd, to[e]); }
        }
    }
    return d;
}
```

### 3.2 Bellman–Ford with "−∞" propagation (which vertices are affected by a negative cycle)

```cpp
struct Edge { int u, v; ll w; };
const ll INF = LLONG_MAX / 4, NEG_INF = LLONG_MIN / 4;

// d[v] = INF (unreachable), NEG_INF (a reachable negative cycle can push it down forever), or the exact distance.
vector<ll> bellmanFord(int n, const vector<Edge>& edges, int s) {
    vector<ll> d(n, INF);
    d[s] = 0;
    for (int round = 0; round < n - 1; round++) {
        bool changed = false;
        for (auto& e : edges)
            if (d[e.u] != INF && d[e.u] + e.w < d[e.v]) { d[e.v] = d[e.u] + e.w; changed = true; }
        if (!changed) break;                         // early exit: already optimal
    }
    for (int round = 0; round < n; round++)          // n more rounds spread "minus infinity"
        for (auto& e : edges)
            if (d[e.u] != INF && (d[e.u] == NEG_INF || d[e.u] + e.w < d[e.v])) d[e.v] = NEG_INF;
    return d;
}
```

```java
static final long INF = Long.MAX_VALUE / 4, NEG_INF = Long.MIN_VALUE / 4;

static long[] bellmanFord(int n, int[] eu, int[] ev, long[] ew, int s) {
    long[] d = new long[n];
    Arrays.fill(d, INF);
    d[s] = 0;
    int m = eu.length;
    for (int round = 0; round < n - 1; round++) {
        boolean changed = false;
        for (int i = 0; i < m; i++)
            if (d[eu[i]] != INF && d[eu[i]] + ew[i] < d[ev[i]]) { d[ev[i]] = d[eu[i]] + ew[i]; changed = true; }
        if (!changed) break;
    }
    for (int round = 0; round < n; round++)
        for (int i = 0; i < m; i++)
            if (d[eu[i]] != INF && (d[eu[i]] == NEG_INF || d[eu[i]] + ew[i] < d[ev[i]])) d[ev[i]] = NEG_INF;
    return d;
}
```

### 3.3 SPFA with negative-cycle detection (know it, distrust it)

```cpp
// Returns false if a negative cycle is reachable from s.  Worst case O(nm): hackable.
bool spfa(const vector<vector<pair<int, ll>>>& g, int s, vector<ll>& d) {
    int n = g.size();
    d.assign(n, LLONG_MAX / 4);
    vector<int> len(n, 0);                     // edges on the path that produced d[v]
    vector<char> inq(n, 0);
    queue<int> q;
    d[s] = 0; q.push(s); inq[s] = 1;
    while (!q.empty()) {
        int u = q.front(); q.pop(); inq[u] = 0;
        for (auto [v, w] : g[u])
            if (d[u] + w < d[v]) {
                d[v] = d[u] + w;
                len[v] = len[u] + 1;
                if (len[v] >= n) return false;     // a simple path has at most n-1 edges
                if (!inq[v]) { inq[v] = 1; q.push(v); }
            }
    }
    return true;
}
```

```java
static boolean spfa(int n, int[] start, int[] to, long[] wt, int s, long[] d) {
    Arrays.fill(d, Long.MAX_VALUE / 4);
    int[] len = new int[n];
    boolean[] inq = new boolean[n];
    ArrayDeque<Integer> q = new ArrayDeque<>();
    d[s] = 0; q.add(s); inq[s] = true;
    while (!q.isEmpty()) {
        int u = q.poll(); inq[u] = false;
        for (int e = start[u]; e < start[u + 1]; e++) {
            int v = to[e];
            if (d[u] + wt[e] < d[v]) {
                d[v] = d[u] + wt[e];
                len[v] = len[u] + 1;
                if (len[v] >= n) return false;
                if (!inq[v]) { inq[v] = true; q.add(v); }
            }
        }
    }
    return true;
}
```

### 3.4 Floyd–Warshall with path reconstruction

```cpp
// d: n x n matrix, d[i][i] = 0, INF where no edge (take the min over parallel edges before calling).
// nxt[i][j] = second vertex on a shortest i -> j path (init nxt[i][j] = j for every edge).
void floydWarshall(vector<vector<ll>>& d, vector<vector<int>>& nxt) {
    const ll INF = LLONG_MAX / 4;
    int n = d.size();
    for (int k = 0; k < n; k++)
        for (int i = 0; i < n; i++) {
            if (d[i][k] >= INF) continue;
            for (int j = 0; j < n; j++)
                if (d[k][j] < INF && d[i][k] + d[k][j] < d[i][j]) { d[i][j] = d[i][k] + d[k][j]; nxt[i][j] = nxt[i][k]; }
        }
}

vector<int> floydPath(const vector<vector<int>>& nxt, int i, int j) {   // assumes a path exists, no negative cycle
    vector<int> p = {i};
    while (i != j) { i = nxt[i][j]; p.push_back(i); }
    return p;
}
```

```java
static void floydWarshall(long[][] d, int[][] nxt) {
    final long INF = Long.MAX_VALUE / 4;
    int n = d.length;
    for (int k = 0; k < n; k++) {
        long[] dk = d[k];
        for (int i = 0; i < n; i++) {
            long[] di = d[i];
            long dik = di[k];
            if (dik >= INF) continue;
            int[] ni = nxt[i];
            for (int j = 0; j < n; j++)
                if (dk[j] < INF && dik + dk[j] < di[j]) { di[j] = dik + dk[j]; ni[j] = ni[k]; }
        }
    }
}

static List<Integer> floydPath(int[][] nxt, int i, int j) {
    List<Integer> p = new ArrayList<>();
    p.add(i);
    while (i != j) { i = nxt[i][j]; p.add(i); }
    return p;
}
```

### 3.5 K shortest walks from s to t

```cpp
// The k smallest walk lengths s -> t (vertices may repeat), non-negative weights; fewer if fewer exist.
vector<ll> kShortestWalks(const vector<vector<pair<int, ll>>>& g, int s, int t, int k) {
    vector<int> popped(g.size(), 0);
    vector<ll> res;
    priority_queue<pair<ll, int>, vector<pair<ll, int>>, greater<>> pq;
    pq.push({0, s});
    while (!pq.empty() && (int)res.size() < k) {
        auto [d, u] = pq.top(); pq.pop();
        if (popped[u] == k) continue;                // u already has its k best walks
        popped[u]++;
        if (u == t) res.push_back(d);
        for (auto [v, w] : g[u]) if (popped[v] < k) pq.push({d + w, v});
    }
    return res;
}
```

```java
// Uses LongHeap from 3.1 (repeated here so the block compiles alone).
static final class LongHeap {
    long[] key = new long[16]; int[] val = new int[16]; int size; long topKey; int topVal;
    void push(long k, int v) {
        if (size == key.length) { key = Arrays.copyOf(key, 2 * size); val = Arrays.copyOf(val, 2 * size); }
        int i = size++;
        while (i > 0) { int p = (i - 1) >> 1; if (key[p] <= k) break; key[i] = key[p]; val[i] = val[p]; i = p; }
        key[i] = k; val[i] = v;
    }
    void pop() {
        topKey = key[0]; topVal = val[0];
        long k = key[--size]; int v = val[size]; int i = 0;
        while (true) {
            int c = 2 * i + 1;
            if (c >= size) break;
            if (c + 1 < size && key[c + 1] < key[c]) c++;
            if (key[c] >= k) break;
            key[i] = key[c]; val[i] = val[c]; i = c;
        }
        key[i] = k; val[i] = v;
    }
}

static long[] kShortestWalks(int n, int[] start, int[] to, long[] wt, int s, int t, int k) {
    int[] popped = new int[n];
    long[] res = new long[k];
    int cnt = 0;
    LongHeap pq = new LongHeap();
    pq.push(0, s);
    while (pq.size > 0 && cnt < k) {
        pq.pop();
        long d = pq.topKey; int u = pq.topVal;
        if (popped[u] == k) continue;
        popped[u]++;
        if (u == t) res[cnt++] = d;
        for (int e = start[u]; e < start[u + 1]; e++) if (popped[to[e]] < k) pq.push(d + wt[e], to[e]);
    }
    return Arrays.copyOf(res, cnt);
}
```

**Johnson (🧊):** run 3.2 from a virtual vertex joined to everything with weight 0 to get $h$ (abort if a negative cycle
exists), set `w' = w + h[u] - h[v]`, run 3.1 from every source, and add back `- h[s] + h[t]`.

## 4. Recognising the pattern

| Signal | Algorithm |
|---|---|
| unit weights / "minimum number of moves" | BFS ([file 01](01-graph-representation-bfs-dfs.md)) |
| weights 0/1, "free moves", "pay 1 to turn/break" | 0-1 BFS |
| non-negative weights, $n,m \le 2\cdot10^5$ | Dijkstra with a heap |
| $n \le 5000$ and the graph is complete / dense | $O(n^2)$ Dijkstra |
| negative weights, single source, $nm \le 10^8$ | Bellman–Ford (SPFA only if you must) |
| "can the score grow forever", "arbitrage", "infinite profit" | negative (or positive, after negating) cycle on a path that reaches the target |
| $n \le 500$, many pair queries, "for every pair" | Floyd–Warshall |
| vertices deleted / added one by one, all-pairs sum | Floyd in reverse order of deletion |
| "at most $k$ edges free/halved", "one coupon", "parity", "used the special edge?" | layered/state graph + Dijkstra |
| "number of shortest routes", "min/max edges among cheapest routes" | DP on the shortest-path DAG in settling order |
| "second shortest", "$k$ cheapest routes" | pop each vertex up to $k$ times |
| inequalities $x_j - x_i \le c$, "assign values so that ..." | difference constraints → Bellman–Ford from a virtual source |
| "nearest of many sources" for every vertex | multi-source Dijkstra (all sources at distance 0, or at their own start cost) |
| edges from one vertex to a whole *range* of vertices | segment-tree-shaped graph ([special graphs](10-functional-graphs-and-special-graphs.md)) |
| minimize the *maximum* edge on a path | minimax Dijkstra, or MST/DSU ([MST](03-minimum-spanning-trees.md)) |
| $m - n$ tiny (graph = tree + few edges) | tree distances + Dijkstra from endpoints of the extra edges (CF 1051F) |

## 5. Worked examples (graded)

### Example 1 — Shortest Routes I  ·  ★ ≈1400

- **Source:** [CSES 1671 · Shortest Routes I](https://cses.fi/problemset/task/1671)
- **Difficulty:** ≈1400 (est.)
- **Problem:** $n \le 10^5$ cities, $m \le 2\cdot10^5$ one-way flights $a \to b$ of price $c \le 10^9$ (parallel flights
  allowed). Every city is reachable from city 1; print the cheapest price from city 1 to every city.
- **Thinking from first principles:** single source, non-negative weights, sparse → Dijkstra with a heap. The only traps are
  overflow ($10^5\cdot10^9$ needs 64 bits) and speed: stale heap entries must be skipped, otherwise a vertex with many incoming
  improvements rescans its edges many times.

<details><summary>Solution</summary>

Lazy-deletion Dijkstra (§3.1). $O((n+m)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<vector<pair<int, int>>> g(n + 1);
    for (int i = 0; i < m; i++) {
        int a, b, c;
        cin >> a >> b >> c;
        g[a].push_back({b, c});
    }
    vector<ll> d(n + 1, LLONG_MAX);
    priority_queue<pair<ll, int>, vector<pair<ll, int>>, greater<>> pq;
    d[1] = 0;
    pq.push({0, 1});
    while (!pq.empty()) {
        auto [du, u] = pq.top(); pq.pop();
        if (du != d[u]) continue;
        for (auto [v, w] : g[u])
            if (du + w < d[v]) { d[v] = du + w; pq.push({d[v], v}); }
    }
    for (int v = 1; v <= n; v++) cout << d[v] << " \n"[v == n];
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
    static int nextInt() throws IOException {
        int b = in.read();
        while (b < '0' || b > '9') b = in.read();
        int r = 0;
        while (b >= '0' && b <= '9') { r = r * 10 + (b - '0'); b = in.read(); }
        return r;
    }

    static final class LongHeap {
        long[] key; int[] val; int size; long topKey; int topVal;
        LongHeap(int cap) { key = new long[cap]; val = new int[cap]; }
        void push(long k, int v) {
            if (size == key.length) { key = Arrays.copyOf(key, 2 * size); val = Arrays.copyOf(val, 2 * size); }
            int i = size++;
            while (i > 0) { int p = (i - 1) >> 1; if (key[p] <= k) break; key[i] = key[p]; val[i] = val[p]; i = p; }
            key[i] = k; val[i] = v;
        }
        void pop() {
            topKey = key[0]; topVal = val[0];
            long k = key[--size]; int v = val[size]; int i = 0;
            while (true) {
                int c = 2 * i + 1;
                if (c >= size) break;
                if (c + 1 < size && key[c + 1] < key[c]) c++;
                if (key[c] >= k) break;
                key[i] = key[c]; val[i] = val[c]; i = c;
            }
            key[i] = k; val[i] = v;
        }
    }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt();
        int[] ea = new int[m], eb = new int[m], ec = new int[m], start = new int[n + 2];
        for (int i = 0; i < m; i++) { ea[i] = nextInt(); eb[i] = nextInt(); ec[i] = nextInt(); start[ea[i] + 1]++; }
        for (int i = 0; i <= n; i++) start[i + 1] += start[i];
        int[] to = new int[m], pos = Arrays.copyOf(start, n + 1);
        long[] wt = new long[m];
        for (int i = 0; i < m; i++) { int p = pos[ea[i]]++; to[p] = eb[i]; wt[p] = ec[i]; }
        long[] d = new long[n + 1];
        Arrays.fill(d, Long.MAX_VALUE);
        LongHeap pq = new LongHeap(m + 1);
        d[1] = 0;
        pq.push(0, 1);
        while (pq.size > 0) {
            pq.pop();
            long du = pq.topKey; int u = pq.topVal;
            if (du != d[u]) continue;
            for (int e = start[u]; e < start[u + 1]; e++) {
                long nd = du + wt[e];
                if (nd < d[to[e]]) { d[to[e]] = nd; pq.push(nd, to[e]); }
            }
        }
        StringBuilder sb = new StringBuilder();
        for (int v = 1; v <= n; v++) sb.append(d[v]).append(v == n ? '\n' : ' ');
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
4 5
1 2 4
1 3 1
3 2 2
2 4 1
3 4 5
out:
0 3 1 4
-->
<!-- test
in:
2 3
1 2 1000000000
1 2 7
2 1 1
out:
0 7
-->
<!-- test
in:
3 2
1 2 1000000000
2 3 1000000000
out:
0 1000000000 2000000000
-->

### Example 2 — Shortest Routes II (all pairs)  ·  ★ ≈1500

- **Source:** [CSES 1672 · Shortest Routes II](https://cses.fi/problemset/task/1672)
- **Difficulty:** ≈1500 (est.)
- **Problem:** $n \le 500$ cities, $m \le n^2$ two-way roads with lengths $\le 10^9$ (parallel roads possible),
  $q \le 10^5$ queries "shortest distance between $a$ and $b$", $-1$ if none.
- **Thinking from first principles:** $10^5$ queries rule out per-query searches unless each is cheap; $n = 500$ makes
  $n^3 = 1.25\cdot10^8$ simple operations affordable, after which each query is $O(1)$. Running Dijkstra from every vertex
  would also work ($n \cdot m\log n$ ≈ $500\cdot 2.5\cdot10^5\cdot 18$ — slower here, since $m$ can be $n^2$). Parallel roads:
  keep the minimum.

<details><summary>Solution</summary>

Floyd–Warshall with $k$ outermost, skipping `INF` to avoid overflow. $O(n^3 + q)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m, q;
    cin >> n >> m >> q;
    const ll INF = LLONG_MAX / 4;
    vector<vector<ll>> d(n + 1, vector<ll>(n + 1, INF));
    for (int i = 1; i <= n; i++) d[i][i] = 0;
    for (int i = 0; i < m; i++) {
        int a, b; ll c;
        cin >> a >> b >> c;
        d[a][b] = min(d[a][b], c);
        d[b][a] = min(d[b][a], c);
    }
    for (int k = 1; k <= n; k++)
        for (int i = 1; i <= n; i++) {
            if (d[i][k] == INF) continue;
            for (int j = 1; j <= n; j++)
                if (d[i][k] + d[k][j] < d[i][j]) d[i][j] = d[i][k] + d[k][j];   // d[k][j] <= INF: no overflow
        }
    while (q--) {
        int a, b;
        cin >> a >> b;
        cout << (d[a][b] == INF ? -1 : d[a][b]) << "\n";
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
    static long nextLong() throws IOException {
        int b = in.read();
        while (b < '0' || b > '9') b = in.read();
        long r = 0;
        while (b >= '0' && b <= '9') { r = r * 10 + (b - '0'); b = in.read(); }
        return r;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nextLong(), m = (int) nextLong(), q = (int) nextLong();
        final long INF = Long.MAX_VALUE / 4;
        long[][] d = new long[n + 1][n + 1];
        for (long[] row : d) Arrays.fill(row, INF);
        for (int i = 1; i <= n; i++) d[i][i] = 0;
        for (int i = 0; i < m; i++) {
            int a = (int) nextLong(), b = (int) nextLong();
            long c = nextLong();
            if (c < d[a][b]) { d[a][b] = c; d[b][a] = c; }
        }
        for (int k = 1; k <= n; k++) {
            long[] dk = d[k];
            for (int i = 1; i <= n; i++) {
                long[] di = d[i];
                long dik = di[k];
                if (dik == INF) continue;
                for (int j = 1; j <= n; j++)
                    if (dik + dk[j] < di[j]) di[j] = dik + dk[j];
            }
        }
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            int a = (int) nextLong(), b = (int) nextLong();
            sb.append(d[a][b] == INF ? -1 : d[a][b]).append('\n');
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
4 3 4
1 2 5
2 3 3
1 2 2
1 3
3 1
1 4
2 2
out:
5
5
-1
0
-->
<!-- test
in:
3 3 2
1 2 1000000000
2 3 1000000000
1 3 1999999999
1 3
2 1
out:
1999999999
1000000000
-->

### Example 3 — Flight Discount (layered graph)  ·  ★ ≈1600

- **Source:** [CSES 1195 · Flight Discount](https://cses.fi/problemset/task/1195)
- **Difficulty:** ≈1600 (est.)
- **Problem:** Directed flights ($n \le 10^5$, $m \le 2\cdot10^5$, prices $\le 10^9$). You have one coupon that halves the
  price of a single flight (rounded down). Find the cheapest trip from city 1 to city $n$ (it exists).
- **Thinking from first principles:** dead end 1 — "take the shortest path and halve its most expensive edge": the best
  discounted trip may use a path that is not shortest (third test below). Dead end 2 — "for each edge, try halving it and rerun
  Dijkstra": $m$ runs. What does the future depend on? Only whether the coupon is still available. So the state is
  $(v, \text{used})$: two copies of the graph, and each edge $u\to v$ also goes from copy 0 to copy 1 at half price. One Dijkstra
  on $2n$ vertices. (Equivalent closed form: $\min_{u\to v} d_1(u) + \lfloor c/2\rfloor + d_n'(v)$ with $d_n'$ computed on the
  reversed graph — a good cross-check.)

<details><summary>Solution</summary>

Vertex id `2*v + used`. From `(u,0)`: to `(v,0)` at `c`, to `(v,1)` at `c/2`; from `(u,1)`: to `(v,1)` at `c`.
Answer `min(d[(n,0)], d[(n,1)])`. $O((n+m)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<vector<pair<int, int>>> g(n + 1);
    for (int i = 0; i < m; i++) {
        int a, b, c;
        cin >> a >> b >> c;
        g[a].push_back({b, c});
    }
    vector<ll> d(2 * (n + 1), LLONG_MAX);
    priority_queue<pair<ll, int>, vector<pair<ll, int>>, greater<>> pq;
    auto relax = [&](int s, ll nd) { if (nd < d[s]) { d[s] = nd; pq.push({nd, s}); } };
    relax(2 * 1 + 0, 0);
    while (!pq.empty()) {
        auto [du, s] = pq.top(); pq.pop();
        if (du != d[s]) continue;
        int u = s / 2, used = s % 2;
        for (auto [v, c] : g[u]) {
            relax(2 * v + used, du + c);
            if (!used) relax(2 * v + 1, du + c / 2);   // spend the coupon on this flight
        }
    }
    cout << min(d[2 * n], d[2 * n + 1]) << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
    static int nextInt() throws IOException {
        int b = in.read();
        while (b < '0' || b > '9') b = in.read();
        int r = 0;
        while (b >= '0' && b <= '9') { r = r * 10 + (b - '0'); b = in.read(); }
        return r;
    }

    static final class LongHeap {
        long[] key; int[] val; int size; long topKey; int topVal;
        LongHeap(int cap) { key = new long[cap]; val = new int[cap]; }
        void push(long k, int v) {
            if (size == key.length) { key = Arrays.copyOf(key, 2 * size); val = Arrays.copyOf(val, 2 * size); }
            int i = size++;
            while (i > 0) { int p = (i - 1) >> 1; if (key[p] <= k) break; key[i] = key[p]; val[i] = val[p]; i = p; }
            key[i] = k; val[i] = v;
        }
        void pop() {
            topKey = key[0]; topVal = val[0];
            long k = key[--size]; int v = val[size]; int i = 0;
            while (true) {
                int c = 2 * i + 1;
                if (c >= size) break;
                if (c + 1 < size && key[c + 1] < key[c]) c++;
                if (key[c] >= k) break;
                key[i] = key[c]; val[i] = val[c]; i = c;
            }
            key[i] = k; val[i] = v;
        }
    }

    static long[] d;
    static LongHeap pq;
    static void relax(int s, long nd) { if (nd < d[s]) { d[s] = nd; pq.push(nd, s); } }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt();
        int[] ea = new int[m], eb = new int[m], ec = new int[m], start = new int[n + 2];
        for (int i = 0; i < m; i++) { ea[i] = nextInt(); eb[i] = nextInt(); ec[i] = nextInt(); start[ea[i] + 1]++; }
        for (int i = 0; i <= n; i++) start[i + 1] += start[i];
        int[] to = new int[m], wt = new int[m], pos = Arrays.copyOf(start, n + 1);
        for (int i = 0; i < m; i++) { int p = pos[ea[i]]++; to[p] = eb[i]; wt[p] = ec[i]; }
        d = new long[2 * (n + 1)];
        Arrays.fill(d, Long.MAX_VALUE);
        pq = new LongHeap(2 * m + 2);
        relax(2, 0);
        while (pq.size > 0) {
            pq.pop();
            long du = pq.topKey; int s = pq.topVal;
            if (du != d[s]) continue;
            int u = s >> 1, used = s & 1;
            for (int e = start[u]; e < start[u + 1]; e++) {
                relax(2 * to[e] + used, du + wt[e]);
                if (used == 0) relax(2 * to[e] + 1, du + wt[e] / 2);
            }
        }
        System.out.println(Math.min(d[2 * n], d[2 * n + 1]));
    }
}
```

</details>

<!-- test
in:
3 4
1 2 3
2 3 1
1 3 7
2 1 5
out:
2
-->
<!-- test
in:
2 1
1 2 1
out:
0
-->
<!-- test
in:
4 4
1 2 6
2 4 6
1 3 1
3 4 14
out:
8
-->

### Example 4 — Investigation (counting shortest paths)  ·  ★ ≈1700

- **Source:** [CSES 1202 · Investigation](https://cses.fi/problemset/task/1202)
- **Difficulty:** ≈1700 (est.)
- **Problem:** Directed flights with positive prices ($n \le 10^5$, $m \le 2\cdot10^5$). Print four numbers for routes
  $1 \to n$: the minimum price, the number of minimum-price routes modulo $10^9+7$, and the minimum and maximum number of
  flights on a minimum-price route.
- **Thinking from first principles:** all four quantities live on the shortest-path DAG (edges with $d[v] = d[u]+w$). A DP
  needs a topological order of that DAG; with **positive** weights every DAG predecessor of $v$ has a strictly smaller $d$,
  so Dijkstra's settling order is such an order and the DP can be fused into the relaxation: on improvement, copy; on a tie,
  combine. (With zero-weight edges this fusion is wrong — compute $d$ first, then do the DP in a topological order.)

<details><summary>Solution</summary>

Dijkstra with `cnt`, `mn`, `mx` updated per the recurrences in §2. When `u` is popped its values are final, because all its
DAG predecessors were popped earlier and already relaxed into it. $O((n+m)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    const ll MOD = 1'000'000'007;
    int n, m;
    cin >> n >> m;
    vector<vector<pair<int, int>>> g(n + 1);
    for (int i = 0; i < m; i++) {
        int a, b, c;
        cin >> a >> b >> c;
        g[a].push_back({b, c});
    }
    vector<ll> d(n + 1, LLONG_MAX), cnt(n + 1, 0);
    vector<int> mn(n + 1, 0), mx(n + 1, 0);
    priority_queue<pair<ll, int>, vector<pair<ll, int>>, greater<>> pq;
    d[1] = 0; cnt[1] = 1;
    pq.push({0, 1});
    while (!pq.empty()) {
        auto [du, u] = pq.top(); pq.pop();
        if (du != d[u]) continue;
        for (auto [v, w] : g[u]) {
            ll nd = du + w;
            if (nd < d[v]) {
                d[v] = nd; cnt[v] = cnt[u]; mn[v] = mn[u] + 1; mx[v] = mx[u] + 1;
                pq.push({nd, v});
            } else if (nd == d[v]) {
                cnt[v] = (cnt[v] + cnt[u]) % MOD;
                mn[v] = min(mn[v], mn[u] + 1);
                mx[v] = max(mx[v], mx[u] + 1);
            }
        }
    }
    cout << d[n] << ' ' << cnt[n] << ' ' << mn[n] << ' ' << mx[n] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
    static int nextInt() throws IOException {
        int b = in.read();
        while (b < '0' || b > '9') b = in.read();
        int r = 0;
        while (b >= '0' && b <= '9') { r = r * 10 + (b - '0'); b = in.read(); }
        return r;
    }

    static final class LongHeap {
        long[] key; int[] val; int size; long topKey; int topVal;
        LongHeap(int cap) { key = new long[cap]; val = new int[cap]; }
        void push(long k, int v) {
            if (size == key.length) { key = Arrays.copyOf(key, 2 * size); val = Arrays.copyOf(val, 2 * size); }
            int i = size++;
            while (i > 0) { int p = (i - 1) >> 1; if (key[p] <= k) break; key[i] = key[p]; val[i] = val[p]; i = p; }
            key[i] = k; val[i] = v;
        }
        void pop() {
            topKey = key[0]; topVal = val[0];
            long k = key[--size]; int v = val[size]; int i = 0;
            while (true) {
                int c = 2 * i + 1;
                if (c >= size) break;
                if (c + 1 < size && key[c + 1] < key[c]) c++;
                if (key[c] >= k) break;
                key[i] = key[c]; val[i] = val[c]; i = c;
            }
            key[i] = k; val[i] = v;
        }
    }

    public static void main(String[] args) throws IOException {
        final long MOD = 1_000_000_007L;
        int n = nextInt(), m = nextInt();
        int[] ea = new int[m], eb = new int[m], ec = new int[m], start = new int[n + 2];
        for (int i = 0; i < m; i++) { ea[i] = nextInt(); eb[i] = nextInt(); ec[i] = nextInt(); start[ea[i] + 1]++; }
        for (int i = 0; i <= n; i++) start[i + 1] += start[i];
        int[] to = new int[m], wt = new int[m], pos = Arrays.copyOf(start, n + 1);
        for (int i = 0; i < m; i++) { int p = pos[ea[i]]++; to[p] = eb[i]; wt[p] = ec[i]; }
        long[] d = new long[n + 1], cnt = new long[n + 1];
        int[] mn = new int[n + 1], mx = new int[n + 1];
        Arrays.fill(d, Long.MAX_VALUE);
        LongHeap pq = new LongHeap(m + 1);
        d[1] = 0; cnt[1] = 1;
        pq.push(0, 1);
        while (pq.size > 0) {
            pq.pop();
            long du = pq.topKey; int u = pq.topVal;
            if (du != d[u]) continue;
            for (int e = start[u]; e < start[u + 1]; e++) {
                int v = to[e];
                long nd = du + wt[e];
                if (nd < d[v]) {
                    d[v] = nd; cnt[v] = cnt[u]; mn[v] = mn[u] + 1; mx[v] = mx[u] + 1;
                    pq.push(nd, v);
                } else if (nd == d[v]) {
                    cnt[v] = (cnt[v] + cnt[u]) % MOD;
                    mn[v] = Math.min(mn[v], mn[u] + 1);
                    mx[v] = Math.max(mx[v], mx[u] + 1);
                }
            }
        }
        System.out.println(d[n] + " " + cnt[n] + " " + mn[n] + " " + mx[n]);
    }
}
```

</details>

<!-- test
in:
4 5
1 2 1
2 4 1
1 3 1
3 4 1
1 4 2
out:
2 3 1 2
-->
<!-- test
in:
2 1
1 2 5
out:
5 1 1 1
-->
<!-- test
in:
5 6
1 2 2
1 3 1
3 2 1
2 5 3
1 4 4
4 5 1
out:
5 3 2 3
-->

### Example 5 — Cycle Finding (print a negative cycle)  ·  ★ ≈1800

- **Source:** [CSES 1197 · Cycle Finding](https://cses.fi/problemset/task/1197)
- **Difficulty:** ≈1800 (est.)
- **Problem:** A directed graph ($n \le 2500$, $m \le 5000$, weights $|c| \le 10^9$). Decide whether it contains a negative
  cycle anywhere; if so print `YES` and the cycle's vertices in order (first vertex repeated at the end), else `NO`. Any
  negative cycle is accepted; we rotate the one we find to start at its smallest vertex.
- **Thinking from first principles:** "anywhere", not "reachable from 1": start every $d$ at 0 (virtual source). Run $n$
  rounds of Bellman–Ford; a relaxation in round $n$ proves a negative cycle exists (§1). The relaxed vertex $x$ may hang
  *below* the cycle in the parent graph, so first walk `par` $n$ times — that is guaranteed to land on the cycle — then collect
  the cycle by following `par` until the start repeats, and reverse it (parents point backwards).

<details><summary>Solution</summary>

$O(nm) = 1.25\cdot10^7$ relaxations. Values stay within about $n^2\cdot10^9 \approx 6\cdot10^{15}$, safe in 64 bits.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<int> eu(m), ev(m);
    vector<ll> ew(m);
    for (int i = 0; i < m; i++) cin >> eu[i] >> ev[i] >> ew[i];
    vector<ll> d(n + 1, 0);                  // virtual source: every vertex starts at 0
    vector<int> par(n + 1, -1);
    int x = -1;
    for (int round = 0; round < n; round++) {
        x = -1;
        for (int i = 0; i < m; i++)
            if (d[eu[i]] + ew[i] < d[ev[i]]) { d[ev[i]] = d[eu[i]] + ew[i]; par[ev[i]] = eu[i]; x = ev[i]; }
        if (x == -1) break;                  // stable: no negative cycle
    }
    if (x == -1) { cout << "NO\n"; return 0; }
    for (int i = 0; i < n; i++) x = par[x];  // now x lies on the cycle
    vector<int> cyc;
    for (int v = x;; v = par[v]) {
        cyc.push_back(v);
        if (v == x && cyc.size() > 1) break;
    }
    cyc.pop_back();                          // drop the repeated x
    reverse(cyc.begin(), cyc.end());         // parent pointers go backwards
    rotate(cyc.begin(), min_element(cyc.begin(), cyc.end()), cyc.end());
    cout << "YES\n";
    for (int v : cyc) cout << v << ' ';
    cout << cyc[0] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
    static long nextLong() throws IOException {
        int b = in.read();
        while (b != '-' && (b < '0' || b > '9')) b = in.read();
        boolean neg = b == '-';
        if (neg) b = in.read();
        long r = 0;
        while (b >= '0' && b <= '9') { r = r * 10 + (b - '0'); b = in.read(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nextLong(), m = (int) nextLong();
        int[] eu = new int[m], ev = new int[m];
        long[] ew = new long[m];
        for (int i = 0; i < m; i++) { eu[i] = (int) nextLong(); ev[i] = (int) nextLong(); ew[i] = nextLong(); }
        long[] d = new long[n + 1];
        int[] par = new int[n + 1];
        Arrays.fill(par, -1);
        int x = -1;
        for (int round = 0; round < n; round++) {
            x = -1;
            for (int i = 0; i < m; i++)
                if (d[eu[i]] + ew[i] < d[ev[i]]) { d[ev[i]] = d[eu[i]] + ew[i]; par[ev[i]] = eu[i]; x = ev[i]; }
            if (x == -1) break;
        }
        if (x == -1) { System.out.println("NO"); return; }
        for (int i = 0; i < n; i++) x = par[x];
        ArrayList<Integer> cyc = new ArrayList<>();
        int v = x;
        do { cyc.add(v); v = par[v]; } while (v != x);
        Collections.reverse(cyc);
        int mi = 0;
        for (int i = 1; i < cyc.size(); i++) if (cyc.get(i) < cyc.get(mi)) mi = i;
        Collections.rotate(cyc, -mi);
        StringBuilder sb = new StringBuilder("YES\n");
        for (int y : cyc) sb.append(y).append(' ');
        sb.append(cyc.get(0)).append('\n');
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
5 6
1 2 4
2 3 -2
3 4 -3
4 2 4
4 5 1
5 1 2
out:
YES
2 3 4 2
-->
<!-- test
in:
3 3
1 2 -5
2 3 2
3 1 3
out:
NO
-->
<!-- test
in:
2 2
1 2 -1
2 1 0
out:
YES
1 2 1
-->
<!-- test
in:
1 0
out:
NO
-->

### Example 6 — Difference constraints  ·  ★ ≈2000

- **Source:** Original problem (the modeling step behind [CF 241E · Flights](https://codeforces.com/problemset/problem/241/E) — 2600 and [CF 1450E · Capitalism](https://codeforces.com/problemset/problem/1450/E) — 2700).
- **Difficulty:** ≈2000 (est.)
- **Problem:** Unknown integers $x_1..x_n$ ($n \le 2000$) and $m \le 5000$ constraints "$u\ v\ w$" meaning
  $x_v - x_u \le w$ ($|w| \le 10^9$). Print `NO` if no integer solution exists; otherwise print the componentwise largest
  solution with every $x_i \le 0$.
- **Thinking from first principles:** the constraint $x_v \le x_u + w$ is exactly the triangle inequality of shortest paths
  along an edge $u \to v$ of weight $w$, and "$x_i \le 0$" is an edge of weight 0 from a virtual source $S$ with $x_S = 0$.
  Any solution satisfies $x_v \le x_S + w(P)$ along every path $P$ from $S$, so $x_v \le \operatorname{dist}(S, v)$; and the
  distances themselves satisfy all constraints. Hence: feasible iff no negative cycle (a negative cycle sums the inequalities
  to $0 \le w(C) < 0$), and the answer is $x = \operatorname{dist}(S,\cdot)$, integral because all weights are integers.

<details><summary>Solution</summary>

Bellman–Ford with all $d = 0$ (the virtual source's edges are pre-relaxed), up to $n$ rounds; a change in round $n$ means `NO`.
$O(nm)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<int> eu(m), ev(m);
    vector<ll> ew(m);
    for (int i = 0; i < m; i++) cin >> eu[i] >> ev[i] >> ew[i];   // x[v] - x[u] <= w  ->  edge u -> v
    vector<ll> x(n + 1, 0);
    bool changed = true;
    for (int round = 0; round < n && changed; round++) {
        changed = false;
        for (int i = 0; i < m; i++)
            if (x[eu[i]] + ew[i] < x[ev[i]]) { x[ev[i]] = x[eu[i]] + ew[i]; changed = true; }
    }
    if (changed) { cout << "NO\n"; return 0; }     // still relaxing after n rounds: negative cycle
    for (int i = 1; i <= n; i++) cout << x[i] << " \n"[i == n];
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
    static long nextLong() throws IOException {
        int b = in.read();
        while (b != '-' && (b < '0' || b > '9')) b = in.read();
        boolean neg = b == '-';
        if (neg) b = in.read();
        long r = 0;
        while (b >= '0' && b <= '9') { r = r * 10 + (b - '0'); b = in.read(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nextLong(), m = (int) nextLong();
        int[] eu = new int[m], ev = new int[m];
        long[] ew = new long[m];
        for (int i = 0; i < m; i++) { eu[i] = (int) nextLong(); ev[i] = (int) nextLong(); ew[i] = nextLong(); }
        long[] x = new long[n + 1];
        boolean changed = true;
        for (int round = 0; round < n && changed; round++) {
            changed = false;
            for (int i = 0; i < m; i++)
                if (x[eu[i]] + ew[i] < x[ev[i]]) { x[ev[i]] = x[eu[i]] + ew[i]; changed = true; }
        }
        if (changed) { System.out.println("NO"); return; }
        StringBuilder sb = new StringBuilder();
        for (int i = 1; i <= n; i++) sb.append(x[i]).append(i == n ? '\n' : ' ');
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
3 3
1 2 3
2 3 -2
1 3 -4
out:
0 0 -4
-->
<!-- test
in:
2 2
1 2 -1
2 1 0
out:
NO
-->
<!-- test
in:
1 0
out:
0
-->
<!-- test
in:
4 3
2 1 -1
3 2 -1
4 3 -1
out:
-3 -2 -1 0
-->

## 6. Tricks, pitfalls and things to remember

1. **Never run Dijkstra with negative edges**, not even "just one". It may return wrong answers silently, or (with
   re-insertion allowed) take exponential time on adversarial inputs.
2. **Skip stale heap entries** (`if (du != d[u]) continue;`). Without it the code is still correct but rescans adjacency
   lists — $O(m^2)$ in the worst case (a vertex improved $\deg$ times).
3. **`priority_queue` is a max-heap** in C++: use `greater<>` or push negated distances. In Java, a
   `PriorityQueue<long[]>` with a comparator works but allocates per push; the primitive heap in §3.1 is 2–3× faster.
4. **INF arithmetic.** `INF + w` overflows with `LLONG_MAX`; use `LLONG_MAX/4` or test `d[u] == INF` before adding. In
   Floyd skip `d[i][k] == INF`.
5. **Floyd loop order is `k, i, j`.** Any other outer loop is wrong. Initialize `d[i][i] = 0` and take the minimum over parallel
   edges; with negative self-loops `d[i][i]` starts negative.
6. **Bellman–Ford reachability.** "Is the answer unbounded?" asks whether a negative cycle lies on some path from $s$ *to
   $t$* — a negative cycle elsewhere does not matter (CSES High Score, ABC137 E). Propagate $-\infty$ (§3.2) or intersect
   "reachable from $s$" with "reaches $t$".
7. **Counting paths with zero-weight edges**: settle order is not a valid DP order among equal distances. Compute $d$, then DP
   in a topological order of the tight-edge DAG (or forbid zero edges by the statement). Also take counts **mod** $p$ only
   for the count, never for distances.
8. **Undirected = two directed edges.** Forgetting the reverse edge, or allocating `m` instead of `2m` slots, is the most common
   bug in CSR code.
9. **Layered graphs grow memory** by the number of layers; with $k$ up to 20 and $n=10^5$ you have $2\cdot10^6$ vertices — use
   `int` ids `v*(k+1)+j` and flat arrays.
10. **SPFA is hackable.** On Codeforces, prefer Dijkstra (with potentials if negative edges come from a structure you
    control) or Bellman–Ford with early exit.
11. **Path restoration** needs parents updated on every strict improvement; for "lexicographically smallest shortest path",
    break ties during a BFS/Dijkstra by layers, not by comparing whole paths.
12. **Java recursion is never needed here**, but Java heap memory is: `long[n][n]` with $n=2000$ is 32 MB, fine;
    `ArrayList<long[]>` per vertex is not.

## 7. Going further (toward 2400–2600+)

- **Graph-construction tricks.** Edges "from $v$ to every vertex in $[l, r]$" (CF 786B Legacy) become $O(\log n)$ edges into a
  segment tree of auxiliary vertices; "from $[l,r]$ to $v$" uses a second, reversed tree. Circular "mod $M$" costs (AtCoder
  ABC232 G) become a cycle of auxiliary vertices sorted by residue. See
  [special graphs](10-functional-graphs-and-special-graphs.md).
- **Dijkstra on huge implicit graphs** where each step jumps by a function: CF 1715E Long Way Home alternates Dijkstra with a
  convex-hull-trick "flight" layer ([CHT](../07-DP-Optimizations/02-convex-hull-trick-and-li-chao-tree.md)).
- **Tree plus few edges** (CF 1051F): $m - n \le 20$ → distances = min(tree distance via [LCA](../10-Trees/02-lca-and-binary-lifting.md),
  paths through one of the $\le 42$ endpoints of extra edges, each with its own Dijkstra).
- **Potentials everywhere.** Min-cost flow's Dijkstra with potentials ([min-cost flow](../12-Flows-and-Matching/04-min-cost-flow.md)),
  "skiing" problems (AtCoder ABC237 E: costs depend on height differences — choose $h$ = height to make all weights non-negative).
- **Difference constraints with structure** (CF 1450E): Floyd on $n\le200$ with edges of weight $\pm1$, plus a bipartiteness
  check, then choose the source maximizing the spread.
- **Modified Dijkstra with multiple labels** (bi-criteria: cost and time; LC 1928) is exact only when one criterion is bounded
  and small enough to be a state; otherwise it's NP-hard in general (resource-constrained shortest path).
- **Shortest paths in DAGs** need no heap: relax in topological order, negative weights allowed
  ([topological sort and DAG DP](04-topological-sort-and-dag-dp.md)).
- **Kinetic/"time-expanded" graphs** and **Dial's buckets** (radix heap) for integer weights ≤ C: $O(m + nC)$ — useful when
  $C$ is tiny and $n$ huge.

## 8. Practice ladder

**1400–1700**
- [ ] [CSES 1671 · Shortest Routes I](https://cses.fi/problemset/task/1671) — Dijkstra
- [ ] [CSES 1672 · Shortest Routes II](https://cses.fi/problemset/task/1672) — Floyd–Warshall
- [ ] [AtCoder ABC211 D · Number of Shortest paths](https://atcoder.jp/contests/abc211/tasks/abc211_d) — BFS counting
- [ ] [AtCoder ABC208 D · Shortest Path Queries 2](https://atcoder.jp/contests/abc208/tasks/abc208_d) — Floyd's intermediate stages
- [ ] [AtCoder ABC191 E · Come Back Quickly](https://atcoder.jp/contests/abc191/tasks/abc191_e) — shortest cycle through each vertex
- [ ] [AtCoder ABC192 E · Train](https://atcoder.jp/contests/abc192/tasks/abc192_e) — time-dependent Dijkstra
- [ ] [AtCoder ABC237 E · Skiing](https://atcoder.jp/contests/abc237/tasks/abc237_e) — potentials
- [ ] [AtCoder ABC252 E · Road Reduction](https://atcoder.jp/contests/abc252/tasks/abc252_e) — shortest-path tree
- [ ] [CSES 1195 · Flight Discount](https://cses.fi/problemset/task/1195) — layered graph
- [ ] [CSES 1673 · High Score](https://cses.fi/problemset/task/1673) — Bellman–Ford + reachability
- [ ] [CSES 1197 · Cycle Finding](https://cses.fi/problemset/task/1197) — negative cycle
- [ ] [CSES 1202 · Investigation](https://cses.fi/problemset/task/1202) — counting on the DAG
- [ ] [CF 295B · Greg and Graph](https://codeforces.com/problemset/problem/295/B) — 1700

**1700–2100**
- [ ] [CSES 1196 · Flight Routes](https://cses.fi/problemset/task/1196) — k shortest walks
- [ ] [AtCoder ABC051 D · Candidates of No Shortest Paths](https://atcoder.jp/contests/abc051/tasks/abc051_d) — tight edges
- [ ] [AtCoder ABC137 E · Coins Respawn](https://atcoder.jp/contests/abc137/tasks/abc137_e) — Bellman–Ford, cycles on the way to $n$
- [ ] [AtCoder ABC164 E · Two Currencies](https://atcoder.jp/contests/abc164/tasks/abc164_e) — Dijkstra on (vertex, coins)
- [ ] [AtCoder ABC061 D · Score Attack](https://atcoder.jp/contests/abc061/tasks/abc061_d) — longest path with positive cycles
- [ ] [CF 20C · Dijkstra?](https://codeforces.com/problemset/problem/20/C) — 1900
- [ ] [CF 25C · Roads in Berland](https://codeforces.com/problemset/problem/25/C) — 1900
- [ ] [CF 1307D · Cow and Fields](https://codeforces.com/problemset/problem/1307/D) — 1900
- [ ] [CF 449B · Jzzhu and Cities](https://codeforces.com/problemset/problem/449/B) — 2000
- [ ] [CF 545E · Paths and Trees](https://codeforces.com/problemset/problem/545/E) — 2000
- [ ] [CF 938D · Buy a Ticket](https://codeforces.com/problemset/problem/938/D) — 2000
- [ ] [CF 1433G · Reducing Delivery Cost](https://codeforces.com/problemset/problem/1433/G) — 2100
- [ ] [CF 1343E · Weights Distributing](https://codeforces.com/problemset/problem/1343/E) — 2100

**2100+**
- [ ] [CF 786B · Legacy](https://codeforces.com/problemset/problem/786/B) — 2300
- [ ] [CF 715B · Complete The Graph](https://codeforces.com/problemset/problem/715/B) — 2300
- [ ] [CF 1473E · Minimum Path](https://codeforces.com/problemset/problem/1473/E) — 2400
- [ ] [CF 1051F · The Shortest Statement](https://codeforces.com/problemset/problem/1051/F) — 2400
- [ ] [CF 1715E · Long Way Home](https://codeforces.com/problemset/problem/1715/E) — 2400
- [ ] [AtCoder ABC232 G · Modulo Shortest Path](https://atcoder.jp/contests/abc232/tasks/abc232_g) — graph construction
- [ ] [CF 241E · Flights](https://codeforces.com/problemset/problem/241/E) — 2600
- [ ] [CF 1450E · Capitalism](https://codeforces.com/problemset/problem/1450/E) — 2700

## 9. LeetCode / FAANG cross-reference

Dijkstra is expected at FAANG on-sites (Medium/Hard); Bellman–Ford appears mostly as "at most $k$ stops"; Floyd as "all pairs
under a threshold". Negative cycles and difference constraints are rare in interviews.

- [LC 743 · Network Delay Time](https://leetcode.com/problems/network-delay-time/) — Medium — plain Dijkstra, answer = max distance.
- [LC 787 · Cheapest Flights Within K Stops](https://leetcode.com/problems/cheapest-flights-within-k-stops/) — Medium — Bellman–Ford with $k+1$ rounds on a copy of `d` (or state Dijkstra).
- [LC 1631 · Path With Minimum Effort](https://leetcode.com/problems/path-with-minimum-effort/) — Medium — minimax Dijkstra.
- [LC 778 · Swim in Rising Water](https://leetcode.com/problems/swim-in-rising-water/) — Hard — minimax Dijkstra / DSU.
- [LC 1514 · Path with Maximum Probability](https://leetcode.com/problems/path-with-maximum-probability/) — Medium — max-product Dijkstra.
- [LC 1334 · Find the City With the Smallest Number of Neighbors at a Threshold Distance](https://leetcode.com/problems/find-the-city-with-the-smallest-number-of-neighbors-at-a-threshold-distance/) — Medium — Floyd.
- [LC 1976 · Number of Ways to Arrive at Destination](https://leetcode.com/problems/number-of-ways-to-arrive-at-destination/) — Medium — Example 4's counting.
- [LC 1786 · Number of Restricted Paths From First to Last Node](https://leetcode.com/problems/number-of-restricted-paths-from-first-to-last-node/) — Medium — Dijkstra from $n$ + DP in distance order.
- [LC 2203 · Minimum Weighted Subgraph With the Required Paths](https://leetcode.com/problems/minimum-weighted-subgraph-with-the-required-paths/) — Hard — three Dijkstras (one reversed), meet at a vertex.
- [LC 2045 · Second Minimum Time to Reach Destination](https://leetcode.com/problems/second-minimum-time-to-reach-destination/) — Hard — keep two best per vertex.
- [LC 882 · Reachable Nodes In Subdivided Graph](https://leetcode.com/problems/reachable-nodes-in-subdivided-graph/) — Hard — Dijkstra then count edge remainders.
- [LC 1928 · Minimum Cost to Reach Destination in Time](https://leetcode.com/problems/minimum-cost-to-reach-destination-in-time/) — Hard — state (node, time).
- [LC 2577 · Minimum Time to Visit a Cell In a Grid](https://leetcode.com/problems/minimum-time-to-visit-a-cell-in-a-grid/) — Hard — time-dependent Dijkstra with parity waiting.
- [LC 3112 · Minimum Time to Visit Disappearing Nodes](https://leetcode.com/problems/minimum-time-to-visit-disappearing-nodes/) — Medium — Dijkstra with deadlines.
- [LC 2642 · Design Graph With Shortest Path Calculator](https://leetcode.com/problems/design-graph-with-shortest-path-calculator/) — Hard — Dijkstra per query or Floyd with $O(n^2)$ edge insertion.
- [LC 2662 · Minimum Cost of a Path With Special Roads](https://leetcode.com/problems/minimum-cost-of-a-path-with-special-roads/) — Medium — Dijkstra on special-road endpoints only.

More interview framing: [FAANG advanced graphs](../17-FAANG-Interview-DSA/12-advanced-graphs.md).

## 10. Self-check

1. Point to the exact line of Dijkstra's correctness proof that uses $w \ge 0$, and give a 3-vertex counterexample.
2. Why does adding a constant $C$ to every edge not make negative weights safe, while potentials $h(u) - h(v)$ do?
3. After $k$ rounds of Bellman–Ford, what is guaranteed about $d[v]$? Why are $n - 1$ rounds enough?
4. Why must you walk `par` $n$ times before extracting a negative cycle?
5. Why is the in-place Floyd–Warshall correct, and what goes wrong if $k$ is the innermost loop?
6. In Example 3, why is "shortest path, then halve its largest edge" wrong?
7. When is it wrong to count shortest paths during Dijkstra's relaxations?
8. A system $x_v - x_u \le w$ is feasible. Which solution does Bellman–Ford from a virtual source return, and why is it the
   largest with $x \le 0$?

<details><summary>Answers</summary>

1. "$\operatorname{dist}(y) \le \operatorname{dist}(u)$ because $y$ is on a shortest path to $u$". Counterexample:
   $s\to a$ (2), $s\to b$ (3), $b\to a$ ($-2$): $a$ is settled at 2, true distance 1.
2. A constant per edge penalizes paths by their number of edges, changing which path is shortest. A potential changes every
   $s\leadsto t$ path by the same $h(s) - h(t)$ (the sum telescopes), preserving the order.
3. $d[v] \le$ the minimum length of a walk with at most $k$ edges. Without negative cycles some shortest walk is a simple path
   with $\le n-1$ edges.
4. The vertex relaxed in round $n$ may lie on a parent chain *leading out of* the cycle; following $n$ parents from it must
   enter the cycle (the chain cannot stay acyclic for $n$ steps among $n$ vertices).
5. In round $k$ the entries $d[i][k]$ and $d[k][j]$ cannot change (that would need $d[k][k]<0$), so reading updated or old
   values is the same. With $k$ innermost, $d[i][j]$ is finalized after considering only paths whose split points were already
   optimal — it misses paths needing several intermediate vertices.
6. The best discounted trip may use a path that is not shortest without the coupon (test 3: shortest is $1\to2\to4$ with
   price 12, best with coupon is $1\to3\to4$ with $1 + 7 = 8$).
7. When zero-weight edges exist: two vertices with equal $d$ may be DAG-predecessor and successor in either pop order, so a
   successor can be finalized before its predecessor contributed. Use a topological order of the tight-edge DAG.
8. $x_v = \operatorname{dist}(S, v)$. Any solution with $x \le 0$ satisfies $x_v \le x_u + w$ along every path from $S$ (where
   $x_S = 0$), so $x_v \le \operatorname{dist}(S,v)$; and $\operatorname{dist}$ satisfies every constraint by the triangle
   inequality.

</details>
