# Advanced Segment Trees — Descent, Sparse Trees, Merging, Beats, Sweep Lines

> **Band:** 🟣–🟠 1900–2500 · **Priority:** 🔥 (descent, dynamic tree, sweep) · ⚡ (merging, potential arguments) · 🧊 (beats, wavelet, 2D) · **FAANG:** low · **Prerequisites:** [segment tree basics](02-segment-tree-basics.md), [lazy propagation](03-lazy-propagation.md), [coordinate compression and sweep line](../02-Core-Techniques/05-coordinate-compression-and-sweep-line.md)
> **You can say you know this when:** you can find "the first index where …" in $O(\log n)$ by walking the tree; build a segment tree over $[0, 10^9]$ with nodes created on demand; merge value-indexed trees bottom-up on a rooted tree and prove the total is $O(n\log n)$; compute a union area with a cover-count tree; and explain *why* range-mod and range-chmin run fast even though no lazy tag exists.

## 1. First principles — why this works

### 1.1 Descending (walking) the tree

**Problem.** "Smallest $i$ with $a_1+\dots+a_i \ge k$", "first hotel with at least $r$ free rooms", "first $j \ge l$ with $a_j \ge x$".
The naive approach binary-searches $i$ and asks a range query each time: $O(\log^2 n)$. The waste: every probe of the binary search
re-walks the same root-to-leaf path. Instead, *make the binary search decisions at the tree nodes themselves*.

- **Prefix sum $\ge k$** (non-negative values): at node $v$, if the left child's sum is $\ge k$, the answer is in the left child; otherwise it is in the right child with
  $k \leftarrow k - \text{sum(left)}$. One root-to-leaf path: $O(\log n)$. This is the segment-tree version of the [Fenwick descent](01-fenwick-tree.md).
- **First element $\ge x$ globally** (max tree): go left if $\max(\text{left}) \ge x$, else right.
- **First element $\ge x$ inside $[l, r]$**: recurse left-then-right, pruning nodes disjoint from $[l,r]$ or with $\max < x$.
  Complexity is still $O(\log n)$: the partially covered nodes are $O(\log n)$ as in any query; among fully covered nodes, those with $\max < x$
  are rejected in $O(1)$, and the *first* fully covered node with $\max \ge x$ is guaranteed to contain an answer, so the single descent into it
  succeeds and the search stops. Total: $O(\log n)$ partial nodes + $O(\log n)$ rejected nodes + one $O(\log n)$ descent.

### 1.2 Dynamic (sparse, implicit) segment tree

Coordinates up to $10^9$ and you must answer **online** (no compression possible, e.g. queries depend on earlier answers), or the
coordinate set is too large to list. Observation: a point update touches one root-to-leaf path of $\lceil\log_2 C\rceil + 1$ nodes; a query
only reads nodes that exist (a missing child means "identity"). So **create nodes on demand**: children are pointers (indices into a pool), 0 = null.
Memory: $O(q \log C)$ nodes, more precisely about $q(\log_2 C - \log_2 q) + 2q$ because the top $\log_2 q$ levels are shared.
For $q = 4\cdot10^5$, $C = 10^9$ that is $\approx 6\cdot10^6$ nodes — use flat `int` arrays, not objects. With lazy propagation, a push must
create both children first.

### 1.3 Segment tree merging

**Setting.** Every vertex of a rooted tree owns a set of values (colours, depths, …) stored as a *value-indexed* dynamic segment tree;
we need, for every vertex, a statistic of the union over its subtree. Merge children's trees into the parent's:

```text
merge(a, b):                       # trees over the same value range; returns the merged tree, reusing a's nodes
    if a == null: return b
    if b == null: return a
    if leaf: combine leaf values of a and b into a; return a
    a.left  = merge(a.left,  b.left)
    a.right = merge(a.right, b.right)
    pull(a); return a
```

**Why the total is $O(n \log C)$.** Count the calls in which both `a` and `b` are non-null: each such call permanently discards node `b`
(its information now lives in `a`). Nodes are never created by merging, so the number of such calls is at most the number of nodes ever created,
which is $n(\lceil\log_2 C\rceil+1)$ if each vertex starts with one value. Calls with a null argument are charged to their parent call (at most 2 each).
So **all merges together** cost $O(n \log C)$, regardless of the tree's shape — no small-to-large needed. The price: merging is destructive
(child trees are consumed), so read each vertex's answer *before* merging it into its parent, or process queries offline at the right moment.
Compare [small-to-large / DSU on tree](../10-Trees/03-small-to-large-and-dsu-on-tree.md), which gets $O(n \log^2 n)$ with ordinary maps.

### 1.4 Potential arguments: when there is no lazy tag

**Range mod.** $a_i \leftarrow a_i \bmod x$ on $[l, r]$, query sums. The new sum is not a function of the old summary, so no tag exists.
Observation: if $a \ge x$ then $a \bmod x < a/2$ (if $x \le a/2$, $a \bmod x < x \le a/2$; if $x > a/2$, $a \bmod x = a - x < a/2$).
And if $a < x$ nothing changes. So recurse into a node only if its **max $\ge x$** — any leaf reached at least halves. Potential: $\Phi = \sum_i \log_2(a_i + 1)$.
Each leaf visit that changes a value decreases $\Phi$ by $\ge 1$, and a point assignment increases it by at most $\log_2 V$. Every recursion path ends
at a changed leaf or is pruned at a partial-overlap node, so the total time is $O((n + q)\log n \log V)$. The same argument works for
"$a_i \leftarrow \lfloor\sqrt{a_i}\rfloor$" (values reach 1 after $O(\log\log V)$ steps) and "$a_i \leftarrow \varphi(a_i)$".

**Range chmin ("segment tree beats", 🧊).** $a_i \leftarrow \min(a_i, x)$ on $[l, r]$, query sum and max. Store per node: maximum $m_1$, strict
second maximum $m_2$, count of maxima $c$, sum $s$. At a fully covered node:

- if $m_1 \le x$: nothing changes — stop;
- if $m_2 < x < m_1$: only the $c$ maximal elements change, all to $x$: $s \mathrel{-}= (m_1 - x)\,c$, $m_1 = x$ — this *is* a tag ("chmin with $m_1$", pushed to children whose max exceeds the parent's);
- if $x \le m_2$: recurse ("break" the node).

*Why the breaks are cheap* (a simplified version of Ji Ruyi's argument): let $\Phi$ = sum over all nodes of the number of distinct values in the node's segment.
Initially $\Phi \le n(\lceil\log_2 n\rceil + 1)$. A break happens at a node where $x \le m_2$, so after the update $m_1$ and $m_2$ both become $x$: that node's distinct count
drops by at least 1, which pays for visiting it. An update can *increase* distinct counts only on the $O(\log n)$ partially covered nodes, by at most 1 each.
Total: $O((n + q)\log n)$ amortised. (With range *add* mixed in, the known bound is $O(n \log^2 n)$.)

### 1.5 Sweep line with a cover-count tree (union of rectangles)

Area of the union of $n$ axis-parallel rectangles. Sweep a vertical line over $x$; between two consecutive event coordinates, the union's
cross-section is a fixed set of $y$-intervals, and the area of that slab is (covered length) × (width). Events: at $x_1$ add $[y_1, y_2)$, at $x_2$ remove it.
Compress the $y$ coordinates into elementary intervals $[Y_i, Y_{i+1})$. The tree stores per node

- `cnt` — how many active rectangles cover this node's *whole* range **as a canonical piece**,
- `len` — covered length inside this node's range: `cnt > 0 ? full length : (leaf ? 0 : len(left) + len(right))`.

**No push-down is needed** — this is the subtle point. Every removal is the exact inverse of an earlier insertion with the same interval, hence
it touches exactly the same canonical nodes. `cnt` is therefore never negative and never needs to be passed to children; `len` only needs to be
correct at the root, and the formula above makes it correct at every node given its subtree. Time $O(n \log n)$.

### 1.6 Other trees to know exist (🧊)

- **Merge-sort tree**: each node stores its segment sorted. "Count elements $\le x$ in $[l,r]$" = binary search in $O(\log n)$ nodes: $O(\log^2 n)$, memory $O(n\log n)$. Static only; fractional cascading removes one log.
- **Wavelet tree**: recursively split by *value* (lower half / upper half), storing at each level a prefix count of "went left". k-th smallest in $[l, r]$ and rank queries in $O(\log V)$, $O(n\log V)$ bits of memory. A static alternative to the [persistent segment tree](08-persistent-data-structures.md).
- **2D segment tree / segment tree of BITs**: a segment tree over $x$ whose nodes are segment trees (or BITs) over $y$; $O(\log^2)$ per operation and $O(n \log^2 n)$ memory if dynamic. Usually an offline sweep + 1D tree or [CDQ](../16-IGM-Frontier/01-offline-techniques-cdq-parallel-binary-search.md) is simpler.

## 2. Formulas, definitions and identities

| Technique | Cost | Key fact |
|---|---|---|
| prefix-sum descent | $O(\log n)$ | go left iff `sum(left) >= k`, else `k -= sum(left)` |
| first $\ge x$ in $[l, r]$ | $O(\log n)$ | only one descent into a fully covered node succeeds-or-prunes |
| dynamic tree, $q$ updates on $[0, C)$ | $O(\log C)$ per op, $\approx q(\log_2 C - \log_2 q + 2)$ nodes | create nodes on the update path only |
| merging $n$ singleton trees | $O(n \log C)$ total | each two-non-null call deletes a node |
| range mod with potential | $O((n+q)\log n\log V)$ | $a \ge x \Rightarrow a \bmod x < a/2$ |
| range chmin + sum (beats) | $O((n+q)\log n)$ amortised | breaks decrease "distinct values per node" |
| rectangle union area | $O(n\log n)$ | cover count without push-down; $\text{area} = \sum \text{len}(root)\cdot\Delta x$ |
| merge-sort tree count | $O(\log^2 n)$ query, $O(n\log n)$ memory | sorted lists per node |
| wavelet tree k-th | $O(\log V)$ | per-level prefix counts |

Beats update at a fully covered node, with $(m_1, m_2, c, s)$: if $m_2 < x < m_1$ then $s' = s - (m_1 - x)c$, $m_1' = x$.
Union-area node: $\text{len}(v) = \begin{cases} Y_{r+1} - Y_l & \text{cnt}(v) > 0\\ 0 & \text{leaf}\\ \text{len}(2v) + \text{len}(2v+1) & \text{otherwise}\end{cases}$

## 3. Implementation (C++ and Java)

### 3.1 Both descents on a sum+max tree

Original task. Non-negative array; `1 p v` sets $a_p = v$; `2 k` prints the smallest $i$ with $a_1+\dots+a_i \ge k$ (or $-1$);
`3 l r x` prints the first $i\in[l,r]$ with $a_i \ge x$ (or $-1$). 1-indexed input.

```cpp
#include <bits/stdc++.h>
using namespace std;

int n;
vector<long long> sm, mx;
void pull(int v) { sm[v] = sm[2 * v] + sm[2 * v + 1]; mx[v] = max(mx[2 * v], mx[2 * v + 1]); }
void build(int v, int l, int r, const vector<long long>& a) {
    if (l == r) { sm[v] = mx[v] = a[l]; return; }
    int m = (l + r) >> 1;
    build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a); pull(v);
}
void setVal(int v, int l, int r, int p, long long x) {
    if (l == r) { sm[v] = mx[v] = x; return; }
    int m = (l + r) >> 1;
    if (p <= m) setVal(2 * v, l, m, p, x); else setVal(2 * v + 1, m + 1, r, p, x);
    pull(v);
}
int prefixAtLeast(long long k) {                                  // smallest index with prefix sum >= k
    if (sm[1] < k) return -1;
    int v = 1, l = 0, r = n - 1;
    while (l < r) {
        int m = (l + r) >> 1;
        if (sm[2 * v] >= k) { v = 2 * v; r = m; }
        else { k -= sm[2 * v]; v = 2 * v + 1; l = m + 1; }
    }
    return l;
}
int firstAtLeast(int v, int l, int r, int ql, int qr, long long x) {  // first index in [ql, qr] with a >= x
    if (qr < l || r < ql || mx[v] < x) return -1;
    if (l == r) return l;
    int m = (l + r) >> 1;
    int res = firstAtLeast(2 * v, l, m, ql, qr, x);
    return res != -1 ? res : firstAtLeast(2 * v + 1, m + 1, r, ql, qr, x);
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int q; cin >> n >> q;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    sm.assign(4 * n, 0); mx.assign(4 * n, 0);
    build(1, 0, n - 1, a);
    while (q--) {
        int type; cin >> type;
        if (type == 1) { int p; long long v; cin >> p >> v; setVal(1, 0, n - 1, p - 1, v); }
        else if (type == 2) { long long k; cin >> k; int i = prefixAtLeast(k); cout << (i < 0 ? -1 : i + 1) << '\n'; }
        else { int l, r; long long x; cin >> l >> r >> x; int i = firstAtLeast(1, 0, n - 1, l - 1, r - 1, x); cout << (i < 0 ? -1 : i + 1) << '\n'; }
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n; static long[] sm, mx;
    static void pull(int v) { sm[v] = sm[2 * v] + sm[2 * v + 1]; mx[v] = Math.max(mx[2 * v], mx[2 * v + 1]); }
    static void build(int v, int l, int r, long[] a) {
        if (l == r) { sm[v] = mx[v] = a[l]; return; }
        int m = (l + r) >> 1;
        build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a); pull(v);
    }
    static void setVal(int v, int l, int r, int p, long x) {
        if (l == r) { sm[v] = mx[v] = x; return; }
        int m = (l + r) >> 1;
        if (p <= m) setVal(2 * v, l, m, p, x); else setVal(2 * v + 1, m + 1, r, p, x);
        pull(v);
    }
    static int prefixAtLeast(long k) {
        if (sm[1] < k) return -1;
        int v = 1, l = 0, r = n - 1;
        while (l < r) {
            int m = (l + r) >> 1;
            if (sm[2 * v] >= k) { v = 2 * v; r = m; }
            else { k -= sm[2 * v]; v = 2 * v + 1; l = m + 1; }
        }
        return l;
    }
    static int firstAtLeast(int v, int l, int r, int ql, int qr, long x) {
        if (qr < l || r < ql || mx[v] < x) return -1;
        if (l == r) return l;
        int m = (l + r) >> 1;
        int res = firstAtLeast(2 * v, l, m, ql, qr, x);
        return res != -1 ? res : firstAtLeast(2 * v + 1, m + 1, r, ql, qr, x);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        n = in.nextInt(); int q = in.nextInt();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        sm = new long[4 * n]; mx = new long[4 * n];
        build(1, 0, n - 1, a);
        while (q-- > 0) {
            int type = in.nextInt();
            if (type == 1) { int p = in.nextInt(); setVal(1, 0, n - 1, p - 1, in.nextLong()); }
            else if (type == 2) { int i = prefixAtLeast(in.nextLong()); out.println(i < 0 ? -1 : i + 1); }
            else {
                int l = in.nextInt(), r = in.nextInt(); long x = in.nextLong();
                int i = firstAtLeast(1, 0, n - 1, l - 1, r - 1, x); out.println(i < 0 ? -1 : i + 1);
            }
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
6 7
3 0 4 1 5 2
2 3
2 4
2 16
3 2 6 4
3 4 4 2
1 2 9
2 4
out:
1
3
-1
3
-1
2
-->
<!-- test
in:
1 3
0
2 1
3 1 1 0
1 1 7
out:
-1
1
-->

### 3.2 Dynamic segment tree over a large range (point add, range sum)

Nodes live in flat arrays; node 0 is the null node (count 0, children 0), node 1 is the root.

```cpp
struct DynSeg {
    long long lo, hi;                                 // value range [lo, hi]
    vector<int> L, R; vector<long long> cnt;          // node 0 = null
    DynSeg(long long lo, long long hi) : lo(lo), hi(hi), L(2, 0), R(2, 0), cnt(2, 0) {}
    int newNode() { L.push_back(0); R.push_back(0); cnt.push_back(0); return int(L.size()) - 1; }
    void add(long long pos, long long d) {
        int v = 1; long long l = lo, r = hi;
        while (true) {
            cnt[v] += d;
            if (l == r) return;
            long long m = l + ((r - l) >> 1);         // floor midpoint, safe for negative ranges
            if (pos <= m) { if (!L[v]) { int c = newNode(); L[v] = c; } v = L[v]; r = m; }
            else          { if (!R[v]) { int c = newNode(); R[v] = c; } v = R[v]; l = m + 1; }
        }
    }
    long long query(int v, long long l, long long r, long long ql, long long qr) const {
        if (!v || qr < l || r < ql) return 0;
        if (ql <= l && r <= qr) return cnt[v];
        long long m = l + ((r - l) >> 1);
        return query(L[v], l, m, ql, qr) + query(R[v], m + 1, r, ql, qr);
    }
    long long query(long long ql, long long qr) const { return query(1, lo, hi, ql, qr); }
};
```

```java
static class DynSeg {
    final long lo, hi; int[] L, R; long[] cnt; int size = 2;   // node 0 = null, node 1 = root
    DynSeg(long lo, long hi, int cap) { this.lo = lo; this.hi = hi; cap = Math.max(cap, 2); L = new int[cap]; R = new int[cap]; cnt = new long[cap]; }
    int newNode() {
        if (size == L.length) { int c = 2 * size; L = Arrays.copyOf(L, c); R = Arrays.copyOf(R, c); cnt = Arrays.copyOf(cnt, c); }
        return size++;
    }
    void add(long pos, long d) {
        int v = 1; long l = lo, r = hi;
        while (true) {
            cnt[v] += d;
            if (l == r) return;
            long m = l + ((r - l) >> 1);
            if (pos <= m) { if (L[v] == 0) { int c = newNode(); L[v] = c; } v = L[v]; r = m; }
            else          { if (R[v] == 0) { int c = newNode(); R[v] = c; } v = R[v]; l = m + 1; }
        }
    }
    long query(int v, long l, long r, long ql, long qr) {
        if (v == 0 || qr < l || r < ql) return 0;
        if (ql <= l && r <= qr) return cnt[v];
        long m = l + ((r - l) >> 1);
        return query(L[v], l, m, ql, qr) + query(R[v], m + 1, r, ql, qr);
    }
    long query(long ql, long qr) { return query(1, lo, hi, ql, qr); }
}
```

The `int c = newNode(); L[v] = c;` split matters: in Java `L[v] = newNode()` evaluates the array reference `L` *before* the call, so if
`newNode()` reallocates `L`, the write goes to the old array. (C++17 sequences the right side first, but the habit is cheap insurance.)

### 3.3 Segment tree merging (destructive, value-indexed)

```cpp
struct MergeSeg {
    vector<int> L, R, cnt;                             // cnt = number of present values in the node's range
    explicit MergeSeg(int cap) { L.reserve(cap); R.reserve(cap); cnt.reserve(cap); L.push_back(0); R.push_back(0); cnt.push_back(0); }
    int node() { L.push_back(0); R.push_back(0); cnt.push_back(0); return int(L.size()) - 1; }
    int single(int l, int r, int pos) {                // tree containing only value pos
        int root = node(), v = root;
        while (true) {
            cnt[v] = 1;
            if (l == r) return root;
            int m = (l + r) >> 1, c = node();
            if (pos <= m) { L[v] = c; r = m; } else { R[v] = c; l = m + 1; }
            v = c;
        }
    }
    int merge(int a, int b, int l, int r) {            // consumes b
        if (!a || !b) return a | b;
        if (l == r) { cnt[a] = 1; return a; }          // "present" is an OR at the leaves
        int m = (l + r) >> 1;
        int la = merge(L[a], L[b], l, m), ra = merge(R[a], R[b], m + 1, r);
        L[a] = la; R[a] = ra; cnt[a] = cnt[la] + cnt[ra];
        return a;
    }
};
```

```java
static class MergeSeg {
    final int[] L, R, cnt; int size = 1;               // node 0 = null
    MergeSeg(int cap) { L = new int[cap]; R = new int[cap]; cnt = new int[cap]; }
    int single(int l, int r, int pos) {
        int root = size++, v = root;
        while (true) {
            cnt[v] = 1;
            if (l == r) return root;
            int m = (l + r) >> 1, c = size++;
            if (pos <= m) { L[v] = c; r = m; } else { R[v] = c; l = m + 1; }
            v = c;
        }
    }
    int merge(int a, int b, int l, int r) {
        if (a == 0 || b == 0) return a | b;
        if (l == r) { cnt[a] = 1; return a; }
        int m = (l + r) >> 1;
        int la = merge(L[a], L[b], l, m), ra = merge(R[a], R[b], m + 1, r);
        L[a] = la; R[a] = ra; cnt[a] = cnt[la] + cnt[ra];
        return a;
    }
}
```

## 4. Recognising the pattern

- **"Find the first/leftmost position such that …"** with updates (first hotel with capacity, $k$-th zero, first index where prefix exceeds) → descent, never binary search + query.
- **Values or positions up to $10^9$, online / forced-online queries** → dynamic tree. Offline → compress instead (smaller, faster).
- **"For every vertex, something about the multiset of values in its subtree"** (distinct count, mode, $k$-th) → segment-tree merging, or [small-to-large](../10-Trees/03-small-to-large-and-dsu-on-tree.md).
- **An update that has no tag but "shrinks" values** (mod, sqrt, divide, chmin, gcd with a value) → potential argument: recurse while the update can still change something; prune with max (or "all equal" flags).
- **Area/perimeter of union of rectangles, "max points covered by a window"** → sweep + cover-count tree (or add/max lazy tree for the window variant).
- **Static "k-th smallest in a range" / "count $\le x$ in a range"** → persistent tree, wavelet tree or merge-sort tree; with updates → BIT of dynamic trees or offline tricks.

## 5. Worked examples (graded)

### Example 1 — Hotel Queries (global descent)  ·  ★ ≈1500

- **Source:** [CSES 1143 · Hotel Queries](https://cses.fi/problemset/task/1143)
- **Difficulty:** ≈1500 (est.)
- **Problem:** $n, m \le 2\cdot10^5$ hotels with $h_i$ free rooms, in order. Each of $m$ groups needs $r_j$ rooms in a single hotel and takes the *first* hotel that has enough; print its index (or 0 if none) and reduce its rooms.
- **Thinking from first principles:** "first index with $h_i \ge r$" — linear scan is $O(nm)$. A max tree tells us in $O(1)$ whether a whole block contains a large enough hotel, and therefore which half to enter. After the descent, the leaf is known: update it and recompute ancestors.

<details><summary>Solution</summary>

Max tree in the recursive layout; descent and update share the path (parent of `v` is `v / 2`), so both are loops. $O((n + m)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    vector<int> h(n);
    for (auto& x : h) cin >> x;
    vector<int> mx(4 * n, 0);
    auto build = [&](auto&& self, int v, int l, int r) -> void {
        if (l == r) { mx[v] = h[l]; return; }
        int mid = (l + r) >> 1;
        self(self, 2 * v, l, mid); self(self, 2 * v + 1, mid + 1, r);
        mx[v] = max(mx[2 * v], mx[2 * v + 1]);
    };
    build(build, 1, 0, n - 1);
    for (int j = 0; j < m; j++) {
        int need; cin >> need;
        if (mx[1] < need) { cout << 0 << (j + 1 < m ? ' ' : '\n'); continue; }
        int v = 1, l = 0, r = n - 1;
        while (l < r) {
            int mid = (l + r) >> 1;
            if (mx[2 * v] >= need) { v = 2 * v; r = mid; } else { v = 2 * v + 1; l = mid + 1; }
        }
        cout << l + 1 << (j + 1 < m ? ' ' : '\n');
        mx[v] -= need;
        for (v >>= 1; v > 0; v >>= 1) mx[v] = max(mx[2 * v], mx[2 * v + 1]);
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] mx, h;
    static void build(int v, int l, int r) {
        if (l == r) { mx[v] = h[l]; return; }
        int mid = (l + r) >> 1;
        build(2 * v, l, mid); build(2 * v + 1, mid + 1, r);
        mx[v] = Math.max(mx[2 * v], mx[2 * v + 1]);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt();
        h = new int[n];
        for (int i = 0; i < n; i++) h[i] = in.nextInt();
        mx = new int[4 * n];
        build(1, 0, n - 1);
        StringBuilder sb = new StringBuilder();
        for (int j = 0; j < m; j++) {
            int need = in.nextInt();
            if (mx[1] < need) { sb.append(0).append(j + 1 < m ? ' ' : '\n'); continue; }
            int v = 1, l = 0, r = n - 1;
            while (l < r) {
                int mid = (l + r) >> 1;
                if (mx[2 * v] >= need) { v = 2 * v; r = mid; } else { v = 2 * v + 1; l = mid + 1; }
            }
            sb.append(l + 1).append(j + 1 < m ? ' ' : '\n');
            mx[v] -= need;
            for (v >>= 1; v > 0; v >>= 1) mx[v] = Math.max(mx[2 * v], mx[2 * v + 1]);
        }
        System.out.print(sb);
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
8 5
3 2 4 1 5 5 2 6
4 4 7 1 1
out:
3 5 0 1 1
-->
<!-- test
in:
1 3
5
5 1 1
out:
1 0 0
-->

</details>

### Example 2 — Salary Queries (dynamic tree over $[1, 10^9]$)  ·  ★ ≈1800

- **Source:** [CSES 1144 · Salary Queries](https://cses.fi/problemset/task/1144)
- **Difficulty:** ≈1800 (est.)
- **Problem:** $n, q \le 2\cdot10^5$ salaries up to $10^9$. `! k x`: employee $k$'s salary becomes $x$; `? a b`: how many salaries lie in $[a, b]$.
- **Thinking from first principles:** keep a count per salary *value* and answer a range sum over values. Values go up to $10^9$, so an array is impossible.
  Two routes: (a) read everything, compress all salaries that ever appear plus nothing else (query endpoints are handled with `lower_bound`/`upper_bound`), BIT — the best offline solution;
  (b) a dynamic segment tree over $[1, 10^9]$ — no preprocessing, works online. We take (b) to practise it: $\le 4\cdot10^5$ point updates create about $6\cdot10^6$ nodes.

<details><summary>Solution</summary>

`add(old, -1)`, `add(new, +1)` per change; `query(a, b)` per question. $O((n+q)\log C)$, $C = 10^9$.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct DynSeg {
    long long lo, hi;
    vector<int> L, R; vector<long long> cnt;
    DynSeg(long long lo, long long hi) : lo(lo), hi(hi), L(2, 0), R(2, 0), cnt(2, 0) {}
    int newNode() { L.push_back(0); R.push_back(0); cnt.push_back(0); return int(L.size()) - 1; }
    void add(long long pos, long long d) {
        int v = 1; long long l = lo, r = hi;
        while (true) {
            cnt[v] += d;
            if (l == r) return;
            long long m = l + ((r - l) >> 1);
            if (pos <= m) { if (!L[v]) { int c = newNode(); L[v] = c; } v = L[v]; r = m; }
            else          { if (!R[v]) { int c = newNode(); R[v] = c; } v = R[v]; l = m + 1; }
        }
    }
    long long query(int v, long long l, long long r, long long ql, long long qr) const {
        if (!v || qr < l || r < ql) return 0;
        if (ql <= l && r <= qr) return cnt[v];
        long long m = l + ((r - l) >> 1);
        return query(L[v], l, m, ql, qr) + query(R[v], m + 1, r, ql, qr);
    }
    long long query(long long ql, long long qr) const { return query(1, lo, hi, ql, qr); }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    DynSeg seg(1, 1000000000);
    seg.L.reserve(1 << 23); seg.R.reserve(1 << 23); seg.cnt.reserve(1 << 23);
    vector<long long> p(n + 1);
    for (int i = 1; i <= n; i++) { cin >> p[i]; seg.add(p[i], 1); }
    while (q--) {
        char c; long long a, b; cin >> c >> a >> b;
        if (c == '!') { seg.add(p[a], -1); p[a] = b; seg.add(b, 1); }
        else cout << seg.query(a, b) << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static class DynSeg {
        final long lo, hi; int[] L, R; long[] cnt; int size = 2;
        DynSeg(long lo, long hi, int cap) { this.lo = lo; this.hi = hi; cap = Math.max(cap, 2); L = new int[cap]; R = new int[cap]; cnt = new long[cap]; }
        int newNode() {
            if (size == L.length) { int c = 2 * size; L = Arrays.copyOf(L, c); R = Arrays.copyOf(R, c); cnt = Arrays.copyOf(cnt, c); }
            return size++;
        }
        void add(long pos, long d) {
            int v = 1; long l = lo, r = hi;
            while (true) {
                cnt[v] += d;
                if (l == r) return;
                long m = l + ((r - l) >> 1);
                if (pos <= m) { if (L[v] == 0) { int c = newNode(); L[v] = c; } v = L[v]; r = m; }
                else          { if (R[v] == 0) { int c = newNode(); R[v] = c; } v = R[v]; l = m + 1; }
            }
        }
        long query(int v, long l, long r, long ql, long qr) {
            if (v == 0 || qr < l || r < ql) return 0;
            if (ql <= l && r <= qr) return cnt[v];
            long m = l + ((r - l) >> 1);
            return query(L[v], l, m, ql, qr) + query(R[v], m + 1, r, ql, qr);
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), q = in.nextInt();
        DynSeg seg = new DynSeg(1, 1_000_000_000L, 1 << 20);
        long[] p = new long[n + 1];
        for (int i = 1; i <= n; i++) { p[i] = in.nextInt(); seg.add(p[i], 1); }
        while (q-- > 0) {
            char c = in.nextChar(); int a = in.nextInt(), b = in.nextInt();
            if (c == '!') { seg.add(p[a], -1); p[a] = b; seg.add(b, 1); }
            else out.println(seg.query(1, seg.lo, seg.hi, a, b));
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
        char nextChar() throws IOException { int c = read(); while (c != -1 && c <= ' ') c = read(); return (char) c; }
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
3 7 2 2 5
? 2 3
! 3 6
? 2 3
out:
3
2
-->
<!-- test
in:
2 4
1000000000 1
? 1 1000000000
! 2 1000000000
? 1000000000 1000000000
? 1 999999999
out:
2
2
0
-->

</details>

### Example 3 — Distinct Colors (segment tree merging)  ·  ★ ≈1900

- **Source:** [CSES 1139 · Distinct Colors](https://cses.fi/problemset/task/1139)
- **Difficulty:** ≈1900 (est.)
- **Problem:** a tree of $n \le 2\cdot10^5$ vertices rooted at 1, vertex $i$ has colour $c_i \le 10^9$. For every vertex print the number of distinct colours in its subtree.
- **Thinking from first principles:** the answer for $v$ is the size of the *union* of its children's colour sets plus $c_v$. Unions of sets → each vertex owns
  a presence tree over compressed colours (one root-to-leaf path initially) and merges its children's trees into its own. The answer is the root's count.
  Total work $O(n \log n)$ by the node-deletion argument of §1.3. Recursion over the *tree* would be $2\cdot10^5$ deep (a path), so order vertices iteratively;
  recursion inside `merge` is only $\log n$ deep. Alternatives: small-to-large with sets ($O(n\log^2 n)$), or Euler tour + offline distinct-values (as in the Fenwick file).

<details><summary>Solution</summary>

Compress colours to $[0, K)$. Preorder by an explicit stack; process vertices in reverse preorder so children are finished before parents:
record `ans[v] = cnt[root[v]]`, then `root[parent] = merge(root[parent], root[v])`. Node pool: $n(\lceil\log_2 K\rceil + 1) + 1$.

```cpp
#include <bits/stdc++.h>
using namespace std;

vector<int> Lc, Rc, cnt;
int newNode() { Lc.push_back(0); Rc.push_back(0); cnt.push_back(0); return int(Lc.size()) - 1; }
int single(int l, int r, int pos) {
    int root = newNode(), v = root;
    while (true) {
        cnt[v] = 1;
        if (l == r) return root;
        int m = (l + r) >> 1, c = newNode();
        if (pos <= m) { Lc[v] = c; r = m; } else { Rc[v] = c; l = m + 1; }
        v = c;
    }
}
int merge(int a, int b, int l, int r) {
    if (!a || !b) return a | b;
    if (l == r) { cnt[a] = 1; return a; }
    int m = (l + r) >> 1;
    int la = merge(Lc[a], Lc[b], l, m), ra = merge(Rc[a], Rc[b], m + 1, r);
    Lc[a] = la; Rc[a] = ra; cnt[a] = cnt[la] + cnt[ra];
    return a;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<int> c(n + 1);
    for (int i = 1; i <= n; i++) cin >> c[i];
    vector<int> vals(c.begin() + 1, c.end());
    sort(vals.begin(), vals.end()); vals.erase(unique(vals.begin(), vals.end()), vals.end());
    int K = vals.size();
    vector<vector<int>> g(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; g[a].push_back(b); g[b].push_back(a); }
    Lc.reserve(n * 20 + 2); Rc.reserve(n * 20 + 2); cnt.reserve(n * 20 + 2);
    newNode();                                                   // node 0 = null
    vector<int> root(n + 1), par(n + 1, 0), order; order.reserve(n);
    vector<int> st = {1}; par[1] = -1;
    while (!st.empty()) {
        int v = st.back(); st.pop_back(); order.push_back(v);
        for (int u : g[v]) if (u != par[v]) { par[u] = v; st.push_back(u); }
    }
    for (int v = 1; v <= n; v++) root[v] = single(0, K - 1, int(lower_bound(vals.begin(), vals.end(), c[v]) - vals.begin()));
    vector<int> ans(n + 1);
    for (int i = n - 1; i >= 0; i--) {
        int v = order[i];
        ans[v] = cnt[root[v]];
        if (par[v] > 0) root[par[v]] = merge(root[par[v]], root[v], 0, K - 1);
    }
    for (int v = 1; v <= n; v++) cout << ans[v] << (v < n ? ' ' : '\n');
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] Lc, Rc, cnt; static int size = 1;               // node 0 = null
    static int single(int l, int r, int pos) {
        int root = size++, v = root;
        while (true) {
            cnt[v] = 1;
            if (l == r) return root;
            int m = (l + r) >> 1, c = size++;
            if (pos <= m) { Lc[v] = c; r = m; } else { Rc[v] = c; l = m + 1; }
            v = c;
        }
    }
    static int merge(int a, int b, int l, int r) {
        if (a == 0 || b == 0) return a | b;
        if (l == r) { cnt[a] = 1; return a; }
        int m = (l + r) >> 1;
        int la = merge(Lc[a], Lc[b], l, m), ra = merge(Rc[a], Rc[b], m + 1, r);
        Lc[a] = la; Rc[a] = ra; cnt[a] = cnt[la] + cnt[ra];
        return a;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] c = new int[n + 1];
        for (int i = 1; i <= n; i++) c[i] = in.nextInt();
        int[] vals = Arrays.copyOfRange(c, 1, n + 1);
        Random rnd = new Random(1);
        for (int i = n - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); int t = vals[i]; vals[i] = vals[j]; vals[j] = t; }
        Arrays.sort(vals);
        int K = 0;
        for (int i = 0; i < n; i++) if (i == 0 || vals[i] != vals[i - 1]) vals[K++] = vals[i];
        int[] head = new int[n + 1], nxt = new int[2 * (n - 1)], to = new int[2 * (n - 1)];
        Arrays.fill(head, -1);
        for (int i = 0; i < n - 1; i++) {
            int a = in.nextInt(), b = in.nextInt();
            to[2 * i] = b; nxt[2 * i] = head[a]; head[a] = 2 * i;
            to[2 * i + 1] = a; nxt[2 * i + 1] = head[b]; head[b] = 2 * i + 1;
        }
        int depth = 1; while ((1 << (depth - 1)) < K) depth++;
        Lc = new int[n * (depth + 1) + 2]; Rc = new int[Lc.length]; cnt = new int[Lc.length];
        int[] root = new int[n + 1], par = new int[n + 1], order = new int[n], st = new int[n];
        int sp = 0, cntOrd = 0; st[sp++] = 1; par[1] = -1;
        while (sp > 0) {
            int v = st[--sp]; order[cntOrd++] = v;
            for (int e = head[v]; e != -1; e = nxt[e]) if (to[e] != par[v]) { par[to[e]] = v; st[sp++] = to[e]; }
        }
        for (int v = 1; v <= n; v++) root[v] = single(0, K - 1, Arrays.binarySearch(vals, 0, K, c[v]));
        int[] ans = new int[n + 1];
        for (int i = n - 1; i >= 0; i--) {
            int v = order[i];
            ans[v] = cnt[root[v]];
            if (par[v] > 0) root[par[v]] = merge(root[par[v]], root[v], 0, K - 1);
        }
        StringBuilder sb = new StringBuilder();
        for (int v = 1; v <= n; v++) sb.append(ans[v]).append(v < n ? ' ' : '\n');
        System.out.print(sb);
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
2 3 2 2 1
1 2
1 3
3 4
3 5
out:
3 1 2 1 1
-->
<!-- test
in:
1
1000000000
out:
1
-->
<!-- test
in:
4
7 7 7 7
1 2
2 3
3 4
out:
1 1 1 1
-->

</details>

### Example 4 — Area of a union of rectangles (cover-count sweep)  ·  ★ ≈2100

- **Source:** Original problem (the classic behind [LC 850 · Rectangle Area II](https://leetcode.com/problems/rectangle-area-ii/) — Hard).
- **Difficulty:** ≈2100 (est.)
- **Problem:** $n \le 10^5$ axis-parallel rectangles with integer corners $0 \le x_1 < x_2 \le 10^9$, $0 \le y_1 < y_2 \le 10^9$. Print the area of their union.
- **Thinking from first principles:** inclusion–exclusion is exponential; a grid of compressed cells is $O(n^2)$ cells. Sweep $x$: between consecutive event $x$'s the
  union's vertical cross-section is constant, so area = $\sum (\text{covered } y\text{-length}) \times \Delta x$. We need a structure supporting "add/remove interval" and "total covered length".
  A lazy assign does not fit (overlaps!). The cover count with the no-push invariant (§1.5) does. Area $\le 10^{18}$ fits in signed 64-bit.

<details><summary>Solution</summary>

Compress $y$ into $m$ distinct values; leaf $i$ is $[Y_i, Y_{i+1})$, $m - 1$ leaves. Sort events by $x$; before applying events at $x$, add `len[1] * (x - prevX)`. $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

vector<long long> Y, len;
vector<int> cnt;
void upd(int v, int l, int r, int ql, int qr, int d) {          // leaves l..r, leaf i = [Y[i], Y[i+1])
    if (qr < l || r < ql) return;
    if (ql <= l && r <= qr) cnt[v] += d;
    else { int m = (l + r) >> 1; upd(2 * v, l, m, ql, qr, d); upd(2 * v + 1, m + 1, r, ql, qr, d); }
    if (cnt[v] > 0) len[v] = Y[r + 1] - Y[l];
    else if (l == r) len[v] = 0;
    else len[v] = len[2 * v] + len[2 * v + 1];
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<array<long long, 4>> ev;                              // x, d, y1, y2
    for (int i = 0; i < n; i++) {
        long long x1, y1, x2, y2; cin >> x1 >> y1 >> x2 >> y2;
        ev.push_back({x1, 1, y1, y2}); ev.push_back({x2, -1, y1, y2});
        Y.push_back(y1); Y.push_back(y2);
    }
    sort(Y.begin(), Y.end()); Y.erase(unique(Y.begin(), Y.end()), Y.end());
    int m = Y.size() - 1;                                        // number of elementary intervals (>= 1)
    cnt.assign(4 * m, 0); len.assign(4 * m, 0);
    sort(ev.begin(), ev.end());
    long long area = 0, prevX = ev[0][0];
    for (auto& e : ev) {
        area += len[1] * (e[0] - prevX);
        prevX = e[0];
        int a = int(lower_bound(Y.begin(), Y.end(), e[2]) - Y.begin());
        int b = int(lower_bound(Y.begin(), Y.end(), e[3]) - Y.begin()) - 1;
        upd(1, 0, m - 1, a, b, int(e[1]));
    }
    cout << area << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long[] Y, len; static int[] cnt;
    static void upd(int v, int l, int r, int ql, int qr, int d) {
        if (qr < l || r < ql) return;
        if (ql <= l && r <= qr) cnt[v] += d;
        else { int m = (l + r) >> 1; upd(2 * v, l, m, ql, qr, d); upd(2 * v + 1, m + 1, r, ql, qr, d); }
        if (cnt[v] > 0) len[v] = Y[r + 1] - Y[l];
        else if (l == r) len[v] = 0;
        else len[v] = len[2 * v] + len[2 * v + 1];
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long[][] ev = new long[2 * n][];
        long[] ys = new long[2 * n];
        for (int i = 0; i < n; i++) {
            long x1 = in.nextLong(), y1 = in.nextLong(), x2 = in.nextLong(), y2 = in.nextLong();
            ev[2 * i] = new long[]{x1, 1, y1, y2}; ev[2 * i + 1] = new long[]{x2, -1, y1, y2};
            ys[2 * i] = y1; ys[2 * i + 1] = y2;
        }
        Arrays.sort(ys);                                          // long[] from input coordinates: shuffle if hacks are possible
        int k = 0;
        for (int i = 0; i < ys.length; i++) if (i == 0 || ys[i] != ys[i - 1]) ys[k++] = ys[i];
        Y = Arrays.copyOf(ys, k);
        int m = k - 1;
        cnt = new int[4 * m]; len = new long[4 * m];
        Arrays.sort(ev, (p, q) -> Long.compare(p[0], q[0]));    // object sort: TimSort, no anti-quicksort issue
        long area = 0, prevX = ev[0][0];
        for (long[] e : ev) {
            area += len[1] * (e[0] - prevX);
            prevX = e[0];
            int a = Arrays.binarySearch(Y, e[2]), b = Arrays.binarySearch(Y, e[3]) - 1;
            upd(1, 0, m - 1, a, b, (int) e[1]);
        }
        System.out.println(area);
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
2
0 0 2 2
1 1 3 3
out:
7
-->
<!-- test
in:
3
0 0 1 1
0 0 1 1
5 5 6 7
out:
3
-->
<!-- test
in:
1
0 0 1000000000 1000000000
out:
1000000000000000000
-->
<!-- test
in:
3
0 0 4 1
0 0 1 4
3 0 4 4
out:
10
-->

</details>

### Example 5 — The Child and Sequence (range mod by potential)  ·  ★ 2300

- **Source:** [CF 438D · The Child and Sequence](https://codeforces.com/problemset/problem/438/D) — 2300
- **Difficulty:** 2300
- **Problem:** $n, m \le 10^5$, values $\le 10^9$. Operations: `1 l r` print $\sum_{i=l}^r a_i$; `2 l r x` set $a_i \leftarrow a_i \bmod x$ on $[l, r]$; `3 k x` set $a_k = x$.
- **Thinking from first principles:** no tag exists for mod (§1.4). But mod is either a no-op ($a < x$) or at least halves $a$. So: keep sum and max; enter a node only if its max $\ge x$;
  at a leaf apply the mod directly. Each element can be halved only $\log_2 10^9 \approx 30$ times between assignments, and each assignment restores at most 30 "units" of potential.

<details><summary>Solution</summary>

Total $O((n + m)\log n \log V)$. Sums up to $10^{14}$ → 64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;

int n;
vector<long long> sm, mx;
void pull(int v) { sm[v] = sm[2 * v] + sm[2 * v + 1]; mx[v] = max(mx[2 * v], mx[2 * v + 1]); }
void build(int v, int l, int r, const vector<long long>& a) {
    if (l == r) { sm[v] = mx[v] = a[l]; return; }
    int m = (l + r) >> 1;
    build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a); pull(v);
}
void modUpd(int v, int l, int r, int ql, int qr, long long x) {
    if (qr < l || r < ql || mx[v] < x) return;                  // no element can change
    if (l == r) { sm[v] %= x; mx[v] = sm[v]; return; }
    int m = (l + r) >> 1;
    modUpd(2 * v, l, m, ql, qr, x); modUpd(2 * v + 1, m + 1, r, ql, qr, x); pull(v);
}
void setUpd(int v, int l, int r, int p, long long x) {
    if (l == r) { sm[v] = mx[v] = x; return; }
    int m = (l + r) >> 1;
    if (p <= m) setUpd(2 * v, l, m, p, x); else setUpd(2 * v + 1, m + 1, r, p, x);
    pull(v);
}
long long query(int v, int l, int r, int ql, int qr) {
    if (qr < l || r < ql) return 0;
    if (ql <= l && r <= qr) return sm[v];
    int m = (l + r) >> 1;
    return query(2 * v, l, m, ql, qr) + query(2 * v + 1, m + 1, r, ql, qr);
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int m; cin >> n >> m;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    sm.assign(4 * n, 0); mx.assign(4 * n, 0);
    build(1, 0, n - 1, a);
    while (m--) {
        int type; cin >> type;
        if (type == 1) { int l, r; cin >> l >> r; cout << query(1, 0, n - 1, l - 1, r - 1) << '\n'; }
        else if (type == 2) { int l, r; long long x; cin >> l >> r >> x; modUpd(1, 0, n - 1, l - 1, r - 1, x); }
        else { int k; long long x; cin >> k >> x; setUpd(1, 0, n - 1, k - 1, x); }
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long[] sm, mx;
    static void pull(int v) { sm[v] = sm[2 * v] + sm[2 * v + 1]; mx[v] = Math.max(mx[2 * v], mx[2 * v + 1]); }
    static void build(int v, int l, int r, long[] a) {
        if (l == r) { sm[v] = mx[v] = a[l]; return; }
        int m = (l + r) >> 1;
        build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a); pull(v);
    }
    static void modUpd(int v, int l, int r, int ql, int qr, long x) {
        if (qr < l || r < ql || mx[v] < x) return;
        if (l == r) { sm[v] %= x; mx[v] = sm[v]; return; }
        int m = (l + r) >> 1;
        modUpd(2 * v, l, m, ql, qr, x); modUpd(2 * v + 1, m + 1, r, ql, qr, x); pull(v);
    }
    static void setUpd(int v, int l, int r, int p, long x) {
        if (l == r) { sm[v] = mx[v] = x; return; }
        int m = (l + r) >> 1;
        if (p <= m) setUpd(2 * v, l, m, p, x); else setUpd(2 * v + 1, m + 1, r, p, x);
        pull(v);
    }
    static long query(int v, int l, int r, int ql, int qr) {
        if (qr < l || r < ql) return 0;
        if (ql <= l && r <= qr) return sm[v];
        int m = (l + r) >> 1;
        return query(2 * v, l, m, ql, qr) + query(2 * v + 1, m + 1, r, ql, qr);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), m = in.nextInt();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        sm = new long[4 * n]; mx = new long[4 * n];
        build(1, 0, n - 1, a);
        while (m-- > 0) {
            int type = in.nextInt();
            if (type == 1) { int l = in.nextInt(), r = in.nextInt(); out.println(query(1, 0, n - 1, l - 1, r - 1)); }
            else if (type == 2) { int l = in.nextInt(), r = in.nextInt(); modUpd(1, 0, n - 1, l - 1, r - 1, in.nextLong()); }
            else { int k = in.nextInt(); setUpd(1, 0, n - 1, k - 1, in.nextLong()); }
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
1 2 3 4 5
2 3 5 4
3 3 5
1 2 5
2 1 3 3
1 1 3
out:
8
5
-->
<!-- test
in:
1 4
1000000000
2 1 1 7
1 1 1
3 1 999999999
1 1 1
out:
6
999999999
-->

</details>

### Example 6 — Range chmin, range sum, range max (segment tree beats)  ·  ★ ≈2500

- **Source:** Original problem (the standard "Gorgeous Sequence"-style exercise).
- **Difficulty:** ≈2500 (est.)
- **Problem:** $n, q \le 2\cdot10^5$, $0 \le a_i \le 10^9$. `1 l r x`: $a_i \leftarrow \min(a_i, x)$ on $[l, r]$; `2 l r`: print the sum; `3 l r`: print the max.
- **Thinking from first principles:** chmin with $x$ changes exactly the elements above $x$ by different amounts — no single tag. But if in a node only the *maximum value* exceeds $x$
  (i.e. second max $< x$), all changed elements change by the same amount $m_1 - x$, and we know how many there are. Store $(m_1, m_2, c, s)$, tag "cap at $m_1$" for children, break otherwise.
  The amortised bound is the potential argument of §1.4.

<details><summary>Solution</summary>

`push(v)` caps each child at `mx1[v]` (only children whose max exceeds it change). Leaves have $m_2 = -\infty$, so updates never break a leaf.
$O((n + q)\log n)$ amortised.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long NEG = LLONG_MIN / 4;

int n;
vector<long long> mx1, mx2, sm;
vector<int> cmx;
void pull(int v) {
    int L = 2 * v, R = 2 * v + 1;
    sm[v] = sm[L] + sm[R];
    if (mx1[L] > mx1[R]) { mx1[v] = mx1[L]; cmx[v] = cmx[L]; mx2[v] = max(mx2[L], mx1[R]); }
    else if (mx1[L] < mx1[R]) { mx1[v] = mx1[R]; cmx[v] = cmx[R]; mx2[v] = max(mx1[L], mx2[R]); }
    else { mx1[v] = mx1[L]; cmx[v] = cmx[L] + cmx[R]; mx2[v] = max(mx2[L], mx2[R]); }
}
void capNode(int v, long long x) {                               // precondition: mx2[v] < x
    if (mx1[v] <= x) return;
    sm[v] -= (mx1[v] - x) * cmx[v];
    mx1[v] = x;
}
void push(int v) { capNode(2 * v, mx1[v]); capNode(2 * v + 1, mx1[v]); }
void build(int v, int l, int r, const vector<long long>& a) {
    if (l == r) { mx1[v] = sm[v] = a[l]; mx2[v] = NEG; cmx[v] = 1; return; }
    int m = (l + r) >> 1;
    build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a); pull(v);
}
void chmin(int v, int l, int r, int ql, int qr, long long x) {
    if (qr < l || r < ql || mx1[v] <= x) return;
    if (ql <= l && r <= qr && mx2[v] < x) { capNode(v, x); return; }
    push(v);
    int m = (l + r) >> 1;
    chmin(2 * v, l, m, ql, qr, x); chmin(2 * v + 1, m + 1, r, ql, qr, x); pull(v);
}
long long qsum(int v, int l, int r, int ql, int qr) {
    if (qr < l || r < ql) return 0;
    if (ql <= l && r <= qr) return sm[v];
    push(v);
    int m = (l + r) >> 1;
    return qsum(2 * v, l, m, ql, qr) + qsum(2 * v + 1, m + 1, r, ql, qr);
}
long long qmax(int v, int l, int r, int ql, int qr) {
    if (qr < l || r < ql) return NEG;
    if (ql <= l && r <= qr) return mx1[v];
    push(v);
    int m = (l + r) >> 1;
    return max(qmax(2 * v, l, m, ql, qr), qmax(2 * v + 1, m + 1, r, ql, qr));
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int q; cin >> n >> q;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    mx1.assign(4 * n, 0); mx2.assign(4 * n, NEG); sm.assign(4 * n, 0); cmx.assign(4 * n, 0);
    build(1, 0, n - 1, a);
    while (q--) {
        int type, l, r; cin >> type >> l >> r; l--; r--;
        if (type == 1) { long long x; cin >> x; chmin(1, 0, n - 1, l, r, x); }
        else if (type == 2) cout << qsum(1, 0, n - 1, l, r) << '\n';
        else cout << qmax(1, 0, n - 1, l, r) << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long NEG = Long.MIN_VALUE / 4;
    static long[] mx1, mx2, sm; static int[] cmx;
    static void pull(int v) {
        int L = 2 * v, R = 2 * v + 1;
        sm[v] = sm[L] + sm[R];
        if (mx1[L] > mx1[R]) { mx1[v] = mx1[L]; cmx[v] = cmx[L]; mx2[v] = Math.max(mx2[L], mx1[R]); }
        else if (mx1[L] < mx1[R]) { mx1[v] = mx1[R]; cmx[v] = cmx[R]; mx2[v] = Math.max(mx1[L], mx2[R]); }
        else { mx1[v] = mx1[L]; cmx[v] = cmx[L] + cmx[R]; mx2[v] = Math.max(mx2[L], mx2[R]); }
    }
    static void capNode(int v, long x) {
        if (mx1[v] <= x) return;
        sm[v] -= (mx1[v] - x) * cmx[v];
        mx1[v] = x;
    }
    static void push(int v) { capNode(2 * v, mx1[v]); capNode(2 * v + 1, mx1[v]); }
    static void build(int v, int l, int r, long[] a) {
        if (l == r) { mx1[v] = sm[v] = a[l]; mx2[v] = NEG; cmx[v] = 1; return; }
        int m = (l + r) >> 1;
        build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a); pull(v);
    }
    static void chmin(int v, int l, int r, int ql, int qr, long x) {
        if (qr < l || r < ql || mx1[v] <= x) return;
        if (ql <= l && r <= qr && mx2[v] < x) { capNode(v, x); return; }
        push(v);
        int m = (l + r) >> 1;
        chmin(2 * v, l, m, ql, qr, x); chmin(2 * v + 1, m + 1, r, ql, qr, x); pull(v);
    }
    static long qsum(int v, int l, int r, int ql, int qr) {
        if (qr < l || r < ql) return 0;
        if (ql <= l && r <= qr) return sm[v];
        push(v);
        int m = (l + r) >> 1;
        return qsum(2 * v, l, m, ql, qr) + qsum(2 * v + 1, m + 1, r, ql, qr);
    }
    static long qmax(int v, int l, int r, int ql, int qr) {
        if (qr < l || r < ql) return NEG;
        if (ql <= l && r <= qr) return mx1[v];
        push(v);
        int m = (l + r) >> 1;
        return Math.max(qmax(2 * v, l, m, ql, qr), qmax(2 * v + 1, m + 1, r, ql, qr));
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), q = in.nextInt();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        mx1 = new long[4 * n]; mx2 = new long[4 * n]; sm = new long[4 * n]; cmx = new int[4 * n];
        Arrays.fill(mx2, NEG);
        build(1, 0, n - 1, a);
        while (q-- > 0) {
            int type = in.nextInt(), l = in.nextInt() - 1, r = in.nextInt() - 1;
            if (type == 1) chmin(1, 0, n - 1, l, r, in.nextLong());
            else if (type == 2) out.println(qsum(1, 0, n - 1, l, r));
            else out.println(qmax(1, 0, n - 1, l, r));
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
5 6
1 2 3 4 5
3 1 5
1 2 4 2
2 1 5
3 2 4
1 1 5 1
2 1 5
out:
5
12
2
5
-->
<!-- test
in:
1 4
1000000000
1 1 1 1000000000
2 1 1
1 1 1 0
3 1 1
out:
1000000000
0
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Descent preconditions**: prefix-sum descent needs non-negative values (otherwise prefix sums are not monotone); check the total first (`sm[1] < k` → none).
2. **Range-restricted descent returns early.** Search the left child first and return as soon as it succeeds; searching both and taking the min is $O(\log^2 n)$ or worse.
3. **Dynamic tree memory**: estimate nodes as $q(\log_2 C - \log_2 q + 2)$ and preallocate; in Java use `int[]` pools with doubling, not `Node` objects (12–16 bytes of header each).
4. **Reallocation trap**: `L[v] = newNode()` when `newNode` can reallocate `L` — store into a temporary first (Java evaluates the array reference before the call).
5. **Midpoints of large or negative ranges**: `l + ((r - l) >> 1)` — `(l + r) / 2` overflows for `int` near $2^{31}$ and rounds toward zero for negatives.
6. **Merging is destructive.** After `merge(a, b)`, tree `b` is garbage. Read answers before merging, or make merging persistent (copy nodes) at a memory cost.
7. **Pool size for merging** = number of nodes created by the initial trees; merging creates none. $n(\lceil\log_2 K\rceil+1)$ for singleton trees.
8. **Potential arguments need the right pruning test**: for mod prune with `max < x`; for chmin prune with `max <= x` and tag with `second max < x`. Pruning with the wrong inequality silently degrades to $O(n)$ per update.
9. **Range mod with $x = 1$** turns everything into 0; fine, but a "set" operation can then re-inflate values: the potential argument budgets $\log V$ per assignment.
10. **Union-area tree**: leaf $i$ represents $[Y_i, Y_{i+1})$, so an interval $[y_1, y_2)$ maps to leaves $\text{idx}(y_1) .. \text{idx}(y_2) - 1$. Using closed leaves double-counts boundaries. Size the tree with $m - 1 \ge 1$ leaves.
11. **Sorting events with equal $x$** in any order is fine for area (zero width), but for *perimeter* or "touching counts" problems the order of $+1/-1$ at equal $x$ matters.
12. **Beats with `long long` sentinels**: use $-\infty = $ `LLONG_MIN / 4`, never `LLONG_MIN` (subtractions overflow).

## 7. Going further (toward 2400–2600+)

- **Descent with lazy tags**: [CF 1179C · Serge and Dining Room](https://codeforces.com/problemset/problem/1179/C) — 2200 (find the rightmost position with positive suffix balance) and [CF 817F · MEX Queries](https://codeforces.com/problemset/problem/817/F) — 2300 (assign/flip on compressed intervals, then find the first zero).
- **Segment tree split and merge** (split by value range in $O(\log n)$ amortised): [CF 911G · Mass Change Queries](https://codeforces.com/problemset/problem/911/G) — 2500; [CF 558E · A Simple Task](https://codeforces.com/problemset/problem/558/E) — 2300 has an elegant split/merge solution too.
- **Merging for subtree statistics**: [CF 600E · Lomsat gelral](https://codeforces.com/problemset/problem/600/E) — 2300, [CF 1009F · Dominant Indices](https://codeforces.com/problemset/problem/1009/F) — 2300 (also solvable by long-path decomposition).
- **Full beats with range add and historic maxima** (Ji's "Gorgeous Sequence" family): [CF 1290E · Cartesian Tree](https://codeforces.com/problemset/problem/1290/E) — 3300, [CF 855F · Nagini](https://codeforces.com/problemset/problem/855/F) — 3100.
- **Kinetic segment trees, Li Chao trees, segment trees over time** for offline deletions ([segment tree on time](../16-IGM-Frontier/02-segment-tree-on-time-and-dsu-rollback.md)).
- **Sweep variants**: maximum number of rectangles covering a point (add/max lazy), union perimeter (count covered segments' endpoints), [CF 610D · Vika and Segments](https://codeforces.com/problemset/problem/610/D) — 2300 (union of unit-width segments).

## 8. Practice ladder

**1500–1900**
- [ ] [CSES 1143 · Hotel Queries](https://cses.fi/problemset/task/1143)
- [ ] [CSES 1749 · List Removals](https://cses.fi/problemset/task/1749)
- [ ] [CSES 1144 · Salary Queries](https://cses.fi/problemset/task/1144)
- [ ] [CSES 1139 · Distinct Colors](https://cses.fi/problemset/task/1139)
- [ ] [CF 1354D · Multiset](https://codeforces.com/problemset/problem/1354/D) — 1900

**1900–2300**
- [ ] [CF 1446C · Xor Tree](https://codeforces.com/problemset/problem/1446/C) — 2100
- [ ] [CF 1179C · Serge and Dining Room](https://codeforces.com/problemset/problem/1179/C) — 2200
- [ ] [CF 438D · The Child and Sequence](https://codeforces.com/problemset/problem/438/D) — 2300
- [ ] [CF 915E · Physical Education Lessons](https://codeforces.com/problemset/problem/915/E) — 2300
- [ ] [CF 817F · MEX Queries](https://codeforces.com/problemset/problem/817/F) — 2300
- [ ] [CF 600E · Lomsat gelral](https://codeforces.com/problemset/problem/600/E) — 2300
- [ ] [CF 1009F · Dominant Indices](https://codeforces.com/problemset/problem/1009/F) — 2300
- [ ] [CF 610D · Vika and Segments](https://codeforces.com/problemset/problem/610/D) — 2300
- [ ] [CF 1093G · Multidimensional Queries](https://codeforces.com/problemset/problem/1093/G) — 2300

**2400+**
- [ ] [CF 1638E · Colorful Operations](https://codeforces.com/problemset/problem/1638/E) — 2400
- [ ] [CF 911G · Mass Change Queries](https://codeforces.com/problemset/problem/911/G) — 2500
- [ ] [CF 896C · Willem, Chtholly and Seniorious](https://codeforces.com/problemset/problem/896/C) — 2600
- [ ] [CF 855F · Nagini](https://codeforces.com/problemset/problem/855/F) — 3100
- [ ] [CF 1290E · Cartesian Tree](https://codeforces.com/problemset/problem/1290/E) — 3300

## 9. LeetCode / FAANG cross-reference

- [LC 850 · Rectangle Area II](https://leetcode.com/problems/rectangle-area-ii/) — Hard — Example 4 exactly (answer modulo $10^9+7$).
- [LC 2286 · Booking Concert Tickets in Groups](https://leetcode.com/problems/booking-concert-tickets-in-groups/) — Hard — max-tree descent for "first row with $k$ free seats" + sum-tree descent for "scatter".
- [LC 2940 · Find Building Where Alice and Bob Can Meet](https://leetcode.com/problems/find-building-where-alice-and-bob-can-meet/) — Hard — "first index $> j$ with height $> h$": range-restricted descent.
- [LC 732 · My Calendar III](https://leetcode.com/problems/my-calendar-iii/) — Hard — dynamic tree with add/max over $[0, 10^9]$.
- [LC 2276 · Count Integers in Intervals](https://leetcode.com/problems/count-integers-in-intervals/) — Hard — dynamic tree with "assign 1" and pruning of fully-covered nodes.
- [LC 218 · The Skyline Problem](https://leetcode.com/problems/the-skyline-problem/) — Hard — sweep with a max structure (heap with lazy deletion or a max tree).

Rare in interviews beyond descent and sweep: interviewers expect a heap/ordered-map sweep for skyline-type questions.

## 10. Self-check

1. Prove that "first element $\ge x$ in $[l, r]$" takes $O(\log n)$, not $O(\log^2 n)$.
2. Estimate the number of nodes of a dynamic tree after $2\cdot10^5$ insertions into $[1, 10^9]$.
3. Why does merging $n$ singleton value-trees cost $O(n \log C)$ in total, independent of the tree shape?
4. Why does $a \bmod x$ at least halve $a$ when $x \le a$? What potential bounds the total work?
5. In beats, why is it safe to tag a node when $m_2 < x < m_1$, and why are breaks amortised cheap?
6. Why does the union-area tree never need push-down? What would break if removals did not mirror insertions?
7. Which static structures answer "k-th smallest in $a[l..r]$", and what are their complexities?

<details><summary>Answers</summary>

1. Partial nodes are $O(\log n)$; fully covered nodes with max $< x$ are rejected in $O(1)$ (at most two per level); the first fully covered node with max $\ge x$ contains an answer, and the descent into it is one root-to-leaf path that never fails.
2. Roughly $q(\log_2 C - \log_2 q + 2) \approx 2\cdot10^5 \cdot (30 - 17.6 + 2) \approx 2.9\cdot10^6$, plus the shared top part; preallocate ~$4\cdot10^6$.
3. Every merge call with two non-null nodes deletes one node; no nodes are created; there are $n(\log C + 1)$ nodes in total.
4. If $x \le a/2$ the remainder is $< x \le a/2$; otherwise it is $a - x < a/2$. Potential $\sum \log_2(a_i+1)$ drops by $\ge 1$ per changed leaf and rises by $\le \log V$ per assignment.
5. Only elements equal to $m_1$ exceed $x$, all decrease by the same $m_1 - x$, so sum and max update in $O(1)$ and the tag "cap at $m_1$" pushes correctly. A break happens only when $x \le m_2$, which merges at least two distinct values in that node, decreasing the total "distinct values per node" potential.
6. `cnt` is only ever undone by the same canonical decomposition, so it never needs to reach children; `len` is recomputed from the subtree. Arbitrary removals would make counts in sub-nodes wrong.
7. Persistent segment tree ($O(\log n)$ per query, $O(n\log n)$ memory), wavelet tree ($O(\log V)$), merge-sort tree with binary search on the answer ($O(\log^3 n)$ or $O(\log^2 n)$ with cascading).

</details>
