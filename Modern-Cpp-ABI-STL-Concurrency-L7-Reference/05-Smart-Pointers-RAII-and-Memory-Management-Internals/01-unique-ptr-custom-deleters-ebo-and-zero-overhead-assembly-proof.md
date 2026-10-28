# 01 · `unique_ptr`: custom deleters, EBO, and the zero-overhead claim, in assembly

> **Scope.** `std::unique_ptr` is the default owning handle in modern C++. "Zero overhead" is true in one precise
> sense and false in another, and both are visible in the generated code. This file shows the claim against raw
> `new`/`delete`, the cost of a stateful deleter, the ABI cost of passing ownership through a non-inlined call (built on
> Folder 01, file 02), and the semantic traps: non-virtual destructors, arrays, value-initialization and conversion to
> `shared_ptr`. Deleter compression (EBO, `[[no_unique_address]]`, the 16-byte `final` deleter) is in Folder 01, file 04.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 5.1 | `uptr_asm.cpp` | identical happy path to raw `new`/`delete` + a landing pad raw code lacks; passing by value through memory; stateless vs function-pointer deleters | `-O3` asm x86-64 + AArch64 |
| 5.2 | `uptr_semantics.cpp` | virtual destructors through `unique_ptr<Base>`; `make_unique<T[]>` zero-fills (19–31 ms for 128 MB), `make_unique_for_overwrite` does not; deleter carried into `shared_ptr`; **only Clang diagnoses a non-virtual destructor** | run + diagnostics, both compilers |

**Verification line.** Codegen: Clang 21.1 `-O3`, `x86_64-linux-gnu` and `aarch64-linux-gnu` (libc++). Runs: GCC 16.2 +
libstdc++ and Clang 21.1 + libc++ on Windows x86-64.

---

## 1. First principles

### 1.1 The zero-overhead claim, tested (Listing 5.1)

```cpp
// uptr_asm.cpp - is unique_ptr zero-overhead? Same function with raw new/delete and with unique_ptr, compiled
#include <cstdio>
#include <memory>

struct Widget {
    int a = 1, b = 2;
};
void consume(Widget*);                 // opaque: may throw, may keep nothing

// Raw ownership: correct only if consume() never throws.
int raw_owner() {
    Widget* w = new Widget;
    consume(w);
    int r = w->a + w->b;
    delete w;
    return r;
}
// unique_ptr ownership: the same happy path, plus the cleanup that raw_owner forgot (a landing pad).
int unique_owner() {
    auto w = std::make_unique<Widget>();
    consume(w.get());
    return w->a + w->b;
}
// Passing ownership across a non-inlined call: here the ABI cost of Folder 01 / file 02 appears.
void sink(std::unique_ptr<Widget> w);
void give_away() { sink(std::make_unique<Widget>()); }

// A stateful deleter (function pointer) is stored and called indirectly; a stateless one is free.
struct FileCloser {
    void operator()(std::FILE* f) const noexcept { std::fclose(f); }
};
using FileStateless = std::unique_ptr<std::FILE, FileCloser>;
using FileFnPtr = std::unique_ptr<std::FILE, int (*)(std::FILE*)>;
void close_stateless(FileStateless f) { f.reset(); }
void close_fnptr(FileFnPtr f) { f.reset(); }
```

Clang `-O3`, x86-64:

```asm
_Z9raw_ownerv:                     # raw_owner()
	pushq	%rbp
	pushq	%rbx
	pushq	%rax
	movl	$8, %edi
	callq	_Znwm@PLT                            # operator new(unsigned long)
	movq	%rax, %rbx
	movabsq	$8589934593, %rax
	movq	%rax, (%rbx)
	movq	%rbx, %rdi
	callq	_Z7consumeP6Widget@PLT               # consume(Widget*)
	movl	4(%rbx), %ebp
	addl	(%rbx), %ebp
	movl	$8, %esi
	movq	%rbx, %rdi
	callq	_ZdlPvm@PLT                          # operator delete(void*, unsigned long)
	movl	%ebp, %eax
	addq	$8, %rsp
	popq	%rbx
	popq	%rbp
	retq

_Z12unique_ownerv:                 # unique_owner()
	pushq	%rbp
	pushq	%r14
	pushq	%rbx
	movl	$8, %edi
	callq	_Znwm@PLT                            # operator new(unsigned long)
	movq	%rax, %rbx
	movabsq	$8589934593, %rax
	movq	%rax, (%rbx)
	movq	%rbx, %rdi
	callq	_Z7consumeP6Widget@PLT               # consume(Widget*)
	movl	4(%rbx), %ebp
	addl	(%rbx), %ebp
	movl	$8, %esi
	movq	%rbx, %rdi
	callq	_ZdlPvm@PLT                          # operator delete(void*, unsigned long)
	movl	%ebp, %eax
	popq	%rbx
	popq	%r14
	popq	%rbp
	retq
.Ltmp2:                                     # landing pad (entered only via the LSDA)
	movq	%rax, %r14
	movl	$8, %esi
	movq	%rbx, %rdi
	callq	_ZdlPvm@PLT                          # operator delete(void*, unsigned long)
	movq	%r14, %rdi
	callq	_Unwind_Resume@PLT

_Z9give_awayv:                     # give_away()
	pushq	%rbx
	subq	$16, %rsp
	movl	$8, %edi
	callq	_Znwm@PLT                            # operator new(unsigned long)
	movabsq	$8589934593, %rcx
	movq	%rcx, (%rax)
	movq	%rax, 8(%rsp)
	leaq	8(%rsp), %rdi
	callq	_Z4sinkNSt3__110unique_ptrI6WidgetNS_14default_deleteIS1_EEEE@PLT # sink(std::__1::unique_ptr<Widget, std::__1::default_delete<Widget> >)
	movq	8(%rsp), %rdi
	movq	$0, 8(%rsp)
	testq	%rdi, %rdi
	je	.LBB2_3
	movl	$8, %esi
	callq	_ZdlPvm@PLT                          # operator delete(void*, unsigned long)
.LBB2_3:
	addq	$16, %rsp
	popq	%rbx
	retq
.Ltmp5:                                     # landing pad (entered only via the LSDA)
	movq	%rax, %rbx
	movq	8(%rsp), %rdi
	movq	$0, 8(%rsp)
	testq	%rdi, %rdi
	je	.LBB2_6
	movl	$8, %esi
	callq	_ZdlPvm@PLT                          # operator delete(void*, unsigned long)
.LBB2_6:
	movq	%rbx, %rdi
	callq	_Unwind_Resume@PLT

_Z15close_statelessNSt3__110unique_ptrI8_IO_FILE10FileCloserEE: # close_stateless(std::__1::unique_ptr<_IO_FILE, FileCloser>)
	movq	%rdi, %rax
	movq	(%rdi), %rdi
	movq	$0, (%rax)
	testq	%rdi, %rdi
	jne	fclose@PLT
	retq

_Z11close_fnptrNSt3__110unique_ptrI8_IO_FILEPFiPS1_EEE: # close_fnptr(std::__1::unique_ptr<_IO_FILE, int (*)(_IO_FILE*)>)
	pushq	%rax
	movq	%rdi, %rax
	movq	(%rdi), %rdi
	movq	$0, (%rax)
	testq	%rdi, %rdi
	je	.LBB4_2
	callq	*8(%rax)
.LBB4_2:
	popq	%rax
	retq
.Ltmp8:                                     # landing pad (entered only via the LSDA)
	movq	%rax, %rdi
	callq	__clang_call_terminate
```

<details><summary>AArch64</summary>

```asm
_Z9raw_ownerv:                     // raw_owner()
	stp	x30, x21, [sp, #-32]!
	stp	x20, x19, [sp, #16]
	mov	w0, #8
	bl	_Znwm                                   // operator new(unsigned long)
	adrp	x8, .LCPI0_0
	mov	x19, x0
	ldr	d0, [x8, :lo12:.LCPI0_0]
	str	d0, [x0]
	bl	_Z7consumeP6Widget                      // consume(Widget*)
	ldp	w20, w21, [x19]
	mov	x0, x19
	mov	w1, #8
	bl	_ZdlPvm                                 // operator delete(void*, unsigned long)
	add	w0, w21, w20
	ldp	x20, x19, [sp, #16]
	ldp	x30, x21, [sp], #32
	ret

_Z12unique_ownerv:                 // unique_owner()
	stp	x30, x21, [sp, #-32]!
	stp	x20, x19, [sp, #16]
	mov	w0, #8
	bl	_Znwm                                   // operator new(unsigned long)
	mov	x8, #1
	mov	x19, x0
	movk	x8, #2, lsl #32
	str	x8, [x0]
	bl	_Z7consumeP6Widget                      // consume(Widget*)
	ldp	w20, w21, [x19]
	mov	x0, x19
	mov	w1, #8
	bl	_ZdlPvm                                 // operator delete(void*, unsigned long)
	add	w0, w21, w20
	ldp	x20, x19, [sp, #16]
	ldp	x30, x21, [sp], #32
	ret
.Ltmp2:                                     // landing pad (entered only via the LSDA)
	mov	x20, x0
	mov	x0, x19
	mov	w1, #8
	bl	_ZdlPvm                                 // operator delete(void*, unsigned long)
	mov	x0, x20
	bl	_Unwind_Resume

_Z9give_awayv:                     // give_away()
	sub	sp, sp, #32
	stp	x30, x19, [sp, #16]
	mov	w0, #8
	bl	_Znwm                                   // operator new(unsigned long)
	mov	x8, #1
	str	x0, [sp, #8]
	movk	x8, #2, lsl #32
	str	x8, [x0]
	add	x0, sp, #8
	bl	_Z4sinkNSt3__110unique_ptrI6WidgetNS_14default_deleteIS1_EEEE // sink(std::__1::unique_ptr<Widget, std::__1::default_delete<Widget> >)
	ldr	x0, [sp, #8]
	str	xzr, [sp, #8]
	cbz	x0, .LBB2_3
	mov	w1, #8
	bl	_ZdlPvm                                 // operator delete(void*, unsigned long)
.LBB2_3:
	ldp	x30, x19, [sp, #16]
	add	sp, sp, #32
	ret
.Ltmp5:                                     // landing pad (entered only via the LSDA)
	mov	x19, x0
	ldr	x0, [sp, #8]
	str	xzr, [sp, #8]
	cbz	x0, .LBB2_6
	mov	w1, #8
	bl	_ZdlPvm                                 // operator delete(void*, unsigned long)
.LBB2_6:
	mov	x0, x19
	bl	_Unwind_Resume

_Z15close_statelessNSt3__110unique_ptrI8_IO_FILE10FileCloserEE: // close_stateless(std::__1::unique_ptr<_IO_FILE, FileCloser>)
	mov	x8, x0
	ldr	x0, [x0]
	str	xzr, [x8]
	cbz	x0, .LBB3_2
	b	fclose
.LBB3_2:
	ret

_Z11close_fnptrNSt3__110unique_ptrI8_IO_FILEPFiPS1_EEE: // close_fnptr(std::__1::unique_ptr<_IO_FILE, int (*)(_IO_FILE*)>)
	str	x30, [sp, #-16]!
	mov	x8, x0
	ldr	x0, [x0]
	str	xzr, [x8]
	cbz	x0, .LBB4_2
	ldr	x8, [x8, #8]
	blr	x8
.LBB4_2:
	ldr	x30, [sp], #16
	ret
.Ltmp8:                                     // landing pad (entered only via the LSDA)
	bl	__clang_call_terminate
```

</details>

* **`raw_owner` and `unique_owner` have the same happy path**, instruction for instruction: `operator new(8)`, store
  the initial values (`movabsq $8589934593` = `{1, 2}` as one 64-bit store), call `consume`, load the fields,
  `operator delete(p, 8)`. `unique_ptr` costs nothing in time or space on the normal path.
* **`unique_owner` adds a landing pad** that `raw_owner` does not have: if `consume` throws, `unique_ptr` frees the
  widget and `raw_owner` leaks it. The "overhead" is the cleanup the raw version should have had. It lives in a cold
  section and costs nothing until an exception happens (Folder 01, file 02, §1.6).
* **Passing ownership by value through a non-inlined call is not free.** `give_away` materializes the `unique_ptr` in a
  stack slot, passes its address, and after `sink` returns, reloads it, null-tests it and possibly deletes. It also
  needs a landing pad. `unique_ptr` has a non-trivial destructor, so it is "non-trivial for the purposes of calls"
  and travels through memory (Folder 01, file 02, §1.4). A raw pointer would travel in RDI.
* **Stateless deleter vs function pointer.** `close_stateless` tail-calls `fclose` directly (the deleter type *is*
  the code). `close_fnptr` loads the stored function pointer and calls it indirectly (`callq *8(%rax)`), and the
  `unique_ptr` is 16 bytes. Because `reset()` is `noexcept` and an arbitrary function pointer might throw, it also
  carries a `__clang_call_terminate` landing pad.

### 1.2 Semantics that bite (Listing 5.2)

```cpp
// uptr_semantics.cpp - unique_ptr's sharp edges: base without virtual dtor, arrays, for_overwrite, to shared_ptr
#include <chrono>
#include <cstddef>
#include <memory>
#include <print>

int g_base_dtor = 0, g_derived_dtor = 0;
struct Base {
    virtual void hello() const {}
    virtual ~Base() { ++g_base_dtor; }
};
struct Derived : Base {
    ~Derived() override { ++g_derived_dtor; }
};
#ifdef SHOW_NONVIRTUAL_DTOR
struct BadBase {                       // polymorphic, but the destructor is not virtual
    virtual void hello() const {}
    ~BadBase() {}
};
struct BadDerived : BadBase {};
void bad() { std::unique_ptr<BadBase> p = std::make_unique<BadDerived>(); }  // ~BadDerived never runs: UB
#endif

int main() {
    { std::unique_ptr<Base> p = std::make_unique<Derived>(); }
    std::println("virtual ~Base: ~Derived ran {} time(s), ~Base ran {} time(s)", g_derived_dtor, g_base_dtor);

    // Arrays: unique_ptr<T[]> calls delete[]; make_unique<T[]>(n) value-initializes (zeroes) every element.
    constexpr std::size_t kN = 32 * 1024 * 1024;  // 128 MB of int
    auto t0 = std::chrono::steady_clock::now();
    auto zeroed = std::make_unique<int[]>(kN);
    auto t1 = std::chrono::steady_clock::now();
    auto raw = std::make_unique_for_overwrite<int[]>(kN);  // C++20: default-initialized (no zeroing)
    auto t2 = std::chrono::steady_clock::now();
    zeroed[kN - 1] = 1;
    raw[kN - 1] = 1;
    auto ms = [](auto d) { return std::chrono::duration<double, std::milli>(d).count(); };
    std::println("128 MB int array: make_unique {:.1f} ms (zero-fills), make_unique_for_overwrite {:.3f} ms",
                 ms(t1 - t0), ms(t2 - t1));

    // unique_ptr -> shared_ptr: the deleter moves into the control block (and out of the type).
    int deleted = 0;
    auto counting = [&deleted](int* p) { ++deleted; delete p; };
    std::unique_ptr<int, decltype(counting)> u(new int(5), counting);
    std::shared_ptr<int> s = std::move(u);
    s.reset();
    std::println("custom deleter ran after conversion to shared_ptr: {}", deleted == 1);
    std::println("sizeof: unique_ptr<int>={} unique_ptr<int, decltype(counting)>={} shared_ptr<int>={}",
                 sizeof(std::unique_ptr<int>), sizeof(std::unique_ptr<int, decltype(counting)>), sizeof(s));
}
```

GCC 16.2 + libstdc++ (one run):

```text
virtual ~Base: ~Derived ran 1 time(s), ~Base ran 1 time(s)
128 MB int array: make_unique 18.0 ms (zero-fills), make_unique_for_overwrite 0.000 ms
custom deleter ran after conversion to shared_ptr: true
sizeof: unique_ptr<int>=8 unique_ptr<int, decltype(counting)>=16 shared_ptr<int>=16
```

Clang 21.1 + libc++ (one run):

```text
virtual ~Base: ~Derived ran 1 time(s), ~Base ran 1 time(s)
128 MB int array: make_unique 37.2 ms (zero-fills), make_unique_for_overwrite 0.044 ms
custom deleter ran after conversion to shared_ptr: true
sizeof: unique_ptr<int>=8 unique_ptr<int, decltype(counting)>=16 shared_ptr<int>=16
```

With `-DSHOW_NONVIRTUAL_DTOR` (a polymorphic base with a non-virtual destructor, deleted through `unique_ptr<Base>`):

```text
unique_ptr.h:77:5: error: delete called on non-final 'BadDerived' that has virtual functions but non-virtual destructor [-Werror,-Wdelete-non-abstract-non-virtual-dtor]
unique_ptr.h:77:5: error: delete called on non-final 'BadBase' that has virtual functions but non-virtual destructor [-Werror,-Wdelete-non-abstract-non-virtual-dtor]
uptr_semantics.cpp: compiled with NO diagnostic (gcc)
```

* **Deleting through `unique_ptr<Base>` needs a virtual destructor** (or a deleter that knows the real type). Without
  one, `~Derived` never runs: UB, typically leaking everything `Derived` owns. **Clang diagnoses it**
  (`-Wdelete-non-abstract-non-virtual-dtor`, on by default with `-Wall`), even though the `delete` is inside libc++'s
  `default_delete`. **GCC 16.2 compiles it silently**: its `-Wdelete-non-virtual-dtor` exists, but the `delete`
  expression sits in a system header, where GCC suppresses warnings. The bug is only caught on the Clang build.
* **`make_unique<T[]>(n)` value-initializes**: 128 MB of `int` is zero-filled (19–31 ms here, the cost of touching every
  page). C++20 `make_unique_for_overwrite<T[]>(n)` default-initializes (no fill), which is right for buffers you are
  about to overwrite (I/O, decompression). The allocation itself is nearly free because the OS maps zero pages lazily.
* **Converting to `shared_ptr` keeps the deleter**: it moves from the `unique_ptr`'s *type* into the `shared_ptr`'s
  control block, which is type-erased (file 02). That is why `shared_ptr<T>` has one type whatever the deleter, while
  `unique_ptr<T, D>` makes the deleter part of the type.
* `sizeof(unique_ptr<int, decltype(lambda)>)` is 16 here because the lambda *captures* (`&deleted`). A captureless
  lambda deleter is free (Folder 01, file 04, Listing 4.4).

---

## 2. Evolution table

| Feature | Standard (paper) | Notes |
|---|---|---|
| `unique_ptr`, move-only ownership; `auto_ptr` deprecated | C++11 (N1856 lineage) | `auto_ptr` removed in C++17 |
| `make_unique` | C++14 (N3656) | exception safety in argument lists |
| `unique_ptr<T[]>` converting constructors | C++17 (N4089) | array form with `delete[]` |
| `make_unique_for_overwrite`, `make_shared_for_overwrite` | C++20 (P1020R1) | default-initialization for buffers |
| `operator<=>` | C++20 | — |
| `constexpr unique_ptr` | C++23 (P2273R3) | usable in constant evaluation |
| `std::out_ptr`, `std::inout_ptr` | C++23 (P1132R8) | adapters for C APIs that return pointers through `T**` |
| trivial-ABI `unique_ptr` | not standard | libc++ ABI v2 (`_LIBCPP_ABI_ENABLE_UNIQUE_PTR_TRIVIAL_ABI`), Folder 01 |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| C resource (FILE*, sockets) | `unique_ptr<FILE, decltype(&fclose)>` (16 B, indirect call) | an empty deleter struct: `unique_ptr<FILE, FileCloser>` (8 B, direct call) |
| deleting through a base | `unique_ptr<Base>` with a non-virtual destructor | virtual (or protected non-virtual) destructor; build with Clang in CI to catch it |
| buffer you will overwrite | `make_unique<char[]>(n)` (zero-fills) | `make_unique_for_overwrite<char[]>(n)` |
| C API returning `T**` | `T* raw; api(&raw); std::unique_ptr<T, D> p(raw);` (leaks if something throws in between) | `api(std::out_ptr(p))` (C++23) |
| ownership through a hot non-inline API | `void f(std::unique_ptr<T>)` on a hot path | measure; consider `T*` + documented ownership, or a `trivial_abi` handle in ABI-controlled code |
| optional ownership | `unique_ptr` + a separate flag | `unique_ptr` null state is the flag |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| leaks of derived-class resources | `unique_ptr<Base>` + non-virtual destructor | Clang `-Wdelete-non-abstract-non-virtual-dtor`; ASan leak checker |
| a 2× slower allocation path for large buffers | value-initialization of arrays | `make_unique_for_overwrite` |
| double free | two `unique_ptr`s from the same raw pointer | ASan; never construct from a raw pointer you don't own exclusively |
| use after `release()` | `release()` gives up ownership without freeing | prefer `std::move`; treat `release()` as an FFI-only operation |
| deleter not called on a C handle | wrong deleter type, or `release()` | review deleters together with the acquire function |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "Is unique_ptr zero-cost?"</b></summary>

**Initial prompt.** "Prove or disprove: `std::unique_ptr` has zero overhead compared with a raw pointer."

**L5 textbook answer.** "Zero overhead: same size, and all operations inline."

**Why L5 breaks.** Half right, and Listing 5.1 shows both halves. Within a function, the happy path is identical
instruction for instruction, and the extra landing pad is *correctness* (raw code leaks on exceptions). Across a
non-inlined call boundary, passing a `unique_ptr` by value makes the caller spill it to memory, pass a pointer, and
destroy it afterwards (`give_away`): a real cost that a raw pointer does not have. A function-pointer deleter also
doubles the size and adds an indirect call.

**L7 principal defense.** "Zero overhead in space and in the local happy path; non-zero at ABI boundaries, because
`unique_ptr` is non-trivial for calls. I keep ownership transfer out of the hottest non-inlined paths, use empty deleter
types, and know that libc++'s unstable ABI can make `unique_ptr` trivially relocatable for calls."
</details>

<details><summary><b>Chain 2 🔥 "Why does my unique_ptr<Base> leak?"</b></summary>

**Initial prompt.** "`std::unique_ptr<Shape> s = std::make_unique<Circle>();` and Circle's members leak. Why?"

**L5 textbook answer.** "You forgot to call `delete`."

**Why L5 breaks.** `unique_ptr` did call `delete` on a `Shape*`. Without a virtual destructor in `Shape`, that runs
only `~Shape`: UB, and in practice `~Circle` and its members are skipped. Listing 5.2 shows that only Clang warns
here. GCC is silent because the `delete` happens inside a system header.

**L7 principal defense.** "Any class that is deleted polymorphically gets a virtual destructor. Classes not meant for
that get a protected non-virtual one, or `final`. CI builds with Clang so `-Wdelete-non-abstract-non-virtual-dtor`
catches what GCC hides. `shared_ptr<Base>(new Derived)` would have worked by accident, because its control block
remembers the real type, and that accident hides the bug in mixed code bases."
</details>

<details><summary><b>Chain 3 ⚡ "Function pointer or functor deleter?"</b></summary>

**Initial prompt.** "Which deleter type for wrapping `FILE*`?"

**L5 textbook answer.** "`decltype(&fclose)` is simplest."

**Why L5 breaks.** Simplest to write, worst to run. A function pointer is *state*: the `unique_ptr` grows to 16 bytes
and calls through a stored pointer (Listing 5.1: `callq *8(%rax)` plus a terminate landing pad). An empty functor
type is 0 bytes and the call is direct (`jne fclose`). There is also a portability trap: taking the address of a
standard-library function (`&fclose`) is unspecified for many functions (they may be macros or overloaded).

**L7 principal defense.** "A tiny empty struct deleter for every C resource, ideally generated by a template
(`template <auto F> struct Fn { void operator()(auto* p) const { F(p); } };`), which keeps the handle at 8 bytes and
the call direct. Don't make it `final` (Folder 01: `final` deleters are not compressed)."
</details>

<details><summary><b>Chain 4 🧊 "make_unique<char[]>(n) is slow"</b></summary>

**Initial prompt.** "Allocating a 128 MB buffer with `make_unique<char[]>` takes 20–30 ms. Malloc takes microseconds.
Why?"

**L5 textbook answer.** "make_unique is slower than malloc."

**Why L5 breaks.** The allocation is the same. `make_unique<T[]>(n)` *value-initializes*, so it writes zeros to every
byte, which also faults in every page. malloc of a large block maps pages lazily and does not touch them. Listing 5.2:
19–31 ms vs ~0 ms for `make_unique_for_overwrite`.

**L7 principal defense.** "`make_unique_for_overwrite` (C++20) for buffers that will be filled anyway; `make_unique` when
zeros are actually needed. And the real cost (page faults) arrives on first touch either way, so for latency-critical
paths I pre-fault buffers at start-up."
</details>

<details><summary><b>Chain 5 ⚡ "release() vs move"</b></summary>

**Initial prompt.** "When do you use `unique_ptr::release()`?"

**L5 textbook answer.** "To get the raw pointer out."

**Why L5 breaks.** That is `get()`. `release()` *gives up ownership* without freeing: after it, nobody owns the object
unless the caller takes over. Using it to "pass to a function" leaks, or causes a double free when the callee also
wraps it. In C++23, the right tool for C APIs that take ownership or return a new pointer is `std::out_ptr` /
`std::inout_ptr`.

**L7 principal defense.** "`std::move` for transfers between owners; `get()` for non-owning access; `release()` only at an
FFI boundary that documents taking ownership, immediately at the call site. `out_ptr` for output parameters."
</details>

<details><summary><b>Chain 6 🧊 "unique_ptr in a container: what breaks?"</b></summary>

**Initial prompt.** "Any issues with `std::vector<std::unique_ptr<Order>>`?"

**L5 textbook answer.** "No, unique_ptr is movable, so it works in vectors."

**Why L5 breaks.** It works. The L7 points: growth moves the pointers (cheap, `noexcept`, and libc++ memcpy-relocates
them, Folder 01, file 04); `std::initializer_list` construction does not compile (elements are copied, Folder 02);
iteration is a pointer chase per element (cache misses: often 5–10× slower than a `vector<Order>`); and algorithms that
copy (`std::copy`, `std::fill`) don't compile.

**L7 principal defense.** "`vector<unique_ptr<T>>` when objects must not move (their address is stored elsewhere) or are
polymorphic. Otherwise `vector<T>` for locality. For stable addresses with good locality, a `deque` or a hive (Folder
03)."
</details>

<details><summary><b>Chain 7 🔥 "Implement unique_ptr"</b></summary>

**Initial prompt.** "Write a minimal `unique_ptr<T, D>`."

**L5 textbook answer.** A class with a `T*`, a destructor that deletes, a deleted copy constructor and a move constructor.

**Why L5 breaks.** Missing pieces show up in review: the deleter must be stored with EBO/`[[no_unique_address]]`
(otherwise every `unique_ptr` is 16 bytes); move assignment must reset the old pointer *after* taking the new one
(self-move safety) and must be `noexcept`; `reset(p)` must store the new pointer before deleting the old one (the old
deleter may reach this object); conversion from `unique_ptr<Derived>` needs constrained templates; and the array
specialization uses `delete[]` and forbids derived-to-base conversion (pointer arithmetic on base pointers is wrong).

**L7 principal defense.** "Pointer + `[[no_unique_address]]` deleter, `noexcept` moves, `reset` that swaps first and
deletes second, constrained converting constructors, a separate `T[]` specialization. Folder 11 file 02 builds it with
tests."
</details>

<details><summary><b>Chain 8 ⚡ "Pass unique_ptr by value or by reference?"</b></summary>

**Initial prompt.** "How should a function take a `unique_ptr` parameter?"

**L5 textbook answer.** "Always by const reference, to avoid copies."

**Why L5 breaks.** `const unique_ptr<T>&` says nothing useful: the function can't take ownership and could have taken
`T&` or `T*`. The parameter type should state intent. By value: "I take ownership" (caller must `std::move`). `T&` /
`T*`: "I use it, you keep it". `unique_ptr<T>&`: "I may reset or replace it" (rare). Listing 5.1's `give_away` shows that
by-value has a call-site cost, so it should be used when ownership really moves.

**L7 principal defense.** "Ownership in the type: by value to sink, `T&`/`T*` to borrow, `unique_ptr&` only for in-place
replacement. I would not pass `const unique_ptr&`."
</details>

---

## 6. Invariants checklist

- [ ] Polymorphically deleted classes have virtual destructors; CI includes a Clang build to catch the GCC-silent case.
- [ ] C-resource deleters are empty types, not function pointers; not `final`.
- [ ] Buffers to be overwritten use `make_unique_for_overwrite`.
- [ ] `release()` appears only at documented FFI ownership transfers; `out_ptr` for output parameters (C++23).
- [ ] Ownership transfer by value is kept off the hottest non-inlined paths.
- [ ] Parameter types encode ownership intent (by value = sink, `T&`/`T*` = borrow).

## 7. References

- N3656 (`make_unique`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2013/n3656.htm>
- P1020R1 (`make_unique_for_overwrite`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2018/p1020r1.html>
- P1132R8 (`out_ptr`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2021/p1132r8.html>
- P2273R3 (`constexpr unique_ptr`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2021/p2273r3.pdf>
- Herb Sutter, GotW #91 "Smart Pointer Parameters": <https://herbsutter.com/2013/06/05/gotw-91-solution-smart-pointer-parameters/>
