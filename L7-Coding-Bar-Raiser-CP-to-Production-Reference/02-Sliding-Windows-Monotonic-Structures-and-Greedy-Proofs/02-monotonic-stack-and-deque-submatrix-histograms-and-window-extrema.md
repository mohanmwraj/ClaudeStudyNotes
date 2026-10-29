# Monotonic Stack and Deque: Submatrix Histograms and Window Extrema

> **Folder 02 · File 2 of 3** — "every index is pushed once and popped once", made precise; the tie-breaking rule that decides correctness; and the two-stacks queue that generalizes window extrema to any associative operation.
> **Languages:** Java 21 (`--release 21 -Xlint:all -Werror`, JDK 25.0.4.1) and C++23 (GCC 16.2 and Clang 21.1, `-O2`, warnings as errors).

| Listing | File | What it proves |
|---|---|---|
| 2.3 | `MonotonicStructures.java` | LC 84 with an `int` area silently returns 2×10⁹ for 3×10⁹; LC 85; LC 239 with a ring deque and `ArrayDeque<Integer>`; LC 907's tie bug shrunk to `[1, 1]`; a two-stacks aggregate queue for gcd and a **non-commutative** concatenation; a 10 M-element timing |
| 2.4 | `monotonic_structures.cpp` | The same; the overflowing contest version is evaluated only in `static_assert` and rejected by both compilers (`-DAREA_OVERFLOW`); the two-stacks queue beats both deques |

**Verification.** Both listings were extracted from this file, compiled and run. Everything is **Output (verified)** except the last line of each (**one measured run**). The expected-failure build is re-checked by the gate.

---

## 0. Orientation

Monotonic structures are the most "contest-shaped" tool in this folder: short, fast, easy to get subtly wrong. Interviewers like them because three questions separate levels quickly:

1. *Why is it O(n)?* (amortization)
2. *What does the stack contain?* (the invariant)
3. *What happens with equal values?* (the tie rule)

| Contest habit | What breaks | L7 replacement |
|---|---|---|
| `int area = h * w` | Heights up to 10⁹ × widths up to 10⁵ overflow 32 bits, silently | 64-bit area, bound stated |
| `<` on both sides (or `<=` on both) when counting spans | Subarrays with repeated minima counted zero times (or twice) | Break ties asymmetrically: strict on one side, non-strict on the other, written in the contract |
| `ArrayDeque<Integer>` / `std::deque` as "the" deque | Boxing, chunked storage, unpredictable branches | Index ring buffer of capacity `w + 1`, or the two-stacks queue, **measured** |
| A different hand-written structure per aggregate | Max uses a deque, gcd can't, matrix products can't | Two-stacks queue: any associative operation, amortized O(1) |

---

## 1. First principles

### 1.1 The candidate-set invariant

A monotonic stack maintains the set of indices that **can still be the answer** for some future query, and that set is always sorted by value. For "next smaller element" or "largest rectangle", index `j` stays on the stack while no lower bar has appeared to its right. The moment a lower bar arrives at `i`, `j`'s answer is known: its rectangle extends from the previous stack entry, the nearest lower bar on the left, to `i`. Then `j` leaves forever.

**Amortization:** each index is pushed once and popped at most once. The inner `while` therefore runs at most `n` times **in total**, not per iteration: `2n` stack operations, `O(n)`. That sentence is the complexity argument.

### 1.2 The monotonic deque

For window extrema, a deque holds indices in the current window whose values are **strictly decreasing** from front to back. When a new value arrives, every element at the back that is ≤ it is **dominated**. It is older and no larger, so it can never be the maximum of any future window, and it is removed. The front is the window maximum; it leaves when it falls out of the window. Each index is pushed and popped at most once, so the cost is amortized O(1) per element. The capacity needed is the window size `w` plus one: during a push the deque momentarily holds the new element before the expired front is evicted.

### 1.3 Ties are part of the algorithm

"Sum over all subarrays of their minimum" (LeetCode 907) assigns every subarray to the index that is its minimum. With repeated values, a subarray has several minimum positions and must be assigned to **exactly one**. The rule: extend left past elements **strictly greater** (stop at an equal one), extend right past elements **greater or equal** (pass equal ones). Using the same comparison on both sides either assigns the subarray to nobody (stop at equals on both sides) or to every copy (pass equals on both sides). The same asymmetric tie rule appears in "number of subarrays where X is the max", in histogram variants and in stock-span problems. **Writing it in a comment is an L7 signal.**

### 1.4 The two-stacks queue: window aggregates for any monoid

A monotonic deque only works for max/min, because "dominated" needs an order. For any **associative** operation `⊕` with identity (sum, gcd, bitwise OR, matrix product, function composition, string concatenation), use two stacks:

* the **back** stack receives pushes and keeps one running aggregate `B = b₁ ⊕ … ⊕ b_k`;
* the **front** stack serves pops, and each entry stores the aggregate of itself and everything newer within the front stack (a suffix aggregate);
* when the front is empty and a pop arrives, the back is flipped into the front (newest first, so the oldest ends on top), computing suffix aggregates on the way.

The query is `front.top.aggregate ⊕ B`. Each element is moved once, so the cost is amortized O(1) per operation. **Associativity is the only requirement, and commutativity is not needed:** the order of operands is preserved, which is why the listing tests it with string concatenation. This is the "two-stacks" algorithm from the sliding-window-aggregation literature (Tangwongsan, Hirzel and Schneider). Stream processors use variants of it that are worst-case O(1).

---

## 2. The listings

### 2.1 Listing 2.3 — Java

```java
// MonotonicStructures.java - monotonic stack/deque and the two-stacks aggregate queue: O(n) because each index moves twice.
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.NoSuchElementException;
import java.util.function.BinaryOperator;

public final class MonotonicStructures {

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
        int[] array(int maxLen, int lo, int hi) {
            int[] a = new int[nextInt(maxLen + 1)];
            for (int i = 0; i < a.length; i++) a[i] = lo + nextInt(hi - lo + 1);
            return a;
        }
    }

    // ===================================================================== 1. LC 84 largest rectangle in a histogram
    static int cpLargestRectangle(int[] h) {  // contest habit: int area
        int n = h.length, best = 0, top = 0;
        int[] st = new int[n + 1];
        for (int i = 0; i <= n; i++) {
            int cur = i == n ? 0 : h[i];
            while (top > 0 && h[st[top - 1]] >= cur) {
                int height = h[st[--top]], width = top == 0 ? i : i - st[top - 1] - 1;
                best = Math.max(best, height * width);
            }
            st[top++] = i;
        }
        return best;
    }

    /**
     * Stack invariant: indices with strictly increasing heights. When bar j is popped by a lower bar at i, the
     * previous stack entry is the nearest lower bar on the left, so j's maximal rectangle spans exactly (prev, i).
     * Every index is pushed once and popped once: O(n). Area in long: 2^31 x 10^5 needs 47 bits.
     */
    static long largestRectangle(int[] h) {
        int n = h.length, top = 0;
        int[] st = new int[n + 1];
        long best = 0;
        for (int i = 0; i <= n; i++) {
            int cur = i == n ? 0 : h[i];
            if (cur < 0) throw new IllegalArgumentException("negative height at " + i);
            while (top > 0 && h[st[top - 1]] >= cur) {
                long height = h[st[--top]], width = top == 0 ? i : i - st[top - 1] - 1;
                best = Math.max(best, height * width);
            }
            st[top++] = i;
        }
        return best;
    }

    static long largestRectangleOracle(int[] h) {
        long best = 0;
        for (int i = 0; i < h.length; i++) {
            long min = Long.MAX_VALUE;
            for (int j = i; j < h.length; j++) best = Math.max(best, (min = Math.min(min, h[j])) * (j - i + 1));
        }
        return best;
    }

    // ===================================================================== 2. LC 85 maximal rectangle of 1s
    static long maximalRectangle(int[][] grid) {  // one histogram per row: O(rows x cols)
        if (grid.length == 0) return 0;
        int[] heights = new int[grid[0].length];
        long best = 0;
        for (int[] row : grid) {
            for (int c = 0; c < row.length; c++) heights[c] = row[c] == 1 ? heights[c] + 1 : 0;
            best = Math.max(best, largestRectangle(heights));
        }
        return best;
    }

    static long maximalRectangleOracle(int[][] g) {
        long best = 0;
        int rows = g.length, cols = rows == 0 ? 0 : g[0].length;
        for (int r1 = 0; r1 < rows; r1++)
            for (int r2 = r1; r2 < rows; r2++)
                for (int c1 = 0; c1 < cols; c1++)
                    for (int c2 = c1; c2 < cols; c2++) {
                        boolean all = true;
                        for (int r = r1; r <= r2 && all; r++) for (int c = c1; c <= c2 && all; c++) all = g[r][c] == 1;
                        if (all) best = Math.max(best, (long) (r2 - r1 + 1) * (c2 - c1 + 1));
                    }
        return best;
    }

    // ===================================================================== 3. LC 239 sliding window maximum
    /** Deque invariant: indices in the window with strictly decreasing values; the front is the window maximum. */
    static final class WindowMax {
        private final long[] idx;  // absolute stream positions, so eviction is a plain comparison
        private final int[] val;
        private final int cap, w;  // a push momentarily holds w + 1 entries before the front is evicted
        private int head, size;
        private long seen;

        WindowMax(int w) {
            if (w <= 0) throw new IllegalArgumentException("w must be > 0");
            this.w = w;
            this.cap = w + 1;
            idx = new long[cap];
            val = new int[cap];
        }

        private int at(int offset) {  // ring index without %: a division per access is a hidden constant
            int i = head + offset;
            return i >= cap ? i - cap : i;
        }

        /** Push the next stream value; true when a full window is available via max(). O(1) amortized, O(w) memory. */
        boolean push(int v) {
            while (size > 0 && val[at(size - 1)] <= v) size--;  // dominated: can never be a maximum again
            int slot = at(size);
            idx[slot] = seen;
            val[slot] = v;
            size++;
            if (idx[head] <= seen - w) {
                head = head + 1 == cap ? 0 : head + 1;
                size--;
            }
            seen++;
            return seen >= w;
        }

        int max() { return val[head]; }
    }

    static int[] windowMaxOracle(int[] a, int w) {
        int[] out = new int[Math.max(0, a.length - w + 1)];
        for (int i = 0; i + w <= a.length; i++) out[i] = Arrays.stream(a, i, i + w).max().orElseThrow();
        return out;
    }

    static int[] windowMax(int[] a, int w) {
        WindowMax m = new WindowMax(w);
        int[] out = new int[Math.max(0, a.length - w + 1)];
        int k = 0;
        for (int v : a) if (m.push(v)) out[k++] = m.max();
        return out;
    }

    static int[] windowMaxBoxed(int[] a, int w) {  // the textbook ArrayDeque<Integer> version: same algorithm, boxed
        ArrayDeque<Integer> dq = new ArrayDeque<>();
        int[] out = new int[Math.max(0, a.length - w + 1)];
        for (int i = 0; i < a.length; i++) {
            while (!dq.isEmpty() && a[dq.peekLast()] <= a[i]) dq.pollLast();
            dq.addLast(i);
            if (dq.peekFirst() <= i - w) dq.pollFirst();
            if (i >= w - 1) out[i - w + 1] = a[dq.peekFirst()];
        }
        return out;
    }

    // ===================================================================== 4. LC 907 sum of subarray minimums
    /** Contest bug: stop at an EQUAL element on both sides, so a subarray whose minimum occurs twice is counted by
     *  nobody (the mirror habit, passing equals on both sides, counts it twice). */
    static long cpSumSubarrayMins(int[] a) {
        int n = a.length;
        long sum = 0;
        for (int i = 0; i < n; i++) {
            int l = i, r = i;
            while (l > 0 && a[l - 1] > a[i]) l--;
            while (r < n - 1 && a[r + 1] > a[i]) r++;
            sum += (long) a[i] * (i - l + 1) * (r - i + 1);
        }
        return sum;
    }

    /** Tie-break once: an equal element to the LEFT stops the span, to the RIGHT it does not. Two monotonic passes. */
    static long sumSubarrayMins(int[] a) {
        int n = a.length, top = 0;
        int[] left = new int[n], right = new int[n], st = new int[n];
        for (int i = 0; i < n; i++) {
            while (top > 0 && a[st[top - 1]] > a[i]) top--;                // previous element <= a[i] stops us
            left[i] = top == 0 ? i + 1 : i - st[top - 1];
            st[top++] = i;
        }
        top = 0;
        for (int i = n - 1; i >= 0; i--) {
            while (top > 0 && a[st[top - 1]] >= a[i]) top--;               // next element < a[i] stops us
            right[i] = top == 0 ? n - i : st[top - 1] - i;
            st[top++] = i;
        }
        long sum = 0;
        for (int i = 0; i < n; i++) sum += (long) a[i] * left[i] * right[i];
        return sum;
    }

    static long sumSubarrayMinsOracle(int[] a) {
        long sum = 0;
        for (int i = 0; i < a.length; i++) {
            int min = Integer.MAX_VALUE;
            for (int j = i; j < a.length; j++) sum += (min = Math.min(min, a[j]));
        }
        return sum;
    }

    // ===================================================================== 5. two-stacks aggregate queue (any monoid)
    /**
     * FIFO queue answering "aggregate of everything inside" in O(1) amortized for ANY associative op -- max, min, gcd,
     * sum, matrix product, even non-commutative ones. The front stack stores suffix aggregates (oldest on top).
     */
    static final class AggQueue<T> {
        private final BinaryOperator<T> op;
        private final T identity;
        private final List<T> front = new ArrayList<>(), frontAgg = new ArrayList<>();
        private final List<T> back = new ArrayList<>();
        private T backAgg;

        AggQueue(BinaryOperator<T> op, T identity) {
            this.op = op;
            this.identity = identity;
            this.backAgg = identity;
        }

        void push(T v) {
            back.add(v);
            backAgg = op.apply(backAgg, v);
        }

        T pop() {
            if (front.isEmpty()) {
                for (int i = back.size() - 1; i >= 0; i--) {   // newest first, so the oldest ends on top
                    T v = back.get(i);
                    frontAgg.add(frontAgg.isEmpty() ? v : op.apply(v, frontAgg.get(frontAgg.size() - 1)));
                    front.add(v);
                }
                back.clear();
                backAgg = identity;
            }
            if (front.isEmpty()) throw new NoSuchElementException("empty");
            frontAgg.remove(frontAgg.size() - 1);
            return front.remove(front.size() - 1);
        }

        T aggregate() { return op.apply(frontAgg.isEmpty() ? identity : frontAgg.get(frontAgg.size() - 1), backAgg); }
    }

    static int gcd(int a, int b) { return b == 0 ? Math.abs(a) : gcd(b, a % b); }

    public static void main(String[] args) {
        int[] big = {1_000_000_000, 1_000_000_000, 1_000_000_000};
        System.out.printf("1. LC 84, heights %s: contest int area %,d | long area %,d%n", Arrays.toString(big),
                cpLargestRectangle(big), largestRectangle(big));
        SplitMix64 r = new SplitMix64(31);
        int trials = 20_000, okHist = 0, okRect = 0, okMax = 0, okMins = 0, cpMins = 0, okAgg = 0;
        int[] firstBad = null;
        for (int t = 0; t < trials; t++) {
            int[] h = r.array(10, 0, 6);
            okHist += largestRectangle(h) == largestRectangleOracle(h) ? 1 : 0;
            int rows = r.nextInt(5), cols = 1 + r.nextInt(5);
            int[][] g = new int[rows][cols];
            for (int[] row : g) for (int c = 0; c < cols; c++) row[c] = r.nextInt(3) == 0 ? 0 : 1;
            okRect += maximalRectangle(g) == maximalRectangleOracle(g) ? 1 : 0;
            int[] a = r.array(12, 1, 4);
            int w = 1 + r.nextInt(4);
            okMax += Arrays.equals(windowMax(a, w), windowMaxOracle(a, w))
                    && Arrays.equals(windowMaxBoxed(a, w), windowMaxOracle(a, w)) ? 1 : 0;
            long want = sumSubarrayMinsOracle(a);
            okMins += sumSubarrayMins(a) == want ? 1 : 0;
            if (cpSumSubarrayMins(a) == want) cpMins++;
            else if (firstBad == null || a.length < firstBad.length) firstBad = a;
            AggQueue<Integer> gq = new AggQueue<>(MonotonicStructures::gcd, 0);
            AggQueue<String> sq = new AggQueue<>(String::concat, "");
            boolean ok = true;
            for (int i = 0; i < a.length; i++) {
                gq.push(a[i] * 6);
                sq.push(Character.toString('a' + a[i]));
                if (i >= w) { gq.pop(); sq.pop(); }
                int lo = Math.max(0, i - w + 1), g2 = 0;
                StringBuilder sb = new StringBuilder();
                for (int j = lo; j <= i; j++) { g2 = gcd(g2, a[j] * 6); sb.append((char) ('a' + a[j])); }
                ok &= gq.aggregate() == g2 && sq.aggregate().equals(sb.toString());
            }
            okAgg += ok ? 1 : 0;
        }
        System.out.printf("   LC 84 monotonic stack vs O(n^2) oracle: %d/%d%n", okHist, trials);
        System.out.printf("2. LC 85 maximal rectangle vs brute force: %d/%d%n", okRect, trials);
        System.out.printf("3. LC 239 window max (int ring deque and ArrayDeque<Integer>) vs oracle: %d/%d%n", okMax, trials);
        System.out.printf("4. LC 907 sum of subarray minimums: tie-broken stacks %d/%d | contest strict-both-sides %d/%d,"
                + " smallest failure %s -> %d vs truth %d%n", okMins, trials, cpMins, trials, Arrays.toString(firstBad),
                cpSumSubarrayMins(firstBad), sumSubarrayMinsOracle(firstBad));
        System.out.printf("5. two-stacks queue, gcd and NON-commutative concat over sliding windows vs brute: %d/%d%n", okAgg, trials);

        int n = 10_000_000, w = 1_000;
        int[] data = new int[n];
        for (int i = 0; i < n; i++) data[i] = (int) (r.next() >>> 40);
        for (int rep = 0; rep < 2; rep++) {  // second round reported: first pays for JIT
            long t0 = System.nanoTime();
            int[] a1 = windowMax(data, w);
            long t1 = System.nanoTime();
            int[] a2 = windowMaxBoxed(data, w);
            long t2 = System.nanoTime();
            AggQueue<Integer> q = new AggQueue<>(Math::max, Integer.MIN_VALUE);
            long check = 0;
            for (int i = 0; i < n; i++) {
                q.push(data[i]);
                if (i >= w) q.pop();
                if (i >= w - 1) check += q.aggregate() == a1[i - w + 1] ? 0 : 1;
            }
            long t3 = System.nanoTime();
            if (rep == 1) {
                System.out.printf("B. window max, n=%,d, w=%,d (one measured run): int ring deque %d ms (O(w) memory) |"
                        + " ArrayDeque<Integer> %d ms | AggQueue<Integer> %d ms | all agree: %b%n", n, w,
                        (t1 - t0) / 1_000_000, (t2 - t1) / 1_000_000, (t3 - t2) / 1_000_000, Arrays.equals(a1, a2) && check == 0);
            }
        }
    }
}
```

**Output (verified; the last line is one measured run):**

```text
1. LC 84, heights [1000000000, 1000000000, 1000000000]: contest int area 2,000,000,000 | long area 3,000,000,000
   LC 84 monotonic stack vs O(n^2) oracle: 20000/20000
2. LC 85 maximal rectangle vs brute force: 20000/20000
3. LC 239 window max (int ring deque and ArrayDeque<Integer>) vs oracle: 20000/20000
4. LC 907 sum of subarray minimums: tie-broken stacks 20000/20000 | contest strict-both-sides 5580/20000, smallest failure [1, 1] -> 2 vs truth 3
5. two-stacks queue, gcd and NON-commutative concat over sliding windows vs brute: 20000/20000
B. window max, n=10,000,000, w=1,000 (one measured run): int ring deque 90 ms (O(w) memory) | ArrayDeque<Integer> 169 ms | AggQueue<Integer> 307 ms | all agree: true
```

### 2.2 Listing 2.4 — C++23

```cpp
// monotonic_structures.cpp - monotonic stack/deque and the two-stacks aggregate queue: O(n) because each index moves twice.
#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <deque>
#include <format>
#include <functional>
#include <limits>
#include <numeric>
#include <print>
#include <span>
#include <stdexcept>
#include <string>
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
    Vec array(int max_len, int lo, int hi) {
        Vec a(static_cast<std::size_t>(next_int(max_len + 1)));
        for (int& x : a) x = lo + next_int(hi - lo + 1);
        return a;
    }
};

// ======================================================================= 1. LC 84 largest rectangle in a histogram
// Contest habit: int area. Signed overflow is UB, so it is only ever evaluated at compile time (-DAREA_OVERFLOW).
constexpr int cp_largest_rectangle(std::span<const int> h) {
    int n = static_cast<int>(h.size()), best = 0, top = 0;
    std::vector<int> st(h.size() + 1);
    for (int i = 0; i <= n; i++) {
        int cur = i == n ? 0 : h[static_cast<std::size_t>(i)];
        while (top > 0 && h[static_cast<std::size_t>(st[static_cast<std::size_t>(top - 1)])] >= cur) {
            int height = h[static_cast<std::size_t>(st[static_cast<std::size_t>(--top)])];
            int width = top == 0 ? i : i - st[static_cast<std::size_t>(top - 1)] - 1;
            best = std::max(best, height * width);
        }
        st[static_cast<std::size_t>(top++)] = i;
    }
    return best;
}
static_assert(cp_largest_rectangle(std::array{2, 1, 5, 6, 2, 3}) == 10);  // the LeetCode sample passes ...
#ifdef AREA_OVERFLOW
static_assert(cp_largest_rectangle(std::array{1'000'000'000, 1'000'000'000, 1'000'000'000}) > 0);  // ... this does not compile
#endif

// Stack invariant: indices with strictly increasing heights. When bar j is popped by a lower bar at i, the previous
// stack entry is the nearest lower bar on the left, so j's maximal rectangle spans exactly (prev, i).
// Every index is pushed once and popped once: O(n). Area in int64: 2^31 x 10^5 needs 47 bits.
std::int64_t largest_rectangle(std::span<const int> h) {
    std::vector<std::size_t> st;
    st.reserve(h.size());
    std::int64_t best = 0;
    for (std::size_t i = 0; i <= h.size(); ++i) {
        int cur = i == h.size() ? 0 : h[i];
        if (cur < 0) throw std::invalid_argument(std::format("negative height at {}", i));
        while (!st.empty() && h[st.back()] >= cur) {
            std::int64_t height = h[st.back()];
            st.pop_back();
            auto width = static_cast<std::int64_t>(st.empty() ? i : i - st.back() - 1);
            best = std::max(best, height * width);
        }
        st.push_back(i);
    }
    return best;
}

std::int64_t largest_rectangle_oracle(std::span<const int> h) {
    std::int64_t best = 0;
    for (std::size_t i = 0; i < h.size(); ++i) {
        std::int64_t mn = std::numeric_limits<std::int64_t>::max();
        for (std::size_t j = i; j < h.size(); ++j)
            best = std::max(best, (mn = std::min<std::int64_t>(mn, h[j])) * static_cast<std::int64_t>(j - i + 1));
    }
    return best;
}

// ======================================================================= 2. LC 85 maximal rectangle of 1s
using Grid = std::vector<Vec>;
std::int64_t maximal_rectangle(const Grid& g) {  // one histogram per row: O(rows x cols)
    if (g.empty()) return 0;
    Vec heights(g[0].size());
    std::int64_t best = 0;
    for (const auto& row : g) {
        for (std::size_t c = 0; c < row.size(); ++c) heights[c] = row[c] == 1 ? heights[c] + 1 : 0;
        best = std::max(best, largest_rectangle(heights));
    }
    return best;
}

std::int64_t maximal_rectangle_oracle(const Grid& g) {
    std::int64_t best = 0;
    std::size_t rows = g.size(), cols = rows == 0 ? 0 : g[0].size();
    for (std::size_t r1 = 0; r1 < rows; ++r1)
        for (std::size_t r2 = r1; r2 < rows; ++r2)
            for (std::size_t c1 = 0; c1 < cols; ++c1)
                for (std::size_t c2 = c1; c2 < cols; ++c2) {
                    bool all = true;
                    for (std::size_t r = r1; r <= r2 && all; ++r)
                        for (std::size_t c = c1; c <= c2 && all; ++c) all = g[r][c] == 1;
                    if (all) best = std::max(best, static_cast<std::int64_t>((r2 - r1 + 1) * (c2 - c1 + 1)));
                }
    return best;
}

// ======================================================================= 3. LC 239 sliding window maximum
// Deque invariant: indices in the window with strictly decreasing values; the front is the window maximum.
class WindowMax {
public:
    explicit WindowMax(std::size_t w) : w_(w), cap_(w + 1), idx_(cap_), val_(cap_) {
        if (w == 0) throw std::invalid_argument("w must be > 0");
    }
    // Push the next stream value; true when a full window is available via max(). O(1) amortized, O(w) memory.
    bool push(int v) {
        while (size_ > 0 && val_[at(size_ - 1)] <= v) --size_;  // dominated: can never be a maximum again
        std::size_t slot = at(size_);
        idx_[slot] = seen_;
        val_[slot] = v;
        ++size_;
        if (seen_ >= w_ && idx_[head_] <= seen_ - w_) {
            head_ = head_ + 1 == cap_ ? 0 : head_ + 1;
            --size_;
        }
        ++seen_;
        return seen_ >= w_;
    }
    int max() const { return val_[head_]; }

private:
    std::size_t at(std::size_t offset) const {  // ring index without %: a division per access is a hidden constant
        std::size_t i = head_ + offset;
        return i >= cap_ ? i - cap_ : i;
    }
    std::size_t w_, cap_;  // a push momentarily holds w + 1 entries before the front is evicted
    std::vector<std::uint64_t> idx_;
    std::vector<int> val_;
    std::size_t head_ = 0, size_ = 0;
    std::uint64_t seen_ = 0;
};

Vec window_max(std::span<const int> a, std::size_t w) {
    WindowMax m(w);
    Vec out;
    for (int v : a)
        if (m.push(v)) out.push_back(m.max());
    return out;
}

Vec window_max_std_deque(std::span<const int> a, std::size_t w) {  // the textbook std::deque version
    std::deque<std::size_t> dq;
    Vec out;
    for (std::size_t i = 0; i < a.size(); ++i) {
        while (!dq.empty() && a[dq.back()] <= a[i]) dq.pop_back();
        dq.push_back(i);
        if (dq.front() + w <= i) dq.pop_front();
        if (i + 1 >= w) out.push_back(a[dq.front()]);
    }
    return out;
}

Vec window_max_oracle(std::span<const int> a, std::size_t w) {
    Vec out;
    for (std::size_t i = 0; i + w <= a.size(); ++i) out.push_back(*std::max_element(a.begin() + static_cast<std::ptrdiff_t>(i),
                                                                                  a.begin() + static_cast<std::ptrdiff_t>(i + w)));
    return out;
}

// ======================================================================= 4. LC 907 sum of subarray minimums
// Contest bug: stop at an EQUAL element on both sides, so a subarray whose minimum occurs twice is counted by nobody.
std::int64_t cp_sum_subarray_mins(std::span<const int> a) {
    std::int64_t sum = 0;
    for (std::size_t i = 0; i < a.size(); ++i) {
        std::size_t l = i, r = i;
        while (l > 0 && a[l - 1] > a[i]) --l;
        while (r + 1 < a.size() && a[r + 1] > a[i]) ++r;
        sum += static_cast<std::int64_t>(a[i]) * static_cast<std::int64_t>((i - l + 1) * (r - i + 1));
    }
    return sum;
}

// Tie-break once: an equal element to the LEFT stops the span, to the RIGHT it does not. Two monotonic passes.
std::int64_t sum_subarray_mins(std::span<const int> a) {
    std::size_t n = a.size();
    std::vector<std::size_t> left(n), right(n), st;
    for (std::size_t i = 0; i < n; ++i) {
        while (!st.empty() && a[st.back()] > a[i]) st.pop_back();  // previous element <= a[i] stops us
        left[i] = st.empty() ? i + 1 : i - st.back();
        st.push_back(i);
    }
    st.clear();
    for (std::size_t i = n; i-- > 0;) {
        while (!st.empty() && a[st.back()] >= a[i]) st.pop_back();  // next element < a[i] stops us
        right[i] = st.empty() ? n - i : st.back() - i;
        st.push_back(i);
    }
    std::int64_t sum = 0;
    for (std::size_t i = 0; i < n; ++i) sum += static_cast<std::int64_t>(a[i]) * static_cast<std::int64_t>(left[i] * right[i]);
    return sum;
}

std::int64_t sum_subarray_mins_oracle(std::span<const int> a) {
    std::int64_t sum = 0;
    for (std::size_t i = 0; i < a.size(); ++i) {
        int mn = std::numeric_limits<int>::max();
        for (std::size_t j = i; j < a.size(); ++j) sum += (mn = std::min(mn, a[j]));
    }
    return sum;
}

// ======================================================================= 5. two-stacks aggregate queue (any monoid)
// FIFO queue answering "aggregate of everything inside" in O(1) amortized for ANY associative op -- max, gcd, sum,
// matrix product, even non-commutative ones. The front stack stores suffix aggregates (oldest on top).
template <class T, class Op>
class AggQueue {
public:
    AggQueue(Op op, T identity) : op_(std::move(op)), identity_(identity), back_agg_(identity) {}
    void push(T v) {
        back_agg_ = op_(back_agg_, v);
        back_.push_back(std::move(v));
    }
    T pop() {
        if (front_.empty()) {
            for (auto it = back_.rbegin(); it != back_.rend(); ++it) {  // newest first, so the oldest ends on top
                front_agg_.push_back(front_agg_.empty() ? *it : op_(*it, front_agg_.back()));
                front_.push_back(std::move(*it));
            }
            back_.clear();
            back_agg_ = identity_;
        }
        if (front_.empty()) throw std::out_of_range("empty");
        front_agg_.pop_back();
        T v = std::move(front_.back());
        front_.pop_back();
        return v;
    }
    T aggregate() const { return op_(front_agg_.empty() ? identity_ : front_agg_.back(), back_agg_); }

private:
    Op op_;
    T identity_;
    std::vector<T> front_, front_agg_, back_;
    T back_agg_;
};

std::string show(std::span<const int> a) {
    std::string s = "[";
    for (std::size_t i = 0; i < a.size(); ++i) s += std::format("{}{}", i ? ", " : "", a[i]);
    return s + "]";
}

int main() {
    std::println("1. LC 84, heights [1000000000 x 3]: contest int area: not run (UB; see the -D build) | int64 area {}",
                 largest_rectangle(std::array{1'000'000'000, 1'000'000'000, 1'000'000'000}));
    SplitMix64 r{31};
    constexpr int kTrials = 20'000;
    int ok_hist = 0, ok_rect = 0, ok_max = 0, ok_mins = 0, cp_mins = 0, ok_agg = 0;
    Vec first_bad;
    bool have_bad = false;
    auto gcd = [](int x, int y) { return std::gcd(x, y); };
    auto cat = [](const std::string& x, const std::string& y) { return x + y; };
    for (int t = 0; t < kTrials; ++t) {
        Vec h = r.array(10, 0, 6);
        ok_hist += largest_rectangle(h) == largest_rectangle_oracle(h);
        int rows = r.next_int(5), cols = 1 + r.next_int(5);
        Grid g(static_cast<std::size_t>(rows), Vec(static_cast<std::size_t>(cols)));
        for (auto& row : g)
            for (int& c : row) c = r.next_int(3) == 0 ? 0 : 1;
        ok_rect += maximal_rectangle(g) == maximal_rectangle_oracle(g);
        Vec a = r.array(12, 1, 4);
        auto w = static_cast<std::size_t>(1 + r.next_int(4));
        auto want_max = window_max_oracle(a, w);
        ok_max += window_max(a, w) == want_max && window_max_std_deque(a, w) == want_max;
        auto want = sum_subarray_mins_oracle(a);
        ok_mins += sum_subarray_mins(a) == want;
        if (cp_sum_subarray_mins(a) == want) ++cp_mins;
        else if (!have_bad || a.size() < first_bad.size()) first_bad = a, have_bad = true;
        AggQueue<int, decltype(gcd)> gq(gcd, 0);
        AggQueue<std::string, decltype(cat)> sq(cat, "");
        bool ok = true;
        for (std::size_t i = 0; i < a.size(); ++i) {
            gq.push(a[i] * 6);
            sq.push(std::string(1, static_cast<char>('a' + a[i])));
            if (i >= w) (void)gq.pop(), (void)sq.pop();
            std::size_t lo = i + 1 >= w ? i + 1 - w : 0;
            int g2 = 0;
            std::string s;
            for (std::size_t j = lo; j <= i; ++j) g2 = std::gcd(g2, a[j] * 6), s += static_cast<char>('a' + a[j]);
            ok = ok && gq.aggregate() == g2 && sq.aggregate() == s;
        }
        ok_agg += ok;
    }
    std::println("   LC 84 monotonic stack vs O(n^2) oracle: {}/{}", ok_hist, kTrials);
    std::println("2. LC 85 maximal rectangle vs brute force: {}/{}", ok_rect, kTrials);
    std::println("3. LC 239 window max (ring deque and std::deque) vs oracle: {}/{}", ok_max, kTrials);
    std::println("4. LC 907 sum of subarray minimums: tie-broken stacks {}/{} | contest strict-both-sides {}/{}, smallest"
                 " failure {} -> {} vs truth {}", ok_mins, kTrials, cp_mins, kTrials, show(first_bad),
                 cp_sum_subarray_mins(first_bad), sum_subarray_mins_oracle(first_bad));
    std::println("5. two-stacks queue, gcd and NON-commutative concat over sliding windows vs brute: {}/{}", ok_agg, kTrials);

    constexpr std::size_t n = 10'000'000, w = 1'000;
    Vec data(n);
    for (int& v : data) v = static_cast<int>(r.next() >> 40);
    using clock = std::chrono::steady_clock;
    auto ms = [](clock::duration d) { return std::chrono::duration_cast<std::chrono::milliseconds>(d).count(); };
    auto t0 = clock::now();
    Vec a1 = window_max(data, w);
    auto t1 = clock::now();
    Vec a2 = window_max_std_deque(data, w);
    auto t2 = clock::now();
    auto mx = [](int x, int y) { return std::max(x, y); };
    AggQueue<int, decltype(mx)> q(mx, std::numeric_limits<int>::min());
    std::size_t mismatches = 0;
    for (std::size_t i = 0; i < n; ++i) {
        q.push(data[i]);
        if (i >= w) (void)q.pop();
        if (i + 1 >= w) mismatches += q.aggregate() != a1[i + 1 - w];
    }
    auto t3 = clock::now();
    std::println("B. window max, n={}, w={} (one measured run): ring deque {} ms (O(w) memory) | std::deque {} ms |"
                 " AggQueue<int> {} ms | all agree: {}", n, w, ms(t1 - t0), ms(t2 - t1), ms(t3 - t2), a1 == a2 && mismatches == 0);
}
```

**Output, GCC 16.2 (verified; the last line is one measured run):**

```text
1. LC 84, heights [1000000000 x 3]: contest int area: not run (UB; see the -D build) | int64 area 3000000000
   LC 84 monotonic stack vs O(n^2) oracle: 20000/20000
2. LC 85 maximal rectangle vs brute force: 20000/20000
3. LC 239 window max (ring deque and std::deque) vs oracle: 20000/20000
4. LC 907 sum of subarray minimums: tie-broken stacks 20000/20000 | contest strict-both-sides 5580/20000, smallest failure [1, 1] -> 2 vs truth 3
5. two-stacks queue, gcd and NON-commutative concat over sliding windows vs brute: 20000/20000
B. window max, n=10000000, w=1000 (one measured run): ring deque 111 ms (O(w) memory) | std::deque 109 ms | AggQueue<int> 23 ms | all agree: true
```

**Output, Clang 21.1 (verified; the last line is one measured run):**

```text
1. LC 84, heights [1000000000 x 3]: contest int area: not run (UB; see the -D build) | int64 area 3000000000
   LC 84 monotonic stack vs O(n^2) oracle: 20000/20000
2. LC 85 maximal rectangle vs brute force: 20000/20000
3. LC 239 window max (ring deque and std::deque) vs oracle: 20000/20000
4. LC 907 sum of subarray minimums: tie-broken stacks 20000/20000 | contest strict-both-sides 5580/20000, smallest failure [1, 1] -> 2 vs truth 3
5. two-stacks queue, gcd and NON-commutative concat over sliding windows vs brute: 20000/20000
B. window max, n=10000000, w=1000 (one measured run): ring deque 128 ms (O(w) memory) | std::deque 159 ms | AggQueue<int> 57 ms | all agree: true
```

**The expected-failure build (`-DAREA_OVERFLOW`), GCC 16.2:**

```text
monotonic_structures.cpp:53:93: error: non-constant condition for static assertion
monotonic_structures.cpp:45:42: error: overflow in constant expression [-fpermissive]
```

**Clang 21.1:**

```text
monotonic_structures.cpp:53:15: error: static assertion expression is not an integral constant expression
monotonic_structures.cpp:45:42: note: value 3000000000 is outside the range of representable values of type 'int'
```

---

## 3. What the results show

* **The overflowing area doesn't crash; it picks a wrong rectangle.** Three bars of height 10⁹: the true answer is 3×10⁹. The Java contest code computes the width-3 area as 3×10⁹, which wraps to −1,294,967,296. `Math.max` then keeps the width-2 area of **2,000,000,000**, which is plausible, positive and wrong. In C++ that multiplication is undefined behaviour, so the contest version only runs inside `static_assert`. There, the LeetCode sample passes and the large input is rejected by both compilers (*"value 3000000000 is outside the range of representable values of type 'int'"*).
* **The tie bug is invisible on distinct values.** Random arrays with values 1–4 exposed it in 72% of cases (5,580/20,000 correct). The minimal counterexample is `[1, 1]`: the contest code counts the two one-element subarrays and never the pair `[1, 1]`, giving 2 instead of 3. The asymmetric version passes all 20,000.
* **The two-stacks queue handles what a deque can't.** Window gcd and window string concatenation, the latter non-commutative, both match brute force on all 20,000 random windows.
* **Constants, measured (10 M elements, w = 1,000; ranges across 2–4 runs):**

| Implementation | Java | C++ GCC | C++ Clang |
|---|---|---|---|
| Index ring deque, capacity `w + 1` | 90–100 ms | 102–123 ms | 128–153 ms |
| `ArrayDeque<Integer>` / `std::deque` | 169–187 ms | 109–157 ms | 159–185 ms |
| Two-stacks queue (`AggQueue`) | 307–337 ms (boxed `Integer`) | **23–27 ms** | **57–61 ms** |

Two findings here were not what I expected, and both are reported as measured:

1. **The first version of the ring deque lost to boxed `ArrayDeque<Integer>`** (237 ms vs 182 ms). It computed every ring index with `%`, an integer division on each access, and its capacity was `w` instead of `w + 1`. Replacing `%` with compare-and-wrap made it 2.4–2.6× faster. The listing keeps the comment. *Big-O equal, constant dominated by one instruction.*
2. **In C++ the general-purpose two-stacks queue beat the specialized monotonic deques by 2–5×** (23–61 ms against 102–185 ms across four runs). On GCC the hand-written ring deque and `std::deque` were roughly tied. The deque's inner `while (back ≤ v) pop` has a data-dependent trip count on random input, a likely source of branch mispredictions ⚠ (not profiled). The two-stacks queue does the same work in straight-line code with one rare flip. In Java the boxed generic version was the slowest. The interview-grade statement: *"the same O(1)-amortized window ranged from 23 ms to 337 ms, a 15× spread across languages and representations; measure the one you ship."*

---

## 4. The last 10 minutes: Extensions A, B and C

### 4.1 Extension A — "64 threads"

* **Per-key window extrema** (max latency per endpoint in the last minute): partition keys to single-writer workers. Each window is a private deque, so no locks.
* **One global window fed by many producers:** a deque is a sequential structure, and making it concurrent means a lock around every push. The scalable alternative uses the aggregate's algebra. Each producer keeps its own window over a **shared time grid** (panes), and a query combines the per-producer pane aggregates with `⊕`. That requires `⊕` to be **commutative** as well as associative, because producers' panes interleave arbitrarily. Max, sum and gcd qualify; string concatenation does not.
* **Static arrays with many concurrent range-extreme queries:** build once, publish immutable, query lock-free. That is a sparse table: O(1) range-min after O(n log n) preprocessing (Folder 03).

### 4.2 Extension B — "an unbounded stream, or a window of a billion events"

* A count window needs `O(w)` memory. That is fine at `w = 10⁶` and not at `w = 10⁹`.
* **Panes again:** for a 24-hour max with one-minute panes, push one aggregate per pane into a two-stacks queue of 1,440 panes. Exact at pane boundaries, memory 1,440 entries regardless of event rate. This is how stream processors evaluate long sliding windows ("No pane, no gain").
* The two-stacks queue's flip is O(w) in the worst case. If **per-event latency** matters more than throughput, the "DABA" family of algorithms makes every operation worst-case O(1) ⚠ (cited, not implemented here).

### 4.3 Extension C — "the series is sharded across 100 machines"

* **Fixed windows across shard boundaries:** a halo of `w − 1`, as in File 1.
* **Range extremes over arbitrary ranges:** each shard publishes one summary, its max. A query over shards `[a, b]` combines whole shards in O(number of shards) and asks the two edge shards for partial ranges. That is a two-level segment tree; Folder 03 generalizes it.
* **Histogram and rectangle problems don't decompose that simply.** The largest rectangle can span shards, and a shard summary needs its stack of "open" bars on each edge. The nearest-smaller-element structure of a concatenation can be computed from the two halves' boundary stacks. Whether a problem has a compact boundary summary is the question that decides whether it distributes at all. Say that, and offer the composable alternative when one exists.

---

## 5. Failure modes

| # | Failure | Symptom | Prevention |
|---|---|---|---|
| F1 | `int` area or product | Plausible but wrong maximum (2×10⁹ for 3×10⁹) | 64-bit arithmetic, bound stated |
| F2 | Symmetric tie rule when counting spans | Repeated-minimum subarrays counted 0 or 2 times | Strict on one side, non-strict on the other, commented |
| F3 | Deque capacity `w` | Overwrites during push; wrong maxima on some inputs | Capacity `w + 1`, or evict before push |
| F4 | `%` in a hot ring index | 2.4× slower than necessary | Compare-and-wrap, or power-of-two capacity with a mask |
| F5 | Boxed deques on hot paths | Allocation and indirection | Primitive index rings; measure |
| F6 | Monotonic deque for a non-ordered aggregate | Can't express gcd, OR, products | Two-stacks queue (any monoid) |
| F7 | Treating a non-commutative op as mergeable across producers | Wrong combined result | Combine per-producer aggregates only for commutative ops; otherwise impose an order |
| F8 | O(w) state for enormous windows | Memory blow-up | Panes; sketches |

---

## 6. Bar-raiser chains

<details><summary><b>Q1 · "Why is the histogram algorithm O(n) when there's a while loop inside the for loop?"</b></summary>

**Initial Prompt.** LeetCode 84 solved with a monotonic stack.

**L5 Answer.** "It's amortized."

**Why L5 Stalls.** "Amortized" names the technique without the argument.

**L7 Answer.** "Each index is pushed exactly once and popped at most once, so all iterations of the inner loop together pop at most n times. Total work is 2n stack operations plus n comparisons that end a while loop. The invariant that makes each pop final: when bar j is popped by a lower bar at i, the entry below j is the nearest lower bar on its left, so j's widest rectangle is exactly between those two and can be computed right then."
</details>

<details><summary><b>Q2 · "Heights go up to 10⁹ and n to 10⁵. Anything to change?"</b></summary>

**Initial Prompt.** The candidate's area variable is `int`.

**L5 Answer.** "It should still fit."

**Why L5 Stalls.** 10⁹ × 10⁵ = 10¹⁴ needs 47 bits. And the failure is silent: measured, three bars of 10⁹ returned 2×10⁹ instead of 3×10⁹.

**L7 Answer.** "Height times width can reach 10¹⁴, so the area is a long. I'd say that before writing the multiplication. In C++ an int overflow there is undefined behaviour, not just a wrong number, so the cast to 64 bits goes on the operands, not the result."
</details>

<details><summary><b>Q3 · "Sum of subarray minimums — what if values repeat?"</b></summary>

**Initial Prompt.** LeetCode 907; the candidate's spans use `<` on both sides.

**L5 Answer.** "Equal values are fine; the minimum is the same."

**Why L5 Stalls.** The *value* is the same but the *assignment* of a subarray to an index is not unique. Measured: 72% of random inputs with repeats were wrong, minimal case `[1, 1]` gives 2 instead of 3.

**L7 Answer.** "Each subarray must be credited to exactly one of its minimum positions. I'll break ties asymmetrically: the left span stops at an equal element, the right span passes equal elements. So a subarray belongs to its leftmost minimum. I'll write that rule in a comment and test `[1, 1]` and `[2, 2, 2]` explicitly. Products in long; the problem's modulus applied once at the end of each term."
</details>

<details><summary><b>Q4 · "Sliding window maximum — which deque would you use?"</b></summary>

**Initial Prompt.** LeetCode 239, Java or C++.

**L5 Answer.** "ArrayDeque," or "std::deque."

**Why L5 Stalls.** Fine for correctness; but the follow-up is "make it faster" or "bounded memory", and the candidate has no model of the constants.

**L7 Answer.** "Algorithmically any deque works: amortized O(1) per element, O(w) memory. For a hot path I'd use a primitive ring of indices with capacity w + 1 and compare-and-wrap indexing. I measured my first version, which used `%`, losing to `ArrayDeque<Integer>`; without `%` it was about 2× faster than the boxed deque. In C++, a two-stacks queue was faster still on random data because it has no data-dependent pop loop. So the answer is to benchmark the shapes on realistic data."
</details>

<details><summary><b>Q5 · "Now I want the gcd of the last w numbers, not the max."</b></summary>

**Initial Prompt.** A variation that breaks the deque.

**L5 Answer.** Tries to adapt the dominance rule to gcd and gets stuck, or recomputes each window in O(w).

**Why L5 Stalls.** Dominance needs a total order on aggregate values; gcd has none, so there's no "dominated" element to discard.

**L7 Answer.** "Gcd is associative with identity 0, so a two-stacks queue works. The back stack keeps a running gcd, the front stack stores suffix gcds, and pop flips the back when the front is empty. Amortized O(1) per operation, and it works for any associative operation, including non-commutative ones like matrix products, because it preserves order. I'd write it once, generic over the operator, and reuse it for max, sum and gcd."
</details>

<details><summary><b>Q6 · "The stream is 1 M events per second; the window is 24 hours."</b></summary>

**Initial Prompt.** Extension B: the window holds 86 billion events.

**L5 Answer.** "Use the deque; it only keeps a subset."

**Why L5 Stalls.** The deque's worst case is the whole window (a decreasing input), and the two-stacks queue always holds the whole window.

**L7 Answer.** "Exact per-event state is impossible at that size, so I'd use panes. Aggregate each minute into one value, and keep a two-stacks queue of 1,440 pane aggregates. Memory is constant regardless of rate; the result is exact at minute boundaries, and the current minute's partial pane is combined in at query time. If per-event latency spikes from the flip matter, there are worst-case O(1) variants."
</details>

<details><summary><b>Q7 · "64 producers push into one global window. Max of the last minute?"</b></summary>

**Initial Prompt.** Extension A.

**L5 Answer.** "Lock the deque."

**Why L5 Stalls.** It works but serializes every event through one lock, and the deque can't be partitioned because it depends on arrival order.

**L7 Answer.** "Max is associative *and* commutative, so I don't need one global order. Each producer keeps per-second pane maxima for its own events, and a query takes the max across producers and panes. No shared mutable state on the hot path. That trick only works for commutative aggregates; for something order-dependent I'd need a sequencer or a single-writer partition."
</details>

<details><summary><b>Q8 · "Maximal rectangle of 1s in a binary matrix."</b></summary>

**Initial Prompt.** LeetCode 85.

**L5 Answer.** Proposes O(R²C²) enumeration, or a DP with three arrays without explaining it.

**Why L5 Stalls.** Misses the reduction that makes it a one-liner on top of an already-proven primitive.

**L7 Answer.** "Treat each row as the floor of a histogram whose bar heights are the number of consecutive 1s above. A row update is O(C), and the largest rectangle in that histogram is the monotonic-stack routine I already have. O(R × C) total, reusing a tested component. I'd test it against brute force on small random matrices; the listing does 20,000 of them."
</details>

---

## 7. Checklist

* [ ] Say what the stack/deque contains (the candidate set) and why each pop is final.
* [ ] Complexity by amortization: each index pushed once, popped once.
* [ ] 64-bit products; bounds stated before the multiplication.
* [ ] Tie rule written down: strict on one side, non-strict on the other.
* [ ] Deque capacity `w + 1`; no `%` in hot ring indexing; primitive indices.
* [ ] Non-ordered aggregates → two-stacks queue (associativity only).
* [ ] Extension A: single-writer per key; commutative aggregates combine across producers.
* [ ] Extension B: panes for long windows; worst-case O(1) variants if latency matters.
* [ ] Extension C: halo for fixed windows; boundary summaries; segment-tree style composition.

---

## 8. References

* K. Tangwongsan, M. Hirzel, S. Schneider, R. Wu, *General Incremental Sliding-Window Aggregation*, PVLDB 8(7), 2015 — DOI 10.14778/2752939.2752940
* K. Tangwongsan, M. Hirzel, S. Schneider, *Optimal and General Out-of-Order Sliding-Window Aggregation*, PVLDB 12(10), 2019 — DOI 10.14778/3339490.3339495
* J. Li, D. Maier, K. Tufte, V. Papadimos, P. A. Tucker, *No pane, no gain*, SIGMOD Record 34(1), 2005 — DOI 10.1145/1058150.1058158
* LeetCode anchors: [84 Largest Rectangle in Histogram](https://leetcode.com/problems/largest-rectangle-in-histogram/), [85 Maximal Rectangle](https://leetcode.com/problems/maximal-rectangle/), [239 Sliding Window Maximum](https://leetcode.com/problems/sliding-window-maximum/), [907 Sum of Subarray Minimums](https://leetcode.com/problems/sum-of-subarray-minimums/), [496 Next Greater Element I](https://leetcode.com/problems/next-greater-element-i/), [42 Trapping Rain Water](https://leetcode.com/problems/trapping-rain-water/)
* Java SE 21 API: `ArrayDeque` — <https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/ArrayDeque.html>; cppreference `std::deque` — <https://en.cppreference.com/w/cpp/container/deque>

*Folder 02:* [01 — two pointers and window invariants](01-two-pointers-and-non-shrinkable-sliding-window-invariants.md) · [03 — exchange arguments, matroids and regret greedy](03-exchange-arguments-matroids-interval-scheduling-and-regret-greedy-heaps.md)
