# Binary Lifting, LCA, Euler-Tour Flattening and Heavy-Light Decomposition

> **Folder 03 · File 1 of 3** — three ways to answer "lowest common ancestor", the one traversal that turns subtrees into array ranges, and the decomposition that turns paths into O(log n) ranges. All iterative, all checked against parent-walking oracles.
> **Languages:** Java 21 (`--release 21 -Xlint:all -Werror`, JDK 25.0.4.1) and C++23 (GCC 16.2 and Clang 21.1, `-O2`, warnings as errors).

| Listing | File | What it proves |
|---|---|---|
| 3.1 | `TreeQueries.java` | A validated, immutable `Tree` built by one heavy-first iterative DFS; binary lifting in two memory layouts; Euler tour + sparse table; subtree and path sums via Fenwick over HLD positions; ancestor tests from labels. 90,000 random operations; a 524,288-deep chain |
| 3.2 | `tree_queries.cpp` | The same in C++23; identical correctness counts; a 40–50× spread between LCA implementations of the same asymptotic class |

**Verification.** Both listings were extracted from this file, compiled and run. Everything is **Output (verified)** except the timing lines (**one measured run**).

---

## 0. Orientation

Tree queries are where contest code is most fragile in production: recursive DFS (stack overflow on a 10⁵-deep chain), global arrays sized `MAXN` and `LOG = 17`, and node ids assumed to be `1..n` with node 1 the root. The Staff version is mostly *the same algorithms*, but with a construction step that **validates** the input (exactly one root, no cycles, everything reachable), **lays out** the tree once, and then serves queries from immutable arrays that any number of threads can read.

| Contest habit | What breaks | L7 replacement |
|---|---|---|
| Recursive DFS | `StackOverflowError` at about 15k frames on a 1 MiB stack (Folder 01) | One explicit-stack DFS that computes everything |
| Trust the input is a tree | A cycle or a forest loops forever or silently ignores nodes | Validate: one root, all `n` nodes reached, or `IllegalArgumentException` / `std::invalid_argument` |
| `up[LOG][MAXN]` globals | Fixed limits; layout chosen by accident | Instance arrays sized from `n`; layout chosen and **measured** |
| Separate DFS per technique | Three traversals, three orders to keep in sync | One heavy-first preorder gives subtree ranges, heavy paths and the Euler tour together |
| Recompute LCA for "is u an ancestor of v" | O(log n) or worse per check | Two integer comparisons on preorder labels |

---

## 1. First principles

### 1.1 Preorder labels turn subtrees into ranges

In a preorder DFS, a node's whole subtree is visited contiguously, immediately after the node itself. If `pos[v]` is v's preorder index and `size[v]` its subtree size, then:

* subtree(v) = positions `[pos[v], pos[v] + size[v])`;
* u is an ancestor of v ⇔ `pos[u] ≤ pos[v] < pos[u] + size[u]`.

This is the **nested-sets** labelling. Every "aggregate over a subtree" becomes an aggregate over an array range, so a Fenwick tree or segment tree over `pos` order answers subtree sums with point updates in O(log n). Databases use the same labels to answer hierarchy queries ("all reports under this manager") with one range scan.

### 1.2 LCA by binary lifting

Store, for every node v and every k, the 2^k-th ancestor `up[k][v]`. To find LCA(u, v): lift the deeper node by the depth difference, one set bit at a time. Then, for k from high to low, if `up[k][u] ≠ up[k][v]`, lift both. Invariant: u and v are at the same depth and strictly below their LCA. When no level can move them, their parent is the answer. O(n log n) preprocessing, O(log n) per query. It also answers "k-th ancestor" directly, which the Euler method does not.

### 1.3 LCA by Euler tour + range minimum

Write down each node every time the DFS is *at* it: on entry, and again after returning from each child. The sequence has `2n − 1` entries. The LCA of u and v is the **shallowest node between any occurrence of u and any occurrence of v** in that sequence: the walk from u to v must pass through their LCA and never above it. With a **sparse table** over the tour (minimum depth over each power-of-two window), each query is two overlapping lookups: **O(1)** per query after O(n log n) preprocessing. It needs more memory than lifting but no loop at query time.

### 1.4 Heavy-light decomposition

For every node, call the child with the largest subtree **heavy** and the other edges **light**. Moving down a light edge at least halves the subtree size, so **any root-to-node path crosses O(log n) light edges**. If the DFS visits the heavy child first, each maximal chain of heavy edges (a *heavy path*) occupies **consecutive** positions. A path query u→v then becomes O(log n) contiguous ranges, one per heavy path crossed, each answered by a Fenwick or segment tree. That's O(log² n) per path query, and subtree ranges still work because the order is a preorder. The listing builds pos, size, heavy, head and the Euler tour in **one** explicit-stack DFS.

### 1.5 Validation is part of construction

Given a parent array, a valid rooted tree has exactly one `−1`, all other parents in range, and every node reachable from the root. A cycle among non-root nodes leaves them unreachable. The constructor counts the visited nodes and rejects the input otherwise. The listing shows both failure messages: *"no root (a cycle)"* and *"not a tree: 2 nodes unreachable from the root"*.

---

## 2. The listings

### 2.1 Listing 3.1 — Java

```java
// TreeQueries.java - LCA by binary lifting and by Euler tour + sparse table, subtree flattening, heavy-light paths; no recursion.
import java.util.function.IntBinaryOperator;

public final class TreeQueries {

    static final class SplitMix64 {
        private long state;
        SplitMix64(long seed) { state = seed; }
        long next() {
            long z = (state += 0x9E3779B97F4A7C15L);
            z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
            z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
            return z ^ (z >>> 31);
        }
        int nextInt(int bound) { return (int) Long.remainderUnsigned(next(), bound); }
    }

    /**
     * A rooted tree validated and laid out once by an iterative DFS: CSR children, depth, subtree size, and a preorder
     * in which every heavy child comes first, so that (a) each subtree is the contiguous range [pos, pos + size) and
     * (b) each heavy path is contiguous too. Immutable after construction: safe to share across threads.
     */
    static final class Tree {
        final int n, root;
        final int[] parent, depth, size, heavy, head, pos, euler, first;

        Tree(int[] par) {
            n = par.length;
            int r = -1;
            int[] childCount = new int[n + 1];
            for (int v = 0; v < n; v++) {
                if (par[v] == -1) {
                    if (r != -1) throw new IllegalArgumentException("two roots: " + r + " and " + v);
                    r = v;
                } else if (par[v] < 0 || par[v] >= n) {
                    throw new IllegalArgumentException("bad parent " + par[v] + " of " + v);
                } else {
                    childCount[par[v] + 1]++;
                }
            }
            if (r == -1) throw new IllegalArgumentException("no root (a cycle)");
            root = r;
            parent = par.clone();
            int[] start = new int[n + 1];
            for (int v = 0; v < n; v++) start[v + 1] = start[v] + childCount[v + 1];
            int[] fill = start.clone(), kids = new int[Math.max(0, n - 1)];
            for (int v = 0; v < n; v++) if (par[v] != -1) kids[fill[par[v]]++] = v;

            depth = new int[n];
            size = new int[n];
            heavy = new int[n];
            int[] order = new int[n], stack = new int[n];
            int top = 0, seen = 0;
            stack[top++] = root;
            while (top > 0) {                                   // pass 1: preorder, depths
                int v = stack[--top];
                order[seen++] = v;
                for (int i = start[v]; i < start[v + 1]; i++) {
                    depth[kids[i]] = depth[v] + 1;
                    stack[top++] = kids[i];
                }
            }
            if (seen != n) throw new IllegalArgumentException("not a tree: " + (n - seen) + " nodes unreachable from the root");
            for (int i = n - 1; i >= 0; i--) {                  // pass 2: sizes and heavy children, bottom-up
                int v = order[i];
                size[v]++;
                heavy[v] = -1;
                for (int k = start[v]; k < start[v + 1]; k++) {
                    int c = kids[k];
                    if (heavy[v] == -1 || size[c] > size[heavy[v]]) heavy[v] = c;
                }
                if (par[v] != -1) size[par[v]] += size[v];
            }
            head = new int[n];
            pos = new int[n];
            euler = new int[2 * n - 1];
            first = new int[n];
            int[] nextKid = new int[n];                         // pass 3: heavy-first DFS with an explicit stack
            int cur = 0, e = 0;
            top = 0;
            stack[top++] = root;
            head[root] = root;
            pos[root] = cur++;
            first[root] = e;
            euler[e++] = root;
            nextKid[root] = -1;                                 // -1 = heavy child not visited yet
            while (top > 0) {
                int v = stack[top - 1], c = -1;
                if (nextKid[v] == -1) {
                    nextKid[v] = start[v];
                    c = heavy[v];
                } else {
                    while (nextKid[v] < start[v + 1] && kids[nextKid[v]] == heavy[v]) nextKid[v]++;
                    if (nextKid[v] < start[v + 1]) c = kids[nextKid[v]++];
                }
                if (c == -1) {
                    top--;
                    if (top > 0) euler[e++] = stack[top - 1];   // back in the parent
                    continue;
                }
                head[c] = c == heavy[v] ? head[v] : c;
                pos[c] = cur++;
                first[c] = e;
                euler[e++] = c;
                nextKid[c] = -1;
                stack[top++] = c;
            }
        }

        /** u is an ancestor of v (or u == v): two comparisons on labels, no traversal. */
        boolean isAncestor(int u, int v) { return pos[u] <= pos[v] && pos[v] < pos[u] + size[u]; }
    }

    // ===================================================================== LCA 1: binary lifting, O(n log n) / O(log n)
    static final class Lifting {
        private final int[][] up;
        private final int[] depth;

        Lifting(Tree t) {
            int log = 1;
            while ((1 << log) < t.n) log++;
            up = new int[log][t.n];
            depth = t.depth;
            for (int v = 0; v < t.n; v++) up[0][v] = t.parent[v] == -1 ? v : t.parent[v];
            for (int k = 1; k < log; k++) for (int v = 0; v < t.n; v++) up[k][v] = up[k - 1][up[k - 1][v]];
        }

        int lca(int u, int v) {
            if (depth[u] < depth[v]) { int x = u; u = v; v = x; }
            for (int k = up.length - 1, diff = depth[u] - depth[v]; k >= 0; k--) if ((diff >> k & 1) == 1) u = up[k][u];
            if (u == v) return u;
            for (int k = up.length - 1; k >= 0; k--) if (up[k][u] != up[k][v]) { u = up[k][u]; v = up[k][v]; }
            return up[0][u];
        }
    }

    /** Same algorithm, node-major layout: all of v's ancestors share one or two cache lines (File 1.2's lesson). */
    static final class LiftingNodeMajor {
        private final int[] anc;   // anc[v * log + k] = 2^k-th ancestor of v
        private final int[] depth;
        private final int log;

        LiftingNodeMajor(Tree t) {
            int lg = 1;
            while ((1 << lg) < t.n) lg++;
            log = lg;
            depth = t.depth;
            anc = new int[t.n * log];
            int[] order = new int[t.n];                          // parents before children, so anc[parent] is ready
            for (int v = 0; v < t.n; v++) order[t.pos[v]] = v;
            for (int v : order) {
                int p = t.parent[v] == -1 ? v : t.parent[v];
                anc[v * log] = p;
                for (int k = 1; k < log; k++) anc[v * log + k] = anc[anc[v * log + k - 1] * log + k - 1];
            }
        }

        int lca(int u, int v) {
            if (depth[u] < depth[v]) { int x = u; u = v; v = x; }
            for (int k = log - 1, diff = depth[u] - depth[v]; k >= 0; k--) if ((diff >> k & 1) == 1) u = anc[u * log + k];
            if (u == v) return u;
            for (int k = log - 1; k >= 0; k--) {
                int au = anc[u * log + k], av = anc[v * log + k];
                if (au != av) { u = au; v = av; }
            }
            return anc[u * log];
        }
    }

    // ===================================================================== LCA 2: Euler tour + sparse table, O(1) query
    static final class EulerRmq {
        private final int[][] table;  // table[k][i] = shallowest node among euler[i, i + 2^k)
        private final Tree t;

        EulerRmq(Tree t) {
            this.t = t;
            int m = t.euler.length, levels = 32 - Integer.numberOfLeadingZeros(m);
            table = new int[levels][];
            table[0] = t.euler.clone();
            for (int k = 1; k < levels; k++) {
                table[k] = new int[m - (1 << k) + 1];
                for (int i = 0; i < table[k].length; i++) table[k][i] = shallower(table[k - 1][i], table[k - 1][i + (1 << (k - 1))]);
            }
        }

        private int shallower(int a, int b) { return t.depth[a] <= t.depth[b] ? a : b; }

        int lca(int u, int v) {
            int l = Math.min(t.first[u], t.first[v]), r = Math.max(t.first[u], t.first[v]);
            int k = 31 - Integer.numberOfLeadingZeros(r - l + 1);
            return shallower(table[k][l], table[k][r - (1 << k) + 1]);
        }
    }

    // ===================================================================== values on nodes: subtree and path sums
    static final class Fenwick {
        private final long[] f;
        Fenwick(int n) { f = new long[n + 1]; }
        void add(int i, long d) { for (i++; i < f.length; i += i & -i) f[i] += d; }
        long prefix(int i) { long s = 0; for (i++; i > 0; i -= i & -i) s += f[i]; return s; }  // sum of [0, i]
        long range(int l, int r) { return prefix(r) - (l == 0 ? 0 : prefix(l - 1)); }
    }

    /** Point update, subtree sum and path sum. Heavy-light: any root-to-node path crosses O(log n) light edges. */
    static final class NodeValues {
        private final Tree t;
        private final Fenwick fw;

        NodeValues(Tree t) {
            this.t = t;
            fw = new Fenwick(t.n);
        }

        void add(int v, long d) { fw.add(t.pos[v], d); }

        long subtreeSum(int v) { return fw.range(t.pos[v], t.pos[v] + t.size[v] - 1); }

        long pathSum(int u, int v) {
            long s = 0;
            while (t.head[u] != t.head[v]) {
                if (t.depth[t.head[u]] < t.depth[t.head[v]]) { int x = u; u = v; v = x; }
                s += fw.range(t.pos[t.head[u]], t.pos[u]);
                u = t.parent[t.head[u]];
            }
            if (t.depth[u] > t.depth[v]) { int x = u; u = v; v = x; }
            return s + fw.range(t.pos[u], t.pos[v]);
        }
    }

    // ===================================================================== oracles: walk the parent pointers
    static int naiveLca(int[] par, int[] depth, int u, int v) {
        while (depth[u] > depth[v]) u = par[u];
        while (depth[v] > depth[u]) v = par[v];
        while (u != v) { u = par[u]; v = par[v]; }
        return u;
    }

    static int[] randomParents(SplitMix64 r, int n, int shape) {
        int[] par = new int[n];
        int[] label = new int[n];                             // random relabelling: node ids carry no structure
        for (int i = 0; i < n; i++) label[i] = i;
        for (int i = n - 1; i > 0; i--) { int j = r.nextInt(i + 1), x = label[i]; label[i] = label[j]; label[j] = x; }
        par[label[0]] = -1;
        for (int i = 1; i < n; i++) {
            int p = shape == 0 ? r.nextInt(i) : shape == 1 ? i - 1 : 0;   // random recursive / path / star
            par[label[i]] = label[p];
        }
        return par;
    }

    static double timeLca(IntBinaryOperator lca, int[] qu, int[] qv, long[] check) {
        long t0 = System.nanoTime(), s = 0;
        for (int i = 0; i < qu.length; i++) s += lca.applyAsInt(qu[i], qv[i]);
        check[0] = s;
        return (System.nanoTime() - t0) / (double) qu.length;
    }

    public static void main(String[] args) {
        SplitMix64 r = new SplitMix64(51);
        int trials = 3_000, ops = 0, bad = 0;
        for (int t = 0; t < trials; t++) {
            int n = 1 + r.nextInt(40), shape = r.nextInt(3);
            int[] par = randomParents(r, n, shape);
            Tree tree = new Tree(par);
            Lifting lift = new Lifting(tree);
            LiftingNodeMajor lift2 = new LiftingNodeMajor(tree);
            EulerRmq rmq = new EulerRmq(tree);
            NodeValues vals = new NodeValues(tree);
            long[] val = new long[n];
            for (int q = 0; q < 30; q++, ops++) {
                int u = r.nextInt(n), v = r.nextInt(n), kind = r.nextInt(5);
                switch (kind) {
                    case 0 -> {
                        long d = r.nextInt(2_000_001) - 1_000_000;
                        val[u] += d;
                        vals.add(u, d);
                    }
                    case 1 -> {
                        int want = naiveLca(par, tree.depth, u, v);
                        if (lift.lca(u, v) != want || lift2.lca(u, v) != want || rmq.lca(u, v) != want) bad++;
                    }
                    case 2 -> {
                        int w = naiveLca(par, tree.depth, u, v);
                        long want = val[w];
                        for (int x = u; x != w; x = par[x]) want += val[x];
                        for (int x = v; x != w; x = par[x]) want += val[x];
                        if (vals.pathSum(u, v) != want) bad++;
                    }
                    case 3 -> {
                        long want = 0;
                        for (int x = 0; x < n; x++) if (naiveLca(par, tree.depth, u, x) == u) want += val[x];
                        if (vals.subtreeSum(u) != want) bad++;
                    }
                    default -> {
                        if (tree.isAncestor(u, v) != (naiveLca(par, tree.depth, u, v) == u)) bad++;
                    }
                }
            }
        }
        System.out.printf("random trees (recursive / path / star, n <= 40, relabelled): %,d operations, %d mismatches vs parent-walking oracles%n",
                ops, bad);
        try {
            new Tree(new int[] {1, 2, 0});
        } catch (IllegalArgumentException e) {
            System.out.println("Tree(parents of a 3-cycle) -> IllegalArgumentException: " + e.getMessage());
        }
        try {
            new Tree(new int[] {-1, 2, 1});
        } catch (IllegalArgumentException e) {
            System.out.println("Tree(root + detached 2-cycle) -> IllegalArgumentException: " + e.getMessage());
        }

        int n = 1 << 19, queries = 1 << 20;
        String[] shapes = {"random recursive tree", "path (depth n)"};
        System.out.printf("n=%,d nodes, %,d random LCA queries (one measured run):%n", n, queries);
        for (int shape = 0; shape < 2; shape++) {
            int[] par = randomParents(r, n, shape);
            long t0 = System.nanoTime();
            Tree tree = new Tree(par);
            long t1 = System.nanoTime();
            Lifting lift = new Lifting(tree);
            long t2 = System.nanoTime();
            EulerRmq rmq = new EulerRmq(tree);
            long t3 = System.nanoTime();
            LiftingNodeMajor lift2 = new LiftingNodeMajor(tree);
            int[] qu = new int[queries], qv = new int[queries];
            for (int i = 0; i < queries; i++) { qu[i] = r.nextInt(n); qv[i] = r.nextInt(n); }
            long[] c1 = new long[1], c2 = new long[1], c3 = new long[1];
            timeLca(lift::lca, qu, qv, c1);  // warm-up passes
            timeLca(lift2::lca, qu, qv, c3);
            double nsLift = timeLca(lift::lca, qu, qv, c1), nsLift2 = timeLca(lift2::lca, qu, qv, c3);
            double nsRmq = timeLca(rmq::lca, qu, qv, c2);
            int maxDepth = 0;
            for (int d : tree.depth) maxDepth = Math.max(maxDepth, d);
            System.out.printf("   %-22s depth %,7d | layout %3d ms | lifting build %3d ms: up[k][v] %4.0f ns/query, up[v][k] %4.0f |"
                    + " Euler+sparse build %3d ms, %3.0f ns/query | agree %b%n", shapes[shape], maxDepth, (t1 - t0) / 1_000_000,
                    (t2 - t1) / 1_000_000, nsLift, nsLift2, (t3 - t2) / 1_000_000, nsRmq, c1[0] == c2[0] && c2[0] == c3[0]);
        }
    }
}
```

**Output (verified; the last three lines are one measured run):**

```text
random trees (recursive / path / star, n <= 40, relabelled): 90,000 operations, 0 mismatches vs parent-walking oracles
Tree(parents of a 3-cycle) -> IllegalArgumentException: no root (a cycle)
Tree(root + detached 2-cycle) -> IllegalArgumentException: not a tree: 2 nodes unreachable from the root
n=524,288 nodes, 1,048,576 random LCA queries (one measured run):
   random recursive tree  depth      30 | layout 123 ms | lifting build  11 ms: up[k][v]  422 ns/query, up[v][k]  248 | Euler+sparse build  35 ms,  43 ns/query | agree true
   path (depth n)         depth 524,287 | layout 127 ms | lifting build  17 ms: up[k][v]  637 ns/query, up[v][k]  672 | Euler+sparse build  45 ms,  57 ns/query | agree true
```

### 2.2 Listing 3.2 — C++23

```cpp
// tree_queries.cpp - LCA by binary lifting and by Euler tour + sparse table, subtree flattening, heavy-light paths; no recursion.
#include <algorithm>
#include <bit>
#include <chrono>
#include <cstdint>
#include <format>
#include <print>
#include <span>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using Vec = std::vector<int>;

struct SplitMix64 {
    std::uint64_t state;
    std::uint64_t next() noexcept {
        std::uint64_t z = (state += 0x9E3779B97F4A7C15ULL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }
    int next_int(int bound) noexcept { return static_cast<int>(next() % static_cast<std::uint64_t>(bound)); }
};

inline std::size_t U(int x) { return static_cast<std::size_t>(x); }

// A rooted tree validated and laid out once by an iterative DFS: depth, subtree size, and a preorder in which every
// heavy child comes first, so each subtree is [pos, pos + size) and each heavy path is contiguous. Immutable after
// construction: safe to share across threads without synchronization.
class Tree {
public:
    int n, root = -1;
    Vec parent, depth, size, heavy, head, pos, euler, first;

    explicit Tree(std::span<const int> par) : n(static_cast<int>(par.size())), parent(par.begin(), par.end()) {
        Vec child_count(U(n) + 1);
        for (int v = 0; v < n; ++v) {
            int p = par[U(v)];
            if (p == -1) {
                if (root != -1) throw std::invalid_argument(std::format("two roots: {} and {}", root, v));
                root = v;
            } else if (p < 0 || p >= n) {
                throw std::invalid_argument(std::format("bad parent {} of {}", p, v));
            } else {
                ++child_count[U(p) + 1];
            }
        }
        if (root == -1) throw std::invalid_argument("no root (a cycle)");
        Vec start(U(n) + 1);
        for (int v = 0; v < n; ++v) start[U(v) + 1] = start[U(v)] + child_count[U(v) + 1];
        Vec fill = start, kids(U(std::max(0, n - 1)));
        for (int v = 0; v < n; ++v)
            if (par[U(v)] != -1) kids[U(fill[U(par[U(v)])]++)] = v;

        depth.assign(U(n), 0);
        size.assign(U(n), 0);
        heavy.assign(U(n), -1);
        Vec order, stack{root};
        order.reserve(U(n));
        while (!stack.empty()) {  // pass 1: preorder, depths
            int v = stack.back();
            stack.pop_back();
            order.push_back(v);
            for (int i = start[U(v)]; i < start[U(v) + 1]; ++i) {
                depth[U(kids[U(i)])] = depth[U(v)] + 1;
                stack.push_back(kids[U(i)]);
            }
        }
        if (static_cast<int>(order.size()) != n)
            throw std::invalid_argument(std::format("not a tree: {} nodes unreachable from the root", n - static_cast<int>(order.size())));
        for (auto it = order.rbegin(); it != order.rend(); ++it) {  // pass 2: sizes and heavy children, bottom-up
            int v = *it;
            ++size[U(v)];
            for (int k = start[U(v)]; k < start[U(v) + 1]; ++k) {
                int c = kids[U(k)];
                if (heavy[U(v)] == -1 || size[U(c)] > size[U(heavy[U(v)])]) heavy[U(v)] = c;
            }
            if (par[U(v)] != -1) size[U(par[U(v)])] += size[U(v)];
        }
        head.assign(U(n), 0);
        pos.assign(U(n), 0);
        first.assign(U(n), 0);
        euler.reserve(U(2 * n - 1));
        Vec next_kid(U(n), -1);  // -1 = heavy child not visited yet
        int cur = 0;
        stack.assign(1, root);
        head[U(root)] = root;
        pos[U(root)] = cur++;
        first[U(root)] = 0;
        euler.push_back(root);
        while (!stack.empty()) {  // pass 3: heavy-first DFS with an explicit stack
            int v = stack.back(), c = -1;
            if (next_kid[U(v)] == -1) {
                next_kid[U(v)] = start[U(v)];
                c = heavy[U(v)];
            } else {
                while (next_kid[U(v)] < start[U(v) + 1] && kids[U(next_kid[U(v)])] == heavy[U(v)]) ++next_kid[U(v)];
                if (next_kid[U(v)] < start[U(v) + 1]) c = kids[U(next_kid[U(v)]++)];
            }
            if (c == -1) {
                stack.pop_back();
                if (!stack.empty()) euler.push_back(stack.back());  // back in the parent
                continue;
            }
            head[U(c)] = c == heavy[U(v)] ? head[U(v)] : c;
            pos[U(c)] = cur++;
            first[U(c)] = static_cast<int>(euler.size());
            euler.push_back(c);
            next_kid[U(c)] = -1;
            stack.push_back(c);
        }
    }

    // u is an ancestor of v (or u == v): two comparisons on labels, no traversal.
    bool is_ancestor(int u, int v) const { return pos[U(u)] <= pos[U(v)] && pos[U(v)] < pos[U(u)] + size[U(u)]; }
};

int log_levels(int n) {
    int lg = 1;
    while ((1 << lg) < n) ++lg;
    return lg;
}

// ======================================================================= LCA 1: binary lifting, level-major
class Lifting {
public:
    explicit Lifting(const Tree& t) : up_(U(log_levels(t.n)), Vec(U(t.n))), depth_(&t.depth) {
        for (int v = 0; v < t.n; ++v) up_[0][U(v)] = t.parent[U(v)] == -1 ? v : t.parent[U(v)];
        for (std::size_t k = 1; k < up_.size(); ++k)
            for (std::size_t v = 0; v < U(t.n); ++v) up_[k][v] = up_[k - 1][U(up_[k - 1][v])];
    }
    int lca(int u, int v) const {
        const Vec& d = *depth_;
        if (d[U(u)] < d[U(v)]) std::swap(u, v);
        int diff = d[U(u)] - d[U(v)];
        for (std::size_t k = up_.size(); k-- > 0;)
            if (diff >> k & 1) u = up_[k][U(u)];
        if (u == v) return u;
        for (std::size_t k = up_.size(); k-- > 0;)
            if (up_[k][U(u)] != up_[k][U(v)]) u = up_[k][U(u)], v = up_[k][U(v)];
        return up_[0][U(u)];
    }

private:
    std::vector<Vec> up_;
    const Vec* depth_;
};

// Same algorithm, node-major layout: all of v's ancestors share one or two cache lines.
class LiftingNodeMajor {
public:
    explicit LiftingNodeMajor(const Tree& t) : log_(U(log_levels(t.n))), anc_(U(t.n) * log_), depth_(&t.depth) {
        Vec order(U(t.n));
        for (int v = 0; v < t.n; ++v) order[U(t.pos[U(v)])] = v;  // parents before children
        for (int v : order) {
            std::size_t base = U(v) * log_;
            anc_[base] = t.parent[U(v)] == -1 ? v : t.parent[U(v)];
            for (std::size_t k = 1; k < log_; ++k) anc_[base + k] = anc_[U(anc_[base + k - 1]) * log_ + k - 1];
        }
    }
    int lca(int u, int v) const {
        const Vec& d = *depth_;
        if (d[U(u)] < d[U(v)]) std::swap(u, v);
        int diff = d[U(u)] - d[U(v)];
        for (std::size_t k = log_; k-- > 0;)
            if (diff >> k & 1) u = anc_[U(u) * log_ + k];
        if (u == v) return u;
        for (std::size_t k = log_; k-- > 0;) {
            int au = anc_[U(u) * log_ + k], av = anc_[U(v) * log_ + k];
            if (au != av) u = au, v = av;
        }
        return anc_[U(u) * log_];
    }

private:
    std::size_t log_;
    Vec anc_;
    const Vec* depth_;
};

// ======================================================================= LCA 2: Euler tour + sparse table, O(1) query
class EulerRmq {
public:
    explicit EulerRmq(const Tree& t) : t_(&t) {
        std::size_t m = t.euler.size(), levels = U(std::bit_width(m));
        table_.resize(levels);
        table_[0] = t.euler;
        for (std::size_t k = 1; k < levels; ++k) {
            table_[k].resize(m - (std::size_t{1} << k) + 1);
            for (std::size_t i = 0; i < table_[k].size(); ++i)
                table_[k][i] = shallower(table_[k - 1][i], table_[k - 1][i + (std::size_t{1} << (k - 1))]);
        }
    }
    int lca(int u, int v) const {
        auto l = U(std::min(t_->first[U(u)], t_->first[U(v)])), r = U(std::max(t_->first[U(u)], t_->first[U(v)]));
        std::size_t k = U(std::bit_width(r - l + 1)) - 1;
        return shallower(table_[k][l], table_[k][r + 1 - (std::size_t{1} << k)]);
    }

private:
    int shallower(int a, int b) const { return t_->depth[U(a)] <= t_->depth[U(b)] ? a : b; }
    const Tree* t_;
    std::vector<Vec> table_;
};

// ======================================================================= values on nodes: subtree and path sums
class Fenwick {
public:
    explicit Fenwick(int n) : f_(U(n) + 1) {}
    void add(int i, std::int64_t d) {
        for (std::size_t x = U(i) + 1; x < f_.size(); x += x & (~x + 1)) f_[x] += d;
    }
    std::int64_t prefix(int i) const {  // sum of [0, i]
        std::int64_t s = 0;
        for (std::size_t x = U(i) + 1; x > 0; x -= x & (~x + 1)) s += f_[x];
        return s;
    }
    std::int64_t range(int l, int r) const { return prefix(r) - (l == 0 ? 0 : prefix(l - 1)); }

private:
    std::vector<std::int64_t> f_;
};

// Point update, subtree sum and path sum. Heavy-light: any root-to-node path crosses O(log n) light edges.
class NodeValues {
public:
    explicit NodeValues(const Tree& t) : t_(&t), fw_(t.n) {}
    void add(int v, std::int64_t d) { fw_.add(t_->pos[U(v)], d); }
    std::int64_t subtree_sum(int v) const { return fw_.range(t_->pos[U(v)], t_->pos[U(v)] + t_->size[U(v)] - 1); }
    std::int64_t path_sum(int u, int v) const {
        const Tree& t = *t_;
        std::int64_t s = 0;
        while (t.head[U(u)] != t.head[U(v)]) {
            if (t.depth[U(t.head[U(u)])] < t.depth[U(t.head[U(v)])]) std::swap(u, v);
            s += fw_.range(t.pos[U(t.head[U(u)])], t.pos[U(u)]);
            u = t.parent[U(t.head[U(u)])];
        }
        if (t.depth[U(u)] > t.depth[U(v)]) std::swap(u, v);
        return s + fw_.range(t.pos[U(u)], t.pos[U(v)]);
    }

private:
    const Tree* t_;
    Fenwick fw_;
};

// ======================================================================= oracles: walk the parent pointers
int naive_lca(const Vec& par, const Vec& depth, int u, int v) {
    while (depth[U(u)] > depth[U(v)]) u = par[U(u)];
    while (depth[U(v)] > depth[U(u)]) v = par[U(v)];
    while (u != v) u = par[U(u)], v = par[U(v)];
    return u;
}

Vec random_parents(SplitMix64& r, int n, int shape) {
    Vec par(U(n)), label(U(n));
    for (int i = 0; i < n; ++i) label[U(i)] = i;  // random relabelling: node ids carry no structure
    for (int i = n - 1; i > 0; --i) std::swap(label[U(i)], label[U(r.next_int(i + 1))]);
    par[U(label[0])] = -1;
    for (int i = 1; i < n; ++i) {
        int p = shape == 0 ? r.next_int(i) : shape == 1 ? i - 1 : 0;  // random recursive / path / star
        par[U(label[U(i)])] = label[U(p)];
    }
    return par;
}

template <class Lca>
double time_lca(const Lca& lca, const Vec& qu, const Vec& qv, std::int64_t& check) {
    auto t0 = std::chrono::steady_clock::now();
    std::int64_t s = 0;
    for (std::size_t i = 0; i < qu.size(); ++i) s += lca.lca(qu[i], qv[i]);
    check = s;
    return std::chrono::duration<double, std::nano>(std::chrono::steady_clock::now() - t0).count() / static_cast<double>(qu.size());
}

int main() {
    SplitMix64 r{51};
    int ops = 0, bad = 0;
    for (int t = 0; t < 3'000; ++t) {
        int n = 1 + r.next_int(40), shape = r.next_int(3);
        Vec par = random_parents(r, n, shape);
        Tree tree(par);
        Lifting lift(tree);
        LiftingNodeMajor lift2(tree);
        EulerRmq rmq(tree);
        NodeValues vals(tree);
        std::vector<std::int64_t> val(U(n));
        for (int q = 0; q < 30; ++q, ++ops) {
            int u = r.next_int(n), v = r.next_int(n), kind = r.next_int(5);
            if (kind == 0) {
                std::int64_t d = r.next_int(2'000'001) - 1'000'000;
                val[U(u)] += d;
                vals.add(u, d);
            } else if (kind == 1) {
                int want = naive_lca(par, tree.depth, u, v);
                bad += lift.lca(u, v) != want || lift2.lca(u, v) != want || rmq.lca(u, v) != want;
            } else if (kind == 2) {
                int w = naive_lca(par, tree.depth, u, v);
                std::int64_t want = val[U(w)];
                for (int x = u; x != w; x = par[U(x)]) want += val[U(x)];
                for (int x = v; x != w; x = par[U(x)]) want += val[U(x)];
                bad += vals.path_sum(u, v) != want;
            } else if (kind == 3) {
                std::int64_t want = 0;
                for (int x = 0; x < n; ++x)
                    if (naive_lca(par, tree.depth, u, x) == u) want += val[U(x)];
                bad += vals.subtree_sum(u) != want;
            } else {
                bad += tree.is_ancestor(u, v) != (naive_lca(par, tree.depth, u, v) == u);
            }
        }
    }
    std::println("random trees (recursive / path / star, n <= 40, relabelled): {} operations, {} mismatches vs parent-walking oracles",
                 ops, bad);
    for (const Vec& bad_par : {Vec{1, 2, 0}, Vec{-1, 2, 1}}) {
        try {
            Tree broken(bad_par);
        } catch (const std::invalid_argument& e) {
            std::println("Tree({}) -> std::invalid_argument: {}", bad_par[0] == -1 ? "root + detached 2-cycle" : "parents of a 3-cycle",
                         e.what());
        }
    }

    constexpr int n = 1 << 19, queries = 1 << 20;
    const char* shapes[] = {"random recursive tree", "path (depth n)"};
    std::println("n={} nodes, {} random LCA queries (one measured run):", n, queries);
    using clock = std::chrono::steady_clock;
    auto ms = [](clock::duration d) { return std::chrono::duration_cast<std::chrono::milliseconds>(d).count(); };
    for (int shape = 0; shape < 2; ++shape) {
        Vec par = random_parents(r, n, shape);
        auto t0 = clock::now();
        Tree tree(par);
        auto t1 = clock::now();
        Lifting lift(tree);
        auto t2 = clock::now();
        EulerRmq rmq(tree);
        auto t3 = clock::now();
        LiftingNodeMajor lift2(tree);
        Vec qu(U(queries)), qv(U(queries));
        for (std::size_t i = 0; i < U(queries); ++i) {
            qu[i] = r.next_int(n);
            qv[i] = r.next_int(n);
        }
        std::int64_t c1 = 0, c2 = 0, c3 = 0;
        double ns_lift = time_lca(lift, qu, qv, c1), ns_lift2 = time_lca(lift2, qu, qv, c3), ns_rmq = time_lca(rmq, qu, qv, c2);
        int max_depth = *std::ranges::max_element(tree.depth);
        std::println("   {:<22} depth {:7} | layout {:3} ms | lifting build {:3} ms: up[k][v] {:4.0f} ns/query, up[v][k] {:4.0f} |"
                     " Euler+sparse build {:3} ms, {:3.0f} ns/query | agree {}", shapes[shape], max_depth, ms(t1 - t0), ms(t2 - t1),
                     ns_lift, ns_lift2, ms(t3 - t2), ns_rmq, c1 == c2 && c2 == c3);
    }
}
```

**Output, GCC 16.2 (verified; timing lines are one measured run):**

```text
random trees (recursive / path / star, n <= 40, relabelled): 90000 operations, 0 mismatches vs parent-walking oracles
Tree(parents of a 3-cycle) -> std::invalid_argument: no root (a cycle)
Tree(root + detached 2-cycle) -> std::invalid_argument: not a tree: 2 nodes unreachable from the root
n=524288 nodes, 1048576 random LCA queries (one measured run):
   random recursive tree  depth      30 | layout  66 ms | lifting build  12 ms: up[k][v] 1346 ns/query, up[v][k]  394 | Euler+sparse build  26 ms,  23 ns/query | agree true
   path (depth n)         depth  524287 | layout  72 ms | lifting build  18 ms: up[k][v]  342 ns/query, up[v][k]  299 | Euler+sparse build  40 ms,  21 ns/query | agree true
```

**Output, Clang 21.1 (verified; timing lines are one measured run):**

```text
random trees (recursive / path / star, n <= 40, relabelled): 90000 operations, 0 mismatches vs parent-walking oracles
Tree(parents of a 3-cycle) -> std::invalid_argument: no root (a cycle)
Tree(root + detached 2-cycle) -> std::invalid_argument: not a tree: 2 nodes unreachable from the root
n=524288 nodes, 1048576 random LCA queries (one measured run):
   random recursive tree  depth      30 | layout  69 ms | lifting build  14 ms: up[k][v] 1026 ns/query, up[v][k]  353 | Euler+sparse build  33 ms,  21 ns/query | agree true
   path (depth n)         depth  524287 | layout  71 ms | lifting build  21 ms: up[k][v]  338 ns/query, up[v][k]  310 | Euler+sparse build  53 ms,  22 ns/query | agree true
```

---

## 3. What the results show

* **Correctness:** 90,000 random operations on random recursive trees, paths and stars, with node ids randomly relabelled so that no code can rely on "parent < child". Zero mismatches against oracles that only walk parent pointers. The ancestor test from labels agrees with LCA on every query.
* **Depth is not a problem when nothing recurses.** A 524,287-deep path builds in about 100 ms. In Folder 01 the recursive version died at about 15,000 frames.
* **The same O(log n) can cost 250 ns or 1,350 ns, and the O(1) alternative costs 20–60 ns.** Per query on 524k nodes, ranges over two runs:

| LCA method | Java (random tree / path) | C++ GCC (random / path) | C++ Clang (random / path) |
|---|---|---|---|
| Binary lifting, `up[k][v]` (level-major) | 395–422 / 627–637 ns | 1,313–1,346 / 337–342 ns | 1,026–1,043 / 326–338 ns |
| Binary lifting, `up[v][k]` (node-major) | 248–261 / 513–672 ns | 394–399 / 282–299 ns | 353–400 / 310–314 ns |
| Euler tour + sparse table | 43–51 / 57–58 ns | 23–26 / 21–23 ns | 21–26 / 20–22 ns |

On the random tree, level-major lifting touches up to 2 × 19 different 2 MiB arrays per query, one likely cache miss each. Node-major packs a node's 19 ancestors into one or two cache lines, which is worth 1.6–3.4×. On the path, one node is always the other's ancestor, so the second lifting loop exits immediately and the layout barely matters (in one Java run node-major was even slower). The Euler/sparse-table query does two table reads and no loop, so it is **5–50× faster** than either lifting layout. The trade-off is memory: about 2n × log(2n) ints, roughly 80 MB at 524k nodes, against n × log n for lifting. This is Folder 01 File 2's lesson applied to trees: *same algorithm, the layout decides the constant; different algorithm, the loop disappears.*

* **Build costs** are all tens of milliseconds at this size. Preprocessing is never the bottleneck for a static tree; query volume is.

---

## 4. The last 10 minutes: Extensions A, B and C

### 4.1 Extension A — "64 threads query and update the tree"

* **Structure queries (LCA, ancestor tests, k-th ancestor)** read only immutable arrays built in the constructor. Publish the `Tree` once (final fields, `const` in C++) and every thread can query without locks. This is the strongest argument for doing all the work up front.
* **Node values with point updates** (subtree sums, path sums) need a shared Fenwick. The updates are commutative additions, so the options are those File 2 measures: per-cell atomic adds (exact final state in any interleaving, though a concurrent reader may see a partially applied update), per-thread Fenwicks summed at query time (fastest writes, slower reads), or a single-writer partition with readers on a snapshot.
* **Structural changes** (re-parenting a subtree) invalidate pos, Euler and lifting tables. Use **copy-on-write**: rebuild off to the side and publish the new immutable `Tree` with one atomic reference swap. Reads never block. For high-churn trees, link-cut trees or Euler-tour trees support dynamic updates in O(log n), at a large constant and a lot of code. Name them; don't write them in a round.

### 4.2 Extension B — "the tree has 10 billion nodes, or the queries stream in"

* **Offline LCA (Tarjan's algorithm):** one DFS plus a DSU answers a whole batch of LCA queries in nearly linear time with O(n) memory, and it can process queries grouped by node. For a tree on disk, an **external** DFS order (Folder 07's external sort) builds pos and Euler arrays as sequential files.
* **Labels compress the tree into two integers per node.** Ancestor tests then need no tree at all, just `(pos, size)`. That's 16 bytes per node for 10⁹ nodes: 16 GB, stored on SSD and memory-mapped, answered with a single random read per node.
* **A streaming ancestry check** over events that carry `(pos, size)` labels is O(1) state.

### 4.3 Extension C — "the hierarchy is sharded over 100 machines" (file systems, org charts, category trees)

* **Nested-sets labels make most queries shard-local.** "Is document D under folder F?" compares labels carried with the request. No cross-shard traversal.
* **Partition by subtree.** Assign contiguous `pos` ranges to shards; a subtree is then one contiguous range on one shard, or a few adjacent shards. Subtree aggregates become range queries routed like any range-partitioned key space.
* **Dynamic hierarchies break dense labels:** inserting a node renumbers everything after it. Production systems use **gap labelling** (leave holes and relabel rarely), **path enumeration** (a materialized path string like `/1/7/42/`; ancestor = prefix test; this is how many file-system and comment-tree schemas work), or **ORDPATH**-style hierarchical labels that never need relabelling. Path enumeration also makes LCA the **longest common prefix** of two paths, which needs no global state at all.
* **Cross-shard LCA** with materialized paths is a string LCP. With lifting tables it would need one remote hop per level, which is why distributed systems prefer labels to pointers.

---

## 5. Failure modes

| # | Failure | Symptom | Prevention |
|---|---|---|---|
| F1 | Recursive DFS | Stack overflow on deep inputs (chains, degenerate BSTs) | Explicit stack; one traversal |
| F2 | Unvalidated parent array | Infinite loop, or nodes silently missing | Count reached nodes; reject cycles and forests with a message |
| F3 | Fixed `LOG` / `MAXN` | Wrong answers beyond the constant | Size from `n` at construction |
| F4 | Level-major lifting on a hot path | 2.5–3× slower than node-major in C++ | Node-major layout, or Euler + sparse table for O(1) |
| F5 | Separate traversals for HLD and Euler | Orders disagree after a refactor | One heavy-first preorder computes all labels |
| F6 | Path query without heavy-first order | Heavy paths not contiguous; wrong ranges | Visit the heavy child first; assert `pos[heavy[v]] == pos[v] + 1` |
| F7 | `int` sums of node values | Overflow on long paths | `long` sums |
| F8 | Mutating a shared tree in place | Torn reads of pos and parent arrays | Copy-on-write rebuild + atomic publish |
| F9 | Dense labels on a dynamic tree | Relabel storms on insert | Gap labels, path enumeration, ORDPATH |

---

## 6. Bar-raiser chains

<details><summary><b>Q1 · "Find the lowest common ancestor of two nodes."</b></summary>

**Initial Prompt.** A binary tree given as node objects; one query.

**L5 Answer.** The recursive "return the node if found in both subtrees" solution.

**Why L5 Stalls.** Fine for one query on a small tree. The follow-up is "a million queries on a million-node tree": O(n) per query, recursion depth O(n).

**L7 Answer.** "For one query, the recursive search is O(n), but I'd write it iteratively because depth is input-controlled. For many queries I'd preprocess. Binary lifting gives O(log n) per query and also k-th ancestors. An Euler tour plus a sparse table gives O(1) per query at about twice the memory. I measured 260–1,300 ns for lifting against 20–60 ns for the sparse table at half a million nodes, so for a query-heavy service the Euler version wins."
</details>

<details><summary><b>Q2 · "Your DFS is recursive. Any problem?"</b></summary>

**Initial Prompt.** The tree can be a chain of 10⁶ nodes.

**L5 Answer.** "Recursion is cleaner; I'd increase the stack size."

**Why L5 Stalls.** Stack size is a deployment knob that differs between JVM, thread and toolchain (1, 2 or 16 MiB here), and a C++ stack overflow is a crash with no diagnostic.

**L7 Answer.** "Depth is controlled by the input, so I won't recurse on it. One explicit-stack DFS computes depth, size, the heavy child, preorder positions and the Euler tour. The listing builds a 524,287-deep chain in about 100 ms that way. Recursion is fine where depth is provably O(log n), like inside a segment tree."
</details>

<details><summary><b>Q3 · "Sum of values in the subtree of v, with point updates."</b></summary>

**Initial Prompt.** An org chart where each employee's cost changes; managers query their org's total.

**L5 Answer.** "DFS from v each time and add the values."

**Why L5 Stalls.** O(subtree) per query, O(n) for the CEO.

**L7 Answer.** "Flatten the tree with a preorder: v's subtree is the contiguous range [pos[v], pos[v] + size[v]). Store values in a Fenwick tree in that order. An update is O(log n), a subtree query is one range sum, O(log n). The same labels answer 'is A in B's org' with two integer comparisons. That's the nested-sets model databases use for hierarchies."
</details>

<details><summary><b>Q4 · "Now sum the values on the path between two employees."</b></summary>

**Initial Prompt.** Path queries with point updates.

**L5 Answer.** "Walk up from both to the LCA, summing."

**Why L5 Stalls.** O(depth) per query; O(n) on a chain.

**L7 Answer.** "Heavy-light decomposition. Make each node's largest child its heavy child and visit it first, so heavy paths are contiguous in the same preorder I use for subtrees. Any root-to-node path crosses O(log n) light edges, because each light edge at least halves the subtree size. A path query becomes O(log n) contiguous ranges, each a Fenwick range sum: O(log² n). The same array serves subtree queries too."
</details>

<details><summary><b>Q5 · "Why might your O(log n) LCA be slower than you expect?"</b></summary>

**Initial Prompt.** Performance probe.

**L5 Answer.** "Log n is about 20 steps, so it should be fast."

**Why L5 Stalls.** It counts steps, not cache misses.

**L7 Answer.** "Each step reads `up[k][u]` for a different k, and with a level-major table each level is a separate array, so every step can be a cache miss on a large tree. I measured about 1.0–1.3 µs per query in C++ that way. Storing each node's ancestors contiguously cut it to about 400 ns. An Euler tour with a sparse table needs only two reads, at 20–30 ns. I'd pick the layout from the query-to-update ratio and the memory budget."
</details>

<details><summary><b>Q6 · "Many threads query; occasionally the hierarchy changes."</b></summary>

**Initial Prompt.** Extension A for a permissions hierarchy.

**L5 Answer.** "Put a read-write lock around the tree."

**Why L5 Stalls.** Every query pays for the lock, and a rebuild holds the write lock for the whole rebuild.

**L7 Answer.** "Queries only read arrays built at construction, so I'd make the tree immutable. A change builds a new tree off to the side, O(n) for a rare event, and publishes it with one atomic reference swap. Readers never block; each query sees either the old or the new hierarchy, never a mix. If changes were frequent, I'd look at link-cut trees or switch to materialized-path labels that update locally."
</details>

<details><summary><b>Q7 · "The hierarchy is a file system with billions of entries across 100 servers."</b></summary>

**Initial Prompt.** Extension C: is file F inside directory D?

**L5 Answer.** "Walk up F's parents until reaching D or the root."

**Why L5 Stalls.** Each step may be a cross-server hop; depth-many RPCs per check.

**L7 Answer.** "Carry a label with each entry so the check is local. With interval labels it's two integer comparisons, but those labels need renumbering on insert. For a mutable file system I'd use materialized paths: ancestor means prefix, and LCA is the longest common prefix, with no tree walk. To keep subtree operations local, I'd partition by path prefix, so a directory's contents live together and only very large directories split across servers."
</details>

<details><summary><b>Q8 · "The input is a parent array. What can go wrong?"</b></summary>

**Initial Prompt.** The candidate starts building adjacency lists immediately.

**L5 Answer.** "Nothing; it's guaranteed to be a tree."

**Why L5 Stalls.** In production, "guaranteed" is a contract someone else can break. A cycle can hang a DFS that doesn't track visited nodes, or silently leave nodes out.

**L7 Answer.** "Exactly one root, every parent in range, and every node reachable from the root; otherwise it's a forest or contains a cycle. I validate in the constructor by counting nodes reached from the root and throw with a specific message. Downstream code can then trust the invariants without re-checking. The listing rejects a 3-cycle with 'no root' and a detached 2-cycle with 'not a tree: 2 nodes unreachable'."
</details>

---

## 7. Checklist

* [ ] Validate the tree at construction: one root, all nodes reachable.
* [ ] One iterative, heavy-first DFS computes depth, size, heavy, head, pos and the Euler tour.
* [ ] Subtree = `[pos, pos + size)`; ancestor test = two comparisons.
* [ ] LCA: lifting (O(log n), k-th ancestor) vs Euler + sparse table (O(1), more memory). Choose by query volume.
* [ ] Lifting layout node-major on hot paths.
* [ ] Path queries: HLD → O(log n) ranges → Fenwick/segment tree.
* [ ] Recursion only where depth is provably logarithmic.
* [ ] Extension A: immutable tree, copy-on-write rebuilds, commutative value updates.
* [ ] Extension B: offline Tarjan LCA; labels as compact per-node data; external DFS order.
* [ ] Extension C: labels make checks local; subtree partitioning; materialized paths for dynamic hierarchies.

---

## 8. References

* M. A. Bender, M. Farach-Colton, *The LCA Problem Revisited*, LATIN 2000 — DOI 10.1007/10719839_9
* D. D. Sleator, R. E. Tarjan, *A Data Structure for Dynamic Trees*, JCSS 26(3), 1983 — DOI 10.1016/0022-0000(83)90006-5 (the source of heavy-light-style decomposition and link-cut trees)
* R. E. Tarjan, *Applications of Path Compression on Balanced Trees*, JACM 26(4), 1979 — DOI 10.1145/322154.322161 (offline LCA)
* P. O'Neil, E. O'Neil, S. Pal, I. Cseri, G. Schaller, N. Westbury, *ORDPATHs: Insert-Friendly XML Node Labels*, SIGMOD 2004 — DOI 10.1145/1007568.1007686
* J. Celko, *Trees and Hierarchies in SQL for Smarties*, 2nd ed. (2012): nested sets and path enumeration.
* cp-algorithms: [LCA with binary lifting](https://cp-algorithms.com/graph/lca_binary_lifting.html), [LCA via RMQ](https://cp-algorithms.com/graph/lca.html), [Heavy-light decomposition](https://cp-algorithms.com/graph/hld.html)
* LeetCode anchors: [236 Lowest Common Ancestor of a Binary Tree](https://leetcode.com/problems/lowest-common-ancestor-of-a-binary-tree/), [1483 Kth Ancestor of a Tree Node](https://leetcode.com/problems/kth-ancestor-of-a-tree-node/)

*Folder 03:* [02 — Fenwick, lazy and sparse segment trees](02-fenwick-bit-and-lazy-segment-trees-with-sparse-dynamic-nodes.md) · [03 — radix tries, Aho–Corasick, XOR tries](03-compressed-radix-tries-aho-corasick-automata-and-bitwise-xor-tries.md)
