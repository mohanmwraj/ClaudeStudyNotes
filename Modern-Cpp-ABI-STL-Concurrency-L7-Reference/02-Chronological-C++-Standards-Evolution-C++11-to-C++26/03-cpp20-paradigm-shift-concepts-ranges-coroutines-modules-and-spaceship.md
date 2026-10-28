# 03 · C++20: the paradigm shift (concepts, ranges, coroutines, modules, `<=>`)

> **Scope.** C++20 is the largest revision since C++11, and its four headline features each change a different
> layer: concepts change *how templates fail*, ranges change *how algorithms compose*, coroutines change *how
> functions suspend*, and modules change *how code is compiled*. The spaceship operator changes how comparisons are
> written. Each is shown here with the machinery the compiler generates and with the trap that production code
> hits first. Coroutines get their deep dive in Folder 10, ranges in Folder 04, concepts in Folder 06.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 2.9 | `spaceship.cpp` | defaulted `<=>` vs `==` codegen (separate on purpose); partial ordering for NaN; a weak ordering | run + asm |
| 2.10 | `concepts_diag.cpp` | the same misuse diagnosed with and without constraints, measured in lines on both compilers | 3 expected failures × 2 compilers |
| 2.11 | `ranges_lazy.cpp` | laziness counted; `transform \| filter` runs the transform twice; `filter_view::begin()` does work | run, both libraries |
| 2.12 | `coro_gen.cpp` | a generator's frame, promise and handle; Clang elides the heap frame (HALO), GCC allocates 48 bytes | run (both compilers, Clang at `-O2` and `-O0`) |
| 2.13 | `geometry.cppm` + `mod_main.cpp` | named modules on GCC 16 (with `import std;`) and Clang 21; module linkage; BMI configuration mismatch | built and run with both compilers |

**Verification line.** As for files 01–02. The module build is a separate script (`modules.py`): GCC 16.2
`-fmodules` (including `--compile-std-module`), and Clang 21.1 `--precompile` → `.pcm` → object. Both programs run
and print the same result.

---

## 1. First principles

### 1.1 Three-way comparison (Listing 2.9)

```cpp
// spaceship.cpp - C++20 three-way comparison: synthesized operators, ordering categories, and the codegen
#include <cmath>
#include <compare>
#include <print>
#include <string>

struct Version {                       // = default: member-wise lexicographic <=> AND == in declaration order
    int major, minor, patch;
    auto operator<=>(const Version&) const = default;
};
static_assert(Version{1, 2, 3} < Version{1, 10, 0});
static_assert(Version{2, 0, 0} != Version{2, 0, 1});  // != is rewritten to !(a == b)

struct Temp {                          // double members -> std::partial_ordering (NaN is unordered)
    double celsius;
    auto operator<=>(const Temp&) const = default;
};

struct CaseInsensitive {               // a hand-written weak ordering: equivalent is not equal
    std::string s;
    std::weak_ordering operator<=>(const CaseInsensitive& o) const {
        for (std::size_t i = 0; i < s.size() && i < o.s.size(); ++i) {
            int a = std::tolower(static_cast<unsigned char>(s[i])), b = std::tolower(static_cast<unsigned char>(o.s[i]));
            if (a != b) return a < b ? std::weak_ordering::less : std::weak_ordering::greater;
        }
        return s.size() <=> o.s.size();
    }
    bool operator==(const CaseInsensitive& o) const { return (*this <=> o) == 0; }  // not generated from <=>
};

bool less_version(const Version& a, const Version& b) { return a < b; }  // look at the generated code
bool equal_version(const Version& a, const Version& b) { return a == b; }

int main() {
    Temp nan{std::nan("")}, warm{20.0};
    auto r = nan <=> warm;
    std::println("Temp(NaN) <=> Temp(20): unordered = {}, <: {}, >: {}, ==: {}", r == std::partial_ordering::unordered,
                 nan < warm, nan > warm, nan == warm);
    CaseInsensitive a{"Hello"}, b{"hello"};
    std::println("\"Hello\" vs \"hello\" (case-insensitive): equivalent = {}, std::string == = {}", a == b, a.s == b.s);
    std::println("Version{{1,2,3}} < Version{{1,10,0}}: {}", less_version({1, 2, 3}, {1, 10, 0}));
    std::println("ordering categories convert: strong -> weak -> partial (never the reverse)");
}
```

Output (verified, both compilers):

```text
Temp(NaN) <=> Temp(20): unordered = true, <: false, >: false, ==: false
"Hello" vs "hello" (case-insensitive): equivalent = true, std::string == = false
Version{1,2,3} < Version{1,10,0}: true
ordering categories convert: strong -> weak -> partial (never the reverse)
```

Clang `-O3`, x86-64 then AArch64:

```asm
_Z12less_versionRK7VersionS1_:     # less_version(Version const&, Version const&)
	movl	(%rdi), %eax
	cmpl	(%rsi), %eax
	setl	%al
	jne	.LBB0_3
	movl	4(%rdi), %eax
	cmpl	4(%rsi), %eax
	setl	%al
	jne	.LBB0_3
	movl	8(%rdi), %eax
	cmpl	8(%rsi), %eax
	setl	%al
.LBB0_3:
	retq

_Z13equal_versionRK7VersionS1_:    # equal_version(Version const&, Version const&)
	movq	(%rdi), %rax
	xorq	(%rsi), %rax
	movl	8(%rdi), %ecx
	xorl	8(%rsi), %ecx
	orq	%rax, %rcx
	sete	%al
	retq
```

```asm
_Z12less_versionRK7VersionS1_:     // less_version(Version const&, Version const&)
	ldr	w9, [x0]
	ldr	w10, [x1]
	mov	x8, x0
	cmp	w9, w10
	cset	w0, lt
	b.ne	.LBB0_3
	ldr	w9, [x8, #4]
	ldr	w10, [x1, #4]
	cmp	w9, w10
	cset	w0, lt
	b.ne	.LBB0_3
	ldr	w8, [x8, #8]
	ldr	w9, [x1, #8]
	cmp	w8, w9
	cset	w0, lt
.LBB0_3:
	ret

_Z13equal_versionRK7VersionS1_:    // equal_version(Version const&, Version const&)
	ldr	x8, [x0]
	ldr	x9, [x1]
	ldr	w10, [x0, #8]
	ldr	w11, [x1, #8]
	cmp	x8, x9
	ccmp	x10, x11, #0, eq
	cset	w0, eq
	ret
```

* **One defaulted `<=>` gives all six operators.** `<`, `<=`, `>`, `>=` are rewritten to `(a <=> b) < 0`.
  `!=` is rewritten to `!(a == b)`. A defaulted `<=>` also implicitly declares a defaulted `==`.
* **`==` is deliberately *not* derived from `<=>`** (P1185R2). The codegen shows why. `less_version` must compare
  member by member with early exit (three compare/branch pairs). `equal_version` compiles to one 64-bit XOR, one
  32-bit XOR and an OR: no branches, because equality of all members does not need an order. For strings and
  vectors, `==` can also check sizes first, which `<=>` cannot.
* **Ordering categories** are types: `strong_ordering` (substitutable equality), `weak_ordering` (equivalence,
  like case-insensitive strings), `partial_ordering` (some pairs unordered: `NaN`). A struct with a `double` member
  gets `partial_ordering`, and every comparison with a NaN member is false, including `==`. Sorting such structs
  with `std::sort` breaks strict weak ordering (Folder 04).

### 1.2 Concepts: errors at the call site (Listing 2.10)

```cpp
// concepts_diag.cpp - the same mistake (sorting a std::list) diagnosed without and with C++20 constraints
#include <algorithm>
#include <concepts>
#include <iterator>
#include <list>
#include <vector>

// C++17 style: unconstrained; the error surfaces deep inside the library's implementation.
template <class It>
void sort_old(It first, It last) { std::sort(first, last); }

// C++20: the requirement is part of the signature; the error is reported at the call site.
template <std::random_access_iterator It>
    requires std::sortable<It>
void sort_new(It first, It last) { std::sort(first, last); }

// Constrained algorithms (std::ranges::) carry the same constraints in the standard library itself.
int main() {
    std::vector<int> v{3, 1, 2};
    sort_old(v.begin(), v.end());
    sort_new(v.begin(), v.end());
    std::list<int> l{3, 1, 2};
#ifdef SHOW_OLD_ERROR
    sort_old(l.begin(), l.end());
#endif
#ifdef SHOW_NEW_ERROR
    sort_new(l.begin(), l.end());
#endif
#ifdef SHOW_RANGES_ERROR
    std::ranges::sort(l);
#endif
    l.sort();                          // the right tool: list sorts by relinking nodes
    return v.front() == 1 && l.front() == 1 ? 0 : 1;
}
```

The same mistake (sorting a `std::list`) three ways. Each block: total diagnostic lines, `error:` lines, the first
error. GCC 16.2 first, then Clang 21.1:

```text
unconstrained template (sort_old):
36 lines of diagnostics, 1 'error:' lines; first:
  stl_algo.h:1914:50: error: no match for 'operator-' (operand types are 'std::_List_iterator<int>' and 'std::_List_iterator<int>')
150 lines of diagnostics, 4 'error:' lines; first:
  make_heap.h:35:34: error: invalid operands to binary expression ('std::__list_iterator<int, void *>' and 'std::__list_iterator<int, void *>')
```

```text
constrained template (sort_new):
38 lines of diagnostics, 1 'error:' lines; first:
  concepts_diag.cpp:27:13: error: no matching function for call to 'sort_new(std::__cxx11::list<int>::iterator, std::__cxx11::list<int>::iterator)'
16 lines of diagnostics, 1 'error:' lines; first:
  concepts_diag.cpp:27:5: error: no matching function for call to 'sort_new'
```

```text
std::ranges::sort:
51 lines of diagnostics, 1 'error:' lines; first:
  concepts_diag.cpp:30:22: error: no match for call to '(const std::ranges::__sort_fn) (std::__cxx11::list<int>&)'
22 lines of diagnostics, 1 'error:' lines; first:
  concepts_diag.cpp:30:5: error: no matching function for call to object of type 'const __sort'
```

The measured effect is not "shorter errors" in general. **On GCC the constrained version is about the same
length** (38 lines vs 36), because GCC explains which constraint failed and why. What changes is the *location*:
the unconstrained error is inside `stl_algo.h` (`no match for 'operator-'`). The constrained one is at the call
site, naming `random_access_iterator`. **On Clang the volume collapses**: 150 lines with 4 errors in libc++
internals, against 16 lines with 1 error. The constrained `ranges::sort` gets the same benefit for free.

Concepts also change overload resolution (subsumption: the more constrained overload wins) and allow `requires`
expressions for ad-hoc checks. Folder 06 file 02 covers both.

### 1.3 Ranges are lazy, and laziness has a price (Listing 2.11)

```cpp
// ranges_lazy.cpp - C++20 views are lazy: count how often each stage runs (and where it runs twice)
#include <print>
#include <ranges>
#include <vector>

int g_transform = 0, g_filter = 0;

int main() {
    std::vector<int> v(1000);
    for (int i = 0; i < 1000; ++i) v[static_cast<std::size_t>(i)] = i;

    auto square = [](int x) { ++g_transform; return x * x; };
    auto even = [](int x) { ++g_filter; return x % 2 == 0; };

    // filter first, then transform, take 3: work stops as soon as 3 results exist.
    g_transform = g_filter = 0;
    int s1 = 0;
    for (int x : v | std::views::filter(even) | std::views::transform(square) | std::views::take(3)) s1 += x;
    std::println("filter | transform | take(3): sum={} filter calls={} transform calls={}", s1, g_filter, g_transform);

    // transform first, then filter: the filter's predicate dereferences the transform iterator, and the loop
    // body dereferences it AGAIN for every element that passes -> square() runs twice per accepted element.
    g_transform = g_filter = 0;
    int s2 = 0;
    for (int x : v | std::views::transform(square) | std::views::filter(even) | std::views::take(3)) s2 += x;
    std::println("transform | filter | take(3): sum={} filter calls={} transform calls={}", s2, g_filter, g_transform);

    // Nothing runs until iteration: building the pipeline is free.
    g_transform = g_filter = 0;
    auto pipeline = v | std::views::transform(square) | std::views::filter(even);
    std::println("after building the pipeline: transform calls={}", g_transform);
    auto it = pipeline.begin();        // begin() of filter_view must find the first match: work happens here
    std::println("after pipeline.begin(): transform calls={} (filter_view caches begin())", g_transform);
    (void)it;
}
```

Output (verified; libstdc++ and libc++ give the same counts):

```text
filter | transform | take(3): sum=20 filter calls=7 transform calls=3
transform | filter | take(3): sum=20 filter calls=7 transform calls=10
after building the pipeline: transform calls=0
after pipeline.begin(): transform calls=1 (filter_view caches begin())
```

* **Laziness works:** `filter | transform | take(3)` touched 7 elements and ran `square` 3 times out of 1,000
  possible.
* **The overrun:** the filter ran 7 times for 3 results (elements 0–6). After the third match, the loop increments
  the filter iterator *before* comparing with `take`'s end, so the filter searches for a fourth match (5, 6). With
  an expensive predicate or an input iterator (network data), that extra work is real.
* **`transform | filter` calls the transform twice per accepted element:** once inside the predicate (which
  dereferences the transform iterator) and again in the loop body. 10 calls instead of 7. Put `filter` first when
  possible. Otherwise cache the result, for example with C++26 `views::cache_latest` (P3138; ⚠ not in these
  libraries), or by materializing.
* **`filter_view::begin()` is not O(1)** and it **caches**: the first `begin()` scans for the first match, and
  later calls return the cached iterator. That is why `filter_view` cannot be iterated through a `const&`, and why
  modifying the underlying container after the first `begin()` gives stale results. Folder 04 file 02 goes deeper.

### 1.4 Coroutines: what the compiler builds (Listing 2.12)

```cpp
// coro_gen.cpp - a minimal C++20 generator: what the compiler builds (frame, promise, handle) and allocates
#include <coroutine>
#include <cstddef>
#include <cstdlib>
#include <exception>
#include <new>
#include <print>
#include <utility>

std::size_t g_frames = 0, g_frame_bytes = 0;

template <class T>
class Generator {
public:
    struct promise_type {
        T current{};
        // The coroutine frame (locals that live across suspension points + promise + bookkeeping) is
        // allocated through promise_type::operator new when it exists, else through global operator new.
        static void* operator new(std::size_t n) {
            ++g_frames;
            g_frame_bytes = n;
            if (void* p = std::malloc(n)) return p;
            throw std::bad_alloc{};
        }
        static void operator delete(void* p) noexcept { std::free(p); }
        Generator get_return_object() { return Generator{std::coroutine_handle<promise_type>::from_promise(*this)}; }
        std::suspend_always initial_suspend() noexcept { return {}; }  // lazy: nothing runs until the first next()
        std::suspend_always final_suspend() noexcept { return {}; }    // keep the frame so done() can be queried
        std::suspend_always yield_value(T v) noexcept {
            current = std::move(v);
            return {};
        }
        void return_void() noexcept {}
        void unhandled_exception() { std::terminate(); }
    };

    explicit Generator(std::coroutine_handle<promise_type> h) : h_(h) {}
    Generator(Generator&& o) noexcept : h_(std::exchange(o.h_, {})) {}
    Generator(const Generator&) = delete;
    ~Generator() {
        if (h_) h_.destroy();          // destroys the frame: runs destructors of live locals, frees memory
    }
    bool next() {
        h_.resume();                   // runs until the next co_yield or the end
        return !h_.done();
    }
    const T& value() const { return h_.promise().current; }

private:
    std::coroutine_handle<promise_type> h_;
};

Generator<long> fib(int n) {
    long a = 0, b = 1;                 // live across co_yield -> stored in the heap frame, not on the stack
    for (int i = 0; i < n; ++i) {
        co_yield a;
        a = std::exchange(b, a + b);
    }
}

long sum_fib(int n) {
    long s = 0;
    auto g = fib(n);                   // allocates the frame; nothing has executed yet (initial_suspend)
    while (g.next()) s += g.value();
    return s;
}

int main() {
    long s = sum_fib(10);
    std::println("sum of first 10 Fibonacci numbers = {}", s);
    std::println("coroutine frames allocated: {}, frame size: {} bytes", g_frames, g_frame_bytes);
}
```

Clang 21.1 `-O2` (verified):

```text
sum of first 10 Fibonacci numbers = 88
coroutine frames allocated: 0, frame size: 0 bytes
```

Clang 21.1 `-O0`, and GCC 16.2 `-O2` (verified):

```text
sum of first 10 Fibonacci numbers = 88
coroutine frames allocated: 1, frame size: 48 bytes
```

```text
sum of first 10 Fibonacci numbers = 88
coroutine frames allocated: 1, frame size: 48 bytes
```

What `fib(n)` became:

```text
 fib(10)  (ramp function: runs on the caller's stack)
   1. frame = promise_type::operator new(48)     <- locals a, b, i, n + promise + resume/destroy fn ptrs + state
   2. construct promise; get_return_object() -> Generator{handle}
   3. co_await initial_suspend()  (suspend_always: return to caller, body not started)
 g.next() -> handle.resume()      (resume function: jumps to the saved state, runs to the next co_yield)
   co_yield a  ==  co_await promise.yield_value(a)  -> store a in promise, suspend
 ~Generator() -> handle.destroy() (destroy function: destructs live locals for the current state, frees frame)
```

* **The frame is on the heap by default**, because a coroutine can outlive the call that created it. Its size
  (48 bytes here) is chosen by the compiler from the variables live across suspension points.
* **HALO (heap allocation elision)**: Clang at `-O2` saw that the generator's lifetime is strictly nested inside
  `sum_fib`, with resume and destroy visible, and put the frame **on `sum_fib`'s stack**: zero calls to
  `operator new`. At `-O0` it allocates. GCC 16.2 at `-O2` allocates. Coroutine code that is fast on Clang can
  allocate on every call when built with GCC. For hot paths, give the promise a custom `operator new` with a pool
  or an arena. Folder 10 covers symmetric transfer, awaitables and allocator control in depth.

### 1.5 Modules (Listing 2.13)

```cpp
// geometry.cppm - a C++20 named module: an interface unit with exported and non-exported entities
module;                                // global module fragment: #includes go here, before 'export module'
#include <cmath>
export module geometry;

export namespace geo {
struct Point {
    double x, y;
};
double dot(Point a, Point b) { return a.x * b.x + a.y * b.y; }
double norm(Point a) { return std::sqrt(dot(a, a)); }
}  // namespace geo

int internal_helper() { return 42; }   // module linkage: visible inside 'geometry' only, never to importers
```

```cpp
// mod_main.cpp - importing a named module (and, on GCC 16, the standard library as 'import std;')
#ifdef USE_IMPORT_STD
import std;                            // GCC 16: build once with 'g++ -fmodules --compile-std-module'
#else
#include <cstdio>
#endif
import geometry;

int main() {
    geo::Point p{3, 4};
#ifdef USE_IMPORT_STD
    std::println("import std: dot={} norm={}", geo::dot(p, {1, 0}), geo::norm(p));
#else
    std::printf("#include: dot=%g norm=%g\n", geo::dot(p, {1, 0}), geo::norm(p));
#endif
#ifdef SHOW_MODULE_LINKAGE
    return internal_helper();          // not exported: importers cannot name it
#endif
}
```

GCC 16.2 (`-fmodules`; `g++ -fmodules --compile-std-module -c` built `std.gcm` once, then `import std;` works):

```text
import std: dot=3 norm=5
gcm.cache/: C- geometry.gcm std.compat.gcm std.gcm
```

Clang 21.1 (`--precompile geometry.cppm -o geometry.pcm`, then `-fmodule-file=geometry=geometry.pcm`):

```text
#include: dot=3 norm=5
```

Module linkage: `internal_helper` is not exported, so the importer cannot name it (`-DSHOW_MODULE_LINKAGE`):

```text
mod_main.cpp:17:12: error: 'internal_helper' was not declared in this scope
mod_main.cpp:17:12: error: use of undeclared identifier 'internal_helper'
```

A binary module interface (BMI) built with different settings is rejected (Clang; BMI built as C++23, importer
compiled as C++20):

```text
error: C++23 was enabled in precompiled file 'geometry.pcm' but is currently disabled
error: module file geometry.pcm cannot be loaded due to a configuration mismatch with the current compilation [-Wmodule-file-config-mismatch]
```

What modules change, and what they do not:

* **Macros do not leak in or out.** An importer cannot see `#define`s from the module, and the module is not
  affected by the importer's macros. `#include`s needed by the implementation go in the **global module fragment**
  (`module;` … `export module`), where they do not become part of the interface.
* **Compile once, import many.** The BMI (`.gcm` / `.pcm`) is a compiler-specific serialized AST. It is **not
  portable** between compilers, versions, or (as shown) language modes and other configuration options. A build
  system must build BMIs per configuration and in dependency order. This is why module adoption depends on CMake
  3.28+, `ninja` dyndep, and compiler scanning (P1689 dependency files).
* **`import std;` is a C++23 feature (P2465R3).** It worked with GCC 16 here. On the Clang side, the libc++ that
  Zig 0.16 ships is configured with `_LIBCPP_HAS_NO_STD_MODULES`, so it was not available. (Upstream libc++ ships a
  `std.cppm` that build systems compile; ⚠ not tested here.)
* **The ABI does not change.** Exported functions are mangled and linked as usual. Module linkage (names private to
  a module) is new.
* Neither compiler defines `__cpp_modules` in these builds (file 04's probe), so feature-testing modules happens in
  the build system, not in the source.
* Two module-build problems hit me while writing this listing, and they are typical. Zig's driver adds libc++ only
  for file types it recognizes, so a `.cppm` picked up GCC's headers through Clang's MinGW toolchain detection. And
  Zig's compile cache does not track the BMI an importer depends on, so a stale result hid an error until a
  cache-busting define forced recompilation.

---

## 2. Evolution table

| Feature | C++20 (paper) | Status in these toolchains | Later |
|---|---|---|---|
| concepts | P0734R0, library concepts P0898R3 | both: `__cpp_concepts` 202002 | C++26 concept and variable-template template parameters (P2841) |
| ranges | P0896R4 | both (`__cpp_lib_ranges` 202406L) | C++23 `zip`, `enumerate`, `chunk`, `slide`, `to` (libc++ 21 does not define the `zip`/`enumerate` feature macros); C++26 `cache_latest`, `concat` |
| coroutines | P0912R5 | both (`__cpp_impl_coroutine` 201902L) | C++23 `std::generator` (libstdc++ 16 yes, libc++ 21 no); C++26 `std::execution` task (P3552) |
| modules | P1103R3 | GCC 16 (`-fmodules`), Clang 21 (`--precompile`) | C++23 `import std;` (P2465R3) |
| `<=>` | P0515R3, P1185R2 (`==` separate) | both | — |
| `consteval`, `constinit` | P1073R3, P1143R2 | both | C++23 `if consteval` |
| designated initializers | P0329R4 | both | — |
| `std::format` | P0645R10 | both | C++23 `print`, ranges formatting |
| `std::span` | P0122R7 | both | C++26 `span::at` |
| `jthread`, `stop_token`, `atomic::wait`, latch/barrier/semaphore | P0660, P1135 | both | Folder 08 |
| `<chrono>` calendars and time zones | P0355R7 | libstdc++ full (202306L); libc++ 21 partial (`__cpp_lib_chrono` 201611L) | — |
| `std::source_location`, `std::bit_cast`, `std::bit_*` | P1208, P0476, P0553 | both | — |

---

## 3. Production blueprints

### 3.1 Comparisons

| Subtle buggy way | Production-hardened way |
|---|---|
| hand-written `<`, `==`, `!=` … that disagree after a member is added | `auto operator<=>(const T&) const = default;` (keeps all six consistent) |
| a custom `<=>` and no `==` | write `==` too: a user-provided `<=>` does not declare `==` |
| sorting structs containing `double` | define a total order explicitly (`std::strong_order` on the double, or reject NaN at construction) |
| `<=>` on types with expensive comparisons | a separate `==` that checks cheap fields or sizes first |

### 3.2 Ranges in production code

Use views for *readable composition*. Check hot loops in a profile, since the overrun and double-evaluation counts in
§1.3 are real costs. Put `filter` before `transform`. Do not store views over temporaries (Folder 04, dangling).
Materialize (`std::ranges::to<std::vector>()`, C++23) at API boundaries.

### 3.3 Coroutines in production code

Decide the allocation strategy explicitly (promise `operator new` with an arena or pool). Do not rely on HALO, which
Listing 2.12 shows is compiler-dependent. Make the coroutine type own its handle and destroy it in its destructor.
Never let a reference parameter outlive the call that created the coroutine (Folder 10).

### 3.4 Modules adoption

Start with leaf libraries, produce BMIs per build configuration, keep the global module fragment small, and keep a
header fallback for compilers or package managers that are not ready. Treat `import std;` as available only where
the toolchain ships the std module (GCC 16 here, not this libc++ build).

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| `std::sort` crashes or loops on structs with `double` | NaN breaks strict weak ordering (`partial_ordering`) | `static_assert(std::is_same_v<decltype(a <=> b), std::strong_ordering>)`; libc++ hardened mode checks |
| a view prints stale data | `filter_view` cached `begin()` before the container changed | do not mutate under a live view |
| an expensive transform shows twice the expected calls | `transform \| filter` double evaluation | reorder, or cache |
| coroutine code allocates on GCC but not on Clang | HALO is an optimization, not a guarantee | promise `operator new` counters in tests |
| "module file cannot be loaded due to a configuration mismatch" | BMI built with other flags/standard | per-configuration BMIs in the build system |
| names from a module "not declared" | not exported (module linkage) | export them, or move them to an implementation partition |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "Why doesn't <=> give you == for free?"</b></summary>

**Initial prompt.** "If I default `operator<=>`, do I also get `==`? Why is `==` treated separately?"

**L5 textbook answer.** "Yes, the compiler generates all comparisons from `<=>`."

**Why L5 breaks.** A *defaulted* `<=>` implicitly declares a defaulted `==`, but a *user-provided* `<=>` does not,
and `a == b` then fails to compile. The reason is P1185R2: equality can be much cheaper than ordering. Listing 2.9
shows the defaulted `==` compiled to two XORs and an OR with no branches, while `<` needs three dependent compares.
For containers `==` checks the sizes first, which no ordering can do.

**L7 principal defense.** "Default both when member-wise semantics are right. With a custom `<=>`, I write `==`
deliberately, usually cheaper fields first. I check the ordering category: a `double` member turns the result into
`partial_ordering`, and then I either define a total order or forbid NaN."
</details>

<details><summary><b>Chain 2 ⚡ "Do concepts make error messages shorter?"</b></summary>

**Initial prompt.** "Sell me on concepts."

**L5 textbook answer.** "Concepts give much shorter, clearer error messages."

**Why L5 breaks.** Measured, it is compiler-dependent (Listing 2.10). On Clang, 150 lines with 4 errors became 16
lines with 1. On GCC the constrained version is *about the same length* (36 → 38 lines), but the error moves from
`stl_algo.h` to the call site, which is the real win. The larger benefits are elsewhere: overloads selected by
constraints (subsumption) instead of `enable_if` tricks, constraints that document the interface, and checks that
happen before instantiation (no instantiating a body with the wrong type).

**L7 principal defense.** "Concepts are interface contracts for templates: they move errors to the boundary and make
overload sets explicit. I constrain public templates with standard concepts (`std::random_access_iterator`,
`std::sortable`), write named concepts for domain requirements, and keep requires-clauses semantic, not just
syntactic. Folder 06 shows subsumption."
</details>

<details><summary><b>Chain 3 🔥 "Are ranges zero-cost?"</b></summary>

**Initial prompt.** "Is `v | filter(p) | transform(f) | take(n)` as fast as a hand loop?"

**L5 textbook answer.** "Yes, it's all templates and inlining, so it compiles to the same loop."

**Why L5 breaks.** Often the instructions are similar, but the *work* can differ. Listing 2.11 counts it:
`transform | filter` runs the transform twice per accepted element, and `take(3)` over a filter runs the predicate
past the third match. `filter_view::begin()` does a linear search and caches, so it is not const-iterable. These
are semantic costs that no inliner removes.

**L7 principal defense.** "Views are lazy *descriptions*. I order stages to minimize work (filter first), avoid
expensive transforms before filters, and materialize at boundaries. In hot loops I compare against a hand loop in a
profile, not in the assembly alone."
</details>

<details><summary><b>Chain 4 🔥 "Do coroutines allocate?"</b></summary>

**Initial prompt.** "Our team says coroutines are zero-overhead. True?"

**L5 textbook answer.** "Yes, the compiler optimizes away the heap allocation."

**Why L5 breaks.** Sometimes. Listing 2.12: Clang 21 at `-O2` elided the frame allocation (HALO); Clang at `-O0` and
GCC 16 at `-O2` allocated 48 bytes per call. HALO requires the coroutine's lifetime to be provably nested within the
caller's, which fails as soon as the handle escapes (stored in a scheduler, returned, passed to another thread),
which is the normal case for async code.

**L7 principal defense.** "Assume an allocation per coroutine call unless proven otherwise, and control it: a promise
`operator new` that uses a per-thread pool or a caller-provided allocator (`std::allocator_arg_t` convention). Count
allocations in tests on every shipped compiler. For deep chains, symmetric transfer prevents stack growth (Folder
10)."
</details>

<details><summary><b>Chain 5 ⚡ "Should we switch to modules now?"</b></summary>

**Initial prompt.** "Is C++20 modules support ready for our 5M-line code base?"

**L5 textbook answer.** "Yes, modules make builds faster; just replace includes with imports."

**Why L5 breaks.** The language part works (Listing 2.13 ran on both compilers), but the *build* part decides.
BMIs are compiler-, version- and configuration-specific: a BMI built as C++23 is rejected by a C++20 importer, so
every configuration needs its own. The build system must discover dependencies before compiling (P1689 scanning) and
build in order, which serializes previously parallel builds. Macros no longer flow, which breaks code that relied
on them. `import std;` worked with GCC 16 but not with the libc++ that this Zig ships. And Zig's own compile cache
did not track the BMI dependency.

**L7 principal defense.** "Pilot on leaf libraries with a modern build system (CMake 3.28+ with Ninja), measure clean
and incremental build times, and keep header builds working in parallel. Adopt `import std;` where the toolchain
supports it. The win is real for template-heavy headers, but it comes from build-system work, not from replacing
`#include` lines."
</details>

<details><summary><b>Chain 6 🧊 "Why can't I iterate a filter_view through const&?"</b></summary>

**Initial prompt.** "`void print(const auto& r) { for (auto x : r) ... }` fails to compile for a `filter_view`. Why?"

**L5 textbook answer.** "Probably a library bug; remove the const."

**Why L5 breaks.** It is by design. To make `begin()` amortized O(1), `filter_view` caches the first matching
iterator on the first call (Listing 2.11: the transform ran once at `begin()`). Caching mutates the view, so there is
no `begin() const`. The consequence also explains stale results: mutating the underlying range after the first
`begin()` leaves the cache pointing at an old position.

**L7 principal defense.** "Take views by forwarding reference (`auto&& r`) or by value in generic code, and treat
views as single-pass descriptions over stable data. When I need const-iterable results or stability, I materialize."
</details>

<details><summary><b>Chain 7 🧊 "What is a coroutine frame?"</b></summary>

**Initial prompt.** "Where do a coroutine's local variables live?"

**L5 textbook answer.** "On the stack, like any function."

**Why L5 breaks.** Variables that are live across a suspension point live in the **coroutine frame**, normally a heap
allocation made by the ramp function through `promise_type::operator new` (48 bytes for `fib`). The frame also holds
the promise, the resume and destroy function pointers, and the suspension state. The stack holds only the
currently running activation. That is why a coroutine that takes a parameter by reference is dangerous: the
reference is stored in the frame, while the object it refers to is on a caller's stack that is gone by the time the
coroutine resumes.

**L7 principal defense.** "Frame = heap object owned by the handle; its destroy function runs the destructors of live
locals. I pass parameters to coroutines by value (they are copied into the frame), size frames by keeping big objects
out of suspension-spanning scopes, and use a custom `operator new` when the allocation matters."
</details>

<details><summary><b>Chain 8 ⚡ "consteval, constexpr, constinit: which one?"</b></summary>

**Initial prompt.** "Explain the difference between the three."

**L5 textbook answer.** "They all mean compile-time."

**Why L5 breaks.** `constexpr` *permits* compile-time evaluation (file 01). `consteval` *requires* it: an immediate
function cannot run at run time, and calling it with run-time values is an error. `constinit` is about a
**variable's initialization**: it must be constant-initialized (no dynamic initializer, so no static-initialization
order problem), but the variable stays mutable afterwards. Mixing them up leads either to run-time evaluation of
"compile-time" code, or to the static-initialization-order fiasco in code that looked safe.

**L7 principal defense.** "`consteval` for functions that must never run at run time (format-string checking,
reflection helpers); `constexpr` for code usable in both worlds; `constinit` on every namespace-scope or static
variable that must be ready before `main` (loggers, allocators, registries). Folder 06 file 04 shows the
initialization-order bug that `constinit` prevents."
</details>

---

## 6. Invariants checklist

- [ ] Comparisons are defaulted (`<=>` and `==`) or written as a consistent pair; ordering category checked for
      floating-point members.
- [ ] Public templates are constrained with standard or named concepts.
- [ ] Range pipelines order `filter` before `transform`; no views stored over temporaries; `const&` not used for
      views in generic code.
- [ ] Every coroutine type owns and destroys its handle; allocation strategy explicit; parameters by value.
- [ ] Module BMIs built per configuration; header fallback kept during migration.
- [ ] Static-storage variables that must be ready before `main` are `constinit`.

## 7. References

- P0515R3 (`<=>`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2017/p0515r3.pdf>
- P1185R2 (`==` separate from `<=>`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2019/p1185r2.html>
- P0896R4 (ranges): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2018/p0896r4.pdf>
- P1103R3 (modules): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2019/p1103r3.pdf>
- P2465R3 (`import std;`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2022/p2465r3.pdf>
- GCC modules documentation: <https://gcc.gnu.org/onlinedocs/gcc/C_002b_002b-Modules.html>
- Clang standard C++ modules: <https://clang.llvm.org/docs/StandardCPlusPlusModules.html>
- Lewis Baker, "C++ Coroutines: Understanding the promise type": <https://lewissbaker.github.io/2018/09/05/understanding-the-promise-type>
