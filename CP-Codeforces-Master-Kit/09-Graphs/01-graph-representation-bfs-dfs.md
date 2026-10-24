# Graph Representation, BFS and DFS

> **Band:** 🟢 800 → 🔵 1900 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [complexity and constraint reading](../01-Foundations/01-complexity-and-constraint-reading.md), [STL and Java collections](../01-Foundations/02-cpp-stl-and-java-collections.md), [recursion](../01-Foundations/04-recursion-brute-force-and-backtracking.md)
> **You can say you know this when:** you can turn a statement into "vertices = states, edges = moves", pick a representation that fits the constraints (CSR arrays in Java), and write BFS with path restoration, multi-source BFS, 0-1 BFS, BFS over composite states and an iterative DFS with entry/exit times and cycle detection from memory, without bugs, in both languages.

## 1. First principles — why this works

**What a graph is to a solver.** A graph is a set of *states* (vertices) and *moves* (edges). Most "graph problems" never
say "graph": a grid maze, the numbers reachable from $x$ by "double it or subtract one", the configurations of a lock,
the pairs (cell, walls broken so far). The first skill is to name the state so that the question becomes "is there a path",
"what is the shortest path" or "what is connected to what". Everything in this folder is built on the two traversals in
this file.

**Representation follows the operations you need.**

| Operation you need | Adjacency matrix | Adjacency list (`vector<vector<int>>`) | CSR (compressed sparse row) | Edge list |
|---|---|---|---|---|
| iterate neighbors of $u$ | $O(n)$ | $O(\deg u)$ | $O(\deg u)$, contiguous | $O(m)$ |
| "is $(u,v)$ an edge?" | $O(1)$ | $O(\deg u)$ | $O(\log \deg u)$ if sorted | $O(m)$ |
| memory | $n^2$ | $O(n+m)$, many small allocations | $O(n+m)$, two flat arrays | $O(m)$ |
| typical use | $n \le 2000$, Floyd–Warshall, bitsets | default in C++ | default in Java, huge graphs | Kruskal, Bellman–Ford |

CSR stores all neighbor lists back to back in one array `adj`, with `start[v]` pointing at the first neighbor of `v`
(and `start[v+1]` one past the last). It is built in two passes: count degrees, prefix-sum them into `start`, then drop each
edge into its slot. In Java this replaces $n$ `ArrayList<Integer>` objects (each with boxing and pointer chasing) by two
`int[]`s, which is often the difference between TLE and 300 ms at $n = m = 2\cdot 10^5$.

**Implicit graphs.** If the neighbors of a state can be computed, never build the graph. A grid cell $(r,c)$ has id
$r\cdot C + c$ and four candidate neighbors; a number $x$ has neighbors $2x$ and $x-1$; a bitmask state has its one-bit
flips. You only store `dist[]` / `visited[]` indexed by the state id, so the cost is the number of states times the
branching factor.

**BFS — why "first time seen" is the shortest distance.** Define layers: $L_0 = \{s\}$ and
$L_{k+1}$ = vertices adjacent to $L_k$ that are in no earlier layer. Claim: $v \in L_k \iff \operatorname{dist}(s,v) = k$.
*Proof by induction on $k$.* If $\operatorname{dist}(v) = k+1$, the shortest path's second-to-last vertex $u$ has
$\operatorname{dist}(u) = k$, so $u \in L_k$ and $v$ is adjacent to $L_k$; $v$ is in no earlier layer since those contain only
vertices at distance $\le k$. Conversely, $v \in L_{k+1}$ means a path of length $k+1$ exists and $v$ is not at distance
$\le k$. A FIFO queue produces exactly these layers: the queue always holds some vertices of $L_k$ followed by some of
$L_{k+1}$ (the **two-value invariant**), because a vertex popped from $L_k$ only pushes vertices of $L_{k+1}$. Each vertex
enters the queue once and each edge is scanned once (twice if undirected): $O(n+m)$.

**Multi-source BFS** ("distance to the nearest fire / shop / zero cell") is BFS from a virtual super-source joined by
edges to every source. Removing that virtual vertex just means: start with all sources in the queue at distance 0.
One BFS, $O(n+m)$, instead of one BFS per source.

**0-1 BFS.** With edge weights in $\{0,1\}$ the layers argument breaks (a 0-edge keeps you in the same layer), but the
fix is tiny: keep a **deque** whose distances are non-decreasing and span at most two values $d, d+1$. Relaxing through a
0-edge gives distance $d$ → push to the front; through a 1-edge gives $d+1$ → push to the back. The invariant holds, so
vertices are popped in non-decreasing distance order, which is exactly Dijkstra's order (see
[shortest paths](02-shortest-paths.md)) without the $\log$. A vertex can be pushed at most twice (its tentative value can
only drop from $d+1$ to $d$), so the total is $O(n+m)$.

**BFS on states.** If the move rules depend on history (walls broken, keys held, direction faced, time modulo $k$),
put that history into the vertex: the state becomes $(\text{cell}, \text{extra})$. The graph is still unweighted, BFS still
works, and the cost is $\#\text{states}\times\text{branching}$. The art is finding the *smallest* extra information that makes
the future independent of the past (exactly the DP-state question; see
[DP state design](../06-Dynamic-Programming/01-dp-first-principles-and-state-design.md)).

**Bidirectional BFS.** With branching factor $b$ and answer $d$, one BFS touches about $b^d$ states; two BFS's that meet
in the middle touch about $2b^{d/2}$. Correct termination is the subtle part: expand **whole layers**, always the smaller
frontier, and stop at the first layer expansion that touches a vertex already seen by the other side; then the answer is the
minimum of $d_S(u) + 1 + d_T(v)$ over the touching edges. *Why it is exact:* before that expansion no vertex had both
$d_S \le a$ and $d_T \le b$, which forces $\operatorname{dist}(s,t) > a+b$; every candidate found while expanding layer $a$ is
$\le a+1+b$; the shortest path's vertex at $d_S = a+1$ yields a candidate of exactly $a+1+b$. Stopping at the first
*single* meeting vertex inside a layer is a classic bug only when you then compare candidates from different layers.

**DFS — the stack discipline.** DFS goes as deep as possible and backtracks; the recursion stack is always the path from
the root to the current vertex. Record `tin[v]` when $v$ is entered and `tout[v]` when it is finished. Two facts carry most
of the theory:

- **Parenthesis theorem.** For any $u, v$ the intervals $[\text{tin}_u, \text{tout}_u]$ and $[\text{tin}_v,
  \text{tout}_v]$ are either disjoint or nested, and nested exactly when one is an ancestor of the other in the DFS forest.
  (A vertex entered while $u$ is on the stack is finished before $u$ is popped.)
- **White-path theorem.** $v$ becomes a descendant of $u$ iff, at time $\text{tin}_u$, there is a path from $u$ to $v$
  consisting only of unvisited ("white") vertices.

**Edge classification (directed graphs).** Color vertices white (unvisited), gray (on the stack), black (finished). When
DFS at $u$ looks at the edge $u \to v$:

| color of $v$ | edge type | meaning |
|---|---|---|
| white | tree edge | $v$ becomes a child of $u$ |
| gray | back edge | $v$ is an ancestor of $u$ (on the stack) → **a cycle** $v \to \dots \to u \to v$ |
| black, $\text{tin}_u < \text{tin}_v$ | forward edge | $v$ is an already-finished descendant |
| black, $\text{tin}_v < \text{tin}_u$ | cross edge | $v$ is in an earlier, finished subtree |

**A directed graph has a cycle iff DFS finds a back edge.** A back edge closes a cycle with the tree path. Conversely, let
$v$ be the first vertex of some cycle to be entered and $u$ its predecessor on the cycle. At $\text{tin}_v$ the rest of the
cycle is white, so by the white-path theorem $u$ becomes a descendant of $v$, and when $u$ scans $u\to v$, $v$ is still
gray. This is why cycle detection needs **three** colors: a black vertex reached again (forward/cross edge) is *not* a cycle.

**Undirected graphs have only tree and back edges.** If $\{u,v\}$ is a non-tree edge with $u$ entered first, then $v$ was
white and reachable from $u$ when $u$ was entered, so $v$ is a descendant of $u$: the edge goes to an ancestor. Hence an
undirected graph has a cycle iff DFS meets an edge to an already visited vertex *other than through the edge it came in on*
(compare edge ids, not parent vertices, if parallel edges exist). This "no cross edges" fact is the base of
[bridges and articulation points](06-bridges-articulation-points-and-bcc.md).

**Connected components** are the trees of the DFS/BFS forest: start a traversal from every unvisited vertex. If edges
only arrive over time and you never delete, a [DSU](../08-Data-Structures/06-dsu-and-variants.md) does the same job online.

**Iterative DFS done right.** Java's default thread stack overflows around $10^4$–$10^5$ frames, and even C++ on Windows
has a 1 MB default stack. The faithful iterative DFS keeps, for each vertex on an explicit stack, an iterator into its
adjacency list (`it[u]`): look at the top $u$; if it has an unscanned edge, scan it (and push the child if white);
otherwise pop $u$ and set `tout[u]`. This reproduces the recursive order exactly, so `tin/tout`, colors, low-links and
post-orders are all correct. The shortcut "pop $u$, push all its unvisited neighbors" is fine for reachability and
component counting but is **not** a DFS order: never use it for cycle detection, topological sort or low-link.

## 2. Formulas, definitions and identities

- **Handshake lemma:** $\sum_v \deg(v) = 2m$ (each edge counted at both ends), so the number of odd-degree vertices is even.
  Directed: $\sum_v \deg^+(v) = \sum_v \deg^-(v) = m$.
- **Edge bounds:** a simple undirected graph has $m \le \binom{n}{2}$; a tree has $m = n-1$; a forest with $c$ components has
  $m = n - c$. The **cyclomatic number** $m - n + c$ is the number of independent cycles (dimension of the cycle space; see
  [cycle basis](09-bipartite-graphs-and-cycles.md)).
- **Grid ids:** $\text{id} = r\cdot C + c$, $r = \lfloor \text{id}/C \rfloor$, $c = \text{id} \bmod C$; 4-neighbors via
  `dr = {1,-1,0,0}`, `dc = {0,0,1,-1}`; on an $R\times C$ grid with 4-moves $m \le 2RC$.
- **BFS distance recurrence:** $\operatorname{dist}(v) = 1 + \min_{u \to v} \operatorname{dist}(u)$. In an undirected graph,
  every edge $\{u,v\}$ satisfies $|\operatorname{dist}(u) - \operatorname{dist}(v)| \le 1$: non-tree edges of a BFS tree join
  equal or adjacent layers. (Consequence: an edge inside a layer closes an odd cycle — see
  [bipartite graphs](09-bipartite-graphs-and-cycles.md).)
- **Shortest-path DAG:** edge $u\to v$ lies on some shortest $s$-path iff $\operatorname{dist}(v) = \operatorname{dist}(u)+1$;
  counting/extracting shortest paths is DP over this DAG in BFS order.
- **0-1 BFS invariant:** deque values are non-decreasing and $\max - \min \le 1$; each vertex is pushed $\le 2$ times; $O(n+m)$.
- **Bidirectional BFS:** work $\approx 2 b^{d/2}$ instead of $b^{d}$; answer $= a + 1 + b$ at the first meeting while expanding
  layer $a$ of one side against completed layers $0..b$ of the other.
- **Parenthesis theorem:** $u$ is an ancestor of $v$ $\iff \text{tin}_u \le \text{tin}_v$ and $\text{tout}_v \le \text{tout}_u$
  (with one shared timer for entries and exits). With a timer that only counts entries, the subtree of $u$ is the contiguous
  range $[\text{tin}_u, \text{tin}_u + \text{size}_u)$ — the Euler-tour trick of [tree basics](../10-Trees/01-tree-basics-diameter-center-euler-tour.md).
- **Complexities:** BFS / DFS / components / flood fill $O(n+m)$ time, $O(n)$ extra memory; BFS on states
  $O(\#\text{states}\cdot\text{branching})$; adjacency-matrix traversal $O(n^2)$.

## 3. Implementation (C++ and Java)

### 3.1 CSR adjacency (build once, traverse fast)

```cpp
// Neighbors of v are adj[start[v] .. start[v+1]).  Vertices are 0-indexed.
struct CSR {
    int n;
    vector<int> start, adj;
    CSR(int n, const vector<pair<int, int>>& edges, bool directed) : n(n), start(n + 1, 0) {
        for (auto [u, v] : edges) { start[u + 1]++; if (!directed) start[v + 1]++; }
        for (int i = 0; i < n; i++) start[i + 1] += start[i];
        adj.resize(start[n]);
        vector<int> pos(start.begin(), start.end() - 1);   // next free slot of each vertex
        for (auto [u, v] : edges) { adj[pos[u]++] = v; if (!directed) adj[pos[v]++] = u; }
    }
};
```

```java
static final class CSR {
    final int n;
    final int[] start, adj;   // neighbors of v: adj[start[v] .. start[v+1])
    CSR(int n, int[] eu, int[] ev, boolean directed) {
        this.n = n;
        start = new int[n + 1];
        int m = eu.length;
        for (int i = 0; i < m; i++) { start[eu[i] + 1]++; if (!directed) start[ev[i] + 1]++; }
        for (int i = 0; i < n; i++) start[i + 1] += start[i];
        adj = new int[start[n]];
        int[] pos = Arrays.copyOf(start, n);
        for (int i = 0; i < m; i++) {
            adj[pos[eu[i]]++] = ev[i];
            if (!directed) adj[pos[ev[i]]++] = eu[i];
        }
    }
}
```

A popular alternative in Java is the "forward star" (`head[v]`, `nxt[e]`, `to[e]`): edges are prepended to a linked list
per vertex, so it supports adding edges online, but iterates neighbors in *reverse* insertion order and with worse cache
behavior than CSR.

### 3.2 BFS with parents, multi-source, and path restoration

```cpp
// Multi-source BFS: every vertex in `sources` starts at distance 0.  dist = -1 means unreachable.
pair<vector<int>, vector<int>> bfs(const vector<vector<int>>& g, const vector<int>& sources) {
    int n = g.size();
    vector<int> dist(n, -1), par(n, -1), q;
    q.reserve(n);
    for (int s : sources) if (dist[s] < 0) { dist[s] = 0; q.push_back(s); }
    for (size_t h = 0; h < q.size(); h++) {          // a vector used as a queue: no deque overhead
        int u = q[h];
        for (int v : g[u]) if (dist[v] < 0) { dist[v] = dist[u] + 1; par[v] = u; q.push_back(v); }
    }
    return {dist, par};
}

vector<int> restorePath(const vector<int>& par, int t) {   // source ... t, assuming dist[t] >= 0
    vector<int> path;
    for (int v = t; v != -1; v = par[v]) path.push_back(v);
    reverse(path.begin(), path.end());
    return path;
}
```

```java
// Returns {dist, par}; adjacency in CSR form (start, adj).
static int[][] bfs(int n, int[] start, int[] adj, int[] sources) {
    int[] dist = new int[n], par = new int[n], q = new int[n];
    Arrays.fill(dist, -1);
    Arrays.fill(par, -1);
    int head = 0, tail = 0;
    for (int s : sources) if (dist[s] < 0) { dist[s] = 0; q[tail++] = s; }
    while (head < tail) {
        int u = q[head++];
        for (int e = start[u]; e < start[u + 1]; e++) {
            int v = adj[e];
            if (dist[v] < 0) { dist[v] = dist[u] + 1; par[v] = u; q[tail++] = v; }
        }
    }
    return new int[][]{dist, par};
}

static int[] restorePath(int[] par, int t) {
    int len = 0;
    for (int v = t; v != -1; v = par[v]) len++;
    int[] path = new int[len];
    for (int v = t, i = len - 1; v != -1; v = par[v]) path[i--] = v;
    return path;
}
```

### 3.3 0-1 BFS

```cpp
// g[u] = list of (v, w) with w in {0, 1}.  Returns INT_MAX for unreachable vertices.
vector<int> zeroOneBfs(const vector<vector<pair<int, int>>>& g, int s) {
    vector<int> dist(g.size(), INT_MAX);
    deque<int> dq;
    dist[s] = 0;
    dq.push_back(s);
    while (!dq.empty()) {
        int u = dq.front(); dq.pop_front();
        for (auto [v, w] : g[u]) {
            if (dist[u] + w < dist[v]) {
                dist[v] = dist[u] + w;
                if (w == 0) dq.push_front(v); else dq.push_back(v);   // keeps the deque sorted
            }
        }
    }
    return dist;
}
```

```java
// Edge arrays: neighbors of u are to[start[u]..start[u+1]) with weights wt[...] in {0,1}.
static int[] zeroOneBfs(int n, int[] start, int[] to, int[] wt, int s) {
    int[] dist = new int[n];
    Arrays.fill(dist, Integer.MAX_VALUE);
    int cap = 2 * n + 1;                    // each vertex is pushed at most twice
    int[] dq = new int[cap];
    int head = 0, size = 0;
    dist[s] = 0;
    dq[0] = s; size = 1;
    while (size > 0) {
        int u = dq[head]; head = (head + 1) % cap; size--;
        for (int e = start[u]; e < start[u + 1]; e++) {
            int v = to[e], nd = dist[u] + wt[e];
            if (nd < dist[v]) {
                dist[v] = nd;
                if (wt[e] == 0) { head = (head - 1 + cap) % cap; dq[head] = v; }
                else dq[(head + size) % cap] = v;
                size++;
            }
        }
    }
    return dist;
}
```

### 3.4 Iterative DFS: entry/exit times, edge classification, directed cycle

```cpp
struct DfsInfo {
    vector<int> tin, tout, parent;
    long long tree = 0, back = 0, forward = 0, cross = 0;
};

// Faithful iterative DFS over all vertices (directed graph).  One timer for entries and exits.
DfsInfo dfsAll(const vector<vector<int>>& g) {
    int n = g.size(), timer = 0;
    DfsInfo r;
    r.tin.assign(n, -1); r.tout.assign(n, -1); r.parent.assign(n, -1);
    vector<int> color(n, 0), it(n, 0), st;        // 0 white, 1 gray (on stack), 2 black
    for (int s = 0; s < n; s++) {
        if (color[s]) continue;
        color[s] = 1; r.tin[s] = timer++; st.push_back(s);
        while (!st.empty()) {
            int u = st.back();
            if (it[u] < (int)g[u].size()) {
                int v = g[u][it[u]++];
                if (color[v] == 0) { r.tree++; r.parent[v] = u; color[v] = 1; r.tin[v] = timer++; st.push_back(v); }
                else if (color[v] == 1) r.back++;                 // v is an ancestor: cycle
                else if (r.tin[u] < r.tin[v]) r.forward++;
                else r.cross++;
            } else {
                color[u] = 2; r.tout[u] = timer++; st.pop_back();
            }
        }
    }
    return r;
}
```

```java
// Returns {tin, tout, parent, counts} where counts = {tree, back, forward, cross}.
static int[][] dfsAll(int n, int[] start, int[] adj) {
    int[] tin = new int[n], tout = new int[n], par = new int[n], color = new int[n], it = new int[n], st = new int[n];
    int[] cnt = new int[4];
    Arrays.fill(par, -1);
    int timer = 0;
    for (int s = 0; s < n; s++) {
        if (color[s] != 0) continue;
        int top = 0;
        color[s] = 1; tin[s] = timer++; st[top++] = s; it[s] = start[s];
        while (top > 0) {
            int u = st[top - 1];
            if (it[u] < start[u + 1]) {
                int v = adj[it[u]++];
                if (color[v] == 0) { cnt[0]++; par[v] = u; color[v] = 1; tin[v] = timer++; it[v] = start[v]; st[top++] = v; }
                else if (color[v] == 1) cnt[1]++;
                else if (tin[u] < tin[v]) cnt[2]++;
                else cnt[3]++;
            } else {
                color[u] = 2; tout[u] = timer++; top--;
            }
        }
    }
    return new int[][]{tin, tout, par, cnt};
}
```

### 3.5 Bidirectional BFS (undirected, unweighted)

```cpp
int bidirectionalBfs(const vector<vector<int>>& g, int s, int t) {
    if (s == t) return 0;
    int n = g.size();
    vector<int> d[2] = {vector<int>(n, -1), vector<int>(n, -1)};
    vector<int> frontier[2] = {{s}, {t}};
    d[0][s] = 0; d[1][t] = 0;
    while (!frontier[0].empty() && !frontier[1].empty()) {
        int side = frontier[0].size() <= frontier[1].size() ? 0 : 1;   // expand the smaller side
        vector<int> next;
        int best = INT_MAX;
        for (int u : frontier[side])
            for (int v : g[u]) {
                if (d[1 - side][v] >= 0) best = min(best, d[side][u] + 1 + d[1 - side][v]);
                if (d[side][v] < 0) { d[side][v] = d[side][u] + 1; next.push_back(v); }
            }
        if (best != INT_MAX) return best;       // only after the WHOLE layer has been expanded
        frontier[side] = std::move(next);
    }
    return -1;
}
```

```java
static int bidirectionalBfs(int n, int[] start, int[] adj, int s, int t) {
    if (s == t) return 0;
    int[][] d = new int[2][n];
    Arrays.fill(d[0], -1);
    Arrays.fill(d[1], -1);
    int[][] fr = {{s}, {t}};
    int[] frSize = {1, 1};
    d[0][s] = 0; d[1][t] = 0;
    int[] next = new int[n];
    while (frSize[0] > 0 && frSize[1] > 0) {
        int side = frSize[0] <= frSize[1] ? 0 : 1, other = 1 - side, cnt = 0;
        int best = Integer.MAX_VALUE;
        for (int i = 0; i < frSize[side]; i++) {
            int u = fr[side][i];
            for (int e = start[u]; e < start[u + 1]; e++) {
                int v = adj[e];
                if (d[other][v] >= 0) best = Math.min(best, d[side][u] + 1 + d[other][v]);
                if (d[side][v] < 0) { d[side][v] = d[side][u] + 1; next[cnt++] = v; }
            }
        }
        if (best != Integer.MAX_VALUE) return best;
        fr[side] = Arrays.copyOf(next, cnt);
        frSize[side] = cnt;
    }
    return -1;
}
```

## 4. Recognising the pattern

| Signal in the statement | Think |
|---|---|
| "minimum number of moves/steps/operations", every move costs the same | BFS over states |
| grid with `.`/`#`, "count regions", "largest island" | flood fill (iterative DFS/BFS), or DSU |
| "distance to the nearest X" for every cell/vertex | multi-source BFS from all X at once |
| moves of cost 0 and 1 ("free" moves, "pay to break a wall", "turns cost 1") | 0-1 BFS |
| a resource or memory: "at most $k$ walls", "holding keys", "direction", "parity", "time mod $g$" | BFS on (vertex, extra) — check #states fits |
| huge implicit space, known start and target, reversible moves (word ladder, puzzles) | bidirectional BFS |
| "is there a cycle", "detect deadlock", "can the process run forever" | DFS with three colors (directed) / visited + edge id (undirected) |
| "is $u$ an ancestor of $v$", subtree queries | DFS entry/exit times |
| $n \le 2000$ and dense input given as a matrix | adjacency matrix, maybe bitsets |
| $n, m \le 2\cdot10^5$ in Java | CSR arrays, iterative traversal, fast input |

Common confusions: BFS gives shortest paths only when all edges cost the same (otherwise 0-1 BFS or Dijkstra); a "visited"
check at *push* time (BFS) versus at *pop* time (Dijkstra / 0-1 BFS) matters; DFS does **not** give shortest paths.

## 5. Worked examples (graded)

### Example 1 — Counting Rooms  ·  ★ ≈1200

- **Source:** [CSES 1192 · Counting Rooms](https://cses.fi/problemset/task/1192)
- **Difficulty:** ≈1200 (est.)
- **Problem:** An $n \times m$ map ($1 \le n, m \le 1000$) has floor cells `.` and wall cells `#`. A room is a maximal set of
  floor cells connected by side-adjacent moves. Count the rooms.
- **Thinking from first principles:** cells are vertices, side-adjacency between floor cells are edges; rooms are connected
  components. Recursion depth can reach $10^6$ on a serpentine map, so recursion is out (especially in Java). An explicit
  stack (or queue) flood fill visits each cell once. Marking visited cells by overwriting the map saves a second array.

<details><summary>Solution</summary>

For every unvisited floor cell, increment the answer and flood-fill its component with an explicit stack, overwriting
visited cells with `#`. Each cell is pushed at most once: $O(nm)$ time and memory.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<string> g(n);
    for (auto& row : g) cin >> row;
    const int dr[4] = {1, -1, 0, 0}, dc[4] = {0, 0, 1, -1};
    vector<int> st;
    st.reserve(n * m);
    int rooms = 0;
    for (int i = 0; i < n; i++)
        for (int j = 0; j < m; j++) {
            if (g[i][j] != '.') continue;
            rooms++;
            g[i][j] = '#';                       // mark when pushing, so nothing is pushed twice
            st.push_back(i * m + j);
            while (!st.empty()) {
                int id = st.back(); st.pop_back();
                int r = id / m, c = id % m;
                for (int k = 0; k < 4; k++) {
                    int nr = r + dr[k], nc = c + dc[k];
                    if (nr < 0 || nr >= n || nc < 0 || nc >= m || g[nr][nc] != '.') continue;
                    g[nr][nc] = '#';
                    st.push_back(nr * m + nc);
                }
            }
        }
    cout << rooms << "\n";
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
        while (b < '0' || b > '9') b = readByte();
        int r = 0;
        while (b >= '0' && b <= '9') { r = r * 10 + (b - '0'); b = readByte(); }
        return r;
    }
    static String next() throws IOException {
        int b = readByte();
        while (b <= ' ') b = readByte();
        StringBuilder sb = new StringBuilder();
        while (b > ' ') { sb.append((char) b); b = readByte(); }
        return sb.toString();
    }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt();
        char[][] g = new char[n][];
        for (int i = 0; i < n; i++) g[i] = next().toCharArray();
        int[] dr = {1, -1, 0, 0}, dc = {0, 0, 1, -1};
        int[] st = new int[n * m];
        int rooms = 0;
        for (int i = 0; i < n; i++)
            for (int j = 0; j < m; j++) {
                if (g[i][j] != '.') continue;
                rooms++;
                int top = 0;
                g[i][j] = '#';
                st[top++] = i * m + j;
                while (top > 0) {
                    int id = st[--top], r = id / m, c = id % m;
                    for (int k = 0; k < 4; k++) {
                        int nr = r + dr[k], nc = c + dc[k];
                        if (nr < 0 || nr >= n || nc < 0 || nc >= m || g[nr][nc] != '.') continue;
                        g[nr][nc] = '#';
                        st[top++] = nr * m + nc;
                    }
                }
            }
        System.out.println(rooms);
    }
}
```

</details>

<!-- test
in:
4 6
..#...
#.#.##
###...
.#.#..
out:
4
-->
<!-- test
in:
1 1
#
out:
0
-->
<!-- test
in:
3 3
...
...
...
out:
1
-->

### Example 2 — Message Route  ·  ★ ≈1300

- **Source:** [CSES 1667 · Message Route](https://cses.fi/problemset/task/1667)
- **Difficulty:** ≈1300 (est.)
- **Problem:** An undirected network has $n \le 10^5$ computers and $m \le 2\cdot10^5$ cables. Find a route from computer 1
  to computer $n$ that uses the fewest computers; print the number of computers on it and the route itself, or
  `IMPOSSIBLE`.
- **Thinking from first principles:** "fewest computers" = fewest edges + 1, all edges equal → BFS. To output the route we
  need, for each vertex, the vertex it was discovered from (`par`). Following `par` from $n$ back to 1 walks the BFS tree
  backwards, and every prefix of a BFS-tree path is itself shortest, so the restored route is a shortest one. (When several
  shortest routes exist any is accepted; the tests below have a unique one.)

<details><summary>Solution</summary>

BFS from vertex 1 storing `par`; if `dist[n]` is unset print `IMPOSSIBLE`, else walk `par` back from $n$ and reverse.
$O(n+m)$.

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
    vector<int> par(n + 1, 0), q = {1};
    vector<char> seen(n + 1, 0);
    seen[1] = 1;
    for (size_t h = 0; h < q.size(); h++) {
        int u = q[h];
        for (int v : g[u]) if (!seen[v]) { seen[v] = 1; par[v] = u; q.push_back(v); }
    }
    if (!seen[n]) { cout << "IMPOSSIBLE\n"; return 0; }
    vector<int> path;
    for (int v = n; v != 0; v = par[v]) path.push_back(v);   // par[1] = 0 stops the walk
    reverse(path.begin(), path.end());
    cout << path.size() << "\n";
    for (size_t i = 0; i < path.size(); i++) cout << path[i] << " \n"[i + 1 == path.size()];
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
        for (int i = 0; i < m; i++) {
            eu[i] = nextInt(); ev[i] = nextInt();
            start[eu[i] + 1]++; start[ev[i] + 1]++;
        }
        for (int i = 0; i <= n; i++) start[i + 1] += start[i];
        int[] adj = new int[2 * m], pos = Arrays.copyOf(start, n + 1);
        for (int i = 0; i < m; i++) { adj[pos[eu[i]]++] = ev[i]; adj[pos[ev[i]]++] = eu[i]; }
        int[] par = new int[n + 1], q = new int[n];
        boolean[] seen = new boolean[n + 1];
        int head = 0, tail = 0;
        q[tail++] = 1; seen[1] = true;
        while (head < tail) {
            int u = q[head++];
            for (int e = start[u]; e < start[u + 1]; e++) {
                int v = adj[e];
                if (!seen[v]) { seen[v] = true; par[v] = u; q[tail++] = v; }
            }
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        if (!seen[n]) { out.println("IMPOSSIBLE"); out.flush(); return; }
        int len = 0;
        for (int v = n; v != 0; v = par[v]) len++;
        int[] path = new int[len];
        for (int v = n, i = len - 1; v != 0; v = par[v]) path[i--] = v;
        out.println(len);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < len; i++) sb.append(path[i]).append(i + 1 == len ? '\n' : ' ');
        out.print(sb);
        out.flush();
    }
}
```

</details>

<!-- test
in:
6 7
1 2
2 3
3 6
1 4
4 5
5 3
2 5
out:
4
1 2 3 6
-->
<!-- test
in:
4 2
1 2
3 4
out:
IMPOSSIBLE
-->
<!-- test
in:
2 1
2 1
out:
2
1 2
-->

### Example 3 — Labyrinth with limited left/right moves  ·  ★ 1800

- **Source:** [CF 1063B · Labyrinth](https://codeforces.com/problemset/problem/1063/B) — 1800
- **Difficulty:** 1800
- **Problem:** An $n\times m$ maze ($n, m \le 2000$) of free `.` and blocked `*` cells; you start at $(r,c)$ and may move up
  and down freely, but make at most $x$ moves to the left and at most $y$ moves to the right in total
  ($0 \le x, y \le 10^9$). Count the cells you can reach.
- **Thinking from first principles:** the naive state $(\text{cell}, \text{lefts}, \text{rights})$ is far too big. Key
  observation: for any walk ending in column $j$, $\text{rights} - \text{lefts} = j - c$ is fixed. So both counters are
  minimized together: minimizing lefts alone suffices, and a cell is reachable iff
  $L_{\min} \le x$ and $L_{\min} + (j - c) \le y$. "Minimize the number of left moves" is a shortest path where a left move
  costs 1 and every other move costs 0 → **0-1 BFS**. A plain BFS by number of steps is wrong here: the walk with the fewest
  steps may waste left moves (that's the trap many solvers fall into; the last hidden test below is a $5	imes6$ maze where
  "BFS by steps, record the counters at first visit" reports 18 cells instead of 19).

<details><summary>Solution</summary>

0-1 BFS from the start with weight 1 on left moves and 0 on up/down/right moves; `L[cell]` = minimum number of left moves.
Count cells with `L ≤ x` and `L + (j − c) ≤ y`. Proof: any walk to the cell uses at least `L` lefts and exactly
`lefts + (j − c)` rights, so the minimal-left walk is the best for both limits simultaneously. $O(nm)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m, r, c;
    long long x, y;
    cin >> n >> m >> r >> c >> x >> y;
    --r; --c;
    vector<string> g(n);
    for (auto& row : g) cin >> row;
    const int INF = INT_MAX;
    const int di[4] = {-1, 1, 0, 0}, dj[4] = {0, 0, -1, 1}, w[4] = {0, 0, 1, 0};   // left costs 1
    vector<int> L(n * m, INF);
    deque<int> dq;
    L[r * m + c] = 0;
    dq.push_back(r * m + c);
    while (!dq.empty()) {
        int id = dq.front(); dq.pop_front();
        int i = id / m, j = id % m;
        for (int k = 0; k < 4; k++) {
            int ni = i + di[k], nj = j + dj[k];
            if (ni < 0 || ni >= n || nj < 0 || nj >= m || g[ni][nj] == '*') continue;
            int nid = ni * m + nj;
            if (L[id] + w[k] < L[nid]) {
                L[nid] = L[id] + w[k];
                if (w[k] == 0) dq.push_front(nid); else dq.push_back(nid);
            }
        }
    }
    long long cnt = 0;
    for (int i = 0; i < n; i++)
        for (int j = 0; j < m; j++) {
            int id = i * m + j;
            if (L[id] == INF) continue;
            long long left = L[id], right = left + (j - c);
            if (left <= x && right <= y) cnt++;
        }
    cout << cnt << "\n";
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
    static String next() throws IOException {
        int b = in.read();
        while (b <= ' ') b = in.read();
        StringBuilder sb = new StringBuilder();
        while (b > ' ') { sb.append((char) b); b = in.read(); }
        return sb.toString();
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nextLong(), m = (int) nextLong(), r = (int) nextLong() - 1, c = (int) nextLong() - 1;
        long x = nextLong(), y = nextLong();
        char[][] g = new char[n][];
        for (int i = 0; i < n; i++) g[i] = next().toCharArray();
        int N = n * m, cap = 2 * N + 1;
        int[] L = new int[N];
        Arrays.fill(L, Integer.MAX_VALUE);
        int[] dq = new int[cap];
        int head = 0, size = 0;
        int[] di = {-1, 1, 0, 0}, dj = {0, 0, -1, 1}, w = {0, 0, 1, 0};
        L[r * m + c] = 0;
        dq[0] = r * m + c; size = 1;
        while (size > 0) {
            int id = dq[head]; head = (head + 1) % cap; size--;
            int i = id / m, j = id % m;
            for (int k = 0; k < 4; k++) {
                int ni = i + di[k], nj = j + dj[k];
                if (ni < 0 || ni >= n || nj < 0 || nj >= m || g[ni][nj] == '*') continue;
                int nid = ni * m + nj, nd = L[id] + w[k];
                if (nd < L[nid]) {
                    L[nid] = nd;
                    if (w[k] == 0) { head = (head - 1 + cap) % cap; dq[head] = nid; }
                    else dq[(head + size) % cap] = nid;
                    size++;
                }
            }
        }
        long cnt = 0;
        for (int i = 0; i < n; i++)
            for (int j = 0; j < m; j++) {
                int id = i * m + j;
                if (L[id] == Integer.MAX_VALUE) continue;
                long left = L[id], right = left + (j - c);
                if (left <= x && right <= y) cnt++;
            }
        System.out.println(cnt);
    }
}
```

</details>

<!-- test
in:
3 4
2 2
1 1
....
..*.
....
out:
8
-->
<!-- test
in:
1 1
1 1
0 0
.
out:
1
-->
<!-- test
in:
4 5
3 2
1 2
.....
.***.
...*.
***..
out:
7
-->
<!-- test
in:
3 5
1 5
0 3
.....
.*.*.
.....
out:
3
-->
<!-- test
in:
5 6
3 3
1 3
....*.
.....*
...*..
..*..*
......
out:
19
-->

### Example 4 — Shortest path with at most K wall breaks  ·  ★ ≈1700

- **Source:** Original problem (same idea as [LC 1293 · Shortest Path in a Grid with Obstacles Elimination](https://leetcode.com/problems/shortest-path-in-a-grid-with-obstacles-elimination/) — Hard).
- **Difficulty:** ≈1700 (est.)
- **Problem:** An $R\times C$ grid ($R\cdot C\cdot(K+1) \le 2\cdot 10^6$) of `.` and `#`. Walk from the top-left to the
  bottom-right cell (both `.`) with side moves; stepping onto a `#` cell breaks it and uses one of your $K$ breaks. Print the
  minimum number of steps, or $-1$.
- **Thinking from first principles:** the cell alone is not a valid state: reaching a cell with fewer breaks used is
  strictly better for the future, so two walks reaching the same cell are not interchangeable. Add the number of breaks
  used: state $(r, c, k)$, at most $R\cdot C\cdot(K+1)$ of them, every move costs one step → plain BFS. (Dead end: Dijkstra on
  "breaks used" minimizes the wrong quantity; 0-1 BFS on breaks answers a different question.) Side fact worth noticing: a
  monotone path has $R+C-3$ intermediate cells, so if $K \ge R+C-3$ the answer is just $R+C-2$.

<details><summary>Solution</summary>

BFS over $(r, c, k)$ with id $((r\cdot C + c)(K+1) + k)$. Moving onto `#` goes from $k$ to $k+1$ (only if $k < K$). The
first time any state of the target cell is popped, its distance is the answer (BFS pops in non-decreasing distance).
$O(RC(K+1))$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int R, C, K;
    cin >> R >> C >> K;
    vector<string> g(R);
    for (auto& row : g) cin >> row;
    int S = R * C * (K + 1);
    vector<int> dist(S, -1), q(S);
    int head = 0, tail = 0;
    dist[0] = 0;                         // state (0, 0, 0)
    q[tail++] = 0;
    const int dr[4] = {1, -1, 0, 0}, dc[4] = {0, 0, 1, -1};
    while (head < tail) {
        int s = q[head++];
        int k = s % (K + 1), cell = s / (K + 1), r = cell / C, c = cell % C;
        if (r == R - 1 && c == C - 1) { cout << dist[s] << "\n"; return 0; }
        for (int d = 0; d < 4; d++) {
            int nr = r + dr[d], nc = c + dc[d];
            if (nr < 0 || nr >= R || nc < 0 || nc >= C) continue;
            int nk = k + (g[nr][nc] == '#');
            if (nk > K) continue;
            int ns = (nr * C + nc) * (K + 1) + nk;
            if (dist[ns] < 0) { dist[ns] = dist[s] + 1; q[tail++] = ns; }
        }
    }
    cout << -1 << "\n";
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
    static String next() throws IOException {
        int b = in.read();
        while (b <= ' ') b = in.read();
        StringBuilder sb = new StringBuilder();
        while (b > ' ') { sb.append((char) b); b = in.read(); }
        return sb.toString();
    }

    public static void main(String[] args) throws IOException {
        int R = nextInt(), C = nextInt(), K = nextInt();
        char[][] g = new char[R][];
        for (int i = 0; i < R; i++) g[i] = next().toCharArray();
        int S = R * C * (K + 1);
        int[] dist = new int[S], q = new int[S];
        Arrays.fill(dist, -1);
        int head = 0, tail = 0;
        dist[0] = 0;
        q[tail++] = 0;
        int[] dr = {1, -1, 0, 0}, dc = {0, 0, 1, -1};
        while (head < tail) {
            int s = q[head++];
            int k = s % (K + 1), cell = s / (K + 1), r = cell / C, c = cell % C;
            if (r == R - 1 && c == C - 1) { System.out.println(dist[s]); return; }
            for (int d = 0; d < 4; d++) {
                int nr = r + dr[d], nc = c + dc[d];
                if (nr < 0 || nr >= R || nc < 0 || nc >= C) continue;
                int nk = k + (g[nr][nc] == '#' ? 1 : 0);
                if (nk > K) continue;
                int ns = (nr * C + nc) * (K + 1) + nk;
                if (dist[ns] < 0) { dist[ns] = dist[s] + 1; q[tail++] = ns; }
            }
        }
        System.out.println(-1);
    }
}
```

</details>

<!-- test
in:
5 3 1
...
##.
...
.##
...
out:
6
-->
<!-- test
in:
5 3 0
...
##.
...
.##
...
out:
10
-->
<!-- test
in:
3 3 0
.#.
##.
.#.
out:
-1
-->
<!-- test
in:
1 1 0
.
out:
0
-->

### Example 5 — Round Trip II (directed cycle)  ·  ★ ≈1600

- **Source:** [CSES 1678 · Round Trip II](https://cses.fi/problemset/task/1678)
- **Difficulty:** ≈1600 (est.)
- **Problem:** A directed graph with $n \le 10^5$ vertices and $m \le 2\cdot10^5$ edges. Find any directed cycle: print the
  number of vertices on the route (the start is counted twice) and the route, or `IMPOSSIBLE`. Any cycle is accepted; to make
  the output deterministic, we rotate the found cycle so it starts at its smallest vertex (still a valid answer).
- **Thinking from first principles:** "visited before" is not enough in a directed graph — a vertex reached twice through a
  diamond $1\to2\to4$, $1\to3\to4$ is no cycle. The three-color argument of §1 says: a cycle exists iff DFS meets a **gray**
  vertex, and then the gray vertex $v$ and the current vertex $u$ are joined by the tree path $v \leadsto u$ plus the edge
  $u\to v$. Recursion depth can be $10^5$, so use the iterative DFS of §3.4.

<details><summary>Solution</summary>

Iterative three-color DFS from every white vertex. On a back edge $u\to v$, collect $u, \text{par}[u], \dots, v$, reverse
to get $v \to \dots \to u$, rotate to the minimum, print it with the first vertex repeated. If no back edge exists, the
graph is acyclic. $O(n+m)$.

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
    }
    vector<int> color(n + 1, 0), par(n + 1, 0), it(n + 1, 0), st;
    for (int s = 1; s <= n; s++) {
        if (color[s]) continue;
        color[s] = 1; st.push_back(s);
        while (!st.empty()) {
            int u = st.back();
            if (it[u] == (int)g[u].size()) { color[u] = 2; st.pop_back(); continue; }
            int v = g[u][it[u]++];
            if (color[v] == 0) { color[v] = 1; par[v] = u; st.push_back(v); }
            else if (color[v] == 1) {                       // back edge u -> v closes a cycle
                vector<int> cyc;
                for (int x = u; x != v; x = par[x]) cyc.push_back(x);
                cyc.push_back(v);
                reverse(cyc.begin(), cyc.end());            // v ... u
                rotate(cyc.begin(), min_element(cyc.begin(), cyc.end()), cyc.end());
                cout << cyc.size() + 1 << "\n";
                for (int x : cyc) cout << x << ' ';
                cout << cyc[0] << "\n";
                return 0;
            }
        }
    }
    cout << "IMPOSSIBLE\n";
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
        for (int i = 0; i < m; i++) { eu[i] = nextInt(); ev[i] = nextInt(); start[eu[i] + 1]++; }
        for (int i = 0; i <= n; i++) start[i + 1] += start[i];
        int[] adj = new int[m], pos = Arrays.copyOf(start, n + 1);
        for (int i = 0; i < m; i++) adj[pos[eu[i]]++] = ev[i];     // keeps input order per vertex
        int[] color = new int[n + 1], par = new int[n + 1], it = new int[n + 1], st = new int[n + 1];
        for (int s = 1; s <= n; s++) {
            if (color[s] != 0) continue;
            int top = 0;
            color[s] = 1; it[s] = start[s]; st[top++] = s;
            while (top > 0) {
                int u = st[top - 1];
                if (it[u] == start[u + 1]) { color[u] = 2; top--; continue; }
                int v = adj[it[u]++];
                if (color[v] == 0) { color[v] = 1; par[v] = u; it[v] = start[v]; st[top++] = v; }
                else if (color[v] == 1) {
                    ArrayList<Integer> cyc = new ArrayList<>();
                    for (int x = u; x != v; x = par[x]) cyc.add(x);
                    cyc.add(v);
                    Collections.reverse(cyc);
                    int mi = 0;
                    for (int i = 1; i < cyc.size(); i++) if (cyc.get(i) < cyc.get(mi)) mi = i;
                    Collections.rotate(cyc, -mi);
                    StringBuilder sb = new StringBuilder();
                    sb.append(cyc.size() + 1).append('\n');
                    for (int x : cyc) sb.append(x).append(' ');
                    sb.append(cyc.get(0)).append('\n');
                    System.out.print(sb);
                    return;
                }
            }
        }
        System.out.println("IMPOSSIBLE");
    }
}
```

</details>

<!-- test
in:
4 4
1 2
2 3
3 4
4 2
out:
4
2 3 4 2
-->
<!-- test
in:
3 3
1 2
2 3
1 3
out:
IMPOSSIBLE
-->
<!-- test
in:
5 5
1 2
2 5
5 3
3 4
4 5
out:
4
3 4 5 3
-->
<!-- test
in:
4 4
1 2
1 3
2 4
3 4
out:
IMPOSSIBLE
-->

## 6. Tricks, pitfalls and things to remember

1. **Mark visited when pushing in BFS, not when popping.** Marking at pop time lets a vertex enter the queue many times
   (up to $\deg$ times): still correct distances, but $O(m)$ queue entries become $O(m)$ *per vertex* on dense graphs → TLE/MLE.
2. **0-1 BFS / Dijkstra are the opposite:** a vertex's distance is final only when it is *popped*; never skip relaxations
   because a vertex was "seen".
3. **Recursion depth.** A path graph with $10^5$–$10^6$ vertices kills recursive DFS: Java's default stack, and C++ on Windows
   (1 MB). Use the iterator-stack DFS of §3.4, or in Java run `solve()` in `new Thread(null, r, "", 1 << 28)`. Codeforces
   gives C++ 256 MB of stack, so recursive C++ is usually fine *there*, but not in your local tests.
4. **Three colors for directed cycles.** Two colors (visited / not) report false cycles on diamonds; in undirected graphs,
   skip the *edge id* you came through, not the parent vertex, or parallel edges $u$–$v$ (a genuine 2-cycle) are missed.
5. **Grid bounds and ids.** Use `id = r * C + c` with `C` = number of **columns**; mixing $R$ and $C$ silently works on square
   tests and fails on rectangles. Check bounds before indexing the grid.
6. **State-space size.** Before writing BFS on states, multiply: $2000\times2000\times 11 = 4.4\cdot10^7$ ints = 176 MB → MLE.
   Shrink the state (Example 3's observation removed two dimensions), or store `dist` as `short`/`char` when the values are
   small.
7. **`vector<vector<int>>` for $10^6$ vertices** costs ~24 bytes per inner vector plus heap overhead; prefer CSR. In Java,
   `ArrayList<Integer>[]` boxes every neighbor (16+ bytes each) — use `int[]` CSR or forward star.
8. **Multi-source BFS initialization:** set all sources to distance 0 *before* the loop. Pushing them one at a time while the
   loop runs breaks the layer invariant.
9. **Bidirectional BFS termination:** finish the whole layer before returning (see §1); returning at the first meeting
   vertex without taking the minimum over the layer gives off-by-one answers.
10. **Disconnected graphs.** "For every vertex" questions need the outer loop over all start vertices (components, cycles,
    topological order). Forgetting it passes samples (usually connected) and fails hidden tests.
11. **Java I/O.** Grids of $4\cdot10^6$ characters: read with a byte-buffer reader (`DataInputStream`), never `Scanner`;
    output with one `StringBuilder`/`PrintWriter`.
12. **Undirected edge arrays are twice as long** (`2m` slots). Allocating `m` is a classic out-of-bounds in CSR code.

## 7. Going further (toward 2400–2600+)

- **BFS with "skip already-visited ranges"**: when each vertex connects to an interval of others (jump games, CF 1601B
  Frog Traveler), keep unvisited vertices in a DSU "next pointer" or ordered set so that each vertex is visited once:
  total $O(n\,\alpha(n))$ instead of $O(n^2)$ edges. The same idea gives BFS on the **complement graph** in $O(n+m)$ — see
  [functional and special graphs](10-functional-graphs-and-special-graphs.md).
- **BFS on rows/columns as vertices** (CF 173B): connect each `#` cell's row node to its column node; one BFS layer = one
  "reflection". Turning objects into vertices and relations into edges, rather than cells into vertices, is a recurring
  2000+ trick.
- **State BFS with time modulo $g$** (CF 1340C Nastya and Unexpected Guest) mixes 0-1 BFS with a large but structured state
  space; the bound $\#\text{islands}\times g$ is what makes it feasible.
- **Shortest-path DAG reasoning:** "which edges lie on some shortest path", "number of shortest paths", "lexicographically
  smallest shortest path" (BFS by layers, choosing the smallest label per layer, CF 1209F style) all come from
  $\operatorname{dist}(v) = \operatorname{dist}(u) + 1$. See [shortest paths](02-shortest-paths.md) for the weighted versions.
- **DFS trees as a proof tool:** low-link ([bridges/BCC](06-bridges-articulation-points-and-bcc.md)), SCC
  ([Tarjan](05-scc-and-condensation.md)), and many constructive problems (CF 1325F Ehab's Last Theorem: a DFS tree either
  has a long back edge — a long cycle — or is "shallow" enough to yield a large independent set) use only the fact that
  undirected DFS trees have no cross edges.

## 8. Practice ladder

**≤ 1400**
- [ ] [CSES 1192 · Counting Rooms](https://cses.fi/problemset/task/1192) — flood fill
- [ ] [CSES 1666 · Building Roads](https://cses.fi/problemset/task/1666) — components, join them
- [ ] [CSES 1667 · Message Route](https://cses.fi/problemset/task/1667) — BFS + path
- [ ] [CSES 1193 · Labyrinth](https://cses.fi/problemset/task/1193) — grid BFS, print the moves
- [ ] [CF 115A · Party](https://codeforces.com/problemset/problem/115/A) — 900
- [ ] [CF 500A · New Year Transportation](https://codeforces.com/problemset/problem/500/A) — 1000
- [ ] [CF 1829E · The Lakes](https://codeforces.com/problemset/problem/1829/E) — 1100
- [ ] [CF 893C · Rumor](https://codeforces.com/problemset/problem/893/C) — 1300
- [ ] [CF 520B · Two Buttons](https://codeforces.com/problemset/problem/520/B) — 1400
- [ ] [CF 1167C · News Distribution](https://codeforces.com/problemset/problem/1167/C) — 1400

**1400–1700**
- [ ] [CF 580C · Kefa and Park](https://codeforces.com/problemset/problem/580/C) — 1500
- [ ] [CF 977E · Cyclic Components](https://codeforces.com/problemset/problem/977/E) — 1500
- [ ] [CSES 1194 · Monsters](https://cses.fi/problemset/task/1194) — multi-source BFS race
- [ ] [CSES 1678 · Round Trip II](https://cses.fi/problemset/task/1678) — three colors
- [ ] [AtCoder ABC151 D · Maze Master](https://atcoder.jp/contests/abc151/tasks/abc151_d) — BFS from every cell
- [ ] [AtCoder ABC277 E · Crystal Switches](https://atcoder.jp/contests/abc277/tasks/abc277_e) — BFS on (vertex, switch parity)
- [ ] [AtCoder ABC176 D · Wizard in Maze](https://atcoder.jp/contests/abc176/tasks/abc176_d) — 0-1 BFS
- [ ] [AtCoder ABC213 E · Stronger Takahashi](https://atcoder.jp/contests/abc213/tasks/abc213_e) — 0-1 BFS with area moves
- [ ] [CF 1037D · Valid BFS?](https://codeforces.com/problemset/problem/1037/D) — 1700
- [ ] [CF 598D · Igor In the Museum](https://codeforces.com/problemset/problem/598/D) — 1700
- [ ] [CF 1365D · Solve The Maze](https://codeforces.com/problemset/problem/1365/D) — 1700
- [ ] [CF 1176E · Cover it!](https://codeforces.com/problemset/problem/1176/E) — 1700

**1700–2100**
- [ ] [AtCoder ABC246 E · Bishop 2](https://atcoder.jp/contests/abc246/tasks/abc246_e) — BFS on (cell, direction)
- [ ] [CF 1063B · Labyrinth](https://codeforces.com/problemset/problem/1063/B) — 1800
- [ ] [CF 173B · Chamber of Secrets](https://codeforces.com/problemset/problem/173/B) — 1800
- [ ] [CF 242C · King's Path](https://codeforces.com/problemset/problem/242/C) — 1800
- [ ] [CF 1272E · Nearest Opposite Parity](https://codeforces.com/problemset/problem/1272/E) — 1900
- [ ] [CF 1601B · Frog Traveler](https://codeforces.com/problemset/problem/1601/B) — 1900
- [ ] [CF 59E · Shortest Path](https://codeforces.com/problemset/problem/59/E) — 2000

**2100+**
- [ ] [CF 1520G · To Go Or Not To Go?](https://codeforces.com/problemset/problem/1520/G) — 2200
- [ ] [CF 1340C · Nastya and Unexpected Guest](https://codeforces.com/problemset/problem/1340/C) — 2400
- [ ] [CF 1325F · Ehab's Last Theorem](https://codeforces.com/problemset/problem/1325/F) — 2500

## 9. LeetCode / FAANG cross-reference

BFS/DFS is the single most common interview graph topic. Expect grids, implicit state spaces and "clone/copy" questions.

- [LC 200 · Number of Islands](https://leetcode.com/problems/number-of-islands/) — Medium — flood fill / components.
- [LC 695 · Max Area of Island](https://leetcode.com/problems/max-area-of-island/) — Medium — component sizes.
- [LC 133 · Clone Graph](https://leetcode.com/problems/clone-graph/) — Medium — traversal with an old→new map.
- [LC 994 · Rotting Oranges](https://leetcode.com/problems/rotting-oranges/) — Medium — multi-source BFS, answer = last layer.
- [LC 542 · 01 Matrix](https://leetcode.com/problems/01-matrix/) — Medium — multi-source BFS from all zeros.
- [LC 1162 · As Far from Land as Possible](https://leetcode.com/problems/as-far-from-land-as-possible/) — Medium — multi-source BFS.
- [LC 417 · Pacific Atlantic Water Flow](https://leetcode.com/problems/pacific-atlantic-water-flow/) — Medium — reverse BFS from both borders.
- [LC 130 · Surrounded Regions](https://leetcode.com/problems/surrounded-regions/) — Medium — flood from the border.
- [LC 1091 · Shortest Path in Binary Matrix](https://leetcode.com/problems/shortest-path-in-binary-matrix/) — Medium — 8-direction BFS.
- [LC 752 · Open the Lock](https://leetcode.com/problems/open-the-lock/) — Medium — BFS on 10^4 states, bidirectional optional.
- [LC 127 · Word Ladder](https://leetcode.com/problems/word-ladder/) — Hard — implicit graph; wildcard buckets; bidirectional BFS.
- [LC 1293 · Shortest Path in a Grid with Obstacles Elimination](https://leetcode.com/problems/shortest-path-in-a-grid-with-obstacles-elimination/) — Hard — Example 4.
- [LC 864 · Shortest Path to Get All Keys](https://leetcode.com/problems/shortest-path-to-get-all-keys/) — Hard — BFS on (cell, key mask).
- [LC 847 · Shortest Path Visiting All Nodes](https://leetcode.com/problems/shortest-path-visiting-all-nodes/) — Hard — multi-source BFS on (node, mask).
- [LC 1129 · Shortest Path with Alternating Colors](https://leetcode.com/problems/shortest-path-with-alternating-colors/) — Medium — state = (node, last color).
- [LC 1368 · Minimum Cost to Make at Least One Valid Path in a Grid](https://leetcode.com/problems/minimum-cost-to-make-at-least-one-valid-path-in-a-grid/) — Hard — 0-1 BFS.
- [LC 2290 · Minimum Obstacle Removal to Reach Corner](https://leetcode.com/problems/minimum-obstacle-removal-to-reach-corner/) — Hard — 0-1 BFS.
- [LC 1345 · Jump Game IV](https://leetcode.com/problems/jump-game-iv/) — Hard — BFS; clear each value bucket after first use.
- [LC 815 · Bus Routes](https://leetcode.com/problems/bus-routes/) — Hard — BFS over routes (objects as vertices).
- [LC 841 · Keys and Rooms](https://leetcode.com/problems/keys-and-rooms/) — Medium — reachability.

See also the interview-oriented treatment in [FAANG graphs](../17-FAANG-Interview-DSA/11-graphs.md).

## 10. Self-check

1. Prove that the BFS queue never contains vertices from more than two consecutive layers.
2. Why is a vertex pushed at most twice in 0-1 BFS, and why must "final" be decided at pop time?
3. In a directed graph, DFS from vertex 1 reaches an already-visited vertex. Give a graph where this is *not* a cycle, and
   state the exact color condition that detects a cycle.
4. Why does an undirected DFS tree have no cross edges? Which algorithm in this folder relies on that?
5. You need distances from every cell to the nearest exit on a $1000\times1000$ grid. How many BFS runs?
6. In CF 1063B, why is BFS by number of steps wrong, and why is minimizing left moves enough?
7. When exactly may bidirectional BFS stop, and what does it return?
8. What breaks if you build CSR with an array of size $m$ for an undirected graph?

<details><summary>Answers</summary>

1. Popping a layer-$k$ vertex only pushes layer-$(k+1)$ vertices; by induction the queue is "rest of $L_k$, then part of
   $L_{k+1}$", so at most two layers and their distances are non-decreasing.
2. A vertex first gets tentative value $D$ or $D+1$ where $D$ is the (non-decreasing) popped value; later relaxations give
   $\ge D$, so it can improve once (from $D+1$ to $D$). A 0-edge found later can still lower a seen-but-unpopped vertex, so
   finality is only known when popped.
3. Diamond $1\to2\to4$, $1\to3\to4$: vertex 4 is reached twice, no cycle. A cycle exists iff DFS meets a **gray** vertex
   (on the current stack).
4. If $u$ is entered before $v$ and $\{u,v\}$ is an edge, $v$ is white and reachable from $u$ when $u$ is entered, hence a
   descendant (white-path theorem): every non-tree edge goes to an ancestor. Low-link (bridges, articulation points, BCC)
   relies on it.
5. One: multi-source BFS starting from all exits at distance 0.
6. The fewest-steps walk can spend extra left moves that a longer walk avoids. Since rights − lefts is fixed by the column,
   minimizing lefts minimizes both counters at once.
7. After fully expanding one layer, if any edge touched a vertex seen by the other side; return the minimum
   $d_S(u)+1+d_T(v)$ over those edges (it equals $a+1+b$).
8. Each undirected edge is stored twice, so the array needs $2m$ slots; with $m$ you write out of bounds (C++ UB, Java
   `ArrayIndexOutOfBoundsException`).

</details>
