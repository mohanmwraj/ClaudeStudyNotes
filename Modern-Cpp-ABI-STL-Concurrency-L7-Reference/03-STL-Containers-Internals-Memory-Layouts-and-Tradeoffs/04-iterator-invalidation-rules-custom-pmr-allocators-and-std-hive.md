# 04 · Iterator invalidation, PMR pool allocators, and `std::hive`

> **Scope.** The rules that decide whether a saved iterator, pointer or reference is still valid after a container
> operation, observed and then caught by the libraries' checking modes. Then the allocator side: what PMR pool
> resources request from their upstream (and how differently the two libraries are tuned). Finally the container
> C++26 adds for "stable addresses + fast iteration + O(1) erase", `std::hive`, built here as a sketch, because
> neither standard library ships it yet.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 3.11 | `invalidation.cpp` | 6 invalidation rules observed; misuse caught by libstdc++ debug mode, `_GLIBCXX_ASSERTIONS`, and libc++ hardening (which traps silently) | run ×4 configurations |
| 3.12 | `pmr_pool.cpp` | 10,000 node allocations become 10–24 upstream calls through `unsynchronized_pool_resource`; default pool options differ 64× | run, both libraries |
| 3.13 | `hive_sketch.cpp` | stable addresses, O(1) erase with slot reuse, skip-field iteration 6–10× faster than `std::list` | run, both libraries (timed) |

**Verification line.** As for files 01–03. The checking-mode runs abort on purpose: their stderr (first lines) and
exit codes are recorded. 0xC0000409 is the UCRT fast-fail used by `abort()`, and 0xC000001D is an illegal instruction
(`ud2`, the trap that libc++ hardening uses).

---

## 1. First principles

### 1.1 The invalidation table

| Container | Insertion | Erasure | Rehash / growth |
|---|---|---|---|
| `vector`, `string` | all if reallocated; else at and after the point | at and after the point | all (reallocation) |
| `deque` | **all iterators**, but pointers/references stay valid for `push_front`/`push_back`; everything for middle insertion | erased + (middle erase) all | map reallocation: iterators only |
| `list`, `forward_list` | none | only the erased elements | — |
| `map`, `set` (+ multi) | none | only the erased elements | — |
| `unordered_*` | **iterators if rehashed**; pointers/references never | only the erased elements | iterators only; nodes do not move |
| `flat_map`, `flat_set` | all (they are vectors) | at and after the point | all |
| open-addressing (absl, boost) | **all, including pointers**, if rehashed | erased (implementation-specific) | everything moves |
| `hive` (C++26) | none | only the erased elements | — |

```cpp
// invalidation.cpp - which operations invalidate iterators / pointers, observed; and the debug modes that catch misuse
#include <cstddef>
#include <deque>
#include <list>
#include <map>
#include <print>
#include <string>
#include <unordered_map>
#include <vector>

int main() {
    // vector: growth reallocates -> every iterator, pointer and reference is invalidated.
    std::vector<int> v{1, 2, 3};
    v.shrink_to_fit();
    const int* before = v.data();
    v.push_back(4);
    std::println("vector push_back past capacity: storage moved = {}", v.data() != before);

    // vector: erase invalidates at and after the erased position (elements shift down).
    std::vector<int> w{10, 20, 30, 40};
    const int* third = &w[2];
    w.erase(w.begin());
    std::println("vector erase(begin): the object at &w[2] now holds {} (was 30)", *third);

    // deque: push_back/push_front keep pointers and references, but invalidate ALL iterators.
    std::deque<int> d{1, 2, 3};
    const int* dp = &d[1];
    for (int i = 0; i < 10'000; ++i) d.push_back(i);
    std::println("deque push_back x10000: pointer to element still valid, *p = {}", *dp);

    // unordered_map: a rehash invalidates iterators, NOT pointers/references to elements (nodes do not move).
    std::unordered_map<int, std::string> um{{1, "one"}};
    const std::string* up = &um.at(1);
    std::size_t buckets = um.bucket_count();
    for (int i = 2; i < 10'000; ++i) um.emplace(i, "x");
    std::println("unordered_map rehash: buckets {} -> {}, pointer to value still valid: \"{}\"", buckets,
                 um.bucket_count(), *up);

    // map / list: only iterators to the ERASED element are invalidated.
    std::map<int, int> m{{1, 1}, {2, 2}, {3, 3}};
    auto it3 = m.find(3);
    m.erase(1);
    m.erase(2);
    std::println("map erase others: iterator to key 3 still valid, ->second = {}", it3->second);
    std::list<int> l{1, 2, 3};
    auto lit = std::next(l.begin());
    l.push_front(0);
    l.erase(l.begin());
    std::println("list insert/erase others: iterator still valid, *it = {}", *lit);

#ifdef USE_AFTER_INVALIDATION
    std::vector<int> bad{1, 2, 3};
    bad.shrink_to_fit();
    auto stale = bad.begin();
    bad.push_back(4);                  // reallocation: 'stale' is now singular
    std::println("dereferencing a stale iterator: {}", *stale);
#endif
#ifdef OUT_OF_BOUNDS
    std::vector<int> small{1, 2, 3};
    std::size_t idx = small.size();
    std::println("small[{}] = {}", idx, small[idx]);  // one past the end: UB, caught by hardened libraries
#endif
}
```

Default build (verified; the only difference between the libraries is the bucket count):

```text
GCC 16.2 + libstdc++:
vector push_back past capacity: storage moved = true
vector erase(begin): the object at &w[2] now holds 40 (was 30)
deque push_back x10000: pointer to element still valid, *p = 2
unordered_map rehash: buckets 13 -> 10273, pointer to value still valid: "one"
map erase others: iterator to key 3 still valid, ->second = 3
list insert/erase others: iterator still valid, *it = 2
```

```text
Clang 21.1 + libc++:
vector push_back past capacity: storage moved = true
vector erase(begin): the object at &w[2] now holds 40 (was 30)
deque push_back x10000: pointer to element still valid, *p = 2
unordered_map rehash: buckets 2 -> 12853, pointer to value still valid: "one"
map erase others: iterator to key 3 still valid, ->second = 3
list insert/erase others: iterator still valid, *it = 2
```

The surprising rows:

* **`vector::erase(begin())`**: the pointer `&w[2]` still points into the buffer, but the *object* there is now
  `40`. Elements shifted down, so the pointer silently refers to a different element. It is not a crash, it is wrong
  data.
* **`unordered_map` rehash** (13 → 10,273 buckets on libstdc++, 2 → 12,853 on libc++): every iterator is invalid,
  and the pointer to the value is still fine, because nodes do not move.
* **`deque`**: references survive `push_back` but iterators do not. A common bug is keeping `d.begin()` across a
  `push_back`.

### 1.2 Catching misuse: three checking modes, three behaviours

Dereferencing an invalidated vector iterator, with **libstdc++ debug mode** (`-D_GLIBCXX_DEBUG`, GCC):

```text
[stderr] safe_iterator.h:352:
[stderr] In function:
[stderr]     constexpr gnu_debug::_Safe_iterator<_Iterator, _Sequence, 
[stderr]     _Category>::reference gnu_debug::_Safe_iterator<_Iterator, _Sequence, 
[stderr]     _Category>::operator*() const [with _Iterator = gnu_cxx::
[stderr]     normal_iterator<int*, std::vector<int, std::allocator<int> > >; 
[stderr]     _Sequence = std::debug::vector<int>; _Category = 
[stderr]     std::forward_iterator_tag; reference = int&]
[stderr] Error: attempt to dereference a singular iterator.
[stderr] Objects involved in the operation:
[exit code] 0xc0000409
```

Reading one past the end with **`_GLIBCXX_ASSERTIONS`** (GCC; cheap checks, ABI-compatible):

```text
[stderr] stl_vector.h:1253: constexpr std::vector< <template-parameter-1-1>, <template-parameter-1-2> >::reference std::vector< <template-parameter-1-1>, <template-parameter-1-2> >::operator[](size_type) [with _Tp = int; _Alloc = std::allocator<int>; reference = int&; size_type = long long unsigned int]: Assertion '__n < this->size()' failed.
[exit code] 0xc0000409
```

The same out-of-bounds read with **libc++ hardening** (`_LIBCPP_HARDENING_MODE_FAST`, Clang):

```text
[exit code] 0xc000001d
```

| Mode | Catches | Cost | ABI |
|---|---|---|---|
| libstdc++ `_GLIBCXX_DEBUG` | invalidated/singular iterators, iterator ranges from different containers, bounds, some ordering violations | large (every iterator tracked) | **changes layouts**: all TUs must agree |
| libstdc++ `_GLIBCXX_ASSERTIONS` | bounds (`operator[]`, `front`, `back`), null checks | small | compatible |
| libc++ hardening `fast` | bounds and similar cheap checks; **traps with no message** (`ud2`) | very small, production-ready | compatible |
| libc++ hardening `extensive` / `debug` | more checks (debug: some iterator validity) | larger | `debug` may change ABI |

libc++'s fast mode traps silently on purpose: it is meant to run in production, where a crash with a core dump is
the desired outcome and message formatting would cost code size. Find the failing check in the debugger at the
`ud2`. Debug mode is the iterator-invalidation tool, and it belongs in test builds.

### 1.3 PMR pool resources (Listing 3.12)

```text
 container --allocate(n, align)--> unsynchronized_pool_resource
                                     |- blocks <= largest_required_pool_block: per-size pools, each a list of chunks
                                     |     chunk = upstream->allocate(many blocks); blocks handed out from it
                                     |- bigger blocks: forwarded to upstream directly
                                     +- deallocate: block goes back to its pool (not to upstream)
 synchronized_pool_resource = the same with a mutex (or per-thread pools);  release()/destructor frees chunks
```

```cpp
// pmr_pool.cpp - a tracking memory_resource shows what pool resources ask their upstream for
#include <cstddef>
#include <list>
#include <map>
#include <memory_resource>
#include <print>

class Tracking : public std::pmr::memory_resource {  // a decorator: count, then forward to the upstream
public:
    explicit Tracking(std::pmr::memory_resource* up) : up_(up) {}
    std::size_t calls = 0, bytes = 0, largest = 0;

private:
    void* do_allocate(std::size_t n, std::size_t align) override {
        ++calls;
        bytes += n;
        if (n > largest) largest = n;
        return up_->allocate(n, align);
    }
    void do_deallocate(void* p, std::size_t n, std::size_t align) override { up_->deallocate(p, n, align); }
    bool do_is_equal(const std::pmr::memory_resource& o) const noexcept override { return this == &o; }
    std::pmr::memory_resource* up_;
};

template <class Fill>
void run(const char* label, Fill fill) {
    Tracking direct(std::pmr::new_delete_resource());
    fill(&direct);
    Tracking upstream(std::pmr::new_delete_resource());
    {
        std::pmr::unsynchronized_pool_resource pool(&upstream);
        fill(&pool);
    }
    std::println("  {:<26} direct: {:>6} calls   via unsynchronized_pool: {:>4} upstream calls, largest {} B", label,
                 direct.calls, upstream.calls, upstream.largest);
}

int main() {
    std::println("10000 small nodes:");
    run("pmr::list<int>", [](std::pmr::memory_resource* r) {
        std::pmr::list<int> l(r);
        for (int i = 0; i < 10'000; ++i) l.push_back(i);
    });
    run("pmr::map<int,int>", [](std::pmr::memory_resource* r) {
        std::pmr::map<int, int> m(r);
        for (int i = 0; i < 10'000; ++i) m.emplace(i, i);
    });
    std::pmr::pool_options opt;
    std::pmr::unsynchronized_pool_resource probe(opt);
    std::println("default pool_options: max_blocks_per_chunk={} largest_required_pool_block={}",
                 probe.options().max_blocks_per_chunk, probe.options().largest_required_pool_block);
}
```

GCC 16.2 + libstdc++ (verified):

```text
10000 small nodes:
  pmr::list<int>             direct:  10000 calls   via unsynchronized_pool:   10 upstream calls, largest 126608 B
  pmr::map<int,int>          direct:  10000 calls   via unsynchronized_pool:   12 upstream calls, largest 246400 B
default pool_options: max_blocks_per_chunk=16384 largest_required_pool_block=4096
```

Clang 21.1 + libc++ (verified):

```text
10000 small nodes:
  pmr::list<int>             direct:  10000 calls   via unsynchronized_pool:   21 upstream calls, largest 68888 B
  pmr::map<int,int>          direct:  10000 calls   via unsynchronized_pool:   24 upstream calls, largest 129304 B
default pool_options: max_blocks_per_chunk=1048576 largest_required_pool_block=1048576
```

* 10,000 node allocations turn into **10–12 upstream calls on libstdc++, 21–24 on libc++**, because chunks grow
  geometrically.
* **Default `pool_options` differ 64×.** libstdc++ pools blocks up to 4 KiB with at most 16,384 blocks per chunk.
  libc++ reports 1 MiB for both. The same "tuned" configuration means different memory behaviour per library. Set
  `pool_options` explicitly.
* The tracking resource is the production pattern for allocator observability: wrap the upstream, count, forward.
  Combined with `null_memory_resource` (file 02 of Folder 02) it enforces budgets in tests.

### 1.4 `std::hive` (P0447): stable addresses with vector-like iteration (Listing 3.13)

```text
 hive<T>:  block 0 [T T x T T T x T ...] skipfield [0 0 1 0 0 0 1 0 ...]   x = erased slot
           block 1 [T T T T ...]                                        blocks never move
           erased-slot list: (b0,2) (b0,6) ...  -> reused by the next insert, O(1)
 erase:     destroy, mark skipped, push to erased list       O(1), no element moves
 iteration: walk blocks in order, skip marked slots           mostly sequential memory
 vs list:   one node per element, scattered;  vs vector: erase moves elements and invalidates pointers
```

```cpp
// hive_sketch.cpp - the idea behind C++26 std::hive (P0447): stable addresses, O(1) erase, slot reuse, skipping
// A teaching sketch (fixed block size, bool skip flags); plf::hive is the full reference implementation.
#include <cstdint>
#include <chrono>
#include <cstddef>
#include <list>
#include <memory>
#include <new>
#include <print>
#include <tuple>
#include <utility>
#include <vector>

template <class T, std::size_t BlockSize = 64>
class MiniHive {
    struct Block {
        alignas(T) unsigned char storage[BlockSize * sizeof(T)];
        bool live[BlockSize] = {};     // skip field: false = erased or never used
        std::size_t used = 0;          // high-water mark inside the block
        T* slot(std::size_t i) { return std::launder(reinterpret_cast<T*>(storage) + i); }
    };
    std::vector<std::unique_ptr<Block>> blocks_;  // blocks never move: element addresses are stable
    std::vector<std::pair<Block*, std::size_t>> free_;  // erased slots, reused before growing
    std::size_t size_ = 0;

public:
    MiniHive() = default;
    MiniHive(const MiniHive&) = delete;
    ~MiniHive() {
        for (auto& b : blocks_)
            for (std::size_t i = 0; i < b->used; ++i)
                if (b->live[i]) std::destroy_at(b->slot(i));
    }
    struct Handle {                        // what a real hive iterator carries: element, block, index
        T* ptr;
        Block* block;
        std::size_t index;
    };
    Handle insert(const T& v) {
        Block* b;
        std::size_t i;
        if (!free_.empty()) {              // O(1) reuse of an erased slot
            std::tie(b, i) = free_.back();
            free_.pop_back();
        } else {
            if (blocks_.empty() || blocks_.back()->used == BlockSize) blocks_.push_back(std::make_unique<Block>());
            b = blocks_.back().get();
            i = b->used++;
        }
        T* p = ::new (static_cast<void*>(reinterpret_cast<T*>(b->storage) + i)) T(v);
        b->live[i] = true;
        ++size_;
        return {p, b, i};
    }
    void erase(Handle h) {                 // O(1): destroy, mark skipped, remember the slot
        std::destroy_at(h.ptr);
        h.block->live[h.index] = false;
        free_.emplace_back(h.block, h.index);
        --size_;
    }
    template <class F>
    void for_each(F f) {                   // iteration skips erased slots; elements stay in block order
        for (auto& b : blocks_)
            for (std::size_t i = 0; i < b->used; ++i)
                if (b->live[i]) f(*b->slot(i));
    }
    std::size_t size() const { return size_; }
    std::size_t blocks() const { return blocks_.size(); }
};

int main() {
    MiniHive<std::int64_t> h;
    std::vector<MiniHive<std::int64_t>::Handle> handles;
    for (std::int64_t i = 0; i < 1000; ++i) handles.push_back(h.insert(i));
    std::int64_t* keep = handles[999].ptr;
    for (std::size_t i = 0; i < 1000; i += 2) h.erase(handles[i]);       // erase every other element
    for (std::int64_t i = 0; i < 500; ++i) h.insert(10'000 + i);                  // refills the erased slots
    std::println("size={} blocks={} (no growth: erased slots were reused); kept pointer still reads {}", h.size(),
                 h.blocks(), *keep);

    // Iteration speed after heavy churn vs std::list (one run).
    constexpr std::int64_t kN = 1'000'000;
    MiniHive<std::int64_t> big;
    std::list<std::int64_t> lst;
    std::vector<MiniHive<std::int64_t>::Handle> hp;
    std::vector<std::list<std::int64_t>::iterator> lp;
    for (std::int64_t i = 0; i < kN; ++i) {
        hp.push_back(big.insert(i));
        lp.push_back(lst.insert(lst.end(), i));
    }
    for (std::size_t i = 0; i < hp.size(); i += 3) {
        big.erase(hp[i]);
        lst.erase(lp[i]);
    }
    auto time = [](auto&& body) {
        auto t0 = std::chrono::steady_clock::now();
        std::int64_t s = body();
        auto t1 = std::chrono::steady_clock::now();
        return std::pair{s, std::chrono::duration<double, std::milli>(t1 - t0).count()};
    };
    auto [sh, th] = time([&] { std::int64_t s = 0; big.for_each([&](std::int64_t v) { s += v; }); return s; });
    auto [sl, tl] = time([&] { std::int64_t s = 0; for (std::int64_t v : lst) s += v; return s; });
    std::println("iterate {} live elements: MiniHive {:.2f} ms, std::list {:.2f} ms (sums equal: {})", big.size(), th, tl,
                 sh == sl);
}
```

GCC 16.2 (one run):

```text
size=1000 blocks=16 (no growth: erased slots were reused); kept pointer still reads 999
iterate 666666 live elements: MiniHive 1.70 ms, std::list 9.25 ms (sums equal: true)
```

Clang 21.1 (one run):

```text
size=1000 blocks=16 (no growth: erased slots were reused); kept pointer still reads 999
iterate 666666 live elements: MiniHive 1.08 ms, std::list 7.77 ms (sums equal: true)
```

* After erasing 500 of 1,000 elements and inserting 500 new ones, the sketch still has 16 blocks: erased slots were
  reused. The pointer to element 999 never moved.
* Iterating 666,666 live elements after erasing every third one: **0.7–1.7 ms vs 6.9–9.3 ms for `std::list`** (ranges over runs),
  because blocks are contiguous and the skip check is a predictable branch.
* What the real `std::hive` adds (plf::hive is the reference implementation, P0447 the specification): growing block
  capacities, a "jump-counting" skipfield that skips runs of erased slots in O(1) instead of one flag at a time,
  iterators that know their block (O(1) erase from an iterator), `reshape` for block limits, and `splice`. Neither
  libstdc++ 16 nor libc++ 21 ships it (`__cpp_lib_hive` undefined, Folder 02).

Use cases: game entities, particle systems, order books and connection tables. Anywhere objects are
created and destroyed constantly, other structures hold pointers to them, and you iterate over all of them often.

---

## 2. Evolution table

| Feature | Standard (paper) | Notes |
|---|---|---|
| invalidation rules per container | C++98, refined in C++11 | `unordered_*` added with their rehash rules |
| allocator model: stateful allocators, `allocator_traits`, propagation traits | C++11 | `propagate_on_container_move_assignment` etc. |
| `<memory_resource>`, pool and monotonic resources | C++17 (P0220) | — |
| `polymorphic_allocator<>` default parameter, `allocate_object`/`new_object` | C++20 (P0339) | — |
| hardened standard library (bounds checks as specified behaviour) | C++26 (P3471) | libc++ hardening modes and libstdc++ assertions predate it |
| `std::hive` | C++26 (P0447R28) | not shipped by GCC 16 or libc++ 21 |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| erase while iterating a vector | `for (auto it = v.begin(); it != v.end(); ++it) if (p(*it)) v.erase(it);` | `std::erase_if(v, p)` (C++20) |
| erase while iterating a map | `m.erase(it); ++it;` | `it = m.erase(it);` |
| objects referenced from elsewhere, frequent churn | `std::vector<T>` + raw pointers | `hive` / plf::hive, or a slot map with generation counters |
| test builds | release flags only | `-D_GLIBCXX_DEBUG` (whole program) or `_GLIBCXX_ASSERTIONS`; libc++ `extensive` hardening |
| production builds | no checks | `_GLIBCXX_ASSERTIONS` / libc++ `fast` hardening: cheap, and they turn silent corruption into a crash |
| node-heavy containers in a request | default allocator | `pmr::unsynchronized_pool_resource` per thread or request, `pool_options` set explicitly |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| wrong element read through a saved pointer after `erase` | elements shifted | debug mode; store indices or use stable containers |
| crash only after a container grows | reallocation or rehash invalidated iterators | `_GLIBCXX_DEBUG` in tests |
| `ud2` / illegal-instruction crash in production with libc++ | a hardening check fired | inspect the faulting frame: it is the check site |
| link or layout errors when enabling debug mode in one library | `_GLIBCXX_DEBUG` changes the ABI | enable it for the whole program |
| pool resource uses far more memory on one platform | different default `pool_options` | set options explicitly; tracking resource in tests |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "Which operations invalidate iterators?"</b></summary>

**Initial prompt.** "Which operations invalidate iterators for vector, deque, list, map and unordered_map?"

**L5 textbook answer.** "Vector insertion invalidates everything; node containers never invalidate."

**Why L5 breaks.** Four errors: vector insertion without reallocation invalidates only at and after the point;
`unordered_map` is node-based but rehash **does** invalidate all iterators (Listing 3.11: 13 → 10,273 buckets), while
pointers survive; `deque::push_back` invalidates all iterators but no references; and erasing from a vector leaves
pointers that now refer to *different* elements.

**L7 principal defense.** "I distinguish iterators from pointers/references, and reallocation from in-place
operations (§1.1 table). I write loops so they never depend on the subtle cases (`erase_if`, `it = erase(it)`),
and I run tests with libstdc++ debug mode, which reported the singular-iterator dereference in Listing 3.11."
</details>

<details><summary><b>Chain 2 ⚡ "Should production builds have bounds checks?"</b></summary>

**Initial prompt.** "Do you enable standard-library assertions in production?"

**L5 textbook answer.** "No, they're slow; only in debug builds."

**Why L5 breaks.** The cheap checks are cheap: `_GLIBCXX_ASSERTIONS` and libc++'s `fast` hardening check bounds with
one compare and a predictable branch, and both keep the ABI. Without them an out-of-bounds read silently returns
garbage or leaks memory contents. With them it stops at the first bad access (Listing 3.11: an assertion message on
libstdc++, a `ud2` trap on libc++). Several large vendors now ship with these checks on, and C++26 standardizes a
hardened library (P3471).

**L7 principal defense.** "Production: `_GLIBCXX_ASSERTIONS` / libc++ `fast` hardening, measured on our benchmarks
(usually ~0–2%). Test builds: `_GLIBCXX_DEBUG` (ABI-changing, whole program) and libc++ `debug`/`extensive`. The
crash handler must symbolize the trap site, because libc++'s fast mode prints nothing."
</details>

<details><summary><b>Chain 3 🧊 "Erase while iterating"</b></summary>

**Initial prompt.** "Write a loop that removes all odd values from a `std::map<int,int>` and from a `std::vector<int>`."

**L5 textbook answer.** `for (auto it = c.begin(); it != c.end(); ++it) if (it->second % 2) c.erase(it);`

**Why L5 breaks.** For the map, `++it` after `erase(it)` increments an invalidated iterator: UB. For the vector it
also skips the element after each erased one and is O(n²). Debug mode reports the first case immediately.

**L7 principal defense.** "C++20 `std::erase_if(c, pred)` for both. Before C++20: `it = m.erase(it)` in the loop for
node containers, and `v.erase(std::remove_if(...), v.end())` for vectors (Folder 04)."
</details>

<details><summary><b>Chain 4 ⚡ "pmr pools: what do the defaults do?"</b></summary>

**Initial prompt.** "We switched node containers to `std::pmr::unsynchronized_pool_resource` with default options.
Memory use on macOS is much higher than on Linux. Why?"

**L5 textbook answer.** "macOS has a different malloc."

**Why L5 breaks.** The pool's defaults are implementation-defined and differ 64× (Listing 3.12): libstdc++ uses
`largest_required_pool_block` 4096 and `max_blocks_per_chunk` 16384, libc++ uses 1 MiB for both. Chunk growth
differs too (10–12 vs 21–24 upstream calls for the same 10,000 nodes).

**L7 principal defense.** "Set `pool_options` explicitly from measured block sizes, wrap the upstream with a tracking
resource in staging, and put a budget on it (`null_memory_resource` as the final upstream in tests)."
</details>

<details><summary><b>Chain 5 🔥 "Design an entity store with stable handles"</b></summary>

**Initial prompt.** "A simulation creates and destroys 100k entities per second. Systems keep references to entities.
Iteration over all entities happens every frame. Design the storage."

**L5 textbook answer.** "`std::vector<Entity>` and store indices."

**Why L5 breaks.** Erasing from the middle of a vector shifts elements, so indices change (swap-and-pop changes the
*moved* element's index), and references become wrong. `std::list` keeps references but iterates 6–10× slower
(Listing 3.13). `unordered_map<id, Entity>` keeps references but iterates through scattered nodes too.

**L7 principal defense.** "Either a `hive` (stable addresses, O(1) erase with slot reuse, near-contiguous iteration:
Listing 3.13), or a slot map: dense array + sparse index + generation counters, so stale handles are detected rather
than silently reused. I'd choose the slot map when handles cross threads or the network (generations make reuse
detectable), and a hive when raw pointers are acceptable."
</details>

<details><summary><b>Chain 6 🧊 "Why does _GLIBCXX_DEBUG crash my mixed build?"</b></summary>

**Initial prompt.** "We enabled `-D_GLIBCXX_DEBUG` in one library to find a bug, and now the program crashes
elsewhere. Why?"

**L5 textbook answer.** "Debug mode found more bugs."

**Why L5 breaks.** Debug mode replaces the containers with checked versions (`std::__debug::vector`) that have a
*different layout* (they track iterators). A `std::vector` created in a non-debug TU and used in a debug TU is an ODR
violation: two layouts for one type. The crashes are self-inflicted.

**L7 principal defense.** "`_GLIBCXX_DEBUG` is all-or-nothing for a program. For partial instrumentation, use
`_GLIBCXX_ASSERTIONS`, which is ABI-compatible. CI runs one full debug-mode build of the test suite."
</details>

<details><summary><b>Chain 7 ⚡ "What does hive give that a free list doesn't?"</b></summary>

**Initial prompt.** "Isn't `std::hive` just a vector with a free list?"

**L5 textbook answer.** "Yes, basically."

**Why L5 breaks.** A vector with a free list has to *grow* by reallocating, which moves every element and breaks all
pointers. Hive grows by adding blocks, so nothing ever moves. A free list alone also gives no fast way to skip
erased slots during iteration. Hive's skipfield (jump-counting in the real design) makes iteration over sparse
blocks O(live elements + blocks). And the erased-slot reuse keeps memory compact under churn (Listing 3.13: no new
blocks after 500 erase/insert pairs).

**L7 principal defense.** "Blocks for stability, a skipfield for iteration, erased-slot reuse for locality, and
iterators that know their block for O(1) erase. Until the standard library ships it, plf::hive is the
production-quality implementation."
</details>

<details><summary><b>Chain 8 🔥 "A pointer into a vector changed value without anyone writing to it"</b></summary>

**Initial prompt.** "Debug this: `const Order* best = &orders[2];` later `orders.erase(orders.begin());`, and `best`
now shows a different order. No crash, no ASan report."

**L5 textbook answer.** "Memory corruption; run ASan."

**Why L5 breaks.** There is no corruption and nothing for ASan to report: the pointer still points into the live
buffer, at the element that shifted into slot 2 (Listing 3.11: 30 became 40). It is a logic bug caused by erase
semantics. Debug mode does not catch raw pointers either, only iterators.

**L7 principal defense.** "Hold stable identities, not addresses into vectors: IDs looked up through a map, indices
with generation counters, or elements in a stable container. If a pointer into a vector is unavoidable, it must not
outlive the next mutation, which a review rule or a span-with-lifetime type has to enforce."
</details>

---

## 6. Invariants checklist

- [ ] No iterator or pointer into a vector/flat container is held across insertion or erasure.
- [ ] No iterator into an unordered container is held across insertion (rehash).
- [ ] Loops that erase use `erase_if` or `it = erase(it)`.
- [ ] Test builds run libstdc++ debug mode (whole program) and libc++ extensive hardening; production builds run the
      cheap assertions/fast hardening.
- [ ] PMR pools have explicit `pool_options` and a tracking/budgeting upstream in tests.
- [ ] Objects referenced from elsewhere with high churn live in a hive or a slot map.

## 7. References

- libstdc++ debug mode: <https://gcc.gnu.org/onlinedocs/libstdc++/manual/debug_mode.html>
- libc++ hardening modes: <https://libcxx.llvm.org/Hardening.html>
- P3471 (standard library hardening): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2025/p3471r4.html>
- P0447R28 (`std::hive`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2024/p0447r28.html>
- plf::hive reference implementation: <https://github.com/mattreecebentley/plf_hive>
- cppreference, iterator invalidation: <https://en.cppreference.com/w/cpp/container#Iterator_invalidation>
