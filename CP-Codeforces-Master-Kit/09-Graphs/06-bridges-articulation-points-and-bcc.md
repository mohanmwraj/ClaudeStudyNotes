# Bridges, Articulation Points and Biconnected Components

> **Band:** 🔵 1700 → 🟠 2300 · **Priority:** 🔥 (bridges, cut vertices, bridge tree) · ⚡ (block-cut tree) · **FAANG:** medium · **Prerequisites:** [BFS/DFS and DFS timestamps](01-graph-representation-bfs-dfs.md), [DSU](../08-Data-Structures/06-dsu-and-variants.md), [LCA](../10-Trees/02-lca-and-binary-lifting.md) (for block-cut tree queries)
> **You can say you know this when:** you can write the iterative low-link DFS from memory (multi-edges included), derive both the bridge test and the cut-vertex test from the definition of `low`, and turn "remove one edge / one vertex" questions into questions about the bridge tree or the block-cut tree.

## 1. First principles — why this works

**The question.** An edge is a *bridge* if deleting it increases the number of connected components. A vertex is an
*articulation point* (cut vertex) if deleting it (with its edges) increases the number of components. The naive test
deletes each edge and re-runs a BFS: $O(m(n+m))$, hopeless for $m = 2\cdot10^5$. We want one DFS, $O(n+m)$.

**Observation 1 — undirected DFS trees have no cross edges.** Run DFS and record the entry time `tin[v]`. Take any
non-tree edge $u$–$v$ with `tin[u] < tin[v]`. When $u$ was entered, $v$ was still unvisited and reachable through the
edge $u$–$v$, so $v$ is discovered before $u$ finishes, i.e. $v$ is a *descendant* of $u$. Therefore every non-tree edge
joins a vertex to one of its ancestors: a **back edge**. (This is the white-path theorem specialised to undirected graphs.)

**Observation 2 — a tree edge is a bridge iff its lower subtree has no escape.** Let $p \to v$ be a tree edge. Deleting it
disconnects $\text{subtree}(v)$ from $p$ unless some other edge leaves $\text{subtree}(v)$. Tree edges inside the subtree
stay inside; there are no cross edges; so the only possible escapes are back edges from some $x \in \text{subtree}(v)$ to a
proper ancestor of $v$ (that is, to $p$ or higher). Non-tree edges are never bridges (the tree path is an alternative).

So define the **low-link**

$$\text{low}[v] = \min\Big(\text{tin}[v],\ \min_{\substack{x \in \text{subtree}(v)\\ x\text{–}y \text{ back edge}}} \text{tin}[y]\Big),$$

the earliest-entered vertex reachable from the subtree of $v$ using tree edges downward and *one* back edge. An ancestor of
$v$ has a smaller `tin` than $v$, and any vertex with smaller `tin` that is adjacent via a back edge is an ancestor, hence:

- $p \to v$ is a **bridge** $\iff \text{low}[v] > \text{tin}[p]$ (no back edge reaches $p$ or above; the tree edge itself must not count).
- A **non-root** $p$ is a **cut vertex** $\iff$ some child $v$ has $\text{low}[v] \ge \text{tin}[p]$: that child's subtree can
  reach at best $p$ itself, so deleting $p$ strands it. Conversely if every child has an escape strictly above $p$, all child
  subtrees stay attached to $p$'s ancestors and deletion of $p$ disconnects nothing.
- The **root** is a cut vertex $\iff$ it has at least two DFS children (children subtrees cannot see each other: no cross edges).

`low` is computed bottom-up in the same DFS: $\text{low}[v] = \min(\text{tin}[v], \text{tin}[y] \text{ over back edges } v\text{–}y, \text{low}[c] \text{ over children } c)$.

**The two pitfalls that the derivation explains.**
1. *Which edge is "the parent edge"?* The tree edge itself must not be used as an escape. With parallel edges $p$–$v$ (twice),
   the *second* copy **is** an escape and neither copy is a bridge. So skip the parent **edge id**, not the parent vertex.
2. *`tin[y]`, not `low[y]`, for back edges.* For the cut-vertex test, `low[y]` may already include escapes found through
   $p$'s *other* children, making a stranded subtree look rescued. (For bridges alone `low[y]` happens to work; do not rely on it.)

**Equivalence classes.** "There are two edge-disjoint paths between $u$ and $v$" is an equivalence relation on vertices;
its classes are the **2-edge-connected components** (2ECC) = connected components after deleting all bridges. Contracting each
2ECC gives the **bridge tree** (a forest if the graph is disconnected) whose edges are exactly the bridges.

For vertices the right object lives on *edges*: two edges are equivalent if they lie on a common simple cycle. The classes are
the **biconnected components** or **blocks** (a bridge is a block of two vertices). Two blocks share at most one vertex, and
a shared vertex is a cut vertex. The **block-cut tree** has one node per block and one per vertex, joining a vertex to each
block containing it. It is a tree (a cycle in it would merge blocks), and *every path from $a$ to $b$ in the graph passes through
vertex $c$ iff $c$ lies on the tree path between $a$ and $b$*. That is how "can I avoid $c$?" queries become LCA queries.

**Finding blocks in the same DFS.** Keep a stack of visited vertices. When child $v$ of $p$ finishes with
$\text{low}[v] \ge \text{tin}[p]$, the vertices pushed since $v$ (still on the stack) plus $p$ form one block: pop them.
Each block is closed at the moment its "entrance" $p$ is confirmed to separate it.

**Orientation (Robbins' theorem).** A connected graph can be oriented to become strongly connected iff it has no bridge.
Constructive proof: orient tree edges downward and back edges upward. From the root you reach everyone; from any $v$, the
back edge from its subtree to above $v$ (exists since $\text{low}[v] < \text{tin}[v]$ when the parent edge is not a bridge) lets you
climb, and induction climbs to the root.

## 2. Formulas, definitions and identities

| Fact | Meaning / why |
|---|---|
| $\text{low}[v] = \min(\text{tin}[v],\ \min_{v\text{–}y\ \text{back}} \text{tin}[y],\ \min_{c\ \text{child}} \text{low}[c])$ | earliest ancestor reachable from $\text{subtree}(v)$ with one back edge |
| bridge $(p,v)$ $\iff \text{low}[v] > \text{tin}[p]$ $\iff \text{low}[v] = \text{tin}[v]$ | no back edge from the subtree reaches $p$ or above |
| non-root cut vertex $p \iff \exists$ child $v: \text{low}[v] \ge \text{tin}[p]$ | some subtree can reach at most $p$ |
| root cut vertex $\iff$ #children $\ge 2$ | children subtrees are only joined through the root |
| #bridges $\le n - 1$ | bridges form a forest (a cycle of bridges is impossible) |
| removing bridge $(p,v)$ in a connected graph disconnects $sz_v (n - sz_v)$ pairs | $sz_v$ = subtree size in the DFS tree |
| block-cut tree of a connected graph with $B$ blocks: $n + B$ nodes, $\sum_b |V(b)| = n + B - 1$ | it is a tree; edges = vertex–block incidences |
| min edges to add to make a connected graph 2-edge-connected $= \lceil L/2 \rceil$ ($0$ if one 2ECC) | $L$ = leaves of the bridge tree; proof in Example 5 |
| vertex version (biconnectivity augmentation) $= \max(\lceil L'/2\rceil,\ d-1)$ | $L'$ = leaf blocks, $d$ = most components one vertex deletion creates (Eswaran–Tarjan) |
| Whitney: $\kappa(G) \le \lambda(G) \le \delta(G)$ | vertex connectivity ≤ edge connectivity ≤ min degree |
| Robbins: strongly connected orientation exists $\iff$ connected and bridgeless | DFS orientation (tree down, back up) |
| A block is a single edge, or 2-vertex-connected (any two vertices on a common cycle) | Menger, see [flows](../12-Flows-and-Matching/02-min-cut-and-flow-modeling.md) |
| Block with $|E(b)| = |V(b)|$ is a simple cycle | a cactus is a graph where every block is an edge or a cycle |

Complexity: one DFS, $O(n + m)$ time and memory, for bridges, cut vertices, 2ECCs, blocks and the block-cut tree.
Block-cut-tree path queries: $O(\log n)$ each with binary-lifting LCA after $O(n \log n)$ preprocessing.

## 3. Implementation (C++ and Java)

Edges are stored as arc pairs: edge $i$ owns arcs $2i$ ($u \to v$) and $2i+1$ ($v \to u$), so the reverse of arc $a$ is
`a ^ 1` and the edge id is `a >> 1`. The DFS is iterative (a per-vertex edge iterator replaces the call stack), so it is safe
for $n = 10^6$ in both languages. `run()` fills `tin`, `low`, `isBridge[edge]`, `isCut[vertex]` and the 2ECC id `comp[vertex]`.

```cpp
struct LowLink {
    int n, m = 0;
    vector<int> head, nxt, to;
    vector<int> tin, low, comp;
    vector<char> isBridge, isCut;
    int compCount = 0;
    explicit LowLink(int n) : n(n), head(n, -1) {}
    void addEdge(int u, int v) {
        to.push_back(v); nxt.push_back(head[u]); head[u] = 2 * m;
        to.push_back(u); nxt.push_back(head[v]); head[v] = 2 * m + 1;
        m++;
    }
    void run() {
        tin.assign(n, -1); low.assign(n, 0); isCut.assign(n, 0); isBridge.assign(m, 0);
        vector<int> it(n), parArc(n, -1), stk;
        int timer = 0;
        for (int s = 0; s < n; s++) {
            if (tin[s] != -1) continue;
            int rootChildren = 0;
            tin[s] = low[s] = timer++; it[s] = head[s]; stk.push_back(s);
            while (!stk.empty()) {
                int v = stk.back();
                if (it[v] != -1) {
                    int a = it[v]; it[v] = nxt[a];
                    if ((a ^ 1) == parArc[v]) continue;             // skip the parent EDGE, not the parent vertex
                    int w = to[a];
                    if (tin[w] == -1) {
                        parArc[w] = a; tin[w] = low[w] = timer++; it[w] = head[w]; stk.push_back(w);
                        if (v == s) rootChildren++;
                    } else low[v] = min(low[v], tin[w]);            // back edge: tin, not low
                } else {
                    stk.pop_back();
                    if (parArc[v] == -1) continue;
                    int p = to[parArc[v] ^ 1];
                    low[p] = min(low[p], low[v]);
                    if (low[v] > tin[p]) isBridge[parArc[v] >> 1] = 1;
                    if (p != s && low[v] >= tin[p]) isCut[p] = 1;
                }
            }
            if (rootChildren >= 2) isCut[s] = 1;
        }
        // 2-edge-connected components: flood fill that never crosses a bridge
        comp.assign(n, -1); compCount = 0;
        for (int s = 0; s < n; s++) {
            if (comp[s] != -1) continue;
            comp[s] = compCount; stk.assign(1, s);
            while (!stk.empty()) {
                int v = stk.back(); stk.pop_back();
                for (int a = head[v]; a != -1; a = nxt[a])
                    if (!isBridge[a >> 1] && comp[to[a]] == -1) { comp[to[a]] = compCount; stk.push_back(to[a]); }
            }
            compCount++;
        }
    }
};
```

```java
static class LowLink {
    final int n; int m = 0;
    int[] head, nxt = new int[16], to = new int[16];
    int[] tin, low, comp; boolean[] isBridge, isCut; int compCount;
    LowLink(int n) { this.n = n; head = new int[n]; Arrays.fill(head, -1); }
    void addEdge(int u, int v) {
        if (2 * m + 2 > to.length) { to = Arrays.copyOf(to, to.length * 2); nxt = Arrays.copyOf(nxt, nxt.length * 2); }
        to[2 * m] = v; nxt[2 * m] = head[u]; head[u] = 2 * m;
        to[2 * m + 1] = u; nxt[2 * m + 1] = head[v]; head[v] = 2 * m + 1;
        m++;
    }
    void run() {
        tin = new int[n]; low = new int[n]; isCut = new boolean[n]; isBridge = new boolean[m];
        Arrays.fill(tin, -1);
        int[] it = new int[n], parArc = new int[n], stk = new int[n];
        Arrays.fill(parArc, -1);
        int timer = 0;
        for (int s = 0; s < n; s++) {
            if (tin[s] != -1) continue;
            int rootChildren = 0, sp = 0;
            tin[s] = low[s] = timer++; it[s] = head[s]; stk[sp++] = s;
            while (sp > 0) {
                int v = stk[sp - 1];
                if (it[v] != -1) {
                    int a = it[v]; it[v] = nxt[a];
                    if ((a ^ 1) == parArc[v]) continue;
                    int w = to[a];
                    if (tin[w] == -1) {
                        parArc[w] = a; tin[w] = low[w] = timer++; it[w] = head[w]; stk[sp++] = w;
                        if (v == s) rootChildren++;
                    } else low[v] = Math.min(low[v], tin[w]);
                } else {
                    sp--;
                    if (parArc[v] == -1) continue;
                    int p = to[parArc[v] ^ 1];
                    low[p] = Math.min(low[p], low[v]);
                    if (low[v] > tin[p]) isBridge[parArc[v] >> 1] = true;
                    if (p != s && low[v] >= tin[p]) isCut[p] = true;
                }
            }
            if (rootChildren >= 2) isCut[s] = true;
        }
        comp = new int[n]; Arrays.fill(comp, -1); compCount = 0;
        for (int s = 0; s < n; s++) {
            if (comp[s] != -1) continue;
            int sp = 0; comp[s] = compCount; stk[sp++] = s;
            while (sp > 0) {
                int v = stk[--sp];
                for (int a = head[v]; a != -1; a = nxt[a])
                    if (!isBridge[a >> 1] && comp[to[a]] == -1) { comp[to[a]] = compCount; stk[sp++] = to[a]; }
            }
            compCount++;
        }
    }
}
```

**Block-cut tree.** Same DFS plus a vertex stack `vs`: when child $v$ of $p$ finishes with $\text{low}[v] \ge \text{tin}[p]$,
create a block node, pop `vs` down to and including $v$ (attaching each popped vertex to the block), then attach $p$. Tree nodes
`0..n-1` are the original vertices, nodes `n, n+1, ...` are blocks; a vertex is a cut vertex iff its tree degree is at least 2, and an
isolated vertex stays an isolated tree node. The complete, tested C++ and Java builder (with LCA queries on top) is the solution
of Example 4 in §5, so it is not repeated here.

## 4. Recognising the pattern

| Statement signal | Think |
|---|---|
| "critical road / link", "single point of failure", "after closing one road some cities can't communicate" | bridges |
| "critical city / server", "removing one vertex disconnects" | articulation points |
| "for each edge, how many pairs become disconnected" | bridges + subtree sizes $sz_v(n - sz_v)$ |
| "orient every road so that everyone can reach everyone" | Robbins: possible iff bridgeless; DFS orientation |
| "maximum number of bosses/bridges on a path you are forced to pass" | bridge tree + diameter |
| "must every path from $a$ to $b$ pass through $c$?" (undirected) | block-cut tree + LCA |
| same question, **directed** graph, from a fixed source | dominator tree, not BCC (CSES Critical Cities) |
| "edges lying on exactly one simple cycle", "cactus" | blocks with $|E| = |V|$; see [functional & special graphs](10-functional-graphs-and-special-graphs.md) |
| "add fewest edges so no single edge failure disconnects" | $\lceil L/2 \rceil$ on the bridge tree |
| "two edge-disjoint / vertex-disjoint paths between every pair" | 2ECC / biconnected; for *specific* $s,t$ and $k>2$ use [flows (Menger)](../12-Flows-and-Matching/02-min-cut-and-flow-modeling.md) |

Common confusions: SCCs ([file 05](05-scc-and-condensation.md)) are the *directed* analogue; 2-edge-connected ≠ biconnected
(a figure-eight — two triangles sharing a vertex — is 2-edge-connected but has a cut vertex).

## 5. Worked examples (graded)

### Example 1 — Necessary Roads  ·  ★ ≈1700

- **Source:** [CSES 2076 · Necessary Roads](https://cses.fi/problemset/task/2076)
- **Difficulty:** ≈1700 (est.)
- **Problem:** An undirected graph with $n \le 10^5$ cities and $m \le 2\cdot10^5$ roads. A road is *necessary* if removing it
  leaves some pair of cities unable to reach each other. Print the number of necessary roads and list them.
  (Any order is accepted; we print each as `a b` with $a < b$, sorted, so the output is deterministic.)
- **Thinking from first principles:** "necessary" = bridge. Deleting each road and re-checking is $O(m(n+m)) \approx 6\cdot10^{10}$.
  One DFS with low-links answers all edges at once. Multi-edges are possible in general graphs, so skip the parent by arc id.

<details><summary>Solution</summary>

Iterative low-link DFS; collect tree edges with $\text{low}[v] > \text{tin}[p]$; sort. $O((n+m)\log m)$ due to the sort.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<int> head(n + 1, -1), nxt(2 * m), to(2 * m);
    for (int i = 0; i < m; i++) {
        int a, b; cin >> a >> b;
        to[2 * i] = b; nxt[2 * i] = head[a]; head[a] = 2 * i;
        to[2 * i + 1] = a; nxt[2 * i + 1] = head[b]; head[b] = 2 * i + 1;
    }
    vector<int> tin(n + 1, -1), low(n + 1), parArc(n + 1, -1), it(n + 1), stk;
    vector<pair<int,int>> bridges;
    int timer = 0;
    for (int s = 1; s <= n; s++) {
        if (tin[s] != -1) continue;
        tin[s] = low[s] = timer++; it[s] = head[s]; stk.push_back(s);
        while (!stk.empty()) {
            int v = stk.back();
            if (it[v] != -1) {
                int a = it[v]; it[v] = nxt[a];
                if ((a ^ 1) == parArc[v]) continue;
                int w = to[a];
                if (tin[w] == -1) { parArc[w] = a; tin[w] = low[w] = timer++; it[w] = head[w]; stk.push_back(w); }
                else low[v] = min(low[v], tin[w]);
            } else {
                stk.pop_back();
                if (parArc[v] == -1) continue;
                int p = to[parArc[v] ^ 1];
                low[p] = min(low[p], low[v]);
                if (low[v] > tin[p]) bridges.push_back({min(p, v), max(p, v)});
            }
        }
    }
    sort(bridges.begin(), bridges.end());
    cout << bridges.size() << "\n";
    for (auto [a, b] : bridges) cout << a << " " << b << "\n";
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
        int[] tin = new int[n + 1], low = new int[n + 1], parArc = new int[n + 1], it = new int[n + 1], stk = new int[n + 1];
        Arrays.fill(tin, -1); Arrays.fill(parArc, -1);
        long[] found = new long[n];
        int cnt = 0, timer = 0;
        for (int s = 1; s <= n; s++) {
            if (tin[s] != -1) continue;
            int sp = 0;
            tin[s] = low[s] = timer++; it[s] = head[s]; stk[sp++] = s;
            while (sp > 0) {
                int v = stk[sp - 1];
                if (it[v] != -1) {
                    int a = it[v]; it[v] = nxt[a];
                    if ((a ^ 1) == parArc[v]) continue;
                    int w = to[a];
                    if (tin[w] == -1) { parArc[w] = a; tin[w] = low[w] = timer++; it[w] = head[w]; stk[sp++] = w; }
                    else low[v] = Math.min(low[v], tin[w]);
                } else {
                    sp--;
                    if (parArc[v] == -1) continue;
                    int p = to[parArc[v] ^ 1];
                    low[p] = Math.min(low[p], low[v]);
                    if (low[v] > tin[p]) found[cnt++] = ((long) Math.min(p, v) << 20) | Math.max(p, v);  // pack (a,b) to sort fast
                }
            }
        }
        Arrays.sort(found, 0, cnt);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(cnt);
        for (int i = 0; i < cnt; i++) out.println((found[i] >> 20) + " " + (found[i] & ((1 << 20) - 1)));
        out.flush();
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
2
3 4
4 5
-->
<!-- test
in:
2 2
1 2
2 1
out:
0
-->
<!-- test
in:
4 3
2 1
3 1
4 3
out:
3
1 2
1 3
3 4
-->
<!-- test
in:
6 7
1 2
2 3
3 1
4 5
5 6
6 4
3 4
out:
1
3 4
-->

### Example 2 — Necessary Cities  ·  ★ ≈1700

- **Source:** [CSES 2077 · Necessary Cities](https://cses.fi/problemset/task/2077)
- **Difficulty:** ≈1700 (est.)
- **Problem:** Same graph format. A city is *necessary* if removing it (and its roads) disconnects some remaining pair.
  Print how many there are and list them in increasing order.
- **Thinking from first principles:** "necessary city" = articulation point. A tempting shortcut — "endpoints of bridges are
  cut vertices" — is wrong both ways: a bridge endpoint of degree 1 is not a cut vertex, and the shared vertex of two triangles
  is a cut vertex without any bridge. Use the child test $\text{low}[v] \ge \text{tin}[p]$ and the root rule.

<details><summary>Solution</summary>

Same DFS; mark $p$ when a child satisfies $\text{low}[v] \ge \text{tin}[p]$ (non-root) and count root children. $O(n+m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<int> head(n + 1, -1), nxt(2 * m), to(2 * m);
    for (int i = 0; i < m; i++) {
        int a, b; cin >> a >> b;
        to[2 * i] = b; nxt[2 * i] = head[a]; head[a] = 2 * i;
        to[2 * i + 1] = a; nxt[2 * i + 1] = head[b]; head[b] = 2 * i + 1;
    }
    vector<int> tin(n + 1, -1), low(n + 1), parArc(n + 1, -1), it(n + 1), stk;
    vector<char> cut(n + 1, 0);
    int timer = 0;
    for (int s = 1; s <= n; s++) {
        if (tin[s] != -1) continue;
        int rootChildren = 0;
        tin[s] = low[s] = timer++; it[s] = head[s]; stk.push_back(s);
        while (!stk.empty()) {
            int v = stk.back();
            if (it[v] != -1) {
                int a = it[v]; it[v] = nxt[a];
                if ((a ^ 1) == parArc[v]) continue;
                int w = to[a];
                if (tin[w] == -1) {
                    parArc[w] = a; tin[w] = low[w] = timer++; it[w] = head[w]; stk.push_back(w);
                    if (v == s) rootChildren++;
                } else low[v] = min(low[v], tin[w]);
            } else {
                stk.pop_back();
                if (parArc[v] == -1) continue;
                int p = to[parArc[v] ^ 1];
                low[p] = min(low[p], low[v]);
                if (p != s && low[v] >= tin[p]) cut[p] = 1;
            }
        }
        if (rootChildren >= 2) cut[s] = 1;
    }
    vector<int> res;
    for (int v = 1; v <= n; v++) if (cut[v]) res.push_back(v);
    cout << res.size() << "\n";
    for (int i = 0; i < (int)res.size(); i++) cout << res[i] << " \n"[i + 1 == (int)res.size()];
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
        int[] tin = new int[n + 1], low = new int[n + 1], parArc = new int[n + 1], it = new int[n + 1], stk = new int[n + 1];
        boolean[] cut = new boolean[n + 1];
        Arrays.fill(tin, -1); Arrays.fill(parArc, -1);
        int timer = 0;
        for (int s = 1; s <= n; s++) {
            if (tin[s] != -1) continue;
            int sp = 0, rootChildren = 0;
            tin[s] = low[s] = timer++; it[s] = head[s]; stk[sp++] = s;
            while (sp > 0) {
                int v = stk[sp - 1];
                if (it[v] != -1) {
                    int a = it[v]; it[v] = nxt[a];
                    if ((a ^ 1) == parArc[v]) continue;
                    int w = to[a];
                    if (tin[w] == -1) {
                        parArc[w] = a; tin[w] = low[w] = timer++; it[w] = head[w]; stk[sp++] = w;
                        if (v == s) rootChildren++;
                    } else low[v] = Math.min(low[v], tin[w]);
                } else {
                    sp--;
                    if (parArc[v] == -1) continue;
                    int p = to[parArc[v] ^ 1];
                    low[p] = Math.min(low[p], low[v]);
                    if (p != s && low[v] >= tin[p]) cut[p] = true;
                }
            }
            if (rootChildren >= 2) cut[s] = true;
        }
        StringBuilder sb = new StringBuilder();
        int k = 0;
        for (int v = 1; v <= n; v++) if (cut[v]) { k++; sb.append(v).append(' '); }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(k);
        out.println(sb.toString().trim());
        out.flush();
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
2
3 4
-->
<!-- test
in:
4 4
1 2
2 3
3 4
4 1
out:
0
-->
<!-- test
in:
5 6
1 2
2 3
3 1
3 4
4 5
5 3
out:
1
3
-->
<!-- test
in:
2 1
1 2
out:
0
-->

### Example 3 — We Need More Bosses  ·  ★ 2100

- **Source:** [CF 1000E · We Need More Bosses](https://codeforces.com/problemset/problem/1000/E) — 2100
- **Difficulty:** 2100
- **Problem:** A connected undirected graph ($n, m \le 3\cdot10^5$, no parallel edges). For a choice of start $s$ and end $t$,
  an edge is a "boss" if *every* $s$–$t$ path uses it. Choose $s, t$ to maximise the number of bosses; print the maximum.
- **Thinking from first principles:** An edge that every $s$–$t$ path must use is a bridge separating $s$ from $t$. Inside a
  2ECC there is always a detour, so only bridges count. Contract each 2ECC to a node: the graph becomes the bridge tree, and the
  edges forced between $s$ and $t$ are exactly the tree edges on the path between their components. Maximise path length
  over pairs = **tree diameter** (two BFS passes, proof in [tree basics](../10-Trees/01-tree-basics-diameter-center-euler-tour.md)).

<details><summary>Solution</summary>

Bridges → 2ECC ids by flood fill avoiding bridges → bridge tree → BFS from any node, then BFS from the farthest node. $O(n+m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<int> head(n, -1), nxt(2 * m), to(2 * m), eu(m), ev(m);
    for (int i = 0; i < m; i++) {
        cin >> eu[i] >> ev[i]; eu[i]--; ev[i]--;
        to[2 * i] = ev[i]; nxt[2 * i] = head[eu[i]]; head[eu[i]] = 2 * i;
        to[2 * i + 1] = eu[i]; nxt[2 * i + 1] = head[ev[i]]; head[ev[i]] = 2 * i + 1;
    }
    vector<int> tin(n, -1), low(n), parArc(n, -1), it(n), stk;
    vector<char> bridge(m, 0);
    int timer = 0;
    tin[0] = low[0] = timer++; it[0] = head[0]; stk.push_back(0);   // graph is connected
    while (!stk.empty()) {
        int v = stk.back();
        if (it[v] != -1) {
            int a = it[v]; it[v] = nxt[a];
            if ((a ^ 1) == parArc[v]) continue;
            int w = to[a];
            if (tin[w] == -1) { parArc[w] = a; tin[w] = low[w] = timer++; it[w] = head[w]; stk.push_back(w); }
            else low[v] = min(low[v], tin[w]);
        } else {
            stk.pop_back();
            if (parArc[v] == -1) continue;
            int p = to[parArc[v] ^ 1];
            low[p] = min(low[p], low[v]);
            if (low[v] > tin[p]) bridge[parArc[v] >> 1] = 1;
        }
    }
    vector<int> comp(n, -1);
    int C = 0;
    for (int s = 0; s < n; s++) {
        if (comp[s] != -1) continue;
        comp[s] = C; stk.assign(1, s);
        while (!stk.empty()) {
            int v = stk.back(); stk.pop_back();
            for (int a = head[v]; a != -1; a = nxt[a])
                if (!bridge[a >> 1] && comp[to[a]] == -1) { comp[to[a]] = C; stk.push_back(to[a]); }
        }
        C++;
    }
    vector<vector<int>> tree(C);
    for (int i = 0; i < m; i++)
        if (bridge[i]) { tree[comp[eu[i]]].push_back(comp[ev[i]]); tree[comp[ev[i]]].push_back(comp[eu[i]]); }
    auto bfs = [&](int src, vector<int>& d) {
        d.assign(C, -1); d[src] = 0;
        queue<int> q; q.push(src);
        int last = src;
        while (!q.empty()) {
            int v = q.front(); q.pop(); last = v;
            for (int w : tree[v]) if (d[w] == -1) { d[w] = d[v] + 1; q.push(w); }
        }
        return last;                                  // BFS pops in distance order, so this is a farthest node
    };
    vector<int> d;
    int far = bfs(0, d);
    int other = bfs(far, d);
    cout << d[other] << "\n";
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
    static int C;
    static int[] th, tn, tt;

    static int bfs(int src, int[] d) {
        Arrays.fill(d, -1); d[src] = 0;
        int[] q = new int[C]; int qh = 0, qt = 0; q[qt++] = src;
        int last = src;
        while (qh < qt) {
            int v = q[qh++]; last = v;
            for (int a = th[v]; a != -1; a = tn[a]) if (d[tt[a]] == -1) { d[tt[a]] = d[v] + 1; q[qt++] = tt[a]; }
        }
        return last;
    }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt();
        int[] head = new int[n], nxt = new int[2 * m], to = new int[2 * m], eu = new int[m], ev = new int[m];
        Arrays.fill(head, -1);
        for (int i = 0; i < m; i++) {
            eu[i] = nextInt() - 1; ev[i] = nextInt() - 1;
            to[2 * i] = ev[i]; nxt[2 * i] = head[eu[i]]; head[eu[i]] = 2 * i;
            to[2 * i + 1] = eu[i]; nxt[2 * i + 1] = head[ev[i]]; head[ev[i]] = 2 * i + 1;
        }
        int[] tin = new int[n], low = new int[n], parArc = new int[n], it = new int[n], stk = new int[n];
        boolean[] bridge = new boolean[m];
        Arrays.fill(tin, -1); Arrays.fill(parArc, -1);
        int timer = 0, sp = 0;
        tin[0] = low[0] = timer++; it[0] = head[0]; stk[sp++] = 0;
        while (sp > 0) {
            int v = stk[sp - 1];
            if (it[v] != -1) {
                int a = it[v]; it[v] = nxt[a];
                if ((a ^ 1) == parArc[v]) continue;
                int w = to[a];
                if (tin[w] == -1) { parArc[w] = a; tin[w] = low[w] = timer++; it[w] = head[w]; stk[sp++] = w; }
                else low[v] = Math.min(low[v], tin[w]);
            } else {
                sp--;
                if (parArc[v] == -1) continue;
                int p = to[parArc[v] ^ 1];
                low[p] = Math.min(low[p], low[v]);
                if (low[v] > tin[p]) bridge[parArc[v] >> 1] = true;
            }
        }
        int[] comp = new int[n];
        Arrays.fill(comp, -1);
        C = 0;
        for (int s = 0; s < n; s++) {
            if (comp[s] != -1) continue;
            sp = 0; comp[s] = C; stk[sp++] = s;
            while (sp > 0) {
                int v = stk[--sp];
                for (int a = head[v]; a != -1; a = nxt[a])
                    if (!bridge[a >> 1] && comp[to[a]] == -1) { comp[to[a]] = C; stk[sp++] = to[a]; }
            }
            C++;
        }
        th = new int[C]; tn = new int[2 * m]; tt = new int[2 * m];
        Arrays.fill(th, -1);
        int e = 0;
        for (int i = 0; i < m; i++) if (bridge[i]) {
            int x = comp[eu[i]], y = comp[ev[i]];
            tt[e] = y; tn[e] = th[x]; th[x] = e++;
            tt[e] = x; tn[e] = th[y]; th[y] = e++;
        }
        int[] d = new int[C];
        int far = bfs(0, d);
        int other = bfs(far, d);
        System.out.println(d[other]);
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
4 1
5 2
out:
2
-->
<!-- test
in:
4 3
1 2
2 3
3 4
out:
3
-->
<!-- test
in:
3 3
1 2
2 3
3 1
out:
0
-->
<!-- test
in:
1 0
out:
0
-->

### Example 4 — Avoiding a city (block-cut tree queries)  ·  ★ ≈2300

- **Source:** Original problem (the idea behind [CSES 1705 · Forbidden Cities](https://cses.fi/problemset/task/1705)).
- **Difficulty:** ≈2300 (est.)
- **Problem:** Undirected graph, $n, m, q \le 2\cdot10^5$ (possibly disconnected, multi-edges allowed). Each query $(a, b, c)$
  asks: is there a walk from $a$ to $b$ that never visits $c$? (If $c = a$ or $c = b$ the answer is `NO`; if $a = b \ne c$ it is `YES`.)
- **Thinking from first principles:** Per query BFS is $O(q(n+m))$. Removing $c$ only matters if $c$ is a cut vertex, and
  then only if $a$ and $b$ end up on different sides. "Sides" are described by blocks: the block-cut tree turns *every $a$–$b$
  path passes through $c$* into *$c$ lies on the tree path between nodes $a$ and $b$* (any graph path walks through a sequence of
  blocks that must include the tree path's blocks, and consecutive blocks on the tree path share exactly the cut vertex between
  them). With all vertices as tree nodes, $c = a$ or $c = b$ is just the endpoint case of the same test.
  "Is $c$ on path$(a,b)$" in a rooted tree: $c$ is an ancestor of $a$ or of $b$, and $\text{lca}(a,b)$ is an ancestor of $c$.

<details><summary>Solution</summary>

Build the block-cut forest ($\le 2n$ nodes), root every tree, compute Euler `tin/tout` and binary lifting. Query: if $a, b$
lie in different trees → `NO`; otherwise `NO` iff $c$ is on the tree path. $O((n+m) + (n+q)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m, q;
    cin >> n >> m >> q;
    vector<int> head(n, -1), nxt(2 * m), to(2 * m);
    for (int i = 0; i < m; i++) {
        int a, b; cin >> a >> b; a--; b--;
        to[2 * i] = b; nxt[2 * i] = head[a]; head[a] = 2 * i;
        to[2 * i + 1] = a; nxt[2 * i + 1] = head[b]; head[b] = 2 * i + 1;
    }
    // block-cut forest: nodes [0,n) vertices, [n, N) blocks
    vector<int> tin(n, -1), low(n), parArc(n, -1), it(n), dfs, vs;
    vector<vector<int>> tree(n);
    int timer = 0;
    for (int s = 0; s < n; s++) {
        if (tin[s] != -1) continue;
        tin[s] = low[s] = timer++; it[s] = head[s]; dfs.push_back(s); vs.push_back(s);
        while (!dfs.empty()) {
            int v = dfs.back();
            if (it[v] != -1) {
                int a = it[v]; it[v] = nxt[a];
                if ((a ^ 1) == parArc[v]) continue;
                int w = to[a];
                if (tin[w] == -1) { parArc[w] = a; tin[w] = low[w] = timer++; it[w] = head[w]; dfs.push_back(w); vs.push_back(w); }
                else low[v] = min(low[v], tin[w]);
            } else {
                dfs.pop_back();
                if (parArc[v] == -1) { vs.pop_back(); continue; }
                int p = to[parArc[v] ^ 1];
                low[p] = min(low[p], low[v]);
                if (low[v] >= tin[p]) {
                    int b = tree.size(); tree.emplace_back();
                    while (true) {
                        int x = vs.back(); vs.pop_back();
                        tree[b].push_back(x); tree[x].push_back(b);
                        if (x == v) break;
                    }
                    tree[b].push_back(p); tree[p].push_back(b);
                }
            }
        }
    }
    int N = tree.size(), LOG = 1;
    while ((1 << LOG) < N) LOG++;
    vector<vector<int>> up(LOG, vector<int>(N));
    vector<int> tin2(N, -1), tout2(N), root(N), itr(N, 0);
    timer = 0;
    for (int s = 0; s < N; s++) {
        if (tin2[s] != -1) continue;
        vector<int> st = {s};
        tin2[s] = timer++; up[0][s] = s; root[s] = s;
        while (!st.empty()) {
            int v = st.back();
            if (itr[v] < (int)tree[v].size()) {
                int w = tree[v][itr[v]++];
                if (tin2[w] == -1) { tin2[w] = timer++; up[0][w] = v; root[w] = s; st.push_back(w); }
            } else { tout2[v] = timer++; st.pop_back(); }
        }
    }
    for (int k = 1; k < LOG; k++)
        for (int v = 0; v < N; v++) up[k][v] = up[k - 1][up[k - 1][v]];
    auto anc = [&](int u, int v) { return tin2[u] <= tin2[v] && tout2[v] <= tout2[u]; };   // u is an ancestor of v (or u == v)
    auto lca = [&](int a, int b) {
        if (anc(a, b)) return a;
        if (anc(b, a)) return b;
        for (int k = LOG - 1; k >= 0; k--) if (!anc(up[k][a], b)) a = up[k][a];
        return up[0][a];
    };
    string out;
    while (q--) {
        int a, b, c; cin >> a >> b >> c; a--; b--; c--;
        bool blocked;
        if (root[a] != root[b]) blocked = true;
        else blocked = (anc(c, a) || anc(c, b)) && anc(lca(a, b), c);
        out += blocked ? "NO\n" : "YES\n";
    }
    cout << out;
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
    static int[] tin2, tout2;
    static int[][] up;
    static int LOG;
    static boolean anc(int u, int v) { return tin2[u] <= tin2[v] && tout2[v] <= tout2[u]; }
    static int lca(int a, int b) {
        if (anc(a, b)) return a;
        if (anc(b, a)) return b;
        for (int k = LOG - 1; k >= 0; k--) if (!anc(up[k][a], b)) a = up[k][a];
        return up[0][a];
    }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt(), q = nextInt();
        int[] head = new int[n], nxt = new int[2 * m], to = new int[2 * m];
        Arrays.fill(head, -1);
        for (int i = 0; i < m; i++) {
            int a = nextInt() - 1, b = nextInt() - 1;
            to[2 * i] = b; nxt[2 * i] = head[a]; head[a] = 2 * i;
            to[2 * i + 1] = a; nxt[2 * i + 1] = head[b]; head[b] = 2 * i + 1;
        }
        int[] tin = new int[n], low = new int[n], parArc = new int[n], it = new int[n], dfs = new int[n], vs = new int[n];
        Arrays.fill(tin, -1); Arrays.fill(parArc, -1);
        int[] tu = new int[2 * n + 2], tv = new int[2 * n + 2];
        int te = 0, N = n, timer = 0;
        for (int s = 0; s < n; s++) {
            if (tin[s] != -1) continue;
            int dp = 0, vp = 0;
            tin[s] = low[s] = timer++; it[s] = head[s]; dfs[dp++] = s; vs[vp++] = s;
            while (dp > 0) {
                int v = dfs[dp - 1];
                if (it[v] != -1) {
                    int a = it[v]; it[v] = nxt[a];
                    if ((a ^ 1) == parArc[v]) continue;
                    int w = to[a];
                    if (tin[w] == -1) { parArc[w] = a; tin[w] = low[w] = timer++; it[w] = head[w]; dfs[dp++] = w; vs[vp++] = w; }
                    else low[v] = Math.min(low[v], tin[w]);
                } else {
                    dp--;
                    if (parArc[v] == -1) { vp--; continue; }
                    int p = to[parArc[v] ^ 1];
                    low[p] = Math.min(low[p], low[v]);
                    if (low[v] >= tin[p]) {
                        int b = N++;
                        while (true) { int x = vs[--vp]; tu[te] = x; tv[te++] = b; if (x == v) break; }
                        tu[te] = p; tv[te++] = b;
                    }
                }
            }
        }
        int[] th = new int[N], tn = new int[2 * te], tt = new int[2 * te];
        Arrays.fill(th, -1);
        for (int i = 0; i < te; i++) {
            tt[2 * i] = tv[i]; tn[2 * i] = th[tu[i]]; th[tu[i]] = 2 * i;
            tt[2 * i + 1] = tu[i]; tn[2 * i + 1] = th[tv[i]]; th[tv[i]] = 2 * i + 1;
        }
        LOG = 1;
        while ((1 << LOG) < N) LOG++;
        up = new int[LOG][N];
        tin2 = new int[N]; tout2 = new int[N];
        int[] root = new int[N], itr = new int[N], st = new int[N];
        Arrays.fill(tin2, -1);
        for (int v = 0; v < N; v++) itr[v] = th[v];
        timer = 0;
        for (int s = 0; s < N; s++) {
            if (tin2[s] != -1) continue;
            int sp = 0; st[sp++] = s;
            tin2[s] = timer++; up[0][s] = s; root[s] = s;
            while (sp > 0) {
                int v = st[sp - 1];
                if (itr[v] != -1) {
                    int w = tt[itr[v]]; itr[v] = tn[itr[v]];
                    if (tin2[w] == -1) { tin2[w] = timer++; up[0][w] = v; root[w] = s; st[sp++] = w; }
                } else { tout2[v] = timer++; sp--; }
            }
        }
        for (int k = 1; k < LOG; k++)
            for (int v = 0; v < N; v++) up[k][v] = up[k - 1][up[k - 1][v]];
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < q; i++) {
            int a = nextInt() - 1, b = nextInt() - 1, c = nextInt() - 1;
            boolean blocked = root[a] != root[b] || ((anc(c, a) || anc(c, b)) && anc(lca(a, b), c));
            sb.append(blocked ? "NO\n" : "YES\n");
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
8 8 8
1 2
2 3
3 1
3 4
4 5
5 6
6 4
6 7
1 7 4
1 7 5
1 2 3
1 4 3
2 2 5
1 8 2
5 6 5
7 6 6
out:
NO
YES
YES
NO
YES
NO
NO
NO
-->
<!-- test
in:
3 2 3
1 2
2 3
1 3 2
1 2 3
3 1 1
out:
NO
YES
NO
-->
<!-- test
in:
4 5 3
1 2
2 3
3 4
4 1
1 3
2 4 1
2 4 3
1 1 2
out:
YES
YES
YES
-->

### Example 5 — Fewest new roads for single-failure tolerance  ·  ★ ≈2000

- **Source:** Original problem (the counting half of [CSES 1704 · Network Renovation](https://cses.fi/problemset/task/1704)).
- **Difficulty:** ≈2000 (est.)
- **Problem:** A connected undirected graph ($n, m \le 2\cdot10^5$). Add the fewest new edges (parallel to existing ones allowed)
  so that the graph has no bridge. Print that number.
- **Thinking from first principles:** Inside a 2ECC nothing needs fixing, so contract: we get the bridge tree $T$ with $L$ leaves.
  *Lower bound:* a leaf component hangs on a single bridge; unless some new edge has an endpoint in that leaf, that bridge
  stays a bridge. Each new edge has two endpoints, so at least $\lceil L/2 \rceil$ edges are needed.
  *Upper bound:* list the leaves in DFS order $\ell_0, \dots, \ell_{L-1}$ and join $\ell_i$ with $\ell_{i+\lfloor L/2\rfloor}$
  (plus one extra edge from the last leaf if $L$ is odd). Any tree edge $e$ splits the leaves into a contiguous block of the DFS
  order (the leaves below $e$) and the rest. If the block has at most $L/2$ leaves, its first leaf's partner is $\lfloor L/2\rfloor$
  positions away, hence outside; otherwise the complementary (cyclically contiguous) block is the small one and the same argument
  applies to it. Either way a new edge crosses $e$, so $e$ lies on a cycle. Hence the answer is exactly $\lceil L/2\rceil$
  (and $0$ when $T$ is a single node; a tree with $\ge 2$ nodes has $L \ge 2$).

<details><summary>Solution</summary>

Bridges → 2ECC ids → degree of every component in the bridge tree → count degree-1 components. $O(n+m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<int> head(n, -1), nxt(2 * m), to(2 * m), eu(m), ev(m);
    for (int i = 0; i < m; i++) {
        cin >> eu[i] >> ev[i]; eu[i]--; ev[i]--;
        to[2 * i] = ev[i]; nxt[2 * i] = head[eu[i]]; head[eu[i]] = 2 * i;
        to[2 * i + 1] = eu[i]; nxt[2 * i + 1] = head[ev[i]]; head[ev[i]] = 2 * i + 1;
    }
    vector<int> tin(n, -1), low(n), parArc(n, -1), it(n), stk;
    vector<char> bridge(m, 0);
    int timer = 0;
    tin[0] = low[0] = timer++; it[0] = head[0]; stk.push_back(0);
    while (!stk.empty()) {
        int v = stk.back();
        if (it[v] != -1) {
            int a = it[v]; it[v] = nxt[a];
            if ((a ^ 1) == parArc[v]) continue;
            int w = to[a];
            if (tin[w] == -1) { parArc[w] = a; tin[w] = low[w] = timer++; it[w] = head[w]; stk.push_back(w); }
            else low[v] = min(low[v], tin[w]);
        } else {
            stk.pop_back();
            if (parArc[v] == -1) continue;
            int p = to[parArc[v] ^ 1];
            low[p] = min(low[p], low[v]);
            if (low[v] > tin[p]) bridge[parArc[v] >> 1] = 1;
        }
    }
    vector<int> comp(n, -1);
    int C = 0;
    for (int s = 0; s < n; s++) {
        if (comp[s] != -1) continue;
        comp[s] = C; stk.assign(1, s);
        while (!stk.empty()) {
            int v = stk.back(); stk.pop_back();
            for (int a = head[v]; a != -1; a = nxt[a])
                if (!bridge[a >> 1] && comp[to[a]] == -1) { comp[to[a]] = C; stk.push_back(to[a]); }
        }
        C++;
    }
    vector<int> deg(C, 0);
    for (int i = 0; i < m; i++) if (bridge[i]) { deg[comp[eu[i]]]++; deg[comp[ev[i]]]++; }
    int leaves = count(deg.begin(), deg.end(), 1);
    cout << (C == 1 ? 0 : (leaves + 1) / 2) << "\n";
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
        int[] head = new int[n], nxt = new int[2 * m], to = new int[2 * m], eu = new int[m], ev = new int[m];
        Arrays.fill(head, -1);
        for (int i = 0; i < m; i++) {
            eu[i] = nextInt() - 1; ev[i] = nextInt() - 1;
            to[2 * i] = ev[i]; nxt[2 * i] = head[eu[i]]; head[eu[i]] = 2 * i;
            to[2 * i + 1] = eu[i]; nxt[2 * i + 1] = head[ev[i]]; head[ev[i]] = 2 * i + 1;
        }
        int[] tin = new int[n], low = new int[n], parArc = new int[n], it = new int[n], stk = new int[n];
        boolean[] bridge = new boolean[m];
        Arrays.fill(tin, -1); Arrays.fill(parArc, -1);
        int timer = 0, sp = 0;
        tin[0] = low[0] = timer++; it[0] = head[0]; stk[sp++] = 0;
        while (sp > 0) {
            int v = stk[sp - 1];
            if (it[v] != -1) {
                int a = it[v]; it[v] = nxt[a];
                if ((a ^ 1) == parArc[v]) continue;
                int w = to[a];
                if (tin[w] == -1) { parArc[w] = a; tin[w] = low[w] = timer++; it[w] = head[w]; stk[sp++] = w; }
                else low[v] = Math.min(low[v], tin[w]);
            } else {
                sp--;
                if (parArc[v] == -1) continue;
                int p = to[parArc[v] ^ 1];
                low[p] = Math.min(low[p], low[v]);
                if (low[v] > tin[p]) bridge[parArc[v] >> 1] = true;
            }
        }
        int[] comp = new int[n];
        Arrays.fill(comp, -1);
        int C = 0;
        for (int s = 0; s < n; s++) {
            if (comp[s] != -1) continue;
            sp = 0; comp[s] = C; stk[sp++] = s;
            while (sp > 0) {
                int v = stk[--sp];
                for (int a = head[v]; a != -1; a = nxt[a])
                    if (!bridge[a >> 1] && comp[to[a]] == -1) { comp[to[a]] = C; stk[sp++] = to[a]; }
            }
            C++;
        }
        int[] deg = new int[C];
        for (int i = 0; i < m; i++) if (bridge[i]) { deg[comp[eu[i]]]++; deg[comp[ev[i]]]++; }
        int leaves = 0;
        for (int x : deg) if (x == 1) leaves++;
        System.out.println(C == 1 ? 0 : (leaves + 1) / 2);
    }
}
```

</details>

<!-- test
in:
5 4
1 2
1 3
1 4
1 5
out:
2
-->
<!-- test
in:
2 1
1 2
out:
1
-->
<!-- test
in:
4 4
1 2
2 3
3 4
4 1
out:
0
-->
<!-- test
in:
7 8
1 2
2 3
3 1
3 4
4 5
5 6
6 4
6 7
out:
1
-->

## 6. Tricks, pitfalls and things to remember

1. **Skip the parent edge by id** (`(a ^ 1) == parArc[v]`), never by parent vertex — otherwise parallel edges are reported as bridges.
2. **Back edges update with `tin[w]`**, children with `low[c]`. Mixing them up breaks the articulation-point test.
3. **The root is special** for cut vertices (≥ 2 DFS children), but not for bridges.
4. **Loop over all start vertices**: graphs are often disconnected; the bridge tree and block-cut tree are then forests.
5. **Recursion depth**: a path of $10^5$–$10^6$ vertices overflows Java's default stack and the Windows C++ default; the iterative
   edge-iterator DFS above has no limit. If you write it recursively in Java, run it in `new Thread(null, r, "", 1 << 28)`.
6. **Cut vertex ≠ endpoint of a bridge.** Leaves of bridges are not cut vertices; the hinge of a figure-eight is a cut vertex with no bridges.
7. **Self-loops** never matter (they are back edges to the vertex itself); make sure your edge storage tolerates them.
8. **2-edge-connected vs biconnected:** 2ECCs partition *vertices*; blocks partition *edges* and a cut vertex belongs to several blocks.
9. **Block-cut tree size** is up to $2n$ nodes: size arrays accordingly (`2n + 2` tree edges is enough).
10. **"$c$ on path$(a,b)$"** needs the LCA condition; testing only "c is an ancestor of a or b" accepts ancestors above the LCA.
11. **Java speed:** use `int[] head/nxt/to` arrays (arc ids double as edge ids); `ArrayList<int[]>` adjacency is 3–5× slower at $m = 2\cdot10^5$.
12. **Counting disconnected pairs** after deleting bridge $(p,v)$: $sz_v (n - sz_v)$ — use `long long`, it reaches $2.5\cdot10^{9}$ for $n=10^5$.

## 7. Going further (toward 2400–2600+)

- **Online bridges** (edges only added, maintain number of bridges after each insertion): DSU over 2ECCs plus a DSU over
  connected components with path compression along the bridge forest (classic $O(n \log n + m\,\alpha)$ technique).
- **Fully dynamic / offline deletions:** segment tree over time + DSU with rollback,
  see [segment tree on time](../16-IGM-Frontier/02-segment-tree-on-time-and-dsu-rollback.md).
- **Directed analogue:** "every path from the source to $v$ passes through $c$" → dominator tree (Lengauer–Tarjan, 🧊).
- **Bridge tree + LCA** for path-constrained orientations ([CF 555E · Case of Computer Network](https://codeforces.com/problemset/problem/555/E) — 2800):
  orient each tree edge by difference counters on the bridge tree.
- **Block-cut tree + HLD**: path min over cut vertices / blocks with point updates — [CF 487E · Tourists](https://codeforces.com/problemset/problem/487/E) — 3200.
  The standard trick: store a block's value in a multiset at the block node excluding its parent cut vertex.
- **Cactus graphs:** each block is an edge or a cycle, so tree DP generalises to "cycle DP" on the block-cut tree
  ([CF 231E · Cactus](https://codeforces.com/problemset/problem/231/E) — 2100). See also [special graphs](10-functional-graphs-and-special-graphs.md).
- **3-edge-connectivity and SPQR trees** exist (🧊); in contests, $k$-connectivity for a specific pair is a flow problem.

## 8. Practice ladder

**≤ 1700**
- [ ] [AtCoder ABC075 C · Bridge](https://atcoder.jp/contests/abc075/tasks/abc075_c) — ≈1067 (est.) — count bridges (small; also try brute force)
- [ ] [CSES 2076 · Necessary Roads](https://cses.fi/problemset/task/2076) — bridges
- [ ] [CSES 2077 · Necessary Cities](https://cses.fi/problemset/task/2077) — articulation points
- [ ] [CF 193A · Cutting Figure](https://codeforces.com/problemset/problem/193/A) — 1700 — grid cut vertex, answer ≤ 2
- [ ] [CF 22C · System Administrator](https://codeforces.com/problemset/problem/22/C) — 1700 — build a graph with a prescribed cut vertex

**1700–2100**
- [ ] [CF 1986F · Non-academic Problem](https://codeforces.com/problemset/problem/1986/F) — 1900 — bridges + subtree sizes
- [ ] [CF 1927F · Microcycle](https://codeforces.com/problemset/problem/1927/F) — 1900 — lightest non-bridge edge
- [ ] [CF 118E · Bertown roads](https://codeforces.com/problemset/problem/118/E) — 2000 — Robbins orientation
- [ ] [CSES 2177 · Strongly Connected Edges](https://cses.fi/problemset/task/2177) — orientation output
- [ ] [CF 1000E · We Need More Bosses](https://codeforces.com/problemset/problem/1000/E) — 2100 — bridge tree diameter
- [ ] [CF 231E · Cactus](https://codeforces.com/problemset/problem/231/E) — 2100 — compress cycles, count on a tree

**2100–2400**
- [ ] [CF 1220E · Tourism](https://codeforces.com/problemset/problem/1220/E) — 2200 — 2ECC compression + tree DP
- [ ] [CF 732F · Tourist Reform](https://codeforces.com/problemset/problem/732/F) — 2300 — largest 2ECC as the sink
- [ ] [CF 652E · Pursuit For Artifacts](https://codeforces.com/problemset/problem/652/E) — 2300 — bridge tree path query
- [ ] [CSES 1704 · Network Renovation](https://cses.fi/problemset/task/1704) — construct the $\lceil L/2\rceil$ edges
- [ ] [CSES 1705 · Forbidden Cities](https://cses.fi/problemset/task/1705) — block-cut tree queries
- [ ] [CF 962F · Simple Cycles Edges](https://codeforces.com/problemset/problem/962/F) — 2400 — blocks with $|E| = |V|$

**2400+**
- [ ] [CF 555E · Case of Computer Network](https://codeforces.com/problemset/problem/555/E) — 2800 — bridge tree + LCA + difference marks
- [ ] [CF 51F · Caterpillar](https://codeforces.com/problemset/problem/51/F) — 2800 — 2ECC compression + tree diameter reasoning
- [ ] [CF 487E · Tourists](https://codeforces.com/problemset/problem/487/E) — 3200 — block-cut tree + HLD

## 9. LeetCode / FAANG cross-reference

- [LC 1192 · Critical Connections in a Network](https://leetcode.com/problems/critical-connections-in-a-network/) — Hard — exactly "list all bridges"; the low-link DFS is the expected answer.
- [LC 1568 · Minimum Number of Days to Disconnect Island](https://leetcode.com/problems/minimum-number-of-days-to-disconnect-island/) — Hard — answer is 0, 1 or 2; "1" iff a land cell is an articulation point (or only one cell).
- [LC 928 · Minimize Malware Spread II](https://leetcode.com/problems/minimize-malware-spread-ii/) — Hard — removing a vertex; the clean solution is BFS per infected node, a cut-vertex view explains it.

Interviews mostly ask for bridges (LC 1192) and expect you to explain `low`. Block-cut trees are rare in interviews.

## 10. Self-check

1. Why does an undirected DFS tree have no cross edges?
2. State and justify the bridge condition in terms of `tin` and `low`.
3. Why must the root be treated separately for cut vertices but not for bridges?
4. Give a graph where skipping the parent *vertex* (instead of the parent edge) reports a wrong bridge.
5. Give a graph that is 2-edge-connected but not biconnected.
6. How do you answer "does every $a$–$b$ path pass through $c$?" for $10^5$ queries?
7. Why is the minimum number of edges to make a tree-of-2ECCs bridgeless exactly $\lceil L/2\rceil$?
8. Which back-edge update (`tin[w]` or `low[w]`) is safe for articulation points, and why is the other one wrong?

<details><summary>Answers</summary>

1. If $u$–$v$ is a non-tree edge with $u$ entered first, $v$ is still unvisited and adjacent to $u$, so DFS reaches $v$ before $u$ finishes: $v$ is a descendant.
2. Tree edge $p \to v$ is a bridge iff $\text{low}[v] > \text{tin}[p]$: the only escapes from $\text{subtree}(v)$ are back edges to ancestors, and `low` is the earliest one.
3. The root has no ancestor, so the child test $\text{low}[v] \ge \text{tin}[root]$ always holds; what matters is whether two child subtrees exist. Bridges are a property of edges and need no exception.
4. Two vertices joined by two parallel edges: skipping vertex $1$ from $2$ ignores the second edge, so $\text{low}[2] = \text{tin}[2] > \text{tin}[1]$ and the edge looks like a bridge.
5. Two triangles sharing one vertex (figure-eight): no bridges, but the shared vertex is a cut vertex.
6. Build the block-cut tree, root it, binary-lift: answer "blocked" iff $c$ is an ancestor of $a$ or $b$ and $\text{lca}(a,b)$ is an ancestor of $c$ (and $a,b$ connected).
7. Each leaf component needs a new edge endpoint (lower bound); pairing leaf $i$ with leaf $i + \lfloor L/2 \rfloor$ in DFS order crosses every tree edge (upper bound).
8. `tin[w]`. Using `low[w]` lets a subtree "escape" through $p$'s other children: low can drop below `tin[p]` even though the only way out passes through $p$.

</details>
