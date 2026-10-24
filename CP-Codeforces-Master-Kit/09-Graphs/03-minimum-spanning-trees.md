# Minimum Spanning Trees

> **Band:** 🔵 1500 → 🔴 2400+ · **Priority:** 🔥 (Kruskal, cut/cycle properties) · ⚡ (Prim, second-best, bottleneck) · 🧊 (Borůvka, Kruskal reconstruction tree) · **FAANG:** medium · **Prerequisites:** [DSU](../08-Data-Structures/06-dsu-and-variants.md), [sorting](../01-Foundations/05-sorting-and-comparators.md), [LCA and binary lifting](../10-Trees/02-lca-and-binary-lifting.md) (for path-maximum queries)
> **You can say you know this when:** you can prove the cut and cycle properties by an exchange argument, write Kruskal and the $O(n^2)$ Prim without thinking, answer "MST that must contain edge $e$" and "minimum bottleneck between $u$ and $v$" queries, and solve MST on an implicit complete graph (virtual node, complement graph, XOR weights) without listing $n^2$ edges.

## 1. First principles — why this works

**The problem.** Given a connected weighted undirected graph, choose edges connecting all $n$ vertices with minimum total
weight. Such a set never needs a cycle (drop the heaviest edge of a cycle: still connected, not heavier), so it is a spanning
tree with $n-1$ edges. Enumerating spanning trees is hopeless (a complete graph has $n^{n-2}$, Cayley). Every efficient
algorithm rests on two exchange arguments.

**Cut property.** Let $(S, V\setminus S)$ be any cut and $e$ a minimum-weight edge crossing it. Then some MST contains $e$
(and if $e$ is the *unique* lightest crossing edge, every MST contains it).
*Proof.* Take an MST $T$ without $e = \{u,v\}$. The path in $T$ from $u$ to $v$ must cross the cut at some edge $f$. Then
$T - f + e$ is a spanning tree with weight $w(T) - w(f) + w(e) \le w(T)$. ∎

**Cycle property.** Let $C$ be any cycle and $e$ an edge of $C$ that is *strictly* heavier than every other edge of $C$. Then
no MST contains $e$.
*Proof.* If an MST $T$ contained $e$, removing $e$ splits $T$ into two parts; the rest of $C$ reconnects them through some edge
$f$ lighter than $e$; $T - e + f$ is lighter. ∎

**Generic greedy.** Keep a forest $F$ contained in some MST. Pick any cut that no edge of $F$ crosses and add its lightest
crossing edge; by the cut property (applied with $T \supseteq F$ and the exchange keeping $F$) the new forest is still inside
some MST. Kruskal and Prim are two ways to choose the cut.

**Kruskal.** Process edges in increasing weight; add an edge iff its endpoints are in different components of $F$ (checked
with a [DSU](../08-Data-Structures/06-dsu-and-variants.md)). The added edge $\{u,v\}$ is the lightest edge crossing the cut
"component of $u$ versus everything else" — every lighter edge crossing that cut would have been added already. Cost:
$O(m\log m)$ for sorting plus $O(m\,\alpha(n))$ for the DSU. If the graph is disconnected, Kruskal returns a minimum spanning
*forest*; check that exactly $n-1$ edges were taken.

**Prim.** Grow a single tree from any vertex; repeatedly add the lightest edge leaving the tree (cut = tree versus rest).
Keep `key[v]` = lightest edge from the tree to $v$. The **dense version** scans all $n$ keys to find the minimum: $O(n^2)$
with no sorting and no edge list — the right choice on complete graphs given by a formula ($n \le 5000$). The heap version is
$O(m\log n)$, like Dijkstra with `key[v]` instead of `dist[v]`.

**Borůvka (🧊).** In each round, every component picks its lightest outgoing edge and all of them are added at once (ties
broken by edge index so no cycle forms). Each round at least halves the number of components: $O(\log n)$ rounds,
$O(m\log n)$ total. Its value is structural: when "the lightest edge from this component to anything else" can be found by a
data structure (a trie for XOR weights, a segment tree for interval graphs), Borůvka gives an MST of an implicit complete
graph in $O(n \log n \cdot \text{query})$.

**What all MSTs share.** For every threshold $w$, the connected components formed by edges of weight $< w$ are the same in
every MST's view: Kruskal processes the edges of weight $< w$ first, and whichever ties it chooses, the resulting partition is
"components of the graph restricted to weights $< w$". Consequences: all MSTs have the same multiset of weights; an edge of
weight $w$ is in **some** MST iff its endpoints are in different components of the "$<w$" graph; it is in **every** MST iff
additionally it is a bridge among the weight-$w$ edges between those components (CF 160D); making the MST unique
(CF 1108F) means fixing ties within each weight class.

**Second-best MST and "MST containing edge $e$".** Forcing a non-tree edge $e=\{u,v\}$ into the tree creates exactly one cycle
(the tree path $u \leadsto v$ plus $e$); the best repair removes the heaviest edge on that path:
$$\text{MST}(e) = w(T) - \max_{f \in \text{path}_T(u,v)} w(f) + w(e).$$
The second-best MST is $\min_{e\notin T} \text{MST}(e)$ (for *strictly* second-best, when the path maximum equals $w(e)$ use
the largest path edge strictly below $w(e)$). Path maxima come from binary lifting on the MST: $O((n+m)\log n)$.

**Minimum bottleneck paths.** Among all $u$–$v$ paths, minimize the largest edge. The MST path between $u$ and $v$ is optimal
for **every** pair simultaneously: the answer is the weight $w^*$ at which Kruskal first joins $u$ and $v$ — any path with all
edges $< w^*$ would have joined them earlier. So offline queries "is there a path using only edges $\le x$?" are: sort queries
by $x$, add edges with DSU (LC 1697). Online, build the **Kruskal reconstruction tree (🔴)**: whenever Kruskal merges two
components, create a new node with that edge's weight whose children are the two components' roots. It has $2n-1$ nodes, weights
increase towards the root, the bottleneck between $u$ and $v$ is the weight of $\operatorname{LCA}(u,v)$, and "all vertices
reachable from $v$ using edges $\le x$" is the leaf set of the highest ancestor of $v$ with weight $\le x$ — a subtree, hence a
contiguous range in DFS order (CF 1416D, CF 1706E).

**MST on implicit complete graphs.** $n = 2\cdot10^5$ vertices with a weight formula means $\sim2\cdot10^{10}$ edges; the
work is proving that a small candidate set suffices.
- *Virtual vertex:* "build a station at $i$ for $c_i$ or connect to a powered city" — add vertex 0 with edges $(0,i)$ of weight
  $c_i$; the MST of $n+1$ vertices is the answer (CF 1245D).
- *Star dominance:* if $w(i,j) = a_i + a_j$, every edge $(i,j)$ can be replaced by $(i, \arg\min a)$ and $(j, \arg\min a)$
  arguments: only the star from the minimum vertex plus special offers matter (CF 1095F).
- *0/1 weights:* the MST weight is (number of components of the weight-0 graph) $-1$; if the weight-0 graph is the
  **complement** of a sparse graph, count its components with complement BFS (CF 1242B).
- *XOR weights:* group numbers by their highest differing bit (a binary trie). Edges inside a trie child cost $< 2^b$, edges
  across cost $\ge 2^b$, so by the cut property Kruskal connects each child internally first and then needs exactly **one**
  crossing edge: the minimum XOR pair between the two children (CF 888G).
- *Manhattan distance (🧊):* only $4n$ candidate edges (nearest point in each of 8 octants, by symmetry 4 sweeps).

**Directed version (🧊).** The minimum spanning *arborescence* (all vertices reachable from a root along directed edges) is
**not** solved by greedy-by-weight; it needs Chu–Liu/Edmonds ($O(nm)$, or $O(m\log n)$ with mergeable heaps).

## 2. Formulas, definitions and identities

- **Spanning tree:** $n-1$ edges, connected, acyclic (any two imply the third). Number of spanning trees of $K_n$: $n^{n-2}$
  (Cayley); of a general graph: any cofactor of the Laplacian (Kirchhoff,
  [matrix-tree theorem](../15-Advanced-Math/06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md)).
- **Cut property:** lightest crossing edge ∈ some MST. **Cycle property:** strictly heaviest edge on a cycle ∉ any MST.
- **Uniqueness:** distinct weights ⇒ unique MST. In general all MSTs have the same sorted weight sequence.
- **Edge classification (CF 160D):** with components $\mathcal{C}_{<w}$ of the graph of edges lighter than $w$,
  edge $e$ of weight $w$ is in *no* MST if both ends are in the same component of $\mathcal{C}_{<w}$; in *every* MST if it is a
  bridge of the multigraph (on contracted components) formed by the weight-$w$ edges; otherwise in *some*.
- **Forced edge:** $\text{MST}(e) = w(T) - \text{pathmax}_T(u,v) + w(e)$; second-best $= \min_{e \notin T}\text{MST}(e)$.
- **Bottleneck:** $\min_{P: u\leadsto v} \max_{f\in P} w(f) = \text{pathmax}_T(u, v) = w(\operatorname{LCA}_{\text{KRT}}(u,v))$.
- **XOR-MST recurrence:** for a trie node at bit $b$ with children $L, R$ (both non-empty),
  $\text{cost} = \text{cost}(L) + \text{cost}(R) + 2^b + \min_{x\in L, y\in R} (x \oplus y \bmod 2^b)$.
- **Maximum spanning tree:** run Kruskal in decreasing order (or negate weights); all properties flip.
- **Complexities:** Kruskal $O(m\log m)$; Prim dense $O(n^2)$; Prim heap $O(m\log n)$; Borůvka $O(m\log n)$; path maxima via
  binary lifting $O((n+q)\log n)$; Kruskal reconstruction tree build $O(m\log m)$, queries $O(\log n)$.

## 3. Implementation (C++ and Java)

### 3.1 DSU + Kruskal

```cpp
struct DSU {
    vector<int> p, sz;
    DSU(int n) : p(n), sz(n, 1) { iota(p.begin(), p.end(), 0); }
    int find(int x) { while (p[x] != x) x = p[x] = p[p[x]]; return x; }   // path halving
    bool unite(int a, int b) {
        a = find(a); b = find(b);
        if (a == b) return false;
        if (sz[a] < sz[b]) swap(a, b);
        p[b] = a; sz[a] += sz[b];
        return true;
    }
};

// edges: (w, u, v), vertices 0..n-1.  Returns the MST weight, or -1 if the graph is disconnected.
ll kruskal(int n, vector<array<ll, 3>> edges, vector<int>* chosen = nullptr) {
    vector<int> order(edges.size());
    iota(order.begin(), order.end(), 0);
    sort(order.begin(), order.end(), [&](int a, int b) { return edges[a][0] < edges[b][0]; });
    DSU d(n);
    ll total = 0; int taken = 0;
    for (int i : order)
        if (d.unite(edges[i][1], edges[i][2])) {
            total += edges[i][0]; taken++;
            if (chosen) chosen->push_back(i);
        }
    return taken == n - 1 ? total : -1;
}
```

```java
static final class DSU {
    final int[] p, sz;
    DSU(int n) { p = new int[n]; sz = new int[n]; for (int i = 0; i < n; i++) { p[i] = i; sz[i] = 1; } }
    int find(int x) { while (p[x] != x) { p[x] = p[p[x]]; x = p[x]; } return x; }
    boolean unite(int a, int b) {
        a = find(a); b = find(b);
        if (a == b) return false;
        if (sz[a] < sz[b]) { int t = a; a = b; b = t; }
        p[b] = a; sz[a] += sz[b];
        return true;
    }
}

// Sort edge indices by weight without boxing: pack (weight, index) into one long (weights < 2^31).
static long kruskal(int n, int[] eu, int[] ev, int[] ew) {
    int m = eu.length;
    long[] key = new long[m];
    for (int i = 0; i < m; i++) key[i] = ((long) ew[i] << 32) | i;
    Arrays.sort(key);                                  // primitives: no boxing (shuffle first on JDK <= 13, see pitfall 3)
    DSU d = new DSU(n);
    long total = 0; int taken = 0;
    for (long k : key) {
        int i = (int) k;                               // low 32 bits = index
        if (d.unite(eu[i], ev[i])) { total += ew[i]; taken++; }
    }
    return taken == n - 1 ? total : -1;
}
```

### 3.2 Prim, dense $O(n^2)$ (complete graphs given by a formula)

```cpp
// w(i, j) is any symmetric cost function; returns the MST weight of the complete graph on n vertices.
ll primDense(int n, const function<ll(int, int)>& w) {
    const ll INF = LLONG_MAX;
    vector<ll> key(n, INF);
    vector<char> in(n, 0);
    key[0] = 0;
    ll total = 0;
    for (int it = 0; it < n; it++) {
        int u = -1;
        for (int v = 0; v < n; v++) if (!in[v] && (u < 0 || key[v] < key[u])) u = v;
        in[u] = 1; total += key[u];
        for (int v = 0; v < n; v++) if (!in[v]) key[v] = min(key[v], w(u, v));
    }
    return total;
}
```

```java
static long primDense(int n, java.util.function.LongBinaryOperator w) {   // w.applyAsLong(i, j)
    long[] key = new long[n];
    boolean[] in = new boolean[n];
    Arrays.fill(key, Long.MAX_VALUE);
    key[0] = 0;
    long total = 0;
    for (int it = 0; it < n; it++) {
        int u = -1;
        for (int v = 0; v < n; v++) if (!in[v] && (u < 0 || key[v] < key[u])) u = v;
        in[u] = true; total += key[u];
        for (int v = 0; v < n; v++) if (!in[v]) key[v] = Math.min(key[v], w.applyAsLong(u, v));
    }
    return total;
}
```

### 3.3 Prim with a heap (sparse graphs)

```cpp
// g[u] = {(v, w)}; connected graph assumed (returns -1 otherwise).
ll primHeap(const vector<vector<pair<int, ll>>>& g) {
    int n = g.size(), cnt = 0;
    vector<char> in(n, 0);
    priority_queue<pair<ll, int>, vector<pair<ll, int>>, greater<>> pq;
    pq.push({0, 0});
    ll total = 0;
    while (!pq.empty()) {
        auto [w, u] = pq.top(); pq.pop();
        if (in[u]) continue;                  // lazy deletion: an older, heavier entry
        in[u] = 1; total += w; cnt++;
        for (auto [v, c] : g[u]) if (!in[v]) pq.push({c, v});
    }
    return cnt == n ? total : -1;
}
```

```java
// CSR graph (start, to, wt).  Heap entries packed as weight * 2^20 + vertex (weights < 2^43, n < 2^20).
static long primHeap(int n, int[] start, int[] to, long[] wt) {
    boolean[] in = new boolean[n];
    PriorityQueue<Long> pq = new PriorityQueue<>();
    pq.add(0L);
    long total = 0; int cnt = 0;
    while (!pq.isEmpty()) {
        long top = pq.poll();
        int u = (int) (top & ((1 << 20) - 1));
        if (in[u]) continue;
        in[u] = true; total += top >>> 20; cnt++;
        for (int e = start[u]; e < start[u + 1]; e++) if (!in[to[e]]) pq.add((wt[e] << 20) | to[e]);
    }
    return cnt == n ? total : -1;
}
```

### 3.4 Borůvka (🧊)

```cpp
// edges (u, v, w); ties broken by edge index so that the chosen edges never form a cycle.
ll boruvka(int n, const vector<array<ll, 3>>& e) {
    vector<int> p(n);
    iota(p.begin(), p.end(), 0);
    function<int(int)> find = [&](int x) { while (p[x] != x) x = p[x] = p[p[x]]; return x; };
    int comps = n; ll total = 0;
    while (comps > 1) {
        vector<int> best(n, -1);                                // best edge index per component root
        auto better = [&](int i, int j) { return j < 0 || e[i][2] < e[j][2] || (e[i][2] == e[j][2] && i < j); };
        for (int i = 0; i < (int)e.size(); i++) {
            int a = find(e[i][0]), b = find(e[i][1]);
            if (a == b) continue;
            if (better(i, best[a])) best[a] = i;
            if (better(i, best[b])) best[b] = i;
        }
        bool progress = false;
        for (int r = 0; r < n; r++) {
            if (best[r] < 0) continue;
            int a = find(e[best[r]][0]), b = find(e[best[r]][1]);
            if (a == b) continue;                               // already merged this round via the same edge
            p[a] = b; total += e[best[r]][2]; comps--; progress = true;
        }
        if (!progress) return -1;                               // disconnected
    }
    return total;
}
```

```java
static int[] bp;
static int bfind(int x) { while (bp[x] != x) { bp[x] = bp[bp[x]]; x = bp[x]; } return x; }

static long boruvka(int n, int[] eu, int[] ev, long[] ew) {
    bp = new int[n];
    for (int i = 0; i < n; i++) bp[i] = i;
    int m = eu.length, comps = n;
    long total = 0;
    while (comps > 1) {
        int[] best = new int[n];
        Arrays.fill(best, -1);
        for (int i = 0; i < m; i++) {
            int a = bfind(eu[i]), b = bfind(ev[i]);
            if (a == b) continue;
            if (best[a] < 0 || ew[i] < ew[best[a]] || (ew[i] == ew[best[a]] && i < best[a])) best[a] = i;
            if (best[b] < 0 || ew[i] < ew[best[b]] || (ew[i] == ew[best[b]] && i < best[b])) best[b] = i;
        }
        boolean progress = false;
        for (int r = 0; r < n; r++) {
            if (best[r] < 0) continue;
            int a = bfind(eu[best[r]]), b = bfind(ev[best[r]]);
            if (a == b) continue;
            bp[a] = b; total += ew[best[r]]; comps--; progress = true;
        }
        if (!progress) return -1;
    }
    return total;
}
```

### 3.5 Kruskal reconstruction tree (🔴)

```cpp
// Leaves 0..n-1 are the vertices; internal node n+k is the k-th successful union, weight[n+k] = that edge's weight.
// Bottleneck(u, v) = weight[LCA(u, v)]; nodes reachable from v with edges <= x = leaves under the highest ancestor of v with weight <= x.
struct KRT {
    vector<int> parent;
    vector<ll> weight;
    vector<array<int, 2>> child;
    int root = -1;
    KRT(int n, vector<array<ll, 3>> edges) : parent(2 * n - 1, -1), weight(2 * n - 1, 0), child(2 * n - 1, {-1, -1}) {
        sort(edges.begin(), edges.end());                      // (w, u, v)
        vector<int> dsu(2 * n - 1);
        iota(dsu.begin(), dsu.end(), 0);
        auto find = [&](int x) { while (dsu[x] != x) x = dsu[x] = dsu[dsu[x]]; return x; };
        int next = n;
        for (auto& [w, u, v] : edges) {
            int a = find(u), b = find(v);
            if (a == b) continue;
            weight[next] = w; child[next] = {a, b};
            parent[a] = parent[b] = next;
            dsu[a] = dsu[b] = next;                            // the new node becomes the component's representative
            next++;
        }
        root = next - 1;                                        // valid if the graph is connected
    }
};
```

```java
static final class KRT {
    final int[] parent, left, right;
    final long[] weight;
    int root = -1;
    KRT(int n, int[] eu, int[] ev, long[] ew) {
        int N = 2 * n - 1, m = eu.length;
        parent = new int[N]; left = new int[N]; right = new int[N]; weight = new long[N];
        Arrays.fill(parent, -1); Arrays.fill(left, -1); Arrays.fill(right, -1);
        Integer[] order = new Integer[m];
        for (int i = 0; i < m; i++) order[i] = i;
        Arrays.sort(order, (a, b) -> Long.compare(ew[a], ew[b]));
        int[] dsu = new int[N];
        for (int i = 0; i < N; i++) dsu[i] = i;
        int next = n;
        for (int i : order) {
            int a = find(dsu, eu[i]), b = find(dsu, ev[i]);
            if (a == b) continue;
            weight[next] = ew[i]; left[next] = a; right[next] = b;
            parent[a] = parent[b] = next;
            dsu[a] = dsu[b] = next;
            next++;
        }
        root = next - 1;
    }
    static int find(int[] d, int x) { while (d[x] != x) { d[x] = d[d[x]]; x = d[x]; } return x; }
}
```

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "connect all", "minimum total cost of roads/cables", "every city reachable" | MST (Kruskal) |
| "build a station at $i$ for $c_i$ **or** connect it" | virtual vertex 0 with edges of weight $c_i$ |
| complete graph, weight given by a formula, $n \le 5000$ | dense Prim $O(n^2)$ |
| complete graph, $n \ge 10^5$, weight = XOR / sum / min / Manhattan | find a small candidate edge set (trie, star, octants) or Borůvka |
| "minimize the maximum edge on the path", "all edges $\le x$" queries | MST path / DSU over sorted edges / Kruskal reconstruction tree |
| "spanning tree that must include edge $e$", "second-best MST" | MST + path maximum via binary lifting |
| "is edge $e$ in all / some / no MST", "make the MST unique" | process weight classes together (cut/cycle properties) |
| "remove maximum total weight while staying connected" | total − MST |
| "keep both Alice and Bob connected" (two colors of edges) | Kruskal with shared edges first (LC 1579) |
| directed "arborescence" | not Kruskal — Chu–Liu/Edmonds (🧊) |

Often confused with: shortest-path trees (an MST does not minimize distances from a root), Steiner trees (connect only a subset
— NP-hard; bitmask DP for small terminal sets).

## 5. Worked examples (graded)

### Example 1 — Road Reparation  ·  ★ ≈1400

- **Source:** [CSES 1675 · Road Reparation](https://cses.fi/problemset/task/1675)
- **Difficulty:** ≈1400 (est.)
- **Problem:** $n \le 10^5$ cities, $m \le 2\cdot10^5$ broken two-way roads with repair costs $\le 10^9$. Repair roads so that
  every pair of cities is connected, at minimum total cost; print it, or `IMPOSSIBLE`.
- **Thinking from first principles:** "connect everything at minimum cost" is the MST definition. Kruskal: sort, DSU. The
  only decisions are 64-bit totals and the disconnected case (fewer than $n-1$ successful unions).

<details><summary>Solution</summary>

Kruskal, $O(m\log m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<array<int, 3>> e(m);
    for (auto& [w, u, v] : e) cin >> u >> v >> w;
    sort(e.begin(), e.end());
    vector<int> p(n + 1), sz(n + 1, 1);
    iota(p.begin(), p.end(), 0);
    auto find = [&](int x) { while (p[x] != x) x = p[x] = p[p[x]]; return x; };
    ll total = 0; int taken = 0;
    for (auto& [w, u, v] : e) {
        int a = find(u), b = find(v);
        if (a == b) continue;
        if (sz[a] < sz[b]) swap(a, b);
        p[b] = a; sz[a] += sz[b];
        total += w; taken++;
    }
    if (taken == n - 1) cout << total << "\n";
    else cout << "IMPOSSIBLE\n";
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
    static int[] p, sz;
    static int find(int x) { while (p[x] != x) { p[x] = p[p[x]]; x = p[x]; } return x; }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt();
        int[] eu = new int[m], ev = new int[m], ew = new int[m];
        long[] key = new long[m];
        for (int i = 0; i < m; i++) {
            eu[i] = nextInt(); ev[i] = nextInt(); ew[i] = nextInt();
            key[i] = ((long) ew[i] << 32) | i;                  // sort primitives, not objects
        }
        Arrays.sort(key);
        p = new int[n + 1]; sz = new int[n + 1];
        for (int i = 0; i <= n; i++) { p[i] = i; sz[i] = 1; }
        long total = 0; int taken = 0;
        for (long k : key) {
            int i = (int) k, a = find(eu[i]), b = find(ev[i]);
            if (a == b) continue;
            if (sz[a] < sz[b]) { int t = a; a = b; b = t; }
            p[b] = a; sz[a] += sz[b];
            total += ew[i]; taken++;
        }
        System.out.println(taken == n - 1 ? String.valueOf(total) : "IMPOSSIBLE");
    }
}
```

</details>

<!-- test
in:
5 6
1 2 3
2 3 5
2 4 2
3 4 8
5 1 7
5 4 4
out:
14
-->
<!-- test
in:
4 2
1 2 1
3 4 1
out:
IMPOSSIBLE
-->
<!-- test
in:
1 0
out:
0
-->
<!-- test
in:
3 3
1 2 1000000000
2 3 1000000000
1 3 1000000000
out:
2000000000
-->

### Example 2 — Power grid (virtual vertex + dense Prim)  ·  ★ 1900

- **Source:** [CF 1245D · Shichikuji and Power Grid](https://codeforces.com/problemset/problem/1245/D) — 1900 (we print only the minimum cost; the original also asks for the construction).
- **Difficulty:** 1900
- **Problem:** $n \le 2000$ cities at integer points $(x_i, y_i)$ ($1 \le x, y \le 10^6$). Building a power station in city
  $i$ costs $c_i$; a wire between $i$ and $j$ costs $(k_i + k_j)\cdot(|x_i-x_j| + |y_i-y_j|)$ ($c, k \le 10^9$). A city has power
  if it has a station or is wired to a city with power. Minimum total cost to power all cities.
- **Thinking from first principles:** two kinds of decisions (stations and wires) look different, but a station is just a wire
  to an imaginary "power plant" vertex 0 that costs $c_i$. Then "every city has power" = "every city is connected to vertex 0",
  and the cheapest such edge set is an MST of $n+1$ vertices. The graph is complete ($\approx 2\cdot10^6$ edges): Kruskal would
  sort $2\cdot10^6$ edges (fine in C++, heavy in Java); dense Prim needs no edge list at all and runs $O(n^2) = 4\cdot10^6$.
  Magnitudes: one wire can cost $2\cdot10^9 \cdot 4\cdot10^6 = 8\cdot10^{15}$ — fits in 64 bits; the answer is at most
  $\sum c_i \le 2\cdot10^{12}$.

<details><summary>Solution</summary>

Prim from vertex 0: initially `key[i] = c_i`; after adding city $u$, `key[v] = min(key[v], (k_u+k_v)·dist(u,v))`. $O(n^2)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<ll> x(n), y(n), c(n), k(n);
    for (int i = 0; i < n; i++) cin >> x[i] >> y[i];
    for (auto& v : c) cin >> v;
    for (auto& v : k) cin >> v;
    vector<ll> key = c;                  // edge from the virtual power plant
    vector<char> in(n, 0);
    ll total = 0;
    for (int it = 0; it < n; it++) {
        int u = -1;
        for (int v = 0; v < n; v++) if (!in[v] && (u < 0 || key[v] < key[u])) u = v;
        in[u] = 1; total += key[u];
        for (int v = 0; v < n; v++)
            if (!in[v]) key[v] = min(key[v], (k[u] + k[v]) * (llabs(x[u] - x[v]) + llabs(y[u] - y[v])));
    }
    cout << total << "\n";
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
        int n = (int) nextLong();
        long[] x = new long[n], y = new long[n], c = new long[n], k = new long[n];
        for (int i = 0; i < n; i++) { x[i] = nextLong(); y[i] = nextLong(); }
        for (int i = 0; i < n; i++) c[i] = nextLong();
        for (int i = 0; i < n; i++) k[i] = nextLong();
        long[] key = c.clone();
        boolean[] done = new boolean[n];
        long total = 0;
        for (int it = 0; it < n; it++) {
            int u = -1;
            for (int v = 0; v < n; v++) if (!done[v] && (u < 0 || key[v] < key[u])) u = v;
            done[u] = true; total += key[u];
            for (int v = 0; v < n; v++)
                if (!done[v]) key[v] = Math.min(key[v], (k[u] + k[v]) * (Math.abs(x[u] - x[v]) + Math.abs(y[u] - y[v])));
        }
        System.out.println(total);
    }
}
```

</details>

<!-- test
in:
3
1 1
2 2
3 3
3 2 3
1 1 1
out:
8
-->
<!-- test
in:
3
1 1
1 5
5 5
5 5 5
10 10 10
out:
15
-->
<!-- test
in:
1
7 7
1000000000
1000000000
out:
1000000000
-->

### Example 3 — Minimum spanning tree for each edge  ·  ★ 2100

- **Source:** [CF 609E · Minimum spanning tree for each edge](https://codeforces.com/problemset/problem/609/E) — 2100
- **Difficulty:** 2100
- **Problem:** A connected undirected graph without loops or multi-edges ($n, m \le 2\cdot10^5$, $w \le 10^9$). For every edge,
  print the minimum weight of a spanning tree that contains it.
- **Thinking from first principles:** recomputing an MST per edge is $O(m^2)$. Fix one MST $T$. For a tree edge the answer is
  $w(T)$. For a non-tree edge $\{u,v\}$, any spanning tree containing it can be compared with $T$ by exchanges: add $e$ to $T$,
  which closes the cycle $e + \text{path}_T(u,v)$, and drop the heaviest path edge — the cycle property shows nothing better is
  possible. So we need path maxima on a static tree: binary lifting stores, for each vertex and $2^j$, the ancestor and the
  maximum edge weight on the way up. (Tree edges also satisfy the formula: their path maximum is themselves.)

<details><summary>Solution</summary>

Kruskal; root the MST at 1 with an iterative BFS (no recursion — depth can be $2\cdot10^5$); build `up[j][v]` and
`mx[j][v]`; answer `W - pathmax(u, v) + w`. $O((n+m)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<int> eu(m), ev(m), ew(m), order(m);
    for (int i = 0; i < m; i++) cin >> eu[i] >> ev[i] >> ew[i];
    iota(order.begin(), order.end(), 0);
    sort(order.begin(), order.end(), [&](int a, int b) { return ew[a] < ew[b]; });
    vector<int> p(n + 1);
    iota(p.begin(), p.end(), 0);
    auto find = [&](int x) { while (p[x] != x) x = p[x] = p[p[x]]; return x; };
    vector<vector<pair<int, int>>> tree(n + 1);
    ll W = 0;
    for (int i : order) {
        int a = find(eu[i]), b = find(ev[i]);
        if (a == b) continue;
        p[a] = b; W += ew[i];
        tree[eu[i]].push_back({ev[i], ew[i]});
        tree[ev[i]].push_back({eu[i], ew[i]});
    }
    int LOG = 1;
    while ((1 << LOG) <= n) LOG++;
    vector<vector<int>> up(LOG, vector<int>(n + 1, 1)), mx(LOG, vector<int>(n + 1, 0));
    vector<int> depth(n + 1, -1), q = {1};
    depth[1] = 0;
    for (size_t h = 0; h < q.size(); h++) {
        int u = q[h];
        for (auto [v, w] : tree[u])
            if (depth[v] < 0) { depth[v] = depth[u] + 1; up[0][v] = u; mx[0][v] = w; q.push_back(v); }
    }
    for (int j = 1; j < LOG; j++)
        for (int v = 1; v <= n; v++) {
            up[j][v] = up[j - 1][up[j - 1][v]];
            mx[j][v] = max(mx[j - 1][v], mx[j - 1][up[j - 1][v]]);
        }
    auto pathMax = [&](int a, int b) {
        int res = 0;
        if (depth[a] < depth[b]) swap(a, b);
        for (int j = LOG - 1; j >= 0; j--)
            if (depth[a] - (1 << j) >= depth[b]) { res = max(res, mx[j][a]); a = up[j][a]; }
        if (a == b) return res;
        for (int j = LOG - 1; j >= 0; j--)
            if (up[j][a] != up[j][b]) { res = max({res, mx[j][a], mx[j][b]}); a = up[j][a]; b = up[j][b]; }
        return max({res, mx[0][a], mx[0][b]});
    };
    for (int i = 0; i < m; i++) cout << W - pathMax(eu[i], ev[i]) + ew[i] << "\n";
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
    static int[] p;
    static int find(int x) { while (p[x] != x) { p[x] = p[p[x]]; x = p[x]; } return x; }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt();
        int[] eu = new int[m], ev = new int[m], ew = new int[m];
        long[] key = new long[m];
        for (int i = 0; i < m; i++) {
            eu[i] = nextInt(); ev[i] = nextInt(); ew[i] = nextInt();
            key[i] = ((long) ew[i] << 32) | i;
        }
        Arrays.sort(key);
        p = new int[n + 1];
        for (int i = 0; i <= n; i++) p[i] = i;
        int[] tu = new int[n - 1], tv = new int[n - 1], tw = new int[n - 1], start = new int[n + 2];
        int t = 0;
        long W = 0;
        for (long k : key) {
            int i = (int) k, a = find(eu[i]), b = find(ev[i]);
            if (a == b) continue;
            p[a] = b; W += ew[i];
            tu[t] = eu[i]; tv[t] = ev[i]; tw[t] = ew[i]; t++;
            start[eu[i] + 1]++; start[ev[i] + 1]++;
        }
        for (int i = 0; i <= n; i++) start[i + 1] += start[i];
        int[] to = new int[2 * (n - 1)], wt = new int[2 * (n - 1)], pos = Arrays.copyOf(start, n + 1);
        for (int i = 0; i < n - 1; i++) {
            int a = pos[tu[i]]++; to[a] = tv[i]; wt[a] = tw[i];
            int b = pos[tv[i]]++; to[b] = tu[i]; wt[b] = tw[i];
        }
        int LOG = 1;
        while ((1 << LOG) <= n) LOG++;
        int[][] up = new int[LOG][n + 1], mx = new int[LOG][n + 1];
        int[] depth = new int[n + 1], q = new int[n];
        Arrays.fill(depth, -1);
        Arrays.fill(up[0], 1);
        int head = 0, tail = 0;
        q[tail++] = 1; depth[1] = 0;
        while (head < tail) {
            int u = q[head++];
            for (int e = start[u]; e < start[u + 1]; e++) {
                int v = to[e];
                if (depth[v] < 0) { depth[v] = depth[u] + 1; up[0][v] = u; mx[0][v] = wt[e]; q[tail++] = v; }
            }
        }
        for (int j = 1; j < LOG; j++)
            for (int v = 1; v <= n; v++) {
                up[j][v] = up[j - 1][up[j - 1][v]];
                mx[j][v] = Math.max(mx[j - 1][v], mx[j - 1][up[j - 1][v]]);
            }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < m; i++) {
            int a = eu[i], b = ev[i], res = 0;
            if (depth[a] < depth[b]) { int tmp = a; a = b; b = tmp; }
            for (int j = LOG - 1; j >= 0; j--)
                if (depth[a] - (1 << j) >= depth[b]) { res = Math.max(res, mx[j][a]); a = up[j][a]; }
            if (a != b) {
                for (int j = LOG - 1; j >= 0; j--)
                    if (up[j][a] != up[j][b]) {
                        res = Math.max(res, Math.max(mx[j][a], mx[j][b]));
                        a = up[j][a]; b = up[j][b];
                    }
                res = Math.max(res, Math.max(mx[0][a], mx[0][b]));
            }
            sb.append(W - res + ew[i]).append('\n');
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
4 5
1 2 1
2 3 2
3 4 3
1 3 4
2 4 10
out:
6
6
6
8
13
-->
<!-- test
in:
2 1
1 2 5
out:
5
-->
<!-- test
in:
3 3
1 2 1000000000
2 3 1000000000
3 1 1000000000
out:
2000000000
2000000000
2000000000
-->

### Example 4 — 0-1 MST (complement graph)  ·  ★ 1900

- **Source:** [CF 1242B · 0-1 MST](https://codeforces.com/problemset/problem/1242/B) — 1900
- **Difficulty:** 1900
- **Problem:** A complete graph on $n \le 10^5$ vertices; $m \le 10^5$ listed edges have weight 1, all others weight 0. Find
  the MST weight.
- **Thinking from first principles:** Kruskal takes all weight-0 edges it can, then needs one weight-1 edge per remaining
  merge, so the answer is $(\#\text{components of the weight-0 graph}) - 1$. The weight-0 graph is the **complement** of the
  given sparse graph — up to $5\cdot10^9$ edges. BFS on the complement without building it: keep the set of unvisited vertices;
  when expanding $u$, every unvisited vertex *not* adjacent to $u$ in the given graph is a complement neighbor and leaves the
  set; the ones that are adjacent stay. Each check either removes a vertex ($\le n$ times overall) or is paid by a given edge
  incident to $u$ ($\le 2m$ overall): $O(n+m)$.

<details><summary>Solution</summary>

Complement BFS with a vector of unvisited vertices and a "marked by $u$" stamp array. Answer = components − 1.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<vector<int>> g(n + 1);
    for (int i = 0; i < m; i++) {
        int a, b;
        cin >> a >> b;
        g[a].push_back(b);
        g[b].push_back(a);
    }
    vector<int> rest(n), mark(n + 1, 0), q;
    iota(rest.begin(), rest.end(), 1);
    int comps = 0;
    while (!rest.empty()) {
        comps++;
        q.assign(1, rest.back());
        rest.pop_back();
        for (size_t h = 0; h < q.size(); h++) {
            int u = q[h];
            for (int v : g[u]) mark[v] = u;           // weight-1 neighbors of u
            vector<int> keep;
            for (int v : rest) {
                if (mark[v] == u) keep.push_back(v);  // not a complement neighbor: stays unvisited
                else q.push_back(v);                  // complement edge u-v: visit v
            }
            rest.swap(keep);
        }
    }
    cout << comps - 1 << "\n";
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

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt();
        int[] eu = new int[m], ev = new int[m], start = new int[n + 2];
        for (int i = 0; i < m; i++) { eu[i] = nextInt(); ev[i] = nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int i = 0; i <= n; i++) start[i + 1] += start[i];
        int[] adj = new int[2 * m], pos = Arrays.copyOf(start, n + 1);
        for (int i = 0; i < m; i++) { adj[pos[eu[i]]++] = ev[i]; adj[pos[ev[i]]++] = eu[i]; }
        int[] rest = new int[n], keep = new int[n], mark = new int[n + 1], q = new int[n];
        int restSize = n;
        for (int i = 0; i < n; i++) rest[i] = i + 1;
        int comps = 0;
        while (restSize > 0) {
            comps++;
            int head = 0, tail = 0;
            q[tail++] = rest[--restSize];
            while (head < tail) {
                int u = q[head++];
                for (int e = start[u]; e < start[u + 1]; e++) mark[adj[e]] = u;
                int k = 0;
                for (int i = 0; i < restSize; i++) {
                    int v = rest[i];
                    if (mark[v] == u) keep[k++] = v; else q[tail++] = v;
                }
                int[] t = rest; rest = keep; keep = t;
                restSize = k;
            }
        }
        System.out.println(comps - 1);
    }
}
```

</details>

<!-- test
in:
5 5
1 2
1 3
1 4
1 5
2 3
out:
1
-->
<!-- test
in:
3 0
out:
0
-->
<!-- test
in:
1 0
out:
0
-->
<!-- test
in:
3 3
1 2
2 3
1 3
out:
2
-->

### Example 5 — Xor-MST  ·  ★ 2300

- **Source:** [CF 888G · Xor-MST](https://codeforces.com/problemset/problem/888/G) — 2300
- **Difficulty:** 2300
- **Problem:** $n \le 2\cdot10^5$ numbers $0 \le a_i < 2^{30}$; the complete graph on them has $w(i,j) = a_i \oplus a_j$.
  Find the MST weight.
- **Thinking from first principles:** Look at the highest bit $b$ where the numbers differ. It splits them into $L$ (bit 0) and
  $R$ (bit 1). Every edge inside $L$ or inside $R$ costs $< 2^b$; every edge across costs $\ge 2^b$. Kruskal therefore connects
  $L$ and $R$ internally before considering any crossing edge, and afterwards needs exactly one crossing edge — the cheapest,
  $\min_{x\in L, y\in R} x\oplus y$. Recurse on $L$ and $R$ with bit $b-1$. These splits are exactly a binary trie over the
  numbers. The crossing minimum: iterate over the smaller side and query a trie for the best partner in the other side — each
  element is on the smaller side at most $\log n$ times (small-to-large), each query costs 30 steps:
  $O(n \log n \cdot 30)$.

<details><summary>Solution</summary>

Sort the numbers and build a trie; a trie node's subtree is a contiguous range of the sorted array. `solve(node, l, r, b)`
splits the range at the first index with bit $b$ set. Recursion depth is only 31, safe in Java.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

vector<array<int, 2>> ch;
vector<int> a;

int query(int node, int x, int b) {        // min (x xor y) over y in the subtree, counting bits b..0
    int res = 0;
    for (; b >= 0; b--) {
        int t = (x >> b) & 1;
        if (ch[node][t] != -1) node = ch[node][t];
        else { node = ch[node][t ^ 1]; res |= 1 << b; }
    }
    return res;
}

ll solve(int node, int l, int r, int b) {  // a[l..r) is exactly the subtree of node, which sits at bit b
    if (b < 0 || r - l <= 1) return 0;
    int mid = partition_point(a.begin() + l, a.begin() + r, [&](int v) { return !((v >> b) & 1); }) - a.begin();
    int c0 = ch[node][0], c1 = ch[node][1];
    if (c0 == -1) return solve(c1, l, r, b - 1);
    if (c1 == -1) return solve(c0, l, r, b - 1);
    ll res = solve(c0, l, mid, b - 1) + solve(c1, mid, r, b - 1);
    int best = INT_MAX;
    if (mid - l <= r - mid) for (int i = l; i < mid; i++) best = min(best, query(c1, a[i], b - 1));
    else for (int i = mid; i < r; i++) best = min(best, query(c0, a[i], b - 1));
    return res + best + (1LL << b);
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    a.resize(n);
    for (auto& v : a) cin >> v;
    sort(a.begin(), a.end());
    ch.reserve(31 * n + 1);
    ch.push_back({-1, -1});
    for (int v : a) {
        int node = 0;
        for (int b = 29; b >= 0; b--) {
            int t = (v >> b) & 1;
            if (ch[node][t] == -1) { ch[node][t] = ch.size(); ch.push_back({-1, -1}); }
            node = ch[node][t];
        }
    }
    cout << solve(0, 0, n, 29) << "\n";
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
    static int[] c0, c1, a;
    static int cnt = 1;

    static int query(int node, int x, int b) {
        int res = 0;
        for (; b >= 0; b--) {
            int t = (x >> b) & 1;
            int same = t == 0 ? c0[node] : c1[node];
            if (same != -1) node = same;
            else { node = t == 0 ? c1[node] : c0[node]; res |= 1 << b; }
        }
        return res;
    }

    static long solve(int node, int l, int r, int b) {
        if (b < 0 || r - l <= 1) return 0;
        int lo = l, hi = r;                       // first index in [l, r) with bit b set
        while (lo < hi) { int md = (lo + hi) >>> 1; if (((a[md] >> b) & 1) == 0) lo = md + 1; else hi = md; }
        int mid = lo, x0 = c0[node], x1 = c1[node];
        if (x0 == -1) return solve(x1, l, r, b - 1);
        if (x1 == -1) return solve(x0, l, r, b - 1);
        long res = solve(x0, l, mid, b - 1) + solve(x1, mid, r, b - 1);
        int best = Integer.MAX_VALUE;
        if (mid - l <= r - mid) for (int i = l; i < mid; i++) best = Math.min(best, query(x1, a[i], b - 1));
        else for (int i = mid; i < r; i++) best = Math.min(best, query(x0, a[i], b - 1));
        return res + best + (1L << b);
    }

    public static void main(String[] args) throws IOException {
        int n = nextInt();
        a = new int[n];
        for (int i = 0; i < n; i++) a[i] = nextInt();
        Random rnd = new Random(12345);           // shuffle: defeats anti-quicksort tests on old JDKs
        for (int i = n - 1; i > 0; i--) { int j = rnd.nextInt(i + 1), t = a[i]; a[i] = a[j]; a[j] = t; }
        Arrays.sort(a);
        c0 = new int[30 * n + 2]; c1 = new int[30 * n + 2];
        c0[0] = c1[0] = -1;
        for (int v : a) {
            int node = 0;
            for (int b = 29; b >= 0; b--) {
                int t = (v >> b) & 1;
                int nx = t == 0 ? c0[node] : c1[node];
                if (nx == -1) {
                    nx = cnt++;
                    c0[nx] = c1[nx] = -1;
                    if (t == 0) c0[node] = nx; else c1[node] = nx;
                }
                node = nx;
            }
        }
        System.out.println(solve(0, 0, n, 29));
    }
}
```

</details>

<!-- test
in:
4
5 9 12 3
out:
20
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
7 7 7
out:
0
-->
<!-- test
in:
5
0 1 2 3 1073741823
out:
1073741824
-->

## 6. Tricks, pitfalls and things to remember

1. **Check connectivity.** Kruskal silently returns a spanning *forest*; count successful unions (must be $n-1$).
2. **DSU without path compression *and* without union by size** degrades to $O(n)$ per find on a path; use at least one
   (path halving as above is the shortest code).
3. **Sorting in Java:** `Arrays.sort(int[][])` / `Integer[]` with a comparator boxes and is slow; pack `(weight << 32) | index`
   into a `long[]` (as in §3.1). Primitive sorts (`int[]`, `long[]`) are dual-pivot quicksort: on JDK ≤ 13 anti-quicksort
   tests can force $\Theta(n^2)$ (JDK 14+ falls back to heapsort), so shuffle first when the judge's JDK is old or unknown.
4. **Overflow:** the total of $n-1$ weights up to $10^9$ needs 64 bits; formula weights (products of coordinates and costs) need
   64 bits even per edge.
5. **Prim's dense loop** must scan only vertices not yet in the tree, and update keys after *each* addition — forgetting either
   gives a wrong answer that passes small tests.
6. **"Minimum spanning tree" is about total weight, not distances.** The MST path between two vertices can be much longer than
   their shortest path; never use an MST for distance queries (but do use it for **bottleneck** queries).
7. **Ties.** With equal weights there may be many MSTs; problems asking "is this edge in some/every MST" or "unique MST"
   require processing a whole weight class before uniting (CF 160D, CF 1108F, LC 1489).
8. **Strictly second-best MST:** if the path maximum equals $w(e)$, the swap gives the same weight; keep the two largest
   *distinct* values on each lifting jump.
9. **Borůvka needs a consistent tie-break** (e.g. by edge index); otherwise two components can pick different equal-weight edges
   and create a cycle.
10. **Complement BFS:** iterate over the unvisited list, not over all vertices, and rebuild the list each step; scanning all $n$
    vertices per BFS step is $O(n^2)$.
11. **Recursion depth** when rooting the MST for LCA: use BFS order (Example 3) — Java's default stack dies on a path of
    $2\cdot10^5$.
12. **Max spanning tree / "maximize the minimum edge"**: sort descending; the same proofs apply with inequalities flipped.

## 7. Going further (toward 2400–2600+)

- **Edge classes and contraction** (CF 160D Edges in MST, 2300): process each weight class on the graph contracted by the DSU
  of lighter edges; inside the class, bridges (see [bridges](06-bridges-articulation-points-and-bcc.md)) are in every MST,
  other non-loop edges in some.
- **MST + shortest paths** (CF 1253F Cheap Robot, 2500): multi-source Dijkstra from all centrals turns edge weights into
  $d_u + d_v + w$; the answer to "minimum battery capacity" queries is a bottleneck on the MST of the new weights.
- **Kruskal reconstruction tree** (CF 1416D Graph and Queries 2600, CF 1706E 2300): turns "reachable with edges $\le x$" into a
  subtree, combinable with segment trees over DFS order or with [persistent structures](../08-Data-Structures/08-persistent-data-structures.md).
- **Dynamic MST / offline edge insertions and deletions:** segment tree on time + DSU with rollback
  ([segment tree on time](../16-IGM-Frontier/02-segment-tree-on-time-and-dsu-rollback.md)), or link-cut trees maintaining
  path maxima online ([link-cut trees](../16-IGM-Frontier/03-link-cut-trees.md)).
- **Borůvka on implicit graphs:** for each component, query the best outgoing edge with a data structure that excludes the
  component itself (keep the best and second-best by component id). Classic for "MST where $w(i,j)$ depends on values in a
  structure" problems at 2500+.
- **Counting MSTs:** group by weight, and within each class count spanning forests of the contracted multigraph with the
  matrix-tree theorem ([linear-algebra tricks](../15-Advanced-Math/06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md)).
- **Directed MST** (Chu–Liu/Edmonds) and **Steiner tree** DP over subsets of terminals
  ([bitmask DP](../06-Dynamic-Programming/06-bitmask-dp.md)) are the two "MST-like" problems where greedy fails.

## 8. Practice ladder

**≤ 1700**
- [ ] [CSES 1675 · Road Reparation](https://cses.fi/problemset/task/1675) — Kruskal
- [ ] [AtCoder ABC218 E · Destruction](https://atcoder.jp/contests/abc218/tasks/abc218_e) — keep a minimum tree, remove the rest (careful with negative weights)
- [ ] [CF 437C · The Child and Toy](https://codeforces.com/problemset/problem/437/C) — 1400 (greedy edge-cost argument, MST-flavored)
- [ ] [AtCoder ABC235 E · MST + 1](https://atcoder.jp/contests/abc235/tasks/abc235_e) — offline: would this edge enter the MST?
- [ ] [AtCoder ABC282 E · Choose Two and Eat One](https://atcoder.jp/contests/abc282/tasks/abc282_e) — maximum spanning tree on a complete graph

**1700–2100**
- [ ] [AtCoder ABC270 F · Transportation](https://atcoder.jp/contests/abc270/tasks/abc270_f) — two virtual vertices, 4 cases
- [ ] [CF 1095F · Make It Connected](https://codeforces.com/problemset/problem/1095/F) — 1900
- [ ] [CF 1245D · Shichikuji and Power Grid](https://codeforces.com/problemset/problem/1245/D) — 1900
- [ ] [CF 1242B · 0-1 MST](https://codeforces.com/problemset/problem/1242/B) — 1900
- [ ] [CF 1624G · MinOr Tree](https://codeforces.com/problemset/problem/1624/G) — 1900
- [ ] [CF 25D · Roads not only in Berland](https://codeforces.com/problemset/problem/25/D) — 1900
- [ ] [CF 1513D · GCD and MST](https://codeforces.com/problemset/problem/1513/D) — 2000
- [ ] [CF 609E · Minimum spanning tree for each edge](https://codeforces.com/problemset/problem/609/E) — 2100
- [ ] [CF 1108F · MST Unification](https://codeforces.com/problemset/problem/1108/F) — 2100
- [ ] [CSES 3407 · MST Edge Check](https://cses.fi/problemset/task/3407) — some-MST test per edge
- [ ] [CSES 3409 · MST Edge Cost](https://cses.fi/problemset/task/3409) — forced-edge MST

**2100+**
- [ ] [CSES 3408 · MST Edge Set Check](https://cses.fi/problemset/task/3408) — weight classes
- [ ] [CF 160D · Edges in MST](https://codeforces.com/problemset/problem/160/D) — 2300
- [ ] [CF 888G · Xor-MST](https://codeforces.com/problemset/problem/888/G) — 2300
- [ ] [CF 1706E · Qpwoeirut and Vertices](https://codeforces.com/problemset/problem/1706/E) — 2300
- [ ] [CF 1253F · Cheap Robot](https://codeforces.com/problemset/problem/1253/F) — 2500
- [ ] [CF 1416D · Graph and Queries](https://codeforces.com/problemset/problem/1416/D) — 2600

## 9. LeetCode / FAANG cross-reference

MST appears in interviews mostly as "connect points/cities at minimum cost" (Kruskal or Prim) and as DSU + sorting puzzles.

- [LC 1584 · Min Cost to Connect All Points](https://leetcode.com/problems/min-cost-to-connect-all-points/) — Medium — dense Prim $O(n^2)$ on Manhattan distances.
- [LC 1135 · Connecting Cities With Minimum Cost](https://leetcode.com/problems/connecting-cities-with-minimum-cost/) — Medium 🔒 — Kruskal with the connectivity check.
- [LC 1168 · Optimize Water Distribution in a Village](https://leetcode.com/problems/optimize-water-distribution-in-a-village/) — Hard 🔒 — virtual vertex (Example 2's trick).
- [LC 1489 · Find Critical and Pseudo-Critical Edges in Minimum Spanning Tree](https://leetcode.com/problems/find-critical-and-pseudo-critical-edges-in-minimum-spanning-tree/) — Hard — exclude/force each edge, or weight classes.
- [LC 1697 · Checking Existence of Edge Length Limited Paths](https://leetcode.com/problems/checking-existence-of-edge-length-limited-paths/) — Hard — offline bottleneck queries with DSU.
- [LC 1579 · Remove Max Number of Edges to Keep Graph Fully Traversable](https://leetcode.com/problems/remove-max-number-of-edges-to-keep-graph-fully-traversable/) — Hard — Kruskal with shared edges first, two DSUs.
- [LC 778 · Swim in Rising Water](https://leetcode.com/problems/swim-in-rising-water/) — Hard — bottleneck path = add cells in increasing height until connected.
- [LC 1631 · Path With Minimum Effort](https://leetcode.com/problems/path-with-minimum-effort/) — Medium — bottleneck path via Kruskal or minimax Dijkstra.
- [LC 684 · Redundant Connection](https://leetcode.com/problems/redundant-connection/) — Medium — the first edge closing a cycle (DSU).

## 10. Self-check

1. State and prove the cut property. Where does the proof need "minimum"?
2. Why is Kruskal's chosen edge the lightest edge across *some* cut?
3. When is dense Prim better than Kruskal, and what is its complexity?
4. Give the formula for the lightest spanning tree containing a non-tree edge $e$ and justify it with the cycle property.
5. Why is the MST path a minimum bottleneck path for *every* pair of vertices?
6. In XOR-MST, why does exactly one edge cross between the two children of a trie node?
7. How do you turn "build a station or connect to a powered neighbor" into an MST?
8. Why is complement BFS $O(n+m)$ and not $O(n^2)$?

<details><summary>Answers</summary>

1. For any cut, a lightest crossing edge $e$ is in some MST: if MST $T$ lacks $e$, its $u$–$v$ path crosses the cut at $f$ with
   $w(f) \ge w(e)$ (here "minimum" is used); $T - f + e$ is a spanning tree no heavier.
2. When $e = \{u,v\}$ is accepted, $u$ and $v$ are in different components; take the cut (component of $u$, rest). Every lighter
   edge was processed earlier and either joined two components (so it is inside one now) or was inside one: no lighter edge
   crosses this cut.
3. On dense/complete graphs ($m \approx n^2$), especially when weights come from a formula: $O(n^2)$ time, $O(n)$ memory, no
   edge list or sort.
4. $w(T) - \max_{f\in\text{path}_T(u,v)} w(f) + w(e)$: any spanning tree containing $e$ must omit some edge of that cycle; the
   exchange argument shows dropping the heaviest path edge is optimal.
5. Kruskal joins $u$ and $v$ at the first weight $w^*$ where they become connected; every $u$–$v$ path has an edge $\ge w^*$
   (else they'd be joined earlier), and the MST path's edges are all $\le w^*$.
6. Edges inside each child cost $< 2^b$ and edges across cost $\ge 2^b$, so Kruskal finishes connecting each child before any
   crossing edge; then one crossing edge connects the two components, and further crossing edges would close cycles.
7. Add a virtual vertex 0 with edge $(0,i)$ of weight $c_i$; the MST on $n+1$ vertices connects every city to 0 = gives it power.
8. Every check of an unvisited vertex $v$ while expanding $u$ either removes $v$ (at most $n$ times in total) or finds that
   $\{u,v\}$ is a given edge (at most $2m$ times in total).

</details>
