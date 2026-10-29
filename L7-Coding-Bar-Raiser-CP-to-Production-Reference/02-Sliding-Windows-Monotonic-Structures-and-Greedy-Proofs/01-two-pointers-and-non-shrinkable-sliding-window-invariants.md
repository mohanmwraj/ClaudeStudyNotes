# Two Pointers and Non-Shrinkable Sliding-Window Invariants

> **Folder 02 · File 1 of 3** — why two pointers are O(n), the one property that makes them correct, the inputs where they silently are not, and what a window becomes over a stream and over shards.
> **Languages:** Java 21 (`--release 21 -Xlint:all -Werror`, JDK 25.0.4.1) and C++23 (GCC 16.2 and Clang 21.1, `-O2`, warnings as errors).

| Listing | File | What it proves |
|---|---|---|
| 2.1 | `SlidingWindows.java` | At-most-k-distinct over **code points** (a `char[]` window gets emoji wrong); LC 1004 shrinkable = non-shrinkable; LC 76 minimum cover; LC 560 two pointers fail with zeros and negatives, shrunk to `[3, -2]`; an O(w) streaming window; the shard halo |
| 2.2 | `sliding_windows.cpp` | The same in C++23: UTF-8 decoding with `std::expected`, the same counts and counterexamples, ranges-based streaming input |

**Verification.** Both listings were extracted from this file, compiled and run. Every output is **Output (verified)**: deterministic, re-checked byte-for-byte, and identical between Java and both C++ builds apart from number formatting.

---

## 0. Orientation

Two pointers is the pattern competitive programmers reach for fastest and justify least. In a contest that's fine: if it passes, it was right. In a Staff round the interviewer asks *"why is this correct?"*, and the answer is one sentence about **monotonicity**. A candidate who can't give it has been pattern-matching, and those candidates get the variants with zeros and negative numbers wrong.

| Contest habit | What breaks | L7 replacement |
|---|---|---|
| `int cnt[256]` indexed by `char` | Java `char` is a UTF-16 unit and C++ `char` a UTF-8 byte: one emoji is 2 or 4 "characters" | Window over **tokens**: code points or interned ids, counted in a map (or an array when the alphabet is proven small) |
| Two pointers for "count subarrays with sum k" | Correct only when every value is > 0; silently wrong with zeros or negatives | Prefix sums + hash map, `O(n)` for any signs; two pointers only after stating the monotonicity it relies on |
| Re-deriving the shrink loop under pressure | Off-by-one in "shortest vs longest" windows | Two templates with written invariants: *shrink while invalid* (longest) and *shrink while valid* (shortest) |
| `while` vs `if` in the shrink step, by feel | Sometimes right by accident | The non-shrinkable window: `if` is correct **because** the answer never needs a smaller window |
| A window over an array in memory | Fails on a stream or across shards | O(w) ring buffer; a halo of `w − 1` per shard |

---

## 1. First principles

### 1.1 The invariant that makes two pointers O(n)

Let `P(l, r)` be "window `[l, r]` is valid". Two pointers is correct for a **longest valid window** problem if and only if validity is **closed under shrinking**: if `[l, r]` is valid, every sub-window `[l', r']` with `l ≤ l' ≤ r' ≤ r` is valid. Then for each right end `r`, the smallest valid left end `L(r)` is **non-decreasing** in `r`. Moving `r` right can only make the window harder to satisfy, never easier, so the left pointer never needs to move back. Each pointer moves at most `n` times: `O(n)` total, regardless of the inner `while`.

* "At most k distinct values", "at most k zeros", "sum ≤ S with non-negative values" are all closed under shrinking. Two pointers is correct.
* "Sum exactly k" with zeros or negatives is **not**. Removing a negative from the left can *raise* the sum, so `L(r)` is not monotone. Two pointers is wrong, and nothing crashes. Listing 2.1 shows it.

For **shortest valid window** problems (LeetCode 76, minimum window cover) the property flips: validity must be closed under **growing**. If `[l, r]` covers the target, any super-window does too. The loop shrinks **while valid**, recording the answer before each shrink.

**"Exactly k"** problems reduce to two monotone ones: `exactly(k) = atMost(k) − atMost(k − 1)` (LeetCode 992, subarrays with k different integers). That is the standard way to keep two pointers when the predicate itself is not monotone.

### 1.2 The non-shrinkable window

For "longest window", the window never needs to get *smaller* than the best seen so far. A smaller window can't improve the answer. So replace the shrink `while` with a single `if`. When the window becomes invalid, slide it by one: `l++` together with the `r++` of the next iteration. The window's size then never decreases, and at the end **`n − l` is the answer**. Invariant: *after step r, `r − l + 1` equals the best length seen so far, and the window `[l, r]` is either valid or exactly one step past a valid window of that length.* Listing 2.1 checks shrinkable and non-shrinkable against brute force on 20,000 random inputs. It's a useful trick to know and a better one to be able to prove in one sentence.

### 1.3 When the pointers point at a sorted array

Opposite-ends two pointers (pair sum on a sorted array, LeetCode 167; container with most water, LeetCode 11) rest on a different invariant. With `a` sorted and `l < r`, if `a[l] + a[r] < target`, then `a[l]` cannot pair with **any** element in `(l, r]` to reach the target. So discarding `l` loses nothing. Each step discards one candidate with proof, which bounds the steps by `n`. Say the discard rule aloud; it is the proof.

### 1.4 Tokens, not characters

A string window's alphabet is part of the contract. A Java `String` is UTF-16. `charAt` returns a 16-bit code **unit**, and every character outside the Basic Multilingual Plane (emoji, many CJK extensions) is **two** units. A C++ `std::string` is bytes; UTF-8 uses one to four per code point. A window that counts units or bytes as "characters" gives wrong lengths and wrong distinct counts on real text. The production move is to decide the token type explicitly: code points (`String.codePoints()`, a UTF-8 decoder), grapheme clusters (what a user calls a character), or interned ids. Then make the window generic over `int` tokens.

---

## 2. The listings

### 2.1 Listing 2.1 — Java

```java
// SlidingWindows.java - two pointers and window invariants: when they hold, when they silently don't, streams and shards.
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.PrimitiveIterator;
import java.util.Set;
import java.util.function.BiPredicate;
import java.util.stream.IntStream;

public final class SlidingWindows {

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

    // ===================================================================== 1. longest window with <= k distinct
    /** Contest habit: index an array by char. A Java char is a UTF-16 code unit, so one emoji is two "characters". */
    static int cpAtMostKDistinct(String s, int k) {
        int[] cnt = new int[65536];
        int distinct = 0, best = 0;
        for (int l = 0, r = 0; r < s.length(); r++) {
            if (cnt[s.charAt(r)]++ == 0) distinct++;
            while (distinct > k) if (--cnt[s.charAt(l++)] == 0) distinct--;
            best = Math.max(best, r - l + 1);
        }
        return best;
    }

    /**
     * Longest window of tokens with at most k distinct values. Invariant: [l, r] is valid after the inner loop.
     * Correct because validity is monotone: every sub-window of a valid window is valid. O(n) expected, O(k) space.
     */
    static int atMostKDistinct(int[] tokens, int k) {
        if (k < 0) throw new IllegalArgumentException("k < 0");
        Map<Integer, Integer> cnt = new HashMap<>();
        int best = 0;
        for (int l = 0, r = 0; r < tokens.length; r++) {
            cnt.merge(tokens[r], 1, Integer::sum);
            while (cnt.size() > k) {
                if (cnt.merge(tokens[l], -1, Integer::sum) == 0) cnt.remove(tokens[l]);
                l++;
            }
            best = Math.max(best, r - l + 1);
        }
        return best;
    }

    static int atMostKDistinctOracle(int[] t, int k) {
        int best = 0;
        for (int i = 0; i < t.length; i++) {
            Set<Integer> seen = new HashSet<>();
            for (int j = i; j < t.length; j++) {
                seen.add(t[j]);
                if (seen.size() <= k) best = Math.max(best, j - i + 1);
            }
        }
        return best;
    }

    // ===================================================================== 2. LC 1004: max ones with k flips
    static int maxOnesShrinking(int[] a, int k) {
        int best = 0, zeros = 0;
        for (int l = 0, r = 0; r < a.length; r++) {
            if (a[r] == 0) zeros++;
            while (zeros > k) if (a[l++] == 0) zeros--;
            best = Math.max(best, r - l + 1);
        }
        return best;
    }

    /** Non-shrinkable: the window grows or slides, never shrinks, so its final size IS the best size seen. */
    static int maxOnesNonShrinking(int[] a, int k) {
        int l = 0, zeros = 0;
        for (int r = 0; r < a.length; r++) {
            if (a[r] == 0) zeros++;
            if (zeros > k && a[l++] == 0) zeros--;
        }
        return a.length - l;
    }

    static int maxOnesOracle(int[] a, int k) {
        int best = 0;
        for (int i = 0; i < a.length; i++) {
            int zeros = 0;
            for (int j = i; j < a.length; j++) {
                zeros += a[j] == 0 ? 1 : 0;
                if (zeros <= k) best = Math.max(best, j - i + 1);
            }
        }
        return best;
    }

    // ===================================================================== 3. LC 76: minimum window covering a multiset
    /** Returns {start, end} (half-open) of the shortest, then leftmost, window covering `need`; {0, 0} if none. */
    static int[] minWindow(int[] text, int[] need) {
        Map<Integer, Integer> missing = new HashMap<>();
        for (int x : need) missing.merge(x, 1, Integer::sum);
        int stillMissing = need.length, bestL = 0, bestR = Integer.MAX_VALUE;
        if (need.length == 0) return new int[] {0, 0};
        for (int l = 0, r = 0; r < text.length; r++) {
            Integer m = missing.get(text[r]);
            if (m != null) {
                if (m > 0) stillMissing--;
                missing.put(text[r], m - 1);  // negative = surplus copies inside the window
            }
            while (stillMissing == 0) {
                if (r + 1 - l < bestR - bestL) { bestL = l; bestR = r + 1; }
                Integer ml = missing.get(text[l]);
                if (ml != null) {
                    if (ml == 0) stillMissing++;
                    missing.put(text[l], ml + 1);
                }
                l++;
            }
        }
        return bestR == Integer.MAX_VALUE ? new int[] {0, 0} : new int[] {bestL, bestR};
    }

    static int[] minWindowOracle(int[] text, int[] need) {
        if (need.length == 0) return new int[] {0, 0};
        Map<Integer, Long> want = new HashMap<>();
        for (int x : need) want.merge(x, 1L, Long::sum);
        for (int len = 1; len <= text.length; len++) {
            for (int i = 0; i + len <= text.length; i++) {
                Map<Integer, Long> have = new HashMap<>();
                for (int j = i; j < i + len; j++) have.merge(text[j], 1L, Long::sum);
                if (want.entrySet().stream().allMatch(e -> have.getOrDefault(e.getKey(), 0L) >= e.getValue())) {
                    return new int[] {i, i + len};
                }
            }
        }
        return new int[] {0, 0};
    }

    // ===================================================================== 4. LC 560: count subarrays with sum k
    /** Contest habit: two pointers. Valid ONLY if every value is > 0, so that the window sum is strictly monotone. */
    static long cpCountSumK(int[] a, long k) {
        long count = 0, sum = 0;
        for (int l = 0, r = 0; r < a.length; r++) {
            sum += a[r];
            while (sum > k && l <= r) sum -= a[l++];
            if (sum == k && l <= r) count++;
        }
        return count;
    }

    /** prefix[j] - prefix[i] == k  <=>  prefix[i] == prefix[j] - k: count earlier prefixes. O(n) expected, any signs. */
    static long countSumK(int[] a, long k) {
        Map<Long, Integer> seen = new HashMap<>(Map.of(0L, 1));
        long prefix = 0, count = 0;
        for (int v : a) {
            prefix += v;
            count += seen.getOrDefault(prefix - k, 0);
            seen.merge(prefix, 1, Integer::sum);
        }
        return count;
    }

    static long countSumKOracle(int[] a, long k) {
        long count = 0;
        for (int i = 0; i < a.length; i++) {
            long s = 0;
            for (int j = i; j < a.length; j++) if ((s += a[j]) == k) count++;
        }
        return count;
    }

    static int[] shrink(int[] a, BiPredicate<int[], Integer> fails, int k) {  // drop elements / move toward 0
        for (boolean progress = true; progress; ) {
            progress = false;
            List<int[]> cands = new ArrayList<>();
            for (int i = 0; i < a.length; i++) {
                int[] c = new int[a.length - 1];
                System.arraycopy(a, 0, c, 0, i);
                System.arraycopy(a, i + 1, c, i, a.length - i - 1);
                cands.add(c);
            }
            for (int i = 0; i < a.length; i++) {
                if (a[i] == 0) continue;
                int[] c = a.clone();
                c[i] -= Integer.signum(a[i]);
                cands.add(c);
            }
            for (int[] c : cands) {
                if (fails.test(c, k)) { a = c; progress = true; break; }
            }
        }
        return a;
    }

    // ===================================================================== Extension B: bounded memory over a stream
    /** Max sum of any w consecutive values of an unbounded stream: O(w) memory (ring buffer), O(1) per element. */
    static long maxWindowSum(PrimitiveIterator.OfInt stream, int w) {
        int[] ring = new int[w];
        long sum = 0, best = Long.MIN_VALUE;
        for (long i = 0; stream.hasNext(); i++) {
            int v = stream.nextInt(), slot = (int) (i % w);
            sum += v - (i >= w ? ring[slot] : 0);
            ring[slot] = v;
            if (i >= w - 1) best = Math.max(best, sum);
        }
        return best;
    }

    // ===================================================================== Extension C: shards need a halo
    /** Shard s owns windows STARTING in [lo_s, hi_s) and therefore needs a[lo_s, hi_s + w - 1): a halo of w - 1. */
    static long shardedMaxWindowSum(int[] a, int w, int shards, boolean halo) {
        long best = Long.MIN_VALUE;
        for (int s = 0; s < shards; s++) {
            int lo = (int) ((long) a.length * s / shards), hi = (int) ((long) a.length * (s + 1) / shards);
            int end = halo ? Math.min(a.length, hi + w - 1) : hi;
            if (end - lo >= w) best = Math.max(best, maxWindowSum(Arrays.stream(a, lo, end).iterator(), w));
        }
        return best;
    }

    public static void main(String[] args) {
        String text = "ab😀😀😀b";  // "ab" + three U+1F600 + "b"
        int[] cps = text.codePoints().toArray();
        System.out.printf("1. \"ab\" + 3 x U+1F600 + \"b\": %d UTF-16 chars, %d code points; longest run with <= 1 distinct:%n",
                text.length(), cps.length);
        System.out.printf("   contest (chars) %d   L7 (code points) %d   oracle %d%n", cpAtMostKDistinct(text, 1),
                atMostKDistinct(cps, 1), atMostKDistinctOracle(cps, 1));

        SplitMix64 r = new SplitMix64(21);
        int trials = 20_000, okDistinct = 0, okOnes = 0, okMin = 0;
        for (int t = 0; t < trials; t++) {
            int[] a = r.array(12, 0, 3);
            int k = r.nextInt(4);
            okDistinct += atMostKDistinct(a, k) == atMostKDistinctOracle(a, k) ? 1 : 0;
            int[] bits = r.array(12, 0, 1);
            int f = r.nextInt(3);
            int want = maxOnesOracle(bits, f);
            okOnes += maxOnesShrinking(bits, f) == want && maxOnesNonShrinking(bits, f) == want ? 1 : 0;
            int[] need = r.array(3, 0, 3);
            okMin += Arrays.equals(minWindow(a, need), minWindowOracle(a, need)) ? 1 : 0;
        }
        System.out.printf("   at-most-k-distinct vs oracle: %d/%d%n", okDistinct, trials);
        System.out.printf("2. LC 1004 shrinking == non-shrinking == oracle: %d/%d%n", okOnes, trials);
        System.out.printf("3. LC 76 min window (shortest, then leftmost) vs oracle: %d/%d%n", okMin, trials);

        System.out.println("4. LC 560 count subarrays with sum k: two pointers vs prefix-sum map, both vs oracle");
        String[] names = {"values 1..3 (positive)", "values 0..3 (zeros)", "values -3..3 (negatives)"};
        int[][] ranges = {{1, 3}, {0, 3}, {-3, 3}};
        for (int g = 0; g < 3; g++) {
            int cpOk = 0, l7Ok = 0;
            int[] firstBad = null;
            int badK = 0;
            for (int t = 0; t < trials; t++) {
                int[] a = r.array(10, ranges[g][0], ranges[g][1]);
                int k = r.nextInt(10) - 3;
                long want = countSumKOracle(a, k);
                l7Ok += countSumK(a, k) == want ? 1 : 0;
                if (cpCountSumK(a, k) == want) cpOk++;
                else if (firstBad == null) { firstBad = a; badK = k; }
            }
            String ce = "";
            if (firstBad != null) {
                int[] m = shrink(firstBad, (c, kk) -> cpCountSumK(c, kk) != countSumKOracle(c, kk), badK);
                ce = String.format("  shrunk: %s, k=%d -> two pointers %d, truth %d", Arrays.toString(m), badK,
                        cpCountSumK(m, badK), countSumKOracle(m, badK));
            }
            System.out.printf("   %-26s two pointers %5d/%d  prefix map %5d/%d%s%n", names[g], cpOk, trials, l7Ok, trials, ce);
        }

        int w = 1_000;
        long streamed = maxWindowSum(IntStream.range(0, 10_000_000).map(i -> (int) ((i * 2654435761L >>> 16) % 2001) - 1000).iterator(), w);
        System.out.printf("B. max sum of %,d consecutive values over a 10,000,000-value stream: %,d using a %,d-int ring buffer%n",
                w, streamed, w);

        int[] data = IntStream.range(0, 100_000).map(i -> (int) ((i * 2654435761L >>> 16) % 2001) - 1000).toArray();
        for (int i = 49_990; i < 50_010; i++) data[i] = 1_000;  // the best window straddles the shard boundary at 50,000
        long global = maxWindowSum(Arrays.stream(data).iterator(), 20);
        System.out.printf("C. w=20 over 100,000 values: global %,d | 2 shards without halo %,d | with a %d-value halo %,d%n",
                global, shardedMaxWindowSum(data, 20, 2, false), 19, shardedMaxWindowSum(data, 20, 2, true));
    }
}
```

**Output (verified):**

```text
1. "ab" + 3 x U+1F600 + "b": 9 UTF-16 chars, 6 code points; longest run with <= 1 distinct:
   contest (chars) 1   L7 (code points) 3   oracle 3
   at-most-k-distinct vs oracle: 20000/20000
2. LC 1004 shrinking == non-shrinking == oracle: 20000/20000
3. LC 76 min window (shortest, then leftmost) vs oracle: 20000/20000
4. LC 560 count subarrays with sum k: two pointers vs prefix-sum map, both vs oracle
   values 1..3 (positive)     two pointers 20000/20000  prefix map 20000/20000
   values 0..3 (zeros)        two pointers 16762/20000  prefix map 20000/20000  shrunk: [0, 2, 1], k=3 -> two pointers 1, truth 2
   values -3..3 (negatives)   two pointers 11933/20000  prefix map 20000/20000  shrunk: [3, -2], k=1 -> two pointers 0, truth 1
B. max sum of 1,000 consecutive values over a 10,000,000-value stream: 4,536 using a 1,000-int ring buffer
C. w=20 over 100,000 values: global 20,000 | 2 shards without halo 10,939 | with a 19-value halo 20,000
```

### 2.2 Listing 2.2 — C++23

```cpp
// sliding_windows.cpp - two pointers and window invariants: when they hold, when they silently don't, streams and shards.
#include <algorithm>
#include <cstdint>
#include <expected>
#include <format>
#include <functional>
#include <limits>
#include <map>
#include <print>
#include <ranges>
#include <span>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
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

std::string show(std::span<const int> a) {
    std::string s = "[";
    for (std::size_t i = 0; i < a.size(); ++i) s += std::format("{}{}", i ? ", " : "", a[i]);
    return s + "]";
}

// ======================================================================= 1. longest window with <= k distinct
// Contest habit: index an array by char. A std::string holds UTF-8 BYTES, so one emoji is four "characters".
int cp_at_most_k_distinct(std::string_view s, int k) {
    int cnt[256] = {};
    int distinct = 0, best = 0;
    for (std::size_t l = 0, r = 0; r < s.size(); ++r) {
        if (cnt[static_cast<unsigned char>(s[r])]++ == 0) ++distinct;
        while (distinct > k)
            if (--cnt[static_cast<unsigned char>(s[l++])] == 0) --distinct;
        best = std::max(best, static_cast<int>(r - l + 1));
    }
    return best;
}

// Decode UTF-8 into code points; malformed input is an error value, not a crash or a silent U+FFFD.
std::expected<Vec, std::string> decode_utf8(std::string_view s) {
    Vec out;
    for (std::size_t i = 0; i < s.size();) {
        auto b0 = static_cast<unsigned char>(s[i]);
        int len = b0 < 0x80 ? 1 : (b0 >> 5) == 0x6 ? 2 : (b0 >> 4) == 0xE ? 3 : (b0 >> 3) == 0x1E ? 4 : 0;
        if (len == 0 || i + static_cast<std::size_t>(len) > s.size())
            return std::unexpected(std::format("bad UTF-8 at byte {}", i));
        int cp = len == 1 ? b0 : b0 & (0x7F >> len);
        for (int j = 1; j < len; ++j) {
            auto b = static_cast<unsigned char>(s[i + static_cast<std::size_t>(j)]);
            if ((b >> 6) != 0x2) return std::unexpected(std::format("bad continuation at byte {}", i + static_cast<std::size_t>(j)));
            cp = (cp << 6) | (b & 0x3F);
        }
        out.push_back(cp);
        i += static_cast<std::size_t>(len);
    }
    return out;
}

// Longest window of tokens with at most k distinct values. Invariant: [l, r] is valid after the inner loop.
// Correct because validity is monotone: every sub-window of a valid window is valid. O(n) expected, O(k) space.
int at_most_k_distinct(std::span<const int> t, int k) {
    std::unordered_map<int, int> cnt;
    int best = 0;
    for (std::size_t l = 0, r = 0; r < t.size(); ++r) {
        ++cnt[t[r]];
        while (cnt.size() > static_cast<std::size_t>(k)) {
            if (--cnt[t[l]] == 0) cnt.erase(t[l]);
            ++l;
        }
        best = std::max(best, static_cast<int>(r - l + 1));
    }
    return best;
}

int at_most_k_distinct_oracle(std::span<const int> t, int k) {
    int best = 0;
    for (std::size_t i = 0; i < t.size(); ++i) {
        std::unordered_set<int> seen;
        for (std::size_t j = i; j < t.size(); ++j) {
            seen.insert(t[j]);
            if (seen.size() <= static_cast<std::size_t>(k)) best = std::max(best, static_cast<int>(j - i + 1));
        }
    }
    return best;
}

// ======================================================================= 2. LC 1004: max ones with k flips
int max_ones_shrinking(std::span<const int> a, int k) {
    int best = 0, zeros = 0;
    for (std::size_t l = 0, r = 0; r < a.size(); ++r) {
        zeros += a[r] == 0;
        while (zeros > k) zeros -= a[l++] == 0;
        best = std::max(best, static_cast<int>(r - l + 1));
    }
    return best;
}

// Non-shrinkable: the window grows or slides, never shrinks, so its final size IS the best size seen.
int max_ones_non_shrinking(std::span<const int> a, int k) {
    std::size_t l = 0;
    int zeros = 0;
    for (std::size_t r = 0; r < a.size(); ++r) {
        zeros += a[r] == 0;
        if (zeros > k) zeros -= a[l++] == 0;
    }
    return static_cast<int>(a.size() - l);
}

int max_ones_oracle(std::span<const int> a, int k) {
    int best = 0;
    for (std::size_t i = 0; i < a.size(); ++i) {
        int zeros = 0;
        for (std::size_t j = i; j < a.size(); ++j) {
            zeros += a[j] == 0;
            if (zeros <= k) best = std::max(best, static_cast<int>(j - i + 1));
        }
    }
    return best;
}

// ======================================================================= 3. LC 76: minimum window covering a multiset
struct Window {
    std::size_t start = 0, end = 0;  // half-open; {0, 0} = none
    friend bool operator==(const Window&, const Window&) = default;
};

Window min_window(std::span<const int> text, std::span<const int> need) {
    if (need.empty()) return {};
    std::unordered_map<int, int> missing;
    for (int x : need) ++missing[x];
    std::size_t still_missing = need.size(), best_l = 0, best_r = std::numeric_limits<std::size_t>::max();
    for (std::size_t l = 0, r = 0; r < text.size(); ++r) {
        if (auto it = missing.find(text[r]); it != missing.end()) {
            if (it->second > 0) --still_missing;
            --it->second;  // negative = surplus copies inside the window
        }
        while (still_missing == 0) {
            if (r + 1 - l < best_r - best_l) best_l = l, best_r = r + 1;
            if (auto it = missing.find(text[l]); it != missing.end()) {
                if (it->second == 0) ++still_missing;
                ++it->second;
            }
            ++l;
        }
    }
    return best_r == std::numeric_limits<std::size_t>::max() ? Window{} : Window{best_l, best_r};
}

Window min_window_oracle(std::span<const int> text, std::span<const int> need) {
    if (need.empty()) return {};
    std::map<int, int> want;
    for (int x : need) ++want[x];
    for (std::size_t len = 1; len <= text.size(); ++len)
        for (std::size_t i = 0; i + len <= text.size(); ++i) {
            std::map<int, int> have;
            for (std::size_t j = i; j < i + len; ++j) ++have[text[j]];
            if (std::ranges::all_of(want, [&](const auto& e) { return have[e.first] >= e.second; })) return {i, i + len};
        }
    return {};
}

// ======================================================================= 4. LC 560: count subarrays with sum k
// Contest habit: two pointers. Valid ONLY if every value is > 0, so that the window sum is strictly monotone.
std::int64_t cp_count_sum_k(std::span<const int> a, std::int64_t k) {
    std::int64_t count = 0, sum = 0;
    for (std::size_t l = 0, r = 0; r < a.size(); ++r) {
        sum += a[r];
        while (sum > k && l <= r) sum -= a[l++];
        if (sum == k && l <= r) ++count;
    }
    return count;
}

// prefix[j] - prefix[i] == k  <=>  prefix[i] == prefix[j] - k: count earlier prefixes. O(n) expected, any signs.
std::int64_t count_sum_k(std::span<const int> a, std::int64_t k) {
    std::unordered_map<std::int64_t, std::int64_t> seen{{0, 1}};
    std::int64_t prefix = 0, count = 0;
    for (int v : a) {
        prefix += v;
        if (auto it = seen.find(prefix - k); it != seen.end()) count += it->second;
        ++seen[prefix];
    }
    return count;
}

std::int64_t count_sum_k_oracle(std::span<const int> a, std::int64_t k) {
    std::int64_t count = 0;
    for (std::size_t i = 0; i < a.size(); ++i) {
        std::int64_t s = 0;
        for (std::size_t j = i; j < a.size(); ++j) count += (s += a[j]) == k;
    }
    return count;
}

template <class Fails>
Vec shrink(Vec a, Fails fails) {  // drop elements / move toward 0
    for (bool progress = true; progress;) {
        progress = false;
        std::vector<Vec> cands;
        for (std::size_t i = 0; i < a.size(); ++i) {
            Vec c = a;
            c.erase(c.begin() + static_cast<std::ptrdiff_t>(i));
            cands.push_back(std::move(c));
        }
        for (std::size_t i = 0; i < a.size(); ++i) {
            if (a[i] == 0) continue;
            Vec c = a;
            c[i] -= a[i] > 0 ? 1 : -1;
            cands.push_back(std::move(c));
        }
        for (auto& c : cands)
            if (fails(c)) {
                a = std::move(c);
                progress = true;
                break;
            }
    }
    return a;
}

// ======================================================================= Extension B: bounded memory over a stream
// Max sum of any w consecutive values of an unbounded input range: O(w) memory (ring buffer), O(1) per element.
template <std::ranges::input_range R>
std::int64_t max_window_sum(R&& stream, std::size_t w) {
    std::vector<int> ring(w);
    std::int64_t sum = 0, best = std::numeric_limits<std::int64_t>::min();
    std::size_t i = 0;
    for (int v : stream) {
        std::size_t slot = i % w;
        sum += v - (i >= w ? ring[slot] : 0);
        ring[slot] = v;
        if (i + 1 >= w) best = std::max(best, sum);
        ++i;
    }
    return best;
}

// ======================================================================= Extension C: shards need a halo
// Shard s owns windows STARTING in [lo_s, hi_s) and therefore needs a[lo_s, hi_s + w - 1): a halo of w - 1.
std::int64_t sharded_max_window_sum(std::span<const int> a, std::size_t w, std::size_t shards, bool halo) {
    std::int64_t best = std::numeric_limits<std::int64_t>::min();
    for (std::size_t s = 0; s < shards; ++s) {
        std::size_t lo = a.size() * s / shards, hi = a.size() * (s + 1) / shards;
        std::size_t end = halo ? std::min(a.size(), hi + w - 1) : hi;
        if (end - lo >= w) best = std::max(best, max_window_sum(a.subspan(lo, end - lo), w));
    }
    return best;
}

int hash_value(std::uint64_t i) { return static_cast<int>((i * 2654435761ULL >> 16) % 2001) - 1000; }

int main() {
    const std::string text = "ab\xF0\x9F\x98\x80\xF0\x9F\x98\x80\xF0\x9F\x98\x80" "b";  // "ab" + three U+1F600 + "b"
    auto cps = decode_utf8(text);
    std::println("1. \"ab\" + 3 x U+1F600 + \"b\": {} UTF-8 bytes, {} code points; longest run with <= 1 distinct:",
                 text.size(), cps->size());
    std::println("   contest (bytes) {}   L7 (code points) {}   oracle {}", cp_at_most_k_distinct(text, 1),
                 at_most_k_distinct(*cps, 1), at_most_k_distinct_oracle(*cps, 1));
    std::println("   decode_utf8 of a truncated emoji -> {}", decode_utf8(text.substr(0, 4)).error());

    SplitMix64 r{21};
    constexpr int kTrials = 20'000;
    int ok_distinct = 0, ok_ones = 0, ok_min = 0;
    for (int t = 0; t < kTrials; ++t) {
        Vec a = r.array(12, 0, 3);
        int k = r.next_int(4);
        ok_distinct += at_most_k_distinct(a, k) == at_most_k_distinct_oracle(a, k);
        Vec bits = r.array(12, 0, 1);
        int f = r.next_int(3);
        int want = max_ones_oracle(bits, f);
        ok_ones += max_ones_shrinking(bits, f) == want && max_ones_non_shrinking(bits, f) == want;
        Vec need = r.array(3, 0, 3);
        ok_min += min_window(a, need) == min_window_oracle(a, need);
    }
    std::println("   at-most-k-distinct vs oracle: {}/{}", ok_distinct, kTrials);
    std::println("2. LC 1004 shrinking == non-shrinking == oracle: {}/{}", ok_ones, kTrials);
    std::println("3. LC 76 min window (shortest, then leftmost) vs oracle: {}/{}", ok_min, kTrials);

    std::println("4. LC 560 count subarrays with sum k: two pointers vs prefix-sum map, both vs oracle");
    const char* names[] = {"values 1..3 (positive)", "values 0..3 (zeros)", "values -3..3 (negatives)"};
    const int ranges[3][2] = {{1, 3}, {0, 3}, {-3, 3}};
    for (int g = 0; g < 3; ++g) {
        int cp_ok = 0, l7_ok = 0;
        Vec first_bad;
        bool have_bad = false;
        int bad_k = 0;
        for (int t = 0; t < kTrials; ++t) {
            Vec a = r.array(10, ranges[g][0], ranges[g][1]);
            int k = r.next_int(10) - 3;
            auto want = count_sum_k_oracle(a, k);
            l7_ok += count_sum_k(a, k) == want;
            if (cp_count_sum_k(a, k) == want) ++cp_ok;
            else if (!have_bad) first_bad = a, bad_k = k, have_bad = true;
        }
        std::string ce;
        if (have_bad) {
            Vec m = shrink(first_bad, [&](const Vec& c) { return cp_count_sum_k(c, bad_k) != count_sum_k_oracle(c, bad_k); });
            ce = std::format("  shrunk: {}, k={} -> two pointers {}, truth {}", show(m), bad_k, cp_count_sum_k(m, bad_k),
                             count_sum_k_oracle(m, bad_k));
        }
        std::println("   {:<26} two pointers {:5}/{}  prefix map {:5}/{}{}", names[g], cp_ok, kTrials, l7_ok, kTrials, ce);
    }

    constexpr std::size_t w = 1'000;
    auto stream = std::views::iota(std::uint64_t{0}, std::uint64_t{10'000'000}) | std::views::transform(hash_value);
    std::println("B. max sum of {} consecutive values over a 10,000,000-value stream: {} using a {}-int ring buffer", w,
                 max_window_sum(stream, w), w);

    Vec data(100'000);
    for (std::size_t i = 0; i < data.size(); ++i) data[i] = hash_value(i);
    for (std::size_t i = 49'990; i < 50'010; ++i) data[i] = 1'000;  // the best window straddles the shard boundary
    std::println("C. w=20 over 100,000 values: global {} | 2 shards without halo {} | with a {}-value halo {}",
                 max_window_sum(data, 20), sharded_max_window_sum(data, 20, 2, false), 19,
                 sharded_max_window_sum(data, 20, 2, true));
}
```

**Output, both compilers (verified; GCC shown, Clang identical):**

```text
1. "ab" + 3 x U+1F600 + "b": 15 UTF-8 bytes, 6 code points; longest run with <= 1 distinct:
   contest (bytes) 1   L7 (code points) 3   oracle 3
   decode_utf8 of a truncated emoji -> bad UTF-8 at byte 2
   at-most-k-distinct vs oracle: 20000/20000
2. LC 1004 shrinking == non-shrinking == oracle: 20000/20000
3. LC 76 min window (shortest, then leftmost) vs oracle: 20000/20000
4. LC 560 count subarrays with sum k: two pointers vs prefix-sum map, both vs oracle
   values 1..3 (positive)     two pointers 20000/20000  prefix map 20000/20000
   values 0..3 (zeros)        two pointers 16762/20000  prefix map 20000/20000  shrunk: [0, 2, 1], k=3 -> two pointers 1, truth 2
   values -3..3 (negatives)   two pointers 11933/20000  prefix map 20000/20000  shrunk: [3, -2], k=1 -> two pointers 0, truth 1
B. max sum of 1000 consecutive values over a 10,000,000-value stream: 4536 using a 1000-int ring buffer
C. w=20 over 100,000 values: global 20000 | 2 shards without halo 10939 | with a 19-value halo 20000
```

---

## 3. What the results show

* **Units vs code points.** `"ab" + 3 × U+1F600 + "b"` is 9 UTF-16 chars, 15 UTF-8 bytes and 6 code points. The longest run with at most one distinct value is the three emoji (3). The contest versions return **1** in both languages: each emoji is two different units (high and low surrogate) or four different bytes, so no two adjacent "characters" are equal. The C++ decoder also reports malformed input as a value (`bad UTF-8 at byte 2` for a truncated emoji) rather than inventing code points.
* **Shrinkable and non-shrinkable agree, as the proof says.** 20,000/20,000 random binary arrays and flip budgets give identical answers to brute force. The `if`-instead-of-`while` version is correct by the invariant in §1.2, not by luck.
* **Minimum cover** (shortest, then leftmost window containing a multiset): 20,000/20,000 against an exhaustive oracle. The tie rule ("leftmost among the shortest") is part of the contract and is tested.
* **Two pointers on "sum exactly k" fail exactly where monotonicity fails.** With strictly positive values: 20,000/20,000. With zeros: 16,762/20,000. With negatives: 11,933/20,000. The shrinker reduces the failures to `[0, 2, 1], k = 3`. Both `[0, 2, 1]` and `[2, 1]` sum to 3, but the left pointer only moves when the sum *exceeds* k. It counts the first window and never tries the second, because dropping the zero doesn't change the sum. With negatives it shrinks to `[3, -2], k = 1`. The only valid window is the whole array, and the left pointer had already dropped the 3 when the sum first exceeded 1. The prefix-sum map is correct on all 60,000. *A wrong algorithm that is right 60–84% of the time on random inputs and 100% on the problem's sample is exactly what interviews are designed to catch.*
* **Streaming (Extension B).** The maximum sum over any 1,000 consecutive values of a 10,000,000-value stream is computed with a 1,000-entry ring buffer: memory `O(w)`, independent of the stream length. The same function accepts a Java `PrimitiveIterator.OfInt` or any C++ `input_range` (here a lazy `iota | transform`), so nothing is materialized.
* **Sharding (Extension C).** The best 20-wide window was planted across the boundary of two shards. Without a halo the shards report 10,939; with each shard reading `w − 1 = 19` values past its end, they report the true 20,000. The rule: **a shard owns the windows that start in its range, and so needs `w − 1` elements of the next shard.**

---

## 4. The last 10 minutes: Extensions A, B and C

### 4.1 Extension A — "64 threads feed events into these windows"

Sliding windows in production are usually **per key**: requests per user in the last minute (rate limiting), errors per host in the last five minutes (alerting), distinct items per session. Three designs, in increasing order of throughput:

| Design | Mechanism | Cost / failure mode |
|---|---|---|
| Shared map of windows, one lock | `synchronized` around `Map<Key, Deque<Long>>` | Every event serializes; File 1.1 measured one lock at about 2× *slower* than a single thread |
| Per-key lock | `ConcurrentHashMap<Key, Window>`, `synchronized (window)` | Contention only on hot keys. **Take the timestamp inside the lock**: a timestamp taken before the lock can arrive out of order, and a deque that assumes sorted timestamps evicts wrongly |
| Partition by key to single-writer workers | `hash(key) mod T` → one queue per worker; each worker owns its keys' windows without locks | The Kafka-partition / actor model: no locks, per-key ordering for free; a hot key saturates one worker (salt it, or approximate with a sketch) |

For **aggregates that form a monoid** (sum, count, max, min), each thread can keep its own window over a shared time grid and the query combines them: the sum of per-thread sums, the max of per-thread maxima. **Distinct counts are not decomposable**: the union of two sets of size 10 is not 20. Merging per-thread windows needs the sets themselves, or a mergeable sketch such as HyperLogLog (Folder 06).

### 4.2 Extension B — "the input is an infinite stream"

* **Count-based windows** need `O(w)` memory: a ring buffer, as measured. For *sum*, keep the running sum. For *max/min*, use a monotonic deque (File 2). For any associative aggregate, use the two-stacks queue (File 2).
* **Time-based windows** ("last 60 seconds") evict by timestamp rather than count, so memory is proportional to the event *rate × window*. A 60 s window over 1 M events/s is 60 M entries. The fix is **panes**: aggregate per second, keep 60 pane summaries, and evict whole panes. Memory becomes `O(window / pane)`, exact at pane granularity.
* **Out-of-order events** (network delays, multiple producers) break "evict everything older than t − w". Streaming systems use **watermarks**: an assertion that no event older than `t` will arrive. Windows are finalized only when the watermark passes their end, and late events either update the result or go to a side output. That is the vocabulary to use in the interview (Flink and Beam both work this way).
* **At-most-k-distinct over a stream** needs a count map of size at most `k + 1`: still bounded. **Exact distinct count over a 1-hour window** at high cardinality is not bounded, so name the trade-off and reach for a sketch.

### 4.3 Extension C — "the sequence is split across 100 machines"

* **Windows per key:** partition by key. Every window lives on one machine and nothing crosses the network after the shuffle.
* **Windows over a global order** (positions in a genome, time across a sharded log): give each shard a **halo** of `w − 1` elements from its successor. The shard owns windows *starting* in its range. Measured: without the halo the planted best window was invisible to both shards (10,939 vs 20,000). Cost: `(S − 1)(w − 1)` extra elements, negligible when `w` is much smaller than the shard size.
* **Variable-length windows have no fixed halo.** For "longest window with at most k distinct" the window can be arbitrarily long, so no fixed halo suffices. The general tool is a **summary per shard** that composes associatively. For example, the classic maximum-subarray monoid `(total, best prefix, best suffix, best inside)` combines two adjacent shards in `O(1)`. Folder 03's segment trees are this idea stored in a tree. For at-most-k-distinct the per-shard summary is the boundary runs, the longest k-distinct prefix and suffix and their value sets. Whether a compact summary exists is the real design question to discuss.
* **"Exactly k" and counting problems** shard naturally with prefix sums. Each shard computes its total. A prefix scan over the S totals gives every shard its starting offset, and then each shard counts locally against a hash map seeded with the boundary prefixes it needs. Prefix sums are the canonical two-pass distributed algorithm.

---

## 5. Failure modes

| # | Failure | Symptom | Prevention |
|---|---|---|---|
| F1 | Two pointers without monotone validity | Plausible counts, wrong by a few; passes positive-only samples | State the closure property aloud; if it fails, prefix sums + hash map or `atMost(k) − atMost(k−1)` |
| F2 | Counting units or bytes as characters | Wrong lengths and distinct counts on emoji, CJK, accents | Decide the token type; window over code points or ids |
| F3 | Shrinking past the answer in "shortest window" | Records a window that no longer covers the target | Record *before* shrinking; shrink while valid |
| F4 | `while` vs `if` confusion | Longest-window answer too small | Use the non-shrinkable form only with its invariant: final `n − l` |
| F5 | `int` window sums | Overflow on long windows of large values | `long` sums, stated bound |
| F6 | Materializing a stream to run a window | `O(n)` memory, or impossible | Ring buffer `O(w)`; panes for time windows |
| F7 | Timestamps taken outside the per-key lock | Out-of-order deque; wrong eviction | Timestamp inside the critical section, or a single writer per key |
| F8 | Sharded windows without halo | Windows crossing shard boundaries never evaluated | Halo of `w − 1`, or composable shard summaries |
| F9 | Merging per-thread distinct counts by addition | Overcounts shared elements | Merge sets, or use HyperLogLog |

---

## 6. Bar-raiser chains

<details><summary><b>Q1 · "Why is your two-pointer solution O(n) and not O(n²)?"</b></summary>

**Initial Prompt.** The candidate wrote a `for r` loop containing a `while` that moves `l`.

**L5 Answer.** "Each pointer only moves forward."

**Why L5 Stalls.** It states the conclusion, not the reason. *Why* `l` never needs to move backward is the correctness argument, and without it the candidate can't tell when the pattern breaks.

**L7 Answer.** "Validity is closed under shrinking: if a window has at most k distinct values, so does every sub-window. So the smallest valid left end is non-decreasing as `r` grows. Once a left end is invalid for `r`, it's invalid for every larger `r`. That's why `l` never moves back, and each pointer moves at most n times. The same argument tells me when *not* to use it, for example sums with negative numbers."
</details>

<details><summary><b>Q2 · "Count subarrays that sum to k."</b></summary>

**Initial Prompt.** LeetCode 560; the sample array is all positive.

**L5 Answer.** Two pointers: expand right, shrink while the sum exceeds k, count when equal.

**Why L5 Stalls.** Passes the sample and fails on zeros (counts `[0,2,1]` but not `[2,1]` for k = 3) and negatives (`[3,-2]`, k = 1, gives 0). Measured on random inputs: 16–40% wrong.

**L7 Answer.** "Two pointers needs the window sum to be monotone, which needs positive values. The problem allows any integer, so I'd use prefix sums: a subarray `(i, j]` sums to k exactly when `prefix[i] = prefix[j] − k`. Keep a hash map from prefix value to how many times it has occurred and add the count at each step. O(n) expected, any signs. Sums in `long`. And the map starts with `{0: 1}` for subarrays that begin at index 0."
</details>

<details><summary><b>Q3 · "Longest substring with at most k distinct characters — does your solution handle Unicode?"</b></summary>

**Initial Prompt.** The candidate used `int[26]` or `int[256]`.

**L5 Answer.** "I'll make the array 65,536 long."

**Why L5 Stalls.** A Java `char` is a UTF-16 code unit, so an emoji is still two "characters" with different values. The bigger array changes nothing; measured, the answer is 1 instead of 3.

**L7 Answer.** "First: what's a character? If it's a code point, I'll iterate `codePoints()` and window over ints with a `HashMap` count, since the alphabet is unbounded. If the product means user-perceived characters, it's grapheme clusters, which need a segmentation library. The window algorithm doesn't change; only the tokenizer in front of it does. In C++ the input is UTF-8 bytes, so I'd decode first and return an error for malformed input."
</details>

<details><summary><b>Q4 · "You used `if` where most people use `while`. Is that a bug?"</b></summary>

**Initial Prompt.** The candidate wrote the non-shrinkable window for LeetCode 1004 or 424.

**L5 Answer.** "It's a known trick, it passes."

**Why L5 Stalls.** "Known trick" is not a correctness argument. The interviewer is checking that the candidate understands *why* the window may be temporarily invalid.

**L7 Answer.** "It's deliberate. For a *longest* window I never need a window shorter than the best so far, so when the window becomes invalid I slide it instead of shrinking it. The invariant is that the window's size always equals the best length seen. It may be invalid at times, but only after a valid window of that size existed. At the end, `n − l` is the answer. I checked it against brute force: identical on 20,000 random cases."
</details>

<details><summary><b>Q5 · "Now the events come from 64 producer threads."</b></summary>

**Initial Prompt.** Extension A for a per-user sliding-window rate limiter.

**L5 Answer.** "Make the map a ConcurrentHashMap."

**Why L5 Stalls.** A concurrent map makes the *map* safe, not each window's deque, and it doesn't fix out-of-order timestamps.

**L7 Answer.** "The map holds windows, and each window needs its own mutual exclusion, or a single writer. I'd partition users across worker queues by `hash(user)`, so each window has exactly one writer and needs no lock, and per-user ordering comes free. If I keep shared windows instead, the timestamp must be taken inside the per-window lock, otherwise two threads can append out of order and eviction by 'oldest first' is wrong. Hot users are the remaining risk: one partition saturates, so I'd watch per-partition lag."
</details>

<details><summary><b>Q6 · "The input is an unbounded stream. Change anything?"</b></summary>

**Initial Prompt.** Extension B for a fixed-size window aggregate.

**L5 Answer.** "Keep all values in a list and slide over it."

**Why L5 Stalls.** Memory grows with the stream, and the window only ever needs the last `w` values.

**L7 Answer.** "Memory must be O(w): a ring buffer for count windows, plus the running aggregate. Sum is O(1) per event; max needs the monotonic deque or the two-stacks queue. For time windows I'd aggregate into panes, per-second buckets, so memory is window/pane regardless of rate. With out-of-order events I'd finalize windows on a watermark and decide explicitly what happens to late events."
</details>

<details><summary><b>Q7 · "The array is split across 100 machines. Max sum of any w consecutive elements?"</b></summary>

**Initial Prompt.** Extension C.

**L5 Answer.** "Each machine computes its max window; take the max of those."

**Why L5 Stalls.** Windows that straddle a boundary belong to no machine. Measured: the planted best window was missed entirely (10,939 vs 20,000).

**L7 Answer.** "Each machine owns the windows that *start* in its range, so it needs the first `w − 1` elements of the next machine: a halo. Then the max of local maxima is exact, at a cost of `(S−1)(w−1)` extra elements. If `w` is huge, or the window isn't fixed-length, I'd switch to composable summaries per shard, like the maximum-subarray monoid of (total, best prefix, best suffix, best), and combine them in order."
</details>

<details><summary><b>Q8 · "Count subarrays with exactly k distinct values."</b></summary>

**Initial Prompt.** LeetCode 992.

**L5 Answer.** Tries a single two-pointer window for "exactly k" and gets stuck on when to shrink.

**Why L5 Stalls.** "Exactly k" isn't closed under shrinking or growing, so no single window works.

**L7 Answer.** "Exactly k equals at-most-k minus at-most-(k−1). Each 'at most' count is a monotone window: for each `r`, the number of valid windows ending at `r` is `r − l + 1`. Two O(n) passes, no new invariant to prove, and the at-most function is the one I've already tested."
</details>

---

## 7. Checklist

* [ ] State the closure property (under shrinking for longest, under growing for shortest) before writing the loop.
* [ ] Negative numbers or zeros with a sum target → prefix sums + hash map, not two pointers.
* [ ] "Exactly k" → `atMost(k) − atMost(k−1)`.
* [ ] Decide the token type (code points, ids); never index arrays by `char` on real text.
* [ ] Shortest window: record before shrinking; tie rule stated (leftmost).
* [ ] Non-shrinkable window only with its invariant; answer `n − l`.
* [ ] `long` sums; validated `k`, `w`.
* [ ] Extension A: per-key windows; single writer per key or a per-window lock with the timestamp inside it; distinct counts aren't additive.
* [ ] Extension B: ring buffer `O(w)`; panes for time windows; watermarks for disorder.
* [ ] Extension C: partition by key; halo of `w − 1` for global order; composable summaries otherwise.

---

## 8. References

* LeetCode anchors: [76 Minimum Window Substring](https://leetcode.com/problems/minimum-window-substring/), [340 Longest Substring with At Most K Distinct Characters](https://leetcode.com/problems/longest-substring-with-at-most-k-distinct-characters/), [424 Longest Repeating Character Replacement](https://leetcode.com/problems/longest-repeating-character-replacement/), [560 Subarray Sum Equals K](https://leetcode.com/problems/subarray-sum-equals-k/), [992 Subarrays with K Different Integers](https://leetcode.com/problems/subarrays-with-k-different-integers/), [1004 Max Consecutive Ones III](https://leetcode.com/problems/max-consecutive-ones-iii/), [167 Two Sum II](https://leetcode.com/problems/two-sum-ii-input-array-is-sorted/)
* Java SE 21 API, `String.codePoints` and the UTF-16 representation — <https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/lang/String.html>; `Character` (supplementary characters) — <https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/lang/Character.html>
* The Unicode Standard, UTF-8 encoding form (chapter 3) — <https://www.unicode.org/versions/latest/>; UAX #29, *Unicode Text Segmentation* (grapheme clusters) — <https://www.unicode.org/reports/tr29/>
* Apache Flink documentation, *Timely Stream Processing* (event time and watermarks) — <https://nightlies.apache.org/flink/flink-docs-stable/docs/concepts/time/>
* J. Li, D. Maier, K. Tufte, V. Papadimos, P. A. Tucker, *No pane, no gain: efficient evaluation of sliding-window aggregates over data streams*, SIGMOD Record 34(1), 2005 — DOI 10.1145/1058150.1058158

*Folder 02:* [02 — monotonic stack and deque](02-monotonic-stack-and-deque-submatrix-histograms-and-window-extrema.md) · [03 — exchange arguments, matroids and regret greedy](03-exchange-arguments-matroids-interval-scheduling-and-regret-greedy-heaps.md) · [Folder 01](../01-L7-Coding-Rubric-and-Hardware-Complexity-Physics/01-how-bar-raisers-grade-l5-vs-l6-vs-l7-in-45-minute-coding-rounds.md)
