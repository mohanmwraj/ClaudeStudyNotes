# Cheat Sheet — Flows and Matching

Revision only. Full derivations: [max flow](../12-Flows-and-Matching/01-max-flow-dinic.md) · [min cut & modeling](../12-Flows-and-Matching/02-min-cut-and-flow-modeling.md) ·
[bipartite matching](../12-Flows-and-Matching/03-bipartite-matching-kuhn-hopcroft-karp.md) · [min-cost flow](../12-Flows-and-Matching/04-min-cost-flow.md) ·
[Hungarian](../12-Flows-and-Matching/05-hungarian-algorithm.md) · [theorems](../12-Flows-and-Matching/06-matching-theorems-konig-hall-dilworth.md) · [problems](../12-Flows-and-Matching/problems.md)

## 1. Algorithms and complexities

| Algorithm | Time | Use when |
|---|---|---|
| Ford–Fulkerson (DFS) | $O(E\cdot\lvert f\rvert)$ | flow value tiny |
| Edmonds–Karp (BFS) | $O(VE^2)$ | brute force / teaching |
| **Dinic** | $O(V^2E)$, fast in practice | default max flow |
| Dinic, unit capacities | $O(E\min(\sqrt E, V^{2/3}))$ | edge-disjoint paths |
| Dinic / **Hopcroft–Karp**, bipartite | $O(E\sqrt V)$ | matching with $10^5$ edges |
| **Kuhn** | $O(V\cdot E)$ | matching, $n\le 5000$-ish, short code |
| **SSP min-cost flow** (Dijkstra + potentials) | $O(F\cdot E\log V)$ + one Bellman–Ford $O(VE)$ | costs per unit, small $F$ |
| **Hungarian** | $O(n^2m)$ | dense assignment, $n\le 500$ |
| Push–relabel (🧊) | $O(V^2\sqrt E)$ | dense adversarial |
| Blossom (🔴) | $O(V^3)$ | general-graph matching |

## 2. Theorems and formulas

| Statement | Formula |
|---|---|
| Max-flow min-cut | $\max\lvert f\rvert = \min c(S,T)$; $S$ = residual-reachable from $s$ (canonical, smallest) |
| Integrality | integer capacities ⇒ integral max flow and min-cost flow |
| Residual capacity | $c_f(u,v) = c(u,v)-f(u,v)+f(v,u)$; reverse edge `i ^ 1` |
| Menger | #edge-disjoint paths = min edge cut; #internally vertex-disjoint = min vertex cut (split) |
| Project selection | $\max = \sum_{p_i>0}p_i - \text{mincut}$; $s\to i$ ($p_i>0$), $i\to t$ ($-p_i$), $i\to j$ $\infty$ ("$i$ needs $j$") |
| Lower bounds | $f=l+f'$; $\text{ex}(v)=\sum_{in}l-\sum_{out}l$; $S^*\to v$ / $v\to T^*$; add $t\to s$ $\infty$; feasible iff saturating |
| Max flow with bounds | $F_0$ = flow on $t\to s$; delete it; answer $F_0+\text{maxflow}(s,t)$ |
| Reduced cost | $w_\pi(u,v)=w(u,v)+\pi(u)-\pi(v)\ge0$; update $\pi\mathrel{+}=d$; path cost $=\pi(t)-\pi(s)$ |
| Min-cost optimality | no negative residual cycle $\iff$ optimal for its value |
| Convexity | cost$(F)$ convex ⇒ stop at first non-negative path for "any amount of flow" |
| Convex per-unit cost | unit edges with $g(k)-g(k-1)$; squares: $2k-1$ |
| Berge | matching maximum $\iff$ no augmenting path |
| König (bipartite) | $\nu=\tau$; cover $=(L\setminus Z)\cup(R\cap Z)$, $Z$ = alternating-reachable from free left |
| Gallai | $\alpha+\tau=n$; $\nu+\rho=n$ (no isolated vertices); bipartite: $\alpha=\rho=n-\nu$ |
| Hall | $L$-perfect iff $\lvert N(X)\rvert\ge\lvert X\rvert\ \forall X$; $\nu=\lvert L\rvert-\max_X(\lvert X\rvert-\lvert N(X)\rvert)$ |
| Typed Hall | $\forall U$: #left vertices with allowed set $\subseteq U$ $\le$ capacity of $U$ ($2^k$ checks) |
| Dilworth | min chain cover = max antichain $=n-\nu(G_<)$ (relation must be transitive) |
| DAG path cover | vertex-disjoint: $n-\nu(\text{edges})$; vertices shared: $n-\nu(\text{closure})$ |
| Mirsky | longest chain = min antichain partition; min #non-increasing subsequences = strict LIS |
| Hungarian dual | $u_i+v_j\le c_{ij}$, optimum uses tight cells; $\delta$ step: tree rows $+\delta$, tree cols $-\delta$ |
| Tutte–Berge (🔴) | $\nu=\min_U\frac12(n+\lvert U\rvert-\text{odd}(G-U))$ |

## 3. Signal → model

| Statement | Model |
|---|---|
| assign A's to B's, B has capacity | $s\to A$ (1) $\to B$ (1) $\to t$ (cap) |
| fewest edges/vertices to separate $x,y$ | min cut; vertices → split |
| max routes sharing no edge / vertex | unit max flow / split vertices |
| pick a subset, profits, "needs" rules | closure (project selection) |
| two labels per cell, pay when neighbors differ | segmentation min cut |
| neighbors *should* differ, bipartite grid | flip one color class, then segmentation |
| "minimum rows/columns/segments covering all marks" | König → matching |
| "maximum set with no conflicting pair", bipartite conflicts | $n-\nu$ |
| "every subset of requests has enough resources" | Hall; few types → $2^k$ checks |
| lexicographically smallest assignment | greedy + feasibility (Hall / matching) per tentative choice |
| min chains / workers / trips covering ordered tasks | Dilworth on transitive closure |
| min total cost to ship $k$ units | min-cost $k$-flow |
| at most $k$ disjoint paths maximizing value | split vertices, cost $-w$, Bellman–Ford, stop at non-negative path |
| maximize min / minimize max + assignment | binary search + matching/flow |
| answer after inserting edges one by one | incremental augmenting paths (reverse deletions) |

## 4. Gadgets

| Gadget | Construction |
|---|---|
| undirected edge $c$ | one pair, capacity $c$ both ways |
| vertex capacity $c$ | $v_{in}\to v_{out}$ with $c$; edges enter $v_{in}$, leave $v_{out}$ |
| implication $u\in S\Rightarrow v\in S$ | $u\to v$ with $\infty$ |
| "at least $l$ on an edge" | lower bound transform (§2) |
| choose one of $k$ labels with convex pair costs (🔴) | chain of $k-1$ vertices per item |

## 5. Templates

Dinic (C++).

```cpp
struct Dinic {
    struct E { int to; ll cap; };
    vector<E> e; vector<vector<int>> g; vector<int> lvl, it;
    Dinic(int n) : g(n), lvl(n), it(n) {}
    int addEdge(int u, int v, ll c, ll rc = 0) {
        g[u].push_back(e.size()); e.push_back({v, c});
        g[v].push_back(e.size()); e.push_back({u, rc});
        return (int)e.size() - 2;
    }
    bool bfs(int s, int t) {
        fill(lvl.begin(), lvl.end(), -1); lvl[s] = 0;
        queue<int> q; q.push(s);
        while (!q.empty()) {
            int u = q.front(); q.pop();
            for (int id : g[u]) if (e[id].cap > 0 && lvl[e[id].to] < 0) { lvl[e[id].to] = lvl[u] + 1; q.push(e[id].to); }
        }
        return lvl[t] >= 0;
    }
    ll dfs(int u, int t, ll f) {
        if (u == t) return f;
        ll got = 0;
        for (int &i = it[u]; i < (int)g[u].size(); i++) {
            int id = g[u][i], v = e[id].to;
            if (e[id].cap <= 0 || lvl[v] != lvl[u] + 1) continue;
            ll d = dfs(v, t, min(f - got, e[id].cap));
            if (d == 0) continue;
            e[id].cap -= d; e[id ^ 1].cap += d; got += d;
            if (got == f) return got;
        }
        lvl[u] = -1;
        return got;
    }
    ll maxflow(int s, int t, ll limit = LLONG_MAX) {
        ll flow = 0;
        while (flow < limit && bfs(s, t)) { fill(it.begin(), it.end(), 0); flow += dfs(s, t, limit - flow); }
        return flow;
    }
};
```

Dinic (Java, iterative DFS — no stack issues).

```java
static class Dinic {
    int n, cnt = 0; int[] head, nxt, to, lvl, it, q, stk; long[] cap;
    Dinic(int n, int maxEdges) {
        this.n = n; head = new int[n]; Arrays.fill(head, -1);
        nxt = new int[2 * maxEdges]; to = new int[2 * maxEdges]; cap = new long[2 * maxEdges];
        lvl = new int[n]; it = new int[n]; q = new int[n]; stk = new int[n];
    }
    int addEdge(int u, int v, long c, long rc) {
        to[cnt] = v; cap[cnt] = c; nxt[cnt] = head[u]; head[u] = cnt++;
        to[cnt] = u; cap[cnt] = rc; nxt[cnt] = head[v]; head[v] = cnt++;
        return cnt - 2;
    }
    boolean bfs(int s, int t) {
        Arrays.fill(lvl, -1); int qh = 0, qt = 0; lvl[s] = 0; q[qt++] = s;
        while (qh < qt) { int u = q[qh++]; for (int e = head[u]; e != -1; e = nxt[e]) if (cap[e] > 0 && lvl[to[e]] < 0) { lvl[to[e]] = lvl[u] + 1; q[qt++] = to[e]; } }
        return lvl[t] >= 0;
    }
    long maxflow(int s, int t, long limit) {
        long flow = 0;
        while (flow < limit && bfs(s, t)) {
            System.arraycopy(head, 0, it, 0, n);
            int top = 0, u = s;
            while (flow < limit) {
                if (u == t) {
                    long f = limit - flow; int back = top;
                    for (int i = 0; i < top; i++) f = Math.min(f, cap[stk[i]]);
                    for (int i = top - 1; i >= 0; i--) { cap[stk[i]] -= f; cap[stk[i] ^ 1] += f; if (cap[stk[i]] == 0) back = i; }
                    flow += f; top = back; u = top == 0 ? s : to[stk[top - 1]];
                    continue;
                }
                int e = it[u];
                while (e != -1 && (cap[e] <= 0 || lvl[to[e]] != lvl[u] + 1)) e = nxt[e];
                it[u] = e;
                if (e != -1) { stk[top++] = e; u = to[e]; continue; }
                lvl[u] = -1;
                if (top == 0) break;
                u = to[stk[--top] ^ 1];
            }
        }
        return flow;
    }
}
```

Hopcroft–Karp (C++). For Java use the CSR/iterative version in [03](../12-Flows-and-Matching/03-bipartite-matching-kuhn-hopcroft-karp.md); here is the short Java **Kuhn**.

```cpp
struct HopcroftKarp {
    int nl, nr; vector<vector<int>> adj; vector<int> ml, mr, dist, it;
    HopcroftKarp(int nl, int nr) : nl(nl), nr(nr), adj(nl), ml(nl, -1), mr(nr, -1), dist(nl), it(nl) {}
    void addEdge(int u, int v) { adj[u].push_back(v); }
    bool bfs() {
        queue<int> q;
        for (int u = 0; u < nl; u++) { dist[u] = ml[u] == -1 ? 0 : -1; if (!dist[u]) q.push(u); }
        bool found = false;
        while (!q.empty()) {
            int u = q.front(); q.pop();
            for (int v : adj[u]) { int w = mr[v]; if (w == -1) found = true; else if (dist[w] < 0) { dist[w] = dist[u] + 1; q.push(w); } }
        }
        return found;
    }
    bool dfs(int u) {
        for (int &i = it[u]; i < (int)adj[u].size(); i++) {
            int v = adj[u][i], w = mr[v];
            if (w == -1 || (dist[w] == dist[u] + 1 && dfs(w))) { ml[u] = v; mr[v] = u; return true; }
        }
        dist[u] = -1;
        return false;
    }
    int solve() {
        int res = 0;
        while (bfs()) { fill(it.begin(), it.end(), 0); for (int u = 0; u < nl; u++) if (ml[u] == -1 && dfs(u)) res++; }
        return res;
    }
};
```

```java
static class Kuhn {                      // call from a big-stack Thread if |L| > ~1e4
    int nl, stamp = 0; int[][] adj; int[] ml, mr, vis;
    Kuhn(int nl, int nr, int[][] adj) {
        this.nl = nl; this.adj = adj; ml = new int[nl]; mr = new int[nr]; vis = new int[nl];
        Arrays.fill(ml, -1); Arrays.fill(mr, -1);
    }
    boolean augment(int u) {
        if (vis[u] == stamp) return false;
        vis[u] = stamp;
        for (int v : adj[u]) if (mr[v] == -1 || augment(mr[v])) { ml[u] = v; mr[v] = u; return true; }
        return false;
    }
    int solve() {
        int res = 0;
        for (int u = 0; u < nl; u++) for (int v : adj[u]) if (mr[v] == -1) { ml[u] = v; mr[v] = u; res++; break; }
        for (int u = 0; u < nl; u++) if (ml[u] == -1) { stamp++; if (augment(u)) res++; }
        return res;
    }
}
```

Min-cost flow, successive shortest paths with potentials (C++). `initPotentials` only if some cost is negative; `stopNonNeg` for "any amount of flow".

```cpp
struct MCMF {
    struct E { int to; ll cap, cost; };
    const ll INF = LLONG_MAX / 4;
    int n; vector<E> e; vector<vector<int>> g; vector<ll> pot, dist; vector<int> pe;
    MCMF(int n) : n(n), g(n), pot(n, 0), dist(n), pe(n) {}
    void addEdge(int u, int v, ll cap, ll cost) {
        g[u].push_back(e.size()); e.push_back({v, cap, cost});
        g[v].push_back(e.size()); e.push_back({u, 0, -cost});
    }
    void initPotentials(int s) {
        fill(pot.begin(), pot.end(), INF); pot[s] = 0;
        for (int r = 0; r < n; r++) {
            bool ch = false;
            for (int u = 0; u < n; u++) if (pot[u] < INF)
                for (int id : g[u]) if (e[id].cap > 0 && pot[u] + e[id].cost < pot[e[id].to]) { pot[e[id].to] = pot[u] + e[id].cost; ch = true; }
            if (!ch) break;
        }
        for (auto &p : pot) if (p == INF) p = 0;
    }
    pair<ll, ll> solve(int s, int t, ll maxf = LLONG_MAX, bool stopNonNeg = false) {
        ll flow = 0, cost = 0;
        while (flow < maxf) {
            fill(dist.begin(), dist.end(), INF); dist[s] = 0;
            priority_queue<pair<ll, int>, vector<pair<ll, int>>, greater<>> pq; pq.push({0, s});
            while (!pq.empty()) {
                auto [d, u] = pq.top(); pq.pop();
                if (d > dist[u]) continue;
                for (int id : g[u]) if (e[id].cap > 0) {
                    int v = e[id].to; ll nd = d + e[id].cost + pot[u] - pot[v];
                    if (nd < dist[v]) { dist[v] = nd; pe[v] = id; pq.push({nd, v}); }
                }
            }
            if (dist[t] >= INF) break;
            for (int v = 0; v < n; v++) if (dist[v] < INF) pot[v] += dist[v];
            ll pc = pot[t] - pot[s];
            if (stopNonNeg && pc >= 0) break;
            ll f = maxf - flow;
            for (int v = t; v != s; v = e[pe[v] ^ 1].to) f = min(f, e[pe[v]].cap);
            for (int v = t; v != s; v = e[pe[v] ^ 1].to) { e[pe[v]].cap -= f; e[pe[v] ^ 1].cap += f; }
            flow += f; cost += f * pc;
        }
        return {flow, cost};
    }
};
```

Min-cost flow (Java; `PriorityQueue<long[]>` for brevity — the heap-array version in [04](../12-Flows-and-Matching/04-min-cost-flow.md) is faster).

```java
static class MCMF {
    static final long INF = Long.MAX_VALUE / 4;
    int n, cnt = 0; int[] head, nxt, to, pe; long[] cap, cost, pot, dist;
    MCMF(int n, int maxEdges) {
        this.n = n; head = new int[n]; Arrays.fill(head, -1);
        nxt = new int[2 * maxEdges]; to = new int[2 * maxEdges]; cap = new long[2 * maxEdges]; cost = new long[2 * maxEdges];
        pot = new long[n]; dist = new long[n]; pe = new int[n];
    }
    void addEdge(int u, int v, long c, long w) {
        to[cnt] = v; cap[cnt] = c; cost[cnt] = w; nxt[cnt] = head[u]; head[u] = cnt++;
        to[cnt] = u; cap[cnt] = 0; cost[cnt] = -w; nxt[cnt] = head[v]; head[v] = cnt++;
    }
    long[] solve(int s, int t, long maxf, boolean stopNonNeg) {   // assumes pot is valid (all costs >= 0, or set by Bellman-Ford)
        long flow = 0, total = 0;
        while (flow < maxf) {
            Arrays.fill(dist, INF); dist[s] = 0;
            PriorityQueue<long[]> pq = new PriorityQueue<>((a, b) -> Long.compare(a[0], b[0]));
            pq.add(new long[]{0, s});
            while (!pq.isEmpty()) {
                long[] top = pq.poll(); int u = (int) top[1];
                if (top[0] > dist[u]) continue;
                for (int e = head[u]; e != -1; e = nxt[e]) if (cap[e] > 0) {
                    int v = to[e]; long nd = top[0] + cost[e] + pot[u] - pot[v];
                    if (nd < dist[v]) { dist[v] = nd; pe[v] = e; pq.add(new long[]{nd, v}); }
                }
            }
            if (dist[t] >= INF) break;
            for (int v = 0; v < n; v++) if (dist[v] < INF) pot[v] += dist[v];
            long pc = pot[t] - pot[s];
            if (stopNonNeg && pc >= 0) break;
            long f = maxf - flow;
            for (int v = t; v != s; v = to[pe[v] ^ 1]) f = Math.min(f, cap[pe[v]]);
            for (int v = t; v != s; v = to[pe[v] ^ 1]) { cap[pe[v]] -= f; cap[pe[v] ^ 1] += f; }
            flow += f; total += f * pc;
        }
        return new long[]{flow, total};
    }
}
```

Hungarian, $n\le m$, minimize (C++ and Java).

```cpp
pair<ll, vector<int>> hungarian(const vector<vector<ll>> &c) {
    int n = c.size(), m = c[0].size();
    const ll INF = LLONG_MAX / 4;
    vector<ll> u(n + 1), v(m + 1);
    vector<int> rowOf(m + 1, 0), way(m + 1, 0);
    for (int i = 1; i <= n; i++) {
        rowOf[0] = i; int j0 = 0;
        vector<ll> minv(m + 1, INF); vector<char> in(m + 1, 0);
        do {
            in[j0] = 1; int i0 = rowOf[j0], j1 = 0; ll delta = INF;
            for (int j = 1; j <= m; j++) if (!in[j]) {
                ll cur = c[i0 - 1][j - 1] - u[i0] - v[j];
                if (cur < minv[j]) { minv[j] = cur; way[j] = j0; }
                if (minv[j] < delta) { delta = minv[j]; j1 = j; }
            }
            for (int j = 0; j <= m; j++) if (in[j]) { u[rowOf[j]] += delta; v[j] -= delta; } else minv[j] -= delta;
            j0 = j1;
        } while (rowOf[j0] != 0);
        do { int j1 = way[j0]; rowOf[j0] = rowOf[j1]; j0 = j1; } while (j0);
    }
    vector<int> colOf(n);
    for (int j = 1; j <= m; j++) if (rowOf[j]) colOf[rowOf[j] - 1] = j - 1;
    ll cost = 0;
    for (int i = 0; i < n; i++) cost += c[i][colOf[i]];
    return {cost, colOf};
}
```

```java
static long hungarian(long[][] c, int[] colOf) {      // returns min cost, fills colOf (length n)
    int n = c.length, m = c[0].length;
    final long INF = Long.MAX_VALUE / 4;
    long[] u = new long[n + 1], v = new long[m + 1], minv = new long[m + 1];
    int[] rowOf = new int[m + 1], way = new int[m + 1];
    boolean[] in = new boolean[m + 1];
    for (int i = 1; i <= n; i++) {
        rowOf[0] = i; int j0 = 0;
        Arrays.fill(minv, INF); Arrays.fill(in, false);
        do {
            in[j0] = true; int i0 = rowOf[j0], j1 = 0; long delta = INF;
            for (int j = 1; j <= m; j++) if (!in[j]) {
                long cur = c[i0 - 1][j - 1] - u[i0] - v[j];
                if (cur < minv[j]) { minv[j] = cur; way[j] = j0; }
                if (minv[j] < delta) { delta = minv[j]; j1 = j; }
            }
            for (int j = 0; j <= m; j++) if (in[j]) { u[rowOf[j]] += delta; v[j] -= delta; } else minv[j] -= delta;
            j0 = j1;
        } while (rowOf[j0] != 0);
        do { int j1 = way[j0]; rowOf[j0] = rowOf[j1]; j0 = j1; } while (j0 != 0);
    }
    for (int j = 1; j <= m; j++) if (rowOf[j] != 0) colOf[rowOf[j] - 1] = j - 1;
    long cost = 0;
    for (int i = 0; i < n; i++) cost += c[i][colOf[i]];
    return cost;
}
```

## 6. Edge cases and constants

| Item | Value / rule |
|---|---|
| INF capacity | $\ge\sum$ finite capacities $+1$; with `ll`, $10^{18}$ is safe only if INF edges are never summed into a cut you subtract from |
| Hungarian BIG (forbidden) | $> n\cdot\max c$, and $n\cdot\text{BIG} < 9.2\cdot10^{18}$ (e.g. $10^{12}$ for $c\le10^6$, $n\le500$) |
| Max flow with $V=10^4$, $E=10^5$ | Dinic ≪ 1 s |
| Matching with $E=10^6$ | Hopcroft–Karp (Kuhn may TLE) |
| MCMF iterations | $\le F$ (flow value) Dijkstras |
| Java stack | recursive Kuhn/Dinic deeper than ~$10^4$ → `new Thread(null, r, "", 1 << 27)` |

## 7. Top 10 mistakes

1. Single edges instead of pairs → `i ^ 1` points to the wrong edge.
2. Current-arc pointer reset inside DFS (or never) → TLE / wrong.
3. Using an exhausted network again in a binary search without rebuilding.
4. Forgetting $\infty$ on split edges of $s$ and $t$ (answer capped at 1).
5. Project selection: subtracting from the sum of *all* profits instead of positive ones.
6. Path cover with shared vertices without the transitive closure (or Dilworth on a non-transitive relation).
7. König/independent-set formulas on a non-bipartite graph.
8. Min-cost flow with negative costs but zero initial potentials → Dijkstra wrong.
9. Reporting `dist[t]` (reduced) instead of `pot[t] - pot[s]` as the path cost.
10. Lower bounds: forgetting $t\to s$, or forgetting to delete it before maximizing.

## 8. Last-minute before the contest

- Paste-ready: Dinic (both languages), Hopcroft–Karp, MCMF, Hungarian — compiled once on a sample.
- For every flow idea, write in one line: *what is one unit of flow?* or *what does $v\in S$ mean?*
- Check the network size: $V$, $E$ including reverse edges, and the flow value bound $F$ for MCMF.
- Before printing a certificate (cut, cover, antichain), re-derive it from the residual graph — never from the original graph.
- If $n\le 20$: bitmask DP may be simpler than any flow.
- If $n\ge 2\cdot10^5$ and the "network" is a line or a tree: look for the greedy/DP that computes the min cut directly.
