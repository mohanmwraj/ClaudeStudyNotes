# Bipartite Matching: Kuhn's Algorithm and Hopcroft–Karp

> **Band:** 🔵→🟣 1700–2400 · **Priority:** 🔥 · **FAANG:** low (medium for the *idea* of augmenting paths) · **Prerequisites:** [BFS/DFS](../09-Graphs/01-graph-representation-bfs-dfs.md), [bipartite graphs](../09-Graphs/09-bipartite-graphs-and-cycles.md), [max flow](01-max-flow-dinic.md)
> **You can say you know this when:** you can prove Berge's lemma, write Kuhn in five minutes and Hopcroft–Karp in fifteen, explain why each costs what it costs,
> and recover a minimum vertex cover / maximum independent set from a maximum matching.

## 1. First principles — why this works

A **matching** is a set of edges with no shared endpoint. In a bipartite graph $G=(L\cup R, E)$ we want a maximum one.

**Naive approaches.** Trying all subsets is exponential. Greedy ("match each left vertex to any free neighbor") is not optimal: with edges $a_1b_1, a_1b_2, a_2b_1$,
matching $a_1b_1$ first blocks $a_2$; the optimum is $\{a_1b_2, a_2b_1\}$. Greedy made a choice it could not revise — the same disease as greedy flow, and the same cure.

**Alternating and augmenting paths.** Given a matching $M$, an *alternating path* alternates non-matching and matching edges. An *augmenting path* is an alternating
path whose two ends are both free (unmatched). Flipping it (matched ↔ unmatched along the path) gives a matching with one more edge. In the example, after $a_1b_1$:
$a_2 \to b_1 \Rightarrow a_1 \to b_2$ is augmenting, and flipping it yields the optimum.

**Berge's lemma.** $M$ is maximum iff there is no augmenting path. Proof of the hard direction: let $M^*$ be larger; the symmetric difference $M\oplus M^*$ has max degree 2,
so it splits into alternating paths and even cycles. Cycles and even paths have equally many edges of each; since $|M^*|>|M|$, some component has more $M^*$ edges,
which is an odd path starting and ending with $M^*$ edges — an augmenting path for $M$. ∎

**Kuhn's algorithm.** For each left vertex $u$ in turn, DFS for an augmenting path starting at $u$: from a left vertex try every neighbor $v$; if $v$ is free, done;
otherwise continue from $v$'s partner (the only way an alternating path can continue). Mark left vertices visited per search so each search is $O(E)$.

*Why one pass over $u$ suffices:* if no augmenting path starts at free $u$ now, none will appear later while we augment from other vertices. (Sketch: an augmentation along
path $P$ only changes edges of $P$; if after it an augmenting path $Q$ from $u$ existed, $Q$ must intersect $P$, and then splicing the part of $Q$ from $u$ to the first common vertex
with the appropriate end of $P$ gives an augmenting path from $u$ before the augmentation — contradiction.) So Kuhn is $|L|$ searches of $O(E)$: $O(|L|\cdot E)$, i.e. $O(VE)$.
In practice it is much faster, especially with a **greedy initialization** (match obvious pairs first; this alone often finds 90%+ of the matching) and with
"multi-pass" visited arrays (reset `visited` only after a pass in which some augmentation failed).

**Matching = unit flow.** Add $s\to u$ ($u\in L$), $u\to v$ for edges, $v\to t$ ($v\in R$), all capacity 1. Integral flows are exactly matchings, so max flow = max matching.
Kuhn is Ford–Fulkerson on this network; residual paths are alternating paths. Running **Dinic** on it is $O(E\sqrt V)$ (unit network, see [01](01-max-flow-dinic.md)),
which is the same bound as Hopcroft–Karp.

**Hopcroft–Karp.** Like Dinic: in each phase, BFS from *all* free left vertices to get layers (distance along alternating paths), then find a maximal set of
vertex-disjoint *shortest* augmenting paths by DFS that only moves to the next layer (with current-arc pointers so a phase is $O(E)$). After a phase, the shortest augmenting path is strictly longer.

*Phase bound:* after $\sqrt V$ phases every augmenting path has length $\ge\sqrt V$. If $M^*$ is maximum, $M\oplus M^*$ contains $|M^*|-|M|$ vertex-disjoint augmenting paths,
each with $\ge \sqrt V$ vertices, so $|M^*|-|M|\le \sqrt V$; at most $\sqrt V$ more phases. Total $O(\sqrt V)$ phases × $O(E)$ = $O(E\sqrt V)$.

**What a maximum matching certifies (König, Gallai).** In a bipartite graph the size of a maximum matching equals the size of a minimum vertex cover (König, proved in
[06](06-matching-theorems-konig-hall-dilworth.md)), and the complement of a minimum vertex cover is a maximum independent set. The constructive proof is a single BFS:
let $Z$ = vertices reachable from free left vertices by alternating paths. Then $(L\setminus Z)\cup(R\cap Z)$ is a minimum vertex cover.

## 2. Formulas, definitions and identities

| Quantity | Formula / statement | Why |
|---|---|---|
| Augmentation | $M' = M\oplus P$, $\lvert M'\rvert = \lvert M\rvert + 1$ | $P$ has one more non-matching edge than matching edges |
| Berge | $M$ maximum $\iff$ no augmenting path | symmetric difference argument |
| Matching via flow | $\nu(G) = \text{maxflow}(s,t)$ in the unit network | integral flows ↔ matchings |
| König | $\nu(G) = \tau(G)$ (min vertex cover), bipartite only | alternating BFS construction |
| Independent set | $\alpha(G) = \lvert V\rvert - \tau(G) = \lvert V\rvert - \nu(G)$ (bipartite) | complement of a cover is independent |
| Edge cover (Gallai) | $\rho(G) = \lvert V\rvert - \nu(G)$ if no isolated vertex | extend a max matching greedily |
| Perfect matching (Hall) | exists on $L$ iff $\lvert N(S)\rvert\ge\lvert S\rvert\ \forall S\subseteq L$ | see [06](06-matching-theorems-konig-hall-dilworth.md) |
| Deficiency | $\nu = \lvert L\rvert - \max_{S\subseteq L}(\lvert S\rvert-\lvert N(S)\rvert)$ | König applied to $S$ |
| Remaining gap | $\lvert M^*\rvert - \lvert M\rvert \le V / \ell$ if shortest augmenting path has $\ell$ vertices | disjoint paths in $M\oplus M^*$ |

Complexities: Kuhn $O(|L|\,E)$; Hopcroft–Karp $O(E\sqrt V)$; Dinic on the unit network $O(E\sqrt V)$; greedy initialization $O(E)$; cover reconstruction $O(V+E)$.
General (non-bipartite) graphs: Edmonds' blossom $O(V^3)$ or $O(VE)$ variants (🔴, see §7).

## 3. Implementation (C++ and Java)

**Kuhn** with greedy initialization. Left vertices $0..n_L-1$, right $0..n_R-1$. The Java version is recursive (depth $\le n_L$): call it from a thread with a large
stack if $n_L$ can exceed ~$10^4$.

```cpp
struct Kuhn {
    int nl, nr, stamp = 0;
    vector<vector<int>> adj;
    vector<int> ml, mr, vis;                 // ml[u] = partner of left u, mr[v] = partner of right v
    Kuhn(int nl, int nr) : nl(nl), nr(nr), adj(nl), ml(nl, -1), mr(nr, -1), vis(nl, 0) {}
    void addEdge(int u, int v) { adj[u].push_back(v); }
    bool augment(int u) {
        if (vis[u] == stamp) return false;
        vis[u] = stamp;
        for (int v : adj[u])
            if (mr[v] == -1 || augment(mr[v])) { ml[u] = v; mr[v] = u; return true; }
        return false;
    }
    int solve() {
        int res = 0;
        for (int u = 0; u < nl; u++)          // greedy initialization
            for (int v : adj[u]) if (mr[v] == -1) { ml[u] = v; mr[v] = u; res++; break; }
        for (int u = 0; u < nl; u++)
            if (ml[u] == -1) { stamp++; if (augment(u)) res++; }
        return res;
    }
};
```

```java
static class Kuhn {
    int nl, nr, stamp = 0;
    int[][] adj;
    int[] ml, mr, vis;
    Kuhn(int nl, int nr, int[][] adj) {
        this.nl = nl; this.nr = nr; this.adj = adj;
        ml = new int[nl]; mr = new int[nr]; vis = new int[nl];
        Arrays.fill(ml, -1); Arrays.fill(mr, -1);
    }
    boolean augment(int u) {
        if (vis[u] == stamp) return false;
        vis[u] = stamp;
        for (int v : adj[u])
            if (mr[v] == -1 || augment(mr[v])) { ml[u] = v; mr[v] = u; return true; }
        return false;
    }
    int solve() {
        int res = 0;
        for (int u = 0; u < nl; u++)
            for (int v : adj[u]) if (mr[v] == -1) { ml[u] = v; mr[v] = u; res++; break; }
        for (int u = 0; u < nl; u++)
            if (ml[u] == -1) { stamp++; if (augment(u)) res++; }
        return res;
    }
    // adjacency builder: edges (eu[i], ev[i]) for i < m
    static int[][] build(int nl, int[] eu, int[] ev, int m) {
        int[] deg = new int[nl];
        for (int i = 0; i < m; i++) deg[eu[i]]++;
        int[][] adj = new int[nl][];
        for (int u = 0; u < nl; u++) adj[u] = new int[deg[u]];
        for (int i = 0; i < m; i++) adj[eu[i]][--deg[eu[i]]] = ev[i];
        return adj;
    }
}
```

**Hopcroft–Karp**, $O(E\sqrt V)$. C++ uses a recursive DFS with current-arc pointers; Java uses CSR arrays and an explicit stack (no recursion).

```cpp
struct HopcroftKarp {
    int nl, nr;
    vector<vector<int>> adj;
    vector<int> ml, mr, dist, it;
    HopcroftKarp(int nl, int nr) : nl(nl), nr(nr), adj(nl), ml(nl, -1), mr(nr, -1), dist(nl), it(nl) {}
    void addEdge(int u, int v) { adj[u].push_back(v); }
    bool bfs() {                               // layers over left vertices, from all free ones
        queue<int> q;
        for (int u = 0; u < nl; u++) { dist[u] = ml[u] == -1 ? 0 : -1; if (!dist[u]) q.push(u); }
        bool found = false;
        while (!q.empty()) {
            int u = q.front(); q.pop();
            for (int v : adj[u]) {
                int w = mr[v];
                if (w == -1) found = true;
                else if (dist[w] < 0) { dist[w] = dist[u] + 1; q.push(w); }
            }
        }
        return found;
    }
    bool dfs(int u) {
        for (int &i = it[u]; i < (int)adj[u].size(); i++) {
            int v = adj[u][i], w = mr[v];
            if (w == -1 || (dist[w] == dist[u] + 1 && dfs(w))) { ml[u] = v; mr[v] = u; return true; }
        }
        dist[u] = -1;                          // dead for this phase
        return false;
    }
    int solve() {
        int res = 0;
        while (bfs()) {
            fill(it.begin(), it.end(), 0);
            for (int u = 0; u < nl; u++) if (ml[u] == -1 && dfs(u)) res++;
        }
        return res;
    }
};
```

```java
static class HopcroftKarp {
    int nl, nr;
    int[] start, adjv, ml, mr, dist, it, q, stk;
    HopcroftKarp(int nl, int nr, int[] eu, int[] ev, int m) {   // CSR from an edge list
        this.nl = nl; this.nr = nr;
        start = new int[nl + 1]; adjv = new int[m];
        for (int i = 0; i < m; i++) start[eu[i] + 1]++;
        for (int u = 0; u < nl; u++) start[u + 1] += start[u];
        int[] pos = Arrays.copyOf(start, nl);
        for (int i = 0; i < m; i++) adjv[pos[eu[i]]++] = ev[i];
        ml = new int[nl]; mr = new int[nr]; dist = new int[nl]; it = new int[nl]; q = new int[nl]; stk = new int[nl];
        Arrays.fill(ml, -1); Arrays.fill(mr, -1);
    }
    boolean bfs() {
        int qh = 0, qt = 0;
        for (int u = 0; u < nl; u++) { dist[u] = ml[u] == -1 ? 0 : -1; if (dist[u] == 0) q[qt++] = u; }
        boolean found = false;
        while (qh < qt) {
            int u = q[qh++];
            for (int k = start[u]; k < start[u + 1]; k++) {
                int w = mr[adjv[k]];
                if (w == -1) found = true;
                else if (dist[w] < 0) { dist[w] = dist[u] + 1; q[qt++] = w; }
            }
        }
        return found;
    }
    boolean dfs(int root) {                    // iterative: stk holds left vertices of the current path
        int top = 0;
        stk[top++] = root;
        while (top > 0) {
            int u = stk[top - 1];
            if (it[u] == start[u + 1]) { dist[u] = -1; top--; continue; }   // dead end, retreat
            int w = mr[adjv[it[u]]];
            if (w == -1) {                                                    // free right vertex: flip the path
                for (int i = top - 1; i >= 0; i--) { int x = stk[i], y = adjv[it[x]]; ml[x] = y; mr[y] = x; }
                return true;
            }
            if (dist[w] == dist[u] + 1) stk[top++] = w;                      // go one layer deeper
            else it[u]++;
        }
        return false;
    }
    int solve() {
        int res = 0;
        while (bfs()) {
            System.arraycopy(start, 0, it, 0, nl);
            for (int u = 0; u < nl; u++) if (ml[u] == -1 && dfs(u)) res++;
        }
        return res;
    }
}
```

**Minimum vertex cover and maximum independent set** from a maximum matching (König's construction). `inCover[L|R]` marks the cover; the independent set is the complement.

```cpp
// adj: left adjacency, ml/mr: a MAXIMUM matching. Returns {coverLeft, coverRight}.
pair<vector<char>, vector<char>> konigCover(int nl, int nr, const vector<vector<int>> &adj, const vector<int> &ml, const vector<int> &mr) {
    vector<char> visL(nl, 0), visR(nr, 0);
    queue<int> q;
    for (int u = 0; u < nl; u++) if (ml[u] == -1) { visL[u] = 1; q.push(u); }
    while (!q.empty()) {
        int u = q.front(); q.pop();
        for (int v : adj[u]) if (!visR[v]) {         // non-matching edge L -> R
            visR[v] = 1;
            int w = mr[v];                            // matching edge R -> L (w exists: matching is maximum)
            if (w != -1 && !visL[w]) { visL[w] = 1; q.push(w); }
        }
    }
    vector<char> coverL(nl), coverR(nr);
    for (int u = 0; u < nl; u++) coverL[u] = !visL[u];
    for (int v = 0; v < nr; v++) coverR[v] = visR[v];
    return {coverL, coverR};
}
```

```java
// adj: left adjacency, ml/mr: a MAXIMUM matching. Returns {coverLeft, coverRight}.
static boolean[][] konigCover(int nl, int nr, int[][] adj, int[] ml, int[] mr) {
    boolean[] visL = new boolean[nl], visR = new boolean[nr];
    int[] q = new int[nl];
    int qh = 0, qt = 0;
    for (int u = 0; u < nl; u++) if (ml[u] == -1) { visL[u] = true; q[qt++] = u; }
    while (qh < qt) {
        int u = q[qh++];
        for (int v : adj[u]) if (!visR[v]) {
            visR[v] = true;
            int w = mr[v];
            if (w != -1 && !visL[w]) { visL[w] = true; q[qt++] = w; }
        }
    }
    boolean[] coverL = new boolean[nl], coverR = new boolean[nr];
    for (int u = 0; u < nl; u++) coverL[u] = !visL[u];
    for (int v = 0; v < nr; v++) coverR[v] = visR[v];
    return new boolean[][]{coverL, coverR};
}
```

Why the construction is a cover of size $\nu$: an edge $uv$ is uncovered only if $u\in Z$ and $v\notin Z$; but from $u\in Z$ the BFS visits every neighbor, so $v\in Z$. Every
$R\cap Z$ vertex is matched (otherwise an augmenting path exists) and its partner is in $Z$, hence not in the cover; every $L\setminus Z$ vertex is matched (free left vertices are in $Z$)
and its partner is not in $Z$ (else the left vertex would be). So each matching edge contributes exactly one cover vertex and nothing else is chosen: size $=\nu$.

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| two kinds of objects, each pairs with at most one of the other kind | bipartite matching |
| grid + "no two adjacent", dominoes, $2\times1$ tiles | chessboard bipartition, cells as vertices |
| "minimum number of points/lines to cover all X", "rows or columns" | König: minimum vertex cover = matching |
| "maximum set with no conflicting pair", conflicts only between two classes | maximum independent set $= V-\nu$ |
| $n\le 500$: Kuhn; $n, m\le 10^5$: Hopcroft–Karp or Dinic | pick the algorithm by $V\sqrt E$ vs $VE$ |
| "maximize the minimum / minimize the maximum" + pairing feasibility | binary search + matching |
| answer changes as edges are added one by one | incremental augmenting paths (never recompute from scratch) |
| objects on a line with "pair if close" | probably a greedy two-pointer; matching is the safe fallback |

Confusions: **general graphs** (odd cycles) need blossom, not Kuhn — check bipartiteness first. **Weighted** matching is the assignment problem
([Hungarian](05-hungarian-algorithm.md) or [min-cost flow](04-min-cost-flow.md)). **Capacities** larger than 1 on vertices ("each club accepts 3 people") are a flow, not a matching.

## 5. Worked examples (graded)

### Example 1 — School Dance  ·  ★ ≈1700

- **Source:** [CSES 1696 · School Dance](https://cses.fi/problemset/task/1696)
- **Difficulty:** ≈1700 (est.)
- **Problem:** $n\le 500$ boys, $m\le 500$ girls, $k\le 1000$ compatible boy–girl pairs. Form as many dance pairs as possible (each person in at most one pair) and print them.
- **Thinking from first principles:** textbook bipartite matching; $VE = 5\cdot10^5$, so Kuhn is instant. The output is any maximum matching; we print the pairs sorted by boy, and the tests
  below have a unique maximum matching so the output is checkable.

<details><summary>Solution</summary>

Kuhn with greedy initialization; print $(u+1, ml[u]+1)$ for every matched boy in increasing order. $O(nk)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct Kuhn {
    int nl, nr, stamp = 0;
    vector<vector<int>> adj; vector<int> ml, mr, vis;
    Kuhn(int nl, int nr) : nl(nl), nr(nr), adj(nl), ml(nl, -1), mr(nr, -1), vis(nl, 0) {}
    void addEdge(int u, int v) { adj[u].push_back(v); }
    bool augment(int u) {
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
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m, k;
    cin >> n >> m >> k;
    Kuhn km(n, m);
    for (int i = 0; i < k; i++) { int a, b; cin >> a >> b; km.addEdge(a - 1, b - 1); }
    cout << km.solve() << "\n";
    for (int u = 0; u < n; u++) if (km.ml[u] != -1) cout << u + 1 << " " << km.ml[u] + 1 << "\n";
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

    static class Kuhn {
        int nl, nr, stamp = 0; int[][] adj; int[] ml, mr, vis;
        Kuhn(int nl, int nr, int[][] adj) {
            this.nl = nl; this.nr = nr; this.adj = adj;
            ml = new int[nl]; mr = new int[nr]; vis = new int[nl];
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

    static void solve() throws IOException {
        int n = nextInt(), m = nextInt(), k = nextInt();
        int[] eu = new int[k], ev = new int[k], deg = new int[n];
        for (int i = 0; i < k; i++) { eu[i] = nextInt() - 1; ev[i] = nextInt() - 1; deg[eu[i]]++; }
        int[][] adj = new int[n][];
        for (int u = 0; u < n; u++) adj[u] = new int[deg[u]];
        for (int i = k - 1; i >= 0; i--) adj[eu[i]][--deg[eu[i]]] = ev[i];   // keeps input order
        Kuhn km = new Kuhn(n, m, adj);
        StringBuilder sb = new StringBuilder().append(km.solve()).append('\n');
        for (int u = 0; u < n; u++) if (km.ml[u] != -1) sb.append(u + 1).append(' ').append(km.ml[u] + 1).append('\n');
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.print(sb);
        out.flush();
    }

    public static void main(String[] args) throws Exception {
        Thread th = new Thread(null, () -> {
            try { solve(); } catch (IOException e) { throw new UncheckedIOException(e); }
        }, "main", 1 << 27);
        th.start();
        th.join();
    }
}
```

</details>

In the first test greedy would pair boy 1 with girl 1 and then has to reroute (boy 2 only likes girl 1); the unique maximum matching is 1–2, 2–1, 3–3.

<!-- test
in:
3 3 4
1 1
1 2
2 1
3 3
out:
3
1 2
2 1
3 3
-->
<!-- test
in:
1 1 0
out:
0
-->
<!-- test
in:
4 2 4
1 1
2 1
3 2
4 1
out:
2
1 1
3 2
-->

The third test is not unique in general (boys 1, 2 and 4 all like girl 1); our deterministic rule (greedy initialization in input order) gives boy 1, which the program prints.
Its count, 2, is forced (only two girls).

### Example 2 — BerSU Ball  ·  ★ 1200

- **Source:** [CF 489B · BerSU Ball](https://codeforces.com/problemset/problem/489/B) — 1200
- **Difficulty:** 1200
- **Problem:** $n\le 100$ boys and $m\le 100$ girls with dancing skills in $[1,100]$; a boy and a girl can pair if their skills differ by at most 1. Print the maximum number of pairs.
- **Thinking from first principles:** the compatibility graph is bipartite, so Kuhn solves it outright. There is also a greedy: sort both arrays and sweep with two pointers,
  pairing whenever $|a_i-b_j|\le1$ and otherwise advancing the smaller one. The exchange argument: the smallest boy should take the smallest compatible girl, since any other
  choice can be swapped without loss. Knowing both is the point — matching is the safe tool, the greedy is the 1200-rated insight.

<details><summary>Solution</summary>

Kuhn on the compatibility graph: $O(nm\cdot n)$ at most $10^6$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int n, m;
vector<int> a, b, mr, vis;
int stamp_ = 0;

bool augment(int u) {
    if (vis[u] == stamp_) return false;
    vis[u] = stamp_;
    for (int v = 0; v < m; v++)
        if (abs(a[u] - b[v]) <= 1 && (mr[v] == -1 || augment(mr[v]))) { mr[v] = u; return true; }
    return false;
}

int main() {
    cin >> n;
    a.resize(n);
    for (auto &x : a) cin >> x;
    cin >> m;
    b.resize(m);
    for (auto &x : b) cin >> x;
    mr.assign(m, -1);
    vis.assign(n, 0);
    int res = 0;
    for (int u = 0; u < n; u++) { stamp_++; if (augment(u)) res++; }
    cout << res << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n, m, stamp = 0;
    static int[] a, b, mr, vis;

    static boolean augment(int u) {
        if (vis[u] == stamp) return false;
        vis[u] = stamp;
        for (int v = 0; v < m; v++)
            if (Math.abs(a[u] - b[v]) <= 1 && (mr[v] == -1 || augment(mr[v]))) { mr[v] = u; return true; }
        return false;
    }

    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); n = (int) st.nval;
        a = new int[n];
        for (int i = 0; i < n; i++) { st.nextToken(); a[i] = (int) st.nval; }
        st.nextToken(); m = (int) st.nval;
        b = new int[m];
        for (int i = 0; i < m; i++) { st.nextToken(); b[i] = (int) st.nval; }
        mr = new int[m]; Arrays.fill(mr, -1);
        vis = new int[n];
        int res = 0;
        for (int u = 0; u < n; u++) { stamp++; if (augment(u)) res++; }
        System.out.println(res);
    }
}
```

</details>

<!-- test
in:
4
1 4 6 2
5
5 1 5 7 9
out:
3
-->
<!-- test
in:
1
1
1
3
out:
0
-->
<!-- test
in:
3
2 2 2
2
1 3
out:
2
-->

### Example 3 — Array and Operations  ·  ★ 2100

- **Source:** [CF 498C · Array and Operations](https://codeforces.com/problemset/problem/498/C) — 2100
- **Difficulty:** 2100
- **Problem:** an array $a_1..a_n$ ($n\le 100$, $a_i\le10^9$) and $m\le 100$ "good pairs" $(i,j)$ with $i<j$ and $i+j$ odd. One operation picks a good pair and an integer $v>1$ dividing
  both $a_i$ and $a_j$, and divides both by $v$. Print the maximum number of operations.
- **Thinking from first principles:** (1) Dividing by a composite $v$ is never better than dividing by one of its primes — so every operation removes *one copy of one prime* from
  both ends. (2) Different primes never interact, so solve each prime $p$ separately and add up. (3) For a fixed $p$, index $i$ holds $e_p(a_i)$ copies; an operation consumes one copy at
  each end of a good pair. Because $i+j$ is odd, every good pair joins an odd index with an even index — the "pairs" graph is bipartite. Consuming copies in pairs along edges is a
  **matching with multiplicities** (a $b$-matching), i.e. a flow: $s\to$ odd $i$ (capacity $e_p(a_i)$), odd $\to$ even along good pairs ($\infty$), even $j\to t$ (capacity $e_p(a_j)$).

<details><summary>Solution</summary>

Factorize every $a_i$ by trial division up to $\sqrt{10^9}\approx 31623$, collect the distinct primes (at most $9n$), and for each prime add the max flow of the network above.
Each network has $n+2$ vertices and $\le n+m$ edges; total cost is negligible.

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
    vector<ll> a(n + 1);
    for (int i = 1; i <= n; i++) cin >> a[i];
    vector<pair<int, int>> pr(m);
    for (auto &[i, j] : pr) { cin >> i >> j; if (i % 2 == 0) swap(i, j); }   // i odd, j even
    set<ll> primes;
    for (int i = 1; i <= n; i++) {
        ll x = a[i];
        for (ll p = 2; p * p <= x; p++) if (x % p == 0) { primes.insert(p); while (x % p == 0) x /= p; }
        if (x > 1) primes.insert(x);
    }
    ll ans = 0;
    for (ll p : primes) {
        int s = 0, t = n + 1;
        Dinic d(n + 2);
        for (int i = 1; i <= n; i++) {
            int e = 0;
            for (ll x = a[i]; x % p == 0; x /= p) e++;
            if (e == 0) continue;
            if (i % 2 == 1) d.addEdge(s, i, e); else d.addEdge(i, t, e);
        }
        for (auto [i, j] : pr) d.addEdge(i, j, 1000);
        ans += d.maxflow(s, t);
    }
    cout << ans << "\n";
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
        long[] a = new long[n + 1];
        for (int i = 1; i <= n; i++) a[i] = nextLong();
        int[] pi = new int[m], pj = new int[m];
        for (int k = 0; k < m; k++) {
            int i = nextInt(), j = nextInt();
            if (i % 2 == 0) { int tmp = i; i = j; j = tmp; }
            pi[k] = i; pj[k] = j;
        }
        TreeSet<Long> primes = new TreeSet<>();
        for (int i = 1; i <= n; i++) {
            long x = a[i];
            for (long p = 2; p * p <= x; p++) if (x % p == 0) { primes.add(p); while (x % p == 0) x /= p; }
            if (x > 1) primes.add(x);
        }
        long ans = 0;
        for (long p : primes) {
            int s = 0, t = n + 1;
            Dinic d = new Dinic(n + 2, n + m);
            for (int i = 1; i <= n; i++) {
                int e = 0;
                for (long x = a[i]; x % p == 0; x /= p) e++;
                if (e == 0) continue;
                if (i % 2 == 1) d.addEdge(s, i, e, 0); else d.addEdge(i, t, e, 0);
            }
            for (int k = 0; k < m; k++) d.addEdge(pi[k], pj[k], 1000, 0);
            ans += d.maxflow(s, t, Long.MAX_VALUE);
        }
        System.out.println(ans);
    }
}
```

</details>

Hand checks: $[8,3,8]$ with pairs $(1,2),(2,3)$: index 2 has no factor 2 and only one 3 — nothing in common with the 8s, so 0. $[8,12,8]$ with the same pairs: prime 2 has
$3,2,3$ copies; index 2 (even) has 2 copies to share with indices 1 and 3, so 2. A single pair $(1,2)$ of $[2^{5}\cdot 3, 2^{3}\cdot 3^{2}] = [96, 72]$ gives $3 + 1 = 4$.

<!-- test
in:
3 2
8 3 8
1 2
2 3
out:
0
-->
<!-- test
in:
3 2
8 12 8
1 2
2 3
out:
2
-->
<!-- test
in:
2 1
96 72
1 2
out:
4
-->
<!-- test
in:
1 0
1000000000
out:
0
-->

### Example 4 — Maximize Mex  ·  ★ 2400

- **Source:** [CF 1139E · Maximize Mex](https://codeforces.com/problemset/problem/1139/E) — 2400
- **Difficulty:** 2400
- **Problem:** $n\le 5000$ students, each with a potential $p_i\in[0,5000)$ and a club $c_i\in[1,m]$ ($m\le5000$). On each of $d$ days one given student leaves forever; then the
  director picks at most one remaining student from every club and the day's value is the mex of the picked potentials. Print the best possible value for each day.
- **Thinking from first principles:** for a fixed set of students, "mex $\ge x$" means potentials $0,\dots,x-1$ can each be assigned a *distinct* club that has a student with that potential:
  a matching between **values** and **clubs**. Deletions are hard for matchings; insertions are easy (old augmenting paths stay valid, only new ones may appear). So reverse time:
  start from the students who never leave, insert the leavers in reverse order. Mex never decreases under insertion, so keep a pointer `mex` and keep trying to augment from value
  `mex`; each success increments it permanently.

<details><summary>Solution</summary>

Left side = values $0..4999$, right side = clubs. Present students are edges $p_i\to c_i$. Maintain a matching that saturates values $0..\text{mex}-1$. After inserting a student,
repeatedly run Kuhn's `augment(mex)` (fresh visited stamp) while it succeeds. Correctness: values below `mex` stay matched (augmenting never unmatches a left vertex), and if `augment(mex)`
fails there is no matching covering $0..\text{mex}$ by Berge's lemma. Cost: at most 5000 successful and $d+1$ failed searches, each $O(n)$: about $5\cdot 10^7$.

```cpp
#include <bits/stdc++.h>
using namespace std;

const int V = 5000;
vector<int> adj[V];
int mr[5001], vis[V], stamp_ = 0;

bool augment(int x) {
    if (vis[x] == stamp_) return false;
    vis[x] = stamp_;
    for (int c : adj[x]) if (mr[c] == -1 || augment(mr[c])) { mr[c] = x; return true; }
    return false;
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<int> p(n), c(n);
    for (auto &x : p) cin >> x;
    for (auto &x : c) cin >> x;
    int d;
    cin >> d;
    vector<int> k(d);
    vector<char> leaves(n, 0);
    for (auto &x : k) { cin >> x; x--; leaves[x] = 1; }
    for (int i = 0; i < n; i++) if (!leaves[i]) adj[p[i]].push_back(c[i]);
    fill(mr, mr + m + 1, -1);
    int mex = 0;
    vector<int> ans(d);
    for (int day = d - 1; day >= 0; day--) {
        while (mex < V) { stamp_++; if (augment(mex)) mex++; else break; }
        ans[day] = mex;
        adj[p[k[day]]].push_back(c[k[day]]);        // the student who left on this day comes back
    }
    for (int x : ans) cout << x << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final int V = 5000;
    static int[][] adj = new int[V][];
    static int[] deg = new int[V], mr, vis = new int[V];
    static int stamp = 0;

    static void add(int x, int club) {
        if (adj[x] == null) adj[x] = new int[4];
        if (deg[x] == adj[x].length) adj[x] = Arrays.copyOf(adj[x], 2 * deg[x]);
        adj[x][deg[x]++] = club;
    }

    static boolean augment(int x) {
        if (vis[x] == stamp) return false;
        vis[x] = stamp;
        for (int i = 0; i < deg[x]; i++) {
            int c = adj[x][i];
            if (mr[c] == -1 || augment(mr[c])) { mr[c] = x; return true; }
        }
        return false;
    }

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

    static void solve() throws IOException {
        int n = nextInt(), m = nextInt();
        int[] p = new int[n], c = new int[n];
        for (int i = 0; i < n; i++) p[i] = nextInt();
        for (int i = 0; i < n; i++) c[i] = nextInt();
        int d = nextInt();
        int[] k = new int[d];
        boolean[] leaves = new boolean[n];
        for (int i = 0; i < d; i++) { k[i] = nextInt() - 1; leaves[k[i]] = true; }
        for (int i = 0; i < n; i++) if (!leaves[i]) add(p[i], c[i]);
        mr = new int[m + 1];
        Arrays.fill(mr, -1);
        int mex = 0;
        int[] ans = new int[d];
        for (int day = d - 1; day >= 0; day--) {
            while (mex < V) { stamp++; if (augment(mex)) mex++; else break; }
            ans[day] = mex;
            add(p[k[day]], c[k[day]]);
        }
        StringBuilder sb = new StringBuilder();
        for (int x : ans) sb.append(x).append('\n');
        System.out.print(sb);
    }

    public static void main(String[] args) throws Exception {
        Thread th = new Thread(null, () -> {
            try { solve(); } catch (IOException e) { throw new UncheckedIOException(e); }
        }, "main", 1 << 27);
        th.start();
        th.join();
    }
}
```

</details>

Hand check of the first test: students (potential, club) = (0,1), (1,2), (2,2), (0,3), (1,3). After day 1 (student 1 leaves) club 1 is empty, club 3 can give 0
and club 2 can give 1, so the mex is 2 (three values from two clubs is impossible). After day 2 (student 4 leaves) nobody has potential 0, so the mex is 0.

<!-- test
in:
5 3
0 1 2 0 1
1 2 2 3 3
2
1
4
out:
2
0
-->
<!-- test
in:
1 1
0
1
1
1
out:
0
-->
<!-- test
in:
4 4
0 1 2 3
1 2 3 4
1
4
out:
3
-->

### Example 5 — Rooks behind walls  ·  ★ ≈2000

- **Source:** Original problem.
- **Difficulty:** ≈2000 (est.)
- **Problem:** an $H\times W$ grid ($H,W\le 500$) of `.` and `#`. Place as many rooks as possible on `.` cells so that no two attack each other; a rook attacks along its row and column
  but walls `#` block the line of sight. Print the maximum.
- **Thinking from first principles:** without walls the answer is $\min(H,W)$ — rows and columns are a bipartite structure and a rook *is* a row–column pair. With walls, the right
  "rows" are **maximal horizontal runs** of `.` cells and the "columns" are maximal vertical runs: two rooks conflict exactly when they share a run. Each cell is one edge (its horizontal run,
  its vertical run), and a valid placement is a matching. Up to $1.25\cdot10^5$ runs per side and $2.5\cdot10^5$ edges — use Hopcroft–Karp.

<details><summary>Solution</summary>

Label horizontal runs and vertical runs, add an edge per `.` cell, and print the maximum matching. $O(E\sqrt V)$ with $E\le HW$.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct HopcroftKarp {
    int nl, nr;
    vector<vector<int>> adj; vector<int> ml, mr, dist, it;
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

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int h, w;
    cin >> h >> w;
    vector<string> g(h);
    for (auto &row : g) cin >> row;
    vector<vector<int>> hid(h, vector<int>(w, -1)), vid(h, vector<int>(w, -1));
    int nh = 0, nv = 0;
    for (int i = 0; i < h; i++)
        for (int j = 0; j < w; j++) if (g[i][j] == '.') hid[i][j] = (j > 0 && g[i][j - 1] == '.') ? hid[i][j - 1] : nh++;
    for (int j = 0; j < w; j++)
        for (int i = 0; i < h; i++) if (g[i][j] == '.') vid[i][j] = (i > 0 && g[i - 1][j] == '.') ? vid[i - 1][j] : nv++;
    HopcroftKarp hk(nh, nv);
    for (int i = 0; i < h; i++) for (int j = 0; j < w; j++) if (g[i][j] == '.') hk.addEdge(hid[i][j], vid[i][j]);
    cout << hk.solve() << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static class HopcroftKarp {
        int nl, nr; int[] start, adjv, ml, mr, dist, it, q, stk;
        HopcroftKarp(int nl, int nr, int[] eu, int[] ev, int m) {
            this.nl = nl; this.nr = nr;
            start = new int[nl + 1]; adjv = new int[m];
            for (int i = 0; i < m; i++) start[eu[i] + 1]++;
            for (int u = 0; u < nl; u++) start[u + 1] += start[u];
            int[] pos = Arrays.copyOf(start, nl);
            for (int i = 0; i < m; i++) adjv[pos[eu[i]]++] = ev[i];
            ml = new int[nl]; mr = new int[nr]; dist = new int[nl]; it = new int[nl]; q = new int[nl]; stk = new int[nl];
            Arrays.fill(ml, -1); Arrays.fill(mr, -1);
        }
        boolean bfs() {
            int qh = 0, qt = 0;
            for (int u = 0; u < nl; u++) { dist[u] = ml[u] == -1 ? 0 : -1; if (dist[u] == 0) q[qt++] = u; }
            boolean found = false;
            while (qh < qt) {
                int u = q[qh++];
                for (int k = start[u]; k < start[u + 1]; k++) { int w = mr[adjv[k]]; if (w == -1) found = true; else if (dist[w] < 0) { dist[w] = dist[u] + 1; q[qt++] = w; } }
            }
            return found;
        }
        boolean dfs(int root) {
            int top = 0; stk[top++] = root;
            while (top > 0) {
                int u = stk[top - 1];
                if (it[u] == start[u + 1]) { dist[u] = -1; top--; continue; }
                int w = mr[adjv[it[u]]];
                if (w == -1) { for (int i = top - 1; i >= 0; i--) { int x = stk[i], y = adjv[it[x]]; ml[x] = y; mr[y] = x; } return true; }
                if (dist[w] == dist[u] + 1) stk[top++] = w; else it[u]++;
            }
            return false;
        }
        int solve() {
            int res = 0;
            while (bfs()) { System.arraycopy(start, 0, it, 0, nl); for (int u = 0; u < nl; u++) if (ml[u] == -1 && dfs(u)) res++; }
            return res;
        }
    }

    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        int h = Integer.parseInt(st.nextToken()), w = Integer.parseInt(st.nextToken());
        char[][] g = new char[h][];
        for (int i = 0; i < h; i++) g[i] = br.readLine().trim().toCharArray();
        int[][] hid = new int[h][w], vid = new int[h][w];
        int nh = 0, nv = 0, cells = 0;
        for (int i = 0; i < h; i++)
            for (int j = 0; j < w; j++) if (g[i][j] == '.') { hid[i][j] = (j > 0 && g[i][j - 1] == '.') ? hid[i][j - 1] : nh++; cells++; }
        for (int j = 0; j < w; j++)
            for (int i = 0; i < h; i++) if (g[i][j] == '.') vid[i][j] = (i > 0 && g[i - 1][j] == '.') ? vid[i - 1][j] : nv++;
        int[] eu = new int[cells], ev = new int[cells];
        int m = 0;
        for (int i = 0; i < h; i++) for (int j = 0; j < w; j++) if (g[i][j] == '.') { eu[m] = hid[i][j]; ev[m] = vid[i][j]; m++; }
        System.out.println(new HopcroftKarp(nh, nv, eu, ev, m).solve());
    }
}
```

</details>

Hand checks: a $3\times3$ empty board → 3. A wall in the center of a $3\times3$ board splits the middle row and column, allowing 4 (e.g. the four edge midpoints). A board of walls → 0.

<!-- test
in:
3 3
...
...
...
out:
3
-->
<!-- test
in:
3 3
...
.#.
...
out:
4
-->
<!-- test
in:
2 2
##
##
out:
0
-->
<!-- test
in:
1 5
..#..
out:
2
-->

## 6. Tricks, pitfalls and things to remember

1. **Visited marks are per search**, not global: reset (or bump a stamp) before each `augment(u)` from a new free vertex. Forgetting gives wrong answers; resetting inside the recursion gives exponential time.
2. **Mark left vertices, not right ones**, in Kuhn (or both consistently). Marking right vertices also works if done before recursing — mixing the two conventions is a classic bug.
3. **Greedy initialization** is free and usually halves the running time; it never hurts correctness.
4. **Kuhn's order trick**: shuffling the left vertices or sorting by degree (low degree first) fights adversarial inputs.
5. **Kuhn is $O(VE)$ worst case.** At $V=E=10^5$ switch to Hopcroft–Karp or Dinic. Kuhn with a *global* visited array reset only when a whole pass fails is a fast heuristic, but its worst case is still $O(VE)$.
6. **Java recursion**: Kuhn's DFS depth can reach $|L|$; run in a `Thread` with a big stack or use the iterative Hopcroft–Karp. Use `int[][]`/CSR adjacency, not `ArrayList<Integer>`.
7. **The reconstruction needs a *maximum* matching.** König's construction on a non-maximum matching produces a non-cover.
8. **Non-bipartite graphs**: Kuhn silently returns a wrong (too small or invalid) answer on odd cycles. Check bipartiteness or use blossom.
9. **Incremental problems**: after adding edges, only try to augment from *new* candidates (Maximize Mex). Removing edges is the hard direction — reverse time.
10. **Duplicate edges** are harmless for correctness but cost time; dedupe on huge inputs.

## 7. Going further (toward 2400–2600+)

- **Weighted bipartite matching**: [Hungarian algorithm](05-hungarian-algorithm.md) and [min-cost flow](04-min-cost-flow.md).
- **General matching (🔴)**: Edmonds' blossom algorithm contracts odd cycles ("blossoms") during the alternating search, $O(V^3)$. For $V\le 40$ or so, bitmask DP is easier;
  randomized Tutte-matrix rank (🔴, Lovász) gives $\nu$ via Gaussian elimination modulo a prime — see [linear algebra tricks](../15-Advanced-Math/06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md).
  Practice: [CF 21D · Traveling Graph](https://codeforces.com/problemset/problem/21/D) — 2400 (Chinese postman: odd vertices paired by bitmask DP).
- **Matching theory** (König, Hall, Dilworth, Gallai): [06](06-matching-theorems-konig-hall-dilworth.md).
- **Online / dynamic matching**, matroid intersection (🧊): matching is the intersection of two partition matroids; harder "choose a set with two independence constraints" problems generalize the augmenting-path idea.

## 8. Practice ladder

≤ 1900
- [ ] [CF 489B · BerSU Ball](https://codeforces.com/problemset/problem/489/B) — 1200 — Example 2
- [ ] [CF 1360C · Similar Pairs](https://codeforces.com/problemset/problem/1360/C) — 1100 — parity counting; matching is overkill but think about why
- [ ] [CSES 1696 · School Dance](https://cses.fi/problemset/task/1696) — Example 1
- [ ] [AtCoder ARC092 A · 2D Plane 2N Points](https://atcoder.jp/contests/arc092/tasks/arc092_a) — dominance pairs; Kuhn or greedy
- [ ] [CF 1437C · Chef Monocarp](https://codeforces.com/problemset/problem/1437/C) — 1800 — dishes to time slots (DP or assignment)
- [ ] [CF 1423B · Valuable Paper](https://codeforces.com/problemset/problem/1423/B) — 1900 — binary search + Hopcroft–Karp ($10^5$ edges)
- [ ] [AtCoder PRACTICE2 D · Maxflow](https://atcoder.jp/contests/practice2/tasks/practice2_d) — domino tiling as matching

1900–2300
- [ ] [CF 498C · Array and Operations](https://codeforces.com/problemset/problem/498/C) — 2100 — Example 3
- [ ] [CF 852D · Exploration plan](https://codeforces.com/problemset/problem/852/D) — 2100 — binary search + matching
- [ ] [CF 387D · George and Interesting Graph](https://codeforces.com/problemset/problem/387/D) — 2200 — fix the center, match the rest
- [ ] [CF 1179C · Serge and Dining Room](https://codeforces.com/problemset/problem/1179/C) — 2200 — greedy matching characterized by a Hall-type prefix condition
- [ ] [CF 1470D · Strange Housing](https://codeforces.com/problemset/problem/1470/D) — 2200 — independent-set style construction (contrast with matching)

2300+
- [ ] [CF 1139E · Maximize Mex](https://codeforces.com/problemset/problem/1139/E) — 2400 — Example 4
- [ ] [CF 1027F · Session in BSU](https://codeforces.com/problemset/problem/1027/F) — 2400 — matching on a pseudoforest via DSU
- [ ] [CF 1783F · Double Sort II](https://codeforces.com/problemset/problem/1783/F) — 2500 — cycles + maximum matching
- [ ] [CF 1404E · Bricks](https://codeforces.com/problemset/problem/1404/E) — 2800 — maximum independent set in a bipartite conflict graph
- [ ] [CF 1198E · Rectangle Painting 2](https://codeforces.com/problemset/problem/1198/E) — 2500 — vertex cover with compressed coordinates
- [ ] [CF 21D · Traveling Graph](https://codeforces.com/problemset/problem/21/D) — 2400 — general matching by bitmask DP

## 9. LeetCode / FAANG cross-reference

Rare in interviews as "write Hopcroft–Karp", but augmenting-path matching on small inputs does appear in hard problems:

- [LC 1349 · Maximum Students Taking Exam](https://leetcode.com/problems/maximum-students-taking-exam/) — Hard — seats split by column parity are bipartite; answer = seats − matching.
- [LC 1820 · Maximum Number of Accepted Invitations](https://leetcode.com/problems/maximum-number-of-accepted-invitations/) — Medium 🔒 — plain bipartite matching (Kuhn).
- [LC 2123 · Minimum Operations to Remove Adjacent Ones in Matrix](https://leetcode.com/problems/minimum-operations-to-remove-adjacent-ones-in-matrix/) — Hard 🔒 — min vertex cover on a grid = max matching.
- [LC 2410 · Maximum Matching of Players With Trainers](https://leetcode.com/problems/maximum-matching-of-players-with-trainers/) — Medium — the "matching on a line" case: sort + two pointers.
- [LC 1947 · Maximum Compatibility Score Sum](https://leetcode.com/problems/maximum-compatibility-score-sum/) — Medium — weighted version (assignment); see [Hungarian](05-hungarian-algorithm.md).

## 10. Self-check

1. State and prove Berge's lemma.
2. Why does Kuhn need only one augmentation attempt per left vertex?
3. What is the complexity of Kuhn, and which inputs make it slow?
4. Why does Hopcroft–Karp have $O(\sqrt V)$ phases?
5. Given a maximum matching, construct a minimum vertex cover. Why is its size exactly $\nu$?
6. How do you get a maximum independent set in a bipartite graph? Why does this fail in general graphs?
7. In Maximize Mex, why process the days backwards?
8. In Array and Operations, why can each prime be handled independently, and why is the graph bipartite?

<details><summary>Answers</summary>

1. Augmenting path ⇒ not maximum (flip it). Not maximum ⇒ $M\oplus M^*$ splits into alternating paths/cycles; one component has more $M^*$ edges, an odd path with both end edges in $M^*$ — augmenting for $M$.
2. If no augmenting path from $u$ exists now, later augmentations elsewhere cannot create one (splicing argument), so retrying $u$ is useless.
3. $O(|L|\cdot E)$; long alternating chains where each search explores almost the whole graph (e.g. adversarial orderings in dense graphs).
4. After $\sqrt V$ phases augmenting paths have $\ge\sqrt V$ vertices; the $|M^*|-|M|$ disjoint augmenting paths in $M\oplus M^*$ then number at most $\sqrt V$; each phase finds at least one.
5. BFS alternating paths from free left vertices ($Z$); cover $=(L\setminus Z)\cup(R\cap Z)$. Each matching edge has exactly one endpoint in it and no other vertex is chosen.
6. Complement of a minimum vertex cover: $|V|-\nu$. In general graphs $\alpha + \tau = |V|$ still holds but $\tau\ne\nu$ (triangle: $\nu=1,\tau=2$), and min vertex cover is NP-hard.
7. Matchings handle edge insertion incrementally (the mex only grows), deletions would require recomputation.
8. Dividing by a prime power factor never helps over primes; exponents of different primes are independent resources. $i+j$ odd means every good pair joins an odd and an even index.

</details>
