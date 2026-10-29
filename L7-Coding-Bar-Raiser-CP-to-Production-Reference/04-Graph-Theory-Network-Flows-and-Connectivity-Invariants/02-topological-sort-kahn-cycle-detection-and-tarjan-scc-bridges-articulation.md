# Topological Sort (Kahn), Cycle Detection, and Tarjan SCC, Bridges and Articulation Points

> **Folder 04 · File 2 of 3** — dependency order with proof of failure (a cycle witness, not a boolean), low-link values as "single points of failure", all without recursion, plus a parallel DAG executor and the race its first version had.
> **Languages:** Java 21 (`--release 21 -Xlint:all -Werror`, JDK 25.0.4.1) and C++23 (GCC 16.2 and Clang 21.1, `-O2`, warnings as errors).

| Listing | File | What it proves |
|---|---|---|
| 4.3 | `Connectivity.java` | Kahn with a min-heap returns a sealed `Order` or a **verified** `Cycle` witness; iterative Tarjan SCC equals mutual reachability; bridges and articulation points match remove-and-recount oracles; the parent-vertex contest habit misclassifies parallel edges; Tarjan on a 1 M-vertex path; a lock-free DAG executor with 0 dependency violations |
| 4.4 | `graph_connectivity.cpp` | The same with `std::variant` as the sealed result; identical counts. (Named so it doesn't collide with `Connectivity.java` on a case-insensitive file system) |

**Verification.** Both listings were extracted from this file, compiled and run. Everything is **Output (verified)** except the two timing lines (**one measured run**).

---

## 0. Orientation

| Contest habit | What breaks | L7 replacement |
|---|---|---|
| `return false` when a cycle exists | The caller (a build tool, a scheduler) can't tell the user *what* to fix | Return the cycle: a sealed `Order` / `Cycle` result, checked edge by edge |
| Any topological order | Non-deterministic builds, flaky tests | Lexicographically smallest order via a min-heap: deterministic by contract |
| Recursive Tarjan / DFS | Stack overflow on long dependency chains | Explicit call stack of (vertex, next-edge) frames |
| Skip the parent *vertex* in low-link | Parallel edges reported as bridges (27% of random multigraphs wrong) | Skip the parent *edge id* |
| Topological order computed, tasks run sequentially | Leaves parallelism unused | In-degree counters + a ready queue: a task starts the moment its last dependency finishes |

---

## 1. First principles

### 1.1 Kahn's algorithm and the cycle witness

Repeatedly remove a vertex with in-degree 0, decrementing its successors' in-degrees. If every vertex is removed, the removal order is topological. If some remain, **every remaining vertex has a remaining predecessor**: its in-degree is still positive, and only remaining vertices can contribute to it. Start anywhere among them and walk to a remaining predecessor, then to its remaining predecessor, and so on. The walk can't go on forever in a finite set, so it revisits a vertex, and the segment between the two visits is a directed cycle. That is a constructive proof and an O(V + E) algorithm for an **explanation**: "`build.gradle` cycle: 1 → 2 → 1".

Using a **min-heap** instead of a queue for the ready set gives the lexicographically smallest order. That costs log V per vertex and makes the output deterministic. For a build system, that means reproducible build logs; for a test, it means exact expected output.

### 1.2 Tarjan's low-link

DFS assigns each vertex a discovery index. `low[u]` is the smallest index reachable from u's DFS subtree using at most one back edge to a vertex still on the stack. A vertex u with `low[u] == index[u]` is the **root of an SCC**: nothing below it climbs higher, so everything above it on the stack belongs to its component. Pop them. Components come out in reverse topological order of the condensation DAG, which is useful in itself, for example for 2-SAT.

### 1.3 Bridges and articulation points: single points of failure

In an **undirected** graph with DFS discovery times `tin` and low-links over non-tree edges:

* **Bridge** (p, u): `low[u] > tin[p]`. Nothing in u's subtree has a back edge to p or above, so removing the edge disconnects the subtree. *A single link whose failure partitions the network.*
* **Articulation point** p (non-root): some child u with `low[u] ≥ tin[p]`. u's subtree reaches back no further than p, so removing p disconnects it. The root is an articulation point iff it has ≥ 2 DFS children. *A single router or service whose failure partitions the network.*

**The parallel-edge trap.** To avoid treating the tree edge to the parent as a back edge, contest code skips the parent **vertex**. But with two parallel edges between p and u, the second edge *is* a genuine back edge, and skipping it reports a bridge that is really redundant. Skip the specific **edge id** you arrived by instead. The listing's contest variant was wrong on 27% of random multigraphs (2,173 of 3,000 correct). The minimal case, two parallel edges between 0 and 1, is the redundant-link scenario a network engineer would test first.

### 1.4 Recursion-free DFS

All three algorithms are DFS with post-order work. The iterative form keeps an explicit frame per active vertex, `(vertex, next-edge index)`. "Recursing" pushes a frame, and "returning" pops it and propagates `low` to the new top frame. The code is a mechanical transformation of the recursive version, which is why it's worth knowing by heart.

---

## 2. The listings

### 2.1 Listing 4.3 — Java

```java
// Connectivity.java - Kahn with a cycle witness, iterative Tarjan SCC, bridges/articulation points, and a parallel DAG runner.
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.PriorityQueue;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicIntegerArray;

public final class Connectivity {

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

    /** CSR adjacency; for undirected graphs each edge id appears in both endpoints' lists. Immutable. */
    static final class Graph {
        final int n;
        final int[] start, to, edgeId;

        Graph(int n, int[] from, int[] to, boolean undirected) {
            this.n = n;
            int m = from.length, slots = undirected ? 2 * m : m;
            start = new int[n + 1];
            for (int e = 0; e < m; e++) { start[from[e] + 1]++; if (undirected) start[to[e] + 1]++; }
            for (int i = 0; i < n; i++) start[i + 1] += start[i];
            int[] fill = Arrays.copyOf(start, n);
            this.to = new int[slots];
            edgeId = new int[slots];
            for (int e = 0; e < m; e++) {
                int k = fill[from[e]]++;
                this.to[k] = to[e];
                edgeId[k] = e;
                if (undirected) { k = fill[to[e]]++; this.to[k] = from[e]; edgeId[k] = e; }
            }
        }
    }

    // ===================================================================== 1. topological order or a cycle witness
    sealed interface TopoResult permits Order, Cycle {}
    record Order(int[] vertices) implements TopoResult {}
    record Cycle(List<Integer> vertices) implements TopoResult {}

    /**
     * Kahn's algorithm with a min-heap: the lexicographically smallest topological order, so the output is
     * deterministic and testable. If vertices remain, every one of them has a remaining predecessor; walking
     * predecessors must revisit a vertex, and the revisited stretch is a directed cycle -- returned as evidence.
     */
    static TopoResult topoSort(Graph g) {
        int[] indeg = new int[g.n];
        for (int v : g.to) indeg[v]++;
        PriorityQueue<Integer> ready = new PriorityQueue<>();
        for (int v = 0; v < g.n; v++) if (indeg[v] == 0) ready.add(v);
        int[] order = new int[g.n];
        int k = 0;
        while (!ready.isEmpty()) {
            int u = ready.poll();
            order[k++] = u;
            for (int e = g.start[u]; e < g.start[u + 1]; e++) if (--indeg[g.to[e]] == 0) ready.add(g.to[e]);
        }
        if (k == g.n) return new Order(order);
        int[] pred = new int[g.n];
        Arrays.fill(pred, -1);
        for (int u = 0; u < g.n; u++)
            for (int e = g.start[u]; e < g.start[u + 1]; e++) if (indeg[u] > 0 && indeg[g.to[e]] > 0) pred[g.to[e]] = u;
        int v = 0;
        while (indeg[v] == 0) v++;
        int[] seenAt = new int[g.n];
        Arrays.fill(seenAt, -1);
        List<Integer> walk = new ArrayList<>();
        while (seenAt[v] == -1) { seenAt[v] = walk.size(); walk.add(v); v = pred[v]; }
        List<Integer> cycle = new ArrayList<>(walk.subList(seenAt[v], walk.size()));
        java.util.Collections.reverse(cycle);  // walked backwards along edges
        return new Cycle(cycle);
    }

    static boolean isValidOrder(Graph g, int[] order) {
        int[] at = new int[g.n];
        for (int i = 0; i < order.length; i++) at[order[i]] = i;
        for (int u = 0; u < g.n; u++) for (int e = g.start[u]; e < g.start[u + 1]; e++) if (at[u] >= at[g.to[e]]) return false;
        return true;
    }

    static boolean isCycle(Graph g, List<Integer> c) {
        if (c.isEmpty()) return false;
        for (int i = 0; i < c.size(); i++) {
            int u = c.get(i), v = c.get((i + 1) % c.size());
            boolean edge = false;
            for (int e = g.start[u]; e < g.start[u + 1]; e++) edge |= g.to[e] == v;
            if (!edge) return false;
        }
        return true;
    }

    // ===================================================================== 2. Tarjan SCC, iterative
    /** comp[v] = SCC id; ids come out in reverse topological order of the condensation. No recursion. */
    static int[] tarjanScc(Graph g) {
        int n = g.n, timer = 0, comps = 0, top = 0, ctop = 0;
        int[] index = new int[n], low = new int[n], comp = new int[n], stack = new int[n], callV = new int[n], callE = new int[n];
        boolean[] onStack = new boolean[n];
        Arrays.fill(index, -1);
        for (int s = 0; s < n; s++) {
            if (index[s] != -1) continue;
            callV[ctop] = s; callE[ctop++] = g.start[s];
            index[s] = low[s] = timer++; stack[top++] = s; onStack[s] = true;
            while (ctop > 0) {
                int u = callV[ctop - 1];
                if (callE[ctop - 1] < g.start[u + 1]) {
                    int v = g.to[callE[ctop - 1]++];
                    if (index[v] == -1) {                       // "recurse"
                        index[v] = low[v] = timer++; stack[top++] = v; onStack[v] = true;
                        callV[ctop] = v; callE[ctop++] = g.start[v];
                    } else if (onStack[v]) {
                        low[u] = Math.min(low[u], index[v]);
                    }
                    continue;
                }
                ctop--;                                         // "return" from u
                if (low[u] == index[u]) {
                    int v;
                    do { v = stack[--top]; onStack[v] = false; comp[v] = comps; } while (v != u);
                    comps++;
                }
                if (ctop > 0) { int p = callV[ctop - 1]; low[p] = Math.min(low[p], low[u]); }
            }
        }
        return comp;
    }

    static boolean[][] reach(Graph g) {
        boolean[][] r = new boolean[g.n][g.n];
        for (int s = 0; s < g.n; s++) {
            int[] q = new int[g.n];
            int h = 0, t = 0;
            r[s][s] = true;
            q[t++] = s;
            while (h < t) { int u = q[h++]; for (int e = g.start[u]; e < g.start[u + 1]; e++) if (!r[s][g.to[e]]) { r[s][g.to[e]] = true; q[t++] = g.to[e]; } }
        }
        return r;
    }

    // ===================================================================== 3. bridges and articulation points (undirected)
    /** low-link over edge ids: skip the EDGE we came in on, not the parent VERTEX, so parallel edges are not bridges. */
    static boolean[][] bridgesAndCuts(Graph g, int m, boolean skipParentVertex) {
        int n = g.n, timer = 0, ctop = 0;
        int[] tin = new int[n], low = new int[n], callV = new int[n], callE = new int[n], viaEdge = new int[n], parent = new int[n];
        int[] children = new int[n];
        boolean[] bridge = new boolean[m], cut = new boolean[n];
        Arrays.fill(tin, -1);
        for (int s = 0; s < n; s++) {
            if (tin[s] != -1) continue;
            tin[s] = low[s] = timer++;
            parent[s] = -1; viaEdge[s] = -1;
            callV[ctop] = s; callE[ctop++] = g.start[s];
            while (ctop > 0) {
                int u = callV[ctop - 1];
                if (callE[ctop - 1] < g.start[u + 1]) {
                    int slot = callE[ctop - 1]++, v = g.to[slot], id = g.edgeId[slot];
                    boolean back = skipParentVertex ? v == parent[u] : id == viaEdge[u];
                    if (back) continue;
                    if (tin[v] == -1) {
                        tin[v] = low[v] = timer++;
                        parent[v] = u; viaEdge[v] = id; children[u]++;
                        callV[ctop] = v; callE[ctop++] = g.start[v];
                    } else {
                        low[u] = Math.min(low[u], tin[v]);
                    }
                    continue;
                }
                ctop--;
                int p = parent[u];
                if (p != -1) {
                    low[p] = Math.min(low[p], low[u]);
                    if (low[u] > tin[p]) bridge[viaEdge[u]] = true;                 // nothing below u climbs over (p,u)
                    if (parent[p] != -1 && low[u] >= tin[p]) cut[p] = true;         // u's subtree hangs only on p
                } else if (children[u] > 1) {
                    cut[u] = true;                                                   // a root with 2+ DFS children
                }
            }
        }
        return new boolean[][] {bridge, cut};
    }

    static int components(int n, int[] from, int[] to, int skipEdge, int skipVertex) {
        int[] p = new int[n];
        for (int i = 0; i < n; i++) p[i] = i;
        int comps = n - (skipVertex >= 0 ? 1 : 0);
        for (int e = 0; e < from.length; e++) {
            if (e == skipEdge || from[e] == skipVertex || to[e] == skipVertex) continue;
            int a = from[e], b = to[e];
            while (p[a] != a) a = p[a] = p[p[a]];
            while (p[b] != b) b = p[b] = p[p[b]];
            if (a != b) { p[a] = b; comps--; }
        }
        return comps;
    }

    // ===================================================================== Extension A: run a DAG of tasks in parallel
    static double busyWork(int units) {  // a deterministic CPU-bound task
        double x = 0;
        for (int i = 0; i < units; i++) x += Math.sqrt(i + 1.0);
        return x;
    }

    static volatile double sink;

    /** Each task starts when its in-degree reaches 0 (atomic decrement by finishing predecessors). */
    static long[] runDag(Graph dag, int threads, int units) throws InterruptedException {
        AtomicIntegerArray indeg = new AtomicIntegerArray(dag.n);
        for (int v : dag.to) indeg.incrementAndGet(v);
        long[] startedAt = new long[dag.n], finishedAt = new long[dag.n];
        AtomicInteger clock = new AtomicInteger();
        CountDownLatch done = new CountDownLatch(dag.n);
        ExecutorService pool = Executors.newFixedThreadPool(threads);
        class Task implements Runnable {
            final int v;
            Task(int v) { this.v = v; }
            @Override
            public void run() {
                startedAt[v] = clock.incrementAndGet();
                sink = busyWork(units);
                finishedAt[v] = clock.incrementAndGet();
                for (int e = dag.start[v]; e < dag.start[v + 1]; e++) if (indeg.decrementAndGet(dag.to[e]) == 0) pool.execute(new Task(dag.to[e]));
                done.countDown();
            }
        }
        // Snapshot the initial ready set BEFORE submitting anything. The first version submitted inside this loop, read
        // in-degrees that running tasks were already decrementing, and ran some tasks twice (25 dependency violations).
        List<Integer> roots = new ArrayList<>();
        for (int v = 0; v < dag.n; v++) if (indeg.get(v) == 0) roots.add(v);
        for (int v : roots) pool.execute(new Task(v));
        done.await();
        pool.shutdown();
        long violations = 0;
        for (int u = 0; u < dag.n; u++) for (int e = dag.start[u]; e < dag.start[u + 1]; e++) if (finishedAt[u] > startedAt[dag.to[e]]) violations++;
        return new long[] {violations};
    }

    public static void main(String[] args) throws InterruptedException {
        SplitMix64 r = new SplitMix64(91);
        int trials = 3_000, okTopo = 0, cycles = 0, okScc = 0, okBridge = 0, okCut = 0, cpBridge = 0;
        for (int t = 0; t < trials; t++) {
            int n = 1 + r.nextInt(10), m = r.nextInt(2 * n + 1);
            int[] f = new int[m], to = new int[m];
            for (int e = 0; e < m; e++) { f[e] = r.nextInt(n); to[e] = r.nextInt(n); }
            Graph g = new Graph(n, f, to, false);
            boolean[][] rc = reach(g);
            boolean acyclic = true;
            for (int u = 0; u < n; u++) for (int v = 0; v < n; v++) if (u != v && rc[u][v] && rc[v][u]) acyclic = false;
            for (int u = 0; u < n; u++) for (int e = g.start[u]; e < g.start[u + 1]; e++) if (g.to[e] == u) acyclic = false;
            TopoResult res = topoSort(g);
            boolean ok = switch (res) {
                case Order o -> acyclic && isValidOrder(g, o.vertices());
                case Cycle c -> !acyclic && isCycle(g, c.vertices());
            };
            okTopo += ok ? 1 : 0;
            cycles += acyclic ? 0 : 1;
            int[] comp = tarjanScc(g);
            boolean sccOk = true;
            for (int u = 0; u < n; u++) for (int v = 0; v < n; v++) sccOk &= (comp[u] == comp[v]) == (rc[u][v] && rc[v][u]);
            okScc += sccOk ? 1 : 0;
            int[] uf = new int[m], ut = new int[m];
            for (int e = 0; e < m; e++) { uf[e] = r.nextInt(n); ut[e] = r.nextInt(n); if (uf[e] == ut[e]) ut[e] = (ut[e] + 1) % n; }
            if (n == 1) { uf = new int[0]; ut = new int[0]; }
            Graph ug = new Graph(n, uf, ut, true);
            boolean[][] bc = bridgesAndCuts(ug, uf.length, false), cpBc = bridgesAndCuts(ug, uf.length, true);
            int base = components(n, uf, ut, -1, -1);
            boolean bOk = true, cpOk = true, cOk = true;
            for (int e = 0; e < uf.length; e++) {
                boolean truth = components(n, uf, ut, e, -1) > base;
                bOk &= bc[0][e] == truth;
                cpOk &= cpBc[0][e] == truth;
            }
            for (int v = 0; v < n; v++) cOk &= bc[1][v] == (components(n, uf, ut, -1, v) > base - (isolated(v, uf, ut) ? 1 : 0));
            okBridge += bOk ? 1 : 0;
            cpBridge += cpOk ? 1 : 0;
            okCut += cOk ? 1 : 0;
        }
        System.out.printf("random graphs, n <= 10 (%,d trials, %d with a cycle) vs reachability / remove-and-recount oracles:%n", trials, cycles);
        System.out.printf("   Kahn: valid lexicographic order, or a VERIFIED cycle witness  %d/%d%n", okTopo, trials);
        System.out.printf("   iterative Tarjan SCC == mutual reachability                   %d/%d%n", okScc, trials);
        System.out.printf("   bridges, skipping the parent EDGE id                          %d/%d%n", okBridge, trials);
        System.out.printf("   bridges, skipping the parent VERTEX (contest habit)           %d/%d%n", cpBridge, trials);
        System.out.printf("   articulation points                                           %d/%d%n", okCut, trials);
        Graph multi = new Graph(2, new int[] {0, 0}, new int[] {1, 1}, true);
        System.out.printf("   two parallel edges 0-1: edge-id rule says bridge=%b, vertex rule says bridge=%b%n",
                bridgesAndCuts(multi, 2, false)[0][0], bridgesAndCuts(multi, 2, true)[0][0]);
        TopoResult c = topoSort(new Graph(4, new int[] {0, 1, 2, 3}, new int[] {1, 2, 1, 0}, false));
        System.out.println("   topoSort(0->1->2->1, 3->0) -> " + c);

        int n = 1 << 20;
        int[] f = new int[n - 1], t = new int[n - 1];
        for (int v = 1; v < n; v++) { f[v - 1] = v - 1; t[v - 1] = v; }
        long t0 = System.nanoTime();
        int[] comp = tarjanScc(new Graph(n, f, t, false));
        System.out.printf("   iterative Tarjan on a %,d-vertex path: %d ms, %,d components, no recursion%n",
                n, (System.nanoTime() - t0) / 1_000_000, Arrays.stream(comp).max().orElse(-1) + 1);

        int tasks = 2_000, units = 20_000;
        int[] df = new int[3 * tasks], dt = new int[3 * tasks];
        for (int e = 0; e < df.length; e++) {
            int a = r.nextInt(tasks), b = r.nextInt(tasks);
            if (a == b) b = (b + 1) % tasks;
            df[e] = Math.min(a, b);   // edges go from lower to higher id: acyclic by construction
            dt[e] = Math.max(a, b);
        }
        Graph dag = new Graph(tasks, df, dt, false);
        int[] longest = new int[tasks];
        for (int u = 0; u < tasks; u++) for (int e = dag.start[u]; e < dag.start[u + 1]; e++) longest[dag.to[e]] = Math.max(longest[dag.to[e]], longest[u] + 1);
        runDag(dag, 1, units);  // warm-up
        long s0 = System.nanoTime();
        long v1 = runDag(dag, 1, units)[0];
        long s1 = System.nanoTime();
        long v8 = runDag(dag, 8, units)[0];
        long s2 = System.nanoTime();
        System.out.printf("A. DAG of %,d tasks / %,d edges, critical path %d tasks (one measured run): 1 thread %d ms | 8 threads %d ms |"
                + " dependency violations %d and %d%n", tasks, df.length, Arrays.stream(longest).max().orElse(0) + 1,
                (s1 - s0) / 1_000_000, (s2 - s1) / 1_000_000, v1, v8);
    }

    static boolean isolated(int v, int[] uf, int[] ut) {
        for (int e = 0; e < uf.length; e++) if (uf[e] == v || ut[e] == v) return false;
        return true;
    }
}
```

**Output (verified; the last two lines are one measured run):**

```text
random graphs, n <= 10 (3,000 trials, 2066 with a cycle) vs reachability / remove-and-recount oracles:
   Kahn: valid lexicographic order, or a VERIFIED cycle witness  3000/3000
   iterative Tarjan SCC == mutual reachability                   3000/3000
   bridges, skipping the parent EDGE id                          3000/3000
   bridges, skipping the parent VERTEX (contest habit)           2173/3000
   articulation points                                           3000/3000
   two parallel edges 0-1: edge-id rule says bridge=false, vertex rule says bridge=true
   topoSort(0->1->2->1, 3->0) -> Cycle[vertices=[2, 1]]
   iterative Tarjan on a 1,048,576-vertex path: 64 ms, 1,048,576 components, no recursion
A. DAG of 2,000 tasks / 6,000 edges, critical path 16 tasks (one measured run): 1 thread 64 ms | 8 threads 20 ms | dependency violations 0 and 0
```

### 2.2 Listing 4.4 — C++23

```cpp
// graph_connectivity.cpp - Kahn with a cycle witness, iterative Tarjan SCC, bridges/articulation points, a parallel DAG runner.
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <mutex>
#include <print>
#include <queue>
#include <string>
#include <thread>
#include <variant>
#include <vector>

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

// CSR adjacency; for undirected graphs each edge id appears in both endpoints' lists. Immutable.
struct Graph {
    int n;
    Vec start, to, edge_id;
    Graph(int n_, const Vec& from, const Vec& tos, bool undirected) : n(n_), start(U(n_) + 1) {
        for (std::size_t e = 0; e < from.size(); ++e) {
            ++start[U(from[e]) + 1];
            if (undirected) ++start[U(tos[e]) + 1];
        }
        for (std::size_t i = 0; i < U(n); ++i) start[i + 1] += start[i];
        Vec fill(start.begin(), start.end() - 1);
        to.resize(undirected ? 2 * from.size() : from.size());
        edge_id.resize(to.size());
        for (std::size_t e = 0; e < from.size(); ++e) {
            auto k = U(fill[U(from[e])]++);
            to[k] = tos[e], edge_id[k] = static_cast<int>(e);
            if (undirected) k = U(fill[U(tos[e])]++), to[k] = from[e], edge_id[k] = static_cast<int>(e);
        }
    }
    std::size_t begin(int u) const { return U(start[U(u)]); }
    std::size_t end(int u) const { return U(start[U(u) + 1]); }
};

// ======================================================================= 1. topological order or a cycle witness
struct Order {
    Vec vertices;
};
struct Cycle {
    Vec vertices;
};
using TopoResult = std::variant<Order, Cycle>;  // the C++ spelling of a sealed result type

// Kahn with a min-heap (lexicographically smallest order). Leftover vertices all have a leftover predecessor;
// walking predecessors must revisit a vertex, and the revisited stretch is a directed cycle, returned as evidence.
TopoResult topo_sort(const Graph& g) {
    Vec indeg(U(g.n));
    for (int v : g.to) ++indeg[U(v)];
    std::priority_queue<int, Vec, std::greater<>> ready;
    for (int v = 0; v < g.n; ++v)
        if (indeg[U(v)] == 0) ready.push(v);
    Vec order;
    while (!ready.empty()) {
        int u = ready.top();
        ready.pop();
        order.push_back(u);
        for (auto e = g.begin(u); e < g.end(u); ++e)
            if (--indeg[U(g.to[e])] == 0) ready.push(g.to[e]);
    }
    if (static_cast<int>(order.size()) == g.n) return Order{order};
    Vec pred(U(g.n), -1);
    for (int u = 0; u < g.n; ++u)
        for (auto e = g.begin(u); e < g.end(u); ++e)
            if (indeg[U(u)] > 0 && indeg[U(g.to[e])] > 0) pred[U(g.to[e])] = u;
    int v = 0;
    while (indeg[U(v)] == 0) ++v;
    Vec seen_at(U(g.n), -1), walk;
    while (seen_at[U(v)] == -1) seen_at[U(v)] = static_cast<int>(walk.size()), walk.push_back(v), v = pred[U(v)];
    Vec cycle(walk.begin() + seen_at[U(v)], walk.end());
    std::ranges::reverse(cycle);  // walked backwards along edges
    return Cycle{cycle};
}

bool is_valid_order(const Graph& g, const Vec& order) {
    Vec at(U(g.n));
    for (std::size_t i = 0; i < order.size(); ++i) at[U(order[i])] = static_cast<int>(i);
    for (int u = 0; u < g.n; ++u)
        for (auto e = g.begin(u); e < g.end(u); ++e)
            if (at[U(u)] >= at[U(g.to[e])]) return false;
    return true;
}

bool is_cycle(const Graph& g, const Vec& c) {
    if (c.empty()) return false;
    for (std::size_t i = 0; i < c.size(); ++i) {
        int u = c[i], v = c[(i + 1) % c.size()];
        bool edge = false;
        for (auto e = g.begin(u); e < g.end(u); ++e) edge = edge || g.to[e] == v;
        if (!edge) return false;
    }
    return true;
}

// ======================================================================= 2. Tarjan SCC, iterative
Vec tarjan_scc(const Graph& g) {
    int n = g.n, timer = 0, comps = 0;
    Vec index(U(n), -1), low(U(n)), comp(U(n)), stack, call_v;
    std::vector<std::size_t> call_e;
    std::vector<bool> on_stack(U(n));
    for (int s = 0; s < n; ++s) {
        if (index[U(s)] != -1) continue;
        call_v.push_back(s), call_e.push_back(g.begin(s));
        index[U(s)] = low[U(s)] = timer++, stack.push_back(s), on_stack[U(s)] = true;
        while (!call_v.empty()) {
            int u = call_v.back();
            if (call_e.back() < g.end(u)) {
                int v = g.to[call_e.back()++];
                if (index[U(v)] == -1) {  // "recurse"
                    index[U(v)] = low[U(v)] = timer++, stack.push_back(v), on_stack[U(v)] = true;
                    call_v.push_back(v), call_e.push_back(g.begin(v));
                } else if (on_stack[U(v)]) {
                    low[U(u)] = std::min(low[U(u)], index[U(v)]);
                }
                continue;
            }
            call_v.pop_back(), call_e.pop_back();  // "return" from u
            if (low[U(u)] == index[U(u)]) {
                int v;
                do {
                    v = stack.back();
                    stack.pop_back();
                    on_stack[U(v)] = false;
                    comp[U(v)] = comps;
                } while (v != u);
                ++comps;
            }
            if (!call_v.empty()) low[U(call_v.back())] = std::min(low[U(call_v.back())], low[U(u)]);
        }
    }
    return comp;
}

std::vector<std::vector<bool>> reach(const Graph& g) {
    std::vector<std::vector<bool>> r(U(g.n), std::vector<bool>(U(g.n)));
    for (int s = 0; s < g.n; ++s) {
        Vec q{s};
        r[U(s)][U(s)] = true;
        for (std::size_t h = 0; h < q.size(); ++h)
            for (auto e = g.begin(q[h]); e < g.end(q[h]); ++e)
                if (!r[U(s)][U(g.to[e])]) r[U(s)][U(g.to[e])] = true, q.push_back(g.to[e]);
    }
    return r;
}

// ======================================================================= 3. bridges and articulation points
struct BridgesAndCuts {
    std::vector<bool> bridge, cut;
};

// low-link over edge ids: skip the EDGE we came in on, not the parent VERTEX, so parallel edges are not bridges.
BridgesAndCuts bridges_and_cuts(const Graph& g, std::size_t m, bool skip_parent_vertex) {
    int n = g.n, timer = 0;
    Vec tin(U(n), -1), low(U(n)), via_edge(U(n), -1), parent(U(n), -1), children(U(n)), call_v;
    std::vector<std::size_t> call_e;
    BridgesAndCuts out{std::vector<bool>(m), std::vector<bool>(U(n))};
    for (int s = 0; s < n; ++s) {
        if (tin[U(s)] != -1) continue;
        tin[U(s)] = low[U(s)] = timer++;
        call_v.push_back(s), call_e.push_back(g.begin(s));
        while (!call_v.empty()) {
            int u = call_v.back();
            if (call_e.back() < g.end(u)) {
                std::size_t slot = call_e.back()++;
                int v = g.to[slot], id = g.edge_id[slot];
                if (skip_parent_vertex ? v == parent[U(u)] : id == via_edge[U(u)]) continue;
                if (tin[U(v)] == -1) {
                    tin[U(v)] = low[U(v)] = timer++;
                    parent[U(v)] = u, via_edge[U(v)] = id, ++children[U(u)];
                    call_v.push_back(v), call_e.push_back(g.begin(v));
                } else {
                    low[U(u)] = std::min(low[U(u)], tin[U(v)]);
                }
                continue;
            }
            call_v.pop_back(), call_e.pop_back();
            int p = parent[U(u)];
            if (p != -1) {
                low[U(p)] = std::min(low[U(p)], low[U(u)]);
                if (low[U(u)] > tin[U(p)]) out.bridge[U(via_edge[U(u)])] = true;  // nothing below u climbs over (p,u)
                if (parent[U(p)] != -1 && low[U(u)] >= tin[U(p)]) out.cut[U(p)] = true;  // u's subtree hangs only on p
            } else if (children[U(u)] > 1) {
                out.cut[U(u)] = true;  // a root with 2+ DFS children
            }
        }
    }
    return out;
}

int components(int n, const Vec& from, const Vec& to, int skip_edge, int skip_vertex) {
    Vec p(U(n));
    for (int i = 0; i < n; ++i) p[U(i)] = i;
    int comps = n - (skip_vertex >= 0 ? 1 : 0);
    for (std::size_t e = 0; e < from.size(); ++e) {
        if (static_cast<int>(e) == skip_edge || from[e] == skip_vertex || to[e] == skip_vertex) continue;
        int a = from[e], b = to[e];
        while (p[U(a)] != a) a = p[U(a)] = p[U(p[U(a)])];
        while (p[U(b)] != b) b = p[U(b)] = p[U(p[U(b)])];
        if (a != b) p[U(a)] = b, --comps;
    }
    return comps;
}

bool isolated(int v, const Vec& uf, const Vec& ut) {
    for (std::size_t e = 0; e < uf.size(); ++e)
        if (uf[e] == v || ut[e] == v) return false;
    return true;
}

// ======================================================================= Extension A: run a DAG of tasks in parallel
double busy_work(int units) {
    double x = 0;
    for (int i = 0; i < units; ++i) x += std::sqrt(i + 1.0);
    return x;
}
std::atomic<std::uint64_t> g_sink{0};

// Workers pull ready tasks from one queue; a finishing task decrements its successors' in-degrees and enqueues
// those that reach 0. Returns the number of dependency violations (a successor that started before a predecessor ended).
long run_dag(const Graph& dag, int threads, int units) {
    std::vector<std::atomic<int>> indeg(U(dag.n));
    for (int v : dag.to) indeg[U(v)].fetch_add(1, std::memory_order_relaxed);
    std::vector<long> started(U(dag.n)), finished(U(dag.n));
    std::atomic<long> clock{0};
    std::mutex mu;
    std::condition_variable cv;
    std::deque<int> ready;
    int completed = 0;
    for (int v = 0; v < dag.n; ++v)  // the whole initial ready set is collected before any worker starts
        if (indeg[U(v)].load() == 0) ready.push_back(v);
    {
        std::vector<std::jthread> pool;
        for (int t = 0; t < threads; ++t)
            pool.emplace_back([&] {
                while (true) {
                    int v;
                    {
                        std::unique_lock lock(mu);
                        cv.wait(lock, [&] { return !ready.empty() || completed == dag.n; });
                        if (ready.empty()) return;
                        v = ready.front();
                        ready.pop_front();
                    }
                    started[U(v)] = ++clock;
                    g_sink.fetch_add(static_cast<std::uint64_t>(busy_work(units)), std::memory_order_relaxed);
                    finished[U(v)] = ++clock;
                    Vec now_ready;
                    for (auto e = dag.begin(v); e < dag.end(v); ++e)
                        if (indeg[U(dag.to[e])].fetch_sub(1) == 1) now_ready.push_back(dag.to[e]);
                    {
                        std::scoped_lock lock(mu);
                        ready.insert(ready.end(), now_ready.begin(), now_ready.end());
                        ++completed;
                    }
                    cv.notify_all();
                }
            });
    }
    long violations = 0;
    for (int u = 0; u < dag.n; ++u)
        for (auto e = dag.begin(u); e < dag.end(u); ++e) violations += finished[U(u)] > started[U(dag.to[e])];
    return violations;
}

int main() {
    SplitMix64 r{91};
    constexpr int trials = 3'000;
    int ok_topo = 0, cycles = 0, ok_scc = 0, ok_bridge = 0, ok_cut = 0, cp_bridge = 0;
    for (int t = 0; t < trials; ++t) {
        int n = 1 + r.next_int(10), m = r.next_int(2 * n + 1);
        Vec f(U(m)), to(U(m));
        for (std::size_t e = 0; e < U(m); ++e) {
            f[e] = r.next_int(n);
            to[e] = r.next_int(n);
        }
        Graph g(n, f, to, false);
        auto rc = reach(g);
        bool acyclic = true;
        for (std::size_t u = 0; u < U(n); ++u)
            for (std::size_t v = 0; v < U(n); ++v)
                if (u != v && rc[u][v] && rc[v][u]) acyclic = false;
        for (int u = 0; u < n; ++u)
            for (auto e = g.begin(u); e < g.end(u); ++e)
                if (g.to[e] == u) acyclic = false;
        bool ok = std::visit([&](const auto& res) {
            if constexpr (std::is_same_v<std::decay_t<decltype(res)>, Order>) return acyclic && is_valid_order(g, res.vertices);
            else return !acyclic && is_cycle(g, res.vertices);
        }, topo_sort(g));
        ok_topo += ok;
        cycles += !acyclic;
        Vec comp = tarjan_scc(g);
        bool scc_ok = true;
        for (std::size_t u = 0; u < U(n); ++u)
            for (std::size_t v = 0; v < U(n); ++v) scc_ok = scc_ok && (comp[u] == comp[v]) == (rc[u][v] && rc[v][u]);
        ok_scc += scc_ok;
        Vec uf(U(m)), ut(U(m));
        for (std::size_t e = 0; e < U(m); ++e) {
            uf[e] = r.next_int(n);
            ut[e] = r.next_int(n);
            if (uf[e] == ut[e]) ut[e] = (ut[e] + 1) % n;
        }
        if (n == 1) uf.clear(), ut.clear();
        Graph ug(n, uf, ut, true);
        auto bc = bridges_and_cuts(ug, uf.size(), false), cp_bc = bridges_and_cuts(ug, uf.size(), true);
        int base = components(n, uf, ut, -1, -1);
        bool b_ok = true, cp_ok = true, c_ok = true;
        for (std::size_t e = 0; e < uf.size(); ++e) {
            bool truth = components(n, uf, ut, static_cast<int>(e), -1) > base;
            b_ok = b_ok && bc.bridge[e] == truth;
            cp_ok = cp_ok && cp_bc.bridge[e] == truth;
        }
        for (int v = 0; v < n; ++v) c_ok = c_ok && bc.cut[U(v)] == (components(n, uf, ut, -1, v) > base - (isolated(v, uf, ut) ? 1 : 0));
        ok_bridge += b_ok, cp_bridge += cp_ok, ok_cut += c_ok;
    }
    std::println("random graphs, n <= 10 ({} trials, {} with a cycle) vs reachability / remove-and-recount oracles:", trials, cycles);
    std::println("   Kahn: valid lexicographic order, or a VERIFIED cycle witness  {}/{}", ok_topo, trials);
    std::println("   iterative Tarjan SCC == mutual reachability                   {}/{}", ok_scc, trials);
    std::println("   bridges, skipping the parent EDGE id                          {}/{}", ok_bridge, trials);
    std::println("   bridges, skipping the parent VERTEX (contest habit)           {}/{}", cp_bridge, trials);
    std::println("   articulation points                                           {}/{}", ok_cut, trials);
    Graph multi(2, {0, 0}, {1, 1}, true);
    std::println("   two parallel edges 0-1: edge-id rule says bridge={}, vertex rule says bridge={}",
                 static_cast<bool>(bridges_and_cuts(multi, 2, false).bridge[0]), static_cast<bool>(bridges_and_cuts(multi, 2, true).bridge[0]));
    auto c = topo_sort(Graph(4, {0, 1, 2, 3}, {1, 2, 1, 0}, false));
    std::string cs;
    for (int v : std::get<Cycle>(c).vertices) cs += (cs.empty() ? "" : ", ") + std::to_string(v);
    std::println("   topo_sort(0->1->2->1, 3->0) -> Cycle[vertices=[{}]]", cs);

    constexpr int n = 1 << 20;
    Vec f(U(n - 1)), t(U(n - 1));
    for (int v = 1; v < n; ++v) f[U(v - 1)] = v - 1, t[U(v - 1)] = v;
    using clock = std::chrono::steady_clock;
    auto ms = [](clock::duration d) { return std::chrono::duration_cast<std::chrono::milliseconds>(d).count(); };
    auto t0 = clock::now();
    Vec comp = tarjan_scc(Graph(n, f, t, false));
    std::println("   iterative Tarjan on a {}-vertex path: {} ms, {} components, no recursion", n, ms(clock::now() - t0),
                 *std::ranges::max_element(comp) + 1);

    constexpr int tasks = 2'000, units = 20'000;
    Vec df(3 * tasks), dt(3 * tasks);
    for (std::size_t e = 0; e < df.size(); ++e) {
        int a = r.next_int(tasks), b = r.next_int(tasks);
        if (a == b) b = (b + 1) % tasks;
        df[e] = std::min(a, b), dt[e] = std::max(a, b);  // edges go from lower to higher id: acyclic by construction
    }
    Graph dag(tasks, df, dt, false);
    Vec longest(U(tasks));
    for (int u = 0; u < tasks; ++u)
        for (auto e = dag.begin(u); e < dag.end(u); ++e) longest[U(dag.to[e])] = std::max(longest[U(dag.to[e])], longest[U(u)] + 1);
    auto s0 = clock::now();
    long v1 = run_dag(dag, 1, units);
    auto s1 = clock::now();
    long v8 = run_dag(dag, 8, units);
    auto s2 = clock::now();
    std::println("A. DAG of {} tasks / {} edges, critical path {} tasks (one measured run): 1 thread {} ms | 8 threads {} ms |"
                 " dependency violations {} and {}", tasks, df.size(), *std::ranges::max_element(longest) + 1, ms(s1 - s0),
                 ms(s2 - s1), v1, v8);
}
```

**Output, GCC 16.2 (verified; timing lines are one measured run):**

```text
random graphs, n <= 10 (3000 trials, 2066 with a cycle) vs reachability / remove-and-recount oracles:
   Kahn: valid lexicographic order, or a VERIFIED cycle witness  3000/3000
   iterative Tarjan SCC == mutual reachability                   3000/3000
   bridges, skipping the parent EDGE id                          3000/3000
   bridges, skipping the parent VERTEX (contest habit)           2173/3000
   articulation points                                           3000/3000
   two parallel edges 0-1: edge-id rule says bridge=false, vertex rule says bridge=true
   topo_sort(0->1->2->1, 3->0) -> Cycle[vertices=[2, 1]]
   iterative Tarjan on a 1048576-vertex path: 26 ms, 1048576 components, no recursion
A. DAG of 2000 tasks / 6000 edges, critical path 16 tasks (one measured run): 1 thread 61 ms | 8 threads 11 ms | dependency violations 0 and 0
```

**Output, Clang 21.1 (verified; timing lines are one measured run):**

```text
random graphs, n <= 10 (3000 trials, 2066 with a cycle) vs reachability / remove-and-recount oracles:
   Kahn: valid lexicographic order, or a VERIFIED cycle witness  3000/3000
   iterative Tarjan SCC == mutual reachability                   3000/3000
   bridges, skipping the parent EDGE id                          3000/3000
   bridges, skipping the parent VERTEX (contest habit)           2173/3000
   articulation points                                           3000/3000
   two parallel edges 0-1: edge-id rule says bridge=false, vertex rule says bridge=true
   topo_sort(0->1->2->1, 3->0) -> Cycle[vertices=[2, 1]]
   iterative Tarjan on a 1048576-vertex path: 30 ms, 1048576 components, no recursion
A. DAG of 2000 tasks / 6000 edges, critical path 16 tasks (one measured run): 1 thread 59 ms | 8 threads 11 ms | dependency violations 0 and 0
```

---

## 3. What the results show

* **Every cycle claim is checked, not trusted.** In 3,000 random directed graphs, 2,066 of them cyclic, Kahn returned either a valid order (checked edge by edge) or a cycle whose consecutive vertices are verified to be joined by edges. A Java `switch` over the sealed `TopoResult` must handle both cases, or the compiler rejects it; `std::visit` plays the same role in C++. For `0→1→2→1, 3→0` the witness is `[2, 1]`.
* **Tarjan equals mutual reachability** on every random graph, and handles a 1,048,576-vertex path in 26–64 ms with no recursion.
* **Bridges and articulation points** match the remove-and-recount oracle on all 3,000 multigraphs. The parent-vertex variant fails 27% of them.
* **The DAG executor's first version had a race,** found by its own invariant check. The main thread scheduled the initial in-degree-0 tasks *while* workers were already finishing tasks and decrementing in-degrees. A vertex released by a fast worker was then also seen with in-degree 0 by the main loop and **ran twice**: 2,002 executions for 2,000 tasks, 25 dependency violations, and `RejectedExecutionException`s as late tasks hit a shut-down pool. The fix is to snapshot the initial ready set before submitting anything. The C++ version builds it before starting any worker, by construction. With the fix: 0 violations, and 8 threads run 2,000 tasks with a 16-task critical path in 10–20 ms against 57–64 ms for one thread.

---

## 4. The last 10 minutes: Extensions A, B and C

### 4.1 Extension A — "execute the DAG on 64 threads"

That is the build-system and workflow-engine question. The design measured above:

1. Atomic in-degree per task; the initial ready set is snapshotted before any worker starts.
2. A finishing task decrements each successor and enqueues those that reach 0. The decrement to 0 happens exactly once per task, which is what makes the hand-off safe.
3. Completion is counted, not inferred from an empty queue: the queue can be empty while tasks are still running.

Speedup is bounded by the **critical path**: total work / threads ≤ makespan ≥ critical-path work (Graham's bound for list scheduling). Here the critical path was 16 tasks deep out of 2,000, so 8 threads reached 3–6×. Mention priority (longest remaining path first) for critical-path-heavy DAGs, and **cancellation** (a failed task cancels its descendants), and you have a production scheduler.

### 4.2 Extension B — "the dependency graph streams in"

* **Online cycle detection:** maintain a topological order incrementally as edges arrive and reject the edge that would close a cycle. Simple approach: on edge u→v where `order[u] > order[v]`, search forward from v within the affected range (Pearce–Kelly style algorithms bound the work to the affected region). That is how a database detects deadlock in a wait-for graph as lock requests arrive.
* **Streaming bridges** in bounded memory: a spanning forest plus a DSU over 2-edge-connected components, updated per edge, without keeping all edges. Semi-streaming algorithms do this in O(V log V) bits.
* **Huge graphs on disk:** SCC via forward-backward reachability. Pick a pivot, compute its forward and backward reachable sets with external BFS (File 1); their intersection is one SCC, and the three remainders recurse. It works well on real graphs, which have one giant SCC.

### 4.3 Extension C — "the graph spans 100 machines"

* **Topological levels in BSP:** each superstep removes all in-degree-0 vertices everywhere and sends decrement messages across partitions. Supersteps equal the DAG depth. Cycle detection falls out when no vertex has in-degree 0 but some remain.
* **Distributed SCC:** forward-backward with label propagation, or "coloring" algorithms (propagate max ids forward, then backward from roots), in O(diameter) supersteps per round.
* **Single points of failure across data centres:** bridges and articulation points of the service dependency graph. Compute them on the condensed topology (data centres and inter-DC links as one graph, small enough for one machine), not on the full instance graph. Choosing the right level of abstraction is the Staff answer.

---

## 5. Failure modes

| # | Failure | Symptom | Prevention |
|---|---|---|---|
| F1 | Boolean "has cycle" | Users can't find the cycle | Return a witness; verify it in tests |
| F2 | Non-deterministic topological order | Flaky builds and tests | Min-heap ready set (or another total order), documented |
| F3 | Recursive DFS / Tarjan | Stack overflow on long chains | Explicit frames (vertex, next edge) |
| F4 | Skipping the parent vertex | Parallel edges reported as bridges | Skip the arriving edge id |
| F5 | Root articulation rule forgotten | Root misclassified | Root is a cut vertex iff ≥ 2 DFS children |
| F6 | Scheduling roots while workers run | Tasks run twice; dependency violations | Snapshot the ready set before starting |
| F7 | "Queue empty" as completion | Premature shutdown while tasks run | Count completions |
| F8 | Analysing the full instance graph for SPOFs | Too big; noisy | Condense to the meaningful topology (SCCs, data centres) |

---

## 6. Bar-raiser chains

<details><summary><b>Q1 · "Order these build targets; detect cycles."</b></summary>

**Initial Prompt.** LeetCode 210-style with a build-system framing.

**L5 Answer.** Kahn's algorithm, return an empty list if a cycle exists.

**Why L5 Stalls.** An empty list tells the user nothing, and the order varies between runs if the ready set is a plain queue over a hash map.

**L7 Answer.** "Kahn with a min-heap, so the order is deterministic: the lexicographically smallest valid order. If vertices remain, every remaining one has a remaining predecessor, so walking predecessors must repeat a vertex, and that repeated segment is a cycle I return as the error: '`app` → `lib` → `app`'. I'd model the result as a sealed type, Order or Cycle, so callers must handle both."
</details>

<details><summary><b>Q2 · "Find the strongly connected components of a 10⁶-node graph."</b></summary>

**Initial Prompt.** Tarjan or Kosaraju.

**L5 Answer.** Recursive Tarjan.

**Why L5 Stalls.** Recursion depth equals the DFS depth, up to 10⁶ on a chain.

**L7 Answer.** "Tarjan with an explicit stack of (vertex, next-edge) frames: 'recursing' pushes a frame, and 'returning' pops it and folds low into the parent. A vertex whose low equals its index roots a component; pop the SCC stack down to it. Components come out in reverse topological order of the condensation, which I can use directly for 2-SAT or dependency analysis. The listing runs a 1 M-vertex path in tens of milliseconds."
</details>

<details><summary><b>Q3 · "Which links are single points of failure in this network?"</b></summary>

**Initial Prompt.** Bridges (LeetCode 1192, "critical connections").

**L5 Answer.** Tarjan's bridge algorithm, skipping the parent vertex.

**Why L5 Stalls.** Networks have redundant parallel links, and skipping the parent vertex reports them as critical. Wrong on 27% of random multigraphs.

**L7 Answer.** "Low-link DFS: a tree edge (p, u) is a bridge iff nothing in u's subtree has a back edge to p or above, so `low[u] > tin[p]`. To ignore only the edge I arrived by, I skip its *id*, not the parent vertex. Two parallel links are then correctly not a bridge. For failing nodes rather than links, the same pass gives articulation points: a child with `low ≥ tin[p]`, or a root with two or more DFS children."
</details>

<details><summary><b>Q4 · "Run the tasks of this DAG as fast as possible on 64 cores."</b></summary>

**Initial Prompt.** Extension A.

**L5 Answer.** "Topologically sort, then run in that order with a thread pool."

**Why L5 Stalls.** A topological order is a total order; running it sequentially or level by level wastes parallelism and waits on stragglers.

**L7 Answer.** "Event-driven: an atomic in-degree per task, and a finishing task decrements its successors and enqueues any that hit 0. Exactly one decrement takes a task to 0, so it's scheduled exactly once. Two subtleties I've seen bite: snapshot the initial ready set before workers start (my first version double-ran tasks), and detect completion by counting finished tasks, not by an empty queue. Speedup is capped by the critical path, so I'd prioritize tasks on the longest remaining path."
</details>

<details><summary><b>Q5 · "Two parallel cables connect A and B. Is either a bridge?"</b></summary>

**Initial Prompt.** The probe after the candidate's bridge solution.

**L5 Answer.** "Yes, removing one leaves A and B connected... wait, my code says it's a bridge."

**Why L5 Stalls.** The code skipped the parent vertex, so the second cable was never seen as a back edge.

**L7 Answer.** "Neither is a bridge. My DFS skips only the edge *id* it arrived on, so the second cable counts as a back edge, `low[B] ≤ tin[A]`, and neither edge qualifies. I'd keep that exact multigraph as a unit test: it's the case parent-vertex code gets wrong."
</details>

<details><summary><b>Q6 · "Dependencies arrive one at a time; reject one that creates a cycle."</b></summary>

**Initial Prompt.** Extension B: online cycle detection.

**L5 Answer.** "Re-run topological sort after each edge."

**Why L5 Stalls.** O(V + E) per edge.

**L7 Answer.** "Maintain a topological order incrementally. A new edge u→v that already respects the order (u before v) is free. If it doesn't, only the region between v's and u's positions can be affected, so I search forward from v within that window. If I reach u, the edge closes a cycle and I reject it with the path as evidence; otherwise I reorder the affected vertices. That's the Pearce–Kelly approach, and the same check a lock manager runs on its wait-for graph."
</details>

<details><summary><b>Q7 · "SCCs of a web-scale graph across many machines."</b></summary>

**Initial Prompt.** Extension C.

**L5 Answer.** "Run Tarjan on each machine."

**Why L5 Stalls.** Components span machines; local Tarjan sees only fragments.

**L7 Answer.** "Forward-backward. Pick a pivot, compute its forward and backward reachable sets with distributed BFS; their intersection is one SCC, and the remaining three parts are independent subproblems. Real web graphs have one giant SCC, so the first pivot removes most of the graph. Each BFS is BSP supersteps over partitions, with traffic proportional to cut edges."
</details>

<details><summary><b>Q8 · "Why is your topological order different from mine?"</b></summary>

**Initial Prompt.** The interviewer's expected output differs.

**L5 Answer.** "Both are valid."

**Why L5 Stalls.** True, but it shows the candidate didn't consider determinism or ask about the expected order.

**L7 Answer.** "Both are valid orders, but a contract should pick one. I use a min-heap for the ready set, which gives the lexicographically smallest order, so the output is reproducible and testable. If you need a different tie rule, like priority or longest path first, it's just a different comparator on the ready set."
</details>

---

## 7. Checklist

* [ ] Kahn with a deterministic ready set; return `Order | Cycle` and verify the witness.
* [ ] All DFS iterative: explicit (vertex, next-edge) frames.
* [ ] Tarjan: `low == index` roots an SCC; components in reverse topological order.
* [ ] Bridges `low[u] > tin[p]`; articulation `low[u] ≥ tin[p]`; root rule; skip by edge id.
* [ ] Test multigraphs and self-loops explicitly.
* [ ] Extension A: atomic in-degrees, snapshot roots, count completions, critical-path priority.
* [ ] Extension B: incremental topological order; forward-backward SCC on disk.
* [ ] Extension C: BSP levels; forward-backward SCC; analyse condensed topologies.

---

## 8. References

* A. B. Kahn, *Topological sorting of large networks*, CACM 5(11), 1962 — DOI 10.1145/368996.369025
* R. E. Tarjan, *Depth-First Search and Linear Graph Algorithms*, SIAM J. Computing 1(2), 1972 — DOI 10.1137/0201010
* D. J. Pearce, P. H. J. Kelly, *A Dynamic Topological Sort Algorithm for Directed Acyclic Graphs*, ACM JEA 11, 2006 — DOI 10.1145/1187436.1210590
* L. K. Fleischer, B. Hendrickson, A. Pınar, *On Identifying Strongly Connected Components in Parallel*, IPDPS Workshops 2000 — DOI 10.1007/3-540-45591-4_68
* R. L. Graham, *Bounds on Multiprocessing Timing Anomalies*, SIAM J. Applied Math 17(2), 1969 — DOI 10.1137/0117039
* cp-algorithms: [Topological sort](https://cp-algorithms.com/graph/topological-sort.html), [Bridges](https://cp-algorithms.com/graph/bridge-searching.html), [Articulation points](https://cp-algorithms.com/graph/cutpoints.html), [SCC](https://cp-algorithms.com/graph/strongly-connected-components.html)
* LeetCode anchors: [207 Course Schedule](https://leetcode.com/problems/course-schedule/), [210 Course Schedule II](https://leetcode.com/problems/course-schedule-ii/), [1192 Critical Connections in a Network](https://leetcode.com/problems/critical-connections-in-a-network/)

*Folder 04:* [01 — 0-1 BFS, Dijkstra, Bellman–Ford](01-01-bfs-multi-source-dijkstra-state-space-graphs-and-bellman-ford.md) · [03 — DSU, matching, min-cut](03-disjoint-set-union-dsu-with-rollback-bipartite-matching-and-min-cut.md)
