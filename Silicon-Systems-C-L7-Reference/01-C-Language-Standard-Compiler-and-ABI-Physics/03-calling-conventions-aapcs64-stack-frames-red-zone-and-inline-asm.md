# 03 · Calling Conventions: AAPCS64, Stack Frames, the Red Zone, and Inline Assembly

> **Folder:** `01-C-Language-Standard-Compiler-and-ABI-Physics/` · **File 3 of 3**
> **Anchors:**
> - Arm *Procedure Call Standard for the Arm 64-bit Architecture* (AAPCS64, IHI 0055) and *for the Arm Architecture* (AAPCS32, IHI 0042).
> - System V AMD64 psABI; Microsoft x64 calling convention; Apple *Writing ARM64 code for Apple platforms*; RISC-V ELF psABI.
> - Arm ARM for A-profile (DDI 0487): SCTLR_ELx.SA/SA0, PAuth, BTI, GCS, ESR_ELx.
> - ARMv7-M ARM (DDI 0403): exception entry stacking, CCR.STKALIGN, PRIMASK/BASEPRI.
> - Arm C Language Extensions (ACLE); Arm application note AN321 *Cortex-M Programming Guide to Memory Barrier Instructions*.
> - GCC manual *Extended Asm*, *Machine Constraints*, *naked*; LLVM inline-asm documentation; DWARF 5 §6.4 (Call Frame Information).
>
> **Verification:** every *Codegen (verified)* listing was compiled with Clang 21.1.0 on 2026-10-26 ([method](../README.md#verification-method--read-this-before-trusting-a-listing)). The `.S` file was assembled for AArch64. The unwinder was run natively. GCC-specific statements are marked ⚠ verify.

---

## 0. The thesis

A calling convention is the **only contract between code the compiler can see and code it cannot**: other translation units, other compilers, hand-written assembly, the hardware's exception-entry logic, debuggers, and unwinders. The compiler checks none of it across the boundary. Every rule broken at the boundary shows up somewhere else, later:

- a callee-saved register corrupted three frames up;
- a `printf("%f")` that prints garbage only in RTOS tasks;
- a backtrace that stops at a tail call;
- a crash dump whose return addresses carry PAC bits.

Inline assembly is the same boundary *inside* a function. The constraints are the whole contract, because the compiler never reads the template.

---

## 1. First-Principles Hardware and ABI Mechanics

### 1.1 AAPCS64 register roles

| Register | Role | Preserved across calls? |
|---|---|---|
| `x0`–`x7` | Arguments and results | No |
| `x8` | **Indirect result location (XR)**: address where the callee writes a large return value | No |
| `x9`–`x15` | Temporaries | No |
| `x16` (IP0), `x17` (IP1) | Intra-procedure-call scratch, used by linker veneers and PLT stubs. Under BTI, `BR x16`/`BR x17` may land on a `BTI c` pad, which is how PLT stubs remain BTI-compatible | No |
| `x18` | **Platform register.** Reserved on Apple and Windows; used for the Shadow Call Stack on Linux/Android when enabled; otherwise a temporary | Platform-defined |
| `x19`–`x28` | Callee-saved | **Yes** |
| `x29` (FP) | Frame pointer: points at the current frame record | **Yes** |
| `x30` (LR) | Link register, written by `BL`/`BLR` | Saved by any non-leaf callee |
| `SP` | Stack pointer, **16-byte aligned** | **Yes** |
| `v0`–`v7` | FP/SIMD arguments and results | No |
| `v8`–`v15` | **Only the low 64 bits (`d8`–`d15`) are callee-saved** | Low half only |
| `v16`–`v31` | Temporaries | No |
| SVE `z0`–`z31`, `p0`–`p15` | All caller-saved for base-PCS functions, *except* the low 64 bits of `z8`–`z15` (which alias `d8`–`d15`). SVE-PCS functions have their own rules | Mostly no |
| `NZCV`, `FPSR` | Not preserved. `FPCR` rounding and exception-trap settings are expected to be preserved by convention | No |

The "low 64 bits of `v8`–`v15`" rule catches hand-written NEON code in two ways. A callee that uses `q8` as a full 128-bit register must save only `d8`, because the caller can't rely on the upper half. And a *caller* that keeps a 128-bit value in `q8` across a call has lost its upper half.

### 1.2 How arguments are assigned (AAPCS64 §6.8, simplified)

The algorithm walks the arguments left to right with three counters:

- **NGRN**, the next general register number (`x0`–`x7`);
- **NSRN**, the next SIMD/FP register (`v0`–`v7`);
- **NSAA**, the next stacked argument address.

1. **Homogeneous Floating-point/Short-vector Aggregates** (HFA/HVA: 1–4 members of the same FP or vector type) go in consecutive `v` registers if enough remain. Otherwise they go on the stack, and NSRN is set to 8.
2. **Composites larger than 16 bytes** (that are not HFA/HVA) are copied by the caller to memory and passed **by reference** in the next GPR.
3. **Composites of 16 bytes or less** go in one or two GPRs. If the composite's alignment is 16, NGRN is first rounded up to an even number. If too few GPRs remain, the whole composite goes on the stack and NGRN is set to 8: a composite is never split between registers and stack.
4. Integers and pointers take one GPR; `__int128` takes an even-odd pair.
5. **Results** follow the first-argument rules: `x0`/`x1` for up to 16 bytes, `v0`–`v3` for an HFA. Anything else is returned through memory at the address the caller put in **`x8`**.

Source:

```c
#include <stdint.h>
struct big   { uint64_t a, b, c; };          /* 24 bytes: > 16 -> indirect result (x8) */
struct small { uint64_t a; uint32_t b; };    /* 16 bytes: returned in x0:x1 */
struct vec3  { float x, y, z; };             /* HFA of 3 floats -> s0..s2 */
extern int  ext_work(int);
extern void ext_u64(int a, uint64_t b);
struct big   make_big(uint64_t v)   { struct big r = { v, v + 1u, v + 2u }; return r; }
struct small make_small(uint64_t v) { struct small r = { v, (uint32_t)v }; return r; }
float dot3(struct vec3 a, struct vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
int leaf_add(int a, int b) { return a + b; }
int nonleaf_keep(int a, int b) {
    int t = ext_work(a);          /* b must survive the call -> callee-saved reg */
    return t + ext_work(b) + b;
}
void call_u64(void) { ext_u64(1, 0x1122334455667788ull); }
int tail_call(int x) { return ext_work(x + 1); }
```

**Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-linux-gnu`):**

```asm
.LCPI0_0:
	.xword	1
	.xword	2
make_big:
	adrp	x9, .LCPI0_0
	dup	v0.2d, x0
	str	x0, [x8]
	ldr	q1, [x9, :lo12:.LCPI0_0]
	add	v0.2d, v0.2d, v1.2d
	stur	q0, [x8, #8]
	ret
make_small:
	mov	w1, w0
	ret
dot3:
	fmul	s1, s1, s4
	fmadd	s0, s0, s3, s1
	fmadd	s0, s2, s5, s0
	ret
leaf_add:
	add	w0, w1, w0
	ret
nonleaf_keep:
	stp	x29, x30, [sp, #-32]!
	stp	x20, x19, [sp, #16]
	mov	x29, sp
	mov	w19, w1
	bl	ext_work
	mov	w20, w0
	mov	w0, w19
	bl	ext_work
	add	w8, w20, w19
	ldp	x20, x19, [sp, #16]
	add	w0, w8, w0
	ldp	x29, x30, [sp], #32
	ret
call_u64:
	mov	x1, #30600
	mov	w0, #1
	movk	x1, #21862, lsl #16
	movk	x1, #13124, lsl #32
	movk	x1, #4386, lsl #48
	b	ext_u64
tail_call:
	add	w0, w0, #1
	b	ext_work
```

Each function proves one rule:

- **`make_big`**: the 24-byte result is written through **`x8`** (`str x0, [x8]`, `stur q0, [x8, #8]`). The callee never allocates the result; the caller did. The vectorizer even computed `v+1, v+2` as one 128-bit `add`.
- **`make_small`**: a 16-byte result in **`x0:x1`**. `x0` already holds `a = v`, so only `w1 = (uint32_t)v` is needed (the upper half of `x1` is padding).
- **`dot3`**: two 3-float HFAs arrive in **`s0`–`s2`** and **`s3`–`s5`**. No GPRs are involved.
- **`nonleaf_keep`**: the frame record `stp x29, x30, [sp, #-32]!` with `mov x29, sp`, plus `b` kept alive across the call in callee-saved **`w19`**, and the first result in `w20`. Both are saved and restored by this function because they're callee-saved.
- **`call_u64` / `tail_call`**: sibling calls become `b`, not `bl`. No frame is pushed, so the callee returns directly to *our* caller (§1.10).

### 1.3 AAPCS32 (Cortex-M, Cortex-A in AArch32): the same source

Rules that differ from AAPCS64:

- `r0`–`r3` carry arguments and results.
- `r4`–`r8`, `r10`, `r11` are callee-saved. `r9` is the platform register (static base or TLS on some platforms).
- `r12` (IP) is scratch for veneers.
- **SP must be 8-byte aligned at public interfaces** (4-byte at all times).
- **64-bit arguments occupy an even-odd register pair** (`r0:r1` or `r2:r3`), skipping a register if needed.
- **Composites larger than 4 bytes are returned through memory**: the caller passes the destination in `r0`, which shifts every argument by one.
- Hard-float (VFP) variant: `s0`–`s15` / `d0`–`d7` carry FP arguments and results; `s16`–`s31` / `d8`–`d15` are callee-saved.

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7, `thumbv7em-none-eabihf`):**

```asm
make_big:
	adds	r1, r2, #1
	str	r1, [r0, #8]
	adc	r1, r3, #0
	str	r1, [r0, #12]
	adds	r1, r2, #2
	str	r1, [r0, #16]
	strd	r2, r3, [r0]
	adc	r1, r3, #0
	str	r1, [r0, #20]
	bx	lr
make_small:
	strd	r2, r3, [r0]
	str	r2, [r0, #8]
	movs	r1, #0
	str	r1, [r0, #12]
	bx	lr
dot3:
	vmul.f32	s4, s1, s4
	vfma.f32	s4, s0, s3
	vfma.f32	s4, s2, s5
	vmov.f32	s0, s4
	bx	lr
leaf_add:
	add	r0, r1
	bx	lr
nonleaf_keep:
	push	{r4, r5, r7, lr}
	mov	r4, r1
	bl	ext_work
	mov	r5, r0
	mov	r0, r4
	bl	ext_work
	adds	r1, r5, r4
	add	r0, r1
	pop	{r4, r5, r7, pc}
call_u64:
	movw	r2, #30600
	movw	r3, #13124
	movt	r2, #21862
	movt	r3, #4386
	movs	r0, #1
	b	ext_u64
tail_call:
	adds	r0, #1
	b	ext_work
```

Each function proves one rule:

- **`make_big` and `make_small`**: the hidden result pointer is **`r0`**. The `uint64_t v` argument therefore can't go in `r1:r2`, because 64-bit values need an *even* pair. It arrives in **`r2:r3`**, and **`r1` is skipped**. `make_small` is "small" on AArch64, but at 16 bytes it is larger than 4, so on AAPCS32 it is returned through memory.
- **`call_u64`**: `ext_u64(1, 0x1122…)` puts `1` in `r0`, **skips `r1`**, and puts the 64-bit constant in **`r2:r3`**. Hand-written assembly that expects `b` in `r1:r2` reads garbage.
- **`nonleaf_keep`**: `push {r4, r5, r7, lr}` saves *four* registers. `r7` isn't used: it's pushed to keep SP **8-byte aligned** (an even register count).
- **`dot3`**: on the hard-float ABI, HFAs go in `s0`–`s5`, the same idea as AAPCS64.

### 1.4 System V x86-64 and Windows x64: the same source

SysV x86-64:
- Integer arguments in `rdi, rsi, rdx, rcx, r8, r9`; FP arguments in `xmm0`–`xmm7`.
- Results in `rax`/`rdx` and `xmm0`/`xmm1`.
- Callee-saved: `rbx, rbp, r12–r15`.
- `rsp` is 16-byte aligned *before* the `call`.
- Aggregates of 16 bytes or less are classified per eightbyte (INTEGER/SSE); larger ones go through memory.
- **128-byte red zone** (§1.8).

**Codegen (verified — Clang 21.1.0, `-O2`, `x86_64-linux-gnu`):**

```asm
make_big:
	movq	%rdi, %rax
	movq	%rsi, (%rdi)
	leaq	1(%rsi), %rcx
	movq	%rcx, 8(%rdi)
	addq	$2, %rsi
	movq	%rsi, 16(%rdi)
	retq
make_small:
	movq	%rdi, %rax
	movl	%eax, %edx
	retq
dot3:
	movaps	%xmm0, %xmm4
	mulps	%xmm2, %xmm4
	shufps	$85, %xmm4, %xmm4
	mulss	%xmm2, %xmm0
	addss	%xmm4, %xmm0
	mulss	%xmm3, %xmm1
	addss	%xmm1, %xmm0
	retq
leaf_add:
	leal	(%rdi,%rsi), %eax
	retq
nonleaf_keep:
	pushq	%rbp
	pushq	%rbx
	pushq	%rax
	movl	%esi, %ebx
	callq	ext_work@PLT
	movl	%eax, %ebp
	movl	%ebx, %edi
	callq	ext_work@PLT
	addl	%ebx, %ebp
	addl	%ebp, %eax
	addq	$8, %rsp
	popq	%rbx
	popq	%rbp
	retq
call_u64:
	movabsq	$1234605616436508552, %rsi
	movl	$1, %edi
	jmp	ext_u64@PLT
tail_call:
	addl	$1, %edi
	jmp	ext_work@PLT
```

- **`make_big`**: hidden pointer in `rdi`, and the callee **returns it in `rax`** (a SysV requirement that AAPCS64's `x8` convention doesn't have).
- **`make_small`**: two INTEGER eightbytes in `rax:rdx`.
- **`dot3`**: the 12-byte `vec3` is classified as two SSE eightbytes. `(x, y)` is packed into `xmm0` and `z` into `xmm1`, and the second argument in `xmm2`/`xmm3`. Note `shufps $85` (`0x55`), which broadcasts lane 1 (`a.y·b.y`).
- **`nonleaf_keep`**: `pushq %rax` is a dummy push that restores 16-byte alignment before the calls.

**Windows x64 differs on every axis that matters for crash dumps:**
- Arguments go in `rcx, rdx, r8, r9`, and the caller allocates a **32-byte shadow space**.
- `rsi`/`rdi` and `xmm6`–`xmm15` are callee-saved.
- There is **no red zone**.
- Unwinding uses `.pdata`/`.xdata` tables, so the frame pointer need not point at a `{saved rbp, return address}` record.

**Codegen (verified — Clang 21.1.0, `-O2 -fno-omit-frame-pointer`, `x86_64-windows-gnu`):**

```asm
level2:
	pushq	%rbp
	subq	$32, %rsp
	leaq	32(%rsp), %rbp
	callq	level3
	addl	%eax, %eax
	addq	$32, %rsp
	popq	%rbp
	retq
level3:
	pushq	%rbp
	pushq	%rsi
	subq	$56, %rsp
	leaq	48(%rsp), %rbp
	movl	%ecx, %esi
	movq	$0, -8(%rbp)
	movq	$0, (%rbp)
	leaq	-8(%rbp), %rcx
	movq	%rbp, %rdx
	callq	*__imp_GetCurrentThreadStackLimits(%rip)
```

In `level3`, `rbp = rsp + 48` sits **in the middle of the frame**, and `(%rbp)` holds a *local variable*. A `[rbp] → saved rbp` chain walk on Win64 reads garbage. We hit exactly this while building this file's unwinder self-test. Frame-pointer unwinding is an **AAPCS64 and SysV** property, not an x86 property.

### 1.5 RISC-V and Apple arm64, briefly

- **RISC-V psABI (LP64D):**
  - `a0`–`a7` arguments, `a0`/`a1` results; `fa0`–`fa7` for FP.
  - `s0`–`s11` and `fs0`–`fs11` callee-saved (`s0` doubles as the frame pointer); `t0`–`t6` and `ft0`–`ft11` temporaries.
  - `sp` 16-byte aligned. `gp` and `tp` are fixed. No red zone.
- **Apple arm64** (deviations from AAPCS64, all relevant to shared code):
  - `x18` is reserved; never touch it.
  - `x29` must *always* hold a valid frame record.
  - `char` is signed and `long double` is 8 bytes (both verified in File 02).
  - Stacked arguments use their natural size and alignment instead of 8-byte slots.
  - The **caller** sign- or zero-extends sub-32-bit arguments (the callee may rely on it; AAPCS64 leaves the upper bits unspecified).
  - **Variadic arguments always go on the stack** (§1.6).
  - A **128-byte red zone** below SP is available to leaf code.

### 1.6 Variadic functions: three ABIs, three wire formats

```c
extern void log_fmt(const char *fmt, ...);
void call_variadic(int code, double v) { log_fmt("code=%d v=%f", code, v); }
```

**Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-linux-gnu`):**

```asm
call_variadic:
	mov	w1, w0
	adrp	x0, .L.str
	add	x0, x0, :lo12:.L.str
	b	log_fmt
```

**Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-macos`, comments removed):**

```asm
_call_variadic:
	sub	sp, sp, #32
	stp	x29, x30, [sp, #16]
	add	x29, sp, #16
	str	d0, [sp, #8]
	str	x0, [sp]
Lloh0:
	adrp	x0, l_.str@PAGE
Lloh1:
	add	x0, x0, l_.str@PAGEOFF
	bl	_log_fmt
	ldp	x29, x30, [sp, #16]
	add	sp, sp, #32
	ret
```

- **AAPCS64 (Linux):** variadic arguments use the same registers as named ones. `code` moves to `w1` and `v` stays in `d0`, which makes a tail call possible. The callee's `va_start` spills `x0`–`x7` and `q0`–`q7` into a save area, and `va_list` is a five-field struct:
  ```c
  typedef struct {
      void *__stack;     /* next stacked argument                       */
      void *__gr_top;    /* end of the general-register save area       */
      void *__vr_top;    /* end of the FP/SIMD-register save area       */
      int   __gr_offs;   /* negative offset from __gr_top to next GP arg */
      int   __vr_offs;   /* negative offset from __vr_top to next FP arg */
  } va_list;             /* AAPCS64 Appendix: Variable argument lists    */
  ```
- **Apple arm64:** every anonymous argument goes in **8-byte stack slots** (`str x0, [sp]`, `str d0, [sp, #8]`), and `va_list` is a plain `char *`.
- **Windows on ARM64:** variadic FP arguments are passed in **integer** registers, and the callee home-spills `x0`–`x7` (⚠ verify against the Microsoft ARM64 ABI document).
- **SysV x86-64:** the caller sets **`%al`** to an upper bound on the number of vector registers used. A variadic callee that trusts a garbage `%al` may skip saving `xmm` registers.
- **AAPCS32 hard-float:** variadic functions use the **base (soft-float) standard**, so `double` varargs go in core registers or on the stack, not in `d0`.

The consequence: **calling a variadic function through a non-variadic prototype, or the reverse, is UB that actually breaks** on Apple arm64, AArch32 hard-float and x86-64. The classic case is a function pointer cast to `void (*)(const char *, int, double)` and pointed at `printf`. C23 removed unprototyped function declarations: `void f()` now means `void f(void)`, which turns many of these mismatches into compile errors. Build legacy code with `-Wstrict-prototypes -Wmissing-prototypes` (part of this KB's warning set).

### 1.7 Stack frames and the frame-record chain

On AAPCS64 a non-leaf function that keeps a frame pointer creates a **frame record**: two adjacent 64-bit words `{caller's x29, x30}`. It sets `x29` to point at it. The records form a linked list through the stack:

```text
 high addresses
 ┌──────────────────────────────┐
 │ caller's locals / spills     │
 ├──────────────────────────────┤ ◄── caller's x29
 │ [x29+8] caller's LR          │
 │ [x29+0] caller's caller's FP │
 ├──────────────────────────────┤
 │ our callee-saved x19, x20    │   (stp x20, x19, [sp, #16])
 ├──────────────────────────────┤ ◄── our x29 (= SP after "mov x29, sp")
 │ [x29+8] our LR  (x30)        │   return address into caller
 │ [x29+0] caller's x29         │   link to the previous record
 └──────────────────────────────┘ ◄── SP (16-byte aligned)
 low addresses
```

Walking the chain needs no DWARF, no symbol tables, and no heap. That is why the Linux arm64 kernel unwinds through frame records (the arm64 kernel is built with frame pointers; ⚠ verify `CONFIG_FRAME_POINTER` handling in your tree), and why panic handlers prefer them. Defaults vary:

- Clang's default for `aarch64-linux` is `-mframe-pointer=non-leaf` (verified from the driver's `-###` output).
- Apple *requires* frame pointers.
- GCC on AArch64 traditionally omitted them at `-O2` (⚠ verify for your release).
- Several Linux distributions now build packages with `-fno-omit-frame-pointer` for profiling (⚠ verify).

On Cortex-M, frame pointers are usually omitted (verified listings above: no `r7` frame setup). Crash handlers then unwind by DWARF CFI, or heuristically (Folder 07).

### 1.8 SP alignment, and what hardware does when you break it

| Architecture | Rule | Enforcement |
|---|---|---|
| AArch64 | SP 16-byte aligned (AAPCS64) | `SCTLR_ELx.SA` (EL1) and `SA0` (EL0): any SP-based load or store with a misaligned SP raises an **SP alignment fault**, ESR EC `0x26`. Linux enables both |
| AArch32 / Cortex-M | 8-byte aligned at public interfaces, 4 at all times | No hardware check on calls. But `LDRD`/`STRD` and FP double accesses compiled under the 8-byte assumption misbehave if a task stack is only 4-aligned |
| Cortex-M exception entry | Hardware realigns the stacked frame to 8 bytes if `CCR.STKALIGN = 1` (reset default on M3 r2p0+, M4, M7; RES1 on ARMv8-M), recording the pad in stacked **xPSR bit 9** | Automatic |
| x86-64 | `rsp + 8` 16-aligned at function entry | `movaps` to a misaligned stack slot raises `#GP`; a classic crash in hand-written entry stubs |

The Cortex-M field bug: an RTOS creates a task with a stack top that is only 4-aligned. It runs fine until the first `printf("%f", x)`. Here is the mechanism:

1. AAPCS32 places a variadic `double` at an 8-byte-aligned slot in the argument area. The *caller* computes that slot as an offset from an SP it assumes is 8-aligned.
2. Because SP is really 4 mod 8, the `double` lands at an absolute address that is 4 mod 8.
3. The *callee's* `va_arg(ap, double)` rounds the absolute pointer up to 8, skips 4 bytes, and reads half of the `double` and half of the next argument.

Nothing faults, because `LDRD` on ARMv7-M needs only word alignment, so the output is silently garbage. The fix is to align every task stack top to 8 bytes (FreeRTOS's `portBYTE_ALIGNMENT` is 8 on Cortex-M) and assert it when the task is created.

### 1.9 The red zone 🔥

**System V x86-64 defines a 128-byte red zone below `%rsp`.** Leaf functions may use it without adjusting `rsp`. The ABI promises that signal and interrupt handlers won't clobber it: Linux places the signal frame below it. Source:

```c
#include <stdint.h>
uint32_t leaf_sum_locals(const uint32_t *src) {
    volatile uint32_t tmp[8];            /* volatile forces a real stack buffer */
    for (unsigned i = 0; i < 8u; i++) tmp[i] = src[i] * 3u;
    uint32_t s = 0;
    for (unsigned i = 0; i < 8u; i++) s += tmp[i];
    return s;
}
```

**Codegen (verified — Clang 21.1.0, `-O2 -fno-vectorize -fno-unroll-loops`, `x86_64-linux-gnu`):**

```asm
leaf_sum_locals:
	xorl	%eax, %eax
.LBB0_1:
	movl	(%rdi,%rax,4), %ecx
	leal	(%rcx,%rcx,2), %ecx
	movl	%ecx, -40(%rsp,%rax,4)
	addq	$1, %rax
	cmpq	$8, %rax
	jne	.LBB0_1
	xorl	%ecx, %ecx
	xorl	%eax, %eax
.LBB0_3:
	addl	-40(%rsp,%rcx,4), %eax
	addq	$1, %rcx
	cmpq	$8, %rcx
	jne	.LBB0_3
	retq
```

**With `-mno-red-zone` (verified, first lines):**

```asm
leaf_sum_locals:
	subq	$40, %rsp
	xorl	%eax, %eax
.LBB0_1:
	movl	(%rdi,%rax,4), %ecx
	leal	(%rcx,%rcx,2), %ecx
```

The buffer lives at `-40(%rsp)`, **below** the stack pointer, and `rsp` is never moved. That is legal in user space. In the **kernel** it is fatal. An interrupt or exception taken at CPL0 without a stack switch pushes its hardware frame (`SS, RSP, RFLAGS, CS, RIP`, plus an error code) at `rsp`, straight over the red zone. That's why the Linux x86-64 kernel, every x86 hypervisor, and UEFI code are built with **`-mno-red-zone`**.

| ABI | Red zone |
|---|---|
| SysV x86-64 | 128 bytes |
| Windows x64 | None (it has the 32-byte shadow space *above* the return address instead) |
| AAPCS64 (Linux, bare metal) | **None** |
| Apple arm64 | 128 bytes (leaf code may use it) |
| AAPCS32 / Cortex-M | **None.** An exception may be taken at any instruction boundary, and the hardware pushes 32 bytes (basic frame) or 104 bytes (with FP context) **at SP**. Anything stored below SP is destroyed |
| RISC-V psABI | None |

On Cortex-M the rule is absolute and hardware-enforced: **never store below SP**, and never move SP up past live data in hand-written code. The NVIC can stack an exception frame there between any two instructions.

### 1.10 Tail calls and their cost to debugging

All three ISAs turned `return ext_work(x + 1);` into a jump (`b ext_work` / `jmp ext_work@PLT`, verified). The callee returns straight to *our* caller, so **our frame never appears in a backtrace**. In a crash dump, a function that "can't possibly call" the faulting function shows up as the caller. Options:

- `-fno-optimize-sibling-calls` in debug or diagnostic builds.
- Clang's `__attribute__((musttail))` on a `return` statement forces the tail call and makes failure a compile error, which matters for interpreter dispatch loops. GCC 15 adds the same attribute (⚠ verify).
- Crash handlers must treat "LR's function doesn't call PC's function" as normal, not as corruption.

### 1.11 Stack protection and control-flow integrity

#### 1.11.1 Stack canaries (`-fstack-protector-strong`)

Source:

```c
#include <string.h>
extern void consume(char *buf);
extern int  ext_work(int);
int nonleaf(int a) { return ext_work(a) + 1; }
void with_array(const char *s) { char buf[32]; strcpy(buf, s); consume(buf); }
```

**Codegen (verified — Clang 21.1.0, `-O2 -fstack-protector-strong`, `aarch64-none-elf`, function `with_array`):**

```asm
with_array:
	sub	sp, sp, #64
	adrp	x8, __stack_chk_guard
	stp	x29, x30, [sp, #48]
	add	x29, sp, #48
	ldr	x8, [x8, :lo12:__stack_chk_guard]
	mov	x1, x0
	add	x0, sp, #8
	stur	x8, [x29, #-8]
	bl	strcpy
	add	x0, sp, #8
	bl	consume
	adrp	x8, __stack_chk_guard
	ldur	x9, [x29, #-8]
	ldr	x8, [x8, :lo12:__stack_chk_guard]
	cmp	x8, x9
	b.ne	.LBB1_2
	ldp	x29, x30, [sp, #48]
	add	sp, sp, #64
	ret
.LBB1_2:
	bl	__stack_chk_fail
```

**Codegen (verified — same flags, Cortex-M7):**

```asm
with_array:
	push	{r7, lr}
	sub	sp, #40
	movw	r2, :lower16:__stack_chk_guard
	mov	r1, r0
	movt	r2, :upper16:__stack_chk_guard
	add	r0, sp, #4
	ldr	r2, [r2]
	str	r2, [sp, #36]
	bl	strcpy
	bl	consume
	movw	r0, :lower16:__stack_chk_guard
	ldr	r1, [sp, #36]
	movt	r0, :upper16:__stack_chk_guard
	ldr	r0, [r0]
	cmp	r0, r1
	itt	eq
	addeq	sp, #40
	popeq	{r7, pc}
.LBB1_1:
	bl	__stack_chk_fail
```

The canary sits between `buf` and the saved `x29`/`x30` (`[x29, #-8]`) or the saved `lr` (`[sp, #36]`). An overflow of `buf` that reaches the return address must first overwrite the canary. On bare metal **you** provide both symbols:

```c
#include <stdint.h>
uintptr_t __stack_chk_guard;                 /* seeded from the TRNG before any protected
                                                function that will later return is entered */
_Noreturn void __stack_chk_fail(void);
_Noreturn void __stack_chk_fail(void)
{
    /* Log PC/LR to .noinit (Folder 07), then reset. Never return. */
    for (;;) { }
}
```

The seeding-order trap: if `main()` is protected and you seed the guard *inside* `main`, the canary `main` stored on entry no longer matches when `main` returns, and you get a false positive. Seed the guard in `Reset_Handler` before calling anything protected, or compile the early-boot translation unit with `-fno-stack-protector`.

#### 1.11.2 Shadow Call Stack (Clang, AArch64)

**Codegen (verified — Clang 21.1.0, `-O2 -ffixed-x18 -fsanitize=shadow-call-stack`, `aarch64-none-elf`):**

```asm
nonleaf:
	str	x30, [x18], #8
	stp	x29, x30, [sp, #-16]!
	mov	x29, sp
	bl	ext_work
	add	w0, w0, #1
	ldp	x29, x30, [sp], #16
	ldr	x30, [x18, #-8]!
	ret
```

The return address is pushed to a **separate stack addressed by `x18`**, and reloaded from there before `ret`. A linear stack overflow can overwrite the copy in the frame record, but not the one that is actually used. Without `-ffixed-x18` the backend refuses: `fatal error: error in backend: Must reserve x18 to use shadow call stack` (verified). Android and the Linux arm64 kernel (`CONFIG_SHADOW_CALL_STACK`) use it. The SCS region must be kept secret (its address must not leak), because SCS defends against overwrites, not against arbitrary writes.

#### 1.11.3 PAC-RET, BTI and GCS (`-mbranch-protection=standard`)

**Codegen (verified — Clang 21.1.0, `-O2 -mbranch-protection=standard`, `aarch64-linux-gnu`):**

```asm
nonleaf:
	hint	#25
	stp	x29, x30, [sp, #-16]!
	mov	x29, sp
	bl	ext_work
	add	w0, w0, #1
	ldp	x29, x30, [sp], #16
	hint	#29
	ret
```

- **`hint #25` = `PACIASP`.** It signs `x30` with key A, using SP as the modifier, and stores a Pointer Authentication Code in the unused top bits. **`hint #29` = `AUTIASP`** authenticates before `ret`. They're encoded in the HINT space, so cores without FEAT_PAuth execute them as NOPs and one binary runs everywhere.
- On authentication failure, a core with **FEAT_FPAC** faults at the `AUT` (ESR EC `0x1C`). Without FPAC, `AUT` corrupts the pointer's top bits so that the `ret` takes a translation fault, typically with a non-canonical PC in the oops.
- **BTI:** `hint #34` = `BTI c` marks valid targets for indirect *calls*; `BTI j` (#36) marks indirect *jump* targets. `PACIASP` doubles as a `BTI c` landing pad. On pages mapped as *guarded* (the GP bit in the stage-1 descriptor), an indirect branch to any other instruction raises a **Branch Target exception** (ESR EC `0x0D`).
- **The property note.** The linker marks an executable BTI/PAC-compatible only if *every* input object carries a `.note.gnu.property` with `GNU_PROPERTY_AARCH64_FEATURE_1_AND`. Clang 21 emitted the note itself with value **7** = BTI (1) | PAC (2) | **GCS (4)**, verified from the `fp_unwind.c` build. In this Clang release, "standard" includes the Guarded Control Stack bit. **GCS** (FEAT_GCS, Armv9.4-A) is a hardware-protected shadow stack: `BL` pushes, `RET` checks. Linux user-space support landed in the 6.13 era (⚠ verify). Hand-written `.S` files must emit the note themselves (§2.6). **One object without it silently disables BTI for the whole executable.**

In the unwinder blueprint (§3.3) the compiler placed `BTI c` at entry but **shrink-wrapped** `PACIASP` into the slow path, after the early-exit checks. Signing happens only on paths that actually spill `x30`.

#### 1.11.4 Hardware stack limits on Cortex-M

- **ARMv8-M (M23/M33/M55/M85)** adds `MSPLIM` and `PSPLIM`. Any push below the limit raises a UsageFault with `CFSR.STKOF` (bit 20), *before* the overflow corrupts memory. RTOS ports set `PSPLIM` on every context switch.
- **ARMv7-M** has no limit registers. Use an **MPU guard region** (a no-access region of at least 32 bytes) below each stack. An overflow then raises a MemManage fault with `MSTKERR` if it happens during exception stacking. Folder 02 covers the MPU.

### 1.12 Stack-usage analysis

**`-fstack-usage` (verified, Clang 21.1.0, Cortex-M7, file `prot.su`):**

```text
prot.c:4:nonleaf	8	static
prot.c:5:with_array	40	static
```

The qualifiers mean:
- `static`: a compile-time constant frame size.
- `dynamic`: uses `alloca` or VLAs.
- `bounded`: dynamic, but with a known maximum.

Worst-case stack depth is the maximum over call paths of the summed frame sizes, plus exception frames: 32 or 104 bytes per nesting level on Cortex-M, times the number of preemption levels. Tools:
- GCC `-fcallgraph-info=su` emits a call graph annotated with frame sizes.
- `puncover` combines `.su` files with the ELF.
- AbsInt StackAnalyzer works on the binary, including function pointers, given annotations.
- At runtime, **stack painting** fills the stack with a pattern (FreeRTOS uses `0xA5`) and scans for the high-water mark (`uxTaskGetStackHighWaterMark`).

### 1.13 Interrupt handlers on Cortex-M are plain AAPCS functions

On exception entry, ARMv6-M/v7-M/v8-M hardware pushes **`R0`–`R3`, `R12`, `LR`, `PC`, `xPSR`**: exactly the AAPCS32 *caller-saved* set plus the return state. It then loads `LR` with an `EXC_RETURN` value (Folder 04). A plain C function therefore *is* a correct ISR. The callee-saved registers are preserved by the normal prologue, and `bx lr` with `EXC_RETURN` triggers the hardware unstacking.

```c
#include <stdint.h>
extern volatile uint32_t g_ticks;
void SysTick_Handler(void) { g_ticks++; }
__attribute__((interrupt("IRQ"))) void TIM2_IRQHandler(void) { g_ticks += 2u; }
```

**Diagnostic and codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7):**

```text
isr.c:4:40: warning: interrupt service routine with vfp enabled may clobber the interruptee's vfp state; consider using the `interrupt_save_fp` attribute to prevent this behavior [-Warm-interrupt-vfp-clobber]
```

```asm
SysTick_Handler:
	movw	r0, :lower16:g_ticks
	movt	r0, :upper16:g_ticks
	ldr	r1, [r0]
	adds	r1, #1
	str	r1, [r0]
	bx	lr
TIM2_IRQHandler:
	push	{r4, r6, r7, lr}
	add	r7, sp, #8
	mov	r4, sp
	bfc	r4, #0, #3
	mov	sp, r4
	movw	r0, :lower16:g_ticks
	sub.w	r4, r7, #8
	movt	r0, :upper16:g_ticks
	ldr	r1, [r0]
	adds	r1, #2
	str	r1, [r0]
	mov	sp, r4
	pop	{r4, r6, r7, pc}
```

**Don't use `__attribute__((interrupt))` on M-profile.** It made Clang:

- realign SP to 8 bytes in software (`bfc r4, #0, #3`), which the hardware already did (`CCR.STKALIGN`);
- add a frame setup;
- warn about VFP state, which on M-profile is handled by hardware lazy stacking (`FPCCR.LSPEN`).

Seven extra instructions on every interrupt bought nothing. GCC's documentation says that on ARMv7-M the interrupt *type* is ignored and the attribute only means "may be called with a word-aligned SP" (⚠ verify wording for your GCC). The attribute exists for **A/R-profile AArch32** IRQ/FIQ modes, where hardware stacks nothing. On AArch64, exception vectors must be assembly that saves `x0`–`x18`, `x29`, `x30`, `ELR_ELx` and `SPSR_ELx` before calling C (Folder 04).

---

## 2. Inline Assembly: The Constraint Is the Contract

### 2.1 Semantics in one paragraph

```c
__asm__ [volatile] [goto] ( "template"
        : outputs                  /* "=r"(x) write-only, "+r"(x) read-write, "=&r"(x) early clobber */
        : inputs                   /* "r"(y), "i"(CONST), "Q"(*p) ...                               */
        : clobbers                 /* "memory", "cc", "x9", "r12" ...                               */
        : goto_labels );           /* asm goto only                                                 */
```

The compiler **never parses the template**. It sees only:

1. which values go in and come out, and in what kind of location;
2. whether outputs may share registers with inputs;
3. what else is destroyed;
4. whether the statement has side effects beyond its outputs (`volatile`).

Everything you leave out, the optimizer assumes is untouched. GCC's documentation says so explicitly: even `volatile` asm may be moved relative to other code, including across jumps, unless dependencies (operands or a `"memory"` clobber) pin it. Asm statements with no outputs, and all `asm goto`, are implicitly `volatile`.

### 2.2 Constraint and modifier quick reference

**AArch64:**

| Constraint / modifier | Meaning |
|---|---|
| `r` | General register `x0`–`x30` |
| `w` | FP/SIMD register `v0`–`v31` |
| `x` | FP/SIMD register `v0`–`v15` (needed for by-element operands of some instructions) |
| `Q` | Memory addressed by a **single base register with no offset**: what `LDXR`/`STXR`/`LDAR`/`STLR` accept |
| `m` | Any memory operand (may include an offset, so **wrong** for exclusives) |
| `I`, `J`, `K`, `L`, `M`, `N` | Immediate classes (`add`/`sub` imm, logical imm 32/64, `mov` imm) |
| `%w0` / `%x0` | Print operand 0 as `wN` / `xN` |
| `%s0` `%d0` `%q0` | Print an FP/SIMD operand as `sN`/`dN`/`qN` |
| `%l[label]` | A goto label (`asm goto`) |

**AArch32 / Thumb-2:**

| Constraint / modifier | Meaning |
|---|---|
| `r` | `r0`–`r14` (as allowed) |
| `l` | Low registers `r0`–`r7` (Thumb 16-bit encodings) |
| `h` | High registers `r8`–`r15` |
| `t` / `w` | VFP single (`s0`–`s31`) / double (`d0`–`d31`) registers |
| `Q` | Memory addressed by a single register (exclusives) |
| `I`, `J`, `K`, `L`, `M` | Immediate classes |
| `%Q0` / `%R0` | Least / most significant register of a 64-bit operand pair |
| `%H0` | Second register of a register pair |

**x86-64:**

| Constraint / modifier | Meaning |
|---|---|
| `a b c d S D` | Specific registers (`rax`, `rbx`, `rcx`, `rdx`, `rsi`, `rdi`) |
| `r` | Any general register |
| `m` | Memory |
| `i` / `n` | Immediate |
| `=@ccz` and friends | **Flag output operands** (GCC 6+, Clang): read a condition directly without `setcc` |

Note: **GCC and Clang treat every x86 asm as clobbering the flags**; on ARM they don't.

**RISC-V:**

| Constraint | Meaning |
|---|---|
| `r` | Integer register |
| `f` | FP register |
| `I` | 12-bit signed immediate |
| `K` | 5-bit unsigned immediate |
| `A` | Address in a register (for `lr.w`/`sc.w`/AMOs) |

### 2.3 Hazard 1: missing early-clobber 🔥

```c
#include <stdint.h>
/* BUG: %0 is written before %1 is read, but no early-clobber -> may share a register. */
uint32_t scale_bad(uint32_t in) {
    uint32_t out;
    __asm__("mov %w0, #3\n\t"
            "mul %w0, %w0, %w1"
            : "=r"(out) : "r"(in));
    return out;
}
uint32_t scale_good(uint32_t in) {
    uint32_t out;
    __asm__("mov %w0, #3\n\t"
            "mul %w0, %w0, %w1"
            : "=&r"(out) : "r"(in));
    return out;
}
```

**Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-linux-gnu`):**

```asm
scale_bad:
	mov	w0, #3
	mul	w0, w0, w0
	ret
scale_good:
	mov	w8, #3
	mul	w8, w8, w0
	mov	w0, w8
	ret
```

Without `&`, the compiler is told that `out` is written only *after* all inputs are consumed. It may therefore reuse `in`'s register for `out`. Both got `w0`: `mov w0, #3` destroyed the input, and `scale_bad(5)` returns **9**, not 15. The listing looks perfectly reasonable. The bug appears only after inlining or register-pressure changes. **Rule: any output written before the last input is read must be `=&`.** That covers every output of a multi-instruction LL/SC loop.

### 2.4 Hazard 2: missing `volatile` (CSE and deletion)

```c
#include <stdint.h>
extern void work(void);
uint64_t elapsed_bad(void) {
    uint64_t t0, t1;
    __asm__("mrs %0, cntvct_el0" : "=r"(t0));      /* no volatile: "pure function of inputs" */
    work();
    __asm__("mrs %0, cntvct_el0" : "=r"(t1));
    return t1 - t0;
}
uint64_t elapsed_good(void) {
    uint64_t t0, t1;
    __asm__ volatile("isb\n\tmrs %0, cntvct_el0" : "=r"(t0) : : "memory");
    work();
    __asm__ volatile("isb\n\tmrs %0, cntvct_el0" : "=r"(t1) : : "memory");
    return t1 - t0;
}
```

**Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-linux-gnu`):**

```asm
elapsed_bad:
	stp	x29, x30, [sp, #-16]!
	mov	x29, sp
	bl	work
	mov	x0, xzr
	ldp	x29, x30, [sp], #16
	ret
elapsed_good:
	stp	x29, x30, [sp, #-32]!
	str	x19, [sp, #16]
	mov	x29, sp
	isb
	mrs	x19, CNTVCT_EL0
	bl	work
	isb
	mrs	x8, CNTVCT_EL0
	sub	x0, x8, x19
	ldr	x19, [sp, #16]
	ldp	x29, x30, [sp], #32
	ret
```

Two non-`volatile` asm statements with identical templates and no inputs are, as far as the compiler knows, **the same pure computation**. CSE merged them, `t1 - t0` folded to zero, and with nothing using the result, **both `mrs` instructions were deleted**. The benchmark reports 0 ticks. `elapsed_good` adds:

- `volatile`, so each read happens exactly where written;
- `"memory"`, so it stays ordered against surrounding memory operations;
- `isb`, so the *hardware* can't execute the counter read early. A system-register read is not ordered by program order on an out-of-order core.

### 2.5 Hazard 3: missing `"memory"` clobber ⚡

```c
#include <stdint.h>
extern int irq_seen;
void wait_irq_bad(void)  { while (!irq_seen) { __asm__ volatile("wfi"); } }
void wait_irq_good(void) { while (!irq_seen) { __asm__ volatile("wfi" ::: "memory"); } }
```

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7):**

```asm
wait_irq_bad:
	movw	r0, :lower16:irq_seen
	movt	r0, :upper16:irq_seen
.LBB0_1:
	ldr	r1, [r0]
	cbnz	r1, .LBB0_3
	wfi
	b	.LBB0_1
.LBB0_3:
	bx	lr
wait_irq_good:
	movw	r0, :lower16:irq_seen
	movt	r0, :upper16:irq_seen
.LBB1_1:
	ldr	r1, [r0]
	cbnz	r1, .LBB1_3
	wfi
	b	.LBB1_1
.LBB1_3:
	bx	lr
```

**Clang 21 reloaded `irq_seen` in both versions.** LLVM conservatively models every `asm volatile` (an `asm sideeffect` call in IR) as possibly reading and writing memory. **That is a Clang implementation choice, not a contract.** GCC's documented semantics allow it to hoist the load of `irq_seen` out of the loop when the asm has no `"memory"` clobber. That produces a sleep-forever loop that wakes on every interrupt, re-tests a stale register, and sleeps again (⚠ verify on your GCC release; the documentation is unambiguous that you may not rely on the reload). The production rule doesn't depend on which compiler you use today:

- **Every asm that has ordering meaning gets a `"memory"` clobber:** barriers, interrupt masking, sleep, cache maintenance, context switch.
- **`irq_seen` must still be `volatile` or `_Atomic`.** The clobber only forces a reload at the asm. It does not make the cross-context access race-free (File 01 §1.7).

CMSIS-Core defines `__WFI()`, `__DSB()`, `__ISB()`, `__DMB()`, `__enable_irq()` and `__disable_irq()` with `"memory"` clobbers for exactly this reason.

### 2.6 Hazard 4: flags (`"cc"`), labels, and register variables

- **`"cc"`:** if the template sets condition flags (`adds`, `subs`, `cmp`, `tst`), declare `"cc"` on ARM and RISC-V. The compiler may otherwise keep a live comparison result in NZCV across your asm. (On x86 it's implied.)
- **Labels:** a *named* label in an asm template is duplicated whenever the function is inlined or unrolled twice. The assembler rejects it (verified with the buggy header in §3.1):
  ```text
  ./cpu_bad.h:45:23: error: symbol 'done_label' is already defined
     45 |                      "done_label:" : "+r"(x));
  ```
  Use local numeric labels (`1:` with `1b`/`1f`) or GCC's `%=` unique-number substitution. The verified LL/SC loops use `1:`, which Clang's integrated assembler renamed to a unique `.Ltmp0`:
  ```asm
  llsc_fetch_add:
  .Ltmp0:
  	ldaxr	w8, [x0]
  	add	w9, w8, w1
  	stlxr	w10, w9, [x0]
  	cbnz	w10, .Ltmp0
  	mov	w0, w8
  	ret
  ```
- **Local register variables** (`register uint32_t r0 __asm__("r0") = op;`) are guaranteed to be in that register **only when used as an asm operand**, and only if nothing between the assignment and the asm can clobber them. A function call or a division (which may call a runtime helper) in between silently reassigns them. Bind them immediately before the asm, as `cpu_semihost()` in §3.2 does.

### 2.7 Hazard 5: wrong memory constraint for exclusives

`LDXR`/`STXR`/`LDAXR`/`STLXR` accept only `[Xn]`, with no offset. `"m"` lets the compiler pick `[x0, #8]`, which is an assembler error at best. **`"Q"` is the right constraint** (verified `ldaxr w8, [x0]`). The memory operand should be `"+Q"(*p)`, *both* read and written, so the compiler knows the object changes. Add `"memory"` if other memory must be ordered against the atomic.

The equivalent Thumb-2 loop (verified, Cortex-M7):

```asm
ldrex_fetch_add:
.Ltmp0:
	ldrex	r2, [r0]
	add.w	r3, r2, r1
	strex	r12, r3, [r0]
	cmp.w	r12, #0
	bne	.Ltmp0
	mov	r0, r2
	bx	lr
```

Prefer `<stdatomic.h>` or LSE (`LDADDAL`, `-march=armv8.1-a`) in production. Folder 05 covers exclusive-monitor semantics, `CLREX` on context switch, and why LL/SC loops must not contain stores or other exclusives.

### 2.8 `asm goto`

```c
static inline int cpu_is_zero_goto(uint64_t x)
{
    __asm__ goto("cbz %x0, %l[is_zero]" : : "r"(x) : : is_zero);
    return 0;
is_zero:
    return 1;
}
```

**Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-linux-gnu`, inlined into `return cpu_is_zero_goto(x) ? 7 : 9;`):**

```asm
use_goto:
	mov	x8, x0
	mov	w0, #7
	cbz	x8, .LBB2_2
	mov	w0, #9
.LBB2_2:
	ret
```

The template's `cbz` branches straight to a C label. There is no flag materialization and no compare in C. Linux *static keys* (jump labels) are built on `asm goto`: a `nop` in the template is patched at runtime into a `b` to the slow path. `asm goto` with **outputs** is supported by GCC 11+ and Clang 11+.

### 2.9 Naked functions and literal pools

```c
extern uint32_t _estack[];
extern int main(void);
__attribute__((naked, noreturn)) void Reset_Handler(void) {
    __asm__ volatile(
        "ldr r0, =_estack \n\t"
        "msr msp, r0      \n\t"
        "bl  main         \n\t"
        "b   .            \n\t");
}
```

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7, raw labels kept):**

```asm
Reset_Handler:
	ldr	r0, .Ltmp0
	msr	msp, r0
	bl	main
.Ltmp1:
	b	.Ltmp1

	.p2align	2, 0x0
.Ltmp0:
	.long	_estack
```

The compiler emitted **no prologue and no epilogue**. `ldr r0, =_estack` became a PC-relative load from a literal pool the assembler placed after the function. Rules for `naked`:

- Only **basic asm** (no operands) is reliable inside. C statements and extended asm may "work" but are unsupported (GCC documentation).
- **Hardware already loads MSP** from vector-table word 0 at reset, so explicitly setting MSP is needed only when a *bootloader jumps to an application*. That path must also disable interrupts, set `VTOR`, and issue `DSB`/`ISB` (Folder 02 builds the full sequence).

### 2.10 Prefer intrinsics where they exist

```c
#include <arm_acle.h>
#include <stdint.h>
uint32_t acle_demo(uint32_t x) { __dmb(0xF); __dsb(0xF); __isb(0xF); return __rev(x) + __clz(x); }
```

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7):**

```asm
acle_demo:
	dmb	sy
	dsb	sy
	isb	sy
	clz	r1, r0
	rev	r0, r0
	add	r0, r1
	bx	lr
```

ACLE intrinsics give the compiler full knowledge of the instruction. It can schedule `rev` and `clz` freely and treats the barriers as memory barriers. ACLE also provides `__arm_rsr`/`__arm_rsr64`/`__arm_wsr` for system registers by name. Two notes:

- **Option values matter.** `0xF` is `SY`, the only option defined on M-profile. On A-profile SMP, use `ISH` (`0xB`) for inter-core ordering and `SY`/`OSH` only for non-coherent DMA.
- Portable builtins first: `__builtin_bswap32`, `__builtin_ctz`, `__builtin_expect`, `__builtin_prefetch`. Then ACLE. Then inline asm, in one header (MISRA Dir 4.3: assembly shall be encapsulated and isolated).

---

## 3. Production Code Blueprints

### 3.1 The Subtle Buggy Way: `cpu_bad.h`

```c
/* cpu_bad.h - the inline-asm helpers that ship in too many BSPs. Each one
 * compiles without a diagnostic. Each one is wrong. */
#ifndef CPU_BAD_H
#define CPU_BAD_H

#include <stdint.h>

#if defined(__aarch64__)
/* BUG 1: no early clobber - %0 is written before %1 is read, so the register
 * allocator may give them the same register. */
static inline uint32_t bad_scale3(uint32_t in)
{
    uint32_t out;
    __asm__("mov %w0, #3\n\t"
            "mul %w0, %w0, %w1" : "=r"(out) : "r"(in));
    return out;
}

/* BUG 2: not volatile - two identical asm statements with no inputs are
 * "the same pure computation": CSE merges them, then the subtraction folds. */
static inline uint64_t bad_cycles(void)
{
    uint64_t t;
    __asm__("mrs %0, cntvct_el0" : "=r"(t));
    return t;
}
#endif

#if defined(__ARM_ARCH_PROFILE) && (__ARM_ARCH_PROFILE == 'M')
/* BUG 3: no "memory" clobber - GCC documents that memory accesses may be
 * moved across asm without it, volatile or not. */
static inline void bad_wfi(void)        { __asm__ volatile("wfi"); }
static inline void bad_irq_disable(void){ __asm__ volatile("cpsid i"); }

/* BUG 4: unconditional enable - breaks nesting: a caller that already had
 * interrupts masked gets them re-enabled inside its critical section. */
static inline void bad_irq_enable(void) { __asm__ volatile("cpsie i"); }

/* BUG 5: flags modified, "cc" not declared; named label breaks when inlined twice. */
static inline uint32_t bad_sat_inc(uint32_t x)
{
    __asm__ volatile("adds %0, %0, #1\n\t"
                     "bcc done_label\n\t"
                     "mvn %0, #0\n"
                     "done_label:" : "+r"(x));
    return x;
}
#endif

#endif /* CPU_BAD_H */
```

**Evidence (verified):**
- On AArch64 the header compiles with **zero diagnostics** under the full warning set, and bugs 1 and 2 produce the listings in §2.3/§2.4.
- On Cortex-M7, one use of `bad_sat_inc` compiles. Two inlined uses fail with `symbol 'done_label' is already defined`.
- Bugs 3–5 compile silently.
- Bug 4 is pure logic: a nested critical section whose inner exit re-enables interrupts while the outer section is still updating shared state.

### 3.2 The Silicon-Hardened Production Way: `cpu_cm.h` (Cortex-M)

```c
/* cpu_cm.h - Cortex-M (ARMv6-M / ARMv7-M / ARMv8-M) CPU primitives as inline asm
 * with complete constraints and clobbers. Every primitive is a compiler barrier
 * ("memory" clobber) because every caller relies on ordering around it. */
#ifndef CPU_CM_H
#define CPU_CM_H

#include <stdint.h>

#if !defined(__ARM_ARCH_PROFILE) || (__ARM_ARCH_PROFILE != 'M')
#error "cpu_cm.h is for M-profile targets"
#endif

/* BASEPRI exists on v7-M and v8-M Mainline, not on v6-M or v8-M Baseline. */
#if defined(__ARM_ARCH_7M__) || defined(__ARM_ARCH_7EM__) || \
    defined(__ARM_ARCH_8M_MAIN__) || defined(__ARM_ARCH_8_1M_MAIN__)
#define CPU_HAS_BASEPRI 1
#else
#define CPU_HAS_BASEPRI 0
#endif

/* Compiler-only barrier: forbids the compiler from moving memory accesses
 * across this point. Emits no instruction and orders nothing in hardware. */
static inline void cpu_compiler_barrier(void)
{
    __asm__ volatile("" : : : "memory");
}

/* Hardware barriers. On M-profile only the SY option is architecturally defined. */
static inline void cpu_dmb(void) { __asm__ volatile("dmb sy" : : : "memory"); }
static inline void cpu_dsb(void) { __asm__ volatile("dsb sy" : : : "memory"); }
static inline void cpu_isb(void) { __asm__ volatile("isb sy" : : : "memory"); }

/* Sleep until interrupt. DSB first so outstanding stores (e.g. a peripheral
 * interrupt-clear) complete before the core stops issuing. */
static inline void cpu_wfi(void)
{
    __asm__ volatile("dsb sy\n\t"
                     "wfi" : : : "memory");
}

/* Nestable critical section: save PRIMASK, mask, restore the saved value.
 * Never "cpsie i" unconditionally - that breaks a caller that was already masked. */
static inline uint32_t cpu_irq_save(void)
{
    uint32_t primask;
    __asm__ volatile("mrs %0, primask\n\t"
                     "cpsid i" : "=r"(primask) : : "memory");
    return primask;
}

static inline void cpu_irq_restore(uint32_t primask)
{
    __asm__ volatile("msr primask, %0" : : "r"(primask) : "memory");
}

#if CPU_HAS_BASEPRI
/* Priority-ceiling mask: block interrupts at priority >= ceiling (numerically
 * <=), leave higher-priority (zero-latency) interrupts running. BASEPRI_MAX
 * only ever raises the mask, so nested use is safe. `prio` is the already
 * shifted 8-bit value: (level << (8 - __NVIC_PRIO_BITS)). */
static inline uint32_t cpu_basepri_raise(uint32_t prio)
{
    uint32_t old;
    __asm__ volatile("mrs %0, basepri\n\t"
                     "msr basepri_max, %1\n\t"
                     "isb sy" : "=&r"(old) : "r"(prio) : "memory");
    return old;
}

static inline void cpu_basepri_restore(uint32_t old)
{
    __asm__ volatile("msr basepri, %0\n\t"
                     "isb sy" : : "r"(old) : "memory");
}
#endif

/* Non-zero when executing in Handler mode (IPSR holds the exception number). */
static inline uint32_t cpu_ipsr(void)
{
    uint32_t ipsr;
    __asm__ volatile("mrs %0, ipsr" : "=r"(ipsr));
    return ipsr;
}

/* ARM semihosting call (BKPT 0xAB on M-profile). r0 = operation, r1 = argument
 * block; result in r0. Local register variables are guaranteed ONLY as asm
 * operands, so they are bound immediately before the asm statement. */
static inline int32_t cpu_semihost(uint32_t op, const void *arg)
{
    register uint32_t r0 __asm__("r0") = op;
    register const void *r1 __asm__("r1") = arg;
    __asm__ volatile("bkpt 0xAB" : "+r"(r0) : "r"(r1) : "memory");
    return (int32_t)r0;
}

#endif /* CPU_CM_H */
```

A test translation unit (`use_cm.c`):

```c
#include "cpu_cm.h"
extern volatile uint32_t g_flag;
extern uint32_t g_count;
void use_critical(void);
void use_critical(void) { uint32_t k = cpu_irq_save(); g_count++; cpu_irq_restore(k); }
void use_wait(void);
void use_wait(void) { while (g_flag == 0u) { cpu_wfi(); } }
#if CPU_HAS_BASEPRI
void use_ceiling(void);
void use_ceiling(void) { uint32_t old = cpu_basepri_raise(0x40u); g_count += 2u; cpu_basepri_restore(old); }
#endif
int32_t use_semihost(const char *s);
int32_t use_semihost(const char *s) { return cpu_semihost(0x04u, s); }
```

**Build evidence (verified):** zero diagnostics with the full warning set (`-std=c11`) on Cortex-M0+, M4, M7 and M33. On M0+, `CPU_HAS_BASEPRI` evaluates to 0, so the BASEPRI functions don't exist there, which is correct for ARMv6-M.

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7):**

```asm
use_critical:
	movw	r1, :lower16:g_count
	mrs	r0, primask
	cpsid i
	movt	r1, :upper16:g_count
	ldr	r2, [r1]
	adds	r2, #1
	str	r2, [r1]
	msr	primask, r0
	bx	lr
use_wait:
	movw	r0, :lower16:g_flag
	movt	r0, :upper16:g_flag
.LBB1_1:
	ldr	r1, [r0]
	cbnz	r1, .LBB1_3
	dsb	sy
	wfi
	b	.LBB1_1
.LBB1_3:
	bx	lr
use_ceiling:
	movs	r0, #64
	mrs	r1, basepri
	msr	basepri_max, r0
	isb	sy
	movw	r0, :lower16:g_count
	movt	r0, :upper16:g_count
	ldr	r2, [r0]
	adds	r2, #2
	str	r2, [r0]
	msr	basepri, r1
	isb	sy
	bx	lr
use_semihost:
	mov	r1, r0
	movs	r0, #4
	bkpt	#171
	bx	lr
```

**Codegen (verified — Cortex-M0+, `use_semihost` only):**

```asm
use_semihost:
	movs	r2, #4
	mov	r1, r0
	mov	r0, r2
	bkpt	#171
	bx	lr
```

What the listing proves:

- **`use_critical`:** the address materialization (`movw`/`movt`) was scheduled *across* `cpsid i`, which is fine because it isn't a memory access. The `ldr`/`str` of `g_count` stay strictly inside `mrs primask … msr primask`, held there by the `"memory"` clobbers.
- **`use_wait`:** `dsb sy` + `wfi` inside the loop, with `g_flag` (`volatile`) reloaded each iteration.
- **`use_ceiling`:** `BASEPRI_MAX` raises the mask to `0x40` (priority level 4 with `__NVIC_PRIO_BITS = 4`), followed by `isb`. Interrupts with priority 0–3 keep running (zero-latency ISRs, Folder 04). `BASEPRI_MAX` writes only if it *raises* priority, so nesting is safe. 🧊 **Cortex-M7 r0p1 erratum 837070:** a `BASEPRI` write may not take effect immediately. FreeRTOS's M7 r0p1 port wraps it in `cpsid i` / `cpsie i` (⚠ verify against your core revision's errata sheet).
- **`use_semihost`:** `bkpt #171` is `BKPT 0xAB`, with `r0 = 4` (`SYS_WRITE0`) and `r1 = the string`, on both cores. **Semihosting without a debugger attached** hits a `BKPT` with no debug monitor, which HardFaults (or locks up). Guard it with `CoreDebug->DHCSR & C_DEBUGEN` at boot, and never ship it enabled.

### 3.3 The Silicon-Hardened Production Way: `cpu_a64.h` (AArch64)

```c
/* cpu_a64.h - AArch64 CPU primitives with complete constraints and clobbers. */
#ifndef CPU_A64_H
#define CPU_A64_H

#include <stdint.h>

#if !defined(__aarch64__)
#error "cpu_a64.h is for AArch64 targets"
#endif

static inline void cpu_compiler_barrier(void) { __asm__ volatile("" : : : "memory"); }

/* SMP ordering between cores of one OS image uses the Inner Shareable domain;
 * ordering against a non-coherent DMA master needs the full system (SY/OSH). */
static inline void cpu_dmb_ish(void)   { __asm__ volatile("dmb ish" : : : "memory"); }
static inline void cpu_dmb_ishld(void) { __asm__ volatile("dmb ishld" : : : "memory"); }
static inline void cpu_dsb_sy(void)    { __asm__ volatile("dsb sy" : : : "memory"); }
static inline void cpu_isb(void)       { __asm__ volatile("isb" : : : "memory"); }

/* Virtual counter. ISB stops the MRS from being speculated ahead of earlier
 * instructions; `volatile` + "memory" stop the compiler merging or hoisting it. */
static inline uint64_t cpu_cntvct(void)
{
    uint64_t v;
    __asm__ volatile("isb\n\t"
                     "mrs %0, cntvct_el0" : "=r"(v) : : "memory");
    return v;
}

static inline uint64_t cpu_cntfrq(void)
{
    uint64_t v;
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(v));
    return v;
}

static inline uint64_t cpu_ctr_el0(void)
{
    uint64_t v;
    __asm__ volatile("mrs %0, ctr_el0" : "=r"(v));
    return v;
}

/* LL/SC fetch-add (ARMv8.0; prefer LSE `ldaddal` or C11 atomics when available).
 *  - "Q": memory operand addressed by a single base register, no offset - the
 *    only form LDAXR/STLXR accept.
 *  - "=&r": outputs written before all inputs are consumed -> early clobber.
 *  - local label 1: / 1b - safe under inlining and unrolling. */
static inline uint32_t cpu_llsc_fetch_add(uint32_t *p, uint32_t v)
{
    uint32_t old, tmp, fail;
    __asm__ volatile(
        "1: ldaxr  %w[old], %[mem]          \n\t"
        "   add    %w[tmp], %w[old], %w[v]  \n\t"
        "   stlxr  %w[fail], %w[tmp], %[mem]\n\t"
        "   cbnz   %w[fail], 1b             \n\t"
        : [old] "=&r"(old), [tmp] "=&r"(tmp), [fail] "=&r"(fail), [mem] "+Q"(*p)
        : [v] "r"(v)
        : "memory");
    return old;
}

/* asm goto: branch straight to a C label from the template (no flag output). */
static inline int cpu_is_zero_goto(uint64_t x)
{
    __asm__ goto("cbz %x0, %l[is_zero]" : : "r"(x) : : is_zero);
    return 0;
is_zero:
    return 1;
}

#endif /* CPU_A64_H */
```

Test translation unit (`use_a64.c`):

```c
#include "cpu_a64.h"
extern void work(void);
uint64_t use_elapsed(void);
uint64_t use_elapsed(void) { uint64_t t0 = cpu_cntvct(); work(); return cpu_cntvct() - t0; }
uint32_t use_llsc(uint32_t *p);
uint32_t use_llsc(uint32_t *p) { return cpu_llsc_fetch_add(p, 5u); }
int use_goto(uint64_t x);
int use_goto(uint64_t x) { return cpu_is_zero_goto(x) ? 7 : 9; }
```

**Build evidence (verified):** zero diagnostics (full warning set, `-std=c11`, `aarch64-linux-gnu`).

**Codegen (verified — Clang 21.1.0, `-O2`; `.Ltmp0` is the `1:` label, restored from the raw output):**

```asm
use_elapsed:
	stp	x29, x30, [sp, #-32]!
	str	x19, [sp, #16]
	mov	x29, sp
	isb
	mrs	x19, CNTVCT_EL0
	bl	work
	isb
	mrs	x8, CNTVCT_EL0
	sub	x0, x8, x19
	ldr	x19, [sp, #16]
	ldp	x29, x30, [sp], #32
	ret
use_llsc:
	mov	w9, #5
.Ltmp0:
	ldaxr	w8, [x0]
	add	w10, w8, w9
	stlxr	w11, w10, [x0]
	cbnz	w11, .Ltmp0
	mov	w0, w8
	ret
use_goto:
	mov	x8, x0
	mov	w0, #7
	cbz	x8, .LBB2_2
	mov	w0, #9
.LBB2_2:
	ret
```

Note `t0` is kept in **callee-saved `x19`** across `bl work`: the AAPCS64 contract at work. And the early clobbers gave `old`, `tmp` and `fail` three distinct registers (`w8`, `w10`, `w11`), separate from the input `w9`.

### 3.4 Frame-record unwinder: `fp_unwind.h` / `fp_unwind.c`

```c
/* fp_unwind.h - frame-record stack walker for AAPCS64 (x29 chain) and
 * SysV x86-64 builds compiled with -fno-omit-frame-pointer. NOT valid for
 * Win64, where rbp may point mid-frame (use RtlVirtualUnwind there).
 *
 * A frame record is two machine words at [fp]: { caller_fp, return_addr }.
 * The walker never trusts the chain: every fp is bounds-, alignment- and
 * monotonicity-checked before it is dereferenced, so it is safe to call
 * from a HardFault/panic handler on a corrupted stack. */
#ifndef FP_UNWIND_H
#define FP_UNWIND_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
    uintptr_t lo;   /* lowest valid stack address (inclusive)   */
    uintptr_t hi;   /* one past the highest valid stack address */
} stack_bounds_t;

/* Walk from frame pointer `fp`; store up to `max` return addresses in `pcs`.
 * Returns the number of frames recovered. */
size_t fp_backtrace(uintptr_t fp, stack_bounds_t sb, uintptr_t *pcs, size_t max);

/* Current frame pointer of the caller of this macro. */
#define FP_CURRENT() ((uintptr_t)__builtin_frame_address(0))

#endif /* FP_UNWIND_H */
```

> The header's Win64 exclusion was learned during verification: a first self-test that walked the live `rbp` chain on Windows recovered one bogus frame, because `rbp` sits mid-frame on Win64 (§1.4, verified). The self-test below therefore uses a synthetic AAPCS64-shaped stack, which makes it deterministic and lets it exercise the corruption paths too.

```c
/* fp_unwind.c - see fp_unwind.h. */
#include "fp_unwind.h"

#include <string.h>

#define FRAME_RECORD_BYTES (2u * sizeof(uintptr_t))

/* With -mbranch-protection=pac-ret the saved LR carries a PAC in its upper
 * bits. XPACLRI (HINT #7) strips it in place on x30 and executes as a NOP on
 * cores without FEAT_PAuth, so this is safe on every ARMv8.0+ core. */
static inline uintptr_t strip_pac(uintptr_t ra)
{
#if defined(__aarch64__)
    register uintptr_t x30 __asm__("x30") = ra;
    __asm__("hint #7" : "+r"(x30));
    return x30;
#else
    return ra;
#endif
}

size_t fp_backtrace(uintptr_t fp, stack_bounds_t sb, uintptr_t *pcs, size_t max)
{
    size_t n = 0u;

    if ((pcs == NULL) || (sb.hi <= sb.lo) || (sb.hi - sb.lo < FRAME_RECORD_BYTES)) {
        return 0u;
    }
    while (n < max) {
        uintptr_t rec[2];

        /* 1. The whole record must lie inside the stack. */
        if ((fp < sb.lo) || (fp > (sb.hi - FRAME_RECORD_BYTES))) {
            break;
        }
        /* 2. Records are at least word aligned (16 on AAPCS64 in practice). */
        if ((fp % sizeof(uintptr_t)) != 0u) {
            break;
        }
        /* 3. Copy out instead of dereferencing a struct pointer: no aliasing
         *    or alignment assumptions leak into the optimizer. */
        memcpy(rec, (const void *)fp, sizeof rec);

        uintptr_t ra = strip_pac(rec[1]);
        if (ra == 0u) {
            break;
        }
        pcs[n] = ra;
        n++;

        /* 4. Full-descending stack: the caller's record is strictly higher.
         *    This single check makes cycles and garbage chains terminate. */
        if (rec[0] <= fp) {
            break;
        }
        fp = rec[0];
    }
    return n;
}

#ifdef FP_SELFTEST
/* Host test on a synthetic, AAPCS64-shaped stack: four frame records at
 * increasing addresses, then deliberately corrupted variants. */
#include <stdalign.h>
#include <stdio.h>

static alignas(16) uintptr_t stk[64];

static uintptr_t at(size_t i) { return (uintptr_t)&stk[i]; }

static void build_chain(void)
{
    for (size_t i = 0u; i < 64u; i++) { stk[i] = 0u; }
    stk[8]  = at(20); stk[9]  = 0x1000u;   /* innermost frame */
    stk[20] = at(36); stk[21] = 0x2000u;
    stk[36] = at(50); stk[37] = 0x3000u;
    stk[50] = 0u;     stk[51] = 0x4000u;   /* outermost: caller_fp = 0 */
}

static void run(const char *name, uintptr_t fp)
{
    uintptr_t pcs[16];
    stack_bounds_t sb = { at(0), at(0) + sizeof stk };
    size_t n = fp_backtrace(fp, sb, pcs, 16u);
    printf("%-14s frames=%zu", name, n);
    for (size_t i = 0u; i < n; i++) { printf(" 0x%04zx", (size_t)pcs[i]); }
    printf("\n");
}

int main(void)
{
    build_chain();                        run("good",         at(8));
    build_chain(); stk[50] = at(8);       run("cycle",        at(8));
    build_chain();                        run("misaligned",   at(8) + 1u);
    build_chain(); stk[36] = at(0) + sizeof stk; run("out-of-bounds", at(8));
    build_chain(); stk[21] = 0u;          run("null-ra",      at(8));
    build_chain();
    {
        uintptr_t pcs[4];
        stack_bounds_t empty = { 0u, 0u };
        printf("%-14s frames=%zu\n", "empty-bounds", fp_backtrace(at(8), empty, pcs, 4u));
    }
    return 0;
}
#endif
```

**Build evidence (verified):** zero diagnostics with the full warning set (`-std=c11`) on AArch64, x86-64, Cortex-M7 and RV64.

**Self-test output (verified, native x86-64):**

```text
good           frames=4 0x1000 0x2000 0x3000 0x4000
cycle          frames=4 0x1000 0x2000 0x3000 0x4000
misaligned     frames=0
out-of-bounds  frames=3 0x1000 0x2000 0x3000
null-ra        frames=1 0x1000
empty-bounds   frames=0
```

Every corruption mode terminates. In the cycle case, the record at `stk[50]` points *backwards* to `stk[8]`, and the monotonicity check stops the walk after the fourth frame.

**Codegen (verified — Clang 21.1.0, `-O2 -mbranch-protection=standard`, `aarch64-linux-gnu`; the compiler's own property note first):**

```asm
	.word	4
	.word	16
	.word	5
	.asciz	"GNU"
	.word	3221225472
	.word	4
	.word	7
	.word	0
fp_backtrace:
	hint	#34
	mov	x8, x0
	mov	x0, xzr
	cbz	x3, .LBB0_12
	cmp	x2, x1
	b.ls	.LBB0_12
	sub	x9, x2, x1
	cmp	x9, #16
	b.lo	.LBB0_12
	hint	#25
	str	x30, [sp, #-16]!
	mov	x0, xzr
	sub	x9, x2, #16
.LBB0_4:
	cmp	x4, x0
	b.eq	.LBB0_10
	cmp	x8, x1
	b.lo	.LBB0_11
	cmp	x8, x9
	b.hi	.LBB0_11
	and	x10, x8, #0x7
	cbnz	x10, .LBB0_11
	ldr	x30, [x8, #8]
	hint	#7
	cbz	x30, .LBB0_11
	ldr	x10, [x8]
	str	x30, [x3, x0, lsl #3]
	add	x0, x0, #1
	cmp	x10, x8
	mov	x8, x10
	b.hi	.LBB0_4
	b	.LBB0_11
.LBB0_10:
	mov	x0, x4
.LBB0_11:
	ldr	x30, [sp], #16
	hint	#29
.LBB0_12:
	ret
```

Reading it:

- **`.word 3221225472`** is `0xC0000000` (`GNU_PROPERTY_AARCH64_FEATURE_1_AND`), followed by **`.word 7`** (BTI | PAC | GCS).
- **`hint #34`** (`BTI c`) is at entry. **`hint #25`** (`PACIASP`) has been shrink-wrapped past the early exits.
- **`hint #7`** (`XPACLRI`) operates on `x30` *in place*. That is why `strip_pac` binds its operand to `x30`, and why the compiler had to spill the real LR (`str x30, [sp, #-16]!`) around the loop.
- `memcpy(rec, …)` became two plain `ldr`s: no call.

### 3.5 Hand-written AAPCS64 assembly that calls back into C: `sum_mapped.S`

```asm
// sum_mapped.S - hand-written AAPCS64 routine that calls back into C.
//
//   uint64_t sum_mapped(const uint32_t *v, size_t n, uint32_t (*fn)(uint32_t));
//
// Demonstrates every obligation a hand-written AAPCS64 function has:
//   * BTI landing pad (indirectly callable) and PAC-RET signing of LR
//   * a frame record in x29 so frame-pointer unwinders can walk through it
//   * SP 16-byte aligned at every call site (blr)
//   * callee-saved x19-x22 preserved; nothing live in x0-x18 across blr
//   * CFI so DWARF unwinders (gdb, Trace32, perf --call-graph=dwarf) work
//   * GNU property note so the linker can keep the image BTI/PAC-enabled

    .text
    .p2align 2
    .global sum_mapped
    .type   sum_mapped, %function
sum_mapped:
    .cfi_startproc
    bti     c                       // HINT #34: valid target for BLR
    paciasp                         // HINT #25: sign x30 with SP as modifier
    .cfi_negate_ra_state
    stp     x29, x30, [sp, #-48]!   // frame record at the new SP, SP%16 == 0
    .cfi_def_cfa_offset 48
    .cfi_offset w30, -40
    .cfi_offset w29, -48
    mov     x29, sp
    .cfi_def_cfa w29, 48
    stp     x19, x20, [sp, #16]
    .cfi_offset w20, -24
    .cfi_offset w19, -32
    stp     x21, x22, [sp, #32]
    .cfi_offset w22, -8
    .cfi_offset w21, -16

    mov     x19, x0                 // v      (callee-saved: survives blr)
    mov     x20, x1                 // n
    mov     x21, x2                 // fn
    mov     x22, xzr                // acc
    cbz     x20, 2f
1:  ldr     w0, [x19], #4           // arg0 = *v++
    blr     x21                     // clobbers x0-x18, x30, v0-v7, v16-v31
    add     x22, x22, w0, uxtw      // acc += (uint64_t)ret
    subs    x20, x20, #1
    b.ne    1b
2:  mov     x0, x22

    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    .cfi_def_cfa sp, 0
    autiasp                         // HINT #29: authenticate x30
    .cfi_negate_ra_state
    ret
    .cfi_endproc
    .size   sum_mapped, .-sum_mapped

    .section .note.gnu.property, "a"
    .p2align 3
    .word   4                       // n_namesz ("GNU\0")
    .word   16                      // n_descsz
    .word   5                       // NT_GNU_PROPERTY_TYPE_0
    .asciz  "GNU"
    .word   0xc0000000              // GNU_PROPERTY_AARCH64_FEATURE_1_AND
    .word   4                       // pr_datasz
    .word   3                       // BTI (bit 0) | PAC (bit 1)
    .word   0                       // pad to 8

    .section .note.GNU-stack, "", %progbits
```

**Build evidence (verified):** assembled for `aarch64-linux-gnu` with Clang 21.1.0's integrated assembler, producing a 2,480-byte object with no diagnostics.

The obligations, line by line:

1. **`bti c` first.** The function is reachable through a function pointer, so it needs a call landing pad. `paciasp` would also serve as one, but an explicit `bti c` keeps the function correct even if someone later removes PAC.
2. **`paciasp` before `x30` is spilled**, so the stack copy is signed. `.cfi_negate_ra_state` tells DWARF unwinders that the saved RA is now signed; unwinders strip the PAC like `strip_pac` does.
3. **One 48-byte frame:** the 16-byte record plus four callee-saved registers, a multiple of 16. SP stays 16-aligned at the `blr`.
4. **Only callee-saved registers (`x19`–`x22`) are live across `blr`.** `x0`–`x18` and `x30` are dead after every call.
5. **The CFI mirrors every save.** `.cfi_def_cfa w29, 48` makes unwinding robust even if the body moved SP.
6. **The epilogue restores in reverse**, then `autiasp`, then `ret`. A corrupted saved LR now faults instead of returning into attacker-chosen code.
7. **The property note declares BTI | PAC (value 3).** Without it, linking this object into a BTI-enabled executable makes the linker drop BTI enforcement for the *whole* image (or warn with `-z force-bti`). Compiler-generated objects set GCS too (value 7). For GCS-enabled processes, hand-written code must also be audited for return-address manipulation before setting bit 2.

---

## 4. Hardware Debugging and Post-Mortem Diagnostics

### 4.1 ABI violations and their signatures

| Symptom | Mechanism | Confirm |
|---|---|---|
| Crash *after* a call returns, in the caller, with a garbage local | A callee (hand-written asm, or a mismatched compiler flag) clobbered a callee-saved register (`x19`–`x28`, `d8`–`d15`, `r4`–`r11`) | Breakpoint before and after the call; compare `info registers` |
| AArch64 `ESR` EC `0x26` | SP misaligned at an SP-relative access (asm entry stub, manual stack switch) | `p/x $sp & 0xf` |
| `printf("%f")` garbage only in RTOS tasks | Task stack top not 8-aligned (AAPCS32) | Check the task-creation stack pointer mod 8 |
| Linker: "X uses VFP register arguments, Y does not" | Mixing `-mfloat-abi=hard` with `soft`/`softfp` objects | `readelf -A`: `Tag_ABI_VFP_args` |
| Variadic call prints wrong values only on Apple arm64 or x86-64 | Variadic/non-variadic prototype mismatch through a function-pointer cast (§1.6) | `-Wcast-function-type`; C23 prototypes |
| Backtrace skips a frame | Tail call (§1.10) | Disassemble the "missing" function's end: `b`, not `bl` + `ret` |
| Return addresses in the dump have high bits set (`0x003f…`) | PAC-signed LRs saved in frame records | Strip with `XPACLRI`/`XPACI`, or mask to the VA size; the verified `strip_pac` |
| ESR EC `0x1C` | PAC authentication failure (FEAT_FPAC): stack corruption of a saved LR | Frame-record dump around SP |
| ESR EC `0x0D` | BTI violation: an indirect branch to an instruction that isn't a landing pad (often a hand-written `.S` missing `bti`) | Disassemble the branch target |
| Cortex-M UsageFault `STKOF` / MemManage `MSTKERR` | Stack overflow caught by `PSPLIM`/`MSPLIM` (v8-M) or an MPU guard | `-fstack-usage`, high-water marks |
| `INVPC` UsageFault on ISR exit | Handler corrupted `LR` (`EXC_RETURN`), e.g. asm that used `lr` as a scratch register | `p/x $lr` at handler exit must be `0xFFFFFFxx` |

### 4.2 Reading frame records in a raw memory dump

Given `x29` from the crash context (or from the exception frame of an AArch64 panic):

```text
(gdb) x/2gx $x29            # [x29] = caller fp, [x29+8] = return address
(gdb) info symbol 0x<ra>    # map the return address to a function
(gdb) x/2gx 0x<caller fp>   # repeat until fp == 0 or leaves the stack
```

TRACE32: `Frame.view /Caller /Locals` unwinds from DWARF CFI. When CFI is missing (hand-written `.S` without `.cfi_*`, or `-fno-asynchronous-unwind-tables` firmware), set `Frame.CONFIG.EPILOG ON` and walk the records manually with `Data.dump Register(X29) /Quad`.

The Linux arm64 oops `Call trace:` comes from the kernel's frame-record unwinder. The `pc : func+0x24/0x80` and `lr : …` lines are the first two entries. With PAC enabled, the kernel strips the PAC before symbolizing.

### 4.3 Unwinding without frame pointers (Cortex-M reality)

- **DWARF CFI** (`.debug_frame`, which GCC/Clang keep with `-g` even when `.eh_frame` is disabled) lets GDB and TRACE32 unwind exactly. Keep the ELF with debug info for every shipped build ID.
- **AArch32 EHABI** (`.ARM.exidx`/`.ARM.extab`) is what the C++ runtime and `libunwind` use. It can also drive a small on-target unwinder.
- **Heuristic stack scanning**, the last resort inside a HardFault handler, scans the stack for words that are odd (Thumb bit set) and fall inside `.text`, then reports them as *candidate* return addresses. It produces false positives, so it always records the raw stack too. Folder 07 implements it with the exception frame, `EXC_RETURN` decoding, and a `.noinit` crash record.

### 4.4 Inline-asm forensics

When an inline-asm helper misbehaves, **read the compiled output, not the template**:

- `objdump -d --no-show-raw-insn fw.elf | less`, or `-S` for interleaved source.
- Check that every output register differs from every input register that is read later (early clobber).
- Check that the asm still exists (`volatile`).
- Check that the memory operations you depend on are on the correct side of it (`"memory"`).
- Clang's `-Xclang -fdump-...` is rarely needed. A 10-line reproducer on Compiler Explorer with your exact flags resolves most cases in minutes.

---

## 5. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "Walk me through register usage across a call on AArch64. What does the callee owe the caller?"

- **L5:** "`x0`–`x7` are arguments, `x19`–`x28` are callee-saved, `x30` is the link register."
- **Why L5 fails on real hardware:** It misses the rules that break hand-written and SIMD code:
  - **`x8`** carries the indirect-result pointer (verified `make_big` writes through it).
  - **`x16`/`x17`** are clobbered by veneers and PLT stubs *between* the `bl` and the callee, so asm can't pass values in them.
  - **`x18`** is off-limits on Apple and Windows, and is the SCS pointer on Android and Linux.
  - Only the **low 64 bits of `v8`–`v15`** survive.
  - SVE `z` registers and predicates are caller-saved in the base PCS.
  - **SP must stay 16-aligned** (`SCTLR.SA` faults, EC `0x26`).
  - A non-leaf function owes a **frame record** if the platform requires one (Apple, kernels, profilers).
- **L7 defense:** State the full table (§1.1), the composite-passing rules (HFA in `v` registers, more than 16 bytes by reference, `x8` for results), and the platform deltas (Apple, Windows). Then show how you enforce it:
  - hand-written assembly lives in `.S` files with CFI and BTI/PAC;
  - every boundary function has a C prototype under `-Wstrict-prototypes`;
  - a register-clobber test calls each asm routine with sentinel values in `x19`–`x28` and `d8`–`d15` and checks them afterwards.

### Q2 🔥 "On Cortex-M, `void f(int a, uint64_t b)`. Which registers hold `b`? Why does it matter?"

- **L5:** "`r1` and `r2`."
- **Why L5 fails:** AAPCS32 puts 64-bit values in an **even-odd pair**, so `b` is in **`r2:r3`** and `r1` is skipped (verified `call_u64`: `r0 = 1`, `r2:r3` = constant). When a hidden struct-return pointer takes `r0`, the effect compounds (verified `make_big`: `v` in `r2:r3`). Hand-written assembly, ROM-API function tables, and RTOS SVC dispatchers that unpack arguments by hand all get this wrong. On AArch64 none of this applies: one `x` register per 64-bit value.
- **L7 defense:** Never hand-unpack arguments in asm; call a C function with a real prototype. For SVC dispatch, read arguments from the *stacked* exception frame (`r0`–`r3` at offsets 0–12) using the documented pairing. Add ABI unit tests that call the asm entry point from C with 64-bit arguments in every position.

### Q3 🔥 "What is the red zone? Why does the x86-64 kernel build with `-mno-red-zone`? Does Cortex-M have one?"

- **L5:** "It's 128 bytes below the stack pointer that leaf functions may use. Kernels disable it for safety."
- **Why L5 fails:** "For safety" isn't a mechanism. The mechanism: an interrupt or exception taken at CPL0 without a stack switch pushes the hardware frame at `rsp`, **into** the red zone, corrupting the leaf function's locals (verified listing: the buffer at `-40(%rsp)` with no `sub`). Cortex-M is the extreme case. The NVIC can stack 32 or 104 bytes **at SP between any two instructions**. AAPCS32 therefore defines no red zone, and storing below SP is always a latent corruption. AAPCS64 Linux has none either. Apple arm64 *does* define one (128 bytes), which matters if you write asm shared across Apple and Linux.
- **L7 defense:** Know the per-ABI table (§1.9). Build kernels, hypervisors, firmware and UEFI with `-mno-red-zone`. Review hand-written asm for "store below SP". In RTOS ports, make sure the context-switch code never drops SP *above* live data before the save completes.

### Q4 🔥 "This inline asm multiplies by 3. It passes unit tests, and returns `in*in` in the release build."

- **L5:** "Compiler bug, or the asm is wrong; rewrite it in C."
- **Why L5 fails:** The asm is fine. The **constraint** is wrong. Without `=&r`, the compiler may allocate the output to the input's register, and `mov w0, #3` destroys the input (verified: `mul w0, w0, w0`). Unit tests built at `-O0`, or with the helper not inlined, got a different register allocation.
- **L7 defense:** Early clobber (`=&r`) on every output written before the last input read. Review asm by reading the compiled output. Keep asm in one header (MISRA Dir 4.3), with a codegen test in CI that greps the disassembly. Prefer ACLE intrinsics or C (verified `__rev`/`__clz`/barriers), which make the whole class of bug impossible.

### Q5 "Your cycle-count instrumentation reports 0 elapsed ticks around an expensive function."

- **L5:** "The counter isn't enabled."
- **Why L5 fails:** The counter is fine. The two `mrs` statements were **non-`volatile`** with no inputs, so CSE merged them, the subtraction folded, and both reads were deleted (verified: `mov x0, xzr`). Even with `volatile`, an out-of-order core can execute `mrs cntvct_el0` early unless it is preceded by an `ISB`. On Cortex-M with `DWT->CYCCNT` (a `volatile` MMIO read), the compiler is fine, but the reads can still be scheduled around non-volatile work.
- **L7 defense:** `asm volatile("isb; mrs %0, cntvct_el0" ::: "memory")` (verified listing), or ACLE `__arm_rsr64` with an explicit `__isb`. Put `"memory"` clobbers on both reads, so the measured code can't migrate outside the window. Verify the instrumentation by measuring a calibrated busy loop.

### Q6 🔥 "Is `asm volatile("" ::: "memory")` a memory barrier?"

- **L5:** "Yes, it prevents reordering."
- **Why L5 fails:** It prevents **compiler** reordering of memory accesses across that point, and emits **zero instructions**. On multi-core ARM, the store buffer and out-of-order load execution still reorder accesses as seen by other cores. A non-coherent DMA engine still sees stale cache lines. So it is sufficient only for ordering against an interrupt handler **on the same single core** (and even then the shared variable must be `volatile` or atomic).
- **L7 defense:** Distinguish the three tools:
  1. **Compiler barrier:** same core, ISR handoff.
  2. **`DMB`** (inner-shareable `ISH` on A-profile; `SY` on M-profile): ordering between observers.
  3. **`DSB` (+ `ISB`):** completion, for sleep entry, MPU/MMU changes, and DMA kicks.

  In C, use `atomic_thread_fence(memory_order_acq_rel)` or acquire/release operations, which the compiler lowers to the correct instruction per target. Folder 03 has the full derivation.

### Q7 "Write a critical section on Cortex-M. Why save and restore PRIMASK instead of `cpsid`/`cpsie`? When is BASEPRI better?"

- **L5:** "`__disable_irq(); …; __enable_irq();`"
- **Why L5 fails:** An unconditional `cpsie i` re-enables interrupts inside a **caller's** critical section when the code nests (the `cpu_bad.h` bug 4). PRIMASK also masks *everything* at configurable priority, adding latency to ISRs that never touch the shared data. That latency is fatal for motor control or high-rate ADC handling.
- **L7 defense:**
  - Save and restore PRIMASK (verified `use_critical`: the `ldr`/`str` are pinned between `mrs primask` and `msr primask` by `"memory"` clobbers).
  - On v7-M/v8-M Mainline, use **BASEPRI with `BASEPRI_MAX`** as a priority *ceiling* (verified `use_ceiling`). It masks only interrupts at or below the shared data's priority, so higher-priority "zero-latency" ISRs keep running. Those ISRs must never call RTOS APIs.
  - `isb` after the `MSR BASEPRI`, and know the Cortex-M7 r0p1 erratum (⚠ verify).
  - v6-M has no BASEPRI (verified: `CPU_HAS_BASEPRI` = 0 on M0+). There, use PRIMASK, or design the code lock-free (Folder 05).

### Q8 ⚡ "Your crash dump's return addresses look like `0x003c7f0012345678`, and the backtrace stops after two frames."

- **L5:** "Stack corruption."
- **Why L5 fails:** Those are **PAC-signed** link registers saved in frame records under `-mbranch-protection=standard`. The upper bits hold the authentication code. The symbolizer can't map them, and an unwinder that validates "ra must look like a code address" stops early. Separately, any frame that ended in a tail call never appears (verified `b ext_work`).
- **L7 defense:**
  - Strip PACs before symbolizing: `XPACLRI` (verified `hint #7` in `strip_pac`), `XPACI` on v8.3+, or mask to the configured VA size.
  - Treat tail-call gaps as expected.
  - Use DWARF CFI (`.cfi_negate_ra_state`-aware) for exact offline unwinding.
  - Keep frame pointers on in diagnostic builds.
  - Bounds- and monotonicity-check every frame (verified walker: cycles and out-of-bounds chains terminate).

### Q9 "Should Cortex-M ISRs use `__attribute__((interrupt))`?"

- **L5:** "Yes, the compiler needs to know it's an interrupt handler."
- **Why L5 fails:** On M-profile the hardware already stacks the AAPCS caller-saved registers and aligns SP to 8, so a plain function is a correct handler. The attribute made Clang emit a software SP realignment (`bfc r4, #0, #3`) plus a frame, **seven extra instructions per interrupt**, and a misleading VFP warning, since FP state is handled by hardware lazy stacking (verified listing).
- **L7 defense:** Plain `void X_IRQHandler(void)` on M-profile, with the vector-table symbol names from the startup file (Folder 02). The attribute is for A/R-profile AArch32 IRQ/FIQ entry. On AArch64, vectors are assembly that builds a full register frame before calling C (Folder 04).

### Q10 🧊 "You hand-wrote an AArch64 routine that takes a callback. List every obligation it has."

- **L5:** "Save the registers I use and return with `ret`."
- **Why L5 fails:** That misses:
  - BTI landing pads (indirect calls fault with EC `0x0D` on guarded pages);
  - PAC signing before spilling `x30`;
  - the frame record for unwinders;
  - 16-byte SP alignment at the `blr`;
  - the rule that nothing may stay live in `x0`–`x18` across the callback;
  - CFI for debuggers;
  - the `.note.gnu.property` that keeps the *whole executable* BTI-enabled.
- **L7 defense:** The verified `sum_mapped.S` (§3.5), which assembles cleanly and covers all seven. Plus a CI check that `readelf -n` on the final image shows the AArch64 feature property, and a test that runs the routine with `x19`–`x28` sentinels.

---

## 6. Invariants Checklist

- [ ] All cross-boundary functions have full prototypes (`-Wstrict-prototypes -Wmissing-prototypes`); no variadic/non-variadic function-pointer casts.
- [ ] Hand-written assembly lives in `.S` files with CFI, `bti c`, `paciasp`/`autiasp`, frame records, 16-byte SP alignment, and a `.note.gnu.property`.
- [ ] Hand-written AAPCS32 code respects even register pairs for 64-bit values and the `r0` struct-return shift.
- [ ] Kernels, hypervisors, bare-metal and UEFI code build with `-mno-red-zone` on x86-64; nothing is ever stored below SP on Cortex-M.
- [ ] RTOS task stacks start 8-byte aligned (AAPCS32) or 16-byte aligned (AAPCS64); asserted at task creation.
- [ ] Stack canaries: `__stack_chk_guard` seeded from the TRNG before any protected frame that returns; `__stack_chk_fail` logs and resets.
- [ ] Stack overflow is hardware-detected: `PSPLIM`/`MSPLIM` (v8-M) or MPU guard regions (v7-M); `-fstack-usage` worst-case analysis in CI.
- [ ] Cortex-M ISRs are plain functions (no `interrupt` attribute).
- [ ] Every inline asm: `=&` on early-written outputs; `volatile` when it has effects beyond its outputs; `"memory"` when ordering matters; `"cc"` when it writes flags; `Q` for exclusives; local numeric labels only.
- [ ] Critical sections save and restore PRIMASK, or raise BASEPRI with `BASEPRI_MAX` + `ISB`; never an unconditional `cpsie i`.
- [ ] Timing reads: `ISB` + `volatile` + `"memory"`.
- [ ] Crash unwinders strip PAC, bounds- and monotonicity-check frames, and tolerate tail-call gaps.

## 7. MISRA C:2012 / CERT C Cross-Reference

| Topic | MISRA C:2012 | CERT C |
|---|---|---|
| Assembly encapsulated and isolated | Dir 4.3 | (none) |
| Inline asm documented | Dir 4.2 (all uses of assembly language should be documented) | (none) |
| Function prototypes | Rules 8.2, 8.4, 17.3 | DCL31-C, DCL40-C (incompatible declarations) |
| Calling through an incompatible function pointer | Rule 11.1 | EXP37-C (call functions with the correct number and type of arguments) |
| Variadic functions | Rule 17.1 (`<stdarg.h>` shall not be used) | DCL10-C, DCL11-C (recommendations) |
| Recursion (unbounded stack) | Rule 17.2 | MEM05-C (avoid large stack allocations, recommendation) |
| Return-address and stack integrity | (none; covered by Dir 4.1 run-time failures) | (none; mitigations: stack protector, SCS, PAC, GCS) |

## 8. References

1. Arm, *Procedure Call Standard for the Arm 64-bit Architecture (AAPCS64)*, IHI 0055, current release; *Procedure Call Standard for the Arm Architecture (AAPCS32)*, IHI 0042.
2. Arm, *Arm Architecture Reference Manual for A-profile* (DDI 0487): SCTLR_ELx, ESR_ELx exception classes, Pointer Authentication, BTI (guarded pages), FEAT_FPAC, FEAT_GCS.
3. Arm, *ARMv7-M Architecture Reference Manual* (DDI 0403E) §B1.5 (exception entry and stack alignment), §B5.2 (MRS/MSR special registers); *ARMv8-M ARM* (DDI 0553): stack limit registers.
4. Arm, *Arm C Language Extensions (ACLE)*; Application Note AN321, *ARM Cortex-M Programming Guide to Memory Barrier Instructions*; Cortex-M7 errata notice (837070).
5. H. J. Lu, M. Matz, J. Hubička, A. Jaeger, M. Mitchell, *System V Application Binary Interface: AMD64 Architecture Processor Supplement*; Microsoft, *x64 calling convention*, *ARM64 ABI conventions*; Apple, *Writing ARM64 code for Apple platforms*; RISC-V International, *RISC-V ELF psABI*.
6. GCC Manual: *Extended Asm*, *Constraints for asm Operands / Machine Constraints*, *Common Function Attributes* (`naked`, `interrupt`), `-fstack-usage`, `-fcallgraph-info`; LLVM, *Inline Assembler Expressions* and *ShadowCallStack* documentation.
7. DWARF Debugging Information Format, Version 5, §6.4 *Call Frame Information*; Arm, *Exception Handling ABI for the Arm Architecture* (EHABI, IHI 0038).
8. Linux kernel: `arch/arm64/kernel/stacktrace.c` (frame-record unwinding), `Documentation/arch/arm64/pointer-authentication.rst`, `Documentation/arch/x86/kernel-stacks.rst`, jump labels (`include/linux/jump_label.h`).
9. ARM, *Semihosting for AArch32 and AArch64* specification (`SYS_WRITE0` = 0x04).
