# 01 · Sorting and selection: introsort vs pdqsort, `stable_sort`, `nth_element`, erase-remove

> **Scope.** `std::sort` guarantees only O(n log n) comparisons and nothing about the algorithm. The two standard
> libraries ship different algorithms, and that is visible in comparison counts on structured inputs. This file
> identifies them from measurements, shows what an invalid comparator does and which checks catch it, and covers the
> selection and removal algorithms whose cost is regularly misjudged (`nth_element` vs `partial_sort`, the
> erase-remove idiom).

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 4.1 | `sort_patterns.cpp` | comparison counts on 6 input patterns: introsort (libstdc++) vs pattern-defeating quicksort (libc++); `stable_sort` costs | run, both libraries (counts deterministic, times one run) |
| 4.2 | `bad_comparator.cpp` | `<=` and NaN break strict weak ordering; two libraries "sort" NaN differently and both report `is_sorted`; debug/hardened modes catch `<=` | run ×3 configurations |
| 4.3 | `select_erase.cpp` | top-100 of 5M: `partial_sort` 2–4 ms beats `nth_element` 28–38 ms; erase-remove vs `erase_if` vs erase in a loop | run, both libraries (one run) |

**Verification line.** Native runs as in Folders 01–03: GCC 16.2 + libstdc++, Clang 21.1 + libc++, `-O2`. Comparison
counts are deterministic for a given library and input. Times are single runs on a laptop.

---

## 1. First principles

### 1.1 What the two `std::sort`s are (Listing 4.1)

```cpp
// sort_patterns.cpp - std::sort vs std::stable_sort across input patterns: comparisons counted, time measured
#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <numeric>
#include <print>
#include <random>
#include <string>
#include <vector>

static std::uint64_t g_cmp = 0;
struct Counting {
    bool operator()(int a, int b) const {
        ++g_cmp;
        return a < b;
    }
};

std::vector<int> make(const std::string& kind, std::size_t n) {
    std::vector<int> v(n);
    std::mt19937 rng(1);
    if (kind == "random") for (auto& x : v) x = static_cast<int>(rng());
    if (kind == "sorted") std::iota(v.begin(), v.end(), 0);
    if (kind == "reversed") std::iota(v.rbegin(), v.rend(), 0);
    if (kind == "organ pipe")
        for (std::size_t i = 0; i < n; ++i) v[i] = static_cast<int>(i < n / 2 ? i : n - i);
    if (kind == "few unique") for (auto& x : v) x = static_cast<int>(rng() % 4);
    if (kind == "sorted+1") {
        std::iota(v.begin(), v.end(), 0);
        v.back() = -1;                 // one element out of place at the end
    }
    return v;
}

int main() {
    constexpr std::size_t kN = 1'000'000;
    std::println("{:<12} {:>13} {:>9}   {:>13} {:>9}   (n = {}, n*log2(n) = {:.0f})", "pattern", "sort cmps", "ms",
                 "stable cmps", "ms", kN, kN * 19.93);
    for (std::string kind : {"random", "sorted", "reversed", "organ pipe", "few unique", "sorted+1"}) {
        auto a = make(kind, kN), b = a;
        g_cmp = 0;
        auto t0 = std::chrono::steady_clock::now();
        std::sort(a.begin(), a.end(), Counting{});
        auto t1 = std::chrono::steady_clock::now();
        std::uint64_t c1 = g_cmp;
        g_cmp = 0;
        std::stable_sort(b.begin(), b.end(), Counting{});
        auto t2 = std::chrono::steady_clock::now();
        auto ms = [](auto d) { return std::chrono::duration<double, std::milli>(d).count(); };
        std::println("{:<12} {:>13} {:>9.1f}   {:>13} {:>9.1f}   sorted ok: {}", kind, c1, ms(t1 - t0), g_cmp,
                     ms(t2 - t1), std::is_sorted(a.begin(), a.end()) && a == b);
    }
}
```

GCC 16.2 + libstdc++:

```text
pattern          sort cmps        ms     stable cmps        ms   (n = 1000000, n*log2(n) = 19930000)
random            24200959      56.0        19821602      67.8   sorted ok: true
sorted            25604781       9.2        11016700       9.6   sorted ok: true
reversed          18131082       6.7         9281750      11.1   sorted ok: true
organ pipe        54113388      45.4        10649223      10.9   sorted ok: true
few unique        18229837      15.0        17967398      24.2   sorted ok: true
sorted+1          59367144      59.2        11016706      10.0   sorted ok: true
```

Clang 21.1 + libc++:

```text
pattern          sort cmps        ms     stable cmps        ms   (n = 1000000, n*log2(n) = 19930000)
random            22414569      57.2        29920525      49.6   sorted ok: true
sorted             2000006       0.8         7982144      19.3   sorted ok: true
reversed           3000021       1.2        37019328      33.7   sorted ok: true
organ pipe        53737793      49.2        23000734      28.4   sorted ok: true
few unique         3499975       6.2        24458813      45.0   sorted ok: true
sorted+1           3000003       1.2         7982218      21.6   sorted ok: true
```

Reading the comparison counts (n = 10⁶, n·log₂n ≈ 2·10⁷):

| Pattern | libstdc++ `sort` | libc++ `sort` | What it reveals |
|---|---|---|---|
| random | 24.2M | 22.4M | both ~1.1–1.2 n log n: quicksort family |
| sorted | **25.6M** | **2.0M** | libc++ detects that a partition needed no swaps and finishes with bounded insertion-sort passes, the **pattern-defeating quicksort** technique |
| reversed | 18.1M | 3.0M | same detection after one reversal-like partition |
| few unique | 18.2M | 3.5M | pdqsort partitions equal keys together (three-way-like handling) |
| sorted + 1 | 59.4M | 3.0M | libstdc++'s median-of-3 introsort hits a bad pivot sequence: **3× its random-input cost** |
| organ pipe | 54.1M | 53.7M | both degrade, still bounded by the introsort fallback (heapsort at depth 2 log n) |

* **libstdc++'s `std::sort` is introsort**: quicksort with median-of-3 pivots, a final insertion sort over
  16-element runs, and a switch to heapsort when recursion exceeds 2·log₂n. It has no pattern detection, so
  already-sorted input costs as much as random input.
* **libc++'s `std::sort` is introsort extended with pdqsort's techniques** (read from its `__algorithm/sort.h`): it detects already-partitioned ranges (`__insertion_sort_incomplete`), groups equal keys (`__partition_with_equals_on_left`), uses bitset (branchless)
  partitioning for arithmetic types, and shuffles pivots on bad partitions. Sorted, reversed and few-unique inputs are
  near-linear.
* **`stable_sort` is merge sort in both**, using a temporary buffer when it can get one (O(n log n) comparisons;
  O(n log² n) if no buffer). libstdc++'s variant was faster on structured inputs here. libc++'s was faster on random
  input, slower on reversed (37M comparisons).
* None of these is **Timsort** (Python's and Java's object sort). Timsort finds natural runs and merges them; for data
  with long sorted runs it beats both. The standard does not require run detection, so if your data is "mostly
  sorted", measure your library or use a run-aware sort.

### 1.2 Strict weak ordering, and what breaks without it (Listing 4.2)

`std::sort` requires `comp` to be a *strict weak ordering*: irreflexive (`!comp(a, a)`), transitive, and with
transitive incomparability (if `a ~ b` and `b ~ c` then `a ~ c`, where `~` means neither is less).

```cpp
// bad_comparator.cpp - a comparator that is not a strict weak ordering ('<='), and the checks that catch it
#include <algorithm>
#include <cmath>
#include <print>
#include <vector>

int main() {
    std::vector<int> v(64, 7);         // many equal elements: the case where '<=' breaks partition loops
    for (int i = 0; i < 64; i += 3) v[static_cast<std::size_t>(i)] = i;
    auto bad = [](int a, int b) { return a <= b; };   // reflexive: bad(x, x) == true
    std::println("bad(7, 7) = {} (a strict weak ordering requires comp(x, x) == false)", bad(7, 7));

    std::vector<double> d{3.0, std::nan(""), 1.0, 2.0};
    std::sort(d.begin(), d.end(), [](double a, double b) { return a < b; });  // NaN breaks the ordering too
    std::println("sorting {{3, NaN, 1, 2}} with '<': {} {} {} {}  is_sorted: {}", d[0], d[1], d[2], d[3],
                 std::is_sorted(d.begin(), d.end()));
#ifdef RUN_BAD_SORT
    std::sort(v.begin(), v.end(), bad);  // UB: libstdc++'s unguarded partition can run past the range
    std::println("bad sort finished: is_sorted = {}", std::is_sorted(v.begin(), v.end()));
#else
    std::sort(v.begin(), v.end(), [](int a, int b) { return a < b; });
    std::println("good sort: is_sorted = {}", std::is_sorted(v.begin(), v.end()));
#endif
}
```

Default build (verified):

```text
GCC 16.2 + libstdc++:
bad(7, 7) = true (a strict weak ordering requires comp(x, x) == false)
sorting {3, NaN, 1, 2} with '<': 1 3 nan 2  is_sorted: true
good sort: is_sorted = true
```

```text
Clang 21.1 + libc++:
bad(7, 7) = true (a strict weak ordering requires comp(x, x) == false)
sorting {3, NaN, 1, 2} with '<': 3 nan 1 2  is_sorted: true
good sort: is_sorted = true
```

* **NaN breaks incomparability transitivity**: `1 ~ NaN` and `NaN ~ 3`, but `1 < 3`. The two libraries "sort" the same
  four values differently (`1 3 nan 2` vs `3 nan 1 2`), and **`std::is_sorted` returns `true` for both**, because it
  checks with the same broken comparator. The checking function cannot detect the bug it is meant to detect.
* **`<=` violates irreflexivity.** In libstdc++'s unguarded partition loops, `comp(x, pivot)` being true for equal
  elements lets the scan run past the end of the range: an out-of-bounds read, and potentially a crash or memory
  corruption with enough equal elements. The listing does not execute that in the default build.

With checks enabled, the `<=` sort is caught. libstdc++ debug mode (`-D_GLIBCXX_DEBUG`):

```text
[stderr] stl_algo.h:4847:
[stderr] In function:
[stderr]     constexpr void std::sort(_RAIter, _RAIter, _Compare) [with _RAIter = 
[stderr]     gnu_debug::_Safe_iterator<gnu_cxx::normal_iterator<int*, vector<int, 
[stderr]     allocator<int> > >, debug::vector<int>, random_access_iterator_tag>; 
[stderr]     _Compare = main()::<lambda(int, int)>]
[stderr] Error: comparison doesn't meet irreflexive requirements, assert(!(a < a)).
[exit code] 0xc0000409
```

libc++ hardening in debug mode (`_LIBCPP_HARDENING_MODE_DEBUG`), which checks the result of small sorts:

```text
[stderr] strict_weak_ordering_check.h:52: libc++ Hardening assertion !__comp(*(__first + __b), *(__first + __a)) failed: Your comparator is not a valid strict-weak ordering
[exit code] 0xc0000409
```

### 1.3 Selection and removal (Listing 4.3)

```cpp
// select_erase.cpp - top-k with nth_element / partial_sort / sort, and the erase-remove idiom vs std::erase_if
#include <algorithm>
#include <chrono>
#include <functional>
#include <list>
#include <print>
#include <random>
#include <vector>

template <class F>
double ms(F f) {
    auto t0 = std::chrono::steady_clock::now();
    f();
    auto t1 = std::chrono::steady_clock::now();
    return std::chrono::duration<double, std::milli>(t1 - t0).count();
}

int main() {
    constexpr std::size_t kN = 5'000'000, kK = 100;
    std::vector<int> base(kN);
    std::mt19937 rng(3);
    for (auto& x : base) x = static_cast<int>(rng());

    // Top-k largest. Three algorithms, same answer.
    auto a = base, b = base, c = base;
    double t_nth = ms([&] {
        std::nth_element(a.begin(), a.begin() + kK, a.end(), std::greater<>{});  // O(n) average
        std::sort(a.begin(), a.begin() + kK, std::greater<>{});                   // then order the k winners
    });
    double t_partial = ms([&] { std::partial_sort(b.begin(), b.begin() + kK, b.end(), std::greater<>{}); });  // heap
    double t_sort = ms([&] { std::sort(c.begin(), c.end(), std::greater<>{}); });
    bool same = std::equal(a.begin(), a.begin() + kK, b.begin()) && std::equal(b.begin(), b.begin() + kK, c.begin());
    std::println("top-{} of {}M ints: nth_element+sort {:.1f} ms, partial_sort {:.1f} ms, full sort {:.1f} ms (same: {})",
                 kK, kN / 1'000'000, t_nth, t_partial, t_sort, same);

    // Erasing every odd value.
    auto v1 = base, v2 = base;
    double t_idiom = ms([&] { v1.erase(std::remove_if(v1.begin(), v1.end(), [](int x) { return x & 1; }), v1.end()); });
    double t_erase_if = ms([&] { std::erase_if(v2, [](int x) { return x & 1; }); });  // C++20: the same algorithm
    std::vector<int> v3(base.begin(), base.begin() + 50'000);
    double t_naive = ms([&] {                                    // erase in a loop: O(n^2) element shifting
        for (auto it = v3.begin(); it != v3.end();)
            it = (*it & 1) ? v3.erase(it) : it + 1;
    });
    std::println("remove odd values: erase(remove_if) {:.1f} ms, std::erase_if {:.1f} ms (5M); erase-in-loop {:.1f} ms "
                 "for only 50k", t_idiom, t_erase_if, t_naive);
    std::println("sizes equal: {}", v1.size() == v2.size());

    // remove_if does not remove: it moves the kept elements forward and returns the new logical end.
    std::vector<int> demo{1, 2, 3, 4, 5, 6};
    auto new_end = std::remove_if(demo.begin(), demo.end(), [](int x) { return x % 2 == 0; });
    std::println("after remove_if: size still {}, kept prefix length {}", demo.size(), new_end - demo.begin());
    std::list<int> lst{1, 2, 3, 4, 5, 6};
    lst.remove_if([](int x) { return x % 2 == 0; });             // list: relinks nodes, really removes
    std::println("list::remove_if: size {}", lst.size());
}
```

GCC 16.2 + libstdc++ (one run):

```text
top-100 of 5M ints: nth_element+sort 36.8 ms, partial_sort 2.4 ms, full sort 333.7 ms (same: true)
remove odd values: erase(remove_if) 17.4 ms, std::erase_if 17.2 ms (5M); erase-in-loop 616.2 ms for only 50k
sizes equal: true
after remove_if: size still 6, kept prefix length 3
list::remove_if: size 3
```

Clang 21.1 + libc++ (one run):

```text
top-100 of 5M ints: nth_element+sort 29.2 ms, partial_sort 1.9 ms, full sort 137.1 ms (same: true)
remove odd values: erase(remove_if) 17.5 ms, std::erase_if 17.1 ms (5M); erase-in-loop 55.8 ms for only 50k
sizes equal: true
after remove_if: size still 6, kept prefix length 3
list::remove_if: size 3
```

* **For a small k, `partial_sort` beats `nth_element`.** `partial_sort(first, first + k, last)` keeps a max-heap of k
  elements and makes *one* comparison per remaining element (`x < heap.top()`), and that comparison is almost always
  false for random data, so it is perfectly predicted. Cost ≈ n + (#replacements)·log k. `nth_element` is O(n) on
  average, but it is a full introselect with partitioning passes over all 5M elements (28–38 ms vs 2–4 ms here).
  For large k (say n/2), `nth_element` wins.
* **`remove_if` does not remove.** It moves kept elements to the front and returns the new logical end. The size is
  unchanged until `erase(new_end, end())`. C++20 `std::erase_if` is the same algorithm in one call (equal timings).
* **Erase in a loop is O(n²).** Each `erase` shifts the tail. 50k elements took 57 ms (Clang) and 593 ms (GCC), against
  ~17 ms for 5M elements with the idiom. The libstdc++ single-element `erase` was 10× slower than libc++'s here.
* **Node containers really remove**: `list::remove_if` relinks nodes, and the size changes.

---

## 2. Evolution table

| Algorithm feature | Standard (paper) | Notes |
|---|---|---|
| `std::sort` O(n log n) **worst case** required | C++11 (LWG 713) | C++03 required only average O(n log n); introsort satisfies the new rule |
| `is_sorted`, `is_partitioned`, `minmax_element`, `all_of`… | C++11 | — |
| parallel overloads (`std::execution::par`) | C++17 (P0024) | libstdc++ needs TBB for real parallelism; libc++ 21 does not define the macro |
| `std::erase`/`std::erase_if` | C++20 (P1209) | uniform removal |
| constrained algorithms (`std::ranges::sort` etc.) with projections | C++20 (P0896) | file 02 |
| `constexpr` sort and most algorithms | C++20 (P0879) | — |
| `ranges::fold_left`, `ranges::contains`, `ranges::find_last` | C++23 (P2322, P2302, P1223) | — |
| `std::ranges::` parallel algorithms | C++26 (P3179) | — |
| debug checks of strict weak ordering | library QoI | libstdc++ debug mode, libc++ hardening `debug` |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| sorting structs with a float key | `a.price < b.price` with possible NaN | reject NaN at ingestion, or `std::strong_order(a.price, b.price) < 0` (total order, NaN last) |
| "descending" comparator | `a >= b` | `a > b` (or `std::greater<>{}`) |
| multi-key comparison | nested `if`s that miss a case | `std::tie(a.x, a.y) < std::tie(b.x, b.y)`, or a defaulted `<=>` |
| top-k with small k | `sort` then take k | `partial_sort` (or a bounded heap); `nth_element` for large k |
| removing elements from a vector | `erase` inside a loop | `std::erase_if(v, pred)` |
| mostly-sorted input on libstdc++ | `std::sort` | measure; libc++'s pdqsort or a run-aware sort may be 10× cheaper |
| sorting in a test | trust `is_sorted` | assert with an independent check (e.g. a reference sort with `std::strong_order`) |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| crash or garbage inside `std::sort` | non-strict comparator (`<=`) or a comparator with side effects | `_GLIBCXX_DEBUG`; libc++ hardening `debug` |
| "sorted" output in a different order on macOS vs Linux | invalid ordering (NaN), or equal keys with `sort` (not stable) | `std::strong_order`; `stable_sort` when ties matter |
| a sort 3× slower than expected on nearly-sorted data (Linux) | libstdc++ introsort without pattern detection | profile per library |
| an O(n²) cleanup loop | erase inside iteration | `erase_if` |
| `remove_if` "didn't remove anything" | missing `erase` | use `erase_if` |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "What algorithm does std::sort use?"</b></summary>

**Initial prompt.** "What algorithm is `std::sort`, and what is its complexity?"

**L5 textbook answer.** "Quicksort, O(n log n) average, O(n²) worst."

**Why L5 breaks.** Since C++11 the standard requires O(n log n) comparisons in the *worst* case, which plain quicksort
cannot meet. libstdc++ uses introsort (quicksort + heapsort fallback + insertion sort). libc++ uses a pattern-defeating
quicksort. Listing 4.1 tells them apart: on already-sorted input libstdc++ makes 25.6M comparisons, libc++ 2.0M. On
"sorted + 1" libstdc++ makes 59.4M, 3× its random-input count.

**L7 principal defense.** "Introsort guarantees the bound. pdqsort adds adaptivity to patterns (sorted, reversed, few
distinct keys) and branchless block partitioning. The workload decides which matters: for mostly-sorted feeds on
libstdc++ I'd benchmark alternatives (pdqsort, a run-aware sort, or insertion of the few new elements into the
already-sorted data)."
</details>

<details><summary><b>Chain 2 🔥 "What happens with a <= comparator?"</b></summary>

**Initial prompt.** "A teammate sorted descending with `[](auto a, auto b) { return a >= b; }`. Tests pass. Problem?"

**L5 textbook answer.** "It works, just not stable."

**Why L5 corrupts memory.** `>=` is reflexive, so it is not a strict weak ordering, and `std::sort`'s behaviour is
undefined. In libstdc++'s unguarded partition, the scan relies on `comp(x, pivot)` becoming false. With equal keys it
never does, so the loop walks past the end of the range: out-of-bounds reads, and with enough duplicates a crash or
corrupted memory. Tests with few duplicates pass. Debug mode reports it immediately (Listing 4.2: "comparison doesn't
meet irreflexive requirements").

**L7 principal defense.** "`std::greater<>{}` or `a > b`. Comparators are pure strict weak orderings. CI runs the test
suite once under `_GLIBCXX_DEBUG` and once under libc++ debug hardening, both of which check this."
</details>

<details><summary><b>Chain 3 ⚡ "Fastest way to get the top 100 of 5 million?"</b></summary>

**Initial prompt.** "Find the 100 largest of 5M integers, sorted."

**L5 textbook answer.** "`nth_element` is O(n), the best possible, then sort the 100."

**Why L5 breaks.** O(n) is asymptotically optimal, but the constant matters. Listing 4.3: `nth_element` + sort took 28–38
ms; `partial_sort` took 2–4 ms. `partial_sort` keeps a 100-element heap and does one well-predicted comparison per
element. `nth_element` partitions all 5M elements several times.

**L7 principal defense.** "For k ≪ n, a bounded heap (`partial_sort` or `std::priority_queue` of size k), which also
works on a stream. For k comparable to n, `nth_element`. Measure on the real distribution: adversarial or already-sorted
input changes the heap's replacement rate."
</details>

<details><summary><b>Chain 4 🧊 "Your sorted result differs between platforms"</b></summary>

**Initial prompt.** "Sorting prices gives different orders on Linux and macOS builds, and `is_sorted` passes on both.
Explain."

**L5 textbook answer.** "`std::sort` isn't stable, so equal elements can be in any order."

**Why L5 breaks.** Instability explains different orders of *equal* keys. Listing 4.2 shows a stronger effect: with a
NaN, the libraries produce `1 3 nan 2` and `3 nan 1 2`, orders that are not sorted in any meaningful sense. `is_sorted`
says `true` because it uses the same invalid comparator. NaN makes the comparator violate transitivity of
incomparability.

**L7 principal defense.** "Validate floating-point keys at the boundary, or sort with `std::strong_order` (IEEE total
order). Use `stable_sort` where tie order is observable. Never test a sort with the comparator under test."
</details>

<details><summary><b>Chain 5 ⚡ "Why is remove_if not removing?"</b></summary>

**Initial prompt.** "`std::remove_if(v.begin(), v.end(), pred);` but `v.size()` didn't change. Bug in the library?"

**L5 textbook answer.** "You need to call `erase` afterwards."

**Why L5 breaks.** Correct, and the L7 part is *why*: algorithms operate on iterator ranges and cannot change a
container's size. `remove_if` compacts the kept elements to the front (stable, O(n), one move per kept element) and
returns the logical end. The tail elements are valid but unspecified (moved-from). C++20 `std::erase_if` does both
steps. The naive alternative, `erase` in a loop, is O(n²) (Listing 4.3: 57–593 ms for 50k elements vs ~17 ms for 5M).

**L7 principal defense.** "`std::erase_if` (C++20), or the erase-remove idiom before it. For `list`/`forward_list`, the
member `remove_if`, which relinks nodes. For order-insensitive vectors, swap-and-pop is O(1) per removal."
</details>

<details><summary><b>Chain 6 🧊 "Is std::sort stable? When does it matter?"</b></summary>

**Initial prompt.** "Does `std::sort` preserve the order of equal elements?"

**L5 textbook answer.** "No, use `stable_sort` if you need that."

**Why L5 breaks.** It is the right rule. What the L5 answer misses: (1) `stable_sort` has different costs per library
(Listing 4.1: libc++ 37M comparisons on reversed input vs libstdc++ 9M); (2) it allocates a buffer and falls back to
O(n log² n) if allocation fails; (3) instability makes results differ between libraries, which breaks golden-file tests
and distributed consensus on "the same" sort.

**L7 principal defense.** "If tie order is observable (UI lists, deterministic output, replicated state), either use
`stable_sort` or make the comparator total by adding a tiebreak key (an ID). The tiebreak is usually cheaper and makes
the result library-independent."
</details>

<details><summary><b>Chain 7 ⚡ "Mostly-sorted data: what's the fastest sort?"</b></summary>

**Initial prompt.** "Each tick, 1% of a 1M-element sorted array changes. How do you re-sort?"

**L5 textbook answer.** "`std::sort` again; it's O(n log n)."

**Why L5 breaks.** On libstdc++, `std::sort` costs about as much as on random data even for nearly sorted input (25–59M
comparisons in Listing 4.1). libc++'s pdqsort is near-linear on sorted input, but "1% scattered changes" is not the
same pattern. Algorithmically, the changed elements can be extracted, sorted (10k elements) and merged back
(`std::inplace_merge`, O(n)).

**L7 principal defense.** "Extract the changed elements, sort them, merge: O(n + k log k). Or keep the data in a
structure that does not need re-sorting (an order-statistic tree, or a B-tree). And benchmark both libraries, because
the algorithm behind `std::sort` differs."
</details>

<details><summary><b>Chain 8 🔥 "Comparator with side effects"</b></summary>

**Initial prompt.** "Our comparator increments a counter so we can log sort cost. Any problem?"

**L5 textbook answer.** "No, it's just a counter."

**Why L5 breaks.** Counting is harmless (Listing 4.1 does it). Side effects that *affect the result* (caching that
changes keys, reading values another thread modifies, randomness) break strict weak ordering in ways no checker sees.
Parallel sorts (`std::execution::par`) also call the comparator concurrently, so a plain counter becomes a data race.

**L7 principal defense.** "Comparators are pure functions of immutable keys. Instrumentation uses thread-local or atomic
counters. Keys that need computation are precomputed once (decorate-sort-undecorate, or `ranges::sort` with a
projection over cached keys)."
</details>

---

## 6. Invariants checklist

- [ ] Every comparator is a strict weak ordering over immutable data; floating-point keys use `std::strong_order` or
      are NaN-free by construction.
- [ ] Tie order that matters is made explicit (tiebreak key or `stable_sort`).
- [ ] Top-k uses `partial_sort`/bounded heaps for small k.
- [ ] Removal uses `std::erase_if`; no erase-in-loop on vectors.
- [ ] CI runs the suite under libstdc++ debug mode and libc++ debug hardening.
- [ ] Sort performance on structured inputs measured on every shipped library.

## 7. References

- David Musser, "Introspective Sorting and Selection Algorithms" (1997): <https://www.cs.rpi.edu/~musser/gp/introsort.ps>
- Orson Peters, "Pattern-defeating Quicksort" (2021): <https://arxiv.org/abs/2106.05123>
- LWG 713 (worst-case complexity of `std::sort`): <https://cplusplus.github.io/LWG/issue713>
- libc++ sort: <https://github.com/llvm/llvm-project/blob/main/libcxx/include/__algorithm/sort.h>
- libstdc++ `stl_algo.h`: <https://github.com/gcc-mirror/gcc/blob/master/libstdc%2B%2B-v3/include/bits/stl_algo.h>
- P1209R0 (`erase_if`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2018/p1209r0.html>
