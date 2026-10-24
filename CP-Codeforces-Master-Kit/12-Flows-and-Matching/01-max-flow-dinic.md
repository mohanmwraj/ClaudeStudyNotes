# Maximum Flow: Residual Graphs, Ford–Fulkerson, Edmonds–Karp and Dinic

> **Band:** 🟣 1900–2400 · **Priority:** 🔥 (Dinic, max-flow min-cut) · ⚡ (Edmonds–Karp) · 🧊 (capacity scaling, push–relabel) · **FAANG:** low · **Prerequisites:** [BFS/DFS](../09-Graphs/01-graph-representation-bfs-dfs.md), [shortest paths](../09-Graphs/02-shortest-paths.md)
> **You can say you know this when:** you can write Dinic from memory in C++ and Java in under ten minutes, prove max-flow = min-cut from scratch, and explain why Dinic needs at most $V-1$ phases and why one phase costs $O(VE)$.

## 1. First principles — why this works

**The problem.** A *network* is a directed graph $G=(V,E)$ with a capacity $c(u,v)\ge 0$ on every edge, a source $s$ and a sink $t$.
A *flow* assigns $f(u,v)$ to every edge with

- capacity: $0 \le f(u,v) \le c(u,v)$,
- conservation: for every $v \ne s,t$, flow in = flow out.

The value $|f|$ is the net flow leaving $s$. We want the maximum value. Think of water pipes, or better, think of $|f|$ as **the number of unit "tokens" that can travel from $s$ to $t$ simultaneously without exceeding any edge's capacity** — that view is what makes flows a modeling tool (see [modeling](02-min-cut-and-flow-modeling.md)).

**The naive greedy and why it fails.** "Find any $s$–$t$ path with spare capacity, push as much as possible, repeat." Take the diamond
$s\to a,\ s\to b,\ a\to b,\ a\to t,\ b\to t$, all capacity 1. If the first path chosen is $s\to a\to b\to t$, then $s\to a$ and $b\to t$ are full and no other
path has spare capacity; greedy stops at 1, but the optimum is 2 ($s\to a\to t$, $s\to b\to t$). The greedy committed to $a\to b$ and has no way to change its mind.

**The fix: allow undoing.** Sending flow back along $a\to b$ is the same as cancelling some of it. So define the **residual graph** $G_f$: for every edge $(u,v)$,

- a forward residual edge $u\to v$ with residual capacity $c(u,v)-f(u,v)$,
- a backward residual edge $v\to u$ with residual capacity $f(u,v)$.

An **augmenting path** is an $s$–$t$ path in $G_f$ using only positive residual capacities. Pushing $\delta$ along it keeps capacity and conservation valid
(every inner vertex gains $\delta$ in and $\delta$ out) and increases $|f|$ by $\delta$. In the diamond, after the bad first path the residual graph has
$s\to b\to a\to t$ (using the backward edge $b\to a$), which reroutes: the final flow uses $s\to a\to t$ and $s\to b\to t$.

**When can we stop? Cuts.** An $s$–$t$ cut is a partition $V=S\cup T$ with $s\in S,\ t\in T$; its capacity $c(S,T)$ is the sum of capacities of edges from $S$ to $T$
(edges from $T$ to $S$ do not count). For any flow and any cut,

$$|f| = f(S\to T) - f(T\to S) \le c(S,T),$$

because the net flow across any cut equals the flow leaving $s$ (sum conservation over all vertices of $S$). So every cut is an upper bound for every flow.

**Max-flow min-cut theorem.** The following are equivalent: (1) $f$ is a maximum flow; (2) $G_f$ has no augmenting path; (3) $|f| = c(S,T)$ for some cut.
(1)⇒(2): an augmenting path would increase $|f|$. (3)⇒(1): no flow can beat a cut. (2)⇒(3): let $S$ be the set of vertices reachable from $s$ in $G_f$;
$t\notin S$. Every original edge $S\to T$ must be saturated (otherwise its forward residual edge would extend $S$), and every edge $T\to S$ must carry zero flow
(otherwise its backward residual edge would extend $S$). Plug into the identity above: $|f| = c(S,T) - 0$. ∎

This proof is also an algorithm for **finding a minimum cut**: after any max-flow algorithm, BFS from $s$ along positive residual edges; the visited set is $S$.

**Integrality.** If all capacities are integers, every augmentation pushes an integer amount, so the final flow is integral. Hence *some maximum flow is integral*.
This is the single most important modeling fact: "each student gets one project" can be written as capacity 1 and the solver will never split a student in half.

**Ford–Fulkerson** = "augment along any path until none exists". With integer capacities it terminates after at most $|f^*|$ augmentations, $O(E\,|f^*|)$ total.
That can be terrible: a 4-vertex graph with capacities $10^9$ and a middle edge of capacity 1 can force $2\cdot 10^9$ augmentations if paths alternate through the middle edge.
(With irrational capacities it may not even terminate.)

**Edmonds–Karp** = always augment along a *shortest* (fewest edges) path, found by BFS. Two facts give $O(VE^2)$:

1. The BFS distance $d_f(s,v)$ never decreases. Augmenting along a shortest path only creates backward edges $v\to u$ with $d(v) = d(u)+1$, which go *down* one
   layer and can never create a shortcut.
2. An edge $(u,v)$ is *critical* (saturated by the augmentation) only when $d(v)=d(u)+1$. Before it can be critical again, flow must go back along $v\to u$,
   which needs $d'(u) = d'(v)+1 \ge d(v)+1 = d(u)+2$. So $d(u)$ grows by 2 between criticalities, at most $V/2$ times per edge. Each augmentation has a critical edge,
   so there are $O(VE)$ augmentations of cost $O(E)$ each.

**Dinic: all shortest paths of one length at once.** Edmonds–Karp wastes time recomputing BFS after every single path. Dinic computes BFS levels once,
keeps only edges $u\to v$ with $\text{level}(v)=\text{level}(u)+1$ (the **level graph**, a DAG containing exactly the shortest augmenting paths), and pushes a
**blocking flow**: a flow in the level graph after which every $s$–$t$ path in it has a saturated edge.

- *Phases are few.* After a blocking flow, every remaining augmenting path must use an edge that was not in the level graph (a backward edge or a "flat/backward" edge),
  so $d(s,t)$ strictly increases. Distances are at most $V-1$, so there are at most $V-1$ phases.
- *A phase is cheap.* Use a DFS with a **current-arc pointer** `it[u]`: the next edge of $u$ worth trying. When an edge leads to a dead end or gets saturated, advance the pointer
  permanently — within this phase that edge can never become useful again (levels are fixed and residual capacity in the level graph only decreases). Each augmenting path costs
  $O(V)$ edges walked plus pointer advances; each path saturates at least one edge, so at most $E$ paths, and the pointer advances total $O(E)$. One phase is $O(VE)$, all phases $O(V^2E)$.
- *Unit networks.* If every capacity is 1, a phase costs only $O(E)$ (every edge on a found path is saturated and abandoned), and after $\sqrt V$ phases the remaining flow
  is at most $\sqrt V$ (in a unit network where each vertex has in-degree 1 or out-degree 1, residual paths are vertex-disjoint and each has length $\ge \sqrt V$),
  so only $\sqrt V$ more phases happen: $O(E\sqrt V)$. Bipartite matching is exactly such a network — this is Hopcroft–Karp (see [matching](03-bipartite-matching-kuhn-hopcroft-karp.md)).

**In practice** Dinic is far faster than $O(V^2E)$ on contest graphs: $10^4$ vertices and $10^5$ edges is routine. Problem setters almost always design flow problems so Dinic passes.

**Capacity scaling (🧊).** Only augment along paths whose bottleneck is at least $\Delta$; halve $\Delta$ from the highest power of two $\le C$. Each scale has $O(E)$ augmentations,
giving $O(E^2\log C)$ with BFS, or $O(VE\log C)$ with Dinic inside each scale. Rarely needed.

**Push–relabel (🧊).** Instead of paths, keep a *preflow* (vertices may hold excess) and *heights*; push excess downhill, relabel a vertex when stuck. FIFO selection is $O(V^3)$,
highest-label with gap heuristics $O(V^2\sqrt E)$. It wins on some dense adversarial graphs; know it exists, learn it after Master.

## 2. Formulas, definitions and identities

| Object | Formula | Meaning / proof sketch |
|---|---|---|
| Flow value | $\lvert f\rvert = \sum_v f(s,v) - \sum_v f(v,s)$ | net out of the source |
| Residual capacity | $c_f(u,v) = c(u,v) - f(u,v) + f(v,u)$ | spare forward capacity plus cancellable backward flow |
| Cut capacity | $c(S,T) = \sum_{u\in S, v\in T} c(u,v)$ | only edges leaving $S$ count |
| Flow across a cut | $\lvert f\rvert = f(S\to T) - f(T\to S)$ | sum the conservation equations over $S$ |
| Weak duality | $\lvert f\rvert \le c(S,T)$ for every flow and cut | from the previous line and $0\le f\le c$ |
| Max-flow min-cut | $\max_f \lvert f\rvert = \min_{(S,T)} c(S,T)$ | residual reachability proof above |
| Integrality | integer $c$ ⇒ an integral max flow exists | every augmentation is integral |
| Flow decomposition | any flow = at most $E$ path flows + cycle flows | repeatedly peel a path/cycle through positive edges, each peel zeroes an edge |
| Path count bound | Edmonds–Karp augmentations $\le VE/2$ | each edge critical $\le V/2$ times |
| Dinic phases | $\le V-1$ | $d_f(s,t)$ strictly increases per phase |

Complexities:

| Algorithm | Time | When |
|---|---|---|
| Ford–Fulkerson (DFS) | $O(E\,\lvert f^*\rvert)$ | tiny flow values only |
| Edmonds–Karp | $O(VE^2)$ | teaching; small graphs |
| Dinic | $O(V^2E)$ worst, fast in practice | default choice |
| Dinic, unit capacities | $O(E\min(\sqrt E, V^{2/3}))$ | edge-disjoint paths |
| Dinic, unit network (bipartite matching) | $O(E\sqrt V)$ | matching, vertex-disjoint paths |
| Capacity scaling (🧊) | $O(E^2\log C)$ | huge capacities, few edges |
| Push–relabel FIFO / highest label (🧊) | $O(V^3)$ / $O(V^2\sqrt E)$ | dense graphs |

**Storage trick.** Store edges in an array in pairs: edge $2k$ is the forward edge and $2k+1$ its reverse, so `rev(i) = i ^ 1`. Pushing $\delta$ on edge $i$:
`cap[i] -= δ; cap[i ^ 1] += δ`. An undirected edge of capacity $c$ is one pair with capacity $c$ in *both* directions.

## 3. Implementation (C++ and Java)

Dinic with current-arc pointers and an optional `limit` (stop once that much flow is found — useful for "is the flow at least $x$?").
`minCutSide(s)` after `maxflow` returns the source side $S$ of a minimum cut. The C++ DFS is recursive (depth $\le$ number of levels $\le V$);
the Java DFS is iterative with an explicit edge stack, so it is safe on Java's default stack.

```cpp
struct Dinic {
    struct E { int to; ll cap; };
    vector<E> e;                 // e[i] and e[i ^ 1] are a forward/reverse pair
    vector<vector<int>> g;
    vector<int> lvl, it;
    Dinic(int n) : g(n), lvl(n), it(n) {}
    int addEdge(int u, int v, ll c, ll rc = 0) {      // rc = c for an undirected edge
        g[u].push_back(e.size()); e.push_back({v, c});
        g[v].push_back(e.size()); e.push_back({u, rc});
        return (int)e.size() - 2;                      // id of the forward edge
    }
    bool bfs(int s, int t) {
        fill(lvl.begin(), lvl.end(), -1);
        lvl[s] = 0;
        queue<int> q; q.push(s);
        while (!q.empty()) {
            int u = q.front(); q.pop();
            for (int id : g[u])
                if (e[id].cap > 0 && lvl[e[id].to] < 0) { lvl[e[id].to] = lvl[u] + 1; q.push(e[id].to); }
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
            if (got == f) return got;                  // do not advance: this edge may have capacity left
        }
        lvl[u] = -1;                                   // u is dead for the rest of this phase
        return got;
    }
    ll maxflow(int s, int t, ll limit = LLONG_MAX) {
        ll flow = 0;
        while (flow < limit && bfs(s, t)) {
            fill(it.begin(), it.end(), 0);
            flow += dfs(s, t, limit - flow);           // one call pushes a whole blocking flow
        }
        return flow;
    }
    vector<char> minCutSide(int s) {                   // call after maxflow
        vector<char> vis(g.size(), 0);
        queue<int> q; q.push(s); vis[s] = 1;
        while (!q.empty()) {
            int u = q.front(); q.pop();
            for (int id : g[u]) if (e[id].cap > 0 && !vis[e[id].to]) { vis[e[id].to] = 1; q.push(e[id].to); }
        }
        return vis;
    }
};
```

```java
static class Dinic {
    int n, cnt = 0;
    int[] head, nxt, to, lvl, it, q, stk;
    long[] cap;
    Dinic(int n, int maxEdges) {
        this.n = n;
        head = new int[n]; Arrays.fill(head, -1);
        nxt = new int[2 * maxEdges]; to = new int[2 * maxEdges]; cap = new long[2 * maxEdges];
        lvl = new int[n]; it = new int[n]; q = new int[n]; stk = new int[n];
    }
    int addEdge(int u, int v, long c, long rc) {       // rc = c for an undirected edge
        to[cnt] = v; cap[cnt] = c; nxt[cnt] = head[u]; head[u] = cnt++;
        to[cnt] = u; cap[cnt] = rc; nxt[cnt] = head[v]; head[v] = cnt++;
        return cnt - 2;
    }
    boolean bfs(int s, int t) {
        Arrays.fill(lvl, -1);
        int qh = 0, qt = 0;
        lvl[s] = 0; q[qt++] = s;
        while (qh < qt) {
            int u = q[qh++];
            for (int e = head[u]; e != -1; e = nxt[e])
                if (cap[e] > 0 && lvl[to[e]] < 0) { lvl[to[e]] = lvl[u] + 1; q[qt++] = to[e]; }
        }
        return lvl[t] >= 0;
    }
    long maxflow(int s, int t, long limit) {
        long flow = 0;
        while (flow < limit && bfs(s, t)) {
            System.arraycopy(head, 0, it, 0, n);
            int top = 0, u = s;                         // stk[0..top) = edges of the current path
            while (flow < limit) {
                if (u == t) {
                    long f = limit - flow;
                    for (int i = 0; i < top; i++) f = Math.min(f, cap[stk[i]]);
                    int back = top;
                    for (int i = top - 1; i >= 0; i--) {
                        cap[stk[i]] -= f; cap[stk[i] ^ 1] += f;
                        if (cap[stk[i]] == 0) back = i;     // first saturated edge on the path
                    }
                    flow += f;
                    top = back;                             // retreat to the tail of that edge
                    u = top == 0 ? s : to[stk[top - 1]];
                    continue;
                }
                int e = it[u];
                while (e != -1 && (cap[e] <= 0 || lvl[to[e]] != lvl[u] + 1)) e = nxt[e];
                it[u] = e;
                if (e != -1) { stk[top++] = e; u = to[e]; continue; }
                lvl[u] = -1;                                // dead end for this phase
                if (top == 0) break;
                u = to[stk[--top] ^ 1];
            }
        }
        return flow;
    }
    boolean[] minCutSide(int s) {                       // call after maxflow
        boolean[] vis = new boolean[n];
        int qh = 0, qt = 0;
        q[qt++] = s; vis[s] = true;
        while (qh < qt) {
            int u = q[qh++];
            for (int e = head[u]; e != -1; e = nxt[e]) if (cap[e] > 0 && !vis[to[e]]) { vis[to[e]] = true; q[qt++] = to[e]; }
        }
        return vis;
    }
}
```

Edmonds–Karp on a capacity matrix — not for contests, but it is the shortest correct max-flow program and a good brute force for stress tests.

```cpp
ll edmondsKarp(vector<vector<ll>> cap, int s, int t) {   // cap is copied: it becomes the residual matrix
    int n = cap.size();
    ll flow = 0;
    while (true) {
        vector<int> par(n, -1);
        par[s] = s;
        queue<int> q; q.push(s);
        while (!q.empty() && par[t] < 0) {
            int u = q.front(); q.pop();
            for (int v = 0; v < n; v++) if (par[v] < 0 && cap[u][v] > 0) { par[v] = u; q.push(v); }
        }
        if (par[t] < 0) return flow;
        ll f = LLONG_MAX;
        for (int v = t; v != s; v = par[v]) f = min(f, cap[par[v]][v]);
        for (int v = t; v != s; v = par[v]) { cap[par[v]][v] -= f; cap[v][par[v]] += f; }
        flow += f;
    }
}
```

```java
static long edmondsKarp(long[][] capIn, int s, int t) {
    int n = capIn.length;
    long[][] cap = new long[n][];
    for (int i = 0; i < n; i++) cap[i] = capIn[i].clone();
    long flow = 0;
    while (true) {
        int[] par = new int[n];
        Arrays.fill(par, -1);
        par[s] = s;
        ArrayDeque<Integer> q = new ArrayDeque<>();
        q.add(s);
        while (!q.isEmpty() && par[t] < 0) {
            int u = q.poll();
            for (int v = 0; v < n; v++) if (par[v] < 0 && cap[u][v] > 0) { par[v] = u; q.add(v); }
        }
        if (par[t] < 0) return flow;
        long f = Long.MAX_VALUE;
        for (int v = t; v != s; v = par[v]) f = Math.min(f, cap[par[v]][v]);
        for (int v = t; v != s; v = par[v]) { cap[par[v]][v] -= f; cap[v][par[v]] += f; }
        flow += f;
    }
}
```

## 4. Recognising the pattern

| Signal in the statement | Think |
|---|---|
| "assign each A to at most one B", capacities on B, "maximum number assigned" | bipartite flow $s\to A\to B\to t$; unit capacities on the $A$ side |
| "maximum number of paths that share no edge / no vertex" | max flow with unit edge caps / split vertices (Menger) |
| "minimum number of edges/vertices to remove so that $x$ cannot reach $y$" | min cut = max flow |
| "each item may be used at most $k$ times", "a resource with limit" | an edge with capacity $k$ |
| small $n$ (≤ 200–5000), $m$ ≤ $10^4$–$10^5$, and no obvious greedy | flow is plausible; check the network size |
| "is it possible that all demands are met?" | saturating flow: max flow $=\sum$ demands |
| "maximize the minimum…/ minimize the maximum…" with a feasibility check that is an assignment | binary search the answer + flow (Delivery Bears, Valuable Paper) |
| profits and costs with "if you take X you must take Y" | min cut / closure — [modeling](02-min-cut-and-flow-modeling.md) |

Often confused with: **greedy matching on a line** (intervals, sorted values — an exchange argument beats flow), **shortest path** (min cut is about *capacity*, not length),
and **DP on a path/tree** (flow on a tree or a line usually collapses to a greedy or DP). If $n$ is $2\cdot10^5$ and the structure is special, the intended solution is
usually a greedy that *simulates* a flow, justified by max-flow min-cut (e.g. "answer = min over windows of the window sum").

## 5. Worked examples (graded)

### Example 1 — Download Speed  ·  ★ ≈1700

- **Source:** [CSES 1694 · Download Speed](https://cses.fi/problemset/task/1694)
- **Difficulty:** ≈1700 (est.)
- **Problem:** $n\le 500$ computers and $m\le 1000$ directed connections, each with a speed (capacity) up to $10^9$. Data flows from computer 1 to computer $n$;
  print the maximum total speed.
- **Thinking from first principles:** this is literally maximum flow. The only traps are the value range (sums of $10^9$ exceed 32 bits) and parallel edges
  (just add them as separate edges — the residual logic handles them).

<details><summary>Solution</summary>

Run Dinic from vertex 0 to vertex $n-1$ with 64-bit capacities. $O(V^2E)$ worst case, instant at this size.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

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

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    Dinic d(n);
    for (int i = 0; i < m; i++) {
        int a, b; ll c;
        cin >> a >> b >> c;
        d.addEdge(a - 1, b - 1, c);
    }
    cout << d.maxflow(0, n - 1) << "\n";
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
    static int nextInt() throws IOException { return (int) nextLong(); }

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

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt();
        Dinic d = new Dinic(n, m);
        for (int i = 0; i < m; i++) {
            int a = nextInt() - 1, b = nextInt() - 1;
            long c = nextLong();
            d.addEdge(a, b, c, 0);
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(d.maxflow(0, n - 1, Long.MAX_VALUE));
        out.flush();
    }
}
```

</details>

<!-- test
in:
4 5
1 2 3
2 4 2
1 3 4
3 4 5
4 1 3
out:
6
-->
<!-- test
in:
4 5
1 2 1
1 3 1
2 3 1
2 4 1
3 4 1
out:
2
-->
<!-- test
in:
3 1
1 2 5
out:
0
-->
<!-- test
in:
2 3
1 2 1000000000
1 2 1000000000
2 1 7
out:
2000000000
-->

### Example 2 — Supervised projects (capacities on two levels)  ·  ★ ≈1900

- **Source:** Original problem.
- **Difficulty:** ≈1900 (est.)
- **Problem:** $n$ students, $k$ projects, $p$ professors ($n,k,p\le 300$). Project $j$ accepts at most $c_j$ students and belongs to professor $o_j$;
  professor $q$ can supervise at most $d_q$ students in total over all of their projects. Student $i$ lists the projects acceptable to them. Each student joins
  at most one project. Print the maximum number of students that can be placed.
- **Thinking from first principles:** a greedy "give each student the least popular acceptable project" fails as soon as two levels of capacity interact (a student
  may need to be moved to free a professor's slot). Think of every placed student as one unit of flow travelling *student → project → professor*. Every
  constraint is "at most so many units pass through here", i.e. a capacity: 1 on the student, $c_j$ on the project, $d_q$ on the professor.
  Integrality guarantees an integral optimum, and flow decomposition turns it back into an assignment.

<details><summary>Solution</summary>

Vertices: $s$, students, projects, professors, $t$. Edges: $s\to i$ (cap 1), $i\to j$ for each acceptable project (cap 1), $j\to o_j$ (cap $c_j$),
$q\to t$ (cap $d_q$). Answer = max flow. Correctness: a valid placement gives a flow of the same value (send one unit along each placed student's path);
an integral flow sends 0 or 1 unit out of each student, and the unit's path names the project; the capacities are exactly the constraints.
Size: $V = n+k+p+2$, $E \le n + \sum t_i + k + p$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

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

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, k, p;
    cin >> n >> k >> p;
    // ids: s = 0, students 1..n, projects n+1..n+k, professors n+k+1..n+k+p, t = n+k+p+1
    int s = 0, t = n + k + p + 1;
    Dinic d(t + 1);
    vector<int> c(k), o(k);
    for (auto &x : c) cin >> x;
    for (auto &x : o) cin >> x;
    for (int j = 0; j < k; j++) d.addEdge(n + 1 + j, n + k + o[j], c[j]);
    for (int q = 1; q <= p; q++) { int dq; cin >> dq; d.addEdge(n + k + q, t, dq); }
    for (int i = 1; i <= n; i++) {
        d.addEdge(s, i, 1);
        int cnt; cin >> cnt;
        while (cnt--) { int j; cin >> j; d.addEdge(i, n + j, 1); }
    }
    cout << d.maxflow(s, t) << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
    static int nextInt() throws IOException {
        int b = in.read();
        while (b != '-' && (b < '0' || b > '9')) b = in.read();
        boolean neg = b == '-';
        if (neg) b = in.read();
        int r = 0;
        while (b >= '0' && b <= '9') { r = r * 10 + (b - '0'); b = in.read(); }
        return neg ? -r : r;
    }

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

    public static void main(String[] args) throws IOException {
        int n = nextInt(), k = nextInt(), p = nextInt();
        int s = 0, t = n + k + p + 1;
        int[] c = new int[k], o = new int[k];
        for (int j = 0; j < k; j++) c[j] = nextInt();
        for (int j = 0; j < k; j++) o[j] = nextInt();
        int[] dq = new int[p + 1];
        for (int q = 1; q <= p; q++) dq[q] = nextInt();
        int[][] lists = new int[n + 1][];
        int edges = k + p + n;
        for (int i = 1; i <= n; i++) {
            int cnt = nextInt();
            lists[i] = new int[cnt];
            for (int x = 0; x < cnt; x++) lists[i][x] = nextInt();
            edges += cnt;
        }
        Dinic d = new Dinic(t + 1, edges);
        for (int j = 0; j < k; j++) d.addEdge(n + 1 + j, n + k + o[j], c[j], 0);
        for (int q = 1; q <= p; q++) d.addEdge(n + k + q, t, dq[q], 0);
        for (int i = 1; i <= n; i++) {
            d.addEdge(s, i, 1, 0);
            for (int j : lists[i]) d.addEdge(i, n + j, 1, 0);
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(d.maxflow(s, t, Long.MAX_VALUE));
        out.flush();
    }
}
```

</details>

In the first test, professor 1 owns projects 1 and 2 but can take only 2 students, so at most 2 + 1 = 3 students are placed even though the projects have 4 seats.

<!-- test
in:
4 3 2
2 2 1
1 1 2
2 1
2 1 2
1 1
1 2
2 1 3
out:
3
-->
<!-- test
in:
1 1 1
1
1
5
0
out:
0
-->
<!-- test
in:
3 2 2
3 3
1 2
0 3
1 1
1 1
2 1 2
out:
1
-->

### Example 3 — Delivery Bears  ·  ★ 2200

- **Source:** [CF 653D · Delivery Bears](https://codeforces.com/problemset/problem/653/D) — 2200
- **Difficulty:** 2200
- **Problem:** a directed graph with $n\le 50$ vertices and $m\le 500$ edges; edge $e$ can carry total weight at most $c_e\le 10^6$. Exactly $x\le 10^5$ bears
  each walk a simple path from 1 to $n$ and every bear carries the same weight $w$; the total weight on an edge (bears using it times $w$) may not exceed $c_e$.
  Maximize the total delivered weight $x\cdot w$ (real number, $10^{-6}$ precision). A path from 1 to $n$ exists.
- **Thinking from first principles:** for a fixed $w$, an edge can host at most $\lfloor c_e/w\rfloor$ bears; bears are units of flow, so $w$ is feasible iff
  the max flow with capacities $\lfloor c_e/w\rfloor$ is at least $x$ (cycles in a flow decomposition can be dropped, so paths are simple).
  Feasibility is monotone in $w$ (smaller $w$ only increases capacities), so binary search $w$. Dead end to avoid: binary searching the *total* weight and splitting
  it as a flow — the bears are indivisible units, the per-bear weight is the right parameter.

<details><summary>Solution</summary>

Binary search $w\in(0, \max c]$ for 100 iterations. In each check, build the network with capacity $\min(x, \lfloor c_e/w\rfloor)$ (capping by $x$ avoids
huge numbers when $w$ is tiny) and run Dinic with `limit = x`. Print $x\cdot w$. Complexity $100\cdot O(V^2E)$ with tiny constants.
Precision: after 100 halvings the interval is far below $10^{-6}$ relative; the floor function is the only discontinuity and the binary search converges to it from below.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

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

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m; ll x;
    cin >> n >> m >> x;
    vector<int> a(m), b(m); vector<ll> c(m);
    for (int i = 0; i < m; i++) { cin >> a[i] >> b[i] >> c[i]; a[i]--; b[i]--; }
    auto feasible = [&](double w) {
        Dinic d(n);
        for (int i = 0; i < m; i++) d.addEdge(a[i], b[i], (ll)min<double>((double)x, floor(c[i] / w)));
        return d.maxflow(0, n - 1, x) >= x;
    };
    double lo = 0, hi = *max_element(c.begin(), c.end());
    for (int it = 0; it < 100; it++) {
        double mid = (lo + hi) / 2;
        if (feasible(mid)) lo = mid; else hi = mid;
    }
    cout << fixed << setprecision(10) << lo * x << "\n";
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
    static int nextInt() throws IOException { return (int) nextLong(); }

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

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt();
        long x = nextLong();
        int[] a = new int[m], b = new int[m];
        long[] c = new long[m];
        long mx = 0;
        for (int i = 0; i < m; i++) { a[i] = nextInt() - 1; b[i] = nextInt() - 1; c[i] = nextLong(); mx = Math.max(mx, c[i]); }
        double lo = 0, hi = mx;
        for (int iter = 0; iter < 100; iter++) {
            double mid = (lo + hi) / 2;
            Dinic d = new Dinic(n, m);
            for (int i = 0; i < m; i++) d.addEdge(a[i], b[i], (long) Math.min((double) x, Math.floor(c[i] / mid)), 0);
            if (d.maxflow(0, n - 1, x) >= x) lo = mid; else hi = mid;
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.printf("%.10f%n", lo * x);
        out.flush();
    }
}
```

</details>

Hand checks: one edge of capacity 10 and 3 bears → 10. Two disjoint paths with bottlenecks 1 and 3 bears → each path takes $\lfloor 1/w\rfloor$ bears,
so $w = 1/2$ and the total is 1.5. With one bear the answer is the widest-path bottleneck. Parallel edges 7 and 3 with 5 bears: $\lfloor 7/w\rfloor+\lfloor 3/w\rfloor\ge 5$
holds up to $w=7/4$, total $8.75$.

<!-- test
in:
2 1 3
1 2 10
out:
10.0000000000
-->
<!-- test
in:
4 4 3
1 2 2
2 4 1
1 3 1
3 4 2
out:
1.5000000000
-->
<!-- test
in:
3 3 1
1 2 5
2 3 3
1 3 4
out:
4.0000000000
-->
<!-- test
in:
2 2 5
1 2 7
1 2 3
out:
8.7500000000
-->

## 6. Tricks, pitfalls and things to remember

1. **Edges in pairs from index 0.** `rev(i) = i ^ 1` only works if the first edge has index 0 and you never insert a single edge. Every `addEdge` adds exactly two.
2. **Undirected edge = one pair with capacity $c$ both ways.** Two separate directed pairs also work but double memory and can confuse cut extraction.
3. **Reset the current-arc pointers every phase**, never inside the DFS. Forgetting `it[u]` (or resetting it per DFS call) turns Dinic into exponential-ish Ford–Fulkerson → TLE.
4. **Do not advance the current arc when you return early** because the demand `f` is satisfied: that edge may still have residual capacity.
5. **Overflow.** Use 64-bit capacities. "Infinite" capacity: pick something like $10^{18}$ only if no sum of INF edges is ever added; safer is $\sum$ of all finite capacities $+1$.
6. **Rebuild or reset the network for each binary-search check** — `maxflow` destroys capacities. Keep the original capacities in an array if you want to reset in place.
7. **Java recursion.** A recursive DFS of depth $V$ (e.g. $V=10^4$ on a long chain) can overflow Java's default stack; use the iterative version or run in a
   `Thread` with a 256 MB stack. `ArrayList<int[]>` adjacency in Java is 2–4× slower than the `head/nxt/to` arrays.
8. **Count vertices correctly** when you add layers ($s$, $t$, split copies): an off-by-one silently connects two different layers.
9. **Floating capacities** need an epsilon in `cap > eps`; prefer scaling to integers (Delivery Bears floors to integers instead).
10. **Max flow with a limit** (`maxflow(s, t, k)`) is the clean way to answer "can we route at least $k$?" and also speeds up binary searches.
11. **Dinic is fast in practice but not magic**: on $10^6$ edges with large capacities, consider the problem's structure (often a greedy is intended) before coding flow.

## 7. Going further (toward 2400–2600+)

- **Min cut modeling** is where the hard problems live: closures, vertex splitting, lower bounds — see [min cut & modeling](02-min-cut-and-flow-modeling.md).
- **Flows simulated by data structures.** For huge $n$ with structured graphs (a line, a tree), compute the min cut by DP or a segment tree instead of running flow —
  e.g. [CF 724E · Goods transportation](https://codeforces.com/problemset/problem/724/E) — 2900 and
  [CF 1919F2 · Wine Factory (Hard Version)](https://codeforces.com/problemset/problem/1919/F2) — 2800.
- **Global min cut** (no $s$, $t$): Stoer–Wagner $O(V^3)$ or Karger's randomized contraction — 🧊.
- **Gomory–Hu tree** (🧊): $V-1$ max-flow calls give all-pairs min cuts as path minima in a tree.
- **Parametric flow / incremental flow**: when capacities change monotonically with a parameter, flows can be reused rather than recomputed (advanced; see min-cost flow in [04](04-min-cost-flow.md)).
- **Push–relabel** with highest-label and gap heuristics if you ever face dense $V\approx 5000$ graphs where Dinic is too slow.

## 8. Practice ladder

≤ 1900
- [ ] [CSES 1694 · Download Speed](https://cses.fi/problemset/task/1694) — plain max flow
- [ ] [AtCoder PRACTICE2 D · Maxflow](https://atcoder.jp/contests/practice2/tasks/practice2_d) — domino placement as bipartite flow, reconstruct from residual
- [ ] [CF 1797A · Li Hua and Maze](https://codeforces.com/problemset/problem/1797/A) — 800 — min vertex cut intuition on a grid
- [ ] [CF 965D · Single-use Stones](https://codeforces.com/problemset/problem/965/D) — 1900 — the min cut is a window
- [ ] [CF 1214D · Treasure Island](https://codeforces.com/problemset/problem/1214/D) — 1900 — the answer is a cut of size ≤ 2
- [ ] [CF 1423B · Valuable Paper](https://codeforces.com/problemset/problem/1423/B) — 1900 — binary search + matching

1900–2200
- [ ] [CF 546E · Soldier and Traveling](https://codeforces.com/problemset/problem/546/E) — 2100 — supply/demand network, read the matrix from flows
- [ ] [CF 852D · Exploration plan](https://codeforces.com/problemset/problem/852/D) — 2100 — binary search on time + Floyd + flow
- [ ] [CF 269C · Flawed Flow](https://codeforces.com/problemset/problem/269/C) — 2100 — conservation lets you orient the edges
- [ ] [CF 653D · Delivery Bears](https://codeforces.com/problemset/problem/653/D) — 2200 — Example 3
- [ ] [AtCoder ABC205 F · Grid and Tokens](https://atcoder.jp/contests/abc205/tasks/abc205_f) — rows → tokens → columns with split tokens

2200–2600
- [ ] [CF 510E · Fox And Dinner](https://codeforces.com/problemset/problem/510/E) — 2300 — parity split, degree-2 capacities, read cycles from the flow
- [ ] [AtCoder ABC241 G · Round Robin](https://atcoder.jp/contests/abc241/tasks/abc241_g) — remaining games as flow, per candidate winner
- [ ] [CF 1082G · Petya and Graph](https://codeforces.com/problemset/problem/1082/G) — 2400 — closure (see 02)
- [ ] [CF 1139E · Maximize Mex](https://codeforces.com/problemset/problem/1139/E) — 2400 — incremental augmenting paths (see 03)
- [ ] [CF 1913E · Matrix Problem](https://codeforces.com/problemset/problem/1913/E) — 2400 — row/column sums as flow with costs (see 04)
- [ ] [CF 724E · Goods transportation](https://codeforces.com/problemset/problem/724/E) — 2900 — min cut by DP, flow too big to run

## 9. LeetCode / FAANG cross-reference

Rare in interviews: max flow is not expected in FAANG coding rounds (it is long to code and hard to grade). What does appear is the *idea* of augmenting paths in
bipartite matching on tiny inputs, usually solved there with bitmask DP or backtracking:

- [LC 1349 · Maximum Students Taking Exam](https://leetcode.com/problems/maximum-students-taking-exam/) — Hard — maximum independent set in a bipartite conflict graph = cells − matching (or bitmask DP).
- [LC 1947 · Maximum Compatibility Score Sum](https://leetcode.com/problems/maximum-compatibility-score-sum/) — Medium — an assignment problem (Hungarian or bitmask DP).
- [LC 2850 · Minimum Moves to Spread Stones Over Grid](https://leetcode.com/problems/minimum-moves-to-spread-stones-over-grid/) — Medium — min-cost assignment of surplus stones to holes.

If an interviewer asks about flows at all, it is usually conceptual: explain max-flow min-cut and how bipartite matching reduces to flow.

## 10. Self-check

1. Why does the greedy "push along any path" fail, and what exactly do backward residual edges represent?
2. Prove $|f|\le c(S,T)$ for every flow and cut.
3. After a max flow, how do you obtain a minimum cut, and why is every edge from $S$ to $T$ saturated?
4. Why does Dinic need at most $V-1$ phases?
5. Why can the current-arc pointer be advanced permanently within a phase?
6. What changes in the analysis for unit-capacity bipartite networks, and what bound do you get?
7. How do you model an undirected edge? A vertex capacity?
8. In Delivery Bears, why is feasibility monotone in $w$, and why is it fine that flow decomposition may contain cycles?

<details><summary>Answers</summary>

1. It commits to edges that the optimum does not use. A backward edge $v\to u$ with capacity $f(u,v)$ represents cancelling (rerouting) flow already sent on $u\to v$.
2. Sum conservation over $S$: the net flow out of $S$ equals $|f|$, and it equals $f(S\to T) - f(T\to S) \le c(S,T) - 0$.
3. BFS from $s$ in the residual graph; the reached set is $S$. An unsaturated $S\to T$ edge would have positive residual capacity and its head would have been reached.
4. Every phase saturates all shortest augmenting paths, so the residual $s$–$t$ distance strictly increases; distances are between 1 and $V-1$.
5. Levels are fixed during a phase and residual capacities of level-graph edges only decrease (reverse edges go down a level and are never used), so a dead or saturated edge stays useless.
6. Each phase is $O(E)$, and after $\sqrt V$ phases the remaining flow is at most $\sqrt V$ because residual paths are vertex-disjoint and long: $O(E\sqrt V)$.
7. Undirected: one edge pair with capacity $c$ in both directions. Vertex capacity: split $v$ into $v_{in}\to v_{out}$ with that capacity.
8. Decreasing $w$ never decreases $\lfloor c/w\rfloor$. Cycles in a decomposition carry flow from $s$ back to itself and can be removed without changing the value, leaving simple paths.

</details>
