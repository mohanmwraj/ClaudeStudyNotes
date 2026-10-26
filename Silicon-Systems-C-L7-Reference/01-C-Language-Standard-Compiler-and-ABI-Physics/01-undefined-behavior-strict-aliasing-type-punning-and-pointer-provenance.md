# 01 · Undefined Behavior, Strict Aliasing, Type Punning, and Pointer Provenance

> **Folder:** `01-C-Language-Standard-Compiler-and-ABI-Physics/` · **File 1 of 3**
> **Anchors:**
> - ISO/IEC 9899:2011 / 9899:2018 / 9899:2024 (drafts N1570 / N2176 / N3220): §3.4 behavior taxonomy, §5.1.2.3 abstract machine, §5.1.2.4 data races, §6.2.4 lifetimes, §6.3.2.3 pointer conversions, §6.5p6–7 effective type and aliasing, §6.5.6 pointer arithmetic, §6.5.7 shifts, §6.5.8 relational pointer comparison, §6.7.3.1 `restrict`, §6.8.5p6 forward progress, §7.24.1 string-function argument validity.
> - ISO/IEC TS 6010, the PNVI-ae-udi provenance model (⚠ verify publication status for your citation).
> - LLVM Language Reference: `poison`, `undef`, `nsw`, `inbounds`, `mustprogress`, `null_pointer_is_valid`.
> - GCC manual: `-fstrict-aliasing`, `-fdelete-null-pointer-checks`, `-fisolate-erroneous-paths-*`, `-fwrapv`.
> - ARMv7-M ARM (DDI 0403) §A3.2 alignment support; ARMv8-A ARM (DDI 0487) alignment of Device memory.
> - Lattner, *What Every C Programmer Should Know About Undefined Behavior* (2011); Regehr, *A Guide to Undefined Behavior in C and C++* (2010); Wang et al., *Towards Optimization-Safe Systems* (SOSP 2013, the STACK checker); Memarian et al., *Exploring C Semantics and Pointer Provenance* (POPL 2019); CVE-2009-1897.
>
> **Verification:** every listing marked *Codegen (verified)* was compiled with Clang 21.1.0 on 2026-10-26 (see the [README](../README.md#verification-method--read-this-before-trusting-a-listing)). GCC-specific statements are marked ⚠ verify.

---

## 0. The thesis in one paragraph

The compiler does not translate your C into ARM instructions. It translates the **abstract machine's semantics** into the cheapest instruction sequence that no *well-defined* program could tell apart from that machine. Undefined behavior (UB) does not mean "the hardware does whatever the hardware does". It means **the optimizer may assume this never happens**. That assumption works like a theorem: it propagates forward and backward through the control-flow graph. It lets the compiler:

- delete checks,
- fuse loads into instructions that fault on your silicon,
- erase busy-wait loops,
- hoist a load above the store you thought it depended on.

Every result in this file comes from a real compile. Each one is a production failure mode we have seen on Cortex-M, Cortex-A, or x86-64 fleets.

---

## 1. First-Principles Compiler Mechanics

### 1.1 The abstract machine and what is actually "observable" (§5.1.2.3)

C semantics are defined on an abstract machine. A conforming implementation only has to preserve the program's **observable behavior**:

1. Accesses to `volatile` objects, performed strictly according to the abstract machine's rules.
2. The data written to files, as of program termination.
3. Input/output dynamics of interactive devices.

Everything else can be fused, reordered, duplicated or deleted. That includes stores to ordinary globals, loads from ordinary memory, the order of non-volatile memory operations, and whether a loop runs at all. This freedom is called the **as-if rule**. For firmware, the consequences are immediate:

| What you wrote | What the abstract machine guarantees | What silicon sees at `-O2` |
|---|---|---|
| `GPIO->ODR = 1; GPIO->ODR = 0;` (non-`volatile` struct) | Nothing; the first store is dead | One store, or none |
| `while (!dma_done) {}` on a plain global | Nothing; a data race is UB, and a side-effect-free loop may be assumed to terminate | Loop **deleted** (§1.7, verified) |
| `*(uint32_t *)0` to read the initial MSP | UB (null dereference) | Load **deleted**; garbage returned (§1.8, verified) |
| `x + 1 > x` | Always true for `int` (overflow is UB) | `mov w0, #1` (§1.5, verified) |

### 1.2 The behavior taxonomy (§3.4, §4)

| Class | Definition | Firmware example | Can the optimizer exploit it? |
|---|---|---|---|
| **Implementation-defined** (§3.4.1) | Unspecified behavior that the implementation must document | `char` signedness; right shift of a negative `int`; integer → pointer conversion (§6.3.2.3p5); bit-field allocation order | No: it must be consistent and documented |
| **Unspecified** (§3.4.4) | Two or more possibilities, no documentation required | Evaluation order of `f() + g()`; values of padding bytes | Only to pick any allowed option, possibly a different one each time |
| **Undefined** (§3.4.3) | "No requirements" | Signed overflow, out-of-bounds pointers, misaligned pointer conversion, aliasing violations, data races, uninitialized `register`-able reads, `unreachable()` reached | **Yes:** it is treated as an assumption that never fails |
| **Locale-specific** (§3.4.2) | Depends on locale | `isalpha()` on bytes above 0x7F | No |

§4p2 adds the rule people forget: violating a "shall" outside a *constraint* is UB, **and so is any behavior the standard simply does not define**. You can't read your way out of UB by noting that nothing explicitly forbids something.

### 1.3 Sequencing: from "sequence points" to *sequenced-before*

C11 replaced the C89/C99 sequence-point wording with a relation: *sequenced before*, *unsequenced*, and *indeterminately sequenced* (§5.1.2.3p3). §6.5p2 says that two **unsequenced** side effects on the same scalar, or a side effect unsequenced with a value computation of the same scalar, is UB:

```c
i = i++ + 1;         /* UB: two unsequenced writes to i            */
buf[i] = i++;        /* UB: write of i unsequenced with read of i  */
f(x++, x);           /* UB: argument evaluations are unsequenced   */
```

**The firmware version of this bug is about `volatile`, and it is not UB but *unspecified*.** Many peripherals clear a status flag through a *read sequence*. A classic example is "read SR, then read DR" to clear an overrun flag. If you write the two reads in **one** expression:

```c
uint32_t junk = USART1->SR + USART1->DR;   /* order of the two volatile reads is UNSPECIFIED */
```

then the compiler may read DR first. The sequence must be two full expressions, because each full expression ends in a sequence point:

```c
(void)USART1->SR;   /* full expression 1 */
(void)USART1->DR;   /* full expression 2: guaranteed after the SR read */
```

### 1.4 How optimizers weaponize UB: the IR view

The front end lowers C into an IR that encodes UB as **facts**:

| C rule | LLVM IR encoding | GCC mechanism | Consequence |
|---|---|---|---|
| Signed overflow is UB (§6.5p5) | `add nsw` / `mul nsw` → result is `poison` on overflow | Value-range propagation; `-fstrict-overflow` semantics | `x + 1 > x` ⇒ `true`; induction variables widened to 64-bit without wrap checks |
| Pointer arithmetic beyond the array is UB (§6.5.6p8) | `getelementptr inbounds` → `poison` if out of bounds | Pointer-overflow assumptions | `p + n < p` ⇒ `false` |
| Null dereference is UB | `load`/`store` through `null` in address space 0 is UB, unless the function has `null_pointer_is_valid` | `-fdelete-null-pointer-checks`, `-fisolate-erroneous-paths-dereference` | Later null checks deleted; GCC may replace the access with a trap (⚠ verify per release) |
| Loops without side effects may be assumed to terminate (§6.8.5p6) | `mustprogress` on functions and loops | Finite-loop assumptions | Side-effect-free loops deleted |
| Uninitialized automatic read is UB (§6.3.2.1p2) | `undef`, which may take a different value at each use, or `poison` | Uninitialized-variable propagation | The compiler picks whatever value makes the code fastest |
| `unreachable()` / `__builtin_unreachable()` | `unreachable` terminator | Same | Range checks dominating it are deleted |

Two properties make these facts dangerous:

1. **They compose.** A fact from one UB rule removes a check. That changes the control flow, which exposes a second rule's opportunity.
2. **They time-travel.** If every path through a block ends in UB, the compiler may treat the *whole* block as unreachable, including the side effects that come *before* the UB on that path.

### 1.5 Signed integer overflow 🔥

Source:

```c
#include <stdbool.h>
#include <stdckdint.h>
int  always_true(int x)        { return x + 1 > x; }
bool unsigned_cmp(unsigned x)  { return x + 1 > x; }
bool naive_ovf_check(int a, int b) { return a + b < a; }
bool c23_ovf_check(int *r, int a, int b) { return ckd_add(r, a, b); }
int  mul_div_signed(int i)          { return (i * 2) / 2; }
unsigned mul_div_unsigned(unsigned i) { return (i * 2u) / 2u; }
```

**Codegen (verified — Clang 21.1.0, `-O2 -std=c23`, `aarch64-linux-gnu`):**

```asm
always_true:
	mov	w0, #1
	ret
unsigned_cmp:
	cmn	w0, #1
	cset	w0, ne
	ret
naive_ovf_check:
	lsr	w0, w1, #31
	ret
c23_ovf_check:
	adds	w10, w1, w2
	mov	x9, x0
	cset	w8, vs
	str	w10, [x9]
	mov	w0, w8
	ret
mul_div_signed:
	ret
mul_div_unsigned:
	and	w0, w0, #0x7fffffff
	ret
```

Read each one as a proof:

- **`always_true`**: overflow is assumed impossible, so `x + 1 > x` is a tautology. The unsigned version has to keep a real comparison (`cmn w0, #1` tests `x == UINT_MAX`) because unsigned arithmetic wraps by definition (§6.2.5p9).
- **`naive_ovf_check`**: the programmer meant "did `a + b` overflow?". The compiler reasons that `a + b < a` ⟺ `b < 0` (exact in mathematical integers), and emits **`lsr w0, w1, #31`**: the sign bit of `b`. The overflow check has become a sign test of one argument.
- **`c23_ovf_check`**: C23's `<stdckdint.h>` `ckd_add` returns `true` on overflow and always stores the wrapped result. It lowers to the hardware's real overflow flag: `adds` sets V, and `cset w8, vs` reads it. That costs one instruction. There is no performance excuse for hand-rolled checks.
- **`mul_div_signed`**: `(i*2)/2 == i` holds in ℤ, so the function is the identity (`ret`). The unsigned version must model wrap-around, so it masks off the bit lost by the doubling.

With `-fwrapv` (overflow defined as two's-complement wrap), the first line changes. **Codegen (verified, same target, `-fwrapv`):**

```asm
always_true:
	mov	w8, #2147483647
	cmp	w0, w8
	cset	w0, ne
	ret
```

C23 mandates two's-complement *representation* (§6.2.6.2) but signed overflow is **still undefined**. Representation and arithmetic semantics are separate questions. Don't let a reviewer tell you that "C23 fixed overflow".

**Pre-C23 portable equivalents:**

```c
/* GCC >= 5, Clang >= 3.8: type-generic, lowers to the flag-setting instruction. */
bool add_ovf(int a, int b, int *r) { return __builtin_add_overflow(a, b, r); }

/* Strictly conforming C99/C11 with no builtins: test before you add. */
#include <limits.h>
bool add_would_overflow(int a, int b)
{
    return (b > 0) ? (a > INT_MAX - b) : (a < INT_MIN - b);
}
```

### 1.6 Shifts: three ISAs, three answers, hence UB (§6.5.7)

§6.5.7p3: if the shift count is negative, or **≥ the width of the promoted left operand**, the behavior is undefined. §6.5.7p4: `E1 << E2` with signed `E1` is defined only if `E1 ≥ 0` and `E1 × 2^E2` is representable. So `1 << 31` on 32-bit `int` is UB in C11, C17 **and C23**. Write `1u << 31`.

The reason is physical. With a *register* shift count of 32 applied to a 32-bit value:

| ISA | Instruction | Count semantics | `x << 32` result |
|---|---|---|---|
| AArch64 | `LSLV Wd, Wn, Wm` | count = `Wm mod 32` | `x` |
| AArch32 / Thumb-2 | `LSL Rd, Rn, Rs` | count = `Rs[7:0]`; counts ≥ 32 give 0 | `0` |
| x86-64 | `SHL r32, cl` | count = `cl & 31` | `x` |

A language that wants one instruction per shift *must* leave the out-of-range case undefined. The optimizer then uses the gap. Source:

```c
#include <stdint.h>
uint32_t shl(uint32_t x, unsigned s) { return x << s; }
uint32_t shl_by_32(uint32_t x)       { return shl(x, 32u); }
```

**Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-linux-gnu`):**

```asm
shl:
	lsl	w0, w0, w1
	ret
shl_by_32:
	ret
```

After inlining, `x << 32` is `poison`, and the compiler returns *whatever is already in `w0`*, which here happens to be `x`. On Thumb-2 the hardware would have produced `0`. **The same source gives different answers on two cores of the same SoC.** MISRA Rule 12.2 and CERT INT34-C exist for exactly this.

### 1.7 Infinite loops and the forward-progress license (§6.8.5p6) 🔥⚡

C11 §6.8.5p6:

> An iteration statement whose controlling expression is not a constant expression, that performs no input/output operations, does not access volatile objects, and performs no synchronization or atomic operations in its body, controlling expression, or (in the case of a `for` statement) its *expression-3*, may be assumed by the implementation to terminate.

Source:

```c
unsigned collatz_steps_discarded(unsigned x) {
    while (x != 1u)
        x = (x & 1u) ? 3u * x + 1u : x / 2u;
    return 0u;
}
void spin_forever(void) { while (1) { } }
```

**Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-linux-gnu`):**

```asm
collatz_steps_discarded:
	mov	w0, wzr
	ret
spin_forever:
.LBB1_1:
	b	.LBB1_1
```

The Collatz loop has a non-constant condition and no side effects. Whether it terminates for every input is an open mathematical problem, yet the compiler is allowed to *assume* it does, and its result is unused. So it is gone. `while (1)` has a **constant** controlling expression, so C keeps it. (C++ was stricter: until C++26's P2809, even `while(1){}` fell under the forward-progress rule.)

Now the embedded catastrophe. A flag is set by an ISR or by another core, and the main loop waits for it:

```c
int ready;
int payload;
int consume(void) {
    while (!ready) { }
    return payload;
}
```

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7):**

```asm
consume:
	movw	r0, :lower16:payload
	movt	r0, :upper16:payload
	ldr	r0, [r0]
	bx	lr
ready:
	.long	0
payload:
	.long	0
```

**The wait loop is deleted entirely.** Two independent rules license this:

1. **§5.1.2.4 data race.** `ready` is written by another thread of execution (an ISR counts) without atomics. That is a data race, so the program is undefined. The compiler may therefore assume no one else writes `ready`. Then the loop either never runs or never ends.
2. **§6.8.5p6.** The loop has a non-constant condition and no volatile, atomic or I/O operations, so it may be assumed to terminate. Combined with rule 1, "terminates" means "`ready` was already non-zero". The loop body is never needed.

On AArch64 the same source compiles to the same three-instruction function. Many engineers expect `b .` (a hoisted load followed by an infinite loop). **Deletion is the more aggressive, and equally legal, outcome.** Making `ready` `volatile` defeats rule 2 and the load hoisting, but **not** the cross-core ordering problem. The correct fix is `_Atomic` with acquire/release, covered in depth in [Folder 03](../README.md#layout-and-build-status).

### 1.8 Null pointers: deleted checks, address 0, and `memcpy` 🔥⚡

#### 1.8.1 The CVE-2009-1897 pattern

The Linux `tun` driver (2.6.30) dereferenced `tun->sk` *before* checking `tun` for NULL. GCC deleted the check. An attacker who mapped page 0 turned the deleted check into a kernel exploit. The pattern:

```c
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
struct tun_struct { int *sk; unsigned flags; };
int tun_chr_poll(struct tun_struct *tun) {
    int *sk = tun->sk;          /* dereference happens first ...        */
    if (!tun)                   /* ... so this check is "provably" dead */
        return -1;
    return *sk;
}
void copy_then_check(char *d, const char *s, size_t n) {
    memcpy(d, s, n);
    if (s == NULL)
        abort();
}
```

**Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-linux-gnu`):**

```asm
tun_chr_poll:
	ldr	x8, [x0]
	ldr	w0, [x8]
	ret
copy_then_check:
	stp	x29, x30, [sp, #-32]!
	str	x19, [sp, #16]
	mov	x29, sp
	mov	x19, x1
	bl	memcpy
	cbz	x19, .LBB1_2
	ldr	x19, [sp, #16]
	ldp	x29, x30, [sp], #32
	ret
.LBB1_2:
	bl	abort
```

**Codegen (verified — same, plus `-fno-delete-null-pointer-checks`):**

```asm
tun_chr_poll:
	cbz	x0, .LBB0_2
	ldr	x8, [x0]
	ldr	w0, [x8]
	ret
.LBB0_2:
	mov	w0, #-1
	ret
```

Observations:

- `tun_chr_poll` loses its check (`cbz` is gone) at plain `-O2`. The Linux kernel has built with `-fno-delete-null-pointer-checks` since 2009 for exactly this reason. LLVM implements the flag as the function attribute `null_pointer_is_valid`.
- `copy_then_check`: §7.24.1p2 says pointer arguments to string functions must be valid *even when `n == 0`*, so `memcpy(d, NULL, 0)` is UB in C11–C23. GCC, together with glibc's `__nonnull` attributes, has historically used this to delete the following `s == NULL` check (⚠ verify on your GCC/glibc pair). **Clang 21 kept the check** in this experiment. C2y (paper N3322) makes zero-length operations on null pointers well-defined. Until your whole toolchain implements that, write `if (n != 0u) memcpy(...)`.

#### 1.8.2 Address 0 is real memory on a Cortex-M 🧊

On ARMv6-M, ARMv7-M and ARMv8-M, the reset vector table sits at address 0x0000_0000 (or wherever `VTOR` points). Word 0 is the **initial MSP**, and word 1 is the reset vector. Bootloaders legitimately read it. In C, a null-pointer dereference is UB *regardless of what lives at address 0*:

```c
#include <stdint.h>
uint32_t read_initial_msp_volatile(void) { return *(volatile const uint32_t *)0u; }
uint32_t read_initial_msp_plain(void)    { return *(const uint32_t *)0u; }
```

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7; Cortex-M0+ is identical):**

```text
addr0.c:3:51: warning: indirection of non-volatile null pointer will be deleted, not trap [-Wnull-dereference]
addr0.c:3:51: note: consider using __builtin_trap() or qualifying pointer with 'volatile'
```

```asm
read_initial_msp_volatile:
	movs	r0, #0
	ldr	r0, [r0]
	bx	lr
read_initial_msp_plain:
	bx	lr
```

The plain version is reduced to `bx lr`: the load is deleted and the function returns whatever was in `r0`. The `volatile` version survives in Clang. GCC's `-fisolate-erroneous-paths-dereference` (on by default at `-O2`) may replace a provable null dereference with a **trap instruction**. On Thumb that is an undefined instruction, which raises a HardFault/UsageFault in your bootloader (⚠ verify which GCC releases trap on the `volatile` form).

**Production rule:** never spell address 0 as a null pointer constant. Use one of these:

1. A linker-script symbol: `extern const uint32_t __vector_table[];` then read `__vector_table[0]`. The object has a name, provenance and no null-pointer semantics.
2. `SCB->VTOR`: read the table base from hardware, then index it.
3. If you must, compile the translation unit with `-fno-delete-null-pointer-checks`, and document it as a MISRA Rule 1.3 deviation.

### 1.9 Uninitialized reads (§6.3.2.1p2)

```c
int maybe_init(int c) {
    int v;
    if (c)
        v = 42;
    return v;
}
```

**Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-linux-gnu`):**

```asm
maybe_init:
	mov	w0, #42
	ret
```

On the `c == 0` path `v` is `undef`, and the optimizer may choose `undef = 42` to merge both paths. The branch disappears, and so does any chance of noticing the bug in testing: the function "always works". **With `-ftrivial-auto-var-init=zero` (verified, same target):**

```asm
maybe_init:
	mov	w8, #42
	cmp	w0, #0
	csel	w0, wzr, w8, eq
	ret
```

Linux enables this hardening through `CONFIG_INIT_STACK_ALL_ZERO`. Use `=pattern` in debug builds (Clang fills with `0xAA` bytes) so that uninitialized values become loud, and use `=zero` in production, where a deterministic zero is the safe failure. MISRA Rule 9.1 and CERT EXP33-C cover this.

### 1.10 `unreachable()` is a promise, not a comment

C23 adds `unreachable()` to `<stddef.h>`. GCC and Clang have offered `__builtin_unreachable()` for years.

```c
#include <stddef.h>
int lut_dispatch(int k) {
    switch (k) {
    case 0: return 10;
    case 1: return 21;
    case 2: return 33;
    case 3: return 47;
    default: unreachable();
    }
}
```

**Codegen (verified — Clang 21.1.0, `-O2 -std=c23`, `aarch64-linux-gnu`):**

```asm
lut_dispatch:
	adrp	x8, .Lswitch.table.lut_dispatch
	add	x8, x8, :lo12:.Lswitch.table.lut_dispatch
	ldr	w0, [x8, w0, uxtw #2]
	ret
.Lswitch.table.lut_dispatch:
	.word	10
	.word	21
	.word	33
	.word	47
```

The bounds check is gone. `k = 4` reads past the table. `k = -1` reads at offset `0xFFFFFFFF × 4`, because of the `uxtw` zero-extension. When `unreachable()` sits at the *end* of a function, the compiler may omit the return entirely. Execution then **falls through into whatever function the linker placed next**. §6.1 shows the crash-dump signature. Production policy: use `unreachable()` only through a macro that is `__builtin_trap()` in every build except a measured, profiled hot path.

---

## 2. Strict Aliasing: Effective Type, TBAA, and the Hidden Alignment Bomb

### 2.1 The rules (§6.5p6–7)

**Effective type** (§6.5p6) works as follows:

- For an object with a declared type, the effective type is the declared type.
- For storage with no declared type (`malloc`), a store through a non-character lvalue sets the effective type for later reads.
- `memcpy`/`memmove` (or a character-array copy) transfers the source's effective type.

**Aliasing** (§6.5p7): an object shall have its stored value accessed only by an lvalue of one of these types:

1. a type compatible with the effective type;
2. a qualified version of that type;
3. the signed/unsigned type corresponding to the effective type, or to a qualified version of it;
4. an aggregate or union type that includes one of the above among its members (recursively);
5. **a character type**.

Every other access is UB. The rule is **asymmetric**. A `char`/`unsigned char` lvalue may read any object. An object *declared* as `uint8_t rx[64]` may **not** be read through a `struct hdr *`, because the effective type of those bytes is `uint8_t`, and `struct hdr` is not in that type's list.

> 🧊 `uint8_t` is `unsigned char` on every GCC/Clang target, but the standard doesn't guarantee it: an implementation may define `uint8_t` as a distinct extended integer type. Code that relies on "`uint8_t*` can alias anything" is relying on an implementation property. Use `unsigned char *` when the aliasing permission is the point.

This also hits custom allocators. A fixed-block pool carved from `static uint8_t pool_storage[N]` hands out storage whose declared type is `uint8_t`. Storing a `struct msg` into it is technically outside §6.5p7. Production allocators handle this in one of three ways:

- build the allocator translation unit with `-fno-strict-aliasing`;
- back the pool with storage that has no declared type visible to the compiler (a linker-section symbol);
- use a `union` with the payload types.

See Folder 05.

### 2.2 Why the optimizer cares: type-based alias analysis (TBAA)

```c
int store_int_store_float(int *i, float *f) {
    *i = 1;
    *f = 0.0f;
    return *i;
}
```

**Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-linux-gnu`):**

```asm
store_int_store_float:
	mov	w8, #1
	str	wzr, [x1]
	str	w8, [x0]
	mov	w0, #1
	ret
```

**Codegen (verified — same, `-fno-strict-aliasing`):**

```asm
store_int_store_float:
	mov	w8, #1
	str	w8, [x0]
	str	wzr, [x1]
	ldr	w0, [x0]
	ret
```

With strict aliasing on, the compiler concludes that an `int*` and a `float*` never alias. It **reorders the stores** (the `float` store is issued first) and **forwards the constant** (`mov w0, #1`) instead of reloading. If a caller passes the same address for both pointers, the result is 1 under strict aliasing and 0 without it. That is a semantic difference produced purely by a flag. The Cortex-M7 build makes the same choices:

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7):**

```asm
store_int_store_float:
	movs	r2, #1
	str	r2, [r0]
	movs	r0, #1
	movs	r2, #0
	str	r2, [r1]
	bx	lr
```

### 2.3 The alignment bomb that rides along with the cast 🔥⚡

The aliasing violation usually travels with a second UB. §6.3.2.3p7 says that converting a pointer to a pointer to a type with stricter alignment is undefined **at the conversion itself**, if the result is misaligned. You don't even have to dereference it. Now look at what the compiler does with a "harmless" header overlay on a byte buffer:

```c
#include <stdint.h>
#include <string.h>
struct wire_hdr { uint32_t magic; uint32_t len; };
uint32_t hdr_sum_cast(const uint8_t *rx)   {
    const struct wire_hdr *h = (const struct wire_hdr *)(const void *)rx;
    return h->magic + h->len;
}
uint32_t hdr_sum_memcpy(const uint8_t *rx) {
    struct wire_hdr h;
    memcpy(&h, rx, sizeof h);
    return h.magic + h.len;
}
```

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7, ARMv7E-M):**

```asm
hdr_sum_cast:
	ldrd	r0, r1, [r0]
	add	r0, r1
	bx	lr
hdr_sum_memcpy:
	ldr	r1, [r0]
	ldr	r0, [r0, #4]
	add	r0, r1
	bx	lr
```

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M0+, ARMv6-M):**

```asm
hdr_sum_cast:
	ldr	r1, [r0]
	ldr	r0, [r0, #4]
	adds	r0, r0, r1
	bx	lr
hdr_sum_memcpy:
	ldrb	r1, [r0]
	ldrb	r2, [r0, #1]
	lsls	r2, r2, #8
	adds	r1, r2, r1
	ldrb	r2, [r0, #2]
	lsls	r2, r2, #16
	ldrb	r3, [r0, #3]
	lsls	r3, r3, #24
	adds	r2, r3, r2
	adds	r1, r2, r1
	ldrb	r2, [r0, #4]
	ldrb	r3, [r0, #5]
	lsls	r3, r3, #8
	adds	r2, r3, r2
	ldrb	r3, [r0, #6]
	lsls	r3, r3, #16
	ldrb	r0, [r0, #7]
	lsls	r0, r0, #24
	adds	r0, r0, r3
	adds	r0, r0, r2
	adds	r0, r0, r1
	bx	lr
```

**Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-linux-gnu`):**

```asm
hdr_sum_cast:
	ldp	w8, w9, [x0]
	add	w0, w9, w8
	ret
hdr_sum_memcpy:
	ldp	w8, w9, [x0]
	add	w0, w9, w8
	ret
```

This is the whole interview in three listings:

- **Cortex-M7, cast.** The cast promised 4-byte alignment, so the compiler fused the two loads into **`LDRD`**. On ARMv7-M, `LDRD`/`STRD`, `LDM`/`STM`, `PUSH`/`POP` and `LDREX`/`STREX` **always** fault on a misaligned address. Only single `LDR`/`STR`/`LDRH`/`STRH` tolerate misalignment, and only while `CCR.UNALIGN_TRP = 0`. If the DMA put the frame at `rx + 2` (common after a 2-byte Ethernet pad), you get a UsageFault with `CFSR.UFSR.UNALIGNED` (CFSR bit 24) set. It happens only in the build where the optimizer saw both fields.
- **Cortex-M7, `memcpy`.** `memcpy` makes no alignment promise. The compiler uses two single `LDR`s, which v7-M handles unaligned in hardware. There is no call and no byte loop.
- **Cortex-M0+, cast.** ARMv6-M supports **no** unaligned accesses at all. Even the plain `LDR` raises a HardFault (v6-M has no UsageFault; everything escalates).
- **Cortex-M0+, `memcpy`.** The compiler knows the ISA can't do unaligned word loads, so it emits byte loads and shifts. That is correct by construction.
- **AArch64.** Both versions emit `LDP`. On **Normal** memory with `SCTLR_ELx.A = 0`, unaligned `LDP` works. On **Device** memory (MMIO, or a DMA buffer mapped Device-nGnRE), any unaligned access raises an **Alignment fault** (ESR `EC = 0x25`, `DFSC = 0x21`). Exclusive and acquire/release accesses must be aligned on any memory type. (FEAT_LSE2 relaxes some single-copy-atomic cases; ⚠ verify for your core.)

**Summary table: what a misaligned 32-bit access does**

| Core / memory | `LDR`/`STR` word | `LDRD`/`LDM`/`PUSH` | Exclusive / acquire-release |
|---|---|---|---|
| Cortex-M0/M0+/M23 (v6-M, v8-M Baseline) | HardFault | HardFault | n/a (no exclusives on v6-M) |
| Cortex-M3/M4/M7/M33 (v7-M, v8-M Mainline), `UNALIGN_TRP=0` | OK (extra bus cycles) | UsageFault `UNALIGNED` | UsageFault `UNALIGNED` |
| Same, `UNALIGN_TRP=1` | UsageFault `UNALIGNED` | UsageFault `UNALIGNED` | UsageFault `UNALIGNED` |
| Cortex-A (AArch64), Normal memory, `SCTLR.A=0` | OK | OK (`LDP`) | Alignment fault |
| Cortex-A (AArch64), Device memory | Alignment fault | Alignment fault | Alignment fault |
| x86-64 | OK | OK | OK for `lock` ops, but a split-lock across a cache line triggers `#AC` or a bus lock, which recent kernels can treat as fatal (⚠ verify `split_lock_detect`) |

### 2.4 Type punning: `memcpy` vs `union` vs pointer cast

```c
#include <stdint.h>
#include <string.h>
float u2f_memcpy(uint32_t u) { float f; memcpy(&f, &u, sizeof f); return f; }
float u2f_union(uint32_t u)  { union { uint32_t u; float f; } x = { .u = u }; return x.f; }
```

**Codegen (verified — Clang 21.1.0, `-O2`), per target:**

```asm
; aarch64-linux-gnu
u2f_memcpy:
	fmov	s0, w0
	ret
u2f_union:
	fmov	s0, w0
	ret
```

```asm
# x86_64-linux-gnu
u2f_memcpy:
	movd	%edi, %xmm0
	retq
u2f_union:
	movd	%edi, %xmm0
	retq
```

```asm
@ Cortex-M7, hard-float (value arrives in r0, returns in s0)
u2f_memcpy:
	vmov	s0, r0
	bx	lr
u2f_union:
	vmov	s0, r0
	bx	lr
```

```asm
@ Cortex-M0+, soft-float (the float is returned in r0: the pun is free)
u2f_memcpy:
	bx	lr
u2f_union:
	bx	lr
```

```asm
# riscv64-linux-gnu (lp64d)
u2f_memcpy:
	fmv.w.x	fa0, a0
	ret
u2f_union:
	fmv.w.x	fa0, a0
	ret
```

`memcpy` of a constant small size is a compiler intrinsic: no call, no loop, just the one register-file move the ISA needs. The "`memcpy` is slow" objection is a 1990s compiler artifact.

| Technique | C11/C17/C23 | C++ | Notes |
|---|---|---|---|
| `memcpy` into an object of the target type | ✅ Defined | ✅ Defined | Universal. MISRA Rule 21.15 (pointer arguments to `memcpy` should point to compatible types) still flags `float` ← `uint32_t`, so keep **one** audited helper with a documented deviation |
| Read a `union` member other than the last one written | ✅ Defined: bytes are reinterpreted (C11 §6.5.2.3, footnote 95) | ❌ UB (only the active member may be read) | GCC documents support only when the access goes through the union type; `*(&u.f)` via a member pointer is not covered. MISRA Rule 19.2 (advisory) discourages `union` |
| `*(float *)&u` | ❌ UB (§6.5p7) | ❌ UB | Works until the optimizer reorders around it |
| `__attribute__((may_alias))` typedef | GNU extension | GNU extension | `typedef uint32_t __attribute__((may_alias)) u32_alias;` exempts accesses from TBAA |
| C++20 `std::bit_cast` | n/a | ✅ | The C++ answer, and `constexpr`-friendly |

The GCC manual example to memorize, because it compiles cleanly and is wrong:

```c
union a_union { int i; double d; };
int f(void) {
    union a_union t;
    int *ip;
    t.d = 3.0;
    ip = &t.i;       /* pointer to member: the access is no longer "through the union" */
    return *ip;      /* GCC: might not work (TBAA sees an int load vs a double store) */
}
```

### 2.5 `restrict`: aliasing information you *give* the compiler (§6.7.3.1)

```c
#include <stddef.h>
void axpy(float *y, const float *x, float a, size_t n) {
    for (size_t i = 0; i < n; i++)
        y[i] += a * x[i];
}
void axpy_restrict(float *restrict y, const float *restrict x, float a, size_t n) {
    for (size_t i = 0; i < n; i++)
        y[i] += a * x[i];
}
```

**Codegen (verified — Clang 21.1.0, `-O3`, `aarch64-linux-gnu`):**

```asm
axpy:
	cbz	x2, .LBB0_7
	cmp	x2, #8
	b.lo	.LBB0_4
	lsl	x8, x2, #2
	add	x9, x1, x8
	cmp	x0, x9
	b.hs	.LBB0_8
	add	x8, x0, x8
	cmp	x1, x8
	b.hs	.LBB0_8
.LBB0_4:
	mov	x8, xzr
.LBB0_5:
	lsl	x10, x8, #2
	sub	x8, x2, x8
	add	x9, x0, x10
	add	x10, x1, x10
.LBB0_6:
	ldr	s1, [x10], #4
	ldr	s2, [x9]
	subs	x8, x8, #1
	fmadd	s1, s0, s1, s2
	str	s1, [x9], #4
	b.ne	.LBB0_6
.LBB0_7:
	ret
.LBB0_8:
	and	x8, x2, #0xfffffffffffffff8
	add	x9, x0, #16
	add	x10, x1, #16
	mov	x11, x8
.LBB0_9:
	ldp	q1, q4, [x9, #-16]
	subs	x11, x11, #8
	ldp	q2, q3, [x10, #-16]
	add	x10, x10, #32
	fmla	v1.4s, v2.4s, v0.s[0]
	fmla	v4.4s, v3.4s, v0.s[0]
	stp	q1, q4, [x9, #-16]
	add	x9, x9, #32
	b.ne	.LBB0_9
	cmp	x2, x8
	b.eq	.LBB0_7
	b	.LBB0_5
axpy_restrict:
	cbz	x2, .LBB1_8
	cmp	x2, #8
	b.hs	.LBB1_3
	mov	x8, xzr
	b	.LBB1_6
.LBB1_3:
	and	x8, x2, #0xfffffffffffffff8
	add	x9, x0, #16
	add	x10, x1, #16
	mov	x11, x8
.LBB1_4:
	ldp	q1, q4, [x9, #-16]
	subs	x11, x11, #8
	ldp	q2, q3, [x10, #-16]
	add	x10, x10, #32
	fmla	v1.4s, v2.4s, v0.s[0]
	fmla	v4.4s, v3.4s, v0.s[0]
	stp	q1, q4, [x9, #-16]
	add	x9, x9, #32
	b.ne	.LBB1_4
	cmp	x2, x8
	b.eq	.LBB1_8
.LBB1_6:
	lsl	x10, x8, #2
	sub	x8, x2, x8
	add	x9, x0, x10
	add	x10, x1, x10
.LBB1_7:
	ldr	s1, [x10], #4
	ldr	s2, [x9]
	subs	x8, x8, #1
	fmadd	s1, s0, s1, s2
	str	s1, [x9], #4
	b.ne	.LBB1_7
.LBB1_8:
	ret
```

Without `restrict`, the vectorizer emits a **runtime overlap check** (the four `cmp`/`b.hs` instructions after `cmp x2, #8`). It vectorizes only when `y` and `x` don't overlap, and otherwise falls back to the scalar loop. With `restrict`, the check is gone. On a DSP hot loop that check costs little. The danger is the reverse case: **a `restrict` lie is silent corruption**. An in-place DMA post-processing step that calls `axpy_restrict(buf, buf, …)` with overlapping halves will vectorize across the overlap and read values that were already updated.

### 2.6 The `-fno-strict-aliasing` debate

The Linux kernel builds everything with `-fno-strict-aliasing`. It reinterprets memory constantly (network headers, `container_of`, page-table entries), and Linus Torvalds has long argued that the optimizations aren't worth the bugs. For firmware, the L7 stance is a policy, not a flag:

1. **Keep strict aliasing on** for leaf compute code (DSP, control loops, crypto) where TBAA enables vectorization and scheduling.
2. **Ban object-pointer casts** in application code. Enforce this with MISRA Rule 11.3, Clang `-Wcast-align`, GCC `-Wcast-align=strict` (warns even on targets that tolerate misalignment), and code review.
3. **Quarantine reinterpretation** in a handful of audited helpers: `load_be32`, `f32_from_bits`, and the allocator's TU, which may get `-fno-strict-aliasing` on its own.
4. **Prove it** with UBSan's `-fsanitize=alignment` on the host build, plus a test that parses at every alignment offset 0–7.

---

## 3. Pointer Provenance: Pointers Are Not Integers

### 3.1 The model

Since C89 the standard has spoken of pointers "to an object", "one past the end of an array object", and pointers that become *indeterminate* when their object's lifetime ends (§6.2.4p2). Compilers implement this as **provenance**: every pointer value is conceptually the pair *(address, the allocation it was derived from)*.

- Two pointers with equal addresses but different provenance are **not interchangeable** for access.
- Arithmetic that leaves the allocation (beyond one-past-the-end) is UB even if you never dereference the result (§6.5.6p8).
- Relational comparison (`<`, `<=`, `>`, `>=`) of pointers into different objects is UB (§6.5.8p5). Equality comparison is defined.
- Subtraction of pointers into different objects is UB (§6.5.6p9).

ISO/IEC TS 6010 makes this precise as **PNVI-ae-udi**: "provenance not via integers, address-exposed, user-disambiguation". It works like this:

- Integers don't carry provenance.
- Casting a pointer to an integer **exposes** its allocation.
- Casting an integer back to a pointer picks up the provenance of an exposed allocation at that address, if there is one. "User disambiguation" resolves the one-past-the-end versus next-object ambiguity by how the pointer is *used*.

### 3.2 The experiment: same source, two targets, two answers 🧊

```c
#include <string.h>
int x = 1, y = 2;
int provenance_demo(void) {
    int *p = &x + 1;            /* one-past-the-end of x: valid to form, invalid to deref */
    int *q = &y;
    if (memcmp(&p, &q, sizeof p) == 0) {   /* same bits ... */
        *p = 11;                /* UB: p's provenance is x, not y */
        return *q;              /* compiler: "p cannot alias y" -> may return the old y */
    }
    return -1;
}
```

**Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-linux-gnu`):**

```asm
provenance_demo:
	adrp	x8, :got:x
	adrp	x9, :got:y
	ldr	x8, [x8, :got_lo12:x]
	ldr	x9, [x9, :got_lo12:y]
	add	x10, x8, #4
	cmp	x10, x9
	b.ne	.LBB0_2
	ldr	w0, [x9]
	mov	w10, #11
	str	w10, [x8, #4]
	ret
.LBB0_2:
	mov	w0, #-1
	ret
x:
	.word	1
y:
	.word	2
```

**Codegen (verified — Clang 21.1.0, `-O2`, `x86_64-linux-gnu`):**

```asm
provenance_demo:
	movq	x@GOTPCREL(%rip), %rcx
	leaq	4(%rcx), %rdx
	movl	$-1, %eax
	cmpq	y@GOTPCREL(%rip), %rdx
	jne	.LBB0_2
	movl	$11, 4(%rcx)
	movq	y@GOTPCREL(%rip), %rax
	movl	(%rax), %eax
.LBB0_2:
	retq
```

Look at the AArch64 branch. **`ldr w0, [x9]` (read `*q`) is scheduled before `str w10, [x8, #4]` (write `*p`).** The compiler's alias analysis says a pointer derived from `x` can't modify `y`, so reordering is legal. When `&x + 1 == &y` (the globals are adjacent), the function returns **2** while memory holds **11**. On x86-64 the same compiler happened to keep program order. Natively on x86-64 Windows (verified run):

```text
&x+1 == &y ? yes
provenance_demo() returned 11; y now holds 11
```

**UB does not guarantee a wrong answer. It guarantees that you have no guarantee.** The outcome depends on the scheduler, the target, and the inlining context. That is why "I tested it and it works" proves nothing about UB. GCC folds the classic form of this example to the stale value (Memarian et al., POPL 2019; ⚠ verify with your release).

### 3.3 Where provenance bites firmware

1. **MMIO addresses from integers.** `#define UART0 ((uart_regs_t *)0x40011000u)` is implementation-defined (§6.3.2.3p5), not UB. Compilers treat an integer-to-pointer cast as pointing to *some* exposed or unknown storage, and they won't assume it misses your globals. MISRA Rule 11.4 (advisory) flags it, so keep **one** register-base header with a recorded deviation.

2. **Linker-script symbols.** `_sbss`, `_ebss`, `_sidata` are not C objects. They're addresses the linker invented. Declaring them as `extern uint32_t _sbss;` and then computing `&_ebss - &_sbss` subtracts pointers to *different objects* (§6.5.6p9), and walking `p < &_ebss` relationally compares them (§6.5.8p5). The robust idiom:
   ```c
   extern uint32_t __bss_start__[];   /* arrays of unknown bound: no size the optimizer can reason about */
   extern uint32_t __bss_end__[];
   /* compare and size as integers; derive the walk pointer from one symbol only */
   uintptr_t n = ((uintptr_t)__bss_end__ - (uintptr_t)__bss_start__) / sizeof(uint32_t);
   for (uintptr_t i = 0; i < n; i++) { __bss_start__[i] = 0u; }
   ```
   Folder 02 shows the complete `crt0` and the second trap: the compiler recognizes this loop as a `memset` call (`-ftree-loop-distribute-patterns` in GCC). That matters when `memset` isn't yet usable, or lives in RAM that hasn't been copied.

3. **Overflow checks on pointers:**
   ```c
   #include <stddef.h>
   #include <stdint.h>
   int ptr_wrap_check_ub(const char *p, size_t len) { return p + len < p; }
   int ptr_wrap_check_ok(const char *p, size_t len) { return (uintptr_t)p + len < (uintptr_t)p; }
   ```
   **Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-linux-gnu`):**
   ```text
   ptrovf.c:3:67: warning: pointer comparison always evaluates to false [-Wtautological-compare]
   ```
   ```asm
   ptr_wrap_check_ub:
   	mov	w0, wzr
   	ret
   ptr_wrap_check_ok:
   	cmn	x0, x1
   	cset	w0, hs
   	ret
   ```
   The pointer version is constant-false, because an in-bounds `p + len` can't wrap. The integer version is a real carry test (`cmn` + `cset hs`). Better still, bounds-check **lengths** against the buffer size *before* forming any pointer: `if (len > buf_len - off)`.

4. **`container_of`.** The Linux macro subtracts `offsetof` from a member pointer, stepping back to the enclosing object through `char *` arithmetic within the same allocation, which is defined. The C23 spelling with a type check:
   ```c
   #include <stddef.h>
   #define container_of(ptr, type, member)                                          \
       ((type *)(void *)((char *)(ptr) - offsetof(type, member)) +                  \
        0 * sizeof(struct { _Static_assert(                                         \
            __builtin_types_compatible_p(typeof(*(ptr)), typeof(((type *)0)->member)), \
            "container_of: pointer type mismatch"); int dummy; }))
   ```
   (`typeof` is standard in C23; `__builtin_types_compatible_p` is GNU. Folder 05 uses a simpler form in the intrusive-list blueprint.)

5. **Dangling pointers are *indeterminate*, not just "pointing at freed memory".** After `free(p)` or after the pointee's lifetime ends, the *value* of `p` is indeterminate (§6.2.4p2). Even `if (p == q)` is formally UB. This "pointer zap" semantics matters to lock-free algorithms that compare a stale pointer against a freshly allocated one (ABA, Folder 05).

6. **CHERI / Arm Morello: provenance becomes hardware.** On CHERI, a pointer is a 128-bit capability (address, bounds, permissions) plus a 1-bit validity tag in memory. `uintptr_t` must be capability-sized. Integer arithmetic that leaves the bounds clears the tag, and dereferencing an untagged capability faults. Code that obeys provenance ports cleanly. Code that launders pointers through `uint32_t` or `long` stops working. That is the strongest practical argument for writing provenance-clean C today.

### 3.4 Data races are UB, so `volatile` is not a synchronization primitive (§5.1.2.4)

A data race is two conflicting accesses from different threads, at least one non-atomic, with no happens-before order between them. It is UB, not merely an unspecified value. §1.7's deleted wait-loop is the codegen proof. The full treatment is in [Folder 03](../README.md#layout-and-build-status):

- what `volatile` does (forces a load or store per access, in program order, *with respect to other volatile accesses*);
- what it does not do (order non-volatile accesses, provide atomicity beyond the native width, or emit `DMB`);
- why `_Atomic` + `memory_order_acquire/release` lower to `LDAR`/`STLR` on AArch64 and to `DMB ISH` around plain accesses on Cortex-M.

---

## 4. Production C Code Blueprint: Parsing a DMA'd Frame Header

The setting: a UART, SPI or Ethernet DMA engine deposits frames into a ring of byte buffers. A frame can start at **any** byte offset. Ethernet MACs, for example, commonly start the IP header at offset 2. The header is big-endian on the wire and carries a binary32 float.

### 4.1 The Subtle Buggy Way

```c
/* wire_buggy.c - compiles cleanly with -Wall -Wextra, passes desk review,
 * and faults (or silently misparses) on real silicon. */
#include <stdint.h>

struct wire_hdr_raw {                 /* overlaid directly on the DMA buffer */
    uint32_t magic;
    uint8_t  version;
    uint8_t  flags;
    uint16_t payload_len;
    uint32_t gain_bits;
};

int wire_parse_buggy(uint8_t *buf, int buf_len, float *gain, uint8_t **payload);

int wire_parse_buggy(uint8_t *buf, int buf_len, float *gain, uint8_t **payload)
{
    struct wire_hdr_raw *h = (struct wire_hdr_raw *)buf;    /* (1) alignment UB, (2) aliasing UB */

    if (__builtin_bswap32(h->magic) != 0x4C374B42u)          /* (3) read before any length check  */
        return -1;
    int total = (int)sizeof *h + __builtin_bswap16(h->payload_len); /* (4) sizeof(struct) used as wire size */
    if (buf_len - total < 0)                                 /* (5) signed length arithmetic      */
        return -2;
    *gain = *(float *)&h->gain_bits;                         /* (6) float pun through a pointer   */
    *payload = buf + sizeof *h;
    return 0;
}
```

**Diagnostics (verified, Clang 21.1.0, Cortex-M7):**
- `-Wall -Wextra`: 0 warnings.
- Adding `-Wcast-align`:

```text
wire_buggy.c:17:30: warning: cast from 'uint8_t *' (aka 'unsigned char *') to 'struct wire_hdr_raw *' increases required alignment from 1 to 4 [-Wcast-align]
```

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7):**

```asm
wire_parse_buggy:
	push	{r7, lr}
	movw	lr, #14156
	ldr.w	r12, [r0]
	movt	lr, #16971
	cmp	r12, lr
	bne	.LBB0_3
	ldrh.w	r12, [r0, #6]
	mov.w	lr, #12
	rev.w	r12, r12
	add.w	r12, lr, r12, lsr #16
	cmp	r1, r12
	bge	.LBB0_4
	mvn	r0, #1
	pop	{r7, pc}
.LBB0_3:
	mov.w	r0, #-1
	pop	{r7, pc}
.LBB0_4:
	ldr	r1, [r0, #8]
	adds	r0, #12
	str	r0, [r3]
	movs	r0, #0
	str	r1, [r2]
	pop	{r7, pc}
```

What is wrong, defect by defect:

1. **Alignment.** The conversion is UB if `buf` is misaligned. On Cortex-M0+ the `ldr.w r12, [r0]` HardFaults at an odd address. On M7 it survives here only because this particular field set didn't fuse into `LDRD` (contrast §2.3). One more field read, and it will.
2. **Aliasing.** If `buf` points into a `uint8_t` array, accessing it through `struct wire_hdr_raw` violates §6.5p7.
3. **Reading before checking.** The magic is read before `buf_len` is checked. A 2-byte runt frame reads past the buffer: on the last buffer of a ring that sits at the end of SRAM, this is a BusFault with `PRECISERR` and `BFAR` pointing just past the RAM end.
4. **`sizeof` as wire size.** It works today because this struct has no padding. Add a `uint8_t` field and the compiler inserts padding the wire doesn't have.
5. **Signed lengths.** `buf_len - total` with `int` turns a negative caller length into "valid". With `int` sizes near `INT_MAX`, the addition itself is UB.
6. **The float pun.** It went through a pointer cast. The compiler happened to emit an integer move (`ldr r1, [r0, #8]` / `str r1, [r2]`), but that is luck, not a guarantee.

Note also that the compiler **constant-folded the byte swap** into the comparison: `movw/movt` build `0x424B374C`, the byte-reversed magic, and compare it against the raw word. That is fine, but it shows that the optimizer reasons about the bytes, so it will equally "reason about" your UB.

### 4.2 The Silicon-Hardened Production Way

`wire.h`:

```c
/* wire.h - alignment-agnostic, endian-explicit parser for a DMA'd frame header. */
#ifndef WIRE_H
#define WIRE_H

#include <stddef.h>
#include <stdint.h>

#define WIRE_MAGIC        0x4C374B42u   /* "L7KB", big-endian on the wire */
#define WIRE_VERSION      1u
#define WIRE_HDR_SIZE     12u           /* bytes on the wire, NOT sizeof(wire_hdr_t) */
#define WIRE_MAX_PAYLOAD  1500u

typedef enum {
    WIRE_OK = 0,
    WIRE_ERR_ARG,
    WIRE_ERR_SHORT,
    WIRE_ERR_MAGIC,
    WIRE_ERR_VERSION,
    WIRE_ERR_LENGTH
} wire_status_t;

/* Native, naturally aligned representation. Never overlaid on the buffer. */
typedef struct {
    uint32_t magic;
    uint8_t  version;
    uint8_t  flags;
    uint16_t payload_len;
    float    gain;
} wire_hdr_t;

wire_status_t wire_parse(const uint8_t *buf, size_t buf_len,
                         wire_hdr_t *out, const uint8_t **payload);

#endif /* WIRE_H */
```

`wire.c`:

```c
/* wire.c - "Silicon-hardened" parsing: no pointer casts, no unaligned wide loads,
 * no signed arithmetic on lengths, every read dominated by a bounds check. */
#include "wire.h"

#include <string.h>

#if defined(__has_include)
#  if __has_include(<stdckdint.h>) && defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 202311L)
#    include <stdckdint.h>
#    define WIRE_CKD_ADD(r, a, b) ckd_add((r), (a), (b))
#  endif
#endif
#ifndef WIRE_CKD_ADD
#  define WIRE_CKD_ADD(r, a, b) __builtin_add_overflow((a), (b), (r))
#endif

_Static_assert(sizeof(float) == sizeof(uint32_t), "binary32 float required");
_Static_assert(WIRE_HDR_SIZE == 4u + 1u + 1u + 2u + 4u, "wire layout drifted");

/* Byte-wise loads: defined for any alignment and any effective type (character
 * access is always permitted by C17 6.5p7). Clang/GCC fuse these into LDR+REV
 * where the ISA allows unaligned LDR, and keep byte loads where it does not. */
static inline uint16_t load_be16(const uint8_t *p)
{
    return (uint16_t)(((uint16_t)p[0] << 8) | (uint16_t)p[1]);
}

static inline uint32_t load_be32(const uint8_t *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8)  |  (uint32_t)p[3];
}

static inline float f32_from_bits(uint32_t bits)
{
    float f;
    memcpy(&f, &bits, sizeof f);     /* lowers to a single fmov/vmov */
    return f;
}

wire_status_t wire_parse(const uint8_t *buf, size_t buf_len,
                         wire_hdr_t *out, const uint8_t **payload)
{
    size_t total = 0u;
    wire_hdr_t h;

    if ((buf == NULL) || (out == NULL) || (payload == NULL)) {
        return WIRE_ERR_ARG;
    }
    if (buf_len < (size_t)WIRE_HDR_SIZE) {
        return WIRE_ERR_SHORT;
    }

    h.magic       = load_be32(&buf[0]);
    h.version     = buf[4];
    h.flags       = buf[5];
    h.payload_len = load_be16(&buf[6]);
    h.gain        = f32_from_bits(load_be32(&buf[8]));

    if (h.magic != WIRE_MAGIC) {
        return WIRE_ERR_MAGIC;
    }
    if (h.version != WIRE_VERSION) {
        return WIRE_ERR_VERSION;
    }
    if ((h.payload_len > WIRE_MAX_PAYLOAD) ||
        WIRE_CKD_ADD(&total, (size_t)WIRE_HDR_SIZE, (size_t)h.payload_len) ||
        (total > buf_len)) {
        return WIRE_ERR_LENGTH;
    }

    *out = h;
    *payload = &buf[WIRE_HDR_SIZE];
    return WIRE_OK;
}

#ifdef WIRE_SELFTEST
#include <stdio.h>

int main(void)
{
    /* Simulate a DMA RX buffer where the frame starts at an odd address. */
    static uint8_t rx[64];
    const uint8_t frame[] = {
        0x4C, 0x37, 0x4B, 0x42,   /* magic "L7KB"            */
        0x01, 0xA5,               /* version 1, flags 0xA5    */
        0x00, 0x04,               /* payload_len = 4          */
        0x3F, 0xC0, 0x00, 0x00,   /* gain = 1.5f (0x3FC00000) */
        0xDE, 0xAD, 0xBE, 0xEF    /* payload                  */
    };
    wire_hdr_t h;
    const uint8_t *pl = NULL;

    memcpy(&rx[1], frame, sizeof frame);
    wire_status_t st = wire_parse(&rx[1], sizeof frame, &h, &pl);
    printf("ok:      st=%d magic=0x%08X ver=%u flags=0x%02X len=%u gain=%.3f pl[0]=0x%02X\n",
           (int)st, (unsigned)h.magic, (unsigned)h.version, (unsigned)h.flags,
           (unsigned)h.payload_len, (double)h.gain, (unsigned)pl[0]);
    printf("short:   st=%d\n", (int)wire_parse(&rx[1], 11u, &h, &pl));
    rx[1 + 7] = 0xFF;   /* payload_len = 0x00FF > bytes available */
    printf("length:  st=%d\n", (int)wire_parse(&rx[1], sizeof frame, &h, &pl));
    rx[1] = 0x00;
    printf("magic:   st=%d\n", (int)wire_parse(&rx[1], sizeof frame, &h, &pl));
    printf("nullarg: st=%d\n", (int)wire_parse(NULL, sizeof frame, &h, &pl));
    return 0;
}
#endif
```

**Build evidence (verified):** zero diagnostics under the full warning set (`-Wall -Wextra -Wpedantic -Werror -Wconversion -Wsign-conversion -Wcast-align -Wshadow -Wstrict-prototypes -Wmissing-prototypes`):
- `-std=c17` on Cortex-M7, Cortex-M0+, Cortex-M33, AArch64, x86-64 and RV64;
- `-std=c23` on Cortex-M7 and AArch64.

**Self-test output (verified, native x86-64, frame deliberately at an odd address):**

```text
ok:      st=0 magic=0x4C374B42 ver=1 flags=0xA5 len=4 gain=1.500 pl[0]=0xDE
short:   st=2
length:  st=5
magic:   st=3
nullarg: st=1
```

**Codegen (verified — Clang 21.1.0, `-O2 -std=c17`, Cortex-M7):**

```asm
wire_parse:
	mov.w	r12, #1
	cbz	r0, .LBB0_2
	cmp	r2, #0
	it	ne
	cmpne	r3, #0
	bne	.LBB0_3
.LBB0_2:
	mov	r0, r12
	bx	lr
.LBB0_3:
	cmp	r1, #12
	bhs	.LBB0_5
	mov.w	r12, #2
	mov	r0, r12
	bx	lr
.LBB0_5:
	push	{r4, r5, r7, lr}
	ldr.w	lr, [r0]
	movw	r12, #19266
	movt	r12, #19511
	rev.w	lr, lr
	cmp	lr, r12
	bne	.LBB0_10
	ldrb.w	lr, [r0, #4]
	cmp.w	lr, #1
	bne	.LBB0_11
	ldrh.w	lr, [r0, #6]
	movw	r4, #1500
	rev16.w	lr, lr
	cmp	lr, r4
	bhi	.LBB0_9
	add.w	r4, lr, #12
	cmp	r1, r4
	bhs	.LBB0_13
.LBB0_9:
	mov.w	r12, #5
	b	.LBB0_12
.LBB0_10:
	mov.w	r12, #3
	b	.LBB0_12
.LBB0_11:
	mov.w	r12, #4
.LBB0_12:
	pop.w	{r4, r5, r7, lr}
	mov	r0, r12
	bx	lr
.LBB0_13:
	ldr	r4, [r0, #8]
	ldrb	r5, [r0, #5]
	str.w	r12, [r2]
	mov.w	r12, #0
	movs	r1, #1
	strb	r1, [r2, #4]
	strb	r5, [r2, #5]
	adds	r0, #12
	rev	r1, r4
	strh.w	lr, [r2, #6]
	str	r1, [r2, #8]
	str	r0, [r3]
	b	.LBB0_12
```

**Codegen (verified — Clang 21.1.0, `-O2 -std=c17`, Cortex-M0+):**

```asm
wire_parse:
	push	{r4, r5, r6, r7, lr}
	movs	r4, #1
	cmp	r0, #0
	beq	.LBB0_10
	cmp	r2, #0
	beq	.LBB0_10
	cmp	r3, #0
	beq	.LBB0_10
	cmp	r1, #12
	bhs	.LBB0_5
	movs	r0, #2
	pop	{r4, r5, r6, r7, pc}
.LBB0_5:
	ldrb	r4, [r0]
	lsls	r4, r4, #24
	ldrb	r5, [r0, #1]
	lsls	r5, r5, #16
	adds	r4, r5, r4
	ldrb	r5, [r0, #2]
	lsls	r5, r5, #8
	adds	r4, r4, r5
	ldrb	r5, [r0, #3]
	adds	r4, r4, r5
	ldr	r5, .LCPI0_0
	cmp	r4, r5
	bne	.LBB0_11
	ldrb	r4, [r0, #4]
	cmp	r4, #1
	bne	.LBB0_12
	ldrb	r4, [r0, #7]
	ldrb	r6, [r0, #6]
	lsls	r6, r6, #8
	adds	r6, r6, r4
	movs	r4, #5
	ldr	r7, .LCPI0_1
	cmp	r6, r7
	bhi	.LBB0_10
	mov	r7, r6
	adds	r7, #12
	cmp	r1, r7
	blo	.LBB0_10
	ldrb	r1, [r0, #8]
	lsls	r1, r1, #24
	ldrb	r4, [r0, #9]
	lsls	r4, r4, #16
	adds	r1, r4, r1
	ldrb	r4, [r0, #10]
	lsls	r4, r4, #8
	adds	r1, r1, r4
	ldrb	r4, [r0, #11]
	adds	r1, r1, r4
	ldrb	r4, [r0, #5]
	strb	r4, [r2, #5]
	movs	r4, #1
	strb	r4, [r2, #4]
	str	r5, [r2]
	str	r1, [r2, #8]
	strh	r6, [r2, #6]
	adds	r0, #12
	str	r0, [r3]
	movs	r4, #0
.LBB0_10:
	mov	r0, r4
	pop	{r4, r5, r6, r7, pc}
.LBB0_11:
	movs	r0, #3
	pop	{r4, r5, r6, r7, pc}
.LBB0_12:
	movs	r0, #4
	pop	{r4, r5, r6, r7, pc}
.LCPI0_0:
	.long	1278692162
.LCPI0_1:
	.long	1500
```

Why this is the production answer:

- **One source, two optimal codegens.** On v7E-M, the four-byte big-endian idiom became `ldr.w` + `rev.w`, an unaligned single load plus byte reverse. The 16-bit one became `ldrh.w` + `rev16.w`. On v6-M, where unaligned loads fault, the compiler kept byte loads. The C is correct on both, and fast where the ISA allows.
- **The overflow guard costs nothing where it can't fire.** `size_t + uint16_t` can't overflow a 32-bit `size_t` once `payload_len ≤ 1500`, so the compiler deleted the `ckd_add` branch. You keep the proof in the source, and it's free.
- **Every load is dominated by a length check.** `cmp r1, #12` precedes the first byte read.
- **The native struct is never overlaid** on the buffer, so padding, alignment and endianness of `wire_hdr_t` are irrelevant to the wire format.
- **MISRA:** no Rule 11.3 casts. `memcpy` in `f32_from_bits` needs a Rule 21.15 deviation, recorded once.

---

## 5. Hardware Debugging and Post-Mortem Diagnostics

### 5.1 Symptom → UB class map

| Field symptom | Likely UB class | Confirm with |
|---|---|---|
| UsageFault, `CFSR.UNALIGNED` (bit 24), faulting PC at `LDRD`/`LDM` in a parser | Misaligned pointer cast (§2.3) | Disassemble the PC; check the buffer base address mod 4/8 |
| HardFault on Cortex-M0+ at an ordinary `LDR` | Same, on v6-M (no unaligned support) | Stacked PC → `addr2line`; check `rN` alignment in the stacked frame |
| AArch64 `Internal error: Oops`, `ESR = 0x96000021` (EC 0x25, DFSC 0x21) | Unaligned access to Device memory or an exclusive | Decode the ESR (§5.3); check the page attributes of `FAR` |
| Check present in source, absent from disassembly | Null-check deletion after dereference; signed or pointer overflow folding | `objdump -dS`, then rebuild with `-fno-delete-null-pointer-checks` / `-fwrapv` and diff |
| Busy-wait exits immediately or hangs only at `-O2` | Data race plus forward progress (§1.7) | Disassemble: the loop body is missing, or is a `b .` |
| `PC` in function B, `LR` in function A, and B starts right after A in the map file | `unreachable()` reached; fall-through past a missing `ret` | Map file adjacency; disassemble A's tail |
| UsageFault `UNDEFINSTR` (bit 16) at `0xDEFE` (Thumb), or AArch64 `BRK #0x5500` | UBSan trap mode fired, which is good news | Decode the trap immediate (§5.4) |
| Value "randomly" correct in debug, wrong in release | Uninitialized read; TBAA reordering | `-ftrivial-auto-var-init=pattern`; `-fno-strict-aliasing` bisect |

### 5.2 Decoding the Cortex-M fault status for these cases

The registers are in the System Control Block (ARMv7-M / ARMv8-M Mainline):

| Register | Address | Fields that matter here |
|---|---|---|
| `CFSR` | `0xE000_ED28` | MMFSR `[7:0]`, BFSR `[15:8]`, UFSR `[31:16]` |
| `HFSR` | `0xE000_ED2C` | `VECTTBL` bit 1, `FORCED` bit 30, `DEBUGEVT` bit 31 |
| `MMFAR` | `0xE000_ED34` | Valid only if `CFSR.MMARVALID` (bit 7) |
| `BFAR` | `0xE000_ED38` | Valid only if `CFSR.BFARVALID` (bit 15) |
| `CCR` | `0xE000_ED14` | `UNALIGN_TRP` bit 3, `DIV_0_TRP` bit 4, `STKALIGN` bit 9 |
| `SHCSR` | `0xE000_ED24` | `MEMFAULTENA` 16, `BUSFAULTENA` 17, `USGFAULTENA` 18 (when clear, the fault escalates to HardFault with `FORCED`) |

CFSR bit map (whole-register bit positions):

| Bit | Name | Meaning in a UB post-mortem |
|---|---|---|
| 0 | `IACCVIOL` | Instruction fetch from an XN/MPU-denied region, e.g. a corrupted function pointer |
| 1 | `DACCVIOL` | Data access MPU violation, e.g. an out-of-bounds pointer hitting a guard region |
| 3 / 4 / 5 | `MUNSTKERR` / `MSTKERR` / `MLSPERR` | MPU fault during exception unstack/stack/lazy-FP |
| 7 | `MMARVALID` | `MMFAR` holds the faulting address |
| 8 | `IBUSERR` | Instruction bus error |
| 9 | `PRECISERR` | Precise data bus error; `BFAR` is valid and the stacked PC is the faulting instruction |
| 10 | `IMPRECISERR` | Imprecise: a buffered write failed *later*, so the stacked PC is **not** the culprit |
| 11 / 12 / 13 | `UNSTKERR` / `STKERR` / `LSPERR` | Bus fault on unstack/stack/lazy-FP: usually stack overflow into unmapped memory |
| 15 | `BFARVALID` | `BFAR` holds the faulting address |
| 16 | `UNDEFINSTR` | Undefined instruction: UBSan/`__builtin_trap` `UDF`, or a jump into data |
| 17 | `INVSTATE` | EPSR.T = 0: branch to an even address (function pointer without the Thumb bit) |
| 18 | `INVPC` | Bad `EXC_RETURN` on exception return |
| 19 | `NOCP` | FPU access with `CPACR` not enabled (Folder 02 boot sequence) |
| 20 | `STKOF` | ARMv8-M only: `MSPLIM`/`PSPLIM` stack-limit violation |
| 24 | `UNALIGNED` | Misaligned access that the hardware won't fix up |
| 25 | `DIVBYZERO` | Integer division by zero, only if `CCR.DIV_0_TRP = 1` (otherwise `SDIV` returns 0, which is silent) |

The hardware-stacked exception frame (8 words at the active SP on entry; Folder 04 covers FP extensions):

| Offset | 0x00 | 0x04 | 0x08 | 0x0C | 0x10 | 0x14 | 0x18 | 0x1C |
|---|---|---|---|---|---|---|---|---|
| Register | R0 | R1 | R2 | R3 | R12 | LR | **PC** | xPSR |

**Recipe (GDB over SWD, e.g. OpenOCD or J-Link GDB server):**

```text
(gdb) p/x *(uint32_t*)0xE000ED28            # CFSR
(gdb) p/x *(uint32_t*)0xE000ED38            # BFAR (if BFARVALID)
(gdb) p/x $lr                               # EXC_RETURN: bit 2 selects MSP (0) or PSP (1)
(gdb) set $f = (uint32_t*)(($lr & 4) ? $psp : $msp)
(gdb) p/x $f[6]                             # stacked PC = faulting instruction (if precise)
(gdb) info symbol $f[6]
(gdb) x/4i $f[6]
```

**Recipe (Lauterbach TRACE32):** `Register.view`, then `Data.dump D:0xE000ED28--0xE000ED3F /Long`. `Frame.view /Caller` unwinds from the stacked frame using DWARF CFI. `List.Mix` shows the faulting line interleaved with its machine code, which is how you *see* the `LDRD`.

**Imprecise bus faults** (`IMPRECISERR`) point at a later instruction because the store sat in the write buffer. To make them precise while debugging, set `ACTLR.DISDEFWBUF` (bit 1 of `0xE000_E008`) on Cortex-M3/M4. This disables write buffering for default memory map accesses and costs performance, so use it in debug builds only. Cortex-M7 has different ACTLR controls (⚠ verify in the M7 TRM).

### 5.3 The AArch64 side: decoding ESR_ELx

`ESR_ELx[31:26]` = EC (exception class); `ISS[24:0]` is class-specific.

| EC | Meaning | Typical UB root cause |
|---|---|---|
| `0x15` | SVC from AArch64 | (none) |
| `0x20` / `0x21` | Instruction abort from lower / same EL | Corrupted function pointer, jump into data |
| `0x22` | PC alignment fault | Branch to a misaligned address |
| `0x24` / `0x25` | Data abort from lower / same EL | Null/wild pointer, unaligned Device access |
| `0x26` | SP alignment fault | Hand-written asm broke 16-byte SP alignment (File 03) |
| `0x2F` | SError | Asynchronous external abort (bus error from a buffered write: the AArch64 analogue of `IMPRECISERR`) |
| `0x3C` | `BRK` instruction | UBSan trap (`#0x5500 | check`), `__builtin_trap` |

Data-abort ISS: `WnR` (bit 6: 1 = write), `DFSC` (bits 5:0):

- `0x04`–`0x07`: translation fault, levels 0–3. Most often a null or wild pointer.
- `0x09`–`0x0B`: access flag fault, levels 1–3.
- `0x0D`–`0x0F`: permission fault, levels 1–3.
- `0x10`: synchronous external abort.
- **`0x21`: alignment fault.**

A Linux oops prints `ESR = 0x96000021`. Decode: EC `0x25` (data abort, same EL), IL = 1, DFSC `0x21` (alignment). `FAR` is in the oops header.

### 5.4 Making UB loud on target: UBSan trap mode

Full UBSan needs a runtime that prints diagnostics. On bare metal, use **trap mode**: each check becomes a compare plus an undefined-instruction or `BRK`.

```c
int add_s32(int a, int b) { return a + b; }
```

**Codegen (verified — Clang 21.1.0, `-O2 -fsanitize=signed-integer-overflow -fsanitize-trap=signed-integer-overflow`, Cortex-M7):**

```asm
add_s32:
	adds	r0, r0, r1
	it	vc
	bxvc	lr
.LBB0_1:
	.inst.n	0xdefe
```

**Codegen (verified — same flags, `aarch64-linux-gnu`):**

```asm
add_s32:
	adds	w0, w0, w1
	b.vs	.LBB0_2
	ret
.LBB0_2:
	brk	#0x5500
```

- On Cortex-M, `0xDEFE` is `UDF #254`. It raises a UsageFault with `CFSR.UNDEFINSTR`, or a HardFault if UsageFault isn't enabled. Your HardFault handler (Folder 07) should recognize a stacked PC that points at `0xDEFE` and log "UBSan trap at <PC>". GCC's `__builtin_trap` on Thumb emits a different `UDF` immediate (⚠ verify).
- On AArch64, `BRK #0x5500` carries the UBSan check kind in the low byte (`0x55` is ASCII 'U'). The Linux arm64 kernel decodes this with `CONFIG_UBSAN_TRAP` and reports the check type.
- Cost: one compare-and-branch per checked operation. Ship it in pre-production builds. Many teams keep `-fsanitize=bounds` and `signed-integer-overflow` traps in production firmware for safety-relevant modules.

### 5.5 Bisecting UB in a build

1. **Flag toggles.** Rebuild the suspect TU with each flag below. If the bug disappears, you know the rule:

| Flag | Rule it disables |
|---|---|
| `-fno-strict-aliasing` | TBAA (§2) |
| `-fwrapv` (GCC also has `-fno-strict-overflow`) | Signed overflow (§1.5) |
| `-fno-delete-null-pointer-checks` | Null-check deletion (§1.8) |
| `-fno-aggressive-loop-optimizations` (GCC) | Trip-count inference from UB array indexing |
| `-ftrivial-auto-var-init=pattern` | Uninitialized reads (§1.9) |
| `-fno-builtin` | Library-call semantics (`memcpy` nonnull, loop → `memset`) |

2. **Pass bisection.**
   - LLVM: `-mllvm -opt-bisect-limit=N`, a binary search over pass executions.
   - GCC: `-fdump-tree-all` (tree passes) and `-fopt-info-all` (optimization decisions).
   - Clang remarks: `-Rpass=.*` and `-Rpass-missed=.*`.
3. **Host-side sanitizers.** Build the platform-independent modules for x86-64 with `-fsanitize=undefined,alignment,address -fno-sanitize-recover=all`, and run the unit tests there.
4. **Static analysis that actually proves things:**
   - Clang Static Analyzer (`scan-build`) and GCC `-fanalyzer`: path-sensitive bug finders; *unsound*, so they can miss bugs.
   - Polyspace Code Prover and Astrée: abstract interpretation; *sound* proofs of the absence of run-time errors.
   - Frama-C EVA/WP: abstract interpretation and deductive proof.
   - CBMC: bounded model checking.

   Tier-1 safety programs (ISO 26262 ASIL-D, DO-178C DAL A) use the sound tools for exactly the UB classes in this file.

---

## 6. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "Your overflow check `if (a + b < a)` passes code review and unit tests, but the bug it guards against still ships. Why?"

- **L5 textbook answer:** "Signed overflow is undefined, so use unsigned arithmetic or `INT_MAX - b` pre-checks."
- **Why L5 fails on real hardware:** The answer is correct, but it doesn't explain *why tests passed*. At `-O0` the compare is emitted literally and the wrapped sum makes the check work. At `-O2`, Clang rewrites `a + b < a` as `b < 0` (verified: `lsr w0, w1, #31`). Unit tests built at `-O0`, or with sanitizers that change codegen, pass. The release image tests only the sign of `b`. On multi-core ARM it's worse: one core runs a code path inlined with different range facts, so behavior differs per call site.
- **L7 principal defense:**
  1. Replace hand-rolled checks with `ckd_add` (C23) or `__builtin_add_overflow`, which lower to `adds` + `cset vs` (verified, one instruction).
  2. Build unit tests at the shipping optimization level, plus UBSan trap mode on target.
  3. Treat length and offset math as `size_t`, and validate against buffer sizes before arithmetic.
  4. Add MISRA Rule 10.x / CERT INT32-C enforcement in static analysis.
  5. If legacy code can't be fixed now, `-fwrapv` is the containment, not the cure.

### Q2 🔥⚡ "On Cortex-M7, cast a `uint8_t*` DMA buffer to `struct hdr*` and read two `uint32_t` fields. What can go wrong?"

- **L5:** "Strict aliasing violation; use `memcpy`." Or: "Cortex-M7 supports unaligned access, so it's fine."
- **Why L5 fails:** The second answer is the trap. v7-M tolerates misaligned **single** `LDR`. The cast tells the compiler the address is 4-byte aligned, so it fuses adjacent fields into **`LDRD`** (verified). `LDRD` always faults when misaligned on v7-M: UsageFault, `CFSR.UNALIGNED`. Ethernet DMA commonly starts IP headers at offset 2. The fault appears only in builds where both fields are read near each other, so it comes and goes with unrelated code changes. On the same SoC's Cortex-M0+ companion core, even single `LDR` faults. On a Cortex-A core with the buffer mapped Device-nGnRE, `LDP` alignment-faults.
- **L7 defense:**
  1. Byte-wise `load_be32`/`load_le32` helpers or `memcpy`. They compile to `ldr` + `rev` on v7-M (verified) and byte loads on v6-M (verified).
  2. Never overlay structs on DMA buffers.
  3. Enable `-Wcast-align` (verified to catch it) and MISRA 11.3.
  4. Parse-at-every-offset unit test (0–7).
  5. In the HardFault handler, decode `UNALIGNED` and log the stacked PC.
  6. Decide `CCR.UNALIGN_TRP` deliberately: setting it to 1 in debug builds finds *all* misaligned accesses early.

### Q3 "Read the initial stack pointer from the vector table at address 0 in C."

- **L5:** `uint32_t sp = *(uint32_t *)0;`
- **Why L5 fails:** A null dereference is UB no matter what memory sits at 0. Clang deletes the load and returns garbage (verified: `read_initial_msp_plain` is just `bx lr`, with a warning). GCC may replace it with a trap (`-fisolate-erroneous-paths-dereference`), which crashes the bootloader (⚠ verify per release). `volatile` happened to survive in Clang (verified), but that is not a language guarantee.
- **L7 defense:** Read through a named linker symbol (`extern const uint32_t __vector_table[]`), or index from `SCB->VTOR`. If the translation unit genuinely manipulates page 0 (an MMU-less kernel), build it with `-fno-delete-null-pointer-checks` (as Linux does) and record the deviation. Explain *why* the flag exists: CVE-2009-1897.

### Q4 🔥 "A loop waits for an ISR to set a flag. It works at `-O0` and hangs, or falls straight through, at `-O2`. Explain the two independent rules."

- **L5:** "The compiler cached the flag in a register; make it `volatile`."
- **Why L5 fails:** The verified Cortex-M7 output doesn't cache anything. It **deletes the loop** (`consume` is three instructions). Two rules combine: the data race (§5.1.2.4) lets the compiler assume no concurrent writer, and forward progress (§6.8.5p6) lets it assume a side-effect-free loop terminates. `volatile` removes the forward-progress license and forces a load per iteration, so the uniprocessor ISR case "works". It does not order the *payload* read after the flag read on a weakly ordered multi-core system, and it does not stop a Cortex-A store buffer from making the flag visible before the payload.
- **L7 defense:** `_Atomic bool ready` with `atomic_store_explicit(&ready, true, memory_order_release)` in the producer and `atomic_load_explicit(&ready, memory_order_acquire)` in the consumer. These lower to `STLR`/`LDAR` on AArch64, and to `DMB ISH` plus plain accesses on v7-M. Use `volatile` only for MMIO. For a single-core ISR handoff on Cortex-M, add a compiler barrier and use `__WFI` with a `"memory"` clobber (File 03). Full treatment: Folder 03.

### Q5 "`memcpy` vs `union` vs pointer cast for type punning: what is correct in C, what in C++, and what does each cost?"

- **L5:** "Union punning is fine." Or: "`memcpy` is the only safe way but it's slow."
- **Why L5 fails:** Union punning is defined in C (§6.5.2.3, footnote 95) but UB in C++. Shared headers compiled as both languages break. GCC also supports it only *through the union type*: the member-pointer variant is not covered. The "slow `memcpy`" claim is false: `memcpy` lowers to one `fmov`/`vmov`/`movd`/`fmv.w.x` (verified on five ISAs), and is *free* on soft-float Cortex-M0+ (`bx lr`).
- **L7 defense:** One audited helper per conversion (`f32_from_bits`, `bits_from_f32`) using `memcpy` (C and C++), or `std::bit_cast` (C++20). Record a MISRA Rule 21.15 deviation once. Ban casts elsewhere (Rule 11.3). Verify codegen in CI by grepping the disassembly of the helper for a `bl memcpy`.

### Q6 🧊 "Linux builds with `-fno-strict-aliasing`. Should our flight-controller firmware?"

- **L5:** "Yes, it's safer." Or: "No, it's slower."
- **Why L5 fails:** Either answer is a flag decision, not an engineering decision. Globally disabling TBAA hides aliasing bugs in shared code that will later be built elsewhere (unit-test hosts, a second product line), and costs vectorization in DSP loops (the verified `restrict`/TBAA listings show what the compiler gains). Keeping it on with no policy leaves the casts in.
- **L7 defense:** Per-module policy. TBAA stays on in compute code. The allocator, packet, and HAL TUs either use only character-type access helpers, or are compiled with `-fno-strict-aliasing` as a documented, reviewed exception. MISRA 11.3 and `-Wcast-align=strict` gate merges, and host UBSan runs in CI. Measure the cycle delta of the flag on the real hot loops before arguing about it.

### Q7 🧊 "What is pointer provenance, and when has it bitten firmware you've shipped?"

- **L5:** "Pointers point to objects; don't access freed memory."
- **Why L5 fails:** It misses that **equal addresses aren't equal pointers**. The verified AArch64 listing hoists the `*q` load above the `*p` store when `p == q` bit-for-bit but `p` came from `x`. On x86-64, the same compiler kept the order, so the bug is target-specific. Firmware hits provenance through:
  - linker symbols compared or subtracted as pointers;
  - `p + len < p` overflow checks (verified constant-false);
  - lock-free code comparing pointers after `free` (pointer zap).
- **L7 defense:**
  1. Linker symbols are declared as arrays of unknown bound; sizes and compares are done in `uintptr_t`.
  2. Bounds are checked on lengths, not on pointers.
  3. MISRA 18.2/18.3 and CERT ARR36-C are enforced.
  4. Lock-free reclamation uses tagged indices or hazard pointers, not raw pointer compares (Folder 05).
  5. The codebase is CHERI-clean, so no pointer ever round-trips through `uint32_t`.

### Q8 ⚡ "A field crash: the stacked PC is inside `crc32_update`, but the faulting path never calls it. LR points into `parse_cmd`."

- **L5:** "Stack corruption; check for buffer overflows."
- **Why L5 fails:** Stack corruption is possible, but there's a cheaper hypothesis that the map file confirms in thirty seconds. `parse_cmd` ends in a `switch` whose `default:` is `__builtin_unreachable()`. The compiler emitted no epilogue for that path, so execution **fell off the end of `parse_cmd` into the next function in `.text`**, which the linker happened to place: `crc32_update`. A runtime value outside the enum (a new command ID from a newer host) reached the "impossible" case.
- **L7 defense:**
  1. In the map file or `nm -n`, confirm `crc32_update` starts at `parse_cmd`'s end address.
  2. Disassemble `parse_cmd`'s tail: there's no `bx lr`/`pop {pc}` after the jump table.
  3. Fix: replace `unreachable()` with a `TRAP_UNREACHABLE()` macro that is `__builtin_trap()` (`UDF`), which turns a mystery into a precise UsageFault `UNDEFINSTR` at the right PC. Reserve real `unreachable()` for profiled hot paths, with a proof comment.
  4. Validate external enums at the trust boundary.

### Q9 "Does `-O0` make undefined behavior safe?"

- **L5:** "Yes, because the optimizer doesn't run."
- **Why L5 fails:**
  - Front-end constant folding and `-O0` code generation still rely on the semantics. A shift by 32 folded at compile time has no hardware result to fall back on.
  - The hardware still faults on misaligned `LDRD` if the front end emits it for a 64-bit field.
  - Data races remain races on a multi-core part: `-O0` changes timing, not ordering guarantees.
  - "Works at `-O0`" is evidence that the bug is optimizer-*exposed*, not evidence that the code is correct.
- **L7 defense:** UB is a property of the program, not of the flags. Fix the source, ship at the optimization level you test, and use sanitizers and sound static analysis to establish its absence.

### Q10 🧊 "Why is `realloc(p, 0)` a code-review red flag in C23 code?"

- **L5:** "It frees the memory."
- **Why L5 fails:** C17 left it implementation-defined (it might return NULL and free, or return a unique pointer). C23 made it **undefined**. Ported code that relied on glibc's behavior now has a UB path, and sanitizers and static analyzers will flag it.
- **L7 defense:** Never call `realloc` with size 0. Call `free` explicitly. Firmware with deterministic allocators (Folder 05) shouldn't call `realloc` at all.

---

## 7. Invariants Checklist (pin to the code-review template)

- [ ] No object-pointer casts outside audited helpers (MISRA 11.3; `-Wcast-align=strict` in CI).
- [ ] Every wire/DMA parse is byte-wise or `memcpy`-based, with **every load dominated by a length check**.
- [ ] All length/offset arithmetic is `size_t`; overflow checked with `ckd_add`/`__builtin_*_overflow`.
- [ ] No hand-rolled signed-overflow checks; no `p + n < p` pointer checks.
- [ ] Shift counts proven `< width`; signed left shifts of negative or sign-bit-reaching values forbidden (`1u << 31`).
- [ ] No null-constant spelling of address 0; vector table read via linker symbol or `VTOR`.
- [ ] `memcpy`/`memset` with possibly-null pointers guarded by `n != 0`.
- [ ] Cross-context flags are `_Atomic` (or, for single-core ISR handoff, `volatile` plus a documented barrier); never plain globals.
- [ ] `unreachable()` only through a trap-in-debug macro; external enums validated at trust boundaries.
- [ ] Linker symbols declared as `extern T sym[];` and compared in `uintptr_t`.
- [ ] `-ftrivial-auto-var-init=zero` in production, `=pattern` in debug.
- [ ] UBSan trap mode in pre-production firmware; host UBSan+ASan in CI; a sound analyzer on safety-relevant modules.
- [ ] HardFault handler decodes `UNALIGNED`, `UNDEFINSTR` (including the UBSan `0xDEFE` signature), `PRECISERR`/`BFAR`, and `IMPRECISERR`.

## 8. MISRA C:2012 / CERT C Cross-Reference

| Topic | MISRA C:2012 (retained in :2023) | CERT C |
|---|---|---|
| No UB at all | Rule 1.3 | MSC15-C (recommendation) |
| Signed overflow | Dir 4.1, Rules 10.1 / 10.4 (essential types) | INT32-C |
| Unsigned wrap that is unintended | Rule 12.4 (constant expressions), Dir 4.1 | INT30-C |
| Shift range | Rule 12.2 | INT34-C |
| Pointer cast between object types | Rule 11.3 | EXP36-C (alignment), EXP39-C (aliasing) |
| Integer ↔ pointer | Rule 11.4 (advisory), 11.6 | INT36-C |
| `memcpy` argument types | Rule 21.15 | (none) |
| `union` | Rule 19.2 (advisory) | (none) |
| Pointer arithmetic, subtraction, comparison | Rules 18.1, 18.2, 18.3 | ARR30-C, ARR36-C, ARR38-C |
| Uninitialized reads | Rule 9.1 | EXP33-C |
| Null dereference | Dir 4.1, Rule 1.3 | EXP34-C |
| Data races | Rule 1.3 (and the MISRA C:2012 Amendment 4 concurrency rules) | CON43-C |
| Implicit declarations | Rule 17.3 | DCL31-C |
| Evaluation order / unsequenced effects | Rule 13.2 | EXP30-C |

## 9. References

1. ISO/IEC 9899:2011 (draft N1570), 9899:2018 (draft N2176), 9899:2024 (draft N3220).
2. WG14 N3322, *Allow zero length operations on null pointers* (accepted for C2y). ISO/IEC TS 6010 provenance drafts (N2577, N3005).
3. C. Lattner, *What Every C Programmer Should Know About Undefined Behavior*, LLVM Blog, 2011 (3 parts).
4. J. Regehr, *A Guide to Undefined Behavior in C and C++*, 2010; and *Embedded in Academia* posts on UB and integer overflow.
5. X. Wang, N. Zeldovich, M. F. Kaashoek, A. Solar-Lezama, *Towards Optimization-Safe Systems: Analyzing the Impact of Undefined Behavior*, SOSP 2013.
6. K. Memarian, V. B. F. Gomes, B. Davis, S. Kell, A. Richardson, R. N. M. Watson, P. Sewell, *Exploring C Semantics and Pointer Provenance*, POPL 2019.
7. LLVM Language Reference Manual: *Poison Values*, *Pointer Aliasing Rules*, `nsw`/`nuw`, `inbounds`, `mustprogress`, `null_pointer_is_valid`.
8. GCC Manual: *Optimize Options* (`-fstrict-aliasing`, `-fdelete-null-pointer-checks`, `-fisolate-erroneous-paths-dereference`, `-fwrapv`, `-faggressive-loop-optimizations`); *Common Variable/Type Attributes* (`may_alias`).
9. Arm, *ARMv7-M Architecture Reference Manual* (DDI 0403E), §A3.2 *Alignment support*, §B3.2 *System Control Space*; *ARMv8-M ARM* (DDI 0553); *Arm ARM for A-profile* (DDI 0487), D-chapter on *Alignment faults* and ESR encoding.
10. CVE-2009-1897 (Linux `tun_chr_poll` null-check elimination), and the follow-up kernel switch to `-fno-delete-null-pointer-checks`.
11. MISRA C:2012 (third edition, first revision) with Amendments 1–4 / MISRA C:2023; SEI CERT C Coding Standard.
12. R. N. M. Watson et al., *CHERI C/C++ Programming Guide* (UCAM-CL-TR-947); Arm Morello program documentation.
