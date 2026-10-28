# 01 · C++11 and C++14: the foundation (move, RAII, lambdas, variadics, constexpr)

> **Scope.** C++11 is the standard that made modern C++ possible, and C++14 is the release that finished it.
> This file covers the parts every later standard builds on, each shown as what the compiler actually generates:
> lambdas as structs, braced initialization and its traps, variadic templates and perfect forwarding, and
> `constexpr` from one-return-statement functions to compile-time tables in read-only data. Move semantics,
> `noexcept` and RAII internals are in Folder 01 (file 02) and Folder 05. This file links to them rather than
> repeating them.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 2.1 | `lambda_layout.cpp` | closure sizes for 7 capture styles; copy vs reference capture; inlined lambda vs indirect function pointer | run + asm (x86-64, AArch64) |
| 2.2 | `init_traps.cpp` | `vector{3}` vs `vector(3)`, `string{3,'x'}`, `initializer_list` hijacking, `auto x{1}`, narrowing, the most vexing parse | run + expected diagnostics on both compilers |
| 2.3 | `constexpr_evo.cpp` | C++11 recursion vs C++14 loops; a CRC-32 table computed by the compiler; `std::array` not usable in C++14 constexpr | builds as C++11, C++14 and C++23; expected C++14 failure; asm + data |
| 2.4 | `variadic.cpp` | recursive packs, perfect forwarding (`make_unique`), `index_sequence` (`apply` before C++17) | run, both compilers |

**Verification line.** Same harness as Folder 01: native runs with GCC 16.2 (libstdc++) and Clang 21.1 (libc++),
`-O2 -Wall -Wextra -Wpedantic -Werror -Wshadow -Wconversion -Wsign-conversion`; codegen with Clang 21.1 `-O3` for
`x86_64-linux-gnu` and `aarch64-linux-gnu`. Where a listing is built under several `-std=` values, each build is
named.

---

## 1. First principles

### 1.1 What C++11 changed underneath

| Problem in C++03 | C++11 mechanism | What it is in the machine |
|---|---|---|
| returning or inserting heavy objects copied them | rvalue references, move constructors (Folder 01/02) | a move is a constructor that steals pointers; `noexcept` decides whether containers use it |
| function objects needed hand-written classes | lambdas | an unnamed class with `operator()` and one data member per capture (§1.2) |
| "N overloads for N arguments" | variadic templates | a pack is expanded at compile time into separate instantiations or a comma list (§1.4) |
| compile-time computation only via templates/macros | `constexpr` | the compiler evaluates the function and emits the *result* as data (§1.5) |
| no portable threads or atomics | `std::thread`, `<atomic>`, the memory model | Folders 07–08 |
| `NULL` is an integer | `nullptr` (`std::nullptr_t`) | overload resolution, not codegen |
| inconsistent initialization syntax | braced (uniform) initialization | `std::initializer_list` is a {pointer, size} view of a compiler-made array (§1.3) |
| leaky enums | `enum class` with an explicit underlying type | layout control, no implicit conversions |

### 1.2 A lambda is a struct (Listing 2.1)

```cpp
// lambda_layout.cpp - a lambda is an unnamed struct with operator(); captures are its data members
#include <algorithm>
#include <cstddef>
#include <memory>
#include <print>
#include <utility>

// What the compiler generates for [=](int v) { return v * scale + bias; } (C++11):
struct HandWrittenClosure {
    int scale;                        // captured by copy: a member initialized at the lambda expression
    double bias;
    double operator()(int v) const { return v * scale + bias; }  // const unless the lambda is 'mutable'
};

// Opaque predicate boundaries, to compare an inlined closure call with an indirect function-pointer call.
std::size_t count_fp(const int* p, std::size_t n, bool (*pred)(int)) {
    return static_cast<std::size_t>(std::count_if(p, p + n, pred));  // indirect call per element
}
std::size_t count_lambda(const int* p, std::size_t n, int limit) {
    return static_cast<std::size_t>(std::count_if(p, p + n, [limit](int v) { return v > limit; }));  // inlined
}

int main() {
    int scale = 3;
    double bias = 0.5;
    int big[64] = {};
    auto none = [] { return 1; };
    auto by_copy = [=](int v) { return v * scale + bias; };
    auto by_ref = [&](int v) { return v * scale + bias; };
    auto one_ref = [&scale] { return scale; };
    auto array_copy = [big] { return big[0]; };
    auto init_capture = [p = std::make_unique<int>(7)] { return *p; };  // C++14: move-only capture
    auto generic = [](auto a, auto b) { return a + b; };                // C++14: a template operator()
    HandWrittenClosure hand{scale, bias};

    std::println("sizeof closure:");
    std::println("  {:<30} {:>3}  (empty class)", "[] { ... }", sizeof(none));
    std::println("  {:<30} {:>3}  (int + double, padded)", "[=] uses scale, bias", sizeof(by_copy));
    std::println("  {:<30} {:>3}  (two references)", "[&] uses scale, bias", sizeof(by_ref));
    std::println("  {:<30} {:>3}", "[&scale]", sizeof(one_ref));
    std::println("  {:<30} {:>3}  (arrays are copied element-wise)", "[big] int[64]", sizeof(array_copy));
    std::println("  {:<30} {:>3}", "[p = make_unique<int>(7)]", sizeof(init_capture));
    std::println("  {:<30} {:>3}", "HandWrittenClosure", sizeof(hand));
    std::println("calls: by_copy(2)={} hand(2)={} generic(1,2.5)={} init_capture()={}", by_copy(2), hand(2),
                 generic(1, 2.5), init_capture());

    scale = 100;                       // by_copy captured the OLD value; by_ref sees the new one
    std::println("after scale=100: by_copy(2)={} by_ref(2)={}", by_copy(2), by_ref(2));

    bool (*fp)(int) = [](int v) { return v > 0; };  // only captureless lambdas convert to function pointers
    int data[] = {-1, 2, 3, -4, 5};
    std::println("count_fp={} count_lambda={}", count_fp(data, 5, fp), count_lambda(data, 5, 0));
    static_assert(std::is_empty_v<decltype(none)>);
    static_assert(std::is_move_constructible_v<decltype(init_capture)>);
    static_assert(!std::is_copy_constructible_v<decltype(init_capture)>);  // move-only capture -> move-only closure
}
```

Output (verified, identical on GCC 16.2 and Clang 21.1):

```text
sizeof closure:
  [] { ... }                       1  (empty class)
  [=] uses scale, bias            16  (int + double, padded)
  [&] uses scale, bias            16  (two references)
  [&scale]                         8
  [big] int[64]                  256  (arrays are copied element-wise)
  [p = make_unique<int>(7)]        8
  HandWrittenClosure              16
calls: by_copy(2)=6.5 hand(2)=6.5 generic(1,2.5)=3.5 init_capture()=7
after scale=100: by_copy(2)=6.5 by_ref(2)=200.5
count_fp=3 count_lambda=3
```

* **`[=]` stores copies, `[&]` stores references.** Both closures are 16 bytes here: an `int` + `double` padded,
  or two pointers. The standard leaves the representation of reference captures unspecified, but both compilers
  store one pointer per captured variable. A lambda that captures *one* reference is 8 bytes. A captured array is
  copied element by element (256 bytes for `int[64]`), and that is a classic hidden cost in callbacks.
* **Copy capture is a snapshot.** After `scale = 100`, `by_copy` still uses 3 and `by_ref` uses 100. This is also the
  dangling-reference trap in reverse: a `[&]` lambda that outlives its scope (stored in a `std::function`, handed
  to a thread) reads a dead stack frame.
* **C++14 init-capture** (`[p = std::make_unique<int>(7)]`) makes move-only closures possible. The closure is
  then itself move-only (the `static_assert`s), so it cannot go into a C++11 `std::function`, which requires
  copyable targets. Folder 04 covers `std::move_only_function` (C++23).
* **Only captureless lambdas convert to function pointers.**

Why the closure-as-a-type matters for performance: `count_lambda` gets an inlined, vectorized comparison; `count_fp`
makes an indirect call per element:

<details><summary>Clang -O3, x86-64 (count_fp: indirect call per element; count_lambda: vectorized)</summary>

```asm
_Z8count_fpPKimPFbiE:              # count_fp(int const*, unsigned long, bool (*)(int))
	pushq	%r15
	pushq	%r14
	pushq	%r13
	pushq	%r12
	pushq	%rbx
	testq	%rsi, %rsi
	je	.LBB0_1
	movq	%rdx, %rbx
	movq	%rsi, %r14
	movq	%rdi, %r15
	shlq	$2, %r14
	xorl	%r13d, %r13d
	xorl	%r12d, %r12d
.LBB0_3:
	movl	(%r15,%r13), %edi
	callq	*%rbx
	movzbl	%al, %eax
	addq	%rax, %r12
	addq	$4, %r13
	cmpq	%r13, %r14
	jne	.LBB0_3
	jmp	.LBB0_4
.LBB0_1:
	xorl	%r12d, %r12d
.LBB0_4:
	movq	%r12, %rax
	popq	%rbx
	popq	%r12
	popq	%r13
	popq	%r14
	popq	%r15
	retq

_Z12count_lambdaPKimi:             # count_lambda(int const*, unsigned long, int)
	testq	%rsi, %rsi
	je	.LBB1_1
	leaq	(,%rsi,4), %r8
	addq	$-4, %r8
	cmpq	$12, %r8
	jae	.LBB1_5
	xorl	%eax, %eax
	movq	%rdi, %rcx
	jmp	.LBB1_8
.LBB1_1:
	xorl	%eax, %eax
	retq
.LBB1_5:
	shrq	$2, %r8
	addq	$1, %r8
	movq	%r8, %r9
	andq	$-4, %r9
	leaq	(%rdi,%r9,4), %rcx
	movd	%edx, %xmm0
	pshufd	$80, %xmm0, %xmm1
	pxor	%xmm0, %xmm0
	xorl	%eax, %eax
	movdqa	.LCPI1_0(%rip), %xmm3
	pxor	%xmm2, %xmm2
.LBB1_6:
	movq	(%rdi,%rax,4), %xmm4
	movq	8(%rdi,%rax,4), %xmm5
	pcmpgtd	%xmm1, %xmm4
	pshufd	$212, %xmm4, %xmm4
	pand	%xmm3, %xmm4
	paddq	%xmm4, %xmm0
	pcmpgtd	%xmm1, %xmm5
	pshufd	$212, %xmm5, %xmm4
	pand	%xmm3, %xmm4
	paddq	%xmm4, %xmm2
	addq	$4, %rax
	cmpq	%rax, %r9
	jne	.LBB1_6
	paddq	%xmm0, %xmm2
	pshufd	$238, %xmm2, %xmm0
	paddq	%xmm2, %xmm0
	movq	%xmm0, %rax
	cmpq	%r9, %r8
	je	.LBB1_2
.LBB1_8:
	leaq	(%rdi,%rsi,4), %rsi
.LBB1_9:
	xorl	%edi, %edi
	cmpl	%edx, (%rcx)
	setg	%dil
	addq	%rdi, %rax
	addq	$4, %rcx
	cmpq	%rsi, %rcx
	jne	.LBB1_9
.LBB1_2:
	retq
```

</details>

`count_fp`'s loop body is `movl (%r15,%r13),%edi; callq *%rbx`: one indirect call per element. `count_lambda` has
no call at all. Each lambda has a *unique type*, so `std::count_if<const int*, Lambda>` is instantiated for exactly
that body and the optimizer sees it. A function pointer is a *value*, known only at run time unless constant
propagation reaches it. This is the mechanism behind "std::sort beats qsort".

### 1.3 Braced initialization and its traps (Listing 2.2)

```cpp
// init_traps.cpp - C++11 uniform initialization: initializer_list hijacking, auto + braces, narrowing, vexing parse
#include <initializer_list>
#include <print>
#include <string>
#include <type_traits>
#include <vector>

struct Widget {
    int a, b;
    Widget(int x, int y) : a(x), b(y) {}
    Widget(std::initializer_list<int> il) : a(static_cast<int>(il.size())), b(-1) {}  // wins for ANY braced list
};
struct Timer {};
struct Clock {
    explicit Clock(Timer) {}
    int now() const { return 42; }
};

int main() {
    std::vector<int> paren(3, 7);     // three 7s
    std::vector<int> brace{3, 7};     // two elements: 3 and 7 (initializer_list constructor wins)
    std::vector<int> one_paren(3);    // three zeros
    std::vector<int> one_brace{3};    // ONE element: 3
    std::println("vector(3,7)={} vector{{3,7}}={} vector(3)={} vector{{3}}={}", paren, brace, one_paren, one_brace);

    std::string s1(3, 'x');           // "xxx"
    std::string s2{3, 'x'};           // two chars: '\x03', 'x'
    std::println("string(3,'x').size()={} string{{3,'x'}}.size()={}", s1.size(), s2.size());

    Widget w1(1, 2);
    Widget w2{1, 2};                  // initializer_list ctor, not (int,int)
    std::println("Widget(1,2): a={} b={}   Widget{{1,2}}: a={} b={}", w1.a, w1.b, w2.a, w2.b);

    auto a1 = {1};                    // std::initializer_list<int>
    auto a2{1};                       // int since C++17 (N3922); was initializer_list<int> in C++11/14
    static_assert(std::is_same_v<decltype(a1), std::initializer_list<int>>);
    static_assert(std::is_same_v<decltype(a2), int>);
    std::println("auto a1 = {{1}} -> initializer_list<int>;  auto a2{{1}} -> int");

    Clock c{Timer{}};                 // braces: an object. Clock c(Timer()); would declare a FUNCTION
    std::println("Clock c{{Timer{{}}}}.now() = {}", c.now());
#ifdef SHOW_INIT_ERRORS
    int narrow{3.5};                  // narrowing conversion inside braces: ill-formed
    Clock vexing(Timer());            // most vexing parse: declares a function returning Clock
    int n = vexing.now();             // ill-formed: vexing names a function
    (void)narrow; (void)n;
#endif
}
```

Output (verified, identical on both compilers):

```text
vector(3,7)=[7, 7, 7] vector{3,7}=[3, 7] vector(3)=[0, 0, 0] vector{3}=[3]
string(3,'x').size()=3 string{3,'x'}.size()=2
Widget(1,2): a=1 b=2   Widget{1,2}: a=2 b=-1
auto a1 = {1} -> initializer_list<int>;  auto a2{1} -> int
Clock c{Timer{}}.now() = 42
```

The rule behind every surprising line: **if a class has an `initializer_list` constructor, a braced list prefers it
over every other constructor**, as long as the elements convert. `vector<int>{3}` is one element. `string{3, 'x'}` is
the characters `'\x03'` and `'x'`. `Widget{1, 2}` calls the list constructor. Braces are still the safer default
for *aggregates and non-container types* because they forbid narrowing and avoid the most vexing parse. The
diagnostics with `-DSHOW_INIT_ERRORS` (GCC, then Clang):

```text
init_traps.cpp:43:16: error: narrowing conversion of '3.5e+0' from 'double' to 'int' [-Wnarrowing]
init_traps.cpp:44:17: error: parentheses were disambiguated as a function declaration [-Werror=vexing-parse]
init_traps.cpp:44:17: note: replace parentheses with braces to declare a variable
init_traps.cpp:45:20: error: request for member 'now' in 'vexing', which is of non-class type 'Clock(Timer (*)())'
init_traps.cpp:43:16: error: type 'double' cannot be narrowed to 'int' in initializer list [-Wc++11-narrowing]
init_traps.cpp:43:16: note: insert an explicit cast to silence this issue
init_traps.cpp:43:16: error: implicit conversion from 'double' to 'int' changes value from 3.5 to 3 [-Werror,-Wliteral-conversion]
init_traps.cpp:44:17: error: parentheses were disambiguated as a function declaration [-Werror,-Wvexing-parse]
init_traps.cpp:44:18: note: add a pair of parentheses to declare a variable
init_traps.cpp:45:19: error: member reference base type 'Clock (Timer (*)())' is not a structure or union
```

`auto a2{1}` was `std::initializer_list<int>` in C++11/14 and became `int` with N3922. The C++17 committee applied
that change as a defect report: both compilers here give `int` even with `-std=c++11` (checked with a one-line `static_assert`).

### 1.4 Variadic templates and perfect forwarding (Listing 2.4, `variadic.cpp`)

```cpp
// variadic.cpp - C++11 variadic templates, perfect forwarding, and C++14 index_sequence
// The templates use only C++11/14 facilities; main() prints with C++23 std::println.
#include <cstddef>
#include <memory>
#include <print>
#include <string>
#include <tuple>
#include <utility>

// C++11: no fold expressions, so a pack is consumed by recursion (one instantiation per element).
template <class T>
T sum11(T v) { return v; }
template <class T, class... Rest>
T sum11(T first, Rest... rest) { return first + sum11(rest...); }

// C++11 perfect forwarding: the core of std::make_unique (which only arrived in C++14, N3656).
template <class T, class... Args>
std::unique_ptr<T> my_make_unique(Args&&... args) {
    return std::unique_ptr<T>(new T(std::forward<Args>(args)...));
}

// C++14: std::index_sequence turns a tuple into a pack of indices; this is std::apply before C++17.
template <class F, class Tuple, std::size_t... I>
decltype(auto) apply_impl(F&& f, Tuple&& t, std::index_sequence<I...>) {
    return std::forward<F>(f)(std::get<I>(std::forward<Tuple>(t))...);
}
template <class F, class Tuple>
decltype(auto) my_apply(F&& f, Tuple&& t) {
    constexpr std::size_t n = std::tuple_size<typename std::remove_reference<Tuple>::type>::value;
    return apply_impl(std::forward<F>(f), std::forward<Tuple>(t), std::make_index_sequence<n>{});
}

int g_copies = 0;
struct Tracked {
    std::string s;
    explicit Tracked(std::string v) : s(std::move(v)) {}
    Tracked(const Tracked& o) : s(o.s) { ++g_copies; }
    Tracked(Tracked&&) noexcept = default;
};
struct Pair {
    Tracked a, b;
    Pair(Tracked x, Tracked y) : a(std::move(x)), b(std::move(y)) {}
};

// sizeof... counts a pack without expanding it.
template <class... Ts>
constexpr std::size_t count_types() { return sizeof...(Ts); }
static_assert(count_types<int, char, double>() == 3, "");

int main() {
    std::println("sum11(1, 2, 3, 4) = {}", sum11(1, 2, 3, 4));
    Tracked t("lvalue");
    auto p = my_make_unique<Pair>(t, Tracked("rvalue"));  // t is copied once, the temporary is moved
    std::println("my_make_unique<Pair>(lvalue, rvalue): copies = {} ({} / {})", g_copies, p->a.s, p->b.s);
    auto r = my_apply([](int a, double b, const std::string& c) { return c + ":" + std::to_string(a + b); },
                      std::make_tuple(1, 2.5, std::string("apply")));
    std::println("my_apply -> {}", r);
}
```

Output (verified, both compilers):

```text
sum11(1, 2, 3, 4) = 10
my_make_unique<Pair>(lvalue, rvalue): copies = 1 (lvalue / rvalue)
my_apply -> apply:3.500000
```

* **C++11 packs are consumed by recursion.** `sum11(1,2,3,4)` instantiates four functions. C++17 fold expressions
  (file 02) do it in one. C++26 pack indexing (file 04) removes the remaining recursive tricks.
* **Perfect forwarding is a cast that preserves the value category.** In `my_make_unique` the lvalue `t` stays an
  lvalue (one copy), and the temporary stays an rvalue (moved). `copies = 1` is the proof. The mechanism (forwarding
  references, reference collapsing) is Folder 06 file 01.
* **`std::index_sequence` (C++14)** turns "the elements of a tuple" into a pack of indices. That is how
  `std::apply`, `std::make_from_tuple` and every C++14-era `tuple` algorithm are written.

### 1.5 constexpr: from recursion to tables in .rodata (Listing 2.3, `constexpr_evo.cpp`)

```cpp
// constexpr_evo.cpp - constexpr from C++11 (one return statement) to C++14 (loops) to a table in .rodata
// No digit separators: they are C++14, and this file must also build as C++11.
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdio>

// C++11: the body must be a single return statement, so iteration is recursion.
constexpr std::uint32_t crc_bit11(std::uint32_t c, int k) {
    return k == 0 ? c : crc_bit11((c & 1u) ? 0xEDB88320u ^ (c >> 1) : c >> 1, k - 1);
}
constexpr std::uint32_t crc_entry11(std::uint32_t i) { return crc_bit11(i, 8); }
static_assert(crc_entry11(1) == 0x77073096u, "message required before C++17");

#if __cplusplus >= 201402L
#if __cplusplus >= 201703L || defined(USE_STD_ARRAY_IN_CXX14)
using Table = std::array<std::uint32_t, 256>;  // non-const operator[] is constexpr only since C++17 (P0031)
#else
struct Table {                                 // C++14: the language allows mutation, the library did not yet
    std::uint32_t v[256];
    constexpr std::uint32_t& operator[](std::size_t i) { return v[i]; }
    constexpr const std::uint32_t& operator[](std::size_t i) const { return v[i]; }
};
#endif
// C++14: local variables, loops and mutation are allowed in constant expressions.
constexpr Table make_crc_table() {
    Table t{};
    for (std::uint32_t i = 0; i < 256; ++i) {
        std::uint32_t c = i;
        for (int k = 0; k < 8; ++k) c = (c & 1u) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
        t[i] = c;
    }
    return t;
}
// constexpr variable: computed by the compiler, emitted as initialized read-only data (no run-time init).
constexpr Table kCrcTable = make_crc_table();
static_assert(kCrcTable[1] == crc_entry11(1) && kCrcTable[255] == crc_entry11(255), "C++11 == C++14");

std::uint32_t crc32(const unsigned char* p, std::size_t n) {
    std::uint32_t c = 0xFFFFFFFFu;
    for (std::size_t i = 0; i < n; ++i) c = kCrcTable[(c ^ p[i]) & 0xFFu] ^ (c >> 8);
    return c ^ 0xFFFFFFFFu;
}
#endif

int main() {
#if __cplusplus >= 201402L
    const unsigned char msg[] = "123456789";
    std::printf("crc32(\"123456789\") = %08x (check value cbf43926)\n", static_cast<unsigned>(crc32(msg, 9)));
    std::printf("table[1] = %08x, table[255] = %08x\n", static_cast<unsigned>(kCrcTable[1]),
                static_cast<unsigned>(kCrcTable[255]));
#else
    std::printf("C++11 build: crc_entry11(1) = %08x\n", static_cast<unsigned>(crc_entry11(1)));
#endif
}
```

The same file built three ways (verified; GCC and Clang agree):

```text
-std=c++11:
C++11 build: crc_entry11(1) = 77073096
```

```text
-std=c++14:
crc32("123456789") = cbf43926 (check value cbf43926)
table[1] = 77073096, table[255] = 2d02ef8d
```

```text
-std=c++23:
crc32("123456789") = cbf43926 (check value cbf43926)
table[1] = 77073096, table[255] = 2d02ef8d
```

And with `-std=c++14 -DUSE_STD_ARRAY_IN_CXX14`, the same algorithm written with `std::array` (GCC, then Clang):

```text
constexpr_evo.cpp:31:12: error: call to non-'constexpr' function 'std::array<_Tp, _Nm>::value_type& std::array<_Tp, _Nm>::operator[](size_type) [with _Tp = unsigned int; long long unsigned int _Nm = 256; reference = unsigned int&; size_type = long long unsigned int]'
constexpr_evo.cpp:37:46: error: non-constant condition for static assertion
constexpr_evo.cpp:26:17: error: constexpr function never produces a constant expression [-Winvalid-constexpr]
constexpr_evo.cpp:36:17: error: constexpr variable 'kCrcTable' must be initialized by a constant expression
constexpr_evo.cpp:37:15: error: static assertion expression is not an integral constant expression
```

That failure is the interesting fact. **C++14 relaxed `constexpr` in the language, but the library had not caught
up**: `std::array`'s non-const `operator[]` became `constexpr` only in C++17 (P0031). The digit separators
(`0xEDB8'8320`) had to go too, because they are C++14 and this file also builds as C++11. Each standard is two
releases: the language one and the library one.

The generated code proves where the table lives (Clang `-O3`, x86-64):

```asm
_Z5crc32PKhm:                      # crc32(unsigned char const*, unsigned long)
	testq	%rsi, %rsi
	je	.LBB0_1
	cmpq	$1, %rsi
	jne	.LBB0_8
	movl	$-1, %eax
	xorl	%ecx, %ecx
	jmp	.LBB0_4
.LBB0_1:
	xorl	%eax, %eax
	retq
.LBB0_8:
	movq	%rsi, %rdx
	andq	$-2, %rdx
	movl	$-1, %eax
	xorl	%ecx, %ecx
	leaq	_ZL9kCrcTable(%rip), %r8              # kCrcTable
.LBB0_9:
	movzbl	(%rdi,%rcx), %r9d
	xorb	%al, %r9b
	movzbl	%r9b, %r9d
	shrl	$8, %eax
	xorl	(%r8,%r9,4), %eax
	movzbl	1(%rdi,%rcx), %r9d
	xorb	%al, %r9b
	movzbl	%r9b, %r9d
	shrl	$8, %eax
	xorl	(%r8,%r9,4), %eax
	addq	$2, %rcx
	cmpq	%rcx, %rdx
	jne	.LBB0_9
.LBB0_4:
	testb	$1, %sil
	je	.LBB0_6
	movzbl	(%rdi,%rcx), %ecx
	xorb	%al, %cl
	movzbl	%cl, %ecx
	leaq	_ZL9kCrcTable(%rip), %rdx             # kCrcTable
	shrl	$8, %eax
	xorl	(%rdx,%rcx,4), %eax
.LBB0_6:
	notl	%eax
	retq
```

```text
_ZL9kCrcTable:                     # kCrcTable
	.long 0
	.long 1996959894
	.long 3993919788
	.long 2567524794
	.long 124634137
	... (256 data directives in total, 259 lines in the full listing)
```

`crc32` loads from `_ZL9kCrcTable(%rip)`, and the table itself is 256 `.long` constants emitted by the compiler.
There is no initialization code, no static-init guard and no run-time cost. Compare a `static const` table filled
by a function at start-up: that one needs either a dynamic initializer (ordering problems, Folder 06) or a
thread-safe local-static guard (Folder 08).

---

## 2. Evolution table

| Feature | C++11 | C++14 | Later |
|---|---|---|---|
| `constexpr` functions | single `return`, recursion only | loops, locals, mutation (N3652) | C++17 lambdas; C++20 `virtual`, `try`, dynamic allocation; C++23 `static` locals; C++26 placement new, exceptions |
| `constexpr` library | very little | `std::array` read access only | C++17 mutable `array`; C++20 `vector`/`string`; C++23 `unique_ptr`, `optional` more |
| lambdas | captures by copy/reference, non-generic | generic (`auto` params), init-capture, `auto` return deduction | C++17 `constexpr` lambdas, `*this` capture; C++20 template lambdas, lambdas in unevaluated contexts; C++23 `static operator()`, deducing `this` |
| initialization | braced init, `initializer_list` | `auto x{1}` still `initializer_list` | N3922 (C++17, applied as a DR): `auto x{1}` → `int`; C++20 designated initializers, paren-init of aggregates |
| variadic templates | packs, `sizeof...` | `std::index_sequence`, `std::make_unique` (N3656) | C++17 folds; C++20 lambda pack captures; C++26 pack indexing, structured-binding packs |
| literals | user-defined literals, raw strings | binary literals, digit separators, `std::chrono` literals, `""s` | C++20 `char8_t`; C++23 `z`/`uz` suffixes |
| type deduction | `auto`, `decltype` | `decltype(auto)`, return type deduction | C++17 CTAD; C++20 abbreviated templates |
| attributes | `[[noreturn]]`, `[[carries_dependency]]` | `[[deprecated]]` | C++17 `[[nodiscard]]`, `[[maybe_unused]]`, `[[fallthrough]]`; C++20 `[[likely]]`, `[[no_unique_address]]`; C++23 `[[assume]]` |
| concurrency | `thread`, `mutex`, `condition_variable`, `atomic`, `future` | `shared_timed_mutex` | C++17 `shared_mutex`, `scoped_lock`; C++20 `jthread`, `atomic::wait`, latch, barrier, semaphore; C++26 hazard pointers, RCU (not shipped by GCC 16 or libc++ 21) |

---

## 3. Production blueprints

### 3.1 Callbacks that cannot dangle

| Subtle buggy way | Production-hardened way |
|---|---|
| `pool.submit([&] { use(local); });` then return | capture by value (`[local]`, or `[p = std::move(ptr)]`), or capture a `shared_ptr`/`weak_ptr` and check it |
| `[this]` in a callback that outlives `*this` | `[self = shared_from_this()]` (Folder 05), or unregister in the destructor before members die |
| `[=]` in a member function (implicitly captures `this`; deprecated in C++20) | name what you capture: `[this, x]` or `[*this]` (C++17 copy of the object) |
| a captured array in a hot callback | capture a pointer or a `std::span` (C++20) |

### 3.2 Initialization rules for a code base

* Aggregates and value types: braces (no narrowing, no vexing parse).
* Containers with a size or fill argument: **parentheses**: `std::vector<int> v(n, 0)`.
* `auto x = T{...}` for "make one of these"; never `auto x{...}` when the type matters to readers.
* Compile-time tables: `constexpr` variables at namespace scope, verified with `static_assert`, so they land in
  `.rodata` as Listing 2.3 shows.

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| a vector has the wrong number of elements | `{n}` / `{n, v}` picked the `initializer_list` constructor | review rule: containers with sizes use `()` |
| "object" that cannot be used, odd errors at the next line | most vexing parse | `-Wvexing-parse` (both compilers, on by default) |
| callback reads garbage after the caller returned | `[&]` capture outliving the frame | ASan `detect_stack_use_after_return`; capture by value |
| table init shows up in start-up profiles | a `static const` table filled at run time | make it `constexpr`; check that the asm has no initializer |
| `constexpr` function "never produces a constant expression" when compiled as C++14 | a library facility that is not yet `constexpr` in that standard | check the library column of the evolution table |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "What is a lambda, really?"</b></summary>

**Initial prompt.** "What does the compiler generate for a lambda? How big is it?"

**L5 textbook answer.** "An anonymous function. It's like a function pointer with captures."

**Why L5 breaks.** A lambda is a *class type*, not a function pointer. Its size is the size of its captures
(Listing 2.1: 1 to 256 bytes), and its `operator()` is `const` unless declared `mutable`. Each lambda has a unique
type, so templates instantiated with it inline the body. The function-pointer model predicts the opposite of the
real performance (indirect call in `count_fp`, none in `count_lambda`). It also cannot explain why a move-capture
lambda does not fit in a C++11 `std::function`.

**L7 principal defense.** "A closure is a compiler-generated struct, one member per capture plus `operator()`. I size
callbacks by their captures, keep them small enough for `std::function`'s small-buffer storage when I must
type-erase (Folder 04), and pass lambdas as template parameters on hot paths so they inline. The production bug to
watch is `[&]` outliving its frame."
</details>

<details><summary><b>Chain 2 ⚡ "Braces or parentheses?"</b></summary>

**Initial prompt.** "Our style guide says 'always use braces'. Agree?"

**L5 textbook answer.** "Yes, uniform initialization works everywhere and prevents narrowing."

**Why L5 breaks.** Listing 2.2: `std::vector<int>{3}` holds one element, `std::string{3, 'x'}` holds two
characters, and `Widget{1, 2}` silently picks the `initializer_list` constructor. Adding an `initializer_list`
constructor to an existing class changes the meaning of every braced call site in the code base, with no
diagnostic.

**L7 principal defense.** "Braces for aggregates and value types, parentheses for containers with size or fill
arguments, and no `initializer_list` constructors on classes that also take a couple of integers. Adding an
`initializer_list` constructor to a public type is an API change, and I review it as one."
</details>

<details><summary><b>Chain 3 🧊 "Is constexpr evaluated at compile time?"</b></summary>

**Initial prompt.** "If I mark a function `constexpr`, does it run at compile time?"

**L5 textbook answer.** "Yes, constexpr functions are computed by the compiler."

**Why L5 breaks.** `constexpr` *permits* compile-time evaluation. A `constexpr` function called with run-time
arguments is an ordinary function. Evaluation at compile time is *required* only in a manifestly constant-evaluated
context: a `constexpr` variable, `static_assert`, template arguments, array bounds, `case` labels, or a C++20
`consteval` function. Listing 2.3 forces it by initializing a `constexpr` variable, and the assembly proves the
result is data. The L5 answer also misses that the *library* lags: the C++14 build fails on `std::array`.

**L7 principal defense.** "To guarantee compile-time evaluation I use a `constexpr` variable, `consteval`, or
`constinit` for static initialization (Folder 06). Then I check the output: the table should be `.long` data with
no initializer function. I keep `constexpr` functions usable at run time too, so tests can run them under
sanitizers."
</details>

<details><summary><b>Chain 4 🔥 "Implement make_unique"</b></summary>

**Initial prompt.** "Write `make_unique` as it would have been written in C++11."

**L5 textbook answer.** `template<class T, class... A> unique_ptr<T> make_unique(A... a) { return unique_ptr<T>(new T(a...)); }`

**Why L5 breaks.** Taking `A...` by value copies every argument. Lvalues are copied once more than needed, and
move-only arguments do not compile. Without `std::forward`, rvalues arrive as lvalues inside the function and are
copied again. Listing 2.4's version (`A&&...` + `std::forward<A>(a)...`) makes exactly one copy, for the lvalue.
The interview follow-ups: why `make_unique` was missing from C++11 (an oversight, fixed by N3656), why it does not
support custom deleters, and why `make_unique<T[]>(n)` value-initializes.

**L7 principal defense.** "Forwarding references plus `std::forward` preserve each argument's category. I'd add
`static_assert(!std::is_array_v<T>)` for the scalar overload, mention `make_unique_for_overwrite` (C++20) for
buffers you will fill anyway, and explain that `make_unique` exists for exception safety in C++11/14 argument
lists (`f(unique_ptr<A>(new A), g())`). C++17's stricter evaluation order removed most of that risk."
</details>

<details><summary><b>Chain 5 ⚡ "Why not just pass function pointers?"</b></summary>

**Initial prompt.** "Templates on callables bloat the binary. Why not accept `bool(*)(int)` everywhere?"

**L5 textbook answer.** "Function pointers are fine; the compiler optimizes them."

**Why L5 breaks.** Only when constant propagation reaches the call. In an opaque boundary (`count_fp`) every element
costs an indirect call and the loop cannot vectorize. The lambda version is vectorized (Listing 2.1). Function
pointers also cannot carry state, so stateful predicates end up in globals or `void*` context parameters (Folder 01,
`cb_cast`).

**L7 principal defense.** "Templates on hot paths, type erasure (`std::function`, `function_ref`) at API boundaries
where code size and compile time matter more. I decide per boundary, by profile and by how often the callable
changes. Binary bloat is measurable: I would check the symbol sizes before trading away inlining."
</details>

<details><summary><b>Chain 6 🧊 "What does std::initializer_list cost?"</b></summary>

**Initial prompt.** "Can I move elements out of an `initializer_list`?"

**L5 textbook answer.** "Yes, use `std::move` on the elements."

**Why L5 breaks.** `initializer_list<T>` is a view of a compiler-generated `const T[]`. The elements are `const`,
so `std::move` produces `const T&&`, which binds to the copy constructor (Folder 01, `move_traps`).
`vector<string>{a, b, c}` therefore *copies* each string, and `vector<unique_ptr<T>>{...}` does not compile.

**L7 principal defense.** "For move-only or heavy elements, `reserve` + `emplace_back`, or a variadic factory that
forwards. `initializer_list` is for small, cheap-to-copy literals."
</details>

<details><summary><b>Chain 7 ⚡ "C++11 recursion vs C++17 folds: does it matter?"</b></summary>

**Initial prompt.** "Our C++11-era code uses recursive variadic templates. Worth rewriting?"

**L5 textbook answer.** "No, the generated code is the same after inlining."

**Why L5 breaks.** The run time is usually the same. The *compile time* is not. N-element recursion instantiates
N function templates (more with helper structs) and nests N deep, which hits instantiation-depth limits and
dominates build time in heavy metaprogramming. Folds, `if constexpr` and C++26 pack indexing instantiate one.

**L7 principal defense.** "Rewrite where build profiles say so. Clang's `-ftime-trace` shows template
instantiation time per entity. Leave stable code alone otherwise. New code uses folds and pack indexing."
</details>

<details><summary><b>Chain 8 🔥 "When does a [&] lambda become a bug?"</b></summary>

**Initial prompt.** "Is `std::thread t([&] { work(buf); }); t.detach();` OK?"

**L5 textbook answer.** "Yes if `buf` is still around."

**Why L5 corrupts memory.** "Still around" is the whole problem. After the enclosing function returns, the closure
holds a reference into a dead stack frame. With a detached thread, nothing ever waits for the work to finish.
On ARM64 the thread may also observe partially written state from the creator: a reference capture gives no
ordering guarantees beyond the `thread` constructor's own synchronization point.

**L7 principal defense.** "No `detach` in production code. Use `std::jthread` (C++20, joins in its destructor,
Folder 08), and capture by value or by owning pointer. If work must outlive the scope, its inputs move into the
closure, and its lifetime is owned by a pool with shutdown semantics (Folder 10)."
</details>

---

## 6. Invariants checklist

- [ ] Long-lived callbacks capture by value or by owning pointer; no `[&]` across threads or into stored
      `std::function`s.
- [ ] Containers with size/fill arguments use parentheses; no new `initializer_list` constructors on numeric-taking
      classes.
- [ ] Compile-time tables are `constexpr` variables checked with `static_assert`, and appear as data in the binary.
- [ ] Forwarding functions use `T&&` + `std::forward<T>`.
- [ ] Hot-path callables are template parameters; type erasure only at boundaries.

## 7. References

- N3652 (relaxed constexpr, C++14): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2013/n3652.html>
- N3656 (`make_unique`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2013/n3656.htm>
- N3922 (`auto` and braced init): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2014/n3922.html>
- P0031R0 (constexpr for `array`, iterators): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2015/p0031r0.html>
- cppreference, lambda expressions: <https://en.cppreference.com/w/cpp/language/lambda>
- Scott Meyers, *Effective Modern C++* (2014), items 7 (braces), 31–34 (lambdas), 25 (`std::forward`).
