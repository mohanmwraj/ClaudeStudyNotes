# Virtual (auxiliary) trees

> **Band:** 🟠 2200 – 🔴 2600 · **Priority:** ⚡ · **FAANG:** none · **Prerequisites:** [LCA (preorder + sparse table)](02-lca-and-binary-lifting.md), [Euler tour / preorder](01-tree-basics-diameter-center-euler-tour.md), [tree DP](../06-Dynamic-Programming/08-tree-dp-and-rerooting.md), [sorting](../01-Foundations/05-sorting-and-comparators.md)
> **You can say you know this when:** you can build the virtual tree of $k$ key vertices in $O(k\log k)$ by the "sort, add adjacent LCAs, sort again" method, prove why it is correct, and rewrite an $O(n)$-per-query tree DP so it runs on the virtual tree in $O(k\log k)$ per query.

## 1. First principles — why this works

### 1.1 The problem class

A tree with $n$ vertices, and many queries, each naming a set $K$ of $k$ **key vertices**, with $\sum k$ bounded (say $\le 2\cdot10^5$). Each query is answered by some tree DP: "cut the key vertices from the root at minimum cost", "how many vertices must be removed to separate all key vertices", "count pairs of keys whose path contains no other key"… Running the DP on the whole tree costs $O(n)$ per query, $O(nq)$ total — too slow when $q$ is large even though each query is small.

### 1.2 What actually matters for one query

Root the tree. Look at a single query:

- a subtree containing no key vertex is irrelevant to almost every such DP (it contributes a neutral value);
- a chain of non-key vertices with exactly one child that matters can be contracted to a single edge carrying an aggregate of the chain (its length, its cheapest edge, …).

What remains are the key vertices and the **branching points** where key vertices from different branches meet — the pairwise LCAs. That compressed tree is the **virtual tree** (also called the auxiliary tree):

$$V' = K \cup \{\mathrm{lca}(u, v) : u, v \in K\},$$

with an edge from every $v \in V'$ (except the top) to its deepest proper ancestor in $V'$.

### 1.3 Only adjacent LCAs are needed

There are $\binom{k}{2}$ pairs, but:

**Lemma 1.** Sort $K$ by preorder time: $x_1, \dots, x_k$. Then $V' = K \cup \{\mathrm{lca}(x_t, x_{t+1}) : 1 \le t < k\}$. In particular $\lvert V'\rvert \le 2k - 1$.

*Proof.* Take $i < j$ and $w = \mathrm{lca}(x_i, x_j)$. If $x_i = w$, then $w \in K$. Otherwise let $c$ be the child of $w$ whose subtree contains $x_i$. All $x_t$ with $i \le t \le j$ lie in subtree($w$) (their preorder times are between those of $x_i$ and $x_j$). Let $t$ be the largest index $\le j$ with $x_t$ in subtree($c$); $t < j$ because $x_j$ is not in subtree($c$). Then $x_{t+1}$ is in subtree($w$) but not in subtree($c$), so $\mathrm{lca}(x_t, x_{t+1}) = w$. $\blacksquare$

**Lemma 2 (closure).** $V'$ is closed under LCA: the LCA of two LCAs of key pairs is itself the LCA of a key pair (the LCA of any vertex set equals the LCA of its two preorder-extreme members). So the virtual tree is well defined.

### 1.4 Edges: one more sort, one LCA per vertex

**Lemma 3.** Sort $V'$ by preorder time: $y_1, \dots, y_m$. For $i \ge 2$, the virtual parent of $y_i$ is $\mathrm{lca}(y_{i-1}, y_i)$; $y_1$ is the top (an ancestor of everything).

*Proof.* Let $p$ be the deepest proper ancestor of $y_i$ in $V'$ (it exists: $y_1 = \mathrm{lca}(V')$ is an ancestor of $y_i$). Since $tin(p) \le tin(y_{i-1}) < tin(y_i) \le tout(p)$, $y_{i-1}$ lies in subtree($p$), so $\ell = \mathrm{lca}(y_{i-1}, y_i)$ lies on the path $p \to y_i$. $\ell \ne y_i$ (a descendant cannot come earlier in preorder), and $\ell \in V'$ by closure. So $\ell$ is a proper ancestor of $y_i$ in $V'$ at least as deep as $p$: $\ell = p$. $\blacksquare$

**Algorithm (sort twice).**

1. sort $K$ by $tin$; append $\mathrm{lca}(x_t, x_{t+1})$ for adjacent pairs;
2. sort the result by $tin$, remove duplicates → $y_1..y_m$;
3. $vpar(y_i) = \mathrm{lca}(y_{i-1}, y_i)$ for $i \ge 2$.

With an $O(1)$ LCA (preorder + sparse table, file 02), the cost is dominated by sorting: $O(k\log k)$ per query. Because $y$ is sorted by preorder, **scanning it backwards visits children before parents** — exactly the order a bottom-up DP needs, no adjacency lists required. (A one-sort alternative maintains the current root-to-$y$ path on a stack; it is equivalent and slightly faster, but harder to get right.)

### 1.5 DP on the virtual tree

A virtual edge $(vpar(v), v)$ stands for a real path. Its "content" must be summarised for the DP:

- length: $D(v) - D(vpar(v))$ with weighted depths;
- cheapest edge on the path: binary lifting (file 02), or — if the DP really only needs the cheapest edge on the *whole root path* — a simple prefix minimum from the root (Example 2);
- whether there are interior vertices at all: $\mathrm{dep}(v) - \mathrm{dep}(vpar(v)) \ge 2$ (Example 3).

Two habits keep it $O(k\log k)$: **reset only the vertices of $V'$** after each query (never `fill` size-$n$ arrays), and read every per-vertex array through vertex ids so that one global array of size $n$ is reused by all queries.

### 1.6 Where $\sum k$ comes from

Sometimes the key sets are not queries at all: **colour classes** partition the vertices, so $\sum_{\text{colours}} \lvert K_c\rvert = n$ and one virtual tree per colour costs $O(n\log n)$ in total (Example 1). The same trick works for "for every value $x$, the vertices with value $x$" and for divisors ("vertices whose value is divisible by $d$", $\sum$ over $d$ is $O(n \cdot \max \#\text{divisors})$).

## 2. Formulas, definitions and identities

| Formula | Meaning |
|---|---|
| $V' = K \cup \{\mathrm{lca}(x_t,x_{t+1})\}$, $x$ sorted by $tin$ | Lemma 1 |
| $\lvert V'\rvert \le 2k - 1$ | at most $k - 1$ extra vertices |
| $vpar(y_i) = \mathrm{lca}(y_{i-1}, y_i)$ | Lemma 3 |
| $\mathrm{lca}(S) = \mathrm{lca}(\arg\min_S tin, \arg\max_S tin)$ | extreme preorder members |
| weight of virtual edge $= D(v) - D(vpar(v))$ | weighted depth difference |
| Steiner tree weight $= \sum_{v \ne y_1} (D(v) - D(vpar(v))) = \tfrac12 \sum_{t=1}^{k} d(x_t, x_{t+1 \bmod k})$ | the DFS tour visiting keys in preorder crosses every Steiner edge exactly twice |
| per query: $O(k \log k)$ time; total $O(n\log n + \sum k \log k)$ | sorting dominates |

## 3. Implementation (C++ and Java)

### 3.1 Build the virtual tree; report its size and the Steiner tree weight

Input: `n`, $n-1$ weighted edges `a b w`, `q`, then each query as `k v_1 … v_k` (distinct vertices). Output per query: $\lvert V'\rvert$ and the total weight of the smallest connected subtree containing all key vertices. Vertices are handled through their preorder index, so sorting and deduplicating are plain integer operations.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<vector<pair<int, ll>>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; ll w; cin >> a >> b >> w; adj[a].push_back({b, w}); adj[b].push_back({a, w}); }
    // preorder, weighted depth, O(1) LCA on tin indices (file 02, section 3.2)
    vector<int> par(n + 1, 0), tin(n + 1), order, st = {1};
    vector<ll> D(n + 1, 0);
    while (!st.empty()) {
        int v = st.back(); st.pop_back();
        tin[v] = order.size(); order.push_back(v);
        for (auto [u, w] : adj[v]) if (u != par[v]) { par[u] = v; D[u] = D[v] + w; st.push_back(u); }
    }
    int LOG = 1; while ((1 << LOG) <= n) LOG++;
    vector<vector<int>> sp(LOG, vector<int>(n, 0));
    for (int i = 1; i < n; i++) sp[0][i] = tin[par[order[i]]];
    for (int j = 1; j < LOG; j++)
        for (int i = 0; i + (1 << j) <= n; i++) sp[j][i] = min(sp[j - 1][i], sp[j - 1][i + (1 << (j - 1))]);
    auto lcaT = [&](int a, int b) {                       // a, b are tin indices; returns a tin index
        if (a == b) return a;
        if (a > b) swap(a, b);
        a++;
        int j = __lg(b - a + 1);
        return min(sp[j][a], sp[j][b - (1 << j) + 1]);
    };
    int q; cin >> q;
    vector<int> vpar(n, -1);
    while (q--) {
        int k; cin >> k;
        vector<int> ys(k);
        for (int& y : ys) { int v; cin >> v; y = tin[v]; }
        sort(ys.begin(), ys.end());
        for (int i = 0; i + 1 < k; i++) ys.push_back(lcaT(ys[i], ys[i + 1]));
        sort(ys.begin(), ys.end());
        ys.erase(unique(ys.begin(), ys.end()), ys.end());
        ll weight = 0;
        for (size_t i = 1; i < ys.size(); i++) {
            vpar[ys[i]] = lcaT(ys[i - 1], ys[i]);
            weight += D[order[ys[i]]] - D[order[vpar[ys[i]]]];
        }
        cout << ys.size() << ' ' << weight << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[][] sp;
    static int lcaT(int a, int b) {
        if (a == b) return a;
        if (a > b) { int t = a; a = b; b = t; }
        a++;
        int j = 31 - Integer.numberOfLeadingZeros(b - a + 1);
        return Math.min(sp[j][a], sp[j][b - (1 << j) + 1]);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        int[] ea = new int[n - 1], eb = new int[n - 1], start = new int[n + 2];
        long[] ew = new long[n - 1];
        for (int i = 0; i < n - 1; i++) { ea[i] = in.nextInt(); eb[i] = in.nextInt(); ew[i] = in.nextLong(); start[ea[i] + 1]++; start[eb[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        long[] wt = new long[2 * (n - 1)];
        for (int i = 0; i < n - 1; i++) {
            wt[fill[ea[i]]] = ew[i]; adj[fill[ea[i]]++] = eb[i];
            wt[fill[eb[i]]] = ew[i]; adj[fill[eb[i]]++] = ea[i];
        }
        int[] par = new int[n + 1], tin = new int[n + 1], order = new int[n], st = new int[n];
        long[] D = new long[n + 1];
        int top = 0, cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top];
            tin[v] = cnt; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) { int u = adj[j]; if (u != par[v]) { par[u] = v; D[u] = D[v] + wt[j]; st[top++] = u; } }
        }
        int LOG = 1; while ((1 << LOG) <= n) LOG++;
        sp = new int[LOG][n];
        for (int i = 1; i < n; i++) sp[0][i] = tin[par[order[i]]];
        for (int j = 1; j < LOG; j++)
            for (int i = 0; i + (1 << j) <= n; i++) sp[j][i] = Math.min(sp[j - 1][i], sp[j - 1][i + (1 << (j - 1))]);
        int q = in.nextInt();
        int[] ys = new int[2 * n], vpar = new int[n];
        Random rnd = new Random(99);
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            int k = in.nextInt();
            for (int i = 0; i < k; i++) ys[i] = tin[in.nextInt()];
            Arrays.sort(ys, 0, k);
            int m = k;
            for (int i = 0; i + 1 < k; i++) ys[m++] = lcaT(ys[i], ys[i + 1]);
            for (int i = m - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); int t = ys[i]; ys[i] = ys[j]; ys[j] = t; }
            Arrays.sort(ys, 0, m);
            int u = 0;
            for (int i = 0; i < m; i++) if (i == 0 || ys[i] != ys[i - 1]) ys[u++] = ys[i];
            long weight = 0;
            for (int i = 1; i < u; i++) {
                vpar[ys[i]] = lcaT(ys[i - 1], ys[i]);
                weight += D[order[ys[i]]] - D[order[vpar[ys[i]]]];
            }
            sb.append(u).append(' ').append(weight).append('\n');
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

The first sort in Java runs on preorder indices read from the input; the second sort is shuffled first (both are `int[]` sorts — see the anti-quicksort note in the pitfalls). Test 1: tree $1$–$2$ (2), $1$–$3$ (5), $2$–$4$ (1), $2$–$5$ (4), $3$–$6$ (3). Keys $\{4,5,6\}$: $V' = \{4,5,6,2,1\}$, Steiner weight $1 + 4 + 2 + 5 + 3 = 15$. Keys $\{4,5\}$: $V' = \{2,4,5\}$, weight 5. Keys $\{6\}$: one vertex, weight 0. Keys $\{1,6,4\}$: both adjacent LCAs are 1 itself, so $V' = \{1,4,6\}$ and the weight is $(2+1) + (5+3) = 11$.

<!-- test
in:
6
1 2 2
1 3 5
2 4 1
2 5 4
3 6 3
4
3 4 5 6
2 4 5
1 6
3 1 6 4
out:
5 15
3 5
1 0
3 11
-->
<!-- test
in:
1
1
1 1
out:
1 0
-->

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| many queries, each with a vertex set of size $k_i$, and "$\sum k_i \le$ something" in the constraints | virtual tree per query |
| per-query tree DP that would be $O(n)$ and only depends on the key vertices and their branching | build the virtual tree, run the DP on it |
| "for each colour / value / divisor class, …" with classes partitioning the vertices | one virtual tree per class, total $O(n\log n)$ |
| "minimal subtree connecting these vertices" (size/weight) | Steiner tree = sum of virtual edges, or half the cyclic tour in preorder |
| pairs of key vertices with a condition on the path between them | DP over the virtual tree counting "visible" keys |
| set sizes are not bounded in total | not this — think [centroid decomposition](05-centroid-decomposition.md) or offline data structures |

## 5. Worked examples (graded)

### Example 1 — Count Paths · ★ 2000

- **Source:** [CF 1923E · Count Paths](https://codeforces.com/problemset/problem/1923/E) — 2000
- **Difficulty:** 2000
- **Problem:** a tree on $n \le 2\cdot10^5$ vertices (many test cases, $\sum n \le 2\cdot10^5$), each vertex has a colour. Count pairs $u < v$ of the **same colour** such that no other vertex of that colour lies on the path between them.
- **Thinking from first principles:** colours are independent, and a colour class $S$ partitions the vertex set, so $\sum_c \lvert S_c\rvert = n$: one virtual tree per colour is affordable. In the virtual tree of $S$, every real vertex of colour $c$ that lies on a path between two vertices of $S$ is itself a virtual vertex. So "no other vertex of the colour on the path" becomes "no other *key* virtual vertex on the virtual path". Count bottom-up: let $up(v)$ be the number of key vertices reachable *downwards* from $v$ through non-key vertices only. A key vertex pairs with everything visible below it and then blocks; a non-key vertex pairs up what is visible through its different children.

<details><summary>Solution</summary>

For each child $c$ of $v$ in the virtual tree let $a_c = 1$ if $c$ is key, else $up(c)$.

- $v$ key: answer $\mathrel{+}= \sum_c a_c$; (then $v$ looks like $a = 1$ to its parent).
- $v$ non-key: answer $\mathrel{+}= \sum_{c < c'} a_c a_{c'}$, and $up(v) = \sum_c a_c$.

Bucket the vertices by colour while scanning the global preorder, so each bucket is already sorted by $tin$; process buckets of size $\ge 2$. Children-before-parent order is the reversed sorted virtual vertex list; accumulate $\sum a$ and $\sum a^2$ per parent to get $\sum_{c<c'} a_ca_{c'} = \frac{(\sum a)^2 - \sum a^2}{2}$. $O(n\log n)$ per test.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        int n; cin >> n;
        vector<int> col(n + 1);
        for (int v = 1; v <= n; v++) cin >> col[v];
        vector<vector<int>> adj(n + 1);
        for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; adj[a].push_back(b); adj[b].push_back(a); }
        vector<int> par(n + 1, 0), tin(n + 1), order, st = {1};
        while (!st.empty()) {
            int v = st.back(); st.pop_back();
            tin[v] = order.size(); order.push_back(v);
            for (int u : adj[v]) if (u != par[v]) { par[u] = v; st.push_back(u); }
        }
        int LOG = 1; while ((1 << LOG) <= n) LOG++;
        vector<vector<int>> sp(LOG, vector<int>(n, 0));
        for (int i = 1; i < n; i++) sp[0][i] = tin[par[order[i]]];
        for (int j = 1; j < LOG; j++)
            for (int i = 0; i + (1 << j) <= n; i++) sp[j][i] = min(sp[j - 1][i], sp[j - 1][i + (1 << (j - 1))]);
        auto lcaT = [&](int a, int b) {
            if (a == b) return a;
            if (a > b) swap(a, b);
            a++;
            int j = __lg(b - a + 1);
            return min(sp[j][a], sp[j][b - (1 << j) + 1]);
        };
        vector<vector<int>> bucket(n + 1);
        for (int i = 0; i < n; i++) bucket[col[order[i]]].push_back(i);   // already sorted by tin
        vector<char> isKey(n, 0);
        vector<ll> sumA(n, 0), sumA2(n, 0);
        vector<int> vpar(n, -1);
        ll ans = 0;
        vector<int> ys;
        for (int c = 1; c <= n; c++) {
            auto& K = bucket[c];
            if (K.size() < 2) continue;
            ys = K;
            for (size_t i = 0; i + 1 < K.size(); i++) ys.push_back(lcaT(K[i], K[i + 1]));
            sort(ys.begin(), ys.end());
            ys.erase(unique(ys.begin(), ys.end()), ys.end());
            for (int y : K) isKey[y] = 1;
            for (size_t i = 1; i < ys.size(); i++) vpar[ys[i]] = lcaT(ys[i - 1], ys[i]);
            for (int i = (int)ys.size() - 1; i >= 0; i--) {           // children before parents
                int y = ys[i];
                ll a;
                if (isKey[y]) { ans += sumA[y]; a = 1; }
                else { ans += (sumA[y] * sumA[y] - sumA2[y]) / 2; a = sumA[y]; }
                if (i > 0) { sumA[vpar[y]] += a; sumA2[vpar[y]] += a * a; }
            }
            for (int y : ys) { isKey[y] = 0; sumA[y] = 0; sumA2[y] = 0; }   // reset only what we touched
        }
        cout << ans << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[][] sp;
    static int lcaT(int a, int b) {
        if (a == b) return a;
        if (a > b) { int t = a; a = b; b = t; }
        a++;
        int j = 31 - Integer.numberOfLeadingZeros(b - a + 1);
        return Math.min(sp[j][a], sp[j][b - (1 << j) + 1]);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = in.nextInt();
        Random rnd = new Random(5);
        StringBuilder sb = new StringBuilder();
        while (t-- > 0) {
            int n = in.nextInt();
            int[] col = new int[n + 1];
            for (int v = 1; v <= n; v++) col[v] = in.nextInt();
            int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2];
            for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
            for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
            int[] adj = new int[2 * (n - 1)], fill = start.clone();
            for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
            int[] par = new int[n + 1], tin = new int[n + 1], order = new int[n], st = new int[n];
            int top = 0, cnt = 0;
            st[top++] = 1;
            while (top > 0) {
                int v = st[--top];
                tin[v] = cnt; order[cnt++] = v;
                for (int j = start[v]; j < start[v + 1]; j++) if (adj[j] != par[v]) { par[adj[j]] = v; st[top++] = adj[j]; }
            }
            int LOG = 1; while ((1 << LOG) <= n) LOG++;
            sp = new int[LOG][n];
            for (int i = 1; i < n; i++) sp[0][i] = tin[par[order[i]]];
            for (int j = 1; j < LOG; j++)
                for (int i = 0; i + (1 << j) <= n; i++) sp[j][i] = Math.min(sp[j - 1][i], sp[j - 1][i + (1 << (j - 1))]);
            int[] bStart = new int[n + 2];                       // buckets by colour, in preorder
            for (int v = 1; v <= n; v++) bStart[col[v] + 1]++;
            for (int c = 1; c <= n + 1; c++) bStart[c] += bStart[c - 1];
            int[] bucket = new int[n], bf = bStart.clone();
            for (int i = 0; i < n; i++) bucket[bf[col[order[i]]]++] = i;
            boolean[] isKey = new boolean[n];
            long[] sumA = new long[n], sumA2 = new long[n];
            int[] vpar = new int[n], ys = new int[2 * n];
            long ans = 0;
            for (int c = 1; c <= n; c++) {
                int lo = bStart[c], k = bStart[c + 1] - lo;
                if (k < 2) continue;
                int m = 0;
                for (int i = 0; i < k; i++) { ys[m++] = bucket[lo + i]; isKey[bucket[lo + i]] = true; }
                for (int i = 0; i + 1 < k; i++) ys[m++] = lcaT(bucket[lo + i], bucket[lo + i + 1]);
                for (int i = m - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); int tt = ys[i]; ys[i] = ys[j]; ys[j] = tt; }
                Arrays.sort(ys, 0, m);
                int u = 0;
                for (int i = 0; i < m; i++) if (i == 0 || ys[i] != ys[i - 1]) ys[u++] = ys[i];
                for (int i = 1; i < u; i++) vpar[ys[i]] = lcaT(ys[i - 1], ys[i]);
                for (int i = u - 1; i >= 0; i--) {
                    int y = ys[i];
                    long a;
                    if (isKey[y]) { ans += sumA[y]; a = 1; }
                    else { ans += (sumA[y] * sumA[y] - sumA2[y]) / 2; a = sumA[y]; }
                    if (i > 0) { sumA[vpar[y]] += a; sumA2[vpar[y]] += a * a; }
                }
                for (int i = 0; i < u; i++) { int y = ys[i]; isKey[y] = false; sumA[y] = 0; sumA2[y] = 0; }
            }
            sb.append(ans).append('\n');
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

Test 1, case 1: path $1$–$2$–$3$ with colours $1, 2, 1$: the pair $(1,3)$ counts (vertex 2 has another colour). Case 2: a star centred at 1 (colour 1) with leaves of colour 1: the centre pairs with each leaf (3 pairs), but leaf–leaf paths pass the centre: 3. Case 3: centre colour 2 with three colour-1 leaves: all $\binom32 = 3$ leaf pairs count, centre alone: 3. Test 2: a single vertex (0); and a tree whose colour-1 vertices $\{1,3,5,6\}$ are separated only by colour-2 vertices (all 6 pairs count) plus the adjacent colour-2 pair $(2,4)$: 7.

<!-- test
in:
3
3
1 2 1
1 2
2 3
4
1 1 1 1
1 2
1 3
1 4
4
2 1 1 1
1 2
1 3
1 4
out:
1
3
3
-->
<!-- test
in:
2
1
1
6
1 2 1 2 1 1
1 2
2 3
2 4
4 5
4 6
out:
0
7
-->

</details>

### Example 2 — Cut the key vertices off the root · ★ ≈2300 (est.)

- **Source:** Original problem (a well-known classic of the Chinese olympiad training canon, often used to introduce virtual trees).
- **Difficulty:** ≈2300 (est.)
- **Problem:** a tree rooted at 1 with positive edge costs, $n \le 2.5\cdot10^5$. Each of $q$ queries names $k$ key vertices (never the root), $\sum k \le 5\cdot10^5$. Remove edges of minimum total cost so that no key vertex stays connected to the root.
- **Thinking from first principles:** on the full tree the DP is immediate: $h(v)$ = cheapest way to cut every key vertex of subtree($v$) off from $v$'s parent $= w(p(v), v)$ if $v$ is key, else $\min(w(p(v),v), \sum_c h(c))$. That is $O(n)$ per query. On the virtual tree, the edge to the virtual parent stands for a whole path, so replace $w(p(v),v)$ by "the cheapest edge on the root path of $v$", $mn(v)$ — a prefix minimum from the root, no lifting needed. Why is the *whole root path* allowed and not just the virtual edge? Cutting the cheapest edge above $v$ might lie above the virtual parent too; but then it also separates the virtual parent's other branches, and the DP at the parent (which can choose $mn(\text{parent}) \le$ that edge) is at least as good — so the minimum is unchanged, and the DP never undercounts a feasible solution.

<details><summary>Solution</summary>

Precompute $mn(v)$ (with $mn(1) = +\infty$). Per query: add the root to the key set, build the virtual tree, scan it backwards: $f(v) = mn(v)$ if $v$ is key, else $\min(mn(v), \sum_c f(c))$; the answer is $\sum$ over the root's virtual children. $O(n\log n + \sum k\log k)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<vector<pair<int, ll>>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; ll w; cin >> a >> b >> w; adj[a].push_back({b, w}); adj[b].push_back({a, w}); }
    const ll INF = LLONG_MAX / 4;
    vector<int> par(n + 1, 0), tin(n + 1), order, st = {1};
    vector<ll> mn(n + 1, INF);                              // cheapest edge on the root path
    while (!st.empty()) {
        int v = st.back(); st.pop_back();
        tin[v] = order.size(); order.push_back(v);
        for (auto [u, w] : adj[v]) if (u != par[v]) { par[u] = v; mn[u] = min(mn[v], w); st.push_back(u); }
    }
    int LOG = 1; while ((1 << LOG) <= n) LOG++;
    vector<vector<int>> sp(LOG, vector<int>(n, 0));
    for (int i = 1; i < n; i++) sp[0][i] = tin[par[order[i]]];
    for (int j = 1; j < LOG; j++)
        for (int i = 0; i + (1 << j) <= n; i++) sp[j][i] = min(sp[j - 1][i], sp[j - 1][i + (1 << (j - 1))]);
    auto lcaT = [&](int a, int b) {
        if (a == b) return a;
        if (a > b) swap(a, b);
        a++;
        int j = __lg(b - a + 1);
        return min(sp[j][a], sp[j][b - (1 << j) + 1]);
    };
    vector<char> isKey(n, 0);
    vector<ll> sub(n, 0);
    vector<int> vpar(n, -1);
    int q; cin >> q;
    while (q--) {
        int k; cin >> k;
        vector<int> ys = {0};                               // tin of the root
        for (int i = 0; i < k; i++) { int v; cin >> v; ys.push_back(tin[v]); isKey[tin[v]] = 1; }
        sort(ys.begin(), ys.end());
        int base = ys.size();
        for (int i = 0; i + 1 < base; i++) ys.push_back(lcaT(ys[i], ys[i + 1]));
        sort(ys.begin(), ys.end());
        ys.erase(unique(ys.begin(), ys.end()), ys.end());
        for (size_t i = 1; i < ys.size(); i++) vpar[ys[i]] = lcaT(ys[i - 1], ys[i]);
        for (int i = (int)ys.size() - 1; i >= 1; i--) {      // ys[0] is the root
            int y = ys[i];
            ll m = mn[order[y]];
            ll f = isKey[y] ? m : min(m, sub[y]);
            sub[vpar[y]] += f;
        }
        cout << sub[0] << '\n';
        for (int y : ys) { isKey[y] = 0; sub[y] = 0; }
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[][] sp;
    static int lcaT(int a, int b) {
        if (a == b) return a;
        if (a > b) { int t = a; a = b; b = t; }
        a++;
        int j = 31 - Integer.numberOfLeadingZeros(b - a + 1);
        return Math.min(sp[j][a], sp[j][b - (1 << j) + 1]);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        int[] ea = new int[n - 1], eb = new int[n - 1], start = new int[n + 2];
        long[] ew = new long[n - 1];
        for (int i = 0; i < n - 1; i++) { ea[i] = in.nextInt(); eb[i] = in.nextInt(); ew[i] = in.nextLong(); start[ea[i] + 1]++; start[eb[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        long[] wt = new long[2 * (n - 1)];
        for (int i = 0; i < n - 1; i++) {
            wt[fill[ea[i]]] = ew[i]; adj[fill[ea[i]]++] = eb[i];
            wt[fill[eb[i]]] = ew[i]; adj[fill[eb[i]]++] = ea[i];
        }
        final long INF = Long.MAX_VALUE / 4;
        int[] par = new int[n + 1], tin = new int[n + 1], order = new int[n], st = new int[n];
        long[] mn = new long[n + 1];
        mn[1] = INF;
        int top = 0, cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top];
            tin[v] = cnt; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) { int u = adj[j]; if (u != par[v]) { par[u] = v; mn[u] = Math.min(mn[v], wt[j]); st[top++] = u; } }
        }
        int LOG = 1; while ((1 << LOG) <= n) LOG++;
        sp = new int[LOG][n];
        for (int i = 1; i < n; i++) sp[0][i] = tin[par[order[i]]];
        for (int j = 1; j < LOG; j++)
            for (int i = 0; i + (1 << j) <= n; i++) sp[j][i] = Math.min(sp[j - 1][i], sp[j - 1][i + (1 << (j - 1))]);
        boolean[] isKey = new boolean[n];
        long[] sub = new long[n];
        int[] vpar = new int[n], ys = new int[2 * n + 2];
        Random rnd = new Random(11);
        int q = in.nextInt();
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            int k = in.nextInt();
            int m = 0;
            ys[m++] = 0;
            for (int i = 0; i < k; i++) { int y = tin[in.nextInt()]; ys[m++] = y; isKey[y] = true; }
            for (int i = m - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); int tt = ys[i]; ys[i] = ys[j]; ys[j] = tt; }
            Arrays.sort(ys, 0, m);
            int base = m;
            for (int i = 0; i + 1 < base; i++) ys[m++] = lcaT(ys[i], ys[i + 1]);
            for (int i = m - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); int tt = ys[i]; ys[i] = ys[j]; ys[j] = tt; }
            Arrays.sort(ys, 0, m);
            int u = 0;
            for (int i = 0; i < m; i++) if (i == 0 || ys[i] != ys[i - 1]) ys[u++] = ys[i];
            for (int i = 1; i < u; i++) vpar[ys[i]] = lcaT(ys[i - 1], ys[i]);
            for (int i = u - 1; i >= 1; i--) {
                int y = ys[i];
                long mm = mn[order[y]];
                long f = isKey[y] ? mm : Math.min(mm, sub[y]);
                sub[vpar[y]] += f;
            }
            sb.append(sub[0]).append('\n');
            for (int i = 0; i < u; i++) { isKey[ys[i]] = false; sub[ys[i]] = 0; }
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

Test 1: tree $1$–$2$ (5), $2$–$3$ (2), $2$–$4$ (3), $1$–$5$ (4), $5$–$6$ (1). Keys $\{3,4\}$: cutting $2$–$3$ and $2$–$4$ costs 5, cutting $1$–$2$ also 5 → 5. Keys $\{3,4,6\}$: $5 + 1 = 6$. Keys $\{2, 3\}$: 2 is key, must cut above it: 5. Keys $\{6\}$: 1.

<!-- test
in:
6
1 2 5
2 3 2
2 4 3
1 5 4
5 6 1
4
2 3 4
3 3 4 6
2 2 3
1 6
out:
5
6
5
1
-->
<!-- test
in:
4
1 2 10
2 3 1
2 4 1
2
2 3 4
1 2
out:
2
10
-->

</details>

### Example 3 — Kingdom and its Cities · ★ 2800

- **Source:** [CF 613D · Kingdom and its Cities](https://codeforces.com/problemset/problem/613/D) — 2800
- **Difficulty:** 2800
- **Problem:** a tree with $n \le 10^5$ cities; $q$ plans, each a set of $k$ important cities ($\sum k \le 10^5$). Find the minimum number of **non-important** cities to capture (remove) so that all important cities become pairwise disconnected, or $-1$ if impossible.
- **Thinking from first principles:** impossible exactly when two important cities are adjacent (nothing can be removed between them). Otherwise, on the full tree, a greedy DP works bottom-up: let $g(v)$ = number of important cities still connected to $v$ from below (0 or 1 after resolution). At an important $v$: every child branch with $g > 0$ must be cut (one removal each — there is a non-important vertex on that branch, because adjacency was excluded), then $g(v) = 1$. At a non-important $v$: if two or more branches bring an important city, removing $v$ itself fixes them all at once (cost 1), $g(v) = 0$; if exactly one, pass it up ($g(v) = 1$) — deciding later is never worse, since removing a higher vertex can serve more branches. Only key vertices and branching LCAs matter, so run it on the virtual tree.

<details><summary>Solution</summary>

Per plan: check adjacency (some important city whose parent is important), build the virtual tree, scan backwards with the DP above. $O(n\log n + \sum k\log k)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; adj[a].push_back(b); adj[b].push_back(a); }
    vector<int> par(n + 1, 0), tin(n + 1), order, st = {1};
    while (!st.empty()) {
        int v = st.back(); st.pop_back();
        tin[v] = order.size(); order.push_back(v);
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; st.push_back(u); }
    }
    int LOG = 1; while ((1 << LOG) <= n) LOG++;
    vector<vector<int>> sp(LOG, vector<int>(n, 0));
    for (int i = 1; i < n; i++) sp[0][i] = tin[par[order[i]]];
    for (int j = 1; j < LOG; j++)
        for (int i = 0; i + (1 << j) <= n; i++) sp[j][i] = min(sp[j - 1][i], sp[j - 1][i + (1 << (j - 1))]);
    auto lcaT = [&](int a, int b) {
        if (a == b) return a;
        if (a > b) swap(a, b);
        a++;
        int j = __lg(b - a + 1);
        return min(sp[j][a], sp[j][b - (1 << j) + 1]);
    };
    vector<char> imp(n + 1, 0);                             // by vertex id
    vector<int> vpar(n, -1), g(n, 0), branches(n, 0);       // by tin index
    int q; cin >> q;
    string outs;
    while (q--) {
        int k; cin >> k;
        vector<int> vs(k);
        for (int& v : vs) { cin >> v; imp[v] = 1; }
        bool bad = false;
        for (int v : vs) if (v != 1 && imp[par[v]]) bad = true;
        if (bad) { outs += "-1\n"; for (int v : vs) imp[v] = 0; continue; }
        vector<int> ys;
        for (int v : vs) ys.push_back(tin[v]);
        sort(ys.begin(), ys.end());
        for (int i = 0; i + 1 < k; i++) ys.push_back(lcaT(ys[i], ys[i + 1]));
        sort(ys.begin(), ys.end());
        ys.erase(unique(ys.begin(), ys.end()), ys.end());
        for (size_t i = 1; i < ys.size(); i++) vpar[ys[i]] = lcaT(ys[i - 1], ys[i]);
        int ans = 0;
        for (int i = (int)ys.size() - 1; i >= 0; i--) {
            int y = ys[i];
            if (imp[order[y]]) { ans += branches[y]; g[y] = 1; }       // cut every branch that still reaches here
            else if (branches[y] >= 2) { ans++; g[y] = 0; }            // remove y itself
            else g[y] = branches[y];
            if (i > 0 && g[y]) branches[vpar[y]]++;
        }
        outs += to_string(ans); outs += '\n';
        for (int y : ys) { g[y] = 0; branches[y] = 0; }
        for (int v : vs) imp[v] = 0;
    }
    cout << outs;
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[][] sp;
    static int lcaT(int a, int b) {
        if (a == b) return a;
        if (a > b) { int t = a; a = b; b = t; }
        a++;
        int j = 31 - Integer.numberOfLeadingZeros(b - a + 1);
        return Math.min(sp[j][a], sp[j][b - (1 << j) + 1]);
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
        int[] par = new int[n + 1], tin = new int[n + 1], order = new int[n], st = new int[n];
        int top = 0, cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top];
            tin[v] = cnt; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) if (adj[j] != par[v]) { par[adj[j]] = v; st[top++] = adj[j]; }
        }
        int LOG = 1; while ((1 << LOG) <= n) LOG++;
        sp = new int[LOG][n];
        for (int i = 1; i < n; i++) sp[0][i] = tin[par[order[i]]];
        for (int j = 1; j < LOG; j++)
            for (int i = 0; i + (1 << j) <= n; i++) sp[j][i] = Math.min(sp[j - 1][i], sp[j - 1][i + (1 << (j - 1))]);
        boolean[] imp = new boolean[n + 1];
        int[] vpar = new int[n], g = new int[n], branches = new int[n], ys = new int[2 * n], vs = new int[n];
        Random rnd = new Random(3);
        int q = in.nextInt();
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            int k = in.nextInt();
            for (int i = 0; i < k; i++) { vs[i] = in.nextInt(); imp[vs[i]] = true; }
            boolean bad = false;
            for (int i = 0; i < k; i++) if (vs[i] != 1 && imp[par[vs[i]]]) bad = true;
            if (bad) { sb.append("-1\n"); for (int i = 0; i < k; i++) imp[vs[i]] = false; continue; }
            int m = 0;
            for (int i = 0; i < k; i++) ys[m++] = tin[vs[i]];
            for (int i = m - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); int tt = ys[i]; ys[i] = ys[j]; ys[j] = tt; }
            Arrays.sort(ys, 0, m);
            for (int i = 0; i + 1 < k; i++) ys[m++] = lcaT(ys[i], ys[i + 1]);
            for (int i = m - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); int tt = ys[i]; ys[i] = ys[j]; ys[j] = tt; }
            Arrays.sort(ys, 0, m);
            int u = 0;
            for (int i = 0; i < m; i++) if (i == 0 || ys[i] != ys[i - 1]) ys[u++] = ys[i];
            for (int i = 1; i < u; i++) vpar[ys[i]] = lcaT(ys[i - 1], ys[i]);
            int ans = 0;
            for (int i = u - 1; i >= 0; i--) {
                int y = ys[i];
                if (imp[order[y]]) { ans += branches[y]; g[y] = 1; }
                else if (branches[y] >= 2) { ans++; g[y] = 0; }
                else g[y] = branches[y];
                if (i > 0 && g[y] != 0) branches[vpar[y]]++;
            }
            sb.append(ans).append('\n');
            for (int i = 0; i < u; i++) { g[ys[i]] = 0; branches[ys[i]] = 0; }
            for (int i = 0; i < k; i++) imp[vs[i]] = false;
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

Test 1: tree $1$–$2$, $1$–$3$, $2$–$4$, $2$–$5$, $3$–$6$, $3$–$7$. $\{4,5\}$: remove 2 → 1. $\{4,5,6,7\}$: remove 2 and 3 → 2. $\{4,6\}$: one removal (1, 2 or 3) → 1. $\{2,4\}$: adjacent → $-1$. $\{1,4,6\}$: 1 important; branches through 2 and 3 each need one cut → 2. $\{5\}$: nothing to separate → 0.

<!-- test
in:
7
1 2
1 3
2 4
2 5
3 6
3 7
6
2 4 5
4 4 5 6 7
2 4 6
2 2 4
3 1 4 6
1 5
out:
1
2
1
-1
2
0
-->
<!-- test
in:
4
1 2
2 3
3 4
2
2 1 4
2 1 3
out:
1
1
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Sort by preorder time, not by vertex id.** Working directly with $tin$ indices (as in all programs here) makes sorting, deduplication and array indexing trivial; map back with `order[]` only when you need a vertex property.
2. **Deduplicate after adding LCAs** — the same LCA appears many times, and a key vertex can itself be an LCA.
3. **Reset only touched entries.** A `fill` of size $n$ per query turns $O(\sum k\log k)$ into $O(nq)$.
4. **Add the root explicitly** when the DP needs it (Example 2); otherwise the virtual tree's top is the LCA of the keys, which may not be the root.
5. **Children-before-parents order is the reversed sorted list** — no adjacency lists, no recursion. If the DP needs all children of a node at once (e.g. a product over children), accumulate into the parent as you go.
6. **Virtual edges hide real vertices.** Decide explicitly what the DP needs from the hidden chain (length, min edge, "has an interior vertex") — Example 3's correctness depends on interior vertices existing, which the adjacency check guarantees.
7. **$O(1)$ LCA matters**: with $\sum k = 10^6$ the $O(\log n)$ lifting LCA plus sorting is still fine in C++, but in Java prefer the preorder sparse table.
8. **Java `Arrays.sort(int[])`** can be driven to quadratic time by adversarial inputs; shuffle the slice first (all Java programs above do), or sort `long`-packed keys.
9. **Answer overflow**: pair counts up to $\binom{n}{2}$ need 64-bit; $\frac{(\sum a)^2 - \sum a^2}{2}$ is exact in 64-bit as long as $\sum a \le 3\cdot10^9$.

## 7. Going further (toward 2400–2600+)

- **Virtual tree + shortest paths**: multi-source Dijkstra on the virtual tree with tie-breaking by source index — [CF 1320E · Treeland and Viruses](https://codeforces.com/problemset/problem/1320/E) — 3000.
- **Per-colour virtual trees for path statistics**: sum over all paths of the number of colours appearing exactly once — [CF 1681F · Unique Occurrences](https://codeforces.com/problemset/problem/1681/F) — 2300 (also solvable with DSU / small-to-large).
- **Queries with a changing root and grouping constraints**: [CF 1111E · Tree](https://codeforces.com/problemset/problem/1111/E) — 2500 — the same "only key vertices matter" idea, with ancestor counts via Fenwick on the Euler tour.
- **Offline number theory on paths** (per-prime vertex sets): [CF 986E · Prince's Problem](https://codeforces.com/problemset/problem/986/E) — 2800.
- **Steiner tree size online** (insert/delete key vertices, maintain $\frac12\sum$ cyclic distances in a `set` ordered by $tin$) — a standard follow-up that needs only LCA distances.
- Revision: [cheat sheet](../99-Cheat-Sheets/10-trees-cheatsheet.md).

## 8. Practice ladder

**2000–2400**
- [ ] [CF 1923E · Count Paths](https://codeforces.com/problemset/problem/1923/E) — 2000
- [ ] [CF 1681F · Unique Occurrences](https://codeforces.com/problemset/problem/1681/F) — 2300
- [ ] [CF 1702G2 · Passable Paths (hard version)](https://codeforces.com/problemset/problem/1702/G2) — 2000 — warm-up: "do the keys form a path?" is a virtual tree that is a chain

**2400+**
- [ ] [CF 1111E · Tree](https://codeforces.com/problemset/problem/1111/E) — 2500
- [ ] [CF 613D · Kingdom and its Cities](https://codeforces.com/problemset/problem/613/D) — 2800
- [ ] [CF 986E · Prince's Problem](https://codeforces.com/problemset/problem/986/E) — 2800
- [ ] [CF 1320E · Treeland and Viruses](https://codeforces.com/problemset/problem/1320/E) — 3000

## 9. LeetCode / FAANG cross-reference

Rare in interviews — virtual trees appear only in contests with many-query, bounded-$\sum k$ constraints. The closest interview idea is "the minimal subtree connecting marked nodes":

- [LC 1443 · Minimum Time to Collect All Apples in a Tree](https://leetcode.com/problems/minimum-time-to-collect-all-apples-in-a-tree/) — Medium — twice the Steiner tree size of the apples plus the root (one query; plain DFS suffices).
- [LC 2603 · Collect Coins in a Tree](https://leetcode.com/problems/collect-coins-in-a-tree/) — Hard — pruning irrelevant leaves, the same "only the relevant skeleton matters" idea.

## 10. Self-check

1. Prove that adjacent LCAs in preorder suffice to make the key set LCA-closed.
2. Why is $\lvert V'\rvert \le 2k-1$?
3. Prove that the virtual parent of $y_i$ is $\mathrm{lca}(y_{i-1}, y_i)$.
4. Why does scanning the sorted virtual vertex list backwards give children before parents?
5. In Example 2, why may the DP use the cheapest edge on the whole root path instead of only the virtual edge?
6. How would you maintain the Steiner tree weight under insertions and deletions of key vertices?
7. Which per-query costs must be avoided to keep the total at $O(\sum k\log k)$?

<details><summary>Answers</summary>

1. Lemma 1: for $i<j$, the LCA $w$ of $x_i, x_j$ equals $\mathrm{lca}(x_t, x_{t+1})$ where $t$ is the last index whose vertex is in the child subtree of $w$ containing $x_i$.
2. $V'$ consists of $k$ keys plus at most $k-1$ adjacent LCAs (Lemma 1).
3. Lemma 3: $y_{i-1}$ lies in the subtree of the deepest proper $V'$-ancestor $p$ of $y_i$, so the LCA lies on $p \to y_i$, is in $V'$ by closure and is a proper ancestor — hence it is $p$.
4. A parent is an ancestor, and ancestors come earlier in preorder; so every child appears after its parent in the sorted list.
5. Cutting an edge above the virtual parent also disconnects the parent's other branches; the parent's own option $mn(\text{parent})$ covers that case at no more cost, so allowing it at the child never produces an answer below the true optimum, and every DP value corresponds to a feasible set of cuts.
6. Keep the keys in a balanced set ordered by $tin$; the weight is $\frac12\sum$ of distances between cyclically adjacent keys. Inserting $x$ between $a$ and $b$ adds $\frac12(d(a,x) + d(x,b) - d(a,b))$; deletion subtracts it.
7. Anything $O(n)$ per query: clearing global arrays, recomputing depths, building adjacency for the whole tree. Only touch the $O(k)$ virtual vertices.

</details>
