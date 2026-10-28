# 03 · `std::function`, small-buffer type erasure, `function_ref`, `move_only_function`

> **Scope.** Type-erased callables are everywhere in production C++: callbacks, task queues, plugin hooks. Their cost
> has three parts: **storage** (inline small buffer or a heap allocation), **call** (one or two indirections, arguments
> forwarded through memory) and **copy semantics** (`std::function` requires copyable targets). This file measures all
> three on both libraries, compares the C++23/26 alternatives, and builds a type-erased callable from scratch so the
> mechanism is visible.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 4.6 | `function_sbo.cpp` | `sizeof` and inline-buffer thresholds: 16 B and **trivially copyable only** (libstdc++), 24 B if nothrow-copyable (libc++); `move_only_function`/`copyable_function`/`function_ref` | run, both libraries (GCC: `-fno-assume-sane-operators-new-delete`) |
| 4.7 | `call_cost.cpp` | ns per call for template, function pointer, virtual, `std::function`, `function_ref`; the `std::function` call sequence in both libraries | run + asm (Clang/libc++, GCC/libstdc++) |
| 4.8 | `small_function.cpp` | a move-only type-erased callable with an inline buffer and a static function-pointer vtable | run, both compilers |

**Verification line.** As for files 01–02. GCC call-sequence asm uses GCC's native Win64 calling convention (`gccw`:
the `std::function` arrives in RCX, the argument in EDX).

---

## 1. First principles

### 1.1 The storage decision (Listing 4.6)

```text
 std::function<R(A...)> object
 +------------------------------+------------------+
 | inline buffer                | manager/invoker  |   libstdc++: 32 bytes = 16-byte _Any_data + _M_manager + _M_invoker
 | holds the callable, or a     | (or a pointer to |   libc++:    48 bytes = aligned_storage<3*sizeof(void*)> (32 bytes after
 | pointer to a heap copy       |  a polymorphic   |              16-byte alignment) holding a __func object (vptr +
 |                              |  holder)         |              callable, so callables <= 24 B fit) + __func* at +32
 +------------------------------+------------------+
 libstdc++: copy/destroy = _M_manager(op), call = _M_invoker(&buffer, args...)
 libc++:    copy/destroy/call = virtual functions of the __func object that __f_ points to (in the buffer or on the heap)
```

```cpp
// function_sbo.cpp - std::function's small-buffer threshold per library, and the C++23/26 alternatives
#include <version>
#include <array>
#include <cstddef>
#include <cstdlib>
#include <functional>
#include <new>
#include <print>
#include <string>
#include <utility>

#pragma GCC diagnostic ignored "-Wmismatched-new-delete"  // see Folder 03 transparent.cpp
static std::size_t g_allocs = 0;
void* operator new(std::size_t n) {
    ++g_allocs;
    if (void* p = std::malloc(n ? n : 1)) return p;
    throw std::bad_alloc{};
}
void operator delete(void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }

template <std::size_t N>
struct Payload {                       // a callable whose size we control
    std::array<char, N> bytes{};
    int operator()(int x) const { return x + bytes[0]; }
};

struct NonTrivial8 {                   // 8 bytes, but NOT trivially copyable (user-provided noexcept copy)
    long x = 0;
    NonTrivial8() = default;
    NonTrivial8(const NonTrivial8& o) noexcept : x(o.x) {}
    int operator()(int v) const { return v + static_cast<int>(x); }
};
struct ThrowingCopy16 {                // 16 bytes, copy constructor not noexcept
    long x = 0, y = 0;
    ThrowingCopy16() = default;
    ThrowingCopy16(const ThrowingCopy16& o) : x(o.x), y(o.y) {}
    int operator()(int v) const { return v + static_cast<int>(x + y); }
};
template <class C>
std::size_t allocs_std_function() {
    g_allocs = 0;
    std::function<int(int)> f = C{};
    std::size_t a = g_allocs;
    volatile int sink = f(1);
    (void)sink;
    return a;
}

template <template <class> class Fn, std::size_t N>
std::size_t allocs_for() {
    g_allocs = 0;
    Fn<int(int)> f = Payload<N>{};
    std::size_t a = g_allocs;
    volatile int sink = f(1);
    (void)sink;
    return a;
}

template <template <class> class Fn>
void row(const char* name) {
    std::println("  {:<22} sizeof={:>2}   allocations for a callable of 8/16/24/32/48 bytes: {} {} {} {} {}", name,
                 sizeof(Fn<int(int)>), allocs_for<Fn, 8>(), allocs_for<Fn, 16>(), allocs_for<Fn, 24>(),
                 allocs_for<Fn, 32>(), allocs_for<Fn, 48>());
}

template <class Sig>
using StdFunction = std::function<Sig>;
#if __cpp_lib_move_only_function
template <class Sig>
using MoveOnly = std::move_only_function<Sig>;
#endif
#if __cpp_lib_copyable_function
template <class Sig>
using Copyable = std::copyable_function<Sig>;
#endif

int main() {
    row<StdFunction>("std::function");
#if __cpp_lib_move_only_function
    row<MoveOnly>("std::move_only_function");
#endif
#if __cpp_lib_copyable_function
    row<Copyable>("std::copyable_function");
#endif
#if __cpp_lib_function_ref
    auto big = Payload<48>{};
    g_allocs = 0;
    std::function_ref<int(int)> r = big;    // non-owning: never allocates, whatever the size
    std::println("  {:<22} sizeof={:>2}   allocations for a 48-byte callable: {} (it only points at it)",
                 "std::function_ref", sizeof(r), g_allocs);
#endif
    std::println("std::function, small but non-trivial callables: 8-byte noexcept-copy {} allocation(s), "
                 "16-byte throwing-copy {} allocation(s)", allocs_std_function<NonTrivial8>(),
                 allocs_std_function<ThrowingCopy16>());
    // A lambda capturing a std::string: the closure is 32 (libstdc++) or 24 (libc++) bytes.
    std::string s = "captured";
    g_allocs = 0;
    std::function<std::size_t()> f = [s] { return s.size(); };
    std::println("std::function holding [std::string] lambda (sizeof closure {}): {} allocation(s)", sizeof(s),
                 g_allocs);
    (void)f;
}
```

GCC 16.2 + libstdc++ (verified):

```text
  std::function          sizeof=32   allocations for a callable of 8/16/24/32/48 bytes: 0 0 1 1 1
  std::move_only_function sizeof=40   allocations for a callable of 8/16/24/32/48 bytes: 0 0 0 1 1
  std::copyable_function sizeof=40   allocations for a callable of 8/16/24/32/48 bytes: 0 0 0 1 1
  std::function_ref      sizeof=16   allocations for a 48-byte callable: 0 (it only points at it)
std::function, small but non-trivial callables: 8-byte noexcept-copy 1 allocation(s), 16-byte throwing-copy 1 allocation(s)
std::function holding [std::string] lambda (sizeof closure 32): 1 allocation(s)
```

Clang 21.1 + libc++ (verified):

```text
  std::function          sizeof=48   allocations for a callable of 8/16/24/32/48 bytes: 0 0 0 1 1
std::function, small but non-trivial callables: 8-byte noexcept-copy 0 allocation(s), 16-byte throwing-copy 1 allocation(s)
std::function holding [std::string] lambda (sizeof closure 24): 1 allocation(s)
```

| Type | libstdc++ 16 | libc++ 21 |
|---|---|---|
| `std::function` size | 32 B | 48 B |
| stored inline if… | ≤ 16 B **and trivially copyable** ("location invariant") | ≤ 24 B and nothrow copy-constructible |
| 8-byte callable with a user-provided `noexcept` copy | **heap** | inline |
| 16-byte callable with a throwing copy | heap | heap |
| lambda capturing one `std::string` | heap (32 B closure) | heap (copy not `noexcept`) |
| `move_only_function` / `copyable_function` (C++23/26) | 40 B, inline ≤ 24 B | not shipped |
| `function_ref` (C++26) | 16 B, never allocates | not shipped |

Consequences:

* **A `std::function` holding a lambda that captures a `std::string` allocates on both libraries.** A task queue of
  `std::function<void()>` with string captures pays one `malloc` + `free` per task, and on libstdc++ any non-trivially
  copyable capture (a `shared_ptr`, a `std::string`, a `std::vector`) allocates however small it is.
* `move_only_function` has a bigger buffer and no copy requirement, so move-only captures (`unique_ptr`) work.
  `copyable_function` is the C++26 "fixed `std::function`": copyable, const-correct `operator()`, same buffer as
  `move_only_function`.
* `function_ref` stores two pointers (the object and a thunk). It does not own the callable, so it is for *parameters*,
  never for storage.

### 1.2 The call (Listing 4.7)

```cpp
// call_cost.cpp - what one call costs through each callable abstraction (opaque boundary, one run)
#include <cstdint>
#include <version>
#include <chrono>
#include <functional>
#include <print>

struct Op {
    virtual ~Op() = default;
    virtual int apply(int x) const = 0;
};
struct AddOne final : Op {
    int apply(int x) const override { return x + 1; }
};
int add_one(int x) { return x + 1; }

// Out-of-line (noinline) loops: each receives the callable through its abstraction and cannot see the target.
[[gnu::noinline]] std::int64_t loop_fp(int (*f)(int), int n) {
    std::int64_t s = 0;
    for (int i = 0; i < n; ++i) s += f(i);
    return s;
}
[[gnu::noinline]] std::int64_t loop_function(const std::function<int(int)>& f, int n) {
    std::int64_t s = 0;
    for (int i = 0; i < n; ++i) s += f(i);
    return s;
}
[[gnu::noinline]] std::int64_t loop_virtual(const Op& op, int n) {
    std::int64_t s = 0;
    for (int i = 0; i < n; ++i) s += op.apply(i);
    return s;
}
#if __cpp_lib_function_ref
[[gnu::noinline]] std::int64_t loop_ref(std::function_ref<int(int)> f, int n) {
    std::int64_t s = 0;
    for (int i = 0; i < n; ++i) s += f(i);
    return s;
}
#endif
template <class F>
[[gnu::noinline]] std::int64_t loop_template(F f, int n) {  // the callable's type is known: inlined
    std::int64_t s = 0;
    for (int i = 0; i < n; ++i) s += f(i);
    return s;
}

// The call sequence of std::function in isolation (see the asm in the text).
int call_function(const std::function<int(int)>& f, int x) { return f(x); }

template <class F>
void bench(const char* label, F f) {
    constexpr int kN = 100'000'000;
    auto t0 = std::chrono::steady_clock::now();
    std::int64_t s = f(kN);
    auto t1 = std::chrono::steady_clock::now();
    std::println("  {:<28} {:5.2f} ns/call (sum {})", label,
                 std::chrono::duration<double, std::nano>(t1 - t0).count() / kN, s);
}

int main() {
    auto lam = [](int x) { return x + 1; };
    std::function<int(int)> fn = lam;
    AddOne op;
    std::println("100M calls of x + 1:");
    bench("template parameter (inlined)", [&](int n) { return loop_template(lam, n); });
    bench("function pointer", [&](int n) { return loop_fp(&add_one, n); });
    bench("virtual call", [&](int n) { return loop_virtual(op, n); });
    bench("std::function", [&](int n) { return loop_function(fn, n); });
#if __cpp_lib_function_ref
    bench("std::function_ref", [&](int n) { return loop_ref(lam, n); });
#endif
}
```

GCC 16.2 (one run):

```text
100M calls of x + 1:
  template parameter (inlined)  0.00 ns/call (sum 5000000050000000)
  function pointer              1.28 ns/call (sum 5000000050000000)
  virtual call                  0.58 ns/call (sum 5000000050000000)
  std::function                 1.43 ns/call (sum 5000000050000000)
  std::function_ref             0.48 ns/call (sum 5000000050000000)
```

Clang 21.1 (one run):

```text
100M calls of x + 1:
  template parameter (inlined)  0.00 ns/call (sum 5000000050000000)
  function pointer              1.07 ns/call (sum 5000000050000000)
  virtual call                  1.29 ns/call (sum 5000000050000000)
  std::function                 1.13 ns/call (sum 5000000050000000)
```

The call sequence of `f(x)` on a `const std::function<int(int)>&`. libc++ (Clang `-O3`, x86-64 SysV):

```asm
_Z13call_functionRKNSt3__18functionIFiiEEEi: # call_function(std::__1::function<int (int)> const&, int)
	pushq	%rax
	movl	%esi, 4(%rsp)
	movq	32(%rdi), %rdi
	testq	%rdi, %rdi
	je	.LBB4_2
	movq	(%rdi), %rax
	leaq	4(%rsp), %rsi
	callq	*48(%rax)
	popq	%rcx
	retq
.LBB4_2:
	callq	_ZNSt3__125__throw_bad_function_callB8ne210100Ev@PLT # std::__1::__throw_bad_function_call[abi:ne210100]()
```

libstdc++ (GCC `-O3`, Win64 convention: `f` in RCX, `x` in EDX):

```asm
_Z13call_functionRKSt8functionIFiiEEi: # call_function(std::function<int (int)> const&, int)
	subq	$56, %rsp
	movl	%edx, 44(%rsp)
	cmpq	$0, 16(%rcx)
	je	.L341
	leaq	44(%rsp), %rdx
	call	*24(%rcx)
	addq	$56, %rsp
	ret

_Z13call_functionRKSt8functionIFiiEEi.cold: # call_function(std::function<int (int)> const&, int) [clone .cold]
	call	_ZSt25__throw_bad_function_callv      # std::__throw_bad_function_call()
```

<details><summary>AArch64 (libc++)</summary>

```asm
_Z13call_functionRKNSt3__18functionIFiiEEEi: // call_function(std::__1::function<int (int)> const&, int)
	str	x30, [sp, #-16]!
	ldr	x0, [x0, #32]
	str	w1, [sp, #12]
	cbz	x0, .LBB4_2
	ldr	x8, [x0]
	add	x1, sp, #12
	ldr	x8, [x8, #48]
	blr	x8
	ldr	x30, [sp], #16
	ret
.LBB4_2:
	bl	_ZNSt3__125__throw_bad_function_callB8ne210100Ev // std::__1::__throw_bad_function_call[abi:ne210100]()
```

</details>

* **libc++: two dependent loads, then an indirect call**: `32(%rdi)` (the `__base*`), null test,
  `(%rdi)` (its vptr), `callq *48(%rax)`. libstdc++: test the manager pointer at `16(%rcx)`, then
  `call *24(%rcx)` (the invoker), which is one load before the indirect call.
* **The argument goes through memory in both**: `movl %esi, 4(%rsp)` … `leaq 4(%rsp), %rsi`. The invoker takes its
  arguments as `A&&...` (perfect forwarding through a type-erased boundary), so even an `int` is spilled to the stack
  and passed by address.
* **An empty `std::function` throws `bad_function_call`**: the null test and a cold call on every invocation.
* Measured cost per call, 100M calls, opaque boundary, ranges over 3 runs: function pointer 1.07–1.28 ns,
  `std::function` 1.03–1.59 ns, `function_ref` 0.46–0.81 ns (GCC). The **virtual call measured 0.58–0.92 ns on GCC**
  because GCC's speculative devirtualization (Folder 01) guessed the only overrider and inlined it behind a compare,
  while Clang paid 1.27–1.40 ns. The template version is inlined, and both compilers folded the whole loop into a
  closed-form sum (0.00 ns). For trivial bodies the dominant cost is the lost inlining, not the indirection.

### 1.3 Type erasure by hand (Listing 4.8)

```cpp
// small_function.cpp - type erasure by hand: a move-only callable with a configurable inline buffer
#include <cstddef>
#include <memory>
#include <new>
#include <print>
#include <string>
#include <type_traits>
#include <utility>

template <class Sig, std::size_t Cap = 32>
class SmallFunction;

template <class R, class... A, std::size_t Cap>
class SmallFunction<R(A...), Cap> {
    // One static "vtable" per erased type: plain function pointers, no RTTI, no virtual inheritance.
    struct VTable {
        R (*call)(void*, A&&...);
        void (*move_to)(void* src, void* dst) noexcept;  // relocate into another object's storage
        void (*destroy)(void*) noexcept;
    };
    template <class F>
    static constexpr bool kInline = sizeof(F) <= Cap && alignof(F) <= alignof(std::max_align_t) &&
                                    std::is_nothrow_move_constructible_v<F>;
    template <class F>
    static F* get(void* storage) {
        if constexpr (kInline<F>) return std::launder(reinterpret_cast<F*>(storage));
        else return *static_cast<F**>(storage);       // heap case: the buffer holds a pointer
    }
    template <class F>
    static constexpr VTable kVTable{
        [](void* s, A&&... a) -> R { return (*get<F>(s))(std::forward<A>(a)...); },
        [](void* src, void* dst) noexcept {
            if constexpr (kInline<F>) {
                ::new (dst) F(std::move(*get<F>(src)));
                get<F>(src)->~F();
            } else {
                *static_cast<F**>(dst) = *static_cast<F**>(src);  // steal the pointer
            }
        },
        [](void* s) noexcept {
            if constexpr (kInline<F>) get<F>(s)->~F();
            else delete *static_cast<F**>(s);
        }};

    alignas(std::max_align_t) unsigned char storage_[Cap];
    const VTable* vt_ = nullptr;

public:
    SmallFunction() = default;
    template <class F, class D = std::decay_t<F>>
        requires(!std::is_same_v<D, SmallFunction> && std::is_invocable_r_v<R, D&, A...>)
    SmallFunction(F&& f) : vt_(&kVTable<D>) {
        if constexpr (kInline<D>) ::new (static_cast<void*>(storage_)) D(std::forward<F>(f));
        else *reinterpret_cast<D**>(storage_) = new D(std::forward<F>(f));
    }
    SmallFunction(SmallFunction&& o) noexcept : vt_(std::exchange(o.vt_, nullptr)) {
        if (vt_) vt_->move_to(o.storage_, storage_);
    }
    SmallFunction(const SmallFunction&) = delete;
    ~SmallFunction() {
        if (vt_) vt_->destroy(storage_);
    }
    R operator()(A... a) { return vt_->call(storage_, std::forward<A>(a)...); }
    explicit operator bool() const noexcept { return vt_ != nullptr; }
};

static int g_heap = 0;
struct Big {
    char pad[100] = {};
    std::unique_ptr<int> p = std::make_unique<int>(5);   // move-only state is fine: SmallFunction is move-only
    static void* operator new(std::size_t n) { ++g_heap; return ::operator new(n); }
    static void operator delete(void* q) noexcept { ::operator delete(q); }
    int operator()(int x) { return x + *p; }
};

int main() {
    std::string tag = "small";
    SmallFunction<std::size_t(int)> f1 = [tag](int x) { return tag.size() + static_cast<std::size_t>(x); };
    SmallFunction<int(int)> f2 = Big{};
    SmallFunction<int(int)> f3 = std::move(f2);  // move: inline objects are relocated, heap objects pointer-stolen
    std::println("sizeof(SmallFunction<int(int)>) = {}", sizeof(f3));
    std::println("f1(3) = {} (std::string capture stored inline: {} <= 32)", f1(3), sizeof(tag));
    std::println("f3(1) = {} (100+ byte functor on the heap: Big::operator new calls = {}); moved-from f2 empty: {}",
                 f3(1), g_heap, !f2);
}
```

Output (verified, both compilers):

```text
sizeof(SmallFunction<int(int)>) = 48
f1(3) = 8 (std::string capture stored inline: 32 <= 32)
f3(1) = 6 (100+ byte functor on the heap: Big::operator new calls = 1); moved-from f2 empty: true
```

The design, piece by piece:

* **A static vtable of plain function pointers per erased type** (`kVTable<F>`, a `constexpr` variable template). The
  object stores one pointer to it, which gives virtual-call semantics without inheritance, RTTI or a heap-allocated
  base.
* **The inline/heap decision is a compile-time property** (`kInline<F>`): size, alignment and a `noexcept` move. The
  `noexcept` move matters because moving a `SmallFunction` must not throw (containers, Folder 01).
* **Move = relocate**: inline callables are move-constructed into the destination buffer and destroyed in the source;
  heap callables just hand over the pointer. The type is move-only, so captures like `unique_ptr` work, exactly the
  gap `std::move_only_function` fills.
* What production versions add: copy support (a `clone` slot), `const`/`noexcept`/ref-qualified signatures,
  allocator support, and empty-state checks. folly's `Function` and abseil's `AnyInvocable` follow this design.

---

## 2. Evolution table

| Facility | Standard (paper) | Status here | Notes |
|---|---|---|---|
| `std::function` | C++11 | both | copyable targets only; `operator()` is `const` but can call non-const targets (a known const-correctness hole) |
| `std::bind`, `std::mem_fn` | C++11 | both | prefer lambdas |
| `std::invoke` | C++17 (N4169) | both | uniform call of member pointers and callables |
| `std::bind_front` | C++20 (P0356) | both | — |
| `std::move_only_function` | C++23 (P0288) | libstdc++ 16 | move-only, cv/ref/noexcept-qualified signatures |
| `std::bind_back` | C++23 (P2387) | — | — |
| `std::copyable_function` | C++26 (P2548) | libstdc++ 16 | the const-correct `std::function` |
| `std::function_ref` | C++26 (P0792) | libstdc++ 16 | non-owning, two pointers |
| `std::nontype<f>` for `function_ref` | C++26 (P2472) | — | bind a function at compile time: no object pointer needed |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| callback *parameter* | `void each(const std::function<void(int)>& f)` | a template parameter (hot path) or `std::function_ref<void(int)>` (C++26) |
| task queue with move-only captures | `std::function<void()>` (does not compile with `unique_ptr`) | `std::move_only_function<void()>` or a `SmallFunction` |
| task queue with string captures | `std::function` (one allocation per task on both libraries) | capture an index/ID, or a type-erased task with a bigger buffer (Listing 4.8 with `Cap = 64`) |
| storing a callback | `std::function_ref` member (dangles) | an owning type (`move_only_function`, `copyable_function`) |
| a "maybe" callback | calling an empty `std::function` (throws `bad_function_call`) | check `if (f)`, or require non-empty at construction |
| `std::bind` with placeholders | hard-to-read, copies arguments | lambdas, `std::bind_front` |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| `malloc` hot in a task-queue profile | captures exceed the inline buffer or are not trivially copyable (libstdc++) | allocation counters per task; measure capture sizes |
| `bad_function_call` in production | an empty `std::function` was called | null-object pattern, or construct from a required callable |
| crash calling a stored `function_ref` | it pointed at a temporary lambda | `function_ref` only as a parameter |
| `std::function` won't accept a lambda | the lambda captures a move-only object | `move_only_function` |
| a "const" callback mutates state | `std::function::operator() const` calls a non-const target | `copyable_function` (C++26) enforces constness |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "Does std::function allocate?"</b></summary>

**Initial prompt.** "When does `std::function` heap-allocate?"

**L5 textbook answer.** "When the callable is bigger than its small buffer, about 16 bytes."

**Why L5 breaks.** Size is only one condition. Listing 4.6: libstdc++ stores a callable inline only if it is ≤16 bytes
**and trivially copyable**, so an 8-byte functor with a user-written `noexcept` copy constructor allocates. libc++ uses
a 24-byte buffer and requires a `noexcept` copy, so that functor is inline there. A lambda capturing one `std::string`
allocates on both. Thresholds and rules are library details that decide whether a task queue mallocs per task.

**L7 principal defense.** "I measure with an allocation counter per library, and I design captures to be small and
trivially copyable on hot paths (an index into a table instead of a `std::string`). If that is not possible, I use a
type-erased task with a buffer sized for our captures (Listing 4.8) or `move_only_function` (24-byte buffer in
libstdc++)."
</details>

<details><summary><b>Chain 2 ⚡ "What does a std::function call cost?"</b></summary>

**Initial prompt.** "Compare the cost of calling through `std::function` with a virtual call."

**L5 textbook answer.** "About the same, both are indirect calls."

**Why L5 breaks.** Comparable in the measurement (1.0–1.6 ns for `std::function` vs 1.3–1.4 ns virtual on Clang), but
the mechanics differ (Listing 4.7). libc++ does two dependent loads plus an indirect call, libstdc++ one load. Both test
for emptiness. Both pass even an `int` argument **through memory** (spilled to the stack, passed by address), because the
invoker takes `A&&...`. And the virtual call can be devirtualized (GCC did: 0.58–0.92 ns), while a `std::function`
target cannot, because it is erased.

**L7 principal defense.** "On hot paths the target must be visible to the optimizer: a template parameter (both
compilers folded that loop away entirely). At boundaries, `function_ref` is the cheapest erased call (0.46–0.81 ns
here, two pointers, no ownership). I keep `std::function` for stored callbacks where ownership and copying are the
point."
</details>

<details><summary><b>Chain 3 🔥 "function_ref: what's the catch?"</b></summary>

**Initial prompt.** "C++26 adds `std::function_ref`. Why not use it everywhere instead of `std::function`?"

**L5 textbook answer.** "It's faster and doesn't allocate, so yes."

**Why L5 breaks.** It does not own the callable: it is a pointer to an object plus a thunk (16 bytes, Listing 4.6).
`std::function_ref<int(int)> r = [](int x) { return x; };` as a member or local binds to a temporary lambda that dies at
the semicolon. Every later call is a use-after-free. It is the `string_view` of callables.

**L7 principal defense.** "`function_ref` for parameters of functions that call the callback before returning
(algorithms, visitors). Owning types for anything stored. Same discipline as `string_view`, and the same review rule:
no `function_ref` members."
</details>

<details><summary><b>Chain 4 🧊 "Implement type erasure without virtual functions"</b></summary>

**Initial prompt.** "Implement a type-erased callable without inheritance."

**L5 textbook answer.** "Use `void*` and a function pointer."

**Why L5 breaks.** That handles calling, not lifetime. You also need destroy, move (and maybe copy), alignment, and a
decision about where the object lives. Without a destroy slot, captured `std::string`s leak. Without a correct move,
copying the wrapper double-frees. Listing 4.8 shows the complete minimal set: a static vtable `{call, move_to, destroy}`
per erased type, a compile-time inline/heap decision that requires a `noexcept` move for inline storage, and
relocation on move.

**L7 principal defense.** "Static per-type vtables (`constexpr` variable templates) give virtual dispatch without a
heap-allocated base. Inline storage only for nothrow-movable types, so the wrapper's move is `noexcept`. I would test it
with a counting payload (constructions, moves, destructions must balance) and in a `constexpr` context where possible
(Folder 01)."
</details>

<details><summary><b>Chain 5 ⚡ "std::function and move-only lambdas"</b></summary>

**Initial prompt.** "Why doesn't `std::function<void()> f = [p = std::make_unique<int>()] {};` compile?"

**L5 textbook answer.** "`std::function` can't hold lambdas with captures."

**Why L5 breaks.** It holds capturing lambdas fine. The requirement is that the target be **copy-constructible**,
because `std::function` is copyable. The closure with a `unique_ptr` capture is move-only (Folder 02, Listing 2.1).
C++23 `std::move_only_function` drops the copy requirement (available in libstdc++ 16, not in libc++ 21 here).

**L7 principal defense.** "`move_only_function` for task queues and one-shot callbacks; a hand-written move-only
wrapper (Listing 4.8) where the library doesn't provide it. Wrapping the `unique_ptr` in a `shared_ptr` just to satisfy
`std::function` adds an atomic refcount and an allocation."
</details>

<details><summary><b>Chain 6 🧊 "The const hole in std::function"</b></summary>

**Initial prompt.** "Can a `const std::function` mutate state?"

**L5 textbook answer.** "No, const means const."

**Why L5 breaks.** `std::function::operator()` is `const`, but it calls the target as non-const. A `mutable` lambda's
state changes through a `const std::function&`. Two threads calling "const" callbacks concurrently race on that state.
`copyable_function` (C++26) and `move_only_function` (C++23) fix it by putting the qualifiers in the signature
(`copyable_function<void() const>` requires a const-callable target).

**L7 principal defense.** "For shared callbacks called from several threads, use `copyable_function<R(A...) const>` (or
document and enforce statelessness), so the type system expresses the thread-safety contract."
</details>

<details><summary><b>Chain 7 🔥 "Design a low-latency task queue's task type"</b></summary>

**Initial prompt.** "Each task is a closure; 10M tasks per second; no allocation on the hot path. Design the task type."

**L5 textbook answer.** "`std::function<void()>` in a lock-free queue."

**Why L5 breaks.** `std::function` allocates for any capture above 16 bytes, or any non-trivially-copyable capture on
libstdc++ (Listing 4.6), and its move is not guaranteed `noexcept` in all cases. At 10M/s an allocation per task is
the bottleneck, and the allocator becomes a contended shared resource across threads.

**L7 principal defense.** "A fixed-size, move-only, type-erased task with an inline buffer sized from measured captures
(Listing 4.8 with `Cap` = 48 or 64, one cache line per task), `static_assert` that every submitted callable fits,
`noexcept` relocation, and a slot array ring (Folder 09). Tasks that don't fit are rejected at compile time, not
silently heap-allocated."
</details>

<details><summary><b>Chain 8 ⚡ "std::bind vs lambdas"</b></summary>

**Initial prompt.** "Is `std::bind` still useful?"

**L5 textbook answer.** "Yes, for partial application."

**Why L5 breaks.** Lambdas do partial application more readably, with explicit capture semantics. `std::bind` copies its
bound arguments (surprising with references unless wrapped in `std::ref`), evaluates nested `bind` expressions eagerly,
silently ignores extra arguments, and produces types that are harder for the optimizer to see through. C++20
`std::bind_front` covers the one common use (binding leading arguments) without placeholders.

**L7 principal defense.** "Lambdas everywhere, `std::bind_front` for binding a member function to an object, and no
`std::bind` in new code."
</details>

---

## 6. Invariants checklist

- [ ] Callback parameters are templates or `function_ref`; stored callbacks are owning types.
- [ ] Task types have a measured inline buffer; captures on hot paths are small and trivially copyable.
- [ ] Move-only captures use `move_only_function` (or an equivalent), not `shared_ptr` workarounds.
- [ ] Empty callables are impossible by construction, or checked before calling.
- [ ] Callbacks shared across threads have const-qualified signatures (`copyable_function<R() const>`).
- [ ] No `function_ref` stored in members or containers.

## 7. References

- P0288R9 (`move_only_function`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2021/p0288r9.html>
- P2548R6 (`copyable_function`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2023/p2548r6.pdf>
- P0792R14 (`function_ref`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2023/p0792r14.html>
- abseil `AnyInvocable`: <https://github.com/abseil/abseil-cpp/blob/master/absl/functional/any_invocable.h>
- folly `Function`: <https://github.com/facebook/folly/blob/main/folly/Function.h>
- Sean Parent, "Inheritance Is the Base Class of Evil", GoingNative 2013 (type erasure).
