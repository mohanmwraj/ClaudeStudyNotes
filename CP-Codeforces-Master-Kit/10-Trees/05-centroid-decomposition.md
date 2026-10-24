# Centroid decomposition

> **Band:** 🟠 2100–2400 · **Priority:** ⚡ · **FAANG:** none · **Prerequisites:** [centroids and tree basics](01-tree-basics-diameter-center-euler-tour.md), [LCA](02-lca-and-binary-lifting.md), [two pointers](../02-Core-Techniques/03-two-pointers-and-sliding-window.md), [prefix sums](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md), [Fenwick tree](../08-Data-Structures/01-fenwick-tree.md)
> **You can say you know this when:** you can write an iterative centroid decomposition that counts paths with a length/weight constraint in $O(n\log n)$ or $O(n\log^2 n)$, explain why every path is counted exactly once, and use the centroid tree for "nearest marked vertex" style update/query problems.

## 1. First principles — why this works

### 1.1 Paths through one vertex, then divide and conquer

Many tree problems ask about **all paths**: count pairs at distance exactly $k$, at most $K$, with weight in a range, with some XOR or bitmask property, the best path under a constraint… There are $\Theta(n^2)$ paths, so enumerating them is out.

Pick any vertex $c$. Every path either **passes through $c$**, or lies entirely inside one component of $T - c$. Paths through $c$ are easy to organise: each such path is two "arms" $c \to u$ and $c \to v$ hanging into *different* components (or one arm, if an endpoint is $c$). So:

1. handle all paths through $c$ by combining arm information from different components — typically linear or $O(m\log m)$ in the component size $m$;
2. delete $c$ and recurse on every component.

Every path is handled exactly once: at the **first** removed vertex that lies on it (before that, the path was inside one component; at that moment it passes through the chosen vertex).

### 1.2 Why the centroid

The cost is the sum of component sizes over all recursion nodes. If we pick $c$ badly — say an endpoint of a long path — the component shrinks by one and the total is $\Theta(n^2)$. Pick the **centroid** (file 01: a vertex whose removal leaves components of size $\le m/2$). Then every vertex lies in components whose sizes at least halve at each level, so it belongs to at most $\lfloor \log_2 n\rfloor + 1$ components. Summing over vertices: $O(n\log n)$ total work for linear per-component processing, $O(n\log^2 n)$ if each level sorts.

Finding the centroid of a component of size $m$: root it anywhere, compute subtree sizes, and walk from the root towards a child with size $> m/2$ while one exists. The part "above" the current vertex always has size $< m/2$ (we only stepped into a child of size $> m/2$), so the walk stops at a centroid. $O(m)$.

### 1.3 Counting each pair once: two standard tricks

When combining arms at $c$, pairs of arms inside the **same** component must not be combined (their real path does not pass through $c$).

- **Inclusion–exclusion.** Count pairs among *all* arms of the component (including the trivial arm $c$ at distance 0), then subtract, for every child component, the pairs among its own arms — measured from $c$, so the subtracted quantity is computed with the same distances. Works when "count pairs" is easy for a multiset (sort + two pointers for "$d_u + d_v \le K$").
- **Incremental.** Process child components one by one; query each arm against a structure holding the arms of the *previous* components (plus $c$ itself), then insert the current component. Works for anything with a query/insert structure (count arrays, Fenwick trees, hash maps of masks…).

### 1.4 The centroid tree

Record, for every centroid, the centroid of the component it was split from: this defines the **centroid tree**, of depth $\le \lfloor\log_2 n\rfloor + 1$. Its key property:

> For any two vertices $u, v$, the original path $u$–$v$ passes through $w = \mathrm{lca}_{C}(u, v)$ (the LCA in the centroid tree), and $w$ is an ancestor of both in the centroid tree.

*Proof.* $u$ and $v$ stay in the same component until the first time a vertex of their path is removed — that vertex is the centroid that separates them, which is exactly their centroid-tree LCA. $\blacksquare$

Consequences. For any centroid ancestor $c$ of $u$, $d(u, v) \le d(u, c) + d(c, v)$, with **equality for $c = w$**. So

$$\min_{v \text{ marked}} d(u, v) = \min_{c \,\in\, \mathrm{anc}_C(u)} \big( d(u, c) + best(c) \big), \qquad best(c) = \min_{v \text{ marked},\ v \in \mathrm{comp}(c)} d(c, v),$$

and marking a vertex $v$ updates $best(c)$ for its $O(\log n)$ centroid ancestors. Store $d(v, c)$ for every vertex and each of its centroid ancestors — $O(n\log n)$ numbers, computed by one BFS per component during the decomposition.

### 1.5 Without recursion

Use an explicit work list of (component entry vertex, centroid parent, level). For each item: BFS from the entry vertex over non-removed vertices to get the component and a BFS order, sizes by reverse order, walk to the centroid, mark it removed, do the per-centroid work (another BFS from the centroid for distances), and push one item per remaining neighbour. Every vertex is touched $O(\log n)$ times in total.

## 2. Formulas, definitions and identities

| Formula | Meaning |
|---|---|
| component sizes after removing a centroid: $\le \lfloor m/2 \rfloor$ | definition |
| levels $\le \lfloor\log_2 n\rfloor + 1$; each vertex in $\le \lfloor\log_2 n\rfloor + 1$ components | halving |
| $T(m) = O(m) + \sum_i T(m_i)$, $m_i \le m/2$, $\sum m_i = m - 1$ ⇒ $T(n) = O(n\log n)$ | linear work per level |
| with a sort per component: $O(n\log^2 n)$ | |
| pairs through $c$ with $d_u + d_v \le K$: $P(\text{all arms}) - \sum_{\text{child } i} P(\text{arms of } i)$ | inclusion–exclusion (§1.3) |
| $d(u,v) = d(u,w) + d(w,v)$, $w = \mathrm{lca}_C(u,v)$ | centroid-tree property |
| nearest marked: $\min_{c \in \mathrm{anc}_C(u)} d(u,c) + best(c)$ | §1.4 |
| exact-length counting with count arrays: per child cost $O(\text{depth of the child})$ if children are processed by increasing depth | §5, Example 3 |

| Operation | Cost |
|---|---|
| decomposition (centroid tree + distance tables) | $O(n\log n)$ time, $O(n\log n)$ memory for tables |
| count pairs with $d \le K$ (sort + two pointers) | $O(n\log^2 n)$ |
| count pairs with $d \in [k_1, k_2]$ (count arrays, sorted children) | $O(n\log n)$ |
| mark / nearest-marked query on the centroid tree | $O(\log n)$ each |

## 3. Implementation (C++ and Java)

### 3.1 Iterative decomposition: count pairs with weighted distance $\le K$

Input: `n K`, then $n-1$ lines `a b w` ($w \ge 0$). Output: the number of unordered pairs $u < v$ with $d(u,v) \le K$. Per centroid: inclusion–exclusion with sort + two pointers.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

ll countPairs(vector<ll>& d, ll K) {          // pairs i < j with d[i] + d[j] <= K
    sort(d.begin(), d.end());
    ll res = 0;
    for (int i = 0, j = (int)d.size() - 1; i < j; ) {
        if (d[i] + d[j] <= K) { res += j - i; i++; } else j--;
    }
    return res;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; ll K; cin >> n >> K;
    vector<vector<pair<int, ll>>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; ll w; cin >> a >> b >> w; adj[a].push_back({b, w}); adj[b].push_back({a, w}); }
    vector<char> removed(n + 1, 0);
    vector<int> par(n + 1, 0), sz(n + 1, 0), comp;
    vector<ll> dist(n + 1, 0);
    // collect the arms of the component entered at s (parent p, distance d0 from the centroid)
    auto collect = [&](int s, int p, ll d0, vector<ll>& out) {
        comp.clear(); comp.push_back(s); par[s] = p; dist[s] = d0;
        for (size_t i = 0; i < comp.size(); i++) {
            int v = comp[i];
            for (auto [u, w] : adj[v]) if (!removed[u] && u != par[v]) { par[u] = v; dist[u] = dist[v] + w; comp.push_back(u); }
        }
        for (int v : comp) out.push_back(dist[v]);
    };
    ll ans = 0;
    vector<int> work = {1};
    while (!work.empty()) {
        int r = work.back(); work.pop_back();
        // 1. the component of r, BFS order, sizes
        comp.clear(); comp.push_back(r); par[r] = 0;
        for (size_t i = 0; i < comp.size(); i++) {
            int v = comp[i];
            for (auto [u, w] : adj[v]) if (!removed[u] && u != par[v]) { par[u] = v; comp.push_back(u); }
        }
        int m = comp.size();
        for (int i = m - 1; i >= 0; i--) { int v = comp[i]; sz[v] = 1; }
        for (int i = m - 1; i > 0; i--) sz[par[comp[i]]] += sz[comp[i]];
        // 2. walk to the centroid
        int c = r;
        for (bool moved = true; moved; ) {
            moved = false;
            for (auto [u, w] : adj[c]) if (!removed[u] && u != par[c] && 2 * sz[u] > m) { c = u; moved = true; break; }
        }
        // 3. paths through c: all arms minus same-branch arms
        removed[c] = 1;
        vector<ll> all = {0};
        for (auto [u, w] : adj[c]) if (!removed[u]) {
            vector<ll> br;
            collect(u, c, w, br);
            ans -= countPairs(br, K);
            all.insert(all.end(), br.begin(), br.end());
        }
        ans += countPairs(all, K);
        // 4. recurse on the components
        for (auto [u, w] : adj[c]) if (!removed[u]) work.push_back(u);
    }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n;
    static int[] start, adj, par, comp;
    static long[] wt, dist;
    static boolean[] removed;
    static int compSize;
    static final Random RND = new Random(2026);

    static long countPairs(long[] d, int len, long K) {
        for (int i = len - 1; i > 0; i--) { int j = RND.nextInt(i + 1); long t = d[i]; d[i] = d[j]; d[j] = t; }
        Arrays.sort(d, 0, len);
        long res = 0;
        for (int i = 0, j = len - 1; i < j; ) {
            if (d[i] + d[j] <= K) { res += j - i; i++; } else j--;
        }
        return res;
    }

    static void bfs(int s, int p, long d0) {           // fills comp[0..compSize) with the component of s
        compSize = 0; comp[compSize++] = s; par[s] = p; dist[s] = d0;
        for (int i = 0; i < compSize; i++) {
            int v = comp[i];
            for (int j = start[v]; j < start[v + 1]; j++) {
                int u = adj[j];
                if (!removed[u] && u != par[v]) { par[u] = v; dist[u] = dist[v] + wt[j]; comp[compSize++] = u; }
            }
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        n = in.nextInt();
        long K = in.nextLong();
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
        removed = new boolean[n + 1]; par = new int[n + 1]; comp = new int[n]; dist = new long[n + 1];
        int[] sz = new int[n + 1], work = new int[n];
        long[] all = new long[n], br = new long[n];
        int wTop = 0;
        work[wTop++] = 1;
        long ans = 0;
        while (wTop > 0) {
            int r = work[--wTop];
            bfs(r, 0, 0);
            int m = compSize;
            for (int i = 0; i < m; i++) sz[comp[i]] = 1;
            for (int i = m - 1; i > 0; i--) sz[par[comp[i]]] += sz[comp[i]];
            int c = r;
            for (boolean moved = true; moved; ) {
                moved = false;
                for (int j = start[c]; j < start[c + 1]; j++) {
                    int u = adj[j];
                    if (!removed[u] && u != par[c] && 2 * sz[u] > m) { c = u; moved = true; break; }
                }
            }
            removed[c] = true;
            int allLen = 0;
            all[allLen++] = 0;
            for (int j = start[c]; j < start[c + 1]; j++) {
                int u = adj[j];
                if (removed[u]) continue;
                bfs(u, c, wt[j]);
                for (int i = 0; i < compSize; i++) { br[i] = dist[comp[i]]; all[allLen++] = dist[comp[i]]; }
                ans -= countPairs(br, compSize, K);
            }
            ans += countPairs(all, allLen, K);
            for (int j = start[c]; j < start[c + 1]; j++) if (!removed[adj[j]]) work[wTop++] = adj[j];
        }
        out.println(ans);
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

The work list holds at most $n$ entries in total over time but at most $O(n)$ at once, so `work = new int[n]` suffices (each vertex is pushed at most once as an entry point, since an entry vertex is adjacent to a just-removed centroid and lies in a fresh component). Test 1: path $1$–$2$–$3$–$4$ with weights $1, 2, 3$: distances $1,3,6,2,5,3$ → five pairs with $d \le 5$. Test 2: a star with weight-0 edges — all $\binom{5}{2} = 10$ pairs have distance 0.

<!-- test
in:
4 5
1 2 1
2 3 2
3 4 3
out:
5
-->
<!-- test
in:
5 0
1 2 0
1 3 0
1 4 0
1 5 0
out:
10
-->
<!-- test
in:
1 7
out:
0
-->
<!-- test
in:
7 4
1 2 1
1 3 1
2 4 2
2 5 3
3 6 1
6 7 5
out:
11
-->

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "count pairs / paths with length = $k$, $\le K$, in $[a,b]$" on a tree, $n \ge 10^5$ | centroid decomposition |
| path property composed of two arm properties (sum, XOR, bitmask parity, max, gcd…) | combine arms through the centroid |
| "for every vertex, how many interesting paths pass through it" | centroid + propagate counts down each arm |
| online "mark a vertex / nearest marked vertex" or "sum of distances to marked set" | centroid tree, $O(\log n)$ ancestors |
| "find a path with property P, minimise length" | centroid + best-arm tables |
| constraint like $k \le 500$ and $n \le 5\cdot10^4$ | the simpler $O(nk)$ tree DP may be intended — check first |
| subtree statistics (not paths) | not centroid — [small-to-large](03-small-to-large-and-dsu-on-tree.md) |

## 5. Worked examples (graded)

### Example 1 — Finding a Centroid · ★ ≈1600 (est.)

- **Source:** [CSES 2079 · Finding a Centroid](https://cses.fi/problemset/task/2079)
- **Difficulty:** ≈1600 (est.)
- **Problem:** $n \le 2\cdot10^5$; print a vertex whose removal leaves components of size $\le \lfloor n/2 \rfloor$.
- **Thinking from first principles:** the existence proof *is* the algorithm: root at 1, compute sizes, walk into a child of size $> n/2$ while possible.

<details><summary>Solution</summary>

$O(n)$. When two centroids exist, this walk prints the one closer to vertex 1; the tests below have unique centroids.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; adj[a].push_back(b); adj[b].push_back(a); }
    vector<int> par(n + 1, 0), sz(n + 1, 1), order, st = {1};
    while (!st.empty()) {
        int v = st.back(); st.pop_back(); order.push_back(v);
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; st.push_back(u); }
    }
    for (int i = n - 1; i > 0; i--) sz[par[order[i]]] += sz[order[i]];
    int c = 1;
    for (bool moved = true; moved; ) {
        moved = false;
        for (int u : adj[c]) if (u != par[c] && 2 * sz[u] > n) { c = u; moved = true; break; }
    }
    cout << c << '\n';
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
        int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        int[] par = new int[n + 1], sz = new int[n + 1], order = new int[n], st = new int[n];
        int top = 0, cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top]; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) if (adj[j] != par[v]) { par[adj[j]] = v; st[top++] = adj[j]; }
        }
        Arrays.fill(sz, 1);
        for (int i = n - 1; i > 0; i--) sz[par[order[i]]] += sz[order[i]];
        int c = 1;
        for (boolean moved = true; moved; ) {
            moved = false;
            for (int j = start[c]; j < start[c + 1]; j++) {
                int u = adj[j];
                if (u != par[c] && 2 * sz[u] > n) { c = u; moved = true; break; }
            }
        }
        out.println(c);
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
2 3
3 4
4 5
out:
3
-->
<!-- test
in:
7
1 2
2 3
2 4
4 5
4 6
4 7
out:
4
-->
<!-- test
in:
1
out:
1
-->

</details>

### Example 2 — Ciel the Commander · ★ 2100

- **Source:** [CF 321C · Ciel the Commander](https://codeforces.com/problemset/problem/321/C) — 2100
- **Difficulty:** 2100
- **Problem:** assign each of $n \le 10^5$ vertices a rank `A`..`Z` so that any two vertices of equal rank have a vertex of strictly higher rank (smaller letter) on the path between them; or report impossibility.
- **Thinking from first principles:** the single `A` must split the tree so that each component is solved independently with `B`..`Z` — exactly the recursion of §1.1, and the constraint "26 letters" becomes "recursion depth $\le 26$". Choosing the centroid gives depth $\le \lfloor\log_2 10^5\rfloor + 1 = 17$, so the answer always exists: rank = `'A' + level` in the centroid tree. Validity: two vertices with the same level are in different components at that level (or one is the centroid), and their path passes through their centroid-tree LCA, which has a smaller level.

<details><summary>Solution</summary>

Iterative decomposition, recording levels. $O(n\log n)$. The tests use trees whose centroids are unique at every level, so the output is forced.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; adj[a].push_back(b); adj[b].push_back(a); }
    vector<char> removed(n + 1, 0);
    vector<int> par(n + 1, 0), sz(n + 1), level(n + 1), comp;
    vector<pair<int,int>> work = {{1, 0}};                 // (entry vertex, level)
    while (!work.empty()) {
        auto [r, lev] = work.back(); work.pop_back();
        comp.clear(); comp.push_back(r); par[r] = 0;
        for (size_t i = 0; i < comp.size(); i++) {
            int v = comp[i];
            for (int u : adj[v]) if (!removed[u] && u != par[v]) { par[u] = v; comp.push_back(u); }
        }
        int m = comp.size();
        for (int v : comp) sz[v] = 1;
        for (int i = m - 1; i > 0; i--) sz[par[comp[i]]] += sz[comp[i]];
        int c = r;
        for (bool moved = true; moved; ) {
            moved = false;
            for (int u : adj[c]) if (!removed[u] && u != par[c] && 2 * sz[u] > m) { c = u; moved = true; break; }
        }
        removed[c] = 1; level[c] = lev;
        for (int u : adj[c]) if (!removed[u]) work.push_back({u, lev + 1});
    }
    for (int v = 1; v <= n; v++) cout << char('A' + level[v]) << (v == n ? '\n' : ' ');
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
        int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        boolean[] removed = new boolean[n + 1];
        int[] par = new int[n + 1], sz = new int[n + 1], level = new int[n + 1], comp = new int[n];
        int[] workV = new int[n], workL = new int[n];
        int wTop = 0;
        workV[wTop] = 1; workL[wTop++] = 0;
        while (wTop > 0) {
            int r = workV[--wTop], lev = workL[wTop];
            int m = 0;
            comp[m++] = r; par[r] = 0;
            for (int i = 0; i < m; i++) {
                int v = comp[i];
                for (int j = start[v]; j < start[v + 1]; j++) { int u = adj[j]; if (!removed[u] && u != par[v]) { par[u] = v; comp[m++] = u; } }
            }
            for (int i = 0; i < m; i++) sz[comp[i]] = 1;
            for (int i = m - 1; i > 0; i--) sz[par[comp[i]]] += sz[comp[i]];
            int c = r;
            for (boolean moved = true; moved; ) {
                moved = false;
                for (int j = start[c]; j < start[c + 1]; j++) {
                    int u = adj[j];
                    if (!removed[u] && u != par[c] && 2 * sz[u] > m) { c = u; moved = true; break; }
                }
            }
            removed[c] = true; level[c] = lev;
            for (int j = start[c]; j < start[c + 1]; j++) if (!removed[adj[j]]) { workV[wTop] = adj[j]; workL[wTop++] = lev + 1; }
        }
        StringBuilder sb = new StringBuilder();
        for (int v = 1; v <= n; v++) sb.append((char) ('A' + level[v])).append(v == n ? '\n' : ' ');
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

Test 1 is the path of 7 vertices: centre 4 (`A`), then 2 and 6 (`B`), then the leaves (`C`). Test 2 is a star: the centre is `A`, every leaf `B`.

<!-- test
in:
7
1 2
2 3
3 4
4 5
5 6
6 7
out:
C B C A C B C
-->
<!-- test
in:
5
3 1
3 2
3 4
3 5
out:
B B A B B
-->
<!-- test
in:
1
out:
A
-->

</details>

### Example 3 — Fixed-Length Paths II · ★ ≈2200 (est.)

- **Source:** [CSES 2081 · Fixed-Length Paths II](https://cses.fi/problemset/task/2081) (and the exact-length version [CSES 2080 · Fixed-Length Paths I](https://cses.fi/problemset/task/2080))
- **Difficulty:** ≈2200 (est.)
- **Problem:** $n \le 2\cdot10^5$, $1 \le k_1 \le k_2 \le n$; count paths whose number of edges lies in $[k_1, k_2]$.
- **Thinking from first principles:** through a centroid $c$, a path is two arms of depths $a$ (in one child component) and $b$ (in an earlier component, or $b = 0$ for $c$ itself) with $k_1 \le a + b \le k_2$. Use the incremental trick with a count array `cnt[b]` and its prefix sums: an arm of depth $a$ pairs with $\sum_{b = k_1 - a}^{k_2 - a} cnt[b]$. The catch is cost: recomputing prefix sums of `cnt` for every child costs the *current maximum depth*, which can be large for every one of many tiny children (a star of long paths). Fix: **process children in increasing order of their depth**. Then the current maximum depth never exceeds the depth of the child being processed, so each child costs $O(\text{its depth}) \le O(\text{its size})$, and the whole level is linear.

<details><summary>Solution</summary>

Per centroid: BFS each child component to get its depth histogram, sort children by maximum depth, then for each child: rebuild prefix sums of `cnt` (length = current max depth + 1), add its pairs, merge its histogram into `cnt`. $O(n \log n)$ overall (plus sorting the children, $O(\deg\log\deg)$ per centroid). Answers up to $\approx 2\cdot10^{10}$: 64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, k1, k2; cin >> n >> k1 >> k2;
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; adj[a].push_back(b); adj[b].push_back(a); }
    vector<char> removed(n + 1, 0);
    vector<int> par(n + 1, 0), sz(n + 1), dep(n + 1), comp;
    ll ans = 0;
    vector<int> work = {1};
    while (!work.empty()) {
        int r = work.back(); work.pop_back();
        comp.clear(); comp.push_back(r); par[r] = 0;
        for (size_t i = 0; i < comp.size(); i++) {
            int v = comp[i];
            for (int u : adj[v]) if (!removed[u] && u != par[v]) { par[u] = v; comp.push_back(u); }
        }
        int m = comp.size();
        for (int v : comp) sz[v] = 1;
        for (int i = m - 1; i > 0; i--) sz[par[comp[i]]] += sz[comp[i]];
        int c = r;
        for (bool moved = true; moved; ) {
            moved = false;
            for (int u : adj[c]) if (!removed[u] && u != par[c] && 2 * sz[u] > m) { c = u; moved = true; break; }
        }
        removed[c] = 1;
        vector<vector<ll>> hist;                            // depth histogram of each child component
        for (int u : adj[c]) if (!removed[u]) {
            comp.clear(); comp.push_back(u); par[u] = c; dep[u] = 1;
            for (size_t i = 0; i < comp.size(); i++) {
                int v = comp[i];
                for (int x : adj[v]) if (!removed[x] && x != par[v]) { par[x] = v; dep[x] = dep[v] + 1; comp.push_back(x); }
            }
            vector<ll> h(dep[comp.back()] + 1, 0);           // BFS: the last vertex is the deepest
            for (int v : comp) h[dep[v]]++;
            hist.push_back(move(h));
        }
        sort(hist.begin(), hist.end(), [](const vector<ll>& a, const vector<ll>& b) { return a.size() < b.size(); });
        vector<ll> cnt = {1}, pre;                           // the centroid itself: one arm of depth 0
        for (auto& h : hist) {
            int md = cnt.size() - 1;                         // current max depth, <= this child's depth
            pre.assign(md + 2, 0);
            for (int b = 0; b <= md; b++) pre[b + 1] = pre[b] + cnt[b];
            for (int a = 1; a < (int)h.size(); a++) {
                int lo = max(0, k1 - a), hi = min(md, k2 - a);
                if (lo <= hi) ans += h[a] * (pre[hi + 1] - pre[lo]);
            }
            if (h.size() > cnt.size()) cnt.resize(h.size(), 0);
            for (int a = 1; a < (int)h.size(); a++) cnt[a] += h[a];
        }
        for (int u : adj[c]) if (!removed[u]) work.push_back(u);
    }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), k1 = in.nextInt(), k2 = in.nextInt();
        int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        boolean[] removed = new boolean[n + 1];
        int[] par = new int[n + 1], sz = new int[n + 1], dep = new int[n + 1], comp = new int[n], work = new int[n];
        long[] cnt = new long[n + 1], pre = new long[n + 2];
        int wTop = 0;
        work[wTop++] = 1;
        long ans = 0;
        while (wTop > 0) {
            int r = work[--wTop];
            int m = 0;
            comp[m++] = r; par[r] = 0;
            for (int i = 0; i < m; i++) {
                int v = comp[i];
                for (int j = start[v]; j < start[v + 1]; j++) { int u = adj[j]; if (!removed[u] && u != par[v]) { par[u] = v; comp[m++] = u; } }
            }
            for (int i = 0; i < m; i++) sz[comp[i]] = 1;
            for (int i = m - 1; i > 0; i--) sz[par[comp[i]]] += sz[comp[i]];
            int c = r;
            for (boolean moved = true; moved; ) {
                moved = false;
                for (int j = start[c]; j < start[c + 1]; j++) {
                    int u = adj[j];
                    if (!removed[u] && u != par[c] && 2 * sz[u] > m) { c = u; moved = true; break; }
                }
            }
            removed[c] = true;
            ArrayList<long[]> hist = new ArrayList<>();
            for (int j = start[c]; j < start[c + 1]; j++) {
                int u = adj[j];
                if (removed[u]) continue;
                int k = 0;
                comp[k++] = u; par[u] = c; dep[u] = 1;
                for (int i = 0; i < k; i++) {
                    int v = comp[i];
                    for (int t = start[v]; t < start[v + 1]; t++) { int x = adj[t]; if (!removed[x] && x != par[v]) { par[x] = v; dep[x] = dep[v] + 1; comp[k++] = x; } }
                }
                long[] h = new long[dep[comp[k - 1]] + 1];
                for (int i = 0; i < k; i++) h[dep[comp[i]]]++;
                hist.add(h);
            }
            hist.sort((a, b) -> Integer.compare(a.length, b.length));
            int md = 0;
            cnt[0] = 1;
            for (long[] h : hist) {
                for (int b = 0; b <= md; b++) pre[b + 1] = pre[b] + cnt[b];
                for (int a = 1; a < h.length; a++) {
                    int lo = Math.max(0, k1 - a), hi = Math.min(md, k2 - a);
                    if (lo <= hi) ans += h[a] * (pre[hi + 1] - pre[lo]);
                }
                for (int a = 1; a < h.length; a++) cnt[a] += h[a];
                md = Math.max(md, h.length - 1);
            }
            for (int b = 0; b <= md; b++) cnt[b] = 0;          // reset only what was used
            for (int j = start[c]; j < start[c + 1]; j++) if (!removed[adj[j]]) work[wTop++] = adj[j];
        }
        out.println(ans);
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

Test 1: a path of 5 vertices has $5-\ell$ paths of length $\ell$: lengths in $[2,3]$ give $3 + 2 = 5$. Test 2: the tree $1$–$2$, $2$–$3$, $2$–$4$, $4$–$5$ has 4 paths of length 1, 4 of length 2 ($1$–$3$, $1$–$4$, $3$–$4$, $2$–$5$) and 2 of length 3; $[1,4]$ counts all 10.

<!-- test
in:
5 2 3
1 2
2 3
3 4
4 5
out:
5
-->
<!-- test
in:
5 1 4
1 2
2 3
2 4
4 5
out:
10
-->
<!-- test
in:
5 2 2
1 2
2 3
2 4
4 5
out:
4
-->

</details>

### Example 4 — Xenia and Tree · ★ 2400

- **Source:** [CF 342E · Xenia and Tree](https://codeforces.com/problemset/problem/342/E) — 2400
- **Difficulty:** 2400
- **Problem:** $n, m \le 10^5$. Initially vertex 1 is red and all others blue. Queries: paint a vertex red; report the distance from $v$ to the nearest red vertex.
- **Thinking from first principles:** a BFS per query is $O(nm)$. Offline square-root rebuilding works ($O(m\sqrt n)$), but the centroid tree gives a clean $O(\log n)$: by §1.4, the nearest red vertex to $v$ is found by trying each centroid ancestor $c$ of $v$ as the "meeting point": $d(v, c) + best(c)$. Painting $u$ red lowers $best(c)$ to $d(u, c)$ for each centroid ancestor $c$ of $u$. Since $d(v,c) + d(c,u) \ge d(v,u)$ with equality at the centroid LCA, the minimum is exact.

<details><summary>Solution</summary>

Decompose once; store `cpar`, `clev` and `cd[level][v]` = distance from $v$ to its centroid ancestor at that level. Each operation walks $\le 18$ ancestors. $O((n + m)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; adj[a].push_back(b); adj[b].push_back(a); }
    int LOG = 1; while ((1 << LOG) <= n) LOG++;
    vector<vector<int>> cd(LOG + 1, vector<int>(n + 1, 0));
    vector<char> removed(n + 1, 0);
    vector<int> par(n + 1, 0), sz(n + 1), cpar(n + 1, 0), clev(n + 1, 0), comp;
    vector<array<int, 3>> work = {{1, 0, 0}};              // (entry, centroid parent, level)
    while (!work.empty()) {
        auto [r, cp, lev] = work.back(); work.pop_back();
        comp.clear(); comp.push_back(r); par[r] = 0;
        for (size_t i = 0; i < comp.size(); i++) {
            int v = comp[i];
            for (int u : adj[v]) if (!removed[u] && u != par[v]) { par[u] = v; comp.push_back(u); }
        }
        int mm = comp.size();
        for (int v : comp) sz[v] = 1;
        for (int i = mm - 1; i > 0; i--) sz[par[comp[i]]] += sz[comp[i]];
        int c = r;
        for (bool moved = true; moved; ) {
            moved = false;
            for (int u : adj[c]) if (!removed[u] && u != par[c] && 2 * sz[u] > mm) { c = u; moved = true; break; }
        }
        cpar[c] = cp; clev[c] = lev;
        comp.clear(); comp.push_back(c); par[c] = 0; cd[lev][c] = 0;   // distances from c inside its component
        for (size_t i = 0; i < comp.size(); i++) {
            int v = comp[i];
            for (int u : adj[v]) if (!removed[u] && u != par[v]) { par[u] = v; cd[lev][u] = cd[lev][v] + 1; comp.push_back(u); }
        }
        removed[c] = 1;
        for (int u : adj[c]) if (!removed[u]) work.push_back({u, c, lev + 1});
    }
    const int INF = 1e9;
    vector<int> best(n + 1, INF);
    auto paint = [&](int v) { for (int c = v, l = clev[v]; c; c = cpar[c], l--) best[c] = min(best[c], cd[l][v]); };
    auto query = [&](int v) { int res = INF; for (int c = v, l = clev[v]; c; c = cpar[c], l--) res = min(res, best[c] + cd[l][v]); return res; };
    paint(1);
    string outs;
    while (m--) {
        int t, v; cin >> t >> v;
        if (t == 1) paint(v);
        else { outs += to_string(query(v)); outs += '\n'; }
    }
    cout << outs;
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
        int LOG = 1; while ((1 << LOG) <= n) LOG++;
        int[][] cd = new int[LOG + 1][n + 1];
        boolean[] removed = new boolean[n + 1];
        int[] par = new int[n + 1], sz = new int[n + 1], cpar = new int[n + 1], clev = new int[n + 1], comp = new int[n];
        int[] wv = new int[n], wp = new int[n], wl = new int[n];
        int wTop = 0;
        wv[wTop] = 1; wp[wTop] = 0; wl[wTop++] = 0;
        while (wTop > 0) {
            wTop--;
            int r = wv[wTop], cp = wp[wTop], lev = wl[wTop];
            int mm = 0;
            comp[mm++] = r; par[r] = 0;
            for (int i = 0; i < mm; i++) {
                int v = comp[i];
                for (int j = start[v]; j < start[v + 1]; j++) { int u = adj[j]; if (!removed[u] && u != par[v]) { par[u] = v; comp[mm++] = u; } }
            }
            for (int i = 0; i < mm; i++) sz[comp[i]] = 1;
            for (int i = mm - 1; i > 0; i--) sz[par[comp[i]]] += sz[comp[i]];
            int c = r;
            for (boolean moved = true; moved; ) {
                moved = false;
                for (int j = start[c]; j < start[c + 1]; j++) {
                    int u = adj[j];
                    if (!removed[u] && u != par[c] && 2 * sz[u] > mm) { c = u; moved = true; break; }
                }
            }
            cpar[c] = cp; clev[c] = lev;
            int[] d = cd[lev];
            int k = 0;
            comp[k++] = c; par[c] = 0; d[c] = 0;
            for (int i = 0; i < k; i++) {
                int v = comp[i];
                for (int j = start[v]; j < start[v + 1]; j++) { int u = adj[j]; if (!removed[u] && u != par[v]) { par[u] = v; d[u] = d[v] + 1; comp[k++] = u; } }
            }
            removed[c] = true;
            for (int j = start[c]; j < start[c + 1]; j++) if (!removed[adj[j]]) { wv[wTop] = adj[j]; wp[wTop] = c; wl[wTop++] = lev + 1; }
        }
        final int INF = 1_000_000_000;
        int[] best = new int[n + 1];
        Arrays.fill(best, INF);
        for (int c = 1, l = clev[1]; c != 0; c = cpar[c], l--) best[c] = Math.min(best[c], cd[l][1]);
        StringBuilder sb = new StringBuilder();
        for (int q = 0; q < m; q++) {
            int t = in.nextInt(), v = in.nextInt();
            if (t == 1) { for (int c = v, l = clev[v]; c != 0; c = cpar[c], l--) best[c] = Math.min(best[c], cd[l][v]); }
            else {
                int res = INF;
                for (int c = v, l = clev[v]; c != 0; c = cpar[c], l--) res = Math.min(res, best[c] + cd[l][v]);
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

`cd` needs one row per level; levels go up to $\lfloor\log_2 n\rfloor$, so $LOG + 1$ rows are safe. Test 1: tree $1$–$2$, $2$–$3$, $2$–$4$, $4$–$5$. Only 1 is red: $d(1,5) = 3$. Paint 3: $5$ is still at distance 3 from both 1 and 3; vertex 4 is at distance 2. Paint 5: vertex 4 is at distance 1.

<!-- test
in:
5 6
1 2
2 3
2 4
4 5
2 5
2 1
1 3
2 4
1 5
2 4
out:
3
0
2
1
-->
<!-- test
in:
1 2
2 1
1 1
out:
0
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Recompute sizes inside the current component** (ignoring removed vertices) every time — sizes from the original rooting are wrong after removals.
2. **Walk to the centroid with "child size $> m/2$" using the component's own parent pointers**; comparing with `sz[u] > m/2` in integer division vs `2*sz[u] > m` differs for odd $m$ — use the multiplication form.
3. **Inclusion–exclusion must measure the subtracted branch from the centroid** (arm lengths include the edge to the centroid), otherwise the subtraction does not cancel exactly the same-branch pairs.
4. **The centroid itself is an arm of length 0** — forgetting it misses every path with an endpoint at the centroid.
5. **Linear-per-level counting needs children sorted by depth** (Example 3); without it, a star of long paths makes the prefix-sum rebuilds quadratic.
6. **Reset count arrays only up to the depth you used**, never with a full `fill` of size $n$ per centroid ($O(n)$ per centroid is $O(n^2)$).
7. **Distance tables:** `cd[level][v]` with level-major layout is compact and cache-friendly; per-vertex `vector`s of ancestors are fine too but allocate more.
8. **Recursion depth** of centroid decomposition itself is only $O(\log n)$, but the DFS *inside* a component can be $O(n)$ deep — the iterative BFS avoids both problems.
9. **Java**: sorting `long[]` arms in Example-§3 style should be shuffled first (adversarial weights can be crafted); `ArrayList<long[]>` of histograms is fine because total length is $O(n)$ per level.
10. **Two centroids**: either is fine for the complexity; only output-format problems (Example 1) care.

## 7. Going further (toward 2400–2600+)

- **Paths with bitmask/XOR/parity properties**: count palindromic-able paths with letter masks — [CF 914E · Palindromes in a Tree](https://codeforces.com/problemset/problem/914/E) — 2400 (also propagates counts back to every vertex on the path).
- **Two-criteria paths** ("length $\le L$ and weight $\le W$"): centroid + sort by one key + Fenwick on the other — [CF 293E · Close Vertices](https://codeforces.com/problemset/problem/293/E) — 2700.
- **Numbers read along paths** (concatenation modulo $M$ with modular inverses on the way up): [CF 715C · Digit Tree](https://codeforces.com/problemset/problem/715/C) — 2700.
- **Binary search on the answer + centroid + monotone deque** for "median/average on a path with length in $[L, R]$": [CF 150E · Freezing with Style](https://codeforces.com/problemset/problem/150/E) — 3000.
- **Products of path weights with balance constraints** (centroid + BIT, inclusion–exclusion on two inequalities): [CF 833D · Red-Black Cobweb](https://codeforces.com/problemset/problem/833/D) — 2800.
- **Dynamic centroid tree**: point updates with per-centroid Fenwick trees indexed by distance — "sum of values within distance $k$ of $v$" online in $O(\log^2 n)$.
- Centroid decomposition is also the standard way to build a **balanced binary search** over tree vertices in interactive problems ("is the hidden vertex in this component?").
- Revision: [cheat sheet](../99-Cheat-Sheets/10-trees-cheatsheet.md).

## 8. Practice ladder

**1600–2100**
- [ ] [CSES 2079 · Finding a Centroid](https://cses.fi/problemset/task/2079)
- [ ] [CF 161D · Distance in Tree](https://codeforces.com/problemset/problem/161/D) — 1800 — also solvable by $O(nk)$ DP; do it both ways
- [ ] [CSES 2080 · Fixed-Length Paths I](https://cses.fi/problemset/task/2080)
- [ ] [CF 321C · Ciel the Commander](https://codeforces.com/problemset/problem/321/C) — 2100
- [ ] [CF 1790F · Timofey and Black-White Tree](https://codeforces.com/problemset/problem/1790/F) — 2100

**2100–2400**
- [ ] [CSES 2081 · Fixed-Length Paths II](https://cses.fi/problemset/task/2081)
- [ ] [CF 1156D · 0-1-Tree](https://codeforces.com/problemset/problem/1156/D) — 2200
- [ ] [CF 342E · Xenia and Tree](https://codeforces.com/problemset/problem/342/E) — 2400
- [ ] [CF 914E · Palindromes in a Tree](https://codeforces.com/problemset/problem/914/E) — 2400
- [ ] [CF 990G · GCD Counting](https://codeforces.com/problemset/problem/990/G) — 2400

**2400+**
- [ ] [CF 293E · Close Vertices](https://codeforces.com/problemset/problem/293/E) — 2700
- [ ] [CF 715C · Digit Tree](https://codeforces.com/problemset/problem/715/C) — 2700
- [ ] [CF 833D · Red-Black Cobweb](https://codeforces.com/problemset/problem/833/D) — 2800
- [ ] [CF 150E · Freezing with Style](https://codeforces.com/problemset/problem/150/E) — 3000

## 9. LeetCode / FAANG cross-reference

Rare in interviews — the technique is long and specialised. The nearest interview problems are solvable with simpler tools:

- [LC 1617 · Count Subtrees With Max Distance Between Cities](https://leetcode.com/problems/count-subtrees-with-max-distance-between-cities/) — Hard — $n \le 15$, brute force over subsets with diameters; at scale, path counting is where centroid decomposition starts.
- [LC 834 · Sum of Distances in Tree](https://leetcode.com/problems/sum-of-distances-in-tree/) — Hard — rerooting DP; the centroid-tree "sum of distances to marked set" is its dynamic generalisation.

## 10. Self-check

1. Why is every path handled exactly once by centroid decomposition?
2. Prove that each vertex belongs to $O(\log n)$ components.
3. Why must the centroid be counted as an arm of length 0?
4. In inclusion–exclusion, what goes wrong if branch arms are measured from the branch root instead of from the centroid?
5. Why does processing children by increasing depth make exact-length counting linear per level?
6. State and prove the centroid-tree LCA property used for nearest-marked queries.
7. What memory does the distance table use for $n = 10^5$, and how would you reduce it?

<details><summary>Answers</summary>

1. A path stays inside a single component until one of its vertices is chosen as a centroid; at that moment it passes through that centroid and is counted there; afterwards it is split and never seen whole again.
2. Each time a vertex survives into a sub-component, the component size at least halves; sizes start at $n$ and are $\ge 1$.
3. Paths with one endpoint at the centroid consist of a single arm; pairing with the length-0 arm counts them in the same formula.
4. The subtracted pairs would have different lengths than the pairs counted in "all arms", so the subtraction would remove the wrong number — some cross pairs survive or some same-branch pairs are not cancelled.
5. Rebuilding prefix sums costs the current max depth, which (after sorting) is at most the depth of the child being processed, which is at most its size. Summed over children: linear in the component.
6. $u$ and $v$ are in the same component until the first removed vertex on their path, which is their centroid-tree LCA $w$; so the path passes through $w$ and $d(u,v) = d(u,w) + d(w,v)$. Every other centroid ancestor $c$ gives $d(u,c) + d(c,v) \ge d(u,v)$ by the triangle inequality.
7. $(\lfloor\log_2 n\rfloor + 2)\cdot(n+1)$ ints ≈ $1.8\cdot10^6$ ints ≈ 7 MB. Store per-vertex ancestor distances only for actual ancestors (a jagged array of total size $\sum (\text{level}+1)$), or recompute distances with an $O(1)$ LCA instead of storing them.

</details>
