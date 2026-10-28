# 03 · Hash tables: `unordered_map` chaining vs Swiss tables, hash flooding, and `flat_map`

> **Scope.** The standard unordered containers are *node-based separate chaining* tables. That design follows from
> the standard's guarantees (stable references, bucket interface), and it costs a pointer chase per lookup. This
> file measures their policies (prime bucket counts, the identity hash for integers), shows a collision attack
> that turns a 3 ns lookup into 38 µs, builds the core of a Swiss table (open addressing with SIMD control bytes),
> and compares all of it with ordered alternatives, including C++23 `std::flat_map`.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 3.8 | `bucket_stats.cpp` | bucket-count sequences (different per library), `std::hash<int>` = identity, a 20,000-long chain, **3 ns → 38 µs** | run, both libraries |
| 3.9 | `swiss_set.cpp` | control bytes + 16-wide SSE2 probing; hits 23 vs 49–72 ns, misses 14–15 vs 57–96 ns against `unordered_set` | run, both libraries (timed) |
| 3.10 | `lookup_bench.cpp` | `map` vs `flat_map` vs sorted vector vs `unordered_map` at 10³/10⁵/10⁶ elements | run, both libraries (timed) |

**Verification line.** As for files 01–02. Benchmarks are single runs on a laptop (12 logical cores, one thread
used). They show ratios and trends, not absolute numbers for your hardware.

---

## 1. First principles

### 1.1 Separate chaining, as the standard requires it

```text
 unordered_map<K,V> (libstdc++)                          node: [ next | pair<const K, V> ]          (16 B for <int,int>)
   buckets: [ * | * | . | * | ... ]   (prime count)            libc++ node: [ next | hash | pair ]   (24 B for <int,int>)
              |   |       |
              v   v       v            libstdc++ keeps ONE singly linked list of all nodes; a bucket points to
            node node     node         the node BEFORE its first element ("before-begin"), so erase is O(1)
              |                        and iteration walks a single list.
              v
            node                       lookup = hash -> bucket index (modulo a prime) -> walk the chain
 required by the standard: references stay valid across rehash; bucket(n), bucket_size(n), local iterators;
 max_load_factor() with average chain length <= 1  =>  nodes must be separate allocations
```

```cpp
// bucket_stats.cpp - std::unordered_map internals: bucket counts, std::hash<int>, chain lengths, a hostile key set
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <print>
#include <string>
#include <unordered_map>
#include <unordered_set>

int main() {
    // 1. Bucket-count policy as the table grows (max_load_factor = 1.0 by default).
    std::unordered_set<int> s;
    std::size_t last = 0;
    std::print("bucket_count after growth:");
    for (int i = 0; i < 5000; ++i) {
        s.insert(i);
        if (s.bucket_count() != last) std::print(" {}", last = s.bucket_count());
    }
    std::println("  (max_load_factor {})", s.max_load_factor());

    // 2. std::hash for integers is the identity function in both libraries.
    std::println("std::hash<int>{{}}(12345) = {}, std::hash<std::uint64_t>{{}}(1ull << 40) = {}", std::hash<int>{}(12345),
                 std::hash<std::uint64_t>{}(1ull << 40));

    // 3. Chain lengths for well-spread keys vs keys that are multiples of the bucket count.
    auto longest_chain = [](const std::unordered_set<std::uint64_t>& t) {
        std::size_t worst = 0;
        for (std::size_t b = 0; b < t.bucket_count(); ++b) worst = std::max(worst, t.bucket_size(b));
        return worst;
    };
    std::unordered_set<std::uint64_t> good, bad;
    good.reserve(20000);
    bad.reserve(20000);
    const std::uint64_t stride = bad.bucket_count();  // an attacker who knows the bucket count
    for (std::uint64_t i = 0; i < 20000; ++i) {
        good.insert(i * 7919);
        bad.insert(i * stride);
    }
    std::println("buckets={} longest chain: spread keys {}, keys = i * bucket_count {}", bad.bucket_count(),
                 longest_chain(good), longest_chain(bad));

    // 4. What that does to lookup time (all keys present, one run).
    auto time_lookups = [](const std::unordered_set<std::uint64_t>& t, std::uint64_t mul) {
        auto t0 = std::chrono::steady_clock::now();
        std::size_t hits = 0;
        for (std::uint64_t i = 0; i < 20000; ++i) hits += t.count(i * mul);
        auto t1 = std::chrono::steady_clock::now();
        return std::pair{hits, std::chrono::duration<double, std::nano>(t1 - t0).count() / 20000.0};
    };
    auto [h1, ns_good] = time_lookups(good, 7919);
    auto [h2, ns_bad] = time_lookups(bad, stride);
    std::println("lookup: spread keys {:.1f} ns, colliding keys {:.1f} ns (hits {} / {})", ns_good, ns_bad, h1, h2);
}
```

GCC 16.2 + libstdc++ (one run):

```text
bucket_count after growth: 13 29 59 127 257 541 1109 2357 5087  (max_load_factor 1)
std::hash<int>{}(12345) = 12345, std::hash<std::uint64_t>{}(1ull << 40) = 1099511627776
buckets=20753 longest chain: spread keys 1, keys = i * bucket_count 20000
lookup: spread keys 2.4 ns, colliding keys 38635.8 ns (hits 20000 / 20000)
```

Clang 21.1 + libc++ (one run):

```text
bucket_count after growth: 2 5 11 23 47 97 197 397 797 1597 3203 6421  (max_load_factor 1)
std::hash<int>{}(12345) = 12345, std::hash<std::uint64_t>{}(1ull << 40) = 1099511627776
buckets=20011 longest chain: spread keys 1, keys = i * bucket_count 20000
lookup: spread keys 5.0 ns, colliding keys 39243.3 ns (hits 20000 / 20000)
```

* **Bucket counts are primes in both libraries, with different sequences:** libstdc++ jumps 13 → 29 → 59 … (it
  over-allocates relative to the next prime after 2n), and libc++ starts at 2 and roughly doubles to the next prime
  (2 → 5 → 11 → 23 …). Prime moduli exist because of the next point.
* **`std::hash<int>` and `std::hash<uint64_t>` are the identity** in both libraries. With a power-of-two table, keys
  that differ only in high bits (pointers aligned to 16 bytes, IDs that are multiples of 1024) would all land in
  the same buckets. The prime modulo spreads them, at the cost of a 64-bit division per lookup.
* **Hash flooding.** An adversary who knows (or probes for) the bucket count sends keys that are multiples of it.
  All 20,000 keys landed in **one bucket**, and lookups went from 2.5–5 ns (over runs) to **~38 µs**, roughly 10,000× slower.
  Inserting n such keys costs O(n²). This is a real denial-of-service vector for any service that puts
  client-controlled values (headers, JSON keys, IDs) into a standard hash table with the default hash.

### 1.2 Open addressing, Swiss-table style (Listing 3.9)

```text
 control bytes:  [ 0x80 | 0x13 | 0x80 | 0x5A | 0x13 | ... ]   1 byte per slot: 0x80 = empty, 0x00..0x7F = H2
 slots:          [  --  |  k1  |  --  |  k2  |  k3  | ... ]   keys stored inline (no nodes, no pointers)
 hash(k) = mix(k)  ->  H1 = hash >> 7 (selects the starting group), H2 = hash & 0x7F (7-bit tag)
 probe one GROUP of 16 control bytes with one SSE2 compare:
   movemask(cmpeq(group, set1(H2)))   -> bitmask of slots whose tag matches  (check those keys)
   movemask(cmpeq(group, set1(EMPTY)))-> if any empty slot: the key is absent, stop
 expected work for a miss at load 0.5: one 16-byte load, two compares, no key comparisons (1/128 false-tag rate)
```

```cpp
// swiss_set.cpp - the core of a Swiss table (absl::flat_hash_map's design): control bytes + 16-wide SIMD probing
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <memory>
#include <print>
#include <random>
#include <unordered_set>
#include <vector>
#if defined(__SSE2__)
#include <emmintrin.h>
#endif

class SwissSet {
    // Control byte per slot: 0x80 = empty, 0x00..0x7F = full with the low 7 bits of the hash (H2).
    static constexpr std::int8_t kEmpty = static_cast<std::int8_t>(0x80);
    static constexpr std::size_t kGroup = 16;
    std::unique_ptr<std::int8_t[]> ctrl_;
    std::unique_ptr<std::uint64_t[]> slots_;
    std::size_t mask_ = 0, size_ = 0;  // capacity - 1 (power of two, multiple of kGroup)

    static std::uint64_t mix(std::uint64_t x) {  // std::hash<int> is the identity: mix before using bits
        x ^= x >> 33;
        x *= 0xff51afd7ed558ccdULL;
        x ^= x >> 33;
        return x;
    }
    // Bitmask of the slots in the 16-byte group at 'pos' whose control byte equals 'b'.
    std::uint32_t match(std::size_t pos, std::int8_t b) const {
#if defined(__SSE2__)
        __m128i g = _mm_loadu_si128(reinterpret_cast<const __m128i*>(ctrl_.get() + pos));
        return static_cast<std::uint32_t>(_mm_movemask_epi8(_mm_cmpeq_epi8(g, _mm_set1_epi8(b))));
#else
        std::uint32_t m = 0;           // portable fallback (AArch64 would use NEON vceqq_s8 + a narrowing trick)
        for (std::size_t i = 0; i < kGroup; ++i) m |= static_cast<std::uint32_t>(ctrl_[pos + i] == b) << i;
        return m;
#endif
    }

public:
    explicit SwissSet(std::size_t capacity_pow2) : mask_(capacity_pow2 - 1) {
        // kGroup extra control bytes mirror the first group so a probe never wraps inside one 16-byte load.
        ctrl_ = std::make_unique<std::int8_t[]>(capacity_pow2 + kGroup);
        std::memset(ctrl_.get(), 0x80, capacity_pow2 + kGroup);
        slots_ = std::make_unique<std::uint64_t[]>(capacity_pow2);
    }
    bool insert(std::uint64_t key) {  // no growth in this sketch: caller sizes for load factor <= 7/8
        std::uint64_t h = mix(key);
        auto h2 = static_cast<std::int8_t>(h & 0x7F);
        for (std::size_t pos = (h >> 7) & mask_;; pos = (pos + kGroup) & mask_) {
            for (std::uint32_t m = match(pos, h2); m; m &= m - 1) {
                std::size_t i = (pos + static_cast<std::size_t>(__builtin_ctz(m))) & mask_;
                if (slots_[i] == key) return false;
            }
            if (std::uint32_t e = match(pos, kEmpty)) {
                std::size_t i = (pos + static_cast<std::size_t>(__builtin_ctz(e))) & mask_;
                ctrl_[i] = h2;
                if (i < kGroup) ctrl_[mask_ + 1 + i] = h2;  // keep the mirror in sync
                slots_[i] = key;
                ++size_;
                return true;
            }
        }
    }
    bool contains(std::uint64_t key) const {
        std::uint64_t h = mix(key);
        auto h2 = static_cast<std::int8_t>(h & 0x7F);
        for (std::size_t pos = (h >> 7) & mask_;; pos = (pos + kGroup) & mask_) {
            for (std::uint32_t m = match(pos, h2); m; m &= m - 1)  // 1 in 128 false-positive rate per full slot
                if (slots_[(pos + static_cast<std::size_t>(__builtin_ctz(m))) & mask_] == key) return true;
            if (match(pos, kEmpty)) return false;  // an empty slot in the group ends the probe sequence
        }
    }
    std::size_t size() const { return size_; }
};

template <class F>
double ns(std::size_t n, F f) {
    auto t0 = std::chrono::steady_clock::now();
    std::size_t hits = 0;
    for (std::size_t i = 0; i < n; ++i) hits += f(i);
    auto t1 = std::chrono::steady_clock::now();
    if (hits == 7) std::println("");
    return std::chrono::duration<double, std::nano>(t1 - t0).count() / static_cast<double>(n);
}

int main() {
    constexpr std::size_t kN = 1'000'000;
    std::mt19937_64 rng(7);
    std::vector<std::uint64_t> keys(kN), misses(kN);
    for (auto& k : keys) k = rng();
    for (auto& k : misses) k = rng();
    SwissSet sw(std::size_t{1} << 21);  // 2M slots: load factor 0.48
    std::unordered_set<std::uint64_t> us;
    us.reserve(kN);
    for (auto k : keys) {
        sw.insert(k);
        us.insert(k);
    }
    std::vector<std::size_t> order(kN);
    for (std::size_t i = 0; i < kN; ++i) order[i] = rng() % kN;
    std::println("1M uint64 keys, random-order lookups (one run):");
    std::println("  hits  : SwissSet {:5.1f} ns   unordered_set {:5.1f} ns",
                 ns(kN, [&](std::size_t i) { return sw.contains(keys[order[i]]); }),
                 ns(kN, [&](std::size_t i) { return us.count(keys[order[i]]) != 0; }));
    std::println("  misses: SwissSet {:5.1f} ns   unordered_set {:5.1f} ns",
                 ns(kN, [&](std::size_t i) { return sw.contains(misses[order[i]]); }),
                 ns(kN, [&](std::size_t i) { return us.count(misses[order[i]]) != 0; }));
    std::println("  memory: SwissSet {} MB (1 control byte + 8 key bytes per slot); size={}",
                 ((std::size_t{1} << 21) * 9) >> 20, sw.size());
}
```

GCC 16.2 (one run):

```text
1M uint64 keys, random-order lookups (one run):
  hits  : SwissSet  23.2 ns   unordered_set  49.6 ns
  misses: SwissSet  11.9 ns   unordered_set  57.3 ns
  memory: SwissSet 18 MB (1 control byte + 8 key bytes per slot); size=1000000
```

Clang 21.1 (one run):

```text
1M uint64 keys, random-order lookups (one run):
  hits  : SwissSet  26.3 ns   unordered_set  77.4 ns
  misses: SwissSet  18.4 ns   unordered_set 104.5 ns
  memory: SwissSet 18 MB (1 control byte + 8 key bytes per slot); size=1000000
```

* **2–4× faster than `std::unordered_set`** for hits and much more for misses, with 9 bytes per slot (18 MB for 2M
  slots) against ~16–24 B per node plus buckets plus malloc headers.
* **Misses are the Swiss table's best case**: an empty control byte in the first group ends the probe after one
  16-byte load. `unordered_set` must walk the chain or at least load the bucket and compare.
* **The hash must be mixed** before splitting into H1/H2 (`mix()` here; absl uses a strong mixing hash), because
  the standard integer hash is the identity (§1.1).
* What this sketch leaves out, and production versions (absl `flat_hash_map`, boost `unordered_flat_map`, folly
  F14) handle: growth and rehash; deletion with tombstones (or F14's overflow counts); triangular probing over groups
  instead of linear; `std::hash` adapters; NEON on ARM64, where there is no direct `movemask` and a narrowing shift
  (`vshrn`) is used to build the mask; and the price of open addressing: **elements move on rehash**, so pointers
  and references are not stable. That is the reason `std::unordered_map` cannot be specified this way.

### 1.3 Sorted contiguous storage: `flat_map` and friends (Listing 3.10)

C++23 `std::flat_map` stores keys and values in two separate sorted sequences (by default two `std::vector`s).
Lookup is a binary search over a contiguous key array. Insertion is O(n), because elements shift.

```cpp
// lookup_bench.cpp - the same lookups against map, flat_map, a sorted vector and unordered_map (one run)
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <flat_map>
#include <map>
#include <print>
#include <random>
#include <unordered_map>
#include <utility>
#include <vector>

template <class F>
double ns_per_op(const std::vector<std::uint32_t>& probes, F f) {
    auto t0 = std::chrono::steady_clock::now();
    std::uint64_t sum = 0;
    for (auto k : probes) sum += f(k);
    auto t1 = std::chrono::steady_clock::now();
    if (sum == 1) std::println("");
    return std::chrono::duration<double, std::nano>(t1 - t0).count() / static_cast<double>(probes.size());
}

int main() {
    std::mt19937 rng(42);
    for (std::size_t n : {std::size_t{1'000}, std::size_t{100'000}, std::size_t{1'000'000}}) {
        std::vector<std::uint32_t> keys(n);
        for (auto& k : keys) k = static_cast<std::uint32_t>(rng());
        std::map<std::uint32_t, std::uint32_t> m;
        std::unordered_map<std::uint32_t, std::uint32_t> um;
        um.reserve(n);
        for (auto k : keys) {
            m.emplace(k, k);
            um.emplace(k, k);
        }
        std::flat_map<std::uint32_t, std::uint32_t> fm(m.begin(), m.end());
        std::vector<std::pair<std::uint32_t, std::uint32_t>> sv(m.begin(), m.end());
        std::vector<std::uint32_t> probes(1'000'000);
        for (auto& p : probes) p = keys[rng() % n];      // all hits, random order

        double t_map = ns_per_op(probes, [&](std::uint32_t k) { return m.find(k)->second; });
        double t_flat = ns_per_op(probes, [&](std::uint32_t k) { return fm.find(k)->second; });
        double t_vec = ns_per_op(probes, [&](std::uint32_t k) {
            return std::lower_bound(sv.begin(), sv.end(), k, [](const auto& e, std::uint32_t x) { return e.first < x; })
                ->second;
        });
        double t_um = ns_per_op(probes, [&](std::uint32_t k) { return um.find(k)->second; });
        std::println("n={:>9}: map {:6.1f}  flat_map {:6.1f}  sorted vector {:6.1f}  unordered_map {:6.1f}  ns/lookup", n,
                     t_map, t_flat, t_vec, t_um);
    }
}
```

GCC 16.2 + libstdc++ (one run):

```text
n=     1000: map   40.6  flat_map   44.8  sorted vector   44.1  unordered_map    9.7  ns/lookup
n=   100000: map  217.4  flat_map   70.7  sorted vector   75.2  unordered_map   16.6  ns/lookup
n=  1000000: map  710.8  flat_map  112.3  sorted vector  127.2  unordered_map   41.4  ns/lookup
```

Clang 21.1 + libc++ (one run):

```text
n=     1000: map   27.2  flat_map   14.3  sorted vector   11.4  unordered_map    8.8  ns/lookup
n=   100000: map   88.7  flat_map   38.1  sorted vector   39.3  unordered_map   14.3  ns/lookup
n=  1000000: map  410.0  flat_map  100.4  sorted vector   84.7  unordered_map   42.9  ns/lookup
```

* **At 10⁶ elements `std::map` costs 384–684 ns per lookup**: ~20 levels of pointer chasing, each a likely cache
  miss. `flat_map` and a sorted vector cost ~90–118 ns (the search still touches ~20 cache lines, but they are
  prefetch-friendly near the end). `unordered_map` costs ~40 ns (one bucket + one node).
* **At 10³ elements GCC's binary search is 3.5× slower than Clang's** (42 vs 12 ns for `flat_map`). The data fits
  in L1. The difference is branch prediction: a branchy binary search mispredicts about half its branches on
  random probes, while a branchless one (conditional moves) does not. Same algorithm, same complexity, different
  codegen. For small hot tables a branchless `lower_bound` or a linear SIMD scan wins.
* `flat_map` ≈ sorted `vector<pair>` for lookup. Its advantage is the separate key array (denser search, better
  when values are large) and the map interface.

---

## 2. Evolution table

| Feature | Standard (paper) | Notes |
|---|---|---|
| `unordered_map`/`set` | C++11 (from TR1) | chaining forced by the bucket API and reference stability |
| `reserve`, `max_load_factor`, `rehash` | C++11 | — |
| `try_emplace`, `insert_or_assign`, node handles | C++17 | node handles also work for unordered containers |
| heterogeneous lookup (transparent hash + equality) | C++20 (P0919, P1690) | file 02 |
| `contains`, `erase_if` | C++20 | — |
| `flat_map`, `flat_set`, `flat_multimap`, `flat_multiset` | C++23 (P0429, P1222) | both libraries here (`__cpp_lib_flat_map`) |
| heterogeneous `try_emplace`/`operator[]`/`bucket` | C++26 (P2363) | libstdc++ 16 |
| open-addressing standard container | — | none; absl/boost/folly provide them |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| hash table keyed by client-controlled data | `std::unordered_map<std::string, V>` with `std::hash` | a seeded, strong hash (SipHash-style, or absl's randomized hash per process); cap request sizes |
| integer keys with structure (pointers, multiples of 2ᵏ) | power-of-two custom table with identity hash | mix the hash (multiply-shift / `mix()` in Listing 3.9) |
| lookup-heavy table, no reference stability needed | `std::unordered_map` | `absl::flat_hash_map` / `boost::unordered_flat_map` |
| small read-mostly map (< ~100 entries) | `std::map` | sorted `std::vector` / `flat_map` with a branchless or linear search |
| build once, query forever | `unordered_map` with incremental inserts | `reserve(n)` first, or a perfect hash / sorted array built offline |
| references to elements kept elsewhere | open-addressing table | node-based table, or store indices into a separate stable array |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| CPU pegged by a few requests with "weird" IDs | hash flooding into one bucket | `bucket_size` histogram; per-request key-count limits |
| lookups slower on one platform | different bucket policies / node layouts / branchy binary search | per-library benchmarks with production key distributions |
| a pointer into a flat hash map dangles after an insert | open addressing moves elements on rehash | never hold pointers into open-addressing tables across inserts |
| iteration order changed after a library upgrade | unordered iteration order is unspecified | never depend on it (tests, serialization) |
| `rehash` latency spike | growth rehashes all n elements | `reserve` up front; incremental-rehash tables if latency-critical |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "Is unordered_map lookup O(1)?"</b></summary>

**Initial prompt.** "What's the complexity of `unordered_map::find`?"

**L5 textbook answer.** "O(1) on average, O(n) worst case."

**Why L5 breaks.** True, and the worst case is not theoretical. With the identity `std::hash` and a known bucket
count, choosing keys that are multiples of `bucket_count()` puts every key into one chain. Listing 3.8: 2.5–5 ns
became ~38 µs per lookup with 20,000 keys. Insertion of n such keys is O(n²). Any service that hashes untrusted input
with the default hash can be taken down this way.

**L7 principal defense.** "Average O(1) needs a hash the adversary can't predict. For untrusted keys I use a seeded,
keyed hash (per-process random seed), limit the number of keys per request, and monitor the longest chain. For
trusted integer keys I still mix the hash, because structure in the keys (pointers, aligned IDs) defeats the
identity hash with power-of-two tables."
</details>

<details><summary><b>Chain 2 ⚡ "Why is absl::flat_hash_map faster than std::unordered_map?"</b></summary>

**Initial prompt.** "Explain why Swiss tables beat `std::unordered_map`."

**L5 textbook answer.** "Better hash function and open addressing."

**Why L5 breaks.** Open addressing is the start. The real mechanisms (Listing 3.9): (1) no node allocation, keys
inline in a slot array; (2) a separate array of 1-byte control tags, so one 16-byte SIMD compare checks 16 slots at
once; (3) the 7-bit tag filters out almost all non-matching slots without touching the keys (1/128 false-positive
rate); (4) a miss usually ends at the first empty tag in the first group. Measured: hits 23 vs 49–72 ns, misses
14–15 vs 57–96 ns. The trade-off is reference stability, which `std::unordered_map` guarantees and a Swiss table
cannot.

**L7 principal defense.** "Swiss tables win on cache behaviour and branch-free filtering, not on big-O. I use them
for lookup-heavy tables without pointer stability requirements, keep `std::unordered_map` where references must
survive inserts, and check the ARM64 path (NEON emulation of `movemask`) when we ship on Graviton."
</details>

<details><summary><b>Chain 3 🧊 "Why doesn't the standard specify open addressing?"</b></summary>

**Initial prompt.** "If open addressing is faster, why does the standard mandate chaining?"

**L5 textbook answer.** "Historical reasons; it was designed before cache effects mattered."

**Why L5 breaks.** It follows from the *interface* the standard specified in C++11: pointers and references to elements
must stay valid across rehash; `bucket(key)`, `bucket_size(n)` and local iterators expose the bucket structure;
`max_load_factor` can exceed 1; node handles can extract elements. All of these require one heap node per element.
Changing that now is an ABI and API break for every user.

**L7 principal defense.** "The bucket API locked the implementation. So the ecosystem moved to library types (absl,
boost 1.81+ `unordered_flat_map`, folly F14) with different guarantees. In code review I treat the choice as an
interface decision: does any caller keep references into the table?"
</details>

<details><summary><b>Chain 4 ⚡ "map, flat_map, sorted vector or hash map for 1,000 entries?"</b></summary>

**Initial prompt.** "A config table with ~1,000 entries is read millions of times per second. Which container?"

**L5 textbook answer.** "`unordered_map` for O(1)."

**Why L5 breaks.** At 1,000 entries everything fits in L1/L2, so constants dominate. Listing 3.10 at n = 1000:
`unordered_map` 8.5–8.9 ns, Clang's `flat_map` 12 ns, but GCC's `flat_map` 42 ns, because of a branchy binary search
that mispredicts. `std::map` 25–38 ns. The right answer depends on the compiler's codegen for the search, not only on
the data structure.

**L7 principal defense.** "For a small read-mostly table: a hash map with a cheap hash, or a sorted array with a
*branchless* lower_bound (which I'd write explicitly rather than trust the library's codegen). I'd keep it immutable
and swap the whole table on update (RCU-style, Folder 09). Then I'd measure with the real key distribution on our
compiler."
</details>

<details><summary><b>Chain 5 🔥 "Can I hold a pointer into my hash map?"</b></summary>

**Initial prompt.** "We store `Session*` pointers that point into an `absl::flat_hash_map<id, Session>`. Safe?"

**L5 textbook answer.** "Yes, as long as you don't erase the session."

**Why L5 corrupts memory.** In an open-addressing table *any insert* can trigger a rehash that moves every element
(that is what the slot array is). All saved pointers then dangle. With `std::unordered_map` they would stay valid,
because nodes don't move (file 04). The bug appears only when the table grows, often under peak load.

**L7 principal defense.** "Either store `std::unique_ptr<Session>` (or use `absl::node_hash_map`) so the session
object doesn't move, or hand out IDs and look them up. The container's stability guarantee is part of the design
decision, written next to the type."
</details>

<details><summary><b>Chain 6 🧊 "Why prime bucket counts?"</b></summary>

**Initial prompt.** "Why do libstdc++ and libc++ use prime bucket counts instead of powers of two?"

**L5 textbook answer.** "Primes distribute keys better."

**Why L5 breaks.** Only because the default integer hash is the identity (Listing 3.8). With identity hashing, a
power-of-two modulus uses only the low bits, so keys that differ in high bits collide. A prime modulus mixes all
bits into the index, at the cost of a 64-bit division (tens of cycles) per lookup. Tables with a strong hash
(absl, boost) use powers of two and a mask instead. Primes are also no defence against a determined attacker,
who can simply use multiples of the prime.

**L7 principal defense.** "Strong mixing hash + power-of-two mask is faster and at least as good. Prime moduli are a
workaround for weak hashes. Neither replaces a keyed hash for untrusted input."
</details>

<details><summary><b>Chain 7 ⚡ "Reserve or not?"</b></summary>

**Initial prompt.** "Does `reserve` matter for `unordered_map`?"

**L5 textbook answer.** "Not much; rehashing is amortized."

**Why L5 breaks.** Each growth rehashes every node (relinks all n nodes into new buckets) and allocates a new bucket
array: 7 (libstdc++) to 10 (libc++) bucket allocations for 1,000 elements (file 02, Listing 3.5). Amortized cost is
fine for throughput, but each rehash is a latency spike proportional to n, and it invalidates all iterators.

**L7 principal defense.** "`reserve(n)` when n is known or bounded, both for throughput and to remove the latency
spikes. For tables that grow without bound in latency-critical paths, I use designs with incremental rehash, or
shard the table so each rehash is small."
</details>

<details><summary><b>Chain 8 🔥 "Design a hash table for 100M IDs on a memory budget"</b></summary>

**Initial prompt.** "Store 100 million 64-bit IDs → 32-bit values. Minimize memory and lookup time."

**L5 textbook answer.** "`std::unordered_map<uint64_t, uint32_t>` with `reserve(100'000'000)`."

**Why L5 breaks.** libstdc++ nodes for `<uint64_t, uint32_t>` are ~24 bytes plus ~16 bytes of malloc overhead, plus 8
bytes per bucket pointer: ~5 GB, with a dependent pointer load per lookup. Allocation of 10⁸ nodes alone takes
seconds.

**L7 principal defense.** "Open addressing with inline slots: a control-byte array (1 B per slot) plus keys and values
in separate arrays (8 + 4 B) at 7/8 load factor is ~1.5 GB; or a sorted key array + parallel value array if the set is
static (1.2 GB, binary or interpolation search). Mixed hash, power-of-two size, SIMD tag probing (Listing 3.9), huge
pages for the arrays, and a build in one pass from a pre-sized layout. And I'd measure the miss path, because most
lookups in ID filters are misses."
</details>

---

## 6. Invariants checklist

- [ ] No default `std::hash` over attacker-controlled keys; keyed hash + per-request limits.
- [ ] Integer keys with structure are mixed before use in power-of-two tables.
- [ ] `reserve` before bulk insertion; rehash latency considered on hot paths.
- [ ] No pointers into open-addressing tables across inserts.
- [ ] Iteration order of unordered containers never relied on.
- [ ] Small hot tables benchmarked with branchless search vs hash on the shipped compilers.

## 7. References

- Abseil Swiss tables design notes: <https://abseil.io/about/design/swisstables>
- Matt Kulukundis, "Designing a Fast, Efficient, Cache-friendly Hash Table, Step by Step", CppCon 2017: <https://www.youtube.com/watch?v=ncHmEUmJZf4>
- Boost.Unordered `unordered_flat_map` design: <https://www.boost.org/doc/libs/release/libs/unordered/doc/html/unordered.html>
- folly F14: <https://github.com/facebook/folly/blob/main/folly/container/F14.md>
- P0429R9 (`flat_map`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2022/p0429r9.pdf>
- Crosby & Wallach, "Denial of Service via Algorithmic Complexity Attacks", USENIX Security 2003: <https://www.usenix.org/legacy/events/sec03/tech/full_papers/crosby/crosby.pdf>
