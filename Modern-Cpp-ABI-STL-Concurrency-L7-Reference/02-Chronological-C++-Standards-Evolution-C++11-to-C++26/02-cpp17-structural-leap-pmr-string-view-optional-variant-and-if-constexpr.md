# 02 · C++17: the structural leap (PMR, `string_view`, `optional`/`variant`, `if constexpr`)

> **Scope.** C++17 changed how C++ libraries are *built* more than how programs look: guaranteed copy elision
> (Folder 01), vocabulary types (`optional`, `variant`, `any`, `string_view`), polymorphic memory resources, and
> the language features that removed whole categories of template tricks (`if constexpr`, fold expressions,
> structured bindings, CTAD, inline variables, defined evaluation order). Every feature is shown with the trap that
> comes with it, and where the two standard libraries make *different* choices, both are shown.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 2.5 | `pmr_bench.cpp` | the same container code on a monotonic arena: 402,400 → 0 heap allocations, ~8× faster | run, both libraries (timed) |
| 2.6 | `sv.cpp` | `string_view` in two registers vs `const string&` + SSO decode; implicit `std::string` construction; no terminator; dangling detection differs by compiler | run + asm + diagnostics |
| 2.7 | `variant_visit.cpp` | `optional`/`variant` sizes; `std::visit` is a **branch** in libstdc++ and an **indirect call** in libc++; valueless-by-exception differs | run + asm (Clang/libc++, GCC/libstdc++) |
| 2.8 | `cpp17_lang.cpp` | folds, `if constexpr`, structured-binding copies, CTAD surprises, P0145 evaluation order | run, both compilers |

**Verification line.** Native runs: GCC 16.2 + libstdc++, Clang 21.1 + libc++. Codegen: Clang 21.1 `-O3` for
x86-64/AArch64 Linux (libc++), and GCC 16.2 `-O3` in its native Win64 calling convention for the libstdc++ `visit`
comparison (marked `gccw`; arguments arrive in RCX, RDX, … instead of RDI, RSI, …).

---

## 1. First principles

### 1.1 Polymorphic memory resources (Listing 2.5)

`std::pmr::polymorphic_allocator<T>` holds a pointer to a `std::pmr::memory_resource` and forwards every
allocation to its virtual `do_allocate`. One container type works with any resource. The allocator **propagates**:
a `pmr::vector<pmr::string>` passes its resource to each string it constructs (uses-allocator construction).

```text
 pmr::vector<pmr::string> v(&arena)
   +-- v.data_ -------> [ string | string | ... ]  <- allocated from arena
   +-- v.alloc_ = &arena          |
                         each element: { ptr, size, cap/SSO, alloc_ = &arena }  <- 8 bytes bigger than std::string
                                    +--> heap buffer for 48 chars: also from arena

 monotonic_buffer_resource: bump pointer inside 'buffer'; deallocate() is a no-op; release/destructor resets
 the pointer. null_memory_resource() as upstream: running out THROWS bad_alloc instead of silently using the heap.
```

```cpp
// pmr_bench.cpp - C++17 polymorphic allocators: the same container code on a monotonic arena vs the heap
#include <chrono>
#include <cstddef>
#include <cstdlib>
#include <memory_resource>
#include <new>
#include <print>
#include <string>
#include <vector>

// Count every global operator new: the arena should make the heap disappear from the hot loop.
static std::size_t g_heap_allocs = 0;
void* operator new(std::size_t n) {
    ++g_heap_allocs;
    if (void* p = std::malloc(n ? n : 1)) return p;
    throw std::bad_alloc{};
}
void operator delete(void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }

template <class Vec>
static std::size_t fill(Vec& v, int n) {
    std::size_t total = 0;
    for (int i = 0; i < n; ++i) {
        v.emplace_back(48, static_cast<char>('a' + i % 26));  // 48 chars: beyond SSO in every library
        total += v.back().size();
    }
    return total;
}

int main() {
    constexpr int kStrings = 2000, kRounds = 200;
    using clock = std::chrono::steady_clock;

    g_heap_allocs = 0;
    auto t0 = clock::now();
    std::size_t sink = 0;
    for (int r = 0; r < kRounds; ++r) {
        std::vector<std::string> v;                           // std::allocator -> operator new
        sink += fill(v, kStrings);
    }
    auto t1 = clock::now();
    std::size_t heap_default = g_heap_allocs;

    alignas(std::max_align_t) static std::byte buffer[512 * 1024];
    g_heap_allocs = 0;
    auto t2 = clock::now();
    for (int r = 0; r < kRounds; ++r) {
        std::pmr::monotonic_buffer_resource arena(buffer, sizeof buffer, std::pmr::null_memory_resource());
        std::pmr::vector<std::pmr::string> v(&arena);           // the allocator PROPAGATES to the strings
        sink += fill(v, kStrings);
    }                                                         // releasing the arena = one pointer reset
    auto t3 = clock::now();
    std::size_t heap_pmr = g_heap_allocs;

    auto ms = [](auto d) { return std::chrono::duration<double, std::milli>(d).count(); };
    std::println("{} rounds x {} strings of 48 chars (sink {}):", kRounds, kStrings, sink);
    std::println("  std::vector<std::string>            {:7.1f} ms   heap allocations: {}", ms(t1 - t0), heap_default);
    std::println("  pmr::vector<pmr::string> on arena    {:7.1f} ms   heap allocations: {}", ms(t3 - t2), heap_pmr);
    std::println("sizeof(std::string)={} sizeof(std::pmr::string)={}  (the allocator pointer is per object)",
                 sizeof(std::string), sizeof(std::pmr::string));
}
```

GCC 16.2 + libstdc++ (one run):

```text
200 rounds x 2000 strings of 48 chars (sink 38400000):
  std::vector<std::string>               43.8 ms   heap allocations: 402400
  pmr::vector<pmr::string> on arena        5.3 ms   heap allocations: 0
sizeof(std::string)=32 sizeof(std::pmr::string)=40  (the allocator pointer is per object)
```

Clang 21.1 + libc++ (one run):

```text
200 rounds x 2000 strings of 48 chars (sink 38400000):
  std::vector<std::string>               25.4 ms   heap allocations: 402400
  pmr::vector<pmr::string> on arena        3.7 ms   heap allocations: 0
sizeof(std::string)=24 sizeof(std::pmr::string)=32  (the allocator pointer is per object)
```

* 402,400 = 200 rounds × (2,000 string buffers + 12 vector growths). With the arena, **zero** calls reach the global
  `operator new`: every string buffer and every vector buffer comes from the bump pointer.
* The 8–9× speed-up is allocation cost plus locality: consecutive strings are adjacent in memory.
* The cost is visible in `sizeof`: `pmr::string` is 8 bytes bigger (the resource pointer) in both libraries. A
  `pmr::vector<pmr::string>` with 10⁶ elements carries 8 MB of identical pointers.
* The trap is lifetime. Objects allocated from `arena` must not outlive it. A `pmr::string` copied into a
  longer-lived container with a *different* resource is fine (it copies). Moving it between resources is a copy
  too, because the allocators compare unequal. Assignment between containers with different resources therefore
  copies, which silently undoes the "move" in move-heavy code.

### 1.2 `std::string_view`: two words, no ownership, no terminator (Listing 2.6)

```cpp
// sv.cpp - std::string_view: two registers instead of a pointer chase, no terminator, no ownership
#include <cstddef>
#include <cstdio>
#include <string>
#include <string_view>

// By value: {data, size} arrive in RDI:RSI (x86-64) / X0:X1 (AArch64). No indirection to reach the size.
std::size_t len_sv(std::string_view s) { return s.size(); }
// By const reference: one pointer, then a load (and the layout of std::string is library-specific).
std::size_t len_str(const std::string& s) { return s.size(); }
// A const char* caller of the string overload must construct a std::string (strlen + maybe heap).
std::size_t call_str(const char* p) { return len_str(p); }
std::size_t call_sv(const char* p) { return len_sv(p); }

std::string make_name() { return std::string(40, 'n'); }

int main() {
    std::string_view word = std::string_view("hello world").substr(0, 5);
    std::printf("view: %.*s (size %zu)\n", static_cast<int>(word.size()), word.data(), word.size());
    std::printf("data() as a C string: %s   <- no terminator after 'hello'\n", word.data());
#ifdef SHOW_DANGLING_VIEW
    std::string_view dangling = make_name();   // the temporary std::string dies at the semicolon
    std::printf("%zu\n", dangling.size());
#endif
    std::printf("len_sv=%zu len_str=%zu\n", call_sv("abc"), call_str("abc"));
}
```

Output (verified, both compilers):

```text
view: hello (size 5)
data() as a C string: hello world   <- no terminator after 'hello'
len_sv=3 len_str=3
```

Clang `-O3`, x86-64 (libc++):

```asm
_Z6len_svNSt3__117basic_string_viewIcNS_11char_traitsIcEEEE: # len_sv(std::__1::basic_string_view<char, std::__1::char_traits<char> >)
	movq	%rsi, %rax
	retq

_Z7len_strRKNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEE: # len_str(std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&)
	movzbl	(%rdi), %eax
	testb	$1, %al
	je	.LBB1_1
	movq	8(%rdi), %rax
	retq
.LBB1_1:
	shrl	%eax
	retq

_Z8call_strPKc:                    # call_str(char const*)
	pushq	%r15
	pushq	%r14
	pushq	%r12
	pushq	%rbx
	subq	$24, %rsp
	movq	%rdi, %r14
	callq	strlen@PLT
	cmpq	$-9, %rax
	jae	.LBB2_9
	movq	%rax, %rbx
	cmpq	$23, %rax
	jae	.LBB2_2
	leal	(%rbx,%rbx), %eax
	movb	%al, (%rsp)
	leaq	1(%rsp), %r15
	testq	%rbx, %rbx
	jne	.LBB2_4
	jmp	.LBB2_5
.LBB2_2:
	movq	%rbx, %rax
	orq	$7, %rax
	leaq	1(%rax), %rcx
	cmpq	$23, %rax
	movl	$26, %r12d
	cmovneq	%rcx, %r12
	movq	%r12, %rdi
	callq	_Znwm@PLT                            # operator new(unsigned long)
	movq	%rax, %r15
	movq	%rax, 16(%rsp)
	orq	$1, %r12
	movq	%r12, (%rsp)
	movq	%rbx, 8(%rsp)
.LBB2_4:
	movq	%r15, %rdi
	movq	%r14, %rsi
	movq	%rbx, %rdx
	callq	memcpy@PLT
.LBB2_5:
	movb	$0, (%r15,%rbx)
	movzbl	(%rsp), %ebx
	testb	$1, %bl
	jne	.LBB2_7
	shrl	%ebx
	jmp	.LBB2_8
.LBB2_7:
	movq	(%rsp), %rsi
	movq	8(%rsp), %rbx
	movq	16(%rsp), %rdi
	andq	$-2, %rsi
	callq	_ZdlPvm@PLT                          # operator delete(void*, unsigned long)
.LBB2_8:
	movq	%rbx, %rax
	addq	$24, %rsp
	popq	%rbx
	popq	%r12
	popq	%r14
	popq	%r15
	retq
.LBB2_9:
	callq	_ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE20__throw_length_errorB8ne210100Ev@PLT # std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> >::__throw_length_error[abi:ne210100]()

_Z7call_svPKc:                     # call_sv(char const*)
	jmp	strlen@PLT
```

<details><summary>AArch64</summary>

```asm
_Z6len_svNSt3__117basic_string_viewIcNS_11char_traitsIcEEEE: // len_sv(std::__1::basic_string_view<char, std::__1::char_traits<char> >)
	mov	x0, x1
	ret

_Z7len_strRKNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEE: // len_str(std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&)
	ldrb	w8, [x0]
	ldr	x9, [x0, #8]
	lsr	x10, x8, #1
	tst	w8, #0x1
	csel	x0, x10, x9, eq
	ret

_Z8call_strPKc:                    // call_str(char const*)
	sub	sp, sp, #80
	str	x30, [sp, #32]
	stp	x22, x21, [sp, #48]
	stp	x20, x19, [sp, #64]
	mov	x20, x0
	bl	strlen
	cmn	x0, #9
	b.hs	.LBB2_9
	mov	x19, x0
	cmp	x0, #23
	b.hs	.LBB2_3
	lsl	w8, w19, #1
	add	x9, sp, #8
	orr	x21, x9, #0x1
	strb	w8, [sp, #8]
	cbnz	x19, .LBB2_4
	b	.LBB2_5
.LBB2_3:
	orr	x8, x19, #0x7
	mov	w9, #26
	cmp	x8, #23
	csinc	x22, x9, x8, eq
	mov	x0, x22
	bl	_Znwm                                   // operator new(unsigned long)
	orr	x8, x22, #0x1
	mov	x21, x0
	stp	x19, x0, [sp, #16]
	str	x8, [sp, #8]
.LBB2_4:
	mov	x0, x21
	mov	x1, x20
	mov	x2, x19
	bl	memcpy
.LBB2_5:
	strb	wzr, [x21, x19]
	ldrb	w8, [sp, #8]
	tbnz	w8, #0, .LBB2_7
	lsr	x19, x8, #1
	b	.LBB2_8
.LBB2_7:
	ldp	x19, x0, [sp, #16]
	ldr	x8, [sp, #8]
	and	x1, x8, #0xfffffffffffffffe
	bl	_ZdlPvm                                 // operator delete(void*, unsigned long)
.LBB2_8:
	mov	x0, x19
	ldp	x20, x19, [sp, #64]
	ldp	x22, x21, [sp, #48]
	ldr	x30, [sp, #32]
	add	sp, sp, #80
	ret
.LBB2_9:
	bl	_ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE20__throw_length_errorB8ne210100Ev // std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> >::__throw_length_error[abi:ne210100]()

_Z7call_svPKc:                     // call_sv(char const*)
	b	strlen
```

</details>

* **`len_sv` is one `mov`**: a `string_view` is `{const char*, size_t}`, trivially copyable, 16 bytes, so it travels
  in RDI:RSI / X0:X1 (Folder 01, file 02, §1.4). `len_str` must decode libc++'s SSO layout (test the short/long
  bit in the first byte, then load the size from one of two places).
* **`call_str("abc")` constructs a `std::string`**: `strlen`, a small-string or `operator new` path, `memcpy`,
  then the destructor. `call_sv("abc")` is `strlen` and nothing else. A `const std::string&` parameter that is
  mostly fed string literals pays for a temporary on every call.
* **`data()` is not a C string.** The view `"hello"` printed with `%s` shows `hello world`, because the bytes after
  the view happen to continue. With a different buffer it reads past the end. Never pass `sv.data()` to a C API
  that expects a terminator. Use `%.*s`, or make a `std::string`.
* **Dangling is not reliably diagnosed.** `std::string_view sv = make_name();` binds to a temporary string that
  dies at the semicolon:

```text
sv.cpp:22:33: error: object backing the pointer will be destroyed at the end of the full-expression [-Werror,-Wdangling-gsl]
sv.cpp: compiled with NO diagnostic (gcc)
```

  Clang's `-Wdangling-gsl` (on by default) rejects it: Clang's lifetime analysis treats `std::string_view` as a
  "pointer" type and `std::string` as its "owner" (the `[[gsl::Pointer]]` / `[[gsl::Owner]]` model). **GCC 16.2 compiles it with no diagnostic** under `-Wall -Wextra`. The only
  dependable rule is ownership discipline: `string_view` parameters are fine, `string_view` *members and return
  values* need a documented owner.

### 1.3 `std::optional` and `std::variant`: layout, `visit`, and the valueless state (Listing 2.7)

```cpp
// variant_visit.cpp - std::optional / std::variant layout, valueless_by_exception, and what std::visit compiles to
#include <cstdint>
#include <optional>
#include <print>
#include <stdexcept>
#include <string>
#include <variant>

template <class... F>
struct overloaded : F... {
    using F::operator()...;
};

struct Circle { double r; };
struct Rect { double w, h; };
struct Tri { double b, h; };
using Shape = std::variant<Circle, Rect, Tri>;

// std::visit over a closed set: the compiler sees every alternative (compare: a virtual call).
double area(const Shape& s) {
    return std::visit(overloaded{[](const Circle& c) { return 3.14159 * c.r * c.r; },
                                 [](const Rect& r) { return r.w * r.h; },
                                 [](const Tri& t) { return 0.5 * t.b * t.h; }},
                      s);
}

struct Bomb {                          // throws while being constructed into the variant
    Bomb() { throw std::runtime_error("boom"); }
};

int main() {
    std::println("sizeof: optional<int>={} optional<double>={} optional<std::string>={}", sizeof(std::optional<int>),
                 sizeof(std::optional<double>), sizeof(std::optional<std::string>));
    std::println("sizeof: variant<int,double>={} variant<char,int64_t>={} Shape={}", sizeof(std::variant<int, double>),
                 sizeof(std::variant<char, std::int64_t>), sizeof(Shape));
    Shape s = Rect{2, 3};
    std::println("area(Rect{{2,3}}) = {}, index = {}", area(s), s.index());

    std::variant<std::string, Bomb> v = std::string("intact");
    try {
        v.emplace<Bomb>();             // the old string is destroyed first, then Bomb's constructor throws
    } catch (const std::exception& e) {
        std::println("emplace threw '{}': valueless_by_exception() = {}, index() == variant_npos: {}", e.what(),
                     v.valueless_by_exception(), v.index() == std::variant_npos);
    }
    if (!v.valueless_by_exception())   // allowed: the standard says the variant "might not hold a value"
        std::println("  the variant still holds \"{}\": this library built the new value in a temporary first",
                     std::get<std::string>(v));
    try {
        std::visit([](const auto&) {}, v);
    } catch (const std::bad_variant_access& e) {
        std::println("visit on a valueless variant throws bad_variant_access");
    }
}
```

GCC 16.2 + libstdc++ (verified):

```text
sizeof: optional<int>=8 optional<double>=16 optional<std::string>=40
sizeof: variant<int,double>=16 variant<char,int64_t>=16 Shape=24
area(Rect{2,3}) = 6, index = 1
emplace threw 'boom': valueless_by_exception() = false, index() == variant_npos: false
  the variant still holds "intact": this library built the new value in a temporary first
```

Clang 21.1 + libc++ (verified):

```text
sizeof: optional<int>=8 optional<double>=16 optional<std::string>=32
sizeof: variant<int,double>=16 variant<char,int64_t>=16 Shape=24
area(Rect{2,3}) = 6, index = 1
emplace threw 'boom': valueless_by_exception() = true, index() == variant_npos: true
visit on a valueless variant throws bad_variant_access
```

The sizes are the same on both libraries (except for `optional<std::string>`, which follows `sizeof(string)`):
`optional<T>` is `T` plus a `bool`, rounded up to `T`'s alignment. `variant` is the largest alternative plus an
index. Two behaviours differ:

**1. A throwing `emplace` leaves libc++'s variant valueless, libstdc++'s intact.** The standard says the variant
"might not hold a value" after an exception during `emplace`, so both are conforming. libstdc++ constructs the new
alternative in a temporary first when the type is nothrow-move-constructible (here `Bomb` is), so a throwing
constructor never touches the old value. libc++ destroys the old value and then constructs in place. Portable code
must handle `valueless_by_exception()` and must not rely on either behaviour.

**2. `std::visit` compiles very differently.**

Clang 21.1 + libc++, x86-64:

```asm
_Z4areaRKNSt3__17variantIJ6Circle4Rect3TriEEE: # area(std::__1::variant<Circle, Rect, Tri> const&)
	subq	$24, %rsp
	movl	16(%rdi), %eax
	movl	$4294967295, %ecx
	cmpq	%rcx, %rax
	je	.LBB0_2
	movq	%rdi, %rsi
	leaq	15(%rsp), %rcx
	movq	%rcx, 16(%rsp)
	leaq	.L__const._ZNSt3__116__variant_detail12__visitation6__base11__visit_altB8ne210100INS1_9__variant15__value_visitorI10overloadedIJZ4areaRKNS_7variantIJ6Circle4Rect3TriEEEE3$_0Z4areaSD_E3$_1Z4areaSD_E3$_2EEEEJRKNS0_6__implIJS8_S9_SA_EEEEEEDcOT_DpOT0_.__fmatrix(%rip), %rcx # decltype(auto) std::__1::__variant_detail::__visitation::__base::__visit_alt[abi:ne210100]<std::__1::__variant_detail::__visitation::__variant::__value_visitor<overloaded<area(std::__1::variant<Circle, Rect, Tri> const&)::$_0, area(std::__1::variant<Circle, Rect, Tri> const&)::$_1, area(std::__1::variant<Circle, Rect, Tri> const&)::$_2> >, std::__1::__variant_detail::__impl<Circle, Rect, Tri> const&>(std::__1::__variant_detail::__visitation::__variant::__value_visitor<overloaded<area(std::__1::variant<Circle, Rect, Tri> const&)::$_0, area(std::__1::variant<Circle, Rect, Tri> const&)::$_1, area(std::__1::variant<Circle, Rect, Tri> const&)::$_2> >&&, std::__1::__variant_detail::__impl<Circle, Rect, Tri> const&) [clone .__fmatrix]
	leaq	16(%rsp), %rdi
	callq	*(%rcx,%rax,8)
	addq	$24, %rsp
	retq
.LBB0_2:
	callq	_ZNSt3__126__throw_bad_variant_accessB8ne210100Ev@PLT # std::__1::__throw_bad_variant_access[abi:ne210100]()
```

```asm
_Z4areaRKNSt3__17variantIJ6Circle4Rect3TriEEE: // area(std::__1::variant<Circle, Rect, Tri> const&)
	sub	sp, sp, #32
	str	x30, [sp, #16]
	ldr	w8, [x0, #16]
	cmn	w8, #1
	b.eq	.LBB0_2
	adrp	x10, .L__const._ZNSt3__116__variant_detail12__visitation6__base11__visit_altB8ne210100INS1_9__variant15__value_visitorI10overloadedIJZ4areaRKNS_7variantIJ6Circle4Rect3TriEEEE3$_0Z4areaSD_E3$_1Z4areaSD_E3$_2EEEEJRKNS0_6__implIJS8_S9_SA_EEEEEEDcOT_DpOT0_.__fmatrix // decltype(auto) std::__1::__variant_detail::__visitation::__base::__visit_alt[abi:ne210100]<std::__1::__variant_detail::__visitation::__variant::__value_visitor<overloaded<area(std::__1::variant<Circle, Rect, Tri> const&)::$_0, area(std::__1::variant<Circle, Rect, Tri> const&)::$_1, area(std::__1::variant<Circle, Rect, Tri> const&)::$_2> >, std::__1::__variant_detail::__impl<Circle, Rect, Tri> const&>(std::__1::__variant_detail::__visitation::__variant::__value_visitor<overloaded<area(std::__1::variant<Circle, Rect, Tri> const&)::$_0, area(std::__1::variant<Circle, Rect, Tri> const&)::$_1, area(std::__1::variant<Circle, Rect, Tri> const&)::$_2> >&&, std::__1::__variant_detail::__impl<Circle, Rect, Tri> const&) [clone .__fmatrix]
	add	x10, x10, :lo12:.L__const._ZNSt3__116__variant_detail12__visitation6__base11__visit_altB8ne210100INS1_9__variant15__value_visitorI10overloadedIJZ4areaRKNS_7variantIJ6Circle4Rect3TriEEEE3$_0Z4areaSD_E3$_1Z4areaSD_E3$_2EEEEJRKNS0_6__implIJS8_S9_SA_EEEEEEDcOT_DpOT0_.__fmatrix // decltype(auto) std::__1::__variant_detail::__visitation::__base::__visit_alt[abi:ne210100]<std::__1::__variant_detail::__visitation::__variant::__value_visitor<overloaded<area(std::__1::variant<Circle, Rect, Tri> const&)::$_0, area(std::__1::variant<Circle, Rect, Tri> const&)::$_1, area(std::__1::variant<Circle, Rect, Tri> const&)::$_2> >, std::__1::__variant_detail::__impl<Circle, Rect, Tri> const&>(std::__1::__variant_detail::__visitation::__variant::__value_visitor<overloaded<area(std::__1::variant<Circle, Rect, Tri> const&)::$_0, area(std::__1::variant<Circle, Rect, Tri> const&)::$_1, area(std::__1::variant<Circle, Rect, Tri> const&)::$_2> >&&, std::__1::__variant_detail::__impl<Circle, Rect, Tri> const&) [clone .__fmatrix]
	mov	x1, x0
	ldr	x8, [x10, x8, lsl #3]
	add	x9, sp, #15
	add	x0, sp, #24
	str	x9, [sp, #24]
	blr	x8
	ldr	x30, [sp, #16]
	add	sp, sp, #32
	ret
.LBB0_2:
	bl	_ZNSt3__126__throw_bad_variant_accessB8ne210100Ev // std::__1::__throw_bad_variant_access[abi:ne210100]()
```

GCC 16.2 + libstdc++ (Win64 calling convention: the variant's address arrives in RCX):

```asm
_Z4areaRKSt7variantIJ6Circle4Rect3TriEE: # area(std::variant<Circle, Rect, Tri> const&)
	movzbl	16(%rcx), %eax
	cmpq	$1, %rax
	je	.L262
	cmpq	$2, %rax
	jne	.L265
	movsd	.LC14(%rip), %xmm0
	mulsd	(%rcx), %xmm0
	mulsd	8(%rcx), %xmm0
	ret
.L265:
	movsd	(%rcx), %xmm1
	movsd	.LC13(%rip), %xmm0
	mulsd	%xmm1, %xmm0
	mulsd	%xmm1, %xmm0
	ret
.L262:
	movsd	(%rcx), %xmm0
	mulsd	8(%rcx), %xmm0
	ret
```

libc++ dispatches through a **function-pointer table** (`__fmatrix`): `callq *(%rcx,%rax,8)`. That is an indirect
call that is not inlined, exactly like a virtual call (Folder 01, file 01). libstdc++ turns `visit` with a single
variant into a **switch**: two compares on the index byte, then each alternative's arithmetic inlined in place.
The two libraries also store the index differently: a byte (`movzbl 16(%rcx)`) in libstdc++, 32 bits compared
with `0xFFFFFFFF` (the valueless marker) in libc++. "`std::variant` is faster than virtual functions" is therefore
**true with libstdc++ and not necessarily with libc++**. For hot code on libc++, a hand-written `switch (v.index())`
with `std::get_if` gives the switch form on both.

### 1.4 The C++17 language features, with their traps (Listing 2.8)

```cpp
// cpp17_lang.cpp - C++17 language features and their traps: structured bindings, CTAD, if constexpr, folds
#include <map>
#include <print>
#include <string>
#include <tuple>
#include <type_traits>
#include <vector>

// Fold expressions replace C++11 recursion (variadic.cpp); one instantiation, any arity.
template <class... T>
auto sum(T... v) { return (v + ... + 0); }
template <class... T>
bool all_positive(T... v) { return ((v > 0) && ...); }  // empty pack -> true

// if constexpr discards the untaken branch at instantiation: no SFINAE, no tag dispatch.
template <class T>
std::string describe(const T& v) {
    if constexpr (std::is_integral_v<T>) return "integral " + std::to_string(v);
    else if constexpr (std::is_floating_point_v<T>) return "floating " + std::to_string(v);
    else return "other: " + std::string(v);   // only instantiated for T where this compiles
}

struct Big {
    std::vector<int> data = std::vector<int>(1000);
    static inline int copies = 0;      // C++17 inline variable: defined in the header, one object program-wide
    Big() = default;
    Big(const Big& o) : data(o.data) { ++copies; }
    Big(Big&&) noexcept = default;
};

int main() {
    std::println("sum(1,2,3)={} sum()={} all_positive(1,2,-3)={} all_positive()={}", sum(1, 2, 3), sum(),
                 all_positive(1, 2, -3), all_positive());
    std::println("{} | {} | {}", describe(42), describe(2.5), describe("text"));

    // Structured bindings: 'auto [a, b] = p;' COPIES the whole object, then names its members.
    std::pair<Big, int> p;
    auto [b1, n1] = p;
    auto& [b2, n2] = p;               // binds to p itself
    std::println("auto [..] = pair copies Big: {} copy; auto& [..] copies: {}", Big::copies, Big::copies - 1);
    b2.data[0] = 7;
    std::println("p.first.data[0] after writing through b2: {}; through b1 copy untouched: {}", p.first.data[0],
                 b1.data[0]);
    (void)n1; (void)n2;
    std::map<std::string, int> m{{"a", 1}, {"b", 2}};
    for (const auto& [key, value] : m) std::print("{}={} ", key, value);
    std::println("");

    // CTAD: the deduced type is not always the one you meant.
    std::vector v1{1, 2, 3};          // vector<int>
    std::vector v2{v1};               // vector<int> (copy deduction candidate), NOT vector<vector<int>>
    std::vector v3{v1, v1};           // vector<vector<int>>
    static_assert(std::is_same_v<decltype(v2), std::vector<int>>);
    static_assert(std::is_same_v<decltype(v3), std::vector<std::vector<int>>>);
    std::tuple t{1, 2.0, std::string("x")};  // tuple<int, double, std::string>
    std::println("v2.size()={} v3.size()={} tuple<{}> elements", v2.size(), v3.size(), std::tuple_size_v<decltype(t)>);

    // Guaranteed evaluation order (P0145): in a = b the RIGHT operand is sequenced first; in a << b, a[b],
    // a.b and a->b the left one is.
    std::size_t i = 0;
    std::vector<std::size_t> order(3);
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wsequence-point"  // GCC 16 still warns here in C++17 mode; the order is defined
    order[i++] = i + 10;              // C++17: reads i (0) first, then order[0] -> 10. Before C++17: UB
#pragma GCC diagnostic pop
    std::println("order[0] after 'order[i++] = i + 10' = {}", order[0]);
}
```

Output (verified, both compilers):

```text
sum(1,2,3)=6 sum()=0 all_positive(1,2,-3)=false all_positive()=true
integral 42 | floating 2.500000 | other: text
auto [..] = pair copies Big: 1 copy; auto& [..] copies: 0
p.first.data[0] after writing through b2: 7; through b1 copy untouched: 0
a=1 b=2 
v2.size()=3 v3.size()=2 tuple<3> elements
order[0] after 'order[i++] = i + 10' = 10
```

* **Folds** handle empty packs by identity: `(v + ... + 0)` is 0, and `(... && pred)` is `true` for an empty pack.
  A unary fold over `+` with an empty pack is ill-formed. Always give the identity.
* **`if constexpr`** discards the untaken branch *at instantiation*. `describe("text")` instantiates only the
  `std::string(v)` branch. In a non-template, both branches are still checked.
* **Structured bindings copy unless you write `&`.** `auto [b1, n1] = p;` copied the 1,000-element vector once,
  and writing through `b2` (from `auto&`) changed `p`. The names are aliases into one hidden object, either the
  copy or the reference.
* **CTAD surprise:** `std::vector v2{v1}` is `vector<int>` (the copy deduction candidate wins), while
  `std::vector v3{v1, v1}` is `vector<vector<int>>`. Generic code that does `std::vector{x}` changes meaning when
  `x` happens to be a vector.
* **Evaluation order (P0145).** In `a = b` the *right* operand is sequenced first. `order[i++] = i + 10` reads `i`
  (0), then indexes `order[0]`. Before C++17 this was undefined. **GCC 16 still warns `-Wsequence-point` here in
  C++17+ mode** (the listing silences it with a pragma), Clang does not. The other P0145 rules: `a.b`, `a->b`,
  `a[b]`, `a << b`, `a >> b` evaluate the left side first. Function arguments are still unsequenced relative to
  each other (only interleaving is forbidden).

---

## 2. Evolution table

| Area | C++17 addition (paper) | Before | After (C++20/23/26) |
|---|---|---|---|
| elision | guaranteed copy elision (P0135R1) | optional RVO | Folder 01, file 02 |
| vocabulary | `optional`, `variant`, `any` (P0088 et al.) | Boost | C++23 `optional` monadic ops (P0798), `expected`; C++26 `optional<T&>` (P2988), `optional` as a range (P3168) |
| strings | `string_view` (N3921 lineage) | `const char*` + length | C++20 `starts_with`/`ends_with`; C++23 `contains`; C++26 `string_view` + `string` concatenation (P2591) |
| memory | `<memory_resource>` (P0220) | allocator templates per container | C++20 `polymorphic_allocator<>` defaults, `allocate_object` |
| language | `if constexpr`, folds, structured bindings, CTAD, inline variables, `[[nodiscard]]` | tag dispatch, SFINAE, recursion | C++20 concepts; C++26 structured-binding packs, pack indexing |
| evaluation order | P0145 | unsequenced/UB cases | — |
| aligned new | P0035R4 | manual over-alignment | — |
| filesystem | `<filesystem>` (P0218) | Boost.Filesystem | — |
| parallel algorithms | execution policies (P0024) | TBB / OpenMP | C++26 `std::execution` (P2300) is a different model (Folder 10) |
| removed | `auto_ptr`, `register`, trigraphs, dynamic exception specs | — | — |

On parallel algorithms: both toolchains *declare* them. libstdc++ reports `__cpp_lib_parallel_algorithm`, libc++
21 does not (the std probe in file 04). libstdc++ runs `std::execution::par` in parallel only when built against
Intel TBB, and otherwise falls back to serial. ⚠ The TBB-backed path was not exercised here.

---

## 3. Production blueprints

### 3.1 Request-scoped arenas

| Subtle buggy way | Production-hardened way |
|---|---|
| `monotonic_buffer_resource arena;` (default upstream = the heap) | pass `null_memory_resource()` as upstream when the budget must be enforced, or a pooled upstream when it may grow |
| storing a `pmr::string` from the arena in a global cache | copy into a container with the global resource; static-analysis rule: arena-scoped types do not escape |
| `v1 = std::move(v2)` between containers on different arenas | the allocators compare unequal, so this is an element-wise copy; keep move-heavy data on one resource |
| `pmr::` everywhere "for speed" | profile first; each object grows by 8 bytes and each allocation becomes a virtual call |

### 3.2 `string_view` rules

1. Parameters: `std::string_view` for read-only text that is not stored.
2. Members and return values: only with a named owner whose lifetime is documented (an interned-string table, a
   memory-mapped file).
3. Never `data()` into C APIs; never `string_view` of a temporary.
4. Clang builds catch common dangling (`-Wdangling-gsl`). GCC 16 does not, so the rule has to live in review.

### 3.3 `variant` on hot paths

Benchmark on *your* standard library (Listing 2.7: switch on libstdc++, function table on libc++). For a closed
set on a hot path, write the `switch (v.index())` yourself with `std::get_if`. Handle `valueless_by_exception()`
or make alternatives nothrow-move-constructible.

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| garbage at the end of a printed name | `sv.data()` passed to `%s` / a C API | review; `%.*s` |
| crash reading a returned `string_view` | view of a temporary or of a destroyed owner | Clang `-Wdangling-gsl`; ASan use-after-free (GCC gives no warning) |
| `bad_variant_access` in production on libc++ only | a valueless variant after an exception | handle `valueless_by_exception()`; nothrow alternatives |
| `std::visit` hot in a profile on macOS/Android (libc++) but not Linux (libstdc++) | function-table dispatch | manual `switch` on `index()` |
| arena-backed objects corrupted after a request ends | `pmr` objects escaped the arena's lifetime | ownership rule + ASan |
| a structured binding "doesn't update" the object | `auto [..]` copied | use `auto&` / `const auto&` |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "Is std::variant faster than virtual functions?"</b></summary>

**Initial prompt.** "We have a closed set of shape types. variant + visit or virtual?"

**L5 textbook answer.** "variant: no heap allocation, no vtable, and the compiler can inline everything."

**Why L5 breaks.** The heap part is right. The inlining claim depends on the library. Listing 2.7: libstdc++
compiles `visit` to a two-compare switch with each alternative inlined; libc++ calls through a function-pointer
table, which is an indirect call just like a virtual call. The answer also misses the valueless state (libc++ goes
valueless after a throwing `emplace`, libstdc++ does not), and the size cost: every `variant` is as large as its
largest alternative.

**L7 principal defense.** "variant for closed sets of small value types, with a benchmark on our toolchain. If
libc++ is in the matrix and dispatch is hot, a manual `switch (index())`. Virtual for open sets and for large or
rarely-mixed types. Either way I would make the alternatives nothrow-move-constructible so that the valueless
state cannot happen."
</details>

<details><summary><b>Chain 2 🔥 "When is std::string_view dangerous?"</b></summary>

**Initial prompt.** "Should all our string parameters become `string_view`?"

**L5 textbook answer.** "Yes, it avoids copies and works with any string."

**Why L5 breaks.** Parameters: mostly yes, and Listing 2.6 shows why (one register pair instead of an SSO decode,
and no temporary `std::string` for literals). But `string_view` is non-owning and not terminated. Returning a view
of a local, storing a view of a temporary, or passing `data()` to `fopen` are all bugs. Only Clang diagnoses the
temporary case; GCC 16.2 compiles it silently. There is also an API trap: changing `const std::string&` to
`string_view` in a function that *stores* the argument forces the callee to copy anyway, and in a function that
passes it on to a C API forces a terminator copy.

**L7 principal defense.** "`string_view` for non-stored, read-only parameters; owners for everything that lives
longer. Clang's lifetime warnings on in CI, because GCC misses this class of bug. And no `data()` into C APIs: wrap
them to take `const std::string&` or a `zstring_view`-like type that guarantees the terminator."
</details>

<details><summary><b>Chain 3 ⚡ "Make allocation 10× cheaper without touching the algorithms"</b></summary>

**Initial prompt.** "A request handler allocates thousands of small strings. How would you cut allocation cost
without rewriting the logic?"

**L5 textbook answer.** "Use a faster malloc like jemalloc or tcmalloc."

**Why L5 breaks.** A better malloc helps (2× is typical), but it still runs per-allocation bookkeeping and frees
each object individually. Listing 2.5 removes 402,400 allocations entirely, ~8–9× faster, by switching the
container types to `pmr` and giving the request a monotonic arena. The trade-offs the L5 answer cannot discuss:
8 bytes more per object, a virtual call per allocation, propagation rules, and lifetime discipline (nothing may
escape the request).

**L7 principal defense.** "Request-scoped `monotonic_buffer_resource` with a stack buffer, `null_memory_resource`
upstream in tests (to prove the budget) and a pool upstream in production. Containers are `pmr::` only inside the
request layer. Results that outlive the request are copied out at the boundary. Then measure: if the profile still
shows allocation, the next step is fewer allocations (`reserve`, `string_view` into the input buffer), not a faster
allocator."
</details>

<details><summary><b>Chain 4 🧊 "What does 'valueless by exception' mean?"</b></summary>

**Initial prompt.** "Can a `std::variant` ever hold no value?"

**L5 textbook answer.** "No, a variant always holds one of its alternatives. That's the point versus a union."

**Why L5 breaks.** It can, after an exception thrown while changing the alternative. Listing 2.7: libc++'s variant
became valueless (`index() == variant_npos`, and `visit` throws `bad_variant_access`). libstdc++'s kept its old
string, because it built the new alternative in a temporary first. Both are conforming. Code tested only with
libstdc++ never sees the state, and then crashes on Apple platforms.

**L7 principal defense.** "I treat valueless as a real state: either make all alternatives nothrow-move-constructible
and build the new value before the assignment (then no library goes valueless), or check `valueless_by_exception()`
where recovery matters. Tests must cover libc++ if we ship on Apple or Android."
</details>

<details><summary><b>Chain 5 ⚡ "auto [a, b] = getPair(); any cost?"</b></summary>

**Initial prompt.** "Do structured bindings copy?"

**L5 textbook answer.** "No, they just give names to the members."

**Why L5 breaks.** They give names to the members of a *hidden object*, and that object is initialized from the
initializer with the declared `auto`/`auto&`/`auto&&`. `auto [b1, n1] = p;` copied a 1,000-element vector (Listing
2.8), and writes through `b1` do not reach `p`. With a prvalue initializer (`= getPair()`), the hidden object *is*
the returned temporary (guaranteed elision), so it is free. The cost depends on the initializer's value category.

**L7 principal defense.** "`const auto& [..]` for reading existing objects, `auto [..]` for function results, and
`auto& [..]` when mutating. The same rule applies to range-for over maps: `for (const auto& [k, v] : m)`."
</details>

<details><summary><b>Chain 6 🧊 "Is f(i++, i++) defined in C++17?"</b></summary>

**Initial prompt.** "C++17 fixed evaluation order. So `f(i++, i++)` is now well-defined?"

**L5 textbook answer.** "Yes, arguments are evaluated left to right now."

**Why L5 breaks.** No. P0145 fixed the order for `a.b`, `a->b`, `a[b]`, `<<`, `>>`, assignment (right first) and a
few more. Function arguments are only *indeterminately sequenced*: no interleaving, but no specified order. So
`f(i++, i++)` gives an unspecified result (GCC and Clang have historically differed). The fixed rules also give
answers people do not expect: `order[i++] = i + 10` assigns to `order[0]` with the *old* `i` (Listing 2.8). And GCC
16 still warns about that line even though it is well-defined now.

**L7 principal defense.** "Never write code whose meaning depends on these rules. The value of P0145 is that
chained calls (`s.replace(...).replace(...)`, `std::cout << f() << g()`) and `m[k] = make(k)` behave as people read
them. Not that we should write puzzles."
</details>

<details><summary><b>Chain 7 ⚡ "CTAD everywhere?"</b></summary>

**Initial prompt.** "Can we drop explicit template arguments now that we have CTAD?"

**L5 textbook answer.** "Yes, `std::vector v{1, 2, 3}` deduces `vector<int>` and it's cleaner."

**Why L5 breaks.** CTAD has corner cases that change types silently. `std::vector v{v1}` is a *copy*
(`vector<int>`), not a vector of vectors (Listing 2.8). `std::pair p{"a", 1}` deduces `pair<const char*, int>`, not
`std::string`. `std::optional o{std::optional{1}}` deduces `optional<int>`. In generic code the result depends on
whether the argument happens to be the same template.

**L7 principal defense.** "CTAD for local variables with literal or obvious arguments. Explicit arguments in generic
code, in public APIs, and whenever the argument might be a specialization of the same template. Deduction guides
for our own types where the default would surprise."
</details>

<details><summary><b>Chain 8 🔥 "if constexpr vs SFINAE vs tag dispatch"</b></summary>

**Initial prompt.** "How do you select an implementation based on a type property?"

**L5 textbook answer.** "SFINAE with `enable_if`."

**Why L5 breaks.** It works, but it is the C++11 answer. Since C++17, `if constexpr` handles the common case inside
one function body (Listing 2.8's `describe`), and since C++20, concepts select *overloads* with readable errors
(file 03). SFINAE also has traps that `if constexpr` lacks: default template arguments are not part of the
signature, so two `enable_if` overloads that differ only in the default argument are redeclarations.

**L7 principal defense.** "`if constexpr` inside a function when the branches share a signature; concepts and
`requires` when the overload set itself must change; SFINAE only in C++14 code bases. Folder 06 file 02 has the
full comparison, including subsumption."
</details>

---

## 6. Invariants checklist

- [ ] `string_view` only for non-owning, non-stored text; never `data()` into C APIs.
- [ ] Clang lifetime warnings enabled in CI (GCC misses dangling views).
- [ ] `variant` alternatives nothrow-move-constructible; `valueless_by_exception()` handled where it matters.
- [ ] Hot `visit` benchmarked on every shipped standard library.
- [ ] Arena-allocated (`pmr`) objects never escape their resource's lifetime; budget enforced with
      `null_memory_resource` in tests.
- [ ] Structured bindings use `const auto&` / `auto&` unless a copy is intended.
- [ ] No CTAD in generic code where the argument may be the same template.

## 7. References

- P0135R1 (guaranteed elision): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2016/p0135r1.html>
- P0145R3 (evaluation order): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2016/p0145r3.pdf>
- P0220R1 (library fundamentals into C++17: `optional`, `any`, `string_view`, `memory_resource`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2016/p0220r1.html>
- P0088R3 (`variant`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2016/p0088r3.html>
- Clang lifetime analysis (`-Wdangling-gsl`): <https://clang.llvm.org/docs/AttributeReference.html#pointer>
- Pablo Halpern & John Lakos, "Allocators: The Good Parts" (CppCon 2017).
