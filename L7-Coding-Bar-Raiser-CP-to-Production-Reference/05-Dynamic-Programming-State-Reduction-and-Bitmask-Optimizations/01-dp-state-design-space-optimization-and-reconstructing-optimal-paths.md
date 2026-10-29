# DP State Design, Space Optimization and Reconstructing Optimal Paths

> **Folder 05 · File 1 of 3** — what a DP state *is* (the smallest summary of the past that decides the future), what you lose when you roll the array (the path), how Hirschberg gets it back in linear space, and why the direction of a loop is part of the state.
> **Languages:** Java 21 (`--release 21 -Xlint:all -Werror`, JDK 25.0.4.1) and C++23 (GCC 16.2 and Clang 21.1, `-O2`, warnings as errors).

| Listing | File | What it proves |
|---|---|---|
| 5.1 | `DpCore.java` | Edit distance: full table = rolling rows = memoized recursion. A Hirschberg alignment that provably transforms a into b at optimal cost. 0/1 knapsack's loop direction (the forward loop is wrong on 63% of instances); reconstructed knapsack items; O(n log n) LIS with reconstruction. The memo-in-a-hash-map constant; a tiled wavefront |
| 5.2 | `dp_core.cpp` | The same; the wavefront uses persistent threads and a spin barrier; identical correctness counts |

**Verification.** Both listings were extracted from this file, compiled and run. Everything is **Output (verified)** except the two timing lines (**one measured run**).

---

## 0. Orientation

| Contest habit | What breaks | L7 replacement |
|---|---|---|
| "dp[i][j] means ... something" | Can't explain correctness or extend the problem | State = the minimal summary of decisions so far that determines the best future; say it in one sentence |
| Recursive memo in `HashMap<String, ...>` | 41–453× slower than arrays (measured); recursion depth | Bottom-up over a dense index space; memo only for sparse state spaces |
| Roll the array to save memory, then get asked for the solution | The path is gone | Keep a decision table (bits), or use Hirschberg: linear memory *and* the path |
| `for c in w..W` in 0/1 knapsack | Becomes the unbounded knapsack: wrong on 63% of instances | Reverse the capacity loop; state *why* (`dp[c − w]` must still mean "without item i") |
| Return the value only | Interviewers ask "which items?" next | Reconstruct, then **verify** the reconstruction re-evaluates to the optimum |

---

## 1. First principles

### 1.1 What a state is

A DP state is the smallest summary of the decisions made so far such that the **best completion depends only on that summary**: the Markov property for optimization. For edit distance, the state `(i, j)` (prefixes consumed) is enough: how we aligned those prefixes doesn't constrain the rest. The recurrence is then a statement of optimal substructure: the best answer for a state is the best of the transitions into it, plus their costs.

Three questions decide whether a DP is right before writing code:

1. **Is the state sufficient?** (Folder 04 File 1: "city" is not a sufficient state under a stop limit; "(city, stops)" is.)
2. **Is the transition order valid?** Every state must be computed after the states it reads (topological order of the state DAG).
3. **What does it cost?** (states × transitions per state) time and (states) memory, or less if the order allows rolling.

### 1.2 Rolling arrays and the loop-direction trap

If row i reads only row i − 1, keep two rows: memory O(width). With **one** array updated in place, the iteration order determines which version of each cell you read. In 0/1 knapsack, `dp[c] = max(dp[c], dp[c − w] + v)` must read `dp[c − w]` **before** item i touched it, so c must go **downward**. Going upward reads a value that already includes item i, so the item can be used repeatedly. That is precisely the unbounded knapsack, a different problem with a plausible-looking answer. The listing's forward loop was right on only 1,099 of 3,000 random instances.

### 1.3 Reconstruction costs memory, unless you are clever

Reconstruction walks back from the final state, re-asking "which transition produced this value?". It needs either the full table (O(nm) for edit distance), or a table of **decisions** (one bit per state for knapsack: `take[i][c]`, n × W bits), or recomputation. **Hirschberg's algorithm** recomputes cleverly. It splits a at its midpoint, runs one forward linear-space pass on the first half and one backward pass on the reversed second half, and finds the column where an optimal path crosses the middle row (the j minimizing `forward[j] + backward[m − j]`). Then it recurses on the two sub-problems. Time stays O(nm) (geometric series), memory is O(n + m), and recursion depth is O(log n). That's the standard way to align long DNA or diff huge files without a quadratic table.

### 1.4 Patience sorting: LIS with reconstruction

For the longest strictly increasing subsequence, keep `tail[len]` = the index of the smallest possible tail of an increasing subsequence of length `len + 1`. Each new element binary-searches its position (first tail ≥ it) and records a **parent pointer** to the tail before that position. That's O(n log n), and the parent chain from the last tail reconstructs one optimal subsequence. The invariant: tails are strictly increasing in value, so binary search is valid.

### 1.5 Top-down vs bottom-up

Memoized recursion is the fastest to write and computes only reachable states. That wins when the state space is sparse, as in digit DP with tight bounds. For dense state spaces it pays a hash lookup per state, an allocation per entry in Java (boxed keys and values), and recursion depth proportional to the longest dependency chain (n + m for edit distance). Measured over 1 M dense states: 168–173× slower than rolling arrays in Java and 41–114× in C++, where the hash map holds no boxes but still hashes and chases nodes. The Staff answer: *prototype top-down, ship bottom-up over a dense index, and say why.*

---

## 2. The listings

### 2.1 Listing 5.1 — Java

```java
// DpCore.java - DP state design, rolling arrays, Hirschberg reconstruction, loop direction, memo constants, wavefront threads.
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

public final class DpCore {

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
        String word(int maxLen, int alphabet) { return fixed(nextInt(maxLen + 1), alphabet); }
        String fixed(int len, int alphabet) {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < len; i++) sb.append((char) ('a' + nextInt(alphabet)));
            return sb.toString();
        }
    }

    // ===================================================================== 1. edit distance: state = (i, j) prefixes
    /** d[i][j] = edits turning a[0,i) into b[0,j). O(nm) time and memory: the table needed for reconstruction. */
    static int[][] editTable(String a, String b) {
        int n = a.length(), m = b.length();
        int[][] d = new int[n + 1][m + 1];
        for (int i = 0; i <= n; i++) d[i][0] = i;
        for (int j = 0; j <= m; j++) d[0][j] = j;
        for (int i = 1; i <= n; i++)
            for (int j = 1; j <= m; j++)
                d[i][j] = Math.min(Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1), d[i - 1][j - 1] + (a.charAt(i - 1) == b.charAt(j - 1) ? 0 : 1));
        return d;
    }

    /** Row i only reads row i-1: two rows, O(min(n, m)) memory -- but the path through the table is gone. */
    static int editDistance(String a, String b) {
        if (a.length() < b.length()) { String t = a; a = b; b = t; }
        int m = b.length();
        int[] prev = new int[m + 1], cur = new int[m + 1];
        for (int j = 0; j <= m; j++) prev[j] = j;
        for (int i = 1; i <= a.length(); i++) {
            cur[0] = i;
            for (int j = 1; j <= m; j++)
                cur[j] = Math.min(Math.min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + (a.charAt(i - 1) == b.charAt(j - 1) ? 0 : 1));
            int[] t = prev; prev = cur; cur = t;
        }
        return prev[m];
    }

    /** Backtrack through the full table: ops are M(atch) S(ubstitute) D(elete from a) I(nsert from b). */
    static String opsFromTable(String a, String b) {
        int[][] d = editTable(a, b);
        StringBuilder ops = new StringBuilder();
        int i = a.length(), j = b.length();
        while (i > 0 || j > 0) {
            if (i > 0 && j > 0 && d[i][j] == d[i - 1][j - 1] + (a.charAt(i - 1) == b.charAt(j - 1) ? 0 : 1)) {
                ops.append(a.charAt(i - 1) == b.charAt(j - 1) ? 'M' : 'S'); i--; j--;
            } else if (i > 0 && d[i][j] == d[i - 1][j] + 1) { ops.append('D'); i--; }
            else { ops.append('I'); j--; }
        }
        return ops.reverse().toString();
    }

    /** Last row of edit distances from a to every prefix of b (forward), in O(|b|) memory. */
    private static int[] lastRow(String a, String b) {
        int m = b.length();
        int[] prev = new int[m + 1], cur = new int[m + 1];
        for (int j = 0; j <= m; j++) prev[j] = j;
        for (int i = 1; i <= a.length(); i++) {
            cur[0] = i;
            for (int j = 1; j <= m; j++)
                cur[j] = Math.min(Math.min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + (a.charAt(i - 1) == b.charAt(j - 1) ? 0 : 1));
            int[] t = prev; prev = cur; cur = t;
        }
        return prev;
    }

    /**
     * Hirschberg: split a in half, find where an optimal path crosses the middle row by combining a forward and a
     * backward linear-space pass, recurse on both halves. O(nm) time, O(n + m) memory, recursion depth O(log n).
     */
    static String hirschberg(String a, String b) {
        if (a.isEmpty()) return "I".repeat(b.length());
        if (b.isEmpty()) return "D".repeat(a.length());
        if (a.length() == 1) return opsFromTable(a, b);
        int mid = a.length() / 2;
        int[] left = lastRow(a.substring(0, mid), b);
        int[] right = lastRow(new StringBuilder(a.substring(mid)).reverse().toString(), new StringBuilder(b).reverse().toString());
        int split = 0, best = Integer.MAX_VALUE;
        for (int j = 0; j <= b.length(); j++) {
            int c = left[j] + right[b.length() - j];
            if (c < best) { best = c; split = j; }
        }
        return hirschberg(a.substring(0, mid), b.substring(0, split)) + hirschberg(a.substring(mid), b.substring(split));
    }

    /** Applies the ops; returns null if they don't produce b. Cost = number of non-M ops. */
    static String apply(String a, String b, String ops) {
        StringBuilder out = new StringBuilder();
        int i = 0, j = 0;
        for (char op : ops.toCharArray()) {
            switch (op) {
                case 'M' -> { if (a.charAt(i) != b.charAt(j)) return null; out.append(a.charAt(i)); i++; j++; }
                case 'S' -> { out.append(b.charAt(j)); i++; j++; }
                case 'D' -> i++;
                default -> { out.append(b.charAt(j)); j++; }
            }
        }
        return i == a.length() ? out.toString() : null;
    }

    static int cost(String ops) { return (int) ops.chars().filter(c -> c != 'M').count(); }

    /** The contest-to-interview habit: top-down recursion memoized in a HashMap keyed by the state. */
    static int memoEdit(String a, String b, int i, int j, Map<Long, Integer> memo) {
        if (i == 0) return j;
        if (j == 0) return i;
        long key = (long) i << 32 | j;
        Integer hit = memo.get(key);
        if (hit != null) return hit;
        int r = Math.min(Math.min(memoEdit(a, b, i - 1, j, memo) + 1, memoEdit(a, b, i, j - 1, memo) + 1),
                memoEdit(a, b, i - 1, j - 1, memo) + (a.charAt(i - 1) == b.charAt(j - 1) ? 0 : 1));
        memo.put(key, r);
        return r;
    }

    // ===================================================================== 2. 0/1 knapsack: loop direction is the state
    /** dp[c] = best value with capacity c over items seen so far. REVERSE c so each item is used at most once. */
    static long knapsack(int[] w, int[] v, int cap, boolean[][] take) {
        long[] dp = new long[cap + 1];
        for (int i = 0; i < w.length; i++)
            for (int c = cap; c >= w[i]; c--)
                if (dp[c - w[i]] + v[i] > dp[c]) { dp[c] = dp[c - w[i]] + v[i]; if (take != null) take[i][c] = true; }
        return dp[cap];
    }

    /** Contest slip: forward c lets dp[c - w] already include item i -- the unbounded knapsack, silently. */
    static long knapsackForward(int[] w, int[] v, int cap) {
        long[] dp = new long[cap + 1];
        for (int i = 0; i < w.length; i++)
            for (int c = w[i]; c <= cap; c++) dp[c] = Math.max(dp[c], dp[c - w[i]] + v[i]);
        return dp[cap];
    }

    /** take[i][c] records the decision at item i with capacity c; walk items backwards to recover the set. */
    static List<Integer> knapsackItems(int[] w, boolean[][] take, int cap) {
        List<Integer> items = new ArrayList<>();
        for (int i = w.length - 1, c = cap; i >= 0; i--) if (take[i][c]) { items.add(i); c -= w[i]; }
        return items;
    }

    // ===================================================================== 3. LIS in O(n log n) with reconstruction
    static int[] lis(int[] a) {
        int[] tailIdx = new int[a.length], parent = new int[a.length];
        int len = 0;
        for (int i = 0; i < a.length; i++) {
            int lo = 0, hi = len;                                   // first tail >= a[i] (strictly increasing LIS)
            while (lo < hi) { int mid = (lo + hi) >>> 1; if (a[tailIdx[mid]] < a[i]) lo = mid + 1; else hi = mid; }
            parent[i] = lo > 0 ? tailIdx[lo - 1] : -1;
            tailIdx[lo] = i;
            if (lo == len) len++;
        }
        int[] out = new int[len];
        for (int k = len - 1, i = len > 0 ? tailIdx[len - 1] : -1; k >= 0; k--, i = parent[i]) out[k] = a[i];
        return out;
    }

    static int lisOracle(int[] a) {
        int best = 0;
        int[] d = new int[a.length];
        for (int i = 0; i < a.length; i++) {
            d[i] = 1;
            for (int j = 0; j < i; j++) if (a[j] < a[i]) d[i] = Math.max(d[i], d[j] + 1);
            best = Math.max(best, d[i]);
        }
        return best;
    }

    // ===================================================================== Extension A: tiled anti-diagonal wavefront
    /** Tiles on the same anti-diagonal of TILES are independent: each depends only on its upper and left neighbours. */
    static int wavefront(String a, String b, int threads, int tile, ExecutorService pool) throws Exception {
        int n = a.length(), m = b.length();
        int[][] d = new int[n + 1][m + 1];
        for (int i = 0; i <= n; i++) d[i][0] = i;
        for (int j = 0; j <= m; j++) d[0][j] = j;
        int tr = (n + tile - 1) / tile, tc = (m + tile - 1) / tile;
        for (int diag = 0; diag < tr + tc - 1; diag++) {
            List<Future<?>> work = new ArrayList<>();
            for (int ti = Math.max(0, diag - tc + 1); ti <= Math.min(tr - 1, diag); ti++) {
                int tj = diag - ti, i0 = ti * tile + 1, j0 = tj * tile + 1;
                work.add(pool.submit(() -> {
                    for (int i = i0; i < Math.min(n + 1, i0 + tile); i++)
                        for (int j = j0; j < Math.min(m + 1, j0 + tile); j++)
                            d[i][j] = Math.min(Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1), d[i - 1][j - 1] + (a.charAt(i - 1) == b.charAt(j - 1) ? 0 : 1));
                }));
            }
            for (Future<?> f : work) f.get();                           // barrier between tile anti-diagonals
        }
        return d[n][m];
    }

    public static void main(String[] args) throws Exception {
        SplitMix64 r = new SplitMix64(111);
        int trials = 3_000, okEdit = 0, okHir = 0, okKnap = 0, cpKnap = 0, okItems = 0, okLis = 0;
        for (int t = 0; t < trials; t++) {
            String a = r.word(12, 3), b = r.word(12, 3);
            int full = editTable(a, b)[a.length()][b.length()];
            okEdit += editDistance(a, b) == full && memoEdit(a, b, a.length(), b.length(), new HashMap<>()) == full ? 1 : 0;
            String ops = hirschberg(a, b);
            okHir += b.equals(apply(a, b, ops)) && cost(ops) == full ? 1 : 0;
            int n = r.nextInt(9), cap = r.nextInt(16);
            int[] w = new int[n], v = new int[n];
            for (int i = 0; i < n; i++) { w[i] = 1 + r.nextInt(6); v[i] = r.nextInt(20); }
            long best = 0;
            for (int mask = 0; mask < 1 << n; mask++) {
                long ww = 0, vv = 0;
                for (int i = 0; i < n; i++) if ((mask >> i & 1) == 1) { ww += w[i]; vv += v[i]; }
                if (ww <= cap) best = Math.max(best, vv);
            }
            boolean[][] take = new boolean[n][cap + 1];
            long got = knapsack(w, v, cap, take);
            okKnap += got == best ? 1 : 0;
            cpKnap += knapsackForward(w, v, cap) == best ? 1 : 0;
            List<Integer> items = knapsackItems(w, take, cap);
            okItems += items.stream().mapToInt(i -> w[i]).sum() <= cap && items.stream().mapToLong(i -> v[i]).sum() == got ? 1 : 0;
            int[] s = new int[r.nextInt(14)];
            for (int i = 0; i < s.length; i++) s[i] = r.nextInt(8);
            int[] seq = lis(s);
            boolean inc = true;
            for (int i = 1; i < seq.length; i++) inc &= seq[i - 1] < seq[i];
            boolean sub = true;
            for (int i = 0, k = 0; k < seq.length; i++) { if (i == s.length) { sub = false; break; } if (s[i] == seq[k]) k++; }
            okLis += inc && sub && seq.length == lisOracle(s) ? 1 : 0;
        }
        System.out.printf("random instances (%,d each) vs full-table / exhaustive oracles:%n", trials);
        System.out.printf("   edit distance: rolling rows == memoized recursion == full table  %d/%d%n", okEdit, trials);
        System.out.printf("   Hirschberg alignment transforms a into b at optimal cost        %d/%d%n", okHir, trials);
        System.out.printf("   0/1 knapsack, reverse capacity loop                            %d/%d | forward loop (contest slip) %d/%d%n",
                okKnap, trials, cpKnap, trials);
        System.out.printf("   knapsack items reconstructed: fit the capacity, sum to the optimum %d/%d%n", okItems, trials);
        System.out.printf("   LIS O(n log n) returns an increasing subsequence of optimal length %d/%d%n", okLis, trials);

        String a = r.fixed(1_000, 4), b = r.fixed(1_000, 4);
        for (int rep = 0; rep < 2; rep++) {
            long t0 = System.nanoTime();
            int x = editDistance(a, b);
            long t1 = System.nanoTime();
            int y = memoEdit(a, b, a.length(), b.length(), new HashMap<>());
            long t2 = System.nanoTime();
            if (rep == 1) System.out.printf("constants, 1,000 x 1,000 = 1 M states (one measured run): rolling arrays %.1f ms |"
                    + " HashMap-memoized recursion %.1f ms (%.0fx) | equal %b%n", (t1 - t0) / 1e6, (t2 - t1) / 1e6,
                    (double) (t2 - t1) / (t1 - t0), x == y);
        }
        String big1 = r.fixed(6_000, 4), big2 = r.fixed(6_000, 4);
        int tiles = (6_000 + 255) / 256;
        ExecutorService pool = Executors.newFixedThreadPool(8);
        wavefront(big1, big2, 8, 256, pool);   // warm-up
        long t0 = System.nanoTime();
        int seq = editDistance(big1, big2);
        long t1 = System.nanoTime();
        int par = wavefront(big1, big2, 8, 256, pool);
        long t2 = System.nanoTime();
        pool.shutdown();
        System.out.printf("A. 6,000 x 6,000 edit distance (one measured run): rolling rows %d ms | 8-thread tiled wavefront"
                + " (256x256 tiles, %d tile diagonals) %d ms | equal %b%n", (t1 - t0) / 1_000_000, 2 * tiles - 1, (t2 - t1) / 1_000_000, seq == par);
    }
}
```

**Output (verified; the last two lines are one measured run):**

```text
random instances (3,000 each) vs full-table / exhaustive oracles:
   edit distance: rolling rows == memoized recursion == full table  3000/3000
   Hirschberg alignment transforms a into b at optimal cost        3000/3000
   0/1 knapsack, reverse capacity loop                            3000/3000 | forward loop (contest slip) 1099/3000
   knapsack items reconstructed: fit the capacity, sum to the optimum 3000/3000
   LIS O(n log n) returns an increasing subsequence of optimal length 3000/3000
constants, 1,000 x 1,000 = 1 M states (one measured run): rolling arrays 4.5 ms | HashMap-memoized recursion 753.3 ms (168x) | equal true
A. 6,000 x 6,000 edit distance (one measured run): rolling rows 169 ms | 8-thread tiled wavefront (256x256 tiles, 47 tile diagonals) 93 ms | equal true
```

### 2.2 Listing 5.2 — C++23

```cpp
// dp_core.cpp - DP state design, rolling arrays, Hirschberg reconstruction, loop direction, memo constants, wavefront threads.
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <print>
#include <string>
#include <string_view>
#include <thread>
#include <unordered_map>
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
    std::string fixed(int len, int alphabet) {
        std::string s;
        for (int i = 0; i < len; ++i) s += static_cast<char>('a' + next_int(alphabet));
        return s;
    }
    std::string word(int max_len, int alphabet) { return fixed(next_int(max_len + 1), alphabet); }
};

int sub_cost(char x, char y) { return x == y ? 0 : 1; }

// ======================================================================= 1. edit distance: state = (i, j) prefixes
std::vector<Vec> edit_table(std::string_view a, std::string_view b) {
    std::vector<Vec> d(a.size() + 1, Vec(b.size() + 1));
    for (std::size_t i = 0; i <= a.size(); ++i) d[i][0] = static_cast<int>(i);
    for (std::size_t j = 0; j <= b.size(); ++j) d[0][j] = static_cast<int>(j);
    for (std::size_t i = 1; i <= a.size(); ++i)
        for (std::size_t j = 1; j <= b.size(); ++j)
            d[i][j] = std::min({d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + sub_cost(a[i - 1], b[j - 1])});
    return d;
}

// Row i only reads row i-1: two rows, O(min(n, m)) memory -- but the path through the table is gone.
Vec last_row(std::string_view a, std::string_view b) {
    Vec prev(b.size() + 1), cur(b.size() + 1);
    for (std::size_t j = 0; j <= b.size(); ++j) prev[j] = static_cast<int>(j);
    for (std::size_t i = 1; i <= a.size(); ++i) {
        cur[0] = static_cast<int>(i);
        for (std::size_t j = 1; j <= b.size(); ++j)
            cur[j] = std::min({prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + sub_cost(a[i - 1], b[j - 1])});
        std::swap(prev, cur);
    }
    return prev;
}
int edit_distance(std::string_view a, std::string_view b) {
    if (a.size() < b.size()) std::swap(a, b);
    return last_row(a, b).back();
}

// Backtrack through the full table: M(atch) S(ubstitute) D(elete from a) I(nsert from b).
std::string ops_from_table(std::string_view a, std::string_view b) {
    auto d = edit_table(a, b);
    std::string ops;
    std::size_t i = a.size(), j = b.size();
    while (i > 0 || j > 0) {
        if (i > 0 && j > 0 && d[i][j] == d[i - 1][j - 1] + sub_cost(a[i - 1], b[j - 1])) ops += a[i - 1] == b[j - 1] ? 'M' : 'S', --i, --j;
        else if (i > 0 && d[i][j] == d[i - 1][j] + 1) ops += 'D', --i;
        else ops += 'I', --j;
    }
    std::ranges::reverse(ops);
    return ops;
}

// Hirschberg: O(nm) time, O(n + m) memory, recursion depth O(log n).
std::string hirschberg(std::string_view a, std::string_view b) {
    if (a.empty()) return std::string(b.size(), 'I');
    if (b.empty()) return std::string(a.size(), 'D');
    if (a.size() == 1) return ops_from_table(a, b);
    std::size_t mid = a.size() / 2;
    Vec left = last_row(a.substr(0, mid), b);
    std::string ra(a.substr(mid).rbegin(), a.substr(mid).rend()), rb(b.rbegin(), b.rend());
    Vec right = last_row(ra, rb);
    std::size_t split = 0;
    int best = std::numeric_limits<int>::max();
    for (std::size_t j = 0; j <= b.size(); ++j)
        if (int c = left[j] + right[b.size() - j]; c < best) best = c, split = j;
    return hirschberg(a.substr(0, mid), b.substr(0, split)) + hirschberg(a.substr(mid), b.substr(split));
}

bool transforms(std::string_view a, std::string_view b, std::string_view ops) {
    std::string out;
    std::size_t i = 0, j = 0;
    for (char op : ops) {
        if (op == 'M') {
            if (a[i] != b[j]) return false;
            out += a[i++], ++j;
        } else if (op == 'S') {
            out += b[j++], ++i;
        } else if (op == 'D') {
            ++i;
        } else {
            out += b[j++];
        }
    }
    return i == a.size() && out == b;
}
int cost(std::string_view ops) { return static_cast<int>(std::ranges::count_if(ops, [](char c) { return c != 'M'; })); }

// The contest-to-interview habit: top-down recursion memoized in a hash map keyed by the state.
int memo_edit(std::string_view a, std::string_view b, std::size_t i, std::size_t j, std::unordered_map<std::uint64_t, int>& memo) {
    if (i == 0) return static_cast<int>(j);
    if (j == 0) return static_cast<int>(i);
    std::uint64_t key = static_cast<std::uint64_t>(i) << 32 | j;
    if (auto it = memo.find(key); it != memo.end()) return it->second;
    int r = std::min({memo_edit(a, b, i - 1, j, memo) + 1, memo_edit(a, b, i, j - 1, memo) + 1,
                      memo_edit(a, b, i - 1, j - 1, memo) + sub_cost(a[i - 1], b[j - 1])});
    memo.emplace(key, r);
    return r;
}

// ======================================================================= 2. 0/1 knapsack: loop direction is the state
i64 knapsack(const Vec& w, const Vec& v, int cap, std::vector<std::vector<bool>>* take) {
    std::vector<i64> dp(U(cap) + 1);
    for (std::size_t i = 0; i < w.size(); ++i)
        for (int c = cap; c >= w[i]; --c)  // REVERSE: dp[c - w] still means "without item i"
            if (dp[U(c - w[i])] + v[i] > dp[U(c)]) {
                dp[U(c)] = dp[U(c - w[i])] + v[i];
                if (take) (*take)[i][U(c)] = true;
            }
    return dp[U(cap)];
}
i64 knapsack_forward(const Vec& w, const Vec& v, int cap) {  // contest slip: silently the unbounded knapsack
    std::vector<i64> dp(U(cap) + 1);
    for (std::size_t i = 0; i < w.size(); ++i)
        for (int c = w[i]; c <= cap; ++c) dp[U(c)] = std::max(dp[U(c)], dp[U(c - w[i])] + v[i]);
    return dp[U(cap)];
}
Vec knapsack_items(const Vec& w, const std::vector<std::vector<bool>>& take, int cap) {
    Vec items;
    for (std::size_t i = w.size(), c = U(cap); i-- > 0;)
        if (take[i][c]) items.push_back(static_cast<int>(i)), c -= U(w[i]);
    return items;
}

// ======================================================================= 3. LIS in O(n log n) with reconstruction
Vec lis(const Vec& a) {
    Vec tail_idx, parent(a.size(), -1);
    for (std::size_t i = 0; i < a.size(); ++i) {
        auto pos = std::ranges::partition_point(tail_idx, [&](int t) { return a[U(t)] < a[i]; }) - tail_idx.begin();
        parent[i] = pos > 0 ? tail_idx[U(static_cast<int>(pos) - 1)] : -1;
        if (U(static_cast<int>(pos)) == tail_idx.size()) tail_idx.push_back(static_cast<int>(i));
        else tail_idx[U(static_cast<int>(pos))] = static_cast<int>(i);
    }
    Vec out(tail_idx.size());
    for (int k = static_cast<int>(out.size()) - 1, i = out.empty() ? -1 : tail_idx.back(); k >= 0; --k, i = parent[U(i)]) out[U(k)] = a[U(i)];
    return out;
}
int lis_oracle(const Vec& a) {
    int best = 0;
    Vec d(a.size());
    for (std::size_t i = 0; i < a.size(); ++i) {
        d[i] = 1;
        for (std::size_t j = 0; j < i; ++j)
            if (a[j] < a[i]) d[i] = std::max(d[i], d[j] + 1);
        best = std::max(best, d[i]);
    }
    return best;
}

// ======================================================================= Extension A: tiled anti-diagonal wavefront
class SpinBarrier {  // std::barrier on this toolchain sleeps ~15 ms after its spin phase; 47 phases need a pure spin
public:
    explicit SpinBarrier(int n) : n_(n) {}
    void arrive_and_wait() {
        int gen = gen_.load();
        if (count_.fetch_add(1) + 1 == n_) {
            count_.store(0);
            gen_.fetch_add(1);
        } else {
            while (gen_.load() == gen) {}
        }
    }

private:
    int n_;
    std::atomic<int> count_{0}, gen_{0};
};

int wavefront(std::string_view a, std::string_view b, int threads, int tile) {
    int n = static_cast<int>(a.size()), m = static_cast<int>(b.size());
    std::vector<Vec> d(U(n) + 1, Vec(U(m) + 1));
    for (int i = 0; i <= n; ++i) d[U(i)][0] = i;
    for (int j = 0; j <= m; ++j) d[0][U(j)] = j;
    int tr = (n + tile - 1) / tile, tc = (m + tile - 1) / tile;
    SpinBarrier barrier(threads);
    {
        std::vector<std::jthread> pool;
        for (int t = 0; t < threads; ++t)
            pool.emplace_back([&, t] {
                for (int diag = 0; diag < tr + tc - 1; ++diag) {
                    int lo = std::max(0, diag - tc + 1), hi = std::min(tr - 1, diag);
                    for (int ti = lo + t; ti <= hi; ti += threads) {  // tiles on one anti-diagonal are independent
                        int tj = diag - ti, i0 = ti * tile + 1, j0 = tj * tile + 1;
                        for (int i = i0; i < std::min(n + 1, i0 + tile); ++i)
                            for (int j = j0; j < std::min(m + 1, j0 + tile); ++j)
                                d[U(i)][U(j)] = std::min({d[U(i - 1)][U(j)] + 1, d[U(i)][U(j - 1)] + 1,
                                                          d[U(i - 1)][U(j - 1)] + sub_cost(a[U(i - 1)], b[U(j - 1)])});
                    }
                    barrier.arrive_and_wait();
                }
            });
    }
    return d[U(n)][U(m)];
}

int main() {
    SplitMix64 r{111};
    constexpr int trials = 3'000;
    int ok_edit = 0, ok_hir = 0, ok_knap = 0, cp_knap = 0, ok_items = 0, ok_lis = 0;
    for (int t = 0; t < trials; ++t) {
        std::string a = r.word(12, 3), b = r.word(12, 3);
        int full = edit_table(a, b)[a.size()][b.size()];
        std::unordered_map<std::uint64_t, int> memo;
        ok_edit += edit_distance(a, b) == full && memo_edit(a, b, a.size(), b.size(), memo) == full;
        std::string ops = hirschberg(a, b);
        ok_hir += transforms(a, b, ops) && cost(ops) == full;
        int n = r.next_int(9), cap = r.next_int(16);
        Vec w(U(n)), v(U(n));
        for (std::size_t i = 0; i < U(n); ++i) {
            w[i] = 1 + r.next_int(6);
            v[i] = r.next_int(20);
        }
        i64 best = 0;
        for (unsigned mask = 0; mask < (1u << n); ++mask) {
            i64 ww = 0, vv = 0;
            for (std::size_t i = 0; i < U(n); ++i)
                if (mask >> i & 1) ww += w[i], vv += v[i];
            if (ww <= cap) best = std::max(best, vv);
        }
        std::vector<std::vector<bool>> take(U(n), std::vector<bool>(U(cap) + 1));
        i64 got = knapsack(w, v, cap, &take);
        ok_knap += got == best;
        cp_knap += knapsack_forward(w, v, cap) == best;
        Vec items = knapsack_items(w, take, cap);
        i64 iw = 0, iv = 0;
        for (int i : items) iw += w[U(i)], iv += v[U(i)];
        ok_items += iw <= cap && iv == got;
        Vec s(U(r.next_int(14)));
        for (int& x : s) x = r.next_int(8);
        Vec seq = lis(s);
        bool inc = std::ranges::adjacent_find(seq, std::greater_equal<>()) == seq.end();
        std::size_t k = 0;
        for (std::size_t i = 0; i < s.size() && k < seq.size(); ++i) k += s[i] == seq[k];
        ok_lis += inc && k == seq.size() && static_cast<int>(seq.size()) == lis_oracle(s);
    }
    std::println("random instances ({} each) vs full-table / exhaustive oracles:", trials);
    std::println("   edit distance: rolling rows == memoized recursion == full table  {}/{}", ok_edit, trials);
    std::println("   Hirschberg alignment transforms a into b at optimal cost        {}/{}", ok_hir, trials);
    std::println("   0/1 knapsack, reverse capacity loop                            {}/{} | forward loop (contest slip) {}/{}", ok_knap,
                 trials, cp_knap, trials);
    std::println("   knapsack items reconstructed: fit the capacity, sum to the optimum {}/{}", ok_items, trials);
    std::println("   LIS O(n log n) returns an increasing subsequence of optimal length {}/{}", ok_lis, trials);

    using clock = std::chrono::steady_clock;
    auto ms = [](clock::duration d) { return std::chrono::duration<double, std::milli>(d).count(); };
    std::string a = r.fixed(1'000, 4), b = r.fixed(1'000, 4);
    auto t0 = clock::now();
    int x = edit_distance(a, b);
    auto t1 = clock::now();
    std::unordered_map<std::uint64_t, int> memo;
    int y = memo_edit(a, b, a.size(), b.size(), memo);
    auto t2 = clock::now();
    std::println("constants, 1,000 x 1,000 = 1 M states (one measured run): rolling arrays {:.1f} ms | hash-memoized recursion"
                 " {:.1f} ms ({:.0f}x) | equal {}", ms(t1 - t0), ms(t2 - t1), ms(t2 - t1) / ms(t1 - t0), x == y);
    std::string big1 = r.fixed(6'000, 4), big2 = r.fixed(6'000, 4);
    int tiles = (6'000 + 255) / 256;
    auto s0 = clock::now();
    int seq = edit_distance(big1, big2);
    auto s1 = clock::now();
    int par = wavefront(big1, big2, 8, 256);
    auto s2 = clock::now();
    std::println("A. 6,000 x 6,000 edit distance (one measured run): rolling rows {:.0f} ms | 8-thread tiled wavefront (256x256 tiles,"
                 " {} tile diagonals) {:.0f} ms | equal {}", ms(s1 - s0), 2 * tiles - 1, ms(s2 - s1), seq == par);
}
```

**Output, GCC 16.2 (verified; the last two lines are one measured run):**

```text
random instances (3000 each) vs full-table / exhaustive oracles:
   edit distance: rolling rows == memoized recursion == full table  3000/3000
   Hirschberg alignment transforms a into b at optimal cost        3000/3000
   0/1 knapsack, reverse capacity loop                            3000/3000 | forward loop (contest slip) 1099/3000
   knapsack items reconstructed: fit the capacity, sum to the optimum 3000/3000
   LIS O(n log n) returns an increasing subsequence of optimal length 3000/3000
constants, 1,000 x 1,000 = 1 M states (one measured run): rolling arrays 2.3 ms | hash-memoized recursion 95.4 ms (41x) | equal true
A. 6,000 x 6,000 edit distance (one measured run): rolling rows 83 ms | 8-thread tiled wavefront (256x256 tiles, 47 tile diagonals) 92 ms | equal true
```

**Output, Clang 21.1 (verified; the last two lines are one measured run):**

```text
random instances (3000 each) vs full-table / exhaustive oracles:
   edit distance: rolling rows == memoized recursion == full table  3000/3000
   Hirschberg alignment transforms a into b at optimal cost        3000/3000
   0/1 knapsack, reverse capacity loop                            3000/3000 | forward loop (contest slip) 1099/3000
   knapsack items reconstructed: fit the capacity, sum to the optimum 3000/3000
   LIS O(n log n) returns an increasing subsequence of optimal length 3000/3000
constants, 1,000 x 1,000 = 1 M states (one measured run): rolling arrays 1.2 ms | hash-memoized recursion 135.4 ms (114x) | equal true
A. 6,000 x 6,000 edit distance (one measured run): rolling rows 45 ms | 8-thread tiled wavefront (256x256 tiles, 47 tile diagonals) 91 ms | equal true
```

---

## 3. What the results show

* **Reconstructions are verified, not trusted.** Every Hirschberg alignment is *applied* to a and must produce b at exactly the optimal number of edits. Every knapsack item set must fit the capacity and sum to the optimum. Every LIS must be increasing, a subsequence, and of optimal length. That's 3,000/3,000 each, in both languages.
* **Loop direction is a correctness property:** forward-loop knapsack 1,099/3,000.
* **The memo constant:** a 1 M-state edit distance took 4.5–5 ms with rolling arrays and 753–871 ms with a `HashMap<Long, Integer>` memo in Java (168–173×). On the first, larger 4 M-state run it was 9.1 s against 20 ms (453×), because boxing and GC grow with the table. C++ `unordered_map`: 41–114×.
* **Parallelizing a cache-friendly DP can lose.** The tiled anti-diagonal wavefront for a 6,000 × 6,000 edit distance must materialize the full 36 M-cell table (144 MB), while the sequential rolling-row version keeps two 24 KB rows in L1/L2. Java: 169–185 ms sequential vs 93–130 ms on 8 threads, only 1.4–1.8×. C++: GCC 83–85 vs 83–92 ms (no gain), Clang 44–45 vs 91–92 ms (the parallel version is **2× slower**). Parallelism multiplied memory traffic more than it divided compute. A better parallel design streams anti-diagonal buffers (O(n) memory per tile row) instead of the full table ⚠ (not implemented here).

---

## 4. The last 10 minutes: Extensions A, B and C

### 4.1 Extension A — "64 threads"

* **Which DPs parallelize:** states whose dependencies form a DAG with wide antichains. Grid DPs (edit distance, LCS) parallelize by anti-diagonal. Interval DPs by interval length (File 2 measures 3–4×). Layered DPs (knapsack over items) parallelize *within* a layer: for item i, every capacity c reads layer i − 1 only, if you keep two arrays instead of one in-place array.
* **Tile, don't parallelize cells.** A barrier per anti-diagonal of *cells* (12,000 barriers for 6,000 × 6,000) is pure overhead; tiles of 256 × 256 reduce it to 47.
* **Memory traffic decides.** As measured, parallel versions that need the full table can lose to a sequential rolling version. Measure before promising a speedup, and prefer designs that keep per-tile working sets in cache.
* **Many independent DPs** (one per request, as in a spell-checker scoring candidates) parallelize trivially: one per thread, no sharing.

### 4.2 Extension B — "the strings are 10 GB each"

* **Hirschberg** gives linear memory: 2 × 10 GB of input plus O(n) rows. The O(nm) *time* is the real problem at that scale.
* **Banded DP:** if the edit distance is known to be ≤ k (similar documents, read alignment), only cells with |i − j| ≤ k matter: O(nk) time and O(k) memory (Ukkonen). The diff tools behind version control rely on Myers' O(ND) algorithm, where D is the edit distance: fast exactly when files are similar.
* **Streaming decisions:** when the DP runs left to right and only the current row matters, input can be streamed from disk with O(row) memory. The knapsack's decision bits can be spilled to disk in row order and read backwards for reconstruction: sequential I/O both ways.

### 4.3 Extension C — "the DP is too big for one machine"

* **Wavefront across machines:** partition the grid into column blocks, one per machine. Machine k computes its block row by row and streams its **last column** to machine k + 1. It's a pipeline whose throughput approaches S× after the initial fill. Messages are O(rows) per block boundary.
* **Divide and conquer à la Hirschberg distributes naturally:** the midpoint split produces two independent sub-problems with known boundary values, which are then shipped to different machines.
* **Many small DPs** (alignment of millions of read pairs) are the common case at scale. Distribute the *problems*, not the table: a map over pairs, each solved locally. Recognizing that is usually the right answer.

---

## 5. Failure modes

| # | Failure | Symptom | Prevention |
|---|---|---|---|
| F1 | Insufficient state | Wrong on inputs where history matters | One-sentence state definition; test against brute force |
| F2 | Wrong in-place loop direction | 0/1 knapsack becomes unbounded (63% wrong) | Reverse the loop, or two arrays; comment why |
| F3 | Rolling array, then asked for the path | Path unrecoverable | Decision bits, or Hirschberg |
| F4 | Unverified reconstruction | A "solution" whose cost differs from the reported optimum | Re-evaluate the reconstruction in tests |
| F5 | Hash-map memo on dense states | 41–453× slower; GC pressure | Dense arrays, bottom-up |
| F6 | Deep memo recursion | Stack overflow at depth n + m | Bottom-up, or explicit stack |
| F7 | `int` accumulators | Overflow in value DPs | `long`, stated bound |
| F8 | Parallelizing by materializing the full table | Slower than sequential | Tiles with small working sets; measure |

---

## 6. Bar-raiser chains

<details><summary><b>Q1 · "What exactly does dp[i][j] represent?"</b></summary>

**Initial Prompt.** After an edit-distance solution.

**L5 Answer.** "The answer for i and j."

**Why L5 Stalls.** Vague states hide wrong recurrences and can't be extended.

**L7 Answer.** "The minimum edits turning the first i characters of a into the first j of b. It's sufficient because how those prefixes were aligned doesn't constrain the rest. The last operation is a match/substitute (from i−1, j−1), a delete (from i−1, j) or an insert (from i, j−1), so the recurrence is the min of those three plus their costs. Base cases are the empty prefixes: i deletions or j insertions."
</details>

<details><summary><b>Q2 · "Can you do it in less memory?"</b></summary>

**Initial Prompt.** The table is n × m.

**L5 Answer.** "Keep two rows."

**Why L5 Stalls.** Correct for the value; the follow-up is "now return the alignment", and two rows can't.

**L7 Answer.** "Two rows give the distance in O(min(n, m)) memory. For the alignment too, Hirschberg: split a at the middle, run a forward pass on the first half and a backward pass on the reversed second half, pick the column where forward plus backward is minimal, and recurse on both sides. O(nm) time, O(n + m) memory, log-depth recursion. I verify the output by applying the edits and checking they produce b at the optimal cost."
</details>

<details><summary><b>Q3 · "0/1 knapsack in one array: why does your loop go backwards?"</b></summary>

**Initial Prompt.** The candidate wrote the reversed loop, perhaps from memory.

**L5 Answer.** "That's the standard way."

**Why L5 Stalls.** Memorized, not understood, so it won't transfer to variants.

**L7 Answer.** "In place, `dp[c − w]` must still hold the value *without* item i when I compute `dp[c]`. Going downwards, every index below c is untouched by item i. Going upwards I'd read a value that already includes item i and use it again: that's the unbounded knapsack. On random instances the forward loop is wrong about 63% of the time. If I wanted unbounded, forward would be right; the loop direction encodes which problem I'm solving."
</details>

<details><summary><b>Q4 · "Which items did you pick?"</b></summary>

**Initial Prompt.** Reconstruction.

**L5 Answer.** Tries to infer items from the final 1D array and can't.

**Why L5 Stalls.** The 1D array has overwritten the decision history.

**L7 Answer.** "I record one decision bit per (item, capacity): did item i improve dp[c]? That's n × W bits. Walking items from last to first, if the bit for the current capacity is set, take the item and subtract its weight. I verify the set fits and sums to the optimum. If n × W bits is too much, Hirschberg-style divide and conquer over items recovers the set in O(W) memory at about 2× the time."
</details>

<details><summary><b>Q5 · "Your memoized recursion is clean. Ship it?"</b></summary>

**Initial Prompt.** Top-down DP with a HashMap memo.

**L5 Answer.** "Yes, same complexity as bottom-up."

**Why L5 Stalls.** Same Big-O, very different constant, plus recursion depth.

**L7 Answer.** "Same O(nm), but every state costs a hash lookup and, in Java, boxed keys and values. I measured 168–173× slower than rolling arrays for 1 M states, and 453× at 4 M once GC kicked in. Recursion depth also reaches n + m. For a dense grid I'd ship bottom-up arrays. I'd keep memoization for sparse state spaces where only a small fraction of states is reachable."
</details>

<details><summary><b>Q6 · "Parallelize edit distance on 8 cores."</b></summary>

**Initial Prompt.** Extension A.

**L5 Answer.** "Cells on the same anti-diagonal are independent; parallelize each diagonal."

**Why L5 Stalls.** Right dependency insight, but per-cell barriers and full-table memory dominate.

**L7 Answer.** "Anti-diagonals of tiles, not cells, so 47 barriers instead of 12,000 for a 6,000 × 6,000 table. But I'd measure first. The sequential two-row version lives in L1, and the parallel one I tried materialized a 144 MB table. It gained only 1.4–1.8× in Java and was slower in one C++ build. A real speedup needs tiles that pass only their boundary rows and columns, not a full table. And if there are many independent alignments, parallelize across them instead."
</details>

<details><summary><b>Q7 · "Diff two 10 GB files."</b></summary>

**Initial Prompt.** Extension B.

**L5 Answer.** "Edit distance DP."

**Why L5 Stalls.** 10¹⁰ × 10¹⁰ cells is impossible in time, not just memory.

**L7 Answer.** "Quadratic is out, so I'd exploit similarity. Real diffs use Myers' O(ND) algorithm, where D is the number of differences: fast when files are similar, which is the common case. Or a banded DP if I can bound the distance. In practice I'd first chunk both files with content-defined boundaries and hashes, match identical chunks, and run detailed alignment only inside mismatched regions. Linear-space reconstruction (Hirschberg) keeps memory bounded within each region."
</details>

<details><summary><b>Q8 · "LIS — and give me the subsequence, not just its length."</b></summary>

**Initial Prompt.** LeetCode 300 with reconstruction.

**L5 Answer.** O(n²) DP with parent pointers, or O(n log n) length only.

**Why L5 Stalls.** Either too slow for 10⁶ or missing the reconstruction.

**L7 Answer.** "Patience sorting: tails[k] is the index of the smallest tail of an increasing subsequence of length k+1. Each element binary-searches the first tail ≥ it, replaces it, and records a parent pointer to the previous tail. That's O(n log n). Following parents from the last tail gives an optimal subsequence. I'd test that the output is increasing, is a subsequence, and has the length an O(n²) oracle computes."
</details>

---

## 7. Checklist

* [ ] One-sentence state definition; sufficiency argued.
* [ ] Transition order = topological order of the state DAG.
* [ ] Rolling arrays: say which direction and why.
* [ ] Reconstruction: decision bits or Hirschberg; verify by re-evaluation.
* [ ] Dense states → arrays bottom-up; sparse → memo.
* [ ] `long` values; overflow bounds stated.
* [ ] Extension A: tiles, layers, independent problems; measure memory traffic.
* [ ] Extension B: Hirschberg memory, banded/O(ND) time, streaming rows.
* [ ] Extension C: pipelined column blocks; distribute problems, not tables.

---

## 8. References

* D. S. Hirschberg, *A Linear Space Algorithm for Computing Maximal Common Subsequences*, CACM 18(6), 1975 — DOI 10.1145/360825.360861
* E. W. Myers, *An O(ND) Difference Algorithm and Its Variations*, Algorithmica 1, 1986 — DOI 10.1007/BF01840446
* E. Ukkonen, *Algorithms for Approximate String Matching*, Information and Control 64, 1985 — DOI 10.1016/S0019-9958(85)80046-2
* R. Bellman, *Dynamic Programming*, Princeton University Press, 1957.
* cp-algorithms: [Longest increasing subsequence](https://cp-algorithms.com/sequences/longest_increasing_subsequence.html), [Knapsack](https://cp-algorithms.com/dynamic_programming/knapsack.html)
* LeetCode anchors: [72 Edit Distance](https://leetcode.com/problems/edit-distance/), [300 Longest Increasing Subsequence](https://leetcode.com/problems/longest-increasing-subsequence/), [416 Partition Equal Subset Sum](https://leetcode.com/problems/partition-equal-subset-sum/), [1143 Longest Common Subsequence](https://leetcode.com/problems/longest-common-subsequence/)

*Folder 05:* [02 — interval DP, rerooting, digit DP](02-interval-dp-tree-dp-rerooting-and-digit-dp-blueprints.md) · [03 — bitmask, SOS, monotonic-queue and D&C DP](03-bitmask-dp-sos-dp-monotonic-queue-dp-and-divide-and-conquer-dp.md)
