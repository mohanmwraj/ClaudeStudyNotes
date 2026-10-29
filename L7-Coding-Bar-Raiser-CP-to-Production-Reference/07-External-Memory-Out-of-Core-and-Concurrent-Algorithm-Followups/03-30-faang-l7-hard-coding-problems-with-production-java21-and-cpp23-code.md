# 30 Hard Coding Problems with Production Java 21 and C++23 Code

> **Folder 07 · File 3 of 3** — thirty classic hard interview problems, each solved once in production style in both languages, each **tested against a brute-force oracle or a reference model on 1,000 random instances**, and each given its own "last 10 minutes": what changes with 64 threads, with an unbounded stream or 100 TB, and with 100 machines. The problems are well-known public LeetCode problems of the kind used in senior coding loops; nothing here is a claim about any particular company's question bank.
> **Languages:** Java 21 (`--release 21 -Xlint:all -Werror`, JDK 25.0.4.1) and C++23 (GCC 16.2 and Clang 21.1, `-O2`, `-Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wsign-conversion`, warnings as errors).

| Listing | File | What it proves |
|---|---|---|
| 7.5 | `L7Problems.java` | 30 solutions × 1,000 random trials, each checked against an independent oracle or model: 30,000 of 30,000 trials pass. A 100,000-node degenerate tree serializes and deserializes without recursion |
| 7.6 | `l7_problems.cpp` | The same 30 solutions in C++23. Same SplitMix64 stream, same instances, same draw order: the output is **byte-identical** to Java's under both compilers |

**Verification.** Both listings were extracted from this file, compiled and run. All output is **Output (verified)**: deterministic, and byte-for-byte identical across Java, GCC and Clang. A separate mutation run (§4) planted nine classic bugs one at a time and checked that the oracles notice.

---

## 0. Orientation

At L6/L7 the algorithm is table stakes. Two candidates who both reach the optimal complexity are separated by everything around it: whether the code states and protects its invariants, survives inputs the examples didn't show, stays correct when the data is 10⁵ levels deep or the values overflow 32 bits, comes with a credible test, and can be extended when the interviewer adds threads, streams or machines. Every solution in this file is written to that bar, and the table below lists the habits it replaces.

| Contest habit | Where it bites in these 30 problems | Production replacement |
|---|---|---|
| Recursive DFS on trees and graphs | Recursive LC 297 / 124 / 1192 can overflow the default stack on a 10⁵-deep chain | Explicit stacks everywhere; the 100,000-node chain round-trips in both languages |
| `std::unique_ptr` child pointers in C++ trees | The destructor recurses: a deep tree overflows the stack when it is *freed* | An arena (`std::deque<Node>`) owns all nodes; destruction is a loop |
| `int` for every quantity | LC 84 area = height × width, LC 1235 profit sums, LC 743 distances exceed 2³¹ | `long` / `int64_t` for anything that multiplies or accumulates |
| Skip the parent **vertex** in low-link DFS | LC 1192 with parallel edges reports false bridges (59% of the planted-bug trials passed, 41% failed) | Skip the arriving **edge id** |
| Trust a hash match | LC 1044 can report a substring that isn't repeated: rare on random input (about L/2⁶¹ per compared pair), easy for an adversary against a fixed or 2⁶⁴ modulus | Verify every candidate; the algorithm becomes exact (Las Vegas) |
| Slopes as `double` | LC 149: 1/3 vs 0.333…, −0.0 vs 0.0, vertical lines | gcd-normalized integer direction with a canonical sign |
| `need[s[i]]` on a `char` | C++ `char` may be signed: negative index for bytes ≥ 0x80 | Index by `unsigned char` over 256 entries (C++); state the ASCII contract (Java) |
| No input validation | LC 239 with k > n, LC 4 with two empty arrays: garbage or an infinite loop | Validate and throw `IllegalArgumentException` / `std::invalid_argument` |
| `size() - 1` on an unsigned size | LC 42 on empty input: `0u - 1` = 2⁶⁴ − 1 | Guard the empty case first |
| Test on the examples | Most bugs live in duplicates, empties and ties | A brute-force oracle on 1,000 small random instances per problem, plus planted-bug checks |

---

## 1. First principles

### 1.1 What the bar-raiser is listening for

For each problem, five things, in this order:

1. **The invariant**, stated in one sentence before any code: "the deque holds indices of a decreasing subsequence of the window, so the front is the maximum." An invariant is what makes the code checkable and the complexity obvious.
2. **The complexity**, derived from the invariant: every index enters and leaves the deque once, so O(n).
3. **The edge cases the invariant implies**: empty input, k = n, duplicates (does the deque pop on `<=` or `<`?), ties, overflow.
4. **How you'd test it**: an oracle and random instances, not three hand-written examples.
5. **The extension**: what part of the invariant survives threads, streams and shards, and what replaces the part that doesn't.

### 1.2 How these 30 solutions are verified

Every problem's test has the same shape: generate a small random instance from the shared SplitMix64 stream, compute the answer with the production solution, compute it again with an **oracle** that shares no code or idea with it, compare. 1,000 trials per problem. The oracles are chosen to be obviously correct, even when slow:

* **Exhaustive search** where the space is small: every burst order (LC 312), every subset of jobs (LC 1235), every letter order (LC 269), every permutation of nodes over all-pairs shortest paths (LC 847), every substring (LC 76, LC 1044).
* **A naive model** for designs: a list in recency order for LRU, a (frequency, last-use) table for LFU, a sorted list for the running median, a timestamp list for the hit counter, an append-only log for the time map.
* **A different algorithm** for graphs: Floyd–Warshall against Dijkstra (LC 743), remove-each-edge-and-recount against low-link (LC 1192), BFS recount against union-find (LC 305), transitive closure against Kahn (LC 210).
* **Direct recursion** for DP: the exponential edit-distance recursion (LC 72), backtracking regex (LC 10), O(n²) LIS (LC 300).

Instances are deliberately **small** (a few to a few dozen elements, alphabets of 2–4 letters, values from tiny ranges). That makes the exponential oracles affordable, and it makes duplicates, ties, empties and degenerate shapes appear constantly. A random array of 10 values from 0..9 almost always contains a duplicate; a random array of 10 values from 0..2³¹ almost never does.

**Same instances in both languages.** Both listings draw every random number from the same SplitMix64 generator, in the same order, one draw per statement (C++ leaves the evaluation order of function arguments unspecified, so `f(R.next(), R.next())` would differ between compilers). The printed pass counts are therefore the same lines, and the whole output is byte-identical.

### 1.3 What random testing can't see

Random testing found every bug planted in §4 except one: deleting the verification step from the rolling-hash search in LC 1044. Without verification, a hash match is trusted, and two different substrings with the same hash would be reported as a duplicate. With a random base modulo the Mersenne prime 2⁶¹ − 1, a collision between two specific substrings of length L has probability at most L/2⁶¹ (two distinct polynomials of degree < L agree on at most L − 1 points). Random tests never hit that.

But the input is not always random. A fixed base, or a modulus of 2⁶⁴ (natural overflow), can be attacked: Thue–Morse strings collide under any odd base modulo 2⁶⁴, and anti-hash tests exist for common fixed moduli (Folder 06 File 1 has the details). So the property "this code is correct on every input" can't come from testing here. It comes from an argument: **verify every hash match by direct comparison**, which costs O(L) only when hashes agree, and the algorithm is exact, with only its running time depending on luck.

---

## 2. The 30 problems at a glance

The numbering matches the listings and the output. "Production delta" is what the listing does beyond a typical accepted solution.

### 2.1 Designs: 1–3, 27, 28

| # | Problem | Invariant | Time / space | Production delta |
|---|---|---|---|---|
| 1 | LC 146 LRU cache | Hash map from key to a node of a recency list; the list's tail is the least recently used | O(1) per op / O(capacity) | Capacity validated. Java: `LinkedHashMap` in access order. C++: `std::list::splice` moves a node in O(1) without invalidating the map's iterators |
| 2 | LC 460 LFU cache | key → (value, freq, position); freq → keys in recency order; `minFreq` resets to 1 on insert and otherwise rises only when its bucket empties | O(1) per op / O(capacity) | Eviction tie-break (least recently used among the least frequent) checked against a model, not assumed. C++ splices between buckets, keeping positions valid |
| 3 | LC 295 Median from a data stream | Max-heap `low` and min-heap `high`; max(low) ≤ min(high); \|low\| − \|high\| ∈ {0, 1} | O(log n) add, O(1) median / O(n) | Every add routes through the other heap, so one code path restores both invariants; the even-size median is computed in `double` without integer overflow |
| 27 | LC 362 Design hit counter | A ring of 300 buckets indexed by second mod 300; a bucket whose stored second is stale is ignored | O(1) hit, O(300) count / O(300) | Memory independent of the hit rate (a queue of timestamps grows with traffic) |
| 28 | LC 981 Time-based key-value store | Per key, a sorted map from timestamp to value; `get` is a floor lookup | O(log n) / O(n) | Java `TreeMap.floorEntry`; C++ `upper_bound` then step back. Doesn't rely on timestamps arriving in order |

### 2.2 Arrays, windows, stacks and heaps: 4–8

| # | Problem | Invariant | Time / space | Production delta |
|---|---|---|---|---|
| 4 | LC 239 Sliding window maximum | Deque of indices with strictly decreasing values; the front is the window maximum; indices ≤ i − k expire from the front | O(n) / O(k) | k validated (k ≤ 0 or k > n throws) |
| 5 | LC 76 Minimum window substring | `need[c]` counts what the window still owes; `missing` counts owed characters; shrink while `missing == 0` | O(\|s\| + \|t\|) / O(alphabet) | Java states an ASCII contract; C++ indexes by `unsigned char` over 256 entries, so any byte is safe |
| 6 | LC 42 Trapping rain water | Two pointers: the side with the lower wall is settled by its own running maximum | O(n) / O(1) | `long` total; C++ guards the empty input before `size() - 1` |
| 7 | LC 84 Largest rectangle in histogram | Increasing stack of indices; a popped bar extends from the new top + 1 to i − 1 | O(n) / O(n) | Area in `long`; a virtual height-0 bar at the end flushes the stack |
| 8 | LC 23 Merge k sorted lists | Heap of the current heads, one per list | O(N log k) / O(k) | Ties broken by list index: deterministic output. The same code is the merge phase of an external sort (File 1) |

### 2.3 Graphs: 9–14

| # | Problem | Invariant | Time / space | Production delta |
|---|---|---|---|---|
| 9 | LC 127 Word ladder | BFS by levels; words sharing a wildcard pattern ("h*t") are neighbours | O(N·L²) / O(N·L) | Pattern buckets instead of comparing all word pairs (O(N²·L)); 0 when the target isn't in the dictionary |
| 10 | LC 210 Course schedule II | Kahn: repeatedly remove an indegree-0 vertex; a cycle exists iff fewer than n are removed | O(V + E) | Empty result means "cycle", documented; the oracle checks both a valid order and that a reported cycle is real |
| 11 | LC 743 Network delay time | Dijkstra: a vertex's distance is final when it's popped with its current distance; stale heap entries are skipped | O(E log V) | `long` distances; −1 when unreachable |
| 12 | LC 1192 Critical connections | Edge (p, u) is a bridge iff low[u] > tin[p]; the DFS skips the **edge** it arrived by, not the parent vertex | O(V + E) | Iterative DFS (no recursion at 10⁵ vertices); correct with parallel edges |
| 13 | LC 305 Number of islands II | Union-find over land cells; count + 1 per new cell, − 1 per successful union | O(k·α(n)) | Re-adding an existing cell is a no-op; path halving |
| 14 | LC 269 Alien dictionary | The first differing letter of adjacent words gives an edge; a word before its own proper prefix is invalid; topological sort | O(total letters) | Detects the prefix case and cycles; smallest-letter-first order makes the output deterministic |

### 2.4 Trees: 15–16

| # | Problem | Invariant | Time / space | Production delta |
|---|---|---|---|---|
| 15 | LC 297 Serialize and deserialize binary tree | Preorder with `#` for null; deserialization keeps a stack of nodes still waiting for a left or right child | O(n) / O(height) | No recursion in either direction: a 100,000-node chain round-trips. C++ owns nodes in an arena and validates every token (`std::from_chars`, extra tokens rejected) |
| 16 | LC 124 Binary tree maximum path sum | gain(v) = val + max(0, gain(left), gain(right)); best path through v = val + max(0, gain(l)) + max(0, gain(r)) | O(n) / O(n) | Post-order by reversing an explicit-stack preorder; `long` sums |

### 2.5 Range structures and tries: 17–19

| # | Problem | Invariant | Time / space | Production delta |
|---|---|---|---|---|
| 17 | LC 315 Count of smaller numbers after self | Scan right to left; a Fenwick tree over value ranks counts what's already been seen | O(n log n) / O(n) | Coordinate compression; "strictly smaller" is a prefix query up to rank − 1, and the planted off-by-one (§4) is caught |
| 18 | LC 732 My calendar III | A sorted map of +1/−1 deltas; the answer is the maximum prefix sum | O(n) per booking / O(n) | Right for the problem's limits (400 bookings); a lazy segment tree (Folder 03) gives O(log n) per booking at scale |
| 19 | LC 212 Word search II | DFS from every cell, guided by a trie; stop as soon as the path isn't a prefix | O(cells · 4 · 3^(L−1)) worst case | Trie as flat arrays; C++ takes the board by value (the caller's board is never mutated); recursion depth ≤ longest word |

### 2.6 Dynamic programming and hashing: 20–26

| # | Problem | Invariant | Time / space | Production delta |
|---|---|---|---|---|
| 20 | LC 300 Longest increasing subsequence | tails[k] = smallest tail of an increasing subsequence of length k + 1; tails is increasing | O(n log n) / O(n) | Strict increase ⇒ lower bound; non-decreasing ⇒ upper bound: a one-character difference |
| 21 | LC 72 Edit distance | dp[i][j] = cost of turning a[..i) into b[..j); two rows suffice | O(mn) / O(n) | Rolling rows; Hirschberg recovers the alignment in linear space |
| 22 | LC 10 Regular expression matching | dp[i][j] = s[i..] matches p[j..]; `x*` = skip the pair, or consume one x and stay | O(mn) / O(mn) | Bottom-up: no exponential backtracking on patterns like `a*a*a*…b` |
| 23 | LC 312 Burst balloons | Choose the **last** balloon k burst in (i, j): its neighbours are then i and j | O(n³) / O(n²) | Sentinel 1s at both ends remove special cases |
| 24 | LC 847 Shortest path visiting all nodes | BFS over states (node, visited set), started from every node at once | O(2ⁿ · n²) / O(2ⁿ · n) | Multi-source BFS; the 2ⁿ limit (n ≤ 12 in the problem) is stated, not hidden |
| 25 | LC 1235 Maximum profit in job scheduling | Sort by end; dp[i] = max(dp[i − 1], profit + dp[number of jobs ending ≤ this start]) | O(n log n) / O(n) | A job may start exactly when another ends (`<=`, and the planted `<` is caught); `long` profits |
| 26 | LC 1044 Longest duplicate substring | "A duplicate of length L exists" is monotone in L: binary search; rolling hash modulo 2⁶¹ − 1 with a random base; **every hash match verified** | O(n log n) expected / O(n) | Exact, not probabilistic; Mersenne-prime multiply via `Math.multiplyHigh` (Java) and `unsigned __int128` (C++) |

### 2.7 Math: 29–30

| # | Problem | Invariant | Time / space | Production delta |
|---|---|---|---|---|
| 29 | LC 4 Median of two sorted arrays | Binary search a cut i in the shorter array, with j = half − i in the other; the cut is right when aL ≤ bR and bL ≤ aR | O(log min(m, n)) / O(1) | Two empty arrays throw instead of looping or returning garbage; `half = (m + n + 1) / 2` (the planted `(m + n) / 2` is caught) |
| 30 | LC 149 Max points on a line | For each anchor, count directions to the other points, normalized by gcd with a canonical sign; duplicates of the anchor are counted separately | O(n² log C) / O(n) | No floating point; the packed direction key is documented for the coordinate range |

---

## 3. The listings

### 3.1 Listing 7.5 — Java

Each problem is a static method or a small final class. The test harness at the bottom (`main`) generates instances and runs one oracle per problem, and `report` prints the pass count. Oracles live after the solutions and share no code with them.

```java
// L7Problems.java - 30 hard interview problems, production-style, each checked against a brute-force oracle or model.
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.PriorityQueue;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.function.IntSupplier;

public final class L7Problems {

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
        int range(int lo, int hi) { return lo + nextInt(hi - lo + 1); }
        int[] ints(int n, int lo, int hi) { int[] a = new int[n]; for (int i = 0; i < n; i++) a[i] = range(lo, hi); return a; }
        String word(int len, int alphabet) { StringBuilder sb = new StringBuilder(); for (int i = 0; i < len; i++) sb.append((char) ('a' + nextInt(alphabet))); return sb.toString(); }
    }

    static final SplitMix64 R = new SplitMix64(181);
    static int failures = 0;

    static void report(int id, String lc, String name, IntSupplier oneTrialPasses, int trials) {
        int ok = 0;
        for (int t = 0; t < trials; t++) ok += oneTrialPasses.getAsInt();
        if (ok != trials) failures++;
        System.out.printf("%2d. %-8s %-46s %5d/%d%n", id, lc, name, ok, trials);
    }

    // ===================================================================== 1-3, 27-28: designs (checked against models)
    /** LC 146. O(1) get/put; LinkedHashMap in access order is a hash map threaded with a recency list. */
    static final class LruCache {
        private final int capacity;
        private final LinkedHashMap<Integer, Integer> map = new LinkedHashMap<>(16, 0.75f, true);
        LruCache(int capacity) { if (capacity <= 0) throw new IllegalArgumentException("capacity"); this.capacity = capacity; }
        int get(int key) { Integer v = map.get(key); return v == null ? -1 : v; }
        void put(int key, int value) {
            map.put(key, value);
            if (map.size() > capacity) { Iterator<Integer> it = map.keySet().iterator(); it.next(); it.remove(); }
        }
    }

    /** LC 460. O(1): key -> (value, freq), freq -> keys in recency order, and the current minimum frequency. */
    static final class LfuCache {
        private final int capacity;
        private final Map<Integer, int[]> entries = new HashMap<>();
        private final Map<Integer, LinkedHashSet<Integer>> byFreq = new HashMap<>();
        private int minFreq;
        LfuCache(int capacity) { this.capacity = capacity; }
        private void touch(int key) {
            int[] e = entries.get(key);
            LinkedHashSet<Integer> set = byFreq.get(e[1]);
            set.remove(key);
            if (set.isEmpty()) { byFreq.remove(e[1]); if (minFreq == e[1]) minFreq++; }
            e[1]++;
            byFreq.computeIfAbsent(e[1], f -> new LinkedHashSet<>()).add(key);
        }
        int get(int key) { if (!entries.containsKey(key)) return -1; touch(key); return entries.get(key)[0]; }
        void put(int key, int value) {
            if (capacity == 0) return;
            if (entries.containsKey(key)) { entries.get(key)[0] = value; touch(key); return; }
            if (entries.size() == capacity) {
                LinkedHashSet<Integer> set = byFreq.get(minFreq);
                int victim = set.iterator().next();
                set.remove(victim);
                if (set.isEmpty()) byFreq.remove(minFreq);
                entries.remove(victim);
            }
            entries.put(key, new int[] {value, 1});
            byFreq.computeIfAbsent(1, f -> new LinkedHashSet<>()).add(key);
            minFreq = 1;
        }
    }

    /** LC 295. Max-heap of the lower half, min-heap of the upper half, sizes differ by at most one. */
    static final class MedianFinder {
        private final PriorityQueue<Integer> low = new PriorityQueue<>(Collections.reverseOrder()), high = new PriorityQueue<>();
        void add(int x) {
            low.add(x);
            high.add(low.poll());
            if (high.size() > low.size()) low.add(high.poll());
        }
        double median() { return low.size() > high.size() ? low.peek() : (low.peek() + (double) high.peek()) / 2; }
    }

    /** LC 362. Hits in the last 300 s: a ring of 300 (second, count) buckets. O(1) memory per second of window. */
    static final class HitCounter {
        private final int[] times = new int[300], counts = new int[300];
        void hit(int t) { int i = t % 300; if (times[i] != t) { times[i] = t; counts[i] = 0; } counts[i]++; }
        int hits(int t) { int s = 0; for (int i = 0; i < 300; i++) if (t - times[i] < 300 && times[i] <= t && counts[i] > 0) s += counts[i]; return s; }
    }

    /** LC 981. Per key, a sorted map from timestamp to value; get = floor lookup. O(log n). */
    static final class TimeMap {
        private final Map<String, TreeMap<Integer, String>> data = new HashMap<>();
        void set(String k, String v, int ts) { data.computeIfAbsent(k, x -> new TreeMap<>()).put(ts, v); }
        String get(String k, int ts) { TreeMap<Integer, String> m = data.get(k); if (m == null) return ""; Map.Entry<Integer, String> e = m.floorEntry(ts); return e == null ? "" : e.getValue(); }
    }

    // ===================================================================== 4-8: arrays, windows, stacks, heaps
    static int[] windowMax(int[] a, int k) {                                       // LC 239
        if (k <= 0 || k > a.length) throw new IllegalArgumentException("k=" + k + " for n=" + a.length);
        int[] out = new int[a.length - k + 1], dq = new int[a.length];
        int head = 0, tail = 0;
        for (int i = 0; i < a.length; i++) {
            while (tail > head && a[dq[tail - 1]] <= a[i]) tail--;
            dq[tail++] = i;
            if (dq[head] <= i - k) head++;
            if (i >= k - 1) out[i - k + 1] = a[dq[head]];
        }
        return out;
    }

    static String minWindow(String s, String t) {                                  // LC 76, ASCII
        int[] need = new int[128];
        for (char c : t.toCharArray()) need[c]++;
        int missing = t.length(), bestL = 0, bestLen = Integer.MAX_VALUE;
        for (int l = 0, r = 0; r < s.length(); r++) {
            if (need[s.charAt(r)]-- > 0) missing--;
            while (missing == 0) {
                if (r - l + 1 < bestLen) { bestLen = r - l + 1; bestL = l; }
                if (++need[s.charAt(l++)] > 0) missing++;
            }
        }
        return bestLen == Integer.MAX_VALUE ? "" : s.substring(bestL, bestL + bestLen);
    }

    static long trap(int[] h) {                                                    // LC 42
        int l = 0, r = h.length - 1, lm = 0, rm = 0;
        long water = 0;
        while (l < r) {
            if (h[l] < h[r]) { lm = Math.max(lm, h[l]); water += lm - h[l++]; }   // the lower side is the binding wall
            else { rm = Math.max(rm, h[r]); water += rm - h[r--]; }
        }
        return water;
    }

    static long largestRectangle(int[] h) {                                        // LC 84
        int[] st = new int[h.length + 1];
        int top = 0;
        long best = 0;
        for (int i = 0; i <= h.length; i++) {
            int cur = i == h.length ? 0 : h[i];
            while (top > 0 && h[st[top - 1]] >= cur) {
                long height = h[st[--top]], width = top == 0 ? i : i - st[top - 1] - 1;
                best = Math.max(best, height * width);
            }
            st[top++] = i;
        }
        return best;
    }

    static int[] mergeK(int[][] lists) {                                           // LC 23
        PriorityQueue<int[]> pq = new PriorityQueue<>((x, y) -> x[0] != y[0] ? Integer.compare(x[0], y[0]) : Integer.compare(x[1], y[1]));
        int total = 0;
        int[] pos = new int[lists.length];
        for (int i = 0; i < lists.length; i++) { total += lists[i].length; if (lists[i].length > 0) pq.add(new int[] {lists[i][0], i}); }
        int[] out = new int[total];
        for (int k = 0; !pq.isEmpty(); k++) {
            int[] e = pq.poll();
            out[k] = e[0];
            if (++pos[e[1]] < lists[e[1]].length) pq.add(new int[] {lists[e[1]][pos[e[1]]], e[1]});
        }
        return out;
    }

    // ===================================================================== 9-14: graphs
    static int ladderLength(String begin, String end, List<String> words) {        // LC 127
        Set<String> dict = new HashSet<>(words);
        if (!dict.contains(end)) return 0;
        Map<String, List<String>> buckets = new HashMap<>();                       // "h*t" -> words: no O(n^2) adjacency
        for (String w : dict) for (int i = 0; i < w.length(); i++) buckets.computeIfAbsent(w.substring(0, i) + '*' + w.substring(i + 1), x -> new ArrayList<>()).add(w);
        Map<String, Integer> dist = new HashMap<>(Map.of(begin, 1));
        ArrayDeque<String> q = new ArrayDeque<>(List.of(begin));
        while (!q.isEmpty()) {
            String u = q.poll();
            if (u.equals(end)) return dist.get(u);
            for (int i = 0; i < u.length(); i++)
                for (String v : buckets.getOrDefault(u.substring(0, i) + '*' + u.substring(i + 1), List.of()))
                    if (!dist.containsKey(v)) { dist.put(v, dist.get(u) + 1); q.add(v); }
        }
        return 0;
    }

    static int[] courseOrder(int n, int[][] prereq) {                              // LC 210: empty array = cycle
        List<List<Integer>> adj = new ArrayList<>();
        for (int i = 0; i < n; i++) adj.add(new ArrayList<>());
        int[] indeg = new int[n];
        for (int[] p : prereq) { adj.get(p[1]).add(p[0]); indeg[p[0]]++; }
        ArrayDeque<Integer> q = new ArrayDeque<>();
        for (int i = 0; i < n; i++) if (indeg[i] == 0) q.add(i);
        int[] order = new int[n];
        int k = 0;
        while (!q.isEmpty()) { int u = q.poll(); order[k++] = u; for (int v : adj.get(u)) if (--indeg[v] == 0) q.add(v); }
        return k == n ? order : new int[0];
    }

    static int networkDelay(int[][] times, int n, int src) {                       // LC 743, nodes 1..n
        List<List<int[]>> adj = new ArrayList<>();
        for (int i = 0; i <= n; i++) adj.add(new ArrayList<>());
        for (int[] t : times) adj.get(t[0]).add(new int[] {t[1], t[2]});
        long[] dist = new long[n + 1];
        Arrays.fill(dist, Long.MAX_VALUE);
        dist[src] = 0;
        PriorityQueue<long[]> pq = new PriorityQueue<>((x, y) -> Long.compare(x[0], y[0]));
        pq.add(new long[] {0, src});
        while (!pq.isEmpty()) {
            long[] e = pq.poll();
            int u = (int) e[1];
            if (e[0] > dist[u]) continue;                                           // stale entry
            for (int[] ed : adj.get(u)) if (dist[u] + ed[1] < dist[ed[0]]) { dist[ed[0]] = dist[u] + ed[1]; pq.add(new long[] {dist[ed[0]], ed[0]}); }
        }
        long worst = 0;
        for (int i = 1; i <= n; i++) worst = Math.max(worst, dist[i]);
        return worst == Long.MAX_VALUE ? -1 : (int) worst;
    }

    static List<List<Integer>> bridges(int n, int[][] edges) {                    // LC 1192, iterative low-link
        List<List<int[]>> adj = new ArrayList<>();
        for (int i = 0; i < n; i++) adj.add(new ArrayList<>());
        for (int e = 0; e < edges.length; e++) { adj.get(edges[e][0]).add(new int[] {edges[e][1], e}); adj.get(edges[e][1]).add(new int[] {edges[e][0], e}); }
        int[] tin = new int[n], low = new int[n], via = new int[n], it = new int[n];
        Arrays.fill(tin, -1);
        List<List<Integer>> out = new ArrayList<>();
        int timer = 0;
        for (int s = 0; s < n; s++) {
            if (tin[s] != -1) continue;
            ArrayDeque<Integer> st = new ArrayDeque<>();
            tin[s] = low[s] = timer++; via[s] = -1; st.push(s);
            while (!st.isEmpty()) {
                int u = st.peek();
                if (it[u] < adj.get(u).size()) {
                    int[] e = adj.get(u).get(it[u]++);
                    if (e[1] == via[u]) continue;                                   // skip the arriving EDGE, not the parent vertex
                    if (tin[e[0]] == -1) { tin[e[0]] = low[e[0]] = timer++; via[e[0]] = e[1]; st.push(e[0]); }
                    else low[u] = Math.min(low[u], tin[e[0]]);
                    continue;
                }
                st.pop();
                if (via[u] >= 0) {
                    int[] pe = edges[via[u]];
                    int p = pe[0] == u ? pe[1] : pe[0];
                    low[p] = Math.min(low[p], low[u]);
                    if (low[u] > tin[p]) out.add(List.of(Math.min(p, u), Math.max(p, u)));
                }
            }
        }
        return out;
    }

    static int[] islandsOnline(int rows, int cols, int[][] adds) {                 // LC 305
        int[] parent = new int[rows * cols];
        Arrays.fill(parent, -1);                                                   // -1 = water
        int[] out = new int[adds.length];
        int count = 0;
        for (int k = 0; k < adds.length; k++) {
            int c = adds[k][0] * cols + adds[k][1];
            if (parent[c] == -1) {
                parent[c] = c;
                count++;
                int[][] d = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}};
                for (int[] dd : d) {
                    int r2 = adds[k][0] + dd[0], c2 = adds[k][1] + dd[1];
                    if (r2 < 0 || c2 < 0 || r2 >= rows || c2 >= cols || parent[r2 * cols + c2] == -1) continue;
                    int a = find(parent, c), b = find(parent, r2 * cols + c2);
                    if (a != b) { parent[a] = b; count--; }
                }
            }
            out[k] = count;
        }
        return out;
    }

    static int find(int[] p, int x) { while (p[x] != x) { p[x] = p[p[x]]; x = p[x]; } return x; }

    static String alienOrder(String[] words) {                                     // LC 269
        Map<Character, Set<Character>> adj = new TreeMap<>();
        for (String w : words) for (char c : w.toCharArray()) adj.putIfAbsent(c, new HashSet<>());
        for (int i = 0; i + 1 < words.length; i++) {
            String a = words[i], b = words[i + 1];
            int j = 0;
            while (j < Math.min(a.length(), b.length()) && a.charAt(j) == b.charAt(j)) j++;
            if (j == Math.min(a.length(), b.length())) { if (a.length() > b.length()) return ""; continue; }  // "abc" before "ab": invalid
            adj.get(a.charAt(j)).add(b.charAt(j));
        }
        Map<Character, Integer> indeg = new TreeMap<>();
        for (char c : adj.keySet()) indeg.putIfAbsent(c, 0);
        for (Set<Character> s : adj.values()) for (char c : s) indeg.merge(c, 1, Integer::sum);
        PriorityQueue<Character> q = new PriorityQueue<>();
        indeg.forEach((c, d) -> { if (d == 0) q.add(c); });
        StringBuilder sb = new StringBuilder();
        while (!q.isEmpty()) { char c = q.poll(); sb.append(c); for (char v : adj.get(c)) if (indeg.merge(v, -1, Integer::sum) == 0) q.add(v); }
        return sb.length() == adj.size() ? sb.toString() : "";
    }

    // ===================================================================== 15-16: trees (iterative)
    static final class TreeNode {
        final int val;
        TreeNode left, right;
        TreeNode(int val) { this.val = val; }
    }

    static final Object NULL_MARK = new Object();                                  // ArrayDeque rejects null elements

    static String serialize(TreeNode root) {                                       // LC 297: preorder with '#', no recursion
        StringBuilder out = new StringBuilder();
        ArrayDeque<Object> work = new ArrayDeque<>();
        work.push(root == null ? NULL_MARK : root);
        while (!work.isEmpty()) {
            Object o = work.pop();
            if (out.length() > 0) out.append(',');
            if (o == NULL_MARK) { out.append('#'); continue; }
            TreeNode n = (TreeNode) o;
            out.append(n.val);
            work.push(n.right == null ? NULL_MARK : n.right);
            work.push(n.left == null ? NULL_MARK : n.left);
        }
        return out.toString();
    }

    static TreeNode deserialize(String data) {
        String[] tok = data.split(",");
        if (tok[0].equals("#")) return null;
        TreeNode root = new TreeNode(Integer.parseInt(tok[0]));
        ArrayDeque<TreeNode> st = new ArrayDeque<>();                              // nodes still waiting for children
        ArrayDeque<Integer> filled = new ArrayDeque<>();                           // 0 = needs left, 1 = needs right
        st.push(root); filled.push(0);
        for (int i = 1; i < tok.length; i++) {
            TreeNode child = tok[i].equals("#") ? null : new TreeNode(Integer.parseInt(tok[i]));
            if (st.isEmpty()) throw new IllegalArgumentException("extra tokens after a complete tree");
            TreeNode parent = st.peek();
            int side = filled.pop();
            if (side == 0) { parent.left = child; filled.push(1); }
            else { parent.right = child; st.pop(); }
            if (child != null) { st.push(child); filled.push(0); }
        }
        return root;
    }

    static boolean sameTree(TreeNode a, TreeNode b) {
        ArrayDeque<TreeNode[]> st = new ArrayDeque<>();
        st.push(new TreeNode[] {a, b});
        while (!st.isEmpty()) {
            TreeNode[] p = st.pop();
            if (p[0] == null || p[1] == null) { if (p[0] != p[1]) return false; continue; }
            if (p[0].val != p[1].val) return false;
            st.push(new TreeNode[] {p[0].left, p[1].left});
            st.push(new TreeNode[] {p[0].right, p[1].right});
        }
        return true;
    }

    static long maxPathSum(TreeNode root) {                                        // LC 124: post-order gains, iterative
        List<TreeNode> order = new ArrayList<>();
        ArrayDeque<TreeNode> st = new ArrayDeque<>();
        st.push(root);
        while (!st.isEmpty()) { TreeNode n = st.pop(); order.add(n); if (n.left != null) st.push(n.left); if (n.right != null) st.push(n.right); }
        Map<TreeNode, Long> gain = new HashMap<>();
        long best = Long.MIN_VALUE;
        for (int i = order.size() - 1; i >= 0; i--) {                              // children before parents
            TreeNode n = order.get(i);
            long l = Math.max(0, n.left == null ? 0 : gain.get(n.left)), r = Math.max(0, n.right == null ? 0 : gain.get(n.right));
            best = Math.max(best, n.val + l + r);
            gain.put(n, n.val + Math.max(l, r));
        }
        return best;
    }

    // ===================================================================== 17-19: range structures, tries
    static int[] countSmallerAfter(int[] a) {                                      // LC 315: Fenwick over compressed values
        int[] sorted = Arrays.stream(a).distinct().sorted().toArray();
        int[] fw = new int[sorted.length + 1], out = new int[a.length];
        for (int i = a.length - 1; i >= 0; i--) {
            int rank = Arrays.binarySearch(sorted, a[i]);                          // 0-based rank of a[i]
            int s = 0;
            for (int j = rank; j > 0; j -= j & -j) s += fw[j];                      // count of ranks < rank
            out[i] = s;
            for (int j = rank + 1; j < fw.length; j += j & -j) fw[j]++;
        }
        return out;
    }

    static final class MyCalendarThree {                                           // LC 732: sweep over a sorted delta map
        private final TreeMap<Integer, Integer> delta = new TreeMap<>();
        int book(int start, int end) {
            delta.merge(start, 1, Integer::sum);
            delta.merge(end, -1, Integer::sum);
            int cur = 0, best = 0;
            for (int d : delta.values()) best = Math.max(best, cur += d);
            return best;
        }
    }

    static List<String> findWords(char[][] board, String[] words) {               // LC 212: trie-guided DFS
        List<int[]> next = new ArrayList<>();
        List<String> wordAt = new ArrayList<>();
        next.add(new int[26]); wordAt.add(null);
        for (String w : words) {
            int v = 0;
            for (char c : w.toCharArray()) { if (next.get(v)[c - 'a'] == 0) { next.get(v)[c - 'a'] = next.size(); next.add(new int[26]); wordAt.add(null); } v = next.get(v)[c - 'a']; }
            wordAt.set(v, w);
        }
        Set<String> found = new HashSet<>();
        int rows = board.length, cols = board[0].length;
        for (int r0 = 0; r0 < rows; r0++)
            for (int c0 = 0; c0 < cols; c0++)
                dfs(board, r0, c0, 0, next, wordAt, found);                       // depth <= longest word: bounded recursion
        List<String> out = new ArrayList<>(found);
        Collections.sort(out);
        return out;
    }

    private static void dfs(char[][] b, int r, int c, int node, List<int[]> next, List<String> wordAt, Set<String> found) {
        if (r < 0 || c < 0 || r >= b.length || c >= b[0].length || b[r][c] == '#') return;
        int v = next.get(node)[b[r][c] - 'a'];
        if (v == 0) return;
        if (wordAt.get(v) != null) found.add(wordAt.get(v));
        char saved = b[r][c];
        b[r][c] = '#';
        dfs(b, r + 1, c, v, next, wordAt, found); dfs(b, r - 1, c, v, next, wordAt, found);
        dfs(b, r, c + 1, v, next, wordAt, found); dfs(b, r, c - 1, v, next, wordAt, found);
        b[r][c] = saved;
    }

    // ===================================================================== 20-26: dynamic programming, hashing
    static int lis(int[] a) {                                                      // LC 300
        int[] tails = new int[a.length];
        int len = 0;
        for (int x : a) { int i = Arrays.binarySearch(tails, 0, len, x); if (i < 0) i = -i - 1; tails[i] = x; if (i == len) len++; }
        return len;
    }

    static int editDistance(String a, String b) {                                  // LC 72, two rows
        int[] prev = new int[b.length() + 1], cur = new int[b.length() + 1];
        for (int j = 0; j <= b.length(); j++) prev[j] = j;
        for (int i = 1; i <= a.length(); i++) {
            cur[0] = i;
            for (int j = 1; j <= b.length(); j++) cur[j] = Math.min(Math.min(prev[j], cur[j - 1]) + 1, prev[j - 1] + (a.charAt(i - 1) == b.charAt(j - 1) ? 0 : 1));
            int[] t = prev; prev = cur; cur = t;
        }
        return prev[b.length()];
    }

    static boolean regexMatch(String s, String p) {                                // LC 10: dp[i][j] = s[i..] matches p[j..]
        boolean[][] dp = new boolean[s.length() + 1][p.length() + 1];
        dp[s.length()][p.length()] = true;
        for (int i = s.length(); i >= 0; i--)
            for (int j = p.length() - 1; j >= 0; j--) {
                boolean first = i < s.length() && (p.charAt(j) == '.' || p.charAt(j) == s.charAt(i));
                dp[i][j] = j + 1 < p.length() && p.charAt(j + 1) == '*' ? dp[i][j + 2] || (first && dp[i + 1][j]) : first && dp[i + 1][j + 1];
            }
        return dp[0][0];
    }

    static int burstBalloons(int[] nums) {                                         // LC 312: k = LAST balloon burst in (i, j)
        int n = nums.length + 2;
        int[] v = new int[n];
        v[0] = v[n - 1] = 1;
        System.arraycopy(nums, 0, v, 1, nums.length);
        int[][] dp = new int[n][n];
        for (int len = 2; len < n; len++)
            for (int i = 0; i + len < n; i++) {
                int j = i + len;
                for (int k = i + 1; k < j; k++) dp[i][j] = Math.max(dp[i][j], dp[i][k] + dp[k][j] + v[i] * v[k] * v[j]);
            }
        return dp[0][n - 1];
    }

    static int shortestPathAllNodes(List<List<Integer>> g) {                      // LC 847: BFS over (node, visited mask)
        int n = g.size(), full = (1 << n) - 1;
        int[][] dist = new int[n][1 << n];
        for (int[] row : dist) Arrays.fill(row, -1);
        ArrayDeque<int[]> q = new ArrayDeque<>();
        for (int v = 0; v < n; v++) { dist[v][1 << v] = 0; q.add(new int[] {v, 1 << v}); }
        while (!q.isEmpty()) {
            int[] s = q.poll();
            if (s[1] == full) return dist[s[0]][s[1]];
            for (int u : g.get(s[0])) { int m = s[1] | 1 << u; if (dist[u][m] == -1) { dist[u][m] = dist[s[0]][s[1]] + 1; q.add(new int[] {u, m}); } }
        }
        return -1;
    }

    static long jobScheduling(int[] start, int[] end, int[] profit) {              // LC 1235
        Integer[] idx = new Integer[start.length];
        for (int i = 0; i < idx.length; i++) idx[i] = i;
        Arrays.sort(idx, (x, y) -> Integer.compare(end[x], end[y]));
        long[] dp = new long[idx.length + 1];
        int[] ends = new int[idx.length];
        for (int i = 0; i < idx.length; i++) ends[i] = end[idx[i]];
        for (int i = 1; i <= idx.length; i++) {
            int j = idx[i - 1], lo = 0, hi = i - 1;                                // jobs among the first i-1 ending <= start
            while (lo < hi) { int mid = (lo + hi + 1) >>> 1; if (ends[mid - 1] <= start[j]) lo = mid; else hi = mid - 1; }
            dp[i] = Math.max(dp[i - 1], dp[lo] + profit[j]);
        }
        return dp[idx.length];
    }

    static final long MOD = (1L << 61) - 1;
    static long mulMod(long a, long b) {
        long hi = Math.multiplyHigh(a, b), lo = a * b;
        long r = (lo & MOD) + ((lo >>> 61) | (hi << 3));
        r = (r & MOD) + (r >>> 61);
        return r >= MOD ? r - MOD : r;
    }

    static String longestDupSubstring(String s, long base) {                       // LC 1044: binary search + verified hashes
        int n = s.length();
        long[] pre = new long[n + 1], pw = new long[n + 1];
        pw[0] = 1;
        for (int i = 0; i < n; i++) { pre[i + 1] = (mulMod(pre[i], base) + s.charAt(i)) % MOD; pw[i + 1] = mulMod(pw[i], base); }
        String best = "";
        int lo = 1, hi = n - 1;
        while (lo <= hi) {
            int len = (lo + hi) >>> 1;
            String found = null;
            Map<Long, List<Integer>> seen = new HashMap<>();
            for (int i = 0; i + len <= n && found == null; i++) {
                long h = (pre[i + len] - mulMod(pre[i], pw[len]) + MOD) % MOD;
                List<Integer> starts = seen.computeIfAbsent(h, x -> new ArrayList<>());
                for (int j : starts) if (s.regionMatches(i, s, j, len)) { found = s.substring(i, i + len); break; }  // verify
                starts.add(i);
            }
            if (found != null) { best = found; lo = len + 1; } else hi = len - 1;
        }
        return best;
    }

    // ===================================================================== 29-30: math
    static double medianSorted(int[] a, int[] b) {                                 // LC 4: partition the shorter array
        if (a.length == 0 && b.length == 0) throw new IllegalArgumentException("both arrays empty");
        if (a.length > b.length) return medianSorted(b, a);
        int m = a.length, n = b.length, half = (m + n + 1) / 2, lo = 0, hi = m;
        while (true) {
            int i = (lo + hi) >>> 1, j = half - i;
            int aL = i == 0 ? Integer.MIN_VALUE : a[i - 1], aR = i == m ? Integer.MAX_VALUE : a[i];
            int bL = j == 0 ? Integer.MIN_VALUE : b[j - 1], bR = j == n ? Integer.MAX_VALUE : b[j];
            if (aL <= bR && bL <= aR) {
                int left = Math.max(aL, bL);
                return (m + n) % 2 == 1 ? left : (left + (double) Math.min(aR, bR)) / 2;
            }
            if (aL > bR) hi = i - 1; else lo = i + 1;
        }
    }

    static int maxPoints(int[][] pts) {                                            // LC 149: gcd-normalized directions
        int best = Math.min(pts.length, 1);
        for (int i = 0; i < pts.length; i++) {
            Map<Long, Integer> slopes = new HashMap<>();
            int dup = 0, local = 0;
            for (int j = i + 1; j < pts.length; j++) {
                long dx = (long) pts[j][0] - pts[i][0], dy = (long) pts[j][1] - pts[i][1];
                if (dx == 0 && dy == 0) { dup++; continue; }
                long g = gcd(Math.abs(dx), Math.abs(dy));
                dx /= g; dy /= g;
                if (dx < 0 || (dx == 0 && dy < 0)) { dx = -dx; dy = -dy; }          // one canonical sign per direction
                local = Math.max(local, slopes.merge(dx * 4_000_003L + dy, 1, Integer::sum));
            }
            best = Math.max(best, local + dup + 1);
        }
        return best;
    }

    static long gcd(long a, long b) { while (b != 0) { long t = a % b; a = b; b = t; } return a; }

    // ===================================================================== oracles and random instances
    static int[][] randomEdges(int n, int m) { int[][] e = new int[m][]; for (int i = 0; i < m; i++) { int a = R.nextInt(n), b = R.nextInt(n); if (a == b) b = (b + 1) % n; e[i] = new int[] {a, b}; } return e; }

    static TreeNode randomTree(int n) {
        if (n == 0) return null;
        List<TreeNode> nodes = new ArrayList<>();
        TreeNode root = new TreeNode(R.range(-10, 10));
        nodes.add(root);
        for (int i = 1; i < n; i++) {
            TreeNode c = new TreeNode(R.range(-10, 10));
            while (true) {
                TreeNode p = nodes.get(R.nextInt(nodes.size()));
                if (R.nextInt(2) == 0 && p.left == null) { p.left = c; break; }
                if (p.right == null) { p.right = c; break; }
                if (p.left == null) { p.left = c; break; }
            }
            nodes.add(c);
        }
        return root;
    }

    static int components(int n, int[][] edges, int skip) {
        int[] p = new int[n];
        for (int i = 0; i < n; i++) p[i] = i;
        int c = n;
        for (int e = 0; e < edges.length; e++) if (e != skip) { int a = find(p, edges[e][0]), b = find(p, edges[e][1]); if (a != b) { p[a] = b; c--; } }
        return c;
    }

    static boolean regexBrute(String s, int i, String p, int j) {
        if (j == p.length()) return i == s.length();
        boolean first = i < s.length() && (p.charAt(j) == '.' || p.charAt(j) == s.charAt(i));
        if (j + 1 < p.length() && p.charAt(j + 1) == '*') return regexBrute(s, i, p, j + 2) || (first && regexBrute(s, i + 1, p, j));
        return first && regexBrute(s, i + 1, p, j + 1);
    }

    static int editBrute(String a, String b) {
        if (a.isEmpty()) return b.length();
        if (b.isEmpty()) return a.length();
        if (a.charAt(0) == b.charAt(0)) return editBrute(a.substring(1), b.substring(1));
        return 1 + Math.min(editBrute(a.substring(1), b), Math.min(editBrute(a, b.substring(1)), editBrute(a.substring(1), b.substring(1))));
    }

    static boolean nextPermutation(int[] a) {
        int i = a.length - 2;
        while (i >= 0 && a[i] >= a[i + 1]) i--;
        if (i < 0) return false;
        int j = a.length - 1;
        while (a[j] <= a[i]) j--;
        int t = a[i]; a[i] = a[j]; a[j] = t;
        for (int l = i + 1, r = a.length - 1; l < r; l++, r--) { t = a[l]; a[l] = a[r]; a[r] = t; }
        return true;
    }

    static boolean sortedUnder(String[] words, String order) {
        int[] rank = new int[26];
        for (int i = 0; i < order.length(); i++) rank[order.charAt(i) - 'a'] = i;
        for (int i = 0; i + 1 < words.length; i++) {
            String a = words[i], b = words[i + 1];
            int j = 0;
            while (j < Math.min(a.length(), b.length()) && a.charAt(j) == b.charAt(j)) j++;
            if (j == Math.min(a.length(), b.length())) { if (a.length() > b.length()) return false; continue; }
            if (rank[a.charAt(j) - 'a'] > rank[b.charAt(j) - 'a']) return false;
        }
        return true;
    }

    public static void main(String[] args) {
        int T = 1_000;
        report(1, "LC 146", "LRU cache vs list model", () -> {
            int cap = R.range(1, 4);
            LruCache c = new LruCache(cap);
            List<int[]> model = new ArrayList<>();
            for (int op = 0; op < 30; op++) {
                int k = R.nextInt(6);
                int idx = -1;
                for (int i = 0; i < model.size(); i++) if (model.get(i)[0] == k) idx = i;
                if (R.nextInt(2) == 0) {
                    int want = idx < 0 ? -1 : model.get(idx)[1];
                    if (idx >= 0) model.add(model.remove(idx));
                    if (c.get(k) != want) return 0;
                } else {
                    int v = R.nextInt(100);
                    if (idx >= 0) model.remove(idx);
                    model.add(new int[] {k, v});
                    if (model.size() > cap) model.remove(0);
                    c.put(k, v);
                }
            }
            return 1;
        }, T);
        report(2, "LC 460", "LFU cache vs (freq, last-use) model", () -> {
            int cap = R.range(1, 3);
            LfuCache c = new LfuCache(cap);
            Map<Integer, long[]> model = new HashMap<>();                      // key -> {value, freq, lastUse}
            long tick = 0;
            for (int op = 0; op < 30; op++) {
                int k = R.nextInt(5);
                tick++;
                if (R.nextInt(2) == 0) {
                    long[] e = model.get(k);
                    int want = e == null ? -1 : (int) e[0];
                    if (e != null) { e[1]++; e[2] = tick; }
                    if (c.get(k) != want) return 0;
                } else {
                    int v = R.nextInt(100);
                    long[] e = model.get(k);
                    if (e != null) { e[0] = v; e[1]++; e[2] = tick; }
                    else {
                        if (model.size() == cap) {
                            int victim = -1;
                            for (Map.Entry<Integer, long[]> x : model.entrySet())
                                if (victim == -1 || x.getValue()[1] < model.get(victim)[1] || (x.getValue()[1] == model.get(victim)[1] && x.getValue()[2] < model.get(victim)[2])) victim = x.getKey();
                            model.remove(victim);
                        }
                        model.put(k, new long[] {v, 1, tick});
                    }
                    c.put(k, v);
                }
            }
            return 1;
        }, T);
        report(3, "LC 295", "median of a stream vs sorted list", () -> {
            MedianFinder mf = new MedianFinder();
            List<Integer> all = new ArrayList<>();
            for (int i = R.range(1, 20); i > 0; i--) {
                int x = R.range(-50, 50);
                mf.add(x); all.add(x); Collections.sort(all);
                int n = all.size();
                double want = n % 2 == 1 ? all.get(n / 2) : (all.get(n / 2 - 1) + (double) all.get(n / 2)) / 2;
                if (mf.median() != want) return 0;
            }
            return 1;
        }, T);
        report(4, "LC 239", "sliding window maximum vs brute", () -> {
            int[] a = R.ints(R.range(1, 15), -9, 9);
            int k = R.range(1, a.length);
            int[] got = windowMax(a, k);
            for (int i = 0; i + k <= a.length; i++) if (got[i] != Arrays.stream(a, i, i + k).max().orElseThrow()) return 0;
            return 1;
        }, T);
        report(5, "LC 76", "minimum window substring vs brute", () -> {
            String s = R.word(R.range(0, 12), 3), t = R.word(R.range(1, 3), 3);
            String want = "";
            outer:
            for (int len = 1; len <= s.length(); len++)
                for (int i = 0; i + len <= s.length(); i++) {
                    int[] cnt = new int[128];
                    for (int j = i; j < i + len; j++) cnt[s.charAt(j)]++;
                    boolean ok = true;
                    for (char c : t.toCharArray()) if (--cnt[c] < 0) ok = false;
                    if (ok) { want = s.substring(i, i + len); break outer; }
                }
            return minWindow(s, t).equals(want) ? 1 : 0;
        }, T);
        report(6, "LC 42", "trapping rain water vs per-column brute", () -> {
            int[] h = R.ints(R.range(0, 15), 0, 8);
            long want = 0;
            for (int i = 0; i < h.length; i++) {
                int l = 0, r = 0;
                for (int j = 0; j <= i; j++) l = Math.max(l, h[j]);
                for (int j = i; j < h.length; j++) r = Math.max(r, h[j]);
                want += Math.min(l, r) - h[i];
            }
            return trap(h) == want ? 1 : 0;
        }, T);
        report(7, "LC 84", "largest rectangle in histogram vs O(n^2)", () -> {
            int[] h = R.ints(R.range(0, 12), 0, 9);
            long want = 0;
            for (int i = 0; i < h.length; i++) { long mn = Long.MAX_VALUE; for (int j = i; j < h.length; j++) want = Math.max(want, (mn = Math.min(mn, h[j])) * (j - i + 1)); }
            return largestRectangle(h) == want ? 1 : 0;
        }, T);
        report(8, "LC 23", "merge k sorted lists vs concat + sort", () -> {
            int[][] lists = new int[R.range(0, 6)][];
            List<Integer> all = new ArrayList<>();
            for (int i = 0; i < lists.length; i++) { lists[i] = R.ints(R.range(0, 6), -20, 20); Arrays.sort(lists[i]); for (int x : lists[i]) all.add(x); }
            Collections.sort(all);
            return Arrays.equals(mergeK(lists), all.stream().mapToInt(Integer::intValue).toArray()) ? 1 : 0;
        }, T);
        report(9, "LC 127", "word ladder vs BFS on explicit graph", () -> {
            List<String> words = new ArrayList<>();
            for (int i = R.range(1, 10); i > 0; i--) words.add(R.word(3, 3));
            String begin = R.word(3, 3), end = words.get(R.nextInt(words.size()));
            List<String> nodes = new ArrayList<>(new LinkedHashSet<>(words));
            nodes.add(0, begin);
            int[] dist = new int[nodes.size()];
            Arrays.fill(dist, -1);
            dist[0] = 1;
            ArrayDeque<Integer> q = new ArrayDeque<>(List.of(0));
            int want = 0;
            while (!q.isEmpty()) {
                int u = q.poll();
                if (nodes.get(u).equals(end)) { want = dist[u]; break; }
                for (int v = 1; v < nodes.size(); v++) {
                    int diff = 0;
                    for (int k = 0; k < 3; k++) if (nodes.get(u).charAt(k) != nodes.get(v).charAt(k)) diff++;
                    if (diff == 1 && dist[v] == -1) { dist[v] = dist[u] + 1; q.add(v); }
                }
            }
            return ladderLength(begin, end, words) == want ? 1 : 0;
        }, T);
        report(10, "LC 210", "course order: valid order, or a real cycle", () -> {
            int n = R.range(1, 7);
            int[][] pre = new int[R.nextInt(2 * n)][];
            for (int i = 0; i < pre.length; i++) { int a = R.nextInt(n), b = R.nextInt(n); pre[i] = new int[] {a, b}; }
            int[] order = courseOrder(n, pre);
            boolean[][] reach = new boolean[n][n];
            for (int[] p : pre) reach[p[1]][p[0]] = true;
            for (int k = 0; k < n; k++) for (int i = 0; i < n; i++) for (int j = 0; j < n; j++) reach[i][j] |= reach[i][k] && reach[k][j];
            boolean cyclic = false;
            for (int i = 0; i < n; i++) cyclic |= reach[i][i];
            if (order.length == 0) return cyclic ? 1 : 0;
            int[] at = new int[n];
            for (int i = 0; i < n; i++) at[order[i]] = i;
            for (int[] p : pre) if (at[p[1]] >= at[p[0]]) return 0;
            return cyclic ? 0 : 1;
        }, T);
        report(11, "LC 743", "network delay (Dijkstra) vs Floyd-Warshall", () -> {
            int n = R.range(1, 7);
            int[][] times = new int[R.nextInt(3 * n)][];
            for (int i = 0; i < times.length; i++) times[i] = new int[] {R.range(1, n), R.range(1, n), R.range(0, 9)};
            int src = R.range(1, n);
            long[][] d = new long[n + 1][n + 1];
            for (long[] row : d) Arrays.fill(row, Long.MAX_VALUE / 4);
            for (int i = 1; i <= n; i++) d[i][i] = 0;
            for (int[] t : times) d[t[0]][t[1]] = Math.min(d[t[0]][t[1]], t[2]);
            for (int k = 1; k <= n; k++) for (int i = 1; i <= n; i++) for (int j = 1; j <= n; j++) d[i][j] = Math.min(d[i][j], d[i][k] + d[k][j]);
            long worst = 0;
            for (int i = 1; i <= n; i++) worst = Math.max(worst, d[src][i]);
            int want = worst >= Long.MAX_VALUE / 4 ? -1 : (int) worst;
            return networkDelay(times, n, src) == want ? 1 : 0;
        }, T);
        report(12, "LC 1192", "critical connections vs remove-and-recount", () -> {
            int n = R.range(2, 8);
            int[][] e = randomEdges(n, R.range(1, 2 * n));
            List<List<Integer>> want = new ArrayList<>();
            int base = components(n, e, -1);
            for (int i = 0; i < e.length; i++) if (components(n, e, i) > base) want.add(List.of(Math.min(e[i][0], e[i][1]), Math.max(e[i][0], e[i][1])));
            List<List<Integer>> got = bridges(n, e);
            Comparator<List<Integer>> cmp = Comparator.<List<Integer>>comparingInt(x -> x.get(0)).thenComparingInt(x -> x.get(1));
            want.sort(cmp); got.sort(cmp);
            return got.equals(want) ? 1 : 0;
        }, T);
        report(13, "LC 305", "islands online (DSU) vs BFS recount", () -> {
            int rows = R.range(1, 5), cols = R.range(1, 5);
            int[][] adds = new int[R.range(1, 12)][];
            for (int i = 0; i < adds.length; i++) adds[i] = new int[] {R.nextInt(rows), R.nextInt(cols)};
            int[] got = islandsOnline(rows, cols, adds);
            boolean[][] land = new boolean[rows][cols];
            for (int k = 0; k < adds.length; k++) {
                land[adds[k][0]][adds[k][1]] = true;
                int count = 0;
                boolean[][] seen = new boolean[rows][cols];
                for (int r0 = 0; r0 < rows; r0++) for (int c0 = 0; c0 < cols; c0++) {
                    if (!land[r0][c0] || seen[r0][c0]) continue;
                    count++;
                    ArrayDeque<int[]> q = new ArrayDeque<>(List.of(new int[] {r0, c0}));
                    seen[r0][c0] = true;
                    while (!q.isEmpty()) {
                        int[] p = q.poll();
                        for (int[] d : new int[][] {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
                            int a = p[0] + d[0], b = p[1] + d[1];
                            if (a >= 0 && b >= 0 && a < rows && b < cols && land[a][b] && !seen[a][b]) { seen[a][b] = true; q.add(new int[] {a, b}); }
                        }
                    }
                }
                if (got[k] != count) return 0;
            }
            return 1;
        }, T);
        report(14, "LC 269", "alien dictionary vs brute over letter orders", () -> {
            String[] words = new String[R.range(1, 5)];
            for (int i = 0; i < words.length; i++) words[i] = R.word(R.range(1, 3), 4);
            if (R.nextInt(2) == 0) {                                          // half the time, sort under a hidden order
                int[] perm = {0, 1, 2, 3};
                for (int i = 3; i > 0; i--) { int j = R.nextInt(i + 1), t = perm[i]; perm[i] = perm[j]; perm[j] = t; }
                Arrays.sort(words, (x, y) -> {
                    for (int i = 0; i < Math.min(x.length(), y.length()); i++) if (x.charAt(i) != y.charAt(i)) return Integer.compare(perm[x.charAt(i) - 'a'], perm[y.charAt(i) - 'a']);
                    return Integer.compare(x.length(), y.length());
                });
            }
            String got = alienOrder(words);
            Set<Character> letters = new TreeSet<>();
            for (String w : words) for (char c : w.toCharArray()) letters.add(c);
            int[] perm = {0, 1, 2, 3};
            boolean exists = false;
            do {
                StringBuilder ord = new StringBuilder();
                for (int p : perm) ord.append((char) ('a' + p));
                exists |= sortedUnder(words, ord.toString());
            } while (!exists && nextPermutation(perm));
            if (!exists) return got.isEmpty() ? 1 : 0;
            if (got.length() != letters.size()) return 0;
            StringBuilder full = new StringBuilder(got);
            for (char c = 'a'; c <= 'd'; c++) if (got.indexOf(c) < 0) full.append(c);
            return sortedUnder(words, full.toString()) ? 1 : 0;
        }, T);
        report(15, "LC 297", "serialize/deserialize round trip", () -> {
            TreeNode t = randomTree(R.range(0, 25));
            return sameTree(t, deserialize(serialize(t))) ? 1 : 0;
        }, T);
        TreeNode chain = new TreeNode(0), cur = chain;
        for (int i = 1; i < 100_000; i++) { cur.right = new TreeNode(i % 7); cur = cur.right; }
        boolean deepOk = sameTree(chain, deserialize(serialize(chain)));
        report(16, "LC 124", "max path sum vs all node pairs", () -> {
            TreeNode t = randomTree(R.range(1, 12));
            List<TreeNode> nodes = new ArrayList<>();
            Map<TreeNode, TreeNode> parent = new HashMap<>();
            ArrayDeque<TreeNode> st = new ArrayDeque<>(List.of(t));
            while (!st.isEmpty()) { TreeNode n = st.pop(); nodes.add(n); for (TreeNode c : new TreeNode[] {n.left, n.right}) if (c != null) { parent.put(c, n); st.push(c); } }
            long want = Long.MIN_VALUE;
            for (TreeNode u : nodes) for (TreeNode v : nodes) {
                Set<TreeNode> up = new HashSet<>();
                for (TreeNode x = u; x != null; x = parent.get(x)) up.add(x);
                TreeNode lca = v;
                while (!up.contains(lca)) lca = parent.get(lca);
                long s = lca.val;
                for (TreeNode x = u; x != lca; x = parent.get(x)) s += x.val;
                for (TreeNode x = v; x != lca; x = parent.get(x)) s += x.val;
                want = Math.max(want, s);
            }
            return maxPathSum(t) == want ? 1 : 0;
        }, T);
        report(17, "LC 315", "count smaller after self vs O(n^2)", () -> {
            int[] a = R.ints(R.range(0, 15), -5, 5);
            int[] got = countSmallerAfter(a);
            for (int i = 0; i < a.length; i++) { int c = 0; for (int j = i + 1; j < a.length; j++) if (a[j] < a[i]) c++; if (got[i] != c) return 0; }
            return 1;
        }, T);
        report(18, "LC 732", "calendar max overlap vs per-point count", () -> {
            MyCalendarThree cal = new MyCalendarThree();
            int[] cover = new int[30];
            for (int b = R.range(1, 8); b > 0; b--) {
                int s = R.nextInt(25), e = s + R.range(1, 5);
                for (int x = s; x < e; x++) cover[x]++;
                if (cal.book(s, e) != Arrays.stream(cover).max().orElse(0)) return 0;
            }
            return 1;
        }, T);
        report(19, "LC 212", "word search II (trie) vs per-word search", () -> {
            int rows = R.range(1, 3), cols = R.range(1, 3);
            char[][] board = new char[rows][cols];
            for (char[] row : board) for (int c = 0; c < cols; c++) row[c] = (char) ('a' + R.nextInt(3));
            String[] words = new String[R.range(1, 6)];
            for (int i = 0; i < words.length; i++) words[i] = R.word(R.range(1, 4), 3);
            List<String> got = findWords(board, words);
            Set<String> want = new TreeSet<>();
            for (String w : words) {
                for (int r0 = 0; r0 < rows; r0++) for (int c0 = 0; c0 < cols; c0++) if (exists(board, w, 0, r0, c0, new boolean[rows][cols])) want.add(w);
            }
            return got.equals(new ArrayList<>(want)) ? 1 : 0;
        }, T);
        report(20, "LC 300", "LIS length vs O(n^2)", () -> {
            int[] a = R.ints(R.range(0, 15), 0, 9);
            int[] d = new int[a.length];
            int want = 0;
            for (int i = 0; i < a.length; i++) { d[i] = 1; for (int j = 0; j < i; j++) if (a[j] < a[i]) d[i] = Math.max(d[i], d[j] + 1); want = Math.max(want, d[i]); }
            return lis(a) == want ? 1 : 0;
        }, T);
        report(21, "LC 72", "edit distance vs exponential recursion", () -> {
            String a = R.word(R.range(0, 6), 3), b = R.word(R.range(0, 6), 3);
            return editDistance(a, b) == editBrute(a, b) ? 1 : 0;
        }, T);
        report(22, "LC 10", "regex . and * (DP) vs backtracking", () -> {
            String s = R.word(R.range(0, 6), 2);
            StringBuilder p = new StringBuilder();
            for (int i = R.range(0, 4); i > 0; i--) { p.append(R.nextInt(4) == 0 ? '.' : (char) ('a' + R.nextInt(2))); if (R.nextInt(2) == 0) p.append('*'); }
            return regexMatch(s, p.toString()) == regexBrute(s, 0, p.toString(), 0) ? 1 : 0;
        }, T);
        report(23, "LC 312", "burst balloons vs every burst order", () -> {
            int[] nums = R.ints(R.range(1, 6), 0, 6);
            int[] perm = new int[nums.length];
            for (int i = 0; i < perm.length; i++) perm[i] = i;
            int want = 0;
            do {
                boolean[] gone = new boolean[nums.length];
                int coins = 0;
                for (int idx : perm) {
                    int l = idx - 1, r = idx + 1;
                    while (l >= 0 && gone[l]) l--;
                    while (r < nums.length && gone[r]) r++;
                    coins += (l < 0 ? 1 : nums[l]) * nums[idx] * (r >= nums.length ? 1 : nums[r]);
                    gone[idx] = true;
                }
                want = Math.max(want, coins);
            } while (nextPermutation(perm));
            return burstBalloons(nums) == want ? 1 : 0;
        }, T);
        report(24, "LC 847", "shortest walk visiting all nodes vs brute", () -> {
            int n = R.range(1, 6);
            List<List<Integer>> g = new ArrayList<>();
            for (int i = 0; i < n; i++) g.add(new ArrayList<>());
            int[][] d = new int[n][n];
            for (int[] row : d) Arrays.fill(row, 1_000);
            for (int i = 0; i < n; i++) d[i][i] = 0;
            for (int v = 1; v < n; v++) { int u = R.nextInt(v); g.get(u).add(v); g.get(v).add(u); d[u][v] = d[v][u] = 1; }  // connected
            for (int extra = R.nextInt(n); extra > 0; extra--) { int u = R.nextInt(n), v = R.nextInt(n); if (u != v && d[u][v] != 1) { g.get(u).add(v); g.get(v).add(u); d[u][v] = d[v][u] = 1; } }
            for (int k = 0; k < n; k++) for (int i = 0; i < n; i++) for (int j = 0; j < n; j++) d[i][j] = Math.min(d[i][j], d[i][k] + d[k][j]);
            int[] perm = new int[n];
            for (int i = 0; i < n; i++) perm[i] = i;
            int want = Integer.MAX_VALUE;
            do { int s = 0; for (int i = 0; i + 1 < n; i++) s += d[perm[i]][perm[i + 1]]; want = Math.min(want, s); } while (nextPermutation(perm));
            return shortestPathAllNodes(g) == want ? 1 : 0;
        }, T);
        report(25, "LC 1235", "weighted job scheduling vs all subsets", () -> {
            int n = R.range(1, 9);
            int[] s = new int[n], e = new int[n], p = new int[n];
            for (int i = 0; i < n; i++) { s[i] = R.nextInt(10); e[i] = s[i] + R.range(1, 5); p[i] = R.range(1, 20); }
            long want = 0;
            for (int mask = 0; mask < 1 << n; mask++) {
                boolean ok = true;
                long sum = 0;
                for (int i = 0; i < n && ok; i++) if ((mask >> i & 1) == 1) { sum += p[i]; for (int j = i + 1; j < n; j++) if ((mask >> j & 1) == 1 && s[i] < e[j] && s[j] < e[i]) ok = false; }
                if (ok) want = Math.max(want, sum);
            }
            return jobScheduling(s, e, p) == want ? 1 : 0;
        }, T);
        long base = (R.next() >>> 4) % (MOD - 256) + 256;
        report(26, "LC 1044", "longest duplicate substring vs brute", () -> {
            String s = R.word(R.range(2, 18), 2);
            int want = 0;
            for (int len = 1; len < s.length(); len++)
                for (int i = 0; i + len <= s.length(); i++) if (s.indexOf(s.substring(i, i + len), i + 1) >= 0) want = Math.max(want, len);
            String got = longestDupSubstring(s, base);
            boolean twice = got.isEmpty() || s.indexOf(got) != s.lastIndexOf(got);
            return got.length() == want && twice ? 1 : 0;
        }, T);
        report(27, "LC 362", "hit counter (300 s ring) vs timestamp list", () -> {
            HitCounter hc = new HitCounter();
            List<Integer> hits = new ArrayList<>();
            int t = R.range(1, 50);
            for (int op = 0; op < 40; op++) {
                t += R.nextInt(120);
                if (R.nextInt(2) == 0) { hc.hit(t); hits.add(t); }
                else { final int now = t; if (hc.hits(t) != hits.stream().filter(x -> now - x < 300).count()) return 0; }
            }
            return 1;
        }, T);
        report(28, "LC 981", "time-based key-value store vs linear scan", () -> {
            TimeMap tm = new TimeMap();
            List<Object[]> log = new ArrayList<>();
            int ts = 0;
            for (int op = 0; op < 30; op++) {
                String k = "k" + R.nextInt(3);
                if (R.nextInt(2) == 0) { ts += R.range(1, 3); String v = "v" + R.nextInt(100); tm.set(k, v, ts); log.add(new Object[] {k, v, ts}); }
                else {
                    int q = R.nextInt(ts + 2);
                    String want = "";
                    int bestTs = -1;
                    for (Object[] e : log) if (e[0].equals(k) && (int) e[2] <= q && (int) e[2] > bestTs) { bestTs = (int) e[2]; want = (String) e[1]; }
                    if (!tm.get(k, q).equals(want)) return 0;
                }
            }
            return 1;
        }, T);
        report(29, "LC 4", "median of two sorted arrays vs merge", () -> {
            int[] a = R.ints(R.range(0, 6), -20, 20), b = R.ints(R.range(a.length == 0 ? 1 : 0, 6), -20, 20);
            Arrays.sort(a); Arrays.sort(b);
            int[] all = new int[a.length + b.length];
            System.arraycopy(a, 0, all, 0, a.length); System.arraycopy(b, 0, all, a.length, b.length);
            Arrays.sort(all);
            int n = all.length;
            double want = n % 2 == 1 ? all[n / 2] : (all[n / 2 - 1] + (double) all[n / 2]) / 2;
            return medianSorted(a, b) == want ? 1 : 0;
        }, T);
        report(30, "LC 149", "max points on a line vs cross-product brute", () -> {
            int[][] pts = new int[R.range(1, 8)][];
            for (int i = 0; i < pts.length; i++) pts[i] = new int[] {R.range(-4, 4), R.range(-4, 4)};
            int want = 1;
            for (int i = 0; i < pts.length; i++) for (int j = i + 1; j < pts.length; j++) {
                int c = 0;
                boolean same = pts[i][0] == pts[j][0] && pts[i][1] == pts[j][1];
                for (int[] q : pts) {
                    long cross = (long) (pts[j][0] - pts[i][0]) * (q[1] - pts[i][1]) - (long) (pts[j][1] - pts[i][1]) * (q[0] - pts[i][0]);
                    if (same ? q[0] == pts[i][0] && q[1] == pts[i][1] : cross == 0) c++;
                }
                want = Math.max(want, c);
            }
            return maxPoints(pts) == want ? 1 : 0;
        }, T);
        System.out.printf("serialize/deserialize of a 100,000-node chain without recursion: %b | problems with any failing trial: %d of 30%n",
                deepOk, failures);
    }

    static boolean exists(char[][] b, String w, int k, int r, int c, boolean[][] used) {  // per-word DFS oracle (depth <= |w|)
        if (r < 0 || c < 0 || r >= b.length || c >= b[0].length || used[r][c] || b[r][c] != w.charAt(k)) return false;
        if (k == w.length() - 1) return true;
        used[r][c] = true;
        boolean ok = exists(b, w, k + 1, r + 1, c, used) || exists(b, w, k + 1, r - 1, c, used) || exists(b, w, k + 1, r, c + 1, used) || exists(b, w, k + 1, r, c - 1, used);
        used[r][c] = false;
        return ok;
    }
}
```

**Output (verified):**

```text
 1. LC 146   LRU cache vs list model                         1000/1000
 2. LC 460   LFU cache vs (freq, last-use) model             1000/1000
 3. LC 295   median of a stream vs sorted list               1000/1000
 4. LC 239   sliding window maximum vs brute                 1000/1000
 5. LC 76    minimum window substring vs brute               1000/1000
 6. LC 42    trapping rain water vs per-column brute         1000/1000
 7. LC 84    largest rectangle in histogram vs O(n^2)        1000/1000
 8. LC 23    merge k sorted lists vs concat + sort           1000/1000
 9. LC 127   word ladder vs BFS on explicit graph            1000/1000
10. LC 210   course order: valid order, or a real cycle      1000/1000
11. LC 743   network delay (Dijkstra) vs Floyd-Warshall      1000/1000
12. LC 1192  critical connections vs remove-and-recount      1000/1000
13. LC 305   islands online (DSU) vs BFS recount             1000/1000
14. LC 269   alien dictionary vs brute over letter orders    1000/1000
15. LC 297   serialize/deserialize round trip                1000/1000
16. LC 124   max path sum vs all node pairs                  1000/1000
17. LC 315   count smaller after self vs O(n^2)              1000/1000
18. LC 732   calendar max overlap vs per-point count         1000/1000
19. LC 212   word search II (trie) vs per-word search        1000/1000
20. LC 300   LIS length vs O(n^2)                            1000/1000
21. LC 72    edit distance vs exponential recursion          1000/1000
22. LC 10    regex . and * (DP) vs backtracking              1000/1000
23. LC 312   burst balloons vs every burst order             1000/1000
24. LC 847   shortest walk visiting all nodes vs brute       1000/1000
25. LC 1235  weighted job scheduling vs all subsets          1000/1000
26. LC 1044  longest duplicate substring vs brute            1000/1000
27. LC 362   hit counter (300 s ring) vs timestamp list      1000/1000
28. LC 981   time-based key-value store vs linear scan       1000/1000
29. LC 4     median of two sorted arrays vs merge            1000/1000
30. LC 149   max points on a line vs cross-product brute     1000/1000
serialize/deserialize of a 100,000-node chain without recursion: true | problems with any failing trial: 0 of 30
```

### 3.2 Listing 7.6 — C++23

The same structure: free functions and small classes, then oracles, then `main` with one lambda per problem. Notable C++-only choices: the tree arena (`Tree` owns a `std::deque<Node>`, so destroying a 100,000-node chain is a loop, not a recursion); `std::span` for the oracles' sub-ranges; C++23 deducing `this` for the recursive trie DFS lambda; `std::from_chars` with error checking in the deserializer; `std::println` for output.

```cpp
// l7_problems.cpp - 30 hard interview problems, production-style, each checked against a brute-force oracle or model.
#include <algorithm>
#include <array>
#include <charconv>
#include <cstdint>
#include <deque>
#include <functional>
#include <limits>
#include <list>
#include <map>
#include <numeric>
#include <print>
#include <queue>
#include <set>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <system_error>
#include <tuple>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

using i64 = std::int64_t;
using u64 = std::uint64_t;
using Vec = std::vector<int>;
using Pairs = std::vector<std::array<int, 2>>;
inline std::size_t U(int x) { return static_cast<std::size_t>(x); }
template <class C> int isize(const C& c) { return static_cast<int>(std::size(c)); }

struct SplitMix64 {
    u64 state;
    u64 next() noexcept {
        u64 z = (state += 0x9E3779B97F4A7C15ULL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }
    int next_int(int bound) noexcept { return static_cast<int>(next() % static_cast<u64>(bound)); }
    int range(int lo, int hi) noexcept { return lo + next_int(hi - lo + 1); }
    Vec ints(int n, int lo, int hi) { Vec a(U(n)); for (int& x : a) x = range(lo, hi); return a; }
    std::string word(int n, int alphabet) { std::string s; for (int i = 0; i < n; ++i) s += static_cast<char>('a' + next_int(alphabet)); return s; }
};

SplitMix64 R{181};
int failures = 0;

template <class F> void report(int id, const char* lc, const char* name, F one_trial_passes, int trials) {
    int ok = 0;
    for (int t = 0; t < trials; ++t) ok += one_trial_passes() ? 1 : 0;
    if (ok != trials) ++failures;
    std::println("{:2}. {:<8} {:<46} {:5}/{}", id, lc, name, ok, trials);
}

// ===================================================================== 1-3, 27-28: designs (checked against models)
/** LC 146. O(1) get/put: a recency list (front = most recent) plus a hash map from key to list position. */
class LruCache {
public:
    explicit LruCache(int capacity) : capacity_(capacity) { if (capacity <= 0) throw std::invalid_argument("capacity"); }
    int get(int key) {
        auto it = pos_.find(key);
        if (it == pos_.end()) return -1;
        order_.splice(order_.begin(), order_, it->second);                      // O(1); iterators stay valid
        return it->second->second;
    }
    void put(int key, int value) {
        if (auto it = pos_.find(key); it != pos_.end()) { it->second->second = value; order_.splice(order_.begin(), order_, it->second); return; }
        order_.emplace_front(key, value);
        pos_[key] = order_.begin();
        if (isize(order_) > capacity_) { pos_.erase(order_.back().first); order_.pop_back(); }
    }

private:
    int capacity_;
    std::list<std::pair<int, int>> order_;
    std::unordered_map<int, std::list<std::pair<int, int>>::iterator> pos_;
};

/** LC 460. O(1): key -> (value, freq, position in its bucket), freq -> keys in recency order, and the minimum frequency. */
class LfuCache {
public:
    explicit LfuCache(int capacity) : capacity_(capacity) {}
    int get(int key) {
        auto it = entries_.find(key);
        if (it == entries_.end()) return -1;
        touch(it->second);
        return it->second.value;
    }
    void put(int key, int value) {
        if (capacity_ == 0) return;
        if (auto it = entries_.find(key); it != entries_.end()) { it->second.value = value; touch(it->second); return; }
        if (isize(entries_) == capacity_) {
            auto& victims = by_freq_[min_freq_];
            entries_.erase(victims.front());
            victims.pop_front();
            if (victims.empty()) by_freq_.erase(min_freq_);
        }
        auto& bucket = by_freq_[1];
        bucket.push_back(key);
        entries_.emplace(key, Entry{value, 1, std::prev(bucket.end())});
        min_freq_ = 1;
    }

private:
    struct Entry { int value; int freq; std::list<int>::iterator where; };
    void touch(Entry& e) {
        auto& from = by_freq_[e.freq];
        auto& to = by_freq_[e.freq + 1];                                         // references survive a rehash
        to.splice(to.end(), from, e.where);                                      // O(1) move between buckets
        if (from.empty()) { by_freq_.erase(e.freq); if (min_freq_ == e.freq) ++min_freq_; }
        ++e.freq;
    }
    int capacity_, min_freq_ = 0;
    std::unordered_map<int, Entry> entries_;
    std::unordered_map<int, std::list<int>> by_freq_;
};

/** LC 295. Max-heap of the lower half, min-heap of the upper half, sizes differ by at most one. */
class MedianFinder {
public:
    void add(int x) {
        low_.push(x);
        high_.push(low_.top());
        low_.pop();
        if (high_.size() > low_.size()) { low_.push(high_.top()); high_.pop(); }
    }
    double median() const { return low_.size() > high_.size() ? low_.top() : (low_.top() + static_cast<double>(high_.top())) / 2; }

private:
    std::priority_queue<int> low_;
    std::priority_queue<int, Vec, std::greater<>> high_;
};

/** LC 362. Hits in the last 300 s: a ring of 300 (second, count) buckets. O(1) memory per second of window. */
class HitCounter {
public:
    void hit(int t) { auto i = U(t % 300); if (times_[i] != t) { times_[i] = t; counts_[i] = 0; } ++counts_[i]; }
    int hits(int t) const {
        int s = 0;
        for (std::size_t i = 0; i < 300; ++i) if (t - times_[i] < 300 && times_[i] <= t && counts_[i] > 0) s += counts_[i];
        return s;
    }

private:
    std::array<int, 300> times_{}, counts_{};
};

/** LC 981. Per key, a sorted map from timestamp to value; get = floor lookup. O(log n). */
class TimeMap {
public:
    void set(const std::string& k, std::string v, int ts) { data_[k].insert_or_assign(ts, std::move(v)); }
    std::string get(const std::string& k, int ts) const {
        auto m = data_.find(k);
        if (m == data_.end()) return "";
        auto it = m->second.upper_bound(ts);                                     // first timestamp > ts; its predecessor is the floor
        return it == m->second.begin() ? "" : std::prev(it)->second;
    }

private:
    std::unordered_map<std::string, std::map<int, std::string>> data_;
};

// ===================================================================== 4-8: arrays, windows, stacks, heaps
Vec window_max(const Vec& a, std::size_t k) {                                   // LC 239
    if (k == 0 || k > a.size()) throw std::invalid_argument("k out of range");
    Vec out;
    std::deque<std::size_t> dq;                                                  // indices; values decrease front to back
    for (std::size_t i = 0; i < a.size(); ++i) {
        while (!dq.empty() && a[dq.back()] <= a[i]) dq.pop_back();
        dq.push_back(i);
        if (dq.front() + k <= i) dq.pop_front();
        if (i + 1 >= k) out.push_back(a[dq.front()]);
    }
    return out;
}

std::string min_window(std::string_view s, std::string_view t) {                // LC 76, any byte
    std::array<int, 256> need{};
    for (char c : t) ++need[static_cast<unsigned char>(c)];
    int missing = isize(t);
    std::size_t best_l = 0, best_len = std::string_view::npos;
    for (std::size_t l = 0, r = 0; r < s.size(); ++r) {
        if (need[static_cast<unsigned char>(s[r])]-- > 0) --missing;
        while (missing == 0) {
            if (r - l + 1 < best_len) { best_len = r - l + 1; best_l = l; }
            if (++need[static_cast<unsigned char>(s[l++])] > 0) ++missing;
        }
    }
    return best_len == std::string_view::npos ? "" : std::string(s.substr(best_l, best_len));
}

i64 trap(const Vec& h) {                                                        // LC 42
    if (h.empty()) return 0;                                                     // h.size() - 1 would wrap
    std::size_t l = 0, r = h.size() - 1;
    int lm = 0, rm = 0;
    i64 water = 0;
    while (l < r) {
        if (h[l] < h[r]) { lm = std::max(lm, h[l]); water += lm - h[l++]; }     // the lower side is the binding wall
        else { rm = std::max(rm, h[r]); water += rm - h[r--]; }
    }
    return water;
}

i64 largest_rectangle(const Vec& h) {                                           // LC 84
    std::vector<std::size_t> st;
    i64 best = 0;
    for (std::size_t i = 0; i <= h.size(); ++i) {
        int cur = i == h.size() ? 0 : h[i];
        while (!st.empty() && h[st.back()] >= cur) {
            i64 height = h[st.back()];
            st.pop_back();
            auto width = static_cast<i64>(st.empty() ? i : i - st.back() - 1);
            best = std::max(best, height * width);
        }
        st.push_back(i);
    }
    return best;
}

Vec merge_k(const std::vector<Vec>& lists) {                                    // LC 23
    using Item = std::pair<int, std::size_t>;                                   // (value, list): ties by list index
    std::priority_queue<Item, std::vector<Item>, std::greater<>> pq;
    std::vector<std::size_t> pos(lists.size());
    std::size_t total = 0;
    for (std::size_t i = 0; i < lists.size(); ++i) { total += lists[i].size(); if (!lists[i].empty()) pq.emplace(lists[i][0], i); }
    Vec out;
    out.reserve(total);
    while (!pq.empty()) {
        auto [v, i] = pq.top();
        pq.pop();
        out.push_back(v);
        if (++pos[i] < lists[i].size()) pq.emplace(lists[i][pos[i]], i);
    }
    return out;
}

// ===================================================================== 9-14: graphs
int ladder_length(const std::string& begin, const std::string& end, const std::vector<std::string>& words) {  // LC 127
    std::unordered_set<std::string> dict(words.begin(), words.end());
    if (!dict.contains(end)) return 0;
    std::unordered_map<std::string, std::vector<std::string>> buckets;          // "h*t" -> words: no O(n^2) adjacency
    for (const auto& w : dict)
        for (std::size_t i = 0; i < w.size(); ++i) { std::string key = w; key[i] = '*'; buckets[key].push_back(w); }
    std::unordered_map<std::string, int> dist{{begin, 1}};
    std::deque<std::string> q{begin};
    while (!q.empty()) {
        std::string u = std::move(q.front());
        q.pop_front();
        if (u == end) return dist[u];
        for (std::size_t i = 0; i < u.size(); ++i) {
            std::string key = u;
            key[i] = '*';
            auto it = buckets.find(key);
            if (it == buckets.end()) continue;
            for (const auto& v : it->second) if (!dist.contains(v)) { dist[v] = dist[u] + 1; q.push_back(v); }
        }
    }
    return 0;
}

Vec course_order(int n, const Pairs& prereq) {                                  // LC 210: empty = cycle
    std::vector<Vec> adj(U(n));
    Vec indeg(U(n)), order;
    for (auto [course, before] : prereq) { adj[U(before)].push_back(course); ++indeg[U(course)]; }
    std::deque<int> q;
    for (int i = 0; i < n; ++i) if (indeg[U(i)] == 0) q.push_back(i);
    while (!q.empty()) {
        int u = q.front();
        q.pop_front();
        order.push_back(u);
        for (int v : adj[U(u)]) if (--indeg[U(v)] == 0) q.push_back(v);
    }
    return isize(order) == n ? order : Vec{};
}

int network_delay(const std::vector<std::array<int, 3>>& times, int n, int src) {  // LC 743, nodes 1..n
    std::vector<std::vector<std::pair<int, int>>> adj(U(n + 1));
    for (auto [u, v, w] : times) adj[U(u)].emplace_back(v, w);
    constexpr i64 INF = std::numeric_limits<i64>::max();
    std::vector<i64> dist(U(n + 1), INF);
    dist[U(src)] = 0;
    using Item = std::pair<i64, int>;
    std::priority_queue<Item, std::vector<Item>, std::greater<>> pq;
    pq.emplace(0, src);
    while (!pq.empty()) {
        auto [d, u] = pq.top();
        pq.pop();
        if (d > dist[U(u)]) continue;                                           // stale entry
        for (auto [v, w] : adj[U(u)]) if (d + w < dist[U(v)]) { dist[U(v)] = d + w; pq.emplace(dist[U(v)], v); }
    }
    i64 worst = *std::max_element(dist.begin() + 1, dist.end());
    return worst == INF ? -1 : static_cast<int>(worst);
}

Pairs bridges(int n, const Pairs& edges) {                                      // LC 1192, iterative low-link
    std::vector<std::vector<std::pair<int, int>>> adj(U(n));                    // (neighbour, edge id)
    for (int e = 0; e < isize(edges); ++e) { auto [a, b] = edges[U(e)]; adj[U(a)].emplace_back(b, e); adj[U(b)].emplace_back(a, e); }
    Vec tin(U(n), -1), low(U(n)), via(U(n), -1), it(U(n));
    Pairs out;
    int timer = 0;
    for (int s = 0; s < n; ++s) {
        if (tin[U(s)] != -1) continue;
        Vec st{s};
        tin[U(s)] = low[U(s)] = timer++;
        while (!st.empty()) {
            int u = st.back();
            if (it[U(u)] < isize(adj[U(u)])) {
                auto [v, e] = adj[U(u)][U(it[U(u)]++)];
                if (e == via[U(u)]) continue;                                   // skip the arriving EDGE, not the parent vertex
                if (tin[U(v)] == -1) { tin[U(v)] = low[U(v)] = timer++; via[U(v)] = e; st.push_back(v); }
                else low[U(u)] = std::min(low[U(u)], tin[U(v)]);
                continue;
            }
            st.pop_back();
            if (via[U(u)] >= 0) {
                auto [a, b] = edges[U(via[U(u)])];
                int p = a == u ? b : a;
                low[U(p)] = std::min(low[U(p)], low[U(u)]);
                if (low[U(u)] > tin[U(p)]) out.push_back({std::min(p, u), std::max(p, u)});
            }
        }
    }
    return out;
}

int find_root(Vec& p, int x) { while (p[U(x)] != x) { p[U(x)] = p[U(p[U(x)])]; x = p[U(x)]; } return x; }

constexpr std::array<std::array<int, 2>, 4> DIRS{{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}};

Vec islands_online(int rows, int cols, const Pairs& adds) {                     // LC 305
    Vec parent(U(rows * cols), -1), out;                                         // -1 = water
    int count = 0;
    for (auto [r, c] : adds) {
        int cell = r * cols + c;
        if (parent[U(cell)] == -1) {
            parent[U(cell)] = cell;
            ++count;
            for (auto [dr, dc] : DIRS) {
                int r2 = r + dr, c2 = c + dc;
                if (r2 < 0 || c2 < 0 || r2 >= rows || c2 >= cols || parent[U(r2 * cols + c2)] == -1) continue;
                int a = find_root(parent, cell), b = find_root(parent, r2 * cols + c2);
                if (a != b) { parent[U(a)] = b; --count; }
            }
        }
        out.push_back(count);
    }
    return out;
}

std::string alien_order(const std::vector<std::string>& words) {               // LC 269
    std::map<char, std::set<char>> adj;
    for (const auto& w : words) for (char c : w) adj.try_emplace(c);
    for (std::size_t i = 0; i + 1 < words.size(); ++i) {
        const auto& a = words[i];
        const auto& b = words[i + 1];
        auto [ia, ib] = std::ranges::mismatch(a, b);
        if (ia == a.end() || ib == b.end()) { if (a.size() > b.size()) return ""; continue; }  // "abc" before "ab": invalid
        adj[*ia].insert(*ib);
    }
    std::map<char, int> indeg;
    for (const auto& [c, outs] : adj) { indeg.try_emplace(c, 0); for (char v : outs) ++indeg[v]; }
    std::priority_queue<char, std::vector<char>, std::greater<>> q;
    for (auto [c, d] : indeg) if (d == 0) q.push(c);
    std::string order;
    while (!q.empty()) {
        char c = q.top();
        q.pop();
        order += c;
        for (char v : adj[c]) if (--indeg[v] == 0) q.push(v);
    }
    return order.size() == adj.size() ? order : "";
}

// ===================================================================== 15-16: trees (iterative, arena-owned)
struct Node {
    int val;
    Node* left = nullptr;
    Node* right = nullptr;
};

/** Owns every node in a deque: destruction is a loop, so a 100,000-node chain cannot overflow the stack the way
    a recursive unique_ptr<Node> tree does when it is destroyed. */
struct Tree {
    std::deque<Node> pool;
    Node* root = nullptr;
    Tree() = default;
    Tree(Tree&&) = default;
    Tree(const Tree&) = delete;
    Node* make(int v) { return &pool.emplace_back(Node{v}); }
};

std::string serialize(const Node* root) {                                       // LC 297: preorder with '#', no recursion
    std::string out;
    std::vector<const Node*> work{root};
    while (!work.empty()) {
        const Node* n = work.back();
        work.pop_back();
        if (!out.empty()) out += ',';
        if (n == nullptr) { out += '#'; continue; }
        out += std::to_string(n->val);
        work.push_back(n->right);
        work.push_back(n->left);
    }
    return out;
}

Tree deserialize(std::string_view data) {
    Tree t;
    std::vector<std::pair<Node*, bool>> waiting;                                // (node, its left is already set)
    bool first = true;
    for (std::size_t pos = 0; pos <= data.size();) {
        std::size_t comma = std::min(data.find(',', pos), data.size());
        std::string_view tok = data.substr(pos, comma - pos);
        pos = comma + 1;
        Node* child = nullptr;
        if (tok != "#") {
            int v = 0;
            auto [p, ec] = std::from_chars(tok.data(), tok.data() + tok.size(), v);
            if (ec != std::errc{} || p != tok.data() + tok.size()) throw std::invalid_argument("bad token");
            child = t.make(v);
        }
        if (first) { first = false; t.root = child; if (child) waiting.emplace_back(child, false); continue; }
        if (waiting.empty()) throw std::invalid_argument("extra tokens after a complete tree");
        auto& [parent, left_done] = waiting.back();
        if (!left_done) { parent->left = child; left_done = true; }
        else { parent->right = child; waiting.pop_back(); }
        if (child) waiting.emplace_back(child, false);
    }
    return t;
}

bool same_tree(const Node* a, const Node* b) {
    std::vector<std::pair<const Node*, const Node*>> st;
    st.emplace_back(a, b);
    while (!st.empty()) {
        auto [x, y] = st.back();
        st.pop_back();
        if (!x || !y) { if (x != y) return false; continue; }
        if (x->val != y->val) return false;
        st.emplace_back(x->left, y->left);
        st.emplace_back(x->right, y->right);
    }
    return true;
}

i64 max_path_sum(const Node* root) {                                            // LC 124: post-order gains, iterative
    std::vector<const Node*> order, st{root};
    while (!st.empty()) {
        const Node* n = st.back();
        st.pop_back();
        order.push_back(n);
        if (n->left) st.push_back(n->left);
        if (n->right) st.push_back(n->right);
    }
    std::unordered_map<const Node*, i64> gain;
    i64 best = std::numeric_limits<i64>::min();
    for (auto it = order.rbegin(); it != order.rend(); ++it) {                   // children before parents
        const Node* n = *it;
        i64 l = n->left ? std::max<i64>(0, gain[n->left]) : 0, r = n->right ? std::max<i64>(0, gain[n->right]) : 0;
        best = std::max(best, n->val + l + r);
        gain[n] = n->val + std::max(l, r);
    }
    return best;
}

// ===================================================================== 17-19: range structures, tries
constexpr std::size_t lowbit(std::size_t j) { return j & (~j + 1); }

Vec count_smaller_after(const Vec& a) {                                        // LC 315: Fenwick over compressed values
    Vec sorted = a;
    std::ranges::sort(sorted);
    sorted.erase(std::unique(sorted.begin(), sorted.end()), sorted.end());
    Vec fw(sorted.size() + 1), out(a.size());
    for (std::size_t i = a.size(); i-- > 0;) {
        auto rank = static_cast<std::size_t>(std::ranges::lower_bound(sorted, a[i]) - sorted.begin());
        int s = 0;
        for (std::size_t j = rank; j > 0; j -= lowbit(j)) s += fw[j];            // count of ranks < rank
        out[i] = s;
        for (std::size_t j = rank + 1; j < fw.size(); j += lowbit(j)) ++fw[j];
    }
    return out;
}

class MyCalendarThree {                                                         // LC 732: sweep over a sorted delta map
public:
    int book(int start, int end) {
        ++delta_[start];
        --delta_[end];
        int cur = 0, best = 0;
        for (const auto& kv : delta_) best = std::max(best, cur += kv.second);
        return best;
    }

private:
    std::map<int, int> delta_;
};

std::vector<std::string> find_words(std::vector<std::string> board, const std::vector<std::string>& words) {  // LC 212
    std::vector<std::array<int, 26>> next(1);                                   // trie; node 0 = root, 0 = no child
    Vec word_at(1, -1);
    for (int w = 0; w < isize(words); ++w) {
        std::size_t v = 0;
        for (char c : words[U(w)]) {
            auto ch = static_cast<std::size_t>(c - 'a');
            if (next[v][ch] == 0) { next[v][ch] = isize(next); next.push_back({}); word_at.push_back(-1); }
            v = U(next[v][ch]);
        }
        word_at[v] = w;
    }
    std::set<std::string> found;
    const int rows = isize(board), cols = isize(board[0]);
    auto dfs = [&](this const auto& self, int r, int c, std::size_t node) -> void {   // depth <= longest word
        if (r < 0 || c < 0 || r >= rows || c >= cols || board[U(r)][U(c)] == '#') return;
        int v = next[node][static_cast<std::size_t>(board[U(r)][U(c)] - 'a')];
        if (v == 0) return;
        if (word_at[U(v)] >= 0) found.insert(words[U(word_at[U(v)])]);
        char saved = std::exchange(board[U(r)][U(c)], '#');
        self(r + 1, c, U(v)); self(r - 1, c, U(v)); self(r, c + 1, U(v)); self(r, c - 1, U(v));
        board[U(r)][U(c)] = saved;
    };
    for (int r0 = 0; r0 < rows; ++r0)
        for (int c0 = 0; c0 < cols; ++c0) dfs(r0, c0, 0);
    return {found.begin(), found.end()};
}

// ===================================================================== 20-26: dynamic programming, hashing
int lis(const Vec& a) {                                                         // LC 300
    Vec tails;
    for (int x : a) {
        auto it = std::ranges::lower_bound(tails, x);
        if (it == tails.end()) tails.push_back(x);
        else *it = x;
    }
    return isize(tails);
}

int edit_distance(std::string_view a, std::string_view b) {                     // LC 72, two rows
    Vec prev(b.size() + 1), cur(b.size() + 1);
    std::iota(prev.begin(), prev.end(), 0);
    for (std::size_t i = 1; i <= a.size(); ++i) {
        cur[0] = static_cast<int>(i);
        for (std::size_t j = 1; j <= b.size(); ++j)
            cur[j] = std::min(std::min(prev[j], cur[j - 1]) + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
        std::swap(prev, cur);
    }
    return prev[b.size()];
}

bool regex_match(std::string_view s, std::string_view p) {                      // LC 10: dp[i][j] = s[i..] matches p[j..]
    const std::size_t n = s.size(), m = p.size();
    std::vector<std::vector<bool>> dp(n + 1, std::vector<bool>(m + 1));
    dp[n][m] = true;
    for (std::size_t i = n + 1; i-- > 0;)
        for (std::size_t j = m; j-- > 0;) {
            bool first = i < n && (p[j] == '.' || p[j] == s[i]);
            dp[i][j] = j + 1 < m && p[j + 1] == '*' ? dp[i][j + 2] || (first && dp[i + 1][j]) : first && dp[i + 1][j + 1];
        }
    return dp[0][0];
}

int burst_balloons(const Vec& nums) {                                           // LC 312: k = LAST balloon burst in (i, j)
    const std::size_t n = nums.size() + 2;
    Vec v(n, 1);
    std::ranges::copy(nums, v.begin() + 1);
    std::vector<Vec> dp(n, Vec(n));
    for (std::size_t span = 2; span < n; ++span)
        for (std::size_t i = 0; i + span < n; ++i) {
            std::size_t j = i + span;
            for (std::size_t k = i + 1; k < j; ++k) dp[i][j] = std::max(dp[i][j], dp[i][k] + dp[k][j] + v[i] * v[k] * v[j]);
        }
    return dp[0][n - 1];
}

int shortest_path_all_nodes(const std::vector<Vec>& g) {                        // LC 847: BFS over (node, visited mask)
    const int n = isize(g);
    const unsigned full = (1u << n) - 1;
    std::vector<Vec> dist(U(n), Vec(std::size_t{1} << n, -1));
    std::deque<std::pair<int, unsigned>> q;
    for (int v = 0; v < n; ++v) { dist[U(v)][1u << v] = 0; q.emplace_back(v, 1u << v); }
    while (!q.empty()) {
        auto [v, mask] = q.front();
        q.pop_front();
        if (mask == full) return dist[U(v)][mask];
        for (int u : g[U(v)]) {
            unsigned m2 = mask | 1u << u;
            if (dist[U(u)][m2] == -1) { dist[U(u)][m2] = dist[U(v)][mask] + 1; q.emplace_back(u, m2); }
        }
    }
    return -1;
}

i64 job_scheduling(const Vec& start, const Vec& end, const Vec& profit) {       // LC 1235
    std::vector<std::size_t> idx(start.size());
    std::iota(idx.begin(), idx.end(), std::size_t{0});
    std::ranges::stable_sort(idx, {}, [&](std::size_t i) { return end[i]; });
    Vec ends;
    for (auto i : idx) ends.push_back(end[i]);
    std::vector<i64> dp(idx.size() + 1);
    for (std::size_t i = 1; i <= idx.size(); ++i) {
        std::size_t j = idx[i - 1];
        auto fit = static_cast<std::size_t>(                                    // jobs among the first i-1 ending <= start
            std::upper_bound(ends.begin(), ends.begin() + static_cast<std::ptrdiff_t>(i - 1), start[j]) - ends.begin());
        dp[i] = std::max(dp[i - 1], dp[fit] + profit[j]);
    }
    return dp.back();
}

__extension__ typedef unsigned __int128 u128;
constexpr u64 MOD = (u64{1} << 61) - 1;

u64 mul_mod(u64 a, u64 b) {
    u128 p = static_cast<u128>(a) * b;
    u64 r = (static_cast<u64>(p) & MOD) + static_cast<u64>(p >> 61);
    r = (r & MOD) + (r >> 61);
    return r >= MOD ? r - MOD : r;
}

std::string longest_dup_substring(std::string_view s, u64 base) {               // LC 1044: binary search + verified hashes
    const std::size_t n = s.size();
    std::vector<u64> pre(n + 1), pw(n + 1, 1);
    for (std::size_t i = 0; i < n; ++i) {
        pre[i + 1] = (mul_mod(pre[i], base) + u64{static_cast<unsigned char>(s[i])}) % MOD;
        pw[i + 1] = mul_mod(pw[i], base);
    }
    std::string_view best;
    std::size_t lo = 1, hi = n == 0 ? 0 : n - 1;
    while (lo <= hi) {
        std::size_t mid = lo + (hi - lo) / 2;
        std::string_view found;
        bool hit = false;
        std::unordered_map<u64, std::vector<std::size_t>> seen;
        for (std::size_t i = 0; i + mid <= n && !hit; ++i) {
            u64 h = (pre[i + mid] + MOD - mul_mod(pre[i], pw[mid])) % MOD;
            auto& starts = seen[h];
            for (std::size_t j : starts)
                if (s.substr(i, mid) == s.substr(j, mid)) { found = s.substr(i, mid); hit = true; break; }  // verify
            starts.push_back(i);
        }
        if (hit) { best = found; lo = mid + 1; }
        else hi = mid - 1;
    }
    return std::string(best);
}

// ===================================================================== 29-30: math
double median_sorted(const Vec& a, const Vec& b) {                              // LC 4: partition the shorter array
    if (a.empty() && b.empty()) throw std::invalid_argument("both arrays empty");
    if (a.size() > b.size()) return median_sorted(b, a);
    const int m = isize(a), n = isize(b), half = (m + n + 1) / 2;
    constexpr int NEG = std::numeric_limits<int>::min(), POS = std::numeric_limits<int>::max();
    int lo = 0, hi = m;
    while (true) {
        int i = lo + (hi - lo) / 2, j = half - i;
        int a_l = i == 0 ? NEG : a[U(i - 1)], a_r = i == m ? POS : a[U(i)];
        int b_l = j == 0 ? NEG : b[U(j - 1)], b_r = j == n ? POS : b[U(j)];
        if (a_l <= b_r && b_l <= a_r) {
            int left = std::max(a_l, b_l);
            return (m + n) % 2 == 1 ? left : (left + static_cast<double>(std::min(a_r, b_r))) / 2;
        }
        if (a_l > b_r) hi = i - 1;
        else lo = i + 1;
    }
}

int max_points(const Pairs& pts) {                                              // LC 149: gcd-normalized directions
    int best = std::min(isize(pts), 1);
    for (std::size_t i = 0; i < pts.size(); ++i) {
        std::unordered_map<i64, int> slopes;
        int dup = 0, local = 0;
        for (std::size_t j = i + 1; j < pts.size(); ++j) {
            i64 dx = i64{pts[j][0]} - pts[i][0], dy = i64{pts[j][1]} - pts[i][1];
            if (dx == 0 && dy == 0) { ++dup; continue; }
            i64 g = std::gcd(dx, dy);                                           // std::gcd works on absolute values
            dx /= g;
            dy /= g;
            if (dx < 0 || (dx == 0 && dy < 0)) { dx = -dx; dy = -dy; }          // one canonical sign per direction
            local = std::max(local, ++slopes[dx * 4'000'003 + dy]);
        }
        best = std::max(best, local + dup + 1);
    }
    return best;
}

// ===================================================================== oracles and random instances
Pairs random_edges(int n, int m) {
    Pairs e;
    for (int i = 0; i < m; ++i) {
        int a = R.next_int(n);
        int b = R.next_int(n);
        if (a == b) b = (b + 1) % n;
        e.push_back({a, b});
    }
    return e;
}

Tree random_tree(int n) {
    Tree t;
    if (n == 0) return t;
    std::vector<Node*> nodes{t.make(R.range(-10, 10))};
    t.root = nodes[0];
    for (int i = 1; i < n; ++i) {
        Node* c = t.make(R.range(-10, 10));
        while (true) {
            Node* p = nodes[U(R.next_int(isize(nodes)))];
            if (R.next_int(2) == 0 && p->left == nullptr) { p->left = c; break; }
            if (p->right == nullptr) { p->right = c; break; }
            if (p->left == nullptr) { p->left = c; break; }
        }
        nodes.push_back(c);
    }
    return t;
}

int components(int n, const Pairs& edges, int skip) {
    Vec p(U(n));
    std::iota(p.begin(), p.end(), 0);
    int c = n;
    for (int e = 0; e < isize(edges); ++e)
        if (e != skip) { int a = find_root(p, edges[U(e)][0]), b = find_root(p, edges[U(e)][1]); if (a != b) { p[U(a)] = b; --c; } }
    return c;
}

bool regex_brute(std::string_view s, std::string_view p) {
    if (p.empty()) return s.empty();
    bool first = !s.empty() && (p[0] == '.' || p[0] == s[0]);
    if (p.size() >= 2 && p[1] == '*') return regex_brute(s, p.substr(2)) || (first && regex_brute(s.substr(1), p));
    return first && regex_brute(s.substr(1), p.substr(1));
}

int edit_brute(std::string_view a, std::string_view b) {
    if (a.empty()) return isize(b);
    if (b.empty()) return isize(a);
    if (a[0] == b[0]) return edit_brute(a.substr(1), b.substr(1));
    return 1 + std::min({edit_brute(a.substr(1), b), edit_brute(a, b.substr(1)), edit_brute(a.substr(1), b.substr(1))});
}

bool sorted_under(const std::vector<std::string>& words, std::string_view order) {
    std::array<std::size_t, 26> rank{};
    for (std::size_t i = 0; i < order.size(); ++i) rank[static_cast<std::size_t>(order[i] - 'a')] = i;
    for (std::size_t i = 0; i + 1 < words.size(); ++i) {
        const auto& a = words[i];
        const auto& b = words[i + 1];
        auto [ia, ib] = std::ranges::mismatch(a, b);
        if (ia == a.end() || ib == b.end()) { if (a.size() > b.size()) return false; continue; }
        if (rank[static_cast<std::size_t>(*ia - 'a')] > rank[static_cast<std::size_t>(*ib - 'a')]) return false;
    }
    return true;
}

bool word_on_board(const std::vector<std::string>& b, std::string_view w, std::size_t k, int r, int c,
                   std::vector<std::vector<bool>>& used) {                      // per-word DFS oracle (depth <= |w|)
    if (r < 0 || c < 0 || r >= isize(b) || c >= isize(b[0]) || used[U(r)][U(c)] || b[U(r)][U(c)] != w[k]) return false;
    if (k + 1 == w.size()) return true;
    used[U(r)][U(c)] = true;
    bool ok = word_on_board(b, w, k + 1, r + 1, c, used) || word_on_board(b, w, k + 1, r - 1, c, used)
              || word_on_board(b, w, k + 1, r, c + 1, used) || word_on_board(b, w, k + 1, r, c - 1, used);
    used[U(r)][U(c)] = false;
    return ok;
}

int main() {
    constexpr int T = 1'000;
    report(1, "LC 146", "LRU cache vs list model", [] {
        int cap = R.range(1, 4);
        LruCache c(cap);
        std::vector<std::pair<int, int>> model;                                 // least recent first
        for (int op = 0; op < 30; ++op) {
            int k = R.next_int(6);
            auto it = std::ranges::find(model, k, &std::pair<int, int>::first);
            if (R.next_int(2) == 0) {
                int want = it == model.end() ? -1 : it->second;
                if (it != model.end()) std::rotate(it, it + 1, model.end());    // becomes most recent
                if (c.get(k) != want) return false;
            } else {
                int v = R.next_int(100);
                if (it != model.end()) model.erase(it);
                model.emplace_back(k, v);
                if (isize(model) > cap) model.erase(model.begin());
                c.put(k, v);
            }
        }
        return true;
    }, T);
    report(2, "LC 460", "LFU cache vs (freq, last-use) model", [] {
        int cap = R.range(1, 3);
        LfuCache c(cap);
        std::map<int, std::array<i64, 3>> model;                                // key -> {value, freq, last use}
        i64 tick = 0;
        for (int op = 0; op < 30; ++op) {
            int k = R.next_int(5);
            ++tick;
            auto it = model.find(k);
            if (R.next_int(2) == 0) {
                int want = it == model.end() ? -1 : static_cast<int>(it->second[0]);
                if (it != model.end()) { ++it->second[1]; it->second[2] = tick; }
                if (c.get(k) != want) return false;
            } else {
                int v = R.next_int(100);
                if (it != model.end()) it->second = {v, it->second[1] + 1, tick};
                else {
                    if (isize(model) == cap)
                        model.erase(std::ranges::min_element(model, {}, [](const auto& kv) { return std::pair{kv.second[1], kv.second[2]}; }));
                    model[k] = {v, 1, tick};
                }
                c.put(k, v);
            }
        }
        return true;
    }, T);
    report(3, "LC 295", "median of a stream vs sorted list", [] {
        MedianFinder mf;
        Vec all;
        for (int i = R.range(1, 20); i > 0; --i) {
            int x = R.range(-50, 50);
            mf.add(x);
            all.insert(std::ranges::upper_bound(all, x), x);
            std::size_t n = all.size();
            double want = n % 2 == 1 ? all[n / 2] : (all[n / 2 - 1] + static_cast<double>(all[n / 2])) / 2;
            if (mf.median() != want) return false;
        }
        return true;
    }, T);
    report(4, "LC 239", "sliding window maximum vs brute", [] {
        Vec a = R.ints(R.range(1, 15), -9, 9);
        auto k = U(R.range(1, isize(a)));
        Vec got = window_max(a, k);
        for (std::size_t i = 0; i + k <= a.size(); ++i) if (got[i] != std::ranges::max(std::span(a).subspan(i, k))) return false;
        return true;
    }, T);
    report(5, "LC 76", "minimum window substring vs brute", [] {
        std::string s = R.word(R.range(0, 12), 3);
        std::string t = R.word(R.range(1, 3), 3);
        std::string want;
        for (std::size_t n = 1; n <= s.size() && want.empty(); ++n)
            for (std::size_t i = 0; i + n <= s.size() && want.empty(); ++i) {
                std::array<int, 256> cnt{};
                for (char c : s.substr(i, n)) ++cnt[static_cast<unsigned char>(c)];
                bool ok = true;
                for (char c : t) if (--cnt[static_cast<unsigned char>(c)] < 0) ok = false;
                if (ok) want = s.substr(i, n);
            }
        return min_window(s, t) == want;
    }, T);
    report(6, "LC 42", "trapping rain water vs per-column brute", [] {
        Vec h = R.ints(R.range(0, 15), 0, 8);
        i64 want = 0;
        for (std::size_t i = 0; i < h.size(); ++i)
            want += std::min(std::ranges::max(std::span(h).first(i + 1)), std::ranges::max(std::span(h).subspan(i))) - h[i];
        return trap(h) == want;
    }, T);
    report(7, "LC 84", "largest rectangle in histogram vs O(n^2)", [] {
        Vec h = R.ints(R.range(0, 12), 0, 9);
        i64 want = 0;
        for (std::size_t i = 0; i < h.size(); ++i) {
            i64 mn = std::numeric_limits<i64>::max();
            for (std::size_t j = i; j < h.size(); ++j) { mn = std::min<i64>(mn, h[j]); want = std::max(want, mn * static_cast<i64>(j - i + 1)); }
        }
        return largest_rectangle(h) == want;
    }, T);
    report(8, "LC 23", "merge k sorted lists vs concat + sort", [] {
        std::vector<Vec> lists(U(R.range(0, 6)));
        Vec all;
        for (auto& l : lists) { l = R.ints(R.range(0, 6), -20, 20); std::ranges::sort(l); all.insert(all.end(), l.begin(), l.end()); }
        std::ranges::sort(all);
        return merge_k(lists) == all;
    }, T);
    report(9, "LC 127", "word ladder vs BFS on explicit graph", [] {
        std::vector<std::string> words;
        for (int i = R.range(1, 10); i > 0; --i) words.push_back(R.word(3, 3));
        std::string begin = R.word(3, 3);
        std::string end = words[U(R.next_int(isize(words)))];
        std::vector<std::string> nodes{begin};
        for (const auto& w : words) if (std::find(nodes.begin() + 1, nodes.end(), w) == nodes.end()) nodes.push_back(w);
        Vec dist(nodes.size(), -1);
        dist[0] = 1;
        std::deque<std::size_t> q{0};
        int want = 0;
        while (!q.empty()) {
            std::size_t u = q.front();
            q.pop_front();
            if (nodes[u] == end) { want = dist[u]; break; }
            for (std::size_t v = 1; v < nodes.size(); ++v) {
                int diff = 0;
                for (std::size_t k = 0; k < 3; ++k) diff += nodes[u][k] != nodes[v][k] ? 1 : 0;
                if (diff == 1 && dist[v] == -1) { dist[v] = dist[u] + 1; q.push_back(v); }
            }
        }
        return ladder_length(begin, end, words) == want;
    }, T);
    report(10, "LC 210", "course order: valid order, or a real cycle", [] {
        int n = R.range(1, 7);
        Pairs pre(U(R.next_int(2 * n)));
        for (auto& p : pre) { int a = R.next_int(n); int b = R.next_int(n); p = {a, b}; }
        Vec order = course_order(n, pre);
        const std::size_t N = U(n);
        std::vector<std::vector<bool>> reach(N, std::vector<bool>(N));
        for (auto [a, b] : pre) reach[U(b)][U(a)] = true;
        for (std::size_t k = 0; k < N; ++k)
            for (std::size_t i = 0; i < N; ++i)
                for (std::size_t j = 0; j < N; ++j) reach[i][j] = reach[i][j] || (reach[i][k] && reach[k][j]);
        bool cyclic = false;
        for (std::size_t i = 0; i < N; ++i) cyclic = cyclic || reach[i][i];
        if (order.empty()) return cyclic;
        Vec at(N);
        for (int i = 0; i < n; ++i) at[U(order[U(i)])] = i;
        for (auto [a, b] : pre) if (at[U(b)] >= at[U(a)]) return false;
        return !cyclic;
    }, T);
    report(11, "LC 743", "network delay (Dijkstra) vs Floyd-Warshall", [] {
        int n = R.range(1, 7);
        std::vector<std::array<int, 3>> times(U(R.next_int(3 * n)));
        for (auto& t : times) { int u = R.range(1, n); int v = R.range(1, n); int w = R.range(0, 9); t = {u, v, w}; }
        int src = R.range(1, n);
        constexpr i64 BIG = std::numeric_limits<i64>::max() / 4;
        const std::size_t N = U(n) + 1;
        std::vector<std::vector<i64>> d(N, std::vector<i64>(N, BIG));
        for (std::size_t i = 1; i < N; ++i) d[i][i] = 0;
        for (auto [u, v, w] : times) d[U(u)][U(v)] = std::min<i64>(d[U(u)][U(v)], w);
        for (std::size_t k = 1; k < N; ++k)
            for (std::size_t i = 1; i < N; ++i)
                for (std::size_t j = 1; j < N; ++j) d[i][j] = std::min(d[i][j], d[i][k] + d[k][j]);
        i64 worst = 0;
        for (std::size_t i = 1; i < N; ++i) worst = std::max(worst, d[U(src)][i]);
        int want = worst >= BIG ? -1 : static_cast<int>(worst);
        return network_delay(times, n, src) == want;
    }, T);
    report(12, "LC 1192", "critical connections vs remove-and-recount", [] {
        int n = R.range(2, 8);
        Pairs e = random_edges(n, R.range(1, 2 * n));
        Pairs want;
        int all_parts = components(n, e, -1);
        for (int i = 0; i < isize(e); ++i)
            if (components(n, e, i) > all_parts) want.push_back({std::min(e[U(i)][0], e[U(i)][1]), std::max(e[U(i)][0], e[U(i)][1])});
        Pairs got = bridges(n, e);
        std::ranges::sort(want);
        std::ranges::sort(got);
        return got == want;
    }, T);
    report(13, "LC 305", "islands online (DSU) vs BFS recount", [] {
        int rows = R.range(1, 5);
        int cols = R.range(1, 5);
        Pairs adds(U(R.range(1, 12)));
        for (auto& a : adds) { int r = R.next_int(rows); int c = R.next_int(cols); a = {r, c}; }
        Vec got = islands_online(rows, cols, adds);
        std::vector<std::vector<bool>> land(U(rows), std::vector<bool>(U(cols)));
        for (std::size_t k = 0; k < adds.size(); ++k) {
            land[U(adds[k][0])][U(adds[k][1])] = true;
            int count = 0;
            std::vector<std::vector<bool>> seen(U(rows), std::vector<bool>(U(cols)));
            for (int r0 = 0; r0 < rows; ++r0)
                for (int c0 = 0; c0 < cols; ++c0) {
                    if (!land[U(r0)][U(c0)] || seen[U(r0)][U(c0)]) continue;
                    ++count;
                    std::deque<std::pair<int, int>> q{{r0, c0}};
                    seen[U(r0)][U(c0)] = true;
                    while (!q.empty()) {
                        auto [pr, pc] = q.front();
                        q.pop_front();
                        for (auto [dr, dc] : DIRS) {
                            int a = pr + dr, b = pc + dc;
                            if (a >= 0 && b >= 0 && a < rows && b < cols && land[U(a)][U(b)] && !seen[U(a)][U(b)]) { seen[U(a)][U(b)] = true; q.emplace_back(a, b); }
                        }
                    }
                }
            if (got[k] != count) return false;
        }
        return true;
    }, T);
    report(14, "LC 269", "alien dictionary vs brute over letter orders", [] {
        std::vector<std::string> words(U(R.range(1, 5)));
        for (auto& w : words) w = R.word(R.range(1, 3), 4);
        if (R.next_int(2) == 0) {                                               // half the time, sort under a hidden order
            std::array<int, 4> perm{0, 1, 2, 3};
            for (int i = 3; i > 0; --i) std::swap(perm[U(i)], perm[U(R.next_int(i + 1))]);
            std::ranges::stable_sort(words, [&](const std::string& x, const std::string& y) {
                auto [ix, iy] = std::ranges::mismatch(x, y);
                if (ix != x.end() && iy != y.end()) return perm[U(*ix - 'a')] < perm[U(*iy - 'a')];
                return x.size() < y.size();
            });
        }
        std::string got = alien_order(words);
        std::set<char> letters;
        for (const auto& w : words) letters.insert(w.begin(), w.end());
        std::string order = "abcd";
        bool any_order = false;
        do any_order = sorted_under(words, order);
        while (!any_order && std::ranges::next_permutation(order).found);
        if (!any_order) return got.empty();
        if (got.size() != letters.size()) return false;
        std::string full = got;
        for (char c = 'a'; c <= 'd'; ++c) if (got.find(c) == std::string::npos) full += c;
        return sorted_under(words, full);
    }, T);
    report(15, "LC 297", "serialize/deserialize round trip", [] {
        Tree t = random_tree(R.range(0, 25));
        return same_tree(t.root, deserialize(serialize(t.root)).root);
    }, T);
    Tree chain;
    Node* tail = chain.root = chain.make(0);
    for (int i = 1; i < 100'000; ++i) tail = tail->right = chain.make(i % 7);
    bool deep_ok = same_tree(chain.root, deserialize(serialize(chain.root)).root);
    report(16, "LC 124", "max path sum vs all node pairs", [] {
        Tree t = random_tree(R.range(1, 12));
        std::vector<const Node*> nodes, st{t.root};
        std::unordered_map<const Node*, const Node*> parent;
        while (!st.empty()) {
            const Node* n = st.back();
            st.pop_back();
            nodes.push_back(n);
            for (const Node* c : {n->left, n->right}) if (c) { parent[c] = n; st.push_back(c); }
        }
        auto up = [&](const Node* x) -> const Node* { auto it = parent.find(x); return it == parent.end() ? nullptr : it->second; };
        i64 want = std::numeric_limits<i64>::min();
        for (const Node* u : nodes)
            for (const Node* v : nodes) {
                std::unordered_set<const Node*> ancestors;
                for (const Node* x = u; x; x = up(x)) ancestors.insert(x);
                const Node* lca = v;
                while (!ancestors.contains(lca)) lca = up(lca);
                i64 s = lca->val;
                for (const Node* x = u; x != lca; x = up(x)) s += x->val;
                for (const Node* x = v; x != lca; x = up(x)) s += x->val;
                want = std::max(want, s);
            }
        return max_path_sum(t.root) == want;
    }, T);
    report(17, "LC 315", "count smaller after self vs O(n^2)", [] {
        Vec a = R.ints(R.range(0, 15), -5, 5);
        Vec got = count_smaller_after(a);
        for (std::size_t i = 0; i < a.size(); ++i)
            if (got[i] != std::ranges::count_if(std::span(a).subspan(i + 1), [&](int x) { return x < a[i]; })) return false;
        return true;
    }, T);
    report(18, "LC 732", "calendar max overlap vs per-point count", [] {
        MyCalendarThree cal;
        std::array<int, 30> cover{};
        for (int b = R.range(1, 8); b > 0; --b) {
            int s = R.next_int(25);
            int e = s + R.range(1, 5);
            for (int x = s; x < e; ++x) ++cover[U(x)];
            if (cal.book(s, e) != std::ranges::max(cover)) return false;
        }
        return true;
    }, T);
    report(19, "LC 212", "word search II (trie) vs per-word search", [] {
        int rows = R.range(1, 3);
        int cols = R.range(1, 3);
        std::vector<std::string> board(U(rows), std::string(U(cols), ' '));
        for (auto& row : board) for (char& c : row) c = static_cast<char>('a' + R.next_int(3));
        std::vector<std::string> words(U(R.range(1, 6)));
        for (auto& w : words) w = R.word(R.range(1, 4), 3);
        std::vector<std::string> got = find_words(board, words);
        std::set<std::string> want;
        for (const auto& w : words)
            for (int r0 = 0; r0 < rows; ++r0)
                for (int c0 = 0; c0 < cols; ++c0) {
                    std::vector<std::vector<bool>> used(U(rows), std::vector<bool>(U(cols)));
                    if (word_on_board(board, w, 0, r0, c0, used)) want.insert(w);
                }
        return got == std::vector<std::string>(want.begin(), want.end());
    }, T);
    report(20, "LC 300", "LIS length vs O(n^2)", [] {
        Vec a = R.ints(R.range(0, 15), 0, 9);
        Vec d(a.size(), 1);
        int want = 0;
        for (std::size_t i = 0; i < a.size(); ++i) {
            for (std::size_t j = 0; j < i; ++j) if (a[j] < a[i]) d[i] = std::max(d[i], d[j] + 1);
            want = std::max(want, d[i]);
        }
        return lis(a) == want;
    }, T);
    report(21, "LC 72", "edit distance vs exponential recursion", [] {
        std::string a = R.word(R.range(0, 6), 3);
        std::string b = R.word(R.range(0, 6), 3);
        return edit_distance(a, b) == edit_brute(a, b);
    }, T);
    report(22, "LC 10", "regex . and * (DP) vs backtracking", [] {
        std::string s = R.word(R.range(0, 6), 2);
        std::string p;
        for (int i = R.range(0, 4); i > 0; --i) {
            if (R.next_int(4) == 0) p += '.';
            else p += static_cast<char>('a' + R.next_int(2));
            if (R.next_int(2) == 0) p += '*';
        }
        return regex_match(s, p) == regex_brute(s, p);
    }, T);
    report(23, "LC 312", "burst balloons vs every burst order", [] {
        Vec nums = R.ints(R.range(1, 6), 0, 6);
        Vec perm(nums.size());
        std::iota(perm.begin(), perm.end(), 0);
        int want = 0;
        do {
            std::vector<bool> gone(nums.size());
            int coins = 0;
            for (int idx : perm) {
                int l = idx - 1, r = idx + 1;
                while (l >= 0 && gone[U(l)]) --l;
                while (r < isize(nums) && gone[U(r)]) ++r;
                coins += (l < 0 ? 1 : nums[U(l)]) * nums[U(idx)] * (r >= isize(nums) ? 1 : nums[U(r)]);
                gone[U(idx)] = true;
            }
            want = std::max(want, coins);
        } while (std::ranges::next_permutation(perm).found);
        return burst_balloons(nums) == want;
    }, T);
    report(24, "LC 847", "shortest walk visiting all nodes vs brute", [] {
        int n = R.range(1, 6);
        std::vector<Vec> g(U(n));
        std::vector<Vec> d(U(n), Vec(U(n), 1'000));
        for (std::size_t i = 0; i < U(n); ++i) d[i][i] = 0;
        for (int v = 1; v < n; ++v) {                                           // a random tree first: connected
            int u = R.next_int(v);
            g[U(u)].push_back(v); g[U(v)].push_back(u); d[U(u)][U(v)] = d[U(v)][U(u)] = 1;
        }
        for (int extra = R.next_int(n); extra > 0; --extra) {
            int u = R.next_int(n);
            int v = R.next_int(n);
            if (u != v && d[U(u)][U(v)] != 1) { g[U(u)].push_back(v); g[U(v)].push_back(u); d[U(u)][U(v)] = d[U(v)][U(u)] = 1; }
        }
        for (std::size_t k = 0; k < U(n); ++k)
            for (std::size_t i = 0; i < U(n); ++i)
                for (std::size_t j = 0; j < U(n); ++j) d[i][j] = std::min(d[i][j], d[i][k] + d[k][j]);
        Vec perm(U(n));
        std::iota(perm.begin(), perm.end(), 0);
        int want = std::numeric_limits<int>::max();
        do {
            int s = 0;
            for (std::size_t i = 0; i + 1 < perm.size(); ++i) s += d[U(perm[i])][U(perm[i + 1])];
            want = std::min(want, s);
        } while (std::ranges::next_permutation(perm).found);
        return shortest_path_all_nodes(g) == want;
    }, T);
    report(25, "LC 1235", "weighted job scheduling vs all subsets", [] {
        int n = R.range(1, 9);
        Vec s(U(n)), e(U(n)), p(U(n));
        for (std::size_t i = 0; i < U(n); ++i) { s[i] = R.next_int(10); e[i] = s[i] + R.range(1, 5); p[i] = R.range(1, 20); }
        i64 want = 0;
        for (unsigned mask = 0; mask < (1u << n); ++mask) {
            bool ok = true;
            i64 sum = 0;
            for (std::size_t i = 0; i < U(n) && ok; ++i) {
                if ((mask >> i & 1u) == 0) continue;
                sum += p[i];
                for (std::size_t j = i + 1; j < U(n); ++j) if ((mask >> j & 1u) == 1 && s[i] < e[j] && s[j] < e[i]) ok = false;
            }
            if (ok) want = std::max(want, sum);
        }
        return job_scheduling(s, e, p) == want;
    }, T);
    const u64 hash_base = (R.next() >> 4) % (MOD - 256) + 256;
    report(26, "LC 1044", "longest duplicate substring vs brute", [hash_base] {
        std::string s = R.word(R.range(2, 18), 2);
        std::size_t want = 0;
        for (std::size_t n = 1; n < s.size(); ++n)
            for (std::size_t i = 0; i + n <= s.size(); ++i) if (s.find(s.substr(i, n), i + 1) != std::string::npos) want = std::max(want, n);
        std::string got = longest_dup_substring(s, hash_base);
        bool twice = got.empty() || s.find(got) != s.rfind(got);
        return got.size() == want && twice;
    }, T);
    report(27, "LC 362", "hit counter (300 s ring) vs timestamp list", [] {
        HitCounter hc;
        Vec hits;
        int t = R.range(1, 50);
        for (int op = 0; op < 40; ++op) {
            t += R.next_int(120);
            if (R.next_int(2) == 0) { hc.hit(t); hits.push_back(t); }
            else if (hc.hits(t) != std::ranges::count_if(hits, [t](int x) { return t - x < 300; })) return false;
        }
        return true;
    }, T);
    report(28, "LC 981", "time-based key-value store vs linear scan", [] {
        TimeMap tm;
        std::vector<std::tuple<std::string, std::string, int>> log;
        int ts = 0;
        for (int op = 0; op < 30; ++op) {
            std::string k = "k" + std::to_string(R.next_int(3));
            if (R.next_int(2) == 0) {
                ts += R.range(1, 3);
                std::string v = "v" + std::to_string(R.next_int(100));
                tm.set(k, v, ts);
                log.emplace_back(k, v, ts);
            } else {
                int q = R.next_int(ts + 2);
                std::string want;
                int best_ts = -1;
                for (const auto& [lk, lv, lt] : log) if (lk == k && lt <= q && lt > best_ts) { best_ts = lt; want = lv; }
                if (tm.get(k, q) != want) return false;
            }
        }
        return true;
    }, T);
    report(29, "LC 4", "median of two sorted arrays vs merge", [] {
        Vec a = R.ints(R.range(0, 6), -20, 20);
        Vec b = R.ints(R.range(a.empty() ? 1 : 0, 6), -20, 20);
        std::ranges::sort(a);
        std::ranges::sort(b);
        Vec all = a;
        all.insert(all.end(), b.begin(), b.end());
        std::ranges::sort(all);
        std::size_t n = all.size();
        double want = n % 2 == 1 ? all[n / 2] : (all[n / 2 - 1] + static_cast<double>(all[n / 2])) / 2;
        return median_sorted(a, b) == want;
    }, T);
    report(30, "LC 149", "max points on a line vs cross-product brute", [] {
        Pairs pts(U(R.range(1, 8)));
        for (auto& p : pts) { int x = R.range(-4, 4); int y = R.range(-4, 4); p = {x, y}; }
        int want = 1;
        for (std::size_t i = 0; i < pts.size(); ++i)
            for (std::size_t j = i + 1; j < pts.size(); ++j) {
                int c = 0;
                bool same = pts[i] == pts[j];
                for (const auto& q : pts) {
                    i64 cross = i64{pts[j][0] - pts[i][0]} * (q[1] - pts[i][1]) - i64{pts[j][1] - pts[i][1]} * (q[0] - pts[i][0]);
                    if (same ? q == pts[i] : cross == 0) ++c;
                }
                want = std::max(want, c);
            }
        return max_points(pts) == want;
    }, T);
    std::println("serialize/deserialize of a 100,000-node chain without recursion: {} | problems with any failing trial: {} of 30",
                 deep_ok, failures);
}
```

**Output, both compilers (verified; GCC shown, Clang byte-identical, and both byte-identical to Java):**

```text
 1. LC 146   LRU cache vs list model                         1000/1000
 2. LC 460   LFU cache vs (freq, last-use) model             1000/1000
 3. LC 295   median of a stream vs sorted list               1000/1000
 4. LC 239   sliding window maximum vs brute                 1000/1000
 5. LC 76    minimum window substring vs brute               1000/1000
 6. LC 42    trapping rain water vs per-column brute         1000/1000
 7. LC 84    largest rectangle in histogram vs O(n^2)        1000/1000
 8. LC 23    merge k sorted lists vs concat + sort           1000/1000
 9. LC 127   word ladder vs BFS on explicit graph            1000/1000
10. LC 210   course order: valid order, or a real cycle      1000/1000
11. LC 743   network delay (Dijkstra) vs Floyd-Warshall      1000/1000
12. LC 1192  critical connections vs remove-and-recount      1000/1000
13. LC 305   islands online (DSU) vs BFS recount             1000/1000
14. LC 269   alien dictionary vs brute over letter orders    1000/1000
15. LC 297   serialize/deserialize round trip                1000/1000
16. LC 124   max path sum vs all node pairs                  1000/1000
17. LC 315   count smaller after self vs O(n^2)              1000/1000
18. LC 732   calendar max overlap vs per-point count         1000/1000
19. LC 212   word search II (trie) vs per-word search        1000/1000
20. LC 300   LIS length vs O(n^2)                            1000/1000
21. LC 72    edit distance vs exponential recursion          1000/1000
22. LC 10    regex . and * (DP) vs backtracking              1000/1000
23. LC 312   burst balloons vs every burst order             1000/1000
24. LC 847   shortest walk visiting all nodes vs brute       1000/1000
25. LC 1235  weighted job scheduling vs all subsets          1000/1000
26. LC 1044  longest duplicate substring vs brute            1000/1000
27. LC 362   hit counter (300 s ring) vs timestamp list      1000/1000
28. LC 981   time-based key-value store vs linear scan       1000/1000
29. LC 4     median of two sorted arrays vs merge            1000/1000
30. LC 149   max points on a line vs cross-product brute     1000/1000
serialize/deserialize of a 100,000-node chain without recursion: true | problems with any failing trial: 0 of 30
```

---

## 4. What the results show

* **All 30,000 trials pass in all three builds,** and the 100,000-node chain serializes and deserializes without recursion.
* **The three outputs are byte-identical.** The instances are the same because the random draws are the same, so a failure in one language would show up as a differing line.
* **The oracles have teeth.** A mutation run (a script outside the listings) planted one classic bug at a time into the Java solutions and reran the whole harness:

| # | Planted bug | Trials still passing | Caught? |
|---|---|---|---|
| 12 | Bridges: skip the parent vertex instead of the arriving edge | 593 / 1,000 | Yes: one edge of a doubled pair is reported as a bridge |
| 2 | LFU: forget to advance `minFreq` when its bucket empties | crashed (NullPointerException at the next eviction) | Yes |
| 29 | Median of two arrays: `half = (m + n) / 2` | 558 / 1,000 | Yes: every odd total length |
| 25 | Job scheduling: a job may not start when another ends (`<` for `<=`) | 573 / 1,000 | Yes |
| 30 | Max points: no canonical sign for a direction | 932 / 1,000 | Yes: (1, 2) and (−1, −2) counted as different lines |
| 14 | Alien dictionary: drop the "word before its own prefix" check | 959 / 1,000 | Yes |
| 22 | Regex: `x*` must match at least one x | 890 / 1,000 | Yes |
| 17 | Count smaller: count smaller-or-equal | 320 / 1,000 | Yes |
| 26 | Longest duplicate substring: trust hash matches without comparing | 1,000 / 1,000 | **No**: see §1.3 |

In every run that completed, no other problem's pass count changed. The pass rates also say something about test design: the canonical-sign bug survived 93% of trials and the prefix bug 96%. **A handful of hand-written tests would likely have missed both.** A thousand small random instances found them.

* **The one mutant that survived is the one that matters most to argue.** A missing collision check is invisible to random testing and fatal under adversarial input. Its correctness has to come from the code's structure (verification), not from the test.
---

## 5. The last 10 minutes: Extensions A, B and C for each problem

Each row answers the three standard follow-ups in a sentence or two: **A**, 64 threads share the structure or the work; **B**, the input is an unbounded stream or 100 TB; **C**, the data or traffic is spread over 100 machines. The pattern to notice is which part of each invariant is **mergeable** (it survives splitting the input and combining partial results), because that part extends for free and the rest needs a new idea.

### 5.1 Designs

| # | Problem | A — 64 threads | B — stream / 100 TB | C — 100 machines |
|---|---|---|---|---|
| 1 | LRU cache | Lock striping (File 2: 3.6–4.5× at 8 threads); for read-heavy loads, Caffeine-style buffered access recording | Bound by bytes, not entries; TinyLFU admission so a scan doesn't flush the cache | Consistent hashing of keys to nodes, local LRU per node, hot keys replicated |
| 2 | LFU cache | `minFreq` and the bucket map are one shared invariant: stripe whole caches, or replace exact counts with a frequency sketch | Exact counts for an unbounded key space grow without bound: a Count-Min sketch with periodic halving ("aging") as in TinyLFU | Per-node LFU; global popularity by summing per-node sketches (exact merge) |
| 3 | Median from a data stream | Exact medians don't merge from per-thread medians: one locked pair of heaps, or per-thread quantile sketches merged on read | Two heaps keep every element: O(n). Use a quantile sketch (KLL, t-digest) with a stated rank error; for a sliding window, two heaps with lazy deletion or an order-statistic tree | Exact: distributed selection, binary search on the value with a "count ≤ v" round to all nodes (about 32 rounds for 32-bit values). Approximate: merge KLL sketches |
| 27 | Hit counter | Per-thread counters summed on read (`LongAdder` per bucket); resetting a stale bucket must be a CAS on (second, count) | Already O(window) memory; per-key counts for millions of keys: a Count-Min sketch per bucket | Counts are sums, so per-node rings merge exactly; clock skew decides which bucket a hit lands in |
| 28 | Time map | `ConcurrentHashMap` of `ConcurrentSkipListMap` (Java); readers never block writers | This is an MVCC store: an LSM tree (in-memory sorted table, flushed to sorted runs, merged by compaction) | Shard by key so all versions of a key live together; timestamps from one clock source or hybrid logical clocks |

### 5.2 Arrays, windows, stacks and heaps

| # | Problem | A — 64 threads | B — stream / 100 TB | C — 100 machines |
|---|---|---|---|---|
| 4 | Sliding window maximum | Split into blocks of k, precompute prefix and suffix maxima per block in parallel (van Herk / Gil–Werman); each window max = max(suffix of one block, prefix of the next) | Already O(k) memory in one pass; for time-based windows store (time, value) and expire by time | Max is mergeable: each shard computes window maxima over its range, with a halo of k − 1 elements from the left neighbour |
| 5 | Minimum window substring | One string is a sequential scan; parallelize across independent queries, or split s into chunks with overlap equal to a window-length cap | Positions of the current window in a deque; without a length cap the window can grow without bound, so cap it | Range shards with a halo of the length cap; the global answer is the minimum over shards |
| 6 | Trapping rain water | water[i] = min(prefixMax, suffixMax) − h[i]: two parallel scans (max is associative) and a parallel sum | Two sequential passes over the file (suffix maxima backwards to disk, then forwards); or a monotonic stack that settles water when a taller bar arrives | Each shard sends its maximum; an exclusive scan over 100 values gives every shard its left and right walls, then water is local |
| 7 | Largest rectangle in histogram | Divide and conquer on the minimum bar, or parallel all-nearest-smaller-values | The stack can hold O(n) bars on increasing input: spill it to disk, or bound the width | Local stacks per shard; a rectangle crossing shards needs each shard's boundary stack summary from its neighbours |
| 8 | Merge k sorted lists | Split the value range with sampled splitters and merge each range on its own thread (File 1 §4.1) | This is the merge phase of external sort: one buffer per list | Range-partition first so no global merge is needed; or stream a k-way merge at a coordinator |

### 5.3 Graphs

| # | Problem | A — 64 threads | B — stream / 100 TB | C — 100 machines |
|---|---|---|---|---|
| 9 | Word ladder | Level-synchronous BFS; visited claimed by CAS; bidirectional search shrinks the frontier | Dictionary on disk: build wildcard buckets by external sort on (pattern, word), then BFS one level per pass | BSP BFS (File 1) with words partitioned by pattern hash; bidirectional from both ends |
| 10 | Course schedule II | Parallel Kahn: all indegree-0 vertices of a level at once, indegrees decremented atomically | Indegrees fit in RAM even when edges don't: stream the edge file once per level (semi-external) | BSP: each superstep removes every indegree-0 vertex and sends decrements; vertices left at the end lie on cycles |
| 11 | Network delay time | Delta-stepping: relax a whole distance bucket in parallel | Graphs on disk make Dijkstra I/O-bound; for repeated queries precompute (contraction hierarchies) | Distributed delta-stepping or BSP Bellman–Ford; partition for locality (File 1: 256× fewer messages) |
| 12 | Critical connections | DFS is inherently sequential; parallel biconnectivity (Tarjan–Vishkin) uses a spanning tree plus an Euler tour | Semi-streaming in O(n) memory: keep a spanning forest F₁ and a spanning forest F₂ of the edges F₁ rejects; F₁ ∪ F₂ has exactly the same bridges as the whole graph | Distributed spanning forest (Borůvka rounds), then a tree edge is a bridge iff no non-tree edge covers it (LCA-based path marking) |
| 13 | Number of islands II | Concurrent union-find with CAS on parent pointers (Anderson–Woll); the island count as an atomic | Cells arrive as a stream: union-find over a hash map of land cells only | Tile the grid; union-find per tile; tiles exchange boundary labels and union them (distributed connected-component labelling) |
| 14 | Alien dictionary | Edge extraction from adjacent pairs is embarrassingly parallel; the alphabet-sized topological sort is tiny | Only adjacent words matter: keep the previous word and an alphabet × alphabet edge set, O(1) words of memory | Each shard extracts edges from its sorted range; add the edges from each pair of shard boundary words; union the edge sets |

### 5.4 Trees

| # | Problem | A — 64 threads | B — stream / 100 TB | C — 100 machines |
|---|---|---|---|---|
| 15 | Serialize and deserialize | A subtree's preorder is contiguous: serialize subtrees in parallel (fork-join) and concatenate | Already streaming: the iterative serializer emits tokens as it walks and the deserializer consumes them one at a time with O(height) state | A tree bigger than one machine is stored as pages of subtrees with references between them (B-tree and Merkle-tree style) |
| 16 | Binary tree maximum path sum | Fork-join over subtrees: each task returns (best path inside, best downward gain) | An edge-list tree on disk: compute depths, sort by depth, process deepest first, keeping gains for the current and next level | The (best inside, best downward gain) pair is a mergeable summary: each machine summarizes its subtrees and the parents combine them (tree contraction) |

### 5.5 Range structures and tries

| # | Problem | A — 64 threads | B — stream / 100 TB | C — 100 machines |
|---|---|---|---|---|
| 17 | Count of smaller numbers after self | Merge sort that counts, for each element, how many smaller elements cross from the right; the merge levels parallelize | Fenwick over a bounded value range: O(range) memory regardless of n; read the file backwards in blocks | Range-partition by value; or external merge sort carrying counts (the external form of the parallel merge sort) |
| 18 | My calendar III | A lazy segment tree over compressed time under a lock, or a concurrent skip list of deltas with a separate max-maintenance pass | Bucket time (per minute or per hour) for bounded memory, at stated resolution | Partition by time range; split bookings that cross a boundary; global max = max of shard maxima |
| 19 | Word search II | Parallel over start cells: the trie is read-only, each thread uses its own visited marks | A huge dictionary as a compressed trie (DAWG or FST) memory-mapped from disk | Shard the dictionary by first letters; each machine searches the board with its subtrie; union the results |

### 5.6 Dynamic programming and hashing

| # | Problem | A — 64 threads | B — stream / 100 TB | C — 100 machines |
|---|---|---|---|---|
| 20 | LIS | No simple decomposition: the LIS of a concatenation isn't a function of the parts' LIS lengths. Run it sequentially (it is O(n log n) and memory-light) | Patience sorting is already one pass with O(answer) memory | Same problem as A: funnel the (ordered) stream through one machine, or answer a windowed variant per shard |
| 21 | Edit distance | Anti-diagonal wavefront: cells on one anti-diagonal are independent | Two rows: O(min(m, n)) memory; Hirschberg recovers the alignment in linear space | Banded edit distance when a threshold is known; block wavefront pipelined across machines |
| 22 | Regular expression matching | Many inputs against one compiled pattern in parallel | Compile to an NFA and simulate it with a set of states (Thompson): O(m) memory per stream, no backtracking, immune to ReDoS | One huge input: transition functions of chunks compose associatively, so chunks are processed in parallel and combined by a prefix composition |
| 23 | Burst balloons | All intervals of the same length are independent: parallelize per length | O(n²) memory: not a streaming problem (n ≤ 300 in the original) | Same per-length wavefront across machines; the communication usually costs more than it saves |
| 24 | Shortest path visiting all nodes | Level-synchronous BFS over (node, mask) states | 2ⁿ · n states: 20 nodes is 20 M states and fits; beyond that, say so and switch to heuristics (this is TSP on a graph metric) | Partition the state space by hash of (node, mask); BSP BFS |
| 25 | Maximum profit in job scheduling | Parallel sort; the DP is a sequential pass after it | Jobs sorted by end can be streamed: keep a monotone list of (end, best) and binary-search it | Partition by time; a job crossing a boundary belongs to the shard where it ends; the DP passes the best value at each boundary forward (a prefix computation over 100 values) |
| 26 | Longest duplicate substring | Hash all windows of length L in parallel into a concurrent map; verify matches | Suffix array + LCP built in external memory (the answer is the maximum LCP) | Shuffle windows by hash so equal hashes meet on one machine; one round per binary-search step |

### 5.7 Math

| # | Problem | A — 64 threads | B — stream / 100 TB | C — 100 machines |
|---|---|---|---|---|
| 29 | Median of two sorted arrays | O(log n) already; the general k-th of many sorted arrays is a binary search on value with parallel counting | Arrays on disk: O(log n) random reads | k-th smallest across 100 sorted shards: binary search on the value, one "count ≤ v" round per step |
| 30 | Max points on a line | Parallel over anchors; each thread its own direction map | O(n²) pairs can't be streamed exactly: RANSAC (random pairs as hypotheses, count support in one pass per batch) | Broadcast the points; distribute anchors; take the maximum. Or distribute RANSAC hypotheses |

---

## 6. Failure modes

| # | Failure | Problem(s) | Prevention |
|---|---|---|---|
| F1 | Recursion depth proportional to input size | 297, 124, 1192 | Explicit stacks; test a 10⁵-deep chain |
| F2 | Recursive destruction of `unique_ptr` trees | 297 (C++) | Arena ownership; iterative teardown |
| F3 | Skipping the parent vertex instead of the edge | 1192 | Track the arriving edge id (planted bug: 41% of trials fail) |
| F4 | Trusting hash equality | 1044 | Verify candidates; random base, large prime modulus |
| F5 | Floating-point slopes | 149 | gcd-normalized integer directions, canonical sign |
| F6 | 32-bit area, sum or distance | 84, 1235, 743, 124 | 64-bit accumulators |
| F7 | Off-by-one in a monotone predicate | 4 (`half`), 1235 (`<=`), 315 (strict), 300 (lower vs upper bound) | Write the invariant first; random oracle tests (the first three were planted in §4 and caught) |
| F8 | Signed `char` as an index | 76 (C++) | `unsigned char`, 256 entries |
| F9 | Unsigned underflow on empty input | 42 (C++) | Guard the empty case |
| F10 | Unvalidated parameters | 239 (k), 4 (both empty), 146 (capacity), 297 (tokens) | Validate at the API boundary and throw a typed exception |
| F11 | `minFreq` not maintained | 460 | It changes in exactly two places: insert (→ 1) and emptying its bucket (+1) |
| F12 | Missing a tie rule | 460 (LRU within frequency), 23 (equal heads), 269 (output order) | Make tie-breaking explicit and deterministic |
| F13 | Testing only the examples | All | A brute-force oracle on 1,000 small random instances; planted-bug runs to check the oracle |
| F14 | Exponential backtracking | 10 | DP or NFA simulation; never backtrack on user-supplied patterns |

---

## 7. Bar-raiser chains

<details><summary><b>Q1 · "Design an LFU cache with O(1) operations." (LC 460)</b></summary>

**Initial Prompt.** As stated; capacity up to 10⁴, 2·10⁵ calls.

**L5 Answer.** A heap keyed by (frequency, last use), giving O(log n) per operation, or a correct O(1) design that evicts an arbitrary key among the least frequent.

**Why L5 Stalls.** The first misses the stated bound; the second misses the specified tie rule (least recently used among the least frequent). Neither says how `minFreq` stays correct.

**L7 Answer.** "Three maps: key → (value, frequency, position in its bucket); frequency → keys in recency order; and the current minimum frequency. A touch moves a key from bucket f to f + 1 in O(1); if bucket f empties and f was the minimum, the minimum becomes f + 1. That's the only way it rises. An insert sets it to 1, so it never needs a search. Eviction takes the oldest key in the minimum bucket, which is exactly the least recently used among the least frequent. I checked it against a brute-force model on 1,000 random operation sequences; forgetting to advance `minFreq` crashes at the next eviction. At scale I'd swap exact counts for a frequency sketch with aging (TinyLFU), because exact per-key counts never shrink."
</details>

<details><summary><b>Q2 · "Running median, but over 100 machines." (LC 295)</b></summary>

**Initial Prompt.** Extension C of the two-heaps solution.

**L5 Answer.** "Each machine keeps two heaps; average their medians."

**Why L5 Stalls.** The median of medians is not the median: with 1, 2, 3 on one machine and 100, 200 on another, the true median is 3, not the average of 2 and 150.

**L7 Answer.** "Medians don't merge, counts do. Exact: binary-search on the value. Each round asks every machine 'how many of your values are ≤ v?', which is O(log n) locally if each keeps a sorted structure, and sums the answers. 32 rounds pin down a 32-bit median, each round being 100 small messages. Approximate and streaming: each machine keeps a KLL or t-digest sketch; sketches merge, and the merged sketch answers any quantile with a stated rank error. I'd ask which one the product needs: an exact median of a snapshot, or a p99 latency dashboard."
</details>

<details><summary><b>Q3 · "Find all bridges. The graph has a million vertices." (LC 1192)</b></summary>

**Initial Prompt.** The standard problem at full size.

**L5 Answer.** Recursive Tarjan low-link, skipping the parent vertex.

**Why L5 Stalls.** Two bugs at once. Recursion depth can reach 10⁶ on a path-like graph: a stack overflow. And skipping the parent *vertex* ignores a parallel edge back to the parent, so a doubled edge is reported as a bridge; that planted bug failed 41% of random trials.

**L7 Answer.** "Low-link with an explicit stack: per vertex, an iterator into its adjacency list and the id of the edge it arrived by. When I see that same edge id I skip it, but a second edge to the parent counts as a back edge, so parallel edges are handled. When a vertex finishes I propagate its low to the parent and test low[u] > tin[parent]. I tested it against remove-each-edge-and-count-components on 1,000 random multigraphs. If the graph doesn't fit in memory: keep a spanning forest and a second forest of the leftover edges. Their union, O(n) edges, has exactly the same bridges, so I can stream the edges once and solve the small graph."
</details>

<details><summary><b>Q4 · "Serialize a binary tree." (LC 297)</b></summary>

**Initial Prompt.** As stated.

**L5 Answer.** Recursive preorder with null markers, recursive parse.

**Why L5 Stalls.** Correct for balanced trees; a degenerate tree with 10⁵ nodes overflows the stack in both directions. No input validation on deserialize.

**L7 Answer.** "Preorder with `#` for null. Serialize with an explicit stack: pop, emit, push right then left. Deserialize with a stack of nodes still waiting for a child plus a flag for which side, so it's one pass and O(height) memory. I tested a 100,000-node chain round trip in both languages. In C++ I also changed ownership: with `unique_ptr` children the *destructor* recurses, so the nodes live in an arena and destruction is a loop. The parser validates every token (`from_chars` must consume it fully) and rejects tokens after the tree is complete. For a public format I'd add a version and a length prefix."
</details>

<details><summary><b>Q5 · "Longest duplicate substring, n = 3·10⁴." (LC 1044)</b></summary>

**Initial Prompt.** As stated.

**L5 Answer.** Binary search on the length plus a rolling hash modulo 10⁹ + 7 with base 31, returning the first hash match.

**Why L5 Stalls.** With 3·10⁴ windows and a 30-bit modulus, the birthday bound makes a false match likely on each check. Base 31 and fixed moduli are attackable, and unverified matches make the answer wrong, not slow.

**L7 Answer.** "Binary search on L works because a duplicate of length L contains one of length L − 1. For each L, hash every window modulo the Mersenne prime 2⁶¹ − 1 with a random base, using 128-bit multiplication. Then the crucial part: on a hash match, compare the substrings directly. That makes the result exact; luck only affects the running time. I planted the bug of skipping that comparison, and 1,000 random tests still passed, which is precisely why it has to be argued rather than tested. Two specific substrings collide with probability under L/2⁶¹, but a fixed base or a 2⁶⁴ modulus can be attacked deliberately, e.g. with Thue–Morse strings. A suffix array with LCP gives a deterministic O(n log n) alternative."
</details>

<details><summary><b>Q6 · "Max points on a line." (LC 149)</b></summary>

**Initial Prompt.** Up to 300 points, integer coordinates.

**L5 Answer.** For each pair, compute the slope as `double`, count in a hash map; special-case vertical lines.

**Why L5 Stalls.** `double` slopes misgroup: 1/3 isn't exact, −0.0 and 0.0 hash differently in Java's `Double`, and large coordinates lose precision. Duplicated points need their own handling.

**L7 Answer.** "For each anchor, reduce the direction to every other point by gcd and fix a canonical sign (dx > 0, or dx = 0 and dy > 0), so (1, 2) and (−1, −2) map to the same key. Duplicates of the anchor are counted separately and added to the best direction. No floating point at all. I planted the bug of dropping the canonical sign and it survived 93% of random trials, so this is exactly the kind of bug hand-written examples miss. For millions of points the exact O(n²) is out; I'd use RANSAC: sample point pairs as candidate lines, count support in a pass, keep the best."
</details>

<details><summary><b>Q7 · "Median of two sorted arrays in O(log(m + n))." (LC 4)</b></summary>

**Initial Prompt.** As stated.

**L5 Answer.** A binary search that works on the examples but uses `half = (m + n) / 2`, or doesn't search the shorter array.

**Why L5 Stalls.** The off-by-one fails on odd total lengths (planted: 44% of trials failed). Searching the longer array lets j go negative. Two empty arrays loop forever or return garbage.

**L7 Answer.** "Binary-search the cut i in the shorter array, with j = (m + n + 1) / 2 − i in the other, so the left side holds the extra element when the total is odd. The cut is right when aL ≤ bR and bL ≤ aR, using sentinels at the ends. If aL > bR, move left; otherwise move right. O(log min(m, n)). I reject two empty arrays explicitly. The generalization interviewers ask next is the k-th smallest across 100 sorted shards: binary-search on the value, and each round asks every shard for its count ≤ v."
</details>

<details><summary><b>Q8 · "Word ladder over a 10-million-word dictionary." (LC 127)</b></summary>

**Initial Prompt.** Scale-up of the standard problem.

**L5 Answer.** BFS, checking every dictionary word for a one-letter difference from the current word.

**Why L5 Stalls.** That's O(N) per dequeued word, O(N² · L) overall: 10¹⁴ comparisons at N = 10⁷.

**L7 Answer.** "Bucket words by wildcard pattern: 'hot' goes into '*ot', 'h*t' and 'ho*'. Neighbours are words sharing a bucket, so building is O(N · L²) and BFS touches only real edges. I'd run it bidirectionally, expanding the smaller frontier, which shrinks the explored set from b^d to about 2·b^(d/2). At 10⁷ words the buckets are an external sort on (pattern, word), and the BFS becomes the BSP BFS from File 1, with words partitioned by pattern hash."
</details>

<details><summary><b>Q9 · "Regular expression matching with . and *." (LC 10)</b></summary>

**Initial Prompt.** As stated; then "this runs on user-supplied patterns".

**L5 Answer.** Recursive backtracking, possibly memoized.

**Why L5 Stalls.** Unmemoized, `a*a*a*a*a*b` against `aaaaaaaaaaaaaaaaaaaa` is exponential; that's a ReDoS vector when patterns or inputs come from users.

**L7 Answer.** "Bottom-up DP: dp[i][j] says s[i..] matches p[j..]. For `x*`, either skip the pair (dp[i][j + 2]) or, if x matches s[i], consume one character and stay (dp[i + 1][j]). O(mn) time, guaranteed. The planted bug, making `x*` require at least one x, failed 11% of random trials: every instance where some `x*` had to match nothing. For production matching I'd compile to an NFA and simulate it with a set of states (Thompson's construction), which is linear in the input for a fixed pattern, needs no backtracking at all, and is what RE2 and Rust's regex crate do."
</details>

<details><summary><b>Q10 · "How do you know your solution is right?"</b></summary>

**Initial Prompt.** Asked after any of the 30.

**L5 Answer.** "It passes the examples, and I traced through an edge case."

**Why L5 Stalls.** Examples are chosen to illustrate, not to break. The bugs in this file's mutation table survived 32–96% of *random* trials. Hand-picked examples are much weaker than that.

**L7 Answer.** "Three things. The invariant, stated before the code, so each line can be checked against it. A brute-force oracle that shares no logic with the solution, run on a thousand small random instances: small, so duplicates, empties and ties show up constantly. I've also checked that the oracle can fail, by planting known bugs: here eight of nine were caught. And for the property random testing can't reach, like hash collisions, an argument in the code itself: verify every match. In an interview I'd write the oracle in two minutes and say how I'd run it, because that's what I do on the job."
</details>

---

## 8. Checklist

* [ ] State the invariant in one sentence before writing code.
* [ ] Derive the complexity from the invariant.
* [ ] Walk the edge cases the invariant implies: empty, one element, all equal, k = n, ties, overflow.
* [ ] No recursion whose depth grows with the input; C++ trees owned by an arena or torn down iteratively.
* [ ] 64-bit accumulators for sums, products and distances.
* [ ] Validate parameters at the API boundary; typed exceptions.
* [ ] Deterministic tie-breaking wherever order is observable.
* [ ] No floating point where exact integer arithmetic works (slopes, ratios).
* [ ] Hashes: random base, large prime modulus, verify every match.
* [ ] Test with an independent brute-force oracle on many small random instances; check the oracle with a planted bug.
* [ ] Extension A: find the shared invariant; stripe it, make it per-thread and mergeable, or lock it.
* [ ] Extension B: what does the invariant need to remember? Bound it, or replace it with a sketch.
* [ ] Extension C: which partial results merge (counts, maxima, sketches, sorted runs)? Partition so the rest stays local.

---

## 9. References

**Problems** (links use LeetCode's problem slugs; the pages return HTTP 403 to scripts, so they are not machine-checked):

* [146 LRU Cache](https://leetcode.com/problems/lru-cache/) · [460 LFU Cache](https://leetcode.com/problems/lfu-cache/) · [295 Find Median from Data Stream](https://leetcode.com/problems/find-median-from-data-stream/) · [362 Design Hit Counter](https://leetcode.com/problems/design-hit-counter/) · [981 Time Based Key-Value Store](https://leetcode.com/problems/time-based-key-value-store/)
* [239 Sliding Window Maximum](https://leetcode.com/problems/sliding-window-maximum/) · [76 Minimum Window Substring](https://leetcode.com/problems/minimum-window-substring/) · [42 Trapping Rain Water](https://leetcode.com/problems/trapping-rain-water/) · [84 Largest Rectangle in Histogram](https://leetcode.com/problems/largest-rectangle-in-histogram/) · [23 Merge k Sorted Lists](https://leetcode.com/problems/merge-k-sorted-lists/)
* [127 Word Ladder](https://leetcode.com/problems/word-ladder/) · [210 Course Schedule II](https://leetcode.com/problems/course-schedule-ii/) · [743 Network Delay Time](https://leetcode.com/problems/network-delay-time/) · [1192 Critical Connections in a Network](https://leetcode.com/problems/critical-connections-in-a-network/) · [305 Number of Islands II](https://leetcode.com/problems/number-of-islands-ii/) · [269 Alien Dictionary](https://leetcode.com/problems/alien-dictionary/)
* [297 Serialize and Deserialize Binary Tree](https://leetcode.com/problems/serialize-and-deserialize-binary-tree/) · [124 Binary Tree Maximum Path Sum](https://leetcode.com/problems/binary-tree-maximum-path-sum/)
* [315 Count of Smaller Numbers After Self](https://leetcode.com/problems/count-of-smaller-numbers-after-self/) · [732 My Calendar III](https://leetcode.com/problems/my-calendar-iii/) · [212 Word Search II](https://leetcode.com/problems/word-search-ii/)
* [300 Longest Increasing Subsequence](https://leetcode.com/problems/longest-increasing-subsequence/) · [72 Edit Distance](https://leetcode.com/problems/edit-distance/) · [10 Regular Expression Matching](https://leetcode.com/problems/regular-expression-matching/) · [312 Burst Balloons](https://leetcode.com/problems/burst-balloons/) · [847 Shortest Path Visiting All Nodes](https://leetcode.com/problems/shortest-path-visiting-all-nodes/) · [1235 Maximum Profit in Job Scheduling](https://leetcode.com/problems/maximum-profit-in-job-scheduling/) · [1044 Longest Duplicate Substring](https://leetcode.com/problems/longest-duplicate-substring/)
* [4 Median of Two Sorted Arrays](https://leetcode.com/problems/median-of-two-sorted-arrays/) · [149 Max Points on a Line](https://leetcode.com/problems/max-points-on-a-line/)

**Algorithms and papers:**

* A. B. Kahn, *Topological Sorting of Large Networks*, CACM 5(11), 1962 — DOI 10.1145/368996.369025
* R. Tarjan, *Depth-First Search and Linear Graph Algorithms*, SIAM J. Comput. 1(2), 1972 — DOI 10.1137/0201010
* E. W. Dijkstra, *A Note on Two Problems in Connexion with Graphs*, Numerische Mathematik 1, 1959 — DOI 10.1007/BF01386390
* P. M. Fenwick, *A New Data Structure for Cumulative Frequency Tables*, Software: Practice and Experience 24(3), 1994 — DOI 10.1002/spe.4380240306
* R. M. Karp, M. O. Rabin, *Efficient Randomized Pattern-Matching Algorithms*, IBM J. Res. Dev. 31(2), 1987 — DOI 10.1147/rd.312.0249
* K. Thompson, *Regular Expression Search Algorithm*, CACM 11(6), 1968 — DOI 10.1145/363347.363387
* D. S. Hirschberg, *A Linear Space Algorithm for Computing Maximal Common Subsequences*, CACM 18(6), 1975 — DOI 10.1145/360825.360861
* Z. Karnin, K. Lang, E. Liberty, *Optimal Quantile Approximation in Streams*, FOCS 2016 — DOI 10.1109/FOCS.2016.17
* M. A. Fischler, R. C. Bolles, *Random Sample Consensus*, CACM 24(6), 1981 — DOI 10.1145/358669.358692
* R. Cox, *Regular Expression Matching Can Be Simple And Fast* — <https://swtch.com/~rsc/regexp/regexp1.html>
* dacin21, *Anti-hash tests and how to beat them* (Codeforces) — <https://codeforces.com/topic/60786/en2>

*Folder 07:* [01 — External merge sort, streaming top-K, sharded BFS](01-k-way-external-merge-sort-streaming-top-k-and-sharded-bfs-graph-traversal.md) · [02 — Turning single-threaded DSA into thread-safe concurrent structures](02-turning-single-threaded-dsa-into-thread-safe-concurrent-structures.md)
