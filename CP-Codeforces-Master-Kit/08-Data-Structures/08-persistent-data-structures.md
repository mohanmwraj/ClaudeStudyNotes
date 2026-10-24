# Persistent Data Structures

> **Band:** 🟠 2100–2500 · **Priority:** ⚡ (persistent segment tree is 🔥 once you are past 2100) · **FAANG:** low · **Prerequisites:** [segment tree basics](02-segment-tree-basics.md), [dynamic segment trees](04-segment-tree-advanced-descent-merging-beats.md), [Fenwick offline tricks](01-fenwick-tree.md)
> **You can say you know this when:** you can implement a persistent segment tree with an array node pool in both languages, estimate its memory before coding, answer "k-th smallest in $a[l..r]$" and "how many distinct values in $a[l..r]$" online by subtracting two versions, and recognise when an *offline* version tree with undo is simpler than real persistence.

## 1. First principles — why this works

**The problem.** We need *every* historical version of a structure: "query the array as it was after update $t$", "make a copy of array $k$ and modify it",
"go back to the state after operation $k$ and continue from there". Copying the whole structure per update costs $O(n)$ time and memory per version.

**The observation: an update changes very little.** In any tree-shaped structure (segment tree, BST, trie), a point update modifies only the nodes on one root-to-leaf
path — $O(\log n)$ nodes. Everything else is unchanged. So:

> **Path copying.** Never modify a node. To update, create *new copies* of the nodes on the path, each pointing to the new copy below it and to the *old, shared* sibling
> subtree on the other side. The new root identifies the new version; the old root still describes the old version, untouched.

Because nodes are immutable after creation, sharing is safe: any number of versions can point into the same subtree. Each version costs $O(\log n)$ new nodes, and a query on
version $t$ is an ordinary query starting from `root[t]`.

**Versions form a tree, not a list.** "Copy array $k$" or "go back to version $k$" just records `root[new] = root[k]`; later updates branch from there. Path copying supports
any branching for free.

**The killer application: prefix versions over values.** Build a *value-indexed* count tree (counts of each compressed value) and make version $i$ = version $i-1$ plus $a_i$.
Version $i$ is then the multiset of the prefix $a_1..a_i$. Counts are additive, so the multiset of $a_{l..r}$ is "version $r$ minus version $l-1$" — not stored anywhere,
but we can *walk both trees in lockstep* and subtract counts node by node:

- **k-th smallest in $a[l..r]$**: at each node, $c = \text{cnt}(\text{left}_r) - \text{cnt}(\text{left}_{l-1})$ is how many elements of $a[l..r]$ fall in the left value half.
  If $k \le c$ go left, otherwise $k \mathrel{-}= c$ and go right. $O(\log n)$, online. (This is the Fenwick "k-th by descent" applied to a *range* multiset.)
- **Count of values $< x$ in $a[l..r]$**: a prefix query on the difference.
- **Distinct values in $a[l..r]$, online**: let $\text{prev}_i$ be the previous position of the same value (0 if none). Value $a_i$ is the *first* occurrence of its value inside $[l, r]$ iff
  $\text{prev}_i < l$. So distinct count $= \#\{i \in [l, r] : \text{prev}_i < l\}$ — a "count values $< l$" query on the multiset $\{\text{prev}_i : i \in [l, r]\}$, i.e. on versions $r$ and $l-1$
  of a tree indexed by prev. Replacing $\text{prev}$ with the $k$-th previous occurrence counts "elements among the first $k$ copies of their value" (Example 3).

**Memory estimate — do it before coding.** Initial build: $2n - 1$ nodes (or 1 null node if you start from an empty count tree). Each point update: $\lceil\log_2 n\rceil + 1$ nodes.
For $n = q = 2\cdot10^5$: $4\cdot10^5 + 2\cdot10^5\cdot 19 \approx 4.2\cdot10^6$ nodes. With two `int` child indices and one `long` value per node that is 67 MB; with `int` counts 50 MB.
Allocate the pool once: `n * (ceil(log2 n) + 2)` plus the build — and in Java use parallel primitive arrays (`int[] L, R, cnt`), never `Node` objects (each object costs 16+ bytes of header,
and $4\cdot10^6$ objects stress the GC).

**The null-node trick.** Let node 0 be an empty node whose children are node 0 itself and whose count is 0. Then an "empty version" is just root 0, inserting into an empty tree works without
building anything, and walks can step into missing children safely.

**Persistent arrays.** An array with get/set in $O(\log n)$ and full history is a persistent segment tree with values at leaves. It is the building block of persistent DSU
(union by size *without* path compression on persistent arrays, $O(\log^2 n)$ per operation) 🧊.

**Lazy propagation and persistence.** Pushing a tag *modifies* children, which may be shared. Either use **permanent tags** (keep the tag at the node and add it during queries — see
[lazy propagation](03-lazy-propagation.md)) or *copy* both children during every push (doubles node usage).

**Offline alternative: the version tree with undo.** If all operations are known in advance, build the tree of versions explicitly (operation $i$'s parent is the version it was applied to) and
run a DFS from the initial version: apply an operation when entering its node, record the answer, recurse, *undo* when leaving. Each operation is applied and undone once, so the total cost is
the sum of operation costs — no persistence and no extra memory beyond an undo log. This is often simpler than a persistent structure (Example 4).

**Fat nodes** (the other classic method): each memory cell keeps a list of (version, value) pairs; reading version $t$ binary-searches the list. This is exactly
[LC 1146 · Snapshot Array](https://leetcode.com/problems/snapshot-array/) — Medium; it works for linear version histories.

## 2. Formulas, definitions and identities

| Quantity | Value |
|---|---|
| new nodes per point update | $\lceil \log_2 n\rceil + 1$ |
| total nodes, $n$ build + $q$ updates | $\approx 2n + q(\lceil\log_2 n\rceil + 1)$ |
| prefix versions over values | $\text{cnt}_{[l,r]}(\text{node}) = \text{cnt}_{\text{root}_r}(\text{node}) - \text{cnt}_{\text{root}_{l-1}}(\text{node})$ |
| k-th step | $c = \text{cnt}(L_r) - \text{cnt}(L_{l-1})$; go left iff $k \le c$, else $k \leftarrow k - c$ |
| distinct in $[l, r]$ | $\#\{i \in [l, r] : \text{prev}_i < l\}$ |
| "at most $k$ copies per value" size | $\#\{i \in [l, r] : \text{prev}^{(k)}_i < l\}$, $\text{prev}^{(k)}$ = $k$-th previous occurrence |
| persistent array get/set | $O(\log n)$ time, $O(\log n)$ new nodes per set |
| version tree with undo | $O(\sum \text{cost(apply)} + \text{cost(undo)})$, no persistence |

All queries on a single version cost $O(\log n)$; lockstep walks on two versions cost $O(\log n)$ as well.

## 3. Implementation (C++ and Java)

### 3.1 Persistent count tree over values (insert, k-th, count less than)

Node 0 is the null node. Values are compressed to $[0, V)$. `root[i]` = version after inserting $a_1..a_i$; `root[0] = 0`.

```cpp
struct PersistentCount {
    int V; vector<int> L, R, cnt;                       // node 0 = null (children 0, count 0)
    PersistentCount(int V, int cap) : V(V) { L.reserve(cap); R.reserve(cap); cnt.reserve(cap); L.push_back(0); R.push_back(0); cnt.push_back(0); }
    int clone(int v) { L.push_back(L[v]); R.push_back(R[v]); cnt.push_back(cnt[v]); return int(L.size()) - 1; }
    int insert(int prev, int pos) {                     // returns the root of prev + {pos}; path copying, iterative
        int root = clone(prev), v = root, lo = 0, hi = V - 1;
        cnt[v]++;
        while (lo < hi) {
            int m = (lo + hi) >> 1;
            if (pos <= m) { int c = clone(L[v]); L[v] = c; v = c; hi = m; }
            else          { int c = clone(R[v]); R[v] = c; v = c; lo = m + 1; }
            cnt[v]++;
        }
        return root;
    }
    int kth(int u, int w, int k) const {                // k-th smallest (1-based) of multiset(u) - multiset(w)
        int lo = 0, hi = V - 1;
        while (lo < hi) {
            int m = (lo + hi) >> 1, c = cnt[L[u]] - cnt[L[w]];
            if (k <= c) { u = L[u]; w = L[w]; hi = m; }
            else { k -= c; u = R[u]; w = R[w]; lo = m + 1; }
        }
        return lo;
    }
    int countLess(int u, int w, int x) const {          // #elements < x in multiset(u) - multiset(w)
        int lo = 0, hi = V - 1, res = 0;
        if (x <= 0) return 0;
        if (x > hi) return cnt[u] - cnt[w];
        while (lo < hi) {                               // walk towards x - 1, adding whole left halves
            int m = (lo + hi) >> 1;
            if (x - 1 <= m) { u = L[u]; w = L[w]; hi = m; }
            else { res += cnt[L[u]] - cnt[L[w]]; u = R[u]; w = R[w]; lo = m + 1; }
        }
        return res + cnt[u] - cnt[w];                   // the leaf x - 1 itself
    }
};
```

```java
static class PersistentCount {
    final int V; int[] L, R, cnt; int size = 1;          // node 0 = null
    PersistentCount(int V, int cap) { this.V = V; L = new int[cap]; R = new int[cap]; cnt = new int[cap]; }
    int clone(int v) { L[size] = L[v]; R[size] = R[v]; cnt[size] = cnt[v]; return size++; }
    int insert(int prev, int pos) {
        int root = clone(prev), v = root, lo = 0, hi = V - 1;
        cnt[v]++;
        while (lo < hi) {
            int m = (lo + hi) >> 1;
            if (pos <= m) { int c = clone(L[v]); L[v] = c; v = c; hi = m; }
            else          { int c = clone(R[v]); R[v] = c; v = c; lo = m + 1; }
            cnt[v]++;
        }
        return root;
    }
    int kth(int u, int w, int k) {
        int lo = 0, hi = V - 1;
        while (lo < hi) {
            int m = (lo + hi) >> 1, c = cnt[L[u]] - cnt[L[w]];
            if (k <= c) { u = L[u]; w = L[w]; hi = m; }
            else { k -= c; u = R[u]; w = R[w]; lo = m + 1; }
        }
        return lo;
    }
    int countLess(int u, int w, int x) {
        int lo = 0, hi = V - 1, res = 0;
        if (x <= 0) return 0;
        if (x > hi) return cnt[u] - cnt[w];
        while (lo < hi) {
            int m = (lo + hi) >> 1;
            if (x - 1 <= m) { u = L[u]; w = L[w]; hi = m; }
            else { res += cnt[L[u]] - cnt[L[w]]; u = R[u]; w = R[w]; lo = m + 1; }
        }
        return res + cnt[u] - cnt[w];
    }
}
```

Pool capacity: $1 + n(\lceil\log_2 V\rceil + 1)$ for $n$ inserts.

## 4. Recognising the pattern

- **"k-th smallest / count of values in a range of a static array", forced online** (queries encoded with the previous answer) → persistent count tree over values with prefix versions. Offline alternatives: wavelet tree, merge-sort tree, parallel binary search.
- **"Number of distinct values in $[l, r]$", forced online** → prefix versions indexed by `prev`. Offline → BIT sorted by right end ([Fenwick](01-fenwick-tree.md)).
- **Explicit history**: "copy array $k$", "undo to version $k$", "answer queries about the state at time $t$" → path copying.
- **All operations known in advance and "go back to version $k$"** → version tree + DFS with undo (no persistence needed).
- **Two-dimensional dominance counting online** ($\#\{i \le r : y_i < x\}$) → persistent tree over $y$, versions by $x$/index.
- **Tree path statistics** (k-th smallest on the path $u \to v$) → versions along root paths: $\text{root}_u + \text{root}_v - \text{root}_{\mathrm{lca}} - \text{root}_{\mathrm{parent}(\mathrm{lca})}$.

## 5. Worked examples (graded)

### Example 1 — Range Queries and Copies  ·  ★ ≈1900

- **Source:** [CSES 1737 · Range Queries and Copies](https://cses.fi/problemset/task/1737)
- **Difficulty:** ≈1900 (est.)
- **Problem:** an array of $n \le 2\cdot10^5$ values; $q \le 2\cdot10^5$ operations on a growing list of arrays (initially only array 1): `1 k a x` set position $a$ of array $k$ to $x$; `2 k a b` print the sum of positions $a..b$ of array $k$; `3 k` append a copy of array $k$ as a new array.
- **Thinking from first principles:** copying is the operation that kills naive solutions ($O(n)$ each). With path copying a copy is free — `root.push_back(root[k])` — and an assignment makes $\approx 19$ new nodes on array $k$'s current root only.

<details><summary>Solution</summary>

Persistent sum tree with point assignment. Pool: $2n + 19q$ nodes. $O((n + q)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

vector<int> Lc, Rc;
vector<long long> S;
int node(int l, int r, long long s) { Lc.push_back(l); Rc.push_back(r); S.push_back(s); return int(S.size()) - 1; }
int build(int lo, int hi, const vector<long long>& a) {
    if (lo == hi) return node(0, 0, a[lo]);
    int m = (lo + hi) >> 1;
    int l = build(lo, m, a), r = build(m + 1, hi, a);
    return node(l, r, S[l] + S[r]);
}
int setv(int v, int lo, int hi, int pos, long long x) {             // returns a new root; old version untouched
    if (lo == hi) return node(0, 0, x);
    int m = (lo + hi) >> 1;
    if (pos <= m) { int nl = setv(Lc[v], lo, m, pos, x); int r = Rc[v]; return node(nl, r, S[nl] + S[r]); }
    int nr = setv(Rc[v], m + 1, hi, pos, x); int l = Lc[v];
    return node(l, nr, S[l] + S[nr]);
}
long long sum(int v, int lo, int hi, int ql, int qr) {
    if (qr < lo || hi < ql) return 0;
    if (ql <= lo && hi <= qr) return S[v];
    int m = (lo + hi) >> 1;
    return sum(Lc[v], lo, m, ql, qr) + sum(Rc[v], m + 1, hi, ql, qr);
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    Lc.reserve(2 * n + 20 * q + 5); Rc.reserve(2 * n + 20 * q + 5); S.reserve(2 * n + 20 * q + 5);
    node(0, 0, 0);                                                  // node 0 unused
    vector<int> root = {build(0, n - 1, a)};
    while (q--) {
        int t, k; cin >> t >> k; k--;
        if (t == 1) { int pos; long long x; cin >> pos >> x; root[k] = setv(root[k], 0, n - 1, pos - 1, x); }
        else if (t == 2) { int l, r; cin >> l >> r; cout << sum(root[k], 0, n - 1, l - 1, r - 1) << '\n'; }
        else root.push_back(root[k]);
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] Lc, Rc; static long[] S; static int size = 1;            // node 0 unused
    static int node(int l, int r, long s) { Lc[size] = l; Rc[size] = r; S[size] = s; return size++; }
    static int build(int lo, int hi, long[] a) {
        if (lo == hi) return node(0, 0, a[lo]);
        int m = (lo + hi) >> 1;
        int l = build(lo, m, a), r = build(m + 1, hi, a);
        return node(l, r, S[l] + S[r]);
    }
    static int setv(int v, int lo, int hi, int pos, long x) {
        if (lo == hi) return node(0, 0, x);
        int m = (lo + hi) >> 1;
        if (pos <= m) { int nl = setv(Lc[v], lo, m, pos, x); return node(nl, Rc[v], S[nl] + S[Rc[v]]); }
        int nr = setv(Rc[v], m + 1, hi, pos, x);
        return node(Lc[v], nr, S[Lc[v]] + S[nr]);
    }
    static long sum(int v, int lo, int hi, int ql, int qr) {
        if (qr < lo || hi < ql) return 0;
        if (ql <= lo && hi <= qr) return S[v];
        int m = (lo + hi) >> 1;
        return sum(Lc[v], lo, m, ql, qr) + sum(Rc[v], m + 1, hi, ql, qr);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), q = in.nextInt();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        int depth = 1; while ((1 << (depth - 1)) < n) depth++;
        int cap = 2 * n + q * (depth + 1) + 5;
        Lc = new int[cap]; Rc = new int[cap]; S = new long[cap];
        int[] root = new int[q + 2]; int versions = 1;
        root[0] = build(0, n - 1, a);
        while (q-- > 0) {
            int t = in.nextInt(), k = in.nextInt() - 1;
            if (t == 1) { int pos = in.nextInt() - 1; root[k] = setv(root[k], 0, n - 1, pos, in.nextLong()); }
            else if (t == 2) { int l = in.nextInt() - 1, r = in.nextInt() - 1; out.println(sum(root[k], 0, n - 1, l, r)); }
            else root[versions++] = root[k];
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

In the Java `setv`, `Rc[v]` and `S[...]` are read *after* the recursive call returns; that is safe here only because the pool is preallocated (no reallocation) and old nodes are never modified.

<!-- test
in:
5 6
2 3 1 2 5
3 1
2 1 1 5
2 2 1 5
1 2 4 5
2 1 1 5
2 2 1 5
out:
13
13
13
16
-->
<!-- test
in:
1 5
1000000000
3 1
1 2 1 1
3 2
2 1 1 1
2 3 1 1
out:
1000000000
1
-->

</details>

### Example 2 — k-th smallest in a range (online)  ·  ★ ≈2000

- **Source:** Original problem (the classic "MKTHNUM" task; also the engine of [CF 840D · Destiny](https://codeforces.com/problemset/problem/840/D) — 2500).
- **Difficulty:** ≈2000 (est.)
- **Problem:** a static array of $n \le 2\cdot10^5$ values ($|a_i| \le 10^9$); $q \le 2\cdot10^5$ queries $(l, r, k)$: print the $k$-th smallest value of $a_l..a_r$.
- **Thinking from first principles:** sorting each range is $O(n\log n)$ per query. A merge-sort tree with binary search on the answer is $O(\log^3 n)$. The prefix-version idea of §1 gives the
  multiset of $a[l..r]$ implicitly as `root[r] − root[l-1]`, and the descent decides one bit of the answer's rank per level: $O(\log n)$ per query, online.

<details><summary>Solution</summary>

Compress values, insert prefix by prefix, answer with `kth(root[r], root[l-1], k)` and map back. Memory $1 + n(\lceil\log_2 V\rceil + 1)$ nodes.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct PersistentCount {
    int V; vector<int> L, R, cnt;
    PersistentCount(int V, int cap) : V(V) { L.reserve(cap); R.reserve(cap); cnt.reserve(cap); L.push_back(0); R.push_back(0); cnt.push_back(0); }
    int clone(int v) { L.push_back(L[v]); R.push_back(R[v]); cnt.push_back(cnt[v]); return int(L.size()) - 1; }
    int insert(int prev, int pos) {
        int root = clone(prev), v = root, lo = 0, hi = V - 1;
        cnt[v]++;
        while (lo < hi) {
            int m = (lo + hi) >> 1;
            if (pos <= m) { int c = clone(L[v]); L[v] = c; v = c; hi = m; }
            else          { int c = clone(R[v]); R[v] = c; v = c; lo = m + 1; }
            cnt[v]++;
        }
        return root;
    }
    int kth(int u, int w, int k) const {
        int lo = 0, hi = V - 1;
        while (lo < hi) {
            int m = (lo + hi) >> 1, c = cnt[L[u]] - cnt[L[w]];
            if (k <= c) { u = L[u]; w = L[w]; hi = m; }
            else { k -= c; u = R[u]; w = R[w]; lo = m + 1; }
        }
        return lo;
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    vector<int> a(n);
    for (auto& x : a) cin >> x;
    vector<int> vals(a);
    sort(vals.begin(), vals.end()); vals.erase(unique(vals.begin(), vals.end()), vals.end());
    int V = vals.size(), depth = 1;
    while ((1 << (depth - 1)) < V) depth++;
    PersistentCount pc(V, 1 + n * (depth + 1));
    vector<int> root(n + 1, 0);
    for (int i = 0; i < n; i++) root[i + 1] = pc.insert(root[i], int(lower_bound(vals.begin(), vals.end(), a[i]) - vals.begin()));
    while (q--) {
        int l, r, k; cin >> l >> r >> k;
        cout << vals[pc.kth(root[r], root[l - 1], k)] << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int V; static int[] L, R, cnt; static int size = 1;
    static int clone(int v) { L[size] = L[v]; R[size] = R[v]; cnt[size] = cnt[v]; return size++; }
    static int insert(int prev, int pos) {
        int root = clone(prev), v = root, lo = 0, hi = V - 1;
        cnt[v]++;
        while (lo < hi) {
            int m = (lo + hi) >> 1;
            if (pos <= m) { int c = clone(L[v]); L[v] = c; v = c; hi = m; }
            else          { int c = clone(R[v]); R[v] = c; v = c; lo = m + 1; }
            cnt[v]++;
        }
        return root;
    }
    static int kth(int u, int w, int k) {
        int lo = 0, hi = V - 1;
        while (lo < hi) {
            int m = (lo + hi) >> 1, c = cnt[L[u]] - cnt[L[w]];
            if (k <= c) { u = L[u]; w = L[w]; hi = m; }
            else { k -= c; u = R[u]; w = R[w]; lo = m + 1; }
        }
        return lo;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), q = in.nextInt();
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        int[] vals = a.clone();
        Random rnd = new Random(2);
        for (int i = n - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); int t = vals[i]; vals[i] = vals[j]; vals[j] = t; }
        Arrays.sort(vals);
        V = 0;
        for (int i = 0; i < n; i++) if (i == 0 || vals[i] != vals[i - 1]) vals[V++] = vals[i];
        int depth = 1; while ((1 << (depth - 1)) < V) depth++;
        int cap = 1 + n * (depth + 1);
        L = new int[cap]; R = new int[cap]; cnt = new int[cap];
        int[] root = new int[n + 1];
        for (int i = 0; i < n; i++) root[i + 1] = insert(root[i], Arrays.binarySearch(vals, 0, V, a[i]));
        while (q-- > 0) {
            int l = in.nextInt(), r = in.nextInt(), k = in.nextInt();
            out.println(vals[kth(root[r], root[l - 1], k)]);
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
7 3
1 5 2 6 3 7 4
2 5 3
4 4 1
1 7 3
out:
5
6
3
-->
<!-- test
in:
5 4
-1000000000 1000000000 -1000000000 0 0
1 5 1
1 5 2
1 5 3
2 5 4
out:
-1000000000
-1000000000
0
1000000000
-->
<!-- test
in:
1 1
42
1 1 1
out:
42
-->

</details>

### Example 3 — Army Creation (online "at most $k$ copies")  ·  ★ 2200

- **Source:** [CF 813E · Army Creation](https://codeforces.com/problemset/problem/813/E) — 2200
- **Difficulty:** 2200
- **Problem:** $n, k \le 10^5$, warrior types $a_i \le 10^5$; $q \le 10^5$ queries, **forced online**: with `last` = previous answer (initially 0), $l = ((x + \text{last}) \bmod n) + 1$, $r = ((y + \text{last}) \bmod n) + 1$, swap if $l > r$. Print the largest army from warriors $l..r$ with at most $k$ warriors of each type.
- **Thinking from first principles:** the answer is $\sum_{\text{type } t}\min(\text{cnt}_t, k)$ — keep the first $k$ occurrences of each type inside $[l, r]$. Position $i$ is among the first $k$ occurrences
  of its type inside $[l, r]$ iff its **$k$-th previous occurrence** $p_i$ (0 if none) is $< l$. So the answer is $\#\{i \in [l, r] : p_i < l\}$ — a 2D dominance count. Offline it would be a BIT sweep,
  but the encoding forces online answers: prefix versions of a count tree indexed by $p_i$, and `countLess(root[r], root[l-1], l)`.

<details><summary>Solution</summary>

$p_i$ from per-type occurrence lists: if position $i$ is the $j$-th occurrence (0-based) of its type, $p_i = \text{occ}[j - k]$ when $j \ge k$, else 0. Values of $p$ lie in $[0, n]$. $O((n + q)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct PersistentCount {
    int V; vector<int> L, R, cnt;
    PersistentCount(int V, int cap) : V(V) { L.reserve(cap); R.reserve(cap); cnt.reserve(cap); L.push_back(0); R.push_back(0); cnt.push_back(0); }
    int clone(int v) { L.push_back(L[v]); R.push_back(R[v]); cnt.push_back(cnt[v]); return int(L.size()) - 1; }
    int insert(int prev, int pos) {
        int root = clone(prev), v = root, lo = 0, hi = V - 1;
        cnt[v]++;
        while (lo < hi) {
            int m = (lo + hi) >> 1;
            if (pos <= m) { int c = clone(L[v]); L[v] = c; v = c; hi = m; }
            else          { int c = clone(R[v]); R[v] = c; v = c; lo = m + 1; }
            cnt[v]++;
        }
        return root;
    }
    int countLess(int u, int w, int x) const {
        int lo = 0, hi = V - 1, res = 0;
        if (x <= 0) return 0;
        if (x > hi) return cnt[u] - cnt[w];
        while (lo < hi) {
            int m = (lo + hi) >> 1;
            if (x - 1 <= m) { u = L[u]; w = L[w]; hi = m; }
            else { res += cnt[L[u]] - cnt[L[w]]; u = R[u]; w = R[w]; lo = m + 1; }
        }
        return res + cnt[u] - cnt[w];
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, k; cin >> n >> k;
    vector<int> a(n + 1);
    for (int i = 1; i <= n; i++) cin >> a[i];
    vector<vector<int>> occ(100001);
    vector<int> p(n + 1, 0);
    for (int i = 1; i <= n; i++) {
        auto& o = occ[a[i]];
        if ((int)o.size() >= k) p[i] = o[o.size() - k];
        o.push_back(i);
    }
    PersistentCount pc(n + 1, 1 + n * 20);
    vector<int> root(n + 1, 0);
    for (int i = 1; i <= n; i++) root[i] = pc.insert(root[i - 1], p[i]);
    int q; cin >> q;
    long long last = 0;
    while (q--) {
        long long x, y; cin >> x >> y;
        int l = int((x + last) % n) + 1, r = int((y + last) % n) + 1;
        if (l > r) swap(l, r);
        last = pc.countLess(root[r], root[l - 1], l);
        cout << last << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int V; static int[] L, R, cnt; static int size = 1;
    static int clone(int v) { L[size] = L[v]; R[size] = R[v]; cnt[size] = cnt[v]; return size++; }
    static int insert(int prev, int pos) {
        int root = clone(prev), v = root, lo = 0, hi = V - 1;
        cnt[v]++;
        while (lo < hi) {
            int m = (lo + hi) >> 1;
            if (pos <= m) { int c = clone(L[v]); L[v] = c; v = c; hi = m; }
            else          { int c = clone(R[v]); R[v] = c; v = c; lo = m + 1; }
            cnt[v]++;
        }
        return root;
    }
    static int countLess(int u, int w, int x) {
        int lo = 0, hi = V - 1, res = 0;
        if (x <= 0) return 0;
        if (x > hi) return cnt[u] - cnt[w];
        while (lo < hi) {
            int m = (lo + hi) >> 1;
            if (x - 1 <= m) { u = L[u]; w = L[w]; hi = m; }
            else { res += cnt[L[u]] - cnt[L[w]]; u = R[u]; w = R[w]; lo = m + 1; }
        }
        return res + cnt[u] - cnt[w];
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), k = in.nextInt();
        int[] a = new int[n + 1];
        for (int i = 1; i <= n; i++) a[i] = in.nextInt();
        int[] cntType = new int[100001], start = new int[100002], fill = new int[100001], occ = new int[n];
        for (int i = 1; i <= n; i++) cntType[a[i]]++;
        for (int t = 0; t <= 100000; t++) start[t + 1] = start[t] + cntType[t];   // CSR layout of occurrence lists
        int[] p = new int[n + 1];
        for (int i = 1; i <= n; i++) {
            int t = a[i], j = fill[t]++;
            occ[start[t] + j] = i;
            if (j >= k) p[i] = occ[start[t] + j - k];
        }
        V = n + 1;
        int cap = 1 + n * 20;
        L = new int[cap]; R = new int[cap]; cnt = new int[cap];
        int[] root = new int[n + 1];
        for (int i = 1; i <= n; i++) root[i] = insert(root[i - 1], p[i]);
        int q = in.nextInt();
        long last = 0;
        while (q-- > 0) {
            long x = in.nextInt(), y = in.nextInt();
            int l = (int) ((x + last) % n) + 1, r = (int) ((y + last) % n) + 1;
            if (l > r) { int t = l; l = r; r = t; }
            last = countLess(root[r], root[l - 1], l);
            out.println(last);
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

With $k = 1$ this is exactly "number of distinct values in $[l, r]$, online".

<!-- test
in:
6 2
1 1 1 2 2 2
5
1 6
4 3
1 1
2 6
2 6
out:
2
4
1
3
2
-->
<!-- test
in:
1 1
7
2
0 0
5 3
out:
1
1
-->

</details>

### Example 4 — Persistent Bookcase (offline version tree with undo)  ·  ★ 2200

- **Source:** [CF 707D · Persistent Bookcase](https://codeforces.com/problemset/problem/707/D) — 2200
- **Difficulty:** 2200
- **Problem:** a bookcase with $n \le 1000$ shelves of $m \le 1000$ positions, initially empty. $q \le 10^5$ operations: `1 i j` put a book at $(i, j)$ if empty; `2 i j` remove the book at $(i, j)$ if present; `3 i` invert shelf $i$ (books ↔ empty); `4 k` return to the state after operation $k$ ($k = 0$: initial). After each operation print the number of books.
- **Thinking from first principles:** real persistence is possible (persistent segment tree over $nm$ cells with lazy inversion), but every operation is known in advance.
  Operation $i$ is applied to version $i - 1$, except type 4 whose version *is* version $k$. That defines a tree of versions rooted at 0. DFS it: entering node $i$ applies operation $i$
  (remember whether it changed anything), record the count, visit children, undo when leaving. Each operation is $O(1)$ with a per-shelf "inverted" flag and count.
  The DFS depth can be $10^5$, so it must be iterative (Java, Windows).

<details><summary>Solution</summary>

State: `cell[i][j]` (raw bit), `inv[i]`, `cnt[i]`, `total`. Book present iff `cell ^ inv`. Undo of type 1/2 toggles the cell back if it was changed; undo of type 3 re-inverts.
Iterative DFS with an explicit stack of (node, phase). $O(nm + q)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m, q; cin >> n >> m >> q;
    vector<int> type(q + 1), I(q + 1), J(q + 1);
    vector<vector<int>> ch(q + 1);
    for (int t = 1; t <= q; t++) {
        cin >> type[t];
        if (type[t] == 1 || type[t] == 2) cin >> I[t] >> J[t];
        else cin >> I[t];
        ch[type[t] == 4 ? I[t] : t - 1].push_back(t);
    }
    vector<vector<char>> cell(n + 1, vector<char>(m + 1, 0));
    vector<char> inv(n + 1, 0), changed(q + 1, 0);
    vector<int> cnt(n + 1, 0), ans(q + 1, 0);
    int total = 0;
    auto apply = [&](int t) {                                   // returns whether the state changed
        int i = I[t], j = J[t];
        if (type[t] == 1 && !(cell[i][j] ^ inv[i])) { cell[i][j] ^= 1; cnt[i]++; total++; return true; }
        if (type[t] == 2 && (cell[i][j] ^ inv[i])) { cell[i][j] ^= 1; cnt[i]--; total--; return true; }
        if (type[t] == 3) { inv[i] ^= 1; total += m - 2 * cnt[i]; cnt[i] = m - cnt[i]; return true; }
        return false;
    };
    auto undo = [&](int t) {
        int i = I[t], j = J[t];
        if (type[t] == 1) { cell[i][j] ^= 1; cnt[i]--; total--; }
        else if (type[t] == 2) { cell[i][j] ^= 1; cnt[i]++; total++; }
        else if (type[t] == 3) { inv[i] ^= 1; total += m - 2 * cnt[i]; cnt[i] = m - cnt[i]; }
    };
    vector<pair<int, int>> st = {{0, 0}};                       // (version, next child index)
    while (!st.empty()) {
        auto& [v, idx] = st.back();
        if (idx < (int)ch[v].size()) {
            int c = ch[v][idx++];
            changed[c] = (type[c] != 4) && apply(c);
            ans[c] = total;
            st.push_back({c, 0});
        } else {
            if (v && changed[v]) undo(v);
            st.pop_back();
        }
    }
    for (int t = 1; t <= q; t++) cout << ans[t] << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), m = in.nextInt(), q = in.nextInt();
        int[] type = new int[q + 1], I = new int[q + 1], J = new int[q + 1], par = new int[q + 1];
        int[] head = new int[q + 1], nxt = new int[q + 1];
        Arrays.fill(head, -1);
        for (int t = 1; t <= q; t++) {
            type[t] = in.nextInt();
            if (type[t] == 1 || type[t] == 2) { I[t] = in.nextInt(); J[t] = in.nextInt(); }
            else I[t] = in.nextInt();
            par[t] = type[t] == 4 ? I[t] : t - 1;
        }
        for (int t = q; t >= 1; t--) { nxt[t] = head[par[t]]; head[par[t]] = t; }    // children in increasing order
        boolean[][] cell = new boolean[n + 1][m + 1];
        boolean[] inv = new boolean[n + 1], changed = new boolean[q + 1];
        int[] cnt = new int[n + 1], ans = new int[q + 1], stV = new int[q + 2], stE = new int[q + 2];
        int total = 0, sp = 0;
        stV[sp] = 0; stE[sp] = head[0]; sp++;
        while (sp > 0) {
            int v = stV[sp - 1], c = stE[sp - 1];
            if (c != -1) {
                stE[sp - 1] = nxt[c];
                int i = I[c], j = J[c]; boolean ch = false;
                if (type[c] == 1 && !(cell[i][j] ^ inv[i])) { cell[i][j] = !cell[i][j]; cnt[i]++; total++; ch = true; }
                else if (type[c] == 2 && (cell[i][j] ^ inv[i])) { cell[i][j] = !cell[i][j]; cnt[i]--; total--; ch = true; }
                else if (type[c] == 3) { inv[i] = !inv[i]; total += m - 2 * cnt[i]; cnt[i] = m - cnt[i]; ch = true; }
                changed[c] = ch; ans[c] = total;
                stV[sp] = c; stE[sp] = head[c]; sp++;
            } else {
                if (v != 0 && changed[v]) {
                    int i = I[v], j = J[v];
                    if (type[v] == 1) { cell[i][j] = !cell[i][j]; cnt[i]--; total--; }
                    else if (type[v] == 2) { cell[i][j] = !cell[i][j]; cnt[i]++; total++; }
                    else { inv[i] = !inv[i]; total += m - 2 * cnt[i]; cnt[i] = m - cnt[i]; }
                }
                sp--;
            }
        }
        for (int t = 1; t <= q; t++) out.println(ans[t]);
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
2 3 3
1 1 1
3 2
4 0
out:
1
4
0
-->
<!-- test
in:
4 2 6
3 2
2 2 2
3 3
3 2
2 2 2
3 2
out:
2
1
3
3
2
4
-->
<!-- test
in:
2 2 2
3 2
2 2 1
out:
2
1
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Never modify an existing node** in a persistent structure — not even "just the count". A single in-place write corrupts every version sharing it.
2. **Preallocate the pool** from the estimate $2n + q(\lceil\log_2 n\rceil + 1)$; dynamic growth (`vector` reallocation) is fine in C++ *if* you never hold references across a `push_back`, and fatal in Java if you write `L[v] = clone(...)` into an array that was just replaced.
3. **The null node 0 must be self-referential** (children 0, count 0) and must never be cloned *into* (always clone, then modify the clone).
4. **Versions are roots.** Store `root[t]` for every version you will query; "copy" is `root.push_back(root[k])` — $O(1)$.
5. **Prefix-version subtraction needs an additive (group) statistic**: counts and sums work; max/min do not subtract.
6. **Lockstep walks**: move *both* pointers down together; mixing a child of one with the other's sibling is a silent bug.
7. **Forced-online decoding**: compute with the *previous printed answer* (often 64-bit), and apply the problem's exact formula (mod, +1, swap).
8. **Memory in Java**: three `int` arrays of $4\cdot10^6$ = 48 MB; `long` sums add 32 MB. Check the limit; use `int` where values fit.
9. **Version-tree DFS depth** can equal $q$: iterative DFS (both languages on Windows, always in Java).
10. **Undo must restore exactly**: record whether the operation changed anything (Example 4's "place a book where one already is" is a no-op and must not be undone).
11. **Persistent + lazy**: use permanent tags or copy children on push; never push into shared children.
12. **Compression for value trees**: the tree range is the $V$ compressed values $0, 1, \dots, V-1$, one per distinct value; map back with the sorted array.

## 7. Going further (toward 2400–2600+)

- **Tree-path k-th**: versions along root-to-node paths, combine four roots ($u, v, \mathrm{lca}, \mathrm{parent}(\mathrm{lca})$); see [LCA](../10-Trees/02-lca-and-binary-lifting.md).
- **Majority / frequency queries**: [CF 840D · Destiny](https://codeforces.com/problemset/problem/840/D) — 2500 (descend only into children with count $> (r-l+1)/k$).
- **Persistent tree + binary search on the answer**: [CF 484E · Sign on Fence](https://codeforces.com/problemset/problem/484/E) — 2500 (versions by decreasing height; node = longest run of ones).
- **Persistent tree as an online 2D structure**: [CF 1771F · Hossam and Range Minimum Query](https://codeforces.com/problemset/problem/1771/F) — 2500 (xor hashing per value, descend for the first odd-count value).
- **Persistent DSU, persistent treap** (rope with history): 🧊; see [treaps](09-treaps-and-implicit-treaps.md).
- **Offline replacements**: parallel binary search and CDQ often replace persistence when queries are not forced online ([offline techniques](../16-IGM-Frontier/01-offline-techniques-cdq-parallel-binary-search.md)).

## 8. Practice ladder

**1900–2200**
- [ ] [CSES 1737 · Range Queries and Copies](https://cses.fi/problemset/task/1737)
- [ ] [CSES 1734 · Distinct Values Queries](https://cses.fi/problemset/task/1734) (solve it online with prefix versions)
- [ ] [CSES 1144 · Salary Queries](https://cses.fi/problemset/task/1144) (offline alternative practice)
- [ ] [CF 813E · Army Creation](https://codeforces.com/problemset/problem/813/E) — 2200
- [ ] [CF 707D · Persistent Bookcase](https://codeforces.com/problemset/problem/707/D) — 2200

**2200–2600**
- [ ] [CF 1000F · One Occurrence](https://codeforces.com/problemset/problem/1000/F) — 2400
- [ ] [CF 840D · Destiny](https://codeforces.com/problemset/problem/840/D) — 2500
- [ ] [CF 484E · Sign on Fence](https://codeforces.com/problemset/problem/484/E) — 2500
- [ ] [CF 1771F · Hossam and Range Minimum Query](https://codeforces.com/problemset/problem/1771/F) — 2500
- [ ] [CF 786C · Till I Collapse](https://codeforces.com/problemset/problem/786/C) — 2400

## 9. LeetCode / FAANG cross-reference

- [LC 1146 · Snapshot Array](https://leetcode.com/problems/snapshot-array/) — Medium — fat-node persistence: per index, a list of (snap id, value), binary search on read.
- [LC 981 · Time Based Key-Value Store](https://leetcode.com/problems/time-based-key-value-store/) — Medium — the same fat-node idea keyed by timestamp.
- [LC 2296 · Design a Text Editor](https://leetcode.com/problems/design-a-text-editor/) — Hard — not persistent, but the same "store only what changes" thinking (two stacks).

Rare in interviews: persistent segment trees are essentially never asked; fat-node versioning (snapshot arrays, versioned key-value stores) is the interview-level form and appears in system-design-flavoured coding rounds.

## 10. Self-check

1. Why does path copying keep old versions valid? How many nodes does one point update create?
2. Estimate the memory of a persistent sum tree for $n = q = 2\cdot10^5$ in Java.
3. Explain "version $r$ minus version $l-1$" and why it requires an additive statistic.
4. Write the k-th smallest descent on two versions.
5. How do you count distinct values in $[l, r]$ online? What changes for "at most $k$ copies"?
6. When is an offline version-tree DFS preferable to a persistent structure?
7. How do you combine lazy propagation with persistence?

<details><summary>Answers</summary>

1. Nodes are never modified; an update creates new copies of the $\lceil\log_2 n\rceil+1$ path nodes, which point to shared, unchanged subtrees; old roots still see only old nodes.
2. $\approx 2n + 19q \approx 4.2\cdot10^6$ nodes; two `int` arrays (34 MB) + one `long` array (34 MB) ≈ 67 MB.
3. Version $i$ is the multiset of $a_1..a_i$; counts of $a_{l..r}$ in any value range equal (count in version $r$) − (count in version $l-1$). Only invertible (group) statistics subtract.
4. At each level $c = \text{cnt}(L_r) - \text{cnt}(L_{l-1})$; if $k \le c$ go left in both, else $k \mathrel{-}= c$ and go right in both; the leaf is the answer.
5. Count $i\in[l,r]$ with $\text{prev}_i < l$ via prefix versions indexed by prev; for at most $k$ copies use the $k$-th previous occurrence instead of prev.
6. When all operations are known in advance (no forced-online decoding) and each operation has a cheap exact undo.
7. Permanent tags (no push, accumulate tags along the query path) or copying both children on every push.

</details>
