# Tree basics: rooting, traversal orders, diameter, centre, centroid, Euler tour

> **Band:** 🟢 1200 – 🔵 1900 (isomorphism and Prüfer 🟠) · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [BFS / DFS](../09-Graphs/01-graph-representation-bfs-dfs.md), [Fenwick tree](../08-Data-Structures/01-fenwick-tree.md), [prefix sums and difference arrays](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md)
> **You can say you know this when:** you can root a $2\cdot10^5$-vertex tree without recursion in both languages, prove the two-BFS diameter algorithm, and turn any "subtree" or "root-to-vertex path" query into a Fenwick query on the Euler-tour array in under five minutes.

## 1. First principles — why this works

### 1.1 What a tree is, and the facts every solution silently uses

For a graph with $n$ vertices the following are equivalent; each one is a definition of a *tree*:

1. connected and acyclic;
2. connected with exactly $n-1$ edges;
3. acyclic with exactly $n-1$ edges;
4. between any two vertices there is **exactly one** simple path;
5. connected, and removing any edge disconnects it (minimally connected);
6. acyclic, and adding any edge creates exactly one cycle (maximally acyclic).

*Proof sketch of the core.* Start with $n$ isolated vertices ($n$ components) and add edges one at a time. An edge either joins two components (components $-1$) or closes a cycle (components unchanged). Connected means ending with one component, which needs at least $n-1$ joining edges; acyclic means *every* edge was joining. So "acyclic and connected" forces exactly $n-1$ edges, and any two of {connected, acyclic, $n-1$ edges} imply the third. Uniqueness of paths: two different simple paths between $u$ and $v$ contain a cycle; conversely a cycle gives two paths between any two of its vertices.

Consequences you use constantly:

- **Unique paths** mean distances need no Dijkstra: one BFS/DFS from $s$ gives $d(s,\cdot)$ in $O(n)$ even with weights.
- **Every edge is a bridge**: removing edge $(p,v)$ splits the tree into "subtree of $v$" and "the rest". Almost every counting argument on trees is "count over edges, multiply the two sides" (e.g. $\sum_{u<v} d(u,v) = \sum_e w_e\, s_e (n-s_e)$).
- A tree with $n \ge 2$ has at least two leaves (the two ends of a longest path are leaves).
- $\sum_v \deg v = 2(n-1)$, so the average degree is below 2.

### 1.2 Rooting: the one order you need

Most tree algorithms want a **root** $r$ and, for every vertex, its parent $p(v)$, depth $d(v)$ and subtree size $sz(v)$. The naive way is recursive DFS. The key observation is that recursion is not needed — all you need is **an order in which every parent comes before its children**. Given such an order:

- top-down quantities (depth, root-to-$v$ sums, parent pointers) are computed by scanning it forwards;
- bottom-up quantities (subtree size, subtree sums, tree DP) are computed by scanning it **backwards**, pushing each vertex's value into its parent.

Both BFS order and an iterative stack-DFS order have this property. The stack-DFS order has one more property, which is what makes the Euler tour work:

**Stack preorder.** Push the root. Repeatedly pop $v$, give it the next timestamp, push all its unvisited neighbours. When a child $c$ is popped, everything pushed after it (its descendants) is popped before anything below it on the stack. So the vertices of $c$'s subtree receive **consecutive timestamps**. That is a genuine DFS preorder, just with children visited in reverse adjacency order.

**Why this matters in Java.** The default thread stack is far smaller than CF's 256 MB; a recursive DFS on a path of $2\cdot10^5$ vertices throws `StackOverflowError`. Two fixes: run `main` in `new Thread(null, task, "", 1 << 28)` (works, but you must remember it every time), or use iterative orders (always works, often faster). This kit uses iterative orders in Java and in C++ for the same reason the Windows default stack is tiny when you test locally.

### 1.3 Diameter: why two BFS passes are enough

The **diameter** is the longest path. Naively, a BFS from every vertex is $O(n^2)$. The waste: almost all of those BFS runs are pointless because of the following lemma.

**Lemma (eccentricity through a diameter).** Edge weights $\ge 0$. Let $(u,v)$ be any diameter. Then for every vertex $s$, the farthest distance from $s$ is $\mathrm{ecc}(s) = \max(d(s,u), d(s,v))$.

*Proof.* Let $P$ be the $u$–$v$ path and $y$ the vertex of $P$ where the path from $s$ meets $P$ (its projection). Take any vertex $w$ with projection $z$ on $P$.

- If $z \ne y$, say $z$ lies between $y$ and $v$: the path $s \to w$ is $s \to y \to z \to w$. Also $d(z,w) \le d(z,v)$, otherwise $u \to z \to w$ would be longer than the diameter. Hence $d(s,w) \le d(s,y)+d(y,z)+d(z,v) = d(s,v)$.
- If $z = y$: $d(y,w) \le d(y,v)$ by the same argument, and $d(s,w) \le d(s,y) + d(y,w)$ (tree triangle inequality, which needs $w \ge 0$), so again $d(s,w) \le d(s,v)$. $\blacksquare$

**Corollary.** A vertex $a$ farthest from an arbitrary $s$ is an endpoint of some diameter (chase the equality cases in the proof: $d(s,a) = \max(d(s,u),d(s,v))$ forces $d(a,u) = D$ or $d(a,v) = D$). So: BFS from any vertex to find $a$, BFS from $a$ to find $b$; $d(a,b)$ is the diameter, and the lemma gives every vertex's eccentricity from the two distance arrays — three passes, $O(n)$.

**The DP view (also works with negative weights).** Root the tree. Every path has a unique highest vertex $t$; the path goes down from $t$ into at most two different child subtrees. Let $h(v) = \max(0, \max_c (h(c) + w(v,c)))$ be the longest downward path from $v$. Then

$$D = \max_t \big(\text{largest} + \text{second largest of } \{h(c)+w(t,c)\}\cup\{0,0\}\big).$$

Two-pass BFS is **wrong with negative weights** (the triangle step in the proof fails); the DP is not. The DP pattern — "best path whose top is $t$" — is the prototype for [tree DP](../06-Dynamic-Programming/08-tree-dp-and-rerooting.md).

### 1.4 Centre and centroid — two different "middles"

- **Centre**: vertex minimising eccentricity. By the lemma, $\mathrm{ecc}(s) = \max(d(s,u), d(s,v))$, minimised on the diameter path at its middle. For unweighted trees: if $D$ is even there is one centre (radius $D/2$), if odd there are two adjacent centres (radius $\lceil D/2\rceil$). Every diameter passes through the centre(s). Algorithmically: **peel leaves** layer by layer; the last one or two vertices are the centres. This is the canonical root for unrooted-tree isomorphism (§1.6).
- **Centroid**: vertex whose removal leaves components of size $\le n/2$. *Existence*: start anywhere; if some component has size $> n/2$, step into it. You never step back (the component behind you now has size $< n/2$), and the size of the big component strictly decreases, so the walk stops at a centroid. There are at most two, and two centroids are adjacent with $n/2$ vertices on each side. The centroid also minimises $\sum_u d(v,u)$: moving from $v$ to neighbour $x$ changes the sum by $w\,(n - 2 s_x)$, where $s_x$ is the size of $x$'s side, which is negative exactly when $s_x > n/2$. Centroids drive [centroid decomposition](05-centroid-decomposition.md).

### 1.5 Euler tour: turning subtrees into array ranges

Give each vertex its preorder timestamp $tin(v)$ and let $tout(v) = tin(v) + sz(v) - 1$. Because subtree vertices are consecutive in preorder:

$$\text{subtree}(v) = \{\, x : tin(v) \le tin(x) \le tout(v) \,\}, \qquad u \text{ is an ancestor of } v \iff tin(u) \le tin(v) \le tout(u).$$

Write the vertex values into an array at positions $tin$. Then

- **subtree sum / min / update** = range query on $[tin(v), tout(v)]$ → [Fenwick](../08-Data-Structures/01-fenwick-tree.md) or [segment tree](../08-Data-Structures/02-segment-tree-basics.md);
- **root-to-$v$ path sums with point updates**: let $S(v) = \sum_{x \text{ ancestor of } v} a_x$. Changing $a_x$ by $\delta$ changes $S$ by $\delta$ for exactly the vertices of subtree($x$) — a **range add** on $[tin(x), tout(x)]$; reading $S(v)$ is a **point query** at $tin(v)$. With a difference-array Fenwick both are $O(\log n)$;
- **any path sum**: $\mathrm{sum}(u,v) = S(u)+S(v)-2S(\ell)+a_\ell$ with $\ell = \mathrm{lca}(u,v)$ (see [LCA](02-lca-and-binary-lifting.md)). For non-invertible aggregates (max) on paths you need [binary lifting](02-lca-and-binary-lifting.md) or [HLD](04-heavy-light-decomposition.md).

Some sources call a different sequence the Euler tour: the $2n-1$ vertex sequence written every time DFS *enters or returns to* a vertex. That one is used for $O(1)$ LCA by RMQ (file 02). Keep both in mind; the preorder version is the one for subtree queries.

### 1.6 Tree isomorphism (🟠)

Two **rooted** trees are isomorphic iff their roots' multisets of child subtrees are pairwise isomorphic. So give every rooted subtree a **canonical id**: process vertices bottom-up, form the *sorted* list of child ids, and map that list to an integer through a dictionary shared by both trees (a new list gets the next unused id). Equal ids ⇔ isomorphic subtrees, by induction on height. Total list length is $n-1$, so it costs $O(n \log n)$ with sorting and a balanced map. This is the AHU (Aho–Hopcroft–Ullman) idea.

**Unrooted** trees: an isomorphism maps centres to centres, so root each tree at its centre(s) — one or two candidates — and compare rooted ids. (Rooting at the centroid works equally well.)

**Hashing alternative.** Replace the dictionary by a hash such as $h(v) = \prod_{c}(R_{\mathrm{depth}} + h(c)) \bmod p$ with random $R$'s, or $h(v) = 1 + \sum_c f(h(c))$ with a random-looking $f$ (splitmix64). Faster to write and $O(n)$, but probabilistic: never use a fixed, guessable base on Codeforces (see [hashing](../11-Strings/01-string-hashing.md)).

### 1.7 Prüfer code and Cayley's formula (🟠)

Repeatedly delete the **smallest-numbered leaf** and write down its neighbour, until two vertices remain. A labelled tree on $\{1..n\}$ becomes a sequence of length $n-2$ over $\{1..n\}$, and the map is a **bijection**: in the sequence, every vertex appears exactly $\deg(v)-1$ times (it is written once per deleted neighbour, except for the last edge), so the leaves at each step are exactly the vertices not appearing in the rest of the sequence — which lets you decode uniquely. Hence

$$\#\{\text{labelled trees on } n \text{ vertices}\} = n^{n-2} \quad \text{(Cayley)}.$$

Linear-time encode/decode uses one pointer to the smallest leaf: after deleting a leaf, its neighbour becomes a leaf; if that new leaf is smaller than the pointer it is the next one to delete, otherwise advance the pointer. Each vertex is passed by the pointer once.

## 2. Formulas, definitions and identities

| Formula | Meaning / proof sketch |
|---|---|
| $\lvert E\rvert = n-1$, $\sum_v \deg v = 2n-2$ | §1.1; handshake lemma |
| $\#\text{leaves} = 2 + \sum_{v} \max(0, \deg v - 2)$ | from $\sum (\deg v - 2) = -2$ |
| $\sum_v sz(v) = \sum_v (d(v)+1)$ | each vertex is counted once for every ancestor including itself |
| $\sum_{u<v} d(u,v) = \sum_{e=(p,c)} w_e\, sz(c)\,(n - sz(c))$ | each pair uses edge $e$ iff they are on different sides |
| $\mathrm{ecc}(s) = \max(d(s,a), d(s,b))$ for a diameter $(a,b)$ | §1.3 lemma, weights $\ge 0$ |
| $D = \max_t (h_1(t) + h_2(t))$ | DP over the top vertex; $h_1 \ge h_2$ best child branches, works with any weights |
| radius $= \lceil D/2 \rceil$ (unweighted); 1 centre if $D$ even, 2 if odd | centre is the middle of every diameter |
| centroid: $\max(n - sz(v), \max_c sz(c)) \le \lfloor n/2 \rfloor$ | at most 2, adjacent if 2 |
| centroid minimises $\sum_u d(v,u)$ | moving across an edge changes the sum by $w(n-2s)$ |
| $u$ ancestor of $v$ $\iff tin(u) \le tin(v) \le tout(u)$, $tout(u) = tin(u)+sz(u)-1$ | preorder makes subtrees contiguous |
| $\mathrm{sum}(u,v) = S(u)+S(v)-2S(\ell)+a_\ell$ | inclusion–exclusion on root paths, $S$ = root-to-vertex sum |
| $n^{n-2}$ labelled trees; $n^{n-1}$ rooted labelled trees | Cayley via Prüfer; choose the root |
| $\binom{n-2}{d_1-1,\dots,d_n-1} = \frac{(n-2)!}{\prod (d_i-1)!}$ trees with degrees $d_i$ | $v$ appears $d_v - 1$ times in the Prüfer code |
| $k\, n^{\,n-k-1}$ forests on $n$ labelled vertices with $k$ trees, $k$ given vertices in different trees | generalised Cayley |
| $a^{b-1} b^{a-1}$ spanning trees of $K_{a,b}$ | bipartite Prüfer-type argument (or the [matrix-tree theorem](../15-Advanced-Math/06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md)) |

**Complexities.** Rooting, sizes, depths, Euler tour, diameter, centres, centroids: $O(n)$ time and memory. Subtree query / update on the tour with Fenwick: $O(\log n)$. Rooted canonical ids: $O(n \log n)$. Prüfer encode/decode: $O(n)$.

## 3. Implementation (C++ and Java)

All programs read vertices as $1..n$. Java uses a CSR adjacency (`start[v] .. start[v+1]` in one `int[]`), which is both faster and lighter than `ArrayList<Integer>[]`.

### 3.1 Rooting without recursion: parent, depth, size, tin/tout, ancestor test

Input: `n q`, then $n-1$ edges, then $q$ queries `u v`. Output: parents (root 1 has parent 0), depths, subtree sizes, then for each query `1` if $u$ is an ancestor of $v$ (a vertex is its own ancestor), else `0`.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; adj[a].push_back(b); adj[b].push_back(a); }
    vector<int> par(n + 1, 0), dep(n + 1, 0), sz(n + 1, 1), tin(n + 1), order;
    order.reserve(n);
    vector<int> st = {1};
    while (!st.empty()) {                       // stack preorder: subtrees get consecutive tin
        int v = st.back(); st.pop_back();
        tin[v] = order.size(); order.push_back(v);
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; dep[u] = dep[v] + 1; st.push_back(u); }
    }
    for (int i = n - 1; i > 0; i--) sz[par[order[i]]] += sz[order[i]];   // children before parents
    auto isAnc = [&](int u, int v) { return tin[u] <= tin[v] && tin[v] < tin[u] + sz[u]; };
    for (int v = 1; v <= n; v++) cout << par[v] << (v == n ? '\n' : ' ');
    for (int v = 1; v <= n; v++) cout << dep[v] << (v == n ? '\n' : ' ');
    for (int v = 1; v <= n; v++) cout << sz[v] << (v == n ? '\n' : ' ');
    while (q--) { int u, v; cin >> u >> v; cout << (isAnc(u, v) ? 1 : 0) << '\n'; }
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
        int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        int[] par = new int[n + 1], dep = new int[n + 1], sz = new int[n + 1], tin = new int[n + 1], order = new int[n];
        int[] st = new int[n];
        int top = 0, cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top];
            tin[v] = cnt; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) {
                int u = adj[j];
                if (u != par[v]) { par[u] = v; dep[u] = dep[v] + 1; st[top++] = u; }
            }
        }
        Arrays.fill(sz, 1);
        for (int i = n - 1; i > 0; i--) sz[par[order[i]]] += sz[order[i]];
        StringBuilder sb = new StringBuilder();
        for (int v = 1; v <= n; v++) sb.append(par[v]).append(v == n ? '\n' : ' ');
        for (int v = 1; v <= n; v++) sb.append(dep[v]).append(v == n ? '\n' : ' ');
        for (int v = 1; v <= n; v++) sb.append(sz[v]).append(v == n ? '\n' : ' ');
        for (int k = 0; k < q; k++) {
            int u = in.nextInt(), v = in.nextInt();
            sb.append(tin[u] <= tin[v] && tin[v] < tin[u] + sz[u] ? 1 : 0).append('\n');
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
6 4
1 2
1 3
3 4
3 5
5 6
1 6
3 2
5 6
6 6
out:
0 1 1 3 3 5
0 1 1 2 2 3
6 1 4 1 2 1
1
0
1
1
-->
<!-- test
in:
1 1
1 1
out:
0
0
1
1
-->
<!-- test
in:
4 3
4 3
3 2
2 1
1 4
4 1
2 3
out:
0 1 2 3
0 1 2 3
4 3 2 1
1
0
1
-->

### 3.2 Diameter: two passes, DP, and every eccentricity

Input: `n`, then $n-1$ lines `a b w` with $w \ge 0$. Output: the diameter computed by the DP, then $\mathrm{ecc}(v)$ for all $v$ computed from the two endpoints of the two-pass method. Agreement of the two lines is itself a check of the lemma.

```cpp
#include <bits/stdc++.h>
using namespace std;

int n;
vector<vector<pair<int, long long>>> adj;

vector<long long> distFrom(int s) {          // iterative DFS; tree paths are unique, so any order works
    vector<long long> d(n + 1, -1);
    vector<int> st = {s}; d[s] = 0;
    while (!st.empty()) {
        int v = st.back(); st.pop_back();
        for (auto [u, w] : adj[v]) if (d[u] < 0) { d[u] = d[v] + w; st.push_back(u); }
    }
    return d;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    cin >> n;
    adj.assign(n + 1, {});
    for (int i = 0; i < n - 1; i++) { int a, b; long long w; cin >> a >> b >> w; adj[a].push_back({b, w}); adj[b].push_back({a, w}); }
    // DP: h[v] = longest downward path; best = max over top vertex of the two longest branches
    vector<int> par(n + 1, 0), order; vector<long long> pw(n + 1, 0), h(n + 1, 0);
    vector<int> st = {1};
    while (!st.empty()) {
        int v = st.back(); st.pop_back(); order.push_back(v);
        for (auto [u, w] : adj[v]) if (u != par[v]) { par[u] = v; pw[u] = w; st.push_back(u); }
    }
    vector<long long> h2(n + 1, 0);           // second-best branch at v
    long long best = 0;
    for (int i = n - 1; i >= 0; i--) {
        int v = order[i];
        best = max(best, h[v] + h2[v]);
        if (i > 0) {
            int p = par[v]; long long c = h[v] + pw[v];
            if (c > h[p]) { h2[p] = h[p]; h[p] = c; } else if (c > h2[p]) h2[p] = c;
        }
    }
    // two passes: a = farthest from 1, b = farthest from a
    vector<long long> d1 = distFrom(1);
    int a = max_element(d1.begin() + 1, d1.end()) - d1.begin();
    vector<long long> da = distFrom(a);
    int b = max_element(da.begin() + 1, da.end()) - da.begin();
    vector<long long> db = distFrom(b);
    cout << best << '\n';
    for (int v = 1; v <= n; v++) cout << max(da[v], db[v]) << (v == n ? '\n' : ' ');
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n;
    static int[] start, adj;
    static long[] wt;

    static long[] distFrom(int s) {
        long[] d = new long[n + 1];
        Arrays.fill(d, -1);
        int[] st = new int[n];
        int top = 0;
        st[top++] = s; d[s] = 0;
        while (top > 0) {
            int v = st[--top];
            for (int j = start[v]; j < start[v + 1]; j++)
                if (d[adj[j]] < 0) { d[adj[j]] = d[v] + wt[j]; st[top++] = adj[j]; }
        }
        return d;
    }

    static int argmax(long[] d) {
        int best = 1;
        for (int v = 2; v <= n; v++) if (d[v] > d[best]) best = v;
        return best;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        n = in.nextInt();
        int[] ea = new int[n - 1], eb = new int[n - 1];
        long[] ew = new long[n - 1];
        start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { ea[i] = in.nextInt(); eb[i] = in.nextInt(); ew[i] = in.nextLong(); start[ea[i] + 1]++; start[eb[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        adj = new int[2 * (n - 1)]; wt = new long[2 * (n - 1)];
        int[] fill = start.clone();
        for (int i = 0; i < n - 1; i++) {
            wt[fill[ea[i]]] = ew[i]; adj[fill[ea[i]]++] = eb[i];
            wt[fill[eb[i]]] = ew[i]; adj[fill[eb[i]]++] = ea[i];
        }
        int[] par = new int[n + 1], order = new int[n], st = new int[n];
        long[] pw = new long[n + 1], h = new long[n + 1], h2 = new long[n + 1];
        int top = 0, cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top]; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++)
                if (adj[j] != par[v]) { par[adj[j]] = v; pw[adj[j]] = wt[j]; st[top++] = adj[j]; }
        }
        long best = 0;
        for (int i = n - 1; i >= 0; i--) {
            int v = order[i];
            best = Math.max(best, h[v] + h2[v]);
            if (i > 0) {
                int p = par[v]; long c = h[v] + pw[v];
                if (c > h[p]) { h2[p] = h[p]; h[p] = c; } else if (c > h2[p]) h2[p] = c;
            }
        }
        long[] d1 = distFrom(1);
        long[] da = distFrom(argmax(d1));
        long[] db = distFrom(argmax(da));
        StringBuilder sb = new StringBuilder();
        sb.append(best).append('\n');
        for (int v = 1; v <= n; v++) sb.append(Math.max(da[v], db[v])).append(v == n ? '\n' : ' ');
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
5
1 2 3
1 3 4
3 4 5
3 5 1
out:
12
9 12 7 12 8
-->
<!-- test
in:
1
out:
0
0
-->
<!-- test
in:
4
1 2 0
2 3 1000000000
3 4 0
out:
1000000000
1000000000 1000000000 1000000000 1000000000
-->

### 3.3 Centres (leaf peeling) and centroids

Input: `n` and $n-1$ edges (unweighted). Output line 1: number of centres and the centres in increasing order; line 2: the same for centroids.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<vector<int>> adj(n + 1);
    vector<int> deg(n + 1, 0);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; adj[a].push_back(b); adj[b].push_back(a); deg[a]++; deg[b]++; }
    // centres: remove all leaves layer by layer; the last layer (1 or 2 vertices) is the centre
    vector<int> layer, removed(n + 1, 0);
    for (int v = 1; v <= n; v++) if (deg[v] <= 1) layer.push_back(v);
    int left = n;
    while (left > 2) {
        vector<int> nxt;
        for (int v : layer) {
            removed[v] = 1; left--;
            for (int u : adj[v]) if (!removed[u] && --deg[u] == 1) nxt.push_back(u);
        }
        layer = nxt;
    }
    vector<int> centres;
    for (int v = 1; v <= n; v++) if (!removed[v]) centres.push_back(v);
    // centroids: largest component after deleting v is max(n - sz[v], max child size)
    vector<int> par(n + 1, 0), order, sz(n + 1, 1), big(n + 1, 0);
    vector<int> st = {1};
    while (!st.empty()) {
        int v = st.back(); st.pop_back(); order.push_back(v);
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; st.push_back(u); }
    }
    for (int i = n - 1; i > 0; i--) { int v = order[i]; sz[par[v]] += sz[v]; big[par[v]] = max(big[par[v]], sz[v]); }
    vector<int> cents;
    for (int v = 1; v <= n; v++) if (2 * max(big[v], n - sz[v]) <= n) cents.push_back(v);
    cout << centres.size(); for (int v : centres) cout << ' ' << v; cout << '\n';
    cout << cents.size(); for (int v : cents) cout << ' ' << v; cout << '\n';
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
        int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2], deg = new int[n + 1];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; deg[eu[i]]++; deg[ev[i]]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        boolean[] removed = new boolean[n + 1];
        int[] layer = new int[n], nxt = new int[n];
        int ls = 0, left = n;
        for (int v = 1; v <= n; v++) if (deg[v] <= 1) layer[ls++] = v;
        while (left > 2) {
            int ns = 0;
            for (int k = 0; k < ls; k++) {
                int v = layer[k];
                removed[v] = true; left--;
                for (int j = start[v]; j < start[v + 1]; j++) { int u = adj[j]; if (!removed[u] && --deg[u] == 1) nxt[ns++] = u; }
            }
            int[] t = layer; layer = nxt; nxt = t; ls = ns;
        }
        int[] par = new int[n + 1], order = new int[n], st = new int[n], sz = new int[n + 1], big = new int[n + 1];
        int top = 0, cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top]; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) if (adj[j] != par[v]) { par[adj[j]] = v; st[top++] = adj[j]; }
        }
        Arrays.fill(sz, 1);
        for (int i = n - 1; i > 0; i--) { int v = order[i]; sz[par[v]] += sz[v]; big[par[v]] = Math.max(big[par[v]], sz[v]); }
        StringBuilder a = new StringBuilder(), b = new StringBuilder();
        int ca = 0, cb = 0;
        for (int v = 1; v <= n; v++) {
            if (!removed[v]) { ca++; a.append(' ').append(v); }
            if (2 * Math.max(big[v], n - sz[v]) <= n) { cb++; b.append(' ').append(v); }
        }
        out.println(ca + a.toString());
        out.println(cb + b.toString());
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

The two notions really differ: a long path with a big star at one end has its centre in the middle of the path and its centroid at the star. The first test is such a "broom": path $1..6$ plus six leaves on vertex 6; the centre is 4, the centroid is 6.

<!-- test
in:
12
1 2
2 3
3 4
4 5
5 6
6 7
6 8
6 9
6 10
6 11
6 12
out:
1 4
1 6
-->
<!-- test
in:
6
1 2
1 3
1 4
1 5
5 6
out:
2 1 5
1 1
-->
<!-- test
in:
1
out:
1 1
1 1
-->
<!-- test
in:
2
2 1
out:
2 1 2
2 1 2
-->

### 3.4 Prüfer code: linear decode and encode (🟠)

Input: `n` ($n \ge 2$) and a Prüfer code of length $n-2$. Output: the $n-1$ edges in decoding order (`leaf neighbour`), then the code re-encoded from those edges (it must equal the input — the bijection in action).

```cpp
#include <bits/stdc++.h>
using namespace std;

vector<pair<int,int>> decode(int n, const vector<int>& code) {
    vector<int> deg(n + 1, 1);
    for (int x : code) deg[x]++;
    int ptr = 1;
    while (deg[ptr] != 1) ptr++;
    int leaf = ptr;
    vector<pair<int,int>> edges;
    for (int x : code) {
        edges.push_back({leaf, x});
        if (--deg[x] == 1 && x < ptr) leaf = x;             // x just became the smallest leaf
        else { ptr++; while (deg[ptr] != 1) ptr++; leaf = ptr; }
    }
    edges.push_back({leaf, n});                              // the last two vertices: some leaf and n
    return edges;
}

vector<int> encode(int n, const vector<pair<int,int>>& edges) {
    vector<vector<int>> adj(n + 1);
    for (auto [a, b] : edges) { adj[a].push_back(b); adj[b].push_back(a); }
    vector<int> par(n + 1, 0), deg(n + 1), st = {n};         // root at n: n is never deleted
    vector<char> seen(n + 1, 0); seen[n] = 1;
    while (!st.empty()) {
        int v = st.back(); st.pop_back();
        for (int u : adj[v]) if (!seen[u]) { seen[u] = 1; par[u] = v; st.push_back(u); }
    }
    for (int v = 1; v <= n; v++) deg[v] = adj[v].size();
    int ptr = 1;
    while (deg[ptr] != 1) ptr++;
    int leaf = ptr;
    vector<int> code;
    for (int i = 0; i < n - 2; i++) {
        int x = par[leaf];
        code.push_back(x);
        if (--deg[x] == 1 && x < ptr) leaf = x;
        else { ptr++; while (deg[ptr] != 1) ptr++; leaf = ptr; }
    }
    return code;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<int> code(n - 2);
    for (int& x : code) cin >> x;
    auto edges = decode(n, code);
    for (auto [a, b] : edges) cout << a << ' ' << b << '\n';
    auto back = encode(n, edges);
    for (int i = 0; i < n - 2; i++) cout << back[i] << (i + 1 < n - 2 ? ' ' : '\n');
    if (n == 2) cout << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[][] decode(int n, int[] code) {
        int[] deg = new int[n + 1];
        Arrays.fill(deg, 1);
        for (int x : code) deg[x]++;
        int ptr = 1;
        while (deg[ptr] != 1) ptr++;
        int leaf = ptr;
        int[][] edges = new int[n - 1][];
        int k = 0;
        for (int x : code) {
            edges[k++] = new int[]{leaf, x};
            if (--deg[x] == 1 && x < ptr) leaf = x;
            else { ptr++; while (deg[ptr] != 1) ptr++; leaf = ptr; }
        }
        edges[k] = new int[]{leaf, n};
        return edges;
    }

    static int[] encode(int n, int[][] edges) {
        int[] start = new int[n + 2];
        for (int[] e : edges) { start[e[0] + 1]++; start[e[1] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int[] e : edges) { adj[fill[e[0]]++] = e[1]; adj[fill[e[1]]++] = e[0]; }
        int[] par = new int[n + 1], deg = new int[n + 1], st = new int[n];
        boolean[] seen = new boolean[n + 1];
        int top = 0;
        st[top++] = n; seen[n] = true;
        while (top > 0) {
            int v = st[--top];
            for (int j = start[v]; j < start[v + 1]; j++) if (!seen[adj[j]]) { seen[adj[j]] = true; par[adj[j]] = v; st[top++] = adj[j]; }
        }
        for (int v = 1; v <= n; v++) deg[v] = start[v + 1] - start[v];
        int ptr = 1;
        while (deg[ptr] != 1) ptr++;
        int leaf = ptr;
        int[] code = new int[n - 2];
        for (int i = 0; i < n - 2; i++) {
            int x = par[leaf];
            code[i] = x;
            if (--deg[x] == 1 && x < ptr) leaf = x;
            else { ptr++; while (deg[ptr] != 1) ptr++; leaf = ptr; }
        }
        return code;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        int[] code = new int[n - 2];
        for (int i = 0; i < n - 2; i++) code[i] = in.nextInt();
        int[][] edges = decode(n, code);
        StringBuilder sb = new StringBuilder();
        for (int[] e : edges) sb.append(e[0]).append(' ').append(e[1]).append('\n');
        int[] back = encode(n, edges);
        for (int i = 0; i < n - 2; i++) sb.append(back[i]).append(i + 1 < n - 2 ? ' ' : '\n');
        if (n == 2) sb.append('\n');
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

Hand check of the first test: degrees are $1{:}1, 2{:}3, 3{:}1, 4{:}2, 5{:}1$; delete 1 (write 2), delete 3 (write 2), now 2 is a leaf smaller than the pointer, delete 2 (write 4), and 4–5 remain.

<!-- test
in:
5
2 2 4
out:
1 2
3 2
2 4
4 5
2 2 4
-->
<!-- test
in:
2
out:
1 2
-->
<!-- test
in:
6
6 6 6 6
out:
1 6
2 6
3 6
4 6
5 6
6 6 6 6
-->

## 4. Recognising the pattern

| Statement signal | Think |
|---|---|
| "$n$ vertices and $n-1$ edges, connected" | it's a tree: unique paths, every edge is a bridge, distances by one DFS |
| "farthest vertex", "for every vertex the maximum distance" | diameter endpoints + the eccentricity lemma (3 passes) |
| "longest path", path value = sum over the path with negative weights allowed | DP on the top vertex, not two BFS |
| "choose a vertex minimising the maximum distance" | centre (middle of the diameter) |
| "minimise the sum of distances" / "every component ≤ n/2" | centroid |
| "subtree of $v$" sums / updates / counts with online updates | Euler tour + Fenwick / segment tree |
| "path from the root to $v$" with point updates | range add on $[tin, tout]$, point query |
| "is $u$ an ancestor of $v$", many queries | $tin/tout$ comparison, $O(1)$ |
| "are these two trees the same up to relabelling" | canonical ids (AHU), root at the centre if unrooted |
| "count labelled trees with given degrees" | Prüfer: multinomial $(n-2)!/\prod (d_i-1)!$ |

Commonly confused: *centre* vs *centroid* (§3.3 test 1 shows they differ); preorder "Euler tour" (subtree ranges) vs the $2n-1$ Euler sequence (LCA via RMQ); "depth" (edges from root) vs "height" (longest downward path).

## 5. Worked examples (graded)

### Example 1 — Tree Diameter · ★ ≈1300 (est.)

- **Source:** [CSES 1131 · Tree Diameter](https://cses.fi/problemset/task/1131)
- **Difficulty:** ≈1300 (est.)
- **Problem:** an unweighted tree with $n \le 2\cdot10^5$ vertices; print the number of edges on its longest path.
- **Thinking from first principles:** BFS from every vertex is $4\cdot10^{10}$ — too slow. The lemma of §1.3 says the farthest vertex from *any* start is a diameter endpoint, so two BFS passes suffice. A recursive DFS is the natural first attempt; on a path-shaped test it overflows the Java stack, so use BFS with an explicit queue.

<details><summary>Solution</summary>

BFS from vertex 1, take the farthest vertex $a$, BFS from $a$, print the largest distance. $O(n)$ time and memory. Correctness is the corollary in §1.3.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; adj[a].push_back(b); adj[b].push_back(a); }
    auto bfs = [&](int s, vector<int>& d) {
        d.assign(n + 1, -1);
        queue<int> q; q.push(s); d[s] = 0;
        int last = s;
        while (!q.empty()) {
            int v = q.front(); q.pop(); last = v;           // BFS pops in non-decreasing distance
            for (int u : adj[v]) if (d[u] < 0) { d[u] = d[v] + 1; q.push(u); }
        }
        return last;
    };
    vector<int> d;
    int a = bfs(1, d);
    int b = bfs(a, d);
    cout << d[b] << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n;
    static int[] start, adj, d, q;

    static int bfs(int s) {
        Arrays.fill(d, -1);
        int head = 0, tail = 0;
        q[tail++] = s; d[s] = 0;
        int last = s;
        while (head < tail) {
            int v = q[head++]; last = v;
            for (int j = start[v]; j < start[v + 1]; j++) if (d[adj[j]] < 0) { d[adj[j]] = d[v] + 1; q[tail++] = adj[j]; }
        }
        return last;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        n = in.nextInt();
        int[] eu = new int[n - 1], ev = new int[n - 1];
        start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        adj = new int[2 * (n - 1)];
        int[] fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        d = new int[n + 1]; q = new int[n];
        int a = bfs(1);
        int b = bfs(a);
        out.println(d[b]);
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
5
1 2
1 3
3 4
3 5
out:
3
-->
<!-- test
in:
1
out:
0
-->
<!-- test
in:
6
4 5
2 3
5 6
1 2
3 4
out:
5
-->

</details>

### Example 2 — Subtree Queries · ★ ≈1500 (est.)

- **Source:** [CSES 1137 · Subtree Queries](https://cses.fi/problemset/task/1137)
- **Difficulty:** ≈1500 (est.)
- **Problem:** rooted tree (root 1), $n, q \le 2\cdot10^5$, values up to $10^9$. Queries: set the value of vertex $s$ to $x$; report the sum of values in the subtree of $s$.
- **Thinking from first principles:** a subtree is not contiguous in vertex numbering, so a plain Fenwick tree over $1..n$ cannot answer it. The preorder makes every subtree a contiguous block (§1.5): relabel vertex $v$ as position $tin(v)$ and the tree problem becomes "point assign, range sum" on an array.

<details><summary>Solution</summary>

Compute $tin$ and $sz$ iteratively, build a Fenwick tree over positions with $a_v$ at $tin(v)$. Assignment = add $x - a_s$ at $tin(s)$; query = range sum $[tin(s), tin(s)+sz(s)-1]$. Sums reach $2\cdot10^{14}$: use 64-bit. $O((n+q)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    vector<long long> a(n + 1);
    for (int v = 1; v <= n; v++) cin >> a[v];
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int x, y; cin >> x >> y; adj[x].push_back(y); adj[y].push_back(x); }
    vector<int> par(n + 1, 0), tin(n + 1), sz(n + 1, 1), order;
    vector<int> st = {1};
    while (!st.empty()) {
        int v = st.back(); st.pop_back();
        tin[v] = order.size() + 1; order.push_back(v);      // 1-based positions for the Fenwick tree
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; st.push_back(u); }
    }
    for (int i = n - 1; i > 0; i--) sz[par[order[i]]] += sz[order[i]];
    vector<long long> fw(n + 1, 0);
    auto add = [&](int i, long long d) { for (; i <= n; i += i & -i) fw[i] += d; };
    auto pre = [&](int i) { long long s = 0; for (; i > 0; i -= i & -i) s += fw[i]; return s; };
    for (int v = 1; v <= n; v++) add(tin[v], a[v]);
    while (q--) {
        int t, s; cin >> t >> s;
        if (t == 1) { long long x; cin >> x; add(tin[s], x - a[s]); a[s] = x; }
        else cout << pre(tin[s] + sz[s] - 1) - pre(tin[s] - 1) << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n;
    static long[] fw;
    static void add(int i, long d) { for (; i <= n; i += i & -i) fw[i] += d; }
    static long pre(int i) { long s = 0; for (; i > 0; i -= i & -i) s += fw[i]; return s; }

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
        int[] par = new int[n + 1], tin = new int[n + 1], sz = new int[n + 1], order = new int[n], st = new int[n];
        int top = 0, cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top];
            order[cnt++] = v; tin[v] = cnt;
            for (int j = start[v]; j < start[v + 1]; j++) if (adj[j] != par[v]) { par[adj[j]] = v; st[top++] = adj[j]; }
        }
        Arrays.fill(sz, 1);
        for (int i = n - 1; i > 0; i--) sz[par[order[i]]] += sz[order[i]];
        fw = new long[n + 1];
        for (int v = 1; v <= n; v++) add(tin[v], a[v]);
        StringBuilder sb = new StringBuilder();
        for (int k = 0; k < q; k++) {
            int t = in.nextInt(), s = in.nextInt();
            if (t == 1) { long x = in.nextLong(); add(tin[s], x - a[s]); a[s] = x; }
            else sb.append(pre(tin[s] + sz[s] - 1) - pre(tin[s] - 1)).append('\n');
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
5 5
4 2 5 2 1
1 2
1 3
3 4
3 5
2 3
1 5 3
2 3
2 1
2 5
out:
8
10
16
3
-->
<!-- test
in:
1 3
1000000000
2 1
1 1 7
2 1
out:
1000000000
7
-->

</details>

### Example 3 — Path Queries · ★ ≈1600 (est.)

- **Source:** [CSES 1138 · Path Queries](https://cses.fi/problemset/task/1138)
- **Difficulty:** ≈1600 (est.)
- **Problem:** same input as Example 2, but the query asks for the sum of values on the path from the root to $s$.
- **Thinking from first principles:** the root path of $s$ is not contiguous in preorder, but the *set of vertices whose root path contains $x$* is exactly subtree($x$), which is. So flip the roles: keep $S(v)$ for every vertex as a "difference array over positions". Changing $a_x$ by $\delta$ is a range add of $\delta$ on $[tin(x), tout(x)]$; reading $S(s)$ is a point query at $tin(s)$.

<details><summary>Solution</summary>

Fenwick over the difference array: range add $[l,r]$ = add at $l$, subtract at $r+1$; point value = prefix sum. Initialise by doing the range add for every vertex. $O((n+q)\log n)$, 64-bit sums.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    vector<long long> a(n + 1);
    for (int v = 1; v <= n; v++) cin >> a[v];
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int x, y; cin >> x >> y; adj[x].push_back(y); adj[y].push_back(x); }
    vector<int> par(n + 1, 0), tin(n + 1), sz(n + 1, 1), order;
    vector<int> st = {1};
    while (!st.empty()) {
        int v = st.back(); st.pop_back();
        tin[v] = order.size() + 1; order.push_back(v);
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; st.push_back(u); }
    }
    for (int i = n - 1; i > 0; i--) sz[par[order[i]]] += sz[order[i]];
    vector<long long> fw(n + 2, 0);
    auto add = [&](int i, long long d) { for (; i <= n; i += i & -i) fw[i] += d; };
    auto pre = [&](int i) { long long s = 0; for (; i > 0; i -= i & -i) s += fw[i]; return s; };
    auto rangeAdd = [&](int v, long long d) { add(tin[v], d); add(tin[v] + sz[v], -d); };  // whole subtree of v
    for (int v = 1; v <= n; v++) rangeAdd(v, a[v]);
    while (q--) {
        int t, s; cin >> t >> s;
        if (t == 1) { long long x; cin >> x; rangeAdd(s, x - a[s]); a[s] = x; }
        else cout << pre(tin[s]) << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n;
    static long[] fw;
    static void add(int i, long d) { for (; i <= n; i += i & -i) fw[i] += d; }
    static long pre(int i) { long s = 0; for (; i > 0; i -= i & -i) s += fw[i]; return s; }

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
        int[] par = new int[n + 1], tin = new int[n + 1], sz = new int[n + 1], order = new int[n], st = new int[n];
        int top = 0, cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top];
            order[cnt++] = v; tin[v] = cnt;
            for (int j = start[v]; j < start[v + 1]; j++) if (adj[j] != par[v]) { par[adj[j]] = v; st[top++] = adj[j]; }
        }
        Arrays.fill(sz, 1);
        for (int i = n - 1; i > 0; i--) sz[par[order[i]]] += sz[order[i]];
        fw = new long[n + 1];
        for (int v = 1; v <= n; v++) { add(tin[v], a[v]); add(tin[v] + sz[v], -a[v]); }
        StringBuilder sb = new StringBuilder();
        for (int k = 0; k < q; k++) {
            int t = in.nextInt(), s = in.nextInt();
            if (t == 1) { long x = in.nextLong(), d = x - a[s]; add(tin[s], d); add(tin[s] + sz[s], -d); a[s] = x; }
            else sb.append(pre(tin[s])).append('\n');
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

The Fenwick `add` ignores index $n+1$ (loop condition), which is exactly the "past the end" position of the last subtree.

<!-- test
in:
5 5
4 2 5 2 1
1 2
1 3
3 4
3 5
2 4
1 3 2
2 4
2 2
2 1
out:
11
8
6
4
-->
<!-- test
in:
3 3
5 5 5
3 2
2 1
2 3
1 1 0
2 3
out:
15
10
-->

</details>

### Example 4 — Tree Queries · ★ 1900

- **Source:** [CF 1328E · Tree Queries](https://codeforces.com/problemset/problem/1328/E) — 1900
- **Difficulty:** 1900
- **Problem:** tree rooted at 1, $n, m \le 2\cdot10^5$. Each query gives $k$ vertices ($\sum k \le 2\cdot10^5$); answer whether some root-to-$u$ path passes through or next to every given vertex (each given vertex is on the path or adjacent to a vertex on it).
- **Thinking from first principles:** "on the path or adjacent to it" is awkward. For a vertex $v \ne 1$, if $v$ is adjacent to a root path $1 \to u$ then either $v$ is on it or its parent is (a child of a path vertex is the only way to be adjacent from below). Either way $p(v)$ is on the path, and conversely $p(v)$ on the path suffices. So replace every $v$ by $p(v)$ (root stays root) and ask: *do all these vertices lie on one root path?* That holds iff they are all ancestors of the deepest one — an $O(1)$ $tin/tout$ check each.

<details><summary>Solution</summary>

Let $u$ = the deepest query vertex. Answer YES iff every query vertex's parent is an ancestor of $u$.

*Why.* If all parents are ancestors of $u$, the path $1 \to u$ works: each query vertex is on it or hangs off it by its parent edge. Conversely, if some path $1 \to w$ works, all parents lie on that single root path; since $\mathrm{dep}(p(v)) \le \mathrm{dep}(p(u))$ for every $v$, each $p(v)$ is an ancestor of $p(u)$, hence of $u$. $O(n + \sum k)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; adj[a].push_back(b); adj[b].push_back(a); }
    vector<int> par(n + 1, 0), dep(n + 1, 0), tin(n + 1), sz(n + 1, 1), order;
    vector<int> st = {1};
    while (!st.empty()) {
        int v = st.back(); st.pop_back();
        tin[v] = order.size(); order.push_back(v);
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; dep[u] = dep[v] + 1; st.push_back(u); }
    }
    for (int i = n - 1; i > 0; i--) sz[par[order[i]]] += sz[order[i]];
    par[1] = 1;                                              // the root "replaces itself"
    auto isAnc = [&](int a, int b) { return tin[a] <= tin[b] && tin[b] < tin[a] + sz[a]; };
    while (m--) {
        int k; cin >> k;
        vector<int> v(k);
        for (int& x : v) cin >> x;
        int deep = v[0];
        for (int x : v) if (dep[x] > dep[deep]) deep = x;
        bool ok = true;
        for (int x : v) if (!isAnc(par[x], deep)) { ok = false; break; }
        cout << (ok ? "YES" : "NO") << '\n';
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
        int n = in.nextInt(), m = in.nextInt();
        int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        int[] par = new int[n + 1], dep = new int[n + 1], tin = new int[n + 1], sz = new int[n + 1], order = new int[n], st = new int[n];
        int top = 0, cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top];
            tin[v] = cnt; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) if (adj[j] != par[v]) { par[adj[j]] = v; dep[adj[j]] = dep[v] + 1; st[top++] = adj[j]; }
        }
        Arrays.fill(sz, 1);
        for (int i = n - 1; i > 0; i--) sz[par[order[i]]] += sz[order[i]];
        par[1] = 1;
        StringBuilder sb = new StringBuilder();
        int[] v = new int[n];
        while (m-- > 0) {
            int k = in.nextInt();
            int deep = -1;
            for (int i = 0; i < k; i++) { v[i] = in.nextInt(); if (deep < 0 || dep[v[i]] > dep[deep]) deep = v[i]; }
            boolean ok = true;
            for (int i = 0; i < k && ok; i++) { int p = par[v[i]]; ok = tin[p] <= tin[deep] && tin[deep] < tin[p] + sz[p]; }
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

First test: edges $1$–$2$, $1$–$3$, $3$–$4$, $3$–$5$, $5$–$6$, $4$–$7$. Query $\{7,6\}$: parents $4$ and $5$ are siblings, no root path contains both → NO. Query $\{2,7\}$: path $1\to3\to4\to7$, and 2 hangs off 1 → YES. Query $\{2,4,5\}$: path $1\to3\to4$, 5 hangs off 3 → YES.

<!-- test
in:
7 5
1 2
1 3
3 4
3 5
5 6
4 7
2 7 6
2 2 7
3 2 4 5
2 6 7
1 1
out:
NO
YES
YES
NO
YES
-->
<!-- test
in:
7 3
1 2
2 3
3 4
1 5
5 6
6 7
2 4 7
2 3 2
2 2 6
out:
NO
YES
YES
-->

</details>

### Example 5 — Tree Isomorphism II · ★ ≈2100 (est.)

- **Source:** [CSES 1701 · Tree Isomorphism II](https://cses.fi/problemset/task/1701) (rooted version: [CSES 1700 · Tree Isomorphism I](https://cses.fi/problemset/task/1700))
- **Difficulty:** ≈2100 (est.)
- **Problem:** $t$ test cases, $\sum n \le 10^5$; two unrooted trees on $n$ vertices each; decide whether they are isomorphic.
- **Thinking from first principles:** brute force over $n!$ bijections is hopeless. For rooted trees, isomorphism is recursive: same multiset of child subtrees. So compute canonical ids bottom-up (§1.6). For unrooted trees, we need a root that any isomorphism must respect: the centre. A tree has one or two centres; try the (at most two) centres of the second tree against one centre of the first.

<details><summary>Solution</summary>

Find centres by leaf peeling. For each candidate root, compute canonical ids with one dictionary shared within the test case (so equal ids across trees mean isomorphic subtrees). Isomorphic iff centre counts agree and the root id of $T_1$ (at its first centre) equals the root id of $T_2$ at one of its centres. $O(n \log n)$ per test.

```cpp
#include <bits/stdc++.h>
using namespace std;

vector<int> centres(int n, const vector<vector<int>>& adj) {
    vector<int> deg(n + 1), layer, removed(n + 1, 0);
    for (int v = 1; v <= n; v++) { deg[v] = adj[v].size(); if (deg[v] <= 1) layer.push_back(v); }
    int left = n;
    while (left > 2) {
        vector<int> nxt;
        for (int v : layer) { removed[v] = 1; left--; for (int u : adj[v]) if (!removed[u] && --deg[u] == 1) nxt.push_back(u); }
        layer = nxt;
    }
    vector<int> c;
    for (int v = 1; v <= n; v++) if (!removed[v]) c.push_back(v);
    return c;
}

int canon(int n, const vector<vector<int>>& adj, int root, map<vector<int>, int>& ids) {
    vector<int> par(n + 1, 0), order, st = {root}, id(n + 1);
    par[root] = -1;
    while (!st.empty()) {
        int v = st.back(); st.pop_back(); order.push_back(v);
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; st.push_back(u); }
    }
    vector<vector<int>> kids(n + 1);
    for (int i = n - 1; i >= 0; i--) {                   // children are finished before their parent
        int v = order[i];
        sort(kids[v].begin(), kids[v].end());
        auto it = ids.find(kids[v]);
        if (it == ids.end()) it = ids.emplace(kids[v], (int)ids.size()).first;
        id[v] = it->second;
        if (par[v] > 0) kids[par[v]].push_back(id[v]);
    }
    return id[root];
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        int n; cin >> n;
        vector<vector<int>> A(n + 1), B(n + 1);
        for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; A[a].push_back(b); A[b].push_back(a); }
        for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; B[a].push_back(b); B[b].push_back(a); }
        vector<int> ca = centres(n, A), cb = centres(n, B);
        bool iso = false;
        if (ca.size() == cb.size()) {
            map<vector<int>, int> ids;
            int ha = canon(n, A, ca[0], ids);
            for (int c : cb) if (canon(n, B, c, ids) == ha) iso = true;
        }
        cout << (iso ? "YES" : "NO") << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n;

    static int[][] readTree(FastReader in) throws IOException {   // returns {start, adj}
        int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        return new int[][]{start, adj};
    }

    static List<Integer> centres(int[] start, int[] adj) {
        int[] deg = new int[n + 1], layer = new int[n], nxt = new int[n];
        boolean[] removed = new boolean[n + 1];
        int ls = 0, left = n;
        for (int v = 1; v <= n; v++) { deg[v] = start[v + 1] - start[v]; if (deg[v] <= 1) layer[ls++] = v; }
        while (left > 2) {
            int ns = 0;
            for (int k = 0; k < ls; k++) {
                int v = layer[k]; removed[v] = true; left--;
                for (int j = start[v]; j < start[v + 1]; j++) if (!removed[adj[j]] && --deg[adj[j]] == 1) nxt[ns++] = adj[j];
            }
            int[] tmp = layer; layer = nxt; nxt = tmp; ls = ns;
        }
        List<Integer> c = new ArrayList<>();
        for (int v = 1; v <= n; v++) if (!removed[v]) c.add(v);
        return c;
    }

    static int canon(int[] start, int[] adj, int root, HashMap<List<Integer>, Integer> ids) {
        int[] par = new int[n + 1], order = new int[n], st = new int[n], id = new int[n + 1];
        int top = 0, cnt = 0;
        st[top++] = root; par[root] = -1;
        while (top > 0) {
            int v = st[--top]; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) if (adj[j] != par[v]) { par[adj[j]] = v; st[top++] = adj[j]; }
        }
        @SuppressWarnings("unchecked")
        ArrayList<Integer>[] kids = new ArrayList[n + 1];
        for (int i = n - 1; i >= 0; i--) {
            int v = order[i];
            List<Integer> key = kids[v] == null ? new ArrayList<>() : kids[v];
            Collections.sort(key);
            Integer got = ids.get(key);
            if (got == null) { got = ids.size(); ids.put(key, got); }
            id[v] = got;
            int p = par[v];
            if (p > 0) { if (kids[p] == null) kids[p] = new ArrayList<>(); kids[p].add(got); }
        }
        return id[root];
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = in.nextInt();
        StringBuilder sb = new StringBuilder();
        while (t-- > 0) {
            n = in.nextInt();
            int[][] A = readTree(in), B = readTree(in);
            List<Integer> ca = centres(A[0], A[1]), cb = centres(B[0], B[1]);
            boolean iso = false;
            if (ca.size() == cb.size()) {
                HashMap<List<Integer>, Integer> ids = new HashMap<>();
                int ha = canon(A[0], A[1], ca.get(0), ids);
                for (int c : cb) if (canon(B[0], B[1], c, ids) == ha) iso = true;
            }
            sb.append(iso ? "YES" : "NO").append('\n');
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

Test 1: a path $1$–$2$–$3$–$4$–$5$ against a relabelled path (YES), and a path against a "spider" with legs 2, 1, 1 (NO — the centre counts already differ). Test 2: a relabelled double star (YES); two spiders with the **same degree multiset** $\{3,2,2,1,1,1\}$ but legs $(2,2,1)$ vs $(3,1,1)$ (NO — degree sequences do not determine a tree); and $n = 2$.

<!-- test
in:
2
5
1 2
2 3
3 4
4 5
3 1
1 5
5 2
2 4
5
1 2
2 3
3 4
3 5
1 2
2 3
3 4
4 5
out:
YES
NO
-->
<!-- test
in:
3
6
1 2
1 3
1 4
4 5
4 6
6 1
6 2
6 3
3 4
3 5
6
1 2
2 3
1 4
4 5
1 6
1 2
2 3
3 4
1 5
1 6
2
1 2
2 1
out:
YES
NO
YES
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Never recurse on a tree in Java without a big stack.** A path of $2\cdot10^5$ vertices kills the default stack. Use the stack preorder + reverse-order trick (§1.2) or `new Thread(null, r, "", 1 << 28)`.
2. **Reverse preorder is a valid post-processing order** for any bottom-up DP (children always appear after their parent in preorder). You do not need a true postorder.
3. **Check `u != par[v]`, not a `visited` array**, when the input is guaranteed to be a tree — but if the input could contain a multi-edge (e.g. "graph with $n-1$ edges" that may not be a tree), use `visited`.
4. **Two-BFS fails with negative edge weights** (and for "longest path with vertex weights that can be negative"). Use the DP of §1.3.
5. **Diameter in vertices vs edges**: problems differ; for CSES 1131 it is edges. With $n = 1$ the answer is $0$.
6. **Centre ≠ centroid.** The centre minimises the *maximum* distance; the centroid minimises the *sum* of distances and bounds component sizes.
7. **$tout$ convention**: here $tout = tin + sz - 1$ (inclusive). Mixing inclusive and exclusive conventions is the most common off-by-one in Euler-tour code.
8. **Range add on a subtree touches index $tout+1$**; size the Fenwick array $n+2$ or let `add` ignore indices $> n$.
9. **Subtree sums overflow `int` quickly** ($2\cdot10^5 \times 10^9$). Use `long long` / `long`.
10. **Rooted canonical ids must sort children ids** before lookup; unsorted lists give "different" ids for the same tree. Share the dictionary between the two trees you compare.
11. **Unrooted isomorphism with two centres:** compare against *both* centres of the second tree (or root at the middle edge by subdividing it).
12. **Prüfer decode needs $\deg = 1 + \text{occurrences}$**, and the final edge is always (last leaf, $n$).
13. **Java `HashMap<List<Integer>,…>`** is fine for $10^5$ total list length but allocates heavily; for $10^6$ use a hash of the sorted list (with collision-safe random seeds) or sort-and-relabel per depth level.

## 7. Going further (toward 2400–2600+)

- **Dynamic diameter.** Maintain the diameter under edge-weight updates: segment tree over the $2n-1$ Euler sequence storing $\max(d_a - 2d_b + d_c)$ for $a \le b \le c$ — [CF 1192B · Dynamic Diameter](https://codeforces.com/problemset/problem/1192/B) — unrated, and the bracket-sequence version [CF 1149C · Tree Generator™](https://codeforces.com/problemset/problem/1149/C) — 2700.
- **Merging diameters.** The diameter of $T_1 \cup T_2$ joined by an edge, or of a union of vertex sets, has endpoints among the four old endpoints (consequence of the lemma). This makes "diameter of a vertex subset" mergeable in a segment tree or DSU.
- **All farthest distances / sums of distances** for every vertex: rerooting DP — [tree DP and rerooting](../06-Dynamic-Programming/08-tree-dp-and-rerooting.md).
- **Counting trees**: Kirchhoff and the [matrix-tree theorem](../15-Advanced-Math/06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md); with Prüfer you can count trees with constraints on degrees, e.g. [CF 1109D · Sasha and Interesting Fact from Graph Theory](https://codeforces.com/problemset/problem/1109/D) — 2400.
- **Isomorphism at scale**: hashing-based subtree classes appear inside harder problems (counting distinct subtrees, symmetric vertex choice as in [CF 1182D · Complete Mirror](https://codeforces.com/problemset/problem/1182/D) — 2400).
- Next files: [LCA](02-lca-and-binary-lifting.md) for arbitrary path queries, [small-to-large](03-small-to-large-and-dsu-on-tree.md) for subtree statistics that are not sums, [HLD](04-heavy-light-decomposition.md) for path updates. Revision: [cheat sheet](../99-Cheat-Sheets/10-trees-cheatsheet.md).

## 8. Practice ladder

**≤ 1400**
- [ ] [CSES 1674 · Subordinates](https://cses.fi/problemset/task/1674) — subtree sizes
- [ ] [CF 1676G · White-Black Balanced Subtrees](https://codeforces.com/problemset/problem/1676/G) — 1300
- [ ] [CF 1843D · Apple Tree](https://codeforces.com/problemset/problem/1843/D) — 1200
- [ ] [CF 1143C · Queen](https://codeforces.com/problemset/problem/1143/C) — 1400
- [ ] [CSES 1131 · Tree Diameter](https://cses.fi/problemset/task/1131)

**1400–1900**
- [ ] [CF 580C · Kefa and Park](https://codeforces.com/problemset/problem/580/C) — 1500
- [ ] [CSES 1132 · Tree Distances I](https://cses.fi/problemset/task/1132) — eccentricity lemma
- [ ] [CSES 1137 · Subtree Queries](https://cses.fi/problemset/task/1137)
- [ ] [CSES 1138 · Path Queries](https://cses.fi/problemset/task/1138)
- [ ] [CSES 2079 · Finding a Centroid](https://cses.fi/problemset/task/2079)
- [ ] [CF 1406C · Link Cut Centroids](https://codeforces.com/problemset/problem/1406/C) — 1700
- [ ] [CF 1881F · Minimum Maximum Distance](https://codeforces.com/problemset/problem/1881/F) — 1700
- [ ] [CF 1805D · A Wide, Wide Graph](https://codeforces.com/problemset/problem/1805/D) — 1800
- [ ] [CF 1328E · Tree Queries](https://codeforces.com/problemset/problem/1328/E) — 1900
- [ ] [CF 1404B · Tree Tag](https://codeforces.com/problemset/problem/1404/B) — 1900
- [ ] [CF 14D · Two Paths](https://codeforces.com/problemset/problem/14/D) — 1900

**1900–2400**
- [ ] [CF 1294F · Three Paths on a Tree](https://codeforces.com/problemset/problem/1294/F) — 2000
- [ ] [CF 383C · Propagating tree](https://codeforces.com/problemset/problem/383/C) — 2000
- [ ] [CF 877E · Danil and a Part-time Job](https://codeforces.com/problemset/problem/877/E) — 2000
- [ ] [CF 620E · New Year Tree](https://codeforces.com/problemset/problem/620/E) — 2100
- [ ] [CSES 1700 · Tree Isomorphism I](https://cses.fi/problemset/task/1700)
- [ ] [CSES 1701 · Tree Isomorphism II](https://cses.fi/problemset/task/1701)
- [ ] [CSES 1134 · Prüfer Code](https://cses.fi/problemset/task/1134)
- [ ] [CF 1109D · Sasha and Interesting Fact from Graph Theory](https://codeforces.com/problemset/problem/1109/D) — 2400
- [ ] [CF 1182D · Complete Mirror](https://codeforces.com/problemset/problem/1182/D) — 2400

## 9. LeetCode / FAANG cross-reference

Trees are the single most common interview topic; the techniques here map directly.

- [LC 543 · Diameter of Binary Tree](https://leetcode.com/problems/diameter-of-binary-tree/) — Easy — the top-vertex DP of §1.3 on a binary tree.
- [LC 1245 · Tree Diameter](https://leetcode.com/problems/tree-diameter/) — Medium 🔒 — two BFS passes exactly as Example 1.
- [LC 1522 · Diameter of N-Ary Tree](https://leetcode.com/problems/diameter-of-n-ary-tree/) — Medium 🔒 — top-two branches per vertex.
- [LC 310 · Minimum Height Trees](https://leetcode.com/problems/minimum-height-trees/) — Medium — the centres, by leaf peeling (§3.3).
- [LC 124 · Binary Tree Maximum Path Sum](https://leetcode.com/problems/binary-tree-maximum-path-sum/) — Hard — the diameter DP with negative weights (why two BFS would fail).
- [LC 2246 · Longest Path With Different Adjacent Characters](https://leetcode.com/problems/longest-path-with-different-adjacent-characters/) — Hard — top-two branches with a constraint on which children count.
- [LC 1617 · Count Subtrees With Max Distance Between Cities](https://leetcode.com/problems/count-subtrees-with-max-distance-between-cities/) — Hard — diameter of vertex subsets.
- [LC 652 · Find Duplicate Subtrees](https://leetcode.com/problems/find-duplicate-subtrees/) — Medium — canonical subtree ids (§1.6) in their purest form.
- [LC 1443 · Minimum Time to Collect All Apples in a Tree](https://leetcode.com/problems/minimum-time-to-collect-all-apples-in-a-tree/) — Medium — count edges whose subtree contains a target.
- [LC 2477 · Minimum Fuel Cost to Report to the Capital](https://leetcode.com/problems/minimum-fuel-cost-to-report-to-the-capital/) — Medium — per-edge contribution $\lceil sz/\text{seats}\rceil$.
- [LC 834 · Sum of Distances in Tree](https://leetcode.com/problems/sum-of-distances-in-tree/) — Hard — the edge-contribution identity plus rerooting.
- [LC 2440 · Create Components With Same Value](https://leetcode.com/problems/create-components-with-same-value/) — Hard — subtree sums decide which edges can be cut.

Interview note: interviewers accept recursion on binary trees; say out loud that you would go iterative for a degenerate 10^5-deep tree — it signals production awareness.

## 10. Self-check

1. Why does reverse preorder work for computing subtree sizes?
2. State and prove the eccentricity lemma. Where exactly does the proof use non-negative weights?
3. Give a weighted tree (with a negative edge) where two-BFS returns a wrong diameter.
4. A tree has diameter 7 (edges). How many centres does it have and what is its radius?
5. Prove that a tree has at most two centroids and that two centroids are adjacent.
6. How do you support "add $x$ to every vertex on the path root→$v$" and "query the value of a vertex"? (Hint: dualise Example 3.)
7. How many labelled trees on 6 vertices have vertex 1 of degree 3?
8. Why must the dictionary of canonical ids be shared between the two trees?

<details><summary>Answers</summary>

1. In preorder every vertex appears after its parent, so scanning backwards, a vertex's size is final (all its descendants come later in preorder and were already scanned) when it is pushed into its parent.
2. See §1.3. Non-negativity is used in $d(s,w) \le d(s,y) + d(y,w)$ when $s$ and $w$ share a branch: the true distance is the right side minus twice a common segment, which is only smaller if that segment is non-negative.
3. Edges $1$–$2$ ($3$), $2$–$3$ ($-10$), $3$–$4$ ($8$), $3$–$5$ ($8$). From 1 the farthest vertex is 2 (distance 3; vertices 4 and 5 are at distance 1); from 2 the farthest is 1, so two-BFS reports 3. The path $4$–$3$–$5$ has length 16, which the DP finds.
4. Odd diameter → two adjacent centres, radius $\lceil 7/2 \rceil = 4$.
5. Let $c_1 = p_0, p_1, \dots, p_k = c_2$ be the path between two centroids, and suppose $k \ge 2$. Cut edge $(p_0,p_1)$: the side $R$ containing $p_1$ is a component of $T - c_1$, so $\lvert R\rvert \le n/2$ and the other side $L \ni c_1$ has $\lvert L\rvert \ge n/2$. Symmetrically, cutting $(p_{k-1},p_k)$ gives a side $R' \ni c_2$ with $\lvert R'\rvert \ge n/2$. $L$ and $R'$ are disjoint and both miss $p_1$, so $n/2 + n/2 \le n - 1$, a contradiction. Hence $k = 1$; then both sides of the edge have $\le n/2$ vertices, i.e. exactly $n/2$. Three centroids would be pairwise adjacent — a triangle.
6. "Add $x$ on root→$v$" = point add $x$ at $tin(v)$; the value of $u$ = sum over its subtree range $[tin(u), tout(u)]$ (every update at a descendant passes through $u$). Point update, range query — Example 2's structure.
7. Prüfer: vertex 1 appears exactly twice among the 4 positions, others fill the rest from 5 labels: $\binom{4}{2}\cdot 5^2 = 150$.
8. Ids are only meaningful relative to one dictionary: id 7 in one map and id 7 in another map can denote different shapes.

</details>
