# Bitmask DP, SOS DP, Monotonic-Queue DP and Divide-and-Conquer DP

> **Folder 05 · File 3 of 3** — four DP accelerations, each valid only under a structural precondition, with the precondition **tested by breaking it**. Sets as bitmasks (Held–Karp), subset sums in O(n 2ⁿ), sliding-window transitions in O(1), and monotone optimal splits in O(n log n) per layer.
> **Languages:** Java 21 (`--release 21 -Xlint:all -Werror`, JDK 25.0.4.1) and C++23 (GCC 16.2 and Clang 21.1, `-O2`, warnings as errors).

| Listing | File | What it proves |
|---|---|---|
| 5.5 | `DpOptimizations.java` | Held–Karp TSP with tour reconstruction vs all permutations; SOS DP vs submask enumeration, where the `sub > 0` loop is right on only 3/400; LC 1425 monotonic-queue DP vs O(nk) vs brute force; D&C optimization exact on non-negative data and **wrong on 207/400** when negatives break the quadrangle inequality. Speedups of 33–300×; SOS parallel per bit layer |
| 5.6 | `dp_optimizations.cpp` | The same; identical correctness counts |

**Verification.** Both listings were extracted from this file, compiled and run. Everything is **Output (verified)** except the two constants lines (**one measured run**).

---

## 0. Orientation

| Contest habit | What breaks | L7 replacement |
|---|---|---|
| `for (s = m; s > 0; s = (s-1) & m)` | Skips the empty submask: wrong on 99% of instances here | Handle `s = 0` explicitly, or use SOS DP |
| Submask enumeration for all masks | 3ⁿ: 43 M at n = 16, 3.1 × 10¹⁰ at n = 22 | SOS DP: n × 2ⁿ |
| "This DP has the D&C/Knuth property" by pattern-matching | Silently wrong answers when the cost violates the quadrangle inequality | State the property, check it, and test on inputs that break it |
| O(nk) window maximum inside a DP | 100–130 ms vs 2–3 ms (measured) | Monotonic deque (Folder 02) inside the DP loop |
| `dp[1 << 20][20]` of `long` without thinking | 160 MB; doesn't fit at n = 25 | Memory = 2ⁿ × n × 8 B; meet-in-the-middle or approximation beyond ~24 |

---

## 1. First principles

### 1.1 Bitmask DP

When the state must remember **which** elements of a small set have been used, a bitmask is the state. Held–Karp TSP: `dp[mask][v]` is the cheapest path from city 0 visiting exactly `mask` and ending at v. Transitions add one unvisited city. That's O(2ⁿ n²) time against n! for brute force, but **O(2ⁿ n) memory**, which is the real wall: n = 20 needs 20 M states of 8 bytes (160 MB), and n = 25 needs 6.7 GB. Reconstruction stores the predecessor per state and walks back from the best final state, removing one city per step.

### 1.2 SOS DP (sum over subsets)

`F[mask] = Σ a[sub]` over all subsets `sub ⊆ mask`. Submask enumeration costs Σ over masks of 2^popcount = 3ⁿ. SOS treats the mask as an n-dimensional 0/1 hypercube and takes **prefix sums one dimension at a time**: after processing bit b, `f[mask]` holds the sum over submasks that differ from mask only in bits ≤ b. That's n × 2ⁿ. Within one bit layer, every pair `(mask, mask ^ bit)` is disjoint from every other pair, so a layer is embarrassingly parallel. The same structure gives superset sums, subset-zeta and Möbius transforms, and "OR convolution".

### 1.3 Monotonic-queue DP

When a transition is `dp[i] = a[i] + max(dp[j] for j in a sliding window)`, as in LeetCode 1425 (indices at most k apart), the inner max is Folder 02's sliding-window maximum. A monotonic deque of indices, decreasing in `dp`, turns O(nk) into O(n). The precondition: the window's left edge moves monotonically to the right.

### 1.4 Divide-and-conquer optimization

For layered DPs `dp[g][j] = min over i < j of dp[g−1][i] + C(i, j)`, let `opt(j)` be the minimizing i. If `opt(j) ≤ opt(j + 1)` (**monotone optimal splits**), then computing `opt(mid)` for the middle j bounds the search range for both halves. Total work per layer is O(n log n) instead of O(n²). Monotonicity holds when C satisfies the **quadrangle inequality** `C(a, c) + C(b, d) ≤ C(a, d) + C(b, c)` for `a ≤ b ≤ c ≤ d`. For "partition into g groups minimizing Σ (group sum)²", C(i, j) = (S_j − S_i)² satisfies it when the prefix sums are monotone, i.e. **all values non-negative**. With negative values the optimization still runs, still returns a number, and is wrong on about half of the instances: 207 of 400 here.

---

## 2. The listings

### 2.1 Listing 5.5 — Java

```java
// DpOptimizations.java - bitmask TSP, SOS DP, monotonic-queue DP, divide-and-conquer DP: each with its precondition tested.
import java.util.Arrays;
import java.util.stream.IntStream;

public final class DpOptimizations {

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

    // ===================================================================== 1. bitmask DP: TSP (Held-Karp)
    /** dp[mask][v] = cheapest path from 0 visiting exactly `mask`, ending at v. O(2^n n^2) time, O(2^n n) memory. */
    static int[] tsp(long[][] d, long[] cost) {
        int n = d.length, full = 1 << n;
        long[][] dp = new long[full][n];
        int[][] prev = new int[full][n];
        for (long[] row : dp) Arrays.fill(row, INF);
        dp[1][0] = 0;
        for (int mask = 1; mask < full; mask += 2)          // only masks containing the start city 0
            for (int v = 0; v < n; v++) {
                if (dp[mask][v] == INF || (mask >> v & 1) == 0) continue;
                for (int u = 0; u < n; u++) {
                    if ((mask >> u & 1) == 1) continue;
                    long c = dp[mask][v] + d[v][u];
                    if (c < dp[mask | 1 << u][u]) { dp[mask | 1 << u][u] = c; prev[mask | 1 << u][u] = v; }
                }
            }
        long best = INF;
        int last = 0;
        for (int v = 1; v < n; v++) if (dp[full - 1][v] + d[v][0] < best) { best = dp[full - 1][v] + d[v][0]; last = v; }
        if (n == 1) { cost[0] = 0; return new int[] {0}; }
        int[] tour = new int[n];
        for (int mask = full - 1, v = last, k = n - 1; k >= 0; k--) { tour[k] = v; int p = prev[mask][v]; mask ^= 1 << v; v = p; }
        cost[0] = best;
        return tour;
    }

    static long tspOracle(long[][] d, int[] perm, int k, boolean[] used) {  // all permutations starting at city 0
        int n = d.length;
        if (k == n) { long c = 0; for (int i = 0; i < n; i++) c += d[perm[i]][perm[(i + 1) % n]]; return c; }
        long best = INF;
        for (int v = 1; v < n; v++) {
            if (used[v]) continue;
            used[v] = true; perm[k] = v;
            best = Math.min(best, tspOracle(d, perm, k + 1, used));
            used[v] = false;
        }
        return best;
    }

    // ===================================================================== 2. SOS DP: sum over subsets
    /** F[mask] = sum of a[sub] for every sub of mask. Fold in one bit at a time: O(n 2^n) instead of O(3^n). */
    static long[] sos(long[] a, int bits, boolean parallel) {
        long[] f = a.clone();
        for (int b = 0; b < bits; b++) {
            final int bit = 1 << b;
            IntStream masks = IntStream.range(0, f.length);
            (parallel ? masks.parallel() : masks).forEach(mask -> { if ((mask & bit) != 0) f[mask] += f[mask ^ bit]; });
        }
        return f;
    }

    /** Submask enumeration, O(3^n) total. includeEmpty=false is the classic `for (s = m; s > 0; s = (s-1) & m)` slip. */
    static long[] subsetSumsNaive(long[] a, boolean includeEmpty) {
        long[] f = new long[a.length];
        for (int mask = 0; mask < a.length; mask++) {
            long s = 0;
            for (int sub = mask; sub > 0; sub = (sub - 1) & mask) s += a[sub];
            f[mask] = s + (includeEmpty ? a[0] : 0);
        }
        return f;
    }

    // ===================================================================== 3. monotonic-queue DP (LC 1425)
    /** dp[i] = a[i] + max(0, max dp[i-k..i-1]). The window max comes from a monotonic deque: O(n) total. */
    static long constrainedSubsetSum(int[] a, int k) {
        long[] dp = new long[a.length];
        int[] dq = new int[a.length];
        int head = 0, tail = 0;
        long best = Long.MIN_VALUE;
        for (int i = 0; i < a.length; i++) {
            if (head < tail && dq[head] < i - k) head++;
            dp[i] = a[i] + Math.max(0, head < tail ? dp[dq[head]] : 0);
            while (head < tail && dp[dq[tail - 1]] <= dp[i]) tail--;
            dq[tail++] = i;
            best = Math.max(best, dp[i]);
        }
        return best;
    }

    static long constrainedNaive(int[] a, int k) {  // O(n k)
        long[] dp = new long[a.length];
        long best = Long.MIN_VALUE;
        for (int i = 0; i < a.length; i++) {
            long m = 0;
            for (int j = Math.max(0, i - k); j < i; j++) m = Math.max(m, dp[j]);
            dp[i] = a[i] + m;
            best = Math.max(best, dp[i]);
        }
        return best;
    }

    // ===================================================================== 4. divide-and-conquer optimization
    /** Split a into g contiguous groups minimizing sum of (group sum)^2. Naive layered DP: O(g n^2). */
    static long partitionNaive(long[] prefix, int g) {
        int n = prefix.length - 1;
        long[] prev = new long[n + 1], cur = new long[n + 1];
        Arrays.fill(prev, INF);
        prev[0] = 0;
        for (int layer = 1; layer <= g; layer++) {
            Arrays.fill(cur, INF);
            for (int j = 1; j <= n; j++)
                for (int i = layer - 1; i < j; i++)
                    if (prev[i] < INF) cur[j] = Math.min(cur[j], prev[i] + sq(prefix[j] - prefix[i]));
            long[] t = prev; prev = cur; cur = t;
        }
        return prev[n];
    }

    static long sq(long x) { return x * x; }

    /**
     * If the cost satisfies the quadrangle inequality, the best split point opt(j) is non-decreasing in j, so the
     * middle j's optimum bounds the search for both halves: O(g n log n). (S_j - S_i)^2 satisfies it when the prefix
     * sums are monotone -- i.e. when every value is non-negative. That is a precondition, not a detail.
     */
    static long partitionDivideConquer(long[] prefix, int g) {
        int n = prefix.length - 1;
        long[] prev = new long[n + 1], cur = new long[n + 1];
        Arrays.fill(prev, INF);
        prev[0] = 0;
        for (int layer = 1; layer <= g; layer++) {
            Arrays.fill(cur, INF);
            solve(prev, cur, prefix, 1, n, layer - 1, n - 1);
            long[] t = prev; prev = cur; cur = t;
        }
        return prev[n];
    }

    private static void solve(long[] prev, long[] cur, long[] prefix, int lo, int hi, int optLo, int optHi) {
        // recursion depth is log2(n): the j-range halves at every level
        if (lo > hi) return;
        int mid = (lo + hi) >>> 1, opt = optLo;
        long best = INF;
        for (int i = optLo; i <= Math.min(mid - 1, optHi); i++) {
            if (prev[i] == INF) continue;
            long c = prev[i] + sq(prefix[mid] - prefix[i]);
            if (c < best) { best = c; opt = i; }
        }
        cur[mid] = best;
        solve(prev, cur, prefix, lo, mid - 1, optLo, opt);
        solve(prev, cur, prefix, mid + 1, hi, opt, optHi);
    }

    static long[] prefix(long[] a) {
        long[] p = new long[a.length + 1];
        for (int i = 0; i < a.length; i++) p[i + 1] = p[i] + a[i];
        return p;
    }

    public static void main(String[] args) {
        SplitMix64 r = new SplitMix64(131);
        int trials = 400, okTsp = 0;
        for (int t = 0; t < trials; t++) {
            int n = 1 + r.nextInt(8);
            long[][] d = new long[n][n];
            for (int i = 0; i < n; i++) for (int j = 0; j < n; j++) d[i][j] = i == j ? 0 : 1 + r.nextInt(100);
            long[] cost = new long[1];
            int[] tour = tsp(d, cost);
            long tourCost = 0;
            for (int i = 0; i < n; i++) tourCost += d[tour[i]][tour[(i + 1) % n]];
            long want = n == 1 ? 0 : tspOracle(d, new int[n], 1, new boolean[n]);
            okTsp += cost[0] == want && tourCost == want && tour[0] == 0 && Arrays.stream(tour).distinct().count() == n ? 1 : 0;
        }
        System.out.printf("1. Held-Karp TSP (directed, n <= 8) vs all permutations; the reconstructed tour costs the optimum: %d/%d%n", okTsp, trials);

        int okSos = 0, cpSos = 0;
        for (int t = 0; t < trials; t++) {
            int bits = r.nextInt(9);
            long[] a = new long[1 << bits];
            for (int i = 0; i < a.length; i++) a[i] = r.nextInt(100);
            long[] want = subsetSumsNaive(a, true);
            okSos += Arrays.equals(sos(a, bits, false), want) ? 1 : 0;
            cpSos += Arrays.equals(subsetSumsNaive(a, false), want) ? 1 : 0;
        }
        System.out.printf("2. SOS DP vs submask enumeration: %d/%d | the 'sub > 0' loop that skips the empty subset: %d/%d%n",
                okSos, trials, cpSos, trials);

        int okMq = 0;
        for (int t = 0; t < trials * 5; t++) {
            int n = 1 + r.nextInt(12), k = 1 + r.nextInt(n);
            int[] a = new int[n];
            for (int i = 0; i < n; i++) a[i] = r.nextInt(21) - 10;
            long brute = Long.MIN_VALUE;                                     // every non-empty index set with gaps <= k
            for (int mask = 1; mask < 1 << n; mask++) {
                int last = -1;
                long s = 0;
                boolean ok = true;
                for (int i = 0; i < n; i++) if ((mask >> i & 1) == 1) { if (last >= 0 && i - last > k) ok = false; last = i; s += a[i]; }
                if (ok) brute = Math.max(brute, s);
            }
            okMq += constrainedSubsetSum(a, k) == brute && constrainedNaive(a, k) == brute ? 1 : 0;
        }
        System.out.printf("3. LC 1425 monotonic-queue DP == O(nk) DP == brute force over index sets: %d/%d%n", okMq, trials * 5);

        int okDc = 0, dcNeg = 0;
        for (int t = 0; t < trials; t++) {
            int n = 1 + r.nextInt(40), g = 1 + r.nextInt(Math.min(n, 6));
            long[] a = new long[n], b = new long[n];
            for (int i = 0; i < n; i++) { a[i] = r.nextInt(50); b[i] = r.nextInt(101) - 50; }
            okDc += partitionDivideConquer(prefix(a), g) == partitionNaive(prefix(a), g) ? 1 : 0;
            dcNeg += partitionDivideConquer(prefix(b), g) == partitionNaive(prefix(b), g) ? 1 : 0;
        }
        System.out.printf("4. D&C optimization vs O(g n^2): non-negative values %d/%d | values in [-50, 50] (precondition broken) %d/%d%n",
                okDc, trials, dcNeg, trials);

        int bits = 22;
        long[] a = new long[1 << bits];
        for (int i = 0; i < a.length; i++) a[i] = r.nextInt(1_000);
        int nb = 16;
        long[] small = Arrays.copyOf(a, 1 << nb);
        sos(a, bits, true);  // warm-up
        long t0 = System.nanoTime();
        long[] s1 = sos(a, bits, false);
        long t1 = System.nanoTime();
        long[] s2 = sos(a, bits, true);
        long t2 = System.nanoTime();
        long[] n1 = subsetSumsNaive(small, true);
        long t3 = System.nanoTime();
        long[] n2 = sos(small, nb, false);
        long t4 = System.nanoTime();
        System.out.printf("constants (one measured run): n=16 submask enumeration (3^16 = 43 M) %d ms vs SOS %.1f ms | n=22 SOS"
                + " sequential %d ms, parallel per bit layer %d ms | agree %b%n", (t3 - t2) / 1_000_000, (t4 - t3) / 1e6,
                (t1 - t0) / 1_000_000, (t2 - t1) / 1_000_000, Arrays.equals(s1, s2) && Arrays.equals(n1, n2));

        int n = 4_000, g = 20;
        long[] vals = new long[n];
        for (int i = 0; i < n; i++) vals[i] = r.nextInt(1_000);
        long[] p = prefix(vals);
        long u0 = System.nanoTime();
        long naive = partitionNaive(p, g);
        long u1 = System.nanoTime();
        long dc = partitionDivideConquer(p, g);
        long u2 = System.nanoTime();
        int wn = 200_000, wk = 1_000;
        int[] w = new int[wn];
        for (int i = 0; i < wn; i++) w[i] = r.nextInt(2_001) - 1_000;
        long v0 = System.nanoTime();
        long mq = constrainedSubsetSum(w, wk);
        long v1 = System.nanoTime();
        long nk = constrainedNaive(w, wk);
        long v2 = System.nanoTime();
        System.out.printf("   n=%,d, g=%d groups: O(g n^2) %d ms vs D&C %d ms (equal %b) | LC 1425 n=%,d, k=%,d: deque %.1f ms vs O(nk) %d ms (equal %b)%n",
                n, g, (u1 - u0) / 1_000_000, (u2 - u1) / 1_000_000, naive == dc, wn, wk, (v1 - v0) / 1e6, (v2 - v1) / 1_000_000, mq == nk);
    }
}
```

**Output (verified; the last two lines are one measured run):**

```text
1. Held-Karp TSP (directed, n <= 8) vs all permutations; the reconstructed tour costs the optimum: 400/400
2. SOS DP vs submask enumeration: 400/400 | the 'sub > 0' loop that skips the empty subset: 3/400
3. LC 1425 monotonic-queue DP == O(nk) DP == brute force over index sets: 2000/2000
4. D&C optimization vs O(g n^2): non-negative values 400/400 | values in [-50, 50] (precondition broken) 193/400
constants (one measured run): n=16 submask enumeration (3^16 = 43 M) 34 ms vs SOS 0.7 ms | n=22 SOS sequential 81 ms, parallel per bit layer 42 ms | agree true
   n=4,000, g=20 groups: O(g n^2) 260 ms vs D&C 2 ms (equal true) | LC 1425 n=200,000, k=1,000: deque 3.5 ms vs O(nk) 116 ms (equal true)
```

### 2.2 Listing 5.6 — C++23

```cpp
// dp_optimizations.cpp - bitmask TSP, SOS DP, monotonic-queue DP, divide-and-conquer DP: each with its precondition tested.
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <limits>
#include <print>
#include <set>
#include <thread>
#include <vector>

using i64 = std::int64_t;
using Vec = std::vector<int>;
using LVec = std::vector<i64>;
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

// ======================================================================= 1. bitmask DP: TSP (Held-Karp)
// dp[mask][v] = cheapest path from 0 visiting exactly `mask`, ending at v. O(2^n n^2) time, O(2^n n) memory.
Vec tsp(const std::vector<LVec>& d, i64& cost) {
    int n = static_cast<int>(d.size());
    std::size_t full = std::size_t{1} << n;
    std::vector<LVec> dp(full, LVec(U(n), kInf));
    std::vector<Vec> prev(full, Vec(U(n)));
    dp[1][0] = 0;
    for (std::size_t mask = 1; mask < full; mask += 2)  // only masks containing the start city 0
        for (int v = 0; v < n; ++v) {
            if (dp[mask][U(v)] == kInf || (mask >> v & 1) == 0) continue;
            for (int u = 0; u < n; ++u) {
                if (mask >> u & 1) continue;
                std::size_t next = mask | std::size_t{1} << u;
                if (i64 c = dp[mask][U(v)] + d[U(v)][U(u)]; c < dp[next][U(u)]) dp[next][U(u)] = c, prev[next][U(u)] = v;
            }
        }
    if (n == 1) return cost = 0, Vec{0};
    i64 best = kInf;
    int last = 0;
    for (int v = 1; v < n; ++v)
        if (dp[full - 1][U(v)] + d[U(v)][0] < best) best = dp[full - 1][U(v)] + d[U(v)][0], last = v;
    Vec tour(U(n));
    std::size_t mask = full - 1;
    for (int k = n - 1, v = last; k >= 0; --k) {
        tour[U(k)] = v;
        int p = prev[mask][U(v)];
        mask ^= std::size_t{1} << v;
        v = p;
    }
    cost = best;
    return tour;
}

i64 tsp_oracle(const std::vector<LVec>& d) {  // all permutations starting at city 0
    Vec perm(d.size());
    for (std::size_t i = 0; i < perm.size(); ++i) perm[i] = static_cast<int>(i);
    i64 best = kInf;
    do {
        i64 c = 0;
        for (std::size_t i = 0; i < perm.size(); ++i) c += d[U(perm[i])][U(perm[(i + 1) % perm.size()])];
        best = std::min(best, c);
    } while (std::next_permutation(perm.begin() + 1, perm.end()));
    return best;
}

// ======================================================================= 2. SOS DP: sum over subsets
// F[mask] = sum of a[sub] over sub of mask. Fold in one bit at a time: O(n 2^n) instead of O(3^n).
LVec sos(LVec f, int bits, int threads) {
    if (threads <= 1) {
        for (int b = 0; b < bits; ++b)
            for (std::size_t mask = 0; mask < f.size(); ++mask)
                if (mask >> b & 1) f[mask] += f[mask ^ (std::size_t{1} << b)];
        return f;
    }
    SpinBarrier barrier(threads);  // within one bit layer every (mask, mask^bit) pair is disjoint from the others
    std::vector<std::jthread> pool;
    for (int t = 0; t < threads; ++t)
        pool.emplace_back([&, t] {
            std::size_t lo = f.size() * U(t) / U(threads), hi = f.size() * U(t + 1) / U(threads);
            for (int b = 0; b < bits; ++b) {
                for (std::size_t mask = lo; mask < hi; ++mask)
                    if (mask >> b & 1) f[mask] += f[mask ^ (std::size_t{1} << b)];
                barrier.arrive_and_wait();
            }
        });
    pool.clear();  // join
    return f;
}

// Submask enumeration, O(3^n). include_empty=false is the classic `for (s = m; s > 0; s = (s-1) & m)` slip.
LVec subset_sums_naive(const LVec& a, bool include_empty) {
    LVec f(a.size());
    for (std::size_t mask = 0; mask < a.size(); ++mask) {
        i64 s = 0;
        for (std::size_t sub = mask; sub > 0; sub = (sub - 1) & mask) s += a[sub];
        f[mask] = s + (include_empty ? a[0] : 0);
    }
    return f;
}

// ======================================================================= 3. monotonic-queue DP (LC 1425)
i64 constrained_subset_sum(const Vec& a, int k) {
    LVec dp(a.size());
    std::vector<std::size_t> dq(a.size());
    std::size_t head = 0, tail = 0;
    i64 best = std::numeric_limits<i64>::min();
    for (std::size_t i = 0; i < a.size(); ++i) {
        if (head < tail && dq[head] + U(k) < i) ++head;
        dp[i] = a[i] + std::max<i64>(0, head < tail ? dp[dq[head]] : 0);
        while (head < tail && dp[dq[tail - 1]] <= dp[i]) --tail;
        dq[tail++] = i;
        best = std::max(best, dp[i]);
    }
    return best;
}
i64 constrained_naive(const Vec& a, int k) {  // O(n k)
    LVec dp(a.size());
    i64 best = std::numeric_limits<i64>::min();
    for (std::size_t i = 0; i < a.size(); ++i) {
        i64 m = 0;
        for (std::size_t j = i >= U(k) ? i - U(k) : 0; j < i; ++j) m = std::max(m, dp[j]);
        dp[i] = a[i] + m;
        best = std::max(best, dp[i]);
    }
    return best;
}

// ======================================================================= 4. divide-and-conquer optimization
i64 sq(i64 x) { return x * x; }

i64 partition_naive(const LVec& prefix, int g) {  // O(g n^2)
    std::size_t n = prefix.size() - 1;
    LVec prev(n + 1, kInf), cur(n + 1);
    prev[0] = 0;
    for (int layer = 1; layer <= g; ++layer) {
        std::ranges::fill(cur, kInf);
        for (std::size_t j = 1; j <= n; ++j)
            for (std::size_t i = U(layer - 1); i < j; ++i)
                if (prev[i] < kInf) cur[j] = std::min(cur[j], prev[i] + sq(prefix[j] - prefix[i]));
        std::swap(prev, cur);
    }
    return prev[n];
}

// opt(j) non-decreasing in j when the cost satisfies the quadrangle inequality -- which (S_j - S_i)^2 does only for
// monotone prefix sums, i.e. non-negative values. Recursion depth log2(n).
void solve(const LVec& prev, LVec& cur, const LVec& prefix, int lo, int hi, int opt_lo, int opt_hi) {
    if (lo > hi) return;
    int mid = lo + (hi - lo) / 2, opt = opt_lo;
    i64 best = kInf;
    for (int i = opt_lo; i <= std::min(mid - 1, opt_hi); ++i) {
        if (prev[U(i)] == kInf) continue;
        if (i64 c = prev[U(i)] + sq(prefix[U(mid)] - prefix[U(i)]); c < best) best = c, opt = i;
    }
    cur[U(mid)] = best;
    solve(prev, cur, prefix, lo, mid - 1, opt_lo, opt);
    solve(prev, cur, prefix, mid + 1, hi, opt, opt_hi);
}
i64 partition_dc(const LVec& prefix, int g) {
    int n = static_cast<int>(prefix.size()) - 1;
    LVec prev(U(n) + 1, kInf), cur(U(n) + 1);
    prev[0] = 0;
    for (int layer = 1; layer <= g; ++layer) {
        std::ranges::fill(cur, kInf);
        solve(prev, cur, prefix, 1, n, layer - 1, n - 1);
        std::swap(prev, cur);
    }
    return prev[U(n)];
}
LVec prefix_of(const LVec& a) {
    LVec p(a.size() + 1);
    for (std::size_t i = 0; i < a.size(); ++i) p[i + 1] = p[i] + a[i];
    return p;
}

int main() {
    SplitMix64 r{131};
    constexpr int trials = 400;
    int ok_tsp = 0;
    for (int t = 0; t < trials; ++t) {
        int n = 1 + r.next_int(8);
        std::vector<LVec> d(U(n), LVec(U(n)));
        for (std::size_t i = 0; i < U(n); ++i)
            for (std::size_t j = 0; j < U(n); ++j) d[i][j] = i == j ? 0 : 1 + r.next_int(100);
        i64 cost = 0;
        Vec tour = tsp(d, cost);
        i64 tour_cost = 0;
        for (std::size_t i = 0; i < U(n); ++i) tour_cost += d[U(tour[i])][U(tour[(i + 1) % U(n)])];
        i64 want = n == 1 ? 0 : tsp_oracle(d);
        ok_tsp += cost == want && tour_cost == want && tour[0] == 0 && std::set<int>(tour.begin(), tour.end()).size() == U(n);
    }
    std::println("1. Held-Karp TSP (directed, n <= 8) vs all permutations; the reconstructed tour costs the optimum: {}/{}", ok_tsp, trials);

    int ok_sos = 0, cp_sos = 0;
    for (int t = 0; t < trials; ++t) {
        int bits = r.next_int(9);
        LVec a(std::size_t{1} << bits);
        for (auto& x : a) x = r.next_int(100);
        LVec want = subset_sums_naive(a, true);
        ok_sos += sos(a, bits, 1) == want;
        cp_sos += subset_sums_naive(a, false) == want;
    }
    std::println("2. SOS DP vs submask enumeration: {}/{} | the 'sub > 0' loop that skips the empty subset: {}/{}", ok_sos, trials,
                 cp_sos, trials);

    int ok_mq = 0;
    for (int t = 0; t < trials * 5; ++t) {
        int n = 1 + r.next_int(12), k = 1 + r.next_int(n);
        Vec a(U(n));
        for (int& x : a) x = r.next_int(21) - 10;
        i64 brute = std::numeric_limits<i64>::min();
        for (unsigned mask = 1; mask < (1u << n); ++mask) {
            int last = -1;
            i64 s = 0;
            bool ok = true;
            for (int i = 0; i < n; ++i)
                if (mask >> i & 1) {
                    if (last >= 0 && i - last > k) ok = false;
                    last = i, s += a[U(i)];
                }
            if (ok) brute = std::max(brute, s);
        }
        ok_mq += constrained_subset_sum(a, k) == brute && constrained_naive(a, k) == brute;
    }
    std::println("3. LC 1425 monotonic-queue DP == O(nk) DP == brute force over index sets: {}/{}", ok_mq, trials * 5);

    int ok_dc = 0, dc_neg = 0;
    for (int t = 0; t < trials; ++t) {
        int n = 1 + r.next_int(40), g = 1 + r.next_int(std::min(n, 6));
        LVec a(U(n)), b(U(n));
        for (std::size_t i = 0; i < U(n); ++i) {
            a[i] = r.next_int(50);
            b[i] = r.next_int(101) - 50;
        }
        ok_dc += partition_dc(prefix_of(a), g) == partition_naive(prefix_of(a), g);
        dc_neg += partition_dc(prefix_of(b), g) == partition_naive(prefix_of(b), g);
    }
    std::println("4. D&C optimization vs O(g n^2): non-negative values {}/{} | values in [-50, 50] (precondition broken) {}/{}", ok_dc,
                 trials, dc_neg, trials);

    using clock = std::chrono::steady_clock;
    auto ms = [](clock::duration d) { return std::chrono::duration<double, std::milli>(d).count(); };
    constexpr int bits = 22, nb = 16;
    LVec a(std::size_t{1} << bits);
    for (auto& x : a) x = r.next_int(1'000);
    LVec small(a.begin(), a.begin() + (1 << nb));
    auto t0 = clock::now();
    LVec s1 = sos(a, bits, 1);
    auto t1 = clock::now();
    LVec s2 = sos(a, bits, 8);
    auto t2 = clock::now();
    LVec n1 = subset_sums_naive(small, true);
    auto t3 = clock::now();
    LVec n2 = sos(small, nb, 1);
    auto t4 = clock::now();
    std::println("constants (one measured run): n=16 submask enumeration (3^16 = 43 M) {:.0f} ms vs SOS {:.1f} ms | n=22 SOS sequential"
                 " {:.0f} ms, parallel per bit layer {:.0f} ms | agree {}", ms(t3 - t2), ms(t4 - t3), ms(t1 - t0), ms(t2 - t1),
                 s1 == s2 && n1 == n2);
    constexpr int n = 4'000, g = 20;
    LVec vals(U(n));
    for (auto& v : vals) v = r.next_int(1'000);
    LVec p = prefix_of(vals);
    auto u0 = clock::now();
    i64 naive = partition_naive(p, g);
    auto u1 = clock::now();
    i64 dc = partition_dc(p, g);
    auto u2 = clock::now();
    constexpr int wn = 200'000, wk = 1'000;
    Vec w(U(wn));
    for (int& x : w) x = r.next_int(2'001) - 1'000;
    auto v0 = clock::now();
    i64 mq = constrained_subset_sum(w, wk);
    auto v1 = clock::now();
    i64 nk = constrained_naive(w, wk);
    auto v2 = clock::now();
    std::println("   n={}, g={} groups: O(g n^2) {:.0f} ms vs D&C {:.0f} ms (equal {}) | LC 1425 n={}, k={}: deque {:.1f} ms vs O(nk) {:.0f} ms"
                 " (equal {})", n, g, ms(u1 - u0), ms(u2 - u1), naive == dc, wn, wk, ms(v1 - v0), ms(v2 - v1), mq == nk);
}
```

**Output, GCC 16.2 (verified; the last two lines are one measured run):**

```text
1. Held-Karp TSP (directed, n <= 8) vs all permutations; the reconstructed tour costs the optimum: 400/400
2. SOS DP vs submask enumeration: 400/400 | the 'sub > 0' loop that skips the empty subset: 3/400
3. LC 1425 monotonic-queue DP == O(nk) DP == brute force over index sets: 2000/2000
4. D&C optimization vs O(g n^2): non-negative values 400/400 | values in [-50, 50] (precondition broken) 193/400
constants (one measured run): n=16 submask enumeration (3^16 = 43 M) 23 ms vs SOS 0.6 ms | n=22 SOS sequential 77 ms, parallel per bit layer 45 ms | agree true
   n=4000, g=20 groups: O(g n^2) 192 ms vs D&C 1 ms (equal true) | LC 1425 n=200000, k=1000: deque 1.9 ms vs O(nk) 97 ms (equal true)
```

**Output, Clang 21.1 (verified; the last two lines are one measured run):**

```text
1. Held-Karp TSP (directed, n <= 8) vs all permutations; the reconstructed tour costs the optimum: 400/400
2. SOS DP vs submask enumeration: 400/400 | the 'sub > 0' loop that skips the empty subset: 3/400
3. LC 1425 monotonic-queue DP == O(nk) DP == brute force over index sets: 2000/2000
4. D&C optimization vs O(g n^2): non-negative values 400/400 | values in [-50, 50] (precondition broken) 193/400
constants (one measured run): n=16 submask enumeration (3^16 = 43 M) 33 ms vs SOS 0.5 ms | n=22 SOS sequential 63 ms, parallel per bit layer 40 ms | agree true
   n=4000, g=20 groups: O(g n^2) 311 ms vs D&C 1 ms (equal true) | LC 1425 n=200000, k=1000: deque 2.4 ms vs O(nk) 131 ms (equal true)
```

---

## 3. What the results show

* **Every optimized DP agrees with an independent oracle** (permutations, submask enumeration, O(nk) DP plus brute force over index sets, O(gn²) DP). Each optimization's precondition is then shown to matter:
  * the `sub > 0` submask loop is right on 3 of 400 instances, only those whose empty-set value is 0;
  * D&C optimization on data with negative values is right on 193 of 400, with no error raised.
* **The constants are large:**

| Comparison | Java | C++ GCC / Clang |
|---|---|---|
| n = 16: submask enumeration (3¹⁶) vs SOS (16 × 2¹⁶) | 32–34 ms vs 0.6–0.7 ms | 22–36 ms vs 0.5–0.6 ms |
| n = 22: SOS sequential vs parallel per bit layer | 73–81 vs 38–42 ms | 63–80 vs 35–49 ms |
| Partition n = 4,000, g = 20: O(gn²) vs D&C | 243–260 vs 2 ms | 178–311 vs 1 ms |
| LC 1425 n = 200,000, k = 1,000: O(nk) vs deque | 111–116 vs 3.4–3.5 ms | 94–131 vs 1.9–3.0 ms |

SOS parallelizes about 1.6–2× on 8 threads. The pass over 4 M longs (32 MB) per bit layer is memory-bound, the same lesson as Folder 01 File 2.

---

## 4. The last 10 minutes: Extensions A, B and C

### 4.1 Extension A — "64 threads"

* **SOS DP:** parallel within each bit layer (measured), one barrier per bit. It's bandwidth-bound, so speedup saturates early.
* **Held–Karp:** layers by popcount: every mask with k bits depends only on masks with k − 1 bits. Parallelize within a popcount layer.
* **D&C optimization:** the two recursive halves are independent, so fork them (fork-join). Layers g stay sequential.
* **Monotonic-queue DP** is inherently sequential along i. Parallelize across independent instances.

### 4.2 Extension B — "the state space doesn't fit in memory"

* **Bitmask DP** beyond about 24 elements: store only two popcount layers at a time (the predecessor information for reconstruction then goes to disk), or **meet in the middle**: solve the two halves of the element set and join them, roughly 2^(n/2) memory. Or accept an approximation (Christofides, 2-opt for TSP) with stated bounds.
* **SOS on disk:** each bit layer is a pass of pairs at distance 2^b. Low bits pair elements within a block, and high bits pair whole blocks. That's n sequential passes, which is the external-memory FFT pattern.
* **Monotonic-queue DP** streams naturally: O(k) memory for the window, O(1) state otherwise.

### 4.3 Extension C — "distributed"

* **Bitmask DP:** partition masks by their high bits across machines. Each popcount layer exchanges the masks that cross partitions, which in practice is everything, so communication dominates. Distributed exact TSP beyond n ≈ 30 isn't a DP question any more; it's branch-and-bound or an approximation, and saying so is the senior answer.
* **SOS DP:** partition by high bits. Low-bit layers are local; each high-bit layer is a pairwise exchange between two machines (a butterfly), log(machines) exchange rounds.
* **D&C-optimized partition DP:** each layer's j-range splits across machines, but each needs the previous layer in full. Ship prev-layer arrays (O(n) each), at g rounds of all-to-all.

---

## 5. Failure modes

| # | Failure | Symptom | Prevention |
|---|---|---|---|
| F1 | Submask loop `s > 0` | Empty subset missing (397/400 wrong) | Add `s = 0` explicitly; test masks with a[0] ≠ 0 |
| F2 | 3ⁿ submask enumeration at n ≥ 20 | Minutes to hours | SOS DP |
| F3 | D&C / Knuth without checking the quadrangle inequality | Silent wrong answers (207/400) | State and check the property; adversarial tests |
| F4 | Bitmask memory ignored | OOM at n ≈ 25 | 2ⁿ × n × 8 B budget; layers or meet in the middle |
| F5 | O(nk) window max inside a DP | 30–50× slower | Monotonic deque |
| F6 | Deque window not advanced before use | Uses out-of-window states | Pop expired front before reading |
| F7 | TSP reconstruction unverified | A tour whose cost differs from the DP value | Recompute the tour cost; check it's a permutation |

---

## 6. Bar-raiser chains

<details><summary><b>Q1 · "Shortest route visiting all 15 warehouses."</b></summary>

**Initial Prompt.** TSP with n = 15.

**L5 Answer.** Try all permutations.

**Why L5 Stalls.** 14! ≈ 8.7 × 10¹⁰.

**L7 Answer.** "Held–Karp: state (visited set as a bitmask, current city), 2¹⁵ × 15 states, about 7 M transitions × 15. Milliseconds. I'd keep predecessors to rebuild the tour and check the rebuilt tour's cost equals the DP value. Memory is 2ⁿ × n entries, so this is the tool up to about 20–24 cities; beyond that I'd switch to heuristics with bounds, like 2-opt or Lin–Kernighan, and say so."
</details>

<details><summary><b>Q2 · "For every bitmask, sum the values of all its subsets."</b></summary>

**Initial Prompt.** n = 20 feature flags.

**L5 Answer.** Enumerate submasks for each mask.

**Why L5 Stalls.** 3²⁰ ≈ 3.5 × 10⁹, and the usual submask loop skips the empty set.

**L7 Answer.** "SOS DP: prefix sums along each bit dimension, n × 2ⁿ ≈ 2 × 10⁷. After processing bit b, each entry sums submasks differing only in bits up to b. For n = 16 I measured 32 ms for submask enumeration against 0.6 ms for SOS. If I do enumerate submasks, the loop `s = (s−1) & m` stops at s = 0 without visiting it, so the empty subset needs explicit handling."
</details>

<details><summary><b>Q3 · "Max sum of a subsequence where consecutive picks are at most k apart."</b></summary>

**Initial Prompt.** LeetCode 1425.

**L5 Answer.** dp[i] = a[i] + max(0, max of the last k dp values), with an inner loop: O(nk).

**Why L5 Stalls.** n = k = 10⁵ gives 10¹⁰.

**L7 Answer.** "The inner max is a sliding-window maximum over dp, so a monotonic deque of indices with decreasing dp makes it O(n): pop expired indices from the front, push i after popping dominated ones from the back. Measured at n = 200k, k = 1,000: about 3 ms against about 100 ms. I check it against the O(nk) version and against brute force over index sets on small inputs."
</details>

<details><summary><b>Q4 · "Split this array into g contiguous groups minimizing the sum of squared group sums."</b></summary>

**Initial Prompt.** A load-balancing partition.

**L5 Answer.** "Divide-and-conquer optimization, O(g n log n)."

**Why L5 Stalls.** Correct here only because the values are non-negative, and the candidate didn't say so. Measured with negative values: wrong on about half of the instances.

**L7 Answer.** "The naive layered DP is O(g n²). D&C optimization applies if the best split point is monotone in j, which follows from the quadrangle inequality. For (S_j − S_i)² that needs monotone prefix sums, so non-negative values. With non-negative loads it's exact, 2 ms vs 243 ms. I'd assert non-negativity at the API boundary, because with negatives it still returns a number, just the wrong one."
</details>

<details><summary><b>Q5 · "How do you know an optimization's precondition holds?"</b></summary>

**Initial Prompt.** Probe after Q4.

**L5 Answer.** "It's a known pattern."

**Why L5 Stalls.** Patterns transfer only when the structure does.

**L7 Answer.** "Three ways. Prove it for the cost function: the quadrangle inequality for convex functions of a monotone prefix. Check it empirically by asserting opt(j) ≤ opt(j+1) on the naive DP for random inputs. And test the optimized DP against the naive one on inputs designed to *violate* the precondition, to confirm the guard matters. Here negative values made D&C wrong on 207 of 400 instances."
</details>

<details><summary><b>Q6 · "n = 30 cities. Still Held–Karp?"</b></summary>

**Initial Prompt.** Extension B.

**L5 Answer.** "Yes, just more memory."

**Why L5 Stalls.** 2³⁰ × 30 states × 8 B ≈ 257 GB.

**L7 Answer.** "Not as a full table. Options: keep only two popcount layers, which saves memory but still needs ~10¹² operations; meet in the middle over two halves; or, realistically, an exact solver with branch and bound and good lower bounds (Concorde-class), or a heuristic with a quality bound. For a delivery route of 30 stops, 2-opt plus or-opt gets within a few percent in milliseconds, and that's what I'd ship."
</details>

<details><summary><b>Q7 · "Parallelize SOS DP."</b></summary>

**Initial Prompt.** Extension A.

**L5 Answer.** "Split the masks across threads."

**Why L5 Stalls.** Correct only within a bit layer. Across layers there's a dependency, and the candidate didn't name the barrier.

**L7 Answer.** "Within one bit layer, every update touches a disjoint pair (mask, mask ^ bit), so masks split freely across threads, with a barrier between layers: 22 barriers for n = 22. I measured about 1.6–2× on 8 threads, because each layer streams 32 MB, so it's bandwidth-bound. Distributed, it becomes a butterfly: low bits local, high bits as pairwise exchanges between machines."
</details>

<details><summary><b>Q8 · "Return the actual TSP route, and prove it's right."</b></summary>

**Initial Prompt.** Reconstruction.

**L5 Answer.** Returns the DP cost only, or a route rebuilt without checking.

**Why L5 Stalls.** Reconstruction bugs, like an off-by-one in mask removal, produce plausible but invalid routes.

**L7 Answer.** "Store the predecessor for each (mask, city), walk back from the best end city removing one bit at a time, and then verify: the route starts at city 0, visits each city exactly once, and its recomputed cost equals the DP optimum. The listing checks all three on 400 random instances against brute force."
</details>

---

## 7. Checklist

* [ ] Bitmask DP: memory budget 2ⁿ × n × 8 B stated; reconstruction verified.
* [ ] Submask loops include the empty set; SOS DP for all-masks sums.
* [ ] Monotonic deque inside DP transitions with sliding windows.
* [ ] D&C / Knuth: quadrangle inequality or monotone opt **checked**; precondition asserted at the boundary.
* [ ] Every optimization tested against the naive DP *and* on inputs that violate its precondition.
* [ ] Extension A: parallel within layers (bits, popcounts, recursion halves).
* [ ] Extension B: layer-at-a-time memory; meet in the middle; heuristics with bounds.
* [ ] Extension C: partition by high bits; butterfly exchanges; know when exact distributed DP is the wrong goal.

---

## 8. References

* M. Held, R. M. Karp, *A Dynamic Programming Approach to Sequencing Problems*, J. SIAM 10(1), 1962 — DOI 10.1137/0110015
* R. Bellman, *Dynamic Programming Treatment of the Travelling Salesman Problem*, JACM 9(1), 1962 — DOI 10.1145/321105.321111
* F. F. Yao, *Efficient Dynamic Programming Using Quadrangle Inequalities*, STOC 1980 — DOI 10.1145/800141.804691
* cp-algorithms: [Divide and conquer DP](https://cp-algorithms.com/dynamic_programming/divide-and-conquer-dp.html), [Submask enumeration](https://cp-algorithms.com/algebra/all-submasks.html)
* LeetCode anchors: [943 Find the Shortest Superstring](https://leetcode.com/problems/find-the-shortest-superstring/), [1425 Constrained Subsequence Sum](https://leetcode.com/problems/constrained-subsequence-sum/), [847 Shortest Path Visiting All Nodes](https://leetcode.com/problems/shortest-path-visiting-all-nodes/), [410 Split Array Largest Sum](https://leetcode.com/problems/split-array-largest-sum/)

*Folder 05:* [01 — state design, space, reconstruction](01-dp-state-design-space-optimization-and-reconstructing-optimal-paths.md) · [02 — interval DP, rerooting, digit DP](02-interval-dp-tree-dp-rerooting-and-digit-dp-blueprints.md)
