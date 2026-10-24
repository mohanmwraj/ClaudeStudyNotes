# Treaps and Implicit Treaps

> **Band:** 🟠 2000–2500 · **Priority:** ⚡ · **FAANG:** low · **Prerequisites:** [segment tree basics](02-segment-tree-basics.md), [lazy propagation](03-lazy-propagation.md), [probability and expectation](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md)
> **You can say you know this when:** you can write `split` and `merge` from memory in both languages, use them to build an ordered multiset with order statistics (Java's missing PBDS), and an implicit treap (sequence keyed by position) that supports insert/erase at an index, reversal with a lazy flag, cut-and-paste, cyclic shifts and range sums — and you can explain why the expected depth is $O(\log n)$.

## 1. First principles — why this works

**What we want.** A *sequence* or an *ordered set* that supports, in $O(\log n)$: insert/erase anywhere, "k-th element", "how many are $< x$", and — the part arrays and segment trees
cannot do — **restructuring**: cut a block out and paste it elsewhere, reverse a block, concatenate two sequences. A segment tree has a fixed shape; a balanced BST does not.

**Why not a plain BST?** Its depth depends on the insertion order (sorted input → a chain, $O(n)$). Classical fixes (AVL, red–black) maintain balance with rotations and many cases.

**The treap idea.** Give every node a **random priority** and require two orders at once: BST order on keys and *heap* order on priorities (a parent's priority exceeds its children's).
For distinct keys and priorities there is exactly **one** such tree: the root must be the node with the highest priority, its left subtree is the treap of the smaller keys, its
right subtree the treap of the larger keys (recursively). So the tree is the BST we would get by **inserting the keys in decreasing priority order** — i.e. in a uniformly random order —
whatever order the operations actually came in. Random BSTs are shallow.

**Expected depth $O(\log n)$ — proof sketch.** Sort the keys: $x_1 < \dots < x_n$. Claim: $x_j$ is an ancestor of $x_i$ iff $x_j$ has the highest priority among $x_{\min(i,j)}, \dots, x_{\max(i,j)}$.
(Until some key of that interval becomes a root of a subtree containing both, they stay in the same subtree; the first one chosen separates them unless it is $x_j$ or $x_i$.)
With random priorities that has probability $\frac{1}{|i - j| + 1}$, so

$$\mathbb E[\operatorname{depth}(x_i)] = \sum_{j \ne i} \frac{1}{|i-j|+1} \le 2\left(\frac12 + \frac13 + \dots + \frac1n\right) < 2\ln n .$$

The expected depth is about $2\ln n \approx 1.39\log_2 n$, and large deviations are exponentially unlikely, so recursion depth is never an issue in practice.

**Two primitives do everything.**

- `split(t, k) → (A, B)`: $A$ = keys $< k$, $B$ = keys $\ge k$. At the root: if its key $< k$, the root and its left subtree go to $A$, and we split the right subtree recursively, attaching the
  left part as the root's new right child. Symmetric otherwise. One root-to-leaf path: $O(\text{depth})$.
- `merge(A, B)` (every key of $A$ < every key of $B$): the root of the result is whichever root has the higher priority; recurse into its right (if from $A$) or left (if from $B$) subtree. $O(\text{depth}(A) + \text{depth}(B))$.

Heap order is preserved because merge always puts the higher priority on top; BST order because merge only ever concatenates.

- **insert** $x$: `split(t, x) → (A, B)`, `t = merge(merge(A, node(x)), B)`.
- **erase one** $x$: `split(t, x) → (A, B)`, split one element off $B$; if it equals $x$ drop it; merge the rest.
- With a **size** field in each node: k-th smallest and "count $< x$" are walks, like descents on a segment tree.

**Implicit treap: the key is the position.** For a *sequence*, do not store keys at all. The position of a node is (number of nodes before it) = size of its left subtree plus everything
skipped on the way down. So split *by count*: `split(t, k)` puts the first $k$ elements in $A$. Insertion at index $i$ = split at $i$, merge three parts. The BST order is the sequence order,
and **merge is concatenation**. Now:

- *cut and paste* $[l, r]$ to the end: split into $A\,|\,B\,|\,C$, merge as $A\,C\,B$;
- *cyclic shift* of $[l, r]$ by one to the right: split $B$ into $B_1\,|\,b_r$, rebuild as $b_r\,B_1$;
- *reverse* $[l, r]$: split out $B$ and set a **lazy flag** at its root; pushing the flag swaps the node's children and toggles the flag on both children. Reversing a sequence = reversing both halves and swapping them, recursively — exactly what the flag does when pushed;
- *range sums / range adds*: each node keeps an aggregate of its subtree (sum, min, …) and optional lazy tags, exactly as in a [lazy segment tree](03-lazy-propagation.md). `push` before looking at children, `pull` after changing them.

**Comparison with `__gnu_cxx::rope` (🧊).** libstdc++ ships `#include <ext/rope>`: a balanced tree of string chunks with $O(\log n)$ `insert`, `erase`, `substr`, concatenation, and cheap
copying (persistent-ish). It cannot reverse or maintain custom aggregates, has a large constant, and is GCC-only. An implicit treap covers all of that and is portable — learn the treap, know the rope exists.

## 2. Formulas, definitions and identities

| Quantity / operation | Value |
|---|---|
| $P(x_j \text{ ancestor of } x_i)$ | $1/(\lvert i-j\rvert + 1)$ |
| expected depth | $\sum_{j\ne i} \frac{1}{\lvert i-j\rvert+1} < 2\ln n$ |
| expected cost of split / merge / insert / erase | $O(\log n)$ |
| size field | $\text{sz}(t) = 1 + \text{sz}(L) + \text{sz}(R)$ |
| position of the root inside its subtree | $\text{sz}(L) + 1$ (1-based) |
| split by count, going right | $k \leftarrow k - \text{sz}(L) - 1$ |
| reverse flag push | swap$(L, R)$; flag$(L)$ ^= 1; flag$(R)$ ^= 1 |
| cut $[l,r]$, paste at end | $A\,B\,C \to A\,C\,B$ with $\lvert A\rvert = l-1$, $\lvert B\rvert = r-l+1$ |
| build from a sorted array | $O(n)$ with a stack (Cartesian tree), or $n$ merges in $O(n \log n)$ expected |

## 3. Implementation (C++ and Java)

### 3.1 Ordered multiset treap (insert, erase one, count less, k-th)

Array-based nodes, node 0 = null. Duplicates are separate nodes. Priorities from a fixed-seed generator (contests: seed from the clock to resist adaptive tests).

```cpp
struct Treap {
    vector<int> L, R, sz; vector<unsigned> pri; vector<long long> key;
    mt19937 rng{20261023};
    Treap() { L.push_back(0); R.push_back(0); sz.push_back(0); pri.push_back(0); key.push_back(0); }   // node 0 = null
    int node(long long k) { L.push_back(0); R.push_back(0); sz.push_back(1); pri.push_back(rng()); key.push_back(k); return int(key.size()) - 1; }
    void pull(int t) { sz[t] = 1 + sz[L[t]] + sz[R[t]]; }
    void split(int t, long long k, int& a, int& b) {          // a: keys < k, b: keys >= k
        if (!t) { a = b = 0; return; }
        if (key[t] < k) { split(R[t], k, R[t], b); a = t; } else { split(L[t], k, a, L[t]); b = t; }
        pull(t);
    }
    int merge(int a, int b) {                                  // all keys of a <= all keys of b
        if (!a || !b) return a | b;
        if (pri[a] > pri[b]) { R[a] = merge(R[a], b); pull(a); return a; }
        L[b] = merge(a, L[b]); pull(b); return b;
    }
    int root = 0;
    void insert(long long k) { int a, b; split(root, k, a, b); root = merge(merge(a, node(k)), b); }
    bool eraseOne(long long k) {
        int a, b, c; split(root, k, a, b); split(b, k + 1, b, c);   // b = all copies of k
        bool found = b != 0;
        if (found) b = merge(L[b], R[b]);                      // drop b's root: one copy
        root = merge(merge(a, b), c);
        return found;
    }
    int countLess(long long k) const {
        int t = root, res = 0;
        while (t) { if (key[t] < k) { res += sz[L[t]] + 1; t = R[t]; } else t = L[t]; }
        return res;
    }
    long long kth(int k) const {                               // 1-based; caller ensures 1 <= k <= size
        int t = root;
        while (true) {
            if (k <= sz[L[t]]) t = L[t];
            else if (k == sz[L[t]] + 1) return key[t];
            else { k -= sz[L[t]] + 1; t = R[t]; }
        }
    }
};
```

```java
static class Treap {
    int[] L, R, sz, pri; long[] key; int size = 1, root = 0;   // node 0 = null
    final Random rng = new Random(20261023);
    Treap(int cap) { L = new int[cap + 1]; R = new int[cap + 1]; sz = new int[cap + 1]; pri = new int[cap + 1]; key = new long[cap + 1]; }
    int node(long k) { sz[size] = 1; pri[size] = rng.nextInt(); key[size] = k; return size++; }
    void pull(int t) { sz[t] = 1 + sz[L[t]] + sz[R[t]]; }
    int sa, sb;                                                // split results (Java has no out-parameters)
    void split(int t, long k) {                                // sa: keys < k, sb: keys >= k
        if (t == 0) { sa = sb = 0; return; }
        if (key[t] < k) { split(R[t], k); R[t] = sa; sa = t; } else { split(L[t], k); L[t] = sb; sb = t; }
        pull(t);
    }
    int merge(int a, int b) {
        if (a == 0 || b == 0) return a | b;
        if (pri[a] > pri[b]) { R[a] = merge(R[a], b); pull(a); return a; }
        L[b] = merge(a, L[b]); pull(b); return b;
    }
    void insert(long k) { split(root, k); int a = sa, b = sb; root = merge(merge(a, node(k)), b); }
    boolean eraseOne(long k) {
        split(root, k); int a = sa, rest = sb;
        split(rest, k + 1); int b = sa, c = sb;
        boolean found = b != 0;
        if (found) b = merge(L[b], R[b]);
        root = merge(merge(a, b), c);
        return found;
    }
    int countLess(long k) {
        int t = root, res = 0;
        while (t != 0) { if (key[t] < k) { res += sz[L[t]] + 1; t = R[t]; } else t = L[t]; }
        return res;
    }
    long kth(int k) {
        int t = root;
        while (true) {
            if (k <= sz[L[t]]) t = L[t];
            else if (k == sz[L[t]] + 1) return key[t];
            else { k -= sz[L[t]] + 1; t = R[t]; }
        }
    }
}
```

The Java `split` returns its two results in the fields `sa`, `sb`; copy them into locals immediately, because the next `split` call overwrites them.
Inside `split`, the recursive call's results are consumed before this frame writes `sa`/`sb`, which is why the field trick is correct.

### 3.2 Implicit treap (sequence with reverse flag and subtree sums)

```cpp
struct ImplicitTreap {
    struct Node { int l, r, sz; unsigned pri; long long val, sum; bool rev; };
    vector<Node> t;                                           // array of structs: one cache line per node
    mt19937 rng{1234567};
    explicit ImplicitTreap(int cap = 0) { t.reserve(cap + 1); t.push_back({0, 0, 0, 0, 0, 0, false}); }   // node 0 = null
    int node(long long v) { t.push_back({0, 0, 1, (unsigned)rng(), v, v, false}); return int(t.size()) - 1; }
    void push(int x) {
        if (x && t[x].rev) { swap(t[x].l, t[x].r); t[t[x].l].rev ^= 1; t[t[x].r].rev ^= 1; t[x].rev = 0; t[0].rev = 0; }
    }
    void pull(int x) { Node& a = t[x]; a.sz = 1 + t[a.l].sz + t[a.r].sz; a.sum = a.val + t[a.l].sum + t[a.r].sum; }
    void split(int x, int k, int& a, int& b) {                // a: first k elements
        if (!x) { a = b = 0; return; }
        push(x);
        if (t[t[x].l].sz < k) { split(t[x].r, k - t[t[x].l].sz - 1, t[x].r, b); a = x; } else { split(t[x].l, k, a, t[x].l); b = x; }
        pull(x);
    }
    int merge(int a, int b) {                                 // concatenation a + b
        if (!a || !b) return a | b;
        if (t[a].pri > t[b].pri) { push(a); t[a].r = merge(t[a].r, b); pull(a); return a; }
        push(b); t[b].l = merge(a, t[b].l); pull(b); return b;
    }
    void inorder(int x, vector<long long>& out) {             // iterative, pushes flags on the way
        vector<int> st;
        while (x || !st.empty()) {
            while (x) { push(x); st.push_back(x); x = t[x].l; }
            x = st.back(); st.pop_back();
            out.push_back(t[x].val);
            x = t[x].r;
        }
    }
};
```

```java
static class ImplicitTreap {
    int[] L, R, sz, pri; long[] val, sum; boolean[] rev; int size = 1;
    final Random rng = new Random(1234567);
    ImplicitTreap(int cap) {
        L = new int[cap + 1]; R = new int[cap + 1]; sz = new int[cap + 1]; pri = new int[cap + 1];
        val = new long[cap + 1]; sum = new long[cap + 1]; rev = new boolean[cap + 1];
    }
    int node(long v) { sz[size] = 1; pri[size] = rng.nextInt(); val[size] = v; sum[size] = v; return size++; }
    void push(int t) {
        if (t != 0 && rev[t]) { int x = L[t]; L[t] = R[t]; R[t] = x; rev[L[t]] ^= true; rev[R[t]] ^= true; rev[t] = false; rev[0] = false; }
    }
    void pull(int t) { sz[t] = 1 + sz[L[t]] + sz[R[t]]; sum[t] = val[t] + sum[L[t]] + sum[R[t]]; }
    int sa, sb;
    void split(int t, int k) {                                // sa: first k elements, sb: the rest
        if (t == 0) { sa = sb = 0; return; }
        push(t);
        if (sz[L[t]] < k) { split(R[t], k - sz[L[t]] - 1); R[t] = sa; sa = t; } else { split(L[t], k); L[t] = sb; sb = t; }
        pull(t);
    }
    int merge(int a, int b) {
        if (a == 0 || b == 0) return a | b;
        if (pri[a] > pri[b]) { push(a); R[a] = merge(R[a], b); pull(a); return a; }
        push(b); L[b] = merge(a, L[b]); pull(b); return b;
    }
}
```

`rev[0] = 0` (C++: `t[0].rev = 0`) after toggling guards against the null node accumulating a flag (it is harmless, but keeping node 0 pristine avoids surprises when node 0's fields are read).

## 4. Recognising the pattern

- **"Move/cut/paste/rotate/reverse a block of the sequence"**, "insert at position $i$", "delete the $k$-th element" with interleaved queries → implicit treap.
- **Ordered multiset with order statistics in Java** (C++ has PBDS, see [ordered sets](10-ordered-sets-pbds-and-heaps.md)) → treap, or a BIT over compressed values if all values are known offline.
- **Merging two ordered sets** where every key of one is smaller → `merge` in $O(\log n)$; arbitrary union → 🧊 treap union in $O(m\log(n/m))$.
- **Segment-tree-like aggregates on a sequence whose shape changes** → implicit treap with `pull`/`push` of aggregates and lazy tags.
- **Only appends at the ends and no restructuring** → a deque or a segment tree over the final positions is simpler; treaps are for genuine restructuring.
- Confused with: Cartesian trees on arrays (same structure with *given* priorities — used for RMQ and "max on subarray" counting).

## 5. Worked examples (graded)

### Example 1 — Ordered multiset with ranks  ·  ★ ≈1700

- **Source:** Original problem (the toolkit Java users need for "k-th element / rank" problems such as [CSES 2163 · Josephus Problem II](https://cses.fi/problemset/task/2163)).
- **Difficulty:** ≈1700 (est.)
- **Problem:** $q \le 2\cdot10^5$ operations on an initially empty multiset of integers with $|x| \le 10^9$: `1 x` insert $x$; `2 x` remove one copy of $x$ if present; `3 x` print the number of elements $< x$; `4 k` print the $k$-th smallest element, or $-1$ if there are fewer than $k$.
- **Thinking from first principles:** `std::multiset`/`TreeMap` give insert/erase/lower_bound but not ranks — their nodes lack subtree sizes. Offline, a BIT over compressed values does it.
  Online, keep the sizes yourself: a treap with a size field answers both rank queries by walking from the root.

<details><summary>Solution</summary>

The `Treap` of §3.1 verbatim. Expected $O(\log n)$ per operation.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct Treap {
    vector<int> L, R, sz; vector<unsigned> pri; vector<long long> key;
    mt19937 rng{20261023};
    Treap() { L.push_back(0); R.push_back(0); sz.push_back(0); pri.push_back(0); key.push_back(0); }
    int node(long long k) { L.push_back(0); R.push_back(0); sz.push_back(1); pri.push_back(rng()); key.push_back(k); return int(key.size()) - 1; }
    void pull(int t) { sz[t] = 1 + sz[L[t]] + sz[R[t]]; }
    void split(int t, long long k, int& a, int& b) {
        if (!t) { a = b = 0; return; }
        if (key[t] < k) { split(R[t], k, R[t], b); a = t; } else { split(L[t], k, a, L[t]); b = t; }
        pull(t);
    }
    int merge(int a, int b) {
        if (!a || !b) return a | b;
        if (pri[a] > pri[b]) { R[a] = merge(R[a], b); pull(a); return a; }
        L[b] = merge(a, L[b]); pull(b); return b;
    }
    int root = 0;
    void insert(long long k) { int a, b; split(root, k, a, b); int nd = node(k); root = merge(merge(a, nd), b); }
    bool eraseOne(long long k) {
        int a, b, c; split(root, k, a, b); split(b, k + 1, b, c);
        bool found = b != 0;
        if (found) b = merge(L[b], R[b]);
        root = merge(merge(a, b), c);
        return found;
    }
    int countLess(long long k) const {
        int t = root, res = 0;
        while (t) { if (key[t] < k) { res += sz[L[t]] + 1; t = R[t]; } else t = L[t]; }
        return res;
    }
    long long kth(int k) const {
        int t = root;
        while (true) {
            if (k <= sz[L[t]]) t = L[t];
            else if (k == sz[L[t]] + 1) return key[t];
            else { k -= sz[L[t]] + 1; t = R[t]; }
        }
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int q; cin >> q;
    Treap tr;
    while (q--) {
        int t; long long x; cin >> t >> x;
        if (t == 1) tr.insert(x);
        else if (t == 2) tr.eraseOne(x);
        else if (t == 3) cout << tr.countLess(x) << '\n';
        else cout << (x >= 1 && x <= tr.sz[tr.root] ? tr.kth(int(x)) : -1) << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static class Treap {
        int[] L, R, sz, pri; long[] key; int size = 1, root = 0;
        final Random rng = new Random(20261023);
        Treap(int cap) { L = new int[cap + 1]; R = new int[cap + 1]; sz = new int[cap + 1]; pri = new int[cap + 1]; key = new long[cap + 1]; }
        int node(long k) { sz[size] = 1; pri[size] = rng.nextInt(); key[size] = k; return size++; }
        void pull(int t) { sz[t] = 1 + sz[L[t]] + sz[R[t]]; }
        int sa, sb;
        void split(int t, long k) {
            if (t == 0) { sa = sb = 0; return; }
            if (key[t] < k) { split(R[t], k); R[t] = sa; sa = t; } else { split(L[t], k); L[t] = sb; sb = t; }
            pull(t);
        }
        int merge(int a, int b) {
            if (a == 0 || b == 0) return a | b;
            if (pri[a] > pri[b]) { R[a] = merge(R[a], b); pull(a); return a; }
            L[b] = merge(a, L[b]); pull(b); return b;
        }
        void insert(long k) { split(root, k); int a = sa, b = sb; root = merge(merge(a, node(k)), b); }
        boolean eraseOne(long k) {
            split(root, k); int a = sa, rest = sb;
            split(rest, k + 1); int b = sa, c = sb;
            boolean found = b != 0;
            if (found) b = merge(L[b], R[b]);
            root = merge(merge(a, b), c);
            return found;
        }
        int countLess(long k) {
            int t = root, res = 0;
            while (t != 0) { if (key[t] < k) { res += sz[L[t]] + 1; t = R[t]; } else t = L[t]; }
            return res;
        }
        long kth(int k) {
            int t = root;
            while (true) {
                if (k <= sz[L[t]]) t = L[t];
                else if (k == sz[L[t]] + 1) return key[t];
                else { k -= sz[L[t]] + 1; t = R[t]; }
            }
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int q = in.nextInt();
        Treap tr = new Treap(q);
        while (q-- > 0) {
            int t = in.nextInt(); long x = in.nextLong();
            if (t == 1) tr.insert(x);
            else if (t == 2) tr.eraseOne(x);
            else if (t == 3) out.println(tr.countLess(x));
            else out.println(x >= 1 && x <= tr.sz[tr.root] ? tr.kth((int) x) : -1);
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
10
1 5
1 3
1 5
3 5
4 2
2 5
4 2
2 7
4 3
3 100
out:
1
5
5
-1
2
-->
<!-- test
in:
4
4 1
1 -1000000000
4 1
3 -1000000000
out:
-1
-1000000000
0
-->

</details>

### Example 2 — Yet Another Array Queries Problem (cyclic shifts and reversals)  ·  ★ 1800

- **Source:** [CF 863D · Yet Another Array Queries Problem](https://codeforces.com/problemset/problem/863/D) — 1800
- **Difficulty:** 1800
- **Problem:** an array of $n \le 2\cdot10^5$ values; $q \le 2\cdot10^5$ operations `1 l r` (cyclic shift of $a_l..a_r$ to the right by one: $a_r$ moves to position $l$) and `2 l r` (reverse $a_l..a_r$); then $m \le 100$ indices $b_i$: print $a_{b_i}$ after all operations.
- **Thinking from first principles:** because $m \le 100$, the intended solution traces each requested index *backwards* through the operations ($O(qm)$). An implicit treap solves the general version
  (any number of final reads, or reads interleaved with operations): shift = split $[l, r]$ off, split its last element, re-merge it in front; reverse = flag. Either way: positions are what move, so think in positions.

<details><summary>Solution</summary>

Build by merging nodes left to right; after all operations, one iterative in-order traversal produces the final array. Expected $O((n + q)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct ImplicitTreap {
    struct Node { int l, r, sz; unsigned pri; long long val, sum; bool rev; };
    vector<Node> t;                                           // array of structs: one cache line per node
    mt19937 rng{1234567};
    explicit ImplicitTreap(int cap = 0) { t.reserve(cap + 1); t.push_back({0, 0, 0, 0, 0, 0, false}); }   // node 0 = null
    int node(long long v) { t.push_back({0, 0, 1, (unsigned)rng(), v, v, false}); return int(t.size()) - 1; }
    void push(int x) {
        if (x && t[x].rev) { swap(t[x].l, t[x].r); t[t[x].l].rev ^= 1; t[t[x].r].rev ^= 1; t[x].rev = 0; t[0].rev = 0; }
    }
    void pull(int x) { Node& a = t[x]; a.sz = 1 + t[a.l].sz + t[a.r].sz; a.sum = a.val + t[a.l].sum + t[a.r].sum; }
    void split(int x, int k, int& a, int& b) {                // a: first k elements
        if (!x) { a = b = 0; return; }
        push(x);
        if (t[t[x].l].sz < k) { split(t[x].r, k - t[t[x].l].sz - 1, t[x].r, b); a = x; } else { split(t[x].l, k, a, t[x].l); b = x; }
        pull(x);
    }
    int merge(int a, int b) {                                 // concatenation a + b
        if (!a || !b) return a | b;
        if (t[a].pri > t[b].pri) { push(a); t[a].r = merge(t[a].r, b); pull(a); return a; }
        push(b); t[b].l = merge(a, t[b].l); pull(b); return b;
    }
    void inorder(int x, vector<long long>& out) {             // iterative, pushes flags on the way
        vector<int> st;
        while (x || !st.empty()) {
            while (x) { push(x); st.push_back(x); x = t[x].l; }
            x = st.back(); st.pop_back();
            out.push_back(t[x].val);
            x = t[x].r;
        }
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q, m; cin >> n >> q >> m;
    ImplicitTreap tr(n);
    int root = 0;
    for (int i = 0; i < n; i++) { long long x; cin >> x; int nd = tr.node(x); root = tr.merge(root, nd); }
    while (q--) {
        int t, l, r; cin >> t >> l >> r;
        int a, b, c; tr.split(root, l - 1, a, b); tr.split(b, r - l + 1, b, c);
        if (t == 1) { int b1, b2; tr.split(b, r - l, b1, b2); b = tr.merge(b2, b1); }
        else tr.t[b].rev ^= 1;
        root = tr.merge(tr.merge(a, b), c);
    }
    vector<long long> fin; fin.reserve(n);
    tr.inorder(root, fin);
    for (int i = 0; i < m; i++) { int x; cin >> x; cout << fin[x - 1] << (i + 1 < m ? ' ' : '\n'); }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static class ImplicitTreap {
        int[] L, R, sz, pri; long[] val, sum; boolean[] rev; int size = 1;
        final Random rng = new Random(1234567);
        ImplicitTreap(int cap) {
            L = new int[cap + 1]; R = new int[cap + 1]; sz = new int[cap + 1]; pri = new int[cap + 1];
            val = new long[cap + 1]; sum = new long[cap + 1]; rev = new boolean[cap + 1];
        }
        int node(long v) { sz[size] = 1; pri[size] = rng.nextInt(); val[size] = v; sum[size] = v; return size++; }
        void push(int t) { if (t != 0 && rev[t]) { int x = L[t]; L[t] = R[t]; R[t] = x; rev[L[t]] ^= true; rev[R[t]] ^= true; rev[t] = false; rev[0] = false; } }
        void pull(int t) { sz[t] = 1 + sz[L[t]] + sz[R[t]]; sum[t] = val[t] + sum[L[t]] + sum[R[t]]; }
        int sa, sb;
        void split(int t, int k) {
            if (t == 0) { sa = sb = 0; return; }
            push(t);
            if (sz[L[t]] < k) { split(R[t], k - sz[L[t]] - 1); R[t] = sa; sa = t; } else { split(L[t], k); L[t] = sb; sb = t; }
            pull(t);
        }
        int merge(int a, int b) {
            if (a == 0 || b == 0) return a | b;
            if (pri[a] > pri[b]) { push(a); R[a] = merge(R[a], b); pull(a); return a; }
            push(b); L[b] = merge(a, L[b]); pull(b); return b;
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), q = in.nextInt(), m = in.nextInt();
        ImplicitTreap tr = new ImplicitTreap(n);
        int root = 0;
        for (int i = 0; i < n; i++) root = tr.merge(root, tr.node(in.nextInt()));
        while (q-- > 0) {
            int t = in.nextInt(), l = in.nextInt(), r = in.nextInt();
            tr.split(root, l - 1); int a = tr.sa, rest = tr.sb;
            tr.split(rest, r - l + 1); int b = tr.sa, c = tr.sb;
            if (t == 1) { tr.split(b, r - l); int b1 = tr.sa, b2 = tr.sb; b = tr.merge(b2, b1); }
            else tr.rev[b] ^= true;
            root = tr.merge(tr.merge(a, b), c);
        }
        long[] fin = new long[n]; int cnt = 0;
        int[] st = new int[n + 1]; int sp = 0, t = root;
        while (t != 0 || sp > 0) {
            while (t != 0) { tr.push(t); st[sp++] = t; t = tr.L[t]; }
            t = st[--sp]; fin[cnt++] = tr.val[t]; t = tr.R[t];
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < m; i++) sb.append(fin[in.nextInt() - 1]).append(i + 1 < m ? ' ' : '\n');
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

The in-order traversal uses an explicit stack: the treap is shallow in expectation, but an explicit stack costs nothing and removes any doubt.

<!-- test
in:
6 3 5
1 2 3 4 5 6
2 1 3
2 3 6
1 1 6
2 2 1 5 3
out:
3 3 1 5 2
-->
<!-- test
in:
1 2 1
7
1 1 1
2 1 1
1
out:
7
-->
<!-- test
in:
5 2 5
10 20 30 40 50
1 2 5
1 1 5
1 2 3 4 5
out:
40 10 50 20 30
-->

</details>

### Example 3 — Cut and Paste  ·  ★ ≈1900

- **Source:** [CSES 2072 · Cut and Paste](https://cses.fi/problemset/task/2072)
- **Difficulty:** ≈1900 (est.)
- **Problem:** a string of length $n \le 2\cdot10^5$; $m \le 2\cdot10^5$ operations $(a, b)$: cut the substring $s_a..s_b$ and paste it at the end. Print the final string.
- **Thinking from first principles:** `string::erase` + append is $O(n)$ per operation, $4\cdot10^{10}$ total. Splitting the sequence into $A\,B\,C$ and re-merging as $A\,C\,B$ is three splits/merges — $O(\log n)$.

<details><summary>Solution</summary>

Implicit treap of characters (no aggregates needed). Expected $O((n + m)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

vector<int> L, R, sz; vector<unsigned> pri; vector<char> ch;
mt19937 rng(987654321);
void pull(int t) { sz[t] = 1 + sz[L[t]] + sz[R[t]]; }
void split(int t, int k, int& a, int& b) {
    if (!t) { a = b = 0; return; }
    if (sz[L[t]] < k) { split(R[t], k - sz[L[t]] - 1, R[t], b); a = t; } else { split(L[t], k, a, L[t]); b = t; }
    pull(t);
}
int merge(int a, int b) {
    if (!a || !b) return a | b;
    if (pri[a] > pri[b]) { R[a] = merge(R[a], b); pull(a); return a; }
    L[b] = merge(a, L[b]); pull(b); return b;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; string s; cin >> n >> m >> s;
    L.assign(n + 1, 0); R.assign(n + 1, 0); sz.assign(n + 1, 0); pri.assign(n + 1, 0); ch.assign(n + 1, 0);
    int root = 0;
    for (int i = 1; i <= n; i++) { sz[i] = 1; pri[i] = rng(); ch[i] = s[i - 1]; root = merge(root, i); }
    while (m--) {
        int a, b; cin >> a >> b;
        int x, y, z; split(root, a - 1, x, y); split(y, b - a + 1, y, z);
        root = merge(merge(x, z), y);
    }
    string res; res.reserve(n);
    vector<int> st; int t = root;
    while (t || !st.empty()) {
        while (t) { st.push_back(t); t = L[t]; }
        t = st.back(); st.pop_back(); res += ch[t]; t = R[t];
    }
    cout << res << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] L, R, sz, pri; static int sa, sb;
    static void pull(int t) { sz[t] = 1 + sz[L[t]] + sz[R[t]]; }
    static void split(int t, int k) {
        if (t == 0) { sa = sb = 0; return; }
        if (sz[L[t]] < k) { split(R[t], k - sz[L[t]] - 1); R[t] = sa; sa = t; } else { split(L[t], k); L[t] = sb; sb = t; }
        pull(t);
    }
    static int merge(int a, int b) {
        if (a == 0 || b == 0) return a | b;
        if (pri[a] > pri[b]) { R[a] = merge(R[a], b); pull(a); return a; }
        L[b] = merge(a, L[b]); pull(b); return b;
    }

    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in), 1 << 16);
        StringTokenizer st = new StringTokenizer(br.readLine());
        int n = Integer.parseInt(st.nextToken()), m = Integer.parseInt(st.nextToken());
        String s = br.readLine().trim();
        L = new int[n + 1]; R = new int[n + 1]; sz = new int[n + 1]; pri = new int[n + 1];
        Random rng = new Random(987654321);
        int root = 0;
        for (int i = 1; i <= n; i++) { sz[i] = 1; pri[i] = rng.nextInt(); root = merge(root, i); }
        while (m-- > 0) {
            st = new StringTokenizer(br.readLine());
            int a = Integer.parseInt(st.nextToken()), b = Integer.parseInt(st.nextToken());
            split(root, a - 1); int x = sa, y = sb;
            split(y, b - a + 1); y = sa; int z = sb;
            root = merge(merge(x, z), y);
        }
        StringBuilder res = new StringBuilder(n);
        int[] stk = new int[n + 1]; int sp = 0, t = root;
        while (t != 0 || sp > 0) {
            while (t != 0) { stk[sp++] = t; t = L[t]; }
            t = stk[--sp]; res.append(s.charAt(t - 1)); t = R[t];
        }
        System.out.println(res);
    }
}
```

Node $i$ is created for character $s_i$, so the Java version reads the character back as `s.charAt(t - 1)` instead of storing it.

<!-- test
in:
7 2
AYBABTU
3 5
3 5
out:
AYABTUB
-->
<!-- test
in:
1 1
Z
1 1
out:
Z
-->
<!-- test
in:
5 3
ABCDE
1 2
1 1
4 5
out:
DEABC
-->

</details>

### Example 4 — Reversals and Sums  ·  ★ ≈2100

- **Source:** [CSES 2074 · Reversals and Sums](https://cses.fi/problemset/task/2074)
- **Difficulty:** ≈2100 (est.)
- **Problem:** an array of $n \le 2\cdot10^5$ values up to $10^9$; $m \le 2\cdot10^5$ operations: `1 a b` reverse $t_a..t_b$; `2 a b` print $t_a + \dots + t_b$.
- **Thinking from first principles:** a segment tree has the right aggregate (sum) but cannot reverse — reversal changes *which positions* hold which values, i.e. the shape. The implicit treap holds the sum per subtree and
  reverses by flag: reversing does not change a subtree's sum, so `push` only swaps children. Query = split out $[a, b]$, read the root's sum, merge back.

<details><summary>Solution</summary>

The §3.2 structure. Expected $O((n + m)\log n)$. Sums up to $2\cdot10^{14}$ → 64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct ImplicitTreap {
    struct Node { int l, r, sz; unsigned pri; long long val, sum; bool rev; };
    vector<Node> t;                                           // array of structs: one cache line per node
    mt19937 rng{1234567};
    explicit ImplicitTreap(int cap = 0) { t.reserve(cap + 1); t.push_back({0, 0, 0, 0, 0, 0, false}); }   // node 0 = null
    int node(long long v) { t.push_back({0, 0, 1, (unsigned)rng(), v, v, false}); return int(t.size()) - 1; }
    void push(int x) {
        if (x && t[x].rev) { swap(t[x].l, t[x].r); t[t[x].l].rev ^= 1; t[t[x].r].rev ^= 1; t[x].rev = 0; t[0].rev = 0; }
    }
    void pull(int x) { Node& a = t[x]; a.sz = 1 + t[a.l].sz + t[a.r].sz; a.sum = a.val + t[a.l].sum + t[a.r].sum; }
    void split(int x, int k, int& a, int& b) {                // a: first k elements
        if (!x) { a = b = 0; return; }
        push(x);
        if (t[t[x].l].sz < k) { split(t[x].r, k - t[t[x].l].sz - 1, t[x].r, b); a = x; } else { split(t[x].l, k, a, t[x].l); b = x; }
        pull(x);
    }
    int merge(int a, int b) {                                 // concatenation a + b
        if (!a || !b) return a | b;
        if (t[a].pri > t[b].pri) { push(a); t[a].r = merge(t[a].r, b); pull(a); return a; }
        push(b); t[b].l = merge(a, t[b].l); pull(b); return b;
    }
    void inorder(int x, vector<long long>& out) {             // iterative, pushes flags on the way
        vector<int> st;
        while (x || !st.empty()) {
            while (x) { push(x); st.push_back(x); x = t[x].l; }
            x = st.back(); st.pop_back();
            out.push_back(t[x].val);
            x = t[x].r;
        }
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    ImplicitTreap tr(n);
    int root = 0;
    for (int i = 0; i < n; i++) { long long x; cin >> x; int nd = tr.node(x); root = tr.merge(root, nd); }
    while (m--) {
        int t, a, b; cin >> t >> a >> b;
        int x, y, z; tr.split(root, a - 1, x, y); tr.split(y, b - a + 1, y, z);
        if (t == 1) tr.t[y].rev ^= 1;
        else cout << tr.t[y].sum << '\n';
        root = tr.merge(tr.merge(x, y), z);
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static class ImplicitTreap {
        int[] L, R, sz, pri; long[] val, sum; boolean[] rev; int size = 1;
        final Random rng = new Random(1234567);
        ImplicitTreap(int cap) {
            L = new int[cap + 1]; R = new int[cap + 1]; sz = new int[cap + 1]; pri = new int[cap + 1];
            val = new long[cap + 1]; sum = new long[cap + 1]; rev = new boolean[cap + 1];
        }
        int node(long v) { sz[size] = 1; pri[size] = rng.nextInt(); val[size] = v; sum[size] = v; return size++; }
        void push(int t) { if (t != 0 && rev[t]) { int x = L[t]; L[t] = R[t]; R[t] = x; rev[L[t]] ^= true; rev[R[t]] ^= true; rev[t] = false; rev[0] = false; } }
        void pull(int t) { sz[t] = 1 + sz[L[t]] + sz[R[t]]; sum[t] = val[t] + sum[L[t]] + sum[R[t]]; }
        int sa, sb;
        void split(int t, int k) {
            if (t == 0) { sa = sb = 0; return; }
            push(t);
            if (sz[L[t]] < k) { split(R[t], k - sz[L[t]] - 1); R[t] = sa; sa = t; } else { split(L[t], k); L[t] = sb; sb = t; }
            pull(t);
        }
        int merge(int a, int b) {
            if (a == 0 || b == 0) return a | b;
            if (pri[a] > pri[b]) { push(a); R[a] = merge(R[a], b); pull(a); return a; }
            push(b); L[b] = merge(a, L[b]); pull(b); return b;
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), m = in.nextInt();
        ImplicitTreap tr = new ImplicitTreap(n);
        int root = 0;
        for (int i = 0; i < n; i++) root = tr.merge(root, tr.node(in.nextInt()));
        while (m-- > 0) {
            int t = in.nextInt(), a = in.nextInt(), b = in.nextInt();
            tr.split(root, a - 1); int x = tr.sa, y = tr.sb;
            tr.split(y, b - a + 1); y = tr.sa; int z = tr.sb;
            if (t == 1) tr.rev[y] ^= true;
            else out.println(tr.sum[y]);
            root = tr.merge(tr.merge(x, y), z);
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
8 3
2 1 3 4 5 3 4 4
2 2 4
1 3 6
2 2 4
out:
8
9
-->
<!-- test
in:
1 3
1000000000
1 1 1
2 1 1
2 1 1
out:
1000000000
1000000000
-->
<!-- test
in:
5 4
1 2 3 4 5
1 1 5
2 1 2
1 2 4
2 1 3
out:
9
10
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Push before you look at children** — in `split`, in `merge` (on the root you descend into), in in-order traversal, and in any walk. A missing push in `merge` reverses the wrong subtree.
2. **Pull after you change children** — after every recursive `split`/`merge` call.
3. **Split semantics**: by key `(< k, >= k)` or by count `(first k, rest)` — pick one per structure; erasing one copy of $k$ needs `split(k)` then `split(k + 1)` (integer keys) or a split by count of 1.
4. **Random priorities**: use `mt19937` / `Random` with distinct-enough values; `rand()` on Windows gives 15 bits — ties make the shape non-unique and can degrade balance.
5. **Java out-parameters**: return split results through fields and copy them to locals *immediately*; the next call overwrites them.
6. **Node 0 is the null node**: `sz[0] = 0`, `sum[0] = 0`, `rev[0] = 0`; never let a push write meaningful data into it.
7. **Memory**: one node per element ever created; preallocate in Java. Erased nodes are simply abandoned (or recycled with a free list).
8. **Building**: $n$ merges of single nodes is $O(n \log n)$ expected and simple; for $n = 10^6$ use the $O(n)$ stack-based Cartesian-tree build.
9. **Recursion depth** is $O(\log n)$ in expectation, so recursive split/merge are fine in Java; but traversals of the *whole* tree should use an explicit stack.
10. **Off-by-one in implicit splits**: to isolate $[l, r]$ (1-based), split at $l - 1$, then split the remainder at $r - l + 1$.
11. **Treap vs `std::set` speed**: a treap is 2–4× slower than the standard library; use it only for what the library cannot do (ranks in Java, restructuring).
12. **Adversarial seeds**: a fixed seed is fine for CSES/AtCoder; on Codeforces seed from `chrono::steady_clock` (C++) or `System.nanoTime()` (Java) so hackers cannot target your priorities.

## 7. Going further (toward 2400–2600+)

- **Treaps with lazy range tags** (add, assign, affine) plus reversal: the tags compose with the reverse flag independently; [CF 702F · T-Shirts](https://codeforces.com/problemset/problem/702/F) — 2800 (treap of customers keyed by money, subtract with splits and "re-insert the middle part" amortisation).
- **Treap union/merge of arbitrary key ranges** in $O(m\log(n/m))$ and small-to-large on treaps.
- **Persistent treaps** (copy nodes on split/merge) — ropes with history, 🧊.
- **Splay trees and link–cut trees** for dynamic forests: [link-cut trees](../16-IGM-Frontier/03-link-cut-trees.md).
- **Sqrt-decomposition alternative** for sequence restructuring: split the array into $\sqrt n$ blocks and rebuild periodically — [CF 455D · Serega and Fun](https://codeforces.com/problemset/problem/455/D) — 2700 (cyclic shifts + count of value in range).
- **Treap-based DP** ("slope trick" or sequences of segments merged by keys): [CF 809D · Hitchhiking in the Baltic States](https://codeforces.com/problemset/problem/809/D) — 2900; see [slope trick](../07-DP-Optimizations/07-slope-trick.md).

## 8. Practice ladder

**1700–2100**
- [ ] [CSES 2163 · Josephus Problem II](https://cses.fi/problemset/task/2163)
- [ ] [CSES 1749 · List Removals](https://cses.fi/problemset/task/1749)
- [ ] [CF 863D · Yet Another Array Queries Problem](https://codeforces.com/problemset/problem/863/D) — 1800
- [ ] [CSES 2072 · Cut and Paste](https://cses.fi/problemset/task/2072)
- [ ] [CSES 2073 · Substring Reversals](https://cses.fi/problemset/task/2073)
- [ ] [CSES 2074 · Reversals and Sums](https://cses.fi/problemset/task/2074)

**2100+**
- [ ] [CF 85D · Sum of Medians](https://codeforces.com/problemset/problem/85/D) — 2300
- [ ] [CF 455D · Serega and Fun](https://codeforces.com/problemset/problem/455/D) — 2700
- [ ] [CF 702F · T-Shirts](https://codeforces.com/problemset/problem/702/F) — 2800
- [ ] [CF 809D · Hitchhiking in the Baltic States](https://codeforces.com/problemset/problem/809/D) — 2900

## 9. LeetCode / FAANG cross-reference

- [LC 1206 · Design Skiplist](https://leetcode.com/problems/design-skiplist/) — Hard — the other randomised balanced structure; the same "random levels give $O(\log n)$ expected" argument.
- [LC 2296 · Design a Text Editor](https://leetcode.com/problems/design-a-text-editor/) — Hard — cursor edits; two stacks suffice, a rope/implicit treap generalises it.
- [LC 1825 · Finding MK Average](https://leetcode.com/problems/finding-mk-average/) — Hard — order statistics over a sliding window: three multisets or one rank-augmented tree.
- [LC 2102 · Sequentially Ordinal Rank Tracker](https://leetcode.com/problems/sequentially-ordinal-rank-tracker/) — Hard — k-th query on a growing ordered set (two heaps work too).

Rare in interviews: treaps are almost never expected. Know that an order-statistic tree exists and be able to sketch one; implement heaps or sorted containers instead.

## 10. Self-check

1. Why is the shape of a treap determined by keys and priorities, and why is it the same as a random BST?
2. Prove that $x_j$ is an ancestor of $x_i$ with probability $1/(|i-j|+1)$ and derive the expected depth.
3. Write `split` by key and by count. What changes between them?
4. How do you reverse $[l, r]$ in an implicit treap, and why does pushing the flag produce the reversed sequence?
5. How do you cyclic-shift $[l, r]$ right by $k$ positions?
6. Why must `merge` push before descending?
7. When would you choose a BIT over a treap for order statistics?

<details><summary>Answers</summary>

1. The highest-priority node must be the root (heap order) and BST order fixes which nodes go left/right; recursing gives a unique tree, identical to inserting keys in decreasing priority order — a uniformly random order when priorities are random.
2. Among $x_i..x_j$ (inclusive), the first key "chosen" as a subtree root decides: if it is $x_j$, $x_j$ is an ancestor; if another key between them, they are separated; each of the $|i-j|+1$ keys is equally likely to have the max priority. Summing $1/(d+1)$ over distances gives $< 2\ln n$.
3. By key: compare `key[t] < k`; by count: compare `sz[L[t]] < k` and pass `k - sz[L[t]] - 1` to the right recursion.
4. Split out the middle part and toggle its flag; push swaps the children and toggles the children's flags — recursively this swaps every node's children, i.e. mirrors the in-order sequence.
5. Split out $B = [l, r]$, let $k' = k \bmod |B|$, split $B$ into the first $|B| - k'$ and the last $k'$ elements, merge them in swapped order, merge back.
6. The root we descend into may carry a reverse flag; its children are "logically swapped" until pushed, so attaching to the wrong child corrupts the order.
7. When all values are known in advance (offline compression) and no restructuring is needed: a BIT is shorter, deterministic and faster.

</details>
