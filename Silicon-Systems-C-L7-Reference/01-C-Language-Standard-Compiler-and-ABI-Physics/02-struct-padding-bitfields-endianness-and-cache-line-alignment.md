# 02 · Struct Padding, Bit-Fields, Endianness, and Cache-Line Alignment

> **Folder:** `01-C-Language-Standard-Compiler-and-ABI-Physics/` · **File 2 of 3**
> **Anchors:**
> - ISO/IEC 9899 (C11/C17/C23): §3.14 memory location, §6.2.6.1 representations and padding, §6.2.8 alignment, §6.7.2.1 structure, union and bit-field specifiers, §6.7.9 initialization (C23 §6.7.10, empty initializer `{}`).
> - ABI documents: Arm AAPCS32 (IHI 0042) *Data types and alignment*, *Bit-fields*, *Volatile bit-fields*; Arm AAPCS64 (IHI 0055); System V i386 and AMD64 psABI; Apple *Writing ARM64 code for Apple platforms*; RISC-V psABI.
> - ARMv7-M ARM (DDI 0403) AIRCR.ENDIANNESS and bit-banding; ARMv8-A ARM (DDI 0487) SCTLR_ELx.EE/E0E and CTR_EL0; Cortex-M7 TRM (L1 cache geometry).
> - U. Drepper, *What Every Programmer Should Know About Memory* (2007) §3 (caches) and §6.4 (false sharing).
> - Linux `include/linux/bitfield.h`, `include/linux/overflow.h` (`struct_size`); dwarves `pahole`.
>
> **Verification:** listings marked *Codegen (verified)* and the ABI table were produced by Clang 21.1.0 on 2026-10-26 ([method](../README.md#verification-method--read-this-before-trusting-a-listing)). GCC-specific statements are marked ⚠ verify.

---

## 0. The thesis

A C `struct` is a contract between three parties:

1. **The compiler's ABI:** offsets, padding, alignment, bit-field allocation.
2. **The hardware:** bus byte lanes, access widths, register side effects, cache-line granularity, and coherency.
3. **Other software:** a wire protocol, another core, another compiler, another endianness.

ISO C pins down **only part of the first party**, and leaves most of it implementation-defined. Every production bug in this file comes from assuming the language guarantees something that only one ABI on one core provides.

---

## 1. First-Principles Hardware and Compiler Mechanics

### 1.1 Why hardware wants alignment

A 32-bit AHB-Lite or AXI data bus moves data on **byte lanes**. A 32-bit transfer at an address that is 0 mod 4 occupies all four lanes in one beat (`HSIZE = 0b010`, or AXI `AxSIZE = 2` with `WSTRB = 0xF`). A misaligned 32-bit access has two possible fates:

- The core splits it into multiple bus transactions. Cortex-M3/M4/M7 do this for single `LDR`/`STR` when `CCR.UNALIGN_TRP = 0`. The cost is extra cycles, and **the access is no longer single-copy atomic**.
- The core faults. That happens on ARMv6-M always, on ARMv7-M for `LDRD`/`LDM`/exclusives, and on AArch64 for Device memory (File 01 §2.3).

Single-copy atomicity is the part people forget. On ARM, an **aligned** access no wider than the native register width is single-copy atomic: another observer sees either the old or the new value, never a mix. A misaligned access that the hardware splits can be **torn**: another core, or the DMA engine, sees half old and half new bytes. A "naturally atomic" `uint32_t` stops being atomic the moment `packed` moves it to offset 1.

The C model (§6.2.8):

- Every complete object type has an alignment requirement, a power of two queried with `_Alignof` (`alignof` in C23, or `<stdalign.h>` in C11).
- `max_align_t` has the strictest **fundamental** alignment. `malloc` returns storage aligned for it.
- An **extended** alignment (greater than `alignof(max_align_t)`) is implementation-defined in whether, and where, it is supported. `alignas(64)` on a static object is supported by GCC and Clang through ELF section alignment (verified below: `.p2align 6`).

### 1.2 The layout algorithm (§6.7.2.1 plus the psABI)

C specifies a few rules:

- Members are laid out **in declaration order**. The compiler may never reorder them.
- There is no padding before the first member.
- There may be padding between members and after the last one.

The psABI fills in the rest:

1. For each member, round the current offset up to that member's alignment.
2. The struct's alignment is the maximum alignment of its members.
3. The struct's size is rounded up to a multiple of its alignment, so that arrays of the struct keep every element aligned.

Example source:

```c
struct bad_order  { char a; uint64_t b; char c; };
struct good_order { uint64_t b; char a; char c; };
```

Layouts on LP64 / AAPCS (offsets verified with `offsetof` below):

```text
struct bad_order  (size 24, align 8)          struct good_order (size 16, align 8)
off  0: a        [1]                          off  0: b        [8]
off  1: <pad>    [7]                          off  8: a        [1]
off  8: b        [8]                          off  9: c        [1]
off 16: c        [1]                          off 10: <pad>    [6]  (tail)
off 17: <pad>    [7]  (tail)
```

**`-Wpadded` (verified, Clang 21.1.0, Cortex-M7):**

```text
layout.c:6:41: warning: padding struct 'struct u64_in_struct' with 7 bytes to align 'v' [-Wpadded]
layout.c:4:38: warning: padding struct 'struct bad_order' with 7 bytes to align 'b' [-Wpadded]
layout.c:4:8: warning: padding size of 'struct bad_order' with 7 bytes to alignment boundary [-Wpadded]
layout.c:5:8: warning: padding size of 'struct good_order' with 6 bytes to alignment boundary [-Wpadded]
```

Ordering members by decreasing alignment minimizes padding. It is not always the right order, though. Production layouts are ordered by:

1. hardware or wire contract;
2. **access locality**: fields touched together go in the same cache line;
3. **writer**: fields written by different cores go in different lines;
4. only then, size.

### 1.3 The same struct on eight ABIs (verified) 🔥

The probe source emits each quantity as an initialized constant, so a single compile per target yields the answer from the compiler's own layout engine:

```c
#include <stdalign.h>
#include <stddef.h>
#include <stdint.h>
struct bad_order  { char a; uint64_t b; char c; };
struct good_order { uint64_t b; char a; char c; };
struct u64_in_struct { char c; uint64_t v; };
struct fam_msg { uint32_t len; uint8_t type; uint8_t data[]; };
enum small_enum { SE_A, SE_B };
const unsigned k01_sizeof_long         = sizeof(long);
const unsigned k02_sizeof_ptr          = sizeof(void *);
const unsigned k03_sizeof_long_double  = sizeof(long double);
const unsigned k04_alignof_long_double = alignof(long double);
const unsigned k05_alignof_max_align_t = alignof(max_align_t);
const unsigned k06_alignof_u64         = alignof(uint64_t);
const unsigned k07_gnu_alignof_u64     = __alignof__(uint64_t);
const unsigned k08_offsetof_u64_in_s   = offsetof(struct u64_in_struct, v);
const unsigned k09_sizeof_bad_order    = sizeof(struct bad_order);
const unsigned k10_sizeof_good_order   = sizeof(struct good_order);
const unsigned k11_sizeof_fam_msg      = sizeof(struct fam_msg);
const unsigned k12_offsetof_fam_data   = offsetof(struct fam_msg, data);
const unsigned k13_sizeof_enum         = sizeof(enum small_enum);
const unsigned k14_sizeof_wchar_t      = sizeof(wchar_t);
const int      k15_char_is_signed      = ((char)-1 < 0);
const unsigned k16_sizeof_bool         = sizeof(_Bool);
```

**Result (verified — Clang 21.1.0, `-O2`; columns are the targets from the [README](../README.md#verification-method--read-this-before-trusting-a-listing)):**

| probe | x64 | i386 | a64 | a64mac | a32 | m7 | m0 | rv64 |
|---|---|---|---|---|---|---|---|---|
| `sizeof_long` | 8 | 4 | 8 | 8 | 4 | 4 | 4 | 8 |
| `sizeof_ptr` | 8 | 4 | 8 | 8 | 4 | 4 | 4 | 8 |
| `sizeof_long_double` | 16 | 12 | 16 | **8** | 8 | 8 | 8 | 16 |
| `alignof_long_double` | 16 | 4 | 16 | 8 | 8 | 8 | 8 | 16 |
| `alignof_max_align_t` | 16 | 8 | 16 | 8 | **8** | **8** | **8** | 16 |
| `alignof_u64` | 8 | **4** | 8 | 8 | 8 | 8 | 8 | 8 |
| `gnu_alignof_u64` | 8 | **8** | 8 | 8 | 8 | 8 | 8 | 8 |
| `offsetof_u64_in_s` | 8 | **4** | 8 | 8 | 8 | 8 | 8 | 8 |
| `sizeof_bad_order` | 24 | **16** | 24 | 24 | 24 | 24 | 24 | 24 |
| `sizeof_good_order` | 16 | **12** | 16 | 16 | 16 | 16 | 16 | 16 |
| `sizeof_fam_msg` | 8 | 8 | 8 | 8 | 8 | 8 | 8 | 8 |
| `offsetof_fam_data` | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| `sizeof_enum` | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 4 |
| `sizeof_wchar_t` | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 4 |
| `char_is_signed` | **1** | **1** | 0 | **1** | 0 | 0 | 0 | 0 |
| `sizeof_bool` | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 |

What to take from it:

- **i386 SysV aligns `uint64_t` to 4 inside structs.** AAPCS32 aligns it to 8. A struct with a `uint64_t` after a `uint32_t` has *different offsets* on a 32-bit x86 host tool and on the 32-bit ARM target it talks to. Note `alignof` = 4 (the ABI alignment) versus `__alignof__` = 8 (the *preferred* alignment) on i386. GCC 8 and later, and Clang, distinguish them, and only the former governs struct layout.
- **`char` signedness splits by ABI, not by architecture.** It is signed on x86 and on Apple arm64, and **unsigned on AArch64 Linux, ARM32 and RISC-V**. `char c = 0xFF; if (c < 0)` is true on a Mac and false on a Linux arm64 server running the same code. Linux 6.2 made the kernel build with `-funsigned-char` on every architecture to end this.
- **`long double` is 16 bytes (binary128) on AArch64 Linux, 8 bytes (binary64) on Apple arm64, and 12 or 16 bytes (x87 80-bit) on x86.** Never put it in a shared struct.
- **`max_align_t` is 8 on 32-bit ARM.** `malloc` on a Cortex-M or Cortex-A7 guarantees only 8-byte alignment. That is never enough for a 32- or 64-byte cache-line DMA buffer (§1.8).
- **`enum` is 4 bytes with Clang on bare-metal ARM.** Clang records `Tag_ABI_enum_size = 2` ("int") in the object's EABI attributes, verified from `.eabi_attribute 26, 2`. GCC's `arm-none-eabi` defaults to short enums, `Tag_ABI_enum_size: small` (⚠ verify with `arm-none-eabi-readelf -A` on your toolchain). **Mixing GCC- and Clang-built objects with enums in shared structs is an ABI break.** The linker warns: "uses variable-size enums yet the output is to use 32-bit enums". With `-fshort-enums` Clang gives `sizeof_enum = 1` (verified). Never put an `enum` type in a cross-compiler or cross-core struct: use `uint8_t`/`uint32_t` fields and `enum` *constants*.
- **Flexible array member:** `sizeof(struct fam_msg)` is **8**, but the array starts at **5**. See §1.9.

### 1.4 Padding bytes hold unspecified values (§6.2.6.1p6) ⚡

Padding is not zero. §6.2.6.1p6 states that when a value is stored in a struct or union object, *including in a member*, the padding bytes take **unspecified** values. Three production consequences:

1. **Information leaks across trust boundaries** (CERT DCL39-C). A kernel `ioctl` that builds a struct on the stack and `copy_to_user`s it leaks the old stack contents in the padding. Many Linux CVEs follow this pattern.
2. **`memcmp` of structs is wrong** (CERT EXP42-C). Two structs with equal members can compare unequal because their padding differs.
3. **Hashing, CRCs and signatures over a struct's bytes** are nondeterministic for the same reason.

What does the compiler actually do? Source:

```c
#include <stdint.h>
#include <string.h>
struct info { uint8_t kind; uint32_t value; uint16_t flags; };   /* 12 bytes, 5 of them padding */
void sink(const struct info *i);
void fill_designated(uint8_t k, uint32_t v) { struct info i = { .kind = k, .value = v, .flags = 0u }; sink(&i); }
void fill_memset(uint8_t k, uint32_t v)     { struct info i; memset(&i, 0, sizeof i); i.kind = k; i.value = v; i.flags = 0u; sink(&i); }
```

**Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-linux-gnu`):**

```asm
fill_designated:
	sub	sp, sp, #32
	strb	w0, [sp, #4]
	add	x0, sp, #4
	stp	x29, x30, [sp, #16]
	add	x29, sp, #16
	sturh	wzr, [sp, #5]
	strb	wzr, [sp, #7]
	stp	w1, wzr, [sp, #8]
	bl	sink
	ldp	x29, x30, [sp, #16]
	add	sp, sp, #32
	ret
fill_memset:
	sub	sp, sp, #32
	str	xzr, [sp]
	strb	w0, [sp]
	mov	x0, sp
	stp	x29, x30, [sp, #16]
	add	x29, sp, #16
	stp	w1, wzr, [sp, #4]
	bl	sink
	ldp	x29, x30, [sp, #16]
	add	sp, sp, #32
	ret
```

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7):**

```asm
fill_designated:
	push	{r7, lr}
	sub	sp, #16
	strb.w	r0, [sp, #4]
	movs	r0, #0
	strh.w	r0, [sp, #5]
	strb.w	r0, [sp, #7]
	strd	r1, r0, [sp, #8]
	add	r0, sp, #4
	bl	sink
	add	sp, #16
	pop	{r7, pc}
fill_memset:
	push	{r7, lr}
	sub	sp, #16
	movs	r2, #0
	str	r2, [sp, #4]
	strb.w	r0, [sp, #4]
	add	r0, sp, #4
	str	r2, [sp, #12]
	str	r1, [sp, #8]
	bl	sink
	add	sp, #16
	pop	{r7, pc}
```

Clang 21 **zeroed the padding even in the fully designated initializer**. Look at `sturh wzr, [sp, #5]` / `strb wzr, [sp, #7]` for bytes 5–7, and the `wzr` half of `stp w1, wzr, [sp, #8]` for `flags` plus the tail padding. That is a kindness of this compiler version, **not a language guarantee**. When every member is explicitly initialized, nothing in C11 requires the padding to be zero. GCC releases have differed (⚠ verify). GCC 15 also changed `{0}` for **unions** to initialize only the first member, not the whole union. It offers `-fzero-init-padding-bits=unions|all` to restore the old behavior (⚠ verify against the GCC 15 release notes).

**Production rule:**

| Situation | Do |
|---|---|
| Struct crosses a trust boundary (user/kernel, network, flash, log) | `memset(&s, 0, sizeof s)` and *then* assign members. Or serialize field by field into a byte buffer (best: §2.3 of File 01). |
| C23 code | `struct info i = {};` The empty initializer has static-storage semantics, which include zeroing padding (C23 §6.7.10). This is the cleanest spelling. |
| Comparing or hashing structs | Compare member by member, or hash the serialized form. Never `memcmp` the struct. |
| Kernel | Follow the existing practice (`memset` + assignment). Recent kernels also lean on compiler padding-zeroing flags (⚠ verify for your tree). |

### 1.5 `__attribute__((packed))`: what it really buys

`packed` (GCC/Clang) sets every member's alignment to 1 and removes all padding. The compiler must then assume *every* member access may be misaligned, and must emit code that is legal at any address on the target ISA:

```c
#include <stdint.h>
struct __attribute__((packed)) pk { uint8_t tag; uint32_t val; };
uint32_t pk_get(const struct pk *p) { return p->val; }
uint32_t *pk_addr(struct pk *p) { return &p->val; }
```

**Diagnostic (verified, every target):**

```text
packed.c:4:43: warning: taking address of packed member 'val' of class or structure 'pk' may result in an unaligned pointer value [-Waddress-of-packed-member]
```

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M0+):**

```asm
pk_get:
	ldrb	r1, [r0, #1]
	ldrb	r2, [r0, #2]
	lsls	r2, r2, #8
	adds	r1, r2, r1
	ldrb	r2, [r0, #3]
	lsls	r2, r2, #16
	ldrb	r0, [r0, #4]
	lsls	r0, r0, #24
	adds	r0, r0, r2
	adds	r0, r0, r1
	bx	lr
pk_addr:
	adds	r0, r0, #1
	bx	lr
```

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7):**

```asm
pk_get:
	ldr.w	r0, [r0, #1]
	bx	lr
pk_addr:
	adds	r0, #1
	bx	lr
```

**Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-linux-gnu`):**

```asm
pk_get:
	ldur	w0, [x0, #1]
	ret
pk_addr:
	add	x0, x0, #1
	ret
```

The three ISAs give three strategies:

- **Cortex-M0+** (no unaligned support): four byte loads.
- **Cortex-M7**: one unaligned `LDR`.
- **AArch64**: one `LDUR`. That is fine on Normal memory and an **Alignment fault on Device memory**.

The fatal mistake is `pk_addr`. It returns a plain `uint32_t *` that no longer carries the "may be misaligned" knowledge. The first caller that reads `*p` together with a neighbor gets `LDRD` (File 01 §2.3), or uses it with an atomic (exclusives require alignment), and faults.

**Packed on MMIO is a double failure.** On AArch64 the compiler may emit a misaligned or byte-split access to a Device page: an alignment fault, or several partial register writes the peripheral misinterprets. On Cortex-M0+ it emits four `LDRB`s to a 32-bit register. Many peripherals ignore byte writes or return a bus error. Others, like read-to-clear FIFOs, *pop four times*. **Never `packed` a register map.** Register maps are naturally aligned by construction, so you never need it.

When you genuinely need wire-exact layout, use the File 01 byte-wise serializers. If you know the buffer base is 4-aligned and only some fields are misaligned, `__attribute__((packed, aligned(4)))` restores the struct's alignment so the compiler can use word loads for the aligned members.

### 1.6 Bit-fields: an implementation-defined minefield 🔥

What C leaves to the implementation (§6.7.2.1p5, p11, and Annex J.3.9):

| Property | Standard says | AAPCS (little-endian) | AAPCS (big-endian, BE8) |
|---|---|---|---|
| Permitted types | `_Bool`, `signed int`, `unsigned int`, plus implementation-defined others (C23 adds `_BitInt(N)`) | GCC/Clang accept any integer type as the container | same |
| Plain `int` bit-field signedness | Implementation-defined | Signed (GCC/Clang); MISRA Rule 6.1 bans plain `int` | same |
| Allocation order within a unit | Implementation-defined | **From the least significant bit** | **From the most significant bit** |
| Straddling a unit boundary | Implementation-defined | Not straddled; the container type sets the unit | same |
| Alignment of the storage unit | Unspecified | The container type's alignment | same |
| Access width for `volatile` bit-fields | Implementation-defined ("what constitutes an access") | The AAPCS requires the **container's width** (`-fstrict-volatile-bitfields` in GCC, ⚠ verify the default; `-faapcs-bitfield-width` in Clang) | same |

#### 1.6.1 Proof: the same initializer gives two different register images

```c
#include <stdint.h>
struct ctrl_bf { uint32_t en:1; uint32_t mode:3; uint32_t div:8; uint32_t :4; uint32_t irq:16; };
struct ctrl_bf make_ctrl(void) { struct ctrl_bf c = { .en = 1u, .mode = 5u, .div = 0x3Cu, .irq = 0xBEEFu }; return c; }
uint32_t ctrl_as_word(void) { struct ctrl_bf c = make_ctrl(); uint32_t w; __builtin_memcpy(&w, &c, sizeof w); return w; }
```

**Codegen (verified — Clang 21.1.0, `-O2`):**

```asm
@ Cortex-M7, little-endian (thumbv7em-none-eabihf)
ctrl_as_word:
	movw	r0, #971
	movt	r0, #48879
	bx	lr
```

```asm
; aarch64-linux-gnu, little-endian
ctrl_as_word:
	mov	w0, #971
	movk	w0, #48879, lsl #16
	ret
```

```asm
@ Cortex-M7 built big-endian BE8 (thumbebv7em-none-eabihf)
ctrl_as_word:
	movw	r0, #48879
	movt	r0, #54208
	bx	lr
```

```asm
; aarch64_be-linux-gnu
ctrl_as_word:
	mov	w0, #48879
	movk	w0, #54208, lsl #16
	ret
```

Decoding the constants:

```text
Little-endian: 0xBEEF03CB          Big-endian: 0xD3C0BEEF
 bit 31                    0        bit 31                    0
 [ irq=0xBEEF ][0][div=3C][101][1]  [1][101][div=3C][0][ irq=0xBEEF ]
   31..16     15..12 11..4  3..1 0  31 30..28 27..20 19..16  15..0
```

The datasheet says "EN is bit 0". The big-endian build puts `en` at **bit 31**. Every field of the register is wrong, and the code compiles without a warning. ARM is bi-endian, and some automotive/networking SoCs and DSP subsystems run BE8 (Cortex-M endianness is fixed at reset by the implementation and readable in `AIRCR.ENDIANNESS`, bit 15). A register header built on bit-fields is therefore **not portable even across builds for the same silicon**.

#### 1.6.2 Proof: a bit-field write is a read-modify-write, and W1C registers punish it ⚡

```c
#include <stdint.h>
/* Hypothetical UART status: bits 0..3 are W1C error flags, bit 8 is a R/W enable. */
typedef struct {
    volatile uint32_t PE  : 1;
    volatile uint32_t FE  : 1;
    volatile uint32_t NE  : 1;
    volatile uint32_t ORE : 1;
    volatile uint32_t     : 4;
    volatile uint32_t EN  : 1;
    volatile uint32_t     : 23;
} uart_sr_bits_t;
void clear_ore_bitfield(uart_sr_bits_t *sr)   { sr->ORE = 1u; }
void clear_ore_w1c(volatile uint32_t *sr)     { *sr = (1u << 3); }

typedef struct { volatile uint32_t a : 8; volatile uint32_t b : 8; volatile uint32_t c : 16; } vbf_t;
void     vbf_set_b(vbf_t *p) { p->b = 0x5Au; }
uint32_t vbf_get_b(vbf_t *p) { return p->b; }

typedef struct { volatile uint8_t en : 1; volatile uint8_t mode : 3; volatile uint8_t : 4; volatile uint8_t pre; volatile uint16_t rsvd; } ctrl8_t;
void ctrl8_set_mode(ctrl8_t *c, unsigned m) { c->mode = m & 7u; }
```

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7):**

```asm
clear_ore_bitfield:
	ldr	r1, [r0]
	orr	r1, r1, #8
	str	r1, [r0]
	bx	lr
clear_ore_w1c:
	movs	r1, #8
	str	r1, [r0]
	bx	lr
vbf_set_b:
	ldr	r1, [r0]
	movs	r2, #90
	bfi	r1, r2, #8, #8
	str	r1, [r0]
	bx	lr
vbf_get_b:
	ldr	r0, [r0]
	ubfx	r0, r0, #8, #8
	bx	lr
ctrl8_set_mode:
	ldrb	r2, [r0]
	and	r1, r1, #7
	and	r2, r2, #241
	orr.w	r1, r2, r1, lsl #1
	strb	r1, [r0]
	bx	lr
```

The W1C failure, as a timeline:

```text
t0  SR = 0b0000_0001_0000_0101   (EN=1, PE=1, NE=1 pending; the ISR is about to handle them)
t1  thread: clear_ore_bitfield()  ->  ldr r1, [SR]          r1 = 0x105
t2                                    orr r1, r1, #8          r1 = 0x10D
t3                                    str r1, [SR]            writes 1s to PE, NE, ORE (and EN)
t4  hardware: W1C semantics clear PE and NE too  ->  the parity and noise errors are LOST
```

`clear_ore_w1c` writes exactly one bit and is correct. **No bit-field syntax can express "write 1 to this bit and 0 to all the others".** A bit-field assignment *always* reads the container first. Two related hazards:

- **Read-to-clear (RC) registers.** The read half of the RMW clears flags you didn't intend to consume.
- **`rc_w0` registers** (write 0 to clear, writing 1 has no effect; STM32 timer `SR` flags are the classic example). Even a hand-written `SR &= ~UIF` RMW races with hardware: a flag set between the `ldr` and the `str` is written back as 0 and lost. The vendor-recommended pattern is a single write, `SR = ~UIF`.

`ctrl8_set_mode` shows the **access-width** hazard. A bit-field declared in a `uint8_t` container produces `LDRB`/`STRB`, which are byte-lane accesses (AHB `HSIZE = byte`, AXI `WSTRB = 0b0001`). Many APB/AHB peripherals implement only 32-bit register access. Depending on the bus bridge, a byte write is ignored, replicated across lanes, or answered with an **error response**, which becomes a BusFault (`PRECISERR` with `BFAR` = the register, or `IMPRECISERR` if buffered).

#### 1.6.3 Bit-fields and concurrency: one memory location (§3.14)

§3.14 defines a *memory location* as a scalar object or **a maximal sequence of adjacent non-zero-width bit-fields**. Two bit-fields in the same sequence are the same memory location. A thread writing `flags.a` and an ISR writing `flags.b` is a **data race** (UB), and in hardware terms a lost update: both do `ldr / bfi / str` on the same word, and the last `str` wins. A zero-width bit-field (`unsigned : 0;`) starts a new memory location, but a separate scalar per writer is clearer.

#### 1.6.4 What the industry does instead

- **Linux:** `<linux/bitfield.h>` provides `GENMASK(h, l)`, `FIELD_PREP(mask, val)`, `FIELD_GET(mask, reg)`, `FIELD_FIT`. They have compile-time mask checks, and the shift is derived from the mask, so each field is described once. Bit-fields are banned for hardware registers by review culture.
- **CMSIS / SVD headers:** `UART_CR1_UE_Pos`, `UART_CR1_UE_Msk`, plus the `_VAL2FLD(field, value)` and `_FLD2VAL(field, value)` macros. Vendor SVD-generated headers follow the same `_Pos`/`_Msk` convention.
- **Hardware-atomic set/clear aliases remove RMW entirely:**
  - STM32 `GPIOx->BSRR` (write-only set/reset halves);
  - NXP `…_SET`/`…_CLR`/`…_TOG` register aliases;
  - RP2040 per-peripheral atomic aliases (+0x1000 XOR, +0x2000 SET, +0x3000 CLR);
  - Cortex-M3/M4 **bit-banding**: a word write to `0x2200_0000 + (byte_offset × 32) + (bit × 4)` atomically sets or clears one SRAM bit, and `0x4200_0000 + …` does the same for peripherals. Bit-banding is optional on M3/M4 and **absent on Cortex-M7 and the ARMv8-M cores**.

The blueprint in §2.2 is a C11 `regfield.h` in the Linux style, with every mask proven contiguous at compile time.

### 1.7 Endianness

**Endianness** is the mapping from a multi-byte value to ascending byte addresses. Little-endian puts the least significant byte at the lowest address. On ARM:

- **ARMv6 and later use BE8** for big-endian: *data* accesses are big-endian, *instruction* fetches stay little-endian. Legacy ARMv5 BE32 swapped instruction words too.
- **AArch64:**
  - `SCTLR_EL1.EE` (bit 25) selects EL1 data endianness and the endianness of translation-table walks;
  - `SCTLR_EL1.E0E` (bit 24) selects EL0 data endianness;
  - the `aarch64_be` toolchain targets the BE configuration (verified above).
- **Cortex-M:** fixed at reset by the implementer, and reported read-only in `AIRCR.ENDIANNESS`.

The world you interface with:

| Domain | Byte order |
|---|---|
| IP/TCP/UDP headers ("network byte order") | Big-endian |
| PCIe configuration space and TLP payloads; USB descriptors; most SoC register files; Ethernet MAC descriptors | Little-endian |
| Some IP blocks and DSP subsystems, legacy PowerPC/Coldfire peripherals, CAN payload conventions | Big-endian (check the TRM) |
| Bit order on serial wires (SPI MSB-first vs LSB-first, UART LSB-first) | Separate question: *bit* order on the wire is not *byte* order in memory |

**Endian-neutral code is byte-oriented code.** Write the loads and stores as shifts on bytes. Compilers recognize the idioms and emit the ideal instruction:

```c
#include <stdint.h>
uint32_t load_be32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}
uint32_t load_le32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
void store_be32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v >> 24); p[1] = (uint8_t)(v >> 16); p[2] = (uint8_t)(v >> 8); p[3] = (uint8_t)v;
}
```

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7):**

```asm
load_be32:
	ldr	r0, [r0]
	rev	r0, r0
	bx	lr
load_le32:
	ldr	r0, [r0]
	bx	lr
store_be32:
	rev	r1, r1
	str	r1, [r0]
	bx	lr
```

**Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-linux-gnu`):**

```asm
load_be32:
	ldr	w8, [x0]
	rev	w0, w8
	ret
load_le32:
	ldr	w0, [x0]
	ret
store_be32:
	rev	w8, w1
	str	w8, [x0]
	ret
```

**Codegen (verified — Clang 21.1.0, `-O2`, `x86_64-linux-gnu`; and with `-mmovbe`):**

```asm
load_be32:
	movl	(%rdi), %eax
	bswapl	%eax
	retq
load_le32:
	movl	(%rdi), %eax
	retq
store_be32:
	bswapl	%esi
	movl	%esi, (%rdi)
	retq
```

```asm
# -mmovbe (Atom, Haswell+): load and swap fused
load_be32:
	movbel	(%rdi), %eax
	retq
```

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M0+; no unaligned loads, so the bytes are kept):**

```asm
load_be32:
	ldrb	r1, [r0]
	lsls	r1, r1, #24
	ldrb	r2, [r0, #1]
	lsls	r2, r2, #16
	adds	r1, r2, r1
	ldrb	r2, [r0, #2]
	lsls	r2, r2, #8
	adds	r1, r1, r2
	ldrb	r0, [r0, #3]
	adds	r0, r1, r0
	bx	lr
load_le32:
	ldrb	r1, [r0]
	ldrb	r2, [r0, #1]
	lsls	r2, r2, #8
	adds	r1, r2, r1
	ldrb	r2, [r0, #2]
	lsls	r2, r2, #16
	adds	r1, r1, r2
	ldrb	r0, [r0, #3]
	lsls	r0, r0, #24
	adds	r0, r1, r0
	bx	lr
store_be32:
	strb	r1, [r0, #3]
	lsrs	r2, r1, #8
	strb	r2, [r0, #2]
	lsrs	r2, r1, #16
	strb	r2, [r0, #1]
	lsrs	r1, r1, #24
	strb	r1, [r0]
	bx	lr
```

**Codegen (verified — Clang 21.1.0, `-O2`, `riscv64-linux-gnu`, generic RV64GC; first function):**

```asm
load_be32:
	lbu	a1, 0(a0)
	lbu	a2, 1(a0)
	lbu	a3, 2(a0)
	lbu	a0, 3(a0)
	slliw	a1, a1, 24
	slli	a2, a2, 16
	or	a1, a1, a2
	slli	a3, a3, 8
	or	a0, a0, a3
	or	a0, a0, a1
	ret
```

On generic RV64GC, the compiler may not assume fast or legal unaligned scalar loads (the RVA profiles make them a separate feature), and the base ISA has no byte-reverse instruction (that is Zbb `rev8`). So it emits byte loads and shifts. The same C source yields the optimal code on all five ISAs. **That is the argument for byte-oriented code**, and against `htonl` plus casts, which also isn't available on bare metal.

Endianness tooling:

- GCC/Clang predefine `__BYTE_ORDER__` with values `__ORDER_LITTLE_ENDIAN__` and `__ORDER_BIG_ENDIAN__`, and provide `__builtin_bswap16/32/64`.
- C23 adds `__STDC_ENDIAN_NATIVE__` / `__STDC_ENDIAN_LITTLE__` / `__STDC_ENDIAN_BIG__` through `<stdbit.h>`. That is a *library* header: glibc 2.39 and later provide it, but many bare-metal C libraries don't yet (⚠ verify for your newlib/picolibc).
- Linux annotates `__le32`/`__be32` as `__bitwise` types that `sparse` checks, and converts with `cpu_to_le32()`/`le32_to_cpu()`. Its MMIO accessors `readl()`/`writel()` are **defined as little-endian** (and add ordering barriers). `ioread32be()` exists for BE devices.

### 1.8 Cache lines: geometry, false sharing, and DMA 🔥

#### 1.8.1 Geometry

| Core | L1 D-cache line | Notes |
|---|---|---|
| Cortex-M7 | **32 B** | Optional 4–64 KB L1D, 4-way. `CCSIDR` at `0xE000_ED80` (select with `CSSELR`, `0xE000_ED84`); `LineSize` field = log2(words) − 2 |
| Cortex-A7/A53/A55/A7x/X-series, Neoverse N/V | **64 B** | Read `CTR_EL0.DminLine` |
| Apple M1–M4 (P-cores) | **128 B** | `sysctl hw.cachelinesize` reports 128 |
| x86-64 (Intel/AMD) | 64 B | The L2 *adjacent-line* spatial prefetcher pulls 128-byte-aligned pairs, so many libraries pad hot shared data to **128 B** |
| IBM POWER9/10 | 128 B | (none) |

At runtime on AArch64, use `CTR_EL0` (EL0 can read it if `SCTLR_EL1.UCT = 1`, which Linux sets):

```c
uint64_t read_ctr_el0(void) { uint64_t v; __asm__ volatile("mrs %0, ctr_el0" : "=r"(v)); return v; }
```

**Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-linux-gnu`):**

```asm
read_ctr_el0:
	mrs	x0, CTR_EL0
	ret
```

`CTR_EL0` fields:

| Field | Bits | Meaning |
|---|---|---|
| `IminLine` | `[3:0]` | log2 words of the smallest I-cache line |
| `L1Ip` | `[15:14]` | L1 I-cache policy |
| `DminLine` | `[19:16]` | log2 words of the smallest D/unified line; bytes = `4 << DminLine` |
| `ERG` | `[23:20]` | **Exclusives Reservation Granule**, log2 words. `LDXR`/`STXR` monitors track this granule, so two lock words in one ERG interfere (Folder 05) |
| `CWG` | `[27:24]` | **Cache Writeback Granule**, log2 words. The largest unit a writeback can touch. **DMA buffers must be aligned to CWG, not just DminLine.** `0` means "not reported; assume the architectural maximum of 2 KB" |
| `IDC` | `[28]` | D-cache clean to PoU not required for I/D coherence |
| `DIC` | `[29]` | I-cache invalidation to PoU not required |

Linux arm64 sets `ARCH_DMA_MINALIGN = 128` to cover the largest CWG seen in shipping cores. Since Linux 6.5, small `kmalloc` buffers can be less aligned, with `swiotlb` bouncing for non-coherent DMA.

#### 1.8.2 False sharing, first principles

Under MESI/MOESI, a core must own a line in **M** (Modified) or **E** (Exclusive) state before it writes. Suppose core 0 writes `head` and core 1 writes `tail`, and both live in the same 64-byte line. Every write then sends a *read-for-ownership* (RFO) through the interconnect and invalidates the other core's copy. The line ping-pongs. Each transfer costs on the order of an L2/LLC round trip or a cross-cluster snoop, versus about one cycle for an L1 hit (Drepper §6.4; measure your part, ⚠ verify the numbers for a specific SoC). Throughput collapses even though the program has no logical sharing.

```c
#include <stdalign.h>
#include <stdatomic.h>
#include <stddef.h>
#include <stdint.h>
struct spsc_idx_naive  { _Atomic uint32_t head; _Atomic uint32_t tail; };
struct spsc_idx_padded { alignas(64) _Atomic uint32_t head; alignas(64) _Atomic uint32_t tail; };
_Static_assert(offsetof(struct spsc_idx_padded, tail) == 64u, "tail must own its own line");
_Static_assert(sizeof(struct spsc_idx_padded) == 128u, "two full lines");
alignas(32) uint8_t dma_rx_buf[512];
struct spsc_idx_padded g_idx;
```

**Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-linux-gnu`, directives kept):**

```asm
	.p2align	5, 0x0
dma_rx_buf:
	.zero	512
	.p2align	6, 0x0
g_idx:
	.zero	128
```

The `alignas` requests become ELF section alignment (`.p2align 5` = 32 bytes, `.p2align 6` = 64 bytes). The linker then honors them through the output section's `sh_addralign` (Folder 02). The `_Static_assert`s fail the build if anyone reorders or retypes the fields.

#### 1.8.3 The DMA alignment rule (preview of Folder 03) ⚡

For a non-coherent DMA master and a write-back D-cache, **a DMA buffer must start and end on a cache-line boundary (CWG on Cortex-A), and no CPU-written variable may share any of its lines.** Otherwise:

- **RX invalidate** discards a neighbor's dirty data that shares the first or last line;
- or a CPU write to the neighbor **evicts a stale copy of the line over the freshly DMA'd bytes**.

The size must be **rounded up** too: a 1522-byte frame buffer on a 32-byte-line M7 needs 1536 bytes, or its last line is shared with whatever follows.

The **descriptor ring** variant is the one that survives code review. A DMA IP block typically uses 16-byte descriptors. On Cortex-M7, two descriptors share each 32-byte line. When the driver cleans descriptor *i* after re-arming it, the clean writes back the whole line, **including descriptor *i+1*, which the DMA engine may have just written its status into**. The engine's update is overwritten with the CPU's stale copy: `OWN` flips back, the length reverts, and frames are dropped or replayed. There are two fixes: pad every descriptor to a full line (§2.4), or put the ring in an MPU-configured non-cacheable region (Folder 02/03).

`aligned_alloc(alignment, size)` (C11) is the heap answer. C11 as published required `size` to be a multiple of `alignment`, and the rules were then revised (DR 460, and again in C23; ⚠ verify the exact wording for your target standard). Portable code rounds `size` up to a multiple of `alignment` anyway, which the DMA rule needs regardless. A static `alignas(LINE)` array with a rounded-up size is better still in firmware.

### 1.9 Flexible array members: `sizeof` lies by design

```c
struct fam_msg { uint32_t len; uint8_t type; uint8_t data[]; };
```

The verified table gives `sizeof(struct fam_msg) == 8` and `offsetof(struct fam_msg, data) == 5` on every target. `sizeof` includes the tail padding needed to round to `alignof(uint32_t)`. The array begins *inside* that padding.

- `malloc(sizeof(struct fam_msg) + n)` **over-allocates** by 3 bytes. That is harmless, but sloppy.
- `malloc(offsetof(struct fam_msg, data) + n)` is exact, but must be **at least `sizeof`** when `n` is small, so that whole-struct copies stay in bounds. The correct size is `max(sizeof(struct fam_msg), offsetof(struct fam_msg, data) + n)`, with overflow checks.
- Linux `struct_size(p, member, n)` (`include/linux/overflow.h`) computes this with saturation to `SIZE_MAX` on overflow, so that `kmalloc` fails instead of under-allocating.
- **Bounds checking:**
  - `-fstrict-flex-arrays=3` (GCC 13, Clang 16) stops treating trailing `[1]`/`[0]` arrays as flexible.
  - `__attribute__((counted_by(len)))` (Clang 18, GCC 15; ⚠ verify) tells `__builtin_dynamic_object_size` and `-fsanitize=bounds` the run-time length.
- MISRA C:2012 Rule 18.7 bans flexible array members outright. Safety code uses fixed maximum-size arrays.

---

## 2. Production C Code Blueprints

### 2.1 The Subtle Buggy Way: a bit-field register overlay

```c
/* uart_bitfield_bad.h - looks like the datasheet, compiles cleanly, and is wrong on
 * every axis this file covers. */
#include <stdint.h>

typedef struct {
    volatile uint32_t UE     : 1;   /* bit 0 ... on little-endian AAPCS only     */
    volatile uint32_t        : 1;
    volatile uint32_t RE     : 1;
    volatile uint32_t TE     : 1;
    volatile uint32_t        : 1;
    volatile uint32_t RXNEIE : 1;
    volatile uint32_t        : 2;
    volatile uint32_t PARITY : 2;
    volatile uint32_t        : 2;
    volatile uint32_t STOP   : 2;
    volatile uint32_t        : 18;
} uart_cr_bits_t;

typedef struct {
    volatile uint32_t PE  : 1;      /* W1C ... but bit-field writes are RMW        */
    volatile uint32_t FE  : 1;
    volatile uint32_t NE  : 1;
    volatile uint32_t ORE : 1;
    volatile uint32_t     : 28;
} uart_sr_bits_t;

typedef struct {
    uart_cr_bits_t CR;              /* 0x00 */
    uart_sr_bits_t SR;              /* 0x04: W1C flags cleared by writing SR itself */
    volatile uint32_t DR;           /* 0x08 */
    volatile uint32_t BRR;          /* 0x0C */
} __attribute__((packed)) uart_bad_t;  /* "packed to match the datasheet" */

static inline void uart_bad_config(uart_bad_t *u)
{
    u->CR.UE = 0;                   /* RMW #1                                     */
    u->BRR = 0x2711u;
    u->CR.PARITY = 2;               /* RMW #2: the UART runs half-configured here */
    u->CR.STOP = 2;                 /* RMW #3                                     */
    u->CR.RE = 1;                   /* RMW #4                                     */
    u->CR.TE = 1;                   /* RMW #5                                     */
    u->CR.UE = 1;                   /* RMW #6                                     */
    u->SR.ORE = 1;                  /* RMW on W1C: clears PE/FE/NE too            */
}
```

**Diagnostics (verified):** a TU that calls `uart_bad_config()` compiles with **zero diagnostics** under the full warning set (`-std=c11`) on Cortex-M7, Cortex-M0+ and AArch64.

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7):**

```asm
cfg:
	ldr	r1, [r0]
	movs	r2, #2
	bic	r1, r1, #1
	str	r1, [r0]
	movw	r1, #10001
	str	r1, [r0, #12]
	ldr	r1, [r0]
	bfi	r1, r2, #8, #2
	str	r1, [r0]
	ldr	r1, [r0]
	bfi	r1, r2, #12, #2
	str	r1, [r0]
	ldr	r1, [r0]
	orr	r1, r1, #4
	str	r1, [r0]
	ldr	r1, [r0]
	orr	r1, r1, #8
	str	r1, [r0]
	ldr	r1, [r0]
	orr	r1, r1, #1
	str	r1, [r0]
	ldr	r1, [r0, #4]
	orr	r1, r1, #8
	str	r1, [r0, #4]
	bx	lr
```

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M0+), the full 81 lines:**

```asm
cfg:
	push	{r4, r5, r7, lr}
	ldrb	r1, [r0]
	ldrb	r2, [r0, #1]
	ldrb	r3, [r0, #2]
	ldrb	r4, [r0, #3]
	strb	r4, [r0, #3]
	strb	r3, [r0, #2]
	strb	r2, [r0, #1]
	movs	r2, #254
	ands	r2, r1
	strb	r2, [r0]
	movs	r1, #0
	strb	r1, [r0, #15]
	strb	r1, [r0, #14]
	movs	r1, #39
	strb	r1, [r0, #13]
	movs	r1, #17
	strb	r1, [r0, #12]
	ldrb	r1, [r0, #1]
	ldrb	r2, [r0]
	ldrb	r3, [r0, #2]
	ldrb	r4, [r0, #3]
	strb	r4, [r0, #3]
	strb	r3, [r0, #2]
	strb	r2, [r0]
	movs	r2, #252
	ands	r2, r1
	adds	r1, r2, #2
	strb	r1, [r0, #1]
	ldrb	r1, [r0, #1]
	ldrb	r2, [r0]
	ldrb	r3, [r0, #2]
	ldrb	r4, [r0, #3]
	strb	r4, [r0, #3]
	strb	r3, [r0, #2]
	strb	r2, [r0]
	movs	r2, #207
	ands	r2, r1
	adds	r2, #32
	strb	r2, [r0, #1]
	ldrb	r1, [r0]
	ldrb	r2, [r0, #1]
	ldrb	r3, [r0, #2]
	ldrb	r4, [r0, #3]
	strb	r4, [r0, #3]
	strb	r3, [r0, #2]
	strb	r2, [r0, #1]
	movs	r2, #4
	orrs	r2, r1
	strb	r2, [r0]
	ldrb	r2, [r0]
	ldrb	r1, [r0, #1]
	ldrb	r3, [r0, #2]
	ldrb	r4, [r0, #3]
	strb	r4, [r0, #3]
	strb	r3, [r0, #2]
	strb	r1, [r0, #1]
	movs	r1, #8
	orrs	r2, r1
	strb	r2, [r0]
	ldrb	r2, [r0]
	ldrb	r3, [r0, #1]
	ldrb	r4, [r0, #2]
	ldrb	r5, [r0, #3]
	strb	r5, [r0, #3]
	strb	r4, [r0, #2]
	strb	r3, [r0, #1]
	movs	r3, #1
	orrs	r3, r2
	strb	r3, [r0]
	ldrb	r2, [r0, #4]
	ldrb	r3, [r0, #5]
	ldrb	r4, [r0, #6]
	ldrb	r5, [r0, #7]
	strb	r5, [r0, #7]
	strb	r4, [r0, #6]
	strb	r3, [r0, #5]
	orrs	r2, r1
	strb	r2, [r0, #4]
	pop	{r4, r5, r7, pc}
```

The two listings are the indictment:

- **Cortex-M7:** **six `ldr`/modify/`str` sequences on `CR`** for one configuration, then an RMW on `SR` (`ldr r1, [r0, #4]` / `orr #8` / `str`) that writes back every pending W1C error flag it just read.
- **Cortex-M0+:** `packed` lowered every register access to **byte lanes**. Each bit-field write became four `ldrb` plus four `strb`. It re-writes all four bytes of the register, including bytes it didn't change, and it does so in *descending* order (`[r0, #3]` first). The 32-bit `BRR` store became four separate `strb` (`#15`…`#12`). On a word-only APB peripheral, every one of these accesses is ignored or answered with a bus error. On a peripheral that tolerates byte writes, the register passes through 3 intermediate values per field update. The status-register RMW at the end (`[r0, #4]`…`#7`) clears the W1C flags byte by byte.

Everything wrong with it, cross-referenced:

1. **Bit order** is right only for little-endian AAPCS, and wrong on a BE8 build (§1.6.1, verified).
2. **Access width** follows the container type, which is the AAPCS rule. A refactor to `uint8_t` containers silently produces byte accesses (verified `ldrb/strb`).
3. **Six read-modify-writes** to configure one register. Each is a separate bus transaction on the APB, with the peripheral transiently in partially configured states. A concurrent ISR RMW of `CR` (say, toggling `RXNEIE`) races with every one of them.
4. **The W1C clear destroys other pending error flags** (§1.6.2, verified `ldr/orr/str`).
5. **`packed`** on a register map buys nothing (it's already aligned) and licenses the compiler to emit byte-split accesses on cores without unaligned support. The M0+ listing above shows every register access becoming 4 × `ldrb` + 4 × `strb`.
6. **No offset assertions:** a missing `RESERVED` word shifts every register after it, silently.

### 2.2 The Silicon-Hardened Production Way: `regfield.h` + register map + driver

`regfield.h`:

```c
/* regfield.h - portable, endian-independent register field access (C11).
 * Masks are compile-time constants; shifts are derived from the mask, so a
 * field is described exactly once. Modeled on Linux <linux/bitfield.h>. */
#ifndef REGFIELD_H
#define REGFIELD_H

#include <stdbool.h>
#include <stdint.h>

#define BIT32(n)            ((uint32_t)1u << (n))
/* GENMASK32(h, l): bits h..l inclusive, 0 <= l <= h <= 31. */
#define GENMASK32(h, l)     ((uint32_t)((~(uint32_t)0u >> (31u - (uint32_t)(h))) & \
                                        (~(uint32_t)0u << (uint32_t)(l))))

/* Lowest set bit of a non-zero constant mask: (m & (~m + 1)). */
#define MASK_LSB32(m)       ((uint32_t)((uint32_t)(m) & (~(uint32_t)(m) + 1u)))
/* A mask is a valid field iff it is non-zero and its set bits are contiguous. */
#define MASK_IS_FIELD32(m)  (((uint32_t)(m) != 0u) && \
                             ((((uint32_t)(m) + MASK_LSB32(m)) & (uint32_t)(m)) == 0u))
#define FIELD_SHIFT32(m)    ((uint32_t)__builtin_ctz((uint32_t)(m)))

/* Constant-expression forms (usable in _Static_assert and initializers). */
#define FIELD_PREP32(m, v)  ((uint32_t)(((uint32_t)(v) << FIELD_SHIFT32(m)) & (uint32_t)(m)))
#define FIELD_GET32(m, r)   ((uint32_t)(((uint32_t)(r) & (uint32_t)(m)) >> FIELD_SHIFT32(m)))
#define FIELD_MAX32(m)      ((uint32_t)((uint32_t)(m) >> FIELD_SHIFT32(m)))
#define FIELD_FITS32(m, v)  ((uint32_t)(v) <= FIELD_MAX32(m))

/* Declare a field and prove it is well-formed at compile time. */
#define REGFIELD_ASSERT(m)  _Static_assert(MASK_IS_FIELD32(m), #m " is not a contiguous field")

/* Replace one field in a register image (pure: no hardware access). */
static inline uint32_t field_replace32(uint32_t reg, uint32_t mask, uint32_t val)
{
    return (reg & ~mask) | ((val << (uint32_t)__builtin_ctz(mask)) & mask);
}

#endif /* REGFIELD_H */
```

`uart_regs.h`:

```c
/* uart_regs.h - register map for a hypothetical APB UART at 0x4001_1000. */
#ifndef UART_REGS_H
#define UART_REGS_H

#include <stddef.h>
#include <stdint.h>

#include "regfield.h"

typedef struct {
    volatile uint32_t       CR;           /* 0x00 control                       RW  */
    const volatile uint32_t SR;           /* 0x04 status                        RO  */
    volatile uint32_t       DR;           /* 0x08 data (bits 8:0)               RW  */
    volatile uint32_t       BRR;          /* 0x0C baud-rate divisor             RW  */
    uint32_t                RESERVED0[4]; /* 0x10..0x1F: never touch            --  */
    volatile uint32_t       ICR;          /* 0x20 interrupt/error clear         W1C */
    const volatile uint32_t ID;           /* 0x24 peripheral ID                 RO  */
} uart_regs_t;

/* The layout IS the hardware contract: assert every offset. */
_Static_assert(offsetof(uart_regs_t, CR)  == 0x00u, "CR offset");
_Static_assert(offsetof(uart_regs_t, SR)  == 0x04u, "SR offset");
_Static_assert(offsetof(uart_regs_t, DR)  == 0x08u, "DR offset");
_Static_assert(offsetof(uart_regs_t, BRR) == 0x0Cu, "BRR offset");
_Static_assert(offsetof(uart_regs_t, ICR) == 0x20u, "ICR offset");
_Static_assert(offsetof(uart_regs_t, ID)  == 0x24u, "ID offset");
_Static_assert(sizeof(uart_regs_t)        == 0x28u, "block size");

/* CR fields */
#define UART_CR_UE        BIT32(0)            /* UART enable                 */
#define UART_CR_RE        BIT32(2)            /* receiver enable             */
#define UART_CR_TE        BIT32(3)            /* transmitter enable          */
#define UART_CR_RXNEIE    BIT32(5)            /* RX-not-empty IRQ enable     */
#define UART_CR_PARITY    GENMASK32(9, 8)     /* 0 none, 1 even, 2 odd       */
#define UART_CR_STOP      GENMASK32(13, 12)   /* 0 = 1 stop, 2 = 2 stop      */
REGFIELD_ASSERT(UART_CR_PARITY);
REGFIELD_ASSERT(UART_CR_STOP);

/* SR fields (read-only view; error flags are cleared through ICR) */
#define UART_SR_PE        BIT32(0)
#define UART_SR_FE        BIT32(1)
#define UART_SR_NE        BIT32(2)
#define UART_SR_ORE       BIT32(3)
#define UART_SR_RXNE      BIT32(5)
#define UART_SR_TXE       BIT32(7)
#define UART_SR_ERRORS    (UART_SR_PE | UART_SR_FE | UART_SR_NE | UART_SR_ORE)

/* ICR: write 1 to clear the matching SR error bit; writing 0 has no effect. */
#define UART_ICR_ALL      UART_SR_ERRORS

/* BRR fields */
#define UART_BRR_FRAC     GENMASK32(3, 0)
#define UART_BRR_MANT     GENMASK32(15, 4)
REGFIELD_ASSERT(UART_BRR_FRAC);
REGFIELD_ASSERT(UART_BRR_MANT);

/* Compile-time proof the macros produce what the datasheet table says. */
_Static_assert(UART_CR_PARITY == 0x00000300u, "GENMASK32(9,8)");
_Static_assert(FIELD_PREP32(UART_BRR_MANT, 0x271u) == 0x2710u, "FIELD_PREP32");
_Static_assert(FIELD_GET32(UART_BRR_MANT, 0x2710u) == 0x271u, "FIELD_GET32");

#endif /* UART_REGS_H */
```

`uart.h`:

```c
/* uart.h - driver API over uart_regs.h. */
#ifndef UART_H
#define UART_H

#include <stdbool.h>
#include <stdint.h>

#include "uart_regs.h"

typedef enum { UART_OK = 0, UART_EINVAL } uart_status_t;

typedef struct {
    uint32_t brr_mantissa;    /* 12-bit */
    uint32_t brr_fraction;    /* 4-bit  */
    uint32_t parity;          /* UART_CR_PARITY encoding */
    uint32_t stop_bits_code;  /* UART_CR_STOP encoding   */
    bool     rx_irq;
} uart_cfg_t;

uart_status_t uart_configure(uart_regs_t *u, const uart_cfg_t *cfg);
uint32_t      uart_take_errors(uart_regs_t *u);
void          uart_set_parity(uart_regs_t *u, uint32_t parity);

#endif /* UART_H */
```

`uart.c`:

```c
/* uart.c - register-level driver: one composed store per configuration,
 * W1C clears without read-modify-write, posted-write read-back. */
#include "uart.h"

uart_status_t uart_configure(uart_regs_t *u, const uart_cfg_t *cfg)
{
    if ((u == NULL) || (cfg == NULL) ||
        !FIELD_FITS32(UART_CR_PARITY, cfg->parity) ||
        !FIELD_FITS32(UART_CR_STOP, cfg->stop_bits_code) ||
        !FIELD_FITS32(UART_BRR_MANT, cfg->brr_mantissa) ||
        !FIELD_FITS32(UART_BRR_FRAC, cfg->brr_fraction)) {
        return UART_EINVAL;
    }

    /* 1. Disable first: most UARTs latch BRR/framing only while UE == 0. */
    u->CR = 0u;

    /* 2. Program the divisor in ONE store (no intermediate half-written value). */
    u->BRR = FIELD_PREP32(UART_BRR_MANT, cfg->brr_mantissa) |
             FIELD_PREP32(UART_BRR_FRAC, cfg->brr_fraction);

    /* 3. Clear stale error flags: W1C -> write exactly the bits to clear. */
    u->ICR = UART_ICR_ALL;

    /* 4. Compose the whole CR image in a register, then one store. */
    uint32_t cr = UART_CR_UE | UART_CR_RE | UART_CR_TE |
                  FIELD_PREP32(UART_CR_PARITY, cfg->parity) |
                  FIELD_PREP32(UART_CR_STOP, cfg->stop_bits_code);
    if (cfg->rx_irq) {
        cr |= UART_CR_RXNEIE;
    }
    u->CR = cr;

    /* 5. Read back: forces the posted write through the bus bridge before
     *    the caller enables the NVIC line (see Folder 06, APB write buffers). */
    (void)u->CR;
    return UART_OK;
}

uint32_t uart_take_errors(uart_regs_t *u)
{
    uint32_t err = u->SR & UART_SR_ERRORS;   /* one snapshot read            */
    if (err != 0u) {
        u->ICR = err;                        /* clear exactly what we saw:   */
    }                                        /* a flag raised after the read */
    return err;                              /* survives for the next pass   */
}

/* Read-modify-write is only legal on plain RW fields, and only by a single
 * writer (or inside a critical section if ISR and thread both write CR). */
void uart_set_parity(uart_regs_t *u, uint32_t parity)
{
    u->CR = field_replace32(u->CR, UART_CR_PARITY, parity);
}

#ifdef UART_SELFTEST
#include <stdio.h>

static uart_regs_t fake;   /* host stand-in for the MMIO block */

int main(void)
{
    const uart_cfg_t cfg = { .brr_mantissa = 0x271u, .brr_fraction = 0x1u,
                             .parity = 2u, .stop_bits_code = 2u, .rx_irq = true };
    const uart_cfg_t bad = { .brr_mantissa = 0x1000u, .brr_fraction = 0u,
                             .parity = 0u, .stop_bits_code = 0u, .rx_irq = false };
    uart_status_t st = uart_configure(&fake, &cfg);
    printf("configure: st=%d CR=0x%08X BRR=0x%08X ICR=0x%08X\n", (int)st,
           (unsigned)fake.CR, (unsigned)fake.BRR, (unsigned)fake.ICR);
    uart_set_parity(&fake, 1u);
    printf("parity->1: CR=0x%08X parity=%u\n", (unsigned)fake.CR,
           (unsigned)FIELD_GET32(UART_CR_PARITY, fake.CR));
    printf("bad mantissa: st=%d\n", (int)uart_configure(&fake, &bad));
    printf("GENMASK32(31,0)=0x%08X GENMASK32(15,4)=0x%08X FIELD_MAX32(STOP)=%u\n",
           (unsigned)GENMASK32(31, 0), (unsigned)GENMASK32(15, 4),
           (unsigned)FIELD_MAX32(UART_CR_STOP));
    return 0;
}
#endif
```

**Build evidence (verified):** zero diagnostics with the full warning set:
- `-std=c11` on Cortex-M7, Cortex-M0+, Cortex-M33, AArch64 and x86-64;
- `-std=c23` on Cortex-M7.

**Self-test output (verified, native x86-64):**

```text
configure: st=0 CR=0x0000222D BRR=0x00002711 ICR=0x0000000F
parity->1: CR=0x0000212D parity=1
bad mantissa: st=1
GENMASK32(31,0)=0xFFFFFFFF GENMASK32(15,4)=0x0000FFF0 FIELD_MAX32(STOP)=3
```

Cross-check against the field map: `CR = UE(0x1) | RE(0x4) | TE(0x8) | RXNEIE(0x20) | PARITY=2 (0x200) | STOP=2 (0x2000) = 0x222D`. ✓

**Codegen (verified — Clang 21.1.0, `-O2 -std=c11`, Cortex-M7):**

```asm
uart_configure:
	mov	r2, r0
	cmp	r0, #0
	mov.w	r0, #1
	it	ne
	cmpne	r1, #0
	bne	.LBB0_2
.LBB0_1:
	bx	lr
.LBB0_2:
	ldr	r3, [r1, #8]
	cmp	r3, #3
	bhi	.LBB0_1
	ldr.w	r12, [r1, #12]
	cmp.w	r12, #3
	it	hi
	bxhi	lr
.LBB0_4:
	push	{r4, lr}
	ldr.w	lr, [r1]
	movs	r0, #0
	cmp.w	r0, lr, lsr #12
	bne	.LBB0_7
	ldr	r4, [r1, #4]
	cmp	r4, #15
	bhi	.LBB0_7
	str	r0, [r2]
	orr.w	r4, r4, lr, lsl #4
	str	r4, [r2, #12]
	movs	r4, #15
	str	r4, [r2, #32]
	lsl.w	r4, r12, #12
	ldrb	r1, [r1, #16]
	orr.w	r3, r4, r3, lsl #8
	cmp	r1, #0
	mov.w	r1, #13
	it	ne
	movne	r1, #45
	add	r1, r3
	str	r1, [r2]
	ldr	r1, [r2]
	pop.w	{r4, lr}
	bx	lr
.LBB0_7:
	movs	r0, #1
	pop.w	{r4, lr}
	bx	lr
uart_take_errors:
	mov	r1, r0
	ldr	r0, [r0, #4]
	ands	r0, r0, #15
	it	ne
	strne	r0, [r1, #32]
	bx	lr
uart_set_parity:
	ldr	r2, [r0]
	bfi	r2, r1, #8, #2
	str	r2, [r0]
	bx	lr
```

What the listing proves:

- **Exactly four MMIO stores and one read-back** in `uart_configure`: `str r0, [r2]` (CR = 0), `str r4, [r2, #12]` (BRR), `str r4, [r2, #32]` (ICR = 0xF), `str r1, [r2]` (CR final), and `ldr r1, [r2]` (read-back). Every access is a 32-bit `str`/`ldr`. There are no byte lanes and no RMW.
- **`FIELD_PREP32` costs nothing:** `orr.w r4, r4, lr, lsl #4` *is* the BRR composition. The RXNEIE choice became `13` vs `45` (`0x0D` vs `0x2D`) via an IT block.
- **The W1C clear is a single conditional store** (`strne r0, [r1, #32]`) of exactly the bits that were observed.
- **`uart_set_parity`** is the only RMW: `ldr / bfi / str`, documented as single-writer.

### 2.3 Why the `const volatile` and `RESERVED` members matter

- **`const volatile uint32_t SR`** makes any write to the read-only register a *compile error* (assignment to a read-only member), while every read is still a real load.
- **`RESERVED0[4]`** keeps the offset arithmetic honest, and the `_Static_assert(offsetof(...))` lines **are the review artifact**. A mis-transcribed datasheet table fails the build, not the board bring-up.
- The register block is reached through one implementation-defined integer-to-pointer conversion, in a single place:
  ```c
  #define UART0 ((uart_regs_t *)0x40011000u)   /* MISRA Rule 11.4 deviation, recorded once */
  ```
  `uart_configure(UART0, &cfg)` then never repeats the cast.

### 2.4 Cache-line-exact DMA descriptor ring

`dma_ring.h`:

```c
/* dma_ring.h - descriptor ring laid out so that no two descriptors, no data
 * buffer, and no CPU-owned variable ever share a D-cache line. */
#ifndef DMA_RING_H
#define DMA_RING_H

#include <stdalign.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "regfield.h"

#ifndef DCACHE_LINE
#define DCACHE_LINE 32u      /* Cortex-M7 L1D; 64u on most Cortex-A/Neoverse; 128u on Apple M */
#endif
_Static_assert((DCACHE_LINE & (DCACHE_LINE - 1u)) == 0u, "line size must be a power of two");

#define ROUND_UP_POW2(x, a)  (((x) + ((a) - 1u)) & ~((a) - 1u))

/* The 16-byte layout the DMA IP block fetches. Offsets are the contract. */
typedef struct {
    uint32_t buf_addr;   /* 0x00 bus address of data buffer                     */
    uint32_t ctrl;       /* 0x04 [15:0] LEN, [29] LAST, [30] IRQ, [31] OWN       */
    uint32_t next;       /* 0x08 bus address of next descriptor                 */
    uint32_t status;     /* 0x0C written back by the DMA engine                 */
} dma_desc_hw_t;
_Static_assert(sizeof(dma_desc_hw_t) == 16u, "IP block expects 16-byte descriptors");
_Static_assert(offsetof(dma_desc_hw_t, status) == 0x0Cu, "status offset");

/* One descriptor per cache line: cleaning/invalidating descriptor i can never
 * write back or discard bytes of descriptor i+1 that the engine owns. */
typedef struct {
    alignas(DCACHE_LINE) dma_desc_hw_t hw;
} dma_desc_t;
_Static_assert(sizeof(dma_desc_t) == DCACHE_LINE, "descriptor must fill exactly one line");
_Static_assert(alignof(dma_desc_t) == DCACHE_LINE, "descriptor must start a line");

#define DESC_CTRL_LEN   GENMASK32(15, 0)
#define DESC_CTRL_LAST  BIT32(29)
#define DESC_CTRL_IRQ   BIT32(30)
#define DESC_CTRL_OWN   BIT32(31)
REGFIELD_ASSERT(DESC_CTRL_LEN);

#define DMA_RING_LEN    8u
#define DMA_FRAME_MAX   1522u                                  /* VLAN-tagged Ethernet */
#define DMA_BUF_BYTES   ROUND_UP_POW2(DMA_FRAME_MAX, DCACHE_LINE)

typedef struct {
    dma_desc_t desc[DMA_RING_LEN];
    alignas(DCACHE_LINE) uint8_t buf[DMA_RING_LEN][DMA_BUF_BYTES];
} dma_ring_t;
_Static_assert((DMA_BUF_BYTES % DCACHE_LINE) == 0u, "buffers end on a line boundary");
_Static_assert((offsetof(dma_ring_t, buf) % DCACHE_LINE) == 0u, "buffers start on a line boundary");
_Static_assert((sizeof(dma_ring_t) % DCACHE_LINE) == 0u, "ring ends on a line boundary");

/* True iff [p, p+n) covers whole cache lines only - the precondition for any
 * clean or invalidate-by-address that must not touch neighbouring data. */
static inline bool dma_range_is_line_exact(const void *p, size_t n)
{
    uintptr_t a = (uintptr_t)p;
    return (n != 0u) && ((a % DCACHE_LINE) == 0u) && ((n % DCACHE_LINE) == 0u);
}

/* Build the OWN-last control word: length and flags first, OWN in the same
 * single 32-bit store so the engine never sees OWN with a stale length. */
static inline uint32_t dma_ctrl_word(uint32_t len, bool last, bool irq)
{
    return FIELD_PREP32(DESC_CTRL_LEN, len) |
           (last ? DESC_CTRL_LAST : 0u) |
           (irq  ? DESC_CTRL_IRQ  : 0u) |
           DESC_CTRL_OWN;
}

#endif /* DMA_RING_H */
```

`dma_ring_test.c` (host geometry check):

```c
/* dma_ring_test.c - host check of the ring geometry for a given DCACHE_LINE. */
#include <stdio.h>

#include "dma_ring.h"

static dma_ring_t ring;

int main(void)
{
    printf("DCACHE_LINE=%u sizeof(dma_desc_t)=%zu sizeof(dma_ring_t)=%zu buf_off=%zu buf_bytes=%u\n",
           (unsigned)DCACHE_LINE, sizeof(dma_desc_t), sizeof(dma_ring_t),
           offsetof(dma_ring_t, buf), (unsigned)DMA_BUF_BYTES);
    printf("desc[1] exact=%d  buf[3] exact=%d  desc[1].hw.status alone exact=%d\n",
           (int)dma_range_is_line_exact(&ring.desc[1], sizeof ring.desc[1]),
           (int)dma_range_is_line_exact(ring.buf[3], sizeof ring.buf[3]),
           (int)dma_range_is_line_exact(&ring.desc[1].hw.status, sizeof ring.desc[1].hw.status));
    printf("ctrl(len=1514,last,irq)=0x%08X\n", (unsigned)dma_ctrl_word(1514u, true, true));
    return 0;
}
```

**Build evidence (verified):** a translation unit that includes `dma_ring.h` compiles with zero diagnostics (full warning set, `-std=c11`) on Cortex-M7, M0+, M33, AArch64 and x86-64, and with `-DDCACHE_LINE=64u` on AArch64.

**Output (verified, native, three line sizes):**

```text
DCACHE_LINE=32 sizeof(dma_desc_t)=32 sizeof(dma_ring_t)=12544 buf_off=256 buf_bytes=1536
desc[1] exact=1  buf[3] exact=1  desc[1].hw.status alone exact=0
ctrl(len=1514,last,irq)=0xE00005EA

DCACHE_LINE=64 sizeof(dma_desc_t)=64 sizeof(dma_ring_t)=12800 buf_off=512 buf_bytes=1536
desc[1] exact=1  buf[3] exact=1  desc[1].hw.status alone exact=0
ctrl(len=1514,last,irq)=0xE00005EA

DCACHE_LINE=128 sizeof(dma_desc_t)=128 sizeof(dma_ring_t)=13312 buf_off=1024 buf_bytes=1536
desc[1] exact=1  buf[3] exact=1  desc[1].hw.status alone exact=0
ctrl(len=1514,last,irq)=0xE00005EA
```

The `desc[1].hw.status alone exact=0` line is the guard working. A driver that tries to invalidate *just the status word* is asking for a partial-line operation, and `dma_range_is_line_exact` refuses it. Folder 03's `dcache_invalidate_range()` asserts this precondition. Folder 07 builds the full scatter-gather ping-pong driver on this header.

---

## 3. Hardware Debugging and Post-Mortem Diagnostics

### 3.1 Seeing the real layout

- **`pahole`** (dwarves) reads DWARF and prints offsets, sizes, holes and cache-line boundaries:
  ```text
  $ pahole -C bad_order fw.elf
  struct bad_order {
          char                       a;                    /*     0     1 */
          /* XXX 7 bytes hole, try to pack */
          uint64_t                   b;                    /*     8     8 */
          char                       c;                    /*    16     1 */
          /* size: 24, cachelines: 1, members: 3 */
          /* sum members: 10, holes: 1, sum holes: 7 */
          /* padding: 7 */
          /* last cacheline: 24 bytes */
  };
  ```
  (This is the pahole output format, with offsets matching the verified `offsetof` table; run it on your own ELF.) For kernels, `pahole --reorganize` suggests a denser order.
- **GDB:** `ptype /o struct bad_order` prints offsets and holes (GDB 8.1+).
- **Compiler:** `-Wpadded` (verified above) and, in Clang, `-Xclang -fdump-record-layouts`.
- **ABI attributes:** `arm-none-eabi-readelf -A obj.o` shows `Tag_ABI_enum_size`, `Tag_ABI_PCS_wchar_t`, `Tag_ABI_align_needed`, `Tag_ABI_VFP_args`. Diff them across every object that shares a struct. The verified Clang Cortex-M7 object carries:
  ```asm
  	.eabi_attribute	34, 1	@ Tag_CPU_unaligned_access
  	.eabi_attribute	24, 1	@ Tag_ABI_align_needed
  	.eabi_attribute	25, 1	@ Tag_ABI_align_preserved
  	.eabi_attribute	28, 1	@ Tag_ABI_VFP_args
  	.eabi_attribute	18, 4	@ Tag_ABI_PCS_wchar_t
  	.eabi_attribute	26, 2	@ Tag_ABI_enum_size
  ```

### 3.2 Bit-field and register-access bugs on the bench

| Symptom | Mechanism | How to see it |
|---|---|---|
| Error interrupts "occasionally lost"; the error counter is lower than a logic-analyzer decode of the line shows | W1C RMW clears sibling flags (§1.6.2) | Disassemble the clear: `ldr/orr/str` on the status register means guilty. SWO/ETM trace shows the RMW; a logic analyzer on the device's error IRQ output shows pulses the firmware never counted |
| Register write "doesn't take"; the read-back shows the old value | Byte-lane write to a word-only peripheral, silently ignored | Disassemble for `strb`/`strh` on MMIO; a bus analyzer or AHB trace shows `HSIZE = byte` |
| BusFault `PRECISERR`, `BFAR` = a peripheral register | Byte or halfword access answered with an AHB/APB error response | Decode CFSR bit 9 and BFAR (File 01 §5.2) |
| BusFault `IMPRECISERR`, stacked PC unrelated | Same, but the write was buffered | Set `ACTLR.DISDEFWBUF` (M3/M4) to make it precise, then re-run |
| Field values correct on dev boards, scrambled on a customer's BE build | Bit-field allocation order flips (§1.6.1) | `readelf -h` → `Data: 2's complement, big endian`; check `__BYTE_ORDER__` |
| Configuration "glitch": the peripheral briefly runs with the wrong parity or baud at enable | Sequence of RMWs exposes intermediate states (§2.1) | Logic analyzer on TX: a garbage character at enable. Compose the full value and store it once |

### 3.3 Endianness bugs in logs and dumps

- A 16-bit length that reads `0x0400` when the frame is 4 bytes long, or `0x3412` where `0x1234` was expected, is the textbook byte swap.
- On AArch64 BE, `ldr` of a descriptor written by a little-endian DMA engine needs `le32_to_cpu()`. Missing it shows up as `OWN` never set: bit 31 is now in the lowest byte.
- In Trace32, `Data.dump addr /Long /LE` vs `/BE` lets you view memory in either byte order without recompiling.

### 3.4 False sharing and cache-line bugs

- **Linux, Cortex-A/x86:** `perf c2c record` / `perf c2c report` identifies cache lines with cross-core HITM (hit-modified) traffic, and the offsets within them. That is the definitive false-sharing tool. On Arm servers, `perf c2c` uses SPE (Statistical Profiling Extension) where available (⚠ verify for your kernel and core).
- **PMU events:** L1D refills and bus/snoop traffic counters (event names vary by core; on Arm see `L1D_CACHE_REFILL` and `BUS_ACCESS`). A padded vs unpadded A/B test with `perf stat` is the proof.
- **Cortex-M7 (single core with DMA):** the symptom is data corruption, not slowness. Descriptors revert to old contents, or received frames have a stale 32-byte chunk at the start or end. Check every DMA buffer and descriptor address mod 32 and size mod 32 in the map file. Then set a DWT data watchpoint (`DWT_COMP0`/`DWT_FUNCTION0`, or `Break.Set addr /Write` in Trace32, or `watch -l` in GDB) on the neighbor variable to catch the CPU write that shares the line.

---

## 4. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "Why do kernel and firmware teams ban C bit-fields for hardware registers?"

- **L5:** "Bit-field layout is implementation-defined, so it's not portable."
- **Why L5 fails on real hardware:** True but incomplete. It doesn't name the failures that ship:
  1. Allocation order flips with endianness: the verified `0xBEEF03CB` vs `0xD3C0BEEF`.
  2. Every bit-field write is a **read-modify-write** (verified `ldr/orr/str`). That clears sibling W1C flags and consumes read-to-clear flags.
  3. Access width follows the container type, so a `uint8_t` container produces `strb` byte-lane writes to word-only peripherals (verified), which are ignored or bus-faulted.
  4. Adjacent bit-fields are one memory location (§3.14), so ISR and thread writers race.
  5. Multi-field updates become multiple bus transactions, exposing half-configured hardware.
- **L7 defense:** Masks and shifts with compile-time-checked `GENMASK`/`FIELD_PREP` (the blueprint), `_Static_assert` on every register offset, a single composed store per configuration, explicit W1C writes, and hardware set/clear aliases (BSRR, SET/CLR registers, RP2040 atomic aliases, bit-banding on M3/M4) where RMW concurrency exists. Cite Linux `<linux/bitfield.h>` and the CMSIS `_VAL2FLD`/`_FLD2VAL` convention as prior art.

### Q2 "Reorder this struct to minimize its size. Then tell me why that's sometimes the wrong goal."

- **L5:** Sort by decreasing alignment: 24 → 16 bytes (verified).
- **Why L5 fails:** Size is rarely the binding constraint:
  - A struct shared with hardware or another compiler has a **fixed** layout, so reordering is an ABI break.
  - In a hot path, fields used together should share a cache line, and fields written by different cores must **not** (false sharing).
  - A reorder can move a hot field across a line boundary and add a miss.
  - For DMA, the struct's lines are a correctness contract (§1.8.3).
- **L7 defense:**
  1. Order by contract.
  2. Then by locality and writer.
  3. Then by size.
  4. Lock the result with `_Static_assert(offsetof(...))` and `sizeof` checks.
  5. Verify with `pahole` in CI.
  6. Measure with `perf c2c` and `perf stat`, not intuition.

### Q3 🔥 "An AArch64 Linux host and a Cortex-M4 coprocessor exchange a struct through shared SRAM. A tool on a 32-bit x86 PC also parses it. What can differ?"

- **L5:** "Endianness and padding."
- **Why L5 fails:** The verified ABI table names more:
  - `long` is 8 vs 4 bytes;
  - `uint64_t` after a `uint32_t` lands at offset **4** on i386 and **8** on ARM;
  - `char` signedness differs;
  - `enum` size can be 1 (GCC `arm-none-eabi` short enums, ⚠ verify) vs 4 (Clang, verified);
  - `long double` is 8/12/16 bytes;
  - `bool` representation is fine at 1 byte, but its valid values are only 0 and 1, so a raw byte of 2 is a trap value in practice;
  - padding contents are unspecified.

  On top of layout: **coherency**. The M4 has no cache, but the A-core's write-back cache does, so shared-SRAM writes need cache maintenance or a non-cacheable mapping (Folder 03).
- **L7 defense:** One header used by all three builds:
  - only fixed-width integer types;
  - explicit `uint8_t reserved[n]` padding fields, so there is no implicit padding (check with `-Wpadded`);
  - `_Static_assert` on every offset and the total size;
  - no `enum`/`bool`/`long`/`long double`/pointers in the struct;
  - an explicit byte order with accessor functions;
  - a version field plus a size field first;
  - the shared region mapped Normal Non-cacheable on the A-core, or cleaned/invalidated at ownership handoff;
  - a CI job that compiles the header for all three targets and diffs the `offsetof` tables.

### Q4 ⚡ "Your `ioctl` returns a struct to user space. A security researcher reports a kernel address leak. The struct has no pointer fields."

- **L5:** "Initialize all fields before copying."
- **Why L5 fails:** All fields *are* initialized. The leak is in the **padding**, which holds old stack bytes: return addresses, kernel pointers. §6.2.6.1p6 makes padding unspecified even after member stores. Clang 21 happened to zero padding in the verified designated-initializer case, but that is compiler- and version-specific. GCC 15's `{0}`-for-unions change shows the behavior moves under you.
- **L7 defense:**
  1. `memset(&s, 0, sizeof s)` before the member stores (kernel practice), or `= {}` in C23.
  2. Better: avoid implicit padding in UAPI structs entirely, with explicit `__u8 pad[3]` fields that must be zero, which the kernel validates on input.
  3. `pahole` in CI to prove there are no holes.
  4. Build with `-ftrivial-auto-var-init=zero`.
  5. Cite CERT DCL39-C.

### Q5 🔥 "You padded the producer and consumer indices to 64 bytes. Is that right on every core you ship?"

- **L5:** "Yes, cache lines are 64 bytes."
- **Why L5 fails:**
  - Apple M-series lines are **128 B**.
  - x86's adjacent-line prefetcher couples 128-byte pairs, so 64-byte padding still shows cross-core interference (that's why many libraries use 128).
  - Cortex-M7 is 32 B: 64 is enough there, but wasteful for DMA rounding.
  - On AArch64 the **ERG** (Exclusives Reservation Granule, `CTR_EL0[23:20]`) can be larger than a line, so two `LDXR`/`STXR` lock words in one granule can make each other's store-exclusives fail even on different lines.
  - DMA alignment is governed by **CWG**, not DminLine.
- **L7 defense:** Make the padding a build-time constant per target (`DCACHE_LINE` and `DESTRUCTIVE_INTERFERENCE`), and check it at boot against `CTR_EL0` (or `CCSIDR` on M7), asserting `CWG ≤ configured`. Use 128 for cross-core hot data on x86 and Apple, separate ERG-sized slots for LL/SC lock words, and `alignas` on the type with a `_Static_assert` on `sizeof` (verified 128-byte `spsc_idx_padded`).

### Q6 ⚡🧊 "Your Cortex-M7 Ethernet driver drops about one frame in 10⁵ and occasionally replays an old frame. Descriptors are 16 bytes, in cacheable SRAM, and you clean and invalidate them correctly."

- **L5:** "Add a `DSB` after the cache maintenance." Or: "Make the descriptors `volatile`."
- **Why L5 fails:** The maintenance is "correct" per descriptor, but two 16-byte descriptors share each **32-byte line**. Cleaning descriptor *i* writes back the whole line, overwriting descriptor *i+1*'s fresh DMA write-back (`OWN` cleared, `status` updated) with the CPU's stale copy. The engine then sees `OWN = 1` again and re-uses a buffer: a replay. Or the CPU never sees the completion: a drop. `volatile` affects only the compiler, not the cache. `DSB` orders completion; it does not prevent the line overlap.
- **L7 defense:**
  - One descriptor per line (`alignas(DCACHE_LINE)` wrapper, verified 32/64/128 geometry); or
  - the ring placed in an MPU region marked Normal Non-cacheable (or Device), so no maintenance is needed; or
  - descriptor writes by the CPU only while it owns the *whole line*.

  Plus: `dma_range_is_line_exact()` asserted in every clean/invalidate call (the verified guard rejects a status-word-only invalidate), and a soak test with a DWT watchpoint on descriptor *i+1* during descriptor *i*'s clean.

### Q7 "`__attribute__((packed))` made our Cortex-A driver crash but the same code works on Cortex-M4. Why?"

- **L5:** "Packed structs are slow on ARM."
- **Why L5 fails:** Speed isn't the issue. On AArch64, a packed member read compiles to `LDUR` at an odd offset (verified). On **Normal** memory that's fine, but the driver's struct overlays **Device** memory (an MMIO window or a coherent DMA pool mapped Device-nGnRE), where *any* unaligned access raises an Alignment fault (ESR EC `0x25`, DFSC `0x21`). The Cortex-M4 tolerates unaligned single `LDR` even in the peripheral region on that implementation, and that is luck, not architecture. Then `&p->val` leaked a misaligned `uint32_t *` into code that used an atomic on it (exclusives require alignment on every ARM core).
- **L7 defense:** Never `packed` an MMIO or DMA structure. Register maps are naturally aligned, so assert offsets instead. Wire formats get byte-wise serializers. Turn `-Waddress-of-packed-member` into an error (verified diagnostic). On Linux, map DMA memory through the DMA API, and access MMIO only through `readl`/`writel` (aligned, correctly sized, ordered).

### Q8 "How do you write endian-neutral code, and what does it cost?"

- **L5:** "Use `htonl`/`ntohl`." Or: "Use a union to swap bytes."
- **Why L5 fails:**
  - `htonl` isn't available on bare metal, converts only to big-endian, and invites casts of `uint8_t*` to `uint32_t*` (File 01).
  - Union byte-swapping assumes a host byte order, and is UB in C++.
  - Neither expresses *the device's* byte order, which is often little-endian (PCIe, most SoC IP).
- **L7 defense:** Byte-oriented accessors (`load_be32`/`load_le32`/`store_be32`), which compile to the ideal instruction on every ISA (verified): `ldr+rev` on M7 and A64, `movbe` on x86 with `-mmovbe`, byte loads on M0+ and generic RV64, and a plain `ldr` for the native order. In Linux, use `__le32`/`__be32` with `sparse` checking and `readl`/`ioread32be`. Treat byte order as part of the *type* of a field, not an afterthought.

### Q9 🧊 "What's wrong with `kmalloc(sizeof(*msg) + n * sizeof(msg->data[0]))`?"

- **L5:** "Nothing; that's the standard flexible-array idiom."
- **Why L5 fails:**
  - `sizeof(*msg)` includes tail padding that overlaps the start of `data[]` (verified `sizeof = 8`, `offsetof(data) = 5`), so the allocation is slightly *larger* than needed. That is harmless.
  - The real defect is **`n * sizeof` overflow**: an attacker-controlled `n` wraps the multiplication, the allocation is tiny, and the following copy is a heap overflow.
  - Without `counted_by`, the compiler and sanitizers can't bounds-check `data[]`.
- **L7 defense:**
  1. `kmalloc(struct_size(msg, data, n))`, which saturates to `SIZE_MAX` on overflow so the allocation fails.
  2. `__counted_by(len)` on the flexible array, so `-fsanitize=bounds` and `FORTIFY_SOURCE` check indices.
  3. `-fstrict-flex-arrays=3` to kill legacy `[1]` arrays.
  4. In MISRA code, no FAMs at all (Rule 18.7): fixed-capacity arrays sized for the worst case.

---

## 5. Invariants Checklist

- [ ] Every hardware register map: naturally aligned `volatile uint32_t` members, `const volatile` for read-only, `RESERVED` arrays for gaps, **`_Static_assert(offsetof)` for every register**, never `packed`, never bit-fields.
- [ ] Every register field: a contiguous mask (`REGFIELD_ASSERT`), `FIELD_PREP`/`FIELD_GET`, range-checked with `FIELD_FITS` before composing.
- [ ] W1C registers written with exactly the bits to clear; `rc_w0` registers written with `~bit`; no RMW on either.
- [ ] Multi-field configuration composed in a local and written once; read back where posted writes matter.
- [ ] Shared/cross-compiler structs: fixed-width types only, explicit padding fields, no `enum`/`bool`/`long`/`long double`/pointers, offsets asserted, byte order explicit.
- [ ] Trust-boundary structs: `memset` or C23 `= {}`; no implicit padding; never `memcmp` or hash raw structs.
- [ ] Endianness handled by byte-wise accessors; no unions or casts for swapping; `__le32`/`__be32` annotations in Linux.
- [ ] Cache-line size, CWG and ERG are build-time constants checked at boot against `CTR_EL0`/`CCSIDR`.
- [ ] Cross-core hot fields are on separate `alignas(DESTRUCTIVE_INTERFERENCE)` lines; `sizeof` asserted.
- [ ] DMA buffers and descriptors start and end on line (CWG) boundaries; sizes rounded up; no CPU variables share their lines; `dma_range_is_line_exact` asserted.
- [ ] Flexible arrays sized with overflow-safe helpers and annotated `counted_by`, or banned (MISRA 18.7).

## 6. MISRA C:2012 / CERT C Cross-Reference

| Topic | MISRA C:2012 | CERT C |
|---|---|---|
| Bit-field types (no plain `int`, single-bit fields unsigned) | Rules 6.1, 6.2 | INT12-C (bit-field signedness, recommendation) |
| Unions | Rule 19.2 (advisory) | (none) |
| Size-indicating typedefs | Dir 4.6 | INT00-C (recommendation) |
| Function vs function-like macro | Dir 4.9 (advisory: prefer inline functions; field macros kept for constant expressions with justification) | PRE00-C |
| Integer → pointer for register bases | Rule 11.4 (advisory) | INT36-C |
| Information leakage through padding | (none) | DCL39-C |
| Comparing padding | Rule 21.16 (`memcmp` argument types) | EXP42-C |
| Flexible array members | Rule 18.7 | MEM33-C (allocate and copy FAM structs dynamically) |
| Alignment | Rule 11.3 | EXP36-C |
| Shift range in mask construction | Rule 12.2 | INT34-C |

## 7. References

1. ISO/IEC 9899:2011 / 2018 / 2024 (drafts N1570, N2176, N3220): §3.14, §6.2.6, §6.2.8, §6.7.2.1, §6.7.9 / C23 §6.7.10.
2. Arm, *Procedure Call Standard for the Arm Architecture* (AAPCS32, IHI 0042) and *for the Arm 64-bit Architecture* (AAPCS64, IHI 0055): data types, bit-fields, volatile bit-fields.
3. *System V Application Binary Interface*: i386 supplement and AMD64 psABI; Apple, *Writing ARM64 code for Apple platforms*; RISC-V psABI.
4. Arm, *ARMv7-M Architecture Reference Manual* (DDI 0403E): AIRCR, bit-banding (§B3.5 / optional on M3/M4); *Cortex-M7 Technical Reference Manual* (L1 cache, CCSIDR); *Arm ARM for A-profile* (DDI 0487): CTR_EL0, SCTLR_ELx.EE/E0E, memory types and alignment.
5. U. Drepper, *What Every Programmer Should Know About Memory*, 2007, §3, §6.4.
6. Linux: `include/linux/bitfield.h`, `include/linux/overflow.h` (`struct_size`), `Documentation/core-api/unaligned-memory-access.rst`, `Documentation/driver-api/device-io.rst` (`readl`/`writel` semantics), `perf-c2c(1)`.
7. A. de Melo, *pahole* / dwarves documentation.
8. GCC 15 release notes (`{0}` union initialization; `-fzero-init-padding-bits`; `counted_by`) and Clang 18 release notes (`counted_by`) (⚠ verify version details).
9. CMSIS-Core documentation (`_VAL2FLD`/`_FLD2VAL`, SVD conventions); Raspberry Pi RP2040 datasheet §2.1.2 (atomic register access aliases).
