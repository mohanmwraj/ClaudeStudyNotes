# 02 · C++20/23 ranges: lazy views, sentinels, borrowed ranges, `dangling`, and codegen

> **Scope.** Ranges add three ideas to the STL: **iterator/sentinel pairs** (the end of a range does not have to be
> an iterator), **views** (lazy, cheap-to-copy descriptions of computations), and **lifetime safety** at the type level
> (`borrowed_range`, `std::ranges::dangling`, `owning_view`). Folder 02, file 03 counted the laziness and the
> double-evaluation trap. This file covers the safety model and the cost model: what a pipeline compiles to,
> compared with the equivalent hand loop.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 4.4 | `ranges_safety.cpp` | `dangling` from algorithms on rvalues (with the compile error); borrowed ranges; a one-pass C-string sentinel; `owning_view` over a temporary | run + expected diagnostics, both libraries |
| 4.5 | `ranges_codegen.cpp` | the hand loop becomes branch-free (x86-64) or vectorized (AArch64); the `filter | transform` pipeline becomes nested search loops, ~6× slower on random data |\| transform` pipeline becomes nested search loops, 25–50% slower | run + asm (x86-64, AArch64) |

**Verification line.** As for file 01, plus Clang 21.1 `-O3` codegen for `x86_64-linux-gnu`/`aarch64-linux-gnu` (libc++).

---

## 1. First principles

### 1.1 The model

```text
 range     = something with begin() and end()   (end may be a SENTINEL of a different type)
 view      = a range that is cheap to copy/move (O(1)) and usually lazy: views::filter, transform, take, ...
 adaptor   = a function object that builds a view:  r | views::filter(p)  ==  views::filter(r, p)
 borrowed_range = a range whose iterators do not depend on the range object's lifetime
                  (span, string_view, ref_view, subrange; views over lvalues)
 algorithms (std::ranges::) take a range or an iterator + sentinel pair, plus an optional projection;
   called on a NON-borrowed rvalue, those that would return an iterator return std::ranges::dangling instead
```

### 1.2 Safety at the type level (Listing 4.4)

```cpp
// ranges_safety.cpp - std::ranges::dangling, borrowed ranges, sentinels, and views over temporaries
#include <algorithm>
#include <cstddef>
#include <print>
#include <ranges>
#include <span>
#include <string>
#include <string_view>
#include <type_traits>
#include <vector>

std::vector<int> make_vec() { return {5, 3, 9, 1}; }

// A sentinel type: "end" is wherever the terminator is, found during the single pass.
struct NullTerm {
    friend bool operator==(const char* p, NullTerm) { return *p == '\0'; }
};

int main() {
    // 1. Algorithms on an rvalue range return std::ranges::dangling instead of an iterator into a dead object.
    auto r1 = std::ranges::max_element(make_vec());
    static_assert(std::is_same_v<decltype(r1), std::ranges::dangling>);
#ifdef SHOW_DANGLING_ERROR
    std::println("{}", *r1);           // ill-formed: dangling has no operator*
#endif
    // A borrowed range (span, string_view, views over lvalues) does not own its elements: iterators survive.
    std::vector<int> owner = make_vec();
    auto r2 = std::ranges::max_element(std::span(owner));
    static_assert(std::is_same_v<decltype(r2), std::span<int>::iterator>);
    std::println("max via span: {}; std::ranges::borrowed_range<std::span<int>> = {}, <std::vector<int>> = {}", *r2,
                 std::ranges::borrowed_range<std::span<int>>, std::ranges::borrowed_range<std::vector<int>>);

    // 2. Sentinels: iterate a C string in ONE pass (no strlen first).
    const char* text = "ranges, sentinels";
    auto commas = std::ranges::count(text, NullTerm{}, ',');
    auto len = std::ranges::distance(text, NullTerm{});
    std::println("count ',' = {}, length = {} (iterator/sentinel pairs may have different types)", commas, len);

    // 3. A view of a temporary container: views::all of an rvalue becomes an owning_view (C++23 P2415 / DR).
    auto odds = make_vec() | std::views::filter([](int x) { return x % 2 == 1; });
    std::print("filter over a temporary vector (owning_view keeps it alive):");
    for (int x : odds) std::print(" {}", x);
    std::println("");

    // 4. Splitting a string_view of a literal is fine; a string_view of a temporary std::string would dangle.
    auto words = std::string_view("alpha beta gamma") | std::views::split(' ');
    std::ptrdiff_t n = 0;
    for (auto w : words) n += std::ranges::distance(w);
    std::println("split string_view literal: {} letters in words", n);
}
```

Output (verified, identical on both libraries):

```text
max via span: 9; std::ranges::borrowed_range<std::span<int>> = true, <std::vector<int>> = false
count ',' = 1, length = 17 (iterator/sentinel pairs may have different types)
filter over a temporary vector (owning_view keeps it alive): 5 3 9 1
split string_view literal: 14 letters in words
```

With `-DSHOW_DANGLING_ERROR` (dereferencing the result of `max_element(make_vec())`), GCC then Clang:

```text
ranges_safety.cpp:24:24: error: no match for 'operator*' (operand type is 'std::ranges::dangling')
ranges_safety.cpp:24:24: error: indirection requires pointer operand ('borrowed_iterator_t<std::vector<int, std::allocator<int>>>' (aka 'std::ranges::dangling') invalid)
```

* **`dangling` turns a use-after-free into a compile error.** `std::ranges::max_element(make_vec())` would return an
  iterator into a vector that dies at the semicolon. The constrained algorithm returns `std::ranges::dangling`, a type
  with no `operator*`. The classic `std::max_element(v.begin(), v.end())` on a temporary has no such protection.
* **Borrowed ranges opt out of that protection, correctly**: `span<int>`'s iterators point into `owner`, which outlives
  the call. `borrowed_range<span<int>>` is true, `borrowed_range<vector<int>>` false. Your own view types opt in with
  `enable_borrowed_range`.
* **Sentinels remove a pass.** `ranges::count(text, NullTerm{}, ',')` counts commas and finds the terminator in the
  same loop. The iterator-pair version needs `strlen` first (two passes over the string). The iterator type
  (`const char*`) and the sentinel type (`NullTerm`) differ, which C++17 algorithms did not allow.
* **Views over temporaries are owning since P2415** (C++23, applied as a DR to C++20 by both libraries):
  `make_vec() | views::filter(...)` moves the vector into an `owning_view` inside the pipeline. The pipeline object owns
  it, so the loop is safe. A `string_view` of a temporary `std::string` is not rescued by anything (Folder 02, file 02).

### 1.3 What a pipeline compiles to (Listing 4.5)

```cpp
// ranges_codegen.cpp - the same computation as a hand loop and as a view pipeline: code and time compared
#include <cstdint>
#include <chrono>
#include <cstddef>
#include <print>
#include <ranges>
#include <span>
#include <vector>

// Sum of squares of the even elements.
std::int64_t hand_loop(std::span<const int> v) {
    std::int64_t s = 0;
    for (int x : v)
        if (x % 2 == 0) s += static_cast<std::int64_t>(x) * x;
    return s;
}
std::int64_t pipeline(std::span<const int> v) {
    std::int64_t s = 0;
    for (std::int64_t y : v | std::views::filter([](int x) { return x % 2 == 0; })
                    | std::views::transform([](int x) { return static_cast<std::int64_t>(x) * x; }))
        s += y;
    return s;
}

template <class F>
double ms(F f) {
    auto t0 = std::chrono::steady_clock::now();
    f();
    auto t1 = std::chrono::steady_clock::now();
    return std::chrono::duration<double, std::milli>(t1 - t0).count();
}

int main() {
    std::vector<int> v(10'000'000);
    // Random parity: with a regular pattern (i % 1000) the pipeline's branch is perfectly predicted and the
    // two versions run at the same speed; with random data only the branch-free hand loop is immune.
    std::uint32_t x = 2463534242u;
    for (auto& e : v) {
        x ^= x << 13; x ^= x >> 17; x ^= x << 5;
        e = static_cast<int>(x % 1000);
    }
    std::int64_t a = 0, b = 0;
    double t1 = ms([&] { for (int r = 0; r < 5; ++r) a += hand_loop(v); });
    double t2 = ms([&] { for (int r = 0; r < 5; ++r) b += pipeline(v); });
    std::println("5 x 10M elements: hand loop {:.1f} ms, filter|transform pipeline {:.1f} ms (equal: {})", t1, t2,
                 a == b);
}
```

Output, one run each:

```text
GCC 16.2 + libstdc++:
5 x 10M elements: hand loop 35.3 ms, filter|transform pipeline 183.1 ms (equal: true)
```

```text
Clang 21.1 + libc++:
5 x 10M elements: hand loop 29.6 ms, filter|transform pipeline 178.1 ms (equal: true)
```

Clang `-O3`, x86-64:

```asm
_Z9hand_loopNSt3__14spanIKiLm18446744073709551615EEE: # hand_loop(std::__1::span<int const, 18446744073709551615ul>)
	testq	%rsi, %rsi
	je	.LBB0_1
	addq	$-1, %rsi
	movabsq	$4611686018427387903, %rax
	andq	%rsi, %rax
	leaq	1(%rax), %rdx
	movl	%edx, %ecx
	andl	$3, %ecx
	cmpq	$3, %rax
	jae	.LBB0_8
	xorl	%eax, %eax
	jmp	.LBB0_5
.LBB0_1:
	xorl	%eax, %eax
	retq
.LBB0_8:
	andq	$-4, %rdx
	xorl	%esi, %esi
	xorl	%eax, %eax
.LBB0_9:
	movslq	(%rdi), %r8
	movq	%r8, %r9
	imulq	%r8, %r9
	testb	$1, %r8b
	cmovneq	%rsi, %r9
	addq	%rax, %r9
	movslq	4(%rdi), %rax
	movq	%rax, %r8
	imulq	%rax, %r8
	testb	$1, %al
	cmovneq	%rsi, %r8
	movslq	8(%rdi), %rax
	movq	%rax, %r10
	imulq	%rax, %r10
	testb	$1, %al
	cmovneq	%rsi, %r10
	addq	%r8, %r10
	addq	%r9, %r10
	movslq	12(%rdi), %r8
	movq	%r8, %rax
	imulq	%r8, %rax
	testb	$1, %r8b
	cmovneq	%rsi, %rax
	addq	%r10, %rax
	addq	$16, %rdi
	addq	$-4, %rdx
	jne	.LBB0_9
.LBB0_5:
	testq	%rcx, %rcx
	je	.LBB0_2
	xorl	%edx, %edx
	xorl	%esi, %esi
.LBB0_7:
	movslq	(%rdi,%rsi,4), %r8
	movq	%r8, %r9
	imulq	%r8, %r9
	testb	$1, %r8b
	cmovneq	%rdx, %r9
	addq	%r9, %rax
	addq	$1, %rsi
	cmpq	%rsi, %rcx
	jne	.LBB0_7
.LBB0_2:
	retq

_Z8pipelineNSt3__14spanIKiLm18446744073709551615EEE: # pipeline(std::__1::span<int const, 18446744073709551615ul>)
	leaq	(%rdi,%rsi,4), %rcx
	testq	%rsi, %rsi
	je	.LBB1_5
	shlq	$2, %rsi
.LBB1_2:
	testb	$1, (%rdi)
	je	.LBB1_5
	addq	$4, %rdi
	addq	$-4, %rsi
	jne	.LBB1_2
	movq	%rcx, %rdi
.LBB1_5:
	xorl	%eax, %eax
	cmpq	%rcx, %rdi
	jne	.LBB1_6
.LBB1_11:
	retq
.LBB1_10:
	movslq	(%rdi), %rsi
	imulq	%rsi, %rsi
	addq	%rsi, %rax
	movq	%rdx, %rdi
	cmpq	%rcx, %rdx
	je	.LBB1_11
.LBB1_6:
	leaq	4(%rdi), %rdx
	cmpq	%rcx, %rdx
	je	.LBB1_10
.LBB1_8:
	testb	$1, (%rdx)
	je	.LBB1_10
	addq	$4, %rdx
	cmpq	%rcx, %rdx
	jne	.LBB1_8
	jmp	.LBB1_10
```

<details><summary>AArch64</summary>

```asm
_Z9hand_loopNSt3__14spanIKiLm18446744073709551615EEE: // hand_loop(std::__1::span<int const, 18446744073709551615ul>)
	cbz	x1, .LBB0_3
	lsl	x9, x1, #2
	sub	x8, x9, #4
	cmp	x8, #28
	b.hs	.LBB0_4
	mov	x8, xzr
	mov	x10, x0
	b	.LBB0_7
.LBB0_3:
	mov	x8, xzr
	mov	x0, x8
	ret
.LBB0_4:
	lsr	x8, x8, #2
	movi	v0.2d, #0000000000000000
	movi	v1.4s, #1
	movi	v2.2d, #0000000000000000
	movi	v3.2d, #0000000000000000
	add	x12, x0, #16
	add	x8, x8, #1
	movi	v4.2d, #0000000000000000
	and	x11, x8, #0x7ffffffffffffff8
	add	x10, x0, x11, lsl #2
	mov	x13, x11
.LBB0_5:
	ldp	q5, q6, [x12, #-16]
	subs	x13, x13, #8
	add	x12, x12, #32
	and	v7.16b, v5.16b, v1.16b
	and	v16.16b, v6.16b, v1.16b
	smull2	v17.2d, v5.4s, v5.4s
	smull	v5.2d, v5.2s, v5.2s
	smull2	v18.2d, v6.4s, v6.4s
	smull	v6.2d, v6.2s, v6.2s
	cmeq	v7.4s, v7.4s, #0
	cmeq	v16.4s, v16.4s, #0
	sshll2	v19.2d, v7.4s, #0
	sshll	v7.2d, v7.2s, #0
	sshll2	v20.2d, v16.4s, #0
	sshll	v16.2d, v16.2s, #0
	and	v17.16b, v19.16b, v17.16b
	and	v5.16b, v7.16b, v5.16b
	and	v7.16b, v20.16b, v18.16b
	and	v6.16b, v16.16b, v6.16b
	add	v2.2d, v17.2d, v2.2d
	add	v0.2d, v5.2d, v0.2d
	add	v4.2d, v7.2d, v4.2d
	add	v3.2d, v6.2d, v3.2d
	b.ne	.LBB0_5
	add	v0.2d, v3.2d, v0.2d
	add	v1.2d, v4.2d, v2.2d
	cmp	x8, x11
	add	v0.2d, v0.2d, v1.2d
	addp	d0, v0.2d
	fmov	x8, d0
	b.eq	.LBB0_9
.LBB0_7:
	add	x9, x0, x9
.LBB0_8:
	ldrsw	x11, [x10], #4
	smull	x12, w11, w11
	tst	w11, #0x1
	csel	x11, x12, xzr, eq
	cmp	x10, x9
	add	x8, x11, x8
	b.ne	.LBB0_8
.LBB0_9:
	mov	x0, x8
	ret

_Z8pipelineNSt3__14spanIKiLm18446744073709551615EEE: // pipeline(std::__1::span<int const, 18446744073709551615ul>)
	cbz	x1, .LBB1_5
	lsl	x9, x1, #2
	mov	x8, x0
	add	x10, x0, x9
.LBB1_2:
	ldrb	w11, [x8]
	tbz	w11, #0, .LBB1_6
	subs	x9, x9, #4
	add	x8, x8, #4
	b.ne	.LBB1_2
	mov	x8, x10
	b	.LBB1_6
.LBB1_5:
	mov	x8, x0
.LBB1_6:
	add	x9, x0, x1, lsl #2
	cmp	x8, x9
	b.eq	.LBB1_13
	mov	x0, xzr
	b	.LBB1_9
.LBB1_8:
	cmp	x8, x9
	b.eq	.LBB1_12
.LBB1_9:
	ldrsw	x10, [x8], #4
	cmp	x8, x9
	smaddl	x0, w10, w10, x0
	b.eq	.LBB1_8
.LBB1_10:
	ldrb	w10, [x8]
	tbz	w10, #0, .LBB1_8
	add	x8, x8, #4
	cmp	x8, x9
	b.ne	.LBB1_10
.LBB1_12:
	ret
.LBB1_13:
	mov	x0, xzr
	ret
```

</details>

* **The hand loop** is unrolled 4× and **branch-free** on x86-64: the `x % 2 == 0` test becomes `testb $1` + `cmovne`
  selecting 0 or the square. The two branches of the source became data flow. On AArch64 Clang goes further and
  **vectorizes** it (NEON `smull`/`cmeq`/`and`, 8 elements per iteration).
* **The pipeline** keeps the structure of `filter_view::iterator::operator++` on both targets: an inner loop "find the
  next element that satisfies the predicate" (`testb $1, (%rdx); je ...` / `tbz`) inside the outer loop. That is a
  data-dependent branch per element, no unrolling and no vectorization.
* **Measured on random data: ~6× slower** (178–203 ms vs 30–36 ms for 5 × 10M elements, over 3 runs). The data matters:
  my first version used `i % 1000`, which alternates even/odd, so the pipeline's branch was perfectly predicted and both
  versions ran at the same speed. The branch-free loop is the only one immune to the data pattern. (That first version
  also accumulated into `long`, 32-bit on Windows, and overflowed. The listing now uses `std::int64_t`.)
* The semantics are identical, and neither is wrong. The pipeline hands the optimizer a *control-flow* shape (search,
  then yield) that it does not turn back into a select. The effect is largest for cheap predicates over contiguous
  data. For expensive per-element work (I/O, hashing) the difference vanishes.
* `std::views::transform` alone, or `ranges::fold_left` without a filter, usually compiles to the same loop as
  hand-written code. Filters, joins and splits are where the structure differs.

---

## 2. Evolution table

| Feature | Standard (paper) | Status here |
|---|---|---|
| ranges, views, constrained algorithms, projections, sentinels | C++20 (P0896R4) | both |
| `views::split` redesign, `lazy_split` | C++20 DR (P2210) | both |
| `owning_view`, `views::all` of rvalues | C++20 DR (P2415R2) | both |
| `ranges::to<Container>()` | C++23 (P1206) | both |
| `views::zip`, `zip_transform`, `adjacent`, `enumerate`, `chunk`, `slide`, `chunk_by`, `stride`, `join_with`, `cartesian_product`, `repeat`, `as_rvalue`, `as_const` | C++23 (P2321, P2164, P2442, …) | libstdc++ 16 all; libc++ 21 most, but does not define the `zip`/`enumerate` macros |
| `ranges::fold_left`, `contains`, `starts_with`, `find_last` | C++23 | both |
| `std::generator` | C++23 (P2502) | libstdc++ 16 |
| `views::concat`, `views::cache_latest`, `views::to_input` | C++26 (P2542, P3138, P3137) | ⚠ not checked |
| `std::optional` as a range | C++26 (P3168) | libstdc++ 16 |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| returning a view from a function | `return std::views::filter(local_vec, p);` (dangles: `ref_view` of a local) | return the container, or `std::move(local) \| views::filter(p)` (owning) |
| view stored as a member | a view over a member that may be reassigned | store the data, build the view on demand |
| hot numeric loop | a `filter \| transform` pipeline | a hand loop (or `transform` only), checked in the profile |
| C strings | `strlen` + iterator loop | a sentinel (`NullTerm`) or `std::string_view` once |
| generic code taking views | `const auto& r` | `auto&& r` (some views are not const-iterable, Folder 02) |
| materializing | a manual `push_back` loop | `std::ranges::to<std::vector>()` (C++23) |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| "no match for operator*" on a ranges algorithm result | `dangling`: the algorithm was called on an rvalue container | intended: keep the container alive, or use the value immediately |
| crash iterating a returned view | `ref_view` over a destroyed local | return owning views / containers |
| a view prints stale data | `filter_view`/`drop_view` cached `begin()` | do not mutate under live views |
| pipeline slower than the old loop | control-flow shape of `filter` | profile; hand loop for cheap predicates |
| compile errors only with `const` | non-const-iterable views | forwarding references |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "What is std::ranges::dangling?"</b></summary>

**Initial prompt.** "Why does `auto it = std::ranges::find(get_vector(), 42);` not give me an iterator?"

**L5 textbook answer.** "Ranges algorithms return different types, you need to use `.begin()`."

**Why L5 breaks.** It returns `std::ranges::dangling` on purpose. `get_vector()` is a non-borrowed rvalue that dies at
the end of the statement, so any iterator into it would dangle. The type has no operations, so dereferencing it is a
compile error (Listing 4.4). The same call with `std::find(v.begin(), v.end())` on a temporary compiles and is a
use-after-free.

**L7 principal defense.** "The library encodes lifetime in types: borrowed ranges (span, string_view, subrange, views
of lvalues) return real iterators, owning rvalues return `dangling`. I keep the container in a named variable when I
need the iterator, and mark my own non-owning views with `enable_borrowed_range`."
</details>

<details><summary><b>Chain 2 ⚡ "Are views zero-cost?"</b></summary>

**Initial prompt.** "Is a ranges pipeline as fast as the loop it replaces?"

**L5 textbook answer.** "Yes, views are templates, so everything inlines."

**Why L5 breaks.** Inlining happens. Equivalence does not. Listing 4.5: the hand loop became a 4×-unrolled branchless
loop with `cmov` on x86-64 (and a NEON-vectorized loop on AArch64), while the `filter | transform` pipeline kept
filter's "search for the next match" control flow, an inner loop with a data-dependent branch. On random data it
measured ~6× slower. On regular data (even/odd alternating) both ran at the same speed, which is exactly why
micro-benchmarks on synthetic data mislead. Folder 02 counted another cost: `transform | filter` evaluates the
transform twice per accepted element.

**L7 principal defense.** "Views are excellent for clarity and for expensive per-element work. For cheap predicates in
hot loops I write the loop, or restructure (transform first, then a branchless reduction). I judge by profile and
assembly, not by the claim that templates are free."
</details>

<details><summary><b>Chain 3 🧊 "Why sentinels?"</b></summary>

**Initial prompt.** "Why did C++20 allow `end()` to have a different type from `begin()`?"

**L5 textbook answer.** "For infinite ranges."

**Why L5 breaks.** Infinite ranges (`unreachable_sentinel_t`) are one case. The general benefit is that the end
condition can be a *predicate on the iterator* instead of a position you must compute first. A C string's end is
"`*p == '\0'`" (Listing 4.4: count and length in one pass, no `strlen`). The same applies to counted ranges
(`views::counted`), I/O streams and parsers. Before C++20, every one of these needed a pre-pass or a fake end iterator.

**L7 principal defense.** "Sentinels make the end condition explicit and remove passes. I use them for terminated
buffers and protocol parsers, and pass `unreachable_sentinel` when a bound is known by construction, which removes the
bounds check inside the loop."
</details>

<details><summary><b>Chain 4 🔥 "Return a filtered view from a function"</b></summary>

**Initial prompt.** "Write `auto active_users(std::vector<User> users)` returning the active ones lazily."

**L5 textbook answer.** `return users | std::views::filter(&User::active);`

**Why L5 breaks.** `users` is a function parameter, an lvalue, so `views::all(users)` is a `ref_view` that refers to it.
The parameter is destroyed when the function returns, and the caller iterates a dangling view. It compiles cleanly.

**L7 principal defense.** "`return std::move(users) | std::views::filter(&User::active);`: an rvalue becomes an
`owning_view` (P2415), so the returned pipeline owns the data. Or return a `std::vector` and let the caller filter. In
APIs I avoid returning views over function-local state at all, because the ownership is invisible at the call site."
</details>

<details><summary><b>Chain 5 ⚡ "Projections"</b></summary>

**Initial prompt.** "What are projections in ranges algorithms, and why use them?"

**L5 textbook answer.** "A way to sort by a member, instead of writing a comparator."

**Why L5 breaks.** That is the convenience part. The deeper benefits: the comparator stays generic (`std::ranges::less`),
the key extraction is separated (and can be a pointer to member), and constrained algorithms check that the *projected*
type satisfies the comparator's requirements. The cost trap: the projection runs on every comparison (about 2 n log n
calls for a sort), so an expensive projection (computing a hash, formatting) should be precomputed.

**L7 principal defense.** "`std::ranges::sort(v, {}, &Order::price)` for cheap keys. For expensive keys, compute them
once into a parallel array, or sort indices by cached keys. Projections clarify code but do not cache."
</details>

<details><summary><b>Chain 6 🧊 "Why does my pipeline not compile with const?"</b></summary>

**Initial prompt.** "`void print(const auto& r)` works for vectors but not for `v | views::filter(p)`. Fix?"

**L5 textbook answer.** "Remove `const`."

**Why L5 breaks.** Removing `const` is the fix. The L7 answer explains why: `filter_view::begin()` caches its result to
be amortized O(1), so it is non-const (Folder 02, file 03). `drop_while_view` and `split_view` do the same. Generic code
must take ranges by forwarding reference (`auto&& r`), and must not assume views are const-iterable or thread-safe to
iterate concurrently.

**L7 principal defense.** "Forwarding references for range parameters, and a note in the API that iterating may mutate
the view. Two threads must not iterate the same `filter_view`, because the cache write is a data race."
</details>

<details><summary><b>Chain 7 ⚡ "ranges::to vs a loop"</b></summary>

**Initial prompt.** "How do you materialize a view into a container?"

**L5 textbook answer.** "Loop and `push_back`."

**Why L5 breaks.** It works, but misses reservation and type deduction. C++23 `std::ranges::to<std::vector>()` (both
libraries) reserves when the view is sized (`sized_range`), deduces the element type, and works for nested containers.
For unsized views (`filter`) it cannot reserve, and neither can a hand loop without a counting pass.

**L7 principal defense.** "`ranges::to` at API boundaries, `reserve` + loop where I can bound the size better than the
library can (for example, by an upper bound from the source size)."
</details>

<details><summary><b>Chain 8 🔥 "Views and threads"</b></summary>

**Initial prompt.** "Can two threads iterate the same view?"

**L5 textbook answer.** "Yes, iteration is read-only."

**Why L5 corrupts memory on ARM64.** Not for caching views. The first `begin()` on a `filter_view` *writes* the cached
iterator. Two threads calling `begin()` concurrently race on that write: on x86 you usually get one of two equal values;
on ARM64 a reader can observe a partially published cache (a non-atomic 8–16-byte iterator), and then iterate from a
garbage position. TSan reports it as a data race (Folder 12).

**L7 principal defense.** "Each thread builds its own view (views are cheap to construct), or the view is fully
materialized before sharing. Shared read-only access is only safe for views without caches, which I would not rely on
in generic code."
</details>

---

## 6. Invariants checklist

- [ ] No views over function-local or temporary data escape their scope; returned pipelines are owning.
- [ ] Generic range parameters are forwarding references.
- [ ] Hot loops with cheap predicates are compared against a hand loop in the profile.
- [ ] Expensive projections are precomputed.
- [ ] Views with caches are never iterated concurrently.
- [ ] Terminated or bounded data uses sentinels instead of pre-passes.

## 7. References

- P0896R4 (One Ranges Proposal): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2018/p0896r4.pdf>
- P2415R2 (what is a view?): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2021/p2415r2.html>
- P1206R7 (`ranges::to`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2022/p1206r7.pdf>
- Barry Revzin, "Iterating over a range of ranges" and the ranges blog posts: <https://brevzin.github.io/>
- Eric Niebler, range-v3: <https://github.com/ericniebler/range-v3>
