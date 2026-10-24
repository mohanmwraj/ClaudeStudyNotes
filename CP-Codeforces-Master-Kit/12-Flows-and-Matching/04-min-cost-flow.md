# Minimum-Cost Flow: Successive Shortest Paths with Potentials

> **Band:** 🟠 2100–2600 · **Priority:** 🔥 (successive shortest paths with potentials) · ⚡ (convex costs, negative costs) · 🧊 (cycle canceling, cost scaling, network simplex) · **FAANG:** none · **Prerequisites:** [max flow](01-max-flow-dinic.md), [Dijkstra & Bellman–Ford](../09-Graphs/02-shortest-paths.md), [modeling](02-min-cut-and-flow-modeling.md)
> **You can say you know this when:** you can prove that augmenting along cheapest paths gives a min-cost flow, explain why Johnson potentials keep Dijkstra valid, handle negative
> edge costs, and model "convex cost per unit" and "pick at most $k$ paths with best total value".

## 1. First principles — why this works

**The problem.** Every edge has a capacity $c(e)$ and a cost $w(e)$ per unit of flow. Among flows of value $F$ (or of maximum value), find one minimizing $\sum_e w(e)f(e)$.

**What does "optimal" look like?** Take any flow $f$ of value $F$ and compare with an optimal $f^*$ of the same value. The difference $f^*-f$ is a *circulation* in the residual graph
$G_f$ (conservation everywhere, including $s$ and $t$), and every circulation decomposes into cycles. If $f$ is not optimal, $\text{cost}(f^*-f)<0$, so some cycle of $G_f$ has negative cost.
Conversely, a negative residual cycle can be pushed around to lower the cost without changing the value. Hence:

> **Optimality criterion.** A flow of value $F$ is min-cost among flows of value $F$ $\iff$ its residual graph has no negative-cost cycle
> (residual edges: forward $u\to v$ with cost $w$, backward $v\to u$ with cost $-w$).

**Successive shortest paths (SSP).** Start with $f=0$ (no residual negative cycles if the original graph has none). Repeatedly augment along a **cheapest** $s$–$t$ path in $G_f$.
Claim: if $G_f$ has no negative cycle, then after augmenting along a shortest path $P$ it still has none. Proof via potentials: let $d(v)$ be shortest distances from $s$ in $G_f$. For every
residual edge $d(v)\le d(u)+w(u,v)$, i.e. the *reduced cost* $w(u,v)+d(u)-d(v)\ge 0$. Edges of $P$ have reduced cost exactly 0, so the new backward edges (cost $-w$) also have reduced cost 0.
All residual edges of the new graph have non-negative reduced cost; cycle costs equal their reduced costs (potentials telescope around a cycle), so no negative cycle. ∎
By induction each intermediate flow is min-cost for its value. The path costs are non-decreasing (distances in the residual graph never decrease, same argument), so the cost as a
function of the value, $\text{cost}(F)$, is **convex piecewise linear** — the basis of every "stop early" trick.

**Why potentials (Johnson's trick).** Backward edges have negative costs, so plain Dijkstra is invalid on $G_f$. But the proof above hands us a certificate: keep a potential $\pi(v)$
with all reduced costs $w_\pi(u,v) = w(u,v)+\pi(u)-\pi(v)\ge 0$. Dijkstra on reduced costs finds the same shortest paths (every $s$–$t$ path's reduced cost is its real cost plus the constant
$\pi(s)-\pi(t)$). After each Dijkstra set $\pi \leftarrow \pi + d$; the reduced costs stay non-negative, as shown. The real path cost is $\pi_{\text{new}}(t)-\pi_{\text{new}}(s)$.

**Negative edge costs in the input.** Initial potentials must make all reduced costs non-negative: run Bellman–Ford (or SPFA) once from $s$ and use the distances as $\pi$. This requires no negative
*cycle* in the input graph — true for DAGs and for "profit as negative cost" models where cycles cannot exist. If negative cycles exist, saturate every negative edge first
(push its full capacity, record the cost, fix the excesses with a lower-bound-style super source/sink, see [02](02-min-cut-and-flow-modeling.md)) or use cycle canceling.

**Complexity.** Each augmentation pushes at least one unit, so with integer capacities there are at most $F$ iterations, each a Dijkstra $O(E\log V)$: $O(F\,E\log V)$, plus one
Bellman–Ford $O(VE)$. This is *pseudo-polynomial* — fine when $F$ is small (assignments, $k$ paths) and dangerous when capacities are $10^9$ with many distinct paths. In dense graphs use the
$O(V^2)$ array Dijkstra.

**Variants of the question.**
- *Min-cost max-flow*: augment until no path exists.
- *Min-cost $k$-flow*: stop after $k$ units (`maxf = k`); report impossible if fewer.
- *Min-cost flow of any value* (maximize profit, flow optional): stop as soon as the cheapest path has cost $\ge 0$; by convexity no later path can be negative.

**Convex costs.** If sending $x$ units through a resource costs $g(x)$ with $g$ convex, replace it by unit-capacity parallel edges with costs $g(1)-g(0),\ g(2)-g(1),\dots$ — non-decreasing,
so a min-cost flow uses them in order and pays exactly $g(x)$. (Concave costs break this: the flow would take the cheap later units first.)

**Negative cycle canceling (🧊).** Find any feasible flow of the target value (max flow), then repeatedly find a negative cycle with Bellman–Ford and push along it. Correct by the criterion
above; choosing minimum-mean cycles makes it strongly polynomial (Goldberg–Tarjan). Cost scaling and network simplex are what industrial solvers use. In contests, SSP with potentials is enough.

## 2. Formulas, definitions and identities

- **Residual costs**: forward $u\to v$ costs $w(u,v)$, backward $v\to u$ costs $-w(u,v)$.
- **Reduced cost**: $w_\pi(u,v) = w(u,v) + \pi(u) - \pi(v)$. For any path $P$ from $a$ to $b$: $w_\pi(P) = w(P) + \pi(a) - \pi(b)$; for any cycle $C$: $w_\pi(C) = w(C)$.
- **Potential update**: $\pi'(v) = \pi(v) + d_\pi(v)$, where $d_\pi$ are Dijkstra distances under $w_\pi$. Then $w_{\pi'}(u,v) = w_\pi(u,v) + d_\pi(u) - d_\pi(v) \ge 0$, with equality on shortest-path edges.
- **Path cost**: real cost of the augmenting path $=\pi'(t) - \pi'(s)$.
- **Optimality**: $f$ min-cost for its value $\iff$ no negative residual cycle $\iff$ $\exists \pi$ with $w_\pi\ge 0$ on all residual edges (LP complementary slackness).
- **Convexity**: if $c_1\le c_2\le\dots$ are the successive path costs, $\text{cost}(F) = \sum_{i\le F} c_i$ is convex.
- **Convex edge cost**: $g$ convex ⇒ unit edges with costs $\Delta_k = g(k)-g(k-1)$, $k=1..K$. Squares: $k^2-(k-1)^2 = 2k-1$.
- **Assignment as flow**: $s\to$ worker (1, 0), worker $\to$ job (1, $w_{ij}$), job $\to t$ (1, 0); min-cost max-flow = optimal assignment. Maximize by negating weights.
- **Complexity**: SSP $O(F\cdot E\log V)$ (+ $O(VE)$ Bellman–Ford once); dense Dijkstra variant $O(F\cdot V^2)$; cycle canceling (min-mean) $O(V^2E^2\log V)$ (🧊).

## 3. Implementation (C++ and Java)

`MCMF::solve(s, t, maxf, stopNonNeg)` returns `{flow, cost}`. Call `initPotentials(s)` first only if some edge costs are negative. With `stopNonNeg = true` it stops when the
next path would not decrease the cost (min-cost flow of any value up to `maxf`).

```cpp
struct MCMF {
    struct E { int to; ll cap, cost; };
    const ll INF = LLONG_MAX / 4;
    int n;
    vector<E> e; vector<vector<int>> g;
    vector<ll> pot, dist; vector<int> pe;
    MCMF(int n) : n(n), g(n), pot(n, 0), dist(n), pe(n) {}
    int addEdge(int u, int v, ll cap, ll cost) {
        g[u].push_back(e.size()); e.push_back({v, cap, cost});
        g[v].push_back(e.size()); e.push_back({u, 0, -cost});
        return (int)e.size() - 2;
    }
    void initPotentials(int s) {            // Bellman-Ford; needs no negative cycle
        fill(pot.begin(), pot.end(), INF); pot[s] = 0;
        for (int round = 0; round < n; round++) {
            bool changed = false;
            for (int u = 0; u < n; u++) if (pot[u] < INF)
                for (int id : g[u]) if (e[id].cap > 0 && pot[u] + e[id].cost < pot[e[id].to]) { pot[e[id].to] = pot[u] + e[id].cost; changed = true; }
            if (!changed) break;
        }
        for (auto &p : pot) if (p == INF) p = 0;   // unreachable vertices stay unreachable
    }
    pair<ll, ll> solve(int s, int t, ll maxf = LLONG_MAX, bool stopNonNeg = false) {
        ll flow = 0, cost = 0;
        while (flow < maxf) {
            fill(dist.begin(), dist.end(), INF);
            dist[s] = 0;
            priority_queue<pair<ll, int>, vector<pair<ll, int>>, greater<>> pq;
            pq.push({0, s});
            while (!pq.empty()) {
                auto [d, u] = pq.top(); pq.pop();
                if (d > dist[u]) continue;
                for (int id : g[u]) {
                    if (e[id].cap <= 0) continue;
                    int v = e[id].to;
                    ll nd = d + e[id].cost + pot[u] - pot[v];   // reduced cost >= 0
                    if (nd < dist[v]) { dist[v] = nd; pe[v] = id; pq.push({nd, v}); }
                }
            }
            if (dist[t] >= INF) break;
            for (int v = 0; v < n; v++) if (dist[v] < INF) pot[v] += dist[v];
            ll pathCost = pot[t] - pot[s];
            if (stopNonNeg && pathCost >= 0) break;
            ll f = maxf - flow;
            for (int v = t; v != s; v = e[pe[v] ^ 1].to) f = min(f, e[pe[v]].cap);
            for (int v = t; v != s; v = e[pe[v] ^ 1].to) { e[pe[v]].cap -= f; e[pe[v] ^ 1].cap += f; }
            flow += f; cost += f * pathCost;
        }
        return {flow, cost};
    }
};
```

```java
static class MCMF {
    static final long INF = Long.MAX_VALUE / 4;
    int n, cnt = 0;
    int[] head, nxt, to, pe, hv;
    long[] cap, cost, pot, dist, hk;
    int hs;
    MCMF(int n, int maxEdges) {
        this.n = n; head = new int[n]; Arrays.fill(head, -1);
        nxt = new int[2 * maxEdges]; to = new int[2 * maxEdges]; cap = new long[2 * maxEdges]; cost = new long[2 * maxEdges];
        pot = new long[n]; dist = new long[n]; pe = new int[n];
        hk = new long[2 * maxEdges + n + 1]; hv = new int[2 * maxEdges + n + 1];
    }
    int addEdge(int u, int v, long c, long w) {
        to[cnt] = v; cap[cnt] = c; cost[cnt] = w; nxt[cnt] = head[u]; head[u] = cnt++;
        to[cnt] = u; cap[cnt] = 0; cost[cnt] = -w; nxt[cnt] = head[v]; head[v] = cnt++;
        return cnt - 2;
    }
    void initPotentials(int s) {
        Arrays.fill(pot, INF); pot[s] = 0;
        for (int round = 0; round < n; round++) {
            boolean changed = false;
            for (int u = 0; u < n; u++) if (pot[u] < INF)
                for (int e = head[u]; e != -1; e = nxt[e]) if (cap[e] > 0 && pot[u] + cost[e] < pot[to[e]]) { pot[to[e]] = pot[u] + cost[e]; changed = true; }
            if (!changed) break;
        }
        for (int v = 0; v < n; v++) if (pot[v] == INF) pot[v] = 0;
    }
    void push(long k, int v) {                   // binary min-heap with lazy deletion
        int i = hs++;
        while (i > 0) { int p = (i - 1) >> 1; if (hk[p] <= k) break; hk[i] = hk[p]; hv[i] = hv[p]; i = p; }
        hk[i] = k; hv[i] = v;
    }
    long topK; int topV;
    void pop() {
        topK = hk[0]; topV = hv[0];
        long k = hk[--hs]; int v = hv[hs]; int i = 0;
        while (true) {
            int c = 2 * i + 1;
            if (c >= hs) break;
            if (c + 1 < hs && hk[c + 1] < hk[c]) c++;
            if (hk[c] >= k) break;
            hk[i] = hk[c]; hv[i] = hv[c]; i = c;
        }
        hk[i] = k; hv[i] = v;
    }
    long[] solve(int s, int t, long maxf, boolean stopNonNeg) {
        long flow = 0, total = 0;
        while (flow < maxf) {
            Arrays.fill(dist, INF);
            dist[s] = 0; hs = 0; push(0, s);
            while (hs > 0) {
                pop();
                long d = topK; int u = topV;
                if (d > dist[u]) continue;
                for (int e = head[u]; e != -1; e = nxt[e]) {
                    if (cap[e] <= 0) continue;
                    int v = to[e];
                    long nd = d + cost[e] + pot[u] - pot[v];
                    if (nd < dist[v]) { dist[v] = nd; pe[v] = e; push(nd, v); }
                }
            }
            if (dist[t] >= INF) break;
            for (int v = 0; v < n; v++) if (dist[v] < INF) pot[v] += dist[v];
            long pathCost = pot[t] - pot[s];
            if (stopNonNeg && pathCost >= 0) break;
            long f = maxf - flow;
            for (int v = t; v != s; v = to[pe[v] ^ 1]) f = Math.min(f, cap[pe[v]]);
            for (int v = t; v != s; v = to[pe[v] ^ 1]) { cap[pe[v]] -= f; cap[pe[v] ^ 1] += f; }
            flow += f; total += f * pathCost;
        }
        return new long[]{flow, total};
    }
}
```

## 4. Recognising the pattern

| Signal | Model |
|---|---|
| "assign / route / transport" **and** each unit has a price | min-cost flow |
| "minimum total cost to send exactly $k$" | min-cost $k$-flow (`maxf = k`), check `flow == k` |
| "choose at most $k$ disjoint paths/sequences maximizing total value" | negative costs on vertex-split edges, stop when the path cost is $\ge 0$ |
| cost grows like $x^2$ or any convex function of how many units use a resource | unit edges with marginal costs $2k-1$ |
| $n\le 200$–$500$ items, "each paired once", sum of weights | assignment: [Hungarian](05-hungarian-algorithm.md) or MCMF |
| real-valued distances as costs (geometry) | MCMF with `double` costs and an epsilon in Dijkstra |
| flow value small (≤ a few thousand) | SSP is fast; for $10^9$ units with few paths it is still fine (each iteration pushes a whole bottleneck) |

Confusions: if only the *number* matters, plain max flow suffices. If the costs are "per edge used" (fixed charge, not per unit), it is not a min-cost flow — usually a Steiner-type NP-hard problem.

## 5. Worked examples (graded)

### Example 1 — Parcel Delivery  ·  ★ ≈2000

- **Source:** [CSES 2121 · Parcel Delivery](https://cses.fi/problemset/task/2121)
- **Difficulty:** ≈2000 (est.)
- **Problem:** $n\le 500$ cities and $m\le 1000$ directed routes; route $i$ can carry at most $r_i$ parcels and costs $c_i$ per parcel. Send exactly $k\le 100$ parcels from city 1 to city $n$ at
  minimum total cost, or print $-1$.
- **Thinking from first principles:** units with a per-unit price on capacity-limited edges: min-cost $k$-flow. Costs are non-negative, so initial potentials 0 are valid.

<details><summary>Solution</summary>

SSP with `maxf = k`; print the cost if the flow reached $k$, else $-1$. At most $k$ Dijkstras: $O(k\,m\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

struct MCMF {
    struct E { int to; ll cap, cost; };
    const ll INF = LLONG_MAX / 4;
    int n; vector<E> e; vector<vector<int>> g; vector<ll> pot, dist; vector<int> pe;
    MCMF(int n) : n(n), g(n), pot(n, 0), dist(n), pe(n) {}
    int addEdge(int u, int v, ll cap, ll cost) {
        g[u].push_back(e.size()); e.push_back({v, cap, cost});
        g[v].push_back(e.size()); e.push_back({u, 0, -cost});
        return (int)e.size() - 2;
    }
    pair<ll, ll> solve(int s, int t, ll maxf = LLONG_MAX, bool stopNonNeg = false) {
        ll flow = 0, cost = 0;
        while (flow < maxf) {
            fill(dist.begin(), dist.end(), INF); dist[s] = 0;
            priority_queue<pair<ll, int>, vector<pair<ll, int>>, greater<>> pq; pq.push({0, s});
            while (!pq.empty()) {
                auto [d, u] = pq.top(); pq.pop();
                if (d > dist[u]) continue;
                for (int id : g[u]) {
                    if (e[id].cap <= 0) continue;
                    int v = e[id].to; ll nd = d + e[id].cost + pot[u] - pot[v];
                    if (nd < dist[v]) { dist[v] = nd; pe[v] = id; pq.push({nd, v}); }
                }
            }
            if (dist[t] >= INF) break;
            for (int v = 0; v < n; v++) if (dist[v] < INF) pot[v] += dist[v];
            ll pathCost = pot[t] - pot[s];
            if (stopNonNeg && pathCost >= 0) break;
            ll f = maxf - flow;
            for (int v = t; v != s; v = e[pe[v] ^ 1].to) f = min(f, e[pe[v]].cap);
            for (int v = t; v != s; v = e[pe[v] ^ 1].to) { e[pe[v]].cap -= f; e[pe[v] ^ 1].cap += f; }
            flow += f; cost += f * pathCost;
        }
        return {flow, cost};
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m; ll k;
    cin >> n >> m >> k;
    MCMF mf(n);
    for (int i = 0; i < m; i++) { int a, b; ll r, c; cin >> a >> b >> r >> c; mf.addEdge(a - 1, b - 1, r, c); }
    auto [flow, cost] = mf.solve(0, n - 1, k);
    cout << (flow == k ? cost : -1) << "\n";
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

    static class MCMF {
        static final long INF = Long.MAX_VALUE / 4;
        int n, cnt = 0; int[] head, nxt, to, pe, hv; long[] cap, cost, pot, dist, hk; int hs;
        MCMF(int n, int maxEdges) {
            this.n = n; head = new int[n]; Arrays.fill(head, -1);
            nxt = new int[2 * maxEdges]; to = new int[2 * maxEdges]; cap = new long[2 * maxEdges]; cost = new long[2 * maxEdges];
            pot = new long[n]; dist = new long[n]; pe = new int[n];
            hk = new long[2 * maxEdges + n + 1]; hv = new int[2 * maxEdges + n + 1];
        }
        int addEdge(int u, int v, long c, long w) {
            to[cnt] = v; cap[cnt] = c; cost[cnt] = w; nxt[cnt] = head[u]; head[u] = cnt++;
            to[cnt] = u; cap[cnt] = 0; cost[cnt] = -w; nxt[cnt] = head[v]; head[v] = cnt++;
            return cnt - 2;
        }
        void push(long k, int v) { int i = hs++; while (i > 0) { int p = (i - 1) >> 1; if (hk[p] <= k) break; hk[i] = hk[p]; hv[i] = hv[p]; i = p; } hk[i] = k; hv[i] = v; }
        long topK; int topV;
        void pop() {
            topK = hk[0]; topV = hv[0]; long k = hk[--hs]; int v = hv[hs]; int i = 0;
            while (true) { int c = 2 * i + 1; if (c >= hs) break; if (c + 1 < hs && hk[c + 1] < hk[c]) c++; if (hk[c] >= k) break; hk[i] = hk[c]; hv[i] = hv[c]; i = c; }
            hk[i] = k; hv[i] = v;
        }
        long[] solve(int s, int t, long maxf, boolean stopNonNeg) {
            long flow = 0, total = 0;
            while (flow < maxf) {
                Arrays.fill(dist, INF); dist[s] = 0; hs = 0; push(0, s);
                while (hs > 0) {
                    pop(); long d = topK; int u = topV;
                    if (d > dist[u]) continue;
                    for (int e = head[u]; e != -1; e = nxt[e]) {
                        if (cap[e] <= 0) continue;
                        int v = to[e]; long nd = d + cost[e] + pot[u] - pot[v];
                        if (nd < dist[v]) { dist[v] = nd; pe[v] = e; push(nd, v); }
                    }
                }
                if (dist[t] >= INF) break;
                for (int v = 0; v < n; v++) if (dist[v] < INF) pot[v] += dist[v];
                long pathCost = pot[t] - pot[s];
                if (stopNonNeg && pathCost >= 0) break;
                long f = maxf - flow;
                for (int v = t; v != s; v = to[pe[v] ^ 1]) f = Math.min(f, cap[pe[v]]);
                for (int v = t; v != s; v = to[pe[v] ^ 1]) { cap[pe[v]] -= f; cap[pe[v] ^ 1] += f; }
                flow += f; total += f * pathCost;
            }
            return new long[]{flow, total};
        }
    }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt();
        long k = nextLong();
        MCMF mf = new MCMF(n, m);
        for (int i = 0; i < m; i++) { int a = nextInt() - 1, b = nextInt() - 1; long r = nextLong(), c = nextLong(); mf.addEdge(a, b, r, c); }
        long[] res = mf.solve(0, n - 1, k, false);
        System.out.println(res[0] == k ? res[1] : -1);
    }
}
```

</details>

Hand checks: (1) routes $1\to2$ (cap 5, cost 1), $2\to4$ (5, 1), $1\to3$ (5, 2), $3\to4$ (5, 2), $k=7$: five parcels at cost 2 and two at cost 4 → 18. (2) Not enough capacity → $-1$.
(3) $k$ larger than one route but split over a cheap and an expensive parallel route.

<!-- test
in:
4 4 7
1 2 5 1
2 4 5 1
1 3 5 2
3 4 5 2
out:
18
-->
<!-- test
in:
2 1 3
1 2 2 5
out:
-1
-->
<!-- test
in:
2 2 4
1 2 3 10
1 2 9 20
out:
50
-->

### Example 2 — Build String  ·  ★ 2000

- **Source:** [CF 237E · Build String](https://codeforces.com/problemset/problem/237/E) — 2000
- **Difficulty:** 2000
- **Problem:** a target string $t$ ($|t|\le100$) and $n\le 100$ source strings $s_i$, each with a limit $a_i$: at most $a_i$ characters may be taken out of $s_i$, and every character taken
  from $s_i$ costs $i$ rubles. Build $t$ (order does not matter — we only need the multiset of letters) at minimum cost, or print $-1$.
- **Thinking from first principles:** a character of $t$ is a unit; its life is "leave string $i$ (pay $i$, limited by $a_i$ in total) as a letter $\ell$ that $s_i$ contains (limited by the count of
  $\ell$ in $s_i$), and fill one of the $\text{cnt}_t(\ell)$ slots". Each "limited by" is a capacity and the only price is on leaving string $i$.

<details><summary>Solution</summary>

Vertices $s$, string nodes $1..n$, letter nodes $a..z$, $t$. Edges: $s\to i$ (cap $a_i$, cost $i$); $i\to\ell$ (cap $\text{cnt}_{s_i}(\ell)$, cost 0); $\ell\to t$ (cap $\text{cnt}_t(\ell)$, cost 0).
Min-cost max-flow; if the flow is less than $|t|$ print $-1$. At most $|t|$ augmentations on $\approx 130$ vertices.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

struct MCMF {
    struct E { int to; ll cap, cost; };
    const ll INF = LLONG_MAX / 4;
    int n; vector<E> e; vector<vector<int>> g; vector<ll> pot, dist; vector<int> pe;
    MCMF(int n) : n(n), g(n), pot(n, 0), dist(n), pe(n) {}
    int addEdge(int u, int v, ll cap, ll cost) {
        g[u].push_back(e.size()); e.push_back({v, cap, cost});
        g[v].push_back(e.size()); e.push_back({u, 0, -cost});
        return (int)e.size() - 2;
    }
    pair<ll, ll> solve(int s, int t, ll maxf = LLONG_MAX, bool stopNonNeg = false) {
        ll flow = 0, cost = 0;
        while (flow < maxf) {
            fill(dist.begin(), dist.end(), INF); dist[s] = 0;
            priority_queue<pair<ll, int>, vector<pair<ll, int>>, greater<>> pq; pq.push({0, s});
            while (!pq.empty()) {
                auto [d, u] = pq.top(); pq.pop();
                if (d > dist[u]) continue;
                for (int id : g[u]) {
                    if (e[id].cap <= 0) continue;
                    int v = e[id].to; ll nd = d + e[id].cost + pot[u] - pot[v];
                    if (nd < dist[v]) { dist[v] = nd; pe[v] = id; pq.push({nd, v}); }
                }
            }
            if (dist[t] >= INF) break;
            for (int v = 0; v < n; v++) if (dist[v] < INF) pot[v] += dist[v];
            ll pathCost = pot[t] - pot[s];
            if (stopNonNeg && pathCost >= 0) break;
            ll f = maxf - flow;
            for (int v = t; v != s; v = e[pe[v] ^ 1].to) f = min(f, e[pe[v]].cap);
            for (int v = t; v != s; v = e[pe[v] ^ 1].to) { e[pe[v]].cap -= f; e[pe[v] ^ 1].cap += f; }
            flow += f; cost += f * pathCost;
        }
        return {flow, cost};
    }
};

int main() {
    string t;
    int n;
    cin >> t >> n;
    int S = 0, T = n + 27;                       // strings 1..n, letters n+1..n+26
    MCMF mf(n + 28);
    for (int i = 1; i <= n; i++) {
        string s; int a;
        cin >> s >> a;
        mf.addEdge(S, i, a, i);
        int cnt[26] = {};
        for (char ch : s) cnt[ch - 'a']++;
        for (int c = 0; c < 26; c++) if (cnt[c]) mf.addEdge(i, n + 1 + c, cnt[c], 0);
    }
    int need[26] = {};
    for (char ch : t) need[ch - 'a']++;
    for (int c = 0; c < 26; c++) if (need[c]) mf.addEdge(n + 1 + c, T, need[c], 0);
    auto [flow, cost] = mf.solve(S, T);
    cout << (flow == (ll)t.size() ? cost : -1) << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static class MCMF {
        static final long INF = Long.MAX_VALUE / 4;
        int n, cnt = 0; int[] head, nxt, to, pe, hv; long[] cap, cost, pot, dist, hk; int hs;
        MCMF(int n, int maxEdges) {
            this.n = n; head = new int[n]; Arrays.fill(head, -1);
            nxt = new int[2 * maxEdges]; to = new int[2 * maxEdges]; cap = new long[2 * maxEdges]; cost = new long[2 * maxEdges];
            pot = new long[n]; dist = new long[n]; pe = new int[n];
            hk = new long[2 * maxEdges + n + 1]; hv = new int[2 * maxEdges + n + 1];
        }
        int addEdge(int u, int v, long c, long w) {
            to[cnt] = v; cap[cnt] = c; cost[cnt] = w; nxt[cnt] = head[u]; head[u] = cnt++;
            to[cnt] = u; cap[cnt] = 0; cost[cnt] = -w; nxt[cnt] = head[v]; head[v] = cnt++;
            return cnt - 2;
        }
        void push(long k, int v) { int i = hs++; while (i > 0) { int p = (i - 1) >> 1; if (hk[p] <= k) break; hk[i] = hk[p]; hv[i] = hv[p]; i = p; } hk[i] = k; hv[i] = v; }
        long topK; int topV;
        void pop() {
            topK = hk[0]; topV = hv[0]; long k = hk[--hs]; int v = hv[hs]; int i = 0;
            while (true) { int c = 2 * i + 1; if (c >= hs) break; if (c + 1 < hs && hk[c + 1] < hk[c]) c++; if (hk[c] >= k) break; hk[i] = hk[c]; hv[i] = hv[c]; i = c; }
            hk[i] = k; hv[i] = v;
        }
        long[] solve(int s, int t, long maxf, boolean stopNonNeg) {
            long flow = 0, total = 0;
            while (flow < maxf) {
                Arrays.fill(dist, INF); dist[s] = 0; hs = 0; push(0, s);
                while (hs > 0) {
                    pop(); long d = topK; int u = topV;
                    if (d > dist[u]) continue;
                    for (int e = head[u]; e != -1; e = nxt[e]) {
                        if (cap[e] <= 0) continue;
                        int v = to[e]; long nd = d + cost[e] + pot[u] - pot[v];
                        if (nd < dist[v]) { dist[v] = nd; pe[v] = e; push(nd, v); }
                    }
                }
                if (dist[t] >= INF) break;
                for (int v = 0; v < n; v++) if (dist[v] < INF) pot[v] += dist[v];
                long pathCost = pot[t] - pot[s];
                if (stopNonNeg && pathCost >= 0) break;
                long f = maxf - flow;
                for (int v = t; v != s; v = to[pe[v] ^ 1]) f = Math.min(f, cap[pe[v]]);
                for (int v = t; v != s; v = to[pe[v] ^ 1]) { cap[pe[v]] -= f; cap[pe[v] ^ 1] += f; }
                flow += f; total += f * pathCost;
            }
            return new long[]{flow, total};
        }
    }

    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StreamTokenizer st = new StreamTokenizer(br);
        st.nextToken(); String t = st.sval;
        st.nextToken(); int n = (int) st.nval;
        int S = 0, T = n + 27;
        MCMF mf = new MCMF(n + 28, n + 26 * n + 26);
        for (int i = 1; i <= n; i++) {
            st.nextToken(); String s = st.sval;
            st.nextToken(); int a = (int) st.nval;
            mf.addEdge(S, i, a, i);
            int[] cnt = new int[26];
            for (char ch : s.toCharArray()) cnt[ch - 'a']++;
            for (int c = 0; c < 26; c++) if (cnt[c] > 0) mf.addEdge(i, n + 1 + c, cnt[c], 0);
        }
        int[] need = new int[26];
        for (char ch : t.toCharArray()) need[ch - 'a']++;
        for (int c = 0; c < 26; c++) if (need[c] > 0) mf.addEdge(n + 1 + c, T, need[c], 0);
        long[] res = mf.solve(S, T, Long.MAX_VALUE, false);
        System.out.println(res[0] == t.length() ? res[1] : -1);
    }
}
```

</details>

Hand checks: $t=$`bbaze`, strings `bzb` (limit 2), `aeb` (limit 3), `ba` (limit 10): take `b`,`z` from string 1 (cost 2), `a`,`e`,`b` from string 2 (cost 6) → 8. A missing letter → $-1$.

<!-- test
in:
bbaze
3
bzb 2
aeb 3
ba 10
out:
8
-->
<!-- test
in:
abc
1
abcd 2
out:
-1
-->
<!-- test
in:
aa
2
a 1
aa 5
out:
3
-->

### Example 3 — Almost Permutation  ·  ★ 2200

- **Source:** [CF 863F · Almost Permutation](https://codeforces.com/problemset/problem/863/F) — 2200
- **Difficulty:** 2200
- **Problem:** find an array $a_1..a_n$ ($n\le 50$) with $1\le a_i\le n$ satisfying $q\le 100$ facts of the form "for $l\le i\le r$: $a_i\ge v$" or "$a_i\le v$", minimizing
  $\sum_{v=1}^{n}\text{cnt}(v)^2$, where $\text{cnt}(v)$ is how many times $v$ occurs. Print the minimum or $-1$.
- **Thinking from first principles:** the facts only give each position an allowed interval $[lo_i, hi_i]$; positions are independent otherwise. Each position "chooses" a value: a unit going
  position → value. The cost is a **convex** function of how many units reach each value, $\text{cnt}^2$, so split value $\to t$ into unit edges of marginal cost $1,3,5,\dots$ ($k^2-(k-1)^2$).

<details><summary>Solution</summary>

$s\to i$ (1, 0); $i\to v$ for $lo_i\le v\le hi_i$ (1, 0); for each value $v$, $n$ parallel edges $v\to t$ with capacity 1 and costs $1,3,\dots,2n-1$. If some $lo_i>hi_i$, print $-1$;
otherwise the min-cost flow of value $n$ is the answer (it always reaches $n$). $V\approx 2n+2$, $E\approx 2n^2$, $n$ augmentations.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

struct MCMF {
    struct E { int to; ll cap, cost; };
    const ll INF = LLONG_MAX / 4;
    int n; vector<E> e; vector<vector<int>> g; vector<ll> pot, dist; vector<int> pe;
    MCMF(int n) : n(n), g(n), pot(n, 0), dist(n), pe(n) {}
    int addEdge(int u, int v, ll cap, ll cost) {
        g[u].push_back(e.size()); e.push_back({v, cap, cost});
        g[v].push_back(e.size()); e.push_back({u, 0, -cost});
        return (int)e.size() - 2;
    }
    pair<ll, ll> solve(int s, int t, ll maxf = LLONG_MAX, bool stopNonNeg = false) {
        ll flow = 0, cost = 0;
        while (flow < maxf) {
            fill(dist.begin(), dist.end(), INF); dist[s] = 0;
            priority_queue<pair<ll, int>, vector<pair<ll, int>>, greater<>> pq; pq.push({0, s});
            while (!pq.empty()) {
                auto [d, u] = pq.top(); pq.pop();
                if (d > dist[u]) continue;
                for (int id : g[u]) {
                    if (e[id].cap <= 0) continue;
                    int v = e[id].to; ll nd = d + e[id].cost + pot[u] - pot[v];
                    if (nd < dist[v]) { dist[v] = nd; pe[v] = id; pq.push({nd, v}); }
                }
            }
            if (dist[t] >= INF) break;
            for (int v = 0; v < n; v++) if (dist[v] < INF) pot[v] += dist[v];
            ll pathCost = pot[t] - pot[s];
            if (stopNonNeg && pathCost >= 0) break;
            ll f = maxf - flow;
            for (int v = t; v != s; v = e[pe[v] ^ 1].to) f = min(f, e[pe[v]].cap);
            for (int v = t; v != s; v = e[pe[v] ^ 1].to) { e[pe[v]].cap -= f; e[pe[v] ^ 1].cap += f; }
            flow += f; cost += f * pathCost;
        }
        return {flow, cost};
    }
};

int main() {
    int n, q;
    cin >> n >> q;
    vector<int> lo(n + 1, 1), hi(n + 1, n);
    while (q--) {
        int tp, l, r, v;
        cin >> tp >> l >> r >> v;
        for (int i = l; i <= r; i++) { if (tp == 1) lo[i] = max(lo[i], v); else hi[i] = min(hi[i], v); }
    }
    for (int i = 1; i <= n; i++) if (lo[i] > hi[i]) { cout << -1 << "\n"; return 0; }
    int S = 0, T = 2 * n + 1;                    // positions 1..n, values n+1..2n
    MCMF mf(2 * n + 2);
    for (int i = 1; i <= n; i++) {
        mf.addEdge(S, i, 1, 0);
        for (int v = lo[i]; v <= hi[i]; v++) mf.addEdge(i, n + v, 1, 0);
    }
    for (int v = 1; v <= n; v++) for (int k = 1; k <= n; k++) mf.addEdge(n + v, T, 1, 2 * k - 1);
    cout << mf.solve(S, T).second << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static class MCMF {
        static final long INF = Long.MAX_VALUE / 4;
        int n, cnt = 0; int[] head, nxt, to, pe, hv; long[] cap, cost, pot, dist, hk; int hs;
        MCMF(int n, int maxEdges) {
            this.n = n; head = new int[n]; Arrays.fill(head, -1);
            nxt = new int[2 * maxEdges]; to = new int[2 * maxEdges]; cap = new long[2 * maxEdges]; cost = new long[2 * maxEdges];
            pot = new long[n]; dist = new long[n]; pe = new int[n];
            hk = new long[2 * maxEdges + n + 1]; hv = new int[2 * maxEdges + n + 1];
        }
        int addEdge(int u, int v, long c, long w) {
            to[cnt] = v; cap[cnt] = c; cost[cnt] = w; nxt[cnt] = head[u]; head[u] = cnt++;
            to[cnt] = u; cap[cnt] = 0; cost[cnt] = -w; nxt[cnt] = head[v]; head[v] = cnt++;
            return cnt - 2;
        }
        void push(long k, int v) { int i = hs++; while (i > 0) { int p = (i - 1) >> 1; if (hk[p] <= k) break; hk[i] = hk[p]; hv[i] = hv[p]; i = p; } hk[i] = k; hv[i] = v; }
        long topK; int topV;
        void pop() {
            topK = hk[0]; topV = hv[0]; long k = hk[--hs]; int v = hv[hs]; int i = 0;
            while (true) { int c = 2 * i + 1; if (c >= hs) break; if (c + 1 < hs && hk[c + 1] < hk[c]) c++; if (hk[c] >= k) break; hk[i] = hk[c]; hv[i] = hv[c]; i = c; }
            hk[i] = k; hv[i] = v;
        }
        long[] solve(int s, int t, long maxf, boolean stopNonNeg) {
            long flow = 0, total = 0;
            while (flow < maxf) {
                Arrays.fill(dist, INF); dist[s] = 0; hs = 0; push(0, s);
                while (hs > 0) {
                    pop(); long d = topK; int u = topV;
                    if (d > dist[u]) continue;
                    for (int e = head[u]; e != -1; e = nxt[e]) {
                        if (cap[e] <= 0) continue;
                        int v = to[e]; long nd = d + cost[e] + pot[u] - pot[v];
                        if (nd < dist[v]) { dist[v] = nd; pe[v] = e; push(nd, v); }
                    }
                }
                if (dist[t] >= INF) break;
                for (int v = 0; v < n; v++) if (dist[v] < INF) pot[v] += dist[v];
                long pathCost = pot[t] - pot[s];
                if (stopNonNeg && pathCost >= 0) break;
                long f = maxf - flow;
                for (int v = t; v != s; v = to[pe[v] ^ 1]) f = Math.min(f, cap[pe[v]]);
                for (int v = t; v != s; v = to[pe[v] ^ 1]) { cap[pe[v]] -= f; cap[pe[v] ^ 1] += f; }
                flow += f; total += f * pathCost;
            }
            return new long[]{flow, total};
        }
    }

    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        st.nextToken(); int q = (int) st.nval;
        int[] lo = new int[n + 1], hi = new int[n + 1];
        Arrays.fill(lo, 1); Arrays.fill(hi, n);
        for (int k = 0; k < q; k++) {
            st.nextToken(); int tp = (int) st.nval; st.nextToken(); int l = (int) st.nval;
            st.nextToken(); int r = (int) st.nval; st.nextToken(); int v = (int) st.nval;
            for (int i = l; i <= r; i++) { if (tp == 1) lo[i] = Math.max(lo[i], v); else hi[i] = Math.min(hi[i], v); }
        }
        for (int i = 1; i <= n; i++) if (lo[i] > hi[i]) { System.out.println(-1); return; }
        int S = 0, T = 2 * n + 1;
        MCMF mf = new MCMF(2 * n + 2, n + n * n + n * n);
        for (int i = 1; i <= n; i++) {
            mf.addEdge(S, i, 1, 0);
            for (int v = lo[i]; v <= hi[i]; v++) mf.addEdge(i, n + v, 1, 0);
        }
        for (int v = 1; v <= n; v++) for (int k = 1; k <= n; k++) mf.addEdge(n + v, T, 1, 2 * k - 1);
        System.out.println(mf.solve(S, T, Long.MAX_VALUE, false)[1]);
    }
}
```

</details>

Hand checks: no facts → a permutation, cost $n$. All positions forced to 1 ($a_i\le1$) → $n^2$. Contradictory facts → $-1$.

<!-- test
in:
3 0
out:
3
-->
<!-- test
in:
3 1
2 1 3 1
out:
9
-->
<!-- test
in:
3 2
1 1 3 2
2 1 3 1
out:
-1
-->
<!-- test
in:
4 2
1 1 2 3
2 3 4 2
out:
4
-->

### Example 4 — Binary Tree on Plane  ·  ★ 2400

- **Source:** [CF 277E · Binary Tree on Plane](https://codeforces.com/problemset/problem/277/E) — 2400
- **Difficulty:** 2400
- **Problem:** $n\le 400$ distinct points. Build a rooted binary tree on them (every node has at most 2 children) in which every arc goes from a parent to a child with **strictly smaller $y$**.
  Minimize the total Euclidean length of the arcs, or print $-1$ if impossible.
- **Thinking from first principles:** a rooted tree = every non-root node picks exactly one parent; "at most 2 children" = each node is picked at most twice. So it is an *assignment of children
  to parents* with capacity 2 on the parent side and cost = distance — a min-cost flow on a bipartite graph. Cycles are impossible because $y$ strictly decreases along arcs, so any choice of
  parents is a tree. The root is forced (the unique highest point); if two points share the top $y$, nobody can be the parent of either one, the flow is short, and we print $-1$.

<details><summary>Solution</summary>

$s\to u_{par}$ (cap 2, cost 0) for every node; $u_{par}\to v_{ch}$ (cap 1, cost $\lVert u-v\rVert$) when $y_u>y_v$; $v_{ch}\to t$ (cap 1, cost 0). We need flow $n-1$.
Costs are real, so the MCMF uses `double` with a small epsilon in Dijkstra. $O(n\cdot n^2\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct MCMFD {                                   // double costs, integer capacities
    struct E { int to, cap; double cost; };
    const double INF = 1e18, EPS = 1e-9;
    int n; vector<E> e; vector<vector<int>> g; vector<double> pot, dist; vector<int> pe;
    MCMFD(int n) : n(n), g(n), pot(n, 0), dist(n), pe(n) {}
    void addEdge(int u, int v, int cap, double cost) {
        g[u].push_back(e.size()); e.push_back({v, cap, cost});
        g[v].push_back(e.size()); e.push_back({u, 0, -cost});
    }
    pair<int, double> solve(int s, int t, int maxf) {
        int flow = 0; double cost = 0;
        while (flow < maxf) {
            fill(dist.begin(), dist.end(), INF); dist[s] = 0;
            priority_queue<pair<double, int>, vector<pair<double, int>>, greater<>> pq; pq.push({0, s});
            while (!pq.empty()) {
                auto [d, u] = pq.top(); pq.pop();
                if (d > dist[u] + EPS) continue;
                for (int id : g[u]) {
                    if (e[id].cap <= 0) continue;
                    int v = e[id].to; double nd = d + e[id].cost + pot[u] - pot[v];
                    if (nd < dist[v] - EPS) { dist[v] = nd; pe[v] = id; pq.push({nd, v}); }
                }
            }
            if (dist[t] >= INF / 2) break;
            for (int v = 0; v < n; v++) if (dist[v] < INF / 2) pot[v] += dist[v];
            int f = maxf - flow;
            for (int v = t; v != s; v = e[pe[v] ^ 1].to) f = min(f, e[pe[v]].cap);
            for (int v = t; v != s; v = e[pe[v] ^ 1].to) { e[pe[v]].cap -= f; e[pe[v] ^ 1].cap += f; cost += f * e[pe[v]].cost; }
            flow += f;
        }
        return {flow, cost};
    }
};

int main() {
    int n;
    cin >> n;
    vector<double> x(n), y(n);
    for (int i = 0; i < n; i++) cin >> x[i] >> y[i];
    int S = 2 * n, T = 2 * n + 1;                // parent copies 0..n-1, child copies n..2n-1
    MCMFD mf(2 * n + 2);
    for (int u = 0; u < n; u++) { mf.addEdge(S, u, 2, 0); mf.addEdge(n + u, T, 1, 0); }
    for (int u = 0; u < n; u++)
        for (int v = 0; v < n; v++)
            if (y[u] > y[v]) mf.addEdge(u, n + v, 1, hypot(x[u] - x[v], y[u] - y[v]));
    auto [flow, cost] = mf.solve(S, T, n - 1);
    if (flow < n - 1) cout << -1 << "\n";
    else cout << fixed << setprecision(10) << cost << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static class MCMFD {
        static final double INF = 1e18, EPS = 1e-9;
        int n, cnt = 0; int[] head, nxt, to, cap, pe, hv; double[] cost, pot, dist, hk; int hs;
        MCMFD(int n, int maxEdges) {
            this.n = n; head = new int[n]; Arrays.fill(head, -1);
            nxt = new int[2 * maxEdges]; to = new int[2 * maxEdges]; cap = new int[2 * maxEdges]; cost = new double[2 * maxEdges];
            pot = new double[n]; dist = new double[n]; pe = new int[n];
            hk = new double[2 * maxEdges + n + 1]; hv = new int[2 * maxEdges + n + 1];
        }
        void addEdge(int u, int v, int c, double w) {
            to[cnt] = v; cap[cnt] = c; cost[cnt] = w; nxt[cnt] = head[u]; head[u] = cnt++;
            to[cnt] = u; cap[cnt] = 0; cost[cnt] = -w; nxt[cnt] = head[v]; head[v] = cnt++;
        }
        void push(double k, int v) { int i = hs++; while (i > 0) { int p = (i - 1) >> 1; if (hk[p] <= k) break; hk[i] = hk[p]; hv[i] = hv[p]; i = p; } hk[i] = k; hv[i] = v; }
        double topK; int topV;
        void pop() {
            topK = hk[0]; topV = hv[0]; double k = hk[--hs]; int v = hv[hs]; int i = 0;
            while (true) { int c = 2 * i + 1; if (c >= hs) break; if (c + 1 < hs && hk[c + 1] < hk[c]) c++; if (hk[c] >= k) break; hk[i] = hk[c]; hv[i] = hv[c]; i = c; }
            hk[i] = k; hv[i] = v;
        }
        double[] solve(int s, int t, int maxf) {
            int flow = 0; double total = 0;
            while (flow < maxf) {
                Arrays.fill(dist, INF); dist[s] = 0; hs = 0; push(0, s);
                while (hs > 0) {
                    pop(); double d = topK; int u = topV;
                    if (d > dist[u] + EPS) continue;
                    for (int e = head[u]; e != -1; e = nxt[e]) {
                        if (cap[e] <= 0) continue;
                        int v = to[e]; double nd = d + cost[e] + pot[u] - pot[v];
                        if (nd < dist[v] - EPS) { dist[v] = nd; pe[v] = e; push(nd, v); }
                    }
                }
                if (dist[t] >= INF / 2) break;
                for (int v = 0; v < n; v++) if (dist[v] < INF / 2) pot[v] += dist[v];
                int f = maxf - flow;
                for (int v = t; v != s; v = to[pe[v] ^ 1]) f = Math.min(f, cap[pe[v]]);
                for (int v = t; v != s; v = to[pe[v] ^ 1]) { cap[pe[v]] -= f; cap[pe[v] ^ 1] += f; total += f * cost[pe[v]]; }
                flow += f;
            }
            return new double[]{flow, total};
        }
    }

    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        double[] x = new double[n], y = new double[n];
        for (int i = 0; i < n; i++) { st.nextToken(); x[i] = st.nval; st.nextToken(); y[i] = st.nval; }
        int S = 2 * n, T = 2 * n + 1;
        MCMFD mf = new MCMFD(2 * n + 2, 2 * n + n * (n - 1) / 2);
        for (int u = 0; u < n; u++) { mf.addEdge(S, u, 2, 0); mf.addEdge(n + u, T, 1, 0); }
        for (int u = 0; u < n; u++)
            for (int v = 0; v < n; v++)
                if (y[u] > y[v]) mf.addEdge(u, n + v, 1, Math.hypot(x[u] - x[v], y[u] - y[v]));
        double[] res = mf.solve(S, T, n - 1);
        if (res[0] < n - 1) System.out.println(-1);
        else System.out.printf("%.10f%n", res[1]);
    }
}
```

</details>

Hand checks: (1) root $(2,1)$ with children $(1,0)$ and $(3,0)$ → $2\sqrt2\approx 2.8284271247$. (2) Two points at the top level → $-1$. (3) Four points in a vertical-ish chain where the
root cannot take three children: root $(0,3)$ over $(-1,2),(1,2)$ and $(0,0)$; the cheapest valid tree hangs $(0,0)$ under one of the middle points: $2\sqrt2+\sqrt5\approx 5.0644951022$.
(4) A single point → 0.

<!-- test
in:
3
1 0
2 1
3 0
out:
2.8284271247
-->
<!-- test
in:
2
0 0
1 0
out:
-1
-->
<!-- test
in:
4
0 3
-1 2
1 2
0 0
out:
5.0644951022
-->
<!-- test
in:
1
5 5
out:
0.0000000000
-->

### Example 5 — Treasure robots on a DAG (negative costs)  ·  ★ ≈2300

- **Source:** Original problem.
- **Difficulty:** ≈2300 (est.)
- **Problem:** a DAG with $n\le 200$ vertices (every edge $u\to v$ has $u<v$, $m\le 4000$) and a value $w_v\in[-1000,1000]$ on each vertex. Up to $k\le n$ robots each walk a path (start and
  end anywhere, possibly a single vertex); paths must be vertex-disjoint. A robot collects the values of the vertices it visits; unused robots are allowed. Maximize the total.
- **Thinking from first principles:** "vertex-disjoint paths" → split vertices with capacity 1. "Collect value" → the split edge has cost $-w_v$ (profit as negative cost). Robots start/end anywhere →
  $s\to v_{in}$ and $v_{out}\to t$ with cost 0. "Up to $k$" + "unused allowed" → min-cost flow of *any* value $\le k$: by convexity of cost$(F)$, stop at the first non-negative augmenting path.
  Negative costs ⇒ Bellman–Ford for the first potentials; it is safe because the graph is a DAG (no negative cycles).

<details><summary>Solution</summary>

Super source $S\to s$ with capacity $k$; $s\to v_{in}$ (1, 0); $v_{in}\to v_{out}$ (1, $-w_v$); $v_{out}\to t$ (1, 0); $u_{out}\to v_{in}$ (1, 0) for each edge. Run `initPotentials(S)`, then
`solve(S, t, k, true)`; the answer is $-\text{cost}$. Complexity $O(VE)$ + $O(k\,E\log V)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

struct MCMF {
    struct E { int to; ll cap, cost; };
    const ll INF = LLONG_MAX / 4;
    int n; vector<E> e; vector<vector<int>> g; vector<ll> pot, dist; vector<int> pe;
    MCMF(int n) : n(n), g(n), pot(n, 0), dist(n), pe(n) {}
    int addEdge(int u, int v, ll cap, ll cost) {
        g[u].push_back(e.size()); e.push_back({v, cap, cost});
        g[v].push_back(e.size()); e.push_back({u, 0, -cost});
        return (int)e.size() - 2;
    }
    void initPotentials(int s) {
        fill(pot.begin(), pot.end(), INF); pot[s] = 0;
        for (int round = 0; round < n; round++) {
            bool changed = false;
            for (int u = 0; u < n; u++) if (pot[u] < INF)
                for (int id : g[u]) if (e[id].cap > 0 && pot[u] + e[id].cost < pot[e[id].to]) { pot[e[id].to] = pot[u] + e[id].cost; changed = true; }
            if (!changed) break;
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
                for (int id : g[u]) {
                    if (e[id].cap <= 0) continue;
                    int v = e[id].to; ll nd = d + e[id].cost + pot[u] - pot[v];
                    if (nd < dist[v]) { dist[v] = nd; pe[v] = id; pq.push({nd, v}); }
                }
            }
            if (dist[t] >= INF) break;
            for (int v = 0; v < n; v++) if (dist[v] < INF) pot[v] += dist[v];
            ll pathCost = pot[t] - pot[s];
            if (stopNonNeg && pathCost >= 0) break;
            ll f = maxf - flow;
            for (int v = t; v != s; v = e[pe[v] ^ 1].to) f = min(f, e[pe[v]].cap);
            for (int v = t; v != s; v = e[pe[v] ^ 1].to) { e[pe[v]].cap -= f; e[pe[v] ^ 1].cap += f; }
            flow += f; cost += f * pathCost;
        }
        return {flow, cost};
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m, k;
    cin >> n >> m >> k;
    int S = 2 * n, s = 2 * n + 1, t = 2 * n + 2;     // v_in = v, v_out = v + n
    MCMF mf(2 * n + 3);
    mf.addEdge(S, s, k, 0);
    for (int v = 0; v < n; v++) {
        ll w; cin >> w;
        mf.addEdge(s, v, 1, 0);
        mf.addEdge(v, v + n, 1, -w);
        mf.addEdge(v + n, t, 1, 0);
    }
    for (int i = 0; i < m; i++) { int u, v; cin >> u >> v; mf.addEdge(u - 1 + n, v - 1, 1, 0); }
    mf.initPotentials(S);
    cout << -mf.solve(S, t, k, true).second << "\n";
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

    static class MCMF {
        static final long INF = Long.MAX_VALUE / 4;
        int n, cnt = 0; int[] head, nxt, to, pe, hv; long[] cap, cost, pot, dist, hk; int hs;
        MCMF(int n, int maxEdges) {
            this.n = n; head = new int[n]; Arrays.fill(head, -1);
            nxt = new int[2 * maxEdges]; to = new int[2 * maxEdges]; cap = new long[2 * maxEdges]; cost = new long[2 * maxEdges];
            pot = new long[n]; dist = new long[n]; pe = new int[n];
            hk = new long[2 * maxEdges + n + 1]; hv = new int[2 * maxEdges + n + 1];
        }
        int addEdge(int u, int v, long c, long w) {
            to[cnt] = v; cap[cnt] = c; cost[cnt] = w; nxt[cnt] = head[u]; head[u] = cnt++;
            to[cnt] = u; cap[cnt] = 0; cost[cnt] = -w; nxt[cnt] = head[v]; head[v] = cnt++;
            return cnt - 2;
        }
        void initPotentials(int s) {
            Arrays.fill(pot, INF); pot[s] = 0;
            for (int round = 0; round < n; round++) {
                boolean changed = false;
                for (int u = 0; u < n; u++) if (pot[u] < INF)
                    for (int e = head[u]; e != -1; e = nxt[e]) if (cap[e] > 0 && pot[u] + cost[e] < pot[to[e]]) { pot[to[e]] = pot[u] + cost[e]; changed = true; }
                if (!changed) break;
            }
            for (int v = 0; v < n; v++) if (pot[v] == INF) pot[v] = 0;
        }
        void push(long k, int v) { int i = hs++; while (i > 0) { int p = (i - 1) >> 1; if (hk[p] <= k) break; hk[i] = hk[p]; hv[i] = hv[p]; i = p; } hk[i] = k; hv[i] = v; }
        long topK; int topV;
        void pop() {
            topK = hk[0]; topV = hv[0]; long k = hk[--hs]; int v = hv[hs]; int i = 0;
            while (true) { int c = 2 * i + 1; if (c >= hs) break; if (c + 1 < hs && hk[c + 1] < hk[c]) c++; if (hk[c] >= k) break; hk[i] = hk[c]; hv[i] = hv[c]; i = c; }
            hk[i] = k; hv[i] = v;
        }
        long[] solve(int s, int t, long maxf, boolean stopNonNeg) {
            long flow = 0, total = 0;
            while (flow < maxf) {
                Arrays.fill(dist, INF); dist[s] = 0; hs = 0; push(0, s);
                while (hs > 0) {
                    pop(); long d = topK; int u = topV;
                    if (d > dist[u]) continue;
                    for (int e = head[u]; e != -1; e = nxt[e]) {
                        if (cap[e] <= 0) continue;
                        int v = to[e]; long nd = d + cost[e] + pot[u] - pot[v];
                        if (nd < dist[v]) { dist[v] = nd; pe[v] = e; push(nd, v); }
                    }
                }
                if (dist[t] >= INF) break;
                for (int v = 0; v < n; v++) if (dist[v] < INF) pot[v] += dist[v];
                long pathCost = pot[t] - pot[s];
                if (stopNonNeg && pathCost >= 0) break;
                long f = maxf - flow;
                for (int v = t; v != s; v = to[pe[v] ^ 1]) f = Math.min(f, cap[pe[v]]);
                for (int v = t; v != s; v = to[pe[v] ^ 1]) { cap[pe[v]] -= f; cap[pe[v] ^ 1] += f; }
                flow += f; total += f * pathCost;
            }
            return new long[]{flow, total};
        }
    }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt(), k = nextInt();
        int S = 2 * n, s = 2 * n + 1, t = 2 * n + 2;
        MCMF mf = new MCMF(2 * n + 3, 1 + 3 * n + m);
        mf.addEdge(S, s, k, 0);
        for (int v = 0; v < n; v++) {
            long w = nextLong();
            mf.addEdge(s, v, 1, 0);
            mf.addEdge(v, v + n, 1, -w);
            mf.addEdge(v + n, t, 1, 0);
        }
        for (int i = 0; i < m; i++) { int u = nextInt() - 1, v = nextInt() - 1; mf.addEdge(u + n, v, 1, 0); }
        mf.initPotentials(S);
        System.out.println(-mf.solve(S, t, k, true)[1]);
    }
}
```

</details>

Hand checks: (1) path $1\to2\to3$ with values $5,-1,5$ and one robot: walking all three gives 9, better than any single vertex. With two robots: $5+5 = 10$ (skip the $-1$). (2) All values negative → 0 (no robot moves).

<!-- test
in:
3 2 1
5 -1 5
1 2
2 3
out:
9
-->
<!-- test
in:
3 2 2
5 -1 5
1 2
2 3
out:
10
-->
<!-- test
in:
2 1 2
-3 -4
1 2
out:
0
-->
<!-- test
in:
4 3 1
1 2 3 4
1 2
3 4
2 3
out:
10
-->

## 6. Tricks, pitfalls and things to remember

1. **Potentials must start valid.** With any negative cost, run Bellman–Ford once; with Dijkstra on negative reduced costs the answer is silently wrong.
2. **Only update potentials of reached vertices** (`dist < INF`). Adding INF corrupts them.
3. **Path cost is $\pi(t)-\pi(s)$ after the update**, not `dist[t]` (that is the *reduced* cost).
4. **Overflow:** `flow × cost` can exceed 64 bits only if both are huge — check bounds; INF potentials must not be added to real values.
5. **"Exactly $k$" vs "at most $k$" vs "max flow":** pass `maxf`, check `flow == k`, or use `stopNonNeg`. Mixing them is the most common WA.
6. **Maximization:** negate profits; never add a large constant to make costs positive unless *every* $s$–$t$ path has the same number of such edges (otherwise the optimum changes).
7. **Convex costs only.** Unit-edge splitting works because marginal costs are non-decreasing; concave costs make the flow pick cheap units out of order.
8. **Floating costs:** compare with an epsilon in Dijkstra; accumulate the real cost from edge costs (not from potential differences) to limit error drift.
9. **Dense graphs ($E\approx V^2$):** an $O(V^2)$ array Dijkstra is faster than the heap. In Java, avoid `PriorityQueue<long[]>` allocations in the inner loop.
10. **SSP is pseudo-polynomial.** If the flow value is $10^9$ but the bottlenecks are large, it is still fast; if the instance forces many unit augmentations with big $F$, consider cost scaling (🧊).

## 7. Going further (toward 2400–2600+)

- **Min-cost circulation with lower bounds and negative cycles** — [CF 708D · Incorrect Flow](https://codeforces.com/problemset/problem/708/D) — 2900,
  [CF 1288F · Red-Blue Graph](https://codeforces.com/problemset/problem/1288/F) — 2900.
- **"$k$ disjoint subsequences" family**: [CF 818G · Four Melodies](https://codeforces.com/problemset/problem/818/G) — 2600 needs a compressed network to fit $O(n^2)$ edges.
- **Simulating min-cost flow with heaps** (regret greedy): when the network is a line, augmenting paths correspond to "undo an earlier choice" moves; see
  [CF 280D · k-Maximum Subsequence Sum](https://codeforces.com/problemset/problem/280/D) — 2800 and [greedy with regret](../03-Greedy-Constructive-Interactive/02-greedy-with-heaps-and-regret.md).
- **Parametric cost / convexity in $F$**: since cost$(F)$ is convex, Lagrangian ("Aliens") tricks apply — [WQS binary search](../07-DP-Optimizations/06-aliens-trick-wqs-binary-search.md).
- **LP duality view:** potentials are dual variables; the Hungarian algorithm ([05](05-hungarian-algorithm.md)) is SSP specialized to the assignment network with dense $O(n^2)$ Dijkstra.

## 8. Practice ladder

≤ 2100
- [ ] [CSES 2121 · Parcel Delivery](https://cses.fi/problemset/task/2121) — Example 1
- [ ] [AtCoder PRACTICE2 E · MinCostFlow](https://atcoder.jp/contests/practice2/tasks/practice2_e) — grid selection with row/column limits, profits as negative costs
- [ ] [CF 1437C · Chef Monocarp](https://codeforces.com/problemset/problem/1437/C) — 1800 — dishes to minutes with $|t-T_i|$ cost
- [ ] [CF 1525D · Armchairs](https://codeforces.com/problemset/problem/1525/D) — 1800 — min-cost matching on a line (DP is intended; flow is a check)
- [ ] [CF 237E · Build String](https://codeforces.com/problemset/problem/237/E) — 2000 — Example 2
- [ ] [CSES 2130 · Distinct Routes II](https://cses.fi/problemset/task/2130) — $k$ edge-disjoint paths with minimum total length

2100–2500
- [ ] [CF 863F · Almost Permutation](https://codeforces.com/problemset/problem/863/F) — 2200 — Example 3 (convex costs)
- [ ] [AtCoder ABC247 G · Dream Team](https://atcoder.jp/contests/abc247/tasks/abc247_g) — answer for every team size $k$ = successive path costs
- [ ] [CF 277E · Binary Tree on Plane](https://codeforces.com/problemset/problem/277/E) — 2400 — Example 4
- [ ] [CF 802M2 · April Fools' Problem (medium)](https://codeforces.com/problemset/problem/802/M2) — 2400 — preparation/printing days as min-cost flow
- [ ] [CF 1913E · Matrix Problem](https://codeforces.com/problemset/problem/1913/E) — 2400 — row/column sums, cost = changed cells
- [ ] [AtCoder ABC231 H · Minimum Coloring](https://atcoder.jp/contests/abc231/tasks/abc231_h) — minimum-cost edge cover via flow

2500+
- [ ] [CF 1061E · Politics](https://codeforces.com/problemset/problem/1061/E) — 2600 — two trees of constraints, cost on chosen cities
- [ ] [CF 818G · Four Melodies](https://codeforces.com/problemset/problem/818/G) — 2600 — compressed graph + negative costs
- [ ] [CF 1107F · Vasya and Endless Credits](https://codeforces.com/problemset/problem/1107/F) — 2600 — assignment of offers to months
- [ ] [AtCoder ABC214 H · Collecting](https://atcoder.jp/contests/abc214/tasks/abc214_h) — SCC condensation + $k$ disjoint-ish paths with profits
- [ ] [CF 708D · Incorrect Flow](https://codeforces.com/problemset/problem/708/D) — 2900 — min-cost repair of a flow

## 9. LeetCode / FAANG cross-reference

Rare in interviews: min-cost flow is beyond interview scope. Interview problems with the same *shape* use tiny $n$ and bitmask DP or backtracking:

- [LC 2850 · Minimum Moves to Spread Stones Over Grid](https://leetcode.com/problems/minimum-moves-to-spread-stones-over-grid/) — Medium — min-cost assignment of surplus stones to empty cells.
- [LC 1066 · Campus Bikes II](https://leetcode.com/problems/campus-bikes-ii/) — Medium 🔒 — min-cost assignment of bikes to workers.
- [LC 1595 · Minimum Cost to Connect Two Groups of Points](https://leetcode.com/problems/minimum-cost-to-connect-two-groups-of-points/) — Hard — minimum-cost edge cover in a bipartite graph (bitmask DP in interviews, flow in CP).

## 10. Self-check

1. State the optimality criterion for min-cost flow and prove one direction.
2. Why does augmenting along a shortest residual path preserve "no negative cycles"?
3. What is a reduced cost and why does Dijkstra on reduced costs find real shortest paths?
4. How do you initialize potentials when input costs are negative, and when is that impossible?
5. Why is cost$(F)$ convex, and how does that justify "stop when the path cost is non-negative"?
6. How do you model a cost of $x^2$ for $x$ units through a resource? Why does it fail for $\sqrt x$?
7. In Binary Tree on Plane, why can the parent choices never form a cycle?
8. What is the complexity of SSP, and when is it too slow?

<details><summary>Answers</summary>

1. Min-cost for its value iff no negative residual cycle. If a negative cycle exists, pushing around it lowers the cost without changing the value. Conversely $f^*-f$ is a circulation decomposing into residual cycles with total cost $<0$ if $f$ is not optimal.
2. With shortest distances $d$, all residual edges have $w+d(u)-d(v)\ge0$ and path edges have 0, so the new backward edges also have 0; non-negative reduced costs forbid negative cycles.
3. $w_\pi(u,v)=w(u,v)+\pi(u)-\pi(v)$. Along any $s$–$t$ path it telescopes to $w(P)+\pi(s)-\pi(t)$, a constant shift, so the order of paths is preserved and all edge weights are non-negative.
4. Bellman–Ford from $s$ on the initial graph; impossible if the input has a negative cycle reachable from $s$ (then saturate negative edges first or cancel cycles).
5. The successive path costs are non-decreasing (residual distances only grow), so cost$(F)$ has non-decreasing slopes; once a slope is $\ge0$ all later ones are too.
6. Parallel unit edges with costs $1,3,5,\dots$; for $\sqrt x$ the marginal costs decrease, so flow would use the "later" cheap units first and the cost would be wrong.
7. Every arc goes to a strictly lower $y$, so following parents strictly increases $y$ — no cycle; with $n-1$ parent choices and one root it is a tree.
8. $O(F\cdot E\log V)$ (plus one Bellman–Ford). Too slow when $F$ is large *and* every augmentation pushes only a little flow.

</details>
