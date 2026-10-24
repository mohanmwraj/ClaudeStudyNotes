# Sparse Table and Range Minimum Queries

> **Band:** 🔵 1600–2100 · **Priority:** 🔥 · **FAANG:** low · **Prerequisites:** [bit manipulation](../01-Foundations/03-bit-manipulation.md), [binary search](../02-Core-Techniques/02-binary-search-and-binary-search-on-answer.md), [segment tree basics](02-segment-tree-basics.md)
> **You can say you know this when:** you can explain exactly which operations allow the two-overlapping-blocks $O(1)$ query (and why sum does not), build a sparse table in both languages without off-by-ones, compute LCA by Euler tour + RMQ, and combine a sparse table with two pointers or binary search on a monotone range function (gcd, min, max).

## 1. First principles — why this works

**The problem.** A *static* array and up to $10^6$ queries "min of $a[l..r]$". Prefix minima do not help (no inverse); a segment tree answers in
$O(\log n)$. Can we get $O(1)$ by precomputing more? Precomputing all $\binom{n}{2}$ ranges is $O(n^2)$. The question is which *small* family
of ranges lets every range be assembled in $O(1)$.

**Powers of two.** Store $\mathrm{sp}[k][i] = \min(a_i, \dots, a_{i + 2^k - 1})$ for every $i$ and every $k \le \log_2 n$: $n\log n$ values, built level by level
because a block of length $2^k$ is two blocks of length $2^{k-1}$:

$$\mathrm{sp}[k][i] = \min\big(\mathrm{sp}[k-1][i],\ \mathrm{sp}[k-1][i + 2^{k-1}]\big).$$

**The $O(1)$ query and the idempotence requirement.** For $[l, r]$ with length $L = r - l + 1$, let $k = \lfloor \log_2 L \rfloor$, so $2^k \le L < 2^{k+1}$.
The block starting at $l$ and the block ending at $r$, both of length $2^k$, together cover $[l, r]$ (their total length $2^{k+1}$ exceeds $L$) — but they
**overlap**. For min the overlap is harmless: an element counted twice does not change the minimum. In general the trick works exactly when the
operation is **idempotent** ($x \oplus x = x$), associative and commutative, which makes $\bigoplus$ of a multiset depend only on the underlying *set*:
min, max, gcd, lcm (without overflow), bitwise and/or. It fails for sum, xor, product (an element would be counted twice).

**Non-idempotent operations.** Two options. (1) Decompose $[l, r]$ into $\le \log n$ *disjoint* power-of-two blocks following the bits of $L$
— $O(\log n)$ per query, no better than a segment tree but with no updates and tiny constant. (2) The **disjoint sparse table** (🧊): for each level $h$, cut the
array into blocks of size $2^{h+1}$; inside each block store suffix aggregates from the block's midpoint leftwards and prefix aggregates from the midpoint
rightwards. For a query with $l \ne r$, the level is $h = \lfloor\log_2(l \oplus r)\rfloor$ (the highest bit where $l$ and $r$ differ): at that level $l$ and $r$
lie in the same block but on different sides of its midpoint, so the answer is $\text{suf}_h[l] \oplus \text{pre}_h[r]$ — one combine, $O(1)$, for **any** associative
operation (matrix products, sums mod $p$, string hashes).

**Where idempotent range functions show up besides RMQ.** For a fixed left end $l$, $g(r) = \gcd(a_l..a_r)$ is non-increasing in $r$ *and takes at most
$\log_2 V + 1$ distinct values* (each change divides it by at least 2). Similarly $\max$ is non-decreasing and $\min$ non-increasing. So with $O(1)$ range queries we can
binary search the boundaries where the function changes, or slide two pointers, without any updates. This is the engine behind
"count subarrays whose gcd is $x$", "longest subarray with gcd $>1$", "count $(l, r)$ with $\max a = \min b$".

**LCA as RMQ.** Write the Euler tour of a rooted tree: record a vertex every time the DFS enters it or returns to it from a child — $2n - 1$ entries.
Between the first occurrences of $u$ and $v$, the tour walks from $u$ to $v$ through the tree, and the shallowest vertex it passes is exactly their lowest common ancestor
(the walk must climb to the LCA and cannot go above it, because it never leaves the LCA's subtree in between). So $\mathrm{LCA}(u, v) = $ the minimum-depth vertex
of the tour on $[\text{first}_u, \text{first}_v]$: $O(n\log n)$ preprocessing, $O(1)$ per query. Compare binary lifting
($O(\log n)$ per query) in [LCA and binary lifting](../10-Trees/02-lca-and-binary-lifting.md).

**When not to use it.** Any update forces an $O(n \log n)$ rebuild — use a segment tree. Memory is $n \log n$: for $n = 10^6$ that is $2\cdot 10^7$ ints = 80 MB.
For a single sliding window (all windows of fixed length moving right) a [monotonic deque](../02-Core-Techniques/04-monotonic-stack-and-deque.md) is $O(n)$ total.

## 2. Formulas, definitions and identities

| Formula | Meaning |
|---|---|
| $\mathrm{sp}[0][i] = a_i$, $\mathrm{sp}[k][i] = \mathrm{sp}[k-1][i] \oplus \mathrm{sp}[k-1][i+2^{k-1}]$ | build, valid for $i + 2^k \le n$ |
| $k = \lfloor\log_2(r-l+1)\rfloor$, answer $= \mathrm{sp}[k][l] \oplus \mathrm{sp}[k][r-2^k+1]$ | $O(1)$ query, needs idempotence |
| $\mathrm{lg}[1] = 0$, $\mathrm{lg}[i] = \mathrm{lg}[\lfloor i/2\rfloor] + 1$ | integer log table; or `__lg(x)`, `31 - Integer.numberOfLeadingZeros(x)` |
| $x \oplus x = x$ | idempotence: min, max, gcd, and, or |
| $h = \lfloor\log_2(l \mathbin{\text{xor}} r)\rfloor$, answer $= \text{suf}_h[l] \oplus \text{pre}_h[r]$ | disjoint sparse table, any associative op, $l \ne r$ |
| $\#\{\gcd(a_l..a_r) : r \ge l\} \le \log_2 V + 1$ | gcd changes at most $\log V$ times along a prefix |
| $\mathrm{LCA}(u,v) = \arg\min_{\text{depth}} E[\min(f_u,f_v)..\max(f_u,f_v)]$ | Euler tour $E$ of length $2n-1$, $f$ = first occurrence |
| $\mathrm{dist}(u,v) = d_u + d_v - 2\,d_{\mathrm{LCA}(u,v)}$ | tree distance |

Complexities: build $O(n\log n)$ time and memory; idempotent query $O(1)$; disjoint table build $O(n\log n)$, query $O(1)$; gcd queries cost $O(\log V)$ per combine.

## 3. Implementation (C++ and Java)

### 3.1 Sparse table for an idempotent operation

```cpp
template <class T, class Op>
struct SparseTable {
    vector<vector<T>> sp; Op op;
    SparseTable(const vector<T>& a, Op op) : op(op) {
        int n = a.size(), K = 1;
        while ((1 << K) <= n) K++;
        sp.assign(K, vector<T>());
        sp[0] = a;
        for (int k = 1; k < K; k++) {
            sp[k].resize(n - (1 << k) + 1);
            for (int i = 0; i + (1 << k) <= n; i++) sp[k][i] = op(sp[k - 1][i], sp[k - 1][i + (1 << (k - 1))]);
        }
    }
    T query(int l, int r) const {                              // closed [l, r], 0-indexed, l <= r
        int k = __lg(r - l + 1);
        return op(sp[k][l], sp[k][r - (1 << k) + 1]);
    }
};
// usage: SparseTable st(a, [](int x, int y) { return min(x, y); });
//        SparseTable g(b, [](long long x, long long y) { return gcd(x, y); });
```

```java
static class SparseMin {                                       // change Math.min to max / gcd as needed
    final int[][] sp;
    SparseMin(int[] a) {
        int n = a.length, K = 1;
        while ((1 << K) <= n) K++;
        sp = new int[K][];
        sp[0] = a.clone();
        for (int k = 1; k < K; k++) {
            sp[k] = new int[n - (1 << k) + 1];
            for (int i = 0; i + (1 << k) <= n; i++) sp[k][i] = Math.min(sp[k - 1][i], sp[k - 1][i + (1 << (k - 1))]);
        }
    }
    int query(int l, int r) {                                  // closed [l, r], 0-indexed
        int k = 31 - Integer.numberOfLeadingZeros(r - l + 1);
        return Math.min(sp[k][l], sp[k][r - (1 << k) + 1]);
    }
}
```

### 3.2 Disjoint sparse table — $O(1)$ range product modulo $p$ (non-idempotent)

Original task: `n q`, the array, then `q` queries `l r` (1-indexed): print $\prod_{i=l}^{r} a_i \bmod (10^9+7)$. Pad to a power of two with the identity 1.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 1'000'000'007;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    int LOG = 1; while ((1 << LOG) < n) LOG++;
    int N = 1 << LOG;
    vector<long long> a(N, 1);
    for (int i = 0; i < n; i++) { cin >> a[i]; a[i] %= MOD; }
    vector<vector<long long>> t(LOG, vector<long long>(N));
    for (int h = 0; h < LOG; h++) {
        int half = 1 << h;
        for (int mid = half; mid < N; mid += 2 * half) {          // block [mid - half, mid + half)
            t[h][mid - 1] = a[mid - 1];
            for (int i = mid - 2; i >= mid - half; i--) t[h][i] = a[i] * t[h][i + 1] % MOD;    // suffix products
            t[h][mid] = a[mid];
            for (int i = mid + 1; i < mid + half; i++) t[h][i] = t[h][i - 1] * a[i] % MOD;      // prefix products
        }
    }
    while (q--) {
        int l, r; cin >> l >> r; l--; r--;
        if (l == r) { cout << a[l] << '\n'; continue; }
        int h = __lg(l ^ r);
        cout << t[h][l] * t[h][r] % MOD << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), q = in.nextInt();
        int LOG = 1; while ((1 << LOG) < n) LOG++;
        int N = 1 << LOG;
        long[] a = new long[N]; Arrays.fill(a, 1);
        for (int i = 0; i < n; i++) a[i] = in.nextLong() % MOD;
        long[][] t = new long[LOG][N];
        for (int h = 0; h < LOG; h++) {
            int half = 1 << h;
            for (int mid = half; mid < N; mid += 2 * half) {
                t[h][mid - 1] = a[mid - 1];
                for (int i = mid - 2; i >= mid - half; i--) t[h][i] = a[i] * t[h][i + 1] % MOD;
                t[h][mid] = a[mid];
                for (int i = mid + 1; i < mid + half; i++) t[h][i] = t[h][i - 1] * a[i] % MOD;
            }
        }
        while (q-- > 0) {
            int l = in.nextInt() - 1, r = in.nextInt() - 1;
            if (l == r) { out.println(a[l]); continue; }
            int h = 31 - Integer.numberOfLeadingZeros(l ^ r);
            out.println(t[h][l] * t[h][r] % MOD);
        }
        out.flush();
    }

    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
5 5
2 3 5 7 11
1 5
2 4
3 3
4 5
1 2
out:
2310
105
5
77
6
-->
<!-- test
in:
1 1
1000000006
1 1
out:
1000000006
-->
<!-- test
in:
3 3
1000000000 1000000000 3
1 2
1 3
2 3
out:
49
147
999999986
-->

## 4. Recognising the pattern

- **Static array, many min/max/gcd range queries** (often $q \ge 10^6$ or queries inside a binary search/two-pointer loop) → sparse table.
- **"Count/longest subarrays with gcd (or min, max, and, or) satisfying …"** → the function is monotone in each endpoint; sparse table + two pointers or binary search. For counting by exact gcd value, the "at most $\log V$ distinct values per left end" observation.
- **"$\max$ over one array equals $\min$ over another"** → for fixed $l$ the difference is monotone in $r$; two binary searches.
- **Many LCA queries on a static tree** → Euler tour + sparse table for $O(1)$; binary lifting if you also need $k$-th ancestor or path aggregates.
- **Any update at all** → segment tree, not sparse table.
- **Non-idempotent static queries with $O(1)$ needed** (product mod $p$, matrix products) → disjoint sparse table; otherwise prefix sums when invertible.

## 5. Worked examples (graded)

### Example 1 — Static Range Minimum Queries  ·  ★ ≈1200

- **Source:** [CSES 1647 · Static Range Minimum Queries](https://cses.fi/problemset/task/1647)
- **Difficulty:** ≈1200 (est.)
- **Problem:** $n, q \le 2\cdot10^5$ values up to $10^9$; each query $(a, b)$ asks for $\min(x_a..x_b)$.
- **Thinking from first principles:** no updates and an idempotent operation: the textbook sparse table. Build $O(n\log n)$, each query two lookups.

<details><summary>Solution</summary>

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    int K = 1; while ((1 << K) <= n) K++;
    vector<vector<int>> sp(K, vector<int>(n));
    for (auto& x : sp[0]) cin >> x;
    for (int k = 1; k < K; k++)
        for (int i = 0; i + (1 << k) <= n; i++) sp[k][i] = min(sp[k - 1][i], sp[k - 1][i + (1 << (k - 1))]);
    while (q--) {
        int a, b; cin >> a >> b; a--; b--;
        int k = __lg(b - a + 1);
        cout << min(sp[k][a], sp[k][b - (1 << k) + 1]) << '\n';
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
        int K = 1; while ((1 << K) <= n) K++;
        int[][] sp = new int[K][n];
        for (int i = 0; i < n; i++) sp[0][i] = in.nextInt();
        for (int k = 1; k < K; k++)
            for (int i = 0; i + (1 << k) <= n; i++) sp[k][i] = Math.min(sp[k - 1][i], sp[k - 1][i + (1 << (k - 1))]);
        while (q-- > 0) {
            int a = in.nextInt() - 1, b = in.nextInt() - 1;
            int k = 31 - Integer.numberOfLeadingZeros(b - a + 1);
            out.println(Math.min(sp[k][a], sp[k][b - (1 << k) + 1]));
        }
        out.flush();
    }

    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        int nextInt() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            int r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
    }
}
```

<!-- test
in:
8 4
3 2 4 5 1 1 5 3
2 4
5 6
1 8
3 3
out:
2
1
1
4
-->
<!-- test
in:
1 1
7
1 1
out:
7
-->

</details>

### Example 2 — Distance Queries (LCA by Euler tour + RMQ)  ·  ★ ≈1700

- **Source:** [CSES 1135 · Distance Queries](https://cses.fi/problemset/task/1135)
- **Difficulty:** ≈1700 (est.)
- **Problem:** a tree with $n, q \le 2\cdot10^5$; each query asks for the number of edges between $a$ and $b$.
- **Thinking from first principles:** $\mathrm{dist}(a,b) = d_a + d_b - 2d_{\mathrm{LCA}}$, so the problem *is* LCA. BFS per query is $O(nq)$.
  Euler tour + sparse table over depths gives $O(1)$ per query. The DFS must be iterative: a path of $2\cdot10^5$ vertices overflows the default stack (especially on Windows and in Java).

<details><summary>Solution</summary>

Iterative DFS with an explicit stack of (vertex, next-edge pointer) produces the tour; the sparse table stores *tour indices* compared by depth.
$O(n\log n + q)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    vector<vector<int>> g(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; g[a].push_back(b); g[b].push_back(a); }
    vector<int> depth(n + 1, 0), first(n + 1, -1), tour, it(n + 1, 0), par(n + 1, 0);
    tour.reserve(2 * n);
    vector<int> st = {1}; first[1] = 0; tour.push_back(1);
    while (!st.empty()) {
        int v = st.back();
        if (it[v] < (int)g[v].size()) {
            int u = g[v][it[v]++];
            if (u == par[v]) continue;
            par[u] = v; depth[u] = depth[v] + 1;
            first[u] = tour.size(); tour.push_back(u);
            st.push_back(u);
        } else {
            st.pop_back();
            if (!st.empty()) tour.push_back(st.back());             // back in the parent
        }
    }
    int m = tour.size(), K = 1;
    while ((1 << K) <= m) K++;
    vector<vector<int>> sp(K, vector<int>(m));
    sp[0] = tour;
    auto better = [&](int x, int y) { return depth[x] < depth[y] ? x : y; };
    for (int k = 1; k < K; k++)
        for (int i = 0; i + (1 << k) <= m; i++) sp[k][i] = better(sp[k - 1][i], sp[k - 1][i + (1 << (k - 1))]);
    while (q--) {
        int a, b; cin >> a >> b;
        int l = first[a], r = first[b];
        if (l > r) swap(l, r);
        int k = __lg(r - l + 1);
        int w = better(sp[k][l], sp[k][r - (1 << k) + 1]);
        cout << depth[a] + depth[b] - 2 * depth[w] << '\n';
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
        int[] head = new int[n + 1], nxt = new int[2 * (n - 1)], to = new int[2 * (n - 1)];
        Arrays.fill(head, -1);
        for (int i = 0; i < n - 1; i++) {
            int a = in.nextInt(), b = in.nextInt();
            to[2 * i] = b; nxt[2 * i] = head[a]; head[a] = 2 * i;
            to[2 * i + 1] = a; nxt[2 * i + 1] = head[b]; head[b] = 2 * i + 1;
        }
        int[] depth = new int[n + 1], first = new int[n + 1], par = new int[n + 1], it = new int[n + 1];
        int[] tour = new int[2 * n], st = new int[n];
        for (int v = 1; v <= n; v++) it[v] = head[v];
        int m = 0, sp0 = 0;
        st[sp0++] = 1; first[1] = 0; tour[m++] = 1;
        while (sp0 > 0) {
            int v = st[sp0 - 1];
            if (it[v] != -1) {
                int e = it[v]; it[v] = nxt[e];
                int u = to[e];
                if (u == par[v]) continue;
                par[u] = v; depth[u] = depth[v] + 1;
                first[u] = m; tour[m++] = u;
                st[sp0++] = u;
            } else {
                sp0--;
                if (sp0 > 0) tour[m++] = st[sp0 - 1];
            }
        }
        int K = 1; while ((1 << K) <= m) K++;
        int[][] sp = new int[K][];
        sp[0] = Arrays.copyOf(tour, m);
        for (int k = 1; k < K; k++) {
            sp[k] = new int[m - (1 << k) + 1];
            for (int i = 0; i + (1 << k) <= m; i++) {
                int x = sp[k - 1][i], y = sp[k - 1][i + (1 << (k - 1))];
                sp[k][i] = depth[x] < depth[y] ? x : y;
            }
        }
        while (q-- > 0) {
            int a = in.nextInt(), b = in.nextInt();
            int l = Math.min(first[a], first[b]), r = Math.max(first[a], first[b]);
            int k = 31 - Integer.numberOfLeadingZeros(r - l + 1);
            int x = sp[k][l], y = sp[k][r - (1 << k) + 1], w = depth[x] < depth[y] ? x : y;
            out.println(depth[a] + depth[b] - 2 * depth[w]);
        }
        out.flush();
    }

    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        int nextInt() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            int r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
    }
}
```

<!-- test
in:
5 3
1 2
1 3
3 4
3 5
1 3
2 5
1 4
out:
1
3
2
-->
<!-- test
in:
1 1
1 1
out:
0
-->
<!-- test
in:
4 3
1 2
2 3
3 4
4 1
2 2
1 4
out:
3
0
3
-->

</details>

### Example 3 — Integers Have Friends (gcd table + two pointers)  ·  ★ 1800

- **Source:** [CF 1548B · Integers Have Friends](https://codeforces.com/problemset/problem/1548/B) — 1800
- **Difficulty:** 1800
- **Problem:** $t$ tests, total $n \le 2\cdot10^5$, distinct $a_i \le 10^{18}$. A subarray is a *friend group* if some $m \ge 2$ gives all its elements the same remainder mod $m$. Find the longest friend group.
- **Thinking from first principles:** all of $a_l..a_r$ are congruent mod $m$ iff $m$ divides every adjacent difference $d_i = |a_{i+1} - a_i|$ for $l \le i < r$, iff
  $\gcd(d_l..d_{r-1}) \ge 2$. So we need the longest window of $d$ with gcd $> 1$. The window property is monotone (shrinking a window keeps gcd $> 1$), so two pointers work;
  each step needs a range gcd — $O(1)$ combines with a sparse table, because gcd is idempotent. Distinct values guarantee $d_i \ge 1$. Use 64-bit and `__gcd`/`std::gcd`.

<details><summary>Solution</summary>

Answer $= 1 + $ (longest window of $d$ with gcd $\ge 2$), and at least 1. $O(n \log n \log V)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int T; cin >> T;
    while (T--) {
        int n; cin >> n;
        vector<long long> a(n);
        for (auto& x : a) cin >> x;
        int m = n - 1;
        if (m == 0) { cout << 1 << '\n'; continue; }
        int K = 1; while ((1 << K) <= m) K++;
        vector<vector<long long>> sp(K, vector<long long>(m));
        for (int i = 0; i < m; i++) sp[0][i] = llabs(a[i + 1] - a[i]);
        for (int k = 1; k < K; k++)
            for (int i = 0; i + (1 << k) <= m; i++) sp[k][i] = gcd(sp[k - 1][i], sp[k - 1][i + (1 << (k - 1))]);
        auto query = [&](int l, int r) { int k = __lg(r - l + 1); return gcd(sp[k][l], sp[k][r - (1 << k) + 1]); };
        int best = 0, l = 0;
        for (int r = 0; r < m; r++) {
            while (l <= r && query(l, r) == 1) l++;
            best = max(best, r - l + 1);
        }
        cout << best + 1 << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long gcd(long a, long b) { while (b != 0) { long t = a % b; a = b; b = t; } return a; }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int T = in.nextInt();
        while (T-- > 0) {
            int n = in.nextInt();
            long[] a = new long[n];
            for (int i = 0; i < n; i++) a[i] = in.nextLong();
            int m = n - 1;
            if (m == 0) { out.println(1); continue; }
            int K = 1; while ((1 << K) <= m) K++;
            long[][] sp = new long[K][];
            sp[0] = new long[m];
            for (int i = 0; i < m; i++) sp[0][i] = Math.abs(a[i + 1] - a[i]);
            for (int k = 1; k < K; k++) {
                sp[k] = new long[m - (1 << k) + 1];
                for (int i = 0; i + (1 << k) <= m; i++) sp[k][i] = gcd(sp[k - 1][i], sp[k - 1][i + (1 << (k - 1))]);
            }
            int best = 0, l = 0;
            for (int r = 0; r < m; r++) {
                while (l <= r) {
                    int k = 31 - Integer.numberOfLeadingZeros(r - l + 1);
                    if (gcd(sp[k][l], sp[k][r - (1 << k) + 1]) != 1) break;
                    l++;
                }
                best = Math.max(best, r - l + 1);
            }
            out.println(best + 1);
        }
        out.flush();
    }

    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
4
5
1 5 2 4 6
4
8 2 5 10
2
1000 2000
8
465 55 3 54 234 12 45 78
out:
3
3
2
6
-->
<!-- test
in:
2
1
1000000000000000000
3
1 2 3
out:
1
1
-->

</details>

### Example 4 — Pair of Numbers (binary search on length)  ·  ★ 2000

- **Source:** [CF 359D · Pair of Numbers](https://codeforces.com/problemset/problem/359/D) — 2000
- **Difficulty:** 2000
- **Problem:** $n \le 3\cdot10^5$, $a_i \le 10^6$. A pair $(l, r)$ is good if some $j \in [l, r]$ has $a_j$ dividing all of $a_l..a_r$. Among good pairs maximise $r - l$; print how many pairs achieve the maximum, the maximum, and all their $l$ in increasing order.
- **Thinking from first principles:** if $a_j$ divides every element, it divides the minimum, and it is at least the minimum, so $a_j = \min$; and then $\gcd = \min$.
  Conversely $\gcd(a_l..a_r) = \min(a_l..a_r)$ means the minimum element divides everything. So "good" $\iff \gcd = \min$ on the range — two idempotent range queries.
  *Monotonicity in length:* a good range of length $L+1$ contains a good range of length $L$ (drop an endpoint that is not the dividing element). So binary search the maximum length,
  checking all $n$ windows of a length in $O(n)$ with $O(1)$ queries. The gcd per check costs $O(\log V)$.

<details><summary>Solution</summary>

Two sparse tables (min and gcd). Binary search the largest $D$ such that some window of length $D+1$ is good; then list all such windows. $O(n\log n \log V)$, memory $2 \cdot 19 \cdot 3\cdot10^5$ ints.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    int K = 1; while ((1 << K) <= n) K++;
    vector<vector<int>> mn(K, vector<int>(n)), gd(K, vector<int>(n));
    for (int i = 0; i < n; i++) { cin >> mn[0][i]; gd[0][i] = mn[0][i]; }
    for (int k = 1; k < K; k++)
        for (int i = 0; i + (1 << k) <= n; i++) {
            mn[k][i] = min(mn[k - 1][i], mn[k - 1][i + (1 << (k - 1))]);
            gd[k][i] = gcd(gd[k - 1][i], gd[k - 1][i + (1 << (k - 1))]);
        }
    auto good = [&](int l, int r) {
        int k = __lg(r - l + 1);
        return min(mn[k][l], mn[k][r - (1 << k) + 1]) == gcd(gd[k][l], gd[k][r - (1 << k) + 1]);
    };
    auto exists = [&](int D) { for (int l = 0; l + D < n; l++) if (good(l, l + D)) return true; return false; };
    int lo = 0, hi = n - 1;                                       // D = 0 is always good
    while (lo < hi) { int mid = (lo + hi + 1) / 2; if (exists(mid)) lo = mid; else hi = mid - 1; }
    vector<int> ls;
    for (int l = 0; l + lo < n; l++) if (good(l, l + lo)) ls.push_back(l + 1);
    cout << ls.size() << ' ' << lo << '\n';
    for (size_t i = 0; i < ls.size(); i++) cout << ls[i] << (i + 1 < ls.size() ? ' ' : '\n');
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[][] mn, gd;
    static int gcd(int a, int b) { while (b != 0) { int t = a % b; a = b; b = t; } return a; }
    static boolean good(int l, int r) {
        int k = 31 - Integer.numberOfLeadingZeros(r - l + 1);
        return Math.min(mn[k][l], mn[k][r - (1 << k) + 1]) == gcd(gd[k][l], gd[k][r - (1 << k) + 1]);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int K = 1; while ((1 << K) <= n) K++;
        mn = new int[K][]; gd = new int[K][];
        mn[0] = new int[n];
        for (int i = 0; i < n; i++) mn[0][i] = in.nextInt();
        gd[0] = mn[0].clone();
        for (int k = 1; k < K; k++) {
            int len = n - (1 << k) + 1;
            mn[k] = new int[len]; gd[k] = new int[len];
            for (int i = 0; i < len; i++) {
                mn[k][i] = Math.min(mn[k - 1][i], mn[k - 1][i + (1 << (k - 1))]);
                gd[k][i] = gcd(gd[k - 1][i], gd[k - 1][i + (1 << (k - 1))]);
            }
        }
        int lo = 0, hi = n - 1;
        while (lo < hi) {
            int mid = (lo + hi + 1) / 2; boolean ok = false;
            for (int l = 0; l + mid < n && !ok; l++) ok = good(l, l + mid);
            if (ok) lo = mid; else hi = mid - 1;
        }
        StringBuilder sb = new StringBuilder();
        int cnt = 0;
        for (int l = 0; l + lo < n; l++) if (good(l, l + lo)) { if (cnt++ > 0) sb.append(' '); sb.append(l + 1); }
        System.out.println(cnt + " " + lo);
        System.out.println(sb);
    }

    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        int nextInt() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            int r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
    }
}
```

<!-- test
in:
5
4 6 9 3 6
out:
1 3
2
-->
<!-- test
in:
5
1 3 5 7 9
out:
1 4
1
-->
<!-- test
in:
5
2 3 5 7 11
out:
5 0
1 2 3 4 5
-->
<!-- test
in:
1
1000000
out:
1 0
1
-->

</details>

### Example 5 — Friends and Subsequences (two binary searches per left end)  ·  ★ 2100

- **Source:** [CF 689D · Friends and Subsequences](https://codeforces.com/problemset/problem/689/D) — 2100
- **Difficulty:** 2100
- **Problem:** two arrays $a, b$ of length $n \le 2\cdot10^5$, $|a_i|, |b_i| \le 10^9$. Count pairs $l \le r$ with $\max(a_l..a_r) = \min(b_l..b_r)$.
- **Thinking from first principles:** $O(n^2)$ pairs is too many, so fix $l$ and understand the set of good $r$. As $r$ grows, $\max a$ can only increase and $\min b$ can only decrease,
  so $f(r) = \max a - \min b$ is **non-decreasing**. The good $r$ are those with $f(r) = 0$: a contiguous interval $[r_1, r_2)$ where $r_1$ = first $r$ with $f \ge 0$ and $r_2$ = first $r$ with $f > 0$.
  Two binary searches per $l$, each probe two $O(1)$ sparse-table queries. The answer reaches $n(n+1)/2 \approx 2\cdot10^{10}$ → 64-bit.

<details><summary>Solution</summary>

$O(n\log n)$ build and $O(n \log n)$ queries.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    int K = 1; while ((1 << K) <= n) K++;
    vector<vector<int>> mx(K, vector<int>(n)), mn(K, vector<int>(n));
    for (auto& x : mx[0]) cin >> x;
    for (auto& x : mn[0]) cin >> x;
    for (int k = 1; k < K; k++)
        for (int i = 0; i + (1 << k) <= n; i++) {
            mx[k][i] = max(mx[k - 1][i], mx[k - 1][i + (1 << (k - 1))]);
            mn[k][i] = min(mn[k - 1][i], mn[k - 1][i + (1 << (k - 1))]);
        }
    auto f = [&](int l, int r) -> long long {                     // max a - min b on [l, r], non-decreasing in r
        int k = __lg(r - l + 1);
        return (long long)max(mx[k][l], mx[k][r - (1 << k) + 1]) - min(mn[k][l], mn[k][r - (1 << k) + 1]);
    };
    auto firstR = [&](int l, bool strict) {                       // first r >= l with f > 0 (strict) or f >= 0
        int lo = l, hi = n;
        while (lo < hi) {
            int mid = (lo + hi) / 2;
            long long v = f(l, mid);
            if (strict ? v > 0 : v >= 0) hi = mid; else lo = mid + 1;
        }
        return lo;
    };
    long long ans = 0;
    for (int l = 0; l < n; l++) ans += firstR(l, true) - firstR(l, false);
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n; static int[][] mx, mn;
    static long f(int l, int r) {
        int k = 31 - Integer.numberOfLeadingZeros(r - l + 1);
        return (long) Math.max(mx[k][l], mx[k][r - (1 << k) + 1]) - Math.min(mn[k][l], mn[k][r - (1 << k) + 1]);
    }
    static int firstR(int l, boolean strict) {
        int lo = l, hi = n;
        while (lo < hi) {
            int mid = (lo + hi) >>> 1;
            long v = f(l, mid);
            if (strict ? v > 0 : v >= 0) hi = mid; else lo = mid + 1;
        }
        return lo;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        n = in.nextInt();
        int K = 1; while ((1 << K) <= n) K++;
        mx = new int[K][]; mn = new int[K][];
        mx[0] = new int[n]; mn[0] = new int[n];
        for (int i = 0; i < n; i++) mx[0][i] = in.nextInt();
        for (int i = 0; i < n; i++) mn[0][i] = in.nextInt();
        for (int k = 1; k < K; k++) {
            int len = n - (1 << k) + 1;
            mx[k] = new int[len]; mn[k] = new int[len];
            for (int i = 0; i < len; i++) {
                mx[k][i] = Math.max(mx[k - 1][i], mx[k - 1][i + (1 << (k - 1))]);
                mn[k][i] = Math.min(mn[k - 1][i], mn[k - 1][i + (1 << (k - 1))]);
            }
        }
        long ans = 0;
        for (int l = 0; l < n; l++) ans += firstR(l, true) - firstR(l, false);
        System.out.println(ans);
    }

    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        int nextInt() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            int r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
    }
}
```

<!-- test
in:
6
1 2 3 2 1 4
6 7 1 2 3 2
out:
2
-->
<!-- test
in:
3
3 3 3
1 1 1
out:
0
-->
<!-- test
in:
3
5 5 5
5 5 5
out:
6
-->
<!-- test
in:
1
-1000000000
-1000000000
out:
1
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Idempotence is the whole trick.** Sum/xor/product with two overlapping blocks double-counts; use prefix sums, a disjoint sparse table, or a segment tree.
2. **Level bound.** Build levels $k$ with $2^k \le n$ only; `while ((1 << K) <= n) K++` gives the count of levels. Accessing `sp[k][i]` with $i + 2^k > n$ is out of bounds or garbage.
3. **Integer log.** `__lg(x)` (C++) / `31 - Integer.numberOfLeadingZeros(x)` (Java) are exact and fast; `log2((double)x)` can be off by one near powers of two.
4. **Memory layout `sp[k][i]`** (level-major) is cache-friendly for both build and query; `sp[i][k]` is slower and harder to size. For $n = 10^6$ budget 80 MB of ints, or use the $O(n)$ block RMQ.
5. **Gcd cost.** Each combine is $O(\log V)$; with $10^6$ queries inside a binary search, the gcd dominates. Prefer two pointers ($O(n)$ queries) over binary search ($O(n\log n)$ queries) when both work.
6. **`gcd` of 64-bit values**: `std::gcd` needs both arguments the same type; `llabs` for differences; Java has no built-in `long` gcd (write the loop).
7. **Euler tour length is $2n - 1$**; allocate $2n$. Store vertex ids in the table and compare by depth (or store `depth * N + vertex` packed in a `long`).
8. **Iterative DFS** for trees with $2\cdot10^5$ vertices — a path graph overflows recursion in Java and on Windows builds.
9. **Monotone functions only.** Binary search on $r$ for fixed $l$ requires the function to be monotone in $r$ (max, min, gcd, and, or are); "max − min" is monotone, "max + min" is not in general.
10. **Multi-test allocation**: allocate the table per test with the test's $n$; a global $20 \times 2\cdot10^5$ table re-filled per test is fine only if you never read stale cells.

## 7. Going further (toward 2400–2600+)

- **$O(n)$ preprocessing, $O(1)$ RMQ** (block decomposition: sparse table over block minima + in-block bitmask stacks; or Fischer–Heun): useful for $n \ge 10^7$ or as a lower-memory LCA. 🧊
- **Sqrt tree** — $O(1)$ queries for any associative operation with $O(n\log\log n)$ preprocessing and point updates in $O(\sqrt n)$. 🧊
- **Counting subarrays by gcd/or value** with the "$\le\log V$ distinct values per endpoint" lists: [CF 475D · CGCDSSQ](https://codeforces.com/problemset/problem/475/D) — 2000, then [CF 1547F · Array Stabilization (GCD version)](https://codeforces.com/problemset/problem/1547/F) — 1900.
- **Sparse tables on trees** (binary lifting) for path min/max and $k$-th ancestor: [LCA and binary lifting](../10-Trees/02-lca-and-binary-lifting.md); jump pointers for "next greater" chains: [CF 1175E · Minimal Segment Cover](https://codeforces.com/problemset/problem/1175/E) — 2200.
- **2D sparse table** ($O(nm\log n\log m)$ memory) for static 2D RMQ, e.g. largest square checks; usually replaced by row-wise sparse tables + monotonic deques.
- **Suffix array LCP queries** are RMQ on the LCP array: [suffix array and LCP](../11-Strings/07-suffix-array-and-lcp.md).

## 8. Practice ladder

**≤ 1800**
- [ ] [CSES 1647 · Static Range Minimum Queries](https://cses.fi/problemset/task/1647)
- [ ] [CSES 1135 · Distance Queries](https://cses.fi/problemset/task/1135)
- [ ] [CSES 1688 · Company Queries II](https://cses.fi/problemset/task/1688)
- [ ] [CF 1548B · Integers Have Friends](https://codeforces.com/problemset/problem/1548/B) — 1800
- [ ] [CF 1691D · Max GEQ Sum](https://codeforces.com/problemset/problem/1691/D) — 1800

**1800–2100**
- [ ] [CF 1547F · Array Stabilization (GCD version)](https://codeforces.com/problemset/problem/1547/F) — 1900
- [ ] [CF 359D · Pair of Numbers](https://codeforces.com/problemset/problem/359/D) — 2000
- [ ] [CF 514D · R2D2 and Droid Army](https://codeforces.com/problemset/problem/514/D) — 2000
- [ ] [CF 475D · CGCDSSQ](https://codeforces.com/problemset/problem/475/D) — 2000
- [ ] [CF 689D · Friends and Subsequences](https://codeforces.com/problemset/problem/689/D) — 2100
- [ ] [CF 474F · Ant colony](https://codeforces.com/problemset/problem/474/F) — 2100

**2100+**
- [ ] [CF 1175E · Minimal Segment Cover](https://codeforces.com/problemset/problem/1175/E) — 2200
- [ ] [CF 1849E · Max to the Right of Min](https://codeforces.com/problemset/problem/1849/E) — 2300
- [ ] [CF 1771F · Hossam and Range Minimum Query](https://codeforces.com/problemset/problem/1771/F) — 2500

## 9. LeetCode / FAANG cross-reference

- [LC 239 · Sliding Window Maximum](https://leetcode.com/problems/sliding-window-maximum/) — Hard — a sparse table works ($O(n\log n)$), but the expected answer is the $O(n)$ monotonic deque.
- [LC 1438 · Longest Continuous Subarray With Absolute Diff Less Than or Equal to Limit](https://leetcode.com/problems/longest-continuous-subarray-with-absolute-diff-less-than-or-equal-to-limit/) — Medium — two pointers + range max/min (sparse table or two deques).
- [LC 1483 · Kth Ancestor of a Tree Node](https://leetcode.com/problems/kth-ancestor-of-a-tree-node/) — Hard — the tree version of doubling tables (binary lifting).
- [LC 1157 · Online Majority Element In Subarray](https://leetcode.com/problems/online-majority-element-in-subarray/) — Hard — static range queries where the idempotent trick does not apply; shows when to switch structures.

Rare in interviews: sparse tables are almost never expected; the deque and binary lifting are the interview-level relatives.

## 10. Self-check

1. Why does the two-block query need idempotence? Name three idempotent and three non-idempotent operations.
2. Write the recurrence for `sp[k][i]` and the exact loop bound for `i`.
3. For $l = 5$, $r = 12$ (0-indexed), which two blocks does the query use?
4. How does the disjoint sparse table pick its level, and why does one combine suffice?
5. Prove that the minimum-depth vertex between the first occurrences of $u$ and $v$ in the Euler tour is their LCA.
6. For fixed $l$, why does $\gcd(a_l..a_r)$ take at most $\log_2 V + 1$ values?
7. When is two pointers preferable to binary search on top of a sparse table?

<details><summary>Answers</summary>

1. The two blocks overlap, so elements in the overlap are combined twice; this is harmless iff $x\oplus x = x$. Idempotent: min, max, gcd (also and, or). Not: sum, xor, product.
2. $\mathrm{sp}[k][i] = \mathrm{sp}[k-1][i]\oplus\mathrm{sp}[k-1][i + 2^{k-1}]$ for $0 \le i \le n - 2^k$.
3. Length 8, $k = 3$: $[5, 12]$ and $[12 - 8 + 1, 12] = [5, 12]$ — the same block (exact power of two).
4. $h = \lfloor\log_2(l \oplus r)\rfloor$; at that level $l$ and $r$ share a block of size $2^{h+1}$ but sit in different halves, so the range is (suffix of left half from $l$) + (prefix of right half up to $r$).
5. The tour segment between them is a walk inside the LCA's subtree from $u$ to $v$; it passes through the LCA (to cross between the two child subtrees, or because one is the ancestor) and never visits a proper ancestor of the LCA.
6. Each time the gcd changes it becomes a proper divisor, so at least halves; starting from $\le V$ it can change at most $\log_2 V$ times.
7. When the predicate is monotone in both endpoints (window property), two pointers needs $O(n)$ queries instead of $O(n\log n)$ — matters when each query is a gcd.

</details>
