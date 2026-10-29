# Bloom Filters, Count-Min Sketch, HyperLogLog and Reservoir Sampling

> **Folder 06 · File 2 of 2** — four probabilistic structures, each with an error guarantee you can state, a measurement that matches it, a classic implementation bug that silently voids it, and a merge operation that makes it shardable for free.
> **Languages:** Java 21 (`--release 21 -Xlint:all -Werror`, JDK 25.0.4.1) and C++23 (GCC 16.2 and Clang 21.1, `-O2`, warnings as errors).

| Listing | File | What it proves |
|---|---|---|
| 6.3 | `Sketches.java` | Bloom: FPR 0.0101 vs theory 0.0100; "k copies of one hash" gives 0.098; OR-merge equals the whole filter. Count-Min never underestimates and holds its ε·N guarantee on 100% of keys; conservative update cuts max error 3×; merge exact. HyperLogLog within 0.6% at 1 k–10 M with 16 KB; union via register max. Reservoir sampling uniform (χ² = 76.6 on 99 dof) vs the off-by-one (χ² = 1,146) |
| 6.4 | `prob_sketches.cpp` | The same; every number identical to Java |

**Verification.** Both listings were extracted from this file, compiled and run. Everything is **Output (verified)**: fully deterministic, identical across Java and both C++ builds apart from number formatting.

---

## 0. Orientation

Sketches are the standard answer to Extension B ("unbounded stream, bounded memory") and Extension C ("merge across 100 machines"), so interviewers use them to probe whether a candidate knows **what is guaranteed** and **what silently breaks the guarantee**.

| Contest / blog habit | What breaks | L7 replacement |
|---|---|---|
| k Bloom hashes from `hashCode() + i` or the same function k times | FPR 0.098 instead of 0.010 (measured) | Double hashing h₁ + i·h₂ from a well-mixed 64-bit hash (Kirsch–Mitzenmacher) |
| Bloom sized by guess | Unknown false-positive rate | m = −n ln p / (ln 2)², k = (m/n) ln 2; state p in the API |
| Count-Min as "approximate counts" | Can't say how approximate | ε, δ → width ⌈e/ε⌉, depth ⌈ln 1/δ⌉; one-sided error, bounded by ε·N with probability 1 − δ |
| Exact `HashSet` for distinct counts at scale | Memory O(n) | HyperLogLog: 1.04/√m relative error in m bytes, mergeable |
| `rand(0..i-1)` in reservoir sampling | Biased sample (χ² 1,146 vs 99 expected) | `rand(0..i)`; test uniformity statistically |
| One shared sketch for 64 threads with locks | Contention | Per-thread sketches, merged: merge is exact for Bloom, CMS and HLL |

---

## 1. First principles

### 1.1 Bloom filter

An m-bit array and k hash probes per key. Insert sets k bits; a query answers "maybe present" only if all k bits are set. **No false negatives, ever.** After inserting n keys, a given bit is still 0 with probability ≈ e^{−kn/m}, so a non-member's k probes all hit set bits with probability **p ≈ (1 − e^{−kn/m})ᵏ**. That's minimized at k = (m/n) ln 2, giving m/n ≈ 1.44 log₂(1/p) bits per key: about 9.6 bits for 1%. The analysis needs the k probes to be (close to) independent. Kirsch and Mitzenmacher showed that `h₁ + i·h₂` from two halves of one good hash is enough. Using the **same** hash k times collapses the filter to k = 1 at k times the cost: measured FPR 0.098 instead of 0.010.

**Merge:** two filters with identical m, k and hash functions merge by bitwise OR into exactly the filter of the union. There's no deletion (it would need counting Bloom filters or cuckoo filters).

### 1.2 Count-Min sketch

d rows of w counters, one hash per row. An update adds to one counter per row, and the estimate is the **minimum** over rows. Counters only over-count (collisions add), so **estimate ≥ truth always**. In a single row the expected excess is ≤ N/w. By Markov's inequality, the excess exceeds e·N/w with probability ≤ 1/e per row, and the minimum over d independent rows fails only if all rows fail: probability ≤ e^{−d}. Choosing **w = ⌈e/ε⌉, d = ⌈ln(1/δ)⌉** gives *estimate ≤ truth + ε·N with probability ≥ 1 − δ.* Memory is O((1/ε) log(1/δ)), independent of the number of distinct keys.

**Conservative update** raises each row's counter only up to `min_estimate + n`, never past it. It still never underestimates, and in practice it cuts the error substantially (3× here), but it **loses exact mergeability**: summing two conservative sketches is still an upper bound, not the same sketch. Plain CMS merges by element-wise addition, exactly.

### 1.3 HyperLogLog

Hash each element and use the first p bits to pick one of m = 2ᵖ registers. The register keeps the maximum, over its elements, of "position of the first 1-bit" in the remaining bits. A run of r leading zeros suggests about 2ʳ distinct elements, and averaging the registers' evidence harmonically gives an estimate with **standard error ≈ 1.04/√m**: 0.81% for m = 16,384 one-byte registers, 16 KB total, for any cardinality up to billions. Small cardinalities use **linear counting** on the number of empty registers. **Merge** is the register-wise max, exactly the sketch of the union, which makes HLL the standard distributed distinct counter.

### 1.4 Reservoir sampling

Keep a uniform random sample of k items from a stream of unknown length in O(k) memory. Keep the first k; for item i (0-based), draw j uniformly from **0..i** and replace slot j if j < k. By induction, after n items every item is in the sample with probability exactly k/n. Drawing from **0..i−1** admits item i with probability k/i instead of k/(i+1). The early items are over-replaced and the sample is biased toward later items: measured, item 0 was kept 8.9% of the time instead of 10%. A χ² test over 100,000 runs makes the bias unmistakable (1,146 against about 99 for a fair sampler).

---

## 2. The listings

### 2.1 Listing 6.3 — Java

```java
// Sketches.java - Bloom, Count-Min, HyperLogLog, reservoir sampling: measured against theory, and merged across shards.
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

public final class Sketches {

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

    /** 64-bit finalizer (SplitMix64 / Murmur3 fmix style): every input bit affects every output bit. */
    static long mix(long x) {
        x = (x ^ (x >>> 30)) * 0xBF58476D1CE4E5B9L;
        x = (x ^ (x >>> 27)) * 0x94D049BB133111EBL;
        return x ^ (x >>> 31);
    }

    // ===================================================================== 1. Bloom filter
    /** m bits, k probes by double hashing (Kirsch-Mitzenmacher): h1 + i*h2 is as good as k independent hashes. */
    static final class Bloom {
        final long[] bits;
        final int m, k;
        final boolean sameProbe;  // the bug: k "different" hashes that are all the same function

        Bloom(int m, int k, boolean sameProbe) { this.m = m; this.k = k; this.sameProbe = sameProbe; bits = new long[(m + 63) / 64]; }

        private int probe(long key, int i) {
            long h = mix(key), h2 = mix(h ^ 0x5DEECE66DL) | 1;
            return (int) Long.remainderUnsigned(sameProbe ? h : h + i * h2, m);
        }
        void add(long key) { for (int i = 0; i < k; i++) { int b = probe(key, i); bits[b >>> 6] |= 1L << b; } }
        boolean mightContain(long key) {
            for (int i = 0; i < k; i++) { int b = probe(key, i); if ((bits[b >>> 6] & 1L << b) == 0) return false; }
            return true;
        }
        Bloom merge(Bloom o) { Bloom r = new Bloom(m, k, sameProbe); for (int i = 0; i < bits.length; i++) r.bits[i] = bits[i] | o.bits[i]; return r; }
    }

    // ===================================================================== 2. Count-Min sketch
    /** d rows of w counters. Estimate = min over rows: never under, over by <= eps*N with prob >= 1-delta. */
    static final class CountMin {
        final long[][] c;
        final int w, d;
        final boolean conservative;

        CountMin(int w, int d, boolean conservative) { this.w = w; this.d = d; this.conservative = conservative; c = new long[d][w]; }

        private int col(long key, int row) { return (int) Long.remainderUnsigned(mix(key + 0x9E3779B97F4A7C15L * (row + 1)), w); }
        void add(long key, long n) {
            if (!conservative) { for (int r = 0; r < d; r++) c[r][col(key, r)] += n; return; }
            long target = estimate(key) + n;                     // conservative update: raise only counters below target
            for (int r = 0; r < d; r++) { int j = col(key, r); if (c[r][j] < target) c[r][j] = target; }
        }
        long estimate(long key) { long e = Long.MAX_VALUE; for (int r = 0; r < d; r++) e = Math.min(e, c[r][col(key, r)]); return e; }
        CountMin merge(CountMin o) {  // exact for plain CMS; conservative sketches don't merge exactly (not done here)
            CountMin m = new CountMin(w, d, false);
            for (int r = 0; r < d; r++) for (int j = 0; j < w; j++) m.c[r][j] = c[r][j] + o.c[r][j];
            return m;
        }
    }

    // ===================================================================== 3. HyperLogLog
    /** 2^p registers keep the max "leading zeros + 1" seen; harmonic mean + small-range correction. Error ~1.04/sqrt(2^p). */
    static final class HyperLogLog {
        final byte[] reg;
        final int p;

        HyperLogLog(int p) { this.p = p; reg = new byte[1 << p]; }
        void add(long key) {
            long h = mix(key);
            int idx = (int) (h >>> (64 - p));
            int rank = Long.numberOfLeadingZeros(h << p | (1L << (p - 1))) + 1;
            if (rank > reg[idx]) reg[idx] = (byte) rank;
        }
        double estimate() {
            int m = reg.length, zeros = 0;
            double sum = 0;
            for (byte r : reg) { sum += Math.pow(2, -r); if (r == 0) zeros++; }
            double alpha = 0.7213 / (1 + 1.079 / m), e = alpha * m * m / sum;
            return e <= 2.5 * m && zeros > 0 ? m * Math.log((double) m / zeros) : e;  // linear counting for small sets
        }
        HyperLogLog merge(HyperLogLog o) { HyperLogLog r = new HyperLogLog(p); for (int i = 0; i < reg.length; i++) r.reg[i] = (byte) Math.max(reg[i], o.reg[i]); return r; }
    }

    // ===================================================================== 4. reservoir sampling
    /** Algorithm R: keep the first k; item i (0-based) replaces slot j = rand(0..i) if j < k. P(kept) = k/n for all. */
    static long[] reservoir(SplitMix64 r, int n, int k, boolean offByOne) {
        long[] res = new long[k];
        for (int i = 0; i < n; i++) {
            if (i < k) { res[i] = i; continue; }
            int j = r.nextInt(offByOne ? i : i + 1);   // the bug: rand(0..i-1) admits item i with prob k/i, not k/(i+1)
            if (j < k) res[j] = i;
        }
        return res;
    }

    public static void main(String[] args) {
        SplitMix64 r = new SplitMix64(151);
        int n = 100_000;
        double p = 0.01;
        int m = (int) Math.ceil(-n * Math.log(p) / (Math.log(2) * Math.log(2))), k = (int) Math.round((double) m / n * Math.log(2));
        Bloom good = new Bloom(m, k, false), bad = new Bloom(m, k, true), half1 = new Bloom(m, k, false), half2 = new Bloom(m, k, false);
        for (long key = 0; key < n; key++) { good.add(key); bad.add(key); (key % 2 == 0 ? half1 : half2).add(key); }
        int probes = 1_000_000, fpGood = 0, fpBad = 0, missed = 0;
        for (long key = 0; key < n; key++) if (!good.mightContain(key)) missed++;
        for (long key = n; key < n + probes; key++) { if (good.mightContain(key)) fpGood++; if (bad.mightContain(key)) fpBad++; }
        double theory = Math.pow(1 - Math.exp(-(double) k * n / m), k);
        System.out.printf("1. Bloom, n=%,d, m=%,d bits (%.2f bits/key), k=%d: false negatives %d | FPR %.4f (theory %.4f) |"
                + " k copies of ONE hash: FPR %.4f | OR of two half-filters == whole filter: %b%n", n, m, (double) m / n, k, missed,
                (double) fpGood / probes, theory, (double) fpBad / probes, Arrays.equals(half1.merge(half2).bits, good.bits));

        double eps = 0.001, delta = 0.01;
        int w = (int) Math.ceil(Math.E / eps), d = (int) Math.ceil(Math.log(1 / delta));
        CountMin cms = new CountMin(w, d, false), cu = new CountMin(w, d, true), s1 = new CountMin(w, d, false), s2 = new CountMin(w, d, false);
        Map<Long, Long> truth = new HashMap<>();
        long total = 2_000_000;
        for (long i = 0; i < total; i++) {
            double u = (r.next() >>> 11) * 0x1.0p-53;
            long key = (long) (100_000 * u * u * u);          // skewed: a few heavy keys, a long tail
            cms.add(key, 1); cu.add(key, 1); (i % 2 == 0 ? s1 : s2).add(key, 1);
            truth.merge(key, 1L, Long::sum);
        }
        long within = 0, maxErr = 0, maxErrCu = 0, keys = 0;
        for (long key = 0; key < 100_000; key++) {
            long t = truth.getOrDefault(key, 0L), e = cms.estimate(key), ec = cu.estimate(key);
            if (e < t || ec < t) throw new AssertionError("Count-Min underestimated");
            keys++;
            if (e - t <= eps * total) within++;
            maxErr = Math.max(maxErr, e - t);
            maxErrCu = Math.max(maxErrCu, ec - t);
        }
        boolean merged = Arrays.deepEquals(s1.merge(s2).c, cms.c);
        System.out.printf("2. Count-Min, eps=%.3f delta=%.2f -> %d x %,d counters (%,d KB) for N=%,d events: never under;"
                + " %.2f%% of keys within eps*N=%,d (guarantee >= 99%%) | max error %,d, conservative update %,d | merge of halves exact: %b%n",
                eps, delta, d, w, (long) d * w * 8 / 1024, total, 100.0 * within / keys, (long) (eps * total), maxErr, maxErrCu, merged);

        System.out.print("3. HyperLogLog p=14 (16,384 registers, 16 KB, expected error ~0.81%):");
        long next = 1L << 40;
        for (int card : new int[] {1_000, 100_000, 10_000_000}) {
            HyperLogLog h = new HyperLogLog(14);
            for (int i = 0; i < card; i++) h.add(next + i);
            next += card;
            System.out.printf(" n=%,d -> %,.0f (%+.2f%%) |", card, h.estimate(), 100 * (h.estimate() - card) / card);
        }
        HyperLogLog a = new HyperLogLog(14), b = new HyperLogLog(14);
        for (long i = 0; i < 3_000_000; i++) a.add(i);
        for (long i = 2_000_000; i < 5_000_000; i++) b.add(i);
        System.out.printf(" union of two shards (3 M + 3 M, 1 M shared) -> %,.0f (truth 5,000,000)%n", a.merge(b).estimate());

        int trials = 100_000, sn = 100, sk = 10;
        double[] good4 = new double[2];
        for (int variant = 0; variant < 2; variant++) {
            long[] hits = new long[sn];
            for (int t = 0; t < trials; t++) for (long x : reservoir(r, sn, sk, variant == 1)) hits[(int) x]++;
            double expected = (double) trials * sk / sn, chi = 0;
            for (long h : hits) chi += (h - expected) * (h - expected) / expected;
            good4[variant] = chi;
            if (variant == 1) {
                System.out.printf("4. reservoir k=%d of n=%d, %,d trials: Algorithm R chi^2 = %.1f (99 dof, ~99 expected) |"
                        + " rand(0..i-1) off-by-one chi^2 = %.1f; item %d kept %.4f vs item %d kept %.4f (truth %.2f)%n", sk, sn, trials,
                        good4[0], chi, 0, (double) hits[0] / trials, sn - 1, (double) hits[sn - 1] / trials, (double) sk / sn);
            }
        }
    }
}
```

**Output (verified):**

```text
1. Bloom, n=100,000, m=958,506 bits (9.59 bits/key), k=7: false negatives 0 | FPR 0.0101 (theory 0.0100) | k copies of ONE hash: FPR 0.0984 | OR of two half-filters == whole filter: true
2. Count-Min, eps=0.001 delta=0.01 -> 5 x 2,719 counters (106 KB) for N=2,000,000 events: never under; 100.00% of keys within eps*N=2,000 (guarantee >= 99%) | max error 1,178, conservative update 398 | merge of halves exact: true
3. HyperLogLog p=14 (16,384 registers, 16 KB, expected error ~0.81%): n=1,000 -> 1,005 (+0.52%) | n=100,000 -> 99,605 (-0.39%) | n=10,000,000 -> 9,967,955 (-0.32%) | union of two shards (3 M + 3 M, 1 M shared) -> 5,035,838 (truth 5,000,000)
4. reservoir k=10 of n=100, 100,000 trials: Algorithm R chi^2 = 76.6 (99 dof, ~99 expected) | rand(0..i-1) off-by-one chi^2 = 1145.9; item 0 kept 0.0892 vs item 99 kept 0.1013 (truth 0.10)
```

### 2.2 Listing 6.4 — C++23

```cpp
// prob_sketches.cpp - Bloom, Count-Min, HyperLogLog, reservoir sampling: measured against theory, and merged across shards.
#include <algorithm>
#include <bit>
#include <cmath>
#include <cstdint>
#include <limits>
#include <numbers>
#include <print>
#include <stdexcept>
#include <unordered_map>
#include <vector>

using u64 = std::uint64_t;
using i64 = std::int64_t;

struct SplitMix64 {
    u64 state;
    u64 next() noexcept {
        u64 z = (state += 0x9E3779B97F4A7C15ULL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }
    u64 below(u64 bound) noexcept { return next() % bound; }
};

u64 mix(u64 x) {  // 64-bit finalizer: every input bit affects every output bit
    x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9ULL;
    x = (x ^ (x >> 27)) * 0x94D049BB133111EBULL;
    return x ^ (x >> 31);
}

// ======================================================================= 1. Bloom filter
// m bits, k probes by double hashing (Kirsch-Mitzenmacher). same_probe = the bug: k "hashes" that are one function.
class Bloom {
public:
    Bloom(u64 m, int k, bool same_probe) : m_(m), k_(k), same_(same_probe), bits_((m + 63) / 64) {}
    void add(u64 key) {
        for (int i = 0; i < k_; ++i) set(probe(key, static_cast<u64>(i)));
    }
    bool might_contain(u64 key) const {
        for (int i = 0; i < k_; ++i)
            if (!test(probe(key, static_cast<u64>(i)))) return false;
        return true;
    }
    Bloom merged(const Bloom& o) const {
        Bloom r(m_, k_, same_);
        for (std::size_t i = 0; i < bits_.size(); ++i) r.bits_[i] = bits_[i] | o.bits_[i];
        return r;
    }
    friend bool operator==(const Bloom& a, const Bloom& b) { return a.bits_ == b.bits_; }

private:
    u64 probe(u64 key, u64 i) const {
        u64 h = mix(key), h2 = mix(h ^ 0x5DEECE66DULL) | 1;
        return (same_ ? h : h + i * h2) % m_;
    }
    void set(u64 b) { bits_[b >> 6] |= u64{1} << (b & 63); }
    bool test(u64 b) const { return (bits_[b >> 6] >> (b & 63) & 1) != 0; }
    u64 m_;
    int k_;
    bool same_;
    std::vector<u64> bits_;
};

// ======================================================================= 2. Count-Min sketch
class CountMin {
public:
    CountMin(std::size_t w, std::size_t d, bool conservative) : w_(w), d_(d), cons_(conservative), c_(d * w) {}
    void add(u64 key, i64 n) {
        if (!cons_) {
            for (std::size_t r = 0; r < d_; ++r) c_[r * w_ + col(key, r)] += n;
            return;
        }
        i64 target = estimate(key) + n;  // conservative update: raise only counters below the new estimate
        for (std::size_t r = 0; r < d_; ++r) c_[r * w_ + col(key, r)] = std::max(c_[r * w_ + col(key, r)], target);
    }
    i64 estimate(u64 key) const {
        i64 e = std::numeric_limits<i64>::max();
        for (std::size_t r = 0; r < d_; ++r) e = std::min(e, c_[r * w_ + col(key, r)]);
        return e;
    }
    CountMin merged(const CountMin& o) const {  // exact for plain CMS
        CountMin m(w_, d_, false);
        for (std::size_t i = 0; i < c_.size(); ++i) m.c_[i] = c_[i] + o.c_[i];
        return m;
    }
    friend bool operator==(const CountMin& a, const CountMin& b) { return a.c_ == b.c_; }

private:
    std::size_t col(u64 key, std::size_t row) const { return static_cast<std::size_t>(mix(key + 0x9E3779B97F4A7C15ULL * (row + 1)) % w_); }
    std::size_t w_, d_;
    bool cons_;
    std::vector<i64> c_;
};

// ======================================================================= 3. HyperLogLog
class HyperLogLog {
public:
    explicit HyperLogLog(int p) : p_(p), reg_(std::size_t{1} << p) {}
    void add(u64 key) {
        u64 h = mix(key);
        auto idx = static_cast<std::size_t>(h >> (64 - p_));
        auto rank = static_cast<std::uint8_t>(std::countl_zero(h << p_ | (u64{1} << (p_ - 1))) + 1);
        reg_[idx] = std::max(reg_[idx], rank);
    }
    double estimate() const {
        double m = static_cast<double>(reg_.size()), sum = 0;
        int zeros = 0;
        for (auto r : reg_) sum += std::pow(2.0, -static_cast<double>(r)), zeros += r == 0;
        double alpha = 0.7213 / (1 + 1.079 / m), e = alpha * m * m / sum;
        return e <= 2.5 * m && zeros > 0 ? m * std::log(m / zeros) : e;  // linear counting for small sets
    }
    HyperLogLog merged(const HyperLogLog& o) const {
        HyperLogLog r(p_);
        for (std::size_t i = 0; i < reg_.size(); ++i) r.reg_[i] = std::max(reg_[i], o.reg_[i]);
        return r;
    }

private:
    int p_;
    std::vector<std::uint8_t> reg_;
};

// ======================================================================= 4. reservoir sampling
std::vector<u64> reservoir(SplitMix64& r, u64 n, u64 k, bool off_by_one) {
    std::vector<u64> res(k);
    for (u64 i = 0; i < n; ++i) {
        if (i < k) {
            res[i] = i;
            continue;
        }
        u64 j = r.below(off_by_one ? i : i + 1);  // the bug: rand(0..i-1) admits item i with prob k/i, not k/(i+1)
        if (j < k) res[j] = i;
    }
    return res;
}

int main() {
    SplitMix64 r{151};
    constexpr u64 n = 100'000;
    double p = 0.01, ln2 = std::numbers::ln2;
    auto m = static_cast<u64>(std::ceil(-static_cast<double>(n) * std::log(p) / (ln2 * ln2)));
    int k = static_cast<int>(std::lround(static_cast<double>(m) / static_cast<double>(n) * ln2));
    Bloom good(m, k, false), bad(m, k, true), half1(m, k, false), half2(m, k, false);
    for (u64 key = 0; key < n; ++key) good.add(key), bad.add(key), (key % 2 == 0 ? half1 : half2).add(key);
    constexpr u64 probes = 1'000'000;
    u64 fp_good = 0, fp_bad = 0, missed = 0;
    for (u64 key = 0; key < n; ++key) missed += !good.might_contain(key);
    for (u64 key = n; key < n + probes; ++key) fp_good += good.might_contain(key), fp_bad += bad.might_contain(key);
    double theory = std::pow(1 - std::exp(-k * static_cast<double>(n) / static_cast<double>(m)), k);
    std::println("1. Bloom, n={}, m={} bits ({:.2f} bits/key), k={}: false negatives {} | FPR {:.4f} (theory {:.4f}) | k copies of ONE hash:"
                 " FPR {:.4f} | OR of two half-filters == whole filter: {}", n, m, static_cast<double>(m) / n, k, missed,
                 static_cast<double>(fp_good) / probes, theory, static_cast<double>(fp_bad) / probes, half1.merged(half2) == good);

    double eps = 0.001, delta = 0.01;
    auto w = static_cast<std::size_t>(std::ceil(std::numbers::e / eps)), d = static_cast<std::size_t>(std::ceil(std::log(1 / delta)));
    CountMin cms(w, d, false), cu(w, d, true), s1(w, d, false), s2(w, d, false);
    std::unordered_map<u64, i64> truth;
    constexpr i64 total = 2'000'000;
    for (i64 i = 0; i < total; ++i) {
        double u = static_cast<double>(r.next() >> 11) * 0x1.0p-53;
        auto key = static_cast<u64>(100'000 * u * u * u);  // skewed: a few heavy keys, a long tail
        cms.add(key, 1), cu.add(key, 1), (i % 2 == 0 ? s1 : s2).add(key, 1);
        ++truth[key];
    }
    i64 within = 0, max_err = 0, max_err_cu = 0, keys = 0;
    for (u64 key = 0; key < 100'000; ++key) {
        i64 t = truth.contains(key) ? truth[key] : 0, e = cms.estimate(key), ec = cu.estimate(key);
        if (e < t || ec < t) throw std::logic_error("Count-Min underestimated");
        ++keys;
        within += static_cast<double>(e - t) <= eps * total;
        max_err = std::max(max_err, e - t), max_err_cu = std::max(max_err_cu, ec - t);
    }
    std::println("2. Count-Min, eps={:.3f} delta={:.2f} -> {} x {} counters ({} KB) for N={} events: never under; {:.2f}% of keys within"
                 " eps*N={} (guarantee >= 99%) | max error {}, conservative update {} | merge of halves exact: {}", eps, delta, d, w,
                 d * w * 8 / 1024, total, 100.0 * static_cast<double>(within) / static_cast<double>(keys),
                 static_cast<i64>(eps * total), max_err, max_err_cu, s1.merged(s2) == cms);

    std::print("3. HyperLogLog p=14 (16,384 registers, 16 KB, expected error ~0.81%):");
    u64 next = u64{1} << 40;
    for (u64 card : {u64{1'000}, u64{100'000}, u64{10'000'000}}) {
        HyperLogLog h(14);
        for (u64 i = 0; i < card; ++i) h.add(next + i);
        next += card;
        double est = h.estimate();
        std::print(" n={} -> {:.0f} ({:+.2f}%) |", card, est, 100 * (est - static_cast<double>(card)) / static_cast<double>(card));
    }
    HyperLogLog a(14), b(14);
    for (u64 i = 0; i < 3'000'000; ++i) a.add(i);
    for (u64 i = 2'000'000; i < 5'000'000; ++i) b.add(i);
    std::println(" union of two shards (3 M + 3 M, 1 M shared) -> {:.0f} (truth 5,000,000)", a.merged(b).estimate());

    constexpr u64 trials = 100'000, sn = 100, sk = 10;
    double chi_good = 0;
    for (int variant = 0; variant < 2; ++variant) {
        std::vector<u64> hits(sn);
        for (u64 t = 0; t < trials; ++t)
            for (u64 x : reservoir(r, sn, sk, variant == 1)) ++hits[x];
        double expected = static_cast<double>(trials * sk) / sn, chi = 0;
        for (u64 h : hits) chi += (static_cast<double>(h) - expected) * (static_cast<double>(h) - expected) / expected;
        if (variant == 0) chi_good = chi;
        else
            std::println("4. reservoir k={} of n={}, {} trials: Algorithm R chi^2 = {:.1f} (99 dof, ~99 expected) | rand(0..i-1) off-by-one"
                         " chi^2 = {:.1f}; item 0 kept {:.4f} vs item {} kept {:.4f} (truth {:.2f})", sk, sn, trials, chi_good, chi,
                         static_cast<double>(hits[0]) / trials, sn - 1, static_cast<double>(hits[sn - 1]) / trials,
                         static_cast<double>(sk) / sn);
    }
}
```

**Output, both compilers (verified; GCC shown, Clang identical):**

```text
1. Bloom, n=100000, m=958506 bits (9.59 bits/key), k=7: false negatives 0 | FPR 0.0101 (theory 0.0100) | k copies of ONE hash: FPR 0.0984 | OR of two half-filters == whole filter: true
2. Count-Min, eps=0.001 delta=0.01 -> 5 x 2719 counters (106 KB) for N=2000000 events: never under; 100.00% of keys within eps*N=2000 (guarantee >= 99%) | max error 1178, conservative update 398 | merge of halves exact: true
3. HyperLogLog p=14 (16,384 registers, 16 KB, expected error ~0.81%): n=1000 -> 1005 (+0.52%) | n=100000 -> 99605 (-0.39%) | n=10000000 -> 9967955 (-0.32%) | union of two shards (3 M + 3 M, 1 M shared) -> 5035838 (truth 5,000,000)
4. reservoir k=10 of n=100, 100000 trials: Algorithm R chi^2 = 76.6 (99 dof, ~99 expected) | rand(0..i-1) off-by-one chi^2 = 1145.9; item 0 kept 0.0892 vs item 99 kept 0.1013 (truth 0.10)
```

---

## 3. What the results show

* **Theory matches measurement.** Bloom: 958,506 bits (9.59 bits/key), k = 7, measured FPR 0.0101 against 0.0100 predicted, zero false negatives. HLL: −0.39% to +0.52% error at 10³–10⁷ elements with 16 KB, inside the expected ±0.81% standard error. Count-Min: every estimate ≥ truth, and 100% of keys within ε·N = 2,000 (the guarantee asks for ≥ 99%).
* **Each classic bug is caught by a number:** one hash used k times (FPR × 9.7); the off-by-one reservoir (χ² × 15, with a visible bias on early items).
* **Merges are exact where the theory says so:** Bloom halves OR to the whole filter, bit for bit; Count-Min halves add to the whole sketch, counter for counter; two overlapping HLL shards (3 M + 3 M, 1 M shared) merge to an estimate of 5,035,838 for a true union of 5,000,000 (+0.7%).
* **Conservative update** cut Count-Min's worst over-estimate from 1,178 to 398 on a skewed stream, at the price of exact mergeability.
* **Java and C++ produce identical numbers** for every sketch: same hash finalizer, same SplitMix64 stream, same parameters.

---

## 4. The last 10 minutes: Extensions A, B and C

Sketches are where all three extensions have the same answer: **mergeability**.

### 4.1 Extension A — "64 threads update the sketch"

* **Per-thread sketches, merged on read.** Bloom (OR), Count-Min (add) and HLL (max) merges are exact, so each thread owns a private sketch with zero contention, and a query merges them. That costs `threads × sketch size` per query: 64 × 16 KB for HLL is trivial.
* **Shared sketch with atomics:** Count-Min counters as atomic adds (commutative; Folder 03 File 2's lesson), HLL registers as atomic max (CAS loop), Bloom bits as atomic OR (`fetch_or`). Exact final state in any interleaving, no locks. Readers may see a partially applied update: a Bloom query concurrent with an insert can say "absent" for a key being inserted. That's the same non-linearizability discussion again.
* **Reservoir sampling across threads:** one reservoir per thread, then merge by **weighted** sampling: pick each slot from thread t's reservoir with probability proportional to the number of items thread t saw. Naively concatenating reservoirs is biased toward small streams.

### 4.2 Extension B — "an unbounded stream"

This is what sketches are for. Memory is fixed at construction: m bits (Bloom), d × w counters (CMS), 2ᵖ bytes (HLL), k items (reservoir), whatever the stream length. Two caveats worth naming:

* **Bloom filters fill up.** The FPR depends on n, so a filter sized for 10⁶ keys that receives 10⁷ approaches FPR 1. Use scalable Bloom filters (a chain of filters with tightening p) or time-windowed filters that rotate.
* **Count-Min error grows with N** (ε·N). Over an unbounded stream, absolute error grows without bound. Use time-decayed sketches or windowed sketches (a ring of per-minute sketches merged on query), the "panes" idea from Folder 02.

### 4.3 Extension C — "100 machines"

* **Distinct users across 100 shards:** each shard keeps an HLL; the coordinator takes the register-wise max. A 16 KB message per shard yields the global distinct count within about 0.8%, measured exact as a merge. Summing per-shard distinct counts would count users active on several shards multiple times.
* **Heavy hitters across shards:** sum Count-Min sketches (exact merge), then query candidate keys. Or combine with Space-Saving (Folder 01 File 1) to find the candidates.
* **Distributed membership:** Bloom filters gossiped between nodes (OR-merge) answer "might node X have key K?". Cassandra and other LSM stores keep one per SSTable to skip disk reads.
* **Parameters are part of the protocol:** sketches merge only if they share m, k, w, d, p **and hash functions**. A fleet upgrade that changes the hash seed silently breaks every merge, so version the sketch format.

---

## 5. Failure modes

| # | Failure | Symptom | Prevention |
|---|---|---|---|
| F1 | k Bloom probes from one hash | FPR × ~10 (0.098 vs 0.010) | Double hashing from a mixed 64-bit hash |
| F2 | Bloom past its design n | FPR → 1 | Size for the real n; scalable or rotating filters |
| F3 | CMS without (ε, δ) | Error unknown | Width and depth derived from ε, δ; state the guarantee |
| F4 | Merging conservative-update CMS as if exact | Upper bound, not the union sketch | Keep plain CMS for merging, or accept the bound |
| F5 | Summing per-shard distinct counts | Overcount of shared elements | HLL merge (register max) |
| F6 | Reservoir `rand(0..i−1)` | Biased sample | `rand(0..i)`; χ² test |
| F7 | Concatenating per-thread reservoirs | Bias toward small streams | Weighted merge |
| F8 | Sketch parameters or hash changed across versions | Silent merge corruption | Version the format; refuse to merge mismatches |

---

## 6. Bar-raiser chains

<details><summary><b>Q1 · "Avoid disk reads for keys that don't exist."</b></summary>

**Initial Prompt.** An LSM-tree store; most lookups are misses.

**L5 Answer.** "Keep a HashSet of keys in memory."

**Why L5 Stalls.** Memory O(keys × key size): billions of keys don't fit.

**L7 Answer.** "A Bloom filter per SSTable. For a 1% false-positive rate it needs about 9.6 bits per key and 7 probes, generated by double hashing from one 64-bit hash. I measured 1.01% against 1.00% predicted. A 'no' is definite, so 99% of misses skip the disk read. I'd size it for the file's actual key count and expose the target FPR as a parameter."
</details>

<details><summary><b>Q2 · "Your Bloom filter uses k hash functions. Which ones?"</b></summary>

**Initial Prompt.** Implementation probe.

**L5 Answer.** "`hash(key) + i`" or "`hashCode()` k times with different seeds of a weak hash."

**Why L5 Stalls.** Correlated probes break the independence the FPR formula assumes. In the extreme, the same hash k times measured FPR 0.098, 10× the target.

**L7 Answer.** "One strong 64-bit hash, split into h₁ and h₂ (h₂ forced odd), with probes h₁ + i·h₂ mod m. Kirsch and Mitzenmacher proved that gives the same asymptotic FPR as k independent hashes. The quality of the base hash matters, so I use a finalizer that mixes every input bit, not Java's `hashCode` directly."
</details>

<details><summary><b>Q3 · "Count the top queries in a 100 TB log with 100 MB of RAM."</b></summary>

**Initial Prompt.** Extension B.

**L5 Answer.** "Hash map of counts."

**Why L5 Stalls.** Distinct queries exceed RAM.

**L7 Answer.** "A Count-Min sketch for frequencies plus a small heap of candidates. With ε = 0.001 and δ = 0.01 it's 5 × 2,719 counters, about 100 KB, and every estimate is within 0.1% of the stream length of the truth with 99% probability, never below it. Candidates come from a Space-Saving summary or from items whose estimate crosses a threshold. Shards each keep a sketch and the sketches add exactly."
</details>

<details><summary><b>Q4 · "How many distinct users visited across all 100 data centres today?"</b></summary>

**Initial Prompt.** Extension C.

**L5 Answer.** "Each data centre counts distinct users; sum them."

**Why L5 Stalls.** Users visiting several data centres are counted several times.

**L7 Answer.** "HyperLogLog per data centre: 16 KB each, about 0.8% standard error. The global count is the HLL of the register-wise max of all 100 sketches, which is exactly the sketch of the union. Duplicates across data centres are handled for free. I measured an overlapping two-shard union within 0.7%. The parameters and hash function must match fleet-wide, so the format gets a version number."
</details>

<details><summary><b>Q5 · "Pick 1,000 random log lines from a stream of unknown length."</b></summary>

**Initial Prompt.** Reservoir sampling.

**L5 Answer.** Algorithm R, with the random index drawn from 0..i−1.

**Why L5 Stalls.** Off by one: item i is admitted with probability k/i, so early items are over-replaced. Measured: χ² of 1,146 against about 99 expected; item 0 kept 8.9% of the time instead of 10%.

**L7 Answer.** "Keep the first k; for the i-th item (0-based), draw j uniformly from 0..i inclusive and replace slot j if j < k. By induction every item ends up with probability k/n. I'd test it statistically: many runs, count how often each position is kept, and run a χ² test against uniform. The listing's correct version gives 76.6 on 99 degrees of freedom."
</details>

<details><summary><b>Q6 · "Conservative update is better — always use it?"</b></summary>

**Initial Prompt.** Count-Min design probe.

**L5 Answer.** "Yes, lower error."

**Why L5 Stalls.** It gives up exact mergeability and only works for positive updates.

**L7 Answer.** "It cut the worst over-estimate from 1,178 to 398 on a skewed stream, so for a single-node, insert-only sketch, yes. But it isn't linear any more. Two conservative sketches don't add up to the union's sketch, and deletions (negative updates) are unsafe. For anything sharded or merged I'd keep plain Count-Min, or accept that the merged result is only an upper bound."
</details>

<details><summary><b>Q7 · "64 threads add to one HyperLogLog."</b></summary>

**Initial Prompt.** Extension A.

**L5 Answer.** "Synchronize add."

**Why L5 Stalls.** One lock serializes the hot path.

**L7 Answer.** "Per-thread HLLs, merged with a register-wise max when someone reads: 16 KB per thread, no contention, exact merge. If memory is tight, one shared array with an atomic max per register (a CAS loop) is also exact in the final state. Either way the read side does a merge or a scan; there's no need to lock writers."
</details>

<details><summary><b>Q8 · "After a deploy, the merged distinct count jumped 2×."</b></summary>

**Initial Prompt.** A production incident.

**L5 Answer.** "Traffic must have doubled."

**Why L5 Stalls.** It doesn't consider that sketch merges depend on identical parameters and hash functions.

**L7 Answer.** "I'd first check whether the new version changed the HLL's precision or hash seed. Merging sketches built with different hash functions is meaningless: the same user lands in different registers, so the union looks like two populations. Sketch formats need a version header, and merges must refuse mismatched versions. Then I'd recompute from raw data for a day to confirm."
</details>

---

## 7. Checklist

* [ ] Bloom: m and k from n and p; double hashing from a strong 64-bit hash; size for real n.
* [ ] Count-Min: w = ⌈e/ε⌉, d = ⌈ln 1/δ⌉; one-sided error; conservative update only when not merging.
* [ ] HLL: precision p ↔ 1.04/√2ᵖ; linear counting for small n; merge by max.
* [ ] Reservoir: `rand(0..i)`; weighted merge across threads; χ² test.
* [ ] Every sketch: state its guarantee; measure it; version the format.
* [ ] Extension A: per-thread sketches + exact merge, or atomic cells.
* [ ] Extension B: bounded memory by construction; windowed or rotating sketches for unbounded time.
* [ ] Extension C: merge across shards (OR / add / max); identical parameters fleet-wide.

---

## 8. References

* B. H. Bloom, *Space/Time Trade-offs in Hash Coding with Allowable Errors*, CACM 13(7), 1970 — DOI 10.1145/362686.362692
* A. Kirsch, M. Mitzenmacher, *Less Hashing, Same Performance: Building a Better Bloom Filter*, ESA 2006 — DOI 10.1007/11841036_42
* G. Cormode, S. Muthukrishnan, *An Improved Data Stream Summary: The Count-Min Sketch and its Applications*, J. Algorithms 55(1), 2005 — DOI 10.1016/j.jalgor.2003.12.001
* P. Flajolet, É. Fusy, O. Gandouet, F. Meunier, *HyperLogLog: the analysis of a near-optimal cardinality estimation algorithm*, AofA 2007 — <https://algo.inria.fr/flajolet/Publications/FlFuGaMe07.pdf>
* S. Heule, M. Nunkesser, A. Hall, *HyperLogLog in Practice*, EDBT 2013 — DOI 10.1145/2452376.2452456
* J. S. Vitter, *Random Sampling with a Reservoir*, ACM TOMS 11(1), 1985 — DOI 10.1145/3147.3165
* Apache DataSketches (production sketch library) — <https://datasketches.apache.org/>

*Folder 06:* [01 — KMP, Z, Manacher, Rabin–Karp](01-kmp-prefix-automaton-z-algorithm-manacher-and-rabin-karp-double-hash.md)
