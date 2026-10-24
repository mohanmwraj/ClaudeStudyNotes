# Lazy Propagation

> **Band:** 🟣 1900–2200 · **Priority:** 🔥 · **FAANG:** low · **Prerequisites:** [segment tree basics](02-segment-tree-basics.md), [modular arithmetic](../04-Number-Theory/02-modular-arithmetic-and-inverses.md)
> **You can say you know this when:** for a new pair (range update, range query) you can decide in a minute whether a lazy tag exists, write the tag's `apply` and `compose` formulas, and implement the tree with a correct push-down — including assign+add composition and affine maps.

## 1. First principles — why this works

**The waste in a naive range update.** With a plain segment tree, "add $v$ to $a_l..a_r$" must touch every leaf in the range:
$O(n)$ per update. But the query side already decomposes $[l, r]$ into $O(\log n)$ canonical nodes. If we could apply the update
to those nodes *as wholes* — fix their summaries in $O(1)$ — and postpone the work inside them until somebody actually looks inside,
an update would cost the same as a query.

Two things must be true for this to be possible.

1. **The new summary is computable from the old summary.** For "add $v$, query sum": the new sum is $\text{sum} + v\cdot \text{len}$ —
   computable if the node knows its length. For "add $v$, query min": $\min + v$. For "$a_i \bmod x$, query sum": *not computable* (the
   new sum depends on individual values) — no lazy tag exists, and you need the potential arguments of
   [segment tree beats](04-segment-tree-advanced-descent-merging-beats.md).
2. **Postponed updates can be merged into one.** A node may receive several updates before anyone looks inside. We store a single
   *tag* that represents their composition, so composing two updates must give another update of the same form, in $O(1)$.

**The algebra (monoid action).** Let node summaries form a monoid $(S, \oplus, e)$ as in [the basics](02-segment-tree-basics.md).
Let $F$ be a set of maps $S \to S$ such that

- $F$ contains the identity map and is closed under composition ($f, g \in F \Rightarrow f\circ g \in F$);
- every $f \in F$ **distributes over the combine**: $f(x \oplus y) = f(x) \oplus f(y)$.

Distributivity is what makes "apply $f$ to the parent" equal to "apply $f$ to both children and recombine", i.e. it is the
correctness condition for keeping a tag at a node instead of pushing it. Composition of functions is automatically associative, so
the only things to *derive* are `apply(f, s)` and `compose(f_new, f_old)` $= f_{new} \circ f_{old}$ in a compact representation.

**The invariant and push-down.** `t[v]` is the correct summary of $v$'s segment *taking into account every update except those still
pending in tags of strict ancestors of $v$*. `lz[v]` is a map already applied to `t[v]` but not yet to $v$'s children. Before we look at
children — in an update or a query that only partially covers $v$ — we **push**:

$$t[c] \leftarrow \mathrm{lz}[v]\big(t[c]\big), \qquad \mathrm{lz}[c] \leftarrow \mathrm{lz}[v] \circ \mathrm{lz}[c] \quad (c = 2v, 2v+1), \qquad \mathrm{lz}[v] \leftarrow \mathrm{id}.$$

The new tag goes on the **outside** of the composition: the child's old pending map happened earlier. After recursing in an update,
**pull**: `t[v] = t[2v] ⊕ t[2v+1]`. Complexity: an update visits the same $O(\log n)$ nodes as a query, each with $O(1)$ push and pull.

**Derivations of the tag algebras you will need.** Write a tag as the map it represents and compose maps.

| Update / query | Summary $S$ | Tag $f$ | `apply` | `compose` $f_2 \circ f_1$ |
|---|---|---|---|---|
| add $v$ / sum | (sum, len) | $x \mapsto x + v$ | $\text{sum} + v\cdot\text{len}$ | $v_1 + v_2$ |
| add $v$ / min, max | min | $x\mapsto x+v$ | $\min + v$ | $v_1 + v_2$ |
| assign $c$ / sum | (sum, len) | $x \mapsto c$ | $c \cdot \text{len}$ | $f_2$ (the newer wins) |
| assign $c$ and add $v$ / sum | (sum, len) | "set $c$" or "add $v$" | see below | see below |
| affine $x\mapsto bx + c$ / sum | (sum, len) | $(b, c)$ | $b\cdot\text{sum} + c\cdot\text{len}$ | $(b_2 b_1,\ b_2 c_1 + c_2)$ |
| flip bits / count of ones | (ones, len) | flip flag $\phi$ | $\phi ?\ \text{len} - \text{ones} : \text{ones}$ | $\phi_1 \oplus \phi_2$ |
| xor $x$ / sum | (cnt$_b$ per bit, len) | mask $x$ | $\text{cnt}_b \to \text{len}-\text{cnt}_b$ for bits of $x$ | $x_1 \oplus x_2$ |
| add $A + D\cdot k$ ($k$ = offset in node) / sum | (sum, len) | $(A, D)$ | $\text{sum} + A\,\text{len} + D\binom{\text{len}}{2}$ | $(A_1 + A_2, D_1 + D_2)$, right child gets $A + D\cdot\text{len}_{left}$ |

*Affine maps.* $f_2(f_1(x)) = b_2(b_1 x + c_1) + c_2 = (b_2 b_1)x + (b_2 c_1 + c_2)$; on a sum of $\text{len}$ elements,
$\sum (b x_i + c) = b \sum x_i + c\cdot\text{len}$, which also proves distributivity. Add is $(1, v)$, assign is $(0, c)$, multiply is $(k, 0)$ —
so the affine tree subsumes all three and their mixtures. Identity: $(1, 0)$.

*Assign + add without the general affine machinery.* Composition of any sequence of "set" and "add" maps is again either
"set $c$" (if at least one set happened: the last set, plus every add after it) or "add $v$" (sum of adds). So store `(isSet, val)`:
a new set $c$ replaces the tag with `(true, c)`; a new add $v$ does `val += v` and keeps `isSet`. Apply: set → $\text{sum} = c\cdot \text{len}$;
add → $\text{sum} \mathrel{+}= v\cdot\text{len}$. Getting the order wrong ("add then set" treated like "set then add") is the classic bug.

*Arithmetic progressions.* The tag says "position at offset $k$ from this node's left end receives $A + Dk$". The sum over the node is
$A\cdot\text{len} + D\cdot \frac{\text{len}(\text{len}-1)}{2}$. When pushed, the left child has the same left end (tag $(A, D)$), the right child
starts $\text{len}_{left}$ later (tag $(A + D\,\text{len}_{left}, D)$). Two pending progressions add componentwise.

**When there is no tag.** Range chmin with sum, range mod, range sqrt, range divide: the new sum depends on more than the summary.
Two escape routes: potential arguments (each element can only change $O(\log V)$ times — recurse until the update becomes a no-op or uniform),
and segment tree beats (keep max and second max). Both are in [the advanced file](04-segment-tree-advanced-descent-merging-beats.md).

**Lazy without pushing ("permanent tags").** For add/min (or add/sum) you can keep tags forever: `t[v] = op(t[2v], t[2v+1]) + tag[v]`,
and a query adds the tags of all ancestors on its path. No push-down is needed, which is essential for persistent and 2D segment trees
(nobody may modify shared children) and slightly faster.

## 2. Formulas, definitions and identities

- Monoid action conditions: $\mathrm{id}\in F$; $f, g\in F \Rightarrow f\circ g \in F$; $f(x\oplus y) = f(x)\oplus f(y)$; $f(e) = e$ is usually needed too, so that identities in unused nodes stay identities.
- Push rule: $t[c] \leftarrow \mathrm{lz}[v]\big(t[c]\big)$, $\mathrm{lz}[c] \leftarrow \mathrm{lz}[v]\circ\mathrm{lz}[c]$.
- Affine: $(b_2, c_2) \circ (b_1, c_1) = (b_2 b_1, b_2 c_1 + c_2)$; on sums: $\text{sum}' = b\,\text{sum} + c\,\text{len}$.
- Assign+add: $\text{add}(v)\circ\text{set}(c) = \text{set}(c+v)$; $\text{set}(c)\circ g = \text{set}(c)$; $\text{add}(v_2)\circ\text{add}(v_1) = \text{add}(v_1+v_2)$.
- AP: $\sum_{k=0}^{\text{len}-1} (A + Dk) = A\cdot\text{len} + D\,\frac{\text{len}(\text{len}-1)}{2}$.
- Bit decomposition: $\sum_i a_i = \sum_b 2^b\,\text{cnt}_b$; xor with $x$ maps $\text{cnt}_b \mapsto \text{len} - \text{cnt}_b$ for each set bit $b$ of $x$.
- Complexity: update and query $O(\log n)$ node visits, $O(1)$ tag work each (times the summary width, e.g. $\times 20$ for per-bit counts). Memory $4n$ summaries + $4n$ tags.

## 3. Implementation (C++ and Java)

### 3.1 Generic lazy segment tree (policy-based)

C++: the policy supplies `S, F, e, id, op, apply, compose` — exactly the algebra of §1. `apply` gets the node length, so
summaries need not store it. Java has no zero-cost generics over primitives, so the Java version is the **affine-sum** tree, which already covers
add, assign and multiply on sums (with a modulus; for plain integers drop the `% MOD` and use 64-bit).

```cpp
template <class P>
struct LazySeg {
    using S = typename P::S; using F = typename P::F;
    int n; vector<S> t; vector<F> lz;
    explicit LazySeg(const vector<S>& a) : n(a.size()), t(4 * a.size()), lz(4 * a.size(), P::id()) { build(1, 0, n - 1, a); }
    void build(int v, int l, int r, const vector<S>& a) {
        if (l == r) { t[v] = a[l]; return; }
        int m = (l + r) >> 1;
        build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a);
        t[v] = P::op(t[2 * v], t[2 * v + 1]);
    }
    void applyNode(int v, int len, const F& f) { t[v] = P::apply(f, t[v], len); lz[v] = P::compose(f, lz[v]); }
    void push(int v, int l, int m, int r) {                // only called on internal nodes
        applyNode(2 * v, m - l + 1, lz[v]); applyNode(2 * v + 1, r - m, lz[v]);
        lz[v] = P::id();
    }
    void update(int v, int l, int r, int ql, int qr, const F& f) {
        if (qr < l || r < ql) return;
        if (ql <= l && r <= qr) { applyNode(v, r - l + 1, f); return; }
        int m = (l + r) >> 1;
        push(v, l, m, r);
        update(2 * v, l, m, ql, qr, f); update(2 * v + 1, m + 1, r, ql, qr, f);
        t[v] = P::op(t[2 * v], t[2 * v + 1]);
    }
    S query(int v, int l, int r, int ql, int qr) {
        if (qr < l || r < ql) return P::e();
        if (ql <= l && r <= qr) return t[v];
        int m = (l + r) >> 1;
        push(v, l, m, r);
        return P::op(query(2 * v, l, m, ql, qr), query(2 * v + 1, m + 1, r, ql, qr));
    }
    void update(int l, int r, const F& f) { update(1, 0, n - 1, l, r, f); }   // closed [l, r]
    S query(int l, int r) { return query(1, 0, n - 1, l, r); }
};

struct AffineSumMod {                                       // example policy: x -> b x + c on sums mod p
    static constexpr long long MOD = 998244353;
    using S = long long; using F = pair<long long, long long>;
    static S e() { return 0; }
    static F id() { return {1, 0}; }
    static S op(S a, S b) { return (a + b) % MOD; }
    static S apply(const F& f, S s, int len) { return (f.first * s + f.second * len) % MOD; }
    static F compose(const F& g, const F& f) { return {g.first * f.first % MOD, (g.first * f.second + g.second) % MOD}; }  // g after f
};
// usage: LazySeg<AffineSumMod> seg(vector<long long>(n, 0)); seg.update(l, r, {b, c}); seg.query(l, r);
```

```java
static class LazyAffine {                                  // x -> b x + c on range sums mod MOD
    static final long MOD = 998244353;
    final int n; final long[] sum, mb, mc;                 // mb, mc: pending map (identity = (1, 0))
    LazyAffine(long[] a) {
        n = a.length; sum = new long[4 * n]; mb = new long[4 * n]; mc = new long[4 * n];
        Arrays.fill(mb, 1); build(1, 0, n - 1, a);
    }
    void build(int v, int l, int r, long[] a) {
        if (l == r) { sum[v] = a[l] % MOD; return; }
        int m = (l + r) >> 1;
        build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a);
        sum[v] = (sum[2 * v] + sum[2 * v + 1]) % MOD;
    }
    void applyNode(int v, int len, long b, long c) {
        sum[v] = (b * sum[v] + c * len) % MOD;
        mc[v] = (b * mc[v] + c) % MOD;                     // new map after the old one
        mb[v] = b * mb[v] % MOD;
    }
    void push(int v, int l, int m, int r) {
        if (mb[v] != 1 || mc[v] != 0) {
            applyNode(2 * v, m - l + 1, mb[v], mc[v]); applyNode(2 * v + 1, r - m, mb[v], mc[v]);
            mb[v] = 1; mc[v] = 0;
        }
    }
    void update(int v, int l, int r, int ql, int qr, long b, long c) {
        if (qr < l || r < ql) return;
        if (ql <= l && r <= qr) { applyNode(v, r - l + 1, b, c); return; }
        int m = (l + r) >> 1;
        push(v, l, m, r);
        update(2 * v, l, m, ql, qr, b, c); update(2 * v + 1, m + 1, r, ql, qr, b, c);
        sum[v] = (sum[2 * v] + sum[2 * v + 1]) % MOD;
    }
    long query(int v, int l, int r, int ql, int qr) {
        if (qr < l || r < ql) return 0;
        if (ql <= l && r <= qr) return sum[v];
        int m = (l + r) >> 1;
        push(v, l, m, r);
        return (query(2 * v, l, m, ql, qr) + query(2 * v + 1, m + 1, r, ql, qr)) % MOD;
    }
    void update(int l, int r, long b, long c) { update(1, 0, n - 1, l, r, b, c); }   // closed [l, r]
    long query(int l, int r) { return query(1, 0, n - 1, l, r); }
}
```

## 4. Recognising the pattern

- **Both updates and queries are on ranges** ("add to all soldiers in $[l,r]$", "paint segment", "flip all bits", "multiply a range") → lazy propagation. If only one of them is a range, a [BIT](01-fenwick-tree.md) or plain tree usually suffices.
- **The update has the form "every element becomes $g(x)$" with $g$ in a small closed family** (adds, assignments, affine maps, xor masks, flips, progressions) → derive `apply` and `compose`.
- **"Assign" anywhere** → the tag needs a "no assignment" state distinct from every legal value; use a flag, not a magic number like $0$ or $-1$.
- **Updates like `a[i] %= x`, `a[i] = sqrt(a[i])`, `a[i] = min(a[i], x)`** → no lazy tag; see potential arguments and beats in [the advanced file](04-segment-tree-advanced-descent-merging-beats.md).
- **Bitwise updates (xor/and/or) with sum queries** → split into one count per bit (20–30 bits), or for and/or use "if the update changes nothing in this node, stop".
- **Tree path / subtree updates** → flatten with an Euler tour (subtree = range) or [HLD](../10-Trees/04-heavy-light-decomposition.md) (path = $O(\log n)$ ranges), then lazy.
- **Offline, many sorted assignments** ("paint", "sort segment ascending") can sometimes be done with a set of intervals (Chtholly / ODT) instead; see §7.

## 5. Worked examples (graded)

### Example 1 — Range Updates and Sums (assign + add)  ·  ★ ≈1900

- **Source:** [CSES 1735 · Range Updates and Sums](https://cses.fi/problemset/task/1735)
- **Difficulty:** ≈1900 (est.)
- **Problem:** $n, q \le 2\cdot10^5$, values $\le 10^6$. `1 a b x`: add $x$ to $t_a..t_b$; `2 a b x`: set $t_a..t_b$ to $x$; `3 a b`: print the sum.
- **Thinking from first principles:** sums are a monoid; adds and sets are maps whose compositions stay in "set $c$ or add $v$" (§1).
  The failure mode is the composition order: if a node holds "set 5" and receives "add 2", the result is "set 7", not "add 2" and not "set 5".
  Magnitudes: up to $2\cdot10^5$ adds of $10^6$ on each element, times $2\cdot10^5$ elements $\approx 4\cdot10^{16}$ → 64-bit.

<details><summary>Solution</summary>

Tag = `(isSet, val)`. $O((n+q)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int n;
vector<long long> sm, tg;
vector<char> st;                                              // st[v] = 1: pending "set tg[v]"; else pending "add tg[v]"
void applyNode(int v, int len, bool isSet, long long x) {
    if (isSet) { sm[v] = x * len; tg[v] = x; st[v] = 1; }
    else { sm[v] += x * len; tg[v] += x; }                     // add after set keeps it a set (of a larger value)
}
void push(int v, int l, int m, int r) {
    if (st[v] || tg[v]) {
        applyNode(2 * v, m - l + 1, st[v], tg[v]); applyNode(2 * v + 1, r - m, st[v], tg[v]);
        st[v] = 0; tg[v] = 0;
    }
}
void build(int v, int l, int r, const vector<long long>& a) {
    if (l == r) { sm[v] = a[l]; return; }
    int m = (l + r) >> 1;
    build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a);
    sm[v] = sm[2 * v] + sm[2 * v + 1];
}
void update(int v, int l, int r, int ql, int qr, bool isSet, long long x) {
    if (qr < l || r < ql) return;
    if (ql <= l && r <= qr) { applyNode(v, r - l + 1, isSet, x); return; }
    int m = (l + r) >> 1;
    push(v, l, m, r);
    update(2 * v, l, m, ql, qr, isSet, x); update(2 * v + 1, m + 1, r, ql, qr, isSet, x);
    sm[v] = sm[2 * v] + sm[2 * v + 1];
}
long long query(int v, int l, int r, int ql, int qr) {
    if (qr < l || r < ql) return 0;
    if (ql <= l && r <= qr) return sm[v];
    int m = (l + r) >> 1;
    push(v, l, m, r);
    return query(2 * v, l, m, ql, qr) + query(2 * v + 1, m + 1, r, ql, qr);
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int q; cin >> n >> q;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    sm.assign(4 * n, 0); tg.assign(4 * n, 0); st.assign(4 * n, 0);
    build(1, 0, n - 1, a);
    while (q--) {
        int type, l, r; cin >> type >> l >> r; l--; r--;
        if (type == 3) { cout << query(1, 0, n - 1, l, r) << '\n'; continue; }
        long long x; cin >> x;
        update(1, 0, n - 1, l, r, type == 2, x);
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long[] sm, tg; static boolean[] st;
    static void applyNode(int v, int len, boolean isSet, long x) {
        if (isSet) { sm[v] = x * len; tg[v] = x; st[v] = true; }
        else { sm[v] += x * len; tg[v] += x; }
    }
    static void push(int v, int l, int m, int r) {
        if (st[v] || tg[v] != 0) {
            applyNode(2 * v, m - l + 1, st[v], tg[v]); applyNode(2 * v + 1, r - m, st[v], tg[v]);
            st[v] = false; tg[v] = 0;
        }
    }
    static void build(int v, int l, int r, long[] a) {
        if (l == r) { sm[v] = a[l]; return; }
        int m = (l + r) >> 1;
        build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a);
        sm[v] = sm[2 * v] + sm[2 * v + 1];
    }
    static void update(int v, int l, int r, int ql, int qr, boolean isSet, long x) {
        if (qr < l || r < ql) return;
        if (ql <= l && r <= qr) { applyNode(v, r - l + 1, isSet, x); return; }
        int m = (l + r) >> 1;
        push(v, l, m, r);
        update(2 * v, l, m, ql, qr, isSet, x); update(2 * v + 1, m + 1, r, ql, qr, isSet, x);
        sm[v] = sm[2 * v] + sm[2 * v + 1];
    }
    static long query(int v, int l, int r, int ql, int qr) {
        if (qr < l || r < ql) return 0;
        if (ql <= l && r <= qr) return sm[v];
        int m = (l + r) >> 1;
        push(v, l, m, r);
        return query(2 * v, l, m, ql, qr) + query(2 * v + 1, m + 1, r, ql, qr);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), q = in.nextInt();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        sm = new long[4 * n]; tg = new long[4 * n]; st = new boolean[4 * n];
        build(1, 0, n - 1, a);
        while (q-- > 0) {
            int type = in.nextInt(), l = in.nextInt() - 1, r = in.nextInt() - 1;
            if (type == 3) out.println(query(1, 0, n - 1, l, r));
            else update(1, 0, n - 1, l, r, type == 2, in.nextLong());
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
6 5
2 3 1 1 5 3
3 3 5
1 2 4 2
3 3 5
2 2 4 5
3 3 5
out:
7
11
15
-->
<!-- test
in:
3 6
1 1 1
2 1 3 4
1 2 3 3
3 1 3
2 2 2 0
1 1 2 1
3 1 3
out:
18
13
-->
<!-- test
in:
1 3
1000000
1 1 1 1000000
3 1 1
3 1 1
out:
2000000
2000000
-->

</details>

### Example 2 — XOR on Segment (per-bit counts)  ·  ★ 2000

- **Source:** [CF 242E · XOR on Segment](https://codeforces.com/problemset/problem/242/E) — 2000
- **Difficulty:** 2000
- **Problem:** $n \le 10^5$ values $< 2^{20}$; $m \le 5\cdot10^4$ operations: `1 l r` print the sum; `2 l r x` xor every element in the range with $x$.
- **Thinking from first principles:** is the new sum computable from the old sum? No: $\sum (a_i \oplus x)$ depends on the bits.
  But **per bit** it is: if a node has $\text{cnt}_b$ elements with bit $b$ set, xoring with $x$ (bit $b$ set) makes it $\text{len} - \text{cnt}_b$.
  So the summary is the vector of 20 counts, the tag is a mask, and masks compose by xor. Width 20 multiplies time and memory by 20: $4n\cdot 20$ ints = 32 MB, fine.

<details><summary>Solution</summary>

$O(20\,(n + m)\log n)$. Sum $=\sum_b 2^b\,\text{cnt}_b$ in 64 bits ($10^5 \cdot 2^{20} \approx 10^{11}$).

```cpp
#include <bits/stdc++.h>
using namespace std;
const int B = 20;

int n;
vector<array<int, B>> cnt;
vector<int> lz;
void applyNode(int v, int len, int x) {
    for (int b = 0; b < B; b++) if (x >> b & 1) cnt[v][b] = len - cnt[v][b];
    lz[v] ^= x;
}
void push(int v, int l, int m, int r) {
    if (lz[v]) { applyNode(2 * v, m - l + 1, lz[v]); applyNode(2 * v + 1, r - m, lz[v]); lz[v] = 0; }
}
void pull(int v) { for (int b = 0; b < B; b++) cnt[v][b] = cnt[2 * v][b] + cnt[2 * v + 1][b]; }
void build(int v, int l, int r, const vector<int>& a) {
    if (l == r) { for (int b = 0; b < B; b++) cnt[v][b] = a[l] >> b & 1; return; }
    int m = (l + r) >> 1;
    build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a); pull(v);
}
void update(int v, int l, int r, int ql, int qr, int x) {
    if (qr < l || r < ql) return;
    if (ql <= l && r <= qr) { applyNode(v, r - l + 1, x); return; }
    int m = (l + r) >> 1;
    push(v, l, m, r);
    update(2 * v, l, m, ql, qr, x); update(2 * v + 1, m + 1, r, ql, qr, x); pull(v);
}
long long query(int v, int l, int r, int ql, int qr) {
    if (qr < l || r < ql) return 0;
    if (ql <= l && r <= qr) { long long s = 0; for (int b = 0; b < B; b++) s += (long long)cnt[v][b] << b; return s; }
    int m = (l + r) >> 1;
    push(v, l, m, r);
    return query(2 * v, l, m, ql, qr) + query(2 * v + 1, m + 1, r, ql, qr);
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    cin >> n;
    vector<int> a(n);
    for (auto& x : a) cin >> x;
    cnt.assign(4 * n, {}); lz.assign(4 * n, 0);
    build(1, 0, n - 1, a);
    int m; cin >> m;
    while (m--) {
        int type, l, r; cin >> type >> l >> r; l--; r--;
        if (type == 1) cout << query(1, 0, n - 1, l, r) << '\n';
        else { int x; cin >> x; update(1, 0, n - 1, l, r, x); }
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final int B = 20;
    static int[][] cnt; static int[] lz;                      // cnt[b][v]: one array per bit
    static void applyNode(int v, int len, int x) {
        for (int b = 0; b < B; b++) if ((x >> b & 1) == 1) cnt[b][v] = len - cnt[b][v];
        lz[v] ^= x;
    }
    static void push(int v, int l, int m, int r) {
        if (lz[v] != 0) { applyNode(2 * v, m - l + 1, lz[v]); applyNode(2 * v + 1, r - m, lz[v]); lz[v] = 0; }
    }
    static void pull(int v) { for (int b = 0; b < B; b++) cnt[b][v] = cnt[b][2 * v] + cnt[b][2 * v + 1]; }
    static void build(int v, int l, int r, int[] a) {
        if (l == r) { for (int b = 0; b < B; b++) cnt[b][v] = a[l] >> b & 1; return; }
        int m = (l + r) >> 1;
        build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a); pull(v);
    }
    static void update(int v, int l, int r, int ql, int qr, int x) {
        if (qr < l || r < ql) return;
        if (ql <= l && r <= qr) { applyNode(v, r - l + 1, x); return; }
        int m = (l + r) >> 1;
        push(v, l, m, r);
        update(2 * v, l, m, ql, qr, x); update(2 * v + 1, m + 1, r, ql, qr, x); pull(v);
    }
    static long query(int v, int l, int r, int ql, int qr) {
        if (qr < l || r < ql) return 0;
        if (ql <= l && r <= qr) { long s = 0; for (int b = 0; b < B; b++) s += (long) cnt[b][v] << b; return s; }
        int m = (l + r) >> 1;
        push(v, l, m, r);
        return query(2 * v, l, m, ql, qr) + query(2 * v + 1, m + 1, r, ql, qr);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        cnt = new int[B][4 * n]; lz = new int[4 * n];
        build(1, 0, n - 1, a);
        int m = in.nextInt();
        while (m-- > 0) {
            int type = in.nextInt(), l = in.nextInt() - 1, r = in.nextInt() - 1;
            if (type == 1) out.println(query(1, 0, n - 1, l, r));
            else update(1, 0, n - 1, l, r, in.nextInt());
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
5
4 10 3 13 7
8
1 2 4
2 1 3 3
1 2 4
1 3 3
2 2 5 5
1 1 5
2 1 2 10
1 2 3
out:
26
22
0
34
11
-->
<!-- test
in:
1
1048575
3
1 1 1
2 1 1 1048575
1 1 1
out:
1048575
0
-->

</details>

### Example 3 — Polynomial Queries (arithmetic-progression tags)  ·  ★ ≈2000

- **Source:** [CSES 1736 · Polynomial Queries](https://cses.fi/problemset/task/1736)
- **Difficulty:** ≈2000 (est.)
- **Problem:** $n, q \le 2\cdot10^5$. `1 a b`: add $1$ to $t_a$, $2$ to $t_{a+1}$, …, $b - a + 1$ to $t_b$. `2 a b`: print $t_a + \dots + t_b$.
- **Thinking from first principles:** the update is not "the same map on every element" — it depends on the position. Make it uniform
  *relative to the node*: on a fully covered node $[l, r]$ the update adds $A + D\cdot k$ at offset $k$, with $A = l - a + 1$, $D = 1$.
  Progressions are closed under addition, the node sum is $A\,\text{len} + D\binom{\text{len}}{2}$, and pushing to the right child shifts $A$ by $D\cdot\text{len}_{left}$ (§1).
  (Alternative: two BITs storing coefficients of $i^0$ and $i^1$ — the same idea as the two-BIT trick, one degree higher.)

<details><summary>Solution</summary>

Tags $(A, D)$ as two `long long` arrays. $O((n+q)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int n;
vector<long long> sm, tA, tD;
void applyNode(int v, long long len, long long A, long long D) {
    sm[v] += A * len + D * (len * (len - 1) / 2);
    tA[v] += A; tD[v] += D;
}
void push(int v, int l, int m, int r) {
    if (tA[v] || tD[v]) {
        long long lenL = m - l + 1;
        applyNode(2 * v, lenL, tA[v], tD[v]);
        applyNode(2 * v + 1, r - m, tA[v] + tD[v] * lenL, tD[v]);
        tA[v] = tD[v] = 0;
    }
}
void build(int v, int l, int r, const vector<long long>& a) {
    if (l == r) { sm[v] = a[l]; return; }
    int m = (l + r) >> 1;
    build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a);
    sm[v] = sm[2 * v] + sm[2 * v + 1];
}
void update(int v, int l, int r, int ql, int qr) {             // adds (i - ql + 1) at position i
    if (qr < l || r < ql) return;
    if (ql <= l && r <= qr) { applyNode(v, r - l + 1, l - ql + 1, 1); return; }
    int m = (l + r) >> 1;
    push(v, l, m, r);
    update(2 * v, l, m, ql, qr); update(2 * v + 1, m + 1, r, ql, qr);
    sm[v] = sm[2 * v] + sm[2 * v + 1];
}
long long query(int v, int l, int r, int ql, int qr) {
    if (qr < l || r < ql) return 0;
    if (ql <= l && r <= qr) return sm[v];
    int m = (l + r) >> 1;
    push(v, l, m, r);
    return query(2 * v, l, m, ql, qr) + query(2 * v + 1, m + 1, r, ql, qr);
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int q; cin >> n >> q;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    sm.assign(4 * n, 0); tA.assign(4 * n, 0); tD.assign(4 * n, 0);
    build(1, 0, n - 1, a);
    while (q--) {
        int type, l, r; cin >> type >> l >> r; l--; r--;
        if (type == 1) update(1, 0, n - 1, l, r);
        else cout << query(1, 0, n - 1, l, r) << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long[] sm, tA, tD;
    static void applyNode(int v, long len, long A, long D) {
        sm[v] += A * len + D * (len * (len - 1) / 2);
        tA[v] += A; tD[v] += D;
    }
    static void push(int v, int l, int m, int r) {
        if (tA[v] != 0 || tD[v] != 0) {
            long lenL = m - l + 1;
            applyNode(2 * v, lenL, tA[v], tD[v]);
            applyNode(2 * v + 1, r - m, tA[v] + tD[v] * lenL, tD[v]);
            tA[v] = 0; tD[v] = 0;
        }
    }
    static void build(int v, int l, int r, long[] a) {
        if (l == r) { sm[v] = a[l]; return; }
        int m = (l + r) >> 1;
        build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a);
        sm[v] = sm[2 * v] + sm[2 * v + 1];
    }
    static void update(int v, int l, int r, int ql, int qr) {
        if (qr < l || r < ql) return;
        if (ql <= l && r <= qr) { applyNode(v, r - l + 1, l - ql + 1, 1); return; }
        int m = (l + r) >> 1;
        push(v, l, m, r);
        update(2 * v, l, m, ql, qr); update(2 * v + 1, m + 1, r, ql, qr);
        sm[v] = sm[2 * v] + sm[2 * v + 1];
    }
    static long query(int v, int l, int r, int ql, int qr) {
        if (qr < l || r < ql) return 0;
        if (ql <= l && r <= qr) return sm[v];
        int m = (l + r) >> 1;
        push(v, l, m, r);
        return query(2 * v, l, m, ql, qr) + query(2 * v + 1, m + 1, r, ql, qr);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), q = in.nextInt();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        sm = new long[4 * n]; tA = new long[4 * n]; tD = new long[4 * n];
        build(1, 0, n - 1, a);
        while (q-- > 0) {
            int type = in.nextInt(), l = in.nextInt() - 1, r = in.nextInt() - 1;
            if (type == 1) update(1, 0, n - 1, l, r);
            else out.println(query(1, 0, n - 1, l, r));
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
4 2 3 1 7
2 1 5
1 1 5
2 1 5
out:
17
32
-->
<!-- test
in:
6 4
0 0 0 0 0 0
1 2 5
2 1 6
2 4 4
1 1 6
out:
10
3
-->
<!-- test
in:
1 3
5
1 1 1
1 1 1
2 1 1
out:
7
-->

</details>

### Example 4 — Range Affine Range Sum  ·  ★ ≈2000

- **Source:** [AtCoder PRACTICE2 K · Range Affine Range Sum](https://atcoder.jp/contests/practice2/tasks/practice2_k)
- **Difficulty:** ≈2000 (est.)
- **Problem:** $N, Q \le 5\cdot10^5$, values $< 998244353$. `0 l r b c`: $a_i \leftarrow b\,a_i + c$ for $l \le i < r$; `1 l r`: print $\sum_{l \le i < r} a_i \bmod 998244353$. (0-indexed, half-open.)
- **Thinking from first principles:** affine maps distribute over sums ($\sum (b x_i + c) = b\sum x_i + c\cdot\text{len}$) and are closed
  under composition: $(b_2, c_2)\circ(b_1,c_1) = (b_2b_1, b_2c_1+c_2)$. This is the "universal" lazy tree; use the policy template in C++
  and the `LazyAffine` class in Java verbatim. Every product of two residues is $< 2^{60}$, so 64-bit arithmetic with `% MOD` after each product is safe.

<details><summary>Solution</summary>

$O((N + Q)\log N)$. Convert half-open `[l, r)` to the closed interface `[l, r-1]`.

```cpp
#include <bits/stdc++.h>
using namespace std;

template <class P>
struct LazySeg {
    using S = typename P::S; using F = typename P::F;
    int n; vector<S> t; vector<F> lz;
    explicit LazySeg(const vector<S>& a) : n(a.size()), t(4 * a.size()), lz(4 * a.size(), P::id()) { build(1, 0, n - 1, a); }
    void build(int v, int l, int r, const vector<S>& a) {
        if (l == r) { t[v] = a[l]; return; }
        int m = (l + r) >> 1;
        build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a);
        t[v] = P::op(t[2 * v], t[2 * v + 1]);
    }
    void applyNode(int v, int len, const F& f) { t[v] = P::apply(f, t[v], len); lz[v] = P::compose(f, lz[v]); }
    void push(int v, int l, int m, int r) {
        applyNode(2 * v, m - l + 1, lz[v]); applyNode(2 * v + 1, r - m, lz[v]);
        lz[v] = P::id();
    }
    void update(int v, int l, int r, int ql, int qr, const F& f) {
        if (qr < l || r < ql) return;
        if (ql <= l && r <= qr) { applyNode(v, r - l + 1, f); return; }
        int m = (l + r) >> 1;
        push(v, l, m, r);
        update(2 * v, l, m, ql, qr, f); update(2 * v + 1, m + 1, r, ql, qr, f);
        t[v] = P::op(t[2 * v], t[2 * v + 1]);
    }
    S query(int v, int l, int r, int ql, int qr) {
        if (qr < l || r < ql) return P::e();
        if (ql <= l && r <= qr) return t[v];
        int m = (l + r) >> 1;
        push(v, l, m, r);
        return P::op(query(2 * v, l, m, ql, qr), query(2 * v + 1, m + 1, r, ql, qr));
    }
    void update(int l, int r, const F& f) { update(1, 0, n - 1, l, r, f); }
    S query(int l, int r) { return query(1, 0, n - 1, l, r); }
};

struct AffineSumMod {
    static constexpr long long MOD = 998244353;
    using S = long long; using F = pair<long long, long long>;
    static S e() { return 0; }
    static F id() { return {1, 0}; }
    static S op(S a, S b) { return (a + b) % MOD; }
    static S apply(const F& f, S s, int len) { return (f.first * s + f.second * len) % MOD; }
    static F compose(const F& g, const F& f) { return {g.first * f.first % MOD, (g.first * f.second + g.second) % MOD}; }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    LazySeg<AffineSumMod> seg(a);
    while (q--) {
        int type, l, r; cin >> type >> l >> r;
        if (type == 0) { long long b, c; cin >> b >> c; seg.update(l, r - 1, {b, c}); }
        else cout << seg.query(l, r - 1) << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static class LazyAffine {
        static final long MOD = 998244353;
        final int n; final long[] sum, mb, mc;
        LazyAffine(long[] a) {
            n = a.length; sum = new long[4 * n]; mb = new long[4 * n]; mc = new long[4 * n];
            Arrays.fill(mb, 1); build(1, 0, n - 1, a);
        }
        void build(int v, int l, int r, long[] a) {
            if (l == r) { sum[v] = a[l] % MOD; return; }
            int m = (l + r) >> 1;
            build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a);
            sum[v] = (sum[2 * v] + sum[2 * v + 1]) % MOD;
        }
        void applyNode(int v, int len, long b, long c) {
            sum[v] = (b * sum[v] + c * len) % MOD;
            mc[v] = (b * mc[v] + c) % MOD;
            mb[v] = b * mb[v] % MOD;
        }
        void push(int v, int l, int m, int r) {
            if (mb[v] != 1 || mc[v] != 0) {
                applyNode(2 * v, m - l + 1, mb[v], mc[v]); applyNode(2 * v + 1, r - m, mb[v], mc[v]);
                mb[v] = 1; mc[v] = 0;
            }
        }
        void update(int v, int l, int r, int ql, int qr, long b, long c) {
            if (qr < l || r < ql) return;
            if (ql <= l && r <= qr) { applyNode(v, r - l + 1, b, c); return; }
            int m = (l + r) >> 1;
            push(v, l, m, r);
            update(2 * v, l, m, ql, qr, b, c); update(2 * v + 1, m + 1, r, ql, qr, b, c);
            sum[v] = (sum[2 * v] + sum[2 * v + 1]) % MOD;
        }
        long query(int v, int l, int r, int ql, int qr) {
            if (qr < l || r < ql) return 0;
            if (ql <= l && r <= qr) return sum[v];
            int m = (l + r) >> 1;
            push(v, l, m, r);
            return (query(2 * v, l, m, ql, qr) + query(2 * v + 1, m + 1, r, ql, qr)) % MOD;
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), q = in.nextInt();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        LazyAffine seg = new LazyAffine(a);
        while (q-- > 0) {
            int type = in.nextInt(), l = in.nextInt(), r = in.nextInt() - 1;
            if (type == 0) { long b = in.nextLong(), c = in.nextLong(); seg.update(1, 0, n - 1, l, r, b, c); }
            else out.println(seg.query(1, 0, n - 1, l, r));
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
5 7
1 2 3 4 5
1 0 5
0 2 4 100 101
1 0 3
0 1 3 102 103
1 2 5
0 2 5 104 105
1 0 5
out:
15
404
41511
4317767
-->
<!-- test
in:
1 4
998244352
1 0 1
0 0 1 2 3
1 0 1
0 0 1 0 7
out:
998244352
1
-->

</details>

### Example 5 — Circular RMQ  ·  ★ 2200

- **Source:** [CF 52C · Circular RMQ](https://codeforces.com/problemset/problem/52/C) — 2200
- **Difficulty:** 2200
- **Problem:** a circular array of $n \le 2\cdot10^5$ values in $[-10^6, 10^6]$; $m \le 2\cdot10^5$ operations, each a line with two numbers `lf rg` (print the minimum on the circular segment from `lf` to `rg`, 0-indexed) or three numbers `lf rg v` (add $v$ on it). If `lf > rg` the segment wraps around.
- **Thinking from first principles:** add/min is the simplest lazy pair ($\min(x+v) = \min(x) + v$). Two twists that cost people the problem:
  (1) a wrapped segment is the union of $[lf, n-1]$ and $[0, rg]$ — two calls; (2) the operation type is determined by the **number of tokens on the line**,
  so input must be read line by line. The rating comes mostly from these traps. Minimum can drift to $\pm 2\cdot10^{11}$ → 64-bit.

<details><summary>Solution</summary>

Lazy add / min tree; split wrapped segments. Read lines with `getline` / `BufferedReader`. $O((n+m)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int n;
vector<long long> mn, lz;
void applyNode(int v, long long x) { mn[v] += x; lz[v] += x; }
void push(int v) { if (lz[v]) { applyNode(2 * v, lz[v]); applyNode(2 * v + 1, lz[v]); lz[v] = 0; } }
void build(int v, int l, int r, const vector<long long>& a) {
    if (l == r) { mn[v] = a[l]; return; }
    int m = (l + r) >> 1;
    build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a);
    mn[v] = min(mn[2 * v], mn[2 * v + 1]);
}
void update(int v, int l, int r, int ql, int qr, long long x) {
    if (qr < l || r < ql) return;
    if (ql <= l && r <= qr) { applyNode(v, x); return; }
    push(v);
    int m = (l + r) >> 1;
    update(2 * v, l, m, ql, qr, x); update(2 * v + 1, m + 1, r, ql, qr, x);
    mn[v] = min(mn[2 * v], mn[2 * v + 1]);
}
long long query(int v, int l, int r, int ql, int qr) {
    if (qr < l || r < ql) return LLONG_MAX;
    if (ql <= l && r <= qr) return mn[v];
    push(v);
    int m = (l + r) >> 1;
    return min(query(2 * v, l, m, ql, qr), query(2 * v + 1, m + 1, r, ql, qr));
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    cin >> n;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    mn.assign(4 * n, 0); lz.assign(4 * n, 0);
    build(1, 0, n - 1, a);
    int m; cin >> m;
    string line; getline(cin, line);                           // finish the line containing m
    while (m--) {
        getline(cin, line);
        istringstream ss(line);
        vector<long long> v; long long x;
        while (ss >> x) v.push_back(x);
        int l = int(v[0]), r = int(v[1]);
        if (v.size() == 2) {
            long long res = (l <= r) ? query(1, 0, n - 1, l, r) : min(query(1, 0, n - 1, l, n - 1), query(1, 0, n - 1, 0, r));
            cout << res << '\n';
        } else if (l <= r) update(1, 0, n - 1, l, r, v[2]);
        else { update(1, 0, n - 1, l, n - 1, v[2]); update(1, 0, n - 1, 0, r, v[2]); }
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long[] mn, lz;
    static void applyNode(int v, long x) { mn[v] += x; lz[v] += x; }
    static void push(int v) { if (lz[v] != 0) { applyNode(2 * v, lz[v]); applyNode(2 * v + 1, lz[v]); lz[v] = 0; } }
    static void build(int v, int l, int r, long[] a) {
        if (l == r) { mn[v] = a[l]; return; }
        int m = (l + r) >> 1;
        build(2 * v, l, m, a); build(2 * v + 1, m + 1, r, a);
        mn[v] = Math.min(mn[2 * v], mn[2 * v + 1]);
    }
    static void update(int v, int l, int r, int ql, int qr, long x) {
        if (qr < l || r < ql) return;
        if (ql <= l && r <= qr) { applyNode(v, x); return; }
        push(v);
        int m = (l + r) >> 1;
        update(2 * v, l, m, ql, qr, x); update(2 * v + 1, m + 1, r, ql, qr, x);
        mn[v] = Math.min(mn[2 * v], mn[2 * v + 1]);
    }
    static long query(int v, int l, int r, int ql, int qr) {
        if (qr < l || r < ql) return Long.MAX_VALUE;
        if (ql <= l && r <= qr) return mn[v];
        push(v);
        int m = (l + r) >> 1;
        return Math.min(query(2 * v, l, m, ql, qr), query(2 * v + 1, m + 1, r, ql, qr));
    }

    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in), 1 << 16);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = Integer.parseInt(br.readLine().trim());
        long[] a = new long[n];
        StringTokenizer st = new StringTokenizer(br.readLine());
        for (int i = 0; i < n; i++) a[i] = Long.parseLong(st.nextToken());
        mn = new long[4 * n]; lz = new long[4 * n];
        build(1, 0, n - 1, a);
        int m = Integer.parseInt(br.readLine().trim());
        while (m-- > 0) {
            st = new StringTokenizer(br.readLine());
            int l = Integer.parseInt(st.nextToken()), r = Integer.parseInt(st.nextToken());
            if (!st.hasMoreTokens()) {
                long res = l <= r ? query(1, 0, n - 1, l, r) : Math.min(query(1, 0, n - 1, l, n - 1), query(1, 0, n - 1, 0, r));
                out.println(res);
            } else {
                long v = Long.parseLong(st.nextToken());
                if (l <= r) update(1, 0, n - 1, l, r, v);
                else { update(1, 0, n - 1, l, n - 1, v); update(1, 0, n - 1, 0, r, v); }
            }
        }
        out.flush();
    }
}
```

<!-- test
in:
4
1 2 3 4
4
3 0
3 0 -1
0 1
2 1
out:
1
0
0
-->
<!-- test
in:
1
-1000000
3
0 0
0 0 1000000
0 0
out:
-1000000
0
-->
<!-- test
in:
5
5 4 3 2 1
4
4 1 10
2 0
1 3 -2
3 2
out:
2
0
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Push before you descend, pull after you return.** Forgetting `push` in `query` is the most common bug — it passes tests with only point queries.
2. **Composition order.** `lz[child] = compose(new, old)` — the parent's tag is newer than the child's. For commutative tags (add, xor) the order does not matter, which hides the bug until you add "assign".
3. **"No tag" must be unrepresentable as a real tag.** Assigning $0$ is a real update; use a flag or the identity of the map family ($(1, 0)$ for affine).
4. **Multiply by the length** when a tag changes a sum. Store the length or pass `r - l + 1`; for an AP tag also shift the right child's start.
5. **Do not push at leaves.** In the 4n layout, children of a leaf may be out of bounds. With the "fully covered → apply and return" structure, recursion never pushes at a leaf; if you write a different structure, guard with `l == r`.
6. **Overflow inside tags.** Accumulated adds and AP coefficients grow; `len * (len - 1) / 2 * D` needs 64-bit. In modular trees reduce after every multiplication (`b * sum % MOD + c * len % MOD`).
7. **Line-based input** (CF 52C): read the whole line and count tokens; in Java use `BufferedReader` + `StringTokenizer`, not `Scanner.hasNextInt()`.
8. **Width of the summary** (per-bit counts, 26 letters) multiplies the constant; in Java store `int[bit][node]` (one array per bit) to stay cache-friendly and allocation-free.
9. **Wrapped / circular ranges**: split into two calls; never "double the array" for updates (each element would exist twice).
10. **Range assign on a sparse coordinate set** (coordinates up to $10^9$): compress the *endpoints* $l$ and $r+1$, then each tree leaf is an elementary interval with a weight (length); or use a dynamic tree ([advanced](04-segment-tree-advanced-descent-merging-beats.md)).
11. **Java recursion cost**: each call passes `(v, l, r, ql, qr)`; for $5\cdot10^5$ queries this is fine within 2–3 s. If TLE, make `ql, qr` (and the update value) static fields instead of parameters.
12. **Reset between test cases** only the first $4n$ cells for the current $n$, not a global $4\cdot\max n$ array per test (multi-test TLE).

## 7. Going further (toward 2400–2600+)

- **Matrix / linear-map tags**: tags that are matrices acting on vectors (e.g. Fibonacci shifts, [CF 718C · Sasha and Array](https://codeforces.com/problemset/problem/718/C) — 2300; [CF 446C · DZY Loves Fibonacci Numbers](https://codeforces.com/problemset/problem/446/C) — 2400 with Fibonacci-progression tags).
- **Multiplicative tags with factor bookkeeping**: [CF 1114F · Please, another Queries on Array?](https://codeforces.com/problemset/problem/1114/F) — 2400 (range multiply, query $\varphi$ of a product: lazy product + bitmask of primes).
- **26 lazy trees for sorting a substring**: [CF 558E · A Simple Task](https://codeforces.com/problemset/problem/558/E) — 2300 (count letters, then assign runs).
- **Lazy on Euler tours**: [CF 877E · Danil and a Part-time Job](https://codeforces.com/problemset/problem/877/E) — 2000, [CF 620E · New Year Tree](https://codeforces.com/problemset/problem/620/E) — 2100, [CF 343D · Water Tree](https://codeforces.com/problemset/problem/343/D) — 2100.
- **Potential-based "lazy"** (range mod / sqrt / chmin) and **segment tree beats**: [advanced segment trees](04-segment-tree-advanced-descent-merging-beats.md).
- **Interval sets ("Chtholly tree")** for random-data assign-heavy problems: [CF 896C · Willem, Chtholly and Seniorious](https://codeforces.com/problemset/problem/896/C) — 2600; the amortisation relies on random input, so it is not a general replacement.
- **Lazy + persistence** requires either permanent tags or copying children on push ([persistent structures](08-persistent-data-structures.md)).

## 8. Practice ladder

**1500–1900**
- [ ] [CSES 1651 · Range Update Queries](https://cses.fi/problemset/task/1651)
- [ ] [CF 1872E · Data Structures Fan](https://codeforces.com/problemset/problem/1872/E) — 1500
- [ ] [AtCoder PRACTICE2 L · Lazy Segment Tree](https://atcoder.jp/contests/practice2/tasks/practice2_l)
- [ ] [CSES 1735 · Range Updates and Sums](https://cses.fi/problemset/task/1735)
- [ ] [CF 482B · Interesting Array](https://codeforces.com/problemset/problem/482/B) — 1800

**1900–2200**
- [ ] [CSES 1736 · Polynomial Queries](https://cses.fi/problemset/task/1736)
- [ ] [AtCoder PRACTICE2 K · Range Affine Range Sum](https://atcoder.jp/contests/practice2/tasks/practice2_k)
- [ ] [CF 242E · XOR on Segment](https://codeforces.com/problemset/problem/242/E) — 2000
- [ ] [CF 877E · Danil and a Part-time Job](https://codeforces.com/problemset/problem/877/E) — 2000
- [ ] [CF 383C · Propagating tree](https://codeforces.com/problemset/problem/383/C) — 2000
- [ ] [CF 343D · Water Tree](https://codeforces.com/problemset/problem/343/D) — 2100
- [ ] [CF 620E · New Year Tree](https://codeforces.com/problemset/problem/620/E) — 2100
- [ ] [CF 52C · Circular RMQ](https://codeforces.com/problemset/problem/52/C) — 2200

**2200–2600**
- [ ] [CF 558E · A Simple Task](https://codeforces.com/problemset/problem/558/E) — 2300
- [ ] [CF 718C · Sasha and Array](https://codeforces.com/problemset/problem/718/C) — 2300
- [ ] [CF 145E · Lucky Queries](https://codeforces.com/problemset/problem/145/E) — 2400
- [ ] [CF 1114F · Please, another Queries on Array?](https://codeforces.com/problemset/problem/1114/F) — 2400
- [ ] [CF 446C · DZY Loves Fibonacci Numbers](https://codeforces.com/problemset/problem/446/C) — 2400
- [ ] [CF 444C · DZY Loves Colors](https://codeforces.com/problemset/problem/444/C) — 2400

## 9. LeetCode / FAANG cross-reference

- [LC 732 · My Calendar III](https://leetcode.com/problems/my-calendar-iii/) — Hard — range add, global max on a dynamic tree over $[0, 10^9]$ (or a sorted-map sweep).
- [LC 731 · My Calendar II](https://leetcode.com/problems/my-calendar-ii/) — Medium — same tree, reject if range max would reach 3.
- [LC 699 · Falling Squares](https://leetcode.com/problems/falling-squares/) — Hard — range assign, range max over compressed coordinates.
- [LC 715 · Range Module](https://leetcode.com/problems/range-module/) — Hard — range assign 0/1, range "all ones?" query; an interval map is the interview-friendly answer.
- [LC 2569 · Handling Sum Queries After Update](https://leetcode.com/problems/handling-sum-queries-after-update/) — Hard — range flip, count of ones: the flip tag of §1.
- [LC 2276 · Count Integers in Intervals](https://leetcode.com/problems/count-integers-in-intervals/) — Hard — range assign-to-1 with a dynamic tree, or merging intervals in an ordered map.

Rare in interviews: lazy propagation is considered beyond the expected toolkit at most companies; mention it, then implement the ordered-map solution unless asked.

## 10. Self-check

1. State the two conditions under which a lazy tag exists for an (update, query) pair.
2. Derive `compose` for affine maps and show that it handles assign and add as special cases.
3. A node holds "add 3"; it receives "set 5", then "add 2". What is its tag, and what does it do to a sum over 4 elements?
4. Why must `query` push, even though it does not modify anything?
5. Write the push for an arithmetic-progression tag. Why does only the right child's tag change?
6. Why is there no lazy tag for "$a_i \leftarrow a_i \bmod x$" with sum queries? What do you use instead?
7. What changes if tags must never be pushed (persistent tree)?

<details><summary>Answers</summary>

1. The new summary must be computable from the old summary (plus length), i.e. maps distribute over the combine; and compositions of updates must be representable in the same tag family in $O(1)$.
2. $(b_2,c_2)\circ(b_1,c_1) = (b_2b_1, b_2c_1 + c_2)$. Add $v$ is $(1, v)$; assign $c$ is $(0, c)$: composing assign after anything gives $(0, c)$, add after assign gives $(0, c+v)$.
3. "set 7"; the sum becomes $28$.
4. Children's stored summaries do not yet include the pending tag; reading them without pushing returns stale values.
5. Left child: $(A, D)$; right child: $(A + D\cdot\text{len}_{left}, D)$; only the right child's offset-0 position differs from the parent's.
6. The new sum depends on every individual value, not on the summary. Use the potential argument: recurse while `max >= x` (each affected element at least halves), see the advanced file.
7. Use permanent tags: a node's value includes its own tag; queries accumulate tags along the path; updates create new nodes instead of modifying children.

</details>
