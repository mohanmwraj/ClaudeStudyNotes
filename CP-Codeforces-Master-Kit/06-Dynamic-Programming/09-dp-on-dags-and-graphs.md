# DP on DAGs and Graphs

> **Band:** 🔵→🟠 1300–2400 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [DP first principles](01-dp-first-principles-and-state-design.md), [topological sort](../09-Graphs/04-topological-sort-and-dag-dp.md), [shortest paths](../09-Graphs/02-shortest-paths.md), [SCC](../09-Graphs/05-scc-and-condensation.md)
> **You can say you know this when:** you can run any DP on an explicit DAG in topological order; count shortest paths (and min/max edges among them) on the shortest-path DAG; condense cycles with SCCs before a DP; solve functional-graph problems by peeling trees off cycles; and recognise when "DP with states that can loop" must become Dijkstra on a product graph.

Every DP is a path problem on a DAG of states ([first principles](01-dp-first-principles-and-state-design.md) §1.3). In this file the DAG is *given* — a directed acyclic graph in the input, a shortest-path DAG hidden inside a weighted graph, or the condensation of a graph with cycles — and the skill is to (a) find a topological order, (b) recognise what to do when the graph is *not* acyclic.

---

## 1. First principles — why this works

### 1.1 DP in topological order

On a DAG, a topological order lists every vertex after all its predecessors. Any recurrence of the form "value of $v$ from values of its predecessors" (pull) or "push $v$'s value to its successors" is correct if vertices are processed in that order:

$$\text{longest}(v) = \max_{(u\to v)} \text{longest}(u) + w(u,v), \qquad \text{ways}(v) = \sum_{(u \to v)} \text{ways}(u).$$

$O(n + m)$ for both. Negative weights are fine — the only requirement is acyclicity. Kahn's algorithm (repeatedly remove a vertex of in-degree 0) produces the order iteratively and detects cycles (fewer than $n$ vertices removed). A memoised DFS ("longest path starting at $v$") is the top-down equivalent but recurses up to depth $n$.

### 1.2 Hidden DAGs: the shortest-path DAG

With non-negative edge weights and $d(\cdot)$ = shortest distance from $s$, call edge $(u \to v, w)$ **tight** if $d(u) + w = d(v)$. A path from $s$ is a shortest path iff all its edges are tight. With strictly positive weights the tight edges form a DAG — $d$ strictly increases along them — and **Dijkstra's pop order is a topological order** of it.

So after Dijkstra, any DP over shortest paths is a DAG DP over tight edges in pop order:

- number of shortest paths: $\text{cnt}(v) = \sum_{\text{tight } u\to v} \text{cnt}(u)$;
- fewest / most edges among shortest paths: $\min / \max$ of $\text{len}(u)+1$;
- "is edge $e$ on every shortest path?" — compare $\text{cnt}_s(u)\cdot\text{cnt}_t(v)$ with $\text{cnt}_s(t)$ (use two moduli or hashing, CF 567E).

You can even do it inside Dijkstra: when a vertex is popped, its value is final; relaxing an edge with equality adds to the count, with strict improvement resets it.

**Zero-weight edges** break this: tight edges may form zero-weight cycles, the pop order is no longer topological among equal distances, and counts can be infinite. Then condense tight zero-weight cycles (SCC) or reason separately.

### 1.3 Cycles: condense first

If the graph has cycles but the DP value of a cycle is "everything on it" (you can walk around freely), contract each **strongly connected component** into a single vertex. Inside an SCC every vertex reaches every other, so a walk entering the SCC can collect all of it; the condensation is a DAG; run the DP there. Classic: maximum coins collected on a walk (Example 5); reachability counts; "longest path in vertices where cycles may be traversed".

If instead the question counts *paths* and a cycle is reachable on some $s \to t$ route, the answer is infinite — detect that first (CF 1547G).

### 1.4 Functional graphs — cycles with trees hanging on them

When every vertex has exactly one outgoing edge $v \to f(v)$, each weakly connected component is one directed cycle with in-trees attached. Walking from any vertex eventually enters the cycle and loops. DPs on such graphs have two parts:

1. **Cycle vertices** get their value collectively (e.g. "number of distinct vertices visited from $v$" is the cycle length for every vertex on it).
2. **Tree vertices** get it from their successor: $\text{ans}(v) = \text{ans}(f(v)) + 1$ — a DP in the order "closest to the cycle first".

Find cycles iteratively: peel vertices of in-degree 0 with Kahn's algorithm — the peeled vertices are exactly the tree vertices (in an order where $v$ is peeled before $f(v)$, so process them in **reverse** peel order); what remains is the union of cycles. No recursion needed ([functional graphs](../09-Graphs/10-functional-graphs-and-special-graphs.md)). For "$k$-th successor" queries use binary lifting instead.

### 1.5 Layered graphs — add the step count to the state

"Cheapest route with at most $k$ edges" (LC 787) is not a plain shortest path: the state needs the number of edges used. The layered graph with vertices $(v, j)$, $j \le k$, and edges $(u, j) \to (v, j+1)$ is a DAG (layer index increases), so $k$ rounds of Bellman–Ford relaxations — each reading only the previous round — solve it in $O(km)$. Same idea for "exactly $k$ steps" counts (matrix power when $k$ is huge, [matrix exponentiation](../07-DP-Optimizations/08-matrix-exponentiation-for-dp.md)).

### 1.6 States with resources — Dijkstra on the product graph

When the state is (vertex, resource) — a coupon used or not (CSES 1195 *Flight Discount*), the bike currently held (CF 1915G *Bicycles*), fuel left, parity — transitions may go back and forth between vertices, so the state graph has cycles and there is no topological order. But if all costs are **non-negative**, Dijkstra on the product graph $(v, r)$ works: it *discovers* the topological order of the shortest-path DAG as it goes. That is "DP when you don't know the order in advance". Size: $n \cdot |R|$ states, $m\cdot|R|$ edges.

Design the resource dimension exactly as in any DP: what must the future know? For Bicycles: only which bike you hold (slowness), not where you have been — and always switching to a strictly better bike is optimal, which keeps the transitions simple.

### 1.7 What is *not* a DP

Longest **simple** path in a general (cyclic) graph is NP-hard: the state would need the visited set. With $n \le 20$ it is bitmask DP ([bitmask DP](06-bitmask-dp.md)); otherwise look for structure (DAG, tree, small treewidth) — or the problem intends walks, not simple paths.

---

## 2. Formulas, definitions and identities

| Task | Method | Time |
|---|---|---|
| longest / shortest path in a DAG (any weights) | DP in topological order | $O(n+m)$ |
| number of paths $s\to t$ in a DAG | $\text{ways}(v) = \sum \text{ways}(u)$ | $O(n+m)$ |
| number of shortest paths (positive weights) | Dijkstra + DP on tight edges in pop order | $O(m\log n)$ |
| DP on a graph with cycles | SCC condensation + DAG DP | $O(n+m)$ |
| functional graph | peel in-degree-0 vertices; cycles separately | $O(n)$ |
| at most $k$ edges | layered Bellman–Ford, $k$ rounds | $O(km)$ |
| state with resources, non-negative costs | Dijkstra on $(v, r)$ | $O(m|R|\log(n|R|))$ |

**Tight-edge criterion:** $(u\to v,w)$ lies on a shortest $s\to t$ path iff $d_s(u)+w+d_t(v) = d_s(t)$ (with $d_t$ from Dijkstra on the reversed graph).

**Edge on all shortest paths:** tight and $\text{cnt}_s(u)\cdot\text{cnt}_t(v) = \text{cnt}_s(t)$ (counts mod a random large prime — two primes to be safe).

**Kosaraju order:** processing vertices of $G^T$ in decreasing finish time of a DFS on $G$ yields the SCCs of $G$ in a topological order of the condensation (sources first).

**Functional graph:** $n$ vertices, $n$ edges; each component has exactly one cycle; the tail length plus cycle length of a vertex is at most $n$.

---

## 3. Implementation (C++ and Java)

### 3.1 Topological order (Kahn) with longest path and path counting

```cpp
// Vertices 0..n-1, edges (u, v). Returns the topological order (shorter than n iff a cycle exists).
vector<int> topoOrder(int n, const vector<pair<int, int>>& edges) {
    vector<vector<int>> adj(n);
    vector<int> indeg(n, 0), order;
    for (auto [u, v] : edges) { adj[u].push_back(v); indeg[v]++; }
    for (int v = 0; v < n; v++) if (indeg[v] == 0) order.push_back(v);
    for (size_t i = 0; i < order.size(); i++)
        for (int v : adj[order[i]]) if (--indeg[v] == 0) order.push_back(v);
    return order;
}

// Number of paths from s to every vertex (mod p) and the longest path (in edges) ending at every vertex.
void dagDp(int n, const vector<pair<int, int>>& edges, int s, vector<long long>& ways, vector<int>& longest) {
    const long long MOD = 1'000'000'007;
    vector<vector<int>> adj(n);
    for (auto [u, v] : edges) adj[u].push_back(v);
    vector<int> order = topoOrder(n, edges);
    ways.assign(n, 0);
    longest.assign(n, 0);
    ways[s] = 1;
    for (int u : order)
        for (int v : adj[u]) {                         // push: u is final when processed
            ways[v] = (ways[v] + ways[u]) % MOD;
            longest[v] = max(longest[v], longest[u] + 1);
        }
}
```

```java
static int[] topoOrder(int n, int[][] edges) {
    int[] indeg = new int[n], cnt = new int[n + 1];
    for (int[] e : edges) { indeg[e[1]]++; cnt[e[0] + 1]++; }
    for (int v = 0; v < n; v++) cnt[v + 1] += cnt[v];
    int[] adj = new int[edges.length], pos = cnt.clone();
    for (int[] e : edges) adj[pos[e[0]]++] = e[1];
    int[] order = new int[n];
    int tail = 0;
    for (int v = 0; v < n; v++) if (indeg[v] == 0) order[tail++] = v;
    for (int i = 0; i < tail; i++) {
        int u = order[i];
        for (int k = cnt[u]; k < cnt[u + 1]; k++) if (--indeg[adj[k]] == 0) order[tail++] = adj[k];
    }
    return Arrays.copyOf(order, tail);
}

static void dagDp(int n, int[][] edges, int s, long[] ways, int[] longest) {
    final long MOD = 1_000_000_007L;
    List<List<Integer>> adj = new ArrayList<>();
    for (int v = 0; v < n; v++) adj.add(new ArrayList<>());
    for (int[] e : edges) adj.get(e[0]).add(e[1]);
    Arrays.fill(ways, 0);
    Arrays.fill(longest, 0);
    ways[s] = 1;
    for (int u : topoOrder(n, edges))
        for (int v : adj.get(u)) {
            ways[v] = (ways[v] + ways[u]) % MOD;
            longest[v] = Math.max(longest[v], longest[u] + 1);
        }
}
```

---

## 4. Recognising the pattern

| Signal | Technique |
|---|---|
| "directed acyclic", "tasks with prerequisites", edges only from smaller to larger index | topological DP |
| "number of shortest routes", "minimum flights among cheapest routes" | Dijkstra + DP on tight edges |
| directed graph with cycles, "collect as much as possible", "can revisit" | SCC condensation + DAG DP |
| each vertex has exactly one successor ("teleporter", "next pointer", permutation) | functional graph: trees + cycles |
| "at most $k$ stops / edges / transfers" | layered graph, $k$ Bellman–Ford rounds |
| "you may use one coupon", "change vehicle", "carry at most $c$" | Dijkstra on (vertex, resource) |
| grid with monotone moves | the DAG is implicit — [grid DP](04-grid-and-path-counting-dp.md) |
| "longest simple path" in a cyclic graph with $n > 20$ | probably not intended as stated — look for a DAG or tree |
| game on a graph, win/lose positions | retrograde analysis from terminal states ([game DP](../13-Game-Theory/04-minimax-and-game-dp.md)) |

---

## 5. Worked examples (graded)

### Example 1 — Longest Path  ·  ★ ≈1300 (est.)

- **Source:** [AtCoder DP G · Longest Path](https://atcoder.jp/contests/dp/tasks/dp_g)
- **Difficulty:** ≈1300 (est.)
- **Problem:** A DAG with $n, m \le 10^5$. Length (in edges) of the longest directed path.
- **Thinking from first principles:** The longest path ending at $v$ comes through some predecessor: $\text{len}(v) = 1+\max_{u\to v}\text{len}(u)$. Topological order guarantees predecessors are final. A memoised DFS works too, but its depth can reach $10^5$ — Kahn is iterative.

<details><summary>Solution</summary>

Kahn's order, push relaxation, answer $\max_v \text{len}(v)$. $O(n+m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<vector<int>> adj(n);
    vector<int> indeg(n, 0);
    for (int i = 0; i < m; i++) {
        int x, y;
        cin >> x >> y;
        adj[x - 1].push_back(y - 1);
        indeg[y - 1]++;
    }
    vector<int> order, len(n, 0);
    for (int v = 0; v < n; v++) if (!indeg[v]) order.push_back(v);
    for (size_t i = 0; i < order.size(); i++) {
        int u = order[i];
        for (int v : adj[u]) {
            len[v] = max(len[v], len[u] + 1);
            if (--indeg[v] == 0) order.push_back(v);
        }
    }
    cout << *max_element(len.begin(), len.end()) << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static int ni() throws IOException {
        int c = IN.read();
        while (c < '0' || c > '9') c = IN.read();
        int r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return r;
    }

    public static void main(String[] args) throws IOException {
        int n = ni(), m = ni();
        int[] ex = new int[m], ey = new int[m], start = new int[n + 1], indeg = new int[n];
        for (int i = 0; i < m; i++) { ex[i] = ni() - 1; ey[i] = ni() - 1; start[ex[i] + 1]++; indeg[ey[i]]++; }
        for (int v = 0; v < n; v++) start[v + 1] += start[v];
        int[] adj = new int[m], pos = start.clone();
        for (int i = 0; i < m; i++) adj[pos[ex[i]]++] = ey[i];
        int[] order = new int[n], len = new int[n];
        int tail = 0;
        for (int v = 0; v < n; v++) if (indeg[v] == 0) order[tail++] = v;
        int best = 0;
        for (int i = 0; i < tail; i++) {
            int u = order[i];
            best = Math.max(best, len[u]);
            for (int k = start[u]; k < start[u + 1]; k++) {
                int v = adj[k];
                len[v] = Math.max(len[v], len[u] + 1);
                if (--indeg[v] == 0) order[tail++] = v;
            }
        }
        System.out.println(best);
    }
}
```

</details>

<!-- test
in:
5 6
1 2
2 3
1 3
3 4
2 5
5 4
out:
3
-->
<!-- test
in:
2 1
2 1
out:
1
-->

### Example 2 — Planets Cycles (functional graph)  ·  ★ ≈1700 (est.)

- **Source:** [CSES 1751 · Planets Cycles](https://cses.fi/problemset/task/1751)
- **Difficulty:** ≈1700 (est.)
- **Problem:** $n \le 2\cdot10^5$ planets, each with one teleporter to planet $t_i$. For every starting planet, how many teleports until a planet is visited for the second time (equivalently: how many distinct planets are visited)?
- **Thinking from first principles:** From $v$ the walk is a tail followed by a cycle; the answer is (tail length) + (cycle length). For a cycle vertex the tail is empty: answer = cycle length. For a tree vertex $v$, the walk from $v$ is $v$ followed by the walk from $t_v$ — so $\text{ans}(v) = \text{ans}(t_v)+1$, a DP in which $t_v$ must be solved first. Kahn on in-degrees peels tree vertices leaves-first, i.e. **$v$ before $t_v$** — so process the peeled list in reverse. The survivors are cycle vertices; walk each cycle once to measure it.

<details><summary>Solution</summary>

$O(n)$, no recursion.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<int> t(n), indeg(n, 0);
    for (auto& x : t) { cin >> x; x--; indeg[x]++; }
    vector<int> peel;                                 // tree vertices, each before its successor
    for (int v = 0; v < n; v++) if (!indeg[v]) peel.push_back(v);
    for (size_t i = 0; i < peel.size(); i++)
        if (--indeg[t[peel[i]]] == 0) peel.push_back(t[peel[i]]);
    vector<int> ans(n, 0);
    for (int v = 0; v < n; v++) {
        if (indeg[v] == 0 || ans[v]) continue;        // not on a cycle, or cycle already measured
        int len = 0, u = v;
        do { u = t[u]; len++; } while (u != v);
        do { ans[u] = len; u = t[u]; } while (u != v);
    }
    for (int i = (int)peel.size() - 1; i >= 0; i--) ans[peel[i]] = ans[t[peel[i]]] + 1;
    for (int v = 0; v < n; v++) cout << ans[v] << " \n"[v + 1 == n];
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static int ni() throws IOException {
        int c = IN.read();
        while (c < '0' || c > '9') c = IN.read();
        int r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return r;
    }

    public static void main(String[] args) throws IOException {
        int n = ni();
        int[] t = new int[n], indeg = new int[n];
        for (int i = 0; i < n; i++) { t[i] = ni() - 1; indeg[t[i]]++; }
        int[] peel = new int[n];
        int tail = 0;
        for (int v = 0; v < n; v++) if (indeg[v] == 0) peel[tail++] = v;
        for (int i = 0; i < tail; i++) if (--indeg[t[peel[i]]] == 0) peel[tail++] = t[peel[i]];
        int[] ans = new int[n];
        for (int v = 0; v < n; v++) {
            if (indeg[v] == 0 || ans[v] != 0) continue;
            int len = 0, u = v;
            do { u = t[u]; len++; } while (u != v);
            do { ans[u] = len; u = t[u]; } while (u != v);
        }
        for (int i = tail - 1; i >= 0; i--) ans[peel[i]] = ans[t[peel[i]]] + 1;
        StringBuilder sb = new StringBuilder();
        for (int v = 0; v < n; v++) sb.append(ans[v]).append(v + 1 == n ? '\n' : ' ');
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
5
2 3 1 1 4
out:
3 3 3 4 5
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
4
2 3 4 2
out:
4 3 3 3
-->

### Example 3 — Bicycles (Dijkstra on vertex × resource)  ·  ★ 1800

- **Source:** [CF 1915G · Bicycles](https://codeforces.com/problemset/problem/1915/G) — 1800
- **Difficulty:** 1800
- **Problem:** $t$ test cases; $n, m \le 1000$ in total. An undirected connected graph with road lengths $w \le 1000$; city $i$ sells a bike with slowness $s_i \le 1000$. Riding a road of length $w$ on a bike of slowness $s$ takes $w\cdot s$. You start in city 1 (taking its bike) and may switch bikes in any city you visit. Minimum time to reach city $n$.
- **Thinking from first principles:** The plain shortest path is wrong — sometimes a detour to a fast bike pays off. What does the future need? Where you are and **which bike you hold** (its slowness); the route so far is irrelevant. So the state is $(v, k)$, $k$ = the city whose bike you ride. Edges go back and forth, so there is no topological order — but costs are non-negative, so Dijkstra on the $n^2 = 10^6$ product states finds it. On arriving at a city, switching to its bike if it is strictly faster is always optimal (a faster bike makes every future road cheaper), so each edge has one successor state.

<details><summary>Solution</summary>

$\text{dist}(1, 1) = 0$; from $(v, k)$ along $(v,u,w)$: cost $w\cdot s_k$, new state $(u, k')$ with $k' = u$ if $s_u < s_k$ else $k$. Answer $\min_k \text{dist}(n, k)$. $O(nm\log(n^2))$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int T;
    cin >> T;
    while (T--) {
        int n, m;
        cin >> n >> m;
        vector<vector<pair<int, int>>> adj(n);
        for (int i = 0; i < m; i++) {
            int u, v, w;
            cin >> u >> v >> w;
            u--, v--;
            adj[u].push_back({v, w});
            adj[v].push_back({u, w});
        }
        vector<long long> s(n);
        for (auto& x : s) cin >> x;
        const long long INF = LLONG_MAX / 4;
        vector<long long> dist((size_t)n * n, INF);  // dist[v * n + k]: at v holding bike of city k
        priority_queue<pair<long long, int>, vector<pair<long long, int>>, greater<>> pq;
        dist[0] = 0;
        pq.push({0, 0});
        while (!pq.empty()) {
            auto [d, id] = pq.top();
            pq.pop();
            if (d != dist[id]) continue;
            int v = id / n, k = id % n;
            for (auto [u, w] : adj[v]) {
                int nk = s[u] < s[k] ? u : k;         // switch to a strictly faster bike
                long long nd = d + w * s[k];
                int nid = u * n + nk;
                if (nd < dist[nid]) { dist[nid] = nd; pq.push({nd, nid}); }
            }
        }
        long long ans = INF;
        for (int k = 0; k < n; k++) ans = min(ans, dist[(size_t)(n - 1) * n + k]);
        cout << ans << "\n";
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static int ni() throws IOException {
        int c = IN.read();
        while (c < '0' || c > '9') c = IN.read();
        int r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return r;
    }

    public static void main(String[] args) throws IOException {
        int T = ni();
        StringBuilder sb = new StringBuilder();
        while (T-- > 0) {
            int n = ni(), m = ni();
            int[] eu = new int[m], ev = new int[m], ew = new int[m], start = new int[n + 1];
            for (int i = 0; i < m; i++) {
                eu[i] = ni() - 1; ev[i] = ni() - 1; ew[i] = ni();
                start[eu[i] + 1]++; start[ev[i] + 1]++;
            }
            for (int v = 0; v < n; v++) start[v + 1] += start[v];
            int[] to = new int[2 * m], wt = new int[2 * m], pos = start.clone();
            for (int i = 0; i < m; i++) {
                to[pos[eu[i]]] = ev[i]; wt[pos[eu[i]]++] = ew[i];
                to[pos[ev[i]]] = eu[i]; wt[pos[ev[i]]++] = ew[i];
            }
            long[] s = new long[n];
            for (int i = 0; i < n; i++) s[i] = ni();
            final long INF = Long.MAX_VALUE / 4;
            long[] dist = new long[n * n];
            Arrays.fill(dist, INF);
            dist[0] = 0;
            PriorityQueue<long[]> pq = new PriorityQueue<>((x, y) -> Long.compare(x[0], y[0]));
            pq.add(new long[]{0, 0});
            while (!pq.isEmpty()) {
                long[] top = pq.poll();
                int id = (int) top[1];
                if (top[0] != dist[id]) continue;
                int v = id / n, k = id % n;
                for (int e = start[v]; e < start[v + 1]; e++) {
                    int u = to[e];
                    int nk = s[u] < s[k] ? u : k;
                    long nd = top[0] + wt[e] * s[k];
                    int nid = u * n + nk;
                    if (nd < dist[nid]) { dist[nid] = nd; pq.add(new long[]{nd, nid}); }
                }
            }
            long ans = INF;
            for (int k = 0; k < n; k++) ans = Math.min(ans, dist[(n - 1) * n + k]);
            sb.append(ans).append('\n');
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
2
3 3
1 2 5
2 3 5
1 3 100
10 1 7
4 4
1 2 3
2 3 4
3 4 5
1 4 50
5 2 9 1
out:
55
33
-->
<!-- test
in:
2
2 1
1 2 7
3 1
3 2
1 2 1
1 3 10
10 1 5
out:
21
21
-->

### Example 4 — Investigation (DP on the shortest-path DAG)  ·  ★ ≈1900 (est.)

- **Source:** [CSES 1202 · Investigation](https://cses.fi/problemset/task/1202)
- **Difficulty:** ≈1900 (est.)
- **Problem:** A directed graph with $n \le 10^5$ cities and $m \le 2\cdot10^5$ flights with prices $\ge 1$. Over all minimum-price routes from city 1 to city $n$, print: the minimum price, the number of such routes mod $10^9+7$, the minimum and the maximum number of flights.
- **Thinking from first principles:** Minimum-price routes use only tight edges, which form a DAG because prices are positive. Dijkstra pops vertices in non-decreasing distance — a topological order of that DAG. So three DAG DPs (count, min length, max length) piggyback on Dijkstra: when $u$ is popped, its values are final and can be pushed along its tight edges. Doing it during relaxation needs care (reset on strict improvement); doing it as a second pass over the pop order is simpler.

<details><summary>Solution</summary>

Dijkstra records the pop order; second pass over that order pushes along tight edges. $O(m\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    const long long MOD = 1'000'000'007;
    int n, m;
    cin >> n >> m;
    vector<vector<pair<int, long long>>> adj(n);
    for (int i = 0; i < m; i++) {
        int a, b;
        long long c;
        cin >> a >> b >> c;
        adj[a - 1].push_back({b - 1, c});
    }
    const long long INF = LLONG_MAX / 4;
    vector<long long> dist(n, INF);
    vector<int> order;
    vector<char> done(n, 0);
    priority_queue<pair<long long, int>, vector<pair<long long, int>>, greater<>> pq;
    dist[0] = 0;
    pq.push({0, 0});
    while (!pq.empty()) {
        auto [d, u] = pq.top();
        pq.pop();
        if (done[u]) continue;
        done[u] = 1;
        order.push_back(u);                            // pop order = topological order of tight edges
        for (auto [v, w] : adj[u])
            if (d + w < dist[v]) { dist[v] = d + w; pq.push({dist[v], v}); }
    }
    vector<long long> cnt(n, 0);
    vector<int> mn(n, INT_MAX), mx(n, INT_MIN);
    cnt[0] = 1; mn[0] = mx[0] = 0;
    for (int u : order)
        for (auto [v, w] : adj[u])
            if (dist[u] + w == dist[v]) {              // tight edge
                cnt[v] = (cnt[v] + cnt[u]) % MOD;
                mn[v] = min(mn[v], mn[u] + 1);
                mx[v] = max(mx[v], mx[u] + 1);
            }
    cout << dist[n - 1] << " " << cnt[n - 1] << " " << mn[n - 1] << " " << mx[n - 1] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static int ni() throws IOException {
        int c = IN.read();
        while (c < '0' || c > '9') c = IN.read();
        int r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return r;
    }

    public static void main(String[] args) throws IOException {
        final long MOD = 1_000_000_007L;
        int n = ni(), m = ni();
        int[] ea = new int[m], eb = new int[m], start = new int[n + 1];
        long[] ec = new long[m];
        for (int i = 0; i < m; i++) { ea[i] = ni() - 1; eb[i] = ni() - 1; ec[i] = ni(); start[ea[i] + 1]++; }
        for (int v = 0; v < n; v++) start[v + 1] += start[v];
        int[] to = new int[m], pos = start.clone();
        long[] wt = new long[m];
        for (int i = 0; i < m; i++) { to[pos[ea[i]]] = eb[i]; wt[pos[ea[i]]++] = ec[i]; }
        final long INF = Long.MAX_VALUE / 4;
        long[] dist = new long[n];
        Arrays.fill(dist, INF);
        boolean[] done = new boolean[n];
        int[] order = new int[n];
        int cntOrder = 0;
        PriorityQueue<long[]> pq = new PriorityQueue<>((x, y) -> Long.compare(x[0], y[0]));
        dist[0] = 0;
        pq.add(new long[]{0, 0});
        while (!pq.isEmpty()) {
            long[] top = pq.poll();
            int u = (int) top[1];
            if (done[u]) continue;
            done[u] = true;
            order[cntOrder++] = u;
            for (int e = start[u]; e < start[u + 1]; e++) {
                int v = to[e];
                if (top[0] + wt[e] < dist[v]) { dist[v] = top[0] + wt[e]; pq.add(new long[]{dist[v], v}); }
            }
        }
        long[] cnt = new long[n];
        int[] mn = new int[n], mx = new int[n];
        Arrays.fill(mn, Integer.MAX_VALUE);
        Arrays.fill(mx, Integer.MIN_VALUE);
        cnt[0] = 1; mn[0] = 0; mx[0] = 0;
        for (int i = 0; i < cntOrder; i++) {
            int u = order[i];
            for (int e = start[u]; e < start[u + 1]; e++) {
                int v = to[e];
                if (dist[u] + wt[e] == dist[v]) {
                    cnt[v] = (cnt[v] + cnt[u]) % MOD;
                    mn[v] = Math.min(mn[v], mn[u] + 1);
                    mx[v] = Math.max(mx[v], mx[u] + 1);
                }
            }
        }
        System.out.println(dist[n - 1] + " " + cnt[n - 1] + " " + mn[n - 1] + " " + mx[n - 1]);
    }
}
```

</details>

<!-- test
in:
4 5
1 2 1
2 4 2
1 3 2
3 4 1
1 4 3
out:
3 3 1 2
-->
<!-- test
in:
2 1
1 2 7
out:
7 1 1 1
-->
<!-- test
in:
5 6
1 2 1
1 3 1
2 4 1
3 4 1
4 5 1
1 5 3
out:
3 3 1 3
-->

### Example 5 — Coin Collector (SCC condensation + DAG DP)  ·  ★ ≈1900 (est.)

- **Source:** [CSES 1686 · Coin Collector](https://cses.fi/problemset/task/1686)
- **Difficulty:** ≈1900 (est.)
- **Problem:** A directed graph with $n \le 10^5$ rooms, $m \le 2\cdot10^5$ tunnels; room $i$ holds $k_i \le 10^9$ coins. Start anywhere, walk along tunnels (rooms may be revisited), collect each room's coins once. Maximise the total.
- **Thinking from first principles:** Cycles make a direct DP impossible (no order). But inside a strongly connected component every room reaches every other, so a walk that enters an SCC can collect all of it and leave by any exit. Contract each SCC into one vertex with the sum of its coins; the condensation is a DAG and the answer is its maximum-weight path. Kosaraju's second pass produces SCCs in topological order, so the DAG DP is one more loop. Totals reach $10^{14}$: 64-bit. Use iterative DFS — chains of $10^5$ rooms are allowed.

<details><summary>Solution</summary>

Iterative Kosaraju (finish order on $G$, components on $G^T$), then $\text{best}(C) = \text{sum}(C) + \max_{C\to D}\text{best}(D)$ over components in reverse topological order. $O(n+m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<long long> k(n);
    for (auto& x : k) cin >> x;
    vector<vector<int>> g(n), gr(n);
    for (int i = 0; i < m; i++) {
        int a, b;
        cin >> a >> b;
        g[a - 1].push_back(b - 1);
        gr[b - 1].push_back(a - 1);
    }
    vector<int> fin, it(n, 0);                        // iterative DFS: it[v] = next edge to try
    vector<char> vis(n, 0);
    for (int s = 0; s < n; s++) {
        if (vis[s]) continue;
        vector<int> st{s};
        vis[s] = 1;
        while (!st.empty()) {
            int v = st.back();
            if (it[v] < (int)g[v].size()) {
                int u = g[v][it[v]++];
                if (!vis[u]) { vis[u] = 1; st.push_back(u); }
            } else { fin.push_back(v); st.pop_back(); }
        }
    }
    vector<int> comp(n, -1);
    int C = 0;
    for (int i = n - 1; i >= 0; i--) {                // decreasing finish time on the reverse graph
        int s = fin[i];
        if (comp[s] != -1) continue;
        vector<int> st{s};
        comp[s] = C;
        while (!st.empty()) {
            int v = st.back();
            st.pop_back();
            for (int u : gr[v]) if (comp[u] == -1) { comp[u] = C; st.push_back(u); }
        }
        C++;
    }
    vector<long long> sum(C, 0), best(C, 0);
    for (int v = 0; v < n; v++) sum[comp[v]] += k[v];
    vector<vector<int>> dag(C);
    for (int v = 0; v < n; v++)
        for (int u : g[v]) if (comp[u] != comp[v]) dag[comp[v]].push_back(comp[u]);
    long long ans = 0;
    for (int c = C - 1; c >= 0; c--) {                // components come out in topological order
        long long out = 0;
        for (int d : dag[c]) out = max(out, best[d]);
        best[c] = sum[c] + out;
        ans = max(ans, best[c]);
    }
    cout << ans << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static int ni() throws IOException {
        int c = IN.read();
        while (c < '0' || c > '9') c = IN.read();
        int r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return r;
    }

    public static void main(String[] args) throws IOException {
        int n = ni(), m = ni();
        long[] k = new long[n];
        for (int i = 0; i < n; i++) k[i] = ni();
        int[] ea = new int[m], eb = new int[m], gs = new int[n + 1], rs = new int[n + 1];
        for (int i = 0; i < m; i++) { ea[i] = ni() - 1; eb[i] = ni() - 1; gs[ea[i] + 1]++; rs[eb[i] + 1]++; }
        for (int v = 0; v < n; v++) { gs[v + 1] += gs[v]; rs[v + 1] += rs[v]; }
        int[] g = new int[m], gr = new int[m], gp = gs.clone(), rp = rs.clone();
        for (int i = 0; i < m; i++) { g[gp[ea[i]]++] = eb[i]; gr[rp[eb[i]]++] = ea[i]; }
        int[] fin = new int[n], it = gs.clone(), st = new int[n];
        int fc = 0;
        boolean[] vis = new boolean[n];
        for (int s = 0; s < n; s++) {
            if (vis[s]) continue;
            int top = 0;
            st[top++] = s;
            vis[s] = true;
            while (top > 0) {
                int v = st[top - 1];
                if (it[v] < gs[v + 1]) {
                    int u = g[it[v]++];
                    if (!vis[u]) { vis[u] = true; st[top++] = u; }
                } else { fin[fc++] = v; top--; }
            }
        }
        int[] comp = new int[n];
        Arrays.fill(comp, -1);
        int C = 0;
        for (int i = n - 1; i >= 0; i--) {
            int s = fin[i];
            if (comp[s] != -1) continue;
            int top = 0;
            st[top++] = s;
            comp[s] = C;
            while (top > 0) {
                int v = st[--top];
                for (int e = rs[v]; e < rs[v + 1]; e++) {
                    int u = gr[e];
                    if (comp[u] == -1) { comp[u] = C; st[top++] = u; }
                }
            }
            C++;
        }
        long[] sum = new long[C], best = new long[C];
        for (int v = 0; v < n; v++) sum[comp[v]] += k[v];
        int[] ds = new int[C + 1];
        for (int i = 0; i < m; i++) if (comp[ea[i]] != comp[eb[i]]) ds[comp[ea[i]] + 1]++;
        for (int c = 0; c < C; c++) ds[c + 1] += ds[c];
        int[] dag = new int[ds[C]], dp = ds.clone();
        for (int i = 0; i < m; i++) if (comp[ea[i]] != comp[eb[i]]) dag[dp[comp[ea[i]]]++] = comp[eb[i]];
        long ans = 0;
        for (int c = C - 1; c >= 0; c--) {
            long out = 0;
            for (int e = ds[c]; e < ds[c + 1]; e++) out = Math.max(out, best[dag[e]]);
            best[c] = sum[c] + out;
            ans = Math.max(ans, best[c]);
        }
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
5 5
3 1 4 1 5
1 2
2 1
2 3
4 3
3 5
out:
13
-->
<!-- test
in:
1 0
7
out:
7
-->
<!-- test
in:
3 3
1000000000 1000000000 1
1 2
2 3
3 1
out:
2000000001
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Unreachable vertices in DAG DPs:** a longest-path DP from a fixed source must start from $-\infty$ everywhere except the source; "longest path anywhere" starts from 0 everywhere (Example 1).
2. **Kahn detects cycles** — if the order has fewer than $n$ vertices, the input is not a DAG (or your edges are reversed).
3. **Counting paths mod $p$** cannot tell "zero paths" from "a multiple of $p$ paths"; track reachability separately when it matters.
4. **Shortest-path DAG needs positive weights;** with zero-weight edges, pop order among equal distances is not topological — condense zero-weight cycles or process equal-distance groups with a topological sort.
5. **Dijkstra stale entries:** skip a popped pair if its distance differs from `dist` (or keep a `done` flag). Counting during relaxation needs "reset on strict improvement, add on equality, only from finalised vertices".
6. **Product-graph size:** $n\cdot|R|$ states can be large — Example 3 has $10^6$ states and fits only because $\sum n \le 1000$. Use flattened arrays.
7. **Recursion:** DFS-based topological sorts and Tarjan recurse to depth $n$. Iterative Kosaraju (Example 5) or Kahn avoid it in both languages.
8. **Functional graph traversal:** process peeled vertices in *reverse* peel order (each after its successor) — forward order reads unfinished successors.
9. **Self-loops and multi-edges:** an SCC of one vertex with a self-loop is still one component; multi-edges duplicate condensation edges harmlessly for max-DPs but double counts in counting DPs (deduplicate if counting distinct edge sets is not intended).
10. **Java `PriorityQueue<long[]>`** allocates per push; for $10^6$ pushes it is fine, but encoding `(dist, id)` into one `long` (`dist << 20 | id`) is faster when distances are small enough.
11. **Edge direction in Kosaraju:** first pass on $G$, second on $G^T$ in decreasing finish order — the components then come out in topological order of $G$'s condensation.
12. **Answer "anywhere" vs from a source:** Coin Collector starts anywhere (max over all components); Investigation is from city 1 only.

---

## 7. Going further (toward 2400–2600+)

- **Counting shortest paths with hashing to test "edge on every shortest path"** (CF 567E): counts mod two primes, $\text{cnt}_s(u)\,\text{cnt}_t(v) \equiv \text{cnt}_s(t)$.
- **Time-expanded graphs** (CF 1137C *Museums Tour*): state (city, day mod $d$), then SCC condensation of the product graph and a DAG DP that counts each museum once per component.
- **DAG DP + data structures** (CF 1407D *Discrete Centrifugal Jumps*): transitions to the next greater/smaller elements found by monotonic stacks; each index has $O(1)$ amortised successors.
- **Two-resource Dijkstra** (CF 1473E *Minimum Path*): "sum − max + min" over a path becomes a state (v, removed-max-used, doubled-min-used) — the minimisation chooses the best edges itself.
- **Reachability counting** in DAGs (for each vertex, how many vertices reachable) — bitsets in $O(nm/64)$ ([bitset optimisation](../16-IGM-Frontier/05-bitset-optimization.md)); no linear algorithm is known.
- **Expected values on graphs with cycles** need equations, not a DP order ([expected-value DP](10-probability-and-expected-value-dp.md), [Gaussian elimination](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md)).

---

## 8. Practice ladder

**≤ 1600**
- [ ] [AtCoder DP G · Longest Path](https://atcoder.jp/contests/dp/tasks/dp_g)
- [ ] [CSES 1681 · Game Routes](https://cses.fi/problemset/task/1681) — count paths in a DAG
- [ ] [CSES 1680 · Longest Flight Route](https://cses.fi/problemset/task/1680) — longest path from a source, with reconstruction
- [ ] [CF 1472C · Long Jumps](https://codeforces.com/problemset/problem/1472/C) — 1100 — implicit DAG
- [ ] [CF 1360E · Polygon](https://codeforces.com/problemset/problem/1360/E) — 1300

**1600–2000**
- [ ] [CSES 1751 · Planets Cycles](https://cses.fi/problemset/task/1751)
- [ ] [CSES 1195 · Flight Discount](https://cses.fi/problemset/task/1195) — Dijkstra on (city, coupon used)
- [ ] [CF 919D · Substring](https://codeforces.com/problemset/problem/919/D) — 1700
- [ ] [CF 1320B · Navigation System](https://codeforces.com/problemset/problem/1320/B) — 1700
- [ ] [CF 1915G · Bicycles](https://codeforces.com/problemset/problem/1915/G) — 1800
- [ ] [CSES 1202 · Investigation](https://cses.fi/problemset/task/1202)
- [ ] [CSES 1686 · Coin Collector](https://cses.fi/problemset/task/1686)
- [ ] [CF 463D · Gargari and Permutations](https://codeforces.com/problemset/problem/463/D) — 1900
- [ ] [CF 505C · Mr. Kitayuta, the Treasure Hunter](https://codeforces.com/problemset/problem/505/C) — 1900

**2000–2400**
- [ ] [CF 1472G · Moving to the Capital](https://codeforces.com/problemset/problem/1472/G) — 2100
- [ ] [CF 507E · Breaking Good](https://codeforces.com/problemset/problem/507/E) — 2100
- [ ] [CF 1547G · How Many Paths?](https://codeforces.com/problemset/problem/1547/G) — 2100
- [ ] [CF 1407D · Discrete Centrifugal Jumps](https://codeforces.com/problemset/problem/1407/D) — 2200
- [ ] [CF 567E · President and Roads](https://codeforces.com/problemset/problem/567/E) — 2200
- [ ] [CF 1473E · Minimum Path](https://codeforces.com/problemset/problem/1473/E) — 2400

**2400+**
- [ ] [CF 1137C · Museums Tour](https://codeforces.com/problemset/problem/1137/C) — 2500

---

## 9. LeetCode / FAANG cross-reference

- [LC 787 · Cheapest Flights Within K Stops](https://leetcode.com/problems/cheapest-flights-within-k-stops/) — Medium — layered Bellman–Ford with $k+1$ rounds (§1.5).
- [LC 1976 · Number of Ways to Arrive at Destination](https://leetcode.com/problems/number-of-ways-to-arrive-at-destination/) — Medium — counting shortest paths (Example 4).
- [LC 1786 · Number of Restricted Paths From First to Last Node](https://leetcode.com/problems/number-of-restricted-paths-from-first-to-last-node/) — Medium — Dijkstra from the end, then a DAG DP ordered by distance.
- [LC 2050 · Parallel Courses III](https://leetcode.com/problems/parallel-courses-iii/) — Hard — longest path in a DAG with vertex weights.
- [LC 1857 · Largest Color Value in a Directed Graph](https://leetcode.com/problems/largest-color-value-in-a-directed-graph/) — Hard — Kahn + 26 DP values per vertex, cycle detection.
- [LC 329 · Longest Increasing Path in a Matrix](https://leetcode.com/problems/longest-increasing-path-in-a-matrix/) — Hard — implicit DAG (strictly increasing moves).
- [LC 1514 · Path with Maximum Probability](https://leetcode.com/problems/path-with-maximum-probability/) — Medium — Dijkstra with a (max, ×) semiring (probabilities $\le 1$ keep it monotone).
- [LC 847 · Shortest Path Visiting All Nodes](https://leetcode.com/problems/shortest-path-visiting-all-nodes/) — Hard — BFS on (mask, vertex).

---

## 10. Self-check

1. Why does Dijkstra's pop order give a topological order of the tight edges, and why does that fail with zero-weight edges?
2. Why can an entire SCC be treated as one vertex in Coin Collector?
3. In a functional graph, why process peeled vertices in reverse order?
4. How do you handle "at most $k$ edges" shortest paths, and why can't you reuse the same array in each Bellman–Ford round?
5. What is the state in Bicycles, and why is it enough?
6. How do you test whether an edge lies on *every* shortest path?
7. Name a DAG DP where negative weights are fine and explain why.

<details><summary>Answers</summary>

1. Tight edges satisfy $d(v) = d(u) + w > d(u)$ when $w > 0$, and Dijkstra pops in non-decreasing $d$, so $u$ is popped before $v$. With $w=0$, $d(u)=d(v)$ and either may be popped first; zero-weight tight cycles are possible.
2. Every vertex of an SCC is reachable from every other, so a walk entering it can collect all its coins and leave by any outgoing edge; between components the walk follows the acyclic condensation.
3. Kahn peels $v$ before its successor $t_v$ (a leaf of the in-tree first), but $\text{ans}(v)$ needs $\text{ans}(t_v)$, so the reverse order is required.
4. Layer by the number of edges: round $j$ computes distances using at most $j$ edges from round $j-1$'s values only; updating in place could chain several edges within one round.
5. (current city, which bike you hold); the cost of the future depends only on these, and the route taken so far does not matter. Switching to a strictly faster bike is always beneficial, so the bike is the best seen so far.
6. It must be tight ($d_s(u)+w+d_t(v) = d_s(t)$) and carry all shortest paths: $\text{cnt}_s(u)\cdot\text{cnt}_t(v) = \text{cnt}_s(t)$ (compare modulo random primes).
7. Longest/shortest path in a DAG via topological order: no cycles means no negative cycle can be exploited, and each vertex is relaxed only after all predecessors are final.

</details>
