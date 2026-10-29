# 0-1 BFS, Multi-Source BFS, Dijkstra, State-Space Graphs and Bellman–Ford

> **Folder 04 · File 1 of 3** — the shortest-path family as one idea (relax edges in an order that makes distances final), the two contest bugs that pass most tests, the "state is not the vertex" trap of LeetCode 787, and level-synchronous parallel BFS.
> **Languages:** Java 21 (`--release 21 -Xlint:all -Werror`, JDK 25.0.4.1) and C++23 (GCC 16.2 and Clang 21.1, `-O2`, warnings as errors).

| Listing | File | What it proves |
|---|---|---|
| 4.1 | `ShortestPaths.java` | Validated CSR graph; 0-1 BFS with a primitive deque; multi-source BFS; Dijkstra with an allocation-free indexed heap vs the visited-on-push contest version; LeetCode 787's two classic bugs; Bellman–Ford returning `null` on a reachable negative cycle. 3,000 random graphs against Floyd–Warshall and path enumeration; parallel BFS on 2 M vertices / 16 M edges |
| 4.2 | `shortest_paths.cpp` | The same with `std::optional` for "no answer"; identical correctness counts; the int-overflow demo is not run (UB) |

**Verification.** Both listings were extracted from this file, compiled and run. Everything is **Output (verified)** except the parallel-BFS line (**one measured run**).

---

## 0. Orientation

| Contest habit | What breaks | L7 replacement |
|---|---|---|
| `vector<vector<pair<int,int>>> adj` | Pointer-chasing, one allocation per vertex | CSR: `start[]`, `to[]`, `w[]`: two contiguous arrays (Folder 01 File 2) |
| `int dist[]`, `INF = 1e9` | Overflow on sums of large weights (3 × 10⁹ → −1,294,967,296) | `long` / `int64` distances, `INF = MAX/4` so `INF + w` can't overflow |
| Mark visited when **pushed** | Wrong distances on 18% of random graphs | A vertex is final only when **popped** (or settled) |
| `priority_queue<pair>` with duplicates | O(E log E) memory and garbage | Indexed heap with decrease-key: ≤ V entries, no allocation per relaxation |
| Dijkstra on any weights | Silently wrong with negative edges | Validate: reject negative weights; Bellman–Ford with negative-cycle detection when they are allowed |
| Dijkstra with one `visited` per city under a stop limit | Wrong in a small fraction of cases (2 of 3,000 here) | The state is (city, stops used): search the state space, or snapshot Bellman–Ford |

---

## 1. First principles

### 1.1 One idea, four algorithms

Every shortest-path algorithm here repeatedly **relaxes** an edge (`dist[v] = min(dist[v], dist[u] + w)`). They differ only in the **order** of relaxation and in when a distance becomes **final**:

| Algorithm | Edge weights | Order | When `dist[v]` is final | Cost |
|---|---|---|---|---|
| BFS | all 1 | FIFO queue by layer | When first reached | O(V + E) |
| 0-1 BFS | 0 or 1 | Deque: 0-edges to the front, 1-edges to the back | When popped | O(V + E) |
| Dijkstra | ≥ 0 | Min-heap by tentative distance | When popped | O((V + E) log V) |
| Bellman–Ford | any | Every edge, V − 1 rounds | After round k: every path of ≤ k edges is accounted for | O(V E) |

**Why Dijkstra's popped distances are final:** when u is popped with distance d, every other tentative distance is ≥ d. Any other path to u must leave the settled set through some vertex with tentative distance ≥ d and then add **non-negative** edges, so it can't be shorter. One negative edge breaks that argument, which is why the production version validates its input.

**Why "visited when pushed" is wrong:** a vertex can be pushed with a large tentative distance, via a long path discovered first, and later be reachable more cheaply. Marking it visited at push time forbids the later improvement. The listing's contest version failed on 18% of random graphs (2,456 of 3,000 correct), while passing any sample where the first discovered path is the shortest.

### 1.2 Multi-source and 0-1 BFS

**Multi-source BFS** answers "distance to the nearest of several sources" (nearest hospital, nearest exit, Dijkstra's "virtual super-source") in one pass: seed the queue with every source at distance 0. **0-1 BFS** handles graphs whose edges cost 0 or 1, such as "flip a direction for cost 1, follow it for free" (LeetCode 1368). A deque keeps the queue sorted by distance with at most two distinct values, so it does Dijkstra's job without a heap.

### 1.3 The state is not always the vertex

LeetCode 787 (cheapest flight with at most k stops) is where pattern-matching on "shortest path → Dijkstra" fails. The constraint makes the **state** `(city, edges used)`, not `city`. Two correct designs:

1. **Bellman–Ford with snapshots:** k + 1 rounds, each reading only the *previous* round's distances, so round i accounts for exactly paths of ≤ i edges. Relaxing **in place** lets one round chain several edges and silently exceed the limit (2,884 of 3,000 correct here).
2. **Dijkstra over states:** settle `(city, edges)` pairs. One `done` flag **per city** is wrong when the cheapest arrival at a city used too many stops, blocking a slightly more expensive arrival with stops to spare. That failed 2 of 3,000 random graphs: exactly the kind of bug a test suite misses.

The general rule, worth saying in an interview: *identify the state that makes the problem memoryless; the graph is over states, and its size is the product of the dimensions.*

### 1.4 Bellman–Ford and negative cycles

With negative edges, "shortest" exists only if no negative cycle is **reachable from the source** (and on a path to the target). Bellman–Ford runs up to V − 1 rounds. If round V still improves something, a reachable negative cycle exists. The production API makes that outcome explicit: `null` in Java, `std::nullopt` in C++, or a sealed result type, never a "distance" that is merely the value after V − 1 rounds.

---

## 2. The listings

### 2.1 Listing 4.1 — Java

```java
// ShortestPaths.java - CSR graphs, 0-1 BFS, Dijkstra with an indexed heap, state-space search, Bellman-Ford, parallel BFS.
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.PriorityQueue;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicIntegerArray;

public final class ShortestPaths {

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

    static final long INF = Long.MAX_VALUE / 4;

    /** Directed graph in compressed sparse row form: edges of u are [start[u], start[u+1]). Immutable. */
    static final class Graph {
        final int n;
        final int[] start, to, w;

        Graph(int n, int[] from, int[] to, int[] w) {
            if (from.length != to.length || to.length != w.length) throw new IllegalArgumentException("edge arrays differ in length");
            this.n = n;
            start = new int[n + 1];
            for (int u : from) {
                if (u < 0 || u >= n) throw new IllegalArgumentException("vertex out of range: " + u);
                start[u + 1]++;
            }
            for (int v : to) if (v < 0 || v >= n) throw new IllegalArgumentException("vertex out of range: " + v);
            for (int i = 0; i < n; i++) start[i + 1] += start[i];
            int[] fill = Arrays.copyOf(start, n), t = new int[to.length], ww = new int[to.length];
            for (int e = 0; e < from.length; e++) { int k = fill[from[e]]++; t[k] = to[e]; ww[k] = w[e]; }
            this.to = t;
            this.w = ww;
        }
    }

    // ===================================================================== 0-1 BFS and multi-source BFS
    /** Weights 0 or 1: a deque replaces the heap. 0-edges go to the front, 1-edges to the back. O(V + E). */
    static long[] bfs01(Graph g, int src) {
        for (int x : g.w) if (x != 0 && x != 1) throw new IllegalArgumentException("0-1 BFS needs weights in {0, 1}, got " + x);
        long[] dist = new long[g.n];
        Arrays.fill(dist, INF);
        int cap = 2 * (g.to.length + g.n) + 2, head = cap / 2, tail = cap / 2;  // each relaxation pushes once
        int[] dq = new int[cap];
        dist[src] = 0;
        dq[tail++] = src;
        while (head < tail) {
            int u = dq[head++];
            for (int e = g.start[u]; e < g.start[u + 1]; e++) {
                int v = g.to[e];
                long nd = dist[u] + g.w[e];
                if (nd < dist[v]) {
                    dist[v] = nd;
                    if (g.w[e] == 0) dq[--head] = v; else dq[tail++] = v;
                }
            }
        }
        return dist;
    }

    /** Distance from the NEAREST of several sources: seed the queue with all of them at distance 0. One O(V + E) pass. */
    static int[] multiSourceBfs(Graph g, int[] sources) {
        int[] dist = new int[g.n], q = new int[g.n];
        Arrays.fill(dist, -1);
        int head = 0, tail = 0;
        for (int s : sources) if (dist[s] == -1) { dist[s] = 0; q[tail++] = s; }
        while (head < tail) {
            int u = q[head++];
            for (int e = g.start[u]; e < g.start[u + 1]; e++) if (dist[g.to[e]] == -1) { dist[g.to[e]] = dist[u] + 1; q[tail++] = g.to[e]; }
        }
        return dist;
    }

    // ===================================================================== Dijkstra
    /** Binary min-heap over vertex ids with decrease-key: no allocation per relaxation, at most V entries. */
    static final class IndexedMinHeap {
        private final int[] heap, pos;
        private final long[] key;
        private int size;

        IndexedMinHeap(int n) {
            heap = new int[n];
            pos = new int[n];
            key = new long[n];
            Arrays.fill(pos, -1);
        }
        boolean isEmpty() { return size == 0; }
        void pushOrDecrease(int v, long k) {
            if (pos[v] == -1) { heap[size] = v; pos[v] = size++; key[v] = k; up(pos[v]); }
            else if (k < key[v]) { key[v] = k; up(pos[v]); }
        }
        int pop() {
            int top = heap[0];
            pos[top] = -2;                       // -2: settled, never re-inserted
            if (--size > 0) { heap[0] = heap[size]; pos[heap[0]] = 0; down(0); }
            return top;
        }
        boolean settled(int v) { return pos[v] == -2; }
        private void up(int i) {
            while (i > 0 && key[heap[(i - 1) / 2]] > key[heap[i]]) { swap(i, (i - 1) / 2); i = (i - 1) / 2; }
        }
        private void down(int i) {
            while (true) {
                int l = 2 * i + 1, r = l + 1, m = i;
                if (l < size && key[heap[l]] < key[heap[m]]) m = l;
                if (r < size && key[heap[r]] < key[heap[m]]) m = r;
                if (m == i) return;
                swap(i, m);
                i = m;
            }
        }
        private void swap(int a, int b) {
            int x = heap[a]; heap[a] = heap[b]; heap[b] = x;
            pos[heap[a]] = a; pos[heap[b]] = b;
        }
    }

    /** Non-negative weights required (checked). Invariant: a popped vertex's distance is final. O((V + E) log V). */
    static long[] dijkstra(Graph g, int src) {
        for (int x : g.w) if (x < 0) throw new IllegalArgumentException("Dijkstra needs non-negative weights, got " + x);
        long[] dist = new long[g.n];
        Arrays.fill(dist, INF);
        dist[src] = 0;
        IndexedMinHeap h = new IndexedMinHeap(g.n);
        h.pushOrDecrease(src, 0);
        while (!h.isEmpty()) {
            int u = h.pop();
            for (int e = g.start[u]; e < g.start[u + 1]; e++) {
                int v = g.to[e];
                long nd = dist[u] + g.w[e];
                if (nd < dist[v] && !h.settled(v)) { dist[v] = nd; h.pushOrDecrease(v, nd); }
            }
        }
        return dist;
    }

    /** Contest habits: int distances and "visited when pushed". Both pass small samples. */
    static long[] cpDijkstra(Graph g, int src) {
        int[] dist = new int[g.n];
        Arrays.fill(dist, Integer.MAX_VALUE);
        boolean[] seen = new boolean[g.n];
        PriorityQueue<int[]> pq = new PriorityQueue<>((a, b) -> a[0] != b[0] ? Integer.compare(a[0], b[0]) : Integer.compare(a[1], b[1]));
        dist[src] = 0;
        pq.add(new int[] {0, src});
        seen[src] = true;
        while (!pq.isEmpty()) {
            int[] top = pq.poll();
            int u = top[1];
            for (int e = g.start[u]; e < g.start[u + 1]; e++) {
                int v = g.to[e];
                if (!seen[v] && dist[u] + g.w[e] < dist[v]) {
                    dist[v] = dist[u] + g.w[e];
                    seen[v] = true;                                 // BUG: finalized before it is popped
                    pq.add(new int[] {dist[v], v});
                }
            }
        }
        return Arrays.stream(dist).mapToLong(d -> d == Integer.MAX_VALUE ? INF : d).toArray();
    }

    static long[][] floydWarshall(Graph g) {
        long[][] d = new long[g.n][g.n];
        for (long[] row : d) Arrays.fill(row, INF);
        for (int i = 0; i < g.n; i++) d[i][i] = 0;
        for (int u = 0; u < g.n; u++) for (int e = g.start[u]; e < g.start[u + 1]; e++) d[u][g.to[e]] = Math.min(d[u][g.to[e]], g.w[e]);
        for (int k = 0; k < g.n; k++)
            for (int i = 0; i < g.n; i++)
                for (int j = 0; j < g.n; j++)
                    if (d[i][k] < INF && d[k][j] < INF) d[i][j] = Math.min(d[i][j], d[i][k] + d[k][j]);
        return d;
    }

    // ===================================================================== LC 787: cheapest path with <= k stops
    /** Correct: k+1 rounds of Bellman-Ford, each reading the PREVIOUS round's distances (path length grows by one edge). */
    static long cheapestWithinStops(Graph g, int src, int dst, int stops) {
        long[] dist = new long[g.n];
        Arrays.fill(dist, INF);
        dist[src] = 0;
        for (int round = 0; round <= stops; round++) {
            long[] next = dist.clone();
            for (int u = 0; u < g.n; u++) {
                if (dist[u] == INF) continue;
                for (int e = g.start[u]; e < g.start[u + 1]; e++) next[g.to[e]] = Math.min(next[g.to[e]], dist[u] + g.w[e]);
            }
            dist = next;
        }
        return dist[dst];
    }

    /** Bug 1: relax in place, so one round can chain several edges and exceed the stop limit. */
    static long cheapestInPlace(Graph g, int src, int dst, int stops) {
        long[] dist = new long[g.n];
        Arrays.fill(dist, INF);
        dist[src] = 0;
        for (int round = 0; round <= stops; round++)
            for (int u = 0; u < g.n; u++)
                if (dist[u] != INF) for (int e = g.start[u]; e < g.start[u + 1]; e++) dist[g.to[e]] = Math.min(dist[g.to[e]], dist[u] + g.w[e]);
        return dist[dst];
    }

    /** Bug 2: Dijkstra with one "done" flag per CITY. The cheapest arrival may have used too many stops. */
    static long cheapestDijkstraPerCity(Graph g, int src, int dst, int stops) {
        boolean[] done = new boolean[g.n];
        PriorityQueue<long[]> pq = new PriorityQueue<>((a, b) -> Arrays.compare(a, b));  // total order: (cost, city, edges)
        pq.add(new long[] {0, src, 0});
        while (!pq.isEmpty()) {
            long[] t = pq.poll();
            int u = (int) t[1], edges = (int) t[2];
            if (u == dst) return t[0];
            if (done[u]) continue;
            done[u] = true;
            if (edges == stops + 1) continue;
            for (int e = g.start[u]; e < g.start[u + 1]; e++) pq.add(new long[] {t[0] + g.w[e], g.to[e], edges + 1});
        }
        return INF;
    }

    static long cheapestOracle(Graph g, int u, int dst, int edgesLeft) {  // enumerate every path of <= stops+1 edges
        if (u == dst) return 0;
        if (edgesLeft == 0) return INF;
        long best = INF;
        for (int e = g.start[u]; e < g.start[u + 1]; e++) {
            long rest = cheapestOracle(g, g.to[e], dst, edgesLeft - 1);
            if (rest < INF) best = Math.min(best, g.w[e] + rest);
        }
        return best;
    }

    // ===================================================================== Bellman-Ford with negative cycles
    /** Distances, or null when a negative cycle is reachable from src (then "shortest" is undefined). O(V E). */
    static long[] bellmanFord(Graph g, int src) {
        long[] dist = new long[g.n];
        Arrays.fill(dist, INF);
        dist[src] = 0;
        for (int round = 0; round < g.n; round++) {
            boolean changed = false;
            for (int u = 0; u < g.n; u++) {
                if (dist[u] == INF) continue;
                for (int e = g.start[u]; e < g.start[u + 1]; e++) {
                    if (dist[u] + g.w[e] < dist[g.to[e]]) { dist[g.to[e]] = dist[u] + g.w[e]; changed = true; }
                }
            }
            if (!changed) return dist;
            if (round == g.n - 1) return null;  // still improving after n-1 rounds: a reachable negative cycle
        }
        return dist;
    }

    static Graph randomGraph(SplitMix64 r, int n, int m, int minW, int maxW) {
        int[] f = new int[m], t = new int[m], w = new int[m];
        for (int i = 0; i < m; i++) { f[i] = r.nextInt(n); t[i] = r.nextInt(n); w[i] = minW + r.nextInt(maxW - minW + 1); }
        return new Graph(n, f, t, w);
    }

    // ===================================================================== Extension A: level-synchronous parallel BFS
    static int[] parallelBfs(Graph g, int src, int threads, ExecutorService pool) throws Exception {
        AtomicIntegerArray dist = new AtomicIntegerArray(g.n);
        for (int i = 0; i < g.n; i++) dist.set(i, -1);
        dist.set(src, 0);
        int[] frontier = {src};
        for (int level = 0; frontier.length > 0; level++) {
            final int[] f = frontier;
            final int next = level + 1;
            List<Future<int[]>> parts = new ArrayList<>();
            for (int t = 0; t < threads; t++) {
                int lo = (int) ((long) f.length * t / threads), hi = (int) ((long) f.length * (t + 1) / threads);
                parts.add(pool.submit(() -> {
                    int[] out = new int[16];
                    int k = 0;
                    for (int i = lo; i < hi; i++) {
                        int u = f[i];
                        for (int e = g.start[u]; e < g.start[u + 1]; e++) {
                            int v = g.to[e];
                            if (dist.get(v) == -1 && dist.compareAndSet(v, -1, next)) {  // exactly one thread claims v
                                if (k == out.length) out = Arrays.copyOf(out, k * 2);
                                out[k++] = v;
                            }
                        }
                    }
                    return Arrays.copyOf(out, k);
                }));
            }
            int total = 0;
            int[][] got = new int[threads][];
            for (int t = 0; t < threads; t++) total += (got[t] = parts.get(t).get()).length;
            frontier = new int[total];
            for (int t = 0, k = 0; t < threads; t++) for (int v : got[t]) frontier[k++] = v;
        }
        int[] out = new int[g.n];
        for (int i = 0; i < g.n; i++) out[i] = dist.get(i);
        return out;
    }

    public static void main(String[] args) throws Exception {
        SplitMix64 r = new SplitMix64(81);
        int trials = 3_000, okDij = 0, okCp = 0, ok01 = 0, okMulti = 0, okBf = 0, negCycles = 0;
        int ok787 = 0, okInPlace = 0, okPerCity = 0;
        for (int t = 0; t < trials; t++) {
            int n = 2 + r.nextInt(9), m = r.nextInt(3 * n);
            Graph g = randomGraph(r, n, m, 0, 9);
            long[][] fw = floydWarshall(g);
            int src = r.nextInt(n);
            okDij += Arrays.equals(dijkstra(g, src), fw[src]) ? 1 : 0;
            okCp += Arrays.equals(cpDijkstra(g, src), fw[src]) ? 1 : 0;
            Graph g01 = randomGraph(r, n, m, 0, 1);
            ok01 += Arrays.equals(bfs01(g01, src), floydWarshall(g01)[src]) ? 1 : 0;
            Graph unit = randomGraph(r, n, m, 1, 1);
            long[][] fu = floydWarshall(unit);
            int s2 = r.nextInt(n);
            int[] ms = multiSourceBfs(unit, new int[] {src, s2});
            boolean multiOk = true;
            for (int v = 0; v < n; v++) {
                long want = Math.min(fu[src][v], fu[s2][v]);
                multiOk &= ms[v] == (want == INF ? -1 : want);
            }
            okMulti += multiOk ? 1 : 0;
            int dst = r.nextInt(n), stops = r.nextInt(3);
            long want = cheapestOracle(g, src, dst, stops + 1);
            ok787 += cheapestWithinStops(g, src, dst, stops) == want ? 1 : 0;
            okInPlace += cheapestInPlace(g, src, dst, stops) == want ? 1 : 0;
            okPerCity += cheapestDijkstraPerCity(g, src, dst, stops) == want ? 1 : 0;
            Graph neg = randomGraph(r, n, m, -3, 9);
            long[][] fn = floydWarshall(neg);
            boolean cycle = false;
            for (int v = 0; v < n; v++) cycle |= fn[src][v] < INF && fn[v][v] < 0;
            long[] bf = bellmanFord(neg, src);
            if (cycle) { negCycles++; okBf += bf == null ? 1 : 0; }
            else okBf += bf != null && Arrays.equals(bf, fn[src]) ? 1 : 0;
        }
        System.out.printf("random graphs, n <= 10 (%,d trials) vs Floyd-Warshall / path enumeration:%n", trials);
        System.out.printf("   Dijkstra (indexed heap)           %5d/%d%n", okDij, trials);
        System.out.printf("   contest Dijkstra (visited-on-push) %4d/%d%n", okCp, trials);
        System.out.printf("   0-1 BFS                           %5d/%d   multi-source BFS %d/%d%n", ok01, trials, okMulti, trials);
        System.out.printf("   LC 787 <= k stops: snapshot Bellman-Ford %d/%d | in-place relax %d/%d | Dijkstra one-flag-per-city %d/%d%n",
                ok787, trials, okInPlace, trials, okPerCity, trials);
        System.out.printf("   Bellman-Ford (null = negative cycle reachable; %d such graphs) %d/%d%n", negCycles, okBf, trials);

        Graph chain = new Graph(4, new int[] {0, 1, 2}, new int[] {1, 2, 3}, new int[] {1_000_000_000, 1_000_000_000, 1_000_000_000});
        System.out.printf("weights 1e9 on a 3-edge chain: contest int distance to node 3 = %d | long = %,d%n",
                cpDijkstra(chain, 0)[3], dijkstra(chain, 0)[3]);
        try {
            dijkstra(new Graph(2, new int[] {0}, new int[] {1}, new int[] {-1}), 0);
        } catch (IllegalArgumentException e) {
            System.out.println("dijkstra on a negative edge -> IllegalArgumentException: " + e.getMessage());
        }

        int n = 1 << 21, m = 1 << 24, threads = 8;
        int[] f = new int[m], t = new int[m], w = new int[m];
        for (int i = 0; i < m; i++) { f[i] = r.nextInt(n); t[i] = r.nextInt(n); }
        Graph big = new Graph(n, f, t, w);
        long t0 = System.nanoTime();
        int[] seq = multiSourceBfs(big, new int[] {0});
        long t1 = System.nanoTime();
        ExecutorService pool = Executors.newFixedThreadPool(threads);
        parallelBfs(big, 0, threads, pool);                     // warm-up
        long t2 = System.nanoTime();
        int[] par = parallelBfs(big, 0, threads, pool);
        long t3 = System.nanoTime();
        pool.shutdown();
        int levels = Arrays.stream(seq).max().orElse(0);
        System.out.printf("A. BFS on %,d vertices / %,d edges (%d levels, one measured run): sequential %d ms | %d-thread"
                + " level-synchronous with CAS claims %d ms | identical distances %b%n", n, m, levels, (t1 - t0) / 1_000_000,
                threads, (t3 - t2) / 1_000_000, Arrays.equals(seq, par));
    }
}
```

**Output (verified; the last line is one measured run):**

```text
random graphs, n <= 10 (3,000 trials) vs Floyd-Warshall / path enumeration:
   Dijkstra (indexed heap)            3000/3000
   contest Dijkstra (visited-on-push) 2456/3000
   0-1 BFS                            3000/3000   multi-source BFS 3000/3000
   LC 787 <= k stops: snapshot Bellman-Ford 3000/3000 | in-place relax 2884/3000 | Dijkstra one-flag-per-city 2998/3000
   Bellman-Ford (null = negative cycle reachable; 760 such graphs) 3000/3000
weights 1e9 on a 3-edge chain: contest int distance to node 3 = -1294967296 | long = 3,000,000,000
dijkstra on a negative edge -> IllegalArgumentException: Dijkstra needs non-negative weights, got -1
A. BFS on 2,097,152 vertices / 16,777,216 edges (10 levels, one measured run): sequential 395 ms | 8-thread level-synchronous with CAS claims 131 ms | identical distances true
```

### 2.2 Listing 4.2 — C++23

```cpp
// shortest_paths.cpp - CSR graphs, 0-1 BFS, Dijkstra with an indexed heap, state-space search, Bellman-Ford, parallel BFS.
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <functional>
#include <limits>
#include <optional>
#include <print>
#include <queue>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

using i64 = std::int64_t;
using Vec = std::vector<int>;
inline std::size_t U(int x) { return static_cast<std::size_t>(x); }
constexpr i64 kInf = std::numeric_limits<i64>::max() / 4;

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

// Directed graph in compressed sparse row form: edges of u are [start[u], start[u+1]). Immutable.
struct Graph {
    int n;
    Vec start, to, w;
    Graph(int n_, const Vec& from, const Vec& tos, const Vec& ws) : n(n_), start(U(n_) + 1) {
        if (from.size() != tos.size() || tos.size() != ws.size()) throw std::invalid_argument("edge arrays differ in length");
        for (int u : from) {
            if (u < 0 || u >= n) throw std::invalid_argument("vertex out of range: " + std::to_string(u));
            ++start[U(u) + 1];
        }
        for (int v : tos)
            if (v < 0 || v >= n) throw std::invalid_argument("vertex out of range: " + std::to_string(v));
        for (std::size_t i = 0; i < U(n); ++i) start[i + 1] += start[i];
        Vec fill(start.begin(), start.end() - 1);
        to.resize(tos.size()), w.resize(ws.size());
        for (std::size_t e = 0; e < from.size(); ++e) {
            auto k = U(fill[U(from[e])]++);
            to[k] = tos[e], w[k] = ws[e];
        }
    }
    auto edges(int u) const { return std::pair{U(start[U(u)]), U(start[U(u) + 1])}; }
};

// ======================================================================= 0-1 BFS and multi-source BFS
std::vector<i64> bfs01(const Graph& g, int src) {
    for (int x : g.w)
        if (x != 0 && x != 1) throw std::invalid_argument("0-1 BFS needs weights in {0, 1}, got " + std::to_string(x));
    std::vector<i64> dist(U(g.n), kInf);
    std::size_t cap = 2 * (g.to.size() + U(g.n)) + 2, head = cap / 2, tail = cap / 2;  // each relaxation pushes once
    Vec dq(cap);
    dist[U(src)] = 0;
    dq[tail++] = src;
    while (head < tail) {
        int u = dq[head++];
        for (auto [e, end] = g.edges(u); e < end; ++e) {
            int v = g.to[e];
            i64 nd = dist[U(u)] + g.w[e];
            if (nd < dist[U(v)]) {
                dist[U(v)] = nd;
                if (g.w[e] == 0) dq[--head] = v;
                else dq[tail++] = v;
            }
        }
    }
    return dist;
}

// Distance from the NEAREST of several sources: seed the queue with all of them at distance 0. One O(V + E) pass.
Vec multi_source_bfs(const Graph& g, const Vec& sources) {
    Vec dist(U(g.n), -1), q;
    q.reserve(U(g.n));
    for (int s : sources)
        if (dist[U(s)] == -1) dist[U(s)] = 0, q.push_back(s);
    for (std::size_t head = 0; head < q.size(); ++head) {
        int u = q[head];
        for (auto [e, end] = g.edges(u); e < end; ++e)
            if (dist[U(g.to[e])] == -1) dist[U(g.to[e])] = dist[U(u)] + 1, q.push_back(g.to[e]);
    }
    return dist;
}

// ======================================================================= Dijkstra
// Binary min-heap over vertex ids with decrease-key: no allocation per relaxation, at most V entries.
class IndexedMinHeap {
public:
    explicit IndexedMinHeap(int n) : heap_(U(n)), pos_(U(n), -1), key_(U(n)) {}
    bool empty() const { return size_ == 0; }
    void push_or_decrease(int v, i64 k) {
        if (pos_[U(v)] == -1) {
            heap_[size_] = v, pos_[U(v)] = static_cast<int>(size_), key_[U(v)] = k;
            up(size_++);
        } else if (k < key_[U(v)]) {
            key_[U(v)] = k;
            up(U(pos_[U(v)]));
        }
    }
    int pop() {
        int top = heap_[0];
        pos_[U(top)] = -2;  // -2: settled, never re-inserted
        if (--size_ > 0) heap_[0] = heap_[size_], pos_[U(heap_[0])] = 0, down(0);
        return top;
    }
    bool settled(int v) const { return pos_[U(v)] == -2; }

private:
    void up(std::size_t i) {
        while (i > 0 && key_[U(heap_[(i - 1) / 2])] > key_[U(heap_[i])]) swap(i, (i - 1) / 2), i = (i - 1) / 2;
    }
    void down(std::size_t i) {
        while (true) {
            std::size_t l = 2 * i + 1, r = l + 1, m = i;
            if (l < size_ && key_[U(heap_[l])] < key_[U(heap_[m])]) m = l;
            if (r < size_ && key_[U(heap_[r])] < key_[U(heap_[m])]) m = r;
            if (m == i) return;
            swap(i, m), i = m;
        }
    }
    void swap(std::size_t a, std::size_t b) {
        std::swap(heap_[a], heap_[b]);
        pos_[U(heap_[a])] = static_cast<int>(a), pos_[U(heap_[b])] = static_cast<int>(b);
    }
    Vec heap_, pos_;
    std::vector<i64> key_;
    std::size_t size_ = 0;
};

// Non-negative weights required (checked). Invariant: a popped vertex's distance is final. O((V + E) log V).
std::vector<i64> dijkstra(const Graph& g, int src) {
    for (int x : g.w)
        if (x < 0) throw std::invalid_argument("Dijkstra needs non-negative weights, got " + std::to_string(x));
    std::vector<i64> dist(U(g.n), kInf);
    dist[U(src)] = 0;
    IndexedMinHeap h(g.n);
    h.push_or_decrease(src, 0);
    while (!h.empty()) {
        int u = h.pop();
        for (auto [e, end] = g.edges(u); e < end; ++e) {
            int v = g.to[e];
            i64 nd = dist[U(u)] + g.w[e];
            if (nd < dist[U(v)] && !h.settled(v)) dist[U(v)] = nd, h.push_or_decrease(v, nd);
        }
    }
    return dist;
}

// Contest habit: "visited when pushed" (int overflow is UB in C++, so this copy uses int64 and keeps only that bug).
std::vector<i64> cp_dijkstra(const Graph& g, int src) {
    std::vector<i64> dist(U(g.n), kInf);
    std::vector<bool> seen(U(g.n));
    std::priority_queue<std::pair<i64, int>, std::vector<std::pair<i64, int>>, std::greater<>> pq;
    dist[U(src)] = 0;
    pq.push({0, src});
    seen[U(src)] = true;
    while (!pq.empty()) {
        int u = pq.top().second;
        pq.pop();
        for (auto [e, end] = g.edges(u); e < end; ++e) {
            int v = g.to[e];
            if (!seen[U(v)] && dist[U(u)] + g.w[e] < dist[U(v)]) {
                dist[U(v)] = dist[U(u)] + g.w[e];
                seen[U(v)] = true;  // BUG: finalized before it is popped
                pq.push({dist[U(v)], v});
            }
        }
    }
    return dist;
}

std::vector<std::vector<i64>> floyd_warshall(const Graph& g) {
    std::vector<std::vector<i64>> d(U(g.n), std::vector<i64>(U(g.n), kInf));
    for (std::size_t i = 0; i < U(g.n); ++i) d[i][i] = 0;
    for (int u = 0; u < g.n; ++u)
        for (auto [e, end] = g.edges(u); e < end; ++e) d[U(u)][U(g.to[e])] = std::min<i64>(d[U(u)][U(g.to[e])], g.w[e]);
    for (std::size_t k = 0; k < U(g.n); ++k)
        for (std::size_t i = 0; i < U(g.n); ++i)
            for (std::size_t j = 0; j < U(g.n); ++j)
                if (d[i][k] < kInf && d[k][j] < kInf) d[i][j] = std::min(d[i][j], d[i][k] + d[k][j]);
    return d;
}

// ======================================================================= LC 787: cheapest path with <= k stops
i64 cheapest_within_stops(const Graph& g, int src, int dst, int stops) {  // k+1 rounds, each reading the previous round
    std::vector<i64> dist(U(g.n), kInf);
    dist[U(src)] = 0;
    for (int round = 0; round <= stops; ++round) {
        auto next = dist;
        for (int u = 0; u < g.n; ++u) {
            if (dist[U(u)] == kInf) continue;
            for (auto [e, end] = g.edges(u); e < end; ++e) next[U(g.to[e])] = std::min(next[U(g.to[e])], dist[U(u)] + g.w[e]);
        }
        dist = std::move(next);
    }
    return dist[U(dst)];
}

i64 cheapest_in_place(const Graph& g, int src, int dst, int stops) {  // bug 1: one round can chain several edges
    std::vector<i64> dist(U(g.n), kInf);
    dist[U(src)] = 0;
    for (int round = 0; round <= stops; ++round)
        for (int u = 0; u < g.n; ++u)
            if (dist[U(u)] != kInf)
                for (auto [e, end] = g.edges(u); e < end; ++e) dist[U(g.to[e])] = std::min(dist[U(g.to[e])], dist[U(u)] + g.w[e]);
    return dist[U(dst)];
}

i64 cheapest_dijkstra_per_city(const Graph& g, int src, int dst, int stops) {  // bug 2: one "done" flag per city
    std::vector<bool> done(U(g.n));
    std::priority_queue<std::array<i64, 3>, std::vector<std::array<i64, 3>>, std::greater<>> pq;  // (cost, city, edges)
    pq.push({0, src, 0});
    while (!pq.empty()) {
        auto [cost, city, edges] = pq.top();
        pq.pop();
        int u = static_cast<int>(city);
        if (u == dst) return cost;
        if (done[U(u)]) continue;
        done[U(u)] = true;
        if (edges == stops + 1) continue;
        for (auto [e, end] = g.edges(u); e < end; ++e) pq.push({cost + g.w[e], g.to[e], edges + 1});
    }
    return kInf;
}

i64 cheapest_oracle(const Graph& g, int u, int dst, int edges_left) {  // enumerate every path of <= stops+1 edges
    if (u == dst) return 0;
    if (edges_left == 0) return kInf;
    i64 best = kInf;
    for (auto [e, end] = g.edges(u); e < end; ++e)
        if (i64 rest = cheapest_oracle(g, g.to[e], dst, edges_left - 1); rest < kInf) best = std::min(best, g.w[e] + rest);
    return best;
}

// ======================================================================= Bellman-Ford with negative cycles
// Distances, or nullopt when a negative cycle is reachable from src (then "shortest" is undefined). O(V E).
std::optional<std::vector<i64>> bellman_ford(const Graph& g, int src) {
    std::vector<i64> dist(U(g.n), kInf);
    dist[U(src)] = 0;
    for (int round = 0; round < g.n; ++round) {
        bool changed = false;
        for (int u = 0; u < g.n; ++u) {
            if (dist[U(u)] == kInf) continue;
            for (auto [e, end] = g.edges(u); e < end; ++e)
                if (dist[U(u)] + g.w[e] < dist[U(g.to[e])]) dist[U(g.to[e])] = dist[U(u)] + g.w[e], changed = true;
        }
        if (!changed) return dist;
        if (round == g.n - 1) return std::nullopt;  // still improving after n-1 rounds: a reachable negative cycle
    }
    return dist;
}

Graph random_graph(SplitMix64& r, int n, int m, int min_w, int max_w) {
    Vec f(U(m)), t(U(m)), w(U(m));
    for (std::size_t i = 0; i < U(m); ++i) {
        f[i] = r.next_int(n);
        t[i] = r.next_int(n);
        w[i] = min_w + r.next_int(max_w - min_w + 1);
    }
    return Graph(n, f, t, w);
}

// ======================================================================= Extension A: level-synchronous parallel BFS
Vec parallel_bfs(const Graph& g, int src, int threads) {
    std::vector<std::atomic<int>> dist(U(g.n));
    for (auto& d : dist) d.store(-1, std::memory_order_relaxed);
    dist[U(src)].store(0);
    Vec frontier{src};
    for (int level = 0; !frontier.empty(); ++level) {
        std::vector<Vec> parts(U(threads));
        {
            std::vector<std::jthread> ts;
            for (int t = 0; t < threads; ++t)
                ts.emplace_back([&, t] {
                    std::size_t lo = frontier.size() * U(t) / U(threads), hi = frontier.size() * U(t + 1) / U(threads);
                    for (std::size_t i = lo; i < hi; ++i)
                        for (auto [e, end] = g.edges(frontier[i]); e < end; ++e) {
                            int v = g.to[e], expected = -1;
                            if (dist[U(v)].load(std::memory_order_relaxed) == -1 &&
                                dist[U(v)].compare_exchange_strong(expected, level + 1, std::memory_order_relaxed))
                                parts[U(t)].push_back(v);  // exactly one thread claims v
                        }
                });
        }  // join = the level barrier
        frontier.clear();
        for (const auto& p : parts) frontier.insert(frontier.end(), p.begin(), p.end());
    }
    Vec out(U(g.n));
    for (std::size_t i = 0; i < U(g.n); ++i) out[i] = dist[i].load();
    return out;
}

int main() {
    SplitMix64 r{81};
    constexpr int trials = 3'000;
    int ok_dij = 0, ok_cp = 0, ok01 = 0, ok_multi = 0, ok_bf = 0, neg_cycles = 0, ok787 = 0, ok_in_place = 0, ok_per_city = 0;
    for (int t = 0; t < trials; ++t) {
        int n = 2 + r.next_int(9), m = r.next_int(3 * n);
        Graph g = random_graph(r, n, m, 0, 9);
        auto fw = floyd_warshall(g);
        int src = r.next_int(n);
        ok_dij += dijkstra(g, src) == fw[U(src)];
        ok_cp += cp_dijkstra(g, src) == fw[U(src)];
        Graph g01 = random_graph(r, n, m, 0, 1);
        ok01 += bfs01(g01, src) == floyd_warshall(g01)[U(src)];
        Graph unit = random_graph(r, n, m, 1, 1);
        auto fu = floyd_warshall(unit);
        int s2 = r.next_int(n);
        Vec ms = multi_source_bfs(unit, {src, s2});
        bool multi_ok = true;
        for (std::size_t v = 0; v < U(n); ++v) {
            i64 want = std::min(fu[U(src)][v], fu[U(s2)][v]);
            multi_ok = multi_ok && ms[v] == (want == kInf ? -1 : want);
        }
        ok_multi += multi_ok;
        int dst = r.next_int(n), stops = r.next_int(3);
        i64 want = cheapest_oracle(g, src, dst, stops + 1);
        ok787 += cheapest_within_stops(g, src, dst, stops) == want;
        ok_in_place += cheapest_in_place(g, src, dst, stops) == want;
        ok_per_city += cheapest_dijkstra_per_city(g, src, dst, stops) == want;
        Graph neg = random_graph(r, n, m, -3, 9);
        auto fn = floyd_warshall(neg);
        bool cycle = false;
        for (std::size_t v = 0; v < U(n); ++v) cycle = cycle || (fn[U(src)][v] < kInf && fn[v][v] < 0);
        auto bf = bellman_ford(neg, src);
        if (cycle) ++neg_cycles, ok_bf += !bf.has_value();
        else ok_bf += bf.has_value() && *bf == fn[U(src)];
    }
    std::println("random graphs, n <= 10 ({} trials) vs Floyd-Warshall / path enumeration:", trials);
    std::println("   Dijkstra (indexed heap)           {:5}/{}", ok_dij, trials);
    std::println("   contest Dijkstra (visited-on-push) {:4}/{}", ok_cp, trials);
    std::println("   0-1 BFS                           {:5}/{}   multi-source BFS {}/{}", ok01, trials, ok_multi, trials);
    std::println("   LC 787 <= k stops: snapshot Bellman-Ford {}/{} | in-place relax {}/{} | Dijkstra one-flag-per-city {}/{}",
                 ok787, trials, ok_in_place, trials, ok_per_city, trials);
    std::println("   Bellman-Ford (nullopt = negative cycle reachable; {} such graphs) {}/{}", neg_cycles, ok_bf, trials);
    Graph chain(4, {0, 1, 2}, {1, 2, 3}, {1'000'000'000, 1'000'000'000, 1'000'000'000});
    std::println("weights 1e9 on a 3-edge chain: contest int distance: not run (signed overflow is UB) | int64 = {}",
                 dijkstra(chain, 0)[3]);
    try {
        (void)dijkstra(Graph(2, {0}, {1}, {-1}), 0);
    } catch (const std::invalid_argument& e) {
        std::println("dijkstra on a negative edge -> std::invalid_argument: {}", e.what());
    }

    constexpr int n = 1 << 21, m = 1 << 24, threads = 8;
    Vec f(U(m)), t(U(m)), w(U(m));
    for (std::size_t i = 0; i < U(m); ++i) {
        f[i] = r.next_int(n);
        t[i] = r.next_int(n);
    }
    Graph big(n, f, t, w);
    using clock = std::chrono::steady_clock;
    auto ms = [](clock::duration d) { return std::chrono::duration_cast<std::chrono::milliseconds>(d).count(); };
    auto t0 = clock::now();
    Vec seq = multi_source_bfs(big, {0});
    auto t1 = clock::now();
    Vec par = parallel_bfs(big, 0, threads);
    auto t2 = clock::now();
    std::println("A. BFS on {} vertices / {} edges ({} levels, one measured run): sequential {} ms | {}-thread level-synchronous"
                 " with CAS claims {} ms | identical distances {}", n, m, *std::ranges::max_element(seq), ms(t1 - t0), threads,
                 ms(t2 - t1), seq == par);
}
```

**Output, GCC 16.2 (verified; the last line is one measured run):**

```text
random graphs, n <= 10 (3000 trials) vs Floyd-Warshall / path enumeration:
   Dijkstra (indexed heap)            3000/3000
   contest Dijkstra (visited-on-push) 2456/3000
   0-1 BFS                            3000/3000   multi-source BFS 3000/3000
   LC 787 <= k stops: snapshot Bellman-Ford 3000/3000 | in-place relax 2884/3000 | Dijkstra one-flag-per-city 2998/3000
   Bellman-Ford (nullopt = negative cycle reachable; 760 such graphs) 3000/3000
weights 1e9 on a 3-edge chain: contest int distance: not run (signed overflow is UB) | int64 = 3000000000
dijkstra on a negative edge -> std::invalid_argument: Dijkstra needs non-negative weights, got -1
A. BFS on 2097152 vertices / 16777216 edges (10 levels, one measured run): sequential 215 ms | 8-thread level-synchronous with CAS claims 90 ms | identical distances true
```

**Output, Clang 21.1 (verified; the last line is one measured run):**

```text
random graphs, n <= 10 (3000 trials) vs Floyd-Warshall / path enumeration:
   Dijkstra (indexed heap)            3000/3000
   contest Dijkstra (visited-on-push) 2456/3000
   0-1 BFS                            3000/3000   multi-source BFS 3000/3000
   LC 787 <= k stops: snapshot Bellman-Ford 3000/3000 | in-place relax 2884/3000 | Dijkstra one-flag-per-city 2998/3000
   Bellman-Ford (nullopt = negative cycle reachable; 760 such graphs) 3000/3000
weights 1e9 on a 3-edge chain: contest int distance: not run (signed overflow is UB) | int64 = 3000000000
dijkstra on a negative edge -> std::invalid_argument: Dijkstra needs non-negative weights, got -1
A. BFS on 2097152 vertices / 16777216 edges (10 levels, one measured run): sequential 241 ms | 8-thread level-synchronous with CAS claims 94 ms | identical distances true
```

---

## 3. What the results show

* **All production algorithms match the oracles on all 3,000 random graphs**, including 760 graphs where a negative cycle is reachable and Bellman–Ford must refuse to answer.
* **The bugs are quiet.** Visited-on-push: 82% correct. In-place relaxation for LC 787: 96%. One-flag-per-city Dijkstra for LC 787: **99.93%**. The last one is the dangerous kind: plausible, fast, and wrong in 2 of 3,000 random cases. Only a path-enumeration oracle on thousands of small graphs found it. Java and C++ agree count for count, because both use a total order (cost, city, edges) in their priority queues. With an incomplete comparator the two languages pop ties in different orders and even the bug counts differ.
* **Overflow:** three edges of weight 10⁹ give an `int` distance of −1,294,967,296 in Java. In C++ the same code is undefined behaviour and is not run. 64-bit distances with `INF = MAX/4` (so `INF + w` stays finite) avoid both.
* **Parallel BFS (Extension A):** 2,097,152 vertices, 16,777,216 random edges, 10 levels. Sequential 210–395 ms; 8 threads, level-synchronous with one CAS per discovered vertex, 88–131 ms (2.4–3.0×), with identical distance arrays in every run.

---

## 4. The last 10 minutes: Extensions A, B and C

### 4.1 Extension A — "64 threads"

* **Level-synchronous BFS** (measured): each level's frontier is split across threads, and a vertex is claimed with one compare-and-set on its distance cell, so exactly one thread adds it to the next frontier. The join at the end of each level is the barrier. Speedup was 2.4–3.0× on 8 threads: BFS on random graphs is **memory-bound** (random accesses into 16 M edges), so threads mostly wait on DRAM together (Folder 01 File 2). Production graph engines add **direction optimization**: when the frontier is large, each unvisited vertex scans its own in-edges for any visited parent instead of each frontier vertex scanning out-edges (Beamer et al.), often 2–10× on low-diameter graphs ⚠ (cited, not measured here).
* **Parallel Dijkstra** is hard because the heap is sequential by nature. Practical options: **Δ-stepping**, which processes all vertices within a distance bucket of width Δ in parallel, or many independent single-source queries in parallel, one per thread, over an immutable shared graph. The second is how a routing service scales: the graph is read-only, so queries need no synchronization.
* **Concurrent graph updates** (edge weights changing with traffic): publish immutable graph snapshots (copy-on-write CSR), and route each query on the snapshot it started with.

### 4.2 Extension B — "the graph doesn't fit in RAM"

* **Semi-external BFS:** if the vertex state fits (one bit or byte per vertex, so 10⁹ vertices is 125 MB of bits) but the edges don't, stream the edge file sequentially once per level and expand every edge whose source is in the frontier. Each level costs one sequential scan instead of random I/O: the I/O model's trade (Folder 01 File 2), and Folder 07 implements it.
* **CSR on disk, memory-mapped:** the `start[]` array is the index and `to[]` the payload. Partition vertices by degree so hubs' adjacency lists are read once.
* **Shortest paths at continental scale** (road networks) use precomputation: contraction hierarchies or hub labels answer queries in microseconds by touching a tiny fraction of the graph. Naming that, instead of "run Dijkstra on 10⁸ vertices per query", is a Staff signal.

### 4.3 Extension C — "the graph is partitioned across 100 machines"

* **BSP / Pregel BFS:** each superstep, every machine expands its local frontier vertices and sends "visit v at distance d" messages for edges that cross partitions. A barrier ends the superstep, and messages become the next frontier. Supersteps = BFS depth; network traffic ≈ number of cut edges. Folder 07 measures it.
* **Partitioning decides the cost:** a hash partition cuts about (1 − 1/S) of edges; a locality-aware partition (by region, by community) cuts far fewer. For shortest paths on road networks, partition by geography and precompute boundary-to-boundary distances per partition: a two-level hierarchy.
* **Distributed Bellman–Ford** is the distance-vector routing protocol (RIP): each node keeps distances and exchanges them with neighbours each round. Its "count to infinity" behaviour on link failure is Bellman–Ford meeting a changing graph, and a good story to tell if the interviewer is network-minded.

---

## 5. Failure modes

| # | Failure | Symptom | Prevention |
|---|---|---|---|
| F1 | Visited-on-push in Dijkstra | Wrong distances when a cheaper path is found later (18% here) | Finalize on pop; or indexed heap with a settled flag |
| F2 | `int` distances | Negative "distances" after overflow | `long`, `INF = MAX/4` |
| F3 | Dijkstra with negative edges | Silently wrong | Validate weights; Bellman–Ford or Johnson's reweighting |
| F4 | Stop-limited paths with per-vertex finality | Wrong in rare cases (2 / 3,000) | State = (vertex, stops); or snapshot Bellman–Ford |
| F5 | In-place Bellman–Ford rounds for a hop limit | Paths with too many edges | Read the previous round's array |
| F6 | Ignoring reachable negative cycles | Garbage distances | Detect in round V; return an explicit "no answer" |
| F7 | Comparator without a total order | Results differ across languages and libraries | Order by (cost, id, ...) |
| F8 | Recursion in graph search | Stack overflow on long paths | Explicit queues and stacks |
| F9 | `vector<vector<>>` adjacency on big graphs | Allocation and pointer chasing | CSR |

---

## 6. Bar-raiser chains

<details><summary><b>Q1 · "Why is Dijkstra correct, and when isn't it?"</b></summary>

**Initial Prompt.** After the candidate writes Dijkstra.

**L5 Answer.** "It always picks the closest unvisited node."

**Why L5 Stalls.** Restates the algorithm instead of the invariant, and misses the non-negativity requirement.

**L7 Answer.** "When a vertex is popped with distance d, every other frontier distance is at least d, and edges are non-negative, so no path through the frontier can come back cheaper: popped distances are final. With one negative edge that argument fails, so the code rejects negative weights and I'd use Bellman–Ford instead. It's also why a vertex must be final on *pop*, not on push."
</details>

<details><summary><b>Q2 · "Cheapest flight with at most k stops."</b></summary>

**Initial Prompt.** LeetCode 787.

**L5 Answer.** Dijkstra keyed by cost with a visited set per city.

**Why L5 Stalls.** The cheapest arrival at a city may have used too many stops and block a costlier arrival with stops to spare. Wrong in 2 of 3,000 random graphs: it passes most test suites.

**L7 Answer.** "The stop limit makes the state (city, edges used), so 'visited' must be per state. Simplest correct: k+1 rounds of Bellman–Ford, each reading only the previous round's distances, which is O(k × E). In-place relaxation is a bug because it lets a round chain several edges. Or Dijkstra over (city, edges) pairs, which explores at most n × (k+1) states. I verified both against path enumeration on random graphs."
</details>

<details><summary><b>Q3 · "Edges cost 0 or 1. Can you beat Dijkstra?"</b></summary>

**Initial Prompt.** A grid where following an arrow is free and changing it costs 1 (LeetCode 1368).

**L5 Answer.** "Dijkstra, O(E log V)."

**Why L5 Stalls.** Correct but misses that two distinct weights make the heap unnecessary.

**L7 Answer.** "0-1 BFS: a deque where 0-edges push to the front and 1-edges to the back. It stays sorted because it only ever holds two adjacent distance values. O(V + E), no heap. For general small integer weights the same idea becomes Dial's algorithm with buckets."
</details>

<details><summary><b>Q4 · "Distance from every cell to the nearest exit."</b></summary>

**Initial Prompt.** Grid with several exits (LeetCode 542-style).

**L5 Answer.** BFS from every cell, or from every exit separately.

**Why L5 Stalls.** O(V × sources) or O(V²).

**L7 Answer.** "Multi-source BFS: put every exit in the queue at distance 0 and run one BFS. Each cell's distance is to its nearest exit, O(V + E) total. It's equivalent to adding a virtual source connected to all exits with 0-weight edges, the same trick that turns 'nearest of many' into a single-source problem for Dijkstra too."
</details>

<details><summary><b>Q5 · "Weights go up to 10⁹ and paths can have 10⁵ edges."</b></summary>

**Initial Prompt.** Overflow probe.

**L5 Answer.** "Use INF = 1e18."

**Why L5 Stalls.** Half the answer. The *distance* type is often still `int`, and `INF + w` with `INF = Long.MAX_VALUE` overflows in the relaxation.

**L7 Answer.** "Distances can reach 10¹⁴, so long, and INF = Long.MAX_VALUE / 4 so that INF + w can't wrap. Otherwise an unreachable vertex 'relaxes' to a negative distance. I'd test a chain of three 10⁹ edges: the int version gives −1,294,967,296."
</details>

<details><summary><b>Q6 · "A billion vertices, BFS, one machine with 32 GB."</b></summary>

**Initial Prompt.** Extension B.

**L5 Answer.** "Load the graph into an adjacency list."

**Why L5 Stalls.** Edges alone may be hundreds of GB.

**L7 Answer.** "Vertex state fits (a bit or a byte per vertex), edges don't. So: semi-external BFS. Keep the visited/frontier bitmaps in RAM and stream the edge file sequentially once per level, expanding edges whose source is in the current frontier. Cost is depth × sequential scans, which beats random I/O by orders of magnitude on disk. If depth is large, partition edges by source range so each level reads only the blocks containing frontier vertices."
</details>

<details><summary><b>Q7 · "Parallelize BFS."</b></summary>

**Initial Prompt.** Extension A.

**L5 Answer.** "Give each thread some vertices."

**Why L5 Stalls.** No synchronization story: two threads can both discover v and add it twice, or overwrite each other's distances.

**L7 Answer.** "Level-synchronous: split the current frontier across threads. Each thread claims a newly discovered vertex with one compare-and-set on its distance cell, so exactly one thread owns it, and appends it to a thread-local next frontier. The end of a level is a barrier where the local frontiers are concatenated. I measured 2.4–3× on 8 threads for a random 16 M-edge graph. It's memory-bound, so more threads help less than you'd think. For low-diameter graphs, switching to bottom-up expansion when the frontier is large is the next big win."
</details>

<details><summary><b>Q8 · "The graph is partitioned across 100 servers."</b></summary>

**Initial Prompt.** Extension C.

**L5 Answer.** "Each server runs BFS on its part."

**Why L5 Stalls.** Paths cross partitions, and a local BFS can't see them.

**L7 Answer.** "BSP, as in Pregel. Each superstep expands local frontier vertices and sends messages for edges crossing partitions; a barrier ends the step. Supersteps equal the BFS depth, and traffic equals the number of cut edges crossed, so partitioning to minimize cut edges is the main lever. For repeated shortest-path queries on road networks I'd precompute a hierarchy (contraction hierarchies or partition-boundary distance tables) rather than run a distributed search per query."
</details>

---

## 7. Checklist

* [ ] CSR adjacency; validated vertex ids.
* [ ] Pick by weights: BFS (unit), 0-1 BFS, Dijkstra (≥ 0), Bellman–Ford (any).
* [ ] State the invariant: popped = final (Dijkstra); round k = paths of ≤ k edges (Bellman–Ford).
* [ ] `long` distances, `INF = MAX/4`; validate non-negative weights for Dijkstra.
* [ ] Constrained paths: define the state; snapshot Bellman–Ford for hop limits.
* [ ] Negative cycles: explicit "no answer" result.
* [ ] Total-order comparators.
* [ ] Extension A: level-synchronous BFS with CAS claims; immutable graph for parallel queries.
* [ ] Extension B: semi-external BFS; precomputed hierarchies for huge road graphs.
* [ ] Extension C: BSP supersteps; minimize cut edges.

---

## 8. References

* E. W. Dijkstra, *A Note on Two Problems in Connexion with Graphs*, Numerische Mathematik 1, 1959 — DOI 10.1007/BF01386390
* S. Beamer, K. Asanović, D. Patterson, *Direction-Optimizing Breadth-First Search*, SC 2012 — DOI 10.1109/SC.2012.50
* U. Meyer, P. Sanders, *Δ-stepping: a parallelizable shortest path algorithm*, J. Algorithms 49(1), 2003 — DOI 10.1016/S0196-6774(03)00076-2
* G. Malewicz et al., *Pregel: A System for Large-Scale Graph Processing*, SIGMOD 2010 — DOI 10.1145/1807167.1807184
* R. Geisberger, P. Sanders, D. Schultes, D. Delling, *Contraction Hierarchies*, WEA 2008 — DOI 10.1007/978-3-540-68552-4_24
* cp-algorithms: [0-1 BFS](https://cp-algorithms.com/graph/01_bfs.html), [Dijkstra](https://cp-algorithms.com/graph/dijkstra.html), [Bellman–Ford](https://cp-algorithms.com/graph/bellman_ford.html)
* LeetCode anchors: [743 Network Delay Time](https://leetcode.com/problems/network-delay-time/), [787 Cheapest Flights Within K Stops](https://leetcode.com/problems/cheapest-flights-within-k-stops/), [1368 Minimum Cost to Make at Least One Valid Path in a Grid](https://leetcode.com/problems/minimum-cost-to-make-at-least-one-valid-path-in-a-grid/), [542 01 Matrix](https://leetcode.com/problems/01-matrix/)

*Folder 04:* [02 — topological sort, Tarjan SCC, bridges](02-topological-sort-kahn-cycle-detection-and-tarjan-scc-bridges-articulation.md) · [03 — DSU, matching, min-cut](03-disjoint-set-union-dsu-with-rollback-bipartite-matching-and-min-cut.md)
