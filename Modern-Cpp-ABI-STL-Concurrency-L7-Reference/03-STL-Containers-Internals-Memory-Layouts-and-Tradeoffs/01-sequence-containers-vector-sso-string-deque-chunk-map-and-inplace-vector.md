# 01 · Sequence containers: `vector` growth, SSO `string`, `deque`'s block map, `inplace_vector`

> **Scope.** The physical layout of the four sequence containers that matter most, measured on both standard
> libraries: growth policy and reallocation cost, the small-string optimization (15 vs 22 characters),
> `deque`'s block size (512 B vs 4 KiB), and fixed-capacity vectors (C++26 `std::inplace_vector`). Every number
> below is printed by a listing. Where the two libraries disagree, both values are shown.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 3.1 | `vector_growth.cpp` | 2× growth on both libraries; 21 allocations / 7 MB vs 1 / 3 MB with `reserve`; `vector<bool>` proxies; **GCC 16 can make allocation counters lie** | run (GCC with/without `-fno-assume-sane-operators-new-delete`, Clang) |
| 3.2 | `sso_layout.cpp` | `sizeof(std::string)` 32 vs 24; inline capacity 15 vs 22; where `data()` points; move of short strings | run, both libraries |
| 3.3 | `deque_layout.cpp` | elements per block: 128 vs 1024 `int`s; reference stability on `push_*` | run, both libraries |
| 3.4 | `static_vector.cpp` | a fixed-capacity vector with C++20 conditionally trivial special members; `std::inplace_vector` sizes; a constexpr difference between GCC and Clang | run + expected diagnostic |

**Verification line.** Native runs: GCC 16.2 + libstdc++ and Clang 21.1 + libc++ on Windows x86-64 (both Itanium
ABI, 64-bit pointers), `-O2` with the full warning set as errors. Allocation counts use a replaced global
`operator new`, built with GCC's `-fno-assume-sane-operators-new-delete` (§1.1 explains why that flag is needed).

---

## 1. First principles

### 1.1 `std::vector`: three pointers and a growth policy (Listing 3.1)

```text
 std::vector<T>  (24 bytes in both libraries)
 +--------+--------+--------+
 | begin  |  end   | cap_end|          heap: [ T T T T T . . . ]
 +--------+--------+--------+                  ^begin     ^end  ^cap_end
 push_back when end == cap_end:
   1. allocate new_cap = 2 * cap (both libraries here; MSVC's STL uses 1.5x)
   2. move_if_noexcept / relocate the old elements (Folder 01, file 02, §1.5)
   3. destroy the old elements, free the old buffer
   -> every pointer, reference and iterator into the vector is now invalid
```

```cpp
// vector_growth.cpp - std::vector growth policy, reallocation cost, and the vector<bool> proxy
#include <cstddef>
#include <cstdlib>
#include <new>
#include <print>
#include <string>
#include <type_traits>
#include <vector>

static std::size_t g_allocs = 0, g_bytes = 0;
volatile int g_sink = 0;
void* operator new(std::size_t n) {
    ++g_allocs;
    g_bytes += n;
    if (void* p = std::malloc(n ? n : 1)) return p;
    throw std::bad_alloc{};
}
void operator delete(void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }
[[gnu::noinline]] void observe(const int* p, std::size_t n) {
    g_sink = p[n / 2];
}

int main() {
    // 1. Capacity sequence: the growth factor is a library choice (2x here; MSVC's STL uses 1.5x).
    std::vector<int> v;
    std::size_t last = 0;
    std::print("capacity after each reallocation:");
    for (int i = 0; i < 1000; ++i) {
        v.push_back(i);
        if (v.capacity() != last) std::print(" {}", last = v.capacity());
    }
    std::println("");

    // 2. The cost of not reserving: allocations and bytes requested from operator new.
    //    observe() keeps the vector alive. GCC 16 also needs -fno-assume-sane-operators-new-delete for the
    //    count to be real: by default it assumes a replaced operator new has no side effects and may drop calls.
    g_allocs = g_bytes = 0;
    { std::vector<int> a; for (int i = 0; i < 1'000'000; ++i) a.push_back(i); observe(a.data(), a.size()); }
    std::size_t na = g_allocs, ba = g_bytes;
    g_allocs = g_bytes = 0;
    { std::vector<int> b; b.reserve(1'000'000); for (int i = 0; i < 1'000'000; ++i) b.push_back(i); observe(b.data(), b.size()); }
    std::size_t nb = g_allocs, bb = g_bytes;
    std::println("1M push_back: without reserve {} allocations / {} MB requested; with reserve {} / {} MB", na,
                 ba >> 20, nb, bb >> 20);

    // 3. shrink_to_fit is a non-binding request; clear() keeps the capacity.
    std::vector<int> c(1000);
    c.clear();
    std::print("after clear(): size={} capacity={}", c.size(), c.capacity());
    c.shrink_to_fit();
    std::println("; after shrink_to_fit(): capacity={}", c.capacity());

    // 4. vector<bool> is not a container of bool: elements are bits, references are proxy objects.
    std::vector<bool> bits(100);
    auto b0 = bits[0];                 // NOT bool: std::vector<bool>::reference (a proxy holding a pointer + mask)
    static_assert(!std::is_same_v<decltype(b0), bool>);
    bits[0] = true;
    std::println("vector<bool>(100): sizeof(element proxy)={} 'auto b0 = bits[0]' sees later write: {}", sizeof(b0),
                 static_cast<bool>(b0));
    // &bits[0] is not a bool*, so vector<bool> cannot be passed to APIs that want contiguous bool storage.
}
```

GCC 16.2 + libstdc++, built with `-fno-assume-sane-operators-new-delete` (verified):

```text
capacity after each reallocation: 1 2 4 8 16 32 64 128 256 512 1024
1M push_back: without reserve 21 allocations / 7 MB requested; with reserve 1 / 3 MB
after clear(): size=0 capacity=1000; after shrink_to_fit(): capacity=0
vector<bool>(100): sizeof(element proxy)=16 'auto b0 = bits[0]' sees later write: true
```

Clang 21.1 + libc++ (verified):

```text
capacity after each reallocation: 1 2 4 8 16 32 64 128 256 512 1024
1M push_back: without reserve 21 allocations / 7 MB requested; with reserve 1 / 3 MB
after clear(): size=0 capacity=1000; after shrink_to_fit(): capacity=0
vector<bool>(100): sizeof(element proxy)=16 'auto b0 = bits[0]' sees later write: true
```

GCC 16.2 **with default flags**, same source:

```text
capacity after each reallocation: 1 2 4 8 16 32 64 128 256 512 1024
1M push_back: without reserve 0 allocations / 0 MB requested; with reserve 0 / 0 MB
after clear(): size=0 capacity=1000; after shrink_to_fit(): capacity=0
vector<bool>(100): sizeof(element proxy)=16 'auto b0 = bits[0]' sees later write: true
```

* **Growth factor 2** in both libraries (1, 2, 4, …, 1024). The amortized cost of `push_back` is O(1). Without
  `reserve`, 1M `int`s cost 21 allocations and 7 MB of requested memory (1 + 2 + … + 2²⁰ elements × 4 B). With
  `reserve`, one allocation of 4 MB (the `>> 20` shows 3). The classic argument for 1.5× is that freed blocks can be
  reused by later growth (the sum of all previous blocks eventually exceeds the next request). With 2× it never
  does: 1 + 2 + … + 2ⁿ⁻¹ < 2ⁿ.
* **The measurement trap.** With default flags, GCC 16 reports **0** allocations. GCC 16 turns on
  `-fassume-sane-operators-new-delete` by default: it may assume a *replaced* global `operator new`/`delete` has no
  side effects worth keeping, so a counting replacement can see no calls even though the memory was allocated.
  Every allocation-counting listing in Folders 03–05 is therefore built with
  `-fno-assume-sane-operators-new-delete` on GCC. This is an important caveat for anyone who instruments
  allocation in production code.
* `clear()` keeps the capacity, and `shrink_to_fit()` is a non-binding request (both libraries do shrink).
* **`vector<bool>`** is a bitset with a proxy `reference` (16 bytes here: a word pointer + a mask).
  `auto b0 = bits[0]` is a proxy, not a `bool`, so it *sees later writes*, and `&bits[0]` is not a `bool*`. Generic
  code that takes `T&` from `operator[]` breaks for `bool`.

### 1.2 `std::string` and the small-string optimization (Listing 3.2)

```text
 libstdc++ (32 bytes)                         libc++ (24 bytes, "alternate" layout off)
 +---------+---------+-------------------+    short: [size<<1 | 0][ 22 chars + '\0'          ]
 | _M_p    | size    | 16-byte buffer    |    long : [cap | 1     ][ size ][ pointer ]
 +---------+---------+-------------------+    (one bit of the first word says short/long)
   _M_p points INTO the buffer for short strings (self-pointer), or to the heap for long ones
```

```cpp
// sso_layout.cpp - std::string small-string optimization: capacity, where data() lives, when the heap is used
#include <cstddef>
#include <cstdlib>
#include <new>
#include <print>
#include <string>

static std::size_t g_allocs = 0;
void* operator new(std::size_t n) {
    ++g_allocs;
    if (void* p = std::malloc(n ? n : 1)) return p;
    throw std::bad_alloc{};
}
void operator delete(void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }

static bool inside(const std::string& s) {
    const char* d = s.data();
    const char* self = reinterpret_cast<const char*>(&s);
    return d >= self && d < self + sizeof(std::string);
}

int main() {
    std::string empty;
    std::println("sizeof(std::string) = {}, default capacity() = {}", sizeof(std::string), empty.capacity());
    std::size_t first_heap = 0;
    for (std::size_t len = 0; len <= 40; ++len) {
        g_allocs = 0;
        std::string s(len, 'x');
        if (g_allocs && !first_heap) first_heap = len;
        if (len == 0 || len == 15 || len == 16 || len == 22 || len == 23 || len == 40)
            std::println("  len {:>2}: capacity {:>2}  data() inside the object: {:<5}  heap allocations: {}", len,
                         s.capacity(), inside(s), g_allocs);
    }
    std::println("first length that allocates: {}", first_heap);
    // Moving a short string copies its bytes (no pointer to steal); moving a long one steals the heap buffer.
    std::string short_s(10, 's'), long_s(100, 'l');
    const char* long_buf = long_s.data();
    std::string a = std::move(short_s), b = std::move(long_s);
    std::println("move: long buffer stolen = {}; short string moved by copying bytes, source size now {}",
                 b.data() == long_buf, short_s.size());
}
```

GCC 16.2 + libstdc++ (verified):

```text
sizeof(std::string) = 32, default capacity() = 15
  len  0: capacity 15  data() inside the object: true   heap allocations: 0
  len 15: capacity 15  data() inside the object: true   heap allocations: 0
  len 16: capacity 16  data() inside the object: false  heap allocations: 1
  len 22: capacity 22  data() inside the object: false  heap allocations: 1
  len 23: capacity 23  data() inside the object: false  heap allocations: 1
  len 40: capacity 40  data() inside the object: false  heap allocations: 1
first length that allocates: 16
move: long buffer stolen = true; short string moved by copying bytes, source size now 0
```

Clang 21.1 + libc++ (verified):

```text
sizeof(std::string) = 24, default capacity() = 22
  len  0: capacity 22  data() inside the object: true   heap allocations: 0
  len 15: capacity 22  data() inside the object: true   heap allocations: 0
  len 16: capacity 22  data() inside the object: true   heap allocations: 0
  len 22: capacity 22  data() inside the object: true   heap allocations: 0
  len 23: capacity 25  data() inside the object: false  heap allocations: 1
  len 40: capacity 47  data() inside the object: false  heap allocations: 1
first length that allocates: 23
move: long buffer stolen = true; short string moved by copying bytes, source size now 0
```

* **Inline capacity: 15 characters (libstdc++) vs 22 (libc++)** on 64-bit targets, with a smaller object in
  libc++. A 16- to 22-character string (UUIDs without dashes, many identifiers) allocates on Linux/GCC and does not
  on macOS/Clang.
* **libstdc++'s `data()` points into the object** for short strings (`_M_p` is a self-pointer). That makes moving
  a short string a byte copy plus a pointer fix-up, and it makes the type **not trivially relocatable**: Folder 01,
  file 04 showed a `memcpy`'d libstdc++ short string reading the *old* object's buffer.
* **Heap capacities differ**: libstdc++ allocates exactly `len + 1` (capacity 40 for 40 characters); libc++ rounds
  up (capacity 47). Growth by `+=` then follows each library's own doubling rule.
* After a move both libraries leave the source empty. The standard only says "valid but unspecified".

### 1.3 `std::deque`: a map of fixed-size blocks (Listing 3.3)

```text
 deque<int>:   map (array of block pointers, grows at both ends)
               [ . | B0 | B1 | B2 | B3 | . ]
                     |    |    |    +--> [ int x N ]      N = 128 (libstdc++: 512-byte blocks)
                     |    |    +-------> [ int x N ]      N = 1024 (libc++: 4096-byte blocks, min 16 elements)
                     ...
 iterator = {current element, block begin, block end, map position}  -> ++ is a compare + maybe a block hop
```

```cpp
// deque_layout.cpp - std::deque is a map of fixed-size blocks: measure the block size, and what push_* keeps stable
#include <array>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <print>

// Count elements per contiguous run: a run ends where the next element is not adjacent in memory.
template <class T>
std::size_t block_elems() {
    std::deque<T> d(4096);
    std::size_t run = 1, best = 0;
    for (std::size_t i = 1; i < d.size(); ++i) {
        auto prev = reinterpret_cast<std::uintptr_t>(&d[i - 1]), cur = reinterpret_cast<std::uintptr_t>(&d[i]);
        if (cur == prev + sizeof(T)) {
            ++run;
        } else {
            if (run > best) best = run;
            run = 1;
        }
    }
    return run > best ? run : best;
}

int main() {
    std::println("sizeof(std::deque<int>) = {}", sizeof(std::deque<int>));
    std::println("elements per block: int={} double={} array<char,100>={} array<char,1000>={}", block_elems<int>(),
                 block_elems<double>(), block_elems<std::array<char, 100>>(), block_elems<std::array<char, 1000>>());

    // push_back/push_front never move existing elements: pointers and references stay valid,
    // but iterators are invalidated (the block map may be reallocated).
    std::deque<int> d{1, 2, 3};
    int* p = &d[1];
    for (int i = 0; i < 100'000; ++i) {
        d.push_back(i);
        d.push_front(-i);
    }
    std::println("after 200k push_back/push_front, the old element is still at the same address: *p = {}", *p);
}
```

GCC 16.2 + libstdc++ (verified):

```text
sizeof(std::deque<int>) = 80
elements per block: int=128 double=64 array<char,100>=5 array<char,1000>=1
after 200k push_back/push_front, the old element is still at the same address: *p = 2
```

Clang 21.1 + libc++ (verified):

```text
sizeof(std::deque<int>) = 48
elements per block: int=1024 double=512 array<char,100>=40 array<char,1000>=16
after 200k push_back/push_front, the old element is still at the same address: *p = 2
```

* **Block sizes differ by 8×.** libstdc++ uses 512-byte blocks: 128 `int`s, but only **5** 100-byte elements and
  **1** 1000-byte element per block. A `deque` of large objects is then a list of single-element allocations.
  libc++ uses 4096 bytes with a minimum of 16 elements.
* `sizeof(std::deque<int>)` is 80 vs 48: libstdc++ stores two full iterators (start and finish), libc++ stores a
  map, a start offset and a size.
* **`push_back`/`push_front` never move existing elements**, so pointers and references stay valid. Iterators
  are invalidated because the map may be reallocated. That makes `deque` the standard answer for "a growing
  sequence of objects whose addresses are handed out".

### 1.4 Fixed capacity: `inplace_vector` and a hand-written equivalent (Listing 3.4)

```cpp
// static_vector.cpp - a fixed-capacity vector (the idea behind C++26 std::inplace_vector), conditionally trivial
#include <version>
#include <cstddef>
#include <memory>
#include <new>
#include <print>
#include <string>
#include <type_traits>
#include <utility>
#if __cpp_lib_inplace_vector
#include <inplace_vector>
#endif

template <class T, std::size_t N>
class StaticVector {
    union {
        T data_[N];                    // storage for N objects; none is constructed until push_back
    };
    std::size_t size_ = 0;

public:
    constexpr StaticVector() noexcept {}
    // C++20 conditionally trivial special members (P0848): for trivially copyable T the whole container is
    // trivially copyable (memcpy-able, passable in registers if small); otherwise copy element by element.
    StaticVector(const StaticVector&) requires std::is_trivially_copy_constructible_v<T> = default;
    constexpr StaticVector(const StaticVector& o) requires(!std::is_trivially_copy_constructible_v<T>) {
        for (std::size_t i = 0; i < o.size_; ++i) std::construct_at(data_ + i, o.data_[i]);
        size_ = o.size_;
    }
    StaticVector& operator=(const StaticVector&) = delete;
    ~StaticVector() requires std::is_trivially_destructible_v<T> = default;
    constexpr ~StaticVector() requires(!std::is_trivially_destructible_v<T>) { clear(); }

    template <class... A>
    constexpr T* try_emplace_back(A&&... a) {  // no exception, no allocation: nullptr when full
        if (size_ == N) return nullptr;
        T* p = std::construct_at(data_ + size_, std::forward<A>(a)...);
        ++size_;
        return p;
    }
    constexpr void clear() noexcept {
        std::destroy(data_, data_ + size_);
        size_ = 0;
    }
    constexpr std::size_t size() const noexcept { return size_; }
    static constexpr std::size_t capacity() noexcept { return N; }
    constexpr T& operator[](std::size_t i) { return data_[i]; }
};

static_assert(std::is_trivially_copyable_v<StaticVector<int, 8>>);
static_assert(!std::is_trivially_copyable_v<StaticVector<std::string, 8>>);
static_assert(std::is_trivially_destructible_v<StaticVector<int, 8>>);

// Constant evaluation checks every lifetime transition of the non-trivial path (Folder 01, file 03).
constexpr std::size_t selftest() {
    StaticVector<std::string, 3> v;
    v.try_emplace_back("a");
    v.try_emplace_back(30, 'b');
    v.try_emplace_back("c");
    bool full = v.try_emplace_back("d") == nullptr;
    StaticVector<std::string, 3> copy = v;
    return copy.size() + copy[1].size() + (full ? 100 : 0);
}
#if defined(__clang__) && !defined(FORCE_CONSTEXPR_SELFTEST)
// Clang 21 rejects starting the lifetime of an element of a union's array member during constant evaluation
// ("construction of subobject of member 'data_' of union with no active member"). C++26 "trivial unions"
// (P3074) make this valid; GCC 16 accepts it. No feature-test macro distinguishes the two, hence the guard.
#else
static_assert(selftest() == 133);
#endif

int main() {
    StaticVector<int, 8> a;
    for (int i = 0; i < 10; ++i) a.try_emplace_back(i);
    std::println("StaticVector<int,8>: size={} capacity={} sizeof={} trivially copyable={}", a.size(), a.capacity(),
                 sizeof(a), std::is_trivially_copyable_v<decltype(a)>);
    std::println("selftest() at run time = {}", selftest());
#if __cpp_lib_inplace_vector
    std::println("std::inplace_vector<int,8>: sizeof={} trivially copyable={}", sizeof(std::inplace_vector<int, 8>),
                 std::is_trivially_copyable_v<std::inplace_vector<int, 8>>);
    std::println("std::inplace_vector<std::string,8>: trivially copyable={}",
                 std::is_trivially_copyable_v<std::inplace_vector<std::string, 8>>);
#else
    std::println("std::inplace_vector: not in this standard library");
#endif
}
```

GCC 16.2 + libstdc++, `-std=c++26` (verified):

```text
StaticVector<int,8>: size=8 capacity=8 sizeof=40 trivially copyable=true
selftest() at run time = 133
std::inplace_vector<int,8>: sizeof=36 trivially copyable=true
std::inplace_vector<std::string,8>: trivially copyable=false
```

Clang 21.1 + libc++ (verified):

```text
StaticVector<int,8>: size=8 capacity=8 sizeof=40 trivially copyable=true
selftest() at run time = 133
std::inplace_vector: not in this standard library
```

With `-DFORCE_CONSTEXPR_SELFTEST`, which enables the compile-time self-test on Clang too (Clang first):

```text
static_vector.cpp:69:15: error: static assertion expression is not an integral constant expression
construct_at.h:38:10: note: construction of subobject of member 'data_' of union with no active member is not allowed in a constant expression
static_vector.cpp:37:16: note: in call to 'construct_at<std::string, const char (&)[2], std::string *>(&v.union (anonymous union at static_vector.cpp:16:5).data_[0], "a")'
static_vector.cpp:57:5: note: in call to 'v.try_emplace_back<const char (&)[2]>("a")'
static_vector.cpp:69:15: note: in call to 'selftest()'
static_vector.cpp: compiled with NO diagnostic (gcc)
```

* **Conditionally trivial special members** (C++20, P0848) let one class template be trivially copyable for
  `StaticVector<int, 8>` (memcpy-able, register-passable when small) and element-wise for `StaticVector<string, 8>`.
  `std::inplace_vector` in libstdc++ 16 does the same (the `trivially copyable` lines). Its size type is smaller:
  36 bytes vs our 40 for 8 `int`s.
* **A compile-time difference.** Constructing an element of a union's *array* member when no member is active is
  what C++26's "trivial unions" change (P3074) allows in constant evaluation. GCC 16 accepts it; Clang 21 rejects it
  with "construction of subobject of member 'data_' of union with no active member". No feature-test macro separates
  them, so the listing guards the `static_assert` with `__clang__` and runs the same self-test at run time on both.
* `try_emplace_back` returns `nullptr` when full: no exceptions, no allocation. That matches embedded, kernel-bypass
  and HFT code that must not allocate after start-up.

---

## 2. Evolution table

| Container | C++11 | C++17 | C++20 | C++23 | C++26 |
|---|---|---|---|---|---|
| `vector` | `emplace_back`, `data()`, `shrink_to_fit`, move-aware growth | `emplace_back` returns a reference | `constexpr vector` (P1004), `std::erase`/`erase_if` | `append_range`, `insert_range` (P1206) | — |
| `string` | SSO mandated in practice (COW banned by C++11 rules), `std::to_string` | `string_view` interop | `constexpr string`, `starts_with` | `contains`, `resize_and_overwrite` | `string` + `string_view` concatenation |
| `deque` | move support | — | `std::erase` | ranges insertion | — |
| fixed capacity | `std::array` | — | `std::to_array`, `constexpr` | — | `std::inplace_vector` (P0843) |
| triviality | — | — | conditionally trivial special members (P0848) | — | trivial unions (P3074) |

C++11's ban on copy-on-write strings (no invalidation of references by non-mutating operations, `O(1)` `size()`
data race rules) forced libstdc++ to change its `std::string` ABI in GCC 5, the "dual ABI"
(`_GLIBCXX_USE_CXX11_ABI`). It is the largest ABI break in that library's history, and the reason `std::__cxx11::`
appears in GCC's mangled names.

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| building a vector of known size | `push_back` in a loop | `reserve(n)` first; or construct with `n` and assign |
| handing out pointers to elements | `std::vector<T>` and `&v[i]` | `std::deque<T>` (stable on `push_*`), indices instead of pointers, or a `hive` (file 04) |
| short identifiers (16–22 chars) | assume SSO everywhere | measure per library; use a fixed-size `std::array<char, N>` or an interned id |
| `vector<bool>` in generic code | `T& x = v[i]` | `std::vector<char>` / `std::bitset` / a dedicated bitset type |
| no allocation after start-up | `std::vector` with "big enough" `reserve` | `inplace_vector` / `StaticVector` with explicit failure on overflow |
| counting allocations in tests | replaced `operator new` built with default GCC flags | add `-fno-assume-sane-operators-new-delete` (GCC 16), or count in a custom allocator |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| crash or garbage through a saved `&v[i]` | reallocation on growth | ASan heap-use-after-free; libstdc++ debug mode (file 04) |
| memory spikes to 2× during growth | old and new buffers alive at once while relocating | `reserve`; chunked containers |
| latency spike every 2ⁿ insertions | reallocation + relocation of all elements | `reserve`; `deque` for unbounded growth |
| string-heavy code allocates on Linux but not macOS | SSO capacity 15 vs 22 | allocation counters per platform |
| `deque` of big objects slower than `list` | libstdc++'s 512-byte blocks hold one large element each | measure; use `vector<unique_ptr<T>>` or a pool |
| allocation tests pass with "0 allocations" on GCC only | `-fassume-sane-operators-new-delete` dropped the counting calls | build instrumented tests with the flag off |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "Why does vector double its capacity?"</b></summary>

**Initial prompt.** "What is `vector`'s growth factor, and why?"

**L5 textbook answer.** "It doubles, which makes `push_back` amortized O(1)."

**Why L5 breaks.** Doubling gives amortized O(1), but so does any factor > 1. The design choice is between 2
(libstdc++ and libc++, measured in Listing 3.1) and 1.5 (MSVC, folly's `fbvector`). With 2×, a freed old block can
never satisfy the next request, because the sum of all previous blocks is smaller than the new one. With 1.5×,
allocators can eventually reuse the freed space. Peak memory during growth is old + new (3× the data with
doubling). The L5 answer also misses that relocation uses copies when the move constructor can throw (Folder 01).

**L7 principal defense.** "I know my library's factor and I design around it: `reserve` when the size is known,
`shrink_to_fit` after bulk loads if memory matters, nothrow moves so relocation is cheap, and for huge vectors a
chunked structure, because doubling a 4 GB buffer needs 12 GB of peak memory during relocation."
</details>

<details><summary><b>Chain 2 🔥 "How big is std::string, and when does it allocate?"</b></summary>

**Initial prompt.** "What is the small-string optimization? What's the threshold?"

**L5 textbook answer.** "Short strings are stored inside the object, up to about 15 characters."

**Why L5 breaks.** 15 is libstdc++. libc++ holds 22 characters in a 24-byte object (Listing 3.2). The layouts differ
fundamentally. libstdc++ keeps a self-pointer, which makes short strings non-relocatable by memcpy (Folder 01,
file 04). libc++ uses a tagged first word. Performance and correctness assumptions made on one library do not
transfer.

**L7 principal defense.** "SSO thresholds are library-specific (15 / 22 here; MSVC's STL is not measured in this harness). For
allocation-sensitive code I measure on each platform, use `string_view` to avoid copies, and for fixed-size
identifiers use a fixed-capacity type. Relocation of strings is left to the standard containers, which know their
own layout."
</details>

<details><summary><b>Chain 3 ⚡ "deque vs vector?"</b></summary>

**Initial prompt.** "When would you choose `std::deque`?"

**L5 textbook answer.** "When you need fast insertion at both ends."

**Why L5 breaks.** That is one reason. The more common production reason is **reference stability**: `push_back`
and `push_front` never move elements (Listing 3.3), so you can hand out pointers. The costs the L5 answer omits:
iteration is a two-level walk (an iterator is four pointers), random access needs a division, and libstdc++'s
512-byte blocks degrade to one element per block for elements over 256 bytes. The block size differs 8× between
libraries.

**L7 principal defense.** "deque for growing sequences with handed-out references or double-ended queues of small
elements; vector for everything iterated or indexed in hot loops; and for big elements, either a vector of owning
pointers or a pool. I check the library's block size before using deque for large types."
</details>

<details><summary><b>Chain 4 🧊 "Your allocation test says 0 allocations"</b></summary>

**Initial prompt.** "Our test counts allocations with a replaced `operator new` and asserts zero allocations on the
hot path. It passes on GCC 16, fails on Clang. Which one is right?"

**L5 textbook answer.** "GCC is better at optimizing, so it eliminated the allocations."

**Why L5 breaks.** Possibly not. GCC 16 enables `-fassume-sane-operators-new-delete` by default and may assume that
replaced `operator new`/`delete` have no observable side effects. The counter increments can disappear while the
allocations still happen (Listing 3.1: 0 with default flags, 21 with the flag off and at `-O0`). The test is then
measuring nothing. Clang reported the real count.

**L7 principal defense.** "Build instrumented allocation tests with `-fno-assume-sane-operators-new-delete` on
GCC, or count in a custom allocator or `memory_resource`, which no compiler assumption touches. Cross-check with a
second compiler. A zero-allocation guarantee is a test, and a test that can be optimized away is not one."
</details>

<details><summary><b>Chain 5 ⚡ "Why not vector<bool>?"</b></summary>

**Initial prompt.** "What's wrong with `std::vector<bool>`?"

**L5 textbook answer.** "Nothing, it saves memory by using bits."

**Why L5 breaks.** It is not a container in the standard's sense: `operator[]` returns a proxy (16 bytes here), not
`bool&`. `auto x = v[i]` aliases the element (Listing 3.1: the "copy" saw a later write). `&v[i]` is not `bool*`, so
`std::span<bool>` and C APIs don't work. Concurrent writes to *different* elements race, because they share a word.
That last one is a data race in code that looks perfectly element-wise.

**L7 principal defense.** "For a packed bitset, use `std::bitset` (fixed) or a dedicated dynamic bitset with an
explicit API. For a container of flags, use `std::vector<char>` or `std::vector<std::uint8_t>`. And never let
threads write neighbouring bits of a `vector<bool>`."
</details>

<details><summary><b>Chain 6 🧊 "Design a no-allocation container for the hot path"</b></summary>

**Initial prompt.** "Order-book updates must not allocate after start-up. Each update holds up to 16 fills. Design the
container."

**L5 textbook answer.** "`std::vector` with `reserve(16)`."

**Why L5 breaks.** `reserve` allocates once per *object*. Every new update object allocates, which is exactly what
must not happen. Exceeding 16 allocates silently. Moving an update moves the heap pointer, so it is cheap but still
allocated. The right shape is inline storage with an explicit overflow policy.

**L7 principal defense.** "`std::inplace_vector<Fill, 16>` where available (GCC 16 here), otherwise a `StaticVector`
like Listing 3.4: inline union storage, conditionally trivial so `Update` stays trivially copyable when `Fill` is,
`try_emplace_back` returning `nullptr` on overflow, and a metric for overflows. `static_assert` the size of `Update`
against the cache-line budget. Then the object can live in a ring buffer (Folder 09) with no allocation anywhere."
</details>

<details><summary><b>Chain 7 ⚡ "Iterators vs references in deque"</b></summary>

**Initial prompt.** "After `d.push_back(x)` on a `std::deque`, which of my saved iterators, pointers and references
are still valid?"

**L5 textbook answer.** "None of them, like vector."

**Why L5 breaks.** Pointers and references to existing elements stay valid (Listing 3.3: `*p == 2` after 200k pushes
at both ends). All iterators are invalidated, because the block map may be reallocated and an iterator caches its
map position. Insertion or erasure in the *middle* invalidates everything.

**L7 principal defense.** "Save pointers or indices, not iterators, across `push_*`. File 04 has the complete
invalidation table, and libstdc++ debug mode catches use of an invalidated iterator in tests."
</details>

<details><summary><b>Chain 8 🔥 "What did C++11 do to std::string?"</b></summary>

**Initial prompt.** "Why does GCC's mangling show `std::__cxx11::basic_string`?"

**L5 textbook answer.** "It's just a namespace for C++11 features."

**Why L5 breaks.** It is the **dual ABI**. C++11's rules (no reference invalidation by non-mutating calls, data-race
guarantees, `O(1)` `size()`) outlawed libstdc++'s old copy-on-write string. GCC 5 introduced a new SSO string in
the inline namespace `__cxx11`, and kept the old one for binary compatibility. Mixing objects built with different
`_GLIBCXX_USE_CXX11_ABI` settings gives link errors at best, and silent layout mismatches across C interfaces at
worst.

**L7 principal defense.** "Standard-library types are part of the ABI. I don't pass them across boundaries built
with different toolchains or ABI flags, I check the flag in mixed builds, and I treat library layout changes as
breaking changes: the same reason `unique_ptr<T, FinalDeleter>` stays 16 bytes (Folder 01)."
</details>

---

## 6. Invariants checklist

- [ ] `reserve` whenever the final size is known or bounded.
- [ ] No saved pointers or iterators into a `vector` across insertion; `deque` or indices when addresses are handed
      out.
- [ ] No `vector<bool>` in generic code or with concurrent writers.
- [ ] SSO-dependent performance assumptions measured on every shipped library.
- [ ] Hot paths that must not allocate use fixed-capacity containers with an explicit overflow policy.
- [ ] Allocation-counting tests built with `-fno-assume-sane-operators-new-delete` on GCC 16.

## 7. References

- libstdc++ dual ABI: <https://gcc.gnu.org/onlinedocs/libstdc++/manual/using_dual_abi.html>
- folly `FBVector` (growth factor discussion): <https://github.com/facebook/folly/blob/main/folly/docs/FBVector.md>
- P0843R14 (`inplace_vector`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2024/p0843r14.html>
- P0848R3 (conditionally trivial special members): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2019/p0848r3.html>
- P3074 (trivial unions): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2025/p3074r7.html>
- GCC `-fassume-sane-operators-new-delete`: <https://gcc.gnu.org/onlinedocs/gcc/C_002b_002b-Dialect-Options.html>
