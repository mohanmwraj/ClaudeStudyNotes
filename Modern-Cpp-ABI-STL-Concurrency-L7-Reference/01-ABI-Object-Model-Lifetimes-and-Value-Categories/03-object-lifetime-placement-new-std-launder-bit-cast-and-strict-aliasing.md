# 03 · Object lifetime, placement new, `std::launder`, `std::bit_cast`, and strict aliasing

> **Scope.** In C++ a pointer points to an *object*, not to an address. The optimizer reasons about objects:
> their types (type-based alias analysis), their lifetimes (when storage holds a live object), and their dynamic
> types (vptr invariance). This file shows each assumption as a code-generation change, then shows the UB that
> breaks it **miscompiling on real compilers**. It finishes with the tools that keep you correct:
> `std::bit_cast`, `std::launder`, `std::construct_at`, implicit-lifetime types, `std::start_lifetime_as`,
> C++23 range-for lifetime extension, and constant evaluation as a UB detector.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 3.1 | `aliasing.cpp` | TBAA folds a reload; `unsigned char` blocks it; `vector<uint8_t>` loop pessimization; `char8_t` does not alias | asm x86-64 + AArch64, with and without `-fno-strict-aliasing` |
| 3.2 | `punning.cpp` | memcpy / `bit_cast` / union / `reinterpret_cast` compile identically; the UB form **returns a stale value** | run (GCC + Clang, ± `-fno-strict-aliasing`) + asm |
| 3.3 | `launder.cpp` | `-fstrict-vtable-pointers` makes Clang call **`Animal::speak` on a `Cat`** without `std::launder` | asm + run (Clang) |
| 3.4 | `wire_parse.cpp` | parsing bytes: memcpy is free; `start_lifetime_as`; atomic alignment on ARM64 (`ldar`/`ldapr`, `ldaxr`/`stlxr` vs `ldaddal`) | asm x86-64, AArch64 v8.0 and Neoverse N1 |
| 3.5 | `lifetime.cpp` | when temporaries die; the C++23 range-for fix (P2718) observed; `-Wdangling-reference` / `lifetimebound` | C++20 + C++23 runs; 4 expected diagnostics |
| 3.6 | `constexpr_ub.cpp` | constant evaluation rejects 4 kinds of lifetime UB | expected compile failures on both compilers |
| 3.7 | `slot.cpp` | an optional-like slot: byte buffer (UB) vs union + `construct_at`, proven by `static_assert` | compile + run, both |
| 3.8 | `features.cpp` | the feature-test macros for this folder, per compiler and library | run with `-std=c++26` |

**Verification line.** Clang 21.1.0 `-O3` codegen for `x86_64-linux-gnu` / `aarch64-linux-gnu`; native runs
with GCC 16.2 (libstdc++) and Clang 21.1 (libc++) at `-O2` with the full warning set as errors. Where a listing
needs a diagnostic disabled to run at all, the pragma is in the listing and the diagnostic is reproduced in the
text.

---

## 1. First principles

### 1.1 The lifetime state machine

```text
  storage acquired           object lifetime begins          object lifetime ends          storage released
  (operator new, stack       (initialization complete;       (destructor call STARTS, or   (operator delete,
   frame, static area,        placement new; construct_at;    storage reused by another     scope exit)
   malloc, mmap)              implicit creation, C++20)       object; trivial: reuse)
        |                            |                               |                            |
        v                            v                               v                            v
  [ raw storage ] --------> [ object of type T alive ] -----> [ raw storage again ] ------> [ gone ]
        ^                     |   pointers/refs to it are       pointers to the old object
        |                     |   VALID                         are now "pointers to storage":
        |                     |                                 only limited use (no member access,
        +---------------------+                                 no virtual calls), per [basic.life]/6-7
          new object of type U created here: old pointers do NOT point to it unless the new object
          "transparently replaces" the old one (C++20 [basic.life]/8) - otherwise std::launder
```

Three consequences carry this whole file:

1. **Types are facts the optimizer uses.** A store through `float*` cannot modify an `int` object. That is
   type-based alias analysis (TBAA). Code that violates it is not "unportable", it is *miscompiled*
   (Listing 3.2).
2. **A pointer remembers which object it points to.** After you create a *different* object in the same
   storage, the old pointer does not point to the new object. `std::launder(p)` gives you a pointer that
   does. Clang can turn this into code (Listing 3.3).
3. **Lifetime ends at the semicolon more often than you think.** Temporaries die at the end of the full
   expression unless they are bound directly to a reference. C++23 extended this for range-`for` only
   (Listing 3.5).

### 1.2 Strict aliasing as the optimizer sees it (Listing 3.1)

[basic.lval]/11 lets you access an object only through a glvalue of (roughly) its own type, its
signed/unsigned variant, or `char`, `unsigned char` or `std::byte`. The exemption for the three byte types
is what makes `memcpy` and serialization possible. It also forces the optimizer to assume that **every byte
store may modify anything**.

```cpp
// aliasing.cpp - strict aliasing as the optimizer sees it: TBAA folds, char-type pessimization, char8_t
#include <cstddef>
#include <cstdint>
#include <vector>

// int and float cannot alias: the store through f cannot change *i, so the result folds to the constant 1.
int store_int_float(int* i, float* f) {
    *i = 1;
    *f = 2.0f;
    return *i;
}
// unsigned char may alias anything: *i must be reloaded after the store through c.
int store_int_char(int* i, unsigned char* c) {
    *i = 1;
    *c = 2;
    return *i;
}
// The classic pessimization: v[i] is a uint8_t (= unsigned char) store, which might modify the vector's own
// begin/end pointers, so they are reloaded on every iteration and the loop is not vectorized.
void bump_u8(std::vector<std::uint8_t>& v) {
    for (std::size_t i = 0; i < v.size(); ++i) v[i] += 1;
}
// char8_t (C++20) is a distinct type WITHOUT the aliasing exemption: the bounds stay in registers.
void bump_c8(std::vector<char8_t>& v) {
    for (std::size_t i = 0; i < v.size(); ++i) v[i] += 1;
}
// The portable fix for uint8_t: hoist the bounds into locals yourself.
void bump_u8_hoisted(std::vector<std::uint8_t>& v) {
    std::uint8_t* p = v.data();
    const std::size_t n = v.size();
    for (std::size_t i = 0; i < n; ++i) p[i] += 1;
}
```

Clang `-O3`, x86-64:

```asm
_Z15store_int_floatPiPf:           # store_int_float(int*, float*)
	movl	$1, (%rdi)
	movl	$1073741824, (%rsi)
	movl	$1, %eax
	retq

_Z14store_int_charPiPh:            # store_int_char(int*, unsigned char*)
	movl	$1, (%rdi)
	movb	$2, (%rsi)
	movl	(%rdi), %eax
	retq

_Z7bump_u8RNSt3__16vectorIhNS_9allocatorIhEEEE: # bump_u8(std::__1::vector<unsigned char, std::__1::allocator<unsigned char> >&)
	movq	(%rdi), %rax
	cmpq	%rax, 8(%rdi)
	je	.LBB2_3
	xorl	%ecx, %ecx
.LBB2_2:
	addb	$1, (%rax,%rcx)
	addq	$1, %rcx
	movq	(%rdi), %rax
	movq	8(%rdi), %rdx
	subq	%rax, %rdx
	cmpq	%rdx, %rcx
	jb	.LBB2_2
.LBB2_3:
	retq

_Z7bump_c8RNSt3__16vectorIDuNS_9allocatorIDuEEEE: # bump_c8(std::__1::vector<char8_t, std::__1::allocator<char8_t> >&)
	movq	(%rdi), %rax
	movq	8(%rdi), %rcx
	subq	%rax, %rcx
	je	.LBB3_13
	cmpq	$3, %rcx
	ja	.LBB3_4
	xorl	%edx, %edx
	jmp	.LBB3_3
.LBB3_4:
	cmpq	$32, %rcx
	jae	.LBB3_6
	xorl	%edx, %edx
	jmp	.LBB3_10
.LBB3_6:
	movq	%rcx, %rdx
	andq	$-32, %rdx
	xorl	%esi, %esi
	pcmpeqd	%xmm0, %xmm0
.LBB3_7:
	movdqu	(%rax,%rsi), %xmm1
	movdqu	16(%rax,%rsi), %xmm2
	psubb	%xmm0, %xmm1
	psubb	%xmm0, %xmm2
	movdqu	%xmm1, (%rax,%rsi)
	movdqu	%xmm2, 16(%rax,%rsi)
	addq	$32, %rsi
	cmpq	%rsi, %rdx
	jne	.LBB3_7
	cmpq	%rdx, %rcx
	je	.LBB3_13
	testb	$28, %cl
	je	.LBB3_3
.LBB3_10:
	movq	%rdx, %rsi
	movq	%rcx, %rdx
	andq	$-4, %rdx
	pcmpeqd	%xmm0, %xmm0
.LBB3_11:
	movd	(%rax,%rsi), %xmm1
	psubb	%xmm0, %xmm1
	movd	%xmm1, (%rax,%rsi)
	addq	$4, %rsi
	cmpq	%rsi, %rdx
	jne	.LBB3_11
	jmp	.LBB3_12
.LBB3_3:
	addb	$1, (%rax,%rdx)
	addq	$1, %rdx
.LBB3_12:
	cmpq	%rdx, %rcx
	jne	.LBB3_3
.LBB3_13:
	retq

_Z15bump_u8_hoistedRNSt3__16vectorIhNS_9allocatorIhEEEE: # bump_u8_hoisted(std::__1::vector<unsigned char, std::__1::allocator<unsigned char> >&)
	movq	(%rdi), %rax
	movq	8(%rdi), %rcx
	subq	%rax, %rcx
	je	.LBB4_13
	cmpq	$3, %rcx
	ja	.LBB4_4
	xorl	%edx, %edx
	jmp	.LBB4_3
.LBB4_4:
	cmpq	$32, %rcx
	jae	.LBB4_6
	xorl	%edx, %edx
	jmp	.LBB4_10
.LBB4_6:
	movq	%rcx, %rdx
	andq	$-32, %rdx
	xorl	%esi, %esi
	pcmpeqd	%xmm0, %xmm0
.LBB4_7:
	movdqu	(%rax,%rsi), %xmm1
	movdqu	16(%rax,%rsi), %xmm2
	psubb	%xmm0, %xmm1
	psubb	%xmm0, %xmm2
	movdqu	%xmm1, (%rax,%rsi)
	movdqu	%xmm2, 16(%rax,%rsi)
	addq	$32, %rsi
	cmpq	%rsi, %rdx
	jne	.LBB4_7
	cmpq	%rdx, %rcx
	je	.LBB4_13
	testb	$28, %cl
	je	.LBB4_3
.LBB4_10:
	movq	%rdx, %rsi
	movq	%rcx, %rdx
	andq	$-4, %rdx
	pcmpeqd	%xmm0, %xmm0
.LBB4_11:
	movd	(%rax,%rsi), %xmm1
	psubb	%xmm0, %xmm1
	movd	%xmm1, (%rax,%rsi)
	addq	$4, %rsi
	cmpq	%rsi, %rdx
	jne	.LBB4_11
	jmp	.LBB4_12
.LBB4_3:
	addb	$1, (%rax,%rdx)
	addq	$1, %rdx
.LBB4_12:
	cmpq	%rdx, %rcx
	jne	.LBB4_3
.LBB4_13:
	retq
```

<details><summary>Clang -O3, AArch64 (same conclusions)</summary>

```asm
_Z15store_int_floatPiPf:           // store_int_float(int*, float*)
	mov	w8, #1
	mov	w9, #1073741824
	str	w8, [x0]
	mov	w0, #1
	str	w9, [x1]
	ret

_Z14store_int_charPiPh:            // store_int_char(int*, unsigned char*)
	mov	w8, #1
	mov	w9, #2
	str	w8, [x0]
	strb	w9, [x1]
	ldr	w0, [x0]
	ret

_Z7bump_u8RNSt3__16vectorIhNS_9allocatorIhEEEE: // bump_u8(std::__1::vector<unsigned char, std::__1::allocator<unsigned char> >&)
	ldp	x8, x9, [x0]
	cmp	x9, x8
	b.eq	.LBB2_3
	mov	x9, xzr
.LBB2_2:
	ldrb	w10, [x8, x9]
	add	w10, w10, #1
	strb	w10, [x8, x9]
	add	x9, x9, #1
	ldp	x8, x10, [x0]
	sub	x10, x10, x8
	cmp	x9, x10
	b.lo	.LBB2_2
.LBB2_3:
	ret

_Z7bump_c8RNSt3__16vectorIDuNS_9allocatorIDuEEEE: // bump_c8(std::__1::vector<char8_t, std::__1::allocator<char8_t> >&)
	ldp	x9, x8, [x0]
	subs	x10, x8, x9
	b.eq	.LBB3_14
	cmp	x10, #7
	b.hi	.LBB3_3
	mov	x11, xzr
	b	.LBB3_12
.LBB3_3:
	cmp	x10, #32
	b.hs	.LBB3_5
	mov	x11, xzr
	b	.LBB3_9
.LBB3_5:
	movi	v0.16b, #1
	and	x11, x10, #0xffffffffffffffe0
	add	x12, x9, #16
	mov	x13, x11
.LBB3_6:
	ldp	q1, q2, [x12, #-16]
	subs	x13, x13, #32
	add	v1.16b, v1.16b, v0.16b
	add	v2.16b, v2.16b, v0.16b
	stp	q1, q2, [x12, #-16]
	add	x12, x12, #32
	b.ne	.LBB3_6
	cmp	x10, x11
	b.eq	.LBB3_14
	tst	x10, #0x18
	b.eq	.LBB3_12
.LBB3_9:
	movi	v0.8b, #1
	mov	x13, x11
	and	x11, x10, #0xfffffffffffffff8
	sub	x12, x13, x11
	add	x13, x9, x13
.LBB3_10:
	ldr	d1, [x13]
	adds	x12, x12, #8
	add	v1.8b, v1.8b, v0.8b
	str	d1, [x13], #8
	b.ne	.LBB3_10
	cmp	x10, x11
	b.eq	.LBB3_14
.LBB3_12:
	add	x9, x11, x9
	sub	x8, x9, x8
.LBB3_13:
	ldrb	w10, [x9]
	adds	x8, x8, #1
	add	w10, w10, #1
	strb	w10, [x9], #1
	b.lo	.LBB3_13
.LBB3_14:
	ret

_Z15bump_u8_hoistedRNSt3__16vectorIhNS_9allocatorIhEEEE: // bump_u8_hoisted(std::__1::vector<unsigned char, std::__1::allocator<unsigned char> >&)
	ldp	x8, x9, [x0]
	subs	x10, x9, x8
	b.eq	.LBB4_14
	cmp	x10, #7
	b.hi	.LBB4_3
	mov	x11, xzr
	b	.LBB4_12
.LBB4_3:
	cmp	x10, #32
	b.hs	.LBB4_5
	mov	x11, xzr
	b	.LBB4_9
.LBB4_5:
	movi	v0.16b, #1
	and	x11, x10, #0xffffffffffffffe0
	add	x12, x8, #16
	mov	x13, x11
.LBB4_6:
	ldp	q1, q2, [x12, #-16]
	subs	x13, x13, #32
	add	v1.16b, v1.16b, v0.16b
	add	v2.16b, v2.16b, v0.16b
	stp	q1, q2, [x12, #-16]
	add	x12, x12, #32
	b.ne	.LBB4_6
	cmp	x10, x11
	b.eq	.LBB4_14
	tst	x10, #0x18
	b.eq	.LBB4_12
.LBB4_9:
	movi	v0.8b, #1
	mov	x13, x11
	and	x11, x10, #0xfffffffffffffff8
	sub	x12, x13, x11
	add	x13, x8, x13
.LBB4_10:
	ldr	d1, [x13]
	adds	x12, x12, #8
	add	v1.8b, v1.8b, v0.8b
	str	d1, [x13], #8
	b.ne	.LBB4_10
	cmp	x10, x11
	b.eq	.LBB4_14
.LBB4_12:
	add	x8, x11, x8
	sub	x9, x8, x9
.LBB4_13:
	ldrb	w10, [x8]
	adds	x9, x9, #1
	add	w10, w10, #1
	strb	w10, [x8], #1
	b.lo	.LBB4_13
.LBB4_14:
	ret
```

</details>

The same `store_int_float` with `-fno-strict-aliasing`, x86-64 then AArch64. The constant `1` becomes a reload:

```asm
_Z15store_int_floatPiPf:           # store_int_float(int*, float*)
	movl	$1, (%rdi)
	movl	$1073741824, (%rsi)
	movl	(%rdi), %eax
	retq
```

```asm
_Z15store_int_floatPiPf:           // store_int_float(int*, float*)
	mov	w8, #1
	mov	w9, #1073741824
	str	w8, [x0]
	str	w9, [x1]
	ldr	w0, [x0]
	ret
```

What the listing proves:

* `store_int_float` returns the constant `1` (`movl $1, %eax`): the store through `float*` is *assumed not
  to touch* `*i`. With `-fno-strict-aliasing` that assumption disappears and the load returns.
* `store_int_char` reloads `*i` after a store through `unsigned char*`.
* **`bump_u8` is the expensive one.** `v[i] += 1` on a `vector<uint8_t>` is an `unsigned char` store, which
  might modify the vector's *own* `begin`/`end` pointers. So the loop reloads `(%rdi)` and `8(%rdi)` on
  every iteration and is **not vectorized**: one byte per iteration.
* `bump_c8` is the same loop over `vector<char8_t>`. `char8_t` (C++20) is a distinct type **without** the
  aliasing exemption, so Clang hoists the bounds and vectorizes, 32 bytes per iteration (two `movdqu` + `psubb`
  pairs). `bump_u8_hoisted` gets the same code by copying `data()` and `size()` into locals.

### 1.3 Type punning: four spellings, one instruction, one of them a trap (Listing 3.2)

```cpp
// punning.cpp - reading an object's bytes as another type: what is defined, what is UB, what it compiles to
#include <bit>
#include <cstdint>
#include <cstring>
#include <print>

// UB: accesses a float object through an uint32_t glvalue (violates [basic.lval]/11).
std::uint32_t bits_reinterpret(const float& f) { return *reinterpret_cast<const std::uint32_t*>(&f); }
// UB in C++ (reads an inactive union member); GCC and Clang document it as a supported extension.
std::uint32_t bits_union(float f) {
    union {
        float f;
        std::uint32_t u;
    } x{f};
    return x.u;
}
// Defined since C++98: copy the object representation.
std::uint32_t bits_memcpy(float f) {
    std::uint32_t u;
    std::memcpy(&u, &f, sizeof u);
    return u;
}
// Defined, constexpr, and type-checked (sizes must match, both trivially copyable): C++20.
std::uint32_t bits_cast(float f) { return std::bit_cast<std::uint32_t>(f); }

// bit_cast works in constant expressions; memcpy and reinterpret_cast do not.
static_assert(std::bit_cast<std::uint32_t>(1.0f) == 0x3f80'0000u);
static_assert(std::bit_cast<float>(0x4049'0fdbu) == 3.14159274f);

// Fast inverse square root, written without UB.
float rsqrt(float x) {
    std::uint32_t i = 0x5f37'59dfu - (std::bit_cast<std::uint32_t>(x) >> 1);
    float y = std::bit_cast<float>(i);
    return y * (1.5f - 0.5f * x * y * y);
}

// What the UB costs: TBAA assumes a uint32_t store cannot modify a float object.
[[gnu::noinline]] float store_then_read(float* f, std::uint32_t* u) {
    *f = 1.0f;
    *u = 0;
    return *f;                        // folded to the constant 1.0f at -O2
}

int main() {
    float f = -0.0f;
    std::println("memcpy   : {:#010x}", bits_memcpy(f));
    std::println("bit_cast : {:#010x}", bits_cast(f));
    std::println("union    : {:#010x}  (extension)", bits_union(f));
    std::println("rsqrt(4) : {:.6f}", rsqrt(4.0f));
    float x = 5.0f;
    float r = store_then_read(&x, reinterpret_cast<std::uint32_t*>(&x));  // UB: aliased float/uint32_t
    std::println("aliased store: function returned {}, memory now holds {}", r, x);
}
```

```asm
_Z16bits_reinterpretRKf:           # bits_reinterpret(float const&)
	movl	(%rdi), %eax
	retq

_Z10bits_unionf:                   # bits_union(float)
	movd	%xmm0, %eax
	retq

_Z11bits_memcpyf:                  # bits_memcpy(float)
	movd	%xmm0, %eax
	retq

_Z9bits_castf:                     # bits_cast(float)
	movd	%xmm0, %eax
	retq
```

```asm
_Z16bits_reinterpretRKf:           // bits_reinterpret(float const&)
	ldr	w0, [x0]
	ret

_Z10bits_unionf:                   // bits_union(float)
	fmov	w0, s0
	ret

_Z11bits_memcpyf:                  // bits_memcpy(float)
	fmov	w0, s0
	ret

_Z9bits_castf:                     // bits_cast(float)
	fmov	w0, s0
	ret
```

All four compile to the same single instruction (`movd %xmm0,%eax` / `fmov w0, s0`, or a plain load for the
by-reference version). `memcpy` and `std::bit_cast` cost nothing. Output, default flags (verified, both
compilers):

```text
memcpy   : 0x80000000
bit_cast : 0x80000000
union    : 0x80000000  (extension)
rsqrt(4) : 0.499154
aliased store: function returned 1, memory now holds 0
```

With `-fno-strict-aliasing` (both compilers):

```text
memcpy   : 0x80000000
bit_cast : 0x80000000
union    : 0x80000000  (extension)
rsqrt(4) : 0.499154
aliased store: function returned 0, memory now holds 0
```

The last line is the point. `store_then_read` writes `1.0f`, then writes `0` through a `uint32_t*` that
aliases the float. Memory holds 0, **but the function returns 1**: TBAA let both compilers fold the final
load to the constant they had just stored. Same source, same machine, different answer depending on one flag.
That is what "UB" means in practice.

`std::bit_cast` is also `constexpr` (the `static_assert`s in the listing) and type-checked: equal sizes, both
types trivially copyable. Use it for every value-level reinterpretation, and `memcpy` for byte buffers.

### 1.4 `std::launder` and the vptr: Clang turns the rule into code (Listing 3.3)

```cpp
// launder.cpp - why std::launder exists: the optimizer may assume a pointer's dynamic type never changes
// Build with and without -fstrict-vtable-pointers (Clang): the flag turns that assumption into codegen.
#include <new>

struct Animal {
    virtual ~Animal();
    virtual int speak() const;
};
struct Cat final : Animal {
    int speak() const override;
};

// Two calls through the same pointer. Without the flag the vptr is reloaded after the first call
// (speak() might have placement-new'ed a different type into *a). With the flag it is loaded once.
int twice(const Animal* a) { return a->speak() + a->speak(); }

// Replace the object with one of a DIFFERENT dynamic type. 'a' does not point to the new Cat
// ([basic.life]/8: not transparently replaceable), so using it is UB...
int replaced(Animal* a) {
    a->~Animal();
    ::new (static_cast<void*>(a)) Cat;
    return a->speak();                // UB: with the flag, Clang reuses what it knows about *a
}
// ...std::launder produces a pointer to the object that now lives at that address.
int replaced_laundered(Animal* a) {
    a->~Animal();
    ::new (static_cast<void*>(a)) Cat;
    return std::launder(a)->speak();  // defined: dispatches to Cat::speak
}

#ifdef LAUNDER_MAIN                   // run-time check (Clang only: GCC has no -fstrict-vtable-pointers)
#include <print>
Animal::~Animal() = default;
int Animal::speak() const { return 1; }
int Cat::speak() const { return 2; }
int main() {
    int (*volatile ub)(Animal*) = replaced;  // volatile: keep the calls opaque to the optimizer
    int (*volatile ok)(Animal*) = replaced_laundered;
    Animal* a = new Animal;
    int r1 = ub(a);
    delete std::launder(a);
    Animal* b = new Animal;
    int r2 = ok(b);
    delete std::launder(b);
    std::println("replaced()           -> {} ({})", r1, r1 == 2 ? "Cat::speak" : "Animal::speak on a Cat!");
    std::println("replaced_laundered() -> {} ({})", r2, r2 == 2 ? "Cat::speak" : "Animal::speak on a Cat!");
}
#endif
```

Clang `-O3`, default:

```asm
_Z5twicePK6Animal:                 # twice(Animal const*)
	pushq	%rbp
	pushq	%rbx
	pushq	%rax
	movq	%rdi, %rbx
	movq	(%rdi), %rax
	callq	*16(%rax)
	movl	%eax, %ebp
	movq	(%rbx), %rax
	movq	%rbx, %rdi
	callq	*16(%rax)
	addl	%ebp, %eax
	addq	$8, %rsp
	popq	%rbx
	popq	%rbp
	retq

_Z8replacedP6Animal:               # replaced(Animal*)
	pushq	%rbx
	movq	%rdi, %rbx
	movq	(%rdi), %rax
	callq	*(%rax)
	movq	_ZTV3Cat@GOTPCREL(%rip), %rax         # vtable for Cat
	leaq	16(%rax), %rcx
	movq	%rcx, (%rbx)
	movq	%rbx, %rdi
	popq	%rbx
	jmpq	*32(%rax)

_Z18replaced_launderedP6Animal:    # replaced_laundered(Animal*)
	pushq	%rbx
	movq	%rdi, %rbx
	movq	(%rdi), %rax
	callq	*(%rax)
	movq	_ZTV3Cat@GOTPCREL(%rip), %rax         # vtable for Cat
	leaq	16(%rax), %rcx
	movq	%rcx, (%rbx)
	movq	%rbx, %rdi
	popq	%rbx
	jmpq	*32(%rax)
```

Clang `-O3 -fstrict-vtable-pointers`:

```asm
_Z5twicePK6Animal:                 # twice(Animal const*)
	pushq	%rbp
	pushq	%r14
	pushq	%rbx
	movq	%rdi, %rbx
	movq	(%rdi), %rax
	movq	16(%rax), %r14
	callq	*%r14
	movl	%eax, %ebp
	movq	%rbx, %rdi
	callq	*%r14
	addl	%ebp, %eax
	popq	%rbx
	popq	%r14
	popq	%rbp
	retq

_Z8replacedP6Animal:               # replaced(Animal*)
	pushq	%r14
	pushq	%rbx
	pushq	%rax
	movq	%rdi, %rbx
	movq	(%rdi), %r14
	callq	*(%r14)
	movq	_ZTV3Cat@GOTPCREL(%rip), %rax         # vtable for Cat
	addq	$16, %rax
	movq	%rax, (%rbx)
	movq	%rbx, %rdi
	movq	%r14, %rax
	addq	$8, %rsp
	popq	%rbx
	popq	%r14
	jmpq	*16(%rax)

_Z18replaced_launderedP6Animal:    # replaced_laundered(Animal*)
	pushq	%rbx
	movq	%rdi, %rbx
	movq	(%rdi), %rax
	callq	*(%rax)
	movq	_ZTV3Cat@GOTPCREL(%rip), %rax         # vtable for Cat
	leaq	16(%rax), %rcx
	movq	%rcx, (%rbx)
	movq	%rbx, %rdi
	popq	%rbx
	jmpq	*32(%rax)
```

<details><summary>AArch64, -fstrict-vtable-pointers</summary>

```asm
_Z5twicePK6Animal:                 // twice(Animal const*)
	stp	x30, x21, [sp, #-32]!
	stp	x20, x19, [sp, #16]
	ldr	x8, [x0]
	mov	x19, x0
	ldr	x21, [x8, #16]
	blr	x21
	mov	w20, w0
	mov	x0, x19
	blr	x21
	add	w0, w0, w20
	ldp	x20, x19, [sp, #16]
	ldp	x30, x21, [sp], #32
	ret

_Z8replacedP6Animal:               // replaced(Animal*)
	str	x30, [sp, #-32]!
	stp	x20, x19, [sp, #16]
	ldr	x20, [x0]
	mov	x19, x0
	ldr	x8, [x20]
	blr	x8
	adrp	x8, :got:_ZTV3Cat                     // vtable for Cat
	mov	x0, x19
	ldr	x8, [x8, :got_lo12:_ZTV3Cat]           // vtable for Cat
	add	x8, x8, #16
	str	x8, [x19]
	ldr	x1, [x20, #16]
	ldp	x20, x19, [sp, #16]
	ldr	x30, [sp], #32
	br	x1

_Z18replaced_launderedP6Animal:    // replaced_laundered(Animal*)
	stp	x30, x19, [sp, #-16]!
	ldr	x8, [x0]
	mov	x19, x0
	ldr	x8, [x8]
	blr	x8
	adrp	x8, :got:_ZTV3Cat                     // vtable for Cat
	mov	x0, x19
	ldr	x8, [x8, :got_lo12:_ZTV3Cat]           // vtable for Cat
	ldr	x1, [x8, #32]
	add	x8, x8, #16
	str	x8, [x19]
	ldp	x30, x19, [sp], #16
	br	x1
```

</details>

* **`twice`.** By default the vptr is reloaded after the first call (`movq (%rbx),%rax` before the second
  `callq`), because `speak()` might have ended `*a`'s lifetime and created a different object there. With
  `-fstrict-vtable-pointers`, Clang loads the slot **once** into `%r14` and calls it twice. The flag tells
  Clang to rely on the rule that "a pointer's dynamic type cannot change without `std::launder`".
* **`replaced` (UB) under the flag.** Clang saved the *old* vptr in `%r14` before the destructor call, stored
  Cat's vptr into the object, and then **called through the saved old vptr** (`jmpq *16(%rax)` with
  `%rax = %r14`). That is `Animal::speak` on a `Cat`.
* **`replaced_laundered`** reloads from Cat's vtable (`jmpq *32(%rax)` off `_ZTV3Cat`) in both modes.

Run-time confirmation (Clang only; GCC has no `-fstrict-vtable-pointers`):

```text
-fstrict-vtable-pointers:
replaced()           -> 1 (Animal::speak on a Cat!)
replaced_laundered() -> 2 (Cat::speak)
```

```text
default flags:
replaced()           -> 2 (Cat::speak)
replaced_laundered() -> 2 (Cat::speak)
```

**When you need `std::launder` (C++20 rules).** A new object *transparently replaces* the old one, so old
pointers and names keep working without launder, when: it occupies exactly the same storage, has the same
type (ignoring top-level cv), the old object is not a *complete const object*, and neither is a
*potentially-overlapping subobject* (a base class or `[[no_unique_address]]` member). You need `std::launder`
when:

| Case | Example | Why |
|---|---|---|
| different type in the storage | `new (a) Cat` through `Animal* a` (Listing 3.3) | not the same type → not transparently replaceable |
| pointer formed from raw storage | `reinterpret_cast<T*>(buf)` after `new (buf) T` | the pointer points to the `std::byte` array, never to the `T` (Listing 3.7) |
| complete const object replaced | `const T t; ... new (&t) T` | [basic.life]/8. For static, thread or automatic `const` objects it is UB even *with* launder ([basic.life]/10) |
| base-class subobject replaced | `new (static_cast<Base*>(d)) Base` | potentially-overlapping (file 04: tail padding) |

The C++17 rule was stricter (const or reference *members* also required launder). C++20 dropped that
condition. The simplest discipline is to **keep the pointer that placement new returns** and never re-derive
it.

### 1.5 Bytes from the wire: implicit lifetime, `start_lifetime_as`, and alignment (Listing 3.4)

```cpp
// wire_parse.cpp - reading structs out of a byte buffer: reinterpret_cast (UB), memcpy, start_lifetime_as
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <memory>
#include <type_traits>

struct Header {                        // an implicit-lifetime aggregate: trivially copyable, trivial dtor
    std::uint32_t magic;
    std::uint16_t len;
    std::uint16_t flags;
};
static_assert(std::is_implicit_lifetime_v<Header>);  // C++23 trait
static_assert(alignof(Header) == 4);

// UB twice over: no Header object exists in the buffer, and buf may not be 4-byte aligned.
std::uint16_t len_cast(const std::byte* buf) { return reinterpret_cast<const Header*>(buf)->len; }
// Defined for any alignment, and the copy is free: same instructions as the cast.
std::uint16_t len_memcpy(const std::byte* buf) {
    Header h;
    std::memcpy(&h, buf, sizeof h);
    return h.len;
}
// Defined for any alignment: copy just the field you need.
std::uint16_t len_field(const std::byte* buf) {
    std::uint16_t v;
    std::memcpy(&v, buf + offsetof(Header, len), sizeof v);
    return v;
}
#if defined(__cpp_lib_start_lifetime_as)
// C++23: implicitly create a Header IN the buffer (no copy). Alignment is still the caller's problem.
std::uint16_t len_start_lifetime(std::byte* buf) { return std::start_lifetime_as<Header>(buf)->len; }
#endif

// Atomics are where misalignment stops being free: the atomic forms below require natural alignment.
// x86-64: an unaligned LOCK'ed access that spans two cache lines is a "split lock" (bus lock).
// AArch64: LDAR/STLR and LDXR/STXR raise an alignment fault when misaligned (FEAT_LSE2 relaxes this only
// for LDAR/STLR/LDAPR within an aligned 16-byte window).
std::uint32_t acquire_magic(Header& h) {
    return std::atomic_ref<std::uint32_t>(h.magic).load(std::memory_order_acquire);
}
std::uint32_t bump_magic(Header& h) {
    return std::atomic_ref<std::uint32_t>(h.magic).fetch_add(1, std::memory_order_acq_rel);
}
```

Clang `-O3`, x86-64:

```asm
_Z8len_castPKSt4byte:              # len_cast(std::byte const*)
	movzwl	4(%rdi), %eax
	retq

_Z10len_memcpyPKSt4byte:           # len_memcpy(std::byte const*)
	movzwl	4(%rdi), %eax
	retq

_Z9len_fieldPKSt4byte:             # len_field(std::byte const*)
	movzwl	4(%rdi), %eax
	retq

_Z13acquire_magicR6Header:         # acquire_magic(Header&)
	movl	(%rdi), %eax
	retq

_Z10bump_magicR6Header:            # bump_magic(Header&)
	movl	$1, %eax
	lock	xaddl	%eax, (%rdi)
	retq
```

AArch64, baseline Armv8.0-A:

```asm
_Z8len_castPKSt4byte:              // len_cast(std::byte const*)
	ldrh	w0, [x0, #4]
	ret

_Z10len_memcpyPKSt4byte:           // len_memcpy(std::byte const*)
	ldrh	w0, [x0, #4]
	ret

_Z9len_fieldPKSt4byte:             // len_field(std::byte const*)
	ldrh	w0, [x0, #4]
	ret

_Z13acquire_magicR6Header:         // acquire_magic(Header&)
	ldar	w0, [x0]
	ret

_Z10bump_magicR6Header:            // bump_magic(Header&)
.LBB4_1:
	ldaxr	w8, [x0]
	add	w9, w8, #1
	stlxr	w10, w9, [x0]
	cbnz	w10, .LBB4_1
	mov	w0, w8
	ret
```

AArch64, `-mcpu=neoverse_n1` (Armv8.2 + LSE + RCpc):

```asm
_Z13acquire_magicR6Header:         // acquire_magic(Header&)
	ldapr	w0, [x0]
	ret

_Z10bump_magicR6Header:            // bump_magic(Header&)
	mov	w8, #1
	ldaddal	w8, w0, [x0]
	ret
```

* **`len_cast`, `len_memcpy` and `len_field` are the same instruction** (`movzwl 4(%rdi)` / `ldrh w0,[x0,#4]`).
  The defined versions cost nothing. Both ISAs allow unaligned *normal* loads on ordinary memory (on AArch64
  as long as `SCTLR_EL1.A` is clear, which it is for Linux user space).
* **C++20 implicit object creation (P0593R6).** Operations that create storage (`malloc`, `operator new`,
  `std::allocator::allocate`, `memcpy` into a byte array, starting the lifetime of a `char`/`std::byte`
  array) implicitly create objects of implicit-lifetime types (`Header` qualifies, as
  `std::is_implicit_lifetime_v` confirms) *if that gives the program defined behaviour*. That retroactively made
  `Header* h = (Header*)malloc(sizeof *h); h->magic = 1;` valid. It does **not** make `reinterpret_cast` of
  an arbitrary received buffer valid, because nothing in that code created storage.
* **`std::start_lifetime_as<T>` (C++23, P2590R2)** is the explicit form for an existing buffer: no copy, an
  object of type `T` now lives there with the bytes' value. Availability differs: libstdc++ 16 has it,
  libc++ 21 does not (Listing 3.8), hence the `#if`.
* **Atomics are where alignment stops being free.** `acquire_magic` is `ldar` on Armv8.0 and `ldapr` (RCpc,
  cheaper ordering) on Neoverse N1. `bump_magic` is an `ldaxr`/`stlxr` retry loop on Armv8.0 and a single
  `ldaddal` with LSE. On x86 it is `lock xadd` in both cases. ⚠ From the Arm ARM, not executed here: a
  misaligned `LDAR`/`STLR`/`LDXR`/`STXR` raises an alignment fault. FEAT_LSE2 relaxes that only for
  `LDAR`/`STLR`/`LDAPR` that stay within a 16-byte aligned window, and never for exclusives. On x86, a `LOCK`ed
  access that splits a cache line is a *split lock*: a bus lock that Linux can detect and penalize
  (`split_lock_detect`). `std::atomic_ref` requires `required_alignment` for exactly this reason.

### 1.6 When temporaries die (Listing 3.5)

```cpp
// lifetime.cpp - when a temporary dies: reference binding extends it, function boundaries do not, and the
// C++23 range-for rule (P2718). Every probe prints the destructor instead of reading dead storage (no UB).
#include <cstdio>
#include <span>

bool g_alive = false;
const int kItems[] = {1, 2, 3};

struct Temp {
    const char* name;
    int member = 42;
    explicit Temp(const char* n) : name(n) { g_alive = true; }
    Temp(const Temp&) = delete;
    ~Temp() {
        g_alive = false;
        std::printf("    ~Temp(%s)\n", name);
    }
    std::span<const int> items() const { return kItems; }  // stands in for "return a member by reference"
};
#if defined(__clang__)
#define LIFETIMEBOUND [[clang::lifetimebound]]
#else
#define LIFETIMEBOUND
#endif
// Like std::min/std::max: returns its parameter. The annotation lets Clang's -Wdangling see through the call.
const Temp& identity(const Temp& t LIFETIMEBOUND) { return t; }

#if !defined(SHOW_DANGLING_WARNINGS) && !defined(__clang__)
#pragma GCC diagnostic ignored "-Wdangling-reference"  // the run below is deliberate; see the diagnostics
#endif
#if !defined(SHOW_DANGLING_WARNINGS) && defined(__clang__)
#pragma clang diagnostic ignored "-Wdangling"
#endif

int main() {
    std::printf("__cpp_range_based_for = %ld\n", static_cast<long>(__cpp_range_based_for));

    std::printf("1. const Temp& r = Temp{...};\n");
    {
        const Temp& r = Temp{"bound"};                  // lifetime extended to r's scope
        std::printf("    using r: alive=%d\n", g_alive);
        (void)r;
    }
    std::printf("2. const int& m = Temp{...}.member;\n");
    {
        const int& m = Temp{"member"}.member;           // extends the WHOLE temporary
        std::printf("    using m: alive=%d\n", g_alive);
        (void)m;
    }
    std::printf("3. const Temp& r = identity(Temp{...});\n");
    {
        const Temp& r = identity(Temp{"through-call"});  // NOT extended: dies at the ';' -> r dangles
        std::printf("    using r: alive=%d\n", g_alive);
        (void)r;
    }
    std::printf("4. for (int i : Temp{...}.items())\n");
    for (int i : Temp{"range"}.items()) {
        std::printf("    body i=%d: temporary alive=%d\n", i, g_alive);  // C++20: 0 (dangling), C++23: 1
        break;
    }
}
```

`-std=c++20` (verified; GCC and Clang print the same):

```text
__cpp_range_based_for = 201603
1. const Temp& r = Temp{...};
    using r: alive=1
    ~Temp(bound)
2. const int& m = Temp{...}.member;
    using m: alive=1
    ~Temp(member)
3. const Temp& r = identity(Temp{...});
    ~Temp(through-call)
    using r: alive=0
4. for (int i : Temp{...}.items())
    ~Temp(range)
    body i=1: temporary alive=0
```

`-std=c++23` (verified; GCC and Clang print the same):

```text
__cpp_range_based_for = 202211
1. const Temp& r = Temp{...};
    using r: alive=1
    ~Temp(bound)
2. const int& m = Temp{...}.member;
    using m: alive=1
    ~Temp(member)
3. const Temp& r = identity(Temp{...});
    ~Temp(through-call)
    using r: alive=0
4. for (int i : Temp{...}.items())
    body i=1: temporary alive=1
    ~Temp(range)
```

The only line that changes is case 4. In C++20 the `Temp` returned by `Temp{"range"}` dies **before the first
iteration**: the range-`for` desugars to `auto&& __range = Temp{...}.items();`, which binds the *span*, not the
`Temp`. If `items()` returned a reference into the `Temp`, the loop would iterate freed memory. P2718R0 (C++23)
extends the lifetime of every temporary in the range-initializer to the end of the loop. Both compilers
implement it (`__cpp_range_based_for` = 202211L).

The diagnostics when the pragmas are removed (`-DSHOW_DANGLING_WARNINGS`):

```text
C++23  (GCC, then Clang):
lifetime.cpp:52:21: error: possibly dangling reference to a temporary [-Werror=dangling-reference]
lifetime.cpp:52:34: error: temporary bound to local reference 'r' will be destroyed at the end of the full-expression [-Werror,-Wdangling]
```

```text
C++20  (GCC, then Clang):
lifetime.cpp:52:21: error: possibly dangling reference to a temporary [-Werror=dangling-reference]
lifetime.cpp:57:38: error: possibly dangling reference to a temporary [-Werror=dangling-reference]
lifetime.cpp:52:34: error: temporary bound to local reference 'r' will be destroyed at the end of the full-expression [-Werror,-Wdangling]
```

* GCC's `-Wdangling-reference` (new in GCC 13) flags case 3 heuristically. It flags the range-`for` case
  **only in C++20 mode**, because it knows the C++23 rule. In GCC 16.2 it is enabled by **`-Wextra`, not
  `-Wall`**: compiling this file with `-Wall` alone produced 0 of these warnings, and with `-Wextra`, 2.
* Clang flags case 3 only because `identity`'s parameter is annotated `[[clang::lifetimebound]]`. Without the
  annotation Clang is silent. Clang never flags the C++20 range-`for` case here.
* Case 3 is `std::min`/`std::max`: `const auto& m = std::max(a, f());` dangles. Return by value when either
  argument may be a temporary.

### 1.7 Constant evaluation as a UB detector (Listing 3.6)

```cpp
// constexpr_ub.cpp - constant evaluation is a UB detector: lifetime, union, and bounds bugs become hard errors
#include <memory>

union IntOrFloat {
    int i;
    float f;
};

constexpr int union_switch_ok() {
    IntOrFloat u{.i = 1};
    std::construct_at(&u.f, 2.0f);    // C++20: change the active member explicitly
    return static_cast<int>(u.f);
}
constexpr int reuse_storage_ok() {
    std::allocator<int> a;
    int* p = a.allocate(1);
    std::construct_at(p, 7);          // constexpr placement new (C++20); C++26 also allows ::new in constexpr
    int v = *p;
    std::destroy_at(p);
    a.deallocate(p, 1);
    return v;
}
static_assert(union_switch_ok() == 2);
static_assert(reuse_storage_ok() == 7);

#ifdef SHOW_CONSTEXPR_UB
constexpr int read_dead_local() {
    const int* p = nullptr;
    {
        int x = 1;
        p = &x;
    }
    return *p;                        // read of an object outside its lifetime
}
constexpr int read_inactive_member() {
    IntOrFloat u{.i = 1};
    return static_cast<int>(u.f);     // inactive member: UB (GCC documents run-time punning as an extension)
}
constexpr int past_the_end() {
    int a[2] = {1, 2};
    return a[2];                      // out-of-bounds read
}
constexpr int use_after_free() {
    std::allocator<int> al;
    int* p = al.allocate(1);
    std::construct_at(p, 3);
    al.deallocate(p, 1);
    return *p;                        // read after deallocation
}
static_assert(read_dead_local() == 1);
static_assert(read_inactive_member() == 1);
static_assert(past_the_end() == 0);
static_assert(use_after_free() == 3);
#endif

int main() { return union_switch_ok() + reuse_storage_ok() == 9 ? 0 : 1; }
```

The two "ok" functions compile and pass their `static_assert`s. With `-DSHOW_CONSTEXPR_UB` (expected failure):

```text
GCC 16.2:
constexpr_ub.cpp:50:33: error: non-constant condition for static assertion
constexpr_ub.cpp:33:12: error: accessing 'x' outside its lifetime
constexpr_ub.cpp:30:13: note: declared here
constexpr_ub.cpp:51:38: error: non-constant condition for static assertion
constexpr_ub.cpp:37:31: error: accessing 'IntOrFloat::f' member instead of active 'IntOrFloat::i' member in constant expression
constexpr_ub.cpp:52:30: error: non-constant condition for static assertion
constexpr_ub.cpp:41:15: error: array subscript value '2' is outside the bounds of array 'a' of type 'int [2]'
constexpr_ub.cpp:40:9: note: declared here
constexpr_ub.cpp:53:32: error: non-constant condition for static assertion
constexpr_ub.cpp:48:12: error: use of allocated storage after deallocation in a constant expression
allocator.h:203:52: note: allocated here
```

```text
Clang 21.1:
constexpr_ub.cpp:41:12: error: array index 2 is past the end of the array (that has type 'int[2]') [-Werror,-Warray-bounds]
constexpr_ub.cpp:40:5: note: array 'a' declared here
constexpr_ub.cpp:50:15: error: static assertion expression is not an integral constant expression
constexpr_ub.cpp:33:12: note: read of object outside its lifetime is not allowed in a constant expression
constexpr_ub.cpp:50:15: note: in call to 'read_dead_local()'
constexpr_ub.cpp:51:15: error: static assertion expression is not an integral constant expression
constexpr_ub.cpp:37:29: note: read of member 'f' of union with active member 'i' is not allowed in a constant expression
constexpr_ub.cpp:51:15: note: in call to 'read_inactive_member()'
constexpr_ub.cpp:52:15: error: static assertion expression is not an integral constant expression
constexpr_ub.cpp:41:12: note: read of dereferenced one-past-the-end pointer is not allowed in a constant expression
constexpr_ub.cpp:52:15: note: in call to 'past_the_end()'
constexpr_ub.cpp:53:15: error: static assertion expression is not an integral constant expression
constexpr_ub.cpp:48:12: note: read of heap allocated object that has been deleted
constexpr_ub.cpp:53:15: note: in call to 'use_after_free()'
```

The constant evaluator is required to diagnose core UB (it must reject the expression as "not a constant
expression"). It tracks object lifetimes, active union members, array bounds and allocation provenance,
which makes it a sanitizer that runs at compile time with **no false negatives for the code it evaluates**.
The engineering trick: make lifetime-heavy utilities `constexpr` and test them in `static_assert` (Listing 3.7).
The run-time behaviour of `read_inactive_member` is different: GCC documents union punning as an extension and
Clang follows, so at run time it "works", and only the constant evaluator holds you to the standard.

### 1.8 What this toolchain offers (Listing 3.8)

```cpp
// features.cpp - feature-test macros for the Folder 01 topics, as THIS compiler + standard library report them
#include <version>
#include <cstdio>
#include <memory>
#include <new>
#include <type_traits>

#define SHOW(m) std::printf("  %-40s %s\n", #m, show_value(#m, MACRO_STR(m)))
#define MACRO_STR(m) #m
#define XSTR(m) MACRO_STR(m)
// An undefined macro stringizes to its own name; a defined one to its value (e.g. 202106L).
static const char* show_value(const char* name, const char* expanded) {
    const char* a = name;
    const char* b = expanded;
    while (*a && *a == *b) ++a, ++b;
    return (*a == 0 && *b == 0) ? "-" : expanded;
}

int main() {
#if defined(__clang__)
    std::printf("compiler: Clang %d.%d, library: %s\n", __clang_major__, __clang_minor__,
#else
    std::printf("compiler: GCC %d.%d, library: %s\n", __GNUC__, __GNUC_MINOR__,
#endif
#if defined(_LIBCPP_VERSION)
                "libc++"
#else
                "libstdc++"
#endif
    );
    std::printf("  %-40s %s\n", "__cplusplus", XSTR(__cplusplus));
    SHOW(__cpp_guaranteed_copy_elision);
    SHOW(__cpp_implicit_move);
    SHOW(__cpp_range_based_for);
    SHOW(__cpp_constexpr);
    SHOW(__cpp_constexpr_dynamic_alloc);
    SHOW(__cpp_explicit_this_parameter);
    SHOW(__cpp_trivial_relocatability);
    SHOW(__cpp_lib_launder);
    SHOW(__cpp_lib_bit_cast);
    SHOW(__cpp_lib_start_lifetime_as);
    SHOW(__cpp_lib_is_implicit_lifetime);
    SHOW(__cpp_lib_trivially_relocatable);
    SHOW(__cpp_lib_constexpr_new);
    SHOW(__cpp_lib_hardware_interference_size);
}
```

```text
compiler: GCC 16.2, library: libstdc++
  __cplusplus                              202400L
  __cpp_guaranteed_copy_elision            201606L
  __cpp_implicit_move                      202207L
  __cpp_range_based_for                    202211L
  __cpp_constexpr                          202406L
  __cpp_constexpr_dynamic_alloc            201907L
  __cpp_explicit_this_parameter            202110L
  __cpp_trivial_relocatability             -
  __cpp_lib_launder                        201606L
  __cpp_lib_bit_cast                       201806L
  __cpp_lib_start_lifetime_as              202207L
  __cpp_lib_is_implicit_lifetime           202302L
  __cpp_lib_trivially_relocatable          -
  __cpp_lib_constexpr_new                  202406L
  __cpp_lib_hardware_interference_size     201703L
```

```text
compiler: Clang 21.1, library: libc++
  __cplusplus                              202400L
  __cpp_guaranteed_copy_elision            201606L
  __cpp_implicit_move                      202207L
  __cpp_range_based_for                    202211L
  __cpp_constexpr                          202406L
  __cpp_constexpr_dynamic_alloc            201907L
  __cpp_explicit_this_parameter            202110L
  __cpp_trivial_relocatability             -
  __cpp_lib_launder                        201606L
  __cpp_lib_bit_cast                       201806L
  __cpp_lib_start_lifetime_as              -
  __cpp_lib_is_implicit_lifetime           202302L
  __cpp_lib_trivially_relocatable          -
  __cpp_lib_constexpr_new                  202406L
  __cpp_lib_hardware_interference_size     201703L
```

`__cplusplus` is `202400L` in both compilers' `-std=c++26` mode (the standard is not final, so the value is
provisional). `__cpp_constexpr` = 202406L means constexpr placement new (P2747R2) is in both. The library
column differs: **`std::start_lifetime_as` is in libstdc++ 16 but not libc++ 21**. Neither defines the trivial
relocation macros, which is consistent with P2786's removal from C++26 (file 04).

---

## 2. Evolution table

| Standard | Change (paper) | Effect |
|---|---|---|
| C++98 | [basic.life], strict aliasing ([basic.lval]) | the rules; compilers enforced TBAA from the 2000s on |
| C++11 | `alignas`, `std::aligned_storage` | raw storage; `aligned_storage` deprecated in C++23 (P1413R3) |
| C++14 | — | — |
| C++17 | `std::launder` (P0137R1), `std::byte` | launder; `std::byte` has the aliasing exemption, `char8_t` (C++20) does not |
| C++17 | guaranteed elision | fewer temporaries to reason about (file 02) |
| C++20 | implicit object creation (P0593R6) | `malloc` + use of implicit-lifetime types is defined |
| C++20 | `std::bit_cast` (P0476R2) | constexpr, type-checked punning |
| C++20 | `std::construct_at`, constexpr allocation and destructors (P0784R7) | lifetime code testable in `static_assert` |
| C++20 | transparently replaceable objects ([basic.life]/8 rewording) | the const/reference-member condition dropped |
| C++20 | `char8_t` (P0482R6) | UTF-8 type without the aliasing exemption (Listing 3.1) |
| C++23 | `std::start_lifetime_as` (P2590R2), `std::is_implicit_lifetime` (P2674R1) | explicit implicit-object creation in existing storage |
| C++23 | range-for lifetime extension (P2718R0) | Listing 3.5, case 4 |
| C++23 | `aligned_storage`/`aligned_union` deprecated (P1413R3) | use `alignas(T) std::byte[]` + launder, or a union |
| C++26 | constexpr placement new (P2747R2) | `::new (p) T` in constant expressions |
| C++26 | `std::is_within_lifetime` (P2641R4) | constant-evaluation query (for example, which union member is active) |
| C++26 | erroneous behaviour for uninitialized reads (P2795R5) | reading an uninitialized automatic variable is *erroneous*, not UB: a defined wrong value that tools may diagnose |

---

## 3. Production blueprints

### 3.1 Storage slots, pools and optionals (Listing 3.7)

```cpp
// slot.cpp - optional-like storage: byte buffer + reinterpret_cast (UB) vs union storage proven in constexpr
#include <cstddef>
#include <memory>
#include <new>
#include <print>
#include <string>
#include <utility>

// Subtle buggy way: the classic aligned-buffer slot (std::aligned_storage is deprecated in C++23 for the same
// reasons). get() forms a T* from the address of a std::byte array: that pointer does not point to the T
// object created there, so every access is UB without std::launder. It also cannot run in constexpr.
template <class T>
class BuggySlot {
    alignas(T) std::byte buf_[sizeof(T)];
    bool full_ = false;

public:
    BuggySlot() = default;
    BuggySlot(const BuggySlot&) = delete;
    BuggySlot& operator=(const BuggySlot&) = delete;
    ~BuggySlot() { reset(); }
    template <class... A>
    T& emplace(A&&... a) {
        reset();
        ::new (static_cast<void*>(buf_)) T(std::forward<A>(a)...);
        full_ = true;
        return get();
    }
    T& get() { return *reinterpret_cast<T*>(buf_); }  // UB; minimal fix: *std::launder(reinterpret_cast<T*>(buf_))
    void reset() {
        if (full_) {
            get().~T();
            full_ = false;
        }
    }
};

// Production-hardened way: a union member NAMES the object, std::construct_at / std::destroy_at begin and end
// its lifetime (and switch the active member), and the whole thing is usable in constant expressions.
template <class T>
class Slot {
    union {
        T value_;                      // no active member until emplace()
    };
    bool full_ = false;

public:
    constexpr Slot() noexcept {}
    Slot(const Slot&) = delete;
    Slot& operator=(const Slot&) = delete;
    constexpr ~Slot() { reset(); }
    template <class... A>
    constexpr T& emplace(A&&... a) {
        reset();
        std::construct_at(std::addressof(value_), std::forward<A>(a)...);
        full_ = true;
        return value_;
    }
    constexpr T& get() noexcept { return value_; }
    constexpr bool has_value() const noexcept { return full_; }
    constexpr void reset() noexcept {
        if (full_) {
            std::destroy_at(std::addressof(value_));
            full_ = false;
        }
    }
};

// Every lifetime transition below is checked by the constant evaluator: a use-after-destroy, a double destroy
// or a read of an inactive member would make this static_assert fail to compile (file 03, Listing 3.6).
constexpr std::size_t slot_selftest() {
    Slot<std::string> s;
    s.emplace("first");
    s.emplace(40, 'x');                // destroy + re-create in the same storage
    std::size_t n = s.get().size();
    s.reset();
    s.emplace("again");
    return n + s.get().size();
}
static_assert(slot_selftest() == 45);

int main() {
    BuggySlot<std::string> b;
    b.emplace("works at run time today");
    Slot<std::string> s;
    s.emplace("works, and is proven in constexpr");
    std::println("BuggySlot: \"{}\"", b.get());
    std::println("Slot     : \"{}\"  sizeof(BuggySlot)={} sizeof(Slot)={}", s.get(), sizeof(BuggySlot<std::string>),
                 sizeof(Slot<std::string>));
}
```

```text
GCC 16.2:
BuggySlot: "works at run time today"
Slot     : "works, and is proven in constexpr"  sizeof(BuggySlot)=40 sizeof(Slot)=40
```

```text
Clang 21.1:
BuggySlot: "works at run time today"
Slot     : "works, and is proven in constexpr"  sizeof(BuggySlot)=32 sizeof(Slot)=32
```

`BuggySlot` works at run time on today's compilers, and that is the trap. Its `get()` is UB, `-fstrict-vtable-
pointers`-style optimizations are allowed to exploit it (Listing 3.3), and it cannot be tested in a constant
expression because `reinterpret_cast` is not allowed there. `Slot` uses a union member to *name* the object
and `construct_at`/`destroy_at` to manage it. It is the same size, and `static_assert(slot_selftest() == 45)`
proves every lifetime transition on both compilers. This is how `std::optional` and `std::variant` are written
in both standard libraries.

### 3.2 Parsing untrusted bytes

| Need | Use | Not |
|---|---|---|
| a field | `memcpy` into a local / `std::bit_cast` from `std::array<std::byte, N>` | `*reinterpret_cast<uint16_t*>(p + 4)` |
| a whole header, copied | `memcpy` into a local `Header` | casting the buffer |
| zero-copy view of an aligned buffer you own | `std::start_lifetime_as<Header>(p)` (libstdc++ 16), else `memcpy` | `reinterpret_cast` + "it works" |
| endianness | `std::byteswap` (C++23) after the copy | `ntohl` on a misaligned pointer |
| atomics on a shared ring | `std::atomic_ref<T>` on storage aligned to `atomic_ref<T>::required_alignment` | `reinterpret_cast<std::atomic<T>*>` into a byte buffer |

### 3.3 Make the optimizer your test

Two build flavours that turn latent lifetime bugs into failures you can see: a **Clang
`-fstrict-vtable-pointers` build** (Listing 3.3 shows it miscompiles missing-launder code), and **`constexpr`
self-tests** for every storage-managing type (Listing 3.7). Add UBSan's `-fsanitize=vptr` (dynamic-type
checks on member calls and casts) and ASan's use-after-scope detection in CI. ⚠ Neither sanitizer runtime was
exercised in this Windows harness; both are standard on Linux Clang/GCC.

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| value "doesn't update" at `-O2`, fine at `-O0` | aliasing violation folded by TBAA (Listing 3.2) | `-fno-strict-aliasing` changes the result → you have a TBAA bug; `-Wstrict-aliasing` catches only direct casts |
| byte-processing loop 10–30× slower than expected | `uint8_t` stores alias the container's pointers (Listing 3.1) | look for reloads of `begin`/`end` in the loop; hoist them, or use `char8_t`/`std::byte`-free element types |
| wrong virtual function after object reuse in a pool | missing `std::launder` / reused stale pointer (Listing 3.3) | Clang `-fstrict-vtable-pointers` build; UBSan `-fsanitize=vptr` |
| range-`for` prints garbage on one compiler only | C++20 temporary lifetime (Listing 3.5) | `-Wdangling-reference` (GCC, in `-Wextra`), `lifetimebound` (Clang), `-std=c++23` |
| `SIGBUS` / alignment fault only on ARM64 | atomic or exclusive access to a misaligned field | align atomics; `static_assert(alignof(...))`; never cast byte buffers to `std::atomic<T>*` |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "What does std::launder do?"</b></summary>

**Initial prompt.** "Explain `std::launder`. When have you needed it?"

**L5 textbook answer.** "It's for placement new: it tells the compiler that memory changed, so it doesn't use a
cached value."

**Why L5 breaks.** It treats launder as a memory barrier or a "volatile-lite". It is neither: it emits no
instruction (Listing 3.3 default build: identical code). It is a *pointer-provenance* operation. It returns a
pointer to the object that currently lives at an address, when the original pointer points to an old object
or to raw storage. The L5 model cannot say *when* it is needed (the C++20 transparent-replacement table in §1.4)
and cannot show a failure. Listing 3.3 shows one: with `-fstrict-vtable-pointers`, the unlaundered call
dispatches to `Animal::speak` on a `Cat`.

**L7 principal defense.** "Launder is how you tell the compiler 'a different object lives here now'. In
practice I avoid needing it: keep the pointer returned by placement new, and use union-member storage plus
`construct_at`, as `std::optional` does. Where it is unavoidable (byte-buffer pools), I launder in exactly one
accessor and build that code in a Clang `-fstrict-vtable-pointers` configuration in CI, because that is the
configuration that turns a missing launder into a visible wrong call."
</details>

<details><summary><b>Chain 2 🔥 "Is type punning through a union OK?"</b></summary>

**Initial prompt.** "To get a float's bits, I write to `u.f` and read `u.i`. Fine in C++?"

**L5 textbook answer.** "Yes, that's what unions are for. It's also how C does it."

**Why L5 breaks.** C allows it (C99 TC3 onward), C++ does not: reading a non-active member is UB. GCC
*documents* it as an extension and Clang follows, which is why it works at run time. But the constant
evaluator rejects it (Listing 3.6, "accessing 'IntOrFloat::f' member instead of active 'IntOrFloat::i'"). Other
compilers, or a future GCC with stricter TBAA modes, owe you nothing. The neighbouring idiom,
`*reinterpret_cast<uint32_t*>(&f)`, does miscompile today (Listing 3.2: the function returned 1 while memory
held 0).

**L7 principal defense.** "`std::bit_cast` for values (constexpr, type-checked, compiles to one `movd`/`fmov`),
`memcpy` for buffers. Both are zero-cost per Listing 3.2. Union punning appears only in C-compatible headers,
and only under a documented compiler-extension contract."
</details>

<details><summary><b>Chain 3 ⚡ "Why doesn't my byte loop vectorize?"</b></summary>

**Initial prompt.** "This loop over `std::vector<uint8_t>` runs at one byte per cycle. The same loop over
`vector<int>` vectorizes. Why?"

**L5 textbook answer.** "Bytes are slower to process; the compiler doesn't vectorize small types well."

**Why L5 breaks.** Compilers vectorize bytes very well: `bump_c8` processes 32 bytes per iteration. The
problem is aliasing. `uint8_t` is `unsigned char`, which may alias the vector object itself, so each store could
change `begin`/`end`, and the compiler must reload both every iteration (Listing 3.1, `bump_u8`). The same
pessimization hits `std::string` and any struct field accessed through `this` inside a byte loop.

**L7 principal defense.** "Hoist the bounds into locals (`bump_u8_hoisted`), or iterate with pointers you
copied up front, or use an element type without the exemption (`char8_t`, a `enum class Byte : uint8_t`). Then
confirm in the assembly. In code review I look for `this->` or container member access inside byte loops,
because the cost is invisible in the source."
</details>

<details><summary><b>Chain 4 🔥 "Can I reinterpret_cast a network buffer to a struct?"</b></summary>

**Initial prompt.** "We receive packets into `char buf[2048]` and do `auto* h = reinterpret_cast<Header*>(buf +
off);`. It's been fine for years on x86. We're moving to Graviton. Concerns?"

**L5 textbook answer.** "It's technically UB but every compiler supports it. ARM handles unaligned loads too, so
it's fine."

**Why L5 corrupts memory (or faults) on ARM64.** Three separate problems. (1) **No `Header` object exists**
in `buf`: nothing created storage, so C++20 implicit creation does not apply. The compiler may assume the
`char` stores that filled `buf` and the `Header` loads are unrelated. Today that usually "works", in the same
way Listing 3.2's function "works" until it returns a stale value. (2) Plain unaligned loads are fine on
AArch64 user space, **but the moment a field is touched atomically** (a sequence number in a shared ring, read
with `std::atomic_ref`/`__atomic_load` or via a `reinterpret_cast<std::atomic<uint32_t>*>`) the access becomes
`ldar`/`ldaxr` (Listing 3.4). Those **fault when misaligned** (LSE2 helps `ldar` within a 16-byte window, not
exclusives). x86 just performs a split lock, slowly but successfully, so the bug never showed. (3) Endianness
and padding assumptions are baked into the cast.

**L7 principal defense.** "Parse by copy: `memcpy` the header into a local (Listing 3.4 shows it is the same
instruction), `std::byteswap` as needed, and validate. Zero-copy views only for buffers we allocate and align
ourselves, via `std::start_lifetime_as` where the library has it. Atomic fields live in properly aligned
structures, never inside byte buffers, with a `static_assert` on `alignof`. And a CI leg on real AArch64,
because x86 hides both the alignment and the ordering bugs."
</details>

<details><summary><b>Chain 5 ⚡ "for (auto x : make().items()) — safe?"</b></summary>

**Initial prompt.** "Is `for (auto& x : get_config().servers())` safe if `servers()` returns
`const std::vector<Server>&`?"

**L5 textbook answer.** "Yes, range-for keeps the temporary alive for the whole loop."

**Why L5 breaks.** Before C++23 it does **not**. Only the object bound to `__range` is extended, and that object
is the returned *reference*'s target inside a temporary that dies at the end of the init statement. Listing 3.5
case 4: in C++20 the destructor runs before the first iteration. Since C++23 (P2718R0) it is safe, so the answer
depends on the `-std` flag of the TU, which in a large code base is not one value.

**L7 principal defense.** "I know the rule changed in C++23 and both compilers implement it, but I write code
that is correct under both: bind the owner first (`auto cfg = get_config(); for (auto& s : cfg.servers())`).
I enable GCC's `-Wdangling-reference` and annotate accessors with `[[clang::lifetimebound]]`, which also covers
the `std::max`-style dangling (case 3) that no standard revision fixes."
</details>

<details><summary><b>Chain 6 🧊 "Can I destroy and re-create a const object in place?"</b></summary>

**Initial prompt.** "A global `const Config cfg` must be reloaded. Can I call its destructor and placement-new a
new one in the same place?"

**L5 textbook answer.** "Yes, with `const_cast` and placement new; maybe use `std::launder` afterwards."

**Why L5 breaks.** For a **complete const object with static, thread or automatic storage duration**, creating
a new object in its storage is UB *even with launder* ([basic.life]/10). The compiler may have placed it in
read-only memory (then the store faults) or constant-folded its fields into every use (then readers keep the
old values forever). There is also a concurrency bug: readers on other threads see a torn object while it is
being re-created.

**L7 principal defense.** "Configuration that changes is not `const`. I publish immutable snapshots:
`std::atomic<std::shared_ptr<const Config>>` (Folder 07), or RCU/hazard pointers on hot read paths (Folder 09).
Readers get a consistent object, and the old one dies when its last reader drops it. `const` then means what it
says: this object never changes."
</details>

<details><summary><b>Chain 7 🧊 "Is malloc'ing a struct UB in C++?"</b></summary>

**Initial prompt.** "`auto* p = static_cast<Point*>(std::malloc(sizeof(Point))); p->x = 1;` Is that valid C++?"

**L5 textbook answer.** "Yes, Point is a POD."

**Why L5 breaks.** Before C++20 it was formally UB, because no object of type `Point` was ever created (there
was no "POD exception"). P0593R6 (C++20) fixed it with *implicit object creation* for implicit-lifetime
types. The fix has limits. It covers storage-creating
operations, not arbitrary reinterpretation. It covers implicit-lifetime types only, so `std::string` in malloc'd
memory still needs placement new. And it does not cover alignment.

**L7 principal defense.** "For implicit-lifetime types, `malloc`/`operator new` + use is defined since C++20,
and `std::start_lifetime_as` covers existing buffers in C++23. Anything with a constructor or destructor gets
`std::construct_at`/`std::destroy_at`, or better, a typed allocator. I check `std::is_implicit_lifetime_v` in a
`static_assert` wherever code relies on implicit creation."
</details>

<details><summary><b>Chain 8 ⚡ "How do you find lifetime UB before production does?"</b></summary>

**Initial prompt.** "What is your strategy for catching lifetime and aliasing UB?"

**L5 textbook answer.** "Run AddressSanitizer and fix what it finds."

**Why L5 breaks.** ASan finds use-after-free and buffer overflows. It does **not** find TBAA violations (Listing
3.2), missing launder (Listing 3.3), inactive union reads, or temporaries that die "too early" but whose memory
is still mapped. Several of those bugs only appear at a particular optimization level or with a particular
compiler, as in file 01's `cb_cast`, where GCC deleted half of `main`.

**L7 principal defense.** "Layered: (1) `constexpr` self-tests for storage types, where the constant
evaluator is exact (Listing 3.6). (2) Build diversity: GCC and Clang, `-O0` and `-O3`, and a Clang
`-fstrict-vtable-pointers` leg; a behaviour difference between legs is a UB alarm. (3) Sanitizers: ASan +
UBSan (`vptr`, `alignment`, `bounds`) + TSan in CI. (4) Warnings as errors: `-Wdangling-reference`,
`-Wstrict-aliasing`, `-Wclass-memaccess`. (5) Code review rules: no `reinterpret_cast` outside a reviewed
allowlist, and every placement new keeps its returned pointer."
</details>

---

## 6. Invariants checklist

- [ ] No `reinterpret_cast` between unrelated object types; values via `std::bit_cast`, buffers via `memcpy`.
- [ ] Byte loops hoist container bounds into locals (or use a non-aliasing element type).
- [ ] Every placement new keeps and uses the pointer it returns; any re-derived pointer goes through
      `std::launder`.
- [ ] Storage-managing types use union members + `construct_at`/`destroy_at` and have a `constexpr` self-test.
- [ ] No reuse of storage of complete `const` objects; changing configuration is published as new immutable
      snapshots.
- [ ] Wire parsing copies (or uses `start_lifetime_as` on owned, aligned buffers); atomics are naturally aligned.
- [ ] No reference bound to the result of a function that returns one of its by-reference arguments
      (`std::min`/`max`) when an argument may be a temporary.
- [ ] Range-`for` over a temporary's member is written to be correct in C++20 too, or the TU is pinned to C++23.
- [ ] CI runs GCC + Clang, `-O0` + `-O3`, plus a Clang `-fstrict-vtable-pointers` leg and ASan/UBSan/TSan.

## 7. References

- [basic.life], [basic.lval], [intro.object] (current draft): <https://eel.is/c++draft/basic.life>
- P0137R1 (launder): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2016/p0137r1.html>
- P0593R6 (implicit object creation): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2020/p0593r6.html>
- P0476R2 (bit_cast): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2017/p0476r2.html>
- P2590R2 (start_lifetime_as): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2022/p2590r2.pdf>
- P2718R0 (range-for lifetime): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2022/p2718r0.html>
- P2747R2 (constexpr placement new): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2024/p2747r2.html>
- P2795R5 (erroneous behaviour): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2024/p2795r5.html>
- GCC type-punning extension (`-fstrict-aliasing`): <https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html>
- Clang `lifetimebound`: <https://clang.llvm.org/docs/AttributeReference.html#lifetimebound>
- Arm Architecture Reference Manual (alignment of exclusives and acquire/release; FEAT_LSE2): <https://developer.arm.com/documentation/ddi0487/latest>
