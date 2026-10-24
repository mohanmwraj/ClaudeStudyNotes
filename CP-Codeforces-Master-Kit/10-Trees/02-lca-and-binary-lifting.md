# LCA and binary lifting

> **Band:** 🔵 1600 – 🟣 2100 · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [tree basics and Euler tour](01-tree-basics-diameter-center-euler-tour.md), [sparse table](../08-Data-Structures/05-sparse-table-and-rmq.md), [DSU](../08-Data-Structures/06-dsu-and-variants.md) (for Tarjan), [bit manipulation](../01-Foundations/03-bit-manipulation.md)
> **You can say you know this when:** you can write binary-lifting LCA with $k$-th ancestor and a path aggregate (max edge) from memory, explain why the greedy "jump while the ancestors differ" is a binary search, and pick between $O(\log n)$ lifting and $O(1)$ Euler-tour RMQ based on the constraints.

## 1. First principles — why this works

### 1.1 The problem and the naive answer

The **lowest common ancestor** $\mathrm{lca}(u,v)$ in a rooted tree is the deepest vertex that is an ancestor of both (a vertex is its own ancestor). It is where the paths from $u$ and $v$ to the root merge, so the $u$–$v$ path is $u \to \mathrm{lca} \to v$. That single fact is why LCA is everywhere: distances, path sums, "is $x$ on the path", the $k$-th vertex of a path, and the path decompositions of later files all reduce to it.

The naive algorithm: lift the deeper vertex until both have equal depth, then lift both one step at a time until they meet. Correct — at equal depth, the ancestors of $u$ and $v$ at the same height coincide from the LCA upward and differ below it — but it costs $O(\text{depth})$, i.e. $O(n)$ per query on a path-shaped tree. With $n = q = 2\cdot10^5$ that is $4\cdot10^{10}$ steps.

### 1.2 Binary lifting: precompute jumps of length $2^j$

The waste is walking one edge at a time. Any distance $k$ is a sum of distinct powers of two, so if every vertex knows its $2^j$-th ancestor for all $j \le \log_2 n$, the $k$-th ancestor takes $\lfloor\log_2 k\rfloor + 1$ jumps. The table is filled by **doubling**:

$$up_0(v) = \mathrm{parent}(v), \qquad up_j(v) = up_{j-1}\big(up_{j-1}(v)\big),$$

with the root's parent set to the root itself (jumps saturate at the root instead of falling off). Building level $j$ only needs level $j-1$ complete, so fill level by level: $O(n\log n)$ time and memory.

**LCA as a binary search.** After equalising depths ($u$ lifted by $\mathrm{dep}(u) - \mathrm{dep}(v)$), if $u = v$ we are done. Otherwise consider $f(t) = [\,t\text{-th ancestor of } u = t\text{-th ancestor of } v\,]$. It is **monotone**: false for $t < \mathrm{dep}(u) - \mathrm{dep}(\mathrm{lca})$ and true from there on (once the two climbs meet they stay together). We want the largest $t$ with $f(t)$ false; then the answer is one step above. Binary search over $t$ written in binary: for $j$ from high to low, if $up_j(u) \ne up_j(v)$, jump both. Each accepted jump keeps the invariant "$u \ne v$, same depth, LCA strictly above"; each rejected jump means $2^j$ more steps would overshoot. After all bits, $u$ and $v$ are the two children of the LCA on the paths, and $\mathrm{lca} = up_0(u)$.

**Variant without depths.** With $tin/tout$ (file 01) you can test ancestry in $O(1)$: if $u$ is an ancestor of $v$, return $u$; otherwise lift $u$ by $2^j$ whenever $up_j(u)$ is *not* an ancestor of $v$, and finish with $up_0(u)$. Same binary search, different predicate.

### 1.3 Path aggregates on the same jumps

Store, next to $up_j(v)$, the aggregate $agg_j(v)$ of the $2^j$ edges (or vertices) covered by that jump:

$$agg_j(v) = agg_{j-1}(v) \oplus agg_{j-1}\big(up_{j-1}(v)\big).$$

Every LCA query decomposes $u \to \mathrm{lca}$ and $v \to \mathrm{lca}$ into $O(\log n)$ jumps, so any **associative** $\oplus$ works — max, min, gcd, sum, even non-invertible or non-commutative ones (for a non-commutative operation keep the two sides separate and reverse one). This is how "minimum spanning tree containing edge $e$" (Example 4) is answered. Prefix sums from the root (file 01) only work for invertible operations; lifting works for all of them.

### 1.4 Euler tour + RMQ: $O(1)$ per query

Write down the vertex every time an (imagined recursive) DFS *enters or returns to* it. The sequence $E$ has length $2n - 1$. Let $first(v)$ be the first position of $v$. Between $first(u)$ and $first(v)$ the walk goes from $u$ to $v$: it must climb to $\mathrm{lca}(u,v)$ to leave the child subtree containing $u$, and it never climbs above $\mathrm{lca}$, because it has not yet finished the LCA's subtree (it still has to reach $v$ inside it). So

$$\mathrm{lca}(u,v) = \text{the vertex of minimum depth in } E[first(u) .. first(v)],$$

a range-minimum query. A [sparse table](../08-Data-Structures/05-sparse-table-and-rmq.md) answers it in $O(1)$ after $O(n\log n)$ preprocessing.

**The $n$-length version (used in §3.2).** You do not need the $2n-1$ sequence. Take the **preorder** and $u \ne v$ with $tin(u) < tin(v)$. Every vertex $x$ at preorder positions $(tin(u), tin(v)]$ lies in the LCA's subtree and is not the LCA itself, so $tin(\mathrm{parent}(x)) \ge tin(\mathrm{lca})$; and the child of the LCA on the way to $v$ lies in that range and achieves equality (if $u$ is an ancestor of $v$, that child is the next vertex on the path; otherwise it is the root of $v$'s branch, whose preorder position comes after all of $u$'s branch). Hence

$$\mathrm{lca}(u,v) = \mathrm{order}\Big[\min_{tin(u) < i \le tin(v)} tin(\mathrm{parent}(\mathrm{order}[i]))\Big],$$

a plain integer range-min — half the memory of the classic version and no iterative-DFS headaches.

### 1.5 Offline: Tarjan's LCA (🧊)

If all queries are known in advance: DFS; when a vertex $v$ finishes, answer each query $(v, w)$ with $w$ already finished as $\mathrm{anc}(\mathrm{find}(w))$, then union $v$ into its parent's DSU set and set the set's anchor to the parent. At any moment, the set of a finished vertex $w$ is anchored at the deepest *still-open* ancestor of $w$, which is exactly the LCA with the vertex currently finishing. $O((n+q)\,\alpha(n))$. Rarely needed in contests (lifting or RMQ are simpler), but the "anchor = deepest open ancestor" idea reappears in offline tree algorithms.

### 1.6 What you get from LCA

- **Distance:** $d(u,v) = D(u) + D(v) - 2D(\mathrm{lca})$ with $D$ = (weighted) depth.
- **On-path test:** $x$ lies on the $u$–$v$ path iff $d(u,x) + d(x,v) = d(u,v)$ (positive weights), or with ancestry tests: $\ell = \mathrm{lca}(u,v)$ is an ancestor of $x$, and $x$ is an ancestor of $u$ or of $v$.
- **$k$-th vertex on the path $u \to v$:** if $k \le \mathrm{dep}(u) - \mathrm{dep}(\ell)$ it is the $k$-th ancestor of $u$; otherwise the $(d(u,v) - k)$-th ancestor of $v$.
- **LCA of a set:** $\mathrm{lca}(S) = \mathrm{lca}(\arg\min_{S} tin, \arg\max_{S} tin)$ — the two extreme vertices in preorder already "span" the set.
- **Counting over paths with a difference array on the tree:** to add $x$ to every vertex of the path $u$–$v$, do $c[u] \mathrel{+}= x$, $c[v] \mathrel{+}= x$, $c[\ell] \mathrel{-}= x$, $c[\mathrm{parent}(\ell)] \mathrel{-}= x$, then take subtree sums. For edges (stored at the child): $c[u] \mathrel{+}= x$, $c[v] \mathrel{+}= x$, $c[\ell] \mathrel{-}= 2x$.

## 2. Formulas, definitions and identities

| Formula | Meaning / why |
|---|---|
| $up_0(v) = p(v)$, $up_j(v) = up_{j-1}(up_{j-1}(v))$, $up_j(\text{root}) = \text{root}$ | doubling; saturating at the root keeps jumps defined |
| levels $L = \lfloor\log_2 n\rfloor + 1$, so $2^L > n - 1 \ge$ any depth | memory $nL$ integers ($\approx 3.6\cdot10^6$ for $n = 2\cdot10^5$) |
| $k$-th ancestor $= \prod_{j : \text{bit } j \text{ of } k} up_j$ (applied in any order) | jumps commute: all are along one root path |
| $\mathrm{lca}$: equalise depth, then for $j = L-1..0$: if $up_j(u) \ne up_j(v)$ jump both; return $up_0(u)$ | binary search on the monotone predicate of §1.2 |
| $agg_j(v) = agg_{j-1}(v) \oplus agg_{j-1}(up_{j-1}(v))$ | path aggregate for any associative $\oplus$ |
| $d(u,v) = D(u) + D(v) - 2D(\ell)$ | root paths overlap exactly above $\ell$ |
| $\lvert E \rvert = 2n - 1$; $\ell = \arg\min_{\mathrm{dep}} E[first(u)..first(v)]$ | Euler tour + RMQ |
| $\ell = \mathrm{order}[\min_{(tin(u), tin(v)]} tin(p(\cdot))]$ | preorder + RMQ (§1.4) |
| sparse table: $st_j[i] = \min(st_{j-1}[i], st_{j-1}[i + 2^{j-1}])$, query $\min(st_k[l], st_k[r - 2^k + 1])$, $k = \lfloor \log_2(r-l+1) \rfloor$ | overlapping halves; needs idempotent $\oplus$ |
| $x \in \mathrm{path}(u,v) \iff \ell \preceq x \wedge (x \preceq u \vee x \preceq v)$ | $\preceq$ = "is an ancestor of" |
| $\mathrm{lca}(S) = \mathrm{lca}(\arg\min tin, \arg\max tin)$ | extreme preorder vertices span $S$ |
| path add: $c_u \mathrel{+}= x, c_v \mathrel{+}= x, c_\ell \mathrel{-}= x, c_{p(\ell)} \mathrel{-}= x$; edges: $c_\ell \mathrel{-}= 2x$ | then subtree sums ("difference array on a tree") |

| Method | Build | Query | Memory | Notes |
|---|---|---|---|---|
| naive climbing | $O(n)$ | $O(\text{depth})$ | $O(n)$ | fine for random trees, dies on paths |
| binary lifting | $O(n\log n)$ | $O(\log n)$ | $O(n\log n)$ | also $k$-th ancestor and path aggregates |
| Euler / preorder + sparse table | $O(n\log n)$ | $O(1)$ | $O(n\log n)$ | fastest for $10^6$ queries |
| Tarjan offline | $O(n + q\,\alpha)$ | — | $O(n+q)$ | offline only |
| [HLD](04-heavy-light-decomposition.md) | $O(n)$ | $O(\log n)$ | $O(n)$ | light memory, small constant |

## 3. Implementation (C++ and Java)

### 3.1 Binary lifting: LCA, $k$-th ancestor, distance

Input: `n q`, $n-1$ edges, then $q$ queries `t a b`: `1 a b` → $\mathrm{lca}(a,b)$; `2 a k` → the $k$-th ancestor of $a$ or $-1$; `3 a b` → $d(a,b)$. Root is 1.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct Lifting {
    int n, LOG;
    vector<vector<int>> up;                       // up[j][v] = 2^j-th ancestor, root -> root
    vector<int> dep;
    Lifting(const vector<vector<int>>& adj, int root) : n(adj.size() - 1) {
        LOG = 1; while ((1 << LOG) <= n) LOG++;
        up.assign(LOG, vector<int>(n + 1, root)); dep.assign(n + 1, 0);
        vector<int> order = {root}; vector<char> seen(n + 1, 0); seen[root] = 1;
        for (size_t i = 0; i < order.size(); i++) {           // BFS: parents before children
            int v = order[i];
            for (int u : adj[v]) if (!seen[u]) { seen[u] = 1; up[0][u] = v; dep[u] = dep[v] + 1; order.push_back(u); }
        }
        for (int j = 1; j < LOG; j++)
            for (int v = 1; v <= n; v++) up[j][v] = up[j - 1][up[j - 1][v]];
    }
    int kth(int v, int k) const {
        if (k > dep[v]) return -1;
        for (int j = 0; k; j++, k >>= 1) if (k & 1) v = up[j][v];
        return v;
    }
    int lca(int a, int b) const {
        if (dep[a] < dep[b]) swap(a, b);
        a = kth(a, dep[a] - dep[b]);
        if (a == b) return a;
        for (int j = LOG - 1; j >= 0; j--)
            if (up[j][a] != up[j][b]) { a = up[j][a]; b = up[j][b]; }   // still below the LCA
        return up[0][a];
    }
    int dist(int a, int b) const { return dep[a] + dep[b] - 2 * dep[lca(a, b)]; }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; adj[a].push_back(b); adj[b].push_back(a); }
    Lifting L(adj, 1);
    while (q--) {
        int t, a, b; cin >> t >> a >> b;
        if (t == 1) cout << L.lca(a, b) << '\n';
        else if (t == 2) cout << L.kth(a, b) << '\n';
        else cout << L.dist(a, b) << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int LOG;
    static int[][] up;
    static int[] dep;

    static void build(int n, int[] start, int[] adj, int root) {
        LOG = 1; while ((1 << LOG) <= n) LOG++;
        up = new int[LOG][n + 1]; dep = new int[n + 1];
        Arrays.fill(up[0], root);
        int[] order = new int[n];
        boolean[] seen = new boolean[n + 1];
        int head = 0, tail = 0;
        order[tail++] = root; seen[root] = true;
        while (head < tail) {
            int v = order[head++];
            for (int j = start[v]; j < start[v + 1]; j++) {
                int u = adj[j];
                if (!seen[u]) { seen[u] = true; up[0][u] = v; dep[u] = dep[v] + 1; order[tail++] = u; }
            }
        }
        for (int j = 1; j < LOG; j++) {
            int[] prev = up[j - 1], cur = up[j];
            for (int v = 0; v <= n; v++) cur[v] = prev[prev[v]];
        }
    }

    static int kth(int v, int k) {
        if (k > dep[v]) return -1;
        for (int j = 0; k > 0; j++, k >>= 1) if ((k & 1) != 0) v = up[j][v];
        return v;
    }

    static int lca(int a, int b) {
        if (dep[a] < dep[b]) { int t = a; a = b; b = t; }
        a = kth(a, dep[a] - dep[b]);
        if (a == b) return a;
        for (int j = LOG - 1; j >= 0; j--)
            if (up[j][a] != up[j][b]) { a = up[j][a]; b = up[j][b]; }
        return up[0][a];
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), q = in.nextInt();
        int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        build(n, start, adj, 1);
        StringBuilder sb = new StringBuilder();
        for (int k = 0; k < q; k++) {
            int t = in.nextInt(), a = in.nextInt(), b = in.nextInt();
            int r = t == 1 ? lca(a, b) : t == 2 ? kth(a, b) : dep[a] + dep[b] - 2 * dep[lca(a, b)];
            sb.append(r).append('\n');
        }
        out.print(sb);
        out.flush();
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

Test tree 1: $1$–$2$, $1$–$3$, $2$–$4$, $2$–$5$, $3$–$6$, $5$–$7$.

<!-- test
in:
7 10
1 2
1 3
2 4
2 5
3 6
5 7
1 4 7
1 7 6
1 5 7
2 7 2
2 7 3
2 7 4
2 1 0
3 4 6
3 7 7
3 7 6
out:
2
1
5
2
1
-1
1
4
0
5
-->
<!-- test
in:
1 3
1 1 1
2 1 1
3 1 1
out:
1
-1
0
-->
<!-- test
in:
6 4
3 4
1 2
5 6
2 3
4 5
1 6 3
2 6 5
3 1 6
2 6 6
out:
3
1
5
-1
-->

### 3.2 $O(1)$ LCA: preorder + sparse table

Input: `n q`, edges, then $q$ pairs `u v`. Output per pair: $\mathrm{lca}(u,v)$ and $d(u,v)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct FastLCA {
    vector<int> tin, order, dep;
    vector<vector<int>> sp;                       // sp[j][i] = min tin(parent) over [i, i + 2^j)
    FastLCA(const vector<vector<int>>& adj, int root) {
        int n = adj.size() - 1;
        tin.assign(n + 1, 0); dep.assign(n + 1, 0);
        vector<int> par(n + 1, 0), st = {root};
        while (!st.empty()) {
            int v = st.back(); st.pop_back();
            tin[v] = order.size(); order.push_back(v);
            for (int u : adj[v]) if (u != par[v]) { par[u] = v; dep[u] = dep[v] + 1; st.push_back(u); }
        }
        int LOG = 1; while ((1 << LOG) <= n) LOG++;
        sp.assign(LOG, vector<int>(n, 0));
        for (int i = 1; i < n; i++) sp[0][i] = tin[par[order[i]]];
        for (int j = 1; j < LOG; j++)
            for (int i = 0; i + (1 << j) <= n; i++) sp[j][i] = min(sp[j - 1][i], sp[j - 1][i + (1 << (j - 1))]);
    }
    int lca(int u, int v) const {
        if (u == v) return u;
        int a = tin[u], b = tin[v];
        if (a > b) swap(a, b);
        a++;                                       // positions (tin[u], tin[v]]
        int j = __lg(b - a + 1);
        return order[min(sp[j][a], sp[j][b - (1 << j) + 1])];
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; adj[a].push_back(b); adj[b].push_back(a); }
    FastLCA F(adj, 1);
    while (q--) {
        int u, v; cin >> u >> v;
        int l = F.lca(u, v);
        cout << l << ' ' << F.dep[u] + F.dep[v] - 2 * F.dep[l] << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] tin, order, dep;
    static int[][] sp;

    static void build(int n, int[] start, int[] adj, int root) {
        tin = new int[n + 1]; dep = new int[n + 1]; order = new int[n];
        int[] par = new int[n + 1], st = new int[n];
        int top = 0, cnt = 0;
        st[top++] = root;
        while (top > 0) {
            int v = st[--top];
            tin[v] = cnt; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) {
                int u = adj[j];
                if (u != par[v]) { par[u] = v; dep[u] = dep[v] + 1; st[top++] = u; }
            }
        }
        int LOG = 1; while ((1 << LOG) <= n) LOG++;
        sp = new int[LOG][n];
        for (int i = 1; i < n; i++) sp[0][i] = tin[par[order[i]]];
        for (int j = 1; j < LOG; j++)
            for (int i = 0; i + (1 << j) <= n; i++) sp[j][i] = Math.min(sp[j - 1][i], sp[j - 1][i + (1 << (j - 1))]);
    }

    static int lca(int u, int v) {
        if (u == v) return u;
        int a = tin[u], b = tin[v];
        if (a > b) { int t = a; a = b; b = t; }
        a++;
        int j = 31 - Integer.numberOfLeadingZeros(b - a + 1);
        return order[Math.min(sp[j][a], sp[j][b - (1 << j) + 1])];
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), q = in.nextInt();
        int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        build(n, start, adj, 1);
        StringBuilder sb = new StringBuilder();
        for (int k = 0; k < q; k++) {
            int u = in.nextInt(), v = in.nextInt(), l = lca(u, v);
            sb.append(l).append(' ').append(dep[u] + dep[v] - 2 * dep[l]).append('\n');
        }
        out.print(sb);
        out.flush();
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

<!-- test
in:
7 6
1 2
1 3
2 4
2 5
3 6
5 7
4 7
7 6
5 7
6 6
1 7
3 6
out:
2 3
1 5
5 1
6 0
1 3
3 1
-->
<!-- test
in:
1 1
1 1
out:
1 0
-->
<!-- test
in:
5 3
3 1
3 2
3 4
3 5
2 4
1 5
5 3
out:
3 2
1 2
3 1
-->

### 3.3 Tarjan's offline LCA, iterative (🧊)

Input: `n q`, edges, $q$ pairs; output each LCA. The DFS keeps an explicit stack with a per-vertex edge pointer so that "a child just finished" is observable.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; adj[a].push_back(b); adj[b].push_back(a); }
    vector<vector<pair<int,int>>> qs(n + 1);
    for (int i = 0; i < q; i++) { int u, v; cin >> u >> v; qs[u].push_back({v, i}); qs[v].push_back({u, i}); }
    vector<int> dsu(n + 1), anc(n + 1), par(n + 1, 0), it(n + 1, 0), ans(q);
    iota(dsu.begin(), dsu.end(), 0);
    auto find = [&](int x) {
        int r = x; while (dsu[r] != r) r = dsu[r];
        while (dsu[x] != r) { int nx = dsu[x]; dsu[x] = r; x = nx; }   // path compression
        return r;
    };
    vector<char> done(n + 1, 0);
    vector<int> st = {1}; anc[1] = 1;
    while (!st.empty()) {
        int v = st.back();
        if (it[v] < (int)adj[v].size()) {
            int u = adj[v][it[v]++];
            if (u != par[v]) { par[u] = v; anc[u] = u; st.push_back(u); }
            continue;
        }
        st.pop_back();
        done[v] = 1;
        for (auto [w, id] : qs[v]) if (done[w]) ans[id] = anc[find(w)];
        if (par[v]) { dsu[find(v)] = find(par[v]); anc[find(par[v])] = par[v]; }   // merge v's set into its parent
    }
    for (int i = 0; i < q; i++) cout << ans[i] << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] dsu;
    static int find(int x) {
        int r = x; while (dsu[r] != r) r = dsu[r];
        while (dsu[x] != r) { int nx = dsu[x]; dsu[x] = r; x = nx; }
        return r;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), q = in.nextInt();
        int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        int[] qa = new int[q], qb = new int[q], qs = new int[n + 2];
        for (int i = 0; i < q; i++) { qa[i] = in.nextInt(); qb[i] = in.nextInt(); qs[qa[i] + 1]++; qs[qb[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) qs[v] += qs[v - 1];
        int[] qOther = new int[2 * q], qId = new int[2 * q], qf = qs.clone();
        for (int i = 0; i < q; i++) {
            qOther[qf[qa[i]]] = qb[i]; qId[qf[qa[i]]++] = i;
            qOther[qf[qb[i]]] = qa[i]; qId[qf[qb[i]]++] = i;
        }
        dsu = new int[n + 1];
        for (int v = 0; v <= n; v++) dsu[v] = v;
        int[] anc = new int[n + 1], par = new int[n + 1], it = new int[n + 1], ans = new int[q], st = new int[n];
        for (int v = 1; v <= n; v++) it[v] = start[v];
        boolean[] done = new boolean[n + 1];
        int top = 0;
        st[top++] = 1; anc[1] = 1;
        while (top > 0) {
            int v = st[top - 1];
            if (it[v] < start[v + 1]) {
                int u = adj[it[v]++];
                if (u != par[v]) { par[u] = v; anc[u] = u; st[top++] = u; }
                continue;
            }
            top--;
            done[v] = true;
            for (int j = qs[v]; j < qs[v + 1]; j++) if (done[qOther[j]]) ans[qId[j]] = anc[find(qOther[j])];
            if (par[v] != 0) { dsu[find(v)] = find(par[v]); anc[find(par[v])] = par[v]; }
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < q; i++) sb.append(ans[i]).append('\n');
        out.print(sb);
        out.flush();
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

The union direction is not by size: the set's anchor must become the parent, and we write it explicitly after the union, so any union rule is correct; path compression alone already gives near-constant amortised time in practice.

<!-- test
in:
7 6
1 2
1 3
2 4
2 5
3 6
5 7
4 7
7 6
5 7
6 6
1 7
3 6
out:
2
1
5
6
1
3
-->
<!-- test
in:
5 3
3 1
3 2
3 4
3 5
2 4
1 5
5 3
out:
3
1
3
-->

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "distance between $u$ and $v$" for many pairs | $D(u) + D(v) - 2D(\mathrm{lca})$ |
| "$k$-th ancestor", "go up $k$ levels", "the boss $k$ levels above" | binary lifting |
| "maximum / minimum edge on the path", static tree | lifting with an aggregate (or HLD + sparse table) |
| "minimum spanning tree that must contain edge $e$", "second-best MST" | MST + path max |
| "count how many of these paths use each edge/vertex" | difference array on the tree + LCA |
| "is $x$ on the path from $u$ to $v$", "do these vertices lie on one path" | ancestry tests around $\mathrm{lca}$ |
| "the vertex in the middle of the path", "equidistant from $a$ and $b$" | $k$-th vertex on a path |
| $10^6$ LCA queries, tight TL | preorder + sparse table, $O(1)$ |
| "first ancestor with value $\ge x$" (values increase towards the root or are monotone) | binary lifting as a binary search on the ancestor chain |
| path aggregate *with updates* | not lifting — use [HLD](04-heavy-light-decomposition.md) or an Euler-tour trick |

## 5. Worked examples (graded)

### Example 1 — Company Queries I · ★ ≈1500 (est.)

- **Source:** [CSES 1687 · Company Queries I](https://cses.fi/problemset/task/1687)
- **Difficulty:** ≈1500 (est.)
- **Problem:** a company tree of $n \le 2\cdot10^5$ employees (1 is the director), given as the boss of each employee $2..n$. Answer $q \le 2\cdot10^5$ queries "who is the boss $k$ levels above $x$" ($-1$ if none).
- **Thinking from first principles:** walking up is $O(k)$, up to $O(nq)$. Write $k$ in binary and jump with the doubling table: $O(\log n)$. Two details: the boss list need not be in BFS order, so compute depths with a BFS over children; and answer $-1$ when $k > \mathrm{dep}(x)$ rather than relying on saturation at the root.

<details><summary>Solution</summary>

Doubling table $up_j$ (any vertex order works per level), depths by BFS from 1, then bit-decompose $k$. $O((n+q)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    int LOG = 1; while ((1 << LOG) <= n) LOG++;
    vector<vector<int>> up(LOG, vector<int>(n + 1, 1)), ch(n + 1);
    for (int v = 2; v <= n; v++) { cin >> up[0][v]; ch[up[0][v]].push_back(v); }
    vector<int> dep(n + 1, 0), order = {1};
    for (size_t i = 0; i < order.size(); i++)
        for (int c : ch[order[i]]) { dep[c] = dep[order[i]] + 1; order.push_back(c); }
    for (int j = 1; j < LOG; j++)
        for (int v = 1; v <= n; v++) up[j][v] = up[j - 1][up[j - 1][v]];
    while (q--) {
        int x, k; cin >> x >> k;
        if (k > dep[x]) { cout << -1 << '\n'; continue; }
        for (int j = 0; k; j++, k >>= 1) if (k & 1) x = up[j][x];
        cout << x << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), q = in.nextInt();
        int LOG = 1; while ((1 << LOG) <= n) LOG++;
        int[][] up = new int[LOG][n + 1];
        Arrays.fill(up[0], 1);
        int[] start = new int[n + 2];
        for (int v = 2; v <= n; v++) { up[0][v] = in.nextInt(); start[up[0][v] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] ch = new int[Math.max(1, n - 1)], fill = start.clone();
        for (int v = 2; v <= n; v++) ch[fill[up[0][v]]++] = v;
        int[] dep = new int[n + 1], order = new int[n];
        int head = 0, tail = 0;
        order[tail++] = 1;
        while (head < tail) {
            int v = order[head++];
            for (int j = start[v]; j < start[v + 1]; j++) { dep[ch[j]] = dep[v] + 1; order[tail++] = ch[j]; }
        }
        for (int j = 1; j < LOG; j++) for (int v = 0; v <= n; v++) up[j][v] = up[j - 1][up[j - 1][v]];
        StringBuilder sb = new StringBuilder();
        for (int t = 0; t < q; t++) {
            int x = in.nextInt(), k = in.nextInt();
            if (k > dep[x]) { sb.append(-1).append('\n'); continue; }
            for (int j = 0; k > 0; j++, k >>= 1) if ((k & 1) != 0) x = up[j][x];
            sb.append(x).append('\n');
        }
        out.print(sb);
        out.flush();
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

First test: bosses of $2..5$ are $1, 1, 3, 4$ (so $5 \to 4 \to 3 \to 1$). Second test: bosses listed out of BFS order ($2$'s boss is $3$, who appears later).

<!-- test
in:
5 4
1 1 3 4
5 1
5 2
5 3
5 4
out:
4
3
1
-1
-->
<!-- test
in:
4 4
3 1 2
4 3
4 2
2 2
1 0
out:
1
3
1
1
-->

</details>

### Example 2 — Fools and Roads · ★ 1900

- **Source:** [CF 191C · Fools and Roads](https://codeforces.com/problemset/problem/191/C) — 1900
- **Difficulty:** 1900
- **Problem:** a tree with $n \le 10^5$ vertices and $k \le 10^5$ paths $a_i$–$b_i$. For every edge (in input order), print how many of the paths use it.
- **Thinking from first principles:** walking each path is $O(nk)$. Think of the 1D analogue: adding $+1$ on many ranges and reading every cell is a difference array. On a tree, "the path $a$–$b$" equals "root path of $a$" + "root path of $b$" − 2 × "root path of $\ell$" as edge multisets. A root path is a prefix from below, so a $+1$ at $a$ followed by **subtree sums** counts it on every edge above $a$. So: $c_a \mathrel{+}= 1$, $c_b \mathrel{+}= 1$, $c_\ell \mathrel{-}= 2$; the answer for edge $(p, v)$ is the subtree sum at the child $v$.

<details><summary>Solution</summary>

One LCA per path, then one bottom-up pass. $O((n + k)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<vector<int>> adj(n + 1);
    vector<int> ea(n - 1), eb(n - 1);
    for (int i = 0; i < n - 1; i++) { cin >> ea[i] >> eb[i]; adj[ea[i]].push_back(eb[i]); adj[eb[i]].push_back(ea[i]); }
    int LOG = 1; while ((1 << LOG) <= n) LOG++;
    vector<vector<int>> up(LOG, vector<int>(n + 1, 1));
    vector<int> dep(n + 1, 0), order = {1}; vector<char> seen(n + 1, 0); seen[1] = 1;
    for (size_t i = 0; i < order.size(); i++) {
        int v = order[i];
        for (int u : adj[v]) if (!seen[u]) { seen[u] = 1; up[0][u] = v; dep[u] = dep[v] + 1; order.push_back(u); }
    }
    for (int j = 1; j < LOG; j++) for (int v = 1; v <= n; v++) up[j][v] = up[j - 1][up[j - 1][v]];
    auto lca = [&](int a, int b) {
        if (dep[a] < dep[b]) swap(a, b);
        for (int j = LOG - 1; j >= 0; j--) if (dep[a] - (1 << j) >= dep[b]) a = up[j][a];
        if (a == b) return a;
        for (int j = LOG - 1; j >= 0; j--) if (up[j][a] != up[j][b]) { a = up[j][a]; b = up[j][b]; }
        return up[0][a];
    };
    vector<long long> c(n + 1, 0);
    int k; cin >> k;
    while (k--) { int a, b; cin >> a >> b; c[a]++; c[b]++; c[lca(a, b)] -= 2; }
    for (int i = n - 1; i > 0; i--) c[up[0][order[i]]] += c[order[i]];   // subtree sums, bottom-up
    for (int i = 0; i < n - 1; i++) {
        int child = dep[ea[i]] > dep[eb[i]] ? ea[i] : eb[i];
        cout << c[child] << (i + 1 < n - 1 ? ' ' : '\n');
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        int[] ea = new int[n - 1], eb = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { ea[i] = in.nextInt(); eb[i] = in.nextInt(); start[ea[i] + 1]++; start[eb[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[ea[i]]++] = eb[i]; adj[fill[eb[i]]++] = ea[i]; }
        int LOG = 1; while ((1 << LOG) <= n) LOG++;
        int[][] up = new int[LOG][n + 1];
        Arrays.fill(up[0], 1);
        int[] dep = new int[n + 1], order = new int[n];
        boolean[] seen = new boolean[n + 1];
        int head = 0, tail = 0;
        order[tail++] = 1; seen[1] = true;
        while (head < tail) {
            int v = order[head++];
            for (int j = start[v]; j < start[v + 1]; j++) {
                int u = adj[j];
                if (!seen[u]) { seen[u] = true; up[0][u] = v; dep[u] = dep[v] + 1; order[tail++] = u; }
            }
        }
        for (int j = 1; j < LOG; j++) for (int v = 0; v <= n; v++) up[j][v] = up[j - 1][up[j - 1][v]];
        long[] c = new long[n + 1];
        int k = in.nextInt();
        for (int t = 0; t < k; t++) {
            int a = in.nextInt(), b = in.nextInt();
            c[a]++; c[b]++;
            int x = a, y = b;
            if (dep[x] < dep[y]) { int tmp = x; x = y; y = tmp; }
            for (int j = LOG - 1; j >= 0; j--) if (dep[x] - (1 << j) >= dep[y]) x = up[j][x];
            if (x != y) {
                for (int j = LOG - 1; j >= 0; j--) if (up[j][x] != up[j][y]) { x = up[j][x]; y = up[j][y]; }
                x = up[0][x];
            }
            c[x] -= 2;
        }
        for (int i = n - 1; i > 0; i--) c[up[0][order[i]]] += c[order[i]];
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < n - 1; i++) {
            int child = dep[ea[i]] > dep[eb[i]] ? ea[i] : eb[i];
            sb.append(c[child]).append(i + 1 < n - 1 ? ' ' : '\n');
        }
        out.print(sb);
        out.flush();
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

First test: edges $1$–$2$, $1$–$3$, $2$–$4$, $2$–$5$; paths $4$–$3$ (uses edges 3, 1, 2), $5$–$4$ (edges 4, 3), $1$–$1$ (none). Edge counts $1, 1, 2, 1$.

<!-- test
in:
5
1 2
1 3
2 4
2 5
3
4 3
5 4
1 1
out:
1 1 2 1
-->
<!-- test
in:
2
2 1
0
out:
0
-->
<!-- test
in:
4
3 4
2 3
1 2
2
4 1
3 4
out:
2 1 1
-->

</details>

### Example 3 — Passable Paths (hard version) · ★ 2000

- **Source:** [CF 1702G2 · Passable Paths (hard version)](https://codeforces.com/problemset/problem/1702/G2) — 2000
- **Difficulty:** 2000
- **Problem:** a tree with $n \le 2\cdot10^5$ vertices; $q$ queries, each a set of $k$ vertices ($\sum k \le 2\cdot10^5$). Decide whether some simple path contains all of them.
- **Thinking from first principles:** if a path exists, shrink it to its two extreme query vertices $a$, $b$. Root the tree. The deepest query vertex must be an endpoint: an interior vertex of a path either is its top (then both ends go deeper) or has a child on the path (then the path continues to something deeper). So $a$ = deepest. Every other vertex is either an ancestor of $a$ (on $a$'s root path) or must be on the $b$ branch; the deepest of those is $b$. If there is none, all vertices are ancestors of $a$ and the answer is YES. Otherwise check every vertex against path$(a, b)$ with the ancestry test of §1.6.

<details><summary>Solution</summary>

Per query: one pass to find $a$, one to find $b$, one LCA, one pass of $O(1)$ tests. $O((n + \sum k)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; adj[a].push_back(b); adj[b].push_back(a); }
    int LOG = 1; while ((1 << LOG) <= n) LOG++;
    vector<vector<int>> up(LOG, vector<int>(n + 1, 1));
    vector<int> dep(n + 1, 0), tin(n + 1), sz(n + 1, 1), order, st = {1};
    while (!st.empty()) {
        int v = st.back(); st.pop_back();
        tin[v] = order.size(); order.push_back(v);
        for (int u : adj[v]) if (u != up[0][v]) { up[0][u] = v; dep[u] = dep[v] + 1; st.push_back(u); }   // up[0][1] = 1 is never a neighbour of 1
    }
    for (int i = n - 1; i > 0; i--) sz[up[0][order[i]]] += sz[order[i]];
    for (int j = 1; j < LOG; j++) for (int v = 1; v <= n; v++) up[j][v] = up[j - 1][up[j - 1][v]];
    auto anc = [&](int a, int b) { return tin[a] <= tin[b] && tin[b] < tin[a] + sz[a]; };
    auto lca = [&](int a, int b) {
        if (anc(a, b)) return a;
        for (int j = LOG - 1; j >= 0; j--) if (!anc(up[j][a], b)) a = up[j][a];
        return up[0][a];
    };
    int q; cin >> q;
    while (q--) {
        int k; cin >> k;
        vector<int> p(k);
        for (int& x : p) cin >> x;
        int a = p[0];
        for (int x : p) if (dep[x] > dep[a]) a = x;
        int b = -1;
        for (int x : p) if (!anc(x, a) && (b < 0 || dep[x] > dep[b])) b = x;
        bool ok = true;
        if (b >= 0) {
            int l = lca(a, b);
            for (int x : p) if (!(anc(l, x) && (anc(x, a) || anc(x, b)))) { ok = false; break; }
        }
        cout << (ok ? "YES" : "NO") << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int LOG;
    static int[][] up;
    static int[] tin, sz;
    static boolean anc(int a, int b) { return tin[a] <= tin[b] && tin[b] < tin[a] + sz[a]; }
    static int lca(int a, int b) {
        if (anc(a, b)) return a;
        for (int j = LOG - 1; j >= 0; j--) if (!anc(up[j][a], b)) a = up[j][a];
        return up[0][a];
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        LOG = 1; while ((1 << LOG) <= n) LOG++;
        up = new int[LOG][n + 1];
        int[] par = new int[n + 1], dep = new int[n + 1], order = new int[n], st = new int[n];
        tin = new int[n + 1]; sz = new int[n + 1];
        int top = 0, cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top];
            tin[v] = cnt; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) if (adj[j] != par[v]) { par[adj[j]] = v; dep[adj[j]] = dep[v] + 1; st[top++] = adj[j]; }
        }
        Arrays.fill(sz, 1);
        for (int i = n - 1; i > 0; i--) sz[par[order[i]]] += sz[order[i]];
        for (int v = 0; v <= n; v++) up[0][v] = v == 1 || v == 0 ? 1 : par[v];
        for (int j = 1; j < LOG; j++) for (int v = 0; v <= n; v++) up[j][v] = up[j - 1][up[j - 1][v]];
        int q = in.nextInt();
        StringBuilder sb = new StringBuilder();
        int[] p = new int[n];
        while (q-- > 0) {
            int k = in.nextInt();
            int a = -1;
            for (int i = 0; i < k; i++) { p[i] = in.nextInt(); if (a < 0 || dep[p[i]] > dep[a]) a = p[i]; }
            int b = -1;
            for (int i = 0; i < k; i++) if (!anc(p[i], a) && (b < 0 || dep[p[i]] > dep[b])) b = p[i];
            boolean ok = true;
            if (b >= 0) {
                int l = lca(a, b);
                for (int i = 0; i < k && ok; i++) ok = anc(l, p[i]) && (anc(p[i], a) || anc(p[i], b));
            }
            sb.append(ok ? "YES" : "NO").append('\n');
        }
        out.print(sb);
        out.flush();
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

Tree of the first test: $1$–$2$, $2$–$3$, $2$–$4$, $4$–$5$, $1$–$6$. $\{3,5\}$: path $3$–$2$–$4$–$5$ → YES. $\{3,5,6\}$: $6$ is off that path and $3$, $5$, $6$ are three leaves → NO. $\{5,6,2\}$: path $5$–$4$–$2$–$1$–$6$ → YES. $\{3,4,1\}$: $3$ and $4$ are both children of $2$, and $1$ is above $2$ — a "Y" shape → NO.

<!-- test
in:
6
1 2
2 3
2 4
4 5
1 6
4
2
3 5
3
3 5 6
3
5 6 2
3
3 4 1
out:
YES
NO
YES
NO
-->
<!-- test
in:
1
1
1
1
out:
YES
-->
<!-- test
in:
3
2 1
3 1
3
3
1 2 3
2
2 3
1
2
out:
YES
YES
YES
-->

</details>

### Example 4 — Minimum spanning tree for each edge · ★ 2100

- **Source:** [CF 609E · Minimum spanning tree for each edge](https://codeforces.com/problemset/problem/609/E) — 2100
- **Difficulty:** 2100
- **Problem:** connected weighted graph, $n, m \le 2\cdot10^5$, weights up to $10^9$. For every edge $(u,v,w)$, print the minimum total weight of a spanning tree that contains it.
- **Thinking from first principles:** recomputing an MST per edge is $O(m^2)$. Fix one MST $T$ of weight $W$. Forcing edge $(u,v)$ in creates exactly one cycle with $T$: the tree path $u$–$v$ plus the new edge. To get back to a tree we must delete one cycle edge, and the best choice is the heaviest edge on the tree path (cut property). So the answer is $W - \max_{T\text{-path}(u,v)} w + w(u,v)$. Static tree, max over paths, many queries: binary lifting with a max aggregate.

<details><summary>Solution</summary>

Kruskal with DSU, build $T$, root it, lift with `mx[j][v]` = max edge weight on the $2^j$ jump from $v$. For MST edges the formula gives $W$ automatically. $O((n + m)\log n)$. Java: sort packed `long` keys after a shuffle (anti-quicksort tests target `Arrays.sort` on primitives).

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    vector<int> U(m), V(m); vector<long long> Wt(m);
    for (int i = 0; i < m; i++) cin >> U[i] >> V[i] >> Wt[i];
    vector<int> idx(m); iota(idx.begin(), idx.end(), 0);
    sort(idx.begin(), idx.end(), [&](int a, int b) { return Wt[a] < Wt[b]; });
    vector<int> dsu(n + 1); iota(dsu.begin(), dsu.end(), 0);
    auto find = [&](int x) { while (dsu[x] != x) x = dsu[x] = dsu[dsu[x]]; return x; };
    vector<vector<pair<int,int>>> adj(n + 1);
    long long W = 0;
    for (int i : idx) {
        int a = find(U[i]), b = find(V[i]);
        if (a == b) continue;
        dsu[a] = b; W += Wt[i];
        adj[U[i]].push_back({V[i], (int)Wt[i]}); adj[V[i]].push_back({U[i], (int)Wt[i]});
    }
    int LOG = 1; while ((1 << LOG) <= n) LOG++;
    vector<vector<int>> up(LOG, vector<int>(n + 1, 1)), mx(LOG, vector<int>(n + 1, 0));
    vector<int> dep(n + 1, 0), order = {1}; vector<char> seen(n + 1, 0); seen[1] = 1;
    for (size_t i = 0; i < order.size(); i++) {
        int v = order[i];
        for (auto [u, w] : adj[v]) if (!seen[u]) { seen[u] = 1; up[0][u] = v; mx[0][u] = w; dep[u] = dep[v] + 1; order.push_back(u); }
    }
    for (int j = 1; j < LOG; j++)
        for (int v = 1; v <= n; v++) {
            up[j][v] = up[j - 1][up[j - 1][v]];
            mx[j][v] = max(mx[j - 1][v], mx[j - 1][up[j - 1][v]]);
        }
    auto pathMax = [&](int a, int b) {
        int res = 0;
        if (dep[a] < dep[b]) swap(a, b);
        for (int j = LOG - 1; j >= 0; j--) if (dep[a] - (1 << j) >= dep[b]) { res = max(res, mx[j][a]); a = up[j][a]; }
        if (a == b) return res;
        for (int j = LOG - 1; j >= 0; j--)
            if (up[j][a] != up[j][b]) { res = max({res, mx[j][a], mx[j][b]}); a = up[j][a]; b = up[j][b]; }
        return max({res, mx[0][a], mx[0][b]});
    };
    for (int i = 0; i < m; i++) cout << W - pathMax(U[i], V[i]) + Wt[i] << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] dsu;
    static int find(int x) { while (dsu[x] != x) x = dsu[x] = dsu[dsu[x]]; return x; }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), m = in.nextInt();
        int[] U = new int[m], V = new int[m];
        long[] Wt = new long[m], key = new long[m];
        for (int i = 0; i < m; i++) { U[i] = in.nextInt(); V[i] = in.nextInt(); Wt[i] = in.nextLong(); key[i] = (Wt[i] << 18) | i; }
        Random rnd = new Random(12345);
        for (int i = m - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long t = key[i]; key[i] = key[j]; key[j] = t; }
        Arrays.sort(key);
        dsu = new int[n + 1];
        for (int v = 0; v <= n; v++) dsu[v] = v;
        int[] tu = new int[n - 1], tv = new int[n - 1], tw = new int[n - 1], start = new int[n + 2];
        int tc = 0;
        long W = 0;
        for (long k : key) {
            int i = (int) (k & ((1 << 18) - 1));
            int a = find(U[i]), b = find(V[i]);
            if (a == b) continue;
            dsu[a] = b; W += Wt[i];
            tu[tc] = U[i]; tv[tc] = V[i]; tw[tc++] = (int) Wt[i];
            start[U[i] + 1]++; start[V[i] + 1]++;
        }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], aw = new int[2 * (n - 1)], fill = start.clone();
        for (int e = 0; e < tc; e++) {
            aw[fill[tu[e]]] = tw[e]; adj[fill[tu[e]]++] = tv[e];
            aw[fill[tv[e]]] = tw[e]; adj[fill[tv[e]]++] = tu[e];
        }
        int LOG = 1; while ((1 << LOG) <= n) LOG++;
        int[][] up = new int[LOG][n + 1], mx = new int[LOG][n + 1];
        Arrays.fill(up[0], 1);
        int[] dep = new int[n + 1], order = new int[n];
        boolean[] seen = new boolean[n + 1];
        int head = 0, tail = 0;
        order[tail++] = 1; seen[1] = true;
        while (head < tail) {
            int v = order[head++];
            for (int j = start[v]; j < start[v + 1]; j++) {
                int u = adj[j];
                if (!seen[u]) { seen[u] = true; up[0][u] = v; mx[0][u] = aw[j]; dep[u] = dep[v] + 1; order[tail++] = u; }
            }
        }
        for (int j = 1; j < LOG; j++)
            for (int v = 0; v <= n; v++) {
                up[j][v] = up[j - 1][up[j - 1][v]];
                mx[j][v] = Math.max(mx[j - 1][v], mx[j - 1][up[j - 1][v]]);
            }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < m; i++) {
            int a = U[i], b = V[i], res = 0;
            if (dep[a] < dep[b]) { int t = a; a = b; b = t; }
            for (int j = LOG - 1; j >= 0; j--) if (dep[a] - (1 << j) >= dep[b]) { res = Math.max(res, mx[j][a]); a = up[j][a]; }
            if (a != b) {
                for (int j = LOG - 1; j >= 0; j--)
                    if (up[j][a] != up[j][b]) { res = Math.max(res, Math.max(mx[j][a], mx[j][b])); a = up[j][a]; b = up[j][b]; }
                res = Math.max(res, Math.max(mx[0][a], mx[0][b]));
            }
            sb.append(W - res + Wt[i]).append('\n');
        }
        out.print(sb);
        out.flush();
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

First test by hand: the MST uses $1$–$3$ (1), $2$–$3$ (2), $3$–$4$ (2), weight 5. Edge $1$–$2$ (3): tree path $1$–$3$–$2$ has max 2, answer $5-2+3 = 6$. Edge $2$–$4$ (5): path $2$–$3$–$4$ max 2, answer 8. Edge $1$–$4$ (4): path $1$–$3$–$4$ max 2, answer 7.

<!-- test
in:
4 6
1 2 3
1 3 1
2 3 2
2 4 5
3 4 2
1 4 4
out:
6
5
5
8
5
7
-->
<!-- test
in:
2 1
1 2 1000000000
out:
1000000000
-->
<!-- test
in:
3 3
1 2 5
2 3 5
1 3 5
out:
10
10
10
-->

</details>

### Example 5 — A and B and Lecture Rooms · ★ 2100

- **Source:** [CF 519E · A and B and Lecture Rooms](https://codeforces.com/problemset/problem/519/E) — 2100
- **Difficulty:** 2100
- **Problem:** a tree with $n \le 10^5$ vertices and $m \le 10^5$ queries $(x, y)$: how many vertices are at equal distance from $x$ and $y$?
- **Thinking from first principles:** the vertices equidistant from $x$ and $y$ are those whose "entry point" onto the $x$–$y$ path is its exact middle vertex $c$, entering from a side branch (not along the path). So: if $x = y$ the answer is $n$; if $d(x,y)$ is odd there is no middle vertex and the answer is $0$. Otherwise find the middle with the $k$-th-vertex-on-path trick and count by subtree sizes. Two cases:
  - $\mathrm{dep}(x) = \mathrm{dep}(y)$: the middle is the LCA. Everything outside the LCA's subtree enters the path at the LCA from above, so it counts; exclude only the two child subtrees towards $x$ and towards $y$. Answer $n - sz(c_x) - sz(c_y)$.
  - $x$ deeper: the middle $c$ is the $\frac d2$-th ancestor of $x$, strictly below the LCA. Now the parent of $c$ lies on the path **towards $y$**, so everything outside $c$'s subtree is closer to $y$ and is excluded, as is the child subtree towards $x$. Answer $sz(c) - sz(c_x)$.

<details><summary>Solution</summary>

All four ingredients — distance, LCA, $k$-th ancestor, subtree sizes — come from one lifting table. $O((n + m)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; adj[a].push_back(b); adj[b].push_back(a); }
    int LOG = 1; while ((1 << LOG) <= n) LOG++;
    vector<vector<int>> up(LOG, vector<int>(n + 1, 1));
    vector<int> dep(n + 1, 0), sz(n + 1, 1), order = {1}; vector<char> seen(n + 1, 0); seen[1] = 1;
    for (size_t i = 0; i < order.size(); i++) {
        int v = order[i];
        for (int u : adj[v]) if (!seen[u]) { seen[u] = 1; up[0][u] = v; dep[u] = dep[v] + 1; order.push_back(u); }
    }
    for (int i = n - 1; i > 0; i--) sz[up[0][order[i]]] += sz[order[i]];
    for (int j = 1; j < LOG; j++) for (int v = 1; v <= n; v++) up[j][v] = up[j - 1][up[j - 1][v]];
    auto kth = [&](int v, int k) { for (int j = 0; k; j++, k >>= 1) if (k & 1) v = up[j][v]; return v; };
    auto lca = [&](int a, int b) {
        if (dep[a] < dep[b]) swap(a, b);
        a = kth(a, dep[a] - dep[b]);
        if (a == b) return a;
        for (int j = LOG - 1; j >= 0; j--) if (up[j][a] != up[j][b]) { a = up[j][a]; b = up[j][b]; }
        return up[0][a];
    };
    int m; cin >> m;
    while (m--) {
        int x, y; cin >> x >> y;
        if (x == y) { cout << n << '\n'; continue; }
        int l = lca(x, y), d = dep[x] + dep[y] - 2 * dep[l];
        if (d % 2) { cout << 0 << '\n'; continue; }
        if (dep[x] < dep[y]) swap(x, y);
        if (dep[x] == dep[y]) {
            int cx = kth(x, d / 2 - 1), cy = kth(y, d / 2 - 1);   // children of l towards x and y
            cout << n - sz[cx] - sz[cy] << '\n';
        } else {
            int c = kth(x, d / 2), cx = kth(x, d / 2 - 1);
            cout << sz[c] - sz[cx] << '\n';
        }
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int LOG;
    static int[][] up;
    static int[] dep;
    static int kth(int v, int k) { for (int j = 0; k > 0; j++, k >>= 1) if ((k & 1) != 0) v = up[j][v]; return v; }
    static int lca(int a, int b) {
        if (dep[a] < dep[b]) { int t = a; a = b; b = t; }
        a = kth(a, dep[a] - dep[b]);
        if (a == b) return a;
        for (int j = LOG - 1; j >= 0; j--) if (up[j][a] != up[j][b]) { a = up[j][a]; b = up[j][b]; }
        return up[0][a];
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        LOG = 1; while ((1 << LOG) <= n) LOG++;
        up = new int[LOG][n + 1]; dep = new int[n + 1];
        Arrays.fill(up[0], 1);
        int[] sz = new int[n + 1], order = new int[n];
        boolean[] seen = new boolean[n + 1];
        int head = 0, tail = 0;
        order[tail++] = 1; seen[1] = true;
        while (head < tail) {
            int v = order[head++];
            for (int j = start[v]; j < start[v + 1]; j++) {
                int u = adj[j];
                if (!seen[u]) { seen[u] = true; up[0][u] = v; dep[u] = dep[v] + 1; order[tail++] = u; }
            }
        }
        Arrays.fill(sz, 1);
        for (int i = n - 1; i > 0; i--) sz[up[0][order[i]]] += sz[order[i]];
        for (int j = 1; j < LOG; j++) for (int v = 0; v <= n; v++) up[j][v] = up[j - 1][up[j - 1][v]];
        int m = in.nextInt();
        StringBuilder sb = new StringBuilder();
        while (m-- > 0) {
            int x = in.nextInt(), y = in.nextInt();
            if (x == y) { sb.append(n).append('\n'); continue; }
            int l = lca(x, y), d = dep[x] + dep[y] - 2 * dep[l];
            if (d % 2 != 0) { sb.append(0).append('\n'); continue; }
            if (dep[x] < dep[y]) { int t = x; x = y; y = t; }
            if (dep[x] == dep[y]) sb.append(n - sz[kth(x, d / 2 - 1)] - sz[kth(y, d / 2 - 1)]).append('\n');
            else sb.append(sz[kth(x, d / 2)] - sz[kth(x, d / 2 - 1)]).append('\n');
        }
        out.print(sb);
        out.flush();
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

First test, tree $1$–$2$, $1$–$3$, $2$–$4$, $2$–$5$, $3$–$6$, $4$–$7$: $(4,6)$ has distance 4 and middle 1, reached from the branches of 2 and 3 — only vertex 1 itself counts → 1. $(7,5)$: distance 3, odd → 0. $(4,3)$: distance 3 → 0. $(7,2)$: distance 2, middle 4; vertices whose route enters at 4 from a side branch: just 4 → 1. $(5,4)$: middle 2 with siblings' subtrees excluded: $\{1, 2, 3, 6\}$ → 4. $(3,3)$ → 7.

<!-- test
in:
7
1 2
1 3
2 4
2 5
3 6
4 7
6
4 6
7 5
4 3
7 2
5 4
3 3
out:
1
0
0
1
4
7
-->
<!-- test
in:
4
1 2
2 3
3 4
3
1 3
2 4
1 4
out:
1
1
0
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Root's parent = root**, not 0, in the lifting table; otherwise `up[j][0]` must also be defined (set `up[*][0] = 0`), and LCA logic that compares ancestors breaks when a jump lands on 0.
2. **`LOG` must satisfy $2^{LOG} > \max \text{depth}$.** Use `while ((1 << LOG) <= n) LOG++`; a hard-coded `LOG = 17` fails at $n = 2\cdot10^5$ (needs 18).
3. **Memory layout**: `up[j][v]` (level-major) builds and queries faster than `up[v][j]` for large $n$ in both languages, and in Java `int[LOG][n+1]` is just LOG arrays — fine; `int[n+1][LOG]` is $n$ tiny arrays, slow and memory-hungry.
4. **Check $k > \mathrm{dep}(v)$ before lifting** for "does the $k$-th ancestor exist" — saturation silently returns the root.
5. **Edge aggregates live at the child** ($mx_0(v)$ = weight of edge $(p(v), v)$). In the final step of a path-max query include both $mx_0(a)$ and $mx_0(b)$ — forgetting one is the classic WA.
6. **Tie the sparse table to an idempotent operation** (min/max/gcd). Sums over ranges need prefix sums or Fenwick instead.
7. **Do not recurse to build lifting tables in Java** — the BFS order is enough (parents before children), and level-by-level filling does not even need an order.
8. **Difference on the tree**: for vertex-weighted paths subtract at $\ell$ *and* at $p(\ell)$; for edge-weighted paths subtract $2$ at $\ell$. Mixing them up double-counts the LCA.
9. **Overflow**: weighted depths $D(v)$ can reach $2\cdot10^{14}$; keep them in `long long`.
10. **Java sorting of edges**: pack (weight, index) into a `long` and shuffle before `Arrays.sort`, or sort an `Integer[]`/object array (merge sort, no adversarial worst case, but slower).
11. **When $q \ge 10^6$**, $O(\log n)$ lifting can TLE in Java; switch to the $O(1)$ preorder + sparse table version.

## 7. Going further (toward 2400–2600+)

- **Lifting as a binary search on ancestors**: "the highest ancestor whose value is $\le x$" or "how far can I climb with budget $B$" — [CF 932D · Tree](https://codeforces.com/problemset/problem/932/D) — 2200, [CF 1059E · Split the Tree](https://codeforces.com/problemset/problem/1059/E) — 2400, [CF 739B · Alyona and a tree](https://codeforces.com/problemset/problem/739/B) — 1900.
- **Mergeable small aggregates on jumps**: store the 10 smallest ids per jump — [CF 587C · Duff in the Army](https://codeforces.com/problemset/problem/587/C) — 2200; store a max-subarray summary per jump (non-commutative) — [CF 1843F2 · Omsk Metro (hard version)](https://codeforces.com/problemset/problem/1843/F2) — 2300 (also solved with HLD in [file 04](04-heavy-light-decomposition.md)).
- **LCA of an interval of vertex labels** with "remove one vertex" — [CF 1062E · Company](https://codeforces.com/problemset/problem/1062/E) — 2300 (uses $\mathrm{lca}(S)$ via min/max $tin$).
- **Graph + few extra edges**: distances via tree LCA plus Dijkstra from the endpoints of the $\le 21$ non-tree edges — [CF 1051F · The Shortest Statement](https://codeforces.com/problemset/problem/1051/F) — 2400.
- **Ladder / long-path decomposition** gives $O(1)$ $k$-th ancestor after $O(n\log n)$ preprocessing; rarely needed but elegant.
- **Dynamic trees** (link/cut with LCA queries): [link-cut trees](../16-IGM-Frontier/03-link-cut-trees.md).
- Revision: [cheat sheet](../99-Cheat-Sheets/10-trees-cheatsheet.md).

## 8. Practice ladder

**1400–1700**
- [ ] [CSES 1687 · Company Queries I](https://cses.fi/problemset/task/1687)
- [ ] [CSES 1688 · Company Queries II](https://cses.fi/problemset/task/1688)
- [ ] [CSES 1135 · Distance Queries](https://cses.fi/problemset/task/1135)
- [ ] [CSES 1136 · Counting Paths](https://cses.fi/problemset/task/1136) — difference array on the tree

**1700–2100**
- [ ] [CF 1702G1 · Passable Paths (easy version)](https://codeforces.com/problemset/problem/1702/G1) — 1900
- [ ] [CF 191C · Fools and Roads](https://codeforces.com/problemset/problem/191/C) — 1900
- [ ] [CF 832D · Misha, Grisha and Underground](https://codeforces.com/problemset/problem/832/D) — 1900
- [ ] [CF 739B · Alyona and a tree](https://codeforces.com/problemset/problem/739/B) — 1900
- [ ] [CF 1843F1 · Omsk Metro (simple version)](https://codeforces.com/problemset/problem/1843/F1) — 1800
- [ ] [CF 1304E · 1-Trees and Queries](https://codeforces.com/problemset/problem/1304/E) — 2000
- [ ] [CF 1702G2 · Passable Paths (hard version)](https://codeforces.com/problemset/problem/1702/G2) — 2000
- [ ] [CF 609E · Minimum spanning tree for each edge](https://codeforces.com/problemset/problem/609/E) — 2100
- [ ] [CF 519E · A and B and Lecture Rooms](https://codeforces.com/problemset/problem/519/E) — 2100
- [ ] [CF 208E · Blood Cousins](https://codeforces.com/problemset/problem/208/E) — 2100

**2100–2400**
- [ ] [CF 932D · Tree](https://codeforces.com/problemset/problem/932/D) — 2200
- [ ] [CF 587C · Duff in the Army](https://codeforces.com/problemset/problem/587/C) — 2200
- [ ] [CF 1062E · Company](https://codeforces.com/problemset/problem/1062/E) — 2300
- [ ] [CF 1843F2 · Omsk Metro (hard version)](https://codeforces.com/problemset/problem/1843/F2) — 2300
- [ ] [CF 1051F · The Shortest Statement](https://codeforces.com/problemset/problem/1051/F) — 2400
- [ ] [CF 1059E · Split the Tree](https://codeforces.com/problemset/problem/1059/E) — 2400

## 9. LeetCode / FAANG cross-reference

- [LC 236 · Lowest Common Ancestor of a Binary Tree](https://leetcode.com/problems/lowest-common-ancestor-of-a-binary-tree/) — Medium — the single-query recursive version; know it cold for interviews.
- [LC 235 · Lowest Common Ancestor of a Binary Search Tree](https://leetcode.com/problems/lowest-common-ancestor-of-a-binary-search-tree/) — Medium — the BST order replaces the search: walk down until $u$ and $v$ split.
- [LC 1123 · Lowest Common Ancestor of Deepest Leaves](https://leetcode.com/problems/lowest-common-ancestor-of-deepest-leaves/) — Medium — LCA of a set (here: of all deepest leaves).
- [LC 1483 · Kth Ancestor of a Tree Node](https://leetcode.com/problems/kth-ancestor-of-a-tree-node/) — Hard — exactly binary lifting (§3.1); a favourite "design" question.
- [LC 2846 · Minimum Edge Weight Equilibrium Queries in a Tree](https://leetcode.com/problems/minimum-edge-weight-equilibrium-queries-in-a-tree/) — Hard — per-weight prefix counts from the root + LCA.
- [LC 2509 · Cycle Length Queries in a Tree](https://leetcode.com/problems/cycle-length-queries-in-a-tree/) — Hard — LCA in an implicit heap-numbered binary tree (halve the larger label).
- [LC 2836 · Maximize Value of Function in a Ball Passing Game](https://leetcode.com/problems/maximize-value-of-function-in-a-ball-passing-game/) — Hard — binary lifting with a sum aggregate on a functional graph.

Interview note: LCA itself is common (236/235); binary lifting appears mostly in "design an API" form (1483) — explain the doubling table and the $O(\log n)$ query.

## 10. Self-check

1. Why is "jump both by $2^j$ when the ancestors differ" a correct binary search? What is the monotone predicate?
2. What breaks if the root's ancestor is stored as 0 and vertex 0 is not initialised?
3. Prove that the minimum-depth vertex between $first(u)$ and $first(v)$ in the Euler tour is the LCA.
4. In the preorder trick, why is the minimum of $tin(\mathrm{parent}(x))$ over $(tin(u), tin(v)]$ attained at a child of the LCA?
5. How do you find the vertex at distance $k$ from $u$ on the path to $v$?
6. Path-max with point updates of edge weights: can you still use lifting? What do you use instead?
7. Give the difference-array updates for "add $x$ to every vertex on path $u$–$v$".
8. How many levels does the table need for $n = 2^{18}$ exactly, and why?

<details><summary>Answers</summary>

1. At equal depth with $u \ne v$, $f(t)$ = "the $t$-th ancestors coincide" is false below the LCA and true from the LCA upward. The loop finds the largest $t$ with $f(t)$ false bit by bit (standard binary search on a monotone predicate); the LCA is one step above.
2. A jump from near the root lands on 0, and `up[j][0]` is garbage or 0; comparisons `up[j][a] != up[j][b]` may then be equal for the wrong reason, or index out of range. Either saturate at the root or define vertex 0 to map to itself.
3. The walk from $u$ to $v$ in the tour stays inside the LCA's subtree (it cannot leave before visiting $v$), so no vertex above the LCA appears; and to get from $u$'s child-subtree of the LCA to $v$'s, it must pass through the LCA. (If $u$ is an ancestor of $v$, the range starts at $u$ itself.)
4. Every vertex in the range lies strictly inside the LCA's subtree, so its parent has $tin \ge tin(\mathrm{lca})$, with equality only for children of the LCA; the child of the LCA on the way to $v$ is in the range.
5. Let $\ell = \mathrm{lca}(u,v)$. If $k \le \mathrm{dep}(u) - \mathrm{dep}(\ell)$: the $k$-th ancestor of $u$; else the $(d(u,v) - k)$-th ancestor of $v$.
6. No — a point update changes $O(n)$ table entries in the worst case (every jump that covers the edge). Use [HLD](04-heavy-light-decomposition.md) with a segment tree ($O(\log^2 n)$ per query) or a link-cut tree.
7. $c_u \mathrel{+}= x$, $c_v \mathrel{+}= x$, $c_\ell \mathrel{-}= x$, $c_{p(\ell)} \mathrel{-}= x$ (skip the last if $\ell$ is the root), then subtree sums give each vertex's total.
8. Max depth is $n - 1 = 2^{18} - 1$, which needs bits $0..17$: 18 levels. The loop `while ((1 << LOG) <= n)` gives $LOG = 19$ here — one spare level is harmless.

</details>
