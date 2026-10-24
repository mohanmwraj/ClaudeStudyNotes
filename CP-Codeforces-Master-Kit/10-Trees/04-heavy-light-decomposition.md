# Heavy–light decomposition (HLD)

> **Band:** 🟠 2100–2400 · **Priority:** ⚡ · **FAANG:** none · **Prerequisites:** [LCA and binary lifting](02-lca-and-binary-lifting.md), [segment tree](../08-Data-Structures/02-segment-tree-basics.md), [lazy propagation](../08-Data-Structures/03-lazy-propagation.md), [Fenwick tree](../08-Data-Structures/01-fenwick-tree.md), the light-edge lemma of [small-to-large](03-small-to-large-and-dsu-on-tree.md)
> **You can say you know this when:** you can write an iterative HLD that supports path and subtree queries/updates on one segment tree, handle edge-weighted variants and non-commutative path aggregates, and prove the $O(\log n)$ chain bound.

## 1. First principles — why this works

### 1.1 The gap HLD fills

Static path aggregates are handled by [binary lifting](02-lca-and-binary-lifting.md); subtree queries with updates by the [Euler tour](01-tree-basics-diameter-center-euler-tour.md). What neither handles is **paths with updates**: "set the value of vertex $s$; report the maximum on the path $a$–$b$", or "add $x$ to every vertex on the path $a$–$b$". A point update changes $\Theta(n)$ lifting entries; a path is not a range of the Euler tour.

If the tree *were* a path, a segment tree would do it. So: **cut the tree into vertex-disjoint vertical paths ("chains") and lay each chain out contiguously in one array.** A tree path then becomes a union of chain pieces — consecutive array ranges — and the question is only how many pieces a path can need. For an arbitrary decomposition that can be $\Theta(n)$ (a "caterpillar" cut badly). The heavy–light choice makes it $O(\log n)$.

### 1.2 Heavy and light edges

For each vertex $v$, its **heavy child** $h(v)$ is a child with the largest subtree; the edge $(v, h(v))$ is *heavy*, the others are *light*. Each vertex has at most one heavy edge going down and at most one going up, so heavy edges form vertex-disjoint vertical **chains** (every vertex belongs to exactly one chain; a leaf's chain may be just itself). The top vertex of $v$'s chain is $head(v)$.

**Lemma.** Any root-to-vertex path contains at most $\log_2 n$ light edges, hence meets at most $\log_2 n + 1$ chains; any $u$–$v$ path meets $O(\log n)$ chains.

*Proof.* On a light edge $(p, c)$, the heavy sibling has $sz \ge sz(c)$, so $sz(p) \ge 2\,sz(c) + 1$. Walking up from a vertex, every light edge more than doubles the subtree size, which never exceeds $n$. A $u$–$v$ path is two root paths glued at the LCA. $\blacksquare$

### 1.3 The layout: one preorder serves paths and subtrees

Number vertices by a DFS preorder that **visits the heavy child first**. Then:

- each chain occupies consecutive positions — $pos(h(v)) = pos(v) + 1$;
- each subtree still occupies $[pos(v), pos(v) + sz(v))$ — it is a preorder.

So one segment tree over positions answers both **path** and **subtree** operations. (This is the same "heavy-first preorder" as the non-recursive sack of file 03.)

### 1.4 Walking a path chain by chain

To process the path $u$–$v$: while $u$ and $v$ are on different chains, take the one whose chain head is **deeper**, say $u$; the piece $[pos(head(u)), pos(u)]$ is part of the path; jump $u \leftarrow parent(head(u))$. When both are on one chain, the last piece is between them, and the shallower of the two is the LCA.

*Why the deeper head is safe to consume.* Suppose $dep(head(u)) \ge dep(head(v))$ and $head(u) \ne head(v)$. If $head(u)$ were an ancestor of $v$, then $v$ leaves $u$'s chain at some vertex $w$ at or below $head(u)$ through a light edge, so $head(v)$ is strictly deeper than $w$, hence deeper than $head(u)$ — contradiction. So $head(u)$ is not an ancestor of $v$: the whole piece $head(u)..u$ lies strictly below the LCA, on $u$'s side of the path. Each jump crosses a light edge, so there are $O(\log n)$ iterations, each with one $O(\log n)$ segment-tree operation: $O(\log^2 n)$ per path operation (often much less in practice, since pieces are usually few).

### 1.5 Variants you must handle

- **Edge values.** Store the weight of edge $(parent(v), v)$ at $pos(v)$. A path then uses all its vertices' positions **except the LCA's**: on the final same-chain step, process $[pos(\text{shallower}) + 1, pos(\text{deeper})]$.
- **Non-commutative aggregates** (max-subarray, matrix products, "string" hashes along the path). Pieces from $u$'s side are traversed *upwards*, i.e. in decreasing position order; pieces from $v$'s side downwards. Keep two accumulators — `accU` extended on the right by `reverse(piece)`, `accV` extended on the left by `piece` — and return `accU ⊕ accV`.
- **Subtree operations** on the same structure: range $[pos(v), pos(v)+sz(v)-1]$.
- **LCA** for free: the loop above with no segment tree is an $O(\log n)$ LCA using $O(n)$ memory.

### 1.6 Iterative construction

Two passes, no recursion (important in Java): (1) a stack preorder for parents and depths, then reverse order for sizes and heavy children; (2) a stack preorder that pushes the heavy child **last** so that it is popped right after its parent, setting $head(h(v)) = head(v)$ and $head(c) = c$ for light children.

## 2. Formulas, definitions and identities

| Formula | Meaning |
|---|---|
| $h(v) = \arg\max_{c \text{ child}} sz(c)$ | heavy child |
| $(p, c)$ light $\Rightarrow sz(p) \ge 2 sz(c) + 1$ | heavy sibling at least as big |
| $\#\text{light edges on a root path} \le \lfloor \log_2 n \rfloor$ | §1.2 |
| $\#\text{chain pieces of a } u\text{–}v \text{ path} \le 2\lfloor\log_2 n\rfloor + 1$ | two root paths |
| $pos(h(v)) = pos(v) + 1$; subtree$(v) = [pos(v), pos(v) + sz(v))$ | heavy-first preorder |
| piece of the deeper head: $[pos(head(u)), pos(u)]$, then $u \leftarrow p(head(u))$ | §1.4 |
| edge path: last piece $[pos(a)+1, pos(b)]$ with $dep(a) \le dep(b)$ | edge stored at its child |
| non-commutative: $acc_U \leftarrow acc_U \oplus \mathrm{rev}(piece)$, $acc_V \leftarrow piece \oplus acc_V$, answer $acc_U \oplus acc_V$ | orientation along the path |

| Operation | Cost |
|---|---|
| build | $O(n)$ (+ segment tree build $O(n)$) |
| path query / update | $O(\log^2 n)$ ($O(\log n)$ pieces × $O(\log n)$) |
| subtree query / update | $O(\log n)$ |
| LCA | $O(\log n)$, $O(n)$ memory |

## 3. Implementation (C++ and Java)

### 3.1 HLD with a Fenwick tree: path sum, subtree sum, LCA

Input: `n q`, values $a_1..a_n$, edges; queries `1 s x` (set $a_s = x$), `2 u v` (sum on the path), `3 s` (sum of the subtree of $s$), `4 u v` (LCA). Root 1.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct HLD {
    int n;
    vector<int> par, dep, heavy, head, pos, sz;
    HLD(const vector<vector<int>>& adj, int root)
        : n(adj.size() - 1), par(n + 1, 0), dep(n + 1, 0), heavy(n + 1, 0), head(n + 1, 0), pos(n + 1, 0), sz(n + 1, 1) {
        vector<int> order, st = {root};
        while (!st.empty()) {
            int v = st.back(); st.pop_back(); order.push_back(v);
            for (int u : adj[v]) if (u != par[v]) { par[u] = v; dep[u] = dep[v] + 1; st.push_back(u); }
        }
        for (int i = n - 1; i > 0; i--) {
            int v = order[i], p = par[v];
            sz[p] += sz[v];
            if (!heavy[p] || sz[v] > sz[heavy[p]]) heavy[p] = v;
        }
        int cur = 0; st = {root}; head[root] = root;
        while (!st.empty()) {                     // heavy child pushed last -> popped next -> chains contiguous
            int v = st.back(); st.pop_back(); pos[v] = cur++;
            for (int u : adj[v]) if (u != par[v] && u != heavy[v]) { head[u] = u; st.push_back(u); }
            if (heavy[v]) { head[heavy[v]] = head[v]; st.push_back(heavy[v]); }
        }
    }
    template <class F> void forPath(int u, int v, F f) {   // f(l, r): inclusive position ranges
        for (; head[u] != head[v]; u = par[head[u]]) {
            if (dep[head[u]] < dep[head[v]]) swap(u, v);
            f(pos[head[u]], pos[u]);
        }
        if (dep[u] > dep[v]) swap(u, v);
        f(pos[u], pos[v]);
    }
    int lca(int u, int v) {
        for (; head[u] != head[v]; u = par[head[u]])
            if (dep[head[u]] < dep[head[v]]) swap(u, v);
        return dep[u] < dep[v] ? u : v;
    }
};

struct Fenwick {
    int n; vector<long long> t;
    Fenwick(int n) : n(n), t(n + 1, 0) {}
    void add(int i, long long d) { for (i++; i <= n; i += i & -i) t[i] += d; }
    long long pre(int i) { long long s = 0; for (i++; i > 0; i -= i & -i) s += t[i]; return s; }   // [0, i]
    long long sum(int l, int r) { return pre(r) - (l ? pre(l - 1) : 0); }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    vector<long long> a(n + 1);
    for (int v = 1; v <= n; v++) cin >> a[v];
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int x, y; cin >> x >> y; adj[x].push_back(y); adj[y].push_back(x); }
    HLD H(adj, 1);
    Fenwick F(n);
    for (int v = 1; v <= n; v++) F.add(H.pos[v], a[v]);
    while (q--) {
        int t; cin >> t;
        if (t == 1) { int s; long long x; cin >> s >> x; F.add(H.pos[s], x - a[s]); a[s] = x; }
        else if (t == 2) {
            int u, v; cin >> u >> v;
            long long res = 0;
            H.forPath(u, v, [&](int l, int r) { res += F.sum(l, r); });
            cout << res << '\n';
        } else if (t == 3) { int s; cin >> s; cout << F.sum(H.pos[s], H.pos[s] + H.sz[s] - 1) << '\n'; }
        else { int u, v; cin >> u >> v; cout << H.lca(u, v) << '\n'; }
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n;
    static int[] par, dep, heavy, head, pos, sz;
    static long[] fw;

    static void build(int[] start, int[] adj, int root) {
        par = new int[n + 1]; dep = new int[n + 1]; heavy = new int[n + 1]; head = new int[n + 1]; pos = new int[n + 1]; sz = new int[n + 1];
        int[] order = new int[n], st = new int[n];
        int top = 0, cnt = 0;
        st[top++] = root;
        while (top > 0) {
            int v = st[--top]; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) { int u = adj[j]; if (u != par[v]) { par[u] = v; dep[u] = dep[v] + 1; st[top++] = u; } }
        }
        Arrays.fill(sz, 1);
        for (int i = n - 1; i > 0; i--) {
            int v = order[i], p = par[v];
            sz[p] += sz[v];
            if (heavy[p] == 0 || sz[v] > sz[heavy[p]]) heavy[p] = v;
        }
        int cur = 0; top = 0;
        st[top++] = root; head[root] = root;
        while (top > 0) {
            int v = st[--top]; pos[v] = cur++;
            for (int j = start[v]; j < start[v + 1]; j++) { int u = adj[j]; if (u != par[v] && u != heavy[v]) { head[u] = u; st[top++] = u; } }
            if (heavy[v] != 0) { head[heavy[v]] = head[v]; st[top++] = heavy[v]; }
        }
    }

    static void add(int i, long d) { for (i++; i <= n; i += i & -i) fw[i] += d; }
    static long pre(int i) { long s = 0; for (i++; i > 0; i -= i & -i) s += fw[i]; return s; }
    static long sum(int l, int r) { return pre(r) - (l > 0 ? pre(l - 1) : 0); }

    static long pathSum(int u, int v) {
        long res = 0;
        while (head[u] != head[v]) {
            if (dep[head[u]] < dep[head[v]]) { int t = u; u = v; v = t; }
            res += sum(pos[head[u]], pos[u]);
            u = par[head[u]];
        }
        if (dep[u] > dep[v]) { int t = u; u = v; v = t; }
        return res + sum(pos[u], pos[v]);
    }

    static int lca(int u, int v) {
        while (head[u] != head[v]) {
            if (dep[head[u]] < dep[head[v]]) { int t = u; u = v; v = t; }
            u = par[head[u]];
        }
        return dep[u] < dep[v] ? u : v;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        n = in.nextInt();
        int q = in.nextInt();
        long[] a = new long[n + 1];
        for (int v = 1; v <= n; v++) a[v] = in.nextLong();
        int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        build(start, adj, 1);
        fw = new long[n + 1];
        for (int v = 1; v <= n; v++) add(pos[v], a[v]);
        StringBuilder sb = new StringBuilder();
        for (int k = 0; k < q; k++) {
            int t = in.nextInt();
            if (t == 1) { int s = in.nextInt(); long x = in.nextLong(); add(pos[s], x - a[s]); a[s] = x; }
            else if (t == 2) sb.append(pathSum(in.nextInt(), in.nextInt())).append('\n');
            else if (t == 3) { int s = in.nextInt(); sb.append(sum(pos[s], pos[s] + sz[s] - 1)).append('\n'); }
            else sb.append(lca(in.nextInt(), in.nextInt())).append('\n');
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

Test 1: tree $1$–$2$, $1$–$3$, $2$–$4$, $2$–$5$, $3$–$6$, $5$–$7$ with values $1..7$. Path $4$–$6$ is $4,2,1,3,6$: $4+2+1+3+6 = 16$. Path $7$–$4$: $7+5+2+4 = 18$. Subtree of 2: $2+4+5+7 = 18$. After $a_2 = 10$: path $4$–$6$ becomes 24 and subtree of 2 becomes 26.

<!-- test
in:
7 9
1 2 3 4 5 6 7
1 2
1 3
2 4
2 5
3 6
5 7
2 4 6
2 7 4
3 2
4 7 6
1 2 10
2 4 6
3 2
2 6 6
4 4 5
out:
16
18
18
1
24
26
6
2
-->
<!-- test
in:
1 3
5
2 1 1
3 1
4 1 1
out:
5
5
1
-->

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "update a vertex/edge, query sum/max/min on the path $u$–$v$" | HLD + segment tree (or Fenwick for sums) |
| "add $x$ / assign $x$ on every vertex of a path", then point or path queries | HLD + lazy segment tree |
| path operations **and** subtree operations in the same problem | HLD — its order serves both |
| a path aggregate that depends on direction (max subarray, matrix, hash of the string read along the path) | HLD with the two-accumulator trick |
| "for each edge, the number of paths / the minimum over paths covering it" (offline) | HLD range-chmin over pieces, or DSU tricks |
| static path max, no updates | binary lifting is simpler ([file 02](02-lca-and-binary-lifting.md)) |
| only root-to-vertex paths with sums | Euler tour + Fenwick is simpler ([file 01](01-tree-basics-diameter-center-euler-tour.md)) |
| link / cut edges online | not HLD — [link-cut tree](../16-IGM-Frontier/03-link-cut-trees.md) |

## 5. Worked examples (graded)

### Example 1 — Path Queries II · ★ ≈2100 (est.)

- **Source:** [CSES 2134 · Path Queries II](https://cses.fi/problemset/task/2134)
- **Difficulty:** ≈2100 (est.)
- **Problem:** $n, q \le 2\cdot10^5$; vertex values; queries: set the value of $s$; report the maximum value on the path $a$–$b$.
- **Thinking from first principles:** max is not invertible, so root prefix sums fail; with point updates, lifting fails. HLD reduces each path to $O(\log n)$ ranges of one array, and an iterative max segment tree answers each range. The CSES limits are tight for $O(q\log^2 n)$ in Java — keep the segment tree bottom-up and the I/O fast.

<details><summary>Solution</summary>

HLD as in §3.1, iterative max segment tree. $O(n + q\log^2 n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    vector<int> a(n + 1);
    for (int v = 1; v <= n; v++) cin >> a[v];
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int x, y; cin >> x >> y; adj[x].push_back(y); adj[y].push_back(x); }
    vector<int> par(n + 1, 0), dep(n + 1, 0), heavy(n + 1, 0), head(n + 1), pos(n + 1), sz(n + 1, 1), order, st = {1};
    while (!st.empty()) {
        int v = st.back(); st.pop_back(); order.push_back(v);
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; dep[u] = dep[v] + 1; st.push_back(u); }
    }
    for (int i = n - 1; i > 0; i--) { int v = order[i], p = par[v]; sz[p] += sz[v]; if (!heavy[p] || sz[v] > sz[heavy[p]]) heavy[p] = v; }
    int cur = 0; st = {1}; head[1] = 1;
    while (!st.empty()) {
        int v = st.back(); st.pop_back(); pos[v] = cur++;
        for (int u : adj[v]) if (u != par[v] && u != heavy[v]) { head[u] = u; st.push_back(u); }
        if (heavy[v]) { head[heavy[v]] = head[v]; st.push_back(heavy[v]); }
    }
    vector<int> seg(2 * n, 0);
    for (int v = 1; v <= n; v++) seg[n + pos[v]] = a[v];
    for (int i = n - 1; i > 0; i--) seg[i] = max(seg[2 * i], seg[2 * i + 1]);
    auto query = [&](int l, int r) {                         // max on [l, r]
        int res = INT_MIN;
        for (l += n, r += n + 1; l < r; l >>= 1, r >>= 1) {
            if (l & 1) res = max(res, seg[l++]);
            if (r & 1) res = max(res, seg[--r]);
        }
        return res;
    };
    string outs;
    while (q--) {
        int t; cin >> t;
        if (t == 1) {
            int s, x; cin >> s >> x;
            int i = n + pos[s]; seg[i] = x;
            for (i >>= 1; i > 0; i >>= 1) seg[i] = max(seg[2 * i], seg[2 * i + 1]);
        } else {
            int u, v; cin >> u >> v;
            int res = INT_MIN;
            for (; head[u] != head[v]; u = par[head[u]]) {
                if (dep[head[u]] < dep[head[v]]) swap(u, v);
                res = max(res, query(pos[head[u]], pos[u]));
            }
            if (dep[u] > dep[v]) swap(u, v);
            res = max(res, query(pos[u], pos[v]));
            outs += to_string(res); outs += '\n';
        }
    }
    cout << outs;
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n;
    static int[] seg;

    static int query(int l, int r) {
        int res = Integer.MIN_VALUE;
        for (l += n, r += n + 1; l < r; l >>= 1, r >>= 1) {
            if ((l & 1) != 0) res = Math.max(res, seg[l++]);
            if ((r & 1) != 0) res = Math.max(res, seg[--r]);
        }
        return res;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        n = in.nextInt();
        int q = in.nextInt();
        int[] a = new int[n + 1];
        for (int v = 1; v <= n; v++) a[v] = in.nextInt();
        int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        int[] par = new int[n + 1], dep = new int[n + 1], heavy = new int[n + 1], head = new int[n + 1], pos = new int[n + 1], sz = new int[n + 1];
        int[] order = new int[n], st = new int[n];
        int top = 0, cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top]; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) { int u = adj[j]; if (u != par[v]) { par[u] = v; dep[u] = dep[v] + 1; st[top++] = u; } }
        }
        Arrays.fill(sz, 1);
        for (int i = n - 1; i > 0; i--) { int v = order[i], p = par[v]; sz[p] += sz[v]; if (heavy[p] == 0 || sz[v] > sz[heavy[p]]) heavy[p] = v; }
        int cur = 0; top = 0;
        st[top++] = 1; head[1] = 1;
        while (top > 0) {
            int v = st[--top]; pos[v] = cur++;
            for (int j = start[v]; j < start[v + 1]; j++) { int u = adj[j]; if (u != par[v] && u != heavy[v]) { head[u] = u; st[top++] = u; } }
            if (heavy[v] != 0) { head[heavy[v]] = head[v]; st[top++] = heavy[v]; }
        }
        seg = new int[2 * n];
        for (int v = 1; v <= n; v++) seg[n + pos[v]] = a[v];
        for (int i = n - 1; i > 0; i--) seg[i] = Math.max(seg[2 * i], seg[2 * i + 1]);
        StringBuilder sb = new StringBuilder();
        for (int k = 0; k < q; k++) {
            int t = in.nextInt();
            if (t == 1) {
                int s = in.nextInt(), x = in.nextInt();
                int i = n + pos[s]; seg[i] = x;
                for (i >>= 1; i > 0; i >>= 1) seg[i] = Math.max(seg[2 * i], seg[2 * i + 1]);
            } else {
                int u = in.nextInt(), v = in.nextInt(), res = Integer.MIN_VALUE;
                while (head[u] != head[v]) {
                    if (dep[head[u]] < dep[head[v]]) { int tt = u; u = v; v = tt; }
                    res = Math.max(res, query(pos[head[u]], pos[u]));
                    u = par[head[u]];
                }
                if (dep[u] > dep[v]) { int tt = u; u = v; v = tt; }
                res = Math.max(res, query(pos[u], pos[v]));
                sb.append(res).append('\n');
            }
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
5 4
2 4 1 3 3
1 2
1 3
2 4
2 5
2 3 5
1 2 2
2 3 5
2 4 4
out:
4
3
3
-->
<!-- test
in:
1 2
7
2 1 1
2 1 1
out:
7
7
-->

</details>

### Example 2 — Beard Graph · ★ 2100

- **Source:** [CF 165D · Beard Graph](https://codeforces.com/problemset/problem/165/D) — 2100
- **Difficulty:** 2100
- **Problem:** a tree with $n \le 10^5$ vertices (in the original, a "beard": all vertices but one have degree $\le 2$ — the solution below does not need that). Edges are black initially. Queries: paint edge $i$ black; paint edge $i$ white; for $a, b$ print the number of edges on the path if all are black, else $-1$.
- **Thinking from first principles:** "all edges black" = "the number of white edges on the path is 0" — a path **sum** of 0/1 edge values with point updates. Edge values live at the child endpoint; the path uses every position on it **except the LCA's**. Fenwick over HLD positions; the distance comes from depths.

<details><summary>Solution</summary>

$O((n + m)\log^2 n)$. (The beard structure allows a simpler per-branch solution, but HLD is uniform.)

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<int> ea(n - 1), eb(n - 1);
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { cin >> ea[i] >> eb[i]; adj[ea[i]].push_back(eb[i]); adj[eb[i]].push_back(ea[i]); }
    vector<int> par(n + 1, 0), dep(n + 1, 0), heavy(n + 1, 0), head(n + 1), pos(n + 1), sz(n + 1, 1), order, st = {1};
    while (!st.empty()) {
        int v = st.back(); st.pop_back(); order.push_back(v);
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; dep[u] = dep[v] + 1; st.push_back(u); }
    }
    for (int i = n - 1; i > 0; i--) { int v = order[i], p = par[v]; sz[p] += sz[v]; if (!heavy[p] || sz[v] > sz[heavy[p]]) heavy[p] = v; }
    int cur = 0; st = {1}; head[1] = 1;
    while (!st.empty()) {
        int v = st.back(); st.pop_back(); pos[v] = cur++;
        for (int u : adj[v]) if (u != par[v] && u != heavy[v]) { head[u] = u; st.push_back(u); }
        if (heavy[v]) { head[heavy[v]] = head[v]; st.push_back(heavy[v]); }
    }
    vector<int> fw(n + 1, 0), white(n - 1, 0);
    auto add = [&](int i, int d) { for (i++; i <= n; i += i & -i) fw[i] += d; };
    auto pre = [&](int i) { int s = 0; for (i++; i > 0; i -= i & -i) s += fw[i]; return s; };   // [0, i], i >= -1
    auto childOf = [&](int e) { return dep[ea[e]] > dep[eb[e]] ? ea[e] : eb[e]; };
    int m; cin >> m;
    while (m--) {
        int t; cin >> t;
        if (t == 1 || t == 2) {
            int e; cin >> e; e--;
            int want = t == 2;
            if (white[e] != want) { add(pos[childOf(e)], want ? 1 : -1); white[e] = want; }
        } else {
            int a, b; cin >> a >> b;
            int u = a, v = b, whites = 0;
            for (; head[u] != head[v]; u = par[head[u]]) {
                if (dep[head[u]] < dep[head[v]]) swap(u, v);
                whites += pre(pos[u]) - pre(pos[head[u]] - 1);
            }
            if (dep[u] > dep[v]) swap(u, v);                 // u is the LCA: skip its own position
            whites += pre(pos[v]) - pre(pos[u]);
            cout << (whites ? -1 : dep[a] + dep[b] - 2 * dep[u]) << '\n';
        }
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n;
    static int[] fw;
    static void add(int i, int d) { for (i++; i <= n; i += i & -i) fw[i] += d; }
    static int pre(int i) { int s = 0; for (i++; i > 0; i -= i & -i) s += fw[i]; return s; }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        n = in.nextInt();
        int[] ea = new int[n - 1], eb = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { ea[i] = in.nextInt(); eb[i] = in.nextInt(); start[ea[i] + 1]++; start[eb[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[ea[i]]++] = eb[i]; adj[fill[eb[i]]++] = ea[i]; }
        int[] par = new int[n + 1], dep = new int[n + 1], heavy = new int[n + 1], head = new int[n + 1], pos = new int[n + 1], sz = new int[n + 1];
        int[] order = new int[n], st = new int[n];
        int top = 0, cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top]; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) { int u = adj[j]; if (u != par[v]) { par[u] = v; dep[u] = dep[v] + 1; st[top++] = u; } }
        }
        Arrays.fill(sz, 1);
        for (int i = n - 1; i > 0; i--) { int v = order[i], p = par[v]; sz[p] += sz[v]; if (heavy[p] == 0 || sz[v] > sz[heavy[p]]) heavy[p] = v; }
        int cur = 0; top = 0;
        st[top++] = 1; head[1] = 1;
        while (top > 0) {
            int v = st[--top]; pos[v] = cur++;
            for (int j = start[v]; j < start[v + 1]; j++) { int u = adj[j]; if (u != par[v] && u != heavy[v]) { head[u] = u; st[top++] = u; } }
            if (heavy[v] != 0) { head[heavy[v]] = head[v]; st[top++] = heavy[v]; }
        }
        fw = new int[n + 1];
        boolean[] white = new boolean[Math.max(1, n - 1)];
        int m = in.nextInt();
        StringBuilder sb = new StringBuilder();
        for (int k = 0; k < m; k++) {
            int t = in.nextInt();
            if (t == 1 || t == 2) {
                int e = in.nextInt() - 1;
                boolean want = t == 2;
                if (white[e] != want) {
                    int child = dep[ea[e]] > dep[eb[e]] ? ea[e] : eb[e];
                    add(pos[child], want ? 1 : -1); white[e] = want;
                }
            } else {
                int a = in.nextInt(), b = in.nextInt(), u = a, v = b, whites = 0;
                while (head[u] != head[v]) {
                    if (dep[head[u]] < dep[head[v]]) { int tt = u; u = v; v = tt; }
                    whites += pre(pos[u]) - pre(pos[head[u]] - 1);
                    u = par[head[u]];
                }
                if (dep[u] > dep[v]) { int tt = u; u = v; v = tt; }
                whites += pre(pos[v]) - pre(pos[u]);
                sb.append(whites != 0 ? -1 : dep[a] + dep[b] - 2 * dep[u]).append('\n');
            }
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

`pre(-1)` returns 0 (the loop starts at index 0 and does nothing), which makes `pre(pos[u]) - pre(pos[head[u]] - 1)` valid for chains starting at position 0. Test 1: a "beard" — centre 1 with branches $1$–$2$–$3$ and $1$–$4$–$5$; edges numbered in input order.

<!-- test
in:
5
1 2
2 3
1 4
4 5
7
3 3 5
2 1
3 3 5
3 4 5
1 1
3 2 4
3 3 3
out:
4
-1
1
2
0
-->
<!-- test
in:
2
1 2
4
3 1 2
2 1
3 2 1
3 2 2
out:
1
-1
0
-->

</details>

### Example 3 — Water Tree · ★ 2100

- **Source:** [CF 343D · Water Tree](https://codeforces.com/problemset/problem/343/D) — 2100
- **Difficulty:** 2100
- **Problem:** rooted tree (root 1), $n, q \le 5\cdot10^5$; every vertex is empty initially. Operations: fill $v$ (all of subtree($v$) becomes full); empty $v$ ($v$ and all its ancestors become empty); ask whether $v$ is full.
- **Thinking from first principles:** the state of $x$ is decided by the **latest** operation that touched it. A fill at $v$ touches $x$ iff $x \in$ subtree($v$) — a range in HLD order; an empty at $v$ touches $x$ iff $x$ is on the root path of $v$ — $O(\log n)$ HLD ranges. So keep two "latest timestamp" structures: `fillT` (range assign by subtree) and `emptyT` (range assign by root path), and answer full iff `fillT(x) > emptyT(x)`. Timestamps only increase, so "assign time $t$ on a range" is "range chmax", and with point queries it needs **no lazy propagation**: put the tag on the $O(\log n)$ covering nodes and take the max over the leaf-to-root path when querying.

<details><summary>Solution</summary>

Two non-lazy segment trees of tags over HLD positions. Fill: one range. Empty: $O(\log n)$ ranges. Query: two root-path maxima. $O((n + q)\log^2 n)$ worst case, fast in practice. (The textbook alternative is a lazy "range assign" segment tree on the same order — also fine.)

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int x, y; cin >> x >> y; adj[x].push_back(y); adj[y].push_back(x); }
    vector<int> par(n + 1, 0), dep(n + 1, 0), heavy(n + 1, 0), head(n + 1), pos(n + 1), sz(n + 1, 1), order, st = {1};
    while (!st.empty()) {
        int v = st.back(); st.pop_back(); order.push_back(v);
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; dep[u] = dep[v] + 1; st.push_back(u); }
    }
    for (int i = n - 1; i > 0; i--) { int v = order[i], p = par[v]; sz[p] += sz[v]; if (!heavy[p] || sz[v] > sz[heavy[p]]) heavy[p] = v; }
    int cur = 0; st = {1}; head[1] = 1;
    while (!st.empty()) {
        int v = st.back(); st.pop_back(); pos[v] = cur++;
        for (int u : adj[v]) if (u != par[v] && u != heavy[v]) { head[u] = u; st.push_back(u); }
        if (heavy[v]) { head[heavy[v]] = head[v]; st.push_back(heavy[v]); }
    }
    vector<int> fillT(2 * n, 0), emptyT(2 * n, 0);
    auto tag = [&](vector<int>& t, int l, int r, int val) {         // t[node] = max(t[node], val) on cover of [l, r]
        for (l += n, r += n + 1; l < r; l >>= 1, r >>= 1) {
            if (l & 1) { t[l] = max(t[l], val); l++; }
            if (r & 1) { --r; t[r] = max(t[r], val); }
        }
    };
    auto point = [&](const vector<int>& t, int i) { int res = 0; for (i += n; i > 0; i >>= 1) res = max(res, t[i]); return res; };
    int q; cin >> q;
    string outs;
    for (int time = 1; time <= q; time++) {
        int c, v; cin >> c >> v;
        if (c == 1) tag(fillT, pos[v], pos[v] + sz[v] - 1, time);
        else if (c == 2) { for (int u = v; u; u = par[head[u]]) tag(emptyT, pos[head[u]], pos[u], time); }
        else { outs += point(fillT, pos[v]) > point(emptyT, pos[v]) ? '1' : '0'; outs += '\n'; }
    }
    cout << outs;
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n;
    static void tag(int[] t, int l, int r, int val) {
        for (l += n, r += n + 1; l < r; l >>= 1, r >>= 1) {
            if ((l & 1) != 0) { if (t[l] < val) t[l] = val; l++; }
            if ((r & 1) != 0) { --r; if (t[r] < val) t[r] = val; }
        }
    }
    static int point(int[] t, int i) { int res = 0; for (i += n; i > 0; i >>= 1) res = Math.max(res, t[i]); return res; }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        n = in.nextInt();
        int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        int[] par = new int[n + 1], dep = new int[n + 1], heavy = new int[n + 1], head = new int[n + 1], pos = new int[n + 1], sz = new int[n + 1];
        int[] order = new int[n], st = new int[n];
        int top = 0, cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top]; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) { int u = adj[j]; if (u != par[v]) { par[u] = v; dep[u] = dep[v] + 1; st[top++] = u; } }
        }
        Arrays.fill(sz, 1);
        for (int i = n - 1; i > 0; i--) { int v = order[i], p = par[v]; sz[p] += sz[v]; if (heavy[p] == 0 || sz[v] > sz[heavy[p]]) heavy[p] = v; }
        int cur = 0; top = 0;
        st[top++] = 1; head[1] = 1;
        while (top > 0) {
            int v = st[--top]; pos[v] = cur++;
            for (int j = start[v]; j < start[v + 1]; j++) { int u = adj[j]; if (u != par[v] && u != heavy[v]) { head[u] = u; st[top++] = u; } }
            if (heavy[v] != 0) { head[heavy[v]] = head[v]; st[top++] = heavy[v]; }
        }
        int[] fillT = new int[2 * n], emptyT = new int[2 * n];
        int q = in.nextInt();
        StringBuilder sb = new StringBuilder();
        for (int time = 1; time <= q; time++) {
            int c = in.nextInt(), v = in.nextInt();
            if (c == 1) tag(fillT, pos[v], pos[v] + sz[v] - 1, time);
            else if (c == 2) { for (int u = v; u != 0; u = par[head[u]]) tag(emptyT, pos[head[u]], pos[u], time); }
            else sb.append(point(fillT, pos[v]) > point(emptyT, pos[v]) ? '1' : '0').append('\n');
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

The root's chain head is 1 and `par[1] = 0`, so the root-path loop stops after the root's chain. Test 1: tree $1$–$2$, $1$–$3$, $2$–$4$, $2$–$5$. Fill 1 (everything full); empty 4 (empties 4, 2, 1); then 5 and 3 are still full, 2 is empty; fill 2; empty 3 (3 and 1); 4 is full again, 1 is empty.

<!-- test
in:
5
1 2
1 3
2 4
2 5
9
1 1
2 4
3 5
3 3
3 2
1 2
2 3
3 4
3 1
out:
1
1
0
1
0
-->
<!-- test
in:
1
3
3 1
1 1
3 1
out:
0
1
-->

</details>

### Example 4 — Omsk Metro (hard version) · ★ 2300

- **Source:** [CF 1843F2 · Omsk Metro (hard version)](https://codeforces.com/problemset/problem/1843/F2) — 2300
- **Difficulty:** 2300
- **Problem:** a tree grows from a single vertex 1 (weight $+1$) by events "add vertex $n+1$ as a child of $v$ with weight $x \in \{-1, +1\}$"; interleaved queries $(u, v, k)$ ask whether some contiguous (possibly empty) segment of the path $u \to v$ has weight sum exactly $k$. $t$ test cases, total events $\le 2\cdot10^5$.
- **Thinking from first principles:** two observations. (1) Adding a leaf never changes an existing path, so answer everything **offline** on the final tree. (2) With $\pm1$ weights, the sums of contiguous segments form a contiguous range of integers containing 0 (extend or shrink a segment by one vertex and the sum moves by 1). So the answer is YES iff $\min \le k \le \max$ over *all segments* of the path — the max-subarray and min-subarray sums. These are classical segment-tree aggregates (sum, best prefix, best suffix, best inside), and they are **not commutative**: we must respect the order of vertices along $u \to \mathrm{lca} \to v$. That is the two-accumulator HLD of §1.5.

<details><summary>Solution</summary>

Node $=(\Sigma, P^{+}, S^{+}, B^{+}, P^{-}, S^{-}, B^{-})$ (sum, max prefix/suffix/subarray, min prefix/suffix/subarray, empty allowed). $\mathrm{rev}$ swaps prefixes and suffixes. Pieces on $u$'s side are appended reversed. Static segment tree (no updates). $O(n + q\log^2 n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct Node { int sum, pmx, smx, bmx, pmn, smn, bmn; };
const Node ID = {0, 0, 0, 0, 0, 0, 0};
Node leaf(int w) { int a = max(0, w), b = min(0, w); return {w, a, a, a, b, b, b}; }
Node comb(const Node& L, const Node& R) {
    return {L.sum + R.sum,
            max(L.pmx, L.sum + R.pmx), max(R.smx, R.sum + L.smx), max({L.bmx, R.bmx, L.smx + R.pmx}),
            min(L.pmn, L.sum + R.pmn), min(R.smn, R.sum + L.smn), min({L.bmn, R.bmn, L.smn + R.pmn})};
}
Node rev(Node x) { swap(x.pmx, x.smx); swap(x.pmn, x.smn); return x; }

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    string outs;
    while (t--) {
        int ev; cin >> ev;
        vector<int> par = {0, 0}, w = {0, 1};
        vector<array<int, 3>> qs;
        for (int i = 0; i < ev; i++) {
            char op; cin >> op;
            if (op == '+') { int v, x; cin >> v >> x; par.push_back(v); w.push_back(x); }
            else { int u, v, k; cin >> u >> v >> k; qs.push_back({u, v, k}); }
        }
        int n = par.size() - 1;
        vector<vector<int>> ch(n + 1);
        for (int v = 2; v <= n; v++) ch[par[v]].push_back(v);
        vector<int> dep(n + 1, 0), heavy(n + 1, 0), head(n + 1), pos(n + 1), sz(n + 1, 1);
        for (int v = 2; v <= n; v++) dep[v] = dep[par[v]] + 1;    // parents have smaller labels
        for (int v = n; v >= 2; v--) { sz[par[v]] += sz[v]; if (!heavy[par[v]] || sz[v] > sz[heavy[par[v]]]) heavy[par[v]] = v; }
        int cur = 0; vector<int> st = {1}; head[1] = 1;
        while (!st.empty()) {
            int v = st.back(); st.pop_back(); pos[v] = cur++;
            for (int u : ch[v]) if (u != heavy[v]) { head[u] = u; st.push_back(u); }
            if (heavy[v]) { head[heavy[v]] = head[v]; st.push_back(heavy[v]); }
        }
        vector<Node> seg(2 * n, ID);
        for (int v = 1; v <= n; v++) seg[n + pos[v]] = leaf(w[v]);
        for (int i = n - 1; i > 0; i--) seg[i] = comb(seg[2 * i], seg[2 * i + 1]);
        auto query = [&](int l, int r) {                      // ordered product over positions [l, r]
            Node L = ID, R = ID;
            for (l += n, r += n + 1; l < r; l >>= 1, r >>= 1) {
                if (l & 1) L = comb(L, seg[l++]);
                if (r & 1) R = comb(seg[--r], R);
            }
            return comb(L, R);
        };
        for (auto [u, v, k] : qs) {
            Node accU = ID, accV = ID;                        // accU: from u upwards; accV: down to v
            while (head[u] != head[v]) {
                if (dep[head[u]] >= dep[head[v]]) { accU = comb(accU, rev(query(pos[head[u]], pos[u]))); u = par[head[u]]; }
                else { accV = comb(query(pos[head[v]], pos[v]), accV); v = par[head[v]]; }
            }
            if (dep[u] >= dep[v]) accU = comb(accU, rev(query(pos[v], pos[u])));
            else accV = comb(query(pos[u], pos[v]), accV);
            Node all = comb(accU, accV);
            outs += (all.bmn <= k && k <= all.bmx) ? "YES\n" : "NO\n";
        }
    }
    cout << outs;
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    // node layout in an int[7]: sum, pmx, smx, bmx, pmn, smn, bmn
    static int[] leaf(int w) { int a = Math.max(0, w), b = Math.min(0, w); return new int[]{w, a, a, a, b, b, b}; }
    static int[] comb(int[] L, int[] R) {
        return new int[]{L[0] + R[0],
            Math.max(L[1], L[0] + R[1]), Math.max(R[2], R[0] + L[2]), Math.max(Math.max(L[3], R[3]), L[2] + R[1]),
            Math.min(L[4], L[0] + R[4]), Math.min(R[5], R[0] + L[5]), Math.min(Math.min(L[6], R[6]), L[5] + R[4])};
    }
    static int[] rev(int[] x) { return new int[]{x[0], x[2], x[1], x[3], x[5], x[4], x[6]}; }
    static final int[] ID = new int[7];
    static int n;
    static int[][] seg;

    static int[] query(int l, int r) {
        int[] L = ID, R = ID;
        for (l += n, r += n + 1; l < r; l >>= 1, r >>= 1) {
            if ((l & 1) != 0) L = comb(L, seg[l++]);
            if ((r & 1) != 0) R = comb(seg[--r], R);
        }
        return comb(L, R);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = in.nextInt();
        StringBuilder sb = new StringBuilder();
        while (t-- > 0) {
            int ev = in.nextInt();
            int[] par = new int[ev + 2], w = new int[ev + 2], qu = new int[ev], qv = new int[ev], qk = new int[ev];
            int cntV = 1, cntQ = 0;
            w[1] = 1;
            for (int i = 0; i < ev; i++) {
                String op = in.next();
                if (op.charAt(0) == '+') { cntV++; par[cntV] = in.nextInt(); w[cntV] = in.nextInt(); }
                else { qu[cntQ] = in.nextInt(); qv[cntQ] = in.nextInt(); qk[cntQ++] = in.nextInt(); }
            }
            n = cntV;
            int[] start = new int[n + 2];
            for (int v = 2; v <= n; v++) start[par[v] + 1]++;
            for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
            int[] ch = new int[Math.max(1, n - 1)], fill = start.clone();
            for (int v = 2; v <= n; v++) ch[fill[par[v]]++] = v;
            int[] dep = new int[n + 1], heavy = new int[n + 1], head = new int[n + 1], pos = new int[n + 1], sz = new int[n + 1];
            for (int v = 2; v <= n; v++) dep[v] = dep[par[v]] + 1;
            Arrays.fill(sz, 1);
            for (int v = n; v >= 2; v--) { sz[par[v]] += sz[v]; if (heavy[par[v]] == 0 || sz[v] > sz[heavy[par[v]]]) heavy[par[v]] = v; }
            int[] st = new int[n];
            int top = 0, cur = 0;
            st[top++] = 1; head[1] = 1;
            while (top > 0) {
                int v = st[--top]; pos[v] = cur++;
                for (int j = start[v]; j < start[v + 1]; j++) if (ch[j] != heavy[v]) { head[ch[j]] = ch[j]; st[top++] = ch[j]; }
                if (heavy[v] != 0) { head[heavy[v]] = head[v]; st[top++] = heavy[v]; }
            }
            seg = new int[2 * n][];
            Arrays.fill(seg, ID);
            for (int v = 1; v <= n; v++) seg[n + pos[v]] = leaf(w[v]);
            for (int i = n - 1; i > 0; i--) seg[i] = comb(seg[2 * i], seg[2 * i + 1]);
            for (int z = 0; z < cntQ; z++) {
                int u = qu[z], v = qv[z], k = qk[z];
                int[] accU = ID, accV = ID;
                while (head[u] != head[v]) {
                    if (dep[head[u]] >= dep[head[v]]) { accU = comb(accU, rev(query(pos[head[u]], pos[u]))); u = par[head[u]]; }
                    else { accV = comb(query(pos[head[v]], pos[v]), accV); v = par[head[v]]; }
                }
                if (dep[u] >= dep[v]) accU = comb(accU, rev(query(pos[v], pos[u])));
                else accV = comb(query(pos[u], pos[v]), accV);
                int[] all = comb(accU, accV);
                sb.append(all[6] <= k && k <= all[3] ? "YES\n" : "NO\n");
            }
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

Test 1 tree: $2$ under 1 (weight $-1$), $3$ under 1 ($+1$), $4$ under 2 ($-1$), $5$ under 3 ($+1$). The path $4 \to 5$ reads $-1, -1, +1, +1, +1$, so segment sums cover exactly $[-2, 3]$; the single vertex 2 gives $[-1, 0]$. Dropping the `rev` on the $u$ side still passes these small cases — it was caught by the random stress test against a brute force, which is why you should always stress non-commutative HLD code.

<!-- test
in:
1
9
+ 1 -1
+ 1 1
+ 2 -1
+ 3 1
? 4 5 3
? 4 5 -2
? 4 5 -3
? 5 4 4
? 2 2 -1
out:
YES
YES
NO
NO
YES
-->
<!-- test
in:
2
3
? 1 1 1
? 1 1 0
? 1 1 -1
4
+ 1 1
+ 2 1
? 3 1 3
? 1 3 4
out:
YES
YES
NO
YES
NO
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Compare depths of the chain heads, not of the vertices**, when choosing which side to lift. Comparing `dep[u]` instead of `dep[head[u]]` is the most common HLD bug and it passes many small tests.
2. **Swap before jumping**: in `for (; head[u] != head[v]; u = par[head[u]])` the swap is in the body, the jump in the increment — keep that order.
3. **Edge-weighted paths exclude the LCA's position** (`pos[lca] + 1` on the last piece). When `u == v` on the last step the range is empty — guard it (`pre(pos[v]) - pre(pos[u])` is naturally 0).
4. **Heavy child must be the largest subtree.** Choosing the first child keeps correctness but loses the $O(\log n)$ piece bound.
5. **Heavy child is pushed last** in the stack preorder; pushing it first breaks chain contiguity ($pos(h(v)) \ne pos(v)+1$).
6. **Non-commutative aggregates**: the $u$-side pieces are reversed; use separate left/right accumulators inside the segment-tree query too (`L = L ⊕ seg[l++]`, `R = seg[--r] ⊕ R`).
7. **Prefer HLD + Fenwick for sums** — 3–5× faster than a segment tree in Java.
8. **Monotone timestamps turn "assign" into "chmax"**: range assign with point queries then needs no lazy propagation (Example 3).
9. **Java allocation in hot loops** (Example 4 allocates small arrays per combine) is acceptable for $2\cdot10^5$ queries × $O(\log^2 n)$ combines, but for $10^6$ operations use flat `int[]` storage with indices.
10. **Recursion**: the classical HLD uses two recursive DFS passes; in Java on a path of $5\cdot10^5$ vertices that overflows. Use the iterative build.

## 7. Going further (toward 2400–2600+)

- **HLD for LCA queries with $O(n)$ memory** and a tiny constant — often the fastest practical LCA.
- **Interactive search with HLD**: descend along heavy paths, using "distance" queries to find the light branch — [CF 1174F · Ehab and the Big Finale](https://codeforces.com/problemset/problem/1174/F) — 2400.
- **Rerooting with HLD**: subtree queries relative to a moving root via case analysis on whether the root lies inside the subtree — [CF 916E · Jamie and Tree](https://codeforces.com/problemset/problem/916/E) — 2400.
- **Light-child contributions**: handle the heavy child lazily and push light children explicitly; each update touches $O(\log n)$ light edges — [CF 1254D · Tree Queries](https://codeforces.com/problemset/problem/1254/D) — 2700.
- **Direction-dependent string hashing / binary patterns along paths**: [CF 536E · Tavas on the Path](https://codeforces.com/problemset/problem/536/E) — 3100.
- **Path updates of the form "$x \to \lfloor x / y \rfloor$"** with early termination: [CF 593D · Happy Tree Party](https://codeforces.com/problemset/problem/593/D) — 2400.
- **Dynamic trees** where edges are linked and cut: [link-cut trees](../16-IGM-Frontier/03-link-cut-trees.md) generalise HLD with splay trees ("preferred paths").
- Revision: [cheat sheet](../99-Cheat-Sheets/10-trees-cheatsheet.md).

## 8. Practice ladder

**1900–2100**
- [ ] [CSES 1138 · Path Queries](https://cses.fi/problemset/task/1138) — redo it with HLD to check your template
- [ ] [CSES 2134 · Path Queries II](https://cses.fi/problemset/task/2134)
- [ ] [CF 165D · Beard Graph](https://codeforces.com/problemset/problem/165/D) — 2100
- [ ] [CF 343D · Water Tree](https://codeforces.com/problemset/problem/343/D) — 2100

**2100–2400**
- [ ] [CF 1843F2 · Omsk Metro (hard version)](https://codeforces.com/problemset/problem/1843/F2) — 2300
- [ ] [CF 1174F · Ehab and the Big Finale](https://codeforces.com/problemset/problem/1174/F) — 2400
- [ ] [CF 916E · Jamie and Tree](https://codeforces.com/problemset/problem/916/E) — 2400
- [ ] [CF 593D · Happy Tree Party](https://codeforces.com/problemset/problem/593/D) — 2400

**2400+**
- [ ] [CF 1023F · Mobile Phone Network](https://codeforces.com/problemset/problem/1023/F) — 2600
- [ ] [CF 1254D · Tree Queries](https://codeforces.com/problemset/problem/1254/D) — 2700
- [ ] [CF 1749F · Distance to the Path](https://codeforces.com/problemset/problem/1749/F) — 2800
- [ ] [CF 536E · Tavas on the Path](https://codeforces.com/problemset/problem/536/E) — 3100

## 9. LeetCode / FAANG cross-reference

Rare in interviews: HLD is a contest-only structure (long to code, no natural "system design" counterpart). Interview problems with path queries are static and solved with LCA:

- [LC 2846 · Minimum Edge Weight Equilibrium Queries in a Tree](https://leetcode.com/problems/minimum-edge-weight-equilibrium-queries-in-a-tree/) — Hard — static path counts; LCA + root prefix counts suffice, HLD is overkill.
- [LC 2538 · Difference Between Maximum and Minimum Price Sum](https://leetcode.com/problems/difference-between-maximum-and-minimum-price-sum/) — Hard — path-sum maximisation by rerooting, the kind of problem where people reach for HLD unnecessarily.

## 10. Self-check

1. Prove that a root path contains at most $\log_2 n$ light edges.
2. Why does the heavy-first preorder keep subtrees contiguous *and* chains contiguous?
3. In the path loop, why must you lift the vertex whose **chain head** is deeper?
4. How do you adapt a vertex-valued HLD to edge values? What exactly changes in the last step?
5. Write the combine and reverse for "max subarray sum along a path".
6. Path assign + path sum: what segment tree do you need, and what is the complexity per operation?
7. When is binary lifting strictly better than HLD, and when is the Euler tour enough?

<details><summary>Answers</summary>

1. On a light edge $(p,c)$ the heavy sibling has size $\ge sz(c)$, so $sz(p) > 2 sz(c)$. Sizes more than double per light edge going up and are bounded by $n$.
2. It is a genuine preorder (stack DFS), so every subtree is a contiguous block; and the heavy child is popped immediately after its parent, so $pos(h(v)) = pos(v)+1$ and chains are runs.
3. If the deeper head $head(u)$ were an ancestor of $v$, $v$'s chain head would be strictly deeper — contradiction. So the piece $head(u)..u$ lies entirely below the LCA on $u$'s side. Lifting by vertex depth can consume a piece containing the LCA and jump above it.
4. Store edge $(p(v),v)$ at $pos(v)$. Everything is the same except the final same-chain piece: use $[pos(\text{shallower}) + 1, pos(\text{deeper})]$, skipping the LCA's position.
5. Node = (sum, best prefix, best suffix, best). $comb(L,R) = (L.s+R.s,\ \max(L.p, L.s+R.p),\ \max(R.x, R.s + L.x),\ \max(L.b, R.b, L.x + R.p))$ where $x$ = suffix; $rev$ swaps prefix and suffix.
6. Lazy segment tree with "assign" tags and sums (handle the tag composition: a new assign overrides everything). $O(\log^2 n)$ per path operation.
7. Lifting: static trees with $k$-th ancestor / binary-search-on-ancestors needs, or when an $O(\log n)$ query without a segment tree is enough. Euler tour: subtree operations, or root-to-vertex path sums with point updates (invertible aggregates). HLD is needed for general path updates or non-invertible path aggregates with updates.

</details>
