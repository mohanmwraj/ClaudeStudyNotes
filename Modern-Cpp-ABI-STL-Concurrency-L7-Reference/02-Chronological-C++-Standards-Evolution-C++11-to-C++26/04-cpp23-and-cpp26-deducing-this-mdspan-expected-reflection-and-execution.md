# 04 · C++23 and C++26: deducing `this`, `mdspan`, `expected`, reflection, contracts, and `std::execution`

> **Scope.** C++23 is a "finish C++20" release with a few structural features (deducing `this`, `mdspan`,
> `expected`, `print`, `flat_map`, `generator`, `import std;`). C++26 is the next large one: **static reflection**,
> **contracts**, **`std::execution`** (senders/receivers), hazard pointers and RCU, `inplace_vector`, `hive`,
> linear algebra, `simd`, pack indexing. This file shows what *runs today* on GCC 16.2 and Clang 21.1. GCC 16
> implements reflection and contracts, and both are executed here. Where nothing ships yet, the file says so and
> points to the folder that builds it from scratch.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 2.14 | `deducing_this.cpp` | one accessor for all value categories, CRTP without templates, recursive lambdas, **by-value `self` in registers** | run + asm |
| 2.15 | `expected_cost.cpp` | `std::expected` monadic API; error path ~4–10 ns vs **1.9–3.1 µs per thrown exception** | run, both compilers (timed) |
| 2.16 | `mdspan_demo.cpp` | static vs dynamic extents in the index arithmetic; layouts; how a 24-byte `mdspan` is passed | run + asm |
| 2.17 | `reflection.cpp` | C++26 reflection running: enum→string, generic field printer, `offset_of` | GCC 16.2 `-freflection` run; Clang 21 has no `<meta>` |
| 2.18 | `contracts.cpp` | `pre`/`post`/`contract_assert` under `observe`, `ignore` and `enforce`; custom violation handler | GCC 16.2 runs ×3 |
| 2.19 | `cpp26_misc.cpp` | pack indexing, `= delete("reason")`, structured-binding packs, `_`, saturation arithmetic (renamed!), `inplace_vector`, `function_ref`, constexpr exceptions | run on both, feature-guarded |
| 2.20 | `std_probe.cpp` | 60 feature-test macros for C++17–C++26, per toolchain | run, `-std=c++26` |

**Verification line.** As for files 01–03. C++26 builds use `-std=c++26` (both compilers report `__cplusplus` =
`202400L`, the provisional value for a standard that is not yet published). Reflection needs GCC's `-freflection`.
Contracts use `-fcontracts -fcontract-evaluation-semantic=…`.

---

## 1. What exists today (Listing 2.20)

```cpp
// std_probe.cpp - which C++17/20/23/26 features THIS compiler + standard library report (build with -std=c++26)
#include <version>
#include <cstdio>

#define MACRO_STR(m) #m
#define XSTR(m) MACRO_STR(m)
// An undefined macro stringizes to its own name; a defined one to its value.
static const char* value(const char* name, const char* expanded) {
    const char* a = name;
    const char* b = expanded;
    while (*a && *a == *b) ++a, ++b;
    return (*a == 0 && *b == 0) ? "-" : expanded;
}
#define ROW(since, m) std::printf("  %-5s %-44s %s\n", since, #m, value(#m, XSTR(m)))

int main() {
#if defined(__clang__)
    std::printf("Clang %d.%d + %s, __cplusplus=%s\n", __clang_major__, __clang_minor__,
#else
    std::printf("GCC %d.%d + %s, __cplusplus=%s\n", __GNUC__, __GNUC_MINOR__,
#endif
#if defined(_LIBCPP_VERSION)
                "libc++",
#else
                "libstdc++",
#endif
                XSTR(__cplusplus));
    std::printf("  language:\n");
    ROW("17", __cpp_fold_expressions);
    ROW("17", __cpp_structured_bindings);
    ROW("17", __cpp_if_constexpr);
    ROW("17", __cpp_deduction_guides);
    ROW("20", __cpp_concepts);
    ROW("20", __cpp_impl_coroutine);
    ROW("20", __cpp_impl_three_way_comparison);
    ROW("20", __cpp_consteval);
    ROW("20", __cpp_constinit);
    ROW("20", __cpp_designated_initializers);
    ROW("20", __cpp_modules);
    ROW("23", __cpp_explicit_this_parameter);
    ROW("23", __cpp_multidimensional_subscript);
    ROW("23", __cpp_if_consteval);
    ROW("23", __cpp_static_call_operator);
    ROW("23", __cpp_auto_cast);
    ROW("26", __cpp_pack_indexing);
    ROW("26", __cpp_placeholder_variables);
    ROW("26", __cpp_deleted_function);
    ROW("26", __cpp_structured_bindings);
    ROW("26", __cpp_constexpr_exceptions);
    ROW("26", __cpp_impl_reflection);
    ROW("26", __cpp_contracts);
    ROW("26", __cpp_variadic_friend);
    ROW("26", __cpp_trivial_relocatability);
    std::printf("  library:\n");
    ROW("17", __cpp_lib_memory_resource);
    ROW("17", __cpp_lib_string_view);
    ROW("17", __cpp_lib_variant);
    ROW("17", __cpp_lib_parallel_algorithm);
    ROW("20", __cpp_lib_ranges);
    ROW("20", __cpp_lib_format);
    ROW("20", __cpp_lib_span);
    ROW("20", __cpp_lib_jthread);
    ROW("20", __cpp_lib_atomic_wait);
    ROW("20", __cpp_lib_chrono);
    ROW("23", __cpp_lib_expected);
    ROW("23", __cpp_lib_mdspan);
    ROW("23", __cpp_lib_print);
    ROW("23", __cpp_lib_flat_map);
    ROW("23", __cpp_lib_generator);
    ROW("23", __cpp_lib_stacktrace);
    ROW("23", __cpp_lib_move_only_function);
    ROW("23", __cpp_lib_ranges_zip);
    ROW("23", __cpp_lib_ranges_enumerate);
    ROW("26", __cpp_lib_inplace_vector);
    ROW("26", __cpp_lib_hive);
    ROW("26", __cpp_lib_senders);
    ROW("26", __cpp_lib_hazard_pointer);
    ROW("26", __cpp_lib_rcu);
    ROW("26", __cpp_lib_function_ref);
    ROW("26", __cpp_lib_copyable_function);
    ROW("26", __cpp_lib_reflection);
    ROW("26", __cpp_lib_linalg);
    ROW("26", __cpp_lib_submdspan);
    ROW("26", __cpp_lib_saturation_arithmetic);
    ROW("26", __cpp_lib_text_encoding);
    ROW("26", __cpp_lib_debugging);
    ROW("26", __cpp_lib_simd);
    ROW("26", __cpp_lib_optional_range_support);
    ROW("26", __cpp_lib_contracts);
}
```

GCC 16.2 + libstdc++:

```text
GCC 16.2 + libstdc++, __cplusplus=202400L
  language:
  17    __cpp_fold_expressions                       201603L
  17    __cpp_structured_bindings                    202411L
  17    __cpp_if_constexpr                           201606L
  17    __cpp_deduction_guides                       202207L
  20    __cpp_concepts                               202002L
  20    __cpp_impl_coroutine                         201902L
  20    __cpp_impl_three_way_comparison              201907L
  20    __cpp_consteval                              202211L
  20    __cpp_constinit                              201907L
  20    __cpp_designated_initializers                201707L
  20    __cpp_modules                                -
  23    __cpp_explicit_this_parameter                202110L
  23    __cpp_multidimensional_subscript             202211L
  23    __cpp_if_consteval                           202106L
  23    __cpp_static_call_operator                   202207L
  23    __cpp_auto_cast                              202110L
  26    __cpp_pack_indexing                          202311L
  26    __cpp_placeholder_variables                  202306L
  26    __cpp_deleted_function                       202403L
  26    __cpp_structured_bindings                    202411L
  26    __cpp_constexpr_exceptions                   202411L
  26    __cpp_impl_reflection                        -
  26    __cpp_contracts                              202502L
  26    __cpp_variadic_friend                        202403L
  26    __cpp_trivial_relocatability                 -
  library:
  17    __cpp_lib_memory_resource                    201603L
  17    __cpp_lib_string_view                        202403L
  17    __cpp_lib_variant                            202306L
  17    __cpp_lib_parallel_algorithm                 201603L
  20    __cpp_lib_ranges                             202406L
  20    __cpp_lib_format                             202603L
  20    __cpp_lib_span                               202311L
  20    __cpp_lib_jthread                            201911L
  20    __cpp_lib_atomic_wait                        201907L
  20    __cpp_lib_chrono                             202306L
  23    __cpp_lib_expected                           202211L
  23    __cpp_lib_mdspan                             202406L
  23    __cpp_lib_print                              202406L
  23    __cpp_lib_flat_map                           202511L
  23    __cpp_lib_generator                          202207L
  23    __cpp_lib_stacktrace                         -
  23    __cpp_lib_move_only_function                 202110L
  23    __cpp_lib_ranges_zip                         202110L
  23    __cpp_lib_ranges_enumerate                   202302L
  26    __cpp_lib_inplace_vector                     202603L
  26    __cpp_lib_hive                               -
  26    __cpp_lib_senders                            -
  26    __cpp_lib_hazard_pointer                     -
  26    __cpp_lib_rcu                                -
  26    __cpp_lib_function_ref                       202603L
  26    __cpp_lib_copyable_function                  202306L
  26    __cpp_lib_reflection                         -
  26    __cpp_lib_linalg                             -
  26    __cpp_lib_submdspan                          202603L
  26    __cpp_lib_saturation_arithmetic              202603L
  26    __cpp_lib_text_encoding                      -
  26    __cpp_lib_debugging                          202403L
  26    __cpp_lib_simd                               -
  26    __cpp_lib_optional_range_support             202406L
  26    __cpp_lib_contracts                          202502L
```

Clang 21.1 + libc++:

```text
Clang 21.1 + libc++, __cplusplus=202400L
  language:
  17    __cpp_fold_expressions                       201603L
  17    __cpp_structured_bindings                    202411L
  17    __cpp_if_constexpr                           201606L
  17    __cpp_deduction_guides                       201703L
  20    __cpp_concepts                               202002
  20    __cpp_impl_coroutine                         201902L
  20    __cpp_impl_three_way_comparison              201907L
  20    __cpp_consteval                              202211L
  20    __cpp_constinit                              201907L
  20    __cpp_designated_initializers                201707L
  20    __cpp_modules                                -
  23    __cpp_explicit_this_parameter                202110L
  23    __cpp_multidimensional_subscript             202211L
  23    __cpp_if_consteval                           202106L
  23    __cpp_static_call_operator                   202207L
  23    __cpp_auto_cast                              202110L
  26    __cpp_pack_indexing                          202311L
  26    __cpp_placeholder_variables                  202306L
  26    __cpp_deleted_function                       202403L
  26    __cpp_structured_bindings                    202411L
  26    __cpp_constexpr_exceptions                   -
  26    __cpp_impl_reflection                        -
  26    __cpp_contracts                              -
  26    __cpp_variadic_friend                        202403L
  26    __cpp_trivial_relocatability                 -
  library:
  17    __cpp_lib_memory_resource                    201603L
  17    __cpp_lib_string_view                        202403L
  17    __cpp_lib_variant                            202306L
  17    __cpp_lib_parallel_algorithm                 -
  20    __cpp_lib_ranges                             202406L
  20    __cpp_lib_format                             202110L
  20    __cpp_lib_span                               202002L
  20    __cpp_lib_jthread                            201911L
  20    __cpp_lib_atomic_wait                        201907L
  20    __cpp_lib_chrono                             201611L
  23    __cpp_lib_expected                           202211L
  23    __cpp_lib_mdspan                             202406L
  23    __cpp_lib_print                              202207L
  23    __cpp_lib_flat_map                           202207L
  23    __cpp_lib_generator                          -
  23    __cpp_lib_stacktrace                         -
  23    __cpp_lib_move_only_function                 -
  23    __cpp_lib_ranges_zip                         -
  23    __cpp_lib_ranges_enumerate                   -
  26    __cpp_lib_inplace_vector                     -
  26    __cpp_lib_hive                               -
  26    __cpp_lib_senders                            -
  26    __cpp_lib_hazard_pointer                     -
  26    __cpp_lib_rcu                                -
  26    __cpp_lib_function_ref                       -
  26    __cpp_lib_copyable_function                  -
  26    __cpp_lib_reflection                         -
  26    __cpp_lib_linalg                             -
  26    __cpp_lib_submdspan                          -
  26    __cpp_lib_saturation_arithmetic              202311L
  26    __cpp_lib_text_encoding                      -
  26    __cpp_lib_debugging                          -
  26    __cpp_lib_simd                               -
  26    __cpp_lib_optional_range_support             -
  26    __cpp_lib_contracts                          -
```

Reading the two columns:

* **GCC 16.2 is far ahead on C++26.** It has contracts (`__cpp_contracts` 202502L), constexpr exceptions,
  `inplace_vector`, `function_ref`, `copyable_function`, `submdspan`, `<debugging>`, optional-as-range, and, with
  `-freflection`, static reflection (`__cpp_impl_reflection` 202603L; the probe above was built without the flag).
* **Nobody ships `hive`, `std::execution` (`__cpp_lib_senders`), hazard pointers, RCU, `linalg` or `simd`** in
  these two libraries. Folder 09 builds hazard pointers and RCU, and Folder 10 builds a sender/receiver core.
* Several values carry **2025–2026 dates** (`format` 202603L, `flat_map` 202511L, `saturation_arithmetic`
  202603L). The draft keeps changing after features land, and libstdc++ tracks the changes. Listing 2.19 shows one
  rename that breaks portable code.
* Neither compiler defines `__cpp_modules`, although both build modules (file 03).

---

## 2. First principles and listings

### 2.1 Deducing `this` (Listing 2.14)

```cpp
// deducing_this.cpp - C++23 explicit object parameters: one accessor for all cv/ref, recursive lambdas, by-value self
#include <print>
#include <string>
#include <utility>
#include <vector>

struct Buffer {
    std::vector<int> data{1, 2, 3};
    // One template replaces four overloads (&, const&, &&, const&&) and forwards the object's value category.
    template <class Self>
    auto&& items(this Self&& self) { return std::forward<Self>(self).data; }
};

// CRTP without the template parameter on the base: 'self' already has the derived type.
struct Printable {
    void print(this const auto& self) { std::println("{}", self.describe()); }
};
struct Point : Printable {
    int x = 1, y = 2;
    std::string describe() const { return "Point(" + std::to_string(x) + ", " + std::to_string(y) + ")"; }
};

// By-value self: a small trivially copyable object travels in registers (compare get_ref below).
struct Pair2 {
    long a, b;
    long sum_ref() const { return a + b; }             // implicit 'this': a pointer, two loads
    long sum_val(this Pair2 p) { return p.a + p.b; }   // the object itself: RDI:RSI / X0:X1
};
long call_ref(const Pair2& p) { return p.sum_ref(); }
long call_val(Pair2 p) { return p.sum_val(); }

int main() {
    Buffer b;
    const Buffer& cb = b;
    static_assert(std::is_same_v<decltype(b.items()), std::vector<int>&>);
    static_assert(std::is_same_v<decltype(cb.items()), const std::vector<int>&>);
    static_assert(std::is_same_v<decltype(std::move(b).items()), std::vector<int>&&>);
    std::vector<int> stolen = std::move(b).items();    // moves out of an rvalue Buffer
    std::println("moved {} elements; source now holds {}", stolen.size(), b.data.size());

    Point{}.print();

    // A recursive lambda without std::function or a Y-combinator: the lambda receives itself.
    auto fib = [](this auto const& self, int n) -> long { return n < 2 ? n : self(n - 1) + self(n - 2); };
    std::println("fib(20) = {}", fib(20));
}
```

Output (verified, both compilers):

```text
moved 3 elements; source now holds 0
Point(1, 2)
fib(20) = 6765
```

Clang `-O3`, x86-64 then AArch64:

```asm
_Z8call_refRK5Pair2:               # call_ref(Pair2 const&)
	movq	8(%rdi), %rax
	addq	(%rdi), %rax
	retq

_Z8call_val5Pair2:                 # call_val(Pair2)
	leaq	(%rdi,%rsi), %rax
	retq
```

```asm
_Z8call_refRK5Pair2:               // call_ref(Pair2 const&)
	ldp	x8, x9, [x0]
	add	x0, x9, x8
	ret

_Z8call_val5Pair2:                 // call_val(Pair2)
	add	x0, x0, x1
	ret
```

* **`this Self&& self`** makes the object parameter a *deduced template parameter*: one function replaces the four
  `&`/`const&`/`&&`/`const&&` overloads, and `std::forward<Self>(self).data` moves out of rvalues (the
  `static_assert`s and "moved 3 elements").
* **CRTP without the template parameter on the base.** `Printable::print(this const auto& self)` sees the derived
  type directly. Folder 06 file 03 compares it with classic CRTP.
* **Recursive lambdas** receive themselves as `self`: no `std::function` (which allocates and type-erases) and no
  Y-combinator.
* **By-value `self` changes the ABI.** `sum_val(this Pair2 p)` receives the 16-byte object **in two registers**
  (`lea (%rdi,%rsi)` / `add x0, x0, x1`). `sum_ref() const` receives a pointer and loads both fields. For small
  value types, a by-value explicit object parameter removes a memory round-trip at non-inlined call sites
  (Folder 01, file 02, §1.4). Explicit-object member functions cannot be `virtual` (Folder 01, file 01).

### 2.2 `std::expected` and the cost of the error path (Listing 2.15)

```cpp
// expected_cost.cpp - C++23 std::expected vs exceptions: the error path measured, the monadic API shown
#include <cstdint>
#include <charconv>
#include <chrono>
#include <expected>
#include <print>
#include <stdexcept>
#include <string>
#include <string_view>
#include <system_error>
#include <vector>

enum class ParseError { empty, not_a_number, out_of_range };

std::expected<int, ParseError> parse_expected(std::string_view s) {
    if (s.empty()) return std::unexpected(ParseError::empty);
    int v = 0;
    auto [p, ec] = std::from_chars(s.data(), s.data() + s.size(), v);
    if (ec == std::errc::result_out_of_range) return std::unexpected(ParseError::out_of_range);
    if (ec != std::errc{} || p != s.data() + s.size()) return std::unexpected(ParseError::not_a_number);
    return v;
}

int parse_throwing(std::string_view s) {
    auto r = parse_expected(s);
    if (!r) throw std::invalid_argument("bad integer");
    return *r;
}

// Monadic composition (C++23): and_then / transform / or_else, no if-ladder.
std::expected<int, ParseError> parse_port(std::string_view s) {
    return parse_expected(s)
        .and_then([](int v) -> std::expected<int, ParseError> {
            if (v < 1 || v > 65535) return std::unexpected(ParseError::out_of_range);
            return v;
        })
        .transform([](int v) { return v; });
}

template <class F>
double bench_ns(const std::vector<std::string>& in, F f) {
    auto t0 = std::chrono::steady_clock::now();
    std::int64_t sink = 0;
    for (int r = 0; r < 20; ++r)
        for (const auto& s : in) sink += f(s);
    auto t1 = std::chrono::steady_clock::now();
    if (sink == 42) std::println("");
    return std::chrono::duration<double, std::nano>(t1 - t0).count() / (20.0 * static_cast<double>(in.size()));
}

int main() {
    std::println("parse_port(\"8080\")={} parse_port(\"99999\") error={} parse_port(\"x\") error={}", *parse_port("8080"),
                 static_cast<int>(parse_port("99999").error()), static_cast<int>(parse_port("x").error()));
    for (int bad_percent : {0, 1, 10, 50}) {
        std::vector<std::string> in;
        for (int i = 0; i < 20000; ++i) in.push_back(i % 100 < bad_percent ? "oops" : std::to_string(i));
        double e = bench_ns(in, [](const std::string& s) { return parse_expected(s).value_or(0); });
        double x = bench_ns(in, [](const std::string& s) {
            try {
                return parse_throwing(s);
            } catch (const std::invalid_argument&) {
                return 0;
            }
        });
        std::println("  {:>2}% bad inputs: expected {:7.1f} ns/call   exceptions {:8.1f} ns/call", bad_percent, e, x);
    }
}
```

GCC 16.2 (one run):

```text
parse_port("8080")=8080 parse_port("99999") error=2 parse_port("x") error=1
   0% bad inputs: expected     4.5 ns/call   exceptions     11.6 ns/call
   1% bad inputs: expected     4.6 ns/call   exceptions     35.8 ns/call
  10% bad inputs: expected     4.7 ns/call   exceptions    235.0 ns/call
  50% bad inputs: expected     3.7 ns/call   exceptions   1106.6 ns/call
```

Clang 21.1 (one run):

```text
parse_port("8080")=8080 parse_port("99999") error=2 parse_port("x") error=1
   0% bad inputs: expected     9.7 ns/call   exceptions     10.6 ns/call
   1% bad inputs: expected     9.4 ns/call   exceptions     40.2 ns/call
  10% bad inputs: expected     9.8 ns/call   exceptions    304.1 ns/call
  50% bad inputs: expected     7.9 ns/call   exceptions   1562.0 ns/call
```

The exception column is linear in the failure rate. From the 50% row, each thrown and caught exception costs about
**(1107 − 4) / 0.5 ≈ 2.2 µs** on GCC and **(1562 − 8) / 0.5 ≈ 3.1 µs** on Clang in the run shown (1.9 µs and 3.0 µs in an earlier run). That covers allocating the
exception, two-phase unwinding through the tables, `catch` matching (RTTI, Folder 01) and destruction. The
`expected` error path costs the same as the success path. At 0% failure both are within a few nanoseconds of each
other: the Itanium zero-cost model really is close to free when nothing throws (Folder 01, file 02, §1.6).

The design rule this supports: **exceptions for exceptional, unrecoverable-locally failures; `expected` for
failures that are part of normal control flow** (parsing, lookups, validation), and especially for anything that
can be triggered by untrusted input at high rates, where exceptions are also a denial-of-service lever.

### 2.3 `std::mdspan` (Listing 2.16)

```cpp
// mdspan_demo.cpp - C++23 std::mdspan: a non-owning multidimensional view; layouts; static vs dynamic extents
#include <cstddef>
#include <mdspan>
#include <print>
#include <vector>

using std::size_t;

// Static extents are part of the type: the index computation folds to constants.
using Mat3x4 = std::mdspan<float, std::extents<size_t, 3, 4>>;
// Dynamic extents are stored in the mdspan (one size_t per dynamic dimension).
using MatXY = std::mdspan<float, std::dextents<size_t, 2>>;
// Column-major view of the same memory.
using MatCol = std::mdspan<float, std::dextents<size_t, 2>, std::layout_left>;

float trace(MatXY m) {
    float t = 0;
    for (size_t i = 0; i < m.extent(0) && i < m.extent(1); ++i) t += m[i, i];  // C++23 multidimensional []
    return t;
}
float at_static(Mat3x4 m, size_t i, size_t j) { return m[i, j]; }  // i*4 + j, 4 is a constant
float at_dynamic(MatXY m, size_t i, size_t j) { return m[i, j]; } // i*extent(1) + j

int main() {
    std::vector<float> buf(12);
    for (size_t k = 0; k < buf.size(); ++k) buf[k] = static_cast<float>(k);
    Mat3x4 a(buf.data());
    MatXY b(buf.data(), 3, 4);
    MatCol c(buf.data(), 3, 4);
    std::println("sizeof: static 3x4 mdspan={} dynamic 2-D mdspan={} (pointer + extents)", sizeof(a), sizeof(b));
    std::println("row-major a[1,2]={} b[1,2]={}   column-major c[1,2]={}", a[1, 2], b[1, 2], c[1, 2]);
    std::println("trace(b)={} required_span_size={}", trace(b), b.mapping().required_span_size());
}
```

Output (verified, both compilers):

```text
sizeof: static 3x4 mdspan=8 dynamic 2-D mdspan=24 (pointer + extents)
row-major a[1,2]=6 b[1,2]=6   column-major c[1,2]=7
trace(b)=15 required_span_size=12
```

Clang `-O3`, x86-64 then AArch64:

```asm
_Z9at_staticNSt3__16mdspanIfNS_7extentsImJLm3ELm4EEEENS_12layout_rightENS_16default_accessorIfEEEEmm: # at_static(std::__1::mdspan<float, std::__1::extents<unsigned long, 3ul, 4ul>, std::__1::layout_right, std::__1::default_accessor<float> >, unsigned long, unsigned long)
	leaq	(%rdi,%rdx,4), %rax
	shlq	$4, %rsi
	movss	(%rsi,%rax), %xmm0
	retq

_Z10at_dynamicNSt3__16mdspanIfNS_7extentsImJLm18446744073709551615ELm18446744073709551615EEEENS_12layout_rightENS_16default_accessorIfEEEEmm: # at_dynamic(std::__1::mdspan<float, std::__1::extents<unsigned long, 18446744073709551615ul, 18446744073709551615ul>, std::__1::layout_right, std::__1::default_accessor<float> >, unsigned long, unsigned long)
	imulq	24(%rsp), %rdi
	shlq	$2, %rdi
	addq	8(%rsp), %rdi
	movss	(%rdi,%rsi,4), %xmm0
	retq
```

```asm
_Z9at_staticNSt3__16mdspanIfNS_7extentsImJLm3ELm4EEEENS_12layout_rightENS_16default_accessorIfEEEEmm: // at_static(std::__1::mdspan<float, std::__1::extents<unsigned long, 3ul, 4ul>, std::__1::layout_right, std::__1::default_accessor<float> >, unsigned long, unsigned long)
	add	x8, x0, x2, lsl #2
	lsl	x9, x1, #4
	ldr	s0, [x8, x9]
	ret

_Z10at_dynamicNSt3__16mdspanIfNS_7extentsImJLm18446744073709551615ELm18446744073709551615EEEENS_12layout_rightENS_16default_accessorIfEEEEmm: // at_dynamic(std::__1::mdspan<float, std::__1::extents<unsigned long, 18446744073709551615ul, 18446744073709551615ul>, std::__1::layout_right, std::__1::default_accessor<float> >, unsigned long, unsigned long)
	ldr	x8, [x0, #16]
	ldr	x9, [x0]
	mul	x8, x8, x1
	add	x8, x9, x8, lsl #2
	ldr	s0, [x8, x2, lsl #2]
	ret
```

* A static-extent `mdspan` is just a pointer (8 bytes). The row stride 4 is a constant, so indexing is
  `shlq $4` (×16 bytes = 4 floats). A dynamic 2-D `mdspan` is 24 bytes: pointer + two extents. The stride
  is loaded and multiplied.
* **How the 24-byte object travels:** it is larger than 16 bytes, so on x86-64 SysV it is passed in memory on the
  stack (`imulq 24(%rsp)`, `addq 8(%rsp)`), and on AArch64 by reference (`ldr x8, [x0, #16]`). Hot kernels should
  take static extents where the shape is known, or pass the data pointer and extents separately.
* `layout_left` (column-major, Fortran/BLAS order) over the same memory gives `c[1,2] = 7` vs row-major `6`. The
  layout is a policy type, so the same algorithm works for both. `submdspan` (C++26) slices views and is in
  libstdc++ 16, but not in libc++ 21.

### 2.4 Static reflection: running C++26 code (Listing 2.17)

```cpp
// reflection.cpp - C++26 static reflection (P2996): ^^ reflects, [: :] splices, std::meta queries (GCC 16 -freflection)
#include <meta>
#include <print>
#include <string>
#include <string_view>

enum class Color { red, green, blue };

// enum -> string without macros or tables: iterate the enumerators at compile time.
template <class E>
    requires std::is_enum_v<E>
constexpr std::string_view to_string(E value) {
    template for (constexpr auto e : std::define_static_array(std::meta::enumerators_of(^^E))) {
        if (value == [:e:]) return std::meta::identifier_of(e);
    }
    return "<unknown>";
}

struct Order {
    int id;
    double price;
    std::string symbol;
};

// A generic printer: one function for every aggregate, driven by its members.
template <class T>
void print_fields(const T& obj) {
    constexpr auto ctx = std::meta::access_context::unchecked();
    std::print("{} {{", std::meta::identifier_of(^^T));
    template for (constexpr auto m : std::define_static_array(std::meta::nonstatic_data_members_of(^^T, ctx))) {
        std::print(" {}={}", std::meta::identifier_of(m), obj.[:m:]);
    }
    std::println(" }}");
}

constexpr std::size_t member_count = std::meta::nonstatic_data_members_of(^^Order,
                                                                          std::meta::access_context::unchecked()).size();
static_assert(member_count == 3);
static_assert(std::meta::identifier_of(^^Order) == "Order");

int main() {
    std::println("to_string(Color::green) = {}", to_string(Color::green));
    print_fields(Order{42, 101.25, "ACME"});
    std::println("Order has {} non-static data members; offset of 'price' = {} bytes", member_count,
                 std::meta::offset_of(std::meta::nonstatic_data_members_of(^^Order,
                                                                            std::meta::access_context::unchecked())[1])
                     .bytes);
}
```

GCC 16.2, `-std=c++26 -freflection` (verified):

```text
to_string(Color::green) = green
Order { id=42 price=101.25 symbol=ACME }
Order has 3 non-static data members; offset of 'price' = 8 bytes
```

Without `-freflection` (GCC), and on Clang 21.1:

```text
77 lines of diagnostics, 24 'error:' lines; first:
  reflection.cpp:13:43: error: 'define_static_array' is not a member of 'std' [-Wtemplate-body]
4 lines of diagnostics, 1 'error:' lines; first:
  reflection.cpp:2:10: fatal error: 'meta' file not found
```

The model (P2996R13, adopted for C++26 in June 2025):

* `^^X` produces a value of type `std::meta::info` that *represents* an entity (type, member, enumerator,
  namespace). Values of that type exist only at compile time.
* `std::meta::` functions query them (`enumerators_of`, `nonstatic_data_members_of`, `identifier_of`,
  `offset_of`). These are ordinary `consteval` functions over `info` values.
* `[: r :]` **splices** a reflection back into code: `[:e:]` is the enumerator, and `obj.[:m:]` is a member
  access.
* `template for` (expansion statements, P1306) iterates at compile time over a range of reflections, producing one
  copy of the body per element. `std::define_static_array` turns a compile-time `vector<info>` into a
  static array that `template for` can iterate.
* `access_context::unchecked()` makes the query ignore access control. Reflection respects `private` by default,
  which is a deliberate design choice after review.

What this replaces: enum-to-string macro tables, hand-maintained serializers, `BOOST_DESCRIBE`/`magic_enum` style
tricks, protobuf-style code generators for in-process use. Folder 06 file 04 builds more on it.

### 2.5 Contracts (Listing 2.18)

```cpp
// contracts.cpp - C++26 contracts (P2900): pre, post, contract_assert, evaluation semantics, a custom handler
// GCC 16; the evaluation semantic is chosen at build time: -fcontract-evaluation-semantic=enforce|observe|ignore
#include <contracts>
#include <cstdio>

// Replaceable violation handler: called on a failed check under 'enforce' and 'observe'.
void handle_contract_violation(const std::contracts::contract_violation& v) {
    std::printf("  violation: kind=%d semantic=%d comment=\"%s\" line=%u\n", static_cast<int>(v.kind()),
                static_cast<int>(v.semantic()), v.comment(), v.location().line());
    std::fflush(stdout);               // under 'enforce' the program terminates right after this returns
}

// P2900 rule: a by-value parameter named in a postcondition must be const (the body cannot change what
// the postcondition talks about).
int checked_div(const int a, const int b)
    pre(b != 0)                        // checked on entry (caller-visible precondition)
    post(r : r * b <= a)               // checked on exit; 'r' names the return value
{
    return a / b;
}

int clamp_index(int i, int n) {
    contract_assert(n > 0);            // an assertion statement, replaces assert()
    return i < 0 ? 0 : (i >= n ? n - 1 : i);
}

int main() {
    std::printf("checked_div(10, 3) = %d\n", checked_div(10, 3));
    std::printf("clamp_index(5, 0):\n");
    int r = clamp_index(5, 0);         // violates contract_assert(n > 0)
    std::printf("  returned %d (only reached if the semantic did not terminate)\n", r);
    std::printf("checked_div(1, 0):\n");
    int volatile zero = 0;
    if (zero == 1) std::printf("%d\n", checked_div(1, zero));  // not executed: shows the call site only
    std::printf("done\n");
}
```

GCC 16.2 with `-fcontract-evaluation-semantic=observe`, `=ignore`, `=enforce` (verified; under `enforce` the
process terminates after the handler returns, exit code 0xC0000409, the UCRT fast-fail used by `abort`):

```text
observe:
checked_div(10, 3) = 3
clamp_index(5, 0):
  violation: kind=3 semantic=2 comment="n > 0" line=23
  returned -1 (only reached if the semantic did not terminate)
checked_div(1, 0):
done
```

```text
ignore:
checked_div(10, 3) = 3
clamp_index(5, 0):
  returned -1 (only reached if the semantic did not terminate)
checked_div(1, 0):
done
```

```text
enforce:
checked_div(10, 3) = 3
clamp_index(5, 0):
  violation: kind=3 semantic=3 comment="n > 0" line=23
```

* **`pre`/`post`** belong to the function declaration, so callers and tools see them. `post(r : …)` names the result.
  **A by-value parameter used in a postcondition must be `const`.** The first build failed with "a value parameter
  used in a postcondition must be const", which is the P2900 rule that stops the body from changing what the
  postcondition describes.
* **The evaluation semantic is a build/link-time choice, not a source choice:** `ignore` (not evaluated), `observe`
  (handler called, execution continues; here `clamp_index` returned −1 for `n = 0`), `enforce` (handler, then
  termination), `quick_enforce` (terminate without the handler). One binary can mix semantics across TUs.
* **The violation handler is replaceable** (`handle_contract_violation`) and receives the kind (`kind=3` is
  `contract_assert`), the semantic, the source text and the location.
* Contracts do not replace input validation. `observe` and `ignore` exist, so a contract can be off in some build.
  Untrusted-input checks stay as code that always runs.

### 2.6 The rest of C++26 that runs today (Listing 2.19)

```cpp
// cpp26_misc.cpp - C++26 features available today, each behind its feature-test macro (build with -std=c++26)
#include <version>
#include <cstdint>
#include <numeric>
#include <print>
#include <stdexcept>
#include <tuple>
#if __cpp_lib_inplace_vector
#include <inplace_vector>
#endif
#if __cpp_lib_function_ref
#include <functional>
#endif

// P2662 pack indexing: Ts...[I] / v...[I] without recursion or std::tuple.
template <std::size_t I, class... Ts>
constexpr auto nth(Ts... v) -> Ts...[I] { return v...[I]; }
static_assert(nth<1>(10, 'x', 3.5) == 'x');

// P2573 = delete("reason"): the reason appears in the diagnostic.
void legacy_api(int) = delete("use legacy_api(std::int64_t): 32-bit ids overflowed in 2024");
void legacy_api(std::int64_t) {}

// P1061 structured bindings can introduce a pack (in a template).
template <class Tuple>
constexpr auto sum_all(const Tuple& t) {
    auto [... xs] = t;
    return (xs + ... + 0);
}
static_assert(sum_all(std::tuple{1, 2, 3, 4}) == 10);

#if __cpp_constexpr_exceptions
// P3068 constexpr exceptions: throw and catch during constant evaluation.
constexpr int checked_ratio(int a, int b) {
    try {
        if (b == 0) throw std::domain_error("b == 0");
        return a / b;
    } catch (const std::domain_error&) {
        return -1;
    }
}
static_assert(checked_ratio(6, 3) == 2 && checked_ratio(1, 0) == -1);
#endif

int main() {
    int _ = 1;                         // P2169: '_' is a placeholder that may be declared again...
    int _ = 2;                         // ...in the same scope (but then it can no longer be named)
    auto [_, second] = std::pair{1, 2};
    std::println("pack indexing: nth<2>(10, 'x', 3.5) = {}; structured-binding pack sum = {}; second = {}",
                 nth<2>(10, 'x', 3.5), sum_all(std::tuple{1, 2, 3, 4}), second);
#if __cpp_lib_saturation_arithmetic >= 202603L      // 2026 draft: renamed to saturating_add/sub/mul/div/cast
    std::println("saturation (saturating_*): add(200, 100) as uint8_t = {}, sub(-100, 100) as int8_t = {}",
                 std::saturating_add<std::uint8_t>(200, 100), std::saturating_sub<std::int8_t>(-100, 100));
#elif __cpp_lib_saturation_arithmetic                  // P0543 (2023) names
    std::println("saturation (add_sat/sub_sat): add(200, 100) as uint8_t = {}, sub(-100, 100) as int8_t = {}",
                 std::add_sat<std::uint8_t>(200, 100), std::sub_sat<std::int8_t>(-100, 100));
#endif
#if __cpp_lib_inplace_vector
    std::inplace_vector<int, 4> iv{1, 2, 3};
    iv.push_back(4);
    // try_push_back returns optional<T&> in libstdc++ 16 (later C++26 wording; P0843 had T*): test it as bool
    std::println("inplace_vector<int,4>: size={} capacity={} sizeof={} try_push_back(5) -> {}", iv.size(),
                 iv.capacity(), sizeof(iv), iv.try_push_back(5) ? "pushed" : "empty result (full)");
#else
    std::println("inplace_vector: not in this standard library");
#endif
#if __cpp_lib_function_ref
    auto twice = [](int x) { return 2 * x; };
    std::function_ref<int(int)> fr = twice;     // non-owning, two pointers, never allocates
    std::println("function_ref: fr(21) = {}, sizeof = {}", fr(21), sizeof(fr));
#else
    std::println("function_ref: not in this standard library");
#endif
#if __cpp_constexpr_exceptions
    std::println("constexpr exceptions: checked_ratio(1, 0) evaluated at compile time = {}", checked_ratio(1, 0));
#else
    std::println("constexpr exceptions: not in this compiler");
#endif
#ifdef SHOW_DELETED_REASON
    legacy_api(7);
#endif
}
```

GCC 16.2 + libstdc++:

```text
pack indexing: nth<2>(10, 'x', 3.5) = 3.5; structured-binding pack sum = 10; second = 2
saturation (saturating_*): add(200, 100) as uint8_t = 255, sub(-100, 100) as int8_t = -128
inplace_vector<int,4>: size=4 capacity=4 sizeof=20 try_push_back(5) -> empty result (full)
function_ref: fr(21) = 42, sizeof = 16
constexpr exceptions: checked_ratio(1, 0) evaluated at compile time = -1
```

Clang 21.1 + libc++:

```text
pack indexing: nth<2>(10, 'x', 3.5) = 3.5; structured-binding pack sum = 10; second = 2
saturation (add_sat/sub_sat): add(200, 100) as uint8_t = 255, sub(-100, 100) as int8_t = -128
inplace_vector: not in this standard library
function_ref: not in this standard library
constexpr exceptions: not in this compiler
```

`= delete("reason")` (GCC, then Clang):

```text
cpp26_misc.cpp:80:15: error: use of deleted function 'void legacy_api(int)': use legacy_api(std::int64_t): 32-bit ids overflowed in 2024
cpp26_misc.cpp:80:5: error: call to deleted function 'legacy_api': use legacy_api(std::int64_t): 32-bit ids overflowed in 2024
```

Things I found while writing this listing:

* **Saturation arithmetic was renamed.** libc++ 21 implements P0543's `std::add_sat`/`sub_sat` (`202311L`).
  libstdc++ 16 has only `std::saturating_add`/`saturating_sub`/`saturating_mul`/`saturating_div`/`saturating_cast`
  (`202603L`), following a 2026 change to the draft. Portable code must branch on the macro value, as the listing
  does.
* **`inplace_vector::try_push_back` returns `optional<T&>` in libstdc++ 16**, not the `T*` of the original
  proposal. The listing tests the result as a boolean, which works for both.
* `inplace_vector<int, 4>` is 20 bytes: inline storage for 4 ints plus a size, no heap, ever. `function_ref` is 16
  bytes (an object pointer + a thunk pointer) and never allocates, unlike `std::function` (Folder 04).
* Pack indexing (`Ts...[I]`), structured-binding packs (`auto [... xs] = t;`), the `_` placeholder (two `int _`
  declarations in one scope) and `= delete("reason")` work on **both** compilers.

### 2.7 `std::execution` (P2300): the model, and why it is not here yet

`std::execution` was voted into C++26 (St. Louis, June 2024). The probe shows that **neither standard library ships
it** (`__cpp_lib_senders` undefined). The reference implementation is NVIDIA's `stdexec`. The model in one diagram:

```text
  sender  = a description of work (lazy, a value type, nothing runs)
  receiver = where the results go: set_value(...) | set_error(e) | set_stopped()
  connect(sender, receiver) -> operation_state   (an object that holds ALL the state, often on the stack)
  start(op)                  -> work begins; completion calls exactly one receiver channel

  auto work = schedule(pool.get_scheduler())           // sender
            | then([] { return parse(); })              // sender adaptor: no allocation, no type erasure
            | then([](Msg m) { return route(m); });
  auto [result] = sync_wait(std::move(work)).value();   // connect + start + block for the result
```

The point relative to `std::future::then` (Concurrency TS) is structural. A future chain allocates a shared state
per step and synchronizes on each handoff with a mutex or atomics. A sender chain is **one nested type** whose
operation state the compiler lays out in advance: no allocation, no type erasure, and no synchronization between
steps that run on the same execution agent. Cancellation (`stop_token`) and error channels are part of the
protocol. Folder 10 file 04 implements `just`, `then`, `schedule` and `sync_wait` from scratch and counts the
allocations against a promise/future chain.

---

## 3. Evolution table: C++23 and C++26 at a glance

| Area | C++23 | C++26 | GCC 16.2 / Clang 21.1 here |
|---|---|---|---|
| object parameter | deducing `this` (P0847R7) | — | both |
| error handling | `std::expected` (P0323R12) + monadic `optional` | constexpr exceptions (P3068) | both / GCC only |
| contracts | — | P2900R14 | GCC 16 |
| reflection | — | P2996R13, expansion statements P1306 | GCC 16 (`-freflection`) |
| arrays | `mdspan` (P0009R18) | `submdspan` (P2630), `linalg` (P1673) | both / GCC / neither |
| containers | `flat_map`/`flat_set` (P0429, P1222) | `inplace_vector` (P0843), `hive` (P0447) | both / GCC / neither |
| callables | `move_only_function` (P0288) | `copyable_function` (P2548), `function_ref` (P0792) | GCC (libc++ 21: none of the three) |
| output | `std::print` (P2093) | — | both |
| coroutines | `std::generator` (P2502) | `std::execution` task (P3552) | GCC / neither |
| concurrency | — | `std::execution` (P2300R10), hazard pointers (P2530), RCU (P2545) | neither |
| SIMD | — | `std::simd` (P1928) | neither |
| packs | — | pack indexing (P2662), structured-binding packs (P1061) | both |
| misc language | `if consteval`, `auto(x)`, `static operator()`, multidim `[]` | `_` placeholder (P2169), `= delete("…")` (P2573), variadic friends | both |
| arithmetic | — | saturation arithmetic (P0543; renamed in 2026 drafts) | both, **different names** |
| relocation | — | trivial relocatability (P2786): **removed** (P3920) | Clang only (pre-removal) |

---

## 4. Production blueprints

### 4.1 Error handling policy

| Subtle buggy way | Production-hardened way |
|---|---|
| `throw` on malformed client input in a request parser | return `std::expected<T, ParseError>`; 1.9–3.1 µs per exception is a DoS lever |
| `expected` everywhere, including OOM and invariant violations | exceptions (or termination) for the truly exceptional; contracts for programming errors |
| `.value()` on an `expected` without checking | `and_then`/`transform`/`or_else`, or check `has_value()`; `.value()` throws `bad_expected_access` |
| `assert()` that disappears in release builds | `contract_assert` with an explicit evaluation semantic per build (where available) |

### 4.2 Adopting C++26 features before every compiler has them

Gate every use on the **feature-test macro and its value** (saturation arithmetic shows that the name can change
between values), keep a fallback path, and build CI with both compilers. Reflection and contracts are GCC-only in
this toolchain matrix, so either restrict them to GCC-built components or wrap them behind an internal macro layer
that degrades to hand-written code.

---

## 5. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| p99 latency spikes under malformed traffic | exceptions on a hot error path (µs each) | count exceptions per second; switch to `expected` |
| build breaks on one standard library: `add_sat` not found | 2026 rename to `saturating_add` | branch on `__cpp_lib_saturation_arithmetic >= 202603L` |
| `try_push_back(x) == nullptr` does not compile | `optional<T&>` return in the newer wording | test as `bool` |
| contract checks "disappear" in production | evaluation semantic set to `ignore` for that TU | audit build flags; log the semantic at start-up |
| `mdspan`-based kernel slower than raw pointers | dynamic extents (stride loads) and passing a 24-byte object through memory | static extents; pass extents separately |
| reflection code compiles on GCC, fails on Clang | P2996 only in GCC 16 here | feature macro `__cpp_impl_reflection` |

---

## 6. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "expected or exceptions?"</b></summary>

**Initial prompt.** "C++23 has `std::expected`. Should we stop using exceptions?"

**L5 textbook answer.** "Yes, exceptions are slow. `expected` is zero-overhead."

**Why L5 breaks.** Exceptions are *not* slow when nothing throws: at 0% failure the two styles were within a few
ns (Listing 2.15). They are slow *per throw*: 1.9–3.1 µs here. And `expected` is not free either: it widens return
types, every caller must propagate (or the error is silently ignored), and it does not work through constructors
or operators.

**L7 principal defense.** "By failure frequency and locality. Expected, high-rate failures, especially ones driven
by external input, use `expected` with monadic chaining. Rare, non-local failures (resource exhaustion, broken
invariants deep in a call tree) use exceptions, or termination with contracts for programming errors. Constructors
use exceptions or factory functions that return `expected`. I would measure the throw rate in production before
changing a public API."
</details>

<details><summary><b>Chain 2 ⚡ "What does deducing this buy you beyond less typing?"</b></summary>

**Initial prompt.** "Is deducing `this` just syntax sugar?"

**L5 textbook answer.** "It removes duplicate const and non-const overloads."

**Why L5 breaks.** It does more. (1) Value-category forwarding of `*this` (moving members out of an rvalue object)
in one function. (2) CRTP without templates on the base (`Printable`). (3) Recursive lambdas without
`std::function`. (4) **A by-value object parameter changes the calling convention**: Listing 2.14 passes `Pair2` in
two registers instead of a pointer. Two limits: explicit-object functions cannot be virtual, and inside them there
is no implicit `this->`.

**L7 principal defense.** "For small value types, `this T self` by value at non-inlined boundaries; for wrappers,
one forwarding accessor; for mixins, deducing `this` instead of CRTP when we can require C++23 everywhere. I keep an
eye on template bloat: a deduced `Self` instantiates per derived type and value category."
</details>

<details><summary><b>Chain 3 🔥 "Static reflection: what can it do, and what can't it?"</b></summary>

**Initial prompt.** "Explain C++26 reflection. Could it replace our protobuf code generator?"

**L5 textbook answer.** "It's like Java reflection: you can inspect classes at run time."

**Why L5 breaks.** It is **compile-time only**. `std::meta::info` values do not exist at run time, and there is no
`Class.forName`. What you get at run time is the *code generated from* reflection (Listing 2.17: a field printer
and an enum-to-string function produced per type). It also respects access control by default. It can generate
in-process serialization, but it cannot replace a schema-first IDL: protobuf's value is a language-neutral wire
contract with versioning rules, which reflection over C++ types does not provide.

**L7 principal defense.** "Reflection removes boilerplate generators for in-process tasks: enum strings, struct
printers, hashing, ORM-style mapping, test registration. Cross-language and cross-version contracts stay
schema-first. Adoption depends on the compiler matrix: today it is GCC 16 with `-freflection` only, so I would put
it behind a macro layer with hand-written fallbacks, or limit it to GCC-built tools."
</details>

<details><summary><b>Chain 4 ⚡ "Do contracts replace assert and input validation?"</b></summary>

**Initial prompt.** "C++26 has contracts. Can we replace all our checks with `pre` conditions?"

**L5 textbook answer.** "Yes, contracts are better asserts and document the API."

**Why L5 breaks.** The evaluation semantic is selected *per build or TU*: `ignore` removes the check, and `observe`
continues after a violation (Listing 2.18: `clamp_index` returned −1 for `n = 0`). A check that guards against
attacker-controlled input must always run, so it cannot be a contract. Contracts also have rules that surprise:
by-value parameters used in postconditions must be `const` (the first build of the listing failed on exactly that).
Side effects in predicates are not guaranteed to happen (they may be evaluated zero, one or more times).

**L7 principal defense.** "Contracts for programming errors (preconditions callers must meet, invariants of our own
code), with `enforce` in tests and a deliberate choice per production build. Validation of external data stays
explicit code that returns `expected` or throws. Predicates have no side effects. The violation handler logs with
enough context (kind, location, comment) for triage."
</details>

<details><summary><b>Chain 5 🧊 "Why do senders/receivers beat futures?"</b></summary>

**Initial prompt.** "What is wrong with `std::future` that P2300 fixes?"

**L5 textbook answer.** "Futures block; senders are asynchronous."

**Why L5 breaks.** Futures also chain asynchronously in the Concurrency TS (`then`). The structural problem is
elsewhere. Each future step allocates a shared state and synchronizes the producer/consumer handoff, a
continuation's execution context is unspecified, and there is no cancellation. Senders are lazy descriptions whose
`connect` produces a single operation state: no allocation per step, no synchronization between steps on the same
agent, explicit schedulers, and value/error/stopped channels with `stop_token` cancellation. The status matters too:
no standard library here ships it yet, and stdexec is the production reference.

**L7 principal defense.** "Senders make execution context and cancellation explicit and let the compiler see the whole
pipeline. I would adopt stdexec (or libunifex) behind our own thin layer now, and migrate to `std::execution` when
our toolchains ship it. Folder 10 measures allocations for both models."
</details>

<details><summary><b>Chain 6 ⚡ "Our code compiled with libc++ but not libstdc++: add_sat"</b></summary>

**Initial prompt.** "Someone used `std::add_sat` from C++26. It builds on macOS and fails on Linux with GCC 16.
Explain."

**L5 textbook answer.** "GCC hasn't implemented it yet."

**Why L5 breaks.** GCC 16 *has* saturation arithmetic, under the newer names: `std::saturating_add` etc., with
`__cpp_lib_saturation_arithmetic` = 202603L. libc++ 21 implements the earlier names (202311L). Both libraries are
"right" for the draft they track. Using a C++26 library facility before the standard is published means depending on
a moving target, and the feature macro *value*, not just its presence, tells you which version you have.

**L7 principal defense.** "Pre-standard features go through a compatibility header that branches on macro values and
exposes our own stable names. CI builds with every shipped standard library. Once the standard is published and both
libraries agree, the shim collapses to a `using`."
</details>

<details><summary><b>Chain 7 🧊 "mdspan vs a raw pointer + stride"</b></summary>

**Initial prompt.** "Is `std::mdspan` as fast as hand-written index math?"

**L5 textbook answer.** "Yes, it's a zero-cost abstraction over pointer arithmetic."

**Why L5 breaks.** With static extents, yes: Listing 2.16's `at_static` is a shift and a load. With dynamic extents,
the extents are data (a 24-byte object): loaded from the stack on x86-64 and through a pointer on AArch64,
multiplied, then used. That matches hand-written code that also keeps strides in memory, but it is not free compared
with compile-time shapes. Accessor policies (atomic, restrict-like, bounds-checked) can add more.

**L7 principal defense.** "Static extents where the shape is a compile-time fact (tiles, small matrices); dynamic
extents at API boundaries; and in hot kernels, hoist `extent()` into locals and check the inner loop in the
assembly. `layout_left` vs `layout_right` must match the traversal order, or every access misses the cache."
</details>

<details><summary><b>Chain 8 🔥 "Which C++26 features can we use today?"</b></summary>

**Initial prompt.** "We are on GCC 16 and Clang 21. What C++26 can we use in production?"

**L5 textbook answer.** "C++26 isn't finished, so none of it."

**Why L5 breaks.** Listings 2.17–2.20 show a lot running today. Both compilers: pack indexing, `_` placeholders,
`= delete("reason")`, structured-binding packs, saturation arithmetic (under different names). GCC 16 only:
contracts, reflection (`-freflection`), constexpr exceptions, `inplace_vector`, `function_ref`. Neither:
`std::execution`, hazard pointers, RCU, `hive`, `simd`, `linalg`. Production use is a policy decision per feature:
some language features are stable, while library features can still change shape (the saturation rename, the
`try_push_back` return type).

**L7 principal defense.** "Language features that both compilers implement identically are fine now, behind
`-std=c++26`. GCC-only features go into components that are GCC-built or behind a compatibility layer. Library
features in flux wait, or get wrapped. Reflection and contracts are worth piloting in tools and tests first.
Concurrency facilities come from proven libraries (stdexec, folly) until the standard library ships them."
</details>

---

## 7. Invariants checklist

- [ ] Error paths that external input can trigger return `expected`, not exceptions.
- [ ] Every C++26 library use is gated on the feature macro *value*, with a fallback.
- [ ] Contracts guard programming errors only; the evaluation semantic is chosen and logged per build.
- [ ] Postcondition parameters are `const`; contract predicates are side-effect free.
- [ ] Hot `mdspan` kernels use static extents or hoisted extents; layout matches traversal.
- [ ] Reflection and contracts are confined to GCC-built components, or wrapped, until Clang ships them.

## 8. References

- P0847R7 (deducing `this`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2021/p0847r7.html>
- P0323R12 (`expected`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2022/p0323r12.html>
- P0009R18 (`mdspan`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2022/p0009r18.html>
- P2996R13 (reflection): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2025/p2996r13.html>
- P2900R14 (contracts): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2025/p2900r14.pdf>
- P2300R10 (`std::execution`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2024/p2300r10.html>
- P0843R14 (`inplace_vector`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2024/p0843r14.html>
- NVIDIA stdexec: <https://github.com/NVIDIA/stdexec>
- GCC C++26 status: <https://gcc.gnu.org/projects/cxx-status.html>
- libc++ status: <https://libcxx.llvm.org/Status/Cxx26.html>
