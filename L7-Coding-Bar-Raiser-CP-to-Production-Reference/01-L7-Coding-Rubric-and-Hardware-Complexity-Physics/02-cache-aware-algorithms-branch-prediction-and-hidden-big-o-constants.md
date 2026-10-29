# Cache-Aware Algorithms, Branch Prediction and Hidden Big-O Constants

> **Folder 01 · File 2 of 3** — why two algorithms with the same Big-O differ by 10–100× on real hardware, measured, and how to say it in an interview.
> **Languages:** Java 21 (`--release 21`, run on JDK 25.0.4.1) and C++23 (GCC 16.2 and Clang 21.1, `-O2`, flags as in File 01).
> **Machine for every number:** Intel i5-11260H, 6 cores / 12 threads, L1d 48 KiB and L2 1.25 MiB per core, L3 12 MiB shared, 16 GB RAM, Windows 11.

| Listing | File | What it measures |
|---|---|---|
| 2.1 | `MemoryHierarchy.java` | Dependent loads, independent loads and sequential streaming over 12 working sets (16 KiB → 256 MiB) |
| 2.2 | `memory_hierarchy.cpp` | The same, plus the surprise that GCC `-O2` does not vectorize the streaming loop |
| 2.3 | `BranchCost.java` | One `if` in four shapes, on sorted vs shuffled data: what a mispredict costs, and whether the JIT removes the branch |
| 2.4 | `branch_cost.cpp` | The same on two compilers that make opposite decisions |
| 2.5 | `SearchLayouts.java` | `lower_bound` four ways: `Arrays.binarySearch`, ternary, mask arithmetic, Eytzinger layout |
| 2.6 | `search_layouts.cpp` | Five ways, adding software prefetch: 5–10× apart on the same `O(log n)` |
| 2.7 | `HashConstants.java` | Boxed chained `HashMap` vs a flat open-addressing table: ns/op, bytes/entry, and the latency tail of "amortized O(1)" |
| 2.8 | `hash_constants.cpp` | `std::unordered_map` vs a flat table, with an allocator that counts bytes |

**Verification.** Every listing was extracted from this file, compiled and run. Every output here is **one measured run**: the shapes, ratios and correctness checks reproduce, the exact nanoseconds do not. Where several development runs disagreed, the text gives the range.

---

## 0. Orientation

Big-O counts operations in the **RAM model**: every memory access costs 1. On the machine you are interviewing about, an access costs anywhere from about 1 ns (L1 hit) to about 130 ns (DRAM miss, dependent). A mispredicted branch costs several nanoseconds, and an allocation can cost a garbage-collection pause of 100+ ms. Big-O is still the right *first* question, because no constant factor rescues `O(n²)` at `n = 10⁷`. But between algorithms of the **same** complexity, or across a `log n` factor, constants decide.

A Staff interviewer rarely asks "what is the L2 latency". They ask "why is your hash map slow", "how would you make this search faster", or "your solution is optimal — why might the `O(n log n)` one beat it in production?" The answer they are listening for has three parts: **what the hardware does, the measured magnitude, and the layout or code change that exploits it.**

### 0.1 The bridge: contest belief → measured reality → L7 statement

| Contest belief | What this file measured | L7 statement |
|---|---|---|
| "10⁸ simple operations per second" | 1.2 ns (L1) to 140 ns (DRAM) per **dependent** load: a 100× spread for the same loop | "Operation counts are only meaningful with an access pattern attached" |
| "A linked structure is as good as an array" | Pointer chasing is latency-bound; independent loads to the same addresses ran 10–15× faster | "I'd make the next address computable without waiting on the previous load" |
| "Branches are free" | A data-dependent branch on random data: about 3 ns per element extra, about 6 ns per mispredict | "Make the branch predictable, make it data, or let the compiler — and then measure, because it may refuse" |
| "Binary search is optimal" | `O(log n)` search ranged from 9 to 1,350 ns per query, and up to 10× apart at the **same** n, depending on layout and codegen | "Layout first: Eytzinger + prefetch for read-mostly; B-tree-style nodes for disk" |
| "HashMap is O(1)" | Boxed `HashMap` put 222 ns vs flat table 70 ns; `std::unordered_map` 309–439 ns vs 33–35 ns; single inserts up to 319 ms | "O(1) amortized hides allocation, pointer chasing, rehash and GC tails; pre-size and flatten" |
| "The compiler will optimize it" | GCC `-O2` left a sum unvectorized (3× slower than Clang); Clang turned *branch-free source* back into a branch | "Source shape is a request, not a guarantee. Check the assembly or measure" |

---

## 1. First principles

### 1.1 The memory hierarchy is a latency ladder

Data moves in **64-byte cache lines**. A load that misses every level pays the full trip to DRAM and back. The CPU hides that only if it has other independent work. Listing 2.1 measured these figures on this laptop:

| Level (this CPU) | Size | Dependent-load latency measured | Rough multiple of L1 |
|---|---|---|---|
| L1d | 48 KiB per core | 1.2–1.3 ns | 1× |
| L2 | 1.25 MiB per core | 3.4–5.3 ns | 3–4× |
| L3 | 12 MiB shared | 13–15 ns at 2 MiB; 26–76 ns at 4 MiB (varied by run) | 10–60× |
| DRAM | 16 GB | 104–140 ns | about 100× |
| SSD / network (for scale; not measured here) | — | tens of µs / hundreds of µs within a datacentre | 10⁴–10⁵× |

Three hardware mechanisms explain most of what follows:

1. **Spatial locality.** Touching one byte brings in 64. Code that uses all 64 bytes it pays for (arrays, struct-of-arrays) gets 16 `int`s per miss; pointer-based structures often get one useful field.
2. **Hardware prefetching.** The core detects sequential and strided streams and fetches ahead, so a linear scan of DRAM-resident data runs at **bandwidth** (15–30 GB/s here), not latency.
3. **Memory-level parallelism (MLP).** An out-of-order core can keep roughly 10+ L1 misses in flight ⚠ (the exact number of fill buffers varies by microarchitecture). That only helps if the addresses are known: `a[idx[i]]` exposes many independent misses, while `i = a[i]` exposes exactly one.

The I/O model of Aggarwal and Vitter (1988) generalizes this. Memory has size `M`, data moves in blocks of size `B`, and **cost = number of block transfers**. A scan costs `N/B`; sorting costs `(N/B) log_{M/B}(N/B)`. The same model applies whether the "block" is a 64-byte line, a 4 KiB page, a 1 MiB SSD read or a network RPC. That is why this file's reasoning carries straight into Extensions B and C, and into Folder 07. **Cache-oblivious** algorithms (Frigo et al., 1999) get optimal block transfers at every level at once without knowing `B` or `M`, typically through recursive divide-and-conquer layouts.

### 1.2 Branch prediction is speculation

A modern core fetches and executes far ahead of the instruction that decides a branch, using a predictor trained on past outcomes. If the guess is wrong, the speculative work is thrown away. That costs roughly 15–20 cycles of pipeline refill, plus whatever the wrong path delayed. Two consequences:

* **Predictable branches are almost free; random ones are expensive.** Sorted data makes `v >= 128` predictable: a long run of false, then a long run of true.
* **Branchless code is not automatically faster.** A select (`cmov`) has no misprediction cost but turns a **control** dependency into a **data** dependency. With a branch, the core can speculatively start the next iteration's load before the comparison resolves. With a select it must wait. When loads miss the cache, that speculation acts as a prefetcher, and the branchy version can win (§4).

Compilers decide between branch and select using their own heuristics. Java's C2 can additionally use the **runtime profile**. The source code expresses a preference at best.

### 1.3 The hidden-constant catalogue

| Constant | Typical magnitude | Where it hides |
|---|---|---|
| Cache miss to DRAM, dependent | about 100–140 ns | Linked lists, tree nodes, hash-map chains, object graphs |
| Branch mispredict | about 6 ns here | Data-dependent `if` on unpredictable data; binary search on random keys |
| Allocation + GC | ns per object, 100+ ms per pause | Boxing (`Long`), per-node maps, temporary objects in hot loops |
| Pointer per element | 8–48 B of overhead | `HashMap` node + boxed key + boxed value ≈ 88 B for 16 B of payload |
| Rehash / resize | `O(n)` stop, amortized away | One insert in millions takes 50–320 ms |
| Missed vectorization | 3–8× on simple loops | Widening conversions, aliasing, `-O2` cost models |
| Timer resolution | 100 ns here | Any per-operation timing below about 1 µs is quantized |
| Virtual / megamorphic dispatch | ns per call, blocks inlining | Comparators, lambdas, interfaces in inner loops |

---

## 2. The memory hierarchy, measured

Each working set is one array. **Dependent chase** follows a single random cycle (Sattolo's algorithm) through every cache line, so each load's address is the previous load's value. **Independent gather** reads the same lines in random order, but from a precomputed index array, so the addresses are known ahead of time. **Sequential stream** sums the array front to back.

### 2.1 Listing 2.1 — Java

```java
// MemoryHierarchy.java - one O(N) loop, three access patterns, twelve working sets: where Big-O stops predicting time.
public final class MemoryHierarchy {
    static final int LINE_INTS = 16;    // a 64-byte cache line holds 16 ints
    static final int STEPS = 1 << 23;   // 8,388,608 loads per measurement

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

    /** One int per cache line points at the next line of a single random cycle (Sattolo) through all lines. */
    static int[] buildChase(int bytes, SplitMix64 r) {
        int lines = bytes / 64;
        int[] perm = new int[lines];
        for (int i = 0; i < lines; i++) perm[i] = i;
        for (int i = lines - 1; i > 0; i--) {
            int j = r.nextInt(i);
            int t = perm[i];
            perm[i] = perm[j];
            perm[j] = t;
        }
        int[] a = new int[bytes / 4];
        for (int i = 0; i < lines; i++) a[i * LINE_INTS] = perm[i] * LINE_INTS;
        return a;
    }

    /** Each address comes from the previous load: the core can have exactly one miss in flight. */
    static int chase(int[] a, int steps) {
        int i = 0;
        for (int s = 0; s < steps; s++) i = a[i];
        return i;
    }

    /** Addresses are known up front: the out-of-order core overlaps many misses (memory-level parallelism). */
    static long gather(int[] a, int[] idx) {
        long sum = 0;
        for (int k : idx) sum += a[k];
        return sum;
    }

    /** Sequential: the hardware prefetcher streams lines in before they are needed. */
    static long stream(int[] a, int passes) {
        long sum = 0;
        for (int p = 0; p < passes; p++) for (int v : a) sum += v;
        return sum;
    }

    static String level(int bytes) {  // i5-11260H: L1d 48 KiB/core, L2 1.25 MiB/core, L3 12 MiB shared
        return bytes <= 48 << 10 ? "L1d" : bytes <= 1_310_720 ? "L2" : bytes <= 12 << 20 ? "L3" : "DRAM";
    }

    static volatile long blackhole;

    public static void main(String[] args) {
        SplitMix64 w = new SplitMix64(99);  // JIT warm-up on its own generator: measured data stays identical to C++
        int[] wa = buildChase(64 << 10, w), widx = new int[1 << 16];
        for (int s = 0; s < widx.length; s++) widx[s] = w.nextInt(1 << 10) * LINE_INTS;
        for (int i = 0; i < 200; i++) blackhole += chase(wa, 1 << 16) + gather(wa, widx) + stream(wa, 4);
        SplitMix64 r = new SplitMix64(1);
        long sink = 0;
        System.out.println("working set  level  dependent chase  independent gather  sequential stream");
        System.out.println("                     (ns per load)    (ns per load)       (ns per int, GB/s)");
        for (int kib : new int[] {16, 32, 64, 256, 1 << 10, 2 << 10, 4 << 10, 8 << 10, 16 << 10, 32 << 10, 64 << 10, 256 << 10}) {
            int bytes = kib << 10, lines = bytes / 64;
            int[] a = buildChase(bytes, r);
            int[] idx = new int[STEPS];
            for (int s = 0; s < STEPS; s++) idx[s] = r.nextInt(lines) * LINE_INTS;
            int passes = Math.max(1, (64 << 20) / bytes);
            double chaseNs = Double.MAX_VALUE, gatherNs = Double.MAX_VALUE, streamNs = Double.MAX_VALUE;
            for (int rep = 0; rep < 2; rep++) {  // best of 2: the first pass also pays for JIT and page faults
                long t0 = System.nanoTime();
                sink += chase(a, STEPS);
                long t1 = System.nanoTime();
                sink += gather(a, idx);
                long t2 = System.nanoTime();
                sink += stream(a, passes);
                long t3 = System.nanoTime();
                chaseNs = Math.min(chaseNs, (t1 - t0) / (double) STEPS);
                gatherNs = Math.min(gatherNs, (t2 - t1) / (double) STEPS);
                streamNs = Math.min(streamNs, (t3 - t2) / ((double) passes * a.length));
            }
            String size = kib < 1024 ? kib + " KiB" : (kib >> 10) + " MiB";
            System.out.printf("%11s  %-5s  %13.2f  %17.2f  %13.3f  %5.1f%n", size, level(bytes), chaseNs, gatherNs,
                    streamNs, 4 / streamNs);
        }
        System.out.println("checksum " + sink);
    }
}
```

**Output (one measured run):**

```text
working set  level  dependent chase  independent gather  sequential stream
                     (ns per load)    (ns per load)       (ns per int, GB/s)
     16 KiB  L1d             1.24               0.37          0.049   82.4
     32 KiB  L1d             1.20               0.74          0.047   85.0
     64 KiB  L2              3.38               0.71          0.047   84.7
    256 KiB  L2              3.56               0.83          0.050   80.3
      1 MiB  L2              4.92               0.90          0.050   80.6
      2 MiB  L3             14.32               1.03          0.066   60.9
      4 MiB  L3             25.67               1.44          0.070   57.0
      8 MiB  L3            106.71               2.99          0.144   27.8
     16 MiB  DRAM          115.10               6.30          0.213   18.8
     32 MiB  DRAM          116.35               7.74          0.212   18.9
     64 MiB  DRAM          122.97               9.84          0.233   17.1
    256 MiB  DRAM          139.61              12.17          0.187   21.4
checksum 1159505052176352
```

### 2.2 Listing 2.2 — C++23

```cpp
// memory_hierarchy.cpp - one O(N) loop, three access patterns, twelve working sets: where Big-O stops predicting time.
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <print>
#include <string>
#include <utility>
#include <vector>

constexpr std::size_t kLineInts = 16;     // a 64-byte cache line holds 16 uint32
constexpr std::size_t kSteps = 1u << 23;  // 8,388,608 loads per measurement

struct SplitMix64 {
    std::uint64_t state;
    std::uint64_t next() noexcept {
        std::uint64_t z = (state += 0x9E3779B97F4A7C15ULL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }
    std::size_t below(std::size_t bound) noexcept { return static_cast<std::size_t>(next() % bound); }
};

// One uint32 per cache line points at the next line of a single random cycle (Sattolo) through all lines.
std::vector<std::uint32_t> build_chase(std::size_t bytes, SplitMix64& r) {
    std::size_t lines = bytes / 64;
    std::vector<std::uint32_t> perm(lines);
    for (std::size_t i = 0; i < lines; ++i) perm[i] = static_cast<std::uint32_t>(i);
    for (std::size_t i = lines - 1; i > 0; --i) std::swap(perm[i], perm[r.below(i)]);
    std::vector<std::uint32_t> a(bytes / 4);
    for (std::size_t i = 0; i < lines; ++i) a[i * kLineInts] = perm[i] * static_cast<std::uint32_t>(kLineInts);
    return a;
}

// Each address comes from the previous load: the core can have exactly one miss in flight.
std::uint32_t chase(const std::vector<std::uint32_t>& a, std::size_t steps) {
    std::uint32_t i = 0;
    for (std::size_t s = 0; s < steps; ++s) i = a[i];
    return i;
}

// Addresses are known up front: the out-of-order core overlaps many misses (memory-level parallelism).
std::uint64_t gather(const std::vector<std::uint32_t>& a, const std::vector<std::uint32_t>& idx) {
    std::uint64_t sum = 0;
    for (std::uint32_t k : idx) sum += a[k];
    return sum;
}

// Sequential: the hardware prefetcher streams lines in before they are needed (and the compiler vectorizes).
std::uint64_t stream(const std::vector<std::uint32_t>& a, std::size_t passes) {
    std::uint64_t sum = 0;
    for (std::size_t p = 0; p < passes; ++p)
        for (std::uint32_t v : a) sum += v;
    return sum;
}

const char* level(std::size_t bytes) {  // i5-11260H: L1d 48 KiB/core, L2 1.25 MiB/core, L3 12 MiB shared
    return bytes <= (48u << 10) ? "L1d" : bytes <= 1'310'720 ? "L2" : bytes <= (12u << 20) ? "L3" : "DRAM";
}

int main() {
    using clock = std::chrono::steady_clock;
    auto ns = [](clock::duration d) { return std::chrono::duration<double, std::nano>(d).count(); };
    SplitMix64 r{1};
    std::uint64_t sink = 0;
    std::println("working set  level  dependent chase  independent gather  sequential stream");
    std::println("                     (ns per load)    (ns per load)       (ns per int, GB/s)");
    for (std::size_t kib : {16u, 32u, 64u, 256u, 1u << 10, 2u << 10, 4u << 10, 8u << 10, 16u << 10, 32u << 10, 64u << 10,
                            256u << 10}) {
        std::size_t bytes = kib << 10, lines = bytes / 64;
        auto a = build_chase(bytes, r);
        std::vector<std::uint32_t> idx(kSteps);
        for (auto& k : idx) k = static_cast<std::uint32_t>(r.below(lines) * kLineInts);
        std::size_t passes = std::max<std::size_t>(1, (64u << 20) / bytes);
        double chase_ns = 1e300, gather_ns = 1e300, stream_ns = 1e300;
        for (int rep = 0; rep < 2; ++rep) {  // best of 2: the first pass also pays for page faults
            auto t0 = clock::now();
            sink += chase(a, kSteps);
            auto t1 = clock::now();
            sink += gather(a, idx);
            auto t2 = clock::now();
            sink += stream(a, passes);
            auto t3 = clock::now();
            chase_ns = std::min(chase_ns, ns(t1 - t0) / kSteps);
            gather_ns = std::min(gather_ns, ns(t2 - t1) / kSteps);
            stream_ns = std::min(stream_ns, ns(t3 - t2) / static_cast<double>(passes * a.size()));
        }
        std::string size = kib < 1024 ? std::to_string(kib) + " KiB" : std::to_string(kib >> 10) + " MiB";
        std::println("{:>11}  {:<5}  {:13.2f}  {:17.2f}  {:13.3f}  {:5.1f}", size, level(bytes), chase_ns, gather_ns,
                     stream_ns, 4 / stream_ns);
    }
    std::println("checksum {}", sink);
}
```

**Output, GCC 16.2 (one measured run):**

```text
working set  level  dependent chase  independent gather  sequential stream
                     (ns per load)    (ns per load)       (ns per int, GB/s)
     16 KiB  L1d             1.31               0.43          0.389   10.3
     32 KiB  L1d             1.28               0.42          0.354   11.3
     64 KiB  L2              3.37               0.46          0.349   11.5
    256 KiB  L2              3.45               0.47          0.340   11.8
      1 MiB  L2              4.79               0.73          0.342   11.7
      2 MiB  L3             13.23               1.02          0.341   11.7
      4 MiB  L3             28.82               1.46          0.350   11.4
      8 MiB  L3            104.22               2.97          0.388   10.3
     16 MiB  DRAM          109.54               4.33          0.444    9.0
     32 MiB  DRAM          114.09               7.99          0.421    9.5
     64 MiB  DRAM          115.07               8.93          0.389   10.3
    256 MiB  DRAM          130.05              10.64          0.427    9.4
checksum 1159505052176352
```

**Output, Clang 21.1 (one measured run):**

```text
working set  level  dependent chase  independent gather  sequential stream
                     (ns per load)    (ns per load)       (ns per int, GB/s)
     16 KiB  L1d             1.20               0.44          0.128   31.2
     32 KiB  L1d             1.18               0.35          0.133   30.0
     64 KiB  L2              3.42               0.39          0.132   30.2
    256 KiB  L2              3.49               0.46          0.129   31.1
      1 MiB  L2              5.26               0.65          0.147   27.3
      2 MiB  L3             13.46               1.02          0.135   29.6
      4 MiB  L3             26.14               1.48          0.132   30.3
      8 MiB  L3            103.92               2.04          0.217   18.5
     16 MiB  DRAM          111.07               4.46          0.264   15.2
     32 MiB  DRAM          111.79               7.13          0.253   15.8
     64 MiB  DRAM          114.63               8.56          0.296   13.5
    256 MiB  DRAM          131.17              12.15          0.273   14.7
checksum 1159505052176352
```

All three builds print the same checksum: they walked identical data.

### 2.3 What the numbers say

**The latency ladder is visible and steep.** Dependent loads cost 1.2 ns in L1, about 3.4 ns in L2, 13–15 ns at 2 MiB, and 104–140 ns once the set exceeds L3. The same `O(N)` loop varies **about 100×** with working-set size alone. The step between 4 MiB and 8 MiB comes earlier than the 12 MiB L3 size suggests. Across development runs the 4 MiB chase measured anywhere from 26 to 76 ns. Plausible contributors, none isolated here ⚠: the L3 is shared with the OS and other cores, it is non-inclusive, random access over thousands of 4 KiB pages stresses the TLB, and laptop power management moves the uncore frequency. The **interview-grade** statement is the robust one: *"beyond L2, every dependent miss costs tens of nanoseconds; beyond L3, about 100+."*

**Memory-level parallelism is worth 10–15×.** At 256 MiB the dependent chase took 130–140 ns per load. Independent loads **to the same random lines** took 10.6–12.2 ns. The difference is not the data; it is whether the core may have many misses in flight. That is the hardware argument for:

* arrays of indices over linked lists (the next address is in a register, not behind a load);
* processing queries in **batches**, with the loads for query *i + 1* issued while query *i* waits;
* software prefetching when the next address is computable (Listing 2.6).

**Streaming is bandwidth-bound, and the compiler matters.** Java's C2 vectorized the summing loop and reached about 80 GB/s from L1/L2 and 17–21 GB/s from DRAM. Clang `-O2` reached about 30 GB/s in cache. **GCC `-O2` stayed near 11 GB/s at every size**: it did not vectorize the loop. The assembly of `stream()` built here shows zero vector instructions at GCC `-O2`, five at GCC `-O3`, and six at Clang `-O2`. Since GCC 12, `-O2` vectorizes only under the "very cheap" cost model, and a `uint32_t → uint64_t` widening sum does not qualify. An interview-ready sentence: *"Same source, same `-O2`, a 3× gap between two mainstream compilers on the simplest loop there is. If it's hot, I look at the assembly or at least benchmark both builds."*

---

## 3. Branch prediction, measured

Four kernels over 1,048,576 values uniform in 0..255. Each is run on the data **shuffled** (the branch `v >= 128` is a coin flip) and **sorted** (the branch flips once).

### 3.1 Listing 2.3 — Java

```java
// BranchCost.java - one if-statement, four shapes: what a mispredicted branch costs, and when the JIT removes it for you.
import java.util.Arrays;

public final class BranchCost {
    static final int N = 1 << 20, REPS = 40;

    static final class SplitMix64 {
        private long state;
        SplitMix64(long seed) { state = seed; }
        long next() {
            long z = (state += 0x9E3779B97F4A7C15L);
            z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
            z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
            return z ^ (z >>> 31);
        }
    }

    /** Keep values >= 128. The store is conditional, so the branch cannot become a select. */
    static int filterBranchy(int[] in, int[] out) {
        int k = 0;
        for (int v : in) if (v >= 128) out[k++] = v;
        return k;
    }

    /** Same result: always store, advance the cursor by 0 or 1. No branch on the data. */
    static int filterBranchless(int[] in, int[] out) {
        int k = 0;
        for (int v : in) {
            out[k] = v;
            k += ~(v - 128) >>> 31;  // 1 when v >= 128 (sign bit of v-128 clear), else 0
        }
        return k;
    }

    /** The famous Stack Overflow loop. Whether this stays a branch is the compiler's decision, not the source's. */
    static long sumIf(int[] in) {
        long s = 0;
        for (int v : in) if (v >= 128) s += v;
        return s;
    }

    /** Arithmetic mask: v & -1 keeps v, v & 0 drops it. */
    static long sumMasked(int[] in) {
        long s = 0;
        for (int v : in) s += v & -(~(v - 128) >>> 31);
        return s;
    }

    interface Kernel { long run(int[] in, int[] out); }

    static double nsPerElement(Kernel k, int[] in, int[] out, long[] sink) {
        double best = Double.MAX_VALUE;
        for (int rep = 0; rep < REPS; rep++) {
            long t0 = System.nanoTime();
            sink[0] += k.run(in, out);
            best = Math.min(best, (System.nanoTime() - t0) / (double) in.length);
        }
        return best;
    }

    public static void main(String[] args) {
        SplitMix64 r = new SplitMix64(3);
        int[] shuffled = new int[N];
        for (int i = 0; i < N; i++) shuffled[i] = (int) (r.next() >>> 56);  // uniform 0..255: a coin flip per element
        int[] sorted = shuffled.clone();
        Arrays.sort(sorted);
        int[] out = new int[N];
        long[] sink = new long[1];
        String[] names = {"filter: if (v >= 128) out[k++] = v", "filter: out[k] = v; k += (v >= 128)",
                          "sum: if (v >= 128) s += v", "sum: s += v & mask(v >= 128)"};
        Kernel[] kernels = {BranchCost::filterBranchy, BranchCost::filterBranchless, (in, o) -> sumIf(in),
                            (in, o) -> sumMasked(in)};
        for (Kernel k : kernels) {  // warm-up so C2 compiles every kernel with a profile of BOTH inputs
            nsPerElement(k, shuffled, out, sink);
            nsPerElement(k, sorted, out, sink);
        }
        System.out.printf("N=%,d bytes-as-ints, best of %d runs (one measured run)%n", N, REPS);
        System.out.printf("%-38s %9s %9s %12s%n", "kernel", "shuffled", "sorted", "difference");
        for (int i = 0; i < kernels.length; i++) {
            double a = nsPerElement(kernels[i], shuffled, out, sink), b = nsPerElement(kernels[i], sorted, out, sink);
            System.out.printf("%-38s %6.2f ns %6.2f ns %9.2f ns%n", names[i], a, b, a - b);
        }
        System.out.printf("checks: filters agree %b, sums agree %b, sink %d%n",
                filterBranchy(shuffled, out) == filterBranchless(shuffled, new int[N]),
                sumIf(shuffled) == sumMasked(shuffled), sink[0]);
    }
}
```

**Output (one measured run):**

```text
N=1,048,576 bytes-as-ints, best of 40 runs (one measured run)
kernel                                  shuffled    sorted   difference
filter: if (v >= 128) out[k++] = v       3.10 ns   0.31 ns      2.79 ns
filter: out[k] = v; k += (v >= 128)      0.66 ns   0.67 ns     -0.02 ns
sum: if (v >= 128) s += v                3.35 ns   0.30 ns      3.06 ns
sum: s += v & mask(v >= 128)             0.09 ns   0.10 ns     -0.00 ns
checks: filters agree true, sums agree true, sink 32302838720
```

### 3.2 Listing 2.4 — C++23

```cpp
// branch_cost.cpp - one if-statement, four shapes: what a mispredicted branch costs, and when the compiler removes it.
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <print>
#include <span>
#include <vector>

struct SplitMix64 {
    std::uint64_t state;
    std::uint64_t next() noexcept {
        std::uint64_t z = (state += 0x9E3779B97F4A7C15ULL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }
};

// Keep values >= 128. The store is conditional, so the branch cannot become a select.
std::size_t filter_branchy(std::span<const int> in, std::span<int> out) {
    std::size_t k = 0;
    for (int v : in)
        if (v >= 128) out[k++] = v;
    return k;
}

// Same result: always store, advance the cursor by 0 or 1. No branch on the data.
std::size_t filter_branchless(std::span<const int> in, std::span<int> out) {
    std::size_t k = 0;
    for (int v : in) {
        out[k] = v;
        k += static_cast<std::size_t>(v >= 128);
    }
    return k;
}

// The famous Stack Overflow loop. Whether this stays a branch is the compiler's decision, not the source's.
std::int64_t sum_if(std::span<const int> in) {
    std::int64_t s = 0;
    for (int v : in)
        if (v >= 128) s += v;
    return s;
}

// Arithmetic mask: v & -1 keeps v, v & 0 drops it.
std::int64_t sum_masked(std::span<const int> in) {
    std::int64_t s = 0;
    for (int v : in) s += v & -static_cast<int>(v >= 128);
    return s;
}

int main() {
    constexpr std::size_t kN = 1u << 20;
    constexpr int kReps = 40;
    SplitMix64 r{3};
    std::vector<int> shuffled(kN), out(kN), out2(kN);
    for (auto& v : shuffled) v = static_cast<int>(r.next() >> 56);  // uniform 0..255: a coin flip per element
    auto sorted = shuffled;
    std::ranges::sort(sorted);
    std::int64_t sink = 0;
    using clock = std::chrono::steady_clock;
    auto measure = [&](auto kernel, std::span<const int> in) {
        double best = 1e300;
        for (int rep = 0; rep < kReps; ++rep) {
            auto t0 = clock::now();
            sink += static_cast<std::int64_t>(kernel(in));
            best = std::min(best, std::chrono::duration<double, std::nano>(clock::now() - t0).count() / kN);
        }
        return best;
    };
    auto row = [&](const char* name, auto kernel) {
        double a = measure(kernel, shuffled), b = measure(kernel, sorted);
        std::println("{:<38} {:6.2f} ns {:6.2f} ns {:9.2f} ns", name, a, b, a - b);
    };
    std::println("N={} bytes-as-ints, best of {} runs (one measured run)", kN, kReps);
    std::println("{:<38} {:>9} {:>9} {:>12}", "kernel", "shuffled", "sorted", "difference");
    row("filter: if (v >= 128) out[k++] = v", [&](std::span<const int> in) { return filter_branchy(in, out); });
    row("filter: out[k] = v; k += (v >= 128)", [&](std::span<const int> in) { return filter_branchless(in, out); });
    row("sum: if (v >= 128) s += v", [](std::span<const int> in) { return sum_if(in); });
    row("sum: s += v & mask(v >= 128)", [](std::span<const int> in) { return sum_masked(in); });
    std::println("checks: filters agree {}, sums agree {}, sink {}",
                 filter_branchy(shuffled, out) == filter_branchless(shuffled, out2), sum_if(shuffled) == sum_masked(shuffled),
                 sink);
}
```

**Output, GCC 16.2 (one measured run):**

```text
N=1048576 bytes-as-ints, best of 40 runs (one measured run)
kernel                                  shuffled    sorted   difference
filter: if (v >= 128) out[k++] = v       3.49 ns   0.32 ns      3.17 ns
filter: out[k] = v; k += (v >= 128)      0.59 ns   0.59 ns     -0.00 ns
sum: if (v >= 128) s += v                0.55 ns   0.55 ns      0.00 ns
sum: s += v & mask(v >= 128)             0.49 ns   0.50 ns     -0.01 ns
checks: filters agree true, sums agree true, sink 16151419360
```

**Output, Clang 21.1 (one measured run):**

```text
N=1048576 bytes-as-ints, best of 40 runs (one measured run)
kernel                                  shuffled    sorted   difference
filter: if (v >= 128) out[k++] = v       3.43 ns   0.26 ns      3.18 ns
filter: out[k] = v; k += (v >= 128)      0.44 ns   0.39 ns      0.05 ns
sum: if (v >= 128) s += v                0.19 ns   0.19 ns      0.01 ns
sum: s += v & mask(v >= 128)             0.25 ns   0.25 ns     -0.01 ns
checks: filters agree true, sums agree true, sink 16151419360
```

### 3.3 What the numbers say

* **The cost of a mispredict.** The branchy filter is 2.8–3.2 ns per element slower on shuffled data in all three builds. About half of the elements mispredict, so that is **about 6 ns per mispredict** (5.6–6.4 ns): about 25 cycles at this laptop's 4+ GHz boost clock ⚠ (frequency not measured), the pipeline refill plus the dependent work it delays.
* **Branch-free by construction fixes it, everywhere.** "Always store, advance the cursor by 0 or 1" is flat across sorted and shuffled data in all three builds (0.4–0.7 ns). This is the core trick of BlockQuicksort (Edelkamp and Weiß, 2016) and of modern partition routines: replace the unpredictable branch with arithmetic on the condition.
* **The famous Stack Overflow loop does not reproduce in C++, but does in Java.** `if (v >= 128) s += v` is flat on both C++ compilers: GCC and Clang if-converted and vectorized it, 0.19–0.55 ns either way. Java's C2 **kept the branch**: 3.35 ns shuffled vs 0.30 ns sorted, even though the kernel was warmed with both inputs so the profile was mixed. The arithmetic-mask version is flat in Java and, at 0.09 ns per element, the fastest code in this file because C2 vectorized it.

The L7 lesson is not "always write branchless". It is: **know which shape the compiler will keep, and measure the shape you shipped.** A sentence that lands in an interview: *"the source-level trick only matters when the compiler doesn't already do it, and the only way to know is to look."*

---

## 4. One `O(log n)` search, five codegens, 5–10× apart

`lower_bound` over `n` sorted distinct ints, 1,048,576 random queries per size:

* **library** — `Arrays.binarySearch` / `std::ranges::lower_bound`;
* **ternary** — Khuong and Morin's branch-free *shape* (`base = a[base + half] < x ? base + half : base`), leaving branch vs select to the compiler;
* **mask** — the same step as pure arithmetic (`base += half & -(a[...] < x)`);
* **Eytzinger** — the sorted array rearranged in BFS order of the implicit search tree (node `k`'s children at `2k` and `2k + 1`), so the first levels of every search share a few cache lines;
* **Eytzinger + prefetch** (C++ only) — while visiting node `k`, prefetch node `16k`, the cache line holding all 16 great-great-grandchildren.

### 4.1 Listing 2.5 — Java

```java
// SearchLayouts.java - one O(log n) lower_bound, four codegens: library, ternary, mask arithmetic, Eytzinger (BFS order).
import java.util.Arrays;

public final class SearchLayouts {
    static final int QUERIES = 1 << 20;

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

    /** The library: correct, branchy; each level's branch is a coin flip for random queries. */
    static int viaLibrary(int[] a, int x) {
        int r = Arrays.binarySearch(a, x);
        return r >= 0 ? r : -r - 1;  // keys are distinct, so a hit is also the lower bound
    }

    /** Khuong & Morin's shape: trip count depends only on n. Whether the ternary becomes a select is up to C2. */
    static int ternary(int[] a, int x) {
        int base = 0, n = a.length;
        while (n > 1) {
            int half = n >>> 1;
            base = a[base + half] < x ? base + half : base;
            n -= half;
        }
        return base + (a[base] < x ? 1 : 0);
    }

    /** Branch-free by construction: (a - x) >> 63 is all ones exactly when a < x (long math cannot overflow). */
    static int mask(int[] a, int x) {
        int base = 0, n = a.length;
        while (n > 1) {
            int half = n >>> 1;
            base += half & (int) (((long) a[base + half] - x) >> 63);
            n -= half;
        }
        return base + (int) (((long) a[base] - x) >>> 63);
    }

    /** b[1..n] holds a in BFS order of the implicit search tree: node k's children are 2k and 2k+1. */
    static int[] eytzinger(int[] a) {
        int[] b = new int[a.length + 1];
        fill(a, b, 1, new int[] {0});
        return b;
    }

    private static void fill(int[] a, int[] b, int k, int[] next) {  // in-order walk; depth is only log2(n)
        if (k >= b.length) return;
        fill(a, b, 2 * k, next);
        b[k] = a[next[0]++];
        fill(a, b, 2 * k + 1, next);
    }

    /** Descend left/right with arithmetic; the top levels share cache lines across all queries. */
    static int eytzingerSearch(int[] b, int x) {
        int k = 1;
        while (k < b.length) k = 2 * k + (b[k] < x ? 1 : 0);
        k >>>= Integer.numberOfTrailingZeros(~k) + 1;  // undo the trailing "went right" moves
        return k;                                        // 0 means "greater than everything"
    }

    public static void main(String[] args) {
        SplitMix64 r = new SplitMix64(5);
        System.out.printf("lower_bound, %,d random queries per size, ns per query (one measured run)%n", QUERIES);
        System.out.printf("%12s %10s %14s %9s %7s %11s  %s%n", "n", "bytes", "binarySearch", "ternary", "mask",
                "eytzinger", "answers agree");
        for (int log = 12; log <= 25; log += (log < 20 ? 4 : log < 23 ? 3 : 2)) {
            int n = 1 << log;
            int[] a = new int[n];
            for (int i = 0; i < n; i++) a[i] = 2 * i + 1;  // sorted, distinct, odd: half the queries miss
            int[] b = eytzinger(a);
            int[] q = new int[QUERIES];
            for (int i = 0; i < QUERIES; i++) q[i] = r.nextInt(2 * n + 1);
            double[] best = {Double.MAX_VALUE, Double.MAX_VALUE, Double.MAX_VALUE, Double.MAX_VALUE};
            long[] sums = new long[4];
            for (int rep = 0; rep < 3; rep++) {
                long[] s = new long[4];
                long t0 = System.nanoTime();
                for (int x : q) { int i = viaLibrary(a, x); s[0] += i < n ? a[i] : Integer.MAX_VALUE; }
                long t1 = System.nanoTime();
                for (int x : q) { int i = ternary(a, x); s[1] += i < n ? a[i] : Integer.MAX_VALUE; }
                long t2 = System.nanoTime();
                for (int x : q) { int i = mask(a, x); s[2] += i < n ? a[i] : Integer.MAX_VALUE; }
                long t3 = System.nanoTime();
                for (int x : q) { int k = eytzingerSearch(b, x); s[3] += k != 0 ? b[k] : Integer.MAX_VALUE; }
                long t4 = System.nanoTime();
                long[] t = {t0, t1, t2, t3, t4};
                for (int v = 0; v < 4; v++) {
                    best[v] = Math.min(best[v], (t[v + 1] - t[v]) / (double) QUERIES);
                    sums[v] = s[v];
                }
            }
            String bytes = n * 4L >= 1 << 20 ? (n * 4L >> 20) + " MiB" : (n * 4L >> 10) + " KiB";
            System.out.printf("%12s %10s %14.1f %9.1f %7.1f %11.1f  %b%n", String.format("2^%d", log), bytes, best[0],
                    best[1], best[2], best[3], sums[0] == sums[1] && sums[1] == sums[2] && sums[2] == sums[3]);
        }
    }
}
```

**Output (one measured run):**

```text
lower_bound, 1,048,576 random queries per size, ns per query (one measured run)
           n      bytes   binarySearch   ternary    mask   eytzinger  answers agree
        2^12     16 KiB           60.5      68.3    20.8        13.1  true
        2^16    256 KiB           80.3      90.4    48.3        19.2  true
        2^20      4 MiB          192.6     181.5   179.4        60.7  true
        2^23     32 MiB          576.8     656.0  1076.4       401.2  true
        2^25    128 MiB          753.2     852.2  1482.4       833.8  true
```

### 4.2 Listing 2.6 — C++23

```cpp
// search_layouts.cpp - one O(log n) lower_bound, five codegens: std::lower_bound, ternary, mask, Eytzinger, + prefetch.
#include <algorithm>
#include <bit>
#include <chrono>
#include <cstdint>
#include <memory>
#include <new>
#include <print>
#include <span>
#include <string>
#include <vector>

struct SplitMix64 {
    std::uint64_t state;
    std::uint64_t next() noexcept {
        std::uint64_t z = (state += 0x9E3779B97F4A7C15ULL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }
};

// Khuong & Morin's shape: trip count depends only on n. Whether the ternary becomes a cmov is the compiler's call.
std::size_t ternary(std::span<const int> a, int x) {
    const int* base = a.data();
    std::size_t n = a.size();
    while (n > 1) {
        std::size_t half = n / 2;
        base = base[half] < x ? base + half : base;
        n -= half;
    }
    return static_cast<std::size_t>(base - a.data()) + (*base < x);
}

// Branch-free by construction: -(a < x) is all ones or zero, so the step is data, not control flow.
std::size_t mask(std::span<const int> a, int x) {
    std::size_t lo = 0, n = a.size();
    while (n > 1) {
        std::size_t half = n / 2;
        lo += half & -static_cast<std::size_t>(a[lo + half] < x);
        n -= half;
    }
    return lo + static_cast<std::size_t>(a[lo] < x);
}

// b[1..n] holds a in BFS order of the implicit search tree; b is 64-byte aligned so b[16k..16k+15] is one line.
struct Eytzinger {
    struct Free {
        void operator()(int* p) const noexcept { ::operator delete[](p, std::align_val_t{64}); }
    };
    std::unique_ptr<int[], Free> mem;
    std::size_t n;

    explicit Eytzinger(std::span<const int> a)
        : mem(static_cast<int*>(::operator new[]((a.size() + 1) * sizeof(int), std::align_val_t{64}))), n(a.size()) {
        std::size_t next = 0;
        fill(a, 1, next);
    }
    void fill(std::span<const int> a, std::size_t k, std::size_t& next) {  // in-order walk; depth is only log2(n)
        if (k > n) return;
        fill(a, 2 * k, next);
        mem[k] = a[next++];
        fill(a, 2 * k + 1, next);
    }
    template <bool Prefetch>
    std::size_t search(int x) const {
        const int* b = mem.get();
        std::size_t k = 1;
        while (k <= n) {
            if constexpr (Prefetch) __builtin_prefetch(b + 16 * k);  // the 16 great-great-grandchildren: one line
            k = 2 * k + static_cast<std::size_t>(b[k] < x);
        }
        return k >> (std::countr_one(k) + 1);  // undo the trailing "went right" moves; 0 = greater than all
    }
    int at(std::size_t k) const { return mem[k]; }
};

int main() {
    constexpr std::size_t kQueries = 1u << 20;
    constexpr int kMax = 0x7fffffff;
    SplitMix64 r{5};
    using clock = std::chrono::steady_clock;
    std::println("lower_bound, {} random queries per size, ns per query (one measured run)", kQueries);
    std::println("{:>12} {:>10} {:>16} {:>8} {:>6} {:>10} {:>11}  {}", "n", "bytes", "std::lower_bound", "ternary", "mask",
                 "eytzinger", "+ prefetch", "answers agree");
    for (int lg = 12; lg <= 25; lg += lg < 20 ? 4 : lg < 23 ? 3 : 2) {
        std::size_t n = std::size_t{1} << lg;
        std::vector<int> a(n);
        for (std::size_t i = 0; i < n; ++i) a[i] = static_cast<int>(2 * i + 1);  // sorted, distinct, odd
        Eytzinger e(a);
        std::vector<int> q(kQueries);
        for (auto& x : q) x = static_cast<int>(r.next() % (2 * n + 1));
        double best[5] = {1e300, 1e300, 1e300, 1e300, 1e300};
        std::int64_t sums[5] = {};
        for (int rep = 0; rep < 3; ++rep) {
            std::int64_t s[5] = {};
            auto t0 = clock::now();
            for (int x : q) {
                auto it = std::ranges::lower_bound(a, x);
                s[0] += it != a.end() ? *it : kMax;
            }
            auto t1 = clock::now();
            for (int x : q) {
                auto i = ternary(a, x);
                s[1] += i < n ? a[i] : kMax;
            }
            auto t2 = clock::now();
            for (int x : q) {
                auto i = mask(a, x);
                s[2] += i < n ? a[i] : kMax;
            }
            auto t3 = clock::now();
            for (int x : q) {
                auto k = e.search<false>(x);
                s[3] += k != 0 ? e.at(k) : kMax;
            }
            auto t4 = clock::now();
            for (int x : q) {
                auto k = e.search<true>(x);
                s[4] += k != 0 ? e.at(k) : kMax;
            }
            auto t5 = clock::now();
            clock::time_point t[] = {t0, t1, t2, t3, t4, t5};
            for (int v = 0; v < 5; ++v) {
                best[v] = std::min(best[v], std::chrono::duration<double, std::nano>(t[v + 1] - t[v]).count() / kQueries);
                sums[v] = s[v];
            }
        }
        std::string bytes = n * 4 >= (1u << 20) ? std::to_string(n * 4 >> 20) + " MiB" : std::to_string(n * 4 >> 10) + " KiB";
        bool agree = std::ranges::all_of(sums, [&](std::int64_t s) { return s == sums[0]; });
        std::println("{:>12} {:>10} {:16.1f} {:8.1f} {:6.1f} {:10.1f} {:11.1f}  {}", "2^" + std::to_string(lg), bytes, best[0],
                     best[1], best[2], best[3], best[4], agree);
    }
}
```

**Output, GCC 16.2 (one measured run):**

```text
lower_bound, 1048576 random queries per size, ns per query (one measured run)
           n      bytes std::lower_bound  ternary   mask  eytzinger  + prefetch  answers agree
        2^12     16 KiB             52.0      8.5   11.6        8.8        10.6  true
        2^16    256 KiB             78.0     19.5   24.1       15.4        16.2  true
        2^20      4 MiB            168.9     75.9   99.3       46.2        27.3  true
        2^23     32 MiB            515.1    512.5  623.2      217.0        87.5  true
        2^25    128 MiB            700.5    792.3  869.4      367.7       119.6  true
```

**Output, Clang 21.1 (one measured run):**

```text
lower_bound, 1048576 random queries per size, ns per query (one measured run)
           n      bytes std::lower_bound  ternary   mask  eytzinger  + prefetch  answers agree
        2^12     16 KiB             15.7     49.7   51.7        8.8        10.6  true
        2^16    256 KiB             45.4     78.8   79.6       15.6        16.6  true
        2^20      4 MiB            139.0    161.2  166.3       41.6        25.3  true
        2^23     32 MiB            836.0    514.4  519.8      230.2        83.3  true
        2^25    128 MiB           1350.4    708.2  731.3      404.3       135.8  true
```

### 4.3 What the numbers say

**At small n, codegen decides, and the two compilers decided opposite things.** At 16 KiB, GCC's `std::lower_bound` is branchy (52 ns) while its ternary and mask versions compile to `cmov` (8.5–11.6 ns). Clang is the mirror image. Its libc++ `std::lower_bound` (a two-variable bisection) is branch-free (15.7 ns), but **both** of my branch-free formulations, the ternary *and* the arithmetic mask, came out as branches (about 50 ns). The assembly confirms it. In Clang's `ternary` and `mask` functions the loop body has a data-dependent `jge`/`jl` and no `cmov`; GCC's each contain one `cmov`. LLVM has explicit heuristics that turn selects back into branches when it judges a branch cheaper: `CodeGenPrepare`'s select-to-branch transform and the x86 cmov-conversion pass. Which one fired here was not traced ⚠. Java's C2 compiled the ternary as a branch (68 ns) but the mask as arithmetic (21 ns).

**At large n, the branchy version catches up, then wins.** At 32–128 MiB the variant the compiler made branch-free is the *slowest* in every build: the mask form in Java (1,076–1,482 ns) and GCC (623–869 ns), and libc++'s branch-free `std::lower_bound` in Clang (836–1,350 ns), while Clang's branchy ternary and mask now beat it. Each level's load must complete before the next address is known. The branchy search lets the core **guess** the next level and start its load speculatively. Half the guesses are right, and those turn a dependent miss into an overlapped one. This is the effect Khuong and Morin measured. Branch-free code wins while the data is in cache and loses once every level misses.

**Layout beats both.** Eytzinger keeps the hot top of the tree in a handful of lines shared by every query, and its descent `k = 2k + (b[k] < x)` compiled branch-free everywhere, Clang included. With prefetching, the C++ version issues the load for four levels down while it works on this one. That converts the dependent chain into overlapped misses, giving **120–136 ns per query at 128 MiB vs 700–1,350 ns** for the library search, about **5–10×** for the same `O(log n)`. Java exposes no prefetch instruction (the `sun.misc.Unsafe` prefetch methods were removed in JDK 9). Its Eytzinger is 4–5× faster than `Arrays.binarySearch` in cache but no faster at 128 MiB (834 vs 753 ns), so layout alone does not rescue the DRAM case without prefetch.

**When to use it.** Eytzinger is for read-mostly sorted data searched by many queries: routing tables, IP ranges, static indexes, the lookup side of a learned index. Inserts are `O(n)` (rebuild), and range iteration in order is awkward. For disk or SSD, the same idea at a larger `B` is the **B+-tree**: one node per page, high fanout, so a search costs `log_B n` block reads instead of `log₂ n`. In an interview: *"binary search is optimal in comparisons, not in cache misses; the I/O-optimal structure is a B-tree, and Eytzinger is its in-memory cousin."*

---

## 5. "O(1)" hash maps, 3–12× apart

Same keys (4,194,304 random 64-bit values), two shapes of hash table:

* **chained, node-based** — `HashMap<Long, Long>` and `std::unordered_map<uint64_t, uint64_t>`: one heap node per entry, boxed keys and values in Java;
* **flat, open addressing** — two parallel `long` / `uint64_t` arrays, linear probing, power-of-two capacity, load factor ≤ ½, Fibonacci hashing (multiply by 2⁶⁴/φ and keep the top bits).

The first section times **every** insert individually to expose the tail; the second runs untimed loops for throughput and measures footprint.

### 5.1 Listing 2.7 — Java

```java
// HashConstants.java - two "O(1)" maps several times apart, and the tail hidden inside "amortized O(1)".
import java.lang.management.GarbageCollectorMXBean;
import java.lang.management.ManagementFactory;
import java.util.Arrays;
import java.util.HashMap;
import java.util.function.IntConsumer;

public final class HashConstants {
    static final int N = 1 << 22;  // 4,194,304 keys

    static final class SplitMix64 {
        private long state;
        SplitMix64(long seed) { state = seed; }
        long next() {
            long z = (state += 0x9E3779B97F4A7C15L);
            z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
            z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
            return z ^ (z >>> 31);
        }
    }

    /** Open addressing, linear probing, power-of-two table, load factor <= 1/2. Key 0 is reserved as "empty". */
    static final class LongLongMap {
        private long[] keys, vals;
        private int shift, size;

        LongLongMap(int expected) {
            alloc(Math.max(16, Integer.highestOneBit(Math.max(1, expected) * 2 - 1) << 1));
        }

        private void alloc(int capacity) {
            keys = new long[capacity];
            vals = new long[capacity];
            shift = 64 - Integer.numberOfTrailingZeros(capacity);
        }

        private int slot(long k) { return (int) ((k * 0x9E3779B97F4A7C15L) >>> shift); }  // Fibonacci hashing

        void put(long k, long v) {
            if (k == 0) throw new IllegalArgumentException("key 0 is reserved for empty slots");
            if (2 * (size + 1) > keys.length) grow();
            int mask = keys.length - 1;
            for (int i = slot(k); ; i = (i + 1) & mask) {
                if (keys[i] == 0) { keys[i] = k; vals[i] = v; size++; return; }
                if (keys[i] == k) { vals[i] = v; return; }
            }
        }

        long getOrDefault(long k, long absent) {
            int mask = keys.length - 1;
            for (int i = slot(k); ; i = (i + 1) & mask) {
                if (keys[i] == k) return vals[i];
                if (keys[i] == 0) return absent;
            }
        }

        private void grow() {
            long[] oldKeys = keys, oldVals = vals;
            alloc(oldKeys.length * 2);
            size = 0;
            for (int i = 0; i < oldKeys.length; i++) if (oldKeys[i] != 0) put(oldKeys[i], oldVals[i]);
        }
    }

    static long gcCount() {
        return ManagementFactory.getGarbageCollectorMXBeans().stream().mapToLong(GarbageCollectorMXBean::getCollectionCount).sum();
    }

    static long usedHeap() {
        System.gc();
        Runtime rt = Runtime.getRuntime();
        return rt.totalMemory() - rt.freeMemory();
    }

    /** Times every insert individually; returns a one-line latency summary. */
    static String latencies(String name, IntConsumer insert) {
        long[] ns = new long[N];
        long gc0 = gcCount(), t0 = System.nanoTime();
        for (int i = 0; i < N; i++) {
            long s = System.nanoTime();
            insert.accept(i);
            ns[i] = System.nanoTime() - s;
        }
        long totalMs = (System.nanoTime() - t0) / 1_000_000, gcs = gcCount() - gc0;
        long slow = Arrays.stream(ns).filter(x -> x > 1_000_000).count();
        Arrays.sort(ns);
        return String.format("    %-30s %5d ms  p50 %4d ns  p99.9 %6.1f us  max %7.1f ms  inserts > 1 ms: %3d  GCs: %d",
                name, totalMs, ns[N / 2], ns[(int) (N * 0.999)] / 1e3, ns[N - 1] / 1e6, slow, gcs);
    }

    public static void main(String[] args) {
        SplitMix64 r = new SplitMix64(11);
        long[] keys = new long[N], misses = new long[N];
        for (int i = 0; i < N; i++) {
            keys[i] = r.next() | 1;      // nonzero (0 is the open-addressing sentinel)
            misses[i] = r.next() | 1;    // almost surely absent
        }
        long tick = Long.MAX_VALUE;
        for (int i = 0; i < 1_000_000; i++) {
            long a = System.nanoTime(), b = System.nanoTime();
            if (b > a) tick = Math.min(tick, b - a);
        }
        System.out.printf("N=%,d random long keys (one measured run); smallest nonzero nanoTime step here: %d ns%n", N, tick);
        System.out.println("insert latency, every insert timed (so p50 is quantized to that step):");
        HashMap<Long, Long> grownBoxed = new HashMap<>();
        System.out.println(latencies("HashMap<Long,Long> default", i -> grownBoxed.put(keys[i], keys[i])));
        HashMap<Long, Long> sizedBoxed = HashMap.newHashMap(N);
        System.out.println(latencies("HashMap<Long,Long> newHashMap(N)", i -> sizedBoxed.put(keys[i], keys[i])));
        LongLongMap grownFlat = new LongLongMap(16);
        System.out.println(latencies("LongLongMap default", i -> grownFlat.put(keys[i], keys[i])));
        LongLongMap sizedFlat = new LongLongMap(N);
        System.out.println(latencies("LongLongMap presized", i -> sizedFlat.put(keys[i], keys[i])));

        System.out.println("throughput and footprint (presized, untimed inner loops):");
        long before = usedHeap();
        HashMap<Long, Long> boxed = HashMap.newHashMap(N);
        long t0 = System.nanoTime();
        for (long k : keys) boxed.put(k, k);
        double boxedPut = (System.nanoTime() - t0) / (double) N;
        long boxedBytes = usedHeap() - before;
        before = usedHeap();
        LongLongMap flat = new LongLongMap(N);
        t0 = System.nanoTime();
        for (long k : keys) flat.put(k, k);
        double flatPut = (System.nanoTime() - t0) / (double) N;
        long flatBytes = usedHeap() - before;
        long hits = 0;
        t0 = System.nanoTime();
        for (int i = 0; i < N; i++) {
            hits += boxed.containsKey(keys[i]) ? 1 : 0;
            hits += boxed.containsKey(misses[i]) ? 1 : 0;
        }
        double boxedGet = (System.nanoTime() - t0) / (2.0 * N);
        long flatHits = 0;
        t0 = System.nanoTime();
        for (int i = 0; i < N; i++) {
            flatHits += flat.getOrDefault(keys[i], 0) != 0 ? 1 : 0;
            flatHits += flat.getOrDefault(misses[i], 0) != 0 ? 1 : 0;
        }
        double flatGet = (System.nanoTime() - t0) / (2.0 * N);
        System.out.printf("    %-30s put %5.1f ns  get %5.1f ns  ~%3d B/entry (heap delta after GC)%n",
                "HashMap<Long,Long>", boxedPut, boxedGet, boxedBytes / N);
        System.out.printf("    %-30s put %5.1f ns  get %5.1f ns  ~%3d B/entry (2 x 8 B / load 0.5)%n",
                "LongLongMap", flatPut, flatGet, flatBytes / N);
        System.out.printf("    hits found: %,d and %,d (expected %,d each); all five maps hold N keys: %b%n", hits, flatHits, N,
                boxed.size() == N && grownBoxed.size() == N && sizedBoxed.size() == N && grownFlat.size == N
                        && sizedFlat.size == N);
    }
}
```

**Output (one measured run):**

```text
N=4,194,304 random long keys (one measured run); smallest nonzero nanoTime step here: 100 ns
insert latency, every insert timed (so p50 is quantized to that step):
    HashMap<Long,Long> default      1458 ms  p50  200 ns  p99.9    4.5 us  max   177.2 ms  inserts > 1 ms:  14  GCs: 10
    HashMap<Long,Long> newHashMap(N)  1395 ms  p50  200 ns  p99.9    5.3 us  max   168.7 ms  inserts > 1 ms:   5  GCs: 4
    LongLongMap default              910 ms  p50  100 ns  p99.9    0.9 us  max    60.3 ms  inserts > 1 ms:   8  GCs: 1
    LongLongMap presized             834 ms  p50  100 ns  p99.9    0.9 us  max     0.2 ms  inserts > 1 ms:   0  GCs: 0
throughput and footprint (presized, untimed inner loops):
    HashMap<Long,Long>             put 222.1 ns  get  88.1 ns  ~ 88 B/entry (heap delta after GC)
    LongLongMap                    put  70.4 ns  get  39.0 ns  ~ 33 B/entry (2 x 8 B / load 0.5)
    hits found: 4,194,304 and 4,194,304 (expected 4,194,304 each); all five maps hold N keys: true
```

### 5.2 Listing 2.8 — C++23

```cpp
// hash_constants.cpp - two "O(1)" maps several times apart, and the tail hidden inside "amortized O(1)".
#include <algorithm>
#include <bit>
#include <chrono>
#include <cstdint>
#include <functional>
#include <memory>
#include <print>
#include <stdexcept>
#include <string_view>
#include <unordered_map>
#include <vector>

constexpr std::size_t kN = std::size_t{1} << 22;  // 4,194,304 keys

struct SplitMix64 {
    std::uint64_t state;
    std::uint64_t next() noexcept {
        std::uint64_t z = (state += 0x9E3779B97F4A7C15ULL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }
};

// Counts live bytes, so bytes/entry is exact rather than estimated.
inline std::size_t g_live_bytes = 0;
template <class T>
struct Counting {
    using value_type = T;
    Counting() = default;
    template <class U>
    Counting(const Counting<U>&) noexcept {}
    T* allocate(std::size_t n) {
        g_live_bytes += n * sizeof(T);
        return std::allocator<T>{}.allocate(n);
    }
    void deallocate(T* p, std::size_t n) noexcept {
        g_live_bytes -= n * sizeof(T);
        std::allocator<T>{}.deallocate(p, n);
    }
    template <class U>
    friend bool operator==(const Counting&, const Counting<U>&) noexcept { return true; }
};
using NodeMap = std::unordered_map<std::uint64_t, std::uint64_t, std::hash<std::uint64_t>, std::equal_to<>,
                                   Counting<std::pair<const std::uint64_t, std::uint64_t>>>;

// Open addressing, linear probing, power-of-two table, load factor <= 1/2. Key 0 is reserved as "empty".
class FlatMap {
public:
    explicit FlatMap(std::size_t expected) { alloc(std::max<std::size_t>(16, std::bit_ceil(std::max<std::size_t>(1, expected) * 2))); }

    void put(std::uint64_t k, std::uint64_t v) {
        if (k == 0) throw std::invalid_argument("key 0 is reserved for empty slots");
        if (2 * (size_ + 1) > keys_.size()) grow();
        const std::size_t mask = keys_.size() - 1;
        for (std::size_t i = slot(k);; i = (i + 1) & mask) {
            if (keys_[i] == 0) { keys_[i] = k; vals_[i] = v; ++size_; return; }
            if (keys_[i] == k) { vals_[i] = v; return; }
        }
    }
    [[nodiscard]] const std::uint64_t* find(std::uint64_t k) const noexcept {
        const std::size_t mask = keys_.size() - 1;
        for (std::size_t i = slot(k);; i = (i + 1) & mask) {
            if (keys_[i] == k) return &vals_[i];
            if (keys_[i] == 0) return nullptr;
        }
    }
    [[nodiscard]] std::size_t size() const noexcept { return size_; }
    [[nodiscard]] std::size_t bytes() const noexcept { return 2 * keys_.capacity() * sizeof(std::uint64_t); }

private:
    void alloc(std::size_t capacity) {
        keys_.assign(capacity, 0);
        vals_.assign(capacity, 0);
        shift_ = 64 - std::countr_zero(capacity);
    }
    [[nodiscard]] std::size_t slot(std::uint64_t k) const noexcept {  // Fibonacci hashing: keep the top bits
        return static_cast<std::size_t>((k * 0x9E3779B97F4A7C15ULL) >> shift_);
    }
    void grow() {
        auto old_keys = std::move(keys_), old_vals = std::move(vals_);
        keys_ = {};
        vals_ = {};
        alloc(old_keys.size() * 2);
        size_ = 0;
        for (std::size_t i = 0; i < old_keys.size(); ++i)
            if (old_keys[i] != 0) put(old_keys[i], old_vals[i]);
    }
    std::vector<std::uint64_t> keys_, vals_;
    int shift_ = 0;
    std::size_t size_ = 0;
};

using clock_type = std::chrono::steady_clock;

template <class Insert>
void latencies(std::string_view name, Insert insert) {
    std::vector<std::int64_t> ns(kN);
    auto t0 = clock_type::now();
    for (std::size_t i = 0; i < kN; ++i) {
        auto s = clock_type::now();
        insert(i);
        ns[i] = std::chrono::duration_cast<std::chrono::nanoseconds>(clock_type::now() - s).count();
    }
    auto total = std::chrono::duration_cast<std::chrono::milliseconds>(clock_type::now() - t0).count();
    auto slow = std::ranges::count_if(ns, [](std::int64_t x) { return x > 1'000'000; });
    std::ranges::sort(ns);
    std::println("    {:<30} {:5} ms  p50 {:4} ns  p99.9 {:6.1f} us  max {:7.1f} ms  inserts > 1 ms: {:3}", name, total,
                 ns[kN / 2], static_cast<double>(ns[kN * 999 / 1000]) / 1e3, static_cast<double>(ns[kN - 1]) / 1e6, slow);
}

int main() {
    SplitMix64 r{11};
    std::vector<std::uint64_t> keys(kN), misses(kN);
    for (std::size_t i = 0; i < kN; ++i) {
        keys[i] = r.next() | 1;    // nonzero (0 is the open-addressing sentinel)
        misses[i] = r.next() | 1;  // almost surely absent
    }
    std::int64_t tick = INT64_MAX;
    for (int i = 0; i < 1'000'000; ++i) {
        auto a = clock_type::now(), b = clock_type::now();
        if (b > a) tick = std::min<std::int64_t>(tick, std::chrono::duration_cast<std::chrono::nanoseconds>(b - a).count());
    }
    std::println("N={} random 64-bit keys (one measured run); smallest nonzero steady_clock step here: {} ns", kN, tick);
    std::println("insert latency, every insert timed (so p50 is quantized to that step):");
    NodeMap grown_nodes;
    latencies("unordered_map default", [&](std::size_t i) { grown_nodes.emplace(keys[i], keys[i]); });
    NodeMap sized_nodes;
    sized_nodes.reserve(kN);
    latencies("unordered_map reserve(N)", [&](std::size_t i) { sized_nodes.emplace(keys[i], keys[i]); });
    FlatMap grown_flat(16);
    latencies("FlatMap default", [&](std::size_t i) { grown_flat.put(keys[i], keys[i]); });
    FlatMap sized_flat(kN);
    latencies("FlatMap presized", [&](std::size_t i) { sized_flat.put(keys[i], keys[i]); });
    grown_nodes = {};
    sized_nodes = {};

    std::println("throughput and footprint (presized, untimed inner loops):");
    std::size_t base = g_live_bytes;
    NodeMap nodes;
    nodes.reserve(kN);
    auto t0 = clock_type::now();
    for (auto k : keys) nodes.emplace(k, k);
    double node_put = std::chrono::duration<double, std::nano>(clock_type::now() - t0).count() / kN;
    std::size_t node_bytes = g_live_bytes - base;
    FlatMap flat(kN);
    t0 = clock_type::now();
    for (auto k : keys) flat.put(k, k);
    double flat_put = std::chrono::duration<double, std::nano>(clock_type::now() - t0).count() / kN;
    std::size_t hits = 0, flat_hits = 0;
    t0 = clock_type::now();
    for (std::size_t i = 0; i < kN; ++i) hits += static_cast<std::size_t>(nodes.contains(keys[i])) + static_cast<std::size_t>(nodes.contains(misses[i]));
    double node_get = std::chrono::duration<double, std::nano>(clock_type::now() - t0).count() / (2.0 * kN);
    t0 = clock_type::now();
    for (std::size_t i = 0; i < kN; ++i) flat_hits += static_cast<std::size_t>(flat.find(keys[i]) != nullptr) + static_cast<std::size_t>(flat.find(misses[i]) != nullptr);
    double flat_get = std::chrono::duration<double, std::nano>(clock_type::now() - t0).count() / (2.0 * kN);
    std::println("    {:<30} put {:5.1f} ns  get {:5.1f} ns  {:3} B/entry requested (+ heap header per node)", "unordered_map",
                 node_put, node_get, node_bytes / kN);
    std::println("    {:<30} put {:5.1f} ns  get {:5.1f} ns  {:3} B/entry (2 x 8 B / load 0.5)", "FlatMap", flat_put,
                 flat_get, flat.bytes() / kN);
    std::println("    hits found: {} and {} (expected {} each); all maps hold N keys: {}", hits, flat_hits, kN,
                 nodes.size() == kN && grown_flat.size() == kN && sized_flat.size() == kN && flat.size() == kN);
}
```

**Output, GCC 16.2 (one measured run):**

```text
N=4194304 random 64-bit keys (one measured run); smallest nonzero steady_clock step here: 100 ns
insert latency, every insert timed (so p50 is quantized to that step):
    unordered_map default           2139 ms  p50  300 ns  p99.9    7.9 us  max   263.8 ms  inserts > 1 ms:   6
    unordered_map reserve(N)        1523 ms  p50  200 ns  p99.9    7.9 us  max     0.2 ms  inserts > 1 ms:   0
    FlatMap default                  821 ms  p50  100 ns  p99.9    0.7 us  max    53.7 ms  inserts > 1 ms:   6
    FlatMap presized                 737 ms  p50  100 ns  p99.9    0.6 us  max     0.1 ms  inserts > 1 ms:   0
throughput and footprint (presized, untimed inner loops):
    unordered_map                  put 309.1 ns  get  51.3 ns   32 B/entry requested (+ heap header per node)
    FlatMap                        put  34.8 ns  get  21.8 ns   32 B/entry (2 x 8 B / load 0.5)
    hits found: 4194304 and 4194304 (expected 4194304 each); all maps hold N keys: true
```

**Output, Clang 21.1 (one measured run):**

```text
N=4194304 random 64-bit keys (one measured run); smallest nonzero steady_clock step here: 100 ns
insert latency, every insert timed (so p50 is quantized to that step):
    unordered_map default           2255 ms  p50  300 ns  p99.9   11.5 us  max   319.3 ms  inserts > 1 ms:   7
    unordered_map reserve(N)        1998 ms  p50  400 ns  p99.9   17.2 us  max     0.5 ms  inserts > 1 ms:   0
    FlatMap default                  768 ms  p50  100 ns  p99.9    0.6 us  max    49.2 ms  inserts > 1 ms:   6
    FlatMap presized                 757 ms  p50  100 ns  p99.9    0.7 us  max     0.2 ms  inserts > 1 ms:   0
throughput and footprint (presized, untimed inner loops):
    unordered_map                  put 438.8 ns  get 111.3 ns   40 B/entry requested (+ heap header per node)
    FlatMap                        put  32.8 ns  get  22.7 ns   32 B/entry (2 x 8 B / load 0.5)
    hits found: 4194304 and 4194304 (expected 4194304 each); all maps hold N keys: true
```

### 5.3 What the numbers say

| Metric | Java `HashMap<Long,Long>` | Java flat | C++ `unordered_map` (GCC / Clang) | C++ flat (GCC / Clang) |
|---|---|---|---|---|
| put, presized | 222 ns | 70 ns | 309 / 439 ns | 35 / 33 ns |
| get (50% hits) | 88 ns | 39 ns | 51 / 111 ns | 22 / 23 ns |
| bytes per entry | about 88 (heap delta) | about 33 | 32 / 40 requested, plus a heap header per node | 32 |
| worst single insert, not presized | 177 ms | 60 ms | 264 / 319 ms | 54 / 49 ms |
| worst single insert, presized | 169 ms (GC) | 0.2 ms | 0.2 / 0.5 ms | 0.1 / 0.2 ms |

* **The flat table is 3–12× faster on put and 2–5× on get.** Same Big-O, same hash quality. The node-based tables pay a heap allocation per insert and a dependent pointer load per lookup: the dependent-chase column of Listing 2.1, inside a "constant-time" operation.
* **Java's 88 bytes per entry for 16 bytes of payload.** A `HashMap.Node` (about 32 B), two boxed `Long`s (16 B each) and the table slot, plus allocator rounding. The flat table's 33 B is exactly 2 × 8 B at load factor ½. The node layout differs between C++ libraries: libstdc++ does not cache the hash for `std::hash<uint64_t>` (24-byte node + 8-byte bucket = 32 B), while libc++ always stores it (32-byte node + bucket = 40 B). The counting allocator measures **requested** bytes. The heap adds its own header to every node, so the real footprint is higher still.
* **"Amortized O(1)" has a tail, and it has two causes.** Without pre-sizing, the largest single insert took 49–60 ms for the flat tables (the final doubling rehashes 4 M entries) and 264–319 ms for `std::unordered_map`. Pre-sizing removed that entirely for both C++ tables and for the Java flat table: worst insert 0.1–0.5 ms. Java's `HashMap` still showed a **169 ms** insert when presized. That one was a garbage-collection pause, not a rehash: four collections ran while 4 M nodes and 8 M boxed `Long`s were promoted. The flat Java table triggered zero collections when presized. For latency-sensitive code the interview answer is *"pre-size, flatten, and keep allocation off the hot path. A p99.9 budget is a memory-layout decision."*
* **The timer is coarser than the operation.** Both `System.nanoTime` and `steady_clock` advanced in 100 ns steps on this Windows machine, so every per-insert p50 here is quantized (100, 200, 300 or 400 ns). Per-operation timing is only good for the tail. Means come from timing a whole loop and dividing, as the throughput section does. This is also why serious Java measurement uses JMH, which this KB deliberately avoids to keep listings self-contained ⚠.

**Where the production tables sit.** Abseil's Swiss tables, Rust's `hashbrown`, Folly's F14 and the Java primitive-collection libraries (fastutil, Eclipse Collections, Koloboke) are all flat, open-addressing designs. Most add SIMD-scanned metadata bytes so a probe compares 16 slots at once. C++23 `std::flat_map` is a different thing: a **sorted** pair of vectors with `O(log n)` binary-search lookup and `O(n)` insert. It is excellent for build-once, read-many maps and wrong for this workload.

---

## 6. The last 10 minutes: Extensions A, B and C

The three patterns in this file are scan/aggregate (§2), search (§4) and hash lookup (§5). Each one has an A/B/C story, and the hardware model above is what makes the answers concrete.

### 6.1 Extension A — "64 threads"

| Pattern | What changes with 64 threads | Mechanism | Cost / failure mode |
|---|---|---|---|
| Scan / aggregate | Memory bandwidth is shared. A DRAM-bound scan saturates at a few cores, and extra threads add nothing | Partition the array into contiguous chunks per thread, reduce privately, combine once | False sharing if per-thread accumulators sit in adjacent slots of one array: pad to 64 B or keep them on the thread's stack. Folder 01 File 1 measured padded vs packed counters: real but small, and not guaranteed |
| Search (read-only) | Nothing breaks: an immutable sorted or Eytzinger array is safely shared without locks | Publish once (final field / `const`), then read concurrently | Each core has its own L1/L2, so the hot top of the tree is replicated per core, which is good. A rebuild must publish a **new** array (copy-on-write) rather than mutate in place |
| Hash map | A shared mutable table needs synchronization; contention concentrates on hot keys and on resize | Striped locks or `ConcurrentHashMap` (per-bin locking, cooperative resize), or per-thread tables merged later | Resize under concurrency is the dangerous moment. Pre-size, and prefer a design where writers own disjoint key ranges (partition by `hash mod threads`) |

A line that shows hardware fluency: *"Past about 6–8 threads on one socket, a DRAM-bound loop is limited by bandwidth, not cores. I'd measure GB/s per thread before adding threads, and reduce the bytes per element first."*

### 6.2 Extension B — "100 TB, 1 GB of RAM"

The I/O model in §1.1 is the whole answer. Each level of the hierarchy is "fast memory of size `M`, slow memory moved in blocks of `B`", and the algorithm's job is to **minimize block transfers**.

* **Scan:** one pass over 100 TB at about 2–3 GB/s of sequential SSD or object-store throughput per reader is about 10–14 hours per reader. Parallel readers over byte ranges are mandatory, and each reader's working set stays in L2 if it processes one block at a time.
* **Search:** a sorted 100 TB file is searched with a **B+-tree / sparse index**. Keep one key per block (about 4 MiB blocks → 25 M index entries, a few hundred MB) in RAM, binary-search it, read one block. That is Eytzinger's idea at block granularity: make the first levels of every search hit fast memory. SSTables, Parquet row-group statistics and database B+-trees are all this.
* **Hash aggregation:** a hash table bigger than RAM thrashes. The external version **partitions first**: hash each key into `P` spill files, sized so each partition's table fits in memory, then aggregate one partition at a time. Two sequential passes instead of random I/O (File 1 §4.4; Folder 07).
* **Sort:** external merge sort costs `(N/B) log_{M/B}(N/B)` block transfers. With `M = 1 GB` and `B = 4 MiB` the fan-in is about 250, so 100 TB sorts in **two** merge passes after run generation. Folder 07 implements it; File 03's lazy k-way merge iterator is its inner loop.

### 6.3 Extension C — "100 machines"

The network is the next level of the hierarchy. Roughly: same-rack round trip in the hundreds of microseconds, cross-region tens of milliseconds, bandwidth per host 10–100 Gb/s ⚠ (order of magnitude; depends entirely on the fleet). The cost model becomes **bytes moved and round trips**, and the same three rules apply:

1. **Locality:** send the computation to the data (partition-local aggregation before any shuffle), just as a scan beats a pointer chase.
2. **Batching:** one RPC carrying 10,000 keys beats 10,000 RPCs, just as independent loads beat dependent ones. MLP's network cousin is pipelining.
3. **Layout:** partition so that the common query touches one shard (partition by the lookup key). A query that fans out to all 100 shards pays the **slowest** shard's latency: the tail at scale.

---

## 7. Failure modes

| # | Failure | Symptom | Prevention |
|---|---|---|---|
| F1 | Linked structure in a hot loop | 100+ ns per element once data exceeds L3 | Arrays, indices, flat tables; batch independent lookups |
| F2 | Trusting Big-O across layouts | "Optimal" code 5–10× slower than a "worse" one | Measure with production-sized data; name the access pattern |
| F3 | Unpredictable branch on hot data | 3 ns per element extra on random input, fine on sorted test data | Branch-free by construction, or sort/partition first; **verify codegen** |
| F4 | Assuming branchless always wins | Branch-free search slowest at 32–128 MiB | Branch-free in cache, speculation or prefetch out of cache |
| F5 | Assuming the compiler keeps your shape | Clang turned the select back into a branch; GCC `-O2` skipped vectorization | Read the assembly or benchmark per compiler; `-O3`/PGO where justified |
| F6 | Boxed collections on hot paths | 88 B per entry, 3× slower puts, GC pauses of 100+ ms | Primitive or flat maps; arrays of primitives; value-based layouts |
| F7 | Not pre-sizing | Single inserts of 50–320 ms during rehash | `HashMap.newHashMap(n)`, `reserve(n)`, presized arrays |
| F8 | Per-operation timing below the timer's resolution | Every p50 equal to 100 or 200 ns | Time loops and divide; use tails only for coarse events; JMH / Google Benchmark |
| F9 | Benchmarking cold code | First measurement includes JIT, page faults, cache warm-up | Warm up, take best-of-N or a distribution, report the range |
| F10 | Ignoring GC in latency budgets | p99.9 fine, max 169 ms | Allocation-free hot paths; measure GC count alongside latency |

---

## 8. Bar-raiser chains

<details><summary><b>Q1 · "Your linked-list solution and the array solution are both O(n). Which would you ship?"</b></summary>

**Initial Prompt.** The candidate implemented a queue or graph adjacency as linked nodes.

**L5 Answer.** "They're the same complexity, so either. Linked lists have O(1) insert."

**Why L5 Stalls.** It treats the RAM model as reality. In this file the same `O(n)` traversal cost 1.2 ns per element in L1 and 130–140 ns per element when each address depended on the previous load.

**L7 Answer.** "The array, unless the workload is dominated by middle insertions. Traversal is where the time goes. Following pointers is one dependent cache miss per node once the data outgrows L3, about 100+ ns each on a laptop, while a contiguous scan runs at memory bandwidth and the prefetcher hides the latency. Even with random access, an index array keeps addresses independent, so the core overlaps 10+ misses; I measured about 10× for that alone. For a graph I'd use CSR (offsets + flat edge array) rather than lists of nodes."
</details>

<details><summary><b>Q2 · "Why is processing sorted data faster?"</b></summary>

**Initial Prompt.** The classic branch-prediction question, often from the Stack Overflow example.

**L5 Answer.** "Branch prediction: sorted data makes the branch predictable."

**Why L5 Stalls.** Correct but stops at the textbook. It doesn't say how much, whether it still happens, or what to do about it.

**L7 Answer.** "When the branch depends on random data, about half the predictions miss, and each miss costs a pipeline refill: about 6 ns per miss on the laptop I measured, about 3 ns per element. But the famous loop often doesn't reproduce today. GCC and Clang if-converted and vectorized it, so sorted and shuffled ran the same; Java's C2 kept the branch and showed the 10× gap. So the real answer is: make the branch predictable or make it data, then check what the compiler did. For a filter with a conditional store, where the compiler can't help, 'always store, advance by the condition' was flat on every build."
</details>

<details><summary><b>Q3 · "Binary search is optimal. How would you make lookups faster?"</b></summary>

**Initial Prompt.** A read-heavy service does millions of `lower_bound` calls on a large static sorted array.

**L5 Answer.** "It's already O(log n); maybe a hash map for exact matches."

**Why L5 Stalls.** A hash map doesn't support `lower_bound` (range or predecessor queries). And "optimal" refers to comparisons, not to cache misses, which are what the hardware charges for.

**L7 Answer.** "Binary search is optimal in comparisons, but each level is a likely cache miss with poor locality. I'd change the layout: Eytzinger (BFS) order so the top levels of every search share a few cache lines, a branch-free descent, and a prefetch of the node four levels down. I measured 120–136 ns per query at 128 MiB against 700–1,350 ns for `std::lower_bound`. If the array is on disk, the same idea at page granularity is a B+-tree. And if queries arrive in batches, I'd sort the batch and do one merge-like sweep."
</details>

<details><summary><b>Q4 · "You wrote it branchless. Is it faster?"</b></summary>

**Initial Prompt.** The candidate replaced an `if` with a ternary or mask to "avoid branch misprediction".

**L5 Answer.** "Yes, branchless code avoids mispredictions."

**Why L5 Stalls.** Two unverified assumptions: that the compiler kept it branch-free, and that branch-free is faster at this data size.

**L7 Answer.** "Not necessarily, on either count. In my measurements Clang compiled both my ternary and my arithmetic-mask versions into branches; the assembly showed a `jl` and no `cmov`. Even when it is branch-free, out-of-cache it can lose: a branch lets the core speculatively start the next load, a select makes it wait. In cache, branch-free won 3–6×; at 128 MiB it was the slowest variant. So I'd look at the generated code and benchmark at the production data size."
</details>

<details><summary><b>Q5 · "HashMap lookups are O(1). Why is this service's p99.9 bad?"</b></summary>

**Initial Prompt.** A latency-sensitive Java service builds a large `HashMap<Long, ...>` at startup and keeps inserting.

**L5 Answer.** "Maybe hash collisions; use a better hash function."

**Why L5 Stalls.** With random keys collisions aren't the issue. The tail comes from resize and from the garbage collector, both invisible in Big-O.

**L7 Answer.** "Amortized O(1) has two tails. A resize rehashes everything: one insert in millions took 50–320 ms in my measurements without pre-sizing. And with boxed keys and values every insert allocates three objects, so the collector eventually moves millions of them; even presized, one insert took 169 ms because a GC pause landed on it. Fixes: pre-size, switch to a primitive open-addressing map (88 B to 33 B per entry, 3× faster puts, zero GCs), and measure tails with a histogram rather than per-operation timers, which on that machine only resolve 100 ns."
</details>

<details><summary><b>Q6 · "Would you use std::unordered_map here?"</b></summary>

**Initial Prompt.** C++ performance round: a hot lookup table of 64-bit keys.

**L5 Answer.** "Yes, it's the standard hash map, average O(1)."

**Why L5 Stalls.** The standard's iterator- and reference-stability guarantees force a node-based design: one allocation per element and a pointer chase per lookup.

**L7 Answer.** "Not on a hot path. The standard requires references to stay valid across rehash, which effectively mandates one heap node per element. I measured 309–439 ns per insert and 51–111 ns per lookup, against 33–35 ns and 22–23 ns for a flat open-addressing table. Footprint also depends on the library: libc++ caches the hash in every node, 40 vs 32 requested bytes per entry. I'd use a flat table (Abseil `flat_hash_map`, Boost `unordered_flat_map`, or a small hand-rolled one), pre-sized, and keep `unordered_map` for when I need stable references."
</details>

<details><summary><b>Q7 · "Add more threads to make the scan faster?"</b></summary>

**Initial Prompt.** A single-threaded scan of a 10 GB array takes 1 s; the candidate is asked to parallelize.

**L5 Answer.** "Split into 64 chunks, 64 threads, about 64× faster."

**Why L5 Stalls.** A DRAM-bound scan is limited by memory bandwidth shared by all cores, not by instruction throughput.

**L7 Answer.** "First, is it compute-bound or bandwidth-bound? 10 GB in 1 s is 10 GB/s, already near what one laptop core can stream; a socket might give 3–5× more in total, not 64×. I'd use as many threads as it takes to saturate bandwidth, measured as GB/s per added thread. Then cut the bytes per element: narrower types, columnar layout, compression. Fewer bytes is the only lever once bandwidth is saturated. And chunks must be contiguous per thread, with private accumulators that aren't adjacent in memory."
</details>

<details><summary><b>Q8 · "How do you know your benchmark is right?"</b></summary>

**Initial Prompt.** The candidate quotes a microbenchmark result.

**L5 Answer.** "I ran it and timed it with `System.nanoTime`."

**Why L5 Stalls.** One run, cold, with an unknown timer resolution, and no check that the compiler didn't delete the work.

**L7 Answer.** "I warm up (JIT, page faults, caches), take best-of-N or a distribution, consume every result so dead-code elimination can't remove the work, and check that all variants compute the same answer. That's what the checksums and 'answers agree' columns are for. I time whole loops, because on that machine the clock only advanced in 100 ns steps. For anything that gates a decision I'd use JMH or Google Benchmark, pin the CPU frequency if possible, and report ranges across runs. And I'd confirm the mechanism with a second signal: assembly for codegen claims, GC counts for latency claims."
</details>

---

## 9. Checklist

* [ ] For every loop on the hot path, name the **access pattern**: sequential, strided, random-independent, or dependent.
* [ ] Know this machine's rungs: about 1 ns L1, about 3–5 ns L2, 13+ ns L3, about 100+ ns DRAM dependent.
* [ ] Prefer arrays and indices over pointers; CSR over adjacency lists; flat tables over node-based maps.
* [ ] Turn dependent loads into independent ones (batching, index arrays) or prefetch when the address is computable.
* [ ] Unpredictable branch on hot data → make it data; **then verify** the compiler kept it that way.
* [ ] Branch-free wins in cache; speculation or prefetch wins out of cache. Benchmark at production size.
* [ ] Pre-size hash maps and arrays; keep allocation off hot paths; count GCs next to latency.
* [ ] Time loops, not single operations; know the timer's resolution; warm up; report ranges.
* [ ] Extension A: bandwidth, false sharing, publish immutable snapshots.
* [ ] Extension B: block transfers (`N/B`, `log_{M/B}`), sparse indexes / B+-trees, partition-then-aggregate.
* [ ] Extension C: bytes moved and round trips; locality, batching, partition by the lookup key.

---

## 10. References

* U. Drepper, *What Every Programmer Should Know About Memory* (2007) — <https://people.freebsd.org/~lstewart/articles/cpumemory.pdf>
* P.-V. Khuong, P. Morin, *Array Layouts for Comparison-Based Searching*, ACM JEA 22 (2017) — <https://arxiv.org/abs/1509.05053>
* A. Aggarwal, J. S. Vitter, *The Input/Output Complexity of Sorting and Related Problems*, CACM 31(9), 1988 — DOI 10.1145/48529.48535
* M. Frigo, C. E. Leiserson, H. Prokop, S. Ramachandran, *Cache-Oblivious Algorithms*, FOCS 1999 — DOI 10.1109/SFFCS.1999.814600
* S. Edelkamp, A. Weiß, *BlockQuicksort: How Branch Mispredictions don't affect Quicksort* (2016) — <https://arxiv.org/abs/1604.06697>
* Stack Overflow, *Why is processing a sorted array faster than processing an unsorted array?* — <https://stackoverflow.com/questions/11227809/why-is-processing-a-sorted-array-faster-than-processing-an-unsorted-array>
* A. Fog, *The microarchitecture of Intel, AMD and VIA CPUs* — <https://www.agner.org/optimize/microarchitecture.pdf>
* GCC optimization options (`-O2` and the vectorizer cost model) — <https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html>
* LLVM source: x86 cmov conversion pass — <https://github.com/llvm/llvm-project/blob/main/llvm/lib/Target/X86/X86CmovConversion.cpp>; CodeGenPrepare — <https://github.com/llvm/llvm-project/blob/main/llvm/lib/CodeGen/CodeGenPrepare.cpp>
* Abseil, *Swiss Tables Design Notes* — <https://abseil.io/about/design/swisstables>
* Java SE 21 API: `HashMap.newHashMap` — <https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/HashMap.html>; `System.nanoTime` — <https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/lang/System.html>
* cppreference: `std::unordered_map` (reference stability) — <https://en.cppreference.com/w/cpp/container/unordered_map>; `std::flat_map` — <https://en.cppreference.com/w/cpp/container/flat_map>
* JMH (Java Microbenchmark Harness) — <https://github.com/openjdk/jmh>; Google Benchmark — <https://github.com/google/benchmark>

*Folder 01:* [01 — how bar-raisers grade](01-how-bar-raisers-grade-l5-vs-l6-vs-l7-in-45-minute-coding-rounds.md) · [03 — API hygiene, immutability, custom iterators and test-driven verification](03-api-hygiene-immutability-custom-iterators-and-test-driven-verification.md)
