# Cheat sheet — 10 Trees

Revision only. Full derivations, proofs and tested programs: [README](../10-Trees/README.md) · [01 basics](../10-Trees/01-tree-basics-diameter-center-euler-tour.md) · [02 LCA](../10-Trees/02-lca-and-binary-lifting.md) · [03 small-to-large](../10-Trees/03-small-to-large-and-dsu-on-tree.md) · [04 HLD](../10-Trees/04-heavy-light-decomposition.md) · [05 centroid](../10-Trees/05-centroid-decomposition.md) · [06 virtual trees](../10-Trees/06-virtual-trees.md) · [problems](../10-Trees/problems.md). Tree DP / rerooting: [06/08](../06-Dynamic-Programming/08-tree-dp-and-rerooting.md).

## 1. Facts and formulas

| Fact | Formula / statement |
|---|---|
| tree ⇔ | connected + acyclic ⇔ connected with $n-1$ edges ⇔ unique simple paths |
| degrees | $\sum \deg = 2n-2$; leaves $= 2 + \sum_{\deg \ge 2}(\deg - 2)$ |
| depths vs sizes | $\sum_v sz(v) = \sum_v (\mathrm{dep}(v)+1)$ |
| all-pairs distance sum | $\sum_{e=(p,c)} w_e\, sz(c)(n - sz(c))$ |
| eccentricity (w ≥ 0) | $\mathrm{ecc}(s) = \max(d(s,a), d(s,b))$ for any diameter $(a,b)$ |
| diameter (any weights) | $\max_t (h_1(t) + h_2(t))$, $h(v) = \max(0, \max_c h(c) + w)$ |
| centre | middle of the diameter; 1 centre if $D$ even, 2 adjacent if odd; radius $\lceil D/2\rceil$ |
| centroid | $\max(n - sz(v), \max_c sz(c)) \le n/2$; $\le 2$ of them, adjacent; minimises $\sum_u d(v,u)$ |
| subtree as range | subtree$(v) = [tin(v), tin(v) + sz(v))$ in any preorder |
| ancestor test | $tin(u) \le tin(v) < tin(u) + sz(u)$ |
| distance | $d(u,v) = D(u) + D(v) - 2D(\mathrm{lca})$ |
| path sum (invertible) | $S(u) + S(v) - 2S(\ell) + a_\ell$, $S$ = root-path sum |
| root-path sums with point updates | range add on $[tin(x), tout(x)]$, point query at $tin(v)$ |
| path add (vertices) | $c_u{+}{=}x,\ c_v{+}{=}x,\ c_\ell{-}{=}x,\ c_{p(\ell)}{-}{=}x$, then subtree sums |
| path add (edges at child) | $c_u{+}{=}x,\ c_v{+}{=}x,\ c_\ell{-}{=}2x$ |
| $x$ on path $u$–$v$ | $\ell \preceq x$ and ($x \preceq u$ or $x \preceq v$); or $d(u,x)+d(x,v) = d(u,v)$ |
| $k$-th vertex on $u \to v$ | $k \le \mathrm{dep}(u) - \mathrm{dep}(\ell)$ ? $\mathrm{kth}(u,k)$ : $\mathrm{kth}(v, d - k)$ |
| LCA of a set | $\mathrm{lca}(\arg\min tin, \arg\max tin)$ |
| preorder $O(1)$ LCA | $\mathrm{order}[\min_{(tin(u), tin(v)]} tin(p(\cdot))]$ |
| light edge $(p,c)$ | $sz(p) > 2\,sz(c)$ ⇒ $\le \log_2 n$ light edges on a root path |
| virtual tree | $V' = K \cup \{\mathrm{lca}(x_t, x_{t+1})\}$ ($tin$-sorted), $\lvert V'\rvert \le 2k-1$, $vpar(y_i) = \mathrm{lca}(y_{i-1}, y_i)$ |
| Steiner tree weight | $\frac12 \sum_t d(x_t, x_{t+1 \bmod k})$, keys sorted by $tin$ |
| Cayley / Prüfer | $n^{n-2}$ labelled trees; $n^{n-1}$ rooted; degrees $d_i$: $\frac{(n-2)!}{\prod (d_i - 1)!}$; $v$ appears $\deg v - 1$ times |
| forests | $k\,n^{n-k-1}$ forests with $k$ trees, given $k$ roots in distinct trees |

## 2. Complexity table

| Technique | Build | Query / update | Memory |
|---|---|---|---|
| rooting, sizes, tin, diameter, centres, centroids | $O(n)$ | — | $O(n)$ |
| Euler tour + Fenwick | $O(n)$ | $O(\log n)$ | $O(n)$ |
| binary lifting (LCA, $k$-th, path max) | $O(n\log n)$ | $O(\log n)$ | $O(n\log n)$ |
| preorder + sparse table LCA | $O(n\log n)$ | $O(1)$ | $O(n\log n)$ |
| Tarjan offline LCA | $O((n+q)\alpha)$ | — | $O(n+q)$ |
| small-to-large (set/map) | — | $O(n\log^2 n)$ total | $O(n)$ |
| sack (count array) | — | $O(n\log n)$ total | $O(n)$ |
| HLD + segment tree | $O(n)$ | path $O(\log^2 n)$, subtree $O(\log n)$ | $O(n)$ |
| centroid decomposition | $O(n\log n)$ | per path-count $O(n\log n)$–$O(n\log^2 n)$; centroid-tree query $O(\log n)$ | $O(n\log n)$ with distance tables |
| virtual tree | — | $O(k\log k)$ per query | $O(k)$ extra |
| rooted isomorphism (AHU ids) | $O(n\log n)$ | — | $O(n)$ |
| Prüfer encode/decode | $O(n)$ | — | $O(n)$ |

Constants: $n = 2\cdot10^5$ needs `LOG = 18` ($2^{18} = 262144$); the safe loop is `LOG = 1; while ((1 << LOG) <= n) LOG++`. Lifting tables: $18 \times 2\cdot10^5$ ints ≈ 14 MB. Centroid levels $\le 18$.

## 3. Signal → technique

| Signal in the statement | Technique |
|---|---|
| "subtree of $v$" sum/min with updates | Euler tour + Fenwick / segment tree |
| "root to $v$" sums with point updates | subtree range add + point query |
| distinct / most frequent / "≥ k times" in subtree | sack or small-to-large (offline) |
| $k$-th ancestor, "go up $k$ levels", first ancestor with property | binary lifting |
| static path max/min/gcd | binary lifting with aggregates |
| path max/sum **with updates**, path assign | HLD + segment tree (lazy for path updates) |
| direction-dependent path aggregate | HLD with `accU ⊕ rev(piece)`, `piece ⊕ accV` |
| count paths with length $= k$ / $\le K$ / in $[a,b]$, $n \ge 10^5$ | centroid decomposition |
| nearest marked vertex, marks added online | centroid tree, $\min_c d(v,c) + best(c)$ |
| "$\sum k \le$" over queries of vertex sets | virtual tree + DP |
| "farthest vertex from every vertex" | diameter endpoints (3 passes) |
| "min max distance" / "min sum of distances" | centre / centroid |
| "same tree up to relabelling" | AHU canonical ids (root at centre) |
| "count labelled trees with degree constraints" | Prüfer multinomial |
| MST containing edge $e$ / second-best MST | MST + path max via lifting |
| many paths, count usage per edge | difference array on tree + LCA |

## 4. Templates

### 4.1 Iterative rooting (preorder, parents, depth, sizes)

```cpp
// adj is 1-indexed; returns preorder; fills par, dep, sz, tin
vector<int> rootTree(const vector<vector<int>>& adj, int root, vector<int>& par, vector<int>& dep, vector<int>& sz, vector<int>& tin) {
    int n = adj.size() - 1;
    par.assign(n + 1, 0); dep.assign(n + 1, 0); sz.assign(n + 1, 1); tin.assign(n + 1, 0);
    vector<int> order, st = {root};
    while (!st.empty()) {
        int v = st.back(); st.pop_back();
        tin[v] = order.size(); order.push_back(v);
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; dep[u] = dep[v] + 1; st.push_back(u); }
    }
    for (int i = n - 1; i > 0; i--) sz[par[order[i]]] += sz[order[i]];
    return order;
}
```

```java
// CSR adjacency: neighbours of v are adj[start[v] .. start[v+1]); arrays sized n+1 (order sized n)
static void rootTree(int n, int[] start, int[] adj, int root, int[] par, int[] dep, int[] sz, int[] tin, int[] order) {
    int[] st = new int[n];
    int top = 0, cnt = 0;
    st[top++] = root; par[root] = 0; dep[root] = 0;
    while (top > 0) {
        int v = st[--top];
        tin[v] = cnt; order[cnt++] = v;
        for (int j = start[v]; j < start[v + 1]; j++) { int u = adj[j]; if (u != par[v]) { par[u] = v; dep[u] = dep[v] + 1; st[top++] = u; } }
    }
    Arrays.fill(sz, 1);
    for (int i = n - 1; i > 0; i--) sz[par[order[i]]] += sz[order[i]];
}
```

### 4.2 Binary lifting

```cpp
struct Lifting {
    int LOG; vector<vector<int>> up; vector<int> dep;
    Lifting(const vector<int>& par, const vector<int>& depth, int root) : dep(depth) {   // par[root] ignored
        int n = par.size() - 1;
        LOG = 1; while ((1 << LOG) <= n) LOG++;
        up.assign(LOG, vector<int>(n + 1, root));
        for (int v = 1; v <= n; v++) if (v != root) up[0][v] = par[v];
        for (int j = 1; j < LOG; j++) for (int v = 1; v <= n; v++) up[j][v] = up[j - 1][up[j - 1][v]];
    }
    int kth(int v, int k) const { if (k > dep[v]) return -1; for (int j = 0; k; j++, k >>= 1) if (k & 1) v = up[j][v]; return v; }
    int lca(int a, int b) const {
        if (dep[a] < dep[b]) swap(a, b);
        a = kth(a, dep[a] - dep[b]);
        if (a == b) return a;
        for (int j = LOG - 1; j >= 0; j--) if (up[j][a] != up[j][b]) { a = up[j][a]; b = up[j][b]; }
        return up[0][a];
    }
};
```

```java
static final class Lifting {
    final int LOG; final int[][] up; final int[] dep;
    Lifting(int n, int[] par, int[] depth, int root) {
        int L = 1; while ((1 << L) <= n) L++;
        LOG = L; dep = depth; up = new int[LOG][n + 1];
        for (int v = 0; v <= n; v++) up[0][v] = (v == root || v == 0) ? root : par[v];
        for (int j = 1; j < LOG; j++) for (int v = 0; v <= n; v++) up[j][v] = up[j - 1][up[j - 1][v]];
    }
    int kth(int v, int k) { if (k > dep[v]) return -1; for (int j = 0; k > 0; j++, k >>= 1) if ((k & 1) != 0) v = up[j][v]; return v; }
    int lca(int a, int b) {
        if (dep[a] < dep[b]) { int t = a; a = b; b = t; }
        a = kth(a, dep[a] - dep[b]);
        if (a == b) return a;
        for (int j = LOG - 1; j >= 0; j--) if (up[j][a] != up[j][b]) { a = up[j][a]; b = up[j][b]; }
        return up[0][a];
    }
}
```

Path max: keep `mx[j][v]` alongside `up`, `mx[j][v] = max(mx[j-1][v], mx[j-1][up[j-1][v]])`; in the query fold `mx` of every jump, and at the end both `mx[0][a]` and `mx[0][b]`.

### 4.3 $O(1)$ LCA on preorder indices

```cpp
struct FastLCA {                       // build from par/tin/order of a preorder (4.1)
    vector<int> order; vector<vector<int>> sp;
    FastLCA(const vector<int>& par, const vector<int>& tin, const vector<int>& ord) : order(ord) {
        int n = ord.size(), LOG = 1; while ((1 << LOG) <= n) LOG++;
        sp.assign(LOG, vector<int>(n, 0));
        for (int i = 1; i < n; i++) sp[0][i] = tin[par[ord[i]]];
        for (int j = 1; j < LOG; j++) for (int i = 0; i + (1 << j) <= n; i++) sp[j][i] = min(sp[j - 1][i], sp[j - 1][i + (1 << (j - 1))]);
    }
    int lcaT(int a, int b) const {     // tin indices in, tin index out
        if (a == b) return a;
        if (a > b) swap(a, b);
        a++; int j = __lg(b - a + 1);
        return min(sp[j][a], sp[j][b - (1 << j) + 1]);
    }
};
```

```java
static final class FastLCA {
    final int[][] sp;
    FastLCA(int n, int[] par, int[] tin, int[] order) {
        int LOG = 1; while ((1 << LOG) <= n) LOG++;
        sp = new int[LOG][n];
        for (int i = 1; i < n; i++) sp[0][i] = tin[par[order[i]]];
        for (int j = 1; j < LOG; j++) for (int i = 0; i + (1 << j) <= n; i++) sp[j][i] = Math.min(sp[j - 1][i], sp[j - 1][i + (1 << (j - 1))]);
    }
    int lcaT(int a, int b) {
        if (a == b) return a;
        if (a > b) { int t = a; a = b; b = t; }
        a++; int j = 31 - Integer.numberOfLeadingZeros(b - a + 1);
        return Math.min(sp[j][a], sp[j][b - (1 << j) + 1]);
    }
}
```

### 4.4 HLD (heavy-first preorder, path pieces)

```cpp
struct HLD {
    vector<int> par, dep, heavy, head, pos, sz;
    HLD(const vector<vector<int>>& adj, int root) {
        int n = adj.size() - 1;
        par.assign(n + 1, 0); dep.assign(n + 1, 0); heavy.assign(n + 1, 0); head.assign(n + 1, 0); pos.assign(n + 1, 0); sz.assign(n + 1, 1);
        vector<int> order, st = {root};
        while (!st.empty()) { int v = st.back(); st.pop_back(); order.push_back(v);
            for (int u : adj[v]) if (u != par[v]) { par[u] = v; dep[u] = dep[v] + 1; st.push_back(u); } }
        for (int i = n - 1; i > 0; i--) { int v = order[i], p = par[v]; sz[p] += sz[v]; if (!heavy[p] || sz[v] > sz[heavy[p]]) heavy[p] = v; }
        int cur = 0; st = {root}; head[root] = root;
        while (!st.empty()) { int v = st.back(); st.pop_back(); pos[v] = cur++;
            for (int u : adj[v]) if (u != par[v] && u != heavy[v]) { head[u] = u; st.push_back(u); }
            if (heavy[v]) { head[heavy[v]] = head[v]; st.push_back(heavy[v]); } }
    }
    template <class F> void forPath(int u, int v, F f, bool edges = false) {   // f(l, r) inclusive
        for (; head[u] != head[v]; u = par[head[u]]) { if (dep[head[u]] < dep[head[v]]) swap(u, v); f(pos[head[u]], pos[u]); }
        if (dep[u] > dep[v]) swap(u, v);
        if (pos[u] + edges <= pos[v]) f(pos[u] + edges, pos[v]);             // edges: skip the LCA
    }
};
```

```java
static final class HLD {
    final int[] par, dep, heavy, head, pos, sz;
    HLD(int n, int[] start, int[] adj, int root) {
        par = new int[n + 1]; dep = new int[n + 1]; heavy = new int[n + 1]; head = new int[n + 1]; pos = new int[n + 1]; sz = new int[n + 1];
        int[] order = new int[n], st = new int[n];
        int top = 0, cnt = 0;
        st[top++] = root;
        while (top > 0) { int v = st[--top]; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) { int u = adj[j]; if (u != par[v]) { par[u] = v; dep[u] = dep[v] + 1; st[top++] = u; } } }
        Arrays.fill(sz, 1);
        for (int i = n - 1; i > 0; i--) { int v = order[i], p = par[v]; sz[p] += sz[v]; if (heavy[p] == 0 || sz[v] > sz[heavy[p]]) heavy[p] = v; }
        int cur = 0; top = 0; st[top++] = root; head[root] = root;
        while (top > 0) { int v = st[--top]; pos[v] = cur++;
            for (int j = start[v]; j < start[v + 1]; j++) { int u = adj[j]; if (u != par[v] && u != heavy[v]) { head[u] = u; st[top++] = u; } }
            if (heavy[v] != 0) { head[heavy[v]] = head[v]; st[top++] = heavy[v]; } }
    }
    interface Range { void apply(int l, int r); }
    void forPath(int u, int v, Range f, boolean edges) {
        while (head[u] != head[v]) {
            if (dep[head[u]] < dep[head[v]]) { int t = u; u = v; v = t; }
            f.apply(pos[head[u]], pos[u]); u = par[head[u]];
        }
        if (dep[u] > dep[v]) { int t = u; u = v; v = t; }
        int l = pos[u] + (edges ? 1 : 0);
        if (l <= pos[v]) f.apply(l, pos[v]);
    }
}
```

### 4.5 Sack (no recursion): heavy-first preorder processed backwards

```cpp
// order = heavy-first preorder (HLD order), sz/heavy/par from 4.4; add(x) inserts vertex x; clearSubtree via the same range
template <class Add, class Answer, class Clear>
void sack(const vector<int>& order, const vector<int>& sz, const vector<int>& heavy, const vector<int>& par, int root, Add add, Answer answer, Clear clear) {
    int n = order.size();
    for (int i = n - 1; i >= 0; i--) {
        int v = order[i], h = heavy[v];
        add(v);
        for (int j = i + 1 + (h ? sz[h] : 0); j < i + sz[v]; j++) add(order[j]);   // light subtrees
        answer(v);                                                              // structure = subtree(v)
        if (v == root || heavy[par[v]] != v) { for (int j = i; j < i + sz[v]; j++) clear(order[j]); }
    }
}
```

```java
interface VertexOp { void at(int v); }
static void sack(int[] order, int[] sz, int[] heavy, int[] par, int root, VertexOp add, VertexOp answer, VertexOp clear) {
    int n = order.length;
    for (int i = n - 1; i >= 0; i--) {
        int v = order[i], h = heavy[v];
        add.at(v);
        for (int j = i + 1 + (h != 0 ? sz[h] : 0); j < i + sz[v]; j++) add.at(order[j]);
        answer.at(v);
        if (v == root || heavy[par[v]] != v) for (int j = i; j < i + sz[v]; j++) clear.at(order[j]);
    }
}
```

Small-to-large instead: reverse preorder; answer $v$; `if (S[v].size() > S[p].size()) swap(S[v], S[p]);` insert all of `S[v]` into `S[p]`; free `S[v]`.

### 4.6 Centroid decomposition skeleton (iterative)

```cpp
// calls process(c, level) once per centroid c (c already marked removed; its component = non-removed vertices reachable from c)
template <class P> void centroidDecomp(const vector<vector<int>>& adj, P process) {
    int n = adj.size() - 1;
    vector<char> removed(n + 1, 0); vector<int> par(n + 1), sz(n + 1), comp;
    vector<pair<int,int>> work = {{1, 0}};
    while (!work.empty()) {
        auto [r, lev] = work.back(); work.pop_back();
        comp.assign(1, r); par[r] = 0;
        for (size_t i = 0; i < comp.size(); i++) { int v = comp[i];
            for (int u : adj[v]) if (!removed[u] && u != par[v]) { par[u] = v; comp.push_back(u); } }
        int m = comp.size();
        for (int v : comp) sz[v] = 1;
        for (int i = m - 1; i > 0; i--) sz[par[comp[i]]] += sz[comp[i]];
        int c = r;
        for (bool moved = true; moved; ) { moved = false;
            for (int u : adj[c]) if (!removed[u] && u != par[c] && 2 * sz[u] > m) { c = u; moved = true; break; } }
        removed[c] = 1;
        process(c, lev);
        for (int u : adj[c]) if (!removed[u]) work.push_back({u, lev + 1});
    }
}
```

```java
interface CentroidOp { void process(int c, int level, boolean[] removed); }   // removed[c] is already true
static void centroidDecomp(int n, int[] start, int[] adj, CentroidOp op) {
    boolean[] removed = new boolean[n + 1];
    int[] par = new int[n + 1], sz = new int[n + 1], comp = new int[n], workV = new int[n], workL = new int[n];
    int wTop = 0;
    workV[wTop] = 1; workL[wTop++] = 0;
    while (wTop > 0) {
        int r = workV[--wTop], lev = workL[wTop], m = 0;
        comp[m++] = r; par[r] = 0;
        for (int i = 0; i < m; i++) { int v = comp[i];
            for (int j = start[v]; j < start[v + 1]; j++) { int u = adj[j]; if (!removed[u] && u != par[v]) { par[u] = v; comp[m++] = u; } } }
        for (int i = 0; i < m; i++) sz[comp[i]] = 1;
        for (int i = m - 1; i > 0; i--) sz[par[comp[i]]] += sz[comp[i]];
        int c = r;
        for (boolean moved = true; moved; ) { moved = false;
            for (int j = start[c]; j < start[c + 1]; j++) { int u = adj[j]; if (!removed[u] && u != par[c] && 2 * sz[u] > m) { c = u; moved = true; break; } } }
        removed[c] = true;
        op.process(c, lev, removed);
        for (int j = start[c]; j < start[c + 1]; j++) if (!removed[adj[j]]) { workV[wTop] = adj[j]; workL[wTop++] = lev + 1; }
    }
}
```

Per centroid: count with (a) inclusion–exclusion (all arms incl. length-0 arm of $c$ minus same-branch arms, measured from $c$), or (b) incremental (query previous branches, then insert). Exact-length counting with arrays: sort branches by depth. Centroid tree: store `cpar`, `clev`, `cd[level][v]`.

### 4.7 Virtual tree build (on tin indices)

```cpp
// keys: tin indices of key vertices (distinct); lcaT works on tin indices (e.g. FastLCA::lcaT of 4.3).
// Returns V' sorted by tin; fills vpar[y] for all but the first.
template <class L> vector<int> buildVirtual(vector<int> keys, L lcaT, vector<int>& vpar) {
    sort(keys.begin(), keys.end());
    int k = keys.size();
    for (int i = 0; i + 1 < k; i++) keys.push_back(lcaT(keys[i], keys[i + 1]));
    sort(keys.begin(), keys.end());
    keys.erase(unique(keys.begin(), keys.end()), keys.end());
    for (size_t i = 1; i < keys.size(); i++) vpar[keys[i]] = lcaT(keys[i - 1], keys[i]);
    return keys;                                  // scan backwards for children-before-parents DP
}
```

```java
// ys[0..k) holds tin indices of keys, capacity >= 2k; returns the size of V' (sorted, unique, in ys)
// lcaT works on tin indices, e.g. (a, b) -> F.lcaT(a, b) with FastLCA of 4.3
static int buildVirtual(int[] ys, int k, IntBinaryOperator lcaT, int[] vpar, Random rnd) {
    for (int i = k - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); int t = ys[i]; ys[i] = ys[j]; ys[j] = t; }
    Arrays.sort(ys, 0, k);
    int m = k;
    for (int i = 0; i + 1 < k; i++) ys[m++] = lcaT.applyAsInt(ys[i], ys[i + 1]);
    for (int i = m - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); int t = ys[i]; ys[i] = ys[j]; ys[j] = t; }
    Arrays.sort(ys, 0, m);
    int u = 0;
    for (int i = 0; i < m; i++) if (i == 0 || ys[i] != ys[i - 1]) ys[u++] = ys[i];
    for (int i = 1; i < u; i++) vpar[ys[i]] = lcaT.applyAsInt(ys[i - 1], ys[i]);
    return u;
}
```

## 5. Edge cases

| Case | What to check |
|---|---|
| $n = 1$ | no edges: arrays of size 0, diameter 0, centre = centroid = 1, sparse table with one element |
| path-shaped tree | recursion depth $n$ (Java!), lifting needs `LOG` with $2^{LOG} > n-1$ |
| star | one huge degree; centroid = centre; small-to-large and sack trivially fast |
| two centroids / two centres | output-format problems: which one is printed |
| $k > \mathrm{dep}(v)$ | $k$-th ancestor must return $-1$, not the root |
| edge-weighted path queries | exclude the LCA's position |
| $u = v$ queries | distance 0, path of one vertex, empty edge range |
| weights 0 or negative | two-BFS diameter wrong with negatives |
| 64-bit | subtree sums, distance sums, pair counts ($\binom n2$) |

## 6. Top 10 mistakes

1. Recursive DFS on $2\cdot10^5$ vertices in Java (stack overflow) — use iterative preorder.
2. `LOG = 17` hard-coded for $n = 2\cdot10^5$ (needs 18).
3. Root's ancestor stored as 0 with `up[*][0]` uninitialised.
4. In HLD, comparing `dep[u]` instead of `dep[head[u]]`.
5. Heavy child pushed first in the stack preorder (chains not contiguous).
6. Edge-valued HLD/lifting including the LCA's own edge position.
7. Mixing inclusive `tout` with exclusive `tin + sz`.
8. Small-to-large copying the big container instead of swapping.
9. Clearing size-$n$ arrays per query/centroid (quadratic) instead of only touched entries.
10. Forgetting the centroid's own length-0 arm, or measuring subtracted branch arms from the branch root.

## 7. Last-minute before the contest

- [ ] Iterative rooting template in both languages compiles from memory (4.1).
- [ ] Lifting: `kth`, `lca`, path max with both `mx[0][a]` and `mx[0][b]` at the end.
- [ ] Preorder RMQ LCA works on tin indices; `__lg` / `numberOfLeadingZeros` for the level.
- [ ] HLD: heavy pushed last; `forPath` swaps before jumping; `edges` flag skips the LCA.
- [ ] Sack loop: add $v$ + light range, answer, clear at path tops.
- [ ] Centroid walk uses `2 * sz[u] > m` with component-local parents.
- [ ] Virtual tree: sort, adjacent LCAs, sort+unique, `vpar = lca(prev, cur)`, scan backwards.
- [ ] Java: shuffle before `Arrays.sort(int[])` / `long[]`; `StringBuilder` + one `print`.
