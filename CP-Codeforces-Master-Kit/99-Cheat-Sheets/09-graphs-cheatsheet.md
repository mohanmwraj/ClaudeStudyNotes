# Cheat Sheet — Graphs

Revision only. Full derivations: [BFS/DFS](../09-Graphs/01-graph-representation-bfs-dfs.md) · [shortest paths](../09-Graphs/02-shortest-paths.md) ·
[MST](../09-Graphs/03-minimum-spanning-trees.md) · [topological sort](../09-Graphs/04-topological-sort-and-dag-dp.md) · [SCC](../09-Graphs/05-scc-and-condensation.md) ·
[bridges/BCC](../09-Graphs/06-bridges-articulation-points-and-bcc.md) · [2-SAT](../09-Graphs/07-two-sat.md) · [Euler](../09-Graphs/08-euler-paths-and-circuits.md) ·
[bipartite/cycles](../09-Graphs/09-bipartite-graphs-and-cycles.md) · [functional/special](../09-Graphs/10-functional-graphs-and-special-graphs.md) · [problems](../09-Graphs/problems.md)

## 1. Algorithms and complexities

| Task | Algorithm | Time | Notes |
|---|---|---|---|
| reachability, components, flood fill | BFS / iterative DFS | $O(n+m)$ | DSU if edges arrive online |
| unweighted shortest path | BFS (mark on push) | $O(n+m)$ | multi-source: all sources at 0 |
| weights $\{0,1\}$ | 0-1 BFS (deque) | $O(n+m)$ | final on pop; push ≤ 2× per vertex |
| weights $\ge 0$ | Dijkstra, heap + lazy deletion | $O((n+m)\log n)$ | dense: $O(n^2)$ array version |
| any weights, single source | Bellman–Ford | $O(nm)$ | relax in round $n$ ⇒ negative cycle |
| any weights, queue | SPFA | $O(nm)$ worst | hackable — avoid on CF |
| all pairs, $n\le500$ | Floyd–Warshall | $O(n^3)$ | `k` outermost |
| all pairs, sparse, negative | Johnson (🧊) | $O(nm\log n)$ | BF potentials + $n$ Dijkstras |
| $k$ shortest walks | pop each vertex ≤ $k$ times | $O(km\log(km))$ | walks, not simple paths |
| DAG shortest/longest/count | DP in topological order | $O(n+m)$ | negative weights fine |
| MST | Kruskal + DSU / Prim | $O(m\log m)$ / $O(n^2)$ | Borůvka $O(m\log n)$ for implicit graphs |
| path max in MST, forced edge | binary lifting | $O((n+q)\log n)$ | second-best MST |
| topological order | Kahn / reverse post-order | $O(n+m)$ | heap ⇒ lexicographically smallest |
| SCC | Tarjan / Kosaraju (iterative!) | $O(n+m)$ | Tarjan ids reverse-topological |
| bridges, cut vertices, 2ECC, BCC | low-link DFS | $O(n+m)$ | skip parent *edge id* |
| 2-SAT | SCC on implication graph | $O(n+m)$ | $x$ true iff `comp[x] < comp[¬x]` (Tarjan ids) |
| Euler path/circuit | Hierholzer (iterative) | $O(n+m)$ | check degrees + connectivity |
| bipartite check | BFS 2-coloring | $O(n+m)$ | edge inside a layer ⇒ odd cycle |
| girth (unweighted) | BFS from every vertex | $O(nm)$ | finish the layer before stopping |
| $k$-th successor | binary lifting | $O(n\log k)$ build | or tail + cycle decomposition |
| cycle in $x \mapsto f(x)$, $O(1)$ memory | Floyd / Brent | $O(\mu+\lambda)$ | returns $\mu$ (tail) and $\lambda$ (period) |
| BFS on complement graph | unvisited list | $O(n+m)$ | 0-1 MST, CF 920E |

## 2. Formulas and facts

| Fact | Statement |
|---|---|
| handshake | $\sum\deg = 2m$; #odd-degree vertices is even |
| forest | $m = n - c$; cyclomatic number $m-n+c$ = #independent cycles |
| BFS layers | $\lvert d(u)-d(v)\rvert \le 1$ on every undirected edge |
| parenthesis | $u$ ancestor of $v$ $\iff tin_u \le tin_v \wedge tout_v \le tout_u$ |
| directed cycle | exists $\iff$ DFS meets a **gray** vertex (back edge) $\iff$ Kahn outputs $<n$ |
| undirected DFS | only tree and back edges (no cross edges) |
| Dijkstra invariant | popped vertex is final because prefixes of shortest paths are not longer ($w\ge0$) |
| Bellman–Ford | after round $k$: $d[v] \le$ best walk with $\le k$ edges |
| negative cycle print | walk `par` $n$ times from the vertex relaxed in round $n$, then follow until repeat |
| Floyd | $d[i][j]=\min(d[i][j], d[i][k]+d[k][j])$; $d[i][i]<0$ ⇒ negative cycle |
| reweighting | $w'=w+h(u)-h(v)$; $\operatorname{dist} = \operatorname{dist}' - h(s) + h(t)$ |
| difference constraints | $x_v-x_u\le w$ ⇒ edge $u\to v$ ($w$); virtual source 0-edges; feasible iff no neg. cycle |
| tight edge | on a shortest $s$–$t$ path iff $d_s(u)+w+d_t(v)=d_s(t)$ |
| cut property | lightest edge across a cut is in some MST |
| cycle property | strictly heaviest edge on a cycle is in no MST |
| forced edge | $\text{MST}(e) = W - \text{pathmax}(u,v) + w(e)$ |
| bottleneck | min over paths of max edge = MST path max = weight of LCA in Kruskal tree |
| condensation | always a DAG; Kosaraju ids topological, Tarjan ids reverse-topological |
| strongly connect | add $\max(\#\text{sources}, \#\text{sinks})$ edges ($0$ if one SCC) |
| reach all from $s$ | #source SCCs other than SCC($s$) |
| bridge | tree edge $p\to v$ with $low[v] > tin[p]$ |
| cut vertex | non-root $p$ with a child $low[v] \ge tin[p]$; root with $\ge2$ children |
| 2-edge-connected | no bridges $\iff$ has a strongly connected orientation (Robbins) |
| bridge-tree augmentation | $\lceil L/2\rceil$ edges, $L$ = #leaves of the bridge tree |
| 2-SAT | unsat $\iff \exists x$: $x$ and $\neg x$ in one SCC |
| Euler circuit (undirected) | all degrees even + edges in one component |
| Euler path (undirected) | 0 or 2 odd vertices; start at an odd one |
| Euler (directed) | circuit: in = out everywhere; path: one $+1$ start, one $-1$ end; weakly connected edges |
| min trails covering all edges | $\sum_{\text{comp with edges}} \max(1, \text{odd}/2)$ |
| de Bruijn $B(k,n)$ | length $k^n$ (cyclic), Euler circuit on $k^{n-1}$ vertices |
| bipartite | $\iff$ no odd cycle $\iff$ 2-colorable |
| functional graph | each component = one cycle + in-trees; $\#\text{distinct visited from } v$ = tail + cycle length |
| planar | $m \le 3n-6$ ($n\ge3$); bipartite planar $m\le 2n-4$; $V-E+F=2$ |
| complete graph | $n^{n-2}$ spanning trees (Cayley); $\binom n2$ edges |

## 3. Signal → technique

| Statement says | Do |
|---|---|
| "minimum number of moves", all moves cost 1 | BFS over states (count states first) |
| "free moves" / "pay 1 to break/turn" | 0-1 BFS |
| "at most $k$ coupons/free edges", "parity", "last color" | layered graph + Dijkstra |
| "number of shortest routes", "min/max edges among cheapest" | DP over the shortest-path DAG |
| "infinite profit / arbitrarily large" | (negative) cycle on a path from $s$ **to $t$** |
| $n\le500$, "every pair", vertices removed over time | Floyd (reverse order of deletion) |
| inequalities $x_j-x_i\le c$ | difference constraints → Bellman–Ford |
| "connect everything at minimum cost" | MST; "build here or connect" → virtual vertex |
| "minimize the max edge on the path" | MST / DSU over sorted edges / Kruskal tree |
| "prerequisites", "order consistent with" | Kahn; lexicographic → heap; "smallest labels" → reverse + max-heap |
| "revisit allowed, collect everything" (directed) | SCC condensation + DAG DP |
| "if $x$ then $y$", each item has two choices | 2-SAT |
| "which single road/city failure disconnects" | bridges / articulation points |
| "use every edge exactly once", "string from all $k$-grams" | Euler path (Hierholzer) |
| "split into two groups with no conflicts" | bipartite coloring (per component: two choices) |
| each vertex has exactly one outgoing edge / permutation | functional graph: cycles + trees, binary lifting |
| graph given as "all pairs except $m$" | complement BFS with an unvisited list |
| edges from a vertex to a whole range | segment-tree graph (auxiliary vertices) |
| $m-n$ tiny | spanning tree + few extra edges |

## 4. Modeling gadgets

- **Virtual source/sink:** one vertex joined to all sources (weight 0 or the source's own cost) — multi-source BFS/Dijkstra,
  "build a station" MST, difference constraints.
- **Vertex → state:** $(v, j)$ with $j$ = resources used / parity / direction / time mod $g$; ids `v*(K+1)+j`.
- **Objects as vertices:** rows and columns (CF 173B), bus routes (LC 815), values (CF 1152E), $k-1$-grams (de Bruijn).
- **Range edges:** segment tree of auxiliary vertices; "out" tree edges parent→child (0), "in" tree child→parent (0).
- **Reverse the graph** for "can reach $t$", "safe states", "minimal labels", Kosaraju pass 2.
- **Contract equivalences:** SCC (directed), 2ECC → bridge tree, blocks → block-cut tree, functional-graph cycles.

## 5. Templates

Dijkstra (C++; Java uses a `long[]` heap of `{dist, v}` — fine up to ~$10^6$ pushes).

```cpp
vector<ll> dijkstra(const vector<vector<pair<int, ll>>>& g, int s) {
    vector<ll> d(g.size(), LLONG_MAX);
    priority_queue<pair<ll, int>, vector<pair<ll, int>>, greater<>> pq;
    d[s] = 0; pq.push({0, s});
    while (!pq.empty()) {
        auto [du, u] = pq.top(); pq.pop();
        if (du != d[u]) continue;
        for (auto [v, w] : g[u]) if (du + w < d[v]) { d[v] = du + w; pq.push({d[v], v}); }
    }
    return d;
}
```

```java
static long[] dijkstra(int n, int[] start, int[] to, long[] wt, int s) {
    long[] d = new long[n];
    Arrays.fill(d, Long.MAX_VALUE);
    PriorityQueue<long[]> pq = new PriorityQueue<>((a, b) -> Long.compare(a[0], b[0]));
    d[s] = 0; pq.add(new long[]{0, s});
    while (!pq.isEmpty()) {
        long[] top = pq.poll();
        int u = (int) top[1];
        if (top[0] != d[u]) continue;
        for (int e = start[u]; e < start[u + 1]; e++)
            if (d[u] + wt[e] < d[to[e]]) { d[to[e]] = d[u] + wt[e]; pq.add(new long[]{d[to[e]], to[e]}); }
    }
    return d;
}
```

DSU + Kruskal (edges `(w, u, v)`; returns $-1$ if disconnected).

```cpp
ll kruskal(int n, vector<array<ll, 3>> e) {
    vector<int> p(n); iota(p.begin(), p.end(), 0);
    auto f = [&](int x) { while (p[x] != x) x = p[x] = p[p[x]]; return x; };
    sort(e.begin(), e.end());
    ll tot = 0; int k = 0;
    for (auto& [w, u, v] : e) { int a = f(u), b = f(v); if (a != b) { p[a] = b; tot += w; k++; } }
    return k == n - 1 ? tot : -1;
}
```

```java
static long kruskal(int n, int[] eu, int[] ev, int[] ew) {
    int m = eu.length; long[] key = new long[m];
    for (int i = 0; i < m; i++) key[i] = ((long) ew[i] << 32) | i;    // weights >= 0, < 2^31
    Arrays.sort(key);
    int[] p = new int[n]; for (int i = 0; i < n; i++) p[i] = i;
    long tot = 0; int k = 0;
    for (long kk : key) {
        int i = (int) kk, a = eu[i], b = ev[i];
        while (p[a] != a) a = p[a] = p[p[a]];
        while (p[b] != b) b = p[b] = p[p[b]];
        if (a != b) { p[a] = b; tot += ew[i]; k++; }
    }
    return k == n - 1 ? tot : -1;
}
```

Kahn (empty / `null` result = cycle).

```cpp
vector<int> topo(const vector<vector<int>>& g) {
    int n = g.size(); vector<int> in(n, 0), q;
    for (auto& a : g) for (int v : a) in[v]++;
    for (int v = 0; v < n; v++) if (!in[v]) q.push_back(v);
    for (size_t h = 0; h < q.size(); h++) for (int v : g[q[h]]) if (--in[v] == 0) q.push_back(v);
    if ((int)q.size() < n) q.clear();
    return q;
}
```

```java
static int[] topo(int n, int[] start, int[] adj) {
    int[] in = new int[n], q = new int[n]; int h = 0, t = 0;
    for (int e = 0; e < start[n]; e++) in[adj[e]]++;
    for (int v = 0; v < n; v++) if (in[v] == 0) q[t++] = v;
    while (h < t) { int u = q[h++]; for (int e = start[u]; e < start[u + 1]; e++) if (--in[adj[e]] == 0) q[t++] = adj[e]; }
    return t == n ? q : null;
}
```

Iterative Tarjan SCC (ids in reverse topological order) + 2-SAT on top (literal `2x` = true, `2x+1` = false).

```cpp
vector<int> tarjan(const vector<vector<int>>& g, int& k) {
    int n = g.size(), timer = 0; k = 0;
    vector<int> tin(n, -1), low(n), it(n, 0), comp(n, -1), st, call; vector<char> on(n, 0);
    for (int s = 0; s < n; s++) {
        if (tin[s] != -1) continue;
        tin[s] = low[s] = timer++; st.push_back(s); on[s] = 1; call.push_back(s);
        while (!call.empty()) {
            int u = call.back();
            if (it[u] < (int)g[u].size()) {
                int v = g[u][it[u]++];
                if (tin[v] == -1) { tin[v] = low[v] = timer++; st.push_back(v); on[v] = 1; call.push_back(v); }
                else if (on[v]) low[u] = min(low[u], tin[v]);
            } else {
                call.pop_back();
                if (!call.empty()) low[call.back()] = min(low[call.back()], low[u]);
                if (low[u] == tin[u]) { int x; do { x = st.back(); st.pop_back(); on[x] = 0; comp[x] = k; } while (x != u); k++; }
            }
        }
    }
    return comp;
}
struct TwoSat {                       // clause (a OR b): literal = 2*var + (negated ? 1 : 0)
    int n; vector<vector<int>> g;
    TwoSat(int n) : n(n), g(2 * n) {}
    void either(int a, int b) { g[a ^ 1].push_back(b); g[b ^ 1].push_back(a); }
    bool solve(vector<int>& val) {
        int k; auto comp = tarjan(g, k); val.assign(n, 0);
        for (int x = 0; x < n; x++) { if (comp[2 * x] == comp[2 * x + 1]) return false; val[x] = comp[2 * x] < comp[2 * x + 1]; }
        return true;
    }
};
```

```java
static int[] tarjan(int n, int[] start, int[] adj, int[] kOut) {
    int[] tin = new int[n], low = new int[n], it = new int[n], comp = new int[n], st = new int[n], call = new int[n];
    boolean[] on = new boolean[n]; Arrays.fill(tin, -1);
    int timer = 0, sp = 0, cp = 0, k = 0;
    for (int s = 0; s < n; s++) {
        if (tin[s] != -1) continue;
        tin[s] = low[s] = timer++; st[sp++] = s; on[s] = true; it[s] = start[s]; call[cp++] = s;
        while (cp > 0) {
            int u = call[cp - 1];
            if (it[u] < start[u + 1]) {
                int v = adj[it[u]++];
                if (tin[v] == -1) { tin[v] = low[v] = timer++; st[sp++] = v; on[v] = true; it[v] = start[v]; call[cp++] = v; }
                else if (on[v]) low[u] = Math.min(low[u], tin[v]);
            } else {
                cp--;
                if (cp > 0) low[call[cp - 1]] = Math.min(low[call[cp - 1]], low[u]);
                if (low[u] == tin[u]) { int x; do { x = st[--sp]; on[x] = false; comp[x] = k; } while (x != u); k++; }
            }
        }
    }
    kOut[0] = k;
    return comp;
}
// 2-SAT: build CSR over 2n literals with edges (a^1 -> b), (b^1 -> a) per clause, then
// unsat iff comp[2x] == comp[2x+1]; otherwise x = (comp[2x] < comp[2x+1]).
static boolean[] twoSat(int n, int[] ca, int[] cb) {
    int m = ca.length, N = 2 * n; int[] from = new int[2 * m], to = new int[2 * m], start = new int[N + 1];
    for (int i = 0; i < m; i++) { from[2 * i] = ca[i] ^ 1; to[2 * i] = cb[i]; from[2 * i + 1] = cb[i] ^ 1; to[2 * i + 1] = ca[i]; }
    for (int f : from) start[f + 1]++;
    for (int i = 0; i < N; i++) start[i + 1] += start[i];
    int[] adj = new int[2 * m], pos = Arrays.copyOf(start, N);
    for (int i = 0; i < 2 * m; i++) adj[pos[from[i]]++] = to[i];
    int[] comp = tarjan(N, start, adj, new int[1]);
    boolean[] val = new boolean[n];
    for (int x = 0; x < n; x++) { if (comp[2 * x] == comp[2 * x + 1]) return null; val[x] = comp[2 * x] < comp[2 * x + 1]; }
    return val;
}
```

Bridges and articulation points, iterative, multi-edge safe (`adj[u] = {(v, edgeId)}`).

```cpp
void lowLink(int n, const vector<vector<pair<int, int>>>& adj, int m, vector<char>& bridge, vector<char>& cut) {
    vector<int> tin(n, -1), low(n), it(n, 0), pe(n, -1), st; bridge.assign(m, 0); cut.assign(n, 0);
    int timer = 0;
    for (int r = 0; r < n; r++) {
        if (tin[r] != -1) continue;
        int kids = 0; tin[r] = low[r] = timer++; st.push_back(r);
        while (!st.empty()) {
            int u = st.back();
            if (it[u] < (int)adj[u].size()) {
                auto [v, id] = adj[u][it[u]++];
                if (id == pe[u]) continue;                                   // skip the parent EDGE, not the parent vertex
                if (tin[v] == -1) { pe[v] = id; tin[v] = low[v] = timer++; st.push_back(v); if (u == r) kids++; }
                else low[u] = min(low[u], tin[v]);
            } else {
                st.pop_back();
                if (st.empty()) break;
                int p = st.back(); low[p] = min(low[p], low[u]);
                if (low[u] > tin[p]) bridge[pe[u]] = 1;
                if (p != r && low[u] >= tin[p]) cut[p] = 1;
            }
        }
        if (kids >= 2) cut[r] = 1;
    }
}
```

```java
// CSR with edge ids: neighbors of u are to[e], ids eid[e], e in [start[u], start[u+1]).
static void lowLink(int n, int[] start, int[] to, int[] eid, int m, boolean[] bridge, boolean[] cut) {
    int[] tin = new int[n], low = new int[n], it = new int[n], pe = new int[n], st = new int[n];
    Arrays.fill(tin, -1); Arrays.fill(pe, -1);
    int timer = 0;
    for (int r = 0; r < n; r++) {
        if (tin[r] != -1) continue;
        int kids = 0, sp = 0; tin[r] = low[r] = timer++; it[r] = start[r]; st[sp++] = r;
        while (sp > 0) {
            int u = st[sp - 1];
            if (it[u] < start[u + 1]) {
                int e = it[u]++, v = to[e];
                if (eid[e] == pe[u]) continue;
                if (tin[v] == -1) { pe[v] = eid[e]; tin[v] = low[v] = timer++; it[v] = start[v]; st[sp++] = v; if (u == r) kids++; }
                else low[u] = Math.min(low[u], tin[v]);
            } else {
                sp--;
                if (sp == 0) break;
                int p = st[sp - 1]; low[p] = Math.min(low[p], low[u]);
                if (low[u] > tin[p]) bridge[pe[u]] = true;
                if (p != r && low[u] >= tin[p]) cut[p] = true;
            }
        }
        if (kids >= 2) cut[r] = true;
    }
}
```

Hierholzer, undirected, iterative (check degree parity and connectivity first; start at an odd vertex for a path).

```cpp
vector<int> euler(int n, const vector<vector<pair<int, int>>>& adj, int m, int s) {
    vector<int> it(n, 0), st = {s}, path; vector<char> used(m, 0);
    while (!st.empty()) {
        int u = st.back();
        while (it[u] < (int)adj[u].size() && used[adj[u][it[u]].second]) it[u]++;
        if (it[u] == (int)adj[u].size()) { path.push_back(u); st.pop_back(); }
        else { auto [v, id] = adj[u][it[u]++]; used[id] = 1; st.push_back(v); }
    }
    if ((int)path.size() != m + 1) return {};                          // some edges unreachable from s
    reverse(path.begin(), path.end());
    return path;
}
```

```java
static int[] euler(int n, int[] start, int[] to, int[] eid, int m, int s) {
    int[] it = Arrays.copyOf(start, n), st = new int[m + 1], path = new int[m + 1];
    boolean[] used = new boolean[m];
    int sp = 0, pc = 0; st[sp++] = s;
    while (sp > 0) {
        int u = st[sp - 1];
        while (it[u] < start[u + 1] && used[eid[it[u]]]) it[u]++;
        if (it[u] == start[u + 1]) { path[pc++] = u; sp--; }
        else { int e = it[u]++; used[eid[e]] = true; st[sp++] = to[e]; }
    }
    if (pc != m + 1) return null;
    for (int i = 0, j = pc - 1; i < j; i++, j--) { int t = path[i]; path[i] = path[j]; path[j] = t; }
    return path;
}
```

## 6. Edge cases and constants

- $n=1$, $m=0$; isolated vertices (still components, still need topological positions, still SCCs).
- Self-loops: a cycle for Kahn/DFS; degree $+2$ in undirected Euler; never a bridge.
- Parallel edges: never bridges; count separately in in-degrees and path counts; keep the minimum in Floyd.
- Disconnected input: outer loop over all start vertices; Kruskal must check $n-1$ unions.
- INF: `LLONG_MAX/4` ($\approx2.3\cdot10^{18}$); $n\cdot w_{\max} = 10^5\cdot10^9$ needs 64 bits.
- Multi-test input: reset adjacency, `tin`, colors, DSU **per test** (and only the used prefix: $\sum n$ bounded).
- Recursion: Java default stack ≈ $10^4$–$10^5$ frames; Windows C++ 1 MB. Iterative DFS or `new Thread(null, r, "", 1<<28)`.
- Mod $10^9+7$ only for counts, never for distances or comparisons.

## 7. Top 10 mistakes

1. Recursive DFS on a $10^5$-vertex path in Java (StackOverflowError) — use the iterator-stack DFS.
2. Marking BFS vertices visited at pop time (queue blow-up) / skipping Dijkstra relaxations of "seen" vertices.
3. Dijkstra with a negative edge "just once".
4. Missing the reverse edge of an undirected graph, or allocating `m` instead of `2m` CSR slots.
5. Two-color cycle detection in a directed graph (diamonds look like cycles).
6. Skipping the parent **vertex** instead of the parent **edge id** in low-link (parallel edges become bridges).
7. Tarjan updating `low` through edges into already completed SCCs (missing the `onStack` check).
8. Floyd with `k` not outermost; adding two INFs.
9. Forgetting that unreachable vertices must stay $-\infty$ in DAG longest path (paths start anywhere).
10. Not checking connectivity of the edge set before declaring an Euler path / spanning tree.

## 8. Last-minute before the contest

- Templates ready and tested: iterative DFS, BFS/0-1 BFS, Dijkstra (C++ `greater<>`; Java primitive heap), DSU, Kahn,
  Tarjan + 2-SAT, low-link, Hierholzer, binary lifting.
- Read constraints → pick: $n+m$ (BFS/DFS/SCC), $(n+m)\log n$ (Dijkstra/Kruskal), $nm$ (Bellman–Ford, girth), $n^3$
  (Floyd, $n\le500$), $n^2$ (dense Prim, $n\le5000$).
- Before coding a state BFS, multiply the state count by the branching factor and by 4 bytes.
- "Any valid answer" problems: still check impossible cases (cycle, odd degrees, disconnected) first.
- Write the stress harness for graph problems once (random small graph generator + Floyd/brute) and reuse it.
