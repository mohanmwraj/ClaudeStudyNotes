# Cheat Sheet — 08 Data Structures

Revision only. Full derivations and tested programs: [Fenwick](../08-Data-Structures/01-fenwick-tree.md) · [segment tree](../08-Data-Structures/02-segment-tree-basics.md) · [lazy](../08-Data-Structures/03-lazy-propagation.md) · [advanced segment trees](../08-Data-Structures/04-segment-tree-advanced-descent-merging-beats.md) · [sparse table](../08-Data-Structures/05-sparse-table-and-rmq.md) · [DSU](../08-Data-Structures/06-dsu-and-variants.md) · [sqrt & Mo](../08-Data-Structures/07-sqrt-decomposition-and-mos-algorithm.md) · [persistent](../08-Data-Structures/08-persistent-data-structures.md) · [treaps](../08-Data-Structures/09-treaps-and-implicit-treaps.md) · [ordered sets & heaps](../08-Data-Structures/10-ordered-sets-pbds-and-heaps.md) · [ladder](../08-Data-Structures/problems.md)

## 1. Structures at a glance

| Structure | Update | Query | Memory | Needs |
|---|---|---|---|---|
| prefix sums | — (static) | $O(1)$ | $n$ | invertible op |
| Fenwick (BIT) | $O(\log n)$ point | $O(\log n)$ prefix; k-th by descent | $n+1$ | invertible op for ranges |
| segment tree (bottom-up) | $O(\log n)$ point | $O(\log n)$ range | $2n$ | monoid (associative + identity) |
| segment tree (recursive) | $O(\log n)$ | $O(\log n)$, descent, merging | $4n$ | monoid |
| lazy segment tree | $O(\log n)$ range | $O(\log n)$ range | $8n$ | maps distribute over combine, closed under $\circ$ |
| sparse table | — (static) | $O(1)$ | $n\log n$ | idempotent ($\min,\max,\gcd,\&,\lvert$) |
| disjoint sparse table | — | $O(1)$ | $n\log n$ | any associative op |
| DSU | $O(\alpha)$ union | $O(\alpha)$ find | $n$ | merges only |
| sqrt blocks | $O(\sqrt n)$ | $O(\sqrt n)$ | $n$ | per-block summary |
| Mo | — | $O((n+q)\sqrt n)$ total | $n + q$ | offline, $O(1)$ add/remove |
| persistent seg tree | $O(\log n)$, $\log n$ new nodes | $O(\log n)$ on any version | $2n + q\log n$ | immutable nodes |
| treap | $O(\log n)$ exp. | $O(\log n)$ exp. | $n$ | random priorities |
| `set`/`TreeMap` | $O(\log n)$ | $O(\log n)$ neighbours | $n$ | — |
| PBDS tree | $O(\log n)$ | `find_by_order`, `order_of_key` $O(\log n)$ | $n$ | GCC |
| binary heap | $O(\log n)$ | top $O(1)$ | $n$ | — |

## 2. Signal → structure

| Statement says / constraints | Reach for |
|---|---|
| point update + range sum/xor | BIT |
| point update + range min/max/gcd/custom | segment tree (design the node) |
| range add/assign/affine + range sum/min | lazy segment tree |
| no updates, $10^6$ RMQ, or RMQ inside binary search | sparse table |
| "first index where …", "k-th one", "first hotel with ≥ r" | descent (BIT or segment tree) |
| count pairs $i<j$ with $a_i$ vs $a_j$ condition | sort/sweep + BIT over compressed values |
| distinct values in ranges, offline | sort queries by $r$, BIT on last occurrences |
| … forced online | persistent tree indexed by `prev` |
| k-th smallest in a range | persistent count tree (online) / wavelet / parallel BS |
| groups merge, "same component?" | DSU; with deletions → reverse time |
| relations $x_u - x_v = w$, same/different | weighted / parity DSU |
| process each untouched index of $[l,r]$ once | next-pointer DSU |
| $a_i \bmod x$, $\sqrt{a_i}$, chmin on ranges | potential argument / beats |
| union area / max overlap of rectangles | sweep + cover-count tree (no push) |
| coordinates $\le 10^9$ online | dynamic segment tree (pool of nodes) |
| per-vertex subtree multiset stats | segment tree merging / small-to-large |
| offline range stats with $O(1)$ add/remove, $n,q\le 10^5$–$2\cdot10^5$ | Mo (odd–even order) |
| same with point updates | Mo with updates, $B=n^{2/3}$ |
| parameter $k$ or modulus $x$ making work $O(n/k)$ | threshold at $\sqrt n$ |
| cut/paste/reverse/rotate blocks of a sequence | implicit treap |
| k-th / rank in a dynamic set | PBDS (C++), BIT over compressed values or treap (Java) |
| stream median, top-k, merge k lists | heaps (two heaps for median) |
| delete from heap / decrease-key | lazy deletion (skip stale tops) |

## 3. Formulas to remember

- $\mathrm{low}(i) = i \,\&\, (-i)$; query: `i -= i & -i`; update: `i += i & -i`; $\le\lfloor\log_2 n\rfloor+1$ steps.
- Range add, range sum with two BITs: $S(x) = (x+1)\sum_{j\le x} d_j - \sum_{j\le x} j\,d_j$; add $v$ on $[l,r]$: $B_1{+}v@l,\ B_1{-}v@(r{+}1),\ B_2{+}lv@l,\ B_2{-}(r{+}1)v@(r{+}1)$.
- BIT k-th: `pos=0; for step=2^⌊log n⌋..1: if pos+step<=n && t[pos+step]<k: pos+=step, k-=t[pos]` → answer `pos+1`.
- Segment tree: $\le 4$ nodes visited per level, $\le 2\lceil\log_2 n\rceil$ canonical pieces; recursive array $4n$; bottom-up $2n$ (root is the whole array only if $n = 2^k$).
- Max subarray node: $\text{sum}=L.s+R.s$, $\text{pre}=\max(L.p, L.s+R.p)$, $\text{suf}=\max(R.f, R.s+L.f)$, $\text{best}=\max(L.b,R.b,L.f+R.p)$.
- Brackets node: $t=\min(o_L, c_R)$, $m=m_L+m_R+t$, $o=o_L+o_R-t$, $c=c_L+c_R-t$; answer $2m$.
- Lazy push: $t[c] \leftarrow \mathrm{lz}[v]\big(t[c]\big)$, $\mathrm{lz}[c]\leftarrow \mathrm{lz}[v]\circ\mathrm{lz}[c]$ (new tag outside).
- Affine: $(b_2,c_2)\circ(b_1,c_1)=(b_2b_1,\ b_2c_1+c_2)$; sum$'=b\cdot$sum$+c\cdot$len; add $=(1,v)$, assign $=(0,c)$.
- Assign+add tag: add after set $\Rightarrow$ set$(c+v)$; set after anything $\Rightarrow$ set$(c)$.
- AP tag $(A,D)$: sum $+= A\cdot\text{len} + D\binom{\text{len}}{2}$; right child gets $(A + D\cdot\text{len}_L, D)$.
- Range mod: $a\ge x \Rightarrow a \bmod x < a/2$; recurse only where $\max \ge x$.
- Beats (chmin $x$): stop if $m_1\le x$; tag if $m_2 < x < m_1$: sum $-= (m_1-x)\,c$; else recurse.
- Sparse table: $\mathrm{sp}[k][i]=\mathrm{sp}[k{-}1][i]\oplus\mathrm{sp}[k{-}1][i+2^{k-1}]$; query $k=\lfloor\log_2(r-l+1)\rfloor$: $\mathrm{sp}[k][l]\oplus\mathrm{sp}[k][r-2^k+1]$.
- Disjoint sparse table level: $h=\lfloor\log_2(l \oplus r)\rfloor$, answer $\text{suf}_h[l]\oplus\text{pre}_h[r]$.
- LCA $=$ min-depth vertex of the Euler tour between first occurrences; $\mathrm{dist}=d_u+d_v-2d_{\mathrm{lca}}$.
- DSU potential merge for $x_v - x_u = w$: attach $r_v$ under $r_u$ with pot $= w + P_u - P_v$; consistency check $P_v - P_u = w$.
- Mo: cost $O(n^2/B + qB)$, $B = n/\sqrt q$; Mo with updates: $B=n^{2/3}$, $O(n^{5/3})$.
- Persistent nodes: $\approx 2n + q(\lceil\log_2 n\rceil+1)$; range multiset $=$ version $r$ − version $l-1$; distinct in $[l,r]$ $=\#\{i\in[l,r]:\text{prev}_i<l\}$.
- Treap: $P(x_j \text{ anc. of } x_i)=1/(|i-j|+1)$, expected depth $<2\ln n$.
- Heapify $O(n)$: $\sum_h \lceil\frac{n}{2^{h+1}}\rceil h = n + O(\log^2 n)$. Lower median of $k$: index $(k-1)/2$.

## 4. Templates (C++ then Java)

### Fenwick (point add, prefix sum, k-th)

```cpp
struct BIT {
    int n, LOG = 1; vector<long long> t;
    BIT(int n) : n(n), t(n + 1) { while ((LOG << 1) <= n) LOG <<= 1; }
    void add(int i, long long v) { for (; i <= n; i += i & -i) t[i] += v; }
    long long sum(int i) { long long s = 0; for (; i > 0; i -= i & -i) s += t[i]; return s; }
    int kth(long long k) { int p = 0; for (int s = LOG; s; s >>= 1) if (p + s <= n && t[p + s] < k) k -= t[p += s]; return p + 1; }
};
```

```java
static class BIT {
    int n, log = 1; long[] t;
    BIT(int n) { this.n = n; t = new long[n + 1]; while ((log << 1) <= n) log <<= 1; }
    void add(int i, long v) { for (; i <= n; i += i & -i) t[i] += v; }
    long sum(int i) { long s = 0; for (; i > 0; i -= i & -i) s += t[i]; return s; }
    int kth(long k) { int p = 0; for (int s = log; s > 0; s >>= 1) if (p + s <= n && t[p + s] < k) { p += s; k -= t[p]; } return p + 1; }
}
```

### Bottom-up segment tree (any monoid; half-open)

```cpp
template <class T, class F> struct Seg {
    int n; T id; F op; vector<T> t;
    Seg(int n, T id, F op) : n(n), id(id), op(op), t(2 * n, id) {}
    void set(int p, T v) { for (t[p += n] = v; p >>= 1;) t[p] = op(t[2 * p], t[2 * p + 1]); }
    T query(int l, int r) { T a = id, b = id; for (l += n, r += n; l < r; l >>= 1, r >>= 1) { if (l & 1) a = op(a, t[l++]); if (r & 1) b = op(t[--r], b); } return op(a, b); }
};
```

```java
static class Seg {
    int n; long id; long[] t; java.util.function.LongBinaryOperator op;
    Seg(int n, long id, java.util.function.LongBinaryOperator op) { this.n = n; this.id = id; this.op = op; t = new long[2 * n]; Arrays.fill(t, id); }
    void set(int p, long v) { for (t[p += n] = v; (p >>= 1) > 0;) t[p] = op.applyAsLong(t[2 * p], t[2 * p + 1]); }
    long query(int l, int r) { long a = id, b = id; for (l += n, r += n; l < r; l >>= 1, r >>= 1) { if ((l & 1) == 1) a = op.applyAsLong(a, t[l++]); if ((r & 1) == 1) b = op.applyAsLong(t[--r], b); } return op.applyAsLong(a, b); }
}
```

### Lazy segment tree (range add, range sum; closed intervals, call with v=1, l=0, r=n-1)

```cpp
struct Lazy {
    vector<long long> s, z;
    Lazy(int n) : s(4 * n), z(4 * n) {}
    void app(int v, int len, long long x) { s[v] += x * len; z[v] += x; }
    void push(int v, int l, int m, int r) { if (z[v]) { app(2 * v, m - l + 1, z[v]); app(2 * v + 1, r - m, z[v]); z[v] = 0; } }
    void upd(int v, int l, int r, int a, int b, long long x) {
        if (b < l || r < a) return;
        if (a <= l && r <= b) { app(v, r - l + 1, x); return; }
        int m = (l + r) / 2; push(v, l, m, r);
        upd(2 * v, l, m, a, b, x); upd(2 * v + 1, m + 1, r, a, b, x); s[v] = s[2 * v] + s[2 * v + 1];
    }
    long long qry(int v, int l, int r, int a, int b) {
        if (b < l || r < a) return 0;
        if (a <= l && r <= b) return s[v];
        int m = (l + r) / 2; push(v, l, m, r);
        return qry(2 * v, l, m, a, b) + qry(2 * v + 1, m + 1, r, a, b);
    }
};
```

```java
static class Lazy {
    long[] s, z;
    Lazy(int n) { s = new long[4 * n]; z = new long[4 * n]; }
    void app(int v, int len, long x) { s[v] += x * len; z[v] += x; }
    void push(int v, int l, int m, int r) { if (z[v] != 0) { app(2 * v, m - l + 1, z[v]); app(2 * v + 1, r - m, z[v]); z[v] = 0; } }
    void upd(int v, int l, int r, int a, int b, long x) {
        if (b < l || r < a) return;
        if (a <= l && r <= b) { app(v, r - l + 1, x); return; }
        int m = (l + r) / 2; push(v, l, m, r);
        upd(2 * v, l, m, a, b, x); upd(2 * v + 1, m + 1, r, a, b, x); s[v] = s[2 * v] + s[2 * v + 1];
    }
    long qry(int v, int l, int r, int a, int b) {
        if (b < l || r < a) return 0;
        if (a <= l && r <= b) return s[v];
        int m = (l + r) / 2; push(v, l, m, r);
        return qry(2 * v, l, m, a, b) + qry(2 * v + 1, m + 1, r, a, b);
    }
}
```

### Sparse table (min) and DSU

```cpp
struct Sparse {
    vector<vector<int>> sp;
    Sparse(const vector<int>& a) {
        int n = a.size(), K = 1; while ((1 << K) <= n) K++;
        sp.assign(K, a);
        for (int k = 1; k < K; k++) for (int i = 0; i + (1 << k) <= n; i++) sp[k][i] = min(sp[k - 1][i], sp[k - 1][i + (1 << (k - 1))]);
    }
    int query(int l, int r) { int k = __lg(r - l + 1); return min(sp[k][l], sp[k][r - (1 << k) + 1]); }
};
struct DSU {
    vector<int> p, sz;
    DSU(int n) : p(n), sz(n, 1) { iota(p.begin(), p.end(), 0); }
    int find(int x) { while (p[x] != x) x = p[x] = p[p[x]]; return x; }
    bool unite(int a, int b) { a = find(a); b = find(b); if (a == b) return false; if (sz[a] < sz[b]) swap(a, b); p[b] = a; sz[a] += sz[b]; return true; }
};
```

```java
static class Sparse {
    int[][] sp;
    Sparse(int[] a) {
        int n = a.length, K = 1; while ((1 << K) <= n) K++;
        sp = new int[K][]; sp[0] = a.clone();
        for (int k = 1; k < K; k++) { sp[k] = new int[n - (1 << k) + 1]; for (int i = 0; i < sp[k].length; i++) sp[k][i] = Math.min(sp[k - 1][i], sp[k - 1][i + (1 << (k - 1))]); }
    }
    int query(int l, int r) { int k = 31 - Integer.numberOfLeadingZeros(r - l + 1); return Math.min(sp[k][l], sp[k][r - (1 << k) + 1]); }
}
static class DSU {
    int[] p, sz;
    DSU(int n) { p = new int[n]; sz = new int[n]; for (int i = 0; i < n; i++) { p[i] = i; sz[i] = 1; } }
    int find(int x) { while (p[x] != x) { p[x] = p[p[x]]; x = p[x]; } return x; }
    boolean unite(int a, int b) { a = find(a); b = find(b); if (a == b) return false; if (sz[a] < sz[b]) { int t = a; a = b; b = t; } p[b] = a; sz[a] += sz[b]; return true; }
}
```

### Persistent count tree (prefix versions, k-th in a range)

```cpp
struct PST {                                          // node 0 = null; root[i] = insert(root[i-1], val[i])
    int V; vector<int> L{0}, R{0}, c{0};
    PST(int V) : V(V) {}
    int clone(int v) { L.push_back(L[v]); R.push_back(R[v]); c.push_back(c[v]); return int(c.size()) - 1; }
    int insert(int prev, int pos) {
        int root = clone(prev), v = root, lo = 0, hi = V - 1; c[v]++;
        while (lo < hi) { int m = (lo + hi) / 2; if (pos <= m) { int x = clone(L[v]); L[v] = x; v = x; hi = m; } else { int x = clone(R[v]); R[v] = x; v = x; lo = m + 1; } c[v]++; }
        return root;
    }
    int kth(int u, int w, int k) { int lo = 0, hi = V - 1; while (lo < hi) { int m = (lo + hi) / 2, d = c[L[u]] - c[L[w]]; if (k <= d) { u = L[u]; w = L[w]; hi = m; } else { k -= d; u = R[u]; w = R[w]; lo = m + 1; } } return lo; }
};
```

```java
static class PST {
    int V, size = 1; int[] L, R, c;
    PST(int V, int cap) { this.V = V; L = new int[cap]; R = new int[cap]; c = new int[cap]; }
    int clone(int v) { L[size] = L[v]; R[size] = R[v]; c[size] = c[v]; return size++; }
    int insert(int prev, int pos) {
        int root = clone(prev), v = root, lo = 0, hi = V - 1; c[v]++;
        while (lo < hi) { int m = (lo + hi) / 2; if (pos <= m) { int x = clone(L[v]); L[v] = x; v = x; hi = m; } else { int x = clone(R[v]); R[v] = x; v = x; lo = m + 1; } c[v]++; }
        return root;
    }
    int kth(int u, int w, int k) { int lo = 0, hi = V - 1; while (lo < hi) { int m = (lo + hi) / 2, d = c[L[u]] - c[L[w]]; if (k <= d) { u = L[u]; w = L[w]; hi = m; } else { k -= d; u = R[u]; w = R[w]; lo = m + 1; } } return lo; }
}
```

### Implicit treap (split by count, merge = concatenation, reverse flag)

```cpp
mt19937 rng(chrono::steady_clock::now().time_since_epoch().count());
vector<int> Lt{0}, Rt{0}, Sz{0}; vector<unsigned> Pr{0}; vector<char> Rv{0};
int mk() { Lt.push_back(0); Rt.push_back(0); Sz.push_back(1); Pr.push_back(rng()); Rv.push_back(0); return int(Sz.size()) - 1; }
void push(int t) { if (t && Rv[t]) { swap(Lt[t], Rt[t]); Rv[Lt[t]] ^= 1; Rv[Rt[t]] ^= 1; Rv[t] = 0; Rv[0] = 0; } }
void pull(int t) { Sz[t] = 1 + Sz[Lt[t]] + Sz[Rt[t]]; }
void split(int t, int k, int& a, int& b) {            // a = first k elements
    if (!t) { a = b = 0; return; }
    push(t);
    if (Sz[Lt[t]] < k) { split(Rt[t], k - Sz[Lt[t]] - 1, Rt[t], b); a = t; } else { split(Lt[t], k, a, Lt[t]); b = t; }
    pull(t);
}
int merge(int a, int b) {
    if (!a || !b) return a | b;
    if (Pr[a] > Pr[b]) { push(a); Rt[a] = merge(Rt[a], b); pull(a); return a; }
    push(b); Lt[b] = merge(a, Lt[b]); pull(b); return b;
}
```

```java
static int[] Lt = new int[1 << 18], Rt = new int[1 << 18], Sz = new int[1 << 18], Pr = new int[1 << 18];
static boolean[] Rv = new boolean[1 << 18];
static int cnt = 1, sa, sb;                            // split results land in sa, sb: copy them at once
static Random rng = new Random(System.nanoTime());
static int mk() { Sz[cnt] = 1; Pr[cnt] = rng.nextInt(); return cnt++; }
static void push(int t) { if (t != 0 && Rv[t]) { int x = Lt[t]; Lt[t] = Rt[t]; Rt[t] = x; Rv[Lt[t]] ^= true; Rv[Rt[t]] ^= true; Rv[t] = false; Rv[0] = false; } }
static void pull(int t) { Sz[t] = 1 + Sz[Lt[t]] + Sz[Rt[t]]; }
static void split(int t, int k) {
    if (t == 0) { sa = sb = 0; return; }
    push(t);
    if (Sz[Lt[t]] < k) { split(Rt[t], k - Sz[Lt[t]] - 1); Rt[t] = sa; sa = t; } else { split(Lt[t], k); Lt[t] = sb; sb = t; }
    pull(t);
}
static int merge(int a, int b) {
    if (a == 0 || b == 0) return a | b;
    if (Pr[a] > Pr[b]) { push(a); Rt[a] = merge(Rt[a], b); pull(a); return a; }
    push(b); Lt[b] = merge(a, Lt[b]); pull(b); return b;
}
```

### PBDS order statistics, anti-hash, Mo order

```cpp
#include <ext/pb_ds/assoc_container.hpp>
#include <ext/pb_ds/tree_policy.hpp>
template <class T> using oset = __gnu_pbds::tree<T, __gnu_pbds::null_type, less<T>, __gnu_pbds::rb_tree_tag, __gnu_pbds::tree_order_statistics_node_update>;
// s.find_by_order(k) -> k-th (0-based); s.order_of_key(x) -> #keys < x; multiset: oset<pair<ll,int>>
struct SplitMix {
    size_t operator()(uint64_t x) const {
        static const uint64_t S = chrono::steady_clock::now().time_since_epoch().count();
        x += S + 0x9e3779b97f4a7c15ULL; x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ULL; x = (x ^ (x >> 27)) * 0x94d049bb133111ebULL;
        return x ^ (x >> 31);
    }
};
// unordered_map<long long, int, SplitMix> m;
bool moLess(pair<int,int> a, pair<int,int> b, int B) {            // odd-even order
    if (a.first / B != b.first / B) return a.first < b.first;
    return (a.first / B & 1) ? a.second > b.second : a.second < b.second;
}
```

```java
static final long SEED = System.nanoTime();
static long mix(long x) { x += SEED + 0x9e3779b97f4a7c15L; x = (x ^ (x >>> 30)) * 0xbf58476d1ce4e5b9L; x = (x ^ (x >>> 27)) * 0x94d049bb133111ebL; return x ^ (x >>> 31); }
// HashMap<Long,Integer>: always store mix(key). Java has no PBDS: use a BIT over compressed values or a treap.
static long moKey(int l, int r, int id, int B) {                  // sort these longs (shuffle first); needs r, id < 2^20
    long b = l / B, rr = (b & 1) == 1 ? (1 << 20) - 1 - r : r;
    return b << 40 | rr << 20 | id;
}
```

## 5. Top 10 mistakes

1. `add(0, v)` on a BIT (infinite loop) and forgetting `r + 1` can be $n + 1$.
2. Wrong identity (0 for min) or bottom-up `t[1]` read as the whole array when $n$ is not a power of two.
3. Combining non-commutative nodes in the wrong order (use left/right accumulators).
4. Lazy: no `push` in `query`; tag composed in the wrong order (assign vs add); not multiplying by length.
5. Sparse table for a non-idempotent op (sum/xor) — double counting.
6. Recursive DSU `find` / DFS without union by size on $10^5$-deep chains in Java (stack overflow). Use path halving and iterative DFS.
7. Mo: shrinking before expanding (negative counts); $B=\sqrt n$ when $q \ll n$; Java comparator sort of `Integer[]` (slow).
8. Persistent: modifying a shared node; pool too small; `L[v] = clone(..)` into a reallocated Java array.
9. `multiset::erase(x)` removing all copies; `prev(begin())`; Java `null` unboxing from `floorKey`.
10. Default `unordered_map` hash on Codeforces (hacked); `(a, b) -> b - a` comparators in Java (overflow).

## 6. Last-minute before contest

- [ ] Templates for BIT, bottom-up segment tree, lazy tree, sparse table, DSU are pasted, compiled and tested in **both** languages.
- [ ] Fast input (DataInputStream / `sync_with_stdio(false)`) and buffered output in every template; no `endl`, no `Scanner`.
- [ ] 64-bit sums everywhere a sum of $\ge 2\cdot10^4$ values of $10^5$ could appear; `1LL *` / `(long)` before multiplications.
- [ ] Java: shuffle before `Arrays.sort` on primitives; primitive arrays for nodes; iterative DFS on trees.
- [ ] `%` of a negative number is negative in both languages — normalise with `((a % m) + m) % m`; `v.size() - 1` underflows for an empty C++ vector — cast to `int` first.
- [ ] Decide offline vs online first — offline (sort by $r$, reverse time, Mo, compression) is usually shorter.
- [ ] For a new range query, write the node's fields and the combine on paper and check associativity + identity before coding.
- [ ] For range updates, write `apply` and `compose` on paper; if impossible, look for a potential argument.
- [ ] Estimate memory: $4n$ nodes × fields; persistent/dynamic pools $q\log C$.
- [ ] Stress-test against a brute force on tiny inputs whenever a data-structure solution gives WA.
