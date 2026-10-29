# Disjoint-Set Union with Rollback, Bipartite Matching and Min-Cut

> **Folder 04 · File 3 of 3** — union-find in four production variants (compressed, undoable, parity-tracking, lock-free), and max-flow as the umbrella for matching and min-cut, every claim checked against an independent oracle.
> **Languages:** Java 21 (`--release 21 -Xlint:all -Werror`, JDK 25.0.4.1) and C++23 (GCC 16.2 and Clang 21.1, `-O2`, warnings as errors).

| Listing | File | What it proves |
|---|---|---|
| 4.5 | `DsuFlow.java` | Rollback DSU equals a rebuild after every step; parity DSU finds the first odd-cycle edge exactly; Dinic (iterative blocking flow) max flow = residual min cut = brute force over all s–t cuts; matching as unit-capacity Dinic equals a bitmask DP; a lock-free CAS union-find with 8 threads |
| 4.6 | `dsu_flow.cpp` | The same; identical correctness counts; the lock-free version beats sequential |

**Verification.** Both listings were extracted from this file, compiled and run. Everything is **Output (verified)** except the concurrency line (**one measured run**).

---

## 0. Orientation

| Contest habit | What breaks | L7 replacement |
|---|---|---|
| Recursive `find` with path compression | Stack overflow on a long chain before the first compression | Iterative path halving |
| Path compression + "undo" | Compression rewrites many pointers; rollback becomes impossible | Union by size **without** compression: O(log n) depth, one write pair per union |
| BFS 2-colouring after every edge | O(E) per edge to answer "still bipartite?" | Parity DSU: O(α(n)) per edge, online |
| Hand-written Hopcroft–Karp, recursive | Long, recursion depth up to V | Matching as max flow: Dinic on a unit network has Hopcroft–Karp's O(E√V) bound |
| "Max flow" answer only | The business question is usually the **cut**: which edges to fix or remove | Residual reachability after max flow gives the min cut's source side |
| One lock around a shared DSU | Writers serialize (329–511 ms here) | CAS on parent pointers: lock-free union-find |

---

## 1. First principles

### 1.1 Union-find invariants

Each set is a tree whose root is its representative. `find` walks to the root; `union` links one root under the other. Two independent optimizations:

* **Union by size (or rank):** link the smaller tree under the larger. Depth stays O(log n), because a node's depth grows only when its tree at least doubles.
* **Path compression / halving:** while walking up, point nodes at their grandparents. Combined with union by size, the amortized cost is O(α(n)): effectively constant.

**Path halving** (`parent[x] = parent[parent[x]]; x = parent[x]`) is a one-pass, iterative form of compression. No recursion, and the depth argument still holds.

### 1.2 Rollback

Offline problems ("process edge insertions and deletions over time", "answer connectivity queries in divide-and-conquer over time") need to **undo** unions in LIFO order. Path compression rewrites pointers all over the tree, so it's incompatible with cheap undo. Without it, union by size keeps depth O(log n), so `find` is O(log n), and each union changes exactly one parent pointer and one size: a two-word history entry. Rollback pops entries. The listing also records no-op unions, so that "roll back to checkpoint k" means the same thing regardless of how many unions merged nothing.

### 1.3 Parity DSU

Store, for each node, the parity of its colour relative to its parent. The colour of x relative to its root is the XOR along the path. An edge (u, v) demands different colours. If u and v are already in the same set with equal parity, the edge closes an **odd cycle** and the graph stops being bipartite. Otherwise, link the roots with the parity that makes the colours differ. This answers "after which edge does the graph stop being bipartite?" online in O(log n) per edge. The same structure solves "these two people are enemies; is the assignment consistent?" and weighted variants (relative offsets instead of parity).

### 1.4 Max flow, min cut, matching

**Max-flow min-cut theorem:** the maximum s–t flow equals the minimum total capacity of edges whose removal separates s from t. After a max flow, the vertices reachable from s in the **residual** graph form the source side of a minimum cut. The cut edges are the saturated edges leaving that set. That's often what the business wants: *which pipes are the bottleneck*, *which links to upgrade*, *which minimal set of accounts separates fraud ring A from B*.

**Dinic:** BFS builds a level graph (distance from s in the residual graph), then a **blocking flow** pushes flow along level-increasing paths until none remain. Each phase strictly increases the s–t distance, so there are at most V phases: O(V² E) in general and **O(E√V) on unit-capacity bipartite networks**. That's the Hopcroft–Karp bound, so maximum bipartite matching is "add a source to the left side and a sink to the right side with capacity 1, run Dinic". The listing's blocking flow is iterative, with an explicit path stack and a retreat that prunes dead-end vertices from the level graph.

### 1.5 Lock-free union-find

Two observations make a CAS-based DSU correct:

1. **Linking:** `CAS(parent[b], b, a)` succeeds only if b is still a root at that instant. If another thread linked b first, the CAS fails and we retry from fresh roots. Always linking the **larger index under the smaller** imposes a global order on links, so no cycle can ever form.
2. **Halving:** `CAS(parent[x], p, gp)` is an optimization. If it fails because someone else changed `parent[x]`, the structure is still valid, and the walk just continues.

The result is a linearizable union and a `find` that returns some root that was valid during the call (Anderson and Woll give the full wait-free treatment with ranks). It loses union-by-size's depth guarantee, which randomized ids recover in expectation.

---

## 2. The listings

### 2.1 Listing 4.5 — Java

```java
// DsuFlow.java - union-find (compressed, rollback, parity, lock-free), Dinic max flow, min cut, and matching as flow.
import java.util.ArrayDeque;
import java.util.Arrays;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicIntegerArray;

public final class DsuFlow {

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

    // ===================================================================== 1. DSU: path halving + union by size
    static final class Dsu {
        private final int[] parent, size;
        private int sets;
        Dsu(int n) { parent = new int[n]; size = new int[n]; sets = n; for (int i = 0; i < n; i++) { parent[i] = i; size[i] = 1; } }
        int find(int x) { while (parent[x] != x) { parent[x] = parent[parent[x]]; x = parent[x]; } return x; }  // iterative
        boolean union(int a, int b) {
            a = find(a); b = find(b);
            if (a == b) return false;
            if (size[a] < size[b]) { int t = a; a = b; b = t; }
            parent[b] = a; size[a] += size[b]; sets--;
            return true;
        }
        int sets() { return sets; }
    }

    // ===================================================================== 2. DSU with rollback (no path compression)
    /** Union by size keeps depth O(log n) without compression, so every union is ONE undoable write pair. */
    static final class RollbackDsu {
        private final int[] parent, size;
        private int[] historyB = new int[16];  // one entry per union call: grows with operations, not with n
        private int top;
        RollbackDsu(int n) { parent = new int[n]; size = new int[n]; for (int i = 0; i < n; i++) { parent[i] = i; size[i] = 1; } }
        int find(int x) { while (parent[x] != x) x = parent[x]; return x; }
        void union(int a, int b) {
            if (top == historyB.length) historyB = Arrays.copyOf(historyB, 2 * top);
            a = find(a); b = find(b);
            if (a == b) { historyB[top++] = -1; return; }   // record a no-op so rollback stays in step
            if (size[a] < size[b]) { int t = a; a = b; b = t; }
            parent[b] = a; size[a] += size[b]; historyB[top++] = b;
        }
        int checkpoint() { return top; }
        void rollback(int to) {
            while (top > to) {
                int b = historyB[--top];
                if (b == -1) continue;
                int a = parent[b];
                size[a] -= size[b]; parent[b] = b;
            }
        }
    }

    // ===================================================================== 3. parity DSU: online bipartiteness
    /** parity[x] = color(x) XOR color(parent(x)). An edge (u, v) demands different colors. O(alpha) per edge. */
    static final class ParityDsu {
        private final int[] parent, size, parity;
        ParityDsu(int n) { parent = new int[n]; size = new int[n]; parity = new int[n]; for (int i = 0; i < n; i++) { parent[i] = i; size[i] = 1; } }
        private int root(int x) { while (parent[x] != x) x = parent[x]; return x; }
        private int colorToRoot(int x) { int c = 0; while (parent[x] != x) { c ^= parity[x]; x = parent[x]; } return c; }
        /** false when this edge closes an odd cycle (the graph stops being bipartite). */
        boolean addEdge(int u, int v) {
            int ru = root(u), rv = root(v), cu = colorToRoot(u), cv = colorToRoot(v);
            if (ru == rv) return cu != cv;
            if (size[ru] < size[rv]) { int t = ru; ru = rv; rv = t; }
            parent[rv] = ru; size[ru] += size[rv]; parity[rv] = cu ^ cv ^ 1;
            return true;
        }
    }

    static boolean bipartiteBfs(int n, int[] f, int[] t, int edges) {
        int[] color = new int[n];
        Arrays.fill(color, -1);
        for (int s = 0; s < n; s++) {
            if (color[s] != -1) continue;
            color[s] = 0;
            ArrayDeque<Integer> q = new ArrayDeque<>();
            q.add(s);
            while (!q.isEmpty()) {
                int u = q.poll();
                for (int e = 0; e < edges; e++) {
                    int v = f[e] == u ? t[e] : t[e] == u ? f[e] : -1;
                    if (v == -1) continue;
                    if (color[v] == -1) { color[v] = color[u] ^ 1; q.add(v); }
                    else if (color[v] == color[u]) return false;
                }
            }
        }
        return true;
    }

    // ===================================================================== 4. Dinic max flow + min cut
    static final class Dinic {
        final int n;
        private int[] head, next, to;
        private long[] cap;
        private int m;
        private int[] level, it;

        Dinic(int n) { this.n = n; head = new int[n]; Arrays.fill(head, -1); next = new int[16]; to = new int[16]; cap = new long[16]; }

        int addEdge(int u, int v, long c) {
            if (c < 0) throw new IllegalArgumentException("negative capacity");
            if (m + 2 > to.length) { next = Arrays.copyOf(next, 2 * to.length); cap = Arrays.copyOf(cap, 2 * to.length); to = Arrays.copyOf(to, 2 * to.length); }
            to[m] = v; cap[m] = c; next[m] = head[u]; head[u] = m++;
            to[m] = u; cap[m] = 0; next[m] = head[v]; head[v] = m++;   // residual twin is e ^ 1
            return m - 2;
        }

        private boolean bfs(int s, int t) {
            level = new int[n];
            Arrays.fill(level, -1);
            int[] q = new int[n];
            int h = 0, tl = 0;
            level[s] = 0;
            q[tl++] = s;
            while (h < tl) { int u = q[h++]; for (int e = head[u]; e != -1; e = next[e]) if (cap[e] > 0 && level[to[e]] == -1) { level[to[e]] = level[u] + 1; q[tl++] = to[e]; } }
            return level[t] != -1;
        }

        /** Blocking flow on the level graph, iteratively: no recursion, depth = path length. */
        private long blockingFlow(int s, int t) {
            long total = 0;
            int[] path = new int[n];
            int depth = 0, u = s;
            while (true) {
                if (u == t) {
                    long f = Long.MAX_VALUE;
                    for (int i = 0; i < depth; i++) f = Math.min(f, cap[path[i]]);
                    for (int i = 0; i < depth; i++) { cap[path[i]] -= f; cap[path[i] ^ 1] += f; }
                    total += f;
                    depth = 0;
                    u = s;
                    continue;
                }
                int e = it[u];
                while (e != -1 && !(cap[e] > 0 && level[to[e]] == level[u] + 1)) e = next[e];
                it[u] = e;
                if (e == -1) {                                // dead end: prune u from the level graph, retreat
                    if (u == s) return total;
                    level[u] = -1;
                    u = to[path[--depth] ^ 1];
                    continue;
                }
                path[depth++] = e;
                u = to[e];
            }
        }

        long maxFlow(int s, int t) {
            long flow = 0;
            while (bfs(s, t)) {
                it = Arrays.copyOf(head, n);
                flow += blockingFlow(s, t);
            }
            return flow;
        }

        /** After maxFlow: vertices reachable from s in the residual graph form the source side of a minimum cut. */
        boolean[] sourceSide(int s) {
            boolean[] seen = new boolean[n];
            ArrayDeque<Integer> q = new ArrayDeque<>();
            seen[s] = true;
            q.add(s);
            while (!q.isEmpty()) { int u = q.poll(); for (int e = head[u]; e != -1; e = next[e]) if (cap[e] > 0 && !seen[to[e]]) { seen[to[e]] = true; q.add(to[e]); } }
            return seen;
        }
    }

    // ===================================================================== Extension A: lock-free union-find
    /** Path halving and linking by CAS. Linking a root only to a SMALLER index makes cycles impossible. */
    static final class ConcurrentDsu {
        private final AtomicIntegerArray parent;
        ConcurrentDsu(int n) { parent = new AtomicIntegerArray(n); for (int i = 0; i < n; i++) parent.set(i, i); }
        int find(int x) {
            while (true) {
                int p = parent.get(x);
                if (p == x) return x;
                int gp = parent.get(p);
                if (p != gp) parent.compareAndSet(x, p, gp);   // best-effort halving; losing the race is harmless
                x = gp;
            }
        }
        void union(int a, int b) {
            while (true) {
                a = find(a); b = find(b);
                if (a == b) return;
                if (a > b) { int t = a; a = b; b = t; }
                if (parent.compareAndSet(b, b, a)) return;   // b must still be a root; otherwise retry
            }
        }
    }

    interface Body { void run(int t); }

    static double parallel(int threads, Body body) throws InterruptedException {
        CountDownLatch gate = new CountDownLatch(1), done = new CountDownLatch(threads);
        for (int t = 0; t < threads; t++) {
            int id = t;
            Thread.ofPlatform().start(() -> {
                try { gate.await(); body.run(id); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
                finally { done.countDown(); }
            });
        }
        long t0 = System.nanoTime();
        gate.countDown();
        done.await();
        return (System.nanoTime() - t0) / 1e6;
    }

    public static void main(String[] args) throws InterruptedException {
        SplitMix64 r = new SplitMix64(101);
        int trials = 2_000, okRollback = 0, okParity = 0, okCut = 0, okMatch = 0;
        for (int t = 0; t < trials; t++) {
            int n = 2 + r.nextInt(9);
            // rollback DSU vs replaying the surviving unions from scratch
            RollbackDsu rb = new RollbackDsu(n);
            int[][] log = new int[40][];
            int len = 0;
            boolean ok = true;
            for (int step = 0; step < 40; step++) {
                if (r.nextInt(4) == 0 && len > 0) {
                    int keep = r.nextInt(len + 1);
                    rb.rollback(keep);
                    len = keep;
                } else {
                    int a = r.nextInt(n), b = r.nextInt(n);
                    rb.union(a, b);
                    log[len++] = new int[] {a, b};
                }
                Dsu fresh = new Dsu(n);
                for (int i = 0; i < len; i++) fresh.union(log[i][0], log[i][1]);
                for (int a = 0; a < n; a++) for (int b = 0; b < n; b++) ok &= (rb.find(a) == rb.find(b)) == (fresh.find(a) == fresh.find(b));
            }
            okRollback += ok ? 1 : 0;
            // parity DSU: first edge that breaks bipartiteness vs BFS on every prefix
            int m = 1 + r.nextInt(2 * n);
            int[] f = new int[m], to = new int[m];
            for (int e = 0; e < m; e++) { f[e] = r.nextInt(n); to[e] = r.nextInt(n); }
            ParityDsu pd = new ParityDsu(n);
            int firstBad = -1, oracleBad = -1;
            for (int e = 0; e < m; e++) if (!pd.addEdge(f[e], to[e]) && firstBad == -1) firstBad = e;
            for (int e = 0; e < m && oracleBad == -1; e++) if (!bipartiteBfs(n, f, to, e + 1)) oracleBad = e;
            okParity += firstBad == oracleBad ? 1 : 0;
            // max flow == min cut == brute-force min over all s-t cuts
            int fm = r.nextInt(3 * n);
            int[] cf = new int[fm], ct = new int[fm], cc = new int[fm];
            Dinic d = new Dinic(n);
            for (int e = 0; e < fm; e++) { cf[e] = r.nextInt(n); ct[e] = r.nextInt(n); cc[e] = r.nextInt(10); d.addEdge(cf[e], ct[e], cc[e]); }
            long flow = d.maxFlow(0, n - 1);
            boolean[] side = d.sourceSide(0);
            long cutCap = 0;
            for (int e = 0; e < fm; e++) if (side[cf[e]] && !side[ct[e]]) cutCap += cc[e];
            long brute = Long.MAX_VALUE;
            for (int mask = 0; mask < 1 << n; mask++) {
                if ((mask & 1) == 0 || (mask >> (n - 1) & 1) == 1) continue;   // s inside, t outside
                long c = 0;
                for (int e = 0; e < fm; e++) if ((mask >> cf[e] & 1) == 1 && (mask >> ct[e] & 1) == 0) c += cc[e];
                brute = Math.min(brute, c);
            }
            okCut += flow == brute && cutCap == flow && !side[n - 1] ? 1 : 0;
            // bipartite matching as unit-capacity Dinic (Hopcroft-Karp's O(E sqrt V)) vs bitmask DP
            int left = 1 + r.nextInt(7), right = 1 + r.nextInt(7);
            boolean[][] adj = new boolean[left][right];
            Dinic mf = new Dinic(left + right + 2);
            int src = left + right, sink = src + 1;
            for (int i = 0; i < left; i++) mf.addEdge(src, i, 1);
            for (int j = 0; j < right; j++) mf.addEdge(left + j, sink, 1);
            for (int i = 0; i < left; i++) for (int j = 0; j < right; j++) if (r.nextInt(3) == 0) { adj[i][j] = true; mf.addEdge(i, left + j, 1); }
            int[] best = new int[1 << right];
            for (int i = 0; i < left; i++) {
                int[] nb = best.clone();
                for (int mask = 0; mask < 1 << right; mask++)
                    for (int j = 0; j < right; j++)
                        if (adj[i][j] && (mask >> j & 1) == 0) nb[mask | 1 << j] = Math.max(nb[mask | 1 << j], best[mask] + 1);
                best = nb;
            }
            okMatch += mf.maxFlow(src, sink) == Arrays.stream(best).max().orElse(0) ? 1 : 0;
        }
        System.out.printf("random small instances (%,d each) vs independent oracles:%n", trials);
        System.out.printf("   rollback DSU == rebuild-from-surviving-unions after every step  %d/%d%n", okRollback, trials);
        System.out.printf("   parity DSU: first odd-cycle edge == BFS 2-colouring of every prefix %d/%d%n", okParity, trials);
        System.out.printf("   Dinic max flow == residual min cut == brute force over all s-t cuts %d/%d%n", okCut, trials);
        System.out.printf("   matching as unit-capacity Dinic == bitmask DP                     %d/%d%n", okMatch, trials);

        int n = 1 << 20, threads = 8, perThread = 1 << 19;
        int[][] ea = new int[threads][perThread], eb = new int[threads][perThread];
        for (int t = 0; t < threads; t++) for (int i = 0; i < perThread; i++) { ea[t][i] = r.nextInt(n); eb[t][i] = r.nextInt(n); }
        Dsu seq = new Dsu(n);
        long s0 = System.nanoTime();
        for (int t = 0; t < threads; t++) for (int i = 0; i < perThread; i++) seq.union(ea[t][i], eb[t][i]);
        double msSeq = (System.nanoTime() - s0) / 1e6;
        Dsu locked = new Dsu(n);
        double msLocked = parallel(threads, t -> { for (int i = 0; i < perThread; i++) synchronized (locked) { locked.union(ea[t][i], eb[t][i]); } });
        ConcurrentDsu cas = new ConcurrentDsu(n);
        double msCas = parallel(threads, t -> { for (int i = 0; i < perThread; i++) cas.union(ea[t][i], eb[t][i]); });
        boolean same = true;
        for (int i = 0; i < n; i++) same &= (seq.find(i) == seq.find(0)) == (cas.find(i) == cas.find(0));
        int casSets = 0;
        for (int i = 0; i < n; i++) if (cas.find(i) == i) casSets++;
        System.out.printf("A. %,d unions over %,d elements (one measured run): sequential %.0f ms | %d threads + one lock %.0f ms |"
                + " %d threads lock-free CAS %.0f ms | sets %,d / %,d / %,d, same partition %b%n", threads * perThread, n, msSeq,
                threads, msLocked, threads, msCas, seq.sets(), locked.sets(), casSets, same);
    }
}
```

**Output (verified; the last line is one measured run):**

```text
random small instances (2,000 each) vs independent oracles:
   rollback DSU == rebuild-from-surviving-unions after every step  2000/2000
   parity DSU: first odd-cycle edge == BFS 2-colouring of every prefix 2000/2000
   Dinic max flow == residual min cut == brute force over all s-t cuts 2000/2000
   matching as unit-capacity Dinic == bitmask DP                     2000/2000
A. 4,194,304 unions over 1,048,576 elements (one measured run): sequential 104 ms | 8 threads + one lock 404 ms | 8 threads lock-free CAS 72 ms | sets 338 / 338 / 338, same partition true
```

### 2.2 Listing 4.6 — C++23

```cpp
// dsu_flow.cpp - union-find (compressed, rollback, parity, lock-free), Dinic max flow, min cut, and matching as flow.
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <deque>
#include <limits>
#include <mutex>
#include <print>
#include <stdexcept>
#include <thread>
#include <vector>

using i64 = std::int64_t;
using Vec = std::vector<int>;
inline std::size_t U(int x) { return static_cast<std::size_t>(x); }

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

// ======================================================================= 1. DSU: path halving + union by size
class Dsu {
public:
    explicit Dsu(int n) : parent_(U(n)), size_(U(n), 1), sets_(n) {
        for (int i = 0; i < n; ++i) parent_[U(i)] = i;
    }
    int find(int x) {  // iterative path halving
        while (parent_[U(x)] != x) x = parent_[U(x)] = parent_[U(parent_[U(x)])];
        return x;
    }
    bool unite(int a, int b) {
        a = find(a), b = find(b);
        if (a == b) return false;
        if (size_[U(a)] < size_[U(b)]) std::swap(a, b);
        parent_[U(b)] = a, size_[U(a)] += size_[U(b)], --sets_;
        return true;
    }
    int sets() const { return sets_; }

private:
    Vec parent_, size_;
    int sets_;
};

// ======================================================================= 2. DSU with rollback (no path compression)
// Union by size keeps depth O(log n) without compression, so every union is ONE undoable write pair.
class RollbackDsu {
public:
    explicit RollbackDsu(int n) : parent_(U(n)), size_(U(n), 1) {
        for (int i = 0; i < n; ++i) parent_[U(i)] = i;
    }
    int find(int x) const {
        while (parent_[U(x)] != x) x = parent_[U(x)];
        return x;
    }
    void unite(int a, int b) {
        a = find(a), b = find(b);
        if (a == b) return history_.push_back(-1);  // record a no-op so rollback stays in step
        if (size_[U(a)] < size_[U(b)]) std::swap(a, b);
        parent_[U(b)] = a, size_[U(a)] += size_[U(b)];
        history_.push_back(b);
    }
    std::size_t checkpoint() const { return history_.size(); }
    void rollback(std::size_t to) {
        while (history_.size() > to) {
            int b = history_.back();
            history_.pop_back();
            if (b == -1) continue;
            int a = parent_[U(b)];
            size_[U(a)] -= size_[U(b)], parent_[U(b)] = b;
        }
    }

private:
    Vec parent_, size_, history_;
};

// ======================================================================= 3. parity DSU: online bipartiteness
class ParityDsu {
public:
    explicit ParityDsu(int n) : parent_(U(n)), size_(U(n), 1), parity_(U(n)) {
        for (int i = 0; i < n; ++i) parent_[U(i)] = i;
    }
    bool add_edge(int u, int v) {  // false when this edge closes an odd cycle
        auto [ru, cu] = root(u);
        auto [rv, cv] = root(v);
        if (ru == rv) return cu != cv;
        if (size_[U(ru)] < size_[U(rv)]) std::swap(ru, rv);
        parent_[U(rv)] = ru, size_[U(ru)] += size_[U(rv)], parity_[U(rv)] = cu ^ cv ^ 1;
        return true;
    }

private:
    std::pair<int, int> root(int x) const {
        int c = 0;
        while (parent_[U(x)] != x) c ^= parity_[U(x)], x = parent_[U(x)];
        return {x, c};
    }
    Vec parent_, size_, parity_;
};

bool bipartite_bfs(int n, const Vec& f, const Vec& t, std::size_t edges) {
    Vec color(U(n), -1);
    for (int s = 0; s < n; ++s) {
        if (color[U(s)] != -1) continue;
        color[U(s)] = 0;
        std::deque<int> q{s};
        while (!q.empty()) {
            int u = q.front();
            q.pop_front();
            for (std::size_t e = 0; e < edges; ++e) {
                int v = f[e] == u ? t[e] : t[e] == u ? f[e] : -1;
                if (v == -1) continue;
                if (color[U(v)] == -1) color[U(v)] = color[U(u)] ^ 1, q.push_back(v);
                else if (color[U(v)] == color[U(u)]) return false;
            }
        }
    }
    return true;
}

// ======================================================================= 4. Dinic max flow + min cut
class Dinic {
public:
    explicit Dinic(int n) : n_(n), head_(U(n), -1) {}
    void add_edge(int u, int v, i64 c) {
        if (c < 0) throw std::invalid_argument("negative capacity");
        to_.push_back(v), cap_.push_back(c), next_.push_back(head_[U(u)]), head_[U(u)] = static_cast<int>(to_.size()) - 1;
        to_.push_back(u), cap_.push_back(0), next_.push_back(head_[U(v)]), head_[U(v)] = static_cast<int>(to_.size()) - 1;
    }
    i64 max_flow(int s, int t) {
        i64 flow = 0;
        while (bfs(s, t)) {
            it_ = head_;
            flow += blocking_flow(s, t);
        }
        return flow;
    }
    std::vector<bool> source_side(int s) const {  // residual reachability after max_flow = min-cut source side
        std::vector<bool> seen(U(n_));
        std::deque<int> q{s};
        seen[U(s)] = true;
        while (!q.empty()) {
            int u = q.front();
            q.pop_front();
            for (int e = head_[U(u)]; e != -1; e = next_[U(e)])
                if (cap_[U(e)] > 0 && !seen[U(to_[U(e)])]) seen[U(to_[U(e)])] = true, q.push_back(to_[U(e)]);
        }
        return seen;
    }

private:
    bool bfs(int s, int t) {
        level_.assign(U(n_), -1);
        Vec q{s};
        level_[U(s)] = 0;
        for (std::size_t h = 0; h < q.size(); ++h)
            for (int u = q[h], e = head_[U(u)]; e != -1; e = next_[U(e)])
                if (cap_[U(e)] > 0 && level_[U(to_[U(e)])] == -1) level_[U(to_[U(e)])] = level_[U(u)] + 1, q.push_back(to_[U(e)]);
        return level_[U(t)] != -1;
    }
    i64 blocking_flow(int s, int t) {  // iterative: no recursion, depth = path length
        i64 total = 0;
        Vec path;
        int u = s;
        while (true) {
            if (u == t) {
                i64 f = std::numeric_limits<i64>::max();
                for (int e : path) f = std::min(f, cap_[U(e)]);
                for (int e : path) cap_[U(e)] -= f, cap_[U(e ^ 1)] += f;
                total += f, path.clear(), u = s;
                continue;
            }
            int e = it_[U(u)];
            while (e != -1 && !(cap_[U(e)] > 0 && level_[U(to_[U(e)])] == level_[U(u)] + 1)) e = next_[U(e)];
            it_[U(u)] = e;
            if (e == -1) {  // dead end: prune u from the level graph, retreat
                if (u == s) return total;
                level_[U(u)] = -1;
                u = to_[U(path.back() ^ 1)];
                path.pop_back();
                continue;
            }
            path.push_back(e);
            u = to_[U(e)];
        }
    }
    int n_;
    Vec head_, next_, to_, level_, it_;
    std::vector<i64> cap_;
};

// ======================================================================= Extension A: lock-free union-find
// Path halving and linking by CAS. Linking a root only under a SMALLER index makes cycles impossible.
class ConcurrentDsu {
public:
    explicit ConcurrentDsu(int n) : parent_(U(n)) {
        for (int i = 0; i < n; ++i) parent_[U(i)].store(i, std::memory_order_relaxed);
    }
    int find(int x) {
        while (true) {
            int p = parent_[U(x)].load(std::memory_order_acquire);
            if (p == x) return x;
            int gp = parent_[U(p)].load(std::memory_order_acquire);
            if (p != gp) parent_[U(x)].compare_exchange_weak(p, gp, std::memory_order_release, std::memory_order_relaxed);
            x = gp;  // best-effort halving; losing the race is harmless
        }
    }
    void unite(int a, int b) {
        while (true) {
            a = find(a), b = find(b);
            if (a == b) return;
            if (a > b) std::swap(a, b);
            int expected = b;
            if (parent_[U(b)].compare_exchange_strong(expected, a, std::memory_order_acq_rel)) return;  // b must still be a root
        }
    }

private:
    std::vector<std::atomic<int>> parent_;
};

template <class Body>
double parallel(int threads, Body body) {
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    std::chrono::steady_clock::time_point t0;
    {
        std::vector<std::jthread> ts;
        for (int t = 0; t < threads; ++t)
            ts.emplace_back([&, t] {
                ready.fetch_add(1);
                while (!go.load(std::memory_order_acquire)) {}
                body(t);
            });
        while (ready.load() < threads) {}
        t0 = std::chrono::steady_clock::now();
        go.store(true, std::memory_order_release);
    }
    return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
}

int main() {
    SplitMix64 r{101};
    constexpr int trials = 2'000;
    int ok_rollback = 0, ok_parity = 0, ok_cut = 0, ok_match = 0;
    for (int t = 0; t < trials; ++t) {
        int n = 2 + r.next_int(9);
        RollbackDsu rb(n);
        std::vector<std::pair<int, int>> log;
        bool ok = true;
        for (int step = 0; step < 40; ++step) {
            if (r.next_int(4) == 0 && !log.empty()) {
                auto keep = U(r.next_int(static_cast<int>(log.size()) + 1));
                rb.rollback(keep);
                log.resize(keep);
            } else {
                int a = r.next_int(n), b = r.next_int(n);
                rb.unite(a, b);
                log.emplace_back(a, b);
            }
            Dsu fresh(n);
            for (auto [a, b] : log) fresh.unite(a, b);
            for (int a = 0; a < n; ++a)
                for (int b = 0; b < n; ++b) ok = ok && (rb.find(a) == rb.find(b)) == (fresh.find(a) == fresh.find(b));
        }
        ok_rollback += ok;
        int m = 1 + r.next_int(2 * n);
        Vec f(U(m)), to(U(m));
        for (std::size_t e = 0; e < U(m); ++e) {
            f[e] = r.next_int(n);
            to[e] = r.next_int(n);
        }
        ParityDsu pd(n);
        int first_bad = -1, oracle_bad = -1;
        for (std::size_t e = 0; e < U(m); ++e)
            if (!pd.add_edge(f[e], to[e]) && first_bad == -1) first_bad = static_cast<int>(e);
        for (std::size_t e = 0; e < U(m) && oracle_bad == -1; ++e)
            if (!bipartite_bfs(n, f, to, e + 1)) oracle_bad = static_cast<int>(e);
        ok_parity += first_bad == oracle_bad;
        int fm = r.next_int(3 * n);
        Vec cf(U(fm)), ct(U(fm)), cc(U(fm));
        Dinic d(n);
        for (std::size_t e = 0; e < U(fm); ++e) {
            cf[e] = r.next_int(n);
            ct[e] = r.next_int(n);
            cc[e] = r.next_int(10);
            d.add_edge(cf[e], ct[e], cc[e]);
        }
        i64 flow = d.max_flow(0, n - 1);
        auto side = d.source_side(0);
        i64 cut_cap = 0, brute = std::numeric_limits<i64>::max();
        for (std::size_t e = 0; e < U(fm); ++e)
            if (side[U(cf[e])] && !side[U(ct[e])]) cut_cap += cc[e];
        for (unsigned mask = 0; mask < (1u << n); ++mask) {
            if ((mask & 1) == 0 || (mask >> (n - 1) & 1) == 1) continue;  // s inside, t outside
            i64 c = 0;
            for (std::size_t e = 0; e < U(fm); ++e)
                if ((mask >> cf[e] & 1) == 1 && (mask >> ct[e] & 1) == 0) c += cc[e];
            brute = std::min(brute, c);
        }
        ok_cut += flow == brute && cut_cap == flow && !side[U(n - 1)];
        int left = 1 + r.next_int(7), right = 1 + r.next_int(7);
        std::vector<std::vector<bool>> adj(U(left), std::vector<bool>(U(right)));
        Dinic mf(left + right + 2);
        int src = left + right, sink = src + 1;
        for (int i = 0; i < left; ++i) mf.add_edge(src, i, 1);
        for (int j = 0; j < right; ++j) mf.add_edge(left + j, sink, 1);
        for (int i = 0; i < left; ++i)
            for (int j = 0; j < right; ++j)
                if (r.next_int(3) == 0) adj[U(i)][U(j)] = true, mf.add_edge(i, left + j, 1);
        Vec best(std::size_t{1} << right);
        for (int i = 0; i < left; ++i) {
            Vec nb = best;
            for (std::size_t mask = 0; mask < best.size(); ++mask)
                for (int j = 0; j < right; ++j)
                    if (adj[U(i)][U(j)] && (mask >> j & 1) == 0) nb[mask | std::size_t{1} << j] = std::max(nb[mask | std::size_t{1} << j], best[mask] + 1);
            best = std::move(nb);
        }
        ok_match += mf.max_flow(src, sink) == *std::ranges::max_element(best);
    }
    std::println("random small instances ({} each) vs independent oracles:", trials);
    std::println("   rollback DSU == rebuild-from-surviving-unions after every step  {}/{}", ok_rollback, trials);
    std::println("   parity DSU: first odd-cycle edge == BFS 2-colouring of every prefix {}/{}", ok_parity, trials);
    std::println("   Dinic max flow == residual min cut == brute force over all s-t cuts {}/{}", ok_cut, trials);
    std::println("   matching as unit-capacity Dinic == bitmask DP                     {}/{}", ok_match, trials);

    constexpr int n = 1 << 20, threads = 8, per_thread = 1 << 19;
    std::vector<Vec> ea(U(threads), Vec(U(per_thread))), eb = ea;
    for (std::size_t t = 0; t < U(threads); ++t)
        for (std::size_t i = 0; i < U(per_thread); ++i) {
            ea[t][i] = r.next_int(n);
            eb[t][i] = r.next_int(n);
        }
    Dsu seq(n);
    auto s0 = std::chrono::steady_clock::now();
    for (std::size_t t = 0; t < U(threads); ++t)
        for (std::size_t i = 0; i < U(per_thread); ++i) seq.unite(ea[t][i], eb[t][i]);
    double ms_seq = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - s0).count();
    Dsu locked(n);
    std::mutex mu;
    double ms_locked = parallel(threads, [&](int t) {
        for (std::size_t i = 0; i < U(per_thread); ++i) {
            std::scoped_lock lock(mu);
            locked.unite(ea[U(t)][i], eb[U(t)][i]);
        }
    });
    ConcurrentDsu cas(n);
    double ms_cas = parallel(threads, [&](int t) {
        for (std::size_t i = 0; i < U(per_thread); ++i) cas.unite(ea[U(t)][i], eb[U(t)][i]);
    });
    bool same = true;
    int cas_sets = 0;
    for (int i = 0; i < n; ++i) {
        same = same && (seq.find(i) == seq.find(0)) == (cas.find(i) == cas.find(0));
        cas_sets += cas.find(i) == i;
    }
    std::println("A. {} unions over {} elements (one measured run): sequential {:.0f} ms | {} threads + one mutex {:.0f} ms |"
                 " {} threads lock-free CAS {:.0f} ms | sets {} / {} / {}, same partition {}", threads * per_thread, n, ms_seq,
                 threads, ms_locked, threads, ms_cas, seq.sets(), locked.sets(), cas_sets, same);
}
```

**Output, GCC 16.2 (verified; the last line is one measured run):**

```text
random small instances (2000 each) vs independent oracles:
   rollback DSU == rebuild-from-surviving-unions after every step  2000/2000
   parity DSU: first odd-cycle edge == BFS 2-colouring of every prefix 2000/2000
   Dinic max flow == residual min cut == brute force over all s-t cuts 2000/2000
   matching as unit-capacity Dinic == bitmask DP                     2000/2000
A. 4194304 unions over 1048576 elements (one measured run): sequential 48 ms | 8 threads + one mutex 663 ms | 8 threads lock-free CAS 13 ms | sets 338 / 338 / 338, same partition true
```

**Output, Clang 21.1 (verified; the last line is one measured run):**

```text
random small instances (2000 each) vs independent oracles:
   rollback DSU == rebuild-from-surviving-unions after every step  2000/2000
   parity DSU: first odd-cycle edge == BFS 2-colouring of every prefix 2000/2000
   Dinic max flow == residual min cut == brute force over all s-t cuts 2000/2000
   matching as unit-capacity Dinic == bitmask DP                     2000/2000
A. 4194304 unions over 1048576 elements (one measured run): sequential 35 ms | 8 threads + one mutex 339 ms | 8 threads lock-free CAS 12 ms | sets 338 / 338 / 338, same partition true
```

---

## 3. What the results show

* **Four independent oracles, 2,000 instances each, zero disagreements.** Rollback is checked against rebuilding from the surviving unions after *every* step. Parity is checked against BFS 2-colouring of *every* prefix. Flow is checked three ways: max-flow value, residual cut capacity, and the minimum over all 2^(n−2) s–t cuts. Matching is checked against a bitmask DP over the right side.
* **A sizing bug caught on the first run:** the Java rollback history was allocated with `n` slots, but it grows with the number of **union calls**, not the number of elements. The first trial threw `ArrayIndexOutOfBoundsException`; the history is now growable. In C++ it's a `std::vector` from the start. Worth stating in an interview: *"undo logs scale with operations, not with state."*
* **Lock-free union-find, 4 M unions over 1 M elements:**

| Version | Java | C++ GCC | C++ Clang |
|---|---|---|---|
| Sequential (path halving + size) | 104–184 ms (one-shot, includes JIT warm-up) | 48–49 ms | 35–36 ms |
| 8 threads + one lock | 351–404 ms | 511–663 ms | 329–339 ms |
| 8 threads, lock-free CAS | 65–72 ms | 13 ms | 12 ms |

Every version produced the same 338 sets and the same membership for vertex 0's set. The lock makes 8 threads slower than one; the CAS version is 3–4× faster than sequential in C++, and 1.4–2.8× in Java, whose single-shot sequential time varies with JIT warm-up. Unions on random pairs rarely touch the same roots, so most CASes succeed the first time.

---

## 4. The last 10 minutes: Extensions A, B and C

### 4.1 Extension A — "64 threads union and query"

* **Lock-free DSU** (measured): CAS linking by index order plus best-effort halving. `find` can return a root that is no longer a root by the time the caller uses it, so `connected(a, b)` must loop until both finds are stable: return true if the roots are equal, or false only if a's root is still a root after reading b's.
* **Flow** is inherently sequential within a phase. Parallelize **across** independent problems (one flow per request), or use push-relabel, whose local operations parallelize better than augmenting paths ⚠.
* **Bipartite matching services** (ride-hailing, ad allocation) rarely run exact matching on a global graph per request. They batch requests per time window and solve each batch, often approximately with greedy or auction algorithms, which parallelize.

### 4.2 Extension B — "edges arrive as an unbounded stream"

* **Connectivity over a stream** is exactly what a DSU does in O(V) memory: edges are never stored. Connected components of an edge stream are a one-pass, semi-streaming algorithm.
* **Bipartiteness over a stream:** parity DSU, also O(V) memory, reports the first violating edge online.
* **Sliding-window connectivity** (only edges from the last hour count) needs deletions. Offline: divide and conquer over time with a rollback DSU (each edge is inserted into O(log T) segments of a time segment tree, and the DFS over that tree applies and rolls back). Online: link-cut trees or HDT dynamic connectivity ⚠ (heavy machinery; name it).

### 4.3 Extension C — "the graph is spread across 100 machines"

* **Connected components:** each machine runs a local DSU over its edges, then the machines exchange (vertex, local root) pairs for vertices that appear on several machines, and a coordinator or a second DSU round merges them. Alternatively, label propagation, where each vertex takes the minimum label of its neighbours per BSP superstep: O(diameter) rounds. "Hash-to-min" style algorithms bring that down to O(log n) rounds on real graphs ⚠.
* **Min cut across machines** is hard to distribute exactly. Real systems partition the graph to keep flow problems local (per region, per tenant) and solve them on one machine. For approximate global min cuts, sparsification (Karger) shrinks the graph to fit one machine.
* **Matching at scale:** solve per shard, then repair along shard boundaries with augmenting paths limited to boundary vertices. Matching isn't a matroid, so unlike Folder 02's job scheduling, local optima don't merge exactly. Say so.

---

## 5. Failure modes

| # | Failure | Symptom | Prevention |
|---|---|---|---|
| F1 | Recursive find | Stack overflow on a long pre-compression chain | Iterative path halving |
| F2 | Compression in a rollback DSU | Undo impossible or wrong | Union by size only; O(log n) find |
| F3 | Undo log sized by n | Out-of-bounds after more unions than elements | Size by operations; growable |
| F4 | Skipping no-op unions in the history | Rollback to a checkpoint undoes the wrong unions | Record no-ops too |
| F5 | Reporting only the max-flow value | The actual question (the cut) unanswered | Residual reachability → source side → cut edges |
| F6 | Recursive augmenting DFS | Stack overflow on long level graphs | Iterative blocking flow with retreat |
| F7 | One lock around a shared DSU | Slower than single-threaded | CAS linking by index order |
| F8 | Lock-free `connected()` read once | Stale answer | Re-check roots until stable |
| F9 | Assuming local matchings merge | Suboptimal global matching | Boundary repair; matching is not a matroid |

---

## 6. Bar-raiser chains

<details><summary><b>Q1 · "Why is union-find nearly O(1)?"</b></summary>

**Initial Prompt.** After the candidate writes DSU with both optimizations.

**L5 Answer.** "Path compression makes trees flat."

**Why L5 Stalls.** Half the argument; compression alone is O(log n) amortized, and the candidate can't say what each optimization buys.

**L7 Answer.** "Union by size alone bounds depth by log n, since a node gets deeper only when its tree doubles. Path compression flattens paths as they're walked. Together the amortized cost is inverse-Ackermann, at most 4 or 5 for any real n. I write the compression as iterative halving, so no recursion. And when I need undo, I drop compression and keep union by size, accepting O(log n) finds."
</details>

<details><summary><b>Q2 · "Edges are added and removed over time; answer connectivity queries."</b></summary>

**Initial Prompt.** Offline dynamic connectivity.

**L5 Answer.** "Rebuild the DSU for each query."

**Why L5 Stalls.** O(E) per query.

**L7 Answer.** "Offline: each edge is alive on a time interval, which I insert into a segment tree over time, so every edge sits in O(log T) nodes. Then a DFS over that tree applies the node's edges with a rollback DSU on the way down, answers queries at the leaves, and rolls back on the way up. Rollback needs union by size without path compression, so each union is one undoable pair of writes. Total O((E log T + Q) log V)."
</details>

<details><summary><b>Q3 · "After which edge does this graph stop being bipartite?"</b></summary>

**Initial Prompt.** Edges arrive one at a time.

**L5 Answer.** "Run BFS 2-colouring after each edge."

**Why L5 Stalls.** O(V + E) per edge, O(E²) total.

**L7 Answer.** "A DSU that stores each node's colour parity relative to its parent. An edge between two nodes in the same set with equal parity closes an odd cycle: that's the answer. Otherwise I link the roots with the parity that gives the endpoints different colours. O(log n) per edge, online, O(V) memory. I checked it against BFS on every prefix of 2,000 random graphs."
</details>

<details><summary><b>Q4 · "Maximum bipartite matching between drivers and riders."</b></summary>

**Initial Prompt.** Classic matching.

**L5 Answer.** Kuhn's augmenting-path DFS, O(VE), recursive.

**Why L5 Stalls.** Correct for small inputs; slow for large ones; recursion depth up to V.

**L7 Answer.** "Model it as max flow: a source to every driver with capacity 1, every rider to a sink with capacity 1, and compatible pairs with capacity 1. Dinic on that unit network runs in O(E√V), which is Hopcroft–Karp's bound, without writing Hopcroft–Karp. I'd write the blocking flow iteratively. In production, matching per time window and per region keeps each problem small, and greedy or auction methods trade a little optimality for latency."
</details>

<details><summary><b>Q5 · "Which links should we upgrade to raise throughput from s to t?"</b></summary>

**Initial Prompt.** The interviewer wants the cut, not the number.

**L5 Answer.** "The max flow is 42."

**Why L5 Stalls.** Answers a different question.

**L7 Answer.** "By max-flow min-cut, the bottleneck is a minimum s–t cut. After the max flow, the vertices reachable from s in the residual graph form its source side, and the saturated edges leaving that set are the cut. Upgrading anything else can't raise throughput. I verified on random graphs that the residual cut's capacity equals both the flow value and the brute-force minimum cut."
</details>

<details><summary><b>Q6 · "64 threads add edges to a shared union-find."</b></summary>

**Initial Prompt.** Extension A.

**L5 Answer.** "Synchronize union and find."

**Why L5 Stalls.** Measured: one lock made 8 threads slower than a single thread.

**L7 Answer.** "Lock-free. Link with a compare-and-set on the loser's parent, which succeeds only if it's still a root, else retry, and always link the larger index under the smaller so cycles can't form. Path halving with CAS is best-effort: a failed CAS is harmless. I measured 1.4–4× faster than sequential on 8 threads, versus 2–14× slower with one lock. The caveat is that `find` can return a root that's stale a moment later, so `connected(a, b)` has to re-check that the roots are still roots."
</details>

<details><summary><b>Q7 · "Connected components of a graph spread across 100 machines."</b></summary>

**Initial Prompt.** Extension C.

**L5 Answer.** "Run union-find on each machine."

**Why L5 Stalls.** Components span machines; local results must be merged.

**L7 Answer.** "Two phases. Each machine builds a local DSU over its edges, then emits (vertex, local root) for vertices that appear on more than one machine. Merging those pairs is a much smaller union-find: one coordinator, or a reduce by vertex hash. The alternative is label propagation, minimum label per superstep, which takes diameter-many rounds. Faster round-reducing schemes exist for skewed real graphs. The local-then-merge pattern works because union is associative and commutative."
</details>

<details><summary><b>Q8 · "Undo the last k merges."</b></summary>

**Initial Prompt.** A feature request on top of DSU (an editor's merge/unmerge, a game's grouping).

**L5 Answer.** "Keep a copy of the parent array before each merge."

**Why L5 Stalls.** O(n) per merge in memory and time.

**L7 Answer.** "A rollback DSU: union by size without path compression, so each merge changes exactly one parent pointer and one size, logged as one entry. Undo pops k entries. No-op merges are logged too, so 'undo k' is exact. Finds become O(log n), the price of undoability. The log grows with operations, so it needs a cap or a checkpoint policy for long sessions."
</details>

---

## 7. Checklist

* [ ] Iterative find with halving; union by size.
* [ ] Rollback: no compression; log every union (including no-ops); size the log by operations.
* [ ] Parity / weighted DSU for consistency constraints and online bipartiteness.
* [ ] Matching = unit-capacity max flow (Dinic's O(E√V)).
* [ ] Report the min cut (residual reachability), not just the flow value.
* [ ] Iterative blocking flow; prune dead ends.
* [ ] Extension A: CAS linking by index order; re-check roots for `connected`.
* [ ] Extension B: DSU is a semi-streaming algorithm; time-segment-tree + rollback for deletions.
* [ ] Extension C: local DSU + merge of boundary roots; label propagation; matching needs boundary repair.

---

## 8. References

* R. E. Tarjan, *Efficiency of a Good But Not Linear Set Union Algorithm*, JACM 22(2), 1975 — DOI 10.1145/321879.321884
* R. J. Anderson, H. Woll, *Wait-free Parallel Algorithms for the Union-Find Problem*, STOC 1991 — DOI 10.1145/103418.103458
* E. A. Dinic, *Algorithm for solution of a problem of maximum flow in networks with power estimation*, Soviet Math. Doklady 11, 1970; S. Even, R. E. Tarjan, *Network Flow and Testing Graph Connectivity*, SIAM J. Computing 4(4), 1975 — DOI 10.1137/0204043 (the O(E√V) unit-network bound)
* J. E. Hopcroft, R. M. Karp, *An n^{5/2} Algorithm for Maximum Matchings in Bipartite Graphs*, SIAM J. Computing 2(4), 1973 — DOI 10.1137/0202019
* L. R. Ford, D. R. Fulkerson, *Maximal Flow Through a Network*, Canadian J. Math 8, 1956 — DOI 10.4153/CJM-1956-045-5
* cp-algorithms: [DSU](https://cp-algorithms.com/data_structures/disjoint_set_union.html), [Dinic](https://cp-algorithms.com/graph/dinic.html), [Deleting from a DSU in O(log n) (offline dynamic connectivity)](https://cp-algorithms.com/data_structures/deleting_in_log_n.html)
* LeetCode anchors: [684 Redundant Connection](https://leetcode.com/problems/redundant-connection/), [785 Is Graph Bipartite?](https://leetcode.com/problems/is-graph-bipartite/), [886 Possible Bipartition](https://leetcode.com/problems/possible-bipartition/), [1579 Remove Max Number of Edges to Keep Graph Fully Traversable](https://leetcode.com/problems/remove-max-number-of-edges-to-keep-graph-fully-traversable/)

*Folder 04:* [01 — 0-1 BFS, Dijkstra, Bellman–Ford](01-01-bfs-multi-source-dijkstra-state-space-graphs-and-bellman-ford.md) · [02 — topological sort, Tarjan SCC, bridges](02-topological-sort-kahn-cycle-detection-and-tarjan-scc-bridges-articulation.md)
