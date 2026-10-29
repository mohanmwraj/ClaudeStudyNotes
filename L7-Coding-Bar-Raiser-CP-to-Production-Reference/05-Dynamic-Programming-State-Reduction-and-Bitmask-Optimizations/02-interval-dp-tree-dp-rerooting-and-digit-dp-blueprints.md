# Interval DP, Tree DP with Rerooting, and Digit DP Blueprints

> **Folder 05 · File 2 of 3** — three DP shapes whose states are not prefixes: intervals (order by length), trees (order by subtree, then reroot in O(1) per edge), and digits (order by position, with a "tight" flag and a "started" flag that contest code forgets).
> **Languages:** Java 21 (`--release 21 -Xlint:all -Werror`, JDK 25.0.4.1) and C++23 (GCC 16.2 and Clang 21.1, `-O2`, warnings as errors).

| Listing | File | What it proves |
|---|---|---|
| 5.3 | `DpPatterns.java` | Matrix-chain order with a reconstructed parenthesization that re-evaluates to the optimum (CLRS example: 15,125); sum of distances **and** eccentricity for every vertex by two-pass rerooting, against BFS from every vertex; digit DP up to `Long.MAX_VALUE`, where the missing `started` flag is right on 18/90 cases; interval DP parallel by length |
| 5.4 | `dp_patterns.cpp` | The same; the parallel version uses persistent threads with a spin barrier per interval length |

**Verification.** Both listings were extracted from this file, compiled and run. Everything is **Output (verified)** except the last line (**one measured run**).

---

## 0. Orientation

| Contest habit | What breaks | L7 replacement |
|---|---|---|
| Interval DP returning only the cost | "Show me the order" can't be answered | A split table + reconstruction, re-evaluated against the reported cost |
| Root the tree at every vertex: O(n²) | 10⁵ vertices → 10¹⁰ steps | Rerooting: one bottom-up pass + one top-down pass, O(n) for all roots |
| Rerooting a max with one "best child" value | Wrong when the best path goes through the child being rerooted to | Keep the top **two** children (and which child gave the best) |
| Recursive DFS for tree DP | Stack overflow on a path | BFS order; process it backwards (bottom-up) and forwards (top-down) |
| Digit DP with leading zeros treated as digits | "007" has two equal neighbours; wrong on 80% of cases here | A `started` flag in the state |
| Memoized digit DP keyed by strings | Slow and allocation-heavy | Small dense arrays over (sum mod k, last digit, started) |

---

## 1. First principles

### 1.1 Interval DP

When the last decision splits an interval `[i, j]` into `[i, k]` and `[k + 1, j]` (the last multiplication, the last balloon to burst, the root of an optimal BST), the state is the interval and the order is **by length**. All intervals of one length depend only on shorter ones, which is also why they parallelize. Cost: O(n²) states × O(n) splits = O(n³). Knuth's optimization reduces some of these (optimal BST) to O(n²) when the best split is monotone in the interval ends. Matrix chain does not satisfy that condition in general.

### 1.2 Rerooting

Many tree questions want an answer **for every vertex as the root**: sum of distances to all others (LeetCode 834), farthest vertex (eccentricity), the number of nodes within distance k. Recomputing from each root is O(n²). Rerooting does it in O(n):

1. **Down pass (post-order):** for a fixed root, compute subtree aggregates: `size[u]`, `down[u]` = sum of distances from u to its subtree, and the two longest downward paths with the child that gives the best one.
2. **Up pass (pre-order):** moving the root from parent p to child u changes aggregates in O(1). For distances: `sum[u] = sum[p] − size[u] + (n − size[u])`, because u's subtree gets one step closer and everything else one step farther. For the farthest vertex: the longest path leaving u upward is `1 + max(up[p], longest downward path of p not through u)`. "Not through u" is why the down pass keeps the **top two** downward paths and *which* child gave the top one. Keeping only the best is the classic rerooting bug.

The general recipe is an associative "combine children" operation with an exclusion: the answer for u's parent side is everything at p except u's own contribution. Prefix and suffix combinations over p's children handle operations without an inverse, such as max.

### 1.3 Digit DP

To count numbers in `[0, N]` with a digit property, walk N's digits from the most significant. The state after a prefix is whatever the property needs from the past, plus two control flags:

* **tight:** the prefix equals N's prefix, so the next digit is bounded by N's digit. The listing handles this by walking N's digits explicitly. Only one tight path exists.
* **started:** a non-zero digit has appeared. Leading zeros are not digits of the number, so "no two equal neighbouring digits" must ignore them. Without the flag, 7 is processed as "...007" and rejected.

For "no equal neighbours and digit sum divisible by k" the state is `(sum mod k, last digit, started)`: at most k × 11 × 2 states per position, 19 positions for any 64-bit N. The listing counts up to `Long.MAX_VALUE` instantly and agrees with brute force on 90 (limit, k) pairs up to 100,000.

---

## 2. The listings

### 2.1 Listing 5.3 — Java

```java
// DpPatterns.java - interval DP with reconstruction, tree DP with rerooting (iterative), digit DP with a leading-zero flag.
import java.util.ArrayDeque;
import java.util.Arrays;
import java.util.stream.IntStream;

public final class DpPatterns {

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

    // ===================================================================== 1. interval DP: matrix-chain order
    /** Matrices M_i are dims[i] x dims[i+1]. cost[i][j] = cheapest product of M_i..M_j; split[i][j] = where. O(n^3). */
    static final class MatrixChain {
        final long[][] cost;
        final int[][] split;

        MatrixChain(int[] dims, boolean parallel) {
            int n = dims.length - 1;
            cost = new long[n][n];
            split = new int[n][n];
            for (int len = 2; len <= n; len++) {          // all intervals of one length depend only on shorter ones
                final int L = len;
                IntStream range = IntStream.rangeClosed(0, n - len);
                (parallel ? range.parallel() : range).forEach(i -> {
                    int j = i + L - 1;
                    long best = Long.MAX_VALUE;
                    for (int k = i; k < j; k++) {
                        long c = cost[i][k] + cost[k + 1][j] + (long) dims[i] * dims[k + 1] * dims[j + 1];
                        if (c < best) { best = c; split[i][j] = k; }
                    }
                    cost[i][j] = best;
                });
            }
        }

        String order(int i, int j) {  // reconstruction from the split table (recursion depth <= n: chains are short)
            if (i == j) return "M" + i;
            return "(" + order(i, split[i][j]) + " " + order(split[i][j] + 1, j) + ")";
        }
    }

    static long chainOracle(int[] dims, int i, int j) {  // every parenthesization, exponential
        if (i == j) return 0;
        long best = Long.MAX_VALUE;
        for (int k = i; k < j; k++) best = Math.min(best, chainOracle(dims, i, k) + chainOracle(dims, k + 1, j) + (long) dims[i] * dims[k + 1] * dims[j + 1]);
        return best;
    }

    static long evaluate(int[] dims, String order) {  // re-derive the cost of a printed order: the reconstruction is checked
        ArrayDeque<long[]> st = new ArrayDeque<>();   // (rows, cols, cost)
        ArrayDeque<Character> ops = new ArrayDeque<>();
        for (int p = 0; p < order.length(); p++) {
            char c = order.charAt(p);
            if (c == 'M') {
                int q = p + 1;
                while (q < order.length() && Character.isDigit(order.charAt(q))) q++;
                int idx = Integer.parseInt(order.substring(p + 1, q));
                st.push(new long[] {dims[idx], dims[idx + 1], 0});
                p = q - 1;
            } else if (c == ')') {
                long[] right = st.pop(), left = st.pop();
                st.push(new long[] {left[0], right[1], left[2] + right[2] + left[0] * left[1] * right[1]});
            }
        }
        return st.pop()[2];
    }

    // ===================================================================== 2. tree DP with rerooting
    /** LC 834 + eccentricity for EVERY vertex in O(n): one bottom-up pass, one top-down pass, no recursion. */
    static long[][] reroot(int n, int[] eu, int[] ev) {
        int[] start = new int[n + 1], adj = new int[2 * (n - 1)];
        for (int e = 0; e < n - 1; e++) { start[eu[e] + 1]++; start[ev[e] + 1]++; }
        for (int i = 0; i < n; i++) start[i + 1] += start[i];
        int[] fill = Arrays.copyOf(start, n);
        for (int e = 0; e < n - 1; e++) { adj[fill[eu[e]]++] = ev[e]; adj[fill[ev[e]]++] = eu[e]; }
        int[] order = new int[n], parent = new int[n];
        Arrays.fill(parent, -1);
        int head = 0, tail = 0;
        order[tail++] = 0;
        parent[0] = 0;
        while (head < tail) { int u = order[head++]; for (int k = start[u]; k < start[u + 1]; k++) if (parent[adj[k]] == -1) { parent[adj[k]] = u; order[tail++] = adj[k]; } }
        parent[0] = -1;
        long[] size = new long[n], down = new long[n], sum = new long[n];
        int[] best1 = new int[n], best2 = new int[n], via = new int[n];  // two longest downward paths, and via which child
        Arrays.fill(via, -1);
        for (int i = n - 1; i >= 0; i--) {                       // bottom-up: subtree sizes, distance sums, depths
            int u = order[i];
            size[u]++;
            if (parent[u] >= 0) {
                int p = parent[u];
                size[p] += size[u];
                down[p] += down[u] + size[u];
                int d = best1[u] + 1;
                if (d > best1[p]) { best2[p] = best1[p]; best1[p] = d; via[p] = u; } else if (d > best2[p]) best2[p] = d;
            }
        }
        int[] up = new int[n];                                   // longest path that leaves u through its parent
        sum[0] = down[0];
        for (int i = 1; i < n; i++) {                            // top-down: move the root across one edge at a time
            int u = order[i], p = parent[u];
            sum[u] = sum[p] - size[u] + (n - size[u]);           // size[u] nodes get 1 closer, the rest 1 farther
            up[u] = 1 + Math.max(up[p], via[p] == u ? best2[p] : best1[p]);
        }
        long[] ecc = new long[n];
        for (int u = 0; u < n; u++) ecc[u] = Math.max(best1[u], up[u]);
        return new long[][] {sum, ecc};
    }

    static long[][] rerootOracle(int n, int[] eu, int[] ev) {
        long[] sum = new long[n], ecc = new long[n];
        for (int s = 0; s < n; s++) {
            int[] dist = new int[n];
            Arrays.fill(dist, -1);
            dist[s] = 0;
            ArrayDeque<Integer> q = new ArrayDeque<>();
            q.add(s);
            while (!q.isEmpty()) {
                int u = q.poll();
                for (int e = 0; e < n - 1; e++) {
                    int v = eu[e] == u ? ev[e] : ev[e] == u ? eu[e] : -1;
                    if (v >= 0 && dist[v] == -1) { dist[v] = dist[u] + 1; q.add(v); }
                }
            }
            for (int d : dist) { sum[s] += d; ecc[s] = Math.max(ecc[s], d); }
        }
        return new long[][] {sum, ecc};
    }

    // ===================================================================== 3. digit DP
    /**
     * Count x in [0, limit] whose decimal digits have no two equal neighbours and whose digit sum is divisible by k.
     * State after each prefix: (digit-sum mod k, last digit, started?). "tight" is handled by walking the bound's
     * digits. Leading zeros are not digits: without the `started` flag, 7 = "007" fails the neighbour rule.
     */
    static long digitCount(long limit, int k, boolean trackStarted) {
        if (limit < 0) return 0;
        char[] ds = Long.toString(limit).toCharArray();
        int len = ds.length;
        long[][][] free = new long[k][11][2];  // counts of non-tight prefixes: [sumMod][last digit or 10 = none][started]
        int tightSum = 0, tightLast = 10;
        boolean tightStarted = false, tightAlive = true;
        for (int p = 0; p < len; p++) {
            long[][][] next = new long[k][11][2];
            for (int s = 0; s < k; s++)
                for (int last = 0; last <= 10; last++)
                    for (int st = 0; st < 2; st++) {
                        long c = free[s][last][st];
                        if (c == 0) continue;
                        for (int d = 0; d <= 9; d++) add(next, s, last, st == 1, d, k, c, trackStarted);
                    }
            if (tightAlive) {
                int bound = ds[p] - '0';
                for (int d = 0; d < bound; d++) add(next, tightSum, tightLast, tightStarted, d, k, 1, trackStarted);
                boolean started = tightStarted || bound != 0 || !trackStarted;
                if (started && tightLast != 10 && tightLast == bound) tightAlive = false;
                else if (started) { tightSum = (tightSum + bound) % k; tightLast = bound; tightStarted = true; }
            }
            free = next;
        }
        long total = 0;
        for (int last = 0; last <= 10; last++) total += free[0][last][1] + free[0][last][0];  // [0][..][0] = the number 0
        if (tightAlive && tightSum % k == 0) total++;
        return total;
    }

    private static void add(long[][][] next, int s, int last, boolean started, int d, int k, long c, boolean trackStarted) {
        boolean nowStarted = started || d != 0 || !trackStarted;
        if (!nowStarted) { next[s][10][0] += c; return; }                   // still in the leading zeros
        if (last != 10 && last == d) return;                                // equal neighbours: rejected
        next[(s + d) % k][d][1] += c;
    }

    static long digitOracle(long limit, int k) {
        long c = 0;
        for (long x = 0; x <= limit; x++) {
            String s = Long.toString(x);
            boolean ok = true;
            int sum = 0;
            for (int i = 0; i < s.length(); i++) { sum += s.charAt(i) - '0'; if (i > 0 && s.charAt(i) == s.charAt(i - 1)) ok = false; }
            if (ok && sum % k == 0) c++;
        }
        return c;
    }

    public static void main(String[] args) {
        SplitMix64 r = new SplitMix64(121);
        int trials = 1_500, okChain = 0, okReroot = 0;
        for (int t = 0; t < trials; t++) {
            int n = 1 + r.nextInt(8);
            int[] dims = new int[n + 1];
            for (int i = 0; i <= n; i++) dims[i] = 1 + r.nextInt(30);
            MatrixChain mc = new MatrixChain(dims, false);
            long want = chainOracle(dims, 0, n - 1);
            okChain += mc.cost[0][n - 1] == want && evaluate(dims, mc.order(0, n - 1)) == want ? 1 : 0;
            int tn = 1 + r.nextInt(30);
            int[] eu = new int[tn - 1], ev = new int[tn - 1];
            for (int v = 1; v < tn; v++) { eu[v - 1] = r.nextInt(v); ev[v - 1] = v; }
            long[][] got = reroot(tn, eu, ev), exp = rerootOracle(tn, eu, ev);
            okReroot += Arrays.equals(got[0], exp[0]) && Arrays.equals(got[1], exp[1]) ? 1 : 0;
        }
        System.out.printf("1. matrix chain: optimal cost == all parenthesizations, and the printed order re-evaluates to it: %d/%d%n", okChain, trials);
        int[] demo = {30, 35, 15, 5, 10, 20, 25};
        MatrixChain mc = new MatrixChain(demo, false);
        System.out.printf("   CLRS dims %s -> %,d multiplications via %s%n", Arrays.toString(demo), mc.cost[0][5], mc.order(0, 5));
        System.out.printf("2. rerooting: sum of distances AND eccentricity for every vertex == BFS from every vertex: %d/%d%n", okReroot, trials);

        int okDigit = 0, cpDigit = 0;
        long[] limits = {0, 9, 10, 99, 100, 777, 1_000, 54_321, 99_999, 100_000};
        for (long lim : limits)
            for (int k = 1; k <= 9; k++) {
                long want = digitOracle(lim, k);
                okDigit += digitCount(lim, k, true) == want ? 1 : 0;
                cpDigit += digitCount(lim, k, false) == want ? 1 : 0;
            }
        System.out.printf("3. digit DP (no equal neighbours, digit sum %% k == 0), 90 (limit, k) pairs vs brute force:"
                + " with started flag %d/90 | leading zeros as digits %d/90%n", okDigit, cpDigit);
        System.out.printf("   limit = Long.MAX_VALUE (%,d), k = 7: %,d numbers, counted in 19 digit steps%n",
                Long.MAX_VALUE, digitCount(Long.MAX_VALUE, 7, true));

        int n = 700;
        int[] dims = new int[n + 1];
        for (int i = 0; i <= n; i++) dims[i] = 1 + r.nextInt(100);
        new MatrixChain(dims, true);   // warm-up (and common-pool start-up)
        long t0 = System.nanoTime();
        long seq = new MatrixChain(dims, false).cost[0][n - 1];
        long t1 = System.nanoTime();
        long par = new MatrixChain(dims, true).cost[0][n - 1];
        long t2 = System.nanoTime();
        System.out.printf("A. matrix chain n=%d (%,d split evaluations, one measured run): sequential %d ms | parallel per interval"
                + " length (common pool) %d ms | equal %b%n", n, (long) n * n * n / 6, (t1 - t0) / 1_000_000, (t2 - t1) / 1_000_000, seq == par);
    }
}
```

**Output (verified; the last line is one measured run):**

```text
1. matrix chain: optimal cost == all parenthesizations, and the printed order re-evaluates to it: 1500/1500
   CLRS dims [30, 35, 15, 5, 10, 20, 25] -> 15,125 multiplications via ((M0 (M1 M2)) ((M3 M4) M5))
2. rerooting: sum of distances AND eccentricity for every vertex == BFS from every vertex: 1500/1500
3. digit DP (no equal neighbours, digit sum % k == 0), 90 (limit, k) pairs vs brute force: with started flag 90/90 | leading zeros as digits 18/90
   limit = Long.MAX_VALUE (9,223,372,036,854,775,807), k = 7: 200,953,421,551,707,992 numbers, counted in 19 digit steps
A. matrix chain n=700 (57,166,666 split evaluations, one measured run): sequential 117 ms | parallel per interval length (common pool) 52 ms | equal true
```

### 2.2 Listing 5.4 — C++23

```cpp
// dp_patterns.cpp - interval DP with reconstruction, tree DP with rerooting (iterative), digit DP with a leading-zero flag.
#include <algorithm>
#include <array>
#include <atomic>
#include <cctype>
#include <chrono>
#include <cstdint>
#include <deque>
#include <limits>
#include <print>
#include <string>
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

class SpinBarrier {
public:
    explicit SpinBarrier(int n) : n_(n) {}
    void arrive_and_wait() {
        int gen = gen_.load();
        if (count_.fetch_add(1) + 1 == n_) count_.store(0), gen_.fetch_add(1);
        else
            while (gen_.load() == gen) {}
    }

private:
    int n_;
    std::atomic<int> count_{0}, gen_{0};
};

// ======================================================================= 1. interval DP: matrix-chain order
// Matrices M_i are dims[i] x dims[i+1]. cost[i][j] = cheapest product of M_i..M_j; split[i][j] = where. O(n^3).
struct MatrixChain {
    std::vector<std::vector<i64>> cost;
    std::vector<Vec> split;

    MatrixChain(const Vec& dims, int threads) {
        int n = static_cast<int>(dims.size()) - 1;
        cost.assign(U(n), std::vector<i64>(U(n)));
        split.assign(U(n), Vec(U(n)));
        auto solve = [&](int i, int len) {
            int j = i + len - 1;
            i64 best = std::numeric_limits<i64>::max();
            for (int k = i; k < j; ++k) {
                i64 c = cost[U(i)][U(k)] + cost[U(k + 1)][U(j)] + i64{dims[U(i)]} * dims[U(k + 1)] * dims[U(j + 1)];
                if (c < best) best = c, split[U(i)][U(j)] = k;
            }
            cost[U(i)][U(j)] = best;
        };
        if (threads <= 1) {
            for (int len = 2; len <= n; ++len)
                for (int i = 0; i + len - 1 < n; ++i) solve(i, len);
            return;
        }
        SpinBarrier barrier(threads);  // all intervals of one length depend only on shorter ones
        std::vector<std::jthread> pool;
        for (int t = 0; t < threads; ++t)
            pool.emplace_back([&, t] {
                for (int len = 2; len <= n; ++len) {
                    for (int i = t; i + len - 1 < n; i += threads) solve(i, len);
                    barrier.arrive_and_wait();
                }
            });
    }

    std::string order(int i, int j) const {  // reconstruction from the split table
        if (i == j) return "M" + std::to_string(i);
        int k = split[U(i)][U(j)];
        return "(" + order(i, k) + " " + order(k + 1, j) + ")";
    }
};

i64 chain_oracle(const Vec& dims, int i, int j) {  // every parenthesization, exponential
    if (i == j) return 0;
    i64 best = std::numeric_limits<i64>::max();
    for (int k = i; k < j; ++k)
        best = std::min(best, chain_oracle(dims, i, k) + chain_oracle(dims, k + 1, j) + i64{dims[U(i)]} * dims[U(k + 1)] * dims[U(j + 1)]);
    return best;
}

i64 evaluate(const Vec& dims, const std::string& order) {  // re-derive the cost of a printed order
    std::vector<std::array<i64, 3>> st;  // (rows, cols, cost)
    for (std::size_t p = 0; p < order.size(); ++p) {
        if (order[p] == 'M') {
            std::size_t q = p + 1;
            while (q < order.size() && std::isdigit(static_cast<unsigned char>(order[q]))) ++q;
            int idx = std::stoi(order.substr(p + 1, q - p - 1));
            st.push_back({dims[U(idx)], dims[U(idx + 1)], 0});
            p = q - 1;
        } else if (order[p] == ')') {
            auto right = st.back();
            st.pop_back();
            auto left = st.back();
            st.pop_back();
            st.push_back({left[0], right[1], left[2] + right[2] + left[0] * left[1] * right[1]});
        }
    }
    return st.back()[2];
}

// ======================================================================= 2. tree DP with rerooting
// LC 834 + eccentricity for EVERY vertex in O(n): one bottom-up pass, one top-down pass, no recursion.
std::array<std::vector<i64>, 2> reroot(int n, const Vec& eu, const Vec& ev) {
    Vec start(U(n) + 1), adj(2 * U(n - 1));
    for (std::size_t e = 0; e < eu.size(); ++e) ++start[U(eu[e]) + 1], ++start[U(ev[e]) + 1];
    for (std::size_t i = 0; i < U(n); ++i) start[i + 1] += start[i];
    Vec fill(start.begin(), start.end() - 1);
    for (std::size_t e = 0; e < eu.size(); ++e) adj[U(fill[U(eu[e])]++)] = ev[e], adj[U(fill[U(ev[e])]++)] = eu[e];
    Vec order{0}, parent(U(n), -1);
    parent[0] = 0;
    for (std::size_t h = 0; h < order.size(); ++h)
        for (int u = order[h], k = start[U(u)]; k < start[U(u) + 1]; ++k)
            if (parent[U(adj[U(k)])] == -1) parent[U(adj[U(k)])] = u, order.push_back(adj[U(k)]);
    parent[0] = -1;
    std::vector<i64> size(U(n)), down(U(n)), sum(U(n));
    Vec best1(U(n)), best2(U(n)), via(U(n), -1), up(U(n));
    for (std::size_t i = U(n); i-- > 0;) {  // bottom-up: subtree sizes, distance sums, two longest downward paths
        int u = order[i];
        ++size[U(u)];
        if (int p = parent[U(u)]; p >= 0) {
            size[U(p)] += size[U(u)];
            down[U(p)] += down[U(u)] + size[U(u)];
            int d = best1[U(u)] + 1;
            if (d > best1[U(p)]) best2[U(p)] = best1[U(p)], best1[U(p)] = d, via[U(p)] = u;
            else if (d > best2[U(p)]) best2[U(p)] = d;
        }
    }
    sum[0] = down[0];
    for (std::size_t i = 1; i < U(n); ++i) {  // top-down: move the root across one edge at a time
        int u = order[i], p = parent[U(u)];
        sum[U(u)] = sum[U(p)] - size[U(u)] + (n - size[U(u)]);  // size[u] nodes get 1 closer, the rest 1 farther
        up[U(u)] = 1 + std::max(up[U(p)], via[U(p)] == u ? best2[U(p)] : best1[U(p)]);
    }
    std::vector<i64> ecc(U(n));
    for (std::size_t u = 0; u < U(n); ++u) ecc[u] = std::max(best1[u], up[u]);
    return {sum, ecc};
}

std::array<std::vector<i64>, 2> reroot_oracle(int n, const Vec& eu, const Vec& ev) {
    std::vector<i64> sum(U(n)), ecc(U(n));
    for (int s = 0; s < n; ++s) {
        Vec dist(U(n), -1);
        dist[U(s)] = 0;
        std::deque<int> q{s};
        while (!q.empty()) {
            int u = q.front();
            q.pop_front();
            for (std::size_t e = 0; e < eu.size(); ++e) {
                int v = eu[e] == u ? ev[e] : ev[e] == u ? eu[e] : -1;
                if (v >= 0 && dist[U(v)] == -1) dist[U(v)] = dist[U(u)] + 1, q.push_back(v);
            }
        }
        for (int d : dist) sum[U(s)] += d, ecc[U(s)] = std::max<i64>(ecc[U(s)], d);
    }
    return {sum, ecc};
}

// ======================================================================= 3. digit DP
// Count x in [0, limit] with no two equal neighbouring digits and digit sum divisible by k. State after a prefix:
// (sum mod k, last digit or 10 = none, started?). Without `started`, leading zeros count as digits and 7 = "007" fails.
using Table = std::vector<std::array<std::array<i64, 2>, 11>>;
void add_digit(Table& next, int s, int last, bool started, int d, int k, i64 c, bool track_started) {
    bool now_started = started || d != 0 || !track_started;
    if (!now_started) return void(next[U(s)][10][0] += c);  // still in the leading zeros
    if (last != 10 && last == d) return;                    // equal neighbours: rejected
    next[U((s + d) % k)][U(d)][1] += c;
}

i64 digit_count(i64 limit, int k, bool track_started) {
    if (limit < 0) return 0;
    std::string ds = std::to_string(limit);
    Table free(U(k));
    int tight_sum = 0, tight_last = 10;
    bool tight_started = false, tight_alive = true;
    for (char ch : ds) {
        Table next(U(k));
        for (int s = 0; s < k; ++s)
            for (int last = 0; last <= 10; ++last)
                for (int st = 0; st < 2; ++st)
                    if (i64 c = free[U(s)][U(last)][U(st)]; c != 0)
                        for (int d = 0; d <= 9; ++d) add_digit(next, s, last, st == 1, d, k, c, track_started);
        if (tight_alive) {
            int bound = ch - '0';
            for (int d = 0; d < bound; ++d) add_digit(next, tight_sum, tight_last, tight_started, d, k, 1, track_started);
            bool started = tight_started || bound != 0 || !track_started;
            if (started && tight_last != 10 && tight_last == bound) tight_alive = false;
            else if (started) tight_sum = (tight_sum + bound) % k, tight_last = bound, tight_started = true;
        }
        free = std::move(next);
    }
    i64 total = 0;
    for (int last = 0; last <= 10; ++last) total += free[0][U(last)][1] + free[0][U(last)][0];
    if (tight_alive && tight_sum % k == 0) ++total;
    return total;
}

i64 digit_oracle(i64 limit, int k) {
    i64 c = 0;
    for (i64 x = 0; x <= limit; ++x) {
        std::string s = std::to_string(x);
        bool ok = true;
        int sum = 0;
        for (std::size_t i = 0; i < s.size(); ++i) {
            sum += s[i] - '0';
            if (i > 0 && s[i] == s[i - 1]) ok = false;
        }
        c += ok && sum % k == 0;
    }
    return c;
}

int main() {
    SplitMix64 r{121};
    constexpr int trials = 1'500;
    int ok_chain = 0, ok_reroot = 0;
    for (int t = 0; t < trials; ++t) {
        int n = 1 + r.next_int(8);
        Vec dims(U(n) + 1);
        for (int& d : dims) d = 1 + r.next_int(30);
        MatrixChain mc(dims, 1);
        i64 want = chain_oracle(dims, 0, n - 1);
        ok_chain += mc.cost[0][U(n - 1)] == want && evaluate(dims, mc.order(0, n - 1)) == want;
        int tn = 1 + r.next_int(30);
        Vec eu(U(tn - 1)), ev(U(tn - 1));
        for (int v = 1; v < tn; ++v) eu[U(v - 1)] = r.next_int(v), ev[U(v - 1)] = v;
        ok_reroot += reroot(tn, eu, ev) == reroot_oracle(tn, eu, ev);
    }
    std::println("1. matrix chain: optimal cost == all parenthesizations, and the printed order re-evaluates to it: {}/{}", ok_chain, trials);
    Vec demo = {30, 35, 15, 5, 10, 20, 25};
    MatrixChain mc(demo, 1);
    std::println("   CLRS dims [30, 35, 15, 5, 10, 20, 25] -> {} multiplications via {}", mc.cost[0][5], mc.order(0, 5));
    std::println("2. rerooting: sum of distances AND eccentricity for every vertex == BFS from every vertex: {}/{}", ok_reroot, trials);

    int ok_digit = 0, cp_digit = 0;
    for (i64 lim : {i64{0}, i64{9}, i64{10}, i64{99}, i64{100}, i64{777}, i64{1'000}, i64{54'321}, i64{99'999}, i64{100'000}})
        for (int k = 1; k <= 9; ++k) {
            i64 want = digit_oracle(lim, k);
            ok_digit += digit_count(lim, k, true) == want;
            cp_digit += digit_count(lim, k, false) == want;
        }
    std::println("3. digit DP (no equal neighbours, digit sum % k == 0), 90 (limit, k) pairs vs brute force: with started flag {}/90 |"
                 " leading zeros as digits {}/90", ok_digit, cp_digit);
    std::println("   limit = INT64_MAX ({}), k = 7: {} numbers, counted in 19 digit steps", std::numeric_limits<i64>::max(),
                 digit_count(std::numeric_limits<i64>::max(), 7, true));

    constexpr int n = 700;
    Vec dims(U(n) + 1);
    for (int& d : dims) d = 1 + r.next_int(100);
    using clock = std::chrono::steady_clock;
    auto t0 = clock::now();
    i64 seq = MatrixChain(dims, 1).cost[0][U(n - 1)];
    auto t1 = clock::now();
    i64 par = MatrixChain(dims, 8).cost[0][U(n - 1)];
    auto t2 = clock::now();
    auto ms = [](clock::duration d) { return std::chrono::duration_cast<std::chrono::milliseconds>(d).count(); };
    std::println("A. matrix chain n={} ({} split evaluations, one measured run): sequential {} ms | 8 threads, one spin barrier per"
                 " interval length {} ms | equal {}", n, i64{n} * n * n / 6, ms(t1 - t0), ms(t2 - t1), seq == par);
}
```

**Output, GCC 16.2 (verified; the last line is one measured run):**

```text
1. matrix chain: optimal cost == all parenthesizations, and the printed order re-evaluates to it: 1500/1500
   CLRS dims [30, 35, 15, 5, 10, 20, 25] -> 15125 multiplications via ((M0 (M1 M2)) ((M3 M4) M5))
2. rerooting: sum of distances AND eccentricity for every vertex == BFS from every vertex: 1500/1500
3. digit DP (no equal neighbours, digit sum % k == 0), 90 (limit, k) pairs vs brute force: with started flag 90/90 | leading zeros as digits 18/90
   limit = INT64_MAX (9223372036854775807), k = 7: 200953421551707992 numbers, counted in 19 digit steps
A. matrix chain n=700 (57166666 split evaluations, one measured run): sequential 78 ms | 8 threads, one spin barrier per interval length 26 ms | equal true
```

**Output, Clang 21.1 (verified; the last line is one measured run):**

```text
1. matrix chain: optimal cost == all parenthesizations, and the printed order re-evaluates to it: 1500/1500
   CLRS dims [30, 35, 15, 5, 10, 20, 25] -> 15125 multiplications via ((M0 (M1 M2)) ((M3 M4) M5))
2. rerooting: sum of distances AND eccentricity for every vertex == BFS from every vertex: 1500/1500
3. digit DP (no equal neighbours, digit sum % k == 0), 90 (limit, k) pairs vs brute force: with started flag 90/90 | leading zeros as digits 18/90
   limit = INT64_MAX (9223372036854775807), k = 7: 200953421551707992 numbers, counted in 19 digit steps
A. matrix chain n=700 (57166666 split evaluations, one measured run): sequential 77 ms | 8 threads, one spin barrier per interval length 25 ms | equal true
```

---

## 3. What the results show

* **Interval DP with reconstruction, checked by re-evaluation.** The printed parenthesization is parsed back and its multiplication count recomputed. It equals the optimum from exhaustive enumeration in all 1,500 cases, and the CLRS textbook example gives 15,125 with `((M0 (M1 M2)) ((M3 M4) M5))`.
* **Rerooting for every vertex** matches BFS from every vertex on all 1,500 random trees, for both the distance sum and the eccentricity. Both passes are array loops over a BFS order, so there's no recursion.
* **The `started` flag is the difference between 90/90 and 18/90.** The leading-zero bug isn't an edge case: most small numbers have implicit leading zeros.
* **Interval DP parallelizes by length:** n = 700 (57 M split evaluations). Java: 117–122 ms sequential vs 46–52 ms with the common pool. C++: 77–93 ms vs 24–28 ms with 8 persistent threads and one spin barrier per length (699 barriers). That's 2.3–3.8×. Each length's work shrinks as lengths grow, so the last few hundred barriers synchronize almost no work.

---

## 4. The last 10 minutes: Extensions A, B and C

### 4.1 Extension A — "64 threads"

* **Interval DP:** parallel by length (measured). For very large n, tile the (i, j) table so each task computes a block of intervals; short lengths have many intervals, long lengths few, so the parallelism fades toward the end.
* **Rerooting:** both passes are prefix-scan-like over a BFS order. Parallelize by levels: all vertices of one depth level are independent in each pass. Or let each thread own whole subtrees and combine at the top.
* **Digit DP** is microseconds per query; parallelize across queries.

### 4.2 Extension B — "the tree has 10⁹ vertices on disk"

The two passes are a backward scan and a forward scan over a BFS order, with per-vertex arrays (size, down, best1, best2, via) as columns. Store them as files and stream them. The only random access is reading the parent's value in the top-down pass. Laying vertices out in BFS order makes a parent's block near its children's for most of the tree. Digit DP needs O(digits × states) memory regardless of N.

### 4.3 Extension C — "the tree is spread across 100 machines"

* **Subtree summaries compose.** A machine that owns a subtree sends its root's `(size, down, best1, best2)` upward. The parent combines children's summaries exactly as in the down pass. The up pass sends each subtree its "everything outside me" summary. Two rounds of messages along the tree of machines, independent of the number of vertices.
* **Interval DP across machines:** partition by interval start, and ship each length's results to the machines that need them as shorter sub-intervals. Communication grows quickly, so it pays only when the per-interval work is heavy.
* **Digit DP across machines:** split [0, N] into ranges `[a, b)` and count each with `count(b − 1) − count(a − 1)`. Counts add, so it's trivially distributed.

---

## 5. Failure modes

| # | Failure | Symptom | Prevention |
|---|---|---|---|
| F1 | Cost without the split table | Can't produce the solution | Store splits; reconstruct; re-evaluate in tests |
| F2 | Re-rooting with only the best child | Wrong eccentricity when the best path goes through the new root | Keep the top two (and which child) |
| F3 | O(n) per root | O(n²) total | Two-pass rerooting |
| F4 | Recursive tree DP | Stack overflow on paths | BFS order, forwards and backwards |
| F5 | Leading zeros treated as digits | Wrong counts (18/90 correct) | `started` flag |
| F6 | Tight handled by string memo keys | Slow; allocation-heavy | Walk the bound's digits; dense arrays |
| F7 | Off-by-one at range bounds | `count(b) − count(a)` excludes a | `count(b) − count(a − 1)`; handle `a = 0` |

---

## 6. Bar-raiser chains

<details><summary><b>Q1 · "Matrix chain multiplication: and which order?"</b></summary>

**Initial Prompt.** Return the minimum cost and the parenthesization.

**L5 Answer.** O(n³) DP returning the cost.

**Why L5 Stalls.** No reconstruction, so the business question ("in which order do we join these tables?") stays unanswered.

**L7 Answer.** "State: cheapest product of matrices i..j. The last multiplication splits it at some k, so the recurrence is the min over k of left + right + the boundary product. I'd fill by increasing length, record the best k per interval, and rebuild the order recursively from the split table. Recursion depth is at most n here. To test it, I parse the printed order back and recompute its cost; it must equal the optimum. That's exactly a query planner's join-ordering problem in its simplest form."
</details>

<details><summary><b>Q2 · "Sum of distances from every node to all others."</b></summary>

**Initial Prompt.** LeetCode 834, n = 3 × 10⁴.

**L5 Answer.** BFS from every node: O(n²).

**Why L5 Stalls.** 9 × 10⁸ steps; and it doesn't generalize.

**L7 Answer.** "Rerooting. First a post-order pass from an arbitrary root computes subtree sizes and the sum of distances within each subtree. Then a pre-order pass moves the root across each edge: `sum[child] = sum[parent] − size[child] + (n − size[child])`, because the child's subtree gets one step closer and the rest one step farther. O(n) total, two array passes over a BFS order, no recursion."
</details>

<details><summary><b>Q3 · "Now the farthest node from every node."</b></summary>

**Initial Prompt.** Eccentricity for every vertex.

**L5 Answer.** Reroots with the single longest downward path.

**Why L5 Stalls.** When moving the root to the child that *gave* the parent its longest path, that path can't be reused, and the answer is wrong.

**L7 Answer.** "Max has no inverse, so I can't subtract the child's contribution. I keep the two longest downward paths per node and which child produced the longest. For a child u, the best path leaving through its parent is `1 + max(up[p], best1[p])` if u isn't the best child, else `1 + max(up[p], best2[p])`. Eccentricity is `max(best1[u], up[u])`. For operations with no 'second best' trick, prefix and suffix combinations over the children do the exclusion."
</details>

<details><summary><b>Q4 · "How many numbers up to 10¹⁸ have no two equal adjacent digits?"</b></summary>

**Initial Prompt.** Digit DP.

**L5 Answer.** Digit DP over (position, last digit, tight), with leading zeros as zeros.

**Why L5 Stalls.** A number like 7 becomes 000…07, with equal neighbours. Measured, the variant is wrong on 72 of 90 test cases.

**L7 Answer.** "State per position: last digit, a `started` flag (leading zeros aren't digits), and tight against the bound. I walk the bound's digits so only one tight path exists, and keep dense counts for the free paths. That's about 20 positions × 11 last digits × 2 flags, microseconds even for 10¹⁸. I'd verify against brute force up to 10⁵ for many bounds, including 0, 9, 10, 99, 100 and boundaries like 54,321."
</details>

<details><summary><b>Q5 · "Count such numbers in a range [a, b]."</b></summary>

**Initial Prompt.** Range version.

**L5 Answer.** `count(b) − count(a)`.

**Why L5 Stalls.** Off by one: it excludes a itself.

**L7 Answer.** "`count(b) − count(a − 1)`, with `count(−1) = 0`. Each count is a prefix query from 0, so ranges compose. That's also how I'd distribute it: split [0, N] into chunks and sum per-chunk counts."
</details>

<details><summary><b>Q6 · "Your interval DP is O(n³). Can it run faster on 8 cores?"</b></summary>

**Initial Prompt.** Extension A.

**L5 Answer.** "Parallelize the innermost loop over k."

**Why L5 Stalls.** The k loop is a min-reduction of size up to n; parallelizing it creates tiny tasks and contention on the result.

**L7 Answer.** "All intervals of the same length depend only on shorter ones, so each length is a parallel batch, with one barrier per length. I measured 2.3–3.8× on 8 threads at n = 700. Late lengths have very few intervals, so parallelism fades. Persistent threads with a cheap spin barrier matter, because there are about n barriers."
</details>

<details><summary><b>Q7 · "The tree is the company org chart, spread across regional databases."</b></summary>

**Initial Prompt.** Extension C for rerooting.

**L5 Answer.** "Collect the whole tree centrally."

**Why L5 Stalls.** Works for small trees; ignores that summaries suffice.

**L7 Answer.** "The down pass only needs each region's root summary (size, sum of distances, two longest depths), so regions send summaries up the region tree. The up pass sends each region its 'outside' summary. Two message rounds along the region hierarchy, no matter how many employees, and every region then finishes its own vertices locally."
</details>

<details><summary><b>Q8 · "How do you know the rerooting formula is right?"</b></summary>

**Initial Prompt.** Verification.

**L5 Answer.** "I traced a small example."

**Why L5 Stalls.** Rerooting bugs hide in specific shapes: paths, stars, and the best-child case.

**L7 Answer.** "BFS from every vertex is an O(n²) oracle that's obviously right. I compare on random trees up to 30 vertices, generated as random recursive trees, so I get paths, stars and bushy trees. 1,500 trees, both the distance sum and the eccentricity, every vertex. The second-best-child case comes up constantly in such trees, so a single-best bug fails immediately."
</details>

---

## 7. Checklist

* [ ] Interval DP: state = interval, order = length; keep splits; reconstruct and re-evaluate.
* [ ] Rerooting: down pass (sizes, aggregates, top-two), up pass (O(1) per edge); iterative.
* [ ] Exclusion without an inverse: top-two, or prefix/suffix combinations.
* [ ] Digit DP: walk the bound; `started` flag; dense state arrays; `count(b) − count(a − 1)`.
* [ ] Extension A: parallel by interval length or tree level; persistent threads.
* [ ] Extension B: rerooting as two sequential scans over BFS-ordered columns.
* [ ] Extension C: subtree summaries up, outside summaries down; digit-DP ranges sum.

---

## 8. References

* T. H. Cormen et al., *Introduction to Algorithms*, 4th ed.: matrix-chain multiplication and optimal BSTs (dynamic programming chapter).
* D. E. Knuth, *Optimum Binary Search Trees*, Acta Informatica 1, 1971 — DOI 10.1007/BF00264289
* cp-algorithms: [Knuth's optimization](https://cp-algorithms.com/dynamic_programming/knuth-optimization.html)
* LeetCode anchors: [312 Burst Balloons](https://leetcode.com/problems/burst-balloons/), [834 Sum of Distances in Tree](https://leetcode.com/problems/sum-of-distances-in-tree/), [902 Numbers At Most N Given Digit Set](https://leetcode.com/problems/numbers-at-most-n-given-digit-set/), [1000 Minimum Cost to Merge Stones](https://leetcode.com/problems/minimum-cost-to-merge-stones/)

*Folder 05:* [01 — state design, space, reconstruction](01-dp-state-design-space-optimization-and-reconstructing-optimal-paths.md) · [03 — bitmask, SOS, monotonic-queue and D&C DP](03-bitmask-dp-sos-dp-monotonic-queue-dp-and-divide-and-conquer-dp.md)
