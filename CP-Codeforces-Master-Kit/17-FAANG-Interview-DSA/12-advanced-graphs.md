# Advanced Graphs: Shortest Paths, MST and Implicit Graphs

> **Band:** 🔵 1500 – 🟣 2000 · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [graphs](11-graphs.md), [heaps](09-heaps-and-top-k.md)
> **You can say you know this when:** you choose between BFS, 0-1 BFS, Dijkstra and Bellman–Ford from the edge weights and constraints, write lazy Dijkstra correctly in both languages, explain why Bellman–Ford with $k+1$ rounds solves "at most $k$ stops", and build MSTs with Prim or Kruskal.

These problems appear less often than plain BFS/DFS, but they are the ones where candidates freeze. The algorithms are short. The real work is **modelling**: what are the nodes, what are the edges, what is the weight, and what extra state (stops used, time, keys) must be part of a node.

## 1. First principles — why this works

### 1.1 Dijkstra: settle the closest unsettled node

With non-negative weights, the unsettled node $u$ with the smallest tentative distance $d(u)$ cannot be improved later: any other path to $u$ leaves the settled set through some unsettled node $x$ with $d(x) \ge d(u)$, and the remaining edges only add non-negative weight. So $u$ can be **settled**, and its outgoing edges relaxed. A min-heap finds that node in $O(\log V)$. The *lazy* version pushes a new `(dist, node)` pair on every improvement and skips stale pairs on pop (`if (d > dist[u]) continue`). This is $O((V + E) \log V)$ and simpler than decrease-key. A negative edge breaks the argument ($x$'s path could get cheaper after $u$ was settled), so Dijkstra is wrong with negative weights.

### 1.2 Bellman–Ford: paths with at most $i$ edges

Let $d_i(v)$ be the cheapest cost of a path from the source to $v$ using **at most $i$ edges**. Then $d_{i}(v) = \min\big(d_{i-1}(v),\ \min_{(u,v)} d_{i-1}(u) + w(u,v)\big)$. A shortest simple path has at most $V - 1$ edges, so $V - 1$ rounds of relaxing every edge give exact distances, in $O(VE)$, and they work with negative edges. If a $V$-th round still improves something, there is a negative cycle. "Cheapest flight with at most $k$ stops" is exactly $d_{k+1}$. You must relax from a **copy** of the previous round's distances, or one round can chain several edges and use more than $i$.

### 1.3 Minimum spanning tree: the cut property

For any partition of the nodes into two sides, the lightest edge crossing it belongs to some MST. Proof by exchange: if an MST avoided it, adding it creates a cycle that crosses the cut a second time through a heavier (or equal) edge, and swapping the two does not increase the weight. Both classical algorithms are this property applied repeatedly:

- **Kruskal:** sort edges, add each one that joins two different components (DSU). $O(E \log E)$.
- **Prim:** grow one tree, always adding the lightest edge leaving it. $O(E \log V)$ with a heap, or $O(V^2)$ with an array, which is better for complete graphs (all pairs of points).

### 1.4 Implicit graphs and state expansion

When a constraint is part of the path (stops used, keys held, time of day), make it part of the **node**: the node becomes `(city, stopsUsed)` or `(cell, keyMask)`. Then a standard algorithm runs on the expanded graph. For word problems the nodes are words and edges are one-letter changes. Generating the neighbours of a word by trying $26L$ substitutions and checking a hash set costs $O(26 L^2)$ per word, which beats comparing all pairs ($O(N^2 L)$) when $N$ is large.

## 2. Algorithm chooser and complexities

| Edge weights / question | Algorithm | Time |
|---|---|---|
| all weights equal | BFS | $O(V + E)$ |
| weights in $\{0, 1\}$ | 0-1 BFS (deque: weight 0 to the front, 1 to the back) | $O(V + E)$ |
| non-negative | Dijkstra with a binary heap | $O((V + E) \log V)$ |
| negative edges, or "at most $k$ edges" | Bellman–Ford ($k$ rounds) | $O(kE)$ |
| all pairs, $V \le 400$ | Floyd–Warshall: $d_{ij} = \min(d_{ij}, d_{ik} + d_{kj})$ for $k$ outermost | $O(V^3)$ |
| minimise the maximum edge on a path ("bottleneck") | Dijkstra with `max` instead of `+`, or MST, or binary search + BFS | $O(E \log V)$ |
| maximise a product of probabilities | Dijkstra on $-\log p$, or directly with `max` and `*` (all $p \le 1$) | $O(E \log V)$ |
| MST, sparse graph | Kruskal + DSU | $O(E \log E)$ |
| MST, complete graph on points | Prim with an array | $O(V^2)$ |
| order with constraints | topological sort ([file 11](11-graphs.md)) | $O(V + E)$ |
| use every edge exactly once | Hierholzer (Euler path) | $O(E)$ |

## 3. Reusable templates (C++ and Java)

Lazy Dijkstra, Bellman–Ford limited to $k$ edges, and Kruskal:

```cpp
vector<long long> dijkstra(const vector<vector<pair<int, int>>>& adj, int src) {   // adj[u] = {v, w}
    const long long INF = LLONG_MAX / 4;
    vector<long long> dist(adj.size(), INF);
    priority_queue<pair<long long, int>, vector<pair<long long, int>>, greater<>> pq;
    dist[src] = 0;
    pq.push({0, src});
    while (!pq.empty()) {
        auto [d, u] = pq.top(); pq.pop();
        if (d > dist[u]) continue;                       // stale entry: u was settled cheaper
        for (auto [v, w] : adj[u])
            if (d + w < dist[v]) { dist[v] = d + w; pq.push({dist[v], v}); }
    }
    return dist;
}

// Cheapest cost from src to every node using at most k edges (edges: {u, v, w}).
vector<long long> bellmanFordK(int n, const vector<array<int, 3>>& edges, int src, int k) {
    const long long INF = LLONG_MAX / 4;
    vector<long long> dist(n, INF);
    dist[src] = 0;
    for (int round = 0; round < k; ++round) {
        vector<long long> next = dist;                   // relax from the previous round only
        for (auto [u, v, w] : edges)
            if (dist[u] != INF && dist[u] + w < next[v]) next[v] = dist[u] + w;
        dist.swap(next);
    }
    return dist;
}

long long kruskal(int n, vector<array<int, 3>> edges) {  // edges: {w, u, v}; returns -1 if disconnected
    sort(edges.begin(), edges.end());
    vector<int> parent(n);
    iota(parent.begin(), parent.end(), 0);
    function<int(int)> find = [&](int x) { return parent[x] == x ? x : parent[x] = find(parent[x]); };
    long long total = 0;
    int used = 0;
    for (auto [w, u, v] : edges) {
        int a = find(u), b = find(v);
        if (a == b) continue;                            // would close a cycle
        parent[a] = b;
        total += w;
        ++used;
    }
    return used == n - 1 ? total : -1;
}
```

```java
static long[] dijkstra(List<List<int[]>> adj, int src) {
    final long INF = Long.MAX_VALUE / 4;
    long[] dist = new long[adj.size()];
    Arrays.fill(dist, INF);
    PriorityQueue<long[]> pq = new PriorityQueue<>((a, b) -> Long.compare(a[0], b[0]));
    dist[src] = 0;
    pq.add(new long[]{0, src});
    while (!pq.isEmpty()) {
        long[] top = pq.poll();
        long d = top[0];
        int u = (int) top[1];
        if (d > dist[u]) continue;
        for (int[] e : adj.get(u)) {
            int v = e[0], w = e[1];
            if (d + w < dist[v]) { dist[v] = d + w; pq.add(new long[]{dist[v], v}); }
        }
    }
    return dist;
}

static long[] bellmanFordK(int n, int[][] edges, int src, int k) {
    final long INF = Long.MAX_VALUE / 4;
    long[] dist = new long[n];
    Arrays.fill(dist, INF);
    dist[src] = 0;
    for (int round = 0; round < k; round++) {
        long[] next = dist.clone();
        for (int[] e : edges)
            if (dist[e[0]] != INF && dist[e[0]] + e[2] < next[e[1]]) next[e[1]] = dist[e[0]] + e[2];
        dist = next;
    }
    return dist;
}

static long kruskal(int n, int[][] edges) {              // edges: {w, u, v}
    int[][] es = edges.clone();
    Arrays.sort(es, (a, b) -> Integer.compare(a[0], b[0]));
    int[] parent = new int[n];
    for (int i = 0; i < n; i++) parent[i] = i;
    long total = 0;
    int used = 0;
    for (int[] e : es) {
        int a = e[1], b = e[2];
        while (parent[a] != a) a = parent[a] = parent[parent[a]];
        while (parent[b] != b) b = parent[b] = parent[parent[b]];
        if (a == b) continue;
        parent[a] = b;
        total += e[0];
        used++;
    }
    return used == n - 1 ? total : -1;
}
```

0-1 BFS (for grids where some moves are free and some cost 1):

```cpp
vector<int> zeroOneBfs(const vector<vector<pair<int, int>>>& adj, int src) {   // weights 0 or 1
    vector<int> dist(adj.size(), INT_MAX);
    deque<int> dq;
    dist[src] = 0;
    dq.push_back(src);
    while (!dq.empty()) {
        int u = dq.front(); dq.pop_front();
        for (auto [v, w] : adj[u])
            if (dist[u] + w < dist[v]) {
                dist[v] = dist[u] + w;
                if (w == 0) dq.push_front(v); else dq.push_back(v);   // keeps the deque sorted by distance
            }
    }
    return dist;
}
```

```java
static int[] zeroOneBfs(List<List<int[]>> adj, int src) {
    int[] dist = new int[adj.size()];
    Arrays.fill(dist, Integer.MAX_VALUE);
    ArrayDeque<Integer> dq = new ArrayDeque<>();
    dist[src] = 0;
    dq.add(src);
    while (!dq.isEmpty()) {
        int u = dq.pollFirst();
        for (int[] e : adj.get(u))
            if (dist[u] + e[1] < dist[e[0]]) {
                dist[e[0]] = dist[u] + e[1];
                if (e[1] == 0) dq.addFirst(e[0]); else dq.addLast(e[0]);
            }
    }
    return dist;
}
```

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| weighted edges, "minimum time / cost / effort", non-negative | Dijkstra |
| "at most $k$ stops / edges / transfers" | Bellman–Ford with $k+1$ rounds, or Dijkstra on `(node, stops)` |
| "minimise the maximum step / height difference" | bottleneck Dijkstra, or binary search on the answer + BFS |
| "connect all points / cities at minimum total cost" | MST (Prim for dense, Kruskal for sparse) |
| "edges that are in every / some MST" | Kruskal with forced inclusion / exclusion per edge |
| sorted words in an unknown alphabet | build letter edges from adjacent words, topological sort |
| "transform word A into B one letter at a time" | BFS over words; bidirectional BFS for speed |
| "route changes", "bus routes", "minimum number of lines" | BFS over routes (or over (stop, route) states) |
| "use every ticket / edge once" | Euler path (Hierholzer) |
| "bridges", "critical connections" | Tarjan low-link ([CP](../09-Graphs/06-bridges-articulation-points-and-bcc.md)) |

## 5. Worked examples

### Example 1 — Network Delay Time · Medium

- **Source:** [LC 743 · Network Delay Time](https://leetcode.com/problems/network-delay-time/) — Medium · `NC150`
- **Difficulty:** LeetCode Medium (≈ 1500 CF, est.)
- **Problem:** directed weighted edges `u v w` ($n \le 100$ nodes labelled $1..n$, $\le 6000$ edges, $0 \le w \le 100$). A signal starts at $k$. How long until every node has received it? Return $-1$ if some node is unreachable.
- **Thinking from first principles:** the time a node receives the signal is its shortest-path distance from $k$, and everyone has it at $\max_v d(v)$. Weights are non-negative, so use Dijkstra. With $n = 100$, Bellman–Ford ($O(nE) = 6 \cdot 10^5$) or Floyd–Warshall ($10^6$) also pass. Name them, then write Dijkstra because it is the one that scales.

<details><summary>Solution</summary>

Lazy Dijkstra from $k$, then the maximum distance (or $-1$ if any is infinite). $O(E \log V)$. The driver reads `n m k` and the `m` edges.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int networkDelayTime(vector<vector<int>>& times, int n, int k) {
        vector<vector<pair<int, int>>> adj(n + 1);
        for (auto& t : times) adj[t[0]].push_back({t[1], t[2]});
        vector<int> dist(n + 1, INT_MAX);
        priority_queue<pair<int, int>, vector<pair<int, int>>, greater<>> pq;   // (dist, node)
        dist[k] = 0;
        pq.push({0, k});
        while (!pq.empty()) {
            auto [d, u] = pq.top(); pq.pop();
            if (d > dist[u]) continue;                     // stale
            for (auto [v, w] : adj[u])
                if (d + w < dist[v]) { dist[v] = d + w; pq.push({dist[v], v}); }
        }
        int best = 0;
        for (int v = 1; v <= n; ++v) {
            if (dist[v] == INT_MAX) return -1;
            best = max(best, dist[v]);
        }
        return best;
    }
};

int main() {
    int n, m, k;
    cin >> n >> m >> k;
    vector<vector<int>> times(m, vector<int>(3));
    for (auto& t : times) cin >> t[0] >> t[1] >> t[2];
    cout << Solution().networkDelayTime(times, n, k) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int networkDelayTime(int[][] times, int n, int k) {
        List<List<int[]>> adj = new ArrayList<>();
        for (int i = 0; i <= n; i++) adj.add(new ArrayList<>());
        for (int[] t : times) adj.get(t[0]).add(new int[]{t[1], t[2]});
        int[] dist = new int[n + 1];
        Arrays.fill(dist, Integer.MAX_VALUE);
        PriorityQueue<int[]> pq = new PriorityQueue<>((a, b) -> Integer.compare(a[0], b[0]));
        dist[k] = 0;
        pq.add(new int[]{0, k});
        while (!pq.isEmpty()) {
            int[] top = pq.poll();
            int d = top[0], u = top[1];
            if (d > dist[u]) continue;
            for (int[] e : adj.get(u))
                if (d + e[1] < dist[e[0]]) { dist[e[0]] = d + e[1]; pq.add(new int[]{dist[e[0]], e[0]}); }
        }
        int best = 0;
        for (int v = 1; v <= n; v++) {
            if (dist[v] == Integer.MAX_VALUE) return -1;
            best = Math.max(best, dist[v]);
        }
        return best;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt(), k = in.nextInt();
        int[][] times = new int[m][3];
        for (int i = 0; i < m; i++) for (int j = 0; j < 3; j++) times[i][j] = in.nextInt();
        System.out.println(new Solution().networkDelayTime(times, n, k));
    }
}

class FastReader {
    private final DataInputStream in;
    private final byte[] buf = new byte[1 << 16];
    private int len = 0, ptr = 0;
    FastReader(InputStream is) { in = new DataInputStream(is); }
    private int read() throws IOException {
        if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
        return buf[ptr++];
    }
    String next() throws IOException {
        int c = read();
        while (c != -1 && c <= ' ') c = read();
        if (c == -1) return null;
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = read(); }
        return sb.toString();
    }
    int nextInt() throws IOException { return Integer.parseInt(next()); }
}
```

</details>

<!-- test
in:
4 3 2
2 1 1
2 3 1
3 4 1
out:
2
-->
<!-- test
in:
2 1 1
1 2 1
out:
1
-->
<!-- test
in:
2 1 2
1 2 1
out:
-1
-->
<!-- test
in:
3 3 1
1 2 10
1 3 1
3 2 2
out:
3
-->

### Example 2 — Cheapest Flights Within K Stops · Medium

- **Source:** [LC 787 · Cheapest Flights Within K Stops](https://leetcode.com/problems/cheapest-flights-within-k-stops/) — Medium · `G169` `NC150`
- **Difficulty:** LeetCode Medium (≈ 1700 CF, est.)
- **Problem:** $n \le 100$ cities, directed flights `from to price` (prices $\ge 1$). Find the cheapest price from `src` to `dst` with **at most $k$ stops** (at most $k + 1$ flights), or $-1$.
- **Thinking from first principles:** plain Dijkstra is wrong here: it settles a city at its cheapest cost, but that cheapest route may use too many stops, while a pricier route with fewer stops is the one that can still reach `dst` in time. The constraint is on the **number of edges**, which is exactly what Bellman–Ford's round index means (§1.2): after $i$ rounds, `dist` is the cheapest cost using at most $i$ flights. So run $k + 1$ rounds, each relaxing from a copy of the previous round. The alternatives are BFS by levels with pruning, or Dijkstra over states `(city, flightsUsed)`.

<details><summary>Solution</summary>

$O((k + 1) \cdot E)$ time, $O(n)$ space. The copy is essential. Without it, a single round can chain two flights, and the count of flights per round is no longer bounded. The driver reads `n m src dst k` and the flights.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int findCheapestPrice(int n, vector<vector<int>>& flights, int src, int dst, int k) {
        const int INF = INT_MAX;
        vector<int> dist(n, INF);
        dist[src] = 0;
        for (int round = 0; round <= k; ++round) {          // k stops = k + 1 flights
            vector<int> next = dist;                        // only extend last round's paths
            for (auto& f : flights) {
                int u = f[0], v = f[1], w = f[2];
                if (dist[u] != INF && dist[u] + w < next[v]) next[v] = dist[u] + w;
            }
            dist.swap(next);
        }
        return dist[dst] == INF ? -1 : dist[dst];
    }
};

int main() {
    int n, m, src, dst, k;
    cin >> n >> m >> src >> dst >> k;
    vector<vector<int>> flights(m, vector<int>(3));
    for (auto& f : flights) cin >> f[0] >> f[1] >> f[2];
    cout << Solution().findCheapestPrice(n, flights, src, dst, k) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int findCheapestPrice(int n, int[][] flights, int src, int dst, int k) {
        final int INF = Integer.MAX_VALUE;
        int[] dist = new int[n];
        Arrays.fill(dist, INF);
        dist[src] = 0;
        for (int round = 0; round <= k; round++) {
            int[] next = dist.clone();
            for (int[] f : flights)
                if (dist[f[0]] != INF && dist[f[0]] + f[2] < next[f[1]]) next[f[1]] = dist[f[0]] + f[2];
            dist = next;
        }
        return dist[dst] == INF ? -1 : dist[dst];
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt(), src = in.nextInt(), dst = in.nextInt(), k = in.nextInt();
        int[][] flights = new int[m][3];
        for (int i = 0; i < m; i++) for (int j = 0; j < 3; j++) flights[i][j] = in.nextInt();
        System.out.println(new Solution().findCheapestPrice(n, flights, src, dst, k));
    }
}

class FastReader {
    private final DataInputStream in;
    private final byte[] buf = new byte[1 << 16];
    private int len = 0, ptr = 0;
    FastReader(InputStream is) { in = new DataInputStream(is); }
    private int read() throws IOException {
        if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
        return buf[ptr++];
    }
    String next() throws IOException {
        int c = read();
        while (c != -1 && c <= ' ') c = read();
        if (c == -1) return null;
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = read(); }
        return sb.toString();
    }
    int nextInt() throws IOException { return Integer.parseInt(next()); }
}
```

</details>

<!-- test
in:
4 5 0 3 1
0 1 100
1 2 100
2 0 100
1 3 600
2 3 200
out:
700
-->
<!-- test
in:
3 3 0 2 1
0 1 100
1 2 100
0 2 500
out:
200
-->
<!-- test
in:
3 3 0 2 0
0 1 100
1 2 100
0 2 500
out:
500
-->
<!-- test
in:
3 1 0 2 5
0 1 1
out:
-1
-->

### Example 3 — Min Cost to Connect All Points · Medium

- **Source:** [LC 1584 · Min Cost to Connect All Points](https://leetcode.com/problems/min-cost-to-connect-all-points/) — Medium · `NC150`
- **Difficulty:** LeetCode Medium (≈ 1600 CF, est.)
- **Problem:** $n \le 1000$ points with integer coordinates in $[-10^6, 10^6]$. Connecting two points costs their Manhattan distance. Return the minimum total cost to connect all points.
- **Thinking from first principles:** that is the MST of the complete graph on the points. Kruskal needs all $\binom{n}{2} \approx 5 \cdot 10^5$ edges sorted, which is fine but memory heavy. For a **complete** graph, array-based Prim is the natural fit: keep `best[v]` = cheapest edge from the tree to $v$, repeatedly add the cheapest outside vertex, and update `best` with its distances. $O(n^2)$ time and $O(n)$ memory, with no heap and no edge list. (Manhattan MSTs can be built in $O(n \log n)$ with a sweep, which is CP territory.)

<details><summary>Solution</summary>

Correctness is the cut property: the added edge is the lightest edge crossing (tree, rest). Costs fit in `int` per edge ($\le 4 \cdot 10^6$), but the total can reach about $4 \cdot 10^9$, so use 64-bit for the sum. The driver reads $n$ and the points.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    long long minCostConnectPoints(vector<vector<int>>& points) {
        int n = points.size();
        vector<int> best(n, INT_MAX);                       // cheapest edge from the tree to v
        vector<bool> inTree(n, false);
        best[0] = 0;
        long long total = 0;
        for (int step = 0; step < n; ++step) {
            int u = -1;
            for (int v = 0; v < n; ++v)
                if (!inTree[v] && (u == -1 || best[v] < best[u])) u = v;   // closest outside vertex
            inTree[u] = true;
            total += best[u];
            for (int v = 0; v < n; ++v)
                if (!inTree[v]) {
                    int d = abs(points[u][0] - points[v][0]) + abs(points[u][1] - points[v][1]);
                    best[v] = min(best[v], d);
                }
        }
        return total;
    }
};

int main() {
    int n;
    cin >> n;
    vector<vector<int>> p(n, vector<int>(2));
    for (auto& q : p) cin >> q[0] >> q[1];
    cout << Solution().minCostConnectPoints(p) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public long minCostConnectPoints(int[][] points) {
        int n = points.length;
        int[] best = new int[n];
        Arrays.fill(best, Integer.MAX_VALUE);
        boolean[] inTree = new boolean[n];
        best[0] = 0;
        long total = 0;
        for (int step = 0; step < n; step++) {
            int u = -1;
            for (int v = 0; v < n; v++) if (!inTree[v] && (u == -1 || best[v] < best[u])) u = v;
            inTree[u] = true;
            total += best[u];
            for (int v = 0; v < n; v++)
                if (!inTree[v]) {
                    int d = Math.abs(points[u][0] - points[v][0]) + Math.abs(points[u][1] - points[v][1]);
                    best[v] = Math.min(best[v], d);
                }
        }
        return total;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[][] p = new int[n][2];
        for (int i = 0; i < n; i++) { p[i][0] = in.nextInt(); p[i][1] = in.nextInt(); }
        System.out.println(new Solution().minCostConnectPoints(p));
    }
}

class FastReader {
    private final DataInputStream in;
    private final byte[] buf = new byte[1 << 16];
    private int len = 0, ptr = 0;
    FastReader(InputStream is) { in = new DataInputStream(is); }
    private int read() throws IOException {
        if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
        return buf[ptr++];
    }
    String next() throws IOException {
        int c = read();
        while (c != -1 && c <= ' ') c = read();
        if (c == -1) return null;
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = read(); }
        return sb.toString();
    }
    int nextInt() throws IOException { return Integer.parseInt(next()); }
}
```

</details>

<!-- test
in:
5
0 0
2 2
3 10
5 2
7 0
out:
20
-->
<!-- test
in:
3
3 12
-2 5
-4 1
out:
18
-->
<!-- test
in:
1
0 0
out:
0
-->
<!-- test
in:
2
-1000000 -1000000
1000000 1000000
out:
4000000
-->

### Example 4 — Alien Dictionary · Hard 🔒

- **Source:** [LC 269 · Alien Dictionary](https://leetcode.com/problems/alien-dictionary/) — Hard 🔒 · `G169` `B75` `NC150`
- **Difficulty:** LeetCode Hard (≈ 1800 CF, est.)
- **Problem:** words (lowercase letters) sorted in an unknown alphabet. Return any letter order consistent with the list, or `""` if none exists. Every letter that appears must be in the output.
- **Thinking from first principles:** sorted order gives information only at the **first differing position** of each adjacent pair of words: if `w1[j] != w2[j]` is the first difference, then `w1[j]` comes before `w2[j]`, and nothing more can be learned from that pair. (Comparing non-adjacent pairs adds nothing new, because the order is transitive.) Two traps: (1) if `w2` is a proper prefix of `w1` (e.g. `abc` before `ab`), the input is contradictory, so return `""`; (2) letters with no constraints must still be output. The letters and constraints form a directed graph, and the answer is a topological order (cycle ⇒ `""`). This solution uses a min-heap in Kahn's algorithm, so it returns the lexicographically smallest valid order. That is deterministic, and any valid order is accepted.

<details><summary>Solution</summary>

Edges from adjacent pairs ($O(\sum |w|)$), then Kahn's algorithm with a min-heap over at most 26 letters. Deduplicate edges with a 26×26 matrix so in-degrees are not double counted. The driver reads the words and prints the order in quotes.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    string alienOrder(vector<string>& words) {
        bool present[26] = {}, edge[26][26] = {};
        int indeg[26] = {};
        for (auto& w : words) for (char c : w) present[c - 'a'] = true;
        for (size_t i = 0; i + 1 < words.size(); ++i) {
            const string &a = words[i], &b = words[i + 1];
            size_t j = 0;
            while (j < a.size() && j < b.size() && a[j] == b[j]) ++j;
            if (j == min(a.size(), b.size())) {
                if (a.size() > b.size()) return "";          // "abc" before its prefix "ab"
                continue;                                    // a is a prefix of b: no information
            }
            int x = a[j] - 'a', y = b[j] - 'a';              // first difference: x before y
            if (!edge[x][y]) { edge[x][y] = true; indeg[y]++; }
        }
        priority_queue<int, vector<int>, greater<int>> pq;   // smallest available letter first
        int total = 0;
        for (int c = 0; c < 26; ++c) if (present[c]) { ++total; if (indeg[c] == 0) pq.push(c); }
        string order;
        while (!pq.empty()) {
            int u = pq.top(); pq.pop();
            order += char('a' + u);
            for (int v = 0; v < 26; ++v)
                if (edge[u][v] && --indeg[v] == 0) pq.push(v);
        }
        return (int)order.size() == total ? order : "";      // a cycle leaves letters behind
    }
};

int main() {
    int n;
    cin >> n;
    vector<string> words(n);
    for (auto& w : words) cin >> w;
    cout << '"' << Solution().alienOrder(words) << '"' << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public String alienOrder(String[] words) {
        boolean[] present = new boolean[26];
        boolean[][] edge = new boolean[26][26];
        int[] indeg = new int[26];
        for (String w : words) for (char c : w.toCharArray()) present[c - 'a'] = true;
        for (int i = 0; i + 1 < words.length; i++) {
            String a = words[i], b = words[i + 1];
            int j = 0;
            while (j < a.length() && j < b.length() && a.charAt(j) == b.charAt(j)) j++;
            if (j == Math.min(a.length(), b.length())) {
                if (a.length() > b.length()) return "";
                continue;
            }
            int x = a.charAt(j) - 'a', y = b.charAt(j) - 'a';
            if (!edge[x][y]) { edge[x][y] = true; indeg[y]++; }
        }
        PriorityQueue<Integer> pq = new PriorityQueue<>();
        int total = 0;
        for (int c = 0; c < 26; c++) if (present[c]) { total++; if (indeg[c] == 0) pq.add(c); }
        StringBuilder order = new StringBuilder();
        while (!pq.isEmpty()) {
            int u = pq.poll();
            order.append((char) ('a' + u));
            for (int v = 0; v < 26; v++) if (edge[u][v] && --indeg[v] == 0) pq.add(v);
        }
        return order.length() == total ? order.toString() : "";
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        String[] words = new String[n];
        for (int i = 0; i < n; i++) words[i] = in.next();
        System.out.println("\"" + new Solution().alienOrder(words) + "\"");
    }
}

class FastReader {
    private final DataInputStream in;
    private final byte[] buf = new byte[1 << 16];
    private int len = 0, ptr = 0;
    FastReader(InputStream is) { in = new DataInputStream(is); }
    private int read() throws IOException {
        if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
        return buf[ptr++];
    }
    String next() throws IOException {
        int c = read();
        while (c != -1 && c <= ' ') c = read();
        if (c == -1) return null;
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = read(); }
        return sb.toString();
    }
    int nextInt() throws IOException { return Integer.parseInt(next()); }
}
```

</details>

<!-- test
in:
5
wrt wrf er ett rftt
out:
"wertf"
-->
<!-- test
in:
2
z x
out:
"zx"
-->
<!-- test
in:
3
z x z
out:
""
-->
<!-- test
in:
2
abc ab
out:
""
-->
<!-- test
in:
2
ab abc
out:
"abc"
-->

### Example 5 — Word Ladder · Hard

- **Source:** [LC 127 · Word Ladder](https://leetcode.com/problems/word-ladder/) — Hard · `G75` `NC150` `TI150`
- **Difficulty:** LeetCode Hard (≈ 1600 CF, est.)
- **Problem:** `beginWord`, `endWord` and a dictionary of $\le 5000$ words of length $L \le 10$. Each step changes one letter, and every intermediate word must be in the dictionary. Return the number of words in the shortest transformation sequence (including both ends), or 0.
- **Thinking from first principles:** words are nodes and one-letter changes are unit-weight edges, so this is BFS. The cost is in generating neighbours. Comparing a word against all $N$ others costs $O(NL)$ per word, $O(N^2 L)$ in total, about $2.5 \cdot 10^8$. Instead, try all $26L$ one-letter mutations and look each up in a hash set: $O(26 L \cdot L)$ per word (the hash of an $L$-letter string costs $L$). Remove words from the set when they are enqueued, which serves as the visited mark. Bidirectional BFS (expand the smaller frontier from both ends) cuts the explored area dramatically. Mention it as the follow-up.

<details><summary>Solution</summary>

Level-order BFS from `beginWord`. The answer is the level at which `endWord` is dequeued, counting `beginWord` as level 1. $O(N \cdot 26 \cdot L^2)$ time, $O(NL)$ space. The driver reads `beginWord endWord n` and the dictionary.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int ladderLength(string beginWord, string endWord, vector<string>& wordList) {
        unordered_set<string> unused(wordList.begin(), wordList.end());   // dictionary minus visited
        if (!unused.count(endWord)) return 0;
        queue<string> q;
        q.push(beginWord);
        unused.erase(beginWord);
        for (int level = 1; !q.empty(); ++level) {
            for (int sz = q.size(); sz > 0; --sz) {
                string w = q.front(); q.pop();
                if (w == endWord) return level;
                for (size_t i = 0; i < w.size(); ++i) {
                    char orig = w[i];
                    for (char c = 'a'; c <= 'z'; ++c) {
                        if (c == orig) continue;
                        w[i] = c;
                        if (unused.count(w)) { unused.erase(w); q.push(w); }   // mark on push
                    }
                    w[i] = orig;
                }
            }
        }
        return 0;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    string b, e;
    int n;
    cin >> b >> e >> n;
    vector<string> words(n);
    for (auto& w : words) cin >> w;
    cout << Solution().ladderLength(b, e, words) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int ladderLength(String beginWord, String endWord, List<String> wordList) {
        Set<String> unused = new HashSet<>(wordList);
        if (!unused.contains(endWord)) return 0;
        ArrayDeque<String> q = new ArrayDeque<>();
        q.add(beginWord);
        unused.remove(beginWord);
        for (int level = 1; !q.isEmpty(); level++) {
            for (int sz = q.size(); sz > 0; sz--) {
                String w = q.poll();
                if (w.equals(endWord)) return level;
                char[] cs = w.toCharArray();
                for (int i = 0; i < cs.length; i++) {
                    char orig = cs[i];
                    for (char c = 'a'; c <= 'z'; c++) {
                        if (c == orig) continue;
                        cs[i] = c;
                        String cand = new String(cs);
                        if (unused.remove(cand)) q.add(cand);   // remove() returns true if it was present
                    }
                    cs[i] = orig;
                }
            }
        }
        return 0;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        String b = in.next(), e = in.next();
        int n = in.nextInt();
        List<String> words = new ArrayList<>();
        for (int i = 0; i < n; i++) words.add(in.next());
        System.out.println(new Solution().ladderLength(b, e, words));
    }
}

class FastReader {
    private final DataInputStream in;
    private final byte[] buf = new byte[1 << 16];
    private int len = 0, ptr = 0;
    FastReader(InputStream is) { in = new DataInputStream(is); }
    private int read() throws IOException {
        if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
        return buf[ptr++];
    }
    String next() throws IOException {
        int c = read();
        while (c != -1 && c <= ' ') c = read();
        if (c == -1) return null;
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = read(); }
        return sb.toString();
    }
    int nextInt() throws IOException { return Integer.parseInt(next()); }
}
```

</details>

<!-- test
in:
hit cog 6
hot dot dog lot log cog
out:
5
-->
<!-- test
in:
hit cog 5
hot dot dog lot log
out:
0
-->
<!-- test
in:
a c 3
a b c
out:
2
-->
<!-- test
in:
hot dog 2
hot dog
out:
0
-->

## 6. Pitfalls and things to remember

1. **Dijkstra with negative edges is wrong**, even without negative cycles. Check the constraints before choosing it.
2. **Stale heap entries:** in lazy Dijkstra, `if (d > dist[u]) continue;` is mandatory for the complexity. Without it, each stale pop re-relaxes all edges.
3. **Overflow in `dist + w`:** with `INT_MAX` as infinity, `dist[u] + w` overflows. Check `dist[u] != INF` first or use `LLONG_MAX / 4`.
4. **Bellman–Ford "at most $k$ edges" needs the copy** of the previous round. In-place relaxation is fine for plain shortest paths but breaks the edge limit.
5. **"$k$ stops" means $k + 1$ edges.** Off-by-one here is the most common wrong answer.
6. **Prim on complete graphs:** the $O(n^2)$ array version beats a heap version that pushes all $n^2$ edges.
7. **MST totals overflow 32 bits** sooner than you think ($n$ edges × $10^6$ each).
8. **Alien Dictionary traps:** a longer word before its own prefix means invalid input; duplicate edges inflate in-degrees; isolated letters must still be printed.
9. **Word Ladder:** check `endWord` is in the dictionary first. Mark visited when *enqueuing* (erase from the set), or the frontier explodes.
10. **Java heaps of `int[]`:** the comparator must compare the distance field. `PriorityQueue<int[]>` without a comparator throws `ClassCastException` at runtime.

## 7. Follow-up questions interviewers ask

| Follow-up | Strong answer |
|---|---|
| "Why not BFS?" | BFS assumes equal weights; with weights, a path with more edges can be cheaper |
| "Return the path itself" | store `parent[v]` when relaxing, then walk back from the target |
| Network delay → "graph with $10^6$ edges, many queries from different sources" | precompute per source only if few sources; otherwise Dijkstra per query; all-pairs only for small $V$ |
| Cheapest flights → "Dijkstra variant?" | state `(cost, city, flights)`; push a state if it improves the best cost *or* the fewest flights seen for that city |
| MST → "is the MST unique?" | unique iff no non-tree edge has weight equal to the heaviest edge on the tree path between its endpoints |
| MST → "edges in every MST / some MST" | per edge: force-exclude (MST weight grows ⇒ critical), force-include (weight unchanged ⇒ pseudo-critical) ([LC 1489 · Find Critical and Pseudo-Critical Edges in Minimum Spanning Tree](https://leetcode.com/problems/find-critical-and-pseudo-critical-edges-in-minimum-spanning-tree/) — Hard) |
| Word ladder → "return all shortest sequences" | BFS to build a layered parent graph, then DFS backwards to enumerate paths ([LC 126 · Word Ladder II](https://leetcode.com/problems/word-ladder-ii/) — Hard) |
| Word ladder → "make it faster" | bidirectional BFS; wildcard buckets (`h*t → [hot, hit]`) to generate neighbours |
| Alien dictionary → "is the order unique?" | Kahn's queue must hold exactly one candidate at every step |
| "Negative cycle detection" | an extra Bellman–Ford round that still relaxes; or Floyd–Warshall with a negative diagonal |

## 8. Problem list

Badges come only from the lists fetched on 23 Oct 2026 (legend in [18-leetcode-master-list.md](18-leetcode-master-list.md)): `G75` · `G169` · `B75` · `NC150` · `NC250` · `TI150`; 🔒 = Premium.

**Medium** (4)

- [ ] [LC 743 · Network Delay Time](https://leetcode.com/problems/network-delay-time/) — Medium · `NC150`
- [ ] [LC 787 · Cheapest Flights Within K Stops](https://leetcode.com/problems/cheapest-flights-within-k-stops/) — Medium · `G169` `NC150`
- [ ] [LC 1584 · Min Cost to Connect All Points](https://leetcode.com/problems/min-cost-to-connect-all-points/) — Medium · `NC150`
- [ ] [LC 1631 · Path With Minimum Effort](https://leetcode.com/problems/path-with-minimum-effort/) — Medium · `NC250`

**Hard** (8)

- [ ] [LC 127 · Word Ladder](https://leetcode.com/problems/word-ladder/) — Hard · `G75` `NC150` `TI150`
- [ ] [LC 269 · Alien Dictionary](https://leetcode.com/problems/alien-dictionary/) — Hard 🔒 · `G169` `B75` `NC150`
- [ ] [LC 332 · Reconstruct Itinerary](https://leetcode.com/problems/reconstruct-itinerary/) — Hard · `NC150`
- [ ] [LC 778 · Swim in Rising Water](https://leetcode.com/problems/swim-in-rising-water/) — Hard · `NC150`
- [ ] [LC 815 · Bus Routes](https://leetcode.com/problems/bus-routes/) — Hard · `G169`
- [ ] [LC 1489 · Find Critical and Pseudo-Critical Edges in Minimum Spanning Tree](https://leetcode.com/problems/find-critical-and-pseudo-critical-edges-in-minimum-spanning-tree/) — Hard · `NC250`
- [ ] [LC 2392 · Build a Matrix With Conditions](https://leetcode.com/problems/build-a-matrix-with-conditions/) — Hard · `NC250`
- [ ] [LC 2709 · Greatest Common Divisor Traversal](https://leetcode.com/problems/greatest-common-divisor-traversal/) — Hard · `NC250`

**Beyond the lists:**

- [ ] [LC 1514 · Path with Maximum Probability](https://leetcode.com/problems/path-with-maximum-probability/) — Medium — Dijkstra with `max` and `*`
- [ ] [LC 1334 · Find the City With the Smallest Number of Neighbors at a Threshold Distance](https://leetcode.com/problems/find-the-city-with-the-smallest-number-of-neighbors-at-a-threshold-distance/) — Medium — Floyd–Warshall
- [ ] [LC 1976 · Number of Ways to Arrive at Destination](https://leetcode.com/problems/number-of-ways-to-arrive-at-destination/) — Medium — Dijkstra + path counting (mod)
- [ ] [LC 1135 · Connecting Cities With Minimum Cost](https://leetcode.com/problems/connecting-cities-with-minimum-cost/) — Medium 🔒 — Kruskal
- [ ] [LC 2290 · Minimum Obstacle Removal to Reach Corner](https://leetcode.com/problems/minimum-obstacle-removal-to-reach-corner/) — Hard — 0-1 BFS
- [ ] [LC 1368 · Minimum Cost to Make at Least One Valid Path in a Grid](https://leetcode.com/problems/minimum-cost-to-make-at-least-one-valid-path-in-a-grid/) — Hard — 0-1 BFS
- [ ] [LC 1192 · Critical Connections in a Network](https://leetcode.com/problems/critical-connections-in-a-network/) — Hard — bridges (Tarjan)
- [ ] [LC 1168 · Optimize Water Distribution in a Village](https://leetcode.com/problems/optimize-water-distribution-in-a-village/) — Hard 🔒 — MST with a virtual well node
- [ ] [LC 126 · Word Ladder II](https://leetcode.com/problems/word-ladder-ii/) — Hard — layered BFS + backtracking

## 9. CP counterpart

- [Shortest paths (CP)](../09-Graphs/02-shortest-paths.md): Dijkstra variants, 0-1 BFS, SPFA caveats, Floyd–Warshall, Johnson.
- [Minimum spanning trees](../09-Graphs/03-minimum-spanning-trees.md): Kruskal/Prim/Borůvka, MST properties, the Kruskal reconstruction tree.
- [Topological sort and DAG DP](../09-Graphs/04-topological-sort-and-dag-dp.md): alien-dictionary-style constraint graphs.
- [Euler paths and circuits](../09-Graphs/08-euler-paths-and-circuits.md): Reconstruct Itinerary is Hierholzer with lexicographic order.
- [Bridges, articulation points and BCC](../09-Graphs/06-bridges-articulation-points-and-bcc.md): critical connections.

Interview difference: the expected solution is usually the textbook algorithm on a modelled graph. CP adds state compression, potentials and data-structure-accelerated relaxations, which are overkill here.

## 10. Self-check

1. Why can Dijkstra settle the minimum-distance node, and which assumption does that need?
2. What does `dist` mean after round $i$ of Bellman–Ford, and why does the $k$-stops version need a copy?
3. State the cut property and use it to justify Prim's algorithm.
4. When is $O(n^2)$ Prim better than Kruskal?
5. In Alien Dictionary, what is learned from a pair of adjacent words, and which input is invalid?
6. Why does Word Ladder generate neighbours by mutation instead of comparing all pairs?
7. How does 0-1 BFS keep the deque ordered by distance?

<details><summary>Answers</summary>

1. Any other path to it leaves the settled set through a node whose tentative distance is at least as large, and the rest of the path adds non-negative weight. That needs all weights $\ge 0$.
2. The cheapest cost using at most $i$ edges. Relaxing in place could use an edge updated earlier in the same round, giving a path with more than $i$ edges.
3. The lightest edge crossing any cut is in some MST. Prim's tree defines a cut (tree vs rest), and it always adds the lightest crossing edge.
4. On dense or complete graphs ($E \approx V^2$), where Kruskal must generate and sort $\Theta(V^2)$ edges.
5. Only the first differing letter: `w1[j]` precedes `w2[j]`. A word followed by its own proper prefix is invalid.
6. Mutation costs $O(26 L^2)$ per word, independent of $N$, while comparing against all words costs $O(NL)$ per word, $O(N^2 L)$ in total.
7. A weight-0 edge leads to a node at the same distance as the front, so it goes to the front. A weight-1 edge leads to distance + 1, which goes to the back. The deque then holds at most two consecutive distance values in sorted order.

</details>
