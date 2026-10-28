# 03 · `std::atomic` internals: CAS strong vs weak, 16-byte atomics, `atomic_ref`, and `atomic<shared_ptr>`

> **Scope.** `std::atomic<T>` is a type with library-specific size, alignment and lock-freedom. Its operations
> become single instructions, load-exclusive/store-exclusive loops, or calls into a lock table, depending on `T`, the
> library and `-march`. This file shows each case: what `compare_exchange_weak` and `compare_exchange_strong` compile
> to, why weak can fail when the values match, what a 16-byte atomic costs on six targets, how `atomic_ref` puts atomic
> operations on plain memory, and how libstdc++ implements `atomic<shared_ptr>` (with a lock bit). Two of the results
> are cross-library differences that break code moved from GCC to Clang.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 7.7 | `cas_asm.cpp` | weak = one LL/SC attempt, strong = an inner retry loop (nested loops in a CAS loop) on ARMv8.0; identical on x86 and with LSE; `fetch_max` = one `LDSMAXAL` with LSE | asm: Clang x86-64, AArch64 v8.0, Neoverse N1 |
| 7.8 | `wide_atomic.cpp` | a 16-byte atomic **load** is a library call, a `LOCK CMPXCHG16B`, a `VMOVDQA`, an `LDAXP`/`STXP` loop, a `CASPA` or an `LDP` depending on target | asm: 4 x86-64 and 3 AArch64 configurations |
| 7.9 | `atomic_props.cpp` | `atomic<T>` size/alignment/lock-freedom per library; **libstdc++ and libc++ lay out `atomic<char[3]-struct>` differently**; **libc++ 21's CAS fails on padding bytes** | run, both compilers, with and without `-mcx16` |
| 7.10 | `cas_contention.cpp` | under contention a CAS loop costs 2–4× `fetch_add` and fails 0.4–1.2 times per increment | run, 1/2/4 threads |
| 7.11 | `atomic_ref_ring.cpp` | an SPSC ring in raw "shared memory" whose indices are plain `uint64_t`, accessed through `atomic_ref` | run, 2 threads, 2M values |
| 7.12 | `atomic_sp.cpp` + libstdc++ excerpt | `atomic<shared_ptr>` hot swap with 0 torn reads; it is a lock bit in the control-block pointer, not lock-free; load ≈ 17 ns | run (GCC only: libc++ 21 does not provide it) |
| 7.13 | `sp_free_functions.cpp` | the C++11 `atomic_load(&sp)` free functions: GCC warns (deprecated), libc++ is silent; nothing stops a plain access | expected diagnostics |

**Verification line.** As in file 01. AArch64 is compiled, not run (⚠). GCC needs `-latomic` for the non-lock-free
sizes; Clang (zig) gets those entry points from compiler-rt.

---

## 1. First principles

### 1.1 What `std::atomic<T>` is, per library (Listing 7.9)

```cpp
// atomic_props.cpp - what std::atomic<T> really is per library: size, alignment, lock-freedom, padding, extras
#include <atomic>
#include <cstdint>
#include <cstring>
#include <memory>
#include <new>
#include <print>

struct Odd3 { char c[3]; };                       // 3 bytes: not a power of two
struct Tagged { void* p; std::uint64_t tag; };    // 16 bytes, alignof 8 (no alignas)
struct Big24 { std::uint64_t a, b, c; };          // 24 bytes: no instruction is that wide
struct Padded { char c; int i; };                 // 3 padding bytes after c

template <class T>
void row(const char* name) {
    std::println("{:<22} {:>4} {:>5}   {:>4} {:>5}   {:<5}   {:>3}", name, sizeof(T), alignof(T),
                 sizeof(std::atomic<T>), alignof(std::atomic<T>), std::atomic<T>::is_always_lock_free ? "yes" : "no",
                 std::atomic_ref<T>::required_alignment);
}

int main() {
    std::println("{:<22} {:>4} {:>5}   {:>4} {:>5}   {:<5}   {}", "T", "size", "align", "A sz", "A al",
                 "lockf", "atomic_ref align");
    row<char>("char");
    row<int>("int");
    row<long long>("long long");
    row<Odd3>("Odd3 {char[3]}");
    row<Padded>("Padded {char; int}");
    row<Tagged>("Tagged {void*; u64}");
    row<Big24>("Big24 {u64 x3}");

    // C++20 (P0528): compare_exchange compares VALUES, so padding bytes must not make it fail.
    std::atomic<Padded> a{Padded{1, 2}};
    Padded expected;
    std::memset(&expected, 0xFF, sizeof expected);   // dirty padding
    expected.c = 1;
    expected.i = 2;
    const bool ok = a.compare_exchange_strong(expected, Padded{3, 4});
    std::println("CAS with dirty padding bytes in 'expected': {}", ok ? "succeeds (padding ignored)" : "FAILS");

    std::println("hardware_destructive_interference_size = {}, constructive = {}",
                 std::hardware_destructive_interference_size, std::hardware_constructive_interference_size);
#if defined(__cpp_lib_atomic_shared_ptr)
    std::atomic<std::shared_ptr<int>> sp;
    std::println("atomic<shared_ptr<int>>: sizeof {}, is_lock_free {}", sizeof(sp), sp.is_lock_free() ? "yes" : "no");
#else
    std::println("atomic<shared_ptr<int>>: not provided by this library");
#endif
#if defined(__cpp_lib_atomic_min_max)
    std::atomic<int> m{5};
    const int old = m.fetch_max(9);   // sequenced first: argument evaluation order is unspecified
    std::println("C++26 fetch_max: old {} -> new {}", old, m.load());
#else
    std::println("C++26 fetch_max: not provided by this library");
#endif
}
```

Output (verified): GCC/libstdc++, Clang/libc++, then Clang/libc++ with `-mcx16`:

```text
T                      size align   A sz  A al   lockf   atomic_ref align
char                      1     1      1     1   yes       1
int                       4     4      4     4   yes       4
long long                 8     8      8     8   yes       8
Odd3 {char[3]}            3     1      3     1   no        1
Padded {char; int}        8     4      8     8   yes       8
Tagged {void*; u64}      16     8     16    16   no       16
Big24 {u64 x3}           24     8     24     8   no        8
CAS with dirty padding bytes in 'expected': succeeds (padding ignored)
hardware_destructive_interference_size = 64, constructive = 64
atomic<shared_ptr<int>>: sizeof 16, is_lock_free no
C++26 fetch_max: old 5 -> new 9
```

```text
T                      size align   A sz  A al   lockf   atomic_ref align
char                      1     1      1     1   yes       1
int                       4     4      4     4   yes       4
long long                 8     8      8     8   yes       8
Odd3 {char[3]}            3     1      4     4   yes       1
Padded {char; int}        8     4      8     8   yes       8
Tagged {void*; u64}      16     8     16    16   no       16
Big24 {u64 x3}           24     8     24     8   no        8
CAS with dirty padding bytes in 'expected': FAILS
hardware_destructive_interference_size = 64, constructive = 64
atomic<shared_ptr<int>>: not provided by this library
C++26 fetch_max: not provided by this library
```

```text
T                      size align   A sz  A al   lockf   atomic_ref align
char                      1     1      1     1   yes       1
int                       4     4      4     4   yes       4
long long                 8     8      8     8   yes       8
Odd3 {char[3]}            3     1      4     4   yes       1
Padded {char; int}        8     4      8     8   yes       8
Tagged {void*; u64}      16     8     16    16   yes      16
Big24 {u64 x3}           24     8     24     8   no        8
CAS with dirty padding bytes in 'expected': FAILS
hardware_destructive_interference_size = 64, constructive = 64
atomic<shared_ptr<int>>: not provided by this library
C++26 fetch_max: not provided by this library
```

(GCC with `-mcx16` prints the same as without: libstdc++ never treats 16 bytes as always-lock-free.)

* **`atomic<T>` raises the alignment to the size** when the size is 1, 2, 4, 8 or 16 bytes. That's why
  `Padded {char; int}` (alignof 4) becomes an 8-aligned 8-byte atomic, and `Tagged` (alignof 8) a 16-aligned one.
  `atomic_ref<T>::required_alignment` carries the same rule to plain objects: **an ordinary `Padded` at an address that
  is 4 mod 8 cannot be used with `atomic_ref<Padded>`.**
* **`Odd3` (3 bytes) differs between the libraries.** libstdc++: size 3, align 1, not always-lock-free (libatomic calls).
  libc++: size 4, align 4, lock-free (Clang's `_Atomic` rounds the size up). The same struct containing an
  `std::atomic<Odd3>` has **a different layout under the two libraries**, an ABI break for any header shared across that
  boundary.
* **16 bytes** is lock-free only with Clang and `-mcx16` (or a `-march` that implies it). libstdc++ says no even with
  `-mcx16` and calls libatomic, which picks an implementation at run time (§1.3).
* **Padding and CAS (P0528, C++20):** `compare_exchange` must compare *values*, so padding bytes must not make it
  fail. libstdc++ clears padding (`__builtin_clear_padding`) and the CAS succeeds. **libc++ 21 compares the bytes, and the
  CAS fails** although every member matches. A strong CAS that fails while the values are equal breaks every protocol
  that reads failure as "someone else changed it".
* `hardware_destructive_interference_size` is 64 in both libraries on x86-64 (file 04 measures what it is for). C++26
  `fetch_max` (P0493) and `atomic<shared_ptr>` exist only in libstdc++ here.

### 1.2 `compare_exchange_weak` vs `strong` (Listing 7.7)

```cpp
// cas_asm.cpp - compare_exchange_weak vs strong: one instruction on x86 and ARMv8.1 LSE, LL/SC on ARMv8.0
#include <atomic>

using A = std::atomic<int>;
constexpr auto acq_rel = std::memory_order_acq_rel;
constexpr auto acq = std::memory_order_acquire;
constexpr auto rlx = std::memory_order_relaxed;

bool cas_weak(A& a, int& expected, int desired) { return a.compare_exchange_weak(expected, desired, acq_rel, acq); }
bool cas_strong(A& a, int& expected, int desired) {
    return a.compare_exchange_strong(expected, desired, acq_rel, acq);
}

// A CAS loop. With weak, a spurious failure simply goes round the caller's loop once more.
int max_loop_weak(A& a, int v) {
    int cur = a.load(rlx);
    while (cur < v && !a.compare_exchange_weak(cur, v, acq_rel, rlx)) {
    }
    return cur;
}
// The same loop with strong: on LL/SC the library adds an inner retry loop for spurious failures.
int max_loop_strong(A& a, int v) {
    int cur = a.load(rlx);
    while (cur < v && !a.compare_exchange_strong(cur, v, acq_rel, rlx)) {
    }
    return cur;
}
// C++26 atomic<int>::fetch_max (P0493) in libstdc++ 16 is this builtin: one LDSMAXAL with LSE.
int fetch_max_builtin(int* p, int v) { return __atomic_fetch_max(p, v, __ATOMIC_ACQ_REL); }
```

AArch64 v8.0 (Clang 21 `-O3`):

```asm
_Z8cas_weakRNSt3__16atomicIiEERii: // cas_weak(std::__1::atomic<int>&, int&, int)
	ldr	w9, [x1]
	ldaxr	w8, [x0]
	cmp	w8, w9
	b.ne	.LBB0_2
	stlxr	w9, w2, [x0]
	cmp	w9, #0
	csetm	w9, eq
	tbz	w9, #0, .LBB0_3
	b	.LBB0_4
.LBB0_2:
	mov	w9, wzr
	clrex
	tbnz	w9, #0, .LBB0_4
.LBB0_3:
	str	w8, [x1]
.LBB0_4:
	and	w0, w9, #0x1
	ret

_Z10cas_strongRNSt3__16atomicIiEERii: // cas_strong(std::__1::atomic<int>&, int&, int)
	ldr	w9, [x1]
.LBB1_1:
	ldaxr	w8, [x0]
	cmp	w8, w9
	b.ne	.LBB1_4
	stlxr	w10, w2, [x0]
	cbnz	w10, .LBB1_1
	mov	w0, #1
	tbz	w0, #0, .LBB1_5
	b	.LBB1_6
.LBB1_4:
	mov	w0, wzr
	clrex
	tbnz	w0, #0, .LBB1_6
.LBB1_5:
	str	w8, [x1]
.LBB1_6:
	ret

_Z13max_loop_weakRNSt3__16atomicIiEEi: // max_loop_weak(std::__1::atomic<int>&, int)
	mov	x8, x0
	ldr	w0, [x0]
	cmp	w0, w1
	b.ge	.LBB2_5
.LBB2_1:
	ldaxr	w9, [x8]
	cmp	w9, w0
	b.ne	.LBB2_3
	stlxr	w10, w1, [x8]
	cmp	w10, #0
	csetm	w10, eq
	tbz	w10, #0, .LBB2_4
	b	.LBB2_5
.LBB2_3:
	mov	w10, wzr
	clrex
	tbnz	w10, #0, .LBB2_5
.LBB2_4:
	cmp	w9, w1
	mov	w0, w9
	b.lt	.LBB2_1
.LBB2_5:
	ret

_Z15max_loop_strongRNSt3__16atomicIiEEi: // max_loop_strong(std::__1::atomic<int>&, int)
	ldr	w9, [x0]
	cmp	w9, w1
	b.ge	.LBB3_8
.LBB3_1:
	mov	w8, w9
.LBB3_2:
	ldaxr	w9, [x0]
	cmp	w9, w8
	b.ne	.LBB3_5
	stlxr	w10, w1, [x0]
	cbnz	w10, .LBB3_2
	mov	w10, #1
	tbz	w10, #0, .LBB3_6
	b	.LBB3_7
.LBB3_5:
	mov	w10, wzr
	clrex
	tbnz	w10, #0, .LBB3_7
.LBB3_6:
	cmp	w9, w1
	mov	w8, w9
	b.lt	.LBB3_1
.LBB3_7:
	mov	w0, w8
	ret
.LBB3_8:
	mov	w8, w9
	mov	w0, w8
	ret

_Z17fetch_max_builtinPii:          // fetch_max_builtin(int*, int)
.LBB4_1:
	ldaxr	w8, [x0]
	cmp	w8, w1
	csel	w9, w8, w1, gt
	stlxr	w10, w9, [x0]
	cbnz	w10, .LBB4_1
	mov	w0, w8
	ret
```

Neoverse N1 (ARMv8.2 + LSE):

```asm
_Z8cas_weakRNSt3__16atomicIiEERii: // cas_weak(std::__1::atomic<int>&, int&, int)
	ldr	w9, [x1]
	mov	w8, w9
	casal	w8, w2, [x0]
	cmp	w8, w9
	cset	w0, eq
	b.eq	.LBB0_2
	str	w8, [x1]
.LBB0_2:
	ret

_Z10cas_strongRNSt3__16atomicIiEERii: // cas_strong(std::__1::atomic<int>&, int&, int)
	ldr	w9, [x1]
	mov	w8, w9
	casal	w8, w2, [x0]
	cmp	w8, w9
	cset	w0, eq
	b.eq	.LBB1_2
	str	w8, [x1]
.LBB1_2:
	ret

_Z13max_loop_weakRNSt3__16atomicIiEEi: // max_loop_weak(std::__1::atomic<int>&, int)
	mov	x8, x0
	ldr	w0, [x0]
	cmp	w0, w1
	b.ge	.LBB2_4
	mov	w9, w0
.LBB2_2:
	casal	w9, w1, [x8]
	cmp	w9, w0
	b.eq	.LBB2_4
	cmp	w9, w1
	mov	w0, w9
	b.lt	.LBB2_2
.LBB2_4:
	ret

_Z15max_loop_strongRNSt3__16atomicIiEEi: // max_loop_strong(std::__1::atomic<int>&, int)
	mov	x8, x0
	ldr	w0, [x0]
	cmp	w0, w1
	b.ge	.LBB3_4
	mov	w9, w0
.LBB3_2:
	casal	w9, w1, [x8]
	cmp	w9, w0
	b.eq	.LBB3_4
	cmp	w9, w1
	mov	w0, w9
	b.lt	.LBB3_2
.LBB3_4:
	ret

_Z17fetch_max_builtinPii:          // fetch_max_builtin(int*, int)
	ldsmaxal	w1, w0, [x0]
	ret
```

x86-64:

```asm
_Z8cas_weakRNSt3__16atomicIiEERii: # cas_weak(std::__1::atomic<int>&, int&, int)
	movl	(%rsi), %eax
	lock	cmpxchgl	%edx, (%rdi)
	sete	%cl
	je	.LBB0_2
	movl	%eax, (%rsi)
.LBB0_2:
	movl	%ecx, %eax
	retq

_Z10cas_strongRNSt3__16atomicIiEERii: # cas_strong(std::__1::atomic<int>&, int&, int)
	movl	(%rsi), %eax
	lock	cmpxchgl	%edx, (%rdi)
	sete	%cl
	je	.LBB1_2
	movl	%eax, (%rsi)
.LBB1_2:
	movl	%ecx, %eax
	retq

_Z13max_loop_weakRNSt3__16atomicIiEEi: # max_loop_weak(std::__1::atomic<int>&, int)
	movl	(%rdi), %ecx
	cmpl	%esi, %ecx
	jge	.LBB2_3
.LBB2_1:
	movl	%ecx, %eax
	lock	cmpxchgl	%esi, (%rdi)
	je	.LBB2_3
	movl	%eax, %ecx
	cmpl	%esi, %eax
	jl	.LBB2_1
.LBB2_3:
	movl	%ecx, %eax
	retq

_Z15max_loop_strongRNSt3__16atomicIiEEi: # max_loop_strong(std::__1::atomic<int>&, int)
	movl	(%rdi), %ecx
	cmpl	%esi, %ecx
	jge	.LBB3_3
.LBB3_1:
	movl	%ecx, %eax
	lock	cmpxchgl	%esi, (%rdi)
	je	.LBB3_3
	movl	%eax, %ecx
	cmpl	%esi, %eax
	jl	.LBB3_1
.LBB3_3:
	movl	%ecx, %eax
	retq

_Z17fetch_max_builtinPii:          # fetch_max_builtin(int*, int)
	movl	(%rdi), %eax
.LBB4_1:
	cmpl	%esi, %eax
	movl	%esi, %ecx
	cmovgl	%eax, %ecx
	lock	cmpxchgl	%ecx, (%rdi)
	jne	.LBB4_1
	retq
```

* **The exclusive monitor.** On ARMv8.0 an RMW is `LDAXR` (load and set an exclusive reservation on the location's
  granule) + `STLXR` (store only if the reservation still holds; `w9 = 0` on success). The reservation is lost when
  another core writes anywhere in the granule (false sharing counts), on an exception or context switch (the kernel
  executes `CLREX`), or when the line is evicted. The store then fails **although the value still equals `expected`**:
  a *spurious failure*.
* **`cas_weak` is one attempt**: if `STLXR` fails, it returns `false` (the `csetm`/`tbz` sequence). **`cas_strong` has
  an inner loop** (`cbnz w10, .LBB1_1`): it retries until it either stores or sees a different value.
* **In a CAS loop, strong on LL/SC means two nested loops.** `max_loop_strong` retries spurious failures in the inner
  loop (`.LBB3_2`) and real ones in the outer loop (`.LBB3_1`). `max_loop_weak` has one loop. That's why weak is the
  default inside loops.
* **With LSE (`CASAL`) and on x86 (`LOCK CMPXCHG`) there are no spurious failures, and weak and strong compile to
  identical code.** The choice only matters on LL/SC machines (ARMv8.0, ARMv7, POWER, RISC-V `LR`/`SC`).
* **`fetch_max`**: libstdc++ 16 implements C++26 `atomic<int>::fetch_max` with `__atomic_fetch_max`. With LSE that is
  a single `LDSMAXAL`. On x86 it is a CAS loop that **always writes**, even when the current value is already larger.
  The hand-written loop's `cur < v` test returns without writing, keeping the line in a shared state when most calls
  change nothing.

### 1.3 16-byte atomics (Listing 7.8)

```cpp
// wide_atomic.cpp - 16-byte atomics: a library call, CMPXCHG16B, LDXP/STXP, CASP or LDP, depending on -march
#include <atomic>
#include <cstdint>

struct alignas(16) Tagged {   // pointer + version counter: the ABA-proof head of a lock-free stack (Folder 09)
    void* ptr;
    std::uint64_t tag;
};

Tagged load16(const std::atomic<Tagged>& a) { return a.load(std::memory_order_acquire); }
void store16(std::atomic<Tagged>& a, Tagged v) { a.store(v, std::memory_order_release); }
bool cas16(std::atomic<Tagged>& a, Tagged& expected, Tagged desired) {
    return a.compare_exchange_weak(expected, desired, std::memory_order_acq_rel, std::memory_order_acquire);
}
```

Loads and stores on x86-64 (Clang baseline, Clang `-mcx16`, Clang `x86-64-v3`, GCC `-mcx16`):

```text
load16:
  x86-64 Clang baseline  pushq %rax ; movl $2, %esi ; callq __atomic_load_16@PLT ; popq %rcx
  Clang -mcx16           pushq %rbx ; xorl %eax, %eax ; xorl %edx, %edx ; xorl %ecx, %ecx ; xorl %ebx, %ebx ; lock cmpxchg16b (%rdi) ; popq %rbx
  Clang x86-64-v3        vmovdqa (%rdi), %xmm0 ; vmovq %xmm0, %rax ; vpextrq $1, %xmm0, %rdx
  GCC -mcx16             subq $8, %rsp ; movl $2, %esi ; call __atomic_load_16 ; addq $8, %rsp

store16:
  x86-64 Clang baseline  pushq %rax ; movl $3, %ecx ; callq __atomic_store_16@PLT ; popq %rax
  Clang -mcx16           pushq %rbx ; movq %rdx, %rcx ; movq %rsi, %rbx ; movq (%rdi), %rax ; movq 8(%rdi), %rdx ; lock cmpxchg16b (%rdi) ; jne .LBB1_1 ; popq %rbx
  Clang x86-64-v3        vmovq %rdx, %xmm0 ; vmovq %rsi, %xmm1 ; vpunpcklqdq %xmm0, %xmm1, %xmm0 ; vmovdqa %xmm0, (%rdi)
  GCC -mcx16             movl $3, %ecx ; jmp __atomic_store_16
```

Loads and stores on AArch64 (v8.0, Neoverse N1 with LSE, Neoverse V1 with LSE2):

```text
load16:
  AArch64 v8.0   mov x8, x0 ; ldaxp x0, x1, [x8] ; stxp w9, x0, x1, [x8] ; cbnz w9, .LBB0_1
  N1, v8.2 LSE   mov x2, xzr ; mov x3, xzr ; caspa x2, x3, x2, x3, [x0] ; mov x0, x2 ; mov x1, x3
  V1, v8.4 LSE2  ldp x0, x1, [x0] ; dmb ishld

store16:
  AArch64 v8.0   ldxp xzr, x8, [x0] ; stlxp w8, x1, x2, [x0] ; cbnz w8, .LBB1_1
  N1, v8.2 LSE   ldp x4, x5, [x0] ; mov x3, x2 ; mov x2, x1 ; mov x6, x4 ; mov x7, x5 ; caspl x6, x7, x2, x3, [x0] ; cmp x7, x5 ; ccmp x6, x4, #0, eq ; mov x4, x6 ; mov x5, x7 ; b.ne .LBB1_1
  V1, v8.4 LSE2  dmb ish ; stp x1, x2, [x0]
```

The CAS, Clang `-mcx16` and Neoverse N1:

```asm
_Z6load16RKNSt3__16atomicI6TaggedEE: # load16(std::__1::atomic<Tagged> const&)
	pushq	%rbx
	xorl	%eax, %eax
	xorl	%edx, %edx
	xorl	%ecx, %ecx
	xorl	%ebx, %ebx
	lock	cmpxchg16b	(%rdi)
	popq	%rbx
	retq

_Z7store16RNSt3__16atomicI6TaggedEES1_: # store16(std::__1::atomic<Tagged>&, Tagged)
	pushq	%rbx
	movq	%rdx, %rcx
	movq	%rsi, %rbx
	movq	(%rdi), %rax
	movq	8(%rdi), %rdx
.LBB1_1:
	lock	cmpxchg16b	(%rdi)
	jne	.LBB1_1
	popq	%rbx
	retq

_Z5cas16RNSt3__16atomicI6TaggedEERS1_S1_: # cas16(std::__1::atomic<Tagged>&, Tagged&, Tagged)
	pushq	%rbx
	movq	%rdx, %rbx
	movq	(%rsi), %rax
	movq	8(%rsi), %rdx
	lock	cmpxchg16b	(%rdi)
	sete	%cl
	je	.LBB2_2
	movq	%rax, (%rsi)
	movq	%rdx, 8(%rsi)
.LBB2_2:
	movl	%ecx, %eax
	popq	%rbx
	retq
```

```asm
_Z6load16RKNSt3__16atomicI6TaggedEE: // load16(std::__1::atomic<Tagged> const&)
	mov	x2, xzr
	mov	x3, xzr
	caspa	x2, x3, x2, x3, [x0]
	mov	x0, x2
	mov	x1, x3
	ret

_Z7store16RNSt3__16atomicI6TaggedEES1_: // store16(std::__1::atomic<Tagged>&, Tagged)
	ldp	x4, x5, [x0]
	mov	x3, x2
	mov	x2, x1
.LBB1_1:
	mov	x6, x4
	mov	x7, x5
	caspl	x6, x7, x2, x3, [x0]
	cmp	x7, x5
	ccmp	x6, x4, #0, eq
	mov	x4, x6
	mov	x5, x7
	b.ne	.LBB1_1
	ret

_Z5cas16RNSt3__16atomicI6TaggedEERS1_S1_: // cas16(std::__1::atomic<Tagged>&, Tagged&, Tagged)
	ldp	x6, x7, [x1]
	mov	x4, x6
	mov	x5, x7
	caspal	x4, x5, x2, x3, [x0]
	cmp	x4, x6
	ccmp	x5, x7, #0, eq
	cset	w0, eq
	b.eq	.LBB2_2
	stp	x4, x5, [x1]
.LBB2_2:
	ret
```

* **Baseline x86-64** cannot assume `CMPXCHG16B` (some early AMD64 CPUs lacked it), so every operation is a call into
  libatomic/compiler-rt.
* **Clang `-mcx16`** inlines `LOCK CMPXCHG16B` for *everything*, including the **load**: a load implemented as a CAS
  writes the line. That faults on read-only memory, and every reader takes the line exclusive, so readers contend like
  writers.
* **Clang `x86-64-v3`** loads and stores with `VMOVDQA`. Intel and AMD document that aligned 16-byte SSE/AVX accesses
  are atomic on processors that support AVX, and Clang relies on that. The CAS stays `CMPXCHG16B`.
* **GCC never inlines 16-byte atomics** (`is_always_lock_free` is false even with `-mcx16`). It calls libatomic, which
  chooses the sequence at run time, because GCC refuses to compile a load into a store. GCC and Clang therefore
  **disagree on `atomic<16-byte>::is_always_lock_free`**. Code that picks a data-structure layout from that constant
  differs between compilers.
* **AArch64 v8.0**: the only single-copy-atomic 128-bit read is `LDAXP` + `STXP` writing the value back, in a loop. A
  load is a write here too. **LSE** gives `CASPA`/`CASPL`/`CASPAL`; the load is a `CASPA` with a dummy value, still a
  write. **LSE2 (ARMv8.4)** makes aligned `LDP`/`STP` single-copy atomic: the load is `LDP` + `DMB ISHLD`, the store
  `DMB ISH` + `STP`.

### 1.4 Contention: `fetch_add` vs a CAS loop (Listing 7.10)

```cpp
// cas_contention.cpp - one contended counter: fetch_add (always succeeds) vs a CAS loop (retries under contention)
#include <atomic>
#include <chrono>
#include <cstdint>
#include <print>
#include <thread>
#include <vector>

constexpr std::int64_t kOpsPerThread = 1'000'000;

struct Result {
    double ns_per_op;      // wall time / total operations
    double fails_per_op;   // failed CAS attempts per successful increment
};

template <bool UseCas>
Result run(int threads) {
    alignas(64) std::atomic<std::int64_t> counter{0};
    std::atomic<std::int64_t> fails{0};
    // Spin-start, not std::latch: libc++ 21 on Windows implements atomic::wait (and so latch) by polling with
    // sleeps, so a latch-released main thread can take t0 milliseconds after the workers have finished.
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    std::vector<std::jthread> ts;
    for (int t = 0; t < threads; ++t)
        ts.emplace_back([&] {
            std::int64_t my_fails = 0;
            ready.fetch_add(1);
            while (!go.load(std::memory_order_acquire)) {
            }
            for (std::int64_t i = 0; i < kOpsPerThread; ++i) {
                if constexpr (UseCas) {
                    std::int64_t cur = counter.load(std::memory_order_relaxed);
                    while (!counter.compare_exchange_weak(cur, cur + 1, std::memory_order_relaxed)) ++my_fails;
                } else {
                    counter.fetch_add(1, std::memory_order_relaxed);
                }
            }
            fails.fetch_add(my_fails, std::memory_order_relaxed);
        });
    while (ready.load() != threads) {
    }
    const auto t0 = std::chrono::steady_clock::now();
    go.store(true, std::memory_order_release);
    ts.clear();
    const std::chrono::duration<double, std::nano> d = std::chrono::steady_clock::now() - t0;
    const double ops = static_cast<double>(threads * kOpsPerThread);
    if (counter.load() != threads * kOpsPerThread) std::println("LOST UPDATES");
    return {d.count() / ops, static_cast<double>(fails.load()) / ops};
}

int main() {
    std::println("threads   fetch_add ns/op   CAS-loop ns/op   CAS failures per increment");
    for (int threads : {1, 2, 4}) {
        const Result f = run<false>(threads);
        const Result c = run<true>(threads);
        std::println("{:>7}   {:>15.1f}   {:>14.1f}   {:>26.2f}", threads, f.ns_per_op, c.ns_per_op, c.fails_per_op);
    }
}
```

Output (verified, GCC then Clang):

```text
threads   fetch_add ns/op   CAS-loop ns/op   CAS failures per increment
      1               4.8              8.7                         0.00
      2              10.1             33.4                         0.45
      4              10.9             37.0                         1.05
threads   fetch_add ns/op   CAS-loop ns/op   CAS failures per increment
      1               5.0              8.7                         0.00
      2              10.5             34.5                         0.43
      4              10.2             38.5                         0.63
```

Over repeated runs on this 6-core part: `fetch_add` 4.8–5.1 ns alone and 10–11 ns with 2–4 threads; the CAS loop
8.3–8.7 ns alone, 20–35 ns with 2 threads and 35–39 ns with 4, with 0.43–0.48 failures per increment at 2 threads
and 0.6–1.2 at 4. A `LOCK XADD` always succeeds once it owns the line. A CAS loop reads the value, loses the line to
another core, fails, and goes round again. **Use the dedicated RMW (`fetch_add`, `fetch_or`, `exchange`, C++26
`fetch_max`) when one exists.** A CAS loop is for transitions no instruction implements.

(The listing starts threads with a spin flag, not `std::latch`. On this Windows toolchain libc++ 21 implements
`atomic::wait` by polling with sleeps, so a latch-released timer can start late; Folder 08 covers it.)

### 1.5 `atomic_ref`: atomic operations on plain memory (Listing 7.11)

```cpp
// atomic_ref_ring.cpp - std::atomic_ref over plain memory: an SPSC ring in a "shared memory" region of raw bytes
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <new>
#include <print>
#include <thread>

// The layout another process (or a device) agrees on: plain integers, no std::atomic in the struct,
// because the region is mapped memory owned by the OS/driver, not by this C++ program's objects.
struct RingHeader {
    alignas(64) std::uint64_t head;   // written by the consumer only
    alignas(64) std::uint64_t tail;   // written by the producer only
};
constexpr std::size_t kSlots = 1024;  // power of two
struct Region {
    RingHeader hdr;
    alignas(64) std::uint64_t slot[kSlots];
};

// Every CONCURRENT access to head/tail goes through atomic_ref; the slots are plain, ordered by them.
static_assert(std::atomic_ref<std::uint64_t>::is_always_lock_free);   // required for shared memory/IPC
static_assert(std::atomic_ref<std::uint64_t>::required_alignment <= alignof(std::uint64_t));

using Ref = std::atomic_ref<std::uint64_t>;

bool try_push(Region& r, std::uint64_t v, std::uint64_t& tail_cache) {
    const std::uint64_t t = tail_cache;                                   // only we write tail
    if (t - Ref(r.hdr.head).load(std::memory_order_acquire) == kSlots) return false;   // full
    r.slot[t % kSlots] = v;                                               // plain store into the slot...
    Ref(r.hdr.tail).store(t + 1, std::memory_order_release);              // ...published by the release
    tail_cache = t + 1;
    return true;
}
bool try_pop(Region& r, std::uint64_t& v, std::uint64_t& head_cache) {
    const std::uint64_t h = head_cache;
    if (Ref(r.hdr.tail).load(std::memory_order_acquire) == h) return false;            // empty
    v = r.slot[h % kSlots];
    Ref(r.hdr.head).store(h + 1, std::memory_order_release);              // the slot may be reused now
    head_cache = h + 1;
    return true;
}

int main() {
    // Stand-in for mmap/shm_open: raw storage whose objects begin life when we create them.
    auto raw = std::make_unique<std::byte[]>(sizeof(Region) + 64);
    void* p = raw.get();
    std::size_t space = sizeof(Region) + 64;
    Region& r = *new (std::align(alignof(Region), sizeof(Region), p, space)) Region{};

    constexpr std::uint64_t n = 2'000'000;
    std::uint64_t sum = 0;
    std::jthread consumer([&] {
        std::uint64_t head = 0, v = 0;
        for (std::uint64_t got = 0; got < n;)
            if (try_pop(r, v, head)) {
                sum += v;
                ++got;
            }
    });
    std::uint64_t tail = 0;
    for (std::uint64_t i = 1; i <= n;)
        if (try_push(r, i, tail)) ++i;
    consumer.join();
    std::println("transferred {} values through a {}-slot ring, sum {} (expected {})", n, kSlots, sum,
                 n * (n + 1) / 2);
    std::println("head {} tail {}", Ref(r.hdr.head).load(), Ref(r.hdr.tail).load());
}
```

Output (verified, GCC then Clang):

```text
transferred 2000000 values through a 1024-slot ring, sum 2000001000000 (expected 2000001000000)
head 2000000 tail 2000000
transferred 2000000 values through a 1024-slot ring, sum 2000001000000 (expected 2000001000000)
head 2000000 tail 2000000
```

* **The use case**: memory whose type you don't control. Examples are a shared-memory segment laid out for another
  process, a DMA descriptor ring, a column of plain integers that is atomic only during a parallel phase, or a C
  struct from a stable ABI. `std::atomic<uint64_t>` would change the layout or require the object to be created as an
  atomic. `atomic_ref` applies atomic operations to an existing `uint64_t`.
* **The rules ([atomics.ref.generic])**: the object must satisfy `required_alignment`. While any `atomic_ref` to it
  exists, **all** accesses that may be concurrent must go through an `atomic_ref`; a plain access concurrent with one is
  a data race. The slots in the ring are plain because each is ordered by the release/acquire on the indices.
* **Across processes, require lock-freedom** (`static_assert(... is_always_lock_free)`). Only lock-free operations
  are expected to be address-free ([atomics.lockfree]); a lock-based fallback keeps its locks inside *this* process,
  so two processes don't exclude each other.
* The ring is the cached-index SPSC design of Folder 09 in miniature: each side caches its own index and reads the
  other's with acquire.
* C++26 adds `atomic_ref::address()` (P2835) and `atomic_ref<const T>` / cv-qualified support (P3323). libstdc++ 16
  reports `__cpp_lib_atomic_ref` = 202603, libc++ 21 reports 201806.

### 1.6 `atomic<shared_ptr>` (Listings 7.12 and 7.13)

```cpp
// atomic_sp.cpp - std::atomic<std::shared_ptr<T>>: a config hot-swap, and what a load costs
#include <atomic>
#include <chrono>
#include <cstdint>
#include <memory>
#include <mutex>
#include <print>
#include <thread>
#include <vector>

struct Config {
    std::int64_t version;
    std::int64_t twice;   // invariant: twice == 2 * version (a reader must never see a half-built Config)
};

std::atomic<std::shared_ptr<const Config>> current;

template <class F>
double ns_per_op(int n, F f) {
    const auto t0 = std::chrono::steady_clock::now();
    for (int i = 0; i < n; ++i) f();
    const std::chrono::duration<double, std::nano> d = std::chrono::steady_clock::now() - t0;
    return d.count() / n;
}

int main() {
    current.store(std::make_shared<const Config>(Config{0, 0}));

    // 1. Readers take a snapshot (the shared_ptr keeps it alive while they use it); one writer swaps it.
    constexpr std::int64_t kVersions = 20'000;
    std::atomic<std::int64_t> broken{0}, backwards{0};
    std::vector<std::jthread> readers;
    for (int r = 0; r < 3; ++r)
        readers.emplace_back([&] {
            std::int64_t last = 0;
            for (;;) {
                const std::shared_ptr<const Config> c = current.load(std::memory_order_acquire);
                if (c->twice != 2 * c->version) broken.fetch_add(1);
                if (c->version < last) backwards.fetch_add(1);
                last = c->version;
                if (last == kVersions) break;
            }
        });
    for (std::int64_t v = 1; v <= kVersions; ++v)
        current.store(std::make_shared<const Config>(Config{v, 2 * v}), std::memory_order_release);
    readers.clear();
    std::println("hot swap: {} versions, 3 readers: invariant broken {} times, version went backwards {} times",
                 kVersions, broken.load(), backwards.load());
    std::println("is_lock_free: {}", current.is_lock_free() ? "yes" : "no");

    // 2. Uncontended cost of a read, single thread.
    constexpr int n = 2'000'000;
    std::int64_t sink = 0;
    std::shared_ptr<const Config> plain = current.load();
    std::mutex m;
    const double t_plain = ns_per_op(n, [&] { sink += std::shared_ptr<const Config>(plain)->version; });
    const double t_mutex = ns_per_op(n, [&] {
        std::shared_ptr<const Config> c;
        {
            std::scoped_lock lk(m);
            c = plain;
        }
        sink += c->version;
    });
    const double t_atomic = ns_per_op(n, [&] { sink += current.load(std::memory_order_acquire)->version; });
    std::println("copy a shared_ptr (refcount inc + dec)       {:5.1f} ns", t_plain);
    std::println("copy under std::mutex                        {:5.1f} ns", t_mutex);
    std::println("atomic<shared_ptr>::load (lock bit + inc/dec) {:5.1f} ns", t_atomic);
    std::println("(checksum {})", sink & 0xFF);
}
```

Output (verified, GCC/libstdc++; libc++ 21 has no `atomic<shared_ptr>`):

```text
hot swap: 20000 versions, 3 readers: invariant broken 0 times, version went backwards 0 times
is_lock_free: no
copy a shared_ptr (refcount inc + dec)        13.4 ns
copy under std::mutex                         24.7 ns
atomic<shared_ptr>::load (lock bit + inc/dec)  17.3 ns
(checksum 0)
```

How libstdc++ 16 does it (excerpt, regenerated from the installed header):

```text
// bits/shared_ptr_atomic.h (libstdc++ 16.2), lines 399-401,439-480,550-555
  399        // An atomic version of __shared_count<> and __weak_count<>.
  400        // Stores a _Sp_counted_base<>* but uses the LSB as a lock.
  401        struct _Atomic_count
    ...
  439          // Precondition: Caller does not hold lock!
  440          // Returns the raw pointer value without the lock bit set.
  441          pointer
  442          lock(memory_order __o) const noexcept
  443          {
  444            // To acquire the lock we flip the LSB from 0 to 1.
  445  
  446            _AtomicRef __aref(&_M_val);
  447            auto __current = __aref.load(memory_order_relaxed);
  448            while (__current & _S_lock_bit)
  449              {
  450  #if __glibcxx_atomic_wait
  451                __detail::__thread_relax();
  452  #endif
  453                __current = __aref.load(memory_order_relaxed);
  454              }
  455  
  456            _GLIBCXX_TSAN_MUTEX_TRY_LOCK(&_M_val);
  457  
  458            while (!__aref.compare_exchange_strong(__current,
  459                                                   __current | _S_lock_bit,
  460                                                   __o,
  461                                                   memory_order_relaxed))
  462              {
  463                _GLIBCXX_TSAN_MUTEX_TRY_LOCK_FAILED(&_M_val);
  464  #if __glibcxx_atomic_wait
  465                __detail::__thread_relax();
  466  #endif
  467                __current = __current & ~_S_lock_bit;
  468                _GLIBCXX_TSAN_MUTEX_TRY_LOCK(&_M_val);
  469              }
  470            _GLIBCXX_TSAN_MUTEX_LOCKED(&_M_val);
  471            return reinterpret_cast<pointer>(__current);
  472          }
  473  
  474          // Precondition: caller holds lock!
  475          void
  476          unlock(memory_order __o) const noexcept
  477          {
  478            _GLIBCXX_TSAN_MUTEX_PRE_UNLOCK(&_M_val);
  479            _AtomicRef(&_M_val).fetch_sub(1, __o);
  480            _GLIBCXX_TSAN_MUTEX_POST_UNLOCK(&_M_val);
    ...
  550  
  551        private:
  552          using _AtomicRef = __atomic_ref<uintptr_t>;
  553          alignas(_AtomicRef::required_alignment) mutable uintptr_t _M_val{0};
  554          static constexpr uintptr_t _S_lock_bit{1};
  555        };
```

* **It is a spinlock in the pointer's low bit.** `atomic<shared_ptr<T>>` is 16 bytes: the element pointer and the
  control-block pointer, whose least significant bit is a lock (control blocks are at least 2-aligned). `load`
  spins until the bit is clear, sets it with a CAS (acquire), copies both pointers, increments the strong count, and
  unlocks with `fetch_sub(1)`. It waits with `__thread_relax`. `is_lock_free()` is `false`: a reader preempted while
  holding the bit stalls every other reader.
* **Cost**, measured single-threaded over repeated runs: plain `shared_ptr` copy 12.6–13.4 ns, copy under
  `std::mutex` 23.0–24.7 ns, `atomic<shared_ptr>::load` about 17 ns. It is cheaper than a mutex and correct: 20,000
  swaps against 3 readers produced 0 torn configs and 0 backward versions.
* **Lock-free designs** (Anthony Williams' and folly's `atomic_shared_ptr`) use **split reference counts**. A small
  "local" count lives next to the pointer (in spare pointer bits or a 16-byte word updated with DWCAS). A reader
  increments it with one CAS, then increments the real count and gives the local count back; a writer that swaps the
  pointer transfers the outstanding local count to the old control block. The cost is DWCAS or pointer-bit packing,
  and much more code.

```cpp
// sp_free_functions.cpp - the C++11 shared_ptr atomic free functions: deprecated in C++20, removed in C++26 (P2869)
#include <memory>

std::shared_ptr<int> g_config;   // a plain shared_ptr: nothing in its type says "only access me atomically"

std::shared_ptr<int> get() { return std::atomic_load(&g_config); }
void set(std::shared_ptr<int> p) { std::atomic_store(&g_config, std::move(p)); }
int unsafe() { return *g_config; }   // compiles fine: one forgotten atomic_load is a data race

int main() {
    set(std::make_shared<int>(1));
    return get() && unsafe() == 1 ? 0 : 1;
}
```

With `-std=c++20` (GCC, then Clang):

```text
sp_free_functions.cpp:6:53: error: 'std::shared_ptr<_Tp> std::atomic_load(const shared_ptr<_Tp>*) [with _Tp = int]' is deprecated: use 'std::atomic<std::shared_ptr<T>>' instead [-Werror=deprecated-declarations]
sp_free_functions.cpp:7:53: error: 'void std::atomic_store(shared_ptr<_Tp>*, shared_ptr<_Tp>) [with _Tp = int]' is deprecated: use 'std::atomic<std::shared_ptr<T>>' instead [-Werror=deprecated-declarations]
sp_free_functions.cpp: compiled with NO diagnostic (clang)
```

The C++11 free functions were deprecated because **the type doesn't say "atomic"**. `unsafe()` compiles, and one
forgotten `atomic_load` is a data race. P2869 removes them in C++26. GCC 16 still provides them in C++26 mode (with the
deprecation warning), and libc++ 21 provides them silently.

---

## 2. Evolution table

| Feature | C++11 | C++14 | C++17 | C++20 | C++23 | C++26 |
|---|---|---|---|---|---|---|
| CAS | `compare_exchange_weak`/`strong` | — | — | padding bits ignored (P0528) | — | — |
| lock-freedom query | `is_lock_free()`, `ATOMIC_*_LOCK_FREE` | — | `is_always_lock_free` (P0152) | `atomic_signed_lock_free` / `atomic_unsigned_lock_free` aliases | — | — |
| new RMWs | `fetch_add/sub/and/or/xor`, `exchange` | — | — | floating-point `fetch_add`/`sub` (P0020) | — | `fetch_max`/`fetch_min` (P0493) |
| `atomic_ref` | — | — | — | `atomic_ref` (P0019) | — | `address()` (P2835), cv-qualified `atomic_ref` (P3323) |
| shared_ptr | free `atomic_load(&sp)` etc. | — | — | `atomic<shared_ptr>`, `atomic<weak_ptr>` (P0718); free functions deprecated | — | free functions removed (P2869) |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| claim a task exactly once | `if (s.compare_exchange_weak(Ready, Taken)) run(); else skip();` (spurious failure on LL/SC: nobody runs it) | single-shot decisions use `compare_exchange_strong`; loops use weak |
| CAS loop with an expensive "desired" (allocation, big copy) | recompute it on every iteration with weak | build it once outside the loop; or strong, so LL/SC spurious failures don't redo the work |
| atomic over a struct | struct with padding (libc++ 21 CAS fails on padding, Listing 7.9) | no padding: explicit fields, `static_assert(std::has_unique_object_representations_v<T>)` |
| atomics in shared memory / IPC | a type that is not always lock-free (possibly a per-process lock) | `static_assert(std::atomic_ref<T>::is_always_lock_free)`; explicit `alignas(required_alignment)` in the layout |
| 16-byte "pointer + tag" head | `atomic<Tagged>::load()` on every read (a write on v8.0, `-mcx16`, LSE) | read it non-atomically or by halves and let the CAS validate (outside the strict C++ model, as production libraries do); or pack the tag into 64 bits (Folder 09); or target LSE2 / AVX |
| config hot swap | `shared_ptr` global + free `atomic_load` (Listing 7.13) | `std::atomic<std::shared_ptr<const Config>>` (libstdc++), or RCU / hazard pointers for very hot reads |
| a "maximum so far" statistic | CAS loop that always writes (or `fetch_max` on x86) | `if (cur < v)` test before the CAS: no write, no line ownership when nothing changes |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| tasks occasionally never run, only on ARM | a single-shot `compare_exchange_weak` failed spuriously | grep weak CASes not inside a loop |
| CAS spins or fails "while equal" on Clang builds only | padding bytes compared (libc++ 21, no P0528) | `has_unique_object_representations_v` assertion |
| a struct's layout differs between GCC and Clang builds | `atomic<T>` for odd-sized `T` (3, 5, 6, 7 bytes) | `static_assert(sizeof(std::atomic<T>) == N)` in shared headers |
| SIGSEGV reading an atomic in a read-only mapping | 16-byte load compiled to `CMPXCHG16B`/`LDAXP`+`STXP`/`CASPA` | check the asm; LSE2/AVX builds or a different design |
| two processes corrupt a shared counter | non-lock-free atomic in shared memory | `is_always_lock_free` assertion |
| config reads stall when the writer is preempted | libstdc++ `atomic<shared_ptr>` lock bit | acceptable for config; for hot paths use RCU/hazard pointers (Folder 09) |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "Weak or strong for a one-shot claim?"</b></summary>

**Initial prompt.** "A dispatcher marks a job taken with `if (state.compare_exchange_weak(expected = Ready, Taken))
run(job);`. Otherwise another worker has it. Correct?"

**L5 textbook answer.** "Yes. Weak is faster, and if it fails, someone else took the job."

**Why L5 deadlocks on ARM64.** On LL/SC hardware `compare_exchange_weak` can fail **while `state == Ready`**: the
exclusive monitor was cleared by an interrupt, a context switch, an eviction, or another core writing the same cache
line (Listing 7.7: one `LDAXR`/`STLXR` attempt, `false` if the store-exclusive fails). Then nobody runs the job, and
whoever waits for its result waits forever. It never reproduces on x86 or LSE builds, where weak and strong compile to
the same `CMPXCHG`/`CASAL`.

**L7 principal defense.** "Single-shot CAS whose failure *means something* is strong. Weak is for loops, where a
spurious failure just costs one more iteration. On LL/SC, strong is exactly 'weak + retry while the value still
matches' (the inner loop in Listing 7.7)."
</details>

<details><summary><b>Chain 2 ⚡ "Is strong ever faster than weak?"</b></summary>

**Initial prompt.** "If weak is the cheap one, when would you ever choose strong inside a loop?"

**L5 textbook answer.** "Never: strong is weak plus a retry loop, so it's always slower."

**Why L5 breaks.** Two cases. (1) On x86 and ARMv8.1+ LSE they are the *same instruction* (Listing 7.7, N1 and x86),
so there is nothing to gain or lose. (2) On LL/SC, when the loop body is expensive (it allocates a node, builds a new
immutable state, hashes a key), a spurious failure with weak re-executes that body, while strong's inner loop retries
only the store-exclusive. The nested loop of `max_loop_strong` is cheaper than redoing the work.

**L7 principal defense.** "Weak in tight loops whose body is a few instructions. Strong (or hoisting the expensive work
out of the loop) when re-running the body costs more than an LL/SC retry. And for ARM servers I compile with LSE
(`-march=armv8.1-a` or a Neoverse `-mcpu`, or rely on GCC's `-moutline-atomics` run-time dispatch), which removes
spurious failures entirely."
</details>

<details><summary><b>Chain 3 🔥 "std::atomic of a small struct is lock-free, right?"</b></summary>

**Initial prompt.** "We put `std::atomic<Rgb>` (3 bytes) and `std::atomic<Pair16>` (16 bytes) in a shared-memory
segment used by two processes. Any problem?"

**L5 textbook answer.** "No. Both are small, so the CPU does them atomically."

**Why L5 corrupts memory on ARM64.** Listing 7.9: with libstdc++, neither is always-lock-free; both become libatomic
calls. Whether libatomic then uses an instruction or a lock depends on the size, alignment and CPU, and is decided at
run time. When it uses a lock, the lock table lives **inside each process**: two processes take different locks, and
their updates interleave freely, on x86 and ARM64 alike. The standard only says that *lock-free* operations should be
address-free and independent of per-process state ([atomics.lockfree]). Even the layout differs: libc++ makes the
3-byte atomic 4 bytes and 4-aligned, libstdc++ keeps it 3/1, so a segment written by one build is misread by the other.

**L7 principal defense.** "Shared-memory types are fixed-width integers, padded to 4/8 bytes, with
`static_assert(std::atomic_ref<T>::is_always_lock_free)` and `alignas(std::atomic_ref<T>::required_alignment)` in the
layout definition. I access them with `atomic_ref` (Listing 7.11), so the segment's struct stays a plain C layout."
</details>

<details><summary><b>Chain 4 ⚡ "What does a 16-byte atomic load cost?"</b></summary>

**Initial prompt.** "Our lock-free stack head is `std::atomic<{Node*, uint64_t tag}>`. Readers call `head.load()`
constantly. Cost?"

**L5 textbook answer.** "One 16-byte load. Modern CPUs have 128-bit loads."

**Why L5 breaks.** Only on some targets (Listing 7.8). With Clang `-mcx16` the load is `LOCK CMPXCHG16B`, a locked
write. On ARMv8.0 it is an `LDAXP`/`STXP` loop that writes the value back, and with LSE a `CASPA`, also a write. With
GCC it is a libatomic call. Every "reader" therefore takes the cache line exclusively, and readers contend like writers.
If the head lives in read-only or copy-on-write memory, the load faults. Only AVX x86 (`VMOVDQA`) and ARMv8.4 LSE2
(`LDP` + `DMB`) give a true read.

**L7 principal defense.** "Don't load the 16-byte head atomically on the read path. Read the two halves with plain or
relaxed 8-byte loads, and let the 16-byte CAS reject a torn snapshot. That steps outside the strict C++ object model, so
it gets isolated and documented the way production libraries do it. Or avoid DWCAS: a 16-bit tag in the unused top
bits of a 48-bit pointer (Folder 09), or hazard pointers, which remove ABA without a tag."
</details>

<details><summary><b>Chain 5 🧊 "compare_exchange on a struct with padding"</b></summary>

**Initial prompt.** "`std::atomic<Item>` where `struct Item { char kind; int value; };`. A CAS with
`expected = {1, 2}` fails even though `load()` returns `{1, 2}`. Compiler bug?"

**L5 textbook answer.** "CAS compares values, so it can't fail when they're equal; it must be a race."

**Why L5 breaks.** Before C++20, `compare_exchange` compared *object representations*, including the 3 padding bytes
after `kind`, and `expected`'s padding is whatever was on the stack. C++20 (P0528) requires padding to be ignored.
libstdc++ implements that and the CAS succeeds; **libc++ 21 does not, and the CAS fails** (Listing 7.9). A CAS loop
recovers on the next iteration, because the failure copies the clean bytes into `expected`. Single-shot logic misfires.

**L7 principal defense.** "Atomic structs have no padding: reorder or add explicit fields, and
`static_assert(std::has_unique_object_representations_v<Item>)`. Better, pack small structs into an integer and use
`std::bit_cast`: then the CAS is an integer CAS and every library agrees."
</details>

<details><summary><b>Chain 6 ⚡ "Why were the shared_ptr atomic free functions deprecated?"</b></summary>

**Initial prompt.** "C++11 had `std::atomic_load(&sp)`. Why deprecate it in C++20 and remove it in C++26?"

**L5 textbook answer.** "Because `atomic<shared_ptr>` is a faster, lock-free implementation."

**Why L5 breaks.** Not faster or lock-free in practice: libstdc++'s `atomic<shared_ptr>` is a lock bit (excerpt in
§1.6), and libc++ 21 doesn't ship it at all. The real reason is type safety. With the free functions the variable is a
plain `shared_ptr`, and any plain access, like `unsafe()` in Listing 7.13, compiles and is a data race. GCC warns about
the deprecated call, libc++ says nothing, and neither diagnoses the unprotected read.

**L7 principal defense.** "`std::atomic<std::shared_ptr<const T>>` makes every access atomic by type. On libc++ (until
it ships P0718) I'd wrap a `shared_ptr` plus a mutex in a small class with only `load()`/`store()`, so the type still
enforces it."
</details>

<details><summary><b>Chain 7 🔥 "Is atomic<shared_ptr> lock-free? Make one that is"</b></summary>

**Initial prompt.** "Our read path does `config.load()` on an `atomic<shared_ptr>` millions of times per second. Is it
lock-free, and how would you make it so?"

**L5 textbook answer.** "It's std::atomic, so it's lock-free."

**Why L5 breaks.** `is_lock_free()` is `false` in libstdc++ (Listing 7.12). Every load sets a lock bit with a CAS, bumps
the count and clears the bit, so all readers serialize on one cache line, and a preempted reader stalls the rest.
Lock-freedom needs **split reference counting**: readers increment a local count packed next to the pointer (DWCAS or
spare pointer bits) in one atomic step, so they never dereference a control block that might be freed; the writer
transfers the local count when it swaps.

**L7 principal defense.** "For config it's fine: about 17 ns, cheaper than a mutex, 0 torn reads in the hot-swap test.
For millions of reads per second I'd change the read path instead: RCU or hazard pointers (C++26 `<rcu>`,
`<hazard_pointer>`, Folder 09), or a per-thread cached `shared_ptr` refreshed when a version counter changes (one relaxed
load per read)."
</details>

<details><summary><b>Chain 8 🧊 "atomic_ref on a field of a plain struct"</b></summary>

**Initial prompt.** "We use `std::atomic_ref<uint64_t>(hdr.tail)` inside a C struct from a driver header, while other
code reads `hdr.tail` directly. Is that allowed?"

**L5 textbook answer.** "Yes: atomic_ref makes any object atomic."

**Why L5 corrupts memory on ARM64.** Three conditions are broken or unchecked. (1) While an `atomic_ref` to `tail`
exists, *every* concurrent access must go through an `atomic_ref`. The direct read is a data race, and on ARM64 it is a
plain `LDR` with no acquire, so it can read `tail` and then stale slot contents. (2) `required_alignment` can exceed
`alignof(T)` (8 vs 4 for `Padded` in Listing 7.9), and a misaligned `atomic_ref` is undefined behaviour. (3) If `T` is not
always lock-free, the "atomic" operations take a process-local lock.

**L7 principal defense.** "All concurrent accesses through `atomic_ref` with explicit orders (Listing 7.11), plus
`static_assert`s on `is_always_lock_free` and `required_alignment <= alignof` for the field. C++26 `atomic_ref<const T>`
lets read-only code use it without casting away `const`."
</details>

---

## 6. Invariants checklist

- [ ] Single-shot CAS decisions use `compare_exchange_strong`; loops use weak.
- [ ] Atomic structs have no padding (`has_unique_object_representations_v`).
- [ ] Types in shared memory or crossing a library boundary: `is_always_lock_free`, `sizeof`, and alignment
      `static_assert`ed.
- [ ] No 16-byte atomic load on a hot read path unless the target has LSE2 or AVX semantics.
- [ ] Dedicated RMWs (`fetch_add`, `exchange`, `fetch_max`) instead of CAS loops where one exists.
- [ ] Every concurrent access to an `atomic_ref`'d object goes through `atomic_ref`.
- [ ] No `std::atomic_load(&shared_ptr)` in new code.

## 7. References

- [atomics.types.generic], [atomics.ref.generic]: <https://eel.is/c++draft/atomics>
- P0528R3 (padding bits in compare-exchange): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2018/p0528r3.html>
- P0019R8 (`atomic_ref`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2018/p0019r8.html>
- P0718R2 (`atomic<shared_ptr>`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2017/p0718r2.html>
- P0493R5 (`fetch_max`/`fetch_min`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2024/p0493r5.pdf>
- P2869R4 (remove deprecated `shared_ptr` atomic access APIs): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2024/p2869r4.pdf>
- Arm ARM, "Exclusive access instructions and the exclusive monitors": <https://developer.arm.com/documentation/ddi0487/latest>
- GCC bug 80878 (16-byte atomics and `CMPXCHG16B` loads): <https://gcc.gnu.org/bugzilla/show_bug.cgi?id=80878>
- folly `AtomicSharedPtr` (split reference counts): <https://github.com/facebook/folly/blob/main/folly/concurrency/AtomicSharedPtr.h>
