# Segment Tree Basics

> **Band:** 🔵 1600–2000 · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [Fenwick tree](01-fenwick-tree.md), [recursion](../01-Foundations/04-recursion-brute-force-and-backtracking.md), [prefix sums](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md)
> **You can say you know this when:** given a new range query, you can design the node (which fields, how two children combine, what the identity is) and prove the combine is associative; and you can write both the recursive and the bottom-up iterative tree from memory, knowing when each is the better choice.

## 1. First principles — why this works

**The problem a Fenwick tree cannot solve.** Range minimum with point assignments. A BIT answers $[l, r]$ as
$\text{prefix}(r) - \text{prefix}(l-1)$, and $\min$ has no "minus". We need a structure that answers a range directly as a
combination of a few precomputed pieces, without subtracting anything.

**Divide and conquer, precomputed.** If $f([l, r]) = f([l, m]) \oplus f([m+1, r])$ for some operation $\oplus$, then a range answer
can be assembled from answers of sub-ranges. Precompute $f$ on a *fixed* hierarchy of segments: the whole array; its two halves;
their halves; …; single elements. That hierarchy is a binary tree of $2n - 1$ nodes and height $\lceil \log_2 n \rceil$.

- **Update** of $a_p$: exactly one node per level contains $p$; recompute those $\lceil \log_2 n\rceil + 1$ nodes bottom-up.
- **Query** $[l, r]$: walk from the root; a node fully inside $[l,r]$ is used as is, a node disjoint from it is ignored, a node
  partially overlapping is split into its children.

**Why a query visits at most 4 nodes per level.** Call a visited node *partial* if it overlaps $[l,r]$ but is not inside it.
A partial node must contain the boundary $l$ or the boundary $r$ (otherwise it would be inside or disjoint), and on one level the
nodes are disjoint, so **at most 2 partial nodes per level**. Only partial nodes recurse, each into 2 children, so at most 4 nodes are
visited on the next level. Total $\le 4\lceil\log_2 n\rceil + 1 = O(\log n)$, and at most $2$ fully-covered nodes per level are
actually combined, so a range is the disjoint union of $\le 2\lceil\log_2 n\rceil$ canonical nodes.

**The monoid abstraction — what $\oplus$ must satisfy.** The tree combines canonical pieces in a bracketing *it* chooses, not the
bracketing of the left-to-right formula. That is legal exactly when $\oplus$ is **associative**: $(x \oplus y) \oplus z = x \oplus (y \oplus z)$.
For empty ranges and for initialising accumulators we need an **identity** $e$ with $e \oplus x = x \oplus e = x$. A set with an
associative operation and an identity is a *monoid*. Commutativity is **not** required, as long as pieces are combined in
left-to-right order. Examples:

| Monoid | $\oplus$ | $e$ | Commutative? |
|---|---|---|---|
| sums | $+$ | $0$ | yes |
| min / max | $\min$ / $\max$ | $+\infty$ / $-\infty$ | yes |
| gcd | $\gcd$ | $0$ | yes |
| affine maps $x \mapsto ax+b$ | composition | $x \mapsto x$ | **no** |
| $k\times k$ matrices | product | $I$ | **no** |
| strings / hashes | concatenation | empty | **no** |
| "max subarray" node (below) | formula | all zeros (if empty allowed) | **no** |

**Designing the node — the single most important skill.** Ask: *what do I need to know about two adjacent segments to compute
the answer for their concatenation?* If the answer itself is not enough, add fields until the set of fields is closed under
concatenation. Three canonical designs:

1. **Maximum subarray sum.** For $L\cdot R$, the best subarray is inside $L$, inside $R$, or crosses the boundary — and the
   crossing one is a suffix of $L$ plus a prefix of $R$. So we need best suffix and best prefix; to compute the prefix of $L\cdot R$
   (either inside $L$, or all of $L$ plus a prefix of $R$) we also need the total. Four fields, closed:
   $$\text{sum} = L.\text{sum}+R.\text{sum},\quad \text{pre} = \max(L.\text{pre},\, L.\text{sum}+R.\text{pre}),\quad \text{suf} = \max(R.\text{suf},\, R.\text{sum}+L.\text{suf}),$$
   $$\text{best} = \max(L.\text{best},\, R.\text{best},\, L.\text{suf}+R.\text{pre}).$$
2. **Number of maximal blocks of 1s** in a 0/1 range. Blocks of $L$ and $R$ add up, except that a block ending at $L$'s right
   end and one starting at $R$'s left end merge: fields $(\text{cnt}, \text{leftBit}, \text{rightBit})$,
   $\text{cnt} = L.\text{cnt} + R.\text{cnt} - [L.\text{rightBit} \wedge R.\text{leftBit}]$.
3. **Bracket matching** (longest correct bracket *subsequence*). Greedily matching inside each half leaves $L$ with $o_L$
   unmatched `(` and $c_L$ unmatched `)` in the shape `)))(((`, same for $R$. Concatenating, $L$'s open brackets meet $R$'s close
   brackets: $t = \min(o_L, c_R)$ new pairs, giving
   $m = m_L + m_R + t,\ o = o_L + o_R - t,\ c = c_L + c_R - t$. Greedy matching is optimal (an exchange argument: any unmatched
   `(` before a `)` could be matched), so $2m$ is the answer.

Associativity of a designed node is proved by observing that each field is the *true* statistic of the concatenated segment, and
the true statistic of $X\cdot Y\cdot Z$ does not depend on bracketing.

**Build in $O(n)$.** Each internal node is computed once from its two children: $n - 1$ combines. Inserting elements one by one
would cost $O(n \log n)$.

**Two layouts.**

- *Recursive, heap-indexed*: root 1, children $2v$ and $2v+1$, node $v$ covers $[l, r]$ passed down as arguments. Height is
  $h = \lceil\log_2 n\rceil$, indices are $< 2^{h+1} < 4n$, hence the famous `4n` array. Flexible: easy to add lazy tags
  ([lazy propagation](03-lazy-propagation.md)), descend ([advanced](04-segment-tree-advanced-descent-merging-beats.md)), or make sparse.
- *Iterative, bottom-up*: leaves at `t[n..2n-1]`, parent of $i$ is $i/2$, exactly $2n$ cells and no recursion. Query $[l, r)$:
  move $l$ and $r$ up level by level; when $l$ is a right child, its node is the leftmost piece not yet taken (take it, step right);
  when $r$ is a right child, `r-1` is the rightmost piece not yet taken. At most 2 nodes per level, and pieces taken from the left are
  appended to a **left accumulator** while pieces from the right are prepended to a **right accumulator**, so non-commutative
  monoids work. 2–3× faster than the recursive version.

  For $n$ not a power of two the bottom-up layout is a forest glued together: some internal nodes (including possibly the root `t[1]`)
  cover a *wrapped* set of leaves. The query loop never uses such nodes, so queries are correct for any $n$ — but **`t[1]` is not
  the whole array** unless $n$ is a power of two. For "answer for the whole array" use `query(0, n)` or pad $n$ to a power of two.

## 2. Formulas, definitions and identities

| Quantity | Value | Why |
|---|---|---|
| nodes in a full tree | $2n - 1$ | each internal node has two children, $n$ leaves |
| height | $\lceil \log_2 n \rceil$ | halving until size 1 |
| recursive array size | $< 2^{\lceil\log_2 n\rceil + 1} \le 4n$ | max heap index on the last level |
| iterative array size | $2n$ | leaves $[n, 2n)$, internals $[1, n)$ |
| nodes visited per query (recursive) | $\le 4$ per level, $\le 4\lceil\log_2 n\rceil + 1$ | $\le 2$ partial nodes per level |
| canonical pieces per query | $\le 2\lceil\log_2 n\rceil$ | $\le 2$ taken per level |
| point update | $\lceil\log_2 n\rceil + 1$ recomputations | one node per level |
| build | $n - 1$ combines, $O(n)$ | |

Monoid laws: $(x\oplus y)\oplus z = x\oplus(y\oplus z)$; $e\oplus x = x\oplus e = x$.
Affine composition ("apply $f$ then $g$"): $(a_1, b_1) \oplus (a_2, b_2) = (a_2 a_1,\ a_2 b_1 + b_2)$, identity $(1, 0)$.
Max-subarray, block-count and bracket combines: see §1.

## 3. Implementation (C++ and Java)

### 3.1 Recursive tree (range min, point assign)

The recursive skeleton every other variant extends. 0-indexed, closed intervals `[ql, qr]`. To change the monoid, change `op` and `ID`.

```cpp
struct SegTreeRec {
    int n; vector<long long> t;
    static constexpr long long ID = LLONG_MAX;                 // identity of min
    static long long op(long long a, long long b) { return min(a, b); }
    explicit SegTreeRec(const vector<long long>& a) : n(a.size()), t(4 * max<size_t>(1, a.size()), ID) { if (n) build(1, 0, n - 1, a); }
    void build(int v, int l, int r, const vector<long long>& a) {
        if (l == r) { t[v] = a[l]; return; }
        int m = (l + r) >> 1;
        build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a);
        t[v] = op(t[2 * v], t[2 * v + 1]);
    }
    void update(int v, int l, int r, int pos, long long val) {
        if (l == r) { t[v] = val; return; }
        int m = (l + r) >> 1;
        if (pos <= m) update(2 * v, l, m, pos, val); else update(2 * v + 1, m + 1, r, pos, val);
        t[v] = op(t[2 * v], t[2 * v + 1]);
    }
    long long query(int v, int l, int r, int ql, int qr) const {
        if (qr < l || r < ql) return ID;                         // disjoint
        if (ql <= l && r <= qr) return t[v];                     // fully covered
        int m = (l + r) >> 1;
        return op(query(2 * v, l, m, ql, qr), query(2 * v + 1, m + 1, r, ql, qr));
    }
    void update(int pos, long long val) { update(1, 0, n - 1, pos, val); }
    long long query(int l, int r) const { return query(1, 0, n - 1, l, r); }
};
```

```java
static class SegTreeRec {
    final int n; final long[] t;
    static final long ID = Long.MAX_VALUE;                      // identity of min
    static long op(long a, long b) { return Math.min(a, b); }
    SegTreeRec(long[] a) { n = a.length; t = new long[4 * Math.max(1, n)]; Arrays.fill(t, ID); if (n > 0) build(1, 0, n - 1, a); }
    void build(int v, int l, int r, long[] a) {
        if (l == r) { t[v] = a[l]; return; }
        int m = (l + r) >> 1;
        build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a);
        t[v] = op(t[2 * v], t[2 * v + 1]);
    }
    void update(int v, int l, int r, int pos, long val) {
        if (l == r) { t[v] = val; return; }
        int m = (l + r) >> 1;
        if (pos <= m) update(2 * v, l, m, pos, val); else update(2 * v + 1, m + 1, r, pos, val);
        t[v] = op(t[2 * v], t[2 * v + 1]);
    }
    long query(int v, int l, int r, int ql, int qr) {
        if (qr < l || r < ql) return ID;
        if (ql <= l && r <= qr) return t[v];
        int m = (l + r) >> 1;
        return op(query(2 * v, l, m, ql, qr), query(2 * v + 1, m + 1, r, ql, qr));
    }
    void update(int pos, long val) { update(1, 0, n - 1, pos, val); }
    long query(int l, int r) { return query(1, 0, n - 1, l, r); }
}
```

### 3.2 Iterative bottom-up tree (any monoid, half-open queries)

Generic in C++ (any `T` and associative `op`); in Java a `long` version with a `LongBinaryOperator`. Set leaves `t[n + i]`, then call `build()`.

```cpp
template <class T, class Op>
struct SegTree {
    int n; vector<T> t; T id; Op op;
    SegTree(int n, T id, Op op) : n(n), t(2 * n, id), id(id), op(op) {}
    void build() { for (int i = n - 1; i > 0; i--) t[i] = op(t[2 * i], t[2 * i + 1]); }
    void set(int p, T v) { for (t[p += n] = v; p >>= 1; ) t[p] = op(t[2 * p], t[2 * p + 1]); }
    T query(int l, int r) const {                              // [l, r), 0-indexed
        T resl = id, resr = id;
        for (l += n, r += n; l < r; l >>= 1, r >>= 1) {
            if (l & 1) resl = op(resl, t[l++]);                // leftmost untaken piece, append on the right of resl
            if (r & 1) resr = op(t[--r], resr);                // rightmost untaken piece, prepend to resr
        }
        return op(resl, resr);
    }
};
// usage: SegTree st(n, LLONG_MAX, [](long long a, long long b) { return min(a, b); });
```

```java
static class SegTree {
    final int n; final long[] t; final long id; final LongBinaryOperator op;
    SegTree(int n, long id, LongBinaryOperator op) { this.n = n; this.id = id; this.op = op; t = new long[2 * n]; Arrays.fill(t, id); }
    void build() { for (int i = n - 1; i > 0; i--) t[i] = op.applyAsLong(t[2 * i], t[2 * i + 1]); }
    void set(int p, long v) { for (t[p += n] = v; (p >>= 1) > 0; ) t[p] = op.applyAsLong(t[2 * p], t[2 * p + 1]); }
    long query(int l, int r) {                                 // [l, r), 0-indexed
        long resl = id, resr = id;
        for (l += n, r += n; l < r; l >>= 1, r >>= 1) {
            if ((l & 1) == 1) resl = op.applyAsLong(resl, t[l++]);
            if ((r & 1) == 1) resr = op.applyAsLong(t[--r], resr);
        }
        return op.applyAsLong(resl, resr);
    }
}
```

### 3.3 A non-commutative monoid: point-set, range-composite of affine maps

Original task. $n$ maps $f_i(x) = a_i x + b_i \pmod{998244353}$. Queries `0 p c d` set $f_p(x) = cx + d$; `1 l r x` print
$f_{r-1}(\cdots f_{l+1}(f_l(x)))$ (0-indexed, half-open). The bottom-up query keeps left and right accumulators, so order is respected even
for $n$ that is not a power of two. Stored as two parallel arrays — in Java this avoids an object per node.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 998244353;

int n;
vector<long long> A, B;                                        // node = map x -> A x + B
// "first (a1,b1), then (a2,b2)"
inline pair<long long,long long> comb(long long a1, long long b1, long long a2, long long b2) {
    return {a2 * a1 % MOD, (a2 * b1 + b2) % MOD};
}
void pull(int i) { tie(A[i], B[i]) = comb(A[2 * i], B[2 * i], A[2 * i + 1], B[2 * i + 1]); }

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int q; cin >> n >> q;
    A.assign(2 * n, 1); B.assign(2 * n, 0);
    for (int i = 0; i < n; i++) cin >> A[n + i] >> B[n + i];
    for (int i = n - 1; i > 0; i--) pull(i);
    while (q--) {
        int type; cin >> type;
        if (type == 0) {
            int p; long long c, d; cin >> p >> c >> d;
            p += n; A[p] = c; B[p] = d;
            for (p >>= 1; p > 0; p >>= 1) pull(p);
        } else {
            int l, r; long long x; cin >> l >> r >> x;
            long long la = 1, lb = 0, ra = 1, rb = 0;
            for (l += n, r += n; l < r; l >>= 1, r >>= 1) {
                if (l & 1) { tie(la, lb) = comb(la, lb, A[l], B[l]); l++; }
                if (r & 1) { --r; tie(ra, rb) = comb(A[r], B[r], ra, rb); }
            }
            auto [fa, fb] = comb(la, lb, ra, rb);
            cout << (fa * x + fb) % MOD << '\n';
        }
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 998244353;
    static int n; static long[] A, B;
    static void pull(int i) {
        long a1 = A[2 * i], b1 = B[2 * i], a2 = A[2 * i + 1], b2 = B[2 * i + 1];
        A[i] = a2 * a1 % MOD; B[i] = (a2 * b1 + b2) % MOD;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        n = in.nextInt(); int q = in.nextInt();
        A = new long[2 * n]; B = new long[2 * n]; Arrays.fill(A, 1);
        for (int i = 0; i < n; i++) { A[n + i] = in.nextLong(); B[n + i] = in.nextLong(); }
        for (int i = n - 1; i > 0; i--) pull(i);
        while (q-- > 0) {
            int type = in.nextInt();
            if (type == 0) {
                int p = in.nextInt() + n; A[p] = in.nextLong(); B[p] = in.nextLong();
                for (p >>= 1; p > 0; p >>= 1) pull(p);
            } else {
                int l = in.nextInt() + n, r = in.nextInt() + n; long x = in.nextLong();
                long la = 1, lb = 0, ra = 1, rb = 0;
                for (; l < r; l >>= 1, r >>= 1) {
                    if ((l & 1) == 1) { long na = A[l] * la % MOD, nb = (A[l] * lb + B[l]) % MOD; la = na; lb = nb; l++; }
                    if ((r & 1) == 1) { --r; long na = ra * A[r] % MOD, nb = (ra * B[r] + rb) % MOD; ra = na; rb = nb; }
                }
                long fa = ra * la % MOD, fb = (ra * lb + rb) % MOD;
                out.println((fa * x + fb) % MOD);
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
3 4
2 1
3 0
1 5
1 0 3 1
1 1 2 4
0 1 0 0
1 0 3 1
out:
14
12
5
-->
<!-- test
in:
1 3
2 1
1 0 1 998244352
0 0 998244352 0
1 0 1 3
out:
998244352
998244350
-->
<!-- test
in:
5 3
2 0
1 1
3 0
1 2
2 1
1 0 5 0
1 1 4 1
1 2 3 7
out:
11
8
21
-->

### 3.4 Node catalogue (combine functions only)

```cpp
struct MaxSub { long long sum, pre, suf, best; };              // empty subarray allowed: leaf x -> {x, max(0,x), max(0,x), max(0,x)}
MaxSub combine(const MaxSub& L, const MaxSub& R) {
    return {L.sum + R.sum, max(L.pre, L.sum + R.pre), max(R.suf, R.sum + L.suf), max({L.best, R.best, L.suf + R.pre})};
}
struct Blocks { int cnt; bool lb, rb; bool empty; };          // maximal blocks of 1s; identity = {0, 0, 0, true}
Blocks combine(const Blocks& L, const Blocks& R) {
    if (L.empty) return R;
    if (R.empty) return L;
    return {L.cnt + R.cnt - (L.rb && R.lb ? 1 : 0), L.lb, R.rb, false};
}
struct Brackets { int m, o, c; };                              // matched pairs, unmatched '(' and ')'; identity {0,0,0}
Brackets combine(const Brackets& L, const Brackets& R) {
    int t = min(L.o, R.c);
    return {L.m + R.m + t, L.o + R.o - t, L.c + R.c - t};
}
```

```java
// Nodes as small immutable records: fine for clarity; in hot loops use parallel primitive arrays instead.
record MaxSub(long sum, long pre, long suf, long best) {
    static MaxSub leaf(long x) { long y = Math.max(0, x); return new MaxSub(x, y, y, y); }
    static MaxSub combine(MaxSub L, MaxSub R) {
        return new MaxSub(L.sum + R.sum, Math.max(L.pre, L.sum + R.pre), Math.max(R.suf, R.sum + L.suf),
                          Math.max(Math.max(L.best, R.best), L.suf + R.pre));
    }
}
record Blocks(int cnt, boolean lb, boolean rb, boolean empty) {
    static final Blocks ID = new Blocks(0, false, false, true);
    static Blocks combine(Blocks L, Blocks R) {
        if (L.empty) return R;
        if (R.empty) return L;
        return new Blocks(L.cnt + R.cnt - (L.rb && R.lb ? 1 : 0), L.lb, R.rb, false);
    }
}
record Brackets(int m, int o, int c) {
    static Brackets combine(Brackets L, Brackets R) {
        int t = Math.min(L.o, R.c);
        return new Brackets(L.m + R.m + t, L.o + R.o - t, L.c + R.c - t);
    }
}
```

## 4. Recognising the pattern

- **Range query + point update, operation without an inverse** (min, max, gcd, "max subarray", "matching brackets", composition) → segment tree. With an inverse and only sums → BIT is shorter.
- **No updates at all** → prefix sums (invertible) or a [sparse table](05-sparse-table-and-rmq.md) (idempotent: min/max/gcd, $O(1)$ query). A segment tree is the fallback for non-idempotent static queries.
- **"After each update, print the answer for the whole array"** → the root of a recursive tree (or `query(0, n)` of the iterative one) — the update is $O(\log n)$, the answer is free.
- **A DP over the array whose transition is the same "shape" everywhere** (e.g. counting subsequences, $(\min,+)$ transitions with $k$ states) → node = $k \times k$ transition matrix, combine = matrix product; point updates change one matrix.
- **Statement mentions brackets, "longest correct subsequence", "number of segments", "runs"** → design a node with boundary information.
- **Range updates too** (add/assign on ranges) → [lazy propagation](03-lazy-propagation.md). "First index where …" → [descent](04-segment-tree-advanced-descent-merging-beats.md).
- Confused with: sliding-window problems (a monotonic deque is $O(n)$ when windows only move right, see [monotonic deque](../02-Core-Techniques/04-monotonic-stack-and-deque.md)).

## 5. Worked examples (graded)

### Example 1 — Dynamic Range Minimum Queries  ·  ★ ≈1300

- **Source:** [CSES 1649 · Dynamic Range Minimum Queries](https://cses.fi/problemset/task/1649)
- **Difficulty:** ≈1300 (est.)
- **Problem:** $n, q \le 2\cdot10^5$; `1 k u` sets $x_k = u$; `2 a b` prints $\min(x_a..x_b)$.
- **Thinking from first principles:** min has no inverse, so no BIT; a sparse table cannot update. Min is a commutative monoid with identity $+\infty$, so the shortest correct code is the bottom-up tree.

<details><summary>Solution</summary>

Bottom-up tree, query `[a-1, b)`. $O((n + q)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    vector<int> t(2 * n);
    for (int i = 0; i < n; i++) cin >> t[n + i];
    for (int i = n - 1; i > 0; i--) t[i] = min(t[2 * i], t[2 * i + 1]);
    while (q--) {
        int type, a, b; cin >> type >> a >> b;
        if (type == 1) {
            int p = a - 1 + n; t[p] = b;
            for (p >>= 1; p > 0; p >>= 1) t[p] = min(t[2 * p], t[2 * p + 1]);
        } else {
            int res = INT_MAX;
            for (int l = a - 1 + n, r = b + n; l < r; l >>= 1, r >>= 1) {
                if (l & 1) res = min(res, t[l++]);
                if (r & 1) res = min(res, t[--r]);
            }
            cout << res << '\n';
        }
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
        int[] t = new int[2 * n];
        for (int i = 0; i < n; i++) t[n + i] = in.nextInt();
        for (int i = n - 1; i > 0; i--) t[i] = Math.min(t[2 * i], t[2 * i + 1]);
        while (q-- > 0) {
            int type = in.nextInt(), a = in.nextInt(), b = in.nextInt();
            if (type == 1) {
                int p = a - 1 + n; t[p] = b;
                for (p >>= 1; p > 0; p >>= 1) t[p] = Math.min(t[2 * p], t[2 * p + 1]);
            } else {
                int res = Integer.MAX_VALUE;
                for (int l = a - 1 + n, r = b + n; l < r; l >>= 1, r >>= 1) {
                    if ((l & 1) == 1) res = Math.min(res, t[l++]);
                    if ((r & 1) == 1) res = Math.min(res, t[--r]);
                }
                out.println(res);
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
2 1 4
2 5 6
1 2 3
2 1 4
out:
2
1
3
-->
<!-- test
in:
1 3
5
2 1 1
1 1 1000000000
2 1 1
out:
5
1000000000
-->

</details>

### Example 2 — Xenia and Bit Operations  ·  ★ 1700

- **Source:** [CF 339D · Xenia and Bit Operations](https://codeforces.com/problemset/problem/339/D) — 1700
- **Difficulty:** 1700
- **Problem:** an array of $2^n$ values ($n \le 17$). Reduce it by replacing adjacent pairs with their OR, then the result's adjacent pairs with XOR, alternating until one value $v$ remains. After each of $m \le 10^5$ point assignments print $v$.
- **Thinking from first principles:** the reduction *is* a segment tree whose operation depends on the level: level 1 (just above leaves) is OR, level 2 XOR, …
  Recomputing everything is $O(2^n)$ per query = $1.3\cdot10^{10}$. Only the $n$ ancestors of the changed leaf change. The operation is not a single monoid,
  but each node's operation is fixed by its height, which is all an update needs.

<details><summary>Solution</summary>

Bottom-up tree of size $N = 2^n$ (a power of two, so `t[1]` is the whole array). Node $i$ has height $h = n - \lfloor\log_2 i\rfloor$; odd height → OR, even → XOR.
During an update, the height grows by one per step. $O(\log N)$ per query.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    int N = 1 << n;
    vector<int> t(2 * N);
    for (int i = 0; i < N; i++) cin >> t[N + i];
    for (int i = N - 1; i > 0; i--) {
        int h = n - __lg(i);
        t[i] = (h & 1) ? (t[2 * i] | t[2 * i + 1]) : (t[2 * i] ^ t[2 * i + 1]);
    }
    while (m--) {
        int p, b; cin >> p >> b;
        p += N - 1; t[p] = b;
        for (int h = 1; p > 1; h++) {
            p >>= 1;
            t[p] = (h & 1) ? (t[2 * p] | t[2 * p + 1]) : (t[2 * p] ^ t[2 * p + 1]);
        }
        cout << t[1] << '\n';
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
        int n = in.nextInt(), m = in.nextInt(), N = 1 << n;
        int[] t = new int[2 * N];
        for (int i = 0; i < N; i++) t[N + i] = in.nextInt();
        for (int i = N - 1; i > 0; i--) {
            int h = n - (31 - Integer.numberOfLeadingZeros(i));
            t[i] = (h & 1) == 1 ? (t[2 * i] | t[2 * i + 1]) : (t[2 * i] ^ t[2 * i + 1]);
        }
        while (m-- > 0) {
            int p = in.nextInt() + N - 1, b = in.nextInt();
            t[p] = b;
            for (int h = 1; p > 1; h++) {
                p >>= 1;
                t[p] = (h & 1) == 1 ? (t[2 * p] | t[2 * p + 1]) : (t[2 * p] ^ t[2 * p + 1]);
            }
            out.println(t[1]);
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
2 4
1 6 3 5
1 4
3 4
1 2
1 2
out:
1
3
3
3
-->
<!-- test
in:
1 2
5 3
1 0
2 8
out:
3
8
-->
<!-- test
in:
3 1
1 2 4 8 16 32 64 128
8 0
out:
127
-->

</details>

### Example 3 — Subarray Sum Queries (the 4-field node)  ·  ★ ≈1800

- **Source:** [CSES 1190 · Subarray Sum Queries](https://cses.fi/problemset/task/1190)
- **Difficulty:** ≈1800 (est.)
- **Problem:** $n, m \le 2\cdot10^5$, values in $[-10^9, 10^9]$. After each point assignment print the maximum subarray sum of the whole array (the empty subarray, sum 0, is allowed).
- **Thinking from first principles:** Kadane is $O(n)$ per update → $4\cdot10^{10}$. The answer for a concatenation needs the best
  crossing subarray = best suffix of the left + best prefix of the right; prefix of a concatenation needs the left total. That is the
  4-field node of §1. Allowing the empty subarray means every "best" field is $\ge 0$, and the identity is all zeros.

<details><summary>Solution</summary>

Recursive tree over the 4-field node, answer = root's `best`. Java keeps four `long[]` arrays instead of node objects.
$O((n + m)\log n)$. Values reach $2\cdot10^{14}$ → 64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct Node { long long sum, pre, suf, best; };
Node leaf(long long x) { long long y = max(0LL, x); return {x, y, y, y}; }
Node combine(const Node& L, const Node& R) {
    return {L.sum + R.sum, max(L.pre, L.sum + R.pre), max(R.suf, R.sum + L.suf), max({L.best, R.best, L.suf + R.pre})};
}
int n;
vector<Node> t;
void build(int v, int l, int r, const vector<long long>& a) {
    if (l == r) { t[v] = leaf(a[l]); return; }
    int m = (l + r) >> 1;
    build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a);
    t[v] = combine(t[2 * v], t[2 * v + 1]);
}
void update(int v, int l, int r, int pos, long long x) {
    if (l == r) { t[v] = leaf(x); return; }
    int m = (l + r) >> 1;
    if (pos <= m) update(2 * v, l, m, pos, x); else update(2 * v + 1, m + 1, r, pos, x);
    t[v] = combine(t[2 * v], t[2 * v + 1]);
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int m; cin >> n >> m;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    t.assign(4 * n, {0, 0, 0, 0});
    build(1, 0, n - 1, a);
    while (m--) {
        int k; long long x; cin >> k >> x;
        update(1, 0, n - 1, k - 1, x);
        cout << t[1].best << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long[] sum, pre, suf, best;
    static void setLeaf(int v, long x) { long y = Math.max(0, x); sum[v] = x; pre[v] = y; suf[v] = y; best[v] = y; }
    static void pull(int v) {
        int L = 2 * v, R = 2 * v + 1;
        sum[v] = sum[L] + sum[R];
        pre[v] = Math.max(pre[L], sum[L] + pre[R]);
        suf[v] = Math.max(suf[R], sum[R] + suf[L]);
        best[v] = Math.max(Math.max(best[L], best[R]), suf[L] + pre[R]);
    }
    static void build(int v, int l, int r, long[] a) {
        if (l == r) { setLeaf(v, a[l]); return; }
        int m = (l + r) >> 1;
        build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a);
        pull(v);
    }
    static void update(int v, int l, int r, int pos, long x) {
        if (l == r) { setLeaf(v, x); return; }
        int m = (l + r) >> 1;
        if (pos <= m) update(2 * v, l, m, pos, x); else update(2 * v + 1, m + 1, r, pos, x);
        pull(v);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), m = in.nextInt();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        sum = new long[4 * n]; pre = new long[4 * n]; suf = new long[4 * n]; best = new long[4 * n];
        build(1, 0, n - 1, a);
        while (m-- > 0) {
            int k = in.nextInt(); long x = in.nextLong();
            update(1, 0, n - 1, k - 1, x);
            out.println(best[1]);
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
5 3
1 2 -3 5 -1
2 6
3 1
2 -2
out:
9
13
6
-->
<!-- test
in:
1 2
-5
1 -7
1 4
out:
0
4
-->
<!-- test
in:
3 1
1000000000 1000000000 1000000000
2 -1000000000
out:
1000000000
-->

</details>

### Example 4 — Prefix Sum Queries (non-commutative range query)  ·  ★ ≈1900

- **Source:** [CSES 2166 · Prefix Sum Queries](https://cses.fi/problemset/task/2166)
- **Difficulty:** ≈1900 (est.)
- **Problem:** $n, q \le 2\cdot10^5$; `1 k u` sets $x_k = u$; `2 a b` prints the maximum prefix sum of the subarray $x_a..x_b$ (the empty prefix, 0, counts).
- **Thinking from first principles:** the best prefix of $L\cdot R$ is either inside $L$ or all of $L$ plus a prefix of $R$:
  node = (sum, pre). This is non-commutative: swapping halves changes the answer. A query must combine canonical pieces **left to right**.
  In the recursive query, visiting the left child before the right child already produces the pieces in order, so we can fold them into a running
  accumulator instead of building and returning node objects.

<details><summary>Solution</summary>

Recursive tree; the query appends each fully covered node to the accumulator `(accSum, accPre)` via
`accPre = max(accPre, accSum + pre[v]); accSum += sum[v]`. Start with the identity `(0, 0)`, which also encodes the empty prefix. $O(\log n)$ per operation.

```cpp
#include <bits/stdc++.h>
using namespace std;

int n;
vector<long long> sm, pr;                                      // pr = best prefix, empty allowed (>= 0)
void setLeaf(int v, long long x) { sm[v] = x; pr[v] = max(0LL, x); }
void pull(int v) { sm[v] = sm[2 * v] + sm[2 * v + 1]; pr[v] = max(pr[2 * v], sm[2 * v] + pr[2 * v + 1]); }
void build(int v, int l, int r, const vector<long long>& a) {
    if (l == r) { setLeaf(v, a[l]); return; }
    int m = (l + r) >> 1;
    build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a); pull(v);
}
void update(int v, int l, int r, int pos, long long x) {
    if (l == r) { setLeaf(v, x); return; }
    int m = (l + r) >> 1;
    if (pos <= m) update(2 * v, l, m, pos, x); else update(2 * v + 1, m + 1, r, pos, x);
    pull(v);
}
long long accSum, accPre;
void query(int v, int l, int r, int ql, int qr) {                // visits covered nodes left to right
    if (qr < l || r < ql) return;
    if (ql <= l && r <= qr) { accPre = max(accPre, accSum + pr[v]); accSum += sm[v]; return; }
    int m = (l + r) >> 1;
    query(2 * v, l, m, ql, qr); query(2 * v + 1, m + 1, r, ql, qr);
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int q; cin >> n >> q;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    sm.assign(4 * n, 0); pr.assign(4 * n, 0);
    build(1, 0, n - 1, a);
    while (q--) {
        int type; long long x, y; cin >> type >> x >> y;
        if (type == 1) update(1, 0, n - 1, int(x) - 1, y);
        else { accSum = accPre = 0; query(1, 0, n - 1, int(x) - 1, int(y) - 1); cout << accPre << '\n'; }
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long[] sm, pr;
    static long accSum, accPre;
    static void setLeaf(int v, long x) { sm[v] = x; pr[v] = Math.max(0, x); }
    static void pull(int v) { sm[v] = sm[2 * v] + sm[2 * v + 1]; pr[v] = Math.max(pr[2 * v], sm[2 * v] + pr[2 * v + 1]); }
    static void build(int v, int l, int r, long[] a) {
        if (l == r) { setLeaf(v, a[l]); return; }
        int m = (l + r) >> 1;
        build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a); pull(v);
    }
    static void update(int v, int l, int r, int pos, long x) {
        if (l == r) { setLeaf(v, x); return; }
        int m = (l + r) >> 1;
        if (pos <= m) update(2 * v, l, m, pos, x); else update(2 * v + 1, m + 1, r, pos, x);
        pull(v);
    }
    static void query(int v, int l, int r, int ql, int qr) {
        if (qr < l || r < ql) return;
        if (ql <= l && r <= qr) { accPre = Math.max(accPre, accSum + pr[v]); accSum += sm[v]; return; }
        int m = (l + r) >> 1;
        query(2 * v, l, m, ql, qr); query(2 * v + 1, m + 1, r, ql, qr);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), q = in.nextInt();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        sm = new long[4 * n]; pr = new long[4 * n];
        build(1, 0, n - 1, a);
        while (q-- > 0) {
            int type = in.nextInt(); long x = in.nextLong(), y = in.nextLong();
            if (type == 1) update(1, 0, n - 1, (int) x - 1, y);
            else { accSum = 0; accPre = 0; query(1, 0, n - 1, (int) x - 1, (int) y - 1); out.println(accPre); }
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
8 4
1 2 -1 3 1 -5 1 4
2 2 6
1 4 -2
2 2 6
2 3 4
out:
5
2
0
-->
<!-- test
in:
1 3
-3
2 1 1
1 1 7
2 1 1
out:
0
7
-->

</details>

### Example 5 — Sereja and Brackets  ·  ★ 2000

- **Source:** [CF 380C · Sereja and Brackets](https://codeforces.com/problemset/problem/380/C) — 2000
- **Difficulty:** 2000
- **Problem:** a bracket string of length $\le 10^6$; $m \le 10^5$ queries $[l, r]$: the length of the longest correct bracket *subsequence* of $s_l..s_r$.
- **Thinking from first principles:** for one string the answer is greedy: scan, match each `)` with an unmatched `(` if any.
  To answer ranges, design the node (§1): after greedy matching a segment reduces to `)))…(((` with $c$ closers and $o$ openers; concatenation matches
  $\min(o_L, c_R)$ more pairs. No updates, but the operation is not idempotent and not invertible, so neither prefix sums nor a sparse table apply directly.
  With $n = 10^6$ memory and speed matter: the bottom-up tree uses $2n$ nodes and no recursion; it must keep left/right accumulators because the node is not commutative.

<details><summary>Solution</summary>

Leaves: `(` → $(0,1,0)$, `)` → $(0,0,1)$. Answer $= 2m$. $O(n + m\log n)$ time, $3 \cdot 2n$ ints of memory.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct B { int m, o, c; };
inline B comb(const B& L, const B& R) {
    int t = min(L.o, R.c);
    return {L.m + R.m + t, L.o + R.o - t, L.c + R.c - t};
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s; cin >> s;
    int n = s.size(), q; cin >> q;
    vector<B> t(2 * n, {0, 0, 0});
    for (int i = 0; i < n; i++) t[n + i] = (s[i] == '(') ? B{0, 1, 0} : B{0, 0, 1};
    for (int i = n - 1; i > 0; i--) t[i] = comb(t[2 * i], t[2 * i + 1]);
    while (q--) {
        int l, r; cin >> l >> r;
        B L{0, 0, 0}, R{0, 0, 0};
        for (l += n - 1, r += n; l < r; l >>= 1, r >>= 1) {
            if (l & 1) L = comb(L, t[l++]);
            if (r & 1) R = comb(t[--r], R);
        }
        cout << 2 * comb(L, R).m << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        byte[] s = new byte[1_000_001]; int n = 0, c = in.read();
        while (c != '(' && c != ')') c = in.read();
        while (c == '(' || c == ')') { s[n++] = (byte) c; c = in.read(); }
        int[] M = new int[2 * n], O = new int[2 * n], C = new int[2 * n];
        for (int i = 0; i < n; i++) { if (s[i] == '(') O[n + i] = 1; else C[n + i] = 1; }
        for (int i = n - 1; i > 0; i--) {
            int a = 2 * i, b = 2 * i + 1, t = Math.min(O[a], C[b]);
            M[i] = M[a] + M[b] + t; O[i] = O[a] + O[b] - t; C[i] = C[a] + C[b] - t;
        }
        int q = readInt(in);
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            int l = readInt(in) + n - 1, r = readInt(in) + n;
            int lm = 0, lo = 0, lc = 0, rm = 0, ro = 0, rc = 0;
            for (; l < r; l >>= 1, r >>= 1) {
                if ((l & 1) == 1) {                                // left accumulator := left (+) node l
                    int t = Math.min(lo, C[l]);
                    lm += M[l] + t; lc += C[l] - t; lo += O[l] - t; l++;
                }
                if ((r & 1) == 1) {                                // right accumulator := node r (+) right
                    --r; int t = Math.min(O[r], rc);
                    rm += M[r] + t; ro += O[r] - t; rc += C[r] - t;
                }
            }
            sb.append(2 * (lm + rm + Math.min(lo, rc))).append('\n');
        }
        System.out.print(sb);
    }

    static int readInt(DataInputStream in) throws IOException {
        int c = in.read(); while (c < '0' || c > '9') c = in.read();
        int r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = in.read(); }
        return r;
    }
}
```

The Java accumulator updates are the combine formula expanded in place: for `left (+) node`, $t = \min(o_{acc}, c_{node})$,
$c_{new} = c_{acc} + c_{node} - t$, $o_{new} = o_{acc} + o_{node} - t$. For `node (+) right` the roles swap.

<!-- test
in:
())(())(())(
7
1 1
2 3
1 2
1 12
8 12
5 11
2 10
out:
0
0
2
10
4
6
6
-->
<!-- test
in:
(
2
1 1
1 1
out:
0
0
-->
<!-- test
in:
)(()(
3
1 5
2 4
3 5
out:
2
2
2
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Array size.** Recursive heap layout needs `4n` (not `2n`): for $n = 2^k + 1$ the last level has indices near $4n$. Bottom-up needs exactly `2n`.
2. **The identity must be a true identity.** `0` is not the identity of min; `INT_MAX` is. For max-subarray with *non-empty* subarrays, the identity cannot be all zeros — either forbid empty queries or carry an `empty` flag (as in `Blocks`).
3. **Non-commutative nodes need ordered combining**: recursive query → `op(left, right)`; bottom-up → two accumulators (`resl = op(resl, t[l])`, `resr = op(t[r], resr)`). Mixing them up passes symmetric tests and fails real ones.
4. **`t[1]` of a bottom-up tree is the whole array only when $n$ is a power of two.** For non-commutative nodes use `query(0, n)` or pad.
5. **Closed vs half-open intervals.** Pick one per template and convert at the call site (`query(a - 1, b)` for 1-indexed closed input on a half-open tree). Most off-by-ones in contests are here.
6. **Midpoint with negative coordinates**: `(l + r) / 2` rounds toward zero in C++/Java; with negative $l$ use `l + (r - l) / 2` or `(l + r) >> 1` (floor) consistently.
7. **Java performance**: arrays of primitives per field (struct-of-arrays), not `Node` objects — object allocation in `combine` triggers GC and doubles memory. Prefer the bottom-up tree when it suffices.
8. **Recursion depth** is only $\log n$, so stack overflow is not a concern for segment trees themselves — but building a tree over an Euler tour still requires an iterative DFS for deep trees.
9. **Reading $10^6$ characters in Java**: read raw bytes (Example 5); `BufferedReader.readLine()` is fine too; `Scanner` is not.
10. **Build in $O(n)$** from the leaves instead of $n$ point updates when $n$ is large.
11. **Point assignment vs point add.** A segment tree stores node values, so assignment is natural; for "add", update the leaf as `t[p] += v` before recomputing ancestors.
12. **Answer type.** Sums of $2\cdot 10^5$ values up to $10^9$ overflow `int`; min/max of `int` values do not — use the smallest safe type in Java for memory, `long` where sums appear.

## 7. Going further (toward 2400–2600+)

- **Matrix nodes for DP**: a DP whose per-element transition is a $k\times k$ matrix in a semiring ($(+,\times)$ or $(\min,+)$) becomes a segment tree of matrices; point updates change one matrix. [CF 750E · New Year and Old Subsequence](https://codeforces.com/problemset/problem/750/E) — 2600 and [CF 1609E · William The Oblivious](https://codeforces.com/problemset/problem/1609/E) — 2400 are the canonical drills. See also [matrix exponentiation for DP](../07-DP-Optimizations/08-matrix-exponentiation-for-dp.md).
- **Rich boundary nodes**: [CF 1149C · Tree Generator™](https://codeforces.com/problemset/problem/1149/C) — 2700 (tree diameter from a bracket sequence: a node with five derived fields of prefix depths).
- **Segment tree over values** (counts per value) for k-th / order statistics, which becomes persistent in [persistent structures](08-persistent-data-structures.md).
- **Segment tree on queries / time** for offline deletions ([segment tree on time](../16-IGM-Frontier/02-segment-tree-on-time-and-dsu-rollback.md)).
- **Li Chao tree** (a segment tree of lines) for DP optimisation ([convex hull trick and Li Chao](../07-DP-Optimizations/02-convex-hull-trick-and-li-chao-tree.md)).
- **Segment tree as a graph**: build edges to $O(\log n)$ nodes to connect a vertex to a whole range ([CF 786B · Legacy](https://codeforces.com/problemset/problem/786/B) — 2300, [shortest paths](../09-Graphs/02-shortest-paths.md)).

## 8. Practice ladder

**≤ 1600**
- [ ] [CSES 1649 · Dynamic Range Minimum Queries](https://cses.fi/problemset/task/1649)
- [ ] [AtCoder PRACTICE2 J · Segment Tree](https://atcoder.jp/contests/practice2/tasks/practice2_j)
- [ ] [AtCoder ABC185 F · Range Xor Query](https://atcoder.jp/contests/abc185/tasks/abc185_f)
- [ ] [CF 1234D · Distinct Characters Queries](https://codeforces.com/problemset/problem/1234/D) — 1600

**1600–1900**
- [ ] [CF 339D · Xenia and Bit Operations](https://codeforces.com/problemset/problem/339/D) — 1700
- [ ] [CSES 1190 · Subarray Sum Queries](https://cses.fi/problemset/task/1190)
- [ ] [CSES 2166 · Prefix Sum Queries](https://cses.fi/problemset/task/2166)
- [ ] [CSES 2206 · Pizzeria Queries](https://cses.fi/problemset/task/2206)
- [ ] [CF 1691D · Max GEQ Sum](https://codeforces.com/problemset/problem/1691/D) — 1800
- [ ] [CF 914D · Bash and a Tough Math Puzzle](https://codeforces.com/problemset/problem/914/D) — 1900

**1900–2200**
- [ ] [CF 380C · Sereja and Brackets](https://codeforces.com/problemset/problem/380/C) — 2000
- [ ] [CF 474F · Ant colony](https://codeforces.com/problemset/problem/474/F) — 2100
- [ ] [CF 1420C2 · Pokémon Army (hard version)](https://codeforces.com/problemset/problem/1420/C2) — 2100
- [ ] [CF 1667B · Optimal Partition](https://codeforces.com/problemset/problem/1667/B) — 2100
- [ ] [CF 1555E · Boring Segments](https://codeforces.com/problemset/problem/1555/E) — 2100
- [ ] [CF 1567E · Non-Decreasing Dilemma](https://codeforces.com/problemset/problem/1567/E) — 2200
- [ ] [CF 1557D · Ezzat and Grid](https://codeforces.com/problemset/problem/1557/D) — 2200

**2200+**
- [ ] [CF 1919F1 · Wine Factory (Easy Version)](https://codeforces.com/problemset/problem/1919/F1) — 2300
- [ ] [CF 1609E · William The Oblivious](https://codeforces.com/problemset/problem/1609/E) — 2400
- [ ] [CF 750E · New Year and Old Subsequence](https://codeforces.com/problemset/problem/750/E) — 2600
- [ ] [CF 1149C · Tree Generator™](https://codeforces.com/problemset/problem/1149/C) — 2700

## 9. LeetCode / FAANG cross-reference

- [LC 307 · Range Sum Query - Mutable](https://leetcode.com/problems/range-sum-query-mutable/) — Medium — either structure; the segment tree version generalises to min/max.
- [LC 2407 · Longest Increasing Subsequence II](https://leetcode.com/problems/longest-increasing-subsequence-ii/) — Hard — $dp[v] = 1 + \max dp[v-k..v-1]$: range-max segment tree over values.
- [LC 2213 · Longest Substring of One Repeating Character](https://leetcode.com/problems/longest-substring-of-one-repeating-character/) — Hard — the "runs" node: (prefix run, suffix run, best, first/last char).
- [LC 2286 · Booking Concert Tickets in Groups](https://leetcode.com/problems/booking-concert-tickets-in-groups/) — Hard — max + sum nodes with descent (see [advanced](04-segment-tree-advanced-descent-merging-beats.md)).
- [LC 218 · The Skyline Problem](https://leetcode.com/problems/the-skyline-problem/) — Hard — usually a heap sweep; a max segment tree over compressed x works too.
- [LC 2940 · Find Building Where Alice and Bob Can Meet](https://leetcode.com/problems/find-building-where-alice-and-bob-can-meet/) — Hard — range max + "first index to the right with value > h" descent.

Interview frequency: medium-low. Segment trees appear at Google/Meta onsite "hard" rounds; most interviewers accept a BIT or a balanced BST where it fits.

## 10. Self-check

1. Prove that a range query visits at most four nodes per level.
2. What are the monoid requirements, and which of them does the bottom-up query rely on when it keeps two accumulators?
3. Design the node for "number of maximal blocks of equal adjacent values" in a range. What is its identity?
4. Why does the recursive layout need `4n` cells? Give an $n$ where `2n` fails.
5. When is `t[1]` of the bottom-up tree *not* the answer for the whole array?
6. How would you answer "maximum subarray sum inside $[l, r]$" with point updates?
7. Why can't a segment tree be built in less than $\Theta(n)$, and how do you get exactly $n - 1$ combines?

<details><summary>Answers</summary>

1. A visited node that recurses is partial, so it contains $l$ or $r$; nodes on a level are disjoint, so at most two are partial, giving at most four children visited on the next level.
2. Associativity and an identity. Two accumulators rely on associativity only (not commutativity): pieces are appended in order on the left and prepended in order on the right.
3. Fields (count, first value, last value, empty flag); combine: counts add, minus 1 if `L.last == R.first`; identity = the empty node.
4. Heap indices on the deepest level reach $2^{\lceil\log_2 n\rceil+1} - 1$. For $n = 5$: $\lceil\log_2 5\rceil = 3$, indices up to 15 > $2n = 10$.
5. When $n$ is not a power of two: some internal nodes, possibly the root, combine wrapped leaf sets.
6. Query the 4-field node over $[l, r]$, combining pieces left to right (recursive) or with two accumulators (bottom-up), and read `best`.
7. Every element must be read. Compute leaves, then each internal node once from its two children in decreasing index order (bottom-up) or post-order (recursive).

</details>
