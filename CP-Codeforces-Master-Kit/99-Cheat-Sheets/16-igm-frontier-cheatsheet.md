# Cheat sheet — 16 IGM Frontier

Revision sheet for [16-IGM-Frontier](../16-IGM-Frontier/README.md). Full derivations, proofs and tested programs: [offline / CDQ / PBS](../16-IGM-Frontier/01-offline-techniques-cdq-parallel-binary-search.md) · [segment tree on time](../16-IGM-Frontier/02-segment-tree-on-time-and-dsu-rollback.md) · [link-cut trees](../16-IGM-Frontier/03-link-cut-trees.md) · [randomised & hashing](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md) · [bitsets](../16-IGM-Frontier/05-bitset-optimization.md) · [sqrt](../16-IGM-Frontier/06-advanced-sqrt-techniques.md) · [how GMs think](../16-IGM-Frontier/07-how-grandmasters-think.md) · [problems](../16-IGM-Frontier/problems.md).

## 1. Signal → technique

| Signal in the statement | Technique | Cost |
|---|---|---|
| many queries with a threshold ("edges $\le w$") | sort queries, add elements, DSU / Fenwick | $O((m+q)\log)$ |
| only deletions | reverse time | as insertions |
| three $\le$ conditions between pairs; dynamic 2D counting offline | CDQ divide and conquer | $O(n\log^2 n)$ |
| "first time each query's condition holds", monotone | parallel binary search | $O(\log K\,(KU + qC))$ |
| $k$-th smallest / threshold answers, many queries, maybe updates | overall binary search on values | $O((n+q)\log V\log n)$ |
| add/remove edges offline, ask connectivity / bipartiteness / component stats | segment tree on time + rollback DSU | $O(q\log q\log n)$ |
| "for each $i$, the answer without element $i$" | leave-one-out D&C + rollback | $O(m\log m \cdot \text{ins})$ |
| forest with link/cut and path queries, online | link-cut tree | $O(\log n)$ amortised |
| static shape, value updates, even reroot queries | HLD (not LCT) | $O(\log^2 n)$ |
| "subarray is a permutation / rearrangement / all counts even" | XOR or sum hashing with random labels | $O(1)$ per query |
| value with frequency $> 1/k$ in a range | random sampling + exact verification | $O(k\log(1/\varepsilon)\log n)$ |
| verify $AB = C$ / a polynomial identity | Freivalds / Schwartz–Zippel | $O(n^2)$ per round |
| boolean DP / closure / intersections with $n \le 2000$–$5000$ | bitset | cost $/64$ |
| sizes sum to $S$, feasibility of sums | group equal sizes, binary split, bitset | $O(S\sqrt S/64)$ |
| two regimes (small/large step, degree, set size, frequency) | heavy/light threshold $B = \sqrt{b/a}$ | $O(\sqrt{ab})$ per op |
| interleaved updates/queries, static structure easy | buffer $B$ updates, rebuild | $(q/B)R + qBc$ |
| total pattern length $L$ | $\le \sqrt{2L}$ distinct lengths | $O(\lvert T\rvert\sqrt L)$ |

## 2. Formulas and bounds

| Fact | Formula |
|---|---|
| CDQ recurrence | $T(n) = 2T(n/2) + O(n\log n) = O(n\log^2 n)$; $k$-D dominance $O(n\log^{k-1} n)$ |
| PBS rounds | $\lceil\log_2(K+1)\rceil$ |
| union-by-size depth | $\le \lfloor\log_2 n\rfloor$ (tree size doubles each time depth grows) |
| canonical segment-tree nodes of an interval | $\le 2\lceil\log_2 q\rceil$ |
| lifetime of edge added at $s$, removed at $e$ | alive on $[s, e-1]$ |
| parity DSU merge | $\text{par}[r_v] = c(u)\oplus c(v)\oplus 1$; odd cycle iff same root and $c(u) = c(v)$ |
| rectangle closure (CF 1140F) | $\sum_C \#x(C)\cdot\#y(C)$ |
| access lemma | splay cost $\le 3(r(t) - r(x)) + 1$, $r = \log_2 s$ |
| light edges on a root path | $\le \log_2 n$ |
| sum-hash collision mod $2^{64}$ | $\le 2^{\nu_2(\Delta)-64}$ |
| XOR hash | XOR of labels of values with odd count |
| birthday | $\Pr \approx 1 - e^{-k^2/2M}$; expected colliding pairs $\binom{k}{2}/M$ |
| amplification | $(1-f)^k \le e^{-fk}$ |
| Schwartz–Zippel | $\Pr[P(x) = 0] \le \deg P/\lvert S\rvert$ |
| colour coding | $\Pr[\text{colourful}] = k!/k^k \ge e^{-k}$ |
| distinct values with sum $S$ | $\le \sqrt{2S}$ |
| heavy objects (size $> B$) | $< S/B$ |
| degree orientation | out-degree $\le \sqrt{2m}$, triangles $O(m\sqrt m)$ |
| balancing | $\min_B(aB + b/B) = 2\sqrt{ab}$ at $B = \sqrt{b/a}$; within $2\times$ of $B^\ast$ costs $\le 1.25\times$ |
| $\lfloor n/k\rfloor$ | at most $2\sqrt n$ distinct values |
| bit-parallel LCS | $X = M_c \mid S$, $S \leftarrow X \,\&\, \lnot(X - ((S\ll1)\mid1))$, LCS $= \mathrm{popcount}(S)$ |

## 3. Constants

| Thing | Value |
|---|---|
| $\sqrt{5\cdot10^5}$, $\sqrt{2\cdot10^5}$, $\sqrt{10^5}$ | 707, 447, 316 |
| max distinct lengths $\sqrt{2L}$ for $L = 10^5$ | 447 |
| $n^2$ bits | $n = 2000$: 0.5 MB · $10^4$: 12.5 MB · $3\cdot10^4$: 112 MB · $5\cdot10^4$: 312 MB |
| word ops budget (C++, in cache) | $\approx 10^9$/s; $10^{10}/64 \approx 1.6\cdot10^8$ |
| safe hash modulus | $2^{61}-1$ (multiply with `__int128` / `Math.multiplyHigh`; $2^{61} \equiv 1$) |
| MinGW `RAND_MAX` | 32767 — never use `rand()` |

## 4. Templates (C++ then Java)

### 4.1 DSU with rollback (no path compression)

```cpp
struct RollbackDSU {
    vector<int> p, sz;
    vector<pair<int, int>> hist;         // (child root b, parent root a) of every successful union
    int comps;
    RollbackDSU(int n) : p(n), sz(n, 1), comps(n) { iota(p.begin(), p.end(), 0); }
    int find(int x) const { while (p[x] != x) x = p[x]; return x; }   // no path compression!
    bool unite(int a, int b) {
        a = find(a); b = find(b);
        if (a == b) return false;
        if (sz[a] < sz[b]) swap(a, b);   // union by size keeps depth <= log2 n
        p[b] = a; sz[a] += sz[b]; comps--;
        hist.push_back({b, a});
        return true;
    }
    int snapshot() const { return hist.size(); }
    void rollback(int snap) {            // undo unions in reverse order, O(1) each
        while ((int)hist.size() > snap) {
            auto [b, a] = hist.back(); hist.pop_back();
            p[b] = b; sz[a] -= sz[b]; comps++;
        }
    }
};
```

```java
static final class RollbackDSU {
    final int[] p, sz;
    int[] histB, histA;
    int top = 0, comps;
    RollbackDSU(int n) {
        p = new int[n]; sz = new int[n]; comps = n;
        histB = new int[n]; histA = new int[n];      // at most n - 1 unions can be live at once
        for (int i = 0; i < n; i++) { p[i] = i; sz[i] = 1; }
    }
    int find(int x) { while (p[x] != x) x = p[x]; return x; }    // no path compression
    boolean unite(int a, int b) {
        a = find(a); b = find(b);
        if (a == b) return false;
        if (sz[a] < sz[b]) { int t = a; a = b; b = t; }
        p[b] = a; sz[a] += sz[b]; comps--;
        histB[top] = b; histA[top] = a; top++;
        return true;
    }
    int snapshot() { return top; }
    void rollback(int snap) {
        while (top > snap) { top--; int b = histB[top], a = histA[top]; p[b] = b; sz[a] -= sz[b]; comps++; }
    }
}
```

Segment tree on time and parallel binary search skeletons:

```text
SEGMENT TREE ON TIME                         PARALLEL BINARY SEARCH
insert edge alive on [s,e] into O(log q)     lo[q]=1, hi[q]=K+1
  canonical nodes                            while some lo<hi:
dfs(node,l,r):                                 bucket q by mid=(lo+hi)/2; reset structure
  snap = dsu.snapshot()                        for t in 1..K: apply event t
  apply node's edges                                for q in bucket[t]: P_q ? hi=t : lo=t+1
  leaf ? answer : dfs(left), dfs(right)
  dsu.rollback(snap)

CDQ (3D dominance, points sorted by (a,b,c), duplicates merged)
cdq(l,r): if r-l<=1 return; m=(l+r)/2; cdq(l,m); cdq(m,r)
  sweep right half by b; insert left points with b<=b_j into Fenwick on c; add sum(c_j)
  undo Fenwick; merge halves by b (stable)
```

### 4.2 Link-cut tree (path sums, reroot)

```cpp
// Link-cut tree over vertices 1..n (0 is the null node), path sums, makeRoot with lazy reversal.
struct LCT {
    vector<array<int, 2>> ch;
    vector<int> fa, stk;
    vector<char> rev;
    vector<ll> val, sum;
    LCT(int n) : ch(n + 1, {0, 0}), fa(n + 1, 0), rev(n + 1, 0), val(n + 1, 0), sum(n + 1, 0) {}
    // x is the root of its splay tree iff its parent pointer is a path-parent (or null)
    bool isRoot(int x) const { int f = fa[x]; return f == 0 || (ch[f][0] != x && ch[f][1] != x); }
    void pull(int x) { sum[x] = sum[ch[x][0]] + sum[ch[x][1]] + val[x]; }
    void flip(int x) { swap(ch[x][0], ch[x][1]); rev[x] ^= 1; }
    void push(int x) {
        if (!rev[x]) return;
        if (ch[x][0]) flip(ch[x][0]);
        if (ch[x][1]) flip(ch[x][1]);
        rev[x] = 0;
    }
    void rotate(int x) {
        int y = fa[x], z = fa[y], k = ch[y][1] == x;
        if (!isRoot(y)) ch[z][ch[z][1] == y] = x;   // must test before fa[y] changes
        fa[x] = z;
        ch[y][k] = ch[x][k ^ 1];
        if (ch[x][k ^ 1]) fa[ch[x][k ^ 1]] = y;
        ch[x][k ^ 1] = y;
        fa[y] = x;
        pull(y);
        pull(x);
    }
    void splay(int x) {
        stk.clear();
        for (int y = x;; y = fa[y]) { stk.push_back(y); if (isRoot(y)) break; }
        while (!stk.empty()) { push(stk.back()); stk.pop_back(); }   // push lazies top-down first
        while (!isRoot(x)) {
            int y = fa[x], z = fa[y];
            if (!isRoot(y)) rotate((ch[y][1] == x) == (ch[z][1] == y) ? y : x);   // zig-zig vs zig-zag
            rotate(x);
        }
    }
    // after access(x): the root-to-x path is one splay tree, x has no preferred child
    void access(int x) {
        for (int last = 0; x; last = x, x = fa[x]) { splay(x); ch[x][1] = last; pull(x); }
    }
    void makeRoot(int x) { access(x); splay(x); flip(x); }
    int findRoot(int x) {
        access(x); splay(x);
        while (true) { push(x); if (!ch[x][0]) break; x = ch[x][0]; }
        splay(x);                                   // keeps the amortised bound
        return x;
    }
    bool connected(int u, int v) { return findRoot(u) == findRoot(v); }
    bool link(int u, int v) {
        makeRoot(u);
        if (findRoot(v) == u) return false;         // already in one tree
        access(v); splay(v);                        // v becomes the root of its auxiliary tree
        fa[u] = v;
        return true;
    }
    bool cut(int u, int v) {
        makeRoot(u);
        if (findRoot(v) != u || fa[v] != u || ch[v][0]) return false;   // u-v is not an edge
        fa[v] = 0; ch[u][1] = 0; pull(u);
        return true;
    }
    ll pathSum(int u, int v) { makeRoot(u); access(v); splay(v); return sum[v]; }
    void setVal(int x, ll w) { splay(x); val[x] = w; pull(x); }
};
```

```java
static final class LCT {
    final int[] lc, rc, fa, stk;
    final boolean[] rev;
    final long[] val, sum;
    LCT(int n) {
        lc = new int[n + 1]; rc = new int[n + 1]; fa = new int[n + 1]; stk = new int[n + 1];
        rev = new boolean[n + 1]; val = new long[n + 1]; sum = new long[n + 1];
    }
    boolean isRoot(int x) { int f = fa[x]; return f == 0 || (lc[f] != x && rc[f] != x); }
    void pull(int x) { sum[x] = sum[lc[x]] + sum[rc[x]] + val[x]; }
    void flip(int x) { int t = lc[x]; lc[x] = rc[x]; rc[x] = t; rev[x] = !rev[x]; }
    void push(int x) {
        if (!rev[x]) return;
        if (lc[x] != 0) flip(lc[x]);
        if (rc[x] != 0) flip(rc[x]);
        rev[x] = false;
    }
    void rotate(int x) {
        int y = fa[x], z = fa[y];
        boolean right = rc[y] == x;
        if (!isRoot(y)) { if (lc[z] == y) lc[z] = x; else rc[z] = x; }
        fa[x] = z;
        if (right) {
            rc[y] = lc[x]; if (lc[x] != 0) fa[lc[x]] = y;
            lc[x] = y;
        } else {
            lc[y] = rc[x]; if (rc[x] != 0) fa[rc[x]] = y;
            rc[x] = y;
        }
        fa[y] = x;
        pull(y);
        pull(x);
    }
    void splay(int x) {
        int top = 0;
        for (int y = x;; y = fa[y]) { stk[top++] = y; if (isRoot(y)) break; }
        while (top > 0) push(stk[--top]);
        while (!isRoot(x)) {
            int y = fa[x], z = fa[y];
            if (!isRoot(y)) rotate(((rc[y] == x) == (rc[z] == y)) ? y : x);
            rotate(x);
        }
    }
    void access(int x) {
        for (int last = 0; x != 0; last = x, x = fa[x]) { splay(x); rc[x] = last; pull(x); }
    }
    void makeRoot(int x) { access(x); splay(x); flip(x); }
    int findRoot(int x) {
        access(x); splay(x);
        while (true) { push(x); if (lc[x] == 0) break; x = lc[x]; }
        splay(x);
        return x;
    }
    boolean connected(int u, int v) { return findRoot(u) == findRoot(v); }
    boolean link(int u, int v) {
        makeRoot(u);
        if (findRoot(v) == u) return false;
        access(v); splay(v);
        fa[u] = v;
        return true;
    }
    boolean cut(int u, int v) {
        makeRoot(u);
        if (findRoot(v) != u || fa[v] != u || lc[v] != 0) return false;
        fa[v] = 0; rc[u] = 0; pull(u);
        return true;
    }
    long pathSum(int u, int v) { makeRoot(u); access(v); splay(v); return sum[v]; }
    void setVal(int x, long w) { splay(x); val[x] = w; pull(x); }
}
```

### 4.3 Random numbers and safe hashing

```cpp
mt19937_64 rng(chrono::steady_clock::now().time_since_epoch().count());   // never a fixed seed
struct SafeHash {                                   // unordered_map<ll, int, SafeHash>
    static ull splitmix64(ull x) {
        x += 0x9e3779b97f4a7c15ULL;
        x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ULL;
        x = (x ^ (x >> 27)) * 0x94d049bb133111ebULL;
        return x ^ (x >> 31);
    }
    size_t operator()(ull x) const {
        static const ull OFFSET = chrono::steady_clock::now().time_since_epoch().count();
        return splitmix64(x + OFFSET);
    }
};
```

```java
static final SplittableRandom RNG = new SplittableRandom(System.nanoTime() ^ 0x9E3779B97F4A7C15L);
static void shuffleSort(int[] a) {                // never Arrays.sort(int[]) on hackable data unshuffled
    for (int i = a.length - 1; i > 0; i--) { int j = RNG.nextInt(i + 1); int t = a[i]; a[i] = a[j]; a[j] = t; }
    Arrays.sort(a);
}
static long splitmix64(long x) {                  // mix keys before using them in a HashMap / own table
    x += 0x9E3779B97F4A7C15L;
    x = (x ^ (x >>> 30)) * 0xBF58476D1CE4E5B9L;
    x = (x ^ (x >>> 27)) * 0x94D049BB133111EBL;
    return x ^ (x >>> 31);
}
```

### 4.4 XOR hashing, triangles, bitset shift-or

```cpp
// XOR hashing: H[i] = r(a_1) ^ ... ^ r(a_i); P[k] = r(1) ^ ... ^ r(k).
// a[l..r] (1-based) is a permutation of 1..len  <=>  (H[r] ^ H[l-1]) == P[r-l+1]   (w.h.p.)
// all counts in a[l..r] are even                  <=>  (H[r] ^ H[l-1]) == 0
pair<vector<ull>, vector<ull>> xorHashes(const vector<int>& a /* 1-based, values in [1, n] */) {
    static mt19937_64 rng(chrono::steady_clock::now().time_since_epoch().count());
    int n = a.size() - 1;
    vector<ull> r(n + 1), H(n + 1, 0), P(n + 1, 0);
    for (int v = 1; v <= n; v++) { r[v] = rng(); P[v] = P[v - 1] ^ r[v]; }
    for (int i = 1; i <= n; i++) H[i] = H[i - 1] ^ r[a[i]];
    return {H, P};
}

// Triangles in O(m sqrt m): orient low (deg, id) -> high; out-degrees <= sqrt(2m). Edges must be distinct.
long long countTriangles(int n, const vector<pair<int, int>>& edges /* 0-based, no loops/duplicates */) {
    vector<int> deg(n, 0);
    for (auto [u, v] : edges) { deg[u]++; deg[v]++; }
    vector<vector<int>> out(n);
    for (auto [u, v] : edges) {
        bool uFirst = deg[u] != deg[v] ? deg[u] < deg[v] : u < v;
        if (uFirst) out[u].push_back(v); else out[v].push_back(u);
    }
    vector<int> mark(n, -1);
    long long t = 0;
    for (int u = 0; u < n; u++) {
        for (int v : out[u]) mark[v] = u;
        for (int v : out[u]) for (int w : out[v]) t += mark[w] == u;
    }
    return t;
}
```

```java
// XOR hashing: returns {H, P} with H[i] = r(a_1)^...^r(a_i), P[k] = r(1)^...^r(k); a is 1-based, values in [1, n].
static long[][] xorHashes(int[] a) {
    SplittableRandom rng = new SplittableRandom(System.nanoTime());
    int n = a.length - 1;
    long[] r = new long[n + 1], H = new long[n + 1], P = new long[n + 1];
    for (int v = 1; v <= n; v++) { r[v] = rng.nextLong(); P[v] = P[v - 1] ^ r[v]; }
    for (int i = 1; i <= n; i++) H[i] = H[i - 1] ^ r[a[i]];
    return new long[][]{H, P};
}

// Triangles in O(m sqrt m); eu/ev are 0-based distinct edges without loops.
static long countTriangles(int n, int[] eu, int[] ev) {
    int m = eu.length;
    int[] deg = new int[n], start = new int[n + 1], from = new int[m], to = new int[m];
    for (int i = 0; i < m; i++) { deg[eu[i]]++; deg[ev[i]]++; }
    for (int i = 0; i < m; i++) {
        int u = eu[i], v = ev[i];
        boolean uFirst = deg[u] != deg[v] ? deg[u] < deg[v] : u < v;
        from[i] = uFirst ? u : v; to[i] = uFirst ? v : u;
        start[from[i] + 1]++;
    }
    for (int i = 0; i < n; i++) start[i + 1] += start[i];
    int[] adj = new int[m], fill = Arrays.copyOf(start, n + 1), mark = new int[n];
    for (int i = 0; i < m; i++) adj[fill[from[i]]++] = to[i];
    Arrays.fill(mark, -1);
    long t = 0;
    for (int u = 0; u < n; u++) {
        for (int p = start[u]; p < start[u + 1]; p++) mark[adj[p]] = u;
        for (int p = start[u]; p < start[u + 1]; p++)
            for (int q = start[adj[p]]; q < start[adj[p] + 1]; q++) if (mark[adj[q]] == u) t++;
    }
    return t;
}

// in-place b |= b << s for a bitset stored in long[] (top word first so each item is used once)
static void orShiftLeft(long[] w, int s) {
    int ws = s >>> 6, bs = s & 63;
    for (int i = w.length - 1; i >= ws; i--) {
        long v = w[i - ws] << bs;
        if (bs != 0 && i - ws - 1 >= 0) v |= w[i - ws - 1] >>> (64 - bs);
        w[i] |= v;
    }
}
```

C++ bitset one-liners: `b |= b << w` (subset sum), `(r[i] & r[j]).count()` (common neighbours), `if (r[i][k]) r[i] |= r[k]` (Warshall), `b._Find_next(i)` (GCC only).

## 5. Top 10 mistakes

1. Path compression in a rollback DSU — wrong answers or TLE after undo.
2. Lifetime off by one: an edge removed by operation $e$ is alive only until $e-1$.
3. CDQ without merging duplicate points, or with an unstable merge / wrong tie order.
4. Clearing the Fenwick tree with `memset` inside CDQ instead of undoing — $O(n^2)$.
5. Forgetting to reset the structure between parallel-binary-search rounds.
6. LCT: changing `fa` before testing `isRoot(y)` in `rotate`; not pushing reversal tags top-down before splaying; walking down without splaying at the end.
7. Fixed RNG seed, `rand()` on Windows, default `unordered_map` hash, or `Arrays.sort(int[])` on hackable input.
8. XOR hashing where counts matter (1 vs 3 copies) — use sum hashing plus a length check.
9. A single $\sim10^9$ modulus for many hashes in a set — birthday collisions.
10. A threshold copied from memory instead of derived — the per-object cost (e.g. $O(\log n)$ LCA) moves the optimum.

## 6. Last-minute before the contest

- Rollback DSU and LCT templates compile and pass the tests in the topic files.
- Every random generator in the template is seeded from the clock; `SafeHash` / shuffled sorts are in place.
- For each square-root idea, write the two costs and solve for $B$ before coding.
- For bitset ideas: compute (boolean cost)/64 and the memory $n^2/8$ bytes first.
- For offline ideas: check that the problem is not forced-online (answers XOR-ed into the next query).
- Stuck? Run the heuristics of [07](../16-IGM-Frontier/07-how-grandmasters-think.md): canonical form, brute force small cases, extremal/last element, fix one parameter, monotonicity, bounds, invariants, special cases, contribution, read the constraints.
