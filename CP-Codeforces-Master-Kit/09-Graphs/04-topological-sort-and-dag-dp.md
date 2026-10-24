# Topological Sort and DP on DAGs

> **Band:** 🟢 1200 → 🟠 2300 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [BFS/DFS, three colors](01-graph-representation-bfs-dfs.md), [heaps](../08-Data-Structures/10-ordered-sets-pbds-and-heaps.md), [DP first principles](../06-Dynamic-Programming/01-dp-first-principles-and-state-design.md)
> **You can say you know this when:** you can prove that a graph has a topological order iff it is acyclic, write Kahn's algorithm (with cycle detection) and the reverse-post-order DFS from memory, produce the lexicographically smallest order *and* know why "smallest labels" (CF 825E) needs the reversed graph, and run longest-path / path-counting / per-letter DPs over a DAG in one pass.

## 1. First principles — why this works

**What a topological order is.** A linear order of the vertices such that every edge $u\to v$ goes forward ($u$ before $v$).
Prerequisites, build systems, spreadsheet recomputation, "letters of an unknown alphabet" — any set of "must come before"
constraints is a directed graph, and a valid schedule is a topological order.

**Existence: an order exists iff the graph has no directed cycle.** A cycle $v_1\to\dots\to v_k\to v_1$ would need
$v_1$ before itself. Conversely, a DAG always has a **source** (in-degree 0): if every vertex had an incoming edge, walking
backwards along incoming edges forever would revisit a vertex, closing a cycle. Put a source first, delete it (still a DAG),
repeat. This proof *is* an algorithm.

**Kahn's algorithm.** Maintain in-degrees and a queue of current sources. Pop a source, append it to the order, delete its
outgoing edges (decrement in-degrees), push vertices that become sources. Each vertex and edge is handled once: $O(n+m)$.
*Cycle detection for free:* if fewer than $n$ vertices are output, the remaining ones all have positive in-degree inside the
remaining subgraph, which therefore contains a cycle (by the source argument above). The leftover vertices are exactly those
on a cycle or reachable from one.

**DFS: reverse post-order.** Run DFS; when a vertex finishes, append it to a list; reverse the list. *Why:* for an edge
$u\to v$, when DFS scans it at $u$: if $v$ is white, it becomes a descendant and finishes before $u$; if $v$ is black, it
already finished; $v$ gray would be a back edge — a cycle. So in a DAG, $\text{tout}(v) < \text{tout}(u)$ for every edge, and
decreasing finish time is a topological order. Use the iterative DFS of [file 01](01-graph-representation-bfs-dfs.md) for
deep graphs. (This is the same post-order Kosaraju's SCC algorithm uses — see [SCC](05-scc-and-condensation.md).)

**Choosing among valid orders.**
- *Lexicographically smallest order:* Kahn with a **min-heap** instead of a queue. Exchange argument: whichever sources are
  available now, any of them may be placed next without restricting the rest more than another choice would (placing a source
  only *adds* sources). So placing the smallest available source first is optimal for the lexicographic comparison, which is
  decided at the first position. $O((n+m)\log n)$.
- *"Vertex 1 as early as possible, then vertex 2, …"* (minimize the **position** of 1, then of 2, … — CF 825E Minimal Labels) is
  a **different** objective. Counterexample: $n=3$, edge $3\to1$. Smallest order is $(2,3,1)$, putting vertex 1 last; but
  $(3,1,2)$ puts 1 at position 2. The correct greedy works **backwards**: on the reversed graph, repeatedly take the **largest**
  available vertex and give it the **largest** free label. Proof idea: the vertex placed last should be the largest index that
  can be last — any small index pushed to the end would only hurt the labels of small vertices.
- *Is the order unique?* Iff Kahn always has exactly one source, iff consecutive vertices of the order are joined by edges (the
  DAG has a Hamiltonian path).
- *Counting orders* (linear extensions) is #P-hard in general; for $n \le 20$ use DP over subsets: $f(S \cup \{v\})
  \mathrel{+}= f(S)$ when all predecessors of $v$ lie in $S$ ([bitmask DP](../06-Dynamic-Programming/06-bitmask-dp.md)).

**DP on a DAG.** A DAG is exactly the dependency structure that makes DP possible: process vertices in topological order and
every value you read was already final. One pass, $O(n+m)$:
- **Longest / shortest path** from a source with *any* weights (negative allowed — no cycles to exploit): $dp[v] =
  \max_{u\to v}(dp[u] + w)$. Remember to keep unreachable vertices at $-\infty$.
- **Counting paths** $1\leadsto n$: $cnt[v] = \sum_{u\to v} cnt[u]$, modulo a prime.
- **Per-label DP**: $dp[v][c]$ = best count of letter $c$ on a path ending at $v$ (CF 919D) — the state carries what the
  objective needs.
- **Scheduling (critical path):** if every task has a duration and unlimited parallelism, the earliest finish time is the
  longest weighted path; the minimum number of rounds/semesters is the number of vertices on the longest path (Kahn by layers).
  With "at most $k$ tasks per round" it becomes hard in general (LC 1494 uses bitmask DP).
- **Reachability counts** ("how many vertices can each vertex reach"): sets don't add up along a DAG (paths overlap), so use
  bitsets: $\text{reach}[u] = \{u\} \cup \bigcup_{u\to v}\text{reach}[v]$ in reverse topological order, $O(nm/64)$.

Many 1700–2100 problems are "find the DAG hidden in the statement": comparisons between adjacent strings (CF 510C), edges
directed from lower to higher value (LC 329 Longest Increasing Path in a Matrix), or the **condensation** of a general directed
graph into its strongly connected components ([SCC and condensation](05-scc-and-condensation.md)). More DAG-DP patterns live in
[DP on DAGs and graphs](../06-Dynamic-Programming/09-dp-on-dags-and-graphs.md).

## 2. Formulas, definitions and identities

- **Existence:** topological order exists $\iff$ no directed cycle $\iff$ DFS finds no back edge $\iff$ Kahn outputs $n$ vertices.
- **Kahn invariant:** $\text{indeg}'(v)$ = number of *unprocessed* in-neighbors; $v$ enters the queue exactly when it drops to 0.
- **DFS order:** for every edge $u\to v$ of a DAG, $\text{tout}(v) < \text{tout}(u)$; order by decreasing $\text{tout}$.
- **Uniqueness:** unique $\iff$ $|\text{queue}| = 1$ at every step $\iff$ $(o_i, o_{i+1})$ is an edge for all $i$.
- **Longest path:** $dp[v] = \max\big(\text{start}(v), \max_{u\to v} dp[u] + w(u,v)\big)$; shortest path: $\min$. $O(n+m)$.
- **Paths count:** $cnt[s]=1$, $cnt[v] = \sum_{u\to v} cnt[u] \pmod p$.
- **Layers:** $\text{level}(v) = 1 + \max_{u\to v}\text{level}(u)$ (sources at 1); minimum number of rounds $= \max_v\text{level}(v)$.
- **Linear extensions (small $n$):** $f(\emptyset)=1$, $f(S\cup\{v\}) \mathrel{+}= f(S)$ if $\text{pred}(v)\subseteq S$; $O(2^n n)$.
- **Reachability:** $\text{reach}[u] = \{u\}\cup\bigcup_{u\to v}\text{reach}[v]$; $O(n(n+m)/64)$ time, $O(n^2/64)$ memory.
- **Complexities:** Kahn / DFS $O(n+m)$; lexicographically smallest (heap) $O((n+m)\log n)$.

## 3. Implementation (C++ and Java)

### 3.1 Kahn's algorithm (returns an empty order if there is a cycle)

```cpp
// Vertices 0..n-1, g[u] = out-neighbors.  If `smallest`, returns the lexicographically smallest order.
vector<int> topoKahn(const vector<vector<int>>& g, bool smallest = false) {
    int n = g.size();
    vector<int> indeg(n, 0), order;
    for (int u = 0; u < n; u++) for (int v : g[u]) indeg[v]++;
    priority_queue<int, vector<int>, greater<>> heap;     // used only when `smallest`
    vector<int> q;
    for (int v = 0; v < n; v++) if (!indeg[v]) { if (smallest) heap.push(v); else q.push_back(v); }
    for (size_t h = 0;;) {
        int u;
        if (smallest) { if (heap.empty()) break; u = heap.top(); heap.pop(); }
        else { if (h == q.size()) break; u = q[h++]; }
        order.push_back(u);
        for (int v : g[u])
            if (--indeg[v] == 0) { if (smallest) heap.push(v); else q.push_back(v); }
    }
    if ((int)order.size() < n) order.clear();              // a cycle exists
    return order;
}
```

```java
// CSR graph: out-neighbors of u are adj[start[u] .. start[u+1]).  Returns null if there is a cycle.
static int[] topoKahn(int n, int[] start, int[] adj, boolean smallest) {
    int[] indeg = new int[n], order = new int[n];
    for (int e = 0; e < start[n]; e++) indeg[adj[e]]++;
    PriorityQueue<Integer> heap = new PriorityQueue<>();   // only for the lexicographic variant
    int[] q = new int[n];
    int qh = 0, qt = 0, cnt = 0;
    for (int v = 0; v < n; v++) if (indeg[v] == 0) { if (smallest) heap.add(v); else q[qt++] = v; }
    while (smallest ? !heap.isEmpty() : qh < qt) {
        int u = smallest ? heap.poll() : q[qh++];
        order[cnt++] = u;
        for (int e = start[u]; e < start[u + 1]; e++) {
            int v = adj[e];
            if (--indeg[v] == 0) { if (smallest) heap.add(v); else q[qt++] = v; }
        }
    }
    return cnt == n ? order : null;
}
```

### 3.2 DFS reverse post-order (iterative) with cycle detection

```cpp
// Returns a topological order, or an empty vector if a back edge (cycle) is found.
vector<int> topoDfs(const vector<vector<int>>& g) {
    int n = g.size();
    vector<int> color(n, 0), it(n, 0), post, st;
    for (int s = 0; s < n; s++) {
        if (color[s]) continue;
        color[s] = 1; st.push_back(s);
        while (!st.empty()) {
            int u = st.back();
            if (it[u] < (int)g[u].size()) {
                int v = g[u][it[u]++];
                if (color[v] == 1) return {};                  // back edge
                if (color[v] == 0) { color[v] = 1; st.push_back(v); }
            } else { color[u] = 2; post.push_back(u); st.pop_back(); }
        }
    }
    reverse(post.begin(), post.end());
    return post;
}
```

```java
static int[] topoDfs(int n, int[] start, int[] adj) {
    int[] color = new int[n], it = new int[n], st = new int[n], post = new int[n];
    int pc = 0;
    for (int s = 0; s < n; s++) {
        if (color[s] != 0) continue;
        int top = 0;
        color[s] = 1; it[s] = start[s]; st[top++] = s;
        while (top > 0) {
            int u = st[top - 1];
            if (it[u] < start[u + 1]) {
                int v = adj[it[u]++];
                if (color[v] == 1) return null;
                if (color[v] == 0) { color[v] = 1; it[v] = start[v]; st[top++] = v; }
            } else { color[u] = 2; post[pc++] = u; top--; }
        }
    }
    for (int i = 0, j = n - 1; i < j; i++, j--) { int t = post[i]; post[i] = post[j]; post[j] = t; }
    return post;
}
```

### 3.3 Reachability counts with bitsets (each vertex: how many vertices it can reach)

```cpp
// n up to ~5*10^4 with m up to ~10^5 fits in time; memory n^2/8 bytes (5*10^4 -> 312 MB is too much: chunk the targets).
template <int N>
vector<int> reachCounts(const vector<vector<int>>& g, const vector<int>& topo) {
    int n = g.size();
    vector<bitset<N>> reach(n);
    for (int i = n - 1; i >= 0; i--) {                     // reverse topological order
        int u = topo[i];
        reach[u][u] = 1;
        for (int v : g[u]) reach[u] |= reach[v];
    }
    vector<int> res(n);
    for (int u = 0; u < n; u++) res[u] = reach[u].count();
    return res;
}
```

```java
static int[] reachCounts(int n, int[] start, int[] adj, int[] topo) {
    int words = (n + 63) >>> 6;
    long[][] reach = new long[n][words];
    for (int i = n - 1; i >= 0; i--) {
        int u = topo[i];
        long[] ru = reach[u];
        ru[u >>> 6] |= 1L << (u & 63);
        for (int e = start[u]; e < start[u + 1]; e++) {
            long[] rv = reach[adj[e]];
            for (int w = 0; w < words; w++) ru[w] |= rv[w];
        }
    }
    int[] res = new int[n];
    for (int u = 0; u < n; u++) { int c = 0; for (long x : reach[u]) c += Long.bitCount(x); res[u] = c; }
    return res;
}
```

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "prerequisites", "must be done before", "dependencies", "build order" | topological sort (Kahn) |
| "is it possible to finish all", "detect a deadlock / circular dependency" | Kahn leftover or DFS back edge |
| "lexicographically smallest order satisfying constraints" | Kahn with a min-heap |
| "vertex 1 should get the smallest possible label, then vertex 2, …" | reversed graph + max-heap, labels from $n$ down |
| "sorted under an unknown alphabet" | edges from the first differing letters of adjacent words |
| "longest path", "maximum score along a route", graph guaranteed acyclic | DP in topological order |
| "number of ways/routes" in a DAG | path counting DP, modulo $p$ |
| "if it can be arbitrarily large, print −1" | a cycle reachable on a relevant path ⇒ unbounded; otherwise DAG DP |
| moves that strictly increase something (value, time, height) | the move graph is a DAG — no explicit sort needed if you process by that key |
| general directed graph with "collect everything in a cycle" | condense SCCs, then DAG DP ([file 05](05-scc-and-condensation.md)) |
| minimum number of rounds with unlimited parallelism | longest path in vertices (Kahn by layers) |

Confusions: topological order is about *edges going forward*, not about distances; a DAG may have many sources and sinks; an
undirected graph has no topological order (any edge is a 2-cycle) — "undirected acyclic" means forest.

## 5. Worked examples (graded)

### Example 1 — Course Schedule  ·  ★ ≈1300

- **Source:** [CSES 1679 · Course Schedule](https://cses.fi/problemset/task/1679)
- **Difficulty:** ≈1300 (est.)
- **Problem:** $n \le 10^5$ courses and $m \le 2\cdot10^5$ requirements "$a$ must be completed before $b$". Print an order
  in which all courses can be completed, or `IMPOSSIBLE`. Any valid order is accepted; we print the lexicographically
  smallest one so that the output is unique.
- **Thinking from first principles:** requirements are edges $a\to b$; a completion order is a topological order; it exists
  iff no cycle. Kahn gives both the order and the cycle test. Swapping the FIFO queue for a min-heap costs only a $\log$ and makes
  the answer canonical (and is exactly what some variants demand).

<details><summary>Solution</summary>

Kahn with a min-heap; `IMPOSSIBLE` if fewer than $n$ courses are output. $O((n+m)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<vector<int>> g(n + 1);
    vector<int> indeg(n + 1, 0);
    for (int i = 0; i < m; i++) {
        int a, b;
        cin >> a >> b;
        g[a].push_back(b);
        indeg[b]++;
    }
    priority_queue<int, vector<int>, greater<>> pq;
    for (int v = 1; v <= n; v++) if (!indeg[v]) pq.push(v);
    vector<int> order;
    while (!pq.empty()) {
        int u = pq.top(); pq.pop();
        order.push_back(u);
        for (int v : g[u]) if (--indeg[v] == 0) pq.push(v);
    }
    if ((int)order.size() < n) { cout << "IMPOSSIBLE\n"; return 0; }
    for (int i = 0; i < n; i++) cout << order[i] << " \n"[i + 1 == n];
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
        int[] ea = new int[m], eb = new int[m], start = new int[n + 2], indeg = new int[n + 1];
        for (int i = 0; i < m; i++) { ea[i] = nextInt(); eb[i] = nextInt(); start[ea[i] + 1]++; indeg[eb[i]]++; }
        for (int i = 0; i <= n; i++) start[i + 1] += start[i];
        int[] adj = new int[m], pos = Arrays.copyOf(start, n + 1);
        for (int i = 0; i < m; i++) adj[pos[ea[i]]++] = eb[i];
        int[] heap = new int[n];                     // hand-rolled int min-heap: no boxing
        int hs = 0;
        int[] order = new int[n];
        int cnt = 0;
        for (int v = 1; v <= n; v++) if (indeg[v] == 0) hs = push(heap, hs, v);
        while (hs > 0) {
            int u = heap[0];
            hs = pop(heap, hs);
            order[cnt++] = u;
            for (int e = start[u]; e < start[u + 1]; e++) if (--indeg[adj[e]] == 0) hs = push(heap, hs, adj[e]);
        }
        if (cnt < n) { System.out.println("IMPOSSIBLE"); return; }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < n; i++) sb.append(order[i]).append(i + 1 == n ? '\n' : ' ');
        System.out.print(sb);
    }

    static int push(int[] h, int size, int x) {
        int i = size++;
        while (i > 0 && h[(i - 1) >> 1] > x) { h[i] = h[(i - 1) >> 1]; i = (i - 1) >> 1; }
        h[i] = x;
        return size;
    }

    static int pop(int[] h, int size) {
        int x = h[--size], i = 0;
        while (2 * i + 1 < size) {
            int c = 2 * i + 1;
            if (c + 1 < size && h[c + 1] < h[c]) c++;
            if (h[c] >= x) break;
            h[i] = h[c]; i = c;
        }
        h[i] = x;
        return size;
    }
}
```

</details>

<!-- test
in:
5 4
3 1
2 5
4 5
3 2
out:
3 1 2 4 5
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
4 4
4 3
3 2
2 1
4 1
out:
4 3 2 1
-->

### Example 2 — Game Routes (counting paths)  ·  ★ ≈1500

- **Source:** [CSES 1681 · Game Routes](https://cses.fi/problemset/task/1681)
- **Difficulty:** ≈1500 (est.)
- **Problem:** A game has $n \le 10^5$ levels and $m \le 2\cdot10^5$ one-way teleporters; the teleporter graph has no directed
  cycles. Count the routes from level 1 to level $n$, modulo $10^9+7$.
- **Thinking from first principles:** a route to $v$ is a route to some in-neighbor $u$ followed by the edge $u\to v$, and
  different $u$ (or different parallel edges) give different routes — so $cnt[v] = \sum_{u\to v} cnt[u]$. This recurrence reads
  only in-neighbors, so any topological order works. Vertices not reachable from 1 simply keep count 0 (no special case needed,
  unlike longest path).

<details><summary>Solution</summary>

Kahn order over the whole graph, pushing counts forward. $O(n+m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    const int MOD = 1'000'000'007;
    int n, m;
    cin >> n >> m;
    vector<vector<int>> g(n + 1);
    vector<int> indeg(n + 1, 0);
    for (int i = 0; i < m; i++) {
        int a, b;
        cin >> a >> b;
        g[a].push_back(b);
        indeg[b]++;
    }
    vector<long long> cnt(n + 1, 0);
    cnt[1] = 1;
    vector<int> q;
    for (int v = 1; v <= n; v++) if (!indeg[v]) q.push_back(v);
    for (size_t h = 0; h < q.size(); h++) {
        int u = q[h];
        for (int v : g[u]) {
            cnt[v] = (cnt[v] + cnt[u]) % MOD;
            if (--indeg[v] == 0) q.push_back(v);
        }
    }
    cout << cnt[n] << "\n";
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
        int n = nextInt(), m = nextInt();
        int[] ea = new int[m], eb = new int[m], start = new int[n + 2], indeg = new int[n + 1];
        for (int i = 0; i < m; i++) { ea[i] = nextInt(); eb[i] = nextInt(); start[ea[i] + 1]++; indeg[eb[i]]++; }
        for (int i = 0; i <= n; i++) start[i + 1] += start[i];
        int[] adj = new int[m], pos = Arrays.copyOf(start, n + 1);
        for (int i = 0; i < m; i++) adj[pos[ea[i]]++] = eb[i];
        long[] cnt = new long[n + 1];
        cnt[1] = 1;
        int[] q = new int[n];
        int qh = 0, qt = 0;
        for (int v = 1; v <= n; v++) if (indeg[v] == 0) q[qt++] = v;
        while (qh < qt) {
            int u = q[qh++];
            for (int e = start[u]; e < start[u + 1]; e++) {
                int v = adj[e];
                cnt[v] = (cnt[v] + cnt[u]) % MOD;
                if (--indeg[v] == 0) q[qt++] = v;
            }
        }
        System.out.println(cnt[n]);
    }
}
```

</details>

<!-- test
in:
5 7
1 2
1 3
2 3
2 4
3 4
4 5
3 5
out:
5
-->
<!-- test
in:
3 1
2 3
out:
0
-->
<!-- test
in:
2 3
1 2
1 2
1 2
out:
3
-->

### Example 3 — Longest Flight Route  ·  ★ ≈1600

- **Source:** [CSES 1680 · Longest Flight Route](https://cses.fi/problemset/task/1680)
- **Difficulty:** ≈1600 (est.)
- **Problem:** $n \le 10^5$ cities, $m \le 2\cdot10^5$ one-way flights, no directed cycles. Find a route from city 1 to city
  $n$ visiting as many cities as possible; print the number of cities and the route, or `IMPOSSIBLE`. (Any longest route is
  accepted; the tests below have a unique one.)
- **Thinking from first principles:** longest path is NP-hard in general graphs but linear on a DAG: $dp[v] = 1 +
  \max_{u\to v} dp[u]$ over in-neighbors **reachable from 1**. The trap: vertices that are sources but not city 1 must not
  start routes, so initialize everything to $-\infty$ except $dp[1]=1$. Store the argmax predecessor to rebuild the route.

<details><summary>Solution</summary>

Kahn over the whole graph; relax `dp[v] = max(dp[v], dp[u] + 1)` only when `dp[u]` is finite. $O(n+m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<vector<int>> g(n + 1);
    vector<int> indeg(n + 1, 0);
    for (int i = 0; i < m; i++) {
        int a, b;
        cin >> a >> b;
        g[a].push_back(b);
        indeg[b]++;
    }
    const int NEG = INT_MIN;
    vector<int> dp(n + 1, NEG), par(n + 1, 0), q;
    dp[1] = 1;
    for (int v = 1; v <= n; v++) if (!indeg[v]) q.push_back(v);
    for (size_t h = 0; h < q.size(); h++) {
        int u = q[h];
        for (int v : g[u]) {
            if (dp[u] != NEG && dp[u] + 1 > dp[v]) { dp[v] = dp[u] + 1; par[v] = u; }
            if (--indeg[v] == 0) q.push_back(v);
        }
    }
    if (dp[n] == NEG) { cout << "IMPOSSIBLE\n"; return 0; }
    vector<int> route;
    for (int v = n; v != 0; v = par[v]) route.push_back(v);     // par[1] = 0
    reverse(route.begin(), route.end());
    cout << route.size() << "\n";
    for (size_t i = 0; i < route.size(); i++) cout << route[i] << " \n"[i + 1 == route.size()];
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
        int[] ea = new int[m], eb = new int[m], start = new int[n + 2], indeg = new int[n + 1];
        for (int i = 0; i < m; i++) { ea[i] = nextInt(); eb[i] = nextInt(); start[ea[i] + 1]++; indeg[eb[i]]++; }
        for (int i = 0; i <= n; i++) start[i + 1] += start[i];
        int[] adj = new int[m], pos = Arrays.copyOf(start, n + 1);
        for (int i = 0; i < m; i++) adj[pos[ea[i]]++] = eb[i];
        final int NEG = Integer.MIN_VALUE;
        int[] dp = new int[n + 1], par = new int[n + 1], q = new int[n];
        Arrays.fill(dp, NEG);
        dp[1] = 1;
        int qh = 0, qt = 0;
        for (int v = 1; v <= n; v++) if (indeg[v] == 0) q[qt++] = v;
        while (qh < qt) {
            int u = q[qh++];
            for (int e = start[u]; e < start[u + 1]; e++) {
                int v = adj[e];
                if (dp[u] != NEG && dp[u] + 1 > dp[v]) { dp[v] = dp[u] + 1; par[v] = u; }
                if (--indeg[v] == 0) q[qt++] = v;
            }
        }
        if (dp[n] == NEG) { System.out.println("IMPOSSIBLE"); return; }
        int len = dp[n];
        int[] route = new int[len];
        for (int v = n, i = len - 1; v != 0; v = par[v]) route[i--] = v;
        StringBuilder sb = new StringBuilder();
        sb.append(len).append('\n');
        for (int i = 0; i < len; i++) sb.append(route[i]).append(i + 1 == len ? '\n' : ' ');
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
6 7
1 2
2 3
1 3
3 6
1 4
4 6
5 2
out:
4
1 2 3 6
-->
<!-- test
in:
3 1
2 3
out:
IMPOSSIBLE
-->
<!-- test
in:
5 4
2 3
3 4
4 5
1 5
out:
2
1 5
-->

### Example 4 — Fox And Names (hidden alphabet)  ·  ★ 1600

- **Source:** [CF 510C · Fox And Names](https://codeforces.com/problemset/problem/510/C) — 1600
- **Difficulty:** 1600
- **Problem:** $n \le 100$ distinct names of lowercase letters (length $\le 100$) are given in a fixed order. Find a permutation
  of `a`–`z` (an alphabet order) under which the list is lexicographically sorted, or print `Impossible`. Any valid permutation
  is accepted; we print the lexicographically smallest one.
- **Thinking from first principles:** lexicographic order of two strings is decided by their first differing position, so only
  **adjacent** pairs matter (sortedness is transitive) and each gives at most one constraint: letter $x$ before letter $y$.
  Special case: if one name is a proper prefix of the next, fine; if the **longer comes first** with the shorter as its prefix,
  no alphabet helps → `Impossible`. Then 26 vertices, $\le 99$ edges, topological sort, cycle → `Impossible`. (Dead end: comparing
  all pairs is unnecessary and adds no information.)

<details><summary>Solution</summary>

Build edges from adjacent names; Kahn with a min-heap over 26 letters. $O(\sum|s| + 26\log 26)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    int n;
    cin >> n;
    vector<string> s(n);
    for (auto& x : s) cin >> x;
    vector<vector<int>> g(26);
    vector<int> indeg(26, 0);
    for (int i = 0; i + 1 < n; i++) {
        const string &a = s[i], &b = s[i + 1];
        size_t k = 0;
        while (k < a.size() && k < b.size() && a[k] == b[k]) k++;
        if (k == min(a.size(), b.size())) {
            if (a.size() > b.size()) { cout << "Impossible\n"; return 0; }   // longer name before its own prefix
            continue;
        }
        g[a[k] - 'a'].push_back(b[k] - 'a');
        indeg[b[k] - 'a']++;
    }
    priority_queue<int, vector<int>, greater<>> pq;
    for (int c = 0; c < 26; c++) if (!indeg[c]) pq.push(c);
    string res;
    while (!pq.empty()) {
        int c = pq.top(); pq.pop();
        res += char('a' + c);
        for (int d : g[c]) if (--indeg[d] == 0) pq.push(d);
    }
    cout << (res.size() == 26 ? res : string("Impossible")) << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StreamTokenizer st = new StreamTokenizer(br);
        st.nextToken();
        int n = (int) st.nval;
        String[] s = new String[n];
        for (int i = 0; i < n; i++) { st.nextToken(); s[i] = st.sval; }
        List<List<Integer>> g = new ArrayList<>();
        for (int c = 0; c < 26; c++) g.add(new ArrayList<>());
        int[] indeg = new int[26];
        for (int i = 0; i + 1 < n; i++) {
            String a = s[i], b = s[i + 1];
            int k = 0;
            while (k < a.length() && k < b.length() && a.charAt(k) == b.charAt(k)) k++;
            if (k == Math.min(a.length(), b.length())) {
                if (a.length() > b.length()) { System.out.println("Impossible"); return; }
                continue;
            }
            g.get(a.charAt(k) - 'a').add(b.charAt(k) - 'a');
            indeg[b.charAt(k) - 'a']++;
        }
        PriorityQueue<Integer> pq = new PriorityQueue<>();
        for (int c = 0; c < 26; c++) if (indeg[c] == 0) pq.add(c);
        StringBuilder res = new StringBuilder();
        while (!pq.isEmpty()) {
            int c = pq.poll();
            res.append((char) ('a' + c));
            for (int d : g.get(c)) if (--indeg[d] == 0) pq.add(d);
        }
        System.out.println(res.length() == 26 ? res.toString() : "Impossible");
    }
}
```

</details>

<!-- test
in:
3
zoo
zebra
abc
out:
bcdfghijklmnoepqrstuvwxyza
-->
<!-- test
in:
2
abcd
abc
out:
Impossible
-->
<!-- test
in:
3
ab
ba
ab
out:
Impossible
-->
<!-- test
in:
1
hello
out:
abcdefghijklmnopqrstuvwxyz
-->

### Example 5 — Substring (best letter on a path, or unbounded)  ·  ★ 1700

- **Source:** [CF 919D · Substring](https://codeforces.com/problemset/problem/919/D) — 1700
- **Difficulty:** 1700
- **Problem:** A directed graph with $n, m \le 3\cdot10^5$ (self-loops and repeated edges allowed); vertex $i$ carries a letter
  $s_i$. The value of a path is the largest number of times a single letter occurs on it. Print the maximum value over all
  paths, or $-1$ if it is unbounded.
- **Thinking from first principles:** any cycle can be traversed forever, repeating its letters → unbounded, so the answer is
  $-1$ iff there is a cycle (Kahn leftover). Otherwise the graph is a DAG and paths are finite; the objective "most frequent
  letter" is not additive, but it is a max over 26 additive objectives: for each letter $c$, the max number of $c$'s on a path.
  State $dp[v][c]$ = max count of letter $c$ on a path ending at $v$; push it along edges in topological order; add 1 for $v$'s
  own letter when $v$ is processed. $26(n+m) \approx 1.6\cdot10^7$ operations.

<details><summary>Solution</summary>

Kahn; when popping $u$, first count its own letter, update the answer, then push `dp[u][*]` into each successor with `max`.
Memory $26n$ ints ≈ 31 MB.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    string s;
    cin >> n >> m >> s;
    vector<vector<int>> g(n);
    vector<int> indeg(n, 0);
    for (int i = 0; i < m; i++) {
        int x, y;
        cin >> x >> y;
        g[x - 1].push_back(y - 1);
        indeg[y - 1]++;
    }
    vector<array<int, 26>> dp(n);
    for (auto& a : dp) a.fill(0);
    vector<int> q;
    for (int v = 0; v < n; v++) if (!indeg[v]) q.push_back(v);
    int best = 0;
    for (size_t h = 0; h < q.size(); h++) {
        int u = q[h];
        dp[u][s[u] - 'a']++;                                  // u's own letter, now dp[u] is final
        best = max(best, *max_element(dp[u].begin(), dp[u].end()));
        for (int v : g[u]) {
            for (int c = 0; c < 26; c++) dp[v][c] = max(dp[v][c], dp[u][c]);
            if (--indeg[v] == 0) q.push_back(v);
        }
    }
    if ((int)q.size() < n) cout << -1 << "\n";                // a cycle (self-loops included)
    else cout << best << "\n";
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
        String s = next();
        int[] ex = new int[m], ey = new int[m], start = new int[n + 1], indeg = new int[n];
        for (int i = 0; i < m; i++) { ex[i] = nextInt() - 1; ey[i] = nextInt() - 1; start[ex[i] + 1]++; indeg[ey[i]]++; }
        for (int i = 0; i < n; i++) start[i + 1] += start[i];
        int[] adj = new int[m], pos = Arrays.copyOf(start, n);
        for (int i = 0; i < m; i++) adj[pos[ex[i]]++] = ey[i];
        int[] dp = new int[26 * n];                                   // dp[v*26 + c], flat for cache locality
        int[] q = new int[n];
        int qh = 0, qt = 0, best = 0;
        for (int v = 0; v < n; v++) if (indeg[v] == 0) q[qt++] = v;
        while (qh < qt) {
            int u = q[qh++], bu = 26 * u;
            dp[bu + s.charAt(u) - 'a']++;
            for (int c = 0; c < 26; c++) best = Math.max(best, dp[bu + c]);
            for (int e = start[u]; e < start[u + 1]; e++) {
                int v = adj[e], bv = 26 * v;
                for (int c = 0; c < 26; c++) if (dp[bu + c] > dp[bv + c]) dp[bv + c] = dp[bu + c];
                if (--indeg[v] == 0) q[qt++] = v;
            }
        }
        System.out.println(qt < n ? -1 : best);
    }
}
```

</details>

<!-- test
in:
5 4
abaca
1 2
2 3
3 4
4 5
out:
3
-->
<!-- test
in:
3 3
xyz
1 2
2 3
3 1
out:
-1
-->
<!-- test
in:
2 1
ab
2 2
out:
-1
-->
<!-- test
in:
4 3
bbab
1 3
2 3
3 4
out:
2
-->

### Example 6 — Minimal Labels (lexicographic by position)  ·  ★ 2300

- **Source:** [CF 825E · Minimal Labels](https://codeforces.com/problemset/problem/825/E) — 2300
- **Difficulty:** 2300
- **Problem:** A DAG with $n, m \le 10^5$. Assign labels $1..n$ (a permutation) so that every edge $v\to u$ has
  $\text{label}_v < \text{label}_u$, and the sequence $(\text{label}_1, \dots, \text{label}_n)$ is lexicographically smallest.
  Print it.
- **Thinking from first principles:** labels are positions in a topological order, and we want vertex 1's position as small as
  possible, then vertex 2's, and so on. Kahn with a min-heap fails (the counterexample in §1: edge $3\to1$). Think about the
  **last** position instead: it must go to a vertex with no outgoing edges, and giving it to the **largest-index** such vertex
  is always safe — any smaller vertex placed last would receive label $n$, which is never better for the lexicographic order of
  labels than giving $n$ to a larger index. Repeat on the remaining graph: reversed Kahn with a **max-heap**, assigning labels
  $n, n-1, \dots, 1$.

<details><summary>Solution</summary>

Out-degree counts; max-heap of sinks; pop the largest, give it the current largest label, decrement out-degrees of its
in-neighbors. $O((n+m)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<vector<int>> rg(n + 1);                  // reversed edges
    vector<int> outdeg(n + 1, 0), label(n + 1, 0);
    for (int i = 0; i < m; i++) {
        int v, u;
        cin >> v >> u;
        rg[u].push_back(v);
        outdeg[v]++;
    }
    priority_queue<int> pq;                         // max-heap
    for (int v = 1; v <= n; v++) if (!outdeg[v]) pq.push(v);
    for (int cur = n; cur >= 1; cur--) {
        int v = pq.top(); pq.pop();
        label[v] = cur;
        for (int u : rg[v]) if (--outdeg[u] == 0) pq.push(u);
    }
    for (int v = 1; v <= n; v++) cout << label[v] << " \n"[v == n];
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
        int[] ev = new int[m], eu = new int[m], start = new int[n + 2], outdeg = new int[n + 1];
        for (int i = 0; i < m; i++) { ev[i] = nextInt(); eu[i] = nextInt(); start[eu[i] + 1]++; outdeg[ev[i]]++; }
        for (int i = 0; i <= n; i++) start[i + 1] += start[i];
        int[] radj = new int[m], pos = Arrays.copyOf(start, n + 1);
        for (int i = 0; i < m; i++) radj[pos[eu[i]]++] = ev[i];
        PriorityQueue<Integer> pq = new PriorityQueue<>(Collections.reverseOrder());
        for (int v = 1; v <= n; v++) if (outdeg[v] == 0) pq.add(v);
        int[] label = new int[n + 1];
        for (int cur = n; cur >= 1; cur--) {
            int v = pq.poll();
            label[v] = cur;
            for (int e = start[v]; e < start[v + 1]; e++) if (--outdeg[radj[e]] == 0) pq.add(radj[e]);
        }
        StringBuilder sb = new StringBuilder();
        for (int v = 1; v <= n; v++) sb.append(label[v]).append(v == n ? '\n' : ' ');
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
3 1
3 1
out:
2 3 1
-->
<!-- test
in:
5 4
5 1
4 1
2 3
5 3
out:
3 4 5 1 2
-->
<!-- test
in:
1 0
out:
1
-->

## 6. Tricks, pitfalls and things to remember

1. **Check the output size of Kahn.** Fewer than $n$ vertices ⇒ cycle. Forgetting the check prints a partial order as if valid.
2. **Count every parallel edge in the in-degree** — and decrement once per edge. Deduplicating edges for in-degrees but not for
   adjacency (or vice versa) deadlocks Kahn.
3. **Self-loops are cycles.** Kahn handles them automatically (the vertex's in-degree never reaches 0); a DFS that skips $v = u$
   misses them.
4. **Unreachable sources in longest-path DP**: initialize to $-\infty$, not 0, or paths may start anywhere (Example 3).
5. **Path counts are modulo $p$, but "is it reachable" is not "count ≠ 0 mod p"** — keep a separate boolean if both matter.
6. **Lexicographically smallest order ≠ smallest labels.** Know both greedy directions (Examples 1 and 6) and the 3-vertex
   counterexample.
7. **Prefix trap in alphabet problems** (Example 4): a longer word before its own prefix is impossible regardless of the
   alphabet; equal prefixes give no edge.
8. **Recursion depth.** DFS-based topological sort on a path of $10^5$ vertices overflows Java's stack; use Kahn or the
   iterative DFS.
9. **Java heaps:** `PriorityQueue<Integer>` boxes; for $10^5$–$10^6$ operations it's fine, for more write an `int[]` heap
   (Example 1).
10. **Memory for per-vertex DP vectors:** `vector<array<int,26>>` is contiguous; `vector<vector<int>>(n, vector<int>(26))` is
    $n$ heap allocations — slower and fatter.
11. **"Unbounded" answers** usually mean "a cycle that is reachable from the start and can reach the end"; for an unrestricted
    path (any start, any end, as in Example 5), any cycle at all.
12. **The order must cover isolated vertices too** — they are sources with no edges; never start Kahn only from vertex 1.

## 7. Going further (toward 2400–2600+)

- **Topological order + data structures:** process vertices in topological order while maintaining a segment tree or DSU
  over some other key; e.g. "for each vertex, the number of reachable vertices" in general needs bitsets (CSES Reachable
  Nodes), and offline reachability queries can be batched by chunks of 64 targets per pass to cap memory.
- **Constrained topological orders:** given a time window $[l_v, r_v]$ per vertex (AtCoder ABC304 Ex), tighten windows along
  edges in topological and reverse topological order, then schedule greedily by deadline with a heap.
- **Acyclic orientations:** "orient the undirected edges so that the result is acyclic" — orient along any topological order of
  the directed part (CF 1385E Directing Edges); "orient so that no long path exists" is bipartite coloring (CF 1144F, see
  [bipartite graphs](09-bipartite-graphs-and-cycles.md)).
- **Reverse thinking:** many "lexicographically smallest under precedence" variants become easy when you build from the end
  (Example 6). Try both directions when a greedy fails.
- **DAG DP with optimization:** longest path with weights depending on positions leads to monotone-queue or CHT
  optimizations ([DP optimizations](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md)).
- **General graphs:** contract SCCs, then everything in this file applies to the condensation
  ([SCC and condensation](05-scc-and-condensation.md)); games on graphs with draws use a Kahn-like retrograde analysis
  ([game theory](../13-Game-Theory/04-minimax-and-game-dp.md)).

## 8. Practice ladder

**≤ 1600**
- [ ] [CSES 1679 · Course Schedule](https://cses.fi/problemset/task/1679) — Kahn
- [ ] [CSES 1681 · Game Routes](https://cses.fi/problemset/task/1681) — counting paths
- [ ] [CSES 1680 · Longest Flight Route](https://cses.fi/problemset/task/1680) — longest path, restore it
- [ ] [AtCoder ABC223 D · Restricted Permutation](https://atcoder.jp/contests/abc223/tasks/abc223_d) — lexicographically smallest order
- [ ] [AtCoder ABC291 E · Find Permutation](https://atcoder.jp/contests/abc291/tasks/abc291_e) — uniqueness of the order
- [ ] [AtCoder ABC216 D · Pair of Balls](https://atcoder.jp/contests/abc216/tasks/abc216_d) — dependency graph, Kahn
- [ ] [CF 510C · Fox And Names](https://codeforces.com/problemset/problem/510/C) — 1600

**1600–2100**
- [ ] [CF 919D · Substring](https://codeforces.com/problemset/problem/919/D) — 1700
- [ ] [CSES 1757 · Course Schedule II](https://cses.fi/problemset/task/1757) — smallest labels (reverse greedy)
- [ ] [CSES 1756 · Acyclic Graph Edges](https://cses.fi/problemset/task/1756) — orient edges acyclically
- [ ] [AtCoder ABC245 F · Endless Walk](https://atcoder.jp/contests/abc245/tasks/abc245_f) — vertices that can walk forever (reverse Kahn)
- [ ] [CF 1679D · Toss a Coin to Your Graph...](https://codeforces.com/problemset/problem/1679/D) — 1900
- [ ] [CF 1385E · Directing Edges](https://codeforces.com/problemset/problem/1385/E) — 2000
- [ ] [CF 1131D · Gourmet choice](https://codeforces.com/problemset/problem/1131/D) — 2000
- [ ] [CSES 2138 · Reachable Nodes](https://cses.fi/problemset/task/2138) — bitsets
- [ ] [CSES 2143 · Reachability Queries](https://cses.fi/problemset/task/2143) — condensation + bitsets

**2100+**
- [ ] [CF 825E · Minimal Labels](https://codeforces.com/problemset/problem/825/E) — 2300
- [ ] [AtCoder ABC304 H · Constrained Topological Sort](https://atcoder.jp/contests/abc304/tasks/abc304_h) — windows + deadline greedy

## 9. LeetCode / FAANG cross-reference

Topological sort is a top-10 interview graph topic (course schedules, build orders, alien dictionary).

- [LC 207 · Course Schedule](https://leetcode.com/problems/course-schedule/) — Medium — Kahn's count or three-color DFS.
- [LC 210 · Course Schedule II](https://leetcode.com/problems/course-schedule-ii/) — Medium — Example 1 without the heap.
- [LC 1462 · Course Schedule IV](https://leetcode.com/problems/course-schedule-iv/) — Medium — reachability (closure) queries.
- [LC 269 · Alien Dictionary](https://leetcode.com/problems/alien-dictionary/) — Hard 🔒 — Example 4 (watch the prefix trap).
- [LC 802 · Find Eventual Safe States](https://leetcode.com/problems/find-eventual-safe-states/) — Medium — reverse Kahn from sinks.
- [LC 1203 · Sort Items by Groups Respecting Dependencies](https://leetcode.com/problems/sort-items-by-groups-respecting-dependencies/) — Hard — two-level topological sort.
- [LC 2050 · Parallel Courses III](https://leetcode.com/problems/parallel-courses-iii/) — Hard — critical path (longest weighted path).
- [LC 1136 · Parallel Courses](https://leetcode.com/problems/parallel-courses/) — Medium 🔒 — Kahn by layers.
- [LC 1494 · Parallel Courses II](https://leetcode.com/problems/parallel-courses-ii/) — Hard — at most $k$ per round: bitmask DP, not greedy.
- [LC 1857 · Largest Color Value in a Directed Graph](https://leetcode.com/problems/largest-color-value-in-a-directed-graph/) — Hard — Example 5 exactly.
- [LC 329 · Longest Increasing Path in a Matrix](https://leetcode.com/problems/longest-increasing-path-in-a-matrix/) — Hard — implicit DAG, memoized DFS.
- [LC 2392 · Build a Matrix With Conditions](https://leetcode.com/problems/build-a-matrix-with-conditions/) — Hard — two independent topological sorts.
- [LC 310 · Minimum Height Trees](https://leetcode.com/problems/minimum-height-trees/) — Medium — "peel leaves" Kahn on a tree.

## 10. Self-check

1. Prove that every DAG has a vertex of in-degree 0, and turn the proof into Kahn's algorithm.
2. Why does Kahn detect cycles, and which vertices remain unprocessed?
3. Why does decreasing finish time give a topological order? What happens at a back edge?
4. Give a graph where the lexicographically smallest topological order is not the one minimizing vertex 1's position.
5. How do you count paths from $s$ to $t$ in a DAG, and why must vertices unreachable from $s$ be handled differently in the
   longest-path DP?
6. In CF 919D, why is the answer $-1$ exactly when the graph has a cycle?
7. When is the topological order unique?
8. How would you compute, for every vertex of a DAG with $n = m = 5\cdot10^4$, the number of vertices it can reach?

<details><summary>Answers</summary>

1. If every vertex had an incoming edge, follow incoming edges backwards forever; after $n$ steps a vertex repeats → a cycle.
   So a source exists; output it, delete it, repeat — with in-degree counters and a queue of sources this is Kahn.
2. A vertex is output only when all its in-edges are deleted. If a cycle exists, its vertices never reach in-degree 0. The
   leftover vertices are those on cycles or reachable from cycles.
3. For an edge $u\to v$ in a DAG, $v$ finishes before $u$ (white → descendant; black → already finished). A gray $v$ means a
   back edge, i.e. a cycle, so no order exists.
4. $n=3$, edge $3\to1$: smallest order $(2,3,1)$ puts 1 last; $(3,1,2)$ puts 1 second.
5. $cnt[s]=1$, $cnt[v]=\sum_{u\to v}cnt[u]$ in topological order; unreachable vertices stay 0 automatically. For longest path,
   a 0 initial value would let paths start at those vertices, so they must start at $-\infty$.
6. A cycle can be walked any number of times, repeating its letters, so the value is unbounded. Without cycles, paths have at
   most $n$ vertices, so the value is finite.
7. Iff at every step Kahn has exactly one source, iff consecutive vertices in the order are joined by an edge (Hamiltonian
   path in the DAG).
8. Bitsets in reverse topological order: $\text{reach}[u] = \{u\} \cup \bigcup \text{reach}[v]$; $n(n+m)/64 \approx 2\cdot10^8$
   word operations, memory $n^2/8$ bytes (≈312 MB — process targets in chunks to cut memory).

</details>
