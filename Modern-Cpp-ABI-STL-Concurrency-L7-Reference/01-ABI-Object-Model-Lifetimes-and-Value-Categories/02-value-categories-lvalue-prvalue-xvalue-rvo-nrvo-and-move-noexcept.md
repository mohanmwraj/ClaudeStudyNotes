# 02 · Value categories, RVO/NRVO, implicit move, the call ABI, and `noexcept` moves

> **Scope.** The type system decides *which constructor runs*. The ABI decides *where the bytes travel*. This
> file connects the two: value categories (lvalue/xvalue/prvalue) proven by the compiler; C++17 guaranteed
> elision versus optional NRVO; the four revisions of implicit move; how x86-64 SysV and AArch64 AAPCS64 pass
> and return objects, and why `std::unique_ptr` by value is not free; and why a missing `noexcept` turns
> `vector` growth from moves into copies.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 2.1 | `valcat.cpp` | 38 expressions classified; every row is a `static_assert` | compiles + runs on GCC 16.2 and Clang 21.1 |
| 2.2 | `elision.cpp` | copy/move counts for 11 return patterns, in C++17/20/23 and `-fno-elide-constructors` | 5 builds × 2 compilers, plus 2 expected diagnostics |
| 2.3 | `move_traps.cpp` | three ways `std::move` copies | run, both compilers |
| 2.4 | `sret_abi.cpp` | registers vs hidden result pointer (RDI / **X8**); `unique_ptr` by value; `[[clang::trivial_abi]]` | `-O3` asm x86-64 + AArch64 |
| 2.5 | `move_noexcept.cpp` | 1M-element growth: 0 vs 1,048,575 copies; library `noexcept` table; the libstdc++ `deque` exception | run, both libraries |
| 2.6 | `noexcept_cost.cpp` | landing pads, `__clang_call_terminate`, and a lost tail call | `-O3` asm x86-64 + AArch64 |
| 2.7 | `order_blueprint.cpp` | instrumented value type: 65,532 hidden copies vs 0 | run, both compilers |

**Verification line.** Same harness as file 01: Clang 21.1.0 `-O3` for `x86_64-linux-gnu` / `aarch64-linux-gnu`,
and native runs on Windows x86-64 with GCC 16.2 (libstdc++) and Clang 21.1 (libc++), `-O2 -Wall -Wextra
-Wpedantic -Werror -Wshadow -Wconversion -Wsign-conversion`. Timings are single runs on a laptop and are
labelled as such.

---

## 1. First principles

### 1.1 Two properties, three categories

Since C++11, every expression has a type and a value category. The categories come from two yes/no
questions:

```text
                         has identity?          can be moved from?
   lvalue                yes (a name, *p)       no (unless you cast)
   xvalue                yes                    yes (std::move(x), a.m on an xvalue, f() returning T&&)
   prvalue               no (C++17: not even    yes
                         an object yet)

        expression
        /        \
   glvalue      rvalue
   /     \      /    \
lvalue   xvalue      prvalue          glvalue = lvalue ∪ xvalue;  rvalue = xvalue ∪ prvalue
```

The C++17 change (P0135R1) is the one that matters for code generation. **A prvalue is not a temporary
object; it is a recipe for initializing one.** Its *result object* is whatever the context supplies: the
variable being declared, the caller's return slot, or a parameter. Only when a prvalue is used as a glvalue
(member access, binding to a reference, discarding it) does *temporary materialization* create an object,
and that object is an **xvalue**. That rule explains the surprising rows below (`S{}.m` is an xvalue).

`decltype((e))` exposes the category: `T&` for lvalues, `T&&` for xvalues, plain `T` for prvalues. The listing
turns that into a compile-time proof:

```cpp
// valcat.cpp - value categories proven by the compiler: decltype((e)) maps lvalue->T&, xvalue->T&&, prvalue->T
#include <print>
#include <string>
#include <string_view>
#include <utility>

template <class T> constexpr std::string_view category = "prvalue";
template <class T> constexpr std::string_view category<T&> = "lvalue";
template <class T> constexpr std::string_view category<T&&> = "xvalue";

// Each row is checked at compile time (static_assert) and printed at run time.
#define ROW(expected, ...)                                                                    \
    static_assert(category<decltype((__VA_ARGS__))> == expected, "wrong category: " #__VA_ARGS__); \
    std::println("  {:<40} {}", #__VA_ARGS__, category<decltype((__VA_ARGS__))>)

struct S {
    int m = 0;
    static inline int sm = 0;
    void probe() const {
        ROW("prvalue", this);                   // 'this' is a prvalue pointer
        ROW("lvalue", *this);
        ROW("lvalue", m);                       // const int lvalue inside a const member function
    }
};
enum class Color { Red };
int f_val();
int& f_lref();
int&& f_rref();
void g();

int main() {
    int x = 0;
    int* p = &x;
    int&& rr = 1;
    int arr[2] = {};
    S s;
    std::println("expression                                 category");
    ROW("lvalue", x);
    ROW("prvalue", 42);
    ROW("lvalue", "hi");                        // string literals are lvalues (arrays with static storage)
    ROW("prvalue", x + 1);
    ROW("lvalue", ++x);
    ROW("prvalue", x++);
    ROW("lvalue", x = 5);
    ROW("lvalue", *p);
    ROW("prvalue", &x);
    ROW("xvalue", std::move(x));
    ROW("xvalue", static_cast<int&&>(x));
    ROW("lvalue", std::forward<int&>(x));
    ROW("xvalue", std::forward<int>(x));
    ROW("lvalue", rr);                          // a NAMED rvalue reference is an lvalue
    ROW("prvalue", f_val());
    ROW("lvalue", f_lref());
    ROW("xvalue", f_rref());
    ROW("lvalue", s.m);
    ROW("xvalue", std::move(s).m);              // member of an xvalue
    ROW("xvalue", S{}.m);                       // prvalue S{} is materialized -> its member is an xvalue
    ROW("lvalue", S{}.sm);                      // static members are lvalues whatever the object expression
    ROW("prvalue", S{});
    ROW("lvalue", arr[0]);
    ROW("xvalue", std::move(arr)[0]);
    ROW("lvalue", true ? x : x);
    ROW("prvalue", true ? x : 1);
    ROW("xvalue", true ? std::move(x) : std::move(x));
    ROW("xvalue", (x, std::move(x)));
    ROW("prvalue", Color::Red);
    ROW("prvalue", nullptr);
    ROW("prvalue", [] { return 1; });
    ROW("lvalue", g);                           // function names are lvalues
    ROW("lvalue", std::move(g));                // ...and rvalue references to functions are lvalues too
    ROW("prvalue", auto(x));                    // C++23 decay-copy
    ROW("prvalue", std::string{} + "a");
    s.probe();
}

int f_val() { return 0; }
int& f_lref() { static int i = 0; return i; }
int&& f_rref() { static int i = 0; return std::move(i); }
void g() {}
```

Output (verified, identical on both compilers; all 38 `static_assert`s hold):

```text
expression                                 category
  x                                        lvalue
  42                                       prvalue
  "hi"                                     lvalue
  x + 1                                    prvalue
  ++x                                      lvalue
  x++                                      prvalue
  x = 5                                    lvalue
  *p                                       lvalue
  &x                                       prvalue
  std::move(x)                             xvalue
  static_cast<int&&>(x)                    xvalue
  std::forward<int&>(x)                    lvalue
  std::forward<int>(x)                     xvalue
  rr                                       lvalue
  f_val()                                  prvalue
  f_lref()                                 lvalue
  f_rref()                                 xvalue
  s.m                                      lvalue
  std::move(s).m                           xvalue
  S{}.m                                    xvalue
  S{}.sm                                   lvalue
  S{}                                      prvalue
  arr[0]                                   lvalue
  std::move(arr)[0]                        xvalue
  true ? x : x                             lvalue
  true ? x : 1                             prvalue
  true ? std::move(x) : std::move(x)       xvalue
  (x, std::move(x))                        xvalue
  Color::Red                               prvalue
  nullptr                                  prvalue
  [] { return 1; }                         prvalue
  g                                        lvalue
  std::move(g)                             lvalue
  auto(x)                                  prvalue
  std::string{} + "a"                      prvalue
  this                                     prvalue
  *this                                    lvalue
  m                                        lvalue
```

The rows people get wrong in interviews: a **named rvalue reference is an lvalue** (`rr`), which is why
`std::forward` and `std::move` exist; **string literals are lvalues**; a **member of a prvalue is an xvalue**
(materialization); **static members are lvalues** whatever the object expression; and rvalue references to
*functions* are lvalues (`std::move(g)`).

### 1.2 Where the result object lives: the elision state machine

For `T r = f();` the caller reserves storage for `r` and passes its address to `f` (§1.4 shows the register).
Everything about elision is the question: *can the callee build its result directly in that storage?*

```text
 return expression in f()         result object built...                      standard says
 -------------------------------  ------------------------------------------  ---------------------------
 return T{...};       (prvalue)   directly in the caller's slot               C++17: guaranteed (no ctor
                                                                              needs to exist)
 return local;        (one name   the local IS the caller's slot (NRVO)       permitted, not guaranteed
   on every path)
 return a; / return b;            cannot be both -> treat the name as an     implicit move (C++11),
   (different locals)             rvalue: MOVE into the slot                 extended in C++14/20/23
 return param;                    parameters live in the caller's frame:     implicit move
                                  MOVE
 return cond ? a : b;             the operand is an lvalue *expression*,     COPY
                                  not a name: no implicit move
 return local.member;             a subobject is not a candidate: COPY       write std::move(local.member)
 return std::move(local);         an xvalue is not a name: NRVO impossible,  1 move; warned by both
                                  MOVE                                        compilers
```

```cpp
// elision.cpp - RVO (guaranteed), NRVO (permitted), implicit move, and the patterns that silently copy
// printf instead of std::print so the same file builds as C++17, C++20 and C++23.
#include <cstdio>
#include <mutex>
#include <utility>

struct Counts {
    int copies = 0, moves = 0;
};
Counts g;

struct T {
    int v = 0;
    T() = default;
    T(const T& o) : v(o.v) { ++g.copies; }
    T(T&& o) noexcept : v(o.v) { ++g.moves; }
    T& operator=(const T&) = default;
    T& operator=(T&&) = default;
    ~T() = default;
};

// Prevent the optimizer from proving which branch runs.
bool opaque(int i) {
    static volatile int sink = 0;
    sink = sink + i;
    return (sink & 1) == 0;
}

T rvo() { return T{}; }                               // prvalue: no temporary exists (C++17 guaranteed)
T nrvo() {
    T t;
    t.v = 1;
    return t;                                         // NRVO: permitted, both compilers do it
}
T nrvo_same_var(int i) {
    T t;
    if (opaque(i)) {
        t.v = 2;
        return t;
    }
    return t;                                         // every return names the same variable: NRVO still possible
}
T two_locals(int i) {
    T a, b;
    if (opaque(i)) return a;
    return b;                                         // which object is the result is unknown: implicit MOVE
}
#ifndef SHOW_PESSIMIZING_MOVE                         // both compilers reject this under -Werror; see the diagnostic
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wpessimizing-move"
#endif
T pessimizing(int) {
    T t;
    return std::move(t);                              // xvalue is not a name: NRVO is impossible -> 1 move
}
#ifndef SHOW_PESSIMIZING_MOVE
#pragma GCC diagnostic pop
#endif
T from_param(T p) { return p; }                       // parameters are never elided: implicit move
T ternary(int i) {
    T a, b;
    return opaque(i) ? a : b;                         // the conditional is an lvalue expression: COPY
}
T ternary_fixed(int i) {
    T a, b;
    if (opaque(i)) return a;                          // two returns -> two implicit moves, no copy
    return b;
}
struct Holder {
    T t;
};
T member_of_local() {
    Holder h;
    return h.t;                                       // a subobject is not an implicitly movable entity: COPY
}
T member_of_local_fixed() {
    Holder h;
    return std::move(h.t);                            // here std::move is correct
}
T from_rvalue_ref(T&& r) { return r; }               // C++20 (P1825): implicitly movable -> move
#ifdef SHOW_P2266_BREAK
T& forward_ref(T&& r) { return r; }                   // OK in C++20; ill-formed in C++23 (P2266: r is an xvalue)
#endif

struct Pinned {                                       // neither copyable nor movable
    int v = 7;
    Pinned() = default;
    Pinned(const Pinned&) = delete;
    Pinned(Pinned&&) = delete;
};
Pinned make_pinned() { return Pinned{}; }             // fine since C++17: no copy/move is even considered
std::mutex make_mutex() { return {}; }

template <class F>
void report(const char* label, F f) {
    g = {};
    T r = f();
    std::printf("  %-34s copies=%d moves=%d\n", label, g.copies, g.moves);
    (void)r;
}

int main() {
    report("return T{}", [] { return rvo(); });
    report("return local (NRVO)", [] { return nrvo(); });
    report("two returns, same local", [] { return nrvo_same_var(0); });
    report("two returns, two locals", [] { return two_locals(0); });
    report("return std::move(local)", [] { return pessimizing(0); });
    report("return by-value parameter", [] { return from_param(T{}); });
    report("return cond ? a : b", [] { return ternary(0); });
    report("if/return a; return b", [] { return ternary_fixed(0); });
    report("return local.member", [] { return member_of_local(); });
    report("return std::move(local.member)", [] { return member_of_local_fixed(); });
    report("return T&& parameter", [] { return from_rvalue_ref(T{}); });
    Pinned pin = make_pinned();
    std::mutex m = make_mutex();
    std::lock_guard lk(m);
    std::printf("  non-movable Pinned from a factory: v=%d\n", pin.v);
}
```

C++23 build (verified; GCC 16.2 and Clang 21.1 print the same; the C++20 build is identical):

```text
  return T{}                         copies=0 moves=0
  return local (NRVO)                copies=0 moves=0
  two returns, same local            copies=0 moves=0
  two returns, two locals            copies=0 moves=1
  return std::move(local)            copies=0 moves=1
  return by-value parameter          copies=0 moves=1
  return cond ? a : b                copies=1 moves=0
  if/return a; return b              copies=0 moves=1
  return local.member                copies=1 moves=0
  return std::move(local.member)     copies=0 moves=1
  return T&& parameter               copies=0 moves=1
  non-movable Pinned from a factory: v=7
```

With `-fno-elide-constructors` (both compilers agree). The prvalue row stays at zero because C++17 elision is
not an optimization the flag can turn off. NRVO rows become moves:

```text
  return T{}                         copies=0 moves=0
  return local (NRVO)                copies=0 moves=1
  two returns, same local            copies=0 moves=1
  two returns, two locals            copies=0 moves=1
  return std::move(local)            copies=0 moves=1
  return by-value parameter          copies=0 moves=1
  return cond ? a : b                copies=1 moves=0
  if/return a; return b              copies=0 moves=1
  return local.member                copies=1 moves=0
  return std::move(local.member)     copies=0 moves=1
  return T&& parameter               copies=0 moves=1
  non-movable Pinned from a factory: v=7
```

**C++17 build: the compilers disagree** on the last row. GCC applies the C++20 implicit-move rule (P1825) only
from C++20. Clang applies it in C++17 mode as well:

```text
GCC 16.2, -std=c++17:
  return T{}                         copies=0 moves=0
  return local (NRVO)                copies=0 moves=0
  two returns, same local            copies=0 moves=0
  two returns, two locals            copies=0 moves=1
  return std::move(local)            copies=0 moves=1
  return by-value parameter          copies=0 moves=1
  return cond ? a : b                copies=1 moves=0
  if/return a; return b              copies=0 moves=1
  return local.member                copies=1 moves=0
  return std::move(local.member)     copies=0 moves=1
  return T&& parameter               copies=1 moves=0
  non-movable Pinned from a factory: v=7
```

```text
Clang 21.1, -std=c++17:
  return T{}                         copies=0 moves=0
  return local (NRVO)                copies=0 moves=0
  two returns, same local            copies=0 moves=0
  two returns, two locals            copies=0 moves=1
  return std::move(local)            copies=0 moves=1
  return by-value parameter          copies=0 moves=1
  return cond ? a : b                copies=1 moves=0
  if/return a; return b              copies=0 moves=1
  return local.member                copies=1 moves=0
  return std::move(local.member)     copies=0 moves=1
  return T&& parameter               copies=0 moves=1
  non-movable Pinned from a factory: v=7
```

Both compilers diagnose the pessimizing move under `-Werror` (the listing suppresses it with a pragma so the
program can still run):

```text
elision.cpp:54:21: error: moving a local object in a return statement prevents copy elision [-Werror=pessimizing-move]
elision.cpp:54:12: error: moving a local object in a return statement prevents copy elision [-Werror,-Wpessimizing-move]
```

C++23's P2266 ("simpler implicit move") makes the *id-expression* in `return r;` an xvalue when `r` is an
implicitly movable entity. That has a sharp edge: a function that returns `T&` from a `T&&` parameter
**compiles in C++20 and is ill-formed in C++23**. The C++20 build with `-DSHOW_P2266_BREAK` compiled and ran.
The C++23 build fails on both compilers:

```text
elision.cpp:82:32: error: cannot bind non-const lvalue reference of type 'T&' to an rvalue of type 'T'
elision.cpp:82:32: error: non-const lvalue reference to type 'T' cannot bind to a temporary of type 'T'
```

### 1.3 `std::move` is only a cast

`std::move(x)` is `static_cast<std::remove_reference_t<T>&&>(x)`. Whether anything moves is decided by
**overload resolution on the result**, and three common shapes select the copy constructor:

```cpp
// move_traps.cpp - std::move is a cast; three ways it silently degrades to a copy
#include <print>
#include <type_traits>
#include <utility>
#include <vector>

struct Counts {
    int copies = 0, moves = 0;
};
Counts g;

struct Payload {
    std::vector<int> data = std::vector<int>(1000);
    Payload() = default;
    Payload(const Payload& o) : data(o.data) { ++g.copies; }
    Payload(Payload&& o) noexcept : data(std::move(o.data)) { ++g.moves; }
    Payload& operator=(const Payload&) = default;
    Payload& operator=(Payload&&) = default;
};

// Trap 2: a user-declared destructor (even "= default") suppresses the implicit move constructor.
// The copy constructor is still implicitly declared, so "moving" a Legacy copies its members.
struct Legacy {
    Payload p;
    ~Legacy() {}                      // added "for logging" - and every move became a copy
};
struct RuleOfZero {
    Payload p;                        // no special members declared: implicit move works
};

struct Owner {
    Payload p;
    // Trap 3: in a const member function, p is const, std::move(p) is const Payload&&,
    // which binds to the copy constructor.
    Payload take() const { return std::move(p); }
    Payload take_fixed() && { return std::move(p); }  // rvalue-qualified: the caller says "I'm done with you"
};

template <class F>
void report(const char* label, F f) {
    g = {};
    f();
    std::println("  {:<42} copies={} moves={}", label, g.copies, g.moves);
}

int main() {
    // is_move_constructible is TRUE for Legacy: a const Legacy& copy constructor accepts rvalues.
    static_assert(std::is_move_constructible_v<Legacy>);
    std::println("is_move_constructible:         Legacy={} RuleOfZero={}", std::is_move_constructible_v<Legacy>,
                 std::is_move_constructible_v<RuleOfZero>);
    std::println("is_nothrow_move_constructible: Legacy={} RuleOfZero={}",
                 std::is_nothrow_move_constructible_v<Legacy>, std::is_nothrow_move_constructible_v<RuleOfZero>);
    report("const Payload c; Payload x = std::move(c);", [] {
        const Payload c;
        Payload x = std::move(c);     // Trap 1: const T&& -> copy constructor
    });
    report("Legacy a; Legacy b = std::move(a);", [] {
        Legacy a;
        Legacy b = std::move(a);
    });
    report("RuleOfZero a; RuleOfZero b = std::move(a);", [] {
        RuleOfZero a;
        RuleOfZero b = std::move(a);
    });
    report("owner.take()  (const member function)", [] {
        Owner o;
        Payload x = o.take();
    });
    report("std::move(owner).take_fixed()", [] {
        Owner o;
        Payload x = std::move(o).take_fixed();
    });
}
```

Output (verified, both compilers):

```text
is_move_constructible:         Legacy=true RuleOfZero=true
is_nothrow_move_constructible: Legacy=false RuleOfZero=true
  const Payload c; Payload x = std::move(c); copies=1 moves=0
  Legacy a; Legacy b = std::move(a);         copies=1 moves=0
  RuleOfZero a; RuleOfZero b = std::move(a); copies=0 moves=1
  owner.take()  (const member function)      copies=1 moves=0
  std::move(owner).take_fixed()              copies=0 moves=1
```

Trap 2 is the expensive one in real code bases. Adding `~Legacy() {}`, or even `~Legacy() = default;` written
in the class body, removes the implicitly declared move constructor. The implicitly declared copy constructor
remains, and it accepts rvalues. So `is_move_constructible_v<Legacy>` is still **true**: the trait asks "can
this be constructed from an rvalue", not "does it have a move constructor". Every `std::move(legacy)` in the
code base, every `vector<Legacy>` reallocation and every `return` now deep-copies, and no test fails. The type is
also no longer nothrow-move-constructible, which turns `vector` growth into copies as well (§1.5).

### 1.4 The call ABI: registers, the hidden result pointer, and "non-trivial for the purposes of calls"

```cpp
// sret_abi.cpp - how values cross a call: registers vs hidden result pointer, and "non-trivial for calls"
#include <cstdint>
#include <memory>

struct Pair { std::int64_t a, b; };                 // 16 B, trivially copyable -> RAX:RDX / X0:X1
struct Big { std::int64_t a, b, c; };               // 24 B -> returned in memory: hidden pointer RDI / X8
struct Tracked {                                    // 8 B, but a user-provided destructor makes it
    std::int64_t a;                                 // non-trivial for the purposes of calls -> memory
    ~Tracked();
};
struct [[clang::trivial_abi]] OwnedPtr {            // like unique_ptr, but opted into register passing
    std::int64_t* p;
    explicit OwnedPtr(std::int64_t* q) : p(q) {}
    OwnedPtr(OwnedPtr&& o) noexcept : p(o.p) { o.p = nullptr; }
    ~OwnedPtr() { delete p; }
};

Pair make_pair16(std::int64_t x) { return {x, x + 1}; }
Big make_big(std::int64_t x) { return {x, x + 1, x + 2}; }
Tracked make_tracked(std::int64_t x) { return {x}; }

// Callee side: a by-value unique_ptr arrives as a POINTER to a caller-owned temporary.
std::int64_t take_uptr(std::unique_ptr<std::int64_t> p) { return *p; }
std::int64_t take_raw(std::int64_t* p) { return *p; }
// trivial_abi: the pointer itself arrives in RDI / X0, and the CALLEE runs the destructor.
std::int64_t take_owned(OwnedPtr p) { return *p.p; }

// Caller side, against callees in another TU (so nothing inlines):
std::int64_t sink_uptr(std::unique_ptr<std::int64_t> p);
std::int64_t sink_owned(OwnedPtr p);
// unique_ptr: build the temporary in a stack slot, pass its address, then the CALLER destroys it
// (null test + delete) after the call returns - plus a landing pad in case the callee throws.
std::int64_t call_uptr(std::int64_t* raw) { return sink_uptr(std::unique_ptr<std::int64_t>(raw)); }
// trivial_abi: pass the raw pointer in a register; nothing left to destroy on the caller side.
std::int64_t call_owned(std::int64_t* raw) { return sink_owned(OwnedPtr(raw)); }
```

Clang `-O3`, x86-64 SysV:

```asm
_Z11make_pair16l:                  # make_pair16(long)
	movq	%rdi, %rax
	leaq	1(%rdi), %rdx
	retq

_Z8make_bigl:                      # make_big(long)
	movq	%rdi, %rax
	movq	%rsi, (%rdi)
	leaq	1(%rsi), %rcx
	movq	%rcx, 8(%rdi)
	addq	$2, %rsi
	movq	%rsi, 16(%rdi)
	retq

_Z12make_trackedl:                 # make_tracked(long)
	movq	%rdi, %rax
	movq	%rsi, (%rdi)
	retq

_Z9take_uptrNSt3__110unique_ptrIlNS_14default_deleteIlEEEE: # take_uptr(std::__1::unique_ptr<long, std::__1::default_delete<long> >)
	movq	(%rdi), %rax
	movq	(%rax), %rax
	retq

_Z8take_rawPl:                     # take_raw(long*)
	movq	(%rdi), %rax
	retq

_Z10take_owned8OwnedPtr:           # take_owned(OwnedPtr)
	pushq	%rbx
	movq	(%rdi), %rbx
	movl	$8, %esi
	callq	_ZdlPvm@PLT                          # operator delete(void*, unsigned long)
	movq	%rbx, %rax
	popq	%rbx
	retq

_Z9call_uptrPl:                    # call_uptr(long*)
	pushq	%rbx
	subq	$16, %rsp
	movq	%rdi, 8(%rsp)
	leaq	8(%rsp), %rdi
	callq	_Z9sink_uptrNSt3__110unique_ptrIlNS_14default_deleteIlEEEE@PLT # sink_uptr(std::__1::unique_ptr<long, std::__1::default_delete<long> >)
	movq	8(%rsp), %rdi
	movq	$0, 8(%rsp)
	testq	%rdi, %rdi
	je	.LBB6_3
	movl	$8, %esi
	movq	%rax, %rbx
	callq	_ZdlPvm@PLT                          # operator delete(void*, unsigned long)
	movq	%rbx, %rax
.LBB6_3:
	addq	$16, %rsp
	popq	%rbx
	retq
.Ltmp2:                                     # landing pad (entered only via the LSDA)
	movq	%rax, %rbx
	movq	8(%rsp), %rdi
	movq	$0, 8(%rsp)
	testq	%rdi, %rdi
	je	.LBB6_6
	movl	$8, %esi
	callq	_ZdlPvm@PLT                          # operator delete(void*, unsigned long)
.LBB6_6:
	movq	%rbx, %rdi
	callq	_Unwind_Resume@PLT

_Z10call_ownedPl:                  # call_owned(long*)
	jmp	_Z10sink_owned8OwnedPtr@PLT            # sink_owned(OwnedPtr)
```

Clang `-O3`, AArch64 AAPCS64:

```asm
_Z11make_pair16l:                  // make_pair16(long)
	add	x1, x0, #1
	ret

_Z8make_bigl:                      // make_big(long)
	adrp	x9, .LCPI1_0
	dup	v0.2d, x0
	str	x0, [x8]
	ldr	q1, [x9, :lo12:.LCPI1_0]
	add	v0.2d, v0.2d, v1.2d
	stur	q0, [x8, #8]
	ret

_Z12make_trackedl:                 // make_tracked(long)
	str	x0, [x8]
	ret

_Z9take_uptrNSt3__110unique_ptrIlNS_14default_deleteIlEEEE: // take_uptr(std::__1::unique_ptr<long, std::__1::default_delete<long> >)
	ldr	x8, [x0]
	ldr	x0, [x8]
	ret

_Z8take_rawPl:                     // take_raw(long*)
	ldr	x0, [x0]
	ret

_Z10take_owned8OwnedPtr:           // take_owned(OwnedPtr)
	stp	x30, x19, [sp, #-16]!
	ldr	x19, [x0]
	mov	w1, #8
	bl	_ZdlPvm                                 // operator delete(void*, unsigned long)
	mov	x0, x19
	ldp	x30, x19, [sp], #16
	ret

_Z9call_uptrPl:                    // call_uptr(long*)
	sub	sp, sp, #32
	stp	x30, x19, [sp, #16]
	str	x0, [sp, #8]
	add	x0, sp, #8
	bl	_Z9sink_uptrNSt3__110unique_ptrIlNS_14default_deleteIlEEEE // sink_uptr(std::__1::unique_ptr<long, std::__1::default_delete<long> >)
	ldr	x8, [sp, #8]
	str	xzr, [sp, #8]
	cbz	x8, .LBB6_3
	mov	x19, x0
	mov	x0, x8
	mov	w1, #8
	bl	_ZdlPvm                                 // operator delete(void*, unsigned long)
	mov	x0, x19
.LBB6_3:
	ldp	x30, x19, [sp, #16]
	add	sp, sp, #32
	ret
.Ltmp2:                                     // landing pad (entered only via the LSDA)
	mov	x19, x0
	ldr	x0, [sp, #8]
	str	xzr, [sp, #8]
	cbz	x0, .LBB6_6
	mov	w1, #8
	bl	_ZdlPvm                                 // operator delete(void*, unsigned long)
.LBB6_6:
	mov	x0, x19
	bl	_Unwind_Resume

_Z10call_ownedPl:                  // call_owned(long*)
	b	_Z10sink_owned8OwnedPtr                  // sink_owned(OwnedPtr)
```

The rules the listing exercises:

| Type | x86-64 SysV | AArch64 AAPCS64 | Itanium C++ ABI rule |
|---|---|---|---|
| `Pair` (16 B, trivially copyable) | returned in **RAX:RDX** | returned in **X0:X1** | C struct rules apply |
| `Big` (24 B) | caller passes a hidden pointer in **RDI**; callee returns it in **RAX** | caller passes it in **X8** (the indirect result register); X0 is *not* the pointer on return | C struct rules apply |
| `Tracked` (8 B + user destructor) | hidden pointer in RDI, even though it is 8 bytes | X8 | **non-trivial for the purposes of calls** → always memory |
| `std::unique_ptr<T>` parameter | `take_uptr` receives a **pointer to** a caller temporary (`mov (%rdi),%rax; mov (%rax),%rax`) | same (`ldr x8,[x0]; ldr x0,[x8]`) | passed by invisible reference; **the caller destroys it** after the call |
| `[[clang::trivial_abi]] OwnedPtr` | the pointer itself in RDI; the callee runs `delete` | X0 | type opts into register passing; **callee** destroys |

The caller side is the real cost. `call_uptr` has to spill the pointer to a stack slot, pass its address, then,
**after** the callee returns, reload it, null-test it, and possibly call `operator delete`. It also needs a
landing pad that does the same during unwinding. That is 20+ instructions. `call_owned` is one tail jump.
This reproduces the point of Chandler Carruth's CppCon 2019 talk "There Are No Zero-cost Abstractions" with
current compilers. libc++ can apply the attribute to `unique_ptr` and `shared_ptr` itself
(`_LIBCPP_ABI_ENABLE_UNIQUE_PTR_TRIVIAL_ABI` and `_LIBCPP_ABI_ENABLE_SHARED_PTR_TRIVIAL_ABI`). Its 21.1
headers enable both only in the unstable ABI v2, because the change breaks the ABI.

**ARM64-specific consequence.** X8 is not an argument register. FFI code (Rust `extern "C"`, Swift, JNI shims,
hand-written assembly) that believes a C++ function returns `Tracked` in X0 reads garbage. Worse, a callee that
was told the result is "returned in registers" never writes the caller's X8 buffer, while the C++ callee
**writes through X8**, which holds whatever the FFI caller left there. That is a memory write to an arbitrary
address. On x86-64 the same mismatch shifts every argument by one register (RDI holds the hidden pointer), so it
usually fails loudly. On AArch64 the arguments stay in place and only the write is wrong, so it fails silently.

### 1.5 Why `vector` copies when the move constructor might throw

`vector::push_back` gives the **strong exception guarantee**: if it throws, the vector is unchanged. During
reallocation it must transfer N old elements into new storage:

```text
 transfer step i fails (throws)          with COPY: old buffer intact -> free new buffer, rethrow:
                                                     strong guarantee holds
                                          with MOVE: elements 0..i-1 already moved-from; moving them
                                                     back can throw too -> strong guarantee impossible
 => std::move_if_noexcept: move only if the move constructor is noexcept OR there is no copy constructor
```

```cpp
// move_noexcept.cpp - why vector growth COPIES unless the move constructor is noexcept (strong guarantee)
#include <chrono>
#include <deque>
#include <functional>
#include <list>
#include <map>
#include <optional>
#include <print>
#include <set>
#include <string>
#include <type_traits>
#include <unordered_map>
#include <variant>
#include <vector>

struct Counts {
    long copies = 0, moves = 0;
};
Counts g;

template <bool NothrowMove>
struct Item {
    std::string payload;              // 40 chars: heap-allocated in every std::string implementation
    explicit Item(int i) : payload(40, char('a' + i % 26)) {}
    Item(const Item& o) : payload(o.payload) { ++g.copies; }
    Item(Item&& o) noexcept(NothrowMove) : payload(std::move(o.payload)) { ++g.moves; }
    Item& operator=(const Item&) = default;
    Item& operator=(Item&&) = default;
    ~Item() = default;
};

struct Wrapper {                       // defaulted move: noexcept only if every member's move is
    Item<false> inner{0};
    Wrapper() = default;
    Wrapper(const Wrapper&) = default;
    Wrapper(Wrapper&&) = default;
};
struct WrapperFixed {
    Item<false> inner{0};
    WrapperFixed() = default;
    WrapperFixed(const WrapperFixed&) = default;
    WrapperFixed(WrapperFixed&&) noexcept = default;  // a promise: if Item's move throws, std::terminate
};

template <class T>
void grow(const char* label, int n) {
    g = {};
    std::vector<T> v;
    auto t0 = std::chrono::steady_clock::now();
    for (int i = 0; i < n; ++i) v.emplace_back(i);
    auto t1 = std::chrono::steady_clock::now();
    std::println("  {:<26} copies={:>7} moves={:>7}  {:6.1f} ms", label, g.copies, g.moves,
                 std::chrono::duration<double, std::milli>(t1 - t0).count());
}

#define NX(...) std::println("  {:<34} {}", #__VA_ARGS__, std::is_nothrow_move_constructible_v<__VA_ARGS__>)

int main() {
    constexpr int kN = 1'000'000;
    std::println("vector<T>::emplace_back x {} (capacity doubles ~20 times):", kN);
    grow<Item<true>>("Item<noexcept move>", kN);
    grow<Item<false>>("Item<throwing move>", kN);
    std::println("defaulted move of a member with a throwing move:");
    static_assert(!std::is_nothrow_move_constructible_v<Wrapper>);
    static_assert(std::is_nothrow_move_constructible_v<WrapperFixed>);
    std::println("  Wrapper      nothrow-move: {}", std::is_nothrow_move_constructible_v<Wrapper>);
    std::println("  WrapperFixed nothrow-move: {}", std::is_nothrow_move_constructible_v<WrapperFixed>);
    std::println("is_nothrow_move_constructible for library types (this standard library):");
    NX(std::string);
    NX(std::vector<int>);
    NX(std::deque<int>);
    NX(std::list<int>);
    NX(std::map<int, int>);
    NX(std::set<int>);
    NX(std::unordered_map<int, int>);
    NX(std::function<void()>);
    NX(std::optional<std::string>);
    NX(std::variant<int, std::string>);

    std::println("vector<deque<Item<noexcept>>> x 100000, 4 items per deque:");
    g = {};
    std::vector<std::deque<Item<true>>> vd;
    for (int i = 0; i < 100'000; ++i) {
        std::deque<Item<true>> d;
        for (int k = 0; k < 4; ++k) d.emplace_back(k);  // constructed in place: no copy, no move
        vd.push_back(std::move(d));                      // deque move: no element copies
    }
    std::println("  Item copies made by vector reallocation: {}", g.copies);
}
```

GCC 16.2 + libstdc++ (one run):

```text
vector<T>::emplace_back x 1000000 (capacity doubles ~20 times):
  Item<noexcept move>        copies=      0 moves=1048575    49.3 ms
  Item<throwing move>        copies=1048575 moves=      0   125.2 ms
defaulted move of a member with a throwing move:
  Wrapper      nothrow-move: false
  WrapperFixed nothrow-move: true
is_nothrow_move_constructible for library types (this standard library):
  std::string                        true
  std::vector<int>                   true
  std::deque<int>                    false
  std::list<int>                     true
  std::map<int, int>                 true
  std::set<int>                      true
  std::unordered_map<int, int>       true
  std::function<void()>              true
  std::optional<std::string>         true
  std::variant<int, std::string>     true
vector<deque<Item<noexcept>>> x 100000, 4 items per deque:
  Item copies made by vector reallocation: 0
```

Clang 21.1 + libc++ (one run):

```text
vector<T>::emplace_back x 1000000 (capacity doubles ~20 times):
  Item<noexcept move>        copies=      0 moves=1048575    51.4 ms
  Item<throwing move>        copies=1048575 moves=      0   128.4 ms
defaulted move of a member with a throwing move:
  Wrapper      nothrow-move: false
  WrapperFixed nothrow-move: true
is_nothrow_move_constructible for library types (this standard library):
  std::string                        true
  std::vector<int>                   true
  std::deque<int>                    true
  std::list<int>                     true
  std::map<int, int>                 true
  std::set<int>                      true
  std::unordered_map<int, int>       true
  std::function<void()>              true
  std::optional<std::string>         true
  std::variant<int, std::string>     true
vector<deque<Item<noexcept>>> x 100000, 4 items per deque:
  Item copies made by vector reallocation: 0
```

* 1,048,575 = 2²⁰ − 1: capacity doubles from 1 up to 2²⁰, and every growth transfers every existing element.
  With a throwing move, every transfer is a deep copy of a 40-char heap string: 2.2–2.4× the time here.
* `Wrapper` shows that `= default` **propagates** `noexcept(false)` from a member. `WrapperFixed` shows the
  explicit override `noexcept = default`. It is a promise: if the member's move ever throws, `std::terminate`.
* **The libraries disagree on `std::deque`.** libstdc++'s move constructor allocates a fresh map for the
  moved-from deque, so it is not `noexcept`. libc++'s is. Yet `vector<deque<…>>` made **zero** element copies
  on libstdc++ too. I read the headers to find out why: libstdc++ specializes its internal
  `std::__is_bitwise_relocatable<deque<T>>` to `true` (`bits/stl_deque.h`), so `vector` reallocation
  **memcpy's the deques** (`__relocate_a_1` → `__builtin_memcpy`) and never calls the move constructor. File 04
  builds on this.

### 1.6 What `noexcept` does to the machine code

```cpp
// noexcept_cost.cpp - what noexcept changes in the generated code (table-based EH: nothing on the hot path)
void may_throw();                     // defined elsewhere: the compiler must assume it can throw
void never_throws() noexcept;         // a promise the optimizer can rely on

struct Guard {
    ~Guard();                         // non-trivial: must run during unwinding
};

// A noexcept function calling a potentially-throwing one: the hot path is a plain call; an exception that
// tries to leave reaches a landing pad that calls std::terminate (Clang: __clang_call_terminate).
void wrapped() noexcept { may_throw(); }
// Same body without noexcept: a tail call, no landing pad needed.
void plain() { may_throw(); }
// A destructor that must run on unwind: normal path calls ~Guard once; the landing pad calls it again
// and resumes unwinding (_Unwind_Resume).
void guarded() {
    Guard g;
    may_throw();
}
// Callee is noexcept: the compiler knows no exception can arrive, so no landing pad is emitted.
void guarded_nothrow() {
    Guard g;
    never_throws();
}
```

```asm
_Z7wrappedv:                       # wrapped()
	pushq	%rax
	callq	_Z9may_throwv@PLT                    # may_throw()
	popq	%rax
	retq
.Ltmp2:                                     # landing pad (entered only via the LSDA)
	movq	%rax, %rdi
	callq	__clang_call_terminate

_Z5plainv:                         # plain()
	jmp	_Z9may_throwv@PLT                      # may_throw()

_Z7guardedv:                       # guarded()
	pushq	%rbx
	subq	$16, %rsp
	callq	_Z9may_throwv@PLT                    # may_throw()
	leaq	15(%rsp), %rdi
	callq	_ZN5GuardD1Ev@PLT                    # Guard::~Guard()
	addq	$16, %rsp
	popq	%rbx
	retq
.Ltmp5:                                     # landing pad (entered only via the LSDA)
	movq	%rax, %rbx
	leaq	15(%rsp), %rdi
	callq	_ZN5GuardD1Ev@PLT                    # Guard::~Guard()
	movq	%rbx, %rdi
	callq	_Unwind_Resume@PLT

_Z15guarded_nothrowv:              # guarded_nothrow()
	pushq	%rax
	callq	_Z12never_throwsv@PLT                # never_throws()
	leaq	7(%rsp), %rdi
	callq	_ZN5GuardD1Ev@PLT                    # Guard::~Guard()
	popq	%rax
	retq
```

```asm
_Z7wrappedv:                       // wrapped()
	str	x30, [sp, #-16]!
	bl	_Z9may_throwv                           // may_throw()
	ldr	x30, [sp], #16
	ret
.Ltmp2:                                     // landing pad (entered only via the LSDA)
	bl	__clang_call_terminate

_Z5plainv:                         // plain()
	b	_Z9may_throwv                            // may_throw()

_Z7guardedv:                       // guarded()
	sub	sp, sp, #32
	stp	x30, x19, [sp, #16]
	bl	_Z9may_throwv                           // may_throw()
	add	x0, sp, #15
	bl	_ZN5GuardD1Ev                           // Guard::~Guard()
	ldp	x30, x19, [sp, #16]
	add	sp, sp, #32
	ret
.Ltmp5:                                     // landing pad (entered only via the LSDA)
	mov	x19, x0
	add	x0, sp, #15
	bl	_ZN5GuardD1Ev                           // Guard::~Guard()
	mov	x0, x19
	bl	_Unwind_Resume

_Z15guarded_nothrowv:              // guarded_nothrow()
	str	x30, [sp, #-16]!
	bl	_Z12never_throwsv                       // never_throws()
	add	x0, sp, #15
	bl	_ZN5GuardD1Ev                           // Guard::~Guard()
	ldr	x30, [sp], #16
	ret
```

* **The happy path is identical.** Table-based EH (the Itanium ABI's zero-cost model) puts no instruction on
  the non-throwing path. The landing pads after `ret` run only when the unwinder finds them through the LSDA.
* **`noexcept` cost `wrapped` its tail call.** `plain` is `jmp may_throw`. `wrapped` must stay on the stack
  (`push`/`call`/`pop`) so that an escaping exception finds its frame and calls `std::terminate`
  (`__clang_call_terminate`). `noexcept` on a thin forwarding wrapper is therefore *not* free.
* **`noexcept` on the callee removes the caller's landing pad.** `guarded_nothrow` has none. `guarded` needs
  one to run `~Guard` and then `_Unwind_Resume`. This is where `noexcept` pays off: in callers that hold
  objects with destructors.

---

## 2. Evolution table

| Standard | Change (paper) | Effect |
|---|---|---|
| C++11 | rvalue references, move semantics, `std::move`/`std::forward` (N2118 lineage) | the lvalue/xvalue/prvalue taxonomy |
| C++11 | implicit move on `return local;` | the "two locals" row in §1.2 |
| C++11 | `noexcept`, `std::move_if_noexcept` | vector growth rule (§1.5) |
| C++14 | CWG1579: implicit move also when the return type differs (converting constructor) | `return derived_local;` for `unique_ptr<Base>` |
| C++17 | guaranteed copy elision (P0135R1) | prvalues are initializers; non-movable factories (`Pinned`, `std::mutex`) |
| C++17 | `noexcept` in the type system (P0012R1) | `void(*)() noexcept` is a separate type |
| C++20 | P1825R0: implicit move for rvalue-reference locals/params, `throw`, more contexts | `return T&&-param;` moves (GCC: C++20 only; Clang: also C++17, §1.2) |
| C++23 | P2266R3 simpler implicit move; `__cpp_implicit_move` = 202207L on both compilers | `return r;` is an xvalue: breaks `T& f(T&& r) { return r; }` |
| C++23 | `auto(x)` decay-copy (P0849R8) | an explicit prvalue copy (`valcat` row) |
| C++26 | nothing new for elision; guaranteed NRVO (P2025) was proposed and not adopted | NRVO stays a quality-of-implementation matter |

---

## 3. Production blueprints

### 3.1 Value types that stay movable (Listing 2.7, `order_blueprint.cpp`)

`OrderBuggy` is the subtle buggy way, a destructor added "only for metrics". `Order` is the
production-hardened way: the side effect moves into a member that owns its special members, and `Order`
itself declares none.

```cpp
// order_blueprint.cpp - instrumenting a value type without losing its noexcept move (rule of zero)
#include <atomic>
#include <print>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

std::atomic<long> g_destroyed{0};
long g_line_copies = 0;

struct Line {
    std::string sku = std::string(32, 's');
    Line() = default;
    Line(const Line& o) : sku(o.sku) { ++g_line_copies; }
    Line(Line&&) noexcept = default;
    Line& operator=(const Line&) = default;
    Line& operator=(Line&&) noexcept = default;
};

// Subtle buggy way: the destructor added for metrics suppresses the implicit move constructor.
struct OrderBuggy {
    std::string id = std::string(24, 'o');
    std::vector<Line> lines = std::vector<Line>(4);
    ~OrderBuggy() { g_destroyed.fetch_add(1, std::memory_order_relaxed); }
};

// Production-hardened way: the side effect lives in a member that owns its own special members.
struct DestroyCounter {
    DestroyCounter() = default;
    DestroyCounter(const DestroyCounter&) = default;
    DestroyCounter(DestroyCounter&&) noexcept = default;
    DestroyCounter& operator=(const DestroyCounter&) = default;
    DestroyCounter& operator=(DestroyCounter&&) noexcept = default;
    ~DestroyCounter() { g_destroyed.fetch_add(1, std::memory_order_relaxed); }
};
struct Order {                         // declares no special members: rule of zero
    std::string id = std::string(24, 'o');
    std::vector<Line> lines = std::vector<Line>(4);
    [[no_unique_address]] DestroyCounter counter;
};
static_assert(std::is_nothrow_move_constructible_v<Order>, "pin the property next to the type");
static_assert(!std::is_nothrow_move_constructible_v<OrderBuggy>);

template <class T>
void grow(const char* label) {
    g_line_copies = 0;
    std::vector<T> book;
    for (int i = 0; i < 10'000; ++i) book.emplace_back();
    std::println("  {:<12} Line copies during growth: {}", label, g_line_copies);
}

int main() {
    std::println("10'000 emplace_back calls, 4 Lines per order:");
    grow<OrderBuggy>("OrderBuggy");
    grow<Order>("Order");
    std::println("  sizeof(OrderBuggy)={} sizeof(Order)={}", sizeof(OrderBuggy), sizeof(Order));
}
```

Output (verified; the sizes differ because libstdc++'s `std::string` is 32 bytes and libc++'s is 24):

```text
GCC 16.2 / libstdc++:
10'000 emplace_back calls, 4 Lines per order:
  OrderBuggy   Line copies during growth: 65532
  Order        Line copies during growth: 0
  sizeof(OrderBuggy)=56 sizeof(Order)=56
```

```text
Clang 21.1 / libc++:
10'000 emplace_back calls, 4 Lines per order:
  OrderBuggy   Line copies during growth: 65532
  Order        Line copies during growth: 0
  sizeof(OrderBuggy)=48 sizeof(Order)=48
```

65,532 = 4 × (1 + 2 + … + 8192): every reallocation deep-copies the four `Line`s of every existing order. The
fixed type has the same size (the counter is `[[no_unique_address]]`, file 04) and makes zero copies. The
`static_assert` next to the type turns any future regression into a build break instead of a latency
regression.

### 3.2 Returning things

| Write | Not | Because |
|---|---|---|
| `return local;` | `return std::move(local);` | NRVO, or an implicit move at worst (§1.2) |
| `if (c) return a; return b;` | `return c ? a : b;` | the conditional copies |
| `return std::move(local.member);` | `return local.member;` | members are not implicitly moved |
| `T f() &&` + `return std::move(m);` | `T f() const { return std::move(m); }` | const member → copy (trap 3) |
| `T make() { return T{...}; }` for non-movable `T` | heap allocation | guaranteed elision (C++17) |

### 3.3 Sink parameters and the ABI

* Small, trivially copyable value types (≤16 bytes on both ABIs): pass and return **by value**; they travel in
  registers.
* Owning handles (`unique_ptr`, `std::string`, `std::function`): pass **by value when the callee keeps it**
  (one move); otherwise pass `T&`, `const T&` or a non-owning view. By-value handles travel through memory
  (§1.4).
* Across FFI boundaries: only **trivially copyable** types, with `static_assert(std::is_trivially_copyable_v<T>)`
  on each one. Never a type with a destructor (the X8 trap in §1.4).

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| latency regression after "adding a destructor" | implicit move suppressed → copies | `static_assert(is_nothrow_move_constructible_v<T>)`; clang-tidy `performance-*` checks |
| vector growth dominates the profile | throwing (or missing) move constructor | Listing 2.5 pattern: count copies in a test |
| warning `-Wpessimizing-move` / `-Wredundant-move` | `return std::move(local)` | keep them as errors |
| C++23 migration error "cannot bind non-const lvalue reference … to an rvalue" | P2266 | return `static_cast<T&>(r)` deliberately, or redesign |
| ARM64-only crash at an FFI boundary | C++ type with a destructor returned via X8 | FFI types must be trivially copyable |
| `std::terminate` in production with no catch site | an exception escaped a `noexcept` function (destructors are implicitly `noexcept`) | core dump frame `__clang_call_terminate` / `std::terminate` |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "What is an xvalue, and why did C++17 change prvalues?"</b></summary>

**Initial prompt.** "Explain lvalue, prvalue, xvalue. Why does anyone care?"

**L5 textbook answer.** "Lvalues have names; rvalues are temporaries. Xvalues are things passed to
`std::move`."

**Why L5 breaks.** It cannot classify `S{}.m` (xvalue), `rr` (lvalue), `"hi"` (lvalue) or `std::move(g)`
(lvalue): four rows of Listing 2.1. More importantly, it predicts the wrong *code*. Before C++17, `T x = T{};`
created a temporary that was then moved (elision optional). Since C++17 there is no temporary at all. That is
why `Pinned make()` compiles with deleted copy *and* move, and why returning a `std::mutex` by value is legal.

**L7 principal defense.** "Two bits: identity and movability. A prvalue is an initializer whose result object
is chosen by context, materialized into an xvalue only when you need a glvalue. I can prove any row with
`decltype((e))`. The practical consequences: factories can return non-movable types, `return T{...}` has no
cost, and the remaining copies come from *named* objects."
</details>

<details><summary><b>Chain 2 🔥 "Does std::move move?"</b></summary>

**Initial prompt.** "What does `std::move` do?"

**L5 textbook answer.** "It moves the object, leaving the source empty."

**Why L5 breaks.** It is a cast and generates no code. Listing 2.3 shows three silent copies: a `const`
source, a class whose user-declared destructor suppressed the move constructor, and `std::move(member)` inside
a `const` member function. `is_move_constructible_v` is **true** in all of them, so a trait-based test does not
catch it. Also, "the source is empty" is not guaranteed: after a move, standard types are in a "valid but
unspecified" state.

**L7 principal defense.** "`std::move` asks for the rvalue overload; overload resolution decides. I enforce
moves with `static_assert(is_nothrow_move_constructible_v<T>)` on value types, a copy-counting test for hot
types (Listing 2.3's harness), and the rule of zero. Moved-from objects are only assigned to or destroyed."
</details>

<details><summary><b>Chain 3 ⚡ "Should I write return std::move(local)?"</b></summary>

**Initial prompt.** "Reviewer says remove `std::move` from `return std::move(result);`. Why? Isn't moving
cheaper than copying?"

**L5 textbook answer.** "Modern compilers do RVO, so it doesn't matter."

**Why L5 breaks.** It does matter. `std::move(local)` is an xvalue, not a name, so **NRVO becomes impossible**:
Listing 2.2 shows 1 move instead of 0, and both compilers warn. It also misses the opposite case:
`return local.member;` and `return cond ? a : b;` **copy**, and there `std::move` (or restructuring into two
`return` statements) is right.

**L7 principal defense.** "Rule: never `std::move` a local or a by-value parameter in a return. Always
`std::move` a member or subobject. Never use a conditional expression to choose between two named locals.
`-Werror=pessimizing-move -Werror=redundant-move` enforces the first rule. The table in §3.2 is our review
checklist."
</details>

<details><summary><b>Chain 4 🔥 "Why must move constructors be noexcept?"</b></summary>

**Initial prompt.** "Why do people insist on `noexcept` move constructors?"

**L5 textbook answer.** "It's faster because the compiler can optimize better."

**Why L5 breaks.** The compiler barely changes (§1.6). The *library* changes its algorithm. `vector`
reallocation uses `move_if_noexcept` to keep the strong guarantee. Listing 2.5: 1,048,575 deep copies versus
1,048,575 moves for one million `push_back`s, 2.2–2.4× slower here, and far worse for heavier types. The
answer also misses the subtleties: `= default` inherits `noexcept(false)` from members (`Wrapper`), and the two
standard libraries disagree on `std::deque` (`false` on libstdc++). libstdc++ still avoids copying deques in a
vector by relocating them with memcpy through an internal trait.

**L7 principal defense.** "`noexcept` on move is a contract with containers: it trades the strong guarantee for
moves. I make value types' moves `noexcept` (rule of zero gets it for free), `static_assert` it, and where a
member blocks it (an old allocator-aware type, a third-party class) I decide explicitly between
`noexcept = default` (terminate on the impossible case) and accepting copies. I would never sprinkle `noexcept`
on functions that can throw."
</details>

<details><summary><b>Chain 5 ⚡ "Is std::unique_ptr a zero-cost abstraction?"</b></summary>

**Initial prompt.** "Is passing `std::unique_ptr<T>` by value as cheap as passing `T*`?"

**L5 textbook answer.** "Yes, it's the same size as a pointer and everything inlines."

**Why L5 breaks.** Same size, different ABI. It has a non-trivial destructor, so it is "non-trivial for the
purposes of calls". It travels through **memory**, and the **caller** must destroy it after the call, with a
landing pad (Listing 2.4: ~20 instructions versus one `jmp` for a `[[clang::trivial_abi]]` equivalent). The
cost only shows up across non-inlined boundaries: library APIs, virtual functions, `std::function` targets.
Those are exactly the boundaries where people choose `unique_ptr` to express ownership.

**L7 principal defense.** "For ownership transfer across a hot non-inline boundary I would measure first. Then
I would either accept the cost, pass `T*` with documented ownership plus a `unique_ptr` at both ends, or use a
`trivial_abi` handle inside our own ABI-controlled code. libc++'s unstable ABI turns this on for `unique_ptr`
(`_LIBCPP_ABI_ENABLE_UNIQUE_PTR_TRIVIAL_ABI`), which is a good argument for an ABI-unstable internal build if
the organization controls all binaries."
</details>

<details><summary><b>Chain 6 🧊 "Your FFI wrapper crashes only on ARM64"</b></summary>

**Initial prompt.** "A Rust service calls `extern "C" Result compute(int)` from our C++ library. Fine on x86 CI,
random memory corruption on Graviton. `Result` is `struct { int64_t v; ~Result(); }`."

**L5 textbook answer.** "Probably a Rust bug, or alignment."

**Why L5 corrupts memory on ARM64.** `Result` has a user-provided destructor, so the C++ compiler returns it
indirectly: the caller must pass a buffer address in **X8** and the callee **writes through X8**
(`make_tracked` in Listing 2.4: `str x0, [x8]`). The Rust side declared a plain `#[repr(C)]` struct of 8 bytes
and expects the result in X0. So it never sets X8, and the C++ callee writes 8 bytes to whatever address X8
held. X8 is a scratch register that often holds a recently used, *valid* pointer, so the write usually lands
somewhere live and nothing crashes at the call. On x86-64 the hidden pointer takes **RDI**, where the Rust caller
put the `int`. The C++ callee reads its `int` from RSI (garbage) and writes the result to the address equal to
the integer argument, which segfaults immediately. x86 fails loudly and consistently, which is why CI never saw
the silent ARM64 corruption.

**L7 principal defense.** "An `extern "C"` boundary takes only types for which
`static_assert(std::is_trivially_copyable_v<T> && std::is_standard_layout_v<T>)` holds. That is checked in the
header next to the declaration, and the FFI bindings are generated from it, not hand-written. Resources cross
the boundary as opaque handles with explicit `destroy()` functions."
</details>

<details><summary><b>Chain 7 ⚡ "Can noexcept make code slower?"</b></summary>

**Initial prompt.** "Should we mark everything `noexcept` for performance?"

**L5 textbook answer.** "Yes, it lets the compiler skip exception handling."

**Why L5 breaks.** Listing 2.6: a `noexcept` function that calls a potentially-throwing one **loses its tail
call** and keeps a frame plus a terminate landing pad. Wrong `noexcept` turns a recoverable `bad_alloc` into
`std::terminate`. And `noexcept` is part of the function type since C++17, so changing it is an API (and
mangling) change. The real wins are in callers holding destructible objects (`guarded_nothrow`) and in library
algorithm selection (`move_if_noexcept`).

**L7 principal defense.** "`noexcept` where it is a true contract and has a consumer: move operations, swap,
destructors (implicit), hash functions, and leaf functions called from hot loops that hold RAII objects. Not on
forwarding wrappers, and not on anything that allocates unless termination on OOM is the policy."
</details>

<details><summary><b>Chain 8 🧊 "Our C++23 upgrade broke a function that returns T&"</b></summary>

**Initial prompt.** "After switching to `-std=c++23`, `T& pass(T&& x) { return x; }` stopped compiling. Bug in
the compiler?"

**L5 textbook answer.** "Probably a compiler bug; add a cast."

**Why L5 breaks.** It is P2266R3, on purpose: in `return x;` an implicitly movable entity is now an **xvalue**,
so it cannot bind to `T&`. Both compilers reject it identically (§1.2). The old code returned an lvalue
reference to the caller's temporary, which was usually a dangling-reference bug: `auto& r = pass(T{});`
dangles at the semicolon. The language now rejects most such code.

**L7 principal defense.** "Read the diagnostic as a lifetime audit. Where the reference really is meant
(forwarding helpers), write `return static_cast<T&>(x);` and name the function honestly. Everywhere else,
return by value. I would grep the code base for `T&&` parameters that are returned as `T&` before flipping the
standard flag."
</details>

---

## 6. Invariants checklist

- [ ] Value types follow the rule of zero; when special members are declared, all five are, with `noexcept`
      moves.
- [ ] `static_assert(std::is_nothrow_move_constructible_v<T>)` next to every hot value type.
- [ ] No `return std::move(local)`, no `return c ? a : b` between locals, `std::move` on returned members.
- [ ] No `std::move` of `const` objects; "consuming" getters are `&&`-qualified.
- [ ] `-Werror=pessimizing-move,redundant-move` (Clang/GCC).
- [ ] FFI and `extern "C"` types are trivially copyable and standard layout, with a `static_assert`.
- [ ] `noexcept` only where it is a contract with a consumer.
- [ ] C++23 migration: audit `T&&` parameters returned by reference.

## 7. References

- P0135R1 guaranteed copy elision: <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2016/p0135r1.html>
- P1825R0 implicit move: <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2019/p1825r0.html>
- P2266R3 simpler implicit move: <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2022/p2266r3.html>
- P2025 guaranteed NRVO (not adopted): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2021/p2025r2.html>
- System V AMD64 psABI: <https://gitlab.com/x86-psABIs/x86-64-ABI>
- AAPCS64 (X8 indirect result register): <https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst>
- Itanium C++ ABI §3.1 (non-trivial for the purposes of calls): <https://itanium-cxx-abi.github.io/cxx-abi/abi.html#calls>
- Clang `trivial_abi`: <https://clang.llvm.org/docs/AttributeReference.html#trivial-abi>
- Chandler Carruth, "There Are No Zero-cost Abstractions", CppCon 2019: <https://www.youtube.com/watch?v=rHIkrotSwcc>
- cppreference, value categories: <https://en.cppreference.com/w/cpp/language/value_category>
