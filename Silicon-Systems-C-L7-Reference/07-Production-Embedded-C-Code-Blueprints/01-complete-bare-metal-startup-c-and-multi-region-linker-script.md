# 01 · Complete Bare-Metal Startup (C) and a Multi-Region Linker Script (ITCM / DTCM / AXI / DMA-NC / Backup `.noinit`)

> **Folder:** `07-Production-Embedded-C-Code-Blueprints/` · **File 1 of 4**
> **Anchors:**
> - Arm *ARMv7-M Architecture Reference Manual* (DDI 0403E): B1.5 exception model and vector table, B3.2 System Control Block (VTOR, CCR, CPACR), B3.5 PMSAv7 MPU, A3.5 memory types.
> - Arm *Cortex-M7 Processor Technical Reference Manual* (DDI 0489): L1 caches, TCM interfaces, cache maintenance operations (ICIALLU, DCISW).
> - Arm *Cortex-M Programming Guide to Memory Barrier Instructions* (AN321): DSB/ISB after VTOR, MPU and CCR writes.
> - CMSIS-Core `core_cm7.h` (`SCB_EnableICache`, `SCB_EnableDCache`), the reference sequence this crt0 matches.
> - STM32H7-class memory map (RM0433-style: ITCM 64 KB, DTCM 128 KB, AXI SRAM 512 KB, D2 SRAM, 4 KB backup SRAM). ⚠ verify sizes, bus masters and backup-domain enables for your exact part.
> - LLD linker-script and range-extension-thunk behavior (LLD 21.1).
>
> **Verification:**
> - All five C files and the linker script below compile and link warning-free with Clang 21.1.0 / LLD 21.1 (`-Wall -Wextra -Wpedantic -Werror -Wconversion -Wsign-conversion -Wcast-align -Wshadow -Wstrict-prototypes -Wmissing-prototypes`, `thumbv7em-none-eabihf -mcpu=cortex-m7`).
> - The linked image was **cold-booted in Unicorn 2.1.4 (Cortex-M7 model)**: only bytes whose load address is in FLASH survive "power-off", every RAM is pre-filled with `0xA5`, and every write to VTOR, CCR, CPACR, the MPU and the cache-maintenance registers is counted.
> - The buggy linker script was linked from the same objects and booted both ways (debugger download and power cycle).
> - All outputs, section tables and listings are inserted verbatim.

---

## 0. The thesis

A Cortex-M7 startup is a **three-party contract**:

1. The **linker script** says where every byte *lives* (VMA) and where it is *stored* until reset (LMA).
2. **crt0** (`Reset_Handler`) makes the C abstract machine's preconditions true: `.data` holds its initializers, `.bss` is zero, constructors have run, and the FPU exists before the first FP instruction.
3. The **MPU and caches** give each region its *memory type*: cacheable, non-cacheable, device, executable or not.

If any two parties disagree, the system usually still boots on the bench. It fails after a power cycle, under DMA load, or on the first NULL dereference in the field. This file builds one coherent contract for five RAM classes. It then proves each clause on an emulated cold boot, and shows the one-line linker mistake that passes every debugger session and dies on the first power cycle.

---

## 1. First-Principles Mechanics

### 1.1 Five RAM classes, five different physics

| Region | Address (H7-class) | Size | Path from the core | Latency | Cacheable? | Typical DMA reach ⚠ verify | Survives reset? |
|---|---|---|---|---|---|---|---|
| **ITCM** | `0x0000_0000` | 64 KB | Dedicated TCM port (64-bit) | 0 wait states, deterministic | No (TCMs are never cached) | Usually only a system DMA through the AHBS slave port | Contents survive a warm reset, lost at power-off |
| **DTCM** | `0x2000_0000` | 128 KB | Dual 32-bit D-TCM ports | 0 wait states | No | Often *not* reachable by general-purpose DMA | Survive warm reset, lost at power-off |
| **AXI SRAM** | `0x2400_0000` | 512 KB | 64-bit AXIM through the bus matrix | Several cycles on a miss | Yes (L1 D-cache, WB-WA) | Yes | Survive warm reset |
| **D2 SRAM** | `0x3000_0000` | 128 KB+ | AXIM → bus matrix → AHB | Slower | **Made Normal-NC by the MPU**: the DMA region | Yes (peripheral DMA lives here) | Survive warm reset |
| **Backup SRAM** | `0x3880_0000` | 4 KB | Backup domain (separate power) | Slow | Mapped NC | Rarely | **Survives reset and, with VBAT, power loss** |

Two consequences drive the whole design:

- **Placement is a performance and correctness decision.**
  - Hot ISRs go in ITCM: no flash wait states, no I-cache misses, and therefore deterministic latency (Folder 04 File 01).
  - ISR state and the main stack go in DTCM: zero wait states, never cached, so they need no maintenance.
  - DMA buffers and descriptors go in a region the MPU marks **Normal Non-cacheable**, which eliminates the clean/invalidate hazards of Folder 03 File 03 by construction.
  - Crash records go in battery-backed SRAM and must **never** be zeroed by crt0.
- **The vendor default map is wrong for DMA.** Under the ARMv7-M default memory map, `0x2000_0000–0x3FFF_FFFF` is Normal **write-back write-allocate**. So D2 SRAM is cacheable until the MPU says otherwise, and the order "MPU, then caches" is not a style choice (§1.3).

### 1.2 VMA vs LMA, and why crt0 reads tables

Every output section has two addresses:

- The **VMA** (virtual/run address) is where code expects to find it.
- The **LMA** (load address) is where the flash programmer stores it.

For anything that runs or lives in RAM, the LMA must be in FLASH and crt0 must copy LMA → VMA. The syntax is `> RAM AT > FLASH`.

With five regions, the classic crt0 symbols (`_sidata`, `_sdata`, `_edata`, `_sbss`, `_ebss`) don't scale. Every new region means a new symbol pair and a crt0 edit. Forgetting one is the bug in §2.1. The production linker script instead **emits the work list**:

```
.copy_table : { LONG(LOADADDR(x)) LONG(ADDR(x)) LONG(SIZEOF(x)/4) ... }   /* {load, run, words} */
.zero_table : { LONG(ADDR(x)) LONG(SIZEOF(x)/4) ... }                     /* {run, words}       */
```

crt0 walks both tables and never changes again. Adding a region is a two-line linker-script edit.

The **NOLOAD** sections (`.dtcm_bss`, `.msp_stack`, `.dma_nc`, `.bkp_noinit`) occupy address space but no file bytes. Of those, only `.dtcm_bss` and `.bss` appear in the zero table:

- `.dma_nc` is owned by drivers, which initialize their own descriptors.
- `.bkp_noinit` must survive reset.
- `.msp_stack` is the stack crt0 is currently running on.

### 1.3 Reset_Handler order, and the hardware reason for every step

| # | Step | Why it must be here |
|---|---|---|
| 1 | Set `CPACR[23:20] = 0xF`, `DSB; ISB` | With `-mfloat-abi=hard`, the compiler may emit VFP instructions anywhere, including in crt0 or an inlined `memcpy`. Before CP10/CP11 are enabled, any FP instruction raises a **NOCP UsageFault**, which escalates to HardFault because UsageFault is disabled at reset. The ISB makes the enable take effect for the next instruction. |
| 2 | `VTOR = g_vectors`, `DSB; ISB` | Point exceptions at our table *before* anything can fault. The table must be aligned to its size rounded up to a power of two: 1 KB for 129–256 entries (the linker script asserts it). |
| 3 | Copy table, then zero table, through `volatile` pointers | Volatile accesses are never converted by LoopIdiomRecognize into `__aeabi_memcpy4`/`__aeabi_memclr4` calls (contrast the listing in §2.1). A libcall in crt0 is fatal if `memcpy` itself was placed in ITCM for speed, because it would be called before it is copied. |
| 4 | `DSB; ISB` after the copies | ITCM code was written through the **data** side. The DSB completes those writes; the ISB discards anything already prefetched, so the first fetch from ITCM sees the new bytes. |
| 5 | MPU (`board_mpu_init`) | Must precede the caches. Otherwise lines from D2 (default-map cacheable) can be allocated, and changing a region's attributes while lines are present requires explicit cache maintenance (ARMv7-M), which nobody remembers to do. |
| 6 | `ICIALLU`, `DSB; ISB`, `CCR.IC = 1`, `DSB; ISB` | Cache RAMs power up with **random contents**, possibly including "valid" tags. They must be invalidated before the cache is switched on. |
| 7 | Select L1-D (`CSSELR = 0`), read `CCSIDR`, invalidate every set/way with `DCISW`, `DSB`, `CCR.DC = 1`, `DSB; ISB` | Same reason. Set/way invalidation is only safe **with the cache off** (it discards dirty data). This is the CMSIS `SCB_EnableDCache` sequence. |
| 8 | Constructors (`.init_array`), `main`, `wfi` loop | C++ or `__attribute__((constructor))` objects. If `main` returns, sleep rather than fall through into garbage. |

The DCISW encoding for the Cortex-M7 L1-D:

- **Set** is in bits `[13:5]`, because `log2(32-byte line) = 5`.
- **Way** is in bits `[31:30]` (4 ways).

With `CCSIDR = 0x000FE019` (128 sets, 4 ways, 32-byte lines: a 16 KB cache), the loop performs exactly **512** writes, and the last one is `(127 << 5) | (3 << 30) = 0xC0000FE0`. The emulator trace in §2.2 shows exactly that.

### 1.4 Calling from flash into ITCM: the linker writes a thunk

A Thumb-2 `BL` reaches ±16 MB. `main` at `0x0800_0370` calling `TIM2_IRQHandler` at `0x0000_0020` is ~128 MB away. LLD silently inserts a **range-extension thunk** (`movw/movt ip` + `bx ip`). GNU ld also inserts long-branch stubs automatically, named `__<symbol>_veneer` in the map ⚠ verify for your binutils version. Alternatively, the call site can use `__attribute__((long_call))`.

Two rules follow:

- **`ITCM_FN` must be `noinline`.** An inlined copy would run from flash, and the ITCM copy would be dead.
- **ITCM code that calls flash functions pays the thunk too.** Keep ITCM ISRs leaf-like, or place their callees in ITCM as well.

### 1.5 The NULL guard

With ITCM at address 0, `*(uint32_t *)NULL` reads the first word of your hottest ISR, silently and with no fault. The production map:

- starts `.itcm_text` at `ORIGIN(ITCM) + 32`;
- marks `0x0–0x1F` **no-access** with MPU region 7, which is the highest-numbered region and therefore wins on overlap (PMSAv7).

A NULL **data** dereference at offset < 32 now raises a MemManage fault with `MMFAR = address`. A NULL **function** call (`blx` to an even address) faults with INVSTATE on M-profile anyway.

The verified runs in §2 show the difference: `TIM2_IRQHandler` sits at `0x21` in the production image and at `0x01` in the buggy one.

### 1.6 Backup SRAM `.noinit`

- `.bkp_noinit` is `NOLOAD` and absent from the zero table, so crt0 never touches it.
- Its *contents* are untrusted after a power-on: they are random. A record is valid only if a magic word and a CRC check out. File 04 builds exactly that.
- On real parts the backup domain must also be clocked and write-unprotected (on STM32-class parts: `PWR_CR1.DBP` and the backup-RAM clock enable) ⚠ verify for your part. The emulator models it as plain RAM.

---

## 2. Production Blueprints

### 2.1 The Subtle Buggy Way

**Defect A: the vendor-template crt0 with local edits.** It compiles warning-free. Every defect in it is architectural:

```c
/* startup_bad.c - the "vendor template plus edits" crt0: boots on the bench,
 * fails in the field. Compiles warning-free; every defect is architectural. */
#include <stdint.h>

extern uint32_t _sidata[], _sdata[], _edata[], _sbss[], _ebss[];
int main(void);
void Reset_Handler(void);

#define SCB_CCR   (*(volatile uint32_t *)0xE000ED14u)
#define SCB_CPACR (*(volatile uint32_t *)0xE000ED88u)

void Reset_Handler(void)
{
    SCB_CCR = SCB_CCR | (1u << 16) | (1u << 17);   /* BUG 1: caches ON with random reset
                                                    *  contents (no ICIALLU / DCISW first)
                                                    *  and BEFORE the MPU: the default map
                                                    *  makes D2 DMA SRAM write-back cacheable */
    uint32_t *src = _sidata;
    uint32_t *dst = _sdata;
    while (dst < _edata) { *dst++ = *src++; }      /* BUG 2: one region: ITCM code and DTCM
                                                    *  data are never copied (and clang turns
                                                    *  this loop into a memcpy call)         */
    for (dst = _sbss; dst < _ebss; ) { *dst++ = 0u; }  /* BUG 3: .bss also covers .noinit */
    SCB_CPACR = SCB_CPACR | (0xFu << 20);          /* BUG 4: FPU enabled last, no DSB/ISB:
                                                    *  any FP instruction above (or in a
                                                    *  memcpy) is a NOCP UsageFault        */
    (void)main();
    for (;;) { }
}
```

**Codegen (verified — Clang 21.1.0, -O2, thumbv7em-none-eabihf, Cortex-M7):**

```asm
Reset_Handler:
	movw	r4, #60692
	movw	r1, :lower16:_edata
	movt	r4, #57344
	movw	r0, :lower16:_sdata
	movt	r1, :upper16:_edata
	movt	r0, :upper16:_sdata
	ldr	r2, [r4]
	cmp	r0, r1
	orr	r2, r2, #196608
	str	r2, [r4]
	bhs	.LBB0_2
	adds	r2, r0, #4
	cmp	r1, r2
	it	hi
	movhi	r2, r1
	subs	r1, r0, r2
	mvn	r2, #3
	bic.w	r1, r2, r1
	adds	r2, r1, #4
	movw	r1, :lower16:_sidata
	movt	r1, :upper16:_sidata
	bl	__aeabi_memcpy4
.LBB0_2:
	movw	r1, :lower16:_ebss
	movw	r0, :lower16:_sbss
	movt	r1, :upper16:_ebss
	movt	r0, :upper16:_sbss
	cmp	r0, r1
	bhs	.LBB0_4
	adds	r2, r0, #4
	cmp	r1, r2
	it	hi
	movhi	r2, r1
	subs	r1, r0, r2
	mvn	r2, #3
	bic.w	r1, r2, r1
	adds	r1, #4
	bl	__aeabi_memclr4
.LBB0_4:
	ldr	r0, [r4, #116]
	orr	r0, r0, #15728640
	str	r0, [r4, #116]
	bl	main
.LBB0_5:
	b	.LBB0_5
```

Read the listing:

- The two "simple loops" became `bl __aeabi_memcpy4` and `bl __aeabi_memclr4`.
- The CCR write (`orr r2, r2, #196608` = bits 16 and 17) has **no barrier and no invalidation** before it.
- CPACR is written last (`ldr/orr/str [r4, #116]`, i.e. `0xE000ED88`), with no DSB/ISB, immediately before `bl main`.

**Defect B: one missing `AT > FLASH`.** It was derived from the production script by a two-line edit, and LLD links it with no warning:

```diff
--- linker_h7.ld	2026-10-26 22:08:27.948033900 +0530
+++ linker_bad.ld	2026-10-26 22:19:42.587997900 +0530
@@ -41,13 +41,13 @@
   } > FLASH
 
   /* --- ITCM: first 32 bytes reserved so a NULL function pointer faults (MPU no-access) --- */
-  .itcm_text ORIGIN(ITCM) + 32 :
+  .itcm_text ORIGIN(ITCM) :
   {
     . = ALIGN(8);
     *(.itcm_text .itcm_text.*)
     *(.ramfunc .ramfunc.*)
     . = ALIGN(8);
-  } > ITCM AT > FLASH
+  } > ITCM
 
   /* --- DTCM: hot initialized data, hot zeroed data, then the MSP stack --- */
   .dtcm_data :
```

Program headers of the buggy image: the ITCM segment's **PhysAddr is `0x00000000`**, so its bytes are "stored" in ITCM itself:

```
  Type           Offset   VirtAddr   PhysAddr   FileSiz MemSiz  Flg Align
  LOAD           0x000214 0x08000000 0x08000000 0x000d0 0x000d0 R   0x4
  LOAD           0x0002e8 0x080000d0 0x080000d0 0x00678 0x00678 R E 0x8
  LOAD           0x000960 0x00000000 0x00000000 0x00010 0x00010 R E 0x8
```

Booted both ways (verified, Unicorn Cortex-M7, same objects as the production build):

```
== bad.elf, debugger download (every PT_LOAD written at its LMA) ==
run 1: reset SP=0x20002020 PC=0x080000D9 -> stopped at 0x08000368 (h7_done)
  g_result@0x2400001C: 0x00000003 0xA11A11A1 0x00000000 0x00000001 0x00000001 0x30000200 0x38800000 0x20000008
== bad.elf, power cycle (only FLASH contents survive) ==
  cold boot: segment for 0x00000000 has LMA 0x00000000 outside FLASH -> lost at power-off
UNMAPPED access type=21 addr=0x00010000 size=2
run 1: CPU stopped: Invalid memory fetch (UC_ERR_FETCH_UNMAPPED) at PC=0x00010000 LR=0x080003A5
== the bytes the CPU fetched at TIM2_IRQHandler (ITCM still holds power-on garbage 0xA5) ==
  00000000:  adr      r5, #0x294
  00000002:  adr      r5, #0x294
  00000004:  adr      r5, #0x294
```

What the runs show:

- **Under the debugger it works.** The debugger writes every PT_LOAD segment at its PhysAddr, including straight into ITCM, so `TIM2_IRQHandler` runs and `g_result[3] = 1`. Note `g_result[4] = 0x00000001`: the handler sits at address 0, so a NULL data pointer reads live ISR code.
- **After a power cycle** the ITCM segment never reached flash. The copy table copies ITCM onto itself (LMA == VMA). The first call executes power-on garbage: `0xA5A5` decodes as `adr r5, #0x294`, a harmless-looking sled of 32,768 instructions across 64 KB that runs off the end of ITCM at `0x00010000`. The LR (`0x080003A5`) points just after the `bl` in `main`.
- On real silicon the garbage is random rather than a tidy sled, so the symptom is a HardFault in an ISR that "can't fault", only on boards that were power-cycled.

### 2.2 The Silicon-Hardened Production Way

**The linker script** (five RAM classes, copy and zero tables, a NULL guard, and asserts that fail the link instead of the board):

```ld
/* linker_h7.ld - Cortex-M7 (STM32H7-class map), five RAM classes:
 *   ITCM     0x0000_0000  64 KB  zero-wait code: hot ISRs, flash-programming code
 *   DTCM     0x2000_0000 128 KB  zero-wait data: MSP stack, ISR state, hot data
 *   AXI_SRAM 0x2400_0000 512 KB  cached: general .data / .bss
 *   SRAM_D2  0x3000_0000 128 KB  MPU Normal-NC: DMA buffers and descriptors
 *   BKPSRAM  0x3880_0000   4 KB  battery-backed: crash records (.noinit)
 * Copy/zero work is described by linker-generated tables, so crt0 never
 * changes when a region is added. */
ENTRY(Reset_Handler)

MEMORY
{
  FLASH    (rx)  : ORIGIN = 0x08000000, LENGTH = 2M
  ITCM     (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
  DTCM     (rw)  : ORIGIN = 0x20000000, LENGTH = 128K
  AXI_SRAM (rw)  : ORIGIN = 0x24000000, LENGTH = 512K
  SRAM_D2  (rw)  : ORIGIN = 0x30000000, LENGTH = 128K
  BKPSRAM  (rw)  : ORIGIN = 0x38800000, LENGTH = 4K
}

__msp_stack_size = 0x2000;

SECTIONS
{
  .isr_vector ORIGIN(FLASH) : { KEEP(*(.isr_vector)) } > FLASH

  .text :
  {
    *(.text .text.*)
    *(.rodata .rodata.*)
    . = ALIGN(4);
  } > FLASH

  .init_array :
  {
    . = ALIGN(4);
    __init_array_start = .;
    KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)))
    KEEP(*(.init_array))
    __init_array_end = .;
  } > FLASH

  /* --- ITCM: first 32 bytes reserved so a NULL function pointer faults (MPU no-access) --- */
  .itcm_text ORIGIN(ITCM) + 32 :
  {
    . = ALIGN(8);
    *(.itcm_text .itcm_text.*)
    *(.ramfunc .ramfunc.*)
    . = ALIGN(8);
  } > ITCM AT > FLASH

  /* --- DTCM: hot initialized data, hot zeroed data, then the MSP stack --- */
  .dtcm_data :
  {
    . = ALIGN(8);
    *(.dtcm_data .dtcm_data.*)
    . = ALIGN(8);
  } > DTCM AT > FLASH

  .dtcm_bss (NOLOAD) :
  {
    . = ALIGN(8);
    *(.dtcm_bss .dtcm_bss.*)
    . = ALIGN(8);
  } > DTCM

  .msp_stack (NOLOAD) :
  {
    . = ALIGN(32);
    __msp_limit = .;            /* MPU guard / MSPLIM target */
    . = . + __msp_stack_size;
    . = ALIGN(8);
    __msp_top = .;
  } > DTCM

  /* --- AXI SRAM: general data --- */
  .data :
  {
    . = ALIGN(8);
    *(.data .data.*)
    . = ALIGN(8);
  } > AXI_SRAM AT > FLASH

  .bss (NOLOAD) :
  {
    . = ALIGN(8);
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(8);
  } > AXI_SRAM

  /* --- D2 SRAM: DMA (MPU maps the whole 128 KB region Normal-NC) --- */
  .dma_nc (NOLOAD) :
  {
    . = ALIGN(32);
    *(.dma_nc .dma_nc.*)
    . = ALIGN(32);
  } > SRAM_D2

  /* --- Backup SRAM: survives resets (and power loss with VBAT) --- */
  .bkp_noinit (NOLOAD) :
  {
    *(.bkp_noinit .bkp_noinit.*)
  } > BKPSRAM

  /* --- crt0 tables: {load, run, words} and {run, words} --- */
  .copy_table :
  {
    . = ALIGN(4);
    __copy_table_start = .;
    LONG(LOADADDR(.itcm_text)) LONG(ADDR(.itcm_text)) LONG(SIZEOF(.itcm_text) / 4)
    LONG(LOADADDR(.dtcm_data)) LONG(ADDR(.dtcm_data)) LONG(SIZEOF(.dtcm_data) / 4)
    LONG(LOADADDR(.data))      LONG(ADDR(.data))      LONG(SIZEOF(.data) / 4)
    __copy_table_end = .;
  } > FLASH

  .zero_table :
  {
    . = ALIGN(4);
    __zero_table_start = .;
    LONG(ADDR(.dtcm_bss)) LONG(SIZEOF(.dtcm_bss) / 4)
    LONG(ADDR(.bss))      LONG(SIZEOF(.bss) / 4)
    __zero_table_end = .;
  } > FLASH
}

ASSERT(LOADADDR(.data) >= ORIGIN(FLASH), ".data LMA must be in FLASH")
ASSERT(__msp_top <= ORIGIN(DTCM) + LENGTH(DTCM), "DTCM overflow")
ASSERT((ADDR(.isr_vector) & 0x3FF) == 0, "vector table must be 1 KB aligned (>128 vectors)")
ASSERT((SIZEOF(.dma_nc) % 32) == 0, "DMA section must end on a cache line")
```

**Section attributes and board interface:**

```c
/* board.h - memory map and section attributes for the H7-class board. */
#ifndef BOARD_H
#define BOARD_H

#include <stdint.h>

#define ITCM_FN   __attribute__((section(".itcm_text"), noinline))  /* zero-wait code    */
#define DTCM_DATA __attribute__((section(".dtcm_data")))            /* hot, initialized  */
#define DTCM_BSS  __attribute__((section(".dtcm_bss")))             /* hot, zeroed       */
#define DMA_NC    __attribute__((section(".dma_nc"), aligned(32)))  /* MPU Normal-NC     */
#define BKP_NOINIT __attribute__((section(".bkp_noinit")))          /* survives resets   */

void board_mpu_init(void);
void TIM2_IRQHandler(void);

#endif /* BOARD_H */
```

**crt0** (FPU → VTOR → tables → MPU → I-cache → D-cache → constructors → `main`):

```c
/* startup_h7.c - production crt0 for a Cortex-M7 with TCMs, caches and MPU.
 * Order: FPU -> VTOR -> copy/zero tables -> MPU -> I-cache -> D-cache ->
 * constructors -> main. Every system-register write that later code depends
 * on is followed by DSB+ISB. */
#include <stdint.h>

#include "board.h"

extern uint32_t __msp_top[];
typedef struct { const uint32_t *load; uint32_t *run; uint32_t words; } copy_entry_t;
typedef struct { uint32_t *run; uint32_t words; } zero_entry_t;
extern const copy_entry_t __copy_table_start[], __copy_table_end[];
extern const zero_entry_t __zero_table_start[], __zero_table_end[];
typedef void (*init_fn_t)(void);
extern const init_fn_t __init_array_start[], __init_array_end[];

int main(void);
void Reset_Handler(void);
void Default_Handler(void);
void NMI_Handler(void)        __attribute__((weak, alias("Default_Handler")));
void HardFault_Handler(void)  __attribute__((weak, alias("Default_Handler")));
void MemManage_Handler(void)  __attribute__((weak, alias("Default_Handler")));
void BusFault_Handler(void)   __attribute__((weak, alias("Default_Handler")));
void UsageFault_Handler(void) __attribute__((weak, alias("Default_Handler")));
void SVC_Handler(void)        __attribute__((weak, alias("Default_Handler")));
void PendSV_Handler(void)     __attribute__((weak, alias("Default_Handler")));
void SysTick_Handler(void)    __attribute__((weak, alias("Default_Handler")));
void TIM2_IRQHandler(void)    __attribute__((weak, alias("Default_Handler")));

typedef union { void (*handler)(void); const void *stack_top; } vector_entry_t;

#define D { .handler = Default_Handler }
#define IRQ_TIM2 28u
/* 16 system entries + 32 IRQs shown; extend to the part's IRQ count (150 on H7). */
__attribute__((section(".isr_vector"), used))
const vector_entry_t g_vectors[16u + 32u] = {
    { .stack_top = __msp_top }, { .handler = Reset_Handler },
    { .handler = NMI_Handler }, { .handler = HardFault_Handler },
    { .handler = MemManage_Handler }, { .handler = BusFault_Handler },
    { .handler = UsageFault_Handler }, D, D, D, D,
    { .handler = SVC_Handler }, D, D,
    { .handler = PendSV_Handler }, { .handler = SysTick_Handler },
    /* IRQ 0..31 */
    D, D, D, D, D, D, D, D, D, D, D, D, D, D, D, D,
    D, D, D, D, D, D, D, D, D, D, D, D, { .handler = TIM2_IRQHandler }, D, D, D,
};
_Static_assert(16u + IRQ_TIM2 == 44u, "TIM2 vector slot");

#define SCB_VTOR     (*(volatile uint32_t *)0xE000ED08u)
#define SCB_CCR      (*(volatile uint32_t *)0xE000ED14u)
#define SCB_CPACR    (*(volatile uint32_t *)0xE000ED88u)
#define SCB_CCSIDR   (*(const volatile uint32_t *)0xE000ED80u)
#define SCB_CSSELR   (*(volatile uint32_t *)0xE000ED84u)
#define SCB_ICIALLU  (*(volatile uint32_t *)0xE000EF50u)
#define SCB_DCISW    (*(volatile uint32_t *)0xE000EF60u)
#define CCR_DC       (1u << 16)
#define CCR_IC       (1u << 17)

static inline void dsb_isb(void) { __asm__ volatile("dsb sy\n\tisb sy" : : : "memory"); }

static void icache_enable(void)
{
    dsb_isb();
    SCB_ICIALLU = 0u;                                  /* invalidate all I-cache lines */
    dsb_isb();
    SCB_CCR = SCB_CCR | CCR_IC;
    dsb_isb();
}

static void dcache_enable(void)
{
    SCB_CSSELR = 0u;                                   /* select L1 data cache        */
    __asm__ volatile("dsb sy" : : : "memory");
    uint32_t ccsidr = SCB_CCSIDR;
    uint32_t sets = ((ccsidr >> 13) & 0x7FFFu) + 1u;
    uint32_t ways = ((ccsidr >> 3) & 0x3FFu) + 1u;
    for (uint32_t s = 0u; s < sets; s++) {             /* invalidate by set/way: only */
        for (uint32_t w = 0u; w < ways; w++) {         /* valid with the cache OFF    */
            SCB_DCISW = ((s & 0x1FFu) << 5) | ((w & 0x3u) << 30);
        }
    }
    __asm__ volatile("dsb sy" : : : "memory");
    SCB_CCR = SCB_CCR | CCR_DC;
    dsb_isb();
}

__attribute__((noreturn)) void Reset_Handler(void)
{
    SCB_CPACR |= (0xFu << 20);                         /* 1. FPU (CP10/CP11) */
    dsb_isb();
    SCB_VTOR = (uint32_t)(uintptr_t)g_vectors;         /* 2. vector table */
    dsb_isb();

    for (const copy_entry_t *c = __copy_table_start; c < __copy_table_end; c++) {   /* 3. */
        volatile uint32_t *dst = c->run;
        const volatile uint32_t *src = c->load;
        for (uint32_t i = 0u; i < c->words; i++) { dst[i] = src[i]; }
    }
    for (const zero_entry_t *z = __zero_table_start; z < __zero_table_end; z++) {
        volatile uint32_t *dst = z->run;
        for (uint32_t i = 0u; i < z->words; i++) { dst[i] = 0u; }
    }
    dsb_isb();                                         /* ITCM code visible to fetch */

    board_mpu_init();                                  /* 4. MPU before caches: the DMA
                                                        *    region is never cacheable */
    icache_enable();                                   /* 5. */
    dcache_enable();                                   /* 6. */

    for (const init_fn_t *f = __init_array_start; f < __init_array_end; f++) { (*f)(); }
    (void)main();
    for (;;) { __asm__ volatile("wfi" : : : "memory"); }
}

void Default_Handler(void)
{
    for (;;) { }
}
```

**The MPU map**, encoded by the verified PMSAv7 encoder `mpu.h`/`mpu.c` from Folder 02 File 03, which is not repeated here:

```c
/* board_mpu.c - the board's MPU map, built with the verified PMSAv7 encoder
 * (Folder 02, File 03). Higher region numbers win on overlap (PMSAv7). */
#include "board.h"
#include "mpu.h"

#define MPU_BASE ((mpu_regs_t *)0xE000ED90u)

static void dsb_isb(void) { __asm__ volatile("dsb sy\n\tisb sy" : : : "memory"); }

static const mpu_region_t k_map[] = {
    { 0x08000000u, 2u << 20,     MEM_NORMAL_WB_WA, AP_PRIV_RO, true,  false }, /* 0 flash: code    */
    { 0x00000000u, 64u << 10,    MEM_NORMAL_WB_WA, AP_PRIV_RO, true,  false }, /* 1 ITCM: code RO  */
    { 0x20000000u, 128u << 10,   MEM_NORMAL_WB_WA, AP_PRIV_RW, false, false }, /* 2 DTCM           */
    { 0x24000000u, 512u << 10,   MEM_NORMAL_WB_WA, AP_PRIV_RW, false, false }, /* 3 AXI SRAM       */
    { 0x30000000u, 128u << 10,   MEM_NORMAL_NC,    AP_PRIV_RW, false, true  }, /* 4 D2: DMA, NC    */
    { 0x38800000u, 4u << 10,     MEM_NORMAL_NC,    AP_PRIV_RW, false, false }, /* 5 backup SRAM    */
    { 0x40000000u, 512u << 20,   MEM_DEVICE,       AP_PRIV_RW, false, true  }, /* 6 peripherals    */
    { 0x00000000u, 32u,          MEM_NORMAL_WB_WA, AP_NONE,    false, false }, /* 7 NULL guard     */
};

void board_mpu_init(void)
{
    (void)mpu_v7_program(MPU_BASE, k_map, sizeof k_map / sizeof k_map[0], dsb_isb);
}
```

**A test `main`** that places one object in every region and reports what crt0 did:

```c
/* main_h7.c - places one object in every region and reports what crt0 did. */
#include <stdint.h>

#include "board.h"

DTCM_DATA uint32_t g_dtcm_init[2] = { 0xD7C30001u, 0xD7C30002u };
DTCM_BSS  uint32_t g_dtcm_zero[4];
uint32_t           g_axi_init = 0xA11A11A1u;
uint32_t           g_axi_zero[4];
DMA_NC    uint8_t  g_dma_rx[2][512];                 /* ping-pong buffers, NC */
BKP_NOINIT uint32_t g_crash_magic;
volatile uint32_t  g_result[8];
static volatile uint32_t g_tim2_hits;

ITCM_FN void TIM2_IRQHandler(void)                     /* hot ISR runs from ITCM */
{
    g_tim2_hits = g_tim2_hits + 1u;
}

__attribute__((noinline)) void h7_done(void);
__attribute__((noinline)) void h7_done(void) { for (;;) { __asm__ volatile("" ::: "memory"); } }

int main(void)
{
    uint32_t z = 0u;
    for (unsigned i = 0u; i < 4u; i++) { z |= g_dtcm_zero[i] | g_axi_zero[i]; }
    TIM2_IRQHandler();                                 /* call through the thunk */
    g_result[0] = g_dtcm_init[0] ^ g_dtcm_init[1];     /* 3 if DTCM copy worked  */
    g_result[1] = g_axi_init;
    g_result[2] = z;                                   /* 0 if both zero tables ran */
    g_result[3] = g_tim2_hits;
    g_result[4] = (uint32_t)(uintptr_t)&TIM2_IRQHandler;
    g_result[5] = (uint32_t)(uintptr_t)&g_dma_rx[1][0];
    g_result[6] = (uint32_t)(uintptr_t)&g_crash_magic;
    g_result[7] = (uint32_t)(uintptr_t)&g_dtcm_zero[0];
    h7_done();
    return 0;
}
```

**Build** (exact commands used; `mpu.c`/`mpu.h` from Folder 02 File 03):

```bash
CF="-target thumbv7em-none-eabihf -mcpu=cortex-m7 -mfloat-abi=hard -O2 -g0 \
    -ffunction-sections -fdata-sections -fno-unwind-tables -fno-asynchronous-unwind-tables"
for f in startup_h7 board_mpu main_h7 mpu; do zig clang $CF -std=c11 -c $f.c -o $f.o; done
zig ld.lld -T linker_h7.ld --gc-sections -z max-page-size=4 -z norelro -Map h7.map \
    -o h7.elf startup_h7.o board_mpu.o main_h7.o mpu.o
```

**Sections and program headers (verified, LLD 21.1):**

```
  [Nr] Name              Type            Addr     Off    Size   ES Flg Lk Inf Al
  [ 1] .isr_vector       PROGBITS        08000000 000214 0000c0 00   A  0   0  4
  [ 2] .ARM.exidx        ARM_EXIDX       080000c0 0002d4 000010 00  AL  5   0  4
  [ 3] .text             PROGBITS        080000d0 0002e8 000678 00 AXM  0   0  8
  [ 4] .init_array       PROGBITS        08000748 000960 000000 00   A  0   0  1
  [ 5] .itcm_text        PROGBITS        00000020 000960 000010 00  AX  0   0  8
  [ 6] .dtcm_data        PROGBITS        20000000 000970 000008 00  WA  0   0  4
  [ 7] .dtcm_bss         NOBITS          20000008 000978 000010 00  WA  0   0  4
  [ 8] .msp_stack        NOBITS          20000018 000978 002008 00  WA  0   0  1
  [ 9] .data             PROGBITS        24000000 000978 000008 00  WA  0   0  4
  [10] .bss              NOBITS          24000008 000980 000038 00  WA  0   0  4
  [11] .dma_nc           NOBITS          30000000 000980 000400 00  WA  0   0 32
  [12] .bkp_noinit       NOBITS          38800000 000980 000004 00  WA  0   0  4
  [13] .copy_table       PROGBITS        08000768 000980 000024 00  WA  0   0  1
  [14] .zero_table       PROGBITS        0800078c 0009a4 000010 00  WA  0   0  1
  Type           Offset   VirtAddr   PhysAddr   FileSiz MemSiz  Flg Align
  LOAD           0x000214 0x08000000 0x08000000 0x000d0 0x000d0 R   0x4
  LOAD           0x0002e8 0x080000d0 0x080000d0 0x00678 0x00678 R E 0x8
  LOAD           0x000960 0x00000020 0x08000748 0x00010 0x00010 R E 0x8
  LOAD           0x000970 0x20000000 0x08000758 0x00008 0x00008 RW  0x4
  LOAD           0x000978 0x20000008 0x20000008 0x00000 0x02018 RW  0x4
  LOAD           0x000978 0x24000000 0x08000760 0x00008 0x00008 RW  0x4
  LOAD           0x000980 0x24000008 0x24000008 0x00000 0x00038 RW  0x4
  LOAD           0x000980 0x30000000 0x30000000 0x00000 0x00400 RW  0x20
  LOAD           0x000980 0x38800000 0x38800000 0x00000 0x00004 RW  0x4
  LOAD           0x000980 0x08000768 0x08000768 0x00034 0x00034 RW  0x4
```

How to read it:

- Every `.itcm_text`, `.dtcm_data` and `.data` segment has **VirtAddr in RAM and PhysAddr in FLASH** (`0x08000748`, `0x08000758`, `0x08000760`). That is the `AT > FLASH` contract.
- The NOLOAD sections have `FileSiz 0`.
- `.dma_nc` is 32-byte aligned and sized in whole lines (asserted).
- `.msp_stack` spans `__msp_limit = 0x20000020` to `__msp_top = 0x20002020`, which is the reset SP below.
- LLD marks the data-command-only `.copy_table`/`.zero_table` output sections `WA` (writable). That's harmless, since flash is read-only to stores anyway.

**Cold boot (verified, Unicorn Cortex-M7, `--flash-only`, all RAM `0xA5`-filled):**

```
run 1: reset SP=0x20002020 PC=0x080000D9 -> stopped at 0x08000368 (h7_done)
  g_result@0x2400001C: 0x00000003 0xA11A11A1 0x00000000 0x00000001 0x00000021 0x30000200 0x38800000 0x20000008
  g_dtcm_init@0x20000000: 0xD7C30001 0xD7C30002
  watch VTOR    @0xE000ED08:    1 writes, last=0x08000000
  watch CCR     @0xE000ED14:    2 writes, last=0x00030200
  watch CPACR   @0xE000ED88:    1 writes, last=0x00F00000
  watch MPU_CTRL@0xE000ED94:    2 writes, last=0x00000005
  watch MPU_RBAR@0xE000ED9C:    8 writes, last=0x00000017
  watch MPU_RASR@0xE000EDA0:   16 writes, last=0x00000000
  watch ICIALLU @0xE000EF50:    1 writes, last=0x00000000
  watch DCISW   @0xE000EF60:  512 writes, last=0xC0000FE0
```

Clause by clause:

| Evidence | Meaning |
|---|---|
| `g_result[0] = 3` | `0xD7C30001 ^ 0xD7C30002`: DTCM `.dtcm_data` was copied from flash. |
| `g_result[1] = 0xA11A11A1` | AXI `.data` was copied. |
| `g_result[2] = 0` | Both zero-table entries ran (DTCM and AXI `.bss` were `0xA5` before). |
| `g_result[3] = 1`, `g_result[4] = 0x21` | The ITCM ISR was copied and executed from `0x20`, past the 32-byte NULL guard, via the thunk below. |
| `g_result[5] = 0x30000200`, `[6] = 0x38800000`, `[7] = 0x20000008` | The second ping-pong buffer is in D2 NC SRAM, the crash magic in backup SRAM, `g_dtcm_zero` in DTCM. |
| VTOR: 1 write, `0x08000000` | Vector table at the start of flash. |
| CPACR: 1 write, `0x00F00000` | CP10/CP11 full access, done first. |
| MPU_RBAR: 8 writes, last `0x17` | 8 regions, last = region 7 (VALID bit 4 set, base 0): the NULL guard. |
| MPU_RASR: 16 writes, last 0 | 8 programmed, plus regions 8–15 explicitly disabled (leftovers from a previous map, e.g. a bootloader's). |
| MPU_CTRL: 2 writes, last `0x5` | Disabled during reprogramming, then ENABLE + PRIVDEFENA. |
| ICIALLU: 1 write | I-cache invalidated before enable. |
| DCISW: 512 writes, last `0xC0000FE0` | 128 sets × 4 ways, exactly as computed in §1.3. |
| CCR: 2 writes, last `0x00030200` | STKALIGN (reset value) + IC + DC. |

**The flash → ITCM call (verified):**

```
main (flash) calls TIM2_IRQHandler (ITCM 0x00000021): BL range is +/-16 MB, distance is ~128 MB
  080003a0:  bl       #0x800068c
linker-generated thunk (<internal>:(.text.thunk), 10 bytes):
  0800068c:  movw     ip, #0x21
  08000690:  movt     ip, #0
  08000694:  bx       ip
```

**Codegen (verified — Clang 21.1.0, -O2, thumbv7em-none-eabihf, Cortex-M7), the complete linked `Reset_Handler`:**

```asm
Reset_Handler:
  080000d8:  movw     fp, #0xef60
  080000dc:  movw     r0, #0xfe28
  080000e0:  movt     fp, #0xe000
  080000e4:  movt     r0, #0xffff
  080000e8:  movw     ip, #0x78c
  080000ec:  ldr.w    r1, [fp, r0]
  080000f0:  movt     ip, #0x800
  080000f4:  orr      r1, r1, #0xf00000
  080000f8:  str.w    r1, [fp, r0]
  080000fc:  movw     r1, #0xfda8
  08000100:  movw     r0, #0
  08000104:  movt     r1, #0xffff
  08000108:  movt     r0, #0x800
  0800010c:  dsb      sy
  08000110:  isb      sy
  08000114:  str.w    r0, [fp, r1]
  08000118:  movw     r0, #0x768
  0800011c:  movt     r0, #0x800
  08000120:  dsb      sy
  08000124:  isb      sy
  08000128:  cmp      r0, ip
  0800012a:  bhs      #0x80001ac
  0800012c:  movw     r8, #0x768
  08000130:  movt     r8, #0x800
  08000134:  b        #0x8000140
  08000136:  nop      
  08000138:  add.w    r8, r8, #0xc
  0800013c:  cmp      r8, ip
  0800013e:  bhs      #0x80001ac
  08000140:  ldr.w    lr, [r8, #8]
  08000144:  cmp.w    lr, #0
  08000148:  beq      #0x8000138
  0800014a:  ldrd     r3, r2, [r8]
  0800014e:  lsrs.w   r5, lr, #2
  08000152:  mov.w    r0, #0
  08000156:  beq      #0x8000180
  08000158:  sub.w    r6, r0, r5, lsl #2
  0800015c:  movs     r5, #0
  0800015e:  nop      
  08000160:  adds     r7, r3, r5
  08000162:  adds     r1, r2, r5
  08000164:  ldr      r4, [r3, r5]
  08000166:  str      r4, [r2, r5]
  08000168:  ldr      r4, [r7, #4]
  0800016a:  str      r4, [r1, #4]
  0800016c:  subs     r0, #4
  0800016e:  ldr      r4, [r7, #8]
  08000170:  str      r4, [r1, #8]
  08000172:  cmp      r6, r0
  08000174:  add.w    r5, r5, #0x10
  08000178:  ldr      r4, [r7, #0xc]
  0800017a:  str      r4, [r1, #0xc]
  0800017c:  bne      #0x8000160
  0800017e:  rsbs     r0, r0, #0
  08000180:  ands     r7, lr, #3
  08000184:  beq      #0x8000138
  08000186:  cmp      r7, #1
  08000188:  ldr.w    r6, [r3, r0, lsl #2]
  0800018c:  str.w    r6, [r2, r0, lsl #2]
  08000190:  beq      #0x8000138
  08000192:  adds     r6, r0, #1
  08000194:  cmp      r7, #2
  08000196:  ldr.w    r7, [r3, r6, lsl #2]
  0800019a:  str.w    r7, [r2, r6, lsl #2]
  0800019e:  beq      #0x8000138
  080001a0:  adds     r0, #2
  080001a2:  ldr.w    r3, [r3, r0, lsl #2]
  080001a6:  str.w    r3, [r2, r0, lsl #2]
  080001aa:  b        #0x8000138
  080001ac:  movw     ip, #0x79c
  080001b0:  movw     r0, #0x78c
  080001b4:  movt     ip, #0x800
  080001b8:  movt     r0, #0x800
  080001bc:  cmp      r0, ip
  080001be:  bhs      #0x800021e
  080001c0:  movw     r1, #0x78c
  080001c4:  movs     r2, #0
  080001c6:  movt     r1, #0x800
  080001ca:  b        #0x80001d6
  080001cc:  nop      
  080001ce:  nop      
  080001d0:  adds     r1, #8
  080001d2:  cmp      r1, ip
  080001d4:  bhs      #0x800021e
  080001d6:  ldr      r0, [r1, #4]
  080001d8:  cmp      r0, #0
  080001da:  beq      #0x80001d0
  080001dc:  lsrs     r3, r0, #2
  080001de:  ldr.w    lr, [r1]
  080001e2:  mov.w    r5, #0
  080001e6:  beq      #0x8000202
  080001e8:  sub.w    r6, lr, #0x10
  080001ec:  sub.w    r3, r5, r3, lsl #2
  080001f0:  subs     r5, #4
  080001f2:  str      r2, [r6, #0x10]!
  080001f6:  cmp      r3, r5
  080001f8:  str      r2, [r6, #4]
  080001fa:  str      r2, [r6, #8]
  080001fc:  str      r2, [r6, #0xc]
  080001fe:  bne      #0x80001f0
  08000200:  rsbs     r5, r5, #0
  08000202:  ands     r0, r0, #3
  08000206:  beq      #0x80001d0
  08000208:  cmp      r0, #1
  0800020a:  str.w    r2, [lr, r5, lsl #2]
  0800020e:  beq      #0x80001d0
  08000210:  add.w    r3, lr, r5, lsl #2
  08000214:  cmp      r0, #2
  08000216:  str      r2, [r3, #4]
  08000218:  it       ne
  0800021a:  strne    r2, [r3, #8]
  0800021c:  b        #0x80001d0
  0800021e:  dsb      sy
  08000222:  isb      sy
  08000226:  bl       #0x8000338
  0800022a:  movw     ip, #0xfdb4
  0800022e:  dsb      sy
  08000232:  isb      sy
  08000236:  movs     r1, #0
  08000238:  str      r1, [fp, #-0x10]
  0800023c:  movt     ip, #0xffff
  08000240:  dsb      sy
  08000244:  isb      sy
  08000248:  movw     r8, #0x3fe0
  0800024c:  ldr.w    r0, [fp, ip]
  08000250:  orr      r0, r0, #0x20000
  08000254:  str.w    r0, [fp, ip]
  08000258:  movw     r0, #0xfe24
  0800025c:  dsb      sy
  08000260:  isb      sy
  08000264:  movt     r0, #0xffff
  08000268:  str.w    r1, [fp, r0]
  0800026c:  movw     r0, #0xfe20
  08000270:  movt     r0, #0xffff
  08000274:  dsb      sy
  08000278:  ldr.w    r0, [fp, r0]
  0800027c:  ubfx     sl, r0, #3, #0xa
  08000280:  add.w    r2, sl, #1
  08000284:  ubfx     sb, r0, #0xd, #0xf
  08000288:  and      r0, r2, #3
  0800028c:  bic      lr, r2, #3
  08000290:  b        #0x80002a0
  08000292:  nop      
  08000294:  nop      
  08000296:  nop      
  08000298:  cmp      r1, sb
  0800029a:  add.w    r1, r1, #1
  0800029e:  beq      #0x80002ee
  080002a0:  cmp.w    sl, #3
  080002a4:  and.w    r6, r8, r1, lsl #5
  080002a8:  blo      #0x80002cc
  080002aa:  add.w    r7, r6, #0x40000000
  080002ae:  add.w    r5, r6, #-0x80000000
  080002b2:  add.w    r3, r6, #-0x40000000
  080002b6:  mov      r2, lr
  080002b8:  subs     r2, #4
  080002ba:  str.w    r6, [fp]
  080002be:  str.w    r7, [fp]
  080002c2:  str.w    r5, [fp]
  080002c6:  str.w    r3, [fp]
  080002ca:  bne      #0x80002b8
  080002cc:  cmp      r0, #0
  080002ce:  beq      #0x8000298
  080002d0:  cmp      r0, #1
  080002d2:  str.w    r6, [fp]
  080002d6:  beq      #0x8000298
  080002d8:  cmp      r0, #2
  080002da:  add.w    r2, r6, #0x40000000
  080002de:  str.w    r2, [fp]
  080002e2:  beq      #0x8000298
  080002e4:  add.w    r2, r6, #-0x80000000
  080002e8:  str.w    r2, [fp]
  080002ec:  b        #0x8000298
  080002ee:  dsb      sy
  080002f2:  movw     r4, #0x748
  080002f6:  ldr.w    r0, [fp, ip]
  080002fa:  movt     r4, #0x800
  080002fe:  orr      r0, r0, #0x10000
  08000302:  str.w    r0, [fp, ip]
  08000306:  movw     r0, #0x748
  0800030a:  dsb      sy
  0800030e:  isb      sy
  08000312:  movt     r0, #0x800
  08000316:  cmp      r0, r4
  08000318:  bhs      #0x800032c
  0800031a:  subs     r5, r0, #4
  0800031c:  nop      
  0800031e:  nop      
  08000320:  ldr      r0, [r5, #4]!
  08000324:  blx      r0
  08000326:  adds     r0, r5, #4
  08000328:  cmp      r0, r4
  0800032a:  blo      #0x8000320
  0800032c:  bl       #0x8000370
  08000330:  wfi      
  08000332:  b        #0x8000330
```

Things to check in this listing:

- There is **no** `__aeabi_memcpy`/`memclr` call. The volatile copy loops were unrolled by four, but every access remains a real `ldr`/`str`.
- The only calls are `bl 0x8000338` (`board_mpu_init`), `blx r0` (constructors) and `bl 0x8000370` (`main`).
- Every system-register store is followed by `dsb sy; isb sy` (CPACR, VTOR, the post-copy barrier, the ICIALLU sequence, CCR.IC, CCR.DC). The DCISW loop is followed by a single `dsb sy` before the CCR.DC write.

**The cold-boot emulator** used for every run in this file and in Folder 02. It loads PT_LOAD segments at their **PhysAddr**, as a flash programmer does. With `--flash-only`, it keeps only bytes whose load address is in FLASH, simulating a power cycle. RAM is pre-filled with `0xA5`, and SCS registers start at their reset values plus `--poke`s. `--watch` counts writes to system registers.

```python
"""emu_m.py - load a Cortex-M ELF the way a flash programmer does (PT_LOAD at
p_paddr), then execute from the reset vector in Unicorn until a stop symbol.

usage: emu_m.py fw.elf stop_symbol [--warm N] [--dump sym:count ...] [--regions name=base:size ...]
RAM regions are pre-filled with 0xA5 so that missing zeroing/copying is visible.
"""
import sys
from elftools.elf.elffile import ELFFile
from unicorn import Uc, UcError, UC_ARCH_ARM, UC_MODE_THUMB, UC_MODE_MCLASS, UC_HOOK_MEM_UNMAPPED
from unicorn.arm_const import UC_ARM_REG_SP, UC_ARM_REG_PC, UC_CPU_ARM_CORTEX_M7

args = sys.argv[1:]
elf_path, stop_sym = args[0], args[1]
warm = 1
flash_only = False   # True = cold boot: only bytes stored in FLASH survive power-off
dumps = []
pokes = []
watches = {}
regions = {"FLASH": (0x08000000, 0x80000), "ITCM": (0x00000000, 0x4000),
           "SRAM": (0x20000000, 0x20000), "SCS": (0xE000E000, 0x1000)}
i = 2
while i < len(args):
    if args[i] == "--flash-only":
        flash_only = True; i += 1
    elif args[i] == "--warm":
        warm = int(args[i + 1]); i += 2
    elif args[i] == "--dump":
        dumps.append(args[i + 1]); i += 2
    elif args[i] == "--poke":                      # --poke 0xADDR=0xVALUE (preload a register)
        a, v = args[i + 1].split("="); pokes.append((int(a, 0), int(v, 0))); i += 2
    elif args[i] == "--watch":                     # --watch NAME=0xADDR (count writes, keep last)
        n, a = args[i + 1].split("="); watches[int(a, 0)] = [n, 0, None]; i += 2
    elif args[i] == "--regions":
        regions = {}
        i += 1
        while i < len(args) and not args[i].startswith("--"):
            name, rest = args[i].split("=")
            b, s = rest.split(":")
            regions[name] = (int(b, 0), int(s, 0)); i += 1
    else:
        raise SystemExit("bad arg " + args[i])

f = open(elf_path, "rb")
elf = ELFFile(f)
syms = {s.name: s["st_value"] for s in elf.get_section_by_name(".symtab").iter_symbols()}

uc = Uc(UC_ARCH_ARM, UC_MODE_THUMB | UC_MODE_MCLASS)
uc.ctl_set_cpu_model(UC_CPU_ARM_CORTEX_M7)
for name, (base, size) in regions.items():
    uc.mem_map(base, size)
    if name not in ("FLASH", "SCS"):            # RAM: power-on garbage; SCS: reset values (0 + --poke)
        uc.mem_write(base, b"\xA5" * size)
uc.mem_write(0xE000ED00, (0x411FC272).to_bytes(4, "little"))  # CPUID: Cortex-M7 r1p2
for a, v in pokes:
    uc.mem_write(a, (v & 0xFFFFFFFF).to_bytes(4, "little"))
from unicorn import UC_HOOK_MEM_WRITE
def on_watch(uc_, access, addr, size, value, data):
    w = watches.get(addr)
    if w is not None:
        w[1] += 1; w[2] = value & 0xFFFFFFFF
for a in watches:
    uc.hook_add(UC_HOOK_MEM_WRITE, on_watch, begin=a, end=a + 3)

for seg in elf.iter_segments():
    if seg["p_type"] == "PT_LOAD" and seg["p_filesz"]:
        fb, fs = regions["FLASH"]
        in_flash = fb <= seg["p_paddr"] < fb + fs
        if flash_only and not in_flash:
            print(f"  cold boot: segment for 0x{seg['p_vaddr']:08X} has LMA 0x{seg['p_paddr']:08X} outside FLASH -> lost at power-off")
            continue
        uc.mem_write(seg["p_paddr"], seg.data())          # program at LMA, like a flasher

def unmapped(uc_, access, addr, size, value, data):
    print(f"UNMAPPED access type={access} addr=0x{addr:08X} size={size}")
    return False
uc.hook_add(UC_HOOK_MEM_UNMAPPED, unmapped)

vec = elf.get_section_by_name(".isr_vector")["sh_addr"]
for run in range(1, warm + 1):
    sp = int.from_bytes(uc.mem_read(vec, 4), "little")
    pc = int.from_bytes(uc.mem_read(vec + 4, 4), "little")
    uc.reg_write(UC_ARM_REG_SP, sp)
    stop = syms[stop_sym] & ~1
    try:
        uc.emu_start(pc | 1, stop, timeout=2_000_000, count=2_000_000)
    except UcError as e:
        from unicorn.arm_const import UC_ARM_REG_LR
        print(f"run {run}: CPU stopped: {e} at PC=0x{uc.reg_read(UC_ARM_REG_PC):08X} LR=0x{uc.reg_read(UC_ARM_REG_LR):08X}")
        break
    print(f"run {run}: reset SP=0x{sp:08X} PC=0x{pc:08X} -> stopped at 0x{uc.reg_read(UC_ARM_REG_PC):08X} ({stop_sym})")
    for d in dumps:
        name, cnt = d.split(":")
        a = syms[name]
        words = [int.from_bytes(uc.mem_read(a + 4 * k, 4), "little") for k in range(int(cnt))]
        print(f"  {name}@0x{a:08X}: " + " ".join(f"0x{w:08X}" for w in words))
for a, (n, cnt, last) in sorted(watches.items()):
    print(f"  watch {n:<8s}@0x{a:08X}: {cnt:4d} writes, last=" + (f"0x{last:08X}" if last is not None else "-"))
```

Run it as: `PYTHONPATH=<pyelftools+unicorn> python emu_m.py h7.elf h7_done --flash-only --regions FLASH=0x08000000:0x200000 ITCM=0x0:0x10000 DTCM=0x20000000:0x20000 AXI=0x24000000:0x80000 D2=0x30000000:0x20000 BKP=0x38800000:0x1000 SCS=0xE000E000:0x1000 --poke 0xE000ED80=0x000FE019 --poke 0xE000ED14=0x00000200 --watch VTOR=0xE000ED08 … --dump g_result:8`.

---

## 3. Hardware Debugging and Post-Mortem Diagnostics

| Symptom | Mechanism | Tooling |
|---|---|---|
| Works under the debugger, HardFaults after a power cycle; fault in an ITCM/RAM function | A RAM section with LMA == VMA (§2.1): the debugger wrote it, the flasher never did | `readelf -l`: every PT_LOAD with `FileSiz > 0` must have PhysAddr in flash. Trace32 `Data.LOAD.Elf` loads everything (hiding it); test with `FLASH.ReProgram` + power cycle. Add a CI check on the program headers |
| HardFault at the first FP instruction, `CFSR.UFSR.NOCP = 1` (`CFSR = 0x00080000`), with `HFSR.FORCED = 1` | FPU not enabled yet (CPACR late, or missing ISB) | Read CFSR/HFSR at `0xE000ED28`/`0xE000ED2C`; disassemble crt0 for `vldr/vstr/vmov` before the CPACR write |
| Random corruption right after enabling the D-cache; differs board to board | Cache enabled without invalidation (random tags valid) | Single-step the cache enable; check for ICIALLU/DCISW writes before `CCR.DC` (the trace counts in §2.2) |
| DMA data stale only for the first transfer after boot | Caches enabled before the MPU: lines allocated under the default WB map | Check the Reset_Handler order; dump MPU regions with `MPU_RNR`/`RBAR`/`RASR` in the debugger |
| NULL dereference returns plausible data instead of faulting | Code or data mapped at address 0 with no guard | Add a 32-byte no-access region at 0; expect `CFSR.MMARVALID` and `MMFAR = 0x00000000 + offset` |
| `.noinit` crash record always empty after reset | Section placed inside `.bss`, or the backup domain not write-enabled/clocked | Map file: its address must be outside every zero-table entry; check `PWR` backup-domain bits ⚠ verify |
| HardFault on the first interrupt, stacked PC = garbage | VTOR not set, or vector table misaligned | Read `VTOR` (`0xE000ED08`) and the table base; the linker ASSERT on alignment |
| Stack overflow silently corrupts DTCM data | MSP region not guarded | `.msp_stack` is first in DTCM after the hot data. On v8-M, set `MSPLIM = __msp_limit`; on v7-M, add an MPU guard region (Folder 02 File 03) |

**JTAG/SWD bring-up checklist** (OpenOCD or Trace32):

- `reset halt`, then read `0x08000000`/`0x08000004`: the initial SP and the reset PC (Thumb bit set).
- Break at `main` and compare a word of ITCM and DTCM against the ELF.
- Power-cycle the board (not a debugger reset) and repeat. Only this catches LMA bugs.

---

## 4. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "Your M7 firmware passes every debugger session but HardFaults in the field after a power cycle. Where do you look first?"

- **L5:** "Probably a brown-out or a stack overflow; increase the stack and add a BOR threshold."
- **Why L5 fails on real hardware:** The decisive clue is *debugger-loaded vs flash-only*. A debugger writes every ELF segment wherever its PhysAddr says, including RAM. A power cycle only preserves flash. Any RAM-resident section (ITCM code, initialized TCM data) whose LMA was never placed in flash works on the bench and is garbage in the field.
- **L7 principal defense:**
  - Check `readelf -l` program headers: every loadable segment with file bytes must have its PhysAddr in flash. The verified buggy image shows the ITCM segment at PhysAddr 0.
  - Reproduce with a real power cycle, or an emulator cold boot as in §2.1: the same objects boot under "download" and run off the end of ITCM after "power-off".
  - Fix the script (`> ITCM AT > FLASH`) and generate the crt0 work list from the linker script (copy/zero tables).
  - Make it unrepeatable: a CI check on the program headers, and linker ASSERTs on LMAs.

### Q2 "Why does it matter whether the MPU or the D-cache is enabled first?"

- **L5:** "It doesn't; both are set up before `main`."
- **Why L5 fails:** Under the ARMv7-M default memory map, the SRAM range `0x2000_0000–0x3FFF_FFFF` is Normal write-back write-allocate. Enable the D-cache first and any access to the future DMA region can allocate lines. When the MPU later marks it Non-cacheable, ARMv7-M requires software maintenance for lines allocated under the old attributes. Without that maintenance, whether a stale line can still be hit or written back is outside what the architecture guarantees.
- **L7 defense:**
  - MPU first, then invalidate and enable the caches. The verified trace shows the MPU writes complete before ICIALLU and DCISW.
  - If attributes must ever change at run time: disable the MPU, clean and invalidate the affected range by address, reprogram, then `DSB; ISB`.

### Q3 🔥 "Walk me through enabling the Cortex-M7 D-cache. Why set/way, why with the cache off, and how many operations?"

- **L5:** "Call `SCB_EnableDCache()`."
- **Why L5 fails:** At L7 you must know what it does and when it is wrong.
  - Cache RAM powers up random; valid bits may be set.
  - An invalidate by set/way discards *dirty* lines. With the cache on, that loses data, and for a shared L2 it is never correct on Cortex-A SMP (Folder 03 File 03).
- **L7 defense:**
  - Select L1-D with `CSSELR = 0` and DSB, then read `CCSIDR` (sets = `[27:13] + 1`, ways = `[12:3] + 1`, line = `2^([2:0] + 4)` bytes).
  - Write `DCISW = (set << 5) | (way << 30)` for each of 128 × 4 = **512** set/way pairs on a 16 KB cache (verified: 512 writes, last `0xC0000FE0`). Then `DSB`, set `CCR.DC`, then `DSB; ISB`.
  - Do it once, in crt0, with the cache off.
  - Run time uses **by-address** clean/invalidate (DCCMVAC/DCIMVAC) only.

### Q4 "What is a range-extension thunk, and when does it bite you in embedded code?"

- **L5:** "A linker detail."
- **Why L5 fails:** It changes timing and safety.
  - Flash code calling an ITCM ISR helper goes through a thunk in flash. The "zero-wait-state" call path now includes a flash fetch: verified, `main` → `bl 0x800068c` → `movw/movt ip; bx ip`.
  - ITCM code calling flash code incurs flash wait states and I-cache misses: the determinism you paid for is gone.
  - Thunks clobber `ip` (r12, allowed by AAPCS). Hand-written asm that keeps a live value in r12 across a `bl` breaks.
- **L7 defense:**
  - Keep ITCM functions leaf-like and `noinline`, and place their callees in ITCM too.
  - Check the map file for `<internal>:(.text.thunk)` entries.
  - Use `long_call` where the toolchain does not generate veneers.

### Q5 "Your crash record in a `.noinit` section is always zero after a watchdog reset. Why?"

- **L5:** "The watchdog clears RAM."
- **Why L5 fails:** Watchdog resets don't clear SRAM. Your crt0 did. Common causes:
  - `.noinit` was matched by a `*(.bss*)` pattern, or placed in a region covered by the zero table.
  - On a part with ECC SRAM, the boot ROM or crt0 performs ECC scrubbing (a zero-fill) of that bank.
  - The backup domain was never write-enabled.
- **L7 defense:**
  - Put the record in its own NOLOAD output section, in a region that no zero/copy entry touches (backup SRAM here). Verify in the map.
  - Validate it with magic + CRC on boot, since power-on contents are random.
  - Clear the magic only after the record has been reported (File 04).

---

## 5. Invariants Checklist

- [ ] Every RAM-resident section that has contents uses `> RAM AT > FLASH`. CI asserts that every PT_LOAD segment with `FileSiz > 0` has PhysAddr inside flash.
- [ ] crt0 walks linker-generated copy and zero tables. No region-specific symbols in C.
- [ ] Copy and zero loops use `volatile` (or hand-written asm), so there are no libcalls before RAM is valid. Verify in the listing.
- [ ] Order: CPACR → VTOR → copy/zero → `DSB; ISB` → MPU → I-cache (invalidate, enable) → D-cache (invalidate by set/way with the cache off, enable) → constructors → `main`.
- [ ] Every system-register write that later code depends on is followed by `DSB; ISB`.
- [ ] DMA buffers and descriptors in an MPU Normal-NC region whose sections are line-aligned and line-sized (asserted).
- [ ] A 32-byte no-access MPU region at address 0 when anything is mapped there; code starts at `ORIGIN + 32`.
- [ ] `.noinit`/crash records: NOLOAD, outside every zero-table entry, validated by magic + CRC.
- [ ] MSP stack bounded: `MSPLIM` (v8-M) or an MPU guard region (v7-M).
- [ ] Vector table alignment asserted (a power of two ≥ table size); MPU leftovers (unused regions) explicitly disabled.
- [ ] Bring-up verified after a **real power cycle**, not only after a debugger download.

## 6. References

1. Arm, *ARMv7-M Architecture Reference Manual* (DDI 0403E): B1.5.3 vector table and VTOR alignment, B3.2.8 CCR, B3.2.20 CPACR, B3.5 PMSAv7 (region priority, default memory map, attribute changes), A3.5 memory types.
2. Arm, *Cortex-M7 Processor Technical Reference Manual* (DDI 0489): L1 cache organization, CCSIDR/CSSELR, ICIALLU/DCISW, TCM interfaces and the AHBS port.
3. Arm, *AN321: Cortex-M Programming Guide to Memory Barrier Instructions*: DSB/ISB after VTOR, MPU and CCR changes.
4. Arm CMSIS-Core, `core_cm7.h`: `SCB_EnableICache`, `SCB_EnableDCache`, `SCB_InvalidateDCache_by_Addr`.
5. STMicroelectronics, *RM0433* (STM32H742/743/750/753 reference manual): memory map, TCM and AXI SRAM, D2 SRAM, backup SRAM and the backup domain (⚠ verify for your exact part).
6. LLVM LLD documentation: linker-script support (`AT>`, `NOLOAD`, `LOADADDR`, `ASSERT`) and Arm range-extension thunks.
7. Folder 02 File 02 (crt0, LMA bugs, loop-idiom libcalls), Folder 02 File 03 (PMSAv7 encoder), Folder 03 File 03 (DMA cache maintenance), Folder 04 File 01 (ITCM ISRs and latency).
