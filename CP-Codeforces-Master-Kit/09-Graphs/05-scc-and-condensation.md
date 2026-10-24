# Strongly Connected Components and the Condensation DAG

> **Band:** 🔵 1600 → 🟠 2400 · **Priority:** 🔥 · **FAANG:** low · **Prerequisites:** [DFS, entry/exit times](01-graph-representation-bfs-dfs.md), [topological sort and DAG DP](04-topological-sort-and-dag-dp.md)
> **You can say you know this when:** you can prove that the condensation is a DAG, write *iterative* Tarjan and Kosaraju in both languages, say in which order each one numbers the components, and reduce "collect everything", "minimum cost to cover", "how many edges to add" and "how many starting points" questions to sources, sinks and DP on the condensation.

## 1. First principles — why this works

**Mutual reachability is an equivalence relation.** Write $u \sim v$ if $u$ reaches $v$ and $v$ reaches $u$. It is reflexive,
symmetric, and transitive (concatenate paths). Its classes are the **strongly connected components** (SCCs). Inside an SCC
every vertex reaches every other, so for "collect", "visit", "infect", "can return" questions an SCC behaves like a single
vertex with combined attributes (total coins, minimum cost, size, "contains a cycle").

**The condensation is a DAG.** Contract every SCC to one vertex and keep the edges between different SCCs. If the contracted
graph had a cycle $C_1 \to C_2 \to \dots \to C_1$, every vertex of these SCCs would reach every other, so they would be a
single SCC — contradiction. Therefore every directed graph is "a DAG of strongly connected blobs", and after condensation all
of [topological sort and DAG DP](04-topological-sort-and-dag-dp.md) applies. That is the main reason SCCs matter in contests.

**Naive approach and why it is slow.** Computing reachability from every vertex is $O(n(n+m))$. Both linear algorithms below
extract the SCCs from one or two DFS runs by using finish times.

**Key lemma (finish times respect the condensation).** Run a full DFS (outer loop over all vertices). For SCCs $C \ne C'$
with an edge $C\to C'$: $\max_{x\in C}\text{tout}(x) > \max_{y\in C'}\text{tout}(y)$.
*Proof.* If DFS enters $C$ first, at vertex $x$, then all of $C\cup C'$ is white and reachable from $x$, so by the white-path
theorem it all becomes descendants of $x$ and finishes before $x$. If DFS enters $C'$ first, nothing in $C$ is reachable from
$C'$ (the condensation is acyclic), so all of $C'$ finishes before any vertex of $C$ is even discovered. ∎
So the vertex with the largest finish time lies in a **source** SCC of the condensation.

**Kosaraju (two passes).** Pass 1: DFS on $G$, record vertices by finish time. Pass 2: process vertices in decreasing
finish time on the **reversed** graph $G^R$; each DFS tree of pass 2 is exactly one SCC.
*Why:* the first unassigned vertex $x$ (largest finish time) lies in a source SCC $C$ of $G$, which is a sink of $G^R$:
from $x$, $G^R$ reaches exactly $C$. Remove $C$ and repeat — by the lemma the next largest finish time is again in a source of
what remains. Components come out in **topological order** of the condensation of $G$. Pass 2 only needs reachability, so
any traversal order works there; pass 1 needs a genuine (iterative) DFS post-order.

**Tarjan (one pass).** DFS with a stack of "vertices whose SCC is still open". Define
$\text{low}[v]$ = the smallest $\text{tin}$ of an **on-stack** vertex reachable from $v$'s DFS subtree using tree edges and
then one more edge. The first vertex of an SCC to be visited is its **root** $r$; all of the SCC are descendants of $r$
(white-path theorem), and they sit above $r$ on the stack until $r$ finishes.
*Claim:* $v$ is a root iff $\text{low}[v] = \text{tin}[v]$. If $v$ is not a root, it reaches its root $r$ (an ancestor, on
the stack, with smaller $\text{tin}$) by a path that must leave $v$'s subtree through an edge into an on-stack vertex of
smaller $\text{tin}$ — so $\text{low}[v] < \text{tin}[v]$. If $v$ is a root, any edge out of its subtree goes to a vertex
already finished and popped (a completed SCC, which cannot reach back) or to a vertex of $v$'s own SCC inside the subtree,
so nothing with smaller $\text{tin}$ is reachable on the stack. When a root finishes, pop the stack down to it: that is its SCC.
An SCC is popped only after every SCC reachable from it has been popped, so Tarjan numbers components in **reverse
topological order** (component 0 is a sink). Edges to already popped vertices must be ignored — that is what the `onStack`
flag is for (using them is the classic Tarjan bug).

**Iterative versions are mandatory in Java** (a path of $10^5$ vertices overflows the default stack) and wise in C++ on
Windows. Both algorithms below keep an explicit call stack with a per-vertex edge iterator.

**What reduces to the condensation.**
- *Path DP that may revisit vertices:* "maximum coins collected on a walk" = longest path in the condensation with SCC sums
  as vertex weights (CSES Coin Collector). "Number of paths, $\infty$ if a cycle is involved" (CF 1547G) = DP over the DAG with
  "contains a cycle" flags.
- *Choose one vertex per SCC:* "build checkposts so that every vertex is protected" (CF 427C) = per SCC, the minimum cost and
  the number of vertices attaining it.
- *Starting points:* the minimum number of vertices from which everything is reachable = number of **source** SCCs (in-degree
  0 in the condensation). With a fixed capital $s$: number of source SCCs other than $s$'s own (CF 999E) — each needs a new
  incoming edge, and an edge from $s$ to each suffices.
- *Make the graph strongly connected:* the minimum number of edges to add is $0$ if there is one SCC, otherwise
  $\max(\#\text{sources}, \#\text{sinks})$ (Eswaran–Tarjan 1976). Lower bound: every source SCC needs a new incoming edge and
  every sink SCC a new outgoing one, and one edge provides at most one of each. The matching upper bound needs a careful
  construction (pair sinks to sources along a chain); CSES New Flight Routes asks for it.
- *"Can the walk go on forever / return"*: a vertex lies on a cycle iff its SCC has size $\ge 2$ or it has a self-loop.
- *Whole-graph strong connectivity* needs no SCC algorithm: $G$ is strongly connected iff vertex 1 reaches everything in $G$
  **and** in $G^R$ (Example 1).
- *2-SAT* is SCC on the implication graph ([2-SAT](07-two-sat.md)); the reverse-topological numbering of Tarjan is exactly
  what its assignment rule uses.

## 2. Formulas, definitions and identities

- $u\sim v \iff (u \leadsto v \wedge v \leadsto u)$; SCCs partition $V$; $\#\text{SCC} = n$ iff the graph is a DAG.
- **Condensation** $G^{SCC} = (\{C_i\}, \{C_i\to C_j : \exists u\in C_i, v\in C_j, u\to v, i\ne j\})$ is a DAG.
- **Finish-time lemma:** edge $C\to C'$ between different SCCs ⇒ $\max_C \text{tout} > \max_{C'}\text{tout}$.
- **Tarjan root test:** $\text{low}[v] = \text{tin}[v]$ with
  $\text{low}[v] = \min\big(\text{tin}[v],\ \min_{\text{tree child } c}\text{low}[c],\ \min_{v\to w,\ w \text{ on stack}}\text{tin}[w]\big)$.
- **Numbering:** Kosaraju → topological order of $G^{SCC}$; Tarjan → reverse topological order (edge $C_i\to C_j$ ⇒ $i > j$).
- **Strong connectivity test:** $\text{reach}_G(1) = V$ and $\text{reach}_{G^R}(1) = V$.
- **Augmentation (Eswaran–Tarjan):** with $k \ge 2$ SCCs, $s$ sources and $t$ sinks (an isolated SCC counts as both),
  the minimum number of added edges is $\max(s, t)$.
- **Coverage from one root:** extra edges so that $r$ reaches all $= \#\{\text{source SCCs}\} - [\text{SCC}(r)\text{ is a source}]$.
- **Complexities:** Tarjan and Kosaraju $O(n+m)$ time, $O(n+m)$ memory; building the condensation $O(n+m)$ (plus sorting if
  you deduplicate edges).

## 3. Implementation (C++ and Java)

### 3.1 Tarjan, iterative (components in reverse topological order)

```cpp
// comp[v] in [0, k).  Component ids are in REVERSE topological order: an edge C_i -> C_j (i != j) has i > j.
struct TarjanSCC {
    int n, k = 0;
    vector<int> comp;
    TarjanSCC(const vector<vector<int>>& g) : n(g.size()), comp(g.size(), -1) {
        vector<int> tin(n, -1), low(n, 0), it(n, 0), st, call;
        vector<char> onStack(n, 0);
        int timer = 0;
        auto enter = [&](int v) {
            tin[v] = low[v] = timer++;
            st.push_back(v); onStack[v] = 1; call.push_back(v);
        };
        for (int s = 0; s < n; s++) {
            if (tin[s] != -1) continue;
            enter(s);
            while (!call.empty()) {
                int u = call.back();
                if (it[u] < (int)g[u].size()) {
                    int v = g[u][it[u]++];
                    if (tin[v] == -1) enter(v);                          // tree edge: "recurse"
                    else if (onStack[v]) low[u] = min(low[u], tin[v]);   // edge into the open part
                } else {                                                 // u finished: "return"
                    call.pop_back();
                    if (!call.empty()) low[call.back()] = min(low[call.back()], low[u]);
                    if (low[u] == tin[u]) {                              // u is the root of an SCC
                        while (true) {
                            int x = st.back(); st.pop_back();
                            onStack[x] = 0; comp[x] = k;
                            if (x == u) break;
                        }
                        k++;
                    }
                }
            }
        }
    }
};
```

```java
// CSR graph (start, adj).  comp[v] in [0, k), reverse topological order.
static int sccCount;
static int[] tarjan(int n, int[] start, int[] adj) {
    int[] tin = new int[n], low = new int[n], it = new int[n], comp = new int[n];
    int[] st = new int[n], call = new int[n];
    boolean[] onStack = new boolean[n];
    Arrays.fill(tin, -1);
    int timer = 0, sp = 0, cp = 0, k = 0;
    for (int s = 0; s < n; s++) {
        if (tin[s] != -1) continue;
        tin[s] = low[s] = timer++; st[sp++] = s; onStack[s] = true; it[s] = start[s]; call[cp++] = s;
        while (cp > 0) {
            int u = call[cp - 1];
            if (it[u] < start[u + 1]) {
                int v = adj[it[u]++];
                if (tin[v] == -1) {
                    tin[v] = low[v] = timer++; st[sp++] = v; onStack[v] = true; it[v] = start[v]; call[cp++] = v;
                } else if (onStack[v] && tin[v] < low[u]) low[u] = tin[v];
            } else {
                cp--;
                if (cp > 0 && low[u] < low[call[cp - 1]]) low[call[cp - 1]] = low[u];
                if (low[u] == tin[u]) {
                    while (true) {
                        int x = st[--sp];
                        onStack[x] = false; comp[x] = k;
                        if (x == u) break;
                    }
                    k++;
                }
            }
        }
    }
    sccCount = k;
    return comp;
}
```

### 3.2 Kosaraju, iterative (components in topological order)

```cpp
// Returns comp[v]; ids follow a topological order of the condensation (edge C_i -> C_j has i < j).
vector<int> kosaraju(const vector<vector<int>>& g, int& k) {
    int n = g.size();
    vector<vector<int>> rg(n);
    for (int u = 0; u < n; u++) for (int v : g[u]) rg[v].push_back(u);
    vector<int> order, it(n, 0), st;                  // pass 1: post-order on g
    vector<char> seen(n, 0);
    for (int s = 0; s < n; s++) {
        if (seen[s]) continue;
        seen[s] = 1; st.push_back(s);
        while (!st.empty()) {
            int u = st.back();
            if (it[u] < (int)g[u].size()) {
                int v = g[u][it[u]++];
                if (!seen[v]) { seen[v] = 1; st.push_back(v); }
            } else { order.push_back(u); st.pop_back(); }
        }
    }
    vector<int> comp(n, -1);                          // pass 2: reversed graph, decreasing finish time
    k = 0;
    for (int i = n - 1; i >= 0; i--) {
        int s = order[i];
        if (comp[s] != -1) continue;
        comp[s] = k; st.push_back(s);
        while (!st.empty()) {
            int u = st.back(); st.pop_back();
            for (int v : rg[u]) if (comp[v] == -1) { comp[v] = k; st.push_back(v); }
        }
        k++;
    }
    return comp;
}
```

```java
// CSR graph g (start, adj) and its reverse (rstart, radj).  Topological numbering.
static int[] kosaraju(int n, int[] start, int[] adj, int[] rstart, int[] radj, int[] kOut) {
    int[] it = new int[n], st = new int[n], order = new int[n];
    boolean[] seen = new boolean[n];
    int oc = 0;
    for (int s = 0; s < n; s++) {
        if (seen[s]) continue;
        int top = 0;
        seen[s] = true; it[s] = start[s]; st[top++] = s;
        while (top > 0) {
            int u = st[top - 1];
            if (it[u] < start[u + 1]) {
                int v = adj[it[u]++];
                if (!seen[v]) { seen[v] = true; it[v] = start[v]; st[top++] = v; }
            } else { order[oc++] = u; top--; }
        }
    }
    int[] comp = new int[n];
    Arrays.fill(comp, -1);
    int k = 0;
    for (int i = n - 1; i >= 0; i--) {
        int s = order[i];
        if (comp[s] != -1) continue;
        int top = 0;
        comp[s] = k; st[top++] = s;
        while (top > 0) {
            int u = st[--top];
            for (int e = rstart[u]; e < rstart[u + 1]; e++) {
                int v = radj[e];
                if (comp[v] == -1) { comp[v] = k; st[top++] = v; }
            }
        }
        k++;
    }
    kOut[0] = k;
    return comp;
}
```

### 3.3 Building the condensation (deduplicated edges)

```cpp
// From comp[] with k components: DAG adjacency between components, without duplicates.
vector<vector<int>> condense(const vector<vector<int>>& g, const vector<int>& comp, int k) {
    vector<vector<int>> dag(k);
    for (int u = 0; u < (int)g.size(); u++)
        for (int v : g[u]) if (comp[u] != comp[v]) dag[comp[u]].push_back(comp[v]);
    for (auto& a : dag) { sort(a.begin(), a.end()); a.erase(unique(a.begin(), a.end()), a.end()); }
    return dag;
}
```

```java
// Returns the condensation as CSR: {dstart, dadj}; duplicates removed with a "last source" stamp.
static int[][] condense(int n, int[] start, int[] adj, int[] comp, int k) {
    int[] cnt = new int[k + 1];
    for (int u = 0; u < n; u++) for (int e = start[u]; e < start[u + 1]; e++) if (comp[u] != comp[adj[e]]) cnt[comp[u] + 1]++;
    for (int i = 0; i < k; i++) cnt[i + 1] += cnt[i];
    int[] raw = new int[cnt[k]], pos = Arrays.copyOf(cnt, k);
    for (int u = 0; u < n; u++) for (int e = start[u]; e < start[u + 1]; e++) if (comp[u] != comp[adj[e]]) raw[pos[comp[u]]++] = comp[adj[e]];
    int[] stamp = new int[k], dstart = new int[k + 1], dadj = new int[raw.length];
    Arrays.fill(stamp, -1);
    int t = 0;
    for (int c = 0; c < k; c++) {
        dstart[c] = t;
        for (int e = cnt[c]; e < cnt[c + 1]; e++) if (stamp[raw[e]] != c) { stamp[raw[e]] = c; dadj[t++] = raw[e]; }
    }
    dstart[k] = t;
    return new int[][]{dstart, Arrays.copyOf(dadj, t)};
}
```

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| directed graph, "you may revisit vertices", "collect as much as possible" | SCC sums + longest path on the condensation |
| "if $u$ can reach $v$ and $v$ can reach $u$ …", "mutually reachable", "kingdoms" | SCC labels |
| "minimum cost to place guards/checkposts so every vertex is covered", coverage spreads along cycles | per-SCC minimum and count |
| "minimum number of vertices to start from so that everything is reached" | number of source SCCs |
| "minimum number of edges to add so that every vertex can reach every other" | $\max(\text{sources}, \text{sinks})$ |
| "can the process go on forever", "is $v$ on a cycle" | SCC size $\ge 2$ or self-loop |
| "count paths; print $-1$ (or ∞) if infinitely many" | condensation + cycle flags (CF 1547G) |
| boolean constraints "if $x$ then $y$" | implication graph SCC = [2-SAT](07-two-sat.md) |
| "is the whole graph strongly connected?" | two BFS (from 1 in $G$ and in $G^R$) |
| state graph (vertex, time mod $d$) with revisits allowed (CF 1137C) | SCC of the product graph, then DAG DP |

Do not confuse with **2-edge-connected / biconnected components** — those are about *undirected* graphs and edge/vertex
failures ([bridges and articulation points](06-bridges-articulation-points-and-bcc.md)) — or with weakly connected components
(ignore directions, use DSU).

## 5. Worked examples (graded)

### Example 1 — Flight Routes Check  ·  ★ ≈1500

- **Source:** [CSES 1682 · Flight Routes Check](https://cses.fi/problemset/task/1682)
- **Difficulty:** ≈1500 (est.)
- **Problem:** A directed graph with $n \le 10^5$ cities and $m \le 2\cdot10^5$ flights. Print `YES` if every city can reach
  every other city; otherwise print `NO` and a pair $a\ b$ such that $b$ is not reachable from $a$. Any pair is accepted; we
  print `1 v` for the smallest $v$ unreachable from 1, or else `v 1` for the smallest $v$ that cannot reach 1.
- **Thinking from first principles:** you don't need all SCCs, only "is there one". If 1 reaches everyone and everyone reaches
  1, then any $a$ reaches any $b$ via 1. "Everyone reaches 1" is "1 reaches everyone in the reversed graph". If either fails,
  the failing vertex together with 1 is the witness pair.

<details><summary>Solution</summary>

Two BFS runs (on $G$ and $G^R$). $O(n+m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

vector<char> reach(const vector<vector<int>>& g, int s) {
    vector<char> seen(g.size(), 0);
    vector<int> q = {s};
    seen[s] = 1;
    for (size_t h = 0; h < q.size(); h++)
        for (int v : g[q[h]]) if (!seen[v]) { seen[v] = 1; q.push_back(v); }
    return seen;
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<vector<int>> g(n + 1), rg(n + 1);
    for (int i = 0; i < m; i++) {
        int a, b;
        cin >> a >> b;
        g[a].push_back(b);
        rg[b].push_back(a);
    }
    auto f = reach(g, 1), r = reach(rg, 1);
    for (int v = 1; v <= n; v++) if (!f[v]) { cout << "NO\n1 " << v << "\n"; return 0; }
    for (int v = 1; v <= n; v++) if (!r[v]) { cout << "NO\n" << v << " 1\n"; return 0; }
    cout << "YES\n";
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

    static boolean[] reach(int n, int[] start, int[] adj, int s) {
        boolean[] seen = new boolean[n + 1];
        int[] q = new int[n];
        int h = 0, t = 0;
        q[t++] = s; seen[s] = true;
        while (h < t) {
            int u = q[h++];
            for (int e = start[u]; e < start[u + 1]; e++) if (!seen[adj[e]]) { seen[adj[e]] = true; q[t++] = adj[e]; }
        }
        return seen;
    }

    static int[][] csr(int n, int[] from, int[] to) {
        int[] start = new int[n + 2];
        for (int x : from) start[x + 1]++;
        for (int i = 0; i <= n; i++) start[i + 1] += start[i];
        int[] adj = new int[from.length], pos = Arrays.copyOf(start, n + 1);
        for (int i = 0; i < from.length; i++) adj[pos[from[i]]++] = to[i];
        return new int[][]{start, adj};
    }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt();
        int[] a = new int[m], b = new int[m];
        for (int i = 0; i < m; i++) { a[i] = nextInt(); b[i] = nextInt(); }
        int[][] g = csr(n, a, b), rg = csr(n, b, a);
        boolean[] f = reach(n, g[0], g[1], 1), r = reach(n, rg[0], rg[1], 1);
        for (int v = 1; v <= n; v++) if (!f[v]) { System.out.println("NO\n1 " + v); return; }
        for (int v = 1; v <= n; v++) if (!r[v]) { System.out.println("NO\n" + v + " 1"); return; }
        System.out.println("YES");
    }
}
```

</details>

<!-- test
in:
4 5
1 2
2 3
3 1
3 4
4 2
out:
YES
-->
<!-- test
in:
4 4
1 2
2 3
3 1
4 1
out:
NO
1 4
-->
<!-- test
in:
3 2
1 2
1 3
out:
NO
2 1
-->
<!-- test
in:
1 0
out:
YES
-->

### Example 2 — Planets and Kingdoms  ·  ★ ≈1600

- **Source:** [CSES 1683 · Planets and Kingdoms](https://cses.fi/problemset/task/1683)
- **Difficulty:** ≈1600 (est.)
- **Problem:** $n \le 10^5$ planets, $m \le 2\cdot10^5$ one-way teleporters. Two planets belong to the same kingdom iff each
  can reach the other. Print the number of kingdoms $k$ and a kingdom label in $1..k$ for every planet. Any labeling is
  accepted; we number kingdoms in order of their smallest planet.
- **Thinking from first principles:** kingdoms are, by definition, SCCs. Tarjan gives ids in some algorithm-dependent order;
  relabel by scanning planets $1..n$ and assigning a fresh label at the first planet of each new component — the output then
  depends only on the partition.

<details><summary>Solution</summary>

Iterative Tarjan + relabeling. $O(n+m)$.

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
        int a, b;
        cin >> a >> b;
        g[a - 1].push_back(b - 1);
    }
    vector<int> tin(n, -1), low(n), it(n, 0), comp(n, -1), st, call;
    vector<char> onStack(n, 0);
    int timer = 0, k = 0;
    for (int s = 0; s < n; s++) {
        if (tin[s] != -1) continue;
        tin[s] = low[s] = timer++; st.push_back(s); onStack[s] = 1; call.push_back(s);
        while (!call.empty()) {
            int u = call.back();
            if (it[u] < (int)g[u].size()) {
                int v = g[u][it[u]++];
                if (tin[v] == -1) { tin[v] = low[v] = timer++; st.push_back(v); onStack[v] = 1; call.push_back(v); }
                else if (onStack[v]) low[u] = min(low[u], tin[v]);
            } else {
                call.pop_back();
                if (!call.empty()) low[call.back()] = min(low[call.back()], low[u]);
                if (low[u] == tin[u]) {
                    int x;
                    do { x = st.back(); st.pop_back(); onStack[x] = 0; comp[x] = k; } while (x != u);
                    k++;
                }
            }
        }
    }
    vector<int> label(k, 0);
    int next = 0;
    for (int v = 0; v < n; v++) if (!label[comp[v]]) label[comp[v]] = ++next;
    cout << k << "\n";
    for (int v = 0; v < n; v++) cout << label[comp[v]] << " \n"[v + 1 == n];
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
        int[] ea = new int[m], eb = new int[m], start = new int[n + 1];
        for (int i = 0; i < m; i++) { ea[i] = nextInt() - 1; eb[i] = nextInt() - 1; start[ea[i] + 1]++; }
        for (int i = 0; i < n; i++) start[i + 1] += start[i];
        int[] adj = new int[m], pos = Arrays.copyOf(start, n);
        for (int i = 0; i < m; i++) adj[pos[ea[i]]++] = eb[i];
        int[] tin = new int[n], low = new int[n], it = new int[n], comp = new int[n], st = new int[n], call = new int[n];
        boolean[] onStack = new boolean[n];
        Arrays.fill(tin, -1);
        int timer = 0, sp = 0, cp = 0, k = 0;
        for (int s = 0; s < n; s++) {
            if (tin[s] != -1) continue;
            tin[s] = low[s] = timer++; st[sp++] = s; onStack[s] = true; it[s] = start[s]; call[cp++] = s;
            while (cp > 0) {
                int u = call[cp - 1];
                if (it[u] < start[u + 1]) {
                    int v = adj[it[u]++];
                    if (tin[v] == -1) { tin[v] = low[v] = timer++; st[sp++] = v; onStack[v] = true; it[v] = start[v]; call[cp++] = v; }
                    else if (onStack[v] && tin[v] < low[u]) low[u] = tin[v];
                } else {
                    cp--;
                    if (cp > 0 && low[u] < low[call[cp - 1]]) low[call[cp - 1]] = low[u];
                    if (low[u] == tin[u]) {
                        int x;
                        do { x = st[--sp]; onStack[x] = false; comp[x] = k; } while (x != u);
                        k++;
                    }
                }
            }
        }
        int[] label = new int[k];
        int next = 0;
        for (int v = 0; v < n; v++) if (label[comp[v]] == 0) label[comp[v]] = ++next;
        StringBuilder sb = new StringBuilder();
        sb.append(k).append('\n');
        for (int v = 0; v < n; v++) sb.append(label[comp[v]]).append(v + 1 == n ? '\n' : ' ');
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
5 6
1 2
2 1
3 4
4 5
5 3
2 3
out:
2
1 1 2 2 2
-->
<!-- test
in:
3 0
out:
3
1 2 3
-->
<!-- test
in:
4 4
4 3
3 4
1 2
2 4
out:
3
1 2 3 3
-->

### Example 3 — Checkposts  ·  ★ 1700

- **Source:** [CF 427C · Checkposts](https://codeforces.com/problemset/problem/427/C) — 1700
- **Difficulty:** 1700
- **Problem:** $n \le 10^5$ junctions with building costs $0 \le c_i \le 10^9$ and $m \le 3\cdot10^5$ one-way roads. A
  checkpost at $i$ protects $j$ if $i$ reaches $j$ and $j$ reaches $i$. Protect every junction with minimum total cost; print
  that cost and the number of minimum-cost ways modulo $10^9+7$ (ways differ in the set of junctions used, and use the
  minimum possible number of checkposts).
- **Thinking from first principles:** "protects" is exactly the SCC relation, so the components are independent: each SCC
  needs at least one checkpost and one suffices. Minimum cost = sum of per-SCC minima; ways = product of the number of
  vertices attaining each minimum (using one checkpost per SCC; adding a second never lowers the cost unless it is free, and
  the count rule restricts to the minimum number). No condensation edges are needed at all.

<details><summary>Solution</summary>

Tarjan; per component track `(min, count)`; total = sum of mins, ways = product of counts. $O(n+m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    const ll MOD = 1'000'000'007;
    int n;
    cin >> n;
    vector<ll> cost(n);
    for (auto& c : cost) cin >> c;
    int m;
    cin >> m;
    vector<vector<int>> g(n);
    for (int i = 0; i < m; i++) {
        int u, v;
        cin >> u >> v;
        g[u - 1].push_back(v - 1);
    }
    vector<int> tin(n, -1), low(n), it(n, 0), st, call;
    vector<char> onStack(n, 0);
    int timer = 0;
    ll total = 0, ways = 1;
    for (int s = 0; s < n; s++) {
        if (tin[s] != -1) continue;
        tin[s] = low[s] = timer++; st.push_back(s); onStack[s] = 1; call.push_back(s);
        while (!call.empty()) {
            int u = call.back();
            if (it[u] < (int)g[u].size()) {
                int v = g[u][it[u]++];
                if (tin[v] == -1) { tin[v] = low[v] = timer++; st.push_back(v); onStack[v] = 1; call.push_back(v); }
                else if (onStack[v]) low[u] = min(low[u], tin[v]);
            } else {
                call.pop_back();
                if (!call.empty()) low[call.back()] = min(low[call.back()], low[u]);
                if (low[u] == tin[u]) {
                    ll mn = LLONG_MAX, cnt = 0;
                    int x;
                    do {
                        x = st.back(); st.pop_back(); onStack[x] = 0;
                        if (cost[x] < mn) { mn = cost[x]; cnt = 1; } else if (cost[x] == mn) cnt++;
                    } while (x != u);
                    total += mn;
                    ways = ways * cnt % MOD;
                }
            }
        }
    }
    cout << total << ' ' << ways << "\n";
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
        final long MOD = 1_000_000_007L;
        int n = nextInt();
        long[] cost = new long[n];
        for (int i = 0; i < n; i++) cost[i] = nextInt();
        int m = nextInt();
        int[] ea = new int[m], eb = new int[m], start = new int[n + 1];
        for (int i = 0; i < m; i++) { ea[i] = nextInt() - 1; eb[i] = nextInt() - 1; start[ea[i] + 1]++; }
        for (int i = 0; i < n; i++) start[i + 1] += start[i];
        int[] adj = new int[m], pos = Arrays.copyOf(start, n);
        for (int i = 0; i < m; i++) adj[pos[ea[i]]++] = eb[i];
        int[] tin = new int[n], low = new int[n], it = new int[n], st = new int[n], call = new int[n];
        boolean[] onStack = new boolean[n];
        Arrays.fill(tin, -1);
        int timer = 0, sp = 0, cp = 0;
        long total = 0, ways = 1;
        for (int s = 0; s < n; s++) {
            if (tin[s] != -1) continue;
            tin[s] = low[s] = timer++; st[sp++] = s; onStack[s] = true; it[s] = start[s]; call[cp++] = s;
            while (cp > 0) {
                int u = call[cp - 1];
                if (it[u] < start[u + 1]) {
                    int v = adj[it[u]++];
                    if (tin[v] == -1) { tin[v] = low[v] = timer++; st[sp++] = v; onStack[v] = true; it[v] = start[v]; call[cp++] = v; }
                    else if (onStack[v] && tin[v] < low[u]) low[u] = tin[v];
                } else {
                    cp--;
                    if (cp > 0 && low[u] < low[call[cp - 1]]) low[call[cp - 1]] = low[u];
                    if (low[u] == tin[u]) {
                        long mn = Long.MAX_VALUE, cnt = 0;
                        int x;
                        do {
                            x = st[--sp]; onStack[x] = false;
                            if (cost[x] < mn) { mn = cost[x]; cnt = 1; } else if (cost[x] == mn) cnt++;
                        } while (x != u);
                        total += mn;
                        ways = ways * cnt % MOD;
                    }
                }
            }
        }
        System.out.println(total + " " + ways);
    }
}
```

</details>

<!-- test
in:
4
2 2 5 1
4
1 2
2 1
3 4
4 3
out:
3 2
-->
<!-- test
in:
1
7
0
out:
7 1
-->
<!-- test
in:
3
0 0 0
3
1 2
2 3
3 1
out:
0 3
-->

### Example 4 — Coin Collector (DP on the condensation)  ·  ★ ≈1900

- **Source:** [CSES 1686 · Coin Collector](https://cses.fi/problemset/task/1686)
- **Difficulty:** ≈1900 (est.)
- **Problem:** $n \le 10^5$ rooms with $k_i \le 10^9$ coins each and $m \le 2\cdot10^5$ one-way tunnels. Walk along tunnels
  starting and ending anywhere, collecting the coins of every room you enter (each room's coins once). Maximize the total.
- **Thinking from first principles:** revisits are allowed, so once you are inside an SCC you can collect all of it and leave
  through any of its vertices. Walks therefore correspond to paths in the condensation, each SCC weighted by its coin sum —
  a longest-path problem on a DAG with positive vertex weights. Tarjan's reverse-topological numbering removes the need for a
  separate topological sort: every condensation edge goes from a larger id to a smaller one, so computing $dp[c] =
  \text{sum}[c] + \max_{c\to c'} dp[c']$ in increasing $c$ reads only finished values.

<details><summary>Solution</summary>

Tarjan → `comp`, `sum`; `best[c]` = best walk starting in component `c`; iterate components $0..k-1$, scanning original
edges grouped by component. Totals up to $10^{14}$: 64-bit. $O(n+m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<ll> coins(n);
    for (auto& c : coins) cin >> c;
    vector<vector<int>> g(n);
    for (int i = 0; i < m; i++) {
        int a, b;
        cin >> a >> b;
        g[a - 1].push_back(b - 1);
    }
    vector<int> tin(n, -1), low(n), it(n, 0), comp(n), st, call;
    vector<char> onStack(n, 0);
    vector<vector<int>> members;
    int timer = 0;
    for (int s = 0; s < n; s++) {
        if (tin[s] != -1) continue;
        tin[s] = low[s] = timer++; st.push_back(s); onStack[s] = 1; call.push_back(s);
        while (!call.empty()) {
            int u = call.back();
            if (it[u] < (int)g[u].size()) {
                int v = g[u][it[u]++];
                if (tin[v] == -1) { tin[v] = low[v] = timer++; st.push_back(v); onStack[v] = 1; call.push_back(v); }
                else if (onStack[v]) low[u] = min(low[u], tin[v]);
            } else {
                call.pop_back();
                if (!call.empty()) low[call.back()] = min(low[call.back()], low[u]);
                if (low[u] == tin[u]) {
                    members.emplace_back();
                    int x;
                    do { x = st.back(); st.pop_back(); onStack[x] = 0; comp[x] = members.size() - 1; members.back().push_back(x); } while (x != u);
                }
            }
        }
    }
    int k = members.size();
    vector<ll> best(k, 0);
    ll ans = 0;
    for (int c = 0; c < k; c++) {                   // successors of c have smaller ids: already final
        ll out = 0, sum = 0;
        for (int x : members[c]) {
            sum += coins[x];
            for (int y : g[x]) if (comp[y] != c) out = max(out, best[comp[y]]);
        }
        best[c] = sum + out;
        ans = max(ans, best[c]);
    }
    cout << ans << "\n";
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
        long[] coins = new long[n];
        for (int i = 0; i < n; i++) coins[i] = nextInt();
        int[] ea = new int[m], eb = new int[m], start = new int[n + 1];
        for (int i = 0; i < m; i++) { ea[i] = nextInt() - 1; eb[i] = nextInt() - 1; start[ea[i] + 1]++; }
        for (int i = 0; i < n; i++) start[i + 1] += start[i];
        int[] adj = new int[m], pos = Arrays.copyOf(start, n);
        for (int i = 0; i < m; i++) adj[pos[ea[i]]++] = eb[i];
        int[] tin = new int[n], low = new int[n], it = new int[n], comp = new int[n], st = new int[n], call = new int[n];
        int[] popOrder = new int[n], compStart = new int[n + 1];       // members of comp c: popOrder[compStart[c] .. compStart[c+1])
        boolean[] onStack = new boolean[n];
        Arrays.fill(tin, -1);
        int timer = 0, sp = 0, cp = 0, k = 0, popped = 0;
        for (int s = 0; s < n; s++) {
            if (tin[s] != -1) continue;
            tin[s] = low[s] = timer++; st[sp++] = s; onStack[s] = true; it[s] = start[s]; call[cp++] = s;
            while (cp > 0) {
                int u = call[cp - 1];
                if (it[u] < start[u + 1]) {
                    int v = adj[it[u]++];
                    if (tin[v] == -1) { tin[v] = low[v] = timer++; st[sp++] = v; onStack[v] = true; it[v] = start[v]; call[cp++] = v; }
                    else if (onStack[v] && tin[v] < low[u]) low[u] = tin[v];
                } else {
                    cp--;
                    if (cp > 0 && low[u] < low[call[cp - 1]]) low[call[cp - 1]] = low[u];
                    if (low[u] == tin[u]) {
                        compStart[k] = popped;
                        int x;
                        do { x = st[--sp]; onStack[x] = false; comp[x] = k; popOrder[popped++] = x; } while (x != u);
                        k++;
                    }
                }
            }
        }
        compStart[k] = popped;
        long[] best = new long[k];
        long ans = 0;
        for (int c = 0; c < k; c++) {
            long out = 0, sum = 0;
            for (int i = compStart[c]; i < compStart[c + 1]; i++) {
                int x = popOrder[i];
                sum += coins[x];
                for (int e = start[x]; e < start[x + 1]; e++) if (comp[adj[e]] != c) out = Math.max(out, best[comp[adj[e]]]);
            }
            best[c] = sum + out;
            ans = Math.max(ans, best[c]);
        }
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
4 4
5 1 2 7
1 2
2 1
2 3
4 3
out:
9
-->
<!-- test
in:
1 0
10
out:
10
-->
<!-- test
in:
3 3
1000000000 1000000000 1000000000
1 2
2 3
3 1
out:
3000000000
-->

### Example 5 — Reachability from the Capital  ·  ★ 2000

- **Source:** [CF 999E · Reachability from the Capital](https://codeforces.com/problemset/problem/999/E) — 2000
- **Difficulty:** 2000
- **Problem:** $n, m \le 5000$, a directed graph and a capital $s$. Add the minimum number of new one-way roads so that
  every city is reachable from $s$; print that number.
- **Thinking from first principles:** contract SCCs. A component with no incoming condensation edge (a **source**) can only
  be reached through a new edge into it — unless it is $s$'s own component. So the answer is at least the number of sources
  other than $\text{SCC}(s)$. It is also enough: add $s \to$ (any vertex of each such source); every component is reachable
  from some source (walk backwards along incoming edges in the DAG until you hit one). A greedy "add an edge to the unreached
  vertex that reaches the most" also works for these limits but needs a proof and $O(n(n+m))$ time; the SCC argument is
  linear and obviously optimal.

<details><summary>Solution</summary>

Tarjan; mark components that receive an edge from a different component; count unmarked components except `comp[s]`.
$O(n+m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m, s;
    cin >> n >> m >> s;
    --s;
    vector<vector<int>> g(n);
    for (int i = 0; i < m; i++) {
        int u, v;
        cin >> u >> v;
        g[u - 1].push_back(v - 1);
    }
    vector<int> tin(n, -1), low(n), it(n, 0), comp(n), st, call;
    vector<char> onStack(n, 0);
    int timer = 0, k = 0;
    for (int r = 0; r < n; r++) {
        if (tin[r] != -1) continue;
        tin[r] = low[r] = timer++; st.push_back(r); onStack[r] = 1; call.push_back(r);
        while (!call.empty()) {
            int u = call.back();
            if (it[u] < (int)g[u].size()) {
                int v = g[u][it[u]++];
                if (tin[v] == -1) { tin[v] = low[v] = timer++; st.push_back(v); onStack[v] = 1; call.push_back(v); }
                else if (onStack[v]) low[u] = min(low[u], tin[v]);
            } else {
                call.pop_back();
                if (!call.empty()) low[call.back()] = min(low[call.back()], low[u]);
                if (low[u] == tin[u]) {
                    int x;
                    do { x = st.back(); st.pop_back(); onStack[x] = 0; comp[x] = k; } while (x != u);
                    k++;
                }
            }
        }
    }
    vector<char> hasIn(k, 0);
    for (int u = 0; u < n; u++)
        for (int v : g[u]) if (comp[u] != comp[v]) hasIn[comp[v]] = 1;
    int ans = 0;
    for (int c = 0; c < k; c++) if (!hasIn[c] && c != comp[s]) ans++;
    cout << ans << "\n";
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
        int n = nextInt(), m = nextInt(), s = nextInt() - 1;
        int[] ea = new int[m], eb = new int[m], start = new int[n + 1];
        for (int i = 0; i < m; i++) { ea[i] = nextInt() - 1; eb[i] = nextInt() - 1; start[ea[i] + 1]++; }
        for (int i = 0; i < n; i++) start[i + 1] += start[i];
        int[] adj = new int[m], pos = Arrays.copyOf(start, n);
        for (int i = 0; i < m; i++) adj[pos[ea[i]]++] = eb[i];
        int[] tin = new int[n], low = new int[n], it = new int[n], comp = new int[n], st = new int[n], call = new int[n];
        boolean[] onStack = new boolean[n];
        Arrays.fill(tin, -1);
        int timer = 0, sp = 0, cp = 0, k = 0;
        for (int r = 0; r < n; r++) {
            if (tin[r] != -1) continue;
            tin[r] = low[r] = timer++; st[sp++] = r; onStack[r] = true; it[r] = start[r]; call[cp++] = r;
            while (cp > 0) {
                int u = call[cp - 1];
                if (it[u] < start[u + 1]) {
                    int v = adj[it[u]++];
                    if (tin[v] == -1) { tin[v] = low[v] = timer++; st[sp++] = v; onStack[v] = true; it[v] = start[v]; call[cp++] = v; }
                    else if (onStack[v] && tin[v] < low[u]) low[u] = tin[v];
                } else {
                    cp--;
                    if (cp > 0 && low[u] < low[call[cp - 1]]) low[call[cp - 1]] = low[u];
                    if (low[u] == tin[u]) {
                        int x;
                        do { x = st[--sp]; onStack[x] = false; comp[x] = k; } while (x != u);
                        k++;
                    }
                }
            }
        }
        boolean[] hasIn = new boolean[k];
        for (int i = 0; i < m; i++) if (comp[ea[i]] != comp[eb[i]]) hasIn[comp[eb[i]]] = true;
        int ans = 0;
        for (int c = 0; c < k; c++) if (!hasIn[c] && c != comp[s]) ans++;
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
5 3 1
2 3
3 2
4 5
out:
2
-->
<!-- test
in:
3 2 1
1 2
2 3
out:
0
-->
<!-- test
in:
1 0 1
out:
0
-->
<!-- test
in:
4 4 2
1 2
2 1
3 4
4 3
out:
1
-->

### Example 6 — Fewest new edges to make a graph strongly connected  ·  ★ ≈2100

- **Source:** Original problem (the counting half of [CSES 1685 · New Flight Routes](https://cses.fi/problemset/task/1685), which also asks for the edges).
- **Difficulty:** ≈2100 (est.)
- **Problem:** A directed graph with $n \le 10^5$ vertices and $m \le 2\cdot10^5$ edges. Print the minimum number of
  directed edges to add so that the graph becomes strongly connected.
- **Thinking from first principles:** in the condensation, a source component needs a new edge *into* it and a sink
  component needs a new edge *out of* it, and one new edge is "into" for one component and "out of" for one component. So
  with $s$ sources and $t$ sinks at least $\max(s,t)$ edges are needed (an isolated component is both a source and a sink).
  With a single SCC the answer is 0 — careful: that one component is both a source and a sink, so the formula would say 1.
  The theorem of Eswaran and Tarjan says $\max(s,t)$ always suffices for $\ge 2$ components; the hidden tests below were
  checked against an exhaustive search over added edge sets.

<details><summary>Solution</summary>

Tarjan; mark components with an incoming / outgoing cross edge; count sources and sinks. $O(n+m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<vector<int>> g(n);
    vector<pair<int, int>> edges(m);
    for (auto& [u, v] : edges) {
        cin >> u >> v;
        --u; --v;
        g[u].push_back(v);
    }
    vector<int> tin(n, -1), low(n), it(n, 0), comp(n), st, call;
    vector<char> onStack(n, 0);
    int timer = 0, k = 0;
    for (int r = 0; r < n; r++) {
        if (tin[r] != -1) continue;
        tin[r] = low[r] = timer++; st.push_back(r); onStack[r] = 1; call.push_back(r);
        while (!call.empty()) {
            int u = call.back();
            if (it[u] < (int)g[u].size()) {
                int v = g[u][it[u]++];
                if (tin[v] == -1) { tin[v] = low[v] = timer++; st.push_back(v); onStack[v] = 1; call.push_back(v); }
                else if (onStack[v]) low[u] = min(low[u], tin[v]);
            } else {
                call.pop_back();
                if (!call.empty()) low[call.back()] = min(low[call.back()], low[u]);
                if (low[u] == tin[u]) {
                    int x;
                    do { x = st.back(); st.pop_back(); onStack[x] = 0; comp[x] = k; } while (x != u);
                    k++;
                }
            }
        }
    }
    if (k == 1) { cout << 0 << "\n"; return 0; }
    vector<char> hasIn(k, 0), hasOut(k, 0);
    for (auto [u, v] : edges)
        if (comp[u] != comp[v]) { hasOut[comp[u]] = 1; hasIn[comp[v]] = 1; }
    int sources = 0, sinks = 0;
    for (int c = 0; c < k; c++) { sources += !hasIn[c]; sinks += !hasOut[c]; }
    cout << max(sources, sinks) << "\n";
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
        int[] ea = new int[m], eb = new int[m], start = new int[n + 1];
        for (int i = 0; i < m; i++) { ea[i] = nextInt() - 1; eb[i] = nextInt() - 1; start[ea[i] + 1]++; }
        for (int i = 0; i < n; i++) start[i + 1] += start[i];
        int[] adj = new int[m], pos = Arrays.copyOf(start, n);
        for (int i = 0; i < m; i++) adj[pos[ea[i]]++] = eb[i];
        int[] tin = new int[n], low = new int[n], it = new int[n], comp = new int[n], st = new int[n], call = new int[n];
        boolean[] onStack = new boolean[n];
        Arrays.fill(tin, -1);
        int timer = 0, sp = 0, cp = 0, k = 0;
        for (int r = 0; r < n; r++) {
            if (tin[r] != -1) continue;
            tin[r] = low[r] = timer++; st[sp++] = r; onStack[r] = true; it[r] = start[r]; call[cp++] = r;
            while (cp > 0) {
                int u = call[cp - 1];
                if (it[u] < start[u + 1]) {
                    int v = adj[it[u]++];
                    if (tin[v] == -1) { tin[v] = low[v] = timer++; st[sp++] = v; onStack[v] = true; it[v] = start[v]; call[cp++] = v; }
                    else if (onStack[v] && tin[v] < low[u]) low[u] = tin[v];
                } else {
                    cp--;
                    if (cp > 0 && low[u] < low[call[cp - 1]]) low[call[cp - 1]] = low[u];
                    if (low[u] == tin[u]) {
                        int x;
                        do { x = st[--sp]; onStack[x] = false; comp[x] = k; } while (x != u);
                        k++;
                    }
                }
            }
        }
        if (k == 1) { System.out.println(0); return; }
        boolean[] hasIn = new boolean[k], hasOut = new boolean[k];
        for (int i = 0; i < m; i++) if (comp[ea[i]] != comp[eb[i]]) { hasOut[comp[ea[i]]] = true; hasIn[comp[eb[i]]] = true; }
        int sources = 0, sinks = 0;
        for (int c = 0; c < k; c++) { if (!hasIn[c]) sources++; if (!hasOut[c]) sinks++; }
        System.out.println(Math.max(sources, sinks));
    }
}
```

</details>

<!-- test
in:
3 0
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
1
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
5 4
1 3
2 3
3 4
3 5
out:
2
-->
<!-- test
in:
1 0
out:
0
-->

## 6. Tricks, pitfalls and things to remember

1. **Tarjan: only edges to on-stack vertices update `low`.** An edge into an already completed SCC must be ignored; using it
   merges unrelated components (the most common Tarjan bug).
2. **Tarjan: propagate `low` from child to parent when the child finishes** — in the iterative version this is the
   `low[parent] = min(low[parent], low[u])` line after popping `u` from the call stack.
3. **Know the numbering direction.** Tarjan: reverse topological (sinks first). Kosaraju: topological. Mixing them up flips DP
   directions and 2-SAT assignments.
4. **Kosaraju pass 1 must be a real DFS post-order** (iterator stack). The "push all neighbors" pseudo-DFS gives wrong finish
   times. Pass 2 can be any traversal.
5. **Recursion depth:** a single long cycle of $10^5$ vertices is a DFS chain of depth $10^5$. Java default stack → crash;
   always use the iterative code (or a big-stack thread).
6. **Single component special cases:** "add edges to make strongly connected" is 0, not $\max(1,1)=1$; "sources other than
   the capital's" must exclude the capital's component even if it is a source.
7. **Self-loops and multi-edges** are harmless for SCC detection, but a vertex with a self-loop *is* on a cycle although its
   SCC has size 1 — check explicitly when "on a cycle" matters.
8. **Duplicate condensation edges** are fine for max/min DP but double-count in counting DPs; deduplicate (§3.3) when counting
   paths in the condensation.
9. **Output normalization:** when any labeling is accepted, relabel by first occurrence to make tests deterministic (Example 2).
10. **Memory in Java:** one `int[]` per Tarjan field ($\approx 7n$ ints) plus CSR; avoid `ArrayList<Integer>` per vertex for
    $n = 10^5$+, especially for the reversed graph in Kosaraju.
11. **Weak vs strong connectivity:** "connected" in a directed problem may mean "ignoring directions" (DSU) — read the
    statement.
12. **Overflow** in SCC sums: $10^5 \cdot 10^9$ needs 64 bits (Example 4).

## 7. Going further (toward 2400–2600+)

- **SCC of product/state graphs:** (vertex, day mod $d$) in CF 1137C Museums Tour — $n\cdot d$ states, then DP on the
  condensation counting distinct museums per component (careful: the same museum may appear in several states of one SCC).
- **Counting paths with infinity** (CF 1547G How Many Paths?): classify each vertex as 0 / 1 / "many" / "infinite" paths from
  vertex 1 using the condensation and a "contains a cycle" flag per component.
- **Cycle-length arithmetic in an SCC** (CF 1515G Phoenix and Odometers, 2700): the set of closed-walk lengths through a vertex
  is the set of multiples of $g$ = gcd over edges $u\to v$ in the SCC of $d(u) + w - d(v)$ for any DFS potentials $d$.
- **Sink components as certificates** (CF 1239D Catowice City, CF 949C Data Center Maintenance): a sink SCC is a minimal
  "closed" set under the reachability relation; many constructive problems pick the smallest sink.
- **Augmentation with construction** (CSES 1685 New Flight Routes): pair sinks to sources along a DFS over the condensation
  so that the new edges chain all sink–source pairs into one cycle; the classic proof is Eswaran–Tarjan (1976).
- **Incremental SCC / online condensation** (edges added over time) needs offline divide-and-conquer on time — an IGM-level
  technique ([offline techniques](../16-IGM-Frontier/01-offline-techniques-cdq-parallel-binary-search.md)).
- **2-SAT** is the most frequent contest use of SCC after condensation DP: [2-SAT](07-two-sat.md).

## 8. Practice ladder

**1400–1900**
- [ ] [CSES 1682 · Flight Routes Check](https://cses.fi/problemset/task/1682) — two BFS
- [ ] [CSES 1683 · Planets and Kingdoms](https://cses.fi/problemset/task/1683) — SCC labels
- [ ] [AtCoder PRACTICE2 G · SCC](https://atcoder.jp/contests/practice2/tasks/practice2_g) — print SCCs in topological order
- [ ] [AtCoder ABC245 F · Endless Walk](https://atcoder.jp/contests/abc245/tasks/abc245_f) — vertices that can walk forever
- [ ] [CF 427C · Checkposts](https://codeforces.com/problemset/problem/427/C) — 1700
- [ ] [CSES 1686 · Coin Collector](https://cses.fi/problemset/task/1686) — condensation DP
- [ ] [CF 949C · Data Center Maintenance](https://codeforces.com/problemset/problem/949/C) — 1900

**1900–2400**
- [ ] [CF 999E · Reachability from the Capital](https://codeforces.com/problemset/problem/999/E) — 2000
- [ ] [CSES 2143 · Reachability Queries](https://cses.fi/problemset/task/2143) — condensation + bitsets
- [ ] [CF 1547G · How Many Paths?](https://codeforces.com/problemset/problem/1547/G) — 2100
- [ ] [CF 402E · Strictly Positive Matrix](https://codeforces.com/problemset/problem/402/E) — 2200
- [ ] [CF 505D · Mr. Kitayuta's Technology](https://codeforces.com/problemset/problem/505/D) — 2200
- [ ] [CF 22E · Scheme](https://codeforces.com/problemset/problem/22/E) — 2300
- [ ] [CSES 1685 · New Flight Routes](https://cses.fi/problemset/task/1685) — construct the $\max(s,t)$ edges

**2400+**
- [ ] [CF 1239D · Catowice City](https://codeforces.com/problemset/problem/1239/D) — 2400
- [ ] [CF 1137C · Museums Tour](https://codeforces.com/problemset/problem/1137/C) — 2500
- [ ] [CF 1515G · Phoenix and Odometers](https://codeforces.com/problemset/problem/1515/G) — 2700

## 9. LeetCode / FAANG cross-reference

Rare in interviews: SCC algorithms are considered specialist knowledge. Interviews ask the *consequences* (cycles, sources,
reachability) and accept simpler tools.

- [LC 1557 · Minimum Number of Vertices to Reach All Nodes](https://leetcode.com/problems/minimum-number-of-vertices-to-reach-all-nodes/) — Medium — sources of a DAG (Example 5's idea without cycles).
- [LC 802 · Find Eventual Safe States](https://leetcode.com/problems/find-eventual-safe-states/) — Medium — vertices that cannot reach a cycle (reverse Kahn; SCC also works).
- [LC 2360 · Longest Cycle in a Graph](https://leetcode.com/problems/longest-cycle-in-a-graph/) — Hard — out-degree ≤ 1, so SCCs are simple cycles ([functional graphs](10-functional-graphs-and-special-graphs.md)).
- [LC 2127 · Maximum Employees to Be Invited to a Meeting](https://leetcode.com/problems/maximum-employees-to-be-invited-to-a-meeting/) — Hard — functional graph cycles and the trees hanging off them.
- [LC 1192 · Critical Connections in a Network](https://leetcode.com/problems/critical-connections-in-a-network/) — Hard — the undirected cousin (bridges, low-link).
- [LC 207 · Course Schedule](https://leetcode.com/problems/course-schedule/) — Medium — "is there a cycle" = "is some SCC larger than 1".

## 10. Self-check

1. Prove that the condensation is acyclic.
2. State and prove the finish-time lemma that Kosaraju relies on.
3. Why does Kosaraju's second pass run on the *reversed* graph, in *decreasing* finish time?
4. In Tarjan, why must edges to vertices that are visited but no longer on the stack be ignored?
5. In which order does Tarjan number components, and why does Example 4 not need a topological sort?
6. How many edges must be added to make a graph with 5 SCCs, 2 sources and 3 sinks strongly connected? With 1 SCC?
7. How do you test strong connectivity of the whole graph without an SCC algorithm?
8. Why is the answer to CF 999E the number of source components other than the capital's?

<details><summary>Answers</summary>

1. A cycle of components would make all their vertices mutually reachable, merging them into one SCC.
2. For an edge $C\to C'$, $\max_C\text{tout} > \max_{C'}\text{tout}$: if DFS enters $C$ first, all of $C\cup C'$ becomes its
   descendants; if it enters $C'$ first, $C'$ finishes entirely before $C$ is discovered (no path back from $C'$ to $C$).
3. The largest finish time lies in a source SCC of $G$, which is a sink of $G^R$, so a traversal of $G^R$ from it cannot leave
   the SCC. Removing it and repeating keeps the invariant.
4. Such a vertex belongs to an already completed SCC that cannot reach back to the current path; letting it lower `low` would
   make a non-root look like it reaches an ancestor and merge separate SCCs.
5. Reverse topological: an SCC is popped only after all SCCs reachable from it. So every condensation edge goes from a larger
   id to a smaller id, and processing ids in increasing order computes "best walk starting here" from finished successors.
6. $\max(2,3) = 3$. With one SCC: 0.
7. BFS from vertex 1 in $G$ and in $G^R$; strongly connected iff both reach all vertices.
8. Each source component other than the capital's has no incoming edge from outside, so it needs at least one new road; one
   road from the capital to each source suffices because every component is reachable from some source.

</details>
