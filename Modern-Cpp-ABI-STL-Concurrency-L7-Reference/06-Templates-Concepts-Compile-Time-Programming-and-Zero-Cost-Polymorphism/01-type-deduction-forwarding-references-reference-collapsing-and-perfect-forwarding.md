# 01 · Type deduction, forwarding references, reference collapsing, and perfect forwarding

> **Scope.** Every generic interface in C++ rests on four rules: how template arguments are deduced from a call, how
> `auto` and `decltype(auto)` deduce, how references to references collapse, and what `std::forward` does with the
> result. This file proves each rule with `static_assert`s that both compilers check, then shows the five cases where
> "perfect" forwarding is not perfect, with the compilers' own diagnostics.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 6.1 | `deduction.cpp` | 24 deduction facts as `static_assert`s: by value, `T&`, `const T&`, `T&&`, `auto`, `auto&&`, `decltype(auto)`; collapsing; the parenthesized-return trap | compiles on both; expected diagnostics |
| 6.2 | `forward_fail.cpp` | braced lists, `0` as null, overload sets and bit-fields break forwarding; the fix for each | run + expected diagnostics on both |

**Verification line.** As in Folders 01–05: GCC 16.2 and Clang 21.1, `-std=c++23 -O2` with warnings as errors. Every
deduction claim below is a `static_assert` in Listing 6.1, so the build itself is the proof.

---

## 1. First principles

### 1.1 The deduction rules (Listing 6.1)

```text
 template <class T> void f(P param);   f(expr);      deduce T by matching P against the type of expr
 P = T          by value: drop references, then drop top-level const/volatile; arrays -> T*, functions -> T(*)(...)
 P = T&         by lvalue reference: T keeps const (const int -> T = const int); arrays keep their extent
 P = const T&   T is the type without const
 P = T&&        FORWARDING reference (T is deduced): lvalue of U -> T = U&  (then U& && collapses to U&)
                                                     rvalue of U -> T = U   (param type U&&)
 auto x = e;    same as P = T;    auto& x = e;  same as P = T&;    auto&& x = e;  forwarding reference
 decltype(auto) x = e;   exactly decltype(e): for a name, its declared type; for (e) or any other expression,
                          T& for lvalues, T&& for xvalues, T for prvalues   (Folder 01, file 02)
 collapsing:  & &  ->  &      & &&  ->  &      && &  ->  &      && &&  ->  &&
```

```cpp
// deduction.cpp - template and auto type deduction, forwarding references, reference collapsing: all static_asserts
#include <print>
#include <string_view>
#include <type_traits>
#include <utility>

// Each probe reports what T was deduced to, as a type, through std::type_identity.
template <class T> constexpr std::type_identity<T> by_value(T) { return {}; }
template <class T> constexpr std::type_identity<T> by_lref(T&) { return {}; }
template <class T> constexpr std::type_identity<T> by_cref(const T&) { return {}; }
template <class T> constexpr std::type_identity<T> by_fwd(T&&) { return {}; }  // forwarding reference

#define DEDUCED(call) typename decltype(call)::type
#define CHECK(call, expected) static_assert(std::is_same_v<DEDUCED(call), expected>, #call " deduces " #expected)

int x = 0;
const int cx = 0;
const int& rx = x;
int arr[3] = {};
void fn(int) {}

// by value: top-level const and references are dropped; arrays and functions DECAY to pointers
CHECK(by_value(x), int);
CHECK(by_value(cx), int);
CHECK(by_value(rx), int);
CHECK(by_value(arr), int*);
CHECK(by_value(fn), void (*)(int));
// by T&: const is kept as part of T; arrays keep their size
CHECK(by_lref(cx), const int);
CHECK(by_lref(arr), int[3]);
CHECK(by_lref(fn), void(int));
// by const T&: const belongs to the parameter, T is unqualified
CHECK(by_cref(cx), int);
CHECK(by_cref(42), int);
// forwarding reference T&&: lvalues deduce T = U& (then & && collapses to &), rvalues deduce T = U
CHECK(by_fwd(x), int&);
CHECK(by_fwd(cx), const int&);
CHECK(by_fwd(42), int);
CHECK(by_fwd(std::move(x)), int);

// Reference collapsing: & + & = &, & + && = &, && + & = &, && + && = &&
template <class T> using add_rref = T&&;
static_assert(std::is_same_v<add_rref<int&>, int&>);
static_assert(std::is_same_v<add_rref<int&&>, int&&>);
static_assert(std::is_same_v<std::add_lvalue_reference_t<int&&>, int&>);

// auto follows template rules; auto&& is a forwarding reference; decltype(auto) keeps the expression's type exactly
auto a1 = cx;            // int
auto& a2 = cx;           // const int&
auto&& a3 = x;           // int&
auto&& a4 = 42;          // int&&
decltype(auto) a5 = rx;  // const int&
decltype(auto) a6 = (x); // int& (parenthesized: decltype((x)) is int&)
static_assert(std::is_same_v<decltype(a1), int> && std::is_same_v<decltype(a2), const int&> &&
              std::is_same_v<decltype(a3), int&> && std::is_same_v<decltype(a4), int&&> &&
              std::is_same_v<decltype(a5), const int&> && std::is_same_v<decltype(a6), int&>);

// The decltype(auto) return trap: returning a parenthesized local yields a dangling reference type.
decltype(auto) good() { int v = 1; return v; }      // int
#ifdef SHOW_DECLTYPE_AUTO_TRAP
decltype(auto) bad() { int v = 1; return (v); }     // int& to a dead local
#endif
static_assert(std::is_same_v<decltype(good()), int>);

int main() {
    std::println("all deduction static_asserts hold (24 probes)");
    std::println("a1={} a2={} a3={} a4={} a5={} a6={}", a1, a2, a3, a4, a5, a6);
}
```

Output (verified, both compilers; the program only runs if every `static_assert` held):

```text
all deduction static_asserts hold (24 probes)
a1=0 a2=0 a3=0 a4=42 a5=0 a6=0
```

The rows that matter in interviews:

* **`by_value(arr)` deduces `int*`**: arrays decay when passed by value, and the size is lost. **`by_lref(arr)` deduces
  `int[3]`**: by reference the extent survives. That is how `std::size(arr)` and `template <class T, size_t N> void f(T
  (&)[N])` work.
* **`by_fwd(x)` deduces `T = int&`**, not `int`. A forwarding reference encodes the argument's value category *in T*:
  `int&` for lvalues, `int` for rvalues. `std::forward<T>` reads it back: `static_cast<T&&>` gives `int& &&` → `int&`
  for lvalues and `int&&` for rvalues.
* **`T&&` is a forwarding reference only when `T` is deduced** for that very function template. `void f(std::vector<T>&&)`,
  a member of a class template where `T` is the class's parameter, or `const T&&` are plain rvalue references.
* **`decltype(auto) a6 = (x);` is `int&`**: the parentheses make it an expression, and `decltype((x))` of an lvalue is a
  reference.

The trap that follows from the last row, a function returning a reference to its own local (`-DSHOW_DECLTYPE_AUTO_TRAP`).
Both compilers reject it under `-Werror`, as GCC, then Clang:

```text
deduction.cpp:61:43: error: reference to local variable 'v' returned [-Werror=return-local-addr]
deduction.cpp:61:43: error: reference to stack memory associated with local variable 'v' returned [-Werror,-Wreturn-stack-address]
```

Without `-Werror` it is only a warning, and the function returns a dangling `int&`. `return v;` returns `int`;
`return (v);` returns `int&`. One pair of parentheses changes the return type.

### 1.2 When perfect forwarding is not perfect (Listing 6.2)

```cpp
// forward_fail.cpp - the cases where "perfect" forwarding is not perfect, and the fixes
#include <cstdint>
#include <memory>
#include <print>
#include <string>
#include <utility>
#include <vector>

void target_vec(const std::vector<int>& v) { std::println("  target_vec: size {}", v.size()); }
void target_ptr(int* p) { std::println("  target_ptr: {}", p == nullptr ? "null" : "non-null"); }
int twice(int x) { return 2 * x; }
double twice(double x) { return 2 * x; }  // overloaded: '&twice' has no single type
void target_fn(int (*f)(int)) { std::println("  target_fn: {}", f(21)); }
struct Header {
    std::uint32_t version : 4;         // a bit-field: no address, cannot bind to a non-const reference
    std::uint32_t flags : 28;
};
void target_int(int v) { std::println("  target_int: {}", v); }

template <class F, class... A>
void forward_to(F f, A&&... a) {       // the "perfect" wrapper
    f(std::forward<A>(a)...);
}

int main() {
    std::println("direct calls work:");
    target_vec({1, 2, 3});
    target_ptr(0);
    target_fn(twice);
    Header h{2, 7};
    target_int(h.version);

    std::println("forwarded, with the fixes:");
    forward_to(target_vec, std::vector<int>{1, 2, 3});        // braced lists have no type: spell it
    forward_to(target_ptr, nullptr);                           // 0 deduces int, not a null pointer
    forward_to(target_fn, static_cast<int (*)(int)>(twice));   // pick the overload explicitly
    forward_to(target_int, static_cast<int>(h.version));      // copy the bit-field into a prvalue
#ifdef SHOW_FORWARDING_FAILURES
    forward_to(target_vec, {1, 2, 3});   // braced-init-list: no type can be deduced for A
    forward_to(target_ptr, 0);           // A = int; int is not convertible to int*
    forward_to(target_fn, twice);        // overload set: deduction of F/A fails
    forward_to(target_int, h.version);   // A&& would bind a non-const reference to a bit-field
#endif
}
```

Output (verified, both compilers):

```text
direct calls work:
  target_vec: size 3
  target_ptr: null
  target_fn: 42
  target_int: 2
forwarded, with the fixes:
  target_vec: size 3
  target_ptr: null
  target_fn: 42
  target_int: 2
```

With `-DSHOW_FORWARDING_FAILURES`, GCC then Clang:

```text
forward_fail.cpp:39:15: error: too many arguments to function 'void forward_to(F, A&& ...) [with F = void (*)(const std::vector<int>&); A = {}]'
forward_fail.cpp:41:15: error: too many arguments to function 'void forward_to(F, A&& ...) [with F = void (*)(int (*)(int)); A = {}]'
forward_fail.cpp:42:30: error: cannot bind bit-field 'h.Header::version' to 'unsigned int&'
forward_fail.cpp:22:6: error: too few arguments to function
forward_fail.cpp:22:6: error: invalid conversion from 'int' to 'int*' [-fpermissive]
forward_fail.cpp:22:6: error: too few arguments to function
forward_fail.cpp:39:5: error: no matching function for call to 'forward_to'
forward_fail.cpp:41:5: error: no matching function for call to 'forward_to'
forward_fail.cpp:42:28: error: non-const reference cannot bind to bit-field 'version'
forward_fail.cpp:22:7: error: cannot initialize a parameter of type 'int *' with an rvalue of type 'int'
forward_fail.cpp:22:7: error: implicit conversion changes signedness: 'unsigned int' to 'int' [-Werror,-Wsign-conversion]
```

| Argument | Direct call | Forwarded | Why it fails | Fix |
|---|---|---|---|---|
| `{1, 2, 3}` | works | "too many arguments … A = {}" | a braced list has no type, so nothing can be deduced for `A` | name the type: `std::vector<int>{1,2,3}` (or `auto il = {1,2,3}` first) |
| `0` / `NULL` | null pointer | `int` → "invalid conversion from int to int*" | the literal is forwarded as an `int`, which is no longer a null pointer constant | `nullptr` |
| `twice` (overloaded) | picks by target type | no type for the overload set | deduction needs one type; an overload set has none | `static_cast<int(*)(int)>(twice)`, or a lambda wrapper |
| bit-field `h.version` | copies the value | "cannot bind bit-field to unsigned int&" | `A&&` would be a non-const reference to a bit-field, and bit-fields have no address | `static_cast<int>(h.version)` (a prvalue copy) |
| `static constexpr` member used before C++17 | works | link error (ODR-use of an undefined member) | binding a reference ODR-uses it | C++17 inline variables (`static constexpr` is implicitly `inline`) |

The general lesson: forwarding transmits *objects*. Anything that is not an object with a deducible type (braced lists,
overload sets, null-pointer-constant literals, bit-fields) loses information on the way.

---

## 2. Evolution table

| Feature | Standard (paper) | Notes |
|---|---|---|
| `auto`, `decltype`, rvalue references, forwarding (universal) references, reference collapsing, `std::forward` | C++11 (N2118, N2343) | the core rules above |
| `decltype(auto)`, return type deduction | C++14 (N3638) | the parenthesized-return trap |
| `auto x{1}` is `int` | C++17 (N3922, applied as a DR) | Folder 02 |
| class template argument deduction (CTAD) | C++17 (P0091) | Folder 02, file 02 |
| `static constexpr` members implicitly `inline` | C++17 (P0386) | removes the ODR-use link failure when forwarding |
| abbreviated function templates (`void f(auto x)`), `std::type_identity` | C++20 (P1141, P0887) | `type_identity_t<T>` blocks deduction for one parameter |
| `auto(x)` decay-copy | C++23 (P0849) | — |
| explicit object parameter (`this auto&& self`) | C++23 (P0847) | deducing the object's type and category (file 03) |
| pack indexing `Ts...[I]` | C++26 (P2662) | Folder 02, file 04 |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| a wrapper that forwards arguments | `template <class... A> void w(A... a) { f(a...); }` (copies) | `template <class... A> void w(A&&... a) { f(std::forward<A>(a)...); }` |
| forwarding twice | `g(std::forward<A>(a)); h(std::forward<A>(a));` (second use sees a moved-from object) | forward only on the last use |
| returning from a forwarding function | `decltype(auto) get() { return (member); }` by accident | `auto` for values; `decltype(auto)` only when reference semantics are intended |
| a parameter that must not participate in deduction | `void set(T value, T limit)` with mixed `int`/`long` | `void set(T value, std::type_identity_t<T> limit)` |
| constructors from forwarding references | `template <class T> Widget(T&&)` hijacks the copy constructor for non-const lvalues | constrain: `requires (!std::same_as<std::remove_cvref_t<T>, Widget>)` |

The last row is the classic: a `template <class T> Widget(T&&)` constructor is a better match than `Widget(const Widget&)`
for a non-const `Widget&` argument, so "copying" a `Widget` calls the template.

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| copy constructor not called when copying a non-const object | an unconstrained forwarding constructor wins | constrain the template; `-Wall` does not warn |
| a function returns a dangling reference | `decltype(auto)` + `return (x);` | `-Wreturn-local-addr` (GCC), `-Wreturn-stack-address` (Clang), both errors under `-Werror` |
| forwarding wrapper fails with `{...}`, `0`, an overloaded name or a bit-field | not deducible objects | the table in §1.2 |
| a value is moved-from unexpectedly | `std::forward` applied twice to the same argument | review rule: forward once |
| silently different types on Windows vs Linux | `auto x = some_long;` where `long` is 32-bit on Windows | fixed-width types in interfaces (Folder 05, file 03) |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "What is a forwarding reference?"</b></summary>

**Initial prompt.** "What does `T&&` mean in `template <class T> void f(T&& x)`?"

**L5 textbook answer.** "An rvalue reference, so `f` takes temporaries."

**Why L5 breaks.** In this position it is a *forwarding reference*: it binds to everything. For an lvalue `int x`, `T`
deduces to `int&`, and `int& &&` collapses to `int&` (Listing 6.1: `by_fwd(x)` → `int&`). For an rvalue, `T` is
`int`. The value category is encoded in `T`, which is what makes `std::forward<T>` possible. The L5 model mispredicts
overload resolution: a forwarding-reference overload beats `const T&` overloads for non-const lvalues.

**L7 principal defense.** "`T&&` with `T` deduced for that function template is a forwarding reference; every other `&&`
is an rvalue reference. `std::forward<T>(x)` is `static_cast<T&&>(x)`, which restores the original category through
collapsing. I constrain forwarding-reference overloads so they don't steal calls meant for copy constructors."
</details>

<details><summary><b>Chain 2 ⚡ "Why does my class template's T&& not bind lvalues?"</b></summary>

**Initial prompt.** "`template <class T> struct Box { void put(T&& v); };` Why doesn't `box.put(x)` compile for an lvalue
`x`?"

**L5 textbook answer.** "Because `T&&` needs `std::forward`."

**Why L5 breaks.** `T` is the *class* template parameter, already fixed when `put` is called (`Box<int>`), so `T&&` is
`int&&`, a plain rvalue reference. No deduction happens for `put`, so there is no forwarding. The fix is a member
template, `template <class U> void put(U&& v)`, or two overloads (`const T&` and `T&&`), which is what `vector::push_back`
does.

**L7 principal defense.** "Forwarding requires deduction in the same declaration. For containers I provide `const T&` and
`T&&` overloads (clear, no template bloat), plus an `emplace` member template with `Args&&...` for in-place
construction."
</details>

<details><summary><b>Chain 3 🔥 "auto vs decltype(auto)"</b></summary>

**Initial prompt.** "When would you use `decltype(auto)` as a return type?"

**L5 textbook answer.** "When you want to keep references."

**Why L5 breaks.** Correct, but the trap is the point: `decltype(auto)` applies `decltype` rules to the return
expression, so `return (v);` on a local returns `int&` to a dead object (Listing 6.1, rejected only because of
`-Werror`). It is also exact for xvalues: returning `std::move(member)` gives `T&&`, which can dangle if the object is
a temporary.

**L7 principal defense.** "`decltype(auto)` only in forwarding wrappers that must reproduce the wrapped call's return type
exactly (`return f(std::forward<A>(a)...)`), never with a parenthesized name. Everything else returns `auto` (by value)
or an explicit reference type that documents the lifetime."
</details>

<details><summary><b>Chain 4 🧊 "Why does forwarding {1, 2, 3} fail?"</b></summary>

**Initial prompt.** "`make_unique<std::vector<int>>({1, 2, 3})` doesn't compile, but `std::vector<int> v({1, 2, 3})`
does. Why?"

**L5 textbook answer.** "A bug in make_unique."

**Why L5 breaks.** A braced-init-list is not an expression with a type, so a function template parameter `A&&` cannot be
deduced from it. GCC reports "too many arguments … A = {}" and Clang "no matching function" (Listing 6.2). The direct call
works because the constructor's parameter type is known (`initializer_list<int>`).

**L7 principal defense.** "Spell the type (`std::vector<int>{1, 2, 3}`), or bind it first (`auto il = {1, 2, 3};
make_unique<std::vector<int>>(il)`). For my own factories I sometimes add an `initializer_list` overload, which is what
`std::make_optional` and `emplace` APIs do."
</details>

<details><summary><b>Chain 5 ⚡ "The constructor that ate the copy constructor"</b></summary>

**Initial prompt.** "Copying a non-const `Widget` calls my `template <class T> Widget(T&&)` instead of the copy constructor.
Why, and how do you fix it?"

**L5 textbook answer.** "Compiler bug; make the copy constructor explicit."

**Why L5 breaks.** Overload resolution prefers an exact match. For a non-const lvalue `w`, the template instantiates
`Widget(Widget&)`, which is a better match than `Widget(const Widget&)` (no added const). The template wins and probably
forwards a `Widget` into a member as if it were a value of another type.

**L7 principal defense.** "Constrain the template: `template <class T> requires (!std::same_as<std::remove_cvref_t<T>,
Widget>) Widget(T&&)`, which removes it from consideration for `Widget` arguments. This is why the standard library
constrains `std::function`'s, `std::optional`'s and `std::any`'s converting constructors."
</details>

<details><summary><b>Chain 6 🧊 "Arrays and templates"</b></summary>

**Initial prompt.** "Write a function template that returns the number of elements of a built-in array."

**L5 textbook answer.** `template <class T> size_t count(T a) { return sizeof(a) / sizeof(a[0]); }`

**Why L5 breaks.** By value, the array decays to a pointer (Listing 6.1: `by_value(arr)` → `int*`), so `sizeof(a)` is the
pointer size and the answer is 2 on a 64-bit target for any `int` array. It compiles cleanly.

**L7 principal defense.** "By reference, so the extent is part of the deduced type: `template <class T, std::size_t N>
constexpr std::size_t count(const T (&)[N]) noexcept { return N; }`, which is `std::size` (C++17). Better still, use
`std::array` or `std::span` and keep the size in the type."
</details>

<details><summary><b>Chain 7 🔥 "What does std::forward actually do?"</b></summary>

**Initial prompt.** "Implement `std::forward`."

**L5 textbook answer.** "It returns `std::move(x)` if `x` is an rvalue."

**Why L5 breaks.** `std::forward` cannot inspect `x`: inside the function, the named parameter is always an lvalue
(Folder 01, file 02). It needs the *template argument* `T`, which holds the original category, and it is just
`static_cast<T&&>(x)` (with an overload for rvalues that rejects forwarding an rvalue as an lvalue). That is why the call
must be `std::forward<T>(x)` with explicit `T`.

**L7 principal defense.** "`template <class T> constexpr T&& forward(std::remove_reference_t<T>& t) noexcept { return
static_cast<T&&>(t); }`, plus the rvalue overload with a `static_assert(!std::is_lvalue_reference_v<T>)`. The
`remove_reference_t` blocks deduction on purpose, so callers must supply `T`."
</details>

<details><summary><b>Chain 8 ⚡ "Deduction in mixed-type calls"</b></summary>

**Initial prompt.** "`template <class T> T clamp(T v, T lo, T hi)`; `clamp(x, 0, 100L)` doesn't compile. Fix it without
casts at the call site."

**L5 textbook answer.** "Use different template parameters for each."

**Why L5 breaks.** Three type parameters compile, but the return type and the comparisons become mixed (signed/unsigned
comparisons, narrowing on return). The intent is "`T` comes from the first argument; convert the others".

**L7 principal defense.** "`template <class T> T clamp(T v, std::type_identity_t<T> lo, std::type_identity_t<T> hi)`:
`type_identity_t` makes those parameters non-deduced contexts, so `T` comes only from `v`, and the bounds convert to it
(with `-Wconversion` warnings if lossy). That is exactly the C++20 tool for this problem."
</details>

---

## 6. Invariants checklist

- [ ] Wrappers take `A&&...` and forward each argument exactly once, on its last use.
- [ ] Forwarding-reference constructors and assignments are constrained against the class's own type.
- [ ] `decltype(auto)` only in exact-forwarding wrappers; never `return (name);`.
- [ ] `nullptr`, never `0`/`NULL`, for pointers.
- [ ] Parameters that must not drive deduction use `std::type_identity_t`.
- [ ] Array sizes come from references to arrays, `std::array` or `std::span`, never from `sizeof` on a parameter.

## 7. References

- Scott Meyers, *Effective Modern C++* (2014), items 1–4 (deduction), 24–30 (forwarding references and failures).
- N2118 / N2343 (rvalue references, `decltype`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2006/n2118.html>
- N3638 (return type deduction): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2013/n3638.html>
- P0887R1 (`std::type_identity`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2018/p0887r1.pdf>
- cppreference, template argument deduction: <https://en.cppreference.com/w/cpp/language/template_argument_deduction>
