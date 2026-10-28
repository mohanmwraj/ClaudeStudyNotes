# 02 · Associative trees: `map`/`set` as red-black trees, node overhead, hints, transparent comparators

> **Scope.** `std::map`, `std::set` and their multi variants are red-black trees in both standard libraries: one
> heap node per element, three pointers and a color per node. This file measures what that costs (node sizes,
> allocations), how to insert efficiently (hints, node handles), and how to look up without constructing
> temporary keys (transparent comparators). The flat alternatives (`flat_map`, sorted vectors) and the lookup
> benchmark against them are in file 03.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 3.5 | `node_sizes.cpp` | bytes per node for `list`, `forward_list`, `set`, `map`, `unordered_map`, on both libraries; C++17 node handles | run, recording allocator |
| 3.6 | `transparent.cpp` | 1000 lookups: 1000 heap allocations with `std::less<std::string>`, 0 with `std::less<>`; the same for unordered containers | run, both libraries |
| 3.7 | `hint_insert.cpp` | ascending inserts: a correct `end()` hint saves ~45% on libstdc++ and nothing on libc++ | run, both libraries (3 runs) |

**Verification line.** As for file 01. Node sizes come from a custom allocator that records `sizeof(T)` of the
type each container rebinds it to, which is exactly the node type.

---

## 1. First principles

### 1.1 The red-black tree node

```text
 libstdc++ _Rb_tree_node<int>          (40 bytes measured)     libc++ __tree_node<int>      (32 bytes measured)
 +-------+--------+--------+--------+-------+                   +--------+--------+--------+------+-------+
 | color | parent |  left  | right  | value |                   |  left  | right  | parent |is_blk| value |
 | int 4 | 8      |   8    |   8    |   4   |  + padding         |   8    |   8    |   8    |  1   | 4 @28 |
 +-------+--------+--------+--------+-------+                   +--------+--------+--------+------+-------+
   header node lives inside the map object (sentinel):  begin() = header.left, end() = &header
 invariants: root black; red nodes have black children; every root->leaf path has the same number of black
 nodes  =>  height <= 2 log2(n + 1)  =>  find/insert/erase O(log n) with at most 2 rotations per insert
```

```cpp
// node_sizes.cpp - what a node-based container really allocates per element (recording allocator)
#include <cstddef>
#include <cstdint>
#include <forward_list>
#include <list>
#include <map>
#include <new>
#include <print>
#include <set>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

struct Log {
    std::size_t allocs = 0, bytes = 0, node_bytes = 0;
};
inline Log g_log;

template <class T>
struct Recording {                     // rebinds to the container's internal node type: sizeof(T) is the node
    using value_type = T;
    Recording() = default;
    template <class U>
    Recording(const Recording<U>&) noexcept {}
    T* allocate(std::size_t n) {
        ++g_log.allocs;
        g_log.bytes += n * sizeof(T);
        if (n == 1) g_log.node_bytes = sizeof(T);
        return static_cast<T*>(::operator new(n * sizeof(T)));
    }
    void deallocate(T* p, std::size_t) noexcept { ::operator delete(p); }
    friend bool operator==(const Recording&, const Recording&) { return true; }
};

template <class Container, class Fill>
void measure(const char* name, std::size_t payload, Fill fill) {
    g_log = {};
    {
        Container c;
        fill(c);
    }
    std::println("  {:<38} node {:>3} B for a {:>2}-byte payload; {:>4} allocations, {:>6} bytes total", name,
                 g_log.node_bytes, payload, g_log.allocs, g_log.bytes);
}

int main() {
    std::println("1000 elements of <int> or <int,int>:");
    g_log = {};
    {
        std::vector<int, Recording<int>> v;
        for (int i = 0; i < 1000; ++i) v.push_back(i);
    }
    std::println("  {:<38} no nodes: {:>4} allocations (growth), {:>6} bytes total", "vector<int>", g_log.allocs,
                 g_log.bytes);
    measure<std::list<int, Recording<int>>>("list<int>", 4, [](auto& c) {
        for (int i = 0; i < 1000; ++i) c.push_back(i);
    });
    measure<std::forward_list<int, Recording<int>>>("forward_list<int>", 4, [](auto& c) {
        for (int i = 0; i < 1000; ++i) c.push_front(i);
    });
    measure<std::set<int, std::less<int>, Recording<int>>>("set<int>", 4, [](auto& c) {
        for (int i = 0; i < 1000; ++i) c.insert(i);
    });
    using P = std::pair<const int, int>;
    measure<std::map<int, int, std::less<int>, Recording<P>>>("map<int,int>", 8, [](auto& c) {
        for (int i = 0; i < 1000; ++i) c.emplace(i, i);
    });
    measure<std::unordered_map<int, int, std::hash<int>, std::equal_to<int>, Recording<P>>>(
        "unordered_map<int,int> (+ bucket arrays)", 8, [](auto& c) {
            for (int i = 0; i < 1000; ++i) c.emplace(i, i);
        });

    // C++17 node handles: move a node between maps, or change its key, without allocating.
    std::map<std::string, int> a{{"alpha", 1}}, b;
    auto nh = a.extract("alpha");
    nh.key() = "renamed";             // keys are const in the map, but not in a detached node handle
    b.insert(std::move(nh));
    std::println("node handle: a.size()={} b.contains(\"renamed\")={}", a.size(), b.contains("renamed"));
}
```

GCC 16.2 + libstdc++ (verified):

```text
1000 elements of <int> or <int,int>:
  vector<int>                            no nodes:   11 allocations (growth),   8188 bytes total
  list<int>                              node  24 B for a  4-byte payload; 1000 allocations,  24000 bytes total
  forward_list<int>                      node  16 B for a  4-byte payload; 1000 allocations,  16000 bytes total
  set<int>                               node  40 B for a  4-byte payload; 1000 allocations,  40000 bytes total
  map<int,int>                           node  40 B for a  8-byte payload; 1000 allocations,  40000 bytes total
  unordered_map<int,int> (+ bucket arrays) node  16 B for a  8-byte payload; 1007 allocations,  33080 bytes total
node handle: a.size()=0 b.contains("renamed")=true
```

Clang 21.1 + libc++ (verified):

```text
1000 elements of <int> or <int,int>:
  vector<int>                            no nodes:   11 allocations (growth),   8188 bytes total
  list<int>                              node  24 B for a  4-byte payload; 1000 allocations,  24000 bytes total
  forward_list<int>                      node  16 B for a  4-byte payload; 1000 allocations,  16000 bytes total
  set<int>                               node  32 B for a  4-byte payload; 1000 allocations,  32000 bytes total
  map<int,int>                           node  40 B for a  8-byte payload; 1000 allocations,  40000 bytes total
  unordered_map<int,int> (+ bucket arrays) node  24 B for a  8-byte payload; 1010 allocations,  49384 bytes total
node handle: a.size()=0 b.contains("renamed")=true
```

* **`set<int>`: 40 bytes per 4-byte element on libstdc++, 32 on libc++.** libstdc++ puts a 4-byte color enum
  first, which pushes the value past 32 bytes. libc++ puts its `bool` after the three pointers, and the `int` fits
  in the padding before byte 32. Add the allocator's own per-allocation header (typically 16 bytes with malloc), and
  one 4-byte key costs ~48–56 bytes of memory.
* `map<int,int>` is 40 bytes in both (the 8-byte pair needs the extra word).
* `list<int>` 24 bytes (two pointers + value), `forward_list<int>` 16.
* **`unordered_map<int,int>` nodes are 16 bytes in libstdc++ but 24 in libc++.** libstdc++ does not cache the hash
  code when the hash is "fast" (`std::hash<int>` is the identity), libc++ always stores it. The bucket arrays add
  7 vs 10 more allocations (file 03).
* **C++17 node handles** (`extract`/`insert`) move a node between containers, or change its key, without
  allocating or copying the value. Keys are `const` inside the map, but writable in a detached node handle.

### 1.2 Lookup without temporaries: transparent comparators (Listing 3.6)

```cpp
// transparent.cpp - heterogeneous lookup: std::less<std::string> builds a temporary string per find(), std::less<> does not
#include <version>
#include <cstddef>
#include <cstdlib>
#include <map>
#include <new>
#include <print>
#include <string>
#include <string_view>
#include <unordered_map>

// GCC 16 with -fno-assume-sane-operators-new-delete (needed for honest counts, see vector_growth.cpp) reports a
// false -Wmismatched-new-delete here: it sees free() on memory "from operator new" without seeing that our
// operator new is malloc().
#pragma GCC diagnostic ignored "-Wmismatched-new-delete"
static std::size_t g_allocs = 0;
void* operator new(std::size_t n) {
    ++g_allocs;
    if (void* p = std::malloc(n ? n : 1)) return p;
    throw std::bad_alloc{};
}
void operator delete(void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }

struct StringHash {                    // C++20 heterogeneous lookup for unordered containers needs BOTH
    using is_transparent = void;       // a transparent hash and a transparent key_equal
    std::size_t operator()(std::string_view s) const noexcept { return std::hash<std::string_view>{}(s); }
};

int main() {
    const std::string key(40, 'k');    // longer than SSO in both libraries: a temporary copy must allocate
    std::string_view probe = key;

    std::map<std::string, int> plain{{key, 1}};
    std::map<std::string, int, std::less<>> transparent{{key, 1}};
    std::unordered_map<std::string, int> uplain{{key, 1}};
    std::unordered_map<std::string, int, StringHash, std::equal_to<>> utransparent{{key, 1}};

    int hits = 0;
    g_allocs = 0;
    for (int i = 0; i < 1000; ++i) hits += plain.find(std::string(probe)) != plain.end();  // must build a key
    std::size_t a_plain = g_allocs;
    g_allocs = 0;
    for (int i = 0; i < 1000; ++i) hits += transparent.find(probe) != transparent.end();   // compares in place
    std::size_t a_transp = g_allocs;
    g_allocs = 0;
    for (int i = 0; i < 1000; ++i) hits += uplain.find(std::string(probe)) != uplain.end();
    std::size_t u_plain = g_allocs;
    g_allocs = 0;
    for (int i = 0; i < 1000; ++i) hits += utransparent.find(probe) != utransparent.end();
    std::size_t u_transp = g_allocs;

    std::println("1000 lookups with a 40-char string_view key (hits={}):", hits);
    std::println("  map<string,int>                      : {:>4} heap allocations", a_plain);
    std::println("  map<string,int, less<>>              : {:>4} heap allocations", a_transp);
    std::println("  unordered_map<string,int>            : {:>4} heap allocations", u_plain);
    std::println("  unordered_map<..., StringHash, equal_to<>>: {:>4} heap allocations", u_transp);
#if __cpp_lib_associative_heterogeneous_insertion
    std::println("C++26 heterogeneous try_emplace/operator[] (P2363): available");
#else
    std::println("C++26 heterogeneous try_emplace/operator[] (P2363): not in this standard library");
#endif
}
```

GCC 16.2 + libstdc++, `-std=c++26` (verified):

```text
1000 lookups with a 40-char string_view key (hits=4000):
  map<string,int>                      : 1000 heap allocations
  map<string,int, less<>>              :    0 heap allocations
  unordered_map<string,int>            : 1000 heap allocations
  unordered_map<..., StringHash, equal_to<>>:    0 heap allocations
C++26 heterogeneous try_emplace/operator[] (P2363): available
```

Clang 21.1 + libc++ (verified):

```text
1000 lookups with a 40-char string_view key (hits=4000):
  map<string,int>                      : 1000 heap allocations
  map<string,int, less<>>              :    0 heap allocations
  unordered_map<string,int>            : 1000 heap allocations
  unordered_map<..., StringHash, equal_to<>>:    0 heap allocations
C++26 heterogeneous try_emplace/operator[] (P2363): not in this standard library
```

* `std::map<std::string, int>::find` takes `const key_type&`. Calling it with a `string_view` or `const char*`
  **builds a `std::string` per lookup**: a heap allocation for any key longer than the SSO capacity (40 chars
  here). That is 1000 allocations for 1000 lookups.
* `std::less<>` (C++14, N3657) has `is_transparent`, which enables the template `find(const K&)` overloads:
  0 allocations. For unordered containers (C++20, P0919/P1690) **both** the hash and the equality need
  `is_transparent`.
* C++26 P2363 extends heterogeneous lookup to `try_emplace`, `insert_or_assign`, `operator[]`, `at` and `bucket`.
  libstdc++ 16 has it, libc++ 21 does not.
* The comparator is part of the type, so switching to `std::less<>` changes `std::map`'s type and breaks ABI or
  overloads that name the old type.

### 1.3 Insertion with hints (Listing 3.7)

```cpp
// hint_insert.cpp - red-black tree insertion: plain insert (O(log n) search) vs a correct hint (amortized O(1))
#include <chrono>
#include <cstddef>
#include <map>
#include <print>
#include <vector>

template <class F>
double ms(F f) {
    auto t0 = std::chrono::steady_clock::now();
    f();
    auto t1 = std::chrono::steady_clock::now();
    return std::chrono::duration<double, std::milli>(t1 - t0).count();
}

int main() {
    constexpr int kN = 1'000'000;
    std::size_t sizes = 0;
    double plain = ms([&] {
        std::map<int, int> m;
        for (int i = 0; i < kN; ++i) m.emplace(i, i);              // each insert searches from the root
        sizes += m.size();
    });
    double hinted = ms([&] {
        std::map<int, int> m;
        for (int i = 0; i < kN; ++i) m.emplace_hint(m.end(), i, i);  // "goes just before end()": no search
        sizes += m.size();
    });
    double wrong = ms([&] {
        std::map<int, int> m;
        for (int i = 0; i < kN; ++i) m.emplace_hint(m.begin(), i, i);  // a wrong hint: falls back to a search
        sizes += m.size();
    });
    std::vector<std::pair<int, int>> sorted;
    for (int i = 0; i < kN; ++i) sorted.emplace_back(i, i);
    double range = ms([&] {
        std::map<int, int> m(sorted.begin(), sorted.end());          // range construction from sorted input
        sizes += m.size();
    });
    std::println("1M ascending keys into std::map<int,int> (one run, sizes {}):", sizes);
    std::println("  emplace(k, v)               {:7.1f} ms", plain);
    std::println("  emplace_hint(end(), k, v)   {:7.1f} ms", hinted);
    std::println("  emplace_hint(begin(), k, v) {:7.1f} ms  (wrong hint)", wrong);
    std::println("  map(sorted.begin(), end())  {:7.1f} ms", range);
}
```

GCC 16.2 + libstdc++ (one run; over 3 runs: plain 138–166 ms, `end()` hint 79–82 ms, wrong hint 154–172 ms, range
constructor 157–172 ms):

```text
1M ascending keys into std::map<int,int> (one run, sizes 4000000):
  emplace(k, v)                 136.7 ms
  emplace_hint(end(), k, v)      79.6 ms
  emplace_hint(begin(), k, v)   150.3 ms  (wrong hint)
  map(sorted.begin(), end())    153.4 ms
```

Clang 21.1 + libc++ (one run; over 3 runs: plain 123–151 ms, `end()` hint 128–146 ms, wrong hint 139–147 ms,
range constructor 123–131 ms):

```text
1M ascending keys into std::map<int,int> (one run, sizes 4000000):
  emplace(k, v)                 122.3 ms
  emplace_hint(end(), k, v)     126.0 ms
  emplace_hint(begin(), k, v)   137.3 ms  (wrong hint)
  map(sorted.begin(), end())    123.4 ms
```

* `emplace_hint(pos, ...)` is amortized O(1) when the new element belongs immediately **before** `pos`. For ascending
  input, `end()` is that position. On libstdc++ the correct hint saves ~45%. On libc++ it saves nothing: libc++'s
  plain insertion of ascending keys is already about as fast, because the search always takes the same, perfectly
  predicted path down the right spine.
* A wrong hint is not an error, only a fallback to a full search, slightly slower than no hint.
* libstdc++'s range constructor from sorted input did *not* match the hinted loop here. Do not assume the
  constructor is the fast path. Measure it on your library.
* For bulk loads of sorted data, a `flat_map` (file 03) is built with one sort and no per-element allocation at all.

---

## 2. Evolution table

| Feature | Standard (paper) | Notes |
|---|---|---|
| `emplace`, `emplace_hint`, move-aware insert | C++11 | hint semantics fixed to "insert before hint" (LWG 233) |
| heterogeneous lookup for ordered containers (`is_transparent`) | C++14 (N3657) | `std::less<>` |
| node handles: `extract`, `insert(node_type&&)`, `merge` | C++17 (P0083R3) | move nodes without reallocation |
| `try_emplace`, `insert_or_assign` | C++17 (N4279) | no value construction if the key exists |
| `contains` | C++20 (P0458) | — |
| heterogeneous lookup for unordered containers | C++20 (P0919, P1690) | needs transparent hash *and* equality |
| `erase_if` | C++20 (P1209) | uniform erase |
| ranges construction/insertion (`from_range`) | C++23 (P1206) | — |
| `flat_map`/`flat_set` | C++23 (P0429, P1222) | file 03 |
| heterogeneous `try_emplace`/`operator[]`/`at`/`insert_or_assign` | C++26 (P2363) | libstdc++ 16 yes, libc++ 21 no |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| string-keyed lookup from `string_view` input | `std::map<std::string, V>` + `find(std::string(sv))` | `std::map<std::string, V, std::less<>>` + `find(sv)` |
| rename a key | erase + insert (free + allocate) | `auto nh = m.extract(k); nh.key() = new_k; m.insert(std::move(nh));` |
| insert-if-absent with an expensive value | `if (!m.count(k)) m[k] = make();` (two lookups) | `m.try_emplace(k, args...)` (one lookup, constructs only on insert) |
| bulk load of sorted data | `insert` in a loop | `emplace_hint(end(), ...)` (libstdc++) or build a `flat_map` |
| map of small values, read-mostly | `std::map` (48+ bytes per entry, pointer chasing) | `flat_map` / sorted vector (file 03) |
| `map[k]` in a lookup function | inserts a default value on miss | `find` / `contains`; `at` when a miss is a bug |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| allocation hot spot inside `map::find` | non-transparent comparator + `string_view`/`const char*` keys | heap profiler; switch to `std::less<>` |
| map grows unexpectedly during reads | `operator[]` inserts on miss | code review rule: no `[]` on read paths |
| crash or infinite loop in `std::map` | comparator not a strict weak ordering (`<=`, NaN keys) | libc++ hardened mode / libstdc++ debug mode check orderings |
| memory 10× the payload | node overhead (40 B node + malloc header for a 4-byte key) | measure bytes per element; consider flat containers |
| keys silently not found after mutation | the key was modified through a pointer (`const_cast`) | never mutate keys in place; use node handles |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "How much memory does a std::set<int> use?"</b></summary>

**Initial prompt.** "Estimate the memory for a `std::set<int>` with 10 million elements."

**L5 textbook answer.** "About 40 MB: 10 million × 4 bytes."

**Why L5 breaks.** Each element is a separate node: 40 bytes on libstdc++, 32 on libc++ (Listing 3.5), plus the
allocator's per-allocation overhead (typically 16 bytes for glibc malloc). That is 480–560 MB, 12–14× the payload,
with every node in a different place, so traversal is a sequence of cache misses.

**L7 principal defense.** "Node containers cost ~50 bytes per small element and a pointer chase per level. For 10⁷
ints I'd use a sorted `std::vector<int>` or `flat_set` (40 MB, binary search, cache-friendly) if the set is
read-mostly, a hash set with open addressing (file 03) for point lookups, or a B-tree (absl::btree_set) if I need
ordered updates. I'd quote both libraries' node sizes rather than assume one."
</details>

<details><summary><b>Chain 2 ⚡ "Why does map::find allocate?"</b></summary>

**Initial prompt.** "A profiler shows `operator new` under `std::map<std::string, Config>::find` on our request path.
How can a lookup allocate?"

**L5 textbook answer.** "It can't; `find` doesn't modify the map."

**Why L5 breaks.** The *call* allocates: `find` takes `const std::string&`, and the request handler passes a
`std::string_view` or `const char*`, so a temporary `std::string` is built for every lookup. Listing 3.6: 1000
allocations for 1000 lookups with a 40-character key. Short keys hide it (SSO), long keys expose it.

**L7 principal defense.** "Use transparent comparators: `std::less<>` for ordered maps, a transparent hash + `std::equal_to<>`
for unordered ones (C++20). Verify with an allocation counter in a unit test. The comparator change alters the
map's type, so I'd do it behind a type alias."
</details>

<details><summary><b>Chain 3 🧊 "Rename a key in a std::map without reallocation"</b></summary>

**Initial prompt.** "You need to change the key of an existing entry whose value is expensive to copy. How?"

**L5 textbook answer.** "Copy the value, erase the old key, insert with the new key."

**Why L5 breaks.** That copies (or moves) the value and frees and allocates a node. With C++17 node handles (Listing
3.5), `extract` detaches the node, `nh.key()` is writable, and `insert(std::move(nh))` relinks it: no allocation,
no copy of the value, and pointers to the value stay valid. The L5 approach also breaks code that held references
to the value.

**L7 principal defense.** "`extract` + modify `key()` + `insert`, checking `insert`'s return for an existing key
(the node is then handed back in `node_type`). The same mechanism moves elements between maps with the same
allocator (`merge`)."
</details>

<details><summary><b>Chain 4 ⚡ "Does emplace_hint matter?"</b></summary>

**Initial prompt.** "Should we always use `emplace_hint` when inserting sorted data?"

**L5 textbook answer.** "Yes, it makes insertion O(1) instead of O(log n)."

**Why L5 breaks.** The complexity statement is right, but the benefit depends on the implementation. Listing 3.7:
the `end()` hint saved ~45% on libstdc++ and nothing measurable on libc++, whose plain insert of ascending keys
already runs fast because every search takes the same, perfectly predicted path. A wrong hint costs a bit more than
none. libstdc++'s sorted-range constructor was not faster than the hinted loop.

**L7 principal defense.** "Use correct hints where they're free to compute (ascending loads, insertions next to a
found position), and measure on the libraries we ship. For bulk sorted loads that are read-mostly afterwards, a flat
container is the better answer than any tree trick."
</details>

<details><summary><b>Chain 5 🔥 "What breaks if the comparator is wrong?"</b></summary>

**Initial prompt.** "What happens if `std::map`'s comparator uses `<=`?"

**L5 textbook answer.** "Duplicates are allowed, like a multimap."

**Why L5 breaks.** `<=` is not a strict weak ordering (it is reflexive), so the tree's invariants are violated:
`find` may not find existing keys, `insert` may add duplicates, and some operations become undefined. Debug and
hardened library modes detect some cases. The same happens with keys containing NaN (`partial_ordering`, file
02-03) or comparators that read mutable state.

**L7 principal defense.** "Comparators are strict weak orderings over immutable key data: `<`, `std::less<>`, or a
`<=>`-derived `strong_ordering`. For floating-point keys I use `std::strong_order` or reject NaN. I enable the
library's checked mode in CI (libstdc++ debug mode, libc++ hardening) to catch violations early."
</details>

<details><summary><b>Chain 6 🧊 "Why is libc++'s set node smaller?"</b></summary>

**Initial prompt.** "Same code, `std::set<int>`: 40 bytes per node on Linux/GCC, 32 on macOS/Clang. Why?"

**L5 textbook answer.** "Different pointer sizes."

**Why L5 breaks.** Both are 64-bit. The difference is member order (Listing 3.5). libstdc++'s
`_Rb_tree_node_base` starts with a 4-byte `_Rb_tree_color` enum followed by three pointers, so the base is 32
bytes (with 4 bytes of padding after the color), and the `int` value lands at 32, giving 40 after rounding. libc++'s
node ends with a 1-byte `__is_black_`, so the `int` fits at offset 28 in the same 32 bytes.

**L7 principal defense.** "Layout details like member order decide 20% memory differences in node containers. When
memory matters I measure node size with a recording allocator on each library, and I choose data structures (flat,
B-tree, intrusive) that do not pay per-node overhead in the first place."
</details>

<details><summary><b>Chain 7 ⚡ "try_emplace vs operator[] vs insert"</b></summary>

**Initial prompt.** "What's the most efficient way to insert-if-absent into a map with an expensive value type?"

**L5 textbook answer.** "`if (m.find(k) == m.end()) m[k] = V(args);`"

**Why L5 breaks.** Two lookups, a default-constructed `V` followed by an assignment, and a requirement that `V` be
default-constructible. `insert({k, V(args)})` constructs the value even if the key already exists. `emplace(k,
args...)` may construct the value before discovering the duplicate (implementation-dependent).

**L7 principal defense.** "`m.try_emplace(k, args...)`: one lookup, and the value is constructed only when inserted.
`insert_or_assign` for upsert. With string keys I add a transparent comparator so the key is not materialized
unless the insert happens (C++26 heterogeneous `try_emplace`, available in libstdc++ 16)."
</details>

<details><summary><b>Chain 8 🔥 "map vs unordered_map?"</b></summary>

**Initial prompt.** "When do you pick `std::map` over `std::unordered_map`?"

**L5 textbook answer.** "`map` when you need ordering, `unordered_map` for O(1) lookup."

**Why L5 breaks.** Ordering is one criterion. The others: iterator and reference stability (both node-based, but
`unordered_map` iterators are invalidated by rehash, file 04), worst-case behaviour (a hash table under adversarial
keys degrades to O(n): file 03 measured 38 µs per lookup), memory per element (40 B vs 16–24 B + buckets), and the
fact that *neither* is the fastest option. A sorted vector or `flat_map` beats `map`, and open addressing beats
`unordered_map` (file 03).

**L7 principal defense.** "I choose by operations and constraints. Ordered iteration or range queries: `map`, or
`flat_map` if read-mostly. Point lookups: an open-addressing table (absl `flat_hash_map`), with a seeded hash if keys
can be attacker-controlled. Stable references across inserts: node-based containers. Then I measure with real key
distributions."
</details>

---

## 6. Invariants checklist

- [ ] String-keyed containers use transparent comparators/hashes; lookups never construct key temporaries.
- [ ] No `operator[]` on read paths.
- [ ] Insert-if-absent uses `try_emplace`; upsert uses `insert_or_assign`.
- [ ] Key changes use node handles.
- [ ] Comparators are strict weak orderings over immutable data; checked modes in CI.
- [ ] Memory per element measured for large node containers; flat alternatives considered.

## 7. References

- N3657 (heterogeneous lookup): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2013/n3657.htm>
- P0083R3 (node handles / splicing): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2016/p0083r3.pdf>
- P0919R3 (heterogeneous lookup for unordered containers): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2018/p0919r3.html>
- P2363R5 (extending heterogeneous overloads): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2023/p2363r5.html>
- libstdc++ `stl_tree.h`: <https://github.com/gcc-mirror/gcc/blob/master/libstdc%2B%2B-v3/include/bits/stl_tree.h>
- libc++ `__tree`: <https://github.com/llvm/llvm-project/blob/main/libcxx/include/__tree>
- Cormen, Leiserson, Rivest, Stein, *Introduction to Algorithms*, ch. 13 (red-black trees).
