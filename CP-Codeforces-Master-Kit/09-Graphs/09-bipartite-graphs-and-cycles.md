# Bipartite Graphs and Cycles

> **Band:** 🟢 1300 → 🟠 2300 · **Priority:** 🔥 (2-coloring, odd cycles, girth) · ⚡ (XOR cycle basis) · **FAANG:** high · **Prerequisites:** [BFS/DFS](01-graph-representation-bfs-dfs.md), [shortest paths](02-shortest-paths.md) (negative cycles)
> **You can say you know this when:** you can 2-color a graph with BFS and, on failure, print an odd cycle; prove "bipartite ⟺ no odd cycle"; compute the girth exactly in $O(nm)$ and explain why the per-source BFS value is only an upper bound; and reduce "XOR of a walk" questions to a linear basis of fundamental cycles.

## 1. First principles — why this works

**Bipartite = two-colorable.** A graph is bipartite if its vertices split into two sides with every edge crossing. Equivalently,
it can be properly colored with two colors. The natural algorithm: color a start vertex $0$, force every neighbor to $1$, every
neighbor of those to $0$, and so on — BFS (or DFS) propagation. In a connected component the coloring is forced up to swapping
the two colors, so if propagation ever meets an edge with equal colors, *no* 2-coloring exists.

**Theorem (König, 1936): bipartite ⟺ no odd cycle.**
- (⇒) Along any cycle the colors alternate, so the cycle returns to its start color only after an even number of steps.
- (⇐) Run BFS from $s$ and color by distance parity, $c(v) = d(v) \bmod 2$. Every edge $u$–$v$ satisfies $|d(u) - d(v)| \le 1$.
  If some edge has $d(u) = d(v)$, follow BFS parents from $u$ and from $v$ up to their lowest common ancestor $\ell$: the two tree paths
  have equal length $d(u) - d(\ell)$, and together with the edge they form a cycle of length $2(d(u)-d(\ell)) + 1$ — odd, and simple
  because the two paths only meet at $\ell$. So if there is no odd cycle, no edge joins equal distances and parity is a proper coloring.

The proof *is* the odd-cycle extraction algorithm: on the first conflicting edge, climb parents from both endpoints in lockstep
(they have equal depth) until they meet.

**Cycles in general.** In an undirected graph, a DFS/BFS tree plus any non-tree edge $u$–$v$ creates exactly one cycle (the
*fundamental cycle*): tree path $u \leadsto v$ plus the edge. Hence a graph has a cycle iff $m > n - c$ ($c$ = number of components),
and the fundamental cycles of the $m - n + c$ non-tree edges form a **basis of the cycle space** over $\mathbb{F}_2$: every Eulerian
subgraph (every cycle in particular) is the XOR (symmetric difference) of the fundamental cycles of the non-tree edges it uses.

**Girth (shortest cycle) from first principles.** Run BFS from a source $s$. For a non-tree edge $u$–$v$, the closed walk
$s \leadsto u \to v \leadsto s$ has length $d(u) + d(v) + 1$ and contains the fundamental cycle of $u$–$v$, so
$$g \le \min_{\text{non-tree } uv} \big(d_s(u) + d_s(v) + 1\big) =: g_s .$$
**Exactness at a vertex of a shortest cycle.** Let $C$ be a shortest cycle (length $g$) through $s$. A tree is acyclic, so some edge
$u$–$v$ of $C$ is a non-tree edge. Removing that edge from $C$ leaves two disjoint arcs from $s$ to $u$ and from $s$ to $v$ of total
length $g - 1$, hence $d_s(u) + d_s(v) + 1 \le g$. Therefore $g = \min_s g_s$: BFS from **every** vertex, $O(n \cdot m)$.

**The caveats.** (1) $g_s$ is *not* "the shortest cycle through $s$": the two BFS paths may share a prefix, and then the real
cycle avoids $s$ (it is shorter, which is fine for the global minimum but wrong if a problem asks per vertex). (2) The $\pm 1$
caveat. While BFS processes a vertex $u$ of layer $d$, a non-tree edge to $v$ gives $d(u)+d(v)+1$ with $d(v) \in \{d, d+1\}$, i.e.
an odd candidate $2d+1$ (same layer) or an even one $2d+2$ ($v$ already discovered in the next layer). Edges to layer $d-1$ were already
reported from the other endpoint (when that endpoint was processed, $u$ was already discovered by its own parent). So the *first*
candidate a BFS meets may be $2d+2$ while a later vertex of the same layer yields $2d+1$: stopping at the first non-tree edge can
overshoot $g_s$ by one. Safe rule: once a candidate is found, finish the layer — the code below stops a source only when
$2d(u) + 1 \ge$ best, which loses nothing.

**Odd/even walks.** "Is there a walk of odd length from $a$ to $b$?" — build the *bipartite double cover*: states $(v, p)$ with
$p$ = parity of the walk so far; edge $u$–$v$ connects $(u,p)$ with $(v, 1-p)$. BFS over $2n$ states. A connected component is
non-bipartite iff $(v,0)$ and $(v,1)$ are connected. The same layered-state trick handles "length $\equiv r \pmod k$".

**XOR of walks.** If a walk's cost is the XOR of its edge weights and edges may be reused, then traversing any cycle and coming back
adds exactly that cycle's XOR (the connecting path is used twice and cancels). So the set of achievable values from $1$ to $n$ is
$d(n) \oplus \text{span}\{\text{XOR of fundamental cycles}\}$ where $d$ is the XOR distance along a spanning tree. Minimising or
maximising over a span is a linear-basis problem ([XOR basis](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md)).

**Negative cycles** are a weighted-directed story — Bellman–Ford/SPFA detection lives in [shortest paths](02-shortest-paths.md).

## 2. Formulas, definitions and identities

| Fact | Why / use |
|---|---|
| bipartite ⟺ no odd cycle ⟺ 2-colorable | BFS parity proof above |
| #proper 2-colorings $= 2^{c}$ if bipartite, else $0$ | each component's coloring is forced up to a swap |
| bipartite with sides $a, b$: $m \le ab \le \lfloor n^2/4 \rfloor$ | complete bipartite $K_{a,b}$ |
| Mantel: triangle-free ⇒ $m \le \lfloor n^2/4 \rfloor$ | extremal graph is $K_{\lceil n/2\rceil,\lfloor n/2\rfloor}$ |
| trees are bipartite; a tree with sides $a, b$ can take $ab - (n-1)$ more edges and stay bipartite | CF 862B |
| cycle exists in an undirected graph ⟺ $m > n - c$ | spanning forest has $n - c$ edges |
| cycle space dimension $= m - n + c$; #Eulerian subgraphs $= 2^{m-n+c}$ | fundamental cycles form a basis over $\mathbb{F}_2$ |
| odd closed walk ⇒ odd simple cycle | split the walk at a repeated vertex; one part is odd |
| girth $g = \min_s \min_{\text{non-tree } uv} (d_s(u) + d_s(v) + 1)$ | exact; $O(nm)$ |
| girth $\ge 5$ ⇒ $m = O(n^{3/2})$; girth $\ge 2k+1$ ⇒ $m = O(n^{1+1/k})$ | Moore bound (why "dense" graphs have short cycles) |
| König: in bipartite graphs, max matching = min vertex cover | [matching theorems](../12-Flows-and-Matching/06-matching-theorems-konig-hall-dilworth.md) |
| Gallai: max independent set $= n -$ min vertex cover (any graph) | bipartite ⇒ $n -$ max matching |
| König's edge-coloring theorem: bipartite ⇒ edge chromatic number $= \Delta$ | (🧊) |
| XOR walk values from $s$ to $t$ $= d(t) \oplus \text{span}(\text{cycle XORs})$ | reuse of edges cancels |

Complexities: 2-coloring and odd-cycle extraction $O(n+m)$; girth $O(nm)$; XOR basis $O((n+m) + (m-n)\log W)$.

## 3. Implementation (C++ and Java)

**BFS 2-coloring with odd-cycle extraction.** Returns the colors, or (if not bipartite) fills `cycle` with an odd cycle
$u \dots \ell \dots v$ as a vertex list. Vertices $0..n-1$, adjacency as vectors/CSR.

```cpp
// returns true if bipartite (color filled); otherwise false and `cycle` holds an odd simple cycle
bool bipartiteOrOddCycle(int n, const vector<vector<int>>& g, vector<int>& color, vector<int>& cycle) {
    color.assign(n, -1);
    vector<int> par(n, -1), dist(n, 0);
    for (int s = 0; s < n; s++) {
        if (color[s] != -1) continue;
        color[s] = 0;
        queue<int> q; q.push(s);
        while (!q.empty()) {
            int u = q.front(); q.pop();
            for (int v : g[u]) {
                if (color[v] == -1) { color[v] = color[u] ^ 1; par[v] = u; dist[v] = dist[u] + 1; q.push(v); }
                else if (color[v] == color[u]) {           // same BFS layer: climb both to their LCA
                    vector<int> left, right;
                    int a = u, b = v;
                    while (a != b) { left.push_back(a); right.push_back(b); a = par[a]; b = par[b]; }
                    cycle = left;
                    cycle.push_back(a);                    // the LCA
                    cycle.insert(cycle.end(), right.rbegin(), right.rend());
                    return false;
                }
            }
        }
    }
    return true;
}
```

```java
// returns null if bipartite (color filled), otherwise an odd simple cycle as a vertex array
static int[] bipartiteOrOddCycle(int n, int[] head, int[] nxt, int[] to, int[] color) {
    Arrays.fill(color, -1);
    int[] par = new int[n], q = new int[n];
    Arrays.fill(par, -1);
    for (int s = 0; s < n; s++) {
        if (color[s] != -1) continue;
        color[s] = 0;
        int qh = 0, qt = 0; q[qt++] = s;
        while (qh < qt) {
            int u = q[qh++];
            for (int e = head[u]; e != -1; e = nxt[e]) {
                int v = to[e];
                if (color[v] == -1) { color[v] = color[u] ^ 1; par[v] = u; q[qt++] = v; }
                else if (color[v] == color[u]) {
                    int[] left = new int[n], right = new int[n];
                    int lc = 0, rc = 0, a = u, b = v;
                    while (a != b) { left[lc++] = a; right[rc++] = b; a = par[a]; b = par[b]; }
                    int[] cyc = new int[lc + 1 + rc];
                    int k = 0;
                    for (int i = 0; i < lc; i++) cyc[k++] = left[i];
                    cyc[k++] = a;
                    for (int i = rc - 1; i >= 0; i--) cyc[k++] = right[i];
                    return cyc;
                }
            }
        }
    }
    return null;
}
```

Why the climb works in lockstep: equal colors inside one BFS tree means equal parity of depth, and an edge changes depth by at most
one, so the depths are actually *equal*; the two parent chains reach the LCA after the same number of steps.

**Girth.** BFS from every vertex; for each non-tree edge, update the answer. Using the parent *edge* (not vertex) makes it correct for
multigraphs too (two parallel edges form a 2-cycle).

```cpp
int girth(int n, const vector<vector<int>>& g) {     // returns -1 if acyclic
    const int INF = INT_MAX;
    int best = INF;
    vector<int> d(n), par(n);
    for (int s = 0; s < n; s++) {
        fill(d.begin(), d.end(), -1);
        d[s] = 0; par[s] = -1;
        queue<int> q; q.push(s);
        while (!q.empty()) {
            int u = q.front(); q.pop();
            if (2 * d[u] + 1 >= best) break;             // no candidate from this layer on can improve
            for (int v : g[u]) {
                if (d[v] == -1) { d[v] = d[u] + 1; par[v] = u; q.push(v); }
                else if (v != par[u]) best = min(best, d[u] + d[v] + 1);
            }
        }
    }
    return best == INF ? -1 : best;
}
```

```java
static int girth(int n, int[] head, int[] nxt, int[] to) {
    int best = Integer.MAX_VALUE;
    int[] d = new int[n], par = new int[n], q = new int[n];
    for (int s = 0; s < n; s++) {
        Arrays.fill(d, -1);
        d[s] = 0; par[s] = -1;
        int qh = 0, qt = 0; q[qt++] = s;
        while (qh < qt) {
            int u = q[qh++];
            if (2 * d[u] + 1 >= best) break;
            for (int e = head[u]; e != -1; e = nxt[e]) {
                int v = to[e];
                if (d[v] == -1) { d[v] = d[u] + 1; par[v] = u; q[qt++] = v; }
                else if (v != par[u]) best = Math.min(best, d[u] + d[v] + 1);
            }
        }
    }
    return best == Integer.MAX_VALUE ? -1 : best;
}
```

The `v != par[u]` test assumes a simple graph (as in CSES Graph Girth); for multigraphs compare edge ids. The early `break` is
safe: a candidate $2d(u)$ would come from a neighbor $v$ one layer up, but that edge was already reported when $v$ was processed
(then $u$ was already discovered by its parent); every other candidate from $u$ or later vertices is $\ge 2d(u) + 1$.

## 4. Recognising the pattern

| Statement signal | Think |
|---|---|
| "split into two groups so that every pair of enemies/friends is separated" | 2-coloring |
| "is it possible…" with only "different" constraints | bipartite check; with "same"/"different" mixed: parity DSU or BFS with edge parities |
| "count assignments" with "adjacent must differ in parity" | bipartite, product over components (CF 1093D) |
| "orient edges so no directed path of length 2" | every vertex is all-in or all-out ⇒ bipartite (CF 1144F) |
| "shortest cycle", "smallest set that forms a loop" | girth by BFS from every vertex ($n \le$ few thousand) |
| "walk of odd/even length", "length divisible by 3" | layered states $(v, \text{len} \bmod k)$ |
| "path weight = XOR of edges, edges reusable" | spanning tree XOR distances + linear basis of cycles |
| "maximum independent set / minimum vertex cover" on a bipartite graph | König via matching ([12/06](../12-Flows-and-Matching/06-matching-theorems-konig-hall-dilworth.md)) |
| "find any cycle" in an undirected graph | DFS: first back edge; in a directed graph use colors ([BFS/DFS](01-graph-representation-bfs-dfs.md)) |

## 5. Worked examples (graded)

### Example 1 — Building Teams  ·  ★ ≈1300

- **Source:** [CSES 1668 · Building Teams](https://cses.fi/problemset/task/1668)
- **Difficulty:** ≈1300 (est.)
- **Problem:** $n \le 10^5$ pupils, $m \le 2\cdot10^5$ friendships. Split the pupils into two teams so that no two friends share a
  team; print a team number ($1$ or $2$) for each pupil, or `IMPOSSIBLE`. (Any valid split is accepted; we BFS from pupils in
  increasing order and give each new component's first pupil team 1, which makes the output deterministic.)
- **Thinking from first principles:** "Friends in different teams" is exactly a proper 2-coloring. Each component's coloring is
  forced once one pupil is fixed, so BFS either succeeds or finds an odd cycle (then no split exists).

<details><summary>Solution</summary>

BFS per component; conflict ⇒ `IMPOSSIBLE`. $O(n + m)$.

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
        int a, b; cin >> a >> b;
        g[a].push_back(b); g[b].push_back(a);
    }
    vector<int> team(n + 1, 0);
    for (int s = 1; s <= n; s++) {
        if (team[s]) continue;
        team[s] = 1;
        queue<int> q; q.push(s);
        while (!q.empty()) {
            int u = q.front(); q.pop();
            for (int v : g[u]) {
                if (!team[v]) { team[v] = 3 - team[u]; q.push(v); }
                else if (team[v] == team[u]) { cout << "IMPOSSIBLE\n"; return 0; }
            }
        }
    }
    for (int v = 1; v <= n; v++) cout << team[v] << " \n"[v == n];
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
        int[] team = new int[n + 1], q = new int[n];
        for (int s = 1; s <= n; s++) {
            if (team[s] != 0) continue;
            team[s] = 1;
            int qh = 0, qt = 0; q[qt++] = s;
            while (qh < qt) {
                int u = q[qh++];
                for (int e = head[u]; e != -1; e = nxt[e]) {
                    int v = to[e];
                    if (team[v] == 0) { team[v] = 3 - team[u]; q[qt++] = v; }
                    else if (team[v] == team[u]) { System.out.println("IMPOSSIBLE"); return; }
                }
            }
        }
        StringBuilder sb = new StringBuilder();
        for (int v = 1; v <= n; v++) sb.append(team[v]).append(v == n ? '\n' : ' ');
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
5 3
1 2
1 3
4 5
out:
1 2 2 1 2
-->
<!-- test
in:
3 3
1 2
2 3
3 1
out:
IMPOSSIBLE
-->
<!-- test
in:
1 0
out:
1
-->
<!-- test
in:
6 6
1 2
2 3
3 4
4 5
5 6
6 1
out:
1 2 1 2 1 2
-->

### Example 2 — Mahmoud and Ehab and the bipartiteness  ·  ★ 1300

- **Source:** [CF 862B · Mahmoud and Ehab and the bipartiteness](https://codeforces.com/problemset/problem/862/B) — 1300
- **Difficulty:** 1300
- **Problem:** A tree with $n \le 10^5$ vertices. Add as many edges as possible so the graph stays bipartite and simple (no loops
  or parallel edges). Print the maximum number of added edges.
- **Thinking from first principles:** A tree is bipartite with a *unique* bipartition $(A, B)$ (connected). Any added edge inside
  a side creates an odd cycle, so every new edge goes between $A$ and $B$; all $|A|\,|B|$ cross pairs are allowed, $n - 1$ already exist.
  Answer $|A|\,|B| - (n-1)$ — up to $2.5\cdot10^9$, so 64-bit.

<details><summary>Solution</summary>

BFS-color the tree, count sides. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<vector<int>> g(n + 1);
    for (int i = 0; i < n - 1; i++) {
        int a, b; cin >> a >> b;
        g[a].push_back(b); g[b].push_back(a);
    }
    vector<int> c(n + 1, -1);
    long long cnt[2] = {0, 0};
    c[1] = 0;
    queue<int> q; q.push(1);
    while (!q.empty()) {
        int u = q.front(); q.pop();
        cnt[c[u]]++;
        for (int v : g[u]) if (c[v] == -1) { c[v] = c[u] ^ 1; q.push(v); }
    }
    cout << cnt[0] * cnt[1] - (n - 1) << "\n";
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
        int[] head = new int[n + 1], nxt = new int[2 * n], to = new int[2 * n];
        Arrays.fill(head, -1);
        for (int i = 0; i < n - 1; i++) {
            int a = nextInt(), b = nextInt();
            to[2 * i] = b; nxt[2 * i] = head[a]; head[a] = 2 * i;
            to[2 * i + 1] = a; nxt[2 * i + 1] = head[b]; head[b] = 2 * i + 1;
        }
        int[] c = new int[n + 1], q = new int[n];
        Arrays.fill(c, -1);
        long[] cnt = new long[2];
        int qh = 0, qt = 0;
        c[1] = 0; q[qt++] = 1;
        while (qh < qt) {
            int u = q[qh++];
            cnt[c[u]]++;
            for (int e = head[u]; e != -1; e = nxt[e]) if (c[to[e]] == -1) { c[to[e]] = c[u] ^ 1; q[qt++] = to[e]; }
        }
        System.out.println(cnt[0] * cnt[1] - (n - 1));
    }
}
```

</details>

<!-- test
in:
1
out:
0
-->
<!-- test
in:
5
1 2
2 3
3 4
4 5
out:
2
-->
<!-- test
in:
5
1 2
1 3
1 4
1 5
out:
0
-->
<!-- test
in:
4
1 2
2 3
3 4
out:
1
-->

### Example 3 — Graph Without Long Directed Paths  ·  ★ 1700

- **Source:** [CF 1144F · Graph Without Long Directed Paths](https://codeforces.com/problemset/problem/1144/F) — 1700
- **Difficulty:** 1700
- **Problem:** A connected simple undirected graph ($n, m \le 2\cdot10^5$). Orient every edge so that the directed graph has no
  path of two or more edges. Print `NO`, or `YES` and a binary string whose $i$-th character is `0` if edge $i$ goes from its first
  listed endpoint to its second, `1` otherwise. (Any valid string is accepted; we color vertex $1$ with $0$ and direct every edge
  from color $0$ to color $1$.)
- **Thinking from first principles:** No directed path of length 2 means no vertex has both an incoming and an outgoing edge:
  every vertex is a pure source or a pure sink. Every edge joins a source to a sink, so {sources, sinks} is a bipartition. Conversely
  any bipartition works by orienting all edges from one side to the other. So: answer exists iff the graph is bipartite.

<details><summary>Solution</summary>

BFS 2-coloring; edge $i = (u_i, v_i)$ prints `0` iff $u_i$ has color $0$. $O(n + m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<vector<int>> g(n + 1);
    vector<int> eu(m), ev(m);
    for (int i = 0; i < m; i++) {
        cin >> eu[i] >> ev[i];
        g[eu[i]].push_back(ev[i]); g[ev[i]].push_back(eu[i]);
    }
    vector<int> c(n + 1, -1);
    c[1] = 0;
    queue<int> q; q.push(1);
    while (!q.empty()) {
        int u = q.front(); q.pop();
        for (int v : g[u]) {
            if (c[v] == -1) { c[v] = c[u] ^ 1; q.push(v); }
            else if (c[v] == c[u]) { cout << "NO\n"; return 0; }
        }
    }
    string s(m, '0');
    for (int i = 0; i < m; i++) if (c[eu[i]] == 1) s[i] = '1';
    cout << "YES\n" << s << "\n";
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
        int[] head = new int[n + 1], nxt = new int[2 * m], to = new int[2 * m], eu = new int[m];
        Arrays.fill(head, -1);
        for (int i = 0; i < m; i++) {
            int a = nextInt(), b = nextInt();
            eu[i] = a;
            to[2 * i] = b; nxt[2 * i] = head[a]; head[a] = 2 * i;
            to[2 * i + 1] = a; nxt[2 * i + 1] = head[b]; head[b] = 2 * i + 1;
        }
        int[] c = new int[n + 1], q = new int[n];
        Arrays.fill(c, -1);
        int qh = 0, qt = 0;
        c[1] = 0; q[qt++] = 1;
        while (qh < qt) {
            int u = q[qh++];
            for (int e = head[u]; e != -1; e = nxt[e]) {
                int v = to[e];
                if (c[v] == -1) { c[v] = c[u] ^ 1; q[qt++] = v; }
                else if (c[v] == c[u]) { System.out.println("NO"); return; }
            }
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < m; i++) sb.append(c[eu[i]] == 1 ? '1' : '0');
        System.out.println("YES\n" + sb);
    }
}
```

</details>

<!-- test
in:
3 3
1 2
2 3
3 1
out:
NO
-->
<!-- test
in:
3 2
1 2
3 1
out:
YES
01
-->
<!-- test
in:
4 4
1 2
2 3
3 4
4 1
out:
YES
0101
-->

### Example 4 — Beautiful Graph  ·  ★ 1700

- **Source:** [CF 1093D · Beautiful Graph](https://codeforces.com/problemset/problem/1093/D) — 1700
- **Difficulty:** 1700
- **Problem:** $t$ test cases, total $n, m \le 3\cdot10^5$. Write $1$, $2$ or $3$ on every vertex so that each edge's endpoint values
  sum to an odd number. Count the ways modulo $998244353$.
- **Thinking from first principles:** Odd sum ⟺ endpoints have different parity, so "even/odd" is a 2-coloring: the graph must be
  bipartite. Even means value $2$ (one choice), odd means $1$ or $3$ (two choices). In a component with sides $a$ and $b$, either side
  can be the odd one: $2^a + 2^b$ ways. Components are independent ⇒ multiply. An isolated vertex contributes $2^1 + 2^0 = 3$. Any odd
  cycle ⇒ $0$. Pitfall: with many test cases, don't `memset` arrays of size $3\cdot10^5$ per test — clear only the vertices used.

<details><summary>Solution</summary>

BFS per component counting side sizes; precompute powers of two. $O(n + m)$ per test.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    const long long MOD = 998244353;
    const int MAXN = 300000;
    vector<long long> pw(MAXN + 1, 1);
    for (int i = 1; i <= MAXN; i++) pw[i] = pw[i - 1] * 2 % MOD;
    int t;
    cin >> t;
    while (t--) {
        int n, m;
        cin >> n >> m;
        vector<vector<int>> g(n + 1);
        for (int i = 0; i < m; i++) {
            int a, b; cin >> a >> b;
            g[a].push_back(b); g[b].push_back(a);
        }
        vector<int> c(n + 1, -1);
        long long ans = 1;
        bool ok = true;
        for (int s = 1; s <= n && ok; s++) {
            if (c[s] != -1) continue;
            int cnt[2] = {0, 0};
            c[s] = 0;
            queue<int> q; q.push(s);
            while (!q.empty() && ok) {
                int u = q.front(); q.pop();
                cnt[c[u]]++;
                for (int v : g[u]) {
                    if (c[v] == -1) { c[v] = c[u] ^ 1; q.push(v); }
                    else if (c[v] == c[u]) { ok = false; break; }
                }
            }
            ans = ans * ((pw[cnt[0]] + pw[cnt[1]]) % MOD) % MOD;
        }
        cout << (ok ? ans : 0) << "\n";
    }
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
        final long MOD = 998244353;
        final int MAXN = 300000;
        long[] pw = new long[MAXN + 1];
        pw[0] = 1;
        for (int i = 1; i <= MAXN; i++) pw[i] = pw[i - 1] * 2 % MOD;
        int t = nextInt();
        StringBuilder sb = new StringBuilder();
        while (t-- > 0) {
            int n = nextInt(), m = nextInt();
            int[] head = new int[n + 1], nxt = new int[2 * m], to = new int[2 * m];
            Arrays.fill(head, -1);
            for (int i = 0; i < m; i++) {
                int a = nextInt(), b = nextInt();
                to[2 * i] = b; nxt[2 * i] = head[a]; head[a] = 2 * i;
                to[2 * i + 1] = a; nxt[2 * i + 1] = head[b]; head[b] = 2 * i + 1;
            }
            int[] c = new int[n + 1], q = new int[n];
            Arrays.fill(c, -1);
            long ans = 1;
            boolean ok = true;
            for (int s = 1; s <= n && ok; s++) {
                if (c[s] != -1) continue;
                int[] cnt = new int[2];
                int qh = 0, qt = 0;
                c[s] = 0; q[qt++] = s;
                while (qh < qt && ok) {
                    int u = q[qh++];
                    cnt[c[u]]++;
                    for (int e = head[u]; e != -1; e = nxt[e]) {
                        int v = to[e];
                        if (c[v] == -1) { c[v] = c[u] ^ 1; q[qt++] = v; }
                        else if (c[v] == c[u]) { ok = false; break; }
                    }
                }
                ans = ans * ((pw[cnt[0]] + pw[cnt[1]]) % MOD) % MOD;
            }
            sb.append(ok ? ans : 0).append('\n');
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
2
2 1
1 2
4 6
1 2
1 3
1 4
2 3
2 4
3 4
out:
4
0
-->
<!-- test
in:
2
3 0
3 2
1 2
2 3
out:
27
6
-->
<!-- test
in:
1
1 0
out:
3
-->

### Example 5 — Graph Girth  ·  ★ ≈2000

- **Source:** [CSES 1707 · Graph Girth](https://cses.fi/problemset/task/1707)
- **Difficulty:** ≈2000 (est.)
- **Problem:** A simple undirected graph with $n \le 2500$, $m \le 5000$. Print the length of its shortest cycle, or $-1$.
- **Thinking from first principles:** DFS back edges give *some* cycle, not the shortest (DFS depths are not distances). BFS
  distances are, and §1 proves $g = \min_s \min_{\text{non-tree } uv} (d_s(u) + d_s(v) + 1)$, with exactness at any vertex of a
  shortest cycle. Total work $n \cdot (n + m) \approx 1.9\cdot10^7$.

<details><summary>Solution</summary>

BFS from every vertex with the layer cut-off from §3. $O(n(n+m))$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<vector<int>> g(n);
    for (int i = 0; i < m; i++) {
        int a, b; cin >> a >> b; a--; b--;
        g[a].push_back(b); g[b].push_back(a);
    }
    const int INF = INT_MAX;
    int best = INF;
    vector<int> d(n), par(n), q(n);
    for (int s = 0; s < n; s++) {
        fill(d.begin(), d.end(), -1);
        d[s] = 0; par[s] = -1;
        int qh = 0, qt = 0; q[qt++] = s;
        while (qh < qt) {
            int u = q[qh++];
            if (2 * d[u] + 1 >= best) break;
            for (int v : g[u]) {
                if (d[v] == -1) { d[v] = d[u] + 1; par[v] = u; q[qt++] = v; }
                else if (v != par[u]) best = min(best, d[u] + d[v] + 1);
            }
        }
    }
    cout << (best == INF ? -1 : best) << "\n";
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
        int[] head = new int[n], nxt = new int[2 * m], to = new int[2 * m];
        Arrays.fill(head, -1);
        for (int i = 0; i < m; i++) {
            int a = nextInt() - 1, b = nextInt() - 1;
            to[2 * i] = b; nxt[2 * i] = head[a]; head[a] = 2 * i;
            to[2 * i + 1] = a; nxt[2 * i + 1] = head[b]; head[b] = 2 * i + 1;
        }
        int best = Integer.MAX_VALUE;
        int[] d = new int[n], par = new int[n], q = new int[n];
        for (int s = 0; s < n; s++) {
            Arrays.fill(d, -1);
            d[s] = 0; par[s] = -1;
            int qh = 0, qt = 0; q[qt++] = s;
            while (qh < qt) {
                int u = q[qh++];
                if (2 * d[u] + 1 >= best) break;
                for (int e = head[u]; e != -1; e = nxt[e]) {
                    int v = to[e];
                    if (d[v] == -1) { d[v] = d[u] + 1; par[v] = u; q[qt++] = v; }
                    else if (v != par[u]) best = Math.min(best, d[u] + d[v] + 1);
                }
            }
        }
        System.out.println(best == Integer.MAX_VALUE ? -1 : best);
    }
}
```

</details>

<!-- test
in:
5 5
1 2
2 3
3 1
3 4
4 5
out:
3
-->
<!-- test
in:
4 3
1 2
2 3
3 4
out:
-1
-->
<!-- test
in:
10 15
1 2
2 3
3 4
4 5
5 1
1 6
2 7
3 8
4 9
5 10
6 8
8 10
10 7
7 9
9 6
out:
5
-->
<!-- test
in:
8 9
1 2
2 3
3 4
4 5
5 1
5 6
6 7
7 8
8 5
out:
4
-->

### Example 6 — Shortest Path Problem? (XOR cycle basis)  ·  ★ 2300

- **Source:** [CF 845G · Shortest Path Problem?](https://codeforces.com/problemset/problem/845/G) — 2300
- **Difficulty:** 2300
- **Problem:** A connected undirected graph ($n, m \le 10^5$, loops and multi-edges allowed, weights $< 2^{27}$). The length of a
  walk is the XOR of its edge weights, counted with multiplicity. Print the minimum length of a walk from $1$ to $n$.
- **Thinking from first principles:** Dijkstra fails: XOR is not monotone. Reuse of edges is the key: go from the walk to any cycle,
  around it, and back along the same connector — the connector cancels, the cycle's XOR is added. So the achievable set is
  $d(n) \oplus \text{span}(\text{cycle values})$, where $d(v)$ is the XOR along a spanning tree and each non-tree edge $u$–$v$ of weight
  $w$ contributes the fundamental cycle value $d(u) \oplus d(v) \oplus w$ (loops: $w$ itself). Every walk's value is of this form
  (its edge multiset reduces mod 2 to a tree path plus cycles), so it is exact. Insert the $m - n + 1$ cycle values into a linear basis
  (Gaussian elimination over $\mathbb{F}_2$, 27 bits) and greedily reduce $d(n)$: for bits from high to low, XOR the basis vector with
  that leading bit if it lowers the value.

<details><summary>Solution</summary>

Iterative DFS/BFS for $d$, basis insertion per non-tree edge, greedy minimisation. $O((n + m) \cdot 27)$.
Stress-tested against a BFS over (vertex, XOR value) states with small weights.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<int> head(n + 1, -1), nxt(2 * m), to(2 * m), wt(2 * m);
    for (int i = 0; i < m; i++) {
        int a, b, w; cin >> a >> b >> w;
        to[2 * i] = b; wt[2 * i] = w; nxt[2 * i] = head[a]; head[a] = 2 * i;
        to[2 * i + 1] = a; wt[2 * i + 1] = w; nxt[2 * i + 1] = head[b]; head[b] = 2 * i + 1;
    }
    int basis[30] = {0};
    auto insert = [&](int x) {
        for (int b = 29; b >= 0 && x; b--) {
            if (!(x >> b & 1)) continue;
            if (!basis[b]) { basis[b] = x; return; }
            x ^= basis[b];
        }
    };
    vector<int> d(n + 1, -1), parArc(n + 1, -1), stk = {1};
    d[1] = 0;
    while (!stk.empty()) {
        int u = stk.back(); stk.pop_back();
        for (int a = head[u]; a != -1; a = nxt[a]) {
            int v = to[a];
            if (d[v] == -1) { d[v] = d[u] ^ wt[a]; parArc[v] = a; stk.push_back(v); }
        }
    }
    for (int i = 0; i < m; i++) {                      // each edge: tree edges give 0, others a cycle value
        int a = to[2 * i + 1], b = to[2 * i];
        insert(d[a] ^ d[b] ^ wt[2 * i]);
    }
    int ans = d[n];
    for (int b = 29; b >= 0; b--) if (basis[b] && (ans ^ basis[b]) < ans) ans ^= basis[b];
    cout << ans << "\n";
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
    static int[] basis = new int[30];
    static void insert(int x) {
        for (int b = 29; b >= 0 && x != 0; b--) {
            if ((x >> b & 1) == 0) continue;
            if (basis[b] == 0) { basis[b] = x; return; }
            x ^= basis[b];
        }
    }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt();
        int[] head = new int[n + 1], nxt = new int[2 * m], to = new int[2 * m], wt = new int[2 * m];
        Arrays.fill(head, -1);
        for (int i = 0; i < m; i++) {
            int a = nextInt(), b = nextInt(), w = nextInt();
            to[2 * i] = b; wt[2 * i] = w; nxt[2 * i] = head[a]; head[a] = 2 * i;
            to[2 * i + 1] = a; wt[2 * i + 1] = w; nxt[2 * i + 1] = head[b]; head[b] = 2 * i + 1;
        }
        int[] d = new int[n + 1], stk = new int[n + 1];
        Arrays.fill(d, -1);
        int sp = 0;
        d[1] = 0; stk[sp++] = 1;
        while (sp > 0) {
            int u = stk[--sp];
            for (int a = head[u]; a != -1; a = nxt[a]) {
                int v = to[a];
                if (d[v] == -1) { d[v] = d[u] ^ wt[a]; stk[sp++] = v; }
            }
        }
        for (int i = 0; i < m; i++) insert(d[to[2 * i + 1]] ^ d[to[2 * i]] ^ wt[2 * i]);
        int ans = d[n];
        for (int b = 29; b >= 0; b--) if (basis[b] != 0 && (ans ^ basis[b]) < ans) ans ^= basis[b];
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
3 3
1 2 3
1 3 2
3 2 0
out:
2
-->
<!-- test
in:
2 2
1 1 3
1 2 3
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
4 4
1 2 5
2 3 6
3 4 7
4 2 1
out:
4
-->
<!-- test
in:
4 4
1 4 7
1 2 1
2 3 2
3 1 4
out:
0
-->

## 6. Tricks, pitfalls and things to remember

1. **Disconnected graphs:** start a BFS from every uncolored vertex; a graph is bipartite iff *every* component is.
2. **Color while pushing**, not while popping, or the same vertex is enqueued many times (and the conflict test misfires).
3. **Odd-cycle extraction needs BFS parents** (equal depths); with DFS, use the tree path between the two endpoints of the back edge instead.
4. **Self-loop ⇒ not bipartite** (a cycle of length 1). Parallel edges are irrelevant for bipartiteness but are 2-cycles for girth in multigraphs.
5. **Girth with early termination:** stop a source's BFS only once `2*d[u]+1 >= best`; stopping at the first candidate can overshoot by 1 (an even $2d+2$ seen before an odd $2d+1$ in the same layer).
6. **Per-vertex shortest cycle through $v$** is *not* $g_v$; it needs extra care (the two BFS branches must start with different first edges).
7. **Counting with many test cases** (CF 1093D): allocate per test or reset only touched vertices; precompute powers once.
8. **Overflow:** $|A|\cdot|B|$ for $n = 10^5$ is $2.5\cdot10^9$ — `long long` / `long`.
9. **Bipartite + parity constraints** ("same/different team"): give edges a parity and check $c(v) = c(u) \oplus p$; or use a parity DSU.
10. **XOR basis:** insert with the *highest* bit first and keep one vector per leading bit; minimise by greedy from the top bit down.
11. **Java:** recursion-free BFS over `int[]` adjacency; for $t$ up to $3\cdot10^5$ tests, avoid `ArrayList` allocation per vertex per test.

## 7. Going further (toward 2400–2600+)

- **Bipartite + knapsack:** each component offers two side sizes; choose one per component to hit an exact count — [CF 1354E · Graph Coloring](https://codeforces.com/problemset/problem/1354/E) — 2100.
- **Dynamic bipartiteness:** edges added/removed over time → DSU with parity + rollback + segment tree on time
  ([segment tree on time](../16-IGM-Frontier/02-segment-tree-on-time-and-dsu-rollback.md), [CF 813F · Bipartite Checking](https://codeforces.com/problemset/problem/813/F) — 2500).
- **Shortest cycle in special graphs:** numbers with $\le 7$ divisors → graph on primes, girth by BFS only from small primes
  ([CF 1325E · Ehab's REAL Number Theory Problem](https://codeforces.com/problemset/problem/1325/E) — 2600); bit graphs where
  a bit shared by $\ge 3$ numbers gives a triangle ([CF 1205B · Shortest Cycle](https://codeforces.com/problemset/problem/1205/B) — 1900).
- **Max/min XOR path, XOR basis queries per prefix, and "number of distinct XOR values"** — all from the same cycle-space basis
  ([XOR basis](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md)).
- **Matching side:** bipartite graphs unlock König, Hall, Hopcroft–Karp — see [12-Flows-and-Matching](../12-Flows-and-Matching/03-bipartite-matching-kuhn-hopcroft-karp.md).
- **Odd cycle transversal / making a graph bipartite by deleting few vertices** is NP-hard in general; contests restrict structure.

## 8. Practice ladder

**≤ 1400**
- [ ] [CSES 1668 · Building Teams](https://cses.fi/problemset/task/1668) — BFS 2-coloring
- [ ] [CF 862B · Mahmoud and Ehab and the bipartiteness](https://codeforces.com/problemset/problem/862/B) — 1300 — sides of a tree
- [ ] [AtCoder ABC327 D · Good Tuple Problem](https://atcoder.jp/contests/abc327/tasks/abc327_d) — ≈709 (est.) — bipartiteness in disguise
- [ ] [CSES 1669 · Round Trip](https://cses.fi/problemset/task/1669) — find any cycle in an undirected graph
- [ ] [CF 1534C · Little Alawn's Puzzle](https://codeforces.com/problemset/problem/1534/C) — 1300 — count cycles of a permutation graph

**1400–1900**
- [ ] [CF 687A · NP-Hard Problem](https://codeforces.com/problemset/problem/687/A) — 1500 — two disjoint vertex covers = bipartition
- [ ] [CF 1702E · Split Into Two Sets](https://codeforces.com/problemset/problem/1702/E) — 1600 — odd cycles in a degree-2 graph
- [ ] [AtCoder ABC282 D · Make Bipartite 2](https://atcoder.jp/contests/abc282/tasks/abc282_d) — ≈1154 (est.) — count addable edges over components
- [ ] [AtCoder ABC126 D · Even Relation](https://atcoder.jp/contests/abc126/tasks/abc126_d) — ≈1279 (est.) — parity of weighted distances
- [ ] [AtCoder ABC132 E · Hopscotch Addict](https://atcoder.jp/contests/abc132/tasks/abc132_e) — ≈1625 (est.) — states $(v, \text{len} \bmod 3)$
- [ ] [CF 1144F · Graph Without Long Directed Paths](https://codeforces.com/problemset/problem/1144/F) — 1700
- [ ] [CF 1093D · Beautiful Graph](https://codeforces.com/problemset/problem/1093/D) — 1700
- [ ] [CF 1176E · Cover it!](https://codeforces.com/problemset/problem/1176/E) — 1700 — smaller BFS-parity class dominates
- [ ] [CF 1205B · Shortest Cycle](https://codeforces.com/problemset/problem/1205/B) — 1900 — pigeonhole then girth
- [ ] [AtCoder ABC229 F · Make Bipartite](https://atcoder.jp/contests/abc229/tasks/abc229_f) — ≈1917 (est.) — cycle DP on a wheel

**1900–2400**
- [ ] [CSES 1707 · Graph Girth](https://cses.fi/problemset/task/1707) — BFS from every vertex
- [ ] [CF 1354E · Graph Coloring](https://codeforces.com/problemset/problem/1354/E) — 2100 — bipartite components + knapsack
- [ ] [CF 845G · Shortest Path Problem?](https://codeforces.com/problemset/problem/845/G) — 2300 — XOR cycle basis

**2400+**
- [ ] [CF 813F · Bipartite Checking](https://codeforces.com/problemset/problem/813/F) — 2500 — offline dynamic bipartiteness
- [ ] [CF 1325E · Ehab's REAL Number Theory Problem](https://codeforces.com/problemset/problem/1325/E) — 2600 — girth on a prime graph

## 9. LeetCode / FAANG cross-reference

- [LC 785 · Is Graph Bipartite?](https://leetcode.com/problems/is-graph-bipartite/) — Medium — BFS coloring over every component.
- [LC 886 · Possible Bipartition](https://leetcode.com/problems/possible-bipartition/) — Medium — dislikes are edges; same algorithm.
- [LC 2493 · Divide Nodes Into the Maximum Number of Groups](https://leetcode.com/problems/divide-nodes-into-the-maximum-number-of-groups/) — Hard — bipartite check, then max BFS depth per component (BFS from every vertex).
- [LC 2608 · Shortest Cycle in a Graph](https://leetcode.com/problems/shortest-cycle-in-a-graph/) — Hard — exactly the girth algorithm.
- [LC 1042 · Flower Planting With No Adjacent](https://leetcode.com/problems/flower-planting-with-no-adjacent/) — Medium — greedy coloring with degree ≤ 3 (contrast: 2 colors is a bipartite question, 4 colors with degree ≤ 3 is always possible).

Bipartite checks are a staple of FAANG graph rounds; girth and XOR-basis variants are rare.

## 10. Self-check

1. Prove that a graph with no odd cycle is bipartite.
2. In BFS 2-coloring, a conflicting edge $u$–$v$ is found. Why are $d(u)$ and $d(v)$ equal, and how do you output an odd cycle?
3. How many valid 2-colorings does a bipartite graph with $c$ components have?
4. Why is $\min_{\text{non-tree } uv} (d_s(u) + d_s(v) + 1)$ an upper bound on the girth, and when is it exact?
5. Why is stopping BFS at the first non-tree edge not safe for computing $g_s$?
6. How do you decide whether there is a walk of odd length between $a$ and $b$?
7. Why does the set of XOR-walk values from $1$ to $n$ equal $d(n) \oplus \text{span}(\text{cycle values})$?
8. A tree with sides $3$ and $4$: how many edges can be added keeping it bipartite and simple?

<details><summary>Answers</summary>

1. BFS-color by distance parity. An edge between equal distances would close an odd cycle with the two BFS paths to their LCA; with no odd cycles every edge joins distances of different parity.
2. Same color = same parity of depth, and an edge changes BFS depth by at most 1, so the depths are equal. Climb parents from both in lockstep until they meet at the LCA; path + edge has odd length $2(d - d_\ell) + 1$.
3. $2^c$.
4. The closed walk $s \leadsto u \to v \leadsto s$ contains the fundamental cycle of $uv$, so the girth is at most its length. It equals the girth when $s$ lies on a shortest cycle: some edge of that cycle is non-tree, and the two remaining arcs bound the distances.
5. While processing layer $d$ the candidates are $2d+1$ (same layer) or $2d+2$ (next layer, already discovered); the first one met may be $2d+2$ although a later vertex of the layer gives $2d+1$. Finish the layer (stop when `2*d[u]+1 >= best`).
6. BFS on the double cover $(v, \text{parity})$: reachable $(b, 1)$ from $(a, 0)$.
7. Any walk's edge multiset mod 2 is a tree path plus a set of fundamental cycles; conversely any cycle can be added by walking to it and back (the connector cancels).
8. $3\cdot4 - 6 = 6$.

</details>
