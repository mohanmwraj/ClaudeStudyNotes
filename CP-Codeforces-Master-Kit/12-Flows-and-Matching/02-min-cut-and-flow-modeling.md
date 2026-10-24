# Minimum Cut and Flow Modeling

> **Band:** 🟣 2000–2600 · **Priority:** 🔥 (cut extraction, splitting, disjoint paths, project selection) · ⚡ (lower bounds, circulations 🟠) · **FAANG:** low · **Prerequisites:** [max flow / Dinic](01-max-flow-dinic.md), [BFS/DFS](../09-Graphs/01-graph-representation-bfs-dfs.md)
> **You can say you know this when:** given a statement about choosing/separating/routing things, you can write down the network, say what a cut *means* in the original
> problem, prove the correspondence in both directions, and print the actual cut or decomposition — including problems with lower bounds on edges.

## 1. First principles — why this works

A max-flow solver is a black box that answers two dual questions at once. Modeling is the art of making one of them be your problem.

**View A — flow as routed units.** By flow decomposition, an integral flow of value $k$ is $k$ unit paths from $s$ to $t$ (plus cycles you can discard).
So "how many things can travel / be assigned simultaneously" is a max flow: each thing is one unit, every resource it passes through is an edge or vertex capacity.
*Think of each unit as a path*: if you can describe one valid "life story" of a unit as an $s$–$t$ path and the constraints as "at most $c$ stories pass here",
you have a flow model.

**View B — cut as a binary labeling.** A cut assigns every vertex a label: $S$ (source side) or $T$ (sink side). Its capacity is the total capacity of edges going from $S$ to $T$.
Read each edge as a *penalty rule*:

| Edge | Paid when | Meaning |
|---|---|---|
| $s\to v$ with capacity $a$ | $v\in T$ | "it costs $a$ to put $v$ on the $T$ side" |
| $v\to t$ with capacity $b$ | $v\in S$ | "it costs $b$ to put $v$ on the $S$ side" |
| $u\to v$ with capacity $c$ | $u\in S,\ v\in T$ | "it costs $c$ if $u$ is $S$ but $v$ is $T$" |
| $u\to v$ with capacity $\infty$ | never allowed | implication: $u\in S \Rightarrow v\in S$ |

So min cut minimizes any energy of the form
$$E(x) = \sum_v \text{unary}_v(x_v) + \sum_{(u,v)} c_{uv}\,[x_u = S,\ x_v = T],\qquad c_{uv}\ge 0.$$
Whenever your problem is "choose a subset; pay for individual choices and for certain *pairs that disagree*", it is a min cut. Pair terms that penalize
*agreement* are not directly representable — unless the graph of pair terms is bipartite, in which case flipping the meaning of the labels on one side turns
"agree" into "disagree" (Example 3).

**Extracting the cut, and which cut you get.** After a max flow, let $R$ = vertices reachable from $s$ through positive residual edges. $(R, V\setminus R)$ is a minimum cut
(the max-flow min-cut proof in [01](01-max-flow-dinic.md)). It is *canonical*: $R$ is the same for every maximum flow, and it is the smallest possible source side.
Proof: take any min cut $(S',T')$ and any max flow $f$. Since $|f| = c(S',T')$, every edge $S'\to T'$ is saturated and every edge $T'\to S'$ carries zero flow, so no residual
edge leaves $S'$; hence everything reachable from $s$ stays inside $S'$, i.e. $R\subseteq S'$. Symmetrically, the set of vertices that can reach $t$ in the residual graph gives
the unique *largest* source side (its complement). When a problem says "print any minimum cut", printing $R$'s cut makes your output deterministic.

**Vertex capacities.** Flow has capacities on edges only. Split $v$ into $v_{in}\to v_{out}$ with the vertex capacity; every edge into $v$ enters $v_{in}$, every edge out of $v$
leaves $v_{out}$. A cut that "removes vertex $v$" now cuts the edge $v_{in}\to v_{out}$.

**Several sources or sinks.** Add a super source $s^*$ with edges $s^*\to s_i$ (capacity = supply of $s_i$, or $\infty$) and a super sink likewise.

**Menger's theorem** is max-flow min-cut with unit capacities:
- the maximum number of edge-disjoint $s$–$t$ paths equals the minimum number of edges whose removal disconnects $t$ from $s$;
- the maximum number of internally vertex-disjoint $s$–$t$ paths ($s,t$ non-adjacent) equals the minimum number of vertices whose removal disconnects them (split vertices).

**Project selection (maximum weight closure).** Items have weights $p_i$ (profit if positive, cost if negative); some rules say "if you take $i$ you must take $j$".
Put chosen items on the $S$ side. For $p_i > 0$ add $s\to i$ with capacity $p_i$ (you lose $p_i$ if $i$ is not chosen); for $p_i<0$ add $i\to t$ with capacity $-p_i$
(you pay if chosen); for every rule add $i\to j$ with capacity $\infty$. Then for every *closed* choice $S$ (rules respected),
$$\text{cut}(S) = \sum_{p_i>0,\ i\notin S} p_i + \sum_{p_i<0,\ i\in S} (-p_i) = \sum_{p_i > 0} p_i - \text{profit}(S),$$
and non-closed choices cost $\infty$. So the best profit is $\sum_{p_i>0}p_i - \text{mincut}$, and the chosen set is $R\setminus\{s\}$.

**Lower bounds (🟠).** Edge $(u,v)$ must carry between $l$ and $c$. Substitute $f = l + f'$ with $0\le f'\le c-l$. The forced $l$ units leave $u$ and arrive at $v$ regardless,
so they break conservation: vertex $v$ has a surplus $\text{ex}(v) = \sum_{\text{in}} l - \sum_{\text{out}} l$. Fix it with a new source $S^*$ and sink $T^*$:
$S^*\to v$ with capacity $\text{ex}(v)$ when positive, $v\to T^*$ with $-\text{ex}(v)$ when negative. A feasible **circulation** exists iff the max flow $S^*\to T^*$
saturates all $S^*$ edges. For an $s$–$t$ flow with bounds, first add $t\to s$ with capacity $\infty$ (turning the flow into a circulation); if feasible, the flow on that edge
$F_0$ is the value of a feasible $s$–$t$ flow. Delete that edge and run max flow $s\to t$ in the residual graph: the **maximum** flow with bounds is $F_0 + \text{extra}$
(for the minimum, run $t\to s$ and subtract). The residual graph encodes exactly the freedom left inside $[l,c]$, so augmenting never violates a bound.

## 2. Formulas, definitions and identities

- **Cut energy.** With $x_v\in\{S,T\}$: $\ \text{cut}(x) = \sum_v a_v[x_v=T] + \sum_v b_v[x_v=S] + \sum_{(u,v)} c_{uv}[x_u=S][x_v=T]$, for capacities $a_v$ ($s\to v$), $b_v$ ($v\to t$), $c_{uv}$ ($u\to v$).
- **Representable pair costs.** A pair cost table $\theta(x_u,x_v)$ is min-cut representable iff $\theta(S,T)+\theta(T,S) \ge \theta(S,S)+\theta(T,T)$ (submodularity). Proof sketch: subtract unary parts so that $\theta(S,S)=\theta(T,T)=0$ and the remaining two entries are non-negative edges $u\to v$ and $v\to u$.
- **Canonical min cut.** $R_{\min} = \{v : s \leadsto v \text{ in } G_f\}$ and $T_{\min} = \{v : v \leadsto t \text{ in } G_f\}$ are the same for every max flow $f$; every min cut $(S,T)$ satisfies $R_{\min}\subseteq S\subseteq V\setminus T_{\min}$.
- **Edge in some / every min cut.** Edge $(u,v)$ is saturated by every max flow and lies in *some* min cut iff there is no residual path $u\leadsto v$; it lies in *every* min cut iff $u\in R_{\min}$ and $v\in T_{\min}$.
- **Menger.** $\lambda(s,t)$ (edge-disjoint paths) $=$ min edge cut; $\kappa(s,t)$ (internally vertex-disjoint) $=$ min vertex separator, for non-adjacent $s,t$.
- **Closure.** $\max_{S \text{ closed}} \sum_{i\in S} p_i = \sum_{p_i>0} p_i - \text{mincut}$.
- **Lower bounds.** $\text{ex}(v) = \sum_{(u,v)} l_{uv} - \sum_{(v,w)} l_{vw}$; feasible iff $\text{maxflow}(S^*,T^*) = \sum_{\text{ex}(v)>0}\text{ex}(v)$; $\ \max$ $s$–$t$ flow $= F_0 + \text{maxflow}_{G_f - (t,s)}(s,t)$.
- **Hoffman's circulation theorem.** A circulation with $l\le f\le c$ exists iff for every vertex set $X$: $\sum_{\text{into }X} l \le \sum_{\text{out of }X} c$. (Max-flow min-cut applied to the $S^*/T^*$ network.)
- **Sizes.** Vertex splitting doubles $V$ and adds $V$ edges; super source/sink add $\le V$ edges each; project selection on $m$ rules and $n$ items has $n+2$ vertices and $n+m$ edges.

## 3. Implementation (C++ and Java)

The Dinic from [01](01-max-flow-dinic.md) plus a lower-bounds wrapper. `LBFlow::addEdge(u, v, l, c)` stores the transformed edge; `maxflow(s, t)` returns the maximum
$s$–$t$ flow respecting all bounds, or $-1$ if no feasible flow exists.

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

struct LBFlow {                 // max s-t flow with lower bounds l <= f <= c on every edge
    int n; Dinic d; vector<ll> ex;
    LBFlow(int n) : n(n), d(n + 2), ex(n, 0) {}
    void addEdge(int u, int v, ll l, ll c) { d.addEdge(u, v, c - l); ex[v] += l; ex[u] -= l; }
    ll maxflow(int s, int t) {
        const ll INF = LLONG_MAX / 4;
        int S = n, T = n + 1, back = d.addEdge(t, s, INF);
        ll need = 0;
        for (int v = 0; v < n; v++) {
            if (ex[v] > 0) { d.addEdge(S, v, ex[v]); need += ex[v]; }
            if (ex[v] < 0) d.addEdge(v, T, -ex[v]);
        }
        if (d.maxflow(S, T) != need) return -1;      // no feasible flow
        ll f0 = d.e[back ^ 1].cap;                   // flow currently on t -> s
        d.e[back].cap = d.e[back ^ 1].cap = 0;       // delete the t -> s edge
        return f0 + d.maxflow(s, t);
    }
};
```

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

static class LBFlow {               // max s-t flow with lower bounds l <= f <= c
    int n; Dinic d; long[] ex;
    LBFlow(int n, int maxEdges) { this.n = n; d = new Dinic(n + 2, maxEdges + n + 1); ex = new long[n]; }
    void addEdge(int u, int v, long l, long c) { d.addEdge(u, v, c - l, 0); ex[v] += l; ex[u] -= l; }
    long maxflow(int s, int t) {
        final long INF = Long.MAX_VALUE / 4;
        int S = n, T = n + 1, back = d.addEdge(t, s, INF, 0);
        long need = 0;
        for (int v = 0; v < n; v++) {
            if (ex[v] > 0) { d.addEdge(S, v, ex[v], 0); need += ex[v]; }
            if (ex[v] < 0) d.addEdge(v, T, -ex[v], 0);
        }
        if (d.maxflow(S, T, Long.MAX_VALUE) != need) return -1;
        long f0 = d.cap[back ^ 1];
        d.cap[back] = 0; d.cap[back ^ 1] = 0;
        return f0 + d.maxflow(s, t, Long.MAX_VALUE);
    }
}
```

## 4. Recognising the pattern

| Statement wording | Model |
|---|---|
| "minimum number of roads/edges to block so A cannot reach B" | min cut, unit capacities; print the cut from residual reachability |
| "minimum number of *cities* to remove" | vertex splitting, $v_{in}\to v_{out}$ capacity 1, endpoints $\infty$ |
| "maximum number of routes that share no road / no city" | Menger: same networks, read paths from the flow |
| "choose a subset; gain $p_i$; taking $i$ forces taking $j$" | project selection / closure; $\infty$ edges for implications |
| "each pixel/cell gets one of two labels; cost per label + cost when neighbors differ" | image-segmentation min cut |
| "neighbors should be *different*" on a grid or bipartite graph | flip labels on one color class, then it is "should be equal" |
| "each edge must be used at least $l$ times" / "every route must be covered" | lower bounds / circulation |
| "can all demands be satisfied?" with supplies and capacities | saturating flow from super source to super sink |

Common confusions: a min cut that separates *several* pairs at once (multiway cut) is NP-hard in general — check that the problem really has one source side and one sink side.
Pair costs that reward agreement on a non-bipartite structure (e.g. "neighbors must differ" on a triangle) are not min cuts.

## 5. Worked examples (graded)

### Example 1 — Police Chase  ·  ★ ≈1800

- **Source:** [CSES 1695 · Police Chase](https://cses.fi/problemset/task/1695)
- **Difficulty:** ≈1800 (est.)
- **Problem:** an undirected graph with $n\le 500$ crossings and $m\le 1000$ streets. Block the minimum number of streets so that crossing 1 can no longer reach crossing $n$,
  and print those streets.
- **Thinking from first principles:** "fewest edges to disconnect" is a min cut with capacity 1 per street (Menger). An undirected street is one edge pair with capacity 1
  in both directions. The cut is read from residual reachability; a street is cut iff exactly one endpoint is reachable. Printing the canonical (source-closest) cut and
  listing streets in input order makes the output deterministic.

<details><summary>Solution</summary>

Max flow from 1 to $n$; BFS from 1 in the residual graph; print every street with one endpoint inside and one outside, in input order and orientation.
The number of such streets equals the max flow by max-flow min-cut. $O(V^2E)$ worst case; trivial here.

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
    vector<int> a(m), b(m);
    for (int i = 0; i < m; i++) { cin >> a[i] >> b[i]; d.addEdge(a[i] - 1, b[i] - 1, 1, 1); }
    ll k = d.maxflow(0, n - 1);
    vector<char> vis(n, 0);                 // canonical source side: residual reachability
    queue<int> q; q.push(0); vis[0] = 1;
    while (!q.empty()) {
        int u = q.front(); q.pop();
        for (int id : d.g[u]) if (d.e[id].cap > 0 && !vis[d.e[id].to]) { vis[d.e[id].to] = 1; q.push(d.e[id].to); }
    }
    cout << k << "\n";
    for (int i = 0; i < m; i++) if (vis[a[i] - 1] != vis[b[i] - 1]) cout << a[i] << " " << b[i] << "\n";
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
        boolean[] minCutSide(int s) {
            boolean[] vis = new boolean[n]; int qh = 0, qt = 0; q[qt++] = s; vis[s] = true;
            while (qh < qt) { int u = q[qh++]; for (int e = head[u]; e != -1; e = nxt[e]) if (cap[e] > 0 && !vis[to[e]]) { vis[to[e]] = true; q[qt++] = to[e]; } }
            return vis;
        }
    }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt();
        Dinic d = new Dinic(n, m);
        int[] a = new int[m], b = new int[m];
        for (int i = 0; i < m; i++) { a[i] = nextInt(); b[i] = nextInt(); d.addEdge(a[i] - 1, b[i] - 1, 1, 1); }
        long k = d.maxflow(0, n - 1, Long.MAX_VALUE);
        boolean[] vis = d.minCutSide(0);
        StringBuilder sb = new StringBuilder().append(k).append('\n');
        for (int i = 0; i < m; i++) if (vis[a[i] - 1] != vis[b[i] - 1]) sb.append(a[i]).append(' ').append(b[i]).append('\n');
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.print(sb);
        out.flush();
    }
}
```

</details>

The third test has two minimum cuts of size 1 (either street of the path); the canonical one is next to crossing 1. In the fourth, several cuts of size 2 exist and the canonical one isolates crossing 1.

<!-- test
in:
4 5
1 2
1 3
2 3
3 4
1 4
out:
2
3 4
1 4
-->
<!-- test
in:
2 1
1 2
out:
1
1 2
-->
<!-- test
in:
3 2
2 1
3 2
out:
1
2 1
-->
<!-- test
in:
6 8
1 2
1 3
2 3
2 4
3 5
4 5
4 6
5 6
out:
2
1 2
1 3
-->

### Example 2 — Routes that share no city  ·  ★ ≈1900

- **Source:** Original problem.
- **Difficulty:** ≈1900 (est.)
- **Problem:** a directed graph with $n\le 500$ vertices and $m\le 5000$ edges (parallel edges allowed). Find the maximum number of paths from 1 to $n$ such that no two paths
  share an edge, and no two paths share a vertex other than 1 and $n$.
- **Thinking from first principles:** edge-disjointness alone is a unit-capacity flow, but flow happily sends two units through the same vertex. To make a *vertex* a resource
  with capacity 1, it must become an *edge*: split $v$ into $v_{in}\to v_{out}$ (capacity 1). Vertices 1 and $n$ are shared by every path, so their split edge gets
  capacity $\infty$ (or $m$). Every original edge $u\to v$ becomes $u_{out}\to v_{in}$ with capacity 1, which keeps parallel edges $1\to n$ as distinct paths.

<details><summary>Solution</summary>

Vertex $v$ (0-indexed) becomes $v_{in}=v$ and $v_{out}=v+n$. Answer = max flow from $0_{in}$ to $(n-1)_{out}$. An integral flow decomposes into unit paths;
capacity 1 on $v_{in}\to v_{out}$ means at most one path passes through $v$. Conversely disjoint paths give a flow. $V = 2n$, $E = n+m$; unit capacities, so
Dinic runs in $O(E\sqrt V)$.

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
    Dinic d(2 * n);
    for (int v = 0; v < n; v++) d.addEdge(v, v + n, (v == 0 || v == n - 1) ? m : 1);
    for (int i = 0; i < m; i++) { int u, v; cin >> u >> v; d.addEdge(u - 1 + n, v - 1, 1); }
    cout << d.maxflow(0, 2 * n - 1) << "\n";
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
        int n = nextInt(), m = nextInt();
        Dinic d = new Dinic(2 * n, n + m);
        for (int v = 0; v < n; v++) d.addEdge(v, v + n, (v == 0 || v == n - 1) ? m : 1, 0);
        for (int i = 0; i < m; i++) { int u = nextInt() - 1, v = nextInt() - 1; d.addEdge(u + n, v, 1, 0); }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(d.maxflow(0, 2 * n - 1, Long.MAX_VALUE));
        out.flush();
    }
}
```

</details>

In the first test both 1→2→4 and 1→3→4 exist, but 1→2→3→4 would share vertex 3; the answer is 2. In the second, every path passes through vertex 2, so edge-disjoint
paths (2 of them) are not vertex-disjoint (only 1).

<!-- test
in:
4 5
1 2
2 4
1 3
3 4
2 3
out:
2
-->
<!-- test
in:
3 4
1 2
1 2
2 3
2 3
out:
1
-->
<!-- test
in:
2 3
1 2
1 2
2 1
out:
2
-->

### Example 3 — Zebraness  ·  ★ ≈2475

- **Source:** [AtCoder ABC193 F · Zebraness](https://atcoder.jp/contests/abc193/tasks/abc193_f)
- **Difficulty:** ≈2475 (est., AtCoder difficulty)
- **Problem:** an $N\times N$ grid ($N\le 100$) of `B`, `W` and `?`. Replace every `?` by `B` or `W` to maximize the number of pairs of side-adjacent cells with different colors.
- **Thinking from first principles:** each cell is a binary label, and the pair term *rewards disagreement* — the wrong direction for min cut. But the grid is bipartite
  (chessboard coloring by $(i+j)\bmod 2$). Flip the meaning of the label on odd cells: "different colors" becomes "equal flipped labels". Now we minimize the number of
  adjacent pairs whose *flipped* labels differ — a pure "neighbors disagree" penalty, i.e. min cut with capacity 1 on every grid edge (both directions). Fixed cells are
  tied to their side with $\infty$ edges.

<details><summary>Solution</summary>

Flipped label of a fixed cell: its color, swapped if $(i+j)$ is odd. Flipped `B` → $s\to v$ ($\infty$); flipped `W` → $v\to t$ ($\infty$). Every adjacent pair: one edge
pair of capacity 1 both ways. The min cut counts adjacent pairs with different flipped labels, i.e. equal original colors. Total adjacent pairs are $2N(N-1)$, so the
answer is $2N(N-1) - \text{mincut}$. $V = N^2+2$, $E\approx 3N^2$.

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
    int n;
    cin >> n;
    vector<string> c(n);
    for (auto &row : c) cin >> row;
    const ll INF = 1e9;
    int s = n * n, t = n * n + 1;
    Dinic d(n * n + 2);
    for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++) {
            int v = i * n + j;
            char ch = c[i][j];
            if (ch != '?' && (i + j) % 2 == 1) ch = (ch == 'B' ? 'W' : 'B');   // flip odd cells
            if (ch == 'B') d.addEdge(s, v, INF);
            if (ch == 'W') d.addEdge(v, t, INF);
            if (i + 1 < n) d.addEdge(v, v + n, 1, 1);
            if (j + 1 < n) d.addEdge(v, v + 1, 1, 1);
        }
    cout << 2LL * n * (n - 1) - d.maxflow(s, t) << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
    static String next() throws IOException {
        int b = in.read();
        while (b <= ' ') b = in.read();
        StringBuilder sb = new StringBuilder();
        while (b > ' ') { sb.append((char) b); b = in.read(); }
        return sb.toString();
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
        int n = Integer.parseInt(next());
        char[][] c = new char[n][];
        for (int i = 0; i < n; i++) c[i] = next().toCharArray();
        final long INF = 1_000_000_000L;
        int s = n * n, t = n * n + 1;
        Dinic d = new Dinic(n * n + 2, 3 * n * n);
        for (int i = 0; i < n; i++)
            for (int j = 0; j < n; j++) {
                int v = i * n + j;
                char ch = c[i][j];
                if (ch != '?' && (i + j) % 2 == 1) ch = (ch == 'B' ? 'W' : 'B');
                if (ch == 'B') d.addEdge(s, v, INF, 0);
                if (ch == 'W') d.addEdge(v, t, INF, 0);
                if (i + 1 < n) d.addEdge(v, v + n, 1, 1);
                if (j + 1 < n) d.addEdge(v, v + 1, 1, 1);
            }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(2L * n * (n - 1) - d.maxflow(s, t, Long.MAX_VALUE));
        out.flush();
    }
}
```

</details>

Hand checks: an all-`?` $2\times2$ grid can be a perfect checkerboard, 4 pairs. `BB/BB` has 0. $N=1$ has no pairs.

<!-- test
in:
2
??
??
out:
4
-->
<!-- test
in:
2
BB
BB
out:
0
-->
<!-- test
in:
1
?
out:
0
-->
<!-- test
in:
3
B?W
???
W?B
out:
8
-->

### Example 4 — Petya and Graph  ·  ★ 2400

- **Source:** [CF 1082G · Petya and Graph](https://codeforces.com/problemset/problem/1082/G) — 2400
- **Difficulty:** 2400
- **Problem:** a simple undirected graph with $n,m\le 1000$; vertex $v$ costs $a_v$, edge $e$ is worth $w_e$ (all positive, up to $10^9$). Choose a vertex set $X$ and take every edge with both
  ends in $X$; maximize total edge worth minus total vertex cost (the empty choice gives 0).
- **Thinking from first principles:** try greedy "take an edge if $w > a_u + a_v$" — wrong, because vertices are shared among edges (one expensive vertex can be paid for by
  many edges). Reformulate as choosing *items*: edges (profit $w_e$) and vertices (cost $a_v$), with rules "taking edge $e=(u,v)$ forces taking $u$ and $v$".
  That is exactly a maximum-weight closure: project selection.

<details><summary>Solution</summary>

Network: $s\to e$ (capacity $w_e$), $e\to u$ and $e\to v$ ($\infty$), $v\to t$ (capacity $a_v$). Answer $=\sum w_e - \text{mincut}$; it is never negative because the empty
closure has profit 0. $V = n+m+2$, $E = 3m+n$; Dinic is fast because the network has depth 3.

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
    int s = n + m, t = n + m + 1;           // vertices 0..n-1, edge-items n..n+m-1
    Dinic d(n + m + 2);
    const ll INF = 4e18 / 4;
    for (int v = 0; v < n; v++) { ll a; cin >> a; d.addEdge(v, t, a); }
    ll total = 0;
    for (int i = 0; i < m; i++) {
        int u, v; ll w;
        cin >> u >> v >> w;
        total += w;
        d.addEdge(s, n + i, w);
        d.addEdge(n + i, u - 1, INF);
        d.addEdge(n + i, v - 1, INF);
    }
    cout << total - d.maxflow(s, t) << "\n";
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
        int s = n + m, t = n + m + 1;
        Dinic d = new Dinic(n + m + 2, n + 3 * m);
        final long INF = Long.MAX_VALUE / 4;
        for (int v = 0; v < n; v++) d.addEdge(v, t, nextLong(), 0);
        long total = 0;
        for (int i = 0; i < m; i++) {
            int u = nextInt() - 1, v = nextInt() - 1;
            long w = nextLong();
            total += w;
            d.addEdge(s, n + i, w, 0);
            d.addEdge(n + i, u, INF, 0);
            d.addEdge(n + i, v, INF, 0);
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(total - d.maxflow(s, t, Long.MAX_VALUE));
        out.flush();
    }
}
```

</details>

Hand checks: a triangle with vertex costs 3 and edges worth 2 each: taking everything gives $6-9<0$, any pair gives $2-6$, so 0. A star whose center costs 5
and leaves cost 1, with three edges worth 3: taking all gives $9-8 = 1$. A heavy single edge 10 with costs 4, 4 gives 2.

<!-- test
in:
3 3
3 3 3
1 2 2
2 3 2
1 3 2
out:
0
-->
<!-- test
in:
4 3
5 1 1 1
1 2 3
1 3 3
1 4 3
out:
1
-->
<!-- test
in:
2 1
4 4
1 2 10
out:
2
-->
<!-- test
in:
1 0
7
out:
0
-->

### Example 5 — Maximum flow with lower bounds  ·  ★ ≈2300

- **Source:** Original problem.
- **Difficulty:** ≈2300 (est.)
- **Problem:** a directed graph with $n\le 200$ vertices, $m\le 2000$ edges, a source $s$ and a sink $t$. Edge $i$ goes $u_i\to v_i$ and must carry an integer flow in
  $[l_i, c_i]$ ($0\le l_i\le c_i\le 10^9$). Conservation holds at every vertex except $s$ and $t$. Print the maximum possible flow value, or $-1$ if no flow satisfies all bounds.
- **Thinking from first principles:** subtract the mandatory part: $f_i = l_i + f'_i$ with $0\le f'_i\le c_i - l_i$. The mandatory parts create a surplus at heads and a deficit
  at tails; some extra flow $f'$ must cancel all of them, which is a supply/demand problem ($S^*$ feeds surpluses, $T^*$ absorbs deficits). Vertices $s$ and $t$ may be unbalanced,
  which the edge $t\to s$ ($\infty$) absorbs. After feasibility, the residual graph describes every remaining degree of freedom, so plain augmentation from $s$ to $t$ finishes.

<details><summary>Solution</summary>

Use `LBFlow` from §3. Feasibility: the $S^*\to T^*$ max flow must equal the total surplus. The flow on $t\to s$ is a feasible value $F_0$; deleting that edge and augmenting
$s\to t$ gives the maximum. Complexity: two Dinic runs on $n+2$ vertices and $m+n+1$ edges.

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

struct LBFlow {
    int n; Dinic d; vector<ll> ex;
    LBFlow(int n) : n(n), d(n + 2), ex(n, 0) {}
    void addEdge(int u, int v, ll l, ll c) { d.addEdge(u, v, c - l); ex[v] += l; ex[u] -= l; }
    ll maxflow(int s, int t) {
        const ll INF = LLONG_MAX / 4;
        int S = n, T = n + 1, back = d.addEdge(t, s, INF);
        ll need = 0;
        for (int v = 0; v < n; v++) {
            if (ex[v] > 0) { d.addEdge(S, v, ex[v]); need += ex[v]; }
            if (ex[v] < 0) d.addEdge(v, T, -ex[v]);
        }
        if (d.maxflow(S, T) != need) return -1;
        ll f0 = d.e[back ^ 1].cap;
        d.e[back].cap = d.e[back ^ 1].cap = 0;
        return f0 + d.maxflow(s, t);
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m, s, t;
    cin >> n >> m >> s >> t;
    LBFlow f(n);
    for (int i = 0; i < m; i++) { int u, v; ll l, c; cin >> u >> v >> l >> c; f.addEdge(u - 1, v - 1, l, c); }
    cout << f.maxflow(s - 1, t - 1) << "\n";
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

    static class LBFlow {
        int n; Dinic d; long[] ex;
        LBFlow(int n, int maxEdges) { this.n = n; d = new Dinic(n + 2, maxEdges + n + 1); ex = new long[n]; }
        void addEdge(int u, int v, long l, long c) { d.addEdge(u, v, c - l, 0); ex[v] += l; ex[u] -= l; }
        long maxflow(int s, int t) {
            final long INF = Long.MAX_VALUE / 4;
            int S = n, T = n + 1, back = d.addEdge(t, s, INF, 0);
            long need = 0;
            for (int v = 0; v < n; v++) {
                if (ex[v] > 0) { d.addEdge(S, v, ex[v], 0); need += ex[v]; }
                if (ex[v] < 0) d.addEdge(v, T, -ex[v], 0);
            }
            if (d.maxflow(S, T, Long.MAX_VALUE) != need) return -1;
            long f0 = d.cap[back ^ 1];
            d.cap[back] = 0; d.cap[back ^ 1] = 0;
            return f0 + d.maxflow(s, t, Long.MAX_VALUE);
        }
    }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt(), s = nextInt() - 1, t = nextInt() - 1;
        LBFlow f = new LBFlow(n, m);
        for (int i = 0; i < m; i++) { int u = nextInt() - 1, v = nextInt() - 1; long l = nextLong(), c = nextLong(); f.addEdge(u, v, l, c); }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(f.maxflow(s, t));
        out.flush();
    }
}
```

</details>

Hand checks: (1) path $1\to2\to3$ with bounds $[2,5]$ and $[0,3]$ → the second edge caps it at 3, and 3 ≥ 2, so 3. (2) Same path with $[4,5]$ and $[0,3]$ → infeasible, $-1$.
(3) Edges $1\to2$ $[0,2]$, $2\to3$ $[1,2]$ and a forced back edge $3\to2$ $[1,1]$: conservation at 2 makes $f(2\to3) = f(1\to2)+1\le 2$, so the value is 1.

<!-- test
in:
3 2 1 3
1 2 2 5
2 3 0 3
out:
3
-->
<!-- test
in:
3 2 1 3
1 2 4 5
2 3 0 3
out:
-1
-->
<!-- test
in:
3 3 1 3
1 2 0 2
2 3 1 2
3 2 1 1
out:
1
-->

## 6. Tricks, pitfalls and things to remember

1. **Say what the cut means before coding.** Write "$v\in S$ means *chosen*", then translate every rule into an edge with "paid when …". Most wrong answers are a reversed edge.
2. **$\infty$ must really be infinite but must not overflow.** Sums of several $\infty$ capacities on one path are fine (flows take minima), but `total - maxflow` with an $\infty$ cut
   means "impossible"; check `maxflow >= INF` before subtracting.
3. **Canonical cut for deterministic output**: BFS from $s$ in the residual graph after the flow. Do not BFS in the *original* graph, and do not use `cap > 0` on reverse edges by
   accident — reverse edges with positive residual capacity *are* residual edges and must be followed.
4. **Undirected unit edges**: one pair with capacity 1 both ways. The cut is "edges with exactly one endpoint reachable".
5. **Vertex splitting: endpoints get $\infty$** (or the max possible flow), otherwise the answer is capped at 1.
6. **Parallel edges** are separate edges in flow; if the statement treats them as one road, merge them first.
7. **Agreement-rewarding pairs** are not min cuts unless the pair graph is bipartite (then flip one side). Multiway cuts are NP-hard; look for a different structure.
8. **Lower bounds**: remember $t\to s$ for an $s$–$t$ problem, and *delete* it before the second phase (otherwise the "max" flow circulates through it and is infinite).
9. **Project selection answer is $\sum$ positive profits $-$ mincut** — not $\sum$ of all profits.
10. **Read the decomposition** (paths) by walking from $s$ along edges with positive flow, decrementing as you go; with Java avoid recursion for long paths.

## 7. Going further (toward 2400–2600+)

- **Min-cost circulation with lower bounds** — [CF 1288F · Red-Blue Graph](https://codeforces.com/problemset/problem/1288/F) — 2900 and
  [CF 708D · Incorrect Flow](https://codeforces.com/problemset/problem/708/D) — 2900 combine §1's lower-bound reduction with [min-cost flow](04-min-cost-flow.md).
- **Min cut as DP.** When the network is too big but structured, compute the min cut directly: [AtCoder ABC332 G · Not Too Many Balls](https://atcoder.jp/contests/abc332/tasks/abc332_g).
- **Multi-label problems (🔴).** Labels $1..k$ on each item with convex pair costs $|x_u - x_v|$ reduce to a chain of $k$ vertices per item ("Ishikawa construction");
  [CF 1146G · Zoning Restrictions](https://codeforces.com/problemset/problem/1146/G) — 2700 is a chain-per-item min cut.
- **Hall-type conditions + closures**: [CF 103E · Buying Sets](https://codeforces.com/problemset/problem/103/E) — 2900 uses a perfect matching to make a closure problem well-posed.
- **Dynamic / incremental min cut**: add capacity and re-augment instead of recomputing ([CF 976F · Minimal k-covering](https://codeforces.com/problemset/problem/976/F) — 2500).

## 8. Practice ladder

≤ 2100
- [ ] [CSES 1695 · Police Chase](https://cses.fi/problemset/task/1695) — Example 1
- [ ] [CSES 1711 · Distinct Routes](https://cses.fi/problemset/task/1711) — edge-disjoint paths, then read the paths from the flow
- [ ] [CF 1214D · Treasure Island](https://codeforces.com/problemset/problem/1214/D) — 1900 — the vertex cut is at most 2
- [ ] [CF 965D · Single-use Stones](https://codeforces.com/problemset/problem/965/D) — 1900 — the cut is a window of length $l$
- [ ] [CF 546E · Soldier and Traveling](https://codeforces.com/problemset/problem/546/E) — 2100 — supplies and demands with a bipartite copy
- [ ] [AtCoder ABC239 G · Builder Takahashi](https://atcoder.jp/contests/abc239/tasks/abc239_g) — vertex splitting, print the removed vertices

2100–2400
- [ ] [AtCoder ABC318 G · Typical Path Problem](https://atcoder.jp/contests/abc318/tasks/abc318_g) — "path through B" = two vertex-disjoint paths out of B
- [ ] [CF 311E · Biologist](https://codeforces.com/problemset/problem/311/E) — 2300 — project selection with flip costs
- [ ] [CF 510E · Fox And Dinner](https://codeforces.com/problemset/problem/510/E) — 2300 — degree constraints as capacities
- [ ] [CF 1082G · Petya and Graph](https://codeforces.com/problemset/problem/1082/G) — 2400 — Example 4
- [ ] [AtCoder ABC259 G · Grid Card Game](https://atcoder.jp/contests/abc259/tasks/abc259_g) — rows/columns as items, pair penalties
- [ ] [AtCoder ABC326 G · Unlock Achievement](https://atcoder.jp/contests/abc326/tasks/abc326_g) — levels as chains, achievements as closures
- [ ] [AtCoder ABC193 F · Zebraness](https://atcoder.jp/contests/abc193/tasks/abc193_f) — Example 3

2400+
- [ ] [CF 2026E · Best Subsequence](https://codeforces.com/problemset/problem/2026/E) — 2500 — elements vs bits, closure / independent set
- [ ] [CF 976F · Minimal k-covering](https://codeforces.com/problemset/problem/976/F) — 2500 — lower bounds that grow with $k$
- [ ] [AtCoder ABC285 G · Tatami](https://atcoder.jp/contests/abc285/tasks/abc285_g) — forced cells = lower bounds on a bipartite flow
- [ ] [CF 1146G · Zoning Restrictions](https://codeforces.com/problemset/problem/1146/G) — 2700 — chain construction
- [ ] [CF 1288F · Red-Blue Graph](https://codeforces.com/problemset/problem/1288/F) — 2900 — lower bounds + costs
- [ ] [CF 103E · Buying Sets](https://codeforces.com/problemset/problem/103/E) — 2900 — closure made valid by Hall

## 9. LeetCode / FAANG cross-reference

Rare in interviews — min cut modeling needs a flow library, which interviews avoid. The ideas that do transfer:

- [LC 1192 · Critical Connections in a Network](https://leetcode.com/problems/critical-connections-in-a-network/) — Hard — min cuts of size one are bridges (solved with low-link, see [bridges](../09-Graphs/06-bridges-articulation-points-and-bcc.md)).
- [LC 1349 · Maximum Students Taking Exam](https://leetcode.com/problems/maximum-students-taking-exam/) — Hard — maximum independent set in a bipartite graph via a min cut / König.
- [LC 2123 · Minimum Operations to Remove Adjacent Ones in Matrix](https://leetcode.com/problems/minimum-operations-to-remove-adjacent-ones-in-matrix/) — Hard 🔒 — minimum vertex cover on a grid = maximum matching.

## 10. Self-check

1. Translate "$u\in S \Rightarrow v\in S$" into an edge. Which direction and capacity?
2. Why is the set of vertices reachable from $s$ in the residual graph the same for every maximum flow?
3. How do you count the maximum number of paths that share no vertex except the endpoints? What capacity do the endpoints' split edges get, and why?
4. Derive the project-selection formula $\sum_{p_i>0}p_i - \text{mincut}$.
5. Why can "neighbors should have different labels" be solved by min cut on a grid but not on a triangle?
6. In the lower-bound reduction, what is $\text{ex}(v)$, which super edges do you add, and why do you need $t\to s$?
7. After a feasible circulation, why must you delete the $t\to s$ edge before maximizing?
8. Which edges belong to *every* minimum cut?

<details><summary>Answers</summary>

1. An edge $u\to v$ with capacity $\infty$: it would be cut exactly when $u\in S,\ v\in T$, which is therefore forbidden.
2. For any min cut $(S',T')$ and any max flow, edges $S'\to T'$ are saturated and edges $T'\to S'$ carry no flow, so no residual edge leaves $S'$; the reachable set lies in every min-cut source side, and it is itself one — so it is the unique minimal one.
3. Split every vertex into $v_{in}\to v_{out}$ with capacity 1 and run unit-capacity max flow; the endpoints get $\infty$ because every path uses them.
4. A closed set $S$ cuts $s\to i$ for profitable $i\notin S$ and $i\to t$ for costly $i\in S$; that sum is $\sum_{p>0} p - \text{profit}(S)$. Non-closed sets cut an $\infty$ edge.
5. The grid is bipartite, so flipping one color class turns "different" into "equal", which min cut handles. A triangle is an odd cycle: no flip works, and the problem (max cut) is NP-hard in general.
6. $\text{ex}(v) = $ (lower bounds entering $v$) $-$ (lower bounds leaving $v$). Add $S^*\to v$ for positive and $v\to T^*$ for negative excess. $t\to s$ turns an $s$–$t$ flow into a circulation so $s$ and $t$ may be unbalanced.
7. Otherwise flow can loop $s\to\dots\to t\to s$ without bound, and the maximum would be measured wrongly; the $F_0$ units it carries are added back explicitly.
8. Edges $(u,v)$ with $u$ reachable from $s$ and $v$ able to reach $t$ in the residual graph of a maximum flow.

</details>
