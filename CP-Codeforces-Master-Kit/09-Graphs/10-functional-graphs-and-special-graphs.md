# Functional Graphs and Special Graphs

> **Band:** 🟢 1200 → 🔴 2400 · **Priority:** 🔥 (functional graphs, binary lifting, cycle decomposition) · ⚡ (complement BFS, virtual nodes) · 🧊 (cactus, planar, segment-tree graphs) · **FAANG:** medium · **Prerequisites:** [BFS/DFS](01-graph-representation-bfs-dfs.md), [binary lifting](../10-Trees/02-lca-and-binary-lifting.md), [shortest paths](02-shortest-paths.md)
> **You can say you know this when:** you can decompose any successor graph into cycles and in-trees iteratively in $O(n)$, answer "where am I after $k$ steps" and "how many steps from $a$ to $b$" for $2\cdot10^5$ queries, find $\mu$ and $\lambda$ of an implicit sequence with $O(1)$ memory, run BFS on a complement graph in $O(n + m)$, and replace $O(n^2)$ edge sets by virtual nodes or segment-tree nodes.

## 1. First principles — why this works

### 1.1 Functional (successor) graphs

A **functional graph** has exactly one outgoing edge per vertex: $v \to f(v)$. Examples: "each planet's teleporter", "each
person passes the ball to $a_i$", iterating $x \mapsto x^2 + 1 \bmod p$, a permutation, a linked list's `next` pointer.

**Structure theorem (the ρ shape).** Start at any $x_0$ and follow $f$. There are finitely many vertices, so some vertex repeats;
let $x_\mu$ be the first vertex that appears twice and $\lambda$ the gap between its occurrences. Then $x_0, \dots, x_{\mu-1}$ is a
**tail** and $x_\mu, \dots, x_{\mu+\lambda-1}$ a **cycle**, and the walk stays on that cycle forever. Globally: every weakly
connected component contains **exactly one cycle** (a component with $k$ vertices has $k$ edges — one more than a tree — and
every vertex reaches a cycle), with trees hanging into it. Reverse the arcs and each component is a cycle of roots of in-trees.

Consequences that drive every algorithm:
- **Answering "after $k$ steps"** naively costs $O(k)$; doubling tables $\text{up}_j(v) = f^{2^j}(v)$ satisfy
  $\text{up}_{j}(v) = \text{up}_{j-1}(\text{up}_{j-1}(v))$, so any $f^k$ is a product of $\le \log k$ jumps (binary lifting).
- **Everything about a vertex is determined by its tail length and its cycle**: the number of distinct vertices on its walk is
  $\text{tail}(v) + \text{len}(\text{cycle}(v))$; distance to a cycle vertex is tail + offset along the cycle.
- **Decomposition in $O(n)$**: walk from an unvisited vertex marking vertices "on the current path" until you hit (a) a vertex on the
  current path → you closed a new cycle; or (b) a finished vertex → you joined an old component. Then fill values backwards along
  the path. Every vertex is pushed once. No recursion needed (tails can be $2\cdot10^5$ long).

**Permutations** are functional graphs where $f$ is a bijection: no tails, only disjoint cycles. Order of the permutation
$= \operatorname{lcm}$ of cycle lengths; minimum swaps to sort $= n - \#\text{cycles}$; parity $= (n - \#\text{cycles}) \bmod 2$.

### 1.2 Cycle detection with O(1) memory (Floyd, Brent)

When $f$ is implicit (a PRNG, Pollard's rho, `x -> x*x % m`, "find the duplicate number" without extra memory) you cannot store
visited states.

**Floyd (tortoise and hare).** Move $T$ by one step and $H$ by two. Once both are on the cycle, the gap $H - T$ (in positions)
grows by one per step, so after at most $\lambda$ more steps it is a multiple of $\lambda$: they meet at some step $i$ with
$i \ge \mu$ and $\lambda \mid i$ (the smallest such $i$ is $\le \mu + \lambda$). Then
**$\mu$:** reset $T$ to $x_0$ and move both one step at a time; after $\mu$ steps $T = x_\mu$ and $H = x_{i+\mu} = x_\mu$ (since $\lambda \mid i$),
and they cannot meet earlier (before $\mu$ steps $T$ is on the tail and $H$ on the cycle). **$\lambda$:** walk once around from $x_\mu$.

**Brent.** Keep a "teleporting tortoise": for $p = 1, 2, 4, \dots$ the tortoise waits at the hare's position while the hare walks up
to $p$ steps. The first time the hare meets it, the number of steps since the last teleport is exactly $\lambda$ (as soon as $p \ge \lambda$
and the tortoise sits on the cycle). Then $\mu$: start one pointer $\lambda$ steps ahead and advance both until they meet. Brent
evaluates $f$ fewer times than Floyd (roughly 36% fewer on random functions per Brent's analysis), which matters when $f$ is expensive.

### 1.3 Complement graphs

Sometimes the input lists the **missing** edges of a complete graph ($n, m \le 2\cdot10^5$, so the actual graph has $\sim n^2/2$ edges).
BFS on it naively scans $n$ candidates per vertex: $O(n^2)$. Trick: keep the set $R$ of **unvisited** vertices. When processing $u$,
mark $u$'s missing neighbors, then scan $R$: an unmarked vertex is a real neighbor — remove it from $R$ and enqueue it; a marked one
stays. Cost per scan = removed + kept. Each vertex is removed once ($\le n$ total), and each kept vertex $x$ during $u$'s scan is
charged to the missing edge $(u, x)$, which happens at most once per processed $u$, so $\le 2m$ total. **$O(n + m)$.**

### 1.4 Special graph classes worth recognising

- **Cactus** (🧊): every edge lies on at most one simple cycle. Its blocks are single edges or simple cycles, so the block-cut tree
  ([BCC](06-bridges-articulation-points-and-bcc.md)) turns most problems into tree DP where a cycle node needs a small extra DP around
  the cycle. A connected cactus has $m - n + 1$ cycles and $m \le \lfloor 3(n-1)/2 \rfloor$.
- **Planar graphs** (🧊): Euler's formula $V - E + F = 1 + C$ ($= 2$ when connected). Every face has $\ge 3$ edges and every edge
  borders 2 faces, so $3F \le 2E$, giving $E \le 3V - 6$ ($V \ge 3$); with no triangles (e.g. bipartite) $4F \le 2E$ gives $E \le 2V - 4$.
  Hence average degree $< 6$, a vertex of degree $\le 5$ always exists, planar graphs are 5-degenerate (greedy 6-coloring; 4 colors
  suffice by the four color theorem). Practical use: "the graph is planar/grid-like" ⇒ $m = O(n)$, so $O(m \sqrt m)$ triangle
  listing or $O(nm)$ tricks are fast. $K_5$ and $K_{3,3}$ are not planar.
- **DAGs, trees, bipartite graphs, functional graphs, permutation graphs** each have their own file or section; the fastest way to
  solve a graph problem is often to notice that the constraints force one of these shapes ("each node has exactly one parent",
  "$m = n$", "$m = n - 1$ and connected").

### 1.5 Graph construction tricks

Many "shortest path" problems are easy once the graph is right; the art is keeping it small.
- **Virtual (hub) nodes:** "teleport between any two cells of the same color for cost $c$" would add $k^2$ edges; instead add a hub
  per color with edges cell → hub (cost $c$) and hub → cell (cost $0$). Same for "all vertices with value $x$", "all stations of a line".
  A **super source** joined to many starts with weight 0 turns multi-source shortest paths into one run.
- **Layered (state) graphs:** vertex × (coupons used, parity, time mod $k$, keys collected) — see [shortest paths](02-shortest-paths.md) and [BFS](01-graph-representation-bfs-dfs.md).
- **Segment-tree graphs** (🔴): edges "from $v$ to every vertex in $[l, r]$" or "from every vertex in $[l, r]$ to $v$". Build two
  segment trees over the vertices: an *out-tree* with $0$-weight arcs parent → child, and an *in-tree* with $0$-weight arcs child → parent;
  their leaves are the original vertices. A range edge connects $v$ to the $O(\log n)$ canonical out-tree nodes covering $[l,r]$
  (or those in-tree nodes to $v$). Total size $O(n + q \log n)$; Dijkstra on it solves [CF 786B · Legacy](https://codeforces.com/problemset/problem/786/B) — 2300.
  The same idea builds 2-SAT implication graphs with range clauses.
- **DSU or BFS?** Static connectivity: BFS/DFS (linear, simple). Edges arriving online with queries in between: DSU. Edges being
  deleted: process offline in reverse (deletions become insertions) or use the segment tree on time
  ([DSU rollback](../16-IGM-Frontier/02-segment-tree-on-time-and-dsu-rollback.md)). Need the actual path: BFS/DFS (DSU forgets it).

## 2. Formulas, definitions and identities

| Fact | Meaning / why |
|---|---|
| walk from $x_0$: $x_i = f^i(x_0)$; tail $\mu$, cycle $\lambda$; $\mu + \lambda \le n$ | ρ shape, first repeat |
| $x_i = x_j$ for $i < j$ $\iff$ $i \ge \mu$ and $\lambda \mid (j - i)$ | positions on the cycle repeat with period $\lambda$ |
| Floyd meets at the smallest $i \ge \max(\mu, 1)$ with $\lambda \mid i$, so $i \le \mu + \lambda$ | gap grows by 1 per step |
| $f^{a+b} = f^a \circ f^b$; $\text{up}_j = \text{up}_{j-1} \circ \text{up}_{j-1}$ | binary lifting, $O(n \log K)$ memory, $O(\log K)$ per query |
| distinct vertices visited from $v$ $= \text{tail}(v) + \lambda(v)$ | CSES Planets Cycles, LC 2876 |
| steps from $a$ to cycle vertex $b$ $= \text{tail}(a) + (\text{pos}(b) - \text{pos}(\text{entry}(a))) \bmod \lambda$ | if same cycle, else unreachable |
| steps from $a$ to tail vertex $b$ $= \text{depth}(a) - \text{depth}(b)$ iff $f^{\text{depth}(a)-\text{depth}(b)}(a) = b$ | depth = distance to the cycle |
| #functional graphs on $n$ labeled vertices $= n^n$; #permutations $= n!$ | each vertex picks its successor |
| random mapping: expected tail and cycle length $\approx \sqrt{\pi n / 8}$ each, ρ length $\approx \sqrt{\pi n/2}$ | birthday paradox; why Pollard rho takes $O(n^{1/4})$ ([Pollard rho](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md)) |
| permutation: order $= \operatorname{lcm}(\text{cycle lengths})$; min swaps $= n - c$; sign $= (-1)^{n-c}$ | disjoint cycles |
| complement of a graph with $m$ edges has $\binom{n}{2} - m$ edges; complement BFS $O(n + m)$ | charge kept vertices to missing edges |
| $G$ disconnected $\Rightarrow \bar G$ connected | across components every pair is an edge of $\bar G$; inside one, both ends share a neighbor in another component |
| $\bar G$ given by $m$ missing edges has $k$ components $\Rightarrow \binom{k}{2} \le m$ | every cross pair must be missing, so $k \le 633$ for $m = 2\cdot10^5$ |
| planar: $V - E + F = 1 + C$; $E \le 3V - 6$; triangle-free planar $E \le 2V - 4$ | face counting |
| connected cactus: #cycles $= m - n + 1$; $m \le \lfloor 3(n-1)/2\rfloor$ | each cycle adds one edge beyond a tree |
| segment-tree graph: $\le 4n$ extra nodes, $O(\log n)$ edges per range edge | two trees with opposite orientations |

## 3. Implementation (C++ and Java)

**Decomposition of a functional graph** (iterative). Fills, for each vertex: `onCycle`, `cyc` (cycle id), `pos` (index on its
cycle, increasing along $f$), `depth` (distance to the cycle), `entry` (first cycle vertex reached); and `cycLen[id]`.

```cpp
struct FunctionalGraph {
    int n;
    vector<int> f, depth, entry, cyc, pos, cycLen;
    vector<char> onCycle;
    explicit FunctionalGraph(const vector<int>& succ) : n(succ.size()), f(succ) {
        depth.assign(n, 0); entry.assign(n, -1); cyc.assign(n, -1); pos.assign(n, -1); onCycle.assign(n, 0);
        vector<int> state(n, 0), idx(n, -1), path;          // state: 0 new, 1 on current path, 2 done
        for (int s = 0; s < n; s++) {
            if (state[s]) continue;
            path.clear();
            int v = s;
            while (state[v] == 0) { state[v] = 1; idx[v] = path.size(); path.push_back(v); v = f[v]; }
            if (state[v] == 1) {                              // closed a new cycle starting at path[idx[v]]
                int id = cycLen.size(), start = idx[v], len = path.size() - start;
                cycLen.push_back(len);
                for (int j = start; j < (int)path.size(); j++) {
                    int u = path[j];
                    onCycle[u] = 1; cyc[u] = id; pos[u] = j - start; depth[u] = 0; entry[u] = u; state[u] = 2;
                }
                path.resize(start);
            }
            for (int j = (int)path.size() - 1; j >= 0; j--) { // tail vertices, from nearest-to-cycle outward
                int u = path[j];
                depth[u] = depth[f[u]] + 1; entry[u] = entry[f[u]]; cyc[u] = cyc[f[u]]; state[u] = 2;
            }
        }
    }
};
```

```java
static class FunctionalGraph {
    int n, cycles = 0;
    int[] f, depth, entry, cyc, pos, cycLen;
    boolean[] onCycle;
    FunctionalGraph(int[] succ) {
        n = succ.length; f = succ;
        depth = new int[n]; entry = new int[n]; cyc = new int[n]; pos = new int[n]; cycLen = new int[n];
        onCycle = new boolean[n];
        int[] state = new int[n], idx = new int[n], path = new int[n];
        for (int s = 0; s < n; s++) {
            if (state[s] != 0) continue;
            int len = 0, v = s;
            while (state[v] == 0) { state[v] = 1; idx[v] = len; path[len++] = v; v = f[v]; }
            if (state[v] == 1) {
                int id = cycles++, start = idx[v];
                cycLen[id] = len - start;
                for (int j = start; j < len; j++) {
                    int u = path[j];
                    onCycle[u] = true; cyc[u] = id; pos[u] = j - start; depth[u] = 0; entry[u] = u; state[u] = 2;
                }
                len = start;
            }
            for (int j = len - 1; j >= 0; j--) {
                int u = path[j];
                depth[u] = depth[f[u]] + 1; entry[u] = entry[f[u]]; cyc[u] = cyc[f[u]]; state[u] = 2;
            }
        }
    }
}
```

**Binary lifting for $f^k$** ($k < 2^{30}$; use 60 levels and `long` for $k \le 10^{18}$).

```cpp
struct Lifting {
    static const int LOG = 30;
    vector<vector<int>> up;
    explicit Lifting(const vector<int>& f) : up(LOG, f) {
        int n = f.size();
        for (int j = 1; j < LOG; j++)
            for (int v = 0; v < n; v++) up[j][v] = up[j - 1][up[j - 1][v]];
    }
    int jump(int v, long long k) const {
        for (int j = 0; j < LOG; j++) if (k >> j & 1) v = up[j][v];
        return v;
    }
};
```

```java
static class Lifting {
    static final int LOG = 30;
    int[][] up;
    Lifting(int[] f) {
        int n = f.length;
        up = new int[LOG][];
        up[0] = f.clone();
        for (int j = 1; j < LOG; j++) {
            up[j] = new int[n];
            for (int v = 0; v < n; v++) up[j][v] = up[j - 1][up[j - 1][v]];
        }
    }
    int jump(int v, long k) {
        for (int j = 0; j < LOG; j++) if ((k >> j & 1) == 1) v = up[j][v];
        return v;
    }
}
```

**Floyd's cycle detection** for an implicit function (returns $\{\mu, \lambda\}$).

```cpp
pair<long long, long long> floydRho(const function<long long(long long)>& f, long long x0) {
    long long t = f(x0), h = f(f(x0));
    while (t != h) { t = f(t); h = f(f(h)); }
    long long mu = 0;
    t = x0;
    while (t != h) { t = f(t); h = f(h); mu++; }        // both now at x_mu
    long long lam = 1;
    h = f(t);
    while (t != h) { h = f(h); lam++; }
    return {mu, lam};
}
```

```java
static long[] floydRho(LongUnaryOperator f, long x0) {
    long t = f.applyAsLong(x0), h = f.applyAsLong(f.applyAsLong(x0));
    while (t != h) { t = f.applyAsLong(t); h = f.applyAsLong(f.applyAsLong(h)); }
    long mu = 0;
    t = x0;
    while (t != h) { t = f.applyAsLong(t); h = f.applyAsLong(h); mu++; }
    long lam = 1;
    h = f.applyAsLong(t);
    while (t != h) { h = f.applyAsLong(h); lam++; }
    return new long[]{mu, lam};
}
```

**Segment-tree graph** (🔴). Vertices $0..n-1$ are the leaves of both trees; internal nodes get fresh ids. Run Dijkstra on `g`.

```cpp
struct SegGraph {
    int n, N;
    vector<int> outId, inId;
    vector<vector<pair<int, long long>>> g;
    explicit SegGraph(int n) : n(n), N(n), outId(4 * n), inId(4 * n) {
        build(1, 0, n - 1);
        g.resize(N);
        link(1, 0, n - 1);
    }
    void build(int x, int l, int r) {
        if (l == r) { outId[x] = inId[x] = l; return; }
        outId[x] = N++; inId[x] = N++;
        int mid = (l + r) / 2;
        build(2 * x, l, mid); build(2 * x + 1, mid + 1, r);
    }
    void link(int x, int l, int r) {
        if (l == r) return;
        for (int c : {2 * x, 2 * x + 1}) {
            g[outId[x]].push_back({outId[c], 0});         // out-tree: downward, reaches every leaf below
            g[inId[c]].push_back({inId[x], 0});           // in-tree: upward, every leaf reaches its ancestors
        }
        int mid = (l + r) / 2;
        link(2 * x, l, mid); link(2 * x + 1, mid + 1, r);
    }
    template <class F> void cover(int x, int l, int r, int lo, int hi, F&& fn) {
        if (hi < l || r < lo) return;
        if (lo <= l && r <= hi) { fn(x); return; }
        int mid = (l + r) / 2;
        cover(2 * x, l, mid, lo, hi, fn); cover(2 * x + 1, mid + 1, r, lo, hi, fn);
    }
    void vertexToRange(int v, int lo, int hi, long long w) { cover(1, 0, n - 1, lo, hi, [&](int x) { g[v].push_back({outId[x], w}); }); }
    void rangeToVertex(int lo, int hi, int v, long long w) { cover(1, 0, n - 1, lo, hi, [&](int x) { g[inId[x]].push_back({v, w}); }); }
};
```

```java
static class SegGraph {
    int n, N;
    int[] outId, inId;
    List<long[]>[] g;                                   // g[u] holds {v, w}
    @SuppressWarnings("unchecked")
    SegGraph(int n) {
        this.n = n; N = n; outId = new int[4 * n]; inId = new int[4 * n];
        build(1, 0, n - 1);
        g = new List[N];
        for (int i = 0; i < N; i++) g[i] = new ArrayList<>();
        link(1, 0, n - 1);
    }
    void build(int x, int l, int r) {
        if (l == r) { outId[x] = inId[x] = l; return; }
        outId[x] = N++; inId[x] = N++;
        int mid = (l + r) / 2;
        build(2 * x, l, mid); build(2 * x + 1, mid + 1, r);
    }
    void link(int x, int l, int r) {
        if (l == r) return;
        for (int c = 2 * x; c <= 2 * x + 1; c++) {
            g[outId[x]].add(new long[]{outId[c], 0});
            g[inId[c]].add(new long[]{inId[x], 0});
        }
        int mid = (l + r) / 2;
        link(2 * x, l, mid); link(2 * x + 1, mid + 1, r);
    }
    void cover(int x, int l, int r, int lo, int hi, IntConsumer fn) {
        if (hi < l || r < lo) return;
        if (lo <= l && r <= hi) { fn.accept(x); return; }
        int mid = (l + r) / 2;
        cover(2 * x, l, mid, lo, hi, fn); cover(2 * x + 1, mid + 1, r, lo, hi, fn);
    }
    void vertexToRange(int v, int lo, int hi, long w) { cover(1, 0, n - 1, lo, hi, x -> g[v].add(new long[]{outId[x], w})); }
    void rangeToVertex(int lo, int hi, int v, long w) { cover(1, 0, n - 1, lo, hi, x -> g[inId[x]].add(new long[]{v, w})); }
}
```

## 4. Recognising the pattern

| Statement signal | Think |
|---|---|
| "each X points to exactly one Y", "teleporter", "passes to $a_i$", array as `next` pointers | functional graph: cycles + in-trees |
| "after $k$ steps" with $k$ up to $10^9$–$10^{18}$ | binary lifting, or tail + $(k - \text{tail}) \bmod \lambda$ |
| "how many distinct states before repeating", "period of the sequence" | ρ decomposition; implicit ⇒ Floyd/Brent |
| "find a duplicate with $O(1)$ extra memory" | Floyd on $i \mapsto a_i$ (LC 287) |
| "minimum cost so that every start is eventually caught/covered" | one choice per cycle (CF 1027D) |
| "swap to sort", "apply permutation $k$ times", "order of permutation" | permutation cycles |
| edges given as the **missing** pairs of a complete graph | complement BFS with an unvisited set |
| "all vertices of color $c$ are connected to each other" | hub node per color |
| "edges from $v$ to all of $[l, r]$" | segment-tree graph |
| "every edge on at most one cycle" | cactus: block-cut tree + cycle DP |
| "graph is planar / grid / drawn without crossings" | $m \le 3n - 6$: dense algorithms become cheap |

## 5. Worked examples (graded)

### Example 1 — Planets Queries I  ·  ★ ≈1600

- **Source:** [CSES 1750 · Planets Queries I](https://cses.fi/problemset/task/1750)
- **Difficulty:** ≈1600 (est.)
- **Problem:** $n \le 2\cdot10^5$ planets, planet $i$ teleports to $t_i$. Answer $q \le 2\cdot10^5$ queries $(x, k)$, $k \le 10^9$:
  where do you end after $k$ teleports from $x$?
- **Thinking from first principles:** Simulating costs $O(k)$ per query. Write $k$ in binary: $f^k$ is a composition of the
  $f^{2^j}$ for the set bits. Precompute $\text{up}_j$ for $j < 30$ in $O(n \log k)$; each query is 30 table lookups.
  (Alternative: decomposition + modular arithmetic on the cycle; lifting is shorter to write and generalises to sums/minima along the walk.)

<details><summary>Solution</summary>

Doubling table of size $30 \times n$ ($6\cdot10^6$ ints, 24 MB). $O((n + q)\log k)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, q;
    cin >> n >> q;
    const int LOG = 30;
    vector<vector<int>> up(LOG, vector<int>(n + 1));
    for (int i = 1; i <= n; i++) cin >> up[0][i];
    for (int j = 1; j < LOG; j++)
        for (int v = 1; v <= n; v++) up[j][v] = up[j - 1][up[j - 1][v]];
    string out;
    while (q--) {
        int x; long long k;
        cin >> x >> k;
        for (int j = 0; j < LOG; j++) if (k >> j & 1) x = up[j][x];
        out += to_string(x); out += '\n';
    }
    cout << out;
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
    static int readByte() throws IOException { return in.read(); }
    static long nextLong() throws IOException {
        int b = readByte();
        while (b != '-' && (b < '0' || b > '9')) b = readByte();
        boolean neg = b == '-';
        if (neg) b = readByte();
        long r = 0;
        while (b >= '0' && b <= '9') { r = r * 10 + (b - '0'); b = readByte(); }
        return neg ? -r : r;
    }
    static int nextInt() throws IOException { return (int) nextLong(); }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), q = nextInt();
        final int LOG = 30;
        int[][] up = new int[LOG][n + 1];
        for (int i = 1; i <= n; i++) up[0][i] = nextInt();
        for (int j = 1; j < LOG; j++)
            for (int v = 1; v <= n; v++) up[j][v] = up[j - 1][up[j - 1][v]];
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            int x = nextInt(); long k = nextLong();
            for (int j = 0; j < LOG; j++) if ((k >> j & 1) == 1) x = up[j][x];
            sb.append(x).append('\n');
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
4 3
2 1 1 4
1 2
3 4
4 1
out:
1
2
4
-->
<!-- test
in:
5 4
2 3 4 5 3
1 1000000000
1 0
5 7
2 1
out:
5
1
3
3
-->

### Example 2 — Planets Cycles  ·  ★ ≈1700

- **Source:** [CSES 1751 · Planets Cycles](https://cses.fi/problemset/task/1751)
- **Difficulty:** ≈1700 (est.)
- **Problem:** Same teleporters, $n \le 2\cdot10^5$. For every starting planet, print how many teleports happen until you land on
  a planet you have already visited (i.e. the number of distinct planets on the walk).
- **Thinking from first principles:** The walk from $v$ is its tail followed by one full cycle; the first repeat happens right after
  the cycle closes. Answer $= \text{tail}(v) + \lambda(v)$. Computing tails one start at a time is $O(n^2)$ on a long path; the
  path-marking decomposition fills all of them in $O(n)$: cycle vertices get $\lambda$, and a tail vertex gets its successor's answer $+1$.

<details><summary>Solution</summary>

Iterative decomposition; values filled backwards along each newly walked path. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<int> f(n + 1);
    for (int i = 1; i <= n; i++) cin >> f[i];
    vector<int> state(n + 1, 0), idx(n + 1), ans(n + 1), path;
    for (int s = 1; s <= n; s++) {
        if (state[s]) continue;
        path.clear();
        int v = s;
        while (state[v] == 0) { state[v] = 1; idx[v] = path.size(); path.push_back(v); v = f[v]; }
        if (state[v] == 1) {
            int start = idx[v], len = path.size() - start;
            for (int j = start; j < (int)path.size(); j++) { ans[path[j]] = len; state[path[j]] = 2; }
            path.resize(start);
        }
        for (int j = (int)path.size() - 1; j >= 0; j--) { ans[path[j]] = ans[f[path[j]]] + 1; state[path[j]] = 2; }
    }
    for (int i = 1; i <= n; i++) cout << ans[i] << " \n"[i == n];
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
    static int readByte() throws IOException { return in.read(); }
    static int nextInt() throws IOException {
        int b = readByte();
        while (b != '-' && (b < '0' || b > '9')) b = readByte();
        boolean neg = b == '-';
        if (neg) b = readByte();
        int r = 0;
        while (b >= '0' && b <= '9') { r = r * 10 + (b - '0'); b = readByte(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = nextInt();
        int[] f = new int[n + 1];
        for (int i = 1; i <= n; i++) f[i] = nextInt();
        int[] state = new int[n + 1], idx = new int[n + 1], ans = new int[n + 1], path = new int[n];
        for (int s = 1; s <= n; s++) {
            if (state[s] != 0) continue;
            int len = 0, v = s;
            while (state[v] == 0) { state[v] = 1; idx[v] = len; path[len++] = v; v = f[v]; }
            if (state[v] == 1) {
                int start = idx[v], cl = len - start;
                for (int j = start; j < len; j++) { ans[path[j]] = cl; state[path[j]] = 2; }
                len = start;
            }
            for (int j = len - 1; j >= 0; j--) { ans[path[j]] = ans[f[path[j]]] + 1; state[path[j]] = 2; }
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 1; i <= n; i++) sb.append(ans[i]).append(i == n ? '\n' : ' ');
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
5
2 4 3 1 4
out:
3 3 1 3 4
-->
<!-- test
in:
1
1
out:
1
-->
<!-- test
in:
6
2 3 4 5 6 6
out:
6 5 4 3 2 1
-->

### Example 3 — Planets Queries II  ·  ★ ≈2000

- **Source:** [CSES 1160 · Planets Queries II](https://cses.fi/problemset/task/1160)
- **Difficulty:** ≈2000 (est.)
- **Problem:** Same teleporters ($n, q \le 2\cdot10^5$). For each query $(a, b)$ print the minimum number of teleports to get from
  $a$ to $b$, or $-1$.
- **Thinking from first principles:** The walk from $a$ is deterministic, so "minimum" is "first time". Two cases by where $b$ is.
  If $b$ is on a cycle: $a$ must drain into the *same* cycle; you need $\text{depth}(a)$ steps to reach $\text{entry}(a)$, then the
  offset along the cycle. If $b$ is on a tail: $b$ is passed at most once, exactly when the remaining depth equals $\text{depth}(b)$,
  i.e. after $\text{depth}(a) - \text{depth}(b)$ steps — so check $f^{\text{depth}(a) - \text{depth}(b)}(a) = b$ with binary lifting.

<details><summary>Solution</summary>

Decomposition (depth, entry, cycle id, position, cycle length) + doubling table. $O((n + q)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, q;
    cin >> n >> q;
    vector<int> f(n);
    for (auto& x : f) { cin >> x; x--; }
    vector<int> depth(n, 0), entry(n), cyc(n), pos(n, 0), cycLen, state(n, 0), idx(n), path;
    vector<char> onCycle(n, 0);
    for (int s = 0; s < n; s++) {
        if (state[s]) continue;
        path.clear();
        int v = s;
        while (state[v] == 0) { state[v] = 1; idx[v] = path.size(); path.push_back(v); v = f[v]; }
        if (state[v] == 1) {
            int id = cycLen.size(), start = idx[v];
            cycLen.push_back(path.size() - start);
            for (int j = start; j < (int)path.size(); j++) {
                int u = path[j];
                onCycle[u] = 1; cyc[u] = id; pos[u] = j - start; entry[u] = u; state[u] = 2;
            }
            path.resize(start);
        }
        for (int j = (int)path.size() - 1; j >= 0; j--) {
            int u = path[j];
            depth[u] = depth[f[u]] + 1; entry[u] = entry[f[u]]; cyc[u] = cyc[f[u]]; state[u] = 2;
        }
    }
    const int LOG = 18;                                      // 2^18 > 2e5 >= any depth difference
    vector<vector<int>> up(LOG, f);
    for (int j = 1; j < LOG; j++)
        for (int v = 0; v < n; v++) up[j][v] = up[j - 1][up[j - 1][v]];
    auto jump = [&](int v, int k) { for (int j = 0; j < LOG; j++) if (k >> j & 1) v = up[j][v]; return v; };
    string out;
    while (q--) {
        int a, b; cin >> a >> b; a--; b--;
        long long res = -1;
        if (cyc[a] == cyc[b]) {
            if (onCycle[b]) {
                int L = cycLen[cyc[b]];
                res = depth[a] + (pos[b] - pos[entry[a]] + L) % L;
            } else if (depth[a] >= depth[b] && jump(a, depth[a] - depth[b]) == b) {
                res = depth[a] - depth[b];
            }
        }
        out += to_string(res); out += '\n';
    }
    cout << out;
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
    static int readByte() throws IOException { return in.read(); }
    static int nextInt() throws IOException {
        int b = readByte();
        while (b != '-' && (b < '0' || b > '9')) b = readByte();
        boolean neg = b == '-';
        if (neg) b = readByte();
        int r = 0;
        while (b >= '0' && b <= '9') { r = r * 10 + (b - '0'); b = readByte(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), q = nextInt();
        int[] f = new int[n];
        for (int i = 0; i < n; i++) f[i] = nextInt() - 1;
        int[] depth = new int[n], entry = new int[n], cyc = new int[n], pos = new int[n], cycLen = new int[n];
        int[] state = new int[n], idx = new int[n], path = new int[n];
        boolean[] onCycle = new boolean[n];
        int cycles = 0;
        for (int s = 0; s < n; s++) {
            if (state[s] != 0) continue;
            int len = 0, v = s;
            while (state[v] == 0) { state[v] = 1; idx[v] = len; path[len++] = v; v = f[v]; }
            if (state[v] == 1) {
                int id = cycles++, start = idx[v];
                cycLen[id] = len - start;
                for (int j = start; j < len; j++) {
                    int u = path[j];
                    onCycle[u] = true; cyc[u] = id; pos[u] = j - start; entry[u] = u; state[u] = 2;
                }
                len = start;
            }
            for (int j = len - 1; j >= 0; j--) {
                int u = path[j];
                depth[u] = depth[f[u]] + 1; entry[u] = entry[f[u]]; cyc[u] = cyc[f[u]]; state[u] = 2;
            }
        }
        final int LOG = 18;
        int[][] up = new int[LOG][];
        up[0] = f.clone();
        for (int j = 1; j < LOG; j++) {
            up[j] = new int[n];
            for (int v = 0; v < n; v++) up[j][v] = up[j - 1][up[j - 1][v]];
        }
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            int a = nextInt() - 1, b = nextInt() - 1;
            long res = -1;
            if (cyc[a] == cyc[b]) {
                if (onCycle[b]) {
                    int L = cycLen[cyc[b]];
                    res = depth[a] + ((pos[b] - pos[entry[a]]) % L + L) % L;
                } else if (depth[a] >= depth[b]) {
                    int v = a, k = depth[a] - depth[b];
                    for (int j = 0; j < LOG; j++) if ((k >> j & 1) == 1) v = up[j][v];
                    if (v == b) res = k;
                }
            }
            sb.append(res).append('\n');
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
5 5
2 3 2 3 4
1 3
4 2
5 1
3 3
5 2
out:
2
2
-1
0
3
-->
<!-- test
in:
7 6
2 3 1 3 4 7 6
5 1
5 4
4 5
6 7
1 6
7 7
out:
3
1
-1
1
-1
0
-->

### Example 4 — Mouse Hunt  ·  ★ 1700

- **Source:** [CF 1027D · Mouse Hunt](https://codeforces.com/problemset/problem/1027/D) — 1700
- **Difficulty:** 1700
- **Problem:** $n \le 2\cdot10^5$ rooms; from room $i$ the mouse always runs to $a_i$; a trap in room $i$ costs $c_i$. The mouse
  may start anywhere. Choose traps of minimum total cost so the mouse is caught whatever its start. Input: $n$, the costs, then the $a_i$.
- **Thinking from first principles:** A mouse starting anywhere eventually loops on the cycle of its component forever, so every
  cycle needs at least one trap — otherwise starting on that cycle escapes forever. One trap per cycle suffices: every walk reaches
  that cycle and goes around it. Traps on tails are useless. Answer $= \sum_{\text{cycles}} \min_{v \in \text{cycle}} c_v$.

<details><summary>Solution</summary>

Path-marking decomposition; when a new cycle closes, take the minimum cost on it. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<int> c(n + 1), a(n + 1);
    for (int i = 1; i <= n; i++) cin >> c[i];
    for (int i = 1; i <= n; i++) cin >> a[i];
    vector<int> state(n + 1, 0);
    long long total = 0;
    for (int s = 1; s <= n; s++) {
        if (state[s]) continue;
        vector<int> path;
        int v = s;
        while (state[v] == 0) { state[v] = 1; path.push_back(v); v = a[v]; }
        if (state[v] == 1) {                       // v starts a cycle that we just closed
            int best = c[v];
            for (int u = a[v]; u != v; u = a[u]) best = min(best, c[u]);
            total += best;
        }
        for (int u : path) state[u] = 2;
    }
    cout << total << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
    static int readByte() throws IOException { return in.read(); }
    static int nextInt() throws IOException {
        int b = readByte();
        while (b != '-' && (b < '0' || b > '9')) b = readByte();
        boolean neg = b == '-';
        if (neg) b = readByte();
        int r = 0;
        while (b >= '0' && b <= '9') { r = r * 10 + (b - '0'); b = readByte(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = nextInt();
        int[] c = new int[n + 1], a = new int[n + 1];
        for (int i = 1; i <= n; i++) c[i] = nextInt();
        for (int i = 1; i <= n; i++) a[i] = nextInt();
        int[] state = new int[n + 1], path = new int[n];
        long total = 0;
        for (int s = 1; s <= n; s++) {
            if (state[s] != 0) continue;
            int len = 0, v = s;
            while (state[v] == 0) { state[v] = 1; path[len++] = v; v = a[v]; }
            if (state[v] == 1) {
                int best = c[v];
                for (int u = a[v]; u != v; u = a[u]) best = Math.min(best, c[u]);
                total += best;
            }
            for (int j = 0; j < len; j++) state[path[j]] = 2;
        }
        System.out.println(total);
    }
}
```

</details>

<!-- test
in:
5
1 2 3 2 10
1 3 4 3 3
out:
3
-->
<!-- test
in:
4
1 10 2 10
2 4 1 2
out:
10
-->
<!-- test
in:
1
7
1
out:
7
-->
<!-- test
in:
6
5 4 3 2 1 6
2 1 4 3 6 5
out:
7
-->

### Example 5 — Period of a linear congruential generator  ·  ★ ≈1800

- **Source:** Original problem.
- **Difficulty:** ≈1800 (est.)
- **Problem:** $x_{i+1} = (A x_i + B) \bmod M$ with $0 \le A, B, x_0 < M \le 10^9$; it is guaranteed that $\mu + \lambda \le 2\cdot10^7$.
  Print the tail length $\mu$ and the cycle length $\lambda$ of the sequence, using $O(1)$ memory.
- **Thinking from first principles:** A hash set of seen values would need $2\cdot10^7$ entries (hundreds of MB in Java). The
  sequence is a walk in the functional graph $x \mapsto Ax + B$, so Brent (or Floyd) finds $\lambda$ and then $\mu$ with two pointers.
  Products $A x < 10^{18}$ fit in 64 bits.

<details><summary>Solution</summary>

Brent: double the window until the hare meets the parked tortoise; the steps since the last park equal $\lambda$. Then put one
pointer $\lambda$ steps ahead of $x_0$ and advance both until equal; the number of steps is $\mu$. $O(\mu + \lambda)$ evaluations.
Checked against a brute force that stores every value, on random small $M$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    long long A, B, M, x0;
    cin >> A >> B >> M >> x0;
    auto f = [&](long long x) { return (A * x + B) % M; };
    long long power = 1, lam = 1, tort = x0, hare = f(x0);
    while (tort != hare) {
        if (power == lam) { tort = hare; power *= 2; lam = 0; }   // park the tortoise at the hare
        hare = f(hare);
        lam++;
    }
    tort = hare = x0;
    for (long long i = 0; i < lam; i++) hare = f(hare);          // hare is lambda steps ahead
    long long mu = 0;
    while (tort != hare) { tort = f(tort); hare = f(hare); mu++; }
    cout << mu << " " << lam << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long A, B, M;
    static long f(long x) { return (A * x + B) % M; }

    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        A = Long.parseLong(st.nextToken()); B = Long.parseLong(st.nextToken());
        M = Long.parseLong(st.nextToken()); long x0 = Long.parseLong(st.nextToken());
        long power = 1, lam = 1, tort = x0, hare = f(x0);
        while (tort != hare) {
            if (power == lam) { tort = hare; power *= 2; lam = 0; }
            hare = f(hare);
            lam++;
        }
        tort = x0; hare = x0;
        for (long i = 0; i < lam; i++) hare = f(hare);
        long mu = 0;
        while (tort != hare) { tort = f(tort); hare = f(hare); mu++; }
        System.out.println(mu + " " + lam);
    }
}
```

</details>

<!-- test
in:
2 0 7 1
out:
0 3
-->
<!-- test
in:
2 1 12 0
out:
2 2
-->
<!-- test
in:
0 3 10 7
out:
1 1
-->
<!-- test
in:
1 0 1 0
out:
0 1
-->
<!-- test
in:
1 1 1000000 0
out:
0 1000000
-->

### Example 6 — Connected Components? (complement BFS)  ·  ★ 2100

- **Source:** [CF 920E · Connected Components?](https://codeforces.com/problemset/problem/920/E) — 2100
- **Difficulty:** 2100
- **Problem:** A graph on $n \le 2\cdot10^5$ vertices is given by the list of $m \le 2\cdot10^5$ pairs that are **not** edges; every
  other pair is an edge. Print the number of connected components and their sizes in non-decreasing order.
- **Thinking from first principles:** The real graph can have $2\cdot10^{10}$ edges, so it cannot be built. BFS only needs, for the
  current vertex $u$, "which unvisited vertices are adjacent to $u$": all of them except $u$'s missing partners. Keep the unvisited
  vertices in an array; for each processed $u$, stamp its missing partners and split the array into "stays" (stamped) and "visited now".
  The amortised cost is $O(n + m)$ (§1.3).

<details><summary>Solution</summary>

CSR of missing pairs, timestamp marks, an unvisited array rebuilt per processed vertex. $O(n + m)$ plus sorting the sizes.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<int> head(n + 1, -1), nxt(2 * m), to(2 * m);
    for (int i = 0; i < m; i++) {
        int a, b; cin >> a >> b;
        to[2 * i] = b; nxt[2 * i] = head[a]; head[a] = 2 * i;
        to[2 * i + 1] = a; nxt[2 * i + 1] = head[b]; head[b] = 2 * i + 1;
    }
    vector<int> rest(n), keep, mark(n + 1, 0), q;
    iota(rest.begin(), rest.end(), 1);
    int stamp = 0;
    vector<int> sizes;
    while (!rest.empty()) {
        q.assign(1, rest.back()); rest.pop_back();
        size_t qh = 0;
        while (qh < q.size()) {
            int u = q[qh++];
            stamp++;
            for (int e = head[u]; e != -1; e = nxt[e]) mark[to[e]] = stamp;
            keep.clear();
            for (int x : rest) (mark[x] == stamp ? keep : q).push_back(x);   // unmarked = real neighbor
            rest.swap(keep);
        }
        sizes.push_back(q.size());
    }
    sort(sizes.begin(), sizes.end());
    cout << sizes.size() << "\n";
    for (size_t i = 0; i < sizes.size(); i++) cout << sizes[i] << " \n"[i + 1 == sizes.size()];
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
    static int readByte() throws IOException { return in.read(); }
    static int nextInt() throws IOException {
        int b = readByte();
        while (b != '-' && (b < '0' || b > '9')) b = readByte();
        boolean neg = b == '-';
        if (neg) b = readByte();
        int r = 0;
        while (b >= '0' && b <= '9') { r = r * 10 + (b - '0'); b = readByte(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt();
        int[] head = new int[n + 1], nxt = new int[2 * m], to = new int[2 * m];
        Arrays.fill(head, -1);
        for (int i = 0; i < m; i++) {
            int a = nextInt(), b = nextInt();
            to[2 * i] = b; nxt[2 * i] = head[a]; head[a] = 2 * i;
            to[2 * i + 1] = a; nxt[2 * i + 1] = head[b]; head[b] = 2 * i + 1;
        }
        int[] rest = new int[n], keep = new int[n], mark = new int[n + 1], q = new int[n], sizes = new int[n];
        int rc = n, comps = 0, stamp = 0;
        for (int i = 0; i < n; i++) rest[i] = i + 1;
        while (rc > 0) {
            int qh = 0, qt = 0;
            q[qt++] = rest[--rc];
            while (qh < qt) {
                int u = q[qh++];
                stamp++;
                for (int e = head[u]; e != -1; e = nxt[e]) mark[to[e]] = stamp;
                int kc = 0;
                for (int i = 0; i < rc; i++) {
                    int x = rest[i];
                    if (mark[x] == stamp) keep[kc++] = x; else q[qt++] = x;
                }
                int[] t = rest; rest = keep; keep = t; rc = kc;
            }
            sizes[comps++] = qt;
        }
        Arrays.sort(sizes, 0, comps);                 // k components need >= k(k-1)/2 missing pairs, so k <= 633: a tiny sort
        StringBuilder sb = new StringBuilder();
        sb.append(comps).append('\n');
        for (int i = 0; i < comps; i++) sb.append(sizes[i]).append(i + 1 == comps ? '\n' : ' ');
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
5 5
1 2
3 4
3 2
4 2
2 5
out:
2
1 4
-->
<!-- test
in:
3 3
1 2
2 3
1 3
out:
3
1 1 1
-->
<!-- test
in:
1 0
out:
1
1
-->
<!-- test
in:
4 0
out:
1
4
-->

## 6. Tricks, pitfalls and things to remember

1. **No recursion on functional graphs.** A single tail can be $2\cdot10^5$ long; recursive DFS overflows Java (and Windows C++) stacks. Use the path-marking loop.
2. **Three states, not two:** "on the current path" vs "finished" is what distinguishes a *new* cycle from joining an old component.
3. **Binary lifting depth:** $\lceil \log_2(k_{\max}+1) \rceil$ levels; $k \le 10^9$ needs 30, $k \le 10^{18}$ needs 60 and `long long` shifts (`1LL << j`).
4. **Memory of lifting tables:** $30 \times 2\cdot10^5$ ints = 24 MB. In Java prefer `int[LOG][n]` (one array per level), not `int[n][LOG]` (cache-unfriendly, more objects).
5. **Distances on a cycle:** use `((pos[b] - pos[a]) % L + L) % L`; Java's `%` keeps the sign of the dividend.
6. **Floyd's first meeting point is not the cycle entry**; you need the second phase (reset one pointer) to get $\mu$.
7. **LCG overflow:** $A x$ with $A, x < 10^{9}$ fits in 64 bits; for $M$ up to $10^{18}$ use `__int128` / `Math.multiplyHigh` or a mulmod.
8. **Complement BFS:** rebuild the unvisited list per processed vertex (or use a linked list); never scan all $n$ vertices per step. Timestamps avoid clearing mark arrays.
9. **Sorting sizes in Java:** `Arrays.sort(int[])` is dual-pivot quicksort with an $O(n^2)$ worst case on adversarial input; for untrusted large arrays shuffle first or sort `long[]`/`Integer[]`.
10. **Segment-tree graph:** leaves must be the original vertices in *both* trees, and the two trees need *opposite* orientations; mixing them makes every range reach everything at zero cost.
11. **Hub nodes need asymmetric weights** (enter with cost $c$, leave with $0$), otherwise passing through the hub costs $2c$.
12. **Planar bound needs a simple graph:** multi-edges and loops break $E \le 3V - 6$.

## 7. Going further (toward 2400–2600+)

- **Values along the walk:** sum/min of the next $k$ vertices with lifting — [CF 702E · Analysis of Pathes in Functional Graph](https://codeforces.com/problemset/problem/702/E) — 2100;
  "maximise $x + f(x) + \dots + f^k(x)$" ([LC 2836](https://leetcode.com/problems/maximize-value-of-function-in-a-ball-passing-game/)).
- **Functional graph + greedy on trees then cycles:** process in-trees by indegree (Kahn on the reversed tree), then decide each cycle
  separately — [CF 1907G · Lights](https://codeforces.com/problemset/problem/1907/G) — 2200, [CF 1872F · Selling a Menagerie](https://codeforces.com/problemset/problem/1872/F) — 1800.
- **Range edges and shortest paths:** [CF 786B · Legacy](https://codeforces.com/problemset/problem/786/B) — 2300 with the segment-tree graph above.
- **Complement graphs elsewhere:** MST of a complete graph with 0/1 weights = components of the complement of the weight-1 edges
  ([CF 1242B · 0-1 MST](https://codeforces.com/problemset/problem/1242/B) — 1900, see [MST](03-minimum-spanning-trees.md)).
- **Cactus DP:** per cycle, a small DP around the ring with the cut vertex fixed — [CF 231E · Cactus](https://codeforces.com/problemset/problem/231/E) — 2100,
  [CF 856D · Masha and Cactus](https://codeforces.com/problemset/problem/856/D) — 2400, [CF 1236F · Alice and the Cactus](https://codeforces.com/problemset/problem/1236/F) — 3000.
- **Pollard's rho** is Floyd/Brent on $x \mapsto x^2 + c \bmod n$ with gcd checks ([number theory](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md)).

## 8. Practice ladder

**≤ 1400**
- [ ] [CF 1020B · Badge](https://codeforces.com/problemset/problem/1020/B) — 1000 — walk until a repeat
- [ ] [AtCoder ABC167 D · Teleporter](https://atcoder.jp/contests/abc167/tasks/abc167_d) — ≈754 (est.) — $k \le 10^{18}$: tail + mod
- [ ] [CF 1249B2 · Books Exchange (hard version)](https://codeforces.com/problemset/problem/1249/B2) — 1300 — permutation cycle lengths
- [ ] [AtCoder ABC179 E · Sequence Sum](https://atcoder.jp/contests/abc179/tasks/abc179_e) — ≈1175 (est.) — periodic sequence sum

**1400–1900**
- [ ] [CSES 1750 · Planets Queries I](https://cses.fi/problemset/task/1750) — binary lifting
- [ ] [CSES 1751 · Planets Cycles](https://cses.fi/problemset/task/1751) — tail + cycle length
- [ ] [AtCoder ABC256 E · Takahashi's Anguish](https://atcoder.jp/contests/abc256/tasks/abc256_e) — ≈1224 (est.) — min edge per cycle
- [ ] [AtCoder ABC296 E · Transition Game](https://atcoder.jp/contests/abc296/tasks/abc296_e) — ≈1285 (est.) — count vertices on cycles
- [ ] [AtCoder ABC357 E · Reachability in Functional Graph](https://atcoder.jp/contests/abc357/tasks/abc357_e) — ≈1295 (est.) — sum of reachable counts
- [ ] [CF 1027D · Mouse Hunt](https://codeforces.com/problemset/problem/1027/D) — 1700
- [ ] [CF 990D · Graph And Its Complement](https://codeforces.com/problemset/problem/990/D) — 1700 — components of $G$ vs $\bar G$
- [ ] [CF 1867D · Cyclic Operations](https://codeforces.com/problemset/problem/1867/D) — 1800 — every cycle must have length $k$
- [ ] [CF 1872F · Selling a Menagerie](https://codeforces.com/problemset/problem/1872/F) — 1800 — topological order on trees, break each cycle at its cheapest vertex

**1900–2400**
- [ ] [CSES 1160 · Planets Queries II](https://cses.fi/problemset/task/1160) — two-case distance query
- [ ] [CF 1242B · 0-1 MST](https://codeforces.com/problemset/problem/1242/B) — 1900 — complement components
- [ ] [CF 702E · Analysis of Pathes in Functional Graph](https://codeforces.com/problemset/problem/702/E) — 2100 — lifting with sum and min
- [ ] [CF 920E · Connected Components?](https://codeforces.com/problemset/problem/920/E) — 2100 — complement BFS
- [ ] [CF 231E · Cactus](https://codeforces.com/problemset/problem/231/E) — 2100 — vertex cactus, count paths through cycles
- [ ] [CF 1907G · Lights](https://codeforces.com/problemset/problem/1907/G) — 2200 — trees first, then cycles
- [ ] [CF 786B · Legacy](https://codeforces.com/problemset/problem/786/B) — 2300 — segment-tree graph + Dijkstra

**2400+**
- [ ] [CF 856D · Masha and Cactus](https://codeforces.com/problemset/problem/856/D) — 2400 — tree DP that builds a cactus
- [ ] [CF 1236F · Alice and the Cactus](https://codeforces.com/problemset/problem/1236/F) — 3000 — components of a cactus $= V - E + (\text{surviving cycles})$, expand the square

## 9. LeetCode / FAANG cross-reference

- [LC 141 · Linked List Cycle](https://leetcode.com/problems/linked-list-cycle/) — Easy and [LC 142 · Linked List Cycle II](https://leetcode.com/problems/linked-list-cycle-ii/) — Medium — Floyd, including the reset-to-head proof for the entry point (a favourite follow-up).
- [LC 287 · Find the Duplicate Number](https://leetcode.com/problems/find-the-duplicate-number/) — Medium — Floyd on $i \mapsto a_i$: the duplicate is the cycle entry.
- [LC 202 · Happy Number](https://leetcode.com/problems/happy-number/) — Easy — implicit functional graph; detect the cycle.
- [LC 565 · Array Nesting](https://leetcode.com/problems/array-nesting/) — Medium — longest permutation cycle.
- [LC 457 · Circular Array Loop](https://leetcode.com/problems/circular-array-loop/) — Medium — functional graph with direction constraints.
- [LC 2360 · Longest Cycle in a Graph](https://leetcode.com/problems/longest-cycle-in-a-graph/) — Hard — out-degree ≤ 1, the three-state walk.
- [LC 2876 · Count Visited Nodes in a Directed Graph](https://leetcode.com/problems/count-visited-nodes-in-a-directed-graph/) — Hard — exactly Planets Cycles.
- [LC 2127 · Maximum Employees to Be Invited to a Meeting](https://leetcode.com/problems/maximum-employees-to-be-invited-to-a-meeting/) — Hard — max(longest cycle, sum over 2-cycles of the two longest tails).
- [LC 2359 · Find Closest Node to Given Two Nodes](https://leetcode.com/problems/find-closest-node-to-given-two-nodes/) — Medium — walk both chains, compare distances.
- [LC 2836 · Maximize Value of Function in a Ball Passing Game](https://leetcode.com/problems/maximize-value-of-function-in-a-ball-passing-game/) — Hard — binary lifting with sums.

Functional graphs are common in interviews through linked-list cycle questions; Floyd's proof is expected at FAANG level.

## 10. Self-check

1. Why does every weakly connected component of a functional graph contain exactly one cycle?
2. In Floyd's algorithm, why does resetting one pointer to $x_0$ and moving both by one step land on the cycle entry?
3. How does Brent's algorithm obtain $\lambda$ directly?
4. Give the formula for the number of distinct vertices visited from $v$, and how to compute it for all $v$ in $O(n)$.
5. How do you answer "steps from $a$ to $b$" when $b$ is on a tail?
6. Why is complement BFS with an unvisited list $O(n + m)$?
7. What are the bounds on edges of a simple planar graph, with and without triangles?
8. How do you add edges "from $v$ to every vertex in $[l, r]$" efficiently?

<details><summary>Answers</summary>

1. A component with $k$ vertices has exactly $k$ arcs; a connected graph with $k$ vertices and $k$ edges has exactly one cycle (as an undirected graph), and since out-degrees are 1 that cycle is directed.
2. The first meeting happens at a step $i$ with $\lambda \mid i$ and $i \ge \mu$. After $\mu$ more steps from $x_0$ and from $x_i$, the pointers are at $x_\mu$ and $x_{i+\mu} = x_\mu$; they cannot meet earlier because one is still on the tail.
3. The tortoise is parked at powers of two; once the window is at least $\lambda$ and the tortoise is on the cycle, the hare meets it after exactly $\lambda$ steps since the last park.
4. $\text{tail}(v) + \lambda(v)$; with path marking: cycle vertices get $\lambda$, tail vertices get successor's value $+1$, filled backwards along each walked path.
5. It is passed exactly once, after $\text{depth}(a) - \text{depth}(b)$ steps, if at all: check $f^{\text{depth}(a)-\text{depth}(b)}(a) = b$ by binary lifting (and same component).
6. Each unvisited vertex is removed once; each vertex kept during the scan of $u$ is charged to the missing edge $(u, x)$, and every vertex is scanned from at most once.
7. $E \le 3V - 6$ for $V \ge 3$; triangle-free (e.g. bipartite) $E \le 2V - 4$.
8. Segment-tree graph: an out-tree with downward 0-edges whose leaves are the vertices; connect $v$ to the $O(\log n)$ nodes covering $[l,r]$. (Use an in-tree with upward edges for the reverse direction.)

</details>
