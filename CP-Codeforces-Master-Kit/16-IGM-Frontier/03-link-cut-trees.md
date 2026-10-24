# Link-cut trees

> **Band:** 🔴 2500–3400 · **Priority:** 🧊 (know it exists before Dec 2027; learn it on the way to GM) · **FAANG:** none · **Prerequisites:** [treaps and implicit treaps](../08-Data-Structures/09-treaps-and-implicit-treaps.md) (rotations, lazy reversal), [heavy-light decomposition](../10-Trees/04-heavy-light-decomposition.md), [Euler tour](../10-Trees/01-tree-basics-diameter-center-euler-tour.md), [LCA](../10-Trees/02-lca-and-binary-lifting.md)
> **You can say you know this when:** you can write `access`, `makeRoot`, `link`, `cut`, `findRoot` and a path aggregate without notes, explain why `access` is amortised $O(\log n)$, and decide in a few seconds whether a problem really needs a link-cut tree or whether HLD / an Euler tour tree / an offline trick is enough.

## 1. First principles — why this works

### 1.1 The problem

Maintain a **forest** under three kinds of operations: add an edge between two trees (**link**), delete a tree edge (**cut**), and ask something about the path between two vertices (sum, max, connectivity, LCA). With $n, q \sim 10^5$–$3\cdot10^5$, $O(n)$ per operation is too slow.

On a **static** tree the answer is [heavy-light decomposition](../10-Trees/04-heavy-light-decomposition.md): cut the tree into vertex-disjoint "heavy" paths so that any root path crosses $O(\log n)$ of them, and keep each path in a segment tree. HLD fails on a changing tree because "heavy" is defined by subtree sizes, and one link can change the sizes of $\Theta(n)$ vertices.

### 1.2 The idea: paths chosen by recent use, stored in splay trees

Keep the idea "decompose the tree into vertex-disjoint paths", but choose the paths **dynamically**:

- Each vertex has at most one **preferred child**: the child through which the most recent `access` passed. Following preferred children decomposes the tree into **preferred paths**.
- Each preferred path is stored as a **splay tree keyed by depth** (in-order = top to bottom). A splay tree gives amortised $O(\log n)$ split/join and can carry path aggregates and lazy tags.
- The root of each splay tree stores a **path-parent pointer** to the parent (in the real tree) of the top vertex of its path.

In code one array `fa[]` holds both kinds of parent. A node is the root of its splay tree exactly when its `fa` is null or its `fa` does not list it as a child — that is the `isRoot` test, the single most important line of the implementation.

### 1.3 `access(x)`: make root…x one preferred path

```text
access(x):
    last = null
    while x != null:
        splay(x)            # x is now the root of its splay tree
        x.right = last      # the deeper part of x's old path becomes its own path (keeps fa = x as path-parent)
        pull(x)
        last = x
        x = fa[x]           # jump along the path-parent pointer
```

After `access(x)`, the splay tree containing $x$ holds exactly the vertices on the path from the root to $x$ (nothing deeper, because the first iteration cut away $x$'s right subtree). Everything else is built from it:

- **Path query $u$–$v$:** `makeRoot(u); access(v); splay(v)` — the splay tree of $v$ is the path, its aggregate is the answer.
- **`makeRoot(x)`:** `access(x); splay(x)` and **reverse** the splay tree (lazy flag). Rerooting at $x$ reverses the depth order on the old root–$x$ path and changes nothing else: every other preferred path hangs off this path by path-parent pointers and keeps its own top-to-bottom order.
- **`findRoot(x)`:** `access(x); splay(x)`, then walk to the leftmost node (pushing reversal tags on the way) — the smallest depth is the root. Splay it afterwards to pay for the walk.
- **`link(u, v)`:** `makeRoot(u)`; if `findRoot(v) == u` they are already connected; otherwise set `fa[u] = v` (a path-parent pointer: $u$ becomes a child of $v$ with no preferred edge).
- **`cut(u, v)`:** `makeRoot(u)`; the edge exists iff after `findRoot(v)` the splay tree is exactly $\{u, v\}$ in that order: `fa[v] == u` and $v$ has no left child. Then detach.
- **LCA in a rooted forest:** `access(u)`, then `access(v)` — the last vertex where the second access jumped onto the first path is the LCA. This is the return value `last` of the loop.

### 1.4 Why it is fast: two amortised bounds

**(a) Preferred-child changes.** Call a tree edge *heavy* if the child's subtree holds more than half of the parent's subtree, *light* otherwise. A root path contains at most $\log_2 n$ light edges. Each iteration of `access` after the first changes one preferred child. A change that makes a **light** edge preferred happens at most $\log_2 n$ times per access. A change that makes a **heavy** edge preferred requires that edge to have been non-preferred, which happened either initially ($\le n-1$ times) or because an earlier access made a light sibling preferred. So over $m$ operations the number of preferred-child changes is $O(n + m\log n)$; link and cut alter heavy/light status only along one root path, adding $O(\log n)$ each.

**(b) Splay cost — the access lemma.** Give every node weight 1 and let $s(x)$ be the number of nodes in $x$'s subtree of the *whole* auxiliary structure (its splay subtree plus everything hanging below through path-parent pointers). With rank $r(x) = \log_2 s(x)$ and potential $\Phi = \sum_x r(x)$, the access lemma of Sleator and Tarjan states that splaying $x$ to the root $t$ of its splay tree costs amortised at most

$$3\big(r(t) - r(x)\big) + 1 \text{ rotations.}$$

During one `access`, the splays happen at $x = x_1, x_2, \dots, x_k$ where $x_{i+1}$ is the path-parent of the splay tree just splayed at $x_i$. Since that whole splay tree hangs below $x_{i+1}$, $r(x_{i+1}) \ge r(t_i)$, so the sum telescopes:

$$\sum_{i=1}^{k}\Big(3\big(r(t_i)-r(x_i)\big)+1\Big) \le 3\big(r(\text{root}) - r(x)\big) + k \le 3\log_2 n + k.$$

Changing `x.right` does not change any $s(\cdot)$ in this weighting (the cut-off part still hangs below $x$), so it costs no potential. With (a), $k$ is amortised $O(\log n)$, so `access` is amortised $O(\log n)$, and so is every operation built from a constant number of accesses. `link` adds a subtree under $v$; doing `access(v); splay(v)` first makes $v$ the root of everything, so only $r(v)$ grows, by at most $\log_2 n$. `cut` only decreases sizes.

The constant is not small: in practice a link-cut tree is 3–5 times slower than HLD with a segment tree on the same static tree.

### 1.5 Neighbours: Euler tour trees, top trees, HLD

| Structure | Changes | Path aggregates | Subtree aggregates | Notes |
|---|---|---|---|---|
| HLD + segment tree | values only, static shape | $O(\log^2 n)$ | $O(\log n)$ | simplest; handles rerooted *queries* by case analysis |
| Link-cut tree | link, cut, reroot | $O(\log n)$ am. | only with "virtual subtree" bookkeeping | this file |
| Euler tour tree 🧊 | link, cut, reroot | no | $O(\log n)$ | balanced BST over the Euler tour; connectivity and subtree sums |
| Top tree 🧊 | everything | yes | yes | rarely worth the code in contests |

**When HLD suffices:**
- the tree shape never changes (only vertex/edge values) — even with "change the root" queries ([CF 916E · Jamie and Tree](https://codeforces.com/problemset/problem/916/E) — 2400);
- **links only, offline**: build the final forest, run HLD on it, and answer each path query only if a DSU says the endpoints are already connected at that time;
- cuts only, offline: reverse time and it becomes links only.

**When an offline trick beats LCT:** if edges are added and removed and you only need connectivity, the [segment tree on time](02-segment-tree-on-time-and-dsu-rollback.md) is easier to get right.

## 2. Formulas, definitions and identities

- **isRoot:** $x$ is a splay root iff `fa[x] == 0` or $x \notin \{\text{ch}[\text{fa}[x]][0], \text{ch}[\text{fa}[x]][1]\}$.
- **Access lemma** (splay tree, weights $w$, $s(x) = \sum_{\text{subtree}} w$, $r = \log_2 s$): amortised cost of `splay(x)` to root $t$ $\le 3(r(t)-r(x)) + 1$.
- **Light edges on a root path:** $\le \log_2 n$ (each light step at least halves the subtree size).
- **Preferred-child changes:** $O(n + m\log n)$ over $m$ operations.
- **Cost per operation:** amortised $O(\log n)$; total $O((n + m)\log n)$.
- **Path aggregate:** after `makeRoot(u); access(v); splay(v)`, $\text{agg}(v) = \bigoplus_{x \in \text{path}(u,v)} \text{val}(x)$ for any associative $\oplus$; with reversal, $\oplus$ must be commutative or you must keep both directions (e.g. for "composition of linear functions along the path", store left-to-right and right-to-left results and swap them on flip).
- **Edge weights:** put edge $e = (u,v)$ in its own node $n+e$ and link $u - (n+e) - v$; vertex nodes get the neutral value. Memory $n + m$ nodes.
- **LCA:** `access(u); return access(v)` (the last `last`).
- **Depth / path length:** keep subtree sizes in the splay; after `access(x); splay(x)`, `size(x) - 1` is the depth of $x$.

## 3. Implementation (C++ and Java)

Unrooted link-cut tree with lazy reversal and path sums. Input: $n$, $q$, the values $v_1..v_n$ ($0 \le v_i \le 10^9$), then $q$ operations: `1 u v` link if not connected, `2 u v` cut if the edge exists, `3 u v` print the path sum or $-1$ if not connected, `4 u x` set $v_u = x$. Invalid links/cuts are ignored, which makes the program its own stress-test target.

Implementation notes: node $0$ is the null node with sum $0$ and is never flipped; `splay` first pushes reversal tags from the splay root down to $x$ (collected on an explicit stack, no recursion); `rotate` must test `isRoot(y)` **before** changing `fa`.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

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

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, q;
    cin >> n >> q;
    LCT t(n);
    for (int i = 1; i <= n; i++) { cin >> t.val[i]; t.sum[i] = t.val[i]; }
    while (q--) {
        int type, a;
        ll b;
        cin >> type >> a >> b;
        if (type == 1) t.link(a, b);
        else if (type == 2) t.cut(a, b);
        else if (type == 3) cout << (t.connected(a, b) ? t.pathSum(a, b) : -1) << '\n';
        else t.setVal(a, b);
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
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

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), q = in.nextInt();
        LCT t = new LCT(n);
        for (int i = 1; i <= n; i++) { t.val[i] = in.nextLong(); t.sum[i] = t.val[i]; }
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            int type = in.nextInt(), a = in.nextInt();
            long b = in.nextLong();
            if (type == 1) t.link(a, (int) b);
            else if (type == 2) t.cut(a, (int) b);
            else if (type == 3) sb.append(t.connected(a, (int) b) ? t.pathSum(a, (int) b) : -1).append('\n');
            else t.setVal(a, b);
        }
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

<!-- test
in:
5 14
1 2 3 4 5
1 1 2
1 2 3
3 1 3
1 4 5
3 1 5
1 3 4
3 1 5
2 2 3
3 1 5
3 3 5
4 4 10
3 3 5
1 1 1
3 1 2
out:
6
-1
15
-1
12
18
3
-->
<!-- test
in:
1 1
42
3 1 1
out:
42
-->
<!-- test
in:
3 5
1 10 100
1 1 2
1 2 3
2 1 3
3 1 3
3 3 1
out:
111
111
-->

Stress-tested against a forest stored as adjacency sets with BFS paths (300 random cases of up to 40 operations, plus Java-vs-C++); $n = 10^5$, $q = 3\cdot10^5$ random operations run in about 1.1 s (C++) and 1.2 s (Java).

## 4. Recognising the pattern

- **"Add an edge", "remove an edge", and a path query, online**, on a graph that is promised to stay a forest → link-cut tree.
- **A pointer structure where each element points to one "next" element and pointers change** ("jump to $i + a_i$", "parent changes") → a rooted forest of next-pointers; queries "how many jumps until leaving" are depths. Link-cut tree or sqrt blocks.
- **Incremental minimum spanning forest** ("edges arrive; after each, report the MST weight") → LCT with edge nodes and path maximum: the new edge replaces the heaviest edge on the cycle it closes.
- **Dynamic connectivity where every edge's deletion time is known at insertion** → maximum spanning forest with weight = deletion time (an edge on a cycle that dies first is redundant).
- **Signals for something simpler:** shape never changes → HLD. Only links, offline → DSU + HLD on the final forest. Connectivity only, offline → segment tree on time. Subtree sums under reroot/link/cut → Euler tour tree.

## 5. Worked examples (graded)

### Example 1 — Ball jumping through holes  ·  ★ 2700

- **Source:** [CF 13E · Holes](https://codeforces.com/problemset/problem/13/E) — 2700
- **Difficulty:** 2700
- **Problem:** $n$ holes in a row, hole $i$ has power $a_i \ge 1$: a ball in hole $i$ jumps to $i + a_i$, and leaves the row when that exceeds $n$. Two operations, $n, m \le 10^5$: change the power of a hole; throw a ball into hole $x$ and print the last hole it visits and the number of jumps it makes (counting the jump that leaves the row).
- **Thinking from first principles:** Simulation is $O(n)$ per throw (power 1 everywhere). Every hole has exactly one "next" hole, or the outside: a **rooted forest** with an extra root $n+1$ ("outside"). A throw from $x$ walks the path from $x$ to the root; the number of jumps is the depth of $x$, and the last hole is the vertex at depth 1 on that path. A power change is "cut $x$ from its parent, link it to a new parent". So we need depth and "the second vertex of the root path" under cut/link — a rooted link-cut tree with subtree sizes in the splay. No `makeRoot` is ever needed, so the reversal tag disappears. (The intended solution is square-root decomposition with per-block "exit" pointers; see [advanced sqrt techniques](06-advanced-sqrt-techniques.md) for the general idea. Both are worth knowing.)

<details><summary>Solution</summary>

`access(x); splay(x)`: the splay tree of $x$ is the path $n+1, h_k, \dots, x$ in in-order, so `size(x) - 1` is the number of holes visited, which equals the number of jumps. The last hole has in-order index 1: descend by subtree sizes, then splay it to pay for the descent. A power change is `cutParent(x)` (detach the left subtree after `access(x); splay(x)`) followed by linking to the new parent. Each operation is amortised $O(\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

// Rooted link-cut tree (no makeRoot, so no reversal): parent of hole i is i + a_i, or n + 1 if it leaves.
struct RootedLCT {
    vector<array<int, 2>> ch;
    vector<int> fa, sz;
    RootedLCT(int n) : ch(n + 1, {0, 0}), fa(n + 1, 0), sz(n + 1, 1) { sz[0] = 0; }
    bool isRoot(int x) const { int f = fa[x]; return f == 0 || (ch[f][0] != x && ch[f][1] != x); }
    void pull(int x) { sz[x] = sz[ch[x][0]] + sz[ch[x][1]] + 1; }
    void rotate(int x) {
        int y = fa[x], z = fa[y], k = ch[y][1] == x;
        if (!isRoot(y)) ch[z][ch[z][1] == y] = x;
        fa[x] = z;
        ch[y][k] = ch[x][k ^ 1];
        if (ch[x][k ^ 1]) fa[ch[x][k ^ 1]] = y;
        ch[x][k ^ 1] = y;
        fa[y] = x;
        pull(y);
        pull(x);
    }
    void splay(int x) {
        while (!isRoot(x)) {
            int y = fa[x], z = fa[y];
            if (!isRoot(y)) rotate((ch[y][1] == x) == (ch[z][1] == y) ? y : x);
            rotate(x);
        }
    }
    void access(int x) {
        for (int last = 0; x; last = x, x = fa[x]) { splay(x); ch[x][1] = last; pull(x); }
    }
    void cutParent(int x) {                 // detach x from its parent (x is not the root)
        access(x); splay(x);
        fa[ch[x][0]] = 0; ch[x][0] = 0; pull(x);
    }
    void linkParent(int x, int p) { access(p); splay(p); fa[x] = p; }   // x: tree root and splay root
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<int> a(n + 1);
    RootedLCT t(n + 1);
    auto nxt = [&](int i) { return i + a[i] > n ? n + 1 : i + a[i]; };
    for (int i = 1; i <= n; i++) { cin >> a[i]; t.linkParent(i, nxt(i)); }
    while (m--) {
        int type, x;
        cin >> type >> x;
        if (type == 0) {
            int b;
            cin >> b;
            t.cutParent(x);
            a[x] = b;
            t.linkParent(x, nxt(x));
        } else {
            t.access(x); t.splay(x);
            int jumps = t.sz[x] - 1;        // the splay holds the path n+1 .. x
            int y = x, k = 1;                // find the in-order element with index 1 (0 = node n+1)
            while (true) {
                int ls = t.sz[t.ch[y][0]];
                if (k < ls) y = t.ch[y][0];
                else if (k == ls) break;
                else { k -= ls + 1; y = t.ch[y][1]; }
            }
            t.splay(y);
            cout << y << ' ' << jumps << '\n';
        }
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static int[] lc, rc, fa, sz;
    static boolean isRoot(int x) { int f = fa[x]; return f == 0 || (lc[f] != x && rc[f] != x); }
    static void pull(int x) { sz[x] = sz[lc[x]] + sz[rc[x]] + 1; }
    static void rotate(int x) {
        int y = fa[x], z = fa[y];
        boolean right = rc[y] == x;
        if (!isRoot(y)) { if (lc[z] == y) lc[z] = x; else rc[z] = x; }
        fa[x] = z;
        if (right) { rc[y] = lc[x]; if (lc[x] != 0) fa[lc[x]] = y; lc[x] = y; }
        else { lc[y] = rc[x]; if (rc[x] != 0) fa[rc[x]] = y; rc[x] = y; }
        fa[y] = x;
        pull(y);
        pull(x);
    }
    static void splay(int x) {
        while (!isRoot(x)) {
            int y = fa[x], z = fa[y];
            if (!isRoot(y)) rotate(((rc[y] == x) == (rc[z] == y)) ? y : x);
            rotate(x);
        }
    }
    static void access(int x) {
        for (int last = 0; x != 0; last = x, x = fa[x]) { splay(x); rc[x] = last; pull(x); }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt();
        int N = n + 2;
        lc = new int[N]; rc = new int[N]; fa = new int[N]; sz = new int[N];
        Arrays.fill(sz, 1);
        sz[0] = 0;
        int[] a = new int[n + 1];
        for (int i = 1; i <= n; i++) { a[i] = in.nextInt(); fa[i] = i + a[i] > n ? n + 1 : i + a[i]; }
        StringBuilder sb = new StringBuilder();
        while (m-- > 0) {
            int type = in.nextInt(), x = in.nextInt();
            if (type == 0) {
                int b = in.nextInt();
                access(x); splay(x);
                fa[lc[x]] = 0; lc[x] = 0; pull(x);          // cut x from its parent
                a[x] = b;
                int p = x + a[x] > n ? n + 1 : x + a[x];
                access(p); splay(p); fa[x] = p;              // link under the new parent
            } else {
                access(x); splay(x);
                int jumps = sz[x] - 1, y = x, k = 1;
                while (true) {
                    int ls = sz[lc[y]];
                    if (k < ls) y = lc[y];
                    else if (k == ls) break;
                    else { k -= ls + 1; y = rc[y]; }
                }
                splay(y);
                sb.append(y).append(' ').append(jumps).append('\n');
            }
        }
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
6 7
2 1 3 1 1 4
1 1
1 2
0 2 5
1 2
0 3 1
1 1
1 6
out:
6 3
6 3
2 1
6 5
6 1
-->
<!-- test
in:
1 1
1
1 1
out:
1 1
-->

### Example 2 — LCA in a forest that changes shape  ·  ★ ≈2500 (est.)

- **Source:** Original problem.
- **Difficulty:** ≈2500 (est.)
- **Problem:** A rooted forest on $n$ vertices, initially $n$ isolated roots. Operations ($q \le 3\cdot10^5$): `1 u v` — if $u$ is a root and $v$ is not in $u$'s tree, make $u$ a child of $v$; `2 u` — cut $u$ from its parent (if any); `3 u v` — print $\mathrm{LCA}(u, v)$, or $-1$ if they are in different trees.
- **Thinking from first principles:** Binary lifting needs a static tree; rebuilding after each change is $O(n\log n)$. In a link-cut tree, `access(u)` makes root…$u$ one preferred path. Then `access(v)` climbs from $v$: the first time it lands on a vertex of that path, it has found the deepest common ancestor, and that vertex is the last one splayed by the second access. Rooted forests need no reversal.

<details><summary>Solution</summary>

Keep a plain `parent[]` array only to validate operations. `findRoot` checks that $v$ is not inside $u$'s tree (for a root $u$, its tree is its subtree). `lca(u, v) = access(u)` then the return value of `access(v)`. Amortised $O(\log n)$ per operation.

```cpp
#include <bits/stdc++.h>
using namespace std;

// Rooted forest under "make u a child of v" / "cut u from its parent" / LCA queries.
struct RootedLCT {
    vector<array<int, 2>> ch;
    vector<int> fa;
    RootedLCT(int n) : ch(n + 1, {0, 0}), fa(n + 1, 0) {}
    bool isRoot(int x) const { int f = fa[x]; return f == 0 || (ch[f][0] != x && ch[f][1] != x); }
    void rotate(int x) {
        int y = fa[x], z = fa[y], k = ch[y][1] == x;
        if (!isRoot(y)) ch[z][ch[z][1] == y] = x;
        fa[x] = z;
        ch[y][k] = ch[x][k ^ 1];
        if (ch[x][k ^ 1]) fa[ch[x][k ^ 1]] = y;
        ch[x][k ^ 1] = y;
        fa[y] = x;
    }
    void splay(int x) {
        while (!isRoot(x)) {
            int y = fa[x], z = fa[y];
            if (!isRoot(y)) rotate((ch[y][1] == x) == (ch[z][1] == y) ? y : x);
            rotate(x);
        }
    }
    int access(int x) {                    // returns the last node where the path joined the old root path
        int last = 0;
        for (; x; last = x, x = fa[x]) { splay(x); ch[x][1] = last; }
        return last;
    }
    int findRoot(int x) {
        access(x); splay(x);
        while (ch[x][0]) x = ch[x][0];
        splay(x);
        return x;
    }
    void link(int u, int v) { access(u); splay(u); access(v); splay(v); fa[u] = v; }   // u is a root
    void cut(int u) { access(u); splay(u); fa[ch[u][0]] = 0; ch[u][0] = 0; }
    int lca(int u, int v) { access(u); return access(v); }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, q;
    cin >> n >> q;
    RootedLCT t(n);
    vector<int> parent(n + 1, 0);
    while (q--) {
        int type, u, v = 0;
        cin >> type >> u;
        if (type != 2) cin >> v;
        if (type == 1) {                       // ignored unless u is a root and v is outside u's tree
            if (parent[u] == 0 && t.findRoot(v) != u) { t.link(u, v); parent[u] = v; }
        } else if (type == 2) {
            if (parent[u] != 0) { t.cut(u); parent[u] = 0; }
        } else {
            cout << (t.findRoot(u) == t.findRoot(v) ? t.lca(u, v) : -1) << '\n';
        }
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static int[] lc, rc, fa;
    static boolean isRoot(int x) { int f = fa[x]; return f == 0 || (lc[f] != x && rc[f] != x); }
    static void rotate(int x) {
        int y = fa[x], z = fa[y];
        boolean right = rc[y] == x;
        if (!isRoot(y)) { if (lc[z] == y) lc[z] = x; else rc[z] = x; }
        fa[x] = z;
        if (right) { rc[y] = lc[x]; if (lc[x] != 0) fa[lc[x]] = y; lc[x] = y; }
        else { lc[y] = rc[x]; if (rc[x] != 0) fa[rc[x]] = y; rc[x] = y; }
        fa[y] = x;
    }
    static void splay(int x) {
        while (!isRoot(x)) {
            int y = fa[x], z = fa[y];
            if (!isRoot(y)) rotate(((rc[y] == x) == (rc[z] == y)) ? y : x);
            rotate(x);
        }
    }
    static int access(int x) {
        int last = 0;
        for (; x != 0; last = x, x = fa[x]) { splay(x); rc[x] = last; }
        return last;
    }
    static int findRoot(int x) {
        access(x); splay(x);
        while (lc[x] != 0) x = lc[x];
        splay(x);
        return x;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), q = in.nextInt();
        lc = new int[n + 1]; rc = new int[n + 1]; fa = new int[n + 1];
        int[] parent = new int[n + 1];
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            int type = in.nextInt(), u = in.nextInt(), v = type != 2 ? in.nextInt() : 0;
            if (type == 1) {
                if (parent[u] == 0 && findRoot(v) != u) { access(u); splay(u); access(v); splay(v); fa[u] = v; parent[u] = v; }
            } else if (type == 2) {
                if (parent[u] != 0) { access(u); splay(u); fa[lc[u]] = 0; lc[u] = 0; parent[u] = 0; }
            } else {
                if (findRoot(u) != findRoot(v)) sb.append(-1).append('\n');
                else { access(u); sb.append(access(v)).append('\n'); }
            }
        }
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
5 11
1 2 1
1 3 1
1 4 2
3 4 3
3 4 2
2 2
3 4 3
1 2 3
3 4 1
3 4 4
3 5 5
out:
1
2
-1
1
4
5
-->
<!-- test
in:
1 1
3 1 1
out:
1
-->

### Example 3 — Minimum spanning forest of a growing graph  ·  ★ ≈2600 (est.)

- **Source:** Original problem (the same mechanism appears in [CF 603E · Pastoral Oddities](https://codeforces.com/problemset/problem/603/E) — 3000 and [CF 1386C · Joker](https://codeforces.com/problemset/problem/1386/C) — 2800, both of which also have offline D&C solutions).
- **Difficulty:** ≈2600 (est.)
- **Problem:** $n$ vertices, $m \le 2\cdot10^5$ weighted edges arrive one by one (loops and multi-edges allowed, $0 \le w \le 10^9$). After each arrival print the total weight of a minimum spanning forest of the edges so far.
- **Thinking from first principles:** Rerunning Kruskal is $O(m^2\log m)$. Cycle property: when a new edge $e$ closes a cycle in the current forest, a heaviest edge of that cycle (the new edge included) can be dropped from every later minimum spanning forest too, because the cycle stays in the graph forever. So the forest changes by at most one swap: if the heaviest forest edge on the $u$–$v$ path is heavier than $e$, swap them; otherwise discard $e$. That needs "max edge on a path" under link and cut: a link-cut tree whose nodes include one node per edge.

<details><summary>Solution</summary>

Vertex nodes $1..n$ have value $-1$; edge $i$ is node $n+i$ with value $w_i$. The splay aggregate is the *index* of the maximum node, so the edge to delete is known directly. New edge $(u, v, w)$: loops are ignored; if $u, v$ are disconnected, link $u - e - v$; otherwise query the path maximum $j$, and if $w_j > w$ cut $j$ from both endpoints and link $e$. Correctness is the cycle property applied once per arrival (a discarded edge is the maximum of a cycle that stays present forever). $O(m\log(n+m))$ amortised.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

// LCT whose aggregate is the node of maximum value on the path. Vertices have value -1,
// edge i is its own node n + i with value w_i, so path maxima are edge maxima.
struct LCT {
    vector<array<int, 2>> ch;
    vector<int> fa, mx, stk;
    vector<char> rev;
    vector<ll> val;
    LCT(int n) : ch(n + 1, {0, 0}), fa(n + 1, 0), mx(n + 1, 0), rev(n + 1, 0), val(n + 1, -1) {
        iota(mx.begin(), mx.end(), 0);
    }
    bool isRoot(int x) const { int f = fa[x]; return f == 0 || (ch[f][0] != x && ch[f][1] != x); }
    void pull(int x) {
        mx[x] = x;
        for (int c : ch[x]) if (c && val[mx[c]] > val[mx[x]]) mx[x] = mx[c];
    }
    void flip(int x) { swap(ch[x][0], ch[x][1]); rev[x] ^= 1; }
    void push(int x) {
        if (!rev[x]) return;
        if (ch[x][0]) flip(ch[x][0]);
        if (ch[x][1]) flip(ch[x][1]);
        rev[x] = 0;
    }
    void rotate(int x) {
        int y = fa[x], z = fa[y], k = ch[y][1] == x;
        if (!isRoot(y)) ch[z][ch[z][1] == y] = x;
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
        while (!stk.empty()) { push(stk.back()); stk.pop_back(); }
        while (!isRoot(x)) {
            int y = fa[x], z = fa[y];
            if (!isRoot(y)) rotate((ch[y][1] == x) == (ch[z][1] == y) ? y : x);
            rotate(x);
        }
    }
    void access(int x) {
        for (int last = 0; x; last = x, x = fa[x]) { splay(x); ch[x][1] = last; pull(x); }
    }
    void makeRoot(int x) { access(x); splay(x); flip(x); }
    int findRoot(int x) {
        access(x); splay(x);
        while (true) { push(x); if (!ch[x][0]) break; x = ch[x][0]; }
        splay(x);
        return x;
    }
    void link(int u, int v) { makeRoot(u); access(v); splay(v); fa[u] = v; }   // caller guarantees different trees
    void cut(int u, int v) { makeRoot(u); access(v); splay(v); ch[v][0] = 0; fa[u] = 0; pull(v); }  // caller guarantees edge u-v
    int pathMax(int u, int v) { makeRoot(u); access(v); splay(v); return mx[v]; }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    LCT t(n + m);
    vector<int> eu(m + 1), ev(m + 1);
    ll total = 0;
    for (int i = 1; i <= m; i++) {
        int u, v;
        ll w;
        cin >> u >> v >> w;
        eu[i] = u; ev[i] = v;
        int e = n + i;
        t.val[e] = w; t.mx[e] = e;
        if (u != v) {
            if (t.findRoot(u) != t.findRoot(v)) {
                t.link(u, e); t.link(e, v); total += w;
            } else {
                int j = t.pathMax(u, v);                   // heaviest edge on the cycle
                if (t.val[j] > w) {
                    int old = j - n;
                    t.cut(eu[old], j); t.cut(j, ev[old]);
                    total -= t.val[j];
                    t.link(u, e); t.link(e, v); total += w;
                }
            }
        }
        cout << total << '\n';
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static int[] lc, rc, fa, mx, stk;
    static boolean[] rev;
    static long[] val;

    static boolean isRoot(int x) { int f = fa[x]; return f == 0 || (lc[f] != x && rc[f] != x); }
    static void pull(int x) {
        mx[x] = x;
        if (lc[x] != 0 && val[mx[lc[x]]] > val[mx[x]]) mx[x] = mx[lc[x]];
        if (rc[x] != 0 && val[mx[rc[x]]] > val[mx[x]]) mx[x] = mx[rc[x]];
    }
    static void flip(int x) { int t = lc[x]; lc[x] = rc[x]; rc[x] = t; rev[x] = !rev[x]; }
    static void push(int x) {
        if (!rev[x]) return;
        if (lc[x] != 0) flip(lc[x]);
        if (rc[x] != 0) flip(rc[x]);
        rev[x] = false;
    }
    static void rotate(int x) {
        int y = fa[x], z = fa[y];
        boolean right = rc[y] == x;
        if (!isRoot(y)) { if (lc[z] == y) lc[z] = x; else rc[z] = x; }
        fa[x] = z;
        if (right) { rc[y] = lc[x]; if (lc[x] != 0) fa[lc[x]] = y; lc[x] = y; }
        else { lc[y] = rc[x]; if (rc[x] != 0) fa[rc[x]] = y; rc[x] = y; }
        fa[y] = x;
        pull(y);
        pull(x);
    }
    static void splay(int x) {
        int top = 0;
        for (int y = x;; y = fa[y]) { stk[top++] = y; if (isRoot(y)) break; }
        while (top > 0) push(stk[--top]);
        while (!isRoot(x)) {
            int y = fa[x], z = fa[y];
            if (!isRoot(y)) rotate(((rc[y] == x) == (rc[z] == y)) ? y : x);
            rotate(x);
        }
    }
    static void access(int x) { for (int last = 0; x != 0; last = x, x = fa[x]) { splay(x); rc[x] = last; pull(x); } }
    static void makeRoot(int x) { access(x); splay(x); flip(x); }
    static int findRoot(int x) {
        access(x); splay(x);
        while (true) { push(x); if (lc[x] == 0) break; x = lc[x]; }
        splay(x);
        return x;
    }
    static void link(int u, int v) { makeRoot(u); access(v); splay(v); fa[u] = v; }
    static void cut(int u, int v) { makeRoot(u); access(v); splay(v); lc[v] = 0; fa[u] = 0; pull(v); }
    static int pathMax(int u, int v) { makeRoot(u); access(v); splay(v); return mx[v]; }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt();
        int N = n + m + 1;
        lc = new int[N]; rc = new int[N]; fa = new int[N]; mx = new int[N]; stk = new int[N];
        rev = new boolean[N]; val = new long[N];
        for (int i = 0; i < N; i++) { mx[i] = i; val[i] = -1; }
        int[] eu = new int[m + 1], ev = new int[m + 1];
        long total = 0;
        StringBuilder sb = new StringBuilder();
        for (int i = 1; i <= m; i++) {
            int u = in.nextInt(), v = in.nextInt();
            long w = in.nextLong();
            eu[i] = u; ev[i] = v;
            int e = n + i;
            val[e] = w;
            if (u != v) {
                if (findRoot(u) != findRoot(v)) {
                    link(u, e); link(e, v); total += w;
                } else {
                    int j = pathMax(u, v);
                    if (val[j] > w) {
                        int old = j - n;
                        cut(eu[old], j); cut(j, ev[old]);
                        total -= val[j];
                        link(u, e); link(e, v); total += w;
                    }
                }
            }
            sb.append(total).append('\n');
        }
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
4 6
1 2 5
2 3 4
1 3 3
3 4 7
1 4 1
2 4 2
out:
5
9
7
14
8
6
-->
<!-- test
in:
1 1
1 1 5
out:
0
-->
<!-- test
in:
3 4
1 2 0
2 1 0
2 3 1000000000
3 2 999999999
out:
0
0
1000000000
999999999
-->

All three examples were stress-tested against naive versions (direct simulation, parent-array LCA, Kruskal from scratch after every edge) on 300 random cases each, and timed at maximum size: about 0.5–0.8 s for Example 1 and 2.0–3.1 s for Example 3 ($m = 2\cdot10^5$) on the test machine.

## 6. Tricks, pitfalls and things to remember

1. **`isRoot` before rotating.** In `rotate(x)`, decide whether $y$ was a splay root *before* overwriting `fa`; otherwise a path-parent pointer gets turned into a child pointer and the structure silently corrupts.
2. **Push before splay.** Reversal tags must be pushed from the splay root down to $x$ before any rotation. Collect the ancestors on a stack (no recursion — a degenerate splay can be $10^5$ deep).
3. **Push while walking down.** `findRoot` and any "k-th node" descent must push tags on the way, or they read swapped children.
4. **Splay after descending.** Walking down without splaying the found node breaks the amortised bound — an adversary can make you walk a long path repeatedly.
5. **Null node 0.** Its aggregate must be the neutral element and it must never be flipped or pulled; guard `flip` calls with `if (child)`.
6. **Reversal and non-commutative aggregates.** For "max" or "sum" a flip changes nothing in the aggregate. For ordered aggregates (string hash of the path, composition of functions) keep both directions and swap them in `flip`.
7. **Edge values belong in edge nodes.** Storing an edge's value at its lower endpoint (the HLD trick) breaks as soon as `makeRoot` changes which endpoint is lower.
8. **Validate cuts.** If the statement allows invalid cuts, use the `fa[v] == u && !ch[v][0]` check after `makeRoot(u); findRoot(v)`; otherwise a "cut" of a non-edge deletes a random edge.
9. **Link at the root of the auxiliary tree** (`access(v); splay(v)` before `fa[u] = v`) — needed for the amortised bound, cheap in practice.
10. **Java:** use parallel `int[]` arrays (`lc`, `rc`, `fa`), not node objects; avoid recursion; read input with a byte buffer. Expect about 1.1–1.5× the C++ time.
11. **Do you really need it?** Before writing 120 lines, check the "HLD suffices" and "offline" lists in §1.5 and §4.

## 7. Going further (toward 2400–2600+)

- **Subtree aggregates in an LCT:** store for each node the sum over its *virtual* children (subtrees hanging by path-parent pointers) and update it in `access` when the preferred child changes. Then "size of $x$'s component" or "subtree sum under the current root" become available. This is the trick behind problems that mix path and subtree information.
- **LCT as a dynamic MST engine:** maximum spanning forest by deletion time answers offline dynamic connectivity online-per-step (compare with [segment tree on time](02-segment-tree-on-time-and-dsu-rollback.md)); minimum spanning forest by weight gives "bottleneck path" queries.
- **Bipartiteness / parity with LCT:** keep the forest of a spanning forest plus counts of "bad" non-tree edges; used in [CF 1386C · Joker](https://codeforces.com/problemset/problem/1386/C) — 2800 and [CF 603E · Pastoral Oddities](https://codeforces.com/problemset/problem/603/E) — 3000 style problems.
- **Access as a counting device:** the number of preferred-child changes during `access` equals the number of "colour changes" on a root path when `access` paints the path with a new colour — the key insight of [CF 1137F · Matches Are Not a Child's Play](https://codeforces.com/problemset/problem/1137/F) — 3400 and related "colour the root path" problems.
- **Euler tour trees and top trees** (🧊): know they exist; reach for them only when you need subtree aggregates under reroot/link/cut and the LCT virtual-subtree trick is not enough.

## 8. Practice ladder

2400–2800
- [ ] [CF 916E · Jamie and Tree](https://codeforces.com/problemset/problem/916/E) — 2400 — reroot on a static tree: HLD/Euler tour is enough (recognise it)
- [ ] [CSES 2101 · New Roads Queries](https://cses.fi/problemset/task/2101) — path maximum in the incremental forest (LCT, or DSU + binary lifting offline)
- [ ] [CSES 2133 · Dynamic Connectivity](https://cses.fi/problemset/task/2133) — try the "maximum spanning forest by deletion time" LCT solution
- [ ] [CF 13E · Holes](https://codeforces.com/problemset/problem/13/E) — 2700 — Example 1
- [ ] [CF 1386C · Joker](https://codeforces.com/problemset/problem/1386/C) — 2800 — LCT or D&C with rollback

2900+
- [ ] [CF 117E · Tree or not Tree](https://codeforces.com/problemset/problem/117/E) — 2900 — unicyclic graph, HLD on the tree part
- [ ] [CF 603E · Pastoral Oddities](https://codeforces.com/problemset/problem/603/E) — 3000 — LCT on edge nodes (or D&C)
- [ ] [CF 1109F · Sasha and Algorithm of Silence's Sounds](https://codeforces.com/problemset/problem/1109/F) — 3200 — two pointers + LCT + segment tree
- [ ] [CF 482E · ELCA](https://codeforces.com/problemset/problem/482/E) — 3200 — dynamic parent changes with subtree statistics
- [ ] [CF 1172E · Nauuo and ODT](https://codeforces.com/problemset/problem/1172/E) — 3300 — LCT maintaining component sizes
- [ ] [CF 1137F · Matches Are Not a Child's Play](https://codeforces.com/problemset/problem/1137/F) — 3400 — access counts colour changes

## 9. LeetCode / FAANG cross-reference

Rare in interviews: no LeetCode problem requires a link-cut tree, and the implementation is far too long for an interview. The interview-level relatives are static: LCA ([LC 236](https://leetcode.com/problems/lowest-common-ancestor-of-a-binary-tree/)-style problems, covered in [trees and BST](../17-FAANG-Interview-DSA/07-trees-and-bst.md)) and union–find connectivity.

## 10. Self-check

1. What two kinds of parent does `fa[]` store, and how does `isRoot` tell them apart?
2. After `access(x)`, which vertices are in $x$'s splay tree, and why is nothing deeper there?
3. Why does `makeRoot(x)` need only a lazy reversal of one splay tree?
4. State the access lemma and show how the costs of the splays inside one `access` telescope.
5. Why is the number of preferred-child changes amortised $O(\log n)$ per access?
6. How do you represent edge weights, and why not store them at the lower endpoint?
7. How do you compute the LCA of $u$ and $v$ in a rooted forest with an LCT?
8. Name three situations where HLD or an offline method is preferable to an LCT.

<details><summary>Answers</summary>

1. Splay-tree parents and path-parents. $x$ is a splay root iff `fa[x]` is null or `fa[x]` has neither child equal to $x$.
2. Exactly the vertices on the root–$x$ path; the first loop iteration sets $x$'s right child (the deeper part of its old preferred path) to null.
3. Rerooting reverses the parent direction only along the old root–$x$ path, which is that splay tree's in-order; other paths keep their order and hang off by path-parent pointers.
4. Splaying $x$ to the root $t$ costs $\le 3(r(t)-r(x))+1$ amortised. In one access, the next splayed node is the path-parent of the previous splay tree, so its rank is at least the previous root's rank; the sum is $\le 3(r(\text{root})-r(x)) + k$.
5. Light preferred edges are created at most $\log n$ times per access; heavy ones need a previous light creation or an initial state; link/cut perturb $O(\log n)$ edges.
6. As extra nodes between the endpoints; the "lower endpoint" changes when the tree is rerooted.
7. `access(u)`; the return value (last splayed node) of `access(v)`.
8. Static shape with value updates (HLD); links only offline (DSU + HLD on the final forest); connectivity with deletions offline (segment tree on time); subtree aggregates under reroot (Euler tour tree / HLD).

</details>
