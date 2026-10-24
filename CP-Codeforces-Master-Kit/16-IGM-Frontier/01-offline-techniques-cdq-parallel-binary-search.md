# Offline techniques: CDQ divide and conquer, parallel binary search, offline sorting + DSU

> **Band:** 🟠 2100–2600 (offline sorting + DSU starts at 🔵 1700) · **Priority:** ⚡ (offline sorting + DSU: 🔥; CDQ and overall binary search: ⚡ after Master basics) · **FAANG:** low (the "sort the queries" pattern: medium) · **Prerequisites:** [Fenwick tree](../08-Data-Structures/01-fenwick-tree.md), [DSU](../08-Data-Structures/06-dsu-and-variants.md), [binary search on the answer](../02-Core-Techniques/02-binary-search-and-binary-search-on-answer.md), [sorting and comparators](../01-Foundations/05-sorting-and-comparators.md)
> **You can say you know this when:** you can write 3D dominance counting with CDQ from memory and explain why each pair is counted exactly once; you can turn "for each query, the first time X happens" into parallel binary search; and you reach for "sort the queries" automatically whenever a problem has a monotone threshold.

## 1. First principles — why this works

### 1.1 What "offline" buys you

A problem is **online** when you must answer query $i$ before you see query $i+1$ (often enforced by XOR-ing inputs with the last answer). Otherwise it is **offline**: you may read everything first. Reading everything first gives you three freedoms that online algorithms do not have:

1. **Reorder the queries** (sort by threshold, by right endpoint, by value).
2. **Reorder time** (process deletions backwards as insertions; split the timeline in halves).
3. **Answer many queries in one pass** (share one sweep among many independent binary searches).

Almost every technique in this file is one of these three freedoms applied to a data structure that is too weak to do the job online. The rule of thumb: *if the natural online structure would need deletions, persistence or 2D/3D ranges, ask whether an offline reordering removes that need.*

### 1.2 Offline sorting + DSU: make the structure monotone

DSU supports *union* and *find*, never *split*. Suppose each query asks about the graph containing only edges of weight $\le w_q$. Online you would need a structure that can "remove" heavy edges. Offline, sort the queries by $w_q$ and the edges by weight: as $w$ grows, edges are only ever **added**, which is exactly what DSU does. Each edge is united once and each query is answered after the pointer passes its threshold: $O((m + q)\log(m+q) + (m+q)\,\alpha(n))$.

The same idea with time reversed handles **deletions only**: process the operations backwards, so deletions become insertions (see [CF 722C · Destroying Array](https://codeforces.com/problemset/problem/722/C) — 1600). The general lesson is to find the direction in which your structure only grows.

### 1.3 CDQ divide and conquer: one dimension per recursion

Start with the counting problem: for each point $i$, count $j \ne i$ with $a_j \le a_i,\ b_j \le b_i,\ c_j \le c_i$ (3D dominance, "3D partial order").

- **1D:** sort by $a$; the answer is the rank. $O(n \log n)$.
- **2D:** sort by $a$, sweep, and keep the $b$ values seen so far in a Fenwick tree; query the prefix count of $b_i$. One dimension is killed by the *order*, the other by the *data structure*. $O(n \log n)$.
- **3D, naive:** a 2D Fenwick tree (memory $O(n^2)$ or offline compression tricks) or $O(n^2)$ brute force. Too slow or too big.

The key observation (credited to Chen Danqi, hence "CDQ"): sort by $a$ and split the array in the middle. Every pair $(j, i)$ is in exactly one of three classes: both in the left half, both in the right half, or **$j$ left, $i$ right**. The first two are recursive calls. For the third, the $a$-condition is *already satisfied* by every such pair, because everything on the left has $a$ no larger than everything on the right. So the cross pairs form a **2D** problem in $(b, c)$ — which the sort + Fenwick sweep solves in $O(\text{len}\log n)$.

Correctness details that a strong solver checks:

- **Can a right point dominate a left point?** After sorting lexicographically by $(a,b,c)$ and merging identical triples, a right point $j$ and a left point $i$ satisfy $(a_i,b_i,c_i) < (a_j,b_j,c_j)$. If $j$ dominated $i$ then $a_j \le a_i$, so $a_j = a_i$; then $b_j \ge b_i$ and dominance forces $b_j = b_i$, then $c_j > c_i$ contradicts $c_j \le c_i$. So only left→right contributions exist and nothing is missed.
- **Duplicates.** Identical triples dominate each other in both directions, which breaks the argument above. Merge them into one weighted point with multiplicity $\text{cnt}$, add $\text{cnt}-1$ at the end.
- **Each pair counted once:** a pair is separated at exactly one recursion node (their lowest common ancestor in the recursion tree).

Complexity: $T(n) = 2T(n/2) + O(n \log n)$. The recursion tree has $\log_2 n$ levels and each level does $O(n)$ Fenwick operations of cost $O(\log n)$, so $T(n) = O(n \log^2 n)$. If you merge-sort by $b$ during the recursion (as in the code below) instead of re-sorting, the merging is $O(n)$ per level and the $\log^2$ comes only from the Fenwick tree.

**CDQ on time (updates → queries).** Replace the first coordinate by *time*. Given a sequence of updates and queries where a query's answer is a sum of contributions of earlier updates, split the timeline in half. For a pair (update in the left half, query in the right half) the time condition is automatically true, so at each node you solve a **static** problem: "these points are present, answer these queries". A dynamic 2D problem becomes a static 2D problem per node, i.e. $O(n \log^2 n)$ overall. It works whenever contributions are *decomposable* (sum, count, max, min — anything where the answer is an aggregate over earlier updates and the static version is easy).

### 1.4 Parallel binary search: many binary searches, one sweep

Typical shape: events $1..K$ happen in order; each query $q$ asks for the **first** $t$ such that a predicate $P_q(t)$ holds, and $P_q$ is monotone in $t$ (false, false, …, true, true). One binary search per query needs $O(\log K)$ evaluations, and each evaluation needs the state after $t$ events — rebuilding that state costs $O(K)$. Total $O(qK\log K)$: hopeless.

Observation: in one "round" every query needs **one** state, the state after its current $\text{mid}$. If we sort the queries by $\text{mid}$ and sweep $t = 1..K$ once, applying event $t$ and then checking every query whose $\text{mid}=t$, all queries advance one binary-search step for the price of one sweep. After $\lceil \log_2(K+1)\rceil$ rounds every interval has length 1.

$$\text{cost} = O\big(\log K \cdot (K \cdot U + q \cdot C)\big)$$

where $U$ is the cost to apply an event and $C$ the cost of one check. Requirements: (1) monotone predicate; (2) the state after $t$ events is obtained incrementally; (3) checks are independent of each other.

### 1.5 Divide and conquer on the answer ("overall binary search")

The recursive cousin of parallel binary search. Maintain `solve(lo, hi, Q, E)` with the invariant: *every query in $Q$ has its answer in $[lo, hi]$, and $E$ holds exactly the elements/updates whose value is in $[lo, hi]$*. Take $\text{mid}$; insert the elements of $E$ with value $\le \text{mid}$ into a structure; for each query count how many relevant elements are $\le \text{mid}$; queries that are satisfied go left, others subtract the count from their $k$ and go right. Elements split the same way.

Each element and each query is in exactly one node per depth, so there are $O((n+q)\log V)$ visits in total, each costing a Fenwick operation. Static range $k$-th smallest becomes $O((n+q)\log V \log n)$ with a 1D Fenwick tree — no persistent segment tree needed — and the method extends to point updates (insert each update as two signed events in time order), which persistent trees do not handle easily.

### 1.6 Choosing among them

| You see | Freedom used | Technique |
|---|---|---|
| Queries with a monotone threshold over a growing structure | reorder queries | sort queries + DSU / Fenwick sweep |
| Only deletions | reverse time | process backwards as insertions |
| "Count $j$ with three $\le$ conditions" or "dynamic 2D counting" | split one dimension (or time) in halves | CDQ |
| "First time each query's condition holds" | share a sweep | parallel binary search |
| "$k$-th smallest / threshold answer" over many queries, maybe with updates | split the value range | overall binary search |

## 2. Formulas, definitions and identities

- **3D dominance count:** $f(i) = \#\{\,j \ne i : a_j \le a_i,\ b_j \le b_i,\ c_j \le c_i\,\}$.
- **CDQ recurrence:** $T(n) = 2T(n/2) + O(n\log n) \Rightarrow T(n) = O(n\log^2 n)$. Proof: level $\ell$ has $2^\ell$ subproblems of size $n/2^\ell$, each costing $O((n/2^\ell)\log n)$; summing over $\log_2 n$ levels gives $O(n \log n \cdot \log n)$.
- **$k$-dimensional dominance by nested CDQ:** $O(n \log^{k-1} n)$ — each extra dimension costs one more $\log$ (one CDQ layer per dimension beyond the two handled by sort + Fenwick).
- **Rectangle by prefix sums (inclusion–exclusion):** with $S(x,y) = \sum_{x_p \le x,\, y_p \le y} w_p$,
  $$\operatorname{rect}(x_1,y_1,x_2,y_2) = S(x_2,y_2) - S(x_1-1,y_2) - S(x_2,y_1-1) + S(x_1-1,y_1-1).$$
- **Parallel binary search rounds:** answers in $\{1,\dots,K\} \cup \{\text{never}\}$ need $\lceil\log_2(K+1)\rceil$ rounds. Cost $O(\log K\,(K U + qC))$.
- **Overall binary search:** depth $\lceil \log_2 V\rceil$ for $V$ distinct values; total cost $O((n+q)\log V \cdot \log n)$ with a Fenwick tree.
- **Offline sorting + DSU:** $O((m+q)\log(m+q) + (m+q)\,\alpha(n))$.
- **Mo's algorithm** (the other big offline technique, see [sqrt decomposition and Mo](../08-Data-Structures/07-sqrt-decomposition-and-mos-algorithm.md)): $O((n+q)\sqrt n)$ pointer moves.

| Technique | Time | Memory | Needs |
|---|---|---|---|
| Sort queries + DSU | $O((m+q)\log)$ | $O(n+m+q)$ | monotone threshold |
| CDQ (3D / dynamic 2D) | $O(n\log^2 n)$ | $O(n)$ | decomposable contributions |
| Parallel binary search | $O(\log K (KU + qC))$ | $O(n + q + K)$ | monotone predicate in time |
| Overall binary search | $O((n+q)\log V\log n)$ | $O(n+q)$ per level | answer is a threshold on a value |

## 3. Implementation (C++ and Java)

### 3.1 CDQ: 3D dominance counting

Input: $n$, then $n$ triples $a\ b\ c$ ($1 \le n \le 2\cdot 10^5$, values up to $10^9$). Output: $f(i)$ for each point in input order. The code sorts by $(a,b,c)$, merges duplicates, and inside the recursion merge-sorts by $b$ so each node sees both halves sorted by $b$.

```cpp
#include <bits/stdc++.h>
using namespace std;

// CDQ divide and conquer: for every point i count j != i with a_j<=a_i, b_j<=b_i, c_j<=c_i.
struct P { int a, b, c, cnt, res, id; };
int K;
vector<int> bit;
void add(int i, int v) { for (; i <= K; i += i & -i) bit[i] += v; }
int sum(int i) { int s = 0; for (; i > 0; i -= i & -i) s += bit[i]; return s; }
vector<P> p, tmp;

void cdq(int l, int r) {                      // half-open [l, r), p[l..r) sorted by (a, b, c)
    if (r - l <= 1) return;
    int m = (l + r) / 2;
    cdq(l, m);
    cdq(m, r);                                // now each half is sorted by b
    int i = l;
    for (int j = m; j < r; j++) {             // left half has smaller (a,b,c) => only left -> right counts
        while (i < m && p[i].b <= p[j].b) { add(p[i].c, p[i].cnt); i++; }
        p[j].res += sum(p[j].c);
    }
    for (int t = l; t < i; t++) add(p[t].c, -p[t].cnt);   // undo: BIT must be empty again
    merge(p.begin() + l, p.begin() + m, p.begin() + m, p.begin() + r, tmp.begin() + l,
          [](const P& x, const P& y) { return x.b < y.b; });
    copy(tmp.begin() + l, tmp.begin() + r, p.begin() + l);
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<array<int, 3>> pts(n);
    for (auto& [a, b, c] : pts) cin >> a >> b >> c;
    vector<int> cs;
    for (auto& t : pts) cs.push_back(t[2]);
    sort(cs.begin(), cs.end());
    cs.erase(unique(cs.begin(), cs.end()), cs.end());
    K = cs.size();
    bit.assign(K + 1, 0);
    vector<int> ord(n);
    iota(ord.begin(), ord.end(), 0);
    sort(ord.begin(), ord.end(), [&](int x, int y) { return pts[x] < pts[y]; });
    vector<int> uid(n);                        // equal triples are merged into one weighted point
    for (int k = 0; k < n; k++) {
        auto& t = pts[ord[k]];
        if (p.empty() || pts[ord[k - 1]] != t) {
            int c = lower_bound(cs.begin(), cs.end(), t[2]) - cs.begin() + 1;
            p.push_back({t[0], t[1], c, 0, 0, (int)p.size()});
        }
        p.back().cnt++;
        uid[ord[k]] = p.size() - 1;
    }
    tmp.resize(p.size());
    cdq(0, p.size());
    vector<int> ans(p.size());
    for (auto& q : p) ans[q.id] = q.res + q.cnt - 1;   // copies of the same triple dominate each other
    for (int i = 0; i < n; i++) cout << ans[uid[i]] << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static int K;
    static int[] bit, A, B, C, cnt, res, ord, tmp;

    static void add(int i, int v) { for (; i <= K; i += i & -i) bit[i] += v; }
    static int sum(int i) { int s = 0; for (; i > 0; i -= i & -i) s += bit[i]; return s; }

    // ord[l..r) holds unique points sorted by (a,b,c); afterwards it is sorted by b
    static void cdq(int l, int r) {
        if (r - l <= 1) return;
        int m = (l + r) >>> 1;
        cdq(l, m);
        cdq(m, r);
        int i = l;
        for (int j = m; j < r; j++) {
            int q = ord[j];
            while (i < m && B[ord[i]] <= B[q]) { add(C[ord[i]], cnt[ord[i]]); i++; }
            res[q] += sum(C[q]);
        }
        for (int t = l; t < i; t++) add(C[ord[t]], -cnt[ord[t]]);
        int x = l, y = m, k = l;                       // stable merge by b
        while (x < m || y < r) {
            if (y == r || (x < m && B[ord[x]] <= B[ord[y]])) tmp[k++] = ord[x++];
            else tmp[k++] = ord[y++];
        }
        System.arraycopy(tmp, l, ord, l, r - l);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[][] pts = new int[n][];
        for (int i = 0; i < n; i++) pts[i] = new int[]{in.nextInt(), in.nextInt(), in.nextInt(), i};
        Arrays.sort(pts, (x, y) -> x[0] != y[0] ? Integer.compare(x[0], y[0])
                : x[1] != y[1] ? Integer.compare(x[1], y[1]) : Integer.compare(x[2], y[2]));
        int[] cs = new int[n];
        for (int i = 0; i < n; i++) cs[i] = pts[i][2];
        shuffleSort(cs);                               // never Arrays.sort(int[]) on hackable data without shuffling
        int dk = 0;
        for (int i = 0; i < n; i++) if (dk == 0 || cs[dk - 1] != cs[i]) cs[dk++] = cs[i];
        K = dk;
        bit = new int[K + 1];
        A = new int[n]; B = new int[n]; C = new int[n]; cnt = new int[n]; res = new int[n];
        int[] uid = new int[n];
        int u = 0;
        for (int i = 0; i < n; i++) {
            int[] t = pts[i];
            if (u == 0 || A[u - 1] != t[0] || B[u - 1] != t[1] || cs[C[u - 1] - 1] != t[2]) {
                A[u] = t[0]; B[u] = t[1];
                C[u] = Arrays.binarySearch(cs, 0, dk, t[2]) + 1;
                u++;
            }
            cnt[u - 1]++;
            uid[t[3]] = u - 1;
        }
        ord = new int[u];
        tmp = new int[u];
        for (int i = 0; i < u; i++) ord[i] = i;
        cdq(0, u);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < n; i++) sb.append(res[uid[i]] + cnt[uid[i]] - 1).append('\n');
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.print(sb);
        out.flush();
    }

    static void shuffleSort(int[] a) {
        Random r = new Random(System.nanoTime());
        for (int i = a.length - 1; i > 0; i--) { int j = r.nextInt(i + 1); int t = a[i]; a[i] = a[j]; a[j] = t; }
        Arrays.sort(a);
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
        int nextInt() throws IOException {
            int ret = 0, b = read();
            while (b <= ' ') b = read();
            boolean neg = b == '-';
            if (neg) b = read();
            while (b >= '0' && b <= '9') { ret = ret * 10 + (b - '0'); b = read(); }
            return neg ? -ret : ret;
        }
    }
}
```

<!-- test
in:
5
1 2 3
2 2 3
1 1 1
3 3 3
2 2 3
out:
1
3
0
4
3
-->
<!-- test
in:
1
7 7 7
out:
0
-->
<!-- test
in:
3
4 4 4
4 4 4
4 4 4
out:
2
2
2
-->
<!-- test
in:
4
1 4 2
2 3 1
3 2 4
4 1 3
out:
0
0
0
0
-->

Stress-tested against the $O(n^2)$ count on 300 random cases with tiny value ranges (lots of ties); $n = 2\cdot10^5$ runs in about 1 s (C++) and 1.9 s (Java) on the test machine.

### 3.2 The parallel binary search skeleton

```text
lo[q] = 1, hi[q] = K + 1           # K + 1 means "never"
repeat while some lo[q] < hi[q]:
    bucket every unfinished q by mid = (lo[q] + hi[q]) / 2
    reset the structure
    for t in 1..K:
        apply event t
        for q in bucket[t]:
            if P_q holds now: hi[q] = t else lo[q] = t + 1
answer[q] = lo[q]  (K + 1 -> "never")
```

Full tested code for this skeleton is in Example 2 below.

## 4. Recognising the pattern

- **"Using only edges of weight $\le w$" / "only elements $\ge x$"** with many queries → sort queries by the threshold, add elements as the threshold grows (DSU, Fenwick, trie).
- **Only deletions, or "after each removal print …"** → reverse time.
- **Three independent $\le$ / $<$ conditions** between pairs ("count pairs with $i<j$, $a_i<a_j$, $b_i<b_j$") → CDQ. Two conditions → sort + Fenwick, not CDQ.
- **A dynamic 2D problem (insert point / query rectangle) with $q \le 2\cdot 10^5$ and no forced online** → CDQ on time instead of a 2D tree.
- **"For each $X$, find the first moment / the minimum $k$ such that …"** with a monotone condition and an expensive state → parallel binary search. Typical: "minimum number of the first edges so that $u$ and $v$ are connected", "first day when the region has collected enough".
- **"$k$-th smallest", "minimum $x$ such that at least $k$ …" over many queries** → overall binary search (or persistent segment tree if online).
- **Online is forced** (queries XOR-ed with the last answer): none of these apply directly; you need persistent structures ([persistent data structures](../08-Data-Structures/08-persistent-data-structures.md)) or a Kruskal reconstruction tree.

Commonly confused: CDQ vs. merge-sort inversion counting (inversions are the 2D special case where one dimension is the index); parallel binary search vs. a single binary search on the answer (that is enough when there is *one* query); Mo's algorithm (offline, but for range queries whose answer is not decomposable, e.g. "number of distinct values").

## 5. Worked examples (graded)

### Example 1 — Component size under a weight limit  ·  ★ ≈1800 (est.)

- **Source:** Original problem (same idea as [CF 1213G · Path Queries](https://codeforces.com/problemset/problem/1213/G) — 1800 and [LC 1697 · Checking Existence of Edge Length Limited Paths](https://leetcode.com/problems/checking-existence-of-edge-length-limited-paths/) — Hard).
- **Difficulty:** ≈1800 (est.)
- **Problem:** An undirected graph has $n$ vertices and $m$ weighted edges ($n, m, q \le 2\cdot10^5$, weights $\le 10^9$). Each query $(v, w)$ asks for the number of vertices reachable from $v$ using only edges of weight $\le w$. Print the answers in input order.
- **Thinking from first principles:** BFS per query is $O(q(n+m))$. The structure "components using edges $\le w$" only grows as $w$ grows, and DSU handles growth. Online we cannot shrink a DSU, but nothing forces us to answer in input order. Sort both lists by weight, move a pointer over the edges, answer each query when the pointer has passed every edge of weight $\le w$. Dead end avoided: trying to delete edges for smaller $w$.

<details><summary>Solution</summary>

Sort edges by weight and queries by limit; for each query in increasing limit, unite all edges with weight $\le$ limit, then read the size of $v$'s component. Correctness: when query $(v,w)$ is answered, the DSU contains exactly the edges of weight $\le w$ (the pointer stopped at the first heavier edge). Complexity $O((m+q)\log(m+q) + (m+q)\alpha(n))$.

The Java version sorts packed `long` keys (`weight << 20 | index`) after a shuffle, which avoids both boxing and the `Arrays.sort(int[])` anti-quicksort worst case.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct DSU {
    vector<int> p, sz;
    DSU(int n) : p(n), sz(n, 1) { iota(p.begin(), p.end(), 0); }
    int find(int x) { while (p[x] != x) x = p[x] = p[p[x]]; return x; }   // path halving
    void unite(int a, int b) {
        a = find(a); b = find(b);
        if (a == b) return;
        if (sz[a] < sz[b]) swap(a, b);
        p[b] = a; sz[a] += sz[b];
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m, q;
    cin >> n >> m >> q;
    vector<array<int, 3>> e(m);                       // {w, u, v}
    for (auto& [w, u, v] : e) { cin >> u >> v >> w; u--; v--; }
    vector<array<int, 3>> qs(q);                      // {limit, vertex, index}
    for (int i = 0; i < q; i++) { cin >> qs[i][1] >> qs[i][0]; qs[i][1]--; qs[i][2] = i; }
    sort(e.begin(), e.end());
    sort(qs.begin(), qs.end());
    DSU d(n);
    vector<int> ans(q);
    int j = 0;
    for (auto& [lim, v, id] : qs) {                   // queries in increasing limit: edges only get added
        while (j < m && e[j][0] <= lim) { d.unite(e[j][1], e[j][2]); j++; }
        ans[id] = d.sz[d.find(v)];
    }
    for (int x : ans) cout << x << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static int[] par, sz;
    static int find(int x) { while (par[x] != x) x = par[x] = par[par[x]]; return x; }
    static void unite(int a, int b) {
        a = find(a); b = find(b);
        if (a == b) return;
        if (sz[a] < sz[b]) { int t = a; a = b; b = t; }
        par[b] = a; sz[a] += sz[b];
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt(), q = in.nextInt();
        int[] eu = new int[m], ev = new int[m];
        long[] ek = new long[m];                       // key = weight << 20 | index (m, q < 2^20)
        for (int i = 0; i < m; i++) {
            eu[i] = in.nextInt() - 1; ev[i] = in.nextInt() - 1;
            ek[i] = ((long) in.nextInt() << 20) | i;
        }
        int[] qv = new int[q];
        long[] qk = new long[q];
        for (int i = 0; i < q; i++) { qv[i] = in.nextInt() - 1; qk[i] = ((long) in.nextInt() << 20) | i; }
        shuffleSort(ek);
        shuffleSort(qk);
        par = new int[n]; sz = new int[n];
        for (int i = 0; i < n; i++) { par[i] = i; sz[i] = 1; }
        int[] ans = new int[q];
        int j = 0;
        for (long k : qk) {
            long lim = k >> 20;
            int id = (int) (k & ((1 << 20) - 1));
            while (j < m && (ek[j] >> 20) <= lim) { int e = (int) (ek[j] & ((1 << 20) - 1)); unite(eu[e], ev[e]); j++; }
            ans[id] = sz[find(qv[id])];
        }
        StringBuilder sb = new StringBuilder();
        for (int x : ans) sb.append(x).append('\n');
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.print(sb);
        out.flush();
    }

    static void shuffleSort(long[] a) {
        Random r = new Random(System.nanoTime());
        for (int i = a.length - 1; i > 0; i--) { int j = r.nextInt(i + 1); long t = a[i]; a[i] = a[j]; a[j] = t; }
        Arrays.sort(a);
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
        int nextInt() throws IOException {
            int ret = 0, b = read();
            while (b <= ' ') b = read();
            boolean neg = b == '-';
            if (neg) b = read();
            while (b >= '0' && b <= '9') { ret = ret * 10 + (b - '0'); b = read(); }
            return neg ? -ret : ret;
        }
    }
}
```

</details>

<!-- test
in:
5 4 5
1 2 3
2 3 5
4 5 1
3 4 10
1 2
1 3
3 5
4 9
5 10
out:
1
2
3
2
5
-->
<!-- test
in:
3 0 2
1 0
3 1000000000
out:
1
1
-->

### Example 2 — First moment each quota is met  ·  ★ ≈2300 (est.)

- **Source:** Original problem, the line version of the classic POI 2011 problem "Meteors", which is the standard parallel-binary-search exercise.
- **Difficulty:** ≈2300 (est.)
- **Problem:** $m$ sectors in a row, sector $j$ owned by member $o_j$ (of $n$ members). Member $i$ needs $\text{need}_i$ units. $K$ events happen in order; event $t$ adds $x_t$ units to every sector in $[l_t, r_t]$. For every member print the first event after which the member's total is $\ge \text{need}_i$, or $-1$. ($n, m, K \le 3\cdot10^5$, $x_t \le 10^9$.)
- **Thinking from first principles:** For one member, binary search on $t$ works: "total after $t$ events $\ge$ need" is monotone. But evaluating it needs the array after $t$ events, an $O(K\log m)$ replay. All members' checks in one round can share one replay: bucket them by their current mid, replay the events with a range-add Fenwick tree, check each member right after its mid. Each member's check costs (number of its sectors) $\times \log m$, and the sectors sum to $m$, so one round is $O((K + m)\log m)$, and there are $\lceil\log_2(K+1)\rceil \approx 19$ rounds.

<details><summary>Solution</summary>

Keep $[lo_i, hi_i]$ with $hi_i = K+1$ meaning "never". Each round: bucket unfinished members by $\text{mid}$, clear the Fenwick tree, apply events $1..K$ in order, and after event $t$ check the members in bucket $t$. A total can reach $m \cdot K \cdot x \approx 9\cdot10^{19}$, which overflows 64 bits, so stop summing a member's sectors as soon as the need is reached. Complexity $O(\log K\,(K + m)\log m)$; about 3.3 s for $n = m = K = 3\cdot10^5$ in both languages on the (slow, shared) test machine. That is at the edge of a 2 s limit: the cost is $\lceil\log_2(K+1)\rceil$ full replays of all $K$ events, so constant factors matter (range-add/point-query Fenwick tree, counting buckets, no per-round allocation, CSR sector lists in Java).

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int m;
vector<ll> bit;
void add(int i, ll v) { for (; i <= m; i += i & -i) bit[i] += v; }
void rangeAdd(int l, int r, ll v) { add(l, v); if (r + 1 <= m) add(r + 1, -v); }
ll pointQuery(int i) { ll s = 0; for (; i > 0; i -= i & -i) s += bit[i]; return s; }

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, k;
    cin >> n >> m >> k;
    vector<vector<int>> own(n);
    for (int j = 1; j <= m; j++) { int o; cin >> o; own[o - 1].push_back(j); }
    vector<ll> need(n);
    for (auto& x : need) cin >> x;
    vector<int> L(k + 1), R(k + 1);
    vector<ll> X(k + 1);
    for (int t = 1; t <= k; t++) cin >> L[t] >> R[t] >> X[t];
    vector<int> lo(n, 1), hi(n, k + 1);              // answer in [lo, hi]; k+1 = "never"
    vector<vector<int>> at(k + 2);
    while (true) {
        bool any = false;
        for (int i = 0; i < n; i++)
            if (lo[i] < hi[i]) { at[(lo[i] + hi[i]) / 2].push_back(i); any = true; }
        if (!any) break;
        bit.assign(m + 1, 0);
        for (int t = 1; t <= k; t++) {               // one sweep answers "is answer <= mid?" for everyone
            rangeAdd(L[t], R[t], X[t]);
            for (int i : at[t]) {
                ll s = 0;
                for (int j : own[i]) { s += pointQuery(j); if (s >= need[i]) break; }   // early exit: no overflow
                if (s >= need[i]) hi[i] = t; else lo[i] = t + 1;
            }
            at[t].clear();
        }
    }
    for (int i = 0; i < n; i++) cout << (lo[i] == k + 1 ? -1 : lo[i]) << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static int m;
    static long[] bit;
    static void add(int i, long v) { for (; i <= m; i += i & -i) bit[i] += v; }
    static void rangeAdd(int l, int r, long v) { add(l, v); if (r + 1 <= m) add(r + 1, -v); }
    static long pointQuery(int i) { long s = 0; for (; i > 0; i -= i & -i) s += bit[i]; return s; }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        m = in.nextInt();
        int k = in.nextInt();
        int[] owner = new int[m + 1], start = new int[n + 1], sec = new int[m];
        for (int j = 1; j <= m; j++) { owner[j] = in.nextInt() - 1; start[owner[j] + 1]++; }
        for (int i = 0; i < n; i++) start[i + 1] += start[i];          // CSR layout of each member's sectors
        int[] fill = Arrays.copyOf(start, n + 1);
        for (int j = 1; j <= m; j++) sec[fill[owner[j]]++] = j;
        long[] need = new long[n];
        for (int i = 0; i < n; i++) need[i] = in.nextLong();
        int[] L = new int[k + 1], R = new int[k + 1];
        long[] X = new long[k + 1];
        for (int t = 1; t <= k; t++) { L[t] = in.nextInt(); R[t] = in.nextInt(); X[t] = in.nextLong(); }
        int[] lo = new int[n], hi = new int[n];
        Arrays.fill(lo, 1);
        Arrays.fill(hi, k + 1);
        int[] head = new int[k + 2], nxt = new int[n];
        bit = new long[m + 1];
        while (true) {
            Arrays.fill(head, -1);
            boolean any = false;
            for (int i = 0; i < n; i++)
                if (lo[i] < hi[i]) { int mid = (lo[i] + hi[i]) >>> 1; nxt[i] = head[mid]; head[mid] = i; any = true; }
            if (!any) break;
            Arrays.fill(bit, 0);
            for (int t = 1; t <= k; t++) {
                rangeAdd(L[t], R[t], X[t]);
                for (int i = head[t]; i != -1; i = nxt[i]) {
                    long s = 0;
                    for (int p = start[i]; p < start[i + 1] && s < need[i]; p++) s += pointQuery(sec[p]);
                    if (s >= need[i]) hi[i] = t; else lo[i] = t + 1;
                }
            }
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < n; i++) sb.append(lo[i] == k + 1 ? -1 : lo[i]).append('\n');
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
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
        long nextLong() throws IOException {
            long ret = 0;
            int b = read();
            while (b <= ' ') b = read();
            boolean neg = b == '-';
            if (neg) b = read();
            while (b >= '0' && b <= '9') { ret = ret * 10 + (b - '0'); b = read(); }
            return neg ? -ret : ret;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
3 5 4
1 2 3 1 2
7 5 7
1 2 3
2 5 2
3 3 10
1 5 1
out:
4
2
3
-->
<!-- test
in:
1 1 1
1
100
1 1 5
out:
-1
-->

### Example 3 — Static range k-th smallest by overall binary search  ·  ★ ≈2300 (est.)

- **Source:** Original problem (the classic "k-th number" task; the same queries are solved online with a persistent segment tree in [persistent data structures](../08-Data-Structures/08-persistent-data-structures.md)).
- **Difficulty:** ≈2300 (est.)
- **Problem:** Array $a_1..a_n$ ($|a_i| \le 10^9$), $q$ queries $(l, r, k)$: print the $k$-th smallest of $a_l..a_r$. $n, q \le 2\cdot10^5$.
- **Thinking from first principles:** For one query, binary search on the value $x$: "how many elements of $[l,r]$ are $\le x$?" is monotone in $x$. Doing it separately per query costs $O(n)$ per check. Instead recurse on the value range: at a node with range $[lo, hi]$, put all elements with value in $[lo, \text{mid}]$ into a Fenwick tree over positions; each query reads its count $c$ in $O(\log n)$ and decides its side. The elements in $[\text{mid}+1, hi]$ are irrelevant to the left side and their count is irrelevant to the right side once we subtract $c$ from $k$.

<details><summary>Solution</summary>

Compress values to $0..V-1$. `solve(lo, hi, el, qs)`: if $lo = hi$ every query in `qs` has answer $lo$. Otherwise add the elements with value $\le \text{mid}$, query each $(l,r)$, route queries with $k \le c$ left and the rest right with $k \leftarrow k - c$, clear the Fenwick tree by undoing the additions (never by reallocating: that would cost $O(n)$ per node), and recurse. Every element and query is visited once per level, so the total is $O((n+q)\log V\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int n;
vector<int> bit, a, L, R, K, ans;
void add(int i, int v) { for (; i <= n; i += i & -i) bit[i] += v; }
int sum(int i) { int s = 0; for (; i > 0; i -= i & -i) s += bit[i]; return s; }

// every query in qs has its answer (a compressed value) in [lo, hi]; el = positions whose value is in [lo, hi]
void solve(int lo, int hi, vector<int>& el, vector<int>& qs) {
    if (qs.empty()) return;
    if (lo == hi) { for (int q : qs) ans[q] = lo; return; }
    int mid = (lo + hi) / 2;
    vector<int> el1, el2, q1, q2;
    for (int p : el) {
        if (a[p] <= mid) { add(p, 1); el1.push_back(p); }
        else el2.push_back(p);
    }
    for (int q : qs) {
        int c = sum(R[q]) - sum(L[q] - 1);          // how many values <= mid lie in [l, r]
        if (K[q] <= c) q1.push_back(q);
        else { K[q] -= c; q2.push_back(q); }        // skip the c smaller values, look on the right
    }
    for (int p : el1) add(p, -1);
    vector<int>().swap(el);                         // free memory before recursing
    solve(lo, mid, el1, q1);
    solve(mid + 1, hi, el2, q2);
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int q;
    cin >> n >> q;
    a.resize(n + 1);
    for (int i = 1; i <= n; i++) cin >> a[i];
    vector<int> vals(a.begin() + 1, a.end());
    sort(vals.begin(), vals.end());
    vals.erase(unique(vals.begin(), vals.end()), vals.end());
    for (int i = 1; i <= n; i++) a[i] = lower_bound(vals.begin(), vals.end(), a[i]) - vals.begin();
    L.resize(q); R.resize(q); K.resize(q); ans.resize(q);
    for (int i = 0; i < q; i++) cin >> L[i] >> R[i] >> K[i];
    bit.assign(n + 1, 0);
    vector<int> el(n), qs(q);
    iota(el.begin(), el.end(), 1);
    iota(qs.begin(), qs.end(), 0);
    solve(0, vals.size() - 1, el, qs);
    for (int i = 0; i < q; i++) cout << vals[ans[i]] << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static int n;
    static int[] bit, a, L, R, K, ans;
    static void add(int i, int v) { for (; i <= n; i += i & -i) bit[i] += v; }
    static int sum(int i) { int s = 0; for (; i > 0; i -= i & -i) s += bit[i]; return s; }

    static void solve(int lo, int hi, int[] el, int ne, int[] qs, int nq) {
        if (nq == 0) return;
        if (lo == hi) { for (int i = 0; i < nq; i++) ans[qs[i]] = lo; return; }
        int mid = (lo + hi) >>> 1;
        int[] el1 = new int[ne], el2 = new int[ne], q1 = new int[nq], q2 = new int[nq];
        int n1 = 0, n2 = 0, m1 = 0, m2 = 0;
        for (int i = 0; i < ne; i++) {
            int p = el[i];
            if (a[p] <= mid) { add(p, 1); el1[n1++] = p; } else el2[n2++] = p;
        }
        for (int i = 0; i < nq; i++) {
            int q = qs[i];
            int c = sum(R[q]) - sum(L[q] - 1);
            if (K[q] <= c) q1[m1++] = q; else { K[q] -= c; q2[m2++] = q; }
        }
        for (int i = 0; i < n1; i++) add(el1[i], -1);
        solve(lo, mid, el1, n1, q1, m1);
        solve(mid + 1, hi, el2, n2, q2, m2);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        n = in.nextInt();
        int q = in.nextInt();
        a = new int[n + 1];
        for (int i = 1; i <= n; i++) a[i] = in.nextInt();
        int[] vals = Arrays.copyOfRange(a, 1, n + 1);
        shuffleSort(vals);
        int d = 0;
        for (int i = 0; i < n; i++) if (d == 0 || vals[d - 1] != vals[i]) vals[d++] = vals[i];
        for (int i = 1; i <= n; i++) a[i] = Arrays.binarySearch(vals, 0, d, a[i]);
        L = new int[q]; R = new int[q]; K = new int[q]; ans = new int[q];
        for (int i = 0; i < q; i++) { L[i] = in.nextInt(); R[i] = in.nextInt(); K[i] = in.nextInt(); }
        bit = new int[n + 1];
        int[] el = new int[n], qs = new int[q];
        for (int i = 0; i < n; i++) el[i] = i + 1;
        for (int i = 0; i < q; i++) qs[i] = i;
        solve(0, d - 1, el, n, qs, q);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < q; i++) sb.append(vals[ans[i]]).append('\n');
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.print(sb);
        out.flush();
    }

    static void shuffleSort(int[] x) {
        Random r = new Random(System.nanoTime());
        for (int i = x.length - 1; i > 0; i--) { int j = r.nextInt(i + 1); int t = x[i]; x[i] = x[j]; x[j] = t; }
        Arrays.sort(x);
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
        int nextInt() throws IOException {
            int ret = 0, b = read();
            while (b <= ' ') b = read();
            boolean neg = b == '-';
            if (neg) b = read();
            while (b >= '0' && b <= '9') { ret = ret * 10 + (b - '0'); b = read(); }
            return neg ? -ret : ret;
        }
    }
}
```

</details>

<!-- test
in:
5 3
3 1 4 1 5
1 5 3
2 4 1
3 5 3
out:
3
1
5
-->
<!-- test
in:
1 1
-7
1 1 1
out:
-7
-->
<!-- test
in:
6 4
2 2 2 9 9 1
1 6 6
1 6 1
2 5 3
4 5 2
out:
9
1
9
9
-->

### Example 4 — Dynamic rectangle sums by CDQ on time  ·  ★ ≈2400 (est.)

- **Source:** Original problem (the technique behind [CF 848C · Goodbye Souvenir](https://codeforces.com/problemset/problem/848/C) — 2600 and [CF 1093E · Intersection of Permutations](https://codeforces.com/problemset/problem/1093/E) — 2400).
- **Difficulty:** ≈2400 (est.)
- **Problem:** Process $q \le 2\cdot10^5$ operations: `1 x y w` adds weight $w$ ($|w| \le 10^9$) at point $(x,y)$; `2 x1 y1 x2 y2` prints the total weight of points in the rectangle. Coordinates are in $[1, 10^9]$.
- **Thinking from first principles:** Online this needs a 2D structure: a 2D Fenwick tree is $10^9 \times 10^9$, a segment tree of sorted vectors cannot take insertions, a BIT of treaps works but is heavy. Offline, split each rectangle into four prefix queries $S(x, y)$. A prefix query at time $t$ sums the updates with time $< t$, $x_p \le x$, $y_p \le y$ — a 3D dominance sum where the first coordinate is time. CDQ on the event index: at each node, left-half updates against right-half queries form a static 2D dominance problem (sort by $x$, Fenwick tree on compressed $y$).

<details><summary>Solution</summary>

Events are pushed in input order (a query becomes four signed prefix events with the same query id). In `cdq(l, r)`: recurse on both halves, then collect updates from $[l, m)$ and queries from $[m, r)$, sort by $x$ with updates before queries at equal $x$, sweep with a Fenwick tree over compressed $y$, and undo the Fenwick changes. The four prefix events of one query never interact, so their relative order is irrelevant. Complexity $O(q\log^2 q)$; the answer magnitude is up to $2\cdot10^5 \cdot 10^9$, so use 64-bit sums.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

struct E { int x, y; ll w; int qid; };      // qid = -1: point update of weight w; else prefix query with sign w
vector<E> ev;
vector<ll> ans, bit;
vector<int> ys;
int K;
void add(int i, ll v) { for (; i <= K; i += i & -i) bit[i] += v; }
ll sum(int i) { ll s = 0; for (; i > 0; i -= i & -i) s += bit[i]; return s; }

void cdq(int l, int r) {                    // events [l, r) in time order
    if (r - l <= 1) return;
    int m = (l + r) / 2;
    cdq(l, m);
    cdq(m, r);
    vector<E> cur;                          // updates from the left half, queries from the right half
    for (int i = l; i < m; i++) if (ev[i].qid < 0) cur.push_back(ev[i]);
    if (cur.empty()) return;
    for (int i = m; i < r; i++) if (ev[i].qid >= 0) cur.push_back(ev[i]);
    sort(cur.begin(), cur.end(), [](const E& a, const E& b) {
        if (a.x != b.x) return a.x < b.x;
        return a.qid < b.qid;               // at equal x the update (qid = -1) goes first
    });
    for (auto& e : cur) {
        if (e.qid < 0) add(lower_bound(ys.begin(), ys.end(), e.y) - ys.begin() + 1, e.w);
        else ans[e.qid] += e.w * sum(upper_bound(ys.begin(), ys.end(), e.y) - ys.begin());
    }
    for (auto& e : cur) if (e.qid < 0) add(lower_bound(ys.begin(), ys.end(), e.y) - ys.begin() + 1, -e.w);
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int q;
    cin >> q;
    int nq = 0;
    for (int i = 0; i < q; i++) {
        int t;
        cin >> t;
        if (t == 1) {
            int x, y; ll w;
            cin >> x >> y >> w;
            ev.push_back({x, y, w, -1});
            ys.push_back(y);
        } else {
            int x1, y1, x2, y2;
            cin >> x1 >> y1 >> x2 >> y2;          // inclusion-exclusion into 4 prefix queries
            ev.push_back({x2, y2, 1, nq});
            ev.push_back({x1 - 1, y2, -1, nq});
            ev.push_back({x2, y1 - 1, -1, nq});
            ev.push_back({x1 - 1, y1 - 1, 1, nq});
            nq++;
        }
    }
    sort(ys.begin(), ys.end());
    ys.erase(unique(ys.begin(), ys.end()), ys.end());
    K = ys.size();
    bit.assign(K + 1, 0);
    ans.assign(nq, 0);
    cdq(0, ev.size());
    for (ll v : ans) cout << v << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static int[] ex, ey, qid;
    static long[] ew, ans, bit;
    static int[] ys;
    static int K;
    static long[] keys;
    static void add(int i, long v) { for (; i <= K; i += i & -i) bit[i] += v; }
    static long sum(int i) { long s = 0; for (; i > 0; i -= i & -i) s += bit[i]; return s; }
    static int lower(int y) { int lo = 0, hi = K; while (lo < hi) { int md = (lo + hi) >>> 1; if (ys[md] < y) lo = md + 1; else hi = md; } return lo; }
    static int upper(int y) { int lo = 0, hi = K; while (lo < hi) { int md = (lo + hi) >>> 1; if (ys[md] <= y) lo = md + 1; else hi = md; } return lo; }

    static void cdq(int l, int r) {
        if (r - l <= 1) return;
        int m = (l + r) >>> 1;
        cdq(l, m);
        cdq(m, r);
        int c = 0;
        boolean anyUpd = false;
        for (int i = l; i < m; i++) if (qid[i] < 0) { keys[c++] = key(i, 0); anyUpd = true; }
        if (!anyUpd) return;
        for (int i = m; i < r; i++) if (qid[i] >= 0) keys[c++] = key(i, 1);
        long[] cur = Arrays.copyOf(keys, c);
        shuffle(cur);
        Arrays.sort(cur);
        for (long k : cur) {
            int i = (int) (k & ((1 << 20) - 1));
            if (qid[i] < 0) add(lower(ey[i]) + 1, ew[i]);
            else ans[qid[i]] += ew[i] * sum(upper(ey[i]));
        }
        for (long k : cur) {
            int i = (int) (k & ((1 << 20) - 1));
            if (qid[i] < 0) add(lower(ey[i]) + 1, -ew[i]);
        }
    }

    // sort key: x (shifted to be non-negative), then updates (0) before queries (1), then event index
    static long key(int i, int type) { return ((long) (ex[i] + 1) << 21) | ((long) type << 20) | i; }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int q = in.nextInt();
        ex = new int[4 * q]; ey = new int[4 * q]; qid = new int[4 * q]; ew = new long[4 * q];
        int[] yl = new int[q];
        int ne = 0, nq = 0, ny = 0;
        for (int i = 0; i < q; i++) {
            int t = in.nextInt();
            if (t == 1) {
                ex[ne] = in.nextInt(); ey[ne] = in.nextInt(); ew[ne] = in.nextLong(); qid[ne] = -1;
                yl[ny++] = ey[ne];
                ne++;
            } else {
                int x1 = in.nextInt(), y1 = in.nextInt(), x2 = in.nextInt(), y2 = in.nextInt();
                int[][] pr = {{x2, y2, 1}, {x1 - 1, y2, -1}, {x2, y1 - 1, -1}, {x1 - 1, y1 - 1, 1}};
                for (int[] p : pr) { ex[ne] = p[0]; ey[ne] = p[1]; ew[ne] = p[2]; qid[ne] = nq; ne++; }
                nq++;
            }
        }
        ys = Arrays.copyOf(yl, ny);
        shuffleSort(ys);
        K = 0;
        for (int i = 0; i < ny; i++) if (K == 0 || ys[K - 1] != ys[i]) ys[K++] = ys[i];
        bit = new long[K + 1];
        ans = new long[nq];
        keys = new long[ne];
        cdq(0, ne);
        StringBuilder sb = new StringBuilder();
        for (long v : ans) sb.append(v).append('\n');
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.print(sb);
        out.flush();
    }

    static void shuffleSort(int[] a) {
        Random r = new Random(System.nanoTime());
        for (int i = a.length - 1; i > 0; i--) { int j = r.nextInt(i + 1); int t = a[i]; a[i] = a[j]; a[j] = t; }
        Arrays.sort(a);
    }

    static void shuffle(long[] a) {
        Random r = new Random(System.nanoTime());
        for (int i = a.length - 1; i > 0; i--) { int j = r.nextInt(i + 1); long t = a[i]; a[i] = a[j]; a[j] = t; }
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
        long nextLong() throws IOException {
            long ret = 0;
            int b = read();
            while (b <= ' ') b = read();
            boolean neg = b == '-';
            if (neg) b = read();
            while (b >= '0' && b <= '9') { ret = ret * 10 + (b - '0'); b = read(); }
            return neg ? -ret : ret;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
6
2 1 1 5 5
1 2 3 5
1 4 4 -2
2 1 1 5 5
2 3 1 5 3
1 4 1 7
out:
0
3
0
-->
<!-- test
in:
5
1 1 1 10
1 1 1 5
2 1 1 1 1
2 2 2 3 3
2 1 1 1000000000 1000000000
out:
15
0
15
-->

All four examples were stress-tested against brute force (BFS per query, direct simulation, sorting each range, $O(q^2)$ rectangle scan) on 300 random small cases each, and the Java and C++ outputs were compared on maximum-size random inputs.

## 6. Tricks, pitfalls and things to remember

1. **CDQ duplicates.** Merge identical points into one weighted point and add $\text{cnt}-1$; otherwise equal points in different halves are counted in one direction only.
2. **CDQ tie order in the sweep.** When $b_{\text{left}} = b_{\text{right}}$ the left point must be inserted before the right point is queried (use `<=` in the `while`). For strict conditions ($<$) flip to `<` and think again about which side ties fall on.
3. **Undo, don't clear.** Reset the Fenwick tree by subtracting what you added. `memset`/`Arrays.fill` per node turns $O(n\log^2 n)$ into $O(n^2)$.
4. **Stable merge.** `std::merge` takes from the first range on ties; a hand-written Java merge must use `<=` for the same reason. An unstable merge silently breaks the "left before right" property for equal keys.
5. **CDQ on time: skip empty work.** If the left half has no updates, return before sorting the right half's queries. Real inputs often alternate in long runs, and this halves the constant.
6. **Parallel binary search: the structure must be rebuilt every round.** Forgetting to reset the Fenwick tree between rounds gives answers that are too small, and only on multi-round inputs — so tiny samples pass.
7. **Parallel binary search overflow.** Per-member totals can exceed $2^{63}$; stop the sum as soon as the need is reached, or cap it.
8. **Bucketing.** Use counting buckets (vector per $t$ or an intrusive linked list `head[t]`/`nxt[i]`). Sorting the queries by mid each round adds a $\log$ and, in Java, boxing.
9. **Overall binary search mutates $k$.** If you need the original $k$ later, copy it first.
10. **Java sorting.** Never `Arrays.sort(int[])` on adversarial data without shuffling (the dual-pivot quicksort has an $O(n^2)$ killer input used in hacks). Packing `(key << 20) | index` into a `long[]` sorts pairs without boxing.
11. **Recursion depth** is only $O(\log n)$ for CDQ and overall binary search, so neither needs an explicit stack, in Java or on Windows.
12. **Online in disguise.** If the statement decodes queries with the previous answer ("$l = (l' \oplus \text{last}) \bmod n$"), offline methods are dead; switch to persistent or online structures.

## 7. Going further (toward 2400–2600+)

- **CDQ for DP.** When `dp[i]` depends on `dp[j]` for $j < i$ with a 2D condition (e.g. 3D LIS: $j<i$, $b_j<b_i$, $c_j<c_i$), run CDQ in the order *left recursion → cross contribution → right recursion* (in-order, not post-order), because the right half needs final left values. The same in-order CDQ also combines with convex hull trick for "online" CHT where slopes are not monotone ([convex hull trick and Li Chao tree](../07-DP-Optimizations/02-convex-hull-trick-and-li-chao-tree.md)).
- **CDQ nesting** gives 4D dominance in $O(n\log^3 n)$; at that point a k-d tree or bitset ([bitset optimisation](05-bitset-optimization.md)) is often simpler.
- **Kruskal reconstruction tree** answers the "first time $u$ and $v$ are connected" queries online in $O(\log n)$ each and replaces parallel binary search for connectivity predicates ([CF 1416D · Graph and Queries](https://codeforces.com/problemset/problem/1416/D) — 2600 combines it with reversed time).
- **Divide and conquer on queries crossing the midpoint:** for range queries $[l, r]$ over a non-invertible operation (linear basis, knapsack, max-plus), split positions at mid, precompute suffix structures of the left half and prefix structures of the right half, and answer every query with $l \le \text{mid} < r$ by merging two precomputed values. [CF 1100F · Ivan and Burgers](https://codeforces.com/problemset/problem/1100/F) — 2500 is the classic.
- **Segment tree on time** ([next file](02-segment-tree-on-time-and-dsu-rollback.md)) handles the case CDQ cannot: contributions that are not decomposable (connectivity) but can be *undone* (DSU with rollback).
- **Overall binary search with updates** ("dynamic $k$-th smallest"): represent a point update as "remove old value, add new value" events in time order; inside the recursion, process events in time order with a Fenwick tree over positions. Same $O((n+q)\log V\log n)$.

## 8. Practice ladder

1600–2000
- [ ] [CF 722C · Destroying Array](https://codeforces.com/problemset/problem/722/C) — 1600 — reverse time, DSU
- [ ] [CF 1213G · Path Queries](https://codeforces.com/problemset/problem/1213/G) — 1800 — sort queries, DSU counting pairs
- [ ] [CSES 1734 · Distinct Values Queries](https://cses.fi/problemset/task/1734) — offline by right endpoint + Fenwick
- [ ] [CF 1311F · Moving Points](https://codeforces.com/problemset/problem/1311/F) — 1900 — 2D offline counting
- [ ] [CF 641E · Little Artem and Time Machine](https://codeforces.com/problemset/problem/641/E) — 2000 — offline per value over time

2100–2400
- [ ] [CF 762E · Radio stations](https://codeforces.com/problemset/problem/762/E) — 2200 — CDQ
- [ ] [CF 1045G · AI robots](https://codeforces.com/problemset/problem/1045/G) — 2200 — CDQ with a window condition
- [ ] [CF 1706E · Qpwoeirut and Vertices](https://codeforces.com/problemset/problem/1706/E) — 2300 — parallel binary search (or Kruskal tree)
- [ ] [CSES 2101 · New Roads Queries](https://cses.fi/problemset/task/2101) — parallel binary search with DSU
- [ ] [AtCoder AGC002 D · Stamp Rally](https://atcoder.jp/contests/agc002/tasks/agc002_d) — the canonical parallel binary search
- [ ] [CF 915F · Imbalance Value of a Tree](https://codeforces.com/problemset/problem/915/F) — 2400 — sort vertices, DSU contribution
- [ ] [CF 12D · Ball](https://codeforces.com/problemset/problem/12/D) — 2400 — 3D dominance (existence)
- [ ] [CF 1000F · One Occurrence](https://codeforces.com/problemset/problem/1000/F) — 2400 — offline by right endpoint
- [ ] [CF 1093E · Intersection of Permutations](https://codeforces.com/problemset/problem/1093/E) — 2400 — CDQ on time

2500+
- [ ] [CF 484E · Sign on Fence](https://codeforces.com/problemset/problem/484/E) — 2500 — parallel binary search over heights
- [ ] [CF 1100F · Ivan and Burgers](https://codeforces.com/problemset/problem/1100/F) — 2500 — D&C on queries crossing mid
- [ ] [CF 1253F · Cheap Robot](https://codeforces.com/problemset/problem/1253/F) — 2500 — transform, then offline DSU
- [ ] [CF 848C · Goodbye Souvenir](https://codeforces.com/problemset/problem/848/C) — 2600 — CDQ on time
- [ ] [CF 1416D · Graph and Queries](https://codeforces.com/problemset/problem/1416/D) — 2600 — reverse time + reconstruction tree

## 9. LeetCode / FAANG cross-reference

- [LC 1697 · Checking Existence of Edge Length Limited Paths](https://leetcode.com/problems/checking-existence-of-edge-length-limited-paths/) — Hard — Example 1 exactly: sort queries and edges, DSU.
- [LC 2503 · Maximum Number of Points From Grid Queries](https://leetcode.com/problems/maximum-number-of-points-from-grid-queries/) — Hard — sort queries, grow the reachable region (DSU or heap).
- [LC 1851 · Minimum Interval to Include Each Query](https://leetcode.com/problems/minimum-interval-to-include-each-query/) — Hard — sort queries, sweep with a heap.
- [LC 2070 · Most Beautiful Item for Each Query](https://leetcode.com/problems/most-beautiful-item-for-each-query/) — Medium — sort queries by price threshold.
- [LC 1707 · Maximum XOR With an Element From Array](https://leetcode.com/problems/maximum-xor-with-an-element-from-array/) — Hard — sort queries by limit, insert into a binary trie.
- [LC 2736 · Maximum Sum Queries](https://leetcode.com/problems/maximum-sum-queries/) — Hard — 2D dominance maximum offline.
- [LC 315 · Count of Smaller Numbers After Self](https://leetcode.com/problems/count-of-smaller-numbers-after-self/) — Hard — 2D CDQ = merge-sort counting.
- [LC 493 · Reverse Pairs](https://leetcode.com/problems/reverse-pairs/) — Hard — cross-half counting inside merge sort.
- [LC 327 · Count of Range Sum](https://leetcode.com/problems/count-of-range-sum/) — Hard — the same cross-half counting on prefix sums.
- [LC 2179 · Count Good Triplets in an Array](https://leetcode.com/problems/count-good-triplets-in-an-array/) — Hard — dominance counting with a Fenwick tree.
- [LC 2382 · Maximum Segment Sum After Removals](https://leetcode.com/problems/maximum-segment-sum-after-removals/) — Hard — reverse time, DSU.

Interviews use the first freedom (sort the queries) often and the merge-sort counting form of CDQ occasionally; parallel binary search and 3D CDQ are rare in interviews because they need too much code for 45 minutes.

## 10. Self-check

1. Why does CDQ only need to count left→right pairs after sorting by $(a,b,c)$ and merging duplicates?
2. What is the recurrence of CDQ and why is the result $O(n\log^2 n)$?
3. In CDQ on time, which events from the left half and which from the right half take part in the cross step?
4. What three properties must a problem have for parallel binary search to apply?
5. How many rounds does parallel binary search need for answers in $\{1..K\} \cup \{\text{never}\}$, and what does one round cost?
6. In overall binary search, why does each element appear in exactly one node per level?
7. Why does offline sorting + DSU fail if the threshold condition is "weight $\ge w$" and you sort ascending — and what is the fix?
8. Name one situation in which none of these techniques works.

<details><summary>Answers</summary>

1. Every right point is lexicographically larger than every left point. If a right point dominated a left point, $a$ would have to be equal, then $b$ equal, and then $c$ would have to be both larger and $\le$ — impossible once identical triples are merged. Left→right pairs already satisfy the $a$-condition, so only $b$ and $c$ remain: a 2D problem.
2. $T(n) = 2T(n/2) + O(n\log n)$; $\log n$ levels, each $O(n\log n)$.
3. Updates from the left half, queries from the right half; every (update, later query) pair is separated at exactly one node.
4. Monotone predicate in $t$; the state after $t$ events is built incrementally; checks are independent.
5. $\lceil\log_2(K+1)\rceil$; one round is one sweep $O(KU)$ plus all checks $O(qC)$.
6. A node's element set is split by value into the two children, so the sets at one depth partition the elements.
7. Edges then disappear as $w$ grows. Sort descending so edges are only added.
8. Forced-online queries (answers decode the next query), or a non-decomposable answer whose structure cannot be undone (then segment tree on time or Mo may still help).

</details>
